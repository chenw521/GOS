#!/usr/bin/env bash
# gos-map:fn bin/lib/task/archive.cjs#fn:cmdArchive bin/lib/knowledge/milestone.cjs#fn:closeMilestone
# gos-map:cmd archive,milestone
# milestone ceremony end-to-end on a seeded container — phase tasks archive
# under the open milestone (task_ref stamps), the close carries parked and
# pending entries byte-equal with dual-channel snapshots, the closing record
# homes in the last done task's archive dir when one exists and in a
# synthesized dated close dir when phases closed via mark-done, and the next
# cycle opens over the carried queue.
PASS=0; FAIL=0
command -v assert_exit >/dev/null || assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected exit $expected, got '${actual:-<none>}')"; FAIL=$((FAIL+1)); fi
}
command -v assert_contains >/dev/null || assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected: '$expected')"; echo "    actual: ${actual:0:240}"; FAIL=$((FAIL+1)); fi
}
command -v assert_file >/dev/null || assert_file() {
  local label="$1" fpath="$2"
  if [ -n "$fpath" ] && [ -e "$fpath" ]; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (missing: '${fpath:-<none>}')"; FAIL=$((FAIL+1)); fi
}
command -v assert_eq >/dev/null || assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected: '$expected', got: '$actual')"; FAIL=$((FAIL+1)); fi
}
GOS="${GOS:-$(git rev-parse --show-toplevel 2>/dev/null)/bin/gos.cjs}"
T118_DIR=""
UDATE="$(date -u +%F)"

t118_setup() {
  [ -n "$TESTBASE" ] || TESTBASE="$(mktemp -d)"
  T118_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t118"
  mkdir -p "$T118_DIR" && cd "$T118_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/.lock\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
  export GOS_SKIP_SHIP_CHECK=1
}

t118_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T118_DIR"; }

# Claim the next pending phase and run it through the archive pipeline with
# the minimal in-flight shape (DONE + spec + approval + lessons entry).
t118_run_phase() {
  node "$GOS" phase claim "$1" >/dev/null 2>&1
  local tok="$2"
  node -e "
const fs = require('fs');
const s = JSON.parse(fs.readFileSync('.gos/state.json', 'utf8'));
s.current_stage = 'DONE';
s.approvals = { ARCHIVE: 'ok' };
s.spec_path = '.gos/task/$tok/spec.md';
fs.writeFileSync('.gos/state.json', JSON.stringify(s, null, 2));"
  mkdir -p ".gos/task/$tok" && echo "spec $tok" > ".gos/task/$tok/spec.md"
  mkdir -p .gos && echo "- [$(date -u +%F)] ceremony $tok → ceremony lesson" >> .gos/lessons.md
  node "$GOS" archive >/dev/null 2>&1
}

echo "--- T118: milestone ceremony end-to-end ---"

# ===== leg 1: two archived tasks + carried debt, close under approval =====
t118_setup
node "$GOS" init --project --project=cycle-one >/dev/null 2>&1
node "$GOS" phase add "P1: first" --goal "goal first" >/dev/null 2>&1
node "$GOS" phase add "P2: second" --goal "goal second" >/dev/null 2>&1
node "$GOS" phase add "P3: parked debt" --goal "goal parked" >/dev/null 2>&1
node "$GOS" phase add "P4: pending tail" --goal "goal tail" >/dev/null 2>&1
node "$GOS" requirement add "parked-owned requirement" --phase "P3: parked debt" >/dev/null 2>&1
node "$GOS" requirement add "pending-owned requirement" --phase "P4: pending tail" >/dev/null 2>&1

t118_run_phase 0 p1
t118_run_phase 1 p2
STAMPS=$(node -e "
const p = require('./.gos/project/project.json');
console.log(p.phases.slice(0, 2).map((ph) => [ph.status, ph.task_ref === undefined ? 'no-ref' : ph.task_ref, typeof ph.completed_at === 'string' ? 'iso' : 'bad'].join('~')).join('|'))")
assert_eq "both archived phases stamped (done~task_ref~iso each)" \
  "done~$UDATE-cycle-one-phase-p1-goal-first~iso|done~$UDATE-cycle-one-phase-p2-goal-second~iso" "$STAMPS"
assert_file "first task archive home exists" ".gos/archive/$UDATE-cycle-one-phase-p1-goal-first"
assert_file "second task archive home exists" ".gos/archive/$UDATE-cycle-one-phase-p2-goal-second"

node "$GOS" phase park 2 --reason "deferred to the next cycle" >/dev/null 2>&1
node "$GOS" render >/dev/null 2>&1
cp .gos/project/project.json ceremony-pre.json
node "$GOS" init 3 "ceremony approval holder" >/dev/null 2>&1
node "$GOS" approve milestone-close >/dev/null 2>&1
set +e; OUT=$(node "$GOS" milestone close --carry-parked --yes 2>&1); RC=$?; set -e
assert_exit "ceremony close exits 0" 0 "$RC"
assert_contains "closing record homes in the last done task's archive dir" "$UDATE-cycle-one-phase-p2-goal-second/milestone-record" "$OUT"

CARRIED=$(node -e "
const pre = require('./ceremony-pre.json');
const post = require('./.gos/project/project.json');
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const prePh = pre.phases.filter((x) => x.status !== 'done');
const postPhIds = new Set(post.phases.map((x) => x.name));
const carriedPh = prePh.filter((x) => postPhIds.has(x.name));
const postReqIds = new Set(post.requirements.map((r) => r.id));
const carriedReq = pre.requirements.filter((r) => postReqIds.has(r.id));
console.log([eq(carriedPh, post.phases), eq(carriedReq, post.requirements), post.phases.map((x) => x.status).join(','), JSON.stringify(post.last_archived_phase), 'closed_at' in post.milestone].join('|'))")
assert_eq "carried phases + rows byte-equal to their preclose entries, last_archived null, closed_at stamped" \
  "true|true|parked,pending|null|true" "$CARRIED"
CLOSE_DATE="$UDATE"
assert_file "preclose snapshot under the project channel" ".gos/project/milestones/cycle-one-$CLOSE_DATE-preclose.json"
assert_file "view snapshot under the task home record" ".gos/archive/$UDATE-cycle-one-phase-p2-goal-second/milestone-record/cycle-one-$CLOSE_DATE-ROADMAP.md"
if cmp -s ".gos/project/milestones/cycle-one-$CLOSE_DATE-preclose.json" ceremony-pre.json; then
  echo "  ✓ preclose.json is the byte-equal pre-close copy"; PASS=$((PASS+1))
else
  echo "  ✗ preclose snapshot drifted"; FAIL=$((FAIL+1))
fi

# ===== next cycle opens over the carried queue =====
set +e; OUT=$(node "$GOS" milestone open 'v1-followup' 2>&1); RC=$?; set -e
assert_exit "next cycle opens" 0 "$RC"
NEXT=$(node -e "
const p = require('./.gos/project/project.json');
console.log([p.milestone.name, 'closed_at' in p.milestone, p.phases.map((x) => x.name + ':' + x.status).join(','), p.requirements.map((r) => r.id).join(',')].join('|'))")
assert_eq "carried queue and rows survive into the next cycle" \
  "v1-followup|false|P3: parked debt:parked,P4: pending tail:pending|R-02,R-03" "$NEXT"
REQS=$(node "$GOS" requirement list --all 2>&1)
assert_contains "carried rows visible in the merged audit view" "pending-owned requirement" "$REQS"
t118_teardown

# ===== leg 2: all-mark-done ceremony — the record homes in a synthesized close dir =====
t118_setup
node "$GOS" init --project --project=backfill >/dev/null 2>&1
node "$GOS" phase add "B1: retro one" --goal g1 >/dev/null 2>&1
node "$GOS" phase add "B2: retro two" --goal g2 >/dev/null 2>&1
node "$GOS" phase add "B3: retro three" --goal g3 >/dev/null 2>&1
set +e; OUT=$(node "$GOS" phase mark-done 0 2>&1); RC=$?; set -e
assert_exit "mark-done on a never-claimed phase exits 0" 0 "$RC"
node "$GOS" phase mark-done 1 >/dev/null 2>&1
node "$GOS" phase mark-done 2 >/dev/null 2>&1
MD=$(node -e "
const p = require('./.gos/project/project.json');
const ph = p.phases[0];
console.log([ph.status, typeof ph.completed_at === 'string' ? 'iso' : 'bad', 'task_ref' in ph].join('|'))")
assert_eq "mark-done stamps completed_at, never a task_ref" "done|iso|false" "$MD"
node "$GOS" render >/dev/null 2>&1
node "$GOS" init 3 "backfill holder" >/dev/null 2>&1
node "$GOS" approve milestone-close >/dev/null 2>&1
set +e; OUT=$(node "$GOS" milestone close --yes 2>&1); RC=$?; set -e
assert_exit "all-mark-done close exits 0" 0 "$RC"
assert_file "closing record synthesized into a dated close dir" ".gos/archive/$UDATE-backfill-close/milestone-record"
WIPED=$(node -e "
const p = require('./.gos/project/project.json');
console.log([p.phases.length, p.decisions.length, p.requirements.length, JSON.stringify(p.last_archived_phase)].join('|'))")
assert_eq "history wiped with the milestone (no carried debt this time)" "0|0|0|null" "$WIPED"
if ls -d .gos/archive/$UDATE-v*-phase-* >/dev/null 2>&1 || ls -d .gos/archive/$UDATE-backfill-phase-* >/dev/null 2>&1; then
  echo "  ✗ mark-done-only ceremony created phase task homes"; FAIL=$((FAIL+1))
else
  echo "  ✓ no phase task homes exist (mark-done never archives)"; PASS=$((PASS+1))
fi
t118_teardown

echo "--- T118 done: PASS=$PASS FAIL=$FAIL ---"
[ "$FAIL" -eq 0 ] || exit 1
