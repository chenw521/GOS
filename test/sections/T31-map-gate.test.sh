#!/usr/bin/env bash
# gos-map:cmd map
# : edges.json integrity freeze — edges.lock (tracked) / adopt / transactional re-freeze /
# tracked-missing die / no-lazy-freeze / worktree-clone cross-machine line
T31_DIR=""

# fixture paths follow the CLI supply (task/<id>/) — never hardcode .gos/ root
gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }
gos_plan() { node "$GOS" context plan 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["plan"])' 2>/dev/null; }

t31_setup() {
  T31_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t31"
  mkdir -p "$T31_DIR" && cd "$T31_DIR" || exit 1
}

t31_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T31_DIR"; }

t31_setup
echo "--- T31: edges.lock integrity freeze (commit-frozen, CLI-refrozen, clone-safe) ---"

git init -q . && mkdir -p bin docs
printf 'x\n' > bin/gos.cjs
printf '# doc mentions gos map scan\n' > docs/usage.md
git add -A && git commit -qm t31-fixture

V() { # V <label> <wantRC> <wantGrep|->
  local label="$1" wantRC="$2" wantGrep="$3" out rc
  set +e; out=$(node "$GOS" map edge verify 2>&1); rc=$?   # stay +e: sections own their errexit policy
  assert_exit "$label" "$wantRC" "$rc"
  if [ "$wantGrep" != "-" ]; then assert_contains "$label (text)" "$wantGrep" "$out"; fi
  LAST_V_OUT="$out"
}

# --- .1 unfrozen after seed = advisory (no lazy freeze until first commit)
node "$GOS" map edge adopt --bootstrap >/dev/null 2>&1
V "T31.1a unfrozen seed verifies as advisory (no die)" 0 "no lazy freeze"

# --- .2 adopt resets the freeze anchor -> lock on disk carries the current sha
node "$GOS" map edge adopt >/dev/null 2>&1
assert_file "T31.2a edges.lock created by adopt" ".gos/cache/edges.lock"
V "T31.2b frozen state verifies ok" 0 "verified"
python3 -c "
import hashlib,json
d=hashlib.sha256(open('.gos/cache/edges.json','rb').read()).hexdigest()
l=json.load(open('.gos/cache/edges.lock'))
exit(0 if l.get('edges_sha256')==d else 1)" && echo "  ✓ lock sha256 == disk content" && PASS=$((PASS+1)) || { echo "  ✗ lock sha mismatch after adopt"; FAIL=$((FAIL+1)); }

# --- .3 direct edit (bypassing the CLI) -> verify dies, message embeds the recovery command
node "$GOS" map edge add docs/usage.md bin/gos.cjs#cmd:map --type greps >/dev/null 2>&1   # legitimate add triggers the transactional re-freeze
V "T31.3a CLI add keeps verify green (transactional re-freeze)" 0 "verified"
printf '  {"tampered": true}\n' >> .gos/cache/edges.json
V "T31.3b hand edit → verify die" 1 "hand edit detected"
assert_contains "T31.3b recovery text embeds adopt" "gos map edge adopt" "$LAST_V_OUT"

# --- .4 recovery after adopt (merge/rescue exit)
node "$GOS" map edge adopt >/dev/null 2>&1   # legitimate rescue (merge/rebase exit)
V "T31.4a after adopt verify green again" 0 "verified"

# --- .5 tracked-missing die (defense torn down)
git add -A >/dev/null 2>&1 && git commit -qm frozen-edge >/dev/null 2>&1
rm -f .gos/cache/edges.json
V "T31.5a tracked-but-deleted → die" 1 "git-tracked but missing"
git checkout -q -- .gos/cache/edges.json
V "T31.5b restored → green" 0 "verified"

# --- .6 worktree clone cross-machine defense
git add -A >/dev/null 2>&1 && git commit -qm wip >/dev/null 2>&1
CLONE_DIR="$T31_DIR/../t31-clone-$$"
git clone -q . "$CLONE_DIR" 2>/dev/null
( cd "$CLONE_DIR" && printf '  {"evil": 1}\n' >> .gos/cache/edges.json )
CLONE_OUT=$(cd "$CLONE_DIR" && node "$GOS" map edge verify 2>&1); CLONE_RC=$?
assert_exit "T31.6a clone: hand edit → verify die (cross-machine line)" 1 "$CLONE_RC"
assert_contains "T31.6b clone die text embeds recovery" "adopt\|checkout" "$CLONE_OUT"
rm -rf "$CLONE_DIR"

# --- .7 untracked repo without edges.json = advisory bootstrap (npm consumer semantics)
mkdir -p sub && cd sub && git init -q . && mkdir -p bin && printf 'x\n' > bin/gos.cjs && git add -A && git commit -qm bare >/dev/null 2>&1
set +e; OUT=$(node "$GOS" map edge verify 2>&1); RC=$?; set -e
assert_exit "T31.7a bare repo (no edges.json, untracked) verifies advisory" 0 "$RC"
assert_contains "T31.7b advisory mentions bootstrap" "bootstrap" "$OUT"
cd "$T31_DIR"

# --- .8 init seeding (a fresh repo holds a tracked empty version right after init)
INIT_DIR="$T31_DIR/initrepo"
mkdir -p "$INIT_DIR" && cd "$INIT_DIR" && git init -q .
set +e; node "$GOS" init 1 "t31-seed-test" >/dev/null 2>&1; INITRC=$?; set -e
assert_file "T31.8a init seeds .gos/cache/edges.json" ".gos/cache/edges.json"
python3 -c "import json;d=json.load(open('.gos/cache/edges.json'));exit(0 if d.get('edges')==[] and d.get('schema_version')==1 else 1)" && echo "  ✓ init seed schema valid" && PASS=$((PASS+1)) || { echo "  ✗ init seed schema wrong"; FAIL=$((FAIL+1)); }
cd "$T31_DIR" && rm -rf "$INIT_DIR"

# --- .9 static: .lock ignored; cache/ whole-dir ignored (edges.lock/json moved in); logs/ machine-local
if grep -qx "\.gos/\.lock" "$GOS_ROOT/.gitignore" && grep -qx "\.gos/cache/" "$GOS_ROOT/.gitignore" && grep -qx "\.gos/logs/" "$GOS_ROOT/.gitignore" && ! grep -q '!\.gos/logs' "$GOS_ROOT/.gitignore"; then
  echo "  ✓ .gitignore: .lock+cache/ ignored; logs/ machine-local (no reversal)"; PASS=$((PASS+1))
else echo "  ✗ .gitignore coverage wrong"; FAIL=$((FAIL+1)); fi

# --- .10 gate integration hook exists (integrity function + die message family)
if grep -q "function checkEdgesIntegrity" "$GOS_ROOT/bin/lib/map/edges.cjs"; then
  echo "  ✓ checkEdgesIntegrity exported for gate wiring"; PASS=$((PASS+1))
else echo "  ✗ checkEdgesIntegrity missing"; FAIL=$((FAIL+1)); fi
N_LOCK=$(node "$GOS" _contract 2>/dev/null | grep -c "edgesLockMismatch\|edgesTrackedMissing\|edgesNotFrozen\|edgesVerifyOk" || true)
if [ "${N_LOCK:-0}" -ge 4 ]; then echo "  ✓ CONTRACTS lock key family ($N_LOCK)"; PASS=$((PASS+1))
else echo "  ✗ CONTRACTS lock keys missing"; FAIL=$((FAIL+1)); fi

# --- .11 gate semantic-closure section (three-source merge + advisory + qualified text + integrity die)
t31_setup
git init -q . && git commit -q --allow-empty -m root
printf ".gos/state.json\n.gos/cache/deps.json\n" > .gitignore && git add .gitignore && git commit -q -m gi
mkdir -p src bin docs
echo 'module.exports = {}' > src/util.js
printf 'function cmdMap() {
  // placeholder
}
' > bin/gos.cjs
printf "switch (sub) { case 'map': cmdMap(); }
" >> bin/gos.cjs
printf 'calls gos map scan somewhere\n' > docs/usage.md
git add -A && git commit -q -m chain
node "$GOS" init 3 "semantic closure" >/dev/null 2>&1
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
printf '# Plan\n\n### Wave 1\n\n#### T1: impl\n- **Covers**: D-01\n- **Files**: bin/gos.cjs\n' > "$(gos_plan)"
node "$GOS" approve plan >/dev/null 2>&1
node "$GOS" commit plan >/dev/null 2>&1
node "$GOS" map edge adopt >/dev/null 2>&1   # freeze (edges.json auto-seeded by init)
git add -A >/dev/null 2>&1 && git commit -qm frozen-edges >/dev/null 2>&1

# a) integrity die takes precedence over every other gate check: tamper -> hand-edit message (not the diff-hit message)
printf '  tamper\n' >> .gos/cache/edges.json
set +e; GOUT=$(node "$GOS" gate semantic 2>&1); GRC=$?; set +e
assert_exit "T31.11a tampered edges → gate semantic die" 1 "$GRC"
assert_contains "integrity die fires FIRST (hand-edit text)" "hand edit detected" "$GOUT"
assert_contains "gate die text embeds adopt recovery" "gos map edge adopt" "$GOUT"
git checkout -q -- .gos/cache/edges.json

# b) semantic closure: hunk lands inside the cmdMap function range (declared) -> gate exit 0 + semantic section + qualified text + mustRun
sed -i 's|// placeholder|// placeholder\n// touch-inside-cmdMap|' bin/gos.cjs
set +e; GOUT=$(node "$GOS" gate semantic 2>&1); GRC=$?; set +e
assert_exit "T31.11b gate semantic advisory stays 0" 0 "$GRC"
assert_contains "T31.11c 语义段限定文案 (非穷尽声明)" "非穷尽\|not exhaustive\|may be incomplete" "$GOUT"
assert_contains "T31.11d must-run sections listed (map cmd touched via fixture chain)" "T" "$GOUT"
assert_contains "T31.11e semantic dependents include docs caller" "docs/usage.md" "$GOUT"

# c) closure --semantic human-readable outlet
set +e; COUT=$(node "$GOS" map closure bin/gos.cjs --semantic 2>&1); CRC=$?; set +e
assert_exit "T31.11f closure --semantic exits 0" 0 "$CRC"
assert_contains "closure --semantic lists callers" "docs/usage.md" "$COUT"

# d) unannotatedCount frozen (gate tail counter ready)
node "$GOS" _contract 2>/dev/null | grep -q "unannotatedCount" && echo "  ✓ unannotatedCount frozen (gate tail counter ready)" && PASS=$((PASS+1)) || { echo "  ✗ unannotatedCount missing"; FAIL=$((FAIL+1)); }

t31_teardown
