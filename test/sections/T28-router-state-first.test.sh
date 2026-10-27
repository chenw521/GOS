#!/usr/bin/env bash
# gos-map:cmd status,resume
# gos-router state-first routing — active state present → resume branch wins
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner
T28_DIR=""

t28_setup() {
  T28_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t28"
  mkdir -p "$T28_DIR" && cd "$T28_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  echo ".gos/state.json" > .gitignore && git add .gitignore && git commit -q -m gi
}

t28_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T28_DIR"; }

t28_setup
echo "--- T28: router state-first (gap reflux #1) ---"

# --- .1: SKILL.md carries the state-first guard (prerequisite first step, first table row)
S="$GOS_ROOT/skills/gos-router/SKILL.md"  # runner always exports GOS_ROOT
grep -q "state-first\|FIRST STEP" "$S" && echo "  ✓ SKILL.md carries state-first guard" && PASS=$((PASS+1)) || { echo "  ✗ SKILL.md lacks state-first guard"; FAIL=$((FAIL+1)); }
# the guard must appear before the New task row (document order = routing priority)
GUARDPOS=$(grep -n "FIRST STEP (state-first guard)" "$S" | head -1 | cut -d: -f1)
NEWTASKPOS=$(grep -n "^| New task |" "$S" | head -1 | cut -d: -f1)
if [ -n "$GUARDPOS" ] && [ -n "$NEWTASKPOS" ] && [ "$GUARDPOS" -lt "$NEWTASKPOS" ]; then echo "  ✓ guard precedes New-task row"; PASS=$((PASS+1)); else echo "  ✗ guard not before New-task row (guard@L$GUARDPOS vs newtask@L$NEWTASKPOS)"; FAIL=$((FAIL+1)); fi

# --- .2: CLI-side guard — init refuses to overwrite an active state (unless --force)
node "$GOS" init 2 "existing task" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" init 2 "another task" 2>&1); RC=$?; set -e
assert_exit "init over active state exits 1 (without --force)" 1 "$RC"
assert_contains "block message names existing task + resume path" "resume" "$OUT"
set +e; OUT=$(node "$GOS" init 2 "replaced" --force 2>&1); RC=$?; set -e
assert_exit "init --force still allowed" 0 "$RC"

# --- .3: CLI-side guard — resume/status do not crash without state
rm -rf .gos
set +e; OUT=$(node "$GOS" status 2>&1); RC=$?; set -e
assert_exit "status with no state exits 0" 0 "$RC"
assert_contains "status shows no-active-task contract" "No active task" "$OUT"

t28_teardown
