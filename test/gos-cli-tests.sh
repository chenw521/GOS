#!/usr/bin/env bash
# GOS CLI test suite — isolated fake-HOME, zero system impact
# Usage: bash test/gos-cli-tests.sh
# Based on install-sh-tests.sh isolation pattern

set -euo pipefail

GOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GOS="$GOS_ROOT/bin/gos.cjs"
TEST_DIR=""
PASS=0
FAIL=0

setup() {
  TEST_DIR="$(mktemp -d "/tmp/gos-test-XXXXXX")"
  cd "$TEST_DIR"
  git init -q .
  git commit -q --allow-empty -m "root"
  echo ".gos/state.json" > .gitignore
  git add .gitignore && git commit -q -m gi
  export GOS_SKIP_SHIP_CHECK=1   # T12 SHIP gate (.changes.md ritual) — unit-tested in T12-wiring, not here
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
  unset GOS_SKIP_SHIP_CHECK
}

assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if [ -z "$expected" ]; then
    echo "  ✗ $label (empty pattern always matches — use assert_file/assert_eq)"
    FAIL=$((FAIL+1))
  elif echo "$actual" | grep -q "$expected"; then
    echo "  ✓ $label"
    PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected: '$expected')"
    echo "    actual: ${actual:0:120}"
    FAIL=$((FAIL+1))
  fi
}

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then
    echo "  ✓ $label (exit $actual)"
    PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected exit $expected, got '${actual:-<none>}')"
    FAIL=$((FAIL+1))
  fi
}

assert_file() {
  local label="$1" fpath="$2"
  if [ -n "$fpath" ] && [ -e "$fpath" ]; then
    echo "  ✓ $label"
    PASS=$((PASS+1))
  else
    echo "  ✗ $label (missing: '${fpath:-<none>}')"
    FAIL=$((FAIL+1))
  fi
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ✓ $label"
    PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected: '$expected', got: '$actual')"
    FAIL=$((FAIL+1))
  fi
}

echo "=== GOS CLI Test Suite ==="
echo ""

# --- T-01: no-arg status (no task) ---
echo "--- T-01: gos (no args, no task) ---"
setup
OUT=$(node "$GOS" 2>&1) || true
assert_contains "shows 'no active task'" "o active task" "$OUT"
assert_contains "hints gos init" "gos init" "$OUT"
teardown

echo "--- T-02: gos init Lv2 ---"
setup
OUT=$(node "$GOS" init 2 "add dark mode" 2>&1)
assert_contains "initialized" "Initialized" "$OUT"
assert_contains "R-01 recorded" "R-01" "$OUT"
  assert_file "state.json exists" .gos/state.json
teardown

# --- T-03: gate coverage exit 1 ---
echo "--- T-03: gate coverage (uncovered D-NN → exit 1) ---"
setup
node "$GOS" init 3 "auth module" >/dev/null 2>&1
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['decisions']=[{'id':'D-01','title':'JWT','covered':False}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" gate coverage 2>&1); RC=$?; set -e
assert_contains "shows D-01 uncovered" "D-01" "$OUT"
assert_exit "gate coverage exit 1 on uncovered D-NN" 1 "$RC"
teardown

# --- T-04: gate requirements exit 1 (Lv4) ---
echo "--- T-04: gate requirements (unclaimed R-NN → exit 1, Lv4) ---"
setup
node "$GOS" init 4 "platform" --project >/dev/null 2>&1
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['requirements']=[{'id':'R-01','text':'auth','phase':'P1','level':4},{'id':'R-02','text':'export','phase':None,'level':4}]
s['decisions']=[{'id':'D-01','title':'x','covered':True}]
s['observable_truths']=[{'id':'T-01','description':'y','verified':True,'evidence':{'command':'cat .gitignore','output_excerpt':'exit code 0, 3 passed','artifact_path':'.gitignore'}}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
OUT=$(node "$GOS" gate requirements 2>&1 || true)
assert_contains "shows R-02 unclaimed" "R-02" "$OUT"
teardown

# --- T-05: gate all passes when clean ---
echo "--- T-05: gate all passes (clean state) ---"
setup
node "$GOS" init 3 "auth" >/dev/null 2>&1
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['decisions']=[{'id':'D-01','title':'JWT','covered':True}]
s['observable_truths']=[{'id':'T-01','description':'login','verified':True,'evidence':{'command':'cat .gitignore','output_excerpt':'exit code 0, 3 passed','artifact_path':'.gitignore'}}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
OUT=$(node "$GOS" gate all 2>&1)
assert_contains "all pass" "ALL GATES PASSED" "$OUT"
teardown

# --- T-06: resume shows summary ---
echo "--- T-06: resume ---"
setup
node "$GOS" init 2 "dark mode" >/dev/null 2>&1
OUT=$(node "$GOS" resume 2>&1)
assert_contains "shows task" "dark mode" "$OUT"
assert_contains "shows stage" "INTENT" "$OUT"
teardown

# --- T-07: commit advances stage ---
echo "--- T-07: commit <stage> ---"
setup
node "$GOS" init 3 "auth" >/dev/null 2>&1
OUT=$(node "$GOS" commit intent 2>&1)
assert_contains "committed" "Committed" "$OUT"
assert_contains "stage advanced" "advanced" "$OUT"
teardown

echo "--- T-08: Lv0 R-01 implicit ---"
setup
node "$GOS" init 0 "fix typo" >/dev/null 2>&1
RNN=$(python3 -c "import json; print(json.load(open('.gos/state.json'))['requirements'][0]['id'])")
assert_contains "R-01 auto-extracted" "R-01" "$RNN"
teardown

# --- T-09: archive creates delta.md ---
echo "--- T-09: archive ---"
setup
node "$GOS" init 3 "auth" >/dev/null 2>&1
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['decisions']=[{'id':'D-01','title':'JWT','covered':True}]
s['observable_truths']=[{'id':'T-01','description':'login','verified':True,'evidence':{'command':'cat .gitignore','output_excerpt':'exit code 0, 3 passed','artifact_path':'.gitignore'}}]
import os, json as _j
_tid=(s.get('task_head') or '0'*8)[:8]
s['spec_path']=os.path.abspath('.gos/task/%s/spec.md'%_tid); s['plan_path']=os.path.abspath('.gos/task/%s/plan.md'%_tid)
json.dump(s,open('.gos/state.json','w'),indent=2)"
_TID="$(python3 -c "import json;print((json.load(open('.gos/state.json')).get('task_head') or '0'*8)[:8])")"
mkdir -p ".gos/task/$_TID"; echo "spec" > ".gos/task/$_TID/spec.md"; echo "plan" > ".gos/task/$_TID/plan.md"
node "$GOS" approve archive >/dev/null 2>&1
OUT=$(node "$GOS" archive 2>&1)
assert_contains "archived" "Archived" "$OUT"
  assert_file "delta.md exists in archive" "$(find .gos/archive -name "delta.md" -print -quit 2>/dev/null)"
teardown

# --- T-10: protect gate (gates.json) ---
echo "--- T-10: protect gate ---"
setup
node "$GOS" init 3 "auth" >/dev/null 2>&1
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['decisions']=[{'id':'D-01','title':'x','covered':True}]
s['observable_truths']=[{'id':'T-01','description':'y','verified':True,'evidence':{'command':'cat .gitignore','output_excerpt':'exit code 0, 3 passed','artifact_path':'.gitignore'}}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
cat > .gos/gates.json << 'EOF'
{"protect": [".env"]}
EOF
echo "SECRET=x" > .env   # untracked file
git add -A 2>/dev/null   # stage it → shows in git status --porcelain
OUT=$(node "$GOS" gate 2>&1 || true)
assert_contains "protect violation" "protect" "$OUT"
# Clean: unstage + remove
git reset -q HEAD .env 2>/dev/null || true
rm -f .env
OUT=$(node "$GOS" gate 2>&1 || true)
assert_contains "protect pass" "no violation" "$OUT"
teardown

# --- T-11: custom gate script ---
echo "--- T-11: custom gate script ---"
setup
node "$GOS" init 3 "auth" >/dev/null 2>&1
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['decisions']=[{'id':'D-01','title':'x','covered':True}]
s['observable_truths']=[{'id':'T-01','description':'y','verified':True,'evidence':{'command':'cat .gitignore','output_excerpt':'exit code 0, 3 passed','artifact_path':'.gitignore'}}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
mkdir -p .gos/gates
printf '#!/bin/bash\necho "fail"\nexit 2\n' > .gos/gates/check.sh
OUT=$(node "$GOS" gate 2>&1 || true)
assert_contains "untrusted gate skipped + failed" "not trusted" "$OUT"
node "$GOS" gate trust check.sh >/dev/null 2>&1
OUT=$(node "$GOS" gate 2>&1 || true)
assert_contains "custom gate blocked" "check.sh" "$OUT"
printf '#!/bin/bash\nexit 0\n' > .gos/gates/check.sh
node "$GOS" gate trust check.sh >/dev/null 2>&1
OUT=$(node "$GOS" gate 2>&1)
assert_contains "custom gate pass" "passed" "$OUT"
teardown

# --- T-12: Lv4 project four-file set ---
echo "--- T-12: Lv4 --project ---"
setup
node "$GOS" init 4 "platform" --project >/dev/null 2>&1
for f in PROJECT.md ROADMAP.md DECISIONS.md REQUIREMENTS.md; do
  assert_file "$f exists" ".gos/project/$f"
done
teardown

# --- TD-01: doctor healthy (fake home, opencode platform linked) ---
echo "--- TD-01: doctor healthy scenario ---"
setup
FAKE_HOME="$TEST_DIR/fake-home"
mkdir -p "$FAKE_HOME/.config/opencode"
HOME="$FAKE_HOME" node "$GOS" setup >/dev/null 2>&1
set +e; OUT=$(HOME="$FAKE_HOME" node "$GOS" doctor 2>&1); RC=$?; set -e
assert_contains "healthy summary line" "RESULT: HEALTHY (0 warnings)" "$OUT"
assert_contains "exit code note" "exit code 0" "$OUT"
assert_exit "doctor exits 0 when healthy" 0 "$RC"
teardown

# --- TD-02: doctor detects broken link ---
echo "--- TD-02: doctor broken-link scenario ---"
setup
FAKE_HOME="$TEST_DIR/fake-home"
mkdir -p "$FAKE_HOME/.config/opencode"
HOME="$FAKE_HOME" node "$GOS" setup >/dev/null 2>&1
rm "$FAKE_HOME/.config/opencode/skills/gos"   # simulate broken install
set +e; OUT=$(HOME="$FAKE_HOME" node "$GOS" doctor 2>&1); RC=$?; set -e
assert_contains "reports missing link" "MISSING" "$OUT"
assert_contains "issues summary line" "RESULT: ISSUES FOUND" "$OUT"
assert_contains "not-a-crash note" "not a crash" "$OUT"
assert_exit "doctor exits 1 on issues" 1 "$RC"
teardown

# --- TD-03: doctor listed in help ---
echo "--- TD-03: help discoverability ---"
setup
OUT=$(node "$GOS" help 2>&1)
assert_contains "help lists doctor" "doctor" "$OUT"
teardown

# --- TD-04: no-platform scenario suggests gos setup ---
echo "--- TD-04: doctor no-platform scenario ---"
setup
FAKE_HOME="$TEST_DIR/fake-home"
mkdir -p "$FAKE_HOME"
set +e; OUT=$(HOME="$FAKE_HOME" node "$GOS" doctor 2>&1); RC=$?; set -e
assert_contains "suggests gos setup" "gos setup" "$OUT"
assert_exit "doctor exits 1 with no platform" 1 "$RC"
teardown

# --- TD-05: safety hardening — no dangerous commands, Fix lines whitelisted, RESULT always present ---
echo "--- TD-05: safety hardening assertions ---"
setup
FAKE_HOME="$TEST_DIR/fake-home"
mkdir -p "$FAKE_HOME/.config/opencode"
HOME="$FAKE_HOME" node "$GOS" setup >/dev/null 2>&1
rm "$FAKE_HOME/.config/opencode/skills/gos"
D1=$(HOME="$FAKE_HOME" node "$GOS" doctor 2>&1 || true)
mkdir -p "$FAKE_HOME/.claude"   # second platform, no links → warnings
D2=$(HOME="$FAKE_HOME" node "$GOS" doctor 2>&1 || true)
for OUT_NAME in D1 D2; do
  OUT_VAL="${!OUT_NAME}"
  if echo "$OUT_VAL" | grep -Eq '(^|[^a-z])(rm |rm -rf|unlink|sudo )'; then
    echo "  ✗ $OUT_NAME contains dangerous command"; FAIL=$((FAIL+1))
  else
    echo "  ✓ $OUT_NAME free of dangerous commands"; PASS=$((PASS+1))
  fi
  BAD_FIX=$(echo "$OUT_VAL" | grep '^ *Fix:' | grep -Evc '^( *Fix: `?(gos (setup|teardown)( --local <repo-path>)?|gos teardown && gos setup( --local <repo-path>)?|reinstall GOS \(npm i -g\) or git pull, then gos setup|report issue at .*doctor output.*))`? *$' || true)
  if [ "${BAD_FIX:-0}" -eq 0 ] 2>/dev/null || [ -z "$(echo "$OUT_VAL" | grep '^ *Fix:')" ]; then
    echo "  ✓ $OUT_NAME Fix lines all whitelisted"; PASS=$((PASS+1))
  else
    echo "  ✗ $OUT_NAME has non-whitelisted Fix line"; FAIL=$((FAIL+1))
  fi
  assert_contains "$OUT_NAME has RESULT line" "RESULT:" "$OUT_VAL"
done
teardown

# --- T-13: Lv4 --project ---
echo "--- T-13: Lv4 --project ---"
setup
node "$GOS" init 4 "platform" --project >/dev/null 2>&1
for f in PROJECT.md ROADMAP.md DECISIONS.md REQUIREMENTS.md; do
  assert_file "$f exists" ".gos/project/$f"
done
teardown

# --- T-14: gos context plan ( , pre-computed JSON)
echo "--- T-14: gos context plan ---"
setup
node "$GOS" init 3 "auth" >/dev/null 2>&1
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='PLAN'
s['decisions']=[{'id':'D-01','title':'JWT','covered':False}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
OUT=$(node "$GOS" context plan 2>&1)
assert_contains "returns JSON stage" '"stage": "PLAN"' "$OUT"
assert_contains "lists uncovered D-01" '"D-01"' "$OUT"
teardown

# --- T-15: filesystem fallback blocks commit think without spec
echo "--- T-15: filesystem fallback ---"
setup
node "$GOS" init 3 "auth" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" commit think 2>&1); RC=$?; set -e
assert_exit "commit think blocked without spec" 1 "$RC"
assert_contains "explains fallback" "filesystem fallback" "$OUT"
teardown

# --- T-16: checkpoint save + resume shows it
echo "--- T-16: checkpoint ---"
setup
node "$GOS" init 3 "auth" >/dev/null 2>&1
node "$GOS" checkpoint save --stage BUILD --unit wave2 --done "T3" --remaining "T4" >/dev/null 2>&1
OUT=$(node "$GOS" resume 2>&1)
assert_contains "resume shows checkpoint" "wave2" "$OUT"
teardown

echo "--- T-17: archive clears checkpoints ---"
setup
node "$GOS" init 3 "auth" >/dev/null 2>&1
node "$GOS" checkpoint save --stage BUILD --unit w1 --done T1 >/dev/null 2>&1
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['observable_truths']=[{'id':'T-01','description':'y','verified':True,'evidence':{'command':'cat .gitignore','output_excerpt':'exit code 0, 3 passed','artifact_path':'.gitignore'}}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
node "$GOS" approve archive >/dev/null 2>&1
node "$GOS" archive >/dev/null 2>&1
CKPTS=$(python3 -c "import json; print(len(json.load(open('.gos/state.json')).get('checkpoints',[])))")
assert_eq "checkpoints cleared" "0" "$CKPTS"
teardown

# --- T-18: lessons enforcement blocks archive
echo "--- T-18: lessons enforcement ---"
setup
HOME_SAVED="$HOME"; export HOME="$TEST_DIR"   # fake-HOME isolation: global lessons file must not leak in (dual-file F-1)
node "$GOS" init 3 "auth" >/dev/null 2>&1
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['gaps']=[{'id':'G-01','type':'minor','description':'x','status':'open'}]
s['observable_truths']=[{'id':'T-01','description':'y','verified':True,'evidence':{'command':'cat .gitignore','output_excerpt':'exit code 0, 3 passed','artifact_path':'.gitignore'}}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
node "$GOS" approve archive >/dev/null 2>&1
set +e; node "$GOS" archive >/dev/null 2>&1; RC=$?; set -e
assert_exit "archive blocked without lesson (approval pre-given)" 1 "$RC"
node "$GOS" lessons add --type project --scene "auth" --lesson "scene → lesson recorded" >/dev/null 2>&1
node "$GOS" archive >/dev/null 2>&1
assert_file "archive succeeds after lesson" .gos/archive
export HOME="$HOME_SAVED"
teardown

echo "--- T-19: resolve-model ---"
setup
node "$GOS" init 3 "auth" >/dev/null 2>&1
OUT=$(node "$GOS" resolve-model checker 2>&1)
assert_contains "returns JSON with agent" '"agent":"checker"' "$OUT"
node "$GOS" config models profile solo >/dev/null 2>&1
OUT=$(node "$GOS" resolve-model implementer 2>&1)
assert_contains "solo → inherit" '"model":"inherit"' "$OUT"
teardown

echo "--- T-20: model name whitelist ---"
setup
node "$GOS" init 3 "auth" >/dev/null 2>&1
set +e; node "$GOS" config models set checker 'bad; rm -rf /' >/dev/null 2>&1; RC=$?; set -e
assert_exit "malicious model name rejected" 1 "$RC"
node "$GOS" config models set checker glm-4.7-flash >/dev/null 2>&1
OUT=$(node "$GOS" resolve-model checker 2>&1)
assert_contains "valid name pinned" 'glm-4.7-flash' "$OUT"
teardown

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1
