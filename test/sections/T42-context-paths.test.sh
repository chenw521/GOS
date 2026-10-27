#!/usr/bin/env bash
# gos-map:fn bin/lib/task/context.cjs#fn:cmdContext bin/lib/task/context.cjs#fn:archiveSlugParts bin/lib/core/state.cjs#fn:ensureTaskDir
# gos-map:cmd context
# context artifact_paths supply + phase-id rules (conflict detection / ts-fallback / 'n' collapse removed)
T42_DIR=""

t42_setup() {
  T42_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t42"
  mkdir -p "$T42_DIR" && cd "$T42_DIR" || exit 1
}
t42_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T42_DIR"; }

t42_setup
trap 't42_teardown' EXIT

PASS=0
FAIL=0

echo "--- T42: context artifact_paths + phase-id rules ---"

git init -q . && git commit -q --allow-empty -m root
node "$GOS" init 1 "t42 supply probe" >/dev/null 2>&1

# python verification outlet: always exits 0, result = first line OK or an error string (bash only compares strings; set -e safe)
vcheck() {
  local code
  code="$(printf '%s\n' "$1" | sed 's/^/    /')"
  python3 -c "
import json, os
def run():
$code
try:
    print(run() or 'OK')
except Exception as e:
    print('ERR: %s' % e)
" 2>/dev/null
}

# .1 context build: artifact_paths.evidence_dir is absolute + directory exists
node "$GOS" context build > ctx1.json 2>/dev/null
V1="$(vcheck '
import json, os
d = json.load(open("ctx1.json"))
ap = d.get("artifact_paths")
assert ap, "NO-ARTIFACT-PATHS"
ed = ap.get("evidence_dir")
assert ed, "NO-EVIDENCE-DIR"
assert os.path.isabs(ed), "NOT-ABS: %r" % ed
assert os.path.isdir(ed), "DIR-MISSING: %r" % ed
assert "/task/" in ed, "NOT-TASK-ZONE: %r" % ed
return "OK"
')"
if [ "$V1" = "OK" ]; then
  echo "  ✓ T42.1 context build supplies abs evidence_dir (dir exists)"; PASS=$((PASS+1))
else
  echo "  ✗ T42.1 $V1"; FAIL=$((FAIL+1))
fi

# .2 idempotent: second context build reports no conflict for the same path
node "$GOS" context build >/dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "  ✓ T42.2 context idempotent (no false conflict on re-run)"; PASS=$((PASS+1))
else
  echo "  ✗ T42.2 re-run failed"; FAIL=$((FAIL+1))
fi

# .3 think/plan/verify stages each supply the right fields
node "$GOS" context think > ct.json 2>/dev/null
node "$GOS" context plan > cp.json 2>/dev/null
node "$GOS" context verify > cv.json 2>/dev/null
V3="$(vcheck '
import json
for f, keys in [("ct.json", ["spec"]), ("cp.json", ["spec", "plan"]), ("cv.json", ["evidence_dir"])]:
    ap = json.load(open(f)).get("artifact_paths", {})
    for k in keys:
        assert ap.get(k), "%s missing %s" % (f, k)
return "OK"
')"
if [ "$V3" = "OK" ]; then
  echo "  ✓ T42.3 think/plan/verify stage-appropriate artifact_paths"; PASS=$((PASS+1))
else
  echo "  ✗ T42.3 $V3"; FAIL=$((FAIL+1))
fi

# .4 conflict detection: tampering with .task-head ownership -> die mentions the task-id conflict
ED="$(vcheck 'import json; return json.load(open("ctx1.json"))["artifact_paths"]["evidence_dir"]' x)"
TASK_DIR="$(dirname "$ED")"
printf '%s\n' '{"task_head":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"}' > "$TASK_DIR/.task-head"
set +e
CTX3="$(node "$GOS" context build 2>&1)"
RC3=$?
set -e
if [ "$RC3" -ne 0 ] && printf '%s' "$CTX3" | grep -q "task id conflict"; then
  echo "  ✓ T42.4 ownership conflict detected (die, never silent reuse)"; PASS=$((PASS+1))
else
  echo "  ✗ T42.4 rc=$RC3 out=${CTX3:0:100}"; FAIL=$((FAIL+1))
fi
printf '%s\n' '{"task_head": null}' > "$TASK_DIR/.task-head"

# .5 ts-fallback: invalid task_head and no phase code -> ts-<timestamp> id + warning
python3 -c "
import json
d = json.load(open('.gos/state.json'))
d['phase_name'] = None
d['task_head'] = None
json.dump(d, open('.gos/state.json', 'w'), ensure_ascii=False, indent=2)
"
rm -rf .gos/task
set +e
CTX4="$(node "$GOS" context build 2>&1)"
RC4=$?
set -e
if [ "$RC4" -eq 0 ] && printf '%s' "$CTX4" | grep -q "ts-"; then
  echo "  ✓ T42.5 ts-fallback id when no code/no task_head"; PASS=$((PASS+1))
else
  echo "  ✗ T42.5 rc=$RC4 out=${CTX4:0:120}"; FAIL=$((FAIL+1))
fi

# .6 'n' collapse removed (grep the source: the 'n' fallback no longer exists in slug computation)
if ! grep -q "|| 'n';" "$GOS_ROOT/bin/gos.cjs"; then
  echo "  ✓ T42.6 no-code phase no longer collapses to 'n'"; PASS=$((PASS+1))
else
  echo "  ✗ T42.6 '|| n' fallback still present"; FAIL=$((FAIL+1))
fi

echo "--- T42 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
