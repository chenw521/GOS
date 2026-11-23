# Spec: Restart-safe auto loop (SIGTERM run record + live VERIFY pin)

> **Date**: 2026-11-20 | **Level**: Lv3 | **Status**: Draft

## Goal

Make the auto loop survive a mid-VERIFY SIGTERM and restart: the killed run
leaves a run record, spawned suite children die with the runner, and the
VERIFY pin worktree stays usable through the sections-suite window so the
restarted run can reach a green record end to end.

## Motivation

The p21 dogfood cycle (2026-11-20) killed a detached runner mid-VERIFY and
exposed two defects that block the green-cycle acceptance:

- The killed run (runTag 15f78531) left NO run record — the exception-record
  route covers in-process throws only, and OS signal termination bypasses
  both the catch and the finally (seed cleanup, pin recycle, lock release).
- The restarted run (runTag 9a07a154) died on its OWN pin: the gate leg
  passed, the sections suite passed, then the truth leg read the pin
  worktree as dead (`.git/worktrees/9a07a154-pin` unresolvable). Two
  consecutive failures tripped breaker layer N and paused the loop.

Evidence: dogfood store runRecords (timing shows the pin died inside the
sections window, twice, within one run); stamps proving the killed run's
suite spawn survived the kill and ran concurrently with the restarted run's
suite; bwrap experiments refuting three candidate kill mechanisms (masked
prune reaps nothing, basename-collision adds suffix cleanly). The exact
metadata killer is unidentified — the cure is deliberately killer-agnostic.

## Requirements (R-NN)

- **R-01**: Restart-safe auto loop: persist a run record on SIGTERM (signal
  route bypasses the exception record) and keep the VERIFY pin worktree
  live across kill/restart (dogfood 9a07a154-pin incident).
- **R-31**: A SIGTERM'd detached auto run leaves a killed run record in the
  store (endState killed, accumulated stage outcomes) and releases the run
  lock before exiting.
- **R-32**: Pin legs survive a mid-suite pin death: the dead worktree
  re-materializes once per load at the recorded commit with treeSha
  re-verified; liveness telemetry brackets the suite window.
- **R-33**: A SIGTERM'd runner terminates its spawned suite children
  (process-group kill); stray pins and sections-tree registrations recycle
  at the next run start under the run lock.
- **R-34**: The section suite runs a simulated dogfood cycle: real --fg
  runner on a fixture store, scripted mid-VERIFY SIGTERM, restart,
  green-record assert.

## Approach

### Selected Approach

Three coordinated changes to `bin/lib/ops/auto/` plus one new section:

1. **Signal handler** (`loop.cjs`): install signal handlers in runLoop.
   Hard constraints (red-team R1+R2, all code-enforced):
   - Coverage: SIGTERM, SIGHUP, SIGINT — one handler, one-shot latch
     (module-level boolean; after first entry all further signals are
     ignored until process.exit completes), synchronous code only (no
     await), endState `killed` carries the signal name, exit code
     128+signum.
   - Lifecycle: handlers install only after the run lock is acquired and
     the runner state is ready; every normal exit route disarms them
     before entering teardown. Pre-lock and post-disarm signals take
     default behavior (a teardown-window SIGTERM must never append a
     killed record after a real end record or flip a completed run).
   - Runner state: a runLoop-scoped shared object
     `{runId, runTag, taskId, stageOutcomes, inFlight}` replaces the
     drive()-closure persistRunRecord; scriptIteration updates `inFlight`
     synchronously at each step boundary; the handler serializes
     stageOutcomes plus the in-flight stage entry (completed steps only,
     each with a status from the CLOSED enum passed/failed/refused —
     store.cjs:110 re-validates every record on every load, so an
     invented status string bricks the whole store; unstarted steps are
     simply absent).
   - Order: kill tracked children FIRST, then write the record, then
     exit via process.exit so the run-lock exit hook releases the lock
     (store.cjs:1188 — R-31's release path, asserted by the section).
   - Child tracking lives in spawnrun.cjs itself: a module-level
     registry `{spawnId → {pid, starttime}}` written at spawn time,
     covering ALL THREE spawn sites (loop.cjs:378 main/script,
     workers.cjs:1175 build waves, redteam.cjs:154 red-team rounds) —
     never written into the spawnreg entry doc (settleClaim rewrites
     entry docs, spawnreg.cjs:210 — a child_pid field there would race
     and resurrect uses). The handler kills only entries whose pid is
     alive AND whose recorded starttime still matches /proc (pid reuse
     protection, procStartTime pattern spawnreg.cjs:287) —
     `kill(-child_pid, 'SIGKILL')` (spawns are detached:true,
     spawnrun.cjs:80, own group leaders; SIGKILL because a suite's EXIT
     trap can drag out SIGTERM). Unmatched entries are skipped and named
     in telemetry.
   - The handler NEVER signals a process group it does not lead: it
     verifies group-leader identity first; a non-leader (`--fg` inherits
     the caller's pgid) degrades to tracked-pid kill + self-exit only.
   - The record write passes an explicit small `waitMs` through the
     mutate opts (writeRunRecord currently takes no opts — store.cjs:990;
     the signature gains an opts passthrough), checks the returned status
     (store-busy is data, not a throw, store.cjs:674), and on failure
     appends an append-only ndjson sidecar
     (`<storeRoot>/runrecords-drop.ndjson`). The sidecar is DRAINED at
     the next run start (under the lock, before drive): each line is
     runRecordRejection-validated, qualifying records append to
     runRecords flagged `droppedRecord: true`, invalid lines move to
     `runrecords-drop.corrupt.ndjson`, the file is truncated — a lost
     record is never silent AND never invisible to the re-enable gate.
     `persistRunRecord` is hoisted from `drive()` scope; the whole
     handler is try/catch-bounded to `process.exit`.
2. **Pin self-heal + telemetry** (`workers.cjs` + `loop.cjs`): when a pin
   load fails with an unresolvable/tampered worktree AND the store record
   still exists, heal and retry the load — with these hard constraints
   (red-team R1+R2):
   - Trust anchor is the RUNNER, not the store record: the heal proceeds
     only if `rec.loopStartCommit` equals the runner's in-memory
     `loopStartCommit` (loop.cjs:909) AND a fresh `rev-parse
     <loopStartCommit>^{tree}` at the live repo root equals `rec.treeSha`.
     The store record is a locating index, never a trust source — a
     poisoned record must fail closed, not materialize attacker code.
   - The heal has exactly ONE choke point: `loadPinnedModuleWithHeal({expectedLoopStartCommit,
     budget})` — both call sites (the Class P step path loop.cjs:1583 and
     the delegated-leg loadLeg loop.cjs:925) route through it and the
     per-run quota is accounted there (the dogfood incident died on the
     Class P truth leg — a heal landing on only one path would leave the
     main scenario dead).
   - The heal is a composite of existing primitives only:
     `recyclePin(rootDir, runTag)` then `materializePin(rootDir,
     {loopStartCommit, runTag: <same tag>})` — recyclePin's remove
     --force → rmSync → prune chain already covers half-dead metadata
     (workers.cjs:720-729), and materializePin rewrites the record's
     path/treeSha so a stale-path record cannot burn the quota in a loop.
     No hand-rolled re-materialize path.
   - The heal quota is per RUN (pinState counts heals; cap 2 per run;
     exceed → fail closed + telemetry names it), not per load — `.git` is
     sandbox-writable, so a deterministic deleter must not farm a
     worktree-add per leg load.
   - Run-start stray recycle runs under the run lock and PAUSES (guidance,
     no sweep) when the lock was taken over from a holder whose takeover
     reason is not dead-pid and whose pid is still alive. This requires
     `acquireRunLock`'s success return to carry `tookOver: {pid,
     hostname, reason}` (the run-lock break path currently records only a
     breaker event — store.cjs:1156-1164 — unlike the mutate lock's
     takeover field at store.cjs:662).
   - The run-start sections-tree sweep is spawnreg-driven: no global
     canonical testBase exists (each suite spawn's testbed is per-spawn,
     workers.cjs:334), so suite spawns record their testBase in the
     spawnreg entry (`test_base`), and the run-start sweep iterates STRAY
     spawnreg entries — per entry, sweepSectionWorktrees with that
     entry's testBase, then one worktree prune. The rm path stays
     code-gated on a non-empty per-entry testBase; bare prefix matching
     never rm's anything. The same run-start sweep removes stale
     auto-seed-* directories (the finally's seed cleanup is skipped by
     process.exit — each kill would otherwise leak one under .gos/cache).
   - Pin-liveness probes (metadata dir existence) log around each Class S
     step. `gos auto status` renders a latest-run line (endState.status,
     droppedRecord and heal counts) so the whole survival path is
     operator-visible without hand-reading store.json.
3. **Simulated dogfood section** (`test/sections/`): fixture repo + fixture
   store (XDG-overridden), real `gos auto run --fg` runner, scripted
   mid-VERIFY SIGTERM, restart, assert the killed record exists and the
   restarted run reaches a green record with pin legs passing. Hard
   constraints (red-team R1+R2):
   - A checks script forbids THE DOGFOOD SECTION ONLY (matched by
     filename) from requiring `bin/lib/ops/auto/{loop,workers}.cjs`
     directly — the real runner is only reachable as a subprocess via
     the CLI. (A blanket test/sections/ ban would immediately red ~10
     existing sections that legitimately harness those modules; the
     legacy sweep is out of scope here.)
   - Constraint verification map (every hard constraint names its
     verifier — unverified = unconstrained):
     | Constraint | Verifier |
     |:--|:--|
     | killed record exists + in-flight VERIFY entry | dogfood section record assert |
     | children dead after SIGTERM | section polls the killed child pid until /proc is silent |
     | no killed record after teardown disarm | section sub-case: second SIGTERM in the exit window appends nothing |
     | SIGHUP variant covered | section runs one kill round with SIGHUP |
     | lock released (R-31) | section asserts the run lock is acquirable before restart |
     | store-busy sidecar + corrupt-line drain | unit section feeding a corrupt sidecar line |
     | heal quota exceeded → fail closed | unit section with a deterministic deleter |
     | tookOver live-pid pause | unit section with a stale-heartbeat live holder |
     | testBase-gated rm (no bare prefix rm) | unit section with a forged registration outside any testBase |
     | telemetry lines exist | dogfood section greps the run log for the liveness markers |
     | status latest-run line | status-rendering section assert |
     | store-path-inside-fixture | dogfood section pre-spawn assert |
   - The nested runner env goes through the registry-driven `GOS_AUTO_*`
     strip (launcher.cjs ALL_GOS_AUTO_ENV) with only explicit
     XDG_DATA_HOME/HOME/PATH injected. The nested cycle's fixture
     dispatch table routes ALL stages to script workers — the cycle never
     selects a host, so the total strip (including
     GOS_AUTO_TEST_FIXTURE) removes nothing the cycle needs.
   - Mid-VERIFY detection is a sentinel handshake, not timing: the
     fixture cycle's VERIFY plan includes a Class S step that writes a
     marker file inside the fixture store's scratch; the section polls
     the marker with a bounded timeout and, once seen, sends SIGTERM to
     the runner PID ONLY (never a group); it then asserts the killed
     record's stages carry the in-flight VERIFY.
   - Nested timeouts come from the fixture store (the strip removes
     GOS_AUTO_TIMEOUT_*): the section pre-seeds small wall/idle values
     plus an iteration cap, and the outer step's wall budget must exceed
     the nested total by a fixed margin — the outer harness wall-kill is
     SIGKILL (spawnrun.cjs:129) and would fake-fail the record assert.
   - Before spawning, the section asserts the resolved store path lives
     inside the fixture directory (XDG override is design, not luck); the
     fixture repo carries no remote matching the real repository.
   - Environment preflight: the section resolves the sandbox engine and
     runs one trivial nested bwrap exec; on failure it skips with a named
     refusal recorded in the run manifest as a distinguishable SKIP
     result (bwrap-in-bwrap feasibility is environment property, not a
     given) — never a silent pass, never a multi-minute cascade. The
     SHIP checklist pairs this with the post-ship real cycle: the
     dogfood host must produce one non-skip run or the kill/restart
     regression surface counts as uncovered.

### Alternatives (Rejected)

- ~~Restart reconciliation (synthetic records for dead predecessors)~~:
  covers SIGKILL nobody asked for, with detection heuristics that can
  false-positive; the acceptance kills with SIGTERM only.
- ~~Hunt the exact metadata killer first, then a targeted fix~~: the hunt
  is unbounded (remaining suspects need an instrumented concurrent
  repro), the acceptance stays blocked meanwhile, and a targeted fix is
  fragile against the next unknown deleter.
- ~~Graceful child termination (signal children, wait for their EXIT-trap
  sweep, then group kill)~~: buys state the run-start stray sweep already
  cleans, at handler-latency cost during teardown.

## Design Decisions (D-NN)

### D-111: Finding A cure — SIGTERM handler persists a killed run record

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| in-process SIGTERM handler | latestRunRecordReadsGreen reads the latest record only; exception route loop.cjs:705-713 proves in-process persistence | record at kill time with real endState + stages; no false cold-start | no SIGKILL cover; persistRunRecord is a drive() closure — replaced by a shared runner-state object | re-enable gate, auto status, dogfood protocol step 4 |
| restart reconciliation | next run under the lock can observe predecessor strays | covers SIGKILL | inferred record (approximate timestamps, guessed endState); heuristic false positives; pre-backfill read window | same consumers, degraded fidelity |
| both | handler + backstop | fullest cover | two mechanisms, two test suites; unrequested SIGKILL cover | union of both |

why-not: restart reconciliation — acceptance is SIGTERM-only so inferred records buy coverage nobody consumes today; both — adds the reconciliation heuristic's false-positive surface before any consumer asks for it.
recommendation: handler — conditional: upgrade to handler+reconciliation if
the dogfood re-run exposes a SIGKILL-class gap.
deepen: any option — ask for another dig round.

### D-112: Finding B cure — bounded pin self-heal + liveness telemetry + run-start stray recycle

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| load-time self-heal | killer unidentified (3 bwrap-refuted hypotheses); treeSha re-verified per load keeps the trust chain; store record is sandbox-unreachable | killer-agnostic, immediately unblocks all pin legs | masks the killer (recurring heal cost); tried-latch must become retry-capable | every pin-leg load path |
| root-cause hunt first | remaining suspects are concurrency-class (orphan suite) | cleanest fix, zero heal cost | unbounded hunt, possibly irreproducible without a killed runner; acceptance stays blocked | one-shot diagnosis |
| self-heal + telemetry + run-start recycle | heal unblocks now; telemetry turns the next recurrence into a named-killer diagnosis; single-runner invariant makes run-start recycle safe | unblocks + diagnoses + deterministically clears strays | telemetry is best-effort stderr; killer remains at large at heal-cost | load paths + run-log diagnosis surface |

why-not: root-cause hunt first — acceptance rides on an unbounded, possibly concurrency-dependent repro; load-time self-heal alone — drops the diagnosis feed and leaves stray registration cleanup to the handler alone.
recommendation: self-heal + telemetry + run-start recycle — conditional:
heal retries are bounded per run (cap 2; exceeding fails closed,
no resurrect loop); telemetry lines stay terse.
deepen: any option — ask for another dig round.

### D-113: SIGTERM handler kills spawned suite children

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| tracked-pid kills over spawnreg entries (amended) | spawns are detached:true (spawnrun.cjs:80) — own process groups, unreachable by a runner-group kill | deterministically removes the dual-suite concurrency suspect; reuses the kill(-pid, SIGKILL) pattern already proven at spawnrun.cjs:129 | suite EXIT traps never run — stranded sections-tree metadata (covered by run-start sweep) | handler teardown path, restart determinism |
| process-group kill of the runner's own group (original, falsified) | assumed the detached runner's group contains the spawns | one syscall | spawns are outside the group (detached:true); in --fg mode the group is the caller's — signaling it kills the operator's shell | none (premise falsified) |
| graceful child termination | runner holds spawn pids; trap sweeps are seconds-fast | fewest strays | handler wait budget during teardown; sandbox trap timing not guaranteed | same, plus trap timing |
| no child handling | orphan interference is suspected, not proven | zero code | concurrency suspect class stays alive; orphan bwrap processes and tee logs keep consuming | none |

why-not: process-group kill of the runner's own group (original, falsified) — spawnrun.cjs:80 detached spawns put it out of reach and --fg shares the caller's group; graceful child termination — pays handler latency for state the run-start sweep already cleans; no child handling — keeps the last un-cleared suspect class and real resource waste.
recommendation: tracked-pid kills — conditional: the handler never signals
a group it does not lead (group-leader check first; --fg degrades to
tracked-pid + self-exit).
deepen: any option — ask for another dig round.

### D-114: dual acceptance — simulated dogfood section + post-ship real cycle

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| section tests only | p21 precedent: a live cycle cannot run while this task is current | light | zero real execution of the kill/restart path — repeats the 881b50bc fixture-vs-reality gap | VERIFY gate |
| simulated cycle in VERIFY | a section can run the real --fg runner on a fixture store and script the kill | real execution enters the suite; regression surface for the restart path | heavy section (minutes); the evidence gate still reads the real store — simulation cannot feed re-enable | VERIFY + regression suite |
| both | simulation proves the code; the real cycle feeds the real gate | end-to-end double cover; green-cycle evidence lands in the runbook | two acceptance costs | union + SHIP checklist item |

why-not: section tests only — ships without any real kill/restart execution; simulated cycle in VERIFY alone — the re-enable gate consumes real-store records no simulation can write.
recommendation: both — conditional: the simulated section must run the
real runner (fixture store, --fg), never mocked stages; the real cycle
remains a post-ship operational step recorded in the dogfood runbook.
deepen: any option — ask for another dig round.

## Scope

### In Scope

- `bin/lib/ops/auto/loop.cjs`: SIGTERM handler (killed record, lock
  release, group kill), persistRunRecord hoist, retry-capable pinState,
  run-start stray recycle, suite-window liveness telemetry.
- `bin/lib/ops/auto/workers.cjs`: pin self-heal in the pinned-load path
  (bounded one re-materialize per load, treeSha re-verified), stray
  sections-tree sweep helper reuse.
- `test/sections/`: new simulated dogfood section (fixture store, real
  --fg runner, scripted SIGTERM, restart, green-record assert).
- Post-ship note in the dogfood runbook (operational step, not code).

### Out of Scope

- SIGKILL survival (no reconciliation backfill).
- Identifying/removing the exact pin-metadata killer (telemetry observes;
  a targeted fix is follow-up work if it recurs and gets named).
- Auto-loop scheduling/pause behavior beyond the kill/restart path.

## Deferred Ideas

- [DI-1]: reconciliation backfill for SIGKILL'd runners (if a real
  SIGKILL-class gap shows up in dogfood re-runs).
- [DI-2]: targeted fix for the pin-metadata killer once telemetry names it
  (attach the run-log evidence to the follow-up).

## Red Team Record (Lv2+ mandatory before user approval)

| Round | Perspective | Findings | Dispositions (A/AP/R-with-facts/D) |
|:---|:---|:---|:---|
| 1 | misuse/safety | 10 (2 Critical, 7 Major, 1 Minor) | all ACCEPT — D-113 amended (group kill falsified by spawnrun.cjs:80; tracked-pid primary); handler write made store-busy-safe with ndjson sidecar; heal trust anchor moved to runner memory commit + root-repo rev-parse; heal quota per run; run-start recycle pauses on live-pid takeover; testBase-gated rm; no-require checks script; registry-driven env strip; fixture store-path assert |
| 2 | edge/exception | 12 (1 Critical, 9 Major, 2 Minor) | all ACCEPT — D-113 amended again (spawnreg pid is the runner's own pid, loop.cjs:1336 — child_pid backfill required); one-shot latch + sync-only handler covering SIGTERM/SIGHUP/SIGINT; install/disarm lifecycle; sidecar drained at run start; heal = recyclePin+materializePin composite; acquireRunLock gains tookOver; spawnreg-driven run-start sweep (test_base field); fixture table routes all stages to script workers; sentinel-based mid-VERIFY handshake; nested timeouts + wall margin; bwrap preflight with named-refusal skip |
| 3 | completeness | 13 (1 Critical, 7 Major, 5 Minor) | all ACCEPT — shared runner-state object replaces the drive()-closure hoist (in-flight stage lands in the killed record); in-flight step statuses pinned to the closed enum (store.cjs:110); kill identity = pid+starttime (procStartTime pattern); child tracking moved into spawnrun.cjs covering all three spawn sites, off the settleClaim entry-doc battlefield; heal choke point loadPinnedModuleWithHeal unifies both call sites; checks ban narrowed to the dogfood section (~10 legacy sections grandfathered); constraint→verification map added; SKIP is manifest-accounted + SHIP checklist non-skip requirement; lock release named via process.exit hook; auto-seed-* sweep added to run start; status renders latest-run line; kill-window→restart outcome table added (reconcileWaves unwired fact recorded) |

> Verdict: escalated-to-user — three rounds produced findings each round
> (10/12/13, all ACCEPTed and landed as spec constraints); per convergence
> rule 3 the spec goes to user approval carrying the full constraint set.

> Disposition key: ACCEPT(design change landed) / ACCEPT-PARTIAL /
> REJECT(factual counter-evidence cited) / DEFER(to DI-n).
> Verdict line: converged (a zero-finding round) or escalated-to-user.

## Risks

- Handler lands mid-spawnSync → record write delayed milliseconds; the
  kill window still closes before process death (Node queues the handler
  until the sync call returns). Mitigation: handler kills tracked children
  and writes the record with a bounded waitMs before exiting.
- Self-heal resurrect loop → per-run heal quota (cap 2); exceeding fails
  closed exactly as today, with telemetry naming the exceed count.
- Poisoned store record → heal cross-checks the runner's in-memory commit
  against a fresh root-repo rev-parse; mismatch fails closed.
- Tracked-pid kill misses an unregistered child → spawnrun.cjs's
  registry covers all three spawn sites (named above); a survivor is
  observable via the liveness telemetry and the section's dead-child
  poll.
- Kill-window → restart outcome contract (what "survive restart" means,
  per window):
  | Kill window | Restart outcome |
  |:--|:--|
  | mid-VERIFY suite | killed record; restart re-drives VERIFY; pin heals; green path (the acceptance scenario) |
  | mid-BUILD wave | waveStarts entries are refresh-overwrite (store.cjs:1614) — the wave re-drives; note: reconcileWaves has zero production callers (tests only) and stays unwired by this task |
  | mid-delegated spawn | no stamp → the restart pauses `orphan-pending-unrecoverable` (loop.cjs:987) — pause, not corruption; accepted |
  | mid-exit commit | spawnSync blocks the event loop; the handler queues behind the commit; the advance lands and the record carries it |
- Simulated dogfood section runtime (minutes) → section selector grouping
  keeps it out of the fast lane.
