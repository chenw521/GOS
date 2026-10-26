// ops/track — `gos track`: validated atomic ignored→tracked flip. T7a core
// steps 1-5 of spec §3.4 (D-15/D-14) + T7b transaction layer: flip manifest
// (.gos/track-manifest.json, per-line {ts,path,head} records, RT2-F5),
// rename-style backups under .gos/cache/track-backup/ with rollback on ANY
// mid-transaction failure (ENOSPC-safe: rollback = rename back, RT2-F10),
// adopt/no-op bookkeeping for already-tracked targets (RT3-F7) and the
// --knowledge preset (guide trio flip + idempotent born-at stamp).
// Transaction shape: die-before-touch validation (canonical path, no-symlink
// components, never-track zones, .env secrets, unborn HEAD, case guards) →
// tri-store + target pre-scan (language boundary reuse + sanitize table) →
// backup-stage the touched stores → [stamp] → manifest append → surgery
// (`.gos/.gitignore` relative-anchored negation, ignored-diff verify with
// rollback) → census-if-present edit → single `git add` tail (target +
// .gitignore + census + manifest) → delete backups.
// The restore path rides a process 'exit' hook: core.die's process.exit and
// uncaught throws BOTH restore every store byte-identically before exit.
// git runs argv-only (execFileSync); every die is die-before-touch.
// Require rule: namespace-only, sibling/domain (core via ../core/index.cjs).
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { execFileSync } = require('node:child_process');

const core = require('../core/index.cjs');

// Never-track zones (spec §3.4 step 1): machine-local by design — flipping a
// file here would leak caches/audit ledgers or fight the runtime (lock,
// staging). Shared with the T7b transaction and the T8 gate reconcile leg.
const TRACK_NEVER_ZONES = ['.gos/archive/', '.gos/logs/', '.gos/cache/', '.gos/.ship-staging/'];

// Never-track files: .gos/.lock fights the runtime; .gos/track-manifest.json
// is machine-managed by the flip transaction itself (a user flip on it would
// race the ledger) — the T8 gate leg exempts never-files from the
// manifest-record requirement, which is how the ledger tracks itself.
const TRACK_NEVER_FILES = ['.gos/.lock', '.gos/track-manifest.json'];

// Flip manifest (spec §3.4 step 6, RT2-F5) — tracked NDJSON ledger, one
// {ts, path, head} record per line (adopt records add "adopted": true).
// Consumed by the T8 gate flip-reconcile leg and the adopt/no-op resolver.
const TRACK_MANIFEST_REL = '.gos/track-manifest.json';

// Rename-style backup zone (GOS_PATHS key track_backup): machine-local,
// exists only inside a transaction window (deleted on success, renamed back
// on failure) — never a durable artifact.
const TRACK_BACKUP_REL = '.gos/cache/track-backup';

// Language-boundary trigger stores (spec §3.2): tracked members are
// English-only; the flip pre-scan reports every one of them before any
// mutation so a repo carrying zh content can never grow its tracked set.
const TRACK_STORES = ['.gos/state.json', '.gos/concerns.md', '.gos/lessons.json'];

// --knowledge preset trio (spec §3.4): guide files that travel with clones.
const KNOWLEDGE_TRIO = ['.gos/codebase/structure.md', '.gos/codebase/conventions.md', '.gos/codebase/concerns.md'];

// TEST-ONLY fault injection (mirrors GOS_TEST_BREAK_SHIP in task/archive.cjs):
// GOS_TEST_BREAK_TRACK=<manifest|surgery|census> throws mid-transaction so
// tests assert the rename-back rollback restores every store byte-identically.
// Inert unless the env var is set; never consult it in product logic.
function testBreak(stage) {
  if (process.env.GOS_TEST_BREAK_TRACK === stage) {
    throw new Error(`GOS_TEST_BREAK_TRACK: injected ${stage} failure`);
  }
}

// gitignore-unsafe path component (leading ! or # would be parsed as pattern
// syntax; a trailing space is silently trimmed by git) — refuse, never guess.
function gitignoreUnsafeComponent(rel) {
  return rel.split('/').some((c) => /^[!#]/.test(c) || /\s$/.test(c));
}

function gitRun(args, opts) {
  try {
    execFileSync('git', args, {
      stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024,
      cwd: (opts && opts.cwd) || undefined,
    });
    return { ok: true, err: '' };
  } catch (e) {
    return { ok: false, err: String((e && e.stderr) || (e && e.message) || 'git failed') };
  }
}

// Steps 1-5, die-before-touch. Returns ctx { top, rel, abs, argRel,
// alreadyTracked }. opts.allowTracked diverts the step-4 NOT-tracked die into
// ctx.alreadyTracked=true (cmdTrack then runs adopt/no-op bookkeeping,
// spec §3.4 step 1 / RT3-F7); the default keeps the strict die for future
// non-CLI callers.
function validateTrackTarget(raw, opts) {
  const arg = String(raw == null ? '' : raw).trim();
  if (!arg || arg.startsWith('-')) core.die('Usage: gos track <path-under-.gos> [--json]');
  const top = core.gitToplevelRealpath();
  if (!top) core.die(core.t('track.err.notRepo'));
  const real = core.canonicalRepoRel(path.resolve(arg));
  if (real == null || real === '') core.die(core.t('track.err.notFound', { path: arg }));
  if (!(real === '.gos' ? false : real.startsWith('.gos/'))) core.die(core.t('track.err.scope', { path: real }));
  const abs = path.join(top, real);
  let st = null;
  try { st = fs.lstatSync(abs); } catch { /* realpath resolved it moments ago */ }
  if (!st || !st.isFile()) core.die(core.t('track.err.notFound', { path: real }));
  // argv spelling honesty (RT3-F12): a case-only mismatch gets the canonical
  // correction; any other argv≠canonical gap means a symlinked or traversed
  // argv — realpath followed it to a different file, refuse both.
  const argRel = path.relative(top, path.resolve(arg)).split(path.sep).join('/');
  if (argRel !== real) {
    if (argRel.toLowerCase() === real.toLowerCase()) core.die(core.t('track.err.caseArg', { arg: argRel, canon: real }));
    core.die(core.t('track.err.symlink', { path: argRel, canon: real }));
  }
  // never-track zones + secrets family (.env) — machine-local or secret by design
  const zoneHit = TRACK_NEVER_ZONES.find((z) => real.startsWith(z)) || TRACK_NEVER_FILES.find((z) => real === z);
  if (zoneHit) core.die(core.t('track.err.zone', { path: real, zone: zoneHit }));
  const base = path.basename(real);
  if (base === '.env' || base.endsWith('.env') || base.startsWith('.env.')) core.die(core.t('track.err.env', { path: real }));
  // unborn HEAD: the flip reconciles against the HEAD blob (gitprobe cat-file
  // leg) — without a first commit there is no durable truth to reconcile with
  if (core.gitHeadSha() == null) core.die(core.t('track.err.unborn'));
  // NOT-tracked precondition (index ∪ HEAD, fail-closed via gitprobe): T7b
  // diverts tracked targets to adopt/no-op bookkeeping — a manifest record
  // present ∧ census consistent → verified no-op; legacy-tracked without a
  // record → adopt; census contradiction → die (spec §3.4 step 1, RT3-F7).
  const alreadyTracked = core.isTracked(abs);
  if (alreadyTracked && !(opts && opts.allowTracked)) core.die(core.t('track.err.tracked', { path: real }));
  // case-insensitive collision guard: a differently-cased twin on disk would
  // clobber one of the two on a case-insensitive clone — refuse the flip
  const dir = path.dirname(abs);
  const lower = real.toLowerCase();
  try {
    for (const f of fs.readdirSync(dir)) {
      if (path.join(path.dirname(real), f).toLowerCase() === lower && path.join(path.dirname(real), f) !== real) {
        core.die(core.t('track.err.caseDisk', { path: real, other: path.join(path.dirname(real), f) }));
      }
    }
  } catch { /* dir gone between probes — canonical above already pinned it */ }
  return { top, rel: real, abs, argRel, alreadyTracked: !!alreadyTracked };
}

function firstCjkLine(text) {
  const lines = String(text == null ? '' : text).split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    if (core.hasCJK(lines[i])) return { line: i + 1, text: lines[i].trim().slice(0, 120) };
  }
  return null;
}

// Sanitize table (spec §3.4 step 3): runtime paths ∪ fixed leak families ∪
// hostname exact. Ordered — the first matching pattern is the reported one.
function sanitizeTable() {
  const t = [];
  for (const p of [os.homedir(), os.tmpdir()]) if (p && p.length > 1) t.push({ pattern: p, label: p });
  for (const p of ['/home/', '/Users/', '/root/', '/mnt/', '/srv/', 'file://']) t.push({ pattern: p, label: p });
  t.push({ pattern: /[A-Z]:\\Users/i, label: '[A-Z]:\\Users' });
  t.push({ pattern: /~/, label: '~' });
  const h = os.hostname();
  if (h) t.push({ pattern: h, label: h });
  return t;
}

// Tri-store + target pre-scan, die-before-touch: reports the offending line.
function prescanFlip(ctx) {
  for (const storeRel of TRACK_STORES) {
    const storeAbs = path.join(ctx.top, storeRel);
    if (!fs.existsSync(storeAbs) || !core.isTracked(storeAbs)) continue;
    let hit = null;
    if (storeRel.endsWith('.json')) {
      let obj;
      try { obj = JSON.parse(fs.readFileSync(storeAbs, 'utf8')); } catch (e) { core.die(`${storeRel} is corrupted: ${e.message}`); }
      const leaf = core.firstCJKLeaf(obj);
      if (leaf) hit = { where: leaf.path, text: leaf.text };
    } else {
      hit = firstCjkLine(fs.readFileSync(storeAbs, 'utf8'));
      if (hit) hit.where = `line ${hit.line}`;
    }
    if (hit) core.die(core.t('track.prescan.storeCjk', { file: storeRel, where: hit.where, text: hit.text }));
  }
  const targetText = fs.readFileSync(ctx.abs, 'utf8');
  const cjk = firstCjkLine(targetText);
  if (cjk) core.die(core.t('track.prescan.targetCjk', { path: ctx.rel, line: cjk.line, text: cjk.text }));
  const table = sanitizeTable();
  const lines = targetText.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    for (const p of table) {
      const hit = p.pattern instanceof RegExp ? p.pattern.test(lines[i]) : lines[i].includes(p.pattern);
      if (hit) core.die(core.t('track.prescan.sanitize', { path: ctx.rel, line: i + 1, pattern: p.label, text: lines[i].trim().slice(0, 120) }));
    }
  }
  return true;
}

// Most-specific census key covering rel (exact > deeper prefix > shallower —
// census _doc matching rule). null when nothing covers it.
function mostSpecificCensusKey(entries, rel) {
  let best = null;
  let bestLen = -1;
  for (const k of Object.keys(entries || {})) {
    const kk = k.endsWith('/') ? k.slice(0, -1) : k;
    if (rel === kk && bestLen < Infinity) { best = k; bestLen = Infinity; continue; }
    if (rel.startsWith(kk + '/') && kk.length > bestLen) { best = k; bestLen = kk.length; }
  }
  return best;
}

// Manifest reader (per-line try→skip+count, never crash): returns the parsed
// records plus malformed-line count. The T8 gate reconcile leg consumes the
// same shape.
function manifestRead(top) {
  const out = { records: [], bad: 0 };
  const p = path.join(top, TRACK_MANIFEST_REL);
  let text = '';
  try { text = fs.readFileSync(p, 'utf8'); } catch { return out; }
  for (const line of text.split(/\r?\n/)) {
    const s = line.trim();
    if (!s) continue;
    try {
      const rec = JSON.parse(s);
      if (rec && typeof rec === 'object' && typeof rec.path === 'string') out.records.push(rec);
      else out.bad += 1;
    } catch { out.bad += 1; }
  }
  return out;
}

// Atomic whole-file append (tmp+rename discipline — appends without an fsync'd
// crash window). Returns the line written.
function manifestAppend(top, record) {
  const p = path.join(top, TRACK_MANIFEST_REL);
  let prev = '';
  try { prev = fs.readFileSync(p, 'utf8'); } catch { /* first record */ }
  if (prev !== '' && !prev.endsWith('\n')) prev += '\n';
  const line = JSON.stringify(record);
  core.writeAtomicText(p, prev + line + '\n');
  return line;
}

// Hard-link staging + rename-back rollback (RT2-F10 ENOSPC-safety): every
// touched store gets a hard-link twin in .gos/cache/track-backup/ BEFORE any
// mutation. A link costs one inode and zero data blocks (no copy — ENOSPC
// cannot strand a half-written backup), and because every product write goes
// through tmp+rename (fsio atomic discipline) the link keeps pointing at the
// pre-transaction bytes while the live path advances. Pure rename-staging is
// impossible here: the flip itself reads these stores and `git add`s them at
// the tail, so they must stay present. Rollback IS a rename (link → live
// path); a store that did not exist before the transaction is unlinked.
// restore() rides a process 'exit' hook: core.die's process.exit AND uncaught
// throws both restore byte-identically. commit() removes the hook and deletes
// the staging links.
function stageTransaction(top, rels) {
  const dir = path.join(top, TRACK_BACKUP_REL);
  fs.mkdirSync(dir, { recursive: true });
  const bakOf = (rel) => path.join(dir, rel.split('/').join('__'));
  const entries = [];
  const staged = [];
  try {
    for (const rel of rels) {
      const abs = path.join(top, rel);
      const existed = fs.existsSync(abs);
      entries.push({ rel, abs, existed });
      if (existed) {
        const bak = bakOf(rel);
        fs.linkSync(abs, bak);
        staged.push({ abs, bak });
      }
    }
  } catch (e) {
    for (const s of staged.reverse()) { try { fs.unlinkSync(s.bak); } catch { /* raced */ } }
    try { fs.rmdirSync(dir); } catch { /* leftover staging dir — cache zone */ }
    core.die(`track: transaction backup staging failed: ${e.message} (nothing was mutated)`);
  }
  let done = false;
  const restore = () => {
    if (done) return;
    done = true;
    const incomplete = [];
    for (const en of entries) {
      try {
        if (en.existed) {
          // the live path may hold an atomic-rewrite product — replace it with
          // the pre-transaction bytes from the staged link
          try { if (fs.existsSync(en.abs)) fs.unlinkSync(en.abs); } catch { /* raced */ }
          fs.renameSync(bakOf(en.rel), en.abs);
        } else if (fs.existsSync(en.abs)) {
          fs.unlinkSync(en.abs);   // created mid-transaction → prior absence
        }
      } catch { incomplete.push(en.rel); }
    }
    // The git-add tail may have staged a subset of the transaction set before
    // failing — sweep the index so "rolled back" covers worktree AND index.
    // HEAD always exists here (unborn HEAD dies at validation); reset on a
    // clean index is a harmless no-op for the die-before-touch steps.
    const reset = gitRun(['reset', '-q', '--', ...rels], { cwd: top });
    if (!reset.ok) incomplete.push(`index sweep (${reset.err.trim()})`);
    let stagingLeft = false;
    try { fs.rmdirSync(dir); } catch { stagingLeft = true; /* non-empty/raced — cache zone sweeps */ }
    if (stagingLeft) incomplete.push('staging dir');
    // Rollback gaps are never silent (spec §3.4: failure at ANY step restores
    // ALL stores): surface what survived and where the backup bytes live.
    if (incomplete.length) {
      process.stderr.write(core.t('track.err.rollbackIncomplete', {
        items: incomplete.join(', '),
        dir,
      }) + '\n');
    }
  };
  process.on('exit', restore);
  const commit = () => {
    if (done) return;
    done = true;
    process.removeListener('exit', restore);
    for (const en of entries) {
      if (en.existed) { try { fs.unlinkSync(bakOf(en.rel)); } catch { /* raced */ } }
    }
    try { fs.rmdirSync(dir); } catch { /* raced */ }
  };
  return { restore, commit };
}

// Census consistency for an ALREADY git-tracked target (spec §3.4 step 1):
// absent census = consistent (census-if-present philosophy); a covering entry
// saying git:false while git says tracked = contradiction (needs human eyes).
function censusConsistency(top, rel) {
  const censusPath = path.join(top, 'census.json');
  if (!fs.existsSync(censusPath)) return { present: false, consistent: true, key: null };
  let census;
  try { census = JSON.parse(fs.readFileSync(censusPath, 'utf8')); } catch (e) { core.die(`census.json is corrupted: ${e.message}`); }
  if (!census || typeof census.entries !== 'object' || census.entries == null) {
    return { present: true, consistent: true, key: null };
  }
  const key = mostSpecificCensusKey(census.entries, rel);
  if (key == null) return { present: true, consistent: true, key: null };
  const covering = key === rel || rel.startsWith((key.endsWith('/') ? key.slice(0, -1) : key) + '/');
  if (!covering) return { present: true, consistent: true, key: null };
  const entry = census.entries[key];
  if (entry && entry.git === false) return { present: true, consistent: false, key };
  return { present: true, consistent: true, key };
}

// Adopt / no-op bookkeeping for an already-tracked target (RT3-F7):
//   census contradiction → die (human eyes first)
//   manifest record for the path → {noop:true}, exit 0, zero mutations
//   legacy-tracked (no record) → append {adopted:true} record, exit 0
function runAdoptOrNoop(ctx) {
  const cen = censusConsistency(ctx.top, ctx.rel);
  if (!cen.consistent) core.die(core.t('track.err.censusContradiction', { path: ctx.rel, key: cen.key }));
  const hasRecord = manifestRead(ctx.top).records.some((r) => r.path === ctx.rel);
  if (hasRecord) {
    return {
      target: ctx.rel, noop: true, adopted: false,
      manifest: { present: true, adopted: false },
      census: { present: cen.present, consistent: true, key: cen.key },
      staged: [],
    };
  }
  const txn = stageTransaction(ctx.top, [TRACK_MANIFEST_REL]);
  try {
    const head = core.gitHeadSha();
    const record = { ts: new Date().toISOString(), path: ctx.rel, head, adopted: true };
    const line = manifestAppend(ctx.top, record);
    const r = gitRun(['add', '--', TRACK_MANIFEST_REL]);
    if (!r.ok) throw new Error(core.t('track.err.gitAdd', { path: TRACK_MANIFEST_REL, err: core.sanitizeEcho(r.err) }));
    txn.commit();
    return {
      target: ctx.rel, noop: false, adopted: true,
      manifest: { present: true, adopted: true, head, line },
      census: { present: cen.present, consistent: true, key: cen.key },
      staged: [TRACK_MANIFEST_REL],
    };
  } catch (e) {
    txn.restore();
    core.die(e && e.message ? e.message : String(e));
  }
}

// Born-at stamp (spec §3.4 --knowledge, §3.5): first line `born-at: <HEAD8>`,
// idempotent replace — an identical existing line writes nothing (no-op
// purity), a differing born-at line is replaced, anything else is prepended.
// Returns true when bytes changed.
function stampBornAt(abs, head8) {
  const line = `born-at: ${head8}`;
  const text = fs.readFileSync(abs, 'utf8');
  const lines = text.split(/\r?\n/);
  if (lines[0] === line) return false;
  if (/^born-at: [0-9a-f]{8,40}$/.test(lines[0])) lines[0] = line;
  else lines.unshift(line);
  core.writeAtomicText(abs, lines.join('\n'));
  return true;
}

// Full flip transaction: backup-stage the touched stores (target, .gitignore,
// census, manifest, state — all guarded, restore covers created files too) →
// [born-at stamp] → manifest record append → performFlip (surgery + census +
// single git add tail staging the manifest via extraStaged) → commit deletes
// backups. Any die/throw restores every store byte-identically first.
function runFlipTransaction(ctx, opts) {
  const o = opts || {};
  const txn = stageTransaction(ctx.top, ['.gos/.gitignore', 'census.json', TRACK_MANIFEST_REL, '.gos/state.json', ctx.rel]);
  try {
    if (o.stampHead8) stampBornAt(ctx.abs, o.stampHead8);
    const head = core.gitHeadSha();
    const record = { ts: new Date().toISOString(), path: ctx.rel, head };
    const line = manifestAppend(ctx.top, record);
    testBreak('manifest');
    const result = performFlip(ctx, { extraStaged: [TRACK_MANIFEST_REL] });
    txn.commit();
    result.manifest = { recorded: true, path: TRACK_MANIFEST_REL, head, line };
    return result;
  } catch (e) {
    txn.restore();
    core.die(e && e.message ? e.message : String(e));
  }
}

// Surgery + census-if-present + git add. Returns the T7b-facing result; every
// failure rolls the .gitignore edit back before dying. opts.extraStaged rides
// the single git add tail (the manifest path); when the manifest itself is
// ignored, the surgery negates it alongside the target and the verify expects
// the ignored-set diff to equal exactly the newly-negated set.
function performFlip(ctx, opts) {
  const o = opts || {};
  const extraStaged = (o.extraStaged || []).filter(Boolean);
  const result = { target: ctx.rel, surgery: { ran: false, negation: null, negated: [], appended: [] }, census: { present: false, edited: false, key: null }, staged: [] };
  const giPath = path.join(ctx.top, '.gos', '.gitignore');
  if (gitignoreUnsafeComponent(ctx.rel)) core.die(core.t('track.err.gitignoreUnsafe', { path: ctx.rel }));
  const preIgnored = core.ignoredSet();
  // what the .gos/.gitignore surgery must un-ignore: the target when ignored,
  // plus the manifest when it is staged by this flip AND currently ignored
  const needs = [];
  if (preIgnored.has(ctx.rel)) needs.push(ctx.rel);
  const manifestNeeded = extraStaged.includes(TRACK_MANIFEST_REL) && preIgnored.has(TRACK_MANIFEST_REL);
  if (manifestNeeded) needs.push(TRACK_MANIFEST_REL);
  if (needs.length > 0) {
    let prev = null;
    let existed = fs.existsSync(giPath);
    let body = '';
    if (existed) {
      prev = fs.readFileSync(giPath, 'utf8');
      body = prev.replace(/\r\n/g, '\n');
      if (!body.endsWith('\n') && body !== '') body += '\n';
    }
    const appended = [];
    for (const needRel of needs) {
      const negation = `!/${needRel.slice('.gos/'.length)}`;
      if (!body.split('\n').includes(negation)) {
        if (body === '' && !existed) body = '# gos track negations (managed by gos track — do not hand-edit)\n';
        body += `${negation}\n`;
        appended.push(needRel);
      }
    }
    if (appended.length > 0) {
      core.writeAtomicText(giPath, body);
      testBreak('surgery');
      const postIgnored = core.ignoredSet();
      const diff = [...new Set([...preIgnored].filter((p) => !postIgnored.has(p)))].sort();
      const expect = [...new Set(appended)].sort();
      if (diff.join(',') !== expect.join(',')) {
        // rollback: restore the prior bytes (or the prior absence) before dying
        if (existed) core.writeAtomicText(giPath, prev);
        else { try { fs.unlinkSync(giPath); } catch { /* raced */ } }
        core.die(core.t('track.surgery.verifyFail', { diff: diff.length ? diff.join(', ') : '(empty)' }));
      }
      result.surgery.appended = appended;
    }
    result.surgery.ran = true;   // idempotent re-entry: every needed negation already present
    result.surgery.negation = `!/${ctx.rel.slice('.gos/'.length)}`;
    result.surgery.negated = needs;
  }
  // census-if-present: obligations attach to the tracked set, and census is
  // the disposition ledger — flip/add ONLY when the covering entry disagrees.
  const censusPath = path.join(ctx.top, 'census.json');
  if (fs.existsSync(censusPath)) {
    result.census.present = true;
    let census;
    try { census = JSON.parse(fs.readFileSync(censusPath, 'utf8')); } catch (e) { core.die(`census.json is corrupted: ${e.message}`); }
    if (census && typeof census.entries === 'object' && census.entries != null) {
      const key = mostSpecificCensusKey(census.entries, ctx.rel);
      const entry = key != null ? census.entries[key] : null;
      const covering = key != null && (key === ctx.rel || ctx.rel.startsWith((key.endsWith('/') ? key.slice(0, -1) : key) + '/'));
      if (covering && entry && entry.git === false) {
        if (key === ctx.rel) {
          census.entries[key].git = true;
          census.entries[key].note = `tracked via gos track ${new Date().toISOString().slice(0, 10)} (flipped from git:false)`;
        } else {
          census.entries[ctx.rel] = { git: true, npm: false, note: `tracked via gos track ${new Date().toISOString().slice(0, 10)} (exact-key override of ${key})` };
        }
        core.writeAtomicJson(censusPath, census);
        testBreak('census');
        result.census.edited = true;
        result.census.key = key === ctx.rel ? key : ctx.rel;
      } else {
        result.census.key = covering ? key : null;
      }
    }
  }
  const addList = [ctx.rel];
  if (result.surgery.ran) addList.push('.gos/.gitignore');
  if (result.census.edited) addList.push('census.json');
  addList.push(...extraStaged);
  // Test seam: simulate a partially-applied add that then fails — part of the
  // set lands in the index, git reports failure — so restore() must sweep the
  // index, not just the worktree bytes.
  if (process.env.GOS_TEST_BREAK_TRACK === 'gitAdd') {
    gitRun(['add', '--', addList[0]], { cwd: ctx.top });
    core.die('GOS_TEST_BREAK_TRACK: injected gitAdd failure');
  }
  const r = gitRun(['add', '--', ...addList], { cwd: ctx.top });
  if (!r.ok) core.die(core.t('track.err.gitAdd', { path: ctx.rel, err: core.sanitizeEcho(r.err) }));
  result.staged = addList;
  return result;
}

// --knowledge preset (spec §3.4): flip the guide trio under .gos/codebase/ +
// stamp `born-at: <HEAD[0:8]>` first-line (idempotent replace). Requires all
// three files (die-before-touch); tracked members run adopt/no-op bookkeeping
// with an idempotent re-stamp.
function knowledgePreset(hasJson) {
  const top = core.gitToplevelRealpath();
  if (!top) core.die(core.t('track.err.notRepo'));
  const head = core.gitHeadSha();
  if (head == null) core.die(core.t('track.err.unborn'));
  for (const rel of KNOWLEDGE_TRIO) {
    if (!fs.existsSync(path.join(top, rel))) core.die(core.t('track.preset.err.missing', { path: rel }));
  }
  const head8 = head.slice(0, 8);
  const files = [];
  for (const rel of KNOWLEDGE_TRIO) {
    const ctx = validateTrackTarget(path.join(top, rel), { allowTracked: true });
    if (ctx.alreadyTracked) {
      const r = runAdoptOrNoop(ctx);
      r.bornAt = stampBornAt(ctx.abs, head8);   // idempotent re-stamp (byte-stable when HEAD unchanged)
      files.push(r);
    } else {
      prescanFlip(ctx);
      const r = runFlipTransaction(ctx, { stampHead8: head8 });
      r.bornAt = true;
      files.push(r);
    }
  }
  if (hasJson) {
    console.log(JSON.stringify({ ok: true, gos_version: core.PKG.version || 'unknown', command: 'track', preset: 'knowledge', head: head8, files }, null, 2));
    return;
  }
  for (const r of files) {
    const censusNote = r.census.edited ? 'census flipped' : r.census.present ? 'census consistent' : 'no census';
    if (r.surgery && r.surgery.ran) console.log(core.t('track.done.surgery', { path: r.target, negation: r.surgery.negation, census: censusNote }));
    else if (r.surgery) console.log(core.t('track.done.noSurgery', { path: r.target, census: censusNote }));
    else if (r.adopted) console.log(core.t('track.adopt.done', { path: r.target, census: censusNote }));
    else console.log(core.t('track.noop.done', { path: r.target, census: censusNote }));
  }
  console.log(core.t('track.knowledge.done', { n: files.length, head: head8 }));
}

function cmdTrack(args) {
  const a = args || [];
  const hasJson = a.includes('--json');
  const hasKnowledge = a.includes('--knowledge');
  const rest = a.filter((x) => x !== '--json' && x !== '--knowledge');
  if (hasKnowledge) {
    if (rest.length > 0) core.die('Usage: gos track --knowledge [--json]');
    return knowledgePreset(hasJson);
  }
  if (rest.length === 0) {
    // help form: machine envelope, rc=0 (byte-0 JSON, no banners)
    if (hasJson) {
      console.log(JSON.stringify({
        gos_version: core.PKG.version || 'unknown',
        command: 'track',
        usage: 'gos track <path-under-.gos> [--json] | gos track --knowledge [--json]',
        scope: '.gos/** only',
        steps: ['validate 1-5 (canonical/symlink/zones/env/unborn/tracked-divert/case)', 'tri-store+target pre-scan (language + sanitize)', 'rename-style backups (rollback = rename back)', 'manifest record append (.gos/track-manifest.json {ts,path,head})', 'gitignore negation surgery (ignored-diff == appended set)', 'census-if-present edit', 'git add (target + .gitignore + census + manifest)', 'adopt/no-op for already-tracked targets; --knowledge preset trio + born-at'],
      }, null, 2));
      return;
    }
    core.die('Usage: gos track <path-under-.gos> [--json]');
  }
  if (rest.length > 1) core.die('Usage: gos track <path-under-.gos> [--json]');
  const ctx = validateTrackTarget(rest[0], { allowTracked: true });
  if (ctx.alreadyTracked) {
    const result = runAdoptOrNoop(ctx);
    if (hasJson) {
      console.log(JSON.stringify({ ok: true, gos_version: core.PKG.version || 'unknown', command: 'track', ...result }, null, 2));
      return;
    }
    const censusNote = result.census.present ? 'census consistent' : 'no census';
    if (result.noop) console.log(core.t('track.noop.done', { path: ctx.rel, census: censusNote }));
    else console.log(core.t('track.adopt.done', { path: ctx.rel, census: censusNote }));
    return;
  }
  prescanFlip(ctx);
  const result = runFlipTransaction(ctx);
  if (hasJson) {
    console.log(JSON.stringify({ ok: true, gos_version: core.PKG.version || 'unknown', command: 'track', ...result }, null, 2));
    return;
  }
  const censusNote = result.census.edited ? 'census flipped' : result.census.present ? 'census consistent' : 'no census';
  if (result.surgery.ran) {
    console.log(core.t('track.done.surgery', { path: ctx.rel, negation: result.surgery.negation, census: censusNote }));
  } else {
    console.log(core.t('track.done.noSurgery', { path: ctx.rel, census: censusNote }));
  }
  console.log(core.t('track.done.manifest', { path: TRACK_MANIFEST_REL, head: result.manifest.head }));
}

module.exports = {
  cmdTrack,
  validateTrackTarget,
  prescanFlip,
  performFlip,
  mostSpecificCensusKey,
  manifestRead,
  manifestAppend,
  runAdoptOrNoop,
  runFlipTransaction,
  stampBornAt,
  TRACK_NEVER_ZONES,
  TRACK_NEVER_FILES,
  TRACK_STORES,
  TRACK_MANIFEST_REL,
  TRACK_BACKUP_REL,
  KNOWLEDGE_TRIO,
};
