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

# grandfather: same spec, no stamp → lazy probe enforces the highest passing floor
python3 - <<'PYEOF'
import json
p='.gos/state.json'
s=json.load(open(p))
del s['spec_gate_version']
json.dump(s,open(p,'w'),indent=2)
PYEOF
OUT=$(t73_g gate semantic 2>&1); RC=$?
if echo "$OUT" | grep -q "spec-gate-card"; then
  echo "  ✗ unstamped old-format spec failed the probed floor"; FAIL=$((FAIL+1))
elif echo "$OUT" | grep -q -- "--refreeze"; then
  echo "  ✓ unstamped old-format spec passes the lazily probed floor, advisory names the persisting flag"; PASS=$((PASS+1))
else
  echo "  ✗ probe advisory missing the persisting flag"; FAIL=$((FAIL+1))
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

# --- .7: floor registry — stamp dispatch, lazy probe, column contract
# Spec fixtures are written through printf lists: markdown heading lines
# carry decision ids, and lines starting with # would read as comment lines
# to the anchor lint.
t73_floor_state() {
  python3 - "$1" <<'PYEOF'
import json, sys
p='.gos/state.json'
s=json.load(open(p))
s['spec_path']='.gos/task/' + s['task_head'][:8] + '/spec.md'
s['decisions']=[{'id':'D-01','title':'storage','covered':True,'status':'covered'}]
s['plan_path']=None
s['plan_snapshot']=None
if 'spec_gate_version' in s: del s['spec_gate_version']
mode = sys.argv[1]
if mode == 'v3': s['spec_gate_version'] = 3
elif mode == 'v2': s['spec_gate_version'] = 2
elif mode == 'v99': s['spec_gate_version'] = 99
elif mode == 'str3': s['spec_gate_version'] = '3'
json.dump(s,open(p,'w'),indent=2)
PYEOF
}

t73_card5() {
  printf '%s\n' \
    '# Spec' \
    '## D-01 storage card' \
    '| Option | Premise | Pros | Cons | Activates |' \
    '|:--|:--|:--|:--|:--|' \
    '| json | tracked | integrity chain | harder to merge | gate freeze check |' \
    '| md | simple | readable | no integrity chain | docs walkthrough |' \
    'why-not: md — no integrity chain' > "$SPEC"
}

t73_card2() {
  printf '%s\n' \
    '# Spec' \
    '## D-01 storage card' \
    '| Option | Premise |' \
    '|:--|:--|' \
    '| json | tracked |' \
    '| md | simple |' \
    'why-not: md — no integrity chain' > "$SPEC"
}

# five-column card under stamp 3 → pass, floor version named
t73_floor_state v3
t73_card5
OUT=$(t73_g gate semantic 2>&1); RC=$?
assert_exit "five-column card under stamp 3 passes" "0" "$RC"
assert_contains "pass line names floor v3" "spec cards (floor v3)" "$OUT"

# card table without the Activates header → fail
t73_floor_state v3
printf '%s\n' \
  '# Spec' \
  '## D-01 storage card' \
  '| Option | Premise | Pros | Cons |' \
  '|:--|:--|:--|:--|' \
  '| json | tracked | integrity chain | harder to merge |' \
  '| md | simple | readable | no integrity chain |' \
  'why-not: md — no integrity chain' > "$SPEC"
OUT=$(t73_g gate semantic 2>&1); RC=$?
assert_exit "missing Activates header fails under stamp 3" "1" "$RC"
assert_contains "missing Activates failure code" "spec-gate-card-column" "$OUT"

# empty Activates cell → fail
t73_floor_state v3
printf '%s\n' \
  '# Spec' \
  '## D-01 storage card' \
  '| Option | Premise | Pros | Cons | Activates |' \
  '|:--|:--|:--|:--|:--|' \
  '| json | tracked | integrity chain | harder to merge | gate freeze check |' \
  '| md | simple | readable | no integrity chain | |' \
  'why-not: md — no integrity chain' > "$SPEC"
OUT=$(t73_g gate semantic 2>&1); RC=$?
assert_exit "empty Activates cell fails under stamp 3" "1" "$RC"
assert_contains "empty cell failure code" "spec-gate-card-column" "$OUT"

# Activates cell identical to the Pros cell → fail
t73_floor_state v3
printf '%s\n' \
  '# Spec' \
  '## D-01 storage card' \
  '| Option | Premise | Pros | Cons | Activates |' \
  '|:--|:--|:--|:--|:--|' \
  '| json | tracked | integrity chain | harder to merge | integrity chain |' \
  '| md | simple | readable | no integrity chain | docs walkthrough |' \
  'why-not: md — no integrity chain' > "$SPEC"
OUT=$(t73_g gate semantic 2>&1); RC=$?
assert_exit "Pros-copy Activates cell fails under stamp 3" "1" "$RC"
assert_contains "Pros-copy failure code" "spec-gate-card-column" "$OUT"

# option row with fewer cells than its own header → fail
t73_floor_state v3
printf '%s\n' \
  '# Spec' \
  '## D-01 storage card' \
  '| Option | Premise | Pros | Cons | Activates |' \
  '|:--|:--|:--|:--|:--|' \
  '| json | tracked | integrity chain | harder to merge |' \
  '| md | simple | readable | no integrity chain | docs walkthrough |' \
  'why-not: md — no integrity chain' > "$SPEC"
OUT=$(t73_g gate semantic 2>&1); RC=$?
assert_exit "malformed row fails under stamp 3" "1" "$RC"
assert_contains "malformed row failure code" "spec-gate-card-column" "$OUT"

# two-column old-format card under stamp 2 → pass, no Activates demanded
t73_floor_state v2
t73_card2
OUT=$(t73_g gate semantic 2>&1); RC=$?
assert_exit "old-format card under stamp 2 passes" "0" "$RC"
assert_contains "pass line names floor v2" "spec cards (floor v2)" "$OUT"

# absent stamp → lazy probe, old-format content passes on floor v2
t73_floor_state none
t73_card2
OUT=$(t73_g gate semantic 2>&1); RC=$?
assert_exit "unstamped old-format card passes the probe" "0" "$RC"
assert_contains "probe enforces floor v2 for this run" "spec cards (floor v2)" "$OUT"
assert_contains "probe advisory names the persisting flag" "no stamp.*refreeze" "$OUT"

# stamp outside the domain → fail closed
t73_floor_state v99
t73_card5
OUT=$(t73_g gate semantic 2>&1); RC=$?
assert_exit "stamp 99 fails closed" "1" "$RC"
assert_contains "unknown stamp failure code" "spec-gate-version-unknown" "$OUT"

# string stamp → fail closed (schema validator or gate domain, never silent)
t73_floor_state str3
t73_card5
OUT=$(t73_g gate semantic 2>&1); RC=$?
assert_exit "string stamp fails closed" "1" "$RC"
if echo "$OUT" | grep -q "spec-gate-version-unknown"; then
  echo "  ✓ string stamp rejected at the gate floor domain"; PASS=$((PASS+1))
elif echo "$OUT" | grep -q "integer required when present"; then
  echo "  ✓ string stamp rejected at the state schema validator"; PASS=$((PASS+1))
else
  echo "  ✗ string stamp did not fail closed"; FAIL=$((FAIL+1))
fi

# override escape: unknown stamp downgraded to an advisory, never blocks
t73_floor_state v99
t73_card5
OUT=$(GOS_SPEC_GATE_FLOOR_OVERRIDE=1 t73_g gate semantic 2>&1); RC=$?
assert_exit "override env var skips the unknown-stamp block" "0" "$RC"
assert_contains "override advisory shown" "GOS_SPEC_GATE_FLOOR_OVERRIDE" "$OUT"

# superseding heading: the mentioned id must not inherit the card
python3 - <<'PYEOF'
import json
p='.gos/state.json'
s=json.load(open(p))
s['spec_path']='.gos/task/' + s['task_head'][:8] + '/spec.md'
s['spec_gate_version']=3
s['decisions']=[
  {'id':'D-01','title':'supersede source','covered':True,'status':'covered'},
  {'id':'D-02','title':'superseded','covered':True,'status':'covered'}]
s['plan_path']=None
s['plan_snapshot']=None
json.dump(s,open(p,'w'),indent=2)
PYEOF
printf '%s\n' \
  '# Spec' \
  '## D-01: superseding D-02' \
  '| Option | Premise | Pros | Cons | Activates |' \
  '|:--|:--|:--|:--|:--|' \
  '| json | tracked | integrity chain | harder to merge | gate freeze check |' \
  '| md | simple | readable | no integrity chain | docs walkthrough |' \
  'why-not: md — no integrity chain' > "$SPEC"
OUT=$(t73_g gate semantic 2>&1); RC=$?
assert_exit "superseded id stays card-missing under stamp 3" "1" "$RC"
assert_contains "mentioned id fails card-missing, not cross-credited" "spec-gate-card-missing" "$OUT"

t73_teardown
