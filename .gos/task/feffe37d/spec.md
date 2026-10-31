# Spec: Stage-dispatch blueprint for the auto loop

> **Date**: 2026-10-31 | **Level**: Lv3 | **Status**: draft (red-teamed)

## Goal

Replace the auto loop's one-shape-fits-all stage spawn with a per-stage
dispatch blueprint: mechanical stages run as script workers inside the
runner, creative stages run as equipped agent workers, BUILD is driven at
wave granularity under a three-contract system (input skill-contract
prompt, process behavioral assertions, output artifacts), trust semantics
are separated into mechanical clearance / progress release / human
approval, and every spawn emits telemetry (model pin, command counts,
head+tail dual-window stream capture).

## Motivation (dig facts)

Dogfood evidence (rounds 2-3, 2026-10-30): the mechanism layer holds
(channel consumed, deny capture, seed sanitize, breaker trips) but spawns
never executed the assigned VERIFY workflow — an LLM spawn was used to run
deterministic commands and did not run them. Counts from the tree today:

- Per-stage variation in the loop is one branch: THINK-only red-team legs
  (bin/lib/ops/auto/loop.cjs). Prompt, profile, whitelist, timeouts are
  identical for every stage; VERIFY burns a model spawn on work that is
  already three CLI verbs (`gate`, `section`, `truth verify`).
- The BUILD path is unproven under auto: the default profile mounts only
  `.gos` writable (loop compose writableRoots), so a BUILD spawn cannot
  write `bin/lib` or `test/` at all; a whole-stage BUILD also outlives the
  60-minute wall clock of any non-trivial task.
- Breaker layer K counts every entry of a stage label (breaker visit()),
  so wave-granularity BUILD (one spawn per wave) would trip K=5 on the
  fifth wave even when every wave succeeds.
- The spawn channel whitelist is a hardcoded four-verb set (spawnreg);
  BUILD workers additionally need `checkpoint` and map reads, and waves
  need their own use budget — one static set cannot serve both THINK and
  BUILD.
- Duplication already diverged: `SPAWN_MAX_BUFFER` in three modules
  (loop.cjs:59, redteam.cjs:40, adapters/opencode.cjs:24),
  `DEFAULT_LIMITS` in two (store.cjs:55, breaker.cjs:22),
  `DEFAULT_WALL_SEC` in two (breaker.cjs:26, redteam.cjs:39), and two
  near-duplicate async spawn runners — the loop's runner gained a live
  idle killer and deny scanning that the red-team runner never received;
  a stalled review stream today dies only at the 60-minute wall.
- `store.mutate` is a lock-free read-modify-write (store.cjs:302): runner
  counter bumps and short CLI writers (`auto on`, `disposition`) race to
  last-writer-wins.
- Nav hints ignore auto mode entirely (concern 652d65f1): `gos status`
  inside a spawned session still teaches the manual flow ("ask the user,
  then gos approve") — guidance that the spawn channel will refuse.

## Requirements

- **R-01** (auto-extracted intent): ship the stage-dispatch blueprint —
  per-stage worker forms, the BUILD three-contract system, wave-granularity
  BUILD dispatch, trust-semantics separation with the ratify-to-mechanical
  -clearance rename, and spawn telemetry.

## Approach

A tracked, fail-closed dispatch table (per stage: worker form, capability
profile, model slot, verb grants, use budget, breaker unit scheme,
prompt/command contracts, telemetry ceilings) drives the loop, the spawn
channel, and the nav hint layer. Script workers run deterministic
registered spawns (fixed argv, sandboxed, no model) for steps that touch
repo test content, plus pinned runner-side legs executed from a
loop-start worktree for steps that need the trust store; agent workers
spawn through the existing launcher/adapter stack with per-stage
composition. BUILD is driven by a runner-side wave iterator over the
frozen plan snapshot, one equipped spawn per wave, each held to the three
contracts and accounted as its own breaker unit.

## Design Decisions

### D-49: Scope bundles for this task (pre-ruled)

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| Ruled bundle in | all three concern triggers name this task (3bfa5fb4 next auto-family refactor, 39219bc9 next store.cjs touch, 577f0bfb next launcher/fixture touch) — the dispatch rewrite touches every one of those files, so deferring re-triggers them mid-build | one coherent auto-family batch; the shared substrate (constants, spawn runner) lands before new consumers multiply it | larger BUILD surface in one task | the auto-family module set this task rewrites (loop/store/breaker/redteam/launcher) and their sections |
| Dispatch only | each concern fires on its own trigger later | smaller diff per task | the rewrite would create a fourth and fifth copy of the duplicated constants before the DRY pass lands — the divergence class red-team flagged | nothing — the deferred concerns simply re-arm |
| Mega-task | one task closes the whole auto concern family | single context switch | five concerns with different risk classes; 559a4cc8 is T-2's owned scope, 8630eee9 needs its own product decision; blast radius unreviewable | none (rejected) |

why-not: Dispatch only — re-arms three triggers this task inevitably pulls;
Mega-task — violates the ruled OUT set (559a4cc8 54561541 f8352d9b 7d63cd9d
8630eee9 stay out).
recommendation: Ruled bundle in — conditional: if BUILD-red evidence shows
the fixture bundle starves the core dispatch work, the odd-path fixtures
split out first (they are the only bundle with no design coupling).
deepen: any option — ask for another dig round.

Subsumed by the intent (no separate card): default-profile capability gap
(a6fbd2db — per-stage floors are D-6 below), spawn quality (0f528c0e — the
three contracts are D-3), feral spawns (3c36cb07 — dispatch discipline and
grants are D-3/D-6).

### D-1: The dispatch table is tracked data, validated fail-closed

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| Tracked JSON | three consumers need the same answers (loop compose, spawnreg grants, nav hints) and two precedents already ship stage-shaped data as tracked JSON (auto-profiles/, adapters/registry.json) | one source for loop + lock layer + hints; diffs are reviewable in the PR; validation mirrors loadProfile's fail-closed shape checks | one more tracked artifact to keep schema-versioned | templates/auto-dispatch.json — loop dispatch, spawnreg grant checks, and the nav hint facade all read one table |
| Code constants | no new file, no loader | none | every stage-shape change is a code change riding the drift ledger; nav cannot import it without a nav→ops edge | the loop module only — hints and the lock layer would re-declare or reach across layers |
| Store config | per-machine tuning via `auto on` | private experimentation | machine-local divergence of a product contract; a fresh clone would silently fall back | the machine-local store only — nothing tracked travels |

why-not: Code constants — splits one truth across three modules and forces
a layer-graph violation for the hint consumer; Store config — machine-local
is for runner state, not product contract.
recommendation: Tracked JSON — conditional: the table must validate before
any spawn composes (unknown stage, missing worker form, or unknown verb
refuses the run, mirroring launcher profile validation); free-form
per-machine overrides stay out.
deepen: any option — ask for another dig round.

Semantics: entries keyed by stage (INTENT THINK PLAN BUILD REVIEW VERIFY
SHIP). Each entry declares: `worker` (agent|script), `profile` (launcher
profile name), `model_slot` (resolve-model agent name), `verbs`
(spawn-channel grant set), `use_cap` (per-spawn write budget, bounded by a
runner-side hard ceiling), `unit` (breaker accounting label scheme, closed
enum stage|stage-wave), `contracts` (prompt contract id + assertion caps
for agent workers; execution-class-split command plan for script workers),
and `telemetry` caps (advisory ceilings). BUILD additionally declares
`wave_dispatch: true`. Schema carries a `dispatch_schema_version`; the
loader refuses newer/unknown versions (store version-mismatch precedent).
The table seeds from templates and travels with clones; `gos auto status`
prints the resolved per-stage view.

Integrity and bounds (red-team R1-F3, folded in): the table is repo
content a BUILD wave could edit, so the runner loads it once at run-lock
acquisition, stamps its sha256 into the trust store, and re-verifies the
hash before every consume (compose, grant check, hint resolution) —
mid-run drift is the existing external-mutation pause, not a reload. Value
bounds live in runner code, never in the loader: `profile` ∈ {restricted}
for non-BUILD agent stages and {workspace} for BUILD (a table cannot grant
`full` or widen non-BUILD stages), `use_cap` ≤ a hard constant, `unit` ∈
{stage, stage-wave}, `worker`/`model_slot` ∈ registry-known names, human
gates remain hardcoded refusals no table entry can list.

### D-2: Two worker forms — script workers never run an LLM, and never run repo code in-process

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| Script spawns + pinned legs | VERIFY's verbs are deterministic CLI-layer work; steps that execute repo test content (section scripts) can run sandboxed under a fixed argv with no model in the loop, and steps that need the trust store or execute runner-trust code run from a pinned loop-start worktree in-process | no LLM call for mechanical work; the store stays masked from every sandbox; the runner never loads post-BUILD code into its own process (execution-integrity pin); the existing spawn channel solves the CLI-child lock deadlock by registration | gate/section need a non-die programmatic entry (cmdGate renders and exits today — split compute from render); one worktree checkout per run | the VERIFY dispatch unit and the runner's own delegated legs — both under one execution-integrity rule |
| Fully in-process | fewest moving parts | no spawn at all | section scripts and gate modules are repo content a BUILD wave just authored — running them unsandboxed inside the runner hands spawn-authored code the trust store, git, and credentials before any human gate fires (red-team R1-F2) | a runner process executing unreviewed repo code — the escalation this option would create |
| Unregistered child | reuses the CLI entry verbatim | zero refactor | guardCwd makes the child die on the runner's live root lock; only registered descendants pass the channel | a child process that cannot actually run — dead option |
| Agent spawn | one uniform spawn path | no dispatch branching | dogfood-proven failure mode (spawns ignored the assignment); a model call per mechanical check; the wall clock bounds each gate run | the current generic spawn — unchanged |

why-not: Fully in-process — executes spawn-authored code with runner
privileges between BUILD and the human SHIP gate; Unregistered child — the
lock/channel geometry refuses it by construction; Agent spawn — the exact
shape rounds 2-3 proved hollow.
recommendation: Script spawns + pinned legs — conditional: the command
plan per dispatch entry splits its steps by execution class (below) and a
failing step holds the stage with findings surfaced — never a blind
retry.
deepen: any option — ask for another dig round.

Semantics — execution classes, one integrity rule:

- **Class S (sandboxed script steps)**: steps whose inputs or bodies are
  repo content authored during the run — section suites above all. The
  runner composes a FIXED argv (no prompt, no host adapter, no model),
  registers it as a `script`-kind spawn with its own grants, and launches
  it through the ordinary launcher frame. Class S REQUIRES the kernel
  tier: a dispatch entry carrying script steps declares
  `requires: kernel-tier`, and a probe that degrades to lexical refuses
  the entry fail-closed (unsandboxed execution of run-authored test
  content is never a degradation path — red-team R2-F2). Class S compose
  contract: one runner-created scratch dir per spawn, rw-bound after the
  masks; `TESTBASE` redirected to it (the section runner's base guard
  learns to accept an env-pinned TESTBASE, literal-path fallback kept);
  git identity env injected (D-3); tmpfs sized explicitly, never default.
  Stream telemetry stamps it like any spawn. The trust store stays
  masked inside (mandatory masks unchanged).
- **Class P (pinned runner-side legs)**: steps that must read the trust
  store or execute runner-trust code — the semantic gate suite and trust
  gates. At run-lock acquisition the runner materializes a detached
  read-only worktree at the loop-start commit (the last reviewed main
  state the task branched from) INSIDE the store dir (machine-local,
  invisible to every sandbox — a `.gos/cache` placement would be
  spawn-deletable, R2-F9), records its tree hash in the store, and
  Class P legs execute ONLY modules from that worktree, hash-reverified
  before each leg — loaded by DYNAMIC require from the worktree path
  (never a static cross-module edge into the live tree, R3-F6). They
  analyze the live tree as data (scans, gate checks) but never `require`
  from it. Worktrees are recycled at run end and lazily by record at
  next start. The existing lazy-require legs (ratify/redteam/delivery)
  move under the same pin — closing the pre-existing post-BUILD
  module-load window at SHIP, not just VERIFY.
- **Bootstrap transition** (R3-F7): the task that lands this design runs
  its own VERIFY on a pin that predates the new programmatic gate entry —
  its loop keeps the legacy leg shapes for its own run, dispatch-driven
  script spawning proves itself via fixtures, and the pin may roll
  forward after a red-team-passed runner-critical wave (the same rolling
  semantics as the dispatch-table stamp, D-3).
- A step with no clear class refuses to run (fail-closed dispatch entry).

Script-worker verdicts come from return values and exit codes, never
parsed console prose. THINK/PLAN/BUILD/REVIEW stay agent workers;
red-team review rounds stay runner-side spawns (unchanged, now
Class-P-pinned for their orchestration code). Host negotiation moves
into dispatch consumption: iterations whose entry declares no agent
worker never probe the host (R2-F10).

### D-3: BUILD wave dispatch under the three contracts

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| Runner-side iterator | plans already group tasks under wave headings (plansnap parses `### Wave N`) and the plan freeze snapshots tasks — the snapshot must GAIN the wave field it currently drops (R2-F3) | bounds each spawn to one wave (wall clock fits); per-wave breaker accounting; checkpoint recovery becomes real (state.checkpoints exists with no consumer) | a new driver module and the hardest contract surface in this task | the BUILD dispatch unit, the checkpoint store, and the plan snapshot as the wave source of truth |
| Whole-stage spawn | zero new driver code (status quo shape) | none — already failing: cannot write code files under the default profile and outlives the wall clock on real tasks | every BUILD retry re-pays the whole stage; one feral spawn wastes the full budget | the current generic spawn — unchanged |
| Mega-spawn orchestration | mirrors the interactive skill flow (BUILD session sub-spawns executors) | keeps the runner simple | sub-spawn supervision inside an untrusted sandboxed session; the runner loses per-wave telemetry and breaker attribution | an in-sandbox orchestrator the runner cannot see |

why-not: Whole-stage spawn — proven non-viable (profile + wall clock);
Mega-spawn orchestration — moves the trust boundary inside the sandbox.
recommendation: Runner-side iterator — conditional: waves run strictly
sequential (section suites are sequential-only until TESTBASE namespaces
split — standing lesson), the iterator reads the frozen `plan_snapshot`
(never the live plan.md), and the freeze GAINS the wave field: snapshot
tasks carry `wave`, freeze-time validation enforces numbers ≥ 1,
contiguous, and unique — a plan with no wave headings refuses BUILD entry
fail-closed with guidance back to PLAN (R2-F3); a single wave is the
trivial first path.
deepen: any option — ask for another dig round.

The three contracts (agent BUILD spawns only):

- **Input (skill-contract prompt)**: runner-held template per worker form,
  hash-stamped in the trust store (redteamPrompt precedent, new snapshot
  kinds). It carries the stage's hard gates distilled from the skill
  (TDD, no untested code, wave single-point commit, forbidden verbs) plus
  scope POINTERS — wave number and task ids from the snapshot — never
  interpolated repo prose. The worker reads the plan itself. The
  "prompt text never comes from repo files" invariant holds: template
  source is runner-held; repo-derived inputs are parsed ids.
- **Process (behavioral assertions)**: deny hits = 0 (streaming detector,
  unchanged); advisory telemetry ceilings rendered but never
  classifying (D-5); frozen files untouched (spec_sha256, plan snapshot
  hashes, and the dispatch-table stamp re-verified after every wave);
  the pinned worktree hash unchanged.
- **Output (artifacts)**: per wave — exactly ONE new commit on the work
  branch in the pre/post range, its changed-path set ⊆ the wave's
  declared task files (plan freeze validates declared files against a
  safe-path allowlist — no `.git/**`, no absolute paths, no `..`, no
  hooks paths — red-team R1-F6); a refs snapshot (`for-each-ref` +
  reflog head) taken before and after each wave — any ref moving besides
  the work-branch tip is a violation; a checkpoint record (`checkpoint
  save` enters the BUILD grant set); section evidence for touched areas.
  At stage exit — one `gos commit build` advance commit (the existing
  coverage gates inside the commit stay the release check). Wave commits
  are plain git commits (the skill's single-point-commit rule; the stage
  advance remains the only `gos commit`). Uncommitted working-tree drift
  beyond machine-local paths and the checkpoint-bearing state file fails
  the wave's release check.

Waves whose declared files intersect runner-critical paths (spawnreg,
lock, the auto family, the dispatch table) release only after a red-team
reviewer pass over that wave's diff (existing red-team round machinery,
one round, findings hold the release) — the diff-surface check bounds
what landed; the review pass bounds whether it should have. A wave
released through that pass may legitimately have edited the dispatch
table itself: the runner ROLLS the store's table stamp to the new sha256
as part of the release and records it in the wave's completion entry —
only drift outside this path stays an external-mutation pause (R2-F7).

Wave lifecycle and recovery (R2-F4, R3-F3): the wave completion record
carries the wave's commit head sha and the post-wave refs snapshot pointer
into the trust store. On resume after a runner death, the iterator FIRST
reconciles the last pre-crash refs range: a commit uniquely attributable
to the wave (reachable from the work branch, inside the range, changed
paths ⊆ the declared set) is adopted — the completion record is written
from it and only the release check re-runs; nothing is ever re-dispatched
onto a completed wave. A wave whose completion record exists re-runs ONLY
its release check. A wave with nothing to do is an explicit no-op: the
spawn must produce an evidenced no-op checkpoint, the runner records
`wave-skipped-noop` and releases it as one legal iteration; silence is
never interpreted as no-op.

Git identity inside BUILD sandboxes (R2-F5): the mandatory masks empty
`~/.gitconfig`, so plain wave commits would die on "Author identity
unknown" on any host relying on global config (this dogfood repo's local
user.name hides the defect). The runner injects a fixed runner-held
identity (`GIT_AUTHOR_*`/`GIT_COMMITTER_*`, `gos-auto <gos-auto@invalid>`)
into every BUILD spawn env; a fixture asserts a wave commit without the
injection fails. BUILD also requires the kernel tier (workspace writes
are the dangerous class — a lexical-tier BUILD refuses fail-closed,
R2-F2).

Breaker accounting: wave spawns carry unit labels `BUILD/W< n >` for the
visit layer (a stuck wave still trips K on its own label; labels derive
from a closed enum, never free-form — R1-F3) while the consecutive layer
keeps the stage streak (three failed waves trip N). Head drift from wave
commits is expected (existing rc0-no-advance scoring does not apply inside
wave iterations — the iterator attributes progress by the wave commit,
not a stage advance).

### D-4: Trust semantics split into three named tiers

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| Rename + tier docs | "ratified" claims an approval the runner never received (a human did not sign it); what the runner does is verify stamp pairing — a mechanical clearance | names stop lying; the human-approval tier stays visibly empty until P16 proof lands | a rename touches readers, locales, docs, and archived-record tolerance | approval-record readers (state schema, commit gate, archive ledger), status/resume renders, and the SHIP ledger that lists delegation evidence |
| Keep the word | zero churn | no migration surface | the word keeps asserting authority in every audit surface — the exact conflation this task is booked to cure | nothing — wording only |
| Drop human tier | one less gate | fastest loop | reverses the standing ruling: archive/push/approve stay human gates (concerns 09ce3e57, 559a4cc8) | none (rejected) |

why-not: Keep the word — the conflation is the defect being cured; Drop
human tier — contradicts standing rulings.
recommendation: Rename + tier docs — conditional: the module file keeps its
name (ratify.cjs — fn-name uniqueness and map edges make a file rename pure
churn); only the concept vocabulary changes.
deepen: any option — ask for another dig round.

Semantics — the three tiers, one line each in every surface that renders
them:

- **Mechanical clearance** (auto, always): structural verification — stamp
  pairing spawnId↔stream hash, contract assertions, gate exit codes.
  Record status becomes `cleared` (writers); readers accept `ratified` as
  the legacy spelling of the same tier (grandfather fixture, bare-string
  human approvals unchanged).
- **Progress release** (auto): the stage may proceed — advance attribution
  plus the stage's dispatch-declared release check (THINK: red-team
  double-zero; PLAN: pairing only; BUILD: commit-build coverage gates;
  REVIEW: advance commit; VERIFY: gate suite green).
- **Human approval** (never delegated): approve/archive/push — the spawn
  channel refusal stays; consent-proof enforcement is T-2's scope (out).

Provenance (red-team R1-F4, folded in): the rename must not launder
forgeable records. `state.json` (which holds approvals) is writable by
every sandboxed spawn, and a bare-string approval record passes gates
today with no pairing at all. Three closures land with the rename:

- The runner-side release check re-verifies EVERY cleared-tier record it
  relies on: either the record is a PENDING→cleared conversion whose
  spawnId/streamSha256 pair against live store stamps, or it is a legacy
  record whose timestamp predates the loop-start baseline identity.
  Anything else (a string or cleared record newer than loop start with no
  store pairing) holds the stage for a human.
- Marker-active stage commits receive a baseline hash of the approvals
  map in the spawn env; a delegated advance whose approvals[stage] exists,
  differs from the baseline, and was not recorded as PENDING by this
  session refuses with guidance (fail closed when the baseline is absent
  in a marker session).
- Renders distinguish `cleared (store-verified)` from
  `cleared (pre-loop legacy)` — the vocabulary never asserts verification
  that did not happen.

Locale texts, status/resume renders, the SHIP delivery ledger, and
README's auto section all switch to the new vocabulary.

### D-5: Spawn telemetry — model pin, command counts, dual-window capture

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| Telemetry + dual window | the adapter already accepts spawn args (`--model`) that the loop never passes, and the capture today is tail-only 64 MB with a streaming deny scan | the pin is runner-enforced argv (a spawn cannot choose its model); windows make every held delegation human-readable without retaining unbounded streams | store schema v1→v2 (additive) and a bounded sidecar dir | store stamps, the advisory trend surfaces, and the human debugging path for held stages |
| Full-stream retention | nothing is ever lost | complete evidence | the redesign was explicitly deferred at the repair task (its D-3 ruled the minimum floor); unbounded disk per spawn | a retention policy this task would have to invent |
| Record nothing | the hash stamp already proves pairing | zero work | the dogfood failure mode (spawn did something other than assigned) is undiagnosable from the record | the status quo blind spot |

why-not: Full-stream retention — re-litigates a ruled deferral; Record
nothing — leaves the incident class unattributable.
recommendation: Telemetry + dual window — conditional: self-reported
fields are ADVISORY and never classify an iteration (red-team R1-F5);
classification stays on runner-observed facts only.
deepen: any option — ask for another dig round.

Semantics: store schema v2 — stamps entries gain optional
`modelPinned`, `modelObserved`, `commandCount`, `headSha256`, `tailSha256`,
`totalBytes`, `denyHits`; `load()` migrates v1 stores in memory (additive
fields, lazy write-back on next mutate; versions newer than known still
refuse). The runner resolves the model per dispatch entry
(`resolve-model <slot>`, staffing-aware) and passes it as adapter spawn
args — the pin is enforced by construction (argv the spawn cannot alter).
Adapters gain a tolerant telemetry extractor over parsed events (model
field and tool-execution count; absent fields → null). By red-team R1-F5
these observations are HOST-SELF-REPORT: a substituted model can echo the
pinned name and a batched tool call undercounts commands, so
`modelObserved`/`commandCount` render as advisory trend fields (labeled
self-report wherever shown, `unobserved` when absent) and NEVER produce a
breaker signal; the runner-enforced channel-use budget (D-6) remains the
hard per-spawn counter. Capture keeps head 256 KB + tail 1 MB windows per
spawn under the store dir (bounded count, pruned with the stamp cap); the
stamp hashes the retained windows and total byte count. The deny scan
keeps its pre-truncation streaming floor (unchanged) and its hit count
lands in the stamp. All spawn-originated bytes rendered to humans (windows,
review texts, hint lines quoting streams) pass a strict sanitizer (ANSI/CSI
escape stripping) and carry a spawn-output marker — never native chrome
(R1-F7).

### D-6: Per-stage capability floors and verb grants

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| Dispatch-declared floors | the capability gap is stage-shaped (BUILD writes code, THINK writes one file) and the channel whitelist is already per-spawn state (registry entries) — only the source of the verb set is hardcoded | BUILD gets workspace writes without making them global; THINK keeps the narrowest surface; grants travel with the spawn entry the lock layer already reads | spawnreg grows a grants field with legacy defaulting | the spawn channel admission path and every dispatch entry's `verbs`/`use_cap` |
| Global widen | one knob: widen the default profile + keep the static whitelist | smallest change | re-arms a6fbd2db verbatim (workspace-default was rejected as too blunt); every stage pays BUILD's blast radius | the blunt profile this design exists to replace |
| Kernel per-file | strongest isolation: bwrap binds narrowed to declared files | least write surface | bwrap binds directories, not declared-file sets; per-wave bind gymnastics dwarf the diff-surface assertion they would duplicate | a mount scheme the artifact contract already covers by check |

why-not: Global widen — the rejected blunt option; Kernel per-file — wrong
granularity for the enforcement available.
recommendation: Dispatch-declared floors — conditional: the artifact
contract (D-3) is the precision layer for WHAT changed; the profile is the
coarse layer for WHERE writes can land; both must agree before a wave
releases.
deepen: any option — ask for another dig round.

Semantics: THINK/PLAN/REVIEW run `restricted` (`.gos`-writable only);
BUILD runs `workspace` (repo root writable, credential masks unchanged —
the launcher's mandatory mask set is untouched). The registry's authority
moves OUT of `.gos/cache/auto-spawn` (inside every spawn's writable set —
red-team R1-F1) into the machine-local trust-store dir — but the channel
consumer runs INSIDE the sandbox, so a store-side registry alone would be
unreadable exactly where admission happens (red-team R2-F1). The channel
therefore becomes runner-mediated with three pieces:

- **Authoritative entry** (store dir, masked from every sandbox,
  runner-written): spawnId, kind, stage, grants, use cap, window expiry.
- **Read-only grant manifest**: at compose time the runner writes ONE
  spawn's immutable view (its grants, its cap, its stage — no other
  spawn's data) and ro-binds it into that sandbox at a fixed path after
  the masks (the launcher's post-mask ro-bind precedent). The spawned
  lock layer reads only this view; a forged `.gos/cache/auto-spawn` file
  is inert.
- **Request/ack admission**: each write-class use drops a request file in
  the spawn's rw scratch dir; the runner's live wait loop polls the
  scratch, appends the authoritative claim line in the store, and writes
  the ack (admitted/refused + remaining budget). The spawned side waits
  bounded (fail-closed on timeout). Forged request files can only burn
  that spawn's own budget — grants are checked against the store entry,
  never against the request.

The assigned-stage commit check and the human-gate refusal stay hardcoded
ahead of grants. Entries without grants (legacy) keep today's four-verb
default. Use budgets: BUILD wave entries raise the per-spawn cap
(checkpoint saves + section runs + the exit commit); THINK/PLAN/VERIFY
keep the current 16; every cap is bounded by the runner-side hard ceiling
from D-1.

### D-7: Nav hints consume the dispatch table and the auto store

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| Task facade | nav→ops edges are banned by the layer graph, but nav→task and task→ops are both legal (commit.cjs precedent); autoResumeLine already proved the entry-side shape | status/next/handoff become auto-aware without touching the require allowlist; the store is only ever READ (no probeWritable mkdir — concern 54561541's spirit even though its fix is out of scope) | one indirection hop | `gos status` / `gos next` / resume handoff inside and outside spawns |
| Entry-level wiring | bin/gos.cjs calls the provider after status | zero new re-export | hint text lands after the status block instead of inside it; every new surface re-wires the entry | the resume tail only (what exists today) |
| Leave manual | no work | none — spawned sessions keep getting refusal-bait guidance | the exact defect 652d65f1 records | the stale guidance, unchanged |

why-not: Entry-level wiring — the hint must be part of the Next block
where the worker actually reads it; Leave manual — the concern's trigger is
this task.
recommendation: Task facade — conditional: store reads are read-only
(missing store ⇒ silence, never mkdir), and the hint line names the
stage's expected artifact and advance verb (from the dispatch table), plus
"human gates are refused here" inside spawned sessions.
deepen: any option — ask for another dig round.

### D-8: One shared substrate (DRY + mutate serialization + odd-path fixtures)

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| Full substrate | the counts are known (3× SPAWN_MAX_BUFFER, 2× DEFAULT_LIMITS, 2× DEFAULT_WALL_SEC, 2 diverged runners) and this task adds new consumers (workers driver, telemetry) that would otherwise grow the copies to four and five | the redteam runner inherits the idle killer and dual-window capture by construction — the divergence bug dies with the duplication; serialization closes the race the same week the runner's write rate rises (per-wave stamps) | widest mechanical diff of the task (touch-everything) | every auto-family module, the store write path, and the new T107+ fixtures |
| Constants only | smaller blast radius | quick | the runner pair keeps drifting (the idle-killer gap is exactly this class) and telemetry would need a third copy or a cross-module reach | two runners still one bug apart |
| Defer all | D-49 ruled the bundles in | none | re-arms three triggers this task inevitably trips | nothing — the concerns re-arm |

why-not: Constants only — leaves the live defect class (diverged runners)
in place while adding a third consumer; Defer all — contradicts the ruling.
recommendation: Full substrate — conditional: the spawn runner keeps ONE
implementation with optional features (idle killer, deny scanner, window
capture) so redteam and work spawns compose rather than fork; the store
mutex fails closed (busy beyond a bounded wait reports store-busy — never
a silent last-writer-wins).
deepen: any option — ask for another dig round.

Semantics: a dependency-free `ops/auto/limits.cjs` becomes the single home
of the shared constants (no destructured requires — standing codemap
lesson); loop/redteam/store/breaker/adapters require it. One async spawn
runner module hosts the union of today's two (idle+wall killers, streaming
deny scan, dual-window capture, telemetry feed). `store.mutate` wraps its
read-modify-write in a mutex file inside the store dir (bounded spin ≈5 s,
fail-closed `store-busy` beyond — never a silent last-writer-wins); stale
reclaim requires the full holder identity the lock layer uses — boot_id
match AND `/proc/<pid>/stat` starttime match — never bare pid liveness
(R1-F8), with an mtime-age fallback when identity is unreadable
(cross-host holders): age past the threshold reclaims and records a
takeover breaker event (R2-F8). Creation uses O_EXCL with a temp+rename
fallback where the filesystem lacks reliable O_EXCL. A store residing on
a network filesystem — two machines sharing one remote derive one store
dir — upgrades from today's advisory warning to a hard refusal at
`auto run` (guidance points XDG_DATA_HOME at local disk; R2-F8). Odd-path
fixtures: the new sections exercise clone roots with spaces, unicode, and
a symlinked root across registry entries (in their new store-side home),
seed materialization, and dispatch-table resolution (realpath-first,
matching repoKey).

## Scope

In scope:

- templates/auto-dispatch.json (schema + seeds) + its fail-closed loader,
  run-start hash stamp, re-verification, and runner-side value bounds
  (loader refusals, enum/cap violations: named negative fixtures)
- bin/lib/core/state.cjs — approvals status enum admits `cleared`
  (`ratified` stays as legacy tolerance); a writer regression here locks
  every later state write, so the fixture is a writer+reader pair
- bin/lib/ops/auto/loop.cjs — dispatch-driven composition, wave iterator
  hookup, unit-label accounting, telemetry stamping, pinned-worktree legs,
  dispatch-consumed host negotiation
- bin/lib/ops/auto/workers.cjs (new) — worker forms: script-spawn command
  plans, pinned Class-P legs, agent wave driver, three-contract
  verification (one-commit range, refs snapshots, safe-path enforcement)
- bin/lib/ops/auto/limits.cjs (new) + bin/lib/ops/auto/spawnrun.cjs (new)
  — D-8 substrate (single constants home + the one async spawn runner);
  loop/redteam/store/breaker/adapters consume
- bin/lib/core/sanitize.cjs (new, dependency-free) — spawn-text sanitizer
  consumed by EVERY surface rendering spawn bytes (status hints, stream
  windows, review texts, ledger lines — R3-F8)
- bin/lib/ops/auto/store.cjs — schema v2 (stamp telemetry, v1 migration),
  mutate serialization (identity-bound reclaim), stream-window sidecars,
  spawn registry + claim ledger relocation into the store dir
- bin/lib/ops/auto/ratify.cjs — clearance vocabulary, provenance
  re-verification, approvals-baseline refusal, legacy tolerance
- bin/lib/ops/auto/cli.cjs — `auto status` per-stage dispatch view,
  clearance renders, the hint-provider export D-7 wires
- bin/lib/ops/auto/launcher.cjs — post-mask grant-manifest ro-binds,
  Class S scratch dirs + tmpfs sizing, git-identity env injection
- bin/lib/ops/auto/adapters/opencode.cjs + codex.cjs — tolerant telemetry
  extractor (model field, tool-execution count)
- bin/lib/core/spawnreg.cjs — store-side authoritative registry, per-spawn
  ro-bound grant manifests, request/ack admission, per-entry grants +
  use caps (legacy default)
- bin/lib/ops/gate.cjs — programmatic verdict entry for Class-P legs
  (compute/render split, no behavior change to the CLI path)
- bin/lib/task/commit.cjs / plansnap.cjs — declared-file safe-path
  validation at plan freeze; `wave` field + validation in plan_snapshot;
  marker-session approvals-baseline check
- bin/lib/task/archive.cjs — ratification-wording renders switch to the
  clearance vocabulary
- test/run-sections.sh — TESTBASE guard accepts the env-pinned sandbox
  base (literal-path fallback kept)
- bin/lib/nav/status.cjs + task/index facade + locales en/zh — auto-aware
  hints (D-7), sanitized rendering
- codebase map ledger duties in the same PR: T46 scan-set/fnTotal/fnDist
  drift declarations for the new modules, T25 frozen-set update, and the
  require-allowlist entry for task→ops/auto if the facade needs one
  (R3-F6)
- census.json reconciliation for every new tracked file
  (templates/auto-dispatch.json, bin/lib/ops/auto/workers.cjs,
  limits.cjs, spawnrun.cjs, bin/lib/core/sanitize.cjs) plus the
  pack-check pass and cjk-lint boundary on the same PR — the census
  ledger is the file-disposition truth, not the codemap ledger
- test/sections: T107 (dispatch + worker forms + execution classes,
  kernel-tier refusals, loader/value-bound negatives), T108 (contracts +
  wave dispatch + recovery + BREAKER WAVE ACCOUNTING: BUILD/W<n> labels
  trip K per label, N keeps the stage streak, no-op and resume paths),
  extensions to T104/T105/T106 (store v2, registry relocation + req/ack
  channel + ack-timeout refusal, clearance rename + provenance +
  approvals-baseline refusal + zero-wave refusal, odd-path fixtures,
  advisory telemetry, git-identity injection, legacy four-verb default)
- truth registration as an explicit early-BUILD task (the spec section
  does not self-register — standing lesson)
- README auto section + skills/gos-verify (script-worker note) wording

Out of scope (per D-49 and rulings): approval consent proof / /dev/tty
enforcement (559a4cc8, T-2), auto status probe side effects (54561541),
`auto run --break-lock` argv restoration (f8352d9b), shared-lock redesign
(7d63cd9d), stage-commit semantics debt (8630eee9), full-stream capture
redesign, parallel wave execution, TESTBASE namespace split, model
selection policy beyond the pin, host adapters beyond opencode/codex
fixtures.

## Deferred Ideas

- DI-1: parallel wave dispatch (needs TESTBASE namespace split + section
  runner serialization rework — lessons f2589acd/63675448).
- DI-2: kernel-level writable narrowing to declared files (per-wave bwrap
  file binds; only if the artifact-contract diff check proves insufficient).
- DI-3: full-stream capture redesign (ruled deferred at the repair task;
  revisit if dual windows starve a real investigation).
- DI-4: approval consent artifacts and gate refusal of proof-less records
  (T-2 / P16 completion, concerns 559a4cc8 + 09ce3e57).
- DI-5: dispatch-table negotiation at `auto on` (per-machine overrides
  with tracked-schema compat checks).

## Observable Truths

- **T1 dispatch drives the loop**: a fixture task at VERIFY under auto
  completes with zero host/LLM spawns on a host with NO selectable host
  adapter (host negotiation is dispatch-consumed, not unconditional);
  the iteration record names the script-spawn steps (sandboxed, fixed
  argv, kernel-tier required) and the pinned Class-P legs with their
  verdicts (section: fixture store + dispatch table).
- **T2 wave dispatch**: a two-wave fixture plan drives two equipped
  spawns; prompts carry wave/task pointers only (hash-stamped template);
  each wave releases on exactly one commit touching only its declared
  files; a wave commit without the injected git identity fails (negative
  fixture).
- **T3 contracts hold**: a wave whose diff touches an undeclared path,
  edits a frozen artifact (spec, plan snapshot, pinned-worktree hash),
  lands a second commit in range, or moves any ref besides the work-branch
  tip classifies `contract-violation` and holds the wave with the named
  violation (negative fixtures); a crashed-and-resumed wave with a valid
  completion record re-runs only its release check; an evidenced no-op
  checkpoint releases as `wave-skipped-noop`; a red-team-passed edit of
  the dispatch table rolls the table stamp without pausing.
- **T4 clearance vocabulary + provenance**: a PENDING THINK approval
  converts to status `cleared`; legacy `ratified` records read as cleared
  (grandfather fixture); a forged bare-string approval newer than
  loop start holds the stage at the release check and renders as
  claimed-not-verified (negative fixture); status/resume/ship-ledger
  renders say mechanical clearance.
- **T5 telemetry stamps are advisory**: a spawn stamp carries
  modelPinned/modelObserved/commandCount/head+tail hashes/totalBytes/
  denyHits; a fixture with a model mismatch or an over-ceiling count
  renders the advisory trend line and NEVER trips a breaker signal; the
  runner-side channel budget still hard-refuses past its cap.
- **T6 grants are runner-held**: a BUILD wave spawn's `checkpoint save`
  and `section` run admitted through the request/ack channel; the same
  verb from a THINK spawn refused (`not-in-grants`); a forged
  `.gos/cache/auto-spawn` entry is inert; a forged request file only
  burns the spawn's own budget; a redteam-kind entry never gains write
  admission; approve/archive/push refused for every stage (negative
  fixtures).
- **T7 script worker verdicts**: a red gate (fixture) holds VERIFY with
  findings surfaced and no breaker count; the programmatic gate entry
  returns the same verdicts as the CLI path (parity fixture); the
  pinned-worktree leg refuses to run when its recorded tree hash no
  longer matches (tamper fixture); a lexical-tier probe refuses BUILD
  and every Class S entry fail-closed.
- **T8 substrate**: `SPAWN_MAX_BUFFER`/`DEFAULT_LIMITS`/`DEFAULT_WALL_SEC`
  defined exactly once under bin/lib/ops/auto; the red-team runner now
  dies at the idle limit on a stalled stream (fixture stream).
- **T9 store serialization**: two concurrent mutators serialize (no lost
  update in a bumped-counter fixture); a held mutex beyond the bounded
  wait fails closed as `store-busy`; a recycled-pid holder does not
  satisfy reclaim without boot+starttime match, and an
  identity-unreadable holder past the mtime threshold reclaims with a
  takeover record (fixtures); `auto run` on a network-FS store refuses
  hard (fixture mount table).
- **T10 odd paths**: registry entry, seed materialization, and dispatch
  resolution succeed under clone roots containing spaces, unicode, and a
  symlinked root.
- **T11 auto-aware hints**: `gos status` inside a marker env names the
  stage artifact + advance verb and the human-gate refusal; outside with
  store mode on it names the loop state; with no store it prints nothing
  new and creates nothing (no mkdir); every rendered spawn byte is
  escape-stripped and spawn-marked (fixture with ANSI-laden stream).
- **T12 breaker wave accounting**: wave spawns account under their
  `BUILD/W< n >` unit labels — five healthy distinct waves never trip K
  while a single wave re-entered five times does; three consecutive
  failed waves trip N as the BUILD stage streak; the dispatch loader and
  value bounds refuse unknown stages/workers/verbs, out-of-enum units,
  and over-ceiling caps with named errors (negative fixtures).

## Red Team Record

Three dispatched rounds (fresh attacker sessions, repo-verified).

| Round | Perspective | Findings | Dispositions (A/AP/R-with-facts/D) |
|:--|:--|:--|:--|
| 1 | misuse/safety | 8 (3 Critical) | F1 registry spawn-writable → ACCEPT (store-side authority + ro-manifest + req/ack, refined R2-F1); F2 in-process execution of run-authored code → ACCEPT (execution classes + integrity pin); F3 dispatch-table integrity → ACCEPT (hash stamp + value bounds); F4 forgeable approvals → ACCEPT (provenance re-verification + baseline refusal); F5 self-reported telemetry → ACCEPT-PARTIAL (advisory-only, never classifying; runner-side budget stays hard); F6 declared-file lists/refs blindness → ACCEPT (safe-path freeze + one-commit + refs snapshots + critical-path review pass); F7 unsanitized render bytes → ACCEPT (sanitizer + marker); F8 mutex identity → ACCEPT (boot+starttime). All verified LANDED by round 2. |
| 2 | edge/exception | 10 (2 Critical) | F1 masked-store registry unreadable from its own consumer → ACCEPT (ro-bound manifest + request/ack admission); F2 lexical degradation → ACCEPT (kernel-tier requirement, fail-closed); F3 snapshot lacks wave field → ACCEPT (freeze gains wave + validation + zero-wave refusal); F4 crash/no-op deadlock → ACCEPT (completion record + resume + no-op evidence); F5 git identity → ACCEPT (runner-injected identity); F6 TESTBASE conflict → ACCEPT (scratch dir + env-pinned guard); F7 stamp-drift contradiction → ACCEPT (stamp rolling on released waves); F8 network-FS/cross-host mutex → ACCEPT (hard refusal + mtime fallback + rename creation); F9 worktree lifecycle → ACCEPT (store-dir home + recycle); F10 unconditional host gate → ACCEPT (dispatch-consumed negotiation). All verified LANDED by round 3. |
| 3 | completeness | 10 (2 Critical) | F1 spec fails its own card floor (abbreviated why-not tokens — verified by running the gate probe) → ACCEPT (all cards re-tokenized, literals in why-not); F2 `cleared` dies in the state approvals enum → ACCEPT (scope + writer/reader fixture); F3 commit-without-record crash window → ACCEPT (resume reconciles the refs range first, never re-dispatches); F4 four consumer files missing from scope → ACCEPT (cli/archive/launcher/adapters lines); F5 unverified semantics → ACCEPT (named negative fixtures + T12); F6 codemap landing duties + ops/auto→ops static edge → ACCEPT (dynamic require from the pinned worktree + ledger/allowlist scope lines); F7 pinned-worktree bootstrap paradox → ACCEPT (transition rule: legacy legs for the landing run, pin rolls on review-passed waves); F8 sanitizer homeless → ACCEPT (core/sanitize.cjs + enumerated surfaces); F9 unnamed module → ACCEPT (spawnrun.cjs); F10 truths need explicit registration → ACCEPT (early-BUILD scope line). |

Verdict: converged — rounds 2 and 3 verified every prior disposition
LANDED; round 3's residual findings were all accepted into the text
above. No REJECT dispositions were used in any round.

## Risks

- Widest mechanical diff of the auto family so far → waves in PLAN are
  cut per module family (substrate first, dispatch second, hints last)
  so each wave is independently verifiable.
- The request/ack admission channel adds runner-side polling machinery →
  the ack wait is bounded and fail-closed on the spawn side, and the
  protocol's failure modes are fixture-covered (T6) before BUILD relies
  on it.
- The runner must never execute post-BUILD repo code in-process → the
  execution-integrity pin (loop-start worktree, hash-verified legs) is
  the load-bearing guard, and kernel-tier requirements refuse the
  unsandboxed degradation paths; fixtures prove both refusals.
- Registry/claim relocation changes the channel's trust root → the
  migration keeps `.gos/cache/auto-spawn` reads inert (old entries
  ignored) and the sections cover forged-entry and forged-request
  negatives.
- Store schema bump on machines with v1 stores → additive in-memory
  migration with lazy write-back; fresh-store creation is unchanged.
- Wave prompts must stay pointer-only → hash-stamped templates + contract
  assertions on the frozen plan; any prose interpolation fails the
  template drift check.
- Self-reported telemetry could be mistaken for enforcement → advisory
  labeling is part of the render contract (T5/T11 fixtures pin it).
