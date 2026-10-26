#!/usr/bin/env bash
# P4 observable-truth T9 evidence: knowledge refresh integrity.
# Passes (exit 0) iff no 4800-line drift claim remains under .gos/codebase/
# AND all three guide-trio files stamp a born-at sha equal to the sha
# recorded in the refresh evidence ledger (not live HEAD).
set -u
BASE="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$BASE" || exit 1
H=$(grep -m1 '^sha: ' .gos/task/p4/evidence/knowledge-refresh.md | cut -d' ' -f2)
S=0
for f in structure conventions concerns; do
  if [ "$(sed -n 2p .gos/codebase/"$f".md)" = "born-at: $H" ]; then S=$((S+1)); fi
done
D=$(grep -rn 4800 .gos/codebase/ | wc -l)
echo "T9 OK ledger=${H:0:8} stamps=$S/3 drift4800=$D"
[ "$S" -eq 3 ] && [ "$D" -eq 0 ]
