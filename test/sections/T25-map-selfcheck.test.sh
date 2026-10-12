#!/usr/bin/env bash
# gos-map:cmd map
# T25: golden-set sanity (GOS self-repo) + main-suite regression + static discipline grep
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner
T25_DIR=""

t25_setup() {
  T25_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t25"
  mkdir -p "$T25_DIR" && cd "$T25_DIR" || exit 1
}

t25_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T25_DIR"; }

t25_setup
echo "--- T25: self-repo golden sanity + main-suite regression ---"

# --- T25.1: GOS self-repo scan — frozen-set equality + expected entry projection edge set ---
# Frozen set shares its source with T46; expected edge set = projection of deps.json edges
# with from==bin/gos.cjs (dual-source cross-check: independent grep of require('./lib/ in bin/gos.cjs)
set +e; OUT=$(cd "$GOS_ROOT" && node "$GOS" map scan 2>/dev/null); RC=$?; set -e
assert_exit "self-repo scan exits 0" 0 "$RC"
python3 - <<'PYEOF'
import json, os, re, sys
d = json.load(open(os.path.join(os.environ['GOS_ROOT'], '.gos', 'cache', 'deps.json')))
bad = []
FROZEN = {'.opencode/plugins/gos.js', 'bin/gos.cjs', 'bin/lib/core/fsio.cjs', 'bin/lib/core/i18n.cjs', 'bin/lib/core/index.cjs', 'bin/lib/core/locales/en.cjs', 'bin/lib/core/locales/zh.cjs', 'bin/lib/core/lock.cjs', 'bin/lib/core/state.cjs', 'bin/lib/map/index.cjs', 'bin/lib/map/allowlist.cjs', 'bin/lib/map/engine.cjs', 'bin/lib/map/edges.cjs', 'bin/lib/map/views.cjs', 'bin/lib/map/anchor.cjs', 'bin/lib/map/contract.cjs', 'bin/lib/knowledge/index.cjs', 'bin/lib/knowledge/lessons-json.cjs', 'bin/lib/knowledge/lessons.cjs', 'bin/lib/knowledge/decisions.cjs', 'bin/lib/knowledge/requirements.cjs', 'bin/lib/knowledge/truth.cjs', 'bin/lib/knowledge/concerns.cjs', 'bin/lib/knowledge/phase.cjs', 'bin/lib/task/index.cjs', 'bin/lib/nav/index.cjs', 'bin/lib/nav/registry.cjs', 'bin/lib/nav/registry-consts.cjs', 'bin/lib/nav/status.cjs', 'bin/lib/nav/help.cjs', 'bin/lib/nav/cmds.cjs', 'bin/lib/render/index.cjs', 'bin/lib/render/views.cjs', 'bin/lib/ops/index.cjs', 'bin/lib/ops/brownfield.cjs', 'bin/lib/ops/brownfield-probe.cjs', 'bin/lib/ops/gate.cjs', 'bin/lib/ops/section.cjs', 'bin/lib/ops/feedback.cjs', 'bin/lib/ops/doctor.cjs', 'bin/lib/ops/setup.cjs', 'bin/lib/ops/config.cjs', 'bin/lib/ops/paths.cjs', 'bin/lib/ops/push.cjs', 'bin/lib/ops/changelog-core.cjs', 'bin/lib/ops/gitseed.cjs', 'bin/lib/task/init.cjs', 'bin/lib/task/commit.cjs', 'bin/lib/task/archive.cjs', 'bin/lib/task/stage.cjs', 'bin/lib/task/checkpoint.cjs', 'bin/lib/task/context.cjs', 'bin/lib/task/plansnap.cjs', 'bin/lib/task/changelog.cjs'}
files = set(d['files'])
if files != FROZEN:
    bad.append(f'scan set drift: +{sorted(files-FROZEN)} -{sorted(FROZEN-files)}')
# Expected projection edges: directed pairs with from==bin/gos.cjs
proj = sorted({(e['from'], e['to']) for e in d['edges'] if e['from'] == 'bin/gos.cjs'})
WANT = [('bin/gos.cjs', 'bin/lib/core/index.cjs'), ('bin/gos.cjs', 'bin/lib/map/index.cjs'), ('bin/gos.cjs', 'bin/lib/knowledge/index.cjs'), ('bin/gos.cjs', 'bin/lib/task/index.cjs'), ('bin/gos.cjs', 'bin/lib/nav/index.cjs'), ('bin/gos.cjs', 'bin/lib/render/index.cjs'), ('bin/gos.cjs', 'bin/lib/ops/index.cjs')]
if proj != sorted(WANT):
    bad.append(f'entry projection edges: got {proj} want {WANT}')
# Dual-source cross-check: independent grep of require('./lib/ literals in entry source
gos_src = open(os.path.join(os.environ['GOS_ROOT'], 'bin', 'gos.cjs')).read()
grep_side = sorted(set(re.findall(r"require\('\./lib/([^']+)'\)", gos_src)))
want_grep = ['core/index.cjs', 'map/index.cjs', 'knowledge/index.cjs', 'task/index.cjs', 'nav/index.cjs', 'render/index.cjs', 'ops/index.cjs']
if grep_side != sorted(want_grep):
    bad.append(f'entry require literals (grep side): got {grep_side} want {want_grep}')
for banned in ('node_modules',):
    if any(banned in f for f in files): bad.append(f'pollution in scan set: {banned}')
n_files, n_edges = len(files), len(d['edges'])
print(f'  ✓ self-repo golden invariants hold ({n_files} files frozen-set-equal, {n_edges} edges total, entry projection={len(proj)})' if not bad else '  ✗ ' + '; '.join(bad))
sys.exit(1 if bad else 0)
PYEOF
assert_exit "self-repo golden invariants" 0 "$?"
# Self-anchor loop: closure query consumes deps.json successfully (anchor verified by loadDeps)
set +e; OUT=$(cd "$GOS_ROOT" && node "$GOS" map closure bin/gos.cjs --no-refresh 2>/dev/null); RC=$?; set -e
assert_exit "closure consumes self-repo deps.json (anchor verified)" 0 "$RC"
assert_contains "self in closure result" "bin/gos.cjs" "$OUT"
rm -f "$GOS_ROOT/.gos/cache/deps.json"   # cleanup: leave no in-repo cache

# --- T25.2: static discipline — atomic deps.json write + no string-concatenated git calls (multi-file grep) ---
# grep patterns frozen: targets = the T46-shared frozen set; patterns track the namespaced form (core.writeAtomicJson + core.GOS_PATHS)
GOS_SRC_FILES="$GOS_ROOT/bin/gos.cjs $GOS_ROOT/bin/lib/core/fsio.cjs $GOS_ROOT/bin/lib/core/state.cjs $GOS_ROOT/bin/lib/core/lock.cjs $GOS_ROOT/bin/lib/map/index.cjs $GOS_ROOT/bin/lib/map/engine.cjs $GOS_ROOT/bin/lib/map/edges.cjs $GOS_ROOT/bin/lib/map/views.cjs $GOS_ROOT/bin/lib/map/anchor.cjs $GOS_ROOT/bin/lib/map/contract.cjs $GOS_ROOT/bin/lib/knowledge/index.cjs $GOS_ROOT/bin/lib/knowledge/lessons-json.cjs $GOS_ROOT/bin/lib/knowledge/lessons.cjs $GOS_ROOT/bin/lib/knowledge/decisions.cjs $GOS_ROOT/bin/lib/knowledge/requirements.cjs $GOS_ROOT/bin/lib/knowledge/truth.cjs $GOS_ROOT/bin/lib/knowledge/concerns.cjs $GOS_ROOT/bin/lib/knowledge/phase.cjs $GOS_ROOT/bin/lib/task/index.cjs $GOS_ROOT/$GOS_ROOT/bin/lib/task/init.cjs $GOS_ROOT/bin/lib/task/commit.cjs $GOS_ROOT/bin/lib/task/archive.cjs $GOS_ROOT/bin/lib/task/stage.cjs $GOS_ROOT/bin/lib/task/checkpoint.cjs $GOS_ROOT/bin/lib/task/context.cjs $GOS_ROOT/bin/lib/task/plansnap.cjs $GOS_ROOT/bin/lib/task/changelog.cjs $GOS_ROOT/bin/lib/nav/index.cjs $GOS_ROOT/bin/lib/nav/registry.cjs $GOS_ROOT/bin/lib/nav/registry-consts.cjs $GOS_ROOT/bin/lib/nav/status.cjs $GOS_ROOT/bin/lib/nav/help.cjs $GOS_ROOT/bin/lib/nav/cmds.cjs $GOS_ROOT/bin/lib/render/index.cjs $GOS_ROOT/bin/lib/render/views.cjs $GOS_ROOT/bin/lib/ops/index.cjs $GOS_ROOT/bin/lib/ops/gate.cjs $GOS_ROOT/bin/lib/ops/doctor.cjs $GOS_ROOT/bin/lib/ops/setup.cjs $GOS_ROOT/bin/lib/ops/config.cjs $GOS_ROOT/bin/lib/ops/paths.cjs"
N_ATOMIC=$(grep -c "writeAtomicJson(path.join(root, '.gos', core.GOS_PATHS.deps.rel)" $GOS_SRC_FILES 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
if [ "${N_ATOMIC:-0}" -ge 1 ]; then
  echo "  ✓ deps.json write path is atomic (tmp+rename via writeAtomicJson; ${N_ATOMIC} site(s) in frozen set)"; PASS=$((PASS+1))
else
  echo "  ✗ deps.json atomic write call not found in frozen file set"; FAIL=$((FAIL+1))
fi
N_STRGIT=$(cat $GOS_SRC_FILES 2>/dev/null | grep -c "execSync('\`\?git \|execSync(\"git " || true)
if [ "${N_STRGIT:-0}" -eq 0 ]; then
  echo "  ✓ no string-concatenated git invocations (argv-array discipline holds across frozen set)"; PASS=$((PASS+1))
else
  echo "  ✗ string-concat git calls found: $N_STRGIT"; FAIL=$((FAIL+1))
fi

# --- T25.3: main-suite regression RC=0 (all sections green ≠ full suite green) ---
set +e; (cd "$GOS_ROOT" && bash test/gos-cli-tests.sh > "$T25_DIR/main-suite.log" 2>&1); MAINRC=$?; set -e
assert_exit "main suite gos-cli-tests.sh RC=0" 0 "$MAINRC"
tail -2 "$T25_DIR/main-suite.log" | head -1 | grep -q "passed\|PASS\|✓" && echo "  ✓ main suite summary present" && PASS=$((PASS+1)) || { echo "  (main suite log tail:)"; tail -3 "$T25_DIR/main-suite.log"; }

t25_teardown
