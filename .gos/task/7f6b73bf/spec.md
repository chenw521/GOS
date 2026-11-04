# Spec — Live dogfood of the stage-dispatch auto pipeline

Task: 7f6b73bf · Level 2 · main 7f6b73b (PR #50 merged 2026-11-02)
Baseline: bwrap 0.13.1 sandbox verified, fresh empty store, section suite
37/0 green (2026-11-02 log).

## Intent

Run the new auto dispatch pipeline on live machinery for two full cycles
(`gos auto on --profile workspace` + `gos auto run`), verifying the three
landmarks of the stage-dispatch redesign, then adjudicate one stale
concern. This task observes; it does not modify pipeline code.

## Scope

- IN: driving two auto cycles end to end, reading pause/breaker/telemetry
  artifacts, classifying every pause, recording dispositions, adjudicating
  concern [72b7706e], reporting evidence.
- OUT: any edit to bin/lib/ops/auto/*, the dispatch table, spawnreg, or
  lock family; any repair of bugs the dogfood surfaces (routed per D4).

## Decisions

### D1 — Cycle 2 vehicle: assertion-debt rewrite, collapsed form

The vehicle is concern [4b55189d] as re-classified by a line-level dig
(counting-level dig said 11 grep assertions; classification cut true debt
to 3 and exposed 5 structural source contracts):

- Wave 1: T55-G1 behavior rewrite (changelog-core single-source becomes an
  observable lint behavior) + T57 missing negative assertion (the malformed
  spec_path fixture becomes a consumed rejection test).
- Wave 2: T61-E1 behavior rewrite (gate wiring observable through gate
  output) + exemption annotations for the five structural source contracts
  (T51-E ×1 group, T51-F1/F2, T61-E2 dual-source sync, T55-L134 CJK scan).
  The vehicle delivery also corrects the misclassification inside concern
  [4b55189d] itself.

Pre-adjudication rule: the rewrite-vs-exemption list is fixed by the
observer in the vehicle prompt BEFORE `auto on`; spawned agents make no
discretionary calls. Evidence basis: T51 header self-declares "(static)",
F1/F2 is an abuse-count contract (commit.cjs:547 sole --allow-empty
spread; L250 exemption key) with no behavior surface, T61-E2 checks
dual-source sync that has no external behavior face.

Cycle 1 vehicle: first item of concern [6dd52a5c] only (stage back without
reason must refuse or demand explicit reason — stage.cjs:20 currently
silently templates it). Single-file, ~10 lines, one wave. Both vehicles sit
outside the auto family (runner-critical boundary verified:
bin/lib/ops/auto/ only), so no table-stamp rolls mid-run.

### D2 — Pause handling: six-family whitelist (closed set), one action each

The loop/workers emit 40+ distinct pause reasons (verified by enumeration);
they collapse into six families, each with exactly one permitted action:

| Family | Members (representative) | Only permitted action |
|:--|:--|:--|
| F-ext external mutation | external-mutation, advance-state-mismatch, orphan-pending-unrecoverable, dispatch-table-drift, prompt-template-drift, pin-tampered | attribute → disposition → at most ONE deliberate resume (`auto run`) |
| F-contract wave accounting | completion-unattributable, post-wave-unreadable, post-crash-evidence, wave-held, advance-check-failed | route to D4 (never retry — a contract break will recur) |
| F-held design holds | delegation-held (red-team findings), delivery-held red-run/subject-lint/ci-watch-timeout/no-disposition, ratify-refused, redteam-round-failed | surface to user, dogfood pauses — these are gates working, not faults |
| F-infra machinery | compose-failed/refused, launch-failed, host-*, spawn-register-failed, grant-manifest-failed, leg-*, refs-unreadable, git-failed, state-corrupt/unreadable, breaker-unavailable, budget-write-failed/budget-read-failed, no-head, dispatch-table-unavailable/-unreadable, work-branch-failed, build-entry-refused, worker-plan-unresolved | NO recovery — route to D4 bug flow |
| F-usage driver mistakes | no-task, mode-off, marker-active, detached-head, invalid-*, wrong-branch, unknown-profile, stage-invalid | fix the driver-side invocation once and re-enter (not a retry: parameter error, not a failure repeat) |
| F-trip breaker | breaker-tripped | read breaker cls BEFORE `auto on`; at most one re-enable per cycle (re-enable = `auto on` after trip; resume = `auto run` after pause — distinct acts) |
| F-unknown unmatched | any reason not matched above (the emitted set drifts as code lands) | NO resume, NO abort — write attribution line, surface to user for explicit family ruling |

Protocol discipline: before acting on any pause, the observer writes one
attribution line + one action line in the session log (user-auditable).
Blind retry is prohibited (task input constraint; external-mutation never
counts into the consecutive layer — locale contract).

### D2a — Mechanized pre-flight gates (red-team R1 findings 1/2/6/7/10)

Text rules above are backed by grep-able gates the observer MUST run
(dispositions currently have no loop-side consumer — delivery-publish.cjs
is the only reader — and every `auto run` rebases the baseline, so the
resume discipline is otherwise unenforceable):

- G0 slot-gate (task slot parking): `auto on` never creates a task — the
  loop drives the single active task in .gos/state.json, and that slot is
  held by THIS task. Before cycle 1, with explicit user approval:
  (a) commit .gos/state.json + .gos/task/7f6b73bf/ to a park branch and
  record the ref (init --force dies on uncommitted spec — commit first);
  (b) pin all observer evidence OUTSIDE the task zone (see log path
  below) so --force's rmSync cannot touch it; (c) `gos init 3 "<vehicle
  intent with pre-adjudicated constraints>"` takes the slot for the
  vehicle; vehicles MUST be Lv3 — the wave driver refuses BUILD without a
  frozen plan snapshot (workers.cjs snapshot-empty fail-closed); (d)
  after both cycles and vehicle archive, restore the observer task from
  the park ref (git checkout <ref> -- .gos/state.json .gos/task/7f6b73bf)
  and continue THINK→TRACE there.
- G0b family-coverage gate: pre-flight diffs the full emitted reason set
  against the six families + F-unknown, using a pinned extraction (exact
  one-liner + exclusion patterns committed in the task dir — ad-hoc
  curation makes the gate itself drift): literals must match an exact
  family member or a declared wildcard (invalid-*, host-*, leg-*, or the
  F-unknown row); the family table used for the diff has exactly one row
  per family name.
- G1 resume-gate: before any deliberate resume, assert the paused runId
  has a matching entry in store dispositions AND resume count for that
  runId ≤ 1 (count from the session log + report files).
- G2 mirror-gate: at every pause, record store counters (tripCount,
  spawnCount) in the session log; before resume, assert current store
  values ≥ recorded (detects budget laundering — consecutive/visits reset
  per run by design, only B is cumulative).
- G3 tier-gate: after each run, assert every run-report iteration entry
  whose spawnId does NOT end in `-exit` carries tier === 'bubblewrap'
  (telemetry stamps carry no tier field — R2 finding; `-exit` script-leg
  entries are tier:null by design and excluded; script-leg tier
  unobservability is logged as a mechanization concern). A 'lexical'
  entry is a post-hoc F-infra event → D4.
- G4 snapshot-gate: sha256 of store.json into the session log before each
  cycle; `auto off` is FORBIDDEN between cycles (purge is unguarded rmSync
  — one keystroke erases every T1–T4 artifact); every TRACE evidence claim
  cites the hash it was read under.
- G4b continuity-gate: cycle 2 pre-flight asserts store continuity —
  cumulative spawnCount ≥ the value recorded at cycle 1 end, AND at least
  one cycle-1 runId still present in the store; failure = abort + D4-BLOCK
  (evidence destroyed).
- G5 plan-gate (bidirectional): after the vehicle's PLAN snapshot freezes
  and before `auto run` drives BUILD, assert set-equality: snapshot wave
  declared files == the D1 adjudicated list — extra, MISSING, or
  empty-vs-nonempty mismatch all abort (a wave omitting **Files** freezes
  as files:[] and would bypass a one-way diff). Validate each declaration
  is a bare repo-relative path (no `:line` suffix, no spaces) before the
  diff — plansnap keeps line-number suffixes that never match git paths.
- G5b exemption-count gate: post-run grep of the vehicle diff for
  exemption annotations — count == 5 and keys ⊆ the adjudicated set
  {T51-E, T51-F1, T51-F2, T61-E2, T55-L134}; any other exempted contract
  fails the gate (G5 enforces file sets, not annotation content).
- G5c behavioral deny-probe (cycle 2, best-effort): if a probe spawn can
  be constructed without violating pre-adjudication, run one harmless
  forbidden verb from a marked spawnId and assert its denyHits increments
  (converts tier certification from argv-adjacent reading into behavioral
  evidence — lesson 881b50bc); the probe's stamp is excluded from T3(a).
  If construction is not clean, log as residual concern instead.

Vehicle intent template (pinned verbatim — both cycles; fill only the
brackets):

  "Store dir ~/.local/share/gos/85af56a090a78924 is live dogfood
  evidence — never delete, reset, or overwrite it; any fixture store
  must be XDG-overridden inside the sandbox. Model policy: accept the
  dispatch-table pinning; no model substitution. Human takeover at the
  advance step on pause is expected behavior, not an anomaly. Work only
  the files the frozen plan snapshot declares for these tasks:
  [D1 adjudicated file list]. Deliver [vehicle-specific scope]."

Pre-flight store-fence assertion: the vehicle task's declared/diffable
files contain no direct reference to the real store path.

- G6 delivery-gate (probe sandwich): before EVERY `auto run` (not just
  cycle 1) AND after each run, assert the store's delivery probe is
  non-green. There is NO interception point between probe-green and merge
  (delivery-publish merges directly on green CI; dispositions are read
  only on the red/unknown path — code-verified). If a post-run probe is
  green = a merge has happened: freeze the dogfood, report the PR to the
  user for retroactive disposition, re-run
  `bash test/checks/push-lint-squash.sh --subject` against the merge
  subject, record per D4-BLOCK.

Observer session log path (pinned): .gos/logs/dogfood-7f6b73bf/session.ndjson
— outside the task zone, immune to init --force rmSync, machine-local;
G1 counts and G2 counter records must be greppable from exactly this file.

D1 adjudicated file list (the G5 diff base, verbatim):
cycle 1 = bin/lib/task/stage.cjs, test/sections/T51-commit-guard.test.sh
(any assertion additions for the new refusal land in T51);
cycle 2 = test/sections/T55-changelog-lint.test.sh,
test/sections/T57-archive-single-track.test.sh,
test/sections/T61-gate-wiring.test.sh.

### D3 — Concern [72b7706e] prune: two-layer evidence

- Static layer (VERIFIED): the old false-positive path is structurally
  gone — `iter.advanced` now comes from `breakerMod.detectAdvance` git
  evidence (loop.cjs:1423/1512), not spawn self-report; the top-of-loop
  lateAdvance reconciler (loop.cjs:755-768) absorbs exactly the old
  signature (spawn-attributed advance settling one read after its commit:
  stage-only delta + forward move + pendingLeg.advanced);
  rc0-no-advance is excluded from mutation-pause (loop.cjs:1180).
- Dynamic layer (PENDING): both dogfood cycles complete with zero
  same-signature pause (advance commit present + stage-only delta +
  non-pause absorption).
- Ruling: both layers green → prune with the evidence chain in the
  disposition. Same-signature pause observed → keep the concern, append
  recurrence-confirmed with live evidence.

### D4 — Bug exposure routing: severity × timing matrix

- BLOCK (loop dead / store corrupt / table mismatch): abort dogfood,
  snapshot evidence (store json + run log + section-runs log), open a
  MANUAL fix task (own level, fast-track Lv1 allowed). Manual — never
  auto: the observer must not become the executed (feral history:
  [3c36cb07] spawns attempted gos auto recursion; refuseIfSpawned gates
  exist for the same reason). Mechanical anchor: the fix task's spec
  declares manual-only, and TRACE asserts zero run-start/report artifacts
  inside the fix window (a grep gate; the flag itself is a mechanization
  concern below).
- MAJOR (a verification landmark fails while the loop lives): record as
  gap, end that cycle, fix goes through a feature-branch task.
- MINOR (telemetry blemish / hint error): log to concerns, dogfood
  continues, batched at TRACE.
- Whether a post-fix cycle 3 re-runs the affected landmark is the user's
  call at the dogfood report, not automatic.

### D5 — Post-cycle integrity assertions (red-team R1 findings 5/8)

- Claims cross-check: every adopted advance / wave commit in the store
  must have an admitted commit claim for its spawnId in the spawnreg
  claims ledger — a spawn forging a state.json edit + stage-labeled
  subject would otherwise be adopted by the lateAdvance reconciler with
  no pause (forward-adoption path has no hash gate; only the rollback
  path does).
- T3 redefined over runner-recorded, grep-able facts (self-reported
  telemetry is advisory and non-gating by design):
  (a) all telemetry stamps denyHits == 0;
  (b) zero breaker records with cls takeover|env;
  (c) zero claims-ledger entries outside the stage's granted verb set;
  (d) every dual-window capture sidecar passes hash match;
  (e) zero adopted advances lacking a claims cross-check match;
  (f) feral signature list (from [3c36cb07]/[0f528c0e]): spawn attempting
  gos-auto recursion, privilege escalation, push/merge/approve verbs,
  OR protocol-internal zero execution while telemetry shows activity.

## Mechanization concerns surfaced by red team (log at TRACE, not this task)

1. Loop pauses are not disposition-gated (dispositions consumed only by
   the red-CI delivery gate) — resume discipline is unenforceable today.
2. Breaker consecutive/visits are per-run memory; only B persists —
   resume launders failure budgets.
3. Telemetry stamps carry no sandbox tier field — lexical degradation
   invisible in the named evidence source.
4. Forward-advance adoption has no runner nonce/claims gate (rollback
   path does) — a forging spawn is adopted silently.
5. No task-level manual-only flag the auto family refuses at `auto on`.
6. Sandbox keeps network — sanctioned spawns can fetch/exfiltrate without
   tripping refs or deny checks (threat model unstated).
7. `auto off --purge` is an unguarded rmSync advertised by the CLI.
8. Script-leg spawns have no observable tier in run reports (tier:null
   hardcoded) — script-worker sandbox posture is unverifiable from
   artifacts (R2).
9. No interception point between a green delivery probe and squash-merge
   to main — green closes directly; dispositions only gate red/unknown
   (R2, delivery-publish.cjs).

## Observable Truths

- T1: zero run-report iteration entries with stage === VERIFY and worker
  kind !== script (machine predicate — agent spawns at THINK/PLAN/REVIEW
  of the Lv3 vehicle are legitimate and out of scope); script-worker and
  pinned-leg entries at VERIFY carry the D-54 fields (model pin where
  applicable, command counts, denyHits).
- T2: every BUILD wave leaves three-contract evidence — exactly one commit
  in its pre/post refs range with paths ⊆ declared set; no ref moves
  besides the work-branch tip; breaker records carry W<n> unit labels.
- T3: zero feral-signature events per the D5 grep-able checklist
  (denyHits, breaker cls, claims verb-set, sidecar hashes, claims
  cross-check, signature list (a)–(f)); any pause that does occur has an
  attribution line + compliant family action + disposition record where
  the family requires one.
- T4: concern [72b7706e] leaves the table with a ruled outcome: pruned
  with both evidence layers, or kept with recurrence-confirmed.

## Execution sequence

1. Pre-flight: G0 slot-gate (user-approved park: commit task zone → park
   ref → init vehicle Lv3) + G0b family-coverage diff + G4 store snapshot
   + G6 delivery probe assert + bwrap presence probe — before any
   `auto on`.
1a. Observer-crash recovery (mandatory on ANY observer session restart):
   tail session.ndjson, re-assert G2 mirror (store counters ≥ last
   recorded) + G6 probe assert BEFORE any next action; a restart that
   landed mid-`auto run` additionally re-runs G3 on the completed run
   report before proceeding.
2. Cycle 1: vehicle [6dd52a5c]-item-1 (Lv3, pinned intent template with
   the pre-adjudicated file list) → `auto on --profile workspace` → G5
   plan-gate after PLAN freezes → `auto run` → classify pauses per D2
   families; G1/G2 gates guard any resume; G3 tier-gate + G5b
   exemption-count + D5 claims cross-check after the run; G6 post-run
   probe assert.
3. Cycle 2: vehicle [4b55189d] collapsed 2-wave form (Lv3, same
   constraints) → G4b continuity-gate + same gate battery + G5c
   behavioral deny-probe (best-effort) → verify T1/T2 landmarks from
   store telemetry + refs snapshots + breaker records.
4. Restore observer task from park ref — with conflict protocol:
   `git diff <park-ref> HEAD -- .gos/state.json` must show only
   vehicle-slot transitions (any other delta → user ruling before
   restore); restore lands on a branch, merges via PR (main is PR-only).
   Then adjudicate [72b7706e] per D3 (dynamic layer = T3 evidence).
5. TRACE report: three landmarks + feral ruling + bug list (if any) with
   D4 dispositions + evidence hashes (G4) + mechanization concerns filed
   to concerns.md.

## Observation evidence sources

- ~/.local/share/gos/85af56a090a78924/store.json — telemetry stamps,
  breaker records, dispositions, snapshots
- .gos/cache/section-runs/ — persisted section logs (read before any
  suite re-run)
- run manifest + refs snapshots recorded by the wave driver
- stream logs (spawn telemetry, dual-window capture)

## Red Team record (3 rounds, Lv2 mandatory set)

- R1 misuse: 10 findings (2C/7M/1m) — all ACCEPT; landed as D2 six-family
  table, D2a G1-G6, D4 anchor, D5 checklist, T3 redefinition.
- R2 edge: 7 findings (1C/4M/2m) — all ACCEPT; landed as G0 slot-gate +
  Lv3 vehicle constraint, G0b coverage, G3 rewrite (iteration tier),
  G5 bidirectional, G4b continuity, G6 sandwich, pinned log path.
- R3 completeness: 9 findings (1H/4M/4L) — 8 ACCEPT + 1 ACCEPT-PARTIAL
  (G5c best-effort probe); landed as store-fence intent template,
  observer-crash recovery 1a, park-ref conflict protocol, T1 machine
  predicate, G5b exemption-count, G0b pinned extraction, F-held dedup.
- Zero REJECT across all rounds; round-over-round landing verified by the
  attacker subagent (R2/R3 Part-1 tables: all landed, one defect caught
  and fixed at R3-5).

## Deferred

- Vehicle [6dd52a5c] item 2 (commit-forward open-gap check) — separate
  small task, not part of this dogfood.
- Router/think gate mechanization concerns logged 2026-11-04 — belong to
  the next router/intent UX phase, not this task.
