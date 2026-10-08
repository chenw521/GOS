// core/fsio.cjs — primitives layer: filesystem/git/hash/path helpers (30 fns + GOS_PATHS)
// Require rule: sibling requires only — zero cross-directory dependencies.
'use strict';


const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const GOS_SELF_ROOT = path.dirname(path.dirname(path.dirname(path.dirname(path.resolve(__filename)))));   // CLI's own repo root (sec: validator; ×4 = bin/lib/core/fsio.cjs → repo)

const GOS_DIR = path.resolve('.gos');

const STATE_PATH = path.join(GOS_DIR, 'state.json');

const PROJECT_DIR = path.join(GOS_DIR, 'project');

const ARCHIVE_DIR = path.join(GOS_DIR, 'archive');

const SKILLS_DIR = path.resolve(GOS_SELF_ROOT, 'skills');

const CODING_STANDARDS_TEMPLATE_DIR = path.join(GOS_SELF_ROOT, 'templates', 'coding-standards');

// Repo-relative destination for `gos init coding` — a USER-repo docs path,
// deliberately NOT a GOS_PATHS key (resolvePath guards stay scoped to .gos/).
const CODING_STANDARDS_DEST_DIR = path.join('docs', 'coding-standards');
const PKG = require('../../../package.json');   // version/metadata shared across modules (bin/lib/core → repo/package.json)

function die(msg, code = 1) {
  console.error(`✗ ${msg}`);
  process.exit(code);
}

function writeAtomicJson(file, obj) {
  const dir = path.dirname(file);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = path.join(dir, `.${path.basename(file)}.tmp${process.pid}-${Date.now()}`);
  const data = JSON.stringify(obj, null, 2) + '\n';
  const fd = fs.openSync(tmp, 'w');
  try {
    fs.writeFileSync(fd, data, { flag: 'w' });
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(tmp, file);
}

const GOS_PATHS = {
  // --- root: global truth sources ---
  state:            { rel: 'state.json', producer: 'cli', readers: 'all commands', purge: 'never (task lifecycle)', tracked: false, granularity: 'file' },
  config:           { rel: 'config.json', producer: 'cli', readers: 'all commands', purge: 'never', tracked: true, granularity: 'file' },
  gates_json:       { rel: 'gates.json', producer: 'cli', readers: 'gate', purge: 'never', tracked: true, granularity: 'file' },
  concerns:         { rel: 'concerns.md', producer: 'cli', readers: 'concerns/status/red-team', purge: 'never', tracked: true, granularity: 'file' },
  cjk_whitelist:    { rel: 'cjk-whitelist.json', producer: 'cli (promoted from task dir 2026-09-30)', readers: 'gate cjk-lint', purge: 'never', tracked: true, granularity: 'file' },
  lessons:          { rel: 'lessons.md', producer: 'cli (regenerated view of lessons.json)', readers: 'lessons/status/red-team', purge: 'regen any time (json is truth)', tracked: true, granularity: 'file' },
  lessons_json:     { rel: 'lessons.json', producer: 'cli (lessons family)', readers: 'lessons/gate/commit/archive', purge: 'never (audit chain lives here)', tracked: true, granularity: 'file' },
  lessons_backup:   { rel: 'lessons-migration-backup-<ymd>.md', producer: 'cli (lessons migrate)', readers: 'migration rollback runbook', purge: 'latest generation only', tracked: true, granularity: 'file' },
  map_ignore:       { rel: 'map-ignore', producer: 'cli', readers: 'map', purge: 'never', tracked: true, granularity: 'file' },
  readme:           { rel: 'README.md', producer: 'cli (gos paths --markdown)', readers: 'human+agent navigation', purge: 'regen any time', tracked: true, granularity: 'file' },
  feedback_ledger:   { rel: 'FEEDBACK.md', producer: 'cli (feedback push backfill)', readers: 'paths render + humans', purge: 'regen any time (rendered)', tracked: true, granularity: 'file' },
  // --- root: CLI directories ---
  gates_dir:        { rel: 'gates', producer: 'cli', readers: 'gate', purge: 'never', tracked: true, granularity: 'dir' },
  project:          { rel: 'project', producer: 'cli', readers: 'phase/decision/requirement cmds', purge: 'never', tracked: true, granularity: 'dir' },
  feedback:         { rel: 'project/feedback', producer: 'user (gos feedback add)', readers: 'feedback list + phase planning', purge: 'never (feedstock)', tracked: false, granularity: 'dir' },
  codebase:         { rel: 'codebase', producer: 'cli (gos map)', readers: 'context/map', purge: 'regen on map refresh', tracked: true, granularity: 'dir' },
  archive:          { rel: 'archive', producer: 'cli (commit ship)', readers: 'human audit', purge: 'batch-prune after milestone (git history is the net)', tracked: true, granularity: 'dir' },
  renderers:        { rel: 'renderers', producer: 'user', readers: 'map graph --renderer', purge: 'user-managed free-zone', tracked: true, granularity: 'dir' },
  // --- cache/: machine caches, ALL ignored, safe to delete any time ---
  deps:             { rel: 'cache/deps.json', producer: 'cli (map extract)', readers: 'map/gate advisory', purge: 'regen (map refresh)', tracked: false, granularity: 'file' },
  run_manifest:     { rel: 'cache/run-manifest.json', producer: 'cli (sections runner)', readers: 'checkManifest gate', purge: 'regen each run', tracked: false, granularity: 'file' },
  trust:            { rel: 'cache/trust.json', producer: 'cli (gate trust)', readers: 'gate/section run', purge: 'never (user consent registry)', tracked: false, granularity: 'file' },
  edges_lock:       { rel: 'cache/edges.lock', producer: 'cli (commit)', readers: 'commit gate', purge: 'regen each commit', tracked: false, granularity: 'file' },
  edges:            { rel: 'cache/edges.json', producer: 'cli', readers: 'map', purge: 'regen', tracked: false, granularity: 'file' },
  backups_dir:      { rel: 'cache/backups', producer: 'cli (network.md refresh)', readers: 'none (rolling keep-5 recovery)', purge: 'rolling', tracked: false, granularity: 'dir' },
  concerns_anchors: { rel: 'cache/.concerns-anchors.json', producer: 'cli', readers: 'concerns anchor guard', purge: 'regen', tracked: false, granularity: 'file' },
  concerns_anchors_bak: { rel: 'cache/.concerns-anchors.bak', producer: 'cli', readers: 'recovery shadow', purge: 'regen', tracked: false, granularity: 'file' },
  lessons_anchors:  { rel: 'cache/.lessons-anchors.json', producer: 'cli', readers: 'lessons derived cache (live_ids; rebuildable via lessons anchor-rebuild)', purge: 'regen', tracked: false, granularity: 'file' },
  // --- logs/: audit receipts, tracked (Phase D T10 semantics preserved) ---
  truth_receipts:   { rel: 'logs/truth-receipts.md', producer: 'cli (truth verify)', readers: 'verify/audit', purge: 'never (cross-machine audit)', tracked: true, granularity: 'file' },
  exemptions:       { rel: 'logs/exemptions.log', producer: 'cli (gate --exempt)', readers: 'exempt audit', purge: 'never (cross-machine audit)', tracked: true, granularity: 'file' },
  edge_audit:       { rel: 'logs/edge-audit.log', producer: 'cli (commit gate)', readers: 'edge audit', purge: 'never (cross-machine audit)', tracked: true, granularity: 'file' },
  // --- task/<id>/: per-phase in-flight artifacts (dynamic) ---
  spec:             { rel: 'task/<task_id>/spec.md', producer: 'agent (THINK)', readers: 'plan/review/verify', purge: 'archived at commit ship', tracked: true, granularity: 'file' },
  plan:             { rel: 'task/<task_id>/plan.md', producer: 'agent (PLAN)', readers: 'build/review', purge: 'archived at commit ship', tracked: true, granularity: 'file' },
  task_evidence:    { rel: 'task/<task_id>/evidence', producer: 'agent (BUILD/VERIFY)', readers: 'verify/ship adoption', purge: 'archived at commit ship (dir-level ignored)', tracked: false, granularity: 'dir' },
  // --- transient: staging zone (orphan-scan excluded, T8a) ---
  ship_staging:     { rel: '.ship-staging', producer: 'cli (commit ship two-phase)', readers: 'ship transaction only', purge: 'rollback/rename on completion', tracked: false, granularity: 'dir' },
};

function resolvePath(key, subst) {
  const e = GOS_PATHS[key];
  if (!e) throw new Error(`GOS_PATHS: unknown key '${key}'`);
  let rel = e.rel;
  const m = rel.match(/<[a-z_]+>/g) || [];
  for (const ph of m) {
    const v = subst && subst[ph.slice(1, -1)];
    if (v == null || String(v) === '') throw new Error(`GOS_PATHS: placeholder '${ph}' unresolvable for key '${key}' (no active task?)`);
    rel = rel.split(ph).join(String(v));
  }
  const out = path.join(GOS_DIR, rel);
  // [REVIEW P2-F1] escape guard: resolved path must stay inside GOS_DIR (fail-fast, never guess)
  if (path.relative(GOS_DIR, out).startsWith('..')) throw new Error(`GOS_PATHS: resolved path escapes .gos/ for key '${key}'`);
  return out;
}

function sanitizeSingleLine(s) {
  return String(s == null ? '' : s).replace(/[\r\n]+/g, ' ').trim();
}

function escCell(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/\|/g, '\\|');
}

function sha256FileSync(p) {
  return crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
}

function gitToplevelRealpath() {
  try {
    const out = require('child_process').execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    return fs.realpathSync(out);
  } catch { return null; }
}

function gitInWorkTree() {
  try { execFileSync('git', ['rev-parse', '--is-inside-work-tree'], { stdio: 'pipe' }); return true; } catch { return false; }
}

function gitHeadSha() {
  try {
    return execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() || null;
  } catch { return null; }
}

function detectActivationSource() {
  const envHl = ['1', 'true', 'yes', 'on'].includes(String(process.env.GOS_HEADLESS || '').trim().toLowerCase());
  const inTty = process.stdin.isTTY === true;
  const outTty = process.stdout.isTTY === true;
  if (envHl || (!inTty && !outTty)) return 'headless';
  return (inTty && outTty) ? 'interactive-tty' : 'interactive-nontty';
}

function isHeadlessEnv() { return detectActivationSource() === 'headless'; }

function sanitizeEcho(s) {
  let t = String(s == null ? '' : s)
    // eslint-disable-next-line no-control-regex
    .replace(/[^\x20-\x7e\n\t\r\u00a0-\u{ffff}]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (t.length > 200) t = t.slice(0, 200) + '…';
  return t;
}

function sha16(s) {
  return crypto.createHash('sha256').update(String(s), 'utf8').digest('hex').slice(0, 16);
}

function globMatch(pattern, p) {   // minimal fnmatch: '*' wildcard only
  const parts = pattern.split('*');
  if (parts.length === 1) return p === pattern;
  let idx = 0;
  for (let i = 0; i < parts.length; i++) {
    const seg = parts[i];
    if (i === 0) { if (!p.startsWith(seg)) return false; idx = seg.length; continue; }
    if (i === parts.length - 1) { if (!p.endsWith(seg) || idx > p.length - seg.length) return false; continue; }
    const at = p.indexOf(seg, idx);
    if (at < 0) return false;
    idx = at + seg.length;
  }
  return true;
}

// GOS_SELF_ROOT is defined at the top of this file — guards against TDZ use-before-def.

let _trackedCache = null;

function trackedFiles(root) {
  if (_trackedCache && _trackedCache.root === root) return _trackedCache;
  const exact = new Set(), norm = new Map();   // norm(lowercased) → original tracked path
  try {
    const txt = execFileSync('git', ['-C', root, '-c', 'core.quotepath=off', 'ls-files'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    for (const l of txt.split('\n')) {
      const p = l.trim();
      if (!p) continue;
      exact.add(p);
      const nl = p.toLowerCase();
      if (!norm.has(nl)) norm.set(nl, p);
    }
  } catch { /* not a git repo — universe shrinks to scan set/fs */ }
  _trackedCache = { root, exact, norm };
  return _trackedCache;
}

function diskHasCaseVariant(root, rel) {   // case-insensitive filesystem honesty (R2-F9):
  const nl = rel.toLowerCase();            // a tracked match only counts if SOME case variant
  const dir = path.dirname(path.join(root, rel));   // actually exists on disk (deleted≠alive)
  try {
    for (const f of fs.readdirSync(dir)) {
      if (path.join(path.dirname(rel), f).toLowerCase() === nl) {
        try { if (fs.statSync(path.join(dir, f)).isFile()) return true; } catch { /* raced */ }
      }
    }
  } catch { /* dir gone */ }
  return false;
}

function writeAtomicText(file, text) {
  const dir = path.dirname(file);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = path.join(dir, `.${path.basename(file)}.tmp${process.pid}-${Date.now()}`);
  const fd = fs.openSync(tmp, 'w');
  try { fs.writeFileSync(fd, text, 'utf8'); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  fs.renameSync(tmp, file);
}

function pidAlive(pid) {
  if (!pid || typeof pid !== 'number') return false;
  try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; } // EPERM = exists but not ours
}

function ask(promptText) {
  process.stdout.write(promptText);
  return new Promise((resolve) => {
    let data = '';
    const stdin = process.stdin;
    if (!stdin.isTTY) { resolve(null); return; }  // non-interactive: fall to defaults
    stdin.setEncoding('utf8');
    stdin.resume();
    stdin.once('data', (d) => { stdin.pause(); resolve(d.trim()); });
  });
}

function gitArgvBytes(args) {
  try { return execFileSync('git', args, { stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 * 1024 * 1024 }); }
  catch { return null; }
}

function nulNames(buf) {
  if (!buf || !buf.length) return [];
  return buf.toString('utf8').split('\0').filter(Boolean);
}

function shaReachable(sha) {
  try { execFileSync('git', ['cat-file', '-e', `${sha}^{commit}`], { stdio: 'ignore' }); return true; }
  catch { return false; }
}

function pathOf(anchorSpec) { const i = String(anchorSpec).lastIndexOf('#'); return i === -1 ? String(anchorSpec) : String(anchorSpec).slice(0, i); }

function escCellMd(t) { return String(t).replace(/\|/g, '\\|').replace(/\n/g, ' '); }

function cryptoEmptySha() {
  return require('crypto').createHash('sha256').update('').digest('hex');
}

function worktreeContentHash(root) {
  // [T10 fix] stable content hash: sha256(HEAD tree + full diff-HEAD patch). git stash
  // create proved NON-deterministic across processes on identical visible state
  // (3-fail rule → swapped); diff-HEAD captures staged+worktree, verified byte-stable.
  try {
    const head = execFileSync('git', ['-C', root, 'rev-parse', 'HEAD^{tree}'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    const patch = execFileSync('git', ['-C', root, '-c', 'core.quotepath=off', 'diff', '--no-color', '--no-ext-diff', '--no-textconv', 'HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 32 * 1024 * 1024 });
    const crypto = require('crypto');
    const patchSha = crypto.createHash('sha256').update(patch).digest('hex');
    return { head_tree: head, patch_sha: patchSha };   // component form: commit-advance tolerant
  } catch { return null; }
}

function globToRegex(g) {
  const esc = g.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*\*/g, '\u0000').replace(/\*/g, '[^/]*').replace(/\u0000/g, '.*').replace(/\?/g, '[^/]');
  return new RegExp(`^${esc}$`);
}

function shellQ(s) { return `'${String(s).replace(/'/g, `'\\''`)}'`; }

// D-66 gate-evidence command-builder: the ONE sanctioned way to build fix lines
// containing dynamic values. Flags/subcommands live in `prog`; every value arg
// is shell-quoted, and `--` is inserted before the first value that looks like
// a path or starts with '-' (argv injection guard — adversarial filenames
// yield single-command-safe lines under `sh -c`).
function gateCmd(prog, ...values) {
  const parts = [String(prog)];
  let guard = false;
  for (const v of values) {
    const s = String(v == null ? '' : v);
    if (!guard && (s.startsWith('-') || s.includes('/') || s.startsWith('.') || (/^\.{0,2}$/.test(s)))) {
      parts.push('--');
      guard = true;
    }
    parts.push(shellQ(s));
  }
  return parts.join(' ');
}

// D-66 single failure constructor: {code, verdict, evidence[], fix}. Throws on
// missing mandatory fields (3-part discipline enforced by construction, F11).
// Locale invariants (D-63): code/evidence/fix NEVER pass through t(); verdict
// may resolve from the i18n catalog by code (wave 3) — this is the only field.
function gateFail(code, fields) {
  const f = fields || {};
  const verdict = f.verdict != null ? f.verdict : f.verdictKey;
  if (!code || typeof code !== 'string') throw new Error('gateFail: code is required (stable machine id)');
  if (verdict == null || String(verdict).trim() === '') throw new Error(`gateFail(${code}): verdict is required`);
  if (f.fix == null || String(f.fix).trim() === '') throw new Error(`gateFail(${code}): fix is required (what/why/fix standard)`);
  return {
    code,
    verdict: String(verdict),
    evidence: f.evidence == null ? [] : Array.isArray(f.evidence) ? f.evidence : [f.evidence],
    fix: String(f.fix),
  };
}

function safeGitArgv(args) { try { return execFileSync('git', args, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).toString(); } catch { return ''; } }

function symlinkOrJunction(target, linkPath, isDir = true) {
  fs.mkdirSync(path.dirname(linkPath), { recursive: true });
  // Idempotent: existing correct symlink = success (re-run friendly)
  try {
    const st = fs.lstatSync(linkPath);
    if (st.isSymbolicLink()) {
      try {
        if (fs.realpathSync(linkPath) === fs.realpathSync(target)) return; // already correct
      } catch { /* dangling — fall through to replace */ }
      fs.unlinkSync(linkPath); // wrong target or dangling — replace
    }
  } catch { /* not present */ }
  try {
    fs.symlinkSync(target, linkPath, isDir ? 'dir' : 'file');
  } catch (e) {
    if (e.code === 'EPERM' && process.platform === 'win32') {
      fs.symlinkSync(target, linkPath, isDir ? 'junction' : 'file');
    } else throw e;
  }
}

module.exports = {
  PKG,
  die,
  writeAtomicJson,
  writeAtomicText,
  sha256FileSync,
  sha16,
  resolvePath,
  sanitizeSingleLine,
  sanitizeEcho,
  escCell,
  escCellMd,
  ask,
  globMatch,
  globToRegex,
  shellQ,
  gateCmd,
  gateFail,
  safeGitArgv,
  symlinkOrJunction,
  shaReachable,
  cryptoEmptySha,
  worktreeContentHash,
  pidAlive,
  gitToplevelRealpath,
  gitInWorkTree,
  gitHeadSha,
  isHeadlessEnv,
  detectActivationSource,
  trackedFiles,
  diskHasCaseVariant,
  pathOf,
  gitArgvBytes,
  nulNames,
  GOS_DIR,
  STATE_PATH,
  PROJECT_DIR,
  ARCHIVE_DIR,
  SKILLS_DIR,
  CODING_STANDARDS_TEMPLATE_DIR,
  CODING_STANDARDS_DEST_DIR,
  GOS_PATHS,
  GOS_SELF_ROOT,
};
