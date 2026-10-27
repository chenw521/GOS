#!/usr/bin/env bash
# gos-map:cmd setup,doctor
# : security test pack (hostile-string canaries / execSync-git static audit / version tripwire / repo identity rescue)
#      + E2E full scenario (Lv3 full cycle → Lv4 dual storage/archive → init --force unarchived guard → P2 claim / same-day -2 dir)
# Env: GOS (CLI path), TESTBASE (scratch root), assert helpers exported by runner.
# This section only echoes ✓/✗ lines — the runner counts pass/fail from the output.
T10A_DIR=""
T10B_DIR=""

# fixture paths follow the CLI supply (task/<id>/) — never hardcode .gos/ root
gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }
gos_plan() { node "$GOS" context plan 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["plan"])' 2>/dev/null; }

t10_setup() { # $1=dir-var-suffix $2=gitignore mode
  local dir="$TESTBASE/test-$(date +%s)-$RANDOM-t10-$1"
  mkdir -p "$dir" && cd "$dir" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/.lock\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
  export GOS_SKIP_SHIP_CHECK=1   # T12 SHIP gate (.changes.md ritual) — unit-tested in T12, not here
  eval "$2=\"\$dir\""
}

t10_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$1"; }

# local helpers (output-only; runner counts ✓/✗)
assert_not_file() {
  local label="$1" fpath="$2"
  if [ -e "$fpath" ]; then echo "  ✗ $label (unexpected file exists: $fpath)"; else echo "  ✓ $label"; fi
}
assert_not_contains() {
  local label="$1" bad="$2" actual="$3"
  if echo "$actual" | grep -q "$bad"; then
    echo "  ✗ $label (unexpected: '$bad')"
    echo "    actual: ${actual:0:160}"
  else
    echo "  ✓ $label"
  fi
}

# ============================================================
# PART 1 — SECURITY (~15 asserts)
# ============================================================
t10_setup A T10A_DIR
echo "--- T10 PART 1: security canaries + static audit + version trip ---"
node "$GOS" init 4 "sec sandbox" --project >/dev/null 2>&1

# --- P1.1: decision add title canary — literal $(...) passed via argv, must be rejected, never executed ---
set +e; OUT=$(node "$GOS" decision add D-01 '$(touch pwned-t10)' --rationale r 2>&1); RC=$?; set -e
assert_exit "decision canary exits 1" 1 "$RC"
assert_not_file "decision canary: no command substitution executed" "pwned-t10"
assert_contains "decision canary names rejection" "rejected" "$OUT"
assert_contains "decision canary points at field" "title" "$OUT"

# --- P1.2: requirement add canary ---
set +e; OUT=$(node "$GOS" requirement add '$(touch pwned-t10b)' 2>&1); RC=$?; set -e
assert_exit "requirement canary exits 1" 1 "$RC"
assert_not_file "requirement canary: no file created" "pwned-t10b"
assert_contains "requirement canary names rejection" "rejected" "$OUT"

# --- P1.3: phase add name canary (badText on name AND goal) ---
set +e; OUT=$(node "$GOS" phase add '$(touch pwned-t10c)' --goal g 2>&1); RC=$?; set -e
assert_exit "phase canary exits 1" 1 "$RC"
assert_not_file "phase canary: no file created" "pwned-t10c"
assert_contains "phase canary names rejection" "rejected" "$OUT"

# --- P1.4: decision amend canary (needs a clean first)
node "$GOS" decision add D-01 "clean base" --rationale r >/dev/null 2>&1
set +e; OUT=$(node "$GOS" decision amend D-01 --title '$(touch pwned-t10d)' 2>&1); RC=$?; set -e
assert_exit "amend canary exits 1" 1 "$RC"
assert_not_file "amend canary: no file created" "pwned-t10d"
assert_contains "amend canary names rejection" "rejected" "$OUT"

# --- P1.5: static audit — NO execSync with git anywhere in the CLI (argv form only) ---
C1=$(grep -cE 'execSync\(.+git' "$GOS" || true)
assert_eq "static: no execSync(...) with git on same line" "0" "$C1"
PAT2='execSync\(\`git|execSync\('"'"'git|execSync\("git'
C2=$(grep -cE "$PAT2" "$GOS" || true)
assert_eq "static: no literal execSync-git forms (backtick/quote)" "0" "$C2"

# --- P1.6: repo identity rescue ( ) — foreign repo_id blocks writes, `gos anchor fix` re-derives
# v4 identity is de-pathed: the state binds via repo_id (remote-URL hash). A
# cloned/copied state carries a foreign id → write-class dies naming the
# mismatch; `gos anchor fix` re-derives from THIS repo's remotes and unblocks.
git remote add origin https://github.com/acme/t10-identity.git
EXPECTED_ID=$(python3 -c "import hashlib; print(hashlib.sha256(b'github.com:443/acme/t10-identity').hexdigest()[:16])")
python3 -c "
import json; s=json.load(open('.gos/state.json')); s['repo_id']='deadbeefdeadbeef'
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" decision add D-99 "blocked" 2>&1); RC=$?; set -e
assert_exit "foreign repo_id blocks write" 1 "$RC"
assert_contains "blocked message names repo identity" "repo identity" "$OUT"
assert_contains "blocked message names stored repo_id" "deadbeefdeadbeef" "$OUT"
assert_contains "blocked message suggests anchor fix" "anchor fix" "$OUT"
set +e; OUT=$(node "$GOS" anchor fix 2>&1); RC=$?; set -e
assert_exit "anchor fix exits 0" 0 "$RC"
assert_contains "anchor fix contract" "anchor re-fixed to" "$OUT"
ID_NOW=$(python3 -c "import json; print(json.load(open('.gos/state.json')).get('repo_id'))")
assert_eq "anchor fix re-derived repo_id from remotes" "$EXPECTED_ID" "$ID_NOW"
assert_not_contains "state carries no project_root after fix" "project_root" "$(cat .gos/state.json)"
set +e; OUT=$(node "$GOS" decision add D-99 "post rescue" 2>&1); RC=$?; set -e
assert_exit "write works after anchor fix" 0 "$RC"

# --- P1.7: version trip — project.json schema 999 → write-class exit 3 (checkpoint save) ---
mkdir -p .gos/project
printf '{"schema_version":999,"last_archived_phase":null,"phases":[],"decisions":[],"requirements":[]}' > .gos/project/project.json
set +e; OUT=$(node "$GOS" checkpoint save --stage BUILD --unit w --done T1 2>&1); RC=$?; set -e
assert_exit "future schema_version trips exit 3" 3 "$RC"
assert_contains "trip names schema_version" "schema_version" "$OUT"
assert_contains "trip suggests upgrade" "upgrade GOS" "$OUT"

t10_teardown "$T10A_DIR"

# ============================================================
# PART 2 — E2E GRAND SCRIPT (~30 asserts, one continuous story)
# ============================================================
t10_setup B T10B_DIR
echo "--- T10 PART 2: E2E grand script ---"

# --- E2E.1: Lv3 init with confirm → status shows Lv3 ---
node "$GOS" init 3 "grand e2e" >/dev/null 2>&1
OUT=$(node "$GOS" status 2>&1)
assert_contains "status shows Lv3" "(Lv3)" "$OUT"

# --- E2E.2: uncovered decision → gate coverage exit 1 naming
node "$GOS" decision add D-01 "use atomic writes" --rationale "crash safety" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" gate coverage 2>&1); RC=$?; set -e
assert_exit "gate coverage exit 1 on uncovered" 1 "$RC"
assert_contains "failure names D-01" "D-01" "$OUT"

# --- E2E.3: fake plan → cover → covered_by P0: → gate coverage passes (truths seeded)
mkdir -p .gos && printf '# plan\n\n#### T1: impl atomic writes\n' > "$(gos_plan)"
set +e; OUT=$(node "$GOS" decision cover D-01 --task T1 2>&1); RC=$?; set -e
assert_exit "cover exits 0" 0 "$RC"
assert_contains "cover contract" "covered by P0:T1" "$OUT"
COV=$(python3 -c "
import json; s=json.load(open('.gos/state.json'))
d=[x for x in s['decisions'] if x['id']=='D-01'][0]
print('%s|%s' % (d['status'], d['covered_by']))")
assert_eq "covered_by recorded P0:T1" "covered|P0:T1" "$COV"
# (T2 migration: string evidence → three-element object [D-30]; artifact must exist)
mkdir -p test/out && echo "grand e2e ok" > test/out/e2e.log
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['observable_truths']=[{'id':'T-01','description':'d','verified':True,'evidence':{'command':'bash test/run-sections.sh','output_excerpt':'308 passed, 0 failed','artifact_path':'test/out/e2e.log'}}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" gate coverage 2>&1); RC=$?; set -e
assert_exit "gate coverage passes after cover" 0 "$RC"

# --- E2E.4: add → amend title → list shows amended
node "$GOS" decision add D-02 "second decision" >/dev/null 2>&1
node "$GOS" decision amend D-02 --title "second amended" >/dev/null 2>&1
OUT=$(node "$GOS" decision list 2>&1)
assert_contains "amended title in list" "second amended" "$OUT"

# --- E2E.5: supersedes → default list hides it, --all shows
node "$GOS" decision add D-03 "supersedes d2" --supersedes D-02 >/dev/null 2>&1
OUT=$(node "$GOS" decision list 2>&1)
assert_not_contains "default list hides superseded D-02" "D-02" "$OUT"
OUT=$(node "$GOS" decision list --all 2>&1)
assert_contains "--all shows superseded D-02" "superseded" "$OUT"
assert_contains "--all shows D-02 row" "| D-02 |" "$OUT"

set +e; OUT=$(node "$GOS" requirement add "extra req" 2>&1); RC=$?; set -e
assert_exit "requirement add exits 0" 0 "$RC"
assert_contains "auto id R-02" "R-02 added" "$OUT"

# --- E2E.7: archive the Lv3 task → no project.json → render skipped message ---
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='DONE'; s['approvals']={'ARCHIVE':'ok'}; s['spec_path']='"$(gos_spec)"'
json.dump(s,open('.gos/state.json','w'),indent=2)"
echo "spec content" > "$(gos_spec)"
echo "- [$(date -u +%F)] e2e scene → e2e lesson" >> .gos/lessons.md
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "Lv3 archive exits 0" 0 "$RC"
assert_contains "non-project archive: render skipped" "(no project.json" "$OUT"
assert_file "Lv3 archive dir + delta.md" "$(find .gos/archive -name delta.md -print -quit 2>/dev/null)"

# --- E2E.8: Lv4 leg — project, phases, dual-store, archive cycle ---
t10_teardown "$T10B_DIR"; t10_setup B T10B_DIR
node "$GOS" init 4 "plat" --project >/dev/null 2>&1
node "$GOS" phase add "P1: core" --goal "g1" >/dev/null 2>&1
node "$GOS" phase add "P2: next" --goal "g2" >/dev/null 2>&1  # pending P2 keeps first archive off the milestone path
python3 -c "
import json; s=json.load(open('.gos/state.json')); s['current_stage']='DONE'
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" phase claim 0 2>&1); RC=$?; set -e
assert_exit "claim 0 allowed (last_archived null)" 0 "$RC"
PH=$(python3 -c "import json; print(json.load(open('.gos/state.json'))['phase_name'])")
assert_eq "state.phase_name = P1: core" "P1: core" "$PH"

node "$GOS" decision add D-01 "use atomic writes" --rationale "crash safety" >/dev/null 2>&1
DUAL=$(python3 -c "
import json
s=json.load(open('.gos/state.json')); p=json.load(open('.gos/project/project.json'))
print('%d|%d' % (len(p['decisions']), len(s['decisions'])))")
assert_eq "D-01 written to BOTH stores (project|state)" "1|1" "$DUAL"

mkdir -p .gos && printf '#### T1: impl\n' > "$(gos_plan)"
node "$GOS" decision cover D-01 --task T1 >/dev/null 2>&1
node "$GOS" requirement add "r" --phase "P1: core" >/dev/null 2>&1
RDUAL=$(python3 -c "
import json
s=json.load(open('.gos/state.json')); p=json.load(open('.gos/project/project.json'))
sp=[r for r in s['requirements'] if r['id']=='R-02']; pp=[r for r in p['requirements'] if r['id']=='R-02']
print('%s|%s' % (sp[0]['phase'] if sp else 'MISSING', pp[0]['phase'] if pp else 'MISSING'))")
assert_eq "R-02 in both stores with phase" "P1: core|P1: core" "$RDUAL"

python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='DONE'; s['approvals']={'ARCHIVE':'ok'}; s['spec_path']='"$(gos_spec)"'
s['intent']['summary']='plat'  # claim replaced intent with the phase goal — force slug 'plat' so the later same-slug archive collides (-2)
json.dump(s,open('.gos/state.json','w'),indent=2)"
echo "spec v4" > "$(gos_spec)"
echo "- [$(date -u +%F)] v4 scene → v4 lesson" >> .gos/lessons.md
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "Lv4 archive exits 0" 0 "$RC"
MERGED=$(python3 -c "
import json
p=json.load(open('.gos/project/project.json'))
d=[x for x in p['decisions'] if x['id']=='D-01'][0]
r=[x for x in p['requirements'] if x['id']=='R-02']
print('|'.join([str(d['covered']), d['covered_by'], str(bool(r)), p['phases'][0]['status'], str(p['last_archived_phase'])]))")
assert_eq "project.json: D-01 covered + R-02 + P1 done + last_archived" \
  "True|P0:T1|True|done|P1: core" "$MERGED"
assert_contains "DECISIONS.md rendered with D-01 row" "| D-01 |" "$(cat .gos/project/DECISIONS.md)"
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "re-archive idempotent exit 0" 0 "$RC"
assert_contains "already-archived message" "already archived" "$OUT"

# --- E2E.9: init --force protection — unarchived spec blocks, committed spec passes ---
# (archive now MOVES spec/plan into the archive dir — SHIP-dogfood fix; rebuild both here)
echo "fresh spec content" > "$(gos_spec)"
echo "# fresh plan" > "$(gos_plan)"
# UNCOMMITTED task-zone spec/plan + --force = HARD block (v0.8-loss protection survives the layout change)
set +e; OUT=$(node "$GOS" init 3 "next task" --force 2>&1); RC=$?; set -e
assert_exit "uncommitted task spec blocks --force" 1 "$RC"
assert_contains "block message names unarchived" "unarchived spec/plan would be overwritten" "$OUT"
# COMMITTED task-zone artifacts + --force = explicit discard (warn): exit 0 + banner
git add "$(gos_spec)" "$(gos_plan)" && git commit -q -m "commit task spec+plan"
set +e; OUT=$(node "$GOS" init 3 "next task" --force 2>&1); RC=$?; set -e
assert_exit "committed task dirs + --force discards with exit 0" 0 "$RC"
assert_contains "discard banner names unarchived task dirs" "discards unarchived task dirs" "$OUT"
# legacy root-level leftovers (pre-migration) still HARD-block
echo "legacy spec" > .gos/spec.md
set +e; OUT=$(node "$GOS" init 3 "another task" --force 2>&1); RC=$?; set -e
assert_exit "legacy root spec blocks --force" 1 "$RC"
assert_contains "block message says unarchived" "unarchived spec/plan would be overwritten" "$OUT"
rm -f .gos/spec.md
git add "$(gos_spec)" "$(gos_plan)" && git commit -q -m "commit spec+plan"
set +e; OUT=$(node "$GOS" init 3 "next task" --force 2>&1); RC=$?; set -e
assert_exit "committed spec → --force proceeds" 0 "$RC"
assert_contains "init success contract" "Initialized" "$OUT"
# restore Lv4 context for the P2 leg (spec/plan still committed-identical → allowed)
set +e; OUT=$(node "$GOS" init 4 "plat" --project --force 2>&1); RC=$?; set -e
assert_exit "Lv4 re-init for P2 leg" 0 "$RC"

# --- E2E.10: claim P2 (P1 archived evidence) → archive same-slug task → -2 suffix dir ---
python3 -c "
import json; s=json.load(open('.gos/state.json')); s['current_stage']='DONE'
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" phase claim 1 2>&1); RC=$?; set -e
assert_exit "claim 1 allowed (P1 archived evidence)" 0 "$RC"
PH2=$(python3 -c "import json; print(json.load(open('.gos/state.json'))['phase_name'])")
assert_eq "state.phase_name = P2: next" "P2: next" "$PH2"

python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='DONE'; s['approvals']={'ARCHIVE':'ok'}; s['spec_path']='"$(gos_spec)"'
s['intent']['summary']='plat'  # same topic as first archive → collision half
s['phase_name']='P1: core'    # structured slug: phase token joins the key — force same phase for -N collision
json.dump(s,open('.gos/state.json','w'),indent=2)"
echo "spec p2" > "$(gos_spec)"
echo "- [$(date -u +%F)] p2 scene → p2 lesson" >> .gos/lessons.md
set +e; OUT=$(GOS_SKIP_SHIP_CHECK=1 node "$GOS" archive 2>&1); RC=$?; set -e
if [ "$RC" -ne 0 ]; then printf '%s\n' "$OUT" | tail -8 >&2; fi   # [T45 debug-keep] failure detail
assert_exit "second same-day archive exits 0" 0 "$RC"
UDATE=$(python3 -c "import datetime; print(datetime.datetime.utcnow().date().isoformat())")
VER=$(node -e "console.log(require(process.env.GOS_ROOT+'/package.json').version)")
assert_file "first archive dir exists (structured slug)" ".gos/archive/$UDATE-v$VER-phase-p1-plat"
assert_file "second archive dir got -2 suffix (structured)" ".gos/archive/$UDATE-v$VER-phase-p1-plat-2"

t10_teardown "$T10B_DIR"
