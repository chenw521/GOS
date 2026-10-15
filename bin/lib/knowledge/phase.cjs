// knowledge/phase.cjs — knowledge module aspect: phase lifecycle over project.json.
// Sibling requires are free; cross-directory requires go to core only.
'use strict';

const decisions = require('./decisions.cjs');


const fs = require('node:fs');
const path = require('node:path');
const core = require('../core/index.cjs');

function detectBrownfield() {
  const found = [];
  const checks = {
    'DECISIONS.md': (t) => /^\|\s*D-\d{2,3}\s*\|/m.test(t),
    'REQUIREMENTS.md': (t) => /^\|\s*R-\d{2,3}\s*\|/m.test(t),
    'ROADMAP.md': (t) => t.split('\n').some(l => /^\|\s*[^:|#\s]/.test(l) && !/^\|\s*Phase\s*\|/.test(l)),
    // D-06: TODO guidance lines are seeded scaffolding, never handwritten
    // content — a fresh skeleton must not read as brownfield.
    'PROJECT.md': (t) => t.split('\n').filter(l => l.trim() && !l.startsWith('#') && !l.trim().startsWith('TODO:')).length > 2,
  };
  for (const [name, test] of Object.entries(checks)) {
    const p = path.join(core.PROJECT_DIR, name);
    if (fs.existsSync(p)) {
      try { if (test(fs.readFileSync(p, 'utf8'))) found.push(name); } catch { /* unreadable */ }
    }
  }
  return found.length ? found : null;
}

// D-06/R-33 (F-8): PROJECT.md per-section predicate. Every `## ` section must
// carry at least one content line: non-TODO, >=20 codepoints, and not a
// separator/dash string (three junk lines like `-`/`x`/`n/a` still fail). A
// section-less file never passes vacuously — at least one `## ` section is
// required. Shared by brownfield detection, the approve-archive pre-flight
// (archive.cjs), and the THINK read_files wiring (context.cjs).
const PROJECT_MD_MIN_CP = 20;
const PROJECT_MD_SEPARATOR_RE = /^[-=_*\s]+$/;

function projectMdSectionReport(text) {
  const sections = [];
  let cur = null;
  for (const raw of String(text).split(/\r?\n/)) {
    if (/^## /.test(raw)) {
      cur = { name: raw.replace(/^##\s*/, '').trim() || '(untitled)', content: 0 };
      sections.push(cur);
      continue;
    }
    if (!cur) continue; // preamble before the first `## ` section
    const t = raw.trim();
    if (!t || t.startsWith('TODO:') || PROJECT_MD_SEPARATOR_RE.test(t)) continue;
    if ([...t].length < PROJECT_MD_MIN_CP) continue;
    cur.content++;
  }
  return { sections, lacking: sections.filter((s) => s.content < 1) };
}

function projectMdFilled(text) {
  const r = projectMdSectionReport(text);
  return r.sections.length >= 1 && r.lacking.length === 0;
}

function cmdPhase(args) {
  const sub = (args[0] || '').toLowerCase();
  const rest = args.slice(1);

  if (sub === 'add') {
    const state = core.readState();
    if (!state || state.project !== true) core.die('phase add requires an Lv4 project (gos init --project)');
    const { pos, opt } = decisions.decisionParseOpts(rest, ['--goal']);
    const name = pos.join(' ').trim();
    const goal = opt['--goal'] !== undefined && opt['--goal'] !== null ? String(opt['--goal']).trim() : '';
    if (!name || !goal) core.die('Usage: gos phase add "P1: name" --goal "..."');
    const nbt = core.badText(name);
    if (nbt) core.die(`name rejected (${nbt})`);
    const gbt = core.badText(goal);
    if (gbt) core.die(`goal rejected (${gbt})`);
    let project = core.loadProject();
    let fresh = false;
    if (!project) { project = core.emptyProject(); fresh = true; } // second legit creation point (with init --project)
    if (project.phases.some((p) => p && p.name === name)) core.die('phase name already exists');
    project.phases.push({ name, goal, status: 'pending' });
    core.saveProject(project);
    if (fresh) {
      // same brownfield warning as init --project — handwritten content about to be shadowed
      const brown = detectBrownfield();
      if (brown) {
        console.log(`⚠ existing handwritten content detected in: ${brown.join(', ')}`);
        console.log('  Import decisions into the truth source: `gos decision import --all` (review first: `gos decision import`)');
        console.log('  Or discard after review: re-run import with --discard. Rendered views will overwrite non-imported content at next archive.');
      }
    }
    console.log(`${core.CONTRACTS.command_contracts.phaseAdded}${name}`);
    console.log('Next: gos phase list');
    decisions.autoRenderViews(project); // D-03: views stay fresh after the mutation
    return;
  }

  // Pending-goal rewrite via command (edit-via-commands; hand-editing project.json
  // is the anti-pattern this closes). Active phases hold their goal inside the
  // in-flight state's requirements — rewriting would desync task and roadmap.
  // Done/parked goals are history: done is audit record, parked must be un-parked
  // explicitly first (its deferral decision was made against the current goal).
  if (sub === 'amend') {
    const { pos, opt } = decisions.decisionParseOpts(rest, ['--goal']);
    const nArg = pos.find((a) => /^\d+$/.test(a));
    const goal = opt['--goal'] !== undefined && opt['--goal'] !== null ? String(opt['--goal']).trim() : '';
    if (nArg === undefined || !goal) core.die('Usage: gos phase amend <n> --goal "..."');
    const n = parseInt(nArg, 10);
    const project = core.loadProject();
    const phases = (project && Array.isArray(project.phases)) ? project.phases : [];
    if (!(n >= 0 && n < phases.length)) core.die(`phase index out of range (valid: 0-${Math.max(phases.length - 1, 0)}) — see \`gos phase list\``);
    const ph = phases[n];
    if (ph.status === 'active') core.die(`phase ${n} (${ph.name}) ${core.CONTRACTS.command_contracts.amendRefuseActive}`);
    if (ph.status === 'done') core.die(`phase ${n} (${ph.name}) ${core.CONTRACTS.command_contracts.amendRefuseDone}`);
    if (ph.status === 'parked') core.die(`phase ${n} (${ph.name}) ${core.CONTRACTS.command_contracts.amendRefuseParked}`);
    const gbt = core.badText(goal);
    if (gbt) core.die(`goal rejected (${gbt})`);
    ph.goal = goal; // whole-goal replace, same semantics as phase add --goal
    core.saveProject(project);
    console.log(`${core.CONTRACTS.command_contracts.phaseAmended}${ph.name}`);
    console.log('Next: gos phase list');
    decisions.autoRenderViews(project); // D-03: views stay fresh after the mutation
    return;
  }

  if (sub === 'list') {
    const project = core.loadProject();
    const phases = (project && Array.isArray(project.phases)) ? project.phases : [];
    if (!phases.length) { console.log('(no phases — gos phase add)'); return; }
    // idx column mirrors the claim argument space (0-based) — display and
    // parameter cannot diverge.
    console.log('| idx | Phase | Goal | Status |');
    console.log('|:---|:---|:---|:---|');
    phases.forEach((p, i) => console.log(`| ${i} | ${core.escCell(p.name)} | ${core.escCell(p.goal)} | ${core.escCell(p.status === 'parked' ? `parked(${p.park_reason || '(no reason)'})` : p.status)} |`));
    return;
  }

  if (sub === 'claim') {
    const force = rest.includes('--force');
    const nArg = rest.find((a) => !a.startsWith('--'));
    if (nArg === undefined) core.die('Usage: gos phase claim <n|name-prefix> [--force]');
    const project = core.loadProject();
    const phases = (project && Array.isArray(project.phases)) ? project.phases : [];
    // Name-prefix claim (`gos phase claim Q`) — index-free reference; humans and
    // machines use the same key. Ambiguous prefix dies listing candidates; digits
    // keep the legacy path.
    let n;
    if (/^\d+$/.test(nArg)) {
      n = parseInt(nArg, 10);
    } else {
      const hits = phases.map((p, i) => ({ p, i })).filter((x) => x.p && x.p.name.toLowerCase().startsWith(nArg.toLowerCase()));
      if (hits.length === 1) n = hits[0].i;
      else if (hits.length > 1) core.die(`✗ ambiguous phase prefix '${nArg}' — matches: ${hits.map((h) => `${h.i}=${h.p.name}`).join(', ')}\nNext: pick the index, or extend the prefix`);
      else n = -1;
    }
    if (!(n >= 0 && n < phases.length)) {
      // Actionable out-of-range error: valid range + queue map + next step.
      const queue = phases.map((p, i) => `${i}=${p.name}(${p.status})`).join('  ');
      core.die(`✗ phase '${nArg}' not found — valid range: 0-${Math.max(phases.length - 1, 0)}\nQueue: ${queue || '(empty — gos phase add first)'}\nNext: re-check with \`gos phase list\`, or claim by name prefix (e.g. gos phase claim ${phases.find((p) => p.status === 'pending') ? phases.find((p) => p.status === 'pending').name.slice(0, 1) : 'X'})`);
    }
    if (phases[n].status === 'active') core.die('phase already active (claimed by current state)');
    // Target-status whitelist — done/parked targets must NEVER be silently revived
    // (the prevOk gate alone would not catch it). --force bypasses CURRENT-task
    // preconditions, never roadmap closure.
    if (phases[n].status === 'done') {
      const nextPending = phases.findIndex((p) => p && p.status === 'pending');
      if (nextPending === -1) {
        const parkedCnt = phases.filter((p) => p && p.status === 'parked').length;
        core.die(`phase ${n} (${phases[n].name}) ${core.CONTRACTS.command_contracts.claimAllClosed}${parkedCnt ? `; ${parkedCnt} parked item(s) pending close-out (\`gos phase list\`)` : ' (milestone ready)'}`);
      }
      core.die(`phase ${n} (${phases[n].name}) ${core.CONTRACTS.command_contracts.claimTargetDone}${nextPending} → \`gos phase claim ${nextPending}\` (see \`gos status\` Next section)`);
    }
    if (phases[n].status === 'parked') {
      core.die(`phase ${n} (${phases[n].name}) ${core.CONTRACTS.command_contracts.claimTargetParked} ${n} --undo\` first, then re-claim`);
    }
    if (phases[n].status !== 'pending') core.die(`phase ${n} has unknown status '${phases[n].status}' — expected pending|active|done|parked (see \`gos phase list\`)`);
    const state = core.readState();
    if (force) console.log('⚠⚠ FORCE-CLAIM bypasses DONE/archive preconditions — data loss risk if current task is mid-flight');
    // DONE precondition applies to PHASE-OWNED state only (phase_name set by a prior claim).
    // A wrapper state (project=true, no phase_name — the Lv4 project container created by init
    // --project) has no work to lose: first claim from wrapper is the NORMAL entry, not an exception.
    // The archived-chain field is audit-only — the order gate is status-based below.
    // Unclaim-then-reclaim of the SAME phase is the designed recovery path
    // (unclaim output says "re-claim or gos init"); the DONE precondition must not
    // block it — only a DIFFERENT phase's claim requires DONE+archive of this one.
    const isSamePhaseReclaim = !!(state && state.phase_name === phases[n].name && phases[n].status === 'pending');
    const isPhaseOwned = !!(state && state.phase_name);
    if (!force) {
      if (isPhaseOwned && !isSamePhaseReclaim && state.current_stage !== 'DONE') core.die(`finish and archive current task first (stage is ${state.current_stage})`);
      if (state && !state.phase_name && state.current_stage !== 'INTENT' && state.current_stage !== 'DONE') {
        core.die(`wrapper state is at ${state.current_stage} — wrapper has no spec/plan; archive it or init --force before claiming`);
      }
      // Prev-done+parked: roadmap order ≠ execution order. Immediate predecessor
      // closed (done OR parked) is enough; last_archived_phase is audit-only,
      // NOT a gate condition.
      const prevOk = n === 0 ? true : ['done', 'parked'].includes(phases[n - 1].status);
      if (!prevOk) {
        const pn = phases[n - 1];
        core.die(`phase ${n - 1} (${pn.name}) ${core.CONTRACTS.command_contracts.claimGatedPrev}\n${core.CONTRACTS.command_contracts.claimDeferredHint} ${n - 1}\` — then re-claim.\n${core.CONTRACTS.command_contracts.claimCrossPhaseHint}`);
      }
    }
    // WRITE ORDER: new state atomically FIRST, then project status — a crash in between
    // leaves a pending phase + orphaned state, never a lying 'active' with no state.
    const goal = phases[n].goal;
    const fresh = core.defaultState(3, goal);
    fresh.intent.confirmed = true;
    fresh.project = true;
    fresh.project_root = core.currentRootRealpath() || fs.realpathSync('.');
    fresh.phase_name = phases[n].name;
    fresh.requirements = core.extractRequirement(goal, 3);
    // Diff baseline at claim; history is append-only — re-claiming the SAME phase
    // appends what:'re-claim' instead of overwriting (baseline reset can't whitewash
    // the prior range). A different/first phase starts a fresh history.
    const inGit = core.gitInWorkTree();
    const headSha = inGit ? core.gitHeadSha() : null;
    fresh.task_head = headSha;
    if (inGit && !headSha) fresh.task_head_pending = true;
    const prevRows = (state && state.phase_name === phases[n].name && Array.isArray(state.task_head_history))
      ? state.task_head_history.filter((r) => r && typeof r === 'object')
      : [];
    fresh.task_head_history = [...prevRows, { sha: headSha, at: new Date().toISOString(), what: prevRows.length ? 're-claim' : 'claim' }];
    core.writeState(fresh);
    phases[n].status = 'active';
    core.saveProject(project);
    console.log(`${core.CONTRACTS.command_contracts.phaseClaimed}${phases[n].name}`);
    console.log('Next: THINK (intent = phase goal)');
    decisions.autoRenderViews(project); // D-03: views stay fresh after the mutation
    return;
  }

  if (sub === 'unclaim') {
    const state = core.readState();
    if (!state) core.die(core.CONTRACTS.state_semantics.noActiveTask);
    const project = core.loadProject();
    const target = (project && Array.isArray(project.phases))
      ? project.phases.find((p) => p && p.status === 'active' && state.phase_name && p.name === state.phase_name)
      : null;
    if (!target) core.die('no active phase to unclaim');
    target.status = 'pending';
    core.saveProject(project);
    console.log(`${core.CONTRACTS.command_contracts.phaseUnclaimed}${target.name} unclaimed — state now orphaned; re-claim or gos init to replace`);
    return;
  }

  // Explicit deferral — pending ⇄ parked. A parked predecessor counts
  // as closed for the claim gate, but parked phases still BLOCK milestone completion
  // (every(done) unchanged) — the debt stays visible in list/status/doneHint/archive.
  if (sub === 'park') {
    const undo = rest.includes('--undo');
    const { pos, opt } = decisions.decisionParseOpts(rest, ['--reason']);
    const nArg = pos.find((a) => /^\d+$/.test(a)) || pos[0];
    if (nArg === undefined) core.die(`Usage: gos phase park <n|name-prefix> [--reason "..."] | gos phase park <n|name-prefix> --undo`);
    const project = core.loadProject();
    const phases = (project && Array.isArray(project.phases)) ? project.phases : [];
    let n;
    if (/^\d+$/.test(nArg)) {
      n = parseInt(nArg, 10);
    } else {
      const hits = phases.map((p, i) => ({ p, i })).filter((x) => x.p && x.p.name.toLowerCase().startsWith(nArg.toLowerCase()));
      if (hits.length === 1) n = hits[0].i;
      else if (hits.length > 1) core.die(`✗ ambiguous phase prefix '${nArg}' — matches: ${hits.map((h) => `${h.i}=${h.p.name}`).join(', ')}\nNext: pick the index, or extend the prefix`);
      else n = -1;
    }
    if (!(n >= 0 && n < phases.length)) {
      // Same actionable range+queue template as claim.
      const queue = phases.map((p, i) => `${i}=${p.name}(${p.status})`).join('  ');
      core.die(`✗ phase '${nArg}' not found — valid range: 0-${Math.max(phases.length - 1, 0)}\nQueue: ${queue || '(empty — gos phase add first)'}\nNext: re-check with \`gos phase list\``);
    }
    const ph = phases[n];
    if (undo) {
      if (ph.status === 'parked') {
        ph.status = 'pending';
        delete ph.park_reason;
        core.saveProject(project);
        console.log(`${core.CONTRACTS.command_contracts.parkUndo}${ph.name}`);
        console.log('Next: gos phase claim <n|name-prefix>');
      } else if (ph.status === 'pending') {
        console.log(core.CONTRACTS.command_contracts.parkUndoIdempotent);
      } else {
        core.die(`phase ${n} (${ph.name}) is ${ph.status} — only parked phases can be un-parked`);
      }
      return;
    }
    if (ph.status === 'parked') { console.log(core.CONTRACTS.command_contracts.parkIdempotent); return; }
    if (ph.status === 'active') core.die(`phase ${n} (${ph.name}) ${core.CONTRACTS.command_contracts.parkRefuseActive}`);
    if (ph.status === 'done') core.die(`phase ${n} (${ph.name}) ${core.CONTRACTS.command_contracts.parkRefuseDone}`);
    let reason = (opt['--reason'] !== undefined && opt['--reason'] !== null) ? String(opt['--reason']).trim() : '';
    if (reason) {
      if (core.cpLen(reason) > 200) core.die(`reason too long: ${core.cpLen(reason)} codepoints (max 200)`);
      const rbt = core.badText(reason);
      if (rbt) core.die(`reason rejected (${rbt})`);
    } else {
      reason = '(no reason)';
    }
    ph.status = 'parked';
    ph.park_reason = reason;
    core.saveProject(project);
    console.log(`${core.CONTRACTS.command_contracts.phaseParked}${ph.name} (${reason})`);
    console.log(`⚠ ${core.CONTRACTS.command_contracts.parkBlocksMilestone}`);
    // A mid-flight task state pointing at the parked phase must not coexist silently
    const pstate = core.readState();
    if (pstate && pstate.phase_name === ph.name && !['INTENT', 'DONE'].includes(pstate.current_stage)) {
      console.log(core.CONTRACTS.command_contracts.parkOrphanWarn);
    }
    console.log('Next: gos phase list');
    return;
  }

  // Bootstrap backfill for phases completed OUTSIDE GOS (e.g. pre-roadmap work
  // retro-recorded). ACTIVE phases are refused — no pipeline bypass (finish & archive
  // through the real flow); idempotent on already-done.
  if (sub === 'mark-done') {
    const nArg = rest.find((a) => /^\d+$/.test(a));
    if (nArg === undefined) core.die('Usage: gos phase mark-done <n>');
    const n = parseInt(nArg, 10);
    const project = core.loadProject();
    const phases = (project && Array.isArray(project.phases)) ? project.phases : [];
    if (!(n >= 0 && n < phases.length)) core.die('phase index out of range');
    const ph = phases[n];
    if (ph.status === 'active') core.die(`phase '${ph.name}' is ACTIVE (claimed by in-flight state) — finish and archive it via the full pipeline; mark-done is only for backfilling phases completed outside GOS`);
    if (ph.status === 'done') { console.log(`✓ phase already done: ${ph.name}`); return; }
    const wasParked = ph.status === 'parked';
    ph.status = 'done';
    delete ph.park_reason;
    // Mark-done is a done-transition too — keep the audit field at the most
    // recent done transition (incl. backfill), or it rots into a guaranteed lie.
    project.last_archived_phase = ph.name;
    core.saveProject(project);
    if (wasParked) console.log(`${core.CONTRACTS.command_contracts.markDoneCloseOut}: ${ph.name}`);
    console.log(`✓ Phase marked done: ${ph.name}`);
    console.log('Next: gos phase list');
    return;
  }

  console.log('Usage: gos phase <add|amend|list|claim|unclaim|park|mark-done>');
  console.log('  add "P1: name" --goal "..."   add pending phase to project.json');
  console.log('  amend <n> --goal "..."        replace goal of a PENDING phase (active/done/parked refused)');
  console.log('  list                          phase table');
  console.log('  claim <n> [--force]           fresh Lv3 state for phase n (DONE + prev archived required)');
  console.log('  unclaim                       revert active phase to pending (state orphaned)');
  console.log('  park <n> [--reason "..."]     explicitly defer a pending phase (blocks milestone, visible debt)');
  console.log('  park <n> --undo               back to pending');
  console.log('  mark-done <n>                 backfill done status (ACTIVE refused — no pipeline bypass)');
}

Object.assign(module.exports, {
  cmdPhase,
  detectBrownfield,
  projectMdSectionReport,
  projectMdFilled,
});   // assignment (not reassignment): sibling modules hold live references to this export
