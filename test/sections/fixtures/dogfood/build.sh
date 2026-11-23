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
# The fixture carries package.json: bin/lib/core/fsio.cjs requires it for
# version metadata, so any real CLI invocation (paths --markdown at build
# time, the gate legs at run time) needs it in the tree. bin/gos.cjs itself
# is zero-dependency CommonJS and the acorn callgraph leg degrades to an
# advisory when the module is absent (engine acornCtx).
# The second commit plants a minimal but structurally valid GOS task at
# VERIFY (task zone spec/plan, state.json, census, Englishization
# whitelists, self-repo lint scripts, generated .gos/README.md) so the
# fixture's own pinned gate/sections/truth legs pass: the workspace repo
# is a self-repo for its CLI, which turns the cjk/ascii/ai-trace lints
# on — they ship with the fixture, and the whitelists are filtered down
# to the paths the fixture actually tracks (bin/**). The task anchors
# its diff baseline (task_head) at the first commit; census.json joins
# the per-task semantic allowlist because it is root-level seed data no
# plan task declares.
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
cp "$REPO_ROOT/package.json" "$TARGET/package.json"

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
# — component form {head_tree, patch_sha}: patch_sha hashes the diff vs
# HEAD at suite end (empty-diff sha on a clean tree), the field the
# commit-time manifest freshness check requires.
SECTIONS_JSON=""
for n in $NAMES; do SECTIONS_JSON="$SECTIONS_JSON\"$n\","; done
FAILED_JSON=""
for n in $FAILED_LIST; do FAILED_JSON="$FAILED_JSON\"$n\","; done
HEAD_TREE="$(git -C "$ROOT" rev-parse 'HEAD^{tree}' 2>/dev/null || echo unknown)"
PATCH_SHA="$(git -C "$ROOT" -c core.quotepath=off diff --no-color --no-ext-diff --no-textconv HEAD 2>/dev/null | sha256sum | cut -d' ' -f1)"
printf '{"schema_version":2,"selector":"full","sections_run":[%s],"failed_sections":[%s],"results":{%s},"log":"%s","head_tree":"%s","patch_sha":"%s","tree_source":"live","pin":null}\n' \
  "${SECTIONS_JSON%,}" "${FAILED_JSON%,}" "${RESULTS%,}" "${RUN_LOG#"$ROOT"/}" "$HEAD_TREE" "${PATCH_SHA:-unknown}" \
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

# Ignored runtime zones: .gos/cache + .gos/logs are the workspace's own
# machine-local surfaces; xdg + home hold the store-seed overrides that
# live inside the fixture dir but must never enter the diff set (the
# task's semantic diff-hit runs over untracked files too).
printf '.gos/cache/\n.gos/logs/\nxdg/\nhome/\n' > "$TARGET/.gitignore"

# ---- self-repo lint scripts: gate all executes them against this repo ----
mkdir -p "$TARGET/test/checks"
for s in cjk-lint.sh ascii-filenames.sh ai-trace-lint.sh; do
  cp "$REPO_ROOT/test/checks/$s" "$TARGET/test/checks/$s"
done

# ---- commit 1: exec tree + suite (the diff baseline the task anchors at) --
# Repo-local git identity: the runner's advance commit spawns `gos commit
# <stage>` under a marker-only env whitelist (no HOME), and git resolves
# committer identity from the repository config before ever touching $HOME —
# without this the advance dies "fatal: $HOME not set". Pinned bytes keep
# the two-build diff empty.
git init -q -b main "$TARGET"
git -C "$TARGET" config user.name "gos-fixture"
git -C "$TARGET" config user.email "fixture@test.invalid"
git -C "$TARGET" add -A
git -C "$TARGET" commit -q -m "fixture: dogfood workspace"
C1="$(git -C "$TARGET" rev-parse HEAD)"

# ---- census: the tracked .gos zone is lifecycle (flip-reconcile exempt) ----
cat > "$TARGET/census.json" <<'CENSUS_EOF'
{
  "schema_version": 1,
  "entries": {
    ".gos/": { "git": true, "lifecycle": true, "npm": false, "local": false }
  }
}
CENSUS_EOF

# ---- Englishization whitelists: keep only entries the fixture tracks ----
mkdir -p "$TARGET/.gos"
node -e '
const fs = require("fs");
const args = process.argv.slice(1);
const filter = (src) => JSON.parse(fs.readFileSync(src, "utf8"))
  .filter((e) => e && typeof e.path === "string" && e.path.startsWith("bin/"));
for (let i = 0; i + 1 < args.length; i += 2) {
  fs.writeFileSync(args[i + 1], JSON.stringify(filter(args[i]), null, 2) + "\n");
}
' "$REPO_ROOT/.gos/cjk-whitelist.json" "$TARGET/.gos/cjk-whitelist.json" \
  "$REPO_ROOT/.gos/ai-trace-whitelist.json" "$TARGET/.gos/ai-trace-whitelist.json"

# ---- task zone: spec (decision card) + plan (one task, no Files) ----------
TID="df01a"
mkdir -p "$TARGET/.gos/task/$TID"

cat > "$TARGET/.gos/task/$TID/spec.md" <<'SPEC_EOF'
# Spec — dogfood fixture task

## Intent

Cycle the dogfood workspace through its verify stage with the real CLI
and leave a green run record in the machine-local store.

## Decision D-201 — sentinel arming policy

The sections sentinel arms once and blocks the first sections pass; any
restarted run passes immediately instead of re-blocking.

| Option | Effect |
|:--|:--|
| arm-once-block | first pass blocks for the kill window |
| always-block | every pass blocks; restarts hang forever |
| no-sentinel | no blocking leg; the kill window cannot exist |

why-not: always-block — a restarted cycle must never re-block; no-sentinel — the acceptance needs a real first-pass window to kill inside.
SPEC_EOF

cat > "$TARGET/.gos/task/$TID/plan.md" <<'PLAN_EOF'
# Plan — dogfood fixture task

### Wave 1

#### T301: drive the verify cycle green

**Covers**: D-201

**Done when**: the fixture verify legs pass, the advance commit lands,
and the run record ends green.
PLAN_EOF

SPEC_SHA="$(node -e 'const c=require("crypto"),f=require("fs");process.stdout.write(c.createHash("sha256").update(f.readFileSync(process.argv[1])).digest("hex"))' "$TARGET/.gos/task/$TID/spec.md")"

cat > "$TARGET/.gos/state.json" <<STATE_EOF
{
  "schema_version": 6,
  "repo_id": null,
  "level": 3,
  "current_stage": "VERIFY",
  "completed_stages": ["INTENT", "THINK", "PLAN", "BUILD", "REVIEW"],
  "intent": {
    "summary": "Dogfood fixture task: cycle the workspace through verify with the real CLI",
    "confirmed": true,
    "confirmation": { "mode": "headless-auto", "ts": "2026-01-01T00:00:00.000Z" }
  },
  "approvals": {
    "THINK": "2026-01-01T00:00:00.000Z",
    "PLAN": "2026-01-01T00:00:00.000Z"
  },
  "spec_path": ".gos/task/$TID/spec.md",
  "plan_path": ".gos/task/$TID/plan.md",
  "project": false,
  "requirements": [
    { "id": "R-01", "text": "Dogfood fixture task: cycle the workspace through verify with the real CLI", "phase": null, "level": 3 }
  ],
  "decisions": [
    {
      "id": "D-201",
      "title": "Sentinel arming policy: arm once, block the first pass, pass restarts immediately",
      "rationale": "The kill window must exist exactly once per cycle; a restarted run must never re-block.",
      "birth_phase": "think",
      "status": "covered",
      "covered": true,
      "covered_by": "T301",
      "born_at": "2026-01-01T00:00:00.000Z"
    }
  ],
  "observable_truths": [
    {
      "id": "T-201",
      "description": "Fixture section suite passes both sections",
      "verified": true,
      "waived": false,
      "evidence": {
        "command": "bash test/run-sections.sh",
        "output_excerpt": "=== Sections total: 4 passed, 0 failed ===",
        "artifact_path": "census.json"
      }
    }
  ],
  "gaps": [],
  "semantic": { "allowlist": ["census.json"] },
  "task_head": "$C1",
  "task_head_history": [ { "sha": "$C1", "at": "2026-01-01T00:00:00.000Z", "what": "fixture-seed" } ],
  "spec_sha256": "$SPEC_SHA",
  "spec_gate_version": 2
}
STATE_EOF

# ---- registry README: rendered by the fixture CLI (regen-guard target) ----
( cd "$TARGET" && node bin/gos.cjs paths --markdown >/dev/null )

# ---- commit 2: task state + self-repo lint surface -----------------------
git -C "$TARGET" add -A
git -C "$TARGET" commit -q -m "fixture: gos task state at verify"
# rebuild the index from the tree object: the post-commit index embeds
# working-tree stat data (mtime/inode) unique to each build; a tree-sourced
# index is byte-identical across builds.
rm -f "$TARGET/.git/index"
git -C "$TARGET" read-tree HEAD

echo "fixture: $TARGET"
