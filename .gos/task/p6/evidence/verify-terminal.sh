#!/usr/bin/env bash
# Terminal-state evidence: lint exits clean and the whitelist holds only
# permanent categories (zero in-flight-sweep entries).
set -u
cd "$(dirname "$0")/../../../.." || exit 1
lint_rc=0
bash test/checks/ai-trace-lint.sh > /dev/null 2>&1 || lint_rc=$?
entries=$(node -e 'const fs=require("fs");const p=process.cwd()+"/.gos/ai-trace-whitelist.json";const w=JSON.parse(fs.readFileSync(p,"utf8"));process.stdout.write(String(w.filter(e=>e.category==="in-flight-sweep").length))')
echo "lint_exit=${lint_rc} in_flight_sweep_entries=${entries}"
test "$lint_rc" -eq 0 -a "$entries" -eq 0
