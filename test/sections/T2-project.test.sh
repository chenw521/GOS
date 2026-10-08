#!/usr/bin/env bash
# gos-map:cmd phase
# T2: project.json read/write layer + init anchors
# Covers: D-01 (plan W1-T2)
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

# --- T2.1: init writes project_root anchor (git toplevel realpath) ---
node "$GOS" init 3 "auth" >/dev/null 2>&1
ROOT=$(python3 -c "import json; print(json.load(open('.gos/state.json')).get('project_root'))")
TOP=$(cd "$(git rev-parse --show-toplevel)" && pwd -P)
assert_eq "project_root anchored to toplevel" "$TOP" "$ROOT"

# --- T2.2: init --project sets project flag + creates project.json + four files ---
t2_teardown; t2_setup
node "$GOS" init 4 "platform" --project >/dev/null 2>&1
FLAG=$(python3 -c "import json; print(json.load(open('.gos/state.json')).get('project'))")
assert_eq "state.project=true with --project" "True" "$FLAG"
assert_file "project.json exists" ".gos/project/project.json"
PJ=$(python3 -c "
import json; p=json.load(open('.gos/project/project.json'))
print('%s|%s|%d|%d|%d' % (p['schema_version'], p['last_archived_phase'], len(p['phases']), len(p['decisions']), len(p['requirements'])))")
assert_contains "project.json empty skeleton" "1|None|0|0|0" "$PJ"

# --- T2.3: corrupted project.json → write-class exit 1 file:field ---
t2_teardown; t2_setup
node "$GOS" init 4 "platform" --project >/dev/null 2>&1
python3 -c "
import json; p=json.load(open('.gos/project/project.json')); p['phases']='not-array'
json.dump(p,open('.gos/project/project.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" checkpoint save --stage BUILD --unit x --done y 2>&1); RC=$?; set -e
assert_exit "corrupt project.json blocks write-class" 1 "$RC"
assert_contains "error locates project file:field" "project.json:phases" "$OUT"

# --- T2.4: project.json version future → exit 3 ---
t2_teardown; t2_setup
node "$GOS" init 4 "platform" --project >/dev/null 2>&1
python3 -c "
import json; p=json.load(open('.gos/project/project.json')); p['schema_version']=99
json.dump(p,open('.gos/project/project.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" checkpoint save --stage BUILD --unit x --done y 2>&1); RC=$?; set -e
assert_exit "project future version exit 3" 3 "$RC"

# --- T2.5: non-git dir: anchor falls back to cwd realpath ---
t2_teardown
T2_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t2ng"
mkdir -p "$T2_DIR" && cd "$T2_DIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TESTBASE"   # stop git from discovering the enclosing repo
if git rev-parse --git-dir >/dev/null 2>&1; then
  echo "  (skip: ceiling ineffective in this git version)"; PASS=$((PASS+1))
else
  node "$GOS" init 2 "no git" >/dev/null 2>&1
  ROOT=$(python3 -c "import json; print(json.load(open('.gos/state.json')).get('project_root'))")
  assert_eq "non-git anchor = cwd realpath" "$(cd "$T2_DIR" && pwd -P)" "$ROOT"
fi
unset GIT_CEILING_DIRECTORIES

t2_teardown
