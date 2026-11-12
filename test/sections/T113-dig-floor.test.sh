#!/usr/bin/env bash
# gos-map:fn bin/lib/knowledge/decisions.cjs#fn:cmdDecision bin/lib/ops/gate.cjs#fn:digFloorFreezeCheck bin/lib/task/commit.cjs#fn:cmdCommit
# gos-map:cmd decision,commit
# Card-preflight dig floor: evidence-object dig is required at decision add
# past the floor era (free text refused; ruling/waiver citations accepted),
# the THINK spec freeze refuses post-era decisions without dig evidence
# while pre-era records grandfather with a loud advisory, and spec headings
# owning an id absent from state surface as prose-era advisories.
T113_DIR=""

t113_setup() {
  T113_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t113"
  mkdir -p "$T113_DIR" && cd "$T113_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/.lock\n.gos/cache/\n" > .gitignore
  git add .gitignore && git commit -q -m gi
  printf 'anchor target line one\nanchor target line two\n' > probe.txt
  git add probe.txt && git commit -q -m probe
}

t113_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T113_DIR"; }

t113_spec_path() {
  node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])'
}

t113_state_field() {
  node -e "
const s=JSON.parse(require('fs').readFileSync('.gos/state.json','utf8'));
console.log(s['$1']===undefined?'absent':String(s['$1']));
" 2>&1
}

t113_setup
trap 't113_teardown' EXIT
PASS=0; FAIL=0
echo "--- T113: card-preflight dig floor (add-time evidence + freeze era semantics) ---"

# ===== part 1: add-time evidence floor =====
ERA="$(node -e "console.log(require('$GOS_ROOT/bin/lib/knowledge/decisions.cjs').DIG_FLOOR_ERA)" 2>/dev/null)"
if [ -n "$ERA" ] && printf '%s' "$ERA" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}'; then
  echo "  ✓ era constant exported as an ISO timestamp"; PASS=$((PASS+1))
else
  echo "  ✗ era constant missing or not ISO ('$ERA')"; FAIL=$((FAIL+1))
fi

node "$GOS" init 3 "dig floor" >/dev/null 2>&1

# bare add past the era: refused, message names every accepted shape
set +e; OUT=$(node "$GOS" decision add D-01 "needs evidence" --rationale r 2>&1); RC=$?; set -e
assert_exit "bare add without dig evidence refused" 1 "$RC"
assert_contains "refusal names the accepted shapes" "accepted shapes" "$OUT"
assert_contains "refusal names the evidence-object shape" "[-]-dig " "$OUT"
assert_contains "refusal names the ruling alternate" "[-]-dig-ruling" "$OUT"
assert_contains "refusal names the waiver alternate" "[-]-dig-waiver" "$OUT"

# free text in either spelling is not evidence
set +e; OUT=$(node "$GOS" decision add D-01 "free text dig" --dig 'just words, no json' 2>&1); RC=$?; set -e
assert_exit "non-JSON dig value refused" 1 "$RC"
assert_contains "non-JSON refusal names the shapes" "accepted shapes" "$OUT"

set +e; OUT=$(node "$GOS" decision add D-01 "string dig" --dig '"I looked around and it seemed fine"' 2>&1); RC=$?; set -e
assert_exit "JSON free-text sentence refused (object required)" 1 "$RC"
assert_contains "string refusal names the shapes" "accepted shapes" "$OUT"

# evidence object with missing pieces
set +e; OUT=$(node "$GOS" decision add D-01 "half dig" --dig '{"command":"grep -n anchor probe.txt","anchor":"probe.txt:1"}' 2>&1); RC=$?; set -e
assert_exit "dig missing output_excerpt refused" 1 "$RC"
assert_contains "missing-field refusal names output_excerpt" "output_excerpt" "$OUT"

set +e; OUT=$(node "$GOS" decision add D-01 "dead anchor" --dig '{"command":"cat nope.txt","output_excerpt":"missing","anchor":"nope.txt:9"}' 2>&1); RC=$?; set -e
assert_exit "unresolvable anchor refused" 1 "$RC"
assert_contains "anchor refusal names resolution" "anchor" "$OUT"

set +e; OUT=$(node "$GOS" decision add D-01 "out of range anchor" --dig '{"command":"cat probe.txt","output_excerpt":"two lines","anchor":"probe.txt:99"}' 2>&1); RC=$?; set -e
assert_exit "out-of-range line anchor refused" 1 "$RC"

# alternate-source discipline
set +e; OUT=$(node "$GOS" decision add D-01 "empty ruling" --dig-ruling '' 2>&1); RC=$?; set -e
assert_exit "empty ruling citation refused" 1 "$RC"

set +e; OUT=$(node "$GOS" decision add D-01 "double source" --dig-ruling '2026-11-11 user ruling' --dig-waiver 'none' 2>&1); RC=$?; set -e
assert_exit "two dig sources refused" 1 "$RC"
assert_contains "single-source rule named" "exactly one" "$OUT"

# valid evidence object accepted; state carries dig + born_at
set +e; OUT=$(node "$GOS" decision add D-01 "dug decision" --rationale r --dig '{"command":"grep -n anchor probe.txt","output_excerpt":"1:anchor target line one","anchor":"probe.txt:1"}' 2>&1); RC=$?; set -e
assert_exit "valid evidence-object dig accepted" 0 "$RC"
D1=$(node -e "
const m=require('$GOS_ROOT/bin/lib/knowledge/decisions.cjs');
const s=JSON.parse(require('fs').readFileSync('.gos/state.json','utf8'));
const d=(s.decisions||[]).find((x)=>x.id==='D-01')||{};
const g=d.dig||{};
const shape=(g.command==='grep -n anchor probe.txt'&&g.output_excerpt==='1:anchor target line one'&&g.anchor==='probe.txt:1')?'dig-ok':'dig-bad';
const born=(typeof d.born_at==='string'&&d.born_at>m.DIG_FLOOR_ERA)?'post-era':'born-bad';
console.log(shape+'|'+born);
" 2>&1)
assert_eq "state carries the dig object and a post-era born_at stamp" "dig-ok|post-era" "$D1"
assert_contains "add contract line unchanged" "added: dug decision" "$OUT"

# ruling and waiver alternates accepted
set +e; OUT=$(node "$GOS" decision add D-02 "ruled decision" --dig-ruling '2026-11-11 user ruling in the live session' 2>&1); RC=$?; set -e
assert_exit "ruling alternate accepted" 0 "$RC"
D2=$(node -e "
const s=JSON.parse(require('fs').readFileSync('.gos/state.json','utf8'));
const d=(s.decisions||[]).find((x)=>x.id==='D-02')||{};
console.log((d.dig&&typeof d.dig.ruling==='string'&&d.dig.ruling.length>0&&typeof d.born_at==='string')?'ruling-ok':'ruling-bad');
" 2>&1)
assert_eq "ruling record carries dig.ruling + born_at" "ruling-ok" "$D2"

set +e; OUT=$(node "$GOS" decision add D-03 "waived decision" --dig-waiver 'fixture decision outside the dig contract scope' 2>&1); RC=$?; set -e
assert_exit "waiver alternate accepted" 0 "$RC"
D3=$(node -e "
const s=JSON.parse(require('fs').readFileSync('.gos/state.json','utf8'));
const d=(s.decisions||[]).find((x)=>x.id==='D-03')||{};
console.log((d.dig&&typeof d.dig.waiver==='string'&&d.dig.waiver.length>0&&typeof d.born_at==='string')?'waiver-ok':'waiver-bad');
" 2>&1)
assert_eq "waiver record carries dig.waiver + born_at" "waiver-ok" "$D3"

assert_contains "list renders the enriched records" "D-03" "$(node "$GOS" decision list 2>&1)"

# ===== part 2: THINK spec freeze refuses post-era dig-less decisions =====
t113_teardown; t113_setup
node "$GOS" init 3 "freeze floor" >/dev/null 2>&1
node "$GOS" commit intent >/dev/null 2>&1
SPEC="$(t113_spec_path)"
mkdir -p "$(dirname "$SPEC")"
# heading hashes ride a variable so the fixture's markdown headings stay
# expandable at write time instead of parsing as shell comments in this file
SPEC_H='##'
cat > "$SPEC" <<SPECEOF
# dig floor fixture spec

${SPEC_H} D-01 post-era decision under the dig floor

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| freeze-leg | direct state read | always blocks | new code path | think freeze |
| probe-leg | registry probe | no new code | never blocks | think freeze |

why-not: probe-leg — the probe returns the first passing floor and passes dig-less content

${SPEC_H} D-02 pre-era grandfather record

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| grandfather | era boundary | zero migration | unchecked | advisory line |
| backfill | re-dig old records | full coverage | rewrites history | advisory line |

why-not: backfill — pre-era records never promised the floor
SPECEOF
node "$GOS" approve think >/dev/null 2>&1
node -e "
const fs=require('fs');
const s=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
s.decisions=[
 {id:'D-01',title:'post-era without dig',rationale:'r',birth_phase:'P0',status:'open',anchor:null,covered:false,covered_by:null,born_at:'2030-01-01T00:00:00.000Z'},
 {id:'D-02',title:'pre-era grandfather',rationale:'r',birth_phase:'P0',status:'open',anchor:null,covered:false,covered_by:null}
];
fs.writeFileSync('.gos/state.json', JSON.stringify(s,null,2));
"
git add "$SPEC" >/dev/null 2>&1

set +e; OUT=$(node "$GOS" commit think 2>&1); RC=$?; set -e
assert_exit "spec freeze refuses the post-era dig-less decision" 1 "$RC"
assert_contains "refusal names the floor" "dig floor" "$OUT"
assert_contains "refusal names the decision id" "D-01" "$OUT"
assert_contains "refusal names the era semantics" "post-era" "$OUT"
assert_eq "refused freeze leaves the stage at THINK" "THINK" "$(t113_state_field current_stage)"
assert_eq "refused freeze persists no floor stamp" "absent" "$(t113_state_field spec_gate_version)"

# cure: attach dig evidence to the post-era record -> the freeze passes
node -e "
const fs=require('fs');
const s=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
const d=s.decisions.find((x)=>x.id==='D-01');
d.dig={command:'grep -n anchor probe.txt',output_excerpt:'1:anchor target line one',anchor:'probe.txt:1'};
fs.writeFileSync('.gos/state.json', JSON.stringify(s,null,2));
"
set +e; OUT=$(node "$GOS" commit think 2>&1); RC=$?; set -e
assert_exit "dug decision passes the freeze" 0 "$RC"
assert_contains "grandfather advisory names the pre-era record" "dig floor: grandfathered D-02 — pre-era decision" "$OUT"
assert_eq "freeze advanced the task past THINK" "PLAN" "$(t113_state_field current_stage)"

# ===== part 3: spec-prose decision headings advise, never block =====
t113_teardown; t113_setup
node "$GOS" init 3 "prose advisory" >/dev/null 2>&1
node "$GOS" commit intent >/dev/null 2>&1
SPEC="$(t113_spec_path)"
mkdir -p "$(dirname "$SPEC")"
printf '# prose-era spec\n\n## D-07 legacy prose-only decision\n\nChosen in prose before the floor era; no state record exists.\n' > "$SPEC"
node "$GOS" approve think >/dev/null 2>&1
node -e "
const fs=require('fs');const c=require('crypto');
const s=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
s.spec_sha256=c.createHash('sha256').update(fs.readFileSync(process.argv[1])).digest('hex');
fs.writeFileSync('.gos/state.json', JSON.stringify(s,null,2));
" "$SPEC"
git add "$SPEC" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" commit think 2>&1); RC=$?; set -e
assert_exit "prose-only heading does not block the freeze" 0 "$RC"
assert_contains "spec-prose advisory names the heading id" "dig floor: D-07 lives in spec prose only" "$OUT"

t113_teardown
echo "--- T113 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
