// core/lock.cjs — primitives layer: lock primitives and mutable state (9 fns; sole host of the four mutable identifiers)
// CJS value-snapshot pitfall: cross-file reads/writes go through accessors only.
'use strict';

const os = require('node:os');

const fs = require('node:fs');
const path = require('node:path');
const fsio = require('./fsio.cjs');
const state = require('./state.cjs');

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

function guardCwd(cls, cmdName, breakLock) {
  if (cls === 'global') return;
  const here = fs.realpathSync('.');
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
  let root = stateL.project_root;
  if (!root) {
    // lazy migration: re-anchor before write (D-10) — same call, atomic
    root = state.currentRootRealpath() || here;
    stateL.project_root = root;
    try { fsio.writeAtomicJson(fsio.STATE_PATH, stateL); } catch { /* command will rewrite anyway */ }
  } else if (root !== here) {
    const top = state.currentRootRealpath();
    if (top !== here) {
      console.error(`✗ this .gos state belongs to project root: ${root}`);
      console.error(`  you are in: ${here}. cd to the project root first.`);
      releaseLock(); process.exit(1);
    }
    // here === toplevel but ≠ stored root: repo moved or fresh worktree → toplevel is truth, re-anchor
    stateL.project_root = here;
    try { fsio.writeAtomicJson(fsio.STATE_PATH, stateL); } catch { /* command will rewrite anyway */ }
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
