// render/views — view/command implementations that consume core + map.
'use strict';

const core = require('../core/index.cjs');
const map = require('../map/index.cjs');
const fs = require('fs');
const path = require('path');

const RENDERED_HEADER = core.CONTRACTS.command_contracts.generatedHeader;

// D-05 scope: active phase + 2 phases before it (by project.phases order).
// No active phase → last 3 phases. Unknown birth_phase (not in phases[]) → always included.

// D-08 backup: only meaningful when the full rendered set exists; history is
// kept in full — expiry (14d rolling sweep) runs on the render entry.

// D-05 atomic protocol: write ALL temps first, then rename ALL; any rename failure →
// restore already-renamed files from the pre-render content and die (never a torn set).

// gap-C handoff block: paste-able fresh-session continuation (commit tails + `gos next`
// tail). References the CURRENT stage's skill — the work you land on after resume.

// gap-A DONE-state hint: discriminate archived vs unarchived; derive pending phases
// from project.json (state-machine purity — position-derived, never context-guessed).
// Symptom history: 5+ mis-navigations 2026-08-24~25 (archived DONE still hinting archive).

// ---------- plan.md parser (OpenSpec-style artifact awareness) ----------

// ---------- Phase B (T2): plan_snapshot freeze [B-15] + freeze-field helpers ----------

// R4-F6 pinned schema: plan_snapshot.tasks = [{id, covers: [D-NN…], files: [path…]}].
// Files comma-split + trim; a single entry containing whitespace is illegal (exit 1).

// B-15 monotonicity: ∪Files and per-task Covers may only GROW vs the existing snapshot.
// Returns the list of shrinkage descriptions (empty = legal refresh).

// B-15 [R2-3] refresh double constraint: ① only current_stage==='PLAN' may refresh an
// existing snapshot (BUILD+ re-commit plan → exit 1); ② monotonic check — shrinkage
// needs --force and writes an audit row what:'snapshot-force'.

// F1 lazy-freeze ledger: uniform home for both lazy-freeze events (plan + spec),
// queryable by later mounts (T7 status/consistency checks).

// ---------- structured next-actions (OpenSpec navigator pattern) ----------

// ---------- commands ----------

// D-30 two-stage level parse (R4-F1): wide lv-like match first, strict inner parse,
// fail-closed die for lv-like-but-invalid; non-lv-like → null (falls to intent text).
// `v1` (no leading l) is NOT lv-like → intent text (spec grammar `[Ll][Vv]?<digits>`).

// ---------- D-01: gos context <stage> (pre-computed context JSON) ----------

// ---------- Phase U follow-up: curated concerns join THINK/PLAN context (D-41 symmetry) ----------
// BUILD/REVIEW already consume .gos/concerns.md (five-piece wiring #5); THINK/PLAN were
// the gap — phase P-type tasks design decisions in THINK, exactly when curated worries
// (e.g. map blast-linked items) must be visible. Non-empty file only; empty = no noise entry.
// Top-level fn declaration REQUIRED: phase-P T36.3d pins acorn(top-level)==regex(line-start).

// ---------- D-02: gos checkpoint save ----------

// ---------- Phase B (T7): commit-embedded semantic checks [D-33/B-10/B-22, F1/R4-F1/F7] ----------
// Layer 3 of the three-layer mount: gate semantic standalone + gate all chained + THIS —
// BUILD/VERIFY commit embeds the SAME ops.semanticChecks() (non-copy) so the model cannot bypass.

// B-10 escape hatch: only GOS_TEST_SANDBOX=<abs path> whose realpath strictly equals the
// project root activates GOS_SKIP_SEMANTIC=1. Bare skip in production → hard refusal.

// T8: does an archive dir exist for today's base slug (exact, or -2/-3 collision suffix)?

// Phase C (T4, D-15): help — three modes, ALL rendered from COMMANDS registry
// (hand-written lists forbidden; T29-4/5 assert derivation).
//   gos help            human-readable, grouped by class (row grammar below)
//   gos help <cmd>      per-command detail page (alias resolution → host entry)
//   gos help --json     machine envelope (sole legal machine mode — see
//                       semantic_checks.jsonMachineMode; strict JSON from byte 0)
// Row grammar (canonical, T29-4 anchors here): command rows match
//   ^  (\(no command\)|[a-z_][a-z0-9_-]*)\s{2,}\S
// (two-space indent, ≥2 spaces separator; sentinel captured as one token;
//  char class includes underscore — real command name '_contract' — spec refrozen).

// ---------- requirement command family (T4): add | list | drop | claim ----------

// ---------- T8: phase command family — add | list | claim | unclaim ----------
// Lv4 lifecycle: add (pending) → claim (fresh Lv3 state per phase, gated on DONE + prev archived)
// → archive (merges back into project.json, marks done) → repeat → milestone reset.

// ---------- Phase B (T3): lessons command family — dual-file + sidecar anchors + audit chain ----------
// D-29/D-32/D-34 + B-7/9/13/14/18/19. [model]→~/.config/gos/lessons.md (os.homedir() joined,
// never literal ~), [project]→.gos/lessons.md. Anchors: per-file sidecar json
// {hashes[16hex], chain_head, audit[]} — NOT in state.json (D-32 symmetric, cross-repo global).

// ---------- truth command family — auto-numbered add (ids continue from existing) + manual/replay verify + receipts ----------
// B-1/B-19/B-20. `truth add` auto-numbers T1/T2… (max existing numeric id + 1, both
// T1 and legacy T-01 forms scanned). `truth verify` manual mode = T2 three-element
// validator (validateEvidenceObject, R4-F14 single consumption point) + manual:true;

const MANUAL_MARKER = core.CONTRACTS.command_contracts.manualMarker;
// D-08 (R-29): backups are machine-local cache under .gos/cache/render-backup —
// full history (no rotation), 14d rolling expiry swept on render entry.
const RENDER_BACKUP_DIR = core.resolvePath('render_backup');
const LEGACY_RENDER_BACKUP_DIR = path.join(core.ARCHIVE_DIR, 'render-backup');
const RENDER_BACKUP_MAX_AGE_MS = 14 * 24 * 60 * 60 * 1000;
// Strict timestamp-dir gate (D-08/R2-5): prefix filter is the classification
// contract; junk NEVER gets recursed into or removed.
const TS_DIR_PREFIX_RE = /^\d{4}-\d{2}-\d{2}T/;
// Full shape: 2026-10-15T12-34-56-789Z (fs-safe ISO, fixed-width → sortable).
const TS_DIR_FULL_RE = /^(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})-(\d{3})Z$/;
// T8 hook: entries silently skipped by name at the backup root — the last-render
// manifest rides the backup root (it is the manifest, not junk); warn+skip stays
// the default for everything else.
const RENDER_BACKUP_SILENT_SKIP = new Set(['manifest.json']);
const VIEW_NAMES = ['DECISIONS.md', 'ROADMAP.md', 'REQUIREMENTS.md'];
// D-03/R3-F1 last-render manifest: content hashes of the three view bodies
// (footer + MANUAL region stripped), written in the same rename batch as the views.
const MANIFEST_PATH = path.join(RENDER_BACKUP_DIR, 'manifest.json');

function renderBackupWarn(msg) {
  console.error(`⚠ [render-backup] ${msg}`);
}

function backupStampMs(name) {
  const m = name.match(TS_DIR_FULL_RE);
  if (!m) return NaN;
  return Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6], +m[7]);
}

// D-08 one-shot migration: timestamp dirs move from the legacy archive path to
// the cache dir; junk (non-timestamp names, symlinks, non-dirs) STAYS BEHIND
// with a warning — never recursed into, never deleted. Same strict filter as
// the sweep (R2-5).
function migrateLegacyRenderBackup() {
  let st;
  try { st = fs.lstatSync(LEGACY_RENDER_BACKUP_DIR); } catch { return; }
  if (st.isSymbolicLink() || !st.isDirectory()) {
    renderBackupWarn(`migration: legacy path is not a directory, skipping: ${LEGACY_RENDER_BACKUP_DIR}`);
    return;
  }
  for (const name of fs.readdirSync(LEGACY_RENDER_BACKUP_DIR)) {
    let est;
    try { est = fs.lstatSync(path.join(LEGACY_RENDER_BACKUP_DIR, name)); } catch { continue; }
    if (est.isSymbolicLink() || !est.isDirectory() || !TS_DIR_PREFIX_RE.test(name)) {
      renderBackupWarn(`migration: leaving non-timestamp entry behind: ${name}`);
      continue;
    }
    const dest = path.join(RENDER_BACKUP_DIR, name);
    if (fs.existsSync(dest)) continue; // already migrated — idempotent re-run
    try {
      fs.mkdirSync(RENDER_BACKUP_DIR, { recursive: true });
      fs.renameSync(path.join(LEGACY_RENDER_BACKUP_DIR, name), dest);
    } catch (e) {
      renderBackupWarn(`migration failed for ${name}: ${e.message}`);
    }
  }
  try {
    if (fs.readdirSync(LEGACY_RENDER_BACKUP_DIR).length === 0) fs.rmdirSync(LEGACY_RENDER_BACKUP_DIR);
  } catch { /* junk remains behind — warnings above already name it */ }
}

// D-08 expiry sweep (rides the render entry, not a separate command): entries
// older than 14 days are removed, EXCEPT the newest backup — hard floor, never
// deleted even when judged expired (clock rolled back). Every entry is lstat'd:
// symlinks and non-directories warn+skip and are never traversed (cache/ is an
// ignored zone — rmSync must not chase attacker-planted links); future-dated
// name-stamps warn+skip (clock rolled forward).
function sweepRenderBackups() {
  let entries;
  try { entries = fs.readdirSync(RENDER_BACKUP_DIR); } catch { return; }
  const now = Date.now();
  const candidates = [];
  for (const name of entries) {
    if (RENDER_BACKUP_SILENT_SKIP.has(name)) continue; // T8: named skip-list hook
    let st;
    try { st = fs.lstatSync(path.join(RENDER_BACKUP_DIR, name)); } catch { continue; }
    if (st.isSymbolicLink() || !st.isDirectory()) {
      renderBackupWarn(`sweep: skipping non-directory entry: ${name}`);
      continue;
    }
    if (!TS_DIR_PREFIX_RE.test(name)) {
      renderBackupWarn(`sweep: skipping non-timestamp entry: ${name}`);
      continue;
    }
    const stamp = backupStampMs(name);
    if (Number.isNaN(stamp)) {
      renderBackupWarn(`sweep: skipping unparseable timestamp entry: ${name}`);
      continue;
    }
    if (stamp > now) {
      renderBackupWarn(`sweep: skipping future-stamped entry: ${name}`);
      continue;
    }
    candidates.push({ name, stamp });
  }
  if (!candidates.length) return;
  const newestStamp = Math.max(...candidates.map((c) => c.stamp));
  for (const c of candidates) {
    if (now - c.stamp <= RENDER_BACKUP_MAX_AGE_MS) continue; // still young
    if (c.stamp === newestStamp) continue; // hard floor: newest never deleted
    try { fs.rmSync(path.join(RENDER_BACKUP_DIR, c.name), { recursive: true, force: true }); }
    catch (e) { renderBackupWarn(`sweep failed for ${c.name}: ${e.message}`); continue; }
    console.error(`- [render-backup] sweep: expired entry removed: ${c.name}`);
  }
}

// D-03/R3-F1 diff basis: view content minus the generated-at footer and the
// MANUAL region — the stable identity of a rendered body (the footer timestamp
// and preserved manual content must never influence the change decision).
function stripViewBody(content) {
  const lines = String(content).split('\n');
  const markerIdx = lines.findIndex((l) => l.trim() === MANUAL_MARKER);
  const manual = markerIdx !== -1;
  const body = (manual ? lines.slice(0, markerIdx) : lines)
    .filter((l) => !/^<!-- generated at .+ -->$/.test(l.trim()))
    .join('\n');
  return { body, manual };
}

// D-03/R3-F1 last-render manifest gate: the renderer refuses to clobber view
// content it cannot vouch for. Provenance = the GENERATED header (line 1) —
// init skeletons and handwritten brownfield views are NOT gated (the import
// flow stays untouched); rendered views without a matching manifest (fresh
// clone — .gos/cache does not travel) are. Returns null (proceed) or the
// self-describing refusal reason.
function renderManifestRefusal() {
  const states = {};
  let tracked = 0;
  for (const n of VIEW_NAMES) {
    let text = null;
    try { text = fs.readFileSync(path.join(core.PROJECT_DIR, n), 'utf8'); } catch { text = null; }
    if (text === null) continue;
    const rendered = (text.split('\n')[0] || '').trim() === RENDERED_HEADER;
    states[n] = { ...stripViewBody(text), rendered };
    if (rendered) tracked++;
  }
  if (!tracked) return null;
  const reconcile = 'Reconcile: move content you want to keep into the MANUAL region, or re-run with: gos render --force';
  let mf = null;
  try { mf = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8')); } catch { mf = null; }
  if (!mf || !mf.views || typeof mf.views !== 'object') {
    return `last-render manifest (.gos/cache/render-backup/manifest.json) missing or unreadable while rendered views exist — .gos/cache does not travel with a clone. ${reconcile}`;
  }
  for (const n of VIEW_NAMES) {
    if (!states[n] || !states[n].rendered) continue;
    const e = mf.views[n];
    if (!e || typeof e.body_hash !== 'string') return `${n}: no manifest entry (manifest and views disagree). ${reconcile}`;
    if (e.body_hash !== core.sha16(states[n].body)) return `${n}: body differs from the last render (hand edit detected) — generated bodies are renderer-owned. ${reconcile}`;
    if (e.manual === true && !states[n].manual) return `${n}: MANUAL region present at last render is now missing — restore it (or its content) from .gos/cache/render-backup. ${reconcile}`;
  }
  return null;
}

// Skip-path manifest touch-up: a MANUAL marker added after the last render is
// legal (preserved verbatim) — recording it keeps a later marker LOSS refusable.
function syncManifestManualFlags(prevStripped) {
  let mf = null;
  try { mf = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8')); } catch { return; }
  if (!mf || !mf.views || typeof mf.views !== 'object') return;
  let drifted = false;
  for (const n of VIEW_NAMES) {
    const e = mf.views[n];
    if (!e || typeof e !== 'object') continue;
    const manual = !!(prevStripped[n] && prevStripped[n].manual);
    if (e.manual !== manual) { e.manual = manual; drifted = true; }
  }
  if (drifted) core.writeAtomicJson(MANIFEST_PATH, mf);
}

// R2-F10: a killed render leaves .tmp<pid> temps behind; dead-pid ones are
// swept at the render entry, live-pid ones are somebody's in-flight write and stay.
function sweepOrphanTemps() {
  const zones = [
    { dir: core.PROJECT_DIR, re: /^\.(?:DECISIONS|ROADMAP|REQUIREMENTS)\.md\.tmp(\d+)$/ },
    { dir: RENDER_BACKUP_DIR, re: /^\.manifest\.json\.tmp(\d+)-\d+$/ },
  ];
  for (const z of zones) {
    let entries;
    try { entries = fs.readdirSync(z.dir); } catch { continue; }
    for (const name of entries) {
      const m = name.match(z.re);
      if (!m) continue;
      const pid = parseInt(m[1], 10);
      if (pid === process.pid || core.pidAlive(pid)) continue;
      try { fs.unlinkSync(path.join(z.dir, name)); } catch { /* racing */ }
    }
  }
}

function renderPathsMarkdown() {
  const lines = [];
  lines.push(`${core.CONTRACTS.command_contracts.readmeHeader} — do not edit; regen: gos paths --markdown -->`);
  lines.push('# .gos/ Directory Map (auto-generated)');
  lines.push('');
  lines.push('Every artifact under .gos/: who writes it, who reads it, when it can be deleted.');
  lines.push('');
  const emit = (title, entries) => {
    if (!entries.length) return;
    lines.push(`## ${title}`);
    lines.push('');
    lines.push('| Path | Producer | Readers | Purge policy | Tracked |');
    lines.push('|:--|:--|:--|:--|:--|');
    for (const [, e] of entries) lines.push(`| \`${e.rel}\` | ${e.producer} | ${e.readers} | ${e.purge} | ${e.tracked ? 'yes' : 'no'} |`);
    lines.push('');
  };
  const entries = Object.entries(core.GOS_PATHS);
  const rootFiles = entries.filter(([, e]) => !e.rel.includes('/') && !e.rel.startsWith('.') && e.granularity === 'file');
  const rootDirs = entries.filter(([, e]) => !e.rel.includes('/') && !e.rel.startsWith('.') && e.granularity === 'dir');
  emit('Root — global truth sources (files)', rootFiles);
  emit('Root — CLI directories (dir-registered prefix zones)', rootDirs);
  emit('cache/ — machine caches (git-ignored, safe to delete any time)', entries.filter(([, e]) => e.rel.startsWith('cache/')));
  emit('logs/ — runtime state, machine-local', entries.filter(([, e]) => e.rel.startsWith('logs/')));
  emit('task/&lt;id&gt;/ — per-phase in-flight artifacts (dynamic, resolved per active task)', entries.filter(([, e]) => e.rel.startsWith('task/')));
  emit('Transient zones (orphan-scan excluded)', entries.filter(([, e]) => e.rel.startsWith('.')));
  // Published feedback ledger — the ONLY feedback data that renders here.
  // Guarded by existsSync: a missing FEEDBACK.md renders nothing (byte-stable),
  // drafts under project/feedback/ never appear (untracked feedstock).
  const ledgerFile = core.resolvePath('feedback_ledger');
  if (fs.existsSync(ledgerFile)) {
    const rows = fs.readFileSync(ledgerFile, 'utf8').split(/\r?\n/).filter((l) => l.startsWith('|'));
    if (rows.length) {
      lines.push('## Feedback (published)');
      lines.push('');
      for (const r of rows) lines.push(r);
      lines.push('');
    }
  }
  lines.push('## Layout rules');
  lines.push('');
  lines.push('- Agent artifacts never appear at .gos/ root — they live under `task/<id>/` (supplied via `gos context <stage>` artifact_paths).');
  lines.push('- Anything not listed above is an orphan: `gos gate` reports it (advisory), `gos commit ship` adopts it into `archive/<date>-orphans/`.');
  lines.push('- `archive/` is the history zone — safe to batch-prune after a milestone (git history is the net).');
  lines.push('- This README is generated — never hand-edit (gate verifies regen diff is empty).');
  return lines.join('\n') + '\n';
}

function scopedPhaseSet(project) {
  const names = project.phases.map((p) => p && p.name).filter((n) => typeof n === 'string');
  const activeIdx = project.phases.findIndex((p) => p && p.status === 'active');
  const from = activeIdx === -1 ? Math.max(0, names.length - 3) : Math.max(0, activeIdx - 2);
  const to = activeIdx === -1 ? names.length : activeIdx + 1;
  return { included: new Set(names.slice(from, to)), known: new Set(names) };
}

function renderDecisionsMd(project) {
  const { included, known } = scopedPhaseSet(project);
  const lines = [
    RENDERED_HEADER,
    '# Decision Index (active + last 2 phases)',
    '',
    '| ID | Decision | Rationale | Phase | Status |',
    '|:---|:---|:---|:---|:---|',
  ];
  const rows = [...project.decisions]
    .sort((a, b) => core.idNum('D', a.id) - core.idNum('D', b.id))
    .filter((d) => included.has(d.birth_phase) || !known.has(d.birth_phase));
  for (const d of rows) {
    const title = d.status === 'superseded' ? `~~${core.escCell(d.title)}~~` : core.escCell(d.title);
    lines.push(`| ${core.escCell(d.id)} | ${title} | ${core.escCell(d.rationale || '')} | ${core.escCell(d.birth_phase || '')} | ${core.escCell(d.status || 'open')} |`);
  }
  return lines.join('\n') + '\n';
}

function renderRoadmapMd(project) {
  const lines = [RENDERED_HEADER, '# Roadmap', '', '| Phase | Goal | Status |', '|:---|:---|:---|'];
  for (const p of project.phases) lines.push(`| ${core.escCell(p.name)} | ${core.escCell(p.goal)} | ${core.escCell(p.status)} |`);
  return lines.join('\n') + '\n';
}

function renderRequirementsMd(project) {
  const lines = [RENDERED_HEADER, '# Requirements', '', '| ID | Requirement | Phase | Status |', '|:---|:---|:---|:---|'];
  const rows = [...project.requirements].sort((a, b) => core.idNum('R', a.id) - core.idNum('R', b.id));
  for (const r of rows) lines.push(`| ${core.escCell(r.id)} | ${core.escCell(r.text)} | ${core.escCell(r.phase || '-')} | ${core.escCell(r.status || 'active')} |`);
  return lines.join('\n') + '\n';
}

function backupRenderedViews(names) {
  const ts = new Date().toISOString().replace(/[:.]/g, '-'); // fs-safe, fixed-width → lexicographic = chronological
  const dest = path.join(RENDER_BACKUP_DIR, ts);
  fs.mkdirSync(dest, { recursive: true });
  for (const n of names) fs.copyFileSync(path.join(core.PROJECT_DIR, n), path.join(dest, n));
  // D-08: full history — no rotation here; the 14d sweep rides the render entry.
}

function renderProjectViews(project, opts = {}) {
  const p = project || core.loadProject();
  if (!p) return null;
  const force = !!opts.force;
  const auto = !!opts.auto; // mutation-driven: diff-skip + refusal carries the auto prefix
  fs.mkdirSync(core.PROJECT_DIR, { recursive: true });
  // D-08: migration + expiry sweep ride the render entry (not a separate command).
  migrateLegacyRenderBackup();
  sweepRenderBackups();
  sweepOrphanTemps();
  // D-03/R3-F1: manifest gate — rendered bodies are renderer-owned; hand-edited
  // or unvouched content refuses instead of being silently destroyed. --force
  // is the explicit reconcile exit.
  if (!force) {
    const refusal = renderManifestRefusal();
    if (refusal) core.die(`${auto ? 'auto-render' : 'render'} refused: ${refusal}`);
  }
  const names = VIEW_NAMES;
  // Phase V [R1-F8]: self-describing footer — generated views carry write-time snapshot
  // semantics (residual rows keep their last-written status forever, D-08); point readers
  // at the live merged views so a frozen 'active' row never misleads again.
  const snapshotFooter = `\n<!-- generated at ${new Date().toISOString()} after phase ${p.last_archived_phase || '(milestone reset)'} — row status is a write-time snapshot, not a live lifecycle; live merged view: gos decision list --all / gos requirement list --all -->`;
  const bodies = {
    'DECISIONS.md': renderDecisionsMd(p),
    'ROADMAP.md': renderRoadmapMd(p),
    'REQUIREMENTS.md': renderRequirementsMd(p),
  };
  const prev = {};
  const prevStripped = {};
  for (const n of names) {
    const f = path.join(core.PROJECT_DIR, n);
    prev[n] = fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : null;
    prevStripped[n] = prev[n] === null ? null : stripViewBody(prev[n]);
  }
  // D-03 R1-F4: diff on footer-free stripped bodies — a no-change mutation
  // writes nothing at all (footer timestamp only advances when body content
  // changed; no backup churn). Explicit `gos render` (and archive renders)
  // stay write-through renders.
  if (auto && names.every((n) => prevStripped[n] !== null && core.sha16(prevStripped[n].body) === core.sha16(bodies[n]))) {
    syncManifestManualFlags(prevStripped);
    return { rendered: [], skipped: true };
  }
  // D-03 R1-F4: backup AFTER the diff decision — a no-change render never
  // churns the backup history. Partial view sets back up what EXISTS: an
  // all-or-nothing gate would leave a handwritten sibling view unbacked and
  // silently destroyed by the first render (review #5).
  const existingViews = names.filter((n) => prev[n] !== null);
  if (existingViews.length) backupRenderedViews(existingViews);
  const manifest = { schema_version: 1, views: {} };
  for (const n of names) {
    manifest.views[n] = { body_hash: core.sha16(bodies[n]), manual: !!(prevStripped[n] && prevStripped[n].manual) };
  }
  const prevManifest = fs.existsSync(MANIFEST_PATH) ? fs.readFileSync(MANIFEST_PATH, 'utf8') : null;
  const temps = {};
  const renamed = [];
  try {
    fs.mkdirSync(RENDER_BACKUP_DIR, { recursive: true });
    for (const n of names) {
      const manual = prev[n] === null ? null : map.manualRegion(prev[n]);
      const content = manual ? bodies[n] + snapshotFooter + '\n' + manual : bodies[n] + snapshotFooter; // rendered + footer + one blank line + MANUAL verbatim
      temps[n] = { tmp: path.join(core.PROJECT_DIR, `.${n}.tmp${process.pid}`), final: path.join(core.PROJECT_DIR, n) };
      fs.writeFileSync(temps[n].tmp, content);
    }
    // D-03/R3-F1: the manifest joins the SAME rename batch — views and manifest
    // land together or not at all.
    temps.__manifest__ = { tmp: path.join(RENDER_BACKUP_DIR, `.manifest.json.tmp${process.pid}-${Date.now()}`), final: MANIFEST_PATH };
    fs.writeFileSync(temps.__manifest__.tmp, JSON.stringify(manifest, null, 2) + '\n');
    for (const n of [...names, '__manifest__']) {
      fs.renameSync(temps[n].tmp, temps[n].final);
      renamed.push(n);
    }
  } catch (e) {
    if (renamed.includes('__manifest__')) {
      try {
        if (prevManifest === null) fs.unlinkSync(MANIFEST_PATH);
        else fs.writeFileSync(MANIFEST_PATH, prevManifest);
      } catch { /* best-effort restore */ }
    }
    for (const n of renamed) {
      if (n === '__manifest__') continue;
      try {
        const f = path.join(core.PROJECT_DIR, n);
        if (prev[n] === null) fs.unlinkSync(f);
        else fs.writeFileSync(f, prev[n]);
      } catch { /* best-effort restore */ }
    }
    for (const k of Object.keys(temps)) { try { if (temps[k] && fs.existsSync(temps[k].tmp)) fs.unlinkSync(temps[k].tmp); } catch { /* best-effort */ } }
    core.die(`render failed mid-rename (${e.message}) — previous views restored`);
  }
  return { rendered: names };
}

function cmdRender(args = []) {
  const force = (args || []).includes('--force'); // D-03/R3-F1: bypass the manifest refusal
  const project = core.loadProject();
  if (!project) {
    console.log('(no project.json — nothing to render)');
    return;
  }
  const res = renderProjectViews(project, { force });
  console.log(`${core.CONTRACTS.command_contracts.renderDone} ${(res ? res.rendered : []).join(', ')}`);
}

module.exports = { renderPathsMarkdown, scopedPhaseSet, renderDecisionsMd, renderRoadmapMd, renderRequirementsMd, backupRenderedViews, renderProjectViews, cmdRender };
