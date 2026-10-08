#!/usr/bin/env bash
# gos-map:fn bin/lib/task/archive.cjs#fn:cmdArchive
# gos-map:cmd archive
# T57: ship/archive single-track — daily obligation reads CHANGELOG.md
# [Unreleased] (today UTC-stamped bullet, utcToday same-source), missing file
# blocks with the bootstrap advisory, .changes.md sealed read-only (mtime
# frozen across archive), delta.md gains user_summary from the task-scoped
# changelog cache (empty fallback), version warn stays git-tag sourced.
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner
T57_DIR=""

gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }

t57_new() {
  T57_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t57"
  mkdir -p "$T57_DIR" && cd "$T57_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t57-seed
  node "$GOS" init 3 "t57 single track ship gate" >/dev/null 2>&1
}

# state → archivable (DONE + approved + spec materialized)
t57_ready() {
  python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='DONE'; s['approvals']={'ARCHIVE':'ok'}; s['spec_path']='\"$(gos_spec)\"'
json.dump(s,open('.gos/state.json','w'),indent=2)"
  echo spec > "$(gos_spec)"
}

t57_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T57_DIR"; }

PASS=0; FAIL=0
echo "--- T57: archive single-track (CHANGELOG.md obligation + sealed .changes.md) ---"
TODAY="$(date -u +%F)"
YESTERDAY="$(date -u -d yesterday +%F)"
TODAY_CORE="$(node -e "console.log(require('$GOS_ROOT/bin/lib/ops/changelog-core.cjs').utcToday())" 2>/dev/null || true)"

# ===== G: gate — fail-closed on the single-track obligation =====
t57_new
t57_ready
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "G1 missing CHANGELOG.md blocks archive" 1 "$RC"
assert_contains "G1 SHIP BLOCKED prefix" "SHIP BLOCKED" "$OUT"
assert_contains "G1 bootstrap advisory points to gos changelog add" "gos changelog add" "$OUT"
printf '# Changelog\n\n## [Unreleased]\n\n- Test stale stamp (R-01) [%s]\n' "$YESTERDAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "G2 yesterday-stamped bullet blocks archive" 1 "$RC"
assert_contains "G2 block names the stamp obligation" "stamped" "$OUT"
assert_contains "G2 block tells the fix command" "gos changelog add" "$OUT"
printf '# Changelog\n\n## [Unreleased]\n\n## [0.1.0] - %s\n\n- Test released today (R-01) [%s]\n' "$TODAY" "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "G3 today bullet in a version section (not Unreleased) still blocks" 1 "$RC"
t57_teardown

# ===== P: today-stamped [Unreleased] bullet → gate passes + version warn rides along =====
t57_new
t57_ready
printf '# Changelog\n\n## [Unreleased]\n\n- Test gate pass (R-01) [%s]\n' "$TODAY_CORE" > CHANGELOG.md
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "P1 today-stamped Unreleased bullet passes archive" 0 "$RC"
assert_contains "P1 version discipline warn on success path" "version discipline" "$OUT"
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
