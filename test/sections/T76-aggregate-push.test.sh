#!/usr/bin/env bash
# gos-map:cmd push
# T76: aggregate push — commits in origin/main..HEAD collapse into one semantic
# commit (tree = HEAD tree, parent = origin/main tip) pushed to refs/heads/main;
# re-run is a no-op; missing message source refuses; permission-class push
# failures print PR-path guidance; archive output ends with the ready-to-run
# push line.
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner
T76_DIR=""

t76_setup() {
  T76_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t76"
  mkdir -p "$T76_DIR" || exit 1
  git init -q --bare "$T76_DIR/origin.git"
  git init -q -b main "$T76_DIR/work"
  cd "$T76_DIR/work" || exit 1
  git remote add origin "$T76_DIR/origin.git"
  echo base > root.txt && git add root.txt && git commit -q -m "chore: seed base" || exit 1
  git push -q origin HEAD:refs/heads/main || exit 1
  git fetch -q origin || exit 1
}

t76_seed_changelog() {
  printf '# Changelog\n\n## [Unreleased]\n\n- feat: aggregate push discipline (D-83) [2026-10-08]\n' > CHANGELOG.md
  git add CHANGELOG.md && git commit -q -m "docs: changelog entry" || exit 1
}

t76_seed_empty_changelog() {
  printf '# Changelog\n\n## [Unreleased]\n' > CHANGELOG.md
  git add CHANGELOG.md && git commit -q -m "docs: empty changelog" || exit 1
}

t76_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T76_DIR"; }

t76_setup
echo "--- T76: aggregate push ---"

# --- T76.1: three atomic commits -> exactly one aggregate commit on origin/main ---
t76_seed_changelog
echo a > a.txt && git add a.txt && git commit -q -m "feat: a" || exit 1
echo b > b.txt && git add b.txt && git commit -q -m "feat: b" || exit 1
OLD_TIP=$(git rev-parse origin/main)
PRE_HEAD=$(git rev-parse HEAD)
HEAD_TREE=$(git rev-parse 'HEAD^{tree}')
set +e; OUT=$(node "$GOS" push 2>&1); RC=$?; set -e
assert_exit "aggregate push exits 0" 0 "$RC"
git fetch -q origin
NEW_TIP=$(git rev-parse origin/main)
assert_eq "exactly one new commit on origin/main" "1" "$(git rev-list --count "$OLD_TIP..$NEW_TIP")"
assert_eq "aggregate parent is the old origin tip" "$OLD_TIP" "$(git rev-parse "$NEW_TIP^")"
assert_eq "aggregate tree equals HEAD tree" "$HEAD_TREE" "$(git rev-parse "$NEW_TIP^{tree}")"
assert_eq "subject derives from the changelog bullet" "feat: aggregate push discipline" "$(git log -1 --format=%s "$NEW_TIP")"
assert_contains "convergence reports the audit branch" "converged" "$OUT"
assert_eq "main converged onto the aggregate" "$NEW_TIP" "$(git rev-parse HEAD)"
CHAIN_TIP=$(git for-each-ref --format='%(objectname)' refs/heads/chain | head -1)
assert_eq "audit branch preserves the atomic chain tip" "$PRE_HEAD" "$CHAIN_TIP"

# --- T76.2: re-run is a no-op ---
set +e; OUT2=$(node "$GOS" push 2>&1); RC2=$?; set -e
assert_exit "re-run exits 0" 0 "$RC2"
assert_contains "re-run reports nothing to aggregate" "nothing" "$OUT2"
git fetch -q origin
assert_eq "origin/main unchanged after re-run" "$NEW_TIP" "$(git rev-parse origin/main)"

# --- T76.3: no --message and empty [Unreleased] delta -> refuses ---
t76_teardown; t76_setup
t76_seed_empty_changelog
echo c > c.txt && git add c.txt && git commit -q -m "feat: c" || exit 1
set +e; OUT=$(node "$GOS" push 2>&1); RC=$?; set -e
if [ "$RC" -ne 0 ]; then echo "  ✓ empty message source refuses (exit $RC)"; PASS=$((PASS+1)); else echo "  ✗ empty message source must refuse, got exit 0"; FAIL=$((FAIL+1)); fi
assert_contains "refusal names the fail-closed rule" "refusing" "$OUT"

# --- T76.4: explicit --message overrides the empty changelog ---
set +e; OUT=$(node "$GOS" push --message "feat(ops): explicit message aggregate" 2>&1); RC=$?; set -e
assert_exit "--message push exits 0" 0 "$RC"
git fetch -q origin
assert_eq "--message becomes the aggregate subject" "feat(ops): explicit message aggregate" "$(git log -1 --format=%s origin/main)"

# --- T76.5: pre-receive decline -> PR-path guidance ---
t76_teardown; t76_setup
t76_seed_changelog
echo d > d.txt && git add d.txt && git commit -q -m "feat: d" || exit 1
printf '#!/bin/sh\necho "declining main push for test" >&2\nexit 1\n' > "$T76_DIR/origin.git/hooks/pre-receive"
chmod +x "$T76_DIR/origin.git/hooks/pre-receive"
set +e; OUT=$(node "$GOS" push 2>&1); RC=$?; set -e
if [ "$RC" -ne 0 ]; then echo "  ✓ declined push exits non-zero (exit $RC)"; PASS=$((PASS+1)); else echo "  ✗ declined push must exit non-zero"; FAIL=$((FAIL+1)); fi
assert_contains "git stderr surfaced for diagnosis" "pre-receive hook declined" "$OUT"
assert_contains "PR guidance points at a feature branch" "feature branch" "$OUT"
assert_contains "PR guidance says squash-merge" "squash" "$OUT"

# --- T76.6: archive output ends with the ready-to-run push line ---
t76_teardown
T76_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t76"
mkdir -p "$T76_DIR" && cd "$T76_DIR" || exit 1
git init -q . && git commit -q --allow-empty -m root
echo ".gos/state.json" > .gitignore && git add .gitignore && git commit -q -m gi
export GOS_SKIP_SHIP_CHECK=1
node "$GOS" init 1 "aggregate push coupling" >/dev/null 2>&1
SPEC=$(node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null)
echo spec > "$SPEC"
node "$GOS" approve archive >/dev/null 2>&1
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "archive exits 0" 0 "$RC"
LAST=$(printf '%s\n' "$OUT" | tail -1)
assert_contains "archive output ends with ready-to-run push line" "gos push" "$LAST"
assert_contains "push line notes message auto-derivation" "auto-derives" "$LAST"
unset GOS_SKIP_SHIP_CHECK

# --- T76.7: pre-push hook rejects a multi-commit raw push to main ---
t76_teardown; t76_setup
set +e; INST=$(node "$GOS" setup --commitlint 2>&1); IRC=$?; set -e
assert_exit "hook install exits 0" 0 "$IRC"
assert_contains "install output names the pre-push hook" "hooks/pre-push" "$INST"
assert_file "pre-push hook file installed" "hooks/pre-push"
REMOTE_TIP=$(git ls-remote origin refs/heads/main | cut -f1)
echo one > one.txt && git add one.txt && git commit -q --no-verify -m "feat: one" || exit 1
echo two > two.txt && git add two.txt && git commit -q --no-verify -m "feat: two" || exit 1
set +e; OUT=$(git push origin HEAD:refs/heads/main 2>&1); RC=$?; set -e
if [ "$RC" -ne 0 ]; then echo "  ✓ multi-commit raw push to main rejected (exit $RC)"; PASS=$((PASS+1)); else echo "  ✗ multi-commit raw push to main must fail"; FAIL=$((FAIL+1)); fi
assert_contains "rejection hints at gos push" "gos push" "$OUT"
assert_contains "rejection names the one-commit discipline" "discipline allows 1" "$OUT"
assert_eq "remote main unchanged after rejection" "$REMOTE_TIP" "$(git ls-remote origin refs/heads/main | cut -f1)"

# --- T76.8: single clean commit passes the raw-push guard ---
git reset -q --hard origin/main || exit 1
echo solo > solo.txt && git add solo.txt && git commit -q --no-verify -m "feat: solo semantic change" || exit 1
LOCAL_TIP=$(git rev-parse HEAD)
set +e; OUT=$(git push origin HEAD:refs/heads/main 2>&1); RC=$?; set -e
assert_exit "single clean commit push passes" 0 "$RC"
assert_eq "remote main advanced to the pushed commit" "$LOCAL_TIP" "$(git ls-remote origin refs/heads/main | cut -f1)"

# --- T76.9: feature-branch pushes are untouched by the guard ---
git checkout -q -b feature
echo f1 > f1.txt && git add f1.txt && git commit -q --no-verify -m "feat: f1" || exit 1
echo f2 > f2.txt && git add f2.txt && git commit -q --no-verify -m "feat: f2" || exit 1
FEATURE_TIP=$(git rev-parse HEAD)
set +e; OUT=$(git push origin feature 2>&1); RC=$?; set -e
assert_exit "multi-commit feature-branch push untouched" 0 "$RC"
assert_eq "feature branch tip on remote" "$FEATURE_TIP" "$(git ls-remote origin refs/heads/feature | cut -f1)"
git checkout -q main

# --- T76.10: advance-template subject rejected even as a single commit ---
t76_teardown; t76_setup
node "$GOS" setup --commitlint >/dev/null 2>&1 || exit 1
echo adv > adv.txt && git add adv.txt && git commit -q --no-verify -m "chore(task): advance P15" || exit 1
set +e; OUT=$(git push origin HEAD:refs/heads/main 2>&1); RC=$?; set -e
if [ "$RC" -ne 0 ]; then echo "  ✓ advance-template push rejected (exit $RC)"; PASS=$((PASS+1)); else echo "  ✗ advance-template push must fail"; FAIL=$((FAIL+1)); fi
assert_contains "advance rejection hints at gos push" "gos push" "$OUT"
assert_contains "rejection names the advance template" "advance-template" "$OUT"

# --- T76.11: tree-empty commit rejected even as a single commit ---
git reset -q --hard origin/main || exit 1
git commit -q --no-verify --allow-empty -m "chore: empty marker" || exit 1
set +e; OUT=$(git push origin HEAD:refs/heads/main 2>&1); RC=$?; set -e
if [ "$RC" -ne 0 ]; then echo "  ✓ tree-empty push rejected (exit $RC)"; PASS=$((PASS+1)); else echo "  ✗ tree-empty push must fail"; FAIL=$((FAIL+1)); fi
assert_contains "tree-empty rejection hints at gos push" "gos push" "$OUT"
assert_contains "rejection names the tree-empty rule" "tree-empty" "$OUT"

# --- T76.12: setup re-run installs both hooks idempotently ---
set +e; RE=$(node "$GOS" setup --commitlint 2>&1); RERC=$?; set -e
assert_exit "setup re-run exits 0" 0 "$RERC"
assert_eq "hooks dir holds exactly the two gos hooks" "2" "$(ls hooks | wc -l | tr -d ' ')"
if [ -x "hooks/pre-push" ]; then
  echo "  ✓ re-installed pre-push stays executable"; PASS=$((PASS+1))
else
  echo "  ✗ re-installed pre-push lost its executable bit"; FAIL=$((FAIL+1))
fi
assert_eq "core.hooksPath stays hooks" "hooks" "$(git config --get core.hooksPath)"

# --- T76.13: aggregate-guard range rules (CI parity inside the sandbox) ---
GUARD="$GOS_ROOT/test/checks/aggregate-guard.sh"
GBASE=$(git rev-parse HEAD)
echo g > g.txt && git add g.txt && git commit -q --no-verify -m "feat: g" || exit 1
GMID=$(git rev-parse HEAD)
echo h > h.txt && git add h.txt && git commit -q --no-verify -m "feat: h" || exit 1
GEND=$(git rev-parse HEAD)
set +e
bash "$GUARD" "$GBASE" "$GMID" >/dev/null 2>&1; GUARD_SINGLE=$?
bash "$GUARD" "$GBASE" "$GEND" >/dev/null 2>&1; GUARD_MULTI=$?
bash "$GUARD" "$GBASE" "$GEND" --forced >/dev/null 2>&1; GUARD_FORCED=$?
bash "$GUARD" "0000000000000000000000000000000000000000" "$GEND" >/dev/null 2>&1; GUARD_ZERO=$?
git commit -q --no-verify --allow-empty -m "chore(task): advance test marker" || true
GADV=$(git rev-parse HEAD)
bash "$GUARD" "$GEND" "$GADV" >/dev/null 2>&1; GUARD_ADVANCE=$?
set -e
assert_exit "guard accepts a single-commit range" 0 "$GUARD_SINGLE"
[ "$GUARD_MULTI" -ne 0 ] && { echo "  ✓ guard rejects a multi-commit range"; PASS=$((PASS+1)); } || { echo "  ✗ guard must reject multi-commit range"; FAIL=$((FAIL+1)); }
assert_exit "forced flag skips the count rule only" 0 "$GUARD_FORCED"
assert_exit "all-zero BEFORE skips all checks" 0 "$GUARD_ZERO"
[ "$GUARD_ADVANCE" -ne 0 ] && { echo "  ✓ guard rejects advance-template subjects"; PASS=$((PASS+1)); } || { echo "  ✗ guard must reject advance-template subjects"; FAIL=$((FAIL+1)); }

# --- T76.14: diverged clone refuses instead of dropping remote content ---
# HEAD holds the T76.13 commits (absent from origin); a second clone then
# advances origin/main with a commit HEAD lacks. The push must fail closed
# on the behind-check rather than fast-forwarding remote content away.
git clone -q "$T76_DIR/origin.git" "$T76_DIR/clone2" 2>/dev/null || exit 1
cd "$T76_DIR/clone2" || exit 1
git config user.email t@t.local && git config user.name t
git checkout -q -B c2work origin/main || exit 1
echo divergent > divergent.txt && git add divergent.txt && git commit -q -m "feat: remote-only change" || exit 1
git push -q origin HEAD:refs/heads/main || exit 1
cd "$T76_DIR/work" || exit 1
set +e; OUT14=$(node "$GOS" push 2>&1); RC14=$?; set -e
[ "$RC14" -ne 0 ] && { echo "  ✓ diverged push refused"; PASS=$((PASS+1)); } || { echo "  ✗ diverged push must fail"; FAIL=$((FAIL+1)); }
assert_contains "divergence refusal names remote-only commits" "not in HEAD" "$OUT14"

# --- T76.15: topology-only divergence (history rebuild) is allowed ---
# Simulate a D-85-style rebuild: origin gains a re-commit whose tree already
# exists in HEAD's ancestry. Content-wise nothing is remote-only, so the
# aggregate must proceed and land on the rebuilt tip.
git fetch -q origin
git reset -q --hard origin/main
echo t15 > t15.txt && git add t15.txt && git commit -q --no-verify -m "feat: t15 content" || exit 1
T15TREE=$(git rev-parse 'HEAD^{tree}')
R=$(git commit-tree "$T15TREE" -p "$(git rev-parse origin/main)" -m "chore: rebuilt history placeholder") || exit 1
git push -q origin "$R:refs/heads/main" || exit 1
git fetch -q origin
echo t16 > t16.txt && git add t16.txt && git commit -q --no-verify -m "feat: t16 content" || exit 1
set +e; OUT15=$(node "$GOS" push --message "feat(ops): topology divergence case" 2>&1); RC15=$?; set -e
assert_exit "rebuild-topology divergence push exits 0" 0 "$RC15"
assert_contains "notice names topology-only divergence" "topology-only divergence" "$OUT15"
git fetch -q origin
assert_eq "aggregate lands on the rebuilt tip" "$(git rev-parse 'HEAD^{tree}')" "$(git rev-parse 'origin/main^{tree}')"
assert_contains "convergence ran after the rebuild push" "converged" "$OUT15"
assert_eq "main matches origin after convergence" "$(git rev-parse origin/main)" "$(git rev-parse HEAD)"

# --- T76.16: non-conventional derived subject refuses with a --message hint ---
echo t17 > t17.txt && git add t17.txt && git commit -q --no-verify -m "feat: t17 content" || exit 1
printf '# Changelog\n\n## [Unreleased]\n\n- Add plain prose summary without a conventional type (R-01) [2026-10-09]\n' > CHANGELOG.md
git add CHANGELOG.md && git commit -q --no-verify -m "docs: plain changelog bullet" || exit 1
PRE16=$(git rev-parse origin/main)
set +e; OUT16=$(node "$GOS" push 2>&1); RC16=$?; set -e
[ "$RC16" -ne 0 ] && { echo "  ✓ non-conventional subject refused"; PASS=$((PASS+1)); } || { echo "  ✗ non-conventional subject must fail"; FAIL=$((FAIL+1)); }
assert_contains "refusal names the format contract" "conventional-format contract" "$OUT16"
assert_contains "refusal hints at an explicit subject" "one-liner" "$OUT16"

# --- T76.16b: subject-case violations refused (CI commitlint parity — the
# aggregate bypasses the commit-msg hook, push is the last local line) ---
set +e; OUT16B=$(node "$GOS" push --message "feat(ops): P1 style uppercase subject" 2>&1); RC16B=$?; set -e
[ "$RC16B" -ne 0 ] && { echo "  ✓ sentence-case subject refused"; PASS=$((PASS+1)); } || { echo "  ✗ sentence-case subject must fail (CI commitlint rejects it)"; FAIL=$((FAIL+1)); }
assert_contains "refusal names subject-case" "subject-case" "$OUT16B"
set +e; OUT16C=$(node "$GOS" push --message "feat(ops): ALL CAPS SUBJECT LINE" 2>&1); RC16C=$?; set -e
[ "$RC16C" -ne 0 ] && { echo "  ✓ upper-case subject refused"; PASS=$((PASS+1)); } || { echo "  ✗ upper-case subject must fail"; FAIL=$((FAIL+1)); }
set +e; OUT16D=$(node "$GOS" push --message "feat(ops): subject ends with period." 2>&1); RC16D=$?; set -e
[ "$RC16D" -ne 0 ] && { echo "  ✓ full-stop subject refused"; PASS=$((PASS+1)); } || { echo "  ✗ trailing period must fail (subject-full-stop)"; FAIL=$((FAIL+1)); }
git fetch -q origin
assert_eq "origin untouched by the refused push" "$PRE16" "$(git rev-parse origin/main)"

t76_teardown
echo "--- T76 done ---"
