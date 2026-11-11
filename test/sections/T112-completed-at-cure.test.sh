#!/usr/bin/env bash
# gos-map:fn bin/lib/task/commit.cjs#fn:cmdCommit bin/lib/task/archive.cjs#fn:cmdArchive bin/lib/ops/gate.cjs#fn:computeGateVerdicts
# gos-map:cmd commit,archive,gate
# completed_at cure — the commit-chain archive result must survive the commit's
# own advance write (merge), a failed chain archive heals or refuses (never
# silently advances), and DONE-idle keys on stamp OR archived-tid paths.
# Cases: A = Lv1 chain archive keeps completed_at + rewrites + freeze fields;
#        B = gate idle split (archived-tid + live paths stays live, stamp idles);
#        C = chain archive throw after dest materialized -> half-tx completion;
#        D = chain archive throw with no dest -> advance refused
T112_DIR=""

t112_setup() {
  T112_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t112"
  mkdir -p "$T112_DIR" && cd "$T112_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/.lock\n.gos/cache/\n" > .gitignore
  git add .gitignore && git commit -q -m gi
}

t112_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T112_DIR"; }

# Drive an Lv1 task to the verify-commit point with the archive approval
# already present: spec + receipt materialized under task/<id>/, one verified
# truth whose evidence points into the task dir (the rewrite observable).
t112_seed() {
  node "$GOS" init 1 "t112 $1" >/dev/null 2>&1
  node "$GOS" commit intent >/dev/null 2>&1
  SPEC="$(node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])')"
  mkdir -p "$(dirname "$SPEC")"; printf '# spec\n\nminimal t112 fixture spec\n' > "$SPEC"
  node "$GOS" approve think >/dev/null 2>&1
  node "$GOS" commit build >/dev/null 2>&1
  node "$GOS" stage build >/dev/null 2>&1
  TID="$(printf '%s' "$SPEC" | sed 's|.*\.gos/task/||; s|/spec.md$||')"
  printf 'receipt-body\n' > ".gos/task/$TID/receipt.md"
  git add ".gos/task/$TID/receipt.md" "$SPEC"
  node "$GOS" truth add "t112 truth $1" >/dev/null 2>&1
  node "$GOS" truth verify T1 --command '["echo","ok112"]' --excerpt 'exit code 0' --artifact ".gos/task/$TID/receipt.md" >/dev/null 2>&1
  node "$GOS" approve archive >/dev/null 2>&1
}

t112_state_summary() {
  node -e "
const s=JSON.parse(require('fs').readFileSync('.gos/state.json','utf8'));
const parts=[];
parts.push('stage='+s.current_stage);
parts.push('stamp='+(s.completed_at?'yes':'no'));
parts.push('spec='+(String(s.spec_path||'').indexOf('.gos/archive/')===0?'arch':'live'));
parts.push('ev='+(((s.observable_truths||[])[0]||{}).evidence&&String(s.observable_truths[0].evidence.artifact_path).indexOf('.gos/archive/')===0?'arch':'live'));
parts.push('appr='+((s.approvals||{}).THINK&&(s.approvals||{}).ARCHIVE?'both':'partial'));
parts.push('cs='+s.completed_stages.join(','));
parts.push('ckpt='+((s.checkpoints||[]).length));
parts.push('sha='+(s.spec_sha256?'yes':'no'));
console.log(parts.join('|'));
" 2>&1
}

t112_setup
trap 't112_teardown' EXIT
PASS=0; FAIL=0
echo "--- T112: completed_at cure (chain merge / catch discipline / idle split) ---"

# ===== A: commit verify chain-archives; the merge keeps archive-won fields
# alongside the commit-won freeze fields =====
t112_seed a
set +e; AOUT=$(node "$GOS" commit verify 2>&1); ARC=$?; set -e
assert_exit "A1 chain archive commit verify exit 0" 0 "$ARC"
assert_contains "A2 archived banner present" "archived" "$AOUT"
assert_eq "A3 final state carries stamp+rewrites+approvals+backfill+sha" \
  "stage=DONE|stamp=yes|spec=arch|ev=arch|appr=both|cs=INTENT,BUILD,VERIFY|ckpt=0|sha=yes" \
  "$(t112_state_summary)"
if [ ! -e ".gos/task/$TID" ]; then echo "  ✓ A4 live task dir moved out"; PASS=$((PASS+1)); else echo "  ✗ A4 live task dir still present"; FAIL=$((FAIL+1)); fi
ADIR="$(ls -d .gos/archive/*/ 2>/dev/null | head -1)"
assert_file "A5 archived receipt inside dest" "${ADIR}task/$TID/receipt.md"
ASHA="$(node -e "
const s=JSON.parse(require('fs').readFileSync('.gos/state.json','utf8'));
const c=require('crypto');const fs=require('fs');
console.log(c.createHash('sha256').update(fs.readFileSync(s.spec_path)).digest('hex')===s.spec_sha256?'match':'mismatch');
" 2>&1)"
assert_eq "A6 spec_sha256 matches the archived spec file" "match" "$ASHA"
assert_contains "A7 archive dest rides in the advance commit" ".gos/archive" "$(git show --name-only --format= HEAD)"

# ===== B: gate idle split — archived tid + live paths stays live; stamp idles =====
t112_teardown; t112_setup
GOS_HEADLESS=1 node "$GOS" init 3 "t112 idle split" >/dev/null 2>&1
node -e "
const fs=require('fs');
const s=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
s.task_head='abcd1234';
s.current_stage='DONE';
s.spec_path='.gos/task/abcd1234/spec.md';
s.decisions=[{id:'D-99',title:'uncovered marker',covered:false,status:'open'}];
fs.writeFileSync('.gos/state.json', JSON.stringify(s,null,2));
"
mkdir -p .gos/archive/2026-11-11-v9.9.9-task-t112split/task/abcd1234
set +e; BOUT=$(node "$GOS" gate coverage 2>&1); BRC=$?; set -e
assert_exit "B1 archived-tid + live paths does NOT idle (exit 1)" 1 "$BRC"
assert_contains "B2 coverage failure surfaced (not an idle advisory)" "not covered" "$BOUT"
if printf '%s' "$BOUT" | grep -q "coverage idle"; then echo "  ✗ B3 idle advisory leaked on live-path state"; FAIL=$((FAIL+1)); else echo "  ✓ B3 no idle advisory on live-path state"; PASS=$((PASS+1)); fi
node -e "
const fs=require('fs');
const s=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
s.completed_at='2026-11-11T00:00:00.000Z';
fs.writeFileSync('.gos/state.json', JSON.stringify(s,null,2));
"
set +e; BOUT2=$(node "$GOS" gate coverage 2>&1); BRC2=$?; set -e
assert_exit "B4 stamp-only idles (exit 0)" 0 "$BRC2"
assert_contains "B5 idle advisory present once stamped" "coverage idle" "$BOUT2"
# stamp removed again, paths relocated into the archived tid home — the
# archived-layout arm alone idles (stamp-lost cure); every registered direct
# path must move (one live path is enough to keep the checks live)
node -e "
const fs=require('fs');
const s=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
delete s.completed_at;
s.spec_path='.gos/archive/2026-11-11-v9.9.9-task-t112split/task/abcd1234/spec.md';
s.plan_path='.gos/archive/2026-11-11-v9.9.9-task-t112split/task/abcd1234/plan.md';
fs.writeFileSync('.gos/state.json', JSON.stringify(s,null,2));
"
set +e; BOUT3=$(node "$GOS" gate coverage 2>&1); BRC3=$?; set -e
assert_exit "B6 archived-tid + archive-resident paths idles without the stamp" 0 "$BRC3"
assert_contains "B7 idle advisory present via the archived-layout arm" "coverage idle" "$BOUT3"

# ===== C: chain archive throws after the dest materialized -> half-tx lands,
# commit still completes with the merged result =====
t112_teardown; t112_setup
t112_seed c
set +e; COUT=$(GOS_TEST_BREAK_SHIP=pre-stamp node "$GOS" commit verify 2>&1); CRC=$?; set -e
assert_exit "C1 catch-with-dest heals and advances (exit 0)" 0 "$CRC"
assert_contains "C2 half-transaction completion banner" "half-transaction completed idempotently" "$COUT"
assert_contains "C3 commit reports the healed archive" "completion landed" "$COUT"
assert_eq "C4 healed final state shape" \
  "stage=DONE|stamp=yes|spec=arch|ev=arch|appr=both|cs=INTENT,BUILD,VERIFY|ckpt=0|sha=yes" \
  "$(t112_state_summary)"

# ===== D: chain archive throws before anything materialized -> advance refused =====
t112_teardown; t112_setup
t112_seed d
set +e; DOUT=$(GOS_TEST_BREAK_SHIP=pre-flight node "$GOS" commit verify 2>&1); DRC=$?; set -e
assert_exit "D1 catch-without-dest refuses the advance (exit 1)" 1 "$DRC"
assert_contains "D2 refusal names the no-dest condition" "refusing to advance" "$DOUT"
DSTAGE="$(python3 -c "import json;print(json.load(open('.gos/state.json'))['current_stage'])")"
assert_eq "D3 state not advanced past VERIFY" "VERIFY" "$DSTAGE"
assert_file "D4 live task dir untouched" ".gos/task/$TID/spec.md"

t112_teardown
echo "--- T112 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
