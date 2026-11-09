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
# only (promote products + history zone); verdict equivalence with
# changelog-core (G-suite harness recomputes the core verdict and pins
# keyword + exit-code agreement against the CLI).
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

# ===== G: verdict equivalence — the lint verdict IS the changelog-core verdict =====
# The harness requires changelog-core directly and recomputes the verdict the
# same way cmdChangelogLint does: validateStructure(text) with the default
# today source, then validateEntry on every parsed [Unreleased] entry. Each
# fixture isolates one failure class (plus one clean file) inside a
# state-present sandbox, so the today-obligation stays hard; agreement is
# pinned per fixture — the class keyword sits in the core's first violation
# AND in the CLI output, and the CLI exit code equals the core verdict code.
t55_core_verdict() {
  node -e '
    const fs = require("node:fs");
    const clcore = require(process.env.GOS_ROOT + "/bin/lib/ops/changelog-core.cjs");
    const text = fs.readFileSync("CHANGELOG.md", "utf8");
    const violations = [];
    for (const e of clcore.validateStructure(text).errors) violations.push(e);
    const parsed = clcore.parseChangelog(text);
    for (const entry of parsed.unreleased) {
      for (const e of clcore.validateEntry(entry).errors) violations.push(e);
    }
    if (violations.length) { console.log(violations[0]); process.exit(1); }
    console.log("clean: zero violations");
    process.exit(0);
  '
}

# ===== G1: duplicate top-level titles =====
t55_new
printf '# Alpha log\n\n# Beta log\n\n## [Unreleased]\n\n- Add today bullet one (D-42) [%s]\n' "$TODAY" > CHANGELOG.md
set +e; CORE_OUT="$(t55_core_verdict 2>&1)"; CORE_RC=$?; CLI_OUT="$(node "$GOS" changelog lint 2>&1)"; CLI_RC=$?; set -e
assert_exit "G1 core flags duplicate title" 1 "$CORE_RC"
assert_contains "G1 core first violation names title" "title" "$CORE_OUT"
assert_contains "G1 CLI output names title" "title" "$CLI_OUT"
assert_eq "G1 CLI rc equals core verdict rc" "$CORE_RC" "$CLI_RC"
t55_teardown

# ===== G2: version dates not newest-first =====
t55_new
printf '# Log\n\n## [Unreleased]\n\n- Add today bullet one (D-42) [%s]\n\n## [1.0.0] - 2026-01-01\n\n- Add first release (D-1)\n\n## [1.1.0] - 2026-02-01\n\n- Add second release (D-2)\n' "$TODAY" > CHANGELOG.md
set +e; CORE_OUT="$(t55_core_verdict 2>&1)"; CORE_RC=$?; CLI_OUT="$(node "$GOS" changelog lint 2>&1)"; CLI_RC=$?; set -e
assert_exit "G2 core flags date order" 1 "$CORE_RC"
assert_contains "G2 core first violation names newest-first" "newest-first" "$CORE_OUT"
assert_contains "G2 CLI output names newest-first" "newest-first" "$CLI_OUT"
assert_eq "G2 CLI rc equals core verdict rc" "$CORE_RC" "$CLI_RC"
t55_teardown

# ===== G3: version heading without a valid date =====
t55_new
printf '# Log\n\n## [Unreleased]\n\n- Add today bullet one (D-42) [%s]\n\n## [1.0.0]\n\n- Add undated release (D-1)\n' "$TODAY" > CHANGELOG.md
set +e; CORE_OUT="$(t55_core_verdict 2>&1)"; CORE_RC=$?; CLI_OUT="$(node "$GOS" changelog lint 2>&1)"; CLI_RC=$?; set -e
assert_exit "G3 core flags undated version" 1 "$CORE_RC"
assert_contains "G3 core first violation names valid date" "valid date" "$CORE_OUT"
assert_contains "G3 CLI output names valid date" "valid date" "$CLI_OUT"
assert_eq "G3 CLI rc equals core verdict rc" "$CORE_RC" "$CLI_RC"
t55_teardown

# ===== G4: today obligation unmet (state present, so it stays hard) =====
t55_new
printf '# Log\n\n## [Unreleased]\n\n- Add stale bullet (D-42) [2026-01-01]\n\n## [1.0.0] - 2026-01-01\n\n- Add old release (D-1)\n' > CHANGELOG.md
set +e; CORE_OUT="$(t55_core_verdict 2>&1)"; CORE_RC=$?; CLI_OUT="$(node "$GOS" changelog lint 2>&1)"; CLI_RC=$?; set -e
assert_exit "G4 core flags today obligation" 1 "$CORE_RC"
assert_contains "G4 core first violation names today's obligation" "today's obligation" "$CORE_OUT"
assert_contains "G4 CLI output names today's obligation" "today's obligation" "$CLI_OUT"
assert_eq "G4 CLI rc equals core verdict rc" "$CORE_RC" "$CLI_RC"
t55_teardown

# ===== G5: clean file — both verdicts exit 0 =====
t55_new
printf '# Log\n\n## [Unreleased]\n\n- Add today bullet one (D-42) [%s]\n- Fix second today bullet (R-06) [%s]\n\n## [1.0.0] - 2026-01-01\n\n- Add old release (D-1)\n' "$TODAY" "$TODAY" > CHANGELOG.md
set +e; CORE_OUT="$(t55_core_verdict 2>&1)"; CORE_RC=$?; CLI_OUT="$(node "$GOS" changelog lint 2>&1)"; CLI_RC=$?; set -e
assert_exit "G5 core clean rc" 0 "$CORE_RC"
assert_contains "G5 core verdict reports clean" "clean: zero violations" "$CORE_OUT"
assert_exit "G5 CLI clean rc" 0 "$CLI_RC"
assert_eq "G5 CLI rc equals core verdict rc" "$CORE_RC" "$CLI_RC"
t55_teardown

# ===== X: usage seam mentions lint =====
set +e; OUT=$(node "$GOS" changelog 2>&1); RC=$?; set -e
assert_exit "X1 bare changelog usage rc" 1 "$RC"
assert_contains "X1 usage lists lint" "lint" "$OUT"

# ===== Z: product source zero CJK =====
CJK_HITS="$(grep -rlP '[\x{4e00}-\x{9fff}]' "$GOS_ROOT/bin/lib/task/changelog.cjs" 2>/dev/null || true)"
if [ -z "$CJK_HITS" ]; then echo "  ✓ Z1 module source contains zero CJK"; PASS=$((PASS+1)); else echo "  ✗ Z1 CJK found: $CJK_HITS"; FAIL=$((FAIL+1)); fi

echo "--- T55 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
