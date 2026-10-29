// ops/auto/breaker — the auto-loop runaway guard: three independent trip
// layers evaluated over one spawn loop. Layer N trips on consecutive
// failed spawns within the current stage; layer K trips on repeated
// re-entry of the same stage label (advance/regress ping-pong); layer B
// trips on the cumulative spawned-session budget read from the trust
// store. Every trip persists a breaker record through the store and
// pauses the loop — nothing auto-resumes; explicit re-enable only.
//
// Spawn failures carry a class tag (task/env/auth/timeout) so environment
// trouble never masquerades as task trouble. CI-watch timeouts are
// external waits, not spawn failures: they never count toward N and route
// to a human disposition instead. Advance attribution compares commit
// reachability, never timestamps: a stage advanced when a new
// stage-labeled commit became reachable from HEAD that was not reachable
// from the pre-spawn HEAD oid.
'use strict';

const { spawnSync } = require('node:child_process');
const store = require('./store.cjs');
const core = require('../../core/index.cjs');

const DEFAULT_LIMITS = { N: 3, K: 5, B: 30 };

// Per-spawn timeout defaults: 60 minutes wall clock, 10 minutes since the
// last stream event. Overridable through the two env vars below.
const DEFAULT_WALL_SEC = 60 * 60;
const DEFAULT_IDLE_SEC = 10 * 60;
const WALL_ENV = 'GOS_AUTO_TIMEOUT_WALL_SEC';
const IDLE_ENV = 'GOS_AUTO_TIMEOUT_IDLE_SEC';

// Loop failure classes accepted on trips. Takeover is deliberately absent:
// it appends breaker records but never counts as a loop failure.
const FAILURE_CLASSES = ['task', 'env', 'auth', 'timeout'];
const FAILURE_CLASS_SET = new Set(FAILURE_CLASSES);

// Adapter/host failure signals mapped onto the trip taxonomy. Signals set
// to countsTowardN=false never touch the consecutive counter — the CI-watch
// timeout is an external wait routed to a human disposition, and takeover
// is a lock-family event recorded without a counter change.
const SIGNALS = {
  'task-failed': { cls: 'task', countsTowardN: true },
  'rc0-no-advance': { cls: 'task', countsTowardN: true },
  'stream-no-terminal': { cls: 'env', countsTowardN: true },
  'stream-malformed': { cls: 'env', countsTowardN: true },
  'spawn-error': { cls: 'env', countsTowardN: true },
  'host-unavailable': { cls: 'env', countsTowardN: true },
  'auth-rejected': { cls: 'auth', countsTowardN: true },
  'wall-timeout': { cls: 'timeout', countsTowardN: true },
  'idle-timeout': { cls: 'timeout', countsTowardN: true },
  'ci-watch-timeout': { cls: null, countsTowardN: false, disposition: 'unknown' },
  takeover: { cls: 'takeover', countsTowardN: false, breakerRecordOnly: true },
};

const OID_RE = /^[0-9a-f]{7,40}$/i;

function isPlainObject(v) {
  return v != null && typeof v === 'object' && !Array.isArray(v);
}

function guidanceFor(key, params) {
  const v = core.t(key, params);
  if (typeof v === 'string') return { what: v };
  return v;
}

// ---- limits ----

// Floors validation: N/K/B must all be present integers >= 1. Invalid
// input is a fail-closed error — never a silent clamp or fill-in.
function validateLimits(limits) {
  const bad = (detail) => ({
    ok: false, status: 'error', reason: 'invalid-limits', detail,
    guidance: guidanceFor('auto.breaker.invalidLimits', { detail }),
  });
  if (!isPlainObject(limits)) return bad('limits object with N/K/B required');
  for (const k of ['N', 'K', 'B']) {
    if (!Number.isInteger(limits[k]) || limits[k] < 1) {
      return bad(`${k} must be an integer >= 1 (got ${JSON.stringify(limits[k])})`);
    }
  }
  return { ok: true, limits: { N: limits.N, K: limits.K, B: limits.B } };
}

// ---- taxonomy ----

// Map an adapter/host failure signal onto the trip taxonomy. Unknown
// signals fail closed — no guessing.
function classify(signal) {
  const s = SIGNALS[signal];
  if (s == null) {
    return {
      ok: false, status: 'error', reason: 'unknown-signal',
      detail: `signal must be one of ${Object.keys(SIGNALS).join('|')}`,
    };
  }
  const out = { ok: true, signal, cls: s.cls, countsTowardN: s.countsTowardN };
  if (s.disposition != null) out.disposition = s.disposition;
  if (s.breakerRecordOnly) out.breakerRecordOnly = true;
  return out;
}

// ---- timeouts ----

// Wall/idle timeout policy from env overrides. A malformed override is a
// fail-closed error, never a silent fallback to the default.
function timeoutPolicy(env) {
  const e = env || process.env;
  const read = (name, dflt) => {
    const raw = e[name];
    if (raw == null) return { ok: true, value: dflt };
    if (!/^[1-9][0-9]*$/.test(String(raw).trim())) {
      return {
        ok: false, status: 'error', reason: 'invalid-timeout', which: name,
        value: String(raw),
        guidance: guidanceFor('auto.breaker.invalidTimeout', { name, value: String(raw) }),
      };
    }
    return { ok: true, value: Number(String(raw).trim()) };
  };
  const wall = read(WALL_ENV, DEFAULT_WALL_SEC);
  if (!wall.ok) return wall;
  const idle = read(IDLE_ENV, DEFAULT_IDLE_SEC);
  if (!idle.ok) return idle;
  return { ok: true, wallSec: wall.value, idleSec: idle.value };
}

// ---- advance detection ----

function escapeRe(s) {
  return String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// Stage-labeled commit subjects look like "chore(task): advance plan — …".
// With a stage the pattern anchors that exact stage word; without one it
// matches any advance label.
function stageAdvanceRe(stage) {
  if (typeof stage === 'string' && stage.length) {
    return new RegExp(`^chore\\(task\\): advance ${escapeRe(stage.toLowerCase())}(?![a-z])`);
  }
  return /^chore\(task\): advance [a-z]+(?![a-z])/;
}

function defaultGitRunner(args, cwd) {
  return spawnSync('git', args, { encoding: 'utf8', cwd, stdio: ['ignore', 'pipe', 'pipe'] });
}

function gitFail(what, r) {
  const err = String((r && r.stderr) || '').trim();
  return {
    ok: false, status: 'error', reason: 'git-failed',
    detail: `git ${what} rc=${r && r.status}${err ? ': ' + err : ''}`,
    guidance: guidanceFor('auto.breaker.advanceCheckFailed', {}),
  };
}

// Advance attribution over git reachability: list commits reachable from
// the current HEAD that were absent from the pre-spawn HEAD, then keep the
// ones whose subject carries a stage-advance label. The git runner is
// injectable so the range/label logic runs against fixtures without a
// repository. Any git breakage fails closed as an error result — callers
// pause with a report rather than scoring it as a spawn failure.
function detectAdvance(opts) {
  if (!isPlainObject(opts)) {
    return { ok: false, status: 'error', reason: 'invalid-input', detail: 'options object required' };
  }
  const pre = opts.preSpawnHead;
  if (typeof pre !== 'string' || !OID_RE.test(pre)) {
    return {
      ok: false, status: 'error', reason: 'invalid-head',
      detail: 'preSpawnHead must be the recorded pre-spawn commit oid',
      guidance: guidanceFor('auto.breaker.advanceCheckFailed', {}),
    };
  }
  const runner = typeof opts.gitRunner === 'function' ? opts.gitRunner : defaultGitRunner;
  let head = opts.head;
  if (head == null) {
    const r = runner(['rev-parse', 'HEAD'], opts.cwd);
    const out = String((r && r.stdout) || '').trim();
    if (!r || r.status !== 0 || !out) return gitFail('rev-parse HEAD', r);
    head = out;
  }
  if (typeof head !== 'string' || !OID_RE.test(head)) {
    return {
      ok: false, status: 'error', reason: 'invalid-head',
      detail: 'head must resolve to a commit oid',
      guidance: guidanceFor('auto.breaker.advanceCheckFailed', {}),
    };
  }
  const range = `${pre}..${head}`;
  const rl = runner(['rev-list', range], opts.cwd);
  if (!rl || rl.status !== 0) return gitFail(`rev-list ${range}`, rl);
  const oids = String(rl.stdout || '').split('\n').map((s) => s.trim()).filter(Boolean);
  if (oids.length === 0) {
    return { ok: true, advanced: false, commits: [], total: 0, head, preSpawnHead: pre };
  }
  const sh = runner(['show', '-s', '--format=%H%x1f%s', ...oids], opts.cwd);
  if (!sh || sh.status !== 0) return gitFail('show -s', sh);
  const commits = [];
  for (const line of String(sh.stdout || '').split('\n')) {
    const t = line.trim();
    if (!t) continue;
    const i = t.indexOf('\x1f');
    if (i < 0) continue;
    const oid = t.slice(0, i);
    const subject = t.slice(i + 1);
    if (OID_RE.test(oid)) commits.push({ oid, subject });
  }
  const re = opts.stageLabelRe instanceof RegExp ? opts.stageLabelRe : stageAdvanceRe(opts.stage);
  const hits = commits.filter((c) => re.test(c.subject));
  return { ok: true, advanced: hits.length > 0, commits: hits, total: commits.length, head, preSpawnHead: pre };
}

// ---- pure layer evaluation ----

// Decide a trip from raw counter values. Each numeric field that is
// present gets checked, in N → K → B order; absent fields are skipped so
// callers evaluate one layer at a time. Limits always run through floors
// validation first.
function evaluate(input) {
  if (!isPlainObject(input)) {
    return { ok: false, status: 'error', reason: 'invalid-input', detail: 'input object required' };
  }
  const v = validateLimits(input.limits);
  if (!v.ok) return v;
  const { N, K, B } = v.limits;
  const stage = typeof input.stage === 'string' && input.stage ? input.stage : '(unknown)';
  if (input.consecutive != null) {
    if (!Number.isInteger(input.consecutive) || input.consecutive < 0) {
      return { ok: false, status: 'error', reason: 'invalid-counter', detail: 'consecutive must be an integer >= 0' };
    }
    if (input.consecutive >= N) {
      const cls = FAILURE_CLASS_SET.has(input.cls) ? input.cls : 'task';
      return {
        ok: true, tripped: true, layer: 'N', cls, stage,
        reason: `stage ${stage}: ${input.consecutive} consecutive failed spawns (limit N=${N})`,
      };
    }
  }
  if (input.visits != null) {
    if (!Number.isInteger(input.visits) || input.visits < 0) {
      return { ok: false, status: 'error', reason: 'invalid-counter', detail: 'visits must be an integer >= 0' };
    }
    if (input.visits >= K) {
      return {
        ok: true, tripped: true, layer: 'K', cls: 'task', stage,
        reason: `stage ${stage}: re-entered ${input.visits} times (limit K=${K})`,
      };
    }
  }
  if (input.spawnCount != null) {
    if (!Number.isInteger(input.spawnCount) || input.spawnCount < 0) {
      return { ok: false, status: 'error', reason: 'invalid-counter', detail: 'spawnCount must be an integer >= 0' };
    }
    if (input.spawnCount >= B) {
      return {
        ok: true, tripped: true, layer: 'B', cls: 'task', stage,
        reason: `spawn budget exhausted: ${input.spawnCount} spawned sessions (limit B=${B})`,
      };
    }
  }
  return { ok: true, tripped: false };
}

// ---- breaker instance ----

function create(opts = {}) {
  let limits;
  if (opts.limits != null) {
    const v = validateLimits(opts.limits);
    if (!v.ok) return v;
    limits = v.limits;
  } else {
    const cur = store.load(opts.rootDir);
    if (!cur.ok) return cur; // fail closed with the store's paused guidance
    const v = validateLimits(cur.store.limits);
    if (!v.ok) return v;
    limits = v.limits;
  }
  const rootDir = opts.rootDir;

  let stage = null;
  let consecutive = 0;
  const visits = Object.create(null);
  let tripped = null;

  function trippedView() {
    return { ...tripped, alreadyTripped: true };
  }

  // Persist one trip: the store owns the record and the cumulative trip
  // counter mirror. A store that refuses the write still trips — the loop
  // pauses either way, with the store failure surfaced in the result.
  function doTrip(layer, cls, tripStage, reason) {
    const detail = `stage=${tripStage} ${reason}`;
    const rec = store.recordTrip({ layer, cls, detail }, rootDir);
    tripped = {
      ok: true, tripped: true, paused: true, layer, stage: tripStage, cls, reason,
      ts: rec.ok ? rec.record.ts : new Date().toISOString(),
      guidance: guidanceFor('auto.breaker.tripped', { layer, reason }),
    };
    if (rec.ok) {
      tripped.record = rec.record;
      tripped.mirrors = rec.mirrors;
    } else {
      tripped.storeResult = rec;
    }
    return { ...tripped };
  }

  const breaker = {
    // Observe a stage entry. A different stage label ends the previous
    // stage's consecutive streak; the visit itself counts toward that
    // label's ping-pong cap for the whole run.
    visit(nextStage) {
      if (tripped) return trippedView();
      if (typeof nextStage !== 'string' || !nextStage) {
        return { ok: false, status: 'error', reason: 'invalid-stage', detail: 'stage label required' };
      }
      if (nextStage !== stage) {
        consecutive = 0;
        stage = nextStage;
      }
      visits[nextStage] = (visits[nextStage] || 0) + 1;
      const d = evaluate({ limits, visits: visits[nextStage], stage: nextStage });
      if (d.tripped) return doTrip(d.layer, d.cls, nextStage, d.reason);
      return { ok: true, layer: 'K', stage: nextStage, visits: visits[nextStage], limit: limits.K };
    },

    // Record a failed spawn in the current stage. Only taxonomy classes
    // are accepted; the class tag rides into the trip record.
    recordFailure(failStage, cls, detail) {
      if (tripped) return trippedView();
      if (typeof failStage !== 'string' || !failStage) {
        return { ok: false, status: 'error', reason: 'invalid-stage', detail: 'stage label required' };
      }
      if (!FAILURE_CLASS_SET.has(cls)) {
        return {
          ok: false, status: 'error', reason: 'invalid-failure-class',
          detail: `cls must be one of ${FAILURE_CLASSES.join('|')}`,
        };
      }
      consecutive += 1;
      const d = evaluate({ limits, consecutive, cls, stage: failStage });
      if (d.tripped) return doTrip(d.layer, d.cls, failStage, d.reason + (detail ? ` | ${detail}` : ''));
      return { ok: true, layer: 'N', stage: failStage, consecutive, limit: limits.N, cls };
    },

    // Record a successful spawn: success ends any consecutive streak.
    recordSuccess(okStage) {
      if (tripped) return trippedView();
      if (typeof okStage !== 'string' || !okStage) {
        return { ok: false, status: 'error', reason: 'invalid-stage', detail: 'stage label required' };
      }
      consecutive = 0;
      return { ok: true, stage: okStage, consecutive: 0 };
    },

    // Classify a signal and route it: counting signals feed recordFailure,
    // the CI-watch timeout returns its disposition untouched, takeover
    // appends a breaker record without any counter change.
    recordOutcome(outStage, signal, detail) {
      if (tripped) return trippedView();
      const c = classify(signal);
      if (!c.ok) return c;
      if (c.breakerRecordOnly) {
        const rec = store.recordBreaker(
          { cls: c.cls, detail: `stage=${outStage} ${signal}${detail ? ': ' + detail : ''}` },
          rootDir,
        );
        if (!rec.ok) return rec;
        return { ok: true, counted: false, signal, record: rec.record };
      }
      if (c.countsTowardN) return breaker.recordFailure(outStage, c.cls, detail);
      return { ok: true, counted: false, signal, disposition: c.disposition || null };
    },

    // Pre-spawn budget guard against the store's cumulative spawn counter
    // (the single authoritative count). An unreadable budget is an error,
    // never a pass.
    checkBudget() {
      if (tripped) return trippedView();
      const m = store.mirrors(rootDir);
      if (!m.ok) return m;
      const d = evaluate({ limits, spawnCount: m.spawnCount, stage });
      if (d.tripped) return doTrip(d.layer, d.cls, stage || '(unknown)', d.reason);
      return { ok: true, layer: 'B', spawnCount: m.spawnCount, limit: limits.B };
    },

    // Read-only snapshot for status surfaces.
    state() {
      return {
        stage,
        consecutive,
        visits: { ...visits },
        limits: { ...limits },
        tripped: tripped ? { layer: tripped.layer, cls: tripped.cls, stage: tripped.stage, reason: tripped.reason } : null,
      };
    },

    // The persisted trip decision, or null while the breaker holds.
    tripped() {
      return tripped ? { ...tripped } : null;
    },
  };

  return { ok: true, breaker, limits: { ...limits } };
}

module.exports = {
  DEFAULT_LIMITS,
  DEFAULT_WALL_SEC,
  DEFAULT_IDLE_SEC,
  FAILURE_CLASSES,
  validateLimits,
  classify,
  timeoutPolicy,
  detectAdvance,
  stageAdvanceRe,
  evaluate,
  create,
};
