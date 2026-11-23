#!/usr/bin/env bash
# Dogfood fixture builder — materializes a self-contained gos workspace
# repo for the restart-safe auto loop acceptance cycle. The fixture owns
# the production shape of a user workspace: the gos exec tree (bin/ +
# templates/ from this checkout) committed in the repo's own history, a
# minimal deterministic section suite whose sentinel section blocks the
# first sections pass, a pinned git identity, and no remote. No fixture
# dispatch table exists — the real CLI's own table drives the cycle.
# Determinism is contractual: two builds into fresh dirs must be
# byte-identical (diff -r empty), so the branch name, identity, and
# author/committer dates are pinned and the post-commit index is rebuilt
# from the tree object (the add/commit index embeds per-build stat data).
# The fixture ships no package.json: bin/gos.cjs is zero-dependency
# CommonJS and the acorn callgraph leg degrades to an advisory when the
# module is absent (engine acornCtx).
# Usage: build.sh <target-dir>  (target must not exist or be empty)
# Output: exactly one line on success — "fixture: <target-dir>"
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"

refuse() { echo "✗ $1" >&2; exit 1; }

if [ $# -ne 1 ] || [ -z "$1" ]; then
  refuse "usage: build.sh <target-dir> (exactly one non-empty argument)"
fi
TARGET="$1"
if [ -e "$TARGET" ]; then
  [ -d "$TARGET" ] || refuse "target '$TARGET' exists and is not a directory"
  [ -z "$(ls -A "$TARGET")" ] || refuse "target '$TARGET' exists and is not empty — refusing to overwrite"
fi
[ -f "$REPO_ROOT/bin/gos.cjs" ] || refuse "no bin/gos.cjs under '$REPO_ROOT' — run from a repo checkout"
[ -d "$REPO_ROOT/templates" ] || refuse "no templates/ under '$REPO_ROOT' — run from a repo checkout"

# Pinned git world: fixed identity, fixed dates, fixed branch — the only
# way two independent builds can agree on commit shas and .git internals.
export GIT_AUTHOR_NAME="gos-fixture" GIT_AUTHOR_EMAIL="fixture@test.invalid"
export GIT_COMMITTER_NAME="gos-fixture" GIT_COMMITTER_EMAIL="fixture@test.invalid"
export GIT_AUTHOR_DATE="2026-01-01T00:00:00+00:00"
export GIT_COMMITTER_DATE="2026-01-01T00:00:00+00:00"

mkdir -p "$TARGET"

# ---- exec tree: exactly what a user workspace carries, committed -------
cp -a "$REPO_ROOT/bin" "$TARGET/bin"
cp -a "$REPO_ROOT/templates" "$TARGET/templates"

# ---- fixture section suite + minimal runner ----------------------------
mkdir -p "$TARGET/test/sections"

cat > "$TARGET/test/run-sections.sh" <<'RUNNER_EOF'
#!/usr/bin/env bash
# Fixture section runner — the dogfood workspace's minimal, deterministic
# counterpart of the product runner: discovers test/sections/T*.test.sh
# in name order, runs each from an isolated base under .gos/cache
# (gitignored, so a run never dirties the workspace tree), counts ✓/✗
# from section output, tees the whole run to .gos/cache/section-runs/,
# overwrites the run manifest at .gos/cache/run-manifest.json (same path
# shapes as the product runner), and exits non-zero on any ✗ or aborted
# section.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export GOS="$ROOT/bin/gos.cjs"
export GOS_ROOT="$ROOT"
export GOS_HEADLESS=1 GOS_LANG=en
export GIT_AUTHOR_NAME="gos-fixture" GIT_AUTHOR_EMAIL="fixture@test.invalid"
export GIT_COMMITTER_NAME="gos-fixture" GIT_COMMITTER_EMAIL="fixture@test.invalid"

mkdir -p "$ROOT/.gos/cache/section-runs"
TESTBASE="$(mktemp -d "$ROOT/.gos/cache/sections-base-XXXXXX")"
export TESTBASE
export HOME="$TESTBASE/home"
mkdir -p "$HOME"
trap 'rm -rf "$TESTBASE"' EXIT

RUN_LOG="$ROOT/.gos/cache/section-runs/$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee "$RUN_LOG") 2>&1

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_LIST=""
NAMES=""
RESULTS=""

for f in "$ROOT"/test/sections/T*.test.sh; do
  name="$(basename "$f" .test.sh)"
  NAMES="$NAMES $name"
  echo "=== $name ==="
  OUT="$(cd "$TESTBASE" && bash "$f" 2>&1)"
  RC=$?
  echo "$OUT"
  P="$(printf '%s\n' "$OUT" | grep -c '^  ✓' || true)"
  X="$(printf '%s\n' "$OUT" | grep -c '^  ✗' || true)"
  if [ "$RC" -ne 0 ]; then
    echo "  ✗ SECTION ABORTED (exit $RC)"
    X=$((X + 1))
  fi
  echo "--- $name: $P passed, $X failed ---"
  TOTAL_PASS=$((TOTAL_PASS + P))
  TOTAL_FAIL=$((TOTAL_FAIL + X))
  RESULTS="$RESULTS\"$name\":{\"pass\":$P,\"fail\":$X},"
  if [ "$X" -gt 0 ]; then FAILED_LIST="$FAILED_LIST $name"; fi
done

# manifest: overwrite-mode snapshot, same path shapes as the product runner
SECTIONS_JSON=""
for n in $NAMES; do SECTIONS_JSON="$SECTIONS_JSON\"$n\","; done
FAILED_JSON=""
for n in $FAILED_LIST; do FAILED_JSON="$FAILED_JSON\"$n\","; done
HEAD_TREE="$(git -C "$ROOT" rev-parse 'HEAD^{tree}' 2>/dev/null || echo unknown)"
printf '{"schema_version":2,"selector":"full","sections_run":[%s],"failed_sections":[%s],"results":{%s},"log":"%s","head_tree":"%s","tree_source":"live","pin":null}\n' \
  "${SECTIONS_JSON%,}" "${FAILED_JSON%,}" "${RESULTS%,}" "${RUN_LOG#"$ROOT"/}" "$HEAD_TREE" \
  > "$ROOT/.gos/cache/run-manifest.json"

echo "=== Sections total: $TOTAL_PASS passed, $TOTAL_FAIL failed ==="
[ "$TOTAL_FAIL" -eq 0 ]
RUNNER_EOF

cat > "$TARGET/test/sections/T1-fixture-trivial.test.sh" <<'TRIVIAL_EOF'
#!/usr/bin/env bash
# Trivial always-green section — standalone-safe without TESTBASE: proves
# the fixture runner discovers and passes a normal section.
echo "  ✓ fixture trivial check 1 (section discovered)"
echo "  ✓ fixture trivial check 2 (exit 0)"
exit 0
TRIVIAL_EOF

cat > "$TARGET/test/sections/T2-fixture-sentinel.test.sh" <<'SENTINEL_EOF'
#!/usr/bin/env bash
# Dogfood sentinel section — two-pass arming design for the restart-safe
# loop acceptance. Pass 1 (marker absent): write the arming marker
# (pid/pgid/timestamp) under the workspace's .gos/cache (writable,
# persists across runner restarts, gitignored) and block for a bounded
# 600s window — the acceptance kills the enclosing runner inside this
# window. Pass 2 (marker present, i.e. a restarted run): report green and
# exit 0 immediately so a restarted cycle cannot re-block.
# DOGFOOD_SENTINEL_RESET=1 deletes the marker and exits green (repeated
# builds/tests).
FIXTURE_REPO="$(cd "$(dirname "$0")/../.." && pwd)"
MARKER="$FIXTURE_REPO/.gos/cache/dogfood-sentinel.marker"

if [ "${DOGFOOD_SENTINEL_RESET:-0}" = "1" ]; then
  rm -f "$MARKER"
  echo "  ✓ sentinel marker cleared (reset)"
  exit 0
fi

if [ -f "$MARKER" ]; then
  echo "  ✓ sentinel already armed — restarted run passes immediately"
  echo "  ✓ sentinel marker: $(tr '\n' ' ' < "$MARKER")"
  exit 0
fi

mkdir -p "$FIXTURE_REPO/.gos/cache"
printf 'pid=%s\npgid=%s\narmed_at=%s\n' \
  "$$" "$(ps -o pgid= -p "$$" | tr -d ' ')" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MARKER"
echo "  ✓ sentinel arming (pid $$, marker at .gos/cache/dogfood-sentinel.marker)"
echo "  ✓ sentinel blocking 600s — kill the enclosing runner inside this window"
sleep 600
SENTINEL_EOF

printf '.gos/cache/\n' > "$TARGET/.gitignore"

# ---- commit: fixed branch, fixed dates, no remote ----------------------
git init -q -b main "$TARGET"
git -C "$TARGET" add -A
git -C "$TARGET" commit -q -m "fixture: dogfood workspace"
# rebuild the index from the tree object: the post-commit index embeds
# working-tree stat data (mtime/inode) unique to each build; a tree-sourced
# index is byte-identical across builds.
rm -f "$TARGET/.git/index"
git -C "$TARGET" read-tree HEAD

echo "fixture: $TARGET"
