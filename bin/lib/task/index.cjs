// task/index.cjs — module entry: spreads aspect exports (the only wiring point consumed by bin/gos.cjs)
'use strict';

// D-03 composition root: task is the only layer allowlisted to require BOTH
// knowledge and render — it installs the auto-render hook so knowledge
// mutations refresh project views without knowledge depending on render.
const _knowledge = require('../knowledge/index.cjs');
const _render = require('../render/index.cjs');
if (typeof _knowledge.setAutoRender === 'function') {
  _knowledge.setAutoRender((project) => _render.renderProjectViews(project, { auto: true }));
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
};
