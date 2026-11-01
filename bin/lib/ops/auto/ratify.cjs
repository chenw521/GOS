// ops/auto/ratify — the two-phase approval ratification boundary.
//
// Phase 1 (in-spawn, phase = PENDING): a delegated-stage commit inside a
// runner-spawned session records a PENDING auto-approval carrying no
// evidence claim — the commit gate runs inside the sandbox while the trust
// store is invisible there, so structural checks are all it can honestly
// perform. Phase 2 (runner-side, after spawn exit): ratify() verifies the
// store stamp pairing (spawnId ↔ captured-stream sha256 at that stage) and
// replaces the PENDING record with a cleared one whose tracked evidence is
// hash/count only — session ids, models, and stream tails stay in the
// machine-local store, never in tracked state.
//
// Provenance re-verification (release checks): every cleared-tier record a
// release relies on must either pair against live store stamps or predate
// the loop-start baseline the runner passed in; a claim inside the loop
// window without pairing holds the stage for a human. Renders distinguish
// the two trusted flavors (store-verified vs pre-loop legacy) from human,
// pending, and claimed-not-verified records.
//
// Approval record shapes read by every consumer here:
//   legacy human approval  bare ISO-ts string (written by `gos approve`)
//   PENDING auto approval  {status:'PENDING', ts, mode:'auto', stage}
//   cleared auto approval  {status:'cleared', ts, mode:'auto', stage,
//                           evidence:{spawnId, streamSha256, stampCount}}
//   legacy spelling        status:'ratified' reads as the same cleared tier
// Records that are not stage approvals (e.g. BASELINE_RESET {ts, reason})
// carry no status field and are invisible to these readers.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const core = require('../../core/index.cjs');
const store = require('./store.cjs');
const loop = require('./loop.cjs');

// Delegated stages: approval authority may pass to the runner with
// store-verified evidence. Mechanical stages gate on structural checks,
// and archive/push are always held human gates (never delegated).
const DELEGATED_STAGES = Object.freeze(['THINK', 'PLAN']);

// Spawn env carrying the runner's approvals baseline: sha256 of the JSON of
// the approvals map at spawn start (key order = the on-disk state file's
// order, which is what both sides hash).
const APPROVALS_BASELINE_ENV = 'GOS_AUTO_APPROVALS_BASELINE';



function isDelegatedStage(stage) {
  return DELEGATED_STAGES.includes(String(stage || '').toUpperCase());
}

// True inside a runner-spawned session (the loop marks every spawn env).
function spawnMarkerActive(env) {
  return Boolean((env || process.env)[loop.SPAWN_MARKER_ENV]);
}

// Legacy-tolerant approval readers: a bare string is a legacy human
// approval (passes gates, is never PENDING); objects are recognized by
// their status field ('ratified' is the legacy spelling of 'cleared' —
// both read as the same cleared tier); anything else (absent,
// BASELINE_RESET records) is neither.
function isPending(approval) {
  return store.isPlainObject(approval) && approval.status === 'PENDING';
}

function isRatified(approval) {
  if (typeof approval === 'string' && approval.length > 0) return true;
  return store.isPlainObject(approval)
    && (approval.status === 'cleared' || approval.status === 'ratified');
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
// cleared record).
function recordPending({ stage, spawnId } = {}) {
  const stg = String(stage || '').toUpperCase();
  if (!stg) return { ok: false, status: 'error', reason: 'invalid-stage' };
  if (spawnId !== undefined && (typeof spawnId !== 'string' || !spawnId)) {
    return { ok: false, status: 'error', reason: 'invalid-spawn-id' };
  }
  return { ok: true, approval: { status: 'PENDING', ts: new Date().toISOString(), mode: 'auto', stage: stg } };
}

// ---- provenance re-verification ----

// Live-store pairing for one cleared-tier record: the tracked evidence must
// name a stamp (spawnId → stage + streamSha256) the machine-local store
// actually holds for that stage.
function evidencePairsWithStamps(record, stage, stamps) {
  if (!store.isPlainObject(record) || !store.isPlainObject(record.evidence)) return false;
  const ev = record.evidence;
  if (typeof ev.spawnId !== 'string' || !ev.spawnId) return false;
  if (typeof ev.streamSha256 !== 'string' || !/^[0-9a-f]{64}$/.test(ev.streamSha256)) return false;
  const st = store.isPlainObject(stamps) ? stamps[ev.spawnId] : null;
  if (!store.isPlainObject(st) || st.streamSha256 !== ev.streamSha256) return false;
  if (String(st.stage || '').toUpperCase() !== String(stage || '').toUpperCase()) return false;
  return true;
}

// A timestamp proves nothing on its own, but a record predating the
// loop-start baseline was written before this run existed — grandfather it.
// Unparseable timestamps prove nothing either way, so they never predate.
function predatesBaseline(tsIso, loopStartIso) {
  if (typeof tsIso !== 'string' || typeof loopStartIso !== 'string') return false;
  const ts = Date.parse(tsIso);
  const start = Date.parse(loopStartIso);
  if (!Number.isFinite(ts) || !Number.isFinite(start)) return false;
  return ts < start;
}

// Classify one approval record:
//   'store-verified'        object record whose evidence pairs live stamps
//   'pre-loop legacy'       record predating loop start, or any record when
//                           no loop start was passed (advisory contexts
//                           never hold on age alone)
//   'claimed-not-verified'  claim at/after loop start with no pairing
//   'pending' / null        PENDING record / not a stage-approval record
function classifyProvenance(record, stage, { loopStartIso, stamps } = {}) {
  if (isPending(record)) return 'pending';
  if (typeof record === 'string' && record.length > 0) {
    if (predatesBaseline(record, loopStartIso)) return 'pre-loop legacy';
    return loopStartIso == null ? 'pre-loop legacy' : 'claimed-not-verified';
  }
  if (store.isPlainObject(record) && (record.status === 'cleared' || record.status === 'ratified')) {
    if (evidencePairsWithStamps(record, stage, stamps)) return 'store-verified';
    if (predatesBaseline(record.ts, loopStartIso)) return 'pre-loop legacy';
    return loopStartIso == null ? 'pre-loop legacy' : 'claimed-not-verified';
  }
  return null;
}

// Release-check re-verification: every cleared-tier record a release
// relies on must either pair against the live trust store or predate the
// loop-start baseline. A claim inside the loop window without pairing
// holds the stage for a human. Without a loop start the check is
// advisory-only (manual contexts never refuse on age alone).
function verifyProvenance({ approvals, loopStartIso, stamps } = {}) {
  const results = [];
  if (!store.isPlainObject(approvals)) return { ok: true, results };
  for (const stage of DELEGATED_STAGES) {
    const record = approvals[stage];
    if (record === undefined || record === null) continue;
    if (!isRatified(record)) continue; // PENDING blockers are advanceBlocker's job
    const outcome = classifyProvenance(record, stage, { loopStartIso, stamps });
    results.push({ stage, outcome });
    if (outcome === 'claimed-not-verified') {
      const kind = typeof record === 'string' ? 'bare-string human-style approval' : 'cleared record';
      return {
        ok: false, reason: 'claimed-not-verified', stage,
        detail: `${kind} for ${stage} sits at or after the loop start (${loopStartIso}) with no store stamp pairing`,
        results,
        guidance: store.guidanceFor('auto.ratify.claimedNotVerified', { stage }),
      };
    }
  }
  return { ok: true, results };
}

// Render taxonomy for one approval record (status surfaces):
//   'cleared (store-verified)' | 'cleared (pre-loop legacy)' | 'human' |
//   'pending' | 'claimed-not-verified'
function describeApproval(record, { loopStartIso, stamps } = {}) {
  if (isPending(record)) return 'pending';
  if (typeof record === 'string' && record.length > 0) {
    return classifyProvenance(record, null, { loopStartIso, stamps }) === 'claimed-not-verified'
      ? 'claimed-not-verified' : 'human';
  }
  if (store.isPlainObject(record) && (record.status === 'cleared' || record.status === 'ratified')) {
    const c = classifyProvenance(record, record.stage, { loopStartIso, stamps });
    if (c === 'store-verified') return 'cleared (store-verified)';
    if (c === 'claimed-not-verified') return 'claimed-not-verified';
    return 'cleared (pre-loop legacy)';
  }
  return 'pending';
}

// ---- marker-session approvals baseline (diffusion guard) ----

// The runner stamps the spawn env with the sha256 of the JSON of the
// approvals map it passed in; the one sanctioned in-spawn mutation of that
// map is the commit path's own PENDING write over an absent record. An
// approvals[stage] record that exists while the map hashes differently
// from the baseline was written by something else — refuse. A marker
// session without a usable baseline fails closed: the runner always
// passes one.
function checkApprovalsBaseline({ approvals, stage, env } = {}) {
  const e = env || process.env;
  const baseline = e[APPROVALS_BASELINE_ENV];
  if (typeof baseline !== 'string' || !/^[0-9a-f]{64}$/.test(baseline)) {
    return {
      ok: false, status: 'refused', reason: 'approvals-baseline-missing', stage,
      guidance: store.guidanceFor('auto.ratify.approvalsBaselineMissing', {}),
    };
  }
  const map = store.isPlainObject(approvals) ? approvals : {};
  const cur = crypto.createHash('sha256').update(JSON.stringify(map), 'utf8').digest('hex');
  if (cur === baseline) return { ok: true };
  if (Object.prototype.hasOwnProperty.call(map, stage) && map[stage] != null) {
    return {
      ok: false, status: 'refused', reason: 'approvals-diffusion', stage,
      detail: `approvals[${stage}] exists but the approvals map differs from the runner-passed baseline`,
      guidance: store.guidanceFor('auto.ratify.approvalsDiffusion', { stage }),
    };
  }
  // Drift outside this stage's record: the upcoming PENDING write for the
  // absent stage stays sanctioned, and the release check re-verifies every
  // cleared-tier record the stage relies on.
  return { ok: true };
}

function stateFilePath(ctx) {
  if (ctx && ctx.statePath != null) return ctx.statePath;
  const root = ctx && ctx.rootDir ? path.resolve(ctx.rootDir) : process.cwd();
  return path.join(root, '.gos', 'state.json');
}

// Phase 2 ratification (runner-side). The store must hold a stamp for
// spawnId@stage whose streamSha256 matches the captured stream the runner
// just observed; only then is the cleared record written over the PENDING
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
    status: 'cleared',
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
  // A human (legacy string) or already-cleared record is never overwritten.
  return { ok: true, approval, stored: prev, keptExisting: true, path: file };
}

module.exports = {
  DELEGATED_STAGES,
  APPROVALS_BASELINE_ENV,
  isDelegatedStage,
  spawnMarkerActive,
  isPending,
  isRatified,
  advanceBlocker,
  recordPending,
  verifyProvenance,
  describeApproval,
  checkApprovalsBaseline,
  ratify,
  guidanceFor: store.guidanceFor,
};
