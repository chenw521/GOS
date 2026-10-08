#!/usr/bin/env bash
# Section test runner — exports shared assert helpers + env (GOS/TESTBASE), runs
# test/sections/T*.test.sh in name order, counts ✓/✗ from output (sections bump
# their own PASS/FAIL copies; output counting is authoritative across processes).
# TESTBASE is an isolated base dir under the repo (sections' convention: sandbox
# dirs created inside it, removed by each section's own teardown; runner sweeps
# any abort leftovers).
# Usage:
#   bash test/run-sections.sh [name-filter]            # machine-state mode (default)
#   bash test/run-sections.sh --fresh [name-filter]    # clean git worktree (CI parity)
#   bash test/run-sections.sh --affected [--base <ref>] [files...]
#                                                      # map-blast closure ∩ section
#                                                      # anchors + gos-map:none set
set -uo pipefail

GOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="machine"
FRESH_FLAG=""
AFFECTED_FLAG=""
BASE_REF=""
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --fresh)    MODE="fresh"; shift ;;
    --affected) MODE="affected"; shift ;;
    --base)     BASE_REF="$2"; shift 2 ;;
    *)          POSITIONAL+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

# ---- --fresh: rerun the whole suite inside a clean git worktree (CI parity).
# The worktree carries HEAD's tracked files only — no machine-local .gos state —
# so self-repo assertions see exactly what a fresh CI checkout sees.
if [ "$MODE" = "fresh" ]; then
  # Place the worktree OUTSIDE the repo: gate's project-root detection walks
  # ancestors, and a worktree nested inside the real repo would find the
  # machine-local task state one level up (exactly what --fresh must exclude).
  FRESH_WT="$(mktemp -d /tmp/gos-fresh-sections-XXXXXX)"
  rmdir "$FRESH_WT"
  if ! git -C "$GOS_ROOT" worktree add --detach -q "$FRESH_WT" HEAD; then
    echo "✗ --fresh: cannot create worktree" >&2; exit 1
  fi
  # CI parity: the sections job installs dependencies before running (acorn
  # for T36). A fresh tree has no node_modules (gitignored).
  ( cd "$FRESH_WT" && npm install --no-audit --no-fund --loglevel=error >/dev/null 2>&1 ) || echo "⚠ fresh: npm install failed (network?)"
  # CI parity: the sections job trusts the tracked custom gate before running
  # (trust is opt-in and machine-local; a fresh tree starts untrusted).
  ( cd "$FRESH_WT" && node bin/gos.cjs gate trust check.sh >/dev/null 2>&1 ) || echo "⚠ fresh: gate trust step failed"
  echo "── fresh mode: clean worktree at $FRESH_WT (tree $(git -C "$FRESH_WT" rev-parse --short HEAD^{tree}))"
  ( cd "$FRESH_WT" && bash test/run-sections.sh "$@" )
  RC=$?
  git -C "$GOS_ROOT" worktree remove --force "$FRESH_WT" 2>/dev/null
  exit $RC
fi

export GOS="$GOS_ROOT/bin/gos.cjs"
export GOS_ROOT
# TESTBASE is deliberately not the repo root: an isolated base dir (absolute
# path inside GOS_ROOT) keeps sections from running with cwd=repo-root when
# their cd fails, which would let fixtures overwrite the real .gos/
export TESTBASE="$(mktemp -d "$GOS_ROOT/test-sections-base-XXXXXX")"
trap 'rm -rf "$TESTBASE"' EXIT
# Phase B T9 [R3-F7]: default fake HOME — global-file sections (T15/T18…) may override
# with their own sandbox HOME; nothing here may touch the real ~/.config/gos/
export HOME="$TESTBASE/home"
mkdir -p "$HOME"
# fake HOME hides the real .gitconfig — pin git identity so sandbox commits work
export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
# Phase U T7 (R4-F3, D-29): headless determinism anchor — suite stdout is never a TTY,
# so without this pin the init dual-mode flips with the developer's terminal state
# (CI green / local red). Sections that need the interactive path MUST `env -u GOS_HEADLESS`
# (see T35-u-init U3-U6: `script -qec` pty cases).
export GOS_HEADLESS=1
# P15 D-63/F10: sections pin en — locale-dependent output stays deterministic
# regardless of the developer's environment (goldens live in section T74).
export GOS_LANG=en

assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if [ -z "$expected" ]; then
    echo "  ✗ $label (empty pattern always matches — use assert_file/assert_eq)"
  elif echo "$actual" | grep -q "$expected"; then
    echo "  ✓ $label"
  else
    echo "  ✗ $label (expected: '$expected')"
    echo "    actual: ${actual:0:160}"
  fi
}

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then
    echo "  ✓ $label (exit $actual)"
  else
    echo "  ✗ $label (expected exit $expected, got '${actual:-<none>}')"
  fi
}

assert_file() {
  local label="$1" fpath="$2"
  if [ -n "$fpath" ] && [ -e "$fpath" ]; then
    echo "  ✓ $label"
  else
    echo "  ✗ $label (missing: '${fpath:-<none>}')"
  fi
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ✓ $label"
  else
    echo "  ✗ $label (expected: '$expected', got: '$actual')"
  fi
}

export -f assert_contains assert_exit assert_file assert_eq
export PASS=0 FAIL=0

FILTER="${1:-}"
[ "$MODE" = "affected" ] && FILTER=""
TOTAL_PASS=0
TOTAL_FAIL=0
RAN_NAMES=""
SELECTOR="full"

# ---- --affected: map-blast closure ∩ section anchors + the gos-map:none set.
# Fail-safe by construction: un-anchored sections always run; blast's mustRun
# already encodes cmd/fn section linkage via the testof edges.
SELECTED=""
if [ "$MODE" = "affected" ]; then
  SELECTOR="affected"
  if [ $# -ge 1 ]; then
    INPUT_FILES="$*"
  else
    BASE="${BASE_REF:-$(node -e "const c=require('./bin/lib/core/index.cjs');const s=c.readState();process.stdout.write(s.task_head||'HEAD')" 2>/dev/null || echo HEAD)}"
    INPUT_FILES="$(git -C "$GOS_ROOT" -c core.quotapath=off diff --name-only "$BASE" 2>/dev/null; git -C "$GOS_ROOT" -c core.quotapath=off ls-files --others --exclude-standard 2>/dev/null)"
  fi
  if [ -z "$INPUT_FILES" ]; then
    echo "── affected mode: empty input set (no diff vs base) — nothing to select"; exit 0
  fi
  # Pre-filter: blast only accepts scan-set files or file-anchor targets.
  # Anything else (unanchored data/docs) is reported as skipped — no section
  # declares it, so no section is impacted by it.
  INPUT_FILES="$(printf '%s\n' $INPUT_FILES | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  const path=require("path");
  const engine=require(path.join(process.env.GOS_ROOT,"bin/lib/map/engine.cjs"));
  const known=engine.mapKnownKeys(engine.scanSources(process.env.GOS_ROOT));
  const anchored=new Set();
  try{const fs=require("fs");const sd=path.join(process.env.GOS_ROOT,"test/sections");
    for(const f of fs.readdirSync(sd).filter(x=>/^T.*\.test\.sh$/.test(x))){
      const head=fs.readFileSync(path.join(sd,f),"utf8").split("\n").slice(0,6);
      for(const l of head){const m=l.match(/^#\s*gos-map:file\s+(\S+)/);if(m)anchored.add(m[1]);}}}catch{}
  const out=[];const skipped=[];
  for(const l of s.split("\n").filter(Boolean)){
    if(known.has(l)||anchored.has(l))out.push(l);else skipped.push(l);}
  for(const x of skipped)console.error(`  ○ not in code graph or file anchors: ${x}`);
  process.stdout.write(out.join("\n"));
});' 2>"$GOS_ROOT/.gos/cache/affected-skipped.txt")" || true
  if [ -z "$INPUT_FILES" ]; then
    echo "── affected mode: no graph-relevant inputs remain (see skip list)"; exit 0
  fi
  # shellcheck disable=SC2086
  BLAST_JSON="$(node "$GOS" map blast --json $INPUT_FILES 2>/dev/null)" || { echo "✗ --affected: map blast failed (run: gos map scan)" >&2; exit 1; }
  SELECTED="$(printf '%s' "$BLAST_JSON" | python3 -c "
import json, sys, glob, os, re
d = json.load(sys.stdin)['blast']
sel = {m['section'] for m in d.get('mustRun', [])}
rationale = {m['section']: 'blast: ' + ','.join(sorted(m.get('cmds') or ['fn'] )) for m in d.get('mustRun', [])}
# fail-safe: gos-map:none sections always run (behavior-contract tests outside static edges)
root = os.environ.get('GOS_ROOT', '.')
for f in sorted(glob.glob(os.path.join(root, 'test/sections/T*.test.sh'))):
    name = os.path.basename(f)[:-len('.test.sh')]
    head = open(f, encoding='utf-8', errors='replace').read(400)
    if re.search(r'^# gos-map:none', head, re.M):
        sel.add(name); rationale.setdefault(name, 'gos-map:none (fail-safe)')
print(' '.join(sorted(sel)))
print('\n'.join(f'{k}\t{v}' for k, v in sorted(rationale.items())), file=sys.stderr)
" 2>"$GOS_ROOT/.gos/cache/affected-rationale.tsv")" || { echo "✗ --affected: selector parse failed" >&2; exit 1; }
  echo "── affected mode: inputs ──"
  printf '%s\n' $INPUT_FILES | sed 's/^/  · /'
  echo "── selected sections (rationale in .gos/cache/affected-rationale.tsv) ──"
  printf '%s\n' $SELECTED | sed 's/^/  · /'
fi

for f in "$GOS_ROOT"/test/sections/T*.test.sh; do
  name="$(basename "$f" .test.sh)"
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then continue; fi
  if [ -n "$SELECTED" ] && ! printf '%s' "$SELECTED" | grep -qw "$name"; then
    echo "── skip $name (not in affected closure)"
    continue
  fi
  RAN_NAMES="$RAN_NAMES$name
"
  echo "=== $name ==="
  # guard: sections must run FROM TESTBASE (never the repo root — F-1 fixture-contamination root fix)
  # REVIEW #1: capture section rc — a section aborted mid-script (set -e truncation, bash
  # error) must NEVER report green; runner counts ✓/✗ lines AND treats rc≠0 as a failure row.
  SEC_OUT="$(cd "$TESTBASE" && bash "$f" 2>&1)"
  SEC_RC=$?
  echo "$SEC_OUT"
  if [ "$SEC_RC" -ne 0 ]; then
    echo "  ✗ SECTION ABORTED (exit $SEC_RC) — assertions after the failure point may not have run"
    # Phase C (T5, R4-F4): rc≠0 MUST count as a failure — the ABORTED line above is
    # echoed to runner stdout (not into SEC_OUT), so the X-count below misses it.
    # A section that dies mid-script with zero ✗ lines must never report green.
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
  fi
  if ! (cd "$TESTBASE" && pwd -P) | grep -q "test-sections-base"; then
    echo "  ✗ RUNNER GUARD FAILED: cwd escaped TESTBASE"; TOTAL_FAIL=$((TOTAL_FAIL+1))
  fi
  P="$(printf '%s\n' "$SEC_OUT" | grep -c '^  ✓' || true)"
  X="$(printf '%s\n' "$SEC_OUT" | grep -c '^  ✗' || true)"
  echo "--- $name: $P passed, $X failed ---"
  TOTAL_PASS=$((TOTAL_PASS + P))
  TOTAL_FAIL=$((TOTAL_FAIL + X))
done

# sweep: sections clean up via their own teardown; remove sandboxes leaked by aborts
shopt -s nullglob
for leak in "$GOS_ROOT"/test-*-t[0-9]* "$GOS_ROOT"/test-sections-base-*; do [ "$leak" = "$TESTBASE" ] && continue; rm -rf "$leak"; done
shopt -u nullglob

echo ""
echo "=== Sections total: $TOTAL_PASS passed, $TOTAL_FAIL failed ==="

# [Phase D T10] run-manifest: overwrite-mode (never append — partial runs are snapshots,
# R4 plan r2 §7). Component form {head_tree, patch_sha} — commit-advance tolerant (T12 fix).
RAN_SECS="$(printf '%s\n' "$RAN_NAMES" | python3 -c "import json,sys; print(json.dumps(sorted(l.strip() for l in sys.stdin if l.strip())))" 2>/dev/null || echo '[]')"
WTH_H="$(git -C "$GOS_ROOT" rev-parse 'HEAD^{tree}' 2>/dev/null)"
WTH_P="$(git -C "$GOS_ROOT" -c core.quotepath=off diff --no-color --no-ext-diff --no-textconv HEAD 2>/dev/null | sha256sum | cut -d' ' -f1)"
mkdir -p "$GOS_ROOT/.gos/cache"
printf '{"schema_version":2,"selector":"%s","sections_run":%s,"head_tree":"%s","patch_sha":"%s","finished_at":"%s"}\n' \
  "$SELECTOR" "$RAN_SECS" "${WTH_H:-unknown}" "${WTH_P:-unknown}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$GOS_ROOT/.gos/cache/run-manifest.json"

[ "$TOTAL_FAIL" -eq 0 ] && exit 0 || exit 1
