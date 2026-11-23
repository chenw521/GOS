#!/usr/bin/env bash
# Dogfood direct-require guard — the dogfood section reaches the auto loop
# via the CLI only.
#
# The restart-safe auto loop's real runner (bin/lib/ops/auto/loop.cjs and
# workers.cjs) is only reachable as a subprocess through the CLI. The
# dogfood acceptance section (test/sections/T136-auto-dogfood-restart.test.sh)
# must therefore never require those modules directly — a direct require
# would exercise the harness instead of the shipped CLI boundary that
# restart-safety depends on. The other sections that harness those modules
# directly are the sanctioned test pattern; this guard bites on the dogfood
# section only.
# Usage: dogfood-no-require.sh
#        dogfood-no-require.sh --self-test
# The --self-test mode scans the real section first, then plants violations
# in scratch copies and asserts the detector catches them.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SECTION="$ROOT/test/sections/T136-auto-dogfood-restart.test.sh"
# Direct or path-joined require of the runner modules: the module path and
# one of the two filenames on the same line covers both forms.
PATTERN='ops/auto.*(loop|workers)\.cjs'

# scan <file>: print "line: text" hits for banned direct requires.
scan() {
  grep -nE "$PATTERN" "$1" || true
}

# verdict <file>: exit 0 clean, exit 1 with the hit lines and a named
# message when banned requires are present.
verdict() {
  local hits
  hits="$(scan "$1")"
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
    echo "✗ dogfood no-require: $1 requires bin/lib/ops/auto/{loop,workers}.cjs directly — the real runner is only reachable as a subprocess via the CLI"
    return 1
  fi
  echo "✓ dogfood no-require: $1 reaches the auto loop via the CLI only"
}

self_test() {
  local got out
  # tmp stays global: the EXIT trap fires after self_test returns, where
  # function locals are already out of scope.
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # expect <wanted-exit:0|1> <label> <file>: assert the scan verdict.
  expect() {
    local want="$1" label="$2" target="$3" got=0 out
    out=$(verdict "$target" 2>&1) || got=1
    if [ "$got" -ne "$want" ]; then
      printf 'FAIL: %s (wanted exit %s, got %s)\n%s\n' \
        "$label" "$want" "$got" "$out" >&2
      exit 1
    fi
    printf 'PASS: %s\n' "$label"
  }

  # 1. clean copy passes
  cp "$SECTION" "$tmp/clean.test.sh"
  expect 0 'clean copy accepted' "$tmp/clean.test.sh"

  # 2. planted direct require rejected, message names the violating file
  cp "$SECTION" "$tmp/direct.test.sh"
  printf "const loop = require('../../bin/lib/ops/auto/loop.cjs');\n" >> "$tmp/direct.test.sh"
  got=0
  out=$(verdict "$tmp/direct.test.sh" 2>&1) || got=1
  if [ "$got" -ne 1 ]; then
    printf 'FAIL: planted direct require not rejected (wanted exit 1, got %s)\n%s\n' "$got" "$out" >&2
    exit 1
  fi
  case "$out" in
    *"$tmp/direct.test.sh"*) ;;
    *)
      echo 'FAIL: rejection message does not name the violating file' >&2
      printf '%s\n' "$out" >&2
      exit 1
      ;;
  esac
  echo 'PASS: planted direct require rejected (message names the file)'

  # 3. path-joined require variant rejected
  cp "$SECTION" "$tmp/joined.test.sh"
  printf "const workers = require(path.join(__dirname, '../../bin/lib/ops/auto', 'workers.cjs'));\n" >> "$tmp/joined.test.sh"
  expect 1 'path-joined require variant rejected' "$tmp/joined.test.sh"

  echo 'dogfood-no-require self-test: 3/3 cases passed'
}

if [ "${1:-}" = '--self-test' ]; then
  if ! verdict "$SECTION" >/dev/null; then
    echo '✗ dogfood no-require: the section on the tree already carries banned requires — fix it before the self-test means anything' >&2
    exit 1
  fi
  self_test
  exit 0
fi

if [ ! -f "$SECTION" ]; then
  echo "✗ dogfood no-require: section file missing: $SECTION" >&2
  exit 1
fi
verdict "$SECTION"
