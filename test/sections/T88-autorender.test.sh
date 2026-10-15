#!/usr/bin/env bash
# gos-map:cmd render
# T88: D-03 auto-render + diff-skip + last-render manifest reconciliation.
# Mutations (decision add/amend/cover, requirement add/claim, phase add/amend/claim)
# render views inline inside the held .gos lock; a no-change mutation writes
# nothing (footer only advances on body change, no backup churn);
# .gos/cache/render-backup/manifest.json gates clobbering — hand-edit,
# fresh-clone (missing manifest) and marker-loss refusals; gos render --force
# is the bypass; render entry sweeps dead-pid .tmp<pid> orphans; the sweep
# classification silently skips manifest.json at the backup root.
# Env: GOS (CLI path), TESTBASE (repo root for sandbox), + assert helpers sourced by runner
T88_DIR=""

gos_plan() { node "$GOS" context plan 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["plan"])' 2>/dev/null; }

t88_setup() {
  T88_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t88"
  mkdir -p "$T88_DIR" && cd "$T88_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/.lock\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t88_seed() {
  python3 -c "
import json
p=json.load(open('.gos/project/project.json'))
p['phases']=[{'name':'P1: core','goal':'ship core','status':'active'}]
p['decisions']=[{'id':'D-01','title':'seed decision','rationale':'r','birth_phase':'P1: core','status':'open','anchor':None,'covered':False,'covered_by':None}]
p['requirements']=[{'id':'R-01','text':'seed req','phase':'P1: core','status':'active'}]
json.dump(p,open('.gos/project/project.json','w'),indent=2)"
}

t88_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T88_DIR"; }

t88_backups() { ls -1 .gos/cache/render-backup 2>/dev/null | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' | wc -l | tr -d ' '; }

t88_newest_backup() { ls -1 .gos/cache/render-backup 2>/dev/null | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' | sort | tail -1; }

t88_setup
echo "--- T88: auto-render + diff-skip + manifest reconciliation ---"

node "$GOS" init 4 "plat" --project >/dev/null 2>&1
t88_seed
node "$GOS" render >/dev/null 2>&1   # baseline: rendered views + manifest exist

# --- T88.1: decision add auto-renders (T4 truth: no manual render needed) ---
set +e; OUT=$(node "$GOS" decision add "auto render probe" --rationale rr 2>&1); RC=$?; set -e
assert_exit "decision add exits 0" 0 "$RC"
assert_contains "add output contract" "✓ Decision D-02 added: auto render probe" "$OUT"
assert_contains "auto-render: new decision in DECISIONS.md without manual render" "auto render probe" "$(cat .gos/project/DECISIONS.md)"
assert_contains "auto-render: new decision id row" "| D-02 " "$(cat .gos/project/DECISIONS.md)"

# --- T88.2: requirement add + phase add auto-render their views ---
set +e; OUT=$(node "$GOS" requirement add "auto req probe" --phase "P1: core" 2>&1); RC=$?; set -e
assert_exit "requirement add exits 0" 0 "$RC"
assert_contains "auto-render: new requirement in REQUIREMENTS.md" "auto req probe" "$(cat .gos/project/REQUIREMENTS.md)"
set +e; OUT=$(node "$GOS" phase add "P2: next" --goal "ship next" 2>&1); RC=$?; set -e
assert_exit "phase add exits 0" 0 "$RC"
assert_contains "auto-render: new phase in ROADMAP.md" "P2: next" "$(cat .gos/project/ROADMAP.md)"

# --- T88.2b: decision cover auto-renders the covered status ---
mkdir -p .gos && printf '#### T1: impl\n' > "$(gos_plan)"
set +e; OUT=$(node "$GOS" decision cover D-02 --task T1 2>&1); RC=$?; set -e
assert_exit "decision cover exits 0" 0 "$RC"
assert_contains "auto-render: covered status in DECISIONS.md" "| covered " "$(cat .gos/project/DECISIONS.md)"

# --- T88.3: no-change mutation — no new backup dir, view byte-identical (footer frozen) ---
B3=$(t88_backups)
SNAP3=$(cat .gos/project/DECISIONS.md)
set +e; OUT=$(node "$GOS" decision amend D-02 --title "auto render probe" 2>&1); RC=$?; set -e
assert_exit "no-change amend exits 0" 0 "$RC"
assert_eq "no-change mutation adds no backup dir" "$B3" "$(t88_backups)"
assert_eq "no-change mutation leaves view byte-identical (footer does not advance)" "$SNAP3" "$(cat .gos/project/DECISIONS.md)"

# --- T88.4: body-changing mutation — exactly one new backup holding PRE-write content ---
B4=$(t88_backups)
node "$GOS" decision amend D-02 --title "retitled probe" >/dev/null 2>&1
assert_eq "changing mutation adds exactly one backup" "$((B4 + 1))" "$(t88_backups)"
NB=$(t88_newest_backup)
assert_contains "backup stores pre-write content" "auto render probe" "$(cat ".gos/cache/render-backup/$NB/DECISIONS.md" 2>/dev/null)"
assert_contains "view now holds the new title" "retitled probe" "$(cat .gos/project/DECISIONS.md)"

# --- T88.5: no-change requirement claim — skip path on the requirement surface ---
B5=$(t88_backups)
SNAP5=$(cat .gos/project/REQUIREMENTS.md)
set +e; OUT=$(node "$GOS" requirement claim R-02 --phase "P1: core" 2>&1); RC=$?; set -e
assert_exit "same-phase claim exits 0" 0 "$RC"
assert_eq "no-change claim adds no backup dir" "$B5" "$(t88_backups)"
assert_eq "no-change claim leaves REQUIREMENTS.md byte-identical" "$SNAP5" "$(cat .gos/project/REQUIREMENTS.md)"

# --- T88.6: hand-edited body → auto-render REFUSES with reconcile instructions ---
printf '| D-77 | hand edit | x | P1: core | open |\n' >> .gos/project/DECISIONS.md
set +e; OUT=$(node "$GOS" decision add "after hand edit" --rationale r 2>&1); RC=$?; set -e
assert_exit "hand-edited body → mutation auto-render refuses (exit 1)" 1 "$RC"
assert_contains "refusal names the offending view" "DECISIONS.md" "$OUT"
assert_contains "refusal reconcile: MANUAL region instruction" "MANUAL" "$OUT"
assert_contains "refusal reconcile: force exit" "render --force" "$OUT"
MUT=$(python3 -c "import json; s=json.load(open('.gos/state.json')); print('D-03' in [d['id'] for d in s['decisions']])")
assert_eq "mutation itself persisted before the render refusal" "True" "$MUT"

# --- T88.7: hand-edited body → direct render refuses too ---
set +e; OUT=$(node "$GOS" render 2>&1); RC=$?; set -e
assert_exit "direct render refuses on hand-edited body" 1 "$RC"
assert_contains "direct refusal also carries the force exit" "render --force" "$OUT"

# --- T88.8: manifest missing while rendered views exist (fresh clone) → refuse ---
rm -f .gos/cache/render-backup/manifest.json
set +e; OUT=$(node "$GOS" render 2>&1); RC=$?; set -e
assert_exit "fresh clone: render refuses without manifest" 1 "$RC"
assert_contains "fresh-clone refusal names the manifest" "manifest" "$OUT"
set +e; OUT=$(node "$GOS" decision add "clone probe" --rationale r 2>&1); RC=$?; set -e
assert_exit "fresh clone: mutation auto-render refuses too" 1 "$RC"

# --- T88.9: gos render --force bypasses and re-establishes the manifest ---
set +e; OUT=$(node "$GOS" render --force 2>&1); RC=$?; set -e
assert_exit "render --force bypasses the refusal" 0 "$RC"
assert_file "manifest re-created by force render" ".gos/cache/render-backup/manifest.json"
if grep -q 'D-77' .gos/project/DECISIONS.md; then echo "  ✗ force render must regenerate the body (hand edit gone)"; FAIL=$((FAIL+1)); else echo "  ✓ force render regenerated the body"; PASS=$((PASS+1)); fi
set +e; OUT=$(node "$GOS" decision add "post force probe" --rationale r 2>&1); RC=$?; set -e
assert_exit "auto-render clean after force reconcile" 0 "$RC"
assert_contains "post-force mutation appears in DECISIONS.md" "post force probe" "$(cat .gos/project/DECISIONS.md)"

# --- T88.10: MANUAL marker present at last render but missing on disk → refuse ---
printf '\n<!-- MANUAL:notes -->\nkeep this note' >> .gos/project/DECISIONS.md
node "$GOS" render >/dev/null 2>&1
assert_contains "sanity: manual note preserved by direct render" "keep this note" "$(cat .gos/project/DECISIONS.md)"
python3 -c "
p='.gos/project/DECISIONS.md'
lines=open(p).read().split('\n')
idx=[i for i,l in enumerate(lines) if l.strip()=='<!-- MANUAL:notes -->'][0]
open(p,'w').write('\n'.join(lines[:idx]))"
set +e; OUT=$(node "$GOS" render 2>&1); RC=$?; set -e
assert_exit "marker loss → render refuses" 1 "$RC"
assert_contains "marker-loss refusal names the MANUAL region" "MANUAL" "$OUT"
node "$GOS" render --force >/dev/null 2>&1

# --- T88.11: render entry sweeps dead-pid .tmp<pid> orphans, keeps live-pid ones ---
DEAD=999989
touch ".gos/project/.DECISIONS.md.tmp$DEAD"
touch ".gos/cache/render-backup/.manifest.json.tmp$DEAD-1234"
touch ".gos/project/.ROADMAP.md.tmp$$"
node "$GOS" render >/dev/null 2>&1
if [ ! -e ".gos/project/.DECISIONS.md.tmp$DEAD" ]; then echo "  ✓ dead-pid view temp swept"; PASS=$((PASS+1)); else echo "  ✗ dead-pid view temp survived"; FAIL=$((FAIL+1)); fi
if [ ! -e ".gos/cache/render-backup/.manifest.json.tmp$DEAD-1234" ]; then echo "  ✓ dead-pid manifest temp swept"; PASS=$((PASS+1)); else echo "  ✗ dead-pid manifest temp survived"; FAIL=$((FAIL+1)); fi
assert_file "live-pid temp untouched by the sweep" ".gos/project/.ROADMAP.md.tmp$$"
rm -f ".gos/project/.ROADMAP.md.tmp$$"

# --- T88.12: sweep classification silently skips manifest.json (not junk) ---
set +e; OUT=$(node "$GOS" render 2>&1); RC=$?; set -e
assert_exit "render with manifest at backup root exits 0" 0 "$RC"
if printf '%s' "$OUT" | grep -q 'manifest.json'; then
  echo "  ✗ manifest.json must be silently skipped (no junk warning)"; FAIL=$((FAIL+1))
else
  echo "  ✓ manifest.json silently skipped by sweep classification"; PASS=$((PASS+1))
fi
assert_file "manifest.json lives at the backup root" ".gos/cache/render-backup/manifest.json"

# --- T88.13: wiring pin — mutations render in-process (dependency inversion:
# decisions installs a hook; task/index.cjs is the composition root wiring it) ---
RPC=$(grep -c 'setAutoRender' "$GOS_ROOT/bin/lib/knowledge/decisions.cjs" 2>/dev/null || true)
WIRE=$(grep -c 'renderProjectViews' "$GOS_ROOT/bin/lib/task/index.cjs" 2>/dev/null || true)
if [ "${RPC:-0}" -ge 1 ] && [ "${WIRE:-0}" -ge 1 ]; then echo "  ✓ mutation render wiring holds (decisions hook ${RPC}, task wiring ${WIRE})"; PASS=$((PASS+1)); else echo "  ✗ decisions.cjs lost its renderProjectViews call"; FAIL=$((FAIL+1)); fi

t88_teardown
