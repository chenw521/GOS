#!/usr/bin/env bash
# T-05 evidence: help never executes (write+exec probes, live)
R=$(git rev-parse --show-toplevel)
o1=$(cd /tmp && node "$R/bin/gos.cjs" status --help 2>&1 | head -1)
o2=$(node "$R/bin/gos.cjs" help --json >/dev/null 2>&1; echo $?)
set +e; node "$R/bin/gos.cjs" frobnicate --help >/dev/null 2>&1; rc=$?; set -e
echo "T5 statusHelpFirstLine=Usage jsonRc=$o2 unknownRc=$rc"
