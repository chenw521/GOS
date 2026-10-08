#!/usr/bin/env bash
# gos-map:fn bin/lib/map/contract.cjs#fn:cmdContract
# gos-map:cmd _contract
# T40: GOS_PATHS registry integrity — _contract additionally emits paths_registry
T40_DIR=""

t40_setup() {
  T40_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t40"
  mkdir -p "$T40_DIR" && cd "$T40_DIR" || exit 1
}
t40_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T40_DIR"; }

t40_setup
trap 't40_teardown' EXIT

PASS=0
FAIL=0

echo "--- T40: GOS_PATHS registry via _contract ---"

OUT="$(node "$GOS" _contract 2>&1)"

# T40.1 output is still valid JSON (the added key does not break the existing contract)
if printf '%s' "$OUT" | python3 -m json.tool >/dev/null 2>&1; then
  echo "  ✓ T40.1 _contract output is valid JSON"; PASS=$((PASS+1))
else
  echo "  ✗ T40.1 _contract output is NOT valid JSON"; FAIL=$((FAIL+1))
fi

# T40.2 paths_registry integrity: key entries + metadata quadruple + dynamic placeholders + scale
printf '%s' "$OUT" > "$T40_DIR/contract.json"
set +e
VERIFY="$(python3 - "$T40_DIR/contract.json" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as fh:
        d = json.load(fh)
except Exception as e:
    print('JSON-FAIL: %s' % e); sys.exit(1)
pr = d.get('paths_registry')
if not isinstance(pr, dict) or not pr:
    print('MISSING: paths_registry absent/empty'); sys.exit(1)
required = ['state','config','gates_json','concerns','lessons','map_ignore','readme',
            'gates_dir','project','codebase','archive','renderers',
            'deps','run_manifest','edges_lock','edges','backups_dir',
            'concerns_anchors','lessons_anchors',
            'truth_receipts','exemptions','edge_audit',
            'spec','plan','task_evidence','ship_staging']
for k in required:
    if k not in pr:
        print('KEY-MISSING: %s' % k); sys.exit(1)
for k, v in pr.items():
    for f in ('rel', 'producer', 'tracked', 'granularity'):
        if f not in v:
            print('FIELD-MISSING: %s.%s' % (k, f)); sys.exit(1)
    if '\\' in v['rel']:
        print('BACKSLASH: %s' % k); sys.exit(1)
    if v['granularity'] not in ('file', 'dir'):
        print('GRANULARITY: %s=%s' % (k, v.get('granularity'))); sys.exit(1)
if '<task_id>' not in pr['spec']['rel'] or '<task_id>' not in pr['plan']['rel']:
    print('PLACEHOLDER: spec/plan rel must carry <task_id>'); sys.exit(1)
if '<task_id>' not in pr['task_evidence']['rel']:
    print('PLACEHOLDER: task_evidence rel must carry <task_id>'); sys.exit(1)
if len(pr) < 26:
    print('SIZE: registry has %d entries (< 26)' % len(pr)); sys.exit(1)
print('OK')
PYEOF
)"
set -e
if [ "$VERIFY" = "OK" ]; then
  echo "  ✓ T40.2 paths_registry complete (26+ keys, meta quad, placeholders)"; PASS=$((PASS+1))
else
  echo "  ✗ T40.2 $VERIFY"; FAIL=$((FAIL+1))
fi

# T40.3 freeze non-regression: existing contract keys still present (additive only)
for key in allPass noActiveTask decisionAdded; do
  if printf '%s' "$OUT" | grep -q "\"$key\""; then
    echo "  ✓ T40.3 existing contract key present: $key"; PASS=$((PASS+1))
  else
    echo "  ✗ T40.3 existing contract key LOST: $key"; FAIL=$((FAIL+1))
  fi
done

echo "--- T40 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
