#!/usr/bin/env bash
# Truth T4 — init-born rows survive a milestone close as init-owned
dir="$(cd "$(dirname "$0")" && pwd)"
echo "dec=$(grep -c "report counts init-owned decisions" "$dir/t4-raw.log") req=$(grep -c "report counts init-owned requirements" "$dir/t4-raw.log") strictP0=$(grep -c "strict P0 placeholder classifies init-owned" "$dir/t4-raw.log") survivors=$(grep -c "post-close wipe side (carried 6 phases, 20 dec" "$dir/t4-raw.log")"
