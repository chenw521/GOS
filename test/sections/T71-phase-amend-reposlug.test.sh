#!/usr/bin/env bash
# gos-map:fn bin/lib/knowledge/phase.cjs#fn:cmdPhase bin/lib/ops/gitseed.cjs#fn:validateRepoSlug bin/lib/ops/gitseed.cjs#fn:inferRepoSlug
# gos-map:cmd phase
# phase amend — pending goal rewrite via command (edit-via-commands discipline)
# Block layout: amend block first; the reposlug block goes at the marked
# append point below (keep teardown/final-exit lines LAST).
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
T71_DIR=""

t71_setup() {
  [ -n "$TESTBASE" ] || TESTBASE="$(mktemp -d)"
  T71_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t71"
  mkdir -p "$T71_DIR" && cd "$T71_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  # sandbox project container: idx0 done (refusal fixture), idx1 pending (amend target)
  node "$GOS" init --project 1 "t71 container" >/dev/null 2>&1
  node "$GOS" phase add "A-alpha: first" --goal "original goal one" >/dev/null 2>&1
  node "$GOS" phase add "B-beta: second" --goal "original goal two" >/dev/null 2>&1
  node "$GOS" phase mark-done 0 >/dev/null 2>&1
}

t71_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T71_DIR"; }

t71_setup
echo "--- T71: phase amend ---"

# --- (a) amend pending phase → list shows new goal (whole-goal replace) ---
set +e; OUT=$(node "$GOS" phase amend 1 --goal "revised goal two" 2>&1); RC=$?; set -e
assert_exit "T71.a1 amend pending exits 0" 0 "$RC"
assert_contains "T71.a2 success contract names phase" "Phase amended: B-beta: second" "$OUT"
OUT=$(node "$GOS" phase list 2>&1)
assert_contains "T71.a3 list shows replaced goal" "revised goal two" "$OUT"
if echo "$OUT" | grep -q "original goal two"; then echo "  ✗ T71.a4 old goal removed (replace semantics)"; FAIL=$((FAIL+1)); else echo "  ✓ T71.a4 old goal removed (replace semantics)"; PASS=$((PASS+1)); fi

# --- (b) amend done phase → non-zero exit + clear reason ---
set +e; OUT=$(node "$GOS" phase amend 0 --goal "x" 2>&1); RC=$?; set -e
assert_exit "T71.b1 amend done phase exits 1" 1 "$RC"
assert_contains "T71.b2 done refusal carries reason" "refused" "$OUT"

# --- (b+) amend active phase → non-zero exit + reason ---
node "$GOS" phase claim 1 >/dev/null 2>&1
set +e; OUT=$(node "$GOS" phase amend 1 --goal "x" 2>&1); RC=$?; set -e
assert_exit "T71.b3 amend active phase exits 1" 1 "$RC"
assert_contains "T71.b4 active refusal carries reason" "active" "$OUT"

# --- (c) empty goal → non-zero exit ---
set +e; OUT=$(node "$GOS" phase amend 1 --goal "" 2>&1); RC=$?; set -e
assert_exit "T71.c1 empty goal exits 1" 1 "$RC"
assert_contains "T71.c2 empty goal prints usage" "Usage: gos phase amend" "$OUT"

t71_teardown
echo "--- T71: repo slug ({{REPO}} variable) ---"
# Sandboxes are plain git repos with optional remotes; init git never reads
# or writes task state, so no project container is needed here.
set +e
T71RS="$TESTBASE/test-$(date +%s)-$RANDOM-t71rs"
mkdir -p "$T71RS" || exit 1

t71rs_repo() {  # $1=name, $2=origin url (optional), $3=upstream url (optional)
  local d="$T71RS/$1"
  mkdir -p "$d" && cd "$d" || exit 1
  git init -q . && git commit -q --allow-empty -m t71rs-seed
  [ -n "${2:-}" ] && git remote add origin "$2"
  [ -n "${3:-}" ] && git remote add upstream "$3"
}

assert_contains "T71.rs0 master config.yml carries the {{REPO}} variable" "{{REPO}}" "$(cat "$GOS_ROOT/templates/git/ISSUE_TEMPLATE/config.yml" 2>/dev/null)"

# --- (a) origin inference → slug in the Discussions URL, zero residue ---
t71rs_repo a https://github.com/OctoCat/Widget
OUT=$(node "$GOS" init git --codeowner '@octocat' </dev/null 2>&1); RC=$?
assert_exit "T71.rs-a1 inference-based seeding exits 0" 0 "$RC"
CFG=$(cat .github/ISSUE_TEMPLATE/config.yml 2>/dev/null)
assert_contains "T71.rs-a2 Discussions URL carries owner-lowercased slug" "github.com/octocat/Widget/discussions" "$CFG"
if printf '%s' "$CFG" | grep -qE '\{\{[A-Z][A-Z0-9_]*\}\}|OWNER/REPO'; then echo "  ✗ T71.rs-a3 placeholder residue in seeded config.yml"; FAIL=$((FAIL+1)); else echo "  ✓ T71.rs-a3 zero placeholder residue"; PASS=$((PASS+1)); fi
assert_contains "T71.rs-a4 codeowner seeding intact alongside the slug" "@octocat" "$(cat .github/CODEOWNERS 2>/dev/null)"

# --- (b) origin ending in .git → suffix stripped from the slug ---
t71rs_repo b https://github.com/octocat/widget.git
OUT=$(node "$GOS" init git --codeowner '@octocat' </dev/null 2>&1); RC=$?
assert_exit "T71.rs-b1 .git remote seeding exits 0" 0 "$RC"
CFG=$(cat .github/ISSUE_TEMPLATE/config.yml 2>/dev/null)
assert_contains "T71.rs-b2 Discussions URL carries slug without .git" "github.com/octocat/widget/discussions" "$CFG"
if printf '%s' "$CFG" | grep -q 'widget\.git'; then echo "  ✗ T71.rs-b3 .git leaked into the slug"; FAIL=$((FAIL+1)); else echo "  ✓ T71.rs-b3 no .git residue in the slug"; PASS=$((PASS+1)); fi

# --- (c) origin wins when upstream is also configured ---
t71rs_repo c https://github.com/octocat/origin-repo.git https://github.com/octocat/upstream-repo.git
OUT=$(node "$GOS" init git --codeowner '@octocat' </dev/null 2>&1); RC=$?
assert_exit "T71.rs-c1 origin+upstream seeding exits 0" 0 "$RC"
CFG=$(cat .github/ISSUE_TEMPLATE/config.yml 2>/dev/null)
assert_contains "T71.rs-c2 slug taken from origin" "github.com/octocat/origin-repo/discussions" "$CFG"
if printf '%s' "$CFG" | grep -q 'upstream-repo'; then echo "  ✗ T71.rs-c3 upstream leaked into the slug"; FAIL=$((FAIL+1)); else echo "  ✓ T71.rs-c3 upstream never consulted"; PASS=$((PASS+1)); fi

# --- (d) non-github host → fail-closed, demand --repo, zero files ---
t71rs_repo d https://gitlab.com/octocat/widget.git
OUT=$(node "$GOS" init git --codeowner '@octocat' </dev/null 2>&1); RC=$?
assert_exit "T71.rs-d1 non-github host refused" 1 "$RC"
assert_contains "T71.rs-d2 message asks for an explicit repo" "pass --repo <owner/repo>" "$OUT"
if [ -e .github ]; then echo "  ✗ T71.rs-d3 files written despite refusal"; FAIL=$((FAIL+1)); else echo "  ✓ T71.rs-d3 zero files written"; PASS=$((PASS+1)); fi

# --- (e) no remote at all → same fail-closed contract ---
t71rs_repo e
OUT=$(node "$GOS" init git --codeowner '@octocat' </dev/null 2>&1); RC=$?
assert_exit "T71.rs-e1 no-remote seeding refused" 1 "$RC"
assert_contains "T71.rs-e2 message asks for an explicit repo" "pass --repo <owner/repo>" "$OUT"
if [ -e .github ] || [ -e commitlint.config.yaml ]; then echo "  ✗ T71.rs-e3 placeholder-bearing files written"; FAIL=$((FAIL+1)); else echo "  ✓ T71.rs-e3 zero files written"; PASS=$((PASS+1)); fi

# --- (f) explicit --repo violations die before any write ---
t71rs_repo f https://github.com/octocat/widget.git
OUT=$(node "$GOS" init git --codeowner '@octocat' --repo "$(printf 'octocat/w\nidget')" </dev/null 2>&1); RC=$?
assert_exit "T71.rs-f1 multi-line --repo refused" 1 "$RC"
assert_contains "T71.rs-f2 violation message names the repo slug" "repo slug" "$OUT"
T71_LONG="$(printf 'a%.0s' $(seq 60))/$(printf 'b%.0s' $(seq 50))"
OUT=$(node "$GOS" init git --codeowner '@octocat' --repo "$T71_LONG" </dev/null 2>&1); RC=$?
assert_exit "T71.rs-f3 over-length --repo refused (111 chars)" 1 "$RC"
OUT=$(node "$GOS" init git --codeowner '@octocat' --repo 'octocat' </dev/null 2>&1); RC=$?
assert_exit "T71.rs-f4 no-slash --repo refused" 1 "$RC"
OUT=$(node "$GOS" init git --codeowner '@octocat' --repo 'octocat/widget.git' </dev/null 2>&1); RC=$?
assert_exit "T71.rs-f5 trailing-.git --repo refused (strip-then-revalidate)" 1 "$RC"
if [ -e .github ]; then echo "  ✗ T71.rs-f6 bad --repo values wrote files"; FAIL=$((FAIL+1)); else echo "  ✓ T71.rs-f6 zero files written for every violation"; PASS=$((PASS+1)); fi

# --- (g) render-self: self slug written once, never overwritten ---
T71RS_SELF="$T71RS/selfrepo"
mkdir -p "$T71RS_SELF"
cp -r "$GOS_ROOT/bin" "$T71RS_SELF/bin" && cp -r "$GOS_ROOT/templates" "$T71RS_SELF/templates" && cp "$GOS_ROOT/package.json" "$T71RS_SELF/package.json"
( cd "$T71RS_SELF" && git init -q . && git commit -q --allow-empty -m t71rs-self ) || exit 1
OUT=$(cd "$T71RS_SELF" && node "$T71RS_SELF/bin/gos.cjs" init git --render-self </dev/null 2>&1); RC=$?
assert_exit "T71.rs-g1 render-self exits 0" 0 "$RC"
assert_contains "T71.rs-g2 self render writes the self slug Discussions URL" "github.com/chenw521/GOS/discussions" "$(cat "$T71RS_SELF/.github/ISSUE_TEMPLATE/config.yml" 2>/dev/null)"
sed -i 's#github.com/chenw521/GOS/discussions#github.com/octocat/widget/discussions#' "$T71RS_SELF/.github/ISSUE_TEMPLATE/config.yml"
OUT=$(cd "$T71RS_SELF" && node "$T71RS_SELF/bin/gos.cjs" init git --render-self </dev/null 2>&1); RC=$?
assert_exit "T71.rs-g3 re-render exits 0" 0 "$RC"
assert_contains "T71.rs-g4 personalized config.yml survives render-self (bootstrap-only)" "github.com/octocat/widget/discussions" "$(cat "$T71RS_SELF/.github/ISSUE_TEMPLATE/config.yml" 2>/dev/null)"

cd "$TESTBASE" >/dev/null 2>&1
rm -rf "$T71RS"
echo "--- T71 done: PASS=$PASS FAIL=$FAIL ---"
[ "$FAIL" -eq 0 ] || exit 1
