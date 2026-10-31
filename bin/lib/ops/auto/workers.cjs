// ops/auto/workers — stage-dispatch table loader for the auto loop.
// Reads templates/auto-dispatch.json (pure data) and enforces every value
// bound in code, mirroring launcher.loadProfile's fail-closed result shape:
// refusals carry a named `reason` and a human-readable `detail` and surface
// before any sandbox compose consumes the table. Bounds held here: the
// stage set is exactly the seven GOS stages, the worker/verb/unit
// vocabularies are closed sets, each stage's profile is pinned (restricted
// everywhere except BUILD's workspace — a table can never grant full),
// wave_dispatch is reserved for BUILD, use_cap never exceeds the
// limits.cjs hard ceiling, and each worker kind carries its contract form
// (agents a prompt string, scripts a steps array).
'use strict';

const fs = require('fs');
const path = require('path');
const limits = require('./limits.cjs');

const DISPATCH_TABLE_NAME = 'auto-dispatch.json';
const DISPATCH_SCHEMA_VERSION = 1;
const STAGES = Object.freeze(['INTENT', 'THINK', 'PLAN', 'BUILD', 'REVIEW', 'VERIFY', 'SHIP']);
const WORKERS = Object.freeze(['agent', 'script']);
const UNITS = Object.freeze(['stage', 'stage-wave']);
const VERBS = Object.freeze(['commit', 'gate', 'section', 'truth', 'checkpoint']);
const WAVE_STAGE = 'BUILD';

// Per-stage profile pin: the only stages that may run the workspace profile
// is BUILD; every other stage — and 'full' for any stage — refuses.
function pinnedProfile(stage) {
  return stage === WAVE_STAGE ? 'workspace' : 'restricted';
}

// bin/lib/ops/auto -> repo root: the exec tree ships and installs as one
// unit, so __dirname anchoring stays correct from the repo and the npm pack.
function defaultTemplatesDir() {
  return path.resolve(__dirname, '..', '..', '..', '..', 'templates');
}

function fail(reason, detail, file) {
  return { ok: false, reason, detail, file };
}

// Validate one stage entry; returns a fail-closed result or null when the
// entry is well formed. Check order: worker presence, closed vocabularies,
// pinned profile, dispatch unit, verbs, numeric cap, contract form.
function validateStage(stage, entry, file) {
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
    return fail('missing-worker-form', `stage ${stage}: entry is not an object`, file);
  }
  if (typeof entry.worker !== 'string' || !entry.worker) {
    return fail('missing-worker-form', `stage ${stage}: worker field is missing`, file);
  }
  if (!WORKERS.includes(entry.worker)) {
    return fail('unknown-worker', `stage ${stage}: worker '${entry.worker}' not in {${WORKERS.join(', ')}}`, file);
  }
  const want = pinnedProfile(stage);
  if (entry.profile !== want) {
    return fail('bad-profile', `stage ${stage}: profile '${entry.profile}' refused — pinned to '${want}'`, file);
  }
  if (!UNITS.includes(entry.unit)) {
    return fail('bad-unit', `stage ${stage}: unit '${entry.unit}' not in {${UNITS.join(', ')}}`, file);
  }
  if (stage !== WAVE_STAGE && entry.wave_dispatch) {
    return fail('bad-unit', `stage ${stage}: wave_dispatch is reserved for ${WAVE_STAGE}`, file);
  }
  if (!Array.isArray(entry.verbs)) {
    return fail('unknown-verb', `stage ${stage}: verbs is not an array`, file);
  }
  for (const v of entry.verbs) {
    if (!VERBS.includes(v)) {
      return fail('unknown-verb', `stage ${stage}: verb '${v}' not in {${VERBS.join(', ')}}`, file);
    }
  }
  const cap = entry.use_cap;
  if (!Number.isInteger(cap) || cap < 1 || cap > limits.HARD_USE_CAP_CEILING) {
    return fail('cap-over-ceiling', `stage ${stage}: use_cap ${JSON.stringify(cap)} outside 1..${limits.HARD_USE_CAP_CEILING}`, file);
  }
  const contracts = entry.contracts;
  if (!contracts || typeof contracts !== 'object' || Array.isArray(contracts)) {
    return fail('missing-worker-form', `stage ${stage}: contracts is not an object`, file);
  }
  if (entry.worker === 'agent' && typeof contracts.prompt !== 'string') {
    return fail('missing-worker-form', `stage ${stage}: agent worker requires contracts.prompt as a string`, file);
  }
  if (entry.worker === 'script' && !Array.isArray(contracts.steps)) {
    return fail('missing-worker-form', `stage ${stage}: script worker requires contracts.steps as an array`, file);
  }
  return null;
}

// loadDispatchTable({templatesDir?, tablePath?}) -> {ok: true, file, table}
// or {ok: false, reason, detail, file}. tablePath wins over templatesDir;
// the default resolves the repo templates dir from this module's location.
// Unknown/newer schema versions, stage-set drift in either direction, and
// every out-of-bound value refuse with a named reason before any consumer
// sees the parsed table.
function loadDispatchTable(opts) {
  const o = opts || {};
  const dir = typeof o.templatesDir === 'string' && o.templatesDir ? o.templatesDir : defaultTemplatesDir();
  const file = typeof o.tablePath === 'string' && o.tablePath ? o.tablePath : path.join(dir, DISPATCH_TABLE_NAME);
  let raw;
  try { raw = fs.readFileSync(file, 'utf8'); }
  catch (e) { return fail('table-unreadable', e.message, file); }
  let obj;
  try { obj = JSON.parse(raw); }
  catch (e) { return fail('table-corrupt', e.message, file); }
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) {
    return fail('table-corrupt', 'root is not a JSON object', file);
  }
  if (obj.dispatch_schema_version !== DISPATCH_SCHEMA_VERSION) {
    return fail('schema-version', `dispatch_schema_version ${JSON.stringify(obj.dispatch_schema_version)} is not a known version (expected ${DISPATCH_SCHEMA_VERSION})`, file);
  }
  const stages = obj.stages;
  if (!stages || typeof stages !== 'object' || Array.isArray(stages)) {
    return fail('unknown-stage', 'stages is not an object keyed by stage name', file);
  }
  const keys = Object.keys(stages);
  const unknown = keys.filter((k) => !STAGES.includes(k));
  if (unknown.length) {
    return fail('unknown-stage', `unknown stage key(s): ${unknown.join(', ')}`, file);
  }
  const missing = STAGES.filter((s) => !(s in stages));
  if (missing.length) {
    return fail('unknown-stage', `missing stage key(s): ${missing.join(', ')}`, file);
  }
  for (const stage of STAGES) {
    const bad = validateStage(stage, stages[stage], file);
    if (bad) return bad;
  }
  return { ok: true, file, table: obj };
}

module.exports = {
  DISPATCH_TABLE_NAME,
  DISPATCH_SCHEMA_VERSION,
  STAGES,
  WORKERS,
  UNITS,
  VERBS,
  WAVE_STAGE,
  loadDispatchTable,
};
