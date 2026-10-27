#!/usr/bin/env bash
# gos-map:fn bin/lib/task/changelog.cjs#fn:cmdChangelogLint
# gos-map:cmd changelog
# gos changelog lint — post-hoc enforcement over CHANGELOG.md.
# Covers: structural three-checks (single title / newest-first dates /
# today's obligation) exit 1 individually; missing-file semantics = advisory +
# exit 0 (obligations start once the file exists; `gos changelog add` bootstraps
# it); no-state (CI) downgrade of the today-obligation to advisory while
# other checks stay enforced; discriminant — [Unreleased] entries get
# full validateEntry (generated zone), versioned sections structural checks
# only (promote products + history zone); same-source consumption of
# changelog-core (require-source grep, no drift).
T55_DIR=""

t55_new() {
  T55_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t55"
  mkdir -p "$T55_DIR" && cd "$T55_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t55-seed
  GOS_HEADLESS=1 node "$GOS" init 3 "t55 changelog lint" >/dev/null 2>&1
}

t55_bare() {
  T55_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t55"
  mkdir -p "$T55_DIR" && cd "$T55_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t55-seed
}

t55_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T55_DIR"; }

PASS=0; FAIL=0
echo "--- T55: gos changelog lint (post-hoc enforcement) ---"

# Single UTC time source for fixture stamps (same function the command uses).
TODAY="$(node -e "console.log(require('$GOS_ROOT/bin/lib/ops/changelog-core.cjs').utcToday())" 2>/dev/null || true)"

# ===== S1: duplicate top-level titles -> exit 1 (state present, rest clean) =====
t55_new
printf '# Alpha log\n\n# Beta log\n\n## [Unreleased]\n\n- Add today bullet one (D-42) [%s]\n' "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "S1 duplicate title rc" 1 "$RC"
assert_contains "S1 duplicate title message" "title" "$OUT"
t55_teardown

# ===== S2: version dates not newest-first -> exit 1 =====
t55_new
printf '# Log\n\n## [Unreleased]\n\n- Add today bullet one (D-42) [%s]\n\n## [1.0.0] - 2026-01-01\n\n- Add first release (D-1)\n\n## [1.1.0] - 2026-02-01\n\n- Add second release (D-2)\n' "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "S2 date order rc" 1 "$RC"
assert_contains "S2 date order message" "newest-first" "$OUT"
t55_teardown

# ===== S2b: version heading without a valid date -> exit 1 =====
t55_new
printf '# Log\n\n## [Unreleased]\n\n- Add today bullet one (D-42) [%s]\n\n## [1.0.0]\n\n- Add undated release (D-1)\n' "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "S2b undated version rc" 1 "$RC"
assert_contains "S2b undated version message" "valid date" "$OUT"
t55_teardown

# ===== S3: today obligation unmet (state present) -> exit 1 =====
t55_new
printf '# Log\n\n## [Unreleased]\n\n- Add stale bullet (D-42) [2026-01-01]\n\n## [1.0.0] - 2026-01-01\n\n- Add old release (D-1)\n' > CHANGELOG.md
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "S3 today obligation rc (state)" 1 "$RC"
assert_contains "S3 today obligation message" "today's obligation" "$OUT"
t55_teardown

# ===== M: CHANGELOG.md missing -> advisory + exit 0 =====
t55_new
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "M1 missing file rc (with state)" 0 "$RC"
assert_contains "M1 missing file advisory" "advisory" "$OUT"
assert_contains "M1 bootstrap hint mentions add" "gos changelog add" "$OUT"
[ ! -f CHANGELOG.md ] && { echo "  ✓ M2 lint never creates the file"; PASS=$((PASS+1)); } || { echo "  ✗ M2 lint created CHANGELOG.md"; FAIL=$((FAIL+1)); }
t55_teardown
t55_bare
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "M3 missing file rc (no state)" 0 "$RC"
assert_contains "M3 missing file advisory" "advisory" "$OUT"
t55_teardown

# ===== D: no state (CI) -> today obligation downgrades to advisory =====
t55_bare
printf '# Log\n\n## [Unreleased]\n\n- Add stale bullet (D-42) [2026-01-01]\n\n## [1.0.0] - 2026-01-01\n\n- Add old release (D-1)\n' > CHANGELOG.md
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "D1 no-state today downgrade rc" 0 "$RC"
assert_contains "D1 downgrade mentions obligation" "today's obligation" "$OUT"
assert_contains "D1 downgrade is advisory" "advisory" "$OUT"
t55_teardown

# ===== D2: no state does NOT downgrade structural checks =====
t55_bare
printf '# Alpha log\n\n# Beta log\n\n## [Unreleased]\n\n- Add today bullet one (D-42) [%s]\n' "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "D2 no-state structural rc" 1 "$RC"
assert_contains "D2 no-state structural message" "title" "$OUT"
t55_teardown

# ===== U1: bad [Unreleased] entry -> exit 1, entry quoted with file:line =====
t55_new
printf '# Log\n\n## [Unreleased]\n\n- This entry breaks every rule T-9 (1) and then some [2026-01-01]\n- Add today bullet one (D-42) [%s]\n\n## [1.0.0] - 2026-01-01\n\n- Add old release (D-1)\n' "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "U1 unreleased bad entry rc" 1 "$RC"
assert_contains "U1 violation class surfaced" "structure:" "$OUT"
assert_contains "U1 entry text quoted" "This entry breaks every rule" "$OUT"
assert_contains "U1 file:line derivable" "CHANGELOG.md:5" "$OUT"
t55_teardown

# ===== U2: identical bad entry in a VERSION section -> NOT flagged =====
t55_new
printf '# Log\n\n## [Unreleased]\n\n- Add today bullet one (D-42) [%s]\n\n## [1.0.0] - 2026-01-01\n\n- This entry breaks every rule T-9 (1) and then some [2026-01-01]\n' "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "U2 versioned bad entry rc (history zone spared)" 0 "$RC"
if printf '%s' "$OUT" | grep -q "This entry breaks every rule"; then echo "  ✗ U2 versioned entry was entry-validated"; FAIL=$((FAIL+1)); else echo "  ✓ U2 versioned entry not entry-validated"; PASS=$((PASS+1)); fi
t55_teardown

# ===== W: clean file (state present) -> exit 0 with ok summary =====
t55_new
printf '# Log\n\n## [Unreleased]\n\n- Add today bullet one (D-42) [%s]\n- Fix second today bullet (R-06) [%s]\n\n## [1.0.0] - 2026-01-01\n\n- Add old release (D-1)\n' "$TODAY" "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "W1 clean rc" 0 "$RC"
assert_contains "W1 ok summary" "✓" "$OUT"
t55_teardown

# ===== G: same-source proof — lint shell requires changelog-core =====
if grep -q "changelog-core" "$GOS_ROOT/bin/lib/task/changelog.cjs"; then echo "  ✓ G1 lint consumes changelog-core (single validator, no drift)"; PASS=$((PASS+1)); else echo "  ✗ G1 changelog-core require missing from task shell"; FAIL=$((FAIL+1)); fi

# ===== X: usage seam mentions lint =====
set +e; OUT=$(node "$GOS" changelog 2>&1); RC=$?; set -e
assert_exit "X1 bare changelog usage rc" 1 "$RC"
assert_contains "X1 usage lists lint" "lint" "$OUT"

# ===== Z: product source zero CJK =====
CJK_HITS="$(grep -rlP '[\x{4e00}-\x{9fff}]' "$GOS_ROOT/bin/lib/task/changelog.cjs" 2>/dev/null || true)"
if [ -z "$CJK_HITS" ]; then echo "  ✓ Z1 module source contains zero CJK"; PASS=$((PASS+1)); else echo "  ✗ Z1 CJK found: $CJK_HITS"; FAIL=$((FAIL+1)); fi

echo "--- T55 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
