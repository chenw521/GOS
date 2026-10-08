#!/usr/bin/env bash
# Detects components needing cold-start smoke tests (from plan/spec hints).
set -uo pipefail
NEED=0
echo "── server entry ──"
ls server.ts server.js app.ts app.js main.py src/server.* src/index.* 2>/dev/null | head -2 | grep -q . && { echo "⚠ FOUND — cold-start test required: kill, fresh boot, health-check"; NEED=1; } || echo "✓ none"
echo "── migrations ──"
ls -d migrations/ db/migrate/ alembic/ prisma/ 2>/dev/null | head -1 | grep -q . && { echo "⚠ FOUND — test: run from scratch on clean DB"; NEED=1; } || echo "✓ none"
echo "── config files ──"
ls .env.example config/*.yaml config/*.toml 2>/dev/null | head -1 | grep -q . && { echo "⚠ FOUND — test: load without optional env vars"; NEED=1; } || echo "✓ none"
[ $NEED -eq 1 ] && echo "RESULT: COLD-START CHECKS NEEDED (add as truths if not present)" || echo "RESULT: NO COLD-START COMPONENTS"
