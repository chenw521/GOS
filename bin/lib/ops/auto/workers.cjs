// ops/auto/workers — stage-dispatch table loader and worker forms for the
// auto loop. Reads templates/auto-dispatch.json (pure data) and enforces
// every value bound in code, mirroring launcher.loadProfile's stepFail-closed
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
//
// Wave dispatch (BUILD): a sequential iterator over the frozen
// plan_snapshot's waves — never live plan.md — with one equipped spawn per
// wave under three contracts. Input: the runner-held, store-stamped prompt
// template interpolates only the wave number and the wave's task ids from
// the snapshot (scope pointers; repo prose never rides in). Process: deny
// hits stay zero, and the frozen world (spec sha, plan snapshot, dispatch
// table stamp, pinned worktree) is re-verified after every wave. Output:
// exactly one new commit on the work branch touching only the wave's
// declared files, no ref moving besides the work-branch tip, and no
// uncommitted drift beyond machine-local paths — or the wave holds with a
// named violation. Waves touching runner-critical paths release only after
// a one-round red-team pass over the wave diff; a released edit of the
// dispatch table rolls the store stamp. Crash recovery (reconcileWaves)
// adopts a commit uniquely attributable to the half-run wave and re-runs
// only the release check.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const limits = require('./limits.cjs');
const launcher = require('./launcher.cjs');
const registry = require('./adapters/registry.cjs');

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
const RUNTAG_RE = /^[A-Za-z\d][A-Za-z\d._-]*$/;
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

function stepFail(reason, detail, file) {
  return { ok: false, reason, detail, file };
}

// Validate one stage entry; returns a stepFail-closed result or null when the
// entry is well formed. Check order: worker presence, closed vocabularies,
// pinned profile, dispatch unit, verbs, numeric cap, contract form.
function validateStage(stage, entry, file) {
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
    return stepFail('missing-worker-form', `stage ${stage}: entry is not an object`, file);
  }
  if (typeof entry.worker !== 'string' || !entry.worker) {
    return stepFail('missing-worker-form', `stage ${stage}: worker field is missing`, file);
  }
  if (!WORKERS.includes(entry.worker)) {
    return stepFail('unknown-worker', `stage ${stage}: worker '${entry.worker}' not in {${WORKERS.join(', ')}}`, file);
  }
  const want = pinnedProfile(stage);
  if (entry.profile !== want) {
    return stepFail('bad-profile', `stage ${stage}: profile '${entry.profile}' refused — pinned to '${want}'`, file);
  }
  if (!UNITS.includes(entry.unit)) {
    return stepFail('bad-unit', `stage ${stage}: unit '${entry.unit}' not in {${UNITS.join(', ')}}`, file);
  }
  if (stage !== WAVE_STAGE && entry.wave_dispatch) {
    return stepFail('bad-unit', `stage ${stage}: wave_dispatch is reserved for ${WAVE_STAGE}`, file);
  }
  if (!Array.isArray(entry.verbs)) {
    return stepFail('unknown-verb', `stage ${stage}: verbs is not an array`, file);
  }
  for (const v of entry.verbs) {
    if (!VERBS.includes(v)) {
      return stepFail('unknown-verb', `stage ${stage}: verb '${v}' not in {${VERBS.join(', ')}}`, file);
    }
  }
  const cap = entry.use_cap;
  if (!Number.isInteger(cap) || cap < 1 || cap > limits.HARD_USE_CAP_CEILING) {
    return stepFail('cap-over-ceiling', `stage ${stage}: use_cap ${JSON.stringify(cap)} outside 1..${limits.HARD_USE_CAP_CEILING}`, file);
  }
  const contracts = entry.contracts;
  if (!contracts || typeof contracts !== 'object' || Array.isArray(contracts)) {
    return stepFail('missing-worker-form', `stage ${stage}: contracts is not an object`, file);
  }
  if (entry.worker === 'agent' && typeof contracts.prompt !== 'string') {
    return stepFail('missing-worker-form', `stage ${stage}: agent worker requires contracts.prompt as a string`, file);
  }
  if (entry.worker === 'script' && !Array.isArray(contracts.steps)) {
    return stepFail('missing-worker-form', `stage ${stage}: script worker requires contracts.steps as an array`, file);
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
  catch (e) { return stepFail('table-unreadable', e.message, file); }
  let obj;
  try { obj = JSON.parse(raw); }
  catch (e) { return stepFail('table-corrupt', e.message, file); }
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) {
    return stepFail('table-corrupt', 'root is not a JSON object', file);
  }
  if (obj.dispatch_schema_version !== DISPATCH_SCHEMA_VERSION) {
    return stepFail('schema-version', `dispatch_schema_version ${JSON.stringify(obj.dispatch_schema_version)} is not a known version (expected ${DISPATCH_SCHEMA_VERSION})`, file);
  }
  const stages = obj.stages;
  if (!stages || typeof stages !== 'object' || Array.isArray(stages)) {
    return stepFail('unknown-stage', 'stages is not an object keyed by stage name', file);
  }
  const keys = Object.keys(stages);
  const unknown = keys.filter((k) => !STAGES.includes(k));
  if (unknown.length) {
    return stepFail('unknown-stage', `unknown stage key(s): ${unknown.join(', ')}`, file);
  }
  const missing = STAGES.filter((s) => !(s in stages));
  if (missing.length) {
    return stepFail('unknown-stage', `missing stage key(s): ${missing.join(', ')}`, file);
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
function storeOf() {
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
// each step carries its execution class, or a stepFail-closed refusal. Steps
// derive from the entry's contracts.steps when it declares any; VERIFY
// falls back to the builtin default; every other script stage resolves to
// no steps (SHIP's delivery stays runner-side). Agent stages refuse —
// execution-class plans exist only for script workers. A step whose class
// cannot be determined refuses the whole plan.
function resolveWorkerPlan(stage, table) {
  const name = String(stage || '').toUpperCase();
  if (!STAGES.includes(name)) return stepFail('unknown-stage', `unknown stage ${JSON.stringify(stage)}`);
  let stages = stagesOf(table);
  if (!stages) {
    const load = loadDispatchTable();
    if (!load.ok) return stepFail('dispatch-table-unavailable', load.detail, load.file);
    stages = load.table.stages;
  }
  const entry = stages[name];
  if (!entry || typeof entry !== 'object') return stepFail('unknown-stage', `stage ${name} is missing from the dispatch table`);
  if (entry.worker === 'agent') {
    return stepFail('agent-worker', `${name} runs an agent worker — execution-class plans apply to script stages only`);
  }
  if (entry.worker !== 'script') {
    return stepFail('unknown-worker', `stage ${name}: worker '${entry.worker}' has no execution class`);
  }
  const declared = entry.contracts && Array.isArray(entry.contracts.steps) ? entry.contracts.steps : null;
  if (declared && declared.length) {
    const steps = [];
    for (const s of declared) {
      const kind = classifyStep(s);
      if (!kind) {
        return stepFail('no-clear-class', `step ${s && s.id ? s.id : JSON.stringify(s)} declares neither exactly one fixed command (Class S) nor one pinned module leg (Class P)`);
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
    return stepFail('not-script-step', `step ${step && step.id ? step.id : '(unidentified)'} does not carry a fixed command (Class S)`);
  }
  const command = step.command.map(String);
  if (command.includes('opencode')) {
    return stepFail('host-adapter-forbidden', 'a Class S spawn runs fixed repo-authored argv — the host adapter can never appear in it');
  }
  const stage = String(ctx.stage || '').toUpperCase();
  if (!STAGES.includes(stage)) return stepFail('unknown-stage', `unknown stage ${JSON.stringify(ctx.stage)}`);
  const load = stagesOf(ctx.table) ? ctx.table : loadDispatchTable();
  if (!load.ok) return stepFail('dispatch-table-unavailable', load.detail, load.file);
  const entry = load.table.stages[stage];
  if (!entry) return stepFail('unknown-stage', `stage ${stage} is missing from the dispatch table`);
  if (entry.worker !== 'script') {
    return stepFail('agent-worker', `${stage} runs an agent worker — Class S spawns apply to script stages only`);
  }
  if (typeof ctx.spawnId !== 'string' || !RUNTAG_RE.test(ctx.spawnId)) {
    return stepFail('invalid-spawn-id', 'spawnId must be filename-safe (letters, digits, dot, dash, underscore)');
  }
  const store = storeOf();
  if (!store) return stepFail('store-unavailable', 'the trust store module could not be loaded');
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
    ackDir: reg.acksDir,
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
    // Engine-first argv: consumers feed this verbatim to the spawn runner,
    // so the sandbox engine must lead — the frame alone would die ENOENT.
    argv: [composed.engine, ...composed.argv, '--', ...command],
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
  const store = storeOf();
  if (!store) return stepFail('store-unavailable', 'the trust store module could not be loaded');
  const commit = opts.loopStartCommit;
  if (typeof commit !== 'string' || !GIT_SHA_RE.test(commit)) {
    return stepFail('pin-commit-invalid', 'loopStartCommit must be a git commit hash (7-64 hex chars)');
  }
  const runTag = typeof opts.runTag === 'string' && opts.runTag ? opts.runTag : newRunTag();
  if (!RUNTAG_RE.test(runTag)) {
    return stepFail('pin-run-tag-invalid', 'runTag must be filename-safe (letters, digits, dot, dash, underscore)');
  }
  const root = store.storeRoot(rootDir);
  if (root == null) return stepFail('store-unavailable', 'no machine-local data home resolvable for the pin worktree');
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
  catch (e) { return stepFail('pin-dir-unwritable', e.message); }
  let add;
  try { add = git(['worktree', 'add', '--detach', wtPath, commit], rootDir); }
  catch (e) { return stepFail('pin-worktree-add-failed', e.message); }
  if (!add || add.status !== 0) {
    return stepFail('pin-worktree-add-failed', String((add && (add.stderr || add.stdout)) || 'git worktree add failed').trim());
  }
  let tree;
  try { tree = git(['rev-parse', `${commit}^{tree}`], rootDir); }
  catch (e) { sweep(); return stepFail('pin-tree-unresolved', e.message); }
  const treeSha = tree && tree.status === 0 ? String(tree.stdout || '').trim() : '';
  if (!GIT_SHA_RE.test(treeSha)) {
    sweep();
    return stepFail('pin-tree-unresolved', String((tree && (tree.stderr || tree.stdout)) || 'rev-parse failed').trim());
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
  if (!pin || typeof pin !== 'object') return stepFail('pin-invalid', 'pin must be an object carrying a runTag or a path+treeSha pair');
  if (typeof pin.runTag === 'string' && pin.runTag) {
    if (!RUNTAG_RE.test(pin.runTag)) return stepFail('pin-invalid', 'runTag must be filename-safe');
    const store = storeOf();
    if (!store) return stepFail('store-unavailable', 'the trust store module could not be loaded');
    const rootDir = opts && typeof opts.rootDir === 'string' && opts.rootDir ? opts.rootDir : pin.rootDir;
    if (!rootDir) return stepFail('pin-invalid', 'a runTag lookup requires rootDir (pin.rootDir or opts.rootDir)');
    const pins = store.readPins(rootDir);
    if (!pins.ok) return { ok: false, reason: pins.reason, detail: pins.detail };
    const rec = pins.pins[pin.runTag];
    if (!rec) return stepFail('pin-unknown', `no pinned worktree recorded for run tag ${pin.runTag}`);
    return { ok: true, record: rec, runTag: pin.runTag };
  }
  if (typeof pin.path === 'string' && path.isAbsolute(pin.path) && typeof pin.treeSha === 'string' && GIT_SHA_RE.test(pin.treeSha)) {
    return { ok: true, record: { path: pin.path, treeSha: pin.treeSha }, runTag: null };
  }
  return stepFail('pin-invalid', 'pin carries neither a runTag nor a path+treeSha pair');
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
    return stepFail('pin-module-invalid', 'relPath must be a relative path inside the pinned worktree');
  }
  const git = gitRunnerOf(opts, rec.path);
  let v;
  try { v = git(['rev-parse', 'HEAD^{tree}'], rec.path); }
  catch (e) { return stepFail('pin-tampered', e.message); }
  if (!v || v.status !== 0) {
    return stepFail('pin-tampered', `pinned worktree HEAD unresolvable: ${String((v && (v.stderr || v.stdout)) || 'git failed').trim()}`);
  }
  const cur = String(v.stdout || '').trim();
  if (cur !== rec.treeSha) {
    return stepFail('pin-tampered', `pinned worktree tree ${cur} does not match the recorded ${rec.treeSha}`);
  }
  const abs = path.resolve(rec.path, relPath);
  if (abs !== rec.path && !abs.startsWith(rec.path + path.sep)) {
    return stepFail('pin-module-invalid', 'relPath resolves outside the pinned worktree');
  }
  let mod;
  try { mod = require(abs); }
  catch (e) { return stepFail('pin-module-unloadable', e.message); }
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
    return stepFail('leg-fn-missing', `${relPath} does not export a function named ${fnName}`);
  }
  let verdict;
  try { verdict = fn(...(Array.isArray(args) ? args : [])); }
  catch (e) { return stepFail('leg-threw', e.message); }
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
  const store = storeOf();
  if (!store) return stepFail('store-unavailable', 'the trust store module could not be loaded');
  if (typeof runTag !== 'string' || !RUNTAG_RE.test(runTag)) {
    return stepFail('pin-run-tag-invalid', 'runTag must be filename-safe (letters, digits, dot, dash, underscore)');
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
    catch (e) { return stepFail('pin-recycle-failed', `${rec.path}: ${e.message}`); }
  }
  try { git(['worktree', 'prune'], rootDir); } catch { /* best effort */ }
  const drop = store.dropPin(rootDir, runTag);
  if (!drop.ok) return { ok: false, reason: drop.reason, detail: drop.detail };
  return { ok: true, runTag, path: rec.path };
}

// lazyRecyclePins(rootDir, { liveRunTags, gitRunner? }) — recycle every
// recorded pin whose run tag is not live (run-end and lazy sweeps).
function lazyRecyclePins(rootDir, opts = {}) {
  const store = storeOf();
  if (!store) return stepFail('store-unavailable', 'the trust store module could not be loaded');
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

// ---- wave dispatch (BUILD) --------------------------------------------------
//
// The wave driver iterates the frozen plan_snapshot (never live plan.md),
// strictly sequentially, one equipped spawn per wave. Modules with a
// store-side cycle (store requires this module at load) resolve lazily.

const WAVE_PROMPT_KIND = 'wavePrompt';
const WAVE_MARKER_NAME = 'wave.json';
const WAVE_NOOP_NAME = 'noop';
const DISPATCH_TABLE_REL = 'templates/' + DISPATCH_TABLE_NAME;

// Runner-critical paths: a wave declaring (or a diff touching) any of
// these releases only after a one-round red-team pass over the wave diff.
const RUNNER_CRITICAL_FILES = Object.freeze(new Set([
  'bin/lib/core/spawnreg.cjs',
  'bin/lib/core/lock.cjs',
  'bin/lib/ops/gate.cjs',
  DISPATCH_TABLE_REL,
]));
const RUNNER_CRITICAL_PREFIXES = Object.freeze(['bin/lib/ops/auto/', 'hooks/']);

function isRunnerCriticalPath(p) {
  return RUNNER_CRITICAL_FILES.has(p) || RUNNER_CRITICAL_PREFIXES.some((pre) => p.startsWith(pre));
}

// Runner-held wave prompt template. The only interpolation tokens are the
// two scope pointers {wave} and {taskIds}; everything else is the distilled
// hard-gate text. The sha256 of this exact constant is stamped into the
// trust store (snapshot kind 'wavePrompt') and any later drift fails closed
// — exactly the redteam prompt pattern.
const WAVE_PROMPT_TEMPLATE = [
  'GOS auto BUILD wave {wave} — tasks {taskIds}.',
  'Work only the files the frozen plan snapshot declares for these tasks.',
  'Land exactly one commit on the work branch for this wave before you exit.',
  'Never touch the dispatch table, runner-critical paths, the plan snapshot, the spec, or any ref besides the work branch tip.',
  'When the wave genuinely needs no change, write a file named "noop" holding one reason line into your scratch directory, then exit.',
  'This session is one-shot: finish the wave or stepFail with a clear error; never loop.',
].join('\n');
const WAVE_PROMPT_TOKENS = Object.freeze(['wave', 'taskIds']);

function getBreaker() {
  try { return require('./breaker.cjs'); } catch { return null; }
}

function getLoop() {
  try { return require('./loop.cjs'); } catch { return null; }
}

function sha256Text(text) {
  return crypto.createHash('sha256').update(String(text), 'utf8').digest('hex');
}

function sha256FileSyncSafe(p) {
  try { return crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex'); }
  catch { return null; }
}

function wavePromptSourceHash() {
  return sha256Text(WAVE_PROMPT_TEMPLATE);
}

// Interpolate the runner template for one wave. A template carrying any
// brace token besides the two sanctioned pointers refuses — repo prose can
// never ride into the prompt through the template.
function renderWavePrompt(ctx, template) {
  const tpl = typeof template === 'string' ? template : WAVE_PROMPT_TEMPLATE;
  for (const m of tpl.matchAll(/\{([A-Za-z][A-Za-z\d]*)\}/g)) {
    if (!WAVE_PROMPT_TOKENS.includes(m[1])) {
      return stepFail('prompt-token-refused', `template carries unsanctioned token '{${m[1]}}' — only {wave} and {taskIds} may appear`);
    }
  }
  if (!ctx || !Number.isInteger(ctx.wave) || ctx.wave < 1) {
    return stepFail('invalid-wave', 'wave must be an integer >= 1');
  }
  if (!Array.isArray(ctx.taskIds) || !ctx.taskIds.length
    || !ctx.taskIds.every((id) => typeof id === 'string' && id)) {
    return stepFail('invalid-task-ids', 'taskIds must be a non-empty array of task id strings');
  }
  const prompt = tpl.replaceAll('{wave}', String(ctx.wave)).replaceAll('{taskIds}', ctx.taskIds.join(','));
  return { ok: true, prompt };
}

// Record the runner template in the trust store: save when absent,
// verify-equal when present (a drifted hash means earlier waves ran under a
// different prompt than the current template — stepFail closed).
function ensureWavePromptRecorded(rootDir) {
  const store = storeOf();
  if (!store) return stepFail('store-unavailable', 'the trust store module could not be loaded');
  const loaded = store.load(rootDir);
  if (!loaded.ok) return loaded;
  const cur = loaded.store.snapshots[WAVE_PROMPT_KIND];
  const want = wavePromptSourceHash();
  if (cur) {
    if (cur.sha256 !== want) {
      return {
        ok: false, status: 'error', reason: 'prompt-template-drift',
        detail: `stored ${cur.sha256.slice(0, 12)} != template ${want.slice(0, 12)}`,
        guidance: store.guidanceFor('auto.redteam.promptDrift'),
      };
    }
    return { ok: true, sha256: cur.sha256 };
  }
  const saved = store.saveSnapshot(WAVE_PROMPT_KIND, WAVE_PROMPT_TEMPLATE, rootDir);
  if (!saved.ok) return saved;
  return { ok: true, sha256: saved.snapshot.sha256 };
}

// ---- wave snapshot helpers ----

// Deterministic JSON for snapshot comparison (key order normalized).
function stableStringify(v) {
  if (v == null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return '[' + v.map(stableStringify).join(',') + ']';
  return '{' + Object.keys(v).sort()
    .map((k) => JSON.stringify(k) + ':' + stableStringify(v[k])).join(',') + '}';
}

function readStateJson(rootDir) {
  try { return JSON.parse(fs.readFileSync(path.join(rootDir, '.gos', 'state.json'), 'utf8')); }
  catch { return null; }
}

// Spec file path anchored at this repo root (state.spec_path override wins,
// else the task/<id>/spec.md convention).
function specPathIn(rootDir, state) {
  if (!state) return null;
  if (typeof state.spec_path === 'string' && state.spec_path) {
    return path.isAbsolute(state.spec_path) ? state.spec_path : path.join(rootDir, state.spec_path);
  }
  const tid = state.task_id || (state.task && state.task.id);
  if (typeof tid !== 'string' || !tid) return null;
  return path.join(rootDir, 'task', tid, 'spec.md');
}

// Group the frozen snapshot's tasks by wave, ascending. A snapshot whose
// wave structure could not be derived refuses BUILD entry with guidance
// back to PLAN — the same verdict task/plansnap.cjs#buildEntryCheck hands
// the stage loop, mirrored here so the wave iterator never grows an
// ops→task require edge.
function waveGroupsOf(snapshot) {
  if (!snapshot || !Array.isArray(snapshot.tasks) || !snapshot.tasks.length) {
    return stepFail('snapshot-empty', 'the frozen plan snapshot carries no tasks');
  }
  const v = snapshot && snapshot.meta && snapshot.meta.waveValidation;
  if (v && !v.ok) {
    return {
      ok: false, reason: v.reason, detail: v.detail,
      guidance: {
        what: 'BUILD entry refused: the frozen plan carries no wave structure',
        fix: 'return to PLAN — re-freeze plan.md with "### Wave N" headings (gos commit plan), then re-enter BUILD',
      },
    };
  }
  const groups = new Map();
  for (const t of snapshot.tasks) {
    if (!t || typeof t.id !== 'string' || !t.id || !Number.isInteger(t.wave) || t.wave < 1) {
      return stepFail('snapshot-task-invalid', `snapshot task ${JSON.stringify(t && t.id)} carries no usable wave assignment`);
    }
    if (!Array.isArray(t.files)) {
      return stepFail('snapshot-task-invalid', `snapshot task ${t.id} carries no declared files array`);
    }
    if (!groups.has(t.wave)) groups.set(t.wave, []);
    groups.get(t.wave).push(t);
  }
  return { ok: true, groups: [...groups.keys()].sort((a, b) => a - b).map((w) => ({ wave: w, tasks: groups.get(w) })) };
}

// ---- wave evidence helpers ----

// Refs snapshot: for-each-ref lines plus the HEAD reflog head, as one text
// (hash-stamped into completion records) and one map (drift checking).
function refsSnapshotOf(git, rootDir) {
  let fer;
  try { fer = git(['for-each-ref', '--format=%(refname) %(objectname)'], rootDir); }
  catch { return null; }
  if (!fer || fer.status !== 0) return null;
  let reflogHead = '';
  try {
    const rl = git(['reflog', 'show', '-n', '1', '--format=%H %gs', 'HEAD'], rootDir);
    if (rl && rl.status === 0) reflogHead = String(rl.stdout || '').trim();
  } catch { /* reflog absent on fresh heads — evidence degrades, not fails */ }
  const text = String(fer.stdout || '').trim() + '\n--reflog--\n' + reflogHead;
  return { text, map: refsMapFromText(text) };
}

function refsMapFromText(text) {
  const map = {};
  for (const line of String(text || '').split('--reflog--')[0].split('\n')) {
    const t = line.trim();
    if (!t) continue;
    const sp = t.indexOf(' ');
    if (sp > 0) map[t.slice(0, sp)] = t.slice(sp + 1).trim();
  }
  return map;
}

// Refs other than the exempted one (the work-branch tip) that moved,
// appeared, or vanished between two snapshots.
function refsDrift(preMap, postMap, exemptRef) {
  const moved = [];
  for (const ref of Object.keys(preMap)) {
    if (postMap[ref] == null) moved.push(`${ref} deleted`);
    else if (postMap[ref] !== preMap[ref] && ref !== exemptRef) {
      moved.push(`${ref}: ${preMap[ref].slice(0, 10)} -> ${postMap[ref].slice(0, 10)}`);
    }
  }
  for (const ref of Object.keys(postMap)) {
    if (preMap[ref] == null) moved.push(`${ref} created`);
  }
  return moved;
}

function statusPathsOf(git, rootDir) {
  let st;
  try { st = git(['status', '--porcelain', '-uall'], rootDir); }
  catch { return null; }
  if (!st || st.status !== 0) return null;
  return new Set(String(st.stdout || '').split('\n')
    .map((l) => l.slice(3).trim()).filter(Boolean).map((p) => p.replace(/^"|"$/g, '')));
}

// Uncommitted drift beyond machine-local paths: paths that appeared after
// the wave and live outside .gos/ (state checkpoints, logs, cache).
function dirtyDriftPaths(preSet, postSet) {
  const out = [];
  for (const p of postSet || []) {
    if (preSet && preSet.has(p)) continue;
    if (p === '.gos' || p.startsWith('.gos/')) continue;
    out.push(p);
  }
  return out;
}

function readHeadOf(git, rootDir) {
  let r;
  try { r = git(['rev-parse', 'HEAD'], rootDir); }
  catch { return null; }
  const out = r && r.status === 0 ? String(r.stdout || '').trim() : '';
  return out && GIT_SHA_RE.test(out) ? out : null;
}

function currentBranchOf(git, rootDir) {
  try {
    const r = git(['rev-parse', '--abbrev-ref', 'HEAD'], rootDir);
    return r && r.status === 0 ? String(r.stdout || '').trim() : null;
  } catch { return null; }
}

// ---- wave evidence helpers ----

// No-op evidence: the spawn's own declared "nothing to do" signal, read
// from its scratch (advisory; the release check still demands no ref moved
// and no drift anywhere).
function readNoopSignal(scratch) {
  try {
    const line = fs.readFileSync(path.join(scratch, WAVE_NOOP_NAME), 'utf8').split('\n')[0].trim();
    return line || 'no-op';
  } catch { return null; }
}

// Frozen-world drift: the live task state's plan snapshot must equal the
// frozen snapshot this driver iterates, and a frozen spec_sha256 must still
// hash the spec file. Returns null while frozen.
function frozenDrift(snapshot, rootDir, stateNow) {
  const frozenTasks = stableStringify(snapshot.tasks);
  const liveTasks = stableStringify(stateNow && stateNow.plan_snapshot ? stateNow.plan_snapshot.tasks : null);
  if (frozenTasks !== liveTasks) {
    return 'the live plan snapshot drifted from the frozen snapshot this wave iterates';
  }
  if (stateNow && typeof stateNow.spec_sha256 === 'string' && stateNow.spec_sha256) {
    const sp = specPathIn(rootDir, stateNow);
    const cur = sp == null ? null : sha256FileSyncSafe(sp);
    if (cur == null || cur !== stateNow.spec_sha256) {
      return 'spec sha mismatch — the spec file changed under the frozen spec_sha256';
    }
  }
  return null;
}

// Verify a pinned worktree still sits at its recorded tree hash (the same
// check loadPinnedModule performs, without loading any module).
function verifyPin(pin, opts = {}) {
  const r = pinnedRecordFor(pin, opts);
  if (!r.ok) return r;
  const rec = r.record;
  const git = gitRunnerOf(opts, rec.path);
  let v;
  try { v = git(['rev-parse', 'HEAD^{tree}'], rec.path); }
  catch (e) { return stepFail('pin-tampered', e.message); }
  if (!v || v.status !== 0) {
    return stepFail('pin-tampered', 'pinned worktree HEAD unresolvable');
  }
  const cur = String(v.stdout || '').trim();
  if (cur !== rec.treeSha) {
    return stepFail('pin-tampered', `pinned worktree tree ${cur} does not match the recorded ${rec.treeSha}`);
  }
  return { ok: true, treeSha: cur, runTag: r.runTag };
}

// ---- wave release check (shared by the driver and crash reconciliation) ----

// One red-team round over the wave diff: reuse the redteam round machinery
// unchanged; findings hold the wave, a zero round clears the release gate.
async function redteamWaveRound({ ctx, spawnId, wave }) {
  const redteam = require('./redteam.cjs');
  return redteam.runRound({ stage: `BUILD-W${wave}`, spawnId: `${spawnId}-rt` }, {
    rootDir: ctx.rootDir,
    env: ctx.env || process.env,
    host: ctx.host,
    profile: 'restricted',
    spawnRunner: ctx.spawnRunner,
    engineProbe: ctx.engineProbe,
    wallMs: ctx.wallMs,
    idleMs: ctx.idleMs,
    now: ctx.now,
  });
}

// Judge one wave's output contract against the pre/post evidence. Returns
//   { action: 'release', head, rolledTable }        — the wave may be recorded
//   { action: 'release-noop', noopReason }          — evidenced no-op
//   { action: 'hold', violation, detail }           — contract violation
//   { action: 'pause', reason, detail, ... }        — runner-side failure
async function evaluateWaveOutput(a) {
  const hold = (violation, detail) => ({ action: 'hold', violation, detail });
  const gitFail = (what, r) => ({
    action: 'pause', reason: 'git-failed',
    detail: `git ${what} rc=${r && r.status}${r && String(r.stderr || '').trim() ? ': ' + String(r.stderr).trim().slice(0, 200) : ''}`,
  });
  let rl;
  try { rl = gitRunnerOf({ gitRunner: a.gitRunner }, a.rootDir)(['rev-list', `${a.preHead}..${a.postHead}`], a.rootDir); }
  catch (e) { return { action: 'pause', reason: 'git-failed', detail: e.message }; }
  if (!rl || rl.status !== 0) return gitFail('rev-list', rl);
  const commits = String(rl.stdout || '').split('\n').map((s) => s.trim()).filter(Boolean);
  const noopReason = readNoopSignal(a.scratch);
  if (noopReason != null && commits.length === 0) {
    // Evidenced no-op: no ref may move at all (not even the tip) and no
    // drift may appear beyond machine-local paths.
    const moved = refsDrift(a.preRefsMap, a.postRefs.map, null);
    if (moved.length) return hold('ref-move', `no-op wave moved refs: ${moved.join('; ')}`);
    const drift = dirtyDriftPaths(a.preDirtySet, a.postDirtySet);
    if (drift.length) return hold('dirty-drift', drift.join(', '));
    return { action: 'release-noop', noopReason };
  }
  if (commits.length === 0) {
    return hold('no-commit', 'the wave spawn exited without a commit and without no-op evidence — silence is never no-op');
  }
  if (commits.length > 1) {
    return hold('second-commit', `${commits.length} commits in the wave range (${commits.join(', ')})`);
  }
  const head = commits[0];
  let df;
  try { df = a.gitRunner(['diff', '--name-only', `${a.preHead}..${head}`], a.rootDir); }
  catch (e) { return { action: 'pause', reason: 'git-failed', detail: e.message }; }
  if (!df || df.status !== 0) return gitFail('diff --name-only', df);
  const changed = String(df.stdout || '').split('\n').map((s) => s.trim()).filter(Boolean);
  const undeclared = changed.filter((p) => !a.declaredSet.has(p));
  if (undeclared.length) {
    return hold('undeclared-path', `changed paths outside the wave's declared files: ${undeclared.join(', ')}`);
  }
  // frozen world: plan snapshot + spec sha + pinned worktree
  const stateNow = readStateJson(a.rootDir);
  const fr = frozenDrift(a.snapshot, a.rootDir, stateNow);
  if (fr) return hold('frozen-edit', fr);
  if (a.ctx.pin) {
    const pv = verifyPin(a.ctx.pin, { rootDir: a.rootDir, gitRunner: a.gitRunner });
    if (!pv.ok) return hold('frozen-edit', `pinned worktree drifted: ${pv.detail || pv.reason}`);
  }
  // dispatch-table stamp + runner-critical release gate
  const store = storeOf();
  const stampRead = store.readDispatchTableStamp(a.rootDir);
  if (!stampRead.ok) return { action: 'pause', reason: stampRead.reason, detail: stampRead.detail, path: stampRead.path };
  const tableSha = sha256FileSyncSafe(a.tableFile);
  const tableChanged = changed.includes(DISPATCH_TABLE_REL);
  const stamped = stampRead.stamp;
  let rolledTable = false;
  if (tableChanged || (stamped != null && tableSha !== stamped.sha256)) {
    if (!tableChanged) {
      return {
        action: 'pause', reason: 'external-mutation',
        detail: `dispatch table drifted outside the wave (stamp ${stamped.sha256.slice(0, 10)} != live ${String(tableSha).slice(0, 10)})`,
      };
    }
    // every dispatch-table edit routes through one red-team round; a pass
    // rolls the store stamp, findings hold the wave
    const rt = await redteamWaveRound({ ctx: a.ctx, spawnId: a.spawnId, wave: a.wave });
    if (!rt.ok) return hold('redteam-failed', `red-team round refused: ${rt.reason}${rt.detail ? ' — ' + rt.detail : ''}`);
    if (rt.round.classified !== 'zero' || !(rt.round.findings === 0)) {
      return hold('redteam-findings', `red-team round over the wave diff reported findings ${rt.round.findings} (${rt.round.classified})`);
    }
    const roll = store.rollDispatchTableStamp(a.rootDir, { sha256: tableSha, rolledByWave: `${a.task}/W${a.wave}` });
    if (!roll.ok) return { action: 'pause', reason: roll.reason, detail: roll.detail, path: roll.path };
    rolledTable = true;
  } else if (changed.some(isRunnerCriticalPath)) {
    // non-table runner-critical waves still clear one red-team round
    const rt = await redteamWaveRound({ ctx: a.ctx, spawnId: a.spawnId, wave: a.wave });
    if (!rt.ok) return hold('redteam-failed', `red-team round refused: ${rt.reason}${rt.detail ? ' — ' + rt.detail : ''}`);
    if (rt.round.classified !== 'zero' || !(rt.round.findings === 0)) {
      return hold('redteam-findings', `red-team round over the wave diff reported findings ${rt.round.findings} (${rt.round.classified})`);
    }
  }
  // refs: only the work-branch tip may move, and it must be the wave commit
  const moved = refsDrift(a.preRefsMap, a.postRefs.map, `refs/heads/${a.workBranch}`);
  if (moved.length) return hold('ref-move', moved.join('; '));
  const tip = a.postRefs.map[`refs/heads/${a.workBranch}`];
  if (tip !== head) {
    return hold('ref-move', `work branch tip is ${tip ? tip.slice(0, 10) : 'absent'}, expected the wave commit ${head.slice(0, 10)}`);
  }
  const drift = dirtyDriftPaths(a.preDirtySet, a.postDirtySet);
  if (drift.length) return hold('dirty-drift', drift.join(', '));
  return { action: 'release', head, rolledTable };
}

// ---- the wave driver ----

function defaultWaveSpawnRunner(spec, ctx) {
  const spawnrun = require('./spawnrun.cjs');
  if (!Array.isArray(spec.argv) || spec.argv.length === 0) {
    return Promise.resolve({ status: null, stdout: '', stderr: '', error: new Error('no spawn argv composed') });
  }
  return spawnrun.spawnRun(spec, {
    idleMs: ctx && ctx.idleMs,
    wallMs: ctx && ctx.wallMs,
    deny: Array.isArray(spec.deny) ? spec.deny : undefined,
    ackTick: ctx && typeof ctx.ackTick === 'function' ? ctx.ackTick : undefined,
  });
}

function validateWaveCtx(snapshot, ctx) {
  const groups = waveGroupsOf(snapshot);
  if (!groups.ok) return { ok: false, status: 'refused', reason: groups.reason, detail: groups.detail, guidance: groups.guidance, waves: [] };
  if (!ctx || typeof ctx.rootDir !== 'string' || !ctx.rootDir) {
    return { ok: false, status: 'refused', reason: 'invalid-root', detail: 'ctx.rootDir required', waves: [] };
  }
  if (typeof ctx.taskId !== 'string' || !RUNTAG_RE.test(ctx.taskId)) {
    return { ok: false, status: 'refused', reason: 'invalid-task-id', detail: 'ctx.taskId must be filename-safe', waves: [] };
  }
  if (typeof ctx.workBranch !== 'string' || !ctx.workBranch || /\s/.test(ctx.workBranch)) {
    return { ok: false, status: 'refused', reason: 'invalid-branch', detail: 'ctx.workBranch must be a branch name without whitespace', waves: [] };
  }
  return { ok: true, groups: groups.groups };
}

// Entry-time frozen verification: the world the driver is about to iterate
// must already match the frozen snapshot — drift here is external mutation,
// never wave-attributed. Returns null or the paused result.
function entryFrozenProblem(snapshot, ctx, rootDir, git) {
  const stateNow = readStateJson(rootDir);
  if (stateNow == null) {
    return { ok: false, status: 'paused', paused: true, reason: 'state-unreadable', detail: '.gos/state.json missing or unparsable', waves: [] };
  }
  const fr = frozenDrift(snapshot, rootDir, stateNow);
  if (fr) {
    return { ok: false, status: 'paused', paused: true, reason: 'external-mutation', detail: fr, waves: [] };
  }
  const store = storeOf();
  const stampRead = store.readDispatchTableStamp(rootDir);
  if (!stampRead.ok) return { ...stampRead, waves: [] };
  if (stampRead.stamp != null) {
    const tableFile = typeof ctx.tablePath === 'string' && ctx.tablePath ? ctx.tablePath : path.join(rootDir, DISPATCH_TABLE_REL);
    const sha = sha256FileSyncSafe(tableFile);
    if (sha == null || sha !== stampRead.stamp.sha256) {
      return {
        ok: false, status: 'paused', paused: true, reason: 'external-mutation',
        detail: `dispatch table drifted from the store stamp (stamp ${stampRead.stamp.sha256.slice(0, 10)})`, waves: [],
      };
    }
  }
  if (ctx.pin) {
    const pv = verifyPin(ctx.pin, { rootDir, gitRunner: git });
    if (!pv.ok) {
      return { ok: false, status: 'paused', paused: true, reason: 'external-mutation', detail: `pinned worktree drifted: ${pv.detail || pv.reason}`, waves: [] };
    }
  }
  return null;
}

// Release-check-lite for a wave whose completion record already exists:
// the recorded head must still resolve and (non-noop) still touch only the
// wave's declared files. Returns null or the unattributable detail.
function completedWaveProblem(rec, declaredSet, git, rootDir) {
  if (rec.noop === true) {
    try {
      const r = git(['rev-parse', `${rec.head}^{commit}`], rootDir);
      if (r && r.status === 0) return null;
    } catch { /* fall through */ }
    return `recorded no-op head ${rec.head} no longer resolves`;
  }
  try {
    const ok = git(['rev-parse', `${rec.head}^{commit}`], rootDir);
    if (!ok || ok.status !== 0) return `recorded head ${rec.head} no longer resolves`;
    const df = git(['diff', '--name-only', `${rec.head}^`, rec.head], rootDir);
    if (!df || df.status !== 0) return `recorded head ${rec.head} diff unreadable`;
    const changed = String(df.stdout || '').split('\n').map((s) => s.trim()).filter(Boolean);
    const undeclared = changed.filter((p) => !declaredSet.has(p));
    if (undeclared.length) return `recorded head touches undeclared paths: ${undeclared.join(', ')}`;
    return null;
  } catch (e) { return e.message; }
}

// runWaveDispatch(snapshot, ctx) — sequential wave iterator over the frozen
// plan snapshot. ctx:
//   rootDir      repo root (required; git/store/scratch derive from it)
//   taskId       GOS task id (required, filename-safe; record keys, spawn ids)
//   workBranch   branch the waves commit on (required; the only ref allowed
//                to move is its tip)
//   spawnRunner  (spec, {wallMs, idleMs}) -> spawnSync shape (injectable)
//   gitRunner    (args, cwd) -> spawnSync shape (injectable)
//   env/engineProbe/host  compose inputs (host adapter name, default opencode)
//   breaker      breaker instance (default: one from the store limits; an
//                injected breaker must be rooted at the same repo's store —
//                the budget layer reads its mirrors from there)
//   limits       breaker limits override when no breaker is passed
//   pin          {runTag, rootDir} pinned worktree re-verified after waves
//   tablePath    dispatch table file for stamp checks (default
//                <rootDir>/templates/auto-dispatch.json)
//   wallMs/idleMs/now  supervision and clock overrides
//   runTag       spawn-id tag (default: random hex)
async function runWaveDispatch(snapshot, ctx = {}) {
  const valid = validateWaveCtx(snapshot, ctx);
  if (!valid.ok) return valid;
  const rootDir = path.resolve(ctx.rootDir);
  const git = gitRunnerOf(ctx, rootDir);
  const now = typeof ctx.now === 'function' ? ctx.now : Date.now;
  const store = storeOf();
  if (!store) return stepFail('store-unavailable', 'the trust store module could not be loaded');

  const recorded = ensureWavePromptRecorded(rootDir);
  if (!recorded.ok) {
    return { ok: false, status: recorded.status || 'error', reason: recorded.reason, detail: recorded.detail, path: recorded.path, guidance: recorded.guidance, waves: [] };
  }

  let breaker = ctx.breaker || null;
  if (!breaker) {
    const breakerMod = getBreaker();
    const made = breakerMod ? breakerMod.createBreaker({ rootDir, limits: ctx.limits || undefined }) : null;
    if (!made || !made.ok) {
      return { ok: false, status: 'paused', paused: true, reason: 'breaker-unavailable', waves: [] };
    }
    breaker = made.breaker;
  }
  const endWith = (base) => ({ ...base, waves: base.waves || [], breaker: breaker.state() });

  const frozen = entryFrozenProblem(snapshot, ctx, rootDir, git);
  if (frozen) return endWith(frozen);

  const branch = currentBranchOf(git, rootDir);
  if (branch !== ctx.workBranch) {
    return endWith({
      ok: false, status: 'refused', reason: 'wrong-branch',
      detail: `HEAD is ${branch == null ? 'unresolvable' : `'${branch}'`}, expected the work branch '${ctx.workBranch}'`, waves: [],
    });
  }
  if (readHeadOf(git, rootDir) == null) {
    return endWith({ ok: false, status: 'paused', paused: true, reason: 'no-head', waves: [] });
  }

  const tableFile = typeof ctx.tablePath === 'string' && ctx.tablePath ? ctx.tablePath : path.join(rootDir, DISPATCH_TABLE_REL);
  const runTag = typeof ctx.runTag === 'string' && ctx.runTag ? ctx.runTag : crypto.randomBytes(4).toString('hex');
  const results = [];

  for (const g of valid.groups) {
    const key = `${ctx.taskId}/W${g.wave}`;
    const existing = store.readWaveRecords(rootDir);
    if (!existing.ok) return endWith({ ...existing, waves: results });
    const rec = existing.waves[key];
    if (rec) {
      const problem = completedWaveProblem(rec, new Set(g.tasks.flatMap((t) => t.files || [])), git, rootDir);
      if (problem) {
        return endWith({ ok: false, status: 'held', reason: 'completion-unattributable', wave: g.wave, detail: problem, waves: results });
      }
      results.push({ wave: g.wave, status: 'already-released', head: rec.head, noop: rec.noop === true, rolledTable: rec.rolledTable === true });
      continue;
    }

    const breakerMod = getBreaker();
    const label = breakerMod.waveUnitLabel(g.wave);
    const visited = breaker.visit(label);
    if (!visited.ok) return endWith({ ok: false, status: 'paused', paused: true, reason: 'stage-invalid', detail: visited.detail, waves: results });
    if (visited.tripped) return endWith({ ok: false, status: 'paused', paused: true, reason: 'breaker-tripped', trip: breaker.tripped(), wave: g.wave, waves: results });
    const budget = breaker.checkBudget();
    if (!budget.ok) return endWith({ ok: false, status: 'paused', paused: true, reason: budget.reason || 'budget-read-failed', waves: results });
    if (budget.tripped) return endWith({ ok: false, status: 'paused', paused: true, reason: 'breaker-tripped', trip: breaker.tripped(), wave: g.wave, waves: results });

    const render = renderWavePrompt({ wave: g.wave, taskIds: g.tasks.map((t) => t.id) });
    if (!render.ok) return endWith({ ok: false, status: 'paused', paused: true, reason: render.reason, detail: render.detail, wave: g.wave, waves: results });

    const declaredSet = new Set(g.tasks.flatMap((t) => t.files || []));
    const spawnId = `${ctx.taskId}-W${g.wave}-${runTag}`;
    const waveResult = { wave: g.wave, spawnId, prompt: render.prompt, unitLabel: label };

    const reg = store.registerSpawn({ spawnId, kind: 'work', stage: WAVE_STAGE, wallMs: ctx.wallMs }, rootDir);
    if (!reg.ok) {
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'spawn-register-failed', detail: reg.detail, wave: g.wave, waves: results });
    }
    const teardown = () => store.removeSpawn(spawnId, rootDir);
    const failHold = async (violation, detail) => {
      // The held record lands FIRST, store-side: without it a held wave is
      // indistinguishable from a crashed one and reconcile could adopt its
      // commit. The spawn then tears down — no crash-shaped evidence stays.
      const held = store.recordHeldWave(rootDir, { task: ctx.taskId, wave: g.wave, reason: violation, spawnId });
      if (!held.ok) {
        teardown();
        return endWith({ ok: false, status: 'paused', paused: true, reason: held.reason || 'held-record-failed', detail: held.detail, wave: g.wave, waves: results });
      }
      teardown();
      waveResult.status = 'held';
      waveResult.violation = violation;
      waveResult.detail = detail;
      waveResult.signal = 'task-failed';
      results.push(waveResult);
      const res = breaker.recordOutcome(WAVE_STAGE, 'task-failed', `${violation}: ${detail}`);
      if (res.tripped) {
        return endWith({ ok: false, status: 'paused', paused: true, reason: 'breaker-tripped', trip: breaker.tripped(), wave: g.wave, waves: results });
      }
      return endWith({ ok: false, status: 'held', reason: violation, wave: g.wave, waves: results });
    };

    const manifest = store.writeGrantManifest(rootDir, spawnId);
    if (!manifest.ok) {
      teardown();
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'grant-manifest-failed', detail: manifest.detail, wave: g.wave, waves: results });
    }
    const composed = launcher.compose(pinnedProfile(WAVE_STAGE), {
      workspace: rootDir,
      env: ctx.env || process.env,
      engineProbe: ctx.engineProbe,
      store,
      writableRoots: ctx.writableRoots || [rootDir, path.join(rootDir, '.gos'), path.join(rootDir, '.gos', 'logs')],
      scratchDir: reg.scratch,
      ackDir: reg.acksDir,
      testBase: true,
      grantManifestPath: manifest.path,
    });
    if (!composed.ok) {
      teardown();
      const res = breaker.recordOutcome(WAVE_STAGE, 'spawn-error', `launcher ${composed.code}`);
      if (res.tripped) return endWith({ ok: false, status: 'paused', paused: true, reason: 'breaker-tripped', trip: breaker.tripped(), wave: g.wave, waves: results });
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'compose-failed', code: composed.code, wave: g.wave, waves: results });
    }
    const adapter = registry.requireAdapter(typeof ctx.host === 'string' && ctx.host ? ctx.host : 'opencode');
    if (!adapter || typeof adapter.buildSpawnSpec !== 'function') {
      teardown();
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'host-adapter-unavailable', wave: g.wave, waves: results });
    }
    const loop = getLoop();
    if (!loop) {
      teardown();
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'loop-module-unavailable', wave: g.wave, waves: results });
    }
    // The adapter env overlay is a sanitized copy: credential-class entries
    // (GH_TOKEN, AWS secrets, ...) must never ride a wave spawn even when
    // the loop env carries them. The adapter sanitizes only its base
    // (process.env), so the overlay sanitizes here.
    const baselineEnvName = typeof ctx.approvalsBaselineEnv === 'string' && ctx.approvalsBaselineEnv
      ? ctx.approvalsBaselineEnv : null;
    const baselineSha = ctx.approvalsBaseline != null ? String(ctx.approvalsBaseline) : null;
    const adapterSpec = adapter.buildSpawnSpec({
      prompt: render.prompt,
      env: loop.spawnEnvTemplate(registry.sanitizedSpawnEnv(ctx.env === process.env ? {} : (ctx.env || {}))),
      cwd: rootDir,
    });
    const argv = composed.tier === 'bubblewrap'
      ? [composed.engine, ...composed.argv, '--', ...adapterSpec.argv]
      : adapterSpec.argv.slice();
    const spec = {
      argv,
      env: {
        ...adapterSpec.env,
        ...composed.env,
        [loop.SPAWN_MARKER_ENV]: '1',
        GOS_AUTO_SPAWN_ID: spawnId,
        ...(baselineEnvName && baselineSha != null ? { [baselineEnvName]: baselineSha } : {}),
      },
      cwd: adapterSpec.cwd || rootDir,
      prompt: render.prompt,
      stage: WAVE_STAGE,
      spawnId,
      wave: g.wave,
      unitLabel: label,
      tier: composed.tier,
      profile: composed.profile,
      deny: composed.deny.slice(),
      scratch: reg.scratch,
      declaredFiles: [...declaredSet],
      roWorkspace: false,
    };

    const preHead = readHeadOf(git, rootDir);
    if (preHead == null) {
      teardown();
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'no-head', wave: g.wave, waves: results });
    }
    const preRefs = refsSnapshotOf(git, rootDir);
    if (preRefs == null) {
      teardown();
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'refs-unreadable', wave: g.wave, waves: results });
    }
    const preDirty = statusPathsOf(git, rootDir);
    if (preDirty == null) {
      teardown();
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'status-unreadable', wave: g.wave, waves: results });
    }
    // Pre-spawn evidence lands store-side (runner-written before the
    // spawn): crash recovery reconciles from this record and never reads
    // attribution evidence out of the spawn-writable scratch.
    const startRec = store.recordWaveStart(rootDir, {
      task: ctx.taskId, wave: g.wave, spawnId,
      preHead, preRefsText: preRefs.text, preDirty: [...preDirty],
    });
    if (!startRec.ok) {
      teardown();
      return endWith({ ok: false, status: 'paused', paused: true, reason: startRec.reason || 'wave-start-record-failed', detail: startRec.detail, wave: g.wave, waves: results });
    }

    let result;
    try {
      result = await (ctx.spawnRunner || defaultWaveSpawnRunner)(spec, { wallMs: ctx.wallMs, idleMs: ctx.idleMs, ackTick: () => store.serviceRequests(rootDir, spawnId) });
    } catch (e) {
      result = { status: null, stdout: '', stderr: '', error: e instanceof Error ? e : new Error(String(e)) };
    }
    if (result == null) result = { status: null, stdout: '', stderr: '' };

    // session accounting before any consumer reads the pairing
    const bumped = store.bumpSpawn(rootDir);
    if (!bumped.ok) return endWith({ ok: false, status: 'paused', paused: true, reason: 'budget-write-failed', path: bumped.path, wave: g.wave, waves: results });
    const streamText = String(result.stdout || '');
    // Escape detector: pre-truncation streaming hits win (a huge benign tail
    // cannot push deny lines out of the captured window); the post-hoc scan
    // stays as the floor. The same hits stamp the telemetry — one
    // computation, the stamp and the scorer both read it.
    const hits = (result && Array.isArray(result.preTruncationDenyHits) && result.preTruncationDenyHits.length)
      ? result.preTruncationDenyHits
      : launcher.scanSpawnOutput(streamText, { deny: spec.deny });
    const stamp = store.stampStream(spawnId, WAVE_STAGE, sha256Text(streamText), new Date(now()).toISOString(), rootDir, { denyHits: hits.length });
    if (!stamp.ok) return endWith({ ok: false, status: 'paused', paused: true, reason: 'stamp-failed', detail: stamp.reason, wave: g.wave, waves: results });
    if (result && result.windowHead && result.windowTail) {
      try {
        store.saveWindows(spawnId, { head: result.windowHead.stdout, tail: result.windowTail.stdout }, rootDir);
      } catch { /* advisory capture: a failed sidecar never blocks the run */ }
    }

    // process contract: deny hits 0, the spawn itself must not have failed
    const runnerFailed = !!(result.error != null || (result.status != null && result.status !== 0));
    if (hits.length || runnerFailed) {
      const violation = hits.length ? 'deny-hit' : 'spawn-failed';
      const detail = hits.length
        ? hits.map((h) => `deny '${h.pattern}': ${h.line.slice(0, 120)}`).join('; ')
        : String((result.error && result.error.message) || result.stderr || 'spawn failed').slice(0, 240);
      return failHold(violation, detail);
    }

    const postHead = readHeadOf(git, rootDir);
    const postRefs = refsSnapshotOf(git, rootDir);
    const postDirty = statusPathsOf(git, rootDir);
    if (postHead == null || postRefs == null || postDirty == null) {
      return endWith({ ok: false, status: 'paused', paused: true, reason: 'post-wave-unreadable', wave: g.wave, waves: results });
    }

    const verdict = await evaluateWaveOutput({
      task: ctx.taskId,
      wave: g.wave,
      spawnId,
      declaredSet,
      workBranch: ctx.workBranch,
      rootDir,
      gitRunner: git,
      tableFile,
      preHead,
      preRefsMap: preRefs.map,
      preDirtySet: preDirty,
      postHead,
      postRefs,
      postDirtySet: postDirty,
      scratch: reg.scratch,
      snapshot,
      ctx: { ...ctx, rootDir },
    });
    if (verdict.action === 'hold') return failHold(verdict.violation, verdict.detail);
    if (verdict.action === 'pause') {
      return endWith({ ok: false, status: 'paused', paused: true, reason: verdict.reason, detail: verdict.detail, wave: g.wave, waves: results });
    }
    if (verdict.action === 'release-noop') {
      const recW = store.recordWaveCompletion(rootDir, {
        task: ctx.taskId, wave: g.wave, head: preHead,
        refsPointer: sha256Text(postRefs.text), noop: true, noopReason: verdict.noopReason,
      });
      if (!recW.ok) return endWith({ ok: false, status: 'paused', paused: true, reason: recW.reason, detail: recW.detail, wave: g.wave, waves: results });
      breaker.recordSuccess(WAVE_STAGE);
      teardown();
      results.push({ ...waveResult, status: 'skipped-noop', noop: true, noopReason: verdict.noopReason, head: preHead });
      continue;
    }
    const recW = store.recordWaveCompletion(rootDir, {
      task: ctx.taskId, wave: g.wave, head: verdict.head,
      refsPointer: sha256Text(postRefs.text), rolledTable: verdict.rolledTable === true,
    });
    if (!recW.ok) return endWith({ ok: false, status: 'paused', paused: true, reason: recW.reason, detail: recW.detail, wave: g.wave, waves: results });
    breaker.recordSuccess(WAVE_STAGE);
    teardown();
    results.push({ ...waveResult, status: 'released', head: verdict.head, rolledTable: verdict.rolledTable === true || undefined });
  }
  return endWith({ ok: true, status: 'complete', waves: results });
}

// reconcileWaves(snapshot, ctx) — crash recovery. Never spawns: a wave with
// a completion record re-runs only its release check; a wave with a held
// record is a runner verdict — reported held, never adopted; a wave with a
// store-side start record (and no verdict) reconciles its pre-crash refs
// range — a commit uniquely attributable to the wave is adopted (record
// written from it, release check re-run), with attribution evidence read
// ONLY from the store record, never from the spawn-writable scratch; waves
// without a start record are not-started. Same ctx as runWaveDispatch.
async function reconcileWaves(snapshot, ctx = {}) {
  const valid = validateWaveCtx(snapshot, ctx);
  if (!valid.ok) return valid;
  const rootDir = path.resolve(ctx.rootDir);
  const git = gitRunnerOf(ctx, rootDir);
  const store = storeOf();
  if (!store) return stepFail('store-unavailable', 'the trust store module could not be loaded');
  const records = store.readWaveRecords(rootDir);
  if (!records.ok) return { ...records, waves: [] };
  const heldRead = store.readHeldWaves(rootDir);
  if (!heldRead.ok) return { ...heldRead, waves: [] };
  const startsRead = store.readWaveStarts(rootDir);
  if (!startsRead.ok) return { ...startsRead, waves: [] };
  const stampLoad = store.load(rootDir);
  const stamps = stampLoad.ok && stampLoad.store && typeof stampLoad.store.stamps === 'object' && stampLoad.store.stamps != null ? stampLoad.store.stamps : {};
  const spawnreg = require('../../core/spawnreg.cjs');
  const tableFile = typeof ctx.tablePath === 'string' && ctx.tablePath ? ctx.tablePath : path.join(rootDir, DISPATCH_TABLE_REL);
  const results = [];
  let ok = true;
  for (const g of valid.groups) {
    const key = `${ctx.taskId}/W${g.wave}`;
    const rec = records.waves[key];
    const declaredSet = new Set(g.tasks.flatMap((t) => t.files || []));
    if (rec) {
      const problem = completedWaveProblem(rec, declaredSet, git, rootDir);
      if (problem) {
        ok = false;
        results.push({ wave: g.wave, action: 'unattributable', detail: problem });
        continue;
      }
      results.push({ wave: g.wave, action: 'release-checked', head: rec.head, noop: rec.noop === true });
      continue;
    }
    // A held record is a runner verdict, not a crash: never adopted, never
    // re-spawned here.
    const held = heldRead.heldWaves[key];
    if (held) {
      ok = false;
      results.push({ wave: g.wave, action: 'held', reason: held.reason, spawnId: held.spawnId, heldAtIso: held.heldAtIso });
      continue;
    }
    const start = startsRead.waveStarts[key];
    if (!start) {
      results.push({ wave: g.wave, action: 'not-started' });
      continue;
    }
    // Deny gate: a crashed spawn whose stamped stream carries deny hits can
    // never have its commit adopted, however attributable it looks.
    const startStamp = stamps[start.spawnId];
    if (startStamp && Number(startStamp.denyHits) > 0) {
      ok = false;
      results.push({
        wave: g.wave, action: 'unattributable', violation: 'deny-hit',
        detail: `the crashed wave spawn's stream stamped ${startStamp.denyHits} deny hit(s) — its commit is never adopted`,
      });
      continue;
    }
    const postHead = readHeadOf(git, rootDir);
    const postRefs = refsSnapshotOf(git, rootDir);
    const postDirty = statusPathsOf(git, rootDir);
    if (postHead == null || postRefs == null || postDirty == null) {
      ok = false;
      results.push({ wave: g.wave, action: 'unresolvable', reason: 'post-crash evidence unreadable' });
      continue;
    }
    const verdict = await evaluateWaveOutput({
      task: ctx.taskId,
      wave: g.wave,
      spawnId: start.spawnId,
      declaredSet,
      workBranch: ctx.workBranch,
      rootDir,
      gitRunner: git,
      tableFile,
      preHead: start.preHead,
      preRefsMap: refsMapFromText(start.preRefsText),
      preDirtySet: new Set(start.preDirty || []),
      postHead,
      postRefs,
      postDirtySet: postDirty,
      scratch: spawnreg.scratchPath(rootDir, start.spawnId),
      snapshot,
      ctx: { ...ctx, rootDir },
    });
    if (verdict.action === 'release' || verdict.action === 'release-noop') {
      const recW = verdict.action === 'release'
        ? store.recordWaveCompletion(rootDir, {
          task: ctx.taskId, wave: g.wave, head: verdict.head,
          refsPointer: sha256Text(postRefs.text), rolledTable: verdict.rolledTable === true,
        })
        : store.recordWaveCompletion(rootDir, {
          task: ctx.taskId, wave: g.wave, head: start.preHead,
          refsPointer: sha256Text(postRefs.text), noop: true, noopReason: verdict.noopReason,
        });
      if (!recW.ok) {
        ok = false;
        results.push({ wave: g.wave, action: 'record-failed', reason: recW.reason, detail: recW.detail });
        continue;
      }
      store.removeSpawn(start.spawnId, rootDir);
      results.push(verdict.action === 'release'
        ? { wave: g.wave, action: 'adopted', head: verdict.head, rolledTable: verdict.rolledTable === true || undefined }
        : { wave: g.wave, action: 'adopted-noop', noop: true, noopReason: verdict.noopReason });
      continue;
    }
    ok = false;
    if (verdict.action === 'hold') {
      results.push({ wave: g.wave, action: 'unattributable', violation: verdict.violation, detail: verdict.detail });
    } else {
      results.push({ wave: g.wave, action: 'unresolvable', reason: verdict.reason, detail: verdict.detail });
    }
  }
  return { ok, status: ok ? 'reconciled' : 'held', waves: results };
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
  verifyPin,
  WAVE_PROMPT_KIND,
  WAVE_PROMPT_TEMPLATE,
  WAVE_PROMPT_TOKENS,
  WAVE_MARKER_NAME,
  WAVE_NOOP_NAME,
  DISPATCH_TABLE_REL,
  isRunnerCriticalPath,
  wavePromptSourceHash,
  renderWavePrompt,
  ensureWavePromptRecorded,
  runWaveDispatch,
  reconcileWaves,
};
