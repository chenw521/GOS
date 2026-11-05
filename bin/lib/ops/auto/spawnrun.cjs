// ops/auto/spawnrun — the one async spawn runner for the auto family: an
// event-loop-alive child process under composable supervision options. The
// idle killer (reset on every stream chunk) kills a stalled stream live;
// the wall killer bounds the total run; the streaming deny scanner catches
// deny lines before any capture window can truncate them away; the head and
// tail dual-window capture keeps both ends of an arbitrarily long stream
// with sha256 stamps and total byte counts riding the result payload.
// loop.cjs and redteam.cjs compose this module — detached child
// composition lives here and nowhere else in the auto family.
'use strict';

const crypto = require('node:crypto');
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

// Run one spawned session and resolve the spawnSync shape the scorer
// consumes (status/stdout/stderr/error), extended with:
//   preTruncationDenyHits  deny hits matched as the stream arrived
//   totalBytes             { stdout, stderr } raw byte counts, pre-cap
//   windowHead/windowTail  { stdout, stderr } bounded head/tail buffers
//   windowSha256s          { stdout: { head, tail }, stderr: { head, tail } }
// spec: { argv, cwd, env, deny } — the composed spawn. opts (all optional):
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
};
