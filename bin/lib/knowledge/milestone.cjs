// knowledge/milestone.cjs — knowledge module aspect: milestone lifecycle over project.json.
// Sibling requires are free; cross-directory requires go to core only.
'use strict';

const decisions = require('./decisions.cjs');
const phaseMod = require('./phase.cjs');


const fs = require('node:fs');
const path = require('node:path');
const core = require('../core/index.cjs');

// Repo-level Lv4 marker: one stable JSON line under .gos/project/. milestone
// open and init --project bootstrap are the seed writers; `gos track` at the
// adoption ceremony flips the file to tracked so Lv4-ness travels with clones.
const LV4_MARKER_LINE = '{"lv4":true}\n';

// Identity-time slug for milestone names: lowercase, non-alphanumerics
// collapse to single '-', leading/trailing '-' trimmed, capped at 40
// codepoints. Returns null for empty or bare-version reserved shapes — the
// stored form is always exactly what this function returns; snapshot names
// and archive slugs derive only from the stored form.
function sanitizeMilestoneName(raw) {
  const collapsed = String(raw == null ? '' : raw).toLowerCase()
    .replace(/[^0-9a-z]+/g, '-')
    .replace(/^-+/, '')
    .replace(/-+$/, '');
  const capped = Array.from(collapsed).slice(0, 40).join('')
    .replace(/^-+/, '')
    .replace(/-+$/, '');
  if (!capped || /^v[0-9]+$/.test(capped)) return null;
  return capped;
}

function writeLv4Marker() {
  fs.mkdirSync(core.PROJECT_DIR, { recursive: true });
  fs.writeFileSync(path.join(core.PROJECT_DIR, 'lv4.json'), LV4_MARKER_LINE);
}

// Close-time row disposition classes, in report order. The first four wipe
// with the milestone history; the last three survive the close.
const CLOSE_ROW_CLASSES = ['done-owned', 'null-phase', 'ghost', 'dropped', 'parked-owned', 'pending-owned', 'active-owned'];

// Classify one decision or requirement row against the phase array. The
// owning phase field is selected by row id prefix (decision rows carry
// birth_phase, requirement rows carry phase). Precedence, first match wins:
//   parked-owned   owner exists and is parked — survives verbatim, even when
//                  the row itself is dropped (the parked owner is the debt
//                  the next milestone must still see)
//   dropped        row.status === 'dropped' under any other owner shape —
//                  wiped as its own class
//   ghost          phase reference matches no phase entry (bare prefixes
//                  that survive normalization land here)
//   null-phase     phase reference is null/absent/empty
//   done-owned / pending-owned / active-owned  owner status mapping
// Anything else refuses (fail closed) — an unclassifiable row never reaches
// a wipe decision by accident.
function classifyRowDisposition(row, phases) {
  if (!row || typeof row !== 'object' || typeof row.id !== 'string') {
    core.die(core.t('milestone.closeUnknownRow'));
  }
  const field = /^D-/.test(row.id) ? 'birth_phase' : /^R-/.test(row.id) ? 'phase' : null;
  if (field === null) core.die(core.t('milestone.closeUnknownRowId', { id: row.id }));
  const ref = row[field];
  let owner = null;
  let ghost = false;
  if (ref === null || ref === undefined || ref === '') {
    owner = null;
  } else if (typeof ref !== 'string') {
    core.die(core.t('milestone.closeUnknownRow'));
  } else {
    owner = (Array.isArray(phases) ? phases : []).find((p) => p && p.name === ref) || null;
    ghost = owner === null;
  }
  if (owner && owner.status === 'parked') return 'parked-owned';
  if (row.status === 'dropped') return 'dropped';
  if (ghost) return 'ghost';
  if (owner === null) return 'null-phase';
  if (owner.status === 'done') return 'done-owned';
  if (owner.status === 'pending') return 'pending-owned';
  if (owner.status === 'active') return 'active-owned';
  core.die(core.t('milestone.closeUnknownPhaseStatus', { name: owner.name, status: String(owner.status) }));
}

// TEST-ONLY fault injection (mirrors the ship/track break hooks): each stage
// throws mid-flow so crash-window recovery can be exercised deterministically.
// Windows: validate (after validation, nothing written), snapshot (snapshots
// materialized and verified, project.json still whole, approval not consumed),
// wipe (project.json already wiped, views not yet re-rendered).
function closeBreak(stage) {
  if (process.env.GOS_TEST_BREAK_CLOSE === stage) {
    throw new Error(`GOS_TEST_BREAK_CLOSE: injected ${stage} failure`);
  }
}

// Validation domain of the close: milestone object present and open, no
// active phase (in-flight work refuses, naming the phase), parked phases only
// under --carry-parked, at least one done phase unless --empty.
function closeValidate(project, flags) {
  const ms = project.milestone;
  if (!ms || typeof ms !== 'object') core.die(core.t('milestone.closeNoMilestone', {}));
  if (ms.closed_at !== undefined) core.die(core.t('milestone.closeAlreadyClosed', { name: ms.name, ts: ms.closed_at }));
  const phases = Array.isArray(project.phases) ? project.phases : [];
  const active = phases.filter((p) => p && p.status === 'active').map((p) => p.name);
  if (active.length) core.die(core.t('milestone.closeRefusesActive', { phases: active.join(', ') }));
  const parked = phases.filter((p) => p && p.status === 'parked').map((p) => p.name);
  if (parked.length && !flags.carryParked) core.die(core.t('milestone.closeRefusesParked', { phases: parked.join(', ') }));
  if (!phases.some((p) => p && p.status === 'done') && !flags.empty) core.die(core.t('milestone.closeRefusesVacuum'));
}

// Bucket every decision and requirement row into its disposition class.
function closeClassifyAll(project) {
  const buckets = { decisions: {}, requirements: {} };
  for (const cls of CLOSE_ROW_CLASSES) { buckets.decisions[cls] = []; buckets.requirements[cls] = []; }
  for (const row of (Array.isArray(project.decisions) ? project.decisions : [])) {
    buckets.decisions[classifyRowDisposition(row, project.phases)].push(row);
  }
  for (const row of (Array.isArray(project.requirements) ? project.requirements : [])) {
    buckets.requirements[classifyRowDisposition(row, project.phases)].push(row);
  }
  return buckets;
}

// The per-ID disposition report (audit artifact): per family, per class,
// count and row ids; plus the phase wipe/carry split. Built from the
// pre-close project state; the executor builds it before the wipe and
// prints it only after.
function closeReportLines(project, buckets) {
  const lines = [core.t('milestone.closeReportTitle', {})];
  const labelFor = {
    'done-owned': core.t('milestone.closeClassDoneOwned'),
    'null-phase': core.t('milestone.closeClassNullPhase'),
    ghost: core.t('milestone.closeClassGhost'),
    dropped: core.t('milestone.closeClassDropped'),
    'parked-owned': core.t('milestone.closeClassParkedOwned'),
    'pending-owned': core.t('milestone.closeClassPendingOwned'),
  };
  const idNum = (id) => parseInt((/^[DR]-(\d+)$/.exec(String(id)) || [0, 0])[1], 10) || 0;
  const family = (header, rows) => {
    lines.push(header);
    for (const cls of CLOSE_ROW_CLASSES) {
      if (cls === 'active-owned') continue; // validation refuses active owners before any report
      const ids = rows[cls].map((r) => r.id).sort((a, b) => idNum(a) - idNum(b));
      lines.push(`  ${labelFor[cls]} (${ids.length}): ${ids.length ? ids.join(', ') : core.t('milestone.closeNone')}`);
    }
  };
  family(core.t('milestone.closeRowsDecisions', { n: (Array.isArray(project.decisions) ? project.decisions : []).length }), buckets.decisions);
  family(core.t('milestone.closeRowsRequirements', { n: (Array.isArray(project.requirements) ? project.requirements : []).length }), buckets.requirements);
  const phases = Array.isArray(project.phases) ? project.phases : [];
  lines.push(core.t('milestone.closeRowsPhases', { n: phases.length }));
  const namesOf = (status) => phases.filter((p) => p && p.status === status).map((p) => p.name);
  for (const [status, key] of [['done', 'milestone.closePhasesWiped'], ['parked', 'milestone.closePhasesCarriedParked'], ['pending', 'milestone.closePhasesCarriedPending']]) {
    const names = namesOf(status);
    lines.push(`  ${core.t(key, { n: names.length })}: ${names.length ? names.join(', ') : core.t('milestone.closeNone')}`);
  }
  return lines;
}

// Resolve the archive channel home for the closing milestone-record: the
// last done phase carrying a task_ref whose archive directory exists on
// disk (stat-verified), else a synthesized dated close directory. Never
// guesses — an unresolvable task_ref simply does not win.
function closeArchiveRecordDir(project, name, date) {
  const phases = Array.isArray(project.phases) ? project.phases : [];
  for (let i = phases.length - 1; i >= 0; i--) {
    const ph = phases[i];
    if (!ph || ph.status !== 'done' || typeof ph.task_ref !== 'string' || !ph.task_ref) continue;
    const dir = path.join(core.ARCHIVE_DIR, ph.task_ref);
    let st = null;
    try { st = fs.statSync(dir); } catch { st = null; }
    if (st && st.isDirectory()) return path.join(dir, 'milestone-record');
  }
  return path.join(core.ARCHIVE_DIR, `${date}-${name}-close`, 'milestone-record');
}

// Dual-channel snapshot: byte copies (never re-renders — MANUAL regions
// survive byte-for-byte) of the pre-close project.json and the on-disk
// rendered views, under dated names that never overwrite, into both
// .gos/project/milestones/ and the archive milestone-record. Every target
// is stat-verified (exists, size > 0) before the caller may proceed to the
// wipe; any failure dies closed.
function closeSnapshot(project, name, date) {
  const rel = (p) => path.relative('.', p);
  const parts = [
    { src: path.join(core.PROJECT_DIR, 'project.json'), base: `${name}-${date}-preclose.json` },
    { src: path.join(core.PROJECT_DIR, 'ROADMAP.md'), base: `${name}-${date}-ROADMAP.md` },
    { src: path.join(core.PROJECT_DIR, 'REQUIREMENTS.md'), base: `${name}-${date}-REQUIREMENTS.md` },
    { src: path.join(core.PROJECT_DIR, 'DECISIONS.md'), base: `${name}-${date}-DECISIONS.md` },
  ];
  const dirs = [path.join(core.PROJECT_DIR, 'milestones'), closeArchiveRecordDir(project, name, date)];
  const targets = [];
  for (const dir of dirs) for (const p of parts) targets.push({ src: p.src, dst: path.join(dir, p.base) });
  for (const t of targets) {
    let st = null;
    try { st = fs.statSync(t.src); } catch { st = null; }
    if (!st || st.size <= 0) core.die(core.t('milestone.closeSnapshotSourceMissing', { path: rel(t.src) || t.src }));
  }
  for (const t of targets) {
    if (fs.existsSync(t.dst)) core.die(core.t('milestone.closeSnapshotExists', { path: rel(t.dst) || t.dst }));
  }
  for (const t of targets) {
    fs.mkdirSync(path.dirname(t.dst), { recursive: true });
    fs.copyFileSync(t.src, t.dst);
    console.log(core.t('milestone.closeSnapshotLine', { src: rel(t.src) || t.src, dst: rel(t.dst) || t.dst }));
  }
  for (const t of targets) {
    let st = null;
    try { st = fs.statSync(t.dst); } catch { st = null; }
    if (!st || st.size <= 0) core.die(core.t('milestone.closeSnapshotVerifyFail', { path: rel(t.dst) || t.dst }));
  }
  console.log(core.t('milestone.closeSnapshotsDone', { n: targets.length }));
  return targets;
}

// The approval IS the code gate: --yes requires state.approvals
// MILESTONE-CLOSE (single-use, fresh within 24h). consume=true deletes the
// record and persists state.json in the same run. Missing/stale/malformed
// dies with the approve hint.
function closeApprovalGate(consume) {
  const state = core.readState();
  const rec = state && state.approvals ? state.approvals['MILESTONE-CLOSE'] : undefined;
  if (rec === undefined) core.die(core.t('milestone.closeApproveMissing', {}));
  const ts = typeof rec === 'string' ? rec : (rec && typeof rec === 'object' && typeof rec.ts === 'string' ? rec.ts : null);
  const parsed = ts === null ? NaN : Date.parse(ts);
  if (!Number.isFinite(parsed) || Date.now() - parsed > 24 * 60 * 60 * 1000) {
    core.die(core.t('milestone.closeApproveStale', {}));
  }
  if (consume) {
    delete state.approvals['MILESTONE-CLOSE'];
    core.writeState(state);
    console.log(core.t('milestone.closeApprovalConsumed', {}));
  }
  return ts;
}

// In-memory wipe: done-owned, null-phase, ghost and dropped rows go; rows
// owned by parked/pending phases stay verbatim; done phase entries go,
// parked/pending entries stay verbatim; the milestone is stamped closed and
// last_archived_phase resets. Classification happens against the FULL phase
// array, so rows are filtered before phases.
function closeApplyWipe(project) {
  const keep = new Set(['parked-owned', 'pending-owned']);
  const rowFilter = (rows) => rows.filter((row) => {
    const cls = classifyRowDisposition(row, project.phases);
    if (cls === 'active-owned') core.die(core.t('milestone.closeInvariantActive', { id: row.id }));
    return keep.has(cls);
  });
  project.decisions = rowFilter(Array.isArray(project.decisions) ? project.decisions : []);
  project.requirements = rowFilter(Array.isArray(project.requirements) ? project.requirements : []);
  project.phases = (Array.isArray(project.phases) ? project.phases : []).filter((ph) => {
    if (!ph) return false;
    if (ph.status === 'done') return false;
    if (ph.status === 'parked' || ph.status === 'pending') return true;
    core.die(core.t('milestone.closeInvariantPhase', { name: String(ph.name), status: String(ph.status) }));
  });
  project.milestone.closed_at = new Date().toISOString();
  project.last_archived_phase = null;
}

// Close flow (runs inside the .gos/.lock critical section the write-class
// dispatch already holds): normalize row phase refs in memory, validate,
// classify. Without --yes: dry run — print the disposition, write nothing.
// With --yes: approval gate, final full render, dual-channel dated
// snapshots, consume-once approval, single atomic project write, re-render,
// then the report (the disposition report never prints before the wipe in
// the same invocation).
function closeMilestone(flags) {
  const project = core.loadProject();
  if (!project) core.die(core.t('milestone.closeNoProject', {}));
  core.normalizeRowPhaseRefs(project.decisions, project.phases, 'birth_phase');
  core.normalizeRowPhaseRefs(project.requirements, project.phases, 'phase');
  closeValidate(project, flags);
  closeBreak('validate');
  const buckets = closeClassifyAll(project);
  if (!flags.yes) {
    console.log(core.t('milestone.closeDryRunBanner', {}));
    for (const line of closeReportLines(project, buckets)) console.log(line);
    console.log(core.t('milestone.closeDryRunNext', {}));
    return;
  }
  closeApprovalGate(false);
  decisions.autoRenderViews(project);
  const report = closeReportLines(project, buckets);
  const date = new Date().toISOString().slice(0, 10);
  closeSnapshot(project, project.milestone.name, date);
  closeBreak('snapshot');
  closeApprovalGate(true);
  closeApplyWipe(project);
  core.saveProject(project);
  closeBreak('wipe');
  decisions.autoRenderViews(project);
  for (const line of report) console.log(line);
  console.log(core.t('milestone.closed', { name: project.milestone.name, ts: project.milestone.closed_at }));
  console.log(core.t('milestone.nextAfterClose', {}));
}

// Open semantics shared by `gos milestone open <name>` and the init --project
// bootstrap: refuse while an unclosed milestone lives (name it, point to
// close); a closed milestone is replaced by a fresh object; write
// {name, opened_at}, seed the repo marker, keep rendered views fresh. The
// publicize render is skipped when handwritten view content is on disk —
// the brownfield import cure (`gos decision import --all`) needs those rows
// in place, and the brownfield warning has already named them; the next
// mutation or explicit render re-renders over the imported truth.
function openMilestone(rawName) {
  const name = sanitizeMilestoneName(rawName);
  if (name === null) {
    core.die(core.t('milestone.badName', { raw: core.sanitizeEcho(String(rawName == null ? '' : rawName)) }));
  }
  let project = core.loadProject();
  if (!project) project = core.emptyProject(); // legit creation point (with init --project and phase add)
  const live = project.milestone;
  if (live && live.closed_at === undefined) {
    core.die(core.t('milestone.openRefusesOpen', { name: live.name }));
  }
  project.milestone = { name, opened_at: new Date().toISOString() };
  core.saveProject(project);
  writeLv4Marker();
  if (!phaseMod.detectBrownfield()) decisions.autoRenderViews(project);
  return { project, name };
}

function cmdMilestone(args) {
  const sub = (args[0] || '').toLowerCase();
  const rest = args.slice(1);

  if (sub === 'open') {
    const pos = rest.filter((a) => !a.startsWith('--'));
    if (!pos.length) core.die('Usage: gos milestone open <name>');
    const raw = pos.join(' ');
    const { name } = openMilestone(raw);
    if (name !== raw) console.log(core.t('milestone.openSanitized', { name, raw: core.sanitizeEcho(raw) }));
    console.log(core.t('milestone.opened', { name }));
    console.log(core.t('milestone.nextAfterOpen'));
    return;
  }

  if (sub === 'close') {
    const known = ['--carry-parked', '--yes', '--empty'];
    const stray = rest.filter((a) => !known.includes(a));
    if (stray.length) core.die('Usage: gos milestone close [--carry-parked] [--yes] [--empty]');
    closeMilestone({
      carryParked: rest.includes('--carry-parked'),
      yes: rest.includes('--yes'),
      empty: rest.includes('--empty'),
    });
    return;
  }

  console.log('Usage: gos milestone open <name> | gos milestone close [--carry-parked] [--yes] [--empty]');
  console.log('  open <name>   open a milestone cycle (name is slug-sanitized at identity; the stored slug is the identity)');
  console.log('  close         close the open milestone: dry-run disposition by default; --yes executes the wipe under dated snapshots (approval-gated)');
}

Object.assign(module.exports, {
  cmdMilestone,
  sanitizeMilestoneName,
  writeLv4Marker,
  openMilestone,
  classifyRowDisposition,
  closeMilestone,
});   // assignment (not reassignment): sibling modules hold live references to this export
