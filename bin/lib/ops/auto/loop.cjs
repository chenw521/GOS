// ops/auto/loop — the full-auto stage loop runner. Drives one GOS task from
// any work stage to the SHIP boundary by spawning ONE fresh host session per
// stage iteration through the adapter registry, composed under a launcher
// capability profile. Guards in order: the spawned-session marker refuses the
// auto family inside spawned envs; the machine-local store must load and be
// mode-on; the exclusive run lock rejects second instances naming the holder;
// the loop never runs on a trunk branch (it creates/joins a per-task work
// branch). Every iteration revalidates task identity and delta origin — a
// mutation made outside the loop pauses with a report and never counts into
// the breaker's consecutive layer. Spawn outcomes flow through the
// three-layer breaker (consecutive N, stage visits K, spawn budget B) with
// class-tagged failures; streams are sha256-stamped into the store at spawn
// exit before any consumer reads them. Reaching SHIP (or DONE) ends the loop
// cleanly with no delivery adapter involved.
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

function isPlainObject(v) {
  return v != null && typeof v === 'object' && !Array.isArray(v);
}

function guidanceFor(key, params) {
  const v = core.t(key, params);
  if (typeof v === 'string') return { what: v };
  return v;
}

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
  if (!isPlainObject(state)) return null;
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

function defaultGitRunner(args, cwd) {
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

// Real spawn: runs the composed argv to completion under the wall timeout.
// Returns the spawnSync shape the loop scores.
function defaultSpawnRunner(spec, ctx) {
  try {
    return spawnSync(spec.argv[0], spec.argv.slice(1), {
      cwd: spec.cwd,
      env: spec.env,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: ctx.wallMs,
      maxBuffer: SPAWN_MAX_BUFFER,
    });
  } catch (e) {
    return { status: null, stdout: '', stderr: '', error: e && e.message ? e : new Error(e && e.message || 'spawn failed') };
  }
}

// Real detach: spawns the CLI run command detached from this parent.
function defaultDetacher(command, args, opts) {
  const child = spawnChild(command, args, { detached: true, stdio: 'ignore', env: opts.env });
  child.unref();
  return { pid: child.pid };
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
//   engineProbe        () -> {engine, version?} launcher probe stub
//   probeRunner        (command, args) -> {ok, out, err} host probe stub
//   heartbeatIntervalMs run-lock heartbeat cadence during spawn waits
//   now                () -> epoch ms clock
function create(opts = {}) {
  const profile = typeof opts.profile === 'string' && opts.profile ? opts.profile : launcher.DEFAULT_PROFILE;
  if (!launcher.KNOWN_PROFILES.includes(profile)) {
    return {
      ok: false, status: 'error', reason: 'unknown-profile', profile,
      known: launcher.KNOWN_PROFILES.slice(),
      guidance: guidanceFor('auto.launcher.unknown-profile', { name: profile, known: launcher.KNOWN_PROFILES.join(', ') }),
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
  const gitRunner = typeof opts.gitRunner === 'function' ? opts.gitRunner : defaultGitRunner;

  // Spawned sessions never run the auto family (the marker is the boundary).
  if (env[SPAWN_MARKER_ENV]) {
    return report({ ok: false, status: 'refused', reason: 'marker-active', guidance: guidanceFor('auto.loop.markerActive') });
  }

  // Detach mode: spawn the CLI run command as a detached child and return.
  // The child performs branch/lock/iteration work; the parent holds nothing
  // (no marker — the child IS the runner, not a spawned stage session).
  if (opts.detach) {
    const detacher = typeof opts.detacher === 'function' ? opts.detacher : defaultDetacher;
    const command = defaultCliEntry();
    const args = [...defaultCliEntryArgs(), 'auto', 'run'];
    const res = await detacher(command, args, { detached: true, env: { ...env } });
    return report({ ok: true, status: 'detached', pid: res && res.pid, argv: [command, ...args] });
  }

  // Trust store: fail-closed load, then the mode gate (resume never
  // auto-spawns; `run` requires mode on).
  const loaded = store.load(rootDir);
  if (!loaded.ok) {
    return report({ ok: false, status: loaded.status, reason: loaded.reason, path: loaded.path, guidance: loaded.guidance });
  }
  if (loaded.store.mode !== 'on') {
    return report({ ok: false, status: 'refused', reason: 'mode-off', guidance: guidanceFor('auto.loop.modeOff') });
  }

  // Exclusive run lock: a second instance is refused and the holder named.
  const lock = store.acquireRunLock({ rootDir, breakLock: opts.breakLock === true });
  if (!lock.ok) {
    return report({ ok: false, status: 'refused', reason: lock.reason, holder: lock.holder || null, path: lock.path, guidance: lock.guidance });
  }

  const stateReader = typeof opts.stateReader === 'function' ? opts.stateReader : () => defaultStateReader(rootDir);
  const spawnRunner = opts.spawnRunner || defaultSpawnRunner;
  const heartbeatIntervalMs = Number.isInteger(opts.heartbeatIntervalMs) ? opts.heartbeatIntervalMs : DEFAULT_HEARTBEAT_INTERVAL_MS;

  try {
    return await drive({ opts, env, now, rootDir, gitRunner, stateReader, spawnRunner, heartbeatIntervalMs, loaded });
  } finally {
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
    return { ok: false, reason: 'detached-head', guidance: guidanceFor('auto.loop.detachedHead') };
  }
  if (branch === 'HEAD') {
    return { ok: false, reason: 'detached-head', branch, guidance: guidanceFor('auto.loop.detachedHead') };
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
      guidance: guidanceFor('auto.loop.workBranchFailed', { branch, work }),
    };
  }
  return { ok: true, branch: work, switched: true };
}

// ---------- the iteration engine ----------

async function drive(ctx) {
  const { opts, env, now, rootDir, gitRunner, stateReader, spawnRunner, heartbeatIntervalMs } = ctx;

  const iterations = [];
  const readTaskState = () => {
    const v = stateReader();
    if (v && v.corrupt) return { err: report({ ok: false, status: 'paused', paused: true, reason: 'state-corrupt', detail: v.error, guidance: guidanceFor('auto.loop.stateCorrupt') }) };
    if (!isPlainObject(v)) return { none: true };
    return { state: v };
  };

  // Task must be active; a task already at a terminus ends the loop cleanly
  // with no spawn adapter involvement at all.
  const first = readTaskState();
  if (first.err) return report(first.err, { iterations, breaker: null });
  if (first.none) {
    return report({ ok: false, status: 'refused', reason: 'no-task', guidance: guidanceFor('auto.loop.noTask') }, { iterations, breaker: null });
  }
  let taskState = first.state;
  const taskId = core.currentTaskId(taskState) || 'task';

  const stage0 = String(taskState.current_stage || '').toUpperCase();
  if (TERMINAL_STAGES.includes(stage0)) {
    return report({
      ok: true, status: stage0 === 'SHIP' ? 'ship' : 'done', reason: `stage-${stage0.toLowerCase()}`,
      deliveryAdapter: false, guidance: guidanceFor('auto.loop.taskAtEnd', { stage: stage0 }),
    }, { iterations, breaker: null });
  }

  // Host negotiation: only selectable hosts run; failures fail closed.
  const hostStatus = registry.hostStatus(opts.host, { env, runner: opts.probeRunner, home: env.HOME || os.homedir() });
  if (!hostStatus.selectable) {
    const g = hostStatus.failure || {};
    return report({
      ok: false, status: 'refused', reason: 'host-not-selectable', host: opts.host,
      hostFailure: g, guidance: guidanceFor('auto.loop.hostNotSelectable', { host: opts.host }),
    }, { iterations, breaker: null });
  }
  const adapter = registry.requireAdapter(opts.host);
  if (!adapter || typeof adapter.buildSpawnSpec !== 'function' || typeof adapter.parseEventStream !== 'function') {
    return report({ ok: false, status: 'refused', reason: 'host-not-selectable', host: opts.host, guidance: guidanceFor('auto.loop.hostNotSelectable', { host: opts.host }) }, { iterations, breaker: null });
  }

  // Breaker over the store limits (or the injected override).
  const made = breakerMod.create({ rootDir, limits: opts.limits || undefined });
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

  // Timeout policy (wall/idle) from env overrides, fail-closed.
  const tp = breakerMod.timeoutPolicy(env);
  if (!tp.ok) {
    return endWith({ ok: false, status: 'error', reason: tp.reason, which: tp.which, guidance: tp.guidance });
  }

  // Identity baseline: what the loop last saw and takes responsibility for.
  let baseline = identityOf(taskState, readHead(gitRunner, rootDir));
  const runId = crypto.randomUUID();
  let seq = 0;

  // Heartbeat during spawn waits so a long-running spawn never makes the
  // runner's lock look stale.
  const withHeartbeat = async (fn) => {
    if (!(heartbeatIntervalMs > 0)) return fn();
    const iv = setInterval(() => { store.heartbeatRunLock(rootDir); }, heartbeatIntervalMs);
    if (typeof iv.unref === 'function') iv.unref();
    try { return await fn(); } finally { clearInterval(iv); }
  };

  for (;;) {
    // ---- identity revalidation: delta origin must be this loop ----
    const cur = readTaskState();
    if (cur.err) return report(cur.err, { iterations, breaker: breakerView() });
    if (cur.none) {
      return endWith({ ok: false, status: 'refused', reason: 'no-task', guidance: guidanceFor('auto.loop.noTask') });
    }
    taskState = cur.state;
    const observed = identityOf(taskState, readHead(gitRunner, rootDir));
    if (baseline && identityDiff(baseline, observed).length) {
      const fields = identityDiff(baseline, observed);
      return endWith({
        ok: false, status: 'paused', paused: true, reason: 'external-mutation',
        expected: baseline, observed, detail: fields.join('; '),
        guidance: guidanceFor('auto.loop.externalMutation', { detail: fields.join('; ') }),
      });
    }
    baseline = observed;

    const stage = String(taskState.current_stage || '').toUpperCase();
    if (TERMINAL_STAGES.includes(stage)) {
      return endWith({ ok: true, status: stage === 'SHIP' ? 'ship' : 'done', reason: `stage-${stage.toLowerCase()}`, deliveryAdapter: false, guidance: guidanceFor('auto.loop.taskAtEnd', { stage }) });
    }

    // ---- iteration ceiling ----
    if (opts.maxIterations != null && iterations.length >= opts.maxIterations) {
      return endWith({ ok: true, status: 'iteration-cap', max: opts.maxIterations, guidance: guidanceFor('auto.loop.iterationCap', { max: String(opts.maxIterations) }) });
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
      env,
      engineProbe: opts.engineProbe,
      store,
      writableRoots: opts.writableRoots || [path.join(rootDir, '.gos'), path.join(rootDir, '.gos', 'logs')],
    });
    if (!composed.ok) {
      const res = b.recordOutcome(stage, 'spawn-error', `launcher ${composed.code}`);
      if (res.tripped) return tripNow();
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'launch-failed', code: composed.code, guidance: guidanceFor('auto.loop.spawnComposeFailed', { detail: String(composed.code) }) });
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
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'no-head', guidance: guidanceFor('auto.breaker.advanceCheckFailed') });
    }

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
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'stamp-failed', detail: stamp.reason, path: stamp.path, guidance: guidanceFor('auto.loop.stampFailed', { detail: String(stamp.reason) }) });
    }

    seq += 1;
    const iter = {
      index: seq, stage, spawnId: spec.spawnId, preSpawnHead,
      head: null, signal: null, advanced: false, counted: false,
      streamSha256, spawnedAtIso, durationMs: endedAtMs - startedAtMs,
      escapeHits: 0, tier: spec.tier,
    };
    iterations.push(iter);

    // ---- score the outcome ----
    const scored = await score({ iter, spec, result, streamText, b, stage, gitRunner, rootDir, adapter, endedAtMs, idleMs: tp.idleSec * 1000 });
    if (scored.err) return report(scored.err, { iterations, breaker: breakerView() });
    if (scored.tripped) return tripNow();

    // ---- refresh the identity baseline from post-spawn truth ----
    const after = readTaskState();
    if (after.err) return report(after.err, { iterations, breaker: breakerView() });
    if (after.none) {
      return endWith({ ok: false, status: 'refused', reason: 'no-task', guidance: guidanceFor('auto.loop.noTask') });
    }
    const postHead = readHead(gitRunner, rootDir);
    const postIdentity = identityOf(after.state, postHead);
    if (iter.advanced && postIdentity.stage === stage) {
      // The advance commit landed but the stage state did not move with it —
      // loop-owned inconsistency, paused rather than retried blind.
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'advance-state-mismatch', expectedStage: stage, guidance: guidanceFor('auto.loop.externalMutation', { detail: `stage still ${stage} after an advance commit` }) });
    }
    if (!iter.advanced && identityDiff(baseline, postIdentity).length) {
      return endWith({
        ok: false, status: 'paused', paused: true, reason: 'external-mutation',
        expected: baseline, observed: postIdentity,
        detail: identityDiff(baseline, postIdentity).join('; '),
        guidance: guidanceFor('auto.loop.externalMutation', { detail: identityDiff(baseline, postIdentity).join('; ') }),
      });
    }
    baseline = postIdentity;
  }
}

// Classify one spawn result into a breaker signal, applying the escape
// detector and advance attribution. Never throws; git breakage during
// attribution pauses instead of scoring.
async function score(ctx) {
  const { iter, spec, result, streamText, b, stage, gitRunner, rootDir, endedAtMs, idleMs, adapter } = ctx;

  const runnerError = result && result.error;
  const timedOut = !!(runnerError && (runnerError.code === 'ETIMEDOUT' || runnerError.killed === true || /timed?out/i.test(String(runnerError.message || ''))));
  const spawnBroke = !!runnerError;

  // Escape detector: deny hits in the captured stream are failures whatever
  // the exit code says.
  const denyForScan = Array.isArray(spec.deny) ? spec.deny : undefined;
  const hits = launcher.scanSpawnOutput(streamText, { deny: denyForScan });
  iter.escapeHits = hits.length;

  const outcome = adapter.parseEventStream(streamText);

  let signal = null;
  let detail = null;
  if (timedOut) { signal = 'wall-timeout'; detail = 'spawn exceeded the wall clock'; }
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
  iter.counted = true;
  const res = b.recordOutcome(stage, 'rc0-no-advance', 'terminal ok but no new stage-labeled commit reachable from HEAD');
  if (res.tripped) return { tripped: true };
  return {};
}

module.exports = {
  SPAWN_MARKER_ENV,
  TRUNK_BRANCHES,
  TERMINAL_STAGES,
  WORK_BRANCH_PREFIX,
  DEFAULT_HEARTBEAT_INTERVAL_MS,
  spawnEnvTemplate,
  workBranchName,
  identityOf,
  identityDiff,
  defaultPrompt,
  create,
};
