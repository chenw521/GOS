#!/usr/bin/env bash
# SHIP cleanup checklist — scans tracked source for ship-blockers.
# Exit: 0 = clean | 1 = findings
set -uo pipefail
F=0
FILES=$(git ls-files 2>/dev/null | grep -Ev '\.(md|lock|json)$|^\.gos/' || true)
[ -z "$FILES" ] && { echo "(no tracked source files)"; exit 0; }

echo "── debug artifacts ──"
# 'console-dot-log' is PRODUCT output in CLI tools (bin/) — only flag in app source.
# Also exempt *.sh: shell scripts embedding node one-liners use console.log functionally
# (e.g. prune-decisions.sh prints the count) — same class as bin/, not debug litter.
SCANFILES=$(echo "$FILES" | grep -v '^bin/' | grep -v '\.sh$' | grep -v 'cleanup-scan.sh$' || true)
HITS=$(echo "$SCANFILES" | xargs grep -ln "console\.log(\|print(\s*debug\|debugger\b" 2>/dev/null || true)
[ -n "$HITS" ] && { echo "⚠ $HITS"; F=1; } || echo "✓ none"

echo "── dead code (commented-out blocks) ──"
HITS=$(echo "$FILES" | xargs grep -lE "^\s*//\s*(function|const|let|var|if|for)\s|^\s*#\s*(def|if|for)\s" 2>/dev/null || true)
[ -n "$HITS" ] && { echo "⚠ $HITS (review — not always blockers)"; } || echo "✓ none"

echo "── secrets ──"
bash "$(dirname "$0")/security.sh" && true || F=1

echo ""
[ $F -eq 0 ] && { echo "RESULT: CLEAN"; exit 0; } || { echo "RESULT: FINDINGS — fix Critical/Major before archive"; exit 1; }
