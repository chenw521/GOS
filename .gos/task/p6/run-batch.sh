#!/usr/bin/env bash
# One sweep batch, end to end, fail-stop. Usage: run-batch.sh <n> <changelog-entry-file>
# Preconditions: committed tree (pins included), disposition frozen.
#   plan -> changelog entry -> apply -> syntax gate -> verify -> lint receipt
set -euo pipefail
cd "$(dirname "$0")/../../../"

N="$1"; ENTRY_FILE="$2"
BATCH=".gos/task/p6/batches/batch-$N.txt"
SWEEP="test/checks/ai-trace-sweep.sh"

rm -rf .gos/task/p6/__pycache__

if [ -n "$(git status --porcelain)" ]; then
  echo "FATAL: worktree not clean before batch $N"; git status --short; exit 1
fi

bash "$SWEEP" plan "$BATCH" | tee /work/rstudio_tmp/opencode/p6-plan.log
grep -q "plan recorded" /work/rstudio_tmp/opencode/p6-plan.log || { echo "FATAL: plan refused"; exit 1; }

python3 - "$ENTRY_FILE" <<'PYEOF'
import sys
entry = open(sys.argv[1]).read().strip()
content = open('CHANGELOG.md').read()
if entry not in content:
    marker = "## [Unreleased]\n\n"
    assert marker in content
    open('CHANGELOG.md','w').write(content.replace(marker, marker + entry + "\n", 1))
PYEOF

python3 .gos/task/p6/apply-batch.py "$BATCH"
while read -r f; do
  case "$f" in *.cjs|*.js|*.mjs) node --check "$f" ;; esac
done < <(grep -v '^#' "$BATCH")

bash "$SWEEP" verify "$BATCH"
bash test/checks/ai-trace-lint.sh
echo "batch $N staged and green — commit it now"
