#!/usr/bin/env bash
# gos-map:cmd decision
# decision command family (add/amend/cover/list/import)
# Env: GOS (CLI path), TESTBASE (repo root for sandbox), + assert helpers sourced by runner
T3_DIR=""

# fixture paths follow the CLI supply (task/<id>/) — never hardcode .gos/ root
gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }
gos_plan() { node "$GOS" context plan 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["plan"])' 2>/dev/null; }

t3_setup() {
  T3_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t3"
  mkdir -p "$T3_DIR" && cd "$T3_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t3_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T3_DIR"; }

t3_setup
echo "--- T3: decision family (add/amend/cover/list/import) ---"

# --- .1: add explicit id → state entry + frozen output + gate coverage blocks
node "$GOS" init 3 "decisions" >/dev/null 2>&1
OUT=$(node "$GOS" decision add D-01 "Use JSON truth store" --rationale "single source" 2>&1)
assert_contains "add D-01 output contract" "✓ Decision D-01 added: Use JSON truth store" "$OUT"
assert_contains "add next-hint contract" "Next: gos decision list" "$OUT"
D01=$(python3 -c "import json; s=json.load(open('.gos/state.json')); print(len(s['decisions']), s['decisions'][0]['id'], s['decisions'][0]['status'])")
assert_contains "state holds D-01 open" "1 D-01 open" "$D01"
set +e; OUT=$(node "$GOS" gate coverage 2>&1); RC=$?; set -e
assert_exit "gate coverage exits 1 on uncovered D-01" 1 "$RC"
assert_contains "gate output names D-01" "D-01" "$OUT"

set +e; OUT=$(node "$GOS" decision add D-01 "another" --rationale x 2>&1); RC=$?; set -e
assert_exit "duplicate add exits 1" 1 "$RC"
assert_contains "duplicate message + amend hint" "already exists, use: gos decision amend D-01" "$OUT"

# --- .3: hostile title rejected, no side-effect file
set +e; OUT=$(node "$GOS" decision add 'bad $(touch pwned-t3) x' --rationale x 2>&1); RC=$?; set -e
assert_exit "hostile title exits 1" 1 "$RC"
if [ -e pwned-t3 ]; then echo "  ✗ hostile title executed payload"; FAIL=$((FAIL+1)); else echo "  ✓ no payload side effect (pwned-t3 absent)"; PASS=$((PASS+1)); fi

LONG=$(python3 -c "print('字'*121)")
set +e; OUT=$(node "$GOS" decision add "$LONG" --rationale x 2>&1); RC=$?; set -e
assert_exit "121-codepoint title exits 1" 1 "$RC"

set +e; OUT=$(node "$GOS" decision add "anchor test" --anchor 'spec.md/../etc' 2>&1); RC=$?; set -e
assert_exit "bad anchor exits 1" 1 "$RC"

# --- .5b: bad explicit id format (R- prefix)
set +e; OUT=$(node "$GOS" decision add R-01 "wrong prefix" --rationale x 2>&1); RC=$?; set -e
assert_exit "R- prefix id rejected" 1 "$RC"

# --- .6: auto id = max(state ∪ project)+1
node "$GOS" decision add "second decision" --rationale r2 >/dev/null 2>&1
AUTO=$(python3 -c "import json; s=json.load(open('.gos/state.json')); print(s['decisions'][-1]['id'])")
assert_eq "auto id continues at D-02" "D-02" "$AUTO"

# --- .7: supersedes marks target + records chain
node "$GOS" decision add "third decision" --supersedes D-01 --rationale r3 >/dev/null 2>&1
SUP=$(python3 -c "
import json; s=json.load(open('.gos/state.json'))
d1=[d for d in s['decisions'] if d['id']=='D-01'][0]
d3=[d for d in s['decisions'] if d['id']=='D-03'][0]
print(d1['status'], d3.get('supersedes'))")
assert_contains "D-01 superseded + D-03.supersedes=D-01" "superseded D-01" "$SUP"

# self-supersede rejected
set +e; OUT=$(node "$GOS" decision add D-04 "self" --supersedes D-04 2>&1); RC=$?; set -e
assert_exit "self-supersede exits 1" 1 "$RC"

# real cycle: pre-seed (supersedes ); adding --supersedes closes the loop
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['decisions'].append({'id':'D-99','title':'chain holder','rationale':'','birth_phase':'P0','status':'open','anchor':None,'covered':False,'covered_by':None,'supersedes':'D-98'})
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" decision add D-98 "cycle closer" --supersedes D-99 2>&1); RC=$?; set -e
assert_exit "supersedes cycle exits 1" 1 "$RC"
assert_contains "cycle message" "cycle" "$OUT"

# re-adding an id that sits in the chain still exits 1
set +e; OUT=$(node "$GOS" decision add D-01 "again" --supersedes D-03 2>&1); RC=$?; set -e
assert_exit "D-01 re-add blocked (dup/cycle)" 1 "$RC"

# no plan.md yet → exit 1 "task not found in current plan"
set +e; OUT=$(node "$GOS" decision cover D-02 --task T1 2>&1); RC=$?; set -e
assert_exit "cover without plan exits 1" 1 "$RC"
assert_contains "no-plan message" "task not found in current plan" "$OUT"

mkdir -p .gos
printf '### Wave 1\n\n#### T1: something\n\n#### T-02: two things\n' > "$(gos_plan)"
OUT=$(node "$GOS" decision cover D-02 --task T1 2>&1)
assert_contains "cover output contract" "✓ Decision D-02 covered by P0:T1" "$OUT"
COV=$(python3 -c "
import json; s=json.load(open('.gos/state.json'))
d=[d for d in s['decisions'] if d['id']=='D-02'][0]
print(d['status'], d['covered'], d['covered_by'])")
assert_contains "covered + derived flag + covered_by" "covered True P0:T1" "$COV"

# T-01 alias for the same task number
OUT=$(node "$GOS" decision cover D-03 --task T-01 2>&1)
assert_contains "T-01 alias accepted" "✓ Decision D-03 covered by P0:T1" "$OUT"

# phantom task
set +e; OUT=$(node "$GOS" decision cover D-02 --task T99 2>&1); RC=$?; set -e
assert_exit "phantom task exits 1" 1 "$RC"
assert_contains "phantom message" "task not found in current plan" "$OUT"

node "$GOS" decision amend D-02 --title "renamed second" >/dev/null 2>&1
T=$(python3 -c "import json; s=json.load(open('.gos/state.json')); print([d for d in s['decisions'] if d['id']=='D-02'][0]['title'])")
assert_eq "amend changes title" "renamed second" "$T"
set +e; OUT=$(node "$GOS" decision amend D-01 --title "nope" 2>&1); RC=$?; set -e
assert_exit "amend superseded blocked" 1 "$RC"
assert_contains "amend superseded message" "cannot amend superseded" "$OUT"

# --- .10: list hides superseded by default, --all shows
OUT=$(node "$GOS" decision list 2>&1)
if echo "$OUT" | grep -q "D-01"; then echo "  ✗ list hides superseded by default"; FAIL=$((FAIL+1)); else echo "  ✓ list hides superseded by default"; PASS=$((PASS+1)); fi
assert_contains "list shows renamed D-02" "renamed second" "$OUT"
assert_contains "list header contract" "| ID | Title | Status | Phase |" "$OUT"
OUT=$(node "$GOS" decision list --all 2>&1)
assert_contains "list --all shows D-01" "D-01" "$OUT"

t3_teardown; t3_setup
node "$GOS" init 3 "import test" >/dev/null 2>&1
mkdir -p .gos/project
printf '# Decision Index\n\n| ID | Decision | Why |\n|:---|:---|:---|\n| D-01 | first imported | because |\n| D-02 | second imported | reason |\n' > .gos/project/DECISIONS.md
OUT=$(node "$GOS" decision import 2>&1)
assert_contains "import preview header" "✓ import preview: 2 entries" "$OUT"
assert_contains "preview non-interactive instructions" "Re-run with --all to import" "$OUT"
NOPERSIST=$(python3 -c "import json; print(len(json.load(open('.gos/state.json'))['decisions']))")
assert_eq "preview writes nothing" "0" "$NOPERSIST"

node "$GOS" decision import --all >/dev/null 2>&1
IMP=$(python3 -c "
import json; s=json.load(open('.gos/state.json'))
ids=[d['id'] for d in s['decisions']]
print(len(ids), 'D-01' in ids, 'D-02' in ids)")
assert_contains "import --all adds both entries" "2 True True" "$IMP"
OUT=$(node "$GOS" decision import --all 2>&1)
assert_contains "re-import skips duplicates with notice" "skipped" "$OUT"

t3_teardown; t3_setup
node "$GOS" init 4 "platform" --project >/dev/null 2>&1
node "$GOS" decision add "dual store decision" --rationale "both stores" >/dev/null 2>&1
DUAL=$(python3 -c "
import json
st=json.load(open('.gos/state.json')); pj=json.load(open('.gos/project/project.json'))
print(len(st['decisions']), len(pj['decisions']), pj['decisions'][0]['id'])")
assert_contains "dual-store: state + project both hold D-01" "1 1 D-01" "$DUAL"

t3_teardown
