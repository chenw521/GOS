#!/usr/bin/env bash
# Truth T2 — foreign-task rows (lesson or add-then-rm) never satisfy F-1
dir="$(cd "$(dirname "$0")" && pwd)"
echo "foreign-blocks=$(grep -c "foreign-task lesson row (today) does NOT exempt (exit 1)" "$dir/t1t2-raw.log") add-then-rm=$(grep -c "this-task add row whose entry was removed does NOT exempt (exit 1)" "$dir/t1t2-raw.log") stale-skip=$(grep -c "anchored skip with stale incidents snapshot does NOT exempt (exit 1)" "$dir/t1t2-raw.log")"
