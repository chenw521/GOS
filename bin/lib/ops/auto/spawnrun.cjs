// ops/auto/spawnrun — the one async spawn runner for the auto family: an
// event-loop-alive child process under composable supervision options. The
// idle killer (reset on every stream chunk) kills a stalled stream live;
// the wall killer bounds the total run; the streaming deny scanner catches
// deny lines before any capture window can truncate them away; the head and
// tail dual-window capture keeps both ends of an arbitrarily long stream
// with sha256 stamps and total byte counts riding the result payload.
// loop.cjs and redteam.cjs compose this module — detached child
// composition lives here and nowhere else in the auto family.
// The child-tracking registry holds every spawned child from the spawn
// call until its run settles, so a runner shutting down can still reach
// the children it started.
'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const { spawn: spawnChild } = require('node:child_process');

const limits = require('./limits.cjs');
const launcher = require('./launcher.cjs');

// Default dual-window capture sizes: head and tail bytes kept per stream
// beside the full (capped) captured text.
const DEFAULT_HEAD_BYTES = 256 * 1024;
const DEFAULT_TAIL_BYTES = 1024 * 1024;

// Bounded byte window over raw chunks: head keeps the first `bytes` bytes,
// tail keeps the last `bytes` bytes.
function headWindow(bytes) {
  let buf = Buffer.alloc(0);
  return {
    push(chunk) {
      const remaining = bytes - buf.length;
      if (remaining <= 0) return;
      buf = Buffer.concat([buf, chunk.subarray(0, remaining)]);
    },
    get() { return buf; },
  };
}

function tailWindow(bytes) {
  let buf = Buffer.alloc(0);
  return {
    push(chunk) {
      buf = Buffer.concat([buf, chunk]);
      if (buf.length > bytes) buf = buf.subarray(buf.length - bytes);
    },
    get() { return buf; },
  };
}

function sha256Buffer(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

// Child-tracking registry: one entry per child spawnRun has alive, from the
// spawn call until the run settles. An entry carries the child's /proc
// starttime, so a sweep can tell the original child from an unrelated
// process that reused the pid. spawnDetached is not tracked: it starts the
// runner itself, never a suite child. Nothing here writes spawnreg docs.
//   entry  { spawnId, pid, starttime } keyed by spawnId; a spec without a
//           spawnId is keyed by its pid as a string; starttime is null when
//           /proc could not be read at spawn time
const tracked = {
  byId: new Map(),

  // /proc/<pid>/stat from the state field on, as an array: index 0 is the
  // state, 2 the process group, 19 the starttime. The comm field may hold
  // spaces and parentheses, so the split starts after the LAST ')'. Returns
  // null when the pid is gone or /proc is unreadable.
  fields(pid) {
    try {
      const raw = fs.readFileSync(`/proc/${pid}/stat`, 'utf8');
      return raw.slice(raw.lastIndexOf(')') + 2).split(' ');
    } catch { return null; }
  },

  // Process group of this process, or null when /proc is unreadable.
  ownPgrp() {
    const own = tracked.fields(process.pid);
    const pgrp = own ? Number(own[2]) : NaN;
    return Number.isInteger(pgrp) ? pgrp : null;
  },

  // Registry key for a spawn: the spawnId when one is given, else the pid
  // as a string. Returns null when the pid is not a positive integer other
  // than this process's own.
  keyOf(spawnId, pid) {
    if (!Number.isInteger(pid) || pid <= 0 || pid === process.pid) return null;
    const id = spawnId == null ? '' : String(spawnId);
    return id ? id : String(pid);
  },

  // Puts one entry into the registry slot `id`, replacing whatever the slot
  // held. Returns the entry.
  write(id, pid, starttime) {
    const entry = { spawnId: id, pid, starttime };
    tracked.byId.set(id, entry);
    return entry;
  },

  // Records a freshly spawned child. Returns the entry, or null when the
  // pid cannot be a registry key.
  add(spawnId, pid) {
    const id = tracked.keyOf(spawnId, pid);
    if (!id) return null;
    const starttime = Number((tracked.fields(pid) || [])[19]);
    return tracked.write(id, pid, Number.isInteger(starttime) && starttime > 0 ? starttime : null);
  },

  // Forgets `entry` when it still occupies its registry slot. A later spawn
  // under the same id has replaced the slot by then, so the match is by
  // identity and the later child stays tracked.
  release(entry) {
    if (entry && tracked.byId.get(entry.spawnId) === entry) tracked.byId.delete(entry.spawnId);
  },

  // Copy of the live entries, oldest registration first.
  snapshot() {
    return [...tracked.byId.values()].map((e) => ({ spawnId: e.spawnId, pid: e.pid, starttime: e.starttime }));
  },

  // Test seam: sets the entry for `spawnId` to the given { pid, starttime }
  // so a sweep can be driven against a chosen identity. An occupied slot is
  // updated in place, which keeps the entry the owning run will release.
  // A missing or non-positive starttime records null. Returns a verdict:
  // { ok: true, entry } or { ok: false, reason, detail }.
  registerForTest(spawnId, rec) {
    const r = rec && typeof rec === 'object' ? rec : {};
    const id = typeof spawnId === 'string' && spawnId ? spawnId : null;
    if (!id) return { ok: false, reason: 'invalid-spawn-id', detail: 'spawnId must be a non-empty string' };
    const pid = r.pid;
    if (!Number.isInteger(pid) || pid <= 0) return { ok: false, reason: 'invalid-pid', detail: 'pid must be a positive integer' };
    if (pid === process.pid) return { ok: false, reason: 'own-pid', detail: 'the registry never holds its own process' };
    const entry = tracked.byId.get(id) || { spawnId: id, pid: 0, starttime: null };
    entry.pid = pid;
    entry.starttime = Number.isInteger(r.starttime) && r.starttime > 0 ? r.starttime : null;
    tracked.byId.set(id, entry);
    return { ok: true, entry: { spawnId: entry.spawnId, pid: entry.pid, starttime: entry.starttime } };
  },

  // Outcome of one signal delivery: { ok, gone, code }. No error means
  // delivered; a target that is already absent (ESRCH) counts as delivered
  // and gone; any other failure is reported through code.
  outcome(e) {
    if (!e) return { ok: true, gone: false, code: null };
    const gone = e.code === 'ESRCH';
    return { ok: gone, gone, code: e.code || String(e) };
  },

  // Delivers SIGKILL to process group `pid`, which must be a group leader.
  killGroup(pid) {
    try {
      process.kill(-pid, 'SIGKILL');
      return tracked.outcome(null);
    } catch (e) { return tracked.outcome(e); }
  },

  // Delivers SIGKILL to the single process `pid`.
  killPid(pid) {
    try {
      process.kill(pid, 'SIGKILL');
      return tracked.outcome(null);
    } catch (e) { return tracked.outcome(e); }
  },

  // Kills every tracked child that is alive and still carries its recorded
  // starttime. A child is signalled as a process group only when it leads
  // a group other than this process's own; a child anywhere else is
  // signalled by pid alone, so no other group is ever reached. Returns
  // { killed, skipped, pidOnly }:
  //   killed   { spawnId, pid } per signalled child, with mode 'pid-only'
  //            when signalled by pid, or gone true when it had already left
  //   skipped  { spawnId, pid, reason } per entry left alone
  //   pidOnly  { spawnId, pid, reason, pgrp } per child signalled by pid
  sweep() {
    const killed = [];
    const skipped = [];
    const pidOnly = [];
    const own = tracked.ownPgrp();
    for (const entry of tracked.snapshot()) {
      const pid = entry.pid;
      const name = { spawnId: entry.spawnId, pid };
      if (!Number.isInteger(pid) || pid <= 0 || pid === process.pid) {
        skipped.push({ ...name, reason: 'invalid-pid' });
        continue;
      }
      const fields = tracked.fields(pid);
      if (!fields) {
        skipped.push({ ...name, reason: 'pid-dead' });
        continue;
      }
      if (!Number.isInteger(entry.starttime) || entry.starttime !== Number(fields[19])) {
        skipped.push({ ...name, reason: 'starttime-mismatch' });
        continue;
      }
      const pgrp = Number(fields[2]);
      const leader = pgrp === pid;
      const asGroup = leader && own !== null && pgrp !== own;
      const sent = asGroup ? tracked.killGroup(pid) : tracked.killPid(pid);
      if (!sent.ok) {
        skipped.push({ ...name, reason: 'kill-failed', detail: sent.code });
        continue;
      }
      if (asGroup) {
        killed.push(sent.gone ? { ...name, gone: true } : name);
        continue;
      }
      pidOnly.push({ ...name, reason: leader ? 'own-process-group' : 'not-group-leader', pgrp });
      killed.push({ ...name, mode: 'pid-only' });
    }
    return { killed, skipped, pidOnly };
  },
};

// Run one spawned session and resolve the spawnSync shape the scorer
// consumes (status/stdout/stderr/error), extended with:
//   preTruncationDenyHits  deny hits matched as the stream arrived
//   totalBytes             { stdout, stderr } raw byte counts, pre-cap
//   windowHead/windowTail  { stdout, stderr } bounded head/tail buffers
//   windowSha256s          { stdout: { head, tail }, stderr: { head, tail } }
// spec: { argv, cwd, env, deny, spawnId } — the composed spawn; spawnId is
// the registry key of the child while the run is alive (the pid when the
// spec carries none). opts (all optional):
//   idleMs   idle killer, reset on every stdout/stderr chunk
//   wallMs   wall killer bounding the total run
//   deny     deny patterns for the streaming scanner (spec.deny wins)
//   windows  { headBytes, tailBytes } capture-window override
function spawnRun(spec, opts = {}) {
  const argv = spec && Array.isArray(spec.argv) ? spec.argv : null;
  if (!argv || argv.length === 0) {
    return Promise.resolve({ status: null, stdout: '', stderr: '', error: new Error('spawn called without argv') });
  }
  const o = opts || {};
  const winOpts = o.windows != null && typeof o.windows === 'object' && !Array.isArray(o.windows) ? o.windows : {};
  const headBytes = positiveInt(winOpts.headBytes) || DEFAULT_HEAD_BYTES;
  const tailBytes = positiveInt(winOpts.tailBytes) || DEFAULT_TAIL_BYTES;
  const deny = Array.isArray(spec.deny) ? spec.deny : (Array.isArray(o.deny) ? o.deny : undefined);

  return new Promise((resolve) => {
    let child;
    try {
      child = spawnChild(argv[0], argv.slice(1), {
        cwd: spec.cwd,
        env: spec.env,
        detached: true,
        stdio: ['ignore', 'pipe', 'pipe'],
      });
    } catch (e) {
      resolve({ status: null, stdout: '', stderr: '', error: e instanceof Error ? e : new Error(String(e)) });
      return;
    }
    const trackedEntry = tracked.add(spec.spawnId, child.pid);
    const cap = limits.SPAWN_MAX_BUFFER;
    let out = '';
    let err = '';
    let idleTimer = null;
    let wallTimer = null;
    let killed = null;
    let settled = false;
    const capOut = { head: headWindow(headBytes), tail: tailWindow(tailBytes), total: 0 };
    const capErr = { head: headWindow(headBytes), tail: tailWindow(tailBytes), total: 0 };
    // Deny lines are detected as they stream in — before the capture window
    // can truncate them away — and ride on the result for the scorer.
    const denyScanner = launcher.makeStreamDenyScanner({ deny });
    // Channel responder tick: while the spawn lives, the runner periodically
    // answers request files the spawned side drops into its scratch. A
    // responder error never kills the spawn — the spawned side still fails
    // closed on its own wait budget.
    const ackTick = typeof o.ackTick === 'function' ? o.ackTick : null;
    let ackTimer = null;
    if (ackTick) {
      ackTimer = setInterval(() => { try { ackTick(); } catch { /* responder sweep is best effort */ } }, 250);
      if (typeof ackTimer.unref === 'function') ackTimer.unref();
    }
    const finish = (payload) => {
      if (settled) return;
      settled = true;
      tracked.release(trackedEntry);
      if (idleTimer) clearTimeout(idleTimer);
      if (wallTimer) clearTimeout(wallTimer);
      if (ackTimer) clearInterval(ackTimer);
      denyScanner.flush();
      payload.preTruncationDenyHits = denyScanner.hits.slice();
      payload.totalBytes = { stdout: capOut.total, stderr: capErr.total };
      payload.windowHead = { stdout: capOut.head.get(), stderr: capErr.head.get() };
      payload.windowTail = { stdout: capOut.tail.get(), stderr: capErr.tail.get() };
      payload.windowSha256s = {
        stdout: { head: sha256Buffer(capOut.head.get()), tail: sha256Buffer(capOut.tail.get()) },
        stderr: { head: sha256Buffer(capErr.head.get()), tail: sha256Buffer(capErr.tail.get()) },
      };
      resolve(payload);
    };
    const kill = (why) => {
      if (killed) return;
      killed = why;
      try { process.kill(-child.pid, 'SIGKILL'); } catch { /* group gone */ try { child.kill('SIGKILL'); } catch { /* already gone */ } }
    };
    const armIdle = () => {
      if (idleTimer) clearTimeout(idleTimer);
      const ms = positiveInt(o.idleMs);
      if (!ms) return;
      idleTimer = setTimeout(() => kill('idle'), ms);
      if (typeof idleTimer.unref === 'function') idleTimer.unref();
    };
    child.stdout.on('data', (d) => {
      out += d;
      if (out.length > cap) out = out.slice(out.length - cap);
      denyScanner.feed(d);
      capOut.head.push(d);
      capOut.tail.push(d);
      capOut.total += d.length;
      armIdle();
    });
    child.stderr.on('data', (d) => {
      err += d;
      if (err.length > cap) err = err.slice(err.length - cap);
      denyScanner.feed(d);
      capErr.head.push(d);
      capErr.tail.push(d);
      capErr.total += d.length;
      armIdle();
    });
    const wallMs = positiveInt(o.wallMs);
    if (wallMs) {
      wallTimer = setTimeout(() => kill('wall'), wallMs);
      if (typeof wallTimer.unref === 'function') wallTimer.unref();
    }
    armIdle();
    child.on('error', (e) => finish({ status: null, stdout: out, stderr: err, error: e }));
    child.on('close', (code) => {
      if (killed === 'idle') finish({ status: null, stdout: out, stderr: err, error: Object.assign(new Error('spawn idle timeout'), { idle: true, killed: true }) });
      else if (killed === 'wall') finish({ status: null, stdout: out, stderr: err, error: Object.assign(new Error('spawn wall timeout'), { killed: true }) });
      else finish({ status: code, stdout: out, stderr: err });
    });
  });
}

// Fire-and-forget detached child (the `auto run --detach` entry): the child
// survives its parent; stdio is the caller's concern (typically an opened
// log fd). Returns the child handle, unref'd unless opts.unref === false.
function spawnDetached(command, args, opts = {}) {
  const child = spawnChild(command, args, {
    cwd: opts.cwd,
    env: opts.env,
    detached: true,
    stdio: opts.stdio || 'ignore',
  });
  if (opts.unref !== false) child.unref();
  return child;
}

function positiveInt(v) {
  const n = Number(v);
  return Number.isInteger(n) && n > 0 ? n : 0;
}

module.exports = {
  DEFAULT_HEAD_BYTES,
  DEFAULT_TAIL_BYTES,
  spawnRun,
  spawnDetached,
  trackedChildren: () => tracked.snapshot(),
  killTrackedChildren: () => tracked.sweep(),
  registerTrackedForTest: (spawnId, rec) => tracked.registerForTest(spawnId, rec),
};
