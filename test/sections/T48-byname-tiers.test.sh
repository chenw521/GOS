#!/usr/bin/env bash
# gos-map:cmd map,gate
# gos-map:fn bin/lib/map/engine.cjs#fn:runExtractors bin/lib/ops/gate.cjs#fn:cmdGate
# byName three-tier resolution
# A: multi-host loser fully-qualified resolves; bare x ambiguous -> refuses + points at qualified form; B: scan dup_names list; C: self-repo gate assertion + injection turns red
T48_DIR=""

t48_setup() {
  T48_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t48"
  mkdir -p "$T48_DIR" && cd "$T48_DIR" || exit 1
}

t48_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T48_DIR"; }

t48_setup
echo "--- T48: byName three-tier (D-29) ---"

# fixture repo: two files share the fn name parsePlanMd (cross-file dup) + each has a unique fn
mkdir -p bin/lib/a bin/lib/b .gos/codebase
git init -q . && git commit -q --allow-empty -m root
cat > bin/lib/a/index.cjs <<'AEOF'
'use strict';
function parsePlanMd() { return 'A'; }
function uniqueA() { return 1; }
module.exports = { parsePlanMd, uniqueA };
AEOF
cat > bin/lib/b/index.cjs <<'BEOF'
'use strict';
function parsePlanMd() { return 'B'; }
function uniqueB() { return 2; }
module.exports = { parsePlanMd, uniqueB };
BEOF
# annotation: loser(b) fully-qualified resolves / bare parsePlanMd is ambiguous / uniqueA bare resolves (non-dup shortcut is legal)
mkdir -p test/sections
cat > test/sections/T901-dup.test.sh <<'SEOF'
#!/usr/bin/env bash
# gos-map:fn bin/lib/b/index.cjs#fn:parsePlanMd parsePlanMd uniqueA
SEOF
set +e; node "$GOS" map scan >/dev/null 2>&1; SC=$?; set -e
assert_exit "fixture scan exits 0 (duplicate names do not break scan — normal in large repos)" 0 "$SC"
node -e "
const fs=require('fs'),crypto=require('crypto');
const d=JSON.parse(fs.readFileSync('.gos/cache/deps.json','utf8'));
const sem=d.semantic||{};
const dup=(sem.dup_names||[]);
const ok1=dup.includes('parsePlanMd');
const ttf=sem.testof_fn||[];
const loser=ttf.find(e=>e.sec==='T901-dup'&&e.fn==='parsePlanMd');
const ok2=loser&&loser.file==='bin/lib/b/index.cjs';
const bareDead=(sem.dead_fn_annotations||[]).find(x=>x.includes('T901-dup#parsePlanMd')&&x.includes('fully-qualified'));
const uniq=ttf.find(e=>e.fn==='uniqueA');
const ok3=uniq&&uniq.file==='bin/lib/a/index.cjs';
console.log((ok1?'OK':'BAD')+' dup_names incl parsePlanMd');
console.log((ok2?'OK':'BAD')+' multi-host loser fully-qualified file='+((loser||{}).file));
console.log((ok3?'OK':'BAD')+' non-dup bare shortcut works uniqueA@'+((uniq||{}).file));
console.log((bareDead?'OK':'BAD')+' bare×dup rejected: '+bareDead);
" > t48a.txt 2>&1 || true
cp t48a.txt "$T48_DIR/t48a-keep.txt" 2>/dev/null; cp -r . "/keep" 2>/dev/null || true
assert_contains "① dup_names lists duplicates" "OK dup_names" "$(cat t48a.txt)"
assert_contains "② loser annotated fully-qualified (multi-host)" "OK multi-host" "$(cat t48a.txt)"
assert_contains "③ non-dup bare shortcut works" "OK non-dup" "$(cat t48a.txt)"
assert_contains "④ bare×dup rejected + fully-qualified hint" "OK bare×dup" "$(cat t48a.txt)"

# --- .B: self-repo gate dup_names=∅ assertion + injection turns red
# Runs inside a detached section worktree (workers.cjs helper): the checkout
# owns its .gos lock+cache, so the dup injection and the restore rescan touch
# the checkout's own cache, never the enclosing repository's. The tracked
# .gos/state.json is removed inside the checkout (tracked session state is
# unsupported in a linked worktree — lock.cjs guard); the leg is stateless,
# and trust is opted in for the fresh checkout.
T48_SRC="$(cd "$(dirname "$(dirname "$(readlink -f "$GOS")")")" && pwd)"
T48_WTB="$TESTBASE/test-$(date +%s)-$RANDOM-t48b/wt"
mkdir -p "$T48_WTB"
T48_WT="$(node -e '
  const cp = require("child_process");
  const path = require("path");
  const root = process.argv[1];
  const w = require(path.join(root, "bin/lib/ops/auto/workers.cjs"));
  const pin = cp.spawnSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).stdout.trim();
  const r = w.prepareSectionWorktree(root, { testBase: process.argv[2], pin });
  if (!r.ok) { process.stderr.write("worktree prepare refused: " + r.reason + "\n"); process.exit(1); }
  process.stdout.write(r.path);
' "$T48_SRC" "$T48_WTB")"
rm -f "$T48_WT/.gos/state.json"
(cd "$T48_WT" && node "$GOS" gate trust check.sh >/dev/null 2>&1)
(cd "$T48_WT" && node "$GOS" map scan >/dev/null 2>&1)
set +e; GOUT=$(cd "$T48_WT" && node "$GOS" gate codemap 2>&1); GRC=$?; set -e
assert_exit "self-repo gate codemap exit 0" 0 "$GRC"
assert_contains "self-repo zero-duplicate assertion green" "dup_names = ∅" "$GOUT"
node -e "
const fs=require('fs'),crypto=require('crypto');
const p=process.argv[1]+'/.gos/cache/deps.json';
const d=JSON.parse(fs.readFileSync(p,'utf8'));
d.semantic.dup_names=['parsePlanMd'];
delete d.self_sha256;
d.self_sha256=crypto.createHash('sha256').update(JSON.stringify(d,null,2)+'\n','utf8').digest('hex');
fs.writeFileSync(p,JSON.stringify(d,null,2));
" "$T48_WT"
set +e; IOUT=$(cd "$T48_WT" && node "$GOS" gate codemap 2>&1); IRC=$?; set -e
assert_exit "injected dup → gate FAIL (exit 1)" 1 "$IRC"
assert_contains "injection names the dup fn" "parsePlanMd" "$IOUT"
# restore: rescan back to ground truth
set +e; (cd "$T48_WT" && node "$GOS" map scan >/dev/null 2>&1); set -e
node -e '
  const path = require("path");
  const w = require(path.join(process.argv[1], "bin/lib/ops/auto/workers.cjs"));
  w.sweepSectionWorktrees(process.argv[1], { testBase: process.argv[2] });
' "$T48_SRC" "$T48_WTB" >/dev/null 2>&1 || true
rm -rf "$(dirname "$T48_WTB")"

t48_teardown
