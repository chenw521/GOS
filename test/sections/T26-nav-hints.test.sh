#!/usr/bin/env bash
# gos-map:cmd status,next
# next/status archived-state navigation + pending phase hints + snapshot coverage
#      computation + commit handoff block + phase mark-done + auto-loop hints
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner
T26_DIR=""

t26_setup() {
  T26_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t26"
  mkdir -p "$T26_DIR" && cd "$T26_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  echo ".gos/state.json" > .gitignore && git add .gitignore && git commit -q -m gi
}

t26_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T26_DIR"; }

# Fixture: phased DONE + archived state — project.json with 3 phases (2 done + 1 pending), state completed_at set
t26_archived_fixture() {
  node "$GOS" init --project 4 "batch" --force >/dev/null 2>&1
  node "$GOS" phase add "P1: alpha" --goal "ga" >/dev/null 2>&1
  node "$GOS" phase add "P2: beta" --goal "gb" >/dev/null 2>&1
  node "$GOS" phase add "R: final" --goal "gr" >/dev/null 2>&1
  python3 - <<'PYEOF'
import json
p = json.load(open('.gos/project/project.json'))
p['phases'][0]['status'] = 'done'
p['phases'][1]['status'] = 'done'
p['last_archived_phase'] = 'P2: beta'
json.dump(p, open('.gos/project/project.json','w'), indent=2)
s = json.load(open('.gos/state.json'))
s['phase_name'] = 'P2: beta'
s['current_stage'] = 'DONE'
s['completed_at'] = '2026-08-25T00:00:00.000Z'
s['completed_stages'] = ['INTENT','THINK','PLAN','BUILD','REVIEW','VERIFY']
s['plan_snapshot'] = {'tasks': [{'id':'T1','covers':['D-01','D-02'],'files':['src/a.js']}]}
s['decisions'] = [{'id':'D-01','title':'a','covered':False},{'id':'D-02','title':'b','covered':False}]
json.dump(s, open('.gos/state.json','w'), indent=2)
PYEOF
}

t26_setup
echo "--- T26: archived-state navigation + handoff + mark-done ---"

# --- .1: archived DONE → next drops the archive hint, shows Task archived + pending claim
t26_archived_fixture
set +e; OUT=$(node "$GOS" next 2>&1); RC=$?; set -e
assert_exit "next at archived DONE exits 0" 0 "$RC"
if echo "$OUT" | grep -q "archive if not yet archived"; then
  echo "  ✗ stale archive hint still shown at archived DONE"; FAIL=$((FAIL+1))
else echo "  ✓ no stale archive hint"; PASS=$((PASS+1)); fi
assert_contains "archived acknowledgment" "archived" "$OUT"
assert_contains "pending phase claim hint (index derived from project.json)" "pending phase: R: final → \`gos phase claim 2\`" "$OUT"

# --- .2: same state via bare `gos` (no-arg status) — identical Next tail
set +e; OUT=$(node "$GOS" 2>&1); RC=$?; set -e
assert_exit "bare status exits 0" 0 "$RC"
assert_contains "status Next tail shows pending claim" "gos phase claim 2" "$OUT"
if echo "$OUT" | grep -q "archive if not yet archived"; then
  echo "  ✗ status stale archive hint"; FAIL=$((FAIL+1))
else echo "  ✓ status clean"; PASS=$((PASS+1)); fi

# --- .3: unarchived DONE (completed_at empty) → archive hint retained
t26_teardown; t26_setup
node "$GOS" init 2 "plain task" >/dev/null 2>&1
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='DONE'; s['completed_at']=None
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" next 2>&1); RC=$?; set -e
assert_exit "next at unarchived DONE exits 0" 0 "$RC"
# unarchived DONE splits by approval gate: unapproved → user-gate hint
assert_contains "unarchived DONE shows user approval gate" "awaiting YOUR approval" "$OUT"

# --- .4: status decision coverage lines — computed from plan_snapshot when plan.md absent + archived annotation
t26_teardown; t26_setup
t26_archived_fixture
set +e; OUT=$(node "$GOS" status 2>&1); RC=$?; set -e
assert_exit "status exits 0" 0 "$RC"
if echo "$OUT" | grep -q "Decisions: 0/2"; then
  echo "  ✗ misleading 0/2 covered line at archived DONE"; FAIL=$((FAIL+1))
else echo "  ✓ no misleading 0/N line"; PASS=$((PASS+1)); fi
assert_contains "coverage computed from frozen snapshot, archived-annotated" "2/2" "$OUT"
assert_contains "archived annotation present" "(archived)" "$OUT"

# --- .5: commit stage handoff block — resume + skill + instructions (Lv3 → THINK)
t26_teardown; t26_setup
node "$GOS" init 3 "handoff task" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" commit intent 2>&1); RC=$?; set -e
assert_exit "commit intent exits 0" 0 "$RC"
assert_contains "handoff block: resume paste line" "gos resume" "$OUT"
assert_contains "handoff block: next skill named" "gos-think" "$OUT"
assert_contains "handoff block: first command" "gos instructions think" "$OUT"
# same tail as next
set +e; OUT=$(node "$GOS" next 2>&1); set -e
assert_contains "next tail has handoff block" "gos resume" "$OUT"

# --- .6: phase mark-done — pending→done; active rejected; out-of-range rejected
t26_teardown; t26_setup
node "$GOS" init --project 4 "batch2" --force >/dev/null 2>&1
node "$GOS" phase add "X1: one" --goal "g1" >/dev/null 2>&1
node "$GOS" phase add "X2: two" --goal "g2" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" phase mark-done 0 2>&1); RC=$?; set -e
assert_exit "mark-done pending phase exits 0" 0 "$RC"
LIST=$(node "$GOS" phase list 2>&1)
assert_contains "phase 0 now done" "done" "$LIST"
set +e; OUT=$(node "$GOS" phase mark-done 0 2>&1); RC=$?; set -e
assert_exit "mark-done on already-done exits 0 (idempotent)" 0 "$RC"
set +e; OUT=$(node "$GOS" phase mark-done 9 2>&1); RC=$?; set -e
assert_exit "mark-done out of range exits 1" 1 "$RC"
# active rejection: reach the active state via claim (mark-done also syncs the last_archived pointer,
# so it is patched by hand here — legacy-fixture compatibility only, the new gate no longer
# consumes it; claim-1 validity is guaranteed by phases[0].status==='done')
# a done phase cannot be claimed again (claim targets are whitelisted) — build the active state from pending X2
python3 -c "
import json; p=json.load(open('.gos/project/project.json')); p['last_archived_phase']='X1: one'
json.dump(p,open('.gos/project/project.json','w'),indent=2)"
node "$GOS" phase claim 1 >/dev/null 2>&1
set +e; OUT=$(node "$GOS" phase mark-done 1 2>&1); RC=$?; set -e
assert_exit "mark-done on ACTIVE phase exits 1 (no pipeline bypass)" 1 "$RC"
assert_contains "active refusal explains full-pipeline path" "finish and archive" "$OUT"

# --- .7-.10: nav auto-aware hints (task facade wiring) — marker env, mode-on
# outside a marker session, no-store silence, allowlist direction. Hint cases
# pin HOME+XDG_DATA_HOME per case so machine-local stores never leak in and
# the no-store assertion stays local to the case world.
t26_hintcase() {
  T26_CASE="$T26_DIR/$1"
  mkdir -p "$T26_CASE/home" "$T26_CASE/xdg" "$T26_CASE/repo"
  export HOME="$T26_CASE/home"
  export XDG_DATA_HOME="$T26_CASE/xdg"
  cd "$T26_CASE/repo" || exit 1
  git init -q -b work . && git commit -q --allow-empty -m root
}

# .7 marker env: the hint names the tracked artifact, the advance verb and the
# human-gate refusal
t26_hintcase hints-marker
node "$GOS" init 1 "nav hints marker" >/dev/null 2>&1
set +e; OUT=$(GOS_AUTO_SPAWNED=1 GOS_AUTO_SPAWN_ID=t19-nav node "$GOS" status 2>&1); RC=$?; set -e
assert_exit "marker-env status exits 0" 0 "$RC"
assert_contains "marker hint names the tracked artifact" ".gos/state.json" "$OUT"
assert_contains "marker hint names the advance verb" "gos commit" "$OUT"
assert_contains "marker hint names the human-gate refusal" "human gates" "$OUT"

# .8 mode-on outside a marker session: the hint names the loop state (status and next)
t26_hintcase hints-mode-on
node "$GOS" init 1 "nav hints mode" >/dev/null 2>&1
node "$GOS" auto on >/dev/null 2>&1
set +e; OUT=$(node "$GOS" status 2>&1); RC=$?; set -e
assert_exit "mode-on outside: status exits 0" 0 "$RC"
assert_contains "mode-on hint names the loop state" "auto mode on" "$OUT"
assert_contains "mode-on hint carries the profile" "profile restricted" "$OUT"
set +e; NOUT=$(node "$GOS" next 2>&1); RC=$?; set -e
assert_exit "mode-on outside: next exits 0" 0 "$RC"
assert_contains "next tail carries the same loop-state hint" "auto mode on" "$NOUT"

# .9 no store: silence — no new hint lines, and the store dir is never created
t26_hintcase hints-none
node "$GOS" init 1 "nav hints none" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" status 2>&1); RC=$?; set -e
assert_exit "no-store status exits 0" 0 "$RC"
if echo "$OUT" | grep -q "auto loop session\|auto mode on"; then
  echo "  ✗ no-store status printed auto hint lines"; FAIL=$((FAIL+1))
else echo "  ✓ no-store status prints no auto hint lines"; PASS=$((PASS+1)); fi
if [ -e "$XDG_DATA_HOME/gos" ]; then
  echo "  ✗ status run created a store dir (read-only invariant broken)"; FAIL=$((FAIL+1))
else echo "  ✓ status run created no store dir"; PASS=$((PASS+1)); fi

# .10 allowlist: the direction covering the task→ops/auto require is present
# and carries the new edge (longest-match module root, the same resolution
# the gate applies)
T26_ALW="$(node -e '
const fs = require("fs");
const path = require("path");
const doc = JSON.parse(fs.readFileSync(path.join(process.env.GOS_ROOT, ".gos/codebase/require-allowlist.json"), "utf8"));
const target = "bin/lib/ops/auto/cli.cjs";
const root = [...doc.moduleRoots].sort((a, b) => b.length - a.length).find((r) => target.startsWith(r + "/"));
const dir = (doc.directions || []).find((d) => d.from === "bin/lib/task" && d.to === root);
console.log(`${root}|${dir && dir.edges >= 9 ? "carries-edge" : dir ? "stale-count" : "absent"}`);
')"
assert_eq "task→ops/auto covered by a registered direction carrying the edge" "bin/lib/ops|carries-edge" "$T26_ALW"

t26_teardown
