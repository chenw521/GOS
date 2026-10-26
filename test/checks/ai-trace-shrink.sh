#!/usr/bin/env bash
# ai-trace whitelist shrink guard — on main the tracker may only shrink.
#
# Compared against origin/main, .gos/ai-trace-whitelist.json must not grow
# (neither entry count nor the sum of capped counts). Status semantics of
# the base...head diff for the whitelist path:
#   A  first landing — pass (the tracker starts from a zero baseline)
#   M  modified      — pass only when entries AND sum-of-counts shrank or held
#   R  renamed       — red (a rename must not silently void the discipline)
#   D  deleted       — red (same reason)
# A missing origin/main ref skips with an explicit advisory line, so fresh
# shallow clones without the base stay deployable; CI fetches the base.
set -euo pipefail

WL=".gos/ai-trace-whitelist.json"
BASE="origin/main"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null 2>&1; then
  echo "ℹ ai-trace shrink: base ref ${BASE} not available — advisory skip (fetch the base to make this guard bite)"
  exit 0
fi

if ! git cat-file -e "${BASE}:${WL}" 2>/dev/null; then
  if git cat-file -e "HEAD:${WL}" 2>/dev/null || [ -f "$WL" ]; then
    echo "✓ ai-trace shrink: first landing against a zero baseline"
    exit 0
  fi
  echo "✓ ai-trace shrink: no whitelist on either side — nothing to guard"
  exit 0
fi

if ! git cat-file -e "HEAD:${WL}" 2>/dev/null; then
  echo "✗ ai-trace shrink: whitelist exists on the base but is gone at HEAD — deletion must not silently void the discipline"
  exit 1
fi

status="$(git diff --name-status "${BASE}...HEAD" -- "$WL" | awk '{print $1}' | head -n1)"
if [ -z "$status" ]; then
  echo "✓ ai-trace shrink: whitelist unchanged versus the base"
  exit 0
fi
case "$status" in
  A*)
    echo "✓ ai-trace shrink: first landing against a zero baseline"
    exit 0
    ;;
  R*)
    echo "✗ ai-trace shrink: whitelist renamed (${status}) — the tracker may not be relocated away from its debt"
    exit 1
    ;;
  D*)
    echo "✗ ai-trace shrink: whitelist deleted — the tracker may not be dropped while debt remains"
    exit 1
    ;;
  M*) ;;
  *)
    echo "✗ ai-trace shrink: unexpected diff status '${status}' for the whitelist"
    exit 1
    ;;
esac

git show "${BASE}:${WL}" >"$tmp/old-whitelist.json"
node - "$tmp/old-whitelist.json" "$WL" <<'SHRINK_EOF'
const fs = require('fs');
const [oldPath, newPath] = process.argv.slice(2);
const load = (p) => {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); }
  catch (e) { console.error('✗ ai-trace shrink: whitelist unreadable: ' + p); process.exit(1); }
};
const oldWl = load(oldPath);
const newWl = load(newPath);
const weight = (wl) => wl.reduce((a, e) => a + (Number.isInteger(e.maxHits) ? e.maxHits : 0), 0);
const oldEntries = oldWl.length, newEntries = newWl.length;
const oldWeight = weight(oldWl), newWeight = weight(newWl);
const fmt = (entries, w) => `entries=${entries}, sum-of-counts=${w}`;
if (newEntries > oldEntries || newWeight > oldWeight) {
  console.error(`✗ ai-trace shrink: whitelist grew versus the base — base ${fmt(oldEntries, oldWeight)}, head ${fmt(newEntries, newWeight)}; sweep batches must shrink the tracker, never extend it`);
  process.exit(1);
}
console.log(`✓ ai-trace shrink: held or shrank — base ${fmt(oldEntries, oldWeight)}, head ${fmt(newEntries, newWeight)}`);
SHRINK_EOF
