// core/lock.cjs — primitives layer: lock primitives and mutable state (9 fns; sole host of the four mutable identifiers)
// CJS value-snapshot pitfall: cross-file reads/writes go through accessors only.
'use strict';

const os = require('node:os');

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const fsio = require('./fsio.cjs');
const state = require('./state.cjs');
const gitprobe = require('./gitprobe.cjs');

function withGlobalAnchorsLock(fn) {
  const lockPath = state.lessonsPaths('model').lock;
  fs.mkdirSync(path.dirname(lockPath), { recursive: true });
  if (fs.existsSync(lockPath)) {
    let info = null;
    try { info = JSON.parse(fs.readFileSync(lockPath, 'utf8')); } catch { /* corrupt */ }
    if (info && fsio.pidAlive(info.pid)) {
      console.error(`✗ global anchors lock held by live pid ${info.pid} (since ${info.started_at}) — wait for it or remove ${lockPath} if stale`);
      process.exit(1);
    }
    try { fs.unlinkSync(lockPath); } catch { /* racing */ }
  }
  let fd;
  try { fd = fs.openSync(lockPath, 'wx'); }
  catch (e) {
    if (e.code === 'EEXIST') fsio.die(`global anchors lock: ${lockPath} exists but is not a regular file (dangling symlink?) — inspect and remove it manually`);
    fsio.die(`global anchors lock: open failed (${e.message})`);
  }
  try {
    fs.writeSync(fd, JSON.stringify({ pid: process.pid, started_at: new Date().toISOString() }));
    fs.closeSync(fd); fd = null;
  } finally {
    if (fd !== null) try { fs.closeSync(fd); } catch { /* closed */ }
  }
  try { return fn(); } finally { try { fs.unlinkSync(lockPath); } catch { /* gone */ } }
}

function mapRootDir() {
  return state.currentRootRealpath() || fs.realpathSync('.');
}

let _edgeRootLock = null;

function acquireEdgeLock() {
  if (_lockHeld) return;   // main-layer guard already holds the lock for this process (same-file when cwd==ROOT — concerns R2-F9 pattern)
  const root = mapRootDir();
  const lp = path.join(root, '.gos', '.lock');
  if (_edgeRootLockPath === lp) return;   // re-entrant: this process already holds it
  fs.mkdirSync(path.join(root, '.gos'), { recursive: true });
  acquireLockAt(lp, CLI_BREAK_LOCK);
  _edgeRootLock = lp;
}

function concernsRootLock(P, fn) {
  const lockDir = path.join(P.root, '.gos');
  fs.mkdirSync(lockDir, { recursive: true });
  const lockPath = path.join(lockDir, '.lock');
  if (fs.existsSync(lockPath)) {
    let info = null;
    try { info = JSON.parse(fs.readFileSync(lockPath, 'utf8')); } catch { /* corrupt */ }
    if (info && fsio.pidAlive(info.pid)) {
      fsio.die(`✗ concerns lock held by live pid ${info.pid} (since ${info.started_at}) at ${lockPath} — wait for it`);
    }
    try { fs.unlinkSync(lockPath); } catch { /* racing */ }
  }
  const fd = fs.openSync(lockPath, 'wx');
  try { fs.writeSync(fd, JSON.stringify({ pid: process.pid, started_at: new Date().toISOString() })); } finally { fs.closeSync(fd); }
  try { return fn(); } finally { try { fs.unlinkSync(lockPath); } catch { /* gone */ } }
}

const LOCK_PATH = path.join(fsio.GOS_DIR, '.lock');

let _lockHeld = false;

function acquireLockAt(lockPath, breakIt) {   // [R2-C2] path-parameterized lock (ROOT-anchored callers)
  if (fs.existsSync(lockPath)) {
    let info = null;
    try { info = JSON.parse(fs.readFileSync(lockPath, 'utf8')); } catch { /* corrupt */ }
    let mtimeStale = false;
    try { mtimeStale = Date.now() - fs.statSync(lockPath).mtimeMs > 120000; } catch { mtimeStale = false; }
    const pidDead = !info || !fsio.pidAlive(info.pid);
    const stale = pidDead || mtimeStale;
    if (pidDead) {
      // Dead holder (crashed/killed writer, unreadable lock) — no one owns it.
      // Auto-recover with a warning (concernsRootLock precedent); a LIVE pid
      // below still blocks hard, and the ambiguous mtime-stale-live case
      // keeps requiring --break-lock.
      console.error(`⚠ stale GOS lock (pid ${info && info.pid} not running) — auto-recovered`);
    } else if (!breakIt || !stale) {
      if (mtimeStale) console.error(`${state.CONTRACTS.state_semantics.lockBlocked} (pid ${info && info.pid}) — heartbeat stale >120s: re-run with --break-lock`);
      else console.error(`${state.CONTRACTS.state_semantics.lockBlocked} (pid ${info && info.pid} is ALIVE): wait, or last resort rm ${lockPath}`);
      process.exit(1);
    }
    try { fs.unlinkSync(lockPath); } catch { /* racing */ }
  }
  const fd = fs.openSync(lockPath, 'wx');
  try { fs.writeSync(fd, JSON.stringify({ pid: process.pid, started_at: new Date().toISOString() })); } finally { fs.closeSync(fd); }
  _edgeRootLockPath = lockPath;
  process.on('exit', () => { try { if (_edgeRootLockPath === lockPath) fs.unlinkSync(lockPath); } catch { /* gone */ } });
}

let _edgeRootLockPath = null;

let CLI_BREAK_LOCK = false;

function acquireLock(breakLock) {
  fs.mkdirSync(fsio.GOS_DIR, { recursive: true });
  if (_lockHeld) return;
  if (fs.existsSync(LOCK_PATH)) {
    let info = null;
    try { info = JSON.parse(fs.readFileSync(LOCK_PATH, 'utf8')); } catch { /* corrupt */ }
    // [R2-F6] heartbeat dual-signal: a live pid is NECESSARY but mtime staleness (>120s)
    // also qualifies — PID reuse in containers/namespaces fakes liveness; the mtime
    // heartbeat (refreshed at acquire; CLI processes are short-lived) is the second voice.
    let mtimeStale = false;
    try { mtimeStale = Date.now() - fs.statSync(LOCK_PATH).mtimeMs > 120000; } catch { mtimeStale = false; }
    const pidDead = !info || !fsio.pidAlive(info.pid);
    const stale = pidDead || mtimeStale; // dead pid OR stale heartbeat (either qualifies for break)
    if (pidDead) {
      // Dead holder — auto-recover (acquireLockAt precedent); live pid blocks
      // hard, mtime-stale-live still requires --break-lock.
      console.error(`⚠ stale GOS lock (pid ${info && info.pid} not running) — auto-recovered`);
    } else if (!breakLock || !stale) {
      if (mtimeStale) {
        console.error(`${state.CONTRACTS.state_semantics.lockBlocked} (pid ${info && info.pid}, since ${info && info.started_at}) — lock heartbeat stale >120s:`);
        console.error('  re-run with --break-lock to clear it (pid may be recycled — container PID reuse).');
      } else {
        console.error(`${state.CONTRACTS.state_semantics.lockBlocked} (pid ${info && info.pid} is ALIVE, since ${info && info.started_at}):`);
        console.error('  wait for it to finish, or run from another directory.');
        console.error('  last resort: rm .gos/.lock — only if you have verified no gos process is running.');
      }
      process.exit(1);
    }
    try { fs.unlinkSync(LOCK_PATH); } catch { /* racing */ }
  }
  const fd = fs.openSync(LOCK_PATH, 'wx'); // O_CREAT|O_EXCL
  fs.writeSync(fd, JSON.stringify({ pid: process.pid, started_at: new Date().toISOString() }));
  fs.closeSync(fd);
  _lockHeld = true;
}

function releaseLock() {
  if (!_lockHeld) return;
  try { fs.unlinkSync(LOCK_PATH); } catch { /* already gone */ }
  _lockHeld = false;
}

// [T4a/D-12/D-18] identity-guard probes — argv-only git calls (never a shell
// string), state.cjs probe style. Null on any git failure: callers degrade to
// advisory, never die on git breakage alone.
function gitFact(args, rootDir) {
  try {
    return execFileSync('git', rootDir ? ['-C', rootDir, ...args] : args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  } catch { return null; }
}

// Linked-worktree predicate: git-dir ≠ git-common-dir (both realpath'd; the
// common dir may come back relative — resolve against the probe cwd).
function inLinkedWorktree() {
  const gd = gitFact(['rev-parse', '--absolute-git-dir']);
  const cd = gitFact(['rev-parse', '--git-common-dir']);
  if (!gd || !cd) return false;
  const cdAbs = path.isAbsolute(cd) ? cd : path.resolve('.', cd);
  try { return fs.realpathSync(gd).toString() !== fs.realpathSync(cdAbs).toString(); } catch { return false; }
}

// repo_id of every identifiable remote URL ( canonicalization per remote).
// Membership is a SET question — origin preference only governs STAMPING.
function remoteRepoIds(rootDir) {
  const names = (gitFact(['remote'], rootDir) || '').split(/\s+/).filter(Boolean);
  const ids = new Set();
  for (const n of names) {
    const url = gitFact(['remote', 'get-url', n], rootDir);
    if (!url) continue;
    const id = state.deriveRepoId(url);
    if (id != null) ids.add(id);
  }
  return [...ids];
}

function guardCwd(cls, cmdName, breakLock) {
  if (cls === 'global') return;
  const here = fs.realpathSync('.');
  // [T4a/T-03] linked worktree ∧ tracked state.json → die (every class):
  // worktrees share one state file — tracked state in a worktree is unsupported.
  if (fs.existsSync(fsio.STATE_PATH) && inLinkedWorktree() && gitprobe.isTracked(fsio.STATE_PATH)) {
    console.error('✗ tracked .gos/state.json inside a linked git worktree is unsupported (worktrees share one state file — concurrent writers would fork the task state)');
    console.error('  run GOS from the main checkout, or untrack the state file in this worktree.');
    process.exit(1);
  }
  if (cls === 'read') {
    console.error(`${state.CONTRACTS.state_semantics.cwdBanner}${here}`); // stderr banner — stdout stays machine-clean
    return;
  }
  // write/exec: lock first (any cwd), then anchor check
  acquireLock(breakLock);
  if (cmdName === 'init') {
    const top = state.currentRootRealpath();
    if (top && here !== top) {
      console.error(`✗ init must run at the project root (git toplevel): ${top}`);
      console.error('  cd there first — a nested .gos/ would create a second truth source.');
      releaseLock(); process.exit(1);
    }
    return; // no state yet — anchor written by init itself
  }
  if (cmdName === 'anchor') return; // anchor fix is the designated rescue (D-10)
  if (cmdName === 'paths') return;  // Phase W (T3): registry query never requires an active task; lock still held for --markdown writes
  if (!fs.existsSync(fsio.STATE_PATH)) {
    // no state HERE — but if an ancestor has .gos/state.json, we are in a subdir of a managed project
    let dir = here;
    while (true) {
      const parent = path.dirname(dir);
      if (parent === dir) break;
      dir = parent;
      if (fs.existsSync(path.join(dir, '.gos', 'state.json'))) {
        console.error(`✗ no GOS task in this directory — a project root was found above: ${dir}`);
        console.error('  cd to the project root first (write-class commands run at the root).');
        releaseLock(); process.exit(1);
      }
    }
    return; // genuinely unmanaged tree
  }
  let stateL = null;
  try { stateL = JSON.parse(fs.readFileSync(fsio.STATE_PATH, 'utf8')); } catch { return; } // corrupt → schema validation handles
  // [T4a/D-12/D-18] identity guard: the state binds to the repo it lands in via
  // repo_id (remote-URL hash set). The legacy path-anchor write-back is
  // REMOVED — no read-class or guard path writes state.json (T-01 byte-stability);
  // the ONE sanctioned opportunistic write is the null+remotes stamp below.
  const root = state.currentRootRealpath();
  const ids = remoteRepoIds(root);
  const stamped = stateL.repo_id == null ? null : String(stateL.repo_id);
  if (!ids.length) {
 // no usable remotes → identity unverifiable → advisory pass (no die).
    // repo_id null IS the recorded advisory (stamped at init) — silent pass; a
    // STAMPED binding that cannot be verified is the case worth one warning
    // (stderr only — stdout stays machine-clean).
    if (stamped != null) {
      console.error(`⚠ repo identity advisory: no usable git remotes — state repo_id ${stamped} binding not verifiable (D-18)`);
    }
  } else if (stamped == null) {
    // null + remotes → derive + store (sanctioned). Conservative: v4 states only —
    // pre-v4 states get repo_id from their own write-class migration (never a
    // hybrid v3+repo_id write), and the stamp is the ONLY field touched.
    if (stateL.schema_version === state.STATE_SCHEMA_VERSION) {
      const id = state.repoIdFromRemotes(root);
      if (id != null) {
        stateL.repo_id = id;
        try { fsio.writeAtomicJson(fsio.STATE_PATH, stateL); } catch { /* command's own write follows */ }
      }
    }
  } else if (!ids.includes(stamped) && !ids.includes(stamped.toLowerCase())) {
    console.error(`✗ repo identity mismatch: .gos/state.json repo_id ${stamped} matches none of this repository's remote identities (D-12)`);
    console.error('  this state was cloned or copied from a different repository.');
    console.error("  deliberate re-bind: `gos anchor fix` re-derives repo_id from this repo's remotes; otherwise remove .gos/ and `gos init` again.");
    releaseLock(); process.exit(1);
  }
}

// ---- mutable-state accessors (the only legal cross-file channel around the CJS value-snapshot pitfall) ----
function holdsLock() { return _lockHeld; }
function breakLockRequested() { return CLI_BREAK_LOCK; }
function setBreakLock(v) { CLI_BREAK_LOCK = v; }

module.exports = {
  withGlobalAnchorsLock,
  acquireEdgeLock,
  acquireLockAt,
  acquireLock,
  releaseLock,
  concernsRootLock,
  mapRootDir,
  guardCwd,
  LOCK_PATH,
  holdsLock,
  breakLockRequested,
  setBreakLock,
};
