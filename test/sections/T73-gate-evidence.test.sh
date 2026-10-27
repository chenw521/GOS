#!/usr/bin/env bash
# gos-map:cmd gate
# gate-evidence meta-tests
# Cases: meta grep zero raw string pushes / renderer unit (string injection
# crashes post-switch) / 3-part block render / adversarial-filename fix lines
# single-command-safe / --json object-only / spec-gate floor (good card pass,
# missing why-not fail, underflow D-NN fail, exempt marker pass, grandfather
# vacuous-pass) / locale-invariant fields
# Env: GOS, TESTBASE, assert helpers
T73_DIR=""

t73_setup() {
  T73_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t73"
  mkdir -p "$T73_DIR" && cd "$T73_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t73_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T73_DIR"; }

t73_g() { node "$GOS" "$@"; }

t73_setup
echo "--- T73: gate evidence chain meta-tests ---"

t73_g init 3 "t73 gate evidence" >/dev/null 2>&1

# --- .1: meta grep — zero raw string failure pushes in the gate family
RAW_PUSH=$(grep -cE "failures\.push\((\`|'|\")" "$GOS_ROOT/bin/lib/ops/gate.cjs" "$GOS_ROOT/bin/lib/map/allowlist.cjs" "$GOS_ROOT/bin/lib/knowledge/lessons-json.cjs" | awk -F: '{s+=$NF} END {print s+0}')
assert_eq "meta grep: zero raw string failure pushes (gate family)" "0" "$RAW_PUSH"

# --- .2: renderer unit — object renders 3-part; string injection CRASHES
OUT=$(node -e '
const gate = require(process.env.GOS_ROOT + "/bin/lib/ops/gate.cjs");
const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
const f = core.gateFail("x-code", { verdict: "what happened", evidence: ["fileA", "edge B→C"], fix: core.gateCmd("git checkout", "a;rm -rf ~.x") });
const out = gate.renderGateFailures([f]);
if (!out.includes("✗ x-code: what happened")) process.exit(11);
if (!out.includes("evidence: fileA") || !out.includes("evidence: edge B→C")) process.exit(12);
if (!out.includes("fix: git checkout \x27a;rm -rf ~.x\x27")) process.exit(13);
try { gate.renderGateFailures(["raw string failure"]); process.exit(20); } catch (e) { if (!/post-switch/.test(e.message)) process.exit(21); }
console.log("OK");
' 2>&1); RC=$?
assert_exit "renderer unit: 3-part block + string injection crashes (post-switch)" "0" "$RC"
assert_contains "renderer OK marker" "OK" "$OUT"

# --- .3: adversarial fix lines are single-command-safe under sh -c
ADV="$T73_DIR/adv"
mkdir -p "$ADV"
echo "victim" > "$ADV/normal-file.cjs"
FIXLINES=$(node -e '
const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
console.log(core.gateCmd("git checkout", process.argv[1]));
console.log(core.gateCmd("node bin/gos.cjs lessons rm", process.argv[2], "--reason cleanup"));
console.log(core.gateCmd("git checkout", "-rf"));
console.log(core.gateCmd("git checkout", process.argv[3]));
' "a;rm -rf \$ADV/victim" "\`touch pwned3\`" '$(touch pwned).cjs' 2>&1)
echo "$FIXLINES" | while IFS= read -r line; do
  sh -c "cd '$ADV' && $line 2>/dev/null || true" >/dev/null 2>&1
done
sleep 0.2
if [ -e pwned ] || [ -e pwned3 ] || [ ! -e "$ADV/normal-file.cjs" ]; then
  echo "  ✗ adversarial fix line executed side effects"; FAIL=$((FAIL+1))
else
  echo "  ✓ adversarial fix lines single-command-safe (no injection artifacts)"; PASS=$((PASS+1))
fi
rm -rf "$ADV"

# --- .4: gate --json failures object-only
python3 - <<'PYEOF'
import json
p='.gos/state.json'
s=json.load(open(p))
s['current_stage']='BUILD'
s['decisions']=[{'id':'D-01','title':'d','covered':False}]
json.dump(s,open(p,'w'),indent=2)
PYEOF
t73_g gate coverage --json > t73-json.out 2>/dev/null; RC=$?
assert_exit "gate coverage with uncovered decision exits 1" "1" "$RC"
if python3 -c "
import json
d=json.load(open('t73-json.out'))
assert d['verdict'] == 'fail'
assert all(isinstance(f, dict) and set(f) >= {'code','verdict','evidence','fix'} for f in d['failures']), 'failures not object-only'
" 2>/dev/null; then
  echo "  ✓ --json failures are {code,verdict,evidence,fix} objects"; PASS=$((PASS+1))
else
  echo "  ✗ --json failures not object-only"; FAIL=$((FAIL+1))
fi

# --- .5: 3-part block in human render (coverage failure path)
OUT=$(t73_g gate coverage 2>&1)
assert_contains "head line is ✗ <code>: <verdict>" "✗ coverage-uncovered:" "$OUT"
assert_contains "evidence line present" "evidence:" "$OUT"
assert_contains "fix line present" "fix:" "$OUT"

# --- .6: spec-gate floor — good card passes; grandfather vacuous-pass
SPEC="$(python3 -c 'import json,os;print(json.load(open(".gos/state.json")).get("spec_path") or "")')"
T73_TID="$(python3 -c 'import json;print(json.load(open(".gos/state.json"))["task_head"][:8])')"
mkdir -p ".gos/task/$T73_TID"
SPEC=".gos/task/$T73_TID/spec.md"
cat > "$SPEC" <<'EOF'
# Spec
## D-01 storage card
| Option | Premise |
|:--|:--|
| json | tracked |
| md | simple |
why-not: md — no integrity chain
EOF
python3 - <<'PYEOF'
import json
p='.gos/state.json'
s=json.load(open(p))
s['spec_path']='.gos/task/' + s['task_head'][:8] + '/spec.md'
s['spec_gate_version']=2
s['decisions']=[{'id':'D-01','title':'storage','covered':True,'status':'covered'}]
s['plan_path']=None
s['plan_snapshot']=None
json.dump(s,open(p,'w'),indent=2)
PYEOF
OUT=$(t73_g gate semantic 2>&1); RC=$?
assert_contains "spec cards ✓ line on good card" "spec cards" "$OUT"
if echo "$OUT" | grep -q "spec-gate"; then
  echo "  ✗ good card flagged"; FAIL=$((FAIL+1))
else
  echo "  ✓ good card passes the floor"; PASS=$((PASS+1))
fi

# grandfather: same spec, no stamp → vacuous pass
python3 - <<'PYEOF'
import json
p='.gos/state.json'
s=json.load(open(p))
del s['spec_gate_version']
json.dump(s,open(p,'w'),indent=2)
PYEOF
OUT=$(t73_g gate semantic 2>&1); RC=$?
if echo "$OUT" | grep -q "spec-gate-card"; then
  echo "  ✗ grandfathered spec failed the card floor"; FAIL=$((FAIL+1))
else
  echo "  ✓ pre-P15 spec vacuous-passes (grandfather, F2/F12)"; PASS=$((PASS+1))
fi
python3 - <<'PYEOF'
import json
p='.gos/state.json'
s=json.load(open(p))
s['spec_gate_version']=2
json.dump(s,open(p,'w'),indent=2)
PYEOF

# missing why-not → FAIL
sed -i '/^why-not:/d' "$SPEC"
OUT=$(t73_g gate semantic 2>&1); RC=$?
assert_exit "missing why-not fails the gate" "1" "$RC"
assert_contains "why-not failure code" "spec-gate-card-why-not" "$OUT"

# underflow D-NN in prose → FAIL; in fenced/exempt → pass
cat >> "$SPEC" <<'EOF'
See D-77 in prose.
EOF
OUT=$(t73_g gate semantic 2>&1); RC=$?
assert_contains "unknown D-NN underflow fails" "spec-gate-unknown-decision" "$OUT"
python3 - <<'PYEOF'
p = '.gos/task/' + open('.gos/state.json').read()
import json, re
s = json.load(open('.gos/state.json'))
sp = '.gos/task/' + s['task_head'][:8] + '/spec.md'
t = open(sp).read().replace('See D-77 in prose.', 'See D-77 exempt. <!-- gos:spec-gate:exempt -->')
open(sp, 'w').write(t)
PYEOF
OUT=$(t73_g gate semantic 2>&1); RC=$?
if echo "$OUT" | grep -q "spec-gate-unknown-decision"; then
  echo "  ✗ exempt-marker line still scanned"; FAIL=$((FAIL+1))
else
  echo "  ✓ exempt-marker line not scanned"; PASS=$((PASS+1))
fi
python3 - <<'PYEOF'
import json
s = json.load(open('.gos/state.json'))
sp = '.gos/task/' + s['task_head'][:8] + '/spec.md'
t = open(sp).read().replace('See D-77 exempt. <!-- gos:spec-gate:exempt -->', '```\nD-77 fenced example\n```')
open(sp, 'w').write(t)
PYEOF
OUT=$(t73_g gate semantic 2>&1); RC=$?
if echo "$OUT" | grep -q "spec-gate-unknown-decision"; then
  echo "  ✗ fenced D-NN still scanned"; FAIL=$((FAIL+1))
else
  echo "  ✓ fenced code block D-NN not scanned"; PASS=$((PASS+1))
fi

t73_teardown
