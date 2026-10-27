#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/changelog-core.cjs#fn:resolveChangelogMd bin/lib/ops/config.cjs#fn:cmdConfigChangelogPath bin/lib/task/archive.cjs#fn:cmdArchive
# gos-map:cmd config,changelog,archive
# changelog location config + single resolver + atomic mv (P1 )
# Covers: `gos config changelog-path` moves the existing file atomically and
#         records the PROJECT-layer key; next `gos changelog add` writes to the
#         configured path; `gos archive` SHIP obligation reads it there (no
#         root fallback); subdir invocations bootstrap nothing (resolver base
#         = project root, never process cwd); banned paths (`..`, `.git/`,
#         `.gos/` incl. cache, node_modules/, absolute, non-.md) die; mv
#         three-state idempotency (same-path no-op, both-exist die, non-regular
#         target die, adopt-existing); config-set serializes on the changelog
#         lock (waits a live holder, breaks a dead one); corrupt project config
#         fails closed at the resolver.
# grep -F discipline for bracketed strings (lesson 265a5dd3 — '[' parses as a
# character class under grep -q).
# Env: GOS (CLI path), TESTBASE (isolated base), assert helpers sourced by
#      runner. Direct invocation self-bootstraps the same environment.
T89_DIR=""

t89_new() {
  T89_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t89"
  mkdir -p "$T89_DIR" && cd "$T89_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t89-seed
  GOS_HEADLESS=1 node "$GOS" init 3 "t89 changelog path" >/dev/null 2>&1
}

t89_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T89_DIR"; }

# --- self-bootstrap: allow direct `bash test/sections/T89-*.test.sh` runs ---
T89_SELF=0
if [ -z "${GOS:-}" ]; then
  T89_SELF=1
  GOS_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  GOS="$GOS_ROOT/bin/gos.cjs"
  TESTBASE="$(mktemp -d "$GOS_ROOT/test-sections-base-XXXXXX")"
  export GOS GOS_ROOT TESTBASE
  export HOME="$TESTBASE/home"; mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
  assert_contains() {
    local label="$1" expected="$2" actual="$3"
    if [ -z "$expected" ]; then echo "  ✗ $label (empty pattern always matches)"; FAIL=$((FAIL+1))
    elif echo "$actual" | grep -q "$expected"; then echo "  ✓ $label"; PASS=$((PASS+1))
    else echo "  ✗ $label (expected: '$expected')"; echo "    actual: ${actual:0:160}"; FAIL=$((FAIL+1)); fi
  }
  assert_exit() {
    local label="$1" expected="$2" actual="$3"
    if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then echo "  ✓ $label (exit $actual)"; PASS=$((PASS+1))
    else echo "  ✗ $label (expected exit $expected, got '${actual:-<none>}')"; FAIL=$((FAIL+1)); fi
  }
  assert_file() {
    local label="$1" fpath="$2"
    if [ -n "$fpath" ] && [ -e "$fpath" ]; then echo "  ✓ $label"; PASS=$((PASS+1))
    else echo "  ✗ $label (missing: '${fpath:-<none>}')"; FAIL=$((FAIL+1)); fi
  }
  assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then echo "  ✓ $label"; PASS=$((PASS+1))
    else echo "  ✗ $label (expected: '$expected', got: '$actual')"; FAIL=$((FAIL+1)); fi
  }
  PASS=0; FAIL=0
fi

PASS=0; FAIL=0
echo "--- T89: changelog location config + single resolver + atomic mv ---"

TODAY="$(node -e "console.log(require('$GOS_ROOT/bin/lib/ops/changelog-core.cjs').utcToday())" 2>/dev/null || true)"

# ===== W: config set moves the file atomically + records the project-layer key =====
t89_new
printf '# Log\n\n## [Unreleased]\n\n- Add relocation seed (D-42) [2026-01-01]\n' > CHANGELOG.md
git add CHANGELOG.md && git commit -q -m seed-changelog
set +e; OUT=$(node "$GOS" config changelog-path docs/CHANGELOG.md 2>&1); RC=$?; set -e
assert_exit "W1 config changelog-path rc" 0 "$RC"
assert_contains "W1 success names the move" "docs/CHANGELOG.md" "$OUT"
assert_file "W2 file landed at the configured path" "docs/CHANGELOG.md"
if [ ! -e CHANGELOG.md ]; then echo "  ✓ W3 old root location vacated"; PASS=$((PASS+1)); else echo "  ✗ W3 root CHANGELOG.md still present"; FAIL=$((FAIL+1)); fi
if grep -qF -- '- Add relocation seed (D-42) [2026-01-01]' docs/CHANGELOG.md; then echo "  ✓ W4 moved content intact (grep -F, bracketed stamp)"; PASS=$((PASS+1)); else echo "  ✗ W4 content lost in move"; FAIL=$((FAIL+1)); fi
if grep -qF '"changelog_path": "docs/CHANGELOG.md"' .gos/config.json; then echo "  ✓ W5 project layer records changelog_path"; PASS=$((PASS+1)); else echo "  ✗ W5 changelog_path missing from .gos/config.json: $(cat .gos/config.json 2>/dev/null)"; FAIL=$((FAIL+1)); fi
# the post-mv git intermediate state is real — deleted + untracked until next commit
PORC="$(git status --porcelain 2>/dev/null || true)"
if printf '%s\n' "$PORC" | grep -qE '^ D CHANGELOG.md'; then echo "  ✓ W6 git intermediate: old path deleted"; PASS=$((PASS+1)); else echo "  ✗ W6 old path not reported deleted: $PORC"; FAIL=$((FAIL+1)); fi
if printf '%s\n' "$PORC" | grep -qE '^\?\? docs/'; then echo "  ✓ W7 git intermediate: new path untracked"; PASS=$((PASS+1)); else echo "  ✗ W7 new path not untracked: $PORC"; FAIL=$((FAIL+1)); fi
if [ ! -e .gos/cache/changelog.lock ]; then echo "  ✓ W8 changelog lock released after set"; PASS=$((PASS+1)); else echo "  ✗ W8 changelog lock left behind"; FAIL=$((FAIL+1)); fi

# ===== N: same-path re-run = no-op success (three-state idempotency) =====
set +e; OUT=$(node "$GOS" config changelog-path docs/CHANGELOG.md 2>&1); RC=$?; set -e
assert_exit "N1 same-path re-run rc" 0 "$RC"
assert_contains "N1 no-op message" "already" "$OUT"
assert_file "N2 file untouched by no-op" "docs/CHANGELOG.md"

# ===== A: next add writes to the configured path =====
set +e; OUT=$(node "$GOS" changelog add --summary "add lands in the configured location" 2>&1); RC=$?; set -e
assert_exit "A1 add after relocation rc" 0 "$RC"
if grep -qF -- '- Add add lands in the configured location' docs/CHANGELOG.md; then echo "  ✓ A2 entry written to the configured path"; PASS=$((PASS+1)); else echo "  ✗ A2 entry not in docs/CHANGELOG.md"; FAIL=$((FAIL+1)); fi
if [ ! -e CHANGELOG.md ]; then echo "  ✓ A3 no foreign root CHANGELOG.md bootstrapped"; PASS=$((PASS+1)); else echo "  ✗ A3 root CHANGELOG.md resurrected"; FAIL=$((FAIL+1)); fi

# ===== R: archive SHIP obligation reads the configured path (no root fallback) =====
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "R1 archive rc (unapproved)" 1 "$RC"
assert_contains "R1 SHIP changelog check passed (approval gate reached)" "approve archive" "$OUT"
if printf '%s' "$OUT" | grep -Fq "CHANGELOG.md not found"; then
  echo "  ✗ R1 archive claims CHANGELOG.md not found (read the wrong location)"; FAIL=$((FAIL+1))
else
  echo "  ✓ R1 obligation found the entry at the configured path"; PASS=$((PASS+1))
fi
# negative control: configured file removed + decoy at root with today entry → still "not found"
mv docs/CHANGELOG.md docs/stash.md
printf '# Log\n\n## [Unreleased]\n\n- Add decoy root entry (D-42) [%s]\n' "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "R2 archive rc with configured file absent" 1 "$RC"
assert_contains "R2 block names the missing changelog" "CHANGELOG.md not found" "$OUT"
if printf '%s' "$OUT" | grep -Fq "approve archive"; then
  echo "  ✗ R2 root decoy satisfied the obligation (root fallback exists)"; FAIL=$((FAIL+1))
else
  echo "  ✓ R2 no root fallback — configured path is the only read location"; PASS=$((PASS+1))
fi
t89_teardown

# ===== X: set with no file anywhere → next add bootstraps at the configured path =====
t89_new
set +e; OUT=$(node "$GOS" config changelog-path docs/CHANGELOG.md 2>&1); RC=$?; set -e
assert_exit "X1 set without an existing changelog rc" 0 "$RC"
assert_contains "X1 hint mentions the bootstrap" "changelog add" "$OUT"
if [ ! -e CHANGELOG.md ] && [ ! -e docs/CHANGELOG.md ]; then echo "  ✓ X2 nothing created by set alone"; PASS=$((PASS+1)); else echo "  ✗ X2 set created a file"; FAIL=$((FAIL+1)); fi
set +e; OUT=$(node "$GOS" changelog add --summary "bootstrap at the configured path" 2>&1); RC=$?; set -e
assert_exit "X3 bootstrap add rc" 0 "$RC"
assert_file "X4 CHANGELOG bootstrapped under docs/" "docs/CHANGELOG.md"
if grep -qF 'Keep a Changelog' docs/CHANGELOG.md; then echo "  ✓ X5 bootstrapped from the master template"; PASS=$((PASS+1)); else echo "  ✗ X5 template header missing"; FAIL=$((FAIL+1)); fi
if [ ! -e CHANGELOG.md ]; then echo "  ✓ X6 root stays clean"; PASS=$((PASS+1)); else echo "  ✗ X6 root CHANGELOG.md bootstrapped"; FAIL=$((FAIL+1)); fi
t89_teardown

# ===== S: subdir invocation bootstraps nothing (resolver base = project root) =====
t89_new
node "$GOS" config changelog-path docs/CHANGELOG.md >/dev/null 2>&1
node "$GOS" changelog add --summary "subdir resolution fixture entry" >/dev/null 2>&1
mkdir -p sub/deeper && cd sub/deeper || exit 1
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "S1 lint from subdir rc" 0 "$RC"
if printf '%s' "$OUT" | grep -Fq 'clean'; then echo "  ✓ S2 lint validated the root-configured file"; PASS=$((PASS+1)); else echo "  ✗ S2 lint did not reach the configured file: $OUT"; FAIL=$((FAIL+1)); fi
if [ ! -e CHANGELOG.md ] && [ ! -e docs ] && [ ! -e .gos ]; then echo "  ✓ S3 subdir bootstrapped nothing"; PASS=$((PASS+1)); else echo "  ✗ S3 subdir polluted (CHANGELOG.md/docs/.gos present)"; FAIL=$((FAIL+1)); fi
set +e; OUT=$(node "$GOS" changelog add --summary "subdir probe must never bootstrap" 2>&1); RC=$?; set -e
assert_exit "S4 subdir add rc (no task state there)" 1 "$RC"
if [ ! -e CHANGELOG.md ] && [ ! -e .gos ]; then echo "  ✓ S5 subdir add wrote nothing"; PASS=$((PASS+1)); else echo "  ✗ S5 subdir add bootstrapped files"; FAIL=$((FAIL+1)); fi
cd "$T89_DIR" || exit 1
assert_file "S6 root configured file intact after subdir probes" "docs/CHANGELOG.md"
t89_teardown

# ===== B: banned paths die (config never written, file never moved) =====
t89_new
printf '# Log\n\n## [Unreleased]\n\n- Add banned probe seed (D-42) [2026-01-01]\n' > CHANGELOG.md
BANNED=('../escape.md' '.git/index' '.git/hooks/probe.md' '.gos/x.md' '.gos/cache/x.md' 'node_modules/x.md' '/abs/CHANGELOG.md' 'docs/CHANGELOG.txt' 'docs/../CHANGELOG.md')
for BP in "${BANNED[@]}"; do
  set +e; OUT=$(node "$GOS" config changelog-path "$BP" 2>&1); RC=$?; set -e
  assert_exit "B1 banned '$BP' rc" 1 "$RC"
done
if [ -e CHANGELOG.md ]; then echo "  ✓ B2 file never moved by refused sets"; PASS=$((PASS+1)); else echo "  ✗ B2 file vanished"; FAIL=$((FAIL+1)); fi
if grep -qF '"changelog_path"' .gos/config.json 2>/dev/null; then echo "  ✗ B3 a refused set still wrote config"; FAIL=$((FAIL+1)); else echo "  ✓ B3 config untouched by refused sets"; PASS=$((PASS+1)); fi
set +e; OUT=$(node "$GOS" config changelog-path 2>&1); RC=$?; set -e
assert_exit "B4 missing operand rc" 1 "$RC"
assert_contains "B4 usage names the family" "changelog-path" "$OUT"
t89_teardown

# ===== M: mv three-state edge semantics =====
t89_new
printf '# Log\n\n## [Unreleased]\n\n- Add collision source (D-42) [2026-01-01]\n' > CHANGELOG.md
mkdir -p docs && printf '# Log\n\n## [Unreleased]\n\n- Add collision target (D-42) [2026-01-01]\n' > docs/CHANGELOG.md
set +e; OUT=$(node "$GOS" config changelog-path docs/CHANGELOG.md 2>&1); RC=$?; set -e
assert_exit "M1 both-exist rc" 1 "$RC"
if grep -qF -- '- Add collision source' CHANGELOG.md && grep -qF -- '- Add collision target' docs/CHANGELOG.md; then echo "  ✓ M2 both files intact after refusal"; PASS=$((PASS+1)); else echo "  ✗ M2 a file was lost on refusal"; FAIL=$((FAIL+1)); fi
t89_teardown

t89_new
mkdir -p docs/CHANGELOG.md   # directory target — not a regular file
printf '# Log\n' > CHANGELOG.md
set +e; OUT=$(node "$GOS" config changelog-path docs/CHANGELOG.md 2>&1); RC=$?; set -e
assert_exit "M3 non-regular target rc" 1 "$RC"
assert_contains "M3 names the non-regular refusal" "not a regular file" "$OUT"
if [ -e CHANGELOG.md ]; then echo "  ✓ M4 source untouched"; PASS=$((PASS+1)); else echo "  ✗ M4 source lost"; FAIL=$((FAIL+1)); fi
t89_teardown

t89_new
mkdir -p docs && printf '# Log\n\n## [Unreleased]\n\n- Add adopted entry (D-42) [2026-01-01]\n' > docs/CHANGELOG.md
set +e; OUT=$(node "$GOS" config changelog-path docs/CHANGELOG.md 2>&1); RC=$?; set -e
assert_exit "M5 adopt-existing (source missing) rc" 0 "$RC"
assert_contains "M5 adoption is explicit" "adopt" "$OUT"
if grep -qF -- '- Add adopted entry' docs/CHANGELOG.md && grep -qF '"changelog_path": "docs/CHANGELOG.md"' .gos/config.json; then echo "  ✓ M6 adopted file + recorded key"; PASS=$((PASS+1)); else echo "  ✗ M6 adoption lost the file or the key"; FAIL=$((FAIL+1)); fi
t89_teardown

# ===== K: config-set serializes on the changelog lock =====
t89_new
printf '# Log\n\n## [Unreleased]\n\n- Add lock probe (D-42) [2026-01-01]\n' > CHANGELOG.md
mkdir -p .gos/cache
sleep 3 & SK_PID=$!
printf '{"pid":%s,"started_at":"%s"}\n' "$SK_PID" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .gos/cache/changelog.lock
( node "$GOS" config changelog-path docs/CHANGELOG.md >k.out 2>&1; echo $? > k.rc ) &
CLI_BG=$!
sleep 0.8
if [ ! -e docs/CHANGELOG.md ] && kill -0 "$SK_PID" 2>/dev/null; then
  echo "  ✓ K1 live lock holder pauses the move"; PASS=$((PASS+1))
else
  echo "  ✗ K1 move raced past a live holder"; FAIL=$((FAIL+1))
fi
wait "$SK_PID" 2>/dev/null
wait "$CLI_BG" 2>/dev/null
assert_exit "K2 config-set rc after holder died (stale lock broken)" 0 "$(cat k.rc 2>/dev/null)"
assert_file "K3 file moved once the lock freed" "docs/CHANGELOG.md"
if [ ! -e .gos/cache/changelog.lock ]; then echo "  ✓ K4 lock released after completion"; PASS=$((PASS+1)); else echo "  ✗ K4 lock left behind"; FAIL=$((FAIL+1)); fi
t89_teardown

# ===== C: corrupt project config fails closed at the resolver =====
t89_new
printf '{corrupt\n' > .gos/config.json
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "C1 corrupt config rc" 1 "$RC"
assert_contains "C1 die names the project config" "config.json" "$OUT"
t89_teardown

# ===== U: usage surfaces =====
t89_new
set +e; OUT=$(node "$GOS" config 2>&1); RC=$?; set -e
if printf '%s' "$OUT" | grep -Fq 'changelog-path'; then echo "  ✓ U1 bare config usage mentions changelog-path"; PASS=$((PASS+1)); else echo "  ✗ U1 usage missing the family: ${OUT:0:120}"; FAIL=$((FAIL+1)); fi
t89_teardown

# ===== Z: product sources stay CJK-free =====
CJK_HITS="$(grep -rlP '[\x{4e00}-\x{9fff}]' "$GOS_ROOT/bin/lib/ops/config.cjs" "$GOS_ROOT/bin/lib/ops/changelog-core.cjs" "$GOS_ROOT/bin/lib/task/changelog.cjs" "$GOS_ROOT/bin/lib/task/archive.cjs" 2>/dev/null || true)"
if [ -z "$CJK_HITS" ]; then echo "  ✓ Z1 touched modules contain zero CJK"; PASS=$((PASS+1)); else echo "  ✗ Z1 CJK found: $CJK_HITS"; FAIL=$((FAIL+1)); fi

echo "--- T89 summary: $PASS passed, $FAIL failed ---"
if [ "$T89_SELF" = "1" ]; then
  rm -rf "$TESTBASE"
fi
[ "$FAIL" -eq 0 ]
