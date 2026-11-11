#!/usr/bin/env bash
# T-08 evidence: dig floor constants wired both sides
R=$(git rev-parse --show-toplevel)
a=$(grep -c "DIG_FLOOR_ERA" "$R/bin/lib/knowledge/decisions.cjs")
b=$(grep -c "digFloorFreezeCheck" "$R/bin/lib/task/commit.cjs")
echo "T8 eraHomeRefs=$a freezeCalls=$b"
