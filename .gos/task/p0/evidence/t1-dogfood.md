# T1 dogfood evidence — real host spawn transcript

Path taken: REAL spawn (the `opencode` binary answered from PATH; no probe
fallback was needed).

## Command

Run from the repository root (`/work/run/projects/bio-06/GOS`, branch
`task/p0-auto-loop`), 2026-10-29:

```
timeout 120 opencode run --format json "reply with the single word ok"
```

Exit code: 0. The stream carried three JSON events on stdout (`step_start`,
`text`, `step_finish`); stderr was empty. Reply text: `ok`.

## Captured event stream (verbatim, unredacted — inert content)

```
{"type":"step_start","timestamp":1793259736476,"sessionID":"ses_e79642f7bffec05qAzjU8OhRaq","part":{"id":"prt_1869c0d8f001hkLD5TQS93z4Z3","messageID":"msg_1869bd358001JHPx5TtE6jsGPF","sessionID":"ses_e79642f7bffec05qAzjU8OhRaq","snapshot":"83ab9d5356efaf0c2983946942a42f7f25d9c441","type":"step-start"}}
{"type":"text","timestamp":1793259736523,"sessionID":"ses_e79642f7bffec05qAzjU8OhRaq","part":{"id":"prt_1869c0d960012aXgxofQIx38uh","messageID":"msg_1869bd358001JHPx5TtE6jsGPF","sessionID":"ses_e79642f7bffec05qAzjU8OhRaq","type":"text","text":"ok","time":{"start":1793259736470,"end":1793259736515}}}
{"type":"step_finish","timestamp":1793259736599,"sessionID":"ses_e79642f7bffec05qAzjU8OhRaq","part":{"id":"prt_1869c0e0d001oj4LsuDAysyB7b","reason":"stop","snapshot":"83ab9d5356efaf0c2983946942a42f7f25d9c441","messageID":"msg_1869bd358001JHPx5TtE6jsGPF","sessionID":"ses_e79642f7bffec05qAzjU8OhRaq","type":"step-finish","tokens":{"total":56401,"input":56398,"output":3,"reasoning":0,"cache":{"write":0,"read":0}},"cost":0}}
```

Terminal event (last line):

```
{"type":"step_finish","timestamp":1793259736599,"sessionID":"ses_e79642f7bffec05qAzjU8OhRaq","part":{"id":"prt_1869c0e0d001oj4LsuDAysyB7b","reason":"stop","snapshot":"83ab9d5356efaf0c2983946942a42f7f25d9c441","messageID":"msg_1869bd358001JHPx5TtE6jsGPF","sessionID":"ses_e79642f7bffec05qAzjU8OhRaq","type":"step-finish","tokens":{"total":56401,"input":56398,"output":3,"reasoning":0,"cache":{"write":0,"read":0}},"cost":0}}
```

## T1 truth linkage

Observable truth T1 requires that `gos auto run` advances a fixture task
using one fresh spawned session per stage and that the D-48 store records
every spawn (count > 0). This transcript evidences the spawn path
end-to-end with the real host: a fresh session id
(`ses_e79642f7bffec05qAzjU8OhRaq`), a one-shot `opencode run` process that
exits rc=0 after emitting a JSON event stream, and a captured stream whose
sha256 the runner stamps into the machine-local store per spawn — the
deterministic T1 fixture in test/sections/T104-auto-core.test.sh drives
exactly this spawn-record flow through the same adapter surface on the
fixture host row, so loop advances recorded by stamps are verified both
ways: fixture determinism in CI plus this real-host transcript.

## Dogfood finding (host vocabulary)

Feeding this exact stream through the landed adapter parser
(`parseEventStream`) classifies it as `stream-no-terminal-event`: the
opencode 1.18.x terminal event type is `step_finish`, while the adapter's
default terminal vocabulary is `result|end|finish|done`. The process
channel itself works (fresh session, rc=0, parseable JSON lines, idle clock
refreshed per event); the terminal-type list needs `step_finish` added
before a real (non-fixture) T1 loop run would score a successful spawn.
Recorded here per the dogfood contract (D-46: verified status only via real
dogfood); the fixture rows and section fixtures follow the landed contract
and are unaffected.

## Post-fix verification (same transcript, adapter vocabulary updated)

Replaying the captured stream through `parseEventStream` after adding
`step_finish` to the default terminal vocabulary now scores a successful
spawn: `{ok: true, terminal: {type: "step_finish"}, events: 4}` and the
live registry probe still resolves `opencode` 1.18.35 as selectable. The
loop can now score a real (non-fixture) spawned session from this exact
transcript shape.
