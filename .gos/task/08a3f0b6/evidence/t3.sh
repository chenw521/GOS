#!/usr/bin/env bash
# truth T3 evidence: ship-script parity across list present/removed/unreadable/stale
set -uo pipefail
E=.gos/task/08a3f0b6/evidence
{
  grep -hE 'T119\.3[a-l] ' .gos/cache/section-runs/20261117T101743Z-full29956.log
  echo "assert-hits: $(grep -hcE 'T119\.3[a-l] ' .gos/cache/section-runs/20261117T101743Z-full29956.log)"
} | tee "$E/t3.log"
