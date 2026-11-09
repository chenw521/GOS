# Spec — Classify truncated wave sessions and stop losing committed-ready work

## Intent

Two of three wave spawns in the cycle-3 dogfood died mid-turn: the opencode
run process exited cleanly ~2s after a completed tool step, swallowing
completed work (death 1: both sections already green; the wave commit never
landed). The adapter currently classifies those streams as successful —
`step_finish` sits in DEFAULT_TERMINAL_TYPES, but opencode emits it after
every tool round, so the terminal check is vacuous and a session that ends
without a final model turn reads as a clean close. Fix the classification
and harden the wave ordering so a session death can no longer cost
commit-ready work.

## Evidence basis

- Streams a6dfc894-W1-6f0b3b37 / a6dfc894-W2-97401b83 (deaths) end at bare
  step_finish with the last consumed event a completed tool result; stream
  a6dfc894-W1-97401b83 (success) ends text -> step_finish. No wall/idle
  timeout, no deny hits, no buffer limit reached; rc clean in all three.
- Host quirk (out of GOS hands): the model occasionally emits an empty turn
  after a tool result (observed after an errored probe script and after a
  large file read); the CLI treats turn-end-without-tools as session end.
- Existing fixture hosts emit explicit `result` closers (T104:166), so the
  tightened semantics keep today's green fixtures green.

## Decisions

### D1 — Terminal semantics: a bare step_finish close is a failure, not a success

Success requires either an explicit terminal event type (result, end,
finish, done — step_finish removed from that set) or a final model turn:
the last event may be step_finish only when a text event follows the last
tool_use event. A stream whose last event is a step_finish directly after
tool events classifies as the new failure `stream-truncated-after-tool-step`
(key auto.host.streamTruncatedAfterToolStep) with the event count in the
params. This is classification-only: no kill logic changes (spawnLive
already reads to natural close); the wave driver's scoring then sees a
spawn failure instead of a false-clean rc0, which distinguishes session
death from a worker that chose not to commit.

### D2 — Wave prompt orders commit-before-probes

renderWavePrompt gains one line: commit the wave as soon as its declared
changes are complete and their checks pass; run exploratory or
discriminating probes only after the commit; if a post-commit probe fails,
stepFail with a clear error instead of continuing. The three-contract is
untouched (still exactly one commit per wave); the change only moves the
commit ahead of risk, so a mid-probe session death costs nothing (in death
1 the work was fully green at death time).

## Scope

In: bin/lib/ops/auto/adapters/opencode.cjs (parser terminal semantics),
bin/lib/ops/auto/workers.cjs (renderWavePrompt line), adapter unit tests
(truncated fails / text-final passes / explicit-result passes) and a T108
prompt assertion.

Out: any retry/resume semantics for truncated sessions (one wave one spawn
stays — a rerun policy is a breaker/family decision, deferred); host-side
model behavior; redteam streams (they have their own verdict contract).

## Observable Truths

1. parseEventStream on a truncated stream (tool_use, then step_finish last)
   fails with class stream-truncated-after-tool-step.
2. parseEventStream on a text-final stream (tool_use, text, step_finish)
   and on an explicit result closer both succeed.
3. The wave prompt render carries the commit-before-probes line and the
   wave prompt hash stamp stays self-consistent.
4. Adapter + wave sections and the full battery are green.

## Red Team record (3 rounds)

- R1 misuse: could a worker defeat D1 by emitting a trailing text event
  then dying before committing? Yes — but that shape is a legitimate quiet
  completion read as success; the no-commit scoring still catches the
  missing commit, so the failure surface stays covered (scoring, not
  classification, owns commit presence). ACCEPT.
- R2 edge: multi-tool rounds — rule keys on text-after-LAST-tool_use, so
  interleaved tool/text/tool/text rounds classify by the final turn only.
  A session ending mid-verbose-narration (text then more tools then death)
  still classifies truncated — correct, the final turn never arrived.
  ACCEPT.
- R3 completeness: fixture hosts across T104/T105/T106/T108 verified to
  emit explicit closers or plain-text verdict lines (malformed-JSON path);
  the one risk is a fixture emitting bare step_finish as its closer — the
  battery run will surface it and the fixture gets the proper closer shape.
  ACCEPT.

## Deferred

- Rerun policy for stream-truncated wave sessions (family/breaker design).
- Host-side empty-turn quirk (upstream opencode/model; GOS can only
  classify and order work defensively).
