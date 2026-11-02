// ops/auto/loop — the full-auto stage loop runner. Drives one GOS task from
// any work stage to the SHIP boundary, composing every stage iteration from
// the dispatch table (templates/auto-dispatch.json): the table loads once at
// run-lock acquisition, its sha256 stamps into the trust store with run-start
// provenance, and every consume point (compose, spawn registration, hint
// resolution) re-verifies the live file against the stamp — mid-run drift is
// the external-mutation pause, never a reload. Per stage the entry decides
// the worker form: agent stages compose through the host adapter under the
// entry's pinned capability profile with entry-driven grants (ro-bound as an
// immutable manifest), scratch, testbed, and the model resolved from the
// entry's slot pinned into the spawn argv; BUILD additionally iterates the
// frozen plan snapshot's waves through the wave driver (breaker accounting on
// stage-wave labels) and exits through one final stage-exit advance spawn;
// script stages (VERIFY) run pinned Class P legs plus fixed-argv Class S
// spawns and never probe the host at all. Guards in order: the
// spawned-session marker refuses the auto family inside spawned envs; the
// machine-local store must load and be mode-on; the exclusive run lock
// rejects second instances naming the holder; the loop never runs on a trunk
// branch (it creates/joins a per-task work branch). Every iteration
// revalidates task identity and delta origin — a mutation made outside the
// loop pauses with a report and never counts into the breaker's consecutive
// layer; head drift from a spawn's own non-advancing commits is scored as
// rc0-no-advance instead. Delegated stages (THINK/PLAN) gain runner-side legs
// after their spawn exits: THINK must first clear a two-pass independent
// red-team review under the double-zero rule, then both stages have their
// in-spawn PENDING approval ratified from the store stamp; findings or failed
// rounds hold the stage for human review. Every spawn env carries the
// approvals baseline hash so a marker-session commit can refuse diffusion.
// At SHIP a green delivery probe runs the mechanical publish leg (branch
// push -> PR -> subject lint -> squash merge -> CI watch); red CI and
// unknown-state watches pause for a human disposition. Runner-trust leg
// modules (ratify/redteam/delivery) load from the pinned worktree when the
// pin can provide them and degrade to the live tree with a warning during
// the bootstrap transition. Spawn outcomes flow through the three-layer
// breaker (consecutive N, stage visits K, spawn budget B) with class-tagged
// failures; streams are sha256-stamped into the store at spawn exit — with
// the telemetry payload (pinned/observed model, command count, deny hits,
// dual-window hashes and sidecars) — before any consumer reads them.
// Reaching SHIP (or DONE) ends the loop cleanly; without a green delivery
// adapter nothing delivery-shaped runs.
//
// Every external effect (git, state reads, spawn, clock, host probe, engine
// probe, detached child, model resolution, pinned legs) is injectable; the
// defaults are real.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const store = require('./store.cjs');
const registry = require('./adapters/registry.cjs');
const launcher = require('./launcher.cjs');
const breakerMod = require('./breaker.cjs');
const spawnrun = require('./spawnrun.cjs');
const workers = require('./workers.cjs');
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

// Registered spawn write channel: the runner registers each spawn before
// launch and removes the entry at exit — the in-spawn gos commands carry
// the spawnId so the lock layer can admit the whitelisted stage verbs.
const spawnreg = require('../../core/spawnreg.cjs');



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

// BUILD stage-exit prompt: the wave driver owns the build work, so this spawn
// exists only to land the single stage advance through the commit channel —
// the PENDING/ratification boundary stays intact because the exit is a
// normal marker-session spawn.
function stageExitPrompt(ctx) {
  return [
    `GOS auto BUILD stage exit (task ${ctx.taskId}).`,
    `Repository: ${ctx.rootDir}`,
    'Every wave of the frozen plan snapshot is released. Run `gos commit build` now, then exit.',
    'Archive and push are human gates — never attempt them.',
    'This session is one-shot: run the single advance commit or fail with a clear error; never loop.',
  ].join('\n');
}

// sha256 of one file's bytes, null when unreadable.
function hashFileSha256(p) {
  try { return crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex'); }
  catch { return null; }
}

// Approvals baseline hash for spawn envs: sha256 of the JSON of the approvals
// map exactly as the pre-spawn state read carries it (the in-spawn commit
// path hashes the same map and refuses diffusion).
function approvalsBaselineOf(state) {
  const approvals = store.isPlainObject(state) && store.isPlainObject(state.approvals) ? state.approvals : {};
  return crypto.createHash('sha256').update(JSON.stringify(approvals), 'utf8').digest('hex');
}

// BUILD entry mode from the frozen plan snapshot: a snapshot whose wave
// validation passed drives the wave iterator; a snapshot carrying a failed
// validation refuses BUILD entry with guidance back to PLAN; tasks with no
// snapshot at all (or a pre-wave-era one without validation meta) stay on
// the legacy monolithic path — a single stage spawn, no wave accounting.
function buildModeFor(state) {
  const snap = store.isPlainObject(state) ? state.plan_snapshot : null;
  if (!store.isPlainObject(snap)) return { mode: 'monolithic' };
  const v = store.isPlainObject(snap.meta) ? snap.meta.waveValidation : null;
  if (!v) return { mode: 'monolithic' };
  if (v.ok === true) return { mode: 'waves', snapshot: snap };
  return {
    mode: 'refused', reason: v.reason, detail: v.detail,
    guidance: {
      what: 'BUILD entry refused: the frozen plan carries no wave structure',
      fix: 'return to PLAN — re-freeze plan.md with "### Wave N" headings (gos commit plan), then re-enter BUILD',
    },
  };
}

// Default model resolver: one CLI child per entry slot. The last JSON line
// with a string `model` wins; anything unresolvable (unknown slot, broken
// CLI, prose output) resolves to inherit — the adapter then pins no model
// argv at all.
function defaultModelResolver(slot) {
  if (typeof slot !== 'string' || !slot) return { model: 'inherit' };
  let r;
  try {
    r = spawnSync(defaultCliEntry(), [...defaultCliEntryArgs(), 'resolve-model', slot], { encoding: 'utf8', timeout: 30000 });
  } catch {
    return { model: 'inherit', hint: 'resolve-model spawn failed' };
  }
  const lines = String((r && r.stdout) || '').split(/\r?\n/).filter(Boolean);
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    try {
      const o = JSON.parse(lines[i]);
      if (o && typeof o.model === 'string' && o.model) return { model: o.model, ...(typeof o.hint === 'string' ? { hint: o.hint } : {}) };
    } catch { /* not the JSON line */ }
  }
  return { model: 'inherit' };
}

// Re-verify the live dispatch table against the store's stamp (run-start or
// the latest wave-released roll). Exported for hint resolution and any later
// consume point: a mismatch or a missing stamp is drift, never a reload.
function verifyDispatchTableStamp(rootDir, tableFile) {
  const read = store.readDispatchTableStamp(rootDir);
  if (!read.ok) return { ok: false, ...read };
  const live = hashFileSha256(tableFile);
  if (read.stamp == null) {
    return { ok: false, reason: 'dispatch-table-drift', detail: 'no dispatch-table stamp recorded for this store' };
  }
  if (live == null || live !== read.stamp.sha256) {
    return {
      ok: false, reason: 'dispatch-table-drift',
      detail: `dispatch table drifted from the store stamp (stamp ${read.stamp.sha256.slice(0, 10)} != live ${live == null ? 'unreadable' : live.slice(0, 10)})`,
      expected: read.stamp.sha256, observed: live,
    };
  }
  return { ok: true, sha256: live, stamp: read.stamp };
}

// Dirty-file baseline: whatever was already uncommitted when the iteration
// started belongs to someone outside this loop. Bounded to a sane list so a
// pathological working tree degrades to no baseline instead of a
// multi-megabyte env.
function dirtyBaselineOf(gitRunner, rootDir) {
  try {
    const st = gitRunner(['status', '--porcelain', '-uall'], rootDir);
    if (st && st.status === 0) {
      const paths = String(st.stdout || '').split('\n').map((l) => l.slice(3).trim())
        .filter(Boolean).map((p) => p.replace(/^"|"$/g, ''))
        .slice(0, 400);
      if (paths.length) return JSON.stringify(paths);
    }
  } catch { /* status unreadable: guard off */ }
  return null;
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

// Real spawn: composes the shared spawn runner — an event-loop-alive child
// process whose stream is supervised live (idle killer reset on every chunk,
// wall killer, streaming pre-truncation deny scan, head/tail dual-window
// capture). The loop's own timers keep firing during the wait — run-lock
// heartbeats stay fresh. Resolves the spawnSync shape the scorer consumes;
// kill reasons ride on the error object.
function loopSpawnRunner(spec, ctx) {
  return spawnrun.spawnRun(spec, {
    idleMs: ctx && ctx.idleMs,
    wallMs: ctx && ctx.wallMs,
    deny: Array.isArray(spec.deny) ? spec.deny : undefined,
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
  const child = spawnrun.spawnDetached(command, args, { stdio, env: opts.env });
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
//   profile            advisory run-level profile (per-stage composition is
//                      dispatch-table-driven; default: 'restricted')
//   env                environment override (marker, timeouts, fixture gate)
//   limits             N/K/B override (default: from the store)
//   prompt             string or fn({stage, taskId, rootDir}) -> prompt
//                      (agent stages only; BUILD stage-exit and script
//                      stages hold runner prompts)
//   maxIterations      safety ceiling on iterations (default: none)
//   breakLock          pass-through to the store run-lock acquisition
//   detach             run as a detached child instead of in-process
//   detacher           (command, args, {rootDir, env}) -> {pid}
//   gitRunner          (args, cwd) -> spawnSync shape
//   stateReader        () -> GOS state object | null | {corrupt}
//   spawnRunner        (spec, {wallMs}) -> spawnSync shape (sync or promise)
//   modelResolver      (slot) -> {model} override for the dispatch slots
//   legRunner          (step, ctx) -> {ok, verdict} pinned-leg override
//   tablePath          dispatch table file override (tests pin a fixture
//                      copy and flip it mid-run)
//   delivery           options bag for the SHIP publish leg: {subject, base,
//                      worker, baseline, gitRunner, privilegedRunner,
//                      ghRunner, lintRunner, ciStatus, sleep, timeoutMs,
//                      pollMs, publish (fn override)}
//   engineProbe        () -> {engine, version?} launcher probe stub
//   probeRunner        (command, args) -> {ok, out, err} host probe stub
//                      (script stages never call it)
//   heartbeatIntervalMs run-lock heartbeat cadence during spawn waits
//   mountsFile/readMounts mount-table override for the network-store refusal
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
    const res = await detacher(command, args, { rootDir, env: { ...env } });
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

  // Machine-local store only: a network filesystem under the store path
  // means two machines can share one remote store, and the mutation mutex
  // cannot serialize writers across hosts — the run refuses hard.
  const netFs = store.refuseNetworkStore(rootDir, { mountsFile: opts.mountsFile, readMounts: opts.readMounts });
  if (!netFs.ok) {
    return report({
      ok: false, status: 'refused', reason: netFs.reason, mount: netFs.mount, fstype: netFs.fstype, path: netFs.path, guidance: netFs.guidance,
    });
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
    try {
      // Lazy pin sweep at run end: every worktree this run materialized (and
      // any a crashed run stranded) recycles; failures never mask the result.
      workers.lazyRecyclePins(rootDir, { liveRunTags: [], gitRunner });
    } catch { /* best effort */ }
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

  // Dispatch table: load once under the run lock (every bound validated by
  // the loader) and stamp the file hash into the trust store with run-start
  // provenance. Every consume below re-verifies the live file against the
  // stamp; drift is the external-mutation pause, never a reload.
  const tableLoad = workers.loadDispatchTable(typeof opts.tablePath === 'string' && opts.tablePath ? { tablePath: opts.tablePath } : undefined);
  if (!tableLoad.ok) {
    return report({ ok: false, status: 'error', reason: 'dispatch-table-unavailable', detail: tableLoad.detail, file: tableLoad.file }, { iterations, breaker: null });
  }
  const tableFile = tableLoad.file;
  const dispatchTable = tableLoad.table;
  const runId = crypto.randomUUID();
  const runTag = runId.slice(0, 8);
  const tableSha = hashFileSha256(tableFile);
  if (tableSha == null) {
    return report({ ok: false, status: 'error', reason: 'dispatch-table-unreadable', file: tableFile }, { iterations, breaker: null });
  }
  const tableStamped = store.rollDispatchTableStamp(rootDir, { sha256: tableSha, rolledByWave: `${runTag}/start` });
  if (!tableStamped.ok) {
    return report({ ok: false, status: tableStamped.status || 'error', reason: tableStamped.reason || 'table-stamp-failed', path: tableStamped.path }, { iterations, breaker: null });
  }
  const verifyTable = () => verifyDispatchTableStamp(rootDir, tableFile);

  // Host negotiation is dispatch-consumed: entries without an agent worker
  // never probe the host (script stages run with no selectable host at all);
  // agent stages negotiate inside their iteration and fail closed there.

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
  let seq = 0;

  // Pinned worktree at the loop-start commit: materialized lazily on first
  // need (wave dispatch, Class P legs, runner-trust leg modules). Consumers
  // degrade per their own contract — wave dispatch verifies only when a pin
  // exists, Class P legs fail closed without one, and the delegated/delivery
  // leg modules fall back to the live tree with a warning (bootstrap
  // transition: repos without the exec tree in their history keep running).
  const loopStartCommit = readHead(gitRunner, rootDir);
  const pinState = { tried: false, pin: null };
  const getPin = () => {
    if (!pinState.tried) {
      pinState.tried = true;
      if (loopStartCommit) {
        const m = workers.materializePin(rootDir, { loopStartCommit, gitRunner, runTag: `${runTag}-pin` });
        if (m.ok) pinState.pin = { runTag: m.runTag, rootDir };
        else console.error(`⚠ auto pin: worktree materialization failed (${m.reason}${m.detail ? ': ' + m.detail : ''}) — pinned legs degrade this run`);
      }
    }
    return pinState.pin;
  };
  const loadLeg = (relPath, liveRequire) => {
    const pin = getPin();
    if (pin) {
      const r = workers.loadPinnedModule(pin, relPath, { rootDir, gitRunner });
      if (r.ok) return { module: r.module, source: 'pin' };
      const detail = String(r.detail || '').split('\n')[0].slice(0, 160);
      console.error(`⚠ auto legs: pinned ${relPath} unavailable (${r.reason}${detail ? ': ' + detail : ''}) — loading the live-tree module`);
    }
    return { module: liveRequire(), source: 'live' };
  };
  const legRatify = () => loadLeg('bin/lib/ops/auto/ratify.cjs', () => require('./ratify.cjs')).module;
  const legRedteam = () => loadLeg('bin/lib/ops/auto/redteam.cjs', () => require('./redteam.cjs')).module;
  const legDelivery = () => loadLeg('bin/lib/ops/auto/delivery.cjs', () => require('./delivery.cjs')).module;
  const legDeliveryPublish = () => loadLeg('bin/lib/ops/auto/delivery-publish.cjs', () => require('./delivery-publish.cjs')).module;
  const APPROVALS_BASELINE_ENV = legRatify().APPROVALS_BASELINE_ENV;

  // One-shot truth-read override after a crashed-advance rollback: the
  // loop just restored .gos/state.json from the pre-advance snapshot, so the
  // next truth read takes the file (a real reader serves the same bytes; an
  // injected stale view must not re-poison the post-spawn identity check).
  let rollbackRestore = null;
  const truthRead = () => {
    if (rollbackRestore) {
      rollbackRestore = null;
      const v = defaultStateReader(rootDir);
      if (v && v.corrupt) return { err: report({ ok: false, status: 'paused', paused: true, reason: 'state-corrupt', detail: v.error, guidance: store.guidanceFor('auto.loop.stateCorrupt') }) };
      if (!store.isPlainObject(v)) return { none: true };
      return { state: v };
    }
    return readTaskState();
  };

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
    const modRatify = legRatify();
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
       const legRes = await withHeartbeat(() => delegatedLegs({ leg: orphanLeg, opts, env, rootDir, spawnRunner, tp, now, runTag, legs: { ratify: legRatify, redteam: legRedteam } }));
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
  // The snapshot path is spawn-writable, so adoption is gated on the
  // store-side baseline hash: only the exact pre-advance bytes the runner
  // last validated roll back — a crafted snapshot falls through to the
  // external-mutation pause.
  const recoverCrashedAdvance = (baseIdentity, observedIdentity, stateObj) => {
    try {
      if (!baseIdentity || !observedIdentity || !stateObj) return null;
      const forward = Array.isArray(stateObj.completed_stages)
        && stateObj.completed_stages.map(String).includes(String(baseIdentity.stage));
      if (!forward) return null;
      if (String(baseIdentity.stage) === String(observedIdentity.stage)) return null;
      const logR = gitRunner(['log', '-1', '--format=%s', 'HEAD'], rootDir);
      const subj = String((logR && logR.stdout) || '');
      const hasAdvanceCommit = new RegExp(`chore\\(task\\): advance ${String(baseIdentity.stage).toLowerCase()}\\b`, 'i').test(subj);
      if (hasAdvanceCommit) return null;
      const snapPath = path.join(rootDir, '.gos', 'cache', 'state.snapshot');
      const snapBuf = fs.readFileSync(snapPath);
      const snap = JSON.parse(snapBuf.toString('utf8'));
      if (String(snap.current_stage || '').toUpperCase() !== String(baseIdentity.stage).toUpperCase()) return null;
      const bl = store.readBaselineState(rootDir);
      const snapSha = crypto.createHash('sha256').update(snapBuf).digest('hex');
      if (!bl.ok || !bl.baselineState || bl.baselineState.sha256 !== snapSha) return null;
      const tmp = `${snapPath}.rollback-tmp-${process.pid}`;
      fs.writeFileSync(tmp, snapBuf);
      fs.renameSync(tmp, path.join(rootDir, '.gos', 'state.json'));
      console.error(`⚠ crashed advance recovered: stage ${baseIdentity.stage} moved in state but its labeled commit never landed — state rolled back from the pre-advance snapshot; the stage will be re-driven`);
      return { restored: snap };
    } catch { return null; }
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
        // The rollback restored the pre-advance world: adopt it — the loop
        // re-drives the rolled-back stage, not whatever stale view the
        // reader still carries.
        taskState = crashedTop.restored;
        baseline = identityOf(taskState, readHead(gitRunner, rootDir));
        rollbackRestore = crashedTop;
      } else {
        baseline = observed;
      }
    } else {
      baseline = observed;
    }
    // Baseline state hash, store-side: the crashed-advance recovery adopts
    // a snapshot only on an exact byte-hash match with the pre-advance world
    // this loop last validated. Best-effort — an unrecordable hash simply
    // means a later recovery refuses adoption (fails closed).
    {
      const baselineShaNow = hashFileSha256(path.join(rootDir, '.gos', 'state.json'));
      if (baselineShaNow != null) store.recordBaselineState(rootDir, baselineShaNow);
    }

    // ---- runner-side legs for the previous delegated spawn ----
    // A delegated-stage advance left a PENDING approval behind (structural
    // checks only, written inside the sandbox): THINK must clear the
    // red-team double-zero gate first, then the runner ratifies from the
    // store stamp. Held gates pause here — no auto-advance, no dispositions.
    if (pendingLeg) {
      const leg = pendingLeg;
      pendingLeg = null;
      const modRatify = legRatify();
      if (leg.advanced && modRatify.isDelegatedStage(leg.stage)) {
        const legRes = await withHeartbeat(() => delegatedLegs({ leg, opts, env, rootDir, spawnRunner, tp, now, runTag, legs: { ratify: legRatify, redteam: legRedteam } }));
        if (legRes.err) return report(legRes.err, { iterations, breaker: breakerView() });
        const legIter = iterations.find((i) => i.spawnId === leg.spawnId);
        if (legIter) legIter.delegation = legRes.summary;
        // Ratification mutated tracked state (the PENDING became a cleared
        // record): re-read so the spawn below carries a fresh approvals
        // baseline, prompt, and identity view.
        const refreshed = readTaskState();
        if (refreshed.err) return report(refreshed.err, { iterations, breaker: breakerView() });
        if (!refreshed.none) taskState = refreshed.state;
      }
    }

    const stage = String(taskState.current_stage || '').toUpperCase();
    if (TERMINAL_STAGES.includes(stage)) {
      // Delivery is probe-gated: without a green adapter state in the store
      // the loop ends cleanly at SHIP with zero delivery involvement.
      let delivery = null;
      if (stage === 'SHIP' && deliveryProbeGreen(rootDir, legDelivery())) {
        const pub = await publishLeg({ opts, rootDir, taskId, taskState, now, withHeartbeat, publishModule: legDeliveryPublish() });
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

    // ---- dispatch entry: the closed table is the stage vocabulary ----
    const entry = dispatchTable.stages[stage];
    if (!store.isPlainObject(entry)) {
      return endWith({
        ok: false, status: 'paused', paused: true, reason: 'external-mutation',
        detail: `stage ${JSON.stringify(stage)} is outside the dispatch table's closed stage set`,
        expected: baseline, observed: identityOf(taskState, readHead(gitRunner, rootDir)),
        guidance: store.guidanceFor('auto.loop.externalMutation', { detail: `stage ${JSON.stringify(stage)} is not in the dispatch table` }),
      });
    }

    // ---- table re-verification before this iteration's consumes ----
    const tableNow = verifyTable();
    if (!tableNow.ok) {
      return endWith({
        ok: false, status: 'paused', paused: true, reason: 'external-mutation',
        detail: tableNow.detail,
        expected: baseline, observed: identityOf(taskState, readHead(gitRunner, rootDir)),
        guidance: store.guidanceFor('auto.loop.externalMutation', { detail: String(tableNow.detail || '').slice(0, 160) }),
      });
    }

    // ---- BUILD entry mode: wave dispatch over the frozen plan snapshot ----
    // (no snapshot or a pre-wave-era one stays on the legacy monolithic path)
    let waveSnapshot = null;
    if (stage === workers.WAVE_STAGE && entry.wave_dispatch === true) {
      const bm = buildModeFor(taskState);
      if (bm.mode === 'refused') {
        return endWith({ ok: false, status: 'paused', paused: true, reason: bm.reason || 'build-entry-refused', detail: bm.detail, guidance: bm.guidance });
      }
      if (bm.mode === 'waves') waveSnapshot = bm.snapshot;
    }
    const waveMode = waveSnapshot != null;

    // ---- breaker pre-checks: K visits, B budget ----
    // Wave-mode BUILD accounts on BUILD/W<n> labels inside the driver, so the
    // stage label itself is never visited here.
    const tripNow = () => endWith({ ok: false, status: 'paused', paused: true, reason: 'breaker-tripped', trip: b.tripped(), guidance: b.tripped() && b.tripped().guidance });
    if (!waveMode) {
      const visit = b.visit(stage);
      if (visit.tripped) return tripNow();
      if (!visit.ok) return endWith({ ok: false, status: 'paused', paused: true, reason: 'stage-invalid', detail: visit.reason });
    }
    const budget = b.checkBudget();
    if (budget.tripped) return tripNow();
    if (!budget.ok) return endWith({ ok: false, status: 'paused', paused: true, reason: budget.reason || 'budget-read-failed', path: budget.path, guidance: budget.guidance });

    const baselineSha = approvalsBaselineOf(taskState);
    const preStageHead = readHead(gitRunner, rootDir);
    if (!preStageHead) {
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'no-head', guidance: store.guidanceFor('auto.breaker.advanceCheckFailed') });
    }
    // Dirty-file baseline: whatever was already uncommitted belongs to
    // someone outside this loop (a supervising human, another terminal).
    // The spawn (or the script advance child) carries the list so its
    // in-spawn stage commit can refuse to sweep those files into the
    // advance commit. Bounded: pathological working trees degrade to no
    // baseline (guard off) rather than a multi-megabyte env.
    const dirtyBaseline = dirtyBaselineOf(gitRunner, rootDir);

    // ---- script stages: no host, no model, pinned legs + fixed argv ----
    if (entry.worker !== 'agent') {
      const res = await scriptIteration({
        stage, entry, tableLoad, verifyTable, opts, env, rootDir, gitRunner, spawnRunner, tp, b,
        runId, seq, baselineSha, preStageHead, dirtyBaseline, getPin, withHeartbeat, now,
        baselineEnvName: APPROVALS_BASELINE_ENV, endWith, tripNow,
      });
      if (res.err) return report(res.err, { iterations, breaker: breakerView() });
      if (res.tripped) return tripNow();
      if (res.iter) {
        iterations.push(res.iter);
        seq = res.seq;
        const afterS = truthRead();
        if (afterS.err) return report(afterS.err, { iterations, breaker: breakerView() });
        if (afterS.none) {
          return endWith({ ok: false, status: 'refused', reason: 'no-task', guidance: store.guidanceFor('auto.loop.noTask') });
        }
        const postIdentityS = identityOf(afterS.state, readHead(gitRunner, rootDir));
        if (res.iter.advanced && postIdentityS.stage === stage) {
          return endWith({ ok: false, status: 'paused', paused: true, reason: 'advance-state-mismatch', expectedStage: stage, guidance: store.guidanceFor('auto.loop.externalMutation', { detail: `stage still ${stage} after an advance commit` }) });
        }
        const mutationS = mutationBetween(baseline, postIdentityS, loopBranch, currentBranch(gitRunner, rootDir));
        if (!res.iter.advanced && mutationS) {
          return endWith({
            ok: false, status: 'paused', paused: true, reason: 'external-mutation',
            expected: baseline, observed: postIdentityS, detail: mutationS.detail,
            guidance: store.guidanceFor('auto.loop.externalMutation', { detail: mutationS.detail }),
          });
        }
        baseline = postIdentityS;
      }
      continue;
    }

    // ---- agent stage: host negotiation (agent entries only) ----
    const hostStatus = registry.hostStatus(opts.host, { env, runner: opts.probeRunner, home: env.HOME || os.homedir() });
    if (!hostStatus.selectable) {
      const g = hostStatus.failure || {};
      return report({
        ok: false, status: 'refused', reason: 'host-not-selectable', host: opts.host,
        hostFailure: g, guidance: store.guidanceFor('auto.loop.hostNotSelectable', { host: opts.host }),
      }, { iterations, breaker: breakerView() });
    }
    const adapter = registry.requireAdapter(opts.host);
    if (!adapter || typeof adapter.buildSpawnSpec !== 'function' || typeof adapter.parseEventStream !== 'function') {
      return report({ ok: false, status: 'refused', reason: 'host-not-selectable', host: opts.host, guidance: store.guidanceFor('auto.loop.hostNotSelectable', { host: opts.host }) }, { iterations, breaker: breakerView() });
    }

    // ---- BUILD waves: iterate the frozen snapshot before the stage exit ----
    let waveSummary = null;
    if (waveMode) {
      const pin = getPin();
      const wd = await withHeartbeat(() => workers.runWaveDispatch(waveSnapshot, {
        rootDir, taskId, workBranch: loopBranch,
        spawnRunner, gitRunner,
        // Original env reference (never a spread copy — a copy would read as
        // a full overlay and bypass the adapter's base-env sanitization);
        // the approvals baseline rides separately.
        env,
        approvalsBaseline: baselineSha,
        approvalsBaselineEnv: APPROVALS_BASELINE_ENV,
        host: opts.host, engineProbe: opts.engineProbe, breaker: b,
        ...(pin ? { pin } : {}),
        tablePath: tableFile,
        wallMs: tp.wallSec * 1000, idleMs: tp.idleSec * 1000, now, runTag,
      }));
      if (!wd.ok) {
        if (wd.status === 'held') {
          const heldWave = Array.isArray(wd.waves) ? wd.waves[wd.waves.length - 1] : null;
          return endWith({
            ok: false, status: 'paused', paused: true, reason: wd.reason || 'wave-held',
            wave: wd.wave, violation: (heldWave && heldWave.violation) || wd.reason,
            detail: (heldWave && heldWave.detail) || wd.detail, waves: wd.waves || [],
            guidance: {
              what: `BUILD wave ${wd.wave != null ? wd.wave : '?'} held: ${(heldWave && heldWave.violation) || wd.reason || 'contract violation'}`,
              fix: 'inspect the wave contract violation on the work branch; a held wave counts one stage failure and never auto-clears',
            },
          });
        }
        return endWith({ ...wd, waves: wd.waves || [] });
      }
      waveSummary = wd.waves;
    }
    const stageExit = waveMode;

    // ---- compose the spawn: entry-driven launcher profile + adapter spec ----
    const spawnId = `${runId}-${seq + 1}`;
    // Registered write channel for this spawn: grants and the use cap come
    // from the dispatch entry (BUILD carries the checkpoint verb and the
    // raised cap); the spawnId rides the env so in-spawn commands present it
    // to the lock. The wave-dispatch BUILD equipage (per-spawn scratch +
    // testbed, grants ro-bound as an immutable manifest, kernel-tier floor)
    // ships with the dispatch world; the legacy monolithic path keeps the
    // pre-dispatch compose shape.
    const waveEquipage = stage === workers.WAVE_STAGE && waveMode;
    const reg = store.registerSpawn({ spawnId, kind: 'work', stage, wallMs: tp.wallSec * 1000, pid: process.pid }, rootDir);
    if (!reg.ok) {
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'spawn-register-failed', detail: reg.detail, stage });
    }
    let manifest = null;
    if (waveEquipage) {
      manifest = store.writeGrantManifest(rootDir, spawnId);
      if (!manifest.ok) {
        store.removeSpawn(spawnId, rootDir);
        return endWith({ ok: false, status: 'paused', paused: true, reason: 'grant-manifest-failed', detail: manifest.detail, stage });
      }
    }
    // Model resolution: the entry's slot resolves once per spawn; inherit
    // pins no argv at all.
    const modelResolver = typeof opts.modelResolver === 'function' ? opts.modelResolver : defaultModelResolver;
    let resolvedModel = { model: 'inherit' };
    try { resolvedModel = modelResolver(entry.model_slot) || { model: 'inherit' }; } catch { /* unresolvable slot pins nothing */ }
    const pinnedModel = typeof resolvedModel.model === 'string' && resolvedModel.model && resolvedModel.model !== 'inherit' ? resolvedModel.model : null;
    const modelArgs = typeof adapter.pinnedModelArgs === 'function' ? adapter.pinnedModelArgs(pinnedModel) : [];
    const composed = launcher.compose(entry.profile, {
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
        entry.profile === 'workspace' || entry.profile === 'full'
          ? [rootDir, path.join(rootDir, '.gos'), path.join(rootDir, '.gos', 'logs')]
          : [path.join(rootDir, '.gos'), path.join(rootDir, '.gos', 'logs')]
      ),
      ...(waveEquipage ? { scratchDir: reg.scratch, ackDir: reg.acksDir, testBase: true, grantManifestPath: manifest.path, requiresKernelTier: true } : {}),
      buildSpawn: stage === workers.WAVE_STAGE,
    });
    if (!composed.ok) {
      store.removeSpawn(spawnId, rootDir);
      const res = b.recordOutcome(stage, 'spawn-error', `launcher ${composed.code}`);
      if (res.tripped) return tripNow();
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'launch-failed', code: composed.code, guidance: store.guidanceFor('auto.loop.spawnComposeFailed', { detail: String(composed.code) }) });
    }

    const prompt = stageExit
      ? stageExitPrompt({ stage, taskId, rootDir })
      : typeof opts.prompt === 'function' ? opts.prompt({ stage, taskId, rootDir })
        : typeof opts.prompt === 'string' ? opts.prompt
          : defaultPrompt({ stage, taskId, rootDir });

    // The adapter spec env carries the marker template; the launcher env
    // injects the composed permission config over it. The model pin lands in
    // the adapter argv and the approvals baseline in the env (a marker
    // session without a baseline fails closed at the commit gate).
    const adapterSpec = adapter.buildSpawnSpec({
      prompt,
      args: modelArgs,
      env: spawnEnvTemplate(env === process.env ? {} : env),
      cwd: rootDir,
    });
    const specEnv = { ...adapterSpec.env, ...composed.env, [SPAWN_MARKER_ENV]: '1', GOS_AUTO_SPAWN_ID: spawnId, [APPROVALS_BASELINE_ENV]: baselineSha };
    const argv = composed.tier === 'bubblewrap'
      ? [composed.engine, ...composed.argv, '--', ...adapterSpec.argv]
      : adapterSpec.argv.slice();
    const spec = {
      argv,
      env: specEnv,
      cwd: adapterSpec.cwd,
      prompt,
      stage,
      spawnId,
      tier: composed.tier,
      profile: entry.profile,
      deny: composed.deny.slice(),
      ...(waveEquipage ? { scratch: reg.scratch, grantManifestPath: manifest.path } : {}),
      modelPinned: pinnedModel,
      ...(stageExit ? { stageExit: true } : {}),
    };
    if (dirtyBaseline) spec.env.GOS_AUTO_DIRTY_BASELINE = dirtyBaseline;

    const preSpawnHead = readHead(gitRunner, rootDir);
    if (!preSpawnHead) {
      store.removeSpawn(spawnId, rootDir);
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'no-head', guidance: store.guidanceFor('auto.breaker.advanceCheckFailed') });
    }

    // ---- spawn under heartbeat + wall clock ----
    store.heartbeatRunLock(rootDir);
    const startedAtMs = now();
    let result;
    try {
      result = await withHeartbeat(() => spawnRunner(spec, { wallMs: tp.wallSec * 1000, idleMs: tp.idleSec * 1000 }));
      try { store.removeSpawn(spawnId, rootDir); } catch { /* already gone */ }
    } catch (e) {
      result = { status: null, stdout: '', stderr: '', error: e };
    }
    store.heartbeatRunLock(rootDir);
    const endedAtMs = now();

    // A spawned session happened: budget counter + stream stamp (before any
    // consumer could read the pairing). The stamp carries the telemetry
    // payload — pinned/observed model, command count, deny hits — and the
    // dual-window capture lands as sidecar files with their hashes.
    const bumped = store.bumpSpawn(rootDir);
    if (!bumped.ok) {
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'budget-write-failed', path: bumped.path, guidance: bumped.guidance });
    }
    const streamText = String((result && result.stdout) || '');
    const streamSha256 = crypto.createHash('sha256').update(streamText, 'utf8').digest('hex');
    const spawnedAtIso = new Date(startedAtMs).toISOString();
    // Escape hits and the parsed outcome are computed once here: the stamp
    // and the scorer below are the two consumers.
    const denyForScan = Array.isArray(spec.deny) ? spec.deny : undefined;
    const hits = (result && Array.isArray(result.preTruncationDenyHits) && result.preTruncationDenyHits.length)
      ? result.preTruncationDenyHits
      : launcher.scanSpawnOutput(streamText, { deny: denyForScan });
    const outcome = adapter.parseEventStream(streamText);
    const telemetry = { denyHits: hits.length };
    if (pinnedModel != null) telemetry.modelPinned = pinnedModel;
    if (typeof adapter.extractTelemetry === 'function') {
      const selfReport = adapter.extractTelemetry(outcome);
      if (selfReport && typeof selfReport.modelObserved === 'string') telemetry.modelObserved = selfReport.modelObserved;
      if (selfReport && Number.isInteger(selfReport.commandCount)) telemetry.commandCount = selfReport.commandCount;
    }
    const stamp = store.stampStream(spec.spawnId, stage, streamSha256, spawnedAtIso, rootDir, telemetry);
    if (!stamp.ok) {
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'stamp-failed', detail: stamp.reason, path: stamp.path, guidance: store.guidanceFor('auto.loop.stampFailed', { detail: String(stamp.reason) }) });
    }
    if (result && result.windowHead && result.windowTail) {
      try {
        store.saveWindows(spec.spawnId, { head: result.windowHead.stdout, tail: result.windowTail.stdout }, rootDir);
      } catch { /* advisory capture: a failed sidecar never blocks the run */ }
    }

    seq += 1;
    const iter = {
      index: seq, stage, spawnId: spec.spawnId, preSpawnHead,
      head: null, signal: null, advanced: false, counted: false,
      streamSha256, spawnedAtIso, durationMs: endedAtMs - startedAtMs,
      escapeHits: hits.length, tier: spec.tier,
      ...(waveSummary ? { waves: waveSummary } : {}),
    };
    iterations.push(iter);

    // ---- post-spawn truth: read once, shared by scoring and the checks ----
    const after = truthRead();
    if (after.err) return report(after.err, { iterations, breaker: breakerView() });
    if (after.none) {
      return endWith({ ok: false, status: 'refused', reason: 'no-task', guidance: store.guidanceFor('auto.loop.noTask') });
    }
    const postHead = readHead(gitRunner, rootDir);
    const postIdentity = identityOf(after.state, postHead);
    const mutation = mutationBetween(baseline, postIdentity, loopBranch, currentBranch(gitRunner, rootDir));

    // ---- score the outcome ----
    const scored = await score({ iter, spec, result, streamText, b, stage, gitRunner, rootDir, adapter, endedAtMs, idleMs: tp.idleSec * 1000, baseline, postIdentity, mutation, hits, outcome });
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
    let recoveredCrash = null;
    if (!iter.advanced && mutation && iter.signal !== 'rc0-no-advance') {
      // A failed-signal spawn alongside a stage-only forward delta with no
      // labeled commit is the crashed-advance window, not an external
      // mutation: recover from the snapshot and keep driving.
      recoveredCrash = recoverCrashedAdvance(baseline, postIdentity, after.state);
      if (recoveredCrash) {
        taskState = recoveredCrash.restored;
        rollbackRestore = recoveredCrash;
      }
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

// One script-worker stage iteration (VERIFY): the dispatch plan's Class P
// steps run as pinned legs and its Class S steps compose as fixed-argv
// script spawns through the registered channel. No host is probed and no
// model spawn exists. Pinned legs fail closed on a TAMPERED worktree; a pin
// that merely cannot provide the module (repos without the exec tree in
// their history) degrades to the live-tree module with a warning — the same
// bootstrap transition the delegated leg modules use. The stage exit stays
// the single `gos commit <stage>` — driven by the runner under a registered
// script spawn's identity (marker env + spawn id + approvals baseline) so
// the commit gate's channel, use-cap, and baseline contracts hold exactly
// as they do inside a spawned session.
async function scriptIteration(a) {
  const {
    stage, entry, tableLoad, verifyTable, opts, env, rootDir, gitRunner, spawnRunner, tp, b,
    runId, seq, baselineSha, preStageHead, dirtyBaseline, getPin, withHeartbeat, now,
    baselineEnvName, endWith, tripNow,
  } = a;

  const plan = workers.resolveWorkerPlan(stage, tableLoad);
  if (!plan.ok) {
    return { err: endWith({ ok: false, status: 'paused', paused: true, reason: plan.reason || 'worker-plan-unresolved', detail: plan.detail, stage }) };
  }
  const startedAtMs = now();
  const stepsSeen = [];
  const stepFailures = [];
  let lastStreamSha256 = null;
  let escapeTotal = 0;

  for (const step of plan.steps) {
    const verified = verifyTable();
    if (!verified.ok) {
      return {
        err: endWith({
          ok: false, status: 'paused', paused: true, reason: 'external-mutation', detail: verified.detail,
          guidance: store.guidanceFor('auto.loop.externalMutation', { detail: String(verified.detail || '').slice(0, 160) }),
        }),
      };
    }
    if (step.kind === 'P') {
      const pin = getPin();
      let leg = null;
      if (typeof opts.legRunner === 'function') {
        try { leg = await opts.legRunner(step, { stage, rootDir, pin, gitRunner }); }
        catch (e) { leg = { ok: false, reason: 'leg-threw', detail: e instanceof Error ? e.message : String(e) }; }
      } else {
        const loaded = pin
          ? workers.loadPinnedModule(pin, step.module, { rootDir, gitRunner })
          : { ok: false, reason: 'pin-unavailable' };
        if (loaded.ok) {
          const fn = loaded.module && loaded.module[step.fn];
          if (typeof fn !== 'function') {
            leg = { ok: false, reason: 'leg-fn-missing', detail: `${step.module} exports no function named ${step.fn}` };
          } else {
            try { leg = { ok: true, verdict: fn(...(Array.isArray(step.args) ? step.args : [])) }; }
            catch (e) { leg = { ok: false, reason: 'leg-threw', detail: e instanceof Error ? e.message : String(e) }; }
          }
        } else if (loaded.reason === 'pin-tampered') {
          leg = { ok: false, reason: 'pin-tampered', detail: loaded.detail };
        } else {
          console.error(`⚠ auto verify: pinned ${step.module} unavailable (${loaded.reason}) — running the live-tree module`);
          try {
            const mod = require(path.join(core.GOS_SELF_ROOT, step.module));
            const fn = mod && mod[step.fn];
            if (typeof fn !== 'function') leg = { ok: false, reason: 'leg-fn-missing', detail: `${step.module} exports no function named ${step.fn}` };
            else leg = { ok: true, verdict: fn(...(Array.isArray(step.args) ? step.args : [])) };
          } catch (e) { leg = { ok: false, reason: 'leg-threw', detail: e instanceof Error ? e.message : String(e) }; }
        }
      }
      if (!leg || leg.ok !== true) {
        stepFailures.push(`pinned leg ${step.id} refused: ${leg && leg.reason}${leg && leg.detail ? ': ' + leg.detail : ''}`);
        stepsSeen.push({ id: step.id, kind: 'P', status: 'refused' });
      } else {
        const verdict = leg.verdict;
        const bad = !store.isPlainObject(verdict) || verdict.ok !== true
          || (Array.isArray(verdict.failures) && verdict.failures.length);
        if (bad) {
          stepFailures.push(`pinned leg ${step.id} failed${typeof verdict.refused === 'string' ? ': ' + verdict.refused : ''}`);
          stepsSeen.push({ id: step.id, kind: 'P', status: 'failed' });
        } else {
          stepsSeen.push({ id: step.id, kind: 'P', status: 'passed' });
        }
      }
    } else {
      const spawnId = `${runId}-${seq + 1}-${step.id}`;
      const composed = workers.composeScriptSpawn(step, {
        stage, spawnId, rootDir, workspace: rootDir, env, engineProbe: opts.engineProbe, table: tableLoad,
      });
      if (!composed.ok) {
        // A refused compose cannot run anything — the remaining steps have
        // no frame, so the iteration stops here.
        stepsSeen.push({ id: step.id, kind: 'S', status: 'refused' });
        stepFailures.push(`Class S compose ${step.id}: ${composed.reason}${composed.detail ? ': ' + composed.detail : ''}`);
        break;
      }
      const spec = {
        argv: composed.argv,
        env: {
          ...registry.sanitizedSpawnEnv(env === process.env ? undefined : env),
          ...composed.env,
          [SPAWN_MARKER_ENV]: '1',
          GOS_AUTO_SPAWN_ID: spawnId,
          [baselineEnvName]: baselineSha,
        },
        cwd: rootDir,
        stage,
        spawnId,
        tier: composed.tier,
        profile: entry.profile,
        deny: composed.deny.slice(),
        scratch: composed.scratch,
        kind: 'script',
      };
      store.heartbeatRunLock(rootDir);
      let result;
      try {
        result = await withHeartbeat(() => spawnRunner(spec, { wallMs: tp.wallSec * 1000, idleMs: tp.idleSec * 1000 }));
      } catch (e) {
        result = { status: null, stdout: '', stderr: '', error: e };
      }
      try { store.removeSpawn(spawnId, rootDir); } catch { /* already gone */ }
      store.heartbeatRunLock(rootDir);
      const bumped = store.bumpSpawn(rootDir);
      if (!bumped.ok) {
        return { err: endWith({ ok: false, status: 'paused', paused: true, reason: 'budget-write-failed', path: bumped.path, guidance: bumped.guidance }) };
      }
      const streamText = String((result && result.stdout) || '');
      const streamSha256 = crypto.createHash('sha256').update(streamText, 'utf8').digest('hex');
      lastStreamSha256 = streamSha256;
      const denyForScan = Array.isArray(spec.deny) ? spec.deny : undefined;
      const hits = (result && Array.isArray(result.preTruncationDenyHits) && result.preTruncationDenyHits.length)
        ? result.preTruncationDenyHits
        : launcher.scanSpawnOutput(streamText, { deny: denyForScan });
      escapeTotal += hits.length;
      const stamp = store.stampStream(spawnId, stage, streamSha256, new Date(now()).toISOString(), rootDir, { denyHits: hits.length });
      if (!stamp.ok) {
        return { err: endWith({ ok: false, status: 'paused', paused: true, reason: 'stamp-failed', detail: stamp.reason, path: stamp.path, guidance: store.guidanceFor('auto.loop.stampFailed', { detail: String(stamp.reason) }) }) };
      }
      if (result && result.windowHead && result.windowTail) {
        try { store.saveWindows(spawnId, { head: result.windowHead.stdout, tail: result.windowTail.stdout }, rootDir); } catch { /* advisory */ }
      }
      const runnerFailed = !!(result && (result.error != null || (result.status != null && result.status !== 0)));
      if (runnerFailed || hits.length) {
        stepFailures.push(
          hits.length
            ? hits.map((h) => `deny '${h.pattern}': ${h.line.slice(0, 120)}`).join('; ')
            : `${step.id}: ${String((result && result.error && result.error.message) || (result && result.stderr) || 'script step failed').slice(0, 240)}`,
        );
        stepsSeen.push({ id: step.id, kind: 'S', status: 'failed' });
      } else {
        stepsSeen.push({ id: step.id, kind: 'S', status: 'passed' });
      }
    }
  }

  const iter = {
    index: seq + 1, stage, spawnId: `${runId}-${seq + 1}-exit`, preSpawnHead: preStageHead,
    head: null, signal: null, advanced: false, counted: false,
    streamSha256: lastStreamSha256, spawnedAtIso: new Date(startedAtMs).toISOString(),
    durationMs: now() - startedAtMs, escapeHits: escapeTotal, tier: null, steps: stepsSeen,
  };

  // Every step runs even when an earlier one failed — the full evidence set
  // lands (the same philosophy `gate all` follows), and any failure fails
  // the iteration as one stage outcome.
  if (stepFailures.length) {
    iter.signal = 'task-failed';
    iter.detail = stepFailures.join(' | ').slice(0, 400);
    iter.counted = true;
    const res = b.recordOutcome(stage, 'task-failed', iter.detail);
    if (res.tripped) return { tripped: true };
    return { iter, seq: seq + 1 };
  }

  // ---- stage exit: one `gos commit <stage>` through the registered channel ----
  const exitSpawnId = iter.spawnId;
  const reg = store.registerSpawn({ spawnId: exitSpawnId, kind: 'script', stage, wallMs: tp.wallSec * 1000, pid: process.pid }, rootDir);
  if (!reg.ok) {
    return { err: endWith({ ok: false, status: 'paused', paused: true, reason: 'spawn-register-failed', detail: reg.detail, stage }) };
  }
  // The spawn channel requires a live, fresh lock holder in the child's
  // ancestry: a runner that did not arrive through the CLI write path
  // (module-driven runs, tests) records itself as the holder for the
  // duration of the child and clears the record afterwards.
  const lockFile = path.join(rootDir, '.gos', '.lock');
  let lockWritten = false;
  try {
    if (!fs.existsSync(lockFile)) {
      fs.mkdirSync(path.join(rootDir, '.gos'), { recursive: true });
      fs.writeFileSync(lockFile, JSON.stringify({ pid: process.pid, started_at: new Date().toISOString(), boot_id: null, starttime: spawnreg.procStartTime(process.pid) }));
      lockWritten = true;
    }
  } catch { /* unwritable: the channel reports it at the child */ }
  const childEnv = {
    ...(env === process.env ? {} : env),
    [SPAWN_MARKER_ENV]: '1',
    GOS_AUTO_SPAWN_ID: exitSpawnId,
    [baselineEnvName]: baselineSha,
  };
  if (dirtyBaseline) childEnv.GOS_AUTO_DIRTY_BASELINE = dirtyBaseline;
  let child;
  try {
    child = spawnSync(defaultCliEntry(), [...defaultCliEntryArgs(), 'commit', String(stage).toLowerCase()], {
      cwd: rootDir, env: childEnv, encoding: 'utf8', timeout: tp.wallSec * 1000 + 30000,
    });
  } catch (e) {
    child = { status: null, stdout: '', stderr: e instanceof Error ? e.message : String(e) };
  }
  try { store.removeSpawn(exitSpawnId, rootDir); } catch { /* gone */ }
  if (lockWritten) { try { fs.unlinkSync(lockFile); } catch { /* gone */ } }
  if (!child || child.status !== 0) {
    iter.signal = 'task-failed';
    iter.detail = `advance commit exited rc=${child ? child.status : 'none'}${String((child && child.stderr) || '').trim() ? ': ' + String(child.stderr).trim().slice(0, 240) : ''}`;
    iter.counted = true;
    const res = b.recordOutcome(stage, 'task-failed', iter.detail);
    if (res.tripped) return { tripped: true };
    return { iter, seq: seq + 1 };
  }
  const adv = breakerMod.detectAdvance({ preSpawnHead: preStageHead, cwd: rootDir, gitRunner, stage });
  if (!adv.ok) {
    return { err: endWith({ ok: false, status: 'paused', paused: true, reason: 'advance-check-failed', detail: adv.detail, guidance: adv.guidance }) };
  }
  iter.head = adv.head;
  iter.advanced = adv.advanced === true;
  if (iter.advanced) {
    const res = b.recordSuccess(stage);
    if (res.tripped) return { tripped: true };
    iter.signal = 'advanced';
  } else {
    iter.signal = 'rc0-no-advance';
    iter.counted = true;
    const res = b.recordOutcome(stage, 'rc0-no-advance', 'advance commit landed no new stage-labeled commit reachable from HEAD');
    if (res.tripped) return { tripped: true };
  }
  return { iter, seq: seq + 1 };
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
  // stays as the floor for runners that captured without a scanner. The
  // caller stamps the same hits into the telemetry, so both consumers read
  // one computation.
  const hits = Array.isArray(ctx.hits) ? ctx.hits : launcher.scanSpawnOutput(streamText, { deny: Array.isArray(spec.deny) ? spec.deny : undefined });
  iter.escapeHits = hits.length;

  const outcome = ctx.outcome || adapter.parseEventStream(streamText);

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
// without a verdict hold the stage for human review. The redteam module
// loads pinned when the pin can provide it, live otherwise.
async function redteamPasses({ leg, opts, env, rootDir, spawnRunner, tp, now, runTag, legs }) {
  const redteamMod = legs.redteam();
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
      idleMs: tp.idleSec * 1000,
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
// advance at the commit gate). Leg modules load pinned when the pin can
// provide them, live otherwise.
async function delegatedLegs({ leg, opts, env, rootDir, spawnRunner, tp, now, runTag, legs }) {
  const modRatify = legs.ratify();
  let redteam = null;
  if (String(leg.stage).toUpperCase() === 'THINK') {
    const rt = await redteamPasses({ leg, opts, env, rootDir, spawnRunner, tp, now, runTag, legs });
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
function deliveryProbeGreen(rootDir, deliveryModule) {
  const delivery = deliveryModule || require('./delivery.cjs');
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
async function publishLeg({ opts, rootDir, taskId, taskState, now, withHeartbeat, publishModule }) {
  const publishMod = publishModule || require('./delivery-publish.cjs');
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
  stageExitPrompt,
  buildModeFor,
  defaultModelResolver,
  verifyDispatchTableStamp,
  createLoop,
};
