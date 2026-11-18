#!/usr/bin/env bash
# truth T5 evidence: README coverage, gate hint strings, scan excluded-count line
set -uo pipefail
E=.gos/task/08a3f0b6/evidence
{
  grep -c map-ignore README.md README.zh-CN.md
  echo "hint-fragments: $(grep -c 'exclude via .gos/map-ignore then rescan' bin/lib/ops/gate.cjs)"
  grep -hE 'T119\.(2b|4c) ' .gos/cache/section-runs/20261117T101743Z-full29956.log
} | tee "$E/t5.log"
