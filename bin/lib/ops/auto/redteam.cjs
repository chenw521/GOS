// ops/auto/redteam — runner-orchestrated red-team review rounds for
// delegated stage approvals. The runner owns the prompt template below
// (workers never receive prompt source from repo files), composes a
// separate spawn through the host adapter's command line under a
// capability profile whose only repository view is the read-only workspace
// (writable set empty; at the lexical tier the read-only posture rests on
// the injected config and the escape detector, not a kernel mount), stamps
// the captured stream into the machine-local store before any consumer
// reads the pairing, and classifies the worker verdict into a findings
// count. Delegation clearance follows the double-zero rule: two INDEPENDENT
// findings=0 rounds (distinct spawn ids) clear the gate, a single zero
// never does, and any round with findings>0 holds the gate for human
// disposition — never auto-cleared.
'use strict';

const crypto = require('node:crypto');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const store = require('./store.cjs');
const launcher = require('./launcher.cjs');
const loop = require('./loop.cjs');
const registry = require('./adapters/registry.cjs');
const core = require('../../core/index.cjs');

// Stamp stage label and prompt snapshot kind in the trust store.
const REDTEAM_STAGE = 'redteam';
const SNAPSHOT_KIND = 'redteamPrompt';

// Double-zero rule: delegated stages auto-advance only after this many
// INDEPENDENT findings=0 rounds.
const REQUIRED_ZEROS = 2;

const DEFAULT_PROFILE = 'restricted';
// Wall clock per review round: the runner's GOS_AUTO_TIMEOUT_WALL_SEC
// override wins over the 60-minute default, with the same strict positive
// integer grammar (a malformed override fails closed, never falls back).
const WALL_ENV = 'GOS_AUTO_TIMEOUT_WALL_SEC';
const DEFAULT_WALL_SEC = 60 * 60;
const SPAWN_MAX_BUFFER = 64 * 1024 * 1024;

// Runner-held prompt template. The sha256 of this exact constant is the
// prompt source hash recorded in the store; the worker session receives an
// interpolated copy at spawn time and never sees the source before that.
const PROMPT_TEMPLATE = [
  'GOS auto red-team review — stage {stage}, round {spawnId}, seed {seed}.',
  'Repository (read-only mount): {rootDir}',
  'You are an independent reviewer, not the author. Attack the {stage} stage work from three perspectives: misuse/safety, edge/exception, completeness.',
  'You may read any file. You may modify nothing — the repository is mounted read-only and your task is review only.',
  'Do not trust claims in the work: verify each one against the repository.',
  'End your reply with exactly one verdict line:',
  'REDTEAM-FINDINGS: <n>',
  'where <n> is the number of concrete, evidenced defects found. Use 0 only when the work survives all three perspectives. Never invent, merge, or soften findings.',
].join('\n');

// ---- locale surfaces ----
// Failure text resolves through locale keys; the catalogs degrade to the
// key string when an entry has not landed yet, so guidance is never null.


function promptSourceHash() {
  return store.sha256Of(PROMPT_TEMPLATE);
}

// Interpolate the runner template for one round. Only these four fields
// ever enter the prompt; worker-repo content never does.
function renderPrompt(ctx) {
  return PROMPT_TEMPLATE
    .replaceAll('{stage}', String(ctx.stage))
    .replaceAll('{spawnId}', String(ctx.spawnId))
    .replaceAll('{seed}', String(ctx.seed))
    .replaceAll('{rootDir}', String(ctx.rootDir));
}

// Record the runner template in the trust store: save when absent,
// verify-equal when present (a drifted hash means earlier rounds ran under
// a different prompt than the current template — the evidence pairing is
// broken, so this fails closed).
function ensurePromptRecorded(rootDir) {
  const loaded = store.load(rootDir);
  if (!loaded.ok) return loaded;
  const cur = loaded.store.snapshots[SNAPSHOT_KIND];
  const want = promptSourceHash();
  if (cur) {
    if (cur.sha256 !== want) {
      return {
        ok: false, status: 'error', reason: 'prompt-template-drift',
        detail: `stored ${cur.sha256.slice(0, 12)} != template ${want.slice(0, 12)}`,
        guidance: store.guidanceFor('auto.redteam.promptDrift'),
      };
    }
    return { ok: true, path: loaded.path, sha256: cur.sha256, snapshot: cur };
  }
  const saved = store.saveSnapshot(SNAPSHOT_KIND, PROMPT_TEMPLATE, rootDir);
  if (!saved.ok) return saved;
  return { ok: true, path: saved.path, sha256: saved.snapshot.sha256, snapshot: saved.snapshot };
}

// Verdict extraction from the captured worker stream. The contract is a
// verdict line ("REDTEAM-FINDINGS: <n>"); tolerant parsing also accepts
// plain "findings: n" spellings and takes the LAST verdict in the stream.
// Output without a recognizable verdict classifies as failure — never a
// crash, and never an implicit zero.
function parseFindings(text) {
  try {
    const RE = /(?:redteam[\s-]*)?findings?\s*[:=]\s*(\d{1,6})\b/i;
    let verdict = null;
    for (const line of String(text == null ? '' : text).split(/\r?\n/)) {
      const m = line.match(RE);
      if (m) verdict = Number(m[1]);
    }
    if (!Number.isInteger(verdict) || verdict < 0) return { ok: false, reason: 'unparsable' };
    return { ok: true, count: verdict };
  } catch {
    return { ok: false, reason: 'unparsable' };
  }
}

// Double-zero gate over accumulated round records
// ({spawnId, findings, ...}). Rounds whose findings is not a non-negative
// integer carry no evidence and count as failed. Independence is spawn-id
// identity: the same id twice is one round, not two.
function evaluateClearance(rounds) {
  const list = Array.isArray(rounds) ? rounds.filter((r) => r && typeof r === 'object') : [];
  const zeroIds = new Set();
  let held = false;
  let findingsTotal = 0;
  let failed = 0;
  for (const r of list) {
    if (Number.isInteger(r.findings) && r.findings >= 0) {
      if (r.findings === 0) zeroIds.add(String(r.spawnId || ''));
      else { held = true; findingsTotal += r.findings; }
    } else failed += 1;
  }
  return {
    cleared: !held && zeroIds.size >= REQUIRED_ZEROS,
    held,
    requiredZeros: REQUIRED_ZEROS,
    independentZeros: zeroIds.size,
    totalRounds: list.length,
    failedRounds: failed,
    findingsTotal,
  };
}

// Real spawn: runs the composed argv to completion under the wall timeout.
// Returns the spawnSync shape runRound scores.
function redteamSpawnRunner(spec, ctx) {
  if (!Array.isArray(spec.argv) || spec.argv.length === 0) {
    return { status: null, stdout: '', stderr: '', error: new Error('no spawn argv composed (lexical tier without a host command)') };
  }
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
    return { status: null, stdout: '', stderr: '', error: e instanceof Error ? e : new Error(String(e)) };
  }
}

// Wall-clock ceiling for one round: explicit ctx.wallMs, else the shared
// env override, else the default. Malformed overrides fail closed.
function resolveWallMs(ctx) {
  if (Number.isInteger(ctx.wallMs) && ctx.wallMs > 0) return { ok: true, wallMs: ctx.wallMs };
  const raw = (ctx.env || process.env)[WALL_ENV];
  if (raw == null) return { ok: true, wallMs: DEFAULT_WALL_SEC * 1000 };
  const text = String(raw).trim();
  if (!/^[1-9][0-9]*$/.test(text)) {
    return {
      ok: false, status: 'error', reason: 'invalid-timeout', which: WALL_ENV, value: String(raw),
      guidance: store.guidanceFor('auto.breaker.invalidTimeout', { name: WALL_ENV, value: String(raw) }),
    };
  }
  return { ok: true, wallMs: Number(text) * 1000 };
}

// Run one red-team review round. Composes a SEPARATE spawn under a
// capability profile with the workspace mounted read-only and NO writable
// roots (the reviewer may read the repository, never write it), takes its
// prompt solely from the runner-held template, delivers it through the host
// adapter's real command line, stamps the captured stream into the trust
// store, and classifies the verdict. Never throws; a failed spawn or
// unparsable output yields a failure-classified round.
//
// runRound({stage, spawnId}, ctx) with ctx:
//   rootDir       repo root (default: resolved cwd)
//   env           environment for profile token resolution
//   host          adapter host name (default 'opencode')
//   profile       launcher profile name (default 'restricted')
//   seed          independence seed (default: the spawnId)
//   spawnRunner   (spec, {wallMs}) -> spawnSync shape; sync or promise
//   engineProbe   () -> {engine, version?} launcher probe stub
//   wallMs        wall-clock ceiling (default: GOS_AUTO_TIMEOUT_WALL_SEC,
//                 else 60 minutes)
//   now           () -> epoch ms clock
async function runRound({ stage, spawnId }, ctx = {}) {
  if (typeof stage !== 'string' || !stage) return { ok: false, status: 'error', reason: 'invalid-stage' };
  if (typeof spawnId !== 'string' || !spawnId) return { ok: false, status: 'error', reason: 'invalid-spawn-id' };
  const rootDir = ctx.rootDir ? path.resolve(String(ctx.rootDir)) : (core.currentRootRealpath() || process.cwd());
  const now = typeof ctx.now === 'function' ? ctx.now : Date.now;

  const wall = resolveWallMs(ctx);
  if (!wall.ok) return wall;

  const recorded = ensurePromptRecorded(rootDir);
  if (!recorded.ok) return recorded;

  // Read-only repo view: the workspace is ro-bound by the composer and the
  // writable-roots list is deliberately empty.
  const composed = launcher.compose(ctx.profile || DEFAULT_PROFILE, {
    workspace: rootDir,
    writableRoots: [],
    env: ctx.env || process.env,
    engineProbe: ctx.engineProbe,
    store,
  });
  if (!composed.ok) {
    return {
      ok: false, status: 'error', reason: 'compose-failed', code: composed.code,
      guidance: store.guidanceFor('auto.redteam.composeFailed', { detail: String(composed.code) }),
    };
  }

  // Host command line: the adapter spec turns the runner template into a
  // real spawn argv (prompt delivered per the adapter contract, PATH/HOME
  // carried by the adapter env); the launcher frame wraps it at the kernel
  // tier and the injected permission config rides the env either way.
  const host = typeof ctx.host === 'string' && ctx.host ? ctx.host : 'opencode';
  const adapterMod = registry.requireAdapter(host);
  if (!adapterMod || typeof adapterMod.buildSpawnSpec !== 'function') {
    return {
      ok: false, status: 'error', reason: 'host-adapter-unavailable', host,
      guidance: store.guidanceFor('auto.redteam.hostUnavailable', { host }),
    };
  }

  const seed = typeof ctx.seed === 'string' && ctx.seed ? ctx.seed : spawnId;
  const prompt = renderPrompt({ stage, spawnId, seed, rootDir });
  const adapterSpec = adapterMod.buildSpawnSpec({
    prompt,
    env: loop.spawnEnvTemplate(ctx.env === process.env ? {} : (ctx.env || {})),
    cwd: rootDir,
  });
  const specEnv = { ...adapterSpec.env, ...composed.env, [loop.SPAWN_MARKER_ENV]: '1' };
  const argv = composed.tier === 'bubblewrap'
    ? ['bwrap', ...composed.argv, '--', ...adapterSpec.argv]
    : adapterSpec.argv.slice();
  const spec = {
    argv,
    env: specEnv,
    cwd: adapterSpec.cwd || rootDir,
    prompt,
    stage,
    spawnId,
    seed,
    tier: composed.tier,
    profile: composed.profile,
    deny: composed.deny.slice(),
    roWorkspace: true,
  };

  const spawnRunner = ctx.spawnRunner || redteamSpawnRunner;
  const wallMs = wall.wallMs;
  let result;
  try {
    result = await spawnRunner(spec, { wallMs });
  } catch (e) {
    result = { status: null, stdout: '', stderr: '', error: e instanceof Error ? e : new Error(String(e)) };
  }
  if (result == null) result = { status: null, stdout: '', stderr: '' };

  // Stamp before any consumer reads the pairing.
  const streamText = String(result.stdout || '');
  const streamSha256 = store.sha256Of(streamText);
  const spawnedAtIso = new Date(now()).toISOString();
  const stamp = store.stampStream(spawnId, REDTEAM_STAGE, streamSha256, spawnedAtIso, rootDir);
  if (!stamp.ok) {
    return {
      ok: false, status: 'paused', paused: true, reason: 'stamp-failed',
      detail: stamp.reason, path: stamp.path,
      guidance: store.guidanceFor('auto.redteam.stampFailed', { detail: String(stamp.reason) }),
    };
  }

  const parsed = parseFindings(streamText);
  const runnerFailed = !!(result.error != null || (result.status != null && result.status !== 0));
  const round = {
    spawnId,
    stage,
    seed,
    streamSha256,
    spawnedAtIso,
    promptSha256: recorded.sha256,
    tier: spec.tier,
    exitStatus: result.status == null ? null : result.status,
    parsed: parsed.ok && !runnerFailed,
    findings: parsed.ok && !runnerFailed ? parsed.count : null,
    classified: parsed.ok && !runnerFailed ? (parsed.count > 0 ? 'findings' : 'zero') : 'failure',
  };
  if (round.classified === 'failure') {
    round.guidance = runnerFailed
      ? store.guidanceFor('auto.redteam.roundFailed')
      : store.guidanceFor('auto.redteam.findingsUnparsable');
  }
  if (spec.tier !== 'bubblewrap') {
    // No kernel sandbox engine: the read-only workspace posture rests on the
    // injected config and the escape detector, not on a mount flag.
    round.readOnlyEnforcement = 'lexical';
    round.lexicalTierNote = core.t('auto.redteam.lexicalTier');
  }
  return { ok: true, round, stamp: stamp.stamp, promptSha256: recorded.sha256 };
}

module.exports = {
  REDTEAM_STAGE,
  SNAPSHOT_KIND,
  REQUIRED_ZEROS,
  PROMPT_TEMPLATE,
  promptSourceHash,
  renderPrompt,
  parseFindings,
  evaluateClearance,
  runRound,
};
