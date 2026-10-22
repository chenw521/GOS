// task/context — per-stage context assembly; home of archiveSlugParts
'use strict';

const core = require('../core/index.cjs');
const nav = require('../nav/status.cjs');   // direct aspect require (dependency DAG)
const knowledge = require('../knowledge/index.cjs');
const sibPlansnap = require('./plansnap.cjs');
const fs = require('fs');
const path = require('path');

function pushCuratedConcerns(out) {
  const f = path.join(core.GOS_DIR, 'concerns.md');
  try {
    if (fs.existsSync(f) && knowledge.concernsEntryLines(fs.readFileSync(f, 'utf8')).length > 0) out.read_files.push('.gos/concerns.md');
  } catch { /* unreadable concerns must never break context */ }
}

function cmdContext(args) {
  const state = core.readState();
  if (!state) core.die(core.CONTRACTS.state_semantics.noActiveTask);
  const stage = (args[0] || state.current_stage || '').toUpperCase();
  if (!stage || nav.stageIndex(stage) === -1) {
    console.log('Usage: gos context <stage>');
    console.log('Stages: INTENT THINK PLAN BUILD REVIEW VERIFY SHIP');
    return;
  }
  const lv = state.level ?? '?';
  const out = {
    stage, level: lv,
    intent: state.intent.summary,
    completed_stages: state.completed_stages,
    read_files: [], produce: '', gates: [],
  };
  // Phase W (T4, R-04): artifact_paths supply — agents consume, never invent.
  // core.ensureTaskDir owns id resolution + conflict guard + mkdir(fail-fast).
  {
    const { tid, dir } = core.ensureTaskDir(state);
    const mkparent = (p) => {
      try { fs.mkdirSync(path.dirname(p), { recursive: true }); } catch (e) { core.die(`✗ cannot create artifact parent dir for ${p}: ${e.message}`); }
      return p;
    };
    const mkdirSelf = (p) => {
      try { fs.mkdirSync(p, { recursive: true }); } catch (e) { core.die(`✗ cannot create artifact dir ${p}: ${e.message}`); }
      return p;
    };
    const A = { task_id: tid, task_dir: dir };
    if (stage === 'THINK') A.spec = mkparent(core.resolvePath('spec', { task_id: tid }));
    else if (stage === 'PLAN') { A.spec = core.resolvePath('spec', { task_id: tid }); A.plan = mkparent(core.resolvePath('plan', { task_id: tid })); }
    else if (stage === 'BUILD' || stage === 'REVIEW') A.evidence_dir = mkdirSelf(core.resolvePath('task_evidence', { task_id: tid }));
    else if (stage === 'VERIFY') { A.evidence_dir = mkdirSelf(core.resolvePath('task_evidence', { task_id: tid })); A.truth_receipts = core.resolvePath('truth_receipts'); }
    else if (stage === 'SHIP') { const { date, slug } = archiveSlugParts(state); A.archive_dir = path.join(core.ARCHIVE_DIR, `${date}-${slug}`); }
    else if (stage === 'INTENT') A.task_dir = dir;
    out.artifact_paths = A;
  }
  // Stage-specific pre-computed context (model consumes, never guesses)
  if (stage === 'THINK') {
    out.read_files = ['.gos/state.json'];
    if (fs.existsSync(path.join(core.PROJECT_DIR, 'DECISIONS.md'))) out.read_files.push('.gos/project/DECISIONS.md');
    // D-06/R-33: a FILLED PROJECT.md joins the THINK read set — a TODO-only
    // skeleton must not pose as project vision (predicate shared with the
    // approve-archive gate; see knowledge/phase.cjs).
    {
      const pmPath = path.join(core.PROJECT_DIR, 'PROJECT.md');
      if (fs.existsSync(pmPath)) {
        try { if (knowledge.projectMdFilled(fs.readFileSync(pmPath, 'utf8'))) out.read_files.push('.gos/project/PROJECT.md'); }
        catch { /* unreadable PROJECT.md must never break context */ }
      }
    }
    pushCuratedConcerns(out);
    if (fs.existsSync(path.join(core.GOS_DIR, 'lessons.md'))) out.read_files.push('.gos/lessons.md');
    // B-11/B-16 [R1-F8]: global lessons join read_files with untrusted annotation
    const globalLessons = core.lessonsPaths('model').file;
    if (fs.existsSync(globalLessons)) {
      out.read_files.push(globalLessons);
      out.untrusted_note = core.CONTRACTS.semantic_checks.untrustedNote; // B-16 frozen header line (REVIEW #9: from table)
      out.untrusted_files = [globalLessons];
    }
    // D-67: attribution note (counts + source paths + expiry) rides read_files —
    // display-load only, a bad store degrades to a note, never an error
    {
      const attr = knowledge.lessonsAttribution();
      out.lessons_attribution = attr.project.ok
        ? { project: attr.project.count, global: attr.global.ok ? attr.global.count : 0, expiring_soon: (attr.project.expiring || 0) + (attr.global.ok ? attr.global.expiring || 0 : 0), source_project: attr.project.path, source_global: attr.global.path }
        : { degraded: attr.project.reason };
    }
    // brownfield: auto-include codebase map if present; else flag the offer
    const cbDir = path.join(core.GOS_DIR, 'codebase');
    if (fs.existsSync(cbDir)) {
      for (const f of ['structure.md', 'conventions.md', 'concerns.md']) {
        if (fs.existsSync(path.join(cbDir, f))) out.read_files.push(`.gos/codebase/${f}`);
      }
      out.has_codebase_map = true;
    } else {
      out.has_codebase_map = false;
      out.suggest = 'existing repo without .gos/codebase/ map — offer one-time mapping (see skills/gos-think/reference/codebase-mapping.md)';
    }
    // D-19/D-20: navigator tiers — tell THINK which map knowledge travels with
    // clones (git-tracked tier) vs regenerates per machine (byproduct carries
    // its own provenance header). Additive field; consumers keep working.
    out.navigator = {
      hint: 'codebase navigator tiers: guide trio (structure/conventions/concerns.md) is static per machine; map data (network.md, edge-baseline.json, require-allowlist.json) is git-tracked and travels with clones; full directory contract: skills/gos-think/reference/codebase-mapping.md',
      map_data: 'travels with clones (git-tracked): network.md, edge-baseline.json, require-allowlist.json',
      provenance: 'regenerable byproduct .gos/codebase/unmapped-fns.txt (rewritten by gate codemap) — first line: generated-at: <ISO> @ <HEAD[0:8]> (unborn repo: @ unborn)',
    };
    out.produce = `${path.relative(process.cwd(), core.specPathOf(state))} (decisions D-NN + requirements R-NN + truths T-NN)`;
    out.template = `${path.join(core.GOS_SELF_ROOT, 'templates', 'spec-template.md')} (readonly skeleton — copy it to the produce path, never edit the in-package original; examples at ${path.join(core.GOS_SELF_ROOT, 'skills', 'gos-think', 'examples')}/)`;
    out.gates = ['Red Team rounds (see skills/gos-think/reference/red-team.md)', 'user approval (HARD GATE)'];
    out.note = '→ Record decisions via `gos decision add` (not hand-editing state.json).';
  } else if (stage === 'PLAN') {
    out.read_files = [path.relative(process.cwd(), core.specPathOf(state))];
    pushCuratedConcerns(out);
    out.uncovered_decisions = state.decisions.filter(d => !d.covered).map(d => ({ id: d.id, title: d.title }));
    out.requirements = state.requirements.map(r => ({ id: r.id, text: r.text.slice(0, 60), claimed: !!r.phase }));
    out.produce = `${path.relative(process.cwd(), core.planPathOf(state))} (tasks with Covers/Wave/Depends)`;
    out.template = `${path.join(core.GOS_SELF_ROOT, 'templates', 'plan-template.md')} (readonly skeleton — copy it to the produce path, never edit the in-package original; example at ${path.join(core.GOS_SELF_ROOT, 'skills', 'gos-plan', 'examples', 'complete-plan.md')})`;
    out.gates = ['gos gate coverage (exit 0)', 'user confirmation'];
  } else if (stage === 'BUILD') {
    out.read_files = [path.relative(process.cwd(), core.planPathOf(state))];
    // D-41 + R3-F3 (five-piece wiring #5): non-empty curated concerns join BUILD's
    // read set — the concerns layer is consumed, never a write-only orphan.
    const concernsFile = path.join(core.GOS_DIR, 'concerns.md');
    if (fs.existsSync(concernsFile) && knowledge.concernsEntryLines(fs.readFileSync(concernsFile, 'utf8')).length > 0) {
      out.read_files.push('.gos/concerns.md');
    }
    const tasks = sibPlansnap.parsePlanMd();
    if (tasks) {
      out.tasks = tasks.map(t => ({ id: t.id, name: t.name, wave: t.wave, covers: t.covers, files: t.files, read_first: t.readFirst, done_when: t.doneWhen, depends: t.depends }));
      out.total_waves = Math.max(...tasks.map(t => t.wave || 1));
      // D-65 wiring: plan Files exist → blast summary + pointer to the full
      // pre-change report (impact analysis is load-bearing, not decorative)
      const planFiles = [...new Set(tasks.flatMap((t) => t.files || []))];
      if (planFiles.length) {
        out.blast_hint = `${planFiles.length} plan-declared file(s) — pre-change report: \`gos map blast ${planFiles.slice(0, 3).join(' ')}${planFiles.length > 3 ? ' …' : ''}\` shows what else must be checked and why`;
      }
    }
    out.produce = 'implementation + tests';
    out.gates = ['all tasks done + tests pass'];
  } else if (stage === 'REVIEW') {
    out.read_files = [];
    // D-41 + R3-F3: REVIEW also consumes the curated concerns (read/prune routing
    // lives in skills/gos-review; here: non-empty file joins read set).
    const concernsFileR = path.join(core.GOS_DIR, 'concerns.md');
    if (fs.existsSync(concernsFileR) && knowledge.concernsEntryLines(fs.readFileSync(concernsFileR, 'utf8')).length > 0) {
      out.read_files.push('.gos/concerns.md');
    }
    out.decisions_to_audit = state.decisions.map(d => d.id);
    out.requirements_to_audit = state.requirements.map(r => r.id);
    out.produce = 'review findings (severity-classified)';
    out.gates = ['all Critical/Major fixed'];
  } else if (stage === 'VERIFY') {
    out.read_files = ['.gos/state.json'];
    out.pending_truths = state.observable_truths.filter(t => !t.verified).map(t => ({ id: t.id, description: t.description }));
    out.produce = 'verification evidence (one truth at a time)';
    out.template = `${path.join(core.GOS_SELF_ROOT, 'templates', 'verify-checklist.md')} (readonly skeleton — copy it to the produce path, never edit the in-package original; examples at ${path.join(core.GOS_SELF_ROOT, 'skills', 'gos-verify', 'examples')}/)`;
    out.gates = ['gos gate all (exit 0)'];
  } else if (stage === 'SHIP') {
    out.produce = 'change record + archive';
    out.gates = ['gos archive (lessons check enforced)'];
  }
  console.log(JSON.stringify(out, null, 2));
}

function archiveSlugParts(state) {
  const date = new Date().toISOString().slice(0, 10);
  let version = '0.0.0';
  try { version = core.PKG.version || '0.0.0'; } catch { /* keep */ }
  let middle = 'task';
  if (state.phase_name) {
    const tok = core.currentTaskId(state) || 'task';
    middle = `phase-${tok}`;
  }
  const topic = (state.intent.summary || 'task').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 30) || 'misc';
  return { date, slug: `v${version}-${middle}-${topic}`.slice(0, 60) };
}

module.exports = { archiveSlugParts, pushCuratedConcerns, cmdContext };
