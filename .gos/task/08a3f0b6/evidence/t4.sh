#!/usr/bin/env bash
# truth T4 evidence: guided rotation lifecycle incl. approve hard gate, stale branch
set -uo pipefail
E=.gos/task/08a3f0b6/evidence
{
  grep -hE 'T119\.(7[g-i]|8[k-l]|9[c-f]) ' .gos/cache/section-runs/20261117T101743Z-full29956.log
  echo "assert-hits: $(grep -hcE 'T119\.(7[g-i]|8[k-l]|9[c-f]) ' .gos/cache/section-runs/20261117T101743Z-full29956.log)"
} | tee "$E/t4.log"
