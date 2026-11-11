#!/usr/bin/env bash
# gos-map:fn bin/lib/knowledge/phase.cjs#fn:cmdPhase
# gos-map:cmd phase
# phase rename — pending-only name rewrite with grammar/collision guards and
# the --expect mis-target guard (edit-via-commands discipline)
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
T111_DIR=""

t111_setup() {
  [ -n "$TESTBASE" ] || TESTBASE="$(mktemp -d)"
  T111_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t111"
  mkdir -p "$T111_DIR" && cd "$T111_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  # sandbox queue: idx0 done, idx1 active, idx2 parked, idx3 and idx4 pending
  node "$GOS" init --project 1 "t111 container" >/dev/null 2>&1
  node "$GOS" phase add "P1: alpha" --goal "fixture goal one" >/dev/null 2>&1
  node "$GOS" phase add "P2: bravo" --goal "fixture goal two" >/dev/null 2>&1
  node "$GOS" phase add "P3: charlie" --goal "fixture goal three" >/dev/null 2>&1
  node "$GOS" phase add "P4: delta" --goal "fixture goal four" >/dev/null 2>&1
  node "$GOS" phase add "P5: echo" --goal "fixture goal five" >/dev/null 2>&1
  node "$GOS" phase mark-done 0 >/dev/null 2>&1
  node "$GOS" phase claim 1 >/dev/null 2>&1
  node "$GOS" phase park 2 --reason "fixture deferral" >/dev/null 2>&1
}

t111_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T111_DIR"; }

t111_setup
echo "--- T111: phase rename ---"

# --- (a) status refusals: active / done / parked (frozen contract text) ---
set +e; OUT=$(node "$GOS" phase rename 1 "P8: xray" 2>&1); RC=$?; set -e
assert_exit "T111.a1 rename active phase exits 1" 1 "$RC"
assert_contains "T111.a2 active refusal carries contract" "refused — phase is active" "$OUT"
set +e; OUT=$(node "$GOS" phase rename 0 "P8: xray" 2>&1); RC=$?; set -e
assert_exit "T111.a3 rename done phase exits 1" 1 "$RC"
assert_contains "T111.a4 done refusal carries contract" "refused — phase is done" "$OUT"
set +e; OUT=$(node "$GOS" phase rename 2 "P8: xray" 2>&1); RC=$?; set -e
assert_exit "T111.a5 rename parked phase exits 1" 1 "$RC"
assert_contains "T111.a6 parked refusal carries contract" "refused — phase is parked" "$OUT"

# --- (b) collision refusals: equality + prefix both directions, any status ---
set +e; OUT=$(node "$GOS" phase rename 3 "P1: alpha" 2>&1); RC=$?; set -e
assert_exit "T111.b1 equal-to-done-phase collision exits 1" 1 "$RC"
assert_contains "T111.b2 collision contract fires" "refused — new name collides" "$OUT"
set +e; OUT=$(node "$GOS" phase rename 3 "P5: echo suffix" 2>&1); RC=$?; set -e
assert_exit "T111.b3 new-starts-with-existing collision exits 1" 1 "$RC"
assert_contains "T111.b4 collision names the blocker" "P5: echo" "$OUT"
set +e; OUT=$(node "$GOS" phase rename 3 "P5: e" 2>&1); RC=$?; set -e
assert_exit "T111.b5 existing-starts-with-new collision exits 1" 1 "$RC"
set +e; OUT=$(node "$GOS" phase rename 3 "P1: alpha prime" 2>&1); RC=$?; set -e
assert_exit "T111.b6 prefix collision against a done phase exits 1" 1 "$RC"
assert_contains "T111.b7 done-phase collision names the blocker" "P1: alpha" "$OUT"
set +e; OUT=$(node "$GOS" phase rename 3 "P4: delta extended" 2>&1); RC=$?; set -e
assert_exit "T111.b8 extension of own current name exits 1" 1 "$RC"

# --- (c) grammar refusals: shape / length / newline ---
set +e; OUT=$(node "$GOS" phase rename 3 "Q7: nope" 2>&1); RC=$?; set -e
assert_exit "T111.c1 non-P prefix exits 1" 1 "$RC"
assert_contains "T111.c2 shape contract fires" "refused — name must keep" "$OUT"
T111_LONG="P4: $(printf 'a%.0s' $(seq 80))"
set +e; OUT=$(node "$GOS" phase rename 3 "$T111_LONG" 2>&1); RC=$?; set -e
assert_exit "T111.c3 over-80-codepoint name exits 1" 1 "$RC"
assert_contains "T111.c4 length contract fires" "refused — name exceeds" "$OUT"
T111_NL="$(printf 'P4: two\nlines')"
set +e; OUT=$(node "$GOS" phase rename 3 "$T111_NL" 2>&1); RC=$?; set -e
assert_exit "T111.c5 newline in name exits 1" 1 "$RC"
assert_contains "T111.c6 control-character rejection fires" "name rejected" "$OUT"

# --- (d) --expect mis-target guard ---
set +e; OUT=$(node "$GOS" phase rename 3 "P9: zulu" --expect "P0: stale" 2>&1); RC=$?; set -e
assert_exit "T111.d1 --expect mismatch exits 1" 1 "$RC"
assert_contains "T111.d2 mismatch contract fires" "refused — --expect mismatch" "$OUT"
assert_contains "T111.d3 mismatch names the actual target" "P4: delta" "$OUT"

# --- (e) success: pending rename applies, old→new printed, views re-rendered ---
set +e; OUT=$(node "$GOS" phase rename 3 "P9: zulu" --expect "P4: delta" 2>&1); RC=$?; set -e
assert_exit "T111.e1 rename pending phase exits 0" 0 "$RC"
assert_contains "T111.e2 old→new printed" "✓ Phase renamed: P4: delta → P9: zulu" "$OUT"
OUT=$(node "$GOS" phase list 2>&1)
assert_contains "T111.e3 list shows the new name" "P9: zulu" "$OUT"
if echo "$OUT" | grep -q "P4: delta"; then echo "  ✗ T111.e4 old name gone from list"; FAIL=$((FAIL+1)); else echo "  ✓ T111.e4 old name gone from list"; PASS=$((PASS+1)); fi
assert_contains "T111.e5 project.json carries the new name" "P9: zulu" "$(cat .gos/project/project.json 2>/dev/null)"
assert_contains "T111.e6 ROADMAP view re-rendered with new name" "P9: zulu" "$(cat .gos/project/ROADMAP.md 2>/dev/null)"

# --- (f) usage + help surfaces ---
OUT=$(node "$GOS" phase 2>&1)
assert_contains "T111.f1 phase usage block lists rename" "rename" "$OUT"
OUT=$(node "$GOS" help phase 2>&1)
assert_contains "T111.f2 help phase shows rename" "rename" "$OUT"

t111_teardown
echo "--- T111 done: PASS=$PASS FAIL=$FAIL ---"
[ "$FAIL" -eq 0 ] || exit 1
