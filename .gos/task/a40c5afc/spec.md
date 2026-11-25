# Spec: CI tiering — PR affected-sections tier, main full-suite closeout

> **Date**: 2026-11-24 | **Level**: Lv2 | **Status**: Draft

## Goal

Split section CI into a three-tier flow: pull requests run the
affected-sections subset plus the cheap whole-tree invariant sections
(`test/run-sections.sh --tier pr --base` against the PR merge-base) for
minutes-level feedback; pushes to main run the heavy `gos-map:none`
complement, the invariant re-run, and a merge-diff blast closure that
runs every landed commit's own affected sections on main. The gate audit
job stays as is on both event types. The task also carries the profile-floors rider:
the per-stage auto-loop write floors are decided here, before any BUILD
workspace write.

## Motivation

- Concern 834fb3e7: every PR push today burns a dual-node full section
  suite (~11 min x 2 per push; 3 round-trips paid on 2026-11-24). The
  affected mode already exists in the section runner, and same-day fixes
  proved fresh-clone parity evidence only comes from remote CI (local
  `--fresh` is broken, concern adf8d93a) — so the fast tier must be a CI
  job, not a local habit.
- Concern f93c297b (anchored trigger: first real auto-driven task — this
  one): per-stage profile floors must be decided before the BUILD wave
  makes its workspace writes. Backstop was 2026-12-15; the anchored
  trigger fires now.

## Requirements (R-NN)

- **R-01**: ci-tiering three-tier flow: PR CI runs affected sections plus
  the cheap whole-tree invariant sections for minutes-level feedback; main
  runs the heavy `gos-map:none` complement, the merge-diff blast closure
  (every commit landing on main carries its own affected-section closure),
  and the invariant re-run (auto from intent). The invariant family is an
  explicit frozen enumeration carried by the runner's `--tier`
  implementation (T46 module counts, T66 census, T85 security-depth,
  T102 ai-trace, T109 changelog structural — the same five-member set
  D-03 and Risks pin; rt1-F3/rt2-F-3 at c5c0f2d0: R-01 was the stale
  four-member copy) — membership changes are decision-gated code
  edits.
- **R-02**: a pull request whose diff contains a `test/sections/T*.test.sh`
  file must see that section run in the PR tier — section files select
  themselves, independent of the code-graph pre-filter. Documented trade
  (ruling 2026-11-24, option A): `gos-map:none` heavy auto-family sections
  are excluded from the PR tier and ride the main closeout — auto-family
  regression surfaces at merge time in exchange for minutes-level PR
  feedback. Exclusion mechanism (rt1-F1/rt2-F-1 at 1650d812): the
  affected-mode map:none fail-safe floor skips `gos-tier:main`-marked
  sections in the PR tier (cheap unmarked map:none sections keep PR
  coverage); the marker set is enumerated and decision-gated exactly like
  the invariant family; this task's BUILD seeds the markers on the heavy
  auto-family sections.
- **R-03**: the per-stage auto-loop profile floors are recorded as a
  decision with dig evidence before the first BUILD workspace write of
  this task.

## Approach

### Selected Approach

`.github/workflows/ci.yml`:

`.github/workflows/ci.yml` + `test/run-sections.sh` (the runner gains the
tier-roster capability this design needs — rt2-F4: neither tier's roster
is expressible today; the runner has exactly machine/fresh/affected
modes):

- New runner flag `--tier <pr|main>`: `--tier pr` selects the affected
  subset against `--base` (existing machinery) UNION the invariant
  enumeration UNION the unmarked-`gos-map:none` fail-safe floor (the
  existing affected-mode floor at run-sections.sh:293-299 keeps every
  unmarked map:none section running; the marker exclusion is the only
  strip — rt1-F1 at c5c0f2d0: this floor term was missing from the
  formula, and the quota derivations below follow the wrong roster),
  MINUS `gos-tier:main`-marked sections; `--tier main`
  selects the `gos-map:none` family UNION the invariant enumeration UNION
  the affected subset computed against the PREVIOUS main head (the merge's
  own diff — this covers composition and the merge-before-green case:
  whatever a PR tier skipped or an ungreen merge dodged, its blast closure
  still runs on main, rt2-F1). Marker validation: `gos-tier:main` on a
  non-`gos-map:none` section is a roster-build error (rt1-2/rt2-F2: an
  unvalidated marker orphans a section from both tiers). No tree guard,
  no manifest artifact — deleted entirely (rt1-1/rt2-F3: the
  manifest-coverage backstop was permanently red by construction on
  partial rosters; dropped to review discipline plus DI-4).
- Invariant-union placement (rt1-F2 at c9b172bd): the invariant union
  joins SELECTED at the same early point as the self-selection — BEFORE
  both empty-input exits — so a docs-only PR still runs the invariant
  floor rather than exiting green with zero sections. The exits
  re-predicate to `INPUT_FILES empty AND SELECTED empty` for the same
  reason. The blast assignment MERGES into SELECTED rather than
  replacing it (rt2-F-2 at c5c0f2d0: run-sections.sh:287-302 reassigns
  SELECTED from the `map blast --json` output on every code-touching PR
  — a replace drops the invariant union from SELECTED unless blast
  re-selects those sections, re-introducing the single-anchor starvation
  class the invariant family exists to prevent): the blast mustRun set
  and the map:none floor join the EXISTING SELECTED (set union), and the
  invariant union re-asserts after the blast assignment.
- The existing `sections` job (dual-node) becomes the main-push closeout
  running `bash test/run-sections.sh --tier main --base <previous-main-head>`
  (base resolve mirrors the gate job's pattern, hard gate: failed base
  resolve is red; the previous-main-head sha comes from the push event's
  `before` field with a fallback to `HEAD~1` semantics documented in
  the job). Zero-sha and force-push `before` values are pinned,
  mirroring the PUSH_BEFORE precedent the commitlint job already
  special-cases (rt1-F4 at c5c0f2d0): `before` = 40×"0" (branch-creation
  push) resolves to `HEAD~1`; an unreachable `before` (force-push,
  platform-permitted until branch protection lands per concern
  98c5d641) falls back to merge-base against the fetched history — and
  every resolve failure stays red (fail-closed direction unchanged).
  timeout-minutes derived from the complement family's measured
  wall time (~8-9 min) plus install overhead PLUS the merge-blast
  additivity (a wide merge touching heavily-linked files can select a
  large anchored fraction, approaching full-suite wall time — the budget
  must accommodate it or legitimate wide merges false-red, rt1-F3 at
  c9b172bd), and the same failure artifact upload.
- A new `sections-pr` job runs on pull requests with the full job's step
  shape plus an explicit `fetch-depth: 0` checkout (the current sections
  job sets no fetch-depth, ci.yml:92; the gate job does, ci.yml:34; other
  jobs vary — commitlint sets 0 at ci.yml:170, the alarm sets 1 at ci.yml:222;
  rt2-F6), node matrix 20/22, npm install, bubblewrap install, `gate
  trust check.sh`, and runs `bash test/run-sections.sh --tier pr --base
  "$GOS_PR_MERGE_BASE"` with `timeout-minutes: 15` (derived: invariants
  ~1-2 min + install ~3 min + affected subset + the unmarked map:none
  floor term from D-01, WITH merge-blast
  additivity allowance — a PR touching core hubs selects a large
  anchored fraction, the same rule the main tier's derivation carries,
  de71f597-rt2-F-2) and the same failure artifact upload. The merge-base resolve is a HARD GATE: failed or
  missing base sha fails red; a resolved base with an empty diff is
  legitimately green (docs-only PR).
- Job names state the tier explicitly ("Sections — PR tier (affected +
  invariants)" / "Sections — main closeout (complement + merge-blast +
  invariants)") so a green check is never misread as a full-suite pass.
- Concurrency (rt2-F-3 at 1650d812, amended v9 per rt2-F-1 at
  de71f597, re-pinned v10 per rt1-F2/rt2-F-1 at c5c0f2d0): GitHub
  cancels at the RUN level — with the workflow-level group
  `ci-${{ github.ref }}` + `cancel-in-progress: true` in place, a newer
  push to main cancels the entire older workflow run INCLUDING its
  closeout job, and no job-level group can rescue it (the v9
  job-level-only fix was ineffective against run-level cancellation).
  The workflow-level `concurrency` block is REMOVED and concurrency
  moves to per-job declarations: PR-tier jobs carry `ci-${{ github.ref }}`
  with `cancel-in-progress: true` (superseded pushes are wasteful to
  run); the main closeout job carries its OWN group
  (`ci-main-closeout`, `cancel-in-progress: false`) AND the
  pending-cancellation caveat is closed with an explicit `queue: max`
  (GitHub's queue semantics cancel an older PENDING run when a newer one
  queues even without cancel-in-progress — `queue: max` opts out,
  keeping every queued closeout; solo-maintainer velocity makes
  unbounded queue growth a non-issue). Without a workflow-level group
  nothing cancels the closeout run itself. The main tier's merge-diff
  blast computes against the last COMPLETED main head, which under
  no-cancel queuing is the immediately-prior commit.

`test/run-sections.sh` selection semantics (all tiers):

- Self-selection: section-file paths (`test/sections/T*.test.sh`) present
  in the RAW input set have their section NAMES re-injected into
  `SELECTED` — computed from the raw diff BEFORE both empty-input exits
  (run-sections.sh:261-263, :283-285; rt1-F2 at 966e04e2: a test-only
  PR's diff is all `.sh` paths, the pre-filter empties the set, and the
  current code exits green before any injection could fire) — and never
  their paths into the `map blast` argv (blast rejects `.sh` paths,
  map/index.cjs scan-unknown; the kept-through shape is forbidden —
  every PR touching a section file would go permanently red). Two
  predicate changes (rt1-F1/rt2-F1 at 966e04e2): (a) both empty-input
  exits re-predicate to `INPUT_FILES empty AND SELECTED empty`; (b) the
  `map blast` call is skipped when INPUT_FILES is empty with SELECTED
  non-empty (blast dies on zero argv by construction, map/index.cjs:225).
- Deletion gap (accepted, documented): a DELETED section file escapes
  selection on every tier (the runner iterates existing files). Review
  discipline covers the residual; DI-4 tracks a roster-shrink detector
  for full-suite runs (rt1-1/rt2-F3 at b9e370f6 killed the v4
  manifest-coverage wiring: the check requires the full on-disk roster
  and a partial run can never validate — happy-path main would be
  permanently red by construction).

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

### D-01: Three-tier flow — PR affected+invariants−tier:main; main complement+merge-blast+invariants; runner gains the `--tier` roster capability

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. tiered rosters via a new `--tier` flag; main = complement ∪ invariants ∪ affected(merge-diff vs prior main) (chosen) | the 2026-11-24 evidence (rt rounds 1-8) shows (i) misses concentrate in whole-tree invariant sections, (ii) the heavy spawn family needs a guaranteed main slot, (iii) merge-before-green and composition require the merge's own blast at main, and (iv) partial-roster manifests cannot validate (manifest-coverage contract) — so the v3/v4 tree-guard and manifest-artifact interludes are withdrawn | minutes-level PR feedback; every commit landing on main carries its own blast closure (covers composition, merge-before-green, and PR-tier skips uniformly); no artifact trust, no tree comparison, no permanently-red-by-construction wiring | a stale map edge can starve an anchored section on all tiers (blast-wrong, not blast-fail) — mitigated by DI-3 nightly-full insurance; the gos-map:none auto-family regression surfaces only at merge (accepted trade, ruling 2026-11-24 option A) | the `--tier` flag, the `sections-pr` job, the tiered main job |
| B. PR affected only; main unchanged full suite | smallest diff | simple | rt2-F4: the tiered rosters are not expressible without the runner feature anyway; the map:none floor keeps PR slow; full-at-main keeps the 11-min closeout cost | nothing |
| C. status quo: full dual-node on PR | selection unproven | zero new machinery | ~11 min x 2 per push; the concern's original cost | nothing — the current `sections` job |

why-not: B — F4 makes it a non-starter without the same runner feature A
adds, and it keeps both costs; C — the per-push cost is the problem being
solved. Tree-guard family (v3/v4 interlude) — retired by evidence: two
incarnations (manifest fingerprint, git refs/pull fetch) each drew
permanently-red or silently-degraded findings (rt2 at 966e04e2, rt1/rt2 at
b9e370f6); the merge-diff blast subsumes both use cases with one mechanism.
recommendation: A — quota stated honestly: PR tier = invariants (~1-2 min)
+ install (~3 min) + affected subset + the unmarked map:none fail-safe
floor (on-disk census: 24 map:none sections, 21 inside the T103-T136
marker-kin range — every unmarked one stays in every PR run;
rt1-F1 at c5c0f2d0: this floor term was missing from the quota and
timeout lines); main tier = complement (~8-9 min) +
merge-blast + invariants; full suite remains the escalation on nothing
scheduled — DI-3 adds nightly-full insurance if blast-staleness is ever
observed. timeout-minutes derives from these measured floors.
deepen: closed — dug the matrix shape (ci.yml:88-90), affected fail-safes
(run-sections.sh:249-330), the map:none floor (293-299, 24/137),
manifest-coverage's full-roster contract (rt1-1/rt2-F3 at b9e370f6), and
the recorded cost (concern 834fb3e7).

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

Failure semantics ride the runner's existing lines with one hard gate
added: a merge-base resolve that FAILS (base sha unfetchable, empty
resolve) fails the job red — a resolved base with an empty diff exits 0
green (a docs-only PR is green in the time it takes to say so); `map
blast` failure exits 1 — the PR tier fails red, never silently green.
The silent-zero-section-green vector (rt1-F1: verify-fetching only the
PR head sha leaves `--base ""` falling back to task_head/HEAD, empty
diff, exit 0) is closed by the hard gate, not by the fallback.

### D-03: Section files self-select in affected mode

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. re-inject section NAMES into SELECTED after the pre-filter (chosen; the kept-through shape is forbidden) | the pre-filter drops .sh paths (only code-graph keys and `gos-map:file` targets survive), so today a new or edited section never runs on its own PR; blast argv accepts map keys only — section paths fed to blast die on scan-unknown (map/index.cjs) since `.sh` is outside MAP_EXTS and sections carry zero self-anchors | test-only edits get PR validation; anchor deletion cannot dodge the edited section; the blast filter stays untouched | small runner patch | the affected-mode block of run-sections.sh |
| B. convention: every section self-anchors via `gos-map:file` | anchors already exist | no runner change | 100+ file churn; convention drift the moment one file forgets | every section file |
| C. rely on the main full suite | main is the backstop anyway | zero change | test-only PRs get zero pre-merge validation — the worst case for iteration speed | nothing |

why-not: B — mass churn for what the runner can do in one place; C —
defeats the PR tier's purpose for exactly the PRs that change tests; the
kept-through variant of A — rt1-F2 showed it feeds section paths into
blast argv and every PR touching a section goes permanently red.
recommendation: A — the re-injection must happen even when the pre-filter
would skip the path, only section NAMES enter SELECTED (paths never reach
blast argv), and the selection log must show the self-selected names.
Marker interaction (v5): `gos-tier:main` is valid ONLY on
`gos-map:none` sections — a marker on an anchored section is a roster
error; the PR tier drops marked sections except when the section file
itself is in the diff (rt1-2/rt2-F2 at b9e370f6: an unvalidated marker
orphans a section from both tiers).
Invariant membership (v6, amended v7 per rt1-F2/rt2-F-2 at 1650d812):
the invariant family is a FROZEN ENUMERATION CONSTANT carried by the
`--tier` implementation itself — the REAL section names T46 (module
counts), T66 (census), T85 (security-depth, added v9 per 01fffe6b-F2:
its single-file anchor would otherwise retire the security classifier's
every-push detection slot), T102 (ai-trace), T109 (changelog
structural); "charset" was a phantom (the charset enforcement lives in
test/checks/commitlint-charset.sh as a PR-only STEP inside the
commitlint job, which itself runs on both PR and push — unchanged from
today, no main-tier regression; de71f597-rt2-F-3). The roster build
errors on unknown names (same validation family as the marker misuse
gate).
Membership changes are decision-gated code edits, same rule as the
D-04 floors.
deepen: closed — dug the pre-filter (run-sections.sh:267-279, keeps only
`known.has(l)||anchored.has(l)`) and confirmed zero self-anchors exist
today (`grep -l "gos-map:file test/sections" test/sections/*.test.sh` —
no matches), plus the blast argv rejection (map/index.cjs:243-246,
engine MAP_EXTS).

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
| INTENT / THINK / PLAN / REVIEW / SHIP | `restricted` | `.gos` and `.gos/logs`, plus the per-spawn scratch (an out-of-repo rw-bind under the store spawn scratch that compose ships with EVERY spawn, loop.cjs, launcher.cjs:310-319 — it is part of the restricted surface, not an omission; rt2-F2) |
| BUILD | `workspace` | repo root plus `.gos` (plus the same per-spawn scratch) |
| VERIFY (agent legs) | `restricted` | `.gos` and `.gos/logs`, plus the per-spawn scratch |
| VERIFY (script legs) | `restricted` + scratch | `scriptWritableRoots` per workers.cjs:194-199 — `<workspace>/.gos/cache` (in-repo cache path: section-runs tee + run-manifest) plus `<scratch>/testbed`; the out-of-repo scratch binds apply as with every spawn |
| any stage via table | `full` refused | only the explicit CLI capability-upgrade flag can raise to full |

Floor-change rule: floors live in `pinnedProfile` and the compose-time
writableRoots union; any change to either is decision-gated and lands as
a code edit in the same change set — never a table or config edit.
This decision is the pre-authorization record this task's BUILD workspace
writes (ci.yml, run-sections.sh) run under.
deepen: closed — dug the pin (workers.cjs:67), the compose-time writable
roots split (loop.cjs:1771-1776), and the script-leg TESTBASE pin
(workers.cjs:335).

## Scope

### In Scope
- ci.yml: `if:` split of the sections job, new `sections-pr` job; the
  workflow-level concurrency group is removed and concurrency moves to
  per-job declarations — the main closeout never cancels in progress
  (rt2-F-3, re-pinned v10: run-level cancellation defeated the v9
  job-level-only fix).
- run-sections.sh: the `--tier <pr|main>` roster capability
  (union/minus/exclusion semantics, marker validation, self-selection
  placement and exit-predicate changes) — rt2-F-4.
- test/sections: `gos-tier:main` markers seeded on the heavy auto-family
  map:none sections (T103-T136 kin, rt1-F1/rt2-F-1) and a new section
  covering the tier-roster semantics (rt2-F-4).
- CHANGELOG entry; census and layout untouched.

### Out of Scope
- Gate, pack, masters, commitlint jobs (unchanged behavior on both tiers).
- Any auto-loop code change — D-04 decides floors, it does not re-implement
  them.
- Local `--fresh` repair (concern adf8d93a — separate debt).
- release.yml and triage-gate.yml.

## Deferred Ideas
- [DI-1]: PR-tier minute-budget alarm or quota telemetry (when quota
  pressure is actually observed, not before).
- [DI-2]: label-triggered on-demand full suite for long-lived PR branches
  (`workflow_dispatch` + label).
- [DI-3]: scheduled nightly full suite on main — bounded insurance against
  the blast-wrong residual (a stale map edge can starve an anchored
  section on all tiers; rt2-F5 at b9e370f6).
- [DI-4]: roster-shrink detector for full-suite runs (deletion-gap
  residual; the v4 manifest-coverage wiring was withdrawn — the check
  cannot validate partial rosters).
- [DI-5]: blast-result caching across pushes of the same PR (only if
  selection cost ever shows up in job timings).

## Observable Truths (T-NN)

- **T-1**: on a pull_request event, the PR sections job runs
  `run-sections.sh --tier pr` against the merge-base; the job log shows
  the affected-mode selection header and skip lines, and unselected
  sections never execute.
- **T-2**: on a push to main, the tiered closeout runs: the heavy
  `gos-map:none` complement, the merge-diff blast closure, and the
  invariant re-run (node 20/22).
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
> Verdict line: converged (final re-attack round returned zero new findings)
> for the inline rounds; the DISPATCHED independent rounds (rt1/rt2, below)
> produced findings that were all ACCEPTed and amended into this spec —
> final state post-amendment awaiting the resumed run's VERIFY.

## Red Team Record — dispatched independent rounds (2026-11-24, this run's delegation)

| Round | Perspective | Findings | Dispositions |
|:---|:---|:---|:---|
| rt1 | misuse/edge | 3 | empty-merge-base silent zero-section green: ACCEPT — hard gate added to D-02 (resolve failure is red, never the fallback). D-03 kept-through variant sanctions permanently-red PRs: ACCEPT — kept-through forbidden, re-inject-after pinned. Citation misattributed (8457308d is the P15 push concern, not the --fresh item): ACCEPT — corrected to concern adf8d93a. |
| rt2 | completeness/factual | 5 | SELECTED/paths contradiction: ACCEPT — merged with rt1-D-03 fix. D-04 floor table understates the per-spawn scratch surface: ACCEPT — floor table amended. Dangling citation (duplicate of rt1-F3): ACCEPT. Quota math ignores the gos-map:none always-run floor (24/137 incl. the heavy auto suite): ACCEPT — D-01 reworked to the three-tier flow, quota restated, timeout derived. fetch-depth baseline misdescribed: ACCEPT — Approach corrected (PR job adds fetch-depth: 0; current sections job has none). |

> All 8 findings ACCEPTed; spec amended in place. Delegation held for
> human review per design (dispositions are never auto-written for the
> working stage); human ruling 2026-11-24 accepted the amendment plan.

### Round 3+4 — resumed-run re-attack on the amended spec (spawn a37c07e8)

| Round | Perspective | Findings | Dispositions |
|:---|:---|:---|:---|
| rt1 (a37c07e8) | edge/completeness | 4 | empty-base silent green, D-03 kept-through, citation, + placement: the re-injection must compute from the RAW input set BEFORE both empty-input exits (a test-only PR exits green at the pre-filter before the current pinned placement ever fires): ACCEPT — placement repinned. |
| rt2 (a37c07e8) | completeness/design | 10 | Consolidated to four mechanism gaps, all ACCEPT: (1) tier-membership mechanism missing — `gos-tier:main` marker added, PR drops marked sections except when the file is in the diff (new-section precedence rule), main runs all map:none. (2) Tree-guard input chain unbuilt — manifest artifact design dropped entirely; main job resolves the merged PR's head tree via GitHub API, forgery fail-safe direction. (3) patch_sha wrong fingerprint in CI (empty-diff hash) — dissolved by the API design. (4) roster precision (invariant enumeration, cheap-map:none default, new-section precedence) + deletion gap documented (baseline floors catch roster shrink at main). |

> All 14 findings ACCEPTed; spec amended to v3 (tier-marker mechanism,
> injection placement, roster enumeration). The
> convergence loop: round 1 attacked the premise, round 2 the mechanism
> layer, the mechanism is now pinned in spec — round 3 expected to
> converge. Delegation held for human review; ruling 2026-11-24 accepted.

### Round 5+6 — resumed-run re-attack on spec v3 (spawn 966e04e2)

| Round | Perspective | Findings | Dispositions |
|:---|:---|:---|:---|
| rt1 (966e04e2) | edge/misuse | 6 | Injection placement insufficient — the :283 exit predicates on INPUT_FILES alone and fires before the run loop even with SELECTED populated: ACCEPT — exit predicates re-pinned to `INPUT_FILES empty AND SELECTED empty`. Tree-guard gh resolve cannot succeed (no GH_TOKEN, no pull-requests:read in Actions; fail-safe direction makes the permanent degradation invisible): ACCEPT — guard re-pinned to git-only `refs/pull/<n>/head` fetch. Rest verified correct (citations, floor table, marker base). |
| rt2 (966e04e2) | edge/completeness | 8 | Zero-argv `map blast` dies on test-only PRs (silently-green replaced by permanently-red): ACCEPT — blast skipped when INPUT_FILES empty with SELECTED non-empty. Deletion-gap backstop cited manifest-coverage with no pipeline invoker: ACCEPT — the main tier invokes it post-suite against the fresh manifest (real mechanism now). Remaining findings consolidations overlap rt1. |

> All 14 findings ACCEPTed; spec amended to v4 (exit predicates, git-only
> blast skip on empty input, manifest-coverage wiring withdrawn). The
> attack surface has shrunk from design-level to predicate-level —
> convergence round next.

### Round 7+8 — resumed-run re-attack on spec v4 (spawn b9e370f6)

| Round | Perspective | Findings | Dispositions |
|:---|:---|:---|:---|
| rt1 (b9e370f6) | edge/misuse | 6 | manifest-coverage backstop permanently red on partial rosters (the check requires the full on-disk roster): ACCEPT — v4 wiring withdrawn. gos-tier:main marker on a non-map:none section orphans it from both tiers: ACCEPT — marker restricted to map:none sections, roster-build error otherwise. Merge-before-green silent zero-testing (no branch protection; guard tests merge-time tree, not last-tested tree): ACCEPT — main tier gains the merge-diff blast closure (subsumes the tree guard). |
| rt2 (b9e370f6) | edge/completeness | 6 | Overlaps rt1 (manifest contract, marker orphan) plus: tiered rosters not expressible by today's runner (no mode/flag; FILTER force-cleared in affected mode so invariants-by-name cannot ride it): ACCEPT — the `--tier` flag is the runner feature. Blast-WRONG (stale edge) loses the full-suite catch-all: ACCEPT — residual documented, DI-3 nightly-full insurance. fetch-density claim still off (commitlint/alarm jobs vary): ACCEPT — wording corrected. |

> All 12 findings ACCEPTed; spec amended to v5 — SIMPLIFICATION round: the
> tree-guard and manifest-artifact mechanisms are withdrawn (each drew
> permanently-red or silently-degraded findings), replaced by one runner
> capability (`--tier` roster flag) plus main's merge-diff blast closure.
> The convergence pattern across 8 rounds: premise → mechanism → predicate
> → SIMPLIFICATION. Delegation held per design; findings-disposition
> delegated to the subject-red-team consensus loop per the user's
> authority (2026-11-24); the stage gate remains human.

### Record completion (v9/v10) — recovered and late-folded dispatched rounds

Four dispatched runs had completed without record rows: the first two
lost tracking across the dispose-detach cycles (discovered by run
1650d812-rt1, confirmed against runRecords): 587c9f4a (2 rounds on spec
v5, 16 findings) and de71f597 (2 rounds on spec v7, 7 findings); the
latter two surfaced in the c5c0f2d0 re-attack's store audit (rt2-F-4/F-5
at c5c0f2d0): c9b172bd (rt1 on v7, 5 findings, rt2 quota-dead) and
123c8b8d (both legs no-verdict). Their evidence is folded here.

| Round | Perspective | Findings | Dispositions |
|:---|:---|:---|:---|
| rt1+rt2 (587c9f4a, on v5) | consistency/completeness | 16 | Stale tree-guard text in R-01/T-2, undefined invariant-membership mechanism, D-04 script-leg row misstatement — all ACCEPT, fixed by the v6 consistency pass and re-verified by rounds 9-16. |
| rt1+rt2 (de71f597, on v7) | edge/completeness | 7 | Main-closeout pending-cancellation semantics (`queue: max` needed): ACCEPT — v9 concurrency amended. PR-tier timeout merge-blast additivity: ACCEPT — v9 derivation amended. charset STEP-vs-JOB misstatement: ACCEPT — v9 wording amended. Remaining findings overlap recorded rounds. |
| rt1+rt2 (01fffe6b, on v8) | edge/exception | 2 (rt2 died mid-investigation — session failure class, counted as no-verdict) | Red Team Record incomplete + trend line false-monotonic: ACCEPT — this record completion is the fix. T85-security-depth starvation mischaracterized as a staleness condition (single-file anchor retires its every-push slot by construction; DI-3's staleness trigger can never fire for it): ACCEPT — T85 added to the invariant enumeration (v9) and the residual restated. |
| rt1 (c9b172bd, on v7; rt2 quota-dead — 429 session-failure class) | completeness/factual | 5 | F1 R-01 still carried the phantom "charset" member (v7 amended D-03 only): ACCEPT — R-01 roster corrected in the v8/v9 passes. F2 invariant-union placement unpinned vs the empty-input exits: ACCEPT — placement pin landed in v9; the residual blast-reassignment gap is re-found and re-fixed as c5c0f2d0-rt2-F-2. F3 main-tier timeout omitted merge-blast additivity: ACCEPT — v9 derivation amended. F4 Round 9+10 trend arithmetic garbled: ACCEPT — trend restated. F5 v7 splice-corruption artifacts (duplicated list item, corrupted trailing line): ACCEPT — cleared in the hand-edited v9. |
| rt1+rt2 (123c8b8d, on v7) | — | 0 (both legs no-verdict: exit 1, no verdict line — session-failure class) | No findings to fold; ledger-dispositioned 2026-11-24T10:16. Row records the run for trend integrity (rt2-F-5 at c5c0f2d0). |

> The TRUE findings trend across all dispatched runs (afaecaf8 → a37c07e8
> → 966e04e2 → b9e370f6 → 587c9f4a → 1650d812 → c9b172bd → 123c8b8d →
> de71f597 → 01fffe6b → c5c0f2d0): 8 -> 14 -> 14 -> 12 -> 16 -> 11 -> 5
> (rt2 no-verdict) -> 0 (both legs no-verdict) -> 7 -> 2 (rt2 no-verdict)
> -> 10. Non-monotonic at AMENDMENT BOUNDARIES — the v5 SIMPLIFICATION
> round and the v9 record completion each traded large amendments for
> fresh attack surface (2 -> 10 at c5c0f2d0 attacked exactly the
> newly-pinned v9 text: concurrency, placement, record rows); counts
> decayed once the new text was pinned. Class note (v10): the v9
> "zero design-level findings" claim is RETRACTED — c5c0f2d0 found two
> convergent mechanism-level defects (run-level cancellation defeating
> the no-closeout-cancel guarantee; blast reassignment clobbering the
> invariant union) in the freshly pinned v9 text. Premise-level attacks
> remain absent since round 8; findings cluster where new text lands.

### Round 9+10 — resumed-run re-attack on spec v6 (spawn 1650d812)

| Round | Perspective | Findings | Dispositions |
|:---|:---|:---|:---|
| rt1 (1650d812) | completeness | 4 | Marker seeding unpinned (0 sections carry gos-tier:main; In Scope omitted markers and the --tier implementation; the map:none fail-safe floor force-adds all 24 regardless — PR tier still runs the heavy family; silently dropping the floor would strip cheap map:none sections unpensioned): ACCEPT — markers seeded in Scope on the heavy auto family, the --tier implementation added to Scope, the fail-safe floor skips marked sections in the PR tier, marker set enumerated/decision-gated. Phantom invariant member ("charset" is a checks script, not a section; lives in the PR-only commitlint job): ACCEPT — roster uses real section names (T46/T66/T102/T109), roster-build errors on unknown names, charset documented as unchanged PR-only coverage. Residual detectors unhosted + Risks overclaims: ACCEPT — DI-3/DI-4 remain explicitly unscheduled ideas; Risks restated. |
| rt2 (1650d812) | misuse/edge | 7 | Overlaps rt1 (marker mechanization, phantom member) plus: cancel-in-progress concurrency defeats the merge-diff closure (a newer push cancels the running closeout; its diff never tested): ACCEPT — main closeout queues (no cancel-in-progress), PR tier keeps it. No tier-roster test section in scope: ACCEPT — new tier-semantics section added to Scope. Citation line drift + Goal sentence garble + T-1 stale flag: ACCEPT — all corrected. |

> All 11 findings ACCEPTed; spec amended to v7 (marker seeding + fail-safe
> interaction + governance, real invariant roster with build validation,
> main-closeout queuing concurrency, tier-semantics test section in
> scope). Findings trend: 8 → 14 → 14 → 12 → 11, and the class has shifted
> entirely to implementation-guidance grade — zero design-level defects in
> the last four rounds. Delegated consensus disposition; stage gate
> remains human.

### Round 17+18 — re-attack on spec v9 (spawn c5c0f2d0)

| Round | Perspective | Findings | Dispositions |
|:---|:---|:---|:---|
| rt1 (c5c0f2d0) | misuse/edge/completeness | 5 | PR-tier roster defined two contradictorily ways (Approach formula omits the unmarked map:none fail-safe floor that R-02 pins; quota/timeout derivations follow the wrong one): ACCEPT — formula, D-01 quota, PR-job timeout, and Risks restated with the floor term (census: 24 map:none on disk, 21 in the marker-kin range). Workflow-level concurrency group defeats the main-closeout no-cancel guarantee (GitHub cancels at RUN level; the v9 job-level-only fix is ineffective): ACCEPT — v10 removes the workflow-level block, concurrency moves to per-job declarations. R-01 invariant enumeration stale at four members (D-03/Risks pin five incl. T85): ACCEPT — R-01 restated. Main-tier base resolution ambiguous for zero-sha and force-push `before`: ACCEPT — both pinned (HEAD~1 / merge-base fallback), fail-closed unchanged; concern 98c5d641 citation verified. Committed THINK artifact (ce53bce) certifies superseded v1 while v9 lived only in the working tree (state.json pins the stale sha — one working-tree reset from losing the 20-round record): ACCEPT — the amended spec is committed via `commit think --refreeze` so the pinned durable copy is the reviewed one. |
| rt2 (c5c0f2d0) | edge/completeness | 5 | F-1 = rt1's workflow-level-concurrency defect (convergent independent rediscovery). F-2 blast reassignment clobbers the invariant union (run-sections.sh:287-302 replaces SELECTED on every code-touching PR, silently dropping T46/T66/T85/T102/T109 unless blast re-selects them): ACCEPT — merge-not-replace plus post-blast re-assertion pinned in the placement paragraph. F-3 = rt1's R-01 T85 omission (convergent). F-4 record omits dispatched run c9b172bd (5 findings, only 2 cited anywhere; rt2 quota-dead): ACCEPT — row folded above, evidence recovered from the store reviewRounds. F-5 record omits dispatched run 123c8b8d and the trend's fail accounting is incomplete (three failed legs in the tail, not one): ACCEPT — row folded, trend restated per-run with verdict notes, v9 class-shift claim retracted. |

> All 10 findings ACCEPTed (8 distinct after dedup; two convergent
> pairs); spec amended to v10 and committed via refreeze so the durable
> pinned copy matches the reviewed text. Delegated consensus disposition
> (ruling 2026-11-24); stage gate remains human. Trend: 2 -> 10 at an
> amendment boundary; rounds 19+20 are the confirmation round — if
> high-grade findings persist there, the loop escalates to the human
> gate with a release-with-known-gaps brief instead of another dialectic
> round.

## Risks
- Under-selection ships a break to main → the heavy `gos-map:none`
  complement is tiered to main (always runs there) and the invariant
  enumeration (T46/T66/T85/T102/T109) runs on BOTH tiers; residual
  risks: composition drift between PR tier and the merged tree (covered
  by main's merge-diff blast closure) and blast-WRONG from a stale map
  edge (an anchored section starves on all tiers — the T85 case is
  excluded from this class by invariant membership; DI-3 nightly-full
  is the scheduled insurance).
- Selection machinery depends on map data health → `map blast` failure
  exits red in the PR tier (run-sections.sh:287), never a silent skip.
- Quota: the PR tier is dual-node but bounded by the invariant floor plus
  the unmarked map:none floor plus the affected subset (derived in D-01);
  the main tier trades the full
  re-run for complement+invariants; the merge-diff blast closure bounds composition risk.
