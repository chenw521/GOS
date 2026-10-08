#!/usr/bin/env bash
# gos-map:cmd gate,map
# T22: gate in-memory recompute of impactClosure three states — N>0 two lines / impactClean / impactVacuous +
#      delete/rename dependents counted + deps.json cache independence + byte stability + lexicographic tie-break
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner
T22_DIR=""

# [Phase W T5] fixture paths follow the CLI supply (task/<id>/) — never hardcode .gos/ root
gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }
gos_plan() { node "$GOS" context plan 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["plan"])' 2>/dev/null; }

t22_setup() {
  T22_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t22"
  mkdir -p "$T22_DIR" && cd "$T22_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/deps.json\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

# usage: t22_plan "<files-csv>"  → full Lv3 fixture with D-01 covered by T1
t22_plan() {
  node "$GOS" init 3 "impact closure" >/dev/null 2>&1
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
- **Covers**: D-01
- **Files**: $1
PLANEOF
  node "$GOS" approve plan >/dev/null 2>&1
  node "$GOS" commit plan >/dev/null 2>&1
}

t22_chain() {   # lib chain committed: util ← a ← b (a requires util, b requires a)
  mkdir -p src
  echo 'module.exports = {}' > src/util.js
  printf "const u = require('./util');\nmodule.exports = { u };\n" > src/a.js
  printf "const a = require('./a');\nmodule.exports = { a };\n" > src/b.js
  git add src && git commit -q -m chain
}

t22_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T22_DIR"; }

t22_setup
echo "--- T22: gate impactClosure three states ---"

# --- T22.1: N>0 → impactClosure + impactHintRun both emitted + exit 0 (advisory, does not fail) ---
# Chain committed; touching only declared util → diff={util}; impacted {a,b} undeclared → N=2; top=util (2 dependents)
t22_chain
t22_plan "src/util.js"
node "$GOS" map scan >/dev/null 2>&1        # deps.json exists at this point (gitignore pre-seeded by setup)
printf "// touch\n" >> src/util.js
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "N>0 advisory keeps exit 0" 0 "$RC"
assert_contains "impactClosure line (N=2: a+b undeclared)" "impact closure: 2 diff dependents not covered by task Files (advisory, regex-based, may be incomplete)" "$OUT"
assert_contains "impactHintRun line follows (top=util, 2 dependents)" "run: gos map closure src/util.js --print0" "$OUT"

# --- T22.2: impactClean state — all impacted files declared ---
t22_teardown; t22_setup
t22_chain
t22_plan "src/a.js, src/b.js, src/util.js"
node "$GOS" map scan >/dev/null 2>&1
printf "// touch\n" >> src/util.js
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "impactClean keeps exit 0" 0 "$RC"
assert_contains "impactClean exact" "impact closure: 0 uncovered dependents (regex-based, may be incomplete)" "$OUT"
if echo "$OUT" | grep -q "diff dependents not covered"; then
  echo "  ✗ impactClosure line must not appear in clean state"; FAIL=$((FAIL+1))
else echo "  ✓ no impactClosure line when clean"; PASS=$((PASS+1)); fi

# --- T22.3: impactVacuous state — zero scannable sources ---
t22_teardown; t22_setup
t22_plan "README.md"
echo hello > README.md
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "vacuous keeps exit 0" 0 "$RC"
assert_contains "impactVacuous exact (0 scannable sources)" "impact closure vacuous (0 scannable sources OR diff fully allowlisted) — NOT evidence of clean" "$OUT"

# --- T22.4: deleting a depended-on file → its dependents count into N ---
# Files={util,a}; rm util → diff={util(del)}; transitive impact {a,b}, undeclared={b} → N=1
t22_teardown; t22_setup
t22_chain
t22_plan "src/util.js, src/a.js"
node "$GOS" map scan >/dev/null 2>&1
rm src/util.js
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "deleted-dependency case exits 0" 0 "$RC"
assert_contains "dependents of deleted file counted (N=1: b undeclared)" "impact closure: 1 diff dependents not covered by task Files" "$OUT"

# --- T22.5: rename pair (delete+add under --no-renames) → delete-side dependents count into N ---
# Files holds delete-side a and add-side a2 (diff-hit on both sides); git mv a→a2 → diff={a(del),a2(add)};
# b still references './a' → delete-side impact reaches b (dangling virtual edge); closure={a,a2,b}, undeclared={b} → N=1
t22_teardown; t22_setup
t22_chain
t22_plan "src/util.js, src/a2.js, src/a.js"
node "$GOS" map scan >/dev/null 2>&1
git mv src/a.js src/a2.js
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "rename-pair case exits 0" 0 "$RC"
assert_contains "deleted side dependents counted (N=1: b undeclared via dangling)" "impact closure: 1 diff dependents not covered by task Files" "$OUT"
assert_contains "top-impact-file = deleted side (its dependents)" "run: gos map closure src/a.js --print0" "$OUT"

# --- T22.6: cache independence — gate output byte-identical with and without deps.json + unchanged after gate ---
t22_teardown; t22_setup
t22_chain
t22_plan "src/a.js"
node "$GOS" map scan >/dev/null 2>&1
H1=$(sha256sum .gos/cache/deps.json | cut -d' ' -f1)
printf "// touch\n" >> src/a.js               # real modification of a declared file
set +e; OUT1=$(node "$GOS" gate semantic 2>&1); RC1=$?; set -e
H2=$(sha256sum .gos/cache/deps.json | cut -d' ' -f1)
assert_eq "gate leaves deps.json byte-identical" "$H1" "$H2"
rm .gos/cache/deps.json
set +e; OUT2=$(node "$GOS" gate semantic 2>&1); RC2=$?; set -e
assert_eq "gate exit identical without deps.json" "$RC1" "$RC2"
if [ "$OUT1" = "$OUT2" ]; then echo "  ✓ gate output byte-identical across deps.json presence"; PASS=$((PASS+1)); else echo "  ✗ gate output differs when deps.json absent"; FAIL=$((FAIL+1)); fi

# --- T22.7: top-impact-file tie → lexicographically smallest + stable output across runs ---
# Symmetric double chains x←p and y←r (1 dependent each); touching declared x,y → tie → winner src/x.js
t22_teardown; t22_setup
mkdir -p src
echo 'module.exports = {}' > src/x.js
printf "const u = require('./x');\nmodule.exports = { u };\n" > src/p.js
echo 'module.exports = {}' > src/y.js
printf "const v = require('./y');\nmodule.exports = { v };\n" > src/r.js
git add src && git commit -q -m chains
t22_plan "src/x.js, src/y.js"
node "$GOS" map scan >/dev/null 2>&1
printf "// t\n" >> src/x.js; printf "// t\n" >> src/y.js
set +e; OUT_A=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "tie case exits 0" 0 "$RC"
assert_contains "tie-break picks lexicographic smallest (src/x.js)" "run: gos map closure src/x.js --print0" "$OUT_A"
set +e; OUT_B=$(node "$GOS" gate semantic 2>&1); OUT_C=$(node "$GOS" gate semantic 2>&1); set -e
if [ "$OUT_A" = "$OUT_B" ] && [ "$OUT_B" = "$OUT_C" ]; then echo "  ✓ 3 repeated runs byte-stable"; PASS=$((PASS+1)); else echo "  ✗ nondeterministic gate output"; FAIL=$((FAIL+1)); fi

t22_teardown
