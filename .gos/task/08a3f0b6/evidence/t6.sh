#!/usr/bin/env bash
# truth T6 evidence: self-repo scan parity, deps shape, pack-check
set -u
E=.gos/task/08a3f0b6/evidence
{
  node bin/gos.cjs map scan >/dev/null 2>&1 && echo "self-scan: exit 0"
  node -e 'const d=require("./.gos/cache/deps.json");if(d.schema_version!==3||("ignored" in d)||("ignore_dead" in d))process.exit(1);console.log("deps-shape-ok schema",d.schema_version)'
  bash test/pack-check.sh >/dev/null && echo PACKCHECK-GREEN
  grep -hE 'T119\.12' .gos/cache/section-runs/20261117T101743Z-full29956.log
} | tee "$E/t6.log"
