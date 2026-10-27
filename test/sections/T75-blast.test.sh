#!/usr/bin/env bash
# gos-map:cmd map,context
# : gos map blast facade
# Cases: report with header + reasons / zero-args usage die / unknown path human
# refuse / unknown path print0 stderr+exit1 / zero-impact explicit line /
# print0 NUL semantics / no anchor syntax in output / --json envelope /
# context build blast hint when plan Files exist
# Env: GOS, TESTBASE, assert helpers
T75_DIR=""

t75_setup() {
  T75_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t75"
  mkdir -p "$T75_DIR" && cd "$T75_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t75_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T75_DIR"; }

t75_g() { node "$GOS" "$@"; }

t75_setup
echo "--- T75: map blast facade ---"

# fixture: hand edge src/util.js --[consumes]--> src/app.js (engine source 3 —
# deterministic, no extractor-pattern coupling)
mkdir -p src
cat > src/util.js <<'EOF'
function helper() { return 1; }
module.exports = { helper };
EOF
cat > src/app.js <<'EOF'
const util = require('./util.js');
function cmdRun() { return util.helper(); }
module.exports = { cmdRun };
EOF
t75_g init 2 "t75 blast" >/dev/null 2>&1
t75_g map edge add src/util.js src/app.js --type consumes --note "app consumes util" >/dev/null 2>&1

# --- .1: report shape — self-labeling header + inputs + reasons
OUT=$(t75_g map blast src/util.js 2>&1); RC=$?
assert_exit "blast exits 0 on known path" "0" "$RC"
assert_contains "self-labeling header" "blast report — human report; machine consumers: --json/--print0" "$OUT"
assert_contains "inputs line" "inputs: src/util.js" "$OUT"
assert_contains "impacted consumer listed" "src/app.js" "$OUT"
assert_contains "edge reason shown" "reason: hand:consumes" "$OUT"
assert_contains "summary line" "summary: 1 impacted file(s)" "$OUT"
assert_contains "next-step guidance" "plan Files" "$OUT"

# --- .2: zero args → usage die (blast wording)
OUT=$(t75_g map blast 2>&1); RC=$?
assert_exit "zero args dies" "1" "$RC"
assert_contains "usage mentions what blast does" "must be checked and why" "$OUT"

# --- .3: unknown path — human mode refuses with closureUnknownPath semantics
OUT=$(t75_g map blast no/such/file.js 2>&1); RC=$?
assert_exit "unknown path refused" "1" "$RC"
assert_contains "unknown-path wording under blast" "not in graph" "$OUT"

# --- .4: unknown path --print0 → stderr diagnostic + exit 1 (never silent)
OUT=$(t75_g map blast no/such/file.js --print0 2>t75-err.txt); RC=$?
assert_exit "print0 unknown path exit 1" "1" "$RC"
assert_contains "print0 stderr single-line diagnostic" "unknown path" "$(cat t75-err.txt)"
if [ -s "$OUT" ] 2>/dev/null || [ -n "$OUT" ]; then
  echo "  ✗ print0 leaked bytes on stdout"; FAIL=$((FAIL+1))
else
  echo "  ✓ print0 stdout empty on error"; PASS=$((PASS+1))
fi

# --- .5: zero-impact explicit line exit 0 + print0 empty success
echo "// standalone" > src/standalone.js
OUT=$(t75_g map blast src/standalone.js 2>&1); RC=$?
assert_exit "zero-impact exits 0" "0" "$RC"
assert_contains "explicit zero-impact line" "no impacted files" "$OUT"
OUT=$(t75_g map blast src/standalone.js --print0 2>/dev/null); RC=$?
assert_exit "print0 zero-impact exit 0 (xargs semantics)" "0" "$RC"
if [ -n "$OUT" ]; then
  echo "  ✗ print0 leaked bytes on zero impact"; FAIL=$((FAIL+1))
else
  echo "  ✓ print0 empty NUL stream on zero impact"; PASS=$((PASS+1))
fi

# --- .6: rendering never emits anchor syntax (# separators)
OUT=$(t75_g map blast src/util.js 2>&1)
if echo "$OUT" | grep -q "#fn:\|#cmd:"; then
  echo "  ✗ anchor syntax leaked into blast output"; FAIL=$((FAIL+1))
else
  echo "  ✓ no anchor syntax in blast render"; PASS=$((PASS+1))
fi

OUT=$(t75_g map blast src/util.js --json 2>/dev/null)
if python3 -c "
import json,sys
d = json.loads('''$OUT''')
b = d['blast']
assert b['inputs'] == ['src/util.js']
assert any(i['file'] == 'src/app.js' for i in b['impacted'])
assert any(i['via'] for i in b['impacted'])
" 2>/dev/null; then
  echo "  ✓ --json envelope carries inputs + impacted with reasons"; PASS=$((PASS+1))
else
  echo "  ✗ --json envelope malformed"; echo "    out: $OUT" | head -3; FAIL=$((FAIL+1))
fi

# --- .8: print0 NUL stream contains impacted files
t75_g map blast src/util.js --print0 > t75-p0.bin 2>/dev/null; RC=$?
assert_exit "print0 known path exits 0" "0" "$RC"
if python3 -c "
data = open('t75-p0.bin','rb').read()
names = [x.decode() for x in data.split(b'\x00') if x]
assert 'src/app.js' in names, names
assert b'#' not in data
" 2>/dev/null; then
  echo "  ✓ print0 NUL stream: impacted files, no anchors"; PASS=$((PASS+1))
else
  echo "  ✗ print0 stream wrong"; FAIL=$((FAIL+1))
fi

# --- .9: context build carries the blast hint when plan Files exist
TID="$(python3 -c 'import json;print(json.load(open(".gos/state.json"))["task_head"][:8])')"
mkdir -p ".gos/task/$TID"
cat > ".gos/task/$TID/plan.md" <<'EOF'
# Plan
### Wave 1
#### T1: impl
- **Covers**: R-01
- **Files**: src/util.js
EOF
python3 - <<'PYEOF'
import json
p='.gos/state.json'
s=json.load(open(p))
s['current_stage']='BUILD'
s['plan_path']='.gos/task/'+s['task_head'][:8]+'/plan.md'
json.dump(s,open(p,'w'),indent=2)
PYEOF
OUT=$(t75_g context build 2>&1)
assert_contains "context build carries blast hint" "gos map blast" "$OUT"

# --- .10: unknown flag → usage die
OUT=$(t75_g map blast src/util.js --bogus 2>&1); RC=$?
assert_exit "unknown flag dies" "1" "$RC"

# --- .11: anti-vacuity — exists-on-disk but unknown-to-graph dies (closure parity)
printf 'notes\n' > notes.md
OUT=$(t75_g map blast notes.md 2>&1); RC=$?
assert_exit "existing-but-unscanned file dies (never vacuous green)" "1" "$RC"
assert_contains "unknown-to-graph wording" "not in graph" "$OUT"
OUT=$(t75_g map blast src 2>&1); RC=$?
assert_exit "directory arg dies" "1" "$RC"
OUT=$(t75_g map blast src/standalone.js 2>&1); RC=$?
assert_exit "scanned zero-impact file still green" "0" "$RC"

t75_teardown
