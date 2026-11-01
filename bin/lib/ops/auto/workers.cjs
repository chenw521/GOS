// ops/auto/workers — stage-dispatch table loader and worker forms for the
// auto loop. Reads templates/auto-dispatch.json (pure data) and enforces
// every value bound in code, mirroring launcher.loadProfile's fail-closed
// result shape: refusals carry a named `reason` and a human-readable
// `detail` and surface before any sandbox compose consumes the table.
// Bounds held here: the stage set is exactly the seven GOS stages, the
// worker/verb/unit vocabularies are closed sets, each stage's profile is
// pinned (restricted everywhere except BUILD's workspace — a table can
// never grant full), wave_dispatch is reserved for BUILD, use_cap never
// exceeds the limits.cjs hard ceiling, and each worker kind carries its
// contract form (agents a prompt string, scripts a steps array).
//
// Worker forms: a script stage's steps split into execution classes.
// Class S (repo-authored content — section suites and the gos CLI) runs
// fixed argv through the launcher frame registered as a script-kind spawn
// — no adapter, no prompt, no model. Class P (trust store or runner-trust
// code — semantic and trust gates) runs from a detached read-only worktree
// pinned at the loop-start commit inside the machine-local store: the tree
// hash is recorded at materialize time and re-verified against the worktree
// before every leg load, so a pinned leg can only ever execute recorded
// code analyzing the live tree as data. Verdicts are return values, never
// parsed prose.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const limits = require('./limits.cjs');
const launcher = require('./launcher.cjs');

const DISPATCH_TABLE_NAME = 'auto-dispatch.json';
const DISPATCH_SCHEMA_VERSION = 1;
const STAGES = Object.freeze(['INTENT', 'THINK', 'PLAN', 'BUILD', 'REVIEW', 'VERIFY', 'SHIP']);
const WORKERS = Object.freeze(['agent', 'script']);
const UNITS = Object.freeze(['stage', 'stage-wave']);
const VERBS = Object.freeze(['commit', 'gate', 'section', 'truth', 'checkpoint']);
const WAVE_STAGE = 'BUILD';

// Filename-safe identifier rule shared by spawn ids and pin run tags (the
// same shape spawnreg enforces, so derived paths can never escape their
// store directory through path fragments).
const ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
// Git object hashes: sha-1 repos carry 40 hex chars, sha-256 repos 64.
const GIT_SHA_RE = /^[0-9a-f]{7,64}$/;

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

// ---- worker forms ----------------------------------------------------------

// Builtin VERIFY plan, used while the table's contracts.steps carry only a
// placeholder: the programmatic gate entry (Class P), the section suite
// (Class S), and the truths check (Class P). SHIP resolves to no steps —
// delivery stays a runner-side leg.
const DEFAULT_VERIFY_STEPS = Object.freeze([
  Object.freeze({ id: 'gate', module: 'bin/lib/ops/gate.cjs', fn: 'computeGateVerdicts', args: [{ which: 'all' }] }),
  Object.freeze({ id: 'sections', command: ['bash', 'test/run-sections.sh'] }),
  Object.freeze({ id: 'truth', module: 'bin/lib/ops/gate.cjs', fn: 'computeGateVerdicts', args: [{ which: 'truths' }] }),
]);

// Store dependency is lazy (store.cjs requires this module at load): the
// require happens at call time so both load orders stay cycle-free.
function getStore() {
  try { return require('./store.cjs'); }
  catch { return null; }
}

// Accept either a loadDispatchTable result or a raw parsed table.
function stagesOf(table) {
  if (!table || typeof table !== 'object') return null;
  if (table.ok === true && table.table && table.table.stages) return table.table.stages;
  if (table.stages && typeof table.stages === 'object') return table.stages;
  return null;
}

// A step's execution class: exactly one declared form. A fixed command
// array (non-empty, all non-empty strings) is Class S; a module+fn pair is
// Class P. Both forms at once, or neither, leave the class undecidable.
function classifyStep(step) {
  if (step == null || typeof step !== 'object' || Array.isArray(step)) return null;
  const command = Array.isArray(step.command) && step.command.length > 0
    && step.command.every((t) => typeof t === 'string' && t.length > 0);
  const leg = typeof step.module === 'string' && step.module.length > 0
    && typeof step.fn === 'string' && step.fn.length > 0;
  if (command === leg) return null;
  return command ? 'S' : 'P';
}

function copyStep(step) {
  const out = { id: step.id, kind: step.kind };
  if (Array.isArray(step.command)) out.command = step.command.map(String);
  if (typeof step.module === 'string') out.module = step.module;
  if (typeof step.fn === 'string') out.fn = step.fn;
  if (Array.isArray(step.args)) out.args = JSON.parse(JSON.stringify(step.args));
  return out;
}

// resolveWorkerPlan(stage, table?) -> { ok, stage, source, steps } where
// each step carries its execution class, or a fail-closed refusal. Steps
// derive from the entry's contracts.steps when it declares any; VERIFY
// falls back to the builtin default; every other script stage resolves to
// no steps (SHIP's delivery stays runner-side). Agent stages refuse —
// execution-class plans exist only for script workers. A step whose class
// cannot be determined refuses the whole plan.
function resolveWorkerPlan(stage, table) {
  const name = String(stage || '').toUpperCase();
  if (!STAGES.includes(name)) return fail('unknown-stage', `unknown stage ${JSON.stringify(stage)}`);
  let stages = stagesOf(table);
  if (!stages) {
    const load = loadDispatchTable();
    if (!load.ok) return fail('dispatch-table-unavailable', load.detail, load.file);
    stages = load.table.stages;
  }
  const entry = stages[name];
  if (!entry || typeof entry !== 'object') return fail('unknown-stage', `stage ${name} is missing from the dispatch table`);
  if (entry.worker === 'agent') {
    return fail('agent-worker', `${name} runs an agent worker — execution-class plans apply to script stages only`);
  }
  if (entry.worker !== 'script') {
    return fail('unknown-worker', `stage ${name}: worker '${entry.worker}' has no execution class`);
  }
  const declared = entry.contracts && Array.isArray(entry.contracts.steps) ? entry.contracts.steps : null;
  if (declared && declared.length) {
    const steps = [];
    for (const s of declared) {
      const kind = classifyStep(s);
      if (!kind) {
        return fail('no-clear-class', `step ${s && s.id ? s.id : JSON.stringify(s)} declares neither exactly one fixed command (Class S) nor one pinned module leg (Class P)`);
      }
      steps.push(copyStep({ ...s, kind }));
    }
    return { ok: true, stage: name, source: 'table', steps };
  }
  if (name === 'VERIFY') {
    return { ok: true, stage: name, source: 'builtin', steps: DEFAULT_VERIFY_STEPS.map((s) => copyStep({ ...s, kind: classifyStep(s) })) };
  }
  return { ok: true, stage: name, source: 'none', steps: [] };
}

// True only when the entry's worker needs the model host: agent stages
// probe the host; script stages never do.
function dispatchNeedsHost(entry) {
  return !!(entry && typeof entry === 'object' && entry.worker === 'agent');
}

// composeScriptSpawn(step, ctx) — Class S spawn compose. ctx:
//   stage      stage name (required; must resolve to a script-worker entry)
//   spawnId    filename-safe spawn id (required)
//   rootDir    repo root used for store/spawnreg derivation (required)
//   workspace  repo root ro-bound into the sandbox
//   env        env for token resolution and the engine probe
//   engineProbe  sandbox engine probe stub (tests pass argv-level probes)
//   table      dispatch table override (loadDispatchTable result shape)
// The spawn registers through the store registry as kind 'script' before
// composing; a refused compose tears the registration back down. The
// returned argv is the composed sandbox frame plus '--' plus the step's
// fixed command — no adapter, no prompt, no model, no git identity.
function composeScriptSpawn(step, ctx = {}) {
  if (classifyStep(step) !== 'S') {
    return fail('not-script-step', `step ${step && step.id ? step.id : '(unidentified)'} does not carry a fixed command (Class S)`);
  }
  const command = step.command.map(String);
  if (command.includes('opencode')) {
    return fail('host-adapter-forbidden', 'a Class S spawn runs fixed repo-authored argv — the host adapter can never appear in it');
  }
  const stage = String(ctx.stage || '').toUpperCase();
  if (!STAGES.includes(stage)) return fail('unknown-stage', `unknown stage ${JSON.stringify(ctx.stage)}`);
  const load = stagesOf(ctx.table) ? ctx.table : loadDispatchTable();
  if (!load.ok) return fail('dispatch-table-unavailable', load.detail, load.file);
  const entry = load.table.stages[stage];
  if (!entry) return fail('unknown-stage', `stage ${stage} is missing from the dispatch table`);
  if (entry.worker !== 'script') {
    return fail('agent-worker', `${stage} runs an agent worker — Class S spawns apply to script stages only`);
  }
  if (typeof ctx.spawnId !== 'string' || !ID_RE.test(ctx.spawnId)) {
    return fail('invalid-spawn-id', 'spawnId must be filename-safe (letters, digits, dot, dash, underscore)');
  }
  const store = getStore();
  if (!store) return fail('store-unavailable', 'the trust store module could not be loaded');
  const reg = store.registerSpawn({ spawnId: ctx.spawnId, kind: 'script', stage, wallMs: ctx.wallMs }, ctx.rootDir);
  if (!reg.ok) return { ok: false, reason: reg.reason, detail: reg.detail, spawnId: ctx.spawnId };
  const manifest = store.writeGrantManifest(ctx.rootDir, ctx.spawnId);
  if (!manifest.ok) {
    store.removeSpawn(ctx.spawnId, ctx.rootDir);
    return { ok: false, reason: manifest.reason || 'grant-manifest-failed', detail: manifest.detail, spawnId: ctx.spawnId };
  }
  const composed = launcher.compose(entry.profile, {
    workspace: ctx.workspace,
    env: ctx.env || process.env,
    engineProbe: ctx.engineProbe,
    writableRoots: ctx.writableRoots,
    userConfig: ctx.userConfig,
    scratchDir: reg.scratch,
    spawnId: ctx.spawnId,
    testBase: true,
    requiresKernelTier: true,
    gitIdentity: false,
    grantManifestPath: manifest.path,
  });
  if (!composed.ok) {
    store.removeSpawn(ctx.spawnId, ctx.rootDir);
    return { ok: false, reason: 'compose-refused', code: composed.code, detail: composed.detail, spawnId: ctx.spawnId };
  }
  return {
    ok: true,
    stage,
    spawnId: ctx.spawnId,
    kind: 'script',
    command,
    argv: [...composed.argv, '--', ...command],
    env: composed.env,
    deny: composed.deny,
    tier: composed.tier,
    engine: composed.engine,
    scratch: reg.scratch,
    grantManifestPath: manifest.path,
    registration: reg.entry,
    meta: composed.meta,
  };
}

// ---- pinned worktrees (Class P legs) ---------------------------------------

// Default git runner: argv array + cwd, spawnSync, never a shell. Tests
// inject their own to point at fixture repositories.
function defaultGitRunner(fallbackCwd) {
  return (argv, cwd) => {
    const r = spawnSync('git', argv, { cwd: cwd || fallbackCwd, encoding: 'utf8' });
    return { status: r.status, stdout: r.stdout || '', stderr: r.stderr || '', error: r.error ? r.error.message : null };
  };
}

function gitRunnerOf(opts, fallbackCwd) {
  return typeof opts === 'object' && typeof opts.gitRunner === 'function' ? opts.gitRunner : defaultGitRunner(fallbackCwd);
}

function newRunTag() {
  const ts = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+$/, '');
  return `pin-${ts}-${crypto.randomBytes(4).toString('hex')}`;
}

// materializePin(rootDir, { loopStartCommit, gitRunner?, runTag? }) —
// checks a detached worktree out at the loop-start commit under
// <storeRoot>/pin-worktrees/<runTag> and records its tree hash in the
// store. The worktree is materialized inside the machine-local store so no
// sandbox ever sees it as writable.
function materializePin(rootDir, opts = {}) {
  const store = getStore();
  if (!store) return fail('store-unavailable', 'the trust store module could not be loaded');
  const commit = opts.loopStartCommit;
  if (typeof commit !== 'string' || !GIT_SHA_RE.test(commit)) {
    return fail('pin-commit-invalid', 'loopStartCommit must be a git commit hash (7-64 hex chars)');
  }
  const runTag = typeof opts.runTag === 'string' && opts.runTag ? opts.runTag : newRunTag();
  if (!ID_RE.test(runTag)) {
    return fail('pin-run-tag-invalid', 'runTag must be filename-safe (letters, digits, dot, dash, underscore)');
  }
  const root = store.storeRoot(rootDir);
  if (root == null) return fail('store-unavailable', 'no machine-local data home resolvable for the pin worktree');
  // Pin worktrees live under <storeRoot>/pin-worktrees/<runTag> — inside
  // the machine-local store (masked from every sandbox), never inside the
  // repo working tree. The store module owns the directory name.
  const dir = store.pinWorktreesDir(rootDir);
  const wtPath = path.join(dir, runTag);
  const git = gitRunnerOf(opts, rootDir);
  const sweep = () => {
    try { git(['worktree', 'remove', '--force', wtPath], rootDir); } catch { /* best effort */ }
    try { git(['worktree', 'prune'], rootDir); } catch { /* best effort */ }
  };
  try { fs.mkdirSync(dir, { recursive: true }); }
  catch (e) { return fail('pin-dir-unwritable', e.message); }
  let add;
  try { add = git(['worktree', 'add', '--detach', wtPath, commit], rootDir); }
  catch (e) { return fail('pin-worktree-add-failed', e.message); }
  if (!add || add.status !== 0) {
    return fail('pin-worktree-add-failed', String((add && (add.stderr || add.stdout)) || 'git worktree add failed').trim());
  }
  let tree;
  try { tree = git(['rev-parse', `${commit}^{tree}`], rootDir); }
  catch (e) { sweep(); return fail('pin-tree-unresolved', e.message); }
  const treeSha = tree && tree.status === 0 ? String(tree.stdout || '').trim() : '';
  if (!GIT_SHA_RE.test(treeSha)) {
    sweep();
    return fail('pin-tree-unresolved', String((tree && (tree.stderr || tree.stdout)) || 'rev-parse failed').trim());
  }
  const rec = store.recordPin(rootDir, { runTag, path: wtPath, treeSha, loopStartCommit: commit });
  if (!rec.ok) {
    sweep();
    return { ok: false, reason: rec.reason, detail: rec.detail, runTag };
  }
  return { ok: true, runTag, path: wtPath, treeSha, loopStartCommit: commit, rootDir: path.resolve(rootDir) };
}

// Resolve the authoritative pin record for a leg: with a runTag the store
// record is re-read fresh every time (the recorded hash is the trust
// input, never a caller-held copy); a pin carrying only path+treeSha is
// verified directly.
function pinnedRecordFor(pin, opts) {
  if (!pin || typeof pin !== 'object') return fail('pin-invalid', 'pin must be an object carrying a runTag or a path+treeSha pair');
  if (typeof pin.runTag === 'string' && pin.runTag) {
    if (!ID_RE.test(pin.runTag)) return fail('pin-invalid', 'runTag must be filename-safe');
    const store = getStore();
    if (!store) return fail('store-unavailable', 'the trust store module could not be loaded');
    const rootDir = opts && typeof opts.rootDir === 'string' && opts.rootDir ? opts.rootDir : pin.rootDir;
    if (!rootDir) return fail('pin-invalid', 'a runTag lookup requires rootDir (pin.rootDir or opts.rootDir)');
    const pins = store.readPins(rootDir);
    if (!pins.ok) return { ok: false, reason: pins.reason, detail: pins.detail };
    const rec = pins.pins[pin.runTag];
    if (!rec) return fail('pin-unknown', `no pinned worktree recorded for run tag ${pin.runTag}`);
    return { ok: true, record: rec, runTag: pin.runTag };
  }
  if (typeof pin.path === 'string' && path.isAbsolute(pin.path) && typeof pin.treeSha === 'string' && GIT_SHA_RE.test(pin.treeSha)) {
    return { ok: true, record: { path: pin.path, treeSha: pin.treeSha }, runTag: null };
  }
  return fail('pin-invalid', 'pin carries neither a runTag nor a path+treeSha pair');
}

// loadPinnedModule(pin, relPath, opts?) — re-verify the recorded tree hash
// against the worktree's HEAD, then DYNAMIC-require the module from the
// worktree path. The verification precedes the require: a mismatched hash
// never loads any code. This is the only sanctioned way runner-trust code
// executes for Class P legs — never a static require into the live tree.
function loadPinnedModule(pin, relPath, opts = {}) {
  const r = pinnedRecordFor(pin, opts);
  if (!r.ok) return r;
  const rec = r.record;
  if (typeof relPath !== 'string' || !relPath || path.isAbsolute(relPath) || relPath.split(/[\\/]/).includes('..')) {
    return fail('pin-module-invalid', 'relPath must be a relative path inside the pinned worktree');
  }
  const git = gitRunnerOf(opts, rec.path);
  let v;
  try { v = git(['rev-parse', 'HEAD^{tree}'], rec.path); }
  catch (e) { return fail('pin-tampered', e.message); }
  if (!v || v.status !== 0) {
    return fail('pin-tampered', `pinned worktree HEAD unresolvable: ${String((v && (v.stderr || v.stdout)) || 'git failed').trim()}`);
  }
  const cur = String(v.stdout || '').trim();
  if (cur !== rec.treeSha) {
    return fail('pin-tampered', `pinned worktree tree ${cur} does not match the recorded ${rec.treeSha}`);
  }
  const abs = path.resolve(rec.path, relPath);
  if (abs !== rec.path && !abs.startsWith(rec.path + path.sep)) {
    return fail('pin-module-invalid', 'relPath resolves outside the pinned worktree');
  }
  let mod;
  try { mod = require(abs); }
  catch (e) { return fail('pin-module-unloadable', e.message); }
  return { ok: true, path: abs, module: mod, runTag: r.runTag, treeSha: rec.treeSha };
}

// runPinnedLeg(pin, relPath, fnName, args, opts?) — load through
// loadPinnedModule (hash re-verified first), call the exported fn with the
// spread args, and return its verdict as data. A thrown leg returns as a
// named refusal; prose is never parsed.
function runPinnedLeg(pin, relPath, fnName, args, opts = {}) {
  const load = loadPinnedModule(pin, relPath, opts);
  if (!load.ok) return load;
  const fn = load.module && load.module[fnName];
  if (typeof fn !== 'function') {
    return fail('leg-fn-missing', `${relPath} does not export a function named ${fnName}`);
  }
  let verdict;
  try { verdict = fn(...(Array.isArray(args) ? args : [])); }
  catch (e) { return fail('leg-threw', e.message); }
  return { ok: true, relPath, fn: fnName, runTag: load.runTag, treeSha: load.treeSha, verdict };
}

// Best-effort removal of a worktree path plus its repo metadata.
function sweepWorktree(git, rootDir, wtPath) {
  try { git(['worktree', 'remove', '--force', wtPath], rootDir); } catch { /* best effort */ }
  if (fs.existsSync(wtPath)) {
    try { fs.rmSync(wtPath, { recursive: true, force: true }); } catch { /* gone */ }
  }
  try { git(['worktree', 'prune'], rootDir); } catch { /* best effort */ }
}

// recyclePin(rootDir, runTag, opts?) — remove one pinned worktree and its
// store record (idempotent: an unknown run tag sweeps any stray directory
// and reports absent).
function recyclePin(rootDir, runTag, opts = {}) {
  const store = getStore();
  if (!store) return fail('store-unavailable', 'the trust store module could not be loaded');
  if (typeof runTag !== 'string' || !ID_RE.test(runTag)) {
    return fail('pin-run-tag-invalid', 'runTag must be filename-safe (letters, digits, dot, dash, underscore)');
  }
  const pinDir = store.pinWorktreesDir(rootDir);
  const git = gitRunnerOf(opts, rootDir);
  const pins = store.readPins(rootDir);
  if (!pins.ok) return { ok: false, reason: pins.reason, detail: pins.detail };
  const rec = pins.pins[runTag];
  if (!rec) {
    const stray = pinDir == null ? null : path.join(pinDir, runTag);
    const swept = stray != null && fs.existsSync(stray);
    if (swept) sweepWorktree(git, rootDir, stray);
    return { ok: true, runTag, absent: true, ...(swept ? { swept: true } : {}) };
  }
  let rm = null;
  try { rm = git(['worktree', 'remove', '--force', rec.path], rootDir); }
  catch (e) { rm = { status: 1, stderr: e.message }; }
  if ((rm && rm.status !== 0) && fs.existsSync(rec.path)) {
    // a plain directory without metadata removes like any stray; only a
    // path git cannot clear AND that still exists refuses
    try { fs.rmSync(rec.path, { recursive: true, force: true }); }
    catch (e) { return fail('pin-recycle-failed', `${rec.path}: ${e.message}`); }
  }
  try { git(['worktree', 'prune'], rootDir); } catch { /* best effort */ }
  const drop = store.dropPin(rootDir, runTag);
  if (!drop.ok) return { ok: false, reason: drop.reason, detail: drop.detail };
  return { ok: true, runTag, path: rec.path };
}

// lazyRecyclePins(rootDir, { liveRunTags, gitRunner? }) — recycle every
// recorded pin whose run tag is not live (run-end and lazy sweeps).
function lazyRecyclePins(rootDir, opts = {}) {
  const store = getStore();
  if (!store) return fail('store-unavailable', 'the trust store module could not be loaded');
  const pins = store.readPins(rootDir);
  if (!pins.ok) return { ok: false, reason: pins.reason, detail: pins.detail };
  const live = new Set(Array.isArray(opts.liveRunTags) ? opts.liveRunTags.map(String) : []);
  const recycled = [];
  const failures = [];
  for (const tag of Object.keys(pins.pins)) {
    if (live.has(tag)) continue;
    const r = recyclePin(rootDir, tag, opts);
    if (r.ok) recycled.push(tag);
    else failures.push({ runTag: tag, reason: r.reason, detail: r.detail });
  }
  return { ok: failures.length === 0, recycled, failures };
}

module.exports = {
  DISPATCH_TABLE_NAME,
  DISPATCH_SCHEMA_VERSION,
  STAGES,
  WORKERS,
  UNITS,
  VERBS,
  WAVE_STAGE,
  DEFAULT_VERIFY_STEPS,
  loadDispatchTable,
  resolveWorkerPlan,
  dispatchNeedsHost,
  composeScriptSpawn,
  materializePin,
  loadPinnedModule,
  runPinnedLeg,
  recyclePin,
  lazyRecyclePins,
};
