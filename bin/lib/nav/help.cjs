// nav/help — placement per aspect-rosters-v2.json
'use strict';

const core = require('../core/index.cjs');
const path = require('path');

function helpLookup(key) {
  const k = String(key).toLowerCase();
  if (k === core.NO_CMD_KEY || k === '') return [core.NO_CMD_KEY, core.COMMANDS[core.NO_CMD_KEY]];
  if (Object.prototype.hasOwnProperty.call(core.COMMANDS, k)) return [k, core.COMMANDS[k]]; // REVIEW-F1: hasOwn — prototype keys (constructor/__proto__) must NOT render
  for (const [name, e] of Object.entries(core.COMMANDS)) {
    if ((e.aliases || []).includes(k)) return [name, e];
  }
  return null;
}

function helpEnvelope() {
  let ver = 'unknown';
  try { ver = core.PKG.version || 'unknown'; } catch { /* guarded require, version unknown fallback */ }
  return {
    gos_version: ver,
    schema_version: 1,
 // Phase U: headless dual-mode documented ONLY in machine mode
    // the default human help page never teaches the auto-confirm path.
    headless_mode: {
      signal: 'non-TTY (stdin+stdout) OR env GOS_HEADLESS in {1,true,yes,on}',
      effect: 'gos init one-shots intent.confirmed=true with audit intent.confirmation={mode:headless-auto,ts}',
      guard: 'in-flight guard / DONE soft path / --force protection all still apply',
      flag_note: '--confirm/--confirmed on a NEW task dies in both modes (two-step protocol; alias retired)',
    },
    class_legend: {
      write: 'mutates task/project state — takes the .gos lock',
      read: 'read-only (no lock; concerns add/prune mutate via internal lock — metadata subclass)',
      exec: 'runs user scripts (gate)',
      global: 'project-independent (no lock, no state)',
    },
    commands: core.COMMANDS,
  };
}

function cmdHelp(args) {
  const a = args || [];
  const hasJson = a.includes('--json');
  const rest = a.filter((x) => x !== '--json');
  if (hasJson && rest.length > 0) core.die('help: --json and <cmd> are mutually exclusive — pick one');
  if (!hasJson && rest.length > 1) core.die('Usage: gos help [<cmd>|--json]');
  if (hasJson) {
    console.log(JSON.stringify(helpEnvelope(), null, 2));
    return;
  }
  if (rest.length === 1) {
    const hit = helpLookup(rest[0]);
    if (!hit) core.die(`Unknown command "${rest[0]}". Try \`gos help\` (or \`gos help --json\`).`);
    const [name, e] = hit;
    const target = e.aliasOf ? helpLookup(e.aliasOf) : null;
    const [tName, t] = target || [name, e];
    if (e.flagOnly) {
      console.log(`flag — run \`gos ${name}\``);
      console.log(`  ${e.desc}`);
      console.log(`Next: gos --version`);
      return;
    }
    console.log(`gos ${tName === core.NO_CMD_KEY ? '(no command)' : tName} — ${t.desc}`);
    console.log(`  class:   ${t.class}`);
    if (t.subs && t.subs.length) console.log(`  subs:    ${t.subs.join(' | ')}`);
    if (t.flags && t.flags.length) {
      for (const f of t.flags) console.log(`  flag:    ${f.name} (${f.scope}) — ${f.effect} [risk: ${f.risk}]`);
    }
    console.log(`  usage:   ${t.usage}`);
    if (tName === 'init') {
 // headless dual-mode detail lives HERE (explicit lookup) — never in the default index
      console.log('  headless: non-TTY or GOS_HEADLESS∈{1,true,yes,on} → init one-shots confirmed=true (audited in state.intent.confirmation)');
      console.log('  two-step: interactive init creates confirmed=false → user verbal yes → bare `gos init --confirm`');
      // git sub-mode documented at the nav layer (the COMMANDS entry is
      // core-owned); seeding never touches task state.
      console.log('  git:      gos init git seeds the git workflow bundle into the work-tree (no task state; flags: --codeowner <v> --overwrite --non-interactive --json --render-self); seeded files are adaptable starters — keep, change, or remove freely');
    }
    if (t.next && t.next.length) console.log(`  next:    ${t.next.join(' | ')}`);
    if (t.contractKeys && t.contractKeys.length) {
      console.log(core.t('help.contractKeysHeader'));
      for (const ck of t.contractKeys) console.log(`    ${ck}`);
    }
    console.log(`Next: gos help | gos help --json`);
    return;
  }
  // mode 1: human-readable index, grouped by class, derived from core.COMMANDS
  const groups = [['write', 'task/project state (lock)'], ['read', 'read-only'], ['exec', 'executes'], ['global', 'project-independent']];
  console.log(`GOS — Get Organized System CLI`);
  console.log('');
  console.log(`Usage: gos <command> [args]  — full detail: gos help <cmd> | machine: gos help --json`);
  for (const [cls, label] of groups) {
    const rows = Object.entries(core.COMMANDS).filter(([n, e]) => e.class === cls && !e.flagOnly);
    if (!rows.length) continue;
    console.log('');
    console.log(`— ${cls} (${label}) —`);
    const shown = rows.map(([n, e]) => {
 // REVIEW-F2: destructive flags surface INLINE in the index
      const descs = (e.flags || []).filter(f => f.risk === 'destructive');
      let d = e.desc;
      if (descs.length) d += ` ⚠ ${descs.map(f => f.name).join(',')} ${descs[0].scope}: ${descs[0].effect}`;
      return [n === core.NO_CMD_KEY ? core.NO_CMD_KEY : n, d];
    });
    const w = Math.max(...shown.map(([n]) => n.length));
    for (const [n, d] of shown) console.log(`  ${n}${' '.repeat(w - n.length + 2)}${d}`);
  }
  console.log('');
  console.log(`Every command's output ends with a "Next:" hint — follow the chain.`);
}

module.exports = { helpLookup, helpEnvelope, cmdHelp };
