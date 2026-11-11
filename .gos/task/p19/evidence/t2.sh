#!/usr/bin/env bash
# T-02 evidence: fixture asserts live in T112 (sandbox); here pin the merge surface by source grep
R=$(git rev-parse --show-toplevel)
a=$(grep -c "mergeArchiveWonFields" "$R/bin/lib/task/commit.cjs")
b=$(grep -c "completed_at" "$R/bin/lib/task/commit.cjs")
echo "T2 mergeHelper=$a completedAtRefs=$b"
