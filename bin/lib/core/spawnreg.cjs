// core/spawnreg — runner-registered spawn write channel: the registry,
// the one-shot claim, and the admission verdict consumed by the lock layer.
// A spawned session gets exactly one write-class command (its assigned
// stage advance); everything else keeps the normal live-holder block.
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const SPAWN_DIR_NAME = path.join('cache', 'auto-spawn');
const MAX_ANCESTRY_DEPTH = 128;
const HEARTBEAT_FRESH_MS = 120000;

function registryDir(root) {
  return path.join(root, '.gos', SPAWN_DIR_NAME);
}

function entryPath(root, spawnId) {
  return path.join(registryDir(root), `${spawnId}.json`);
}

function claimPath(root, spawnId) {
  return path.join(registryDir(root), `${spawnId}.claim`);
}

// Runner-side: register a spawn before launching it. kind is 'work' or
// 'redteam'; wallMs bounds the window after which the entry never validates.
function writeEntry(root, rec) {
  const dir = registryDir(root);
  fs.mkdirSync(dir, { recursive: true });
  const doc = {
    spawn_id: rec.spawnId,
    kind: rec.kind === 'redteam' ? 'redteam' : 'work',
    stage: String(rec.stage || '').toUpperCase(),
    pid: rec.pid,
    expires_at: Date.now() + (rec.wallMs || 3600000),
  };
  fs.writeFileSync(entryPath(root, rec.spawnId), JSON.stringify(doc));
}

// Runner-side: drop the entry when the spawn exits.
function removeEntry(root, spawnId) {
  for (const p of [entryPath(root, spawnId), claimPath(root, spawnId)]) {
    try { fs.unlinkSync(p); } catch { /* absent */ }
  }
}

function readEntry(root, spawnId) {
  if (!spawnId || typeof spawnId !== 'string') return null;
  let doc = null;
  try { doc = JSON.parse(fs.readFileSync(entryPath(root, spawnId), 'utf8')); } catch { return null; }
  if (!doc || typeof doc !== 'object') return null;
  if (Number(doc.expires_at) < Date.now()) return null;
  return doc;
}

// One-shot gate: the first caller claims the channel for this spawn,
// any concurrent second caller fails.
function claimChannel(root, spawnId) {
  try {
    const fd = fs.openSync(claimPath(root, spawnId), 'wx');
    fs.writeSync(fd, JSON.stringify({ pid: process.pid, at: new Date().toISOString() }));
    fs.closeSync(fd);
    return true;
  } catch (e) {
    if (e && e.code === 'EEXIST') return false;
    throw e;
  }
}

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

// Human gates refuse first, before any registry lookups — the refusal is
// about WHAT the command is, not whether the spawn is registered.
const HUMAN_GATE_CMDS = new Set(['approve', 'archive', 'push', 'disposition']);

// The verdict consumed by guardCwd: does THIS command, in THIS process,
// get the runner's spawn channel? holder is the parsed .gos/.lock record
// ({pid, boot_id, starttime}); argvStage is the stage word of a commit
// call. Returns { ok: true } or { ok: false, reason, detail }.
function admitSpawnWrite(root, opts) {
  const { cmdName, argvStage, spawnId, holder, lockPath } = opts;
  if (HUMAN_GATE_CMDS.has(cmdName)) {
    return { ok: false, reason: 'human-gate', detail: `\`gos ${cmdName}\` requires a human at the terminal — the spawned session may only run its assigned stage advance` };
  }
  // The auto family enforces its own marker boundary inside its dispatcher
  // (on/off/run/disposition refuse, status stays readable) — the channel
  // passes it through untouched: no claim, no banner, no lock.
  if (cmdName === 'auto') {
    return { ok: true, passthrough: 'auto-family', entry: null };
  }
  const entry = readEntry(root, spawnId);
  if (!entry) return { ok: false, reason: 'no-entry', detail: `no live registry entry for spawn ${spawnId || '(unset)'}` };
  if (entry.kind === 'redteam') return { ok: false, reason: 'redteam-no-write', detail: 'redteam spawns never carry write authorization' };
  if (cmdName !== 'commit') return { ok: false, reason: 'not-whitelisted', detail: `command "${cmdName}" is outside the spawn channel (only the assigned commit is admitted)` };
  const want = String(entry.stage || '').toUpperCase();
  if (String(argvStage || '').toUpperCase() !== want) {
    return { ok: false, reason: 'stage-mismatch', detail: `spawn ${spawnId} is assigned stage ${want}, not "${argvStage}"` };
  }
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
  if (!claimChannel(root, spawnId)) {
    return { ok: false, reason: 'already-claimed', detail: `spawn ${spawnId} already used its one write` };
  }
  return { ok: true, entry };
}

module.exports = {
  registryDir,
  writeEntry,
  removeEntry,
  readEntry,
  claimChannel,
  admitSpawnWrite,
  procStartTime,
  ancestryPids,
};
