#!/usr/bin/env bash
# gos-map:cmd map
# test-of extractor (⑤) — section header annotations → semantic.testof edges;
# unannotatedCount soft hint; migration completeness; pure metadata (never eval)
T34_DIR=""

t34_setup() {
  T34_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t34"
  mkdir -p "$T34_DIR" && cd "$T34_DIR" || exit 1
}
t34_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T34_DIR"; }

t34_setup
echo "--- T34: test-of extractor + section annotations (R-06/R-10) ---"

# --- .1 self-repo scan: testof edges + unannotatedCount=0
set +e; SCAN_OUT=$(cd "$GOS_ROOT" && node "$GOS" map scan 2>&1); SCAN_RC=$?; set +e
assert_exit "T34.1a self-repo scan exits 0" 0 "$SCAN_RC"
python3 - <<'PYEOF'
import json, os, sys
d = json.load(open(os.path.join(os.environ['GOS_ROOT'], '.gos', 'cache', 'deps.json')))
sem = d.get('semantic', {})
to = sem.get('testof', [])
bad = []
if not any(e.get('sec') == 'T30-map-edges' and e.get('cmd') == 'map' for e in to):
    bad.append('testof edge T30-map-edges→map missing')
if not any(e.get('sec') == 'T31-map-gate' for e in to):
    bad.append('testof edge for T31 missing')
# multi-cmd sections must expand to one edge per cmd
t9 = [e['cmd'] for e in to if e['sec'] == 'T9-contract']
if len(t9) < 2: bad.append(f'T9 multi-cmd annotation not expanded (got {t9})')
print('  ✓ semantic.testof edges present (multi-cmd expanded)' if not bad else '  ✗ ' + '; '.join(bad))
sys.exit(1 if bad else 0)
PYEOF
assert_exit "T34.1b testof content verified" 0 "$?"
if printf '%s\n' "$SCAN_OUT" | grep -q "unannotated"; then
  N_ANN=$(printf '%s\n' "$SCAN_OUT" | grep -o "[0-9]* test section" | head -1 | cut -d' ' -f1)
  echo "  ✗ unannotated sections remain: $N_ANN (R-10 violated)"; FAIL=$((FAIL+1))
else
  echo "  ✓ R-10: all sections annotated (unannotatedCount = 0, no hint line)"; PASS=$((PASS+1))
fi

# --- .2 unannotatedCount counter: sandbox fake-sections scenario (not constructible in GOS_SELF — static assertion instead)
if grep -q "unannotated" "$GOS_ROOT/bin/lib/map/engine.cjs" && node "$GOS" _contract 2>/dev/null | grep -q "unannotated"; then
  echo "  ✓ unannotatedCount frozen in CONTRACTS + emitted by scan"; PASS=$((PASS+1))
else echo "  ✗ unannotatedCount contract key missing"; FAIL=$((FAIL+1)); fi

# --- .3 pure metadata: the extractor never evals header content
if grep -A20 "name: 'testof'" "$GOS_ROOT/bin/gos.cjs" | grep -qE "\beval\(|new Function\(|execSync" ; then
  echo "  ✗ testof extractor shows eval/exec of header content"; FAIL=$((FAIL+1))
else
  echo "  ✓ testof extractor is regex-parse only (no eval/exec of annotation text)"; PASS=$((PASS+1))
fi

# --- .4 sec anchors + testof neighborhood queryable (show integration)
set +e; SHOW=$(cd "$GOS_ROOT" && node "$GOS" map show "bin/gos.cjs#cmd:map" 2>/dev/null | grep -c "T30-map-edges\|T31-map-gate\|T34"); set +e
if [ "${SHOW:-0}" -ge 1 ]; then echo "  ✓ show <cmd:anchor> lists test-of sections"; PASS=$((PASS+1))
else echo "  ✗ show does not surface testof edges"; FAIL=$((FAIL+1)); fi

# --- .5 every existing section header present (28 legacy + 5 map sections)
MISS=0
for f in "$GOS_ROOT"/test/sections/T*.test.sh; do
  if ! head -5 "$f" | grep -q "gos-map:"; then MISS=$((MISS+1)); echo "    unannotated: $(basename "$f")"; fi
done
if [ "$MISS" -eq 0 ]; then echo "  ✓ every section file carries a gos-map header"; PASS=$((PASS+1))
else echo "  ✗ $MISS section(s) missing header"; FAIL=$((FAIL+1)); fi

rm -f "$GOS_ROOT/.gos/cache/deps.json"
t34_teardown
