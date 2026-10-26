// ops/setup — placement per aspect-rosters-v2.json
'use strict';

const core = require('../core/index.cjs');
const sibConfig = require('./config.cjs');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

// Skills shipped in core.SKILLS_DIR, discovered at require time; doctor consumes this module via sibSetup.
const GOS_SKILL_NAMES = fs.existsSync(core.SKILLS_DIR) ? fs.readdirSync(core.SKILLS_DIR).filter((d) => fs.existsSync(path.join(core.SKILLS_DIR, d, 'SKILL.md'))) : [];

function detectPlatforms(home) {
  return [
    { name: 'opencode', detect: () => fs.existsSync(path.join(home, '.config/opencode')) || !!process.env.OPENCODE_CONFIG_DIR, link: path.join(process.env.OPENCODE_CONFIG_DIR || path.join(home, '.config/opencode'), 'skills', 'gos'), shape: 'parent' },
    // commands layer: /gos-* slash commands (GSD 4th layer)
    { name: 'opencode-commands', detect: () => fs.existsSync(path.join(home, '.config/opencode')) || !!process.env.OPENCODE_CONFIG_DIR, link: path.join(process.env.OPENCODE_CONFIG_DIR || path.join(home, '.config/opencode'), 'commands', 'gos'), shape: 'parent', source: 'commands' },
    { name: 'codex', detect: () => fs.existsSync(path.join(home, '.codex')) || fs.existsSync(path.join(home, '.agents')), link: path.join(home, '.agents', 'skills', 'gos'), shape: 'parent' },
    { name: 'claude', detect: () => fs.existsSync(path.join(home, '.claude')), shape: 'individual', linkDir: path.join(home, '.claude', 'skills') },
  ].filter(p => {
    try { return p.detect(); } catch { return false; }
  });
}

// D-63: locale persistence — project config when a .gos/ exists here, else the
// global config (nearest-wins resolution reads the same two).
function persistLocale(locale) {
  const projCfg = path.join(core.GOS_DIR, 'config.json');
  const useProject = fs.existsSync(core.GOS_DIR);
  const file = useProject ? projCfg : core.globalConfigPath();
  let cfg = {};
  try { cfg = JSON.parse(fs.readFileSync(file, 'utf8')) || {}; } catch { /* fresh */ }
  cfg.locale = locale;
  core.writeAtomicJson(file, cfg);
  return { file, scope: useProject ? 'project config' : 'global config' };
}

// D-63 non-interactive language auto-detect: normalize $LANG, persist silently.
// Never dies (an exotic locale just means "keep default").
function autoPersistDetectedLocale() {
  const n = core.normalizeLocale(process.env.LANG || process.env.LC_ALL);
  if (!n) return null;
  const { file, scope } = persistLocale(n);
  return { locale: n, file, scope };
}

function cmdSetup(args) {
  if (args.includes('--commitlint')) { cmdSetupCommitlint(args); return; }
  // D-63 language step: --lang validates normalized values (en | zh-CN) and
  // persists (project config when inside a repo, else global); invalid → die
  // listing valid values. Non-interactive without --lang = detect LANG env,
  // normalize, persist silently (never die, N8).
  const langIdx = args.indexOf('--lang');
  if (langIdx !== -1) {
    const val = args[langIdx + 1];
    const n = core.normalizeLocale(val);
    if (!n) core.die(`setup --lang: '${val == null ? '' : val}' is not a valid locale (valid: ${core.VALID_LOCALES.join(' | ')})`);
    const { file, scope } = persistLocale(n);
    console.log(`✓ language: ${n} (persisted to ${scope}: ${path.relative(process.cwd(), file)})`);
    console.log('Active for the next command run; override per-run with GOS_LANG.');
    return;
  }
  const localIdx = args.indexOf('--local');
  const localPath = localIdx !== -1 ? (args[localIdx + 1] && !args[localIdx + 1].startsWith('--') ? path.resolve(args[localIdx + 1]) : process.cwd()) : null;
  const skillsSrc = localPath ? path.join(localPath, 'skills') : core.SKILLS_DIR;
  if (!fs.existsSync(skillsSrc)) core.die(`skills not found at ${skillsSrc}`);
  const commandsSrc = localPath ? path.join(localPath, '.opencode', 'commands', 'gos') : path.join(core.GOS_SELF_ROOT, '.opencode', 'commands', 'gos');
  const home = os.homedir();
  const platforms = detectPlatforms(home);
  if (!platforms.length) {
    console.log('No supported AI assistant detected (opencode/codex/claude).');
    console.log('Next: install one of them, or run `gos setup` inside their environment');
    return;
  }
  let installed = 0;
  for (const p of platforms) {
    try {
      if (p.source === 'commands') {
        if (fs.existsSync(commandsSrc)) {
          core.symlinkOrJunction(commandsSrc, p.link, true);
          installed++;
          console.log(`✓ ${p.name}: ${p.link} → ${commandsSrc} (/gos-* commands)`);
        }
      } else if (p.shape === 'parent') {
        core.symlinkOrJunction(skillsSrc, p.link, true);
        installed++;
        console.log(`✓ ${p.name}: ${p.link} → ${skillsSrc}`);
      } else {
        for (const s of GOS_SKILL_NAMES) {
          core.symlinkOrJunction(path.join(skillsSrc, s), path.join(p.linkDir, s), true);
        }
        installed++;
        console.log(`✓ ${p.name}: ${GOS_SKILL_NAMES.length} skill links in ${p.linkDir}`);
      }
    } catch (e) {
      console.log(`⚠ ${p.name}: ${e.message}`);
    }
  }
  console.log(`\n${installed} platform(s) configured${localPath ? ' (local dev mode)' : ''}.`);
  // Auto-seed the REVIEW subagent definition for platforms with an agents
  // directory convention (opencode). Codex/Claude consume it via the skill.
  const agentSrc = path.join(skillsSrc, 'gos-review', 'agents', 'code-reviewer.md');
  if (fs.existsSync(agentSrc)) {
    const ocAgentsDir = path.join(process.env.OPENCODE_CONFIG_DIR || path.join(home, '.config', 'opencode'), 'agents');
    try {
      fs.mkdirSync(ocAgentsDir, { recursive: true });
      core.symlinkOrJunction(agentSrc, path.join(ocAgentsDir, 'code-reviewer.md'), true);
      console.log('✓ code-reviewer agent: auto-linked (REVIEW subagent dispatch ready)');
    } catch { /* non-fatal: the prompt template in skills/gos-review/prompts/ still works */ }
  }
  // Interactive onboarding (TTY only; non-interactive keeps defaults)
  if (process.stdin.isTTY && !args.includes('--no-onboard')) {
    onboarding().catch(() => console.log('(onboarding skipped)'));
  } else {
    const cfg = sibConfig.loadConfig();
    const auto = autoPersistDetectedLocale();
    if (auto) console.log(`✓ language: ${auto.locale} (detected from environment, persisted to ${auto.scope})`);
    console.log(`\nTeam staffing: ${cfg.model_profile} — change anytime: gos config models profile <name>`);
    console.log('Next: restart your AI assistant, then say "list your gos skills"');
  }
}

// ---------- commitlint commit-msg hook (install/teardown) ----------
// The hook master ships at <GOS_SELF_ROOT>/hooks/commit-msg.sh; installation
// copies it to <toplevel>/hooks/commit-msg and points core.hooksPath at hooks/.
// The prior core.hooksPath value is backed up under .gos/cache/ (machine-local)
// so teardown can restore it; idempotent re-runs keep the original backup.
const COMMITLINT_HOOK_REL = path.join('hooks', 'commit-msg');
const PRE_PUSH_HOOK_REL = path.join('hooks', 'pre-push');
const COMMITLINT_STATE_REL = path.join('.gos', 'cache', 'commitlint-hook.json');
const COMMITLINT_HOOKS_PATH_VALUE = 'hooks';
// commitlint's real config resolution set (D-94, consumed by
// ops/brownfield-probe.cjs): the rc family and the commitlint.config family
// are stat candidates; package.json counts only through its 'commitlint' key
// (checked by the probe, not by stat). Exported so the candidate strings
// live in exactly one place.
const COMMITLINT_RC_CANDIDATES = ['.commitlintrc', '.commitlintrc.json', '.commitlintrc.yml', '.commitlintrc.yaml', '.commitlintrc.js', '.commitlintrc.cjs', '.commitlintrc.mjs', '.commitlintrc.ts'];
const COMMITLINT_CONFIG_CANDIDATES = ['commitlint.config.js', 'commitlint.config.cjs', 'commitlint.config.mjs', 'commitlint.config.ts'];

function gitTopOrDie() {
  try {
    return execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    core.die('not a git repository — run `gos setup --commitlint` inside one');
  }
}

function gitConfigGet(top, key) {
  try {
    return execFileSync('git', ['-C', top, 'config', '--get', key], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() || null;
  } catch {
    return null;
  }
}

function cmdSetupCommitlint(args) {
  const top = gitTopOrDie();
  const statePath = path.join(top, COMMITLINT_STATE_REL);

  if (args.includes('--teardown')) {
    teardownCommitlint(top, statePath);
    return;
  }

  const hookMasters = [
    { rel: COMMITLINT_HOOK_REL, src: path.join(core.GOS_SELF_ROOT, 'hooks', 'commit-msg.sh') },
    { rel: PRE_PUSH_HOOK_REL, src: path.join(core.GOS_SELF_ROOT, 'hooks', 'pre-push.sh') },
  ];
  for (const hm of hookMasters) {
    if (!fs.existsSync(hm.src)) core.die(`hook master missing: ${hm.src} (reinstall GOS, then gos setup --commitlint)`);
  }

  if (!fs.existsSync(statePath)) {
    fs.mkdirSync(path.dirname(statePath), { recursive: true });
    fs.writeFileSync(statePath, JSON.stringify({
      prior_core_hooks_path: gitConfigGet(top, 'core.hooksPath'),
      hook: COMMITLINT_HOOK_REL,
      hooks: [COMMITLINT_HOOK_REL, PRE_PUSH_HOOK_REL],
      hooks_path: COMMITLINT_HOOKS_PATH_VALUE,
    }, null, 2) + '\n');
  }

  fs.mkdirSync(path.join(top, 'hooks'), { recursive: true });
  for (const hm of hookMasters) {
    fs.copyFileSync(hm.src, path.join(top, hm.rel));
    fs.chmodSync(path.join(top, hm.rel), 0o755);
  }
  execFileSync('git', ['-C', top, 'config', 'core.hooksPath', COMMITLINT_HOOKS_PATH_VALUE], { stdio: 'ignore' });
  console.log(`✓ commitlint hook installed: ${COMMITLINT_HOOK_REL} (core.hooksPath=${COMMITLINT_HOOKS_PATH_VALUE})`);
  console.log(`✓ pre-push guard installed: ${PRE_PUSH_HOOK_REL} (aggregate-push discipline on refs/heads/main)`);
  console.log('✓ linting via npx --yes commitlint@19 (pinned major, matches templates/git/node/ci.yml)');
  console.log('Next: commit messages must follow Conventional Commits; raw multi-commit pushes to main are redirected to `gos push`; remove anytime with `gos setup --commitlint --teardown`');
}

function teardownCommitlint(top, statePath) {
  if (!fs.existsSync(statePath)) {
    console.log('commitlint hook not installed — nothing to tear down');
    return;
  }
  let st = {};
  try { st = JSON.parse(fs.readFileSync(statePath, 'utf8')); } catch { /* corrupted backup: still remove files */ }
  // State written before the pre-push guard shipped carries only `hook`;
  // newer state carries the full `hooks` list.
  const hookRels = Array.isArray(st.hooks) && st.hooks.length ? st.hooks : [st.hook || COMMITLINT_HOOK_REL];
  for (const rel of hookRels) {
    try { fs.unlinkSync(path.join(top, rel)); } catch { /* already gone */ }
  }
  try { fs.rmdirSync(path.join(top, path.dirname(hookRels[0]))); } catch { /* non-empty hooks dir stays */ }

  const cur = gitConfigGet(top, 'core.hooksPath');
  if (cur === (st.hooks_path || COMMITLINT_HOOKS_PATH_VALUE)) {
    if (st.prior_core_hooks_path == null) {
      try { execFileSync('git', ['-C', top, 'config', '--unset', 'core.hooksPath'], { stdio: 'ignore' }); } catch { /* already unset */ }
      console.log('✓ commitlint hook removed, core.hooksPath unset (prior value: none)');
    } else {
      execFileSync('git', ['-C', top, 'config', 'core.hooksPath', st.prior_core_hooks_path], { stdio: 'ignore' });
      console.log(`✓ commitlint hook removed, core.hooksPath restored to: ${st.prior_core_hooks_path}`);
    }
  } else {
    console.log(`✓ commitlint hook files removed; core.hooksPath left as-is (${cur || 'unset'}) — it no longer points at the gos hook`);
  }
  try { fs.unlinkSync(statePath); } catch { /* already gone */ }
  try { fs.rmdirSync(path.dirname(statePath)); } catch { /* non-empty cache dir stays */ }
}

// Seed the teaching-grade gate examples into the CURRENT project (.gos/):
// gates.json (declarative rules) + gates/check.sh (scripted check), then
// register the script's hash in the machine-local trust store — seeded means
// reviewed-by-setup, hence trusted (spec R-05). Idempotent: never overwrites.
// Trust registration goes through the CLI as a subprocess (same-source rule —
// setup must not require gate.cjs, that would close a require cycle via
// doctor.cjs).
function seedGatesExamples() {
  const out = { gates_json: null, check_sh: null, trusted: [], note: '' };
  const tplDir = path.join(core.GOS_SELF_ROOT, 'templates', 'gates');
  const gj = path.join(core.GOS_DIR, 'gates.json');
  if (!fs.existsSync(gj)) {
    fs.mkdirSync(core.GOS_DIR, { recursive: true });
    fs.copyFileSync(path.join(tplDir, 'gates.json'), gj);
    out.gates_json = gj;
  }
  const cs = path.join(core.GOS_DIR, 'gates', 'check.sh');
  if (!fs.existsSync(cs)) {
    fs.mkdirSync(path.dirname(cs), { recursive: true });
    fs.copyFileSync(path.join(tplDir, 'check.sh'), cs);
    try { fs.chmodSync(cs, 0o755); } catch { /* chmod is best-effort */ }
    out.check_sh = cs;
    try {
      execFileSync(process.execPath,
        [path.join(core.GOS_SELF_ROOT, 'bin', 'gos.cjs'), 'gate', 'trust', 'check.sh'],
        { cwd: process.cwd(), stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000 });
      out.trusted.push('check.sh');
    } catch (e) {
      out.note = `gate trust subprocess failed: ${String((e.stderr || e.stdout || e.message) || '').trim().slice(0, 120)}`;
    }
  }
  return out;
}

// Locale-resolved onboarding hint naming the coding-standards seeding
// command; exported so the rendered line is assertable without a TTY.
function renderCodingHint() {
  return core.t('setup.onboard.codingHint');
}

async function onboarding() {
  const W = (s) => console.log(s);
  W('');
  W(core.t('setup.onboard.title'));
  W(core.t('setup.onboard.subtitle'));
  W('╰──────────────────────────────────────────────────────────────╯');

  // ---- Step 0: language (D-63) ----
  W('');
  W(core.t('setup.onboard.step1Title'));
  W(core.t('setup.onboard.step1Desc'));
  W(core.t('setup.onboard.step1Options'));
  const ansLang = await core.ask(core.t('setup.lang.prompt'));
  const langMap = { '1': 'en', '2': 'zh-CN' };
  if (langMap[ansLang.trim()]) {
    const { scope } = persistLocale(langMap[ansLang.trim()]);
    W(`┃ ${core.t('setup.lang.saved', { locale: langMap[ansLang.trim()], source: scope })}`);
  } else {
    W(core.t('setup.onboard.langKept'));
  }

  // ---- Step 1: staffing ----
  W('');
  W(core.t('setup.onboard.step2Title'));
  W(core.t('setup.onboard.step2Desc1'));
  W(core.t('setup.onboard.step2Desc2'));
  W('┃');
  W(core.t('setup.onboard.teamDesc'));
  W(core.t('setup.onboard.teamWhy'));
  W(core.t('setup.onboard.soloDesc'));
  W(core.t('setup.onboard.eliteDesc'));
  W(core.t('setup.onboard.leanDesc'));
  const cfg = sibConfig.loadConfig();
  const ans1 = await core.ask(core.t('setup.onboard.profilePrompt', { current: cfg.model_profile }));
  const profileMap = { '1': 'team', '2': 'solo', '3': 'elite', '4': 'lean', '': 'team' };
  const profile = profileMap[ans1] || cfg.model_profile;
  cfg.model_profile = profile;
  sibConfig.saveConfig(cfg);
  W(core.t('setup.onboard.profileSaved', { profile }));

  // ---- Step 2: sub-config per profile ----
  W('');
  W(core.t('setup.onboard.step3Title'));
  const probed = sibConfig.probeModels();
  if (profile === 'solo') {
    W(core.t('setup.onboard.soloNoRefine'));
    W(core.t('setup.onboard.soloChangeLater'));
  } else if (!probed || !probed.strong || !probed.fast) {
    W(core.t('setup.onboard.probeFailed'));
    W(core.t('setup.onboard.skipRefine'));
    W('┃   gos config models set checker <provider/model-name>');
  } else {
    const others = probed.all.filter(m => m !== probed.strong && m !== probed.fast);
    W(core.t('setup.onboard.probeResult', { strong: probed.strong, fast: probed.fast }));
    W(core.t('setup.onboard.pinRoles'));
    // checker — the different-perspective reviewer; the soul of the team profile.
    if (profile === 'team') {
      const diffCandidates = [probed.fast, ...others.filter(m => m !== probed.strong)].filter(Boolean);
      const suggestion = diffCandidates[0] || probed.fast;
      W(core.t('setup.onboard.checkerDesc'));
      const a = await core.ask(core.t('setup.onboard.checkerPrompt', { suggestion }));
      const m = (a && sibConfig.MODEL_NAME_RE.test(a)) ? a : suggestion;
      cfg.models = cfg.models || {}; cfg.models.checker = m; sibConfig.saveConfig(cfg);
      W(`┃  ✓ checker = ${m}`);
    }
    if (profile === 'elite' || profile === 'lean') {
      const def = profile === 'lean' ? probed.fast : probed.strong;
      const a = await core.ask(core.t('setup.onboard.implementerPrompt', { def }));
      const m = (a && sibConfig.MODEL_NAME_RE.test(a)) ? a : def;
      cfg.models = cfg.models || {}; cfg.models.implementer = m; sibConfig.saveConfig(cfg);
      W(`┃  ✓ implementer = ${m}`);
    }
    W(core.t('setup.onboard.otherRoles'));
  }

  // ---- Step 3: pluggable gates + routing ----
  W('');
  W('┏━ [4/4] Pluggable gates + routing');
  W('┃ GOS ships built-in hard gates (coverage/truths/requirements). You can also add YOUR rules in the project:');
  W('┃   Method A declarative: <project>/.gos/gates.json — e.g. {"protect":[".env"],"lint":"npm run lint"}');
  W('┃   Method B scripted: <project>/.gos/gates/*.sh — any check script, exit 0=pass, non-zero=blocks the stage');
  W('┃ `gos gate all` runs them at every task wrap-up; scripts only run after you review + trust them (gos gate trust <name>).');
  W('┃ (Skipping is fine — GOS built-in cleanup/security scans still run automatically at the ship stage.)');
  const aG = await core.ask('    Seed gate examples now (gates.json + gates/check.sh, hash auto-registered)? [y/N]: ');
  if (aG && aG.toLowerCase() === 'y') {
    const res = seedGatesExamples();
    if (res.gates_json) W(`┃ ✓ generated ${res.gates_json}`); else W('┃ ✓ .gos/gates.json already exists');
    if (res.check_sh) W(`┃ ✓ generated ${res.check_sh}`); else W('┃ ✓ .gos/gates/check.sh already exists');
    if (res.trusted.includes('check.sh')) W('┃ ✓ trusted custom gate registered: check.sh (seeded = trusted)');
    if (res.note) W(`┃ ⚠ ${res.note}`);
  }
  W(core.t('setup.onboard.agentsDesc1'));
  W(core.t('setup.onboard.agentsDesc2'));
  const a3 = await core.ask(core.t('setup.onboard.agentsPrompt'));
  if ((a3 || 'y').toLowerCase() !== 'n') {
    const marker = '<!-- GOS:START -->';
    const block = `${marker}
# GOS Routing
Before starting ANY development task in this session, run \`gos\` (no
arguments) — it reports task state and what to do next. Slash commands:
/gos /gos-next /gos-status /gos-init /gos-resume /gos-gate /gos-commit
<!-- GOS:END -->`;
    const agentsPath = path.resolve('AGENTS.md');
    let existing = '';
    try { existing = fs.readFileSync(agentsPath, 'utf8'); } catch { /* none */ }
    if (existing.includes(marker)) {
      W(core.t('setup.onboard.agentsSkip'));
    } else {
      fs.writeFileSync(agentsPath, (existing ? existing + '\n\n' : '# AGENTS.md\n\n') + block + '\n');
      W(core.t('setup.onboard.agentsWritten', { path: agentsPath }));
    }
  }
  W('');
  W(renderCodingHint());
  W(core.t('setup.onboard.selfCheck'));
  W('');
  W(core.t('setup.onboard.doneTitle'));
  W(core.t('setup.onboard.doneRestart'));
  W(core.t('setup.onboard.doneVerify'));
  W(core.t('setup.onboard.doneStart'));
  W('╰──────────────────────────────────────────────────────────────╯');
}

function cmdTeardown() {
  const home = os.homedir();
  const links = [
    path.join(process.env.OPENCODE_CONFIG_DIR || path.join(home, '.config/opencode'), 'skills', 'gos'),
    path.join(process.env.OPENCODE_CONFIG_DIR || path.join(home, '.config/opencode'), 'commands', 'gos'),
    path.join(process.env.OPENCODE_CONFIG_DIR || path.join(home, '.config/opencode'), 'agents', 'code-reviewer.md'),
    path.join(home, '.agents', 'skills', 'gos'),
    ...GOS_SKILL_NAMES.map(s => path.join(home, '.claude', 'skills', s)),
  ];
  let removed = 0;
  for (const l of links) {
    try {
      const st = fs.lstatSync(l); // symlink only — never touch real dirs (PM-1 invariant)
      if (st.isSymbolicLink()) { fs.unlinkSync(l); removed++; }
    } catch { /* not present */ }
  }
  console.log(`✓ Removed ${removed} symlink(s). (Clone/npm package untouched — uninstall via npm if desired.)`);
}

module.exports = { GOS_SKILL_NAMES, detectPlatforms, cmdSetup, cmdSetupCommitlint, onboarding, renderCodingHint, seedGatesExamples, cmdTeardown, COMMITLINT_HOOK_REL, PRE_PUSH_HOOK_REL, COMMITLINT_STATE_REL, COMMITLINT_HOOKS_PATH_VALUE, COMMITLINT_RC_CANDIDATES, COMMITLINT_CONFIG_CANDIDATES };
