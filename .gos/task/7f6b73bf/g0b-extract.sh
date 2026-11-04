#!/usr/bin/env bash
# Pinned family-coverage extraction for G0b — reproducible literal set.
# Usage: bash .gos/task/7f6b73bf/g0b-extract.sh > literals.txt
# Diff the output against the six families + F-unknown in the spec; any
# literal matched by neither an exact member nor a declared wildcard
# (invalid-*, host-*, leg-*) fails pre-flight until the family table is
# amended. One row per family name in the spec table is asserted by the
# consumer, not here.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
grep -h "reason: '" bin/lib/ops/auto/*.cjs \
  | sed -n "s/.*reason: '\([a-z][a-z0-9-]*\)'.*/\1/p" | sort -u
