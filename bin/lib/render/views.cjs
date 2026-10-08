// render/views — view/command implementations that consume core + map.
'use strict';

const core = require('../core/index.cjs');
const map = require('../map/index.cjs');
const fs = require('fs');
const path = require('path');

const RENDERED_HEADER = core.CONTRACTS.command_contracts.generatedHeader;

const RENDER_KEEP_BACKUPS = 5;

// D-05 scope: active phase + 2 phases before it (by project.phases order).
// No active phase → last 3 phases. Unknown birth_phase (not in phases[]) → always included.

// D-05 backup: only meaningful when the full rendered set exists; prune keeps newest 5 by name (= time) order

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
const RENDER_BACKUP_DIR = path.join(core.ARCHIVE_DIR, 'render-backup');

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
  emit('logs/ — audit receipts (tracked)', entries.filter(([, e]) => e.rel.startsWith('logs/')));
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
  const dirs = fs.readdirSync(RENDER_BACKUP_DIR)
    .filter((d) => { try { return fs.statSync(path.join(RENDER_BACKUP_DIR, d)).isDirectory(); } catch { return false; } })
    .sort();
  for (const old of dirs.slice(0, Math.max(0, dirs.length - RENDER_KEEP_BACKUPS))) {
    fs.rmSync(path.join(RENDER_BACKUP_DIR, old), { recursive: true, force: true });
  }
}

function renderProjectViews(project) {
  const p = project || core.loadProject();
  if (!p) return null;
  fs.mkdirSync(core.PROJECT_DIR, { recursive: true });
  const names = ['DECISIONS.md', 'ROADMAP.md', 'REQUIREMENTS.md'];
  // Phase V [R1-F8]: self-describing footer — generated views carry write-time snapshot
  // semantics (residual rows keep their last-written status forever, D-08); point readers
  // at the live merged views so a frozen 'active' row never misleads again.
  const snapshotFooter = `\n<!-- generated at ${new Date().toISOString()} after phase ${p.last_archived_phase || '(milestone reset)'} — row status is a write-time snapshot, not a live lifecycle; live merged view: gos decision list --all / gos requirement list --all -->`;
  const bodies = {
    'DECISIONS.md': renderDecisionsMd(p) + snapshotFooter,
    'ROADMAP.md': renderRoadmapMd(p) + snapshotFooter,
    'REQUIREMENTS.md': renderRequirementsMd(p) + snapshotFooter,
  };
  const prev = {};
  for (const n of names) {
    const f = path.join(core.PROJECT_DIR, n);
    prev[n] = fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : null;
  }
  if (names.every((n) => prev[n] !== null)) backupRenderedViews(names);
  const temps = {};
  const renamed = [];
  try {
    for (const n of names) {
      const manual = map.manualRegion(prev[n]);
      const content = manual ? bodies[n] + '\n' + manual : bodies[n]; // rendered + one blank line + MANUAL verbatim
      temps[n] = { tmp: path.join(core.PROJECT_DIR, `.${n}.tmp${process.pid}`), final: path.join(core.PROJECT_DIR, n) };
      fs.writeFileSync(temps[n].tmp, content);
    }
    for (const n of names) {
      fs.renameSync(temps[n].tmp, temps[n].final);
      renamed.push(n);
    }
  } catch (e) {
    for (const n of renamed) {
      try {
        const f = path.join(core.PROJECT_DIR, n);
        if (prev[n] === null) fs.unlinkSync(f);
        else fs.writeFileSync(f, prev[n]);
      } catch { /* best-effort restore */ }
    }
    for (const n of names) { try { if (temps[n] && fs.existsSync(temps[n].tmp)) fs.unlinkSync(temps[n].tmp); } catch { /* best-effort */ } }
    core.die(`render failed mid-rename (${e.message}) — previous views restored`);
  }
  return { rendered: names };
}

function cmdRender() {
  const project = core.loadProject();
  if (!project) {
    console.log('(no project.json — nothing to render)');
    return;
  }
  const res = renderProjectViews(project);
  console.log(`${core.CONTRACTS.command_contracts.renderDone} ${(res ? res.rendered : []).join(', ')}`);
}

module.exports = { renderPathsMarkdown, scopedPhaseSet, renderDecisionsMd, renderRoadmapMd, renderRequirementsMd, backupRenderedViews, renderProjectViews, cmdRender };
