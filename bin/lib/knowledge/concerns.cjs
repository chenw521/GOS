// knowledge/concerns.cjs — knowledge module aspect: curated concern list + anchor sidecar.
// Sibling requires are free; cross-directory requires go to core only.
'use strict';

const { execFileSync } = require('node:child_process');

const fs = require('node:fs');
const path = require('node:path');
const core = require('../core/index.cjs');

function concernsPaths() {
  const root = core.mapRootDir();
  return {
    root,
    file: path.join(root, '.gos', 'concerns.md'),
    anchor: path.join(root, '.gos', core.GOS_PATHS.concerns_anchors.rel),
    bak: path.join(root, '.gos', core.GOS_PATHS.concerns_anchors_bak.rel),
  };
}

const CONCERNS_HEADER = '# Concerns (curated worry list — gos concerns add/prune)';

function concernsEntryLines(text) {
  return String(text || '').split('\n').filter((l) => l.startsWith('- ['));
}

function concernsLineHash(line) {
  return core.sha16(String(line).replace(/\r+$/, ''));
}

function concernsFileTracked(P) {
  try {
    const out = execFileSync('git', ['ls-files', '--', path.relative(P.root, P.file)], { cwd: P.root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    return !!out;
  } catch { return false; }
}

function loadConcernsAnchor(P, opts = {}) {
  const SC = core.CONTRACTS.semantic_checks;
  const quiet = !!opts.quiet;
  let fileText = '';
  try { fileText = fs.readFileSync(P.file, 'utf8'); } catch { /* absent */ }
  if (!fs.existsSync(P.anchor)) {
    const nonEmpty = concernsEntryLines(fileText).length > 0;
    if (nonEmpty && concernsFileTracked(P)) {
      core.die(`✗ concerns.md is git-tracked with entries but .concerns-anchors.json is missing — out-of-band deletion suspected; restore via git checkout (bootstrap forbidden, no laundering)`);
    }
    if (!quiet) console.log(`⚠ ${SC.concernsBootstrap}`);
    return { anchor: { hashes: [] }, bootstrapped: true };
  }
  let anchor;
  try { anchor = JSON.parse(fs.readFileSync(P.anchor, 'utf8')); }
  catch { core.die(`✗ .concerns-anchors.json PARSE FAILED — recover via git checkout / .concerns-anchors.bak`); }
  if (!anchor || !Array.isArray(anchor.hashes)) core.die(`✗ .concerns-anchors.json malformed (want {hashes[]})`);
  const fileHashes = concernsEntryLines(fileText).map(concernsLineHash);
  const aSet = new Set(anchor.hashes); const fSet = new Set(fileHashes);
  if (anchor.hashes.some((h) => !fSet.has(h)) || fileHashes.some((h) => !aSet.has(h))) {
    core.die(`✗ ${SC.concernsAnchorFail}`);
  }
  return { anchor, bootstrapped: false };
}

function appendConcernsLine(P, text, opts = {}) {
  const c = core.checkInputConstraint({ value: text, maxCp: 400, label: 'concern text', noNewlineListPrefix: true });
  if (!c.ok) core.die(`✗ ${c.reason}`);
  if (!opts.auto && c.value.includes('(auto)')) core.die(`✗ concern text: '(auto)' is a reserved write-back marker — manual entries may not carry it`);
  if (opts.auto && c.value.includes('(auto)')) core.die(`✗ concern text: '(auto)' may not appear in the source text (system appends it)`);
  const { anchor } = loadConcernsAnchor(P);
  const date = new Date().toISOString().slice(0, 10);
  const display = core.sha16(`${date}|${c.value}`).slice(0, 8);
  const line = `- [${date}] [${display}] ${c.value}${opts.auto ? ' (auto)' : ''}`;
  let fileText = '';
  try { fileText = fs.readFileSync(P.file, 'utf8'); } catch { /* absent */ }
  const body = fileText || `${CONCERNS_HEADER}\n`;
  const normalized = body.replace(/\r\n/g, '\n');
  const next = normalized.endsWith('\n') || !normalized ? normalized : normalized + '\n';
  core.writeAtomicText(P.file, next + line + '\n');
  anchor.hashes.push(concernsLineHash(line));
  // Sidecar + shadow writes are fail-closed — a swallowed failure here leaves
  // file/anchor inconsistent with an ugly deferred crash.
  try { core.writeAtomicJson(P.anchor, anchor); }
  catch (e) { core.die(`✗ .concerns-anchors.json write failed: ${e.message}`); }
  try { core.writeAtomicJson(P.bak, anchor); }
  catch (e) { core.die(`✗ .concerns-anchors.bak write failed: ${e.message} — sidecar written, shadow not; inspect before proceeding`); }
  return line;
}

function cmdConcerns(args) {
  const sub = args[0];
  const P = concernsPaths();
  if (sub === 'add') {
    const text = args.slice(1).join(' ');
    if (!text) core.die('Usage: gos concerns add "text"');
    core.concernsRootLock(P, () => appendConcernsLine(P, text));   // root-anchored lock
    console.log('✓ concern recorded');
    console.log('Next:\n  gos concerns list — review the curated worry list');
    return;
  }
  if (sub === 'list' || sub === undefined || sub === '') {
    const stray = args.slice(1).filter((a) => !['list'].includes(a));
    if (stray.length) core.die(`Usage: gos concerns list (unknown argument: ${stray[0]})`);
    loadConcernsAnchor(P, { quiet: true });   // verify-only (mismatch → exit 1)
    // Fresh repo has no concerns.md yet — bootstrap path returns without creating;
    // the read must be guarded (empty list, never a stack crash).
    let fileText = '';
    try { fileText = fs.readFileSync(P.file, 'utf8'); } catch { /* absent = empty */ }
    const lines = concernsEntryLines(fileText);
    if (!lines.length) console.log('(no concerns recorded — gos concerns add "text")');
    for (const l of lines) console.log(l);
    return;
  }
  if (sub === 'prune') {
    const i = args.indexOf('--contains');
    const needle = i >= 0 ? args[i + 1] : null;
    if (!needle) core.die('Usage: gos concerns prune --contains <substring>');
    core.concernsRootLock(P, () => {   // root-anchored lock
      const { anchor } = loadConcernsAnchor(P);
      let fileText = '';
      try { fileText = fs.readFileSync(P.file, 'utf8'); } catch { /* absent */ }
      const kept = []; const dropped = [];
      for (const l of String(fileText).replace(/\r\n/g, '\n').split('\n')) {
        if (l.startsWith('- [') && l.includes(needle)) dropped.push(l); else kept.push(l);
      }
      if (!dropped.length) core.die(`✗ no concern line matches '${needle}' — nothing pruned`);
      while (kept.length && !kept[kept.length - 1].trim()) kept.pop();
      core.writeAtomicText(P.file, kept.join('\n') + (kept.length ? '\n' : ''));
      anchor.hashes = kept.filter((l) => l.startsWith('- [')).map(concernsLineHash);
      core.writeAtomicJson(P.anchor, anchor);
      // .bak shadow failure is fail-closed (parity with lessons B-9) —
      // a silently-absent shadow breaks the documented recovery path.
      try { core.writeAtomicJson(P.bak, anchor); }
      catch (e) { core.die(`✗ .concerns-anchors.bak write failed: ${e.message} — sidecar written, shadow not; inspect before proceeding`); }
      console.log(`✓ pruned ${dropped.length} concern line(s) — .bak shadow updated`);
      console.log('Next:\n  gos concerns list — verify the curated list');
    });
    return;
  }
  core.die('Usage: gos concerns <add "text" | list | prune --contains <substring>>');
}

Object.assign(module.exports, {
  concernsPaths,
  concernsEntryLines,
  concernsLineHash,
  concernsFileTracked,
  loadConcernsAnchor,
  appendConcernsLine,
  cmdConcerns,
  CONCERNS_HEADER,
});   // assignment (not reassignment): sibling modules hold live references to this export
