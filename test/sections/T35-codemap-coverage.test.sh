#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/gate.cjs#fn:cmdGate bin/lib/map/index.cjs#fn:cmdMap
# gos-map:cmd gate,map
# : gate codemap enhancements — fn coverage report + edge-count baseline drop detection
T35_DIR=""

t35_setup() {
  T35_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t34"
  mkdir -p "$T35_DIR" && cd "$T35_DIR" || exit 1
}
t35_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T35_DIR"; }

t35_setup
echo "--- T34: codemap coverage report + edge baseline drop detection ---"

git init -q . && git commit -q --allow-empty -m root
mkdir -p bin test/sections
# three real js fns: cmdAlpha (section-tested) / cmdBeta / helperOne (unmapped) — acorn-parseable, all called (enter the callgraph node set)
cat > bin/gos.cjs << 'EOF'
function cmdAlpha(){ return 1; }
function cmdBeta(){ return cmdAlpha(); }
function helperOne(){ return 2; }
switch (sub) { case 'a': cmdAlpha(); break; case 'b': cmdBeta(); break; case 'c': helperOne(); break; }
EOF
# section annotations: only cmdAlpha is covered -> unmapped = cmdBeta, helperOne
cat > test/sections/TX-alpha.test.sh << 'EOF'
# gos-map:fn cmdAlpha
echo ok
EOF
git add -A && git commit -q -m chain
node "$GOS" init 1 "t34 fixture" >/dev/null 2>&1

set +e
G_SCAN=$(node "$GOS" map scan 2>&1); SRC=$?; set -e
if [ "$SRC" -ne 0 ]; then echo "  ✗ T35.0 map scan failed: $G_SCAN"; FAIL=$((FAIL+1)); fi
test -f .gos/cache/deps.json && echo "  ✓ T35.0 scan produced deps.json" && PASS=$((PASS+1)) || { echo "  ✗ T35.0 no deps.json"; FAIL=$((FAIL+1)); }
test -f .gos/codebase/edge-baseline.json && echo "  ✓ T35.0b scan wrote edge-baseline.json (D-03)" && PASS=$((PASS+1)) || { echo "  ✗ T35.0b no edge-baseline.json"; FAIL=$((FAIL+1)); }

# --- .4 fresh baseline (scan just wrote it) -> no edge count drop line (false-positive regression guard)
set +e; G=$(node "$GOS" gate codemap 2>&1); GRC=$?; set -e
if [ "$GRC" -eq 0 ] && ! printf '%s\n' "$G" | grep -q "edge count drop"; then
  echo "  ✓ T35.4 fresh baseline: no false drop warning"; PASS=$((PASS+1))
else echo "  ✗ T35.4 false drop or gate failed (rc=$GRC)"; FAIL=$((FAIL+1)); fi

# --- .1 coverage: summary line + unmapped-fns.txt list (number consistent with deps)
set +e; G=$(node "$GOS" gate codemap 2>&1); GRC=$?; set -e
if printf '%s\n' "$G" | grep -qF "unmapped fn(s) without test annotation" && printf '%s\n' "$G" | grep -q "unmapped-fns.txt"; then
  echo "  ✓ T35.1a coverage summary + full-list pointer present"; PASS=$((PASS+1))
else echo "  ✗ T35.1a coverage summary missing"; printf '%s\n' "$G" | head -5; FAIL=$((FAIL+1)); fi
# unmapped count = unique fn count - testof_fn covered count (computed from deps for cross-check);
# file lines = 1 provenance header (generated-at @ HEAD, ) + one line per unmapped fn
UT=$(node -e "
const d=require('./.gos/cache/deps.json');const s=d.semantic||{};
const all=new Set();(s.callgraph||[]).forEach(e=>{all.add(e.file+'#fn:'+e.from);all.add(e.file+'#fn:'+e.to)});
const t=new Set((s.testof_fn||[]).map(x=>x.file+'#fn:'+x.fn));
console.log([...all].filter(f=>!t.has(f)).length)")
test -f .gos/codebase/unmapped-fns.txt && [ "$(wc -l < .gos/codebase/unmapped-fns.txt | tr -d ' ')" = "$((UT + 1))" ] \
  && echo "  ✓ T35.1b unmapped-fns.txt lines (header + $UT) match deps math" && PASS=$((PASS+1)) \
  || { echo "  ✗ T35.1b list lines != computed unmapped + header ($UT + 1)"; FAIL=$((FAIL+1)); }

# --- .2 drop: forged oversized peak -> edge count drop advisory
node -e "
const fs=require('fs');const p='.gos/codebase/edge-baseline.json';
const b=JSON.parse(fs.readFileSync(p,'utf8'));
b.peak=Object.assign({},b.peak||{},{total:99999,callgraph:99999,fn_count:(b.peak&&b.peak.fn_count)||99999});
fs.writeFileSync(p,JSON.stringify(b,null,1));"
set +e; G=$(node "$GOS" gate codemap 2>&1); GRC=$?; set -e
if printf '%s\n' "$G" | grep -q "edge count drop"; then
  echo "  ✓ T35.2 fabricated high baseline → drop warning"; PASS=$((PASS+1))
else echo "  ✗ T35.2 drop warning missing"; FAIL=$((FAIL+1)); fi

# --- .3 missing baseline -> advisory, no FAIL
rm -f .gos/codebase/edge-baseline.json
set +e; G=$(node "$GOS" gate codemap 2>&1); GRC=$?; set -e
if [ "$GRC" -eq 0 ] && printf '%s\n' "$G" | grep -qi "no edge baseline"; then
  echo "  ✓ T35.3 missing baseline → advisory, gate exit 0"; PASS=$((PASS+1))
else echo "  ✗ T35.3 missing baseline mishandled (rc=$GRC)"; FAIL=$((FAIL+1)); fi

t35_teardown
