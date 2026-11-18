#!/usr/bin/env bash
# Manifest coverage check — structural validation of a sections run
# manifest. Takes the manifest PATH as the first argument so pinned sandbox
# runs (manifest under TESTBASE) and literal runs (repo-root manifest)
# validate through the same entry point; without an argument the repo-root
# literal-run manifest is checked (backward compatible).
# Asserts: parsable schema_version 2 manifest; sections_run/results shapes;
# tree_source in {pinned, live} with a pin sha exactly when pinned (the
# Shared Manifest Contract); a non-empty log reference.
# Usage: bash test/checks/manifest-coverage.sh [manifest-path]
set -uo pipefail

GOS_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="${1:-$GOS_ROOT/.gos/cache/run-manifest.json}"

fail=0
check() {
  if [ "$1" -eq 0 ]; then echo "  ✓ $2"
  else echo "  ✗ $2"; fail=1; fi
}

if [ ! -f "$MANIFEST" ]; then
  echo "✗ manifest not found: $MANIFEST (pass the path as the first argument)"
  exit 1
fi

VERDICT="$(python3 - "$MANIFEST" <<'PY'
import json, re, sys

problems = []
try:
    m = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"BAD|unparsable: {e}")
    raise SystemExit

if m.get("schema_version") != 2:
    problems.append(f"schema_version {m.get('schema_version')!r} != 2")
if not isinstance(m.get("sections_run"), list):
    problems.append("sections_run is not a list")
if not isinstance(m.get("results"), dict):
    problems.append("results is not an object")
ts = m.get("tree_source")
pin = m.get("pin")
if ts not in ("pinned", "live"):
    problems.append(f"tree_source {ts!r} not in {{pinned, live}}")
if ts == "pinned" and not (isinstance(pin, str) and re.fullmatch(r"[0-9a-f]{7,64}", pin)):
    problems.append(f"pinned manifest carries no valid pin: {pin!r}")
if ts == "live" and pin is not None:
    problems.append(f"live manifest must carry pin null, got {pin!r}")
if not m.get("log"):
    problems.append("log reference missing")

print("OK" if not problems else "BAD|" + "; ".join(problems))
PY
)"

if [ "$(printf '%s' "$VERDICT" | cut -d'|' -f1)" = "OK" ]; then
  check 0 "manifest $MANIFEST satisfies the schema + tree-provenance contract"
else
  check 1 "manifest $MANIFEST: $(printf '%s' "$VERDICT" | cut -d'|' -f2-)"
fi

[ "$fail" -eq 0 ] && exit 0 || exit 1
