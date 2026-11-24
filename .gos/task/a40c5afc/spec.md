# Spec: CI tiering — PR affected-sections tier, main full-suite closeout

> **Date**: 2026-11-24 | **Level**: Lv2 | **Status**: Draft

## Goal

Split section CI into two tiers: pull requests run the affected-sections
subset (`test/run-sections.sh --affected` against the PR merge-base) for
minutes-level feedback, while pushes to main keep the unchanged dual-node
full suite as the closeout gate. The gate audit job stays as is on both
event types. The task also carries the profile-floors rider: the per-stage
auto-loop write floors are decided here, before any BUILD workspace write.

## Motivation

- Concern 834fb3e7: every PR push today burns a dual-node full section
  suite (~11 min x 2 per push; 3 round-trips paid on 2026-11-24). The
  affected mode already exists in the section runner, and same-day fixes
  proved fresh-clone parity evidence only comes from remote CI (local
  `--fresh` is broken, lesson 8457308d) — so the fast tier must be a CI
  job, not a local habit.
- Concern f93c297b (anchored trigger: first real auto-driven task — this
  one): per-stage profile floors must be decided before the BUILD wave
  makes its workspace writes. Backstop was 2026-12-15; the anchored
  trigger fires now.

## Requirements (R-NN)

- **R-01**: ci-tiering: PR CI runs affected sections plus gate audit for
  minutes-level feedback, main keeps the dual-node full suite (auto from
  intent).
- **R-02**: a pull request whose diff contains a `test/sections/T*.test.sh`
  file must see that section run in the PR tier — section files select
  themselves, independent of the code-graph pre-filter.
- **R-03**: the per-stage auto-loop profile floors are recorded as a
  decision with dig evidence before the first BUILD workspace write of
  this task.

## Approach

### Selected Approach

`.github/workflows/ci.yml`:

- The existing `sections` job (dual-node full suite) gains
  `if: github.event_name == 'push'` — it becomes the main-push closeout.
- A new `sections-pr` job runs on pull requests with the same steps the
  full job has today (checkout with `fetch-depth: 0`, node matrix 20/22,
  npm install, bubblewrap install, `gate trust check.sh`) but runs
  `bash test/run-sections.sh --affected --base "$GOS_PR_MERGE_BASE"`,
  with `timeout-minutes: 15` and the same failure artifact upload. The
  merge-base resolve step mirrors the gate job's changelog-base resolve
  (verify the base sha is present, fetch if not, `git merge-base`).
- Job name states the subset explicitly ("Sections — affected subset")
  so a green PR check is never misread as a full-suite pass.

`test/run-sections.sh`:

- Self-selection: section-file paths (`test/sections/T*.test.sh`) present
  in the raw input set are kept through (or re-injected after) the
  known/anchored pre-filter, and their section names are added to
  `SELECTED` before the blast result is consumed. A new or edited section
  always runs on its own PR.

No other workflow changes. `workflow-lint` constraints hold: the new job
inherits the top-level `permissions: contents: read`, the `needs` graph
stays acyclic (no new edges), `on:` and `jobs:` remain.

### Alternatives (Rejected)

- ~~Single node 22 on the PR tier~~: the PR matrix is the only pre-merge
  place node 20 runs; a node-20-only break would surface after the
  squash-merge lands on main. Affected subsets are small enough that the
  second node costs little wall time and a modest quota slice.
- ~~Nightly or scheduled full runs on PR branches~~: adds a second
  scheduling surface and still burns quota on long-lived branches; the
  main closeout already covers deferred risk.
- ~~Split workflow files (pr-ci.yml / main-ci.yml)~~: duplicates the
  shared steps and lint surface; one file with an `if:` split is smaller
  and keeps the concurrency group unchanged.

## Design Decisions (D-NN)

### D-01: PR tier runs the affected subset on the dual-node matrix; main keeps the full suite

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. affected subset, matrix [20, 22] (chosen) | PR feedback needs the closure of the change, not the whole corpus; node-version parity is a pre-merge concern | minutes-level feedback; no node blind spot; quota drops roughly 5x vs dual full | selection can under-pick (backstopped by main full suite) | the `sections-pr` job every pull request runs |
| B. affected subset, node 22 only | one job is the cheapest tier | fastest, cheapest | node-20 breaks land on main before detection | the PR tier's matrix stanza |
| C. status quo: full dual-node on PR | selection is unproven | zero new machinery | ~11 min x 2 per push; the concern's original cost | nothing — the current `sections` job |

why-not: B — the matrix is the only pre-merge node-20 run, and dropping it
trades a real coverage shape for a small quota slice; C — the per-push cost
is the problem being solved.
recommendation: A — conditional: if quota pressure later outweighs parity,
narrow the matrix then, with a decision.
deepen: closed — dug the matrix shape (ci.yml:88-90), the affected mode's
fail-safes (run-sections.sh:249-330), and the recorded cost (concern
834fb3e7: ~11 min x 2, 3 round-trips on 2026-11-24).

### D-02: Selection base = PR merge-base via a replicated resolve step; empty selection is green, blast failure is red

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. explicit resolve step, `--base <merge-base>` (chosen) | the PR's effective change is merge-base..merge-ref | correct on rebased/behind bases; same pattern as the gate job | one more step in the new job | the `sections-pr` job's first step |
| B. runner default base | the runner already falls back to a base | zero workflow code | the default reads `state.task_head` from committed state (run-sections.sh:258) — a diff artifact, not the PR base | nothing new |
| C. reuse `GOS_CHANGELOG_BASE` from the gate job | the gate job already computes a merge-base | no duplicate resolve | env does not travel across jobs without declared outputs; coupling two jobs for one variable | an `outputs` declaration plus `needs` |

why-not: B — wrong base by construction in CI; C — adds a needs edge and
an outputs contract to save four lines of script.
recommendation: A — the resolve replicates the verify-then-fetch pattern
(gate job, ci.yml:42-58).
deepen: closed — dug the runner's base fallback (run-sections.sh:258),
empty-input exit 0 (:262, :284), and blast-failure exit 1 (:287).

Failure semantics ride the runner's existing lines: empty or
no-graph-relevant input exits 0 with a log line (a docs-only PR is green
in the time it takes to say so); `map blast` failure exits 1 — the PR tier
fails red, never silently green.

### D-03: Section files self-select in affected mode

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. keep `test/sections/T*.test.sh` inputs and inject their names into SELECTED (chosen) | the pre-filter drops .sh paths (only code-graph keys and `gos-map:file` targets survive), so today a new or edited section never runs on its own PR | test-only edits get PR validation; anchor deletion cannot dodge the edited section | small runner patch | the affected-mode block of run-sections.sh |
| B. convention: every section self-anchors via `gos-map:file` | anchors already exist | no runner change | 100+ file churn; convention drift the moment one file forgets | every section file |
| C. rely on the main full suite | main is the backstop anyway | zero change | test-only PRs get zero pre-merge validation — the worst case for iteration speed | nothing |

why-not: B — mass churn for what the runner can do in one place; C —
defeats the PR tier's purpose for exactly the PRs that change tests.
recommendation: A — conditional: the injection must happen even when the
pre-filter would skip the path, and the selection log must show the
self-selected names.
deepen: closed — dug the pre-filter (run-sections.sh:267-279, keeps only
`known.has(l)||anchored.has(l)`) and confirmed zero self-anchors exist
today (`grep -l "gos-map:file test/sections" test/sections/*.test.sh` —
no matches).

### D-04 (profile-floors rider): per-stage auto-loop write floors are the code-pinned profile set

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. ratify the code pins as the floor set (chosen) | the pins already exist and are enforced (dispatch tables cannot override them) | floors are executable facts, not prose; table edits can never widen a stage | changing a floor now means a code edit plus a decision, by design | every auto-loop spawn of every stage |
| B. workspace-default for all stages | task-driving writes are legitimate at any stage | no per-stage reasoning | too blunt — concern f93c297b's own rejection; unrestricted repo writes from THINK/VERIFY workers | every spawn's writable roots |
| C. per-stage profiles editable in the dispatch table | flexibility per deployment | one JSON edit | the pin exists precisely so a table can never grant write surfaces | the dispatch table loader |

why-not: B — rejected when the concern was filed; C — defeats the
mechanism that makes floors trustworthy.
recommendation: A — the floor set, as pinned in code today:

| Stage | Floor | Writable surface |
|:--|:--|:--|
| INTENT / THINK / PLAN / REVIEW / SHIP | `restricted` | `.gos` and `.gos/logs` only |
| BUILD | `workspace` | repo root plus `.gos` |
| VERIFY (agent legs) | `restricted` | `.gos` and `.gos/logs` only |
| VERIFY (script legs) | `restricted` + scratch | writable TESTBASE pin under the store spawn scratch, outside the repo; script writable roots per `scriptWritableRoots` |
| any stage via table | `full` refused | only the explicit CLI capability-upgrade flag can raise to full |

Floor-change rule: floors live in `pinnedProfile` and the compose-time
writableRoots union; any change to either is decision-gated and lands as
a code edit in the same change set — never a table or config edit.
This decision is the pre-authorization record this task's BUILD workspace
writes (ci.yml, run-sections.sh) run under.
deepen: closed — dug the pin (workers.cjs:68), the compose-time writable
roots split (loop.cjs:1771-1776), and the script-leg TESTBASE pin
(workers.cjs:335).

## Scope

### In Scope
- ci.yml: `if:` split of the sections job, new `sections-pr` job.
- run-sections.sh: section-file self-selection in affected mode.
- CHANGELOG entry; census and layout untouched.

### Out of Scope
- Gate, pack, masters, commitlint jobs (unchanged behavior on both tiers).
- Any auto-loop code change — D-04 decides floors, it does not re-implement
  them.
- Local `--fresh` repair (lesson 8457308d — separate debt).
- release.yml and triage-gate.yml.

## Deferred Ideas
- [DI-1]: PR-tier minute-budget alarm or quota telemetry (when quota
  pressure is actually observed, not before).
- [DI-2]: label-triggered on-demand full suite for long-lived PR branches
  (`workflow_dispatch` + label).
- [DI-3]: blast-result caching across pushes of the same PR (only if
  selection cost ever shows up in job timings).

## Observable Truths (T-NN)

- **T-1**: on a pull_request event, the PR sections job runs
  `run-sections.sh --affected` against the merge-base; the job log shows
  the affected-mode selection header and skip lines, and unselected
  sections never execute.
- **T-2**: on a push to main, the full dual-node (20/22) section suite
  still runs.
- **T-3**: a PR whose diff contains a `test/sections/T*.test.sh` file sees
  that section run in the PR tier.
- **T-4**: D-04 is recorded with dig evidence before the first BUILD
  commit of this task (git history order).

## Red Team Record (Lv2+ mandatory before user approval)

Inline self-run in DEGRADED mode (self-attack — no dispatch available in
this session type; shared-prior blind spots cannot be caught this round).

| Round | Perspective | Findings | Dispositions (A/AP/R-with-facts/D) |
|:---|:---|:---|:---|
| 1 | misuse/safety | 2 | F1 green-PR-misread-as-full-pass: ACCEPT — job name carries "affected subset", main full suite stays the closeout (D-01). F2 anchor-deletion dodging selection: ACCEPT-PARTIAL — the deletion edits a section file, so D-03 self-selection forces the edited section to run anyway; anchor removal itself stays review-visible in the diff. |
| 2 | edge/exception | 3 | F1 new/edited section file filtered out by the pre-filter (run-sections.sh:267-279 keeps only known/anchored paths; zero section self-anchors exist): ACCEPT — D-03/R-02. F2 empty-input behavior undefined: REJECT with facts — run-sections.sh:262 and :284 print and exit 0 by construction. F3 base sha absent from a shallow fetch: ACCEPT — D-02 replicates the verify-then-fetch resolve (ci.yml:52-53 pattern). |
| 3 | completeness | 1 | F1 floors must enumerate all seven stages including the VERIFY agent/script split, or the rider is incomplete: ACCEPT — D-04's floor table enumerates INTENT..SHIP with the VERIFY two-leg distinction and the full-refusal rule. Re-attack of R1-F1/R2-F1 after the design changes: no new findings. |

> Disposition key: ACCEPT(design change landed) / ACCEPT-PARTIAL /
> REJECT(factual counter-evidence cited) / DEFER(to DI-n).
> Verdict line: converged (final re-attack round returned zero new findings).

## Risks
- Under-selection ships a break to main → backstopped by the unchanged
  dual-node full suite on main push plus the `gos-map:none` fail-safe set
  that always runs; residual cost is one closeout cycle, accepted.
- Selection machinery depends on map data health → `map blast` failure
  exits red in the PR tier (run-sections.sh:287), never a silent skip.
- Quota: dual-node affected still spends two jobs per PR push — roughly a
  5x net reduction versus today; watch via DI-1 if pressure appears.
