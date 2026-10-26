// task/plansnap — Split-③ ②-4 (T2)
'use strict';

const core = require('../core/index.cjs');
const fs = require('fs');

function parsePlanMd() {
  const planPath = core.planPathOf(core.readState()); // T5: task/<id>/plan.md via single resolver
  if (!fs.existsSync(planPath)) return null;
  const raw = fs.readFileSync(planPath, 'utf8');
  const tasks = [];
  const seenIds = new Set();
  let currentTask = null;
  let currentWave = 0;
  for (const line of raw.split('\n')) {
    const waveMatch = line.match(/^###\s+Wave\s+(\d+)/i);
    if (waveMatch) { currentWave = parseInt(waveMatch[1]); continue; }
    const taskMatch = line.match(/^####\s+(T\d+[a-z]?):\s*(.*)/);
    if (taskMatch) {
      // B-21 [R2-14]: same task id in two blocks → reject (fail-closed, all consumers core.die)
      if (seenIds.has(taskMatch[1])) {
        core.die(`${core.CONTRACTS.state_semantics.planDupTask}: '${taskMatch[1]}' appears in two blocks — task ids must be unique`);
      }
      seenIds.add(taskMatch[1]);
      if (currentTask) tasks.push(currentTask);
      // files: null = no **Files** key (undeclared); '' = `**Files**: ` empty value (also
      // undeclared — B-21 pins the distinction; both freeze to snapshot files: [])
      currentTask = { id: taskMatch[1], name: taskMatch[2].trim(), wave: currentWave, covers: [], files: null, readFirst: '', doneWhen: '', depends: '' };
      continue;
    }
    if (currentTask) {
      const covers = line.match(/\*\*Covers\*\*:\s*(.*)/);
      // Covers are ID lists (D-NN / R-NN). Prose fragments in the line (goal
      // (f), parenthetical notes) are documentation, not references — keeping
      // them would feed ghost garbage into the coverage gate. Markdown
      // backticks are stripped the same way.
      if (covers) currentTask.covers = covers[1].split(/[,\s]+/)
        .map((s) => s.replace(/`/g, ''))
        .filter((s) => /^(D|R)-\d+$/i.test(s));
      const files = line.match(/\*\*Files\*\*:\s*(.*)/);
      // Files entries: strip backticks and trailing `:NN` line refs — the
      // snapshot compares against raw git paths, so `path:31` would never hit.
      if (files) currentTask.files = files[1].split(',')
        .map((s) => s.trim().replace(/`/g, '').replace(/:\d+$/, ''))
        .filter(Boolean).join(', ');
      const readFirst = line.match(/\*\*Read first\*\*:\s*(.*)/);
      if (readFirst) currentTask.readFirst = readFirst[1].trim();
      const doneWhen = line.match(/\*\*Done when\*\*:\s*(.*)/);
      if (doneWhen) currentTask.doneWhen = doneWhen[1].trim();
      const depends = line.match(/\*\*Depends on\*\*:\s*(.*)/);
      if (depends) currentTask.depends = depends[1].trim();
    }
  }
  if (currentTask) tasks.push(currentTask);
  return tasks;
}

function buildPlanSnapshotTasks(parsed) {
  const tasks = [];
  for (const t of (parsed || [])) {
    const files = String(t.files == null ? '' : t.files).split(',').map((s) => s.trim()).filter(Boolean);
    for (const f of files) {
      if (/\s/.test(f)) core.die(`${core.CONTRACTS.state_semantics.snapshotFileSpace}: '${f}' (task ${t.id}) — comma-separated paths only, no spaces`);
    }
    tasks.push({ id: t.id, covers: (t.covers || []).slice(), files });
  }
  return tasks;
}

function snapshotShrinkage(prevTasks, nextTasks) {
  const out = [];
  const freshFiles = new Set(nextTasks.flatMap((t) => t.files || []));
  for (const f of new Set(prevTasks.flatMap((t) => t.files || []))) {
    if (!freshFiles.has(f)) out.push(`∪Files lost '${f}'`);
  }
  const freshById = new Map(nextTasks.map((t) => [t.id, t]));
  for (const p of prevTasks) {
    const n = freshById.get(p.id);
    if (!n) { out.push(`task ${p.id} removed`); continue; }
    for (const c of (p.covers || [])) {
      if (!(n.covers || []).includes(c)) out.push(`task ${p.id} Covers lost '${c}'`);
    }
  }
  return out;
}

function freezeOrRefreshPlanSnapshot(state, { force }) {
  const tasks = buildPlanSnapshotTasks(parsePlanMd());
  const existing = state.plan_snapshot;
  if (!existing || !Array.isArray(existing.tasks)) return { tasks, audit: [] }; // first freeze
  if (state.current_stage !== 'PLAN') {
    core.die(`${core.CONTRACTS.state_semantics.snapshotStageBlock} — current stage is ${state.current_stage}; snapshot is frozen for BUILD+ consumption`);
  }
  const shrink = snapshotShrinkage(existing.tasks, tasks);
  if (shrink.length && !force) {
    core.die(`${core.CONTRACTS.state_semantics.snapshotMonotonic}: ${shrink.join('; ')} — restore the entries, or re-commit with --force (audit row what:snapshot-force)`);
  }
  const audit = (Array.isArray(existing.audit) ? existing.audit : []).slice();
  if (shrink.length && force) audit.push({ at: new Date().toISOString(), what: 'snapshot-force' });
  return { tasks, audit };
}

function pushLazyFreezeLedger(state, what) {
  state.lazy_freeze_audit = [
    ...(Array.isArray(state.lazy_freeze_audit) ? state.lazy_freeze_audit : []),
    { at: new Date().toISOString(), what },
  ];
}

module.exports = { parsePlanMd, buildPlanSnapshotTasks, snapshotShrinkage, freezeOrRefreshPlanSnapshot, pushLazyFreezeLedger };
