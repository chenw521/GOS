#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/config.cjs#fn:loadConfig bin/lib/ops/config.cjs#fn:saveConfig bin/lib/knowledge/lessons-json.cjs#fn:migrateLegacy
# gos-map:cmd config,resolve-model,lessons
# T87: config two-layer system + sentinel deletion + genesis guards (P1 D-09, R-31)
# Covers: global-base/project-overlay merge precedence, models deep-merge,
#         corrupt-layer quarantine+die, missing-global empty base, saveConfig-only
#         one-time lessons_migrated strip (loadConfig never writes), layer-separating
#         project writes, project git-log genesis guard, global migration-backup
#         genesis guard, resume-heal md-regeneration-only semantics
# Env: GOS (CLI path), TESTBASE (isolated base), assert helpers sourced by runner.
#      Direct invocation self-bootstraps the same environment.
# ALL global-path assertions use fake-HOME (HOME=$T87_HOME) [R3-F7]
T87_DIR=""
T87_HOME=""

t87_setup() {
  T87_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t87"
  mkdir -p "$T87_DIR" && cd "$T87_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
  T87_HOME="$T87_DIR/home"
  mkdir -p "$T87_HOME"
}

t87_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T87_DIR"; }

t87_g() { HOME="$T87_HOME" node "$GOS" "$@"; }

# node helper against the CLI's own modules (fixture fabrication with VALID
# ids/hashes — never hand-rolled bytes)
t87_node() { HOME="$T87_HOME" node -e "$1"; }

# write a JSON file with python (keeps fixtures explicit)
t87_json() { python3 -c "
import json, sys, os
p = sys.argv[1]; obj = json.loads(sys.argv[2])
os.makedirs(os.path.dirname(p) or '.', exist_ok=True)
json.dump(obj, open(p, 'w'), indent=2)
" "$1" "$2"; }

# --- self-bootstrap: allow direct `bash test/sections/T87-*.test.sh` runs ---
T87_SELF=0
if [ -z "${GOS:-}" ]; then
  T87_SELF=1
  GOS_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  GOS="$GOS_ROOT/bin/gos.cjs"
  TESTBASE="$(mktemp -d "$GOS_ROOT/test-sections-base-XXXXXX")"
  export GOS GOS_ROOT TESTBASE
  export HOME="$TESTBASE/home"; mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
  assert_contains() {
    local label="$1" expected="$2" actual="$3"
    if [ -z "$expected" ]; then echo "  ✗ $label (empty pattern always matches)"; FAIL=$((FAIL+1))
    elif echo "$actual" | grep -q "$expected"; then echo "  ✓ $label"; PASS=$((PASS+1))
    else echo "  ✗ $label (expected: '$expected')"; echo "    actual: ${actual:0:160}"; FAIL=$((FAIL+1)); fi
  }
  assert_exit() {
    local label="$1" expected="$2" actual="$3"
    if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then echo "  ✓ $label (exit $actual)"; PASS=$((PASS+1))
    else echo "  ✗ $label (expected exit $expected, got '${actual:-<none>}')"; FAIL=$((FAIL+1)); fi
  }
  assert_file() {
    local label="$1" fpath="$2"
    if [ -n "$fpath" ] && [ -e "$fpath" ]; then echo "  ✓ $label"; PASS=$((PASS+1))
    else echo "  ✗ $label (missing: '${fpath:-<none>}')"; FAIL=$((FAIL+1)); fi
  }
  assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then echo "  ✓ $label"; PASS=$((PASS+1))
    else echo "  ✗ $label (expected: '$expected', got: '$actual')"; FAIL=$((FAIL+1)); fi
  }
  PASS=0; FAIL=0
fi

t87_setup
echo "--- T87: config two-layer + sentinel deletion + genesis guards ---"

t87_g init 1 "t87 config two-layer fixture" >/dev/null 2>&1

# --- T87.0: fake-HOME sanity ---
if [ -e "$HOME/.config/gos/config.json" ] || [ -e "$HOME/.config/gos/lessons.json" ]; then
  echo "  ✗ REAL HOME polluted before test"; FAIL=$((FAIL+1))
else
  echo "  ✓ real HOME clean before test"; PASS=$((PASS+1))
fi

# --- T87.1: two-layer merge precedence — scalars project-wins, deep-merged models ---
t87_json "$T87_HOME/.config/gos/config.json" '{"model_profile":"team","models":{"planner":"zai/glm-5.3"},"locale":"en","lessons_migrated":true}'
t87_json ".gos/config.json" '{"model_profile":"solo","models":{"checker":"glm-5.3flash"},"lessons_migrated":true}'
OUT=$(t87_g config models show 2>&1); RC=$?
assert_exit "merged config loads (both layers present)" "0" "$RC"
MERGED=$(printf '%s\n' "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['model_profile'], d['models'].get('planner'), d['models'].get('checker'))")
assert_eq "scalar: project model_profile wins over global" "solo zai/glm-5.3 glm-5.3flash" "$MERGED"

# --- T87.2: missing global layer = legal empty base (defaults apply) ---
T87_HOME2="$T87_DIR/home2"; mkdir -p "$T87_HOME2"
T87_PLAIN="$T87_DIR/nogos"; mkdir -p "$T87_PLAIN" && cd "$T87_PLAIN" || exit 1
OUT=$(HOME="$T87_HOME2" node "$GOS" resolve-model checker 2>&1); RC=$?
assert_exit "missing global layer is a legal empty base" "0" "$RC"
assert_contains "defaults apply when both layers absent" '"profile":"team"' "$OUT"
cd "$T87_DIR" || exit 1

# --- T87.3: corrupt project layer → quarantine rename + die ---
T87_CORRUPT="$T87_DIR/test-corrupt-proj"
mkdir -p "$T87_CORRUPT/.gos" && (cd "$T87_CORRUPT" && git init -q . && git commit -q --allow-empty -m root) || exit 1
(cd "$T87_CORRUPT" && HOME="$T87_HOME" node "$GOS" init 1 "t87 corrupt-proj fixture" >/dev/null 2>&1)
printf '{corrupt\n' > "$T87_CORRUPT/.gos/config.json"
OUT=$(cd "$T87_CORRUPT" && HOME="$T87_HOME" node "$GOS" config models show 2>&1); RC=$?
assert_exit "corrupt project layer fails closed" "1" "$RC"
assert_contains "die names the project layer" "project layer" "$OUT"
if ls "$T87_CORRUPT/.gos/config.json.corrupt-"* >/dev/null 2>&1 && [ ! -f "$T87_CORRUPT/.gos/config.json" ]; then
  echo "  ✓ corrupt project layer renamed .corrupt-<ts> (original gone)"; PASS=$((PASS+1))
else
  echo "  ✗ corrupt project layer quarantine failed"; FAIL=$((FAIL+1))
fi
OUT=$(cd "$T87_CORRUPT" && HOME="$T87_HOME" node "$GOS" config models show 2>&1); RC=$?
assert_exit "post-quarantine command works (missing layer = defaults)" "0" "$RC"

# --- T87.4: corrupt global layer → quarantine rename + die ---
T87_HOME3="$T87_DIR/home3"; mkdir -p "$T87_HOME3/.config/gos"
printf '{corrupt\n' > "$T87_HOME3/.config/gos/config.json"
OUT=$(HOME="$T87_HOME3" node "$GOS" config models show 2>&1); RC=$?
assert_exit "corrupt global layer fails closed" "1" "$RC"
assert_contains "die names the global layer" "global layer" "$OUT"
if ls "$T87_HOME3/.config/gos/config.json.corrupt-"* >/dev/null 2>&1 && [ ! -f "$T87_HOME3/.config/gos/config.json" ]; then
  echo "  ✓ corrupt global layer renamed .corrupt-<ts> (original gone)"; PASS=$((PASS+1))
else
  echo "  ✗ corrupt global layer quarantine failed"; FAIL=$((FAIL+1))
fi

# --- T87.5: saveConfig-only one-time lessons_migrated strip (loadConfig never writes) ---
# read-only command first: the key must SURVIVE (loadConfig never writes)
OUT=$(t87_g resolve-model checker 2>&1); RC=$?
assert_exit "read command under sentinel-carrying layers" "0" "$RC"
if python3 -c "import json; assert json.load(open('.gos/config.json')).get('lessons_migrated') is True and json.load(open('$T87_HOME/.config/gos/config.json')).get('lessons_migrated') is True" 2>/dev/null; then
  echo "  ✓ loadConfig never writes (sentinel intact after read)"; PASS=$((PASS+1))
else
  echo "  ✗ loadConfig wrote (sentinel stripped by a read)"; FAIL=$((FAIL+1))
fi
# first write: strip from BOTH layers with a notice
OUT=$(t87_g config models profile elite 2>&1); RC=$?
assert_exit "first saveConfig succeeds" "0" "$RC"
assert_contains "strip notice names the obsolete key" "lessons_migrated" "$OUT"
if python3 -c "
import json
p = json.load(open('.gos/config.json')); g = json.load(open('$T87_HOME/.config/gos/config.json'))
assert 'lessons_migrated' not in p and 'lessons_migrated' not in g, 'sentinel survived'
assert p.get('model_profile') == 'elite' and g.get('models', {}).get('planner') == 'zai/glm-5.3', 'strip lost keys'
" 2>/dev/null; then
  echo "  ✓ one-time strip removed the key from BOTH layers (other keys intact)"; PASS=$((PASS+1))
else
  echo "  ✗ both-layer strip failed or lost keys"; FAIL=$((FAIL+1))
fi
# second write: no notice (one-time)
OUT=$(t87_g config models profile solo 2>&1); RC=$?
assert_exit "second saveConfig succeeds" "0" "$RC"
if printf '%s' "$OUT" | grep -q "lessons_migrated"; then
  echo "  ✗ strip notice repeated (not one-time)"; FAIL=$((FAIL+1))
else
  echo "  ✓ strip is one-time (no notice on second write)"; PASS=$((PASS+1))
fi

# --- T87.6: layer-separating project write — deep-merge survives, global pins not copied ---
if python3 -c "
import json
p = json.load(open('.gos/config.json'))
assert p.get('models', {}).get('checker') == 'glm-5.3flash', 'project pin lost'
assert 'planner' not in p.get('models', {}), 'global-inherited pin leaked into project layer'
assert p.get('locale') is None, 'global-inherited scalar leaked into project layer'
" 2>/dev/null; then
  echo "  ✓ project write keeps only project-owned keys (no global leak)"; PASS=$((PASS+1))
else
  echo "  ✗ project layer absorbed global-owned values"; FAIL=$((FAIL+1))
fi
OUT=$(t87_g config models show 2>&1)
assert_contains "merged view still exposes global planner pin after save" '"planner": "zai/glm-5.3"' "$OUT"

# --- T87.7: resolve-model under pinned fixture env (HOME + OPENCODE_CONFIG_DIR) ---
T87_FIX="$T87_DIR/ocfix"; mkdir -p "$T87_FIX"
t87_json "$T87_FIX/opencode.json" '{"provider":{"zai":{"models":{"glm-5.3":{"name":"glm-5.3"},"glm-5.3flash":{"name":"glm-5.3flash"}}}}}'
OUT=$(HOME="$T87_FIX" OPENCODE_CONFIG_DIR="$T87_FIX" node "$GOS" resolve-model checker 2>&1); RC=$?
assert_exit "resolve-model checker (pinned) under fixture env" "0" "$RC"
if printf '%s' "$OUT" | grep -Eq '"model":"[^"]*glm-5\.3'; then
  echo "  ✓ pinned checker resolves to a glm-5.3-family model"; PASS=$((PASS+1))
else
  echo "  ✗ pinned checker not glm-5.3-family: $OUT"; FAIL=$((FAIL+1))
fi
# probe path (no project pin): tier resolution must come from the fixture opencode.json
T87_PROBE="$T87_DIR/probe"; mkdir -p "$T87_PROBE/.gos" && (cd "$T87_PROBE" && git init -q . && git commit -q --allow-empty -m root) || exit 1
OUT=$(cd "$T87_PROBE" && HOME="$T87_FIX" OPENCODE_CONFIG_DIR="$T87_FIX" node "$GOS" resolve-model checker 2>&1); RC=$?
assert_exit "resolve-model checker (probed) under fixture env" "0" "$RC"
if printf '%s' "$OUT" | grep -Eq '"model":"[^"]*glm-5\.3'; then
  echo "  ✓ probed checker resolves to a glm-5.3-family model"; PASS=$((PASS+1))
else
  echo "  ✗ probed checker not glm-5.3-family: $OUT"; FAIL=$((FAIL+1))
fi
# tracked repo pin: run from GOS_ROOT with fixture env (read-only command)
OUT=$(cd "$GOS_ROOT" && HOME="$T87_FIX" OPENCODE_CONFIG_DIR="$T87_FIX" node "$GOS" resolve-model checker 2>&1); RC=$?
assert_exit "repo resolve-model checker under fixture env" "0" "$RC"
if printf '%s' "$OUT" | grep -Eq '"model":"[^"]*glm-5\.3flash'; then
  echo "  ✓ repo tracked pin is glm-5.3flash"; PASS=$((PASS+1))
else
  echo "  ✗ repo pin not glm-5.3flash: $OUT"; FAIL=$((FAIL+1))
fi

# --- T87.8: project genesis guard — git history carries lessons.json → restore, don't remigrate ---
T87_GEN="$T87_DIR/test-genesis-proj"
mkdir -p "$T87_GEN" && cd "$T87_GEN" || exit 1
git init -q . && git commit -q --allow-empty -m root
printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
HOME="$T87_HOME" node "$GOS" init 1 "t87 genesis" >/dev/null 2>&1
HOME="$T87_HOME" node "$GOS" lessons add --type project --scene "g" --lesson "genesis seed entry" >/dev/null 2>&1
git add .gos/lessons.json && git commit -q -m "lessons: seed truth"
rm -f .gos/lessons.json
OUT=$(HOME="$T87_HOME" node "$GOS" lessons add --type project --scene "g2" --lesson "after delete" 2>&1); RC=$?
assert_exit "deleted-but-committed json refuses bootstrap" "1" "$RC"
if printf '%s' "$OUT" | grep -Fq "restore, don't remigrate"; then
  echo "  ✓ genesis guard says restore, don't remigrate"; PASS=$((PASS+1))
else
  echo "  ✗ genesis guard message wrong: $OUT"; FAIL=$((FAIL+1))
fi
cd "$T87_DIR" || exit 1

# --- T87.9: global genesis guard — migration backup witness → restore, don't remigrate ---
T87_HOMEG="$T87_DIR/homeg"; mkdir -p "$T87_HOMEG/.config/gos"
printf -- '- [2026-01-01] [model] legacy global line\n' > "$T87_HOMEG/.config/gos/lessons-migration-backup-2026-01-01.md"
OUT=$(HOME="$T87_HOMEG" node "$GOS" lessons add --type model --scene "gg" --lesson "global genesis probe" 2>&1); RC=$?
assert_exit "global json missing + migration backup present refuses bootstrap" "1" "$RC"
if printf '%s' "$OUT" | grep -Fq "restore, don't remigrate"; then
  echo "  ✓ global backup guard says restore, don't remigrate"; PASS=$((PASS+1))
else
  echo "  ✗ global backup guard message wrong: $OUT"; FAIL=$((FAIL+1))
fi
# truth-bak is the same class of witness (a store existed)
rm -f "$T87_HOMEG/.config/gos/lessons-migration-backup-2026-01-01.md"
printf '{"schema_version":2,"entries":[],"audit":[],"chain_head":"GENESIS"}\n' > "$T87_HOMEG/.config/gos/.lessons.json.bak"
OUT=$(HOME="$T87_HOMEG" node "$GOS" lessons add --type model --scene "gg" --lesson "bak witness probe" 2>&1); RC=$?
assert_exit "global json missing + truth-bak present refuses bootstrap" "1" "$RC"
if printf '%s' "$OUT" | grep -Fq "restore, don't remigrate"; then
  echo "  ✓ truth-bak witness also refuses remigration"; PASS=$((PASS+1))
else
  echo "  ✗ truth-bak witness not honored: $OUT"; FAIL=$((FAIL+1))
fi
# witnesses cleared → fresh bootstrap legal
rm -f "$T87_HOMEG/.config/gos/.lessons.json.bak"
OUT=$(HOME="$T87_HOMEG" node "$GOS" lessons add --type model --scene "gg" --lesson "fresh global entry" 2>&1); RC=$?
assert_exit "global fresh bootstrap legal once witnesses cleared" "0" "$RC"

# --- T87.10: resume-heal = md regeneration only, after chain verification ---
T87_RES="$T87_DIR/test-resume"
mkdir -p "$T87_RES/.gos/cache" && cd "$T87_RES" || exit 1
git init -q . && git commit -q --allow-empty -m root
t87_node '
const j = require(process.env.GOS_ROOT + "/bin/lib/knowledge/lessons-json.cjs");
const fs = require("fs");
const P = { truth: ".gos/lessons.json", anchor: ".gos/cache/.lessons-anchors.json", file: ".gos/lessons.md", global: false };
const store = j.emptyStore();
const base = { at: "2026-10-01", type: "project", scene: "resume", lesson: "resume-heal probe entry", tags: [], origin: "v2" };
const { id } = j.mintId(base, () => false);
store.entries.push({ id, ...base });
j.appendAuditRow(store, "add", "fixture", { new_id: id });
j.saveStore(P, store);
fs.writeFileSync(".t87-sidecar-before", fs.readFileSync(P.anchor, "utf8"));
// (a) hand-mangled md view → resume-heal regenerates md ONLY (chain verified)
fs.writeFileSync(P.file, "# hand-edited lessons view\n- not a generated file\n");
const r1 = j.migrateLegacy(P, { quiet: true });
fs.writeFileSync(".t87-a", JSON.stringify({ already: r1.already, header: fs.readFileSync(P.file, "utf8").startsWith("<!-- gos:generated"), sidecarSame: fs.readFileSync(P.anchor, "utf8") === fs.readFileSync(".t87-sidecar-before", "utf8") }));
// (b) hand-deleted entry (sidecar stale = the witness) → heal must NOT rewrite the sidecar
const s2 = JSON.parse(fs.readFileSync(P.truth, "utf8"));
s2.entries = [];
fs.writeFileSync(P.truth, JSON.stringify(s2, null, 2) + "\n");
fs.writeFileSync(P.file, "# hand-edited again\n");
const r2 = j.migrateLegacy(P, { quiet: true });
const res2 = j.loadStore(P);
fs.writeFileSync(".t87-b", JSON.stringify({ already: r2.already, sidecarSame: fs.readFileSync(P.anchor, "utf8") === fs.readFileSync(".t87-sidecar-before", "utf8"), violations: res2.failures.length > 0 }));
// (c) chain-broken json + mangled md → heal must NOT regenerate the md
const s3 = JSON.parse(fs.readFileSync(P.truth, "utf8"));
if (s3.audit.length) s3.audit[0].why = (s3.audit[0].why || "x") + "TAMPER";
fs.writeFileSync(P.truth, JSON.stringify(s3, null, 2) + "\n");
fs.writeFileSync(P.file, "# hand-edited unverified\n");
const r3 = j.migrateLegacy(P, { quiet: true });
fs.writeFileSync(".t87-c", JSON.stringify({ already: r3.already, mdUntouched: fs.readFileSync(P.file, "utf8") === "# hand-edited unverified\n" }));
'
if python3 -c "
import json
a = json.load(open('.t87-a'))
assert a['already'] is True and a['header'] is True and a['sidecarSame'] is True, a
" 2>/dev/null; then
  echo "  ✓ resume-heal regenerates md only (sidecar untouched)"; PASS=$((PASS+1))
else
  echo "  ✗ resume-heal md/sidecar semantics wrong: $(cat .t87-a 2>/dev/null)"; FAIL=$((FAIL+1))
fi
if python3 -c "
import json
b = json.load(open('.t87-b'))
assert b['sidecarSame'] is True and b['violations'] is True, b
" 2>/dev/null; then
  echo "  ✓ stale sidecar kept as witness (deletion still detected)"; PASS=$((PASS+1))
else
  echo "  ✗ stale sidecar healed (witness laundered): $(cat .t87-b 2>/dev/null)"; FAIL=$((FAIL+1))
fi
if python3 -c "
import json
c = json.load(open('.t87-c'))
assert c['already'] is True and c['mdUntouched'] is True, c
" 2>/dev/null; then
  echo "  ✓ chain-broken json never heals the md view"; PASS=$((PASS+1))
else
  echo "  ✗ unverified json healed the md: $(cat .t87-c 2>/dev/null)"; FAIL=$((FAIL+1))
fi
cd "$T87_DIR" || exit 1

t87_teardown
if [ "$T87_SELF" = "1" ]; then
  rm -rf "$TESTBASE"
  [ "$FAIL" -eq 0 ] && exit 0 || exit 1
fi
