#!/usr/bin/env bash
# gos-map:fn bin/lib/task/archive.cjs#fn:cmdArchive
# gos-map:cmd archive
# ship/archive single-track — the SHIP ritual runs the structural batch
# predicate: CHANGELOG.md is compared against the task_head baseline (a
# just-written uncommitted bullet counts; stale date stamps written inside
# the batch count — the UTC-midnight rollover can no longer void a record;
# refs must intersect the task's own decision/requirement ids), missing file
# blocks with the bootstrap advisory, .changes.md sealed read-only (mtime
# frozen across archive), delta.md gains user_summary from the task-scoped
# changelog cache (empty fallback), version warn stays git-tag sourced, and
# a malformed (quoted) spec_path is rejected by commit think naming the
# stored path. Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers
# sourced by runner
T57_DIR=""

gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }

t57_new() {
  T57_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t57"
  mkdir -p "$T57_DIR" && cd "$T57_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t57-seed
  node "$GOS" init 3 "t57 single track ship gate" >/dev/null 2>&1
}

# changelog committed BEFORE the task anchors, so the task_head baseline
# already carries every bullet — the structural batch check sees no record
# until a new one is written inside the batch
t57_committed() {
  T57_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t57"
  mkdir -p "$T57_DIR" && cd "$T57_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t57-seed
  printf '# Changelog\n\n## [Unreleased]\n\n- Test committed baseline bullet (R-01) [2026-01-01]\n' > CHANGELOG.md
  git add CHANGELOG.md && git commit -q -m t57-changelog
  node "$GOS" init 3 "t57 ship structural" >/dev/null 2>&1
}

# state → archivable (DONE + approved + spec materialized)
# spec_path stores the unquoted gos_spec() return (the well-formed value the
# THINK gate and delta generation read); the quoted spelling is a malformed
# fixture consumed by the R-suite rejection scenario below.
t57_ready() {
  python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='DONE'; s['approvals']={'ARCHIVE':'ok'}; s['spec_path']='$(gos_spec)'
json.dump(s,open('.gos/state.json','w'),indent=2)"
  echo spec > "$(gos_spec)"
}

t57_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T57_DIR"; }

PASS=0; FAIL=0
echo "--- T57: archive single-track (CHANGELOG.md obligation + sealed .changes.md) ---"
TODAY="$(date -u +%F)"
YESTERDAY="$(date -u -d yesterday +%F)"
TODAY_CORE="$(node -e "console.log(require('$GOS_ROOT/bin/lib/ops/changelog-core.cjs').utcToday())" 2>/dev/null || true)"

# ===== G: gate — fail-closed on the batch structural obligation =====
t57_new
t57_ready
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "G1 missing CHANGELOG.md blocks archive" 1 "$RC"
assert_contains "G1 SHIP BLOCKED prefix" "SHIP BLOCKED" "$OUT"
assert_contains "G1 bootstrap advisory points to gos changelog add" "gos changelog add" "$OUT"
# a bullet stamped yesterday but written inside this batch counts: the stamp
# is writer metadata, the record is the structural delta (UTC-midnight cure)
printf '# Changelog\n\n## [Unreleased]\n\n- Test stale stamp (R-01) [%s]\n' "$YESTERDAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "G2 yesterday-stamped bullet written in the batch passes" 0 "$RC"
assert_contains "G2 version discipline warn on success path" "version discipline" "$OUT"
t57_teardown

# ===== G3: promote-shaped new version section counts as the batch record =====
t57_new
t57_ready
printf '# Changelog\n\n## [Unreleased]\n\n## [0.1.0] - %s\n\n- Test released today (R-01) [%s]\n' "$TODAY" "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "G3 new version section satisfies the record obligation" 0 "$RC"
assert_contains "G3 version discipline warn on success path" "version discipline" "$OUT"
t57_teardown

# ===== N: structural baseline — task_head snapshot vs working tree =====
# N1: every bullet already sits in the task_head baseline -> no record, blocked
t57_committed
t57_ready
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "N1 no-new-bullet blocks archive" 1 "$RC"
assert_contains "N1 SHIP BLOCKED prefix" "SHIP BLOCKED" "$OUT"
assert_contains "N1 verdict names the no-new-bullet reason" "no-new-bullet" "$OUT"
assert_contains "N1 fix names the writer command" "gos changelog add" "$OUT"
t57_teardown

# N2: a fresh uncommitted bullet appended on top of the baseline -> passes
t57_committed
t57_ready
printf '# Changelog\n\n## [Unreleased]\n\n- Test fresh batch bullet (R-01) [%s]\n- Test committed baseline bullet (R-01) [2026-01-01]\n' "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "N2 fresh uncommitted bullet passes archive" 0 "$RC"
assert_contains "N2 version discipline warn on success path" "version discipline" "$OUT"
t57_teardown

# N3: fresh bullet whose refs miss the task's id set -> blocked
t57_committed
t57_ready
printf '# Changelog\n\n## [Unreleased]\n\n- Test mismatched refs bullet (D-99) [%s]\n- Test committed baseline bullet (R-01) [2026-01-01]\n' "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "N3 task-refs-unmatched blocks archive" 1 "$RC"
assert_contains "N3 verdict names the unmatched refs reason" "task-refs-unmatched" "$OUT"
t57_teardown

# N4: live task without task_head -> blocked with re-claim guidance
t57_new
t57_ready
printf '# Changelog\n\n## [Unreleased]\n\n- Test task head probe (R-01) [%s]\n' "$TODAY" > CHANGELOG.md
python3 -c "
import json
s=json.load(open('.gos/state.json'))
s.pop('task_head', None); s.pop('task_head_pending', None)
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "N4 missing task_head blocks archive" 1 "$RC"
assert_contains "N4 block names the missing baseline" "no task_head" "$OUT"
assert_contains "N4 block carries re-claim guidance" "Re-claim the task" "$OUT"
t57_teardown

# ===== P: today-stamped [Unreleased] bullet → gate passes + version warn rides along =====
t57_new
t57_ready
printf '# Changelog\n\n## [Unreleased]\n\n- Test gate pass (R-01) [%s]\n' "$TODAY_CORE" > CHANGELOG.md
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "P1 today-stamped Unreleased bullet passes archive" 0 "$RC"
assert_contains "P1 version discipline warn on success path" "version discipline" "$OUT"
t57_teardown

# ===== R: malformed (quoted) spec_path -> commit think rejects it =====
# The spec file exists at the real path; only the stored spec_path value is
# malformed (embedded quotes), so the THINK artifact gate must fail on the
# value itself and name the stored path in the refusal — an unrelated gate
# failure cannot satisfy the path pin.
t57_new
SPEC="$(gos_spec)"
echo spec > "$SPEC"
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='THINK'; s['approvals']={'THINK':'ok'}; s['spec_path']='\"$SPEC\"'
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(GOS_HEADLESS=1 node "$GOS" commit think 2>&1); RC=$?; set -e
assert_exit "R1 commit think rejects malformed spec_path" 1 "$RC"
assert_contains "R1 refusal names the spec gate" "spec file not found:" "$OUT"
if printf '%s' "$OUT" | grep -qF "\"$SPEC\""; then echo "  ✓ R1 refusal names the quoted (never-existing) path"; PASS=$((PASS+1)); else echo "  ✗ R1 refusal does not name the quoted path"; FAIL=$((FAIL+1)); fi
t57_teardown

# ===== U: delta.md user_summary from the task-scoped changelog cache =====
t57_new
set +e; OUT=$(node "$GOS" changelog add --summary "wire the archive delta user summary" 2>&1); RC=$?; set -e
assert_exit "U1 changelog add rc (writes entry + caches summary)" 0 "$RC"
t57_ready
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "U2 archive passes on the add-written entry" 0 "$RC"
DST="$(ls -d .gos/archive/*/ 2>/dev/null | head -1)"
assert_file "U3 archive dest with delta.md exists" "${DST}delta.md"
if grep -q "user_summary" "${DST}delta.md" 2>/dev/null; then echo "  ✓ U4 delta.md carries the user_summary field"; PASS=$((PASS+1)); else echo "  ✗ U4 delta.md missing user_summary"; FAIL=$((FAIL+1)); fi
if grep -qF "wire the archive delta user summary" "${DST}delta.md" 2>/dev/null; then echo "  ✓ U5 cached summary value lands in delta.md"; PASS=$((PASS+1)); else echo "  ✗ U5 cached summary value missing in delta.md"; FAIL=$((FAIL+1)); fi
t57_teardown

# ===== E: empty-cache fallback — user_summary line present, empty value, no crash =====
t57_new
t57_ready
printf '# Changelog\n\n## [Unreleased]\n\n- Test empty cache fallback (R-01) [%s]\n' "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "E1 archive passes without cached summary" 0 "$RC"
DST="$(ls -d .gos/archive/*/ 2>/dev/null | head -1)"
if grep -qE '^- user_summary: *$' "${DST}delta.md" 2>/dev/null; then echo "  ✓ E2 empty user_summary line rendered (graceful fallback)"; PASS=$((PASS+1)); else echo "  ✗ E2 empty user_summary line missing: $(grep 'user_summary' "${DST}delta.md" 2>/dev/null || echo none)"; FAIL=$((FAIL+1)); fi
t57_teardown

# ===== S: .changes.md sealed — top note + mtime untouched by archive =====
# .changes.md is machine-local: assert seal wording only where the file exists
# (developer machines); fresh clones/CI legitimately have none.
if [ -f "$GOS_ROOT/.changes.md" ]; then
  if grep -q "SEALED (read-only archive)" "$GOS_ROOT/.changes.md" 2>/dev/null; then echo "  ✓ S1 repo .changes.md carries the seal note"; PASS=$((PASS+1)); else echo "  ✗ S1 seal note missing in repo .changes.md"; FAIL=$((FAIL+1)); fi
  if grep -qi "do not append" "$GOS_ROOT/.changes.md" 2>/dev/null; then echo "  ✓ S2 seal note forbids appending"; PASS=$((PASS+1)); else echo "  ✗ S2 seal note lacks the no-append instruction"; FAIL=$((FAIL+1)); fi
else
  echo "  ○ S1/S2 skipped: .changes.md is machine-local and absent here (fresh checkout)"
fi
t57_new
t57_ready
printf '# Changelog\n\n## [Unreleased]\n\n- Test mtime seal probe (R-01) [%s]\n' "$TODAY" > CHANGELOG.md
printf '# sealed history\n' > .changes.md
touch -d '2026-01-01 00:00:00 UTC' .changes.md
M1="$(stat -c %y .changes.md 2>/dev/null || true)"
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "S3 archive passes for mtime probe" 0 "$RC"
M2="$(stat -c %y .changes.md 2>/dev/null || true)"
assert_eq "S4 .changes.md mtime untouched by archive" "$M1" "$M2"
t57_teardown

# ===== X: GOS_SKIP_SHIP_CHECK=1 still bypasses the ritual gate =====
t57_new
t57_ready
set +e; OUT=$(GOS_SKIP_SHIP_CHECK=1 node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "X1 skip-env archive proceeds without CHANGELOG.md" 0 "$RC"
t57_teardown

# ===== V: source invariants — version warn keeps git-tag compare; zero .changes.md refs =====
if grep -q -- "--abbrev=0" "$GOS_ROOT/bin/lib/task/archive.cjs" 2>/dev/null; then echo "  ✓ V1 version-discipline warn still compares against git tags"; PASS=$((PASS+1)); else echo "  ✗ V1 git-tag comparison missing from archive.cjs"; FAIL=$((FAIL+1)); fi
if grep -q "changes\.md" "$GOS_ROOT/bin/lib/task/archive.cjs" 2>/dev/null; then echo "  ✗ V2 archive.cjs still references .changes.md (single-track violated)"; FAIL=$((FAIL+1)); else echo "  ✓ V2 archive.cjs carries zero .changes.md references"; PASS=$((PASS+1)); fi

echo "--- T57 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
