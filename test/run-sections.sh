#!/usr/bin/env bash
# Section test runner — exports shared assert helpers + env (GOS/TESTBASE), runs
# test/sections/T*.test.sh in name order, counts ✓/✗ from output (sections bump
# their own PASS/FAIL copies; output counting is authoritative across processes).
# TESTBASE is an isolated base dir under the repo (sections' convention: sandbox
# dirs created inside it, removed by each section's own teardown; runner sweeps
# any abort leftovers).
# Usage: bash test/run-sections.sh [name-filter]   e.g. run-sections.sh T10
set -uo pipefail

GOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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
TOTAL_PASS=0
TOTAL_FAIL=0
RAN_NAMES=""
for f in "$GOS_ROOT"/test/sections/T*.test.sh; do
  name="$(basename "$f" .test.sh)"
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then continue; fi
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
printf '{"schema_version":2,"sections_run":%s,"head_tree":"%s","patch_sha":"%s","finished_at":"%s"}\n' \
  "$RAN_SECS" "${WTH_H:-unknown}" "${WTH_P:-unknown}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$GOS_ROOT/.gos/cache/run-manifest.json"

[ "$TOTAL_FAIL" -eq 0 ] && exit 0 || exit 1
