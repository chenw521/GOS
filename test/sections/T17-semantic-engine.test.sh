#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/gate.cjs#fn:cmdGate
# gos-map:cmd gate
# : semantic engine + gate semantic minimal command
# Covers: plan — bidirectional coverage / diff-hit (task_head baseline, CJK NUL)
#     / allowlist strength+exemptions / closureFn interface slot / degradation banners
# Env: GOS (CLI path), TESTBASE (isolated base), assert helpers sourced by runner
T17_DIR=""

# fixture paths follow the CLI supply (task/<id>/) — never hardcode .gos/ root
gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }
gos_plan() { node "$GOS" context plan 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["plan"])' 2>/dev/null; }

t17_setup() {
  T17_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t17"
  mkdir -p "$T17_DIR" && cd "$T17_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

# full Lv3 fixture: init→think→plan committed (plan_snapshot frozen), added
# usage: t17_plan "<covers>" "<files>"
t17_plan() {
  node "$GOS" init 3 "semantic engine" >/dev/null 2>&1
  node "$GOS" commit intent >/dev/null 2>&1
  cat > "$(gos_spec)" <<'SPECEOF'
spec v1 — fixture

## D-01 core
| Option | Premise |
|:--|:--|
| impl a | fixture |
| impl b | fixture |
why-not: impl b — fixture discard
SPECEOF
  node "$GOS" decision add D-01 "core" --rationale "r" >/dev/null 2>&1
  node "$GOS" approve think >/dev/null 2>&1
  node "$GOS" commit think >/dev/null 2>&1
  cat > "$(gos_plan)" <<PLANEOF
# Plan

### Wave 1

#### T1: impl core
- **Covers**: $1
- **Files**: $2
PLANEOF
  node "$GOS" approve plan >/dev/null 2>&1
  node "$GOS" commit plan >/dev/null 2>&1
}

t17_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T17_DIR"; }

t17_setup
echo "--- T17.A: bidirectional coverage [B-2] ---"

# --- A1: ghost in plan Covers (not in state.decisions) → exit 1, names
t17_plan "D-01, D-99" "src/a.js"
mkdir -p src && echo x > src/a.js
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "A1 ghost D-99 → exit 1" 1 "$RC"
assert_contains "A1 failure names D-99" "D-99" "$OUT"

# --- A2: decision in state, covered by no task → exit 1
t17_teardown; t17_setup
t17_plan "D-01" "src/a.js"
node "$GOS" decision add D-02 "uncovered" --rationale "r" >/dev/null 2>&1
mkdir -p src && echo x > src/a.js
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "A2 uncovered decision → exit 1" 1 "$RC"
assert_contains "A2 failure names D-02 not covered" "D-02" "$OUT"

# --- A3: ghost in Covers (no such requirement) → exit 1, names
t17_teardown; t17_setup
t17_plan "D-01, R-99" "src/a.js"
mkdir -p src && echo x > src/a.js
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "A3 ghost R-99 → exit 1" 1 "$RC"
assert_contains "A3 failure names R-99" "R-99" "$OUT"

# --- A4: clean exact coverage + diff hit → exit 0 + ✓ lines + downgrade banner ---
t17_teardown; t17_setup
t17_plan "D-01" "src/a.js"
mkdir -p src && echo x > src/a.js
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "A4 exact coverage + hit → exit 0" 0 "$RC"
assert_contains "A4 bidirectional ✓ line" "bidirectional" "$OUT"
assert_contains "A4 semantic ✓ arms the downgrade banner (B-3)" "syntax+consistency" "$OUT"

# --- A5: parser hygiene — prose in Covers + backticks/line-refs in Files parse clean ---
# Covers keep only D-NN/R-NN tokens (prose like "goal (f)" is not a reference);
# Files strip backticks and trailing :NN so snapshot paths match raw git paths.
t17_teardown; t17_setup
t17_plan "D-01 (core boundary), goal (f)" '`src/a.js`, `docs/notes.md:31`'
mkdir -p src && echo x > src/a.js
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "A5 prose Covers + decorated Files → exit 0" 0 "$RC"
if printf '%s\n' "$OUT" | grep -q "ghost\|undeclared-diff-file"; then
  echo "  ✗ A5 parser leaked prose/backtick fragments"; FAIL=$((FAIL+1))
else
  echo "  ✓ A5 no ghost/undeclared fragments"; PASS=$((PASS+1))
fi

# --- A6: glob Files — a module-batch glob declares every matching changed path ---
t17_teardown; t17_setup
t17_plan "D-01" "src/*.js"
mkdir -p src && echo x > src/a.js && echo y > src/b.js
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "A6 glob Files hit + declared → exit 0" 0 "$RC"

# ============================================================
echo "--- T17.B: diff hit / degradation [B-4] ---"

# --- B1: declared Files, zero diff hits → exit 1 (suspicious no-op) ---
t17_teardown; t17_setup
t17_plan "D-01" "src/a.js, src/b.js"
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "B1 zero-hit → exit 1" 1 "$RC"
assert_contains "B1 zero-hit message names task T1" "T1" "$OUT"
assert_contains "B1 zero-hit wording" "zero-hit" "$OUT"

# --- B2: undeclared file outside allowlist in diff → exit 1 ---
t17_teardown; t17_setup
t17_plan "D-01" "src/a.js"
mkdir -p src && echo x > src/a.js && echo x > src/zzz.js
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "B2 undeclared file → exit 1" 1 "$RC"
assert_contains "B2 failure names undeclared zzz.js" "zzz.js" "$OUT"
assert_contains "B2 undeclared wording" "undeclared" "$OUT"

# --- B3: task with NO Files line → warn only, not failure ---
t17_teardown; t17_setup
t17_plan "D-01" ""
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "B3 no-Files task → warn not fail (exit 0)" 0 "$RC"
assert_contains "B3 warn line names no Files" "no Files" "$OUT"

# --- B4: non-git sandbox → diff skip line, exit 0 ---
# (TESTBASE lives INSIDE the GOS worktree repo — clip git's upward discovery, / convention)
t17_teardown
T17_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t17n"
mkdir -p "$T17_DIR" && cd "$T17_DIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TESTBASE"   # stop git from discovering the enclosing repo
node "$GOS" init 3 "plain dir" >/dev/null 2>&1
node "$GOS" decision add D-01 "core" --rationale "r" >/dev/null 2>&1
cat > "$(gos_plan)" <<'PLANEOF'
# Plan

### Wave 1

#### T1: impl core
- **Covers**: D-01
- **Files**: src/a.js
PLANEOF
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
unset GIT_CEILING_DIRECTORIES
assert_exit "B4 non-git → exit 0 (no diff fail)" 0 "$RC"
assert_contains "B4 not-git skip line" "skip" "$OUT"

# --- B5: plan.md missing → skip banner, no crash ---
t17_teardown; t17_setup
node "$GOS" init 3 "no plan" >/dev/null 2>&1
node "$GOS" decision add D-01 "core" --rationale "r" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "B5 plan missing → exit 0 skip" 0 "$RC"
assert_contains "B5 skip banner mentions plan.md missing" "plan.md missing" "$OUT"

# --- B6: zero-commit repo → task_head_pending → skip note, exit 0 ---
t17_teardown
T17_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t17z"
mkdir -p "$T17_DIR" && cd "$T17_DIR" || exit 1
git init -q .
node "$GOS" init 3 "zero commit" >/dev/null 2>&1
node "$GOS" decision add D-01 "core" --rationale "r" >/dev/null 2>&1
cat > "$(gos_plan)" <<'PLANEOF'
# Plan

### Wave 1

#### T1: impl core
- **Covers**: D-01
- **Files**: src/a.js
PLANEOF
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "B6 pending baseline → exit 0 skip" 0 "$RC"
assert_contains "B6 pending skip note keeps word skip" "skip" "$OUT"

# ============================================================
echo "--- T17.C: allowlist strength + exemptions [B-5] ---"

# --- C1: .changes.md touched (not in Files) → allowlisted, exit 0 ---
t17_teardown; t17_setup
t17_plan "D-01" "src/a.js"
mkdir -p src && echo x > src/a.js && echo "- change" > .changes.md
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "C1 .changes.md allowlisted → exit 0" 0 "$RC"

# --- C2: truth artifact_path exempt from diff + exists → exit 0 ---
t17_teardown; t17_setup
t17_plan "D-01" "src/a.js"
mkdir -p src out && echo x > src/a.js && echo log > out/t17.log
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['observable_truths']=[{'id':'T-01','description':'ok','verified':True,
  'evidence':{'command':'bash x.sh','output_excerpt':'3 passed, 0 failed','artifact_path':'out/t17.log'}}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "C2 artifact_path diff-exempt + exists → exit 0" 0 "$RC"
assert_contains "C2 artifact existence ✓ line" "artifact" "$OUT"

# --- C3: verified truth artifact_path missing on disk → exit 1 (pathExists) ---
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['observable_truths'][0]['evidence']['artifact_path']='out/gone.log'
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "C3 artifact gone → exit 1" 1 "$RC"
assert_contains "C3 names not found on disk" "not found on disk" "$OUT"

# --- C4: state.semantic.allowlist ['**'] → exit 1 pattern too broad ---
# (restore artifact first — validateState would die on the missing path before
#  the allowlist strength check ever loads)
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['observable_truths'][0]['evidence']['artifact_path']='out/t17.log'
s['semantic']={'allowlist':['**']}
json.dump(s,open('.gos/state.json','w'),indent=2)"
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "C4 bare ** allowlist → exit 1" 1 "$RC"
assert_contains "C4 pattern too broad wording" "pattern too broad" "$OUT"

# ============================================================
echo "--- T17.D: CJK filenames via NUL parsing [B-4 ④/R2-5] ---"

# --- D1: CJK declared file is the ONLY hit → pass proves it entered the diff set ---
t17_teardown; t17_setup
t17_plan "D-01" "src/a.js, src/中文.js"
mkdir -p src && echo x > "src/中文.js"
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "D1 CJK file counts as task hit → exit 0" 0 "$RC"

# --- D2: undeclared CJK file → exit 1, raw CJK name in message (quotepath off) ---
t17_teardown; t17_setup
t17_plan "D-01" "src/a.js"
mkdir -p src && echo x > src/a.js && echo x > "src/未声明.js"
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "D2 undeclared CJK → exit 1" 1 "$RC"
assert_contains "D2 failure names raw CJK path" "src/未声明.js" "$OUT"

# ============================================================
echo "--- T17.E: closureFn interface slot [B-6] ---"
SRC="$(cat "$GOS")$(cat "$GOS_ROOT/bin/lib/ops/gate.cjs")"
assert_contains "E1 diffHitCheck signature reserves closureFn = null" "closureFn = null" "$SRC"

t17_teardown
