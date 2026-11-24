#!/usr/bin/env bash
# Manifest coverage check — structural + completeness validation of a
# sections run manifest. Takes the manifest PATH as the first argument so
# pinned sandbox runs (manifest under the test base) and literal runs
# (repo-root manifest) validate through the same entry point; without an
# argument the repo-root literal-run manifest is checked (backward
# compatible). Three check groups, all machine-verdict style:
#   schema    parsable schema_version 2 manifest; sections_run/results
#             shapes; tree_source in {pinned, live} with a pin sha
#             exactly when pinned (the Shared Manifest Contract); a
#             non-empty log reference.
#   coverage  sections_run equals the full on-disk section set — every
#             basename under test/sections matching the T*.test.sh
#             pattern, same names and same count — so a filtered or
#             partial run can never validate.
#   floors    every result's pass count meets or exceeds the per-section
#             pass floor recorded in test/sections/baseline.json; the
#             baseline location is overridable through
#             MANIFEST_COVERAGE_BASELINE for runs whose section tree
#             lives outside this checkout. Baseline keys store section
#             names with hyphens encoded as underscores (an anchor-free
#             data encoding; no section name contains an underscore), so
#             the comparison decodes keys back to basenames.
# Usage: bash test/checks/manifest-coverage.sh [manifest-path]
set -uo pipefail

GOS_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="${1:-$GOS_ROOT/.gos/cache/run-manifest.json}"
BASELINE="${MANIFEST_COVERAGE_BASELINE:-$GOS_ROOT/test/sections/baseline.json}"

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

# Coverage + floors verdict: one python pass over the manifest, the
# section listing, and the baseline file. Precise diffs (missing names,
# unknown names, per-section count shortfalls) ride the verdict line so a
# red run points straight at the gap. The section listing defaults to the
# live checkout; a pinned manifest (a run over another tree) overrides it
# via MANIFEST_COVERAGE_SECTIONS so coverage compares against the tree the
# manifest actually ran — never the wrong checkout.
SECTIONS_DIR="${MANIFEST_COVERAGE_SECTIONS:-$GOS_ROOT/test/sections}"
VERDICT2="$(python3 - "$MANIFEST" "$SECTIONS_DIR" "$BASELINE" <<'PY'
import json, os, re, sys
from collections import Counter

manifest_path, sections_dir, baseline_path = sys.argv[1], sys.argv[2], sys.argv[3]
problems = []

try:
    m = json.load(open(manifest_path))
except Exception as e:
    print(f"BAD|manifest unparsable: {e}")
    raise SystemExit

full = sorted(
    f[: -len(".test.sh")]
    for f in os.listdir(sections_dir)
    if re.fullmatch(r"T[^/]*\.test\.sh", f) and os.path.isfile(os.path.join(sections_dir, f))
)
if not full:
    problems.append(f"no section scripts found under {sections_dir}")

ran = m.get("sections_run")
if not isinstance(ran, list) or not all(isinstance(x, str) for x in ran):
    problems.append("sections_run is not a list of names")
    ran = []
ran_sorted = sorted(ran)

if ran_sorted != full:
    ran_c, full_c = Counter(ran_sorted), Counter(full)
    not_run = sorted((full_c - ran_c).elements())
    unknown = sorted((ran_c - full_c).elements())
    diff = []
    if not_run:
        diff.append(f"not run ({len(not_run)}): {' '.join(not_run)}")
    if unknown:
        diff.append(f"run but not on disk or duplicated ({len(unknown)}): {' '.join(unknown)}")
    if not diff:
        diff.append(f"count mismatch: ran {len(ran_sorted)}, on disk {len(full)}")
    problems.append(
        f"sections_run != full section set (ran {len(ran_sorted)}, on disk {len(full)}): "
        + "; ".join(diff)
    )

results = m.get("results")
if not isinstance(results, dict):
    problems.append("results is not an object")
    results = {}

try:
    with open(baseline_path, encoding="utf-8") as fh:
        b = json.load(fh)
except Exception as e:
    problems.append(f"baseline unreadable at {baseline_path}: {e}")
    b = None

if b is not None:
    if not isinstance(b.get("schema_version"), int):
        problems.append("baseline schema_version missing or not an integer")
    floors = b.get("sections_pass_floor")
    if not isinstance(floors, dict) or not all(
        isinstance(k, str) and re.fullmatch(r"T[^/]*", k) and isinstance(v, int) and v >= 0
        for k, v in floors.items()
    ):
        problems.append("baseline sections_pass_floor must map section names to non-negative integers")
        floors = {}
    floors = {k.replace("_", "-"): v for k, v in floors.items()}
    for name in sorted(floors):
        floor = floors[name]
        res = results.get(name)
        got = res.get("pass") if isinstance(res, dict) else None
        if not isinstance(got, int):
            problems.append(f"{name}: no pass count in results (floor {floor})")
        elif got < floor:
            problems.append(f"{name}: pass {got} below the baseline floor {floor}")

    # Skip entries: a section that refused to run (sandbox engine missing, …)
    # must carry its refusal reason — an empty or non-string skip field is a
    # silent pass and fails here.
    for name in sorted(results):
        res = results.get(name)
        if isinstance(res, dict) and "skip" in res:
            reason = res.get("skip")
            if not isinstance(reason, str) or not reason.strip():
                problems.append(f"{name}: skip entry without a non-empty reason")

print("OK" if not problems else "BAD|" + "; ".join(problems))
PY
)"

if [ "$(printf '%s' "$VERDICT2" | cut -d'|' -f1)" = "OK" ]; then
  check 0 "sections_run covers the full section set and every pass meets the baseline ($MANIFEST)"
else
  check 1 "coverage/floors ($MANIFEST): $(printf '%s' "$VERDICT2" | cut -d'|' -f2-)"
fi

[ "$fail" -eq 0 ] && exit 0 || exit 1
