// ops/auto/ratify — the two-phase approval ratification boundary.
//
// Phase 1 (in-spawn, phase = PENDING): a delegated-stage commit inside a
// runner-spawned session records a PENDING auto-approval carrying no
// evidence claim — the commit gate runs inside the sandbox while the trust
// store is invisible there, so structural checks are all it can honestly
// perform. Phase 2 (runner-side, after spawn exit): ratify() verifies the
// store stamp pairing (spawnId ↔ captured-stream sha256 at that stage) and
// replaces the PENDING record with a ratified one whose tracked evidence is
// hash/count only — session ids, models, and stream tails stay in the
// machine-local store, never in tracked state.
//
// Approval record shapes read by every consumer here:
//   legacy human approval  bare ISO-ts string (written by `gos approve`)
//   PENDING auto approval  {status:'PENDING', ts, mode:'auto', stage}
//   ratified auto approval {status:'ratified', ts, mode:'auto', stage,
//                           evidence:{spawnId, streamSha256, stampCount}}
// Records that are not stage approvals (e.g. BASELINE_RESET {ts, reason})
// carry no status field and are invisible to these readers.
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const core = require('../../core/index.cjs');
const store = require('./store.cjs');
const loop = require('./loop.cjs');

// Delegated stages: approval authority may pass to the runner with
// store-verified evidence. Mechanical stages gate on structural checks,
// and archive/push are always held human gates (never delegated).
const DELEGATED_STAGES = Object.freeze(['THINK', 'PLAN']);



function isDelegatedStage(stage) {
  return DELEGATED_STAGES.includes(String(stage || '').toUpperCase());
}

// True inside a runner-spawned session (the loop marks every spawn env).
function spawnMarkerActive(env) {
  return Boolean((env || process.env)[loop.SPAWN_MARKER_ENV]);
}

// Legacy-tolerant approval readers: a bare string is a legacy human
// approval (passes gates, is never PENDING); objects are recognized by
// their status field; anything else (absent, BASELINE_RESET records) is
// neither.
function isPending(approval) {
  return store.isPlainObject(approval) && approval.status === 'PENDING';
}

function isRatified(approval) {
  if (typeof approval === 'string' && approval.length > 0) return true;
  return store.isPlainObject(approval) && approval.status === 'ratified';
}

// First unratified PENDING in the approvals map, or null. A lingering
// PENDING means a delegated commit advanced a stage without its runner
// ratification ever landing — every later stage advance must block on it.
function advanceBlocker(approvals) {
  if (!store.isPlainObject(approvals)) return null;
  for (const stage of Object.keys(approvals)) {
    if (isPending(approvals[stage])) return { stage, approval: approvals[stage] };
  }
  return null;
}

// Phase 1 record. spawnId is accepted for caller symmetry but never
// persisted: the PENDING record claims no evidence at all (the pairing
// lives in the machine-local store and enters tracked state only with the
// ratified record).
function recordPending({ stage, spawnId } = {}) {
  const stg = String(stage || '').toUpperCase();
  if (!stg) return { ok: false, status: 'error', reason: 'invalid-stage' };
  if (spawnId !== undefined && (typeof spawnId !== 'string' || !spawnId)) {
    return { ok: false, status: 'error', reason: 'invalid-spawn-id' };
  }
  return { ok: true, approval: { status: 'PENDING', ts: new Date().toISOString(), mode: 'auto', stage: stg } };
}

function stateFilePath(ctx) {
  if (ctx && ctx.statePath != null) return ctx.statePath;
  const root = ctx && ctx.rootDir ? path.resolve(ctx.rootDir) : process.cwd();
  return path.join(root, '.gos', 'state.json');
}

// Phase 2 ratification (runner-side). The store must hold a stamp for
// spawnId@stage whose streamSha256 matches the captured stream the runner
// just observed; only then is the ratified record written over the PENDING
// one in tracked repo state. Evidence in the tracked record is hash/count
// only.
function ratify({ stage, spawnId, streamSha256 } = {}, ctx = {}) {
  const stg = String(stage || '').toUpperCase();
  if (!stg) return { ok: false, status: 'error', reason: 'invalid-stage' };
  if (typeof spawnId !== 'string' || !spawnId) return { ok: false, status: 'error', reason: 'invalid-spawn-id' };
  if (typeof streamSha256 !== 'string' || !/^[0-9a-f]{64}$/.test(streamSha256)) {
    return { ok: false, status: 'error', reason: 'invalid-stream-sha256' };
  }
  const loaded = store.load(ctx.rootDir);
  if (!loaded.ok) {
    return { ok: false, status: loaded.status, reason: loaded.reason, path: loaded.path, guidance: loaded.guidance };
  }
  const stamps = store.isPlainObject(loaded.store.stamps) ? loaded.store.stamps : {};
  const stamp = stamps[spawnId];
  if (!stamp) {
    return { ok: false, status: 'refused', reason: 'stamp-missing', spawnId, guidance: store.guidanceFor('auto.ratify.stampMissing', { spawnId }) };
  }
  if (String(stamp.stage || '').toUpperCase() !== stg) {
    return {
      ok: false, status: 'refused', reason: 'stage-mismatch', spawnId,
      detail: `stamp stage ${stamp.stage} does not match ${stg}`,
      guidance: store.guidanceFor('auto.ratify.stageMismatch', { spawnId, stage: stg }),
    };
  }
  if (stamp.streamSha256 !== streamSha256) {
    return { ok: false, status: 'refused', reason: 'hash-mismatch', spawnId, guidance: store.guidanceFor('auto.ratify.hashMismatch', { spawnId }) };
  }
  const approval = {
    status: 'ratified',
    ts: new Date().toISOString(),
    mode: 'auto',
    stage: stg,
    evidence: { spawnId, streamSha256, stampCount: Object.keys(stamps).length },
  };
  const file = stateFilePath(ctx);
  let stateObj;
  try {
    stateObj = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    return { ok: false, status: 'refused', reason: fs.existsSync(file) ? 'state-corrupt' : 'no-task', path: file, detail: e.message, guidance: store.guidanceFor('auto.ratify.noTask') };
  }
  const approvals = store.isPlainObject(stateObj.approvals) ? stateObj.approvals : (stateObj.approvals = {});
  const prev = approvals[stg];
  if (prev === undefined || prev === null || isPending(prev)) {
    approvals[stg] = approval;
    try { core.writeAtomicJson(file, stateObj); }
    catch (e) {
      return { ok: false, status: 'error', reason: 'write-failed', path: file, detail: e.message };
    }
    return { ok: true, approval, stored: approval, replacedPending: isPending(prev), path: file };
  }
  // A human (legacy string) or already-ratified record is never overwritten.
  return { ok: true, approval, stored: prev, keptExisting: true, path: file };
}

module.exports = {
  DELEGATED_STAGES,
  isDelegatedStage,
  spawnMarkerActive,
  isPending,
  isRatified,
  advanceBlocker,
  recordPending,
  ratify,
  guidanceFor: store.guidanceFor,
};
