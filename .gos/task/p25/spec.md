# Spec: P25 quick-fix batch (#62 F-1 task anchor, #1 init phase constant)

> **Date**: 2026-11-18 | **Level**: Lv3 | **Status**: Draft

## Goal

Fix two live papercuts ahead of the thematic batches: #62 (F-1 lessons
same-day check ages out across UTC midnight and blocks gos archive) and
#1 (DECISIONS.md renders a phantom Phase P0 absent from ROADMAP.md).

## Motivation

Both papercuts are daily-friction class. #62 burned a live P19 archival
(lessons recorded 2026-11-11T12:3xZ, archive blocked 2026-11-12T01:25Z)
and its only workaround pollutes the lessons ledger with duplicate
entries. #1 costs cross-session trust: a red-team subagent reading only
the generated views reported DECISIONS.md vs ROADMAP.md mutual
inconsistency as a Major finding — downstream agents treat generated
views as the contract. The #1 dig surfaced a harder defect behind the
render symptom: milestone close classifies `birth_phase = "P0"` rows as
ghost and wipes them, so the four init-time decisions in this repo
(D-01..D-04) would be silently erased at the first milestone close.

## Requirements (R-NN)

- **R-01**: Two live papercuts fixed ahead of the thematic batches: #62
  (F-1 lessons same-day check ages out across UTC midnight and blocks
  gos archive) and #1 (DECISIONS.md renders a phantom Phase P0 absent
  from ROADMAP.md). Small, independently shippable.
- **R-02**: Init-time decision rows survive milestone close as a visible
  disposition class instead of being ghost-wiped (discovered during the
  #1 dig; the render inconsistency is only the symptom).

## Approach

### Selected Approach

#62 — root cause is modeling: the F-1 two-of-one check wants "was a
lesson digested for THIS task" but lessons and skips carry no task
identity, so same-day wall-clock matching was used as a proxy. Fix by
anchoring identity directly: `gos lessons add` and `gos lessons skip`
stamp the active task id into their audit rows (`details.task` — the
designed free surface outside the audit self-hash), and the archive F-1
check accepts this task's rows. Unanchored legacy rows fall back to the
current today match. Time semantics retire from the check.

#1 — root cause is a magic string: `'P0'` is written at three sites when
no task context exists, means both "born at init" and "no context
available", and is rendered verbatim next to real phase names that
ROADMAP never shows. Fix by introducing one explicit `init` constant:
unified write sites, an `init-owned` survive class in milestone close
disposition, rendered with a header note, legacy `P0`/`legacy` values
migrated once.

### Alternatives (Rejected)

See decision cards D-102 and D-103 for the rejected option space
(claim-date windows, rolling windows, schema v3 entry fields,
render-only changes, active-phase association, virtual P0 rows).

## Design Decisions (D-NN)

### D-101: F-1 lesson check anchors to claim date (SUPERSEDED)

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| D-101-A | claim timestamp exists; lesson.at >= claim UTC date; same cure shape as #49 precedent | midnight-independent; ~3-line compare | still a time proxy for identity; foreign same-day lessons still count; skip side unsymmetrical | archive.cjs F-1 compare |
| D-101-B | keep the same-day check unchanged | zero diff | papercut stands; duplicate-ledger workaround pollutes entries | none |

why-not: D-101-A — time window is a proxy for identity, never a
requirement; superseded by D-102 (task-identity anchor) after user
challenge.
recommendation: superseded — see D-102.
deepen: any option — ask for another dig round.

### D-102: F-1 two-of-one anchors to task identity (audit details)

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| D-102-A | add/skip audit rows carry details.task; archive accepts this task's rows; unanchored rows fall back to today; identity is the property F-1 actually wants; audit details is the designed free surface (deliberately outside self-hash) | midnight aging dies; foreign-row loophole closes (tighter than today); both sides symmetric; ~15 lines total | task field is outside the audit self-hash (offline tamper does not break chain; mitigated by git-tracked truth and F-1 being a discipline gate) | lessons.cjs add/skip write sites, archive.cjs F-1 segment, T18 fixtures |
| D-102-B | claim-date window (lesson.at >= claim UTC date); time approximation suffices | no audit surface changes | he-task same-day lesson still counts; window magic number just moves from today to claim date; skip symmetry unsolved | archive.cjs only, residual approximation |
| D-102-C | entries gain a task field (schema v3); identity lands in the entry body | anchor travels with the entry | V2_FIELDS whitelist + hash segments + version bump + migration of 85 entries — over-engineering for a papercut | full schema v3 suite |

why-not: D-102-B — window-tuning keeps the proxy and its loopholes while
the user ruling asked to dissolve the time concept; D-102-C — the audit
details channel already carries the identity at zero schema cost.
recommendation: D-102-A — conditional: no active task at add/skip time
records an unanchored row (no die); fallback branch keeps today match for
legacy rows; F-1 block copy rewritten ("Record a lesson for this task").
A skip row records a details.incidents snapshot (gapCount + total
red-team findings at skip time); this task's skip exempts only while the
snapshot >= the current incident count, so new incidents after a skip
re-arm F-1 (per-archive aging survives the anchor switch). A this-task
add row exempts only while its details.new_id entry still exists in the
store, so an add-then-rm sequence does not satisfy the gate.
deepen: any option — ask for another dig round.

### D-103: init-time decisions get an explicit init constant

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| D-103-A | single init constant at all write sites, init-owned survive class in close, render shows init with header note, one-time legacy migration; "born at init" is a real lifecycle stage, not missing data; consumers need to recognize it, not delete or fake it | milestone ghost-wipe plugged (D-01..D-04 saved); render self-explanatory; honest semantics | touches milestone close class table (i18n report copy + CLOSE_ROW_CLASSES); constant synced across 4 consumer files; one-time migration | decisions.cjs writes, milestone.cjs classification, views.cjs render, project migrate, T3/T7/T114 fixtures |
| D-103-B | render-layer explicitization only; display clarity suffices | minimal diff | does not plug the milestone ghost-wipe — the disease stays | — |
| D-103-C | stateless add associates the active phase; an owner phase prevents ghost | no classification changes | fabricated attribution: pre-claim gap decisions are not born in that phase's lifetime | — |
| D-103-D | virtual P0 row in the phases array; init becomes a first-class phase | no special-case code | pollutes every phase-management predicate (rename collision, claim, move, archive numbering) for one constant | — |

why-not: D-103-B — treats the symptom while close still wipes the data;
D-103-C — writes a lie into the data (decisions recorded before any
claim do not belong to an unborn phase); D-103-D — cost inverted: one
constant versus ten predicate exemptions.
recommendation: D-103-A — conditional: constant value `init` (short, no
P-NN namespace collision); migration is idempotent and exact-equality
only (`birth_phase === 'P0'` or `=== 'legacy'` — never prefix matching,
which would swallow rows of a real `P0: <name>` phase);
DECISIONS.md header note `Phase "init" = decisions born at project init,
before any phase existed`; init-owned rows visible in the close report
(no silent survival).
deepen: any option — ask for another dig round.

### D-104: lessons lifecycle redesign gets its own phase P26 before P22

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| D-104-A | independent P26 queued before P22; the redesign is structural (activation/layering/retirement), beyond quick-fix scope | P22 lessons-digestion mechanics land on the new architecture, not the old flat ledger | one more queued phase | phase queue, P22 goal boundary |
| D-104-B | record as issue and extend P22; P22 already lists lessons digestion | no queue growth | P22 scope balloons past ledger hygiene; digestion on old architecture risks rework | P22 goal amend |
| D-104-C | feedback note without scheduling; no commitment | zero cost | insight decays unowned | .gos/project/feedback/ draft |

why-not: D-104-B — architecture work smuggled into a hygiene batch
doubles its blast radius; D-104-C — the dilution curve evidence would
sit unowned until someone rediscovers it.
recommendation: D-104-A — user ruling 2026-11-18 (recorded via
--dig-ruling); P26 added and moved ahead of P22.
deepen: any option — ask for another dig round.

### D-105: ship as two feature branches, two PRs, serial squash-merge

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| D-105-A | feat/f1-task-anchor (Fixes #62) then feat/init-phase (Fixes #1), serial squash; phase goal says independently shippable; touched file sets are disjoint | independent revert; per-issue autoclose; single-topic squash subjects pass lint cleanly | two PR rituals; second PR rebases landed main (zero file overlap) | BUILD waves, SHIP branch plan |
| D-105-B | one branch, one PR, Fixes #62, Fixes #1; both fixes are quick-fix sized | one ritual | no independent revert; compound subject fights lint and review; issues close atomically | single squash |
| D-105-C | two tasks, two phase-queue runs; full separation | complete 8-stage flow each | process over-engineering for 3+15-line fixes; defeats the batch's purpose | two claim cycles |

why-not: D-105-B — trades the independently-shippable property the phase
goal itself states for one ritual; D-105-C — promotes papercuts to full
task cycles the quick-fix batch exists to avoid.
recommendation: D-105-A — conditional: BUILD splits into wave1 (#62) and
wave2 (#1); second PR rebases after the first lands; both squash
subjects pass test/checks/push-lint-squash.sh before merge.
deepen: any option — ask for another dig round.

## Scope

### In Scope

- archive.cjs F-1 segment: task-anchored lesson/skip acceptance
  (skip requires details.incidents snapshot >= current count; add row
  requires its details.new_id entry to still exist) + unanchored today
  fallback; block copy rewrite
- lessons.cjs add/skip: stamp details.task when a task context exists;
  skip stamps the details.incidents snapshot
- decisions.cjs three write sites + CLI row display: explicit init
  constant replaces the 'P0' magic string
- milestone.cjs classifyRowDisposition: init-owned survive class +
  report copy
- views.cjs renderDecisionsMd: init display + header note
- One-time idempotent migration of legacy birth_phase values (P0,
  legacy) to init
- Test fixtures: T18 (this-task rows pass across midnight; foreign
  today rows reject), T3/T7 (init write + render), T114 (init survives
  close)
- Two feature branches → two PRs → serial squash-merge

### Out of Scope

- Lessons lifecycle redesign (activation retrieval, layering,
  retirement) — P26
- The remaining P22 ledger hygiene work (lessons digestion mechanics
  move to P26's architecture; P22 keeps non-lessons ledger work)
- Any F-1 relevance checking beyond task identity (scene-level matching)

## Deferred Ideas

- DI-1: Lessons lifecycle redesign — activation via context-scoped
  retrieval (tags + D-102 task anchor), evergreen graduation to
  AGENTS.md/skills, timed expiry, superseded/dedup/citation aging (P26,
  queued before P22).

## Red Team Record (Lv2+ mandatory before user approval)

> Ran in DEGRADED mode (inline self-attack) — spawn breaker tripped
> (B=30 exhausted); shared-prior blind spots not coverable this session.

| Round | Perspective | Findings | Dispositions (A/AP/R-with-facts/D) |
|:---|:---|:--|:--|
| 1 | misuse/safety | 2 | F1 ACCEPT → D-102 skip incidents snapshot (re-arms F-1 on new incidents); F2 ACCEPT → D-102 add-row liveness check (details.new_id must still exist) |
| 2 | edge/exception | 1 | F3 ACCEPT → D-103 exact-equality migration guard (prefix would swallow real `P0: <name>` rows) |
| 3 | completeness | 0 | converged — historical lessons checked (e9271355 satisfied and exceeded by the identity anchor; 0d2eedee constant-consumer sweep listed in Scope) |

> Disposition key: ACCEPT(design change landed) / ACCEPT-PARTIAL /
> REJECT(factual counter-evidence cited) / DEFER(to DI-n).
> Verdict line: converged (round 3 zero new findings).

## Risks

- Audit details.task sits outside the self-hash → tamper-evidence rests
  on git-tracked truth; acceptable because F-1 is a discipline gate, not
  an adversarial boundary (clock-changing already defeats today match).
  → Mitigation: document the boundary in the F-1 block copy.
- Milestone close class table change ripples into report i18n strings
  → Mitigation: T114 fixtures assert the new class end-to-end.
- Legacy-value migration touches project.json truth
  → Mitigation: idempotent migration + census reconciliation via
  pack-check before layout-affecting commits.
- Second PR rebases while the first is in review
  → Mitigation: serial merges only (D-105-A), zero file overlap
  verified by the disjoint touched sets.
