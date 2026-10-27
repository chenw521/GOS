#!/usr/bin/env bash
# gos-map:cmd map
# map scan E2E — four-language fixture golden set + symlink/binary/huge skips + probe +
#     triple fail-closed + CRLF normalization + unborn/null texts + help/Next + concurrency smoke
# Covers: full green requires the (map closure) consumer in place
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner
T20_DIR=""

t20_setup() {
  T20_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t20"
  mkdir -p "$T20_DIR" && cd "$T20_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  echo ".gos/state.json" > .gitignore && git add .gitignore && git commit -q -m gi
}

t20_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T20_DIR"; }

t20_fixture() {
  mkdir -p lib app R pkg node_modules/trap linked-target
  # --- js/ts: require forms + import-from + bare import + dynamic/concatenation traps ---
  cat > lib/util.js <<'EOF'
module.exports = {};
EOF
  cat > lib/a.js <<'EOF'
const u = require('./util');
module.exports = { u };
EOF
  cat > lib/b.ts <<'EOF'
import x from './a';
export const b = x;
EOF
  cat > lib/entry.mjs <<'EOF'
import './b';
EOF
  cat > lib/trap.js <<'EOF'
const dyn = import('./lazy');
const p = 'lib/' + 'util.js';
EOF
  echo 'console.log("min")' > lib/vendor.min.js
  echo 'console.log("trap")' > node_modules/trap/x.js
  # --- py: top-level + from + indented imports ---
  cat > app/main.py <<'EOF'
import lib.helper
from lib.util import thing


def f():
    import lib.deep
EOF
  echo '# helper' > lib/helper.py
  echo '# util' > lib/util.py
  echo '# deep' > lib/deep.py
  # --- py flat sibling imports (d3/d4 style in multi-file subdir repos) ---
  mkdir -p subpkg
  printf 'class Core:\n    pass\n' > subpkg/core.py
  printf 'from core import Core\nfrom helper2 import H\n' > subpkg/api.py
  printf 'H = 1\n' > subpkg/helper2.py
  # --- R: source + library + require + pkg::func inline + roxygen/comment/string traps ---
  cat > R/analysis.R <<'EOF'
source("pkg/funcs.R")
library(dplyr)
require(ggplot2)
stats::median(x)
#' @examples tidyr::pivot_wider(df)
# see foo::bar(
str = "not a::match("
EOF
  echo '# funcs' > pkg/funcs.R
  # --- symlink trap (not followed) ---
  ln -s ../lib linkedlib
  echo 'console.log(1)' > linked-target/zz.js
  ln -s ../linked-target linkeddir
  # --- binary fake py + huge single-line js ---
  printf 'A\x00B\nimport os\n' > app/fake.py
  python3 -c "open('app/huge.js','w').write('const x = require(\"./util\");' + 'x' * 1100000)"
}

t20_setup
echo "--- T20: map scan — fixture golden + guards ---"
t20_fixture

# --- .1: scan basic flow: exit 0 + deps.json + trailing mapBanner + Next hint
set +e; OUT=$(node "$GOS" map scan 2>&1); RC=$?; set -e
assert_exit "map scan exits 0" 0 "$RC"
assert_file "deps.json created" ".gos/cache/deps.json"
assert_contains "scan output has Next: tail hint" "Next:" "$OUT"
BANNER=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['semantic_checks']['mapBanner'])")
LAST=$(echo "$OUT" | awk '/^Next:/{print prev} {prev=$0}')
assert_eq "line before Next: == frozen mapBanner (exact)" "$BANNER" "$LAST"
assert_contains "scan summary counts edges" "edge(" "$OUT"

# --- .2: deps.json schema + head anchor
python3 - <<'PYEOF'
import json, subprocess, sys
d = json.load(open(".gos/cache/deps.json"))
head = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
bad = []
if d.get("schema_version") != 3: bad.append("schema_version != 3")   # [Phase P T2/D-40] v3 = +callgraph/testof_fn/parse_failures
if d.get("head") != head: bad.append(f"head anchor mismatch: {d.get('head')!r}")
for k in ("generated", "worktree_clean", "self_sha256", "files", "edges", "externals"):
    if k not in d: bad.append(f"missing field {k}")
files = set(d["files"])
edges = {(e["from"], e["to"]) for e in d["edges"]}
golden = {
    ("lib/a.js", "lib/util.js"),
    ("lib/b.ts", "lib/a.js"),
    ("lib/entry.mjs", "lib/b.ts"),
    ("app/main.py", "lib/helper.py"),
    ("app/main.py", "lib/util.py"),
    ("app/main.py", "lib/deep.py"),
    ("R/analysis.R", "pkg/funcs.R"),
    ("subpkg/api.py", "subpkg/core.py"),      # py sibling resolution [0.11.2]
    ("subpkg/api.py", "subpkg/helper2.py"),   # py sibling resolution [0.11.2]
}
missing = golden - edges
if missing: bad.append(f"golden edges missing: {sorted(missing)}")
if ("lib/trap.js", "lib/util.js") in edges: bad.append("string-concat resolved to edge (must not)")
if ("lib/trap.js", "lib/lazy") in edges: bad.append("dynamic import() resolved to edge (must not)")
for e in d["edges"]:
    if e["from"] not in files or e["to"] not in files: bad.append(f"edge outside file set: {e}")
if "lib/entry.mjs" not in files: bad.append("entry.mjs not scanned")
for banned in ("node_modules/trap/x.js", "lib/vendor.min.js", "app/fake.py", "app/huge.js", "linkedlib", "linkeddir"):
    if banned in files: bad.append(f"banned file in scan set: {banned}")
ext = {x["spec"] for x in d["externals"]}
for want in ("dplyr", "ggplot2", "stats"):
    if want not in ext: bad.append(f"external missing: {want}")
for roxygen in ("tidyr", "foo"):
    if roxygen in ext: bad.append(f"R:: roxygen/comment leaked as external: {roxygen}")
if d.get("skipped_binary", 0) < 1: bad.append("skipped_binary not counted")
if d.get("skipped_huge", 0) < 1: bad.append("skipped_huge not counted")
print("  ✓ scan schema + golden edges + guards all pass" if not bad else "  ✗ " + "; ".join(bad))
sys.exit(1 if bad else 0)
PYEOF
assert_exit "deps.json content: golden superset + traps excluded" 0 "$?"

# --- .3: probeHint detection (verbatim text, concrete filename substituted)
echo 'module.exports = {}' > .dependency-cruiser.cjs
set +e; OUT=$(node "$GOS" map scan 2>&1); RC=$?; set -e
assert_exit "scan with probe file exits 0" 0 "$RC"
assert_contains "probeHint exact (file substituted)" "dedicated dep tool config detected (.dependency-cruiser.cjs) — prefer it for precision (not guaranteed)" "$OUT"
rm .dependency-cruiser.cjs

# --- .4: triple fail-closed (tampered / bad JSON / future schema) — consumer is (map closure)
cp .gos/cache/deps.json deps.bak.json
python3 -c "
import json; d = json.load(open('.gos/cache/deps.json')); d['edges'].append({'from':'lib/a.js','to':'lib/b.ts'})
json.dump(d, open('.gos/cache/deps.json','w'), indent=2)"
set +e; OUT=$(node "$GOS" map closure lib/a.js 2>&1); RC=$?; set -e
assert_exit "tampered deps.json → exit 1" 1 "$RC"
assert_contains "depsTamper frozen text" "deps.json integrity check failed (self-anchor mismatch) — refusing cached map, rescan required" "$OUT"
printf '{broken' > .gos/cache/deps.json
set +e; OUT=$(node "$GOS" map closure lib/a.js 2>&1); RC=$?; set -e
assert_exit "unparseable deps.json → exit 1" 1 "$RC"
assert_contains "depsParseFail frozen text" "deps.json unreadable (parse failed) — refusing cached map" "$OUT"
python3 -c "
import json; d = json.load(open('deps.bak.json')); d['schema_version'] = 4 # future = >3 → upgrade hint, not rescan hint
json.dump(d, open('.gos/cache/deps.json','w'), indent=2)"
set +e; OUT=$(node "$GOS" map closure lib/a.js 2>&1); RC=$?; set -e
assert_exit "future schema_version → exit 1" 1 "$RC"
assert_contains "depsSchemaFuture upgrade text" "upgrade gos" "$OUT"

# --- .5: self-anchor still passes after CRLF rewrite (parse normalization)
python3 -c "
raw = open('deps.bak.json','rb').read().replace(b'\n', b'\r\n')
open('.gos/cache/deps.json','wb').write(raw)"
set +e; OUT=$(node "$GOS" map closure lib/a.js --no-refresh 2>&1); RC=$?; set -e
assert_exit "CRLF-rewritten deps.json still verifies (algorithm normalizes)" 0 "$RC"

# --- .6: unborn (zero-commit repo) and non-git directory
mkdir -p sub/unborn && cd sub/unborn && git init -q .
set +e; OUT=$(node "$GOS" map scan 2>&1); RC=$?; set -e
assert_exit "scan in unborn repo exits 0" 0 "$RC"
assert_contains "headUnborn frozen text" "git repo with no commits — deps.json anchored to empty tree" "$OUT"
python3 -c "import json; assert json.load(open('.gos/cache/deps.json'))['head'] == 'unborn', 'head != unborn'; print('ok')" >/dev/null
assert_exit "unborn deps.json head == 'unborn'" 0 "$?"
cd "$T20_DIR" >/dev/null
mkdir -p nogit && cd nogit
set +e; OUT=$(GIT_CEILING_DIRECTORIES="$T20_DIR" node "$GOS" map scan 2>&1); RC=$?; set -e
assert_exit "scan in non-git dir exits 0" 0 "$RC"
assert_contains "noHead frozen text" "not a git repo — deps.json unanchored (freshness unverifiable, auto-rescan on query)" "$OUT"
GIT_CEILING_DIRECTORIES="$T20_DIR" python3 -c "import json; assert json.load(open('.gos/cache/deps.json'))['head'] is None, 'head != null'; print('ok')" >/dev/null
assert_exit "non-git deps.json head == null" 0 "$?"
cd "$T20_DIR" >/dev/null

# --- .7: help contains the map row; concurrency smoke (atomic write)
# help rendered from COMMANDS registry — row-grammar line `  map  <desc>`
HELP=$(node "$GOS" help 2>&1)
assert_contains "help mentions map command family" "anchor-network map" "$HELP"   # [Phase D compat] desc evolved map→map2.0 (output-compat migration)
for i in 1 2 3; do
  node "$GOS" map scan >/dev/null 2>&1 &
  node "$GOS" map scan >/dev/null 2>&1 &
  wait
done
python3 -c "import json; json.load(open('.gos/cache/deps.json')); print('parse-ok')" >/dev/null
assert_exit "concurrent scan smoke: deps.json still parseable" 0 "$?"

t20_teardown
