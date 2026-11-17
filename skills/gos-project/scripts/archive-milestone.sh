#!/usr/bin/env bash
# Retired: milestone archiving is owned by the CLI (`gos milestone close`).
# This stub refuses so stale callers discover the new flow instead of
# performing the hand-rolled git mv/tag ceremony.
set -euo pipefail
echo "retired: use gos milestone close"
exit 1
