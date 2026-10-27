// nav/cmds — placement per aspect-rosters-v2.json
'use strict';

const core = require('../core/index.cjs');
const task = require('../task/plansnap.cjs');  // direct aspect require (dependency DAG)
const sibStatus = require('./status.cjs');
const knowledge = require('../knowledge/lessons-json.cjs');  // nav→knowledge (D-67 attribution; display-load, never throws)
const concernsMod = require('../knowledge/concerns.cjs');    // nav→knowledge (T5 gap rewrite boundary trigger path)
const fs = require('fs');
const path = require('path');

// lessons attribution block + tags-based progressive disclosure
// stage-relevant subset shown, remainder referenced via `gos lessons list`
// (never silently dropped).
function lessonsAttributionBlock(stage) {
  const attr = knowledge.lessonsAttribution(stage);
  if (!attr.project.ok) {
    console.log(core.t('lessons.unavailable', { reason: attr.project.reason }));
    return;
  }
  console.log(core.t('lessons.attribution', {
    projN: attr.project.count,
    globN: attr.global.ok ? attr.global.count : 0,
    projPath: core.shortPath(attr.project.path),
    globPath: core.shortPath(attr.global.path),
    expiring: (attr.project.expiring || 0) + (attr.global.ok ? attr.global.expiring || 0 : 0),
  }));
  if (attr.stageTagged.length) {
    console.log(core.t('lessons.stageSubsetHeader', { stage: attr.stage }));
    for (const e of attr.stageTagged.slice(0, 8)) {
      console.log(`  (${String(e.id).slice(0, 8)}) ${e.at} — ${e.text != null ? e.text : `${e.scene ? e.scene + ': ' : ''}${e.lesson || ''}`}`.slice(0, 180));
    }
  }
  if (attr.rest > 0) console.log(core.t('lessons.remainderPointer', { n: attr.rest }));
}

function cmdInstructions(args) {
  const state = core.readState();
  if (!state) core.die(core.CONTRACTS.state_semantics.noActiveTask);
  const stage = (args[0] || state.current_stage || '').toUpperCase();
  if (!stage || sibStatus.stageIndex(stage) === -1) {
    console.log('Usage: gos instructions <stage>');
    console.log('Stages: INTENT THINK PLAN BUILD REVIEW VERIFY SHIP');
    return;
  }
  const saved = state.current_stage;
  state.current_stage = stage;
  console.log(`=== Instructions for ${stage} ===\n`);
  lessonsAttributionBlock(stage);
  console.log('');
  for (const line of sibStatus.structuredNextActions(state)) console.log(line);
  state.current_stage = saved;
}

function cmdResume() {
  const state = core.readState();
  if (!state) core.die('No state to resume. Start with `gos init`.');
  console.log('=== GOS Resume Summary ===');
  console.log(`Task: ${core.sanitizeEcho(state.intent.summary)} (Lv${state.level ?? '?'})`);
  console.log(`Completed: ${state.completed_stages.join(' → ') || '(none)'}`);
  console.log(`Current stage: ${state.current_stage}`);
 // Checkpoint takes precedence (finer recovery point than stage level)
  const cps = (state.checkpoints || []).filter(c => !c.consumed);
  if (cps.length) {
    const latest = cps[cps.length - 1];
    console.log(`Checkpoint (wave/area level): ${latest.stage}/${latest.unit} — done: ${latest.done}, remaining: ${latest.remaining}`);
  }
 // stored paths are repo-relative; resolve for display/stat (the
  // absolute form is machine-local and never persisted).
  const specAbs = core.specPathOf(state);
  const planAbs = core.planPathOf(state);
  if (specAbs && fs.existsSync(specAbs)) console.log(`Spec: ${specAbs}`);
  if (planAbs && fs.existsSync(planAbs)) console.log(`Plan: ${planAbs}`);
  if (state.project && fs.existsSync(path.join(core.PROJECT_DIR, 'project.json'))) {
    console.log('→ Lv4: DECISIONS/ROADMAP/REQUIREMENTS are GENERATED views — edit via gos decision/requirement/phase commands.');
  }
  if (state.decisions.length) {
    console.log('Decisions:');
    for (const d of state.decisions) console.log(`  ${d.id}: ${d.title} ${d.covered ? '✓covered' : '✗uncovered'}`);
  }
  if (state.observable_truths.length) {
    console.log('Truths:');
    for (const t of state.observable_truths) console.log(`  ${t.id}: ${t.verified ? '✓verified' : '✗pending'}`);
  }
  console.log(`\nNext:\n${sibStatus.nextHint(state)}`);
}

function cmdApprove(args) {
  const state = core.readState();
  if (!state) core.die(core.CONTRACTS.state_semantics.noActiveTask);
  const what = (args[0] || '').toLowerCase();
  const valid = ['think', 'plan', 'archive', 'baseline-reset'];
  if (!valid.includes(what)) {
    console.log('Usage: gos approve <think|plan|archive|baseline-reset> [--reason "<why>"]');
    console.log('Approvals record EXPLICIT user sign-off; models must core.ask first.');
    const have = Object.keys(state.approvals || {});
    console.log(have.length ? `Current approvals: ${have.join(', ')}` : 'No approvals yet.');
    return;
  }
  state.approvals = state.approvals || {};
  if (what === 'baseline-reset') {
    // approve baseline-reset records {ts, reason}; reset consumes the record once and clears it
    let reason = null;
    for (let i = 1; i < args.length; i++) if (args[i] === '--reason') reason = args[++i];
    if (!reason) core.die('Usage: gos approve baseline-reset --reason "<why>" — a reason is required (consistency-checked against reset --reason)');
    state.approvals.BASELINE_RESET = { ts: new Date().toISOString(), reason };
    core.writeState(state);
    console.log(`✓ BASELINE_RESET approved (reason: ${reason}) — single-consumption: gos map baseline reset --reason "${reason}"`);
    return;
  }
  state.approvals[what.toUpperCase()] = new Date().toISOString();
  core.writeState(state);
  console.log(`✓ ${what.toUpperCase()} approved at ${state.approvals[what.toUpperCase()]}`);
  console.log(what === 'archive' ? 'Next: `gos archive` (will now pass the approval gate)' : `Next: \`gos commit ${what}\` (will now pass the approval gate)`);
}

function cmdTrace(args) {
  const what = (args[0] || 'requirements').toLowerCase();
  const state = core.readState();
  if (!state) core.die(core.CONTRACTS.state_semantics.noActiveTask);
  if (what === 'requirements' || what === 'reqs') {
    // R-NN → phase claim → task Covers (scan plan.md) → truth status
    const planTasks = task.parsePlanMd() || [];
    const rByTask = {};
    for (const t of planTasks) for (const c of t.covers) (rByTask[c] = rByTask[c] || []).push(t.id);
    console.log('| R-NN | Requirement | Phase | Tasks (this phase) | Status |');
    console.log('|:---|:---|:---|:---|:---|');
    for (const r of state.requirements) {
      const tasks = (rByTask[r.id] || []).join(',') || '—';
      console.log(`| ${r.id} | ${r.text.slice(0, 50)} | ${r.phase || '⚠ UNCLAIMED'} | ${tasks} | ${r.done ? '✓' : (r.phase ? 'claimed' : 'open')} |`);
    }
    const unclaimed = state.requirements.filter(r => !r.phase);
    if (unclaimed.length) {
      console.error(`\n⚠ ${unclaimed.length} unclaimed: ${unclaimed.map(r => r.id).join(', ')}`);
      process.exit(1);
    }
  } else if (what === 'decisions' || what === 'dnn') {
    console.log('| D-NN | Decision | Covered | Task |');
    console.log('|:---|:---|:---|:---|');
    for (const d of state.decisions) console.log(`| ${d.id} | ${d.title.slice(0, 50)} | ${d.covered ? '✓' : '✗'} | ${d.task || '—'} |`);
  } else {
    console.log('Usage: gos trace [requirements|decisions]');
  }
}

function cmdAuto(args) {
  const state = core.readState();
  if (!state) core.die(core.CONTRACTS.state_semantics.noActiveTask);
  const sub = (args[0] || '').toLowerCase();
  if (sub === 'on' || sub === 'off') {
    state.auto_mode = sub === 'on' ? 'tiered' : null;
    core.writeState(state);
    console.log(`✓ auto_mode = ${state.auto_mode || 'off'}`);
    console.log(sub === 'on'
      ? 'Tiered auto: routine confirmations auto-pass (spec written, plan coverage green);\n  DECISION gates still stop for you (gray-area choices, truth confirmation, archive).'
      : 'All gates human-held again.');
    return;
  }
  console.log(`auto_mode: ${state.auto_mode || 'off'}`);
  console.log('Usage: gos auto [on|off] — tiered automation: routine gates auto, decision gates held');
}

function cmdGap(args) {
  // gap resolve <G-id> --resolution "..." — closes a stage-back gap (fail-closed)
  // Mirrors the lessons/truth command families: fail-closed argument checks +
  // explicit resolution semantics (a gap is never closed without a resolution).
  const sub = (args[0] || 'list').toLowerCase();
  const rest = args.slice(1);
  // [T6/D-16] migrate/history operate on repo-level stores (concerns.md + the
  // gap-history ledger), NOT task state — they must run post-archive (the cure
  // for a repo whose mirrors outlived its task), so they sit BEFORE the
  // readState gate. Serialization: the write-class dispatch guard already holds
  // the root .gos/.lock for this process (acquireEdgeLock's re-entrancy
  // precedent) — only take concernsRootLock when it does not.
  if (sub === 'migrate') {
    for (const a of rest) core.die(`gap migrate: unknown argument '${a}'`);
    const P = concernsMod.concernsPaths();
    let ownLock = false;
    if (core.holdsLock()) {
      try { ownLock = JSON.parse(fs.readFileSync(path.join(P.root, '.gos', '.lock'), 'utf8')).pid === process.pid; } catch { ownLock = false; }
    }
    const run = () => concernsMod.migrateGapMirrors(P);
    const res = ownLock ? run() : core.concernsRootLock(P, run);
    if (!res.removed) console.log(core.t('gap.migrate.none'));
    else {
      console.log(core.t('gap.migrate.removed', { n: res.removed }));
      if (res.deduped) console.log(core.t('gap.migrate.dupes', { n: res.deduped }));
    }
    return;
  }
  if (sub === 'history') {
    for (const a of rest) core.die(`gap history: unknown argument '${a}'`);
    const { entries, skipped } = concernsMod.readGapHistoryLedger(concernsMod.concernsPaths());
    if (!entries.length) console.log(core.t('gap.history.empty'));
    for (const e of entries) console.log(`${e.ts} ${e.text}`);
    if (skipped) console.log(core.t('gap.history.skipped', { n: skipped }));
    return;
  }
  const state = core.readState();
  if (!state) core.die(`${core.CONTRACTS.state_semantics.noActiveTask} \`gos init\` first.`);
  if (!Array.isArray(state.gaps)) state.gaps = [];
  if (sub === 'list') {
    if (!state.gaps.length) { console.log('(no gaps)'); return; }
    for (const g of state.gaps) console.log(`${g.id} [${g.status}] ${g.description}${g.resolution ? `\n    ↳ fixed: ${g.resolution}` : ''}`);
    return;
  }
  if (sub === 'resolve') {
    const id = rest[0];
    let resolution = null;
    for (let i = 1; i < rest.length; i++) {
      if (rest[i] === '--resolution') resolution = rest[++i];
      else core.die(`gap resolve: unknown argument '${rest[i]}'`);
    }
    if (!id || id.startsWith('--')) core.die('Usage: gos gap resolve <G-id> --resolution "..."');
    if (!resolution || !resolution.trim()) core.die('gap resolve: --resolution is required (fail-closed: closing without a resolution = silent whitewash)');
    if (core.cpLen(resolution) > 300) core.die('gap resolve: resolution exceeds 300 codepoints');
    const g = state.gaps.find((x) => x.id === id);
    if (!g) core.die(`gap resolve: ${id} not found (gos gap list)`);
    if (g.status === 'fixed') core.die(`gap resolve: ${id} already fixed — ${g.resolution || '(no resolution recorded)'}`);
    g.status = 'fixed';
    g.resolution = resolution.trim();
    g.resolved_at = new Date().toISOString();
    core.writeState(state);
    console.log(`✓ gap ${id} fixed: ${g.resolution}`);
    return;
  }
  if (sub === 'rewrite') {
    // [T5/D-17] gap rewrite: replaces a gap description (the sanctioned path to
    // clear legacy zh descriptions). Text passes the tracked-store boundary
    // with concerns.md as the trigger file — gap descriptions flow into
    // concerns.md via the stage-back (auto) write-back, so tracked concerns.md
    // means gap text is clone-traveling content too.
    const id = rest[0];
    let text = null;
    for (let i = 1; i < rest.length; i++) {
      if (rest[i] === '--text') text = rest[++i];
      else core.die(`gap rewrite: unknown argument '${rest[i]}'`);
    }
    if (!id || id.startsWith('--')) core.die('Usage: gos gap rewrite <G-id> --text "<text>"');
    if (!text || !text.trim()) core.die('gap rewrite: --text is required (fail-closed: rewriting without text = silent history edit)');
    const c = core.checkInputConstraint({ value: text, maxCp: 300, label: 'gap text', noNewlineListPrefix: true });
    if (!c.ok) core.die(`✗ ${c.reason}`);
    core.dieTrackedStoreCJK(concernsMod.concernsPaths().file, c.value);
    const g = state.gaps.find((x) => x.id === id);
    if (!g) core.die(`gap rewrite: ${id} not found (gos gap list)`);
    g.description = c.value;
    g.rewritten_at = new Date().toISOString();
    core.writeState(state);
    console.log(`✓ gap ${id} description rewritten`);
    return;
  }
  core.die('Usage: gos gap <list|resolve|rewrite|migrate|history>');
}

module.exports = { cmdInstructions, cmdResume, cmdApprove, cmdTrace, cmdAuto, cmdGap };
