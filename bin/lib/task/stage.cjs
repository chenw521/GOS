// task/stage — Split-③ ②-4 (T2)
'use strict';

const core = require('../core/index.cjs');
const nav = require('../nav/status.cjs');   // direct aspect require (dependency DAG)

function cmdStage(args) {
  const state = core.readState();
  if (!state) core.die(core.CONTRACTS.state_semantics.noActiveTask);
  const sub = (args[0] || '').toLowerCase();
  if (sub === 'back') {
    const target = (args[1] || '').toUpperCase();
    if (!target || nav.stageIndex(target) === -1) core.die('Usage: gos stage back <STAGE>  (e.g. gos stage back think)');
    const curIdx = nav.stageIndex(state.current_stage);
    const targetIdx = nav.stageIndex(target);
    if (targetIdx >= curIdx) core.die(`${target} is not behind current stage ${state.current_stage}.`);
    // Remove stages after target from completed
    state.completed_stages = state.completed_stages.filter(s => nav.stageIndex(s) <= targetIdx);
    state.current_stage = target;
    // Record gap that triggered the back
    const reason = args.slice(2).join(' ') || 'discovered during ' + state.current_stage;
    // D-41 + R2-F8: the gap reason is sanitized (injection '\n- [' / isolated CR /
    // '(auto)' forgery → exit 1 BEFORE the gap is recorded).
    const rc_ = core.checkInputConstraint({ value: reason, maxCp: 400, label: 'stage back reason', noNewlineListPrefix: true });
    if (!rc_.ok) core.die(`✗ ${rc_.reason}`);
    if (rc_.value.includes('(auto)')) core.die(`✗ stage back reason: '(auto)' is reserved for the automated write-back`);
    // [T6/D-16] state.gaps is the single source: stage back NEVER mirrors into
    // concerns.md anymore (legacy mirrors are cured via `gos gap migrate` into
    // the .gos/logs/gap-history.ndjson ledger). The write path below stays
    // ordering-fatal — a die on the boundary leaves BOTH stores untouched.
    state.gaps.push({ id: `G-${Date.now()}`, type: 'major', description: `Fluid back to ${target}: ${reason}`, status: 'open' });
    core.writeState(state);
    console.log(`⏮ Fluid back: → ${target} (gap recorded)`);
    console.log(`Next:\n${nav.nextHint(state)}`);
  } else if (sub === 'show') {
    const cur = state.current_stage;
    const lv = state.level ?? '?';
    const flow = lv === 0 ? ['INTENT','VERIFY','DONE'] : lv === 1 ? ['INTENT','BUILD','VERIFY','DONE']
      : lv === 2 ? ['INTENT','THINK','BUILD','VERIFY','DONE']
      : ['INTENT','THINK','PLAN','BUILD','REVIEW','VERIFY','SHIP','DONE'];
    console.log(`Lv${lv} flow:`);
    console.log(flow.filter(s => s !== 'DONE').map(s => s === cur ? `👉${s}` : s).join(' → '));
  } else {
    console.log('Usage: gos stage <back|show>');
    console.log('  back <stage> [reason]  — fluid workflow: return to earlier stage');
    console.log('  show                   — display current flow position');
  }
}

module.exports = { cmdStage };
