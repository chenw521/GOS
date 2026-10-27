#!/usr/bin/env bash
# gos-map:cmd track
# T98b: gos track — flip transaction: manifest + rename-style backups
# + injected-failure rollback + adopt/no-op + --knowledge preset.
# Facts asserted:
#   - M1 flip success appends a per-line JSON record {ts,path,head} to
#     .gos/track-manifest.json, stages it via the SAME git add, prints it
#   - M2 wholesale-ignored .gos/* repo: surgery negates BOTH the target and the
#     manifest (ignored-set diff == {target, manifest}), both staged
# - GOS_TEST_BREAK_TRACK={manifest,surgery,census} injected mid-
#     transaction failures → exit 1 and ALL stores restored byte-identical
#     (sha256 before/after: .gos/.gitignore, census.json, .gos/state.json,
#     target), manifest absent afterwards, nothing staged, backup dir swept
#   - A1/A2 adopt: legacy-tracked without manifest record → {adopted:true}
#     record appended, exit 0 (census absent OR consistent git:true, census
#     bytes untouched)
#   - A3/A4 census contradiction (git:false while tracked) → die exit 1,
#     manifest absent — contradiction beats adopt AND no-op
#   - N1 no-op: re-run after a successful flip → {noop:true}, exit 0, zero
#     mutations (manifest/gitignore sha unchanged)
#   - K1 --knowledge preset: trio flipped + born-at: <HEAD[0:8]> first line;
#     K2 re-run idempotent (ONE born-at line each, manifest line count stable);
#     K3 missing trio file → die, nothing flipped
#   - N2 manifest itself is a never-file (machine-managed) → direct track dies
#   - G1 GOS_PATHS registration: track_manifest + track_backup keys present in
#     fsio.cjs registry AND referenced from state.cjs (wiring grep ≥2 hits)
# Env: GOS, TESTBASE, assert helpers sourced by runner (standalone-safe).
T98B_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T98B_STANDALONE=1
  T98B_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T98B_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T98B_SELFROOT"
  export TESTBASE="$(mktemp -d "$T98B_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T98B_DIR=""

t98b_fresh() {
  T98B_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t98b"
  mkdir -p "$T98B_DIR" && cd "$T98B_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
  # write-class dispatch guard: every fixture carries its own task state
  node "$GOS" init 1 "t98b track fixture" >/dev/null 2>&1
}

t98b_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T98B_DIR"; }

# counter-bumping assert helpers (runner-parity output; own exit gate)
assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if [ -z "${expected:-}" ]; then
    echo "  ✗ $label (empty pattern always matches — use assert_file/assert_eq)"; FAIL=$((FAIL+1))
  elif echo "$actual" | grep -q "$expected"; then
    echo "  ✓ $label"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected: '$expected')"
    echo "    actual: ${actual:0:160}"; FAIL=$((FAIL+1))
  fi
}
assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then
    echo "  ✓ $label (exit $actual)"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected exit $expected, got '${actual:-<none>}')"; FAIL=$((FAIL+1))
  fi
}
assert_file() {
  local label="$1" fpath="$2"
  if [ -n "$fpath" ] && [ -e "$fpath" ]; then
    echo "  ✓ $label"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (missing: '${fpath:-<none>}')"; FAIL=$((FAIL+1))
  fi
}
assert_no_file() {
  local label="$1" fpath="$2"
  if [ -n "$fpath" ] && [ ! -e "$fpath" ]; then
    echo "  ✓ $label"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (unexpectedly present: '${fpath:-<none>}')"; FAIL=$((FAIL+1))
  fi
}
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ✓ $label"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected: '$expected', got: '$actual')"; FAIL=$((FAIL+1))
  fi
}
# sha256 of every store, one line each — compare before/after for rollback
t98b_store_shas() {
  for f in .gos/.gitignore census.json .gos/state.json .gos/concerns.md; do
    if [ -e "$f" ]; then sha256sum "$f" | cut -d' ' -f1; else echo "ABSENT"; fi
  done
}

PASS=0
FAIL=0

echo "--- T98b: gos track — manifest + backups + adopt/no-op + preset (D-15/D-14) ---"

# --- M1: flip success records the manifest line {ts,path,head} + stages it ---
t98b_fresh
printf ".gos/concerns.md\n" >> .gitignore
mkdir -p .gos && printf 'manifest fixture content\n' > .gos/concerns.md
set +e; OUT=$(node "$GOS" track .gos/concerns.md 2>&1); RC=$?; set -e
assert_exit "M1 track exits 0" "0" "$RC"
assert_file "M1 manifest created" ".gos/track-manifest.json"
assert_contains "M1 manifest printed on success" "track-manifest.json" "$OUT"
HEADSHA=$(git rev-parse HEAD)
MLINE=$(python3 -c '
import json, sys
last = None
for line in open(".gos/track-manifest.json"):
    line = line.strip()
    if not line: continue
    r = json.loads(line)  # per-line JSON — a bad line must fail the test
    assert set(r.keys()) >= {"ts", "path", "head"}, r
    last = r
assert last and last["path"] == ".gos/concerns.md", last
assert last["head"] == sys.argv[1], last
print("OK")
' "$HEADSHA" 2>&1 || true)
assert_eq "M1 record is per-line JSON {ts,path,head} for the target at HEAD" "OK" "$MLINE"
STAGED=$(git diff --cached --name-only)
assert_contains "M1 manifest staged by the flip" ".gos/track-manifest.json" "$STAGED"
assert_contains "M1 target staged" ".gos/concerns.md" "$STAGED"
t98b_teardown

# --- M2: wholesale-ignored .gos/* — surgery negates target AND manifest ---
t98b_fresh
printf '.gos/*\n!.gos/.gitignore\n' > .gitignore && git add .gitignore && git commit -q -m wholesale
mkdir -p .gos && printf 'wholesale fixture content\n' > .gos/concerns.md
git check-ignore -q .gos/concerns.md && git check-ignore -q .gos/track-manifest.json
assert_exit "M2 fixture: target and manifest both ignored" "0" "$?"
set +e; OUT=$(node "$GOS" track .gos/concerns.md 2>&1); RC=$?; set -e
assert_exit "M2 track exits 0 in a wholesale-ignored repo" "0" "$RC"
NEG=$(grep -c '^!/concerns\.md$' .gos/.gitignore || true)
assert_eq "M2 target negation present" "1" "$NEG"
MNEG=$(grep -c '^!/track-manifest\.json$' .gos/.gitignore || true)
assert_eq "M2 manifest negation present" "1" "$MNEG"
set +e; git check-ignore -q .gos/track-manifest.json; MIR=$?; set -e
if [ "$MIR" -ne 0 ]; then
  echo "  ✓ M2 manifest no longer ignored (rc=$MIR)"; PASS=$((PASS+1))
else
  echo "  ✗ M2 manifest still ignored after surgery"; FAIL=$((FAIL+1))
fi
STAGED=$(git diff --cached --name-only)
assert_contains "M2 manifest staged" ".gos/track-manifest.json" "$STAGED"
assert_contains "M2 .gos/.gitignore staged" ".gos/.gitignore" "$STAGED"
t98b_teardown

# --- : injected mid-transaction failure → all stores restored
t98b_rollback_case() {
  local STAGE="$1" LABEL="$2"
  t98b_fresh
  printf ".gos/concerns.md\n" >> .gitignore
  mkdir -p .gos && printf 'rollback fixture content\n' > .gos/concerns.md
  printf '# preexisting managed negations\n!/other.md\n' > .gos/.gitignore
  git add -f .gos/.gitignore && git commit -q -m pregi
  cat > census.json <<'CENEOF'
{
  "schema_version": 1,
  "_doc": "fixture census",
  "entries": {
    ".gos/concerns.md": { "git": false, "npm": false, "note": "machine-local (gitignored)" }
  },
  "dispositions": []
}
CENEOF
  git add census.json && git commit -q -m census
  BEFORE=$(t98b_store_shas)
  set +e; OUT=$(GOS_TEST_BREAK_TRACK="$STAGE" node "$GOS" track .gos/concerns.md 2>&1); RC=$?; set -e
  assert_exit "$LABEL injected '$STAGE' failure dies exit 1" "1" "$RC"
  assert_contains "$LABEL failure wording names the hook" "GOS_TEST_BREAK_TRACK" "$OUT"
  AFTER=$(t98b_store_shas)
  assert_eq "$LABEL all stores restored byte-identical (gitignore/census/state/target)" "$BEFORE" "$AFTER"
  assert_no_file "$LABEL manifest absent after rollback" ".gos/track-manifest.json"
  CACHED=$(git diff --cached --name-only)
  assert_eq "$LABEL nothing staged after rollback" "" "$CACHED"
  if [ ! -e .gos/cache/track-backup ] || [ -z "$(ls -A .gos/cache/track-backup 2>/dev/null)" ]; then
    echo "  ✓ $LABEL backup dir swept"; PASS=$((PASS+1))
  else
    echo "  ✗ $LABEL backup dir still carries entries"; FAIL=$((FAIL+1))
  fi
  t98b_teardown
}
t98b_rollback_case manifest B1
t98b_rollback_case surgery B2
t98b_rollback_case census B3

# --- B4: git-add-tail failure → index swept (worktree AND index rollback) ---
t98b_fresh
printf ".gos/concerns.md\n" >> .gitignore
mkdir -p .gos && printf 'rollback fixture content\n' > .gos/concerns.md
git add -f .gos/.gitignore 2>/dev/null || true
BEFORE=$(t98b_store_shas)
set +e; OUT=$(GOS_TEST_BREAK_TRACK="gitAdd" node "$GOS" track .gos/concerns.md 2>&1); RC=$?; set -e
assert_exit "B4 injected gitAdd failure dies exit 1" "1" "$RC"
assert_contains "B4 failure wording names the hook" "GOS_TEST_BREAK_TRACK" "$OUT"
AFTER=$(t98b_store_shas)
assert_eq "B4 stores restored byte-identical" "$BEFORE" "$AFTER"
CACHED=$(git diff --cached --name-only | grep -F '.gos/concerns.md' || true)
assert_eq "B4 partially-staged target swept from the index" "" "$CACHED"
t98b_teardown
# rollback-gap visibility contract (i18n, both catalogs)
I18N=$(node -e '
const en = require(process.env.GOS_ROOT + "/bin/lib/core/locales/en.cjs");
const zh = require(process.env.GOS_ROOT + "/bin/lib/core/locales/zh.cjs");
const need = ["track.err.rollbackIncomplete"];
const bad = need.filter((k) => !en[k] || !zh[k]);
if (bad.length) { console.error("missing: " + bad.join(",")); process.exit(1); }
console.log("OK");
' 2>&1)
if [ "$I18N" = "OK" ]; then
  echo "  ✓ B4 rollback-incomplete warning catalogued (en+zh)"; PASS=$((PASS+1))
else
  echo "  ✗ B4 rollback-incomplete i18n: $I18N"; FAIL=$((FAIL+1))
fi

# --- A1: adopt — legacy-tracked, no census → {adopted:true}, exit 0 ---
t98b_fresh
mkdir -p .gos && printf 'legacy tracked content\n' > .gos/concerns.md
git add -f .gos/concerns.md && git commit -q -m pretrack
set +e; OUT=$(node "$GOS" track .gos/concerns.md --json 2>/dev/null); RC=$?; set -e
assert_exit "A1 legacy-tracked target adopts exit 0" "0" "$RC"
assert_contains "A1 envelope adopted:true" '"adopted": true' "$OUT"
AREC=$(python3 -c '
import json
recs = [json.loads(l) for l in open(".gos/track-manifest.json") if l.strip()]
hit = [r for r in recs if r.get("path") == ".gos/concerns.md"]
assert len(hit) == 1 and hit[0].get("adopted") is True, hit
print("OK")
' 2>&1 || true)
assert_eq "A1 adopt record {ts,path,head,adopted:true} in manifest" "OK" "$AREC"
STAGED=$(git diff --cached --name-only)
assert_contains "A1 manifest staged by the adopt" ".gos/track-manifest.json" "$STAGED"
t98b_teardown

# --- A2: adopt with consistent census git:true → census bytes untouched ---
t98b_fresh
mkdir -p .gos && printf 'census-consistent tracked content\n' > .gos/concerns.md
cat > census.json <<'CENEOF'
{
  "schema_version": 1,
  "_doc": "fixture census",
  "entries": {
    ".gos/concerns.md": { "git": true, "npm": false, "note": "already shared" }
  },
  "dispositions": []
}
CENEOF
git add -f .gos/concerns.md census.json && git commit -q -m pretrack
CBSHA=$(sha256sum census.json | cut -d' ' -f1)
set +e; OUT=$(node "$GOS" track .gos/concerns.md 2>&1); RC=$?; set -e
assert_exit "A2 adopt with consistent census exits 0" "0" "$RC"
assert_contains "A2 human line says adopted" "adopt" "$OUT"
assert_eq "A2 census bytes untouched by the adopt" "$CBSHA" "$(sha256sum census.json | cut -d' ' -f1)"

# --- A3: `--` end-of-options separator (the gate fix line emits `gos track -- <path>`) ---
t98b_fresh
mkdir -p .gos && printf 'separator form content\n' > .gos/concerns.md
git add -f .gos/concerns.md && git commit -q -m pretrack
set +e; OUT=$(node "$GOS" track -- .gos/concerns.md 2>&1); RC=$?; set -e
assert_exit "A3 track -- <path> adopts (separator parsed, not Usage)" "0" "$RC"
A3REC=$(test -f .gos/track-manifest.json && grep -c '"path":"\.gos/concerns\.md"' .gos/track-manifest.json || echo 0)
assert_eq "A3 separator-form adopt recorded in manifest" "1" "$A3REC"
t98b_teardown
t98b_teardown

# --- A3: census contradiction (tracked but census git:false) → die ---
t98b_fresh
mkdir -p .gos && printf 'contradiction content\n' > .gos/concerns.md
cat > census.json <<'CENEOF'
{
  "schema_version": 1,
  "_doc": "fixture census",
  "entries": {
    ".gos/concerns.md": { "git": false, "npm": false, "note": "says local but tracked" }
  },
  "dispositions": []
}
CENEOF
git add -f .gos/concerns.md census.json && git commit -q -m pretrack
set +e; OUT=$(node "$GOS" track .gos/concerns.md 2>&1); RC=$?; set -e
assert_exit "A3 census contradiction dies exit 1" "1" "$RC"
assert_contains "A3 contradiction wording names census" "census" "$OUT"
assert_no_file "A3 manifest NOT written on contradiction" ".gos/track-manifest.json"
t98b_teardown

# --- A4: contradiction beats no-op (manifest record present but census lies) ---
t98b_fresh
printf ".gos/concerns.md\n" >> .gitignore
mkdir -p .gos && printf 'flip then flip census content\n' > .gos/concerns.md
node "$GOS" track .gos/concerns.md >/dev/null 2>&1
git commit -q -am flipped
cat > census.json <<'CENEOF'
{
  "schema_version": 1,
  "_doc": "fixture census",
  "entries": {
    ".gos/concerns.md": { "git": false, "npm": false, "note": "hand-flipped back to local" }
  },
  "dispositions": []
}
CENEOF
git add census.json && git commit -q -m flipcensus
MSHA=$(sha256sum .gos/track-manifest.json | cut -d' ' -f1)
set +e; OUT=$(node "$GOS" track .gos/concerns.md 2>&1); RC=$?; set -e
assert_exit "A4 contradiction with manifest record still dies" "1" "$RC"
assert_eq "A4 manifest untouched by the die" "$MSHA" "$(sha256sum .gos/track-manifest.json | cut -d' ' -f1)"
t98b_teardown

# --- N1: re-run after a successful flip = verified no-op, zero mutations ---
t98b_fresh
printf ".gos/concerns.md\n" >> .gitignore
mkdir -p .gos && printf 'noop fixture content\n' > .gos/concerns.md
node "$GOS" track .gos/concerns.md >/dev/null 2>&1
GSHA=$(sha256sum .gos/.gitignore | cut -d' ' -f1)
MSHA=$(sha256sum .gos/track-manifest.json | cut -d' ' -f1)
STAGED_BEFORE=$(git diff --cached --name-only | sort | tr '\n' ' ')
set +e; OUT=$(node "$GOS" track .gos/concerns.md --json 2>/dev/null); RC=$?; set -e
assert_exit "N1 re-run exits 0" "0" "$RC"
assert_contains "N1 envelope noop:true" '"noop": true' "$OUT"
assert_eq "N1 .gos/.gitignore unchanged" "$GSHA" "$(sha256sum .gos/.gitignore | cut -d' ' -f1)"
assert_eq "N1 manifest unchanged (no new record)" "$MSHA" "$(sha256sum .gos/track-manifest.json | cut -d' ' -f1)"
assert_eq "N1 staged set unchanged (zero mutations)" "$STAGED_BEFORE" "$(git diff --cached --name-only | sort | tr '\n' ' ')"
t98b_teardown

# --- K1: --knowledge preset flips the trio + born-at: <HEAD[0:8]> first line ---
t98b_fresh
printf '.gos/codebase/structure.md\n.gos/codebase/conventions.md\n.gos/codebase/concerns.md\n' >> .gitignore
mkdir -p .gos/codebase
printf '# Structure\nmodule layout notes\n' > .gos/codebase/structure.md
printf '# Conventions\ncode style rules\n' > .gos/codebase/conventions.md
printf '# Concerns\nwatch-list entries\n' > .gos/codebase/concerns.md
HEAD8=$(git rev-parse HEAD | cut -c1-8)
set +e; OUT=$(node "$GOS" track --knowledge 2>&1); RC=$?; set -e
assert_exit "K1 knowledge preset exits 0" "0" "$RC"
for f in structure conventions concerns; do
  FIRST=$(head -1 ".gos/codebase/$f.md")
  assert_eq "K1 $f.md born-at first line == HEAD[0:8]" "born-at: $HEAD8" "$FIRST"
  set +e; git ls-files --error-unmatch -- ".gos/codebase/$f.md" >/dev/null 2>&1; LSR=$?; set -e
  assert_exit "K1 $f.md staged via git add" "0" "$LSR"
done
KREC=$(python3 -c '
import json
recs = [json.loads(l) for l in open(".gos/track-manifest.json") if l.strip()]
trio = {r["path"] for r in recs}
want = {".gos/codebase/structure.md", ".gos/codebase/conventions.md", ".gos/codebase/concerns.md"}
assert want <= trio, trio
print("OK")
' 2>&1 || true)
assert_eq "K1 manifest carries all three trio records" "OK" "$KREC"
t98b_teardown

# --- K2: --knowledge re-run idempotent — one born-at line each, no dup records ---
t98b_fresh
printf '.gos/codebase/structure.md\n.gos/codebase/conventions.md\n.gos/codebase/concerns.md\n' >> .gitignore
mkdir -p .gos/codebase
printf '# Structure\nmodule layout notes\n' > .gos/codebase/structure.md
printf '# Conventions\ncode style rules\n' > .gos/codebase/conventions.md
printf '# Concerns\nwatch-list entries\n' > .gos/codebase/concerns.md
node "$GOS" track --knowledge >/dev/null 2>&1
BODY_S=$(tail -n +2 .gos/codebase/structure.md | sha256sum | cut -d' ' -f1)
MSHA=$(sha256sum .gos/track-manifest.json | cut -d' ' -f1)
MLINES=$(grep -c '' .gos/track-manifest.json)
set +e; OUT=$(node "$GOS" track --knowledge --json 2>/dev/null); RC=$?; set -e
assert_exit "K2 knowledge re-run exits 0" "0" "$RC"
for f in structure conventions concerns; do
  NB=$(grep -c '^born-at: ' ".gos/codebase/$f.md" || true)
  assert_eq "K2 $f.md exactly one born-at line" "1" "$NB"
done
assert_eq "K2 trio content untouched below the stamp" "$BODY_S" "$(tail -n +2 .gos/codebase/structure.md | sha256sum | cut -d' ' -f1)"
assert_eq "K2 manifest record count stable (re-run = no-op)" "$MLINES" "$(grep -c '' .gos/track-manifest.json)"
t98b_teardown

# --- K3: --knowledge with a missing trio file → die, nothing flipped ---
t98b_fresh
printf '.gos/codebase/structure.md\n.gos/codebase/conventions.md\n.gos/codebase/concerns.md\n' >> .gitignore
mkdir -p .gos/codebase
printf '# Structure\nmodule layout notes\n' > .gos/codebase/structure.md
printf '# Conventions\ncode style rules\n' > .gos/codebase/conventions.md
set +e; OUT=$(node "$GOS" track --knowledge 2>&1); RC=$?; set -e
assert_exit "K3 missing trio file dies exit 1" "1" "$RC"
assert_contains "K3 die names the missing file" ".gos/codebase/concerns.md" "$OUT"
assert_no_file "K3 no .gos/.gitignore created" ".gos/.gitignore"
assert_no_file "K3 no manifest written" ".gos/track-manifest.json"
set +e; git ls-files --error-unmatch -- .gos/codebase/structure.md >/dev/null 2>&1; LSR=$?; set -e
if [ "$LSR" -ne 0 ]; then
  echo "  ✓ K3 die-before-touch: nothing staged"; PASS=$((PASS+1))
else
  echo "  ✗ K3 something got staged despite the die"; FAIL=$((FAIL+1))
fi
t98b_teardown

# --- N2: the manifest itself is a never-file (machine-managed) ---
t98b_fresh
printf '.gos/*\n!.gos/.gitignore\n' > .gitignore && git add .gitignore && git commit -q -m wholesale
mkdir -p .gos && printf '{}' > .gos/track-manifest.json
set +e; OUT=$(node "$GOS" track .gos/track-manifest.json 2>&1); RC=$?; set -e
assert_exit "N2 direct track of the manifest dies exit 1" "1" "$RC"
assert_contains "N2 never-track wording" "never-track" "$OUT"
t98b_teardown

# --- G1: GOS_PATHS registration (fsio.cjs registry + state.cjs wiring refs) ---
GREG=$(node -e '
const fsio = require(process.env.GOS_ROOT + "/bin/lib/core/fsio.cjs");
const bad = [];
const m = fsio.GOS_PATHS.track_manifest;
const b = fsio.GOS_PATHS.track_backup;
if (!m || m.rel !== "track-manifest.json" || m.tracked !== true) bad.push("track_manifest key wrong");
if (!b || b.rel !== "cache/track-backup" || b.tracked !== false) bad.push("track_backup key wrong");
if (!fsio.resolvePath("track_manifest").endsWith(path_join())) bad.push("resolvePath track_manifest");
if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
function path_join() { return require("path").join("track-manifest.json"); }
console.log("OK");
' 2>&1 || true)
assert_eq "G1 GOS_PATHS carries track_manifest + track_backup" "OK" "$GREG"
WHITS=$(grep -c "track_manifest\|track_backup" "$GOS_ROOT/bin/lib/core/state.cjs" "$GOS_ROOT/bin/lib/core/fsio.cjs" | awk -F: '{s+=$2} END {print s}')
if [ "$WHITS" -ge 2 ]; then
  echo "  ✓ G1 wiring grep: track_manifest|track_backup >=2 hits across state.cjs+fsio.cjs ($WHITS)"; PASS=$((PASS+1))
else
  echo "  ✗ G1 wiring grep under 2 hits ($WHITS)"; FAIL=$((FAIL+1))
fi
KFLAG=$(node -e '
const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
const f = (core.COMMANDS.track.flags || []).map((x) => x.name);
console.log(f.includes("--knowledge") ? "OK" : "missing: " + f.join(","));
' 2>&1 || true)
assert_eq "G1 COMMANDS.track registers the --knowledge flag" "OK" "$KFLAG"

if [ "$T98B_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi

echo "--- T98b summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
