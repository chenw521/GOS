#!/usr/bin/env bash
# gos-map:none
# Spawn write-channel section — the registry/request/ack channel that lets a
# runner-spawned session perform exactly its registered stage verbs under the
# runner's live lock, and nothing else. Authoritative entries live in the
# machine-local store dir; the repo-side .gos/cache/auto-spawn path is dead.
# Case map (truth id -> case):
#   channel-admit  C1  a real descendant process with a registered store
#                   entry, matching stage, live fresh holder in its ancestry:
#                   admitted (node-level, real /proc walk); budget counted in
#                   the store entry, claim ledger written
#   channel-negative C2  the refusal matrix: no entry, redteam entry, verb
#                   outside the grants, truth add (verify-only), stage
#                   mismatch, dead holder, pid-reuse starttime mismatch,
#                   non-ancestor holder, stale heartbeat, pid-1 forgery,
#                   missing spawnId, legacy entry checkpoint (four-verb
#                   default), forged .gos/cache entry (inert)
#   cli-surface    C3  CLI integration: marker + out-of-grants write-class
#                   command dies with the refused banner; marker + whitelisted
#                   command without a registry entry dies naming the spawn;
#                   marker + map edge acquisition dies (outside the channel)
#   human-gates    C4  approve/archive/push refuse under the marker
#   sanitized-seed C5  compose form + strip rules (launcher)
#   crash-rollback C6  crashed advance rollback (loop)
#   req-ack        C7  the scratch channel: BUILD entry's checkpoint save,
#                   section run and truth verify admitted through a real
#                   request -> runner admitAndAck -> ack round trip; THINK
#                   entry's checkpoint refused not-in-grants through the same
#                   round trip; ack-timeout fails closed with no burn
#   channel-forge  C8  forged request burns only its own spawn's budget (ack
#                   idempotent on replay); forged cache entry inert through
#                   the channel; redteam never write-admitted (empty-grant
#                   manifest); human gates refused for every stage;
#                   registration validates the cap ceiling and verb vocabulary
#   odd-roots      C9  clone roots with a space, unicode chars, and a
#                   symlinked root: registry write/read round trips in the
#                   store-side home, the symlinked and real spelling derive
#                   one store key (realpath-first repoKey), distinct roots
#                   stay distinct, and seed materialization + seed-bound
#                   compose accept the odd paths verbatim
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

echo "--- T106: spawn write channel (channel-admit, channel-negative, cli-surface, req-ack, channel-forge) ---"

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

# A registered work spawn for stage THINK (legacy grant-less shape: the
# four-verb default) and a redteam spawn (never carries write authorization).
node -e "
const sr = require(process.env.GOS_ROOT + '/bin/lib/core/spawnreg.cjs');
sr.writeEntry('$CHAN_ROOT', { spawnId: 'sp-work', kind: 'work', stage: 'THINK', pid: $$, wallMs: 600000 });
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
OUT2="$(node "$ADMIT" "$CHAN_ROOT" gate all sp-work - - 2>&1)"
t106_contains "window admits multiple whitelisted commands" "ADMITTED stage=THINK" "$OUT2"
OUT3="$(node "$ADMIT" "$CHAN_ROOT" truth verify sp-work - - 2>&1)"
t106_contains "truth verify admitted" "ADMITTED stage=THINK" "$OUT3"
# Budget counting lives in the store entry now: three admitted claims burned
# three uses and wrote three ledger lines.
node -e "
const sr = require(process.env.GOS_ROOT + '/bin/lib/core/spawnreg.cjs');
const fs = require('fs');
const doc = sr.readEntry('$CHAN_ROOT', 'sp-work');
if (!doc || doc.uses !== 3) { console.error('uses after three admits: ' + (doc && doc.uses)); process.exit(1); }
const ledger = fs.readFileSync(sr.claimsPath('$CHAN_ROOT'), 'utf8').trim().split('\n');
if (ledger.length !== 3) { console.error('ledger lines: ' + ledger.length); process.exit(1); }
const last = JSON.parse(ledger[2]);
if (last.spawnId !== 'sp-work' || last.admitted !== true) { console.error('ledger shape: ' + ledger[2]); process.exit(1); }
" 2>&1 && t106_ok "store entry counts uses, ledger records claims" || t106_bad "store entry counts uses, ledger records claims"
# Exhausted window: fill the entry's uses to its cap, then refuse.
node -e "
const sr = require(process.env.GOS_ROOT + '/bin/lib/core/spawnreg.cjs');
sr.writeEntry('$CHAN_ROOT', { spawnId: 'sp-budget', kind: 'work', stage: 'THINK', pid: 1, wallMs: 600000 });
const doc = sr.readEntry('$CHAN_ROOT', 'sp-budget');
doc.uses = doc.use_cap;
sr.saveEntryDoc('$CHAN_ROOT', doc);
" 2>/dev/null
t106_exit "exhausted window budget refused" "REFUSED budget-exhausted" "$(node "$ADMIT" "$CHAN_ROOT" commit THINK sp-budget - - 2>&1)"

# ---------------------------------------------------------------- C2 --
echo "C2: channel-negative (refusal matrix)"
t106_exit "missing entry refused" "REFUSED no-entry" "$(node "$ADMIT" "$CHAN_ROOT" commit THINK sp-nobody - - 2>&1)"
t106_exit "unset spawn id refused" "REFUSED no-entry" "$(node "$ADMIT" "$CHAN_ROOT" commit THINK - - - 2>&1)"
t106_exit "redteam entry never writes" "REFUSED redteam-no-write" "$(node "$ADMIT" "$CHAN_ROOT" commit THINK sp-red - - 2>&1)"
t106_exit "verb outside the grants refused" "REFUSED not-in-grants" "$(node "$ADMIT" "$CHAN_ROOT" decision add sp-work - - 2>&1)"
t106_exit "truth add refused (verify only)" "REFUSED not-whitelisted" "$(node "$ADMIT" "$CHAN_ROOT" truth add sp-work - - 2>&1)"
t106_exit "stage mismatch refused" "REFUSED stage-mismatch" "$(node "$ADMIT" "$CHAN_ROOT" commit BUILD sp-work - - 2>&1)"
t106_exit "legacy grant-less entry keeps the four-verb default (checkpoint outside)" "REFUSED not-in-grants" "$(node "$ADMIT" "$CHAN_ROOT" checkpoint save sp-work - - 2>&1)"

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

# Forged repo-side cache entry: a grant-everything entry planted where the
# OLD registry lived must mean nothing — the store is the only entry source.
printf '{"spawn_id": "sp-ghost", "kind": "work", "stage": "THINK", "grants": ["commit", "gate", "section", "truth", "checkpoint"], "use_cap": 999, "uses": 0, "window_expiry": %s}' "$(node -e 'console.log(Date.now() + 600000)')" > "$CHAN_ROOT/.gos/cache/auto-spawn/sp-ghost.json"
t106_exit "forged .gos/cache entry inert (no store entry)" "REFUSED no-entry" "$(node "$ADMIT" "$CHAN_ROOT" commit THINK sp-ghost - - 2>&1)"
t106_exit "forged .gos/cache entry grants nothing outside its verbs either" "REFUSED not-in-grants" "$(node "$ADMIT" "$CHAN_ROOT" decision add sp-work - - 2>&1)"

# ---------------------------------------------------------------- C3 --
echo "C3: cli-surface (marker-active CLI runs)"
CLI_CASE="$T106_DIR/cli"
mkdir -p "$CLI_CASE/home" "$CLI_CASE/repo/.gos"
export HOME="$CLI_CASE/home"
cd "$CLI_CASE/repo" || exit 1
git init -q -b work . && git commit -q --allow-empty -m root
printf '{"schema_version":6,"level":1,"current_stage":"THINK","completed_stages":["INTENT"],"intent":{"summary":"t106 cli fixture","confirmed":true},"task_head":"abc123def0123456789abcdef0123456789abcdef","spec_path":null,"plan_path":null,"requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{}}' > .gos/state.json

# Marker + out-of-grants write command with a valid registered entry:
# refused at the grant check, before any state work.
cp "$CHAN_ROOT/.gos/.lock" .gos/.lock
node -e "
const sr = require(process.env.GOS_ROOT + '/bin/lib/core/spawnreg.cjs');
sr.writeEntry('$CLI_CASE/repo', { spawnId: 'sp-cli', kind: 'work', stage: 'THINK', pid: 1, wallMs: 600000 });
" 2>/dev/null
OUT="$(GOS_AUTO_SPAWNED=1 GOS_AUTO_SPAWN_ID=sp-cli node "$GOS" decision add D-01 "x" --rationale "y" 2>&1)"; RC=$?
t106_contains "marker + decision add refused" "spawn channel refused (not-in-grants)" "$OUT"
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
  const r = await loop.createLoop({ rootDir: world, host: 'gos-fixture-host', env: { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' }, maxIterations: 2, spawnRunner, stateReader: () => stateNow }).loop.run();
  if (r.status === 'paused' && r.reason === 'external-mutation') problems.push('crashed advance paused as external-mutation: ' + JSON.stringify(r.detail || '').slice(0, 200));
  if (spawnN < 2) problems.push('stage was never re-driven (spawns=' + spawnN + '; result=' + r.status + '/' + r.reason + (r.detail ? ':' + String(r.detail).slice(0, 120) : '') + ')');
  const after = stateNow;
  if (after.current_stage !== 'BUILD' && spawnN < 2) problems.push('rollback did not happen (stage=' + after.current_stage + ')');
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'CRASH-OK');
})().catch((e) => { console.error(e); process.exit(1); });
" 2>&1)"
t106_contains "crashed advance rolls back and re-drives" "CRASH-OK" "$CRASH_OUT"

# ---------------------------------------------------------------- C7 --
echo "C7: req/ack channel (scratch round trips with a live runner)"
WORLD="$T106_DIR/reqroot"
mkdir -p "$WORLD/.gos"
cat > "$T106_DIR/spawned-helper.cjs" <<'EOF'
const sr = require(process.env.GOS_ROOT + '/bin/lib/core/spawnreg.cjs');
const fs = require('fs');
const [cmdName, argvStage, spawnId] = process.argv.slice(2);
const root = process.env.WORLD;
let holder = null;
try { holder = JSON.parse(fs.readFileSync(root + '/.gos/.lock', 'utf8')); } catch { /* absent */ }
const v = sr.admitSpawnWrite(root, { cmdName, argvStage, spawnId, holder, lockPath: root + '/.gos/.lock' });
console.log(v.ok ? 'ADMITTED stage=' + v.entry.stage + ' remaining=' + v.entry.remaining : 'REFUSED ' + v.reason);
EOF
cat > "$T106_DIR/run-c7.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const GR = process.env.GOS_ROOT;
const root = process.env.WORLD;
const sr = require(path.join(GR, 'bin/lib/core/spawnreg.cjs'));
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const problems = [];
// The runner (this process) holds the lock; the spawned helpers are its
// real descendants, so the holder checks inside the channel are genuine.
fs.writeFileSync(path.join(root, '.gos', '.lock'), JSON.stringify({
  pid: process.pid, started_at: new Date().toISOString(), boot_id: null, starttime: sr.procStartTime(process.pid),
}));
const HELPER = path.join(path.dirname(process.argv[1] || '.'), 'spawned-helper.cjs');
const waitAck = (spawnId, cmdName, argvStage, opts = {}) => new Promise((resolve) => {
  const scratch = sr.scratchPath(root, spawnId);
  const child = spawn(process.execPath, [HELPER, cmdName, argvStage || '', spawnId], {
    env: {
      ...process.env, GOS_AUTO_SPAWNED: '1', GOS_AUTO_SPAWN_ID: spawnId,
      GOS_AUTO_SPAWN_SCRATCH: scratch, GOS_AUTO_SPAWN_ACK_WAIT_MS: opts.ackWaitMs || '4000',
    },
  });
  let out = '';
  child.stdout.on('data', (d) => { out += d; });
  child.stderr.on('data', (d) => { out += d; });
  let done = false;
  let verdict = null;
  const startedAt = Date.now();
  const iv = setInterval(() => {
    if (done) return;
    if (opts.noAck) {
      if (Date.now() - startedAt > 6000) { done = true; try { child.kill(); } catch { /* gone */ } }
      return;
    }
    let names = [];
    try { names = fs.readdirSync(scratch); } catch { return; }
    for (const n of names.filter((x) => x.endsWith('.req.json'))) {
      const req = JSON.parse(fs.readFileSync(path.join(scratch, n), 'utf8'));
      verdict = store.admitAndAck(root, spawnId, req.cmd, req.stage, { requestId: req.request_id });
    }
    if (!verdict && Date.now() - startedAt > 6000) { done = true; try { child.kill(); } catch { /* gone */ } }
  }, 15);
  child.on('close', () => { clearInterval(iv); done = true; resolve({ out: out.trim(), verdict }); });
});
(async () => {
  // BUILD entry: raised cap (64) from the dispatch table, checkpoint in its
  // grants, manifest carries grants/cap/stage ONLY.
  const reg = store.registerSpawn({ spawnId: 'sp-build', kind: 'work', stage: 'BUILD', pid: process.pid, wallMs: 600000 }, root);
  if (!reg.ok) problems.push('BUILD registration failed: ' + reg.reason);
  const man = store.writeGrantManifest(root, 'sp-build');
  if (!man.ok) problems.push('manifest write failed: ' + man.reason);
  else {
    const m = man.manifest;
    if (!m.grants.includes('checkpoint')) problems.push('manifest lacks the checkpoint verb');
    if (m.use_cap !== 64) problems.push('manifest cap not 64: ' + m.use_cap);
    if ('uses' in m || 'kind' in m) problems.push('manifest carries non-grant fields');
  }
  let r = await waitAck('sp-build', 'checkpoint', 'save');
  if (!/ADMITTED stage=BUILD/.test(r.out)) problems.push('checkpoint save not admitted through req/ack: ' + r.out);
  if (!r.verdict || r.verdict.admitted !== true || r.verdict.remaining !== 63) problems.push('checkpoint verdict/remaining wrong: ' + JSON.stringify(r.verdict));
  r = await waitAck('sp-build', 'section', 'run');
  if (!/ADMITTED stage=BUILD/.test(r.out)) problems.push('section run not admitted through req/ack: ' + r.out);
  r = await waitAck('sp-build', 'truth', 'verify');
  if (!/ADMITTED stage=BUILD/.test(r.out)) problems.push('truth verify not admitted through req/ack: ' + r.out);
  const eb = sr.readEntry(root, 'sp-build');
  if (!eb || eb.uses !== 3) problems.push('BUILD uses after three admits: ' + (eb && eb.uses));

  // THINK entry: the same verb is refused not-in-grants through the same
  // round trip, and the refusal burns the spawn's own budget.
  store.registerSpawn({ spawnId: 'sp-think', kind: 'work', stage: 'THINK', pid: process.pid, wallMs: 600000 }, root);
  r = await waitAck('sp-think', 'checkpoint', 'save');
  if (!/REFUSED not-in-grants/.test(r.out)) problems.push('THINK checkpoint not refused not-in-grants via req/ack: ' + r.out);
  const et = sr.readEntry(root, 'sp-think');
  if (!et || et.uses !== 1) problems.push('THINK refused request did not burn its own budget: ' + (et && et.uses));

  // No runner answering: the spawned side fails closed on ack timeout and
  // nothing burns (budget burns only on runner-side settlement).
  store.registerSpawn({ spawnId: 'sp-silent', kind: 'work', stage: 'THINK', pid: process.pid, wallMs: 600000 }, root);
  r = await waitAck('sp-silent', 'commit', 'think', { ackWaitMs: '250', noAck: true });
  if (!/REFUSED ack-timeout/.test(r.out)) problems.push('ack timeout did not fail closed: ' + r.out);
  if (r.verdict) problems.push('no-ack case still produced a verdict');
  const es = sr.readEntry(root, 'sp-silent');
  if (!es || es.uses !== 0) problems.push('ack-timeout case burned budget: ' + (es && es.uses));
  const silentScratch = sr.scratchPath(root, 'sp-silent');
  if (fs.readdirSync(silentScratch).some((n) => n.endsWith('.ack.json'))) problems.push('ack file exists without a runner');
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'REQACK-OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
REQACK_OUT="$(WORLD="$WORLD" node "$T106_DIR/run-c7.cjs" 2>&1 | tail -n 1)"
t106_contains "req/ack: BUILD checkpoint+section+truth admitted, THINK not-in-grants, timeout fails closed" "REQACK-OK" "$REQACK_OUT"

# ---------------------------------------------------------------- C8 --
echo "C8: channel-forge (forged requests, redteam, human gates, registration bounds)"
cat > "$T106_DIR/run-c8.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const root = process.env.WORLD;
const sr = require(path.join(GR, 'bin/lib/core/spawnreg.cjs'));
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const problems = [];
// Forged request (hand-written into the scratch, cmd the spawn was never
// granted): refused AND it burns that spawn's own budget; a sibling spawn's
// budget is untouched; re-acking replays the verdict without a second burn.
store.registerSpawn({ spawnId: 'sp-forge', kind: 'work', stage: 'BUILD', pid: process.pid, wallMs: 600000 }, root);
store.registerSpawn({ spawnId: 'sp-innocent', kind: 'work', stage: 'THINK', pid: process.pid, wallMs: 600000 }, root);
const scratch = sr.scratchPath(root, 'sp-forge');
fs.writeFileSync(path.join(scratch, 'req-forged-1.req.json'), JSON.stringify({
  request_id: 'req-forged-1', spawn_id: 'sp-forge', cmd: 'sudo', stage: null, pid: 1, ts: new Date().toISOString(),
}));
const v = store.admitAndAck(root, 'sp-forge', 'sudo', null, { requestId: 'req-forged-1' });
if (v.admitted || v.reason !== 'not-in-grants') problems.push('forged sudo request verdict: ' + JSON.stringify(v));
const ef = sr.readEntry(root, 'sp-forge');
if (!ef || ef.uses !== 1 || v.remaining !== 63) problems.push('forged request did not burn its own budget: ' + JSON.stringify({ uses: ef && ef.uses, remaining: v.remaining }));
const ei = sr.readEntry(root, 'sp-innocent');
if (!ei || ei.uses !== 0) problems.push('sibling spawn budget burned by the forged request');
if (!fs.existsSync(path.join(scratch, 'req-forged-1.ack.json'))) problems.push('refused ack file missing');
const v2 = store.admitAndAck(root, 'sp-forge', 'sudo', null, { requestId: 'req-forged-1' });
if (!v2.replay || v2.remaining !== 63) problems.push('re-ack did not replay idempotently: ' + JSON.stringify(v2));
const ef2 = sr.readEntry(root, 'sp-forge');
if (!ef2 || ef2.uses !== 1) problems.push('replay burned a second use: ' + (ef2 && ef2.uses));

// Forged .gos/cache entry through the channel: the runner checks the store
// entry only — no admission, no budget anywhere.
const cacheDir = path.join(root, '.gos', 'cache', 'auto-spawn');
fs.mkdirSync(cacheDir, { recursive: true });
fs.writeFileSync(path.join(cacheDir, 'sp-ghost.json'), JSON.stringify({
  spawn_id: 'sp-ghost', kind: 'work', stage: 'BUILD',
  grants: ['commit', 'gate', 'section', 'truth', 'checkpoint'],
  use_cap: 999, uses: 0, window_expiry: Date.now() + 600000,
}));
const vg = store.admitAndAck(root, 'sp-ghost', 'checkpoint', 'save', { requestId: 'req-ghost-1' });
if (vg.admitted || vg.reason !== 'no-entry') problems.push('forged cache entry admitted through the channel: ' + JSON.stringify(vg));

// Redteam kind: never write-admitted; its manifest carries no grants.
store.registerSpawn({ spawnId: 'sp-red2', kind: 'redteam', stage: 'THINK', pid: process.pid, wallMs: 600000 }, root);
const vr = store.admitAndAck(root, 'sp-red2', 'commit', 'think');
if (vr.admitted || vr.reason !== 'redteam-no-write') problems.push('redteam write admitted: ' + JSON.stringify(vr));
const mr = store.writeGrantManifest(root, 'sp-red2');
if (!mr.ok || mr.manifest.grants.length !== 0) problems.push('redteam manifest carries grants');

// Human gates refuse for EVERY stage, hardcoded before grant evaluation.
for (const stage of ['INTENT', 'THINK', 'PLAN', 'BUILD', 'REVIEW', 'VERIFY', 'SHIP']) {
  const sid = 'sp-gate-' + stage.toLowerCase();
  store.registerSpawn({ spawnId: sid, kind: 'work', stage, pid: process.pid, wallMs: 600000 }, root);
  for (const gate of ['approve', 'archive', 'push', 'disposition']) {
    const g = store.admitAndAck(root, sid, gate, null);
    if (g.admitted || g.reason !== 'human-gate') problems.push(stage + ' ' + gate + ' not human-gate refused: ' + JSON.stringify(g));
  }
}

// Registration bounds: the use-cap hard ceiling and the verb vocabulary are
// enforced fail-closed; table defaults give BUILD 64 + checkpoint and leave
// THINK at 16 without it.
const over = store.registerSpawn({ spawnId: 'sp-over', kind: 'work', stage: 'BUILD', useCap: 999, wallMs: 600000 }, root);
if (over.ok || over.reason !== 'use-cap-over-ceiling') problems.push('useCap over the ceiling accepted: ' + JSON.stringify(over.reason));
const badg = store.registerSpawn({ spawnId: 'sp-badg', kind: 'work', stage: 'BUILD', grants: ['approve'], wallMs: 600000 }, root);
if (badg.ok || badg.reason !== 'invalid-grants') problems.push('approve grant accepted: ' + JSON.stringify(badg.reason));
const db = store.registerSpawn({ spawnId: 'sp-defb', kind: 'work', stage: 'BUILD', pid: process.pid, wallMs: 600000 }, root);
if (!db.ok || db.entry.use_cap !== 64 || !db.entry.grants.includes('checkpoint')) problems.push('BUILD table defaults wrong: ' + JSON.stringify(db.entry));
const dt = store.registerSpawn({ spawnId: 'sp-deft', kind: 'work', stage: 'THINK', pid: process.pid, wallMs: 600000 }, root);
if (!dt.ok || dt.entry.use_cap !== 16 || dt.entry.grants.includes('checkpoint')) problems.push('THINK table defaults wrong: ' + JSON.stringify(dt.entry));

// Manifest isolation: one spawn's manifest never carries another spawn's data.
const mb = store.writeGrantManifest(root, 'sp-defb');
if (!mb.ok) problems.push('sp-defb manifest failed');
else if (JSON.stringify(mb.manifest).includes('sp-deft') || JSON.stringify(mb.manifest).includes('sp-innocent')) problems.push('manifest leaked sibling spawn data');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'GUARD-OK');
EOF
GUARD_OUT="$(WORLD="$WORLD" node "$T106_DIR/run-c8.cjs" 2>&1 | tail -n 1)"
t106_contains "forged request burns own budget; cache inert; redteam/gates/caps bounded" "GUARD-OK" "$GUARD_OUT"

# ---------------------------------------------------------------- C9 --
echo "C9: odd-roots (space, unicode, symlinked clone root)"
# Unicode segment is built from escapes so file content stays ASCII.
UNI_SEG="$(node -e "process.stdout.write('cl\u00f6ne-\u4ed3\u5e93')")"
ODD_SPACE="$T106_DIR/odd root/spacerepo"
ODD_UNI="$T106_DIR/$UNI_SEG/repo"
ODD_REAL="$T106_DIR/realrepo"
ODD_LINK="$T106_DIR/linkrepo"
mkdir -p "$ODD_SPACE/.gos" "$ODD_UNI/.gos" "$ODD_REAL/.gos"
git init -q "$ODD_SPACE" 2>/dev/null
git init -q "$ODD_REAL" 2>/dev/null
ln -s "$ODD_REAL" "$ODD_LINK"
mkdir -p "$T106_DIR/xdg-store"
cat > "$T106_DIR/run-c9.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const sr = require(path.join(GR, 'bin/lib/core/spawnreg.cjs'));
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const launcher = require(path.join(GR, 'bin/lib/ops/auto/launcher.cjs'));
const problems = [];
const SPACE = process.env.ODD_SPACE, UNI = process.env.ODD_UNI;
const REAL = process.env.ODD_REAL, LINK = process.env.ODD_LINK;

// Registry round trips through the space and unicode roots; entries live in
// the store-side home keyed by the odd root, never inside the repo tree.
sr.writeEntry(SPACE, { spawnId: 'sp-odd-space', kind: 'work', stage: 'THINK', pid: 1, wallMs: 600000 });
sr.writeEntry(UNI, { spawnId: 'sp-odd-uni', kind: 'work', stage: 'BUILD', pid: 1, wallMs: 600000 });
const es = sr.readEntry(SPACE, 'sp-odd-space');
const eu = sr.readEntry(UNI, 'sp-odd-uni');
if (!es || es.stage !== 'THINK') problems.push('space-root entry round trip failed');
if (!eu || eu.stage !== 'BUILD') problems.push('unicode-root entry round trip failed');
if (fs.existsSync(path.join(SPACE, '.gos', 'cache', 'auto-spawn', 'sp-odd-space.json'))) {
  problems.push('space-root entry leaked into the repo-side cache path');
}

// Symlinked root: repoKey is realpath-first, so both spellings derive one
// store identity — write through the link, read back through the real path.
if (store.repoKey(LINK) !== store.repoKey(REAL)) problems.push('repoKey differs across symlink and real spelling');
if (store.repoKey(LINK) === store.repoKey(SPACE)) problems.push('distinct roots collapsed to one store key');
sr.writeEntry(LINK, { spawnId: 'sp-odd-link', kind: 'work', stage: 'BUILD', pid: 1, wallMs: 600000 });
const el = sr.readEntry(REAL, 'sp-odd-link');
if (!el || el.stage !== 'BUILD') problems.push('symlink-written entry unreadable via the real root');
if (sr.scratchPath(LINK, 'x') !== sr.scratchPath(REAL, 'x')) problems.push('scratch paths split by spelling');
const reg = store.registerSpawn({ spawnId: 'sp-odd-reg', kind: 'work', stage: 'BUILD', pid: process.pid, wallMs: 600000 }, LINK);
if (!reg.ok) problems.push('store registration through the symlink refused: ' + reg.reason);
else {
  const er = sr.readEntry(REAL, 'sp-odd-reg');
  if (!er || er.use_cap !== 64) problems.push('registered entry not shared across spellings (store home split)');
}

// Seed materialization under odd base dirs; compose binds the odd seed dir
// and odd workspace verbatim with the mask invariant intact. The host-config
// seed mask appears only when the spawn home carries an opencode config, so
// the fixture home is provisioned the same way the sanitized-seed case does.
const files = { 'opencode.json': JSON.stringify({ model: 'glm-4.7' }), 'theme.txt': 'theme=dark' };
const seedSpace = launcher.materializeSeedDir(files, SPACE, 'auto-seed');
const seedUni = launcher.materializeSeedDir(files, UNI, 'auto-seed');
for (const d of [seedSpace, seedUni]) {
  if (fs.readFileSync(path.join(d, 'theme.txt'), 'utf8') !== 'theme=dark') problems.push('seed content lost under odd path: ' + d);
}
const seedHomeRoot = path.join(path.dirname(seedUni), 'seed-home');
const seedHome = path.join(seedHomeRoot, '.config', 'opencode');
fs.mkdirSync(seedHome, { recursive: true });
fs.writeFileSync(path.join(seedHome, 'opencode.json'), JSON.stringify({ model: 'glm-4.7' }));
const composed = launcher.compose('restricted', { workspace: SPACE, env: { HOME: seedHomeRoot }, seedRoots: { 'host-config': seedSpace }, writableRoots: [SPACE] });
if (!composed.ok) problems.push('compose refused odd paths: ' + (composed.code || composed.reason));
else {
  const argv = composed.argv.join(' ');
  if (!argv.includes('--ro-bind ' + seedSpace + '/opencode.json')) problems.push('odd seed bind missing from argv');
  if (!argv.includes(SPACE)) problems.push('odd workspace missing from argv');
  if (!launcher.maskOverBindHolds(composed)) problems.push('mask-over-bind invariant broken under odd paths');
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'ODD-OK');
EOF
ODD_OUT="$(XDG_DATA_HOME="$T106_DIR/xdg-store" HOME="$TESTBASE/home" ODD_SPACE="$ODD_SPACE" ODD_UNI="$ODD_UNI" ODD_REAL="$ODD_REAL" ODD_LINK="$ODD_LINK" node "$T106_DIR/run-c9.cjs" 2>&1 | tail -n 1)"
t106_contains "odd roots: store round trips, symlink shares one store key, seed+compose hold" "ODD-OK" "$ODD_OUT"

echo "--- T106 summary: $PASS passed, $FAIL failed ---"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
