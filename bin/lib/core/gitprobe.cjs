// core/gitprobe.cjs — fail-closed git probing primitives ( ; / ):
// clone-resume's tracked-flip gate refuses whenever git truth cannot be
// established. isTracked answers `true` (assume tracked) on ANY git failure
// (rc!=0, stderr chatter on rc=0, spawn exception, poisoned GIT_INDEX_FILE /
// GIT_DIR env, not-a-repo cwd) and caches the failure marker for callers to
// report via lastFailure(). Healthy verdict = ls-files --cached UNION
// cat-file -e HEAD:<rel> (TOCTOU-safe: files `git rm --cached`'d stay tracked
// through the HEAD blob leg). ignoredSet = one `status --porcelain -uall
// --ignored=matching` call (failure → empty set, the conservative direction).
// canonicalRepoRel = realpath + case guard → repo-relative form. Probes run in
// the caller's cwd (the worktree under inspection); node stdlib only.
// Require rule: sibling requires only (same directory).
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const fsio = require('./fsio.cjs');

// cat-file rc!=0 stderr shapes that are CLEAN negatives (path simply absent
// from HEAD, or HEAD unborn — nothing can be tracked through HEAD there), not
// git breakage. Three phrasings seen across git versions (2.34 "Not a valid
// object name", classic "does not exist in", 2.55+ "exists on disk, but not
// in"); anchored at `fatal:` so genuine breakage text never matches.
const HEAD_NEGATIVE_RE = /^fatal: (?:Not a valid object name|path '.*' does not exist in|path '.*' exists on disk, but not in) /;

let _failure = null;   // cached fail-closed marker; null while every probe is healthy
let _toplevel;         // realpath'd `rev-parse --show-toplevel`, cached (undefined = not probed)
let _indexSet;         // { exact: Set<string>, lower: Map<lowercase, path> }, cached

function lastFailure() { return _failure; }

function fail(marker) {
  _failure = fsio.sanitizeEcho(marker) || 'git probe failed';
  return _failure;
}

// Adversarial-env pre-flight (before any spawn): GOS never sets these itself,
// so a caller environment that does is exactly the shape the gate must refuse
// (/dev/null index devices, dead GIT_DIR paths, ...). Plausible values pass
// through and git itself remains the judge.
function envPoison() {
  const idx = process.env.GIT_INDEX_FILE;
  if (idx) {
    try { if (!fs.statSync(idx).isFile()) return `GIT_INDEX_FILE not a regular file: ${idx}`; }
    catch { return `GIT_INDEX_FILE unusable: ${idx}`; }
  }
  const gd = process.env.GIT_DIR;
  if (gd) {
    try { if (!fs.statSync(gd).isDirectory()) return `GIT_DIR not a directory: ${gd}`; }
    catch { return `GIT_DIR unusable: ${gd}`; }
  }
  return null;
}

// One git invocation with fail-closed triage. Returns { ok, out, negative } —
// ok=false with negative=true means a caller-expected clean negative stderr
// (`negativeRe`) that must NOT poison the failure cache.
function git(args, opts) {
  const o = opts || {};
  const poison = envPoison();
  if (poison) { fail(poison); return { ok: false, out: '' }; }
  let r = null;
  try {
    r = spawnSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024 });
  } catch (e) {
    fail(`git ${args[0]} exception: ${e && e.message}`);
    return { ok: false, out: '' };
  }
  const err = String((r && r.stderr) || '').trim();
  if (!r.error && o.negativeRe && o.negativeRe.test(err) && (r.status !== 0 || err)) {
    return { ok: false, negative: true, out: String(r.stdout || '') };
  }
  if (r.error) { fail(`git ${args[0]} spawn error: ${r.error.message}`); return { ok: false, out: '' }; }
  if (r.status !== 0) { fail(`git ${args[0]} rc=${r.status}${err ? ': ' + err : ''}`); return { ok: false, out: '' }; }
  if (err) { fail(`git ${args[0]} stderr on success: ${err}`); return { ok: false, out: '' }; }
  return { ok: true, out: String(r.stdout || '') };
}

function toplevelReal() {
  if (_failure) return null;
  if (_toplevel !== undefined) return _toplevel;
  const r = git(['rev-parse', '--show-toplevel']);
  const s = r.ok ? r.out.trim() : '';
  if (!s) { _toplevel = null; if (!_failure) fail('git rev-parse --show-toplevel: empty output'); return null; }
  try { _toplevel = fs.realpathSync(s); } catch { _toplevel = s; }
  return _toplevel;
}

// Cached ls-files --cached universe (raw -z paths, quotepath off). null once
// anything has failed — never guess from a partial read.
function indexSet() {
  if (_failure) return null;
  if (_indexSet) return _indexSet;
  const r = git(['-c', 'core.quotepath=off', 'ls-files', '--cached', '-z']);
  if (!r.ok) return null;
  const exact = new Set();
  const lower = new Map();
  for (const p of r.out.split('\0')) {
    if (!p) continue;
    exact.add(p);
    if (!lower.has(p.toLowerCase())) lower.set(p.toLowerCase(), p);
  }
  _indexSet = { exact, lower };
  return _indexSet;
}

// Absolute input → repo-relative spelling against the realpath'd toplevel,
// with a case-insensitive retry (macOS /users vs /Users prefix honesty).
// undefined = outside the worktree with git healthy (definitively untracked).
// No disk access: the file may be gone from the worktree yet alive in the
// index/HEAD (TOCTOU).
function toRepoRel(raw, top) {
  if (!path.isAbsolute(raw)) return path.normalize(raw).split(path.sep).join('/');
  if (raw === top) return '';
  if (raw.startsWith(top + path.sep)) return raw.slice(top.length + 1);
  const lt = top.toLowerCase();
  const lr = raw.toLowerCase();
  if (lr === lt) return '';
  if (lr.startsWith(lt + path.sep)) return raw.slice(top.length + 1);
  return undefined;
}

function isTracked(file) {
  if (_failure) return true;   // cached fail-closed short-circuit
  const raw = String(file == null ? '' : file).trim();
  if (!raw) { fail('isTracked: empty path'); return true; }
  let rel;
  if (path.isAbsolute(raw)) {
    const top = toplevelReal();
    if (_failure || !top) return true;
    rel = toRepoRel(raw, top);
    if (rel === undefined) return false;   // outside the worktree, git healthy
  } else {
    rel = toRepoRel(raw, '');
  }
  const set = indexSet();
  if (_failure || !set) return true;
  if (set.exact.has(rel)) return true;
 // Case-collision doubt (fail-closed bias, mirrors fsio honesty): a
  // differently-cased index twin that exists on disk counts as tracked.
  if (set.lower.has(rel.toLowerCase())) {
    const top = toplevelReal();
    if (_failure || !top) return true;
    if (fsio.diskHasCaseVariant(top, rel)) return true;
  }
  // TOCTOU leg: the index can lag HEAD (`git rm --cached` between commits) —
  // the HEAD blob is the durable truth for clone-resume.
  const cf = git(['cat-file', '-e', `HEAD:${rel}`], { negativeRe: HEAD_NEGATIVE_RE });
  if (cf.ok) return true;
  return _failure != null;   // clean negative → genuinely untracked
}

function ignoredSet() {
  const out = new Set();
  if (_failure) return out;   // fail-closed: declare nothing ignored
  const r = git(['-c', 'core.quotepath=off', 'status', '--porcelain', '-uall', '--ignored=matching', '-z']);
  if (!r.ok) return out;
  const parts = r.out.split('\0');
  for (let i = 0; i < parts.length; i++) {
    const rec = parts[i];
    if (!rec) continue;
    const xy = rec.slice(0, 2);
    if (xy === '!!') out.add(rec.slice(3));
    if (xy[0] === 'R' || xy[0] === 'C') i++;   // rename/copy: skip the NUL-joined orig path
  }
  return out;
}

// Tracked-under-prefix enumeration ( gate flip-reconcile leg): the sorted
// tracked path set under a repo-relative prefix ('.gos/' — the same set
// `git ls-files -z -- .gos` returns, quotepath off), served from the cached
// index universe with no second spawn. null when git truth is unavailable
// (fail-closed marker cached — callers must refuse, never guess a subset).
function trackedUnder(prefix) {
  if (_failure) return null;
  const set = indexSet();
  if (_failure || !set) return null;
  const raw = String(prefix == null ? '' : prefix);
  if (!raw) return [...set.exact].sort();
  const pfx = raw.endsWith('/') ? raw : raw + '/';
  return [...set.exact].filter((p) => p.startsWith(pfx)).sort();
}

function canonicalRepoRel(p) {
  const raw = String(p == null ? '' : p).trim();
  if (!raw) return null;
  let real;
  try { real = fs.realpathSync(raw); }   // on-disk case + symlink truth
  catch { return null; }                 // ENOENT etc: per-input miss, no cache poison
  if (_failure) return null;
  const top = toplevelReal();
  if (_failure || !top) return null;
  const rel = toRepoRel(real, top);
  if (rel === undefined || rel == null) return null;   // outside the worktree
  return rel;
}

module.exports = { isTracked, ignoredSet, canonicalRepoRel, trackedUnder, lastFailure, HEAD_NEGATIVE_RE };
