#!/usr/bin/env bash
# T-06 evidence: rename verb surfaces
R=$(git rev-parse --show-toplevel)
h=$(node "$R/bin/gos.cjs" help phase 2>&1 | grep -c "rename")
echo "T6 renameInHelp=$h"
