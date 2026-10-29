// ops/auto/adapters/codex — codex host adapter (display-only).
//
// Status: fixture-tested. The exec JSONL event shapes below are validated
// against recorded fixtures only — this adapter exposes NO live spawn path
// (spawn() always returns the classified display-only refusal). It becomes
// spawn-capable only after a dogfood run re-verifies the event contract and
// the registry matrix row flips to verified+selectable.
//
// Stream contract mirrors the opencode adapter: events parse as JSON lines,
// a terminal event closes the stream, malformed JSON or a missing terminal
// event is a classified failure, never a crash.
'use strict';

const NAME = 'codex';
const SPAWN_MODE = 'display-only';
const DISPLAY_ONLY = true;

// Terminal shapes recorded from codex exec JSONL output.
const TERMINAL_TYPES = ['turn.completed', 'thread.completed'];

// Recorded fixtures (host output captured out-of-band; the display surfaces
// and the matrix gating tests parse exactly these shapes).
const RECORDED_FIXTURES = [
  {
    name: 'exec-jsonl-basic',
    text: [
      '{"type":"item.started","item":{"type":"agentMessage"}}',
      '{"type":"item.completed","item":{"type":"agentMessage","text":"ok"}}',
      '{"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":5}}',
    ].join('\n'),
  },
  {
    name: 'exec-jsonl-no-terminal',
    text: [
      '{"type":"item.started","item":{"type":"agentMessage"}}',
      '{"type":"item.completed","item":{"type":"agentMessage","text":"partial"}}',
    ].join('\n'),
  },
];

function parseFixture(text) {
  const events = [];
  let terminal = null;
  let failure = null;
  let lastEventAt = null;
  for (const line of String(text == null ? '' : text).split(/\r?\n/)) {
    const raw = line.trim();
    if (!raw) continue;
    let ev;
    try {
      ev = JSON.parse(raw);
    } catch {
      if (!failure) {
        failure = { class: 'stream-malformed-json', key: 'auto.host.streamMalformed', params: { line: raw.slice(0, 120) }, message: `malformed JSON event line: ${raw.slice(0, 120)}` };
      }
      continue;
    }
    events.push(ev);
    lastEventAt = Date.now();
    if (!terminal && TERMINAL_TYPES.includes(ev.type)) terminal = ev;
  }
  if (!terminal && !failure) {
    failure = { class: 'stream-no-terminal-event', key: 'auto.host.streamNoTerminal', params: { count: events.length }, message: `event stream ended without a terminal event (types: ${TERMINAL_TYPES.join(', ')}; parsed ${events.length} event(s))` };
  }
  return { ok: !failure, terminal, events, eventCount: events.length, lastEventAt, failure };
}

// Validate a candidate stream against the recorded fixture shapes; with no
// argument, runs every recorded fixture and reports each verdict (used by
// status surfaces to show fixture health).
function validateFixture(text) {
  if (text === undefined) {
    return RECORDED_FIXTURES.map((f) => ({ name: f.name, ...parseFixture(f.text) }));
  }
  return parseFixture(text);
}

// Display-only refusal: never spawns, never throws.
function spawn() {
  return {
    ok: false,
    rc: null,
    spec: null,
    failure: {
      class: 'display-only',
      key: 'auto.host.displayOnly',
      params: { host: NAME },
      message: `host '${NAME}' is display-only in this release (matrix status fixture-tested) — not selectable for spawns`,
    },
  };
}

module.exports = { NAME, SPAWN_MODE, DISPLAY_ONLY, TERMINAL_TYPES, RECORDED_FIXTURES, validateFixture, spawn };
