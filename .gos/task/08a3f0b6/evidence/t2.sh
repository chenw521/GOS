#!/usr/bin/env bash
# truth T2 evidence: list written with provenance, body exact, deleted at zero
set -uo pipefail
E=.gos/task/08a3f0b6/evidence
{
  grep -hE 'T119\.(2e|2f|2g|2h|5b) ' .gos/cache/section-runs/20261117T101743Z-full29956.log
  echo "assert-hits: $(grep -hcE 'T119\.(2e|2f|2g|2h|5b) ' .gos/cache/section-runs/20261117T101743Z-full29956.log)"
} | tee "$E/t2.log"
