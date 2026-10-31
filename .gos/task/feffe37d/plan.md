# Plan: Stage-dispatch blueprint for the auto loop

> **Date**: 2026-10-31 | **Based on spec**: .gos/task/feffe37d/spec.md

## Decision Inventory

- [x] D-49: Scope bundles (spawn DRY, mutate serialization, odd-path fixtures) → T2, T4, T9, T20
- [x] D-1: Tracked dispatch table, fail-closed validation → T7, T13, T16
- [x] D-2: Script workers + pinned runner-side legs → T10, T12, T13, T16
- [x] D-3: BUILD wave dispatch under three contracts → T10, T14, T15, T16
- [x] D-4: Trust tiers — mechanical clearance rename + provenance → T6, T17, T18
- [x] D-5: Spawn telemetry, dual-window capture, sanitizer → T3, T5, T8, T11, T16, T19
- [x] D-6: Dispatch-declared capability floors + verb grants → T9, T10
- [x] D-7: Nav hints consume dispatch table + auto store → T18, T19
- [x] D-8: One shared substrate → T2, T3, T4

## Requirement Claims

- [x] R-01: Ship the stage-dispatch blueprint → T1, T7, T15, T16, T17, T20

## Patterns to Follow

- CLI under test is ALWAYS `node bin/gos.cjs` — never the global gos binary.
- New sections: test/sections/T<NN>-<slug>.test.sh, `# gos-map:none` header,
  standalone self-provision copied from T106 (TESTBASE/HOME pins, git identity
  env, GOS_HEADLESS=1).
- Requires: sibling-only within ops/auto; cross-domain via domain index except
  allowlisted directions (.gos/codebase/require-allowlist.json — add the
  direction BEFORE the require); namespace requires, never destructured.
- census.json is the file-disposition truth: new tracked files disposed ONE at
  a time via scripts/census-dispose.sh; bash test/pack-check.sh before layout
  changes; cjk-lint boundary (English only outside README.zh-CN.md).
- Store/machine-local paths never enter wave commit sets (dirty-baseline
  exemption covers .gos/state.json and the task-head marker only).

## Execution Waves

### Wave 1 (parallel — shared substrate + registration)

#### T1: Register the twelve observable truths
- **Covers**: R-01
- **Files**: .gos/state.json
- **Read first**: .gos/task/feffe37d/spec.md (Observable Truths section)
- **Approach**: Register T-01..T-12 from this plan's Observable Truths section
  via `node bin/gos.cjs truth add "<desc>"` — one call per truth, descriptions
  verbatim from the plan. The spec section does not self-register (standing
  lesson); evidence attaches at VERIFY via `truth verify` against the section
  runs named in each Verify line.
- **Done when**: `node bin/gos.cjs status` lists 12 observable truths with ids
  T-01..T-12 and zero verified (verification is VERIFY-stage work)
- **Depends on**: none

#### T2: limits.cjs — single constants home
- **Covers**: D-8, D-49
- **Files**: bin/lib/ops/auto/limits.cjs, bin/lib/ops/auto/loop.cjs, bin/lib/ops/auto/redteam.cjs, bin/lib/ops/auto/store.cjs, bin/lib/ops/auto/breaker.cjs, bin/lib/ops/auto/adapters/opencode.cjs
- **Read first**: bin/lib/ops/auto/store.cjs, bin/lib/ops/auto/breaker.cjs
- **Approach**: New dependency-free module exporting SPAWN_MAX_BUFFER,
  DEFAULT_LIMITS, DEFAULT_WALL_SEC and the runner-side hard use-cap ceiling
  (bound for D-1 use_cap validation). The five consumers drop their local
  copies and require the namespace module (sibling path, no destructuring).
- **Done when**: `grep -rn "SPAWN_MAX_BUFFER =" bin/lib` matches exactly
  bin/lib/ops/auto/limits.cjs (same one-match check for DEFAULT_LIMITS and
  DEFAULT_WALL_SEC) AND `node bin/gos.cjs section T104` exits 0
- **Depends on**: none

#### T3: spawnrun.cjs — one async spawn runner
- **Covers**: D-8, D-5
- **Files**: bin/lib/ops/auto/spawnrun.cjs, bin/lib/ops/auto/loop.cjs, bin/lib/ops/auto/redteam.cjs, test/sections/T105-auto-depth.test.sh
- **Read first**: bin/lib/ops/auto/loop.cjs (loopSpawnRunner), bin/lib/ops/auto/redteam.cjs
- **Approach**: Union of the two near-duplicate runners as composable
  options: idle killer (reset on every chunk), wall killer, streaming
  pre-truncation deny scan, head 256 KB + tail 1 MB dual-window capture with
  sha256 + totalBytes riding the result payload. loop.cjs and redteam.cjs
  compose it — the red-team path inherits the idle killer by construction.
  Window sidecars persist under the store dir once T8 lands; until then the
  payload carries them.
- **Done when**: `grep -rn "detached: true" bin/lib/ops/auto/loop.cjs
  bin/lib/ops/auto/redteam.cjs` returns nothing (detached child composition
  lives only in spawnrun.cjs) AND a T105 extension fixture kills a stalled
  stream at the idle limit
- **Depends on**: T2

#### T4: store.mutate serialization
- **Covers**: D-8, D-49
- **Files**: bin/lib/ops/auto/store.cjs, test/sections/T105-auto-depth.test.sh
- **Read first**: bin/lib/ops/auto/store.cjs (mutate path), bin/lib/core/lock.cjs (holder identity)
- **Approach**: Wrap the read-modify-write in a mutex file inside the store
  dir: bounded spin ~5 s, beyond it fail-closed store-busy (never silent
  last-writer-wins). Stale reclaim requires full holder identity — boot_id
  AND /proc/<pid>/stat starttime — with an mtime-age fallback when identity
  is unreadable (cross-host), recording a takeover breaker event. Creation
  via O_EXCL with temp+rename fallback. A store derived from a network
  filesystem (two machines sharing one remote) refuses hard at auto run with
  XDG_DATA_HOME-local-disk guidance.
- **Done when**: T105 extension fixtures pass — concurrent mutators serialize
  with no lost counter update; held mutex past the wait reports store-busy;
  recycled-pid holder does not satisfy reclaim; identity-unreadable holder
  past threshold reclaims with a takeover record; network-FS mount-table
  fixture refuses
- **Depends on**: T2

#### T5: core/sanitize.cjs — spawn-text sanitizer
- **Covers**: D-5
- **Files**: bin/lib/core/sanitize.cjs, test/sections/T107-auto-dispatch.test.sh
- **Read first**: bin/lib/core/fsio.cjs (module conventions), test/sections/T106-auto-spawn-channel.test.sh (standalone header pattern)
- **Approach**: Dependency-free strict sanitizer: ANSI/CSI escape stripping
  plus a spawn-output marker wrapper for every byte rendered to humans. This
  task CREATES test/sections/T107-auto-dispatch.test.sh (T106-style
  standalone header) carrying the sanitizer unit case; later waves extend
  the section. The render surfaces (status hints, stream windows, review
  texts, ledger lines) wire it in T18/T19.
- **Done when**: T107 exists with the gos-map:none header and its fixture
  asserts an escape-laden string renders escape-free and spawn-marked after
  passing the sanitizer
- **Depends on**: none

#### T6: state approvals enum admits cleared
- **Covers**: D-4
- **Files**: bin/lib/core/state.cjs, test/sections/T105-auto-depth.test.sh
- **Read first**: bin/lib/core/state.cjs (approvals validation)
- **Approach**: Approvals schema accepts object status `cleared` alongside
  `ratified`; bare-string human approvals unchanged. Fixture is a
  writer+reader pair — a writer regression here locks every later state
  write, so the pair must round-trip both spellings.
- **Done when**: T105 extension round-trips a `cleared` approval through
  write+read AND legacy `ratified` records still parse
- **Depends on**: none

### Wave 2 (depends on Wave 1 — dispatch table + trust store + channel)

#### T7: Dispatch table template + fail-closed loader
- **Covers**: D-1, R-01
- **Files**: templates/auto-dispatch.json, bin/lib/ops/auto/workers.cjs, census.json, test/sections/T107-auto-dispatch.test.sh
- **Read first**: templates/auto-profiles/restricted.json, bin/lib/ops/auto/launcher.cjs (loadProfile fail-closed shape checks)
- **Approach**: Extend the T107 section created in T5. New tracked
  templates/auto-dispatch.json keyed by the seven
  stages; each entry declares worker (agent|script), profile, model_slot,
  verbs, use_cap, unit (stage|stage-wave), contracts, telemetry caps; BUILD
  adds wave_dispatch: true. Loader lives in workers.cjs: dispatch_schema_version
  refuses newer/unknown; unknown stage/worker/verb, missing worker form, and
  out-of-enum unit refuse with named errors before any compose. Value bounds
  live in runner code: profile confined to restricted (non-BUILD) /
  workspace (BUILD) — a table can never grant full; use_cap ≤ the limits.cjs
  hard ceiling. Census disposal for the template (git+npm seeding label) via
  scripts/census-dispose.sh.
- **Done when**: T107 loader/value-bound negatives each produce their named
  error AND `bash test/pack-check.sh` exits 0 with the template
  census-reconciled
- **Depends on**: T2

#### T8: Store schema v2 — telemetry stamps + window sidecars
- **Covers**: D-5
- **Files**: bin/lib/ops/auto/store.cjs, test/sections/T105-auto-depth.test.sh
- **Read first**: bin/lib/ops/auto/store.cjs (stamps, load/migrate path)
- **Approach**: Stamp entries gain optional modelPinned, modelObserved,
  commandCount, headSha256, tailSha256, totalBytes, denyHits. load() migrates
  v1 stores in memory (additive fields, lazy write-back on next mutate);
  versions newer than known still refuse. Dual-window sidecars persist under
  the store dir (bounded count, pruned with the stamp cap); the stamp hashes
  retained windows and the total byte count. Self-reported fields are
  advisory by contract — they never classify an iteration.
- **Done when**: T105 extension passes — v1 fixture migrates additively; a
  future-version fixture refuses; sidecar count bounded and pruned with the
  stamp cap
- **Depends on**: T3, T4

#### T9: spawnreg — store-side registry + request/ack admission
- **Covers**: D-6, D-49
- **Files**: bin/lib/core/spawnreg.cjs, bin/lib/ops/auto/store.cjs, test/sections/T106-auto-spawn-channel.test.sh
- **Read first**: bin/lib/core/spawnreg.cjs, bin/lib/core/lock.cjs (guardCwd consumption)
- **Approach**: Authoritative entries move out of .gos/cache/auto-spawn into
  the machine-local store dir (runner-written, masked from every sandbox —
  old cache entries become inert reads). At compose the runner writes ONE
  spawn's immutable grant manifest (its grants, cap, stage only) for
  ro-binding. Each write-class use drops a request file in the spawn's rw
  scratch; the runner's live wait loop polls, appends the authoritative claim
  in the store, writes the ack (admitted/refused + remaining budget); the
  spawned side waits bounded and fails closed on timeout. Grants check
  against the store entry, never the request — forged requests only burn
  that spawn's own budget. Assigned-stage check and human-gate refusals stay
  hardcoded first. Grant-less legacy entries keep the four-verb default;
  BUILD entries carry raised caps (checkpoint saves + section runs + exit
  commit), THINK/PLAN/VERIFY stay 16, all bounded by the hard ceiling.
- **Done when**: T106 extension passes — BUILD entry's checkpoint save and
  section run admitted through req/ack; the same verb from a THINK entry
  refused not-in-grants; forged .gos/cache/auto-spawn entry inert; forged
  request burns only own budget; redteam-kind entry never write-admitted;
  approve/archive/push refused for every stage; ack-timeout fails closed
- **Depends on**: T7, T8

#### T10: Launcher compose — scratch dirs, git identity, kernel tier
- **Covers**: D-2, D-3, D-6
- **Files**: bin/lib/ops/auto/launcher.cjs, test/sections/T107-auto-dispatch.test.sh
- **Read first**: bin/lib/ops/auto/launcher.cjs (mask + bind order, post-mask ro-bind precedent)
- **Approach**: One runner-created scratch dir per spawn, rw-bound after the
  masks, TESTBASE redirected to it; tmpfs sized explicitly, never default.
  Grant manifests ro-bound after the masks (fixed path). Fixed runner-held
  git identity (gos-auto <gos-auto@invalid>) injected as
  GIT_AUTHOR_*/GIT_COMMITTER_* into every BUILD spawn env — mandatory masks
  empty ~/.gitconfig so plain commits would die. Dispatch entries carrying
  script steps or wave dispatch declare requires: kernel-tier; a capability
  probe that degrades to lexical refuses the entry fail-closed.
- **Done when**: T107 passes — Class S compose contract observable (scratch
  rw bind, TESTBASE pin, sized tmpfs); a wave-commit-without-identity
  negative fixture fails as designed; lexical-tier BUILD refuses; trust
  store stays masked inside every sandbox
- **Depends on**: T9

#### T11: Adapter telemetry extractor + model pin argv
- **Covers**: D-5
- **Files**: bin/lib/ops/auto/adapters/opencode.cjs, bin/lib/ops/auto/adapters/codex.cjs, test/sections/T105-auto-depth.test.sh
- **Read first**: bin/lib/ops/auto/adapters/opencode.cjs (spawn args, event parsing)
- **Approach**: Tolerant extractor over parsed events: model field and
  tool-execution count; absent fields → null. Host-self-report contract:
  a substituted model can echo the pinned name and batched calls undercount,
  so values render advisory (self-report label, unobserved when absent) and
  never produce a breaker signal. The runner-side channel-use budget stays
  the hard per-spawn counter. Spawn args pass the runner-resolved model
  (resolve-model per dispatch slot, staffing-aware) — argv the spawn cannot
  alter.
- **Done when**: T105 extension passes — fixture events with and without
  model/tool fields extract to value/null correctly; a model-mismatch and an
  over-ceiling count render the advisory trend line and never trip a
  breaker; the channel budget still hard-refuses past its cap
- **Depends on**: T3

### Wave 3 (depends on Wave 2 — worker forms, waves, loop)

#### T12: Gate programmatic verdict entry + TESTBASE env pin
- **Covers**: D-2
- **Files**: bin/lib/ops/gate.cjs, test/run-sections.sh, test/sections/T107-auto-dispatch.test.sh
- **Read first**: bin/lib/ops/gate.cjs (cmdGate render/exit shape)
- **Approach**: Split compute from render in cmdGate: a programmatic entry
  returns the failure set as data without process exit; the CLI path keeps
  byte-identical behavior. test/run-sections.sh base guard accepts an
  env-pinned TESTBASE (sandbox base set by the runner) with the literal-path
  fallback kept.
- **Done when**: T107 parity fixture returns identical verdicts from the
  programmatic entry and the CLI path on the same fixture inputs; a red gate
  holds VERIFY with findings surfaced and no breaker count;
  env-pinned-TESTBASE section run passes with the literal fallback intact
- **Depends on**: none

#### T13: workers.cjs — worker forms, Class S spawns, Class P pinned legs
- **Covers**: D-2, D-1
- **Files**: bin/lib/ops/auto/workers.cjs, bin/lib/ops/auto/store.cjs, test/sections/T107-auto-dispatch.test.sh
- **Read first**: bin/lib/ops/auto/launcher.cjs, bin/lib/ops/gate.cjs
- **Approach**: Script-worker command plans split steps by execution class:
  Class S (repo-authored content — section suites) runs fixed argv, no
  prompt/host/model, registered as script-kind spawns through the launcher
  frame; Class P (trust store or runner-trust code — semantic + trust gates)
  runs from a detached read-only worktree at the loop-start commit
  materialized INSIDE the store dir at run-lock acquisition, tree hash
  recorded in the store, DYNAMIC require from the worktree path only (never
  a static cross-module edge into the live tree), hash re-verified before
  each leg, analyzing the live tree as data. Existing lazy-require legs
  (ratify/redteam/delivery) move under the same pin. Worktrees recycled at
  run end and lazily by record. A step with no clear class refuses. Script
  verdicts come from return values and exit codes, never parsed prose.
  Iterations whose entry declares no agent worker never probe the host.
  Bootstrap transition: the landing run keeps legacy leg shapes for itself;
  the pin rolls forward only after a red-team-passed runner-critical wave.
- **Done when**: T107 passes — Class S compose contract enforced; pinned-leg
  tamper fixture (recorded tree hash mismatch) refuses; no-clear-class step
  refuses; a VERIFY fixture completes with zero host/LLM spawns on a host
  with no selectable adapter and the iteration record names script steps and
  pinned legs with verdicts
- **Depends on**: T7, T10, T12

#### T14: plansnap — wave field + safe-path freeze validation
- **Covers**: D-3
- **Files**: bin/lib/task/plansnap.cjs, bin/lib/task/commit.cjs, test/sections/T105-auto-depth.test.sh
- **Read first**: bin/lib/task/plansnap.cjs
- **Approach**: Snapshot tasks carry wave; freeze-time validation enforces
  numbers ≥ 1, contiguous, unique; a plan with no wave headings refuses
  BUILD entry fail-closed with guidance back to PLAN. Declared-file lists
  validate against a safe-path allowlist at freeze: no .git/**, no absolute
  paths, no .., no hooks paths.
- **Done when**: T105 extension passes — frozen snapshots carry wave;
  zero-wave, gapped-wave, and duplicate-wave fixtures refuse with named
  errors; unsafe declared paths refuse at freeze
- **Depends on**: none

#### T15: Wave driver + three contracts + breaker wave accounting
- **Covers**: D-3, R-01
- **Files**: bin/lib/ops/auto/workers.cjs, bin/lib/ops/auto/breaker.cjs, bin/lib/ops/auto/store.cjs, test/sections/T108-auto-wave-contracts.test.sh
- **Read first**: bin/lib/task/plansnap.cjs, bin/lib/ops/auto/redteam.cjs (round machinery), bin/lib/ops/auto/breaker.cjs
- **Approach**: Runner-side iterator over the frozen plan_snapshot (never
  live plan.md), strictly sequential, one equipped spawn per wave. Input
  contract: runner-held hash-stamped prompt template carrying distilled hard
  gates plus scope POINTERS (wave number, task ids from the snapshot) — repo
  prose never interpolates; template drift check fails interpolation.
  Process contract: deny hits 0; advisory ceilings rendered but never
  classifying; frozen files untouched — spec sha, plan snapshot hashes, and
  the dispatch-table stamp re-verified after every wave; pinned-worktree
  hash unchanged. Output contract: exactly ONE new commit on the work branch
  in the pre/post range with changed paths ⊆ the wave's declared files; refs
  snapshot (for-each-ref + reflog head) before/after each wave — any ref
  moving besides the work-branch tip is a violation; a checkpoint record per
  wave; section evidence for touched areas; stage exit remains the single
  gos commit build. Uncommitted drift beyond machine-local paths and the
  checkpoint-bearing state file fails the wave release. Waves whose declared
  files intersect runner-critical paths (spawnreg, lock, the auto family,
  the dispatch table) release only after a one-round red-team pass over the
  wave diff; a released edit of the table rolls the store stamp (recorded in
  the completion entry) — only drift outside that path stays an
  external-mutation pause. Recovery: the completion record carries the
  wave's commit head sha and post-wave refs pointer; on resume the iterator
  reconciles the last pre-crash refs range first — a commit uniquely
  attributable to the wave is adopted, the record written from it, only the
  release check re-runs; a wave with an existing completion record re-runs
  only its release check; an evidenced no-op checkpoint releases as
  wave-skipped-noop (silence is never no-op). Breaker: wave spawns carry
  unit labels BUILD/W<n> from the closed enum (a stuck wave trips K on its
  own label) while the consecutive layer keeps the stage streak (three
  failed waves trip N); rc0-no-advance scoring does not apply inside wave
  iterations — progress attributes by the wave commit.
- **Done when**: T108 (new section) passes — a two-wave fixture plan drives
  two spawns with pointer-only prompts; each wave releases on exactly one
  commit touching only its declared files; undeclared-path / frozen-edit /
  second-commit / ref-move negatives classify contract-violation and hold
  with the named violation; crash-resume adopts the attributable commit and
  re-runs only the release check; the no-op path releases; a red-team-passed
  table edit rolls the stamp without pausing; five healthy distinct waves
  never trip K while one wave re-entered five times does; three consecutive
  failed waves trip N
- **Depends on**: T13, T14

#### T16: Loop dispatch integration
- **Covers**: D-1, D-2, D-3, D-5, R-01
- **Files**: bin/lib/ops/auto/loop.cjs, test/sections/T108-auto-wave-contracts.test.sh, test/sections/T104-auto-core.test.sh
- **Read first**: bin/lib/ops/auto/workers.cjs, bin/lib/ops/auto/spawnrun.cjs
- **Approach**: Composition driven by the dispatch table — per stage: worker
  form, capability profile, model slot, verb grants, use cap, breaker unit
  scheme, contracts, telemetry ceilings. The table loads once at run-lock
  acquisition, sha256-stamps into the trust store, and re-verifies before
  every consume (compose, grant check, hint resolution); mid-run drift is
  the existing external-mutation pause, never a reload. BUILD wires the wave
  iterator; unit-label accounting switches stage|stage-wave per entry; the
  model resolves per entry and passes as adapter spawn args; telemetry
  stamps at spawn exit from spawnrun payloads into store v2; host
  negotiation becomes dispatch-consumed — entries without an agent worker
  never probe the host; VERIFY dispatch runs script spawns plus pinned Class
  P legs instead of a model spawn.
- **Done when**: T104 + T108 pass — the loop composes per-stage shapes from
  the table on fixtures (THINK restricted, BUILD workspace); an unknown
  stage or table drift mid-run pauses as external-mutation; stamp
  re-verification is observable before consumes; telemetry stamps carry the
  D-5 fields
- **Depends on**: T15, T11

#### T17: ratify clearance rename + provenance re-verification
- **Covers**: D-4, R-01
- **Files**: bin/lib/ops/auto/ratify.cjs, bin/lib/task/commit.cjs, test/sections/T105-auto-depth.test.sh
- **Read first**: bin/lib/ops/auto/ratify.cjs, bin/lib/task/commit.cjs (ratification boundary)
- **Approach**: ratify() writes status `cleared` (module file keeps its name
  — fn-name uniqueness and map edges make a rename pure churn); readers
  accept `ratified` as the legacy spelling of the same tier; bare-string
  human approvals unchanged. The release check re-verifies EVERY cleared-tier
  record it relies on: either a PENDING→cleared conversion whose
  spawnId/streamSha256 pair against live store stamps, or a legacy record
  whose timestamp predates the loop-start baseline identity; anything else
  (a bare string or cleared record newer than loop start with no pairing)
  holds the stage for a human. Marker-active stage commits receive a
  baseline hash of the approvals map in the spawn env; a delegated advance
  whose approvals[stage] exists, differs from the baseline, and was not
  recorded PENDING by this session refuses with guidance — fail closed when
  the baseline is absent in a marker session. Renders distinguish
  cleared (store-verified) from cleared (pre-loop legacy).
- **Done when**: T105 extension passes — a PENDING THINK approval converts
  to cleared; legacy ratified records read as cleared (grandfather); a
  forged bare-string approval newer than loop start holds the stage and
  renders claimed-not-verified; baseline-diffusion refuses; absent baseline
  in a marker session fails closed
- **Depends on**: T6, T8

### Wave 4 (depends on Wave 3 — render surfaces + hints)

#### T18: auto status dispatch view + clearance renders + wording surfaces
- **Covers**: D-4, D-7
- **Files**: bin/lib/ops/auto/cli.cjs, bin/lib/task/archive.cjs, README.md, skills/gos-verify/SKILL.md, test/sections/T104-auto-core.test.sh
- **Read first**: bin/lib/ops/auto/cli.cjs, bin/lib/task/archive.cjs (SHIP ledger renders)
- **Approach**: `gos auto status` prints the resolved per-stage dispatch
  view (worker form, profile, model slot, grants, unit scheme). The
  three-tier vocabulary — mechanical clearance / progress release / human
  approval — lands in status/resume renders, the SHIP delivery ledger,
  archive renders, the README auto section, and a script-worker note in
  skills/gos-verify. Export the hint-provider function T19 wires. Every
  spawn-originated byte rendered to humans passes core/sanitize.cjs with the
  spawn-output marker.
- **Done when**: T104 extension passes — status/resume/ship-ledger renders
  say mechanical clearance with the store-verified vs pre-loop-legacy
  distinction; the per-stage dispatch view prints; `grep "mechanical
  clearance" README.md skills/gos-verify/SKILL.md` matches
- **Depends on**: T16, T17

#### T19: Nav auto-aware hints via task facade
- **Covers**: D-7, D-5
- **Files**: bin/lib/nav/status.cjs, bin/lib/task/index.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs, .gos/codebase/require-allowlist.json, test/sections/T26-nav-hints.test.sh
- **Read first**: bin/lib/ops/auto/cli.cjs (hint provider export), bin/lib/task/commit.cjs (facade precedent)
- **Approach**: nav→task and task→ops/auto are legal edges (commit.cjs
  precedent); add the task→ops/auto direction to
  .gos/codebase/require-allowlist.json BEFORE adding the require. Store
  reads stay read-only: missing store ⇒ silence, never a probeWritable
  mkdir. The hint line names the stage's expected artifact and advance verb
  (from the dispatch table) plus "human gates are refused here" inside
  marker sessions; outside with store mode on it names the loop state; with
  no store it prints nothing new. All rendered spawn bytes sanitized and
  spawn-marked.
- **Done when**: T26 extension passes — marker-env hint names the artifact,
  advance verb, and human-gate refusal; mode-on outside names the loop
  state; no-store case prints nothing new and creates nothing (no mkdir);
  the allowlist carries the new direction
- **Depends on**: T18

### Wave 5 (depends on Waves 1-4 — ledger + census closure)

#### T20: Codemap ledger + census reconciliation + odd-path fixtures
- **Covers**: D-49, R-01
- **Files**: test/sections/T46-module-structure.test.sh, test/sections/T25-map-selfcheck.test.sh, .gos/codebase/structure.md, census.json, test/sections/T106-auto-spawn-channel.test.sh, test/sections/T107-auto-dispatch.test.sh
- **Read first**: test/sections/T46-module-structure.test.sh (embedded EXPECT), test/sections/T25-map-selfcheck.test.sh (embedded FROZEN set)
- **Approach**: Declare the plan-declared drift: T46 EXPECT gains the new
  modules (limits/spawnrun/workers/sanitize) in its files set with fnTotal
  and fnDist bumps; T25 FROZEN set gains the same files after
  `node bin/gos.cjs map scan` regenerates deps.json; structure.md layout
  refreshed. Census entries verified for every new tracked file
  (templates/auto-dispatch.json, workers.cjs, limits.cjs, spawnrun.cjs,
  core/sanitize.cjs — T7 seeds the first) and disposed one at a time;
  pack-check and cjk-lint pass on the same PR. Odd-path fixtures: clone
  roots with spaces, unicode, and a symlinked root exercising registry
  entries (in their store-side home), seed materialization, and
  dispatch-table resolution (realpath-first, repoKey match).
- **Done when**: `bash test/pack-check.sh` exits 0;
  `node bin/gos.cjs section T46` and `node bin/gos.cjs section T25` exit 0;
  `bash test/checks/cjk-lint.sh` exits 0; odd-path fixtures pass in the
  T106/T107 extensions
- **Depends on**: T16, T18, T19

## Observable Truths

### T-01: Dispatch drives the loop
- **Expected**: a fixture task at VERIFY under auto completes with zero
  host/LLM spawns on a host with NO selectable host adapter; the iteration
  record names the script-spawn steps and pinned Class-P legs with verdicts
- **Verify**: `node bin/gos.cjs section T107` (zero-host VERIFY case green)

### T-02: Wave dispatch
- **Expected**: a two-wave fixture plan drives two equipped spawns; prompts
  carry wave/task pointers only; each wave releases on exactly one commit
  touching only its declared files; a wave commit without the injected git
  identity fails
- **Verify**: `node bin/gos.cjs section T108` (two-wave case green)

### T-03: Contracts hold
- **Expected**: undeclared-path / frozen-edit / second-commit / ref-move
  waves classify contract-violation and hold; a crashed-and-resumed wave
  with a valid completion record re-runs only its release check; an
  evidenced no-op releases as wave-skipped-noop; a red-team-passed dispatch
  table edit rolls the stamp without pausing
- **Verify**: `node bin/gos.cjs section T108` (negative + recovery cases green)

### T-04: Clearance vocabulary + provenance
- **Expected**: a PENDING THINK approval converts to status cleared; legacy
  ratified records read as cleared; a forged bare-string approval newer than
  loop start holds the stage and renders claimed-not-verified; renders say
  mechanical clearance
- **Verify**: `node bin/gos.cjs section T105` (clearance + provenance cases green)

### T-05: Telemetry stamps are advisory
- **Expected**: a spawn stamp carries modelPinned/modelObserved/
  commandCount/head+tail hashes/totalBytes/denyHits; a model mismatch or
  over-ceiling count renders the advisory trend line and NEVER trips a
  breaker; the runner-side channel budget still hard-refuses past its cap
- **Verify**: `node bin/gos.cjs section T105` (advisory telemetry case green)

### T-06: Grants are runner-held
- **Expected**: a BUILD wave spawn's checkpoint save and section run admit
  through the request/ack channel; the same verb from a THINK spawn refuses
  not-in-grants; a forged cache entry is inert; a forged request only burns
  the spawn's own budget; approve/archive/push refuse for every stage
- **Verify**: `node bin/gos.cjs section T106` (grant matrix green)

### T-07: Script worker verdicts
- **Expected**: a red gate holds VERIFY with findings surfaced and no
  breaker count; the programmatic gate entry returns the same verdicts as
  the CLI path; the pinned-worktree leg refuses on tree-hash tamper; a
  lexical-tier probe refuses BUILD and every Class S entry fail-closed
- **Verify**: `node bin/gos.cjs section T107` (parity + tamper + tier-refusal green)

### T-08: Substrate is single-home
- **Expected**: SPAWN_MAX_BUFFER / DEFAULT_LIMITS / DEFAULT_WALL_SEC defined
  exactly once under bin/lib/ops/auto; the red-team runner dies at the idle
  limit on a stalled stream
- **Verify**: `grep -rn "SPAWN_MAX_BUFFER =\|DEFAULT_LIMITS =\|DEFAULT_WALL_SEC =" bin/lib | grep -v limits.cjs` returns nothing AND `node bin/gos.cjs section T105` idle-killer case green

### T-09: Store serialization
- **Expected**: two concurrent mutators serialize (no lost update); a held
  mutex beyond the bounded wait fails closed as store-busy; a recycled-pid
  holder does not satisfy reclaim without boot+starttime match; an
  identity-unreadable holder past the mtime threshold reclaims with a
  takeover record; auto run on a network-FS store refuses hard
- **Verify**: `node bin/gos.cjs section T105` (serialization cases green)

### T-10: Odd paths
- **Expected**: registry entry, seed materialization, and dispatch
  resolution succeed under clone roots containing spaces, unicode, and a
  symlinked root
- **Verify**: `node bin/gos.cjs section T106` and `node bin/gos.cjs section T107` (odd-path cases green)

### T-11: Auto-aware hints
- **Expected**: gos status inside a marker env names the stage artifact +
  advance verb and the human-gate refusal; outside with store mode on it
  names the loop state; with no store it prints nothing new and creates
  nothing; every rendered spawn byte is escape-stripped and spawn-marked
- **Verify**: `node bin/gos.cjs section T26` (hint + sanitizer cases green)

### T-12: Breaker wave accounting + dispatch negatives
- **Expected**: wave spawns account under BUILD/W<n> labels — five healthy
  distinct waves never trip K while a single wave re-entered five times
  does; three consecutive failed waves trip N; the dispatch loader refuses
  unknown stages/workers/verbs, out-of-enum units, and over-ceiling caps
  with named errors
- **Verify**: `node bin/gos.cjs section T108` (wave accounting + loader negatives green)

## Risks

- Widest mechanical diff of the auto family → waves cut per module family
  (substrate → dispatch → surfaces → ledger); each wave independently
  section-verifiable before the next composes onto it.
- Landing-run bootstrap: this task's own BUILD runs on the pre-rewrite loop
  (legacy leg shapes, restricted default profile); early waves may need a
  runner restart onto landed code before wave dispatch can drive itself —
  the transition rule keeps the legacy shapes legal for the landing run.
  T1's truth registration needs a write-lock-legal session (`truth add` is
  never spawn-granted) — under the landing run it runs operator-side,
  verbatim from this plan, before the first wave's release check.
- The request/ack channel adds runner-side polling machinery → ack waits
  bounded and fail-closed on the spawn side; forged-entry/forged-request
  negatives fixture-covered (T-06) before BUILD relies on it.
- Execution-integrity pin is load-bearing (the runner must never execute
  post-BUILD repo code in-process) → pinned worktree + per-leg hash
  re-verification + kernel-tier refusals each carry their own negative
  fixture (T-07).
- Registry relocation changes the channel's trust root → old
  .gos/cache/auto-spawn reads stay inert and the sections cover the
  forged-entry negatives through the migration.
- Store schema bump on v1 machines → additive in-memory migration with lazy
  write-back; fresh-store creation unchanged (T-09 fixtures pin both).
- Wave prompts must stay pointer-only → hash-stamped templates + drift
  check; any prose interpolation fails the template drift check (T-03).
- Self-reported telemetry could be mistaken for enforcement → advisory
  labeling is part of the render contract (T-05/T-11 fixtures pin it).
- Wave commits need the injected git identity on hosts relying on global
  config (this repo's local user.name hides the defect) → the
  without-identity negative fixture keeps the injection honest (T-02).
