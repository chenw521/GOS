#!/usr/bin/env bash
# GENERATED views are scoped by renderer — prune works on project.json now.
# ( migration: the old 150-line DECISIONS.md file check is retired; the truth
#  source is .gos/project/project.json. Advisory only, always exit 0.)
set -euo pipefail
PJ=.gos/project/project.json
[ -f "$PJ" ] || { echo "no project.json (nothing to prune)"; exit 0; }
N=$(node -e "const p=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(Array.isArray(p.decisions)?p.decisions.length:0)" "$PJ")
if [ "$N" -le 50 ]; then
  echo "✓ $N entries (<=50, no prune needed)"
  exit 0
fi
echo "⚠ $N entries (>50) — review project.json: supersede/amend stale decisions (gos decision amend/supersede); the rendered view is already scoped to active + last 2 phases"
exit 0
