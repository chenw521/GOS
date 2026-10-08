// task/checkpoint — Split-③ ②-4 (T2)
'use strict';

const core = require('../core/index.cjs');

function cmdCheckpoint(args) {
  const state = core.readState();
  if (!state) core.die(core.CONTRACTS.state_semantics.noActiveTask);
  const sub = (args[0] || '').toLowerCase();
  if (sub !== 'save') {
    console.log('Usage: gos checkpoint save --stage BUILD --unit wave2 --done "T3,T4" --remaining "T5"');
    return;
  }
  const get = (k) => {
    const i = args.indexOf(`--${k}`);
    return i !== -1 && args[i + 1] ? args[i + 1] : null;
  };
  const cp = {
    stage: (get('stage') || state.current_stage || '').toUpperCase(),
    unit: get('unit') || 'unnamed',
    done: get('done') || '',
    remaining: get('remaining') || '',
    at: new Date().toISOString(),
  };
  state.checkpoints = state.checkpoints || [];
  state.checkpoints.push(cp);
  core.writeState(state);
  console.log(`✓ Checkpoint: ${cp.stage}/${cp.unit} (done: ${cp.done || '-'}, remaining: ${cp.remaining || '-'})`);
  console.log('Next: continue, or `gos resume` after interruption');
}

module.exports = { cmdCheckpoint };
