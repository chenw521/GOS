#!/usr/bin/env bash
# Truth T1 — cross-midnight archival passes on the this-task anchor
dir="$(cd "$(dirname "$0")" && pwd)"
echo "cross-midnight-exempts=$(grep -c "anchored lesson dated yesterday still exempts (cross-midnight) (exit 0)" "$dir/t1t2-raw.log")"
