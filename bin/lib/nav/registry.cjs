// nav/registry — placement per aspect-rosters-v2.json
'use strict';

const core = require('../core/index.cjs');
const sibc = require('./registry-consts.cjs');

function subclassOf(cmd, sub) {
  return sibc.SUBCLASS_OVERRIDES[`${cmd}.${sub}`] || null;
}

function verifyCommandRegistry() {
  const fail = (d) => { console.error(`✗ ${core.CONTRACTS.state_semantics.commandRegistrySelfCheck} ${d}`); process.exit(1); };
  const CLASS_SETS = { write: sibc.WRITE_CMDS, exec: sibc.EXEC_CMDS, global: sibc.GLOBAL_CMDS, read: sibc.READ_CMDS };
  // #1 switchUniverse(core.COMMANDS) === sibc.KNOWN_CASES (bidirectional)
  const su = switchUniverse(core.COMMANDS);
  const kc = new Set(sibc.KNOWN_CASES);
  for (const x of su) if (!kc.has(x)) fail(`registry has '${x}' absent from sibc.KNOWN_CASES`);
  for (const x of kc) if (!su.has(x)) fail(`sibc.KNOWN_CASES has '${x}' absent from registry universe`);
  for (const [name, e] of Object.entries(core.COMMANDS)) {
    if (!CLASS_SETS[e.class]) fail(`'${name}' invalid class '${e.class}'`);
    for (const ck of (e.contractKeys || [])) {
      const dot = ck.indexOf('.');
      const sec = ck.slice(0, dot), key = ck.slice(dot + 1);
      if (!core.CONTRACTS[sec] || !(key in core.CONTRACTS[sec])) fail(`'${name}' contractKey '${ck}' not in core.CONTRACTS`);
    }
    for (const f of (e.flags || [])) {
      if (/--force|--break-lock/.test(f.name) && (f.risk !== 'destructive' || !f.effect)) {
        fail(`'${name}' flag ${f.name} must carry risk:'destructive' and non-empty effect`);
      }
    }
    if (e.aliasOf) {
      const host = core.COMMANDS[e.aliasOf];
      if (!host) fail(`'${name}' aliasOf host '${e.aliasOf}' missing`);
      else if (host.aliasOf) fail(`'${name}' aliasOf chain — host is itself a delegate`);
    }
  }
  // #2 exact partition: every switch label owned by exactly one entry, in exactly
  // one class set, and that set matches the entry's declared class.
  for (const x of sibc.KNOWN_CASES) {
    const owners = Object.entries(core.COMMANDS).filter(([n, e]) => n === x || (e.aliases || []).includes(x));
    if (owners.length !== 1) fail(`switch label '${x || "''"}' owned by ${owners.length} entries`);
    const [, e] = owners[0];
    const sets = Object.entries(CLASS_SETS).filter(([, s]) => s.has(x)).map(([c]) => c);
    if (sets.length !== 1) fail(`switch label '${x || "''"}' in ${sets.length} class sets (${sets.join(',')}) — exact partition violated`);
    if (sets[0] !== e.class) fail(`'${owners[0][0]}' class '${e.class}' ≠ set membership '${sets[0]}'`);
  }
  // #5 sibc.SUBCLASS_OVERRIDES reference a real (cmd, sub-first-word)
  for (const key of Object.keys(sibc.SUBCLASS_OVERRIDES)) {
    const dot = key.indexOf('.');
    const cmd = key.slice(0, dot), sub = key.slice(dot + 1).split(' ')[0];
    const e = core.COMMANDS[cmd];
    if (!e) fail(`sibc.SUBCLASS_OVERRIDES '${key}' unknown command`);
    else if (!(e.subs || []).some(s => s.split(' ')[0] === sub)) fail(`sibc.SUBCLASS_OVERRIDES '${key}' sub not listed in ${cmd}.subs`);
  }
  // #6 core set ≤ 10 (D-20)
  const coreN = Object.values(core.COMMANDS).filter(e => e.core).length;
  if (coreN > 10) fail(`core set has ${coreN} entries (>10, D-20)`);
}

function switchUniverse(entries) {
  const u = new Set();
  for (const [name, e] of Object.entries(entries || {})) {
    for (const a of (e.aliases || [])) u.add(a);
    if (!e.flagOnly && name !== core.NO_CMD_KEY) u.add(name);
  }
  return u;
}

module.exports = { subclassOf, verifyCommandRegistry, switchUniverse };
