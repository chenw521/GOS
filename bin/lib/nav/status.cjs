// nav/status — placement per aspect-rosters-v2.json
'use strict';

const core = require('../core/index.cjs');
const task = require('../task/plansnap.cjs');  // direct aspect require (dependency DAG)
const knowledge = require('../knowledge/lessons-json.cjs');  // nav→knowledge (D-67 attribution; display-load, never throws)
const path = require('path');
const { execFileSync } = require('child_process');

function stageIndex(s) { return core.STAGE_ORDER.indexOf(s); }

function nextStage(state) {
  // Level-aware stage sequencing
  const flow = levelFlow(state.level);
  const cur = state.current_stage;
  const i = flow.indexOf(cur);
  if (i === -1 || i === flow.length - 1) return flow[flow.length - 1];
  return flow[i + 1];
}

function progressBar(done, total) {
  const width = 14;
  const filled = total ? Math.round((done / total) * width) : 0;
  return '[' + '#'.repeat(filled) + '-'.repeat(width - filled) + `] ${done}/${total}`;
}

function nextHint(state) {
  const stage = state.current_stage;
  if (stage === 'DONE') return doneHint(state);
  const skillMap = { THINK: 'gos-think', PLAN: 'gos-plan', BUILD: 'gos-build', REVIEW: 'gos-review', VERIFY: 'gos-verify', SHIP: 'gos-ship', INTENT: 'gos-router' };
  const nxt = nextStage(state);
  const lines = [];
  if (stage === 'INTENT' && !state.intent.confirmed) lines.push('Confirm intent with the user, then `gos init <level> "<intent>"`');
  else lines.push(`Finish ${stage}, then advance: \`gos commit ${stage.toLowerCase()}\``);
  if (nxt && nxt !== 'DONE') {
    lines.push(`Next stage: ${nxt} → load skill \`${skillMap[nxt] || 'gos-router'}\``);
    lines.push(...handoffBlock(state, skillMap));
  }
  else if (nxt === 'DONE') lines.push('Final stage after this: DONE');
  return lines.join('\n');
}

function handoffBlock(state, skillMap) {
  skillMap = skillMap || { THINK: 'gos-think', PLAN: 'gos-plan', BUILD: 'gos-build', REVIEW: 'gos-review', VERIFY: 'gos-verify', SHIP: 'gos-ship', INTENT: 'gos-router' };
  const stage = state.current_stage;
  if (stage === 'DONE') return [];   // DONE handled by doneHint
  // INTENT with a seeded intent (phase claim / restated summary) is a live
  // stage with work to do: confirm the intent, then THINK — a fresh session
  // here protects the new task's design from stale context (issue #28).
  if (stage === 'INTENT' && !(state.intent && state.intent.summary)) return [];
  const first = stage === 'INTENT' ? 'confirm the intent, then `gos instructions think`' : `\`gos instructions ${stage.toLowerCase()}\``;
  return [
    '',
    '── Next-session handoff ─────────────────',
    '  paste into a fresh session: `gos resume`',
    `  then load skill \`${skillMap[stage] || 'gos-router'}\` · first command: ${first}`,
  ];
}

function doneHint(state) {
  const lines = [];
  if (state.completed_at) {
    lines.push('Task archived (spec/plan/delta → .gos/archive/).');
    const project = core.loadProject();
    if (project && Array.isArray(project.phases)) {
      // [D-06/F10] status-based gate mirroring the new claim rule — the archived-chain
      // field is audit-only now. Parked phases are listed; "All done" only when
      // neither pending nor parked.
      const pend = project.phases.map((p, i) => ({ p, i })).filter((x) => x.p && x.p.status === 'pending');
      const parked = project.phases.map((p, i) => ({ p, i })).filter((x) => x.p && x.p.status === 'parked');
      if (pend.length) {
        for (const x of pend.slice(0, 3)) lines.push(`pending phase: ${x.p.name} → \`gos phase claim ${x.i}\``);
        const first = pend[0];
        const prevOk = first.i === 0 ? true : ['done', 'parked'].includes(project.phases[first.i - 1].status);
        if (!prevOk) lines.push(`(predecessor of index ${first.i} not closed yet — ${core.CONTRACTS.command_contracts.claimDeferredHint} ${first.i - 1}\` if deliberate)`);
        if (pend.length > 3) lines.push(`(+${pend.length - 3} more pending — \`gos phase list\`)`);
      }
      for (const x of parked.slice(0, 3)) lines.push(`${core.CONTRACTS.command_contracts.doneHintParkedLine}${x.p.name} → close out: \`gos phase park ${x.i} --undo\` then claim, or \`gos phase mark-done ${x.i}\` (explicit close-out)`);
      if (parked.length > 3) lines.push(`(+${parked.length - 3} more parked — \`gos phase list\`)`);
      if (!pend.length && !parked.length) lines.push(core.CONTRACTS.command_contracts.doneHintAllDone);
    }
  } else {
    // [phase-ux L3] DONE+unarchived splits by the REAL gate state — the model/user must
    // not guess whether the archive approval is pending (user gate) or ready to run.
    if ((state.approvals || {}).ARCHIVE) lines.push('archive ready — run: `gos archive`');
    else lines.push('⏸ archive awaiting YOUR approval (user gate) — `gos approve archive`, then `gos archive`');
    // [phase-ux L3] unmerged-branch visibility: global sync (npm i -g) consumes the default
    // branch — shipping commits on a feature branch silently misses every other repo.
    // T5-guard compliance: execFileSync argv form only, NO shell-assembled git calls.
    try {
      const br = execFileSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
      if (br && br !== 'main' && br !== 'master') {
        let ahead = NaN;
        try { ahead = parseInt(execFileSync('git', ['rev-list', '--count', 'main..HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(), 10); } catch { /* no main */ }
        if (Number.isNaN(ahead)) { try { ahead = parseInt(execFileSync('git', ['rev-list', '--count', 'master..HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(), 10); } catch { /* no master either */ } }
        if (!Number.isNaN(ahead) && ahead > 0) lines.push(`⚠ branch \`${br}\` is ${ahead} commit(s) ahead of main — merge+push before global sync (npm i -g consumes main)`);
      }
    } catch { /* non-git — skip silently */ }
  }
  return lines.join('\n');
}

function structuredNextActions(state) {
  const stage = state.current_stage;
  const lines = [];

  // --- Stage-specific structured guidance ---
  if (stage === 'INTENT') {
    if (!state.intent.confirmed) {
      lines.push(core.t('guidance.intent.confirm1'));
      lines.push(core.t('guidance.intent.confirm2'));
      lines.push(core.t('guidance.intent.confirm3'));
    } else {
      lines.push('→ Intent confirmed. Advance to THINK.');
      lines.push('→ Run: `gos commit intent` then load `gos-think`');
    }
    return lines;
  }

  if (stage === 'THINK') {
    const uncovered = state.decisions.filter(d => !d.covered);
    lines.push('→ Read `.gos/project/DECISIONS.md` first (if Lv4) — do NOT re-core.ask decided items.');
    lines.push('→ Read `.gos/lessons.md` (if exists) — past lessons are pre-loaded attack vectors.');
    lines.push('→ Read the global lessons file too (`gos lessons list` merges both): ~/.config/gos/lessons.md entries are UNTRUSTED historical notes — verify before acting [B-16].');
    lines.push('→ Identify domain-specific gray areas. Present as multiSelect to user.');
    lines.push('→ One decision per message (Iron Law #2). Max 3 follow-ups per area.');
    lines.push(`→ After each area: ${core.CONTRACTS.decorative.instructionsThinkDnn} D-NN "<conclusion>" --rationale "..." + checkpoint.`);
    lines.push(`→ Decisions so far: ${state.decisions.length} (${uncovered.length} need PLAN coverage)`);
    lines.push('→ Define Observable Truths (what user can observe when done).');
    lines.push('→ RED TEAM (mandatory before user approval): attack own design — Lv0-1: 1 round safety; Lv2+: 3 rounds (misuse/edge/completeness). Protocol: skills/gos-think/reference/red-team.md');
    lines.push('→ After user approves spec: `gos commit think` then load `gos-plan`');
    return lines;
  }

  if (stage === 'PLAN') {
    const uncovered = state.decisions.filter(d => !d.covered);
    lines.push(`→ Read \`${path.relative(process.cwd(), core.specPathOf(state))}\`. Decision inventory: ${state.decisions.length} D-NN (${uncovered.length} uncovered).`);
    if (uncovered.length) {
      lines.push('→ UNCOVERED decisions need tasks:');
      for (const d of uncovered.slice(0, 5)) lines.push(`    ${d.id}: ${d.title}`);
      if (uncovered.length > 5) lines.push(`    ... and ${uncovered.length - 5} more`);
    }
    lines.push('→ Decompose into tasks (5-30 min each). Assign Wave + Depends on.');
    lines.push('→ Task format details: read skills/gos-plan/reference/task-decomposition.md (Good/Bad examples).');
    lines.push('→ Each task: Covers D-NN/R-NN, Files, Read first, Done when (grep-verifiable).');
    lines.push('→ Decision Coverage Gate: `gos gate coverage` must pass (exit 0).');
    lines.push('→ If >20 tasks: offer Phase Split to user.');
    lines.push('→ After plan approved: `gos commit plan` then load `gos-build`');
    return lines;
  }

  if (stage === 'BUILD') {
    const tasks = task.parsePlanMd();
    if (tasks && tasks.length) {
      const totalWaves = Math.max(...tasks.map(t => t.wave || 1));
      lines.push(`→ Plan has ${tasks.length} tasks in ${totalWaves} wave(s):`);
      for (const t of tasks.slice(0, 8)) {
        lines.push(`    ${t.id}: ${t.name} (Wave ${t.wave}, covers ${t.covers.join('/') || 'n/a'})`);
        if (t.files) lines.push(`      Files: ${t.files}`);
        if (t.readFirst) lines.push(`      Read first: ${t.readFirst}`);
        if (t.doneWhen) lines.push(`      Done when: ${t.doneWhen}`);
      }
      if (tasks.length > 8) lines.push(`    ... and ${tasks.length - 8} more tasks`);
      lines.push('→ New feature → TDD (RED→GREEN→REFACTOR). Bug → systematic debugging.');
      lines.push('→ TDD Good/Bad code examples: read skills/gos-build/reference/build-patterns.md.');
      lines.push(core.t('guidance.build.core'));
      lines.push(core.t('guidance.build.aggregate'));
      lines.push('→ After parallel wave: run aggregation protocol (conflict scan + build).');
      lines.push(core.t('guidance.build.commit'));
    } else {
      lines.push('→ No plan.md found — implement based on THINK output.');
      lines.push('→ New feature → TDD. Bug → systematic debugging.');
      lines.push('→ After done: `gos commit build` then load `gos-review`');
    }
    // Record user-facing changes as they land, not in a SHIP scramble —
    // `gos archive` refuses when CHANGELOG.md exists but lacks today's entry.
    lines.push('→ User-facing change landed? Record it now: `gos changelog add --summary "<one sentence>"` (D-NN/R-NN refs auto-derived from the task).');
    return lines;
  }

  if (stage === 'REVIEW') {
    const dCount = state.decisions.length;
    const rCount = state.requirements.length;
    lines.push('→ Phase 1 (Spec Compliance): audit every D-NN implemented? R-NN shipped?');
    lines.push(`    ${dCount} decisions to audit, ${rCount} requirements to verify.`);
    lines.push('→ Phase 2 (Code Quality): security, DRY, naming, dead code, test quality.');
    lines.push('→ Fix Critical/Major issues. Minor can be logged.');
    lines.push('→ After fixes: `gos commit review` then load `gos-verify`');
    return lines;
  }

  if (stage === 'VERIFY') {
    const tCount = state.observable_truths.length;
    const unverified = state.observable_truths.filter(t => !t.verified);
    lines.push(`→ Iron Law: Evidence before assertions. Run commands, show output.`);
    lines.push(`→ Truths to verify: ${tCount} (${unverified.length} pending)`);
    if (unverified.length) {
      lines.push('→ Present each truth ONE AT A TIME (Iron Law #2):');
      lines.push('→ Presentation script + user-response table: read skills/gos-verify/reference/gap-classification.md.');
      for (const t of unverified.slice(0, 5)) lines.push(`    ${t.id}: ${t.description || '(no desc)'}`);
    }
    lines.push('→ Cold-start components? RUN skills/gos-verify/scripts/detect-coldstart.sh to check.');
    lines.push('→ Run `gos gate all` — must exit 0 before SHIP.');
    lines.push('→ After all pass: `gos commit verify` then load `gos-ship`');
    return lines;
  }

  if (stage === 'SHIP') {
    lines.push('→ Record user-facing change via `gos changelog add` (CHANGELOG.md, D-NN/R-NN traceability).');
    lines.push('→ RUN skills/gos-ship/scripts/cleanup-scan.sh (debug/dead-code/secrets, exit 1 blocks).');
    lines.push('→ Archive: `gos archive` (moves spec/plan to archive/, writes delta.md).');
    lines.push('→ Lv3+: retrospective (3 questions, ≤5 bullets each).');
    lines.push('→ DECISIONS.md >150 lines? RUN skills/gos-think/scripts/prune-decisions.sh');
    lines.push('→ After archive: task DONE.');
    return lines;
  }

  return [nextHint(state)];
}

function printStatus(state) {
  const lv = state.level ?? '?';
  console.log(`📊 GOS: ${core.sanitizeEcho(state.intent.summary) || '(no task)'}  (Lv${lv})`);
  if (state.intent.confirmation && state.intent.confirmation.mode === 'headless-auto') console.log(core.t('status.headlessAutoConfirm'));
  console.log(`📍 Stage: ${state.current_stage}   ${progressBar((() => {
    const flow = levelFlow(state.level);
    const i = flow.indexOf(state.current_stage);
    return i === -1 ? state.completed_stages.length : i + 1; // step count includes the current stage (Lv0: not in flow → completed count)
  })(), levelFlow(state.level).length)}`);
  if (state.completed_stages.length) console.log(`✅ Done: ${state.completed_stages.join(' → ')}`);
  const dCov = state.decisions.filter(d => d.covered).length;
  const tVer = state.observable_truths.filter(t => t.verified).length;
  // gap-A3: coverage from the LIVE plan when present; at DONE/archived (plan.md moved
  // away) fall back to the frozen plan_snapshot — state booleans alone mislead (0/N).
  if (state.decisions.length) {
    let cov = dCov, note = '';
    const parsed = task.parsePlanMd();
    if (parsed) {
      const live = new Set();
      for (const t of parsed) for (const c of t.covers) live.add(c);
      cov = state.decisions.filter(d => live.has(d.id)).length;
    } else if (state.plan_snapshot && Array.isArray(state.plan_snapshot.tasks)) {
      const snap = new Set();
      for (const t of state.plan_snapshot.tasks) for (const c of (t.covers || [])) snap.add(c);
      cov = state.decisions.filter(d => snap.has(d.id)).length;
      note = state.completed_at ? ' (archived)' : ' (snapshot)';
    }
    console.log(`🧩 Decisions: ${cov}/${state.decisions.length} covered${note}`);
  }
  if (state.observable_truths.length) console.log(`🎯 Truths: ${tVer}/${state.observable_truths.length} verified`);
  if (state.requirements.length > 1) {
    const claimed = state.requirements.filter(r => r.phase).length;
    console.log(`📋 Requirements: ${claimed}/${state.requirements.length} claimed`);
  }
  if (state.gaps.filter(g => g.status !== 'fixed').length) console.log(`⚠ Open gaps: ${state.gaps.filter(g => g.status !== 'fixed').length}`);
  // DECISIONS index governance (D-23 migration): count the truth source (project.json),
  // not file lines — GENERATED views are already scope-limited by the renderer (active + last 2 phases).
  // Phase V [MIN-3]: single core.loadProject — the parked line below shares this load.
  const proj = core.loadProject();
  const dIdxCount = (proj && Array.isArray(proj.decisions)) ? proj.decisions.length : 0;
  if (dIdxCount > 50) console.log(`⚠ DECISIONS index large: ${dIdxCount} entries (>50) — recent-2-phase scoping already applied by renderer`);
  // Phase V [D-06/R1-F1]: parked debt must be visible from ANY stage, not only archived-DONE
  // (doneHint covers the archived case; this line covers mid-flight status checks).
  const projParked = (proj && Array.isArray(proj.phases)) ? proj.phases.filter(x => x && x.status === 'parked').length : 0;
  if (projParked > 0) console.log(`🅿️ Parked phases: ${projParked} — close out via \`gos phase park <n> --undo\` / \`gos phase mark-done <n>\` (blocks milestone)`);
  // D-33 (E6): in-flow self-discovery pointer — frozen core.CONTRACTS string (T4 exact-match)
  console.log(core.CONTRACTS.decorative.fullCapabilityPointer);
}

function cmdStatus() {
  const state = core.readState();
  const eff = core.effectiveLocale();
  console.log(core.t('status.localeLine', { locale: eff.locale, source: eff.source }));
  // D-67/F16: lessons attribution on the human terminal surface — the FB-3
  // complainant is the human, not just the model (display-load: never bricks)
  {
    const attr = knowledge.lessonsAttribution();
    if (!attr.project.ok) {
      console.log(core.t('lessons.unavailable', { reason: attr.project.reason }));
    } else {
      console.log(core.t('lessons.attribution', {
        projN: attr.project.count,
        globN: attr.global.ok ? attr.global.count : 0,
        projPath: core.shortPath(attr.project.path),
        globPath: core.shortPath(attr.global.path),
        expiring: (attr.project.expiring || 0) + (attr.global.ok ? attr.global.expiring || 0 : 0),
      }));
    }
  }
  if (!state) {
    console.log(`📊 GOS: ${core.CONTRACTS.state_semantics.noActiveTask}`);
    console.log(core.t('status.noActiveTask.next'));
    console.log(core.CONTRACTS.decorative.fullCapabilityPointer);
    return;
  }
  printStatus(state);
  const skipCount = (state.semantic_skips || []).length; // R4-F9: visible skip accounting
  if (skipCount > 0) console.log(`⚠ semantic skips recorded: ${skipCount} time(s) via GOS_TEST_SANDBOX escape — review if unexpected`);
  console.log(`\nNext:\n${nextHint(state)}`);
}

function cmdNext() {
  const state = core.readState();
  if (!state) {
    console.log(`→ ${core.CONTRACTS.state_semantics.noActiveTask}`);
    console.log('→ Start one: `gos init <level> "<what do you want>"`');
    console.log(core.t('status.aiChatStart'));
    return;
  }
  console.log(`📍 ${state.current_stage} (Lv${state.level ?? '?'}) | ${core.sanitizeEcho(state.intent.summary)}`);
  console.log('');
  for (const line of structuredNextActions(state)) console.log(line);
  for (const line of handoffBlock(state)) console.log(line);   // gap-C: `gos next` tail gets the same handoff
  console.log('');
  console.log(core.t('status.aiChatContinue'));
}

function levelFlow(lv) {
  if (lv === 0) return ['INTENT', 'VERIFY', 'DONE'];
  if (lv === 1) return ['INTENT', 'BUILD', 'VERIFY', 'DONE'];
  if (lv === 2) return ['INTENT', 'THINK', 'BUILD', 'VERIFY', 'DONE'];
  return ['INTENT', 'THINK', 'PLAN', 'BUILD', 'REVIEW', 'VERIFY', 'SHIP', 'DONE'];
}

module.exports = { stageIndex, nextStage, progressBar, nextHint, handoffBlock, doneHint, structuredNextActions, printStatus, cmdStatus, cmdNext, levelFlow };
