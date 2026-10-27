// knowledge/decisions.cjs — knowledge module aspect: decision lifecycle + supersede chain.
// Sibling requires are free; cross-directory requires go to core only.
'use strict';


const fs = require('node:fs');
const path = require('node:path');
const core = require('../core/index.cjs');

// mutation commands auto-render the project views inline — an
// in-process call inside the already-held .gos lock critical section (lesson
// c7a4be64: never a nested CLI call). Null project (Lv3 task) = nothing to render.
// Dependency inversion: knowledge stays render-agnostic; the task layer (the
// composition root — task→knowledge and task→render are both allowlisted)
// installs the render hook at load time.
let _autoRender = null;

function setAutoRender(fn) {
  _autoRender = typeof fn === 'function' ? fn : null;
}

function autoRenderViews(project) {
  if (!project || !_autoRender) return;
  _autoRender(project);
}

function decisionParseOpts(rest, valueFlags) {
  const pos = [];
  const opt = {};
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (valueFlags.includes(a)) { opt[a] = (i + 1 < rest.length) ? rest[i + 1] : null; i++; }
    else if (a.startsWith('--')) opt[a] = true;
    else pos.push(a);
  }
  return { pos, opt };
}

function decisionFind(state, project, id) {
  const sd = Array.isArray(state.decisions) ? (state.decisions.find((d) => d && d.id === id) || null) : null;
  const pd = (project && Array.isArray(project.decisions)) ? (project.decisions.find((d) => d && d.id === id) || null) : null;
  return { sd, pd };
}

function decisionTitleErr(t) {
  if (typeof t !== 'string' || core.cpLen(t) < 1) return 'title: required (1-120 codepoints)';
  if (core.cpLen(t) > 120) return 'title: >120 codepoints';
  const bt = core.badText(t);
  return bt ? `title: rejected (${bt})` : null;
}

function decisionRationaleErr(r) {
  if (r === undefined || r === null) return null;
  if (core.cpLen(r) > 200) return 'rationale: >200 codepoints';
  const bt = core.badText(r);
  return bt ? `rationale: rejected (${bt})` : null;
}

function decisionNextId(state, project) {
  let max = 0;
  const all = [...(Array.isArray(state.decisions) ? state.decisions : []), ...((project && project.decisions) || [])];
  for (const d of all) {
    const m = /^D-(\d{2,3})$/.exec((d && d.id) || '');
    if (m) max = Math.max(max, parseInt(m[1], 10));
  }
  const n = max + 1;
  if (n > 999) core.die('id space exhausted (D-999 max)');
  return `D-${String(n).padStart(2, '0')}`;
}

function decisionChainReaches(state, project, targetId, newId) {
  let cur = targetId;
  for (let i = 0; i < 50; i++) {
    if (cur === newId) return true;
    const { sd, pd } = decisionFind(state, project, cur);
    const d = sd || pd;
    if (!d || !d.supersedes) return false;
    cur = d.supersedes;
  }
  return true;
}

function decisionDualStore(state) {
  return state.project === true && fs.existsSync(path.join(core.PROJECT_DIR, 'project.json'));
}

function decisionPlanTasks(state) {
  const planPath = core.planPathOf(state);
  if (!fs.existsSync(planPath)) return null;
  const nums = new Set();
  for (const line of fs.readFileSync(planPath, 'utf8').split('\n')) {
    const m = line.match(/^####\s+T-?(\d+)\s*:/);
    if (m) nums.add(parseInt(m[1], 10));
  }
  return { nums, planPath };
}

function projectDecisionRows(proj) {
  return ((proj && Array.isArray(proj.decisions)) ? proj.decisions : []).filter((d) => d && d.id);
}

function printDecisionRows(rows, { includeSuperseded = false } = {}) {
  const sorted = [...rows].sort((a, b) => {
    const na = parseInt((/^D-(\d+)/.exec(a.id || '') || [0, 0])[1], 10) || 0;
    const nb = parseInt((/^D-(\d+)/.exec(b.id || '') || [0, 0])[1], 10) || 0;
    return na - nb;
  });
  console.log('| ID | Title | Status | Phase |');
  console.log('|:---|:---|:---|:---|');
  let shown = 0;
  for (const d of sorted) {
    if (d.status === 'superseded' && !includeSuperseded) continue;
    const esc = String(d.title || '').replace(/\|/g, '\\|');
    console.log(`| ${d.id} | ${esc} | ${d.status || 'open'} | ${d.birth_phase || 'P0'} |`);
    shown++;
  }
  if (!shown) console.log('(no decisions)');
}

function cmdDecision(args) {
  const sub = (args[0] || '').toLowerCase();
  const project = fs.existsSync(path.join(core.PROJECT_DIR, 'project.json')) ? core.loadProject() : null;
  // `list --all` is the audit view — usable WITHOUT an active task
  const isListAll = sub === 'list' && args.includes('--all');
  const state = core.readState();
  if (!state) {
    if (isListAll && project) { printDecisionRows(projectDecisionRows(project), { includeSuperseded: true }); return; }
    if (isListAll) core.die(core.CONTRACTS.command_contracts.listNoSources);
    core.die(`${core.CONTRACTS.state_semantics.noActiveTask} \`gos init\` first.`);
  }

  if (sub === 'add') {
    if (state.level !== null && state.level < 3) core.die('decision add requires Lv3/Lv4 (Lv1-2 decisions live in spec.md prose).');
    const { pos, opt } = decisionParseOpts(args.slice(1), ['--rationale', '--supersedes', '--anchor', '--phase']);
    let id = null;
    let title = null;
    if (pos.length >= 2) { id = pos[0]; title = pos.slice(1).join(' '); }
    else if (pos.length === 1) {
      if (/^[DR]-\d{2,3}$/.test(pos[0])) { id = pos[0]; title = ''; }
      else title = pos[0];
    }
    if (title === null) core.die('Usage: gos decision add [id] "title" --rationale "..." [--supersedes D-XX] [--anchor spec.md#sec] [--phase "P1: name"]');
    if (id !== null && !/^D-\d{2,3}$/.test(id)) core.die(`bad id "${id}" — decision ids must be D-prefixed: ^D-\\d{2,3}$ (D-01..D-999)`);
    if (id === null) id = decisionNextId(state, project);
    const { sd: dupS, pd: dupP } = decisionFind(state, project, id);
    // Project-only IDs are invisible in the default (state-only) list — pointing
    // the model at an entity it cannot see is a trap; teach the auditable path instead.
    if (dupS) core.die(`${id} already exists, use: gos decision amend ${id}`);
    if (dupP) core.die(`${id} ${core.CONTRACTS.command_contracts.dupArchivedTeaching}`);
    const rationale = opt['--rationale'] ?? '';
    const anchor = opt['--anchor'] ?? null;
    const phaseL = opt['--phase'] ?? null;
    const supersedes = opt['--supersedes'] ?? null;
    const err = decisionTitleErr(title) || decisionRationaleErr(rationale);
    if (err) core.die(err);
    if (phaseL && core.badText(phaseL)) core.die(`phase: rejected (${core.badText(phaseL)})`);
    if (anchor && core.badAnchor(anchor)) core.die(`anchor: ${core.badAnchor(anchor)}`);
    if (supersedes) {
      if (supersedes === id) core.die('supersedes: cannot supersede itself');
      const { sd: tS, pd: tP } = decisionFind(state, project, supersedes);
      if (!tS && !tP) core.die(`supersedes target ${supersedes} not found`);
      if (decisionChainReaches(state, project, supersedes, id)) core.die(`supersedes: cycle detected — ${id} is already in the chain from ${supersedes}`);
    }
    const d = { id, title, rationale, birth_phase: phaseL || state.phase_name || 'P0', status: 'open', anchor, covered: false, covered_by: null };
    if (supersedes) d.supersedes = supersedes;
    let touchedProject = false;
    if (decisionDualStore(state) && project) {
      project.decisions.push(d);   // project.json is the Lv4 truth source
      state.decisions.push(d);     // ...mirrored into state
      touchedProject = true;
    } else {
      state.decisions.push(d);
    }
    if (supersedes) {
      const { sd: tS, pd: tP } = decisionFind(state, project, supersedes);
      if (tS) tS.status = 'superseded';
      if (tP) { tP.status = 'superseded'; touchedProject = true; } // target lives in whichever store
    }
    if (touchedProject && project) core.saveProject(project);
    core.writeState(state);
    console.log(`${core.CONTRACTS.command_contracts.decisionAdded}${id.slice(2)} added: ${title}`);
    console.log('Next: gos decision list');
    if (touchedProject && project) autoRenderViews(project); // D-03: views stay fresh after the mutation
    return;
  }

  if (sub === 'amend') {
    const rest = args.slice(1);
    for (const bad of ['--id', '--birth-phase', '--birth_phase', '--anchor', '--phase', '--supersedes']) {
      if (rest.includes(bad)) core.die(`amend cannot change ${bad} — amend only takes --title/--rationale`);
    }
    const { pos, opt } = decisionParseOpts(rest, ['--title', '--rationale']);
    const id = pos[0];
    if (!id) core.die('Usage: gos decision amend <id> --title "..." [--rationale "..."]');
    const { sd, pd } = decisionFind(state, project, id);
    if (!sd && !pd) core.die(`${id} not found (state ∪ project)`);
    const target = sd || pd;
    // Project-only entries frozen by a done phase are history — rewriting them
    // via amend would silently mutate the audit record.
    if (!sd && pd && (!state.phase_name || pd.birth_phase !== state.phase_name)) core.die(`${id} ${core.CONTRACTS.command_contracts.archivedRefusedTeaching}`);
    if (target.status === 'superseded') core.die(`cannot amend superseded decision (${id})`);
    const title = opt['--title'] ?? null;
    const rationale = opt['--rationale'] ?? null;
    if (title === null && rationale === null) core.die('nothing to amend — pass --title and/or --rationale');
    const err = (title !== null ? decisionTitleErr(title) : null) || (rationale !== null ? decisionRationaleErr(rationale) : null);
    if (err) core.die(err);
    if (title !== null) { if (sd) sd.title = title; if (pd) pd.title = title; }
    if (rationale !== null) { if (sd) sd.rationale = rationale; if (pd) pd.rationale = rationale; }
    if (pd) core.saveProject(project);
    core.writeState(state);
    console.log(`${core.CONTRACTS.command_contracts.decisionAmended}${id.slice(2)} amended`);
    if (pd) autoRenderViews(project); // D-03: views stay fresh after the mutation
    return;
  }

  if (sub === 'cover') {
    const { pos, opt } = decisionParseOpts(args.slice(1), ['--task']);
    const id = pos[0];
    const taskArg = opt['--task'];
    if (!id || !taskArg) core.die('Usage: gos decision cover <id> --task T-NN');
    const { sd, pd } = decisionFind(state, project, id);
    if (!sd && !pd) core.die(`${id} not found (state ∪ project)`);
    // Same archived-entity guard as amend — covering a done-phase decision from
    // this phase's plan would falsify the historical coverage record.
    if (!sd && pd && (!state.phase_name || pd.birth_phase !== state.phase_name)) core.die(`${id} ${core.CONTRACTS.command_contracts.archivedRefusedTeaching}`);
    const tm = /^T-?(\d+)$/.exec(taskArg);
    if (!tm) core.die(`bad --task "${taskArg}" — use T1 or T-01 style`);
    const num = parseInt(tm[1], 10);
    const plan = decisionPlanTasks(state);
    if (!plan || !plan.nums.has(num)) core.die(`task not found in current plan (T${num} not in ${plan ? plan.planPath : core.planPathOf(core.readState())})`);
    let seq = 0; // phase-seq: index of state.phase_name in project.phases, 0 if unknown
    if (project && Array.isArray(project.phases) && state.phase_name) {
      const idx = project.phases.findIndex((ph) => ph && ph.name === state.phase_name);
      if (idx > -1) seq = idx;
    }
    const coveredBy = `P${seq}:T${num}`;
    for (const t of [sd, pd]) {
      if (!t) continue;
      t.status = 'covered';
      t.covered = true; // derived from status
      t.covered_by = coveredBy;
    }
    if (pd) core.saveProject(project);
    core.writeState(state);
    console.log(`${core.CONTRACTS.command_contracts.decisionAmended}${id.slice(2)} ${core.CONTRACTS.command_contracts.decisionCovered}${coveredBy.slice(1)}`);
    if (pd) autoRenderViews(project); // D-03: views stay fresh after the mutation
    return;
  }

  if (sub === 'list') {
    // default = STATE-ONLY (current phase decisions); `--all` = merged
    // state∪project view INCLUDING superseded — usage states this dual semantics.
    const all = args.includes('--all');
    let rows;
    if (all) {
      const merged = new Map();
      for (const d of (Array.isArray(state.decisions) ? state.decisions : [])) if (d && d.id) merged.set(d.id, d);
      if (project && Array.isArray(project.decisions)) for (const d of project.decisions) if (d && d.id) merged.set(d.id, d); // project wins on conflict
      rows = [...merged.values()];
      if (project && state.project !== true) console.log(core.CONTRACTS.command_contracts.listForeignProject);
    } else {
      rows = (Array.isArray(state.decisions) ? state.decisions : []).filter((d) => d && d.id);
    }
    printDecisionRows(rows, { includeSuperseded: all });
    return;
  }

  if (sub === 'import') {
    const decPath = path.join(core.PROJECT_DIR, 'DECISIONS.md');
    if (!fs.existsSync(decPath)) core.die('no .gos/project/DECISIONS.md found — nothing to import (D-22)');
    const entries = [];
    for (const line of fs.readFileSync(decPath, 'utf8').split('\n')) {
      const m = line.match(/^\|\s*(D-\d{2,3})\s*\|([^|]*)/);
      if (m) entries.push({ id: m[1], title: m[2].trim() });
    }
    const doAll = args.includes('--all');
    const doDiscard = args.includes('--discard');
    console.log(`✓ import preview: ${entries.length} entries`);
    for (const e of entries) console.log(`  ${e.id}: ${e.title}`);
    if (doDiscard) { console.log('Discarded — nothing written.'); return; }
    if (!doAll) {
      console.log('Re-run with --all to import these entries, or --discard to drop them (non-interactive-safe).');
      return;
    }
    let added = 0;
    let skipped = 0;
    const dual = decisionDualStore(state) && project;
    for (const e of entries) {
      const { sd, pd } = decisionFind(state, project, e.id);
      if (sd || pd) { console.log(`⚠ ${e.id} already exists — skipped`); skipped++; continue; }
      const terr = decisionTitleErr(e.title);
      if (terr) { console.log(`⚠ ${e.id} skipped: ${terr}`); skipped++; continue; }
      const d = { id: e.id, title: e.title, rationale: '', birth_phase: state.phase_name || 'P0', status: 'open', anchor: null, covered: false, covered_by: null };
      state.decisions.push(d);
      if (dual) project.decisions.push(d);
      console.log(`${core.CONTRACTS.command_contracts.decisionAdded}${e.id.slice(2)} added: ${e.title}`);
      added++;
    }
    if (added) {
      if (dual) core.saveProject(project);
      core.writeState(state);
    }
    console.log(`✓ import: ${added} added, ${skipped} skipped`);
    return;
  }

  console.log('Usage: gos decision <add|amend|cover|list|import> ...');
  console.log('  add [id] "title" --rationale "..." [--supersedes D-XX] [--anchor spec.md#sec] [--phase "P1: name"]');
  console.log('  amend <id> --title "..." [--rationale "..."]');
  console.log('  cover <id> --task T-NN');
  console.log('  list [--all]    current-phase decisions; --all = merged cross-phase audit incl. superseded (row status is write-time snapshot)');
  console.log('  import [--all|--discard]');
}

Object.assign(module.exports, {
  decisionParseOpts,
  decisionFind,
  decisionTitleErr,
  decisionRationaleErr,
  decisionNextId,
  decisionChainReaches,
  decisionDualStore,
  decisionPlanTasks,
  projectDecisionRows,
  printDecisionRows,
  setAutoRender,
  autoRenderViews,
  cmdDecision,
});   // assignment (not reassignment): sibling modules hold live references to this export
