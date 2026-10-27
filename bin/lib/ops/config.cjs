// ops/config — placement per aspect-rosters-v2.json
'use strict';

const core = require('../core/index.cjs');
const clcore = require('./changelog-core.cjs');
const fs = require('fs');
const path = require('path');
const os = require('os');

// Model-tier mapping per staffing profile for each semantic agent role.
const MODEL_PROFILES = Object.freeze({
  'think-redteam':   { solo: 'inherit',  team: 'strong',    elite: 'strong',    lean: 'current' },
  'planner':         { solo: 'inherit',  team: 'strong',    elite: 'strong',    lean: 'current' },
  'implementer':     { solo: 'inherit',  team: 'current',   elite: 'strong',    lean: 'fast' },
  'checker':         { solo: 'inherit',  team: 'different', elite: 'strong',    lean: 'fast' },
  'researcher':      { solo: 'inherit',  team: 'current',   elite: 'strong',    lean: 'fast' },
  'code-reviewer':   { solo: 'inherit',  team: 'strong',    elite: 'strong',    lean: 'current' },
});

const VALID_PROFILES = Object.freeze(['team', 'solo', 'elite', 'lean']);

const MODEL_NAME_RE = /^[a-zA-Z0-9._/-]+$/; // F-2 whitelist

const CONFIG_PATH = path.join(core.GOS_DIR, 'config.json');

// two-layer system: GLOBAL layer (~/.config/gos/config.json — physical
// path pinned, precedent i18n.cjs/persistLocale) is the seeded base; PROJECT
// layer (.gos/config.json, tracked) overrides per-repo. Merge: scalars
// project-wins; DEEP_MERGE_KEYS merge per sub-key so a project {checker} pin
// never erases a global {thinker} pin.
function globalConfigFile() { return path.join(os.homedir(), '.config', 'gos', 'config.json'); }

const DEEP_MERGE_KEYS = Object.freeze(['models']);
const SENTINEL_KEY = 'lessons_migrated'; // deleted outright (D-09) — legacy key only ever stripped

// Corrupt layer → rename <path>.corrupt-<ts> + self-describing die — never a
// silent fallback to defaults (the next save would overwrite recoverable
// content). A MISSING layer is a legal empty base and returns {}.
function quarantineCorrupt(p, layer, why) {
  const to = `${p}.corrupt-${Date.now()}`;
  try { fs.renameSync(p, to); }
  catch (e) { core.die(`config: ${layer} layer (${p}) is corrupt (${why}) AND quarantine failed (${e.message}) — fix the file manually, then re-run`); }
  core.die(`config: ${layer} layer is corrupt (${why}) — moved to ${to}; fix it (project layer: git restore ${path.relative(process.cwd(), p) || p}) or delete it deliberately, then re-run. Refusing to fall back to defaults silently.`);
}

function readLayer(p, layer) {
  if (!fs.existsSync(p)) return {};
  let raw;
  try { raw = fs.readFileSync(p, 'utf8'); }
  catch (e) { quarantineCorrupt(p, layer, `unreadable: ${e.message}`); }
  let obj;
  try { obj = JSON.parse(raw); }
  catch (e) { quarantineCorrupt(p, layer, `JSON parse failed: ${e.message}`); }
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) quarantineCorrupt(p, layer, 'not a JSON object');
  return obj;
}

function plainObject(v) {
  return v && typeof v === 'object' && !Array.isArray(v) ? v : {};
}

function loadConfig() {
  const g = readLayer(globalConfigFile(), 'global');
  const p = readLayer(CONFIG_PATH, 'project');
  const merged = { model_profile: 'team', models: {}, ...g, ...p }; // scalars: project wins
  for (const k of DEEP_MERGE_KEYS) {
    merged[k] = { ...plainObject(g[k]), ...plainObject(p[k]) }; // per-key deep merge
  }
  return merged;
}

// One-time lessons_migrated strip for a layer ( R2-6iii). Surgical: the
// layer file is re-read fresh and only the sentinel key is removed, so a
// concurrent `config models set` update to the other layer is never lost
// (the strip lives ONLY inside this single locked write path;
// loadConfig never writes).
function stripSentinelFromLayer(p, layerObj, layer) {
  if (!layerObj || layerObj[SENTINEL_KEY] === undefined) return false;
  const next = { ...layerObj };
  delete next[SENTINEL_KEY];
  core.writeAtomicJson(p, next);
  console.error(`⚠ config: removed obsolete '${SENTINEL_KEY}' key from ${layer} config (${p}) — one-time self-heal (D-09)`);
  return true;
}

// Layer-separating project write: a value equal to the global base is not
// re-pinned into the tracked project layer (machine-local choices never leak
// into the repo file); models separate per agent key. The sentinel key is
// never persisted — the project-side strip is implicit in this view.
function projectWriteView(cfg, g) {
  const out = {};
  const src = plainObject(cfg);
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  for (const k of Object.keys(src)) {
    if (k === SENTINEL_KEY) continue;
    if (k === 'models') {
      const own = {};
      const gm = plainObject(g.models);
      for (const a of Object.keys(plainObject(src.models))) {
        if (!Object.prototype.hasOwnProperty.call(gm, a) || src.models[a] !== gm[a]) own[a] = src.models[a];
      }
      if (Object.keys(own).length) out.models = own;
      continue;
    }
    if (Object.prototype.hasOwnProperty.call(g, k) && same(src[k], g[k])) continue; // base already provides it
    out[k] = src[k];
  }
  return out;
}

function saveConfig(cfg) {
  const gPath = globalConfigFile();
  const g = readLayer(gPath, 'global'); // corrupt global fails closed on the write path too
  stripSentinelFromLayer(gPath, g, 'global');
  const pRaw = readLayer(CONFIG_PATH, 'project');
  const out = projectWriteView(cfg, g);
  core.writeAtomicJson(CONFIG_PATH, out); // REVIEW F-4 (D-18): ALL json writes atomic — config included
  if (pRaw[SENTINEL_KEY] !== undefined) {
    console.error(`⚠ config: removed obsolete '${SENTINEL_KEY}' key from project config (${CONFIG_PATH}) — one-time self-heal (D-09)`);
  }
}

const SEMANTIC_RUNTIME_BASE = {
  skipNotGit: 'semantic diff skip: not a git repo — diff-hit check unavailable here',
  skipNoPlan: 'semantic skip: plan.md missing (Lv0/1) — coverage/diff checks skipped',
  skipShallow: 'semantic diff skip: shallow repo + task_head unreachable — unshallow or re-claim',
  skipPending: 'semantic diff skip: task_head_pending (zero-commit at init) — auto-anchor lands with commit embed',
  noHeadFail: 'git repo but task_head empty and not pending — diff baseline lost (re-init or re-claim)',
  noFilesWarn: 'no Files declared — diff-hit check skipped for this task (warn only)',
  tooBroad: 'pattern too broad',
  untrustedNote: 'untrusted historical notes — verify before acting', // B-16 header line [R1-F8]
};

// Runtime strings merge into the frozen CONTRACTS.semantic_checks table at require time.
Object.assign(core.CONTRACTS.semantic_checks, SEMANTIC_RUNTIME_BASE);

const SEMANTIC_RUNTIME = core.CONTRACTS.semantic_checks;

// plan tasks source for semantic checks: plan_snapshot ( frozen at commit plan)
// first; absent → live task.parsePlanMd() fallback [B-2 source-of-truth rule]. null = no plan.

// ① bidirectional: plan Covers ∪D-NN == state.decisions ids EXACT (both directions);

function resolveSemanticTier(tier) {
  if (tier === 'inherit' || tier === 'current') return { model: 'inherit' };
  const probed = probeModels();
  if (!probed || !probed.strong || !probed.fast) {
    return { model: 'inherit', hint: 'semantic-tier probe failed — falling back to inherit' };
  }
  if (tier === 'strong') return { model: probed.strong };
  if (tier === 'fast') return { model: probed.fast };
  if (tier === 'different') {
    const session = probed.session || '';
    const candidates = [probed.strong, probed.fast].filter(m => m && m !== session);
    if (!candidates.length) return { model: 'inherit', hint: 'no different model available — inherit' };
    return { model: candidates[0] };
  }
  return { model: 'inherit' };
}

function probeModels() {
  const cfgPaths = [
    process.env.OPENCODE_CONFIG_DIR ? path.join(process.env.OPENCODE_CONFIG_DIR, 'opencode.json') : null,
    path.join(os.homedir(), '.config/opencode/opencode.json'),
  ].filter(Boolean);
  let raw = null;
  for (const p of cfgPaths) {
    try { raw = JSON.parse(fs.readFileSync(p, 'utf8')); break; } catch { /* next */ }
  }
  if (!raw || !raw.provider) return null;
  const all = [];
  for (const [prov, def] of Object.entries(raw.provider)) {
    for (const m of Object.keys(def.models || {})) all.push(`${prov}/${m}`);
  }
  if (!all.length) return null;
  // Heuristics: strong = matches 5.x/opus/max/pro/large/latest-ish; fast = flash/mini/haiku/small/lite
  const strong = all.find(m => /(5\.[0-9]|4\.[7-9]|[0-9]+\.5|opus|max|pro|large)/i.test(m) && !/flash|mini|lite/i.test(m))
    || all.find(m => !/flash|mini|lite|haiku|small/i.test(m));
  const fast = all.find(m => /(flash|mini|lite|haiku|small)/i.test(m)) || all[all.length - 1];
  return { all, strong, fast, session: null };
}

function cmdResolveModel(args) {
  const agent = (args[0] || '').toLowerCase();
  if (!agent || !MODEL_PROFILES[agent]) {
    console.log('Usage: gos resolve-model <agent>');
    console.log('Agents: ' + Object.keys(MODEL_PROFILES).join(', '));
    console.log('Dispatch rule: if result is "inherit", OMIT the model parameter (do not pass the literal).');
    return;
  }
  const cfg = loadConfig();
  const profile = cfg.model_profile || 'team';
  const override = (cfg.models || {})[agent];
  if (override && MODEL_NAME_RE.test(override)) {
    console.log(JSON.stringify({ agent, profile, tier: 'pinned', model: override }));
    return;
  }
  const tier = MODEL_PROFILES[agent][profile] || 'inherit';
  const r = resolveSemanticTier(tier);
  console.log(JSON.stringify({ agent, profile, tier, model: r.model, ...(r.hint ? { hint: r.hint } : {}) }));
  if (r.hint) console.error(`hint: ${r.hint}`);
}

// `gos config changelog-path <rel>` — : record the changelog location
// in the PROJECT layer (tracked, clone-consistent) and move any existing file
// there atomically. Lock order pinned .gos/.lock (held by write-class dispatch
// since guardCwd) → changelog.lock, both held across the whole mv+save so a
// concurrent `changelog add` can never rebuild the old path mid-move (R2-4).
// mv three-state idempotency: same-path = no-op; source AND target both exist
// = die (no overwrite — .git/index-shaped targets die in validation anyway);
// target exists but is not a regular file = die; parent dirs mkdir -p; EXDEV
// dies naming EXDEV (no silent copy+delete).
function cmdConfigChangelogPath(rest, cfg) {
  if (rest.length !== 1 || !String(rest[0] || '').trim()) {
    core.die('Usage: gos config changelog-path <repo-relative .md path>  (e.g. docs/CHANGELOG.md)');
  }
  const root = clcore.changelogProjectRoot();
  const v = clcore.validateChangelogRelPath(rest[0], root);
  if (!v.ok) core.die(`config: changelog-path '${rest[0]}' rejected — ${v.reason}`);
  clcore.acquireChangelogLock();
  try {
    const currentAbs = clcore.resolveChangelogMd();
    const currentRel = path.relative(root, currentAbs).split(path.sep).join('/');
    if (currentAbs === v.abs) {
      console.log(`✓ changelog-path already ${v.rel} — nothing to do`);
      return;
    }
    let srcStat = null;
    try { srcStat = fs.statSync(currentAbs); } catch { /* absent: no file to move */ }
    let dstStat = null;
    try { dstStat = fs.lstatSync(v.abs); } catch { /* absent: free target */ }
    if (dstStat !== null && !dstStat.isFile()) {
      core.die(`config: changelog-path target ${v.rel} exists but is not a regular file (${dstStat.isDirectory() ? 'directory' : 'symlink or other'}) — refusing; resolve it manually, then re-run`);
    }
    if (srcStat !== null && dstStat !== null) {
      core.die(`config: both ${currentRel} and ${v.rel} exist — refusing to overwrite; move or delete one deliberately, then re-run`);
    }
    if (srcStat !== null) {
      fs.mkdirSync(path.dirname(v.abs), { recursive: true });
      try {
        fs.renameSync(currentAbs, v.abs);
      } catch (e) {
        if (e.code === 'EXDEV') {
          core.die(`config: moving ${currentRel} → ${v.rel} crosses a filesystem boundary (EXDEV) — no silent copy+delete; relocate the file manually, then re-run to record the path`);
        }
        core.die(`config: moving ${currentRel} → ${v.rel} failed (${e.message})`);
      }
      cfg.changelog_path = v.rel;
      saveConfig(cfg);
      console.log(`✓ changelog moved atomically: ${currentRel} → ${v.rel} (changelog_path recorded in the project layer)`);
      console.log('⚠ git records the relocation only at your next commit (old path deleted + new path untracked until then)');
      return;
    }
    cfg.changelog_path = v.rel;
    saveConfig(cfg);
    if (dstStat !== null) {
      console.log(`✓ changelog-path = ${v.rel} (existing file adopted; nothing moved)`);
    } else {
      console.log(`✓ changelog-path = ${v.rel} (no changelog at ${currentRel} — the next 'gos changelog add' bootstraps at the new path)`);
    }
  } finally {
    clcore.releaseChangelogLock();
  }
}

function cmdConfig(args) {
  const sub = (args[0] || '').toLowerCase();
  const cfg = loadConfig();
  if (sub === 'models') {
    const action = args[1] || 'show';
    if (action === 'show') {
      console.log(JSON.stringify({ model_profile: cfg.model_profile, models: cfg.models, valid_profiles: VALID_PROFILES }, null, 2));
      return;
    }
    if (action === 'profile') {
      const p = (args[2] || '').toLowerCase();
      if (!VALID_PROFILES.includes(p)) core.die(`Invalid profile "${p}". Valid: ${VALID_PROFILES.join(', ')}`);
      cfg.model_profile = p;
      saveConfig(cfg);
      console.log(`✓ model_profile = ${p}`);
      console.log('Next: `gos resolve-model <agent>` to see the effect');
      return;
    }
    if (action === 'set') {
      // gos config models set <agent> <model|inherit>
      const agent = (args[2] || '').toLowerCase();
      const model = args[3] || '';
      if (!agent || !MODEL_PROFILES[agent]) core.die(`Unknown agent "${agent}". Agents: ${Object.keys(MODEL_PROFILES).join(', ')}`);
      if (model !== 'inherit' && !MODEL_NAME_RE.test(model)) {
        core.die(`Invalid model name "${model}" (F-2 whitelist: ^[a-zA-Z0-9._/-]+$). Refusing to write config.`);
      }
      cfg.models = cfg.models || {};
      if (model === 'inherit') delete cfg.models[agent];
      else cfg.models[agent] = model;
      saveConfig(cfg);
      console.log(`✓ models.${agent} = ${model === 'inherit' ? '(cleared → profile applies)' : model}`);
      return;
    }
    core.die('Usage: gos config models [show | profile <name> | set <agent> <model>] | gos config changelog-path <repo-relative .md path>');
  }
  if (sub === 'changelog-path') {
    cmdConfigChangelogPath(args.slice(1), cfg);
    return;
  }
  console.log('Usage: gos config models [show | profile <name> | set <agent> <model>] | gos config changelog-path <repo-relative .md path>');
}

module.exports = { MODEL_NAME_RE, SEMANTIC_RUNTIME, loadConfig, saveConfig, resolveSemanticTier, probeModels, cmdResolveModel, cmdConfig };
