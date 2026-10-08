#!/usr/bin/env bash
# Release precondition validator — the fail-fast gate that must pass before
# any irreversible release action. Checks, in order:
#   1. the tag is valid semver (optional leading v, which is stripped);
#   2. the stripped tag equals the package.json version;
#   3. the tag sorts above the newest version section in CHANGELOG.md;
#   4. [Unreleased] holds at least one entry;
#   5. the npm token works (npm whoami).
# The first violation aborts with an English reason; exit 0 means every
# precondition holds. CHANGELOG parsing and version precedence reuse
# bin/lib/ops/changelog-core.cjs (single source, no drift).
#
# Usage: bash scripts/release-validate.sh <tag> [--dry-run]
#   --dry-run  local offline mode: content checks still run, but a failing
#              or missing npm whoami is tolerated with a notice.
# Root overrides (for sandbox tests):
#   GOS_SELF_ROOT     repo providing bin/lib/ops/changelog-core.cjs
#                     (default: this script's parent directory)
#   GOS_RELEASE_ROOT  repo under validation, where package.json and
#                     CHANGELOG.md are read (default: GOS_SELF_ROOT)
set -uo pipefail

usage() {
  echo "usage: bash scripts/release-validate.sh <tag> [--dry-run]" >&2
  echo "  <tag>      release tag, e.g. v0.19.0 (leading v optional)" >&2
  echo "  --dry-run  tolerate a missing npm login (local offline check)" >&2
}

fail() { echo "release-validate: FAIL: $1" >&2; exit 1; }

SELF_ROOT="${GOS_SELF_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RELEASE_ROOT="${GOS_RELEASE_ROOT:-$SELF_ROOT}"
CORE="$SELF_ROOT/bin/lib/ops/changelog-core.cjs"

tag="${1:-}"
dry_run=0
for arg in "${@:2}"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    *) usage; exit 2 ;;
  esac
done
if [ -z "$tag" ] || [ "$tag" = "--dry-run" ]; then usage; exit 2; fi
[ -f "$CORE" ] || fail "internal: changelog-core.cjs not found at $CORE"

# --- 1. semver (POSIX ERE; official semver grammar plus optional leading v) ---
SEMVER_RE='^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$'
if ! [[ $tag =~ $SEMVER_RE ]]; then
  fail "semver: '$tag' is not a valid semver tag (expected vX.Y.Z with optional prerelease/build)"
fi
stripped="${tag#v}"; stripped="${stripped#V}"
echo "ok semver: '$tag' -> '$stripped'"

# --- 2. tag must equal package.json version ---
PKG="$RELEASE_ROOT/package.json"
[ -f "$PKG" ] || fail "package.json: not found at $PKG"
pkg_version="$(node -p 'require(process.argv[1]).version' "$PKG" 2>/dev/null)" \
  || fail "package.json: cannot read the version field of $PKG"
[ -n "$pkg_version" ] && [ "$pkg_version" != "undefined" ] \
  || fail "package.json: no version field at $PKG"
if [ "$stripped" != "$pkg_version" ]; then
  fail "version mismatch: tag '$stripped' != package.json '$pkg_version' — set package.json version to the tag first"
fi
echo "ok match: tag '$stripped' == package.json version"

# --- 3 + 4. CHANGELOG ordering and non-empty [Unreleased] (one node pass) ---
CH_CHECK='
const fs = require("fs");
const path = require("path");
const core = require(process.argv[1]);
const root = process.argv[2];
const tag = process.argv[3];
function parseSemver(t) {
  const m = String(t).match(/^v?(\d+)\.(\d+)\.(\d+)(?:-([\dA-Za-z-]+(?:\.[\dA-Za-z-]+)*))?/);
  if (!m) return null;
  return { c: [+m[1], +m[2], +m[3]], p: (m[4] || "").split(".").filter(Boolean) };
}
function cmp(a, b) {
  for (let i = 0; i < 3; i++) if (a.c[i] !== b.c[i]) return a.c[i] - b.c[i];
  if (a.p.length === 0 && b.p.length === 0) return 0;
  if (a.p.length === 0) return 1;
  if (b.p.length === 0) return -1;
  for (let i = 0; i < Math.max(a.p.length, b.p.length); i++) {
    const x = a.p[i], y = b.p[i];
    if (x === undefined) return -1;
    if (y === undefined) return 1;
    const xn = /^\d+$/.test(x), yn = /^\d+$/.test(y);
    if (xn && yn) { if (+x !== +y) return +x - +y; }
    else if (xn) return -1;
    else if (yn) return 1;
    else if (x !== y) return x < y ? -1 : 1;
  }
  return 0;
}
const file = path.join(root, "CHANGELOG.md");
let text;
try { text = fs.readFileSync(file, "utf8"); }
catch { console.error("changelog: CHANGELOG.md not found at " + file); process.exit(12); }
const parsed = core.parseChangelog(text);
const latest = parsed.versions[0];
if (latest) {
  const L = parseSemver(latest.tag), T = parseSemver(tag);
  if (!L) {
    console.error("changelog: newest version heading [" + latest.tag + "] is not semver — fix CHANGELOG.md before releasing");
    process.exit(12);
  }
  if (cmp(T, L) <= 0) {
    console.error("ordering: tag " + tag + " does not sort above the newest CHANGELOG version " + latest.tag + " — refusing a version rollback");
    process.exit(10);
  }
} else {
  latest = { tag: "(none)" };
}
if (parsed.unreleased.length === 0) {
  console.error("unreleased: [Unreleased] in CHANGELOG.md has no entries — add entries before releasing");
  process.exit(11);
}
// stdout carries results only after every check has passed, so a failure
// message can never be interleaved with partial success output
console.log(latest.tag);
console.log(parsed.unreleased.length);
'
out="$(node -e "$CH_CHECK" "$CORE" "$RELEASE_ROOT" "$stripped" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || fail "$out"
latest="$(printf '%s\n' "$out" | sed -n 1p)"
count="$(printf '%s\n' "$out" | sed -n 2p)"
echo "ok ordering: tag '$stripped' > CHANGELOG latest '$latest'"
echo "ok unreleased: $count entries under [Unreleased]"

# --- 5. npm token precheck ---
if command -v npm >/dev/null 2>&1 && who="$(npm whoami 2>/dev/null)"; then
  echo "ok npm: authenticated as '$who'"
else
  if [ "$dry_run" -eq 1 ]; then
    echo "skip npm: whoami unavailable — tolerated in --dry-run (content checks above still ran)"
  else
    fail "npm: 'npm whoami' failed — the npm token is missing or invalid; ensure NPM_TOKEN is configured"
  fi
fi

echo "release-validate: all preconditions pass (tag '$stripped')"
