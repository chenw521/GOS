#!/usr/bin/env bash
# Subject charset policy: commit subjects must be pure ASCII (no CJK).
# commitlint has no regex/charset rule (its supported-rule set has no match
# rule; unknown rule names crash with "Found rules without implementation"),
# so this script is the enforcer:
#   1. self-test the charset enforcer against canned CJK/ASCII subjects;
#   2. when commitlint is invocable, assert the repo config accepts a clean
#      ASCII subject (conventional rules and the charset policy must compose);
#   3. enforce the policy over the origin/main..HEAD commit range when the
#      range is resolvable (CI runs this with fetch-depth: 0).
# Exit codes: 0 pass (or documented SKIP of optional legs), 1 policy violated.
set -euo pipefail

CJK_RE='[\x{2e80}-\x{9fff}\x{ff00}-\x{ffef}\x{3000}-\x{303f}]'
RANGE="${1:-origin/main..HEAD}"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

subject_has_cjk() { printf '%s' "$1" | grep -qP -- "$CJK_RE"; }

# 1. self-test (always runs; offline-safe)
subject_has_cjk 'fix: 添加中文主题' || fail 'charset enforcer failed to flag a CJK subject'
if subject_has_cjk 'fix: ascii subject only'; then fail 'charset enforcer flagged a clean ASCII subject'; fi

# 2. commitlint composition (optional locally; CI installs nothing extra and
#    uses npx, so a missing local commitlint is a SKIP, not a failure)
clint=""
if command -v commitlint >/dev/null 2>&1; then
  clint="commitlint"
elif npx --no-install commitlint --version >/dev/null 2>&1; then
  clint="npx --no-install commitlint"
fi
if [ -n "$clint" ]; then
  if ! printf 'fix: ascii subject only\n' | $clint --config commitlint.config.yaml >/dev/null 2>&1; then
    fail 'repo commitlint config rejected a clean ASCII subject'
  fi
else
  echo 'SKIP (commitlint unavailable locally; CI enforces via npx commitlint@19)'
fi

# 3. range enforcement over the PR commit subjects
left="${RANGE%%..*}"
if git rev-parse --verify --quiet "${left}^{commit}" >/dev/null 2>&1; then
  bad=0
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    if subject_has_cjk "$s"; then
      printf 'FAIL: CJK subject in %s: %s\n' "$RANGE" "$s" >&2
      bad=$((bad + 1))
    fi
  done < <(git log --format=%s "$RANGE")
  [ "$bad" -eq 0 ] || fail "$bad CJK subject(s) in $RANGE"
  echo "PASS: subject charset policy holds (self-test ok; $(git rev-list --count "$RANGE") commit(s) in $RANGE checked)"
else
  echo "SKIP (commit range $RANGE not resolvable locally; CI enforces it)"
  echo 'PASS: subject charset self-test ok'
fi
