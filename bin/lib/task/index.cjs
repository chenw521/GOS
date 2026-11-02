// task/index.cjs — module entry: spreads aspect exports (the only wiring point consumed by bin/gos.cjs)
'use strict';

// composition root: task is the only layer allowlisted to require BOTH
// knowledge and render — it installs the auto-render hook so knowledge
// mutations refresh project views without knowledge depending on render.
const _knowledge = require('../knowledge/index.cjs');
const _render = require('../render/index.cjs');
if (typeof _knowledge.setAutoRender === 'function') {
  _knowledge.setAutoRender((project) => _render.renderProjectViews(project, { auto: true }));
}

// Auto-loop orientation for nav surfaces: the hint provider lives in
// ops/auto/cli.cjs and nav reaches it only through this facade (nav→task and
// task→ops are the legal edges — the same direction commit.cjs uses for its
// ops aspect requires). The require is lazy so module load order never
// matters at composition time; the provider itself is read-only and
// failure-tolerant (a missing store renders nothing).
function autoHints(ctx) {
  const autoCli = require('../ops/auto/cli.cjs');
  return autoCli.autoHintProvider(ctx);
}

module.exports = {
  ...require('./init.cjs'),
  ...require('./commit.cjs'),
  ...require('./archive.cjs'),
  ...require('./stage.cjs'),
  ...require('./checkpoint.cjs'),
  ...require('./context.cjs'),
  ...require('./plansnap.cjs'),
  ...require('./changelog.cjs'),
  autoHints,
};
