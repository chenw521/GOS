#!/usr/bin/env bash
# Wave Aggregation Protocol — one command instead of 3 manual steps.
# Exit: 0 = aggregated clean | 1 = issues found (see output)
set -uo pipefail
ISSUES=0

echo "── [1/3] Conflict scan ──"
CHANGED=$(git status --porcelain 2>/dev/null | awk '{print $NF}' | sort)
DUPS=$(echo "$CHANGED" | uniq -d)
if [ -n "$DUPS" ]; then echo "⚠ same-file conflicts (manual merge review):"; echo "$DUPS"; ISSUES=1
else echo "✓ no duplicate-file modifications"; fi

echo "── [2/3] Interface docking hint ──"
PLAN_F="$(node "$(dirname "$0")/../../bin/gos.cjs" context plan 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["plan"])' 2>/dev/null)"; grep -E "Depends on:|provides|requires" "${PLAN_F:-.gos/task/*/plan.md}" 2>/dev/null | head -10 || echo "(no plan.md dependency info — skip)"

echo "── [3/3] Unified build verification ──"
if [ -f package.json ] && grep -q '"test"' package.json; then
  npm test --silent 2>&1 | tail -3 || { echo "⚠ test failure"; ISSUES=1; }
elif [ -f Makefile ] && grep -q '^test:' Makefile; then
  make test 2>&1 | tail -3 || { echo "⚠ make test failure"; ISSUES=1; }
else
  echo "(no test infra detected — run project-specific checks manually)"
fi

echo ""
if [ $ISSUES -eq 0 ]; then echo "RESULT: AGGREGATION CLEAN"; else echo "RESULT: ISSUES FOUND — resolve before wave-complete heartbeat"; fi
exit $ISSUES
