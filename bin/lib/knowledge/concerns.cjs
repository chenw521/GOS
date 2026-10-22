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

// [T6/D-14] tracked probe = the fail-closed core primitive (T1 gitprobe), never
// an ad-hoc `ls-files` shell-out — probe semantics stay monopoly-owned.
function concernsFileTracked(P) {
  return core.isTracked(P.file);
}

// [T6/D-16] bootstrap predicate helper: blob id of the working file vs the HEAD
// blob. argv-only git (never a shell string); null on ANY git failure — callers
// treat null as divergence (fail-closed, no laundering without git truth).
function concernsBlobIds(P) {
  const rel = path.relative(P.root, P.file).split(path.sep).join('/');
  const run = (args) => {
    try {
      return execFileSync('git', args, { cwd: P.root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    } catch { return null; }
  };
  return { head: run(['rev-parse', `HEAD:${rel}`]), disk: run(['hash-object', '--', P.file]) };
}

function loadConcernsAnchor(P, opts = {}) {
  const SC = core.CONTRACTS.semantic_checks;
  const quiet = !!opts.quiet;
  let fileText = '';
  try { fileText = fs.readFileSync(P.file, 'utf8'); } catch { /* absent */ }
  if (!fs.existsSync(P.anchor)) {
    const entryLines = concernsEntryLines(fileText);
    if (entryLines.length > 0 && concernsFileTracked(P)) {
      // [T6/D-16] bootstrap predicate — tracked file + missing sidecar splits in two:
      // working file byte-identical to the HEAD blob → benign cache loss (the sidecar
      // is a rebuildable .gos/cache zone) → rebuild anchors SILENTLY; any divergence
      // (or unverifiable git truth) → hand-edited tracked file → die. Bootstrap must
      // never launder a tampered tracked file.
      const ids = concernsBlobIds(P);
      if (ids.head == null || ids.disk == null || ids.head !== ids.disk) {
        core.die(`✗ ${core.t('concerns.err.anchorMissingDirty')}`);
      }
      const anchor = { hashes: entryLines.map(concernsLineHash) };
      try { core.writeAtomicJson(P.anchor, anchor); }
      catch (e) { core.die(`✗ .concerns-anchors.json write failed: ${e.message}`); }
      try { core.writeAtomicJson(P.bak, anchor); }
      catch (e) { core.die(`✗ .concerns-anchors.bak write failed: ${e.message} — sidecar written, shadow not; inspect before proceeding`); }
      return { anchor, bootstrapped: true };   // silent rebuild — no banner
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
  // [T5/D-17] language boundary at the write path: the new line is the payload;
  // CJK + tracked concerns.md dies (fail-closed via the T1 git probe — checked
  // before the anchor load so the boundary wording wins the failure).
  core.dieTrackedStoreCJK(P.file, c.value);
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

// [T6/D-16] gap-history ledger — append-only ndjson at .gos/logs/gap-history.ndjson
// (machine-local zone; one JSON {ts,text} per line, JSON.stringify guarantees no
// raw newlines → line integrity by construction, the (auto) sentinel rides inside
// text). state.gaps is the single live source; this ledger is the durable record
// of what the stage-back write-back era mirrored into concerns.md before D-16.
function gapHistoryLedgerPath(P) {
  return path.join(P.root, '.gos', 'logs', 'gap-history.ndjson');
}

function readGapHistoryLedger(P) {
  let raw = '';
  try { raw = fs.readFileSync(gapHistoryLedgerPath(P), 'utf8'); } catch { return { entries: [], skipped: 0 }; }
  const entries = [];
  let skipped = 0;
  for (const line of raw.split('\n')) {
    const t = line.trim();
    if (!t) continue;
    try {
      const o = JSON.parse(t);
      if (o && typeof o.ts === 'string' && typeof o.text === 'string') entries.push(o);
      else skipped++;
    } catch { skipped++; }
  }
  return { entries, skipped };
}

function appendGapHistoryLedger(P, texts) {
  if (!texts.length) return;
  const file = gapHistoryLedgerPath(P);
  fs.mkdirSync(path.dirname(file), { recursive: true });   // logs/ may not exist yet
  let needsNl = false;
  try { const prev = fs.readFileSync(file, 'utf8'); needsNl = prev.length > 0 && !prev.endsWith('\n'); } catch { /* first row */ }
  const ts = new Date().toISOString();
  const chunk = texts.map((text) => JSON.stringify({ ts, text }) + '\n').join('');
  fs.appendFileSync(file, (needsNl ? '\n' : '') + chunk);
}

// Cure legacy stage-back mirrors: ledger append FIRST (the durable copy lands
// before the destructive edit; {text} dedupe makes a crash between the two
// retry-safe — a re-run removes the still-present mirror without duplicating
// ledger rows), then concerns.md edit, then anchor + .bak rebuild from the
// kept lines in the same transaction (prune's fail-closed shadow pattern).
// No pre-verification of the old anchor: the sidecar is derived cache
// (census: purge regen) — it is REBUILT from the post-edit file, which also
// retires any mirror hashes the legacy writer minted into it.
function migrateGapMirrors(P) {
  let fileText = '';
  try { fileText = fs.readFileSync(P.file, 'utf8'); } catch { /* absent → no-op */ }
  const lines = String(fileText).replace(/\r\n/g, '\n').split('\n');
  const mirrors = [];
  const kept = [];
  for (const l of lines) {
    const bare = l.replace(/\r+$/, '');
    if (bare.startsWith('- [') && bare.endsWith(' (auto)')) mirrors.push(bare);
    else kept.push(l);
  }
  if (!mirrors.length) return { removed: 0, deduped: 0 };
  const { entries } = readGapHistoryLedger(P);
  const seen = new Set(entries.map((e) => e.text));
  const fresh = mirrors.filter((t) => !seen.has(t));
  appendGapHistoryLedger(P, fresh);
  while (kept.length && !kept[kept.length - 1].trim()) kept.pop();
  core.writeAtomicText(P.file, kept.join('\n') + (kept.length ? '\n' : ''));
  const anchor = { hashes: kept.filter((l) => l.startsWith('- [')).map(concernsLineHash) };
  try { core.writeAtomicJson(P.anchor, anchor); }
  catch (e) { core.die(`✗ .concerns-anchors.json write failed: ${e.message}`); }
  try { core.writeAtomicJson(P.bak, anchor); }
  catch (e) { core.die(`✗ .concerns-anchors.bak write failed: ${e.message} — sidecar written, shadow not; inspect before proceeding`); }
  return { removed: mirrors.length, deduped: mirrors.length - fresh.length };
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
  gapHistoryLedgerPath,
  readGapHistoryLedger,
  migrateGapMirrors,
  cmdConcerns,
  CONCERNS_HEADER,
});   // assignment (not reassignment): sibling modules hold live references to this export
