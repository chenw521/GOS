// map/contract.cjs — map module aspect (the CONTRACTS dump outlet)
// Require rules: same-directory mutual requires are free; cross-directory only → core
'use strict';


const core = require('../core/index.cjs');

function cmdContract(args) {
  // T1 hidden sub-mode: `gos _contract --check-input "<text>" [--max-cp N]`
  // exercises the input-constraint helper for tests; exit 0/1.
  const a = args || [];
  const ci = a.indexOf('--check-input');
  if (ci !== -1) {
    const mi = a.indexOf('--max-cp');
    const maxCp = (mi !== -1 && /^\d+$/.test(String(a[mi + 1]))) ? parseInt(a[mi + 1], 10) : 200;
    const res = core.checkInputConstraint({ value: a[ci + 1], maxCp, label: 'input', noNewlineListPrefix: true });
    if (!res.ok) { console.error(`✗ ${res.reason}`); process.exit(1); }
    return;
  }
  // Phase W (T1): paths_registry attached as a SEPARATE top-level key (additive-only
  // for existing contract consumers — grep-based assertions unaffected).
  console.log(JSON.stringify({ ...core.CONTRACTS, paths_registry: core.GOS_PATHS }, null, 2));
}

Object.assign(module.exports, {
  cmdContract,
});   // assign, not reassign: keeps live references across the same-directory require cycle (CJS value semantics)
