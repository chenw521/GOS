#!/usr/bin/env bash
# gitprobe-monopoly — primitive monopoly check ( , ).
#
# bin/lib/core/gitprobe.cjs is the single fail-closed git-probing primitive.
# No other module under bin/lib may shell out to the probe-family git options
#   check-ignore | --ignored=matching | ls-files --cached
# Direct calls bypass gitprobe's fail-closed triage (env poisoning, stderr
# chatter on success, cached failure markers) and quietly drift back to
# ad-hoc probe semantics — callers must use core.isTracked / core.ignoredSet
# (spread from bin/lib/core/index.cjs) instead.
#
# Fail-closed in every direction:
#   - hit outside the allowed home            -> exit 1
#   - bin/lib or the primitive home missing    -> exit 1
#   - scan infrastructure error (grep rc > 1)  -> exit 1
#
# The -era temporary allowlist (concerns.cjs legacy ls-files probe) was
# removed with : concerns.cjs now uses core.isTracked (gitprobe), so full
# monopoly is enforced unconditionally.
#
# Usage:
#   bash test/checks/gitprobe-monopoly.sh
#
# Exit codes: 0 monopoly holds, 1 violation(s) or infrastructure failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

PRIMITIVE="bin/lib/core/gitprobe.cjs"

[ -d bin/lib ] || { echo "✗ gitprobe-monopoly: bin/lib missing — cannot scan (fail-closed)" >&2; exit 1; }
[ -f "$PRIMITIVE" ] || { echo "✗ gitprobe-monopoly: primitive home $PRIMITIVE missing (fail-closed)" >&2; exit 1; }

set +e
raw=$(grep -rn --include='*.cjs' \
  -e 'check-ignore' -e '--ignored=matching' -e 'ls-files --cached' \
  bin/lib 2>&1)
rc=$?
set -e
if [ "$rc" -gt 1 ]; then
  echo "✗ gitprobe-monopoly: scan failed (grep rc=$rc) — fail-closed" >&2
  printf '%s\n' "$raw" >&2
  exit 1
fi

# strip the primitive's own home — every remaining hit is a hard violation
all=$(printf '%s\n' "$raw" | grep -v '^$' || true)
viol=$(printf '%s\n' "$all" | grep -v "^${PRIMITIVE}:" || true)

if [ -n "$viol" ]; then
  echo "✗ gitprobe-monopoly: probe-family git call(s) outside $PRIMITIVE — migrate to core.isTracked / core.ignoredSet:" >&2
  printf '%s\n' "$viol" >&2
  exit 1
fi

echo "✓ gitprobe-monopoly: no probe-family git calls outside $PRIMITIVE"
