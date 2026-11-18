#!/usr/bin/env bash
# Truth T3 — DECISIONS.md renders init explicitly, no bare P0 column value
dir="$(cd "$(dirname "$0")" && pwd)"
echo "note=$(grep -c "header note explains the init phase" "$dir/t3-raw.log") nobareP0=$(grep -c "no bare P0 column value anywhere" "$dir/t3-raw.log") cell=$(grep -c "init-born row renders the init cell" "$dir/t3-raw.log") legacy=$(grep -c "legacy P0 placeholder migrates to init" "$dir/t3-raw.log")"
