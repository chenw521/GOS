#!/usr/bin/env bash
# gos-map:fn bin/lib/task/changelog.cjs#fn:cmdChangelogLint bin/lib/ops/gate.cjs#fn:changelogObligationLeg
# gos-map:cmd changelog,gate
# gos changelog lint — post-hoc format enforcement over CHANGELOG.md.
# Covers: structural format checks (single title / newest-first dates /
# undated version headings) exit 1 individually; missing-file semantics =
# advisory + exit 0 (obligations start once the file exists; `gos changelog
# add` bootstraps it); clock-free verdicts (stale-stamped-only docs pass —
# the batch-record obligation lives in the gate leg, not in lint);
# discriminant — [Unreleased] entries get full validateEntry (generated
# zone), versioned sections structural checks only (promote products +
# history zone); verdict equivalence with changelog-core (G-suite harness
# recomputes the core verdict and pins keyword + exit-code agreement
# against the CLI). The O-suite drives `gate changelog-obligation` — the
# read-mode structural obligation over a base..head range — through its
# named verdicts (unborn / zero-parent / shallow / non-git / no task ids /
# no-new-bullet / deleted / unmatched refs).
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

# ===== S3: stale-stamped bullets only — lint is clock-free, exit 0 (state present) =====
t55_new
printf '# Log\n\n## [Unreleased]\n\n- Add stale bullet (D-42) [2026-01-01]\n\n## [1.0.0] - 2026-01-01\n\n- Add old release (D-1)\n' > CHANGELOG.md
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "S3 stale-only doc rc (clock obligation retired)" 0 "$RC"
assert_contains "S3 clean summary rendered" "clean" "$OUT"
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

# ===== D: no state (CI) — stale-only doc stays clean, zero obligation copy =====
t55_bare
printf '# Log\n\n## [Unreleased]\n\n- Add stale bullet (D-42) [2026-01-01]\n\n## [1.0.0] - 2026-01-01\n\n- Add old release (D-1)\n' > CHANGELOG.md
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "D1 no-state stale-only rc (clock-free)" 0 "$RC"
if printf '%s' "$OUT" | grep -q "obligation"; then echo "  ✗ D1 obligation copy leaked into lint"; FAIL=$((FAIL+1)); else echo "  ✓ D1 lint output carries no obligation copy"; PASS=$((PASS+1)); fi
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
# same way cmdChangelogLint does: validateStructure(text) with no date input
# (format-only), then validateEntry on every parsed [Unreleased] entry. Each
# fixture isolates one failure class (plus clean files) inside a
# state-present sandbox. Agreement is pinned per fixture — the class keyword
# sits in the core's first violation AND in the CLI output, and the CLI exit
# code equals the core verdict code.
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

# ===== G4: stale-only doc — both verdicts clean (clock obligation retired) =====
t55_new
printf '# Log\n\n## [Unreleased]\n\n- Add stale bullet (D-42) [2026-01-01]\n\n## [1.0.0] - 2026-01-01\n\n- Add old release (D-1)\n' > CHANGELOG.md
set +e; CORE_OUT="$(t55_core_verdict 2>&1)"; CORE_RC=$?; CLI_OUT="$(node "$GOS" changelog lint 2>&1)"; CLI_RC=$?; set -e
assert_exit "G4 core clean on stale-only doc" 0 "$CORE_RC"
assert_contains "G4 core verdict reports clean" "clean: zero violations" "$CORE_OUT"
assert_exit "G4 CLI clean on stale-only doc" 0 "$CLI_RC"
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

# ===== O: gate changelog-obligation — read-mode structural obligation =====
# Each named verdict gets its own fixture; the loud exempt/degraded lines are
# part of the contract (never silent skips). Repos stay bare (no gos state)
# unless a case needs one — statelessness itself pins the degraded refs line.

# O1: fresh uncommitted bullet vs the HEAD^1 baseline -> pass + degraded refs
# (three commits so HEAD^1 actually holds the baseline changelog content)
t55_bare
printf '# Log\n\n## [Unreleased]\n\n- Add baseline bullet (D-42) [2026-01-01]\n' > CHANGELOG.md
git add CHANGELOG.md && git commit -q -m base-changelog
git commit -q --allow-empty -m other-change
printf '# Log\n\n## [Unreleased]\n\n- Add fresh bullet (D-42) [%s]\n- Add baseline bullet (D-42) [2026-01-01]\n' "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" gate changelog-obligation 2>&1); RC=$?; set -e
assert_exit "O1 fresh bullet passes" 0 "$RC"
assert_contains "O1 pass line names the obligation" "changelog obligation: batch adds a changelog record" "$OUT"
assert_contains "O1 refs filter degraded is loud" "refs filter degraded (no task ids)" "$OUT"
t55_teardown

# O2: changelog identical at base and head -> fail naming no-new-bullet
t55_bare
printf '# Log\n\n## [Unreleased]\n\n- Add settled bullet (D-42) [2026-01-01]\n' > CHANGELOG.md
git add CHANGELOG.md && git commit -q -m base-changelog
touch unrelated.txt && git add unrelated.txt && git commit -q -m other-change
set +e; OUT=$(node "$GOS" gate changelog-obligation 2>&1); RC=$?; set -e
assert_exit "O2 no-new-bullet fails" 1 "$RC"
assert_contains "O2 verdict names no-new-bullet" "no-new-bullet" "$OUT"
assert_contains "O2 fix tells to write the record" "write the batch record" "$OUT"
t55_teardown

# O3: unborn repo (no commits) -> exempt with the named line
T55_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t55"; mkdir -p "$T55_DIR" && cd "$T55_DIR" || exit 1
git init -q .
set +e; OUT=$(node "$GOS" gate changelog-obligation 2>&1); RC=$?; set -e
assert_exit "O3 unborn base exempt rc" 0 "$RC"
assert_contains "O3 unborn exempt line" "changelog obligation: exempt (unborn base)" "$OUT"
t55_teardown

# O4: root commit as base (zero parents, full history) -> exempt with the named line
T55_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t55"; mkdir -p "$T55_DIR" && cd "$T55_DIR" || exit 1
git init -q . && git commit -q --allow-empty -m root-only
set +e; OUT=$(node "$GOS" gate changelog-obligation 2>&1); RC=$?; set -e
assert_exit "O4 zero-parent base exempt rc" 0 "$RC"
assert_contains "O4 zero-parent exempt line" "changelog obligation: exempt (zero-parent base)" "$OUT"
t55_teardown

# O5: shallow clone (depth 1 of a 2-commit repo) -> fail-closed naming the fix
T55_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t55"; mkdir -p "$T55_DIR" && cd "$T55_DIR" || exit 1
git init -q . && git commit -q --allow-empty -m one && git commit -q --allow-empty -m two
SRC="$T55_DIR"; cd "$TESTBASE" || exit 1
rm -rf t55-shallow && git clone -q --depth 1 "file://$SRC" t55-shallow && cd t55-shallow
set +e; OUT=$(node "$GOS" gate changelog-obligation 2>&1); RC=$?; set -e
assert_exit "O5 shallow clone fails closed" 1 "$RC"
assert_contains "O5 verdict names the shallow cause" "shallow" "$OUT"
assert_contains "O5 fix names the escape hatch" "GOS_CHANGELOG_BASE" "$OUT"
cd "$TESTBASE" && rm -rf t55-shallow
t55_teardown

# O6a: non-git tree, [Unreleased] holds a bullet -> file-shape fallback passes
T55_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t55"; mkdir -p "$T55_DIR/.gos" && cd "$T55_DIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TESTBASE"
printf '# Log\n\n## [Unreleased]\n\n- Add nongit bullet (D-42) [2026-01-01]\n' > CHANGELOG.md
set +e; OUT=$(node "$GOS" gate changelog-obligation 2>&1); RC=$?; set -e
unset GIT_CEILING_DIRECTORIES
assert_exit "O6a non-git file-shape pass rc" 0 "$RC"
assert_contains "O6a fallback line names file-shape" "file-shape fallback, non-git tree" "$OUT"
t55_teardown

# O6b: non-git tree, empty [Unreleased] -> file-shape fallback fails
T55_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t55"; mkdir -p "$T55_DIR/.gos" && cd "$T55_DIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TESTBASE"
printf '# Log\n\n## [Unreleased]\n' > CHANGELOG.md
set +e; OUT=$(node "$GOS" gate changelog-obligation 2>&1); RC=$?; set -e
unset GIT_CEILING_DIRECTORIES
assert_exit "O6b non-git empty unreleased rc" 1 "$RC"
assert_contains "O6b verdict names unreleased-nonempty" "unreleased-nonempty" "$OUT"
t55_teardown

# O7: live task without task_head -> fail-closed with re-claim guidance
t55_new
python3 -c "
import json
s=json.load(open('.gos/state.json'))
s.pop('task_head', None); s.pop('task_head_pending', None)
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" gate changelog-obligation 2>&1); RC=$?; set -e
assert_exit "O7 missing task_head fails closed" 1 "$RC"
assert_contains "O7 verdict names the missing baseline" "no task_head" "$OUT"
assert_contains "O7 fix carries re-claim guidance" "re-claim the task" "$OUT"
t55_teardown

# O8: state ids present and the fresh bullet misses them all -> unmatched refs
t55_new
node "$GOS" decision add D-07 "refs filter probe" >/dev/null 2>&1
printf '# Log\n\n## [Unreleased]\n\n- Add mismatched refs bullet (D-99) [%s]\n' "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" gate changelog-obligation 2>&1); RC=$?; set -e
assert_exit "O8 unmatched task refs fail" 1 "$RC"
assert_contains "O8 verdict names task-refs-unmatched" "task-refs-unmatched" "$OUT"
if printf '%s' "$OUT" | grep -q "refs filter degraded"; then echo "  ✗ O8 ids were present but the filter read degraded"; FAIL=$((FAIL+1)); else echo "  ✓ O8 refs filter stayed armed (ids parsed)"; PASS=$((PASS+1)); fi
t55_teardown

# O9: changelog deleted after existing at base -> deletion is not a record
t55_bare
printf '# Log\n\n## [Unreleased]\n\n- Add doomed bullet (D-42) [2026-01-01]\n' > CHANGELOG.md
git add CHANGELOG.md && git commit -q -m base-changelog
touch unrelated.txt && git add unrelated.txt && git commit -q -m other-change
rm CHANGELOG.md
set +e; OUT=$(node "$GOS" gate changelog-obligation 2>&1); RC=$?; set -e
assert_exit "O9 deleted changelog fails closed" 1 "$RC"
assert_contains "O9 verdict names the deletion" "gone from the head" "$OUT"
t55_teardown

# O10: --head pins the checked snapshot (explicit base and head refs)
t55_bare
printf '# Log\n\n## [Unreleased]\n\n- Add baseline bullet (D-42) [2026-01-01]\n' > CHANGELOG.md
git add CHANGELOG.md && git commit -q -m base-changelog
printf '# Log\n\n## [Unreleased]\n\n- Add ranged bullet (D-42) [%s]\n- Add baseline bullet (D-42) [2026-01-01]\n' "$TODAY" > CHANGELOG.md
git add CHANGELOG.md && git commit -q -m head-changelog
BASE_SHA="$(git rev-parse HEAD^1)"; HEAD_SHA="$(git rev-parse HEAD)"
set +e; OUT=$(node "$GOS" gate changelog-obligation --base "$BASE_SHA" --head "$HEAD_SHA" 2>&1); RC=$?; set -e
assert_exit "O10 explicit base/head range passes" 0 "$RC"
assert_contains "O10 head names the pinned ref" "head $HEAD_SHA" "$OUT"
set +e; OUT=$(node "$GOS" gate changelog-obligation --base "$HEAD_SHA" --head "$HEAD_SHA" 2>&1); RC=$?; set -e
assert_exit "O10b empty range fails (no-new-bullet)" 1 "$RC"
t55_teardown

# O11: bad --base value -> fail-closed, never a silent vacuous pass
t55_bare
git commit -q --allow-empty -m seed2
printf '# Log\n\n## [Unreleased]\n\n- Add probe bullet (D-42) [%s]\n' "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" gate changelog-obligation --base deadbeefcafe 2>&1); RC=$?; set -e
assert_exit "O11 unresolvable base fails closed" 1 "$RC"
assert_contains "O11 verdict names base-unresolved" "changelog-obligation-base-unresolved" "$OUT"
t55_teardown

# ===== X: usage seam mentions lint =====
set +e; OUT=$(node "$GOS" changelog 2>&1); RC=$?; set -e
assert_exit "X1 bare changelog usage rc" 1 "$RC"
assert_contains "X1 usage lists lint" "lint" "$OUT"

# ===== Z: product source zero CJK =====
# Z1 pins a static source fact — the product module carries zero CJK
# characters. The boundary has no CLI surface to observe from a sandbox, so
# the assertion stays at source level by design (structural source contract).
CJK_HITS="$(grep -rlP '[\x{4e00}-\x{9fff}]' "$GOS_ROOT/bin/lib/task/changelog.cjs" 2>/dev/null || true)"
if [ -z "$CJK_HITS" ]; then echo "  ✓ Z1 module source contains zero CJK"; PASS=$((PASS+1)); else echo "  ✗ Z1 CJK found: $CJK_HITS"; FAIL=$((FAIL+1)); fi

echo "--- T55 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
