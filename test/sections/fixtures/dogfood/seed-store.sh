#!/usr/bin/env bash
# Dogfood fixture store seeder — separates the NON-deterministic half of the
# fixture from the byte-identical builder. build.sh output must stay
# reproducible (diff -r of two builds is empty), but a store seeded through
# the real CLI embeds timestamps and machine-local lock records, so this
# script does the seeding at RUNTIME (the acceptance section invokes it, the
# smoke drives it manually). Safe to re-run: `auto on` reconfigures an
# existing healthy store to the requested flags, and the marker write is a
# plain overwrite.
#
# What lands where (everything inside <fixture-dir>):
#   <fixture>/xdg/data   XDG_DATA_HOME override — the store resolves to
#                        <fixture>/xdg/data/gos/local:<hash> (the fixture
#                        repo has no remote, so the store key is the
#                        path-derived local: identity)
#   <fixture>/home       HOME override for the seeded CLI calls (keeps the
#                        real ~ untouched)
#   <fixture>/.gos/cache/dogfood-sentinel.marker
#                        pre-armed sentinel: the fixture suite's sentinel
#                        section takes its second-pass instant-green path so
#                        a smoke cycle cannot hang in the 600s block window.
#                        The kill/restart acceptance DELETES this marker
#                        before its first run to re-arm first-pass blocking.
#
# Store policy carried here (the nested runner env never sees GOS_AUTO_*):
#   --max-retries 1      breaker N = 1 — the iteration ceiling for the cycle
#   --timeout-wall 180   nested wall budget (>= 120s: the sentinel's 600s
#                        sleep must be killed by the section harness, never
#                        by the wall timer faking a timeout record)
#   --timeout-idle 60    idle budget
#
# Usage: seed-store.sh <fixture-dir>
# Output: exactly one line on success — "store: <store-dir>"
set -euo pipefail

refuse() { echo "✗ $1" >&2; exit 1; }

if [ $# -ne 1 ] || [ -z "$1" ]; then
  refuse "usage: seed-store.sh <fixture-dir> (exactly one non-empty argument)"
fi
FIXTURE="$(cd "$1" && pwd)" || refuse "cannot resolve fixture dir '$1'"
[ -f "$FIXTURE/bin/gos.cjs" ] || refuse "no bin/gos.cjs under '$FIXTURE' — pass a built fixture dir"

XDG="$FIXTURE/xdg/data"
HOME_OVERRIDE="$FIXTURE/home"
mkdir -p "$XDG" "$HOME_OVERRIDE"

# Seed through the REAL fixture CLI with the store env overrides. Re-runs
# reconfigure the same store (mode/profile/limits/timeouts) instead of
# forking a second one.
( cd "$FIXTURE" && XDG_DATA_HOME="$XDG" HOME="$HOME_OVERRIDE" \
  node bin/gos.cjs auto on --max-retries 1 --timeout-wall 180 --timeout-idle 60 ) \
  || refuse "fixture CLI 'auto on' failed"

# Pre-arm the sentinel marker: presence alone flips the section to its
# restarted-run instant-exit path (content is diagnostic only).
MARKER="$FIXTURE/.gos/cache/dogfood-sentinel.marker"
mkdir -p "$FIXTURE/.gos/cache"
printf 'pid=0\npgid=0\narmed_at=2026-01-01T00:00:00Z\nmode=pre-armed-by-seed\n' > "$MARKER"

# Resolve and print the store dir exactly the way the CLI derives it
# (XDG data home + gos/<repo-key>; the remote-less fixture keys on its
# resolved path).
STORE_DIR="$(node -e '
const path = require("path");
const fs = require("fs");
const crypto = require("crypto");
const os = require("os");
const root = fs.realpathSync(process.argv[1]);
const key = "local:" + crypto.createHash("sha256").update(root).digest("hex").slice(0, 16);
process.stdout.write(path.join(process.argv[2], "gos", key));
' "$FIXTURE" "$XDG")"

echo "store: $STORE_DIR"
