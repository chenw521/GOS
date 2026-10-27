// knowledge/requirements.cjs — knowledge module aspect: requirement lifecycle.
// Sibling requires are free; cross-directory requires go to core only.
'use strict';


const fs = require('node:fs');
const path = require('node:path');
const core = require('../core/index.cjs');
const decisions = require('./decisions.cjs');

const REQ_ID_RE = /^R-\d{2,3}$/;

function reqFlags(args) {
  const positional = [];
  const flags = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--phase') {
      if (i + 1 < args.length) { flags.phase = args[i + 1]; i++; }
    } else if (a.startsWith('--phase=')) {
      flags.phase = a.slice('--phase='.length);
    } else if (a.startsWith('--')) {
      flags[a.slice(2)] = true;
    } else {
      positional.push(a);
    }
  }
  return { positional, flags };
}

function cmdRequirement(args) {
  const sub = (args[0] || '').toLowerCase();
  const rest = args.slice(1);
  // project.json is the Lv4 truth source; read-class subcommands merge it whenever it exists
  const projExists = fs.existsSync(path.join(core.PROJECT_DIR, 'project.json'));
  const proj = projExists ? core.loadProject() : null;
  // `list --all` is the audit view — usable WITHOUT an active task
  const isListAll = sub === 'list' && rest.includes('--all');
  const state = core.readState();
  if (!state) {
    if (isListAll && proj) { printRequirementRows(projectRequirementRows(proj)); return; }
    if (isListAll) core.die(core.CONTRACTS.command_contracts.listNoSources);
    core.die(core.CONTRACTS.state_semantics.noActiveTask);
  }

  if (sub === 'add') {
    const { positional, flags } = reqFlags(rest);
 // is init-exclusive: this command takes NO id argument at all
    if (positional.some((p) => /^R-\d/i.test(p))) core.die('R-01 is init-exclusive; requirement add auto-assigns');
    const text = positional.join(' ').trim();
    if (!text) core.die('text required: gos requirement add "text" [--phase "P1: name"]');
    if (core.cpLen(text) > 200) core.die(`text too long: ${core.cpLen(text)} codepoints (max 200)`);
    const bt = core.badText(text);
    if (bt) core.die(`text rejected (${bt})`);
    let phaseL = flags.phase !== undefined ? String(flags.phase).trim() : null;
    if (phaseL === '') phaseL = null;
    if (phaseL) { const pbt = core.badText(phaseL); if (pbt) core.die(`phase rejected (${pbt})`); }
    if (state.level === 4 && !phaseL) core.die('phase required at Lv4: gos requirement add "text" --phase "P1: name"');
 // auto id: max numeric across state ∪ project, +1; floor at (R-01 init-exclusive)
    const nums = [];
    for (const r of (state.requirements || [])) { const m = /^R-(\d+)$/.exec(r.id || ''); if (m) nums.push(parseInt(m[1], 10)); }
    if (proj) for (const r of (proj.requirements || [])) { const m = /^R-(\d+)$/.exec(r.id || ''); if (m) nums.push(parseInt(m[1], 10)); }
    const next = Math.max(2, (nums.length ? Math.max(...nums) : 0) + 1);
    const id = `R-${String(next).padStart(2, '0')}`;
    const rec = { id, text, phase: phaseL, status: 'active' };   // record key frozen as 'phase' (local phaseL avoids the name collision)
    // Dual-store: project.json is the truth source when state.project && it exists; state mirrors it
    if (state.project === true && proj) {
      proj.requirements.push({ ...rec });
      core.saveProject(proj);
    }
    state.requirements.push({ ...rec });
    core.writeState(state);
    console.log(`${core.CONTRACTS.command_contracts.reqAdded}${id.slice(2)} added: ${text}`);
    console.log('Next: gos requirement list');
    if (state.project === true && proj) decisions.autoRenderViews(proj); // D-03: views stay fresh after the mutation
    return;
  }

  if (sub === 'list') {
    // default = STATE-ONLY (current task truth — done-phase residuals in project.json
    // must not shadow it); `--all` = merged state∪project audit view.
    let rows;
    if (rest.includes('--all')) {
      const merged = new Map();
      for (const r of (state.requirements || [])) merged.set(r.id, { ...r });
      if (proj) for (const r of (proj.requirements || [])) merged.set(r.id, { ...(merged.get(r.id) || {}), ...r }); // project wins
      rows = [...merged.values()];
      // row.status in this view is a WRITE-TIME snapshot — not a live lifecycle.
      if (proj && state.project !== true) console.log(core.CONTRACTS.command_contracts.listForeignProject);
    } else {
      rows = (state.requirements || []).map((r) => ({ ...r }));
    }
    printRequirementRows(rows);
    return;
  }

  if (sub === 'drop' || sub === 'claim') {
    const { flags } = reqFlags(rest);
    if (sub === 'drop') {
      const id = positionalOrDie(rest, REQ_ID_RE, 'Usage: gos requirement drop <R-NN>');
      const sr = (state.requirements || []).find((r) => r.id === id);
      const pr = proj ? (proj.requirements || []).find((r) => r.id === id) : undefined;
      if (!sr && !pr) core.die(`Requirement ${id} not found (state ∪ project)`);
      if (sr) sr.status = 'dropped';
      if (pr) pr.status = 'dropped';
      if (pr) core.saveProject(proj);
      if (sr) core.writeState(state);
      console.log(`✓ Requirement ${id} dropped`);
      return;
    }
    const phaseL = flags.phase !== undefined ? String(flags.phase).trim() : null;
    if (!phaseL) core.die('Usage: gos requirement claim <R-NN> --phase "P1: name"');
    const pbt = core.badText(phaseL);
    if (pbt) core.die(`phase rejected (${pbt})`);
    const id = positionalOrDie(rest, REQ_ID_RE, 'Usage: gos requirement claim <R-NN> --phase "P1: name"');
    const sr = (state.requirements || []).find((r) => r.id === id);
    const pr = proj ? (proj.requirements || []).find((r) => r.id === id) : undefined;
    if (!sr && !pr) core.die(`Requirement ${id} not found (state ∪ project)`);
    if (sr) sr.phase = phaseL;
    if (pr) pr.phase = phaseL;
    if (pr) core.saveProject(proj);
    if (sr) core.writeState(state);
    console.log(`✓ Requirement ${id} claimed by ${phaseL}`);
    if (pr) decisions.autoRenderViews(proj); // D-03: views stay fresh after the mutation
    return;
  }

  console.log('Usage: gos requirement <add|list|drop|claim>');
  console.log('  add "text" [--phase "P1: name"]    add (auto R-NN ≥ R-02; R-01 init-exclusive)');
  console.log('  list                              current-task view (state-only; --all = merged audit incl. done-phase residuals, status is write-time snapshot)');
  console.log('  drop <R-NN>                       mark status dropped');
  console.log('  claim <R-NN> --phase "P1: name"   set phase on an existing requirement');
}

function positionalOrDie(args, re, usage) {
  const id = args.find((a) => re.test(a));
  if (!id) core.die(usage);
  return id;
}

function projectRequirementRows(proj) {
  return ((proj && Array.isArray(proj.requirements)) ? proj.requirements : []).filter((r) => r && r.id).map((r) => ({ ...r }));
}

function printRequirementRows(rows) {
  const sorted = [...rows].sort((a, b) =>
    (parseInt(String(a.id || '').replace(/\D/g, ''), 10) || 0) - (parseInt(String(b.id || '').replace(/\D/g, ''), 10) || 0));
  const esc = (s) => String(s).replace(/\|/g, '\\|');
  console.log('| ID | Requirement | Phase | Status |');
  console.log('|:---|:---|:---|:---|');
  for (const r of sorted) console.log(`| ${r.id} | ${esc(String(r.text || '').slice(0, 60))} | ${r.phase || '-'} | ${r.status || 'active'} |`);
}

Object.assign(module.exports, {
  reqFlags,
  cmdRequirement,
  positionalOrDie,
  projectRequirementRows,
  printRequirementRows,
  REQ_ID_RE,
});   // assignment (not reassignment): sibling modules hold live references to this export
