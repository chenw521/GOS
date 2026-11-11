#!/usr/bin/env bash
# T-03 evidence: disjunctive idle pinned in gate source
R=$(git rev-parse --show-toplevel)
a=$(grep -c "archivedTidIdle" "$R/bin/lib/ops/gate.cjs")
b=$(grep -c "archivedTidIdle" "$R/bin/lib/task/archive.cjs")
echo "T3 gateIdleRefs=$a archiveHelper=$b"
