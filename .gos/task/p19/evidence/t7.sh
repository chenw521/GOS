#!/usr/bin/env bash
# T-07 evidence: fresh-checkout census pass without the hotfix
R=$(git rev-parse --show-toplevel)
m=$(grep -c "mkdir -p .gos/cache" "$R/.github/workflows/ci.yml" || true)
echo "T7 ciMkdirLines=$m"
