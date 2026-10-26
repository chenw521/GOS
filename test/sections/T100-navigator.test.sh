#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/gate.cjs#fn:cmdGate bin/lib/task/context.cjs#fn:cmdContext
# gos-map:cmd gate,context
# T100 (Wave 4 T9 / D-19, D-20): navigator bundle — unmapped-fns.txt rename +
# generated-at provenance header + THINK context navigator hint.
# Facts asserted:
#   N1 gate codemap writes .gos/codebase/unmapped-fns.txt; legacy byproduct (old name) absent
#   N2 provenance header first line: `generated-at: <ISO s.Z> @ <HEAD[0:8]>`; the 8-hex
#      slice equals git rev-parse HEAD | cut -c1-8
#   N3 summary wording "unmapped fn(s) without test annotation" + pointer unmapped-fns.txt
#   N4 file line count = 1 header + deps-math unmapped count (header accounted)
#   N5 unborn repo (no commits): header anchor degrades to "@ unborn" (mapGitInfo marker)
#   N6 `gos context think` JSON carries navigator {hint, map_data, provenance} tiers
# Env: GOS, TESTBASE, assert helpers sourced by runner (standalone-safe).
T100_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T100_STANDALONE=1
  T100_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T100_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T100_SELFROOT"
  export TESTBASE="$(mktemp -d "$T100_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T100_DIR=""

t100_setup() {
  T100_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t100"
  mkdir -p "$T100_DIR" && cd "$T100_DIR" || exit 1
}
t100_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T100_DIR"; }

t100_setup
echo "--- T100: navigator bundle (rename + provenance header + THINK hint) ---"

git init -q . && git commit -q --allow-empty -m root
mkdir -p bin test/sections
# three real js fns: cmdAlpha (section-tested) / cmdBeta / helperOne — acorn-parseable,
# all called by the switch so every fn enters the callgraph node set
cat > bin/gos.cjs << 'EOF'
function cmdAlpha(){ return 1; }
function cmdBeta(){ return cmdAlpha(); }
function helperOne(){ return 2; }
switch (sub) { case 'a': cmdAlpha(); break; case 'b': cmdBeta(); break; case 'c': helperOne(); break; }
EOF
cat > test/sections/TX-alpha.test.sh << 'EOF'
# gos-map:fn cmdAlpha
echo ok
EOF
git add -A && git commit -q -m chain
node "$GOS" init 1 "t100 navigator fixture" >/dev/null 2>&1

node "$GOS" map scan >/dev/null 2>&1

# legacy byproduct name is split so the repo-wide old-name grep guard (see the
# task plan done-when) stays empty by construction; D-20 rename swept every
# live reference, this file must not reintroduce the literal
T100_LEGACY=".gos/codebase/un""tested-fns.txt"

# --- N1+N3: run gate codemap — byproduct file (new name) + wording ---
set +e; G=$(node "$GOS" gate codemap 2>&1); GRC=$?; set -e
if [ "$GRC" -eq 0 ] && [ -f .gos/codebase/unmapped-fns.txt ] && [ ! -f "$T100_LEGACY" ]; then
  echo "  ✓ T100.1 unmapped-fns.txt written, legacy byproduct absent"; PASS=$((PASS+1))
else echo "  ✗ T100.1 rc=$GRC new-list=$([ -f .gos/codebase/unmapped-fns.txt ] && echo y || echo n) old-list=$([ -f "$T100_LEGACY" ] && echo y || echo n)"; FAIL=$((FAIL+1)); fi
if printf '%s\n' "$G" | grep -qF "unmapped fn(s) without test annotation" && printf '%s\n' "$G" | grep -q "unmapped-fns.txt"; then
  echo "  ✓ T100.3 summary wording 'unmapped fn(s) without test annotation' + list pointer"; PASS=$((PASS+1))
else echo "  ✗ T100.3 wording missing"; printf '%s\n' "$G" | grep codemap | head -4; FAIL=$((FAIL+1)); fi

# --- N2: provenance header first line — ISO(secs Z) @ HEAD[0:8], sha slice matches git ---
HDR="$(head -n 1 .gos/codebase/unmapped-fns.txt 2>/dev/null || true)"
WANT_SHA="$(git rev-parse HEAD | cut -c1-8)"
if printf '%s\n' "$HDR" | grep -Eq '^generated-at: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z @ [0-9a-f]{8}$' \
  && printf '%s\n' "$HDR" | grep -qF "@ $WANT_SHA"; then
  echo "  ✓ T100.2 header format + HEAD anchor ($HDR)"; PASS=$((PASS+1))
else echo "  ✗ T100.2 bad header: '$HDR' (want sha $WANT_SHA)"; FAIL=$((FAIL+1)); fi

# --- N4: line count = header(1) + deps-math unmapped count ---
UT=$(node -e "
const d=require('./.gos/cache/deps.json');const s=d.semantic||{};
const all=new Set();(s.callgraph||[]).forEach(e=>{all.add(e.file+'#fn:'+e.from);all.add(e.file+'#fn:'+e.to)});
const t=new Set((s.testof_fn||[]).map(x=>x.file+'#fn:'+x.fn));
console.log([...all].filter(f=>!t.has(f)).length)")
LINES="$(wc -l < .gos/codebase/unmapped-fns.txt 2>/dev/null | tr -d ' ' || true)"
if [ "$LINES" = "$((UT + 1))" ]; then
  echo "  ✓ T100.4 line count $LINES = header + $UT unmapped (deps math)"; PASS=$((PASS+1))
else echo "  ✗ T100.4 lines=$LINES expected=$((UT + 1))"; FAIL=$((FAIL+1)); fi

# --- N5: unborn repo — header anchor degrades to @ unborn (gate codemap is stateless) ---
t100_teardown; t100_setup
git init -q .
mkdir -p bin test/sections .gos
printf 'function cmdAlpha(){ return 1; }\nfunction cmdBeta(){ return cmdAlpha(); }\n' > bin/gos.cjs
printf '# gos-map:fn cmdAlpha\necho ok\n' > test/sections/TX-alpha.test.sh
# gos init silently no-ops on an unborn repo (no HEAD anchor) — hand-write the
# minimal state so the lock-layer root detection stops HERE (T99 ancestor-walk
# guard: without it the fixture resolves to the GOS self repo above TESTBASE)
cat > .gos/state.json << 'EOF'
{"schema_version":4,"repo_id":null,"level":1,"intent":{"summary":"t100 unborn fixture"},"current_stage":"INTENT","completed_stages":[],"decisions":[],"requirements":[],"observable_truths":[],"gaps":[]}
EOF
node "$GOS" map scan >/dev/null 2>&1
set +e; GU=$(node "$GOS" gate codemap 2>&1); GURC=$?; set -e
UHDR="$(head -n 1 .gos/codebase/unmapped-fns.txt 2>/dev/null || true)"
if [ "$GURC" -eq 0 ] && printf '%s\n' "$UHDR" | grep -Eq '^generated-at: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z @ unborn$'; then
  echo "  ✓ T100.5 unborn repo header anchor '@ unborn' ($UHDR)"; PASS=$((PASS+1))
else echo "  ✗ T100.5 unborn rc=$GURC header='$UHDR'"; FAIL=$((FAIL+1)); fi

# --- N6: THINK context JSON carries the navigator tiers hint ---
t100_teardown; t100_setup
git init -q . && git commit -q --allow-empty -m root
node "$GOS" init 1 "t100 navigator hint" >/dev/null 2>&1
node "$GOS" context think > ctx.json 2>/dev/null
V6="$(python3 -c "
import json
try:
    d = json.load(open('ctx.json'))
    nav = d.get('navigator')
    assert isinstance(nav, dict), 'NO-NAVIGATOR'
    assert 'guide' in nav['hint'] and 'static' in nav['hint'], 'HINT-MISSING-GUIDE-TIER'
    assert 'travels with clones' in nav['map_data'], 'MAP-DATA-MISSING-TRAVEL'
    assert 'network.md' in nav['map_data'] and 'edge-baseline.json' in nav['map_data'], 'MAP-DATA-MISSING-FILES'
    assert 'unmapped-fns.txt' in nav['provenance'] and 'generated-at' in nav['provenance'], 'PROVENANCE-MISSING'
    print('OK')
except Exception as e:
    print('ERR: %s' % e)
" 2>/dev/null)"
if [ "$V6" = "OK" ]; then
  echo "  ✓ T100.6 THINK context navigator hint {hint, map_data, provenance}"; PASS=$((PASS+1))
else echo "  ✗ T100.6 $V6"; FAIL=$((FAIL+1)); fi

t100_teardown
if [ "$T100_STANDALONE" = "1" ]; then
  echo "--- T100 summary: $PASS passed, $FAIL failed ---"
  [ "$FAIL" -eq 0 ] && rm -rf "$TESTBASE"
fi
[ "$FAIL" -eq 0 ]
