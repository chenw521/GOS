// core/index.cjs — module entry: spread-merges the aspect exports (the sole entry connection point)
'use strict';

module.exports = {
  ...require('./fsio.cjs'),
  ...require('./state.cjs'),
  ...require('./lock.cjs'),
  ...require('./i18n.cjs'),
};
