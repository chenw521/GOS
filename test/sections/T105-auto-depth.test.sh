#!/usr/bin/env bash
# gos-map:none
# Full-auto adversarial depth section — the observable-truths spec section against the landed
# auto modules. Case map (truth id -> case):
#   truth-five  D1  delivery adapter absent: the loop ends cleanly at SHIP with
#           deliveryAdapter=false; the delivery probe classifies absent
#           shapes and persists its three-state result
#   channel-equipage D1b  every agent-stage work spawn (not only BUILD waves)
#           composes with the registered write channel: the spec env carries
#           GOS_AUTO_SPAWN_SCRATCH + GOS_AUTO_ACK_DIR, spec.scratch is set,
#           and under the kernel tier the scratch rw-bind and the ack
#           ro-bind land after every mask mount
#   truth-six  D2  bwrap mask surface (store prefix + credential paths masked over
#           binds), host-state poisoning isolation (deny baseline derives
#           from the runner snapshot, seeds come from runner-held roots),
#           and honest lexical degrade on an engine-less machine
#   truth-seven  D3  tracked privacy: a ratified approval carries hash/count only —
#           zero session ids, model names or output tails in tracked bytes
#   truth-nine  D4  repo-local tamper (forged ledger, forged counters mirror, forged
#           approval evidence) satisfies no gate — verification reads the
#           masked store and the tamper is surfaced
#   truth-ten D5  delivery plants: a .git/hooks/pre-push plant, a remote rewrite
#           and url.insteadOf poison make the privileged git leg abort into
#           the breaker instead of pushing; a global-config insteadOf plant
#           is neutralized by the sanitized privileged environment
#   credential-isolation D6  spawn env: credential env vars (gh/git/ssh/aws) never reach
#           the spawned session; PATH and model-provider keys survive;
#           runner overrides land after sanitization
#   credential-isolation D7  credential masks (.git-credentials/.aws/.gnupg) in every
#           profile incl. full; repo .git rw-bound beside the ro workspace
#           at the kernel tier; mask-over-bind ordering intact
#   D8  registry rows without version_command classify a probe failure via
#           the --version fallback instead of crashing
#   spawnrun  one async spawn runner: idle killer kills a stalled stream
#           live, wall killer bounds the run, deny lines are caught as they
#           stream in, and the head/tail dual-window capture keeps both ends
#           of a long stream with sha256 + total byte counts
#   store-mutex  store.mutate serializes under a cross-process mutex: no
#           lost counter update, held-past-wait fails closed as store-busy,
#           stale reclaim needs full holder identity (boot_id + starttime,
#           mtime fallback for cross-host), and a network-filesystem store
#           refuses at auto run
#   store-v2  telemetry stamps + window sidecars: v1 stores migrate in
#           memory (additive fields, lazy write-back on the next mutate,
#           pure reads never write), future schema versions still refuse,
#           saveWindows persists a bounded head/tail sidecar pair whose
#           hashes and retained byte total ride the stamp, cap pruning
#           drops sidecars with their stamps and sweeps orphans, and
#           self-reported telemetry is advisory — stored verbatim, never
#           branched on
#   telemetry  adapter self-report extraction: model field + tool-execution
#           count read from a parsed outcome stream (tolerant, null on
#           absent evidence, data only — never a breaker signal); the
#           runner-resolved model pin lands verbatim in the spawn argv;
#           advisoryLine renders the self-report (mismatch and over-ceiling
#           included) as one text line
#   plansnap  D3  wave-field freeze validation: frozen task entries carry
#           `wave` on multi-wave plans; gapped/duplicate wave numbering and
#           unsafe declared paths (.git/**, absolute, '..' segments, hooks/**)
#           refuse the freeze with named errors; a heading-less plan freezes
#           with the verdict recorded in meta.waveValidation and refuses
#           BUILD entry with guidance back to PLAN
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

# ---------------------------------------------------------------- D1 --
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
  if (spec.roWorkspace) return { status: 0, stdout: 'review clean\nREDTEAM-FINDINGS: 0\n', stderr: '' };
  spawnSync('git', ['commit', '--allow-empty', '-m', `chore(task): advance ${spec.stage.toLowerCase()}`], { cwd: rootDir });
  const st = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
  st.current_stage = NEXT[spec.stage];
  fs.writeFileSync(stateFile, JSON.stringify(st, null, 2));
  return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
};
(async () => {
  store.create({ mode: 'on', rootDir });
  const r = await loop.createLoop({ rootDir, host: 'gos-fixture-host', env, maxIterations: 5, spawnRunner }).loop.run();
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

# ---------------------------------------------------------------- D1b --
t105_case d1b
t105_state THINK > .gos/state.json
export GOS_AUTO_TIMEOUT_WALL_SEC=2 GOS_AUTO_TIMEOUT_IDLE_SEC=1
cat > run-d1b.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const problems = [];
const captured = [];
// The spawn does no work and advances nothing (rc0-no-advance): the point is
// the equipage the runner handed it, not the outcome.
const spawnRunner = (spec) => {
  captured.push(spec);
  return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
};
(async () => {
  store.create({ mode: 'on', rootDir });
  await loop.createLoop({ rootDir, host: 'gos-fixture-host', env, maxIterations: 1, spawnRunner }).loop.run();
  if (captured.length !== 1) problems.push('expected exactly one spawn spec, got ' + captured.length);
  const spec = captured[0];
  if (!spec) problems.push('no spawn spec captured');
  else {
    const scratch = spec.env && spec.env.GOS_AUTO_SPAWN_SCRATCH;
    if (typeof scratch !== 'string' || !scratch.startsWith('/')) {
      problems.push('GOS_AUTO_SPAWN_SCRATCH missing/not absolute: ' + JSON.stringify(scratch));
    }
    if (!spec.env || spec.env.GOS_AUTO_ACK_DIR !== '/run/gos-acks') {
      problems.push('GOS_AUTO_ACK_DIR not pinned to /run/gos-acks: ' + JSON.stringify(spec.env && spec.env.GOS_AUTO_ACK_DIR));
    }
    if (typeof spec.scratch !== 'string' || !spec.scratch.startsWith(path.sep)) {
      problems.push('spec.scratch not carried for the agent leg: ' + JSON.stringify(spec.scratch));
    }
    if (spec.tier === 'bubblewrap') {
      const argv = spec.argv || [];
      const ackAt = argv.findIndex((_, i) => argv[i] === '--ro-bind' && argv[i + 2] === '/run/gos-acks');
      if (ackAt < 0) problems.push('ack dir not ro-bound at /run/gos-acks');
      const scratchAt = argv.findIndex((_, i) => argv[i] === '--bind' && argv[i + 1] === scratch && argv[i + 2] === scratch);
      if (scratchAt < 0) problems.push('scratch not rw-bound');
    }
  }
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
D1B_OUT="$(node run-d1b.cjs 2>&1 | tail -n 1)"
t105_eq "channel-equipage: non-wave agent spawn carries scratch + ack channel" "OK" "$D1B_OUT"

# ---------------------------------------------------------------- D2 --
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
// credential artifacts exist on the host side so the mask layer has real
// files to hide (absent paths are the skip branch covered by the later case)
fs.closeSync(fs.openSync(path.join(home, '.gitconfig'), 'w'));
fs.closeSync(fs.openSync(path.join(home, '.netrc'), 'w'));
fs.mkdirSync(path.join(home, '.ssh'), { recursive: true });
fs.mkdirSync(path.join(home, '.config', 'gh'), { recursive: true });
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

# ---------------------------------------------------------------- D3 --
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
if (!ok.ok || ok.stored.status !== 'cleared') problems.push('ratify failed');
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

# ---------------------------------------------------------------- D4 --
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
const made = breaker.createBreaker({ rootDir, limits: { N: 9, K: 9, B: 4 } });
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

# ---------------------------------------------------------------- D5 --
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

# ---------------------------------------------------------------- D6 --
t105_case d6
t105_state THINK > .gos/state.json
cat > run-d6.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const registry = require(path.join(GR, 'bin/lib/ops/auto/adapters/registry.cjs'));
const opencode = require(path.join(GR, 'bin/lib/ops/auto/adapters/opencode.cjs'));
const problems = [];
// poisoned parent env: runner/delivery credentials beside the keys a
// spawned session legitimately needs
process.env.LANG = process.env.LANG || 'C.UTF-8';
process.env.GH_TOKEN = 'gh-t105-secret';
process.env.GITHUB_TOKEN = 'github-t105-secret';
process.env.GIT_ASKPASS = '/t105/askpass';
process.env.AWS_SECRET_ACCESS_KEY = 'aws-t105-secret';
process.env.SSH_AUTH_SOCK = '/t105/agent.sock';
process.env.GITHUB_ACTIONS_TOKEN_CACHE = 'pattern-t105-secret';
process.env.ANTHROPIC_API_KEY = 'model-key-t105-keep';
process.env.OPENAI_API_KEY = 'model-key-t105-keep-openai';
const stripped = ['GH_TOKEN', 'GITHUB_TOKEN', 'GIT_ASKPASS', 'AWS_SECRET_ACCESS_KEY', 'SSH_AUTH_SOCK', 'GITHUB_ACTIONS_TOKEN_CACHE'];
const kept = ['PATH', 'HOME', 'LANG', 'XDG_DATA_HOME', 'ANTHROPIC_API_KEY', 'OPENAI_API_KEY'];
// direct sanitizer surface: credentials gone, everything else intact
const s = registry.sanitizedSpawnEnv(process.env);
for (const k of stripped) if (k in s) problems.push('sanitizer kept credential: ' + k);
for (const k of kept) if (!(k in s)) problems.push('sanitizer stripped a benign key: ' + k);
// adapter spawn spec: the same contract on the real build path, with the
// runner's overrides landing after sanitization
const spec = opencode.buildSpawnSpec({
  prompt: 'stage work',
  env: { OPENCODE_CONFIG_CONTENT: '{"permission":{}}', GOS_AUTO_SPAWNED: '1' },
});
for (const k of stripped) if (k in spec.env) problems.push('spawn spec leaked credential: ' + k);
for (const k of kept) if (!(k in spec.env)) problems.push('spawn spec stripped a benign key: ' + k);
if (spec.env.OPENCODE_CONFIG_CONTENT !== '{"permission":{}}') problems.push('runner override OPENCODE_CONFIG_CONTENT lost');
if (spec.env.GOS_AUTO_SPAWNED !== '1') problems.push('spawn marker override lost');
if (spec.env.ANTHROPIC_API_KEY !== 'model-key-t105-keep') problems.push('model-provider key lost in spawn spec');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
D6_OUT="$(node run-d6.cjs 2>&1 | tail -n 1)"
t105_eq "credential env: strips gh/git/ssh/aws credentials; PATH + model keys survive; overrides land last" "OK" "$D6_OUT"

# ---------------------------------------------------------------- D7 --
t105_case d7
t105_state THINK > .gos/state.json
cat > run-d7.cjs <<'EOF'
const path = require('path');
const fs = require('fs');
const os = require('os');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const launcher = require(path.join(GR, 'bin/lib/ops/auto/launcher.cjs'));
const rootDir = process.cwd();
const baseEnv = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const problems = [];
const bwrapProbe = () => ({ engine: 'bwrap', version: '0.11.0' });

// fixture homes control which credential paths exist on the host side
const richHome = fs.mkdtempSync(path.join(os.tmpdir(), 'd7-rich-'));
const bareHome = fs.mkdtempSync(path.join(os.tmpdir(), 'd7-bare-'));
const linkHome = fs.mkdtempSync(path.join(os.tmpdir(), 'd7-link-'));
const outsideAws = fs.mkdtempSync(path.join(os.tmpdir(), 'd7-out-'));
const xdg = fs.mkdtempSync(path.join(os.tmpdir(), 'd7-xdg-'));
fs.mkdirSync(path.join(xdg, 'gos'), { recursive: true });
fs.closeSync(fs.openSync(path.join(richHome, '.git-credentials'), 'w'));
fs.mkdirSync(path.join(richHome, '.aws'), { recursive: true });
fs.mkdirSync(path.join(richHome, '.gnupg'), { recursive: true });
// symlinked host-state shapes: one pointing outside the home bind, one
// resolving to a real directory inside it
fs.mkdirSync(path.join(linkHome, 'gh-internal'), { recursive: true });
fs.mkdirSync(path.join(linkHome, '.config'), { recursive: true });
fs.symlinkSync(path.join(linkHome, 'gh-internal'), path.join(linkHome, '.config', 'gh'));
fs.symlinkSync(outsideAws, path.join(linkHome, '.aws'));
fs.closeSync(fs.openSync(path.join(linkHome, '.git-credentials'), 'w'));
fs.mkdirSync(path.join(linkHome, '.gnupg'), { recursive: true });
// host exec tree in the version-manager shape: bin entry symlinked into a
// sibling lib tree, both under one root outside the system mounts
const fxRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'd7-fx-'));
fs.mkdirSync(path.join(fxRoot, 'bin'), { recursive: true });
fs.mkdirSync(path.join(fxRoot, 'lib', 'host-real'), { recursive: true });
fs.writeFileSync(path.join(fxRoot, 'lib', 'host-real', 'run'), '#!/bin/sh\nexit 0\n');
fs.chmodSync(path.join(fxRoot, 'lib', 'host-real', 'run'), 0o755);
fs.symlinkSync(path.join(fxRoot, 'lib', 'host-real', 'run'), path.join(fxRoot, 'bin', 'run'));
// host-state dir symlinked outside the home bind with a real parent: the
// mask climbs to the nearest real ancestor so the host can still create
// its state dir inside the sandbox
fs.mkdirSync(path.join(linkHome, '.local', 'share'), { recursive: true });
fs.symlinkSync(outsideAws, path.join(linkHome, '.local', 'share', 'opencode'));
store.create({ mode: 'on', rootDir });
const gitDir = path.join(rootDir, '.git');
function ops(argv) {
  const out = [];
  for (let i = 0; i < argv.length;) {
    const t = argv[i];
    if (['--ro-bind', '--ro-bind-try', '--bind', '--bind-try', '--dev-bind'].includes(t)) { out.push({ op: t, src: argv[i + 1], dest: argv[i + 2] }); i += 3; }
    else if (['--tmpfs', '--proc', '--dev', '--dir'].includes(t)) { out.push({ op: t, dest: argv[i + 1] }); i += 2; }
    else i += 1;
  }
  return out;
}
function composeFor(profile, home) {
  return launcher.compose(profile, {
    workspace: rootDir, env: { ...baseEnv, HOME: home, XDG_DATA_HOME: xdg },
    store, engineProbe: bwrapProbe,
    writableRoots: [path.join(rootDir, '.gos')],
    ...(profile === 'full' ? { allowFull: true } : {}),
  });
}
const creds = ['.git-credentials', '.aws', '.gnupg'];
for (const profile of ['restricted', 'workspace', 'full']) {
  // existing credential paths are masked in EVERY profile including full
  const rich = composeFor(profile, richHome);
  if (!rich.ok) { problems.push(profile + ' rich compose failed: ' + rich.code); continue; }
  const ro = ops(rich.argv);
  if (!ro.some((x) => x.op === '--ro-bind' && x.src === '/dev/null' && x.dest === path.join(richHome, '.git-credentials'))) problems.push(profile + ': existing .git-credentials not empty-masked');
  for (const p of ['.aws', '.gnupg']) {
    if (!ro.some((x) => x.op === '--tmpfs' && x.dest === path.join(richHome, p))) problems.push(profile + ': existing ' + p + ' not tmpfs-masked');
  }
  // the repo .git dir is bound read-write beside the read-only workspace
  if (!ro.some((x) => x.op === '--bind' && x.dest === gitDir)) problems.push(profile + ': .git not rw-bound');
  if (ro.some((x) => x.op === '--ro-bind' && x.dest === gitDir)) problems.push(profile + ': .git bound read-only');
  if (!launcher.maskOverBindHolds(rich)) problems.push(profile + ': mask-over-bind ordering violated');
  // nonexistent credential paths are skipped and recorded, never mounted
  const bare = composeFor(profile, bareHome);
  if (!bare.ok) { problems.push(profile + ' bare compose failed: ' + bare.code); continue; }
  const bo = ops(bare.argv);
  for (const p of creds) {
    const dest = path.join(bareHome, p);
    if (bo.some((x) => x.dest === dest)) problems.push(profile + ': nonexistent ' + p + ' mounted anyway');
    if (!(bare.meta.masksSkipped || []).includes('$HOME/' + p)) problems.push(profile + ': nonexistent ' + p + ' not recorded as skipped');
  }
  if (!launcher.maskOverBindHolds(bare)) problems.push(profile + ': bare ordering violated');
}
// symlinked mask destinations: outside-pointing is skipped (unreachable in
// the sandbox), home-internal is masked at its resolved real path
{
  const lk = composeFor('restricted', linkHome);
  if (!lk.ok) problems.push('link compose failed: ' + lk.code);
  else {
    const lo = ops(lk.argv);
    if (lo.some((x) => x.dest === path.join(linkHome, '.aws'))) problems.push('outside-pointing .aws symlink mounted anyway');
    if (!(lk.meta.masksSkipped || []).includes('$HOME/.aws')) problems.push('outside-pointing .aws symlink not recorded as skipped');
    if (!lo.some((x) => x.op === '--tmpfs' && x.dest === path.join(linkHome, 'gh-internal'))) problems.push('home-internal gh symlink not masked at its real path');
    if (lo.some((x) => x.dest === path.join(linkHome, '.config', 'gh'))) problems.push('mask mounted on the symlink itself');
    if (!launcher.maskOverBindHolds(lk)) problems.push('link ordering violated');
    // ancestor climb: tmpfs at the real parent, no mount on the symlink,
    // and the nested store mask still mounted AFTER the ancestor tmpfs
    const shareIdx = lk.argv.findIndex((_, i) => lk.argv[i] === '--tmpfs' && lk.argv[i + 1] === path.join(linkHome, '.local', 'share'));
    if (shareIdx < 0) problems.push('host-state symlink did not climb to its real parent');
    if (lk.argv.some((_, i) => lk.argv[i + 1] === path.join(linkHome, '.local', 'share', 'opencode'))) problems.push('mask mounted on the dangling symlink itself');
    const storeIdx = lk.argv.findIndex((_, i) => lk.argv[i] === '--tmpfs' && lk.argv[i + 1] === path.join(xdg, 'gos'));
    if (shareIdx < 0 || storeIdx < 0) problems.push('ancestor tmpfs or nested store mask missing');
    else {
      const shareP = path.join(linkHome, '.local', 'share');
      if (path.join(xdg, 'gos').startsWith(shareP + path.sep) && storeIdx < shareIdx) problems.push('nested store mask mounted before the ancestor tmpfs');
    }
    const erL = launcher.probeEngine({ env: { ...baseEnv, HOME: linkHome } });
    if (erL.tier === 'bubblewrap') {
      const rm = spawnSync('bwrap', [...lk.argv, '--', '/bin/sh', '-c', 'mkdir "$HOME/.local/share/opencode"'], { timeout: 20000, env: { ...process.env, HOME: linkHome } });
      if (rm.status !== 0) problems.push('host cannot create its state dir through the ancestor tmpfs: rc=' + rm.status + ' ' + String(rm.stderr).slice(0, 120));
    }
  }
}
// real-engine regression: a home lacking every masked credential path must
// still enter the sandbox (mounting a missing path on a read-only bind was
// a hard spawn failure before the skip rule)
const real = launcher.probeEngine({ env: { ...baseEnv, HOME: bareHome } });
if (real.tier === 'bubblewrap') {
  const c = composeFor('restricted', bareHome);
  const r = spawnSync('bwrap', [...c.argv, '--', '/bin/sh', '-c', 'exit 0'], { timeout: 20000 });
  if (r.status !== 0) problems.push('bwrap execution failed on credential-free home: rc=' + r.status + ' ' + String(r.stderr).slice(0, 120));
  const lk = composeFor('restricted', linkHome);
  const r2 = spawnSync('bwrap', [...lk.argv, '--', '/bin/sh', '-c', 'exit 0'], { timeout: 20000 });
  if (r2.status !== 0) problems.push('bwrap execution failed on symlinked-state home: rc=' + r2.status + ' ' + String(r2.stderr).slice(0, 120));
}
// adapter-declared exec tree: the version-manager layout must be bindable
// read-only and the bin symlink must execute through it inside the sandbox
{
  const fx = launcher.compose('restricted', {
    workspace: rootDir, env: { ...baseEnv, HOME: bareHome, XDG_DATA_HOME: xdg },
    store, engineProbe: () => ({ engine: 'bwrap', version: '0.11.0' }),
    roBinds: [fxRoot], writableRoots: [path.join(rootDir, '.gos')],
  });
  if (!fx.ok) problems.push('exec-tree compose failed: ' + fx.code);
  else {
    if (!fx.argv.some((_, i) => fx.argv[i] === '--ro-bind' && fx.argv[i + 1] === fxRoot && fx.argv[i + 2] === fxRoot)) problems.push('exec tree not ro-bound');
    const er = launcher.probeEngine({ env: { ...baseEnv, HOME: bareHome } });
    if (er.tier === 'bubblewrap') {
      const rr = spawnSync('bwrap', [...fx.argv, '--', path.join(fxRoot, 'bin', 'run')], { timeout: 20000 });
      if (rr.status !== 0) problems.push('bin symlink not executable through the ro-bound tree: rc=' + rr.status + ' ' + String(rr.stderr).slice(0, 120));
    }
  }
}
// DNS stub chain: a resolv.conf symlinked into /run must pull its top
// directory into the argv; a plain resolv.conf adds nothing
{
  const fx = launcher.compose('restricted', { env: { ...baseEnv, HOME: bareHome, XDG_DATA_HOME: xdg }, store, engineProbe: bwrapProbe, writableRoots: [path.join(rootDir, '.gos')] });
  if (!fx.ok) problems.push('resolv compose failed: ' + fx.code);
  else {
    let real = null;
    try { real = fs.realpathSync('/etc/resolv.conf'); } catch { real = null; }
    const stubbed = real && real !== '/etc/resolv.conf' && real.startsWith('/run/');
    const hasBind = fx.argv.some((_, i) => fx.argv[i] === '--ro-bind-try' && fx.argv[i + 1] === fx.meta.resolvBind && fx.argv[i + 2] === fx.meta.resolvBind);
    if (stubbed && !hasBind) problems.push('stub resolv.conf did not bind its /run segment');
    if (!stubbed && fx.meta.resolvBind) problems.push('plain resolv.conf must add no bind');
  }
}
// model auth: the declared file binds read-only at its declared path with
// the realpath as the source, inside whatever mask covers the directory
{
  const authSrc = fs.mkdtempSync(path.join(os.tmpdir(), 'd7-auth-'));
  const authReal = path.join(authSrc, 'auth.json');
  fs.writeFileSync(authReal, '{}');
  const declaredHome = fs.mkdtempSync(path.join(os.tmpdir(), 'd7-authdest-'));
  fs.mkdirSync(path.join(declaredHome, '.local', 'share', 'opencode'), { recursive: true });
  const declared = path.join(declaredHome, '.local', 'share', 'opencode', 'auth.json');
  fs.symlinkSync(authReal, declared);
  const ax = launcher.compose('restricted', { env: { ...baseEnv, HOME: declaredHome, XDG_DATA_HOME: xdg }, store, engineProbe: bwrapProbe, authFiles: [declared], writableRoots: [path.join(rootDir, '.gos')] });
  if (!ax.ok) problems.push('auth compose failed: ' + ax.code);
  else {
    const pair = ax.argv.some((_, i) => ax.argv[i] === '--ro-bind' && ax.argv[i + 1] === authReal && ax.argv[i + 2] === declared);
    if (!pair) problems.push('auth file not bound realpath-source at the declared destination');
    if (!launcher.maskOverBindHolds(ax)) problems.push('auth ordering violated');
  }
  for (const d of [authSrc, declaredHome]) { try { fs.rmSync(d, { recursive: true, force: true }); } catch {} }
}
for (const d of [richHome, bareHome, linkHome, outsideAws, fxRoot, xdg]) { try { fs.rmSync(d, { recursive: true, force: true }); } catch {} }
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
D7_RAW="$(node run-d7.cjs 2>&1)"
D7_OUT="$(printf '%s\n' "$D7_RAW" | tail -n 1)"
case "$D7_OUT" in
  OK|BAD\ *) ;;
  *) printf 'D7 raw output (%d chars): %s\n' "${#D7_RAW}" "$(printf '%s' "$D7_RAW" | head -c 400)" ;;
esac
t105_eq "credential masks: existing paths masked in every profile, absent paths skipped+recorded; repo .git rw-bound at kernel tier; ordering intact; credential-free home enters the sandbox" "OK" "$D7_OUT"

# ---------------------------------------------------------------- D8 --
t105_case d8
t105_state THINK > .gos/state.json
cat > run-d8.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const registry = require(path.join(GR, 'bin/lib/ops/auto/adapters/registry.cjs'));
const problems = [];
// matrix row with no version_command: the probe must classify a failure
// naming the --version fallback, never crash on the missing field
const row = { host: 't105-novcmd', binary: 't105-novcmd', version_range: '>=1.0.0', status: 'verified', selectable: true, spawn_mode: 'opencode-run-json' };
const noVersion = registry.probeHost('t105-novcmd', { matrix: [row], runner: () => ({ ok: true, out: 'no version triplet here', err: '' }) });
if (noVersion.ok) problems.push('rc0-no-version probe passed');
if (!noVersion.failure || noVersion.failure.class !== 'probe-version') problems.push('rc0-no-version not a classified probe-version failure');
if (!noVersion.steps.some((s) => s.id === 'version' && !s.ok && /t105-novcmd --version/.test(s.detail))) problems.push('version step detail missing --version fallback');
const failing = registry.probeHost('t105-novcmd', { matrix: [row], runner: () => ({ ok: false, out: '', err: 'rc=127 command not found' }) });
if (failing.ok) problems.push('failed runner probe passed');
if (!failing.failure || failing.failure.class !== 'probe-version') problems.push('runner failure not classified probe-version');
if (!failing.steps.some((s) => s.id === 'version' && !s.ok && /t105-novcmd --version/.test(s.detail))) problems.push('failure detail missing --version fallback');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
D8_OUT="$(node run-d8.cjs 2>&1 | tail -n 1)"
t105_eq "registry: row without version_command classifies a probe failure (fallback --version), never crashes" "OK" "$D8_OUT"

# ---------------------------------------------------------------- D9 --
t105_case d9
t105_state THINK > .gos/state.json
cat > run-d9.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const stateMod = require(path.join(GR, 'bin/lib/core/state.cjs'));
const problems = [];
const hex64 = 'a'.repeat(64);
// writer+reader pair: the canonical auto spelling 'cleared' must survive the
// fail-closed write path, while legacy 'ratified' objects and bare ts-string
// approvals (human `gos approve`) still parse untouched
const st = JSON.parse(fs.readFileSync('.gos/state.json', 'utf8'));
st.approvals.THINK = {
  status: 'cleared', ts: '2026-10-31T00:00:00.000Z', mode: 'auto', stage: 'THINK',
  evidence: { spawnId: 'x', streamSha256: hex64, stampCount: 1 },
};
st.approvals.PLAN = { status: 'ratified', ts: '2026-10-31T00:00:00.000Z', mode: 'auto', stage: 'PLAN' };
st.approvals.INTENT = '2026-10-30T00:00:00.000Z';
stateMod.writeState(st);
const back = stateMod.readState();
if (!back || !back.approvals) problems.push('read-back missing approvals');
else {
  const think = back.approvals.THINK || {};
  if (think.status !== 'cleared') problems.push('cleared not preserved: ' + think.status);
  if (!think.evidence || think.evidence.streamSha256 !== hex64 || think.evidence.stampCount !== 1) problems.push('cleared evidence mangled');
  if ((back.approvals.PLAN || {}).status !== 'ratified') problems.push('legacy ratified not preserved');
  if (back.approvals.INTENT !== '2026-10-30T00:00:00.000Z') problems.push('bare-string approval not preserved');
}
const raw = fs.readFileSync('.gos/state.json', 'utf8');
if (!raw.includes('"cleared"') || !raw.includes(hex64)) problems.push('tracked bytes lost cleared status or evidence');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
D9_OUT="$(node run-d9.cjs 2>&1 | tail -n 1)"
t105_eq "approvals schema: 'cleared' round-trips write+read; legacy 'ratified' and bare-string approvals still parse" "OK" "$D9_OUT"

# ---------------------------------------------------------------- PV --
# provenance re-verification: PENDING converts to cleared with store-paired
# evidence; legacy records and bare strings grandfather as pre-loop; claims
# inside the loop window without pairing hold and render claimed-not-verified
t105_case pv
t105_state THINK > .gos/state.json
cat > run-pv.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const ratify = require(path.join(GR, 'bin/lib/ops/auto/ratify.cjs'));
const rootDir = process.cwd();
const problems = [];
const hex = (t) => crypto.createHash('sha256').update(t).digest('hex');
const loopStart = '2026-06-01T00:00:00.000Z';
// PENDING -> cleared conversion over a fixture stamp
store.create({ mode: 'on', rootDir });
const sha = hex('pv conversion stream');
store.stampStream('pv-spawn-1', 'THINK', sha, new Date().toISOString(), rootDir);
const stateFile = path.join(rootDir, '.gos', 'state.json');
const state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
state.approvals.THINK = { status: 'PENDING', ts: '2026-01-01T00:00:00.000Z', mode: 'auto', stage: 'THINK' };
fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
const conv = ratify.ratify({ stage: 'THINK', spawnId: 'pv-spawn-1', streamSha256: sha }, { rootDir });
if (!conv.ok || conv.stored.status !== 'cleared') problems.push('ratify did not write cleared: ' + JSON.stringify(conv.stored && conv.stored.status));
if (!conv.stored.evidence || conv.stored.evidence.spawnId !== 'pv-spawn-1' || conv.stored.evidence.streamSha256 !== sha) problems.push('cleared evidence shape changed');
const stamps = store.load(rootDir).store.stamps;
// an in-loop conversion (ts after loop start) with pairing: store-verified
if (ratify.describeApproval(conv.stored, { loopStartIso: loopStart, stamps }) !== 'cleared (store-verified)') problems.push('paired cleared not rendered store-verified');
const vpPaired = ratify.verifyProvenance({ approvals: { THINK: conv.stored }, loopStartIso: loopStart, stamps });
if (!vpPaired.ok || !vpPaired.results.some((r) => r.stage === 'THINK' && r.outcome === 'store-verified')) problems.push('paired cleared not verdict store-verified');
// legacy grandfather: old ratified object + old bare string stay cleared-tier
const legacyRec = { status: 'ratified', ts: '2026-01-02T00:00:00.000Z', mode: 'auto', stage: 'PLAN' };
const legacyStr = '2026-01-03T00:00:00.000Z';
if (!ratify.isRatified(legacyRec) || !ratify.isRatified(legacyStr)) problems.push('legacy records left the cleared tier');
const vpLegacy = ratify.verifyProvenance({ approvals: { PLAN: legacyRec, THINK: legacyStr }, loopStartIso: loopStart, stamps });
if (!vpLegacy.ok) problems.push('legacy records held: ' + JSON.stringify(vpLegacy.reason));
for (const r of vpLegacy.results) if (r.outcome !== 'pre-loop legacy') problems.push('legacy outcome not pre-loop legacy: ' + r.stage);
if (ratify.describeApproval(legacyRec, { loopStartIso: loopStart, stamps }) !== 'cleared (pre-loop legacy)') problems.push('legacy record render wrong');
if (ratify.describeApproval(legacyStr, { loopStartIso: loopStart, stamps }) !== 'human') problems.push('legacy bare-string render wrong');
// forged bare string inside the loop window: holds and renders the claim
const forgedStr = new Date(Date.parse(loopStart) + 60000).toISOString();
const vpForged = ratify.verifyProvenance({ approvals: { THINK: forgedStr }, loopStartIso: loopStart, stamps });
if (vpForged.ok || vpForged.reason !== 'claimed-not-verified' || vpForged.stage !== 'THINK') problems.push('forged bare string not held: ' + JSON.stringify(vpForged.reason));
if (ratify.describeApproval(forgedStr, { loopStartIso: loopStart, stamps }) !== 'claimed-not-verified') problems.push('forged bare string render wrong');
// cleared record inside the loop window without pairing: held
const unpaired = { status: 'cleared', ts: forgedStr, mode: 'auto', stage: 'PLAN', evidence: { spawnId: 'pv-ghost', streamSha256: hex('ghost'), stampCount: 1 } };
const vpUnpaired = ratify.verifyProvenance({ approvals: { PLAN: unpaired }, loopStartIso: loopStart, stamps });
if (vpUnpaired.ok || vpUnpaired.reason !== 'claimed-not-verified') problems.push('unpaired cleared record not held');
if (ratify.describeApproval(unpaired, { loopStartIso: loopStart, stamps }) !== 'claimed-not-verified') problems.push('unpaired cleared render wrong');
// advisory contexts (no loop start passed): nothing holds on age alone
const vpAdvisory = ratify.verifyProvenance({ approvals: { THINK: forgedStr, PLAN: unpaired }, stamps });
if (!vpAdvisory.ok) problems.push('advisory context refused: ' + JSON.stringify(vpAdvisory.reason));
// render taxonomy: PENDING record and absent record
if (ratify.describeApproval({ status: 'PENDING', ts: forgedStr, mode: 'auto', stage: 'THINK' }) !== 'pending') problems.push('PENDING render wrong');
if (ratify.describeApproval(undefined) !== 'pending') problems.push('absent render wrong');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
PV_OUT="$(node run-pv.cjs 2>&1 | tail -n 1)"
t105_eq "provenance: PENDING converts to cleared (store-verified); legacy grandfather; post-loop claims without pairing hold as claimed-not-verified" "OK" "$PV_OUT"

# ---------------------------------------------------------------- AB --
# marker-session approvals baseline: an absent baseline fails closed; a
# delegated advance whose approvals[stage] exists under a drifted map
# (diffusion) refuses; a matching baseline lets the sanctioned PENDING write
# proceed; manual (non-marker) commits never consult the baseline
t105_case ab
t105_state THINK > .gos/state.json
T105_EMPTY_BASE="$(node -e "console.log(require('crypto').createHash('sha256').update('{}').digest('hex'))")"
t105_ch_setup() { # $1=spawnId — runner-side channel: holder lock + spawn entry
  node -e "
const sr = require(process.env.GOS_ROOT + '/bin/lib/core/spawnreg.cjs');
const fs = require('fs');
fs.writeFileSync('.gos/.lock', JSON.stringify({pid: process.ppid, started_at: new Date().toISOString(), boot_id: null, starttime: sr.procStartTime(process.ppid)}));
sr.writeEntry(process.cwd(), {spawnId: '$1', kind: 'work', stage: 'THINK', pid: process.ppid, wallMs: 600000});
"
}
# absent baseline in a marker session: fail closed, nothing recorded
t105_ch_setup ab-no-base
GOS_AUTO_SPAWNED=1 GOS_AUTO_SPAWN_ID=ab-no-base node "$GOS" commit think > ab1.txt 2>&1; AB1_RC=$?
rm -f .gos/.lock
t105_exit "AB: marker commit without the approvals baseline fails closed" 1 "$AB1_RC"
t105_contains "AB: refusal names the missing baseline" "approvals-baseline-missing" "$(cat ab1.txt)"
AB1_LEFT="$(python3 -c "import json;print('THINK' in json.load(open('.gos/state.json'))['approvals'])")"
t105_eq "AB: fail-closed refusal records no approval" "False" "$AB1_LEFT"
# diffusion: a forged THINK record the runner never passed refuses
node -e "
const fs = require('fs');
const f = '.gos/state.json';
const st = JSON.parse(fs.readFileSync(f, 'utf8'));
st.approvals.THINK = new Date().toISOString();
fs.writeFileSync(f, JSON.stringify(st, null, 2));
"
t105_ch_setup ab-diffuse
GOS_AUTO_SPAWNED=1 GOS_AUTO_SPAWN_ID=ab-diffuse GOS_AUTO_APPROVALS_BASELINE="$T105_EMPTY_BASE" node "$GOS" commit think > ab2.txt 2>&1; AB2_RC=$?
rm -f .gos/.lock
t105_exit "AB: drifted approvals record refuses (diffusion)" 1 "$AB2_RC"
t105_contains "AB: refusal names approvals-diffusion" "approvals-diffusion" "$(cat ab2.txt)"
# matching baseline: the sanctioned PENDING write proceeds
node -e "
const fs = require('fs');
const f = '.gos/state.json';
const st = JSON.parse(fs.readFileSync(f, 'utf8'));
delete st.approvals.THINK;
fs.writeFileSync(f, JSON.stringify(st, null, 2));
"
t105_ch_setup ab-ok
GOS_AUTO_SPAWNED=1 GOS_AUTO_SPAWN_ID=ab-ok GOS_AUTO_APPROVALS_BASELINE="$T105_EMPTY_BASE" node "$GOS" commit think > ab3.txt 2>&1; AB3_RC=$?
rm -f .gos/.lock
t105_exit "AB: matching baseline lets the delegated advance record its PENDING" 0 "$AB3_RC"
AB3_APP="$(python3 -c "import json;a=json.load(open('.gos/state.json'))['approvals']['THINK'];print(a['status'],a['mode'])")"
t105_eq "AB: persisted approval is PENDING/auto" "PENDING auto" "$AB3_APP"

# manual commit (marker absent) never consults the baseline guard
t105_case ab2
t105_state THINK > .gos/state.json
node -e "
const fs = require('fs');
const f = '.gos/state.json';
const st = JSON.parse(fs.readFileSync(f, 'utf8'));
st.approvals.THINK = new Date().toISOString();
fs.writeFileSync(f, JSON.stringify(st, null, 2));
"
node "$GOS" commit think > ab4.txt 2>&1; AB4_RC=$?
t105_exit "AB: manual commit ignores the approvals baseline guard" 0 "$AB4_RC"
if grep -q "approvals-baseline-missing\|approvals-diffusion" ab4.txt; then
  t105_bad "AB: manual commit surfaced a baseline refusal"
else
  t105_ok "AB: manual commit free of baseline refusals"
fi

# ---------------------------------------------------------------- SR --
t105_case sr
cat > run-sr.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const spawnrun = require(path.join(GR, 'bin/lib/ops/auto/spawnrun.cjs'));
const problems = [];
const run = (script, opts) => spawnrun.spawnRun({
  argv: [process.execPath, '-e', script],
  cwd: process.cwd(),
  env: { ...process.env },
}, opts);
(async () => {
  // stalled stream: one chunk then silence — the idle killer fires live
  const stalled = await run('process.stdout.write("first-chunk\\n"); setInterval(() => {}, 1000);', { idleMs: 400, wallMs: 10000 });
  if (!stalled.error || stalled.error.idle !== true || stalled.error.killed !== true) problems.push('stalled stream not idle-killed');
  if (stalled.status !== null) problems.push('idle kill must resolve status null');
  if (!String(stalled.stdout).includes('first-chunk')) problems.push('idle kill lost the captured chunk');
  // wall killer: a chatty forever-child is killed at the wall clock
  const walled = await run('setInterval(() => process.stdout.write("tick\\n"), 20);', { idleMs: 10000, wallMs: 400 });
  if (!walled.error || walled.error.killed !== true || walled.error.idle === true) problems.push('wall kill missing or misclassified');
  if (walled.status !== null) problems.push('wall kill must resolve status null');
  // streaming deny scan: the hit rides the payload even under tiny windows
  const denied = await run('process.stdout.write("running forbidden-cmd now\\n"); for (let i = 0; i < 40; i++) process.stdout.write("pad" + i + "\\n");', { idleMs: 5000, wallMs: 10000, deny: ['forbidden-cmd'], windows: { headBytes: 32, tailBytes: 32 } });
  if (denied.status !== 0 || denied.error) problems.push('deny-scan child exited dirty: ' + JSON.stringify(denied.status));
  if (!(denied.preTruncationDenyHits || []).some((h) => h.pattern === 'forbidden-cmd')) problems.push('streaming deny scan missed the hit');
  if (denied.windowHead.stdout.length !== 32) problems.push('head window not bounded to headBytes');
  // dual-window capture: head keeps the start, tail keeps the end
  const long = await run('for (let i = 0; i < 100; i++) process.stdout.write("L" + String(i).padStart(4, "0") + "\\n");', { windows: { headBytes: 16, tailBytes: 24 } });
  if (long.status !== 0 || long.error) problems.push('normal exit mangled');
  if (long.totalBytes.stdout !== long.stdout.length && long.totalBytes.stdout < 100 * 6) problems.push('totalBytes.stdout undercounts');
  if (!long.windowHead.stdout.toString().startsWith('L0000')) problems.push('head window lost the stream start');
  if (!long.windowTail.stdout.toString().includes('L0099')) problems.push('tail window lost the stream end');
  if (long.windowTail.stdout.length !== 24) problems.push('tail window not bounded to tailBytes');
  for (const side of ['stdout', 'stderr']) {
    for (const w of ['head', 'tail']) {
      if (!/^[0-9a-f]{64}$/.test((long.windowSha256s || {})[side][w])) problems.push('window sha256 missing for ' + side + '/' + w);
    }
  }
  // empty argv resolves the error shape instead of throwing
  const empty = await spawnrun.spawnRun({ argv: [] }, {});
  if (!empty.error || empty.status !== null) problems.push('empty argv not an error result');
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
SR_OUT="$(node run-sr.cjs 2>&1 | tail -n 1)"
t105_eq "spawnrun: idle killer kills a stalled stream live; wall killer bounds the run; deny hits stream-sampled; dual-window capture bounded with sha256 + totalBytes" "OK" "$SR_OUT"

# ---------------------------------------------------------------- MU1 --
t105_case mu1
cat > mu-worker.cjs <<'EOF'
const path = require('path');
const store = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/store.cjs'));
const rootDir = process.argv[2];
for (let i = 0; i < 50; i += 1) {
  const r = store.bumpSpawn(rootDir);
  if (!r.ok) { console.error('worker bump failed: ' + JSON.stringify(r.reason)); process.exit(1); }
}
console.log('WORKER-DONE');
EOF
cat > run-mu1.cjs <<'EOF'
const { spawn } = require('child_process');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const rootDir = process.cwd();
const problems = [];
store.create({ mode: 'on', rootDir });
const worker = () => new Promise((resolve) => {
  const c = spawn(process.execPath, [path.join(rootDir, 'mu-worker.cjs'), rootDir], { env: { ...process.env } });
  let out = '';
  c.stdout.on('data', (d) => { out += d; });
  c.on('exit', (code) => resolve({ code, out }));
});
(async () => {
  const results = await Promise.all([worker(), worker()]);
  for (const r of results) {
    if (r.code !== 0) problems.push('a worker failed: ' + r.out.trim());
  }
  const m = store.mirrors(rootDir);
  if (!m.ok || m.spawnCount !== 100) problems.push('lost update under concurrency: spawnCount=' + (m.ok ? m.spawnCount : m.reason));
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
MU1_OUT="$(node run-mu1.cjs 2>&1 | tail -n 1)"
t105_eq "store mutex: two concurrent mutators (50 bumps each) serialize — no lost counter update" "OK" "$MU1_OUT"

# ---------------------------------------------------------------- MU2 --
t105_case mu2
cat > mu-holder.cjs <<'EOF'
const path = require('path');
const store = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/store.cjs'));
const r = store.acquireMutateLock(process.argv[2], { waitMs: 3000 });
if (!r.ok) { console.error('holder acquire failed: ' + r.reason); process.exit(1); }
console.log('HELD');
setTimeout(() => process.exit(0), 3500);
EOF
cat > run-mu2.cjs <<'EOF'
const { spawn } = require('child_process');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const rootDir = process.cwd();
const problems = [];
store.create({ mode: 'on', rootDir });
const hold = spawn(process.execPath, [path.join(rootDir, 'mu-holder.cjs'), rootDir], { env: { ...process.env } });
hold.stdout.on('data', (d) => { if (String(d).includes('HELD')) held = true; });
let held = false;
const sleep = (ms) => new Promise((res) => setTimeout(res, ms));
(async () => {
  const deadline = Date.now() + 5000;
  while (!held && Date.now() < deadline) await sleep(20);
  if (!held) problems.push('holder child never acquired the mutex');
  const busy = store.bumpSpawn(rootDir, { waitMs: 600 });
  if (busy.ok || busy.reason !== 'store-busy') problems.push('held mutex past the wait did not fail closed: ' + JSON.stringify(busy.reason));
  if (!busy.holder || busy.holder.pid !== hold.pid) problems.push('store-busy refusal does not name the live holder');
  const done = new Promise((res) => hold.on('exit', res));
  await done;
  const after = store.bumpSpawn(rootDir, { waitMs: 3000 });
  if (!after.ok) problems.push('mutex not recoverable after the holder exits: ' + JSON.stringify(after.reason));
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
MU2_OUT="$(node run-mu2.cjs 2>&1 | tail -n 1)"
t105_eq "store mutex: held mutex past the bounded wait reports store-busy (fail closed, holder named); releases recover" "OK" "$MU2_OUT"

# ---------------------------------------------------------------- MU3 --
t105_case mu3
cat > run-mu3.cjs <<'EOF'
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const rootDir = process.cwd();
const problems = [];
// /proc/<pid>/stat field 22 (starttime), parsed after the last ')'
function starttimeOf(pid) {
  const stat = fs.readFileSync(`/proc/${pid}/stat`, 'utf8');
  return Number(stat.slice(stat.lastIndexOf(')') + 2).split(' ')[19]);
}
store.create({ mode: 'on', rootDir });
// recycled-pid holder: the pid IS alive (a live sleeper) but the recorded
// starttime belongs to a previous process — bare pid-liveness must not
// satisfy the reclaim check's block; full identity proves the holder gone
const sleeper = spawn(process.execPath, ['-e', 'setInterval(() => {}, 5000)'], { stdio: 'ignore' });
const bootId = fs.readFileSync('/proc/sys/kernel/random/boot_id', 'utf8').trim();
const lockPath = store.mutateLockPath(rootDir);
fs.writeFileSync(lockPath, JSON.stringify({
  hostname: os.hostname(), pid: sleeper.pid, boot_id: bootId,
  starttime: starttimeOf(sleeper.pid) + 7, created_at: new Date().toISOString(),
}));
const r = store.bumpSpawn(rootDir, { waitMs: 800 });
if (!r.ok) problems.push('recycled-pid holder blocked the mutation: ' + JSON.stringify(r.reason));
if (r.ok && r.mirrors.spawnCount !== 1) problems.push('reclaim mutation lost the counter bump');
const st = store.load(rootDir);
const records = st.ok ? st.store.breaker.records : [];
if (!records.some((x) => x.cls === 'takeover' && /recycled/.test(String(x.detail)))) problems.push('recycled-pid reclaim not audited as a takeover record');
sleeper.kill();
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
MU3_OUT="$(node run-mu3.cjs 2>&1 | tail -n 1)"
t105_eq "store mutex: recycled-pid holder (live pid, wrong starttime) reclaims with a takeover record — pid liveness alone cannot hold the lock" "OK" "$MU3_OUT"

# ---------------------------------------------------------------- MU4 --
t105_case mu4
cat > run-mu4.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const rootDir = process.cwd();
const problems = [];
store.create({ mode: 'on', rootDir });
const lockPath = store.mutateLockPath(rootDir);
const crossHost = () => fs.writeFileSync(lockPath, JSON.stringify({
  hostname: 'other-machine.example', pid: 424242, boot_id: 'b'.repeat(36),
  starttime: 1, created_at: new Date().toISOString(),
}));
// fresh cross-host holder: identity unreadable from this machine and the
// lock is not aged — fail closed as store-busy, never a blind reclaim
crossHost();
const busy = store.bumpSpawn(rootDir, { waitMs: 400 });
if (busy.ok || busy.reason !== 'store-busy') problems.push('fresh identity-unreadable holder was not store-busy: ' + JSON.stringify(busy.reason));
// aged past the threshold: the mtime fallback reclaims and audits it
crossHost();
const aged = new Date(Date.now() - 120000);
fs.utimesSync(lockPath, aged, aged);
const r = store.bumpSpawn(rootDir, { waitMs: 400, staleMs: 30000 });
if (!r.ok) problems.push('aged identity-unreadable holder was not reclaimed: ' + JSON.stringify(r.reason));
const st = store.load(rootDir);
const records = st.ok ? st.store.breaker.records : [];
if (!records.some((x) => x.cls === 'takeover' && /unreadable/.test(String(x.detail)))) problems.push('mtime-fallback reclaim missing its takeover record');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
MU4_OUT="$(node run-mu4.cjs 2>&1 | tail -n 1)"
t105_eq "store mutex: identity-unreadable holder fails closed while fresh, reclaims with a takeover record past the mtime threshold" "OK" "$MU4_OUT"

# ---------------------------------------------------------------- MU5 --
t105_case mu5
t105_state THINK > .gos/state.json
cat > run-mu5.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const rootDir = process.cwd();
const problems = [];
store.create({ mode: 'on', rootDir });
const sr = store.storeRoot(rootDir);
fs.mkdirSync(sr, { recursive: true });
const nfsTable = `tmpfs / tmpfs rw 0 0\nsrv:/export ${sr} nfs4 rw 0 0\n`;
const localTable = `tmpfs / tmpfs rw 0 0\n/dev/sda1 ${sr} ext4 rw 0 0\n`;
const refused = store.refuseNetworkStore(rootDir, { readMounts: () => nfsTable });
if (refused.ok || refused.reason !== 'network-store' || refused.fstype !== 'nfs4') problems.push('network store not refused: ' + JSON.stringify(refused.reason));
if (!store.refuseNetworkStore(rootDir, { readMounts: () => localTable }).ok) problems.push('local-disk store wrongly refused');
for (const fstype of ['nfs', 'cifs', '9p', 'ceph', 'lustre', 'fuse.sshfs']) {
  const t = `tmpfs / tmpfs rw 0 0\nsrv ${sr} ${fstype} rw 0 0\n`;
  if (store.refuseNetworkStore(rootDir, { readMounts: () => t }).ok) problems.push(fstype + ' not refused');
}
(async () => {
  const r = await loop.createLoop({
    rootDir, host: 'gos-fixture-host',
    env: { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' },
    readMounts: () => nfsTable,
  }).loop.run();
  if (r.status !== 'refused' || r.reason !== 'network-store') problems.push('auto run did not refuse the network store: ' + r.status + '/' + r.reason);
  if (!r.guidance || !String(r.guidance.what || r.guidance).includes('XDG_DATA_HOME')) problems.push('refusal guidance does not point XDG_DATA_HOME at local disk');
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
MU5_OUT="$(node run-mu5.cjs 2>&1 | tail -n 1)"
t105_eq "network-FS store: mount-table fixture refuses hard at auto run with XDG_DATA_HOME-local-disk guidance; local fstypes pass" "OK" "$MU5_OUT"

# ---------------------------------------------------------------- SV1 --
t105_case sv1
cat > run-sv1.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const rootDir = process.cwd();
const problems = [];
const hex = (t) => crypto.createHash('sha256').update(t).digest('hex');
const storeFile = path.join(store.storeRoot(rootDir), 'store.json');
const made = store.create({ mode: 'on', rootDir });
if (!made.ok) problems.push('store create failed');
// v1 fixture: schema-1 store whose stamps predate every telemetry field
const v1 = JSON.parse(JSON.stringify(made.store));
v1.store_schema_version = 1;
v1.stamps = {
  'sv-legacy-1': { stage: 'THINK', streamSha256: hex('s1'), spawnedAtIso: '2026-01-01T00:00:00.000Z', stampedAtIso: '2026-01-01T00:00:01.000Z' },
  'sv-legacy-2': { stage: 'PLAN', streamSha256: hex('s2'), spawnedAtIso: '2026-01-02T00:00:00.000Z', stampedAtIso: '2026-01-02T00:00:01.000Z' },
};
fs.writeFileSync(storeFile, JSON.stringify(v1, null, 2));
const m = store.load(rootDir);
if (!m.ok) problems.push('v1 store did not load: ' + m.reason);
else {
  if (m.store.store_schema_version !== 2) problems.push('v1 store not schema 2 in memory');
  if (m.migrated !== true) problems.push('load does not report the migration');
  for (const id of Object.keys(v1.stamps)) {
    const s = m.store.stamps[id] || {};
    if (s.stage !== v1.stamps[id].stage || s.streamSha256 !== v1.stamps[id].streamSha256) problems.push(id + ': legacy fields lost');
    if (s.modelPinned !== null || s.modelObserved !== null || s.headSha256 !== null || s.tailSha256 !== null) problems.push(id + ': nullable fields not normalized to null');
    if (s.commandCount !== 0 || s.totalBytes !== 0 || s.denyHits !== 0) problems.push(id + ': count fields not normalized to 0');
  }
}
// pure read never writes back: disk stays v1 until the next mutate
if (JSON.parse(fs.readFileSync(storeFile, 'utf8')).store_schema_version !== 1) problems.push('pure read rewrote the v1 store');
const bump = store.bumpSpawn(rootDir);
if (!bump.ok) problems.push('mutate over a migrated store failed: ' + bump.reason);
const afterBump = JSON.parse(fs.readFileSync(storeFile, 'utf8'));
if (afterBump.store_schema_version !== 2) problems.push('lazy write-back did not persist schema 2');
if ((afterBump.stamps['sv-legacy-1'] || {}).commandCount !== 0) problems.push('normalized stamp not persisted by write-back');
// advisory contract: self-reported values ride the stamp verbatim — the
// write path stores them, never branches on them
const tel = { modelPinned: 'pinned-model-x', modelObserved: 'whatever', commandCount: 999999, denyHits: 7, totalBytes: 424242, headSha256: hex('hh'), tailSha256: hex('tt') };
const adv = store.stampStream('sv-adv-1', 'SHIP', hex('adv'), new Date().toISOString(), rootDir, tel);
if (!adv.ok) problems.push('telemetry stamp failed: ' + adv.reason);
for (const [k, v] of Object.entries(tel)) {
  if ((adv.stamp || {})[k] !== v) problems.push('advisory field ' + k + ' not stored verbatim');
}
const reread = store.load(rootDir);
if (!reread.ok || JSON.stringify(reread.store.stamps['sv-adv-1']) !== JSON.stringify(adv.stamp)) problems.push('advisory stamp round-trip mismatch');
// malformed telemetry types refuse with a named error
if (store.stampStream('sv-bad-1', 'SHIP', hex('bad'), new Date().toISOString(), rootDir, { commandCount: 'lots' }).reason !== 'invalid-telemetry') problems.push('non-integer commandCount accepted');
if (store.stampStream('sv-bad-2', 'SHIP', hex('bad'), new Date().toISOString(), rootDir, { headSha256: 'not-hex' }).reason !== 'invalid-telemetry') problems.push('malformed window hash accepted');
// future schema still refuses with the existing refusal
const v3 = JSON.parse(fs.readFileSync(storeFile, 'utf8'));
v3.store_schema_version = 3;
fs.writeFileSync(storeFile, JSON.stringify(v3));
const f = store.load(rootDir);
if (f.status !== 'paused' || f.reason !== 'version-mismatch') problems.push('schema 3 not refused: ' + f.reason);
if (!(f.guidance && String(f.guidance.what).includes('v3'))) problems.push('refusal does not name v3');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
SV1_OUT="$(node run-sv1.cjs 2>&1 | tail -n 1)"
t105_eq "store v2: v1 stores migrate in memory (lazy write-back, pure reads never write); advisory telemetry stored verbatim; schema 3 refuses" "OK" "$SV1_OUT"

# ---------------------------------------------------------------- SV2 --
t105_case sv2
cat > run-sv2.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const rootDir = process.cwd();
const problems = [];
const hex = (t) => crypto.createHash('sha256').update(t).digest('hex');
const storeFile = path.join(store.storeRoot(rootDir), 'store.json');
const winDir = path.join(store.storeRoot(rootDir), 'windows');
const iso = () => new Date().toISOString();
store.create({ mode: 'on', rootDir });
// saveWindows: two sidecars under the store dir + window hashes and the
// retained byte total stamped
store.stampStream('sv-win-1', 'THINK', hex('w1'), iso(), rootDir, { denyHits: 1 });
const sw = store.saveWindows('sv-win-1', { head: 'HEAD-ONE\nline2\n', tail: 'TAIL-ONE\n' }, rootDir);
if (!sw.ok) problems.push('saveWindows failed: ' + sw.reason);
if (fs.readFileSync(path.join(winDir, 'sv-win-1.head.txt'), 'utf8') !== 'HEAD-ONE\nline2\n') problems.push('head sidecar content wrong');
if (fs.readFileSync(path.join(winDir, 'sv-win-1.tail.txt'), 'utf8') !== 'TAIL-ONE\n') problems.push('tail sidecar content wrong');
let s = store.load(rootDir).store.stamps['sv-win-1'];
if (s.headSha256 !== hex('HEAD-ONE\nline2\n')) problems.push('head window hash not stamped');
if (s.tailSha256 !== hex('TAIL-ONE\n')) problems.push('tail window hash not stamped');
if (s.totalBytes !== 'HEAD-ONE\nline2\n'.length + 'TAIL-ONE\n'.length) problems.push('retained byte total not stamped');
if (s.denyHits !== 1) problems.push('earlier advisory fields clobbered by saveWindows');
// binary windows hash their exact bytes
store.stampStream('sv-win-2', 'THINK', hex('w2'), iso(), rootDir);
store.saveWindows('sv-win-2', { head: Buffer.from([0, 1, 2, 255]), tail: '' }, rootDir);
s = store.load(rootDir).store.stamps['sv-win-2'];
if (s.headSha256 !== crypto.createHash('sha256').update(Buffer.from([0, 1, 2, 255])).digest('hex')) problems.push('binary head window hash wrong');
if (s.totalBytes !== 4) problems.push('binary retained byte total wrong');
// refusals: unstamped spawn, path-hostile spawnId, malformed windows
if (store.saveWindows('sv-ghost', { head: 'x', tail: 'y' }, rootDir).reason !== 'stamp-missing') problems.push('unstamped saveWindows not refused');
if (store.saveWindows('sv/../evil', { head: 'x', tail: 'y' }, rootDir).reason !== 'invalid-spawn-id') problems.push('path-hostile spawnId accepted');
if (store.saveWindows('sv-win-1', { head: 7, tail: 'y' }, rootDir).reason !== 'invalid-windows') problems.push('non-string window accepted');
// pruning at the stamp cap: sidecars die with their stamps, orphans swept
const CAP = 1000; // stamp cap (CAPS.stamps in store.cjs)
const disk = JSON.parse(fs.readFileSync(storeFile, 'utf8'));
disk.stamps = {};
const base = Date.UTC(2026, 0, 1);
for (let i = 0; i < CAP; i++) {
  disk.stamps['sv-seed-' + i] = { stage: 'THINK', streamSha256: hex('seed' + i), spawnedAtIso: new Date(base + i * 1000).toISOString(), stampedAtIso: new Date(base + i * 1000).toISOString() };
}
fs.writeFileSync(storeFile, JSON.stringify(disk));
for (const id of ['sv-seed-0', 'sv-seed-1', 'sv-seed-500']) {
  fs.writeFileSync(path.join(winDir, id + '.head.txt'), 'H' + id);
  fs.writeFileSync(path.join(winDir, id + '.tail.txt'), 'T' + id);
}
fs.writeFileSync(path.join(winDir, 'sv-orphan.head.txt'), 'ORPHAN');
// one stamp past the cap prunes the oldest (sv-seed-0) and sweeps orphans
store.stampStream('sv-fresh-1', 'SHIP', hex('f1'), iso(), rootDir);
store.saveWindows('sv-fresh-1', { head: 'FH', tail: 'FT' }, rootDir);
const after = store.load(rootDir).store;
if (Object.keys(after.stamps).length !== CAP) problems.push('stamp count not capped: ' + Object.keys(after.stamps).length);
if (after.stamps['sv-seed-0']) problems.push('oldest stamp not pruned');
if (!after.stamps['sv-seed-1'] || !after.stamps['sv-seed-500'] || !after.stamps['sv-fresh-1']) problems.push('surviving stamps lost');
const files = fs.readdirSync(winDir).sort();
const want = ['sv-fresh-1.head.txt', 'sv-fresh-1.tail.txt', 'sv-seed-1.head.txt', 'sv-seed-1.tail.txt', 'sv-seed-500.head.txt', 'sv-seed-500.tail.txt'].sort();
if (JSON.stringify(files) !== JSON.stringify(want)) problems.push('sidecar set after prune wrong: ' + files.join(','));
// the next prune drops the next oldest with its sidecars
store.stampStream('sv-fresh-2', 'SHIP', hex('f2'), iso(), rootDir);
const after2 = store.load(rootDir).store;
if (after2.stamps['sv-seed-1']) problems.push('second prune did not drop the next oldest');
if (fs.existsSync(path.join(winDir, 'sv-seed-1.head.txt')) || fs.existsSync(path.join(winDir, 'sv-seed-1.tail.txt'))) problems.push('pruned stamp sidecar survived');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
SV2_OUT="$(node run-sv2.cjs 2>&1 | tail -n 1)"
t105_eq "store v2: saveWindows persists hashed sidecars; cap pruning drops sidecars with stamps and sweeps orphans" "OK" "$SV2_OUT"

# ---------------------------------------------------------------- TL --
t105_case tl
cat > run-tl.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const opencode = require(path.join(GR, 'bin/lib/ops/auto/adapters/opencode.cjs'));
const codex = require(path.join(GR, 'bin/lib/ops/auto/adapters/codex.cjs'));
const problems = [];
// (a) opencode stream WITH a model field and three tool_use events — model
// text inside a message body is content, not a model field
const rich = opencode.parseEventStream([
  '{"type":"message","text":"session started on model fake-in-text"}',
  '{"type":"tool_use","part":{"tool":"bash","command":"ls -la"}}',
  '{"type":"tool_use","part":{"tool":"edit"}}',
  '{"type":"tool_use","part":{"tool":"bash"}}',
  '{"type":"result","model":"glm-9.9"}',
].join('\n') + '\n');
const richTel = opencode.extractTelemetry(rich);
if (richTel.modelObserved !== 'glm-9.9' || richTel.commandCount !== 3) problems.push('rich telemetry wrong: ' + JSON.stringify(richTel));
// several model fields: the latest self-report wins
const multi = opencode.parseEventStream('{"type":"message","model":"early-m"}\n{"type":"result","model":"late-m"}\n');
if (opencode.extractTelemetry(multi).modelObserved !== 'late-m') problems.push('latest model self-report not kept');
// (b) stream without model/tool events → null/null (unobserved, not zero)
const bare = opencode.parseEventStream('{"type":"message","text":"no telemetry"}\n{"type":"result"}\n');
const bareTel = opencode.extractTelemetry(bare);
if (bareTel.modelObserved !== null || bareTel.commandCount !== null) problems.push('absent telemetry not null: ' + JSON.stringify(bareTel));
// (c) malformed and non-object events never throw, contribute nothing
const messy = opencode.parseEventStream([
  '[1,2,3]',
  '"bare string"',
  '42',
  '{"type":"tool_use"',
  '{"type":"tool_use","part":{"tool":"bash"}}',
  '{"type":"result","model":"messy-m"}',
].join('\n') + '\n');
let messyTel = null;
try { messyTel = opencode.extractTelemetry(messy); } catch (e) { problems.push('extractTelemetry threw on messy events: ' + e.message); }
if (messyTel && (messyTel.modelObserved !== 'messy-m' || messyTel.commandCount !== 1)) problems.push('messy telemetry wrong: ' + JSON.stringify(messyTel));
for (const absent of [null, undefined, {}, { events: null }, { events: 'nope' }]) {
  try {
    const t = opencode.extractTelemetry(absent);
    if (t.modelObserved !== null || t.commandCount !== null) problems.push('absent outcome not null/null: ' + JSON.stringify(t));
  } catch (e) { problems.push('extractTelemetry threw on ' + JSON.stringify(absent)); }
}
// (d) codex recorded fixtures carry no model field and no command-execution
// item type (agentMessage items + turn.completed usage only) — null/null,
// nothing invented. The synthetic model-bearing line only exercises the
// tolerant generic scan, not a claimed host shape.
for (const f of codex.validateFixture()) {
  const t = codex.extractTelemetry(f);
  if (t.modelObserved !== null || t.commandCount !== null) problems.push('codex fixture telemetry not null/null: ' + f.name);
}
const cx = codex.validateFixture('{"type":"item.completed","item":{"type":"agentMessage","text":"hi"},"model":"m-x"}\n{"type":"turn.completed"}\n');
const cxTel = codex.extractTelemetry(cx);
if (cxTel.modelObserved !== 'm-x' || cxTel.commandCount !== null) problems.push('codex tolerant model scan wrong: ' + JSON.stringify(cxTel));
// (e) advisoryLine: all three shapes
const a1 = opencode.advisoryLine({ modelPinned: 'pinned-m', modelObserved: 'other-m', commandCount: 3, cap: 5 });
if (a1 !== 'self-report: model other-m (pinned pinned-m), commands 3 (cap 5) — advisory only') problems.push('mismatch line wrong: ' + a1);
const a2 = codex.advisoryLine({ modelPinned: 'm', modelObserved: 'm', commandCount: 9, cap: 5 });
if (a2 !== 'self-report: model m (pinned m), commands 9 (cap 5) — advisory only') problems.push('over-ceiling line wrong: ' + a2);
if (opencode.advisoryLine({}) !== null) problems.push('all-absent not null');
if (codex.advisoryLine({ cap: 5 }) !== null) problems.push('cap-only not null');
const a3 = opencode.advisoryLine({ modelPinned: 'm' });
if (a3 !== 'self-report: model unobserved (pinned m) — advisory only') problems.push('pin-only line wrong: ' + a3);
// (f) breaker-guard: the extract path returns data only — whatever the
// values say, no classification key ever rides the payload
const hostileLines = [];
for (let i = 0; i < 500; i++) hostileLines.push('{"type":"tool_use","part":{"tool":"bash"}}');
hostileLines.push('{"type":"result","model":"hostile-m"}');
const hostile = opencode.extractTelemetry(opencode.parseEventStream(hostileLines.join('\n') + '\n'));
const keys = Object.keys(hostile).sort();
if (JSON.stringify(keys) !== JSON.stringify(['commandCount', 'modelObserved'])) problems.push('extract output carries foreign keys: ' + keys.join(','));
if (keys.some((k) => /signal|breaker|trip|abort|fail|class/i.test(k))) problems.push('extract output carries a classification key');
if (hostile.commandCount !== 500) problems.push('hostile count wrong');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
TL_OUT="$(node run-tl.cjs 2>&1 | tail -n 1)"
t105_eq "T11: telemetry extractor tolerant over parsed events (null on absent, never throws) + advisoryLine renders mismatch/over-ceiling/absent — data only, no breaker signal" "OK" "$TL_OUT"

# ---------------------------------------------------------------- TL2 --
t105_case tl2
cat > run-tl2.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const opencode = require(path.join(GR, 'bin/lib/ops/auto/adapters/opencode.cjs'));
const codex = require(path.join(GR, 'bin/lib/ops/auto/adapters/codex.cjs'));
const problems = [];
// opencode pin: non-empty string → ['--model', <id>] verbatim; else []
if (JSON.stringify(opencode.pinnedModelArgs('glm-9.9')) !== JSON.stringify(['--model', 'glm-9.9'])) problems.push('opencode pin argv wrong');
for (const empty of ['', '   ', null, undefined, 42, {}]) {
  if (opencode.pinnedModelArgs(empty).length) problems.push('opencode pin accepted absent model: ' + JSON.stringify(empty));
}
// the pin lands between the flags and the prompt — argv the spawn cannot alter
const spec = opencode.buildSpawnSpec({ prompt: 'stage work', args: opencode.pinnedModelArgs('glm-9.9') });
if (JSON.stringify(spec.argv) !== JSON.stringify(['opencode', 'run', '--format', 'json', '--model', 'glm-9.9', 'stage work'])) problems.push('pin argv not verbatim in spec: ' + spec.argv.join(' '));
const plain = opencode.buildSpawnSpec({ prompt: 'stage work', args: opencode.pinnedModelArgs(null) });
if (JSON.stringify(plain.argv) !== JSON.stringify(['opencode', 'run', '--format', 'json', 'stage work'])) problems.push('empty pin changed the spec argv');
// codex: the exec model flag shape is unrecorded (adapter, fixtures and the
// registry matrix carry no model flag) — no flag invented
if (codex.pinnedModelArgs('glm-9.9').length) problems.push('codex pin argv invented a flag');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
TL2_OUT="$(node run-tl2.cjs 2>&1 | tail -n 1)"
t105_eq "T11: pinnedModelArgs — opencode pins --model verbatim into the spawn argv; codex flag unrecorded → no flag invented" "OK" "$TL2_OUT"

# ---------------------------------------------------------------- PS --
t105_case ps
# dedicated state: plan_path pins the fixture plan explicitly (the shared
# t105_state fixture carries a 41-char task_head that cannot anchor a task dir)
printf '{"schema_version":6,"level":3,"current_stage":"PLAN","completed_stages":["INTENT"],"intent":{"summary":"t105 plansnap fixture","confirmed":true},"task_head":"abc123def0123456789abcdef0123456789abcdef","spec_path":null,"plan_path":".gos/task/ps/plan.md","requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{}}' > .gos/state.json
cat > run-ps.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const plansnap = require(path.join(GR, 'bin/lib/task/plansnap.cjs'));
const planPath = path.join(process.cwd(), '.gos', 'task', 'ps', 'plan.md');
const problems = [];
const writePlan = (s) => { fs.mkdirSync(path.dirname(planPath), { recursive: true }); fs.writeFileSync(planPath, s); };
const freeze = () => plansnap.freezeOrRefreshPlanSnapshot(
  { current_stage: 'PLAN', plan_snapshot: null }, { force: false });
// (a) five-wave plan (the live dispatch plan shape): task entries carry wave,
// meta.waveValidation ok, BUILD entry passes
writePlan([
  '# Plan',
  '### Wave 1 (parallel — shared substrate)',
  '#### T1: constants home',
  '- **Covers**: D-8',
  '- **Files**: bin/lib/ops/auto/limits.cjs',
  '#### T2: spawn runner',
  '- **Covers**: D-5',
  '- **Files**: bin/lib/ops/auto/spawnrun.cjs, test/sections/T105-auto-depth.test.sh',
  '### Wave 2 (depends on Wave 1)',
  '#### T3: dispatch table',
  '- **Covers**: D-1',
  '- **Files**: templates/auto-dispatch.json, bin/lib/ops/auto/workers.cjs',
  '#### T4: store schema',
  '- **Covers**: D-5',
  '- **Files**: bin/lib/ops/auto/store.cjs',
  '### Wave 3 (depends on Wave 2)',
  '#### T5: plansnap waves',
  '- **Covers**: D-3',
  '- **Files**: bin/lib/task/plansnap.cjs',
  '### Wave 4 (depends on Wave 3)',
  '#### T6: render surfaces',
  '- **Covers**: D-4',
  '- **Files**: bin/lib/ops/auto/cli.cjs',
  '### Wave 5 (depends on Waves 1-4)',
  '#### T7: ledger',
  '- **Covers**: D-49',
  '- **Files**: census.json',
].join('\n') + '\n');
const a = freeze();
if (!a || a.ok === false) problems.push('five-wave freeze refused: ' + JSON.stringify(a && a.reason));
if (!a.meta || !a.meta.waveValidation || a.meta.waveValidation.ok !== true || a.meta.waveValidation.waves !== 5) {
  problems.push('meta.waveValidation not ok/5: ' + JSON.stringify(a.meta));
}
const waveOf = new Map(a.tasks.map((t) => [t.id, t.wave]));
const wantWaves = { T1: 1, T2: 1, T3: 2, T4: 2, T5: 3, T6: 4, T7: 5 };
for (const [id, w] of Object.entries(wantWaves)) {
  if (waveOf.get(id) !== w) problems.push('task ' + id + ' wave ' + waveOf.get(id) + ' != ' + w);
}
if (!plansnap.buildEntryCheck(a).ok) problems.push('five-wave BUILD entry refused');
// (b) gapped waves (1,3) refuse at freeze naming the missing middle
writePlan('# Plan\n### Wave 1\n\n#### T1: a\n- **Covers**: D-1\n- **Files**: test/a.sh\n\n### Wave 3\n\n#### T2: b\n- **Covers**: D-1\n- **Files**: test/b.sh\n');
const b = freeze();
if (!b || b.ok !== false || b.reason !== 'gapped-wave') problems.push('gapped not refused: ' + JSON.stringify(b && b.reason));
if (!String((b && b.detail) || '').includes('2')) problems.push('gapped detail does not name the missing wave');
// (c) duplicate `### Wave 2` heading refuses at freeze
writePlan('# Plan\n### Wave 1\n\n#### T1: a\n- **Covers**: D-1\n- **Files**: test/a.sh\n\n### Wave 2\n\n#### T2: b\n- **Covers**: D-1\n- **Files**: test/b.sh\n\n### Wave 2\n\n#### T3: c\n- **Covers**: D-1\n- **Files**: test/c.sh\n');
const c = freeze();
if (!c || c.ok !== false || c.reason !== 'duplicate-wave') problems.push('duplicate not refused: ' + JSON.stringify(c && c.reason));
if (!String((c && c.detail) || '').includes('2')) problems.push('duplicate detail does not name wave 2');
// (d) unsafe declared paths refuse at freeze, the offender named
const unsafe = ['.git/config', '/abs/path', 'foo/../bar', 'hooks/pre-push'];
for (let i = 0; i < unsafe.length; i += 1) {
  writePlan('# Plan\n### Wave 1\n\n#### T' + (i + 1) + ': unsafe\n- **Covers**: D-1\n- **Files**: ' + unsafe[i] + '\n');
  const d = freeze();
  if (!d || d.ok !== false || d.reason !== 'unsafe-path') problems.push('unsafe ' + unsafe[i] + ' not refused: ' + JSON.stringify(d && d.reason));
  if (!String((d && d.detail) || '').includes(unsafe[i])) problems.push('unsafe refusal does not name ' + unsafe[i]);
}
// (e) heading-less plan: freezes legally, verdict recorded zero-wave, BUILD
// entry refuses with guidance naming PLAN; legacy meta-less snapshots pass
writePlan('# Plan\n\n#### T1: simple\n- **Covers**: D-1\n- **Files**: test/one.sh\n\n#### T2: plain\n- **Covers**: D-1\n- **Files**: test/two.sh\n');
const e = freeze();
if (!e || e.ok === false) problems.push('zero-wave freeze refused: ' + JSON.stringify(e && e.reason));
const ev = ((e || {}).meta || {}).waveValidation || {};
if (ev.ok !== false || ev.reason !== 'zero-wave') problems.push('waveValidation not zero-wave: ' + JSON.stringify(ev));
if (!e.tasks || e.tasks.length !== 2) problems.push('zero-wave snapshot tasks missing');
if (e.tasks && e.tasks.some((t) => t.wave !== undefined)) problems.push('heading-less snapshot entries carry a wave');
const entry = plansnap.buildEntryCheck(e);
if (!entry || entry.ok !== false || entry.reason !== 'zero-wave') problems.push('BUILD entry not refused: ' + JSON.stringify(entry && entry.reason));
if (!String((entry && entry.guidance && entry.guidance.fix) || '').includes('PLAN')) problems.push('entry guidance does not name PLAN');
if (!plansnap.buildEntryCheck({ tasks: e.tasks, audit: [] }).ok) problems.push('legacy meta-less snapshot refused at BUILD entry');
// (f) single-wave plan: freezes with wave:1 stamped on every task and
// passes the BUILD entry check (a one-wave plan is a wave plan, not a
// wedge at the door)
writePlan('# Plan\n### Wave 1\n\n#### T1: solo\n- **Covers**: D-1\n- **Files**: test/solo.sh\n');
const f = freeze();
if (!f || f.ok === false) problems.push('single-wave freeze refused: ' + JSON.stringify(f && f.reason));
const fv = ((f || {}).meta || {}).waveValidation || {};
if (fv.ok !== true || fv.waves !== 1) problems.push('single-wave waveValidation not ok/1: ' + JSON.stringify(fv));
if (!f.tasks || f.tasks.length !== 1 || f.tasks[0].wave !== 1) problems.push('single-wave task not stamped wave 1: ' + JSON.stringify(f.tasks));
if (!plansnap.buildEntryCheck(f).ok) problems.push('single-wave BUILD entry refused');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
PS_OUT="$(node run-ps.cjs 2>&1 | tail -n 1)"
t105_eq "T14: plansnap — frozen tasks carry wave; gapped/duplicate/unsafe refuse at freeze; zero-wave freezes but refuses BUILD entry with PLAN guidance; single-wave freezes wave 1 and enters BUILD" "OK" "$PS_OUT"

echo "--- T105 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
