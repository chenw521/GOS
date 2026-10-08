#!/usr/bin/env bash
# gos-map:none
# T35d: negative assertions (zero cooldown mechanism) + runner anchor self-check
# Covers: D-32 (plan T7)
# Env: GOS (CLI path), GOS_ROOT

echo "--- T35d: D-32 negative assertion (no cooldown machinery) + runner anchor ---"

# N1 bin/gos.cjs has no cooldown mechanism (guards against implementing one speculatively)
N=$(grep -ri "cooldown\|冷静期" "$GOS_ROOT/bin/gos.cjs" | wc -l)
assert_eq "N1 no cooldown machinery in gos.cjs" "0" "$N"

# N2 runner anchor present (headless determinism)
grep -q "^export GOS_HEADLESS=1" "$GOS_ROOT/test/run-sections.sh"
assert_exit "N2 runner headless anchor pinned" 0 "$?"

echo "T35d-u-negative done"
