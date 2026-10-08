// knowledge/index.cjs — module entry: command surface + spread-merged aspects (the single wiring point).
'use strict';

const core = require('../core/index.cjs');



module.exports = {
  ...Object.assign({}, require('./lessons.cjs'), require('./lessons-json.cjs'), require('./decisions.cjs'), require('./requirements.cjs'), require('./truth.cjs'), require('./concerns.cjs'), require('./phase.cjs')),

};
