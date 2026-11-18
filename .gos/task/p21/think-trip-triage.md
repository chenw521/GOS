# THINK breaker trip 2026-11-09T09:17Z -- triage

## Verdict

root-cause: code defect -- a stage-pointer/completed_stages desync was scored as spawn failure; bin/lib/ops/auto/loop.cjs score() counted clean rc0 sessions toward the N layer (rc0-no-advance) when the driven stage was already in completed_stages, so three healthy THINK sessions tripped the breaker; the desync itself was created upstream by a headless `gos commit think` executed while current_stage still sat at INTENT (old commit.cjs derived the pointer destination from current_stage -- already cured on 2026-11-10 by the commit-advance destination rework in bin/lib/task/commit.cjs)
evidence: .gos/task/p21/evidence/store-extract-2026-11-09.json, .gos/task/p21/evidence/spawn-tail-addc34ca-1.excerpt.txt, .gos/task/p21/evidence/git-history-2026-11-09T09-window.txt, .gos/task/p21/evidence/fixture-repro-red.txt, .gos/task/p21/evidence/fixture-green.txt
regression: T127-think-trip

## Timeline (all times UTC)

- 07:15:57 -- previous task ends: commit 0852669 `chore(task): advance done`
  leaves state at `current_stage=DONE`, all seven stages completed.
- 08:13:42 -- checkout of `dogfood/issue-57-artifact-zones` at 0852669; the
  next task ("Enforce the artifact-path contract at truth", task dir
  .gos/task/08526693/) grows from that commit. INTENT is skipped for the
  continuation task; no `advance intent` commit ever exists.
- 09:04:22 -- commit fc30294 `chore(task): advance think` lands with parent
  0852669. It was produced by a headless `gos commit think` while
  current_stage still read INTENT; the pre-2026-11-10 commit path derived
  the pointer destination as next(current_stage), so one commit did all of:
  THINK appended to completed_stages, pointer moved only INTENT -> THINK,
  spec.md + .task-head materialized. Resulting state:
  `current_stage=THINK`, `completed_stages=["THINK"]` -- the pointer names a
  stage already completed.
- 09:05:29 / 09:10:11 / 09:11:51 -- the runner re-drives THINK three times
  (spawn ids addc34ca-b254-485a-95a4-d57264ce671b-{1,2,3}, all stamped in
  the dogfood store). Every session finds the work already settled: spec.md
  committed, fc30294 at HEAD, THINK approval recorded 09:04:21.679Z; each
  refuses to fabricate a second advance (the duplicate-advance guard
  rejects `commit think` with exit 1, zero state changes) and exits clean
  with a terminal event.
- 09:17:13.875 -- three consecutive clean sessions scored rc0-no-advance ->
  breaker N layer trips: `stage=THINK: terminal ok but no new stage-labeled
  commit reachable from HEAD`.
- 09:26:23 -- manual repair: commit 1533081 (same subject, +CHANGELOG,
  state.json pointer move) unblocks the cycle; the branch was later rebased
  away (fc30294/1533081 are orphans; the squashed task landed as the
  2026-11-10 archive "enforce-the-artifact-path-cont").

## Why the loop could not escape

- The stage to drive is `taskState.current_stage` (loop.cjs, runLoop main
  loop) with no cross-check against completed_stages, so the desync state
  makes the loop re-drive THINK.
- `detectAdvance` (breaker.cjs) requires a stage-labeled commit in
  `preSpawnHead..HEAD`; fc30294 predates every re-spawn's preSpawnHead, so
  attribution can never succeed.
- score() classified the clean exit as rc0-no-advance and counted it toward
  the N layer -- three healthy sessions produced the trip. The sessions were
  not failing; the pointer was wrong.

## Fix

bin/lib/ops/auto/loop.cjs, score(): the rc0-no-advance branch now receives
`stageAlreadyCompleted` (computed by the caller from the post-spawn state
read) and pauses with reason `stage-already-advanced` instead of counting,
mirroring the existing external-mutation / advance-state-mismatch pause
pattern for loop-unfixable inconsistencies. Failure-signal paths (deny
hits, non-zero exits, timeouts, adapter failures) are untouched: a real
failing session against a desynced pointer still counts, exactly as
T104-auto-core case c24 asserts. The runner-driven exit-spawn channel
(script stages) keeps its existing behavior: its `gos commit <stage>`
refusal carries the duplicate-advance stderr in the scored detail, which is
diagnosable without misattribution.

The upstream desync producer (pointer destination derived from
current_stage) was already cured on 2026-11-10 by the commit-advance
destination rework (destination = next(committed stage), adjacency guard,
canonical completed backfill); this fix closes the loop-side exposure for
any state that reaches a runner already desynced (crash windows, hand
repair, legacy stores).

## Reproduction

test/sections/T127-think-trip.test.sh drives the loop module against a
fixture state with the exact fc30294 shape (current_stage=THINK,
completed_stages=["THINK"], THINK approval recorded) and a spawn harness
that mirrors the field sessions (clean rc0 + terminal event, no new
commit). Pre-fix the fixture reproduces the 09:17 signature verbatim:
`paused|breaker-tripped`, 3 spawns / 3 iterations, store counters
spawnCount=3 tripCount=1 (fixture-repro-red.txt). Post-fix the loop pauses
after the first clean session: `paused|stage-already-advanced`, 1 spawn,
tripCount=0 (fixture-green.txt). Boundary cases guard against over-fire: a
healthy THINK pointer over INTENT-completed still advances, and a terminal
DONE pointer (DONE legally in completed_stages) still ends done.

## Results

- T127-think-trip: 5/5 green.
- T104-auto-core: 93/93 green (includes c24, whose failing-leg-counts-into-N
  assertion the fix preserves).
- T105-auto-depth 33/33, T106-auto-spawn-channel 38/38,
  T107-auto-dispatch 76/76, T108-auto-wave-contracts 63/63 green.
- T25-map-selfcheck and T46-module-structure are red from concurrent
  same-day work outside this change (new file bin/lib/ops/branch-reap.cjs
  and function-count drift in decisions/workers/gate/loop detach code owned
  by other in-flight edits); the two hunks of this change add no functions
  or arrow constructs.
