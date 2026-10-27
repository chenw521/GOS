#!/usr/bin/env bash
# gos-map:none   # sandbox builds its own project container; no live-repo truth source
# render views single source of truth (state-only default + --all audit) + claim gate prev-done/parked
#      + park lifecycle + milestone debt visibility + ghost teaching line + residual byte-stability
PASS=0; FAIL=0
command -v assert_exit >/dev/null || assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected exit $expected, got '${actual:-<none>}')"; FAIL=$((FAIL+1)); fi
}
command -v assert_contains >/dev/null || assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected: '$expected')"; echo "    actual: ${actual:0:200}"; FAIL=$((FAIL+1)); fi
}
command -v assert_not_contains >/dev/null || assert_not_contains() {
  local label="$1" forbidden="$2" actual="$3"
  if echo "$actual" | grep -q "$forbidden"; then echo "  ✗ $label (forbidden '$forbidden' present)"; FAIL=$((FAIL+1)); else echo "  ✓ $label"; PASS=$((PASS+1)); fi
}
command -v t39_done_state >/dev/null || t39_done_state() {
  node -e "
const fs=require('fs');
const d=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
d.current_stage='DONE'; delete d.completed_at; d.approvals={};
fs.writeFileSync('.gos/state.json', JSON.stringify(d,null,2));
" >/dev/null 2>&1
}
GOS="${GOS:-$(git rev-parse --show-toplevel 2>/dev/null)/bin/gos.cjs}"
T39_DIR=""

# Fixture paths follow the CLI supply (task/<id>/) — never hardcode the .gos/ root
gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }
gos_plan() { node "$GOS" context plan 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["plan"])' 2>/dev/null; }

t39_residual_hash() {
  node -e "
const p=require(process.argv[1]);
const pick=(a,id)=>JSON.stringify((a||[]).filter(x=>x.id===id)[0]||null);
const out=['R-02','R-03','D-01','D-02'].map(id=>pick(p.requirements,id)+pick(p.decisions,id)).join('|');
console.log(require('crypto').createHash('sha256').update(out).digest('hex'));
" "$T39_DIR/.gos/project/project.json"
}

t39_setup() {
  [ -n "$TESTBASE" ] || TESTBASE="$(mktemp -d)"
  T39_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t39"
  mkdir -p "$T39_DIR" && cd "$T39_DIR" || exit 1
  git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m root
  node "$GOS" init --project 1 "t39 container" >/dev/null 2>&1
 # PROJECT.md gate: fill the seeded skeleton (TODO-only would block archive preflight)
  cat > .gos/project/PROJECT.md << 'EOF'
## What This Is
t39 fixture container for render-truth, park lifecycle, and ghost-plan coverage.

## Core Value
Exercises parked-phase debt visibility and legacy residual rendering in one section.

## Requirements Evolution
Legacy done-phase residuals (frozen requirement, superseded decisions) are injected below.
EOF
  node "$GOS" phase add "A-alpha: first" --goal "t39 fixture one" >/dev/null 2>&1
  node "$GOS" phase add "B-beta: second" --goal "t39 fixture two" >/dev/null 2>&1
  node "$GOS" phase add "C-gamma: third" --goal "t39 fixture three" >/dev/null 2>&1
  # Inject done-phase residuals: status-frozen active requirement / superseded decision
  node -e "
const fs=require('fs');
const p=JSON.parse(fs.readFileSync('.gos/project/project.json','utf8'));
p.requirements=p.requirements||[];
p.requirements.push({id:'R-02',text:'legacy done-phase requirement',phase:null,status:'active'});
p.requirements.push({id:'R-03',text:'legacy dropped requirement',phase:null,status:'dropped'});
p.decisions=p.decisions||[];
p.decisions.push({id:'D-01',title:'legacy decision',rationale:'',birth_phase:'A-alpha: first',status:'open',anchor:null,covered:false,covered_by:null});
p.decisions.push({id:'D-02',title:'legacy superseded',rationale:'',birth_phase:'A-alpha: first',status:'superseded',anchor:null,covered:false,covered_by:null});
fs.writeFileSync('.gos/project/project.json',JSON.stringify(p,null,2));
" >/dev/null 2>&1
}

t39_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T39_DIR"; }

t39_setup
echo "--- T39: render truth-source + park lifecycle + ghost teaching ---"

H0=$(t39_residual_hash)

# ===== : requirement list state-only default / --all merge =====
OUT=$(node "$GOS" requirement list 2>&1)
assert_contains "T1.a default shows wrapper R-01 only" "t39 container" "$OUT"
assert_not_contains "T1.b default hides legacy R-02" "legacy done-phase requirement" "$OUT"
OUT=$(node "$GOS" requirement list --all 2>&1)
assert_contains "T1.c --all shows legacy R-02" "legacy done-phase requirement" "$OUT"
assert_contains "T1.d --all keeps write-time snapshot status (dropped)" "dropped" "$OUT"

# ===== (pre-claim): decision list empty by default / --all carries residuals and superseded =====
OUT=$(node "$GOS" decision list 2>&1)
assert_contains "T2.a default empty state says no decisions" "(no decisions)" "$OUT"
assert_not_contains "T2.b default hides legacy D-01" "legacy decision" "$OUT"
OUT=$(node "$GOS" decision list --all 2>&1)
assert_contains "T2.c --all shows legacy D-01" "legacy decision" "$OUT"
assert_contains "T2.d --all shows superseded D-02" "superseded" "$OUT"

# ===== : park lifecycle (B not yet claimed) + milestone blocking hint =====
OUT=$(node "$GOS" phase park B --reason "waiting on deps" 2>&1)
assert_contains "T5.a park success names phase" "Phase parked: B-beta: second" "$OUT"
assert_contains "T5.b park warns milestone blocking" "parked blocks milestone completion" "$OUT"
OUT=$(node "$GOS" phase list 2>&1)
assert_contains "T5.c list renders parked(reason)" "parked(waiting on deps)" "$OUT"
OUT=$(node "$GOS" phase park B 2>&1)
assert_contains "T5.d re-park idempotent" "already parked" "$OUT"
OUT=$(node "$GOS" phase park B --undo 2>&1)
assert_contains "T5.e undo returns to pending" "un-parked (back to pending)" "$OUT"
OUT=$(node "$GOS" phase park B --undo 2>&1)
assert_contains "T5.f undo on pending idempotent" "nothing to un-park" "$OUT"
OUT=$(node "$GOS" phase park 99 2>&1); RC=$?
assert_exit "T5.g out-of-range park exits 1" 1 "$RC"
assert_contains "T5.h park range error maps queue" "valid range: 0-2" "$OUT"

# ===== claim A (entering Lv3 phase-owned state) =====
OUT=$(node "$GOS" phase claim A 2>&1)
assert_contains "T4.a claim first phase ok" "Phase claimed: A-alpha: first" "$OUT"

# ===== (post-claim): state-only shows this phase's decisions =====
node "$GOS" decision add "current phase decision" --rationale "t39" >/dev/null 2>&1
OUT=$(node "$GOS" decision list 2>&1)
assert_contains "T2.e default shows current decision" "current phase decision" "$OUT"
assert_not_contains "T2.f default still hides legacy D-01" "legacy decision" "$OUT"

# ===== : status/resume summary lines carry zero residuals =====
OUT=$(node "$GOS" status 2>&1)
assert_not_contains "T3.a status has no legacy requirement text" "legacy done-phase requirement" "$OUT"
assert_not_contains "T3.b status has no legacy decision title" "legacy decision" "$OUT"
OUT=$(node "$GOS" resume 2>&1)
assert_not_contains "T3.c resume has no legacy decision title" "legacy decision" "$OUT"

# ===== (part 1): residuals byte-identical after read-only ops =====
H1=$(t39_residual_hash)
[ "$H0" = "$H1" ] && { echo "  ✓ T11.a residuals byte-identical after read ops"; PASS=$((PASS+1)); } || { echo "  ✗ T11.a residuals mutated by read ops"; FAIL=$((FAIL+1)); }

OUT=$(node "$GOS" phase park A 2>&1); RC=$?
assert_exit "T8.a park on active refused" 1 "$RC"
assert_contains "T8.b refusal explains active" "refused — phase is active" "$OUT"

# ===== .a: orphan warning (park this phase while state is mid-flight) =====
node "$GOS" phase unclaim >/dev/null 2>&1
node -e "
const fs=require('fs');
const d=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
d.current_stage='BUILD';
fs.writeFileSync('.gos/state.json', JSON.stringify(d,null,2));
" >/dev/null 2>&1
OUT=$(node "$GOS" phase park A 2>&1)
assert_contains "T6.a park emits orphan warning for mid-flight state" "state.json still points at this phase" "$OUT"

# ===== : pending predecessor -> claim teaching error (DONE prerequisite) =====
t39_done_state
OUT=$(node "$GOS" phase claim C 2>&1); RC=$?
assert_exit "T4.b skipping pending predecessor exits 1" 1 "$RC"
assert_contains "T4.c teaching: gated on predecessor" "close it first (claim gated on predecessor)" "$OUT"
assert_contains "T4.d teaching: park guidance" "gos phase park 1" "$OUT"
assert_contains "T4.e teaching: cross-phase pointer" "gos requirement list --all" "$OUT"

# ===== .b: parked predecessor lets claim pass =====
node "$GOS" init --force 1 "t39 reset" >/dev/null 2>&1
OUT=$(node "$GOS" phase claim B 2>&1)
assert_contains "T6.b parked predecessor lets claim pass" "Phase claimed: B-beta: second" "$OUT"
assert_contains "T6.b2 claim output recommends a fresh session" "fresh session" "$OUT"
assert_contains "T6.b3 claim output carries the resume handoff" "gos resume" "$OUT"

# ===== : parked/done target allowlist =====
OUT=$(node "$GOS" phase park C 2>&1)
assert_contains "T7.a park pending C ok" "Phase parked: C-gamma: third" "$OUT"
OUT=$(node "$GOS" phase claim C 2>&1); RC=$?
assert_exit "T7.b claiming parked target exits 1" 1 "$RC"
assert_contains "T7.c parked target teaches --undo" "gos phase park 2 --undo" "$OUT"
OUT=$(node "$GOS" phase mark-done 2 2>&1)
assert_contains "T7.d mark-done parked prints explicit close-out" "parked → done (close-out)" "$OUT"
node "$GOS" phase park A --undo >/dev/null 2>&1
OUT=$(node "$GOS" phase claim C 2>&1); RC=$?
assert_exit "T7.e claiming done target exits 1" 1 "$RC"
assert_contains "T7.f done target redirects to next pending" "already done — next pending phase is index" "$OUT"
node "$GOS" phase park A --reason "defer" >/dev/null 2>&1

# ===== : ghost Fix teaching line (B's Lv3 state in hand) =====
cat > "$(gos_plan)" << 'EOF'
# Plan: t39 ghost fixture

## Execution Waves

### Wave 1

#### T1: ghost task
- **Covers**: D-99
- **Files**: fixture.txt
- **Done when**: never
EOF
node "$GOS" decision add "plan decision" --rationale "t39 ghost" >/dev/null 2>&1
OUT=$(node "$GOS" gate semantic 2>&1); RC=$?
assert_exit "T10.a ghost covers fail the gate" 1 "$RC"
assert_contains "T10.b ghost error carries Fix teaching" "Fix: align plan Covers with the state ID set" "$OUT"
assert_contains "T10.c teaching points to cross-phase audit" "cross-phase needs:" "$OUT"

# ===== .g: all-closed variant (A parked / B active / C done -> no pending) =====
t39_done_state
OUT=$(node "$GOS" phase claim C 2>&1)
assert_contains "T7.g all-closed variant mentions parked debt" "parked item(s) pending close-out" "$OUT"

# ===== : milestone debt visibility (archive BLOCKED block + doneHint parked line) =====
printf '# Changelog\n\n## [Unreleased]\n\n- Test t39 fixture ship gate (R-01) [%s]\n' "$(date -u +%F)" > CHANGELOG.md
node -e "
const fs=require('fs');
const d=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
d.current_stage='DONE'; delete d.completed_at; d.approvals={ARCHIVE:'2026-01-01T00:00:00Z'};
fs.writeFileSync('.gos/state.json', JSON.stringify(d,null,2));
" >/dev/null 2>&1
OUT=$(node "$GOS" archive 2>&1)
assert_contains "T9.a archive prints MILESTONE BLOCKED block" "MILESTONE BLOCKED" "$OUT"
OUT=$(node "$GOS" status 2>&1)
assert_contains "T9.b status(doneHint) lists parked phase" "parked phase: A-alpha: first" "$OUT"
assert_not_contains "T9.c no All-done lie while parked" "All roadmap phases done." "$OUT"
node "$GOS" phase mark-done 0 >/dev/null 2>&1
OUT=$(node "$GOS" status 2>&1)
assert_contains "T9.d All-done truth after close-out" "All roadmap phases done." "$OUT"

# ===== (part 2): residuals still byte-identical after full lifecycle =====
H2=$(t39_residual_hash)
[ "$H0" = "$H2" ] && { echo "  ✓ T11.e residuals byte-identical after full lifecycle"; PASS=$((PASS+1)); } || { echo "  ✗ T11.e residuals mutated by lifecycle ops"; FAIL=$((FAIL+1)); }

# ===== recheck: CONTRACTS nail strings exist (guards against bare-printf drift) =====
cat "$GOS" "$GOS_ROOT/bin/lib/core/state.cjs" | grep -q "parked blocks milestone completion" && { echo "  ✓ T12.a park-blocks nail in CONTRACTS"; PASS=$((PASS+1)); } || { echo "  ✗ T12.a nail missing"; FAIL=$((FAIL+1)); }
cat "$GOS" "$GOS_ROOT/bin/lib/core/state.cjs" | grep -q "MILESTONE BLOCKED — parked item(s) prevent milestone completion:" && { echo "  ✓ T12.b milestone-blocked nail"; PASS=$((PASS+1)); } || { echo "  ✗ T12.b nail missing"; FAIL=$((FAIL+1)); }
cat "$GOS" "$GOS_ROOT/bin/lib/core/state.cjs" | grep -q "parked → done (close-out)" && { echo "  ✓ T12.c close-out nail"; PASS=$((PASS+1)); } || { echo "  ✗ T12.c nail missing"; FAIL=$((FAIL+1)); }
cat "$GOS" "$GOS_ROOT/bin/lib/core/state.cjs" | grep -q "Fix: align plan Covers with the state ID set" && { echo "  ✓ T12.d ghost-fix nail"; PASS=$((PASS+1)); } || { echo "  ✗ T12.d nail missing"; FAIL=$((FAIL+1)); }

t39_teardown

# ===== MAJ-1 regression: plain task without project.json — --all does not lie / dual-absent dies =====
P2_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t39b"
mkdir -p "$P2_DIR" && cd "$P2_DIR" || exit 1
git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m root
node "$GOS" init 1 "plain no-project task" >/dev/null 2>&1
OUT=$(node "$GOS" requirement list --all 2>&1)
assert_not_contains "M1.a no-project --all does not claim project.json exists" "project.json exists but" "$OUT"
OUT=$(node "$GOS" decision list --all 2>&1)
assert_not_contains "M1.b decision side same" "project.json exists but" "$OUT"
cd "$TESTBASE" && rm -rf "$P2_DIR"
D2_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t39c"
mkdir -p "$D2_DIR" && cd "$D2_DIR" || exit 1
git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m root
OUT=$(node "$GOS" requirement list --all 2>&1); RC=$?
assert_exit "M1.c no state no project exits 1" 1 "$RC"
# Message branches by environment: outside a repo = 'no state and no project.json'; inside the runner TESTBASE (repo root found upward) = 'no GOS task'
assert_contains "M1.d dual-absent emits an error" "✗" "$OUT"
cd "$TESTBASE" && rm -rf "$D2_DIR"

echo "--- T39 done: PASS=$PASS FAIL=$FAIL ---"
[ "$FAIL" -eq 0 ] || exit 1
