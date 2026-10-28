'use strict';

const core = require('../core/index.cjs');
const clcore = require('../ops/changelog-core.cjs'); // issue-close neutralization (R-01)
const nav = require('../nav/status.cjs');   // direct aspect require (dependency DAG)
const ops = require('../ops/gate.cjs');     // direct aspect require (dependency DAG)
const { SPEC_CARD_FLOORS, probeSpecFloor } = ops; // spec floor registry + shared probe (single source in the gate module)
const map = require('../map/index.cjs');
const knowledge = require('../knowledge/index.cjs');
const sibArchive = require('./archive.cjs');
const sibPlansnap = require('./plansnap.cjs');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

function semanticSkipEscapeActive(repoRoot) {
  if (process.env.GOS_SKIP_SEMANTIC !== '1') return false;
  const sb = process.env.GOS_TEST_SANDBOX;
  if (!sb || !path.isAbsolute(sb)) return false; // invalid binding → treated as production
  try {
    return fs.realpathSync(sb) === fs.realpathSync(repoRoot);
  } catch { return false; }
}

function runCommitSemanticChecks(state, stage) {
  const repoRoot = core.currentRootRealpath() || fs.realpathSync('.');
  // escape hatch — sandbox-bound only [B-10/R2-11]
  // REVIEW #4: the skip exempts ONLY the semantic engine call. State repairs (pending
 // auto-anchor) and the independent anti-tamper embeds ( spec hash, lessons
  // anchor) are NOT "semantic checks" — they run unconditionally.
  let skipSemantic = false;
  if (process.env.GOS_SKIP_SEMANTIC === '1') {
    if (!semanticSkipEscapeActive(repoRoot)) {
      console.error('✗ GOS_SKIP_SEMANTIC=1 refused: not sandbox-bound (GOS_TEST_SANDBOX missing/relative/mismatched)');
      console.error('  unset GOS_SKIP_SEMANTIC — semantic checks are unconditional in production.');
      console.error('  Parallel-wave rule: executors never `gos commit`; the main session single-point commits after wave aggregation.');
      process.exit(1);
    }
    console.log(`⚠ ${core.CONTRACTS.semantic_checks.skipBanner}`);
    state.semantic_skips = [...(state.semantic_skips || []), new Date().toISOString()]; // sole writer [R4-F7]
    skipSemantic = true;
  }
 // ③ pending auto-anchor: zero-commit at init, commits exist now → anchor to root commit
  if (state.task_head_pending) {
    let firstSha = null;
    try { firstSha = execFileSync('git', ['rev-list', '--max-parents=0', 'HEAD'], { encoding: 'utf8' }).trim().split('\n')[0]; } catch { /* still zero commits */ }
    if (firstSha) {
      state.task_head = firstSha;
      state.task_head_pending = false;
      (state.task_head_history = state.task_head_history || []).push({ sha: firstSha, at: new Date().toISOString(), what: 'pending-autoanchor' });
      console.log(`⚠ task_head auto-anchored to first commit ${firstSha.slice(0, 10)} (B-4 pending bootstrap)`);
    }
  }
 // F1 companion ( dogfood finding): pre-Phase-B task whose init predates has NO
  // task_head field — lazy-anchor to the most recent think-stage commit (BUILD diff scope
  // = THINK output onward; spec/plan sit under the .gos/** allowlist so only real code
  // work is diff-hit checked). The generator emits a fixed "advance think" phrase in the
  // subject; repos started before that convention keep the legacy `gos(think):` prefix —
  // both greps are ORed. Falls back to the root commit when no think-stage commit exists.
  if (state.task_head === undefined) {
    let anchorSha = null;
    try {
      // BRE note: a bare `(...)` is a literal in POSIX BRE (escaped `\(` would
      // be a group), so these patterns anchor the line-start prefixes verbatim.
      anchorSha = execFileSync('git', ['log', '--grep=^chore(gos): advance think', '--grep=^gos(think)', '--format=%H', '-1'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() || null;
    } catch { /* non-git */ }
    if (!anchorSha) {
      try { anchorSha = execFileSync('git', ['rev-list', '--max-parents=0', 'HEAD'], { encoding: 'utf8' }).trim().split('\n')[0]; } catch { /* no commits */ }
    }
    if (anchorSha) {
      state.task_head = anchorSha;
      (state.task_head_history = state.task_head_history || []).push({ sha: anchorSha, at: new Date().toISOString(), what: 'lazy-anchor' });
      console.log(`⚠ task_head lazy-anchored to ${anchorSha.slice(0, 10)} (pre-Phase-B task, F1)`);
    }
  }
 // spec_sha256 consistency (freeze exists → must match current spec.md)
  if (state.spec_sha256) {
    const sp = core.specPathOf(state);
    if (fs.existsSync(sp)) {
      const cur = core.sha256FileSync(sp);
      if (cur !== state.spec_sha256) {
        console.error(`✗ spec.md hash ≠ frozen spec_sha256 (B-22) — spec changed after THINK commit.`);
        console.error('  Legitimate change: update spec, re-run `gos commit think` (re-freezes), then retry.');
        process.exit(1);
      }
    }
  }
  // B-8 anti `git add .gos/` whitewash [R1-F3]: lessons json-truth integrity —
  // same implementation as gate lessons + lessons family (single source).
  // The git out-of-band channel inside it compares HEAD vs working json, so a
  // hand-deleted entry with no disposal audit row blocks THIS commit.
  if (fs.existsSync(core.lessonsPaths('project').truth)) {
    const lres = knowledge.loadStore(core.lessonsPaths('project'));
    if (lres.failures.length) {
      for (const f of lres.failures) {
        if (typeof f === 'string') { console.error(`✗ commit blocked: ${f}`); continue; }
        console.error(`✗ commit blocked: ${f.code}: ${f.verdict}`);
        for (const e of f.evidence || []) console.error(`    evidence: ${e}`);
        console.error(`    fix: ${f.fix}`);
      }
      process.exit(1);
    }
  }
 // the semantic engine itself — same function as gate semantic ( , non-copy)
  if (!skipSemantic) {
    const res = ops.semanticChecks({ state });
    if (res.failures.length) {
      console.error(`${core.CONTRACTS.state_semantics.commitBlocked} (semantic layer, ${stage} commit):`);
      console.error(ops.renderGateFailures(res.failures));
      process.exit(1);
    }
  }
}

// CJK detection for the commit-subject language guard: hangul jamo &
// syllables, kana, CJK punctuation/radicals/unified (+Ext-A)/compatibility
// ideographs, fullwidth forms.
const CJK_SUBJECT_RE = /[\u1100-\u11ff\u3000-\u30ff\u3130-\u318f\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af\uf900-\ufaff\uff00-\uffef]/;

// Spec floor stamping: the stamp records the content's era, not the CLI's era.
// The registry, its floors and the probe live in the gate module (single
// source); this side only decides WHEN to probe (first freeze, stamp-absent
// state) and when to dispatch the stamped floor (re-freeze never upgrades).
function renderSpecFloorBlock(failures) {
  for (const f of failures) {
    console.error(`✗ commit blocked: ${f.code}: ${f.verdict}`);
    for (const e of f.evidence || []) console.error(`    evidence: ${e}`);
    console.error(`    fix: ${f.fix}`);
  }
}

// Probe-stamp the content era. blockOnNone=true (first freeze of new
// content): passing no floor at all blocks the commit — a spec authored
// under this CLI must clear the base floor. blockOnNone=false (re-freeze
// and legacy stamp-backfill): pre-floor-era content keeps the stamp absent
// and proceeds grandfathered.
function stampSpecByProbe(state, specText, { blockOnNone = true } = {}) {
  const decisions = state.decisions || [];
  const projectIds = ops.projectDecisionIds();
  const probed = probeSpecFloor(specText, decisions, projectIds);
  if (probed.stamp === null) {
    if (blockOnNone) {
      renderSpecFloorBlock(probed.failures);
      process.exit(1);
    }
    console.log('⚠ spec gate: no floor passes — pre-floor-era content, stamp left absent (card floors grandfathered)');
    return;
  }
  state.spec_gate_version = probed.stamp;
  const aboveFloor = SPEC_CARD_FLOORS[probed.stamp + 1];
  if (aboveFloor) {
    const above = aboveFloor(specText, decisions, projectIds).length;
    console.log(`✓ spec gate: stamped floor v${probed.stamp} (${above} table(s) fail the v${probed.stamp + 1} Activates floor)`);
  } else {
    console.log(`✓ spec gate: stamped floor v${probed.stamp}`);
  }
}

function enforceStampedSpecFloor(state, specText) {
  const stamp = state.spec_gate_version;
  const floor = SPEC_CARD_FLOORS[stamp];
  if (!floor) {
    renderSpecFloorBlock([core.gateFail('spec-gate-version-unknown', {
      verdict: `spec_gate_version=${JSON.stringify(stamp)} is outside the floor domain this CLI knows`,
      evidence: [`.gos/state.json: spec_gate_version=${JSON.stringify(stamp)}`],
      fix: 'upgrade the CLI (or return to the branch that froze this spec) until the stamp is known — escape, user-approved only: rerun with GOS_SPEC_GATE_FLOOR_OVERRIDE=1',
    })]);
    process.exit(1);
  }
  const failures = floor(specText, state.decisions || [], ops.projectDecisionIds());
  if (failures.length) {
    renderSpecFloorBlock(failures);
    process.exit(1);
  }
  console.log(`✓ spec gate: floor v${stamp} holds (stamp kept)`);
}

function cmdCommit(argv) {
  // --subject "<text>": explicit commit subject (English escape hatch when the
  // intent summary cannot serve as one). Consumed BEFORE <stage> parsing so
  // the subject value is never mistaken for the stage argument.
  const args = [...argv];
  let explicitSubject = null;
  const subjIdx = args.indexOf('--subject');
  if (subjIdx !== -1) {
    explicitSubject = args[subjIdx + 1];
    if (!explicitSubject || explicitSubject.startsWith('--')) core.die('Usage: gos commit <stage> [--subject "<english subject>"] [--force] [--refreeze]');
    args.splice(subjIdx, 2);
  }
  const state = core.readState();
  if (!state) core.die(core.CONTRACTS.state_semantics.noActiveTask);
 // flag-aware stage parsing (`gos commit plan --force` — monotonic override)
  const forceFlag = args.includes('--force');
  const refreezeFlag = args.includes('--refreeze');
  const stageArg = args.find((a) => !a.startsWith('--'));
  const stage = (stageArg || state.current_stage || '').toUpperCase();
  if (!stage || nav.stageIndex(stage) === -1) core.die('Usage: gos commit <stage> [--force] [--refreeze]  (e.g. gos commit think --refreeze)');
  if (refreezeFlag && stage !== 'THINK') core.die('gos commit --refreeze is only legal with the think stage — it re-freezes the spec without advancing the stage');

  if (refreezeFlag) {
    // Pure state operation: recompute the sha, keep the stamp (absent stamp
    // probes like a first freeze), no stage advance, no git commit.
    const sp = core.specPathOf(state);
    if (!fs.existsSync(sp)) core.die(`spec file not found: ${sp} (nothing to re-freeze)`);
    const specText = fs.readFileSync(sp, 'utf8');
    if (state.spec_gate_version !== undefined) enforceStampedSpecFloor(state, specText);
    else stampSpecByProbe(state, specText, { blockOnNone: false });
    state.spec_sha256 = core.sha256FileSync(sp);
    core.writeState(state);
    console.log(`✓ spec re-frozen: spec_sha256 recomputed (stage ${state.current_stage} unchanged, no commit written)`);
    return;
  }

  // ---- commit generator guards: hard checks run BEFORE any state mutation
  // reaches disk (archive moves, freeze fields, writeState) so a rejected
  // commit leaves the task exactly where it stood ----
  const hasGit = (() => { try { execFileSync('git', ['rev-parse', '--is-inside-work-tree'], { stdio: 'pipe' }); return true; } catch { return false; } })();
  let commitSubject = null;
  let allowEmptyAdvance = false;
  if (hasGit) {
    // Empty-commit guard: nothing staged AND a clean worktree means the stage
    // produced no recordable change (duplicate run or files missed by the
    // add-list). A hollow commit would desync git history from task state.
    let stagedEmpty = true;
    try { execFileSync('git', ['diff', '--cached', '--quiet'], { stdio: 'pipe' }); } catch { stagedEmpty = false; }
    let porcelain = '';
    try { porcelain = execFileSync('git', ['status', '--porcelain'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }); } catch { /* keep empty */ }
    // `.gos/.lock` is the CLI's own runtime concurrency lock (created with the
    // process, unlinked on exit, machine-local and gitignored in real repos).
    // It must not count as stage output — otherwise the guard can never fire
    // in sandboxes without a covering .gitignore.
    const realDirt = porcelain.split('\n').filter((l) => l.trim() && l.slice(3) !== '.gos/.lock');
    if (stagedEmpty && realDirt.length === 0) {
      // Stage-advance exemption: the FIRST advance commit for the current
      // stage is legitimate even with an empty tree (all wave work already
      // committed; state.json is gitignored, so nothing recordable remains).
      // Duplicate runs are still blocked: once the stage advanced, the stage
      // gate rejects the re-run before this exemption can apply again.
      const advancing = String(state.current_stage || '').toUpperCase() === stage;
      if (!advancing) {
        console.error('✗ no changes to commit (duplicate run or files missed) — stage produced nothing recordable');
        process.exit(1);
      }
      allowEmptyAdvance = true;
    }
    // Subject language guard: commit messages are English; a CJK intent
    // summary must be overridden explicitly via --subject.
    const subjectBase = explicitSubject != null
      ? explicitSubject
      : String((state.intent && state.intent.summary) || '').split('\n')[0];
    commitSubject = core.sanitizeEcho(subjectBase);
    if (explicitSubject == null && CJK_SUBJECT_RE.test(commitSubject)) {
      console.error(`✗ generated commit subject contains CJK ("${commitSubject}") — commit messages must be English`);
      console.error('  escape hatch: gos commit <stage> --subject "<english subject>"');
      process.exit(1);
    }
    // Header budget: `chore(task): advance <stage> — <subject>` must stay within
    // the commitlint 72-char cap; trailing full stops are also rejected by the
    // subject-full-stop rule, so strip them before slicing to the budget.
    commitSubject = commitSubject.replace(/\.+$/, '').slice(0, Math.max(20, 72 - `chore(task): advance ${stage.toLowerCase()} — `.length));
  }
  // Transactional snapshot: byte-exact state.json to restore if the git
  // commit fails below, so a failed commit never advances the task state.
  const stateSnapshot = (hasGit && fs.existsSync(core.STATE_PATH)) ? fs.readFileSync(core.STATE_PATH) : null;

  // Stage monotonicity: re-running the current stage (idempotent re-commit)
  // and committing the next stage stay legal; a stage behind the current one
  // in the task's level flow would write an advance-labeled commit for a
  // point the work history already passed. Stages outside the level flow
  // (the level-dependent stage sets) are not this task's stages — legacy
  // semantics keep applying to them.
  {
    const flow = nav.levelFlow(state.level ?? 0);
    const curIdx = flow.indexOf(String(state.current_stage || '').toUpperCase());
    const reqIdx = flow.indexOf(stage);
    if (curIdx !== -1 && reqIdx !== -1 && reqIdx < curIdx) {
      const parts = core.t('commit.stage-regression-blocked', { stage, current: String(state.current_stage || '') });
      const failure = core.gateFail('stage-regression-blocked', {
        verdict: parts.what,
        evidence: [`re-commit of stage ${stage} is only legal while current_stage=${stage} (now: current_stage=${state.current_stage})`],
        fix: parts.fix,
      });
      console.error(`${core.CONTRACTS.state_semantics.commitBlocked} (stage monotonicity):`);
      console.error(`✗ ${failure.code}: ${failure.verdict}`);
      console.error(`    why: ${parts.why}`);
      for (const e of failure.evidence) console.error(`    evidence: ${e}`);
      console.error(`    fix: ${failure.fix}`);
      process.exit(1);
    }
  }

 // ---- : filesystem fallback (artifact must EXIST — model's word is not evidence)
  const lv = state.level ?? 0;
  const failures = [];
 // trigger alignment: the frozen orphan-advisory text promises
  // `gos commit ship` (project) / `gos commit verify` (non-project) adopt orphans —
  if (stage === 'THINK' && lv >= 2) {
    const sp = core.specPathOf(state);
    if (!fs.existsSync(sp)) failures.push(`spec file not found: ${sp} (THINK produces spec.md)`);
    if (!(state.approvals || {}).THINK) failures.push('user approval missing for THINK (core.ask the user, then `gos approve think`)');
    // Red Team disposition completeness (Lv2+): findings without dispositions = unprocessed attack
    const rounds = state.redteam_rounds || [];
    if (lv >= 2 && rounds.length) {
      // Disposition completeness with supersede awareness:
      // a later FULL disposition round (has dispositions) supersedes earlier
      // undispensed rounds (e.g. protocol adopted mid-task; historical rounds
      // covered by a wholesale disposition pass). Only rounds that are BOTH
      // findings>0, undispensed, AND not superseded block the gate.
      const dispRoundNums = rounds.filter(r => r.dispositions).map(r => r.round);
      const noDisp = rounds.filter(r =>
        (r.findings || 0) > 0 && !r.dispositions && !r.superseded_by
      );
      if (noDisp.length) {
        const supersededInfo = dispRoundNums.length ? ` (disposition rounds present: ${dispRoundNums.join(', ')} — mark old rounds with "superseded_by": <round> if covered)` : '';
        failures.push(`red-team rounds with findings but NO dispositions: rounds ${noDisp.map(r => r.round).join(', ')}${supersededInfo} (every finding needs ACCEPT/PARTIAL/REJECT-with-facts/DEFER — see red-team.md)`);
      }
    }
  }
  if (stage === 'PLAN' && lv >= 3) {
    const pp = core.planPathOf(state);
    if (!fs.existsSync(pp)) failures.push(`plan file not found: ${pp} (PLAN produces plan.md)`);
    if (!(state.approvals || {}).PLAN) failures.push('user approval missing for PLAN (core.ask the user, then `gos approve plan`)');
  }
  if (stage === 'VERIFY') {
    // T2 [R4-F13]: object-form evidence validation — the old `evidence.length < 5`
 // string check is dead code under the object schema (removed).
    const badEv = [];
    for (const t of state.observable_truths) {
      if (!t.verified) continue;
      const err = core.validateEvidenceObject(t.evidence, process.cwd());
      if (err) badEv.push(`${t.id}: ${err}`);
    }
    if (badEv.length) failures.push(`truths verified with invalid evidence: ${badEv.join('; ')}`);
  }
  if (failures.length) {
    console.error(`${core.CONTRACTS.state_semantics.commitBlocked} (filesystem fallback — claimed work not found on disk):`);
    for (const f of failures) console.error(`  ✗ ${f}`);
    process.exit(1);
  }

  // ---- T2 [B-15/B-22/F1]: freeze-field lifecycle (all BEFORE the git commit, so a
  // freeze failure never leaves a git commit without its state side) ----
 // trigger alignment: the frozen orphan-advisory text promises
  // `gos commit ship` (project) / `gos commit verify` (non-project) adopt orphans —
  // wire cmdArchive here so the promise is code, not copy. Idempotent: archive exits 0
  // on "already archived" when the stage rolled past.
  if ((stage === 'SHIP' && lv >= 3) || (stage === 'VERIFY' && lv < 3)) {
    try { sibArchive.cmdArchive({ fromCommit: true }); } catch (e) { console.error(`⚠ post-commit archive skipped: ${e.message || e}`); }   // fromCommit=true: archive inside the commit chain runs with degraded ritual gates and never takes the git commit authority away from this commit
  }
  if (stage === 'THINK' && lv >= 2) {
    const sp = core.specPathOf(state);
    if (fs.existsSync(sp)) {
      // spec card floor: born here (objects, F11) — a spec that freezes
      // under this CLI must carry option cards for every decision it records.
      // First freeze probes the registry and stamps the highest floor the
      // content passes; a re-freeze dispatches the stamped floor and never
      // upgrades the stamp.
      const specText = fs.readFileSync(sp, 'utf8');
      if (state.spec_gate_version !== undefined) enforceStampedSpecFloor(state, specText);
      else stampSpecByProbe(state, specText);
      state.spec_sha256 = core.sha256FileSync(sp); // B-22 freeze at THINK commit
    }
  }
  if (stage === 'PLAN' && lv >= 3) {
    state.plan_snapshot = sibPlansnap.freezeOrRefreshPlanSnapshot(state, { force: forceFlag }); // B-15
  }
  if (stage === 'BUILD' && !state.plan_snapshot) {
    // F1 lazy-freeze: pre-Phase-B task reaches BUILD without a snapshot → freeze from the
    // current plan.md parse + banner + audit row, then proceed (dogfood path for this task)
    const parsed = sibPlansnap.parsePlanMd();
    if (parsed && parsed.length) {
      state.plan_snapshot = { tasks: sibPlansnap.buildPlanSnapshotTasks(parsed), audit: [{ at: new Date().toISOString(), what: 'lazy-freeze' }] };
      sibPlansnap.pushLazyFreezeLedger(state, 'lazy-freeze:plan');
      console.log(`⚠ ${core.CONTRACTS.semantic_checks.lazyFreeze}`);
    }
  }
  if ((stage === 'REVIEW' || stage === 'VERIFY') && !state.spec_sha256) {
    // F1 lazy-freeze: missing spec hash at REVIEW/VERIFY → freeze from current spec.md
    const sp = core.specPathOf(state);
    if (fs.existsSync(sp)) {
      state.spec_sha256 = core.sha256FileSync(sp);
      sibPlansnap.pushLazyFreezeLedger(state, 'lazy-freeze:spec');
      console.log(`⚠ ${core.CONTRACTS.semantic_checks.lazyFreeze}`);
    }
  }

  // ---- Phase B (T7) [D-33/B-10]: BUILD/VERIFY commit embeds the semantic layer ----
  if ((stage === 'BUILD' || stage === 'VERIFY')) {
    runCommitSemanticChecks(state, stage);
  }

  // Stamp-absent states that already carry a frozen sha (pre-stamp freezes
  // and the lazy-freeze above): probe-stamp through the shared registry at
  // the next commit of any kind. The frozen sha itself is untouched;
  // pre-floor-era content stays stamp-absent and grandfathered.
  if (state.spec_sha256 && state.spec_gate_version === undefined) {
    const sp = core.specPathOf(state);
    if (fs.existsSync(sp)) stampSpecByProbe(state, fs.readFileSync(sp, 'utf8'), { blockOnNone: false });
  }

  if (!hasGit) { console.log('(not a git repo — skipping commit, stage still advanced)'); }
  else {
    const dList = state.decisions.map(d => d.id).join(', ') || 'none';
    const rList = state.requirements.map(r => r.id).join(', ') || 'none';
 // choke point: the whole message (subject + body) passes through the
    // shared neutralizer so a close/fix keyword before `#N` never ships in a
    // gos commit (GitHub would close the issue on push).
    const msg = clcore.neutralizeIssueTriggers(`chore(task): advance ${stage.toLowerCase()} — ${commitSubject}\n\nDecisions: ${dList}\nRequirements: ${rList}\nLevel: Lv${state.level ?? '?'}`);
    try {
      // Tolerant add: each path may be missing or gitignored — never fail the whole chain.
      // Phase C (R-fix): add-list was hardcoded to 5 dirs — bin/, .opencode/ and root
      // files silently missed, producing hollow commits (BUILD shipped 0 files for a
      // 26-file diff). Explicit top-level paths (NOT `add -A` — [08-21] parallel-wave
      // lesson forbids blind staging of in-flight files).
 // [Phase D ] commit-time semantic closure report (code-enforced pre-run routing):
      // the must-check/must-run list rides along every stage commit — no skill discipline needed.
      try {
        const changed = execFileSync('git', ['-c', 'core.quotepath=off', 'diff', 'HEAD', '--name-only', '--diff-filter=d', '-z'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 32 * 1024 * 1024 })
          .split('\0').map((l) => l.trim()).filter(Boolean);
 // [Phase W ] print UNCONDITIONALLY — empty-diff silence was previously masked
        // by tracked-but-uncommitted edges.json (E8 lesson regression: silence ≠ checked)
        map.printSemanticClosure(core.mapRootDir(), changed);   // [R2-C1 fix] root was .gos dir — freeze/embed were no-ops
      } catch { /* non-git or unborn — skip */ }
 // [Phase D ] consume exemptions at commit (auto-expiry)
      try { ops.consumeExemptions(core.mapRootDir()); } catch { /* non-git — skip */ }   // [R2-C1 fix]
 // [Phase D ] freeze edges.json integrity anchor into the SAME commit (tracked lock)
      try { if (map.freezeEdgesLock(core.mapRootDir())) console.log('✓ edges.lock frozen into this commit'); } catch { /* no edges.json — skip */ }   // [R2-C1 fix]
      const ADD_PATHS = ['.gos/', 'docs/', 'skills/', 'src/', 'test/', 'bin/', '.opencode/',
        'commands/', 'templates/', '.claude-plugin/', '.codex/', 'package.json', 'AGENTS.md',
        'README.md', 'README.zh-CN.md', 'CONTRIBUTING.md', 'LICENSE', '.gitattributes', '.gitignore',
        '.github/', 'CHANGELOG.md', '.changes.md', 'hooks/', 'scripts/', 'commitlint.config.yaml',
        'census.json'];
      for (const p of ADD_PATHS) { try { execFileSync('git', ['add', p], { stdio: 'pipe' }); } catch { /* tolerant */ } }
      execFileSync('git', ['commit', ...(allowEmptyAdvance ? ['--allow-empty'] : []), '-m', msg], { stdio: 'pipe' });
      const sha = execFileSync('git', ['rev-parse', '--short', 'HEAD'], { stdio: 'pipe' }).toString().trim();
      console.log(`${core.CONTRACTS.state_semantics.committed} ${stage}: ${sha}`);
    } catch (e) {
      console.error(`✗ git commit failed: ${String(e.message).split('\n')[0]}`);
      if (stateSnapshot != null) {
        try { fs.writeFileSync(core.STATE_PATH, stateSnapshot); } catch { /* best-effort restore */ }
        console.error('  state write rolled back — stage not advanced');
      }
      // A failed commit may leave the index staged (ADD_PATHS sweep or archive
      // renames): unstage so a retry starts from a clean, truthful index.
      try { execFileSync('git', ['reset', '-q'], { stdio: 'pipe' }); } catch { /* nothing staged */ }
      process.exit(1);
    }
  }
 // ---- : auto-checkpoint on build commit (code-timed, not model-discipline)
  if (stage === 'BUILD') {
    const tasks = sibPlansnap.parsePlanMd();
    if (tasks && tasks.length) {
      state.checkpoints = state.checkpoints || [];
      const totalWaves = Math.max(...tasks.map(t => t.wave || 1));
      state.checkpoints.push({ stage: 'BUILD', unit: `all-waves (auto at commit)`, done: tasks.map(t => t.id).join(','), remaining: '', at: new Date().toISOString() });
    }
  }
  // advance stage
  if (!state.completed_stages.includes(stage)) state.completed_stages.push(stage);
  const nxt = nav.nextStage(state);
  state.current_stage = nxt;
  core.writeState(state);
  console.log(`${core.CONTRACTS.state_semantics.stageAdvanced}: ${stage} → ${nxt}`);
  console.log(`Next:\n${nav.nextHint(state)}`);
}

module.exports = { semanticSkipEscapeActive, runCommitSemanticChecks, cmdCommit };
