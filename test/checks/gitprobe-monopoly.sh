#!/usr/bin/env bash
# gitprobe-monopoly — D-14/D-15/D-17 primitive monopoly check (§3.7, RT3-F11).
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
#   - hit outside the allowed homes            -> exit 1
#   - bin/lib or the primitive home missing    -> exit 1
#   - scan infrastructure error (grep rc > 1)  -> exit 1
#
# Temporary allowlist (REMOVE WITH T6):
#   bin/lib/knowledge/concerns.cjs — its legacy `ls-files` probe migrates to
#   gitprobe in T6 (wave 2, same serial chain; see plan.md T6). Hits there are
#   printed as warnings but do not fail this check while T6 is pending.
#   TODO(T6, allowlisted 2026-10-22): T6's executor MUST delete the ALLOWLIST
#   line below together with the concerns.cjs migration — full monopoly is
#   enforced the moment the entry is gone.
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
ALLOWLIST="bin/lib/knowledge/concerns.cjs"   # TODO(T6, 2026-10-22): remove with T6 — see header

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

# strip the primitive's own home, then split remaining hits into the
# temporary allowlist bucket (warn) and hard violations (fail)
all=$(printf '%s\n' "$raw" | grep -v '^$' || true)
viol=$(printf '%s\n' "$all" | grep -v "^${PRIMITIVE}:" || true)
concerns=$(printf '%s\n' "$viol" | grep "^${ALLOWLIST}:" || true)
hard=$(printf '%s\n' "$viol" | grep -v "^${ALLOWLIST}:" || true)

if [ -n "$concerns" ]; then
  echo "⚠ gitprobe-monopoly: temporary allowlist still covering $ALLOWLIST (TODO(T6), wave 2 — remove with T6):"
  printf '%s\n' "$concerns" | sed 's/^/    /'
fi

if [ -n "$hard" ]; then
  echo "✗ gitprobe-monopoly: probe-family git call(s) outside $PRIMITIVE — migrate to core.isTracked / core.ignoredSet:" >&2
  printf '%s\n' "$hard" >&2
  exit 1
fi

echo "✓ gitprobe-monopoly: no probe-family git calls outside $PRIMITIVE (concerns.cjs allowlist pending T6)"
