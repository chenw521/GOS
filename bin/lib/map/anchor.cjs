// map/anchor.cjs — map module aspect (anchor parsing/validation + manual region)
// Require rules: same-directory mutual requires are free; cross-directory only → core
'use strict';

const engine = require('./engine.cjs');


const fs = require('node:fs');
const path = require('node:path');
const core = require('../core/index.cjs');

function manualRegion(content) {
  if (content === null || content === undefined) return null;
  const lines = String(content).split('\n');
  const idx = lines.findIndex((l) => l.trim() === core.CONTRACTS.command_contracts.manualMarker);
  if (idx === -1) return null;
  return lines.slice(idx).join('\n');
}

function cmdAnchor(args) {
  const sub = (args[0] || '').toLowerCase();
  if (sub !== 'fix') {
    console.log('Usage: gos anchor fix');
    console.log('  fix   re-anchor state.project_root to this checkout (rescue)');
    return;
  }
  const state = core.readState();
  if (!state) core.die(core.CONTRACTS.state_semantics.noActiveTask);
  state.project_root = core.currentRootRealpath() || fs.realpathSync('.');
  core.writeState(state);
  console.log(`${core.CONTRACTS.command_contracts.anchorFixed}${state.project_root}`);
}

function parseAnchor(spec) {
  if (spec.startsWith('/') || spec.startsWith('~/') || spec === '~') return { ban: 'abs' };
  const idx = spec.lastIndexOf('#');
  if (idx === -1) return { path: spec, anchor: null };
  const p = spec.slice(0, idx), a = spec.slice(idx + 1);
  if (p.includes('#')) return { ban: 'hash' };
  if (p.split('/').includes('..')) return { ban: 'traversal' };   // [R2-M2] escape hatch out of the repo universe
  if (/^L?\d+$/.test(a)) return { ban: 'line' };
  return { path: p, anchor: a };
}

function anchorKind(a) {
  if (a == null) return 'file';
  if (a.startsWith('cmd:')) return 'cmd';
  if (a.startsWith('fn:')) return 'fn';
  if (a.startsWith('sec:')) return 'sec';
  if (a.startsWith('h:')) return 'h';
  return 'contractKey';
}

let _contractKeysFlat = null;

function contractKeysFlat() {
  if (_contractKeysFlat) return _contractKeysFlat;
  const out = new Set();
  (function walk(o) {
    for (const k of Object.keys(o)) {
      const v = o[k];
      if (typeof v === 'string') out.add(k);
      else if (v && typeof v === 'object') walk(v);
    }
  })(core.CONTRACTS);
  _contractKeysFlat = out;
  return out;
}

function validateAnchor(spec, root) {
  const SC = core.CONTRACTS.semantic_checks;
  const parsed = parseAnchor(String(spec || ''));
  if (parsed.ban === 'abs') return { ok: false, msg: `✗ ${SC.anchorVerifAbsPath}` };
  if (parsed.ban === 'hash') return { ok: false, msg: `✗ ${SC.anchorVerifHashInPath}` };
  if (parsed.ban === 'traversal') return { ok: false, msg: `✗ ${SC.anchorVerifAbsPath}` };   // traversal treated as universe escape → same frozen text
  if (parsed.ban === 'line') return { ok: false, msg: `✗ ${SC.anchorVerifLineBan}` };
  const { path: p, anchor: a } = parsed;
  // universe = git-tracked ∪ scan-set (MAP_EXTS, skip dirs) — spec §4.2.
  // An on-disk but untracked+unscannable file is OUTSIDE the universe (dead):
  // legitimate new files enter via `edge add`'s forced git add, or by being scannable.
  const t = core.trackedFiles(root);
  const ext = path.extname(p);
  const top = p.split('/')[0];
  const inScanUniverse = engine.MAP_EXTS.has(ext) && !engine.MAP_SKIP_DIRS.has(top) && !top.startsWith('test-');
  const trackedExact = t.exact.has(p);
  let alive = false;
  const abs = path.join(root, p);
  try { alive = fs.statSync(abs).isFile(); } catch { alive = false; }
  if (!alive) {
    const hit = t.norm.get(p.toLowerCase());
    alive = !!(hit && hit !== p && core.diskHasCaseVariant(root, p));   // case variant on disk (R2-F9)
  }
  if (!alive || (!trackedExact && !inScanUniverse && !t.norm.has(p.toLowerCase()))) {
    return { ok: false, msg: `✗ ${SC.anchorVerifDeadPath.replace('<path>', p)}` };
  }
  {   // [P1-M1] dual-case collision: two tracked files differing only by case → die for human rename (R2-F9)
    const nl = p.toLowerCase();
    const dupes = [...t.exact].filter((x) => x.toLowerCase() === nl);
    if (dupes.length > 1) return { ok: false, msg: `✗ case-collision: tracked files ${dupes.join(' vs ')} differ only by case — rename one (anchors cannot address both unambiguously)` };
  }
  const kind = anchorKind(a);
  if (kind === 'file') return { ok: true, type: 'file', detail: p };
  if (kind === 'cmd') {
    const name = a.slice(4);
    if (!core.COMMANDS[name]) return { ok: false, msg: `✗ ${SC.anchorVerifDeadAnchor.replace('<kind>', 'cmd').replace('<anchor>', a)}` };
    return { ok: true, type: 'cmd', detail: name };
  }
  if (kind === 'fn') {
    const name = a.slice(3);
    let src = '';
    try { src = fs.readFileSync(abs, 'utf8'); } catch { /* unreadable → dead */ }
    if (!new RegExp(`^function ${name}\\b`, 'm').test(src)) return { ok: false, msg: `✗ ${SC.anchorVerifDeadAnchor.replace('<kind>', 'fn').replace('<anchor>', a)}` };
    return { ok: true, type: 'fn', detail: name };
  }
  if (kind === 'sec') {
    const name = a.slice(4);
    if (!fs.existsSync(path.join(root, 'test', 'sections', `${name}.test.sh`))) return { ok: false, msg: `✗ ${SC.anchorVerifDeadAnchor.replace('<kind>', 'sec').replace('<anchor>', a)}` };
    return { ok: true, type: 'sec', detail: name };
  }
  if (kind === 'h') {
    const title = a.slice(2);
    let src = '';
    try { src = fs.readFileSync(abs, 'utf8'); } catch { /* unreadable → dead */ }
    const esc = title.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (!new RegExp(`^#+\\s*${esc}\\s*$`, 'm').test(src)) return { ok: false, msg: `✗ ${SC.anchorVerifDeadAnchor.replace('<kind>', 'h').replace('<anchor>', a)}` };
    return { ok: true, type: 'h', detail: title };
  }
  // bare word = contract key (D-23③ consumers target frozen keys)
  if (!contractKeysFlat().has(a)) return { ok: false, msg: `✗ ${SC.anchorVerifDeadAnchor.replace('<kind>', 'contractKey').replace('<anchor>', a)}` };
  return { ok: true, type: 'contractKey', detail: a };
}

Object.assign(module.exports, {
  parseAnchor,
  anchorKind,
  contractKeysFlat,
  validateAnchor,
  cmdAnchor,
  manualRegion,
});   // assign, not reassign: keeps live references across the same-directory require cycle (CJS value semantics)
