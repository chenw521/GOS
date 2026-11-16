#!/usr/bin/env bash
# gos-map:cmd phase
# project.json read/write layer + init anchors
T2_DIR=""

t2_setup() {
  T2_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t2"
  mkdir -p "$T2_DIR" && cd "$T2_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  echo ".gos/state.json" > .gitignore && git add .gitignore && git commit -q -m gi
}

t2_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T2_DIR"; }

t2_setup
echo "--- T2: project.json layer + anchor ---"

# --- .1: init stamps de-pathed v5 identity (repo_id from remotes; NO project_root)
git remote add origin https://github.com/acme/t2-auth.git
node "$GOS" init 3 "auth" >/dev/null 2>&1
READ=$(python3 -c "
import json
s = json.load(open('.gos/state.json'))
print('%s|%s|%s' % (s.get('schema_version'), 'project_root' in s, s.get('repo_id')))")
WANT=$(python3 -c "
import hashlib
print('6|False|%s' % hashlib.sha256(b'github.com:443/acme/t2-auth').hexdigest()[:16])")
assert_eq "init: v6 + de-pathed (no project_root) + repo_id from origin remote" "$WANT" "$READ"

# --- .2: init --project bootstraps the Lv4 container only (no task state file)
t2_teardown; t2_setup
set +e; OUT=$(node "$GOS" init 4 "platform" --project 2>&1); RC=$?; set -e
assert_exit "bootstrap exits 0" 0 "$RC"
assert_contains "bootstrap opens the default milestone" "Milestone opened: milestone-1" "$OUT"
if [ -e .gos/state.json ]; then
  echo "  ✗ bootstrap wrote a task state file"; FAIL=$((FAIL+1))
else
  echo "  ✓ bootstrap writes no task state file"; PASS=$((PASS+1))
fi
assert_file "project.json exists" ".gos/project/project.json"
PJ=$(python3 -c "
import json; p=json.load(open('.gos/project/project.json'))
print('%s|%s|%s|%d|%d|%d' % (p['schema_version'], p['last_archived_phase'], (p.get('milestone') or {}).get('name'), len(p['phases']), len(p['decisions']), len(p['requirements'])))")
assert_contains "project.json skeleton with milestone-1 open" "2|None|milestone-1|0|0|0" "$PJ"
assert_file "lv4 marker seeded by bootstrap" ".gos/project/lv4.json"
assert_contains "marker is one stable JSON line" '{"lv4":true}' "$(cat .gos/project/lv4.json)"
set +e; OUT=$(node "$GOS" init 4 "platform" --project 2>&1); RC=$?; set -e
assert_exit "re-bootstrap without --fresh refuses" 1 "$RC"
assert_contains "refusal names the Lv4 trace" "Lv4 trace already present" "$OUT"
set +e; OUT=$(node "$GOS" init 4 "platform" --project --fresh 2>&1); RC=$?; set -e
assert_exit "--fresh re-bootstraps" 0 "$RC"

# --- .3: corrupted project.json → write-class exit 1 file:field
t2_teardown; t2_setup
node "$GOS" init 4 "platform" --project >/dev/null 2>&1
node "$GOS" init 3 "probe task" >/dev/null 2>&1
python3 -c "
import json; p=json.load(open('.gos/project/project.json')); p['phases']='not-array'
json.dump(p,open('.gos/project/project.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" checkpoint save --stage BUILD --unit x --done y 2>&1); RC=$?; set -e
assert_exit "corrupt project.json blocks write-class" 1 "$RC"
assert_contains "error locates project file:field" "project.json:phases" "$OUT"

# --- .4: project.json version future → exit 3
t2_teardown; t2_setup
node "$GOS" init 4 "platform" --project >/dev/null 2>&1
node "$GOS" init 3 "probe task" >/dev/null 2>&1
python3 -c "
import json; p=json.load(open('.gos/project/project.json')); p['schema_version']=99
json.dump(p,open('.gos/project/project.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" checkpoint save --stage BUILD --unit x --done y 2>&1); RC=$?; set -e
assert_exit "project future version exit 3" 3 "$RC"

# --- .5: non-git dir: no path identity stored — init succeeds, repo_id advisory null
t2_teardown
T2_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t2ng"
mkdir -p "$T2_DIR" && cd "$T2_DIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TESTBASE"   # stop git from discovering the enclosing repo
if git rev-parse --git-dir >/dev/null 2>&1; then
  echo "  (skip: ceiling ineffective in this git version)"; PASS=$((PASS+1))
else
  node "$GOS" init 2 "no git" >/dev/null 2>&1
  READ=$(python3 -c "
import json
s = json.load(open('.gos/state.json'))
print('%s|%s|%s' % (s.get('schema_version'), 'project_root' in s, s.get('repo_id')))")
  assert_eq "non-git init: v6, de-pathed, repo_id advisory null" "6|False|None" "$READ"
fi
unset GIT_CEILING_DIRECTORIES

t2_teardown
