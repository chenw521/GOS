#!/usr/bin/env bash
# gos-map:cmd gate,help
# contract freeze table (CONTRACTS) + the hidden `gos _contract` subcommand
# + gate emitting from the table
# Env: GOS (CLI path), TESTBASE (repo root for sandbox), assert helpers sourced by runner
T9_DIR=""

t9_setup() {
  T9_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t9"
  mkdir -p "$T9_DIR" && cd "$T9_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  echo ".gos/state.json" > .gitignore && git add .gitignore && git commit -q -m gi
}

t9_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T9_DIR"; }

t9_setup
echo "--- T9: contract frozen table + _contract + gate emission ---"

# --- .1: `_contract` is a global command — exit 0 anywhere, no state needed
set +e; OUT=$(node "$GOS" _contract 2>/dev/null); RC=$?; set -e
assert_exit "_contract exits 0" 0 "$RC"

node "$GOS" _contract 2>/dev/null | python3 -m json.tool >/dev/null 2>&1
assert_exit "stdout is valid JSON" 0 "$?"

# --- .3: all four layers present as top-level keys
LAYERS=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print(','.join(sorted(json.load(sys.stdin).keys())))")
assert_eq "six contract layers (incl. semantic_checks + paths_registry Phase W mount)" "command_contracts,decorative,gate_verdicts,paths_registry,section_runner,semantic_checks,state_semantics" "$LAYERS"

# --- .4: table holds the frozen gate verdict value
assert_contains "table registers ALL GATES PASSED" "ALL GATES PASSED" "$OUT"

# --- .5: no banner — stdout line 1 must be the JSON open brace
FIRST=$(node "$GOS" _contract 2>/dev/null | head -1)
assert_eq "stdout line 1 is '{' (banner-free)" "{" "$FIRST"

# --- .6: live parity — passing gate emits the table's allPass string
# Evidence artifact must exist on disk
node "$GOS" init 3 "auth" >/dev/null 2>&1
mkdir -p test/out && echo "308 passed, 0 failed" > test/out/t9.log
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['decisions']=[{'id':'D-01','title':'JWT','covered':True}]
s['observable_truths']=[{'id':'T-01','description':'login','verified':True,'evidence':{'command':'bash test/run-sections.sh','output_excerpt':'308 passed, 0 failed','artifact_path':'test/out/t9.log'}}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
VAL=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['gate_verdicts']['allPass'])")
assert_eq "table allPass is exact frozen string" "✓ ALL GATES PASSED" "$VAL"
GOUT=$(node "$GOS" gate all 2>&1)
assert_contains "gate all emits table allPass" "$VAL" "$GOUT"

# --- .7: failing-gate parity — uncovered decision → exit 1 + table's fail prefix
node "$GOS" init 3 "auth2" --force >/dev/null 2>&1
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['decisions']=[{'id':'D-01','title':'JWT','covered':False}]
s['observable_truths']=[{'id':'T-01','description':'login','verified':True,'evidence':{'command':'bash test/run-sections.sh','output_excerpt':'308 passed, 0 failed','artifact_path':'test/out/t9.log'}}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
FPREFIX=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['gate_verdicts']['gateFailedPrefix'])")
set +e; FOUT=$(node "$GOS" gate all 2>&1); FRC=$?; set -e
assert_exit "uncovered decision fails gate" 1 "$FRC"
assert_contains "gate output uses table failPrefix" "$FPREFIX" "$FOUT"

# --- .8: no-arg parity — status (no .gos) emits table's noActiveTask
t9_teardown
t9_setup
NOACT=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['state_semantics']['noActiveTask'])")
SOUT=$(node "$GOS" status 2>/dev/null)
assert_contains "status emits table noActiveTask" "$NOACT" "$SOUT"

# --- .9: skills dependency sweep — consumers of the frozen string exist + CLI round-trip
CONSUMERS=$(cd "$GOS_ROOT" && grep -rl "ALL GATES PASSED" skills/ | wc -l)
if [ "$CONSUMERS" -ge 1 ]; then
  echo "  ✓ skills consumers of frozen verdict exist ($CONSUMERS)"; PASS=$((PASS+1))
else
  echo "  ✗ no skills consumer greps 'ALL GATES PASSED' — frozen string has no dependents?"; FAIL=$((FAIL+1))
fi
assert_contains "CLI still emits same string (round-trip)" "ALL GATES PASSED" "$VAL"

t9_teardown
