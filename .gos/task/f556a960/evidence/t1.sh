#!/usr/bin/env bash
# Evidence: the dogfood cycle note exists as an ignored cache artifact.
# Checks: file present and non-empty, lives under the machine-local cache
# root, is git-ignored (check-ignore exit 0, absent from ls-files), and
# carries every mandatory record section plus the cycle anchors.
set -u
cd "$(dirname "$0")/../../../.." || exit 1

NOTE=".gos/cache/dogfood-cycle-note.md"
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -f "$NOTE" ] || fail "note artifact missing at $NOTE"
[ -s "$NOTE" ] || fail "note artifact is empty"

case "$NOTE" in
  .gos/cache/*) ;;
  *) fail "note artifact must live under .gos/cache/" ;;
esac

git check-ignore -q "$NOTE" || fail "note artifact is not git-ignored"
[ -z "$(git ls-files "$NOTE")" ] || fail "note artifact must never be tracked"

for section in \
  "## Cycle identity" \
  "## Breaker pre-state" \
  "## Re-enable" \
  "## Spawned-session observations" \
  "## Host observations" \
  "## Protocol items not exercised"; do
  grep -qF "$section" "$NOTE" || fail "missing section: $section"
done

grep -qF "f556a960" "$NOTE" || fail "missing cycle task anchor f556a960"
grep -qF "2026-11-20T03:54:58.214Z" "$NOTE" || fail "missing breaker trip timestamp"

echo "t1: dogfood cycle note verified (present, ignored, complete)"
