// ops/auto/adapters/opencode — opencode host adapter (spawn + event stream).
//
// Adapter contract (channel-agnostic, frozen at three capabilities):
// 1. spawn spec — buildSpawnSpec(opts) returns { argv, env } describing ONE
//    fresh host session. Adapters never reuse or resume a prior session:
//    every call builds argv/env from scratch and the spawned host process is
//    one-shot (`opencode run` exits with the stage result).
// 2. outcome stream — createEventParser()/parseEventStream() classify a JSON
//    event stream into { ok, terminal, failure }. A stream with no terminal
//    event, or containing malformed JSON, is a classified failure — the
//    parser never throws. Every successfully parsed event refreshes the idle
//    clock (lastEventAt) the caller reads for output-idle timeouts.
// 3. probe inputs — the registry owns capability negotiation; this module
//    contributes the spawn surface (argv shape, flags, config env) the
//    matrix row's probe steps verify.
'use strict';

const { spawnSync } = require('child_process');
const registryMod = require('./registry.cjs');

const NAME = 'opencode';
const SPAWN_MODE = 'opencode-run-json';
const DEFAULT_SPAWN_TIMEOUT_MS = 60 * 60 * 1000;
const SPAWN_MAX_BUFFER = 64 * 1024 * 1024;

// Terminal event shapes: an event whose `type` is listed here, or one that
// carries `terminal: true`, closes the stream successfully.
const DEFAULT_TERMINAL_TYPES = ['result', 'end', 'finish', 'done', 'step_finish'];

function isTerminalEvent(ev, terminalTypes) {
  if (!ev || typeof ev !== 'object') return false;
  if (ev.terminal === true) return true;
  return terminalTypes.includes(ev.type);
}

// ---------- outcome stream parsing ----------

// Incremental parser. feed(line) per streamed line (live as lines arrive —
// each parsed event refreshes lastEventAt at feed time); finish() at stream
// close classifies the whole run. Malformed lines set a failure but never
// throw; parsing continues so the capture stays honest.
function createEventParser(opts) {
  const o = opts || {};
  const terminalTypes = Array.isArray(o.terminalTypes) ? o.terminalTypes : DEFAULT_TERMINAL_TYPES;
  const state = { events: [], terminal: null, failure: null, lastEventAt: null };

  function feed(line) {
    const raw = String(line == null ? '' : line).trim();
    if (!raw) return { event: null };
    let ev;
    try {
      ev = JSON.parse(raw);
    } catch (e) {
      if (!state.failure) {
        state.failure = {
          class: 'stream-malformed-json',
          key: 'auto.host.streamMalformed',
          params: { line: raw.slice(0, 120) },
          message: `malformed JSON event line (never a crash): ${raw.slice(0, 120)}`,
        };
      }
      return { event: null, error: e && e.message };
    }
    state.events.push(ev);
    state.lastEventAt = Date.now();
    if (!state.terminal && isTerminalEvent(ev, terminalTypes)) state.terminal = ev;
    return { event: ev };
  }

  function finish() {
    if (!state.terminal && !state.failure) {
      state.failure = {
        class: 'stream-no-terminal-event',
        key: 'auto.host.streamNoTerminal',
        params: { count: state.events.length },
        message: `event stream ended without a terminal event (types: ${terminalTypes.join(', ')}; parsed ${state.events.length} event(s))`,
      };
    }
    return {
      ok: !state.failure,
      terminal: state.terminal,
      events: state.events,
      eventCount: state.events.length,
      lastEventAt: state.lastEventAt,
      failure: state.failure,
    };
  }

  return { feed, finish, lastEventAt: () => state.lastEventAt, eventCount: () => state.events.length, terminal: () => state.terminal };
}

// Batch wrapper: full captured stream text → classified outcome. Pure —
// testable without any spawn.
function parseEventStream(text, opts) {
  const parser = createEventParser(opts);
  for (const line of String(text == null ? '' : text).split(/\r?\n/)) parser.feed(line);
  return parser.finish();
}

// ---------- spawn ----------

// Fresh-session spawn spec: `opencode run --format json <prompt>` with a
// scratch env. No session id, no resume flag — each spec is a new session.
// The env base is a sanitized copy of process.env (credential classes
// stripped; model-provider auth survives) with the caller's opts.env
// overlays applied last. opts: { prompt, args?, env?, cwd? } — extra args
// land verbatim between the flags and the prompt (e.g. ['--model', '<id>']).
function buildSpawnSpec(opts) {
  const o = opts || {};
  const argv = ['opencode', 'run', '--format', 'json'];
  for (const a of Array.isArray(o.args) ? o.args : []) argv.push(String(a));
  if (o.prompt != null && o.prompt !== '') argv.push(String(o.prompt));
  const env = Object.assign({}, registryMod.sanitizedSpawnEnv(process.env), o.env || {});
  return { argv, env, cwd: o.cwd || process.cwd() };
}

// Live spawn: runs the spec, parses the captured stdout stream. Returns a
// classified outcome — spawn errors, timeouts, malformed streams, and
// missing terminal events are failures, never throws. opts.run injectable
// for tests (signature run(spec, spawnOpts) → { status, stdout, stderr,
// error }).
function spawnLive(opts) {
  const o = opts || {};
  const spec = buildSpawnSpec(o);
  const spawnOpts = {
    cwd: spec.cwd,
    env: spec.env,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: o.timeoutMs || DEFAULT_SPAWN_TIMEOUT_MS,
    maxBuffer: SPAWN_MAX_BUFFER,
  };
  let r;
  try {
    r = (o.run || ((s, so) => spawnSync(s.argv[0], s.argv.slice(1), so)))(spec, spawnOpts);
  } catch (e) {
    return { ok: false, rc: null, spec, failure: { class: 'spawn-error', key: 'auto.host.spawnError', params: { host: NAME }, message: `opencode spawn exception: ${e && e.message}` } };
  }
  if (!r || r.error) {
    const msg = r && r.error ? r.error.message : 'no spawn result';
    return { ok: false, rc: r ? r.status : null, spec, failure: { class: 'spawn-error', key: 'auto.host.spawnError', params: { host: NAME }, message: `opencode spawn error: ${msg}` } };
  }
  const outcome = parseEventStream(String(r.stdout || ''), { terminalTypes: o.terminalTypes });
  return {
    ok: outcome.ok,
    rc: r.status,
    spec,
    terminal: outcome.terminal,
    events: outcome.events,
    eventCount: outcome.eventCount,
    lastEventAt: outcome.lastEventAt,
    failure: outcome.failure,
  };
}

module.exports = {
  NAME,
  SPAWN_MODE,
  DEFAULT_TERMINAL_TYPES,
  buildSpawnSpec,
  createEventParser,
  parseEventStream,
  spawnLive,
};
