#!/usr/bin/env bash
# gos-map:cmd commit,status   # state.json schema is exercised via commit/status
# schema layer + writeAtomicJson + state fail-closed validation + legacy migration
# Env: GOS (CLI path), TESTBASE (repo root for sandbox), + assert helpers sourced by runner
T1_DIR=""

t1_setup() {
  T1_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t1"
  mkdir -p "$T1_DIR" && cd "$T1_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  echo ".gos/state.json" > .gitignore && git add .gitignore && git commit -q -m gi
}

t1_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T1_DIR"; }

t1_setup
echo "--- T1: schema + atomic + validation + migration ---"

# --- .1: init writes state with schema_version=4 ( / : v4 drops version/project_root, adds repo_id)
node "$GOS" init 3 "auth" >/dev/null 2>&1
SV=$(python3 -c "import json; print(json.load(open('.gos/state.json')).get('schema_version'))")
assert_eq "state.schema_version=4 written" "4" "$SV"

# --- .2: corrupted state → write-class exit 1 with file:field
python3 -c "
import json; s=json.load(open('.gos/state.json')); s['decisions']='foo'
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" commit intent 2>&1); RC=$?; set -e
assert_exit "corrupt state blocks write-class" 1 "$RC"
assert_contains "error locates file:field" "state.json:decisions" "$OUT"

# --- .3: read-class on corrupt state → warn banner, no stack trace, no exit-1 crash
set +e; OUT=$(node "$GOS" status 2>&1); RC=$?; set -e
if echo "$OUT" | grep -qi "TypeError\|at Object\.\|at process\."; then
  echo "  ✗ read-class crashed with stack trace"; FAIL=$((FAIL+1))
else
  if echo "$OUT" | grep -q "state.json:decisions"; then
    echo "  ✓ read-class warns with file:field (banner mode)"; PASS=$((PASS+1))
  else
    echo "  ✗ read-class missing field warning"; FAIL=$((FAIL+1))
  fi
fi

# --- .4: legacy v0.5 state auto-migrates
t1_teardown; t1_setup
python3 - << 'PYEOF'
import json, os
os.makedirs('.gos', exist_ok=True)
state = {
  "version": "0.5", "level": 3, "current_stage": "PLAN", "completed_stages": ["INTENT","THINK"],
  "intent": {"summary": "legacy task", "confirmed": True},
  "spec_path": None, "plan_path": None,
  "requirements": [{"id": "R-01", "text": "legacy task", "phase": None, "level": 3}],
  "decisions": [{"id": "D-01", "title": "old bare decision", "covered": False},
                {"id": "D-02", "title": "old covered", "covered": True}],
  "observable_truths": [], "gaps": [{"id": "G-1724265143245", "type": "minor", "description": "x", "status": "open"}],
  "checkpoints": []
}
json.dump(state, open('.gos/state.json','w'), indent=2)
PYEOF
OUT=$(node "$GOS" status 2>&1) || true
assert_contains "legacy state migrated (no crash)" "Decisions" "$OUT"
# read-class does NOT persist migration (only write-class migrates on disk)
DISK=$(python3 -c "import json; print(json.load(open('.gos/state.json')).get('schema_version'))")
assert_eq "read-class leaves disk untouched (no rogue write)" "None" "$DISK"
# write-class persists migration (checkpoint save = unconditional write, no fallback gate)
node "$GOS" checkpoint save --stage PLAN --unit t1 --done "x" >/dev/null 2>&1 || true
MIG=$(python3 -c "
import json; s=json.load(open('.gos/state.json'))
d=s['decisions'][0]
print('%s|%s|%s|%s' % (s.get('schema_version'), d.get('birth_phase'), d.get('status'), d.get('covered')))")
assert_contains "write-class persists migration (birth_phase=legacy status=open)" "4|legacy|open|False" "$MIG"
MIG2=$(python3 -c "
import json; s=json.load(open('.gos/state.json'))
d=s['decisions'][1]; print('%s|%s' % (d.get('status'), d.get('covered')))")
assert_contains "migration derives covered from legacy field" "covered|True" "$MIG2"

# --- .5: future schema_version → exit 3 with upgrade hint
t1_teardown; t1_setup
node "$GOS" init 3 "auth" >/dev/null 2>&1
python3 -c "
import json; s=json.load(open('.gos/state.json')); s['schema_version']=999
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" commit intent 2>&1); RC=$?; set -e
assert_exit "future schema exit 3" 3 "$RC"
assert_contains "upgrade hint present" "upgrade" "$OUT"

# --- .6: atomic write leaves no temp litter
t1_teardown; t1_setup
node "$GOS" init 3 "auth" >/dev/null 2>&1
node "$GOS" status >/dev/null 2>&1 || true
TEMPS=$(ls -a .gos/ 2>/dev/null | grep -c "tmp" || true)
assert_eq "no temp files left in .gos" "0" "$TEMPS"

# --- .7: old 56-test suite regression guard happens in main runner
t1_teardown
