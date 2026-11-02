'use strict';

const core = require('../core/index.cjs');
const fs = require('fs');
const path = require('path');

function parsePlanRaw() {
  const planPath = core.planPathOf(core.readState()); // T5: task/<id>/plan.md via single resolver
  if (!fs.existsSync(planPath)) return null;
  const raw = fs.readFileSync(planPath, 'utf8');
  const tasks = [];
  const headings = []; // ordered "### Wave N" numbers, in file order
  const seenIds = new Set();
  let currentTask = null;
  let currentWave = 0;
  for (const line of raw.split('\n')) {
    const waveMatch = line.match(/^###\s+Wave\s+(\d+)/i);
    if (waveMatch) { currentWave = parseInt(waveMatch[1], 10); headings.push(currentWave); continue; }
    const taskMatch = line.match(/^####\s+(T\d+[a-z]?):\s*(.*)/);
    if (taskMatch) {
      // B-21 [R2-14]: same task id in two blocks → reject (fail-closed, all consumers core.die)
      if (seenIds.has(taskMatch[1])) {
        core.die(`${core.CONTRACTS.state_semantics.planDupTask}: '${taskMatch[1]}' appears in two blocks — task ids must be unique`);
      }
      seenIds.add(taskMatch[1]);
      if (currentTask) tasks.push(currentTask);
      // files: null = no **Files** key (undeclared); '' = `**Files**: ` empty value (also
 // undeclared — pins the distinction; both freeze to snapshot files: [])
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
  return { tasks, headings };
}

function parsePlanMd() {
  const structure = parsePlanRaw();
  return structure ? structure.tasks : null;
}

function buildPlanSnapshotTasks(parsed) {
  const tasks = [];
  // Frozen entries carry `wave` whenever the plan declares any wave heading:
  // single-wave plans stamp wave 1 on their tasks (a one-wave plan is a wave
  // plan), heading-less plans keep the legacy entry shape (tasks implicitly
  // unassigned — snapshot.meta.waveValidation is the authority consumers
  // branch on).
  const waves = new Set((parsed || []).map((t) => (t.wave >= 1 ? t.wave : 0)));
  const stampWave = [...waves].some((w) => w >= 1);
  for (const t of (parsed || [])) {
    const files = String(t.files == null ? '' : t.files).split(',').map((s) => s.trim()).filter(Boolean);
    for (const f of files) {
      if (/\s/.test(f)) core.die(`${core.CONTRACTS.state_semantics.snapshotFileSpace}: '${f}' (task ${t.id}) — comma-separated paths only, no spaces`);
    }
    const entry = { id: t.id, covers: (t.covers || []).slice(), files };
    if (stampWave) entry.wave = t.wave || 0;
    tasks.push(entry);
  }
  return tasks;
}

// Wave-structure verdict over the parsed plan. gapped-wave and duplicate-wave
// are malformed plans and refuse the freeze; zero-wave (no wave headings at
// all) is legal to freeze for non-wave use but blocks BUILD entry — the
// verdict rides snapshot.meta.waveValidation and buildEntryCheck enforces it.
function validateWaveStructure(headings, tasks) {
  const nums = (Array.isArray(headings) ? headings : []).slice();
  if (!nums.length) {
    return { ok: false, reason: 'zero-wave', detail: 'plan.md declares no "### Wave N" headings — wave structure cannot be derived' };
  }
  const seen = new Set();
  for (const n of nums) {
    if (seen.has(n)) return { ok: false, reason: 'duplicate-wave', detail: `wave ${n} is declared by two "### Wave N" headings — wave numbers must be unique` };
    seen.add(n);
  }
  const belowOne = nums.find((n) => n < 1);
  if (belowOne != null) return { ok: false, reason: 'gapped-wave', detail: `wave ${belowOne} is below 1 — wave numbers start at 1` };
  const outside = (tasks || []).filter((t) => !(t.wave >= 1)).map((t) => t.id);
  if (outside.length) return { ok: false, reason: 'gapped-wave', detail: `task ${outside.join(', ')} outside any "### Wave N" heading — every task needs exactly one wave` };
  const sorted = [...seen].sort((a, b) => a - b);
  for (let i = 0; i < sorted.length; i += 1) {
    if (sorted[i] !== i + 1) return { ok: false, reason: 'gapped-wave', detail: `wave numbers [${sorted.join(', ')}] are not contiguous from 1 (missing ${i + 1})` };
  }
  return { ok: true, waves: sorted[sorted.length - 1] };
}

// Safe-path allowlist for declared files: repo-relative, no upward traversal,
// no .git/** and no hooks/** (hook tampering surface). Everything else
// (test/, bin/, templates/, docs/, .gos/…) is legal.
function validateDeclaredPaths(tasks) {
  for (const t of (tasks || [])) {
    for (const f of (t.files || [])) {
      let why = null;
      if (typeof f !== 'string' || !f.trim()) why = 'empty declared path';
      else if (path.isAbsolute(f)) why = `absolute path '${f}' — declared files must be repo-relative`;
      else if (f.split('/').includes('..')) why = `'..' segment in '${f}' — declared files cannot traverse upward`;
      else if (f === '.git' || f.startsWith('.git/')) why = `git metadata '${f}' — declared files cannot touch .git/**`;
      else if (f === 'hooks' || f.startsWith('hooks/')) why = `hooks path '${f}' — hook tampering surface`;
      if (why) return { ok: false, reason: 'unsafe-path', detail: `${why} (task ${t.id})`, path: f, task: t.id };
    }
  }
  return { ok: true };
}

// BUILD-entry refusal for wave dispatch: a frozen plan whose waves could not
// be derived cannot enter BUILD — fail closed with guidance back to PLAN.
// Snapshots frozen before wave stamping (no meta) pass grandfathered.
function buildEntryCheck(snapshot) {
  const v = snapshot && snapshot.meta && snapshot.meta.waveValidation;
  if (!v || v.ok) return { ok: true };
  return {
    ok: false,
    reason: v.reason,
    detail: v.detail,
    guidance: {
      what: 'BUILD entry refused: the frozen plan carries no wave structure',
      fix: 'return to PLAN — re-freeze plan.md with "### Wave N" headings (gos commit plan), then re-enter BUILD',
    },
  };
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

function freezeOrRefreshPlanSnapshot(state, { force, lazy }) {
  const structure = parsePlanRaw() || { tasks: [], headings: [] };
  const tasks = buildPlanSnapshotTasks(structure.tasks);
  // malformed plans refuse the freeze itself: gapped/duplicate wave numbering
  // and unsafe declared paths never reach a snapshot — later consumers trust
  // the frozen lists. zero-wave freezes legally (verdict recorded in meta).
  const waveV = validateWaveStructure(structure.headings, structure.tasks);
  if (!waveV.ok && waveV.reason !== 'zero-wave') {
    return { ok: false, reason: waveV.reason, detail: waveV.detail };
  }
  const pathsV = validateDeclaredPaths(tasks);
  if (!pathsV.ok) return { ok: false, reason: 'unsafe-path', detail: pathsV.detail };
  const meta = { waveValidation: waveV.ok
    ? { ok: true, waves: waveV.waves }
    : { ok: false, reason: waveV.reason, detail: waveV.detail } };
  const existing = state.plan_snapshot;
  if (!existing || !Array.isArray(existing.tasks)) {
    // first freeze; lazy=true marks a BUILD-entry backfill freeze
    return { tasks, audit: lazy ? [{ at: new Date().toISOString(), what: 'lazy-freeze' }] : [], meta };
  }
  if (state.current_stage !== 'PLAN') {
    core.die(`${core.CONTRACTS.state_semantics.snapshotStageBlock} — current stage is ${state.current_stage}; snapshot is frozen for BUILD+ consumption`);
  }
  const shrink = snapshotShrinkage(existing.tasks, tasks);
  if (shrink.length && !force) {
    core.die(`${core.CONTRACTS.state_semantics.snapshotMonotonic}: ${shrink.join('; ')} — restore the entries, or re-commit with --force (audit row what:snapshot-force)`);
  }
  const audit = (Array.isArray(existing.audit) ? existing.audit : []).slice();
  if (shrink.length && force) audit.push({ at: new Date().toISOString(), what: 'snapshot-force' });
  return { tasks, audit, meta };
}

function pushLazyFreezeLedger(state, what) {
  state.lazy_freeze_audit = [
    ...(Array.isArray(state.lazy_freeze_audit) ? state.lazy_freeze_audit : []),
    { at: new Date().toISOString(), what },
  ];
}

module.exports = { parsePlanMd, parsePlanRaw, buildPlanSnapshotTasks, validateWaveStructure, validateDeclaredPaths, buildEntryCheck, snapshotShrinkage, freezeOrRefreshPlanSnapshot, pushLazyFreezeLedger };
