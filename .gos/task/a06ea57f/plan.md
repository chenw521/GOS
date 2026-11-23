# Plan: Restart-safe auto loop (SIGTERM run record + live VERIFY pin)

> **Date**: 2026-11-23 | **Based on spec**: .gos/task/a06ea57f/spec.md
> Revised after Red Team round 4 (plan-attack): 26 findings, all
> ACCEPT/ACCEPT-PARTIAL — see the disposition table at the end.

## Decision Inventory

<!-- Verify every D-NN from spec has a task (Decision Coverage Gate) -->

- [x] D-111: Finding A cure — SIGTERM handler persists a killed run record and releases the run lock; no reconciliation backfill → T2, T4, T5, T6a, T6b, T9a
- [x] D-112: Finding B cure — bounded pin self-heal at load time + liveness telemetry + run-start stray-pin recycle → T3, T4, T6b, T7
- [x] D-113: GA3 — handler kills spawned children (tracked-pid, per-child group kill); stranded sections-tree metadata left to the run-start stray sweep → T1, T2, T5, T6b
- [x] D-114: GA4 — simulated dogfood section in VERIFY (real --fg runner, scripted SIGTERM+restart) + post-ship real cycle → T8a, T8b, T9a, T9b, T10

## Requirement Claims

<!-- Each R-NN must be claimed by ≥1 task. gos gate requirements checks at Lv4. -->

- [x] R-01: Restart-safe auto loop end to end (killed record + live pin across kill/restart) → T5, T9a
- [x] R-31: A SIGTERM'd detached auto run leaves a killed run record (endState killed, accumulated stage outcomes) and releases the run lock before exiting → T2, T4, T5, T9a
- [x] R-32: Pin legs survive a mid-suite pin death: dead worktree re-materializes once per load at the recorded commit with treeSha re-verified; liveness telemetry brackets the suite window → T3, T4, T7, T9a
- [x] R-33: A SIGTERM'd runner terminates its spawned suite children (process-group kill); stray pins and sections-tree registrations recycle at the next run start under the run lock → T1, T2, T5, T6b, T9a
- [x] R-34: The section suite runs a simulated dogfood cycle: real --fg runner on a fixture store, scripted mid-VERIFY SIGTERM, restart, green-record assert → T8a, T8b, T9a, T9b, T10

## Patterns to Follow

- Sections: `test/sections/T*.test.sh` — bash, standalone-safe (TESTBASE pin +
  teardown trap), case-map header comment (mirror T123 for real-CLI
  subprocess conventions, T128/T129 for store-facing asserts).
- Auto modules: `bin/lib/ops/auto/*.cjs` — every failure is a verdict object
  `{ ok: false, status|reason, detail }`, never a throw across module lines;
  store-busy is data, not an exception (store.cjs:674).
- Store writes go through `mutate()`; every new persisted shape must survive
  `validateStoreShape` + `runRecordRejection` (store.cjs:188, 273) on every
  later load — a key only the writer accepts bricks the store
  (RUN_STEP_STATUSES, store.cjs:111).
- Spawn identity: pid + `/proc/<pid>/stat` starttime (procStartTime,
  core/spawnreg.cjs:287). Never persist child pids into spawnreg entry docs
  (settleClaim rewrites entry docs, core/spawnreg.cjs:210) — the runner's
  OWN registration pid/starttime is the sanctioned entry-doc use.
- `run-sections.sh` takes ONE name filter per invocation (`$1`) — done-whens
  list separate invocations per section.
- No AI-trace artifacts in any written file (AGENTS.md Code Style).
- English everywhere; locale keys (`auto.*`, en+zh) for user-facing text.

## Execution Waves

> File-ownership rule (round-4 finding 5): no two tasks in one wave edit the
> same file. loop.cjs tasks serialize T4 → T6a → T6b → T5 → T7.

### Wave 1 (parallel)

#### T1: spawnrun child-tracking registry
- **Covers**: D-113, R-33
- **Files**: bin/lib/ops/auto/spawnrun.cjs, test/sections/T130-spawn-children.test.sh, test/sections/baseline.json
- **Read first**: bin/lib/ops/auto/spawnrun.cjs, bin/lib/core/spawnreg.cjs:280-300 (procStartTime), bin/lib/ops/auto/loop.cjs:1405-1411 (spec.spawnId at the main/script site)
- **Approach**: module-level registry keyed by `spec.spawnId` (fallback: the
  child pid when a spec carries no spawnId — redteam and wave specs already
  carry one) holding `{pid, starttime}` captured at spawn time inside
  `spawnRun`; entries removed on settle (`finish`). Export
  `trackedChildren()` and `killTrackedChildren()`: for each entry whose pid
  is alive AND whose recorded starttime still matches /proc (pid-reuse
  protection), verify `getpgid(childPid) === childPid` then
  `kill(-childPid, 'SIGKILL')` (spawns are detached group leaders,
  spawnrun.cjs:80); NEVER `kill(0, …)` and NEVER `kill(-process.pid, …)` —
  the runner does not signal its own group under any mode. Unmatched
  entries are skipped and named in the return payload. The registry never
  writes spawnreg entry docs.
- **Done when**: `grep -c "killTrackedChildren" bin/lib/ops/auto/spawnun.cjs bin/lib/ops/auto/spawnrun.cjs | tail -1` ≥ 1 AND `grep "starttime" bin/lib/ops/auto/spawnrun.cjs` matches AND section T130 passes using a REAL short-lived spawn (a `sleep` child): identity-gated kill skips a forged starttime mismatch, kills a live child, `getpgid` guard present; baseline.json gains a T130 pass floor.
- **Depends on**: none

#### T2: store/spawnreg surface — record opts, tookOver, sidecar, entry liveness
- **Covers**: D-111, D-113
- **Files**: bin/lib/ops/auto/store.cjs, bin/lib/core/spawnreg.cjs, bin/lib/ops/auto/workers.cjs, bin/lib/ops/auto/loop.cjs, bin/lib/ops/auto/redteam.cjs, test/sections/T131-store-surface.test.sh, test/sections/baseline.json
- **Read first**: bin/lib/ops/auto/store.cjs:643-699 (mutate takeover), 990-1013 (writeRunRecord), 1126-1196 (acquireRunLock), 1270-1341 (registerSpawn), bin/lib/core/spawnreg.cjs:98-172 (paths, saveEntryDoc, readEntry)
- **Approach**: additive surface changes. (1) `writeRunRecord(rec, rootDir,
  opts)` passes opts into `mutate` (bounded `waitMs` for the handler).
  (2) `acquireRunLock` success carries `tookOver: {pid, hostname, reason}`
  with reason from the closed enum `dead-pid | boot-changed | unreadable |
  cross-host | heartbeat-stale` (the dead-pid branch today writes no breaker
  event — the return value is the audit). (3) Export
  `runRecordRejection` (currently module-private, store.cjs:188) for the
  drain validator; export `listSpawnEntries(rootDir)` (readdir of the
  spawnreg dir, entries read best-effort). (4) Sidecar primitives:
  `appendRunRecordDrop(rootDir, rec)` (one ndjson line to
  `<storeRoot>/runrecords-drop.ndjson`), `readRunRecordDrops` /
  `truncateRunRecordDrops` / `moveCorruptDropLines` (→
  `runrecords-drop.corrupt.ndjson`). (5) Registration call sites: every
  `store.registerSpawn(` site (grep-verified: loop.cjs main/script + script
  steps, workers.cjs wave/sections sites) passes `pid: process.pid` and the
  spawnreg entry doc gains `starttime` (procStartTime at save time) plus a
  `test_base` field for sections-suite spawns — the testbed path
  (`<scratch>/testbed`) is only known AFTER registerSpawn returns
  (workers.cjs:334), so spawnreg gains an `updateEntryFields(rootDir,
  spawnId, {test_base})` primitive called from the sections compose once
  the pin exists. All shapes additive-optional.
- **Done when**: `grep "tookOver" bin/lib/ops/auto/store.cjs` matches AND `grep -c "runrecords-drop" bin/lib/ops/auto/store.cjs` ≥ 2 AND `grep "runRecordRejection," bin/lib/ops/auto/store.cjs` matches (export) AND `grep "listSpawnEntries" bin/lib/ops/auto/store.cjs` matches AND section T131 passes: tookOver populated with each enum reason on the matching break (absent on clean acquire), entry doc round-trips pid/starttime/test_base after a real registerSpawn + updateEntryFields, append+read+quarantine+truncate sidecar cycle, drain validation rejects a crafted bad record; baseline.json gains a T131 floor.
- **Depends on**: none

### Wave 2 (parallel)

#### T3: pin self-heal choke point — loadPinnedModuleWithHeal
- **Covers**: D-112, R-32
- **Files**: bin/lib/ops/auto/workers.cjs, test/sections/T132-pin-heal.test.sh, test/sections/baseline.json
- **Read first**: bin/lib/ops/auto/workers.cjs:565-733 (materializePin, loadPinnedModule, recyclePin, sweepWorktree), bin/lib/ops/auto/store.cjs:1470-1495 (recordPin path containment)
- **Approach**: export `loadPinnedModuleWithHeal(pin, relPath, {rootDir,
  gitRunner, expectedLoopStartCommit, budget})` where `budget` is a per-RUN
  counter object `{heals, cap}` (cap 2) owned by the caller (loop.cjs —
  wired in T4; the choke point only accounts). On a load failure whose
  reason is an unresolvable/tampered worktree AND a store record still
  exists, require ALL THREE trust anchors before healing: (a)
  `rec.loopStartCommit === expectedLoopStartCommit`; (b) a fresh `rev-parse
  <expectedLoopStartCommit>^{tree}` run at the LIVE repo root equals
  `rec.treeSha`; (c) `path.resolve(rec.path) === path.join(pinWorktreesDir(rootDir),
  runTag)` — the same containment recordPin enforces on write
  (store.cjs:1481-1484), closing the poisoned-`rec.path` rm vector
  (recyclePin force-removes `rec.path`). Mismatch fails closed, nothing is
  removed or materialized. Heal = composite of existing primitives only:
  `recyclePin(rootDir, runTag)` → `materializePin(rootDir,
  {loopStartCommit: expectedLoopStartCommit, runTag: <same tag>})`
  (rewrites path/treeSha so a stale record cannot loop) → retry the load
  exactly once. Budget exceeded → fail closed, reason exactly
  `heal-budget-exhausted`, exceed count in the verdict detail.
- **Done when**: `grep "loadPinnedModuleWithHeal" bin/lib/ops/auto/workers.cjs` matches AND section T132 passes with a deterministic deleter: first heal succeeds (budget.heals === 1), third fails `heal-budget-exhausted`; an anchor-mismatch record (treeSha or loopStartCommit or out-of-slot path) is refused with the target directory still present on disk; baseline.json gains a T132 floor.
- **Depends on**: none

#### T8a: dogfood fixture builder
- **Covers**: D-114, R-34
- **Files**: test/sections/fixtures/dogfood/build.sh, test/sections/fixtures/dogfood/RUNBOOK.md
- **Read first**: bin/lib/ops/auto/workers.cjs:170-180 (DEFAULT_VERIFY_STEPS — the REAL table drives the cycle; no fixture table exists), bin/lib/ops/auto/launcher.cjs:81-140 (ALL_GOS_AUTO_ENV, stripGosAutoEnv), test/sections/T123-auto-detach.test.sh (real-CLI subprocess conventions), test/checks/manifest-coverage.sh (new-content interactions)
- **Approach**: `build.sh <target-dir>` creates, idempotently, the fixture
  REPO (not the store — T8b tunes state): a git repo seeded with (a) the
  gos exec tree (bin/ + templates/ copied from the real tree, committed —
  pinned Class P legs require the exec tree in the workspace repo's own
  history, exactly the production shape for a user repo), (b) a tiny
  `test/sections/` with one trivial passing section AND the sentinel
  section (Class S target), (c) git identity pinned, (d) NO remote matching
  the real repository. Sentinel section (two-pass design, round-4 finding
  3): first pass writes an arming marker + its pid/pgid under the fixture
  workspace's `.gos/cache/` (writable, persists across runs), then sleeps a
  bounded 600s; on a later pass (restart) it sees the marker and exits 0
  immediately — the restarted run cannot re-block. RUNBOOK.md skeleton
  notes the post-ship cycle step (filled by T10). No fixture dispatch
  table: the real CLI's own table drives (its DEFAULT_VERIFY_STEPS already
  route gate:P / sections:S / truth:P).
- **Done when**: `bash test/sections/fixtures/dogfood/build.sh /tmp/x` twice → `diff -r` of the two outputs is empty (idempotent) AND `grep -r "arming" test/sections/fixtures/dogfood/` matches the sentinel AND `node bin/gos.cjs map scan` still exits clean AND `bash test/run-sections.sh --affected test/sections/fixtures/dogfood/build.sh` green AND `bash test/run-sections.sh T119` green (unanchored dir does not break map/affected).
- **Depends on**: none

### Wave 3 (parallel)

#### T4: loop.cjs refactor — runner-state hoist + heal wiring
- **Covers**: D-111, D-112, R-31, R-32
- **Files**: bin/lib/ops/auto/loop.cjs
- **Read first**: bin/lib/ops/auto/loop.cjs:766-824 (drive + persistRunRecord closure), 903-935 (pinState/loadLeg), 1575-1604 (Class P step path), store.cjs:188-225 (runRecordRejection stage contract)
- **Approach**: two coupled refactors. (1) Runner-state hoist: a
  runLoop-scoped `runnerState = {runId, runTag, taskId, startedAtIso,
  stageOutcomes: [], inFlight: null}` built before drive; persistRunRecord
  and runStageOutcomes operate on it; scriptIteration maintains `inFlight`
  synchronously at every step boundary — `{stage, steps: <completed steps
  only>}` — and the entry goes through the SAME normalizer as
  runStageOutcomes so the record always survives runRecordRejection
  (non-empty spawnId fallback `${runId}-${seq + 1}-inflight`, boolean
  advanced/counted, statuses strictly from `passed|failed|refused`);
  unstarted steps absent; cleared on iteration end. (2) Heal wiring (the
  choke point's only two production callers): per-run `pinBudget = {heals:
  0, cap: 2}` beside pinState; BOTH the loadLeg path (loop.cjs:925) and
  the Class P step path (loop.cjs:1583) route through
  `workers.loadPinnedModuleWithHeal(pin, relPath, {rootDir, gitRunner,
  expectedLoopStartCommit: loopStartCommit, budget: pinBudget})`; pinState's
  tried-latch becomes retry-capable (heal accounting lives in the budget).
  Existing exit routes keep identical output.
- **Done when**: `grep -c "loadPinnedModuleWithHeal" bin/lib/ops/auto/loop.cjs` ≥ 2 AND `grep "workers.loadPinnedModule(pin" bin/lib/ops/auto/loop.cjs` matches 0 lines AND `grep -c "runnerState" bin/lib/ops/auto/loop.cjs` ≥ 5 AND a record containing an in-flight entry round-trips `store.writeRunRecord` + `store.load` ok (harness assert inside the T133 prep or a quick node -e check recorded in the task) AND `bash test/run-sections.sh T128` passes AND `bash test/run-sections.sh T104` passes.
- **Depends on**: T2, T3

#### T8b: fixture smoke — real CLI drives a green cycle
- **Covers**: D-114, R-34
- **Files**: test/sections/fixtures/dogfood/build.sh, test/sections/fixtures/dogfood/seed-notes.md
- **Read first**: T8a output, bin/lib/ops/auto/cli.cjs:200-206 (`auto on --timeout-wall/--timeout-idle`, breaker N=1 as the iteration ceiling — `opts.maxIterations` has no CLI flag, loop.cjs:552/1152), bin/lib/ops/auto/store.cjs (mode/profile/timeouts shape)
- **Approach**: extend build.sh to seed the fixture STORE (XDG_DATA_HOME/
  HOME overridden into the fixture dir; `auto on` with breaker N=1, small
  --timeout-wall/--timeout-idle values — GOS_AUTO_TIMEOUT_* are stripped
  from the nested env by design, so the STORE carries the policy) and plant
  the fixture task state at VERIFY, shaped so the fixture's own pinned
  VERIFY legs (gate:P / sections:S / truth:P from the fixture's committed
  exec tree) pass. The nested runner env goes through the registry-driven
  GOS_AUTO_* strip with only explicit XDG_DATA_HOME/HOME/PATH injected.
  Outer-vs-nested wall budget: the outer step's wall budget exceeds the
  nested total by a fixed margin ≥ 120s (the outer wall-kill is SIGKILL,
  spawnrun.cjs:129 — it would fake-fail the record assert); nested wall
  seeded ≥ 120s so the sentinel's 600s sleep cannot be wall-killed before
  the section's kill lands. Smoke = one full script-VERIFY cycle, no kill.
- **Done when**: from a scratch TESTBASE, spawning the real runner
  (`node bin/gos.cjs auto run --fg` with the fixture env) completes the
  cycle and writes a GREEN run record in the fixture store (verify via
  `auto status` / store read), with the store path resolving inside the
  fixture directory; the smoke is repeatable twice in a row (two fresh
  TESTBASEs).
- **Depends on**: T8a

### Wave 4

#### T6a: run-start recovery I — sidecar drain + auto-seed sweep
- **Covers**: D-111
- **Files**: bin/lib/ops/auto/loop.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: T2 (sidecar primitives, runRecordRejection export), bin/lib/ops/auto/loop.cjs:659-699 (lock → sentinel → seedState → drive window)
- **Approach**: a recovery block in runLoop pinned EXACTLY between
  `writeDetachSentinel` (loop.cjs:666) and the seedState IIFE
  (loop.cjs:674) — before seeding, so the sweep can never delete the
  current run's own seed dir (round-4 finding 6). Under the run lock: read
  `runrecords-drop.ndjson`, validate each line with the exported
  runRecordRejection (bounded: at most 50 lines per drain — RUN_RECORDS_CAP
  parity), qualifying records append to runRecords flagged `droppedRecord:
  true` (runRecordRejection extended to accept the optional boolean),
  invalid lines move to `runrecords-drop.corrupt.ndjson`, then truncate the
  source; a lost record is never silent. Then remove stale `auto-seed-*`
  directories under `.gos/cache` (the finally's seed cleanup is skipped by
  process.exit). Locale keys for any guidance text land in en+zh.
- **Done when**: `grep "runrecords-drop" bin/lib/ops/auto/loop.cjs` matches AND `grep "auto-seed" bin/lib/ops/auto/loop.cjs` matches AND section T133 (delivered with T6b, one file for the whole recovery family) covers: seeded sidecar lines drain into runRecords with droppedRecord:true, a corrupt line is quarantined, the file is truncated, drain bound respected, and the current run's seed dir still exists after recovery.
- **Depends on**: T2, T4

### Wave 5

#### T6b: run-start recovery II — stray sweeps + live-pid pause
- **Covers**: D-111, D-112, D-113, R-33
- **Files**: bin/lib/ops/auto/loop.cjs, test/sections/T133-run-start-recovery.test.sh, test/sections/baseline.json, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: T2 (listSpawnEntries, entry pid/starttime/test_base), bin/lib/ops/auto/workers.cjs:401-460 (sweepSectionWorktrees), bin/lib/ops/auto/store.cjs:735-745 (lazyRecyclePins call shape)
- **Approach**: extend the recovery block. (1) Stray-pin recycle under the
  run lock (a fresh run holds no live tags; lazyRecyclePins with the
  current run's own tag excluded). (2) Spawnreg-driven sections-tree
  sweep: iterate `listSpawnEntries`; an entry is STRAY when its pid is
  absent, or its starttime mismatches /proc, or the pid is dead
  (single-runner-under-lock invariant). Per stray entry with a non-empty
  `test_base`: sweepSectionWorktrees with that entry's testBase, then ONE
  `git worktree prune`; the rm path stays code-gated on the per-entry
  non-empty testBase — a forged registration whose target lies outside any
  recorded testBase is never rm'd (bare prefix matching never removes
  anything). Dead stray entries are removed after sweeping. (3) PAUSE
  (guidance, no sweep) when `lock.tookOver` exists AND
  `tookOver.hostname === os.hostname()` AND reason ≠ `dead-pid` AND the
  recorded pid is still alive — a live-looking holder's strays are not
  ours to judge. Locale keys en+zh for the pause guidance.
- **Done when**: `grep "sweepSectionWorktrees" bin/lib/ops/auto/loop.cjs` matches AND `grep "tookOver" bin/lib/ops/auto/loop.cjs` matches AND section T133 passes: a forged registration outside any testBase leaves its target untouched; a stale-heartbeat LIVE holder pauses with a named reason and no sweep; stray pin + stray sections-tree entries recycle after a simulated dead runner; baseline.json gains a T133 floor.
- **Depends on**: T6a, T3

### Wave 6

#### T5: signal handler — killed record, child kill, lock release
- **Covers**: D-111, D-113, R-01, R-31, R-33
- **Files**: bin/lib/ops/auto/loop.cjs, test/sections/T134-signal-handler.test.sh, test/sections/baseline.json
- **Read first**: T1 (killTrackedChildren contract), T2 (opts passthrough + sidecar), T4 (runnerState), bin/lib/ops/auto/loop.cjs:603-725
- **Approach**: one handler for SIGTERM/SIGHUP/SIGINT, installed in runLoop
  only AFTER the run lock is acquired, the runnerState is ready, and the
  recovery block has run — the install point sits immediately before
  `drive`; one-shot latch (module-level boolean; after first entry all
  further signals are ignored until exit completes); synchronous code only
  (no await). Handler order: (1) kill tracked children FIRST via
  `spawnrun.killTrackedChildren()` (per-child group-kill — the runner
  never signals its own group; there is no --fg degrade clause, children
  are always their own group leaders), logging one stderr line per child
  (`auto kill: <spawnId> pid=<n> …`) via `fs.writeSync(2, …)`; (2) write
  the record: endState `{ok: false, status: 'killed', reason: <signal
  name>}` carrying runnerState.stageOutcomes plus the in-flight entry,
  through `writeRunRecord(..., {waitMs: 2000})`; store-busy or failure →
  `appendRunRecordDrop` sidecar; (3) `process.exit(128 + signum)` so the
  run-lock exit hook (store.cjs:1188) releases the lock. Every normal exit
  route disarms the handlers (listener removal) before the finally
  teardown; pre-lock signals keep default behavior. Handler body is
  try/catch-bounded to `process.exit`.
- **Done when**: `grep -c "SIGHUP\|SIGINT\|SIGTERM" bin/lib/ops/auto/loop.cjs` ≥ 3 AND `grep -ci "latch" bin/lib/ops/auto/loop.cjs` ≥ 1 AND section T134 passes (subprocess-driven, no bwrap needed): a child process running a real createLoop harness gets `process.kill(pid, 'SIGTERM')` mid-step → exits 143, store holds a `killed` record containing the in-flight entry, run lock re-acquirable, `process.listeners('SIGTERM')` is 0 after a normal (unkilled) run completes (mechanical disarm proof — replaces the blind second-SIGTERM sub-case), and a helper process holding the mutate lock ~3s forces the sidecar path (line lands, drain in T133 re-reads it); baseline.json gains a T134 floor. Regression: `bash test/run-sections.sh T104`, `bash test/run-sections.sh T105`, `bash test/run-sections.sh T128` (separate invocations — the runner takes one filter) all green.
- **Depends on**: T1, T2, T4, T6a

### Wave 7

#### T7: liveness telemetry + status latest-run line
- **Covers**: D-112, R-32, R-01
- **Files**: bin/lib/ops/auto/loop.cjs, bin/lib/ops/auto/cli.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs, test/sections/T135-auto-observability.test.sh, test/sections/baseline.json
- **Read first**: bin/lib/ops/auto/loop.cjs:1548-1670 (Class S step loop), bin/lib/ops/auto/cli.cjs:338+ (per-stage dispatch view), T4 (pinBudget surface)
- **Approach**: pin-liveness probes (worktree metadata dir existence:
  `.git/worktrees/<runTag>` resolvable) logged as terse stderr lines
  (`pin-live: …`) around each Class S step — before spawn and after settle
  — bracketing the suite window; heal events log one line each (runTag,
  budget remaining). `gos auto status` renders a latest-run line through a
  NEW locale key (`auto.cli.status.latestRun`) — endState.status,
  droppedRecord count, heal count — so the survival path is
  operator-visible without hand-reading store.json.
- **Done when**: `grep -c "pin-live" bin/lib/ops/auto/loop.cjs` ≥ 2 AND `grep "auto.cli.status.latestRun" bin/lib/ops/auto/cli.cjs bin/lib/core/locales/en.cjs bin/lib/core/locales/zh.cjs` matches all three AND section T135 passes: a harness-driven run's log carries bracketing markers around the script-step window; `auto status` output includes the latest-run fields; baseline.json gains a T135 floor.
- **Depends on**: T5 (same-file serialization), T3, T4

### Wave 8

#### T9a: dogfood section — happy path + SKIP result type
- **Covers**: D-111, D-112, D-113, D-114, R-01, R-31, R-32, R-33, R-34
- **Files**: test/sections/T136-auto-dogfood-restart.test.sh, test/run-sections.sh, test/checks/manifest-coverage.sh
- **Read first**: T8a/T8b fixtures, T5/T6a/T6b/T7 surfaces, test/run-sections.sh:330-345 (results counting), test/checks/manifest-coverage.sh (results contract)
- **Approach**: the acceptance section plus the runner support it needs.
  (1) SKIP result type: run-sections.sh recognizes a sentinel line
  `── SKIP <name>: <reason>` → `results[name] = {pass, fail, skip:
  <reason>}`, not counted into failed_sections; manifest-coverage validates
  a skip entry carries a non-empty reason (never a silent pass). (2) The
  section: environment preflight resolves the sandbox engine and runs one
  trivial nested bwrap exec; on failure (or `T136_FORCE_NO_BWRAP=1`
  self-invocation sub-case) it emits the SKIP sentinel with a named
  refusal. Pre-spawn assert: the resolved store path lives inside the
  fixture directory. Spawn the real runner via the CLI (`--fg`, fixture
  env from build.sh); poll the sentinel marker (armed marker carries the
  inner pid/pgid, poll interval ≤ 250ms, bounded timeout) inside the
  fixture workspace's `.gos/cache/`; once armed, send SIGTERM to the runner
  PID ONLY (never a group). Assert in order: the killed record exists and
  its stages carry the in-flight VERIFY entry (read the store between kill
  and restart — after restart the latest record is the green one); the
  killed child's inner pid (from the marker) is silent in /proc; the
  handler's `auto kill:` stderr lines name the spawn ids (discriminates
  runner-kill from kernel PDEATHSIG); the run lock is acquirable; restart
  → the restarted run passes the sentinel section (two-pass design) and
  reaches a GREEN record with pin legs passing; the run log carries the
  pin-live markers.
- **Done when**: `bash test/run-sections.sh T136` green on a bwrap-capable host; `grep -c "SIGTERM" test/sections/T136-auto-dogfood-restart.test.sh` ≥ 1 AND `grep "SIGHUP" test/sections/T136-auto-dogfood-restart.test.sh` matches (variant lands with T9b); `bash test/run-sections.sh T128` still green (runner changes did not shift counting); `grep "── SKIP" test/run-sections.sh` matches. NO baseline floor for T136 (skippable on incapable hosts — floor would mask the skip); the absence is noted in baseline.json only if the format permits comments, else in the section header.
- **Depends on**: T5, T6a, T6b, T7, T8b

### Wave 9 (parallel)

#### T9b: dogfood section — variants
- **Covers**: D-114, R-31
- **Files**: test/sections/T136-auto-dogfood-restart.test.sh
- **Read first**: T9a section
- **Approach**: append two variants to T136: (1) one kill round repeated
  with SIGHUP (same assert chain, signal swapped); (2) the
  `T136_FORCE_NO_BWRAP=1` self-invocation sub-case asserting the SKIP
  sentinel + manifest accounting (a distinguishable SKIP, never a silent
  pass, never a multi-minute cascade).
- **Done when**: `bash test/run-sections.sh T136` green with both variants active; forced-no-bwrap self-invocation reports the named skip and exits 0.
- **Depends on**: T9a

#### T10: checks script + post-ship runbook step
- **Covers**: D-114, R-34
- **Files**: test/checks/dogfood-no-require.sh, .github/workflows/ci.yml, test/sections/fixtures/dogfood/RUNBOOK.md
- **Read first**: test/checks/aggregate-guard.sh:120-154 (expect/self-test conventions), .github/workflows/ci.yml:70-78 (per-name checks invocation)
- **Approach**: checks script forbids THE DOGFOOD SECTION ONLY (matched by
  filename `T136-auto-dogfood-restart.test.sh`) from requiring
  `bin/lib/ops/auto/{loop,workers}.cjs` directly — the real runner is only
  reachable as a subprocess via the CLI. A blanket test/sections/ ban is
  out of scope (22 existing sections legitimately harness those modules;
  the legacy sweep is not this task). `--self-test` mode plants a temporary
  direct require in a copy and asserts exit 1 (expect pattern from
  aggregate-guard.sh — no manual BUILD-time verification). ci.yml gains a
  step invoking `bash test/checks/dogfood-no-require.sh --self-test`.
  RUNBOOK.md gets the post-ship operational step: one real kill/restart
  cycle on the dogfood host must produce a non-skip run after this task
  ships, or the kill/restart regression surface counts as uncovered
  (pairs with the section's SKIP accounting).
- **Done when**: `bash test/checks/dogfood-no-require.sh` exits 0 on the tree; `bash test/checks/dogfood-no-require.sh --self-test` exits 0 (planted-violation detection proven); `grep "dogfood-no-require" .github/workflows/ci.yml` matches; `grep -c "post-ship" test/sections/fixtures/dogfood/RUNBOOK.md` ≥ 1.
- **Depends on**: T9a

## Observable Truths

<!-- For VERIFY stage: what can the user observe when this works? -->

### T1: Mid-VERIFY SIGTERM leaves a killed run record
- **Expected**: a detached auto run killed mid-VERIFY leaves a run record in
  the store runRecords with status killed and stage outcomes present
  (including the in-flight VERIFY entry); read between kill and restart
  (after restart the latest record is the restarted run's)
- **Verify**: T136's killed-record assert (store read between kill and
  restart) + T134's harness cases; evidence source = one non-sandbox host
  run of `bash test/run-sections.sh T136` with the tee log under
  .gos/cache/section-runs/ (a sandboxed VERIFY host that skips bwrap
  cannot substitute for this evidence)

### T2: The simulated dogfood cycle ends green after restart
- **Expected**: the restarted run completes VERIFY with pin legs passing and
  writes a green run record (the acceptance scenario end to end)
- **Verify**: `bash test/run-sections.sh T136` green-record assert after the
  scripted restart (non-sandbox host, log retained)

### T3: No descendant suite/bwrap processes survive the kill
- **Expected**: after SIGTERM of the runner, no spawned suite or bwrap
  processes remain alive
- **Verify**: T136's dead-children poll on the marker-recorded inner pid/pgid
  + the handler's `auto kill:` stderr lines + T130 identity-gated kill cases

### T4: Pin-liveness telemetry brackets the suite window
- **Expected**: the run log carries pin-liveness telemetry lines before and
  after the sections suite window
- **Verify**: `bash test/run-sections.sh T135` + T136's log grep for the
  pin-live markers

## Risks

- Handler lands mid-spawnSync → record write delayed milliseconds; Node
  queues the handler until the sync call returns; the handler kills tracked
  children and writes with a bounded waitMs before exiting (spec Risk 1).
- Self-heal resurrect loop → per-run quota cap 2 at the single choke point;
  exceeding fails closed with the exceed count in telemetry.
- Poisoned store record → triple trust anchor (commit identity, fresh
  root-repo rev-parse, path containment) fails closed; nothing removed.
- New persisted shapes brick older loads → every store change stays
  additive-optional and survives runRecordRejection/validateStoreShape on
  load (T131/T133 asserts).
- Teardown-window signal appends a phantom record → disarm (listener
  removal) on every normal exit route, asserted mechanically by T134's
  listener-count check.
- Dogfood section runtime (minutes) + CI variance → bwrap preflight turns an
  incapable host into a named manifest-accounted SKIP; the SHIP checklist
  pairs the skip path with the post-ship real-cycle requirement (T10
  runbook step).
- Sentinel step blocks the restart → two-pass arming design (T8a): first
  pass arms + sleeps, later passes exit 0 immediately; nested wall ≥ 120s
  bounds the sleep safely above the section's kill latency.

## Red Team Round 4 (plan-attack) Dispositions

26 findings (3 Critical, 13 Major, 10 Minor) — all dispositions ACCEPT or
ACCEPT-PARTIAL; none REJECTED. Key landings:

| # | Sev | Disposition |
|:--|:--|:--|
| 1 | C | ACCEPT — heal wiring at BOTH production call sites folded into T4 (was missing entirely) |
| 2 | C | ACCEPT — T2 covers registerSpawn call sites (pid/starttime/test_base) + updateEntryFields + listSpawnEntries |
| 3 | C | ACCEPT — two-pass sentinel (arm+sleep / see-marker-exit-0), nested wall ≥ 120s |
| 4 | Maj | ACCEPT — no fixture dispatch table; fixture repo carries the exec tree (production shape for a user repo); real table's DEFAULT_VERIFY_STEPS drive; T8b smoke green = done-when |
| 5 | Maj | ACCEPT — file-ownership waves; loop.cjs chain T4→T6a→T6b→T5→T7 serialized |
| 6 | Maj | ACCEPT — recovery block pinned between writeDetachSentinel and the seedState IIFE |
| 7 | Maj | ACCEPT — degrade clause dropped; per-child getpgid guard; runner never signals its own group |
| 8 | Maj | ACCEPT — listSpawnEntries + stray definition (pid absent / starttime mismatch / pid dead) |
| 9 | Maj | ACCEPT — marker carries pid/pgid; handler emits `auto kill:` stderr lines |
| 10 | Maj | ACCEPT — SKIP sentinel + results shape + manifest-coverage reason validation (T9a) |
| 11 | Maj | ACCEPT — T134 dedicated handler section (subprocess-driven, no bwrap dependency) |
| 12 | Maj | ACCEPT — listener-count disarm assert replaces the blind exit-window sub-case |
| 13 | Maj | ACCEPT — third anchor: path containment mirroring recordPin's write-side check |
| 14 | Maj | ACCEPT — in-flight entry through the same normalizer; write+load round-trip assert |
| 15 | Maj | ACCEPT — ci.yml step + --self-test mode replaces manual BUILD verification |
| 16 | Maj | ACCEPT — runbook home = test/sections/fixtures/dogfood/RUNBOOK.md (census-covered) |
| 17-26 | Min | ACCEPT (17 reason enum + same-host gate; 18 export runRecordRejection + 50-line drain bound; 19 seven done-when concretizations incl. single-filter runner invocations and `T136_FORCE_NO_BWRAP=1`; 20 locale files in Files; 21 baseline floors + no-floor note for T136; 22 truths reworded to read-between-kill-and-restart + non-sandbox evidence source; 23 ACCEPT-PARTIAL — T6→T6a/T6b, T8→T8a/T8b, T9→T9a/T9b split; T3 kept whole at ~40min borderline; 24 breaker N=1 + `auto on` timeout flags replace unreachable iteration cap; 25 counts/anchors corrected (22 legacy sections; store.cjs:111; acquireRunLock 1126); 26 map scan + --affected + T119 gates on the fixtures dir) |
