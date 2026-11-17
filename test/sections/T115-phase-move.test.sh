#!/usr/bin/env bash
# gos-map:fn bin/lib/knowledge/phase.cjs#fn:cmdPhase
# gos-map:cmd phase
# phase move — queue reorder by index or unique name prefix, active-source
# refusal (in-flight work pins its roadmap position), the --expect stale-advice
# guard, argument-shape errors, and the P0-named phase landing at index 0
# with views re-rendered in the new order.
PASS=0; FAIL=0
command -v assert_exit >/dev/null || assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected exit $expected, got '${actual:-<none>}')"; FAIL=$((FAIL+1)); fi
}
command -v assert_contains >/dev/null || assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected: '$expected')"; echo "    actual: ${actual:0:200}"; FAIL=$((FAIL+1)); fi
}
command -v assert_contains_f >/dev/null || assert_contains_f() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected fixed: '$expected')"; echo "    actual: ${actual:0:200}"; FAIL=$((FAIL+1)); fi
}
GOS="${GOS:-$(git rev-parse --show-toplevel 2>/dev/null)/bin/gos.cjs}"
T115_DIR=""

t115_setup() {
  [ -n "$TESTBASE" ] || TESTBASE="$(mktemp -d)"
  T115_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t115"
  mkdir -p "$T115_DIR" && cd "$T115_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  node "$GOS" init --project >/dev/null 2>&1
  node "$GOS" phase add "P1: alpha" --goal "goal one" >/dev/null 2>&1
  node "$GOS" phase add "P2: bravo" --goal "goal two" >/dev/null 2>&1
  node "$GOS" phase add "P3: charlie" --goal "goal three" >/dev/null 2>&1
  node "$GOS" phase add "P4: delta" --goal "goal four" >/dev/null 2>&1
  node "$GOS" phase add "P5: echo" --goal "goal five" >/dev/null 2>&1
}

t115_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T115_DIR"; }

t115_setup
echo "--- T115: phase move ---"

# ===== name-prefix source + queue table echo =====
set +e; OUT=$(node "$GOS" phase move P2 0 2>&1); RC=$?; set -e
assert_exit "move by name prefix exits 0" 0 "$RC"
assert_contains "move contract line names from and to" "✓ Phase moved: P2: bravo (index 1 → 0)" "$OUT"
assert_contains_f "post-move queue table shows the new index 0" "| 0 | P2: bravo | goal two | pending |" "$OUT"
assert_contains_f "shifted phase lands at index 1" "| 1 | P1: alpha | goal one | pending |" "$OUT"
ORDER=$(node -e "console.log(require('./.gos/project/project.json').phases.map((p) => p.name).join(','))")
[ "$ORDER" = "P2: bravo,P1: alpha,P3: charlie,P4: delta,P5: echo" ] && { echo "  ✓ project.json queue reordered"; PASS=$((PASS+1)); } || { echo "  ✗ queue order wrong: $ORDER"; FAIL=$((FAIL+1)); }
assert_contains "ROADMAP view re-rendered in the new order" "P2: bravo" "$(cat .gos/project/ROADMAP.md 2>/dev/null)"
RM=$(node -e "
const fs = require('fs');
const t = fs.readFileSync('.gos/project/ROADMAP.md', 'utf8');
console.log(t.indexOf('P2: bravo') < t.indexOf('P1: alpha') ? 'front' : 'back')")
[ "$RM" = "front" ] && { echo "  ✓ ROADMAP rows follow the new queue order"; PASS=$((PASS+1)); } || { echo "  ✗ ROADMAP order stale"; FAIL=$((FAIL+1)); }

# ===== index source + --expect happy path =====
set +e; OUT=$(node "$GOS" phase move 2 4 --expect 2 2>&1); RC=$?; set -e
assert_exit "index move with matching --expect exits 0" 0 "$RC"
assert_contains "contract line names the moved phase" "✓ Phase moved: P3: charlie (index 2 → 4)" "$OUT"

# ===== --expect stale-advice guard =====
set +e; OUT=$(node "$GOS" phase move 3 0 --expect 1 2>&1); RC=$?; set -e
assert_exit "mismatched --expect refuses" 1 "$RC"
assert_contains "expect guard names the actual index" "refused --expect guard: phase sits at index 3, advice said 1" "$OUT"
set +e; OUT=$(node "$GOS" phase move 3 0 --expect x 2>&1); RC=$?; set -e
assert_exit "non-integer --expect refuses" 1 "$RC"
assert_contains "expect guard shape error" "wants a phase index (non-negative integer) — got 'x'" "$OUT"

# ===== active-source refusal: in-flight work pins its position =====
node "$GOS" phase mark-done 0 >/dev/null 2>&1
node "$GOS" phase claim 1 >/dev/null 2>&1
ACT=$(node -e "console.log(require('./.gos/project/project.json').phases.map((p) => p.status).join(','))")
[ "$ACT" = "done,active,pending,pending,pending" ] && { echo "  ✓ fixture: one done, one active (claimed), three pending"; PASS=$((PASS+1)); } || { echo "  ✗ fixture shape wrong: $ACT"; FAIL=$((FAIL+1)); }
set +e; OUT=$(node "$GOS" phase move 1 4 2>&1); RC=$?; set -e
assert_exit "moving the active phase refuses" 1 "$RC"
assert_contains "active refusal names the pinned position" "refused — phase is active (claimed by in-flight state; its roadmap position is pinned until the task closes)" "$OUT"
# a destination slot holding the active phase is legal — only the SOURCE must not be active
set +e; OUT=$(node "$GOS" phase move 2 1 2>&1); RC=$?; set -e
assert_exit "moving into a slot above the active phase exits 0" 0 "$RC"

# ===== argument-shape errors =====
set +e; OUT=$(node "$GOS" phase move 2 x 2>&1); RC=$?; set -e
assert_exit "non-integer target index refuses" 1 "$RC"
assert_contains "target shape error is actionable" "target index must be a non-negative integer — got 'x'" "$OUT"
set +e; OUT=$(node "$GOS" phase move 9 0 2>&1); RC=$?; set -e
assert_exit "source out of range refuses" 1 "$RC"
assert_contains "source range error maps the queue" "phase '9' not found — valid range: 0-4" "$OUT"
set +e; OUT=$(node "$GOS" phase move 0 9 2>&1); RC=$?; set -e
assert_exit "target out of range refuses" 1 "$RC"
assert_contains "target range error names the valid span" "target index 9 out of range (valid: 0-4)" "$OUT"
set +e; OUT=$(node "$GOS" phase move 2>&1); RC=$?; set -e
assert_exit "missing target argument refuses" 1 "$RC"
assert_contains "usage line names both arguments" "Usage: gos phase move <from> <to>" "$OUT"

# ambiguous prefix: two phases share the letter p — full names differ, prefix collides
set +e; OUT=$(node "$GOS" phase move p 0 2>&1); RC=$?; set -e
assert_exit "ambiguous name prefix refuses" 1 "$RC"
assert_contains "ambiguity error lists the candidates" "ambiguous phase prefix 'p'" "$OUT"

# ===== P0-named phase lands at index 0 (monotonic head of the queue) =====
node "$GOS" phase rename 4 "P0: zero" --expect "P3: charlie" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" phase move P0 0 2>&1); RC=$?; set -e
assert_exit "moving the P0-named phase to the head exits 0" 0 "$RC"
assert_contains_f "queue table puts P0 at index 0" "| 0 | P0: zero | goal three | pending |" "$OUT"
HEAD=$(node -e "
const p = require('./.gos/project/project.json');
console.log([p.phases[0].name, p.phases[0].status].join('|'))")
[ "$HEAD" = "P0: zero|pending" ] && { echo "  ✓ P0-named phase holds index 0 with status untouched"; PASS=$((PASS+1)); } || { echo "  ✗ head wrong: $HEAD"; FAIL=$((FAIL+1)); }

# ===== surface wiring =====
OUT=$(node "$GOS" phase 2>&1)
assert_contains "phase usage block lists move" "move <from> <to>" "$OUT"
OUT=$(node "$GOS" help phase 2>&1)
assert_contains_f "help page documents move with its expect guard" "move <from> <to> [--expect" "$OUT"

t115_teardown
echo "--- T115 done: PASS=$PASS FAIL=$FAIL ---"
[ "$FAIL" -eq 0 ] || exit 1
