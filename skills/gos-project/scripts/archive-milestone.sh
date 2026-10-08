#!/usr/bin/env bash
# Atomic milestone archive ordering (GSD bug #2630 lesson):
# archive → commit → THEN delete original → commit deletion.
set -euo pipefail
V="${1:?usage: archive-milestone.sh <version-tag e.g. v0.1>}"
P=.gos/project
[ -d "$P" ] || { echo "no project dir"; exit 1; }
mkdir -p "$P/milestones"
git mv "$P/ROADMAP.md" "$P/milestones/$V-ROADMAP.md"
git mv "$P/REQUIREMENTS.md" "$P/milestones/$V-REQUIREMENTS.md" 2>/dev/null || true
git commit -q -m "milestone: archive $V (archive-before-delete)"
git tag -a "$V" -m "milestone: $V" 2>/dev/null || echo "(tag exists)"
echo "✓ $V archived (commit + tag). Next: new-project mode regenerates ROADMAP/REQUIREMENTS fresh."
