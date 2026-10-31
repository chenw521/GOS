// ops/auto/store — machine-local runner trust store, external to every
// spawned sandbox: schema-versioned records for the auto loop (mode/profile/
// limits, cumulative counters, breaker records, stream stamps, dispositions,
// runner-held snapshots, probe results) plus the exclusive run-lock family.
//
// Load semantics are fail-closed by construction: a missing, corrupt, or
// future-versioned store NEVER yields a fresh writable store — the loader
// returns a paused result with guidance, and only `create` (the `auto on`
// path) may lay down a fresh store, warning when tracked mirror counters
// imply prior history. The repo-local ledger mirror is never a read source
// here; this store is the single trust input.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const core = require('../../core/index.cjs');
const spawnreg = require('../../core/spawnreg.cjs');
const limits = require('./limits.cjs');

const STORE_SCHEMA_VERSION = 1;

const STORE_FILE = 'store.json';

const RUN_LOCK_FILE = 'run.lock';

// A held run lock is breakable only past this heartbeat age. The floor sits
// above the longest single wait the runner performs (spawn wall clock, CI
// watch); heartbeatStaleThresholdMs raises it further whenever a configured
// wall timeout could legally outlast the floor.
const LOCK_HEARTBEAT_STALE_MS = 90 * 60 * 1000;

// Safety margin added to a resolved wall timeout when it feeds the heartbeat
// staleness threshold: a spawn may run the full wall clock plus teardown.
const LOCK_HEARTBEAT_MARGIN_MS = 15 * 60 * 1000;

// Network filesystem types whose presence under the store path warns about
// shared-home double-runner hazards at `auto on`.
const NETWORK_FS_TYPES = new Set(['nfs', 'nfs4', 'cifs', '9p', 'lustre', 'lustre2', 'gpfs', 'beegfs']);

// Hard-refusal superset for `auto run`: types whose store would be shared
// across machines (two runners, one remote). A local-pid mutation mutex
// cannot serialize writers across hosts, so the run refuses instead.
const REFUSE_NETWORK_FS_TYPES = new Set([...NETWORK_FS_TYPES, 'ceph', 'fuse.sshfs']);

// Cross-process mutation mutex (store.mutate): bounded spin before the
// fail-closed store-busy refusal, retry cadence, and the mtime-age staleness
// threshold for locks whose holder identity this machine cannot verify.
const MUTATE_LOCK_FILE = 'mutate.lock';
const MUTATE_WAIT_MS = 5 * 1000;
const MUTATE_RETRY_MS = 20;
const MUTATE_MTIME_STALE_MS = 30 * 1000;

// Failure-class taxonomy for breaker records. Takeover is a lock-family
// event class, not a loop failure class — it appends records but never
// counts as a trip.
const BREAKER_CLASSES = new Set(['task', 'env', 'auth', 'timeout', 'takeover']);
const TRIP_CLASSES = new Set(['task', 'env', 'auth', 'timeout']);
const TRIP_LAYERS = new Set(['N', 'K', 'B']);

const SNAPSHOT_KINDS = new Set(['denyBaseline', 'hostSeed', 'redteamPrompt', 'prTemplate']);

// Append caps: oldest entries drop beyond the cap so a long-lived store
// stays bounded. In-flight entries are always the newest, never trimmed.
const CAPS = { breakerRecords: 100, dispositions: 200, probeResults: 50, stamps: 1000 };

const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/;

// ---- locale surfaces ----
// All user-facing failure text resolves through locale keys; the catalogs
// degrade to the key string when an entry has not landed yet, so guidance
// is never null and never a crash.
function sha256Of(text) {
  return require('node:crypto').createHash('sha256').update(String(text), 'utf8').digest('hex');
}

function guidanceFor(key, params) {
  const v = core.t(key, params);
  if (typeof v === 'string') return { what: v };
  return v;
}

// ---- location derivation ----

// XDG data home (absolute override respected per spec, else $HOME/.local/share).
function dataHome() {
  const x = process.env.XDG_DATA_HOME;
  if (x && path.isAbsolute(x)) return x;
  const home = os.homedir();
  if (!home) return null;
  return path.join(home, '.local', 'share');
}

// Stable identity for one clone. Prefer the git remote identity hash; a
// remote-less clone falls back to a `local:`-prefixed hash of its resolved
// absolute path so two clones on one machine never share a store.
function repoKey(rootDir) {
  let root = rootDir ? path.resolve(rootDir) : (core.currentRootRealpath() || process.cwd());
  try { root = fs.realpathSync(root); } catch { /* keep resolved path */ }
  const id = core.repoIdFromRemotes(root);
  if (id != null) return id;
  return 'local:' + crypto.createHash('sha256').update(root).digest('hex').slice(0, 16);
}

// Absolute store directory for the current clone, or null when no data home
// is resolvable at all (callers fail closed with unwritable guidance).
// Resolved per call so XDG_DATA_HOME overrides apply immediately.
function storeRoot(rootDir) {
  const home = dataHome();
  if (!home) return null;
  return path.join(home, 'gos', repoKey(rootDir));
}

function storeFile(rootDir) {
  const root = storeRoot(rootDir);
  return root == null ? null : path.join(root, STORE_FILE);
}

// ---- shape validation (corrupt = parse failure OR structural violation) ----

function isPlainObject(v) {
  return v != null && typeof v === 'object' && !Array.isArray(v);
}

function nonNegInt(v) {
  return Number.isInteger(v) && v >= 0;
}

function validateStoreShape(st) {
  const errs = [];
  if (!isPlainObject(st)) return ['store: not an object'];
  if (!Number.isInteger(st.store_schema_version)) errs.push('store_schema_version: integer required');
  if (st.mode !== 'on' && st.mode !== 'off') errs.push(`mode: 'on'|'off' required (got ${JSON.stringify(st.mode)})`);
  if (typeof st.profile !== 'string' || st.profile.length === 0) errs.push('profile: non-empty string required');
  if (!isPlainObject(st.limits) || !['N', 'K', 'B'].every((k) => Number.isInteger(st.limits[k]) && st.limits[k] >= 1)) {
    errs.push('limits: integers >= 1 required for N/K/B');
  }
  if (st.timeouts != null && (!isPlainObject(st.timeouts)
    || !Number.isInteger(st.timeouts.wallSec) || st.timeouts.wallSec < 1
    || !Number.isInteger(st.timeouts.idleSec) || st.timeouts.idleSec < 1)) {
    errs.push('timeouts: integers >= 1 required for wallSec/idleSec');
  }
  if (st.allowFull != null && typeof st.allowFull !== 'boolean') {
    errs.push('allowFull: boolean required');
  }
  if (!isPlainObject(st.counters) || !nonNegInt(st.counters.spawnCount) || !nonNegInt(st.counters.tripCount)) {
    errs.push('counters: integers >= 0 required for spawnCount/tripCount');
  }
  if (!isPlainObject(st.breaker) || !Array.isArray(st.breaker.records)) errs.push('breaker.records: array required');
  else if (!st.breaker.records.every((r) => isPlainObject(r) && typeof r.cls === 'string' && typeof r.ts === 'string')) {
    errs.push('breaker.records: entries need string cls+ts');
  }
  if (!isPlainObject(st.stamps)) errs.push('stamps: object required');
  else if (!Object.values(st.stamps).every((v) => isPlainObject(v) && typeof v.streamSha256 === 'string' && /^[0-9a-f]{64}$/.test(v.streamSha256))) {
    errs.push('stamps: values need hex64 streamSha256');
  }
  if (!Array.isArray(st.dispositions)) errs.push('dispositions: array required');
  else if (!st.dispositions.every((d) => isPlainObject(d) && typeof d.runId === 'string')) {
    errs.push('dispositions: entries need string runId');
  }
  if (!isPlainObject(st.snapshots)) errs.push('snapshots: object required');
  else if (!Object.values(st.snapshots).every((v) => isPlainObject(v) && typeof v.sha256 === 'string' && typeof v.content === 'string')) {
    errs.push('snapshots: values need string content+sha256');
  }
  if (!Array.isArray(st.probeResults)) errs.push('probeResults: array required');
  else if (!st.probeResults.every((p) => isPlainObject(p) && typeof p.host === 'string' && typeof p.state === 'string')) {
    errs.push('probeResults: entries need string host+state');
  }
  return errs;
}

// ---- load / create ----

function paused(reason, file, detail, localeKey, params) {
  const out = { ok: false, status: 'paused', reason, path: file, guidance: guidanceFor(localeKey, params) };
  if (detail) out.detail = detail;
  return out;
}

// Fail-closed read. Never throws, never creates directories, never repairs.
function load(rootDir) {
  const file = storeFile(rootDir);
  if (file == null) return paused('unwritable', null, 'no XDG data home resolvable', 'auto.store.unwritable');
  if (!fs.existsSync(file)) return paused('missing', file, null, 'auto.store.missing', { path: file });
  let raw;
  try { raw = fs.readFileSync(file, 'utf8'); }
  catch (e) { return paused('corrupt', file, e.message, 'auto.store.corrupt', { path: file }); }
  let st;
  try { st = JSON.parse(raw); }
  catch (e) { return paused('corrupt', file, e.message, 'auto.store.corrupt', { path: file }); }
  const errs = validateStoreShape(st);
  if (errs.length) return paused('corrupt', file, errs[0], 'auto.store.corrupt', { path: file });
  if (st.store_schema_version > STORE_SCHEMA_VERSION) {
    return paused('version-mismatch', file, `store at schema v${st.store_schema_version}, this CLI knows v${STORE_SCHEMA_VERSION}`, 'auto.store.versionMismatch', { found: st.store_schema_version, known: STORE_SCHEMA_VERSION });
  }
  if (st.store_schema_version < STORE_SCHEMA_VERSION) {
    return paused('version-mismatch', file, `store at older schema v${st.store_schema_version}`, 'auto.store.versionMismatch', { found: st.store_schema_version, known: STORE_SCHEMA_VERSION });
  }
  return { ok: true, status: 'ok', path: file, store: st };
}

function freshStore(opts) {
  const st = {
    store_schema_version: STORE_SCHEMA_VERSION,
    mode: opts.mode === 'on' ? 'on' : 'off',
    profile: typeof opts.profile === 'string' && opts.profile.length ? opts.profile : 'restricted',
    limits: { ...limits.DEFAULT_LIMITS },
    counters: { spawnCount: 0, tripCount: 0 },
    breaker: { records: [] },
    stamps: {},
    dispositions: [],
    snapshots: {},
    probeResults: [],
  };
  if (opts.timeouts != null) st.timeouts = { wallSec: opts.timeouts.wallSec, idleSec: opts.timeouts.idleSec };
  if (opts.allowFull === true) st.allowFull = true;
  return st;
}

// The only sanctioned fresh-store path (`auto on`). Refuses to reset an
// existing or broken store; seeds counters from tracked mirrors so cost
// history survives store loss, flagging the implied-history warning.
function create(opts = {}) {
  if (opts.limits != null) {
    const l = opts.limits;
    if (!isPlainObject(l) || !['N', 'K', 'B'].every((k) => Number.isInteger(l[k]) && l[k] >= 1)) {
      return { ok: false, status: 'error', reason: 'invalid-limits', detail: 'limits must be integers >= 1 for N/K/B' };
    }
  }
  if (opts.timeouts != null) {
    const t = opts.timeouts;
    if (!isPlainObject(t) || !Number.isInteger(t.wallSec) || t.wallSec < 1 || !Number.isInteger(t.idleSec) || t.idleSec < 1) {
      return { ok: false, status: 'error', reason: 'invalid-timeouts', detail: 'timeouts must be integers >= 1 for wallSec/idleSec' };
    }
  }
  if (opts.allowFull != null && typeof opts.allowFull !== 'boolean') {
    return { ok: false, status: 'error', reason: 'invalid-allow-full', detail: 'allowFull must be a boolean' };
  }
  const file = storeFile(opts.rootDir);
  if (file == null) return paused('unwritable', null, 'no XDG data home resolvable', 'auto.store.unwritable');
  const probe = probeWritable(opts.rootDir);
  if (!probe.ok) return probe;
  if (fs.existsSync(file)) {
    const cur = load(opts.rootDir);
    if (cur.ok) return { ok: true, created: false, path: file, store: cur.store };
    return cur; // existing store is paused material — never silently reset
  }
  const st = freshStore(opts);
  if (opts.limits != null) st.limits = { N: opts.limits.N, K: opts.limits.K, B: opts.limits.B };
  const mirrorsIn = isPlainObject(opts.mirrors) ? opts.mirrors : {};
  st.counters.spawnCount = nonNegInt(mirrorsIn.spawnCount) ? mirrorsIn.spawnCount : 0;
  st.counters.tripCount = nonNegInt(mirrorsIn.tripCount) ? mirrorsIn.tripCount : 0;
  const implied = st.counters.spawnCount > 0 || st.counters.tripCount > 0;
  try { core.writeAtomicJson(file, st); }
  catch (e) {
    return { ok: false, status: 'error', reason: 'write-failed', path: file, detail: e.message, guidance: guidanceFor('auto.store.unwritable', { path: file }) };
  }
  return {
    ok: true, created: true, path: file, store: st,
    impliedHistory: implied,
    guidance: implied ? guidanceFor('auto.store.recreatedOverHistory', { spawnCount: st.counters.spawnCount, tripCount: st.counters.tripCount }) : undefined,
  };
}

// Cheap writability probe: the store dir must be creatable and a probe file
// must round-trip. Fail-closed with guidance (`auto on` surfaces this).
function probeWritable(rootDir) {
  const root = storeRoot(rootDir);
  if (root == null) {
    return { ok: false, reason: 'unwritable', path: null, detail: 'no XDG data home resolvable', guidance: guidanceFor('auto.store.unwritable', {}) };
  }
  try {
    fs.mkdirSync(root, { recursive: true });
    const probeFile = path.join(root, `.probe-${process.pid}-${Date.now()}`);
    fs.writeFileSync(probeFile, 'ok');
    fs.unlinkSync(probeFile);
    return { ok: true, path: root };
  } catch (e) {
    return { ok: false, reason: 'unwritable', path: root, detail: e.message, guidance: guidanceFor('auto.store.unwritable', { path: root }) };
  }
}

// Detect a network filesystem holding the store directory: parse /proc/mounts
// for the longest-prefix mount of the resolved store path and report it when
// its type is network-shaped. Purely advisory — callers print the shared-home
// double-runner hazard; cross-host lock staleness stays hostname-guarded.
function networkFsUnderStore(rootDir) {
  const root = storeRoot(rootDir);
  if (root == null) return null;
  let target;
  try { target = fs.realpathSync(root); } catch { target = path.resolve(root); }
  let lines;
  try { lines = fs.readFileSync('/proc/mounts', 'utf8').split('\n'); } catch { return null; }
  let best = null;
  for (const line of lines) {
    const parts = line.trim().split(/\s+/);
    if (parts.length < 3) continue;
    const mp = parts[1].replace(/\\([0-7]{3})/g, (m, oct) => String.fromCharCode(parseInt(oct, 8)));
    const fstype = parts[2];
    let cmp;
    try { cmp = fs.realpathSync(mp); } catch { cmp = mp; }
    if (target === cmp || target.startsWith(cmp + path.sep)) {
      if (!best || cmp.length > best.mount.length) best = { mount: cmp, fstype };
    }
  }
  return best != null && NETWORK_FS_TYPES.has(best.fstype) ? best : null;
}

// ---- store mutation mutex ----

function mutateLockPath(rootDir) {
  const root = storeRoot(rootDir);
  return root == null ? null : path.join(root, MUTATE_LOCK_FILE);
}

// Identity written by every mutex holder: the pid bound to one process
// lifetime (boot_id + /proc starttime, the same binding the spawn channel
// uses), so a recycled pid can never fake the original holder's liveness.
function mutateHolderRecord() {
  return {
    hostname: os.hostname(),
    pid: process.pid,
    boot_id: readBootId(),
    starttime: spawnreg.procStartTime(process.pid),
    created_at: new Date().toISOString(),
  };
}

function readMutateLock(lp) {
  if (!fs.existsSync(lp)) return null;
  try { return JSON.parse(fs.readFileSync(lp, 'utf8')); }
  catch { return null; } // unreadable record = unproven ownership
}

let _mutateLockPath = null;
let _mutateDepth = 0;
let _mutateExitHook = false;

// Crash cleanup: a process dying mid-mutation must not strand its mutex
// (a live-pid lock blocks every other writer until the pid dies). Installed
// once; only ever removes OUR lock.
function installMutateExitHook() {
  if (_mutateExitHook) return;
  _mutateExitHook = true;
  process.on('exit', () => {
    if (_mutateLockPath == null) return;
    const rec = readMutateLock(_mutateLockPath);
    if (rec && rec.pid === process.pid && rec.hostname === os.hostname()) {
      try { fs.unlinkSync(_mutateLockPath); } catch { /* gone */ }
    }
  });
}

// Synchronous bounded sleep for the spin loop (blocks without burning CPU;
// mutate is deliberately synchronous).
function sleepSpinMs(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

// Exclusive creation of the mutex file: O_EXCL directly, hard-link fallback
// for filesystems without exclusive create (link fails with EEXIST exactly
// when the lock is already held). Returns false when the lock is held.
function createMutateLockFile(lp, rec) {
  let fd;
  try { fd = fs.openSync(lp, 'wx'); }
  catch (e) {
    if (e.code === 'EEXIST') return false;
    if (['ENOSYS', 'EOPNOTSUPP', 'EINVAL', 'EPERM'].includes(e.code)) {
      const tmp = `${lp}.tmp-${process.pid}-${Date.now()}`;
      try {
        fs.writeFileSync(tmp, JSON.stringify(rec));
        fs.linkSync(tmp, lp);
        return true;
      } catch { return false; }
      finally {
        try { fs.unlinkSync(tmp); } catch { /* gone */ }
      }
    }
    throw e;
  }
  try { fs.writeSync(fd, JSON.stringify(rec)); } finally { fs.closeSync(fd); }
  return true;
}

// Staleness verdict for an existing mutex. A readable same-host record is
// judged by full holder identity: a dead pid, a changed boot_id, or a
// starttime mismatch (the pid was recycled by an unrelated process) each
// prove the recorded holder gone and make the lock reclaimable. Records
// whose identity this machine cannot verify (unreadable, cross-host, no
// readable /proc starttime) fall back to lock mtime age.
function mutateLockStale(lp, staleMs) {
  const rec = readMutateLock(lp);
  const identityFallback = (why) => {
    let ageMs = NaN;
    try { ageMs = Date.now() - fs.statSync(lp).mtimeMs; } catch { ageMs = NaN; }
    if (Number.isFinite(ageMs) && ageMs > staleMs) {
      return { stale: true, holder: rec, detail: `holder identity unreadable (${why}); lock mtime ${Math.round(ageMs / 1000)}s old past the ${Math.round(staleMs / 1000)}s threshold` };
    }
    return { stale: false, holder: rec, identityUnreadable: true };
  };
  if (rec == null) return identityFallback('record unreadable');
  if (!Number.isInteger(rec.pid)) return identityFallback('record has no pid');
  if (rec.hostname !== os.hostname()) return identityFallback('holder is on another host');
  const myBoot = readBootId();
  if (myBoot != null && rec.boot_id != null && rec.boot_id !== myBoot) {
    return { stale: true, holder: rec, detail: `holder pid ${rec.pid} is from a previous boot (boot_id changed)` };
  }
  if (!livePid(rec.pid)) {
    return { stale: true, holder: rec, detail: `holder pid ${rec.pid} is not running` };
  }
  const st = spawnreg.procStartTime(rec.pid);
  if (rec.starttime == null || st == null) return identityFallback('holder starttime unverifiable');
  if (Number(rec.starttime) !== st) {
    return { stale: true, holder: rec, detail: `pid ${rec.pid} was recycled (starttime mismatch) — the recorded holder is gone` };
  }
  return { stale: false, holder: rec };
}

// Acquire the mutation mutex with a bounded spin. Returns { ok, takeover }
// (takeover carries the reclaim audit detail when a stale lock was broken)
// or the fail-closed store-busy refusal — contention is never resolved by
// last-writer-wins.
function acquireMutateLock(rootDir, opts = {}) {
  const lp = mutateLockPath(rootDir);
  if (lp == null) return paused('unwritable', null, 'no XDG data home resolvable', 'auto.store.unwritable');
  const waitMs = Number.isFinite(opts.waitMs) && opts.waitMs >= 0 ? opts.waitMs : MUTATE_WAIT_MS;
  const staleMs = Number.isFinite(opts.staleMs) && opts.staleMs > 0 ? opts.staleMs : MUTATE_MTIME_STALE_MS;
  try { fs.mkdirSync(path.dirname(lp), { recursive: true }); }
  catch (e) { return { ok: false, status: 'error', reason: 'unwritable', path: lp, detail: e.message, guidance: guidanceFor('auto.store.unwritable', { path: lp }) }; }
  const deadline = Date.now() + waitMs;
  let takeoverDetail = null;
  for (;;) {
    if (!fs.existsSync(lp)) {
      let created;
      try { created = createMutateLockFile(lp, mutateHolderRecord()); }
      catch (e) {
        return { ok: false, status: 'error', reason: 'mutex-create-failed', path: lp, detail: e.message, guidance: guidanceFor('auto.store.unwritable', { path: lp }) };
      }
      if (created) {
        _mutateLockPath = lp;
        installMutateExitHook();
        return { ok: true, path: lp, takeover: takeoverDetail };
      }
    }
    const verdict = mutateLockStale(lp, staleMs);
    if (verdict.stale) {
      takeoverDetail = takeoverDetail || verdict.detail;
      try { fs.unlinkSync(lp); } catch { /* racing writer — re-evaluate */ }
      continue;
    }
    if (Date.now() >= deadline) {
      const holderPid = verdict.holder && verdict.holder.pid;
      return {
        ok: false, status: 'error', reason: 'store-busy', path: lp, holder: verdict.holder || null,
        detail: `store mutation mutex held${holderPid != null ? ` by pid ${holderPid}` : ''} past the ${Math.round(waitMs / 1000)}s wait`,
        guidance: guidanceFor('auto.store.mutateBusy', { pid: holderPid }),
      };
    }
    sleepSpinMs(MUTATE_RETRY_MS);
  }
}

// Release OUR mutex (the outermost mutate releases; nested mutates join the
// outer critical section). Foreign locks are never touched.
function releaseMutateLock() {
  const lp = _mutateLockPath;
  if (lp == null) return;
  const rec = readMutateLock(lp);
  if (rec && rec.pid === process.pid && rec.hostname === os.hostname()) {
    try { fs.unlinkSync(lp); } catch { /* gone */ }
  }
  _mutateLockPath = null;
}

// Hard network-filesystem refusal for the auto run entry: resolves the
// store directory against the mount table (longest covering mount wins) and
// refuses when that mount is network-shaped. The mount table is injectable
// (tests feed a fixture table); an unreadable table passes — the advisory
// probe at `auto on` still warns there.
function refuseNetworkStore(rootDir, opts = {}) {
  const read = typeof opts.readMounts === 'function'
    ? opts.readMounts
    : () => fs.readFileSync(opts.mountsFile || '/proc/mounts', 'utf8');
  const root = storeRoot(rootDir);
  if (root == null) return { ok: true };
  let target;
  try { target = fs.realpathSync(root); } catch { target = path.resolve(root); }
  let lines;
  try { lines = String(read()).split('\n'); } catch { return { ok: true }; }
  let best = null;
  for (const line of lines) {
    const parts = line.trim().split(/\s+/);
    if (parts.length < 3) continue;
    const mp = parts[1].replace(/\\([0-7]{3})/g, (m, oct) => String.fromCharCode(parseInt(oct, 8)));
    const fstype = parts[2];
    let cmp;
    try { cmp = fs.realpathSync(mp); } catch { cmp = mp; }
    if (target === cmp || target.startsWith(cmp + path.sep)) {
      if (!best || cmp.length > best.mount.length) best = { mount: cmp, fstype };
    }
  }
  if (best != null && REFUSE_NETWORK_FS_TYPES.has(best.fstype)) {
    return {
      ok: false, status: 'refused', reason: 'network-store', mount: best.mount, fstype: best.fstype, path: target,
      guidance: guidanceFor('auto.cli.on.nfsAdvisory', { fstype: best.fstype, mount: best.mount }),
    };
  }
  return { ok: true };
}

// ---- shared writer plumbing ----

// Mutate the loaded store under fn, persist atomically. The whole
// read-modify-write runs under the cross-process mutation mutex: concurrent
// writers serialize (no lost update), and a mutex held past the bounded
// spin fails closed as store-busy instead of resolving by last-writer-wins.
// Reentrant within one process — nested mutates join the outer critical
// section. A stale mutex is reclaimed only on provable holder identity
// (dead pid, changed boot_id, or a recycled pid caught by starttime); the
// reclaim is audited as a takeover breaker record.
function mutate(rootDir, fn, opts = {}) {
  const file = storeFile(rootDir);
  if (file == null) return paused('unwritable', null, 'no XDG data home resolvable', 'auto.store.unwritable');
  if (!fs.existsSync(file)) return load(rootDir);
  const nested = _mutateDepth > 0;
  let acquired = null;
  if (!nested) {
    acquired = acquireMutateLock(rootDir, opts);
    if (!acquired.ok) return acquired;
    _mutateDepth += 1;
  }
  try {
    const cur = load(rootDir);
    if (!cur.ok) return cur;
    // Pre-fn snapshot on the reclaim path only: a refused mutation must
    // never persist caller changes made before the null return.
    const auditText = acquired && acquired.takeover ? JSON.stringify(cur.store) : null;
    let next = fn(cur.store);
    if (next == null) {
      if (auditText != null) persistTakeoverAudit(cur.path, auditText, acquired.takeover);
      return { ok: false, status: 'error', reason: 'rejected', path: cur.path };
    }
    if (auditText != null) {
      const records = isPlainObject(next.breaker) && Array.isArray(next.breaker.records) ? next.breaker.records : null;
      if (records) next.breaker.records = trimArray([...records, { cls: 'takeover', ts: new Date().toISOString(), detail: acquired.takeover }], CAPS.breakerRecords);
    }
    try { core.writeAtomicJson(cur.path, next); }
    catch (e) {
      return { ok: false, status: 'error', reason: 'write-failed', path: cur.path, detail: e.message, guidance: guidanceFor('auto.store.unwritable', { path: cur.path }) };
    }
    return { ok: true, path: cur.path, store: next };
  } finally {
    if (!nested) {
      _mutateDepth -= 1;
      releaseMutateLock();
    }
  }
}

// Persist the takeover audit alone when the caller's mutation was refused —
// the reclaim is an audit fact independent of the refused change.
function persistTakeoverAudit(storeFilePath, auditText, detail) {
  try {
    const st = JSON.parse(auditText);
    if (isPlainObject(st.breaker) && Array.isArray(st.breaker.records)) {
      st.breaker.records = trimArray([...st.breaker.records, { cls: 'takeover', ts: new Date().toISOString(), detail }], CAPS.breakerRecords);
      core.writeAtomicJson(storeFilePath, st);
    }
  } catch { /* audit best-effort */ }
}

function trimArray(arr, cap) {
  return arr.length > cap ? arr.slice(arr.length - cap) : arr;
}

function mirrorsOf(st) {
  return { spawnCount: st.counters.spawnCount, tripCount: st.counters.tripCount };
}

// ---- record API ----

// Stamp the captured-stream hash for one spawn. One spawnId stamps once:
// an identical re-stamp is idempotent, a conflicting one is refused (the
// pairing between spawn and stream hash must not be rewritable).
function stampStream(spawnId, stage, streamSha256, spawnedAtIso, rootDir) {
  if (typeof spawnId !== 'string' || !spawnId) return { ok: false, status: 'error', reason: 'invalid-spawn-id' };
  if (typeof stage !== 'string' || !stage) return { ok: false, status: 'error', reason: 'invalid-stage' };
  if (typeof streamSha256 !== 'string' || !/^[0-9a-f]{64}$/.test(streamSha256)) return { ok: false, status: 'error', reason: 'invalid-stream-sha256' };
  if (typeof spawnedAtIso !== 'string' || !ISO_RE.test(spawnedAtIso)) return { ok: false, status: 'error', reason: 'invalid-spawned-at' };
  let conflict = false;
  const r = mutate(rootDir, (st) => {
    const prev = st.stamps[spawnId];
    if (prev && prev.streamSha256 !== streamSha256) { conflict = true; return null; }
    st.stamps[spawnId] = { stage, streamSha256, spawnedAtIso, stampedAtIso: new Date().toISOString() };
    const keys = Object.keys(st.stamps);
    if (keys.length > CAPS.stamps) {
      keys.sort((a, b) => st.stamps[a].stampedAtIso.localeCompare(st.stamps[b].stampedAtIso));
      for (const k of keys.slice(0, keys.length - CAPS.stamps)) delete st.stamps[k];
    }
    return st;
  });
  if (conflict) return { ok: false, status: 'error', reason: 'stamp-conflict', path: r.path };
  return r.ok ? { ok: true, path: r.path, stamp: r.store.stamps[spawnId] } : r;
}

// Human dispositions (red runs, unknown-state CI) live here — the repo
// ledger mirrors only their hashes.

// Review-round evidence: the full text tail of a red-team round (bounded),
// kept machine-local so a held delegation is decidable by a human reading
// what the reviewer actually wrote.
function recordReviewRound({ spawnId, stage, findings, classified, text }, rootDir) {
  if (typeof spawnId !== 'string' || !spawnId) return { ok: false, status: 'error', reason: 'invalid-spawn-id' };
  if (typeof stage !== 'string' || !stage) return { ok: false, status: 'error', reason: 'invalid-stage' };
  const bounded = typeof text === 'string' ? text.slice(-8192) : '';
  const conflict = false;
  const r = mutate(rootDir, (st) => {
    if (!isPlainObject(st.reviewRounds)) st.reviewRounds = {};
    st.reviewRounds[spawnId] = {
      stage, findings: findings == null ? null : Number(findings), classified: String(classified || ''),
      text: bounded, ts: new Date().toISOString(),
    };
    const keys = Object.keys(st.reviewRounds);
    if (keys.length > CAPS.stamps) {
      keys.sort((a, b) => st.reviewRounds[a].ts.localeCompare(st.reviewRounds[b].ts));
      for (const k of keys.slice(0, keys.length - CAPS.stamps)) delete st.reviewRounds[k];
    }
    return st;
  });
  if (conflict) return { ok: false, status: 'error', reason: 'stamp-conflict', path: r.path };
  return r.ok ? { ok: true, path: r.path, record: r.store.reviewRounds[spawnId] } : r;
}
function recordDisposition(d, rootDir) {
  if (!isPlainObject(d)) return { ok: false, status: 'error', reason: 'invalid-disposition' };
  if (typeof d.runId !== 'string' || !d.runId) return { ok: false, status: 'error', reason: 'invalid-disposition', detail: 'runId required' };
  if (typeof d.ts !== 'string' || !ISO_RE.test(d.ts)) return { ok: false, status: 'error', reason: 'invalid-disposition', detail: 'ts ISO string required' };
  if (typeof d.reason !== 'string' || !d.reason) return { ok: false, status: 'error', reason: 'invalid-disposition', detail: 'reason required' };
  if (typeof d.by !== 'string' || !d.by) return { ok: false, status: 'error', reason: 'invalid-disposition', detail: 'by required' };
  const r = mutate(rootDir, (st) => {
    st.dispositions = trimArray([...st.dispositions, { runId: d.runId, ts: d.ts, reason: d.reason, by: d.by }], CAPS.dispositions);
    return st;
  });
  return r.ok ? { ok: true, path: r.path, disposition: r.store.dispositions[r.store.dispositions.length - 1] } : r;
}

// Runner-held snapshots (deny baseline, host seed, redteam prompt, PR
// template): content stored verbatim with its sha256 so later verification
// can prove the sandbox saw exactly this baseline. Refresh overwrites.
function saveSnapshot(kind, content, rootDir) {
  if (!SNAPSHOT_KINDS.has(kind)) return { ok: false, status: 'error', reason: 'invalid-snapshot-kind', detail: `kind must be one of ${[...SNAPSHOT_KINDS].join('|')}` };
  if (typeof content !== 'string') return { ok: false, status: 'error', reason: 'invalid-snapshot-content' };
  const sha256 = crypto.createHash('sha256').update(content).digest('hex');
  const r = mutate(rootDir, (st) => {
    st.snapshots[kind] = { content, sha256, savedAtIso: new Date().toISOString() };
    return st;
  });
  return r.ok ? { ok: true, path: r.path, snapshot: r.store.snapshots[kind] } : r;
}

// Host/adapter probe outcomes — latest entry per host is the status source.
function saveProbeResult(p, rootDir) {
  if (!isPlainObject(p)) return { ok: false, status: 'error', reason: 'invalid-probe-result' };
  if (typeof p.host !== 'string' || !p.host) return { ok: false, status: 'error', reason: 'invalid-probe-result', detail: 'host required' };
  if (typeof p.state !== 'string' || !p.state) return { ok: false, status: 'error', reason: 'invalid-probe-result', detail: 'state required' };
  if (typeof p.checkedAtIso !== 'string' || !ISO_RE.test(p.checkedAtIso)) return { ok: false, status: 'error', reason: 'invalid-probe-result', detail: 'checkedAtIso ISO string required' };
  const r = mutate(rootDir, (st) => {
    st.probeResults = trimArray([...st.probeResults, { host: p.host, state: p.state, checkedAtIso: p.checkedAtIso }], CAPS.probeResults);
    return st;
  });
  return r.ok ? { ok: true, path: r.path, result: r.store.probeResults[r.store.probeResults.length - 1] } : r;
}

// ---- counters + breaker records ----

// Cumulative spawn counter; the returned mirrors are what the caller
// persists into tracked repo state (counts are clone-safe, detail is not).
function bumpSpawn(rootDir, opts) {
  const r = mutate(rootDir, (st) => {
    st.counters.spawnCount += 1;
    return st;
  }, opts);
  return r.ok ? { ok: true, path: r.path, mirrors: mirrorsOf(r.store) } : r;
}

// Append a breaker record without touching counters (takeover events use
// this; loop failures use recordTrip).
function recordBreaker(rec, rootDir) {
  if (!isPlainObject(rec) || !BREAKER_CLASSES.has(rec.cls)) {
    return { ok: false, status: 'error', reason: 'invalid-breaker-class', detail: `cls must be one of ${[...BREAKER_CLASSES].join('|')}` };
  }
  if (rec.layer != null && !TRIP_LAYERS.has(rec.layer)) {
    return { ok: false, status: 'error', reason: 'invalid-breaker-layer', detail: 'layer must be one of N|K|B or absent' };
  }
  const r = mutate(rootDir, (st) => {
    const entry = { cls: rec.cls, ts: new Date().toISOString() };
    if (rec.layer != null) entry.layer = rec.layer;
    if (typeof rec.detail === 'string' && rec.detail) entry.detail = rec.detail;
    st.breaker.records = trimArray([...st.breaker.records, entry], CAPS.breakerRecords);
    return st;
  });
  return r.ok ? { ok: true, path: r.path, record: r.store.breaker.records[r.store.breaker.records.length - 1] } : r;
}

// A breaker layer trip: appends the record and bumps the cumulative trip
// counter. Layer N/K/B and a loop failure class are both required.
function recordTrip(rec, rootDir) {
  if (!isPlainObject(rec) || !TRIP_LAYERS.has(rec.layer)) {
    return { ok: false, status: 'error', reason: 'invalid-trip-layer', detail: 'layer must be one of N|K|B' };
  }
  if (!TRIP_CLASSES.has(rec.cls)) {
    return { ok: false, status: 'error', reason: 'invalid-trip-class', detail: `cls must be one of ${[...TRIP_CLASSES].join('|')}` };
  }
  const r = mutate(rootDir, (st) => {
    const entry = { layer: rec.layer, cls: rec.cls, ts: new Date().toISOString() };
    if (typeof rec.detail === 'string' && rec.detail) entry.detail = rec.detail;
    st.breaker.records = trimArray([...st.breaker.records, entry], CAPS.breakerRecords);
    st.counters.tripCount += 1;
    return st;
  });
  if (!r.ok) return r;
  return { ok: true, path: r.path, mirrors: mirrorsOf(r.store), record: r.store.breaker.records[r.store.breaker.records.length - 1] };
}

// Read-only mirror snapshot for tracked-state persistence.
function mirrors(rootDir) {
  const cur = load(rootDir);
  return cur.ok ? { ok: true, ...mirrorsOf(cur.store) } : { ok: false, ...cur };
}

// ---- run-lock family ----

// Linux boot identifier disambiguates pid reuse across reboots: a holder
// that recorded a different boot_id cannot still be alive, whatever pid
// signals now claim. Null where unavailable.
function readBootId() {
  try { return fs.readFileSync('/proc/sys/kernel/random/boot_id', 'utf8').trim(); } catch { return null; }
}

function livePid(pid) {
  const n = Number(pid);
  return Number.isInteger(n) && n > 0 ? core.pidAlive(n) : false;
}

function lockPath(rootDir) {
  const root = storeRoot(rootDir);
  return root == null ? null : path.join(root, RUN_LOCK_FILE);
}

function readLockFile(lp) {
  if (!fs.existsSync(lp)) return null;
  try { return JSON.parse(fs.readFileSync(lp, 'utf8')); }
  catch { return null; } // unreadable lock = unproven ownership
}

let _lockHeldPath = null;

// Effective heartbeat staleness threshold: never below the fixed floor, and
// raised to wallTimeout + margin whenever a configured wall timeout (store
// config, then the env override, via the breaker's policy resolution) could
// let a legal spawn outlast the floor. Function-level require: breaker.cjs
// loads this module first, so a top-level require would see partial exports.
function heartbeatStaleThresholdMs(rootDir) {
  const breaker = require('./breaker.cjs');
  const loaded = load(rootDir);
  const defaults = loaded.ok && isPlainObject(loaded.store.timeouts) ? loaded.store.timeouts : undefined;
  const tp = breaker.timeoutPolicy(process.env, defaults);
  const wallMs = (tp.ok ? tp.wallSec : breaker.DEFAULT_WALL_SEC) * 1000;
  return Math.max(LOCK_HEARTBEAT_STALE_MS, wallMs + LOCK_HEARTBEAT_MARGIN_MS);
}

function lockHeartbeatStale(rec, lp, rootDir) {
  const threshold = heartbeatStaleThresholdMs(rootDir);
  if (typeof rec.heartbeat_at === 'string' && ISO_RE.test(rec.heartbeat_at)) {
    return Date.now() - Date.parse(rec.heartbeat_at) > threshold;
  }
  try { return Date.now() - fs.statSync(lp).mtimeMs > threshold; }
  catch { return true; }
}

// Exclusive run lock. Refusals name the holder (cross-host refusals name
// the owning clone — this machine cannot judge a remote pid). Recovery:
// dead pid (same host or different boot_id) auto-recovers; ambiguous
// live-pid-but-stale-heartbeat requires an explicit break.
function acquireRunLock(opts = {}) {
  const breakLock = opts.breakLock === true;
  if (_lockHeldPath) return { ok: true, reentrant: true, path: _lockHeldPath };
  const lp = lockPath(opts.rootDir);
  if (lp == null) return paused('unwritable', null, 'no XDG data home resolvable', 'auto.store.unwritable');
  try { fs.mkdirSync(path.dirname(lp), { recursive: true }); }
  catch (e) { return { ok: false, status: 'error', reason: 'unwritable', path: lp, detail: e.message, guidance: guidanceFor('auto.store.unwritable', { path: lp }) }; }
  if (fs.existsSync(lp)) {
    const rec = readLockFile(lp);
    let remove = false;
    if (rec == null) {
      console.error(`⚠ auto run lock unreadable (${lp}) — auto-recovered`);
      remove = true;
    } else {
      const sameHost = rec.hostname === os.hostname();
      const myBoot = readBootId();
      const bootChanged = sameHost && myBoot != null && rec.boot_id != null && rec.boot_id !== myBoot;
      if (!sameHost) {
        if (!breakLock) {
          return {
            ok: false, status: 'refused', reason: 'cross-host', holder: rec, path: lp,
            guidance: guidanceFor('auto.store.lockCrossHost', { hostname: rec.hostname, clone: rec.clone_path }),
          };
        }
        recordBreaker({ cls: 'takeover', detail: `cross-host break of lock held by ${rec.hostname} (${rec.clone_path})` }, opts.rootDir);
        remove = true;
      } else if (bootChanged || !livePid(rec.pid)) {
        console.error(`⚠ stale auto run lock (pid ${rec.pid} not running) — auto-recovered`);
        remove = true;
      } else {
        const stale = lockHeartbeatStale(rec, lp, opts.rootDir);
        if (!stale || !breakLock) {
          return {
            ok: false, status: 'refused', reason: stale ? 'heartbeat-stale' : 'live', holder: rec, path: lp,
            guidance: guidanceFor(stale ? 'auto.store.lockHeartbeatStale' : 'auto.store.lockHeld', { pid: rec.pid, since: rec.started_at }),
          };
        }
        recordBreaker({ cls: 'takeover', detail: `heartbeat-stale break of lock held by pid ${rec.pid}` }, opts.rootDir);
        remove = true;
      }
    }
    if (remove) { try { fs.unlinkSync(lp); } catch { /* racing */ } }
  }
  const record = {
    hostname: os.hostname(),
    pid: process.pid,
    boot_id: readBootId(),
    clone_path: core.currentRootRealpath() || process.cwd(),
    started_at: new Date().toISOString(),
    heartbeat_at: new Date().toISOString(),
  };
  let fd;
  try { fd = fs.openSync(lp, 'wx'); }
  catch (e) {
    const holder = readLockFile(lp);
    return {
      ok: false, status: 'refused', reason: 'race', holder, path: lp, detail: e.message,
      guidance: guidanceFor('auto.store.lockHeld', { pid: holder && holder.pid, since: holder && holder.started_at }),
    };
  }
  try { fs.writeSync(fd, JSON.stringify(record)); } finally { fs.closeSync(fd); }
  _lockHeldPath = lp;
  process.on('exit', () => {
    if (_lockHeldPath !== lp) return;
    const cur = readLockFile(lp);
    if (cur && cur.pid === process.pid && cur.hostname === os.hostname()) {
      try { fs.unlinkSync(lp); } catch { /* gone */ }
    }
  });
  return { ok: true, path: lp, lock: record };
}

// Refresh the heartbeat of OUR lock (long spawn waits and CI watches must
// not let a healthy runner look stale). The write goes through the same
// atomic writer the rest of the store uses: a torn direct write would read
// as unreadable, unproven ownership, and a reclaimable live lock.
function heartbeatRunLock(rootDir) {
  const lp = lockPath(rootDir);
  if (lp == null || !fs.existsSync(lp)) return { ok: false, status: 'error', reason: 'no-lock' };
  const rec = readLockFile(lp);
  if (!rec || rec.pid !== process.pid || rec.hostname !== os.hostname()) {
    return { ok: false, status: 'error', reason: 'not-owner' };
  }
  rec.heartbeat_at = new Date().toISOString();
  try { core.writeAtomicJson(lp, rec); }
  catch (e) {
    return { ok: false, status: 'error', reason: 'write-failed', detail: e.message };
  }
  return { ok: true, path: lp };
}

// Release our lock (runner exit). Foreign locks are never released here.
function releaseRunLock(rootDir) {
  const lp = lockPath(rootDir);
  if (lp == null || !fs.existsSync(lp)) { _lockHeldPath = null; return { ok: true, absent: true }; }
  const rec = readLockFile(lp);
  if (!rec || rec.pid !== process.pid || rec.hostname !== os.hostname()) {
    return { ok: false, status: 'error', reason: 'not-owner', holder: rec, path: lp };
  }
  try { fs.unlinkSync(lp); } catch { /* gone */ }
  _lockHeldPath = null;
  return { ok: true };
}

// Parsed lock record or null (absent/unreadable) — status surfaces use this.
function readRunLock(rootDir) {
  const lp = lockPath(rootDir);
  return lp == null ? null : readLockFile(lp);
}

// Explicit break (`--break-lock`). A live pid on a matching hostname is
// NEVER breakable — the refusal stands and the attempt is recorded as a
// takeover breaker event. Cross-host locks are always breakable (this
// machine cannot verify a remote pid; the owning clone is named in the
// acquire refusal).
function breakRunLock(rootDir) {
  const lp = lockPath(rootDir);
  if (lp == null) return paused('unwritable', null, 'no XDG data home resolvable', 'auto.store.unwritable');
  if (!fs.existsSync(lp)) return { ok: true, absent: true };
  const rec = readLockFile(lp);
  if (rec == null) {
    // unreadable lock has no proven owner — breakable, still audited
    recordBreaker({ cls: 'takeover', detail: `break of unreadable lock at ${lp}` }, rootDir);
    try { fs.unlinkSync(lp); } catch { /* gone */ }
    return { ok: true, broke: 'unreadable' };
  }
  const sameHost = rec.hostname === os.hostname();
  if (sameHost) {
    const myBoot = readBootId();
    const bootChanged = myBoot != null && rec.boot_id != null && rec.boot_id !== myBoot;
    const live = livePid(rec.pid) && !bootChanged;
    if (live && !lockHeartbeatStale(rec, lp, rootDir)) {
      const rec2 = recordBreaker({ cls: 'takeover', detail: `refused --break-lock: pid ${rec.pid} live on ${rec.hostname}` }, rootDir);
      return {
        ok: false, refused: true, holder: rec, path: lp, recorded: !!(rec2 && rec2.ok),
        guidance: guidanceFor('auto.store.lockBreakRefused', { pid: rec.pid, hostname: rec.hostname }),
      };
    }
  }
  const why = sameHost ? 'stale' : 'cross-host';
  recordBreaker({ cls: 'takeover', detail: `${why} break of lock held by ${rec.hostname} pid ${rec.pid} (${rec.clone_path})` }, rootDir);
  try { fs.unlinkSync(lp); } catch { /* gone */ }
  return { ok: true, broke: why };
}

// ---- teardown ----

// Remove this repo's store (`auto off --purge`). Only the per-repo directory
// under the gos data root is ever removed; a guard re-checks the resolved
// path so an env override can never aim the rm elsewhere.
function purgeStore(rootDir) {
  const root = storeRoot(rootDir);
  if (root == null) return { ok: false, status: 'error', reason: 'no-data-home' };
  const home = dataHome();
  const resolved = path.resolve(root);
  if (!home || !resolved.startsWith(path.resolve(home, 'gos') + path.sep)) {
    return { ok: false, status: 'error', reason: 'outside-store-root', detail: resolved };
  }
  if (_lockHeldPath) releaseRunLock(rootDir);
  if (!fs.existsSync(resolved)) return { ok: true, removed: false };
  try { fs.rmSync(resolved, { recursive: true, force: true }); }
  catch (e) { return { ok: false, status: 'error', reason: 'remove-failed', detail: e.message }; }
  return { ok: true, removed: true, path: resolved };
}

module.exports = {
  STORE_SCHEMA_VERSION,
  DEFAULT_LIMITS: limits.DEFAULT_LIMITS,
  storeRoot,
  repoKey,
  guidanceFor,
  isPlainObject,
  sha256Of,
  load,
  create,
  probeWritable,
  networkFsUnderStore,
  refuseNetworkStore,
  mutateLockPath,
  acquireMutateLock,
  releaseMutateLock,
  heartbeatStaleThresholdMs,
  stampStream,
  recordReviewRound,
  recordDisposition,
  saveSnapshot,
  saveProbeResult,
  bumpSpawn,
  recordTrip,
  recordBreaker,
  mirrors,
  acquireRunLock,
  heartbeatRunLock,
  releaseRunLock,
  readRunLock,
  breakRunLock,
  purgeStore,
};
