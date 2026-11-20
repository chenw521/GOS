#!/usr/bin/env bash
# gos-map:fn bin/lib/knowledge/decisions.cjs#fn:cmdDecision bin/lib/knowledge/decisions.cjs#fn:deepenClosed bin/lib/ops/gate.cjs#fn:digClosureFailures bin/lib/ops/gate.cjs#fn:digFloorFreezeCheck
# gos-map:cmd decision,commit,gate
# Dig-closure floor: a decision records only with its deepen line closed,
# every enumerated dig anchor resolvable, no waiver inside a marker
# session, and dug_at stamps that predate the freeze stamp. An open deepen
# tail, an anchor-less enumeration, a marker-session waiver, a forged
# post-freeze dug_at, and a zero-anchor omission card all refuse; records
# whose dig evidence predates the stamping era grandfather with a loud
# advisory instead of failing.
T122_DIR=""

t122_setup() {
  T122_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t122"
  mkdir -p "$T122_DIR" && cd "$T122_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/.lock\n.gos/cache/\n" > .gitignore
  git add .gitignore && git commit -q -m gi
  printf 'anchor target line one\nanchor target line two\n' > probe.txt
  git add probe.txt && git commit -q -m probe
}

t122_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T122_DIR"; }

t122_spec_path() {
  node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])'
}

t122_state_field() {
  node -e "
const s=JSON.parse(require('fs').readFileSync('.gos/state.json','utf8'));
console.log(s['$1']===undefined?'absent':String(s['$1']));
" 2>&1
}

t122_setup
trap 't122_teardown' EXIT
PASS=0; FAIL=0
echo "--- T122: dig-closure floor (deepen closure, anchored enumeration, marker waiver, forged stamps) ---"

# ===== part 1: add-time closure negatives =====
node "$GOS" init 3 "closure floor" >/dev/null 2>&1

# negative 1: open deepen tail line - the card still asks for another dig round
set +e; OUT=$(node "$GOS" decision add D-01 "open deepen record" --dig '{"command":"grep -n anchor probe.txt","output_excerpt":"1:anchor target line one","anchor":"probe.txt:1"}' --deepen "deepen: any option - ask for another dig round" 2>&1); RC=$?; set -e
assert_exit "open deepen line refused at add" 1 "$RC"
assert_contains "open-line refusal names the closed-state rule" "line not closed" "$OUT"
assert_contains "open-line refusal teaches the closed form" "closed form" "$OUT"

# negative 2: dig supplied as an enumeration without anchors
set +e; OUT=$(node "$GOS" decision add D-01 "enumeration without anchors" --dig '{"command":"grep -rn site src","output_excerpt":"two call sites","anchor":["site one","site two"]}' 2>&1); RC=$?; set -e
assert_exit "enumerated non-anchor entries refused" 1 "$RC"
assert_contains "enumeration refusal names the file:line grammar" "expected file:line" "$OUT"

set +e; OUT=$(node "$GOS" decision add D-01 "dead anchor in enumeration" --dig '{"command":"cat probe.txt","output_excerpt":"two lines","anchor":["probe.txt:1","probe.txt:99"]}' 2>&1); RC=$?; set -e
assert_exit "enumeration with one dead anchor refused" 1 "$RC"
assert_contains "dead-anchor refusal names the range violation" "line 99 outside" "$OUT"

# negative 3: waiver-only evidence inside a marker session. The CLI route is
# refused by the spawn channel first (a spawned session never carries the
# decision verb), so the flag shape is proven through the channel and the
# refusal inside the decision path is driven in-process with the marker env
# set (same module function the dispatcher calls, same env it reads).
set +e; OUT=$(GOS_AUTO_SPAWNED=1 node "$GOS" decision add D-01 "marker waiver flag" --dig-waiver "fixture waiver under the spawned session" 2>&1); RC=$?; set -e
assert_exit "marker-session decision add refused at the spawn channel" 1 "$RC"
assert_contains "channel refusal names the spawn channel" "spawn channel refused" "$OUT"

set +e; OUT=$(node -e "
process.env.GOS_AUTO_SPAWNED='1';
const m=require('$GOS_ROOT/bin/lib/knowledge/decisions.cjs');
m.cmdDecision(['add','D-01','marker waiver flag','--dig-waiver','fixture waiver under the spawned session']);
" 2>&1); RC=$?; set -e
assert_exit "flag waiver refused inside a marker session" 1 "$RC"
assert_contains "marker refusal names the session marker" "marker session" "$OUT"

set +e; OUT=$(node -e "
process.env.GOS_AUTO_SPAWNED='1';
const m=require('$GOS_ROOT/bin/lib/knowledge/decisions.cjs');
m.cmdDecision(['add','D-01','marker waiver json','--dig','{\"waiver\":\"fixture waiver object under the spawned session\"}']);
" 2>&1); RC=$?; set -e
assert_exit "JSON waiver shape refused inside a marker session" 1 "$RC"
assert_contains "JSON waiver refusal names the human-channel rule" "human-channel" "$OUT"

set +e; OUT=$(node "$GOS" decision add D-01 "human channel waiver" --dig-waiver "fixture waiver granted on the human channel" 2>&1); RC=$?; set -e
assert_exit "the same waiver lands outside the marker session" 0 "$RC"

# closure green path: closed deepen line + resolvable enumerated anchors
set +e; OUT=$(node "$GOS" decision add D-02 "closed anchored record" --dig '{"command":"grep -n anchor probe.txt","output_excerpt":"1:anchor target line one","anchor":["probe.txt:1","probe.txt:2"]}' --deepen "deepen: closed - probed both target lines" 2>&1); RC=$?; set -e
assert_exit "closed deepen line with resolvable anchors accepted" 0 "$RC"
assert_contains "closed record lands with the add contract" "added: closed anchored record" "$OUT"

D2=$(node -e "
const m=require('$GOS_ROOT/bin/lib/knowledge/decisions.cjs');
const s=JSON.parse(require('fs').readFileSync('.gos/state.json','utf8'));
const d=(s.decisions||[]).find((x)=>x.id==='D-02')||{};
const sha=(typeof d.dug_sha==='string'&&d.dug_sha===m.digObjectSha(d.dig))?'sha-ok':'sha-bad';
const at=(typeof d.dug_at==='string'&&/T.*Z$/.test(d.dug_at))?'at-ok':'at-bad';
const dp=(d.deepen==='deepen: closed - probed both target lines')?'deepen-ok':'deepen-bad';
console.log(sha+'|'+at+'|'+dp);
" 2>&1)
assert_eq "record carries dug_at + dug_sha matching the dig object + the closed deepen line" "sha-ok|at-ok|deepen-ok" "$D2"

CLOSURE=$(node -e "
const g=require('$GOS_ROOT/bin/lib/ops/gate.cjs');
const fs=require('fs');
const s=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
s.decisions.push({id:'D-04',title:'pre-stamp dig record',rationale:'r',birth_phase:'P0',status:'open',anchor:null,covered:false,covered_by:null,born_at:'2026-01-01T00:00:00.000Z',dig:{command:'cat probe.txt',output_excerpt:'two lines',anchor:'probe.txt:1'}});
const r=g.digClosureFailures(s);
console.log('failures='+r.failures.length+' stamped='+r.stamped+' grandfathered='+r.grandfathered);
" 2>&1)
assert_contains "gate-side closure check passes the stamped records" "failures=0 stamped=2 grandfathered=1" "$CLOSURE"
assert_contains "pre-stamp dig record grandfathers as a loud advisory" "dig-closure: grandfathered D-04" "$CLOSURE"

# negative 5: omission card - zero anchors offered under a closed line
set +e; OUT=$(node "$GOS" decision add D-03 "omission card" --dig '{"command":"cat probe.txt","output_excerpt":"two lines","anchor":[]}' --deepen "deepen: closed - enumerated nothing" 2>&1); RC=$?; set -e
assert_exit "zero-anchor dig refused even with a closed deepen line" 1 "$RC"
assert_contains "omission refusal demands at least one anchor" "at least one resolvable file:line anchor" "$OUT"

set +e; OUT=$(node "$GOS" decision add D-03 "anchorless dig" --dig '{"command":"cat probe.txt","output_excerpt":"two lines"}' --deepen "deepen: closed - no anchors offered" 2>&1); RC=$?; set -e
assert_exit "missing anchor field refused under a closed line" 1 "$RC"
assert_contains "missing-anchor refusal names the string grammar" "anchor: file:line string required" "$OUT"

# ===== part 2: forged post-freeze anchor (dug_at after the freeze stamp) =====
t122_teardown; t122_setup
node "$GOS" init 3 "forged freeze" >/dev/null 2>&1
node "$GOS" commit intent >/dev/null 2>&1
SPEC="$(t122_spec_path)"
mkdir -p "$(dirname "$SPEC")"
# heading hashes ride a variable so the fixture's markdown headings stay
# expandable at write time instead of parsing as shell comments in this file
SPEC_H='##'
cat > "$SPEC" <<SPECEOF
# closure freeze fixture spec

${SPEC_H} D-01 stamped record with a forged post-freeze dug_at

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| forged | dug_at sits after the freeze stamp | none | ordering violation | closure floor refusal |
| honest | fresh dig before the next freeze | true record | one more dig round | closure floor pass |

why-not: honest - the fixture isolates the forged ordering leg
SPECEOF
node "$GOS" approve think >/dev/null 2>&1
node -e "
const fs=require('fs');
const m=require('$GOS_ROOT/bin/lib/knowledge/decisions.cjs');
const s=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
const dig={command:'grep -n anchor probe.txt',output_excerpt:'1:anchor target line one',anchor:'probe.txt:1'};
s.decisions=[{id:'D-01',title:'forged post-freeze anchor',rationale:'r',birth_phase:'P0',status:'open',anchor:null,covered:false,covered_by:null,born_at:'2030-01-01T00:00:00.000Z',dig:dig,dug_at:'2030-06-01T00:00:00.000Z',dug_sha:m.digObjectSha(dig)}];
s.dig_closure_frozen_at='2030-01-02T00:00:00.000Z';
fs.writeFileSync('.gos/state.json', JSON.stringify(s,null,2));
"
git add "$SPEC" >/dev/null 2>&1

set +e; OUT=$(node "$GOS" commit think 2>&1); RC=$?; set -e
assert_exit "freeze refuses the forged post-freeze dug_at" 1 "$RC"
assert_contains "freeze refusal names the forged-anchor code" "dig-closure-forged-anchor" "$OUT"
assert_contains "forged verdict names the ordering violation" "postdates the freeze" "$OUT"
assert_eq "refused freeze leaves the stage at THINK" "THINK" "$(t122_state_field current_stage)"

set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "gate semantic fails the forged anchor (registry-external leg)" 1 "$RC"
assert_contains "gate failure list carries the forged-anchor code" "dig-closure-forged-anchor" "$OUT"

# ===== part 3: live repo closure floor (read-only tie-in) =====
REAL="$( cd "$GOS_ROOT" && node -e '
const gate=require(process.env.GOS_ROOT+"/bin/lib/ops/gate.cjs");
const core=require(process.env.GOS_ROOT+"/bin/lib/core/index.cjs");
const s=core.readState();
if(!s){ console.log("stateless-tree"); process.exit(0); }
const r=gate.digClosureFailures(s);
if(r.failures.length){ console.log("floor-fail "+r.failures.map((f)=>f.code).join(",")); process.exit(0); }
console.log("floor-ok stamped="+r.stamped+" grandfathered="+r.grandfathered);
' 2>&1 )"
LAST="$(printf '%s\n' "$REAL" | tail -1)"
case "$LAST" in
  floor-ok*|stateless-tree)
    echo "  ✓ live closure floor holds (pre-stamp records advise, never fail): $LAST";;
  *)
    echo "  ✗ live closure floor reported failures: $LAST"; FAIL=$((FAIL+1));;
esac
ADV="$(printf '%s\n' "$REAL" | grep -c 'dig-closure: grandfathered' || true)"
if [ "$ADV" -gt 0 ]; then
  case "$LAST" in
    floor-ok*) echo "  ✓ grandfather advisories ride alongside a passing floor ($ADV advisory line(s), non-fatal)";;
    *) : ;;
  esac
else
  echo "  - no pre-stamp dig records on this tree (fresh checkout); the advisory leg is covered by the fixture above"
fi

t122_teardown
echo "--- T122 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
