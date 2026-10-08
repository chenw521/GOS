#!/usr/bin/env bash
# gos-map:none   # sandbox builds its own project container; no live-repo truth source
# T37: phase claim/list UX fixes (idx column / actionable out-of-range error / name prefix)
PASS=0; FAIL=0
command -v assert_exit >/dev/null || assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected exit $expected, got '${actual:-<none>}')"; FAIL=$((FAIL+1)); fi
}
command -v assert_contains >/dev/null || assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected: '$expected')"; echo "    actual: ${actual:0:200}"; FAIL=$((FAIL+1)); fi
}
GOS="${GOS:-$(git rev-parse --show-toplevel 2>/dev/null)/bin/gos.cjs}"
T37_DIR=""

t37_setup() {
  [ -n "$TESTBASE" ] || TESTBASE="$(mktemp -d)"
  T37_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t37"
  mkdir -p "$T37_DIR" && cd "$T37_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  # project container + two phases (own truth source, isolated from the live repo)
  node "$GOS" init --project 1 "t37 container" >/dev/null 2>&1
  node "$GOS" phase add "A-alpha: first" --goal "t37 fixture one" >/dev/null 2>&1
  node "$GOS" phase add "B-beta: second" --goal "t37 fixture two" >/dev/null 2>&1
  # settle the wrapper state (stage may rest at PLAN after add — claim only needs project.json to exist)
}

t37_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T37_DIR"; }

t37_setup
echo "--- T37: phase claim/list UX ---"

# --- list table has an idx column ---
OUT=$(node "$GOS" phase list 2>&1)
assert_contains "T37.1a list has idx header column" "| idx | Phase | Goal | Status |" "$OUT"
assert_contains "T37.1b list row 0 carries index" "| 0 | A-alpha: first |" "$OUT"
assert_contains "T37.1c list row 1 carries index" "| 1 | B-beta: second |" "$OUT"

# --- out-of-range error is actionable ---
OUT=$(node "$GOS" phase claim 99 2>&1); RC=$?
assert_exit "T37.2a out-of-range exits 1" 1 "$RC"
assert_contains "T37.2b error states valid range" "valid range: 0-1" "$OUT"
assert_contains "T37.2c error maps queue entry 0" "0=A-alpha: first" "$OUT"
assert_contains "T37.2d error points to phase list" "gos phase list" "$OUT"

# --- name-prefix claim (real claim + restore in the sandbox) ---
# roadmap order gate: only the FIRST pending phase is claimable — prefix-claim A (in-order)
OUT=$(node "$GOS" phase claim A 2>&1)
assert_contains "T37.3a prefix claim claims named phase" "Phase claimed: A-alpha: first" "$OUT"
OUT=$(node "$GOS" phase unclaim 2>&1)
assert_contains "T37.3b unclaim restores" "A-alpha\|unclaim" "$OUT"
OUT=$(node "$GOS" phase claim Z 2>&1); RC=$?
assert_exit "T37.3c unknown prefix exits 1" 1 "$RC"
assert_contains "T37.3d unknown prefix points to list" "gos phase list" "$OUT"

# --- [L3] DONE-state Next: approval-gate visibility + unmerged-branch reminder ---
# branch ahead case: feature branch with extra commit, DONE+unarchived+unapproved
git checkout -q -b feature-x 2>/dev/null
echo x > f.txt && git add f.txt && git -c user.email=t@t -c user.name=t commit -qm feat
node "$GOS" init 1 "l3 fixture" >/dev/null 2>&1
node -e "
const fs=require('fs');
const d=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
d.current_stage='DONE'; delete d.completed_at; d.approvals={};
fs.writeFileSync('.gos/state.json', JSON.stringify(d,null,2));
"
OUT=$(node "$GOS" 2>&1)
assert_contains "T37.4a DONE+unapproved shows user gate" "awaiting YOUR approval" "$OUT"
assert_contains "T37.4b unmerged branch reminder" "ahead of main" "$OUT"
# approved case: ARCHIVE approval set → 'archive ready'
node -e "
const fs=require('fs');
const d=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
d.approvals={ARCHIVE:'2026-01-01T00:00:00Z'};
fs.writeFileSync('.gos/state.json', JSON.stringify(d,null,2));
"
OUT=$(node "$GOS" 2>&1)
assert_contains "T37.4c approved shows archive ready" "archive ready" "$OUT"

t37_teardown
echo "--- T37 done: PASS=$PASS FAIL=$FAIL ---"
[ "$FAIL" -eq 0 ] || exit 1
