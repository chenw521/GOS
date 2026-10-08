// render/index.cjs — module entry: spread-merges the aspect exports (the sole entry connection point)
'use strict';
module.exports = {
  ...require('./views.cjs'),
};
