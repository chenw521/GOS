#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/gate.cjs#fn:cmdGate bin/lib/map/index.cjs#fn:cmdMap
# gos-map:cmd gate,map
# gos-map:contract bidirectional
# annotation and edge-family extensions — fully-qualified validation + both sugar + sec_contracts
T38_DIR=""

t38_setup() {
  T38_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t38"
  mkdir -p "$T38_DIR" && cd "$T38_DIR" || exit 1
}
t38_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T38_DIR"; }

t38_setup
echo "--- T38: annotation extensions (qualified fn / both sugar / sec_contracts) ---"

git init -q . && git commit -q --allow-empty -m root
mkdir -p bin test/sections
cat > bin/gos.cjs << 'EOF'
function cmdAlpha(){ return 1; }
function cmdBeta(){ return cmdAlpha(); }
function cmdGamma(){ return 3; }
switch (sub) { case 'a': cmdAlpha(); break; case 'b': cmdBeta(); break; case 'g': cmdGamma(); break; }
EOF
# .1 three branches: bare hit / qualified owner match / qualified non-owner -> dead
cat > test/sections/TZ-bare.test.sh << 'EOF'
# gos-map:fn cmdAlpha
echo ok
EOF
cat > test/sections/TZ-qual.test.sh << 'EOF'
# gos-map:fn cmdBeta
echo ok
EOF
cat > test/sections/TZ-bad.test.sh << 'EOF'
# gos-map:fn nofile.js#fn:cmdAlpha
echo ok
EOF
# .2 both: derive the cmdGamma fn edge from one line (cmd edge lives in the GOS_SELF domain, verified in the real repo)
cat > test/sections/TZ-both.test.sh << 'EOF'
# gos-map:both gamma
echo ok
EOF
# .3 explicit wins: same section has explicit cmdBeta + both naming beta -> derivation skips cmdBeta, exactly 1 fn edge in the section
cat > test/sections/TZ-explicit.test.sh << 'EOF'
# gos-map:fn cmdBeta
# gos-map:both beta
echo ok
EOF
# .4 contracts: legal key lands an edge + illegal key dead
cat > test/sections/TZ-con.test.sh << 'EOF'
# gos-map:contract bidirectional,noSuchKeyXxx
echo ok
EOF
git add -A && git commit -q -m chain
node "$GOS" init 1 "t38 fixture" >/dev/null 2>&1

set +e
G_SCAN=$(node "$GOS" map scan 2>&1); SRC=$?; set -e
if [ "$SRC" -ne 0 ]; then echo "  ✗ T38.0 scan failed: $G_SCAN"; FAIL=$((FAIL+1)); fi
DEPSCHK() { node -e "
const d=require('./.gos/cache/deps.json');const s=d.semantic||{};$1"; }

# --- .1a bare + qualified hits land as edges
DEPSCHK="
const t=s.testof_fn||[];
const has=(sec,fn)=>t.some(e=>e.sec==='${sec}'&&e.fn===fn&&e.file==='bin/gos.cjs');
process.exit(has('TZ-bare','cmdAlpha')&&has('TZ-qual','cmdBeta')?0:1)"
node -e "
const d=require('./.gos/cache/deps.json');const t=(d.semantic||{}).testof_fn||[];
const has=(sec,fn)=>t.some(e=>e.sec===process.argv[1]&&e.fn===process.argv[2]&&e.file==='bin/gos.cjs');
process.exit(has('TZ-bare','cmdAlpha')&&has('TZ-qual','cmdBeta')?0:1)" TZ-bare cmdAlpha
[ $? -eq 0 ] && echo "  ✓ T38.1a bare + qualified hits land as edges" && PASS=$((PASS+1)) || { echo "  ✗ T38.1a qualified/bare edges missing"; FAIL=$((FAIL+1)); }

# --- .1b qualified non-owner -> dead_fn_annotations, no edge
node -e "
const d=require('./.gos/cache/deps.json');const s=d.semantic||{};
const bad=(s.testof_fn||[]).some(e=>e.sec==='TZ-bad');
const dead=(s.dead_fn_annotations||[]).some(x=>x.includes('TZ-bad'));
process.exit((!bad&&dead)?0:1)"
[ $? -eq 0 ] && echo "  ✓ T38.1b non-owner qualified → dead, no edge" && PASS=$((PASS+1)) || { echo "  ✗ T38.1b dead semantics wrong"; FAIL=$((FAIL+1)); }

# --- .2 both derives the fn edge
node -e "
const d=require('./.gos/cache/deps.json');const t=(d.semantic||{}).testof_fn||[];
process.exit(t.some(e=>e.sec==='TZ-both'&&e.fn==='cmdGamma')?0:1)"
[ $? -eq 0 ] && echo "  ✓ T38.2 both sugar derives fn edge (cmdGamma)" && PASS=$((PASS+1)) || { echo "  ✗ T38.2 both derivation missing"; FAIL=$((FAIL+1)); }

# --- .3 explicit priority: TZ-explicit has exactly 1 fn edge (cmdBeta, explicit), both derivation does not duplicate
node -e "
const d=require('./.gos/cache/deps.json');const t=(d.semantic||{}).testof_fn||[];
const mine=t.filter(e=>e.sec==='TZ-explicit');
process.exit(mine.length===1&&mine[0].fn==='cmdBeta'?0:1)"
[ $? -eq 0 ] && echo "  ✓ T38.3 explicit annotation wins, no duplicate derivation" && PASS=$((PASS+1)) || { echo "  ✗ T38.3 explicit-priority broken"; FAIL=$((FAIL+1)); }

# --- .4 sec_contracts: legal key lands an edge, illegal key does not
node -e "
const d=require('./.gos/cache/deps.json');const sc=(d.semantic||{}).sec_contracts||[];
const ok=sc.some(e=>e.sec==='TZ-con'&&e.contract==='bidirectional');
const bad=sc.some(e=>e.contract==='noSuchKeyXxx');
process.exit(ok&&!bad?0:1)"
[ $? -eq 0 ] && echo "  ✓ T38.4 sec_contracts edges land, invalid key rejected" && PASS=$((PASS+1)) || { echo "  ✗ T38.4 sec_contracts wrong"; FAIL=$((FAIL+1)); }

t38_teardown
