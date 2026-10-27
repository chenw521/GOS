#!/usr/bin/env bash
# gos-map:cmd requirement
# : requirement command family (add/list/drop/claim) + dual-store
# Covers: (plan )
T4_DIR=""

t4_setup() {
  T4_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t4"
  mkdir -p "$T4_DIR" && cd "$T4_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  echo ".gos/state.json" > .gitignore && git add .gitignore && git commit -q -m gi
}

t4_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T4_DIR"; }

# fixed-string assert (header/rows contain '|', unsafe as assert_contains regex)
assert_contains_f() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then
    echo "  ✓ $label"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected fixed: '$expected')"
    echo "    actual: ${actual:0:160}"
    FAIL=$((FAIL+1))
  fi
}

t4_setup
echo "--- T4: requirement command family ---"

# --- .1: add auto-assigns (init created )
node "$GOS" init 2 "demo task" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" requirement add "second need" 2>&1); RC=$?; set -e
assert_exit "add exits 0" 0 "$RC"
assert_contains "auto R-02 after init R-01" "R-02 added" "$OUT"
assert_contains_f "exact add line" "✓ Requirement R-02 added: second need" "$OUT"
assert_contains "next hint list" "Next: gos requirement list" "$OUT"

set +e; OUT=$(node "$GOS" requirement add "third need" 2>&1); RC=$?; set -e
assert_exit "second add exits 0" 0 "$RC"
assert_contains "auto R-03" "R-03 added" "$OUT"

# --- .3: positional R-NN rejected ( init-exclusive)
set +e; OUT=$(node "$GOS" requirement add R-09 extra 2>&1); RC=$?; set -e
assert_exit "R-09 positional exit 1" 1 "$RC"
assert_contains "init-exclusive message" "init-exclusive" "$OUT"

# --- .4: hostile text rejected, no side effects
set +e; OUT=$(node "$GOS" requirement add 'x $(touch pwned-t4)' 2>&1); RC=$?; set -e
assert_exit "hostile text exit 1" 1 "$RC"
if [ ! -e pwned-t4 ]; then echo "  ✓ pwned-t4 not created"; PASS=$((PASS+1)); else echo "  ✗ pwned-t4 WAS created"; FAIL=$((FAIL+1)); fi

# --- .5: list shows header + + added
OUT=$(node "$GOS" requirement list 2>&1 || true)
assert_contains_f "list header" "| ID | Requirement | Phase | Status |" "$OUT"
assert_contains_f "R-01 row" "| R-01 |" "$OUT"
assert_contains_f "R-02 row" "| R-02 |" "$OUT"
assert_contains_f "R-03 row" "| R-03 |" "$OUT"

# --- .6: drop → list shows dropped
set +e; OUT=$(node "$GOS" requirement drop R-02 2>&1); RC=$?; set -e
assert_exit "drop exits 0" 0 "$RC"
assert_contains_f "drop message" "✓ Requirement R-02 dropped" "$OUT"
OUT=$(node "$GOS" requirement list 2>&1 || true)
assert_contains_f "dropped status in list" "| R-02 | second need | - | dropped |" "$OUT"

set +e; OUT=$(node "$GOS" requirement claim R-03 --phase "P1: x" 2>&1); RC=$?; set -e
assert_exit "claim exits 0" 0 "$RC"
assert_contains_f "claim message" "✓ Requirement R-03 claimed by P1: x" "$OUT"
PH=$(python3 -c "
import json; s=json.load(open('.gos/state.json'))
print([r.get('phase') for r in s['requirements'] if r['id']=='R-03'][0])")
assert_eq "R-03 phase persisted in state" "P1: x" "$PH"

set +e; OUT=$(node "$GOS" requirement drop R-99 2>&1); RC=$?; set -e
assert_exit "drop unknown exit 1" 1 "$RC"
assert_contains "not found message" "not found" "$OUT"

# --- .9: Lv4 (plain init, no --project) add without --phase → exit 1
t4_teardown; t4_setup
node "$GOS" init 4 "lv4 plain" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" requirement add "must claim" 2>&1); RC=$?; set -e
assert_exit "Lv4 add without phase exit 1" 1 "$RC"
assert_contains "phase required message" "phase required" "$OUT"

# --- .10: Lv4 add WITH --phase → succeeds (state-only)
set +e; OUT=$(node "$GOS" requirement add "must claim" --phase "P1: name" 2>&1); RC=$?; set -e
assert_exit "Lv4 add with phase exits 0" 0 "$RC"
assert_contains "R-02 added at Lv4" "R-02 added" "$OUT"

# --- .11: dual-store (init 4 --project): add lands in both stores
t4_teardown; t4_setup
node "$GOS" init 4 "platform" --project >/dev/null 2>&1
set +e; OUT=$(node "$GOS" requirement add "shared need" --phase "P2: later" 2>&1); RC=$?; set -e
assert_exit "dual-store add exits 0" 0 "$RC"
assert_contains "R-02 added dual" "R-02 added" "$OUT"
assert_file "project.json exists" ".gos/project/project.json"
INP=$(python3 -c "
import json; p=json.load(open('.gos/project/project.json'))
print(any(r['id']=='R-02' for r in p['requirements']))")
INS=$(python3 -c "
import json; s=json.load(open('.gos/state.json'))
print(any(r['id']=='R-02' for r in s['requirements']))")
assert_eq "R-02 in project.json" "True" "$INP"
assert_eq "R-02 mirrored in state.json" "True" "$INS"

t4_teardown
