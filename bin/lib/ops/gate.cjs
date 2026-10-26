// ops/gate — gate command: builtin checks (state, semantic engine, codemap, lessons) + gates.json + custom scripts
'use strict';

const core = require('../core/index.cjs');
const map = require('../map/index.cjs');
const knowledge = require('../knowledge/index.cjs');
const task = require('../task/plansnap.cjs');
const sibConfig = require('./config.cjs');  // direct aspect require (acyclic)
const sibDoctor = require('./doctor.cjs');
const sibTrack = require('./track.cjs');    // T8 flip-reconcile leg consumes the T7b exports (manifest read, never-zones/files, census key rule)
const render = require('../render/views.cjs');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const EXEMPT_LOG_REL = core.GOS_PATHS.exemptions.rel; // T16: logs/ via registry (relative read/write path join)

// T5 semanticChecks: orchestrates ①bidirectional ②diff-hit ③artifact existence.
// Prints ✓/⚠ lines inline; returns {failures, passes} — caller (cmdGate / T7 commit
// embed) maps failures → exit 1 and passes → semantic_checks.banner downgrade.

// ---------- setup/teardown (T6): skills management ----------

// ---------- doctor (T7): installation diagnostics — read-only ----------

// DOCTOR_FIXES single source lives in ops/doctor.cjs; gate consumes it via sibDoctor.

function getSemanticPlanTasks(state) {
  const snap = state.plan_snapshot;
  if (snap && Array.isArray(snap.tasks) && snap.tasks.length) {
    return {
      tasks: snap.tasks.map((t) => ({ id: t.id, covers: Array.isArray(t.covers) ? t.covers : [], files: Array.isArray(t.files) ? t.files : [] })),
      source: 'plan_snapshot',
    };
  }
  const parsed = task.parsePlanMd();
  if (!parsed || !parsed.length) return null;
  return { tasks: task.buildPlanSnapshotTasks(parsed), source: 'plan.md' };
}

function checkBidirectional(state, tasks) {
  const failures = [];
  const decIds = new Set(state.decisions.map((d) => d.id));
  const reqIds = new Set(state.requirements.map((r) => r.id));
  const covered = new Set();
  const ghostD = [];
  const ghostR = [];
  for (const t of tasks) {
    for (const c of (t.covers || [])) {
      if (/^R-\d+$/i.test(c)) {
        if (!reqIds.has(c)) ghostR.push(`${c} (task ${t.id})`);
      } else {
        covered.add(c);
        if (!decIds.has(c)) ghostD.push(`${c} (task ${t.id})`);
      }
    }
  }
  if (ghostD.length) failures.push(core.gateFail('plan-covers-ghost-decision', {
    verdict: 'plan Covers reference decisions that do not exist in state.decisions',
    evidence: [...new Set(ghostD)],
    fix: core.gateCmd('node bin/gos.cjs decision list') + ' — align Covers ids with the real decision set (cross-phase needs --all / project DECISIONS.md)',
  }));
  const uncovered = state.decisions.filter((d) => !covered.has(d.id));
  if (uncovered.length) failures.push(core.gateFail('decision-uncovered', {
    verdict: 'decisions recorded in state but not covered by any plan task',
    evidence: uncovered.map((d) => `${d.id} (${d.title})`),
    fix: core.gateCmd('node bin/gos.cjs stage back', 'plan') + ' — add a task covering them, or drop the decision',
  }));
  if (ghostR.length) failures.push(core.gateFail('plan-covers-ghost-requirement', {
    verdict: 'plan Covers reference requirements that do not exist in state.requirements',
    evidence: [...new Set(ghostR)],
    fix: core.gateCmd('node bin/gos.cjs requirement list') + ' — align Covers ids with the real requirement set',
  }));
  // [D-07] teaching line on every ghost-family failure — the graceland exits were never
  // spoken before U2 (commit plan --force only overrides snapshot monotonicity, NOT this
  // check; the real exits are Covers↔state alignment or a stage-back re-plan).
  if (ghostD.length || ghostR.length || uncovered.length) {
    failures.push(core.gateFail('covers-teaching', {
      verdict: core.CONTRACTS.command_contracts.ghostFixTeaching,
      evidence: [],
      fix: core.gateCmd('node bin/gos.cjs status'),
    }));
  }
  return { failures, coveredCount: covered.size };
}

function loadSemanticAllowlist(state) {
  const patterns = ['.changes.md', 'CHANGELOG.md', 'commitlint.config.yaml', '*.lock', '.gos/**'];
  const hardExcl = ['.gos/gates.json', '.gos/gates/**'];
  const cfg = (state && state.semantic && Array.isArray(state.semantic.allowlist)) ? state.semantic.allowlist : [];
  for (const raw of cfg) {
    const p = String(raw == null ? '' : raw).trim();
    if (!p) continue;
    if (p === '**' || p === '*' || p === '/*') {
      core.die(`semantic allowlist: '${p}' ${sibConfig.SEMANTIC_RUNTIME.tooBroad} — bare ** / * / /* rejected (fail-closed)`);
    }
    patterns.push(p);
  }
  const exemptExact = new Set();
  for (const t of ((state && state.observable_truths) || [])) {
    if (t && t.verified && t.evidence && typeof t.evidence.artifact_path === 'string' && t.evidence.artifact_path) {
      exemptExact.add(t.evidence.artifact_path);
    }
  }
  return { patterns, hardExcl, exemptExact };
}

function semanticAllowlisted(file, allowlist) {
  if (allowlist.hardExcl.some((p) => core.globToRegex(p).test(file))) return false; // hardcoded exclusion wins
  if (allowlist.exemptExact.has(file)) return true;                            // truth artifact_path exempt
  return allowlist.patterns.some((p) => core.globToRegex(p).test(file));
}

function semanticBaselineShas(state) {
  const rows = Array.isArray(state.task_head_history) ? state.task_head_history : [];
  return [...new Set([state.task_head, ...rows.map((r) => (r && typeof r === 'object' ? r.sha : null))])]
    .filter((s) => typeof s === 'string' && s);
}

function diffHitCheck(diffFiles, planTasks, allowlist, closureFn = null) {
  const failures = [];
  const warnings = [];
  // Files may be globs (module-batch declarations like `bin/lib/nav/*.cjs`) —
  // a changed path is declared when it equals the entry OR matches it as a
  // glob (same matcher the semantic allowlist uses).
  const fileMatches = (f, decl) => decl === f || core.globToRegex(decl).test(f);
  const declares = (f) => planTasks.some((t) => (t.files || []).some((d) => fileMatches(f, d)));
  const directHit = (f, t) => (t.files || []).some((d) => fileMatches(f, d));
  const hitFn = closureFn || directHit;
  // ① every task with declared Files must have Files∩diff ≠ ∅ (zero-hit = work claimed but never done)
  for (const t of planTasks) {
    if (!t.files || !t.files.length) {
      warnings.push(`task ${t.id}: ${sibConfig.SEMANTIC_RUNTIME.noFilesWarn}`);
      continue;
    }
    let hit = false;
    for (const f of diffFiles) if (hitFn(f, t)) { hit = true; break; }
    if (!hit) failures.push(core.gateFail('diff-zero-hit', {
      verdict: `task ${t.id} declared Files but none of them appear in the diff since task_head — the plan claims work that never happened`,
      evidence: [t.id, ...t.files],
      fix: core.gateCmd('node bin/gos.cjs status') + ' — verify the task really landed; if plan drifted, stage back plan and refresh the snapshot',
    }));
  }
  // ② diff ⊆ ∪Files ∪ allowlist (undeclared modified file → fail)
  for (const f of diffFiles) {
    if (declares(f)) continue;
    if (semanticAllowlisted(f, allowlist)) continue;
    failures.push(core.gateFail('undeclared-diff-file', {
      verdict: `file changed in the diff but not declared in any plan task's Files and not allowlisted`,
      evidence: [f],
      fix: core.gateCmd('node bin/gos.cjs stage back', 'plan') + ' — declare it in plan Files, or extend state.semantic.allowlist when it is task-local noise',
    }));
  }
  return { failures, warnings };
}

function semanticDiffPhase(state, tasks) {
  const shas = semanticBaselineShas(state);
  if (!shas.length) {
    if (state.task_head_pending) {
      console.log(`⚠ ${sibConfig.SEMANTIC_RUNTIME.skipPending}`); // auto-anchor is T7's commit-embed job
      return { failures: [] };
    }
    return { failures: [core.gateFail('diff-baseline-lost', { verdict: `diff-hit: ${sibConfig.SEMANTIC_RUNTIME.noHeadFail}`, evidence: [], fix: core.gateCmd('node bin/gos.cjs init 3', '"<intent>"') + ' — re-init or re-claim the task to re-anchor the diff baseline' })] };
  }
  const shallow = core.safeGitArgv(['rev-parse', '--is-shallow-repository']).trim() === 'true';
  for (const sha of shas) {
    if (!core.shaReachable(sha)) {
      if (shallow) {
        console.log(`⚠ ${sibConfig.SEMANTIC_RUNTIME.skipShallow}`); // not exit 1 [B-4]
        return { failures: [] };
      }
      return { failures: [core.gateFail('diff-baseline-unreachable', { verdict: `task_head ${sha} unreachable in git repo — diff baseline lost`, evidence: [sha], fix: 'git unshallow, or re-init / re-claim the task to re-anchor' })] };
    }
  }
  // diff set = ∪ (git diff <sha> worktree-inclusive, two-dot-free form) + untracked
  const diff = new Set();
  for (const sha of shas) {
    const out = core.gitArgvBytes(['-c', 'core.quotepath=off', 'diff', '--name-only', '--no-renames', '-z', sha]);
    for (const f of core.nulNames(out)) diff.add(f);
  }
  const others = core.gitArgvBytes(['-c', 'core.quotepath=off', 'ls-files', '--others', '--exclude-standard', '-z']);
  for (const f of core.nulNames(others)) diff.add(f);
  // [Phase D T7] integrity FIRST: a corrupted/tampered/deleted edges anchor dies before
  // any other gate can green-light on silently-shrunk closure data (R2-F5 pass-on-unknown).
  {
    const iv = map.checkEdgesIntegrity(core.mapRootDir());
    if (iv.status === 'die') return { failures: [core.gateFail('edges-integrity-die', { verdict: String(iv.msg).replace(/^✗ /, ''), evidence: [], fix: core.gateCmd('node bin/gos.cjs map scan') + ' — regenerate the edges anchor; if hand-edited, restore from git' })] };
    if (iv.status === 'advisory') console.log(iv.msg);
    const dead = map.deadEdgesIn(core.mapRootDir());   // [R1-C1 fix] five-state matrix: dead-edge state now gate-visible
    if (dead.length) return { failures: dead.map((d) => core.gateFail('dead-edge', { verdict: `dead edge ${d} — hand edge references an endpoint that no longer exists`, evidence: [d], fix: core.gateCmd('node bin/gos.cjs map scan') + ' — refresh the map, or fix the stale edge in .gos/codebase/edges.json' })) };
  }
  const hit = diffHitCheck(diff, tasks, loadSemanticAllowlist(state), null); // B-6 direct mode
  for (const w of hit.warnings) console.log(`⚠ ${w}`);
  if (hit.failures.length) return { failures: hit.failures };
  console.log(`✓ diff-hit: ${diff.size} changed file(s) — every Files-declaring task hit, diff ⊆ ∪Files+allowlist`);
  // ④ Phase 6 (T3) impactClosure advisory tail [D-36(amended)/D-38]: in-memory
  // recompute — NEVER reads/writes deps.json (cache-independent by construction);
  // exit-code neutral (prints only); runs only after diff-hit passed.
  impactClosurePhase(diff, tasks, state);
  // [Phase D T7] semantic closure tail (D-26): three-source merge, advisory, qualified
  // wording first line; runs after diff-hit passed so undeclared-change noise never
  // masks the closure report.
  const closure = map.printSemanticClosure(core.mapRootDir(), [...diff]);
  // [Phase D T10] run-manifest freshness: must-run sections exercised against THIS
  // content tree? (no manifest = advisory BUILD mode; stale/missing = FAIL — this is
  // the "declared-must-run actually ran" fact check, NOT closure exhaustiveness)
  const mf = checkManifest(core.mapRootDir(), [...closure.mustRun.keys()], loadSemanticAllowlist(state));
  for (const a of mf.advisories) console.log(`⚠ ${a}`);
  if (mf.failures.length) return { failures: mf.failures };
  return { failures: [], pass: true };
}

function readExemptions(root) {
  // R-35/D-02 line grammar: `<iso8601> <section> :: <reason>` — FIELD 2 is the
  // section (the reason rides along for the `gos logs` view). #-prefixed lines
  // are comments (filtered); a bare single-token legacy line has no field 2 and
  // yields nothing.
  try {
    return fs.readFileSync(path.join(root, '.gos', EXEMPT_LOG_REL), 'utf8').split('\n')
      .map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
      .map((l) => l.split(/\s+/)[1]).filter(Boolean);
  } catch { return []; }
}

function consumeExemptions(root) {   // called from cmdCommit — auto-expiry (R2-F11: auditable, machine-local per D-01)
  const p = path.join(root, '.gos', EXEMPT_LOG_REL);
  if (!fs.existsSync(p)) return;
  const lines = readExemptions(root);
  if (lines.length) console.log(`✓ ${core.CONTRACTS.semantic_checks.exemptCleared} (${lines.length} entr${lines.length === 1 ? 'y' : 'ies'})`);
  fs.rmSync(p, { force: true });   // D-01: consumed ledger leaves no unignored residue (dir may not be gitignored in foreign repos)
}

// ---------- [D-02/R-35] gos logs: runtime ledger view (READ-class, no lock) ----------
// Renders the machine-local logs trio (D-01) as formatted tables. The ledgers
// are enriched at write time (receipts carry the truth text, exemptions carry
// the reason) so the view never needs to join task state — historical lines
// survive post-archive.

const LOGS_VIEWS = {
  receipts: { key: 'truth_receipts', title: 'logs.receipts.title' },
  exemptions: { key: 'exemptions', title: 'logs.exemptions.title' },
  audit: { key: 'edge_audit', title: 'logs.audit.title' },
};

function parseLogsLine(kind, line) {
  if (kind === 'receipts') {
    // enriched: `<iso8601> <id> replay-verified: <cmd> :: <truth text>`; legacy
    // `- [date] id replay-verified: <cmd>` lines render with the whole tail as cmd.
    const m = line.match(/^(\S+)\s+(\S+)\s+replay-verified:\s+(.*)$/);
    if (!m) return { a: '', b: '', c: line, d: '' };
    let cmd = m[3]; let truth = '';
    const idx = cmd.indexOf(' :: '); // writer emits cmd-then-separator: the FIRST boundary is authoritative
    if (idx >= 0) { truth = cmd.slice(idx + 4); cmd = cmd.slice(0, idx); }
    return { a: m[1], b: m[2], c: cmd, d: truth };
  }
  if (kind === 'exemptions') {
    const m = line.match(/^(\S+)\s+(\S+)\s+::\s+(.*)$/);
    if (!m) return { a: '', b: line, c: '' };
    return { a: m[1], b: m[2], c: m[3] };
  }
  // audit: `<iso8601> <action> <from> -> <to> <type>` (edges.cjs writer)
  const m = line.match(/^(\S+)\s+(.+)$/);
  if (!m) return { a: '', b: line };
  return { a: m[1], b: m[2] };
}

function clipCp(s, n) { return [...String(s)].slice(0, n).join(''); }

function padCp(s, w) {
  const s2 = String(s);
  const len = [...s2].length;
  return s2 + ' '.repeat(Math.max(0, w - len));
}

function cmdLogs(args) {
  const sub = (args[0] || '').toLowerCase();
  const view = LOGS_VIEWS[sub];
  const usage = 'Usage: gos logs <receipts|exemptions|audit> [--last N]';
  if (!view) core.die(`${usage}   (view the runtime audit ledgers — receipts carry truth text, exemptions carry the reason; default last 20)`);
  let last = 20;
  const rest = args.slice(1);
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === '--last') {
      const v = rest[++i];
      if (v === undefined || !/^\d+$/.test(v) || Number(v) < 1 || Number(v) > 10000) {
        core.die(`logs: --last must be an integer between 1 and 10000 (entries), e.g. --last 5\n${usage}`);
      }
      last = Number(v);
    } else core.die(`logs: unknown argument '${rest[i]}'\n${usage}`);
  }
  const root = core.mapRootDir();
  const entry = core.GOS_PATHS[view.key];
  const file = path.join(root, '.gos', entry.rel);
  let lines = [];
  try {
    lines = fs.readFileSync(file, 'utf8').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  } catch { /* absent ledger = empty (machine-local, may not exist yet) */ }
  const shown = lines.slice(-last);
  console.log(core.t(view.title, { path: entry.rel, n: String(shown.length), total: String(lines.length) }));
  if (!shown.length) { console.log(core.t('logs.empty')); return; }
  const rows = shown.map((l) => parseLogsLine(sub, l));
  if (sub === 'receipts') {
    const wB = Math.min(10, Math.max(...rows.map((r) => [...r.b].length), 2));
    const wC = Math.min(60, Math.max(...rows.map((r) => [...clipCp(r.c, 60)].length), 7));
    console.log(`  ${padCp('TIMESTAMP', 25)}${padCp('ID', wB + 2)}${padCp('COMMAND', wC + 2)}TRUTH`);
    for (const r of rows) console.log(`  ${padCp(r.a, 25)}${padCp(r.b, wB + 2)}${padCp(clipCp(r.c, 60), wC + 2)}${clipCp(r.d, 80)}`);
  } else if (sub === 'exemptions') {
    const wB = Math.min(28, Math.max(...rows.map((r) => [...r.b].length), 7));
    console.log(`  ${padCp('TIMESTAMP', 25)}${padCp('SECTION', wB + 2)}REASON`);
    for (const r of rows) console.log(`  ${padCp(r.a, 25)}${padCp(clipCp(r.b, 28), wB + 2)}${clipCp(r.c, 120)}`);
  } else {
    console.log(`  ${padCp('TIMESTAMP', 25)}ENTRY`);
    for (const r of rows) console.log(`  ${padCp(r.a, 25)}${clipCp(r.b, 160)}`);
  }
}

function checkManifest(root, mustRunSecs, allowlist) {   // → {advisories, failures} (empty failures = pass); advisory when no manifest
  const SC = core.CONTRACTS.semantic_checks;
  const p = path.join(root, '.gos', core.GOS_PATHS.run_manifest.rel);
  if (!fs.existsSync(p)) return { advisory: SC.manifestNone, advisories: [SC.manifestNone], failures: [] };
  let m = null;
  try { m = JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return { advisory: null, advisories: [], failures: [core.gateFail('manifest-stale', { verdict: SC.manifestStale, evidence: [p], fix: core.gateCmd('bash test/run-sections.sh') + ' — re-run the section suite to rewrite the manifest' })] }; }
  if (m.schema_version !== 2) return { advisory: null, advisories: [], failures: [core.gateFail('manifest-stale', { verdict: SC.manifestStale + ' (old manifest schema — re-run the suite to rewrite)', evidence: [p], fix: core.gateCmd('bash test/run-sections.sh') })] };   // [m7] explicit, not misleading
  // filter audit: a partial run is legitimate (closure responsibility) but never silent
  const advisories = [];
  if (m.selector === 'affected') advisories.push('manifest: affected-sections run (map-blast closure + fail-safe set) — full suite remains the CI authority');
  if (typeof m.filter === 'string' && m.filter) advisories.push(SC.manifestPartialRun.replace('<filter>', m.filter));
  const cur = core.worktreeContentHash(root);
  if (!cur || !m.head_tree || !m.patch_sha) return { advisory: null, advisories, failures: [core.gateFail('manifest-stale', { verdict: SC.manifestStale, evidence: [p], fix: core.gateCmd('bash test/run-sections.sh') })] };
  // commit-advance tolerance: a clean tree is FRESH if the manifest's head_tree is an
  // ANCESTOR of current HEAD (the tested content was committed verbatim); a dirty tree
  // must match exactly (tested content == current visible content).
  let fresh = false;
  let ancestorOk = false;
  if (cur.patch_sha === core.cryptoEmptySha()) {   // empty patch → clean tree
    try {
      const trees = execFileSync('git', ['-C', root, 'log', '--format=%T', '-n', '50'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).split('\n').map((t) => t.trim());
      fresh = trees.includes(m.head_tree);
      ancestorOk = fresh;
    } catch { fresh = false; }
  } else {
    fresh = m.head_tree === cur.head_tree && m.patch_sha === cur.patch_sha;
    // [U2/D-04] ancestor tolerance also anchors the doc-only downgrade: doc edits may
    // ride on top of the tested tree, but never substitute for it.
    if (!fresh) {
      try {
        const trees = execFileSync('git', ['-C', root, 'log', '--format=%T', '-n', '50'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).split('\n').map((t) => t.trim());
        ancestorOk = trees.includes(m.head_tree);
      } catch { ancestorOk = false; }
    }
  }
  if (!fresh) {
    // [U2/D-01~D-04] doc-only downgrade: dirty diff fully semantic-allowlisted AND the
    // tested tree is a HEAD ancestor → doc edits cannot invalidate code-face test
    // evidence; downgrade to a VISIBLE advisory (never silent). Any non-allowlisted
    // file keeps the fail-closed stale (R-02/T33.7); ancestor break also keeps FAIL.
    let docOnly = false;
    if (ancestorOk && allowlist) {
      try {
        const files = execFileSync('git', ['-C', root, '-c', 'core.quotepath=off', 'diff', '--name-only', 'HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).split('\n').map((s) => s.trim()).filter(Boolean);
        docOnly = files.length > 0 && files.every((f) => semanticAllowlisted(f, allowlist));
      } catch { docOnly = false; }
    }
    if (docOnly) return { advisory: SC.manifestDocOnly, advisories: [SC.manifestDocOnly], failures: [] };
    return { advisory: null, advisories, failures: [core.gateFail('manifest-stale', { verdict: SC.manifestStale, evidence: [p], fix: core.gateCmd('bash test/run-sections.sh') })] };
  }
  const exempt = new Set(readExemptions(root));
  const ranList = Array.isArray(m.sections_run) ? m.sections_run : [];
  // empty-run guard: a run that executed NO sections is never freshness
  // evidence (empty section set + empty closure must not pass as fresh)
  if (ranList.length === 0) return { advisory: null, advisories, failures: [core.gateFail('manifest-empty-run', { verdict: SC.manifestEmptyRun, evidence: [p], fix: core.gateCmd('bash test/run-sections.sh') })] };
  const ran = new Set(ranList);
  const missing = [...mustRunSecs].filter((s) => !ran.has(s) && !exempt.has(s));
  if (missing.length) return { advisory: null, advisories, failures: [core.gateFail('manifest-missing-sections', { verdict: SC.manifestMissingSecs.replace('<secs>', missing.join(', ')), evidence: missing, fix: core.gateCmd('bash test/run-sections.sh') + ' — run the missing sections (or gate --exempt <section> with a reason)' })] };
  if (!mustRunSecs.length) advisories.push(SC.manifestEmptyClosure);
  return { advisory: advisories[0] || null, advisories, failures: [] };
}

function impactClosurePhase(diffSet, planTasks, state) {
  const SC = core.CONTRACTS.semantic_checks;
  const allowlist = loadSemanticAllowlist(state);
  const root = core.mapRootDir();
  const scan = map.scanSources(root);                     // gate-time truth: current worktree
  const diffMinusAllow = [...diffSet].filter((f) => !semanticAllowlisted(f, allowlist));
  if (scan.files.length === 0 || diffMinusAllow.length === 0) {
    console.log(`⚠ ${SC.impactVacuous}`);
    return;
  }
  const closure = map.computeClosure(diffMinusAllow, scan, {});
  const unionFiles = new Set(planTasks.flatMap((t) => t.files || []));
  const uncovered = closure.filter((f) => !unionFiles.has(f));
  if (uncovered.length === 0) {
    console.log(`⚠ ${SC.impactClean}`);
    return;
  }
  let best = null, bestN = -1;
  for (const f of diffMinusAllow) {
    const n = map.computeClosure([f], scan, {}).filter((x) => x !== f).length;   // dependents count
    if (n > bestN || (n === bestN && best !== null && f < best)) { best = f; bestN = n; }
  }
  console.log(`⚠ ${SC.impactClosure.replace('<N>', String(uncovered.length))}`);
  console.log(`⚠ ${SC.impactHintRun.replace('<top-impact-file>', best || diffMinusAllow[0])}`);
}

function checkDeferredFindings(state) {
  // Review findings parked as "deferred" need a durable parking spot: either
  // fixed later (fixed: true) or registered in .gos/concerns.md (concern:
  // '<substring>'). A deferred finding without either is an orphan — it dies
  // with the task archive and nobody will remember it.
  const failures = [];
  const rf = state.review_findings;
  if (!rf || !Array.isArray(rf.minors_deferred)) return failures;
  let concernsText = '';
  try { concernsText = fs.readFileSync(core.CONCERNS_PATH || path.join(core.GOS_DIR, 'concerns.md'), 'utf8'); } catch { concernsText = ''; }
  rf.minors_deferred.forEach((item, i) => {
    const label = (item && (item.issue || item.id)) || `#${i + 1}`;
    if (item && item.fixed === true) return;
    if (item && typeof item.concern === 'string' && item.concern.length > 3 && concernsText.includes(item.concern)) return;
    failures.push(core.gateFail('orphan-deferred-finding', {
      verdict: `orphan deferred finding "${String(label).slice(0, 60)}" — it dies with the task archive and nobody will remember it`,
      evidence: [String(label)],
      fix: core.gateCmd('node bin/gos.cjs concerns add', '"<worry>"') + ' — then set review_findings.minors_deferred[].concern to a substring of that entry (or fixed: true once fixed)',
    }));
  });
  return failures;
}

// ---------------------------------------------------------------------------
// D-62 thin spec gate (structural card floor) — pure, fixture-testable (F2:
// NEVER validates the live pre-P15 spec; the grandfather stamp below is the
// only activation switch, set by new-CLI THINK commits).
// ---------------------------------------------------------------------------

function projectDecisionIds() {
  try {
    const pj = core.loadProject();
    return (pj && Array.isArray(pj.decisions)) ? pj.decisions.map((d) => d && d.id).filter(Boolean) : [];
  } catch { return []; }
}

// Strip fenced blocks (``` / ~~~), inline code spans, and exempt-marked lines —
// the D-NN lower-bound scan never reads examples (N7).
function stripSpecForScan(text) {
  let t = String(text || '').replace(/```[\s\S]*?```/g, '').replace(/~~~[\s\S]*?~~~/g, '');
  t = t.replace(/`[^`\n]*`/g, '');
  t = t.split('\n').filter((l) => !l.includes('<!-- gos:spec-gate:exempt -->')).join('\n');
  return t;
}

function specCardFloorFailures(specText, decisions, projectIds) {
  const failures = [];
  // (b) lower bound: every referenced D-NN resolves (cross-phase refs legal)
  const known = new Set([...(decisions || []).map((d) => d && d.id).filter(Boolean), ...(projectIds || [])]);
  const scanned = stripSpecForScan(specText);
  for (const m of scanned.matchAll(/\bD-\d{2,3}\b/g)) {
    if (!known.has(m[0])) {
      failures.push(core.gateFail('spec-gate-unknown-decision', {
        verdict: `spec references ${m[0]} but it resolves to neither state.decisions nor the project DECISIONS index`,
        evidence: [m[0]],
        fix: 'register the decision (`gos decision add`) or fix the typo — unregistered ids are how decisions silently vanish',
      }));
    }
  }
  // (a) card floor: every state decision carries a D-NN section with an options
  // pipe table (≥2 distinct first-column tokens) + a why-not: line hitting one
  const sections = [];
  let cur = null;
  for (const line of String(specText || '').split('\n')) {
    const h = line.match(/^#{1,6}\s+(.*)$/);
    if (h) { cur = { heading: h[1], lines: [] }; sections.push(cur); }
    else if (cur) cur.lines.push(line);
  }
  for (const d of decisions || []) {
    if (!d || !d.id) continue;
    const own = sections.filter((s) => s.heading.includes(d.id));
    if (!own.length) {
      failures.push(core.gateFail('spec-gate-card-missing', {
        verdict: `decision ${d.id} has no spec section — every decision must show its options card (a model preference without alternatives is not a decision)`,
        evidence: [d.id],
        fix: 'add a section whose heading contains the id, with an options table and a why-not line (skills/gos-think/reference/dialogue-protocol.md)',
      }));
      continue;
    }
    const body = own.map((s) => s.lines.join('\n')).join('\n');
    const tokens = new Set();
    for (const row of body.split('\n')) {
      if (!/^\s*\|/.test(row)) continue;
      const first = row.trim().replace(/^\|/, '').split('|')[0].trim();
      if (!first || /^[-:\s]*$/.test(first) || /^option/i.test(first)) continue; // separator + header row
      tokens.add(first);
    }
    if (tokens.size < 2) {
      failures.push(core.gateFail('spec-gate-card-table', {
        verdict: `decision ${d.id} card lacks an options table with ≥2 distinct option rows`,
        evidence: [d.id],
        fix: 'add the option comparison table (first column = option token, ≥2 rows) — see dialogue-protocol.md card template',
      }));
    }
    const whyNot = body.split('\n').find((l) => /^\s*why-not\s*:/i.test(l));
    const tokenHit = whyNot && [...tokens].some((t) => {
      const esc = t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      return new RegExp(esc, 'i').test(whyNot);
    });
    if (!tokenHit) {
      failures.push(core.gateFail('spec-gate-card-why-not', {
        verdict: `decision ${d.id} card lacks a why-not: line naming the rejected option(s)`,
        evidence: [d.id],
        fix: 'add `why-not: <option token> — <reason>` under the table; markers are English-canonical (why-not:)',
      }));
    }
  }
  return failures;
}

function semanticChecks(opts = {}) {
  const state = opts.state || core.readState();
  const failures = [];
  let passes = 0;
  loadSemanticAllowlist(state); // load-time fail-closed strength check (B-5) — dies on broad patterns

  const deferred = checkDeferredFindings(state);
  if (deferred.length) failures.push(...deferred);
  else if (state.review_findings && Array.isArray(state.review_findings.minors_deferred) && state.review_findings.minors_deferred.length) {
    console.log(`✓ deferred findings: ${state.review_findings.minors_deferred.length} parked (concerns.md or fixed)`);
    passes++;
  }

  const tasksSrc = getSemanticPlanTasks(state);
  if (!tasksSrc) {
    console.log(`⚠ ${sibConfig.SEMANTIC_RUNTIME.skipNoPlan}`); // Lv0/1 or not yet planned
  } else {
    const bid = checkBidirectional(state, tasksSrc.tasks);
    if (bid.failures.length) failures.push(...bid.failures);
    else {
      console.log(`✓ bidirectional: ${bid.coveredCount}/${state.decisions.length} decisions covered exactly, Covers R-NN ⊆ requirements`);
      passes++;
    }
    if (!core.gitInWorkTree()) {
      console.log(`⚠ ${sibConfig.SEMANTIC_RUNTIME.skipNotGit}`); // non-git cwd → skip, not fail [B-4]
    } else {
      const res = semanticDiffPhase(state, tasksSrc.tasks);
      if (res.failures.length) failures.push(...res.failures);
      else if (res.pass) passes++;
    }
  }

  // ③ artifact existence (semantic view): verified truths' evidence.artifact_path
  // must exist on disk at gate time — gate truths keeps its own branch (T2/T4).
  const missing = [];
  let artCount = 0;
  for (const t of (state.observable_truths || [])) {
    if (!t || !t.verified || !t.evidence) continue;
    const ap = t.evidence.artifact_path;
    if (typeof ap !== 'string' || !ap) continue;
    artCount++;
    if (!fs.existsSync(path.resolve(ap))) missing.push(core.gateFail('truth-artifact-missing', { verdict: `${t.id}: artifact not found on disk (${core.CONTRACTS.semantic_checks.pathExists})`, evidence: [ap], fix: core.gateCmd('node bin/gos.cjs truth verify', t.id) + ' — re-verify with an existing artifact' }));
  }
  if (missing.length) failures.push(...missing);
  else {
    console.log(`✓ artifacts: ${artCount}/${artCount} verified-truth artifact(s) exist on disk`);
    passes++;
  }

  // B-22 [Phase-1 audit finding]: spec_sha256 consistency — frozen hash (THINK commit or
  // lazy-freeze) must match the CURRENT spec.md. Mismatch = spec tampered mid-task → fail.
  // Missing freeze (pre-lazy-freeze) → skip: not yet frozen, nothing to compare.
  if (state.spec_sha256) {
    const sp = core.specPathOf(state);
    if (fs.existsSync(sp)) {
      const cur = core.sha256FileSync(sp);
      if (cur !== state.spec_sha256) {
        failures.push(core.gateFail('spec-sha-mismatch', { verdict: 'spec.md hash ≠ frozen spec_sha256 (B-22) — spec changed after THINK commit', evidence: [sp], fix: core.gateCmd('node bin/gos.cjs commit think') + ' — re-freeze (only for legitimate changes)' }));
      } else {
        console.log('✓ spec frozen: spec.md hash matches spec_sha256 (B-22)');
        passes++;
      }
    }
  }

  // D-62 thin spec gate: structural card floor. Grandfathered unless the THINK
  // commit ran under a post-P15 CLI (spec_gate_version stamp) — the live p15
  // spec predates the switch and is validated by fixtures only (F2).
  if (state.spec_gate_version === 2) {
    const sp = core.specPathOf(state);
    if (fs.existsSync(sp)) {
      const cardFails = specCardFloorFailures(fs.readFileSync(sp, 'utf8'), state.decisions, projectDecisionIds());
      if (cardFails.length) failures.push(...cardFails);
      else {
        console.log(`✓ spec cards: ${state.decisions.length} decision card(s) with options table + why-not line`);
        passes++;
      }
    }
  }

  return { failures, passes };
}

// ---------- custom-gate hash trust ----------
// Machine-local consent registry (.gos/cache/trust.json, untracked): a custom
// gate script only executes when its CURRENT sha256 matches the registered one.
// A missing file is a fresh install (empty store, ok); a present-but-unparseable
// file is corrupt (ok:false → every script treated as untrusted — never
// skip-and-green). confirmed_sections is reserved for the section-run
// first-use confirmation.
function loadTrustStore() {
  const p = path.join(core.GOS_DIR, core.GOS_PATHS.trust.rel);
  if (!fs.existsSync(p)) return { ok: true, store: { schema_version: 1, trusted_scripts: {}, confirmed_sections: '' } };
  let raw = null;
  try { raw = JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return { ok: false, store: null }; }
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return { ok: false, store: null };
  const ts = (raw.trusted_scripts && typeof raw.trusted_scripts === 'object' && !Array.isArray(raw.trusted_scripts)) ? raw.trusted_scripts : {};
  const cs = typeof raw.confirmed_sections === 'string' ? raw.confirmed_sections : '';
  return { ok: true, store: { schema_version: 1, trusted_scripts: ts, confirmed_sections: cs } };
}

// gos gate trust <name>: register the CURRENT sha256 of .gos/gates/<name> in the
// machine-local registry, then GC entries whose files no longer exist on disk.
// Stateless by design (setup seeding trusts before any `gos init`).
function cmdGateTrust(args) {
  const name = args[1];
  if (!name || /[\\/]/.test(name) || name === '.' || name === '..') {
    core.die('Usage: gos gate trust <name>   (name = a file in .gos/gates/, e.g. check.sh)');
  }
  const full = path.join(core.GOS_DIR, 'gates', name);
  let sha = null;
  try { sha = core.sha256FileSync(full); }
  catch (e) { core.die(`cannot hash .gos/gates/${name}: ${e.message} — check the file exists and is readable`); }
  const base = loadTrustStore();
  if (!base.ok) console.log('⚠ trust store was unreadable/corrupt — rebuilding it from this registration (other entries lost, re-trust as needed)');
  const store = base.ok ? base.store : { schema_version: 1, trusted_scripts: {}, confirmed_sections: '' };
  const prev = store.trusted_scripts[name];
  store.trusted_scripts[name] = sha;
  const gced = [];
  try {
    const present = new Set(fs.readdirSync(path.join(core.GOS_DIR, 'gates')));
    for (const k of Object.keys(store.trusted_scripts)) {
      if (!present.has(k)) { delete store.trusted_scripts[k]; gced.push(k); }
    }
  } catch { /* gates dir vanished mid-run — nothing to GC against */ }
  core.writeAtomicJson(path.join(core.GOS_DIR, core.GOS_PATHS.trust.rel), store);
  console.log(`${core.CONTRACTS.gate_verdicts.trustRegistered}${name} (sha256 ${sha.slice(0, 16)})`);
  if (prev === sha) console.log('(hash unchanged — was already trusted)');
  if (gced.length) console.log(`${core.CONTRACTS.gate_verdicts.trustGc}${gced.join(', ')}`);
}

function cmdGate(args) {
  // gos gate trust <name>: hash registration must work on unmanaged trees too
  // (setup seeding runs before any `gos init`).
  if (args[0] === 'trust') { cmdGateTrust(args); return; }
  // [Phase D T10 → D-01, R-35] gate --exempt <section> --reason "<why>": explicit,
  // machine-local, auto-expiring exemption. --reason is MANDATORY, >=10 codepoints
  // after sanitization (truth-waive precedent — an exemption must be auditable).
  // Line grammar pinned `<iso8601> <section> :: <reason>` (single line, no # — a
  // #-prefixed form would be filtered as a comment by the one-shot reader).
  if (args[0] === '--exempt') {
    const sec = args[1];
    if (!sec || sec.startsWith('--')) core.die('Usage: gos gate --exempt <section-name> --reason "<why>"   (--reason mandatory, >=10 codepoints)');
    if (/[\s#]/.test(sec)) core.die('gate --exempt: section name must be a single token without whitespace or # (line grammar: <iso8601> <section> :: <reason>)');
    const ri = args.indexOf('--reason');
    const rawReason = ri >= 0 ? args[ri + 1] : null;
    const reason = rawReason == null ? '' : String(rawReason).replace(/[\r\n#]+/g, ' ').replace(/\s+/g, ' ').trim();
    if (rawReason == null || core.cpLen(reason) < 10) {
      core.die('gate --exempt: --reason is mandatory and must be at least 10 codepoints after sanitization (single line, no #) — one-shot exemptions must be auditable [R-35]');
    }
    const root = core.mapRootDir();
    core.acquireEdgeLock();
    // B-18-class hardening (mirrors appendTruthReceipt): a planted symlink at
    // the ledger path must not redirect exemption content in cloned repos.
    const exemptPath = path.join(root, '.gos', EXEMPT_LOG_REL);
    if (fs.existsSync(exemptPath) && !fs.lstatSync(exemptPath).isFile()) {
      core.die(`gate exempt: ${exemptPath} is not a regular file (symlink?) — write refused (B-18)`);
    }
    try { fs.appendFileSync(exemptPath, `${new Date().toISOString()} ${sec} :: ${reason}\n`,
      { flag: fs.constants.O_APPEND | fs.constants.O_CREAT | fs.constants.O_WRONLY | fs.constants.O_NOFOLLOW }); } catch (e) { core.die(`cannot write exemptions.log: ${e.message}`); }
    console.log(`✓ exemption recorded: ${sec} — ${reason} (consumed + cleared at next gos commit — one-shot by design)`);
    return;
  }
  // Flag-tolerant positional parse: `gate --audit` and `gate all --audit` both
  // resolve the check set to `all`; flags never masquerade as check names.
  const auditMode = args.includes('--audit');
  const positional = args.filter((a) => !String(a).startsWith('--'));
  const which = (positional[0] || 'all').toLowerCase();
  const state = core.readState();
  // Audit mode: a stateless tree (CI checkout, fresh clone) skips every
  // task-level check and runs the structural layer only. With a state present
  // --audit changes nothing — identical to a plain gate all.
  // Structural subcommand: gate codemap inspects map data only and never
  // consumes task state — it must run on stateless trees (CI checkouts),
  // same philosophy as `gate all --audit`. gate flip (T8) is the same shape:
  // the flip-reconcile leg reads census/git/manifest, never task state.
  const structuralOnly = which === 'codemap' || which === 'flip';
  if (!state && !(auditMode && which === 'all') && !structuralOnly) {
    core.die(`${core.CONTRACTS.state_semantics.noActiveTask} \`gos init\` first.`);
  }
  // DONE is "no active task" for audit purposes: an archived task's plan is
  // gone from .gos/task/, so task-level checks cannot run against it.
  const auditNoState = !state || (state.current_stage === 'DONE' && process.argv.includes('--audit'));
  if (auditNoState) console.log('⚠ gate audit: no active task — task-level checks skipped, structural layer only');
  // B-19 [R3-F4] lock reordering: builtin layer (incl. semantic engine + anchor
  // verification, which read project files) holds the lock; the gates.json lint and
  // custom-script layers run UNLOCKED (long user scripts must not block GOS).
  const failures = [];
  let checked = 0;
  // B-3 [R1-F11+R3-F9]: ✓ lines from semantic_checks-table check types (coverage/
  // truths/lessons) arm the green-light downgrade banner — emitted as LAST line.
  let semanticPass = 0;

  // ---- builtin layer (upgraded: check file contents, not just booleans) ----
  if (!auditNoState && (which === 'all' || which === 'coverage')) {
    checked++;
    // First check state.json booleans (quick)
    const uncoveredState = state.decisions.filter(d => !d.covered);
    // Then cross-check plan.md actual content (deep)
    const planTasks = task.parsePlanMd();
    let coveredInPlan = new Set();
    if (planTasks) {
      for (const t of planTasks) for (const c of t.covers) coveredInPlan.add(c);
    }
    const uncoveredDeep = state.decisions.filter(d =>
      !d.covered && !coveredInPlan.has(d.id)
    );
    const uncovered = (planTasks && planTasks.length) ? uncoveredDeep : uncoveredState;
    if (uncovered.length) {
      failures.push(core.gateFail('coverage-uncovered', { verdict: 'decisions not covered by any task', evidence: uncovered.map((d) => `${d.id} (${d.title})`), fix: core.gateCmd('node bin/gos.cjs stage back', 'plan') + ' — add a covering task or drop the decision' }));
    } else {
      const viaPlan = planTasks ? ` (${coveredInPlan.size} via plan.md scan)` : '';
      console.log(`✓ coverage: ${state.decisions.length}/${state.decisions.length} decisions covered${viaPlan}`);
      semanticPass++;
    }
  }
  if (!auditNoState && (which === 'all' || which === 'truths')) {
    checked++;
    const unverified = state.observable_truths.filter(t => !t.verified && !t.waived);
    const waived = state.observable_truths.filter(t => t.waived);
    if (waived.length) console.log(`⚠ truths: ${waived.length} waived (external/blocked) — ${waived.map(t => `${t.id}: ${(t.waive_reason || '').slice(0, 50)}`).join('; ')}`);
    // REVIEW #7: legacy `evidence.length < 5` string check was dead code under the D-30
    // object schema (.length on an object = undefined) — object-form validation only.
    const noEvidence = state.observable_truths.filter(t => t.verified && (!t.evidence || typeof t.evidence !== 'object'));
    if (unverified.length) {
      failures.push(core.gateFail('truths-unverified', { verdict: 'observable truths recorded but not yet verified', evidence: unverified.map((t) => `${t.id} (${t.description || ''})`), fix: core.gateCmd('node bin/gos.cjs truth verify', '<T-id>') + ' — verify each truth (manual or --replay)' }));
    } else if (noEvidence.length) {
      failures.push(core.gateFail('truths-evidence-shape', { verdict: 'verified truths whose evidence is not the {command, output_excerpt, artifact_path} object', evidence: noEvidence.map((t) => t.id), fix: core.gateCmd('node bin/gos.cjs truth verify', '<T-id>') + ' — re-record with the three-element evidence' }));
    } else {
      console.log(`✓ truths: ${state.observable_truths.length}/${state.observable_truths.length} verified with evidence`);
      semanticPass++;
    }
    // T4 [B-1]: manual evidence is tolerated but flagged — replay is the verification bar [R3-F8]
    const manualN = state.observable_truths.filter((t) => t && t.evidence && t.evidence.manual === true).length;
    if (manualN > 0) console.log(`⚠ ${core.CONTRACTS.semantic_checks.manualWarning.replace('N', String(manualN))}`);
  }
  if (!auditNoState && (which === 'all' || which === 'semantic')) {
    // T5+T7 [D-33] three-layer mount layer 2: gate all chains the semantic engine
    // (same semanticChecks(), never a copy). ✓ lines count toward the downgrade banner.
    checked++;
    const res = semanticChecks({ state });
    if (res.failures.length) failures.push(...res.failures);
    semanticPass += res.passes;
  }
  if (!auditNoState && (which === 'all' || which === 'requirements')) {
    const Lv4 = state.level >= 4;
    if (Lv4) {
      const unclaimed = state.requirements.filter(r => !r.phase);
      checked++;
      if (unclaimed.length) {
        failures.push(core.gateFail('requirements-unclaimed', { verdict: 'requirements not claimed by any phase', evidence: unclaimed.map((r) => `${r.id} (${r.text})`), fix: core.gateCmd('node bin/gos.cjs phase claim', '<n>') + ' — claim the phase that covers them' }));
      } else {
        console.log(`✓ requirements: ${state.requirements.length}/${state.requirements.length} claimed`);
      }
    } else {
      console.log(`- requirements: Lv${state.level} implicit (R-01 = intent), skip claim check`);
    }
  }

  // ---- lessons: json-truth integrity (five invariants) + dual-side expiry (B-11) ----
  // REVIEW #8 lineage: runs INSIDE the locked builtin section (B-19). The gate
  // process holds .gos/.lock, so md render-hash regeneration degrades to an
  // advisory here (C8/N9 — regen joins the next mutation).
  if (!auditNoState && (which === 'all' || which === 'lessons')) {
    const LP = core.lessonsPaths('project');
    // (a) json truth integrity — same implementation as commit embed + lessons
    // family (single source, REVIEW #6): chain/ids/shapes + sidecar diff + git
    // out-of-band channel (the old md-diff auxiliary folded into the API)
    checked++;
    if (fs.existsSync(LP.truth)) {
      const lres = knowledge.loadStore(LP);
      if (lres.failures.length) {
        failures.push(...lres.failures);
      } else {
        console.log('✓ lessons: json truth intact (chain, ids, shapes, no undeleted deletions)');
        semanticPass++;
        // (b) md view freshness — advisory under the gate's lock
        knowledge.ensureLessonsMdFresh(LP, lres.store, { where: 'project' });
      }
    } else {
      console.log('- lessons: no lessons.json yet (pre-migration; first lessons command migrates)');
    }
    // (c) expiry — BOTH sides, display loads (advisory warn, never blocking; a
    // bad lessons file must not be amplified by gate — N9)
    const expired = [];
    let anyLessonsJson = false;
    for (const src of [{ label: 'project', P: core.lessonsPaths('project') }, { label: 'global', P: core.lessonsPaths('model') }]) {
      if (!fs.existsSync(src.P.truth)) continue; // pre-migration side = nothing to check
      const disp = knowledge.loadStoreDisplay(src.P);
      if (!disp.ok || !disp.store) continue;
      anyLessonsJson = true;
      for (const e of disp.store.entries) {
        if (e.expires && new Date(e.expires + 'T23:59:59') < new Date()) {
          expired.push(`[${src.label}] (${String(e.id).slice(0, 8)}) ${String(e.lesson || e.text || '').slice(0, 60)}`);
        }
      }
    }
    if (anyLessonsJson) {
      checked++;
      if (expired.length) {
        console.log(`⚠ lessons: ${expired.length} EXPIRED model-type lesson(s) — confirm still-valid or dispose:`);
        for (const e of expired) console.log(`    ${e}...  (gos lessons rm <id-prefix> --reason "...")`);
      } else {
        console.log('✓ lessons: no expired entries (dual-side)');
        semanticPass++;
      }
    }
  }

  // ---- [Phase P T6 / D-38] gate codemap: map data health + fn-level closure advisory ----
  // FAIL items are "data deterministically broken" (fail-closed, dead-edge precedent) —
  // the D-26 advisory red line (closure quality) is NOT turned into a hard gate here.
  if (which === 'all' || which === 'codemap') {
    checked++;
    const cmRoot = core.mapRootDir();
    const deps = map.loadDeps(cmRoot);   // ② absent → single advisory line, never core.die (F7a)
    if (!deps) {
      console.log('⚠ codemap: no deps.json on disk — run: gos map scan first (advisory, not blocking)');
      checked--;   // capability not enabled — gate stays honest without blocking new clones
    } else {
      const sem = deps.semantic || {};
      // ---- require-direction assertion: cross-module require edges ⊆ require-allowlist.json (code-level, fail-closed) ----
      // v2 file = generic moduleRoots/directions (any repo layout); legacy v1 file kept
      // working only for bin/lib-shaped repos; absent file = advisory (capability off).
      const dirRes = map.directionAssertion(cmRoot, deps);
      for (const line of dirRes.lines) console.log(line);
      failures.push(...dirRes.failures);
      if (sem.acorn_missing) console.log('⚠ codemap: acorn not installed — fn-level data unavailable (see: core.CONTRACTS acornMissing); install acorn then re-run: gos map scan');   // ①' capability advisory, never FAIL
      const pf = sem.parse_failures || [];
      if (pf.length) failures.push(core.gateFail('codemap-parse-failures', { verdict: core.CONTRACTS.semantic_checks.parseFailures.replace('<N>', String(pf.length)).replace('<files>', pf.map((x) => x.file).join(', ')), evidence: pf.map((x) => x.file), fix: core.gateCmd('node bin/gos.cjs map scan') + ' — fix the parse errors or refresh the map' }));   // ① FAIL
      const deadAnn = sem.dead_fn_annotations || [];
      if (deadAnn.length) failures.push(core.gateFail('codemap-dead-annotation', { verdict: `${deadAnn.length} dead gos-map:fn annotation(s) — they point at fns that no longer exist`, evidence: deadAnn, fix: 'fix or remove the dead annotations (dead data misleads the codemap)' }));   // ⑤ FAIL
      // ---- repo-wide unique-name hard assertion (monolith semantic conservation; scan set includes files outside bin/, plugin exemptions noted in the allowlist) ----
      const dupNames = sem.dup_names || [];
      if (dupNames.length) for (const n of dupNames.slice(0, 5)) failures.push(core.gateFail('codemap-dup-fn-name', { verdict: `duplicate fn name across files: ${n} — global uniqueness required`, evidence: [n], fix: 'rename the fn or qualify the annotation; bare annotations are rejected at parse time' }));
      else console.log('✓ codemap: repo-wide unique-name assertion green (dup_names = ∅)');
      // ③ self-consistency: acorn top-level count (deps.fn_count) vs cheap regex recount.
      // Missing fn_count family (schema-window between P-T2 and P-T3 commits) → advisory, not FAIL (F-M8).
      if (typeof sem.fn_count !== 'number') {
        console.log('⚠ codemap: no fn_count in cache (schema window) — self-consistency skipped (advisory)');
      } else {
        let reCount = 0;
        for (const f of deps.files || []) {
          if (!map.SEMANTIC_CODE_EXTS.has(path.extname(f))) continue;
          try { reCount += (fs.readFileSync(path.join(cmRoot, f), 'utf8').match(/^(async )?function \w+\(/gm) || []).length; } catch { /* file gone */ }
        }
        const drift = sem.fn_count === 0 ? (reCount === 0 ? 0 : 1) : Math.abs(reCount - sem.fn_count) / sem.fn_count;
        if (drift > 0.2) failures.push(core.gateFail('codemap-fn-drift', { verdict: `fn self-consistency drift ${(drift * 100).toFixed(0)}% (cache fn_count=${sem.fn_count} vs regex recount=${reCount})`, evidence: [`cache=${sem.fn_count}`, `regex=${reCount}`], fix: core.gateCmd('node bin/gos.cjs map scan') + ' — refresh the cached semantic data' }));   // FAIL
        else { console.log(`✓ codemap: fn self-consistency (${sem.fn_count} acorn ≈ ${reCount} regex)`); semanticPass++; }
      }
      // ④ cmd-entry fns present in this repo's callgraph but never covered by gos-map:fn (advisory — F3 boundary)
      const testedFns = new Set((sem.testof_fn || []).map((t) => `${t.file}#fn:${t.fn}`));
      const cmdFns = new Set(Object.keys(core.COMMANDS).map((c) => 'cmd' + c[0].toUpperCase() + c.slice(1)));
      const untestedCmdFns = [...new Set((sem.callgraph || []).map((e) => `${e.file}#fn:${e.from}`).concat(...(sem.callgraph || []).map((e) => `${e.file}#fn:${e.to}`)))].filter((k) => cmdFns.has(k.split('#fn:')[1])).filter((k) => !testedFns.has(k)).sort();
      if (untestedCmdFns.length) console.log(`⚠ codemap: ${untestedCmdFns.length} cmd-entry fn(s) without any gos-map:fn annotation — cmd-level drill-down relies on annotations: [${untestedCmdFns.slice(0, 8).join(', ')}${untestedCmdFns.length > 8 ? ', …' : ''}]`);
      else console.log('✓ codemap: all cmd-entry fns annotated');
      // ---- [Phase R/D-01] DI-5: fn test-coverage report (advisory; full list on disk) ----
      // D-20: byproduct renamed unmapped-fns.txt — the list is "callgraph fns the
      // test-annotation map does not cover", i.e. unmapped, not "untested".
      const cgFns = new Set();
      for (const e of (sem.callgraph || [])) { cgFns.add(`${e.file}#fn:${e.from}`); cgFns.add(`${e.file}#fn:${e.to}`); }
      const covFns = new Set((sem.testof_fn || []).map((t) => `${t.file}#fn:${t.fn}`));
      const unmappedFns = [...cgFns].filter((k) => !covFns.has(k)).sort();
      if (!cgFns.size) console.log('⚠ codemap: no callgraph fns — fn coverage report unavailable');
      else if (!unmappedFns.length) { console.log('✓ codemap: all fns test-covered'); semanticPass++; }
      else {
        const covPct = Math.round(((cgFns.size - unmappedFns.length) * 100) / cgFns.size);
        // D-20 provenance header: first line = generated-at + HEAD[0:8] anchor; unborn
        // repo degrades to the literal 'unborn' marker (mapGitInfo precedent).
        const headSha = core.gitHeadSha();
        const provHeader = `generated-at: ${new Date().toISOString().replace(/\.\d+Z$/, 'Z')} @ ${headSha ? headSha.slice(0, 8) : 'unborn'}`;
        try { fs.mkdirSync(path.join(cmRoot, '.gos', 'codebase'), { recursive: true }); fs.writeFileSync(path.join(cmRoot, '.gos', 'codebase', 'unmapped-fns.txt'), `${provHeader}\n${unmappedFns.join('\n')}\n`); } catch { /* list file is best-effort */ }
        console.log(`⚠ codemap: ${unmappedFns.length}/${cgFns.size} unmapped fn(s) without test annotation (${covPct}% coverage) — full list: .gos/codebase/unmapped-fns.txt: [${unmappedFns.slice(0, 8).join(', ')}${unmappedFns.length > 8 ? ', …' : ''}]`);
      }
      // ---- C4 baseline alerts (advisory): peak comparison + tiered missing list + fingerprint; all advisory ----
      const blPath = path.join(cmRoot, '.gos', 'codebase', 'edge-baseline.json');
      if (!fs.existsSync(blPath)) console.log('⚠ codemap: no edge baseline (.gos/codebase/edge-baseline.json) — run: gos map scan to establish (drop detection off)');
      else {
        try {
          const bl = JSON.parse(fs.readFileSync(blPath, 'utf8'));
          const peak = bl.peak || bl;   // legacy flat shape compat
          const cur = map.edgeStats(deps);
          const curFns = new Set(sem.fn_universe || []);
          const peakFns = Array.isArray(peak.fns) ? peak.fns : [];
          const missing = peakFns.filter((f) => !curFns.has(f));
          // ① total edge drop (>15% AND >10)
          if (typeof peak.total === 'number' && peak.total > 0) {
            const dropAbs = peak.total - cur.total, dropPct = dropAbs / peak.total;
            if (dropPct > 0.15 && dropAbs > 10) console.log(`⚠ codemap: edge count drop vs peak ${(dropPct * 100).toFixed(0)}% (${peak.total} → ${cur.total}) — extractor degradation suspected (thresholds: 15% / 10)`);
          }
          // ② fn_count drop >15% + tiered missing list (small repos: full list; large repos: per-dir aggregate)
          if (typeof peak.fn_count === 'number' && peak.fn_count > 0) {
            const fnDropPct = (peak.fn_count - cur.fn_count) / peak.fn_count;
            if (fnDropPct > 0.15 || missing.length) {
              if (peak.fn_count <= 50) console.log(`⚠ codemap: fn missing vs peak (${missing.length}): [${missing.join(', ')}]`);
              else {
                const byDir = {};
                const owners = peak.owners || {};
                for (const f of missing) { const d = String(owners[f] || f).split('/').slice(0, -1).join('/') || '(root)'; byDir[d] = (byDir[d] || 0) + 1; }
                const top = Object.entries(byDir).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([d, n]) => `${d}: ${n}`).join('; ');
                console.log(`⚠ codemap: fn missing vs peak ${missing.length}/${peak.fn_count} — by dir: ${top}`);
              }
            }
          }
          // ③ set fingerprint change (catches ±1 swaps)
          if (peak.fp) {
            const fp = map.fnSetFingerprint(sem.fn_universe);
            if (fp !== peak.fp) console.log(`⚠ codemap: fn-set fingerprint changed (${peak.fp} → ${fp}) — any add/remove/swap triggers it`);
          }
        } catch { /* corrupt baseline — best-effort advisory layer */ }
      }
    }
  }

  // ---- [P4 T8 / D-15 / D-14] flip-reconcile leg: census/git/manifest
  // agreement on every tracked .gos file (structural — stateless-tree
  // capable, same registration shape as codemap above) ----
  if (which === 'all' || which === 'flip') {
    checked++;
    const flipRes = flipReconcileLeg();
    if (flipRes.skipped) checked--;   // not a git worktree: capability off, ⚠ printed
    else if (flipRes.failures.length) failures.push(...flipRes.failures);
  }

  // ---- B-19 [R3-F4]: builtin layer done → release lock before user-script layers ----
  core.releaseLock();

  // ---- config layer: .gos/gates.json ----
  let gatesJsonActive = false;   // any live protect/lint/forbid rule (drives the empty-layer hint)
  const gatesJsonPath = path.join(core.GOS_DIR, 'gates.json');
  if (fs.existsSync(gatesJsonPath)) {
    checked++;
    try {
      const rules = JSON.parse(fs.readFileSync(gatesJsonPath, 'utf8'));
      gatesJsonActive = !!(Array.isArray(rules.protect) && rules.protect.length)
        || !!(rules.lint && String(rules.lint).trim())
        || !!(Array.isArray(rules.forbid) && rules.forbid.length);
      // protect: path blacklist — fail if any listed path has uncommitted modifications or exists in staged diff
      if (Array.isArray(rules.protect) && rules.protect.length) {
        const changed = core.safeGitArgv(['status', '--porcelain']);
        const changedFiles = changed.split('\n').filter(Boolean).map(l => l.slice(3).trim());
        const hit = [];
        for (const pattern of rules.protect) {
          const re = core.globToRegex(pattern);
          for (const f of changedFiles) if (re.test(f)) hit.push(`${f} (protect: ${pattern})`);
        }
        if (hit.length) failures.push(core.gateFail('gates-protect-hit', { verdict: 'protected path rule matched — these paths must never be touched by this task', evidence: [...new Set(hit)], fix: 'revert the changes to the protected paths' }));
        else console.log(`✓ protect: ${rules.protect.length} rule(s), no violation`);
      }
      // lint: run user's lint command; non-zero exit = fail
      if (rules.lint) {
        const out = core.tryCmd(rules.lint);
        checked++;
        if (!out.ok) failures.push(core.gateFail('gates-lint-exit', { verdict: `lint rule "${rules.lint}" exited ${out.code}`, evidence: out.out.split('\n').slice(-5), fix: core.gateCmd('node bin/gos.cjs gate', 'all') + ' — fix the lint violations above' }));
        else console.log(`✓ lint: "${rules.lint}" passed`);
      }
      // forbid: pattern must not appear in tracked files
      if (Array.isArray(rules.forbid) && rules.forbid.length) {
        checked++;
        const violations = [];
        for (const rule of rules.forbid) {
          const m = rule.match(/^(.*?)\s+in\s+(.*)$/);
          const [pat, dir] = m ? [m[1], m[2]] : [rule, '.'];
          const out = core.safeGitArgv(['grep', '-l', '-E', pat, '--', dir]);
          if (out.trim()) violations.push(`${pat} found in: ${out.trim().split('\n').slice(0, 3).join(', ')}`);
        }
        if (violations.length) failures.push(core.gateFail('gates-forbid-pattern', { verdict: 'forbid-pattern rule matched — the matched text is banned in this repo', evidence: violations, fix: 'remove the banned text' }));
        else console.log(`✓ forbid: ${rules.forbid.length} rule(s), no violation`);
      }
    } catch (e) {
      gatesJsonActive = true;   // broken file is already a FAIL — never also hint "empty"
      failures.push(core.gateFail('gates-json-invalid', { verdict: `gates.json invalid: ${e.message}`, evidence: [gatesJsonPath], fix: 'fix the JSON syntax in .gos/gates.json (or remove the file)' }));
    }
  }

  // ---- discoverability: report user custom gates (helps users realize they exist) ----
  // (inside gate run; for doctor see below)

  // ---- custom layer: .gos/gates/*.sh|*.js|*.cjs — hash-trust verification ----
  // A script only executes when its CURRENT sha256 matches the machine-local
  // trust registry. Untrusted/drifted/unreadable scripts are skipped + FAIL
  // locally; CI/audit mode (GOS_CI / --audit) skips them with a loud advisory
  // so a fresh clone never fails structurally for lack of a trust store.
  const gatesDir = path.join(core.GOS_DIR, 'gates');
  const customScripts = fs.existsSync(gatesDir)
    ? fs.readdirSync(gatesDir).filter((f) => /\.(sh|js|cjs)$/.test(f)).sort()
    : [];
  const ciMode = auditMode || ['1', 'true', 'yes', 'on'].includes(String(process.env.GOS_CI || '').trim().toLowerCase());
  {
    const T = core.CONTRACTS.gate_verdicts;
    // (1) trust keys must never ride the TRACKED config.json — a PR carrying
    // hashes would re-arm execution on every clone. Independent of any script.
    const polluted = [];
    try {
      const rawCfg = JSON.parse(fs.readFileSync(core.resolvePath('config'), 'utf8'));
      for (const k of ['trusted_scripts', 'confirmed_sections']) {
        if (Object.prototype.hasOwnProperty.call(rawCfg, k)) polluted.push(k);
      }
    } catch { /* absent/invalid config — its own consumers report that */ }
    if (polluted.length) failures.push(core.gateFail('trust-config-polluted', { verdict: `${T.trustConfigPolluted} (found in config.json: ${polluted.join(', ')})`, evidence: polluted, fix: 'remove the trust block from .gos/config.json (trust lives in cache only)' }));
    // (2) trust store health: unreadable/corrupt → every script untrusted
    const trustRes = loadTrustStore();
    if (!trustRes.ok) {
      const line = T.trustStoreUnreadable;
      if (ciMode) console.log(`⚠ ${line}`);
      else failures.push(core.gateFail('trust-store-unreadable', { verdict: line, evidence: [], fix: 'restore .gos/cache/trust.json (or re-confirm sections via gate prompts) — corrupt store = every script untrusted' }));
    }
    // (3) verify + execute each script
    for (const s of customScripts) {
      checked++;
      const full = path.join(gatesDir, s);
      let sha = null;
      try { sha = core.sha256FileSync(full); } catch { sha = null; }
      const skip = (key) => {
        const line = ciMode ? T.trustCiAdvisory.replace(/<name>/g, s) : key.replace(/<name>/g, s);
        if (ciMode) console.log(`⚠ ${line}`);
        else failures.push(core.gateFail('gate-trust-skip', { verdict: line, evidence: [full], fix: core.gateCmd('node bin/gos.cjs gate', 'all') + ' — re-run and confirm the script hash when prompted (trust is opt-in, hash-pinned)' }));
      };
      if (sha == null) { skip(T.trustUnreadableScript); continue; }
      const trusted = trustRes.ok ? trustRes.store.trusted_scripts[s] : undefined;
      if (trusted === undefined) { skip(T.trustUntrusted); continue; }
      if (trusted !== sha) { skip(T.trustDrift); continue; }
      const cmd = s.endsWith('.sh') ? `bash ${core.shellQ(full)}` : `node ${core.shellQ(full)}`;
      const out = core.tryCmd(cmd);
      if (!out.ok) failures.push(core.gateFail('custom-gate-exit', { verdict: `custom gate ${s}: exit ${out.code}`, evidence: out.out.split('\n').slice(-3), fix: `fix the failing custom gate script (.gos/gates/${s})` }));
      else console.log(`✓ custom gate ${s}: passed (trusted)`);
    }
    // (4) empty-state hint: nothing custom configured yet — teach the capability
    if (which === 'all' && !customScripts.length && !gatesJsonActive) {
      console.log(`- ${T.customGateEmpty}`);
    }
  }

  // ---- Phase W (T6, D-12/R-06): orphan detection + README regen guard ----
  // advisory by default (BUILD-in-progress transient files never fail the gate);
  // --strict escalates orphans to FAIL (CI / one-shot audit semantics).
  const strictMode = args.includes('--strict');
  {
    const orphans = auditNoState ? [] : sibDoctor.detectOrphans(state);
    if (orphans.length) {
      checked++;
      const line = sibDoctor.orphanAdvisoryLine(orphans.length);
      if (strictMode) {
        failures.push(core.gateFail('orphan-unregistered', { verdict: line, evidence: orphans.slice(0, 10).concat(orphans.length > 10 ? [`…(+${orphans.length - 10} more)`] : []), fix: core.gateCmd('node bin/gos.cjs commit ship') + ' — adopt via the ship ritual, or remove the strays' }));
      } else {
        console.log(`⚠ ${line}`);
        console.log(`⚠ orphan files: ${orphans.slice(0, 10).join(', ')}${orphans.length > 10 ? `, …(+${orphans.length - 10})` : ''}`);
      }
    }
    // README regen guard (R-03): hand edits to the generated README = drift → FAIL always.
    // gate all ONLY (sub-commands like `gate codemap` may run in clones without a README).
    if (which === 'all') {
      checked++;
      const readmePath = core.resolvePath('readme');
      const expected = render.renderPathsMarkdown();
      let actual = null;
      try { actual = fs.readFileSync(readmePath, 'utf8'); } catch { /* missing */ }
      if (actual !== expected) failures.push(core.gateFail('readme-drift', { verdict: core.CONTRACTS.gate_verdicts.readmeDrift, evidence: [core.resolvePath('readme')], fix: core.gateCmd('node bin/gos.cjs paths --markdown') + ' — restore the generated view (hand edits forbidden)' }));
      else console.log('✓ README regen guard: matches registry');
    }
    // changelog lint joins gate all's structural layer. The verdict logic lives
    // in the changelog lint command — the single implementation the standalone
    // `gos changelog lint` runs. It exits the process itself, so the only
    // drift-free integration is invoking the CLI as a subprocess. A missing
    // CHANGELOG.md stays advisory: lint exits 0 there (obligations start once
    // the file exists); lint violations hard-fail, matching the command's own
    // exit semantics.
    if (which === 'all') {
      checked++;
      let lintOut = '';
      let lintRc = 0;
      try {
        lintOut = execFileSync(process.execPath,
          [path.join(core.GOS_SELF_ROOT, 'bin', 'gos.cjs'), 'changelog', 'lint'],
          { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000 });
      } catch (e) {
        lintRc = e.status == null ? 1 : e.status;
        lintOut = `${e.stdout || ''}${e.stderr || ''}`;
      }
      if (lintRc !== 0) {
        const tail = String(lintOut).trim().split('\n').filter(Boolean).slice(-3).join('\n');
        failures.push(core.gateFail('changelog-lint', { verdict: `changelog lint: ${tail || `exited ${lintRc}`}`, evidence: String(lintOut).trim().split('\n').slice(-3), fix: core.gateCmd('node bin/gos.cjs changelog', 'lint') + ' — see the lint report and fix CHANGELOG.md' }));
      } else {
        const last = String(lintOut).trim().split('\n').filter(Boolean).pop();
        console.log(last || '✓ changelog lint: CHANGELOG.md clean');
      }
    }
    // CJK boundary lint (repo Englishization): tracked files must be CJK-free
    // unless covered by .gos/cjk-whitelist.json. The lint is
    // fail-closed in every direction (unlisted hit / ghost whitelist entry /
    // drifted history pin / broken whitelist) and runs in task mode and
    // --audit mode alike — it is a repo-level structural check, independent
    // of task state. Self-repo only: the whitelist describes THIS repo, so
    // projects consuming the CLI skip silently (their cwd work tree is not
    // the CLI's own checkout).
    const selfRepo = (() => {
      try {
        const cwdRoot = execFileSync('git', ['rev-parse', '--show-toplevel'],
          { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
        return cwdRoot !== '' && path.resolve(cwdRoot) === path.resolve(core.GOS_SELF_ROOT);
      } catch { return false; }
    })();
    if (which === 'all' && selfRepo) {
      checked++;
      let cjkOut = '';
      let cjkRc = 0;
      try {
        cjkOut = execFileSync('bash',
          [path.join(core.GOS_SELF_ROOT, 'test', 'checks', 'cjk-lint.sh')],
          { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 120000 });
      } catch (e) {
        cjkRc = e.status == null ? 1 : e.status;
        cjkOut = `${e.stdout || ''}${e.stderr || ''}`;
      }
      if (cjkRc !== 0) {
        const tail = String(cjkOut).trim().split('\n').filter(Boolean).slice(-3).join('\n');
        failures.push(core.gateFail('cjk-lint', { verdict: `cjk lint: ${tail || `exited ${cjkRc}`}`, evidence: String(cjkOut).trim().split('\n').filter(Boolean).slice(-3), fix: 'remove the CJK text or add a whitelisted entry with an English reason — see test/checks/cjk-lint.sh' }));
      } else {
        const last = String(cjkOut).trim().split('\n').filter(Boolean).pop();
        console.log(last || '✓ cjk lint: tracked tree clean');
      }
      // ascii-filenames: name discipline peer of cjk-lint (content) — all
      // tracked path segments pure ASCII; empty-track/not-a-repo refuse to
      // pass vacuously (exit 2). Same selfRepo scope: the naming rule is a
      // property of THIS repo's tracked tree.
      checked++;
      let ascOut = '';
      let ascRc = 0;
      try {
        ascOut = execFileSync('bash',
          [path.join(core.GOS_SELF_ROOT, 'test', 'checks', 'ascii-filenames.sh')],
          { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 120000 });
      } catch (e) {
        ascRc = e.status == null ? 1 : e.status;
        ascOut = `${e.stdout || ''}${e.stderr || ''}`;
      }
      if (ascRc !== 0) {
        const tailA = String(ascOut).trim().split('\n').filter(Boolean).slice(-3).join('\n');
        failures.push(core.gateFail('ascii-filenames', { verdict: `ascii filenames: ${tailA || `exited ${ascRc}`}`, evidence: String(ascOut).trim().split('\n').filter(Boolean).slice(-3), fix: 'rename the file to a pure-ASCII path or drop it from the tree — see test/checks/ascii-filenames.sh' }));
      } else {
        const lastA = String(ascOut).trim().split('\n').filter(Boolean).pop();
        console.log(`✓ ${lastA || 'ascii filenames: tracked names clean'}`);
      }
      // ai-trace lint (AI-process artifact boundary): content-lineage peer of
      // cjk-lint. Tracked files must describe WHAT the code does, never WHY a
      // task decided it — new lineage markers hard-fail; the legacy stock
      // rides the curated whitelist and shrinks via the sweep. Failure
      // evidence quotes counts only; anchor excerpts stay behind the lint's
      // --json machine view.
      checked++;
      let traceOut = '';
      let traceRc = 0;
      try {
        traceOut = execFileSync('bash',
          [path.join(core.GOS_SELF_ROOT, 'test', 'checks', 'ai-trace-lint.sh')],
          { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 120000 });
      } catch (e) {
        traceRc = e.status == null ? 1 : e.status;
        traceOut = `${e.stdout || ''}${e.stderr || ''}`;
      }
      const traceLines = String(traceOut)
        .replace(/\x1b\[[0-9;?]*[A-Za-z]/g, '') // ANSI CSI strip — evidence lines print clean
        .trim().split('\n').filter(Boolean);
      if (traceRc !== 0) {
        const countM = traceLines.join('\n').match(/(\d+) violation\(s\)/);
        const traceSummary = traceLines.filter((l) => l.includes('ai-trace lint:')).slice(-3);
        failures.push(core.gateFail('ai-trace-lint', {
          verdict: `ai-trace lint: ${countM ? `${countM[1]} violation(s)` : `exited ${traceRc}`} — machine view: bash test/checks/ai-trace-lint.sh --json`,
          evidence: traceSummary.length ? traceSummary : [`ai-trace lint: exited ${traceRc} without a summary`],
          fix: 'remove the anchor / rewrite the comment to WHAT — lineage belongs in the commit body or CHANGELOG.md',
        }));
      } else {
        const traceOk = traceLines.slice(-2).join('\n');
        console.log(traceOk || '✓ ai-trace lint: tracked tree clean');
      }
    }
  }

  if (!checked) { console.log('- nothing to check (no decisions/truths/rules)'); return; }
  // ---- bare-name gos-map:fn annotation advisory (multi-file byName first-win can silently mis-bind) ----
  // Inline block (no new top-level fn); new bare names yield an advisory line and a --json verdict entry.
  const bareNameAdvisories = [];
  {
    const secDir = path.join(core.mapRootDir(), 'test', 'sections');   // USER project root — bare-name advisory covers product sections too
    let secFiles = [];
    try { secFiles = fs.readdirSync(secDir).filter((f) => /^T.*\.test\.sh$/.test(f)).sort(); } catch { secFiles = []; }
    for (const f of secFiles) {
      let head = [];
      try { head = fs.readFileSync(path.join(secDir, f), 'utf8').split('\n').slice(0, 5); } catch { head = []; }
      for (const l of head) {
        const m = l.match(/^#\s*gos-map:fn\s+(\S+)/);
        if (m && !m[1].includes('#')) bareNameAdvisories.push(`${f.replace(/\.test\.sh$/, '')}: gos-map:fn ${m[1]} — must be fully-qualified (path#fn:name); bare names silently mis-bind under multi-file byName first-win (D-17/DI-10)`);
      }
    }
  }
  const jsonMode = args.includes('--json');
  if (jsonMode) {
    // Machine-readable verdict: failures are OBJECT-ONLY ({code, verdict, evidence[], fix});
    // machine consumers key by `code`, humans get the 3-part block below.
    for (const f of failures) {
      if (typeof f === 'string') throw new Error(`gate --json: raw string failure post-switch (D-66): "${String(f).slice(0, 80)}" — wrap it with core.gateFail()`);
    }
    console.log(JSON.stringify({ verdict: failures.length ? 'fail' : 'pass', failures, advisories: bareNameAdvisories, checked }, null, 2));
    process.exit(failures.length ? 1 : 0);
  }
  for (const a of bareNameAdvisories) console.log(`⚠ DI-10 bare-name annotation: ${a}`);
  // B-3 [R1-F11+R3-F9]: table-driven downgrade banner — LAST line whenever any
  // semantic_checks-table check emitted ✓ (even if other checks failed).
  const emitSemanticDowngradeBanner = () => {
    if (semanticPass > 0) console.log(`⚠ ${core.CONTRACTS.semantic_checks.banner}`);
  };
  if (failures.length) {
    console.error(`\n${core.CONTRACTS.gate_verdicts.gateFailedPrefix} (${failures.length}):`);
    console.error(renderGateFailures(failures));
    emitSemanticDowngradeBanner();
    process.exit(1);
  }
  console.log(`\n${core.CONTRACTS.gate_verdicts.allPass}`);
  emitSemanticDowngradeBanner();
}

// ---------------------------------------------------------------------------
// [P4 T8 / D-15 / D-14] flip-reconcile leg — census/git/manifest agreement
// on every tracked .gos file at gate time. File-granular (RT2-F4): the
// tracked set is enumerated under .gos via the gitprobe cache (trackedUnder
// — the same set a plain tracked listing of .gos returns); per file the
// expected value comes from the most-specific census key (census-if-present:
// no census.json → value checks skip, the manifest check stays); lifecycle
// keys are exempt from existence and value assertions (.gos/task is legally
// absent post-archive / fresh-clone); mismatch FAILs in BOTH directions
// (census git:true + nothing tracked; census git:false + tracked); every
// tracked non-zone .gos file carries either census git:true sanction or a
// flip-manifest record — manifest-less FAIL in census-less repos too (the
// manifest is product-shipped). Fail-closed on gitprobe failure (§3.0).
// ---------------------------------------------------------------------------

// Flip-transaction artifacts exempt from the manifest-record requirement on
// top of TRACK_NEVER_FILES (the manifest itself is already a never-file):
// .gos/.gitignore is the surgery store every flip stages alongside its
// target — machine-managed by the transaction, never hand-flipped content.
const FLIP_TXN_STORES = ['.gos/.gitignore'];

function flipReconcileLeg() {
  const failures = [];
  if (!core.gitInWorkTree()) {
    console.log(`⚠ ${core.t('gate.flip.skipNoGit')}`);
    return { failures, skipped: true };
  }
  const tracked = core.trackedUnder('.gos/');
  if (tracked == null) {
    failures.push(core.gateFail('flip-git-probe-failed', {
      verdict: 'flip-reconcile: git truth unavailable (fail-closed) — tracked-set enumeration failed',
      evidence: [String(core.lastFailure() || 'git probe failed')],
      fix: 'resolve the git probe failure above (poisoned env, broken repo, spawn error) — the leg refuses to reconcile on unknown git truth',
    }));
    return { failures };
  }
  const top = core.gitToplevelRealpath();
  if (!top) {
    failures.push(core.gateFail('flip-git-probe-failed', {
      verdict: 'flip-reconcile: repository toplevel could not be resolved (fail-closed)',
      evidence: ['rev-parse --show-toplevel'],
      fix: 'run the gate from inside the git worktree — flip-reconcile refuses on an unknown repo root',
    }));
    return { failures };
  }
  // census-if-present; a corrupt census fails closed (it IS the ledger)
  let entries = null;
  const censusPath = path.join(top, 'census.json');
  if (fs.existsSync(censusPath)) {
    let census = null;
    try { census = JSON.parse(fs.readFileSync(censusPath, 'utf8')); }
    catch (e) {
      return { failures: [core.gateFail('flip-census-corrupt', {
        verdict: `census.json is corrupted: ${e.message}`,
        evidence: [censusPath],
        fix: 'fix census.json (parseable JSON with an entries object) — flip-reconcile fails closed on a broken ledger',
      })] };
    }
    if (census && typeof census.entries === 'object' && census.entries != null && !Array.isArray(census.entries)) entries = census.entries;
  }
  const manifestPaths = new Set(sibTrack.manifestRead(top).records.map((r) => r.path));
  const coverOf = (rel) => {
    if (!entries) return null;
    const key = sibTrack.mostSpecificCensusKey(entries, rel);
    if (key == null) return null;
    return { key, entry: (entries[key] && typeof entries[key] === 'object') ? entries[key] : {} };
  };
  // per tracked file: value agreement + manifest obligation
  for (const f of tracked) {
    if (sibTrack.TRACK_NEVER_ZONES.some((z) => f.startsWith(z))) continue;
    if (sibTrack.TRACK_NEVER_FILES.includes(f)) continue;   // manifest itself included
    if (FLIP_TXN_STORES.includes(f)) continue;              // flip-transaction surgery store
    const cover = coverOf(f);
    if (cover && cover.entry.lifecycle === true) continue;  // lifecycle zones exempt
    if (cover && cover.entry.git === false) {
      failures.push(core.gateFail('flip-census-contradicts', {
        verdict: `${f} is git-tracked but census entry ${cover.key} says git:false`,
        evidence: [f, cover.key],
        fix: core.gateCmd('node bin/gos.cjs track', f) + ' — re-run the flip so census and manifest agree, or untrack the file / fix the census entry (the ledger must describe reality)',
      }));
      continue;   // the contradiction is the repair surface for this file
    }
    const sanctioned = !!(cover && cover.entry.git === true);
    if (!sanctioned && !manifestPaths.has(f)) {
      failures.push(core.gateFail('flip-manifest-missing', {
        verdict: `${f} is git-tracked with neither census git:true sanction nor a flip-manifest record`,
        evidence: [f],
        fix: core.gateCmd('node bin/gos.cjs track', f) + ' — adopt the legacy-tracked file into .gos/track-manifest.json (manifest missing — re-run the flip)',
      }));
    }
  }
  // per census key under .gos: git:true (non-lifecycle) must match tracked reality
  if (entries) {
    for (const k of Object.keys(entries)) {
      const kk = k.endsWith('/') ? k.slice(0, -1) : k;
      if (!(kk === '.gos' || kk.startsWith('.gos/'))) continue;
      const entry = (entries[k] && typeof entries[k] === 'object') ? entries[k] : {};
      if (entry.git !== true || entry.lifecycle === true) continue;
      // existence = enumeration hit OR the isTracked probe (index ∪ HEAD —
      // a `git rm --cached` straggler stays tracked through the HEAD blob)
      const exists = tracked.some((f) => f === kk || f.startsWith(kk + '/'))
        || core.isTracked(path.join(top, kk));
      if (!exists) {
        failures.push(core.gateFail('flip-census-phantom', {
          verdict: `census entry ${k} says git:true but nothing under it is tracked`,
          evidence: [kk],
          fix: core.gateCmd('node bin/gos.cjs track', kk) + ' — flip the file into git, or fix the census entry (git:true zones must be tracked reality)',
        }));
      }
    }
  }
  if (!failures.length) console.log(core.t('gate.flip.pass', { n: String(tracked.length) }));
  return { failures };
}

// D-66/N6 switch renderer: 3-part block, fail-closed on non-object failures —
// a half-migrated site must crash loudly, never silently degrade (unit-tested
// by section T73: injecting a string failure throws).
// D-63↔D-66 join (C4): verdict may localize via catalog key gate.<code>
// ({what,why}); evidence and fix NEVER pass through t() (locale-invariant).
function renderGateFailures(failures, opts = {}) {
  const out = [];
  for (const f of failures) {
    if (typeof f === 'string') {
      throw new Error(`gate renderer: raw string failure post-switch (D-66): "${String(f).slice(0, 80)}" — wrap it with core.gateFail()`);
    }
    let head = f.verdict;
    const parts = core.gateVerdictParts(f.verdictKey || f.code);
    if (parts) head = parts.why ? `${parts.what} — ${parts.why}` : parts.what;
    out.push(`  ${core.CONTRACTS.gate_verdicts.failPrefix}${f.code}: ${head}`);
    for (const e of f.evidence || []) out.push(`      evidence: ${e}`);
    out.push(`      fix: ${f.fix}`);
  }
  return out.join('\n');
}

module.exports = { getSemanticPlanTasks, checkBidirectional, loadSemanticAllowlist, semanticAllowlisted, semanticBaselineShas, diffHitCheck, semanticDiffPhase, readExemptions, consumeExemptions, checkManifest, impactClosurePhase, semanticChecks, loadTrustStore, cmdGateTrust, cmdGate, cmdLogs, specCardFloorFailures, projectDecisionIds, stripSpecForScan, flipReconcileLeg, renderGateFailures };
