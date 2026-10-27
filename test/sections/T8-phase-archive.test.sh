#!/usr/bin/env bash
# gos-map:cmd phase
# : phase command family (add/list/claim/unclaim) + archive integration
# (idempotency / dest conflict / merge / milestone / anchor rewrite)
# Env: GOS (CLI path), TESTBASE (repo root for sandbox), + assert helpers sourced by runner
T8_DIR=""

# Fixture paths follow the CLI supply (task/<id>/) — never hardcode the .gos/ root
gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }
gos_plan() { node "$GOS" context plan 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["plan"])' 2>/dev/null; }

t8_setup() {
  T8_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t8"
  mkdir -p "$T8_DIR" && cd "$T8_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/.lock\n" > .gitignore && git add .gitignore && git commit -q -m gi
  export GOS_SKIP_SHIP_CHECK=1   # T12 SHIP gate (CHANGELOG.md ritual) — unit-tested in T12/T57, not here
}

t8_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T8_DIR"; }

# fixed-string assert (table rows contain '|', unsafe as assert_contains regex)
assert_contains_f() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then
    echo "  ✓ $label"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected fixed: '$expected')"
    echo "    actual: ${actual:0:160}"
    FAIL=$((FAIL+1))
  fi
}

t8_setup
echo "--- T8: phase family + archive integration ---"

node "$GOS" init 4 "plat" --project >/dev/null 2>&1

# --- .1: phase add recreates missing project.json + brownfield warning (same strings as init --project)
rm .gos/project/project.json
printf '| D-99 | legacy call |\n' >> .gos/project/DECISIONS.md
set +e; OUT=$(node "$GOS" phase add "P1: core" --goal "ship g1" 2>&1); RC=$?; set -e
assert_exit "add P1 exits 0" 0 "$RC"
assert_contains "add output contract" "✓ Phase added: P1: core" "$OUT"
assert_contains "fresh creation warns brownfield" "existing handwritten content detected" "$OUT"
assert_file "project.json recreated" ".gos/project/project.json"
P1CNT=$(python3 -c "import json; print(len(json.load(open('.gos/project/project.json'))['phases']))")
assert_eq "recreated project.json holds the phase" "1" "$P1CNT"

node "$GOS" phase add "P2: extra" --goal "ship g1" >/dev/null 2>&1
node "$GOS" phase add "P3: more" --goal "ship tail" >/dev/null 2>&1

# --- .3: phase list shows all pending
set +e; OUT=$(node "$GOS" phase list 2>&1); RC=$?; set -e
assert_exit "list exits 0" 0 "$RC"
assert_contains_f "list header" "| Phase | Goal | Status |" "$OUT"
assert_contains_f "P1 row pending" "| P1: core | ship g1 | pending |" "$OUT"
assert_contains_f "P2 row pending" "| P2: extra | ship g1 | pending |" "$OUT"
assert_contains_f "P3 row pending" "| P3: more | ship tail | pending |" "$OUT"

set +e; OUT=$(node "$GOS" phase add "P1: core" --goal "dup" 2>&1); RC=$?; set -e
assert_exit "duplicate name exits 1" 1 "$RC"
assert_contains "duplicate message" "phase name already exists" "$OUT"

# --- .5: claim blocked while task mid-flight (BUILD stage)
python3 -c "
import json; s=json.load(open('.gos/state.json')); s['current_stage']='BUILD'
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" phase claim 0 2>&1); RC=$?; set -e
assert_exit "claim blocked at BUILD stage" 1 "$RC"
assert_contains "blocked message names wrapper state" "wrapper state is at BUILD" "$OUT"

# --- .6: --force bypasses preconditions with LOUD warning
set +e; OUT=$(node "$GOS" phase claim 0 --force 2>&1); RC=$?; set -e
assert_exit "force-claim exits 0" 0 "$RC"
assert_contains "loud force warning" "FORCE-CLAIM bypasses DONE/archive preconditions" "$OUT"
assert_contains "force claim success" "✓ Phase claimed: P1: core" "$OUT"
ST=$(python3 -c "import json; print(json.load(open('.gos/project/project.json'))['phases'][0]['status'])")
assert_eq "phases[0] active after force-claim" "active" "$ST"

# --- .7: unclaim reverts active phase to pending
set +e; OUT=$(node "$GOS" phase unclaim 2>&1); RC=$?; set -e
assert_exit "unclaim exits 0" 0 "$RC"
assert_contains "unclaim message" "✓ Phase P1: core unclaimed — state now orphaned; re-claim or gos init to replace" "$OUT"
ST=$(python3 -c "import json; print(json.load(open('.gos/project/project.json'))['phases'][0]['status'])")
assert_eq "phases[0] pending after unclaim" "pending" "$ST"

# --- .8: claim 1 without P1 archived → archive-evidence failure
# Claim gate error text is teaching-form: names the gated-predecessor rule and the park escape hatch
python3 -c "
import json; s=json.load(open('.gos/state.json')); s['current_stage']='DONE'
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" phase claim 1 2>&1); RC=$?; set -e
assert_exit "claim 1 blocked: P1 not archived" 1 "$RC"
assert_contains "gated-predecessor message" "close it first (claim gated on predecessor)" "$OUT"
assert_contains "park guidance in gate error" "gos phase park 0" "$OUT"

# --- .9: claim 0 success — fresh state written FIRST, then phase active
set +e; OUT=$(node "$GOS" phase claim 0 2>&1); RC=$?; set -e
assert_exit "claim 0 exits 0" 0 "$RC"
assert_contains "claim success line" "✓ Phase claimed: P1: core" "$OUT"
assert_contains "claim next hint" "Next: THINK (intent = phase goal)" "$OUT"
FRESH=$(python3 -c "
import json
s=json.load(open('.gos/state.json')); p=json.load(open('.gos/project/project.json'))
print('|'.join([s['intent']['summary'], s['phase_name'], str(s['project']), s['current_stage'], str(s['intent']['confirmed']), str(s['level']), s['requirements'][0]['text'], p['phases'][0]['status']]))")
assert_eq "fresh state + active phase (goal|phase|project|stage|confirmed|level|R-01|status)" \
  "ship g1|P1: core|True|INTENT|True|3|ship g1|active" "$FRESH"

# --- .10: re-claim active phase rejected
set +e; OUT=$(node "$GOS" phase claim 0 2>&1); RC=$?; set -e
assert_exit "re-claim exits 1" 1 "$RC"
assert_contains "already-active message" "phase already active" "$OUT"

# --- .11: full cycle → archive merges into project.json + renders views + rewrites anchor
mkdir -p test/out && echo "412 passed, 0 failed" > test/out/t8.log
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='DONE'
s['decisions']=[{'id':'D-01','title':'Use atomic writes','covered':True,'status':'covered','anchor':'spec.md#d-01'}]
s['observable_truths']=[{'id':'T-01','description':'y','verified':True,'evidence':{'command':'bash test/run-sections.sh','output_excerpt':'412 passed, 0 failed','artifact_path':'test/out/t8.log'}}]
s['approvals']={'ARCHIVE':'x'}
s['spec_path']='"$(gos_spec)"'
json.dump(s,open('.gos/state.json','w'),indent=2)"
echo spec > "$(gos_spec)"
mkdir -p .gos && echo "- [$(date -u +%F)] scene → lesson" >> .gos/lessons.md
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "archive exits 0" 0 "$RC"
assert_contains "render line contract" "✓ rendered views (DECISIONS/ROADMAP/REQUIREMENTS)" "$OUT"
MERGED=$(python3 -c "
import json
p=json.load(open('.gos/project/project.json'))
d=[x for x in p['decisions'] if x['id']=='D-01'][0]
print('|'.join([str(len(p['decisions'])), p['phases'][0]['status'], str(p['last_archived_phase']), d['birth_phase'], str(d['anchor'].startswith('.gos/archive/')), str(d['anchor'].endswith('/spec.md#d-01'))]))")
assert_eq "merge: D-01 in + phase done + last_archived + birth_phase + anchor rewritten" \
  "1|done|P1: core|P1: core|True|True" "$MERGED"
assert_file "DECISIONS.md rendered" ".gos/project/DECISIONS.md"
assert_eq "DECISIONS.md line 1 GENERATED header" "<!-- GENERATED by gos — edit via gos decision/requirement/phase commands, not this file -->" "$(head -n 1 .gos/project/DECISIONS.md)"
assert_contains "D-01 row present" "| D-01 |" "$(cat .gos/project/DECISIONS.md)"

set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "re-archive exits 0" 0 "$RC"
assert_contains "idempotent message" "✓ already archived — nothing to do" "$OUT"

# --- .13: claim 1 now allowed (P1 archived)
set +e; OUT=$(node "$GOS" phase claim 1 2>&1); RC=$?; set -e
assert_exit "claim 1 exits 0" 0 "$RC"
CL1=$(python3 -c "
import json
s=json.load(open('.gos/state.json')); p=json.load(open('.gos/project/project.json'))
print('|'.join([s['phase_name'], s['intent']['summary'], p['phases'][1]['status']]))")
assert_eq "P2 claimed (phase_name|intent|status)" "P2: extra|ship g1|active" "$CL1"

# --- .14: same-day same-slug archive → dest gets -2 suffix
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='DONE'
s['decisions']=[{'id':'D-02','title':'Second decision','covered':True,'status':'covered'}]
s['approvals']={'ARCHIVE':'x'}
s['spec_path']='"$(gos_spec)"'
json.dump(s,open('.gos/state.json','w'),indent=2)"
echo spec2 > "$(gos_spec)"
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "second archive exits 0" 0 "$RC"
UDATE=$(python3 -c "import datetime; print(datetime.datetime.utcnow().date().isoformat())")
VER=$(node -e "console.log(require(process.env.GOS_ROOT+'/package.json').version)")
assert_file "P1 archive dir (phase token p1)" ".gos/archive/$UDATE-v$VER-phase-p1-ship-g1"
assert_file "P2 archive dir (phase token p2)" ".gos/archive/$UDATE-v$VER-phase-p2-ship-g1"
# structured-slug collision: reset completed_at on the SAME P2 state → re-archive → -2 suffix
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['completed_at']=None
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "third same-slug archive exits 0" 0 "$RC"
assert_file "collision dest got -2 suffix" ".gos/archive/$UDATE-v$VER-phase-p2-ship-g1-2"
NSLUG=$(ls -d .gos/archive/$UDATE-v$VER-phase-p2-ship-g1* 2>/dev/null | wc -l | tr -d ' ')
assert_eq "exactly two same-slug dirs" "2" "$NSLUG"
P2DONE=$(python3 -c "
import json; p=json.load(open('.gos/project/project.json'))
print('|'.join([p['phases'][1]['status'], str(p['last_archived_phase']), str(len(p['decisions']))]))")
assert_eq "P2 done + last_archived + D-02 merged (no milestone: P3 pending)" "done|P2: extra|2" "$P2DONE"

# --- .15: milestone — all phases done → final render + blank project.json + milestone-record/
python3 -c "
import json
s=json.load(open('.gos/state.json'))
s['intent']['summary']='milestone tail task'
s['current_stage']='DONE'
s['phase_name']='P3: more'
s['decisions']=[{'id':'D-03','title':'Third decision','covered':True,'status':'covered'}]
s['approvals']={'ARCHIVE':'x'}
s['spec_path']='"$(gos_spec)"'
json.dump(s,open('.gos/state.json','w'),indent=2)
p=json.load(open('.gos/project/project.json'))
for ph in p['phases']: ph['status']='done'
p['last_archived_phase']='P3: more'
json.dump(p,open('.gos/project/project.json','w'),indent=2)"
echo spec3 > "$(gos_spec)"
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "milestone archive exits 0" 0 "$RC"
assert_contains "milestone message" "✓ milestone complete — project.json reset for next milestone" "$OUT"
BLANK=$(python3 -c "
import json; p=json.load(open('.gos/project/project.json'))
print('|'.join([str(p['schema_version']), str(p['last_archived_phase']), str(len(p['phases'])), str(len(p['decisions'])), str(len(p['requirements']))]))")
assert_eq "project.json reset to empty shape" "1|None|0|0|0" "$BLANK"
assert_file "milestone-record snapshot" ".gos/archive/$UDATE-v$VER-phase-p3-milestone-tail-task/milestone-record/DECISIONS.md"

# --- .16-18: non-Lv4 guards + no-project render skip
t8_teardown; t8_setup
node "$GOS" init 3 "plain task" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" phase add "P1: x" --goal "g" 2>&1); RC=$?; set -e
assert_exit "phase add without project exits 1" 1 "$RC"
assert_contains "requires-Lv4 message" "phase add requires an Lv4 project (gos init --project)" "$OUT"
OUT=$(node "$GOS" phase list 2>&1)
assert_contains "empty list hint" "(no phases — gos phase add)" "$OUT"
mkdir -p test/out && echo "300 passed, 0 failed" > test/out/t8.log
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='DONE'
s['decisions']=[{'id':'D-01','title':'x','covered':True,'status':'covered'}]
s['observable_truths']=[{'id':'T-01','description':'y','verified':True,'evidence':{'command':'bash test/run-sections.sh','output_excerpt':'300 passed, 0 failed','artifact_path':'test/out/t8.log'}}]
s['approvals']={'ARCHIVE':'x'}
s['spec_path']='"$(gos_spec)"'
json.dump(s,open('.gos/state.json','w'),indent=2)"
echo spec > "$(gos_spec)"
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "archive without project.json exits 0" 0 "$RC"
assert_contains "render-skip message" "(no project.json — render skipped)" "$OUT"

# --- .8: claim precondition semantics — wrapper vs phase-owned state (2026-08-24 fix)
t8_teardown; t8_setup
node "$GOS" init 4 "plat" --project >/dev/null 2>&1
node "$GOS" phase add "P1: first" --goal "g1" >/dev/null 2>&1
node "$GOS" phase add "P2: second" --goal "g2" >/dev/null 2>&1
# wrapper (project=true, no phase_name) at INTENT → first claim allowed, NO --force, NO warning
set +e; OUT=$(node "$GOS" phase claim 0 2>&1); RC=$?; set -e
assert_exit "wrapper first claim allowed without --force" 0 "$RC"
if echo "$OUT" | grep -q "FORCE-CLAIM"; then
  echo "  ✗ wrapper claim must not print force warning"; FAIL=$((FAIL+1))
else
  echo "  ✓ wrapper claim clean (no force warning)"; PASS=$((PASS+1))
fi
PN=$(python3 -c "import json; print(json.load(open('.gos/state.json')).get('phase_name'))")
assert_eq "claimed state is phase-owned (phase_name set)" "P1: first" "$PN"
# phase-owned mid-flight claim of next phase → blocked (the real data-loss guard)
node "$GOS" phase add "P3: third" --goal "g3" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" phase claim 1 2>&1); RC=$?; set -e
assert_exit "phase-owned mid-flight claim blocked" 1 "$RC"
# evidence predicate still enforced for wrapper claims (unarchived predecessor)
t8_teardown; t8_setup
node "$GOS" init 4 "plat" --project >/dev/null 2>&1
node "$GOS" phase add "PA: one" --goal "a" >/dev/null 2>&1
node "$GOS" phase add "PB: two" --goal "b" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" phase claim 1 2>&1); RC=$?; set -e
assert_exit "wrapper claim of P2 blocked (P1 unarchived)" 1 "$RC"
# wrapper stuck mid-stages (not INTENT, no phase_name) → blocked with wrapper hint
python3 -c "
import json; s=json.load(open('.gos/state.json')); s['current_stage']='BUILD'
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" phase claim 0 2>&1); RC=$?; set -e
assert_exit "wrapper at BUILD blocked" 1 "$RC"
assert_contains "wrapper hint present" "wrapper" "$OUT"

t8_teardown
