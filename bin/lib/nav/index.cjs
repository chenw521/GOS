// nav/index — module entry: spreads the aspect exports (single wiring point to bin/gos.cjs)
'use strict';
module.exports = {
  ...require('./cmds.cjs'),
  ...require('./help.cjs'),
  ...require('./registry.cjs'),
  ...require('./status.cjs'),
};

// registry data surface rides the registry aspect export (6 consts incl. SUBCLASS_OVERRIDES)
Object.assign(module.exports, require('./registry-consts.cjs'));
