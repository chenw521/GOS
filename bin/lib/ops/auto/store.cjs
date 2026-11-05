// ops/auto/store — machine-local runner trust store, external to every
// spawned sandbox: schema-versioned records for the auto loop (mode/profile/
// limits, cumulative counters, breaker records, stream stamps with their
// window sidecars, dispositions, runner-held snapshots, probe results) plus
// the exclusive run-lock family.
//
// Load semantics are fail-closed by construction: a missing, corrupt, or
// future-versioned store NEVER yields a fresh writable store — the loader
// returns a paused result with guidance, and only `create` (the `auto on`
// path) may lay down a fresh store, warning when tracked mirror counters
// imply prior history. The repo-local ledger mirror is never a read source
// here; this store is the single trust input. Older on-disk schemas load
// with an in-memory migration (never written by a pure read; the next
// mutate persists the migrated shape).
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const core = require('../../core/index.cjs');
const spawnreg = require('../../core/spawnreg.cjs');
const limits = require('./limits.cjs');
const workers = require('./workers.cjs');

const STORE_SCHEMA_VERSION = 2;

const STORE_FILE = 'store.json';

// Stamp telemetry fields: self-reported model fields and runner counts are
// advisory by contract (stored verbatim, never used to gate a disposition);
// the window hashes and byte totals describe the retained sidecar pair.
const STAMP_TEXT_FIELDS = ['modelPinned', 'modelObserved'];
const STAMP_HASH_FIELDS = ['headSha256', 'tailSha256'];
const STAMP_COUNT_FIELDS = ['commandCount', 'totalBytes', 'denyHits', 'denyCommandHits'];
const HEX64_RE = /^[0-9a-f]{64}$/;

// Window sidecars: one directory under the store dir holding a head/tail
// text pair per stamped spawn, named by spawnId. The pair count is bounded
// by the stamp cap — pruned with its stamp, orphans swept at every prune.
const WINDOWS_DIR = 'windows';
const SPAWN_ID_FILE_RE = /^[A-Za-z\d][A-Za-z\d._-]*$/;
const SIDECAR_RE = /^([A-Za-z\d][A-Za-z\d._-]*)\.(head|tail)\.txt$/;

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

const SNAPSHOT_KINDS = new Set(['denyBaseline', 'hostSeed', 'redteamPrompt', 'prTemplate', 'wavePrompt']);

// Pinned worktrees (Class P legs): run tags and record bounds. Records map
// a filename-safe run tag to the worktree's absolute path, its tree hash,
// the loop-start commit it pins, and the creation time (lazy recycles drop
// pins whose run tag is not live).
const PIN_RUN_TAG_RE = /^[A-Za-z\d][A-Za-z\d._-]*$/;
const GIT_SHA_RE = /^[0-9a-f]{7,64}$/;
const PIN_DIR_NAME = 'pin-worktrees';

// Wave completion records: one key per task wave ('<task>/W<n>', task id
// filename-safe, wave digits only from 1). Values carry the wave's commit
// head, the sha256 of the post-wave refs snapshot (for-each-ref + reflog
// head text), release time, and the optional no-op / table-roll markers.
const WAVE_KEY_RE = /^[A-Za-z\d][A-Za-z\d._-]*\/W[1-9][0-9]*$/;
// Run-start dispatch-table stamp provenance: '<runTag>/start' where runTag
// is the loop's filename-safe run tag (never a wave — a run start releases
// nothing, it only pins what the run loaded).
const RUN_START_KEY_RE = /^[A-Za-z\d][A-Za-z\d._-]*\/start$/;

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

// Optional stamp telemetry: absent or well-typed. A wrong-typed count or a
// malformed hash is structural damage, so the store reads as corrupt.
function stampTelemetryWellTyped(s) {
  for (const f of STAMP_TEXT_FIELDS) if (s[f] != null && typeof s[f] !== 'string') return false;
  for (const f of STAMP_HASH_FIELDS) if (s[f] != null && (typeof s[f] !== 'string' || !HEX64_RE.test(s[f]))) return false;
  for (const f of STAMP_COUNT_FIELDS) if (s[f] != null && !nonNegInt(s[f])) return false;
  return true;
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
  else if (!Object.values(st.stamps).every((v) => isPlainObject(v) && typeof v.streamSha256 === 'string' && HEX64_RE.test(v.streamSha256))) {
    errs.push('stamps: values need hex64 streamSha256');
  }
  else if (!Object.values(st.stamps).every(stampTelemetryWellTyped)) {
    errs.push('stamps: telemetry fields must be absent or well-typed (string, hex64, integer >= 0)');
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
  // Optional pinWorktrees key (additive): absent on older stores, but a
  // present-but-malformed one is structural damage.
  if (st.pinWorktrees != null) {
    if (!isPlainObject(st.pinWorktrees)) errs.push('pinWorktrees: object required');
    else {
      for (const tag of Object.keys(st.pinWorktrees)) {
        const v = st.pinWorktrees[tag];
        if (!PIN_RUN_TAG_RE.test(tag) || !isPlainObject(v)
          || typeof v.path !== 'string' || !path.isAbsolute(v.path)
          || typeof v.treeSha !== 'string' || !GIT_SHA_RE.test(v.treeSha)
          || typeof v.loopStartCommit !== 'string' || !GIT_SHA_RE.test(v.loopStartCommit)
          || typeof v.createdAtIso !== 'string' || !ISO_RE.test(v.createdAtIso)) {
          errs.push(`pinWorktrees: entry ${tag} needs absolute path, hex treeSha + loopStartCommit, ISO createdAtIso`);
          break;
        }
      }
    }
  }
  // Optional wave completion records (additive): absent on older stores,
  // present-but-malformed is structural damage.
  if (st.waves != null) {
    if (!isPlainObject(st.waves)) errs.push('waves: object required');
    else {
      for (const k of Object.keys(st.waves)) {
        const v = st.waves[k];
        if (!WAVE_KEY_RE.test(k) || !isPlainObject(v)
          || typeof v.head !== 'string' || !GIT_SHA_RE.test(v.head)
          || typeof v.refsPointer !== 'string' || !HEX64_RE.test(v.refsPointer)
          || typeof v.releasedAtIso !== 'string' || !ISO_RE.test(v.releasedAtIso)
          || (v.noop != null && typeof v.noop !== 'boolean')
          || (v.noopReason != null && typeof v.noopReason !== 'string')
          || (v.rolledTable != null && typeof v.rolledTable !== 'boolean')) {
          errs.push(`waves: entry ${k} needs git head, hex64 refsPointer, ISO releasedAtIso, boolean noop/rolledTable`);
          break;
        }
      }
    }
  }
  // Optional wave start records (additive): runner-written pre-spawn evidence
  // for the crash-recovery window — never read from the spawn-writable
  // scratch.
  if (st.waveStarts != null) {
    if (!isPlainObject(st.waveStarts)) errs.push('waveStarts: object required');
    else {
      for (const k of Object.keys(st.waveStarts)) {
        const v = st.waveStarts[k];
        if (!WAVE_KEY_RE.test(k) || !isPlainObject(v)
          || typeof v.spawnId !== 'string' || !SPAWN_ID_FILE_RE.test(v.spawnId)
          || typeof v.preHead !== 'string' || !GIT_SHA_RE.test(v.preHead)
          || typeof v.preRefsText !== 'string'
          || !Array.isArray(v.preDirty) || !v.preDirty.every((p) => typeof p === 'string')
          || typeof v.startedAtIso !== 'string' || !ISO_RE.test(v.startedAtIso)) {
          errs.push(`waveStarts: entry ${k} needs filename-safe spawnId, git preHead, string preRefsText, string[] preDirty, ISO startedAtIso`);
          break;
        }
      }
    }
  }
  // Optional held-wave records (additive): a held wave is a runner verdict,
  // never a crash — reconcile must be able to tell them apart.
  if (st.heldWaves != null) {
    if (!isPlainObject(st.heldWaves)) errs.push('heldWaves: object required');
    else {
      for (const k of Object.keys(st.heldWaves)) {
        const v = st.heldWaves[k];
        if (!WAVE_KEY_RE.test(k) || !isPlainObject(v)
          || typeof v.reason !== 'string' || !v.reason
          || typeof v.spawnId !== 'string' || !SPAWN_ID_FILE_RE.test(v.spawnId)
          || typeof v.heldAtIso !== 'string' || !ISO_RE.test(v.heldAtIso)) {
          errs.push(`heldWaves: entry ${k} needs non-empty reason, filename-safe spawnId, ISO heldAtIso`);
          break;
        }
      }
    }
  }
  // Optional dispatch-table stamp (additive): the sha256 of the dispatch
  // table file as of the last runner-released edit, plus when/by-whom.
  if (st.dispatchTable != null) {
    if (!isPlainObject(st.dispatchTable)
      || typeof st.dispatchTable.sha256 !== 'string' || !HEX64_RE.test(st.dispatchTable.sha256)
      || typeof st.dispatchTable.rolledAtIso !== 'string' || !ISO_RE.test(st.dispatchTable.rolledAtIso)
      || typeof st.dispatchTable.rolledByWave !== 'string' || !st.dispatchTable.rolledByWave) {
      errs.push('dispatchTable: hex64 sha256 + ISO rolledAtIso + non-empty rolledByWave required');
    }
  }
  // Optional baseline-state record (additive): the sha256 of the state file
  // bytes as the loop last read and validated them — the crashed-advance
  // recovery gate against crafted spawn-writable snapshots.
  if (st.baselineState != null) {
    if (!isPlainObject(st.baselineState)
      || typeof st.baselineState.sha256 !== 'string' || !HEX64_RE.test(st.baselineState.sha256)
      || typeof st.baselineState.recordedAtIso !== 'string' || !ISO_RE.test(st.baselineState.recordedAtIso)) {
      errs.push('baselineState: hex64 sha256 + ISO recordedAtIso required');
    }
  }
  return errs;
}

// ---- load / create ----

function paused(reason, file, detail, localeKey, params) {
  const out = { ok: false, status: 'paused', reason, path: file, guidance: guidanceFor(localeKey, params) };
  if (detail) out.detail = detail;
  return out;
}

// In-memory v1 -> v2 migration: every stamp gains the telemetry fields at
// their absent-value defaults and the version bumps to the known schema.
// Pure — load never writes; the migrated shape persists lazily on the next
// mutate (which loads through this same normalization before its fn runs).
function normalizeStampsToV2(st) {
  for (const s of Object.values(st.stamps)) {
    for (const f of [...STAMP_TEXT_FIELDS, ...STAMP_HASH_FIELDS]) if (s[f] == null) s[f] = null;
    for (const f of STAMP_COUNT_FIELDS) if (s[f] == null) s[f] = 0;
  }
  st.store_schema_version = STORE_SCHEMA_VERSION;
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
  if (st.store_schema_version < 1) {
    return paused('version-mismatch', file, `store at older schema v${st.store_schema_version}`, 'auto.store.versionMismatch', { found: st.store_schema_version, known: STORE_SCHEMA_VERSION });
  }
  if (st.store_schema_version === 1) {
    normalizeStampsToV2(st);
    return { ok: true, status: 'ok', path: file, store: st, migrated: true };
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

// Stamp the captured-stream hash for one spawn, optionally with runner
// telemetry (self-reported model fields, command count, deny hits, window
// hashes, byte totals — all advisory). One spawnId stamps once: an
// identical re-stamp refreshes, a conflicting one is refused (the pairing
// between spawn and stream hash must not be rewritable).
function stampStream(spawnId, stage, streamSha256, spawnedAtIso, rootDir, telemetry) {
  if (typeof spawnId !== 'string' || !spawnId) return { ok: false, status: 'error', reason: 'invalid-spawn-id' };
  if (typeof stage !== 'string' || !stage) return { ok: false, status: 'error', reason: 'invalid-stage' };
  if (typeof streamSha256 !== 'string' || !HEX64_RE.test(streamSha256)) return { ok: false, status: 'error', reason: 'invalid-stream-sha256' };
  if (typeof spawnedAtIso !== 'string' || !ISO_RE.test(spawnedAtIso)) return { ok: false, status: 'error', reason: 'invalid-spawned-at' };
  const tel = telemetry == null ? {} : telemetry;
  if (!isPlainObject(tel)) return { ok: false, status: 'error', reason: 'invalid-telemetry', detail: 'telemetry must be an object' };
  if (!stampTelemetryWellTyped(tel)) {
    return { ok: false, status: 'error', reason: 'invalid-telemetry', detail: 'fields must be string, hex64, or integer >= 0' };
  }
  let conflict = false;
  const r = mutate(rootDir, (st) => {
    const prev = st.stamps[spawnId];
    if (prev && prev.streamSha256 !== streamSha256) { conflict = true; return null; }
    st.stamps[spawnId] = stampEntry(stage, streamSha256, spawnedAtIso, tel, prev);
    pruneStamps(st, rootDir);
    return st;
  });
  if (conflict) return { ok: false, status: 'error', reason: 'stamp-conflict', path: r.path };
  return r.ok ? { ok: true, path: r.path, stamp: r.store.stamps[spawnId] } : r;
}

// Full v2 stamp: legacy fields plus telemetry, absent telemetry normalized
// to null/0 so every consumer reads one shape. An identical re-stamp keeps
// the prior telemetry values it is not re-handed (window hashes survive a
// saveWindows-then-restamp sequence instead of resetting).
function stampEntry(stage, streamSha256, spawnedAtIso, tel, prev) {
  const src = prev != null ? prev : {};
  const s = { stage, streamSha256, spawnedAtIso, stampedAtIso: new Date().toISOString() };
  for (const f of [...STAMP_TEXT_FIELDS, ...STAMP_HASH_FIELDS]) s[f] = tel[f] != null ? tel[f] : (src[f] != null ? src[f] : null);
  for (const f of STAMP_COUNT_FIELDS) s[f] = tel[f] != null ? tel[f] : (src[f] != null ? src[f] : 0);
  return s;
}

// Stamp-cap pruning: oldest stamps drop past the cap, their window sidecar
// files die with them, and a sweep removes sidecars whose stamp no longer
// exists (crash leftovers, restored stores). File hygiene is best-effort —
// a failed unlink never fails the mutation.
function pruneStamps(st, rootDir) {
  const keys = Object.keys(st.stamps);
  if (keys.length <= CAPS.stamps) return;
  keys.sort((a, b) => st.stamps[a].stampedAtIso.localeCompare(st.stamps[b].stampedAtIso));
  const dropped = keys.slice(0, keys.length - CAPS.stamps);
  for (const k of dropped) delete st.stamps[k];
  const dir = windowsDirOf(rootDir);
  if (dir == null) return;
  for (const k of dropped) unlinkSidecarPair(dir, k);
  sweepOrphanSidecars(dir, st.stamps);
}

// ---- window sidecars ----

function windowsDirOf(rootDir) {
  const root = storeRoot(rootDir);
  return root == null ? null : path.join(root, WINDOWS_DIR);
}

function unlinkSidecarPair(dir, spawnId) {
  for (const suffix of ['head', 'tail']) {
    try { fs.unlinkSync(path.join(dir, `${spawnId}.${suffix}.txt`)); } catch { /* gone */ }
  }
}

function sweepOrphanSidecars(dir, stamps) {
  let names;
  try { names = fs.readdirSync(dir); } catch { return; }
  for (const name of names) {
    const m = SIDECAR_RE.exec(name);
    if (m && !Object.prototype.hasOwnProperty.call(stamps, m[1])) {
      try { fs.unlinkSync(path.join(dir, name)); } catch { /* gone */ }
    }
  }
}

// Persist the retained dual-window capture for one stamped spawn: a head
// and a tail sidecar file under the store dir, plus the stamp's window
// hashes and the retained byte total (exactly the sidecar bytes, so a
// later reader verifies the files against the stamp without the loop).
// Advisory stamp fields are never read or touched here.
function saveWindows(spawnId, windows, rootDir) {
  if (typeof spawnId !== 'string' || !SPAWN_ID_FILE_RE.test(spawnId)) {
    return { ok: false, status: 'error', reason: 'invalid-spawn-id', detail: 'spawnId must be filename-safe (letters, digits, dot, dash, underscore)' };
  }
  const w = windows == null ? {} : windows;
  if (!isPlainObject(w)) return { ok: false, status: 'error', reason: 'invalid-windows', detail: 'windows must be an object' };
  const head = w.head == null ? '' : w.head;
  const tail = w.tail == null ? '' : w.tail;
  if (typeof head !== 'string' && !Buffer.isBuffer(head)) return { ok: false, status: 'error', reason: 'invalid-windows', detail: 'head must be a string or Buffer' };
  if (typeof tail !== 'string' && !Buffer.isBuffer(tail)) return { ok: false, status: 'error', reason: 'invalid-windows', detail: 'tail must be a string or Buffer' };
  const headBuf = Buffer.isBuffer(head) ? head : Buffer.from(head, 'utf8');
  const tailBuf = Buffer.isBuffer(tail) ? tail : Buffer.from(tail, 'utf8');
  const dir = windowsDirOf(rootDir);
  if (dir == null) return paused('unwritable', null, 'no XDG data home resolvable', 'auto.store.unwritable');
  let missing = false;
  const r = mutate(rootDir, (st) => {
    const stamp = st.stamps[spawnId];
    if (!stamp) { missing = true; return null; }
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, `${spawnId}.head.txt`), headBuf);
    fs.writeFileSync(path.join(dir, `${spawnId}.tail.txt`), tailBuf);
    stamp.headSha256 = crypto.createHash('sha256').update(headBuf).digest('hex');
    stamp.tailSha256 = crypto.createHash('sha256').update(tailBuf).digest('hex');
    stamp.totalBytes = headBuf.length + tailBuf.length;
    return st;
  });
  if (missing) return { ok: false, status: 'refused', reason: 'stamp-missing', spawnId, path: r.path };
  return r.ok ? { ok: true, path: r.path, windowsDir: dir, stamp: r.store.stamps[spawnId] } : r;
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

// ---- spawn registry (runner side) ----
// Authoritative spawn entries live in <storeRoot>/spawnreg/<spawnId>.json as
// separate files, not a store.json key: every request the loop's wait loop
// acks settles a claim (entry uses++ rewrite + claims.ndjson append), and
// routing that through store.json's cross-process mutate mutex would churn
// the shared store per ack and contend with breaker/stamp mutations. Entries
// are ephemeral per spawn and die with removeSpawn; the directory sits inside
// the store root (machine-local, masked from every sandbox) and dies with
// purgeStore. Policy bounds live HERE — the verb vocabulary from the
// dispatch table and the use-cap hard ceiling — because core may not require
// ops; core/spawnreg only compares against what an entry records.

// Register one spawn before launching it. Grants and the use cap default
// from the dispatch table's stage entry (BUILD carries the checkpoint verb
// and the raised 64 cap; THINK/PLAN/VERIFY stay at 16); explicit values are
// validated fail-closed — vocabulary closed set, cap never past the hard
// ceiling. Redteam spawns register without any write authorization; script
// spawns (Class S fixed-argv steps) register as kind 'script' and only for
// script-worker stages.
function registerSpawn(rec, rootDir) {
  if (!isPlainObject(rec) || typeof rec.spawnId !== 'string' || !SPAWN_ID_FILE_RE.test(rec.spawnId)) {
    return { ok: false, status: 'error', reason: 'invalid-spawn-id', detail: 'spawnId must be filename-safe (letters, digits, dot, dash, underscore)' };
  }
  const kind = rec.kind === 'redteam' ? 'redteam' : rec.kind === 'script' ? 'script' : 'work';
  const stage = String(rec.stage || '').toUpperCase();
  if (!stage) return { ok: false, status: 'error', reason: 'invalid-stage', detail: 'stage required' };
  const table = workers.loadDispatchTable();
  if (!table.ok) {
    return { ok: false, status: 'error', reason: 'dispatch-table-unavailable', detail: table.detail, file: table.file };
  }
  const stageEntry = table.table.stages[stage];
  if (!stageEntry) return { ok: false, status: 'error', reason: 'invalid-stage', detail: `unknown stage ${stage}` };
  if (kind === 'script' && stageEntry.worker !== 'script') {
    return { ok: false, status: 'error', reason: 'invalid-kind', detail: `kind 'script' registers only for script-worker stages (${stage} runs '${stageEntry.worker}')` };
  }
  let grants = Array.isArray(rec.grants) ? [...new Set(rec.grants.map(String))] : [...stageEntry.verbs];
  if (kind === 'redteam') grants = [];
  const badVerbs = grants.filter((v) => !workers.VERBS.includes(v));
  if (badVerbs.length) {
    return { ok: false, status: 'error', reason: 'invalid-grants', detail: `verbs outside the dispatch vocabulary (${workers.VERBS.join('|')}): ${badVerbs.join(', ')}` };
  }
  let useCap = rec.useCap == null ? stageEntry.use_cap : rec.useCap;
  if (!Number.isInteger(useCap) || useCap < 1) {
    return { ok: false, status: 'error', reason: 'invalid-use-cap', detail: 'useCap must be an integer >= 1' };
  }
  if (useCap > limits.HARD_USE_CAP_CEILING) {
    return { ok: false, status: 'error', reason: 'use-cap-over-ceiling', detail: `useCap ${useCap} exceeds the hard ceiling ${limits.HARD_USE_CAP_CEILING}` };
  }
  const scratch = spawnreg.scratchPath(rootDir, rec.spawnId);
  if (scratch == null) return paused('unwritable', null, 'no XDG data home resolvable', 'auto.store.unwritable');
  const acksDir = spawnreg.acksPath(rootDir, rec.spawnId);
  const doc = spawnreg.saveEntryDoc(rootDir, {
    spawn_id: rec.spawnId,
    kind,
    stage,
    grants,
    use_cap: useCap,
    uses: 0,
    window_expiry: Date.now() + (rec.wallMs || 3600000),
    pid: rec.pid,
  });
  try {
    fs.mkdirSync(scratch, { recursive: true });
    if (acksDir != null) fs.mkdirSync(acksDir, { recursive: true });
  } catch (e) {
    return { ok: false, status: 'error', reason: 'unwritable', path: scratch, detail: e.message, guidance: guidanceFor('auto.store.unwritable', { path: scratch }) };
  }
  return { ok: true, path: spawnreg.entryPath(rootDir, rec.spawnId), scratch, acksDir, entry: doc };
}

// Drop the entry, its manifest, and its scratch when the spawn exits.
function removeSpawn(spawnId, rootDir) {
  spawnreg.removeEntry(rootDir, spawnId);
  return { ok: true };
}

// Write this spawn's immutable grant manifest for ro-binding into its
// sandbox: grants, cap, and stage ONLY — no use counter, no other spawn's
// data, nothing the sandbox could replay against another entry.
function writeGrantManifest(rootDir, spawnId) {
  const entry = spawnreg.readEntry(rootDir, spawnId);
  if (!entry) return { ok: false, status: 'refused', reason: 'no-entry', spawnId };
  const manifest = {
    spawn_id: entry.spawn_id,
    stage: entry.stage,
    grants: [...spawnreg.resolvedGrantsOf(entry)],
    use_cap: entry.use_cap,
  };
  const file = spawnreg.manifestPath(rootDir, spawnId);
  if (file == null) return paused('unwritable', null, 'no XDG data home resolvable', 'auto.store.unwritable');
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(manifest));
  } catch (e) {
    return { ok: false, status: 'error', reason: 'write-failed', path: file, detail: e.message };
  }
  return { ok: true, path: file, manifest };
}

// Ack-file helper: the verdict payload lands in the spawn's store-side ack
// dir (<storeRoot>/spawnreg/<spawnId>.acks/<requestId>.ack.json) — outside
// every sandbox, runner-written, ro-bound into the spawn at /run/gos-acks.
// Best-effort — a missing dir just means the spawned side will time out
// closed.
const writeAckFile = (acksDir, requestId, payload) => {
  try {
    fs.mkdirSync(acksDir, { recursive: true });
    fs.writeFileSync(path.join(acksDir, `${requestId}.ack.json`), JSON.stringify(payload));
    return true;
  } catch { return false; }
};

// One-shot runner-side admission: judge the request against the STORE entry
// (never the request's self-declared identity), burn one use for every
// judged verdict, append the claim ledger line, and answer the ack. Grants,
// stage, and budget all come from the entry — a forged request can only
// burn its own spawn's budget. Re-acking the same requestId replays the
// ledger-recorded verdict without a second burn: the spawned side deletes
// its ack file after consuming it, so the ack file cannot be the replay
// anchor — only the store-side ledger can.
function admitAndAck(rootDir, spawnId, cmdName, argvStage, opts = {}) {
  const requestId = typeof opts.requestId === 'string' && opts.requestId ? opts.requestId : null;
  const acksDir = spawnreg.acksPath(rootDir, spawnId);
  const ackFile = requestId && acksDir != null ? path.join(acksDir, `${requestId}.ack.json`) : null;
  if (requestId) {
    const prior = spawnreg.findClaimByRequestId(rootDir, requestId);
    if (prior) {
      const out = {
        admitted: prior.admitted === true,
        reason: prior.reason || undefined,
        remaining: prior.remaining == null ? null : Number(prior.remaining),
        replay: true,
      };
      if (ackFile) writeAckFile(acksDir, requestId, { request_id: requestId, ...out, stage: prior.stage || null, ts: new Date().toISOString() });
      return out;
    }
  }
  const entry = spawnreg.readEntry(rootDir, spawnId);
  if (!entry) {
    spawnreg.appendClaim(rootDir, { request_id: requestId, spawnId, cmd: cmdName, admitted: false, reason: 'no-entry', remaining: null, stage: null, ts: new Date().toISOString() });
    const refused = { admitted: false, reason: 'no-entry', detail: `no live registry entry for spawn ${spawnId || '(unset)'}`, remaining: null };
    if (ackFile) writeAckFile(acksDir, requestId, { request_id: requestId, ...refused, stage: null, ts: new Date().toISOString() });
    return refused;
  }
  const verdict = spawnreg.judgeClaim(entry, cmdName, argvStage);
  const settled = spawnreg.settleClaim(rootDir, spawnId, entry, cmdName, verdict, requestId);
  let out;
  if (verdict.admitted && !settled.persisted) {
    out = { admitted: false, reason: 'claim-write-failed', detail: 'the claim could not be recorded — an uncountable admission is refused', remaining: settled.remaining };
  } else {
    out = { admitted: verdict.admitted === true, reason: verdict.admitted ? undefined : verdict.reason, detail: verdict.admitted ? undefined : verdict.detail, remaining: settled.remaining };
  }
  if (ackFile) {
    writeAckFile(acksDir, requestId, { request_id: requestId, ...out, stage: entry.stage, ts: new Date().toISOString() });
  }
  return out;
}

// Runner-side responder sweep for one spawn: every pending request file in
// the scratch gets one pass through admitAndAck. The ack file is the
// answered marker — a request whose ack already exists is skipped, so a
// replayed request reuses the ledger verdict without a second burn. An
// absent scratch serves zero.
function serviceRequests(rootDir, spawnId) {
  const scratch = spawnreg.scratchPath(rootDir, spawnId);
  if (typeof scratch !== 'string') return 0;
  let names = [];
  try { names = fs.readdirSync(scratch); } catch { return 0; }
  const acksDir = spawnreg.acksPath(rootDir, spawnId);
  let served = 0;
  for (const n of names) {
    if (!n.endsWith('.req.json')) continue;
    const stem = n.slice(0, -'.req.json'.length);
    if (acksDir != null) {
      try { fs.statSync(path.join(acksDir, `${stem}.ack.json`)); continue; } catch { /* unanswered */ }
    }
    let req = null;
    try { req = JSON.parse(fs.readFileSync(path.join(scratch, n), 'utf8')); } catch { continue; }
    admitAndAck(rootDir, spawnId, req.cmd, req.stage, { requestId: req.request_id || stem });
    served += 1;
  }
  return served;
}

// ---- pinned worktree records (Class P legs) ----
// Pin records live as an additive store.json key (never written by older
// writers, never fatal to older readers — validation only fires when the
// key is present). The worktree directories themselves live under
// <storeRoot>/pin-worktrees/<runTag>, this machine only.

function pinWorktreesDir(rootDir) {
  const root = storeRoot(rootDir);
  return root == null ? null : path.join(root, PIN_DIR_NAME);
}

// Record (or refresh) one pinned worktree. The path must be exactly the
// pin-worktrees/<runTag> slot for this store so a record can never point a
// recycle at an arbitrary path.
function recordPin(rootDir, rec) {
  if (!isPlainObject(rec)) return { ok: false, status: 'error', reason: 'invalid-pin' };
  if (typeof rec.runTag !== 'string' || !PIN_RUN_TAG_RE.test(rec.runTag)) {
    return { ok: false, status: 'error', reason: 'invalid-pin-run-tag', detail: 'runTag must be filename-safe (letters, digits, dot, dash, underscore)' };
  }
  if (typeof rec.loopStartCommit !== 'string' || !GIT_SHA_RE.test(rec.loopStartCommit)) {
    return { ok: false, status: 'error', reason: 'invalid-pin-commit', detail: 'loopStartCommit must be a git commit hash (7-64 hex chars)' };
  }
  if (typeof rec.treeSha !== 'string' || !GIT_SHA_RE.test(rec.treeSha)) {
    return { ok: false, status: 'error', reason: 'invalid-pin-tree-sha', detail: 'treeSha must be a git tree hash (7-64 hex chars)' };
  }
  const dir = pinWorktreesDir(rootDir);
  if (dir == null) return paused('unwritable', null, 'no XDG data home resolvable', 'auto.store.unwritable');
  if (typeof rec.path !== 'string' || path.resolve(rec.path) !== path.join(dir, rec.runTag)) {
    return { ok: false, status: 'error', reason: 'invalid-pin-path', detail: `pin path must be ${path.join(dir, rec.runTag)}` };
  }
  const r = mutate(rootDir, (st) => {
    if (!isPlainObject(st.pinWorktrees)) st.pinWorktrees = {};
    st.pinWorktrees[rec.runTag] = {
      path: path.resolve(rec.path),
      treeSha: rec.treeSha,
      loopStartCommit: rec.loopStartCommit,
      createdAtIso: new Date().toISOString(),
    };
    return st;
  });
  return r.ok ? { ok: true, path: r.path, record: r.store.pinWorktrees[rec.runTag] } : r;
}

// Read-only view of every recorded pin.
function readPins(rootDir) {
  const cur = load(rootDir);
  if (!cur.ok) return cur;
  return { ok: true, path: cur.path, pins: isPlainObject(cur.store.pinWorktrees) ? cur.store.pinWorktrees : {} };
}

// Drop one pin record (worktree removal is the caller's job).
function dropPin(rootDir, runTag) {
  if (typeof runTag !== 'string' || !PIN_RUN_TAG_RE.test(runTag)) {
    return { ok: false, status: 'error', reason: 'invalid-pin-run-tag', detail: 'runTag must be filename-safe' };
  }
  let dropped = null;
  const r = mutate(rootDir, (st) => {
    if (isPlainObject(st.pinWorktrees) && Object.prototype.hasOwnProperty.call(st.pinWorktrees, runTag)) {
      dropped = st.pinWorktrees[runTag];
      delete st.pinWorktrees[runTag];
    }
    return st;
  });
  return r.ok ? { ok: true, path: r.path, dropped } : r;
}

// Prune helper: drop every pin record whose run tag is not live; the
// dropped records ride the result so the caller can remove the worktrees.
function prunePins(rootDir, opts = {}) {
  const live = new Set(Array.isArray(opts.liveRunTags) ? opts.liveRunTags.map(String) : []);
  const dropped = [];
  const r = mutate(rootDir, (st) => {
    if (isPlainObject(st.pinWorktrees)) {
      for (const tag of Object.keys(st.pinWorktrees)) {
        if (!live.has(tag)) {
          dropped.push({ runTag: tag, ...st.pinWorktrees[tag] });
          delete st.pinWorktrees[tag];
        }
      }
    }
    return st;
  });
  return r.ok ? { ok: true, path: r.path, dropped } : r;
}

// ---- wave completion records + dispatch-table stamp ----

// Record (or idempotently re-affirm) one released wave. Keyed
// '<task>/W<n>'. An identical re-record refreshes the timestamp-free
// fields; a conflicting re-record refuses — a released wave's head and
// refs pointer are history, never rewritable.
function recordWaveCompletion(rootDir, rec) {
  if (!isPlainObject(rec)) return { ok: false, status: 'error', reason: 'invalid-wave-record' };
  if (typeof rec.task !== 'string' || !rec.task) return { ok: false, status: 'error', reason: 'invalid-wave-record', detail: 'task required' };
  if (!Number.isInteger(rec.wave) || rec.wave < 1) return { ok: false, status: 'error', reason: 'invalid-wave-record', detail: 'wave must be an integer >= 1' };
  if (typeof rec.head !== 'string' || !GIT_SHA_RE.test(rec.head)) {
    return { ok: false, status: 'error', reason: 'invalid-wave-record', detail: 'head must be a git commit hash' };
  }
  if (typeof rec.refsPointer !== 'string' || !HEX64_RE.test(rec.refsPointer)) {
    return { ok: false, status: 'error', reason: 'invalid-wave-record', detail: 'refsPointer must be the hex64 sha256 of the post-wave refs snapshot' };
  }
  const key = `${rec.task}/W${rec.wave}`;
  if (!WAVE_KEY_RE.test(key)) {
    return { ok: false, status: 'error', reason: 'invalid-wave-record', detail: `task id must be filename-safe (got '${rec.task}')` };
  }
  let conflict = null;
  const r = mutate(rootDir, (st) => {
    if (!isPlainObject(st.waves)) st.waves = {};
    const prev = st.waves[key];
    const next = { head: rec.head, refsPointer: rec.refsPointer, releasedAtIso: new Date().toISOString() };
    if (rec.noop === true) {
      next.noop = true;
      if (typeof rec.noopReason === 'string' && rec.noopReason) next.noopReason = rec.noopReason;
    }
    if (rec.rolledTable === true) next.rolledTable = true;
    if (prev) {
      const held = (o) => [o.head, o.refsPointer, o.noop === true, o.rolledTable === true];
      if (JSON.stringify(held(prev)) !== JSON.stringify(held(next))) {
        conflict = { key, prev };
        return null;
      }
      return st; // identical re-affirmation: keep the original record
    }
    st.waves[key] = next;
    return st;
  });
  if (conflict) {
    return { ok: false, status: 'error', reason: 'wave-record-conflict', path: r.path, detail: `wave ${conflict.key} already recorded with a different outcome` };
  }
  return r.ok ? { ok: true, path: r.path, record: r.store.waves[key] } : r;
}

// Read-only view of every wave completion record.
function readWaveRecords(rootDir) {
  const cur = load(rootDir);
  if (!cur.ok) return cur;
  return { ok: true, path: cur.path, waves: isPlainObject(cur.store.waves) ? cur.store.waves : {} };
}

// Record (or overwrite on re-entry) one wave's pre-spawn start evidence:
// the refs/dirty world the runner validated BEFORE the spawn ran. The
// record is store-side so crash recovery never trusts spawn-writable
// scratch content for attribution.
function recordWaveStart(rootDir, rec) {
  if (!isPlainObject(rec)) return { ok: false, status: 'error', reason: 'invalid-wave-start' };
  if (typeof rec.task !== 'string' || !rec.task) return { ok: false, status: 'error', reason: 'invalid-wave-start', detail: 'task required' };
  if (!Number.isInteger(rec.wave) || rec.wave < 1) return { ok: false, status: 'error', reason: 'invalid-wave-start', detail: 'wave must be an integer >= 1' };
  if (typeof rec.spawnId !== 'string' || !SPAWN_ID_FILE_RE.test(rec.spawnId)) {
    return { ok: false, status: 'error', reason: 'invalid-wave-start', detail: 'spawnId must be filename-safe' };
  }
  if (typeof rec.preHead !== 'string' || !GIT_SHA_RE.test(rec.preHead)) {
    return { ok: false, status: 'error', reason: 'invalid-wave-start', detail: 'preHead must be a git commit hash' };
  }
  if (typeof rec.preRefsText !== 'string') return { ok: false, status: 'error', reason: 'invalid-wave-start', detail: 'preRefsText must be a string' };
  if (!Array.isArray(rec.preDirty) || !rec.preDirty.every((p) => typeof p === 'string')) {
    return { ok: false, status: 'error', reason: 'invalid-wave-start', detail: 'preDirty must be a string array' };
  }
  const key = `${rec.task}/W${rec.wave}`;
  const r = mutate(rootDir, (st) => {
    if (!isPlainObject(st.waveStarts)) st.waveStarts = {};
    st.waveStarts[key] = {
      spawnId: rec.spawnId,
      preHead: rec.preHead,
      preRefsText: rec.preRefsText,
      preDirty: rec.preDirty.slice(),
      startedAtIso: new Date().toISOString(),
    };
    return st;
  });
  return r.ok ? { ok: true, path: r.path, record: r.store.waveStarts[key] } : r;
}

// Read-only view of every wave start record.
function readWaveStarts(rootDir) {
  const cur = load(rootDir);
  if (!cur.ok) return cur;
  return { ok: true, path: cur.path, waveStarts: isPlainObject(cur.store.waveStarts) ? cur.store.waveStarts : {} };
}

// Record one held wave: a runner verdict (contract violation), never a
// crash shape. Reconciliation distinguishes held from crashed waves by this
// record and never adopts a held wave's commit.
function recordHeldWave(rootDir, rec) {
  if (!isPlainObject(rec)) return { ok: false, status: 'error', reason: 'invalid-held-wave' };
  if (typeof rec.task !== 'string' || !rec.task) return { ok: false, status: 'error', reason: 'invalid-held-wave', detail: 'task required' };
  if (!Number.isInteger(rec.wave) || rec.wave < 1) return { ok: false, status: 'error', reason: 'invalid-held-wave', detail: 'wave must be an integer >= 1' };
  if (typeof rec.reason !== 'string' || !rec.reason) return { ok: false, status: 'error', reason: 'invalid-held-wave', detail: 'reason required' };
  if (typeof rec.spawnId !== 'string' || !SPAWN_ID_FILE_RE.test(rec.spawnId)) {
    return { ok: false, status: 'error', reason: 'invalid-held-wave', detail: 'spawnId must be filename-safe' };
  }
  const key = `${rec.task}/W${rec.wave}`;
  const r = mutate(rootDir, (st) => {
    if (!isPlainObject(st.heldWaves)) st.heldWaves = {};
    st.heldWaves[key] = { reason: rec.reason, spawnId: rec.spawnId, heldAtIso: new Date().toISOString() };
    return st;
  });
  return r.ok ? { ok: true, path: r.path, record: r.store.heldWaves[key] } : r;
}

// Read-only view of every held-wave record.
function readHeldWaves(rootDir) {
  const cur = load(rootDir);
  if (!cur.ok) return cur;
  return { ok: true, path: cur.path, heldWaves: isPlainObject(cur.store.heldWaves) ? cur.store.heldWaves : {} };
}

// Roll the dispatch-table stamp. Two provenance shapes: a red-team-passed,
// runner-released wave edit records its wave key '<task>/W<n>'; a run start
// records '<runTag>/start' — the loop stamps the table it loaded before any
// consume, and every later wave re-verifies against that hash. The stamp is
// the sha256 of the table file as of the write; shape validation keeps
// refusing everything outside the two forms.
function rollDispatchTableStamp(rootDir, rec) {
  if (!isPlainObject(rec)) return { ok: false, status: 'error', reason: 'invalid-table-stamp' };
  if (typeof rec.sha256 !== 'string' || !HEX64_RE.test(rec.sha256)) {
    return { ok: false, status: 'error', reason: 'invalid-table-stamp', detail: 'sha256 must be the hex64 hash of the dispatch table file' };
  }
  if (typeof rec.rolledByWave !== 'string' || !(WAVE_KEY_RE.test(rec.rolledByWave) || RUN_START_KEY_RE.test(rec.rolledByWave))) {
    return {
      ok: false, status: 'error', reason: 'invalid-table-stamp',
      detail: `rolledByWave must be a wave key '<task>/W<n>' or a run-start tag '<runTag>/start' (got '${rec.rolledByWave}')`,
    };
  }
  const r = mutate(rootDir, (st) => {
    st.dispatchTable = { sha256: rec.sha256, rolledAtIso: new Date().toISOString(), rolledByWave: rec.rolledByWave };
    return st;
  });
  return r.ok ? { ok: true, path: r.path, stamp: r.store.dispatchTable } : r;
}

// Read-only view of the current dispatch-table stamp (null when never rolled).
function readDispatchTableStamp(rootDir) {
  const cur = load(rootDir);
  if (!cur.ok) return cur;
  return { ok: true, path: cur.path, stamp: isPlainObject(cur.store.dispatchTable) ? cur.store.dispatchTable : null };
}

// Record the loop's baseline state hash: the sha256 of the state file bytes
// as the runner last read and validated them. The crashed-advance recovery
// adopts a snapshot only on an exact hash match, so a crafted snapshot from
// a spawn-writable path can never ride the rollback.
function recordBaselineState(rootDir, sha256) {
  if (typeof sha256 !== 'string' || !HEX64_RE.test(sha256)) {
    return { ok: false, status: 'error', reason: 'invalid-baseline-state', detail: 'sha256 must be the hex64 hash of the state file bytes' };
  }
  const r = mutate(rootDir, (st) => {
    st.baselineState = { sha256, recordedAtIso: new Date().toISOString() };
    return st;
  });
  return r.ok ? { ok: true, path: r.path, baselineState: r.store.baselineState } : r;
}

// Read-only view of the current baseline-state record (null when absent).
function readBaselineState(rootDir) {
  const cur = load(rootDir);
  if (!cur.ok) return cur;
  return { ok: true, path: cur.path, baselineState: isPlainObject(cur.store.baselineState) ? cur.store.baselineState : null };
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
  saveWindows,
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
  registerSpawn,
  removeSpawn,
  writeGrantManifest,
  admitAndAck,
  serviceRequests,
  pinWorktreesDir,
  recordPin,
  readPins,
  dropPin,
  prunePins,
  recordWaveCompletion,
  readWaveRecords,
  recordWaveStart,
  readWaveStarts,
  recordHeldWave,
  readHeldWaves,
  rollDispatchTableStamp,
  readDispatchTableStamp,
  recordBaselineState,
  readBaselineState,
  purgeStore,
};
