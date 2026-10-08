#!/usr/bin/env bash
# CHANGELOG promote helper — folds [Unreleased] entries into a new version
# section for <tag> via changelog-core.promoteUnreleased (which strips the
# UTC date stamps) and rewrites CHANGELOG.md in place via tmp+rename, then
# prints the promoted section. This script ONLY edits the file: the git
# commit of the promote and the GitHub Release creation belong to the
# release workflow, not here.
#
# Failure boundaries (all exit 1 with English guidance):
#   nothing-to-release  [Unreleased] holds no entries;
#   no-header           CHANGELOG.md lacks the '# ' title or the
#                       '## [Unreleased]' heading (skeleton broken);
#   version-rollback    <tag> does not sort above the newest version section.
#
# Usage: bash scripts/release-promote.sh <tag>
# Root overrides (same contract as release-validate.sh):
#   GOS_SELF_ROOT     repo providing bin/lib/ops/changelog-core.cjs
#                    (default: this script's parent directory)
#   GOS_RELEASE_ROOT  repo whose CHANGELOG.md is promoted in place
#                    (default: GOS_SELF_ROOT)
set -uo pipefail

fail() { echo "release-promote: FAIL: $1" >&2; exit 1; }

SELF_ROOT="${GOS_SELF_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RELEASE_ROOT="${GOS_RELEASE_ROOT:-$SELF_ROOT}"
CORE="$SELF_ROOT/bin/lib/ops/changelog-core.cjs"
CHANGELOG="$RELEASE_ROOT/CHANGELOG.md"

tag="${1:-}"
if [ -z "$tag" ] || [ -n "${2:-}" ]; then
  echo "usage: bash scripts/release-promote.sh <tag>" >&2
  exit 2
fi
stripped="${tag#v}"; stripped="${stripped#V}"
[ -f "$CORE" ] || fail "internal: changelog-core.cjs not found at $CORE"
[ -f "$CHANGELOG" ] || fail "CHANGELOG.md not found at $CHANGELOG"

PROMOTE_JS='
const fs = require("fs");
const core = require(process.argv[1]);
const file = process.argv[2];
const tag = process.argv[3];
const text = fs.readFileSync(file, "utf8");
const res = core.promoteUnreleased(text, tag);
if (!res.ok) { console.log(res.reason); process.exit(3); }
const tmp = file + ".promote-tmp";
fs.writeFileSync(tmp, res.text);
fs.renameSync(tmp, file);
const lines = res.text.split("\n");
const i = lines.findIndex((l) => l.indexOf("## [" + tag + "]") === 0);
for (let j = i; j >= 0 && j < lines.length; j++) {
  if (j > i && /^## /.test(lines[j])) break;
  console.log(lines[j]);
}
'
out="$(node -e "$PROMOTE_JS" "$CORE" "$CHANGELOG" "$stripped" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  printf '%s\n' "$out"
  exit 0
fi
if [ "$rc" -eq 3 ]; then
  case "$out" in
    nothing-to-release)
      fail "nothing to release — [Unreleased] in $CHANGELOG holds no entries; add entries (gos changelog add) before promoting" ;;
    no-header)
      fail "broken skeleton — CHANGELOG.md needs exactly one '# ' title and a '## [Unreleased]' heading; restore the Keep-a-Changelog skeleton, then retry" ;;
    version-rollback)
      fail "version rollback — '$stripped' does not sort above the newest version section in $CHANGELOG; use a higher tag" ;;
    *)
      fail "unexpected promote result: $out" ;;
  esac
fi
fail "internal error (node exit $rc): $out"
