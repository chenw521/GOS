// task/index.cjs — module entry: spreads aspect exports (the only wiring point consumed by bin/gos.cjs)
'use strict';
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
