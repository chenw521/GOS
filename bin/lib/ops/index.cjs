// ops/index.cjs — module entry: spreads the aspect exports (single wiring point to bin/gos.cjs)
'use strict';
module.exports = {
  ...require('./auto/cli.cjs'),
  ...require('./brownfield.cjs'),
  ...require('./config.cjs'),
  ...require('./doctor.cjs'),
  ...require('./feedback.cjs'),
  ...require('./gate.cjs'),
  ...require('./paths.cjs'),
  ...require('./push.cjs'),
  ...require('./section.cjs'),
  ...require('./setup.cjs'),
  ...require('./track.cjs'),
};
