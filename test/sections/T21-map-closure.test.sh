#!/usr/bin/env bash
# gos-map:cmd map
# : map closure/show — bidirectional closure + read-only print0 + out-of-graph refusal +
#      three staleness dimensions + root-anchored input normalization + deleted-node traversal
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner
T21_DIR=""

t21_setup() {
  T21_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t21"
  mkdir -p "$T21_DIR" && cd "$T21_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  echo ".gos/state.json" > .gitignore && git add .gitignore && git commit -q -m gi
  mkdir -p lib app
  echo 'module.exports = {}' > lib/util.js
  printf "const u = require('./util');\nmodule.exports = { u };\n" > lib/a.js
  printf "import x from './a';\nexport const b = x;\n" > lib/b.ts
  printf "import './b';\n" > lib/entry.mjs
  cat > app/main.py <<'EOF'
import lib.helper
from lib.util import thing


def f():
    import lib.deep
EOF
  echo '# helper' > lib/helper.py
  echo '# util' > lib/util.py
  echo '# deep' > lib/deep.py
  git add -A && git commit -q -m fixture
}

t21_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T21_DIR"; }

t21_setup
echo "--- T21: map closure/show semantics ---"
node "$GOS" map scan >/dev/null 2>&1

# --- .1: reverse closure (default) — full transitive dependents listed + input itself included
set +e; OUT=$(node "$GOS" map closure lib/util.js 2>/dev/null); RC=$?; set -e
assert_exit "reverse closure exits 0" 0 "$RC"
for f in lib/util.js lib/a.js lib/b.ts lib/entry.mjs; do
  assert_contains "reverse closure contains $f" "$f" "$OUT"
done
assert_contains "util.js dependents chain (entry.mjs)" "lib/entry.mjs" "$OUT"
# py side is a separate node (lib/util.py ≠ lib/util.js — same stem, different extension)
set +e; OUT=$(node "$GOS" map closure lib/util.py 2>/dev/null); RC=$?; set -e
assert_exit "py reverse closure exits 0" 0 "$RC"
assert_contains "py closure includes lib/util.py itself" "lib/util.py" "$OUT"
assert_contains "py closure includes app/main.py (import lib.util)" "app/main.py" "$OUT"

set +e; OUT=$(node "$GOS" map closure lib/entry.mjs --forward 2>/dev/null); RC=$?; set -e
assert_exit "forward closure exits 0" 0 "$RC"
for f in lib/entry.mjs lib/b.ts lib/a.js lib/util.js; do
  assert_contains "forward closure contains $f" "$f" "$OUT"
done
if echo "$OUT" | grep -q "app/main.py"; then
  echo "  ✗ forward closure must not cross into unrelated subtree (main.py)"; FAIL=$((FAIL+1))
else
  echo "  ✓ forward closure stays in entry.mjs subtree"; PASS=$((PASS+1))
fi

# --- .3: --print0 — NUL-separated bare paths, zero banners, exit 0
set +e; P0=$(node "$GOS" map closure lib/util.js --print0 2>/dev/null | tr '\0' '\n'); RC=$?; set -e
assert_exit "print0 exits 0" 0 "$RC"
assert_contains "print0 lists dependents" "lib/entry.mjs" "$P0"
RAW=$(node "$GOS" map closure lib/util.js --print0 2>/dev/null)
if echo "$RAW" | grep -q "regex-based\|Next:\|stale"; then
  echo "  ✗ print0 output contains banner/hint lines"; FAIL=$((FAIL+1))
else
  echo "  ✓ print0 output free of banners/hints"; PASS=$((PASS+1))
fi

# --- .4: out-of-graph path — exit 1 + closureUnknownPath verbatim; print0 emits zero bytes
set +e; OUT=$(node "$GOS" map closure lib/typo.js 2>&1); RC=$?; set -e
assert_exit "unknown path exits 1" 1 "$RC"
assert_contains "closureUnknownPath exact" "closure input not in graph (lib/typo.js) — typo, deleted, or not in scan set — refusing vacuous answer" "$OUT"
set +e; P0OUT=$(node "$GOS" map closure lib/typo.js --print0 2>/dev/null); RC=$?; set -e
assert_exit "unknown path print0 exits 1" 1 "$RC"
if [ -z "$P0OUT" ]; then echo "  ✓ unknown path print0 emits zero bytes"; PASS=$((PASS+1)); else echo "  ✗ print0 emitted bytes on error: '$P0OUT'"; FAIL=$((FAIL+1)); fi

# --- .5: print0 is read-only — no disk writes while stale (read-only .gos directory)
git commit -q --allow-empty -m bump          # HEAD advances → cache goes stale
chmod a-w .gos
set +e; OUT=$(node "$GOS" map closure lib/util.js --print0 2>/dev/null | tr '\0' '\n'); RC=$?; set -e
assert_exit "print0 works in read-only .gos (in-memory recompute)" 0 "$RC"
assert_contains "print0 read-only still answers" "lib/entry.mjs" "$OUT"
chmod u+w .gos

# --- .6: HEAD advance → interactive auto-rescan (cache semantics)
CURHEAD=$(git rev-parse HEAD)
node "$GOS" map closure lib/util.js >/dev/null 2>&1
AFTER=$(python3 -c "import json; print(json.load(open('.gos/cache/deps.json'))['head'])")
assert_eq "interactive auto-rescan advances head anchor" "$CURHEAD" "$AFTER"

# --- .7: --no-refresh + staleNote (only when the path is in the graph)
git commit -q --allow-empty -m bump2
set +e; OUT=$(node "$GOS" map closure lib/util.js --no-refresh 2>/dev/null); RC=$?; set -e
assert_exit "--no-refresh serves stale cache, exit 0" 0 "$RC"
assert_contains "staleNote exact" "stale deps.json (head or worktree anchor mismatch) — cached results used (--no-refresh)" "$OUT"
assert_contains "stale results still present" "lib/entry.mjs" "$OUT"
# Out-of-graph wins: --no-refresh + typo → unknown-path text instead of staleNote
set +e; OUT=$(node "$GOS" map closure lib/typo.js --no-refresh 2>&1); RC=$?; set -e
assert_exit "unknown beats stale (priority order)" 1 "$RC"
assert_contains "unknown-path text wins over staleNote" "closure input not in graph" "$OUT"
if echo "$OUT" | grep -q "stale deps.json"; then
  echo "  ✗ staleNote leaked on unknown-path case (R3-F12 violation)"; FAIL=$((FAIL+1))
else
  echo "  ✓ no staleNote when path unknown"; PASS=$((PASS+1))
fi

# --- .8: dirty worktree (-uno semantics) → auto-rescan; no rescan once clean
node "$GOS" map scan >/dev/null 2>&1          # clean-state scan
echo "// dirty" >> lib/util.js                 # tracked modification → porcelain -uno non-empty
G1=$(python3 -c "import json; print(json.load(open('.gos/cache/deps.json'))['generated'])")
sleep 1
node "$GOS" map closure lib/util.js >/dev/null 2>&1
G2=$(python3 -c "import json; print(json.load(open('.gos/cache/deps.json'))['generated'])")
if [ "$G1" != "$G2" ]; then echo "  ✓ dirty worktree triggers auto-rescan"; PASS=$((PASS+1)); else echo "  ✗ dirty worktree NOT rescanned"; FAIL=$((FAIL+1)); fi
git checkout -q -- lib/util.js                 # restore clean; one transitional rescan (dirty-scan anchor → clean anchor)
node "$GOS" map closure lib/util.js >/dev/null 2>&1
G3=$(python3 -c "import json; print(json.load(open('.gos/cache/deps.json'))['generated'])")
sleep 1
node "$GOS" map closure lib/util.js >/dev/null 2>&1
G4=$(python3 -c "import json; print(json.load(open('.gos/cache/deps.json'))['generated'])")
if [ "$G3" = "$G4" ]; then echo "  ✓ clean+fresh cache NOT rewritten"; PASS=$((PASS+1)); else echo "  ✗ fresh cache rewritten anyway"; FAIL=$((FAIL+1)); fi

# --- .9: unborn does not force a rescan
mkdir -p sub/unborn && cd sub/unborn && git init -q .
node "$GOS" map scan >/dev/null 2>&1
G1=$(python3 -c "import json; print(json.load(open('.gos/cache/deps.json'))['generated'])")
sleep 1
node "$GOS" map show >/dev/null 2>&1
G2=$(python3 -c "import json; print(json.load(open('.gos/cache/deps.json'))['generated'])")
if [ "$G1" = "$G2" ]; then echo "  ✓ unborn cache served without forced rescan"; PASS=$((PASS+1)); else echo "  ✗ unborn forced a rescan"; FAIL=$((FAIL+1)); fi
cd "$T21_DIR" >/dev/null

# --- .10: non-git repo rescans on every query (unanchored is always stale)
mkdir -p nogit && cd nogit
GIT_CEILING_DIRECTORIES="$T21_DIR" node "$GOS" map scan >/dev/null 2>&1
G1=$(python3 -c "import json; print(json.load(open('.gos/cache/deps.json'))['generated'])")
sleep 1
GIT_CEILING_DIRECTORIES="$T21_DIR" node "$GOS" map show >/dev/null 2>&1
G2=$(python3 -c "import json; print(json.load(open('.gos/cache/deps.json'))['generated'])")
if [ "$G1" != "$G2" ]; then echo "  ✓ non-git (unanchored) rescan on every query"; PASS=$((PASS+1)); else echo "  ✗ unanchored cache treated as fresh"; FAIL=$((FAIL+1)); fi
cd "$T21_DIR" >/dev/null

# --- .11: root anchoring — run from a subdir: mapCwdBanner + writes only root .gos/ + input normalization
cd lib
set +e; OUT=$(node "$GOS" map closure util.js 2>/dev/null); RC=$?; set -e
assert_exit "subdir closure with cwd-relative input exits 0" 0 "$RC"
assert_contains "input normalized to root-relative" "lib/util.js" "$OUT"
ERR=$(node "$GOS" map scan 2>&1 >/dev/null)
assert_contains "stderr mapCwdBanner" "anchored to repo root" "$ERR"
if [ -e .gos ]; then echo "  ✗ second .gos/ created in subdir (truth-source fork)"; FAIL=$((FAIL+1)); else echo "  ✓ no .gos/ in subdir"; PASS=$((PASS+1)); fi
cd "$T21_DIR" >/dev/null

# --- .12: deleted query node still traverses (dangling dependents specs rebuild virtual edges)
rm lib/a.js
node "$GOS" map scan >/dev/null 2>&1
set +e; OUT=$(node "$GOS" map closure lib/a.js 2>/dev/null); RC=$?; set -e
assert_exit "deleted query node still traversable" 0 "$RC"
assert_contains "dependent of deleted node found (b.ts via dangling './a')" "lib/b.ts" "$OUT"
git checkout -q -- lib/a.js

# --- .13: show rendering — table + externals JSON escaping + mapBanner
node "$GOS" map scan >/dev/null 2>&1
set +e; OUT=$(node "$GOS" map show 2>/dev/null); RC=$?; set -e
assert_exit "show exits 0" 0 "$RC"
assert_contains "show renders file → deps arrow" "lib/entry.mjs → lib/b.ts" "$OUT"
assert_contains "show stats line" "files:" "$OUT"
BANNER=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['semantic_checks']['mapBanner'])")
assert_contains "show prints frozen mapBanner" "$BANNER" "$OUT"

# --- .14: show rejects positional args / print0+no-refresh combo rejected / out-of-root input rejected
set +e; OUT=$(node "$GOS" map show extra 2>&1); RC=$?; set -e
assert_exit "show rejects stray path args" 1 "$RC"
set +e; OUT=$(node "$GOS" map closure lib/util.js --print0 --no-refresh 2>&1); RC=$?; set -e
assert_exit "contradictory --print0 --no-refresh rejected" 1 "$RC"
set +e; OUT=$(node "$GOS" map closure ../../outside.js 2>&1); RC=$?; set -e
assert_exit "out-of-root traversal input rejected as unknown" 1 "$RC"
assert_contains "out-of-root input gets unknown-path text" "closure input not in graph" "$OUT"

t21_teardown
