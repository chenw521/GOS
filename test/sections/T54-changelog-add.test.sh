#!/usr/bin/env bash
# gos-map:cmd changelog
# gos changelog add — single-track CHANGELOG.md entry generator.
# Covers: fail-closed gates (no-state / no-summary / validator), user_summary
# sources (--summary arg > state cache > TTY ask), template bootstrap,
# UTC-stamped bullet format (same-source with changelog-core), concurrent-safe
# write (dedicated O_EXCL lock, wait-not-die), .changes.md sealed (mtime frozen).
# NOTE: interactive-path cases use `env -u GOS_HEADLESS script -qec` to fabricate
# a pty and feed a line through it ( -u-init pattern); the rest of the
#       section runs headless (GOS_HEADLESS=1 pinned by the runner).
T54_DIR=""

t54_new() {
  T54_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t54"
  mkdir -p "$T54_DIR" && cd "$T54_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t54-seed
  GOS_HEADLESS=1 node "$GOS" init 3 "t54 changelog add" >/dev/null 2>&1
}

t54_bare() {
  T54_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t54"
  mkdir -p "$T54_DIR" && cd "$T54_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t54-seed
}

t54_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T54_DIR"; }

PASS=0; FAIL=0
echo "--- T54: gos changelog add (single-track generator) ---"

# ===== N: no active task state → fail-closed =====
t54_bare
set +e; OUT=$(node "$GOS" changelog add --summary "nowhere task" 2>&1); RC=$?; set -e
assert_exit "N1 no-state add rc" 1 "$RC"
assert_contains "N1 no-state message" "No active task" "$OUT"
[ ! -f CHANGELOG.md ] && { echo "  ✓ N2 nothing written without state"; PASS=$((PASS+1)); } || { echo "  ✗ N2 CHANGELOG.md created without state"; FAIL=$((FAIL+1)); }
t54_teardown

# ===== W: --summary happy path + bootstrap + format + cache =====
t54_new
[ ! -f CHANGELOG.md ] && { echo "  ✓ W1 CHANGELOG.md absent before add"; PASS=$((PASS+1)); } || { echo "  ✗ W1 CHANGELOG.md already exists"; FAIL=$((FAIL+1)); }
set +e; OUT=$(node "$GOS" changelog add --summary "wire the release notes generator" 2>&1); RC=$?; set -e
assert_exit "W2 add --summary rc" 0 "$RC"
assert_contains "W2 success line" "changelog entry written" "$OUT"
assert_file "W3 CHANGELOG.md created" "CHANGELOG.md"
if grep -q 'Keep a Changelog' CHANGELOG.md; then echo "  ✓ W4 bootstrapped from master template"; PASS=$((PASS+1)); else echo "  ✗ W4 template header missing"; FAIL=$((FAIL+1)); fi
if grep -qE '^- Add wire the release notes generator \(R-01\) \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]$' CHANGELOG.md; then echo "  ✓ W5 exact entry format (verb/summary/refs/stamp)"; PASS=$((PASS+1)); else echo "  ✗ W5 entry format mismatch: $(grep -E '^- ' CHANGELOG.md | head -1)"; FAIL=$((FAIL+1)); fi
if grep -A2 '^## \[Unreleased\]' CHANGELOG.md | grep -qF -- '- Add wire the release notes generator'; then echo "  ✓ W6 entry at top of [Unreleased]"; PASS=$((PASS+1)); else echo "  ✗ W6 entry not directly under [Unreleased]"; FAIL=$((FAIL+1)); fi
TODAY="$(node -e "console.log(require('$GOS_ROOT/bin/lib/ops/changelog-core.cjs').utcToday())" 2>/dev/null || true)"
if grep -qF "[$TODAY]" CHANGELOG.md; then echo "  ✓ W7 UTC stamp from the single time source"; PASS=$((PASS+1)); else echo "  ✗ W7 stamp [$TODAY] missing"; FAIL=$((FAIL+1)); fi
CACHE="$(python3 -c "import json;print(json.load(open('.gos/state.json')).get('changelog_user_summary',''))" 2>/dev/null || true)"
assert_eq "W8 summary cached in state.json" "wire the release notes generator" "$CACHE"
set +e; node -e "
const fs = require('fs');
const cc = require('$GOS_ROOT/bin/lib/ops/changelog-core.cjs');
const p = cc.parseChangelog(fs.readFileSync('CHANGELOG.md', 'utf8'));
if (!p.hasHeader || !p.hasUnreleasedHeading || p.unreleased.length !== 1) { console.log('BAD parse ' + JSON.stringify({h: p.hasHeader, u: p.hasUnreleasedHeading, n: p.unreleased.length})); process.exit(1); }
const bad = p.unreleased.filter((e) => !cc.validateEntry(e).ok);
if (bad.length) { console.log('REJECTED ' + bad.join(' | ')); process.exit(1); }
console.log('SAME-SOURCE OK');
" > w9.out 2>&1; W9RC=$?; set -e
assert_exit "W9 written entry passes the shared validator" 0 "$W9RC"
assert_contains "W9 same-source consumption" "SAME-SOURCE OK" "$(cat w9.out)"

# ===== C: task-scoped cache → second add needs no ask (headless, non-TTY) =====
set +e; OUT=$(node "$GOS" changelog add 2>&1); RC=$?; set -e
assert_exit "C1 cached second add rc (no ask)" 0 "$RC"
NB="$(grep -cE '^- Add ' CHANGELOG.md || true)"
assert_eq "C2 both entries present" "2" "$NB"
set +e; OUT=$(node "$GOS" changelog add --summary "newer distinct entry wins the arg" 2>&1); RC=$?; set -e
assert_exit "C3 arg overrides cache rc" 0 "$RC"
if grep -A2 '^## \[Unreleased\]' CHANGELOG.md | grep -qF -- '- Add newer distinct entry wins the arg'; then echo "  ✓ C4 newest entry inserted first"; PASS=$((PASS+1)); else echo "  ✗ C4 newest entry not on top"; FAIL=$((FAIL+1)); fi
t54_teardown

# ===== I: interactive TTY ask → caches → headless second add hits cache =====
t54_new
set +e
env -u GOS_HEADLESS bash -c "{ sleep 0.6; echo 'wired through the terminal prompt'; sleep 0.5; } | script -qec \"node '$GOS' changelog add\" /dev/null" >/dev/null 2>&1
IRC=$?
set -e
assert_exit "I1 interactive add rc (pty)" 0 "$IRC"
if grep -qF 'wired through the terminal prompt' CHANGELOG.md; then echo "  ✓ I2 entry written from the TTY answer"; PASS=$((PASS+1)); else echo "  ✗ I2 TTY answer never landed"; FAIL=$((FAIL+1)); fi
CACHE="$(python3 -c "import json;print(json.load(open('.gos/state.json')).get('changelog_user_summary',''))" 2>/dev/null || true)"
assert_eq "I3 ask result cached in state" "wired through the terminal prompt" "$CACHE"
set +e; OUT=$(node "$GOS" changelog add 2>&1); RC=$?; set -e
assert_exit "I4 second add headless cache-hit rc" 0 "$RC"
NB="$(grep -cE '^- Add ' CHANGELOG.md || true)"
assert_eq "I5 second add appended without asking" "2" "$NB"
t54_teardown

# ===== R: no summary + non-TTY (headless) → refuse, no fallback =====
t54_new
set +e; OUT=$(node "$GOS" changelog add 2>&1); RC=$?; set -e
assert_exit "R1 refusal rc" 1 "$RC"
assert_contains "R1 refusal message" "no user summary" "$OUT"
[ ! -f CHANGELOG.md ] && { echo "  ✓ R2 nothing written on refusal"; PASS=$((PASS+1)); } || { echo "  ✗ R2 CHANGELOG.md written despite refusal"; FAIL=$((FAIL+1)); }
t54_teardown

# ===== T: --type verb contract =====
t54_new
set +e; OUT=$(node "$GOS" changelog add --summary "repair the stamp parser" --type Fix 2>&1); RC=$?; set -e
assert_exit "T1 --type Fix rc" 0 "$RC"
if grep -qE '^- Fix repair the stamp parser \(R-01\) \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]$' CHANGELOG.md; then echo "  ✓ T2 verb override applied"; PASS=$((PASS+1)); else echo "  ✗ T2 verb override missing"; FAIL=$((FAIL+1)); fi
set +e; OUT=$(node "$GOS" changelog add --summary "bogus verb attempt" --type Makes 2>&1); RC=$?; set -e
assert_exit "T3 unknown verb rc" 1 "$RC"
assert_contains "T3 unknown verb message" "category verb" "$OUT"
NB="$(grep -cE '^- ' CHANGELOG.md || true)"
assert_eq "T4 rejected verb wrote nothing" "1" "$NB"
t54_teardown

# ===== F: trace refs — derivation (covered decisions + active reqs) and --refs =====
t54_new
node "$GOS" decision add D-07 "trace derivation probe" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" changelog add --summary "probe open decision exclusion" 2>&1); RC=$?; set -e
assert_exit "F1 open decision still adds rc" 0 "$RC"
if grep -qE '^- Add probe open decision exclusion \(R-01\) \[' CHANGELOG.md && ! grep -q 'D-07' CHANGELOG.md; then echo "  ✓ F2 open decision excluded from derived refs"; PASS=$((PASS+1)); else echo "  ✗ F2 open decision leaked into refs"; FAIL=$((FAIL+1)); fi
python3 -c "
import json
s = json.load(open('.gos/state.json'))
for d in s['decisions']:
    if d['id'] == 'D-07': d['status'] = 'covered'
json.dump(s, open('.gos/state.json', 'w'), indent=2)"
set +e; OUT=$(node "$GOS" changelog add --summary "probe covered inclusion" 2>&1); RC=$?; set -e
assert_exit "F3 covered decision adds rc" 0 "$RC"
if grep -qE '^- Add probe covered inclusion \(D-07/R-01\) \[' CHANGELOG.md; then echo "  ✓ F4 covered decision derived into refs"; PASS=$((PASS+1)); else echo "  ✗ F4 derived refs wrong: $(grep -E '^- ' CHANGELOG.md | head -2)"; FAIL=$((FAIL+1)); fi
set +e; OUT=$(node "$GOS" changelog add --summary "explicit refs override" --refs "D-43,R-05" 2>&1); RC=$?; set -e
assert_exit "F5 --refs override rc" 0 "$RC"
if grep -qE '^- Add explicit refs override \(D-43/R-05\) \[' CHANGELOG.md; then echo "  ✓ F6 explicit refs applied"; PASS=$((PASS+1)); else echo "  ✗ F6 explicit refs missing"; FAIL=$((FAIL+1)); fi
set +e; OUT=$(node "$GOS" changelog add --summary "malformed refs" --refs "T-54" 2>&1); RC=$?; set -e
assert_exit "F7 malformed refs rc" 1 "$RC"
assert_contains "F7 malformed refs message" "malformed" "$OUT"
NB="$(grep -cE '^- ' CHANGELOG.md || true)"
assert_eq "F8 malformed refs wrote nothing" "3" "$NB"
t54_teardown

# ===== V: forbidden summary → shared validator rejects, nothing written =====
t54_new
set +e; OUT=$(node "$GOS" changelog add --summary "adds two things. also breaks the invariant" 2>&1); RC=$?; set -e
assert_exit "V1 multi-sentence rc" 1 "$RC"
assert_contains "V1 validator error surfaced" "multi-sentence" "$OUT"
[ ! -f CHANGELOG.md ] && { echo "  ✓ V2 no bootstrap on validation failure"; PASS=$((PASS+1)); } || { echo "  ✗ V2 CHANGELOG.md written despite rejection"; FAIL=$((FAIL+1)); }
t54_teardown

# ===== X: existing CHANGELOG.md structural precheck (fail-fast insert guards) =====
t54_new
printf '# Notes\n\n## [1.0.0] - 2026-01-01\n\n- Add seed (D-1) [2026-01-01]\n' > CHANGELOG.md
set +e; OUT=$(node "$GOS" changelog add --summary "no unreleased section" 2>&1); RC=$?; set -e
assert_exit "X1 missing [Unreleased] rc" 1 "$RC"
assert_contains "X1 missing [Unreleased] message" "Unreleased" "$OUT"
printf '## [Unreleased]\n\n- Add seed (D-1) [2026-01-01]\n' > CHANGELOG.md
set +e; OUT=$(node "$GOS" changelog add --summary "no title section" 2>&1); RC=$?; set -e
assert_exit "X2 missing H1 rc" 1 "$RC"
assert_contains "X2 missing H1 message" "title" "$OUT"
t54_teardown

# ===== K: concurrent double add — both entries survive (wait, not die) =====
t54_new
set +e
( node "$GOS" changelog add --summary "first concurrent entry" >/dev/null 2>&1; echo $? > k1.rc ) &
( node "$GOS" changelog add --summary "second concurrent entry" >/dev/null 2>&1; echo $? > k2.rc ) &
wait
set -e
assert_eq "K1 first concurrent add rc" "0" "$(cat k1.rc)"
assert_eq "K2 second concurrent add rc" "0" "$(cat k2.rc)"
if grep -qF 'first concurrent entry' CHANGELOG.md && grep -qF 'second concurrent entry' CHANGELOG.md; then echo "  ✓ K3 both concurrent entries present (no loss)"; PASS=$((PASS+1)); else echo "  ✗ K3 an entry was lost: $(grep -cE '^- ' CHANGELOG.md)"; FAIL=$((FAIL+1)); fi
[ ! -e .gos/cache/changelog.lock ] && { echo "  ✓ K4 lock released after adds"; PASS=$((PASS+1)); } || { echo "  ✗ K4 changelog lock left behind"; FAIL=$((FAIL+1)); }
t54_teardown

# ===== M: .changes.md is sealed — mtime untouched =====
t54_new
printf '# sealed history\n' > .changes.md
touch -d '2026-01-01 00:00:00 UTC' .changes.md
M1="$(stat -c %y .changes.md 2>/dev/null || true)"
node "$GOS" changelog add --summary "seal check" >/dev/null 2>&1
M2="$(stat -c %y .changes.md 2>/dev/null || true)"
assert_eq "M1 .changes.md mtime unchanged" "$M1" "$M2"
t54_teardown

# ===== H: help/usage seam + lint stub =====
set +e; HOUT=$(node "$GOS" help changelog 2>&1); HRC=$?; set -e
assert_exit "H1 help changelog rc" 0 "$HRC"
assert_contains "H1 usage rendered from registry" "gos changelog <sub>" "$HOUT"
set +e; OUT=$(node "$GOS" changelog 2>&1); RC=$?; set -e
assert_exit "H2 bare changelog usage rc" 1 "$RC"
assert_contains "H2 usage line" "Usage: gos changelog add" "$OUT"
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "H3 lint wired rc (T55 seam flipped)" 0 "$RC"
assert_contains "H3 lint missing-file advisory" "gos changelog add" "$OUT"

# ===== Z: product source zero CJK =====
CJK_HITS="$(grep -rlP '[\x{4e00}-\x{9fff}]' "$GOS_ROOT/bin/lib/task/changelog.cjs" 2>/dev/null || true)"
if [ -z "$CJK_HITS" ]; then echo "  ✓ Z1 module source contains zero CJK"; PASS=$((PASS+1)); else echo "  ✗ Z1 CJK found: $CJK_HITS"; FAIL=$((FAIL+1)); fi

echo "--- T54 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
