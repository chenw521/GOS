#!/usr/bin/env bash
# T-04 evidence: -der payload rebuilt (local-only zone, non-replayable on clones)
R=$(git rev-parse --show-toplevel)
A="$R/.gos/archive/2026-11-10-v1.0.0-task-commit-advance-destination-der/task/1a2e46f3"
d=$(diff <(git -C "$R" show 493a9e7:.gos/state.json) <(sed '/"completed_at"/d;/completed_at_retro/d' "$A/state.json") | wc -l)
p=$(ls "$A/PROVENANCE.md" 2>/dev/null | wc -l)
k=$(grep -c "^class:\|^sources:\|^lost:" "$A/PROVENANCE.md")
echo "T4 diffLines=$d provenanceFiles=$p frontMatterKeys=$k"
