#!/usr/bin/env bash
# gos-map:file .gos/ai-trace-whitelist.json
# gos-map:file test/fixtures/ai-trace/anchors.json
# gos-map:file test/fixtures/ai-trace/anchors.sh
# gos-map:file test/fixtures/ai-trace/anchors.md
# ai-trace lint boundary — planted fixtures lint red in a scratch repo,
# the tracked tree stays green, whitelist equality binds in both directions,
# ghost and regen guards fire, gate all blocks on a planted anchor, templates
# stay clean and the coding hint renders in both locales.
# Cases: A scratch red, B tracked green, C and D equality, E ghost,
# F regen, G gate, H templates, I hints.
T102_DIR=""
LINT="$GOS_ROOT/test/checks/ai-trace-lint.sh"

t102_scratch() { # name — fresh git repo dir inside this section sandbox
  local d="$T102_DIR/$1"
  mkdir -p "$d" || exit 1
  git init -q "$d" 2>/dev/null
  printf '%s' "$d"
}

# One tier A bracket marker per comment line; the digit is computed at
# runtime so the spellings in this file never match the lint grammar itself.
t102_seed() { # file count
  : > "$1"
  local i
  for ((i = 1; i <= $2; i++)); do
    printf '// [%s %d] seeded tier A marker\n' "REVIEW M" "$((4000 + i))" >> "$1"
  done
}

t102_wl() { # dir category maxHits path — single-entry scratch whitelist
  mkdir -p "$1/.gos"
  node -e '
    const fs = require("fs");
    const e = { path: process.argv[1], category: process.argv[2], maxHits: Number(process.argv[3]),
      reason: "synthetic scratch whitelist entry for the boundary probe" };
    fs.writeFileSync(process.argv[4], JSON.stringify([e], null, 2) + "\n");
  ' "$4" "$2" "$3" "$1/.gos/ai-trace-whitelist.json"
}

t102_verdict() { # outfile ids...
  local out="$1"; shift
  for c in "$@"; do
    if grep -q "^$c-OK$" "$out"; then echo "  ✓ $c machine verdict"; PASS=$((PASS+1));
    else echo "  ✗ $c machine verdict: $(grep "^$c-" "$out" | head -1)"; FAIL=$((FAIL+1)); fi
  done
}

t102_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T102_DIR"; }

PASS=0; FAIL=0
echo "--- T102: ai-trace lint boundary evidence ---"
T102_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t102"
mkdir -p "$T102_DIR" || exit 1

# ===== A: scratch repo, fixtures unregistered — every hit is a violation =====
RED="$(t102_scratch red)"
mkdir -p "$RED/test/fixtures/ai-trace"
cp "$GOS_ROOT"/test/fixtures/ai-trace/* "$RED/test/fixtures/ai-trace/"
(cd "$RED" && git add -A)
set +e; (cd "$RED" && bash "$LINT" --json) > "$T102_DIR/red.json" 2>"$T102_DIR/red.err"; RC=$?; set -e
assert_exit "A1 scratch red lint exit" 1 "$RC"
node -e '
const v = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const fx = v.filter((x) => x.path.startsWith("test/fixtures/ai-trace/"));
const a2 = v.length === 10 && fx.length === 10 &&
  v.every((x) => x.type === "ai-trace-unregistered" && (x.tier === "A" || x.tier === "B")) &&
  v.filter((x) => x.tier === "A").length === 4 && v.filter((x) => x.tier === "B").length === 6;
const md = fx.filter((x) => x.path.endsWith(".md"));
const a3 = md.length === 3;
console.log(a2 ? "A2-OK" : "A2-FAIL got " + v.length + " record(s)");
console.log(a3 ? "A3-OK" : "A3-FAIL md record(s) " + md.length);
' "$T102_DIR/red.json" > "$T102_DIR/a.out" 2>&1 || true
t102_verdict "$T102_DIR/a.out" A2 A3

# ===== B: tracked tree — fixture registration is permanent, lint stays green =====
set +e; (cd "$GOS_ROOT" && bash test/checks/ai-trace-lint.sh) > "$T102_DIR/green.out" 2>&1; RC=$?; set -e
assert_exit "B1 tracked tree lint exit" 0 "$RC"

# ===== C and D: exact equality binds both directions on capped entries =====
EQ="$(t102_scratch eq)"
t102_seed "$EQ/planted.cjs" 3
(cd "$EQ" && git add -A)
t102_wl "$EQ" lint-fixture 3 planted.cjs
set +e; (cd "$EQ" && bash "$LINT" --json) > "$T102_DIR/eq0.json" 2>/dev/null; RC0=$?; set -e
assert_exit "C1 equality exact green exit" 0 "$RC0"
t102_seed "$EQ/planted.cjs" 4
set +e; (cd "$EQ" && bash "$LINT" --json) > "$T102_DIR/eqp.json" 2>/dev/null; RCP=$?; set -e
assert_exit "C2 excess probe exit" 1 "$RCP"
t102_seed "$EQ/planted.cjs" 2
set +e; (cd "$EQ" && bash "$LINT" --json) > "$T102_DIR/eqm.json" 2>/dev/null; RCM=$?; set -e
assert_exit "C3 deficit probe exit" 1 "$RCM"
node -e '
const fs = require("fs");
const read = (p) => JSON.parse(fs.readFileSync(p, "utf8"));
const pos = read(process.argv[1]);
const neg = read(process.argv[2]);
const one = (v) => v.length === 1 && v[0].type === "stale-or-exceeded" && v[0].category === "lint-fixture";
console.log(one(pos) ? "C2-OK" : "C2-FAIL got " + JSON.stringify(pos.map((x) => x.type)));
console.log(one(neg) ? "C3-OK" : "C3-FAIL got " + JSON.stringify(neg.map((x) => x.type)));
' "$T102_DIR/eqp.json" "$T102_DIR/eqm.json" > "$T102_DIR/cd.out" 2>&1 || true
t102_verdict "$T102_DIR/cd.out" C2 C3

# ===== E: ghost — entry naming an untracked path fails closed =====
GH="$(t102_scratch ghost)"
t102_wl "$GH" lint-fixture 1 ghost/absent.cjs
set +e; (cd "$GH" && bash "$LINT" --json) > "$T102_DIR/ghost.json" 2>/dev/null; RCG=$?; set -e
assert_exit "E1 ghost probe exit" 1 "$RCG"
node -e '
const v = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const ok = v.length === 1 && v[0].type === "ghost-whitelist-entry" && v[0].path === "ghost/absent.cjs";
console.log(ok ? "E1-OK" : "E1-FAIL got " + JSON.stringify(v.map((x) => x.type)));
' "$T102_DIR/ghost.json" > "$T102_DIR/e.out" 2>&1 || true
t102_verdict "$T102_DIR/e.out" E1

# ===== F: regen guard — a hand-mutated count diverges from regeneration =====
RG="$(t102_scratch regen)"
t102_seed "$RG/planted.cjs" 3
(cd "$RG" && git add -A)
t102_wl "$RG" in-flight-sweep 5 planted.cjs
set +e; (cd "$RG" && bash "$LINT" --json) > "$T102_DIR/mut.json" 2>/dev/null; RCF=$?; set -e
assert_exit "F1 mutated count fails the check" 1 "$RCF"
set +e; (cd "$RG" && bash "$LINT" --emit-baseline "$T102_DIR/regen.json") >/dev/null 2>&1; RCE=$?; set -e
assert_exit "F2 baseline emission exit" 0 "$RCE"
MUT_DIVERGE=no
if ! diff -q "$RG/.gos/ai-trace-whitelist.json" "$T102_DIR/regen.json" >/dev/null 2>&1; then
  MUT_DIVERGE=yes
fi
node -e '
const fs = require("fs");
const w = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const diverged = process.argv[2] === "yes";
const recomputed = w.length === 1 && w[0].category === "in-flight-sweep" && w[0].maxHits === 3;
console.log(diverged && recomputed ? "F3-OK" : "F3-FAIL diverged=" + diverged + " regen=" + JSON.stringify(w));
' "$T102_DIR/regen.json" "$MUT_DIVERGE" > "$T102_DIR/f.out" 2>&1 || true
t102_verdict "$T102_DIR/f.out" F3

# ===== G: gate integration — archive sandbox repo, planted anchor blocks =====
SBX="$T102_DIR/gatebox"
mkdir -p "$SBX"
git -C "$GOS_ROOT" archive HEAD | tar -x -C "$SBX"
(cd "$SBX" && git init -q . && git add -A)
set +e; (cd "$SBX" && node bin/gos.cjs gate all --json) > "$T102_DIR/gneg.raw" 2>/dev/null; RGN=$?; set -e
printf '// [%s %d] planted lineage marker\n' "REVIEW M" "$((4 + 5))" >> "$SBX/bin/lib/core/fsio.cjs"
set +e; (cd "$SBX" && node bin/gos.cjs gate all --json) > "$T102_DIR/gpos.raw" 2>/dev/null; RGP=$?; set -e
node -e '
const fs = require("fs");
const codes = (p) => {
  const out = fs.readFileSync(p, "utf8");
  const i = out.indexOf("{\n  \"verdict\"");
  if (i < 0) throw new Error("verdict object not found in gate output");
  return JSON.parse(out.slice(i)).failures.map((f) => f.code);
};
try {
  const neg = codes(process.argv[1]);
  console.log(neg.includes("ai-trace-lint") ? "G1-FAIL negative control fired " + JSON.stringify(neg) : "G1-OK");
} catch (e) { console.log("G1-FAIL " + e.message); }
try {
  const pos = codes(process.argv[2]);
  console.log(pos.includes("ai-trace-lint") ? "G2-OK" : "G2-FAIL codes " + JSON.stringify(pos));
} catch (e) { console.log("G2-FAIL " + e.message); }
' "$T102_DIR/gneg.raw" "$T102_DIR/gpos.raw" > "$T102_DIR/g.out" 2>&1 || true
t102_verdict "$T102_DIR/g.out" G1 G2

# ===== H: hits census — templates/ teaches digit-free, zero hit records =====
# The books and framework skeletons use placeholder spellings, so the lint
# covers templates/ with zero records — no curated stock, no whitelist entries.
set +e; (cd "$GOS_ROOT" && bash test/checks/ai-trace-lint.sh --emit-hits "$T102_DIR/hits.json") >/dev/null 2>&1; RCH=$?; set -e
assert_exit "H1 hits census emission exit" 0 "$RCH"
node -e '
const fs = require("fs");
const r = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const under = r.filter((x) => x.path.startsWith("templates/"));
console.log(r.length > 0 && under.length === 0 ? "H2-OK" : "H2-FAIL record(s) under templates " + under.length);
' "$T102_DIR/hits.json" > "$T102_DIR/h.out" 2>&1 || true
t102_verdict "$T102_DIR/h.out" H2

# ===== I: setup hint — the seeding command renders under both locales =====
HINT_EN="$(GOS_LANG=en node -e 'const s = require(process.argv[1] + "/bin/lib/ops/setup.cjs"); process.stdout.write(s.renderCodingHint());' "$GOS_ROOT")"
assert_contains "I1 en hint names the seeding command" "gos init coding" "$HINT_EN"
HINT_ZH="$(GOS_LANG=zh-CN node -e 'const s = require(process.argv[1] + "/bin/lib/ops/setup.cjs"); process.stdout.write(s.renderCodingHint());' "$GOS_ROOT")"
assert_contains "I2 zh hint names the seeding command" "gos init coding" "$HINT_ZH"

t102_teardown
echo "--- T102 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
