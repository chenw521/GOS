// ops/auto/loop — the full-auto stage loop runner. Drives one GOS task from
// any work stage to the SHIP boundary by spawning ONE fresh host session per
// stage iteration through the adapter registry, composed under a launcher
// capability profile. Guards in order: the spawned-session marker refuses the
// auto family inside spawned envs; the machine-local store must load and be
// mode-on; the exclusive run lock rejects second instances naming the holder;
// the loop never runs on a trunk branch (it creates/joins a per-task work
// branch). Every iteration revalidates task identity and delta origin — a
// mutation made outside the loop pauses with a report and never counts into
// the breaker's consecutive layer; head drift from a spawn's own
// non-advancing commits is scored as rc0-no-advance instead. Delegated
// stages (THINK/PLAN) gain runner-side legs after their spawn exits: THINK
// must first clear a two-pass independent red-team review under the
// double-zero rule, then both stages have their in-spawn PENDING approval
// ratified from the store stamp; findings or failed rounds hold the stage
// for human review. At SHIP a green delivery probe runs the mechanical
// publish leg (branch push -> PR -> subject lint -> squash merge -> CI
// watch); red CI and unknown-state watches pause for a human disposition.
// Spawn outcomes flow through the three-layer breaker (consecutive N, stage
// visits K, spawn budget B) with class-tagged failures; streams are
// sha256-stamped into the store at spawn exit before any consumer reads
// them. Reaching SHIP (or DONE) ends the loop cleanly; without a green
// delivery adapter nothing delivery-shaped runs.
//
// Every external effect (git, state reads, spawn, clock, host probe, engine
// probe, detached child) is injectable; the defaults are real.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawn: spawnChild, spawnSync } = require('node:child_process');

const store = require('./store.cjs');
const registry = require('./adapters/registry.cjs');
const launcher = require('./launcher.cjs');
const breakerMod = require('./breaker.cjs');
const core = require('../../core/index.cjs');

// Environment marker identifying a runner-spawned session: in-spawn commands
// consume it to know they are machine-generated, and the auto family refuses
// to run inside such sessions.
const SPAWN_MARKER_ENV = 'GOS_AUTO_SPAWNED';

// Trunk branches the loop never develops on (PR-only ruling).
const TRUNK_BRANCHES = Object.freeze(['main', 'master']);

// Stage termini: SHIP ends the loop (archive and delivery stay human gates
// and work with no delivery adapter), DONE means the task already closed.
const TERMINAL_STAGES = Object.freeze(['SHIP', 'DONE']);

const WORK_BRANCH_PREFIX = 'auto/';

// Run-lock heartbeat cadence during spawn waits. A healthy runner must never
// look stale while a long spawn blocks.
const DEFAULT_HEARTBEAT_INTERVAL_MS = 60 * 1000;

const SPAWN_MAX_BUFFER = 64 * 1024 * 1024;



// ---------- pure helpers ----------

// Spawn env template: the base environment plus the spawned-session marker.
// A fresh object every call — the template is never a reference to caller env.
function spawnEnvTemplate(baseEnv) {
  return { ...(baseEnv || {}), [SPAWN_MARKER_ENV]: '1' };
}

// Per-task work branch name, derived from the GOS task id.
function workBranchName(taskId) {
  const id = String(taskId || '').replace(/[^a-z0-9_-]/gi, '-').replace(/^[-.]+|[-.]+$/g, '') || 'task';
  return WORK_BRANCH_PREFIX + id;
}

// Scalar identity of a GOS task: who the task is and where it stands. Any
// drift between iterations is a mutation the loop did not cause.
function identityOf(state, head) {
  if (!store.isPlainObject(state)) return null;
  return {
    taskId: core.currentTaskId(state) || null,
    stage: state.current_stage || null,
    level: state.level ?? null,
    phaseName: state.phase_name || null,
    head: head || null,
  };
}

function identityDiff(expected, observed) {
  const fields = [];
  for (const k of Object.keys(expected)) {
    if (String(expected[k]) !== String(observed[k])) fields.push(`${k}: ${JSON.stringify(expected[k])} -> ${JSON.stringify(observed[k])}`);
  }
  return fields;
}

// Identity without the head field: post-spawn discrimination between a
// spawn's own non-advancing commits (head drift only) and a real external
// mutation (task/phase/stage identity or the owning branch moved).
function stripIdentityHead(identity) {
  const out = { ...(identity || {}) };
  delete out.head;
  return out;
}

// External-mutation probe between two identity snapshots plus the branch the
// loop owns. Head drift alone is NOT a mutation — a spawn may commit without
// advancing (that is rc0-no-advance, scored into the consecutive layer); a
// moved stage/task/level/phase identity or a branch switch is.
function mutationBetween(baseline, observed, expectedBranch, actualBranch) {
  if (!store.isPlainObject(baseline) || !store.isPlainObject(observed)) return null;
  const fields = identityDiff(stripIdentityHead(baseline), stripIdentityHead(observed));
  const branchMoved = typeof expectedBranch === 'string' && typeof actualBranch === 'string' && actualBranch !== expectedBranch;
  if (!fields.length && !branchMoved) return null;
  const parts = fields.slice();
  if (branchMoved) parts.push(`branch: ${JSON.stringify(expectedBranch)} -> ${JSON.stringify(actualBranch)}`);
  return { fields, branchMoved, branch: actualBranch, detail: parts.join('; ') };
}

// Runner-held stage prompt template: one-shot stage instruction. The loop
// never accepts prompt text from repo files.
function defaultPrompt(ctx) {
  return [
    `GOS auto runner session for stage ${ctx.stage} (task ${ctx.taskId}).`,
    `Repository: ${ctx.rootDir}`,
    `Work the ${ctx.stage} stage now, then advance it with \`gos commit ${String(ctx.stage).toLowerCase()}\`.`,
    'Archive and push are human gates — never attempt them.',
    'This session is one-shot: finish the stage or fail with a clear error; never loop.',
  ].join('\n');
}

// Adapter failure classes mapped onto breaker signals.
function signalForAdapterFailure(failureClass) {
  if (failureClass === 'stream-malformed-json') return 'stream-malformed';
  if (failureClass === 'stream-no-terminal-event') return 'stream-no-terminal';
  return 'task-failed';
}

// ---------- defaults ----------

function loopGitRunner(args, cwd) {
  return spawnSync('git', args, { encoding: 'utf8', cwd, stdio: ['ignore', 'pipe', 'pipe'] });
}

// Read the task state for one repo root from .gos/state.json. Missing ->
// null (no active task); unparsable -> { corrupt, error } (fail closed).
function defaultStateReader(rootDir) {
  const file = path.join(rootDir, '.gos', 'state.json');
  let raw;
  try { raw = fs.readFileSync(file, 'utf8'); }
  catch { return null; }
  try { return JSON.parse(raw); }
  catch (e) { return { corrupt: true, error: e && e.message }; }
}

// Real spawn: an event-loop-alive child process. The loop's own timers keep
// firing during the wait — run-lock heartbeats stay fresh, and the idle
// timeout (reset on every stream chunk) kills a stalled stream live instead
// of being classified after the fact. Resolves the spawnSync shape the
// scorer consumes; kill reasons ride on the error object.
function loopSpawnRunner(spec, ctx) {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawnChild(spec.argv[0], spec.argv.slice(1), {
        cwd: spec.cwd,
        env: spec.env,
        detached: true,
        stdio: ['ignore', 'pipe', 'pipe'],
      });
    } catch (e) {
      resolve({ status: null, stdout: '', stderr: '', error: e && e.message ? e : new Error(e && e.message || 'spawn failed') });
      return;
    }
    const cap = SPAWN_MAX_BUFFER;
    let out = '';
    let err = '';
    let idleTimer = null;
    let wallTimer = null;
    let killed = null;
    let settled = false;
    // Deny lines are detected as they stream in — before the capture window
    // can truncate them away — and ride on the result for the scorer.
    const denyScanner = launcher.makeStreamDenyScanner({ deny: Array.isArray(spec.deny) ? spec.deny : undefined });
    const finish = (payload) => {
      if (settled) return;
      settled = true;
      if (idleTimer) clearTimeout(idleTimer);
      if (wallTimer) clearTimeout(wallTimer);
      payload.preTruncationDenyHits = denyScanner.hits.slice();
      resolve(payload);
    };
    const kill = (why) => {
      if (killed) return;
      killed = why;
      try { process.kill(-child.pid, 'SIGKILL'); } catch { /* group gone */ try { child.kill('SIGKILL'); } catch { /* already gone */ } }
    };
    const armIdle = () => {
      if (idleTimer) clearTimeout(idleTimer);
      const ms = Number(ctx && ctx.idleMs);
      if (!(ms > 0)) return;
      idleTimer = setTimeout(() => kill('idle'), ms);
      if (typeof idleTimer.unref === 'function') idleTimer.unref();
    };
    child.stdout.on('data', (d) => { out += d; if (out.length > cap) out = out.slice(out.length - cap); denyScanner.feed(d); armIdle(); });
    child.stderr.on('data', (d) => { err += d; if (err.length > cap) err = err.slice(err.length - cap); denyScanner.feed(d); armIdle(); });
    const wallMs = Number(ctx && ctx.wallMs);
    if (wallMs > 0) {
      wallTimer = setTimeout(() => kill('wall'), wallMs);
      if (typeof wallTimer.unref === 'function') wallTimer.unref();
    }
    armIdle();
    child.on('error', (e) => finish({ status: null, stdout: out, stderr: err, error: e }));
    child.on('close', (code) => {
      if (killed === 'idle') finish({ status: null, stdout: out, stderr: err, error: Object.assign(new Error('spawn idle timeout'), { idle: true, killed: true }) });
      else if (killed === 'wall') finish({ status: null, stdout: out, stderr: err, error: Object.assign(new Error('spawn wall timeout'), { killed: true }) });
      else finish({ status: code, stdout: out, stderr: err });
    });
  });
}

// Real detach: spawns the CLI run command detached from this parent. The
// child's output tees into a machine-local run log so a silent exit is
// diagnosable from an artifact instead of a black hole.
function defaultDetacher(command, args, opts) {
  const logDir = path.join(opts.rootDir || process.cwd(), '.gos', 'logs');
  try { fs.mkdirSync(logDir, { recursive: true }); } catch { /* unwritable: fall back to ignore */ }
  let stdio = 'ignore';
  let logPath = null;
  try {
    logPath = path.join(logDir, `auto-run-${process.pid}-${Date.now()}.log`);
    const fd = fs.openSync(logPath, 'a');
    stdio = ['ignore', fd, fd];
  } catch { logPath = null; }
  const child = spawnChild(command, args, { detached: true, stdio, env: opts.env });
  child.unref();
  return { pid: child.pid, log: logPath };
}

function defaultCliEntry() {
  return process.execPath;
}

function defaultCliEntryArgs() {
  return [path.join(core.GOS_SELF_ROOT, 'bin', 'gos.cjs')];
}

// ---------- loop factory ----------

// create(opts) validates the pure configuration and returns { ok, loop }.
// Options (all injectable, all with working real defaults):
//   rootDir            repo root for git/store/state (default: resolved cwd)
//   host               adapter host name (default: 'opencode')
//   profile            launcher profile name (default: 'restricted')
//   env                environment override (marker, timeouts, fixture gate)
//   limits             N/K/B override (default: from the store)
//   prompt             string or fn({stage, taskId, rootDir}) -> prompt
//   maxIterations      safety ceiling on iterations (default: none)
//   breakLock          pass-through to the store run-lock acquisition
//   detach             run as a detached child instead of in-process
//   detacher           (command, args, {detached, env}) -> {pid}
//   gitRunner          (args, cwd) -> spawnSync shape
//   stateReader        () -> GOS state object | null | {corrupt}
//   spawnRunner        (spec, {wallMs}) -> spawnSync shape (sync or promise)
//   delivery           options bag for the SHIP publish leg: {subject, base,
//                      worker, baseline, gitRunner, privilegedRunner,
//                      ghRunner, lintRunner, ciStatus, sleep, timeoutMs,
//                      pollMs, publish (fn override)}
//   engineProbe        () -> {engine, version?} launcher probe stub
//   probeRunner        (command, args) -> {ok, out, err} host probe stub
//   heartbeatIntervalMs run-lock heartbeat cadence during spawn waits
//   now                () -> epoch ms clock
function createLoop(opts = {}) {
  const profile = typeof opts.profile === 'string' && opts.profile ? opts.profile : launcher.DEFAULT_PROFILE;
  if (!launcher.KNOWN_PROFILES.includes(profile)) {
    return {
      ok: false, status: 'error', reason: 'unknown-profile', profile,
      known: launcher.KNOWN_PROFILES.slice(),
      guidance: store.guidanceFor('auto.launcher.unknown-profile', { name: profile, known: launcher.KNOWN_PROFILES.join(', ') }),
    };
  }
  if (opts.limits != null) {
    const v = breakerMod.validateLimits(opts.limits);
    if (!v.ok) return v;
  }
  const host = typeof opts.host === 'string' && opts.host ? opts.host : 'opencode';

  const loop = { run: () => runLoop({ ...opts, profile, host }) };
  return { ok: true, loop, profile, host };
}

// ---------- run ----------

function report(base, extra) {
  return { ...base, ...(extra || {}) };
}

async function runLoop(opts) {
  const env = opts.env || process.env;
  const now = typeof opts.now === 'function' ? opts.now : Date.now;
  const rootDir = opts.rootDir ? path.resolve(String(opts.rootDir)) : (core.currentRootRealpath() || process.cwd());
  const gitRunner = typeof opts.gitRunner === 'function' ? opts.gitRunner : loopGitRunner;

  // Spawned sessions never run the auto family (the marker is the boundary).
  if (env[SPAWN_MARKER_ENV]) {
    return report({ ok: false, status: 'refused', reason: 'marker-active', guidance: store.guidanceFor('auto.loop.markerActive') });
  }

  // Detach mode: spawn the CLI run command as a detached child and return.
  // The child performs branch/lock/iteration work; the parent holds nothing
  // (no marker — the child IS the runner, not a spawned stage session).
  if (opts.detach) {
    const detacher = typeof opts.detacher === 'function' ? opts.detacher : defaultDetacher;
    const command = defaultCliEntry();
    const args = [...defaultCliEntryArgs(), 'auto', 'run'];
    const res = await detacher(command, args, { detached: true, rootDir, env: { ...env } });
    return report({ ok: true, status: 'detached', pid: res && res.pid, log: res && res.log, argv: [command, ...args] });
  }

  // Trust store: fail-closed load, then the mode gate (resume never
  // auto-spawns; `run` requires mode on).
  const loaded = store.load(rootDir);
  if (!loaded.ok) {
    return report({ ok: false, status: loaded.status, reason: loaded.reason, path: loaded.path, guidance: loaded.guidance });
  }
  if (loaded.store.mode !== 'on') {
    return report({ ok: false, status: 'refused', reason: 'mode-off', guidance: store.guidanceFor('auto.loop.modeOff') });
  }

  // Exclusive run lock: a second instance is refused and the holder named.
  const lock = store.acquireRunLock({ rootDir, breakLock: opts.breakLock === true });
  if (!lock.ok) {
    return report({ ok: false, status: 'refused', reason: lock.reason, holder: lock.holder || null, path: lock.path, guidance: lock.guidance });
  }

  const stateReader = typeof opts.stateReader === 'function' ? opts.stateReader : () => defaultStateReader(rootDir);
  const spawnRunner = opts.spawnRunner || loopSpawnRunner;
  const heartbeatIntervalMs = Number.isInteger(opts.heartbeatIntervalMs) ? opts.heartbeatIntervalMs : DEFAULT_HEARTBEAT_INTERVAL_MS;

  // Sanitized host-config seed: materialized once per RUN (before the loop
  // starts), consumed by every spawn's compose, cleaned in the finally.
  const seedState = (() => {
    const cacheDir = path.join(rootDir, '.gos', 'cache');
    try { fs.mkdirSync(cacheDir, { recursive: true }); } catch { /* unwritable — skip seeding */ }
    const sanitized = launcher.sanitizeHostConfig(env === process.env ? process.env : env);
    if (!sanitized.ok) {
      if (sanitized.reason === 'absent') console.error('⚠ auto seed: no host opencode config found — spawns run unseeded (today\'s masked behavior)');
      return { seedRoots: {}, cleanup: null };
    }
    if (sanitized.reason === 'unreadable' || sanitized.reason === 'not-a-dir') {
      console.error(`⚠ auto seed: host opencode config ${sanitized.reason} (${sanitized.dir}) — spawns run unseeded`);
      return { seedRoots: {}, cleanup: null };
    }
    if (sanitized.stripped.length) {
      console.error(`⚠ auto seed: stripped ${sanitized.stripped.length} secret/permission/expansion entr(y|ies) from the host opencode config: ${sanitized.stripped.slice(0, 6).join(', ')}${sanitized.stripped.length > 6 ? ' …' : ''}`);
    }
    try {
      const dir = launcher.materializeSeedDir(sanitized.files, cacheDir, 'auto-seed');
      return { seedRoots: { 'host-config': dir }, cleanup: dir };
    } catch (e) {
      console.error(`⚠ auto seed: materialization failed (${e.message}) — spawns run unseeded`);
      return { seedRoots: {}, cleanup: null };
    }
  })();

  try {
    return await drive({ opts, env, now, rootDir, gitRunner, stateReader, spawnRunner, heartbeatIntervalMs, loaded, seedRoots: seedState.seedRoots });
  } finally {
    if (seedState.cleanup) { try { fs.rmSync(seedState.cleanup, { recursive: true, force: true }); } catch { /* best effort */ } }
    store.releaseRunLock(rootDir);
  }
}

function readHead(gitRunner, rootDir) {
  const r = gitRunner(['rev-parse', 'HEAD'], rootDir);
  const out = String((r && r.stdout) || '').trim();
  return r && r.status === 0 && out ? out : null;
}

function currentBranch(gitRunner, rootDir) {
  const r = gitRunner(['rev-parse', '--abbrev-ref', 'HEAD'], rootDir);
  return r && r.status === 0 ? String(r.stdout || '').trim() : null;
}

// Branch posture: refuse detached HEAD (commits could not be attributed to a
// branch), leave any trunk by creating/joining the per-task work branch.
function ensureWorkBranch(gitRunner, rootDir, taskId) {
  const branch = currentBranch(gitRunner, rootDir);
  if (branch == null) {
    return { ok: false, reason: 'detached-head', guidance: store.guidanceFor('auto.loop.detachedHead') };
  }
  if (branch === 'HEAD') {
    return { ok: false, reason: 'detached-head', branch, guidance: store.guidanceFor('auto.loop.detachedHead') };
  }
  if (!TRUNK_BRANCHES.includes(branch)) return { ok: true, branch, switched: false };
  const work = workBranchName(taskId);
  const exists = gitRunner(['rev-parse', '--verify', '--quiet', work], rootDir);
  const step = exists && exists.status === 0
    ? gitRunner(['checkout', work], rootDir)
    : gitRunner(['checkout', '-b', work], rootDir);
  if (!step || step.status !== 0) {
    return {
      ok: false, reason: 'work-branch-failed', branch, work,
      detail: String((step && step.stderr) || '').trim() || 'git checkout failed',
      guidance: store.guidanceFor('auto.loop.workBranchFailed', { branch, work }),
    };
  }
  return { ok: true, branch: work, switched: true };
}

// ---------- the iteration engine ----------

async function drive(ctx) {
  const { opts, env, now, rootDir, gitRunner, stateReader, spawnRunner, heartbeatIntervalMs, loaded, seedRoots } = ctx;

  const iterations = [];
  const readTaskState = () => {
    const v = stateReader();
    if (v && v.corrupt) return { err: report({ ok: false, status: 'paused', paused: true, reason: 'state-corrupt', detail: v.error, guidance: store.guidanceFor('auto.loop.stateCorrupt') }) };
    if (!store.isPlainObject(v)) return { none: true };
    return { state: v };
  };

  // Task must be active; a task already at a terminus ends the loop cleanly
  // with no spawn adapter involvement at all.
  const first = readTaskState();
  if (first.err) return report(first.err, { iterations, breaker: null });
  if (first.none) {
    return report({ ok: false, status: 'refused', reason: 'no-task', guidance: store.guidanceFor('auto.loop.noTask') }, { iterations, breaker: null });
  }
  let taskState = first.state;
  const taskId = core.currentTaskId(taskState) || 'task';

  const stage0 = String(taskState.current_stage || '').toUpperCase();
  if (TERMINAL_STAGES.includes(stage0)) {
    return report({
      ok: true, status: stage0 === 'SHIP' ? 'ship' : 'done', reason: `stage-${stage0.toLowerCase()}`,
      deliveryAdapter: false, guidance: store.guidanceFor('auto.loop.taskAtEnd', { stage: stage0 }),
    }, { iterations, breaker: null });
  }

  // Host negotiation: only selectable hosts run; failures fail closed.
  const hostStatus = registry.hostStatus(opts.host, { env, runner: opts.probeRunner, home: env.HOME || os.homedir() });
  if (!hostStatus.selectable) {
    const g = hostStatus.failure || {};
    return report({
      ok: false, status: 'refused', reason: 'host-not-selectable', host: opts.host,
      hostFailure: g, guidance: store.guidanceFor('auto.loop.hostNotSelectable', { host: opts.host }),
    }, { iterations, breaker: null });
  }
  const adapter = registry.requireAdapter(opts.host);
  if (!adapter || typeof adapter.buildSpawnSpec !== 'function' || typeof adapter.parseEventStream !== 'function') {
    return report({ ok: false, status: 'refused', reason: 'host-not-selectable', host: opts.host, guidance: store.guidanceFor('auto.loop.hostNotSelectable', { host: opts.host }) }, { iterations, breaker: null });
  }

  // Breaker over the store limits (or the injected override).
  const made = breakerMod.createBreaker({ rootDir, limits: opts.limits || undefined });
  if (!made.ok) {
    return report({ ok: false, status: made.status, reason: made.reason, path: made.path, guidance: made.guidance }, { iterations, breaker: null });
  }
  const b = made.breaker;
  const breakerView = () => b.state();
  const endWith = (base) => report(base, { iterations, breaker: breakerView() });

  // Never develop on the trunk: create/join the per-task work branch.
  const branched = ensureWorkBranch(gitRunner, rootDir, taskId);
  if (!branched.ok) {
    return endWith({ ok: false, status: 'refused', reason: branched.reason, branch: branched.branch, work: branched.work || null, detail: branched.detail, guidance: branched.guidance });
  }
  const loopBranch = branched.branch;

  // Timeout policy (wall/idle): store-config defaults from `auto on
  // --timeout-*`, env overrides still win, fail-closed on malformed values.
  const tp = breakerMod.timeoutPolicy(env, store.isPlainObject(loaded.store.timeouts) ? loaded.store.timeouts : undefined);
  if (!tp.ok) {
    return endWith({ ok: false, status: 'error', reason: tp.reason, which: tp.which, guidance: tp.guidance });
  }

  // Identity baseline: what the loop last saw and takes responsibility for.
  let baseline = identityOf(taskState, readHead(gitRunner, rootDir));
  // Delegated leg carried into the next iteration: set after a spawn exits,
  // consumed after identity revalidation so a mutation pauses the loop
  // before any review spawn runs.
  let pendingLeg = null;
  const runId = crypto.randomUUID();
  const runTag = runId.slice(0, 8);
  let seq = 0;

  // Crash-safe delegation: a previous runner may have died between a
  // delegated advance and its ratification, leaving a PENDING approval no
  // in-memory leg will ever clear. The store stamps carry the pairing —
  // Heartbeat during spawn waits so a long-running spawn never makes the
  // runner's lock look stale. The run lock lives in the store; the repo-root
  // .gos/.lock this CLI process holds gets its mtime refreshed too, so a
  // long-lived runner never looks abandoned to a concurrent reader. Every
  // long wait in the loop — main spawns, delegated legs, red-team rounds —
  // runs under it.
  const withHeartbeat = async (fn) => {
    if (!(heartbeatIntervalMs > 0)) return fn();
    const rootLock = path.join(rootDir, '.gos', '.lock');
    const iv = setInterval(() => {
      store.heartbeatRunLock(rootDir);
      try { fs.utimesSync(rootLock, new Date(), new Date()); } catch { /* not held / gone */ }
    }, heartbeatIntervalMs);
    if (typeof iv.unref === 'function') iv.unref();
    try { return await fn(); } finally { clearInterval(iv); }
  };

   // recover the leg from the latest stamp of that stage and run the full
   // delegation sequence now, before any new spawn extends the task.
  {
    const modRatify = require('./ratify.cjs');
    const orphan = modRatify.advanceBlocker(taskState.approvals);
    if (orphan && modRatify.isDelegatedStage(orphan.stage)) {
      const stamps = store.isPlainObject(loaded.store.stamps) ? loaded.store.stamps : {};
      let best = null;
      for (const [sid, st] of Object.entries(stamps)) {
        if (!store.isPlainObject(st)) continue;
        if (String(st.stage || '').toUpperCase() !== String(orphan.stage).toUpperCase()) continue;
        if (!best || String(st.stampedAtIso || '') > String(best.st.stampedAtIso || '')) best = { sid, st };
      }
      if (!best) {
        return endWith({
          ok: false, status: 'paused', paused: true, reason: 'orphan-pending-unrecoverable', stage: orphan.stage,
          guidance: store.guidanceFor('auto.ratify.stampMissing', { spawnId: '(previous run)' }),
        });
      }
       const orphanLeg = { stage: String(orphan.stage).toUpperCase(), spawnId: best.sid, streamSha256: best.st.streamSha256, advanced: true, orphan: true };
       const legRes = await withHeartbeat(() => delegatedLegs({ leg: orphanLeg, opts, env, rootDir, spawnRunner, tp, now, runTag }));
       if (legRes.err) return report(legRes.err, { iterations, breaker: breakerView() });
       iterations.push({ spawnId: orphanLeg.spawnId, stage: orphanLeg.stage, signal: 'orphan-legs', delegation: legRes.summary });
     }
   }

  // Heartbeat during spawn waits so a long-running spawn never makes the
  // runner's lock look stale. The run lock lives in the store; the repo-root
  // .gos/.lock this CLI process holds gets its mtime refreshed too, so a
  // long-lived runner never looks abandoned to a concurrent reader.
  // (withHeartbeat lives above the orphan-leg recovery — every long wait in
  // the loop shares it.)

  // seedRoots was materialized once per RUN in runLoop (sanitized host
  // config); the compose below consumes it for every spawn.

  // Crashed-advance recovery: a group-kill landed between the in-spawn state
  // write and its git commit — the stage moved forward in state.json but no
  // stage-labeled advance commit exists at HEAD. The pre-advance snapshot
  // (written by the commit path) rolls the state back; the loop re-drives
  // the stage instead of pausing as external-mutation. Shared by the
  // post-spawn mutation check and the top-of-loop identity revalidation.
  const recoverCrashedAdvance = (baseIdentity, observedIdentity, stateObj) => {
    try {
      if (!baseIdentity || !observedIdentity || !stateObj) return false;
      const forward = Array.isArray(stateObj.completed_stages)
        && stateObj.completed_stages.map(String).includes(String(baseIdentity.stage));
      if (!forward) return false;
      if (String(baseIdentity.stage) === String(observedIdentity.stage)) return false;
      const logR = gitRunner(['log', '-1', '--format=%s', 'HEAD'], rootDir);
      const subj = String((logR && logR.stdout) || '');
      const hasAdvanceCommit = new RegExp(`chore\\(task\\): advance ${String(baseIdentity.stage).toLowerCase()}\\b`, 'i').test(subj);
      if (hasAdvanceCommit) return false;
      const snapPath = path.join(rootDir, '.gos', 'cache', 'state.snapshot');
      const snapRaw = fs.readFileSync(snapPath, 'utf8');
      const snap = JSON.parse(snapRaw);
      if (String(snap.current_stage || '').toUpperCase() !== String(baseIdentity.stage).toUpperCase()) return false;
      const tmp = `${snapPath}.rollback-tmp-${process.pid}`;
      fs.writeFileSync(tmp, snapRaw);
      fs.renameSync(tmp, path.join(rootDir, '.gos', 'state.json'));
      console.error(`⚠ crashed advance recovered: stage ${baseIdentity.stage} moved in state but its labeled commit never landed — state rolled back from the pre-advance snapshot; the stage will be re-driven`);
      return true;
    } catch { return false; }
  };

  for (;;) {
    // ---- identity revalidation: delta origin must be this loop ----
    const cur = readTaskState();
    if (cur.err) return report(cur.err, { iterations, breaker: breakerView() });
    if (cur.none) {
      return endWith({ ok: false, status: 'refused', reason: 'no-task', guidance: store.guidanceFor('auto.loop.noTask') });
    }
    taskState = cur.state;
    const observed = identityOf(taskState, readHead(gitRunner, rootDir));
    if (baseline && identityDiff(baseline, observed).length) {
      const fields = identityDiff(baseline, observed);
      // A spawn-attributed advance may settle in the state file one read
      // after its git commit: when the previous spawn was scored advanced,
      // the baseline still holds that spawn's stage, the only moved identity
      // field is the stage, and the observed history marks the old stage
      // completed (forward move — a stage-back never completes its victim),
      // the delta belongs to this loop and the baseline rebases.
      const forward = Array.isArray(taskState.completed_stages)
        && taskState.completed_stages.map(String).includes(String(baseline.stage));
      const lateAdvance = pendingLeg && pendingLeg.advanced === true
        && String(baseline.stage) === String(pendingLeg.stage)
        && fields.length === 1 && fields[0].startsWith('stage: ')
        && String(baseline.stage) !== String(observed.stage)
        && forward;
      // Crashed-advance window at the top-of-loop revalidation: the snapshot
      // rollback (recoverCrashedAdvance above) re-drives instead of pausing.
      if (!lateAdvance) {
        const crashedTop = recoverCrashedAdvance(baseline, observed, taskState);
        if (!crashedTop) {
          return endWith({
            ok: false, status: 'paused', paused: true, reason: 'external-mutation',
            expected: baseline, observed, detail: fields.join('; '),
            guidance: store.guidanceFor('auto.loop.externalMutation', { detail: fields.join('; ') }),
          });
        }
      }
    }
    baseline = observed;

    // ---- runner-side legs for the previous delegated spawn ----
    // A delegated-stage advance left a PENDING approval behind (structural
    // checks only, written inside the sandbox): THINK must clear the
    // red-team double-zero gate first, then the runner ratifies from the
    // store stamp. Held gates pause here — no auto-advance, no dispositions.
    if (pendingLeg) {
      const leg = pendingLeg;
      pendingLeg = null;
      const modRatify = require('./ratify.cjs');
      if (leg.advanced && modRatify.isDelegatedStage(leg.stage)) {
        const legRes = await withHeartbeat(() => delegatedLegs({ leg, opts, env, rootDir, spawnRunner, tp, now, runTag }));
        if (legRes.err) return report(legRes.err, { iterations, breaker: breakerView() });
        const legIter = iterations.find((i) => i.spawnId === leg.spawnId);
        if (legIter) legIter.delegation = legRes.summary;
      }
    }

    const stage = String(taskState.current_stage || '').toUpperCase();
    if (TERMINAL_STAGES.includes(stage)) {
      // Delivery is probe-gated: without a green adapter state in the store
      // the loop ends cleanly at SHIP with zero delivery involvement.
      let delivery = null;
      if (stage === 'SHIP' && deliveryProbeGreen(rootDir)) {
        const pub = await publishLeg({ opts, rootDir, taskId, taskState, now, withHeartbeat });
        if (!pub.ok) {
          // Red CI and unknown-state watches wait for a human disposition;
          // every other delivery failure pauses for review too. None of
          // these ever count into the breaker's consecutive layer.
          return endWith({
            ok: false, status: 'paused', paused: true, reason: pub.reason || 'delivery-failed',
            requiresDisposition: pub.requiresDisposition === true,
            detail: pub.detail, delivery: pub, guidance: pub.guidance,
          });
        }
        delivery = pub;
      }
      return endWith({
        ok: true, status: stage === 'SHIP' ? 'ship' : 'done', reason: `stage-${stage.toLowerCase()}`,
        deliveryAdapter: delivery != null, ...(delivery ? { delivery } : {}),
        guidance: store.guidanceFor('auto.loop.taskAtEnd', { stage }),
      });
    }

    // ---- iteration ceiling ----
    if (opts.maxIterations != null && iterations.length >= opts.maxIterations) {
      return endWith({ ok: true, status: 'iteration-cap', max: opts.maxIterations, guidance: store.guidanceFor('auto.loop.iterationCap', { max: String(opts.maxIterations) }) });
    }

    // ---- breaker pre-checks: K visits, B budget ----
    const tripNow = () => endWith({ ok: false, status: 'paused', paused: true, reason: 'breaker-tripped', trip: b.tripped(), guidance: b.tripped() && b.tripped().guidance });
    const visit = b.visit(stage);
    if (visit.tripped) return tripNow();
    if (!visit.ok) return endWith({ ok: false, status: 'paused', paused: true, reason: 'stage-invalid', detail: visit.reason });
    const budget = b.checkBudget();
    if (budget.tripped) return tripNow();
    if (!budget.ok) return endWith({ ok: false, status: 'paused', paused: true, reason: budget.reason || 'budget-read-failed', path: budget.path, guidance: budget.guidance });

    // ---- compose the spawn: launcher profile + adapter spec ----
    const composed = launcher.compose(opts.profile, {
      workspace: rootDir,
      allowFull: opts.allowFull === true,
      env,
      engineProbe: opts.engineProbe,
      store,
      seedRoots: seedRoots || {},
      roBinds: hostStatus.probe && hostStatus.probe.execRoot ? [hostStatus.probe.execRoot] : [],
      authFiles: adapter.authFilePath ? [adapter.authFilePath(env)] : [],
      // Workspace-writing profiles grant the repo root (the profile data
      // deliberately never declares writable roots — compose-time supply is
      // the contract); restricted stays read-only outside .gos.
      writableRoots: opts.writableRoots || (
        opts.profile === 'workspace' || opts.profile === 'full'
          ? [rootDir, path.join(rootDir, '.gos'), path.join(rootDir, '.gos', 'logs')]
          : [path.join(rootDir, '.gos'), path.join(rootDir, '.gos', 'logs')]
      ),
    });
    if (!composed.ok) {
      const res = b.recordOutcome(stage, 'spawn-error', `launcher ${composed.code}`);
      if (res.tripped) return tripNow();
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'launch-failed', code: composed.code, guidance: store.guidanceFor('auto.loop.spawnComposeFailed', { detail: String(composed.code) }) });
    }

    const prompt = typeof opts.prompt === 'function' ? opts.prompt({ stage, taskId, rootDir })
      : typeof opts.prompt === 'string' ? opts.prompt
        : defaultPrompt({ stage, taskId, rootDir });

    // The adapter spec env carries the marker template; the launcher env
    // injects the composed permission config over it.
    const adapterSpec = adapter.buildSpawnSpec({
      prompt,
      env: spawnEnvTemplate(env === process.env ? {} : env),
      cwd: rootDir,
    });
    const specEnv = { ...adapterSpec.env, ...composed.env, [SPAWN_MARKER_ENV]: '1' };
    const argv = composed.tier === 'bubblewrap'
      ? ['bwrap', ...composed.argv, '--', ...adapterSpec.argv]
      : adapterSpec.argv.slice();
    const spec = {
      argv,
      env: specEnv,
      cwd: adapterSpec.cwd,
      prompt,
      stage,
      spawnId: `${runId}-${seq + 1}`,
      tier: composed.tier,
      profile: opts.profile,
      deny: composed.deny.slice(),
    };

    const preSpawnHead = readHead(gitRunner, rootDir);
    if (!preSpawnHead) {
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'no-head', guidance: store.guidanceFor('auto.breaker.advanceCheckFailed') });
    }

    // Dirty-file baseline: whatever was already uncommitted belongs to
    // someone outside this loop (a supervising human, another terminal).
    // The spawn carries the list so its in-spawn stage commit can refuse to
    // sweep those files into the advance commit. Bounded: pathological
    // working trees degrade to no baseline (guard off) rather than a
    // multi-megabyte env.
    let dirtyBaseline = null;
    try {
      const st = gitRunner(['status', '--porcelain', '-uall'], rootDir);
      if (st && st.status === 0) {
        const paths = String(st.stdout || '').split('\n').map((l) => l.slice(3).trim())
          .filter(Boolean).map((p) => p.replace(/^"|"$/g, ''))
          .slice(0, 400);
        if (paths.length) dirtyBaseline = JSON.stringify(paths);
      }
    } catch { /* status unreadable: guard off */ }
    if (dirtyBaseline) spec.env.GOS_AUTO_DIRTY_BASELINE = dirtyBaseline;

    // ---- spawn under heartbeat + wall clock ----
    store.heartbeatRunLock(rootDir);
    const startedAtMs = now();
    let result;
    try {
      result = await withHeartbeat(() => spawnRunner(spec, { wallMs: tp.wallSec * 1000, idleMs: tp.idleSec * 1000 }));
    } catch (e) {
      result = { status: null, stdout: '', stderr: '', error: e };
    }
    store.heartbeatRunLock(rootDir);
    const endedAtMs = now();

    // A spawned session happened: budget counter + stream stamp (before any
    // consumer could read the pairing).
    const bumped = store.bumpSpawn(rootDir);
    if (!bumped.ok) {
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'budget-write-failed', path: bumped.path, guidance: bumped.guidance });
    }
    const streamText = String((result && result.stdout) || '');
    const streamSha256 = crypto.createHash('sha256').update(streamText, 'utf8').digest('hex');
    const spawnedAtIso = new Date(startedAtMs).toISOString();
    const stamp = store.stampStream(spec.spawnId, stage, streamSha256, spawnedAtIso, rootDir);
    if (!stamp.ok) {
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'stamp-failed', detail: stamp.reason, path: stamp.path, guidance: store.guidanceFor('auto.loop.stampFailed', { detail: String(stamp.reason) }) });
    }

    seq += 1;
    const iter = {
      index: seq, stage, spawnId: spec.spawnId, preSpawnHead,
      head: null, signal: null, advanced: false, counted: false,
      streamSha256, spawnedAtIso, durationMs: endedAtMs - startedAtMs,
      escapeHits: 0, tier: spec.tier,
    };
    iterations.push(iter);

    // ---- post-spawn truth: read once, shared by scoring and the checks ----
    const after = readTaskState();
    if (after.err) return report(after.err, { iterations, breaker: breakerView() });
    if (after.none) {
      return endWith({ ok: false, status: 'refused', reason: 'no-task', guidance: store.guidanceFor('auto.loop.noTask') });
    }
    const postHead = readHead(gitRunner, rootDir);
    const postIdentity = identityOf(after.state, postHead);
    const mutation = mutationBetween(baseline, postIdentity, loopBranch, currentBranch(gitRunner, rootDir));

    // ---- score the outcome ----
    const scored = await score({ iter, spec, result, streamText, b, stage, gitRunner, rootDir, adapter, endedAtMs, idleMs: tp.idleSec * 1000, baseline, postIdentity, mutation });
    if (scored.err) return report(scored.err, { iterations, breaker: breakerView() });
    if (scored.tripped) return tripNow();

    // Carry the delegated leg (ratification pairs this spawn's stamp); a
    // pause below discards it and the PENDING blocks any further advance.
    pendingLeg = { stage, spawnId: spec.spawnId, streamSha256: iter.streamSha256, advanced: iter.advanced === true };

    if (iter.advanced && postIdentity.stage === stage) {
      // The advance commit landed but the stage state did not move with it —
      // loop-owned inconsistency, paused rather than retried blind.
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'advance-state-mismatch', expectedStage: stage, guidance: store.guidanceFor('auto.loop.externalMutation', { detail: `stage still ${stage} after an advance commit` }) });
    }
    let recoveredCrash = false;
    if (!iter.advanced && mutation && iter.signal !== 'rc0-no-advance') {
      // A failed-signal spawn alongside a stage-only forward delta with no
      // labeled commit is the crashed-advance window, not an external
      // mutation: recover from the snapshot and keep driving.
      recoveredCrash = recoverCrashedAdvance(baseline, postIdentity, after.state);
      if (!recoveredCrash) {
        // A failed-signal spawn alongside a concurrent external mutation: the
        // spawn's own failure is already scored; the mutation still pauses
        // with a report instead of retrying blind into a moved world.
        return endWith({
          ok: false, status: 'paused', paused: true, reason: 'external-mutation',
          expected: baseline, observed: postIdentity, detail: mutation.detail,
          guidance: store.guidanceFor('auto.loop.externalMutation', { detail: mutation.detail }),
        });
      }
    }
    if (!recoveredCrash) baseline = postIdentity;
    // Recovered: the state file is the pre-advance world again — keep the
    // pre-spawn baseline so the next revalidation sees a stable identity.
  }
}

// Classify one spawn result into a breaker signal, applying the escape
// detector and advance attribution. Never throws; git breakage during
// attribution pauses instead of scoring.
async function score(ctx) {
  const { iter, spec, result, streamText, b, stage, gitRunner, rootDir, endedAtMs, idleMs, adapter, baseline, postIdentity, mutation } = ctx;

  const runnerError = result && result.error;
  const idleKilled = !!(runnerError && runnerError.idle === true);
  const timedOut = !!(runnerError && (runnerError.code === 'ETIMEDOUT' || runnerError.killed === true || /timed?out/i.test(String(runnerError.message || ''))));
  const spawnBroke = !!runnerError;

  // Escape detector: pre-truncation streaming hits win (a huge benign tail
  // cannot push deny lines out of the captured window); the post-hoc scan
  // stays as the floor for runners that captured without a scanner.
  const denyForScan = Array.isArray(spec.deny) ? spec.deny : undefined;
  const hits = (result && Array.isArray(result.preTruncationDenyHits) && result.preTruncationDenyHits.length)
    ? result.preTruncationDenyHits
    : launcher.scanSpawnOutput(streamText, { deny: denyForScan });
  iter.escapeHits = hits.length;

  const outcome = adapter.parseEventStream(streamText);

  let signal = null;
  let detail = null;
  if (idleKilled) { signal = 'idle-timeout'; detail = 'stream stalled: no output chunk for the idle limit (killed live)'; }
  else if (timedOut) { signal = 'wall-timeout'; detail = 'spawn exceeded the wall clock'; }
  else if (spawnBroke) { signal = 'spawn-error'; detail = String(runnerError.message || 'spawn error'); }
  else if (hits.length) {
    signal = 'task-failed';
    detail = hits.map((h) => `deny '${h.pattern}': ${h.line.slice(0, 120)}`).join('; ');
  } else if (result && result.status !== 0 && result.status != null) {
    signal = 'task-failed';
    detail = `host exited rc=${result.status}${String(result.stderr || '').trim() ? ': ' + String(result.stderr).trim().slice(0, 240) : ''}`;
  } else if (!outcome.ok) {
    signal = signalForAdapterFailure(outcome.failure && outcome.failure.class);
    detail = outcome.failure && outcome.failure.message;
  } else if (outcome.lastEventAt != null && (endedAtMs - outcome.lastEventAt) > idleMs) {
    signal = 'idle-timeout';
    detail = `no stream event for ${Math.round((endedAtMs - outcome.lastEventAt) / 1000)}s (idle limit ${Math.round(idleMs / 1000)}s)`;
  }

  if (signal != null) {
    // A stage-labeled advance commit reachable from the post-spawn head is
    // the attribution of record: the work landed even when the process then
    // exited dirty, so the advance outranks the failure signal (the dirty
    // exit rides along as a note instead of burning the retry budget).
    // Escape-detector hits are the exception — a deny violation outranks
    // any progress the same session made.
    const escapeDriven = hits.length > 0;
    const advEarly = breakerMod.detectAdvance({ preSpawnHead: iter.preSpawnHead, cwd: rootDir, gitRunner, stage: iter.stage });
    if (!escapeDriven && advEarly.ok && advEarly.advanced === true) {
      iter.head = advEarly.head;
      iter.advanced = true;
      iter.dirtyExit = signal;
      iter.signal = 'advanced';
      iter.counted = false;
      const res = b.recordSuccess(stage);
      if (res.tripped) return { tripped: true };
      return {};
    }
    iter.signal = signal;
    const tax = breakerMod.classify(signal);
    iter.counted = !!(tax.ok && tax.countsTowardN);
    iter.detail = detail;
    const res = b.recordOutcome(stage, signal, detail);
    if (res.tripped) return { tripped: true };
    return {};
  }

  // rc 0 with a terminal event: advance attribution decides success vs
  // rc0-no-advance.
  const adv = breakerMod.detectAdvance({ preSpawnHead: iter.preSpawnHead, cwd: rootDir, gitRunner, stage: iter.stage });
  if (!adv.ok) {
    return {
      err: {
        ok: false, status: 'paused', paused: true, reason: 'advance-check-failed',
        detail: adv.detail, guidance: adv.guidance,
      },
    };
  }
  iter.head = adv.head;
  iter.advanced = adv.advanced === true;
  if (iter.advanced) {
    const res = b.recordSuccess(stage);
    if (res.tripped) return { tripped: true };
    iter.signal = 'advanced';
    iter.counted = false;
    return {};
  }
  iter.signal = 'rc0-no-advance';
  if (mutation) {
    // The missing advance may be the mutation's doing, not the spawn's: an
    // identity or delta-origin move during the spawn window pauses with a
    // report instead of counting into the consecutive layer.
    return {
      err: {
        ok: false, status: 'paused', paused: true, reason: 'external-mutation',
        expected: baseline, observed: postIdentity, detail: mutation.detail,
        guidance: store.guidanceFor('auto.loop.externalMutation', { detail: mutation.detail }),
      },
    };
  }
  iter.counted = true;
  const res = b.recordOutcome(stage, 'rc0-no-advance', 'terminal ok but no new stage-labeled commit reachable from HEAD');
  if (res.tripped) return { tripped: true };
  return {};
}

// ---------- runner-side delegated legs ----------
//
// ratify/redteam/delivery-publish all require this module; requiring them at
// the top would hand them a partially populated export object under Node's
// cycle resolution. Function-level requires run only after every module has
// finished loading.

// Two INDEPENDENT red-team review rounds over the THINK work, each a separate
// read-only spawn prompted from the runner-held store template. The
// double-zero rule needs findings=0 from both rounds; findings>0 or rounds
// without a verdict hold the stage for human review.
async function redteamPasses({ leg, opts, env, rootDir, spawnRunner, tp, now, runTag }) {
  const redteamMod = require('./redteam.cjs');
  const rounds = [];
  for (let i = 1; i <= redteamMod.REQUIRED_ZEROS; i += 1) {
    // Round ids carry the runner tag so a retry after a verdict-less or
    // failed attempt never collides with the previously stamped streams.
    const spawnId = `${leg.spawnId}-rt${i}${runTag ? '-' + runTag : ''}`;
    const round = await redteamMod.runRound({ stage: leg.stage, spawnId }, {
      rootDir,
      env,
      host: opts.host,
      profile: opts.profile,
      spawnRunner,
      engineProbe: opts.engineProbe,
      wallMs: tp.wallSec * 1000,
      now,
    });
    if (!round.ok) {
      return {
        err: {
          ok: false, status: 'paused', paused: true, reason: round.reason || 'redteam-round-failed',
          detail: round.detail, path: round.path, guidance: round.guidance,
        },
      };
    }
    rounds.push(round.round);
  }
  const clearance = redteamMod.evaluateClearance(rounds);
  if (!clearance.cleared) {
    const detail = clearance.held
      ? `red-team findings total ${clearance.findingsTotal} over ${clearance.totalRounds} round(s)`
      : `${clearance.independentZeros} independent findings=0 round(s) of ${clearance.requiredZeros} required, ${clearance.failedRounds} round(s) produced no verdict`;
    let text = detail;
    if (rounds.some((r) => r && r.readOnlyEnforcement === 'lexical')) {
      text += ` — ${core.t('auto.redteam.lexicalTier')}`;
    }
    return {
      err: {
        ok: false, status: 'paused', paused: true, reason: 'delegation-held', held: true,
        stage: leg.stage, rounds, clearance, detail,
        guidance: store.guidanceFor('auto.loop.delegationHeld', { stage: leg.stage, detail: text }),
      },
    };
  }
  return { rounds, clearance };
}

// Full leg sequence for one delegated advance: THINK clears the red-team
// gate, then the approval is ratified from the store stamp (converting the
// in-spawn PENDING record; a PENDING without this step blocks the next
// advance at the commit gate).
async function delegatedLegs({ leg, opts, env, rootDir, spawnRunner, tp, now, runTag }) {
  const modRatify = require('./ratify.cjs');
  let redteam = null;
  if (String(leg.stage).toUpperCase() === 'THINK') {
    const rt = await redteamPasses({ leg, opts, env, rootDir, spawnRunner, tp, now, runTag });
    if (rt.err) return rt;
    redteam = {
      rounds: rt.rounds.length,
      zeros: rt.clearance.independentZeros,
      tier: rt.rounds[0] && rt.rounds[0].tier,
    };
  }
  const ratified = modRatify.ratify({ stage: leg.stage, spawnId: leg.spawnId, streamSha256: leg.streamSha256 }, { rootDir });
  if (!ratified.ok) {
    return {
      err: {
        ok: false, status: 'paused', paused: true, reason: ratified.reason || 'ratify-refused',
        detail: ratified.detail, path: ratified.path, guidance: ratified.guidance,
      },
    };
  }
  return {
    ok: true,
    summary: { stage: leg.stage, redteam, ratified: true, keptExisting: ratified.keptExisting === true },
  };
}

// ---------- delivery leg ----------

// True when the store's latest delivery probe result is green (the only
// state under which any delivery-shaped action exists at all).
function deliveryProbeGreen(rootDir) {
  const delivery = require('./delivery.cjs');
  const loaded = store.load(rootDir);
  if (!loaded.ok) return false;
  const list = Array.isArray(loaded.store.probeResults) ? loaded.store.probeResults : [];
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const entry = list[i];
    if (store.isPlainObject(entry) && entry.host === delivery.PROBE_HOST) {
      return entry.state === 'green';
    }
  }
  return false;
}

// Mechanical publish leg at SHIP: push the per-task work branch, open the
// runner-rendered PR, lint the squash subject, squash-merge, watch CI. Red
// runs and unknown-state watches come back as held/disposition-unknown
// shapes the caller pauses on — never breaker counts. Every external effect
// is injectable through the `delivery` options bag.
async function publishLeg({ opts, rootDir, taskId, taskState, now, withHeartbeat }) {
  const publishMod = require('./delivery-publish.cjs');
  const deliveryOpts = store.isPlainObject(opts.delivery) ? opts.delivery : {};
  const subject = typeof deliveryOpts.subject === 'string' && deliveryOpts.subject.trim()
    ? deliveryOpts.subject.trim()
    : `chore(task): land task ${taskId} via auto delivery`;
  const shipLedger = {
    delegatedApprovals: Object.entries((taskState && taskState.approvals) || {})
      .filter(([, v]) => store.isPlainObject(v) && v.mode === 'auto')
      .map(([k]) => k),
  };
  if (Array.isArray(taskState && taskState.observable_truths)) shipLedger.verifyTruths = taskState.observable_truths;
  if (Array.isArray(taskState && taskState.redteam_rounds)) shipLedger.redteamFindings = taskState.redteam_rounds;
  const publisher = typeof deliveryOpts.publish === 'function' ? deliveryOpts.publish : publishMod.publish;
  return withHeartbeat(() => publisher({
    rootDir,
    taskId,
    branch: workBranchName(taskId),
    subject,
    base: deliveryOpts.base,
    worker: deliveryOpts.worker,
    shipLedger,
    baseline: deliveryOpts.baseline,
    gitRunner: opts.gitRunner,
    privilegedRunner: deliveryOpts.privilegedRunner,
    ghRunner: deliveryOpts.ghRunner,
    lintRunner: deliveryOpts.lintRunner,
    ciStatus: deliveryOpts.ciStatus,
    sleep: deliveryOpts.sleep,
    timeoutMs: deliveryOpts.timeoutMs,
    pollMs: deliveryOpts.pollMs,
    now,
  }));
}

module.exports = {
  SPAWN_MARKER_ENV,
  TRUNK_BRANCHES,
  TERMINAL_STAGES,
  WORK_BRANCH_PREFIX,
  DEFAULT_HEARTBEAT_INTERVAL_MS,
  spawnEnvTemplate,
  loopSpawnRunner,
  workBranchName,
  identityOf,
  identityDiff,
  defaultPrompt,
  createLoop,
};
