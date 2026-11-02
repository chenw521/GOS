// core/spawnreg — spawn write channel: the request/ack protocol the spawned
// side speaks, the entry/claim/scratch file layout shared with the runner-side
// registry (ops/auto/store.cjs), and the admission verdict the lock layer
// consumes. Authoritative entries live in the machine-local store directory
// (runner-written, masked from every sandbox); the repo-side
// .gos/cache/auto-spawn directory is dead — nothing reads it, and files left
// there carry no meaning.
//
// Layer rule: core may not require ops (require-direction allowlist), so the
// store-location derivation below mirrors ops/auto/store.cjs#storeRoot and the
// runner-side writer (registerSpawn in ops/auto/store.cjs) owns every policy
// bound (verb vocabulary, use-cap ceiling). This module only compares against
// what an entry already records.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const state = require('./state.cjs');

const SPAWNREG_DIR_NAME = 'spawnreg';
const CLAIMS_FILE = 'claims.ndjson';
const MAX_ANCESTRY_DEPTH = 128;
const HEARTBEAT_FRESH_MS = 120000;
const SPAWN_ID_FILE_RE = /^[A-Za-z\d][A-Za-z\d._-]*$/;

// Channel env: GOS_AUTO_SPAWN_SCRATCH is the rw scratch dir the runner mounts
// into the sandbox (request drop); GOS_AUTO_ACK_DIR is the runner-written,
// store-side ack dir ro-bound at /run/gos-acks — the ONLY place the spawned
// side reads verdicts from. The scratch is never an ack source: a sandboxed
// session could self-sign there. GOS_AUTO_SPAWN_ACK_WAIT_MS bounds the
// spawned side's wait for the runner's ack before failing closed.
const SCRATCH_ENV = 'GOS_AUTO_SPAWN_SCRATCH';
const ACK_DIR_ENV = 'GOS_AUTO_ACK_DIR';
const ACK_WAIT_ENV = 'GOS_AUTO_SPAWN_ACK_WAIT_MS';
const ACK_WAIT_DEFAULT_MS = 5000;
const ACK_WAIT_MAX_MS = 60000;
const ACK_POLL_MS = 25;

// Claim ledger bound (the append caps' spirit): past this many lines the file
// is reaped to half before the next append, so a long-lived registry stays
// bounded.
const CLAIMS_LEDGER_MAX = 2048;
const CLAIMS_LEDGER_KEEP = 1024;

// Human gates refuse first, before any registry lookups — the refusal is
// about WHAT the command is, not whether the spawn is registered. Grant lists
// can never negotiate these verbs.
const HUMAN_GATE_CMDS = new Set(['approve', 'archive', 'push', 'disposition']);

// Legacy grant-less default: one window covering the assigned advance and the
// verification verbs. Truth is whitelisted for `verify` only — recording
// evidence with a real replay, never free-text assertion.
const WINDOW_WRITE_CMDS = new Set(['commit', 'gate', 'section']);
const LEGACY_GRANTS = new Set([...WINDOW_WRITE_CMDS, 'truth']);
const LEGACY_USE_CAP = 16;
// Dispatch-table BUILD use_cap for grant-carrying entries written through the
// legacy writer; the hard ceiling itself is enforced by the ops-side writer.
const GRANTED_USE_CAP = 64;
const DEFAULT_WINDOW_MS = 3600000;

// ---- store-side layout (authoritative entry home) ----
// storeSpawnRoot mirrors ops/auto/store.cjs#storeRoot: XDG data home (or
// $HOME/.local/share) plus gos/<repoKey>. Keep the two derivations in sync;
// both resolve per call so env overrides apply immediately.
function storeSpawnRoot(rootDir) {
  const xdg = process.env.XDG_DATA_HOME;
  let home = null;
  if (xdg && path.isAbsolute(xdg)) home = xdg;
  else {
    const h = os.homedir();
    if (h) home = path.join(h, '.local', 'share');
  }
  if (!home) return null;
  let root = rootDir ? path.resolve(rootDir) : (state.currentRootRealpath() || process.cwd());
  try { root = fs.realpathSync(root); } catch { /* keep resolved path */ }
  const id = state.repoIdFromRemotes(root);
  const key = id != null ? id : 'local:' + crypto.createHash('sha256').update(root).digest('hex').slice(0, 16);
  return path.join(home, 'gos', key);
}

function spawnregDir(rootDir) {
  const base = storeSpawnRoot(rootDir);
  return base == null ? null : path.join(base, SPAWNREG_DIR_NAME);
}

function entryPath(rootDir, spawnId) {
  const dir = spawnregDir(rootDir);
  return dir == null ? null : path.join(dir, `${spawnId}.json`);
}

function manifestPath(rootDir, spawnId) {
  const dir = spawnregDir(rootDir);
  return dir == null ? null : path.join(dir, `${spawnId}.manifest.json`);
}

function scratchPath(rootDir, spawnId) {
  const dir = spawnregDir(rootDir);
  return dir == null ? null : path.join(dir, `${spawnId}.scratch`);
}

// Per-spawn ack dir: runner-written verdict files live store-side (outside
// every sandbox); the launcher ro-binds this dir into the sandbox at
// /run/gos-acks so the spawned side can read — never write — its acks.
function acksPath(rootDir, spawnId) {
  const dir = spawnregDir(rootDir);
  return dir == null ? null : path.join(dir, `${spawnId}.acks`);
}

function claimsPath(rootDir) {
  const dir = spawnregDir(rootDir);
  return dir == null ? null : path.join(dir, CLAIMS_FILE);
}

// ---- entry records ----

// Persist a complete entry doc as-is. The doc shape ({spawn_id, kind, stage,
// grants, use_cap, uses, window_expiry, pid}) is this module's file format;
// policy validation belongs to the writer that composed it.
function saveEntryDoc(rootDir, doc) {
  if (!doc || typeof doc !== 'object' || typeof doc.spawn_id !== 'string' || !SPAWN_ID_FILE_RE.test(doc.spawn_id)) {
    throw new Error('spawnreg entry doc requires a filename-safe spawn_id');
  }
  const p = entryPath(rootDir, doc.spawn_id);
  if (p == null) throw new Error('no data home resolvable for the spawn registry');
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, JSON.stringify(doc));
  return doc;
}

// Runner-side legacy registration: entries WITHOUT grants keep the four-verb
// default and the legacy cap. Grant-carrying registration (dispatch-table
// verbs, raised caps) goes through ops/auto/store.cjs#registerSpawn, which
// validates the verb vocabulary and the use-cap ceiling before saving — this
// path never honors caller-supplied grants or caps.
function writeEntry(root, rec) {
  const now = Date.now();
  return saveEntryDoc(root, {
    spawn_id: rec.spawnId,
    kind: rec.kind === 'redteam' ? 'redteam' : 'work',
    stage: String(rec.stage || '').toUpperCase(),
    grants: null,
    use_cap: LEGACY_USE_CAP,
    uses: 0,
    window_expiry: now + (rec.wallMs || DEFAULT_WINDOW_MS),
    pid: rec.pid,
  });
}

// Runner-side teardown: the entry, its manifest, its scratch, and its ack
// dir die together.
function removeEntry(root, spawnId) {
  const dir = spawnregDir(root);
  if (dir == null || !spawnId || !SPAWN_ID_FILE_RE.test(spawnId)) return;
  for (const p of [entryPath(root, spawnId), manifestPath(root, spawnId)]) {
    try { fs.unlinkSync(p); } catch { /* absent */ }
  }
  try { fs.rmSync(path.join(dir, `${spawnId}.scratch`), { recursive: true, force: true }); } catch { /* absent */ }
  try { fs.rmSync(path.join(dir, `${spawnId}.acks`), { recursive: true, force: true }); } catch { /* absent */ }
}

function readEntry(root, spawnId) {
  if (!spawnId || typeof spawnId !== 'string' || !SPAWN_ID_FILE_RE.test(spawnId)) return null;
  const p = entryPath(root, spawnId);
  if (p == null) return null;
  let doc = null;
  try { doc = JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; }
  if (!doc || typeof doc !== 'object') return null;
  if (Number(doc.window_expiry) < Date.now()) return null;
  return doc;
}

// A spawn's effective verb set: grant-carrying entries carry their dispatch
// verbs verbatim; grant-less legacy entries keep the four-verb default.
// Redteam entries never resolve to a non-empty set.
function resolvedGrantsOf(entry) {
  if (entry.kind === 'redteam') return new Set();
  if (Array.isArray(entry.grants) && entry.grants.length) return new Set(entry.grants.map(String));
  return new Set(LEGACY_GRANTS);
}

// ---- claim settlement ----

// Append one claim ledger line, bounded. The ledger is audit-side: a failed
// append never changes a verdict.
function appendClaim(root, line) {
  const p = claimsPath(root);
  if (p == null) return;
  try {
    fs.mkdirSync(path.dirname(p), { recursive: true });
    let lines = [];
    try { lines = fs.readFileSync(p, 'utf8').split('\n').filter((l) => l.trim()); } catch { /* first claim */ }
    if (lines.length >= CLAIMS_LEDGER_MAX) lines = lines.slice(lines.length - CLAIMS_LEDGER_KEEP);
    lines.push(JSON.stringify(line));
    fs.writeFileSync(p, lines.join('\n') + '\n');
  } catch { /* audit best-effort */ }
}

// Burn one use against the entry and record the claim. Every judged verdict
// except budget-exhaustion costs the spawn one use — refused or admitted —
// so a compromised session cannot probe its grants for free. Returns
// { remaining, persisted }; an unpersistable burn must never back an
// admission.
function settleClaim(root, spawnId, entry, cmdName, verdict, requestId) {
  const cap = Number(entry.use_cap || LEGACY_USE_CAP);
  if (verdict.burn) entry.uses = Number(entry.uses || 0) + 1;
  let persisted = true;
  if (verdict.burn) {
    try { saveEntryDoc(root, entry); } catch { persisted = false; }
  }
  const remaining = Math.max(0, cap - Number(entry.uses || 0));
  appendClaim(root, {
    request_id: requestId || null,
    spawnId,
    cmd: cmdName,
    admitted: verdict.admitted === true,
    reason: verdict.admitted ? null : verdict.reason,
    remaining,
    stage: entry.stage || null,
    ts: new Date().toISOString(),
  });
  return { remaining, persisted };
}

// The durable replay anchor for a settled request: the claims ledger lives
// in the store directory, which no spawned side can reach, so a requestId
// judged once keeps its verdict even after the spawned side consumes and
// deletes its ack file. Latest match wins.
function findClaimByRequestId(root, requestId) {
  if (!requestId || typeof requestId !== 'string') return null;
  const p = claimsPath(root);
  if (p == null) return null;
  let lines = [];
  try { lines = fs.readFileSync(p, 'utf8').split('\n'); } catch { return null; }
  for (let i = lines.length - 1; i >= 0; i--) {
    const l = lines[i].trim();
    if (!l) continue;
    let doc = null;
    try { doc = JSON.parse(l); } catch { continue; }
    if (doc && doc.request_id === requestId) return doc;
  }
  return null;
}

// ---- admission rules (pure: entry + command -> verdict) ----
// Hardcoded first, before any grant evaluation: human gates and the redteam
// refusal; the assigned-stage check on `commit` and the truth verify-only
// restriction follow. Budget is judged last.
function judgeClaim(entry, cmdName, argvStage) {
  if (HUMAN_GATE_CMDS.has(cmdName)) {
    return { admitted: false, burn: true, reason: 'human-gate', detail: `\`gos ${cmdName}\` requires a human at the terminal — the spawned session may only run its assigned stage advance` };
  }
  if (entry.kind === 'redteam') {
    return { admitted: false, burn: true, reason: 'redteam-no-write', detail: 'redteam spawns never carry write authorization' };
  }
  const grants = resolvedGrantsOf(entry);
  const notInGrants = () => ({
    admitted: false, burn: true, reason: 'not-in-grants',
    detail: `command "${cmdName}" is not in spawn ${entry.spawn_id}'s grants (${[...grants].join(', ') || 'none'}) — a spawn may run only the verbs the runner registered for it`,
  });
  if (cmdName === 'commit') {
    if (!grants.has('commit')) return notInGrants();
    const want = String(entry.stage || '').toUpperCase();
    if (String(argvStage || '').toUpperCase() !== want) {
      return { admitted: false, burn: true, reason: 'stage-mismatch', detail: `spawn ${entry.spawn_id} is assigned stage ${want}, not "${argvStage}"` };
    }
  } else if (cmdName === 'truth') {
    if (!grants.has('truth')) return notInGrants();
    if (String(argvStage || '').toLowerCase() !== 'verify') {
      return { admitted: false, burn: true, reason: 'not-whitelisted', detail: 'truth is whitelisted for `verify` only — evidence replay, never free-text assertion' };
    }
  } else if (!grants.has(cmdName)) {
    return notInGrants();
  }
  const cap = Number(entry.use_cap || LEGACY_USE_CAP);
  if (Number(entry.uses || 0) >= cap) {
    return { admitted: false, burn: false, reason: 'budget-exhausted', detail: `spawn ${entry.spawn_id} exhausted its window write budget (${cap})` };
  }
  return { admitted: true, burn: true };
}

// ---- holder liveness (unchanged semantics, consolidated) ----

// /proc/<pid>/stat field 22 (starttime) — the comm field may contain
// spaces and parentheses, so parsing starts after the LAST ')'.
function procStartTime(pid) {
  try {
    const stat = fs.readFileSync(`/proc/${pid}/stat`, 'utf8');
    const tail = stat.slice(stat.lastIndexOf(')') + 2);
    return Number(tail.split(' ')[19]); // field 22 overall; index 19 after comm+state
  } catch { return null; }
}

// Ancestry of the current process as a Set of pids, bounded, excluding
// pid 1 and the current pid (every walk terminates at 1 — it proves
// nothing about the holder).
function ancestryPids() {
  const seen = new Set();
  let cur = process.ppid;
  for (let i = 0; i < MAX_ANCESTRY_DEPTH && cur > 1; i++) {
    seen.add(cur);
    try {
      const stat = fs.readFileSync(`/proc/${cur}/stat`, 'utf8');
      const tail = stat.slice(stat.lastIndexOf(')') + 2);
      cur = Number(tail.split(' ')[1]); // ppid: field 4 overall, index 1 after comm+state
      if (!Number.isInteger(cur) || cur <= 0) break;
    } catch { break; } // unreadable /proc — fail closed by truncating the chain
  }
  return seen;
}

// Live, fresh, ancestral lock holder or null. These are environmental
// checks only the spawned side can make (its own /proc view), so they run
// before any channel I/O in both admission paths.
function holderVerdict(holder, lockPath) {
  if (!holder || typeof holder.pid !== 'number') {
    return { ok: false, reason: 'holder-unknown', detail: 'lock record unreadable or missing holder identity' };
  }
  try { process.kill(holder.pid, 0); } catch (e) {
    if (e.code !== 'EPERM') return { ok: false, reason: 'holder-dead', detail: `lock holder pid ${holder.pid} is not alive` };
  }
  const myBoot = (() => {
    try { return fs.readFileSync('/proc/sys/kernel/random/boot_id', 'utf8').trim(); } catch { return null; }
  })();
  if (holder.boot_id != null && myBoot != null && holder.boot_id !== myBoot) {
    return { ok: false, reason: 'holder-boot', detail: `lock holder pid ${holder.pid} is from a previous boot` };
  }
  const startTime = procStartTime(holder.pid);
  if (holder.starttime != null && startTime != null && Number(holder.starttime) !== startTime) {
    return { ok: false, reason: 'holder-starttime', detail: `pid ${holder.pid} exists but is not the lock holder (starttime mismatch — pid reuse)` };
  }
  let mtimeFresh = false;
  try { mtimeFresh = Date.now() - fs.statSync(lockPath).mtimeMs < HEARTBEAT_FRESH_MS; } catch { /* unreadable */ }
  if (!mtimeFresh) {
    return { ok: false, reason: 'stale-heartbeat', detail: `lock heartbeat stale (>${Math.round(HEARTBEAT_FRESH_MS / 1000)}s) — the runner may be stalled; the channel requires a live fresh holder` };
  }
  const chain = ancestryPids();
  if (!chain.has(holder.pid)) {
    return { ok: false, reason: 'not-ancestor', detail: `lock holder pid ${holder.pid} is not in this process's ancestry (marker alone never admits)` };
  }
  return null;
}

// ---- request/ack protocol (spawned side) ----

function channelScratchDir() {
  const v = process.env[SCRATCH_ENV];
  if (v == null || v === '') return null;
  if (!path.isAbsolute(v)) return { invalid: true, value: v };
  return v;
}

// Ack pickup dir: the runner-written, store-side dir ro-bound into the
// sandbox. Unset means no ack can ever arrive (the channel fails closed on
// timeout); a relative value is malformed and refuses immediately.
function channelAckDir() {
  const v = process.env[ACK_DIR_ENV];
  if (v == null || v === '') return null;
  if (!path.isAbsolute(v)) return { invalid: true, value: v };
  return v;
}

function ackWaitMs() {
  const v = Number(process.env[ACK_WAIT_ENV]);
  if (Number.isFinite(v) && v >= 0) return Math.min(v, ACK_WAIT_MAX_MS);
  return ACK_WAIT_DEFAULT_MS;
}

function sleepMs(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

// One-shot channel round trip: drop a request file into the rw scratch,
// wait bounded for the runner's ack from the ro-bound ack dir, fail closed
// on timeout. The ack file is read ONLY from the ack dir — the scratch is
// spawn-writable, so a self-written ack there must never count. A missing
// ack dir env or a malformed/absent ack is a timeout — the channel admits
// nothing without the runner's answer.
function admitViaChannel(scratch, opts) {
  const hv = holderVerdict(opts.holder, opts.lockPath);
  if (hv) return hv;
  const requestId = `req-${Date.now().toString(36)}-${process.pid.toString(36)}-${crypto.randomBytes(4).toString('hex')}`;
  const reqFile = path.join(scratch, `${requestId}.req.json`);
  const ackDir = channelAckDir();
  const ackFile = ackDir ? path.join(ackDir, `${requestId}.ack.json`) : null;
  const request = {
    request_id: requestId,
    spawn_id: opts.spawnId || null,
    cmd: opts.cmdName,
    stage: opts.argvStage || null,
    pid: process.pid,
    ts: new Date().toISOString(),
  };
  try {
    fs.mkdirSync(scratch, { recursive: true });
    fs.writeFileSync(reqFile, JSON.stringify(request));
  } catch (e) {
    return { ok: false, reason: 'no-channel', detail: `spawn scratch ${scratch} unwritable (${e.message}) — the write channel needs the runner-provided scratch dir` };
  }
  const waitMs = ackWaitMs();
  const deadline = Date.now() + waitMs;
  const cleanupReq = () => { try { fs.unlinkSync(reqFile); } catch { /* gone */ } };
  for (;;) {
    let ack = null;
    if (ackFile) {
      try { ack = JSON.parse(fs.readFileSync(ackFile, 'utf8')); } catch { ack = null; }
    }
    if (ack && typeof ack === 'object' && typeof ack.admitted === 'boolean') {
      cleanupReq();
      // Best-effort ack cleanup: the ro-bound dir refuses the unlink inside
      // the sandbox (caught); an unsandboxed dev run clears its own ack.
      try { fs.unlinkSync(ackFile); } catch { /* read-only mount or gone */ }
      if (ack.admitted) {
        return { ok: true, entry: { spawn_id: opts.spawnId, stage: ack.stage, remaining: ack.remaining } };
      }
      return { ok: false, reason: ack.reason || 'refused', detail: ack.detail || 'the runner refused this request' };
    }
    if (Date.now() >= deadline) {
      cleanupReq();
      return { ok: false, reason: 'ack-timeout', detail: `no runner ack within ${waitMs}ms — failing closed (the channel admits nothing without the runner's answer)` };
    }
    sleepMs(ACK_POLL_MS);
  }
}

// Direct admission against the store-side entry: the path taken when no
// scratch dir arrived (unsandboxed or legacy runners — the loop and older
// fixtures register entries and run spawned CLIs synchronously in one
// process tree). Inside a sandbox the store directory is masked, so this
// read can never succeed there; repo-side .gos/cache entries are never
// consulted anywhere.
function admitDirect(root, opts) {
  const entry = readEntry(root, opts.spawnId);
  if (!entry) {
    return { ok: false, reason: 'no-entry', detail: `no live registry entry for spawn ${opts.spawnId || '(unset)'} — the store-side registry is the only entry source (repo-side .gos/cache/auto-spawn files are inert)` };
  }
  const verdict = judgeClaim(entry, opts.cmdName, opts.argvStage);
  if (!verdict.admitted) {
    settleClaim(root, entry.spawn_id, entry, opts.cmdName, verdict);
    return { ok: false, reason: verdict.reason, detail: verdict.detail };
  }
  const hv = holderVerdict(opts.holder, opts.lockPath);
  if (hv) return hv;
  const settled = settleClaim(root, entry.spawn_id, entry, opts.cmdName, verdict);
  if (!settled.persisted) {
    return { ok: false, reason: 'claim-write-failed', detail: 'the claim could not be recorded — an uncountable admission is refused' };
  }
  return { ok: true, entry: { spawn_id: entry.spawn_id, stage: entry.stage, remaining: settled.remaining } };
}

// The verdict consumed by guardCwd: does THIS command, in THIS process, get
// the runner's spawn channel? Human gates and the auto-family passthrough
// are hardcoded first; then the scratch channel (sandboxed spawns) or the
// direct store read (unsandboxed legacy runners). argvStage is the stage
// word of a commit call. Returns { ok: true } or { ok: false, reason, detail }.
function admitSpawnWrite(root, opts) {
  const { cmdName } = opts;
  if (HUMAN_GATE_CMDS.has(cmdName)) {
    return { ok: false, reason: 'human-gate', detail: `\`gos ${cmdName}\` requires a human at the terminal — the spawned session may only run its assigned stage advance` };
  }
  // The auto family enforces its own marker boundary inside its dispatcher
  // (on/off/run/disposition refuse, status stays readable) — the channel
  // passes it through untouched: no claim, no banner, no lock.
  if (cmdName === 'auto') {
    return { ok: true, passthrough: 'auto-family', entry: null };
  }
  const scratch = channelScratchDir();
  if (scratch && scratch.invalid) {
    return { ok: false, reason: 'bad-channel', detail: `${SCRATCH_ENV} must be an absolute scratch dir path (got "${scratch.value}")` };
  }
  const ackDir = channelAckDir();
  if (ackDir && ackDir.invalid) {
    return { ok: false, reason: 'bad-channel', detail: `${ACK_DIR_ENV} must be an absolute ack dir path (got "${ackDir.value}")` };
  }
  if (scratch) return admitViaChannel(scratch, opts);
  return admitDirect(root, opts);
}

module.exports = {
  storeSpawnRoot,
  spawnregDir,
  entryPath,
  manifestPath,
  scratchPath,
  acksPath,
  claimsPath,
  saveEntryDoc,
  writeEntry,
  removeEntry,
  readEntry,
  resolvedGrantsOf,
  judgeClaim,
  settleClaim,
  appendClaim,
  findClaimByRequestId,
  admitSpawnWrite,
  procStartTime,
  ancestryPids,
};
