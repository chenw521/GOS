# Spec: Repair the auto spawn pipeline (user rulings 2026-10-30, red-teamed)

> **Date**: 2026-10-30 | **Level**: Lv2 | **Red Team**: 3 rounds, all
> Critical/High findings accepted into this revision

## Goal

Three consecutive INTENT spawns on task 340de317 ignored their one-shot
stage assignment and escalated instead (sudo/su, git push, gh pr merge,
gos approve archive — denied by the dangerous-cmd gates); the breaker
tripped at N=3. Root cause (diagnosed): the runner holds `.gos/.lock`
with a live heartbeat for the whole loop and `acquireLock` exits(1) on
any live holder, so every write-class gos command inside a spawned
session died at its first step. Secondary root cause (diagnosed by red
team): the sandbox config mask `~/.config/opencode` is declared a seed
mask (kind:seed) but the seed mechanism is never wired — loop never
passes seedRoots — so spawned sessions run without host model
configuration. A spawned session must reliably complete exactly its
assigned stage advance, with no widened write surface for the
untrusted session itself.

## Decisions

### D-1 Registered spawn write channel (ruling: option A, narrowed by red team)

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A registered write channel | the runner already serializes writes; a spawn needs a bounded set of stage-driving writes — model that window, not the whole lock | bounded blast radius: four whitelisted verbs, a 16-use budget, one window; untrusted session trees never gain a general write pass | three new mechanisms (registry, budget, whitelist) instead of one branch | spawn registry + window budget + command whitelist in the lock layer |
| A0 bare ancestry-chain exemption | marker + holder pid in /proc ancestry | smallest diff | grants every descendant of the runner a concurrent write pass — rejected by red team R1-F1/R3-F4 (the feral session's own children are the threat model) | none (rejected) |
| B release for the spawn window | lock window covers runner ops only | no exemption | reverts the just-landed heartbeat design; external writers slip in | none (rejected) |
| C spawns run zero gos writes | sessions produce files, runner commits | lock untouched | per-stage protocol rewrite out of proportion | none (rejected) |

why-not: A0 — mutual exclusion collapses into a family-wide concurrent
write pass with no command, count, or window bound, and the denied
escalation attempts in the incident prove the session itself is the
untrusted party; B — trades a just-verified supervision property; C —
rewrite-scale response.

Semantics:

- **Spawn registry**: before each spawn the runner writes
  `.gos/auto-spawn/<spawnId>.json` (bwrap pid, assigned stage, spawn
  kind work|redteam, window expiry = spawn wall timeout). The registry
  entry is removed at spawn exit; entries past expiry never validate.
- **Window budget**: each admitted use appends one line to the spawn's
  claim file; the budget cap is 16 uses per window — a runaway session
  cannot flood, and legitimate stage work (multiple truth verifications,
  a gate run, the advance) fits. The registry entry is removed at spawn
  exit; entries past expiry never validate.
- **Command whitelist**: the window validates only stage-driving verbs for
  work spawns — the assigned `gos commit <assigned stage>`, `gos truth
  verify` (evidence replay, never free-text `truth add`), `gos gate`, and
  `gos section`. Redteam spawns get NO write authorization (read-class
  only). Everything else write-class keeps the live-holder refusal.
- **Human gates stay hard**: `approve`, `archive`, `push`,
  `disposition` refuse whenever `spawnMarkerActive()` — the lock was
  previously their accidental backstop; the refusal becomes explicit
  (aligned with the P16 direction and concerns 09ce3e57/559a4cc8).
- **Identity binding**: the lock file records `boot_id` and the
  holder's `/proc/<pid>/stat` starttime; the exemption requires the
  ancestor hit to match both. The ancestry walk excludes pid 1 and the
  current pid; depth cap 128; /proc unreadable or walk inconclusive
  fails closed with a dedicated CONTRACTS banner (distinct from
  depth-cap). Evaluation order is pinned: family exemption requires a
  live holder with fresh heartbeat; a dead holder falls through to the
  existing dead-pid auto-recovery (never the exemption).
- **No ownership acquired**: an exempted command passes WITHOUT
  setting _lockHeld and never unlinks or touches the lock (releaseLock
  stays a no-op for it). acquireLockAt/acquireEdgeLock (map/gate
  entry points on the same lock file when cwd is ROOT) reject under
  the marker — map/gate writes are outside the spawn channel by
  declaration, with guidance text saying so.
- **Banner**: one CONTRACTS-frozen line (key
  `state_semantics.lockSpawnChannel`, en/zh aliases, pid and stage as
  interpolation parameters) printed by the exempted command.
- **Crash-window atomicity**: before the in-spawn advance writes
  state, the commit path snapshots the current state bytes to
  `.gos/state.snapshot` (atomic); the runner's identity re-check
  classifies "pointer advanced, stage in completed, no labeled commit"
  as a crashed advance and rolls back from the snapshot
  (writeAtomicJson) instead of pausing as external-mutation. The
  rollback path itself uses writeAtomicJson. Baseline-path exclusion
  in the commit staging sweep moves BEFORE the git add sweep (a
  group-kill between them can no longer strand foreign dirty files in
  the index).
- **Heartbeat coverage**: delegated legs (orphan/pending leg
  verification, redteam passes) run under the same root-lock heartbeat
  refresh as the main spawn, so the lock never looks stale while the
  runner lives.

### D-2 Activate the host-config seed mechanism (ruling: ro-bind real config, re-landed as seed)

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| seed activation | the mask already declares `~/.config/opencode` kind:seed and compose() already supports seedRoots — the mechanism is built but unwired | works WITH the mask-over-bind invariant (T105 keeps holding); runner stays the gatekeeper of what the session sees | a snapshot step at spawn time (materialize + sanitize) | loop materializes a host-config snapshot and passes seedRoots |
| A0 bare ro-bind of the directory | one bwrap arg | none — masks win (silent no-op) or the bind lands after the mask and violates maskOverBindHolds, which T105 asserts | rejected by red team R1-F3/R2-F5/R3-F1 | none (rejected) |
| sanitized single-file injection | runner merges config and binds one file | smaller exposure | a second config channel diverging from the profile system | folded into seed materialization (below) |

why-not: A0 — the target path is a mandatory mask token; the bind is
either dead or invariant-breaking; single-file — the seed mechanism
already provides the sanctioned channel.

Semantics:

- **Sanitized snapshot**: at spawn time the runner reads the host
  opencode config, strips or rejects entries carrying secrets
  (`apiKey`, `mcp` server definitions with env/headers) — an
  `auto on` preflight warns when the host config carries such fields —
  and writes the sanitized tree to a machine-local snapshot dir passed
  as `seedRoots` to compose(). Seeds mount read-only at the mask
  point; auth.json handling stays exactly as is.
- **Deny precedence**: the injected deny union rides
  OPENCODE_CONFIG_CONTENT; the host-matrix gains a probe asserting the
  env config wins over the seeded disk config for permission keys; a
  host failing the probe degrades (no seed) with a loud line.
- **Symlink/absent handling**: source must realpath to an existing
  directory inside the readable host area, otherwise the seed is
  skipped with an advisory line (never silent); dotfiles-repo symlink
  layouts resolve before snapshotting.
- **Odd-path fixtures**: the new snapshot/seed paths get the
  spaces/unicode/symlink fixture treatment (concern 577f0bfb).

### D-3 Captured-stream integrity floor (red-team forced scope)

The tail-only 64MB capture lets benign output push early deny lines
out of the window before the escape detector scans — an blinding
vector now that spawns can write. Minimum floor in this task: deny-hit
scanning runs over the PRE-truncation stream (or a head+tail dual
window); the breaker trip message no longer embeds spliced fragments
(the detail line renders parsed fields, not raw slices). Full stream
capture redesign stays deferred with an explicit ruling recorded in
concerns.

## Scope

- bin/lib/core/lock.cjs — spawn channel (registry/claim/whitelist),
  boot_id+starttime binding, evaluation order, no-ownership pass,
  CONTRACTS banner, acquireLockAt marker refusal
- bin/lib/ops/auto/loop.cjs — registry writer, seedRoots wiring,
  heartbeat coverage for delegated legs, crash-window snapshot
  classification, deny pre-truncation scan
- bin/lib/ops/auto/launcher.cjs — seed materialization hooks (as the
  compose() contract already defines), sanitized snapshot
- bin/lib/nav/cli.cjs / cmds.cjs — approve/archive/push/disposition
  marker-active refusal
- bin/lib/task/commit.cjs — snapshot-before-advance, baseline
  exclusion reordering
- CONTRACTS + locales — spawn-channel banner, marker-refusal texts
- test/sections/ — truth coverage incl. real-family pid fixtures
  (no /proc env hook — that would be a forgery vector), T105 seed
  assertions, odd-path fixtures

Out of scope: model selection policy, full stream capture redesign,
task-id collision (recorded separately), the publishLeg foreign-branch
mismatch (concern recorded — separate fix), unification of the three
existing lock-exemption concepts (7d63cd9d interplay noted there).

## Observable Truths

- T1: under a live runner-held lock with a registered spawn entry, the
  assigned `gos commit <stage>` from a real descendant process
  completes with the spawn-channel banner (real pid ancestry, section
  fixture).
- T2: negative space — a forged marker with holder pid 1, a marked process
  outside the registry window (wrong/missing spawnId), an exhausted window
  budget, a non-whitelisted write command (incl. `truth add`), a redteam
  spawn's write attempt, and approve/archive/push/disposition under the
  marker: each is refused, each with its classified message.
- T3: seed form — with a host config dir present, compose() emits the
  seed ro-binds after the mask and maskOverBindHolds still passes
  (T105); absent host dir skips the seed with an advisory; host config
  carrying apiKey/mcp is stripped before seeding.
- T4: crash-window — a killed in-spawn advance (fixture: SIGKILL
  between state write and git commit) leaves a snapshot the runner's
  identity re-check rolls back, not an external-mutation pause.
- T5: dogfood mechanism layer — two live-repo rounds exercised the
  registered channel (whitelisted uses consumed by real spawned
  commands), pre-truncation deny capture (complete escalation sequences
  recorded where round 1 produced only spliced fragments), live seed
  sanitization, and clean breaker trips; the behavior layer (spawned
  sessions not executing the assigned workflow) is ruled out of scope
  here and consolidated into the stage-dispatch blueprint (concern
  recorded, separate task).
