'use strict';

const core = require('../core/index.cjs');
const nav = require('../nav/status.cjs');   // direct aspect require (dependency DAG — routing through the index hub would cycle task/index)
const render = require('../render/views.cjs');
const map = require('../map/index.cjs');
const knowledge = require('../knowledge/index.cjs');
const gitseed = require('../ops/gitseed.cjs');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

function parseLevelStrict(s) {
  if (s == null) return { level: null };
  const str = String(s);
  if (/^\d+$/.test(str)) {                        // bare digits — mainstream form
    const n = parseInt(str, 10);
    if (!(n >= 0 && n <= 4)) core.die(`level out of range '${core.sanitizeEcho(str)}' — use 0-4 (got ${n})`);
    return { level: n };
  }
  if (!/^l[vv]?[\s-]*\d*$/i.test(str)) return { level: null };
  const m = str.match(/^l[vv]?[\s-]?(\d+)$/i);
  if (!m) core.die(`invalid level '${core.sanitizeEcho(str)}' — use 0-4 with optional lv prefix (e.g. 1, lv1, Lv2)`);
  const n = parseInt(m[1], 10);
  if (!(n >= 0 && n <= 4)) core.die(`level out of range '${core.sanitizeEcho(str)}' — use 0-4 (got ${n})`);
  return { level: n };
}

function cmdInit(args) {
  const isProject = args.includes('--project');
  const positional = args.filter(a => !a.startsWith('--'));
  const wantsConfirm = args.includes('--confirm') || args.includes('--confirmed');

  // `git` is a reserved first positional: the git-workflow seeding verb.
  // This dispatch precedes level/intent parsing and every state read, so
  // seeding never touches task state and is never blocked by the in-flight
  // guard. Escape hatch for git-themed task intents: put the level first
  // (`gos init <level> git "<intent>"`).
  if (positional[0] === 'git') { cmdInitGit(args).catch((e) => core.die(e.message)); return; }
  if (positional[0] === 'coding') { cmdInitCoding(args).catch((e) => core.die(e.message)); return; }

 // confirm-only path: zero positional + --confirm/--confirmed. Repairs the
  // r234 root cause (bare `init --confirm` used to core.die on the in-flight guard) and
  // pins the state-machine semantics: touch ONLY intent.confirmed, never rebuild.
  if (wantsConfirm && positional.length === 0) {
    if (args.includes('--force')) core.die('--confirm and --force are mutually exclusive');
    const cur = core.readState();
    if (!cur) core.die('nothing to confirm — no active task (start one: `gos init <level> "<intent>"`)');
    if (cur.current_stage !== 'INTENT') core.die(`nothing to confirm at stage ${cur.current_stage} — intent confirmation happens at INTENT only`);
    if (cur.intent.confirmed) { console.log('✓ intent already confirmed'); return; }
    cur.intent.confirmed = true;
    core.writeState(cur);
    console.log('✓ intent confirmed (D-34 confirm-only: no semantic field touched; legacy-state migration may normalize schema fields)');
    console.log('Next: intent confirmed → proceed to THINK');
    return;
  }

 // gos init <level> "<intent summary>" — two-stage normalization
  let level = null;
  let intentText = '';
  if (positional.length >= 1) {
    const parsed = parseLevelStrict(positional[0]);
    if (parsed.level !== null) { level = parsed.level; intentText = positional.slice(1).join(' '); }
    else intentText = positional.join(' ');
  }
  const existing = core.readState();
  const hadHeadHistory = !!(existing && Array.isArray(existing.task_head_history) && existing.task_head_history.length);
  if (existing && !args.includes('--force')) {
    // gap-reflux #1 (0.11.3): state-first guard HARDENED — an ACTIVE task (not DONE)
    // must never be silently walked over by a fresh init; router/skills route on this
    // exit code. Archived-DONE states keep the old soft path (re-init is normal there).
    if (existing.current_stage !== 'DONE') {
      console.error(`✗ active task in flight (stage: ${existing.current_stage}) — "${core.sanitizeEcho(existing.intent.summary)}"`);
      console.error('  continue it: `gos resume` (router state-first branch), or finish/archive first;');
      console.error('  overwrite anyway: `gos init --force` (diff baseline restarts)');
      process.exit(1);
    }
    console.log(`⚠ Existing task found: ${core.sanitizeEcho(existing.intent.summary)}`);
    console.log('  Use --force to overwrite, or continue the current task.');
    return nav.printStatus(existing);
  }
 // --force must not silently destroy unarchived spec/plan (v0.8 loss incident).
  // A spec/plan on disk whose content has NO identical git-committed copy is
  // unarchived work — refuse. Archived tasks have spec/plan moved away, so the
  // normal post-archive `init --force` flow is unaffected.
  if (existing && args.includes('--force')) {
 // task/<id>/ dirs are in-flight work — --force is the EXPLICIT discard path
    // (spec: "archive first, or discard via an explicit --force"), so wipe with a warning, never silently orphan.
    const taskZone = path.join(core.GOS_DIR, 'task');
    if (fs.existsSync(taskZone)) {
      const leftovers = fs.readdirSync(taskZone).filter((x) => !x.startsWith('.'));
      if (leftovers.length) {
 // same protection as the root-level probe: an UNCOMMITTED spec/plan
        // inside task/<id>/ is unrecoverable work — refuse; committed content still clears
        const unprotected = [];
        for (const x of leftovers) {
          for (const f of ['spec.md', 'plan.md']) {
            const rel = path.join('.gos', 'task', x, f);
            const abs = path.join(taskZone, x, f);
            if (!fs.existsSync(abs)) continue;
            let committed = null;
            try { committed = execFileSync('git', ['show', `HEAD:${rel}`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }); } catch { committed = null; }
            if (committed === null || committed !== fs.readFileSync(abs, 'utf8')) unprotected.push(rel);
          }
        }
        if (unprotected.length) core.die(`unarchived spec/plan would be overwritten (${unprotected.join(', ')}) — commit them or run gos archive first, then re-run with --force`);
        console.log(`⚠ init --force discards unarchived task dirs: ${leftovers.join(', ')}`);
        for (const x of leftovers) fs.rmSync(path.join(taskZone, x), { recursive: true, force: true });
      }
    }
    for (const rel of ['.gos/spec.md', '.gos/plan.md']) { // [T5-legacy-splice] pre-migration leftover probe — whitelisted in T44 static assertion
      if (!fs.existsSync(rel)) continue;
      let committed = null;
      try {
        committed = execFileSync('git', ['show', `HEAD:${rel}`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
      } catch { committed = null; } // not committed / no repo / no HEAD
      if (committed === null || committed !== fs.readFileSync(rel, 'utf8')) {
        core.die('unarchived spec/plan would be overwritten — run gos archive first (or commit them), then re-run with --force');
      }
    }
  }
 // / : single-shot confirm hole closed — creating a task WITH --confirm in
  // one call dies in BOTH environments (the old `level !== null && --confirm` set the
  // bit as a parameter side-effect; `--confirmed` alias was equally live at :1389).
  if (wantsConfirm) {
    core.die(core.isHeadlessEnv()
      ? 'headless mode: init confirms automatically (audited) — do not pass --confirm/--confirmed'
      : 'two-step protocol: run `gos init <level> "<intent>"` first, get the user\'s verbal yes, then bare `gos init --confirm` (--confirmed alias is retired)');
  }

  const headless = core.isHeadlessEnv();
  const state = core.defaultState(level, intentText);
 // intent confirmation is a USER act (interactive two-step) or an audited env
  // fact (headless one-shot). Audit lands in state — bypass visible, never silent.
  if (headless) {
    state.intent.confirmed = true;
    state.intent.confirmation = { mode: 'headless-auto', ts: new Date().toISOString() };
  }
  state.activation_source = core.detectActivationSource();
  state.requirements = core.extractRequirement(intentText, level);
  // T2 [D-31/B-4]: diff baseline — HEAD sha at init; zero-commit git → pending; non-git → null
  const inGit = core.gitInWorkTree();
  state.task_head = inGit ? core.gitHeadSha() : null;
  if (inGit && !state.task_head) state.task_head_pending = true;
 // (T4b): v4 identity is de-pathed — no project_root anchor is stored;
  // repo identity = repo_id (stamped by defaultState), repo root is
  // runtime-derived via currentRootRealpath() wherever a root is needed.
  const root = core.currentRootRealpath() || fs.realpathSync('.');
 // pin spec/plan to task/<id>/ at birth — single resolution from here on.
  // (project tasks get phase_name later at claim; core.currentTaskId falls to task_head[0:8].)
 // Stored repo-relative : tracked state must not carry machine paths.
  if (!state.spec_path) core.pinTaskPaths(state);
  core.writeState(state);

 // [Phase D ] seed the anchor-network sidecar from birth ( rollout: missing == anomaly)
  if (seedEdgesIfAbsent(root)) {
    console.log('✓ seeded .gos/edges.json (map 2.0 anchor network — first gos commit freezes its lock)');
  }
 // [Phase W ] seed the generated README from birth — README regen guard (gate) fails on absence
  try {
    const readmeP = core.resolvePath('readme');
    if (!fs.existsSync(readmeP)) { fs.mkdirSync(path.dirname(readmeP), { recursive: true }); fs.writeFileSync(readmeP, render.renderPathsMarkdown()); console.log('✓ seeded .gos/README.md (registry navigation — regen via gos paths --markdown)'); }
  } catch { /* non-fatal — guard will instruct */ }

  if (isProject) {
    fs.mkdirSync(core.PROJECT_DIR, { recursive: true });
 // / : PROJECT.md sections seed with TODO guidance lines — the
    // approve-archive gate and brownfield detection both key on them.
    const files = {
      'PROJECT.md': [
        '# Project',
        '',
        '## What This Is',
        'TODO: describe the product in a few sentences — what it is, for whom, and the problem it solves.',
        '',
        '## Core Value',
        'TODO: state the core value proposition — why this project exists and what it guarantees.',
        '',
        '## Requirements Evolution',
        'TODO: summarize how requirements evolve — phase claims, decision records, and truth-backed closure.',
        '',
      ].join('\n'),
      'ROADMAP.md': '# Roadmap\n\n| Phase | Goal | Status |\n|:---|:---|:---|\n',
      'DECISIONS.md': '# Decision Index (GENERATED view — project.json is the truth source; >50 entries → advisory prune)\n\n',
      'REQUIREMENTS.md': '# Requirements\n\n| ID | Requirement | Phase |\n|:---|:---|:---|\n',
    };
    for (const [name, content] of Object.entries(files)) {
      const p = path.join(core.PROJECT_DIR, name);
      if (!fs.existsSync(p)) fs.writeFileSync(p, content);
    }
 // project.json truth source skeleton (only creation point alongside phase add)
    const pj = path.join(core.PROJECT_DIR, 'project.json');
    if (!fs.existsSync(pj)) core.saveProject(core.emptyProject());
 // brownfield detection — handwritten 4-file content → suggest import, never silently overwrite
    const brown = knowledge.detectBrownfield();
    if (brown) {
      console.log(`⚠ existing handwritten content detected in: ${brown.join(', ')}`);
      console.log('  Import decisions into the truth source: `gos decision import --all` (review first: `gos decision import`)');
      console.log('  Or discard after review: re-run import with --discard. Rendered views will overwrite non-imported content at next archive.');
    }
    state.project = true;
    core.writeState(state);
  }
  // T2 [D-31]: --force discards the append-only baseline history — loud, never silent
  if (hadHeadHistory) console.log(`⚠ ${core.CONTRACTS.state_semantics.taskHeadReset}`);
  console.log(`${core.CONTRACTS.state_semantics.initDone} ${isProject ? 'Lv4 project' : 'task'}${level !== null ? ` (Lv${level})` : ''}`);
  console.log(`  R-01 recorded: "${core.sanitizeEcho(state.requirements[0].text)}"`);
  if (headless) console.log(core.t('status.headlessAutoConfirm'));
  console.log(state.intent.confirmed
    ? 'Next: intent confirmed → proceed to THINK'
    : 'Next: confirm intent WITH THE USER (restate, wait for yes), then bare `gos init --confirm`');
}

// gos init git — seed the git workflow template bundle into the current git
// repository (universal layer always; node layer only when the target repo
// has a package.json). Verb contract: task state is never read or written.
// Flags: --codeowner <v> (or interactive prompt), --repo <owner/repo> (or
// inference from the origin remote), --overwrite (replace all conflicts,
// with .gos-bak backups), --non-interactive (never prompt, keep conflicting
// user files), --json (machine report), --render-self (render the universal
// layer into this CLI's own repository).
async function cmdInitGit(args) {
  const KNOWN = ['--json', '--overwrite', '--non-interactive', '--render-self'];
  let codeowner = null;
  let repo = null;
  const rest = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--codeowner') {
      const v = args[i + 1];
      if (v === undefined || v.startsWith('--')) core.die('--codeowner requires a value: --codeowner <github-user-or-org/team>');
      codeowner = v; i++; continue;
    }
    if (a.startsWith('--codeowner=')) { codeowner = a.slice('--codeowner='.length); continue; }
    if (a === '--repo') {
      const v = args[i + 1];
      if (v === undefined || v.startsWith('--')) core.die('--repo requires a value: --repo <owner/repo>');
      repo = v; i++; continue;
    }
    if (a.startsWith('--repo=')) { repo = a.slice('--repo='.length); continue; }
    rest.push(a);
  }
  const flags = rest.filter(a => a.startsWith('--'));
  const positional = rest.filter(a => !a.startsWith('--'));
  if (flags.includes('--force')) {
    core.die('--force keeps its destructive task-state semantics and is not a seeding flag — use --overwrite to replace existing files');
  }
  const unknown = flags.filter(f => !KNOWN.includes(f));
  if (unknown.length) core.die(`unknown flag for init git: ${unknown.join(' ')} (known: ${KNOWN.join(' ')})`);
  if (positional.length > 1) {
    core.die(`unexpected argument after \`git\`: '${core.sanitizeEcho(positional[1])}' — to start a task whose summary begins with "git", put the level first: gos init <level> git "<intent>"`);
  }
  const json = flags.includes('--json');

  if (flags.includes('--render-self')) {
    let res;
    try {
      res = await gitseed.seed({ root: core.GOS_SELF_ROOT, files: gitseed.renderSelf(), overwrite: true, nonInteractive: true });
    } catch (e) { core.die(`render-self failed: ${e.message}`); }
    reportGitSeed(res, { json, self: true, layers: ['universal'], root: core.GOS_SELF_ROOT });
    return;
  }

 // Seeding anchors at the git toplevel, not the cwd : a non work-tree is refused.
  const root = core.gitToplevelRealpath();
  if (!root) core.die('not a git work-tree — run `git init` first, then re-run `gos init git`');

  if (!codeowner && !json && process.stdin.isTTY) {
    codeowner = await core.ask('Codeowner for CODEOWNERS (e.g. @octocat or @org/team): ');
  }
  if (!codeowner) core.die('codeowner required — pass --codeowner <github-user-or-org/team> (or run interactively)');
  try { gitseed.validateCodeowner(codeowner); }
  catch (e) { core.die(e.message); }

  // Explicit inputs are validated before anything is inferred, so a bad
  // --repo value dies before a single file is rendered or written.
  let repoSlug = repo;
  if (repoSlug) {
    try { gitseed.validateRepoSlug(repoSlug); }
    catch (e) { core.die(e.message); }
  } else {
    repoSlug = gitseed.inferRepoSlug(root);
    if (!repoSlug) {
      core.die('repo slug required — pass --repo <owner/repo> (inference reads only the origin remote and requires a github.com host)');
    }
  }

  let res;
  try {
    res = await gitseed.seed({
      root,
      codeowner,
      repo: repoSlug,
      overwrite: flags.includes('--overwrite'),
      nonInteractive: flags.includes('--non-interactive'),
    });
  } catch (e) { core.die(e.message); }
  const layers = ['universal'];
  if (fs.existsSync(path.join(root, 'package.json'))) layers.push('node');
  reportGitSeed(res, { json, layers, root });
}

// gos init coding — seed the coding-standards book set (00-general/shell/
// node/python) into <repo>/docs/coding-standards/. Masters are read verbatim
// from the shipped templates dir (no variable substitution). Verb contract
// mirrors init git: task state is never read or written; the conflict policy
// is gitseed.seed()'s (ask/keep/overwrite+bak, identical files skip).
// Flags: --overwrite (replace conflicts, with .gos-bak backups),
// --non-interactive (never prompt, keep conflicts), --json (machine report).
const CODING_BOOKS = ['00-general.md', 'shell.md', 'node.md', 'python.md'];

function renderCodingFiles() {
  const out = {};
  for (const name of CODING_BOOKS) {
    const master = path.join(core.CODING_STANDARDS_TEMPLATE_DIR, name);
    let content;
    try { content = fs.readFileSync(master, 'utf8'); }
    catch (e) { core.die(`coding-standards master missing: ${master} (${e.message})`); }
    out[path.join(core.CODING_STANDARDS_DEST_DIR, name)] = content;
  }
  return out;
}

async function cmdInitCoding(args) {
  const KNOWN = ['--json', '--overwrite', '--non-interactive'];
  const flags = args.filter(a => a.startsWith('--'));
  const positional = args.filter(a => !a.startsWith('--'));
  if (flags.includes('--force')) {
    core.die('--force keeps its destructive task-state semantics and is not a seeding flag — use --overwrite to replace existing files');
  }
  const unknown = flags.filter(f => !KNOWN.includes(f));
  if (unknown.length) core.die(`unknown flag for init coding: ${unknown.join(' ')} (known: ${KNOWN.join(' ')})`);
  if (positional.length > 1) {
    core.die(`unexpected argument after \`coding\`: '${core.sanitizeEcho(positional[1])}' — to start a task whose summary begins with "coding", put the level first: gos init <level> coding "<intent>"`);
  }
  const json = flags.includes('--json');

  // Same anchor as init git: the git toplevel, never the bare cwd.
  const root = core.gitToplevelRealpath();
  if (!root) core.die('not a git work-tree — run `git init` first, then re-run `gos init coding`');

  let res;
  try {
    res = await gitseed.seed({
      root,
      files: renderCodingFiles(),
      overwrite: flags.includes('--overwrite'),
      nonInteractive: flags.includes('--non-interactive'),
    });
  } catch (e) { core.die(e.message); }
  reportCodingSeed(res, { json, root });
}

// Print the seeding result. --json emits one machine-readable object; the
// human report lists per-file outcomes and always notes that nothing is
// auto-staged (same contract as reportGitSeed).
function reportCodingSeed(res, o) {
  if (o.json) {
    console.log(JSON.stringify({
      root: o.root,
      dest: core.CODING_STANDARDS_DEST_DIR,
      created: res.created,
      skipped: res.skipped,
      overwritten: res.overwritten,
    }));
    return;
  }
  console.log(`✓ coding standards seeded at ${path.join(o.root, core.CODING_STANDARDS_DEST_DIR)} (${CODING_BOOKS.length} books)`);
  if (res.created.length) {
    console.log(`  created (${res.created.length}):`);
    for (const f of res.created) console.log(`    ${f}`);
  }
  if (res.skipped.length) {
    console.log(`  kept (${res.skipped.length}) — existing files preserved, never silently overwritten:`);
    for (const f of res.skipped) console.log(`    ${f}`);
  }
  if (res.overwritten.length) {
    console.log(`  overwritten (${res.overwritten.length}) — previous copies saved as <file>.gos-bak:`);
    for (const f of res.overwritten) console.log(`    ${f}`);
  }
  console.log('  note: nothing is auto-staged — review, then git add what you need');
}

// Print the seeding result. --json emits a single machine-readable object
// (created/skipped/overwritten); the human report lists per-file outcomes and
// always notes that nothing is auto-staged.
function reportGitSeed(res, o) {
  if (o.json) {
    console.log(JSON.stringify({
      root: o.root,
      layers: o.layers,
      created: res.created,
      skipped: res.skipped,
      overwritten: res.overwritten,
    }));
    return;
  }
  if (o.self) {
    console.log(`✓ self-repo templates rendered at ${o.root} (universal layer; node layer exempt)`);
  } else {
    console.log(`✓ git workflow templates seeded at ${o.root}`);
    console.log(`  layers: ${o.layers.join(' + ')}${o.layers.includes('node') ? ' (package.json detected)' : ''}`);
    console.log('  these are adaptable starter templates — keep, change, or remove freely; skip `gos init git` entirely if you already have your own');
  }
  if (res.created.length) {
    console.log(`  created (${res.created.length}):`);
    for (const f of res.created) console.log(`    ${f}`);
  }
  if (res.skipped.length) {
    console.log(`  kept (${res.skipped.length}) — existing files preserved, never silently overwritten:`);
    for (const f of res.skipped) console.log(`    ${f}`);
  }
  if (res.overwritten.length) {
    console.log(`  overwritten (${res.overwritten.length}) — previous copies saved as <file>.gos-bak:`);
    for (const f of res.overwritten) console.log(`    ${f}`);
  }
  console.log('  note: nothing is auto-staged — review, then git add what you need');
}

function seedEdgesIfAbsent(root) {   // gos init wiring: new repos hold the seed from birth
  if (fs.existsSync(map.edgesPath(root))) return false;
  try {
    core.writeAtomicJson(map.edgesPath(root), { schema_version: 1, note: map.EDGES_NOTE, edges: [] });
    try { execFileSync('git', ['-C', root, 'add', '--', path.join('.gos', core.GOS_PATHS.edges.rel)], { stdio: ['ignore', 'ignore', 'ignore'] }); } catch { /* non-git / ignored (T16: cache is ignored by design) */ }
    return true;
  } catch { return false; }
}

module.exports = { parseLevelStrict, cmdInit, cmdInitGit, cmdInitCoding, seedEdgesIfAbsent };
