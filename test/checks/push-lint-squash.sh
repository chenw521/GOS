#!/usr/bin/env bash
# Push-range commitlint with GitHub squash-suffix awareness.
#
# GitHub squash-merges append an automatic " (#N)" suffix to the commit
# header — platform-generated, not author-controllable, and invisible to
# PR-side lint (the suffix only exists after the merge). This script lints
# each commit in the push range individually with that suffix stripped from
# the FIRST line only; the author-controlled message stays fully policed.
# Usage: push-lint-squash.sh <before-sha> <after-sha>
#        push-lint-squash.sh --subject "<candidate header>"
# The --subject mode is the authoring-time guard: it lints one candidate
# header (squash suffix stripped) so a PR title or gh merge --subject can be
# checked BEFORE the platform squashes it — the push-range lint above only
# fires after the merge has already landed on main.
set -euo pipefail

CFG="$(cd "$(dirname "$0")/../.." && pwd)/commitlint.config.yaml"

if [ "${1:-}" = "--subject" ]; then
  CAND="${2:?usage: push-lint-squash.sh --subject \"<candidate header>\"}"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  printf '%s\n' "$CAND" | python3 -c '
import re, sys
lines = sys.stdin.read().split("\n")
lines[0] = re.sub(r" \(#[0-9]+\)$", "", lines[0])
sys.stdout.write("\n".join(lines))
' > "$tmp"
  echo "subject lint: $(head -c 60 "$tmp" | tr "\n" " ")"
  npx --yes commitlint@19 --config "$CFG" --edit "$tmp"
  echo "subject lint: clean (squash suffix stripped for length checks)"
  exit 0
fi

BEFORE="${1:?usage: push-lint-squash.sh <before> <after>}"
AFTER="${2:?usage: push-lint-squash.sh <before> <after>}"

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
