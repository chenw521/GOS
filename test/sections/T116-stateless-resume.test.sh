#!/usr/bin/env bash
# gos-map:fn bin/lib/nav/cmds.cjs#fn:cmdResume bin/lib/core/state.cjs#fn:retireWrapperState
# gos-map:cmd resume
# stateless resume — the fresh-clone view (Lv4 marker present, no task state):
# the NO ACTIVE TASK banner stays ASCII, milestone identity renders open or
# closed, the phase queue tail counts done/active/pending/parked with names
# for pending and parked, the clone warning fires, and the run exits 0.
# Non-Lv4 stateless repos keep the start invitation (exit 1). Legacy wrapper
# states (project=true, no claimed phase) surface the retirement prompt at
# dispatch entry: non-interactive runs keep the state with a notice,
# GOS_RETIRE_WRAPPER=1 retires it, mid-flight wrappers are left untouched,
# and retirement hands the repo to the stateless view.
PASS=0; FAIL=0
command -v assert_exit >/dev/null || assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected exit $expected, got '${actual:-<none>}')"; FAIL=$((FAIL+1)); fi
}
command -v assert_contains >/dev/null || assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected: '$expected')"; echo "    actual: ${actual:0:240}"; FAIL=$((FAIL+1)); fi
}
command -v assert_file >/dev/null || assert_file() {
  local label="$1" fpath="$2"
  if [ -n "$fpath" ] && [ -e "$fpath" ]; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (missing: '${fpath:-<none>}')"; FAIL=$((FAIL+1)); fi
}
GOS="${GOS:-$(git rev-parse --show-toplevel 2>/dev/null)/bin/gos.cjs}"
T116_DIR=""

t116_setup() {
  [ -n "$TESTBASE" ] || TESTBASE="$(mktemp -d)"
  T116_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t116"
  mkdir -p "$T116_DIR" && cd "$T116_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
}

t116_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T116_DIR"; }

# Seed the repo-lane container without ever writing task state: done phase,
# parked phase, pending phase — the queue tail composition the resume view
# must report by name and count.
t116_container() {
  node "$GOS" init --project --project=lifecycle >/dev/null 2>&1
  node "$GOS" phase add "P1: done one" --goal g >/dev/null 2>&1
  node "$GOS" phase add "P2: parked one" --goal g >/dev/null 2>&1
  node "$GOS" phase add "P3: pending one" --goal g >/dev/null 2>&1
  node "$GOS" phase add "P4: pending two" --goal g >/dev/null 2>&1
  node "$GOS" phase mark-done 0 >/dev/null 2>&1
  node "$GOS" phase park 1 --reason "waiting on deps" >/dev/null 2>&1
}

echo "--- T116: stateless resume + wrapper retirement ---"

# ===== bare repo: no state, no Lv4 trace — the start invitation =====
t116_setup
set +e; OUT=$(node "$GOS" resume 2>&1); RC=$?; set -e
assert_exit "resume without state or marker exits 1" 1 "$RC"
assert_contains "start invitation names init" "No state to resume. Start with" "$OUT"
assert_contains "invitation names the init verb" "gos init" "$OUT"
t116_teardown

# ===== fresh clone shape: marker present, no task state =====
t116_setup
t116_container
set +e; OUT=$(node "$GOS" resume 2>&1); RC=$?; set -e
assert_exit "stateless Lv4 resume exits 0" 0 "$RC"
assert_contains "ASCII banner head" "NO ACTIVE TASK" "$OUT"
assert_contains "milestone identity renders open" "Milestone: lifecycle (opened" "$OUT"
assert_contains "queue counts compose by status" "Phases: 1 done · 2 pending · 1 parked" "$OUT"
assert_contains "pending names listed under the label" "pending: P3: pending one, P4: pending two" "$OUT"
assert_contains "parked names listed under the label" "parked: P2: parked one" "$OUT"
assert_contains "clone warning explains machine-local state" "no local state.json — task state is machine-local (never committed); an in-flight task may live on another machine" "$OUT"
if [ -e .gos/state.json ]; then
  echo "  ✗ resume created a state.json (read-only invariant broken)"; FAIL=$((FAIL+1))
else
  echo "  ✓ resume wrote no state.json"; PASS=$((PASS+1))
fi

# closed-milestone variant: identity renders the closed stamp
node "$GOS" init 3 "close holder" >/dev/null 2>&1
node "$GOS" approve milestone-close >/dev/null 2>&1
node "$GOS" milestone close --carry-parked --yes >/dev/null 2>&1
rm -f .gos/state.json
set +e; OUT=$(node "$GOS" resume 2>&1); RC=$?; set -e
assert_exit "stateless resume after close exits 0" 0 "$RC"
assert_contains "milestone identity renders closed" "Milestone: lifecycle (closed" "$OUT"
POST=$(node -e "
const p = require('./.gos/project/project.json');
console.log([p.phases.map((x) => x.status).join(','), p.requirements.length].join('|'))")
[ "$POST" = "parked,pending,pending|0" ] && { echo "  ✓ carried queue intact after the close"; PASS=$((PASS+1)); } || { echo "  ✗ carried queue wrong: $POST"; FAIL=$((FAIL+1)); }
t116_teardown

# ===== empty queue variant =====
t116_setup
node "$GOS" init --project --project=empty-queue >/dev/null 2>&1
set +e; OUT=$(node "$GOS" resume 2>&1); RC=$?; set -e
assert_exit "stateless resume with no phases exits 0" 0 "$RC"
assert_contains "empty queue line" "Phases: none yet — the queue is empty" "$OUT"
assert_contains "milestone identity still present" "Milestone: empty-queue (opened" "$OUT"
t116_teardown

# ===== wrapper zombie retirement =====
t116_setup
t116_container
node "$GOS" init 3 "legacy container state" >/dev/null 2>&1
node -e "
const fs = require('fs');
const s = JSON.parse(fs.readFileSync('.gos/state.json', 'utf8'));
s.project = true;
delete s.phase_name;
fs.writeFileSync('.gos/state.json', JSON.stringify(s, null, 2));"
set +e; OUT=$(node "$GOS" status 2>&1); ERR=$(node "$GOS" status 2>&1 >/dev/null); RC=$?; set -e
assert_exit "run with a wrapper zombie still exits 0 (notice, not a crash)" 0 "$RC"
assert_contains "non-interactive notice names the retirement escape" "retire via GOS_RETIRE_WRAPPER=1 or an interactive re-run" "$ERR"
assert_file "non-interactive run left the wrapper state in place" ".gos/state.json"
set +e; OUT=$(GOS_RETIRE_WRAPPER=1 node "$GOS" status 2>&1); RC=$?; set -e
assert_exit "retirement run exits 0" 0 "$RC"
assert_contains "retirement contract line" "✓ wrapper state.json retired — the repo-level project view takes over (gos status)" "$OUT"
if [ ! -e .gos/state.json ]; then
  echo "  ✓ wrapper state.json deleted by retirement"; PASS=$((PASS+1))
else
  echo "  ✗ wrapper state.json survived retirement"; FAIL=$((FAIL+1))
fi
set +e; OUT=$(node "$GOS" resume 2>&1); RC=$?; set -e
assert_exit "post-retirement resume is the stateless view" 0 "$RC"
assert_contains "stateless banner after retirement" "NO ACTIVE TASK" "$OUT"
assert_contains "queue tail still reports the carried debt" "1 parked" "$OUT"
t116_teardown

# mid-flight wrapper (stage beyond INTENT/DONE) is NOT a zombie — no notice
t116_setup
node "$GOS" init --project >/dev/null 2>&1
node "$GOS" init 3 "midflight wrapper" >/dev/null 2>&1
node -e "
const fs = require('fs');
const s = JSON.parse(fs.readFileSync('.gos/state.json', 'utf8'));
s.project = true;
delete s.phase_name;
s.current_stage = 'BUILD';
fs.writeFileSync('.gos/state.json', JSON.stringify(s, null, 2));"
set +e; OUT=$(node "$GOS" status 2>&1); ERR=$(node "$GOS" status 2>&1 >/dev/null); RC=$?; set -e
assert_exit "mid-flight wrapper status exits 0" 0 "$RC"
if printf '%s' "$ERR" | grep -q 'GOS_RETIRE_WRAPPER'; then
  echo "  ✗ mid-flight wrapper wrongly flagged as a retireable zombie"; FAIL=$((FAIL+1))
else
  echo "  ✓ mid-flight wrapper never flagged for retirement"; PASS=$((PASS+1))
fi
t116_teardown

echo "--- T116 done: PASS=$PASS FAIL=$FAIL ---"
[ "$FAIL" -eq 0 ] || exit 1
