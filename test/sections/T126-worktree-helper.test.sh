#!/usr/bin/env bash
# gos-map:none
# Worktree helper topology — the writable pinned-worktree surface the
# sandboxed section suite runs on (workers.cjs helper + the run-sections.sh
# manifest contract).
# Case map:
#   enum        w1  scriptWritableRoots gains the pre-created absolute TESTBASE
#                 pin (<scratch>/testbed): composeScriptSpawn pre-creates it,
#                 exports TESTBASE there, binds it rw post-mask, keeps the
#                 workspace bind set at .git/.gos/cache (compose-invariants shape), and the
#                 pin sits inside the writable policy allow set (a pin-only
#                 writableRoots refusal names the mask shadow, never
#                 outside-policy)
#   helper      w2  prepareSectionWorktree checks the pinned commit out under
#                 TESTBASE (prefix dir), hardlinks node_modules from the repo
#                 (same inode), refuses bad pin/testBase inputs, and prunes
#                 its own prefix idempotently — two consecutive prepares
#                 never accumulate registrations
#   pinned-run  w3  a self-repo section passes inside the real restricted
#                 sandbox compose with GOS_SECTIONS_TREE_OVERRIDE pinned at
#                 HEAD; the manifest lands at $TESTBASE/run-manifest.json
#                 with tree_source "pinned", pin <sha>, head_tree <sha>^{tree};
#                 the real repo's worktree count returns to baseline after
#                 each run and across two consecutive runs
#   live-run    w4  without the override the manifest stays at the repo-root
#                 path with tree_source "live" and pin null
# The sandbox cases register their spawn through a fixture XDG store and a
# fixture HOME (no machine-local store is touched); the real repo's worktree
# registry is asserted back to baseline in teardown.
# Standalone-safe: self-provisions env when not under test/run-sections.sh.

T126_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T126_STANDALONE=1
  T126_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T126_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T126_SELFROOT"
  export TESTBASE="$(mktemp -d "$T126_SELFROOT/test-sections-base-$$-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T126_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t126"
mkdir -p "$T126_DIR" && cd "$T126_DIR" || exit 1
export T126_DIR

PASS=0
FAIL=0
t126_ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
t126_bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
t126_contains() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then t126_ok "$label"; else
    t126_bad "$label (expected: '$expected')"
    echo "    actual: $(printf '%s' "$actual" | head -c 200)"
  fi
}
t126_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then t126_ok "$label (exit $actual)"; else
    t126_bad "$label (expected exit $expected, got '${actual:-<none>}')"; fi
}
t126_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t126_ok "$label"; else
    t126_bad "$label (expected: '$expected', got: '$actual')"; fi
}

T126_REAL_WT_BASE="$(git -C "$GOS_ROOT" worktree list 2>/dev/null | wc -l)"

t126_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T126_DIR"
  local after
  after="$(git -C "$GOS_ROOT" worktree list 2>/dev/null | wc -l)"
  if [ "$after" != "$T126_REAL_WT_BASE" ]; then
    echo "  ✗ T126 teardown: real-repo worktree count $after != baseline $T126_REAL_WT_BASE"
    node -e '
      const path = require("path");
      const w = require(path.join(process.env.GOS_ROOT, "bin/lib/ops/auto/workers.cjs"));
      const r = w.sweepSectionWorktrees(process.env.GOS_ROOT, {});
      process.stderr.write(JSON.stringify(r) + "\n");
    ' >/dev/null 2>&1 || true
  fi
  if [ "$T126_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t126_teardown EXIT

echo "--- T126: worktree helper topology (pinned writable tree + manifest contract) ---"

# Fixture HOME carries every mandatory mask destination (compose-invariants precedent);
# the store (spawn registrations, scratch dirs) lives under a fixture XDG
# root so no machine-local state is touched.
mkdir -p "$T126_DIR/env/home/.config/gh" "$T126_DIR/env/home/.config/git" \
  "$T126_DIR/env/home/.config/opencode" "$T126_DIR/env/home/.local/share/opencode" \
  "$T126_DIR/env/home/.cache/opencode" "$T126_DIR/env/home/.ssh" \
  "$T126_DIR/env/home/.aws" "$T126_DIR/env/home/.gnupg" "$T126_DIR/env/xdg/gos" \
  "$T126_DIR/env/ws-repo/.gos/cache" "$T126_DIR/env/ws-repo/src"
: > "$T126_DIR/env/home/.gitconfig"
: > "$T126_DIR/env/home/.netrc"
: > "$T126_DIR/env/home/.git-credentials"
export HOME="$T126_DIR/env/home"
export XDG_DATA_HOME="$T126_DIR/env/xdg"

# ---- case one + two: helper API + enumerated writable set (fixture repo, stub engine)
cat > "$T126_DIR/helper-api.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const workers = require(path.join(GR, 'bin/lib/ops/auto/workers.cjs'));
const problems = [];
const marks = [];
const mark = (k, v) => marks.push(`${k}[${v}]`);
const bwrap = () => ({ engine: 'bwrap', version: '0.11.0' });

// fixture repository: one commit, tracked payload, a mini node_modules
const fr = path.join(process.env.T126_DIR, 'env', 'ws-repo');
const gitEnv = {
  ...process.env,
  GIT_AUTHOR_NAME: 'gos-test', GIT_AUTHOR_EMAIL: 'gos-test@test.invalid',
  GIT_COMMITTER_NAME: 'gos-test', GIT_COMMITTER_EMAIL: 'gos-test@test.invalid',
};
const git = (argv) => {
  const r = spawnSync('git', argv, { cwd: fr, encoding: 'utf8', env: gitEnv });
  return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
};
const init = git(['init', '-q', '.']);
if (init.status !== 0) { console.log('T126-BAD fixture init failed: ' + init.stderr); process.exit(0); }
fs.writeFileSync(path.join(fr, 'tracked.txt'), 'payload\n');
fs.writeFileSync(path.join(fr, '.gitignore'), 'node_modules/\n');
fs.mkdirSync(path.join(fr, 'node_modules', 'mini-pkg'), { recursive: true });
fs.writeFileSync(path.join(fr, 'node_modules', 'mini-pkg', 'a.js'), 'module.exports = 1;\n');
git(['add', '-A']);
const commit = git(['commit', '-q', '-m', 'seed']);
if (commit.status !== 0) { console.log('T126-BAD fixture commit failed: ' + commit.stderr); process.exit(0); }
const head = git(['rev-parse', 'HEAD']).stdout.trim();
const headTree = git(['rev-parse', 'HEAD^{tree}']).stdout.trim();
const baseCount = git(['worktree', 'list']).stdout.trim().split('\n').length;
const tbase = fs.mkdtempSync(path.join(process.env.T126_DIR, 'helper-tb-'));

// W2: prepare checks the pinned commit out under TESTBASE
const pre = workers.prepareSectionWorktree(fr, { testBase: tbase, pin: head });
if (!pre.ok) problems.push('prepare refused: ' + pre.reason + ' ' + (pre.detail || ''));
if (pre.ok) {
  mark('PREPATH', path.basename(pre.path));
  mark('PRETREE', pre.treeSha === headTree);
  mark('PREPIN', pre.pin === head);
  if (!fs.existsSync(path.join(pre.path, 'tracked.txt'))) problems.push('tracked.txt missing from the checkout');
  const srcIno = fs.statSync(path.join(fr, 'node_modules', 'mini-pkg', 'a.js')).ino;
  const dstIno = fs.statSync(path.join(pre.path, 'node_modules', 'mini-pkg', 'a.js')).ino;
  mark('HARDLINK', srcIno === dstIno ? 'same-ino' : 'different-ino');
  const n1 = git(['worktree', 'list']).stdout.trim().split('\n').length;
  mark('WTADD', n1 - baseCount);
  // idempotent: a second prepare at the same TESTBASE never accumulates
  const pre2 = workers.prepareSectionWorktree(fr, { testBase: tbase, pin: head });
  if (!pre2.ok) problems.push('second prepare refused: ' + pre2.reason);
  const n2 = git(['worktree', 'list']).stdout.trim().split('\n').length;
  mark('WTIDEAL', n2 - baseCount);
}
// refusals: malformed pin, non-directory testBase
const badPin = workers.prepareSectionWorktree(fr, { testBase: tbase, pin: 'nope!' });
mark('BADPIN', badPin.ok ? 'ok' : badPin.reason);
const badBase = workers.prepareSectionWorktree(fr, { testBase: path.join(tbase, 'absent'), pin: head });
mark('BADBASE', badBase.ok ? 'ok' : badBase.reason);

// sweep returns the fixture repo to its baseline
const swept = workers.sweepSectionWorktrees(fr, { testBase: tbase });
if (!swept.ok) problems.push('sweep refused: ' + swept.reason);
const n3 = git(['worktree', 'list']).stdout.trim().split('\n').length;
mark('WTSWEEP', n3 - baseCount);
mark('SWEEPREMOVED', swept.removed ? swept.removed.length : 0);
if (fs.existsSync(path.join(tbase, 'sections-tree'))) problems.push('prefix dir survived the sweep');
// sweeping again is a no-op (idempotent)
const swept2 = workers.sweepSectionWorktrees(fr, { testBase: tbase });
mark('SWEEPIDEM', swept2.ok && (swept2.removed ? swept2.removed.length : 0));

// W1: the writable enumeration gains the pre-created absolute TESTBASE pin
const ws = fr;
const noPin = workers.scriptWritableRoots(ws);
const withScratch = workers.scriptWritableRoots(ws, { scratch: path.join(tbase, 'sc') });
mark('PINSET', withScratch.filter((p) => p === path.join(tbase, 'sc', 'testbed')).length);
mark('BASESET', noPin.join(','));

const step = { id: 'sections', command: ['bash', 'test/run-sections.sh'] };
const c = workers.composeScriptSpawn(step, {
  stage: 'VERIFY', spawnId: 't126.w1.sp1', rootDir: ws, workspace: ws,
  env: { ...process.env }, engineProbe: bwrap,
});
if (!c.ok) problems.push('script compose refused: ' + (c.code || c.reason) + ' ' + (c.detail || ''));
if (c.ok) {
  const pin = c.env.TESTBASE;
  mark('TESTBASEEND', path.basename(pin));
  if (!pin || !fs.existsSync(pin)) problems.push('compose did not pre-create the TESTBASE pin');
  const pinBind = c.argv.filter((t, i) => t === '--bind' && c.argv[i + 1] === pin && c.argv[i + 2] === pin).length;
  mark('PINBIND', pinBind);
  const BIND_OPS = ['--ro-bind', '--ro-bind-try', '--bind', '--bind-try', '--dev-bind'];
  const ops = [];
  for (let i = 0; i < c.argv.length;) {
    const t = c.argv[i];
    if (BIND_OPS.includes(t)) { ops.push({ op: t, dest: c.argv[i + 2] }); i += 3; } else i += 1;
  }
  const under = (root, p) => p === root || p.startsWith(root + path.sep);
  const rwRel = ops.filter((o) => o.op === '--bind' && under(ws, o.dest))
    .map((o) => path.relative(ws, o.dest)).sort();
  mark('WSRW', rwRel.join(','));
  // the pin sits INSIDE the policy allow set: passing the CURRENT spawn's
  // own pin as a writable bind must fail on the mask shadow (scratch lives
  // under the masked store tree), never on outside-policy
  const spawnreg = require(path.join(GR, 'bin/lib/core/spawnreg.cjs'));
  const ownPin = path.join(spawnreg.scratchPath(ws, 't126.w1.sp2'), 'testbed');
  const pinOnly = workers.composeScriptSpawn(step, {
    stage: 'VERIFY', spawnId: 't126.w1.sp2', rootDir: ws, workspace: ws,
    env: { ...process.env }, engineProbe: bwrap,
    writableRoots: [ownPin],
  });
  mark('PINALLOW', pinOnly.ok ? 'ok' : (pinOnly.code || pinOnly.reason));
}

console.log(problems.length ? 'T126-BAD ' + problems.join('; ') : 'T126-OK');
for (const m of marks) console.log(m);
EOF
API_OUT="$(node "$T126_DIR/helper-api.cjs" 2>&1)"; API_RC=$?
t126_exit "helper-api probe runs clean" "0" "$API_RC"
t126_contains "W2 helper API: prepare/sweep/enums all resolve" "T126-OK" "$API_OUT"
t126_contains "W2 prepare checks out under the TESTBASE prefix dir" "PREPATH[sections-tree]" "$API_OUT"
t126_contains "W2 prepare records the pinned tree hash" "PRETREE[true]" "$API_OUT"
t126_contains "W2 prepare echoes the pin verbatim" "PREPIN[true]" "$API_OUT"
t126_contains "W2 node_modules rides in as hardlinks (same inode)" "HARDLINK[same-ino]" "$API_OUT"
t126_contains "W2 one worktree registration after prepare" "WTADD[1]" "$API_OUT"
t126_contains "W2 two consecutive prepares never accumulate" "WTIDEAL[1]" "$API_OUT"
t126_contains "W2 malformed pin refuses" "BADPIN[section-pin-invalid]" "$API_OUT"
t126_contains "W2 absent testBase refuses" "BADBASE[section-testbase-invalid]" "$API_OUT"
t126_contains "W2 sweep returns the worktree count to baseline" "WTSWEEP[0]" "$API_OUT"
t126_contains "W2 sweep removed the one registration" "SWEEPREMOVED[1]" "$API_OUT"
t126_contains "W2 sweep is idempotent (second sweep removes nothing)" "SWEEPIDEM[0]" "$API_OUT"
t126_contains "W1 enumerated set gains the TESTBASE pin" "PINSET[1]" "$API_OUT"
t126_contains "W1 enumerated set without scratch stays .gos/cache only" "BASESET[$T126_DIR/env/ws-repo/.gos/cache]" "$API_OUT"
t126_contains "W1 compose pre-creates the pin (testbed basename)" "TESTBASEEND[testbed]" "$API_OUT"
t126_contains "W1 pin lands rw-bound post-mask" "PINBIND[1]" "$API_OUT"
t126_contains "W1 workspace bind set unchanged (.git + .gos/cache)" "WSRW[.git,.gos/cache]" "$API_OUT"
t126_contains "W1 pin-only bind fails on the shadow, never outside-policy" "PINALLOW[auto.launcher.writable-shadowed]" "$API_OUT"

# ---- case three: pinned sandbox run of a self-repo section (real compose, real bwrap)
cat > "$T126_DIR/pinned-run.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const workers = require(path.join(GR, 'bin/lib/ops/auto/workers.cjs'));
const tag = process.argv[2];
const head = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: GR, encoding: 'utf8' }).stdout.trim();
const headTree = spawnSync('git', ['rev-parse', 'HEAD^{tree}'], { cwd: GR, encoding: 'utf8' }).stdout.trim();
const c = workers.composeScriptSpawn(
  { id: 'sections', command: ['bash', 'test/run-sections.sh', 'T110-help-shortcircuit'] },
  {
    stage: 'VERIFY', spawnId: `t126.p1.${tag}`, rootDir: GR, workspace: GR,
    env: { ...process.env },
  },
);
if (!c.ok) {
  console.log(`COMPOSE[refused:${c.code || c.reason}]`);
  process.exit(0);
}
console.log(`COMPOSE[ok:${c.tier}]`);
const r = spawnSync(c.argv[0], c.argv.slice(1), {
  cwd: GR,
  env: { ...process.env, GOS_SECTIONS_TREE_OVERRIDE: head, ...c.env },
  encoding: 'utf8',
  timeout: 240000,
});
const out = String(r.stdout || '') + String(r.stderr || '');
const total = out.split('\n').filter((l) => l.includes('Sections total:')).pop() || '(no total line)';
console.log(`RC[${r.status == null ? 'timeout' : r.status}]`);
console.log(`TOTAL[${total.trim()}]`);
const manifestPath = path.join(c.env.TESTBASE, 'run-manifest.json');
let m = null;
try { m = JSON.parse(fs.readFileSync(manifestPath, 'utf8')); }
catch (e) { console.log(`MANIFEST[unreadable:${e.message}]`); }
if (m) {
  console.log(`MANIFEST[at:${manifestPath}]`);
  console.log(`TREE[${m.tree_source}]`);
  console.log(`PIN[${m.pin}]`);
  console.log(`HEADTREE[${m.head_tree}]`);
  console.log(`PINOK[${m.pin === head && m.head_tree === headTree}]`);
}
const wt = spawnSync('git', ['worktree', 'list'], { cwd: GR, encoding: 'utf8' });
console.log(`WT[${wt.stdout.trim().split('\n').length}]`);
EOF
P1_OUT="$(node "$T126_DIR/pinned-run.cjs" a 2>&1)"; P1_RC=$?
t126_exit "pinned-run probe runs clean" "0" "$P1_RC"
t126_contains "W3 compose resolves the kernel tier" "COMPOSE[ok:bubblewrap]" "$P1_OUT"
t126_contains "W3 sandboxed pinned run exits 0" "RC[0]" "$P1_OUT"
t126_contains "W3 self-repo section passes inside the sandbox" "0 failed" "$P1_OUT"
t126_contains "W3 manifest lands under the TESTBASE pin" "MANIFEST[at:" "$P1_OUT"
t126_contains "W3 manifest tree_source pinned" "TREE[pinned]" "$P1_OUT"
t126_contains "W3 manifest pin is the override sha" "PINOK[true]" "$P1_OUT"
t126_contains "W3 worktree count back to baseline after the run" "WT[$T126_REAL_WT_BASE]" "$P1_OUT"

P2_OUT="$(node "$T126_DIR/pinned-run.cjs" b 2>&1)"; P2_RC=$?
t126_exit "second pinned-run probe runs clean" "0" "$P2_RC"
t126_contains "W3 second consecutive pinned run exits 0" "RC[0]" "$P2_OUT"
t126_contains "W3 no accumulation across two consecutive runs" "WT[$T126_REAL_WT_BASE]" "$P2_OUT"

# ---- case four: literal run keeps the repo-root manifest, tree_source live, pin null
LIT_BASE="$T126_DIR/lit"
mkdir -p "$LIT_BASE"
set +e
TESTBASE="$LIT_BASE" HOME="$T126_DIR/env/home" XDG_DATA_HOME="$T126_DIR/env/xdg" \
  bash "$GOS_ROOT/test/run-sections.sh" T110-help-shortcircuit >"$T126_DIR/lit.out" 2>&1
LIT_RC=$?
set -e
t126_exit "W4 literal (unpinned) run exits 0" "0" "$LIT_RC"
LIT_TOTAL="$(grep 'Sections total:' "$T126_DIR/lit.out" | tail -1)"
t126_contains "W4 literal run green" "0 failed" "$LIT_TOTAL"
LIT_M="$GOS_ROOT/.gos/cache/run-manifest.json"
LIT_JSON="$(python3 - "$LIT_M" <<'PY'
import json, sys
try:
    m = json.load(open(sys.argv[1]))
    print(f"{m.get('tree_source')}|{m.get('pin')}|{m.get('head_tree')}")
except Exception as e:
    print(f"unreadable|{e}")
PY
)"
t126_contains "W4 repo-root manifest tree_source live" "live|" "$LIT_JSON"
t126_contains "W4 repo-root manifest pin null" "|None|" "$LIT_JSON"
t126_eq "W4 repo-root manifest head_tree matches live HEAD" \
  "$(git -C "$GOS_ROOT" rev-parse 'HEAD^{tree}')" \
  "$(printf '%s' "$LIT_JSON" | cut -d'|' -f3)"
if [ -e "$LIT_BASE/run-manifest.json" ]; then
  t126_bad "W4 literal run must not write a TESTBASE manifest"
else
  t126_ok "W4 literal run wrote no TESTBASE manifest"
fi

echo "--- T126 done: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
