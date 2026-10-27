#!/usr/bin/env bash
# gos-map:cmd map,gate
# fn-level drill-down — acorn lazy require + schema v3 + callgraph/testof_fn extractors
# Env: GOS (CLI path), TESTBASE (repo root for sandbox), + assert helpers sourced by runner
T36_DIR=""
T36_REPO=""   # live repo root (subject of the lazy/mv experiments)
PASS=0; FAIL=0
# inline helper fallback (skipped when run-sections.sh predefines them)
command -v assert_exit >/dev/null || assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected exit $expected, got '${actual:-<none>}')"; FAIL=$((FAIL+1)); fi
}
command -v assert_eq >/dev/null || assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected '$expected', got '$actual')"; FAIL=$((FAIL+1)); fi
}
command -v assert_contains >/dev/null || assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected: '$expected')"; echo "    actual: ${actual:0:160}"; FAIL=$((FAIL+1)); fi
}

[ -n "$GOS" ] || GOS="$(git rev-parse --show-toplevel 2>/dev/null)/bin/gos.cjs"
[ -n "$TESTBASE" ] || TESTBASE="$(mktemp -d)"

t36_setup() {
  T36_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t36"
  T36_REPO="$(cd "$(dirname "$(dirname "$(readlink -f "$GOS")")")" && pwd)"
  mkdir -p "$T36_DIR" && cd "$T36_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
}

t36_teardown() {
  # best-effort acorn restore (protection when the mv experiment is interrupted)
  if [ -n "$T36_REPO" ] && [ -d "$T36_REPO/node_modules/acorn.bak-t36" ]; then
    mv "$T36_REPO/node_modules/acorn.bak-t36" "$T36_REPO/node_modules/acorn" 2>/dev/null
  fi
  cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T36_DIR"
}

t36_setup
trap t36_teardown EXIT # restore live-repo acorn even on Ctrl-C / assert-exit
echo "--- T36: callgraph fn-level drilling ---"

# --- .1 : lazy require — CLI boots without acorn (help = side-effect-free boot probe)
node "$GOS" help >/dev/null 2>&1
assert_exit "T36.1a CLI boots with acorn present" 0 "$?"
mv "$T36_REPO/node_modules/acorn" "$T36_REPO/node_modules/acorn.bak-t36"
node "$GOS" help >/dev/null 2>&1
assert_exit "T36.1b CLI boots WITHOUT acorn (lazy require)" 0 "$?"
mv "$T36_REPO/node_modules/acorn.bak-t36" "$T36_REPO/node_modules/acorn"
node "$GOS" help >/dev/null 2>&1
assert_exit "T36.1c CLI boots after acorn restore" 0 "$?"

# --- .2 : schema v3 + loadDeps direction-aware die
# re-sign helper: mirror depsSelfHash (canonical JSON + sha256, trailing \n)
t36_resign() {   # file → rewrites self_sha256 in place
  python3 - "$1" <<'PYEOF'
import json, hashlib, sys
p = sys.argv[1]
d = json.load(open(p))
claimed = d.pop('self_sha256', None)
d['self_sha256'] = hashlib.sha256((json.dumps(d, indent=2, ensure_ascii=False) + '\n').encode('utf-8')).hexdigest()
json.dump(d, open(p, 'w'), indent=2, ensure_ascii=False)
PYEOF
}
node "$GOS" map scan >/dev/null 2>&1
SV=$(node -e "console.log(require('./.gos/cache/deps.json').schema_version)")
assert_eq "T36.2a scan writes schema v3" "3" "$SV"
node -e "const fs=require('fs'); const d=require('./.gos/cache/deps.json'); d.schema_version=2; fs.writeFileSync('./.gos/cache/deps.json', JSON.stringify(d,null,2))"
t36_resign ./.gos/cache/deps.json
OUT=$(node "$GOS" map closure bin/gos.cjs 2>&1); RC=$?
assert_exit "T36.2b v2 cache dies" 1 "$RC"
assert_contains "T36.2b' v2 die says rescan" "gos map scan" "$OUT"
node -e "const fs=require('fs'); const d=require('./.gos/cache/deps.json'); d.schema_version=4; fs.writeFileSync('./.gos/cache/deps.json', JSON.stringify(d,null,2))"
t36_resign ./.gos/cache/deps.json
OUT=$(node "$GOS" map closure bin/gos.cjs 2>&1); RC=$?
assert_exit "T36.2c v4 cache dies" 1 "$RC"
assert_contains "T36.2c' v4 die says upgrade" "upgrade gos" "$OUT"
node "$GOS" map scan >/dev/null 2>&1   # restore healthy v3 cache

# --- .3 : callgraph extraction — real edges + self-consistency
# fn-level assertions target the LIVE repo (gos self-hosting monolith); deps.json is gitignored
(cd "$T36_REPO" && node "$GOS" map scan >/dev/null 2>&1)
node -e "
const d = require(process.argv[1] + '/.gos/cache/deps.json');
const c = d.semantic.callgraph || [];
const pf = d.semantic.parse_failures || [];
const okCount = c.length > 150;   // floor re-anchored over repo evolution; cross-module calls appear as member calls, watched separately
const okEdge = c.some(e => e.from === 'writeDeps' && e.to === 'runExtractors');   // same-file (engine) pair — cross-file member calls are outside the extractor's view
const okPf = pf.length === 0;
console.log((okCount?'OK':'BAD') + ' count=' + c.length);
console.log((okEdge?'OK':'BAD') + ' writeDeps->runExtractors');
console.log((okPf?'OK':'BAD') + ' parse_failures empty');
" "$T36_REPO" > t363.txt 2>&1
assert_contains "T36.3a callgraph >150 edges (②-5 multi-file floor)" "OK count=" "$(cat t363.txt)"
assert_contains "T36.3b real edge writeDeps->runExtractors (same-file)" "OK writeDeps" "$(cat t363.txt)"
assert_contains "T36.3c parse_failures empty" "OK parse_failures" "$(cat t363.txt)"
# self-consistency ( /F-H4): acorn top-level FunctionDeclaration count === ^(async )?function regex count
node -e "
const fs = require('fs');
const path = require('path');
const repo = process.argv[1];
const acorn = require(path.join(repo, 'node_modules', 'acorn'));
const src = fs.readFileSync(repo + '/bin/gos.cjs', 'utf8');
const ast = acorn.parse(src, { ecmaVersion: 'latest', sourceType: 'script', allowHashBang: true });
const acornCount = ast.body.filter(n => n.type === 'FunctionDeclaration' && n.id).length;
const reCount = (src.match(/^(async )?function \\w+\\(/gm) || []).length;
console.log((acornCount === reCount ? 'OK' : 'BAD') + ' acorn=' + acornCount + ' regex=' + reCount);
const d = require(repo + '/.gos/cache/deps.json');
const fns = new Set();
for (const e of (d.semantic.callgraph || [])) { fns.add(e.from); fns.add(e.to); }
console.log((fns.size > 140 ? 'OK' : 'BAD') + ' distinct-fns=' + fns.size);   // floor 140 (measured 172 at re-anchor time)
" "$T36_REPO" > t363b.txt 2>&1
assert_contains "T36.3d self-consistency acorn==regex" "OK acorn=" "$(cat t363b.txt)"
assert_contains "T36.3e distinct fn nodes >140" "OK distinct-fns=" "$(cat t363b.txt)"

# --- .4 : testof_fn annotations — clone isolation + dead-annotation soft warning
T36_CLONE="$TESTBASE/clone-$RANDOM-t36"
git clone -q "$T36_REPO" "$T36_CLONE" 2>/dev/null
ln -s "$T36_REPO/node_modules" "$T36_CLONE/node_modules"
# pre-state: clone inherits the live repo's pilot annotations (≥3 sections since .8)
(cd "$T36_CLONE" && node "$GOS" map scan >/dev/null 2>&1)
TFN=$(node -e "console.log(((require(process.argv[1]+'/.gos/cache/deps.json').semantic.testof_fn)||[]).length)" "$T36_CLONE")
[ "$TFN" -ge 3 ] && { echo "  ✓ T36.4a clone inherits live testof_fn edges ($TFN)"; PASS=$((PASS+1)); } || { echo "  ✗ T36.4a clone testof_fn=$TFN (want ≥3)"; FAIL=$((FAIL+1)); }
# annotate cmdMap in the CLONE's copy of a test section
sed -i '2i # gos-map:fn cmdMap,semanticClosure' "$T36_CLONE/test/sections/T12-wiring.test.sh"
(cd "$T36_CLONE" && node "$GOS" map scan >/dev/null 2>&1)
TFN=$(node -e "
const t=(require(process.argv[1]+'/.gos/cache/deps.json').semantic.testof_fn)||[];
console.log(t.some(e=>e.sec==='T12-wiring'&&e.fn==='cmdMap'&&e.file==='bin/lib/map/index.cjs') ? 'hit' : 'miss')" "$T36_CLONE")
assert_eq "T36.4b clone annotation → sec↔fn edge" "hit" "$TFN"
# dead annotation → stderr soft warning (no die)
sed -i '3i # gos-map:fn notExistFn' "$T36_CLONE/test/sections/T12-wiring.test.sh"
OUT=$(cd "$T36_CLONE" && node "$GOS" map scan 2>&1); RC=$?
assert_exit "T36.4c dead annotation does not die" 0 "$RC"
assert_contains "T36.4d dead annotation soft warning" "dead gos-map:fn annotation" "$OUT"
# live repo cmd-family edges unchanged (byte-compare the testof array against a fresh live scan)
(cd "$T36_REPO" && node "$GOS" map scan >/dev/null 2>&1)
LIVE_T=$(node -e "const d=require(process.argv[1]+'/.gos/cache/deps.json'); console.log(JSON.stringify(d.semantic.testof))" "$T36_REPO")
(cd "$T36_CLONE" && node "$GOS" map scan >/dev/null 2>&1)
CLONE_T=$(node -e "const d=require(process.argv[1]+'/.gos/cache/deps.json'); console.log(JSON.stringify(d.semantic.testof))" "$T36_CLONE")
assert_eq "T36.4e cmd family untouched by fn annotations" "$LIVE_T" "$CLONE_T"
rm -rf "$T36_CLONE"

# --- .5 : fn closure — transitive must-run + parse warning + json envelope
# clone: annotate cmdMap → closure on its callee pathOf must surface that section (transitive merge)
T36_CLONE="$TESTBASE/clone5-$RANDOM-t36"
git clone -q "$T36_REPO" "$T36_CLONE" 2>/dev/null
ln -s "$T36_REPO/node_modules" "$T36_CLONE/node_modules"
sed -i '2i # gos-map:fn mapResolveSpec' "$T36_CLONE/test/sections/T12-wiring.test.sh"
(cd "$T36_CLONE" && node "$GOS" map scan >/dev/null 2>&1)
OUT=$(cd "$T36_CLONE" && node "$GOS" map closure bin/lib/map/engine.cjs#fn:mapResolveSpec 2>/dev/null)
assert_contains "T36.5a callers listed (mapResolveSpec)" "fn:mapResolveSpec" "$OUT"
assert_contains "T36.5b transitive must-run (tests caller)" "T12-wiring" "$OUT"
assert_contains "T36.5c empty-parse no warning" "closure for" "$OUT"
if echo "$OUT" | grep -q "closure may be incomplete"; then echo "  X T36.5c2 warning leaked on clean data"; FAIL=$((FAIL+1)); else echo "  [ok] T36.5c2 no warning on clean data"; PASS=$((PASS+1)); fi
# inject parse_failures (re-signed) → warning line present
node -e "
const fs=require('fs');
const d=require(process.argv[1]+'/.gos/cache/deps.json');
d.semantic.parse_failures=[{file:'x.js',msg:'boom'}];
delete d.self_sha256;
const crypto=require('crypto');
d.self_sha256=crypto.createHash('sha256').update(JSON.stringify(d,null,2)+'\n','utf8').digest('hex');
fs.writeFileSync(process.argv[1]+'/.gos/cache/deps.json', JSON.stringify(d,null,2));
" "$T36_CLONE"
OUT=$(cd "$T36_CLONE" && node "$GOS" map closure bin/gos.cjs#fn:pathOf --no-refresh 2>/dev/null)   # --no-refresh: read the injected cache verbatim (worktree-dirty clone would auto-rescan)
assert_contains "T36.5d parse_failures → closure warning line" "closure may be incomplete" "$OUT"
# json envelope: byte-0 '{' + fields
OUT=$(cd "$T36_CLONE" && node "$GOS" map closure bin/lib/map/engine.cjs#fn:mapResolveSpec --json 2>/dev/null)
FIRST=$(printf %.1s "$OUT")
assert_eq "T36.5e json byte0 is brace" "{" "$FIRST"
assert_contains "T36.5f json fields" "fnMustCheck" "$OUT"
assert_contains "T36.5g json parseFailures field" "parseFailures" "$OUT"
# fn-not-in-graph advisory
OUT=$(cd "$T36_CLONE" && node "$GOS" map closure bin/gos.cjs#fn:totallyFakeFn 2>/dev/null)
assert_contains "T36.5h fn not in graph advisory" "isolated or out-of-graph" "$OUT"
rm -rf "$T36_CLONE"

# --- .6 : gate codemap — health FAILs are data-broken only; absent cache is advisory
(cd "$T36_REPO" && node "$GOS" gate codemap >/dev/null 2>&1)
assert_exit "T36.6a healthy repo → gate codemap exit 0" 0 "$?"
OUT=$(cd "$T36_REPO" && node "$GOS" gate codemap 2>&1)
assert_contains "T36.6b self-consistency ✓ line" "codemap: fn self-consistency" "$OUT"
# inject parse_failures (re-signed; gate reads the cache verbatim — no auto-rescan)
T36_CLONE="$TESTBASE/clone6-$RANDOM-t36"
git clone -q "$T36_REPO" "$T36_CLONE" 2>/dev/null
ln -s "$T36_REPO/node_modules" "$T36_CLONE/node_modules"
(cd "$T36_CLONE" && node "$GOS" map scan >/dev/null 2>&1 && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm annot)
# gate requires an active task — seed one headlessly (GOS_HEADLESS auto-confirms)
(cd "$T36_CLONE" && node "$GOS" init 1 "codemap-gate-test" >/dev/null 2>&1)
node -e "
const fs=require('fs');
const d=require(process.argv[1]+'/.gos/cache/deps.json');
d.semantic.parse_failures=[{file:'x.js',msg:'boom'}];
delete d.self_sha256;
const crypto=require('crypto');
d.self_sha256=crypto.createHash('sha256').update(JSON.stringify(d,null,2)+'\n','utf8').digest('hex');
fs.writeFileSync(process.argv[1]+'/.gos/cache/deps.json', JSON.stringify(d,null,2));
" "$T36_CLONE"
OUT=$(cd "$T36_CLONE" && node "$GOS" gate codemap 2>&1); RC=$?
assert_exit "T36.6c parse_failures → gate codemap FAIL (exit 1)" 1 "$RC"
assert_contains "T36.6d FAIL text names the parse failure" "parse failed" "$OUT"
# dead annotation → FAIL
node -e "
const fs=require('fs');
const d=require(process.argv[1]+'/.gos/cache/deps.json');
d.semantic.parse_failures=[];
d.semantic.dead_fn_annotations=['T99-fake#ghostFn'];
delete d.self_sha256;
const crypto=require('crypto');
d.self_sha256=crypto.createHash('sha256').update(JSON.stringify(d,null,2)+'\n','utf8').digest('hex');
fs.writeFileSync(process.argv[1]+'/.gos/cache/deps.json', JSON.stringify(d,null,2));
" "$T36_CLONE"
OUT=$(cd "$T36_CLONE" && node "$GOS" gate codemap 2>&1); RC=$?
assert_exit "T36.6e dead annotations → FAIL (exit 1)" 1 "$RC"
assert_contains "T36.6f FAIL text names dead annotations" "dead gos-map:fn annotation" "$OUT"
# absent deps.json → advisory, exit 0 (capability not enabled must not block).
# GOS_CI=1: a fresh clone ships tracked .gos/gates/ scripts without a trust
# store — CI mode skips them with an advisory instead of the local-only
# untrusted-script FAIL (trust layer semantics).
mv "$T36_CLONE/.gos/cache/deps.json" "$T36_CLONE/.gos/cache/deps.json.bak"
(cd "$T36_CLONE" && GOS_CI=1 node "$GOS" gate codemap >/dev/null 2>&1)
assert_exit "T36.6g no deps.json → advisory exit 0" 0 "$?"
N=$(cd "$T36_REPO" && node "$GOS" init 1 "codemap-gate-all-chain" >/dev/null 2>&1; node "$GOS" gate all 2>&1 | grep -c "codemap:")
[ "$N" -ge 1 ] && { echo "  [ok] T36.6h gate all chains codemap ($N lines)"; PASS=$((PASS+1)); } || { echo "  X T36.6h gate all does not chain codemap"; FAIL=$((FAIL+1)); }
OUT=$(cd "$T36_REPO" && node "$GOS" map closure "bin/gos.cjs#fn:pathOf" --graph 2>/dev/null)
assert_contains "T36.6i closure --graph renders fn nodes" "fn:pathOf" "$OUT"
rm -rf "$T36_CLONE"

# --- .7 : render drill-down — full graph excludes fn family; --fn neighborhood; show fn view
(cd "$T36_REPO" && node "$GOS" map scan >/dev/null 2>&1)
N=$(cd "$T36_REPO" && node "$GOS" map graph 2>/dev/null | grep -c '#fn:')
assert_eq "T36.7a full graph has 0 fn nodes (default off)" "0" "$N"
N=$(cd "$T36_REPO" && node "$GOS" map graph --fn "bin/gos.cjs#fn:pathOf" 2>/dev/null | grep -c '#fn:')
[ "$N" -gt 0 ] && { echo "  ✓ T36.7b --fn anchor renders fn nodes ($N)"; PASS=$((PASS+1)); } || { echo "  ✗ T36.7b --fn anchor renders fn nodes"; FAIL=$((FAIL+1)); }
LINES=$(cd "$T36_REPO" && node "$GOS" map graph --fn "bin/gos.cjs#fn:cmdMap" 2>/dev/null | wc -l)
[ "$LINES" -lt 200 ] && { echo "  ✓ T36.7c --fn neighborhood bounded ($LINES lines < 200)"; PASS=$((PASS+1)); } || { echo "  ✗ T36.7c neighborhood too big ($LINES lines)"; FAIL=$((FAIL+1)); }
node "$GOS" map graph --fn >/dev/null 2>&1
assert_exit "T36.7d bare --fn dies with Usage" 1 "$?"
OUT=$(cd "$T36_REPO" && node "$GOS" map show "bin/lib/map/engine.cjs#fn:mapResolveSpec" 2>/dev/null)
assert_contains "T36.7e show fn neighborhood has callers" "called-by" "$OUT"
assert_contains "T36.7f show dedupes repeated call sites" "$(echo "$OUT" | grep -c 'fn:scanSources' | awk '{print ($1==1)?1:0}')" "1"
grep -q "callgraph (⑥" "$T36_REPO/.gos/codebase/network.md" && { echo "  ✓ T36.7g network.md has fn family stats"; PASS=$((PASS+1)); } || { echo "  ✗ T36.7g network.md fn family missing"; FAIL=$((FAIL+1)); }
grep -q "fn quick reference" "$T36_REPO/.gos/codebase/network.md" && { echo "  ✓ T36.7h network.md has fn quick-reference"; PASS=$((PASS+1)); } || { echo "  ✗ T36.7h fn quick-reference missing"; FAIL=$((FAIL+1)); }

# --- .8 : trap fixtures — exact edge-set assertions in an isolated clone ( blind spots ARE assertions)
mkdir -p "$TESTBASE/traps-src"
cat > "$TESTBASE/traps-src/trap1-redecl.js" <<'EOF'
function dup(){ return 1; }
function dup(){ return 2; }
function user(){ return dup(); }
EOF
cat > "$TESTBASE/traps-src/trap2-shadow.js" <<'EOF'
function A(){ return 1; }
function B(A){ return A(); }   // param shadows top-level A — false edge B->A is a DOCUMENTED blind spot (R-03)
EOF
cat > "$TESTBASE/traps-src/trap3-alias.js" <<'EOF'
function real(){ return 1; }
const alias = real;
function caller(){ return alias(); }   // alias call — MISSING edge caller->real is a documented blind spot (R-03)
EOF
cat > "$TESTBASE/traps-src/trap4-arrow.js" <<'EOF'
function inner(){ return 1; }
function outer(){ const g = () => inner(); return g(); }   // arrow-internal call belongs to nearest TOP-LEVEL fn
EOF
cat > "$TESTBASE/traps-src/trap5-recursion.js" <<'EOF'
function fact(n){ return n <= 1 ? 1 : n * fact(n - 1); }   // self-edge is REAL (recursion)
EOF
cat > "$TESTBASE/traps-src/trap6-mutual.js" <<'EOF'
function isEven(n){ return n === 0 ? true : isOdd(n - 1); }
function isOdd(n){ return n === 0 ? false : isEven(n - 1); }
EOF
T36_CLONE="$TESTBASE/clone8-$RANDOM-t36"
git clone -q "$T36_REPO" "$T36_CLONE" 2>/dev/null
ln -s "$T36_REPO/node_modules" "$T36_CLONE/node_modules"
mkdir -p "$T36_CLONE/traps-src" && cp "$TESTBASE/traps-src/"*.js "$T36_CLONE/traps-src/"
(cd "$T36_CLONE" && git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm traps >/dev/null 2>&1 && node "$GOS" map scan >/dev/null 2>&1)
node -e "
const d = require(process.argv[1] + '/.gos/cache/deps.json');
const edges = new Set((d.semantic.callgraph || []).filter(e => e.file.startsWith('traps-src/')).map(e => e.file + '|' + e.from + '->' + e.to));
const expect = [
  'traps-src/trap1-redecl.js|user->dup',
  'traps-src/trap2-shadow.js|B->A',           // blind-spot false edge: asserted PRESENT (documented)
  'traps-src/trap4-arrow.js|outer->inner',
  'traps-src/trap5-recursion.js|fact->fact',  // recursion self-edge
  'traps-src/trap6-mutual.js|isEven->isOdd',
  'traps-src/trap6-mutual.js|isOdd->isEven',
];
let bad = 0;
for (const x of expect) if (!edges.has(x)) { console.log('MISSING ' + x); bad++; }
if (!edges.has('traps-src/trap3-alias.js|caller->real')) { console.log('OK alias-missing-edge confirmed (blind spot as documented)'); } else { console.log('UNEXPECTED alias edge'); bad++; }
console.log(bad === 0 ? 'TRAPS-OK' : 'TRAPS-FAIL');
" "$T36_CLONE" > t368.txt 2>&1
assert_contains "T36.8a all trap edges exact (incl. documented blind spots)" "TRAPS-OK" "$(cat t368.txt)"

# live-repo pilot annotations: 3 sections get gos-map:fn headers
for spec in "T12-wiring.test.sh:cmdCommit,cmdStatus" "T13-semantic-contracts.test.sh:cmdGate,cmdContract" "T17-semantic-engine.test.sh:cmdGate"; do
  f="${spec%%:*}"; fns="${spec#*:}"
  grep -q "gos-map:fn" "$T36_REPO/test/sections/$f" || sed -i "s|^# gos-map:cmd |# gos-map:fn $fns\n# gos-map:cmd |" "$T36_REPO/test/sections/$f"
done
(cd "$T36_REPO" && node "$GOS" map scan >/dev/null 2>&1)
TFN=$(node -e "
const t=(require(process.argv[1]+'/.gos/cache/deps.json').semantic.testof_fn)||[];
console.log(t.filter(e=>['T12-wiring','T13-semantic-contracts','T17-semantic-engine'].includes(e.sec)).length)" "$T36_REPO")
[ "$TFN" -ge 3 ] && { echo "  ✓ T36.8b pilot annotations produce ≥3 testof_fn edges ($TFN)"; PASS=$((PASS+1)); } || { echo "  ✗ T36.8b pilot testof_fn edges=$TFN (want ≥3)"; FAIL=$((FAIL+1)); }
OUT=$(cd "$T36_REPO" && node "$GOS" gate codemap 2>&1)
assert_contains "T36.8c codemap advisory shrinks (annotated cmds gone)" "cmd-entry fn" "$OUT"
rm -rf "$T36_CLONE" "$TESTBASE/traps-src"

echo "--- T36 done: PASS=$PASS FAIL=$FAIL ---"
[ "$FAIL" -eq 0 ] || exit 1
