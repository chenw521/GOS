#!/usr/bin/env bash
# Push-range commitlint with GitHub squash-suffix awareness.
#
# GitHub squash-merges append an automatic " (#N)" suffix to the commit
# header — platform-generated, not author-controllable, and invisible to
# PR-side lint (the suffix only exists after the merge). This script lints
# each commit in the push range individually with that suffix stripped from
# the FIRST line only; the author-controlled message stays fully policed.
# Usage: push-lint-squash.sh <before-sha> <after-sha>
set -euo pipefail

BEFORE="${1:?usage: push-lint-squash.sh <before> <after>}"
AFTER="${2:?usage: push-lint-squash.sh <before> <after>}"
CFG="$(cd "$(dirname "$0")/../.." && pwd)/commitlint.config.yaml"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

for c in $(git rev-list "$BEFORE..$AFTER"); do
  git log -1 --format=%B "$c" | python3 -c '
import re, sys
lines = sys.stdin.read().split("\n")
lines[0] = re.sub(r" \(#[0-9]+\)$", "", lines[0])
sys.stdout.write("\n".join(lines))
' > "$tmp"
  echo "lint: $c $(head -c 60 "$tmp" | tr "\n" " ")"
  npx --yes commitlint@19 --config "$CFG" --edit "$tmp"
done
echo "push-range lint: all commits clean (squash suffix stripped for length checks)"
