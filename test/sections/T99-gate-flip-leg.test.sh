#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/gate.cjs#fn:flipReconcileLeg bin/lib/core/gitprobe.cjs#fn:trackedUnder
# gos-map:cmd gate,track
# T99: D-15/D-14 gate flip-reconcile leg — census/git/manifest agreement on
# every tracked .gos file at gate time (file-granular, RT2-F4).
# Facts asserted:
#   - V1 census entry git:true (non-lifecycle) with nothing tracked under it
#     → FAIL flip-census-phantom + gateCmd fix line
#   - V2 tracked file covered by a git:false census entry (most-specific key)
#     → FAIL flip-census-contradicts
#   - M1 census-less repo: hand-tracked non-zone .gos file without a
#     flip-manifest record → FAIL flip-manifest-missing
#   - M2 census-present repo: hand-tracked .gos file with NO covering census
#     entry and no manifest record → FAIL flip-manifest-missing
#   - G2 never-file exemption: a committed .gos/track-manifest.json with zero
#     records is exempt from its own requirement (census-less, rc 0)
#   - L1/L2 lifecycle:true keys exempt from existence+manifest assertions
#     (tracked .gos/task files green; absent .gos/task green — no false FAIL)
#   - P1 real `gos track` flip → manifest recorded + census flipped, then
#     `gate flip` green (no false FAIL on the transaction's own artifacts:
#     .gos/.gitignore surgery store and the manifest itself)
#   - G1 wiring: gitprobe exports trackedUnder; gate.cjs carries no
#     probe-family git call (monopoly check green)
#   - S1 self-repo negative assertion (D-14): guide trio cover key
#     (.gos/codebase) + concerns + lessons entries stay git:false in the real
#     census.json AND `gate flip` on this repo exits 0 with the ✓ line
# Env: GOS, TESTBASE, assert helpers sourced by runner (standalone-safe).
T99_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T99_STANDALONE=1
  T99_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T99_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T99_SELFROOT"
  export TESTBASE="$(mktemp -d "$T99_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T99_DIR=""

t99_fresh() {
  T99_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t99"
  mkdir -p "$T99_DIR" && cd "$T99_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
  # write-class dispatch guard: every fixture carries its own task state (the
  # ancestor walk would otherwise find the GOS self repo above TESTBASE)
  node "$GOS" init 1 "t99 flip-leg fixture" >/dev/null 2>&1
}

t99_census() {
  printf '%s\n' "$1" > census.json && git add census.json && git commit -q -m census
}

t99_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T99_DIR"; }

assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if [ -z "${expected:-}" ]; then
    echo "  ✗ $label (empty pattern always matches — use assert_file/assert_eq)"; FAIL=$((FAIL+1))
  elif echo "$actual" | grep -q "$expected"; then
    echo "  ✓ $label"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected: '$expected')"
    echo "    actual: ${actual:0:200}"; FAIL=$((FAIL+1))
  fi
}
assert_not_contains() {
  local label="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo "  ✗ $label (unexpectedly found: '$expected')"; FAIL=$((FAIL+1))
  else
    echo "  ✓ $label"; PASS=$((PASS+1))
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

PASS=0
FAIL=0

echo "--- T99: gate flip-reconcile leg (D-15/D-14 — census/git/manifest agreement) ---"

# --- V1: census git:true entry, nothing tracked under it → phantom FAIL ---
t99_fresh
t99_census '{"entries": {".gos/concerns.md": {"git": true, "npm": false, "note": "t99 v1"}}}'
set +e; OUT=$(node "$GOS" gate flip 2>&1); RC=$?; set -e
assert_exit "V1 census git:true + untracked → exit 1" "1" "$RC"
assert_contains "V1 flip-census-phantom code" "flip-census-phantom" "$OUT"
assert_contains "V1 evidence carries the entry" ".gos/concerns.md" "$OUT"
assert_contains "V1 fix line printed (gateCmd)" "fix: node bin/gos.cjs track" "$OUT"
t99_teardown

# --- V2: census git:false but file tracked → contradiction FAIL ---
t99_fresh
t99_census '{"entries": {".gos/concerns.md": {"git": false, "npm": false, "note": "t99 v2"}}}'
mkdir -p .gos && printf 't99 v2 content\n' > .gos/concerns.md
git add -f .gos/concerns.md && git commit -q -m rogue
set +e; OUT=$(node "$GOS" gate flip 2>&1); RC=$?; set -e
assert_exit "V2 tracked + census git:false → exit 1" "1" "$RC"
assert_contains "V2 flip-census-contradicts code" "flip-census-contradicts" "$OUT"
assert_contains "V2 fix line printed (gateCmd)" "fix: node bin/gos.cjs track" "$OUT"
t99_teardown

# --- M1: census-less repo, hand-tracked .gos file, no manifest → FAIL ---
t99_fresh
mkdir -p .gos && printf 't99 m1 notes\n' > .gos/notes.md
git add .gos/notes.md && git commit -q -m hand
set +e; OUT=$(node "$GOS" gate flip 2>&1); RC=$?; set -e
assert_exit "M1 census-less manifest-less tracked file → exit 1" "1" "$RC"
assert_contains "M1 flip-manifest-missing code" "flip-manifest-missing" "$OUT"
assert_contains "M1 fix line adopts via gos track" "fix: node bin/gos.cjs track" "$OUT"
t99_teardown

# --- M2: census-present, hand-tracked file with NO covering entry → FAIL ---
t99_fresh
t99_census '{"entries": {".gos/state.json": {"git": true, "npm": false, "note": "t99 m2"}}}'
git add -f .gos/state.json && git commit -q -m state
printf 't99 m2 notes\n' > .gos/notes.md
git add .gos/notes.md && git commit -q -m hand
set +e; OUT=$(node "$GOS" gate flip 2>&1); RC=$?; set -e
assert_exit "M2 uncovered tracked file → exit 1" "1" "$RC"
assert_contains "M2 flip-manifest-missing code" "flip-manifest-missing" "$OUT"
if echo "$OUT" | grep -q "evidence: .gos/state.json"; then
  echo "  ✗ M2 sanctioned entry must not fail"; FAIL=$((FAIL+1))
else
  echo "  ✓ M2 sanctioned entry not failed"; PASS=$((PASS+1))
fi
t99_teardown

# --- G2: the manifest itself is a never-file (zero-record manifest green) ---
t99_fresh
mkdir -p .gos && : > .gos/track-manifest.json
git add .gos/track-manifest.json && git commit -q -m manifest
set +e; OUT=$(node "$GOS" gate flip 2>&1); RC=$?; set -e
assert_exit "G2 manifest-only repo → exit 0" "0" "$RC"
assert_contains "G2 flip-reconcile pass line" "flip-reconcile" "$OUT"
t99_teardown

# --- L1: lifecycle:true key with tracked task files → no false FAIL ---
t99_fresh
t99_census '{"entries": {".gos/task": {"git": true, "npm": false, "lifecycle": true, "note": "t99 l1"}}}'
mkdir -p .gos/task && printf '# t99 task spec\n' > .gos/task/spec.md
git add .gos/task/spec.md && git commit -q -m task
set +e; OUT=$(node "$GOS" gate flip 2>&1); RC=$?; set -e
assert_exit "L1 lifecycle zone tracked, no manifest → exit 0" "0" "$RC"
assert_contains "L1 flip-reconcile pass line" "flip-reconcile" "$OUT"
t99_teardown

# --- L2: lifecycle:true key with NOTHING tracked (post-archive clone) → no phantom ---
t99_fresh
t99_census '{"entries": {".gos/task": {"git": true, "npm": false, "lifecycle": true, "note": "t99 l2"}}}'
set +e; OUT=$(node "$GOS" gate flip 2>&1); RC=$?; set -e
assert_exit "L2 lifecycle zone absent → exit 0" "0" "$RC"
assert_not_contains "L2 no phantom on lifecycle key" "flip-census-phantom" "$OUT"
t99_teardown

# --- P1: real gos track flip → gate flip green (transaction artifacts exempt) ---
t99_fresh
t99_census '{"entries": {".gos/concerns.md": {"git": false, "npm": false, "note": "t99 p1"}}}'
printf ".gos/concerns.md\n" >> .gitignore && git add .gitignore && git commit -q -m gi2
mkdir -p .gos && printf 'born-at: 00000000\nt99 p1 guide content\n' > .gos/concerns.md
set +e; OUT=$(node "$GOS" track .gos/concerns.md 2>&1); RC=$?; set -e
assert_exit "P1 gos track exits 0" "0" "$RC"
assert_file "P1 flip manifest recorded" ".gos/track-manifest.json"
set +e; OUT=$(node "$GOS" gate flip 2>&1); RC=$?; set -e
assert_exit "P1 post-flip gate flip → exit 0" "0" "$RC"
assert_contains "P1 flip-reconcile pass line" "flip-reconcile" "$OUT"
assert_not_contains "P1 no manifest accusation" "flip-manifest-missing" "$OUT"
t99_teardown

# --- G1: wiring — trackedUnder exported + probe monopoly holds ---
W=$(node -e 'const g = require(process.env.GOS_ROOT + "/bin/lib/core/gitprobe.cjs"); process.exit(typeof g.trackedUnder === "function" ? 0 : 1)' 2>&1); GRC=$?
assert_exit "G1 gitprobe exports trackedUnder" "0" "$GRC"
bash "$GOS_ROOT/test/checks/gitprobe-monopoly.sh" >/dev/null 2>&1
assert_exit "G1 probe-family monopoly holds (gate.cjs clean)" "0" "$?"

# --- S1: self-repo negative assertion (D-14) + self-repo leg green ---
# Guide trio (.gos/codebase cover key) + concerns + lessons stay git:false in
# the REAL census.json; `gate flip` on this repository must pass.
cd "$GOS_ROOT" || exit 1
S1C=$(python3 -c "
import json
c = json.load(open('census.json'))
bad = [k for k in ['.gos/codebase', '.gos/concerns.md', '.gos/lessons.json', '.gos/lessons.md']
       if not isinstance(c['entries'].get(k), dict) or c['entries'][k].get('git') is not False]
print('OK' if not bad else 'BAD:' + ','.join(bad))
")
assert_contains "S1 self-repo census: trio cover + concerns + lessons git:false" "OK" "$S1C"
set +e; OUT=$(node "$GOS" gate flip 2>&1); RC=$?; set -e
assert_exit "S1 self-repo gate flip exit 0" "0" "$RC"
assert_contains "S1 self-repo flip-reconcile pass line" "flip-reconcile" "$OUT"
cd "$TESTBASE" >/dev/null 2>&1 || true

if [ "$FAIL" -gt 0 ]; then
  echo "T99 RESULT: $PASS passed, $FAIL FAILED"
  exit 1
fi
echo "T99 RESULT: $PASS passed, 0 failed"
