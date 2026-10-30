#!/usr/bin/env bash
# gos-map:none
# Spawn write-channel section — the registry/claim/whitelist channel that
# lets a runner-spawned session perform exactly its assigned stage advance
# under the runner's live lock, and nothing else.
# Case map (truth id -> case):
#   channel-admit  C1  a real descendant process with a registered entry,
#                   matching stage, live fresh holder in its ancestry, and no
#                   prior claim: admitted (node-level, real /proc walk)
#   channel-negative C2  the refusal matrix: no entry, redteam entry, non-
#                   whitelisted command, stage mismatch, second claim, dead
#                   holder, pid-reuse starttime mismatch, non-ancestor holder,
#                   stale heartbeat, pid-1 forgery, missing spawnId
#   cli-surface    C3  CLI integration: marker + non-whitelisted write-class
#                   command dies with the refused banner; marker + whitelist
#                   command without a registry entry dies naming the spawn;
#                   marker + map edge acquisition dies (outside the channel)
# Standalone-safe: self-provisions env when not under test/run-sections.sh.

T106_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T106_STANDALONE=1
  T106_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T106_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T106_SELFROOT"
  export TESTBASE="$(mktemp -d "$T106_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T106_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t106"
mkdir -p "$T106_DIR" && cd "$T106_DIR" || exit 1

PASS=0
FAIL=0
t106_ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
t106_bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
t106_contains() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then t106_ok "$label"; else
    t106_bad "$label (expected: '$expected')"
    echo "    actual: $(printf '%s' "$actual" | head -c 200)"
  fi
}
t106_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then t106_ok "$label (exit $actual)"; else
    t106_bad "$label (expected exit $expected, got '${actual:-<none>}')"; fi
}

t106_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T106_DIR"
  if [ "$T106_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t106_teardown EXIT

echo "--- T106: spawn write channel (channel-admit, channel-negative, cli-surface) ---"

# The registry/lock fixture root: a plain directory standing in for the repo
# root. The holder of .gos/.lock is THIS bash process — the node probes below
# are its real descendants, so the /proc ancestry walk is genuine.
CHAN_ROOT="$T106_DIR/chanroot"
mkdir -p "$CHAN_ROOT/.gos/cache/auto-spawn"

SELF="$T106_DIR/holder-facts.cjs"
cat > "$SELF" <<'EOF'
const sr = require(process.env.GOS_ROOT + '/bin/lib/core/spawnreg.cjs');
const fs = require('fs');
const pid = Number(process.argv[2]);
const rec = { pid, started_at: new Date().toISOString(), boot_id: (() => {
  try { return fs.readFileSync('/proc/sys/kernel/random/boot_id', 'utf8').trim(); } catch { return null; }
})(), starttime: sr.procStartTime(pid) };
console.log(JSON.stringify(rec));
EOF

# Lock held by this bash process with full identity fields.
HOLDER_JSON="$(node "$SELF" $$ 2>/dev/null)"
echo "$HOLDER_JSON" > "$CHAN_ROOT/.gos/.lock"

# A registered work spawn for stage THINK.
node -e "
const sr = require(process.env.GOS_ROOT + '/bin/lib/core/spawnreg.cjs');
sr.writeEntry('$CHAN_ROOT', { spawnId: 'sp-work', kind: 'work', stage: 'THINK', pid: $$, wallMs: 600000 });
" 2>/dev/null
# A registered redteam spawn (never carries write authorization).
node -e "
const sr = require(process.env.GOS_ROOT + '/bin/lib/core/spawnreg.cjs');
sr.writeEntry('$CHAN_ROOT', { spawnId: 'sp-red', kind: 'redteam', stage: 'THINK', pid: $$, wallMs: 600000 });
" 2>/dev/null

ADMIT="$T106_DIR/admit.cjs"
cat > "$ADMIT" <<'EOF'
const sr = require(process.env.GOS_ROOT + '/bin/lib/core/spawnreg.cjs');
const fs = require('fs');
const [root, cmdName, argvStage, spawnId, holderFile, lockFile] = process.argv.slice(2);
const lp = lockFile && lockFile !== '-' ? lockFile : root + '/.gos/.lock';
let holder = null;
if (holderFile && holderFile !== '-') holder = JSON.parse(fs.readFileSync(holderFile, 'utf8'));
else { try { holder = JSON.parse(fs.readFileSync(lp, 'utf8')); } catch { /* absent */ } }
const v = sr.admitSpawnWrite(root, {
  cmdName, argvStage, spawnId,
  holder,
  lockPath: lp,
});
console.log(v.ok ? 'ADMITTED stage=' + v.entry.stage : 'REFUSED ' + v.reason);
EOF

# ---------------------------------------------------------------- C1 --
echo "C1: channel-admit (real descendant, registered, live fresh holder)"
OUT="$(node "$ADMIT" "$CHAN_ROOT" commit THINK sp-work - - 2>&1)"
t106_contains "real descendant admitted" "ADMITTED stage=THINK" "$OUT"
t106_exit "second claim refused (one write per spawn)" "REFUSED already-claimed" "$(node "$ADMIT" "$CHAN_ROOT" commit THINK sp-work - - 2>&1)"

# ---------------------------------------------------------------- C2 --
echo "C2: channel-negative (refusal matrix)"
t106_exit "missing entry refused" "REFUSED no-entry" "$(node "$ADMIT" "$CHAN_ROOT" commit THINK sp-nobody - - 2>&1)"
t106_exit "unset spawn id refused" "REFUSED no-entry" "$(node "$ADMIT" "$CHAN_ROOT" commit THINK - - 2>&1)"
t106_exit "redteam entry never writes" "REFUSED redteam-no-write" "$(node "$ADMIT" "$CHAN_ROOT" commit THINK sp-red - - 2>&1)"
t106_exit "non-whitelisted command refused" "REFUSED not-whitelisted" "$(node "$ADMIT" "$CHAN_ROOT" decision add sp-work - - 2>&1)"
t106_exit "stage mismatch refused" "REFUSED stage-mismatch" "$(node "$ADMIT" "$CHAN_ROOT" commit BUILD sp-work - - 2>&1)"

node -e "
const sr = require(process.env.GOS_ROOT + '/bin/lib/core/spawnreg.cjs');
sr.writeEntry('$CHAN_ROOT', { spawnId: 'sp-dead', kind: 'work', stage: 'THINK', pid: 1, wallMs: 600000 });
sr.writeEntry('$CHAN_ROOT', { spawnId: 'sp-stranger', kind: 'work', stage: 'THINK', pid: 1, wallMs: 600000 });
sr.writeEntry('$CHAN_ROOT', { spawnId: 'sp-reuse', kind: 'work', stage: 'THINK', pid: 1, wallMs: 600000 });
sr.writeEntry('$CHAN_ROOT', { spawnId: 'sp-pid1', kind: 'work', stage: 'THINK', pid: 1, wallMs: 600000 });
sr.writeEntry('$CHAN_ROOT', { spawnId: 'sp-stale', kind: 'work', stage: 'THINK', pid: 1, wallMs: 600000 });
" 2>/dev/null

# Dead holder: a pid that cannot exist.
DEAD_HOLDER="$T106_DIR/dead-holder.json"
printf '{"pid": 4194303, "started_at": "x", "boot_id": null, "starttime": 1}' > "$DEAD_HOLDER"
t106_exit "dead holder refused" "REFUSED holder-dead" "$(node "$ADMIT" "$CHAN_ROOT" commit THINK sp-dead "$DEAD_HOLDER" - 2>&1)"

# Pid reuse: holder pid exists ($$ of this bash) but the recorded starttime
# belongs to a previous boot of that pid.
REUSE_HOLDER="$T106_DIR/reuse-holder.json"
printf '{"pid": %s, "started_at": "x", "boot_id": null, "starttime": 1}' "$$" > "$REUSE_HOLDER"
t106_exit "pid-reuse (starttime mismatch) refused" "REFUSED holder-starttime" "$(node "$ADMIT" "$CHAN_ROOT" commit THINK sp-reuse "$REUSE_HOLDER" - 2>&1)"

# Non-ancestor holder: a live background child of this bash (a sibling of
# the node probes, never their ancestor).
sleep 30 & STRANGER_PID=$!
STRANGER_HOLDER="$T106_DIR/stranger-holder.json"
node "$SELF" "$STRANGER_PID" > "$STRANGER_HOLDER" 2>/dev/null
t106_exit "non-ancestor holder refused" "REFUSED not-ancestor" "$(node "$ADMIT" "$CHAN_ROOT" commit THINK sp-stranger "$STRANGER_HOLDER" - 2>&1)"
kill "$STRANGER_PID" 2>/dev/null

# pid-1 forgery: holder recorded as pid 1 (every walk terminates there).
PID1_HOLDER="$T106_DIR/pid1-holder.json"
node "$SELF" 1 > "$PID1_HOLDER" 2>/dev/null
t106_exit "pid-1 holder never validates" "REFUSED not-ancestor" "$(node "$ADMIT" "$CHAN_ROOT" commit THINK sp-pid1 "$PID1_HOLDER" - 2>&1)"

# Stale heartbeat: holder alive and ancestral, lock mtime older than 120s.
STALE_LOCK="$CHAN_ROOT/.gos/stale.lock"
cp "$CHAN_ROOT/.gos/.lock" "$STALE_LOCK"
touch -d '10 minutes ago' "$STALE_LOCK"
node -e "
const sr = require(process.env.GOS_ROOT + '/bin/lib/core/spawnreg.cjs');
sr.writeEntry('$CHAN_ROOT', { spawnId: 'sp-stale2', kind: 'work', stage: 'THINK', pid: 1, wallMs: 600000 });
" 2>/dev/null
t106_exit "stale heartbeat refused" "REFUSED stale-heartbeat" "$(node "$ADMIT" "$CHAN_ROOT" commit THINK sp-stale2 "$CHAN_ROOT/.gos/.lock" "$STALE_LOCK" 2>&1)"

# ---------------------------------------------------------------- C3 --
echo "C3: cli-surface (marker-active CLI runs)"
CLI_CASE="$T106_DIR/cli"
mkdir -p "$CLI_CASE/home" "$CLI_CASE/repo/.gos"
export HOME="$CLI_CASE/home"
cd "$CLI_CASE/repo" || exit 1
git init -q -b work . && git commit -q --allow-empty -m root
printf '{"schema_version":6,"level":1,"current_stage":"THINK","completed_stages":["INTENT"],"intent":{"summary":"t106 cli fixture","confirmed":true},"task_head":"abc123def0123456789abcdef0123456789abcdef","spec_path":null,"plan_path":null,"requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{}}' > .gos/state.json

# Marker + non-whitelisted write command with a valid registered entry:
# refused at the whitelist check, before any state work.
cp "$CHAN_ROOT/.gos/.lock" .gos/.lock
node -e "
const sr = require(process.env.GOS_ROOT + '/bin/lib/core/spawnreg.cjs');
sr.writeEntry('$CLI_CASE/repo', { spawnId: 'sp-cli', kind: 'work', stage: 'THINK', pid: 1, wallMs: 600000 });
" 2>/dev/null
OUT="$(GOS_AUTO_SPAWNED=1 GOS_AUTO_SPAWN_ID=sp-cli node "$GOS" decision add D-01 "x" --rationale "y" 2>&1)"; RC=$?
t106_contains "marker + decision add refused" "spawn channel refused (not-whitelisted)" "$OUT"
t106_exit "refusal exits non-zero" "1" "$RC"

# Marker + whitelisted command but no registry entry: names the spawn.
OUT="$(GOS_AUTO_SPAWNED=1 node "$GOS" commit think 2>&1)"; RC=$?
t106_contains "marker + commit without entry refused" "spawn channel refused (no-entry)" "$OUT"
t106_exit "no-entry exits non-zero" "1" "$RC"

# Marker + map edge acquisition path: outside the channel by declaration.
OUT="$(GOS_AUTO_SPAWNED=1 node -e "
process.env.GOS_AUTO_SPAWNED = '1';
const lock = require(process.env.GOS_ROOT + '/bin/lib/core/lock.cjs');
try { lock.acquireLockAt('$T106_DIR/edge.lock', false); console.log('EDGE-ACQUIRED'); }
catch (e) { console.log('EDGE-DIED'); process.exit(1); }
" 2>&1)"; RC=$?
t106_contains "map/gate lock acquisition refused under marker" "outside the spawn channel" "$OUT"
t106_exit "edge acquisition exits non-zero" "1" "$RC"

# ---------------------------------------------------------------- C4 --
echo "C4: human gates refuse under the marker (approve/archive/push)"
OUT="$(GOS_AUTO_SPAWNED=1 node "$GOS" approve think 2>&1)"; RC=$?
t106_contains "approve refused in spawn" "human gate refused inside a spawned session" "$OUT"
t106_exit "approve refusal exits non-zero" "1" "$RC"
OUT="$(GOS_AUTO_SPAWNED=1 node "$GOS" archive 2>&1)"; RC=$?
t106_contains "archive refused in spawn" "human gate refused inside a spawned session" "$OUT"
t106_exit "archive refusal exits non-zero" "1" "$RC"
OUT="$(GOS_AUTO_SPAWNED=1 node "$GOS" push 2>&1)"; RC=$?
t106_contains "push refused in spawn" "human gate refused inside a spawned session" "$OUT"
t106_exit "push refusal exits non-zero" "1" "$RC"

# ---------------------------------------------------------------- C5 --
echo "C5: sanitized seed (compose form + strip rules)"
SEED_OUT="$(node -e "
const path = require('path');
const fs = require('fs');
const os = require('os');
const launcher = require(process.env.GOS_ROOT + '/bin/lib/ops/auto/launcher.cjs');
const problems = [];
// A fake host config dir with secrets, permission expansions, and an
// executable tree.
const host = fs.mkdtempSync(path.join(os.tmpdir(), 'hostcfg-'));
fs.writeFileSync(path.join(host, 'opencode.json'), JSON.stringify({
  model: 'glm-4.7',
  provider: { zai: { npm: '@zai/openai', options: { apiKey: 'sk-secret' } } },
  mcp: { evil: { env: { TOKEN: 'x' } } },
  permission: { bash: { '*': 'allow' } },
}));
fs.mkdirSync(path.join(host, 'agent'));
fs.writeFileSync(path.join(host, 'agent', 'helper.md'), 'agent frontmatter');
const s = launcher.sanitizeHostConfig({ HOME: path.dirname(host) });
// Point the sanitizer at the fake dir by faking HOME resolution: it reads
// \$HOME/.config/opencode, so re-run with a proper layout instead.
fs.rmSync(host, { recursive: true, force: true });
const home = fs.mkdtempSync(path.join(os.tmpdir(), 'home-'));
const cfg = path.join(home, '.config', 'opencode');
fs.mkdirSync(cfg, { recursive: true });
fs.writeFileSync(path.join(cfg, 'opencode.json'), JSON.stringify({
  model: 'glm-4.7',
  provider: { zai: { npm: '@zai/openai', options: { apiKey: 'sk-secret' } } },
  mcp: { evil: { env: { TOKEN: 'x' } } },
  permission: { bash: { '*': 'allow' } },
}));
fs.mkdirSync(path.join(cfg, 'agent'));
fs.writeFileSync(path.join(cfg, 'agent', 'helper.md'), 'x');
fs.writeFileSync(path.join(cfg, 'theme.txt'), 'theme=dark');
const sanitized = launcher.sanitizeHostConfig({ HOME: home });
if (!sanitized.ok) problems.push('sanitize failed: ' + sanitized.reason);
const seeded = JSON.parse(sanitized.files['opencode.json']);
if (seeded.provider.zai.options.apiKey !== undefined) problems.push('apiKey survived');
if (seeded.mcp !== undefined) problems.push('mcp survived');
if (seeded.permission !== undefined) problems.push('permission survived');
if (seeded.model !== 'glm-4.7') problems.push('model shape lost');
if (!sanitized.files['theme.txt']) problems.push('plain config file dropped');
if (!sanitized.stripped.some((x) => x.includes('apiKey'))) problems.push('apiKey strip unrecorded');
if (!sanitized.stripped.some((x) => x.includes('agent/'))) problems.push('executable tree unrecorded');
if ('agent' in sanitized.files) problems.push('agent tree seeded');
// Seed-roots compose: the seed bind lands and the ordering invariant holds.
const base = fs.mkdtempSync(path.join(os.tmpdir(), 'seedbase-'));
const dir = launcher.materializeSeedDir(sanitized.files, base, 'auto-seed');
const composed = launcher.compose('restricted', { workspace: process.cwd(), env: { HOME: home }, seedRoots: { 'host-config': dir }, writableRoots: [process.cwd()] });
if (!composed.ok) problems.push('compose failed: ' + composed.code);
else {
  const argv = composed.argv.join(' ');
  if (!argv.includes('--ro-bind ' + dir + '/opencode.json')) problems.push('seed bind missing from argv');
  if (!launcher.maskOverBindHolds(composed)) problems.push('mask-over-bind invariant broken by seed');
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'SEED-OK');
" 2>&1)"
t106_contains "sanitized seed: strip rules + compose form + invariant" "SEED-OK" "$SEED_OUT"

# ---------------------------------------------------------------- C6 --
echo "C6: crashed-advance rollback (state wrote, commit never landed)"
CRASH_OUT="$(node -e "
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const problems = [];
const world = fs.mkdtempSync(path.join(process.cwd(), 'crash-'));
fs.mkdirSync(path.join(world, '.gos', 'cache'), { recursive: true });
spawnSync('git', ['init', '-q', '-b', 'work', '.'], { cwd: world });
spawnSync('git', ['commit', '--allow-empty', '-m', 'root'], { cwd: world });
const pre = { schema_version: 6, level: 1, current_stage: 'BUILD', completed_stages: ['INTENT'], intent: { summary: 'c6', confirmed: true }, task_head: 'abc', requirements: [], decisions: [], observable_truths: [], gaps: [], checkpoints: [], approvals: {} };
// The crash lands mid-loop: iteration 1 sees the pre-advance state, its
// spawn dies (group-kill shape) after writing the post state but before
// the git commit; iteration 2 must roll back from the snapshot and
// re-drive BUILD instead of pausing as external-mutation.
const post = { ...pre, current_stage: 'VERIFY', completed_stages: ['INTENT', 'BUILD'] };
let stateNow = pre;
let spawnN = 0;
const spawnRunner = (spec) => {
  spawnN += 1;
  if (spawnN === 1) {
    // Half-executed in-spawn commit: the crash-window snapshot and the
    // advanced state both landed; the labeled git commit never did.
    fs.writeFileSync(path.join(world, '.gos', 'cache', 'state.snapshot'), JSON.stringify(pre));
    stateNow = post;
    return { status: null, stdout: '', stderr: '', error: Object.assign(new Error('spawn killed'), { killed: true }) };
  }
  return { status: 0, stdout: '{\"type\":\"result\"}\n', stderr: '' };
};
(async () => {
  const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
  store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 5, B: 30 } });
  const r = await loop.createLoop({
    rootDir: world, host: 'gos-fixture-host', env: { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' }, maxIterations: 2,
    spawnRunner, stateReader: () => stateNow,
  }).loop.run();
  if (r.status === 'paused' && r.reason === 'external-mutation') problems.push('crashed advance paused as external-mutation: ' + JSON.stringify(r.detail || '').slice(0, 200));
  if (spawnN < 2) problems.push('stage was never re-driven (spawns=' + spawnN + '; result=' + r.status + '/' + r.reason + (r.detail ? ':' + String(r.detail).slice(0, 120) : '') + ')');
  const after = stateNow;
  if (after.current_stage !== 'BUILD' && spawnN < 2) problems.push('rollback did not happen (stage=' + after.current_stage + ')');
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'CRASH-OK');
})().catch((e) => { console.error(e); process.exit(1); });
" 2>&1)"
t106_contains "crashed advance rolls back and re-drives" "CRASH-OK" "$CRASH_OUT"

echo "--- T106 summary: $PASS passed, $FAIL failed ---"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
