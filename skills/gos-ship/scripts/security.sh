#!/usr/bin/env bash
# Built-in security gate: blocks commit if secrets or dangerous patterns
# are present in staged/tracked source files. Exit non-zero = gate failed.
# Used by `gos gate` (custom-gate layer) — copy/symlink into .gos/gates/ to activate.

set -uo pipefail

PATTERNS_SECRETS='(api[_-]?key|secret|password|token)\s*[:=]\s*["'"'"'][A-Za-z0-9+/_-]{16,}'
PATTERNS_DANGER='(rm\s+-rf\s+/|eval\s*\(\s*["'"'"']|child_process.*shell.*true|curl.*\|\s*sudo\s*bash)'

FAILED=0

# Scan staged + tracked files (skip tests/fixtures/docs/markdown)
FILES=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null; git ls-files 2>/dev/null | grep -v '^\.gos/' )
FILES=$(echo "$FILES" | sort -u | grep -Ev '\.(md|lock|json)$|(^|/)(test|tests|fixtures|mocks)/|^gates/|security\.sh$' || true)

for f in $FILES; do
  [ -f "$f" ] || continue
  if grep -Enq "$PATTERNS_SECRETS" "$f" 2>/dev/null; then
    echo "SECRET-LIKE pattern in $f:" >&2
    grep -En "$PATTERNS_SECRETS" "$f" 2>/dev/null | head -3 >&2
    FAILED=1
  fi
  if grep -Enq "$PATTERNS_DANGER" "$f" 2>/dev/null; then
    echo "DANGEROUS pattern in $f:" >&2
    grep -En "$PATTERNS_DANGER" "$f" 2>/dev/null | head -3 >&2
    FAILED=1
  fi
done

if [ $FAILED -ne 0 ]; then
  echo "security gate: FAIL — resolve above or move values to env/config" >&2
  exit 2
fi
echo "security gate: clean"
exit 0
