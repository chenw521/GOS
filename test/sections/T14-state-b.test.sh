#!/usr/bin/env bash
# gos-map:cmd commit,status
# T14: state schema evolution — evidence three-element object + task_head/_history/_pending
#     + plan_snapshot freeze/monotonic/lazy-freeze + spec_sha256 freeze + parsePlanMd hardening
# Env: GOS (CLI path), TESTBASE (isolated base), assert helpers sourced by runner
T14_DIR=""

# [Phase W T5] fixture paths follow the CLI supply (task/<id>/) — never hardcode .gos/ root
gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }
gos_plan() { node "$GOS" context plan 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["plan"])' 2>/dev/null; }

t14_setup() {
  T14_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t14"
  mkdir -p "$T14_DIR" && cd "$T14_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t14_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T14_DIR"; }

t14_setup
echo "--- T14.A: evidence three-element object, fail-closed [D-30] ---"
node "$GOS" init 3 "evidence schema" >/dev/null 2>&1

# --- A1: legacy string evidence → gate truths exit 1 + re-record hint ---
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['observable_truths']=[{'id':'T-01','description':'legacy','verified':True,'evidence':'ran tests and it passed'}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" gate truths 2>&1); RC=$?; set -e
assert_exit "A1 legacy string evidence → gate truths exit 1" 1 "$RC"
assert_contains "A1 fail-closed message points at truth verify re-record" "truth verify" "$OUT"

# --- A2: hand-edited fake excerpt (misses all three feature regexes) → exit 1 ---
mkdir -p out && echo "fixture" > out/a14.log
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['observable_truths']=[{'id':'T-01','description':'fake excerpt','verified':True,
  'evidence':{'command':'bash test/x.sh','output_excerpt':'all good','artifact_path':'out/a14.log'}}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" gate truths 2>&1); RC=$?; set -e
assert_exit "A2 fake excerpt object → gate truths exit 1" 1 "$RC"
assert_contains "A2 failure names excerpt feature requirement" "exit-code|count|path (manual); count|path|KV (replay; synthetic exit/status keys vetoed)" "$OUT"

# --- A3: valid three-element evidence (numeric-stat excerpt + real artifact) → ✓ ---
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['observable_truths']=[{'id':'T-01','description':'valid','verified':True,
  'evidence':{'command':'bash test/run-sections.sh','output_excerpt':'308 passed, 0 failed','artifact_path':'out/a14.log'}}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" gate truths 2>&1); RC=$?; set -e
assert_exit "A3 valid object → gate truths exit 0" 0 "$RC"
assert_contains "A3 ✓ line emitted" "✓ truths" "$OUT"

# --- A4: artifact_path missing on disk → exit 1 (pathExists) ---
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['observable_truths'][0]['evidence']['artifact_path']='out/gone.log'
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" gate truths 2>&1); RC=$?; set -e
assert_exit "A4 artifact missing on disk → exit 1" 1 "$RC"
assert_contains "A4 names disk existence" "not found on disk" "$OUT"

# --- A4b: machine-local zones (.gos/archive/ .gos/logs/ .gos/cache/) are
# clone-absent by design (D-01/D-08 + census audit) — the on-disk leg is an
# authoring-machine guarantee; clones must not fail schema validation ---
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['observable_truths'][0]['evidence']['artifact_path']='.gos/archive/gone-task/evi.log'
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" gate truths 2>&1); RC=$?; set -e
assert_exit "A4b archive-zone artifact skips disk check → exit 0" 0 "$RC"
if printf '%s' "$OUT" | grep -q 'not found on disk'; then
  echo "  ✗ A4b no not-found error for archive zone"; FAIL=$((FAIL+1))
else
  echo "  ✓ A4b no not-found error for archive zone"; PASS=$((PASS+1))
fi

# --- A5: command over 200 codepoints → exit 1 ---
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['observable_truths'][0]['evidence']['artifact_path']='out/a14.log'
s['observable_truths'][0]['evidence']['command']='x'*201
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" gate truths 2>&1); RC=$?; set -e
assert_exit "A5 command >200 codepoints → exit 1" 1 "$RC"
assert_contains "A5 names the codepoint cap" "200" "$OUT"

# ============================================================
echo "--- T14.B: spec_sha256 + plan_snapshot freeze flow [B-15/B-22] ---"
t14_teardown; t14_setup
node "$GOS" init 3 "snapshot flow" >/dev/null 2>&1
node "$GOS" commit intent >/dev/null 2>&1
echo "spec v1" > "$(gos_spec)"
node "$GOS" approve think >/dev/null 2>&1
set +e; OUT=$(node "$GOS" commit think 2>&1); RC=$?; set -e
assert_exit "B1 commit think exits 0" 0 "$RC"
SPEC_SHA=$(python3 -c "import hashlib; print(hashlib.sha256(open('"$(gos_spec)"','rb').read()).hexdigest())")
FROZEN=$(python3 -c "import json; print(json.load(open('.gos/state.json')).get('spec_sha256') or '')")
assert_eq "B1 commit think freezes spec_sha256 [B-22]" "$SPEC_SHA" "$FROZEN"

cat > "$(gos_plan)" <<'PLANEOF'
# Plan

### Wave 1

#### T1: impl core
- **Covers**: D-01
- **Files**: src/a.cjs, src/b.js
- **Done when**: tests pass
PLANEOF
node "$GOS" approve plan >/dev/null 2>&1
set +e; OUT=$(node "$GOS" commit plan 2>&1); RC=$?; set -e
assert_exit "B2 commit plan (first freeze) exits 0" 0 "$RC"
RT=$(python3 -c "
import json
s=json.load(open('.gos/state.json'))
exp=[{'id':'T1','covers':['D-01'],'files':['src/a.cjs','src/b.js']}]
got=(s.get('plan_snapshot') or {}).get('tasks')
print('EQ' if got==exp else 'NE:'+json.dumps(got))")
assert_eq "B2 snapshot round-trip: frozen tasks == parsed plan" "EQ" "$RT"

# --- B3: BUILD-stage re-commit plan → exit 1 (refresh constraint ①) ---
set +e; OUT=$(node "$GOS" commit plan 2>&1); RC=$?; set -e
assert_exit "B3 re-commit plan after BUILD → exit 1" 1 "$RC"
assert_contains "B3 clean-tree duplicate run hits no-change guard first" "no changes to commit" "$OUT"
mkdir -p scripts && echo drift > scripts/b3-drift.cjs && git add scripts/b3-drift.cjs
set +e; OUT=$(node "$GOS" commit plan 2>&1); RC=$?; set -e
assert_exit "B3b staged-drift re-commit plan → exit 1" 1 "$RC"
assert_contains "B3b stage-block message names current_stage=PLAN rule" "current_stage=PLAN" "$OUT"
git reset -q HEAD -- scripts/b3-drift.cjs 2>/dev/null; rm -f scripts/b3-drift.cjs

# ============================================================
echo "--- T14.C: snapshot monotonicity + --force [B-15/R2-3] ---"
t14_teardown; t14_setup
node "$GOS" init 3 "monotonic" >/dev/null 2>&1
node "$GOS" commit intent >/dev/null 2>&1
echo "spec v1" > "$(gos_spec)"
node "$GOS" approve think >/dev/null 2>&1 && node "$GOS" commit think >/dev/null 2>&1
cat > "$(gos_plan)" <<'PLANEOF'
# Plan

### Wave 1

#### T1: impl core
- **Covers**: D-01
- **Files**: src/a.cjs, src/b.js
- **Done when**: tests pass
PLANEOF
node "$GOS" approve plan >/dev/null 2>&1 && node "$GOS" commit plan >/dev/null 2>&1
# re-open the PLAN refresh window (simulates within-PLAN re-commit)
python3 -c "
import json; s=json.load(open('.gos/state.json')); s['current_stage']='PLAN'
json.dump(s,open('.gos/state.json','w'),indent=2)"
cat > "$(gos_plan)" <<'PLANEOF'
# Plan

### Wave 1

#### T1: impl core
- **Covers**: D-01
- **Files**: src/b.js
- **Done when**: tests pass
PLANEOF
set +e; OUT=$(node "$GOS" commit plan 2>&1); RC=$?; set -e
assert_exit "C1 snapshot shrink (∪Files lost src/a.cjs) → exit 1" 1 "$RC"
assert_contains "C1 monotonic message names the lost file" "src/a.cjs" "$OUT"
set +e; OUT=$(node "$GOS" commit plan --force 2>&1); RC=$?; set -e
assert_exit "C2 --force refresh allowed" 0 "$RC"
AUD=$(python3 -c "
import json; s=json.load(open('.gos/state.json'))
rows=[r.get('what') for r in (s.get('plan_snapshot') or {}).get('audit',[])]
print('OK' if 'snapshot-force' in rows else 'BAD:'+','.join(rows))")
assert_eq "C2 audit row what=snapshot-force written" "OK" "$AUD"
NEWSNAP=$(python3 -c "
import json; s=json.load(open('.gos/state.json'))
exp=[{'id':'T1','covers':['D-01'],'files':['src/b.js']}]
print('EQ' if s['plan_snapshot']['tasks']==exp else 'NE')")
assert_eq "C2 refreshed snapshot reflects the forced plan" "EQ" "$NEWSNAP"

# ============================================================
echo "--- T14.D: parsePlanMd hardening [B-21] ---"
t14_teardown; t14_setup
node "$GOS" init 3 "dup id" >/dev/null 2>&1
cat > "$(gos_plan)" <<'PLANEOF'
# Plan

### Wave 1

#### T1: first block
- **Covers**: D-01
- **Files**: a.cjs

#### T1: duplicate block
- **Covers**: D-01
- **Files**: b.cjs
PLANEOF
node "$GOS" approve plan >/dev/null 2>&1
set +e; OUT=$(node "$GOS" gate coverage 2>&1); RC=$?; set -e
assert_exit "D1 duplicate task id → gate coverage exit 1" 1 "$RC"
assert_contains "D1 duplicate message" "duplicate task id" "$OUT"
set +e; OUT=$(node "$GOS" commit plan 2>&1); RC=$?; set -e
assert_exit "D2 duplicate task id → commit plan exit 1" 1 "$RC"
assert_contains "D2 duplicate message names T1" "T1" "$OUT"

# --- D3: `**Files**: ` empty value = undeclared; parse must not crash ---
t14_teardown; t14_setup
node "$GOS" init 3 "empty files" >/dev/null 2>&1
printf '# Plan\n\n### Wave 1\n\n#### T1: no files declared\n- **Covers**: D-01\n- **Files**: \n' > "$(gos_plan)"
node "$GOS" approve plan >/dev/null 2>&1
set +e; OUT=$(node "$GOS" commit plan 2>&1); RC=$?; set -e
assert_exit "D3 empty Files value = undeclared, no crash" 0 "$RC"
D3=$(python3 -c "import json; print(json.dumps(json.load(open('.gos/state.json'))['plan_snapshot']['tasks']))")
assert_eq "D3 snapshot files == []" '[{"id": "T1", "covers": ["D-01"], "files": []}]' "$D3"

# --- D4: letter-suffixed task ids (T4a/T7b style) must parse with their Files ---
t14_teardown; t14_setup
node "$GOS" init 3 "suffixed ids" >/dev/null 2>&1
cat > "$(gos_plan)" <<'PLANEOF'
# Plan

### Wave 1

#### T4a: suffixed block
- **Covers**: D-01
- **Files**: core/lock.cjs

#### T7b: second suffixed
- **Covers**: D-01
- **Files**: ops/track.cjs
PLANEOF
node "$GOS" approve plan >/dev/null 2>&1
set +e; OUT=$(node "$GOS" commit plan 2>&1); RC=$?; set -e
assert_exit "D4 suffixed ids parse, commit plan exit 0" 0 "$RC"
D4=$(python3 -c "import json; print(json.dumps(json.load(open('.gos/state.json'))['plan_snapshot']['tasks']))")
assert_eq "D4 snapshot keeps T4a/T7b with files" '[{"id": "T4a", "covers": ["D-01"], "files": ["core/lock.cjs"]}, {"id": "T7b", "covers": ["D-01"], "files": ["ops/track.cjs"]}]' "$D4"


# ============================================================
echo "--- T14.E: task_head + history append-only [D-31/B-4] ---"
t14_teardown; t14_setup
node "$GOS" init 4 "plat" --project >/dev/null 2>&1
node "$GOS" phase add "P1: core" --goal "g1" >/dev/null 2>&1
node "$GOS" phase add "P2: next" --goal "g2" >/dev/null 2>&1
HEAD1=$(git rev-parse HEAD)
INITHEAD=$(python3 -c "import json; print(json.load(open('.gos/state.json')).get('task_head') or '')")
assert_eq "E1 init records task_head = HEAD sha" "$HEAD1" "$INITHEAD"
node "$GOS" phase claim 0 >/dev/null 2>&1
E1B=$(python3 -c "
import json; s=json.load(open('.gos/state.json'))
h=s.get('task_head_history') or []
print('%s|%d|%s' % (s.get('task_head'), len(h), h[0].get('what') if h else ''))")
assert_eq "E1 claim writes head + first history row (sha|rows|what)" "$HEAD1|1|claim" "$E1B"
git commit -q --allow-empty -m "advance head"
HEAD2=$(git rev-parse HEAD)
node "$GOS" phase unclaim >/dev/null 2>&1
# REVIEW #1: guard against silent truncation — claim must SUCCEED for E2 to be meaningful;
# if the product regresses, E2's value assertion fails loudly instead of aborting the section.
node "$GOS" phase claim 0 >/dev/null 2>&1 || echo "  ✗ E2 setup: phase claim 0 failed (re-claim regression)"
E2=$(python3 -c "
import json; s=json.load(open('.gos/state.json'))
h=s.get('task_head_history') or []
print('%s|%d|%s|%s|%s' % (s.get('task_head'), len(h), h[1].get('what') if len(h)>1 else '', h[1].get('sha') if len(h)>1 else '', h[0].get('sha') if h else ''))")
assert_eq "E2 re-claim appends row 2 (head|rows|what|sha2|sha1 preserved)" "$HEAD2|2|re-claim|$HEAD2|$HEAD1" "$E2"

# --- E3: init --force resets history + warning banner ---
set +e; OUT=$(node "$GOS" init 3 "fresh task" --force 2>&1); RC=$?; set -e
assert_exit "E3 init --force exits 0" 0 "$RC"
assert_contains "E3 task_head reset banner" "task_head_history reset" "$OUT"
EH=$(python3 -c "import json; s=json.load(open('.gos/state.json')); print(len(s.get('task_head_history') or []))")
assert_eq "E3 history reset to empty" "0" "$EH"

# --- E4: zero-commit repo → task_head null + task_head_pending true ---
t14_teardown
T14_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t14z"
mkdir -p "$T14_DIR" && cd "$T14_DIR" || exit 1
git init -q .
node "$GOS" init 3 "zero commit" >/dev/null 2>&1
E4=$(python3 -c "
import json; s=json.load(open('.gos/state.json'))
print('%s|%s' % (s.get('task_head'), s.get('task_head_pending')))")
assert_eq "E4 zero-commit: task_head null + pending true" "None|True" "$E4"

# ============================================================
echo "--- T14.G: lazy-freeze [F1] ---"
t14_teardown; t14_setup
LZF=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['semantic_checks']['lazyFreeze'])")

# --- G1: BUILD commit without plan_snapshot → banner + snapshot + audit row ---
node "$GOS" init 3 "lazy plan" >/dev/null 2>&1
# REVIEW #1 fallout: this section used to truncate at E2 (phase-claim bug + set -e), so G1
# never actually ran against the commit-embedded semantics. Realistic lazy-freeze fixture:
# the pre-Phase-B task HAS decisions (THINK happened) — plan Covers must match them.
node "$GOS" decision add D-01 "lazy-freeze covered decision" --rationale "r" >/dev/null 2>&1
mkdir -p src && echo "// lazy-freeze fixture" > src/a.cjs # Files-declared file must exist & hit diff (semantic embed)
cat > "$(gos_plan)" <<'PLANEOF'
# Plan

### Wave 1

#### T1: impl
- **Covers**: D-01
- **Files**: src/a.cjs
PLANEOF
python3 -c "
import json; s=json.load(open('.gos/state.json')); s['current_stage']='BUILD'
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" commit build 2>&1); RC=$?; set -e
assert_exit "G1 lazy-freeze BUILD commit exits 0" 0 "$RC"
assert_contains "G1 lazy-freeze banner uses contract text" "$LZF" "$OUT"
G1=$(python3 -c "
import json; s=json.load(open('.gos/state.json'))
ps=s.get('plan_snapshot') or {}
rows=[r.get('what') for r in ps.get('audit',[])]
ok = ps.get('tasks')==[{'id':'T1','covers':['D-01'],'files':['src/a.cjs']}] and 'lazy-freeze' in rows
print('OK' if ok else 'BAD:'+json.dumps(ps))")
assert_eq "G1 snapshot frozen + audit row lazy-freeze" "OK" "$G1"

# --- G2: REVIEW commit without spec_sha256 → banner + freeze + ledger row ---
t14_teardown; t14_setup
node "$GOS" init 3 "lazy spec" >/dev/null 2>&1
echo "spec lz" > "$(gos_spec)"
python3 -c "
import json; s=json.load(open('.gos/state.json')); s['current_stage']='REVIEW'
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" commit review 2>&1); RC=$?; set -e
assert_exit "G2 REVIEW lazy-freeze exits 0" 0 "$RC"
assert_contains "G2 lazy-freeze banner uses contract text" "$LZF" "$OUT"
G2=$(python3 -c "
import json,hashlib
s=json.load(open('.gos/state.json'))
ok = s.get('spec_sha256')==hashlib.sha256(open('"$(gos_spec)"','rb').read()).hexdigest() \
     and any(str(r.get('what','')).startswith('lazy-freeze') for r in s.get('lazy_freeze_audit') or [])
print('OK' if ok else 'BAD')")
assert_eq "G2 spec_sha256 frozen + lazy ledger row" "OK" "$G2"

# ============================================================
echo "--- T14.H: cmdCommit VERIFY evidence objectified [R4-F13] ---"
t14_teardown; t14_setup
node "$GOS" init 3 "verify evidence" >/dev/null 2>&1
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='VERIFY'
s['observable_truths']=[{'id':'T-01','description':'no ev','verified':True}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" commit verify 2>&1); RC=$?; set -e
assert_exit "H1 verified truth without evidence → commit verify exit 1" 1 "$RC"
assert_contains "H1 message names evidence" "evidence" "$OUT"
mkdir -p out && echo "done" > out/h.log
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['observable_truths']=[{'id':'T-01','description':'ok','verified':True,
  'evidence':{'command':'bash x.sh','output_excerpt':'3 passed, 0 failed','artifact_path':'out/h.log'}}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" commit verify 2>&1); RC=$?; set -e
assert_exit "H2 valid object evidence → commit verify exits 0" 0 "$RC"

t14_teardown
