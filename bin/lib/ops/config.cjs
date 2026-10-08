// ops/config — placement per aspect-rosters-v2.json
'use strict';

const core = require('../core/index.cjs');
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

// plan tasks source for semantic checks: plan_snapshot (T2 frozen at commit plan)
// first; absent → live task.parsePlanMd() fallback [B-2 source-of-truth rule]. null = no plan.

// ① B-2 bidirectional: plan Covers ∪D-NN == state.decisions ids EXACT (both directions);

function loadConfig() {
  if (!fs.existsSync(CONFIG_PATH)) return { model_profile: 'team', models: {} };
  try { return { model_profile: 'team', models: {}, ...JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8')) }; }
  catch { return { model_profile: 'team', models: {} }; }
}

function saveConfig(cfg) {
  core.writeAtomicJson(CONFIG_PATH, cfg); // REVIEW F-4 (D-18): ALL json writes atomic — config included
}

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
    core.die('Usage: gos config models [show | profile <name> | set <agent> <model>]');
  }
  console.log('Usage: gos config models [show | profile <name> | set <agent> <model>]');
}

module.exports = { MODEL_NAME_RE, SEMANTIC_RUNTIME, loadConfig, saveConfig, resolveSemanticTier, probeModels, cmdResolveModel, cmdConfig };
