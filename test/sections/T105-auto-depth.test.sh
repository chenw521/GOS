#!/usr/bin/env bash
# gos-map:none
# Full-auto adversarial depth section — spec §4 truths against the landed
# auto modules. Case map (truth id -> case):
#   T5  D1  delivery adapter absent: the loop ends cleanly at SHIP with
#           deliveryAdapter=false; the delivery probe classifies absent
#           shapes and persists its three-state result
#   T6  D2  bwrap mask surface (store prefix + credential paths masked over
#           binds), host-state poisoning isolation (deny baseline derives
#           from the runner snapshot, seeds come from runner-held roots),
#           and honest lexical degrade on an engine-less machine
#   T7  D3  tracked privacy: a ratified approval carries hash/count only —
#           zero session ids, model names or output tails in tracked bytes
#   T9  D4  repo-local tamper (forged ledger, forged counters mirror, forged
#           approval evidence) satisfies no gate — verification reads the
#           masked store and the tamper is surfaced
#   T10 D5  delivery plants: a .git/hooks/pre-push plant, a remote rewrite
#           and url.insteadOf poison make the privileged git leg abort into
#           the breaker instead of pushing; a global-config insteadOf plant
#           is neutralized by the sanitized privileged environment
# Fake host: GOS_AUTO_TEST_FIXTURE=1 activates the registry fixture row;
# loop spawns run through injected spawnRunner harnesses only. HOME and
# XDG_DATA_HOME are pinned per case under TESTBASE;
# GOS_AUTO_TIMEOUT_*_SEC are micro-overridden wherever a loop runs. The
# degrade case passes with or without bubblewrap installed (CI installs it
# so the kernel-tier assertions stay live there). Standalone-safe:
# self-provisions env when not under test/run-sections.sh.

T105_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T105_STANDALONE=1
  T105_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T105_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T105_SELFROOT"
  export TESTBASE="$(mktemp -d "$T105_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T105_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t105"
mkdir -p "$T105_DIR" && cd "$T105_DIR" || exit 1

PASS=0
FAIL=0
t105_ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
t105_bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
t105_contains() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF "$expected"; then t105_ok "$label"; else
    t105_bad "$label (expected: '$expected')"
    echo "    actual: $(printf '%s' "$actual" | head -c 160)"
  fi
}
t105_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t105_ok "$label"; else t105_bad "$label (expected: '$expected', got: '$actual')"; fi
}
t105_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then t105_ok "$label (exit $actual)"; else t105_bad "$label (expected exit $expected, got '${actual:-<none>}')"; fi
}

t105_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T105_DIR"
  if [ "$T105_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t105_teardown EXIT

echo "--- T105: auto adversarial depth (T5,T6,T7,T9,T10) ---"

t105_case() {
  T105_CASE="$T105_DIR/$1"
  mkdir -p "$T105_CASE/home" "$T105_CASE/xdg" "$T105_CASE/repo/.gos/logs"
  export HOME="$T105_CASE/home"
  export XDG_DATA_HOME="$T105_CASE/xdg"
  cd "$T105_CASE/repo" || exit 1
  git init -q -b work . && git commit -q --allow-empty -m root
}

t105_state() { # $1=current_stage
  printf '{"schema_version":6,"level":1,"current_stage":"%s","completed_stages":["INTENT"],"intent":{"summary":"t105 fixture","confirmed":true},"task_head":"abc123def0123456789abcdef0123456789abcdef","spec_path":null,"plan_path":null,"requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{}}' "$1"
}

# ---------------------------------------------------------------- D1 / T5 --
t105_case d1
t105_state THINK > .gos/state.json
export GOS_AUTO_TIMEOUT_WALL_SEC=2 GOS_AUTO_TIMEOUT_IDLE_SEC=1
cat > run-d1.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const delivery = require(path.join(GR, 'bin/lib/ops/auto/delivery.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const problems = [];
// fake host advances THINK -> PLAN -> SHIP; delivery stays entirely absent
const stateFile = path.join(rootDir, '.gos', 'state.json');
const NEXT = { THINK: 'PLAN', PLAN: 'SHIP' };
const spawnRunner = (spec) => {
  spawnSync('git', ['commit', '--allow-empty', '-m', `chore(task): advance ${spec.stage.toLowerCase()}`], { cwd: rootDir });
  const st = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
  st.current_stage = NEXT[spec.stage];
  fs.writeFileSync(stateFile, JSON.stringify(st, null, 2));
  return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
};
(async () => {
  store.create({ mode: 'on', rootDir });
  const r = await loop.create({ rootDir, host: 'gos-fixture-host', env, maxIterations: 5, spawnRunner }).loop.run();
  if (r.status !== 'ship' || r.deliveryAdapter !== false) problems.push('loop did not end at SHIP delivery-absent: ' + r.status);
  // probe classification: absent covers no-origin and gh-auth shapes
  if (delivery.classifyProbe({ hasOrigin: false }).state !== 'absent') problems.push('no-origin not absent');
  if (delivery.classifyProbe({ hasOrigin: true, ghAuthOk: false }).state !== 'absent') problems.push('gh-auth not absent');
  if (delivery.classifyProbe({ hasOrigin: true, ghAuthOk: true, ciPresent: false }).state !== 'advisory') problems.push('no-ci not advisory');
  if (delivery.classifyProbe({ hasOrigin: true, ghAuthOk: true, ciPresent: true }).state !== 'green') problems.push('ci not green');
  // persisted three-state result: a repo with no origin probes absent
  const probe = delivery.probeDelivery({
    rootDir,
    gitRunner: () => ({ status: 1, stdout: '', stderr: 'no origin' }),
    ghRunner: () => ({ status: 1, stdout: '', stderr: 'no gh' }),
  });
  if (probe.state !== 'absent' || probe.reason !== 'no-origin') problems.push('probe not absent/no-origin');
  const st = store.load(rootDir);
  const last = st.ok ? st.store.probeResults[st.store.probeResults.length - 1] : null;
  if (!last || last.host !== 'delivery' || last.state !== 'absent') problems.push('probe result not persisted');
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
D1_OUT="$(node run-d1.cjs 2>&1 | tail -n 1)"
t105_eq "T5: delivery adapter absent — loop ends at SHIP; probe classifies absent shapes and persists its state" "OK" "$D1_OUT"

# ---------------------------------------------------------------- D2 / T6 --
t105_case d2
t105_state THINK > .gos/state.json
cat > run-d2.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const launcher = require(path.join(GR, 'bin/lib/ops/auto/launcher.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const problems = [];
const storePrefix = path.join(process.env.XDG_DATA_HOME, 'gos');
const home = process.env.HOME;
store.create({ mode: 'on', rootDir });
const bwrapProbe = () => ({ engine: 'bwrap', version: '0.11.0' });
const noEngineProbe = () => ({ engine: 'none', reason: 'not installed' });
function argvOps(argv) {
  const ops = [];
  for (let i = 0; i < argv.length;) {
    const t = argv[i];
    if (['--ro-bind', '--ro-bind-try', '--bind', '--bind-try', '--dev-bind'].includes(t)) { ops.push({ op: t, src: argv[i + 1], dest: argv[i + 2] }); i += 3; }
    else if (['--tmpfs', '--proc', '--dev', '--dir'].includes(t)) { ops.push({ op: t, dest: argv[i + 1] }); i += 2; }
    else i += 1;
  }
  return ops;
}
const hasPair = (argv, flag, dest) => argv.some((_, i) => argv[i] === flag && argv[i + 1] === dest);
(async () => {
  // kernel tier: store prefix and delivery-credential paths are masked over
  // the binds (later-mount-wins), and the ordering invariant holds
  const c = launcher.compose('restricted', {
    workspace: rootDir, env, store, engineProbe: bwrapProbe,
    writableRoots: [path.join(rootDir, '.gos'), path.join(rootDir, '.gos', 'logs')],
  });
  if (!c.ok || c.tier !== 'bubblewrap') problems.push('compose not bubblewrap tier');
  if (!hasPair(c.argv, '--tmpfs', storePrefix)) problems.push('store prefix not tmpfs-masked');
  const opsC = argvOps(c.argv);
  if (!opsC.some((o) => o.op === '--ro-bind' && o.src === '/dev/null' && o.dest === path.join(home, '.gitconfig'))) problems.push('.gitconfig not empty-masked');
  if (!opsC.some((o) => o.op === '--ro-bind' && o.src === '/dev/null' && o.dest === path.join(home, '.netrc'))) problems.push('.netrc not empty-masked');
  if (!hasPair(c.argv, '--tmpfs', path.join(home, '.ssh'))) problems.push('.ssh not tmpfs-masked');
  if (!hasPair(c.argv, '--tmpfs', path.join(home, '.config', 'gh'))) problems.push('gh config not masked');
  if (!launcher.maskOverBindHolds(c)) problems.push('mask-over-bind ordering violated');
  if (c.meta.writableShadowed.length) problems.push('writable root shadowed by a mask');
  // engine-less machine: honest lexical degrade (passes without bwrap)
  const lx = launcher.compose('restricted', { workspace: rootDir, env, store, engineProbe: noEngineProbe });
  if (!lx.ok || lx.tier !== 'lexical') problems.push('engine-less compose not lexical');
  const real = launcher.probeEngine({ env });
  if (!['bubblewrap', 'lexical'].includes(real.tier)) problems.push('real probe tier dishonest: ' + real.tier);
  // poisoning isolation A: the deny baseline derives from the runner-held
  // store snapshot, not from a sandbox-rewritable disk config
  await store.saveSnapshot('denyBaseline', JSON.stringify({ permission: { bash: { deny: ['user-secret-cmd'] } } }), rootDir);
  const cfgDir = path.join(home, '.config', 'opencode');
  fs.mkdirSync(cfgDir, { recursive: true });
  fs.writeFileSync(path.join(cfgDir, 'opencode.json'), JSON.stringify({ permission: { bash: { deny: [] } } }));
  const snap = launcher.compose('restricted', { workspace: rootDir, env, store, engineProbe: bwrapProbe });
  if (!snap.deny.includes('user-secret-cmd')) problems.push('snapshot deny baseline not used');
  if (!snap.deny.includes('sudo')) problems.push('profile deny floor lost');
  // poisoning isolation B: host-state seeds come only from runner-held seed
  // roots — a poisoning file written into the real host dir between spawns
  // is absent from the next spawn's view
  const seedDir = path.join(path.dirname(rootDir), 'runner-seed');
  fs.mkdirSync(seedDir, { recursive: true });
  fs.writeFileSync(path.join(seedDir, 'opencode.json'), JSON.stringify({ model: 'runner-seeded' }));
  const poisonPath = path.join(cfgDir, 'evil-poison.json');
  fs.writeFileSync(poisonPath, '{"poison":true}');
  const seeded = launcher.compose('restricted', {
    workspace: rootDir, env, store, engineProbe: bwrapProbe,
    seedRoots: { 'host-config': seedDir },
  });
  if (seeded.meta.seeds['host-config'] !== seedDir) problems.push('seed root not recorded');
  if (seeded.argv.includes(poisonPath)) problems.push('poison file reachable in argv');
  const hostCfgBinds = argvOps(seeded.argv).filter((o) => o.src && o.dest && (o.dest === cfgDir || o.dest.startsWith(cfgDir + path.sep)));
  if (hostCfgBinds.some((o) => !o.src.startsWith(seedDir + path.sep))) problems.push('bind inside host-config dir not seed-sourced');
  if (!hostCfgBinds.some((o) => o.src === path.join(seedDir, 'opencode.json'))) problems.push('seeded snapshot not ro-bound');
  if (!launcher.maskOverBindHolds(seeded)) problems.push('seeded mask ordering violated');
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
D2_OUT="$(node run-d2.cjs 2>&1 | tail -n 1)"
t105_eq "T6: bwrap masks (store + credentials) over binds; poisoning isolated to runner snapshots; lexical degrade honest" "OK" "$D2_OUT"

# ---------------------------------------------------------------- D3 / T7 --
t105_case d3
t105_state THINK > .gos/state.json
cat > run-d3.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const ratify = require(path.join(GR, 'bin/lib/ops/auto/ratify.cjs'));
const rootDir = process.cwd();
const problems = [];
// captured worker stream carrying the privacy-sensitive detail
const stream = [
  '{"type":"message","text":"session sess_T7SECRET started on model glm-9.9"}',
  'worker tail line T7-TAIL-MARKER-XYZ',
  '{"type":"result"}',
].join('\n') + '\n';
const sha = crypto.createHash('sha256').update(stream).digest('hex');
store.create({ mode: 'on', rootDir });
const state = JSON.parse(fs.readFileSync(path.join(rootDir, '.gos', 'state.json'), 'utf8'));
state.approvals.THINK = { status: 'PENDING', ts: new Date().toISOString(), mode: 'auto', stage: 'THINK' };
fs.writeFileSync(path.join(rootDir, '.gos', 'state.json'), JSON.stringify(state, null, 2));
store.stampStream('t7-spawn-1', 'THINK', sha, new Date().toISOString(), rootDir);
const ok = ratify.ratify({ stage: 'THINK', spawnId: 't7-spawn-1', streamSha256: sha }, { rootDir });
if (!ok.ok || ok.stored.status !== 'ratified') problems.push('ratify failed');
// tracked bytes: hash + count only
const stateRaw = fs.readFileSync(path.join(rootDir, '.gos', 'state.json'), 'utf8');
if (!stateRaw.includes(sha) || !stateRaw.includes('"stampCount"')) problems.push('evidence hash/count missing from tracked state');
for (const leak of ['sess_T7SECRET', 'glm-9.9', 'T7-TAIL-MARKER-XYZ', 'worker tail line']) {
  if (stateRaw.includes(leak)) problems.push('tracked state leaks: ' + leak);
}
// the D-48 store carries the stream only as its hash key
const storeRaw = fs.readFileSync(path.join(store.storeRoot(rootDir), 'store.json'), 'utf8');
if (!storeRaw.includes(sha)) problems.push('store lacks the stream hash');
for (const leak of ['sess_T7SECRET', 'T7-TAIL-MARKER-XYZ']) {
  if (storeRaw.includes(leak)) problems.push('store leaks stream detail: ' + leak);
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
D3_OUT="$(node run-d3.cjs 2>&1 | tail -n 1)"
t105_eq "T7: tracked state carries hash/count only — zero session ids, model names or output tails; store keyed by hash" "OK" "$D3_OUT"

# ---------------------------------------------------------------- D4 / T9 --
t105_case d4
t105_state PLAN > .gos/state.json
cat > run-d4.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const breaker = require(path.join(GR, 'bin/lib/ops/auto/breaker.cjs'));
const publish = require(path.join(GR, 'bin/lib/ops/auto/delivery-publish.cjs'));
const ratify = require(path.join(GR, 'bin/lib/ops/auto/ratify.cjs'));
const rootDir = process.cwd();
const problems = [];
store.create({ mode: 'on', rootDir });
store.bumpSpawn(rootDir); store.bumpSpawn(rootDir); store.bumpSpawn(rootDir); store.bumpSpawn(rootDir);
store.recordTrip({ layer: 'N', cls: 'task' }, rootDir);
// worker-side tamper: forged repo-local ledger claiming a disposition and
// reset counters — verification must read the masked store only
fs.mkdirSync(path.join(rootDir, '.gos', 'logs'), { recursive: true });
fs.writeFileSync(path.join(rootDir, '.gos', 'logs', 'auto-ledger.ndjson'), [
  JSON.stringify({ kind: 'disposition', runId: 'forged-9', sha256: '0'.repeat(64), ts: new Date().toISOString() }),
  JSON.stringify({ kind: 'closure', runId: 'forged-9', status: 'green', ts: new Date().toISOString() }),
  JSON.stringify({ kind: 'counters', spawnCount: 0, tripCount: 0 }),
].join('\n') + '\n');
const disp = publish.dispositionFor('forged-9', rootDir);
if (disp.status !== 'not-found') problems.push('forged ledger satisfied a gate');
const mirrors = store.mirrors(rootDir);
if (!mirrors.ok || mirrors.spawnCount !== 4 || mirrors.tripCount !== 1) problems.push('forged mirror moved the counters');
// budget authority: the store count trips B despite the forged mirror
const made = breaker.create({ rootDir, limits: { N: 9, K: 9, B: 4 } });
if (!made.ok) problems.push('breaker create failed');
const budget = made.breaker.checkBudget();
if (!budget.tripped || budget.layer !== 'B') problems.push('forged mirror un-tripped the budget');
// approval tamper: a hand-forged ratified record whose evidence spawn has
// no store stamp cannot pass the sanctioned verification path
const state = JSON.parse(fs.readFileSync(path.join(rootDir, '.gos', 'state.json'), 'utf8'));
state.approvals.THINK = {
  status: 'ratified', ts: new Date().toISOString(), mode: 'auto', stage: 'THINK',
  evidence: { spawnId: 'forged-spawn', streamSha256: 'e'.repeat(64), stampCount: 99 },
};
fs.writeFileSync(path.join(rootDir, '.gos', 'state.json'), JSON.stringify(state, null, 2));
const forged = ratify.ratify({ stage: 'THINK', spawnId: 'forged-spawn', streamSha256: 'e'.repeat(64) }, { rootDir });
if (forged.status !== 'refused' || forged.reason !== 'stamp-missing') problems.push('forged evidence not surfaced: ' + forged.reason);
// a PENDING approval still blocks the next advance with the forged ledger present
state.approvals.THINK = { status: 'PENDING', ts: new Date().toISOString(), mode: 'auto', stage: 'THINK' };
if (!ratify.advanceBlocker(state.approvals)) problems.push('PENDING does not block despite forged ledger');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
D4_OUT="$(node run-d4.cjs 2>&1 | tail -n 1)"
t105_eq "T9: forged ledger/counter/approval records satisfy no gate — verification reads the store, tamper surfaced" "OK" "$D4_OUT"
# the budget trip above appended a second store trip record; status still
# reads the store (4 spawns), never the forged mirror's zeros
D4_STATUS="$(node "$GOS" auto status 2>&1 | grep -F 'counters:')"
t105_contains "T9: status counters come from the masked store, not the forged mirror" "counters: spawns 4 · trips 2" "$D4_STATUS"

# ---------------------------------------------------------------- D5 / T10 --
t105_case d5
t105_state THINK > .gos/state.json
git init -q --bare "$T105_CASE/origin.git"
git init -q --bare "$T105_CASE/origin2.git"
git remote add origin "$T105_CASE/origin.git"
git push -q origin work:main
cat > run-d5.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const delivery = require(path.join(GR, 'bin/lib/ops/auto/delivery.cjs'));
const rootDir = process.cwd();
const problems = [];
const url = path.join(path.dirname(rootDir), 'origin.git');
const url2 = path.join(path.dirname(rootDir), 'origin2.git');
const refspec = 'refs/heads/auto/p0:refs/heads/auto/p0';
let calls = [];
const privilegedRunner = (argv, cwd, env) => { calls.push({ argv: [...argv], env }); return { status: 0, stdout: '', stderr: '' }; };
const run = () => delivery.runPrivilegedGit(['push', url, refspec], { rootDir, privilegedRunner });
const rePin = () => {
  const cap = delivery.captureBaseline({ rootDir });
  if (!cap.ok) throw new Error('re-pin failed: ' + cap.reason);
  delivery.pinBaseline(cap.baseline, rootDir);
};
const breakerRecords = () => {
  const st = store.load(rootDir);
  return st.ok ? st.store.breaker.records : [];
};
store.create({ mode: 'on', rootDir });
(async () => {
  rePin();
  // (a) planted .git/hooks/pre-push: drift aborts into the breaker, no push
  const hook = path.join(rootDir, '.git', 'hooks', 'pre-push');
  fs.writeFileSync(hook, '#!/bin/sh\nexit 0\n');
  fs.chmodSync(hook, 0o755);
  const a = run();
  if (a.status !== 'aborted' || a.reason !== 'drift') problems.push('hook plant not aborted: ' + a.status);
  if (calls.length) problems.push('privileged push ran under hook plant');
  if (!a.breaker || !a.breaker.ok) problems.push('hook plant did not record breaker event');
  const recs = breakerRecords();
  if (!recs.some((r) => r.cls === 'env' && String(r.detail).includes('delivery drift'))) problems.push('drift breaker record missing');
  const capA = delivery.captureBaseline({ rootDir });
  if (!(a.drift.hooks && a.drift.hooks.added.includes('.git/hooks/pre-push'))) problems.push('drift does not name the planted hook');
  // (b) remote rewrite: pinned URL drift aborts before any push
  fs.rmSync(hook);
  rePin();
  require('child_process').spawnSync('git', ['remote', 'set-url', 'origin', url2], { cwd: rootDir });
  const b = run();
  if (b.status !== 'aborted' || !b.drift || !b.drift.remoteUrl) problems.push('remote rewrite not aborted');
  if (calls.length) problems.push('privileged push ran under remote rewrite');
  // (c) url.insteadOf + credential.helper + core.sshCommand poison in the
  // global git config: neutralized by the sanitized privileged environment
  // (push resolves the pinned URL); the same insteadOf plant written into
  // repo .git/config makes the baseline re-capture fail -> the push is
  // refused; a core.sshCommand plant in .git/config is metadata drift ->
  // abort into the breaker
  require('child_process').spawnSync('git', ['remote', 'set-url', 'origin', url], { cwd: rootDir });
  rePin();
  const gitconfig = path.join(process.env.HOME, '.gitconfig');
  fs.writeFileSync(gitconfig, [
    `[url "file://${path.join(path.dirname(rootDir), 't105-evil')}"]`,
    `\tinsteadOf = ${url}`,
    '[credential]',
    '\thelper = /t105/fake-helper',
    '[core]',
    '\tsshCommand = ssh -o ProxyCommand=/t105/fake-ssh',
  ].join('\n') + '\n');
  const c1 = run();
  if (!c1.ok) problems.push('global insteadOf plant caused a false abort: ' + c1.reason);
  if (calls.length !== 1) problems.push('sanitized push did not run');
  const call = calls[0];
  if (call.env.GIT_CONFIG_GLOBAL !== '/dev/null' || call.env.GIT_CONFIG_SYSTEM !== '/dev/null' || call.env.GIT_TERMINAL_PROMPT !== '0') problems.push('privileged env not sanitized');
  if (!String(call.env.GIT_SSH_COMMAND || '').includes('-F none')) problems.push('ssh not pinned to no config');
  if (call.argv[0] !== '-c' || call.argv[1] !== 'core.hooksPath=/dev/null') problems.push('local hooks not disabled');
  if (!call.argv.includes(url) || call.argv.join(' ').includes('t105-evil')) problems.push('push did not resolve the pinned URL');
  require('child_process').spawnSync('git', ['config', 'url.file:///t105-evil-instead.insteadOf', url], { cwd: rootDir });
  calls = [];
  const c2 = run();
  if (c2.ok || calls.length) problems.push('repo-config insteadOf plant let a push through');
  require('child_process').spawnSync('git', ['config', '--unset', 'url.file:///t105-evil-instead.insteadOf'], { cwd: rootDir });
  require('child_process').spawnSync('git', ['config', 'core.sshCommand', 'ssh -o ProxyCommand=/t105/fake-ssh'], { cwd: rootDir });
  calls = [];
  const c3 = run();
  if (c3.status !== 'aborted' || !c3.drift || !c3.drift.configSha256) problems.push('repo-config core.sshCommand plant not aborted: ' + c3.status);
  if (calls.length) problems.push('privileged push ran under config drift');
  if (!c3.breaker || !c3.breaker.ok) problems.push('config drift did not record a breaker event');
  // (d) after the plants are undone and the baseline re-pinned, push proceeds
  require('child_process').spawnSync('git', ['config', '--unset', 'core.sshCommand'], { cwd: rootDir });
  rePin();
  const d = run();
  if (!d.ok || calls.length !== 1) problems.push('clean push refused: ' + d.status);
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
D5_OUT="$(node run-d5.cjs 2>&1 | tail -n 1)"
t105_eq "T10: hook/remote/insteadOf plants abort into the breaker; global-config poison neutralized by sanitized privileged git" "OK" "$D5_OUT"

echo "--- T105 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
