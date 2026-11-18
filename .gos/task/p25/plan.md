# Plan: P25 quick-fix batch (#62 F-1 task anchor, #1 init constant)

> **Date**: 2026-11-18 | **Based on spec**: .gos/task/p25/spec.md

## Decision Inventory

- [x] D-101: claim-date window (SUPERSEDED by D-102) → T1, T2
- [x] D-102: F-1 anchors to task identity (audit details.task, skip incidents snapshot, add-row liveness) → T1, T2, T3
- [x] D-103: explicit init constant (unified writes, init-owned survive class, exact-equality migration) → T4, T5, T6, T7, T8
- [x] D-104: P26 phase for lessons lifecycle redesign, queued before P22 → T0
- [x] D-105: single branch, single PR closing #62 and #1 (amended
  2026-11-18 after the required audit gate blocked the two-PR split) → T9

## Requirement Claims

- [x] R-01: fix #62 and #1, independently shippable → T3, T8, T9
- [x] R-29: init rows survive milestone close visibly (spec R-02; registry
  issued R-29 under the global id namespace) → T5, T8

## Patterns to Follow

- Tests: bash section scripts in test/sections/TNNN-*.test.sh (seed
  fixtures via node heredocs writing .gos state; see T18 stale-fixture
  pattern)
- Audit rows: appendAuditRow(store, what, why, details) — details is the
  free surface outside the self-hash
- i18n: core.t('...') keys with locale files — check bin/lib/core for
  the t() registry before adding report copy (T74 language boundary)
- Commits: Conventional Commits, functional-domain scope, English only

## Execution Waves

### Wave 1 (done at THINK-time, recorded for coverage)

#### T0: Queue P26 lessons lifecycle redesign ahead of P22
- **Covers**: D-104
- **Read first**: .gos/state.json decisions D-104
- **Approach**: phase add P26 with the audit-evidence goal text, then
  phase move ahead of P22 (both executed 2026-11-18 during THINK).
  No Files entry: the change lives in the machine-local project registry,
  which git diffs never see — declaring a local-only path would
  permanently fail the diff-zero-hit gate.
- **Done when**: `node bin/gos.cjs phase list` shows P26 at index 4
  with P22 immediately after
- **Depends on**: none

### Wave 2 (branch feat/f1-task-anchor → single PR → Fixes #62, #1)

#### T1: Stamp task identity on lessons add/skip audit rows
- **Covers**: D-102, D-101 (supersede marker in comment history)
- **Files**: bin/lib/knowledge/lessons.cjs, test/sections/T46-module-structure.test.sh
- **Read first**: bin/lib/knowledge/lessons.cjs (add ~124-165, skip
  ~302-316), bin/lib/knowledge/lessons-json.cjs:186-212 (appendAuditRow
  details), bin/lib/knowledge/decisions.cjs:190-195 (stateless lane
  pattern: core.readState() may return null)
- **Approach**: in add and skip handlers, read state non-fatally
  (readState in read mode or try/catch); when a task id exists, pass
  details {task: taskId} to appendAuditRow (add already passes
  {new_id}; keep it and add task). Skip additionally stamps
  details.incidents = gapCount + total red-team findings read from the
  same state (0 when absent). No task context → record the row without
  a task anchor (no die, stateless lane preserved).
- **Done when**: `grep -n "details" bin/lib/knowledge/lessons.cjs` shows
  task + incidents stamps in both add and skip paths AND `node bin/gos.cjs
  lessons add --type project --scene s --lesson l` still succeeds in a
  repo without an active task
- **Depends on**: none

#### T2: Archive F-1 check accepts this task's rows, falls back to today
- **Covers**: D-102, D-101
- **Files**: bin/lib/task/archive.cjs
- **Read first**: bin/lib/task/archive.cjs:378-408 (F-1 segment),
  bin/lib/knowledge/lessons-json.cjs:198-210 (audit row shape)
- **Approach**: replace the today-only match with: (a) lesson side —
  an audit row with what==='add' AND details.task===state task id AND
  details.new_id still present in store.entries (project or model
  store) satisfies; (b) skip side — a row with what==='skip' AND
  details.task===task id AND details.incidents >= current gapCount +
  findings satisfies; (c) unanchored legacy rows keep the exact current
  today match. Rewrite the block copy: "Record a lesson for this task"
  and keep the skip hint noting it re-arms on new incidents.
- **Done when**: `grep -n "details.task" bin/lib/task/archive.cjs`
  matches AND the unanchored fallback branch still greps `startsWith`
  for legacy skip rows
- **Depends on**: T1

#### T3: T18 fixtures for task-anchored F-1
- **Covers**: D-102, R-01
- **Files**: test/sections/T18-f1-gate-lessons.test.sh
- **Read first**: test/sections/T18-f1-gate-lessons.test.sh (existing
  stale fixtures ~62-90, t18_mkstate helper)
- **Approach**: four new cases: (1) this-task lesson row with at =
  yesterday date passes archive across a simulated midnight (seed audit
  row details.task = the fixture task id); (2) foreign-task lesson row
  with today's date still blocks; (3) this-task skip row with a stale
  incidents snapshot (< current count) blocks; (4) add-then-rm: this-task
  add row whose new_id was removed blocks. Keep existing stale-skip and
  stale-lesson cases green (legacy fallback).
- **Done when**: `bash test/sections/T18-f1-gate-lessons.test.sh` exits
  0 with ≥4 new assertions AND `bash test/run-sections.sh T18` green
- **Depends on**: T1, T2

### Wave 3 (same branch feat/f1-task-anchor → single PR with Wave 2)

#### T4: init constant at decision write sites
- **Covers**: D-103
- **Files**: bin/lib/knowledge/decisions.cjs
- **Read first**: bin/lib/knowledge/decisions.cjs:179 (CLI row),
  260-270 (add write), 390-400 (import write)
- **Approach**: export a single INIT_PHASE = 'init' constant from
  bin/lib/core/state.cjs (core is the only layer every consumer may
  depend on: knowledge/decisions, knowledge/milestone, render/views,
  core migration — decided at plan red-team R4); import it in
  decisions.cjs and replace the three 'P0' literals (add fallback,
  import fallback, CLI row display default).
- **Done when**: `grep -c "'P0'" bin/lib/knowledge/decisions.cjs` = 0
  AND `grep -n "INIT_PHASE" bin/lib/knowledge/decisions.cjs` ≥ 3 AND
  `node -e "console.log(require('./bin/lib/core/state.cjs').INIT_PHASE)"` prints init
- **Depends on**: none (within wave)

#### T5: init-owned survive class in milestone close
- **Covers**: D-103, R-29
- **Files**: bin/lib/knowledge/milestone.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: bin/lib/knowledge/milestone.cjs:40-90 (class table +
  classifyRowDisposition), core.t registry (T74 language boundary)
- **Approach**: in classifyRowDisposition, test ref === INIT_PHASE
  before the phases lookup; return the new 'init-owned' class; append
  'init-owned' to CLOSE_ROW_CLASSES in the surviving tail; add the
  close-class report copy key (en + zh).
- **Done when**: `grep -n "init-owned" bin/lib/knowledge/milestone.cjs`
  matches classification + class list AND the copy key exists in both
  locale sources
- **Depends on**: T4

#### T6: Render init with header note
- **Covers**: D-103
- **Files**: bin/lib/render/views.cjs
- **Read first**: bin/lib/render/views.cjs:334-359 (scopedPhaseSet +
  renderDecisionsMd)
- **Approach**: birth_phase === INIT_PHASE renders as `init`; add one
  header note line after the table header: Phase "init" = decisions
  born at project init, before any phase existed. Keep the
  included/known filter behavior (init stays always-included via the
  unknown-phase branch — verify scopedPhaseSet does not need the
  constant).
- **Done when**: `grep -n "before any phase existed"
  bin/lib/render/views.cjs` matches AND T7-render fixtures pass
- **Depends on**: T4

#### T7: One-time exact-equality migration for legacy birth_phase values
- **Covers**: D-103
- **Files**: bin/lib/core/state.cjs
- **Read first**: bin/lib/core/state.cjs:549-569 (normalizeRowPhaseRefs
  — prefix semantics that must NOT apply here), bin/lib/core/state.cjs:266
  ('legacy' backfill precedent — the exact pattern to copy)
- **Approach**: idempotent backfill inside loadProject, mirroring the
  state.cjs:266 pattern: for decisions rows, birth_phase === 'P0' or
  === 'legacy' (strict equality only) rewrites to INIT_PHASE; values
  like 'P0: <name>' (real phase rows normalized earlier) are untouched;
  persisted via the normal saveProject path so census/pack-check sees it.
- **Done when**: node one-liner on a seeded project.json with rows
  'P0', 'legacy', 'P0: real' returns ['init', 'init', 'P0: real'] AND
  `bash test/pack-check.sh` green
- **Depends on**: T4

#### T8: T3/T7/T114 fixtures for the init constant
- **Covers**: D-103, R-01, R-29
- **Files**: test/sections/T3-decision.test.sh, test/sections/T7-render.test.sh, test/sections/T114-milestone-open-close.test.sh
- **Read first**: existing T3/T7/T114 assertion patterns
- **Approach**: T3 — stateless decision add (no claimed task) writes
  birth_phase init; T7 — rendered DECISIONS.md shows the init cell +
  header note and contains no bare P0 column value; T114 — a milestone
  close on a project with an init row reports init-owned and the row
  survives.
- **Done when**: `bash test/run-sections.sh T3 T7 T114` green AND
  `bash test/run-sections.sh T18` still green (regression)
- **Depends on**: T5, T6, T7

### Wave 4 (delivery)

#### T9: Single-PR squash-merge delivery
- **Covers**: D-105, R-01
- **Files**: .gos/task/p25/plan.md
- **Read first**: AGENTS.md (PR-only main, squash-subject lint rule),
  test/checks/push-lint-squash.sh
- **Approach**: All waves land on feat/f1-task-anchor; the single PR body
  carries "Fixes #62" and "Fixes #1" so one squash merge autocloses both
  issues. Delivery shape amended 2026-11-18 (user ruling): the required
  Gate (audit mode) check blocked merging a first PR while Wave-3 tasks
  and truths structurally belonged to the second branch — one task, one
  plan, one green merge. Squash subject is an imperative verb-object
  clause passing test/checks/push-lint-squash.sh before merge; merge only
  with the full check suite green.
- **Done when**: the PR is merged with all checks green AND issues #62 and
  #1 are both closed by the merge AND the subject passed the squash lint
- **Depends on**: T3, T8

## Observable Truths

### T1 (state T1): cross-midnight archival passes
- **Expected**: task with incidents + this-task lesson row dated
  yesterday archives cleanly; T18 case 1 green
- **Verify**: `bash test/run-sections.sh T18` green with the 4 new
  assertions

### T2 (state T2): foreign rows no longer satisfy F-1
- **Expected**: foreign-task today rows (lesson or skip) block archive
- **Verify**: T18 cases 2 + 4 assert BLOCKED output

### T3 (state T3): init renders explicitly
- **Expected**: DECISIONS.md Phase column shows init + header note; no
  phantom P0
- **Verify**: `node bin/gos.cjs render && grep -c "P0" .gos/project/DECISIONS.md` = 0
  AND `grep "before any phase existed" .gos/project/DECISIONS.md` matches

### T4 (state T4): init rows survive close
- **Expected**: milestone close reports init-owned; row survives
- **Verify**: T114 fixture asserts the class + row presence post-close

### T5 (state T5): single PR closes both issues
- **Expected**: one merged PR (all checks green); #62 and #1 closed by
  its merge
- **Verify**: PR view shows merged + `gh issue view 62 --json state` +
  `gh issue view 1 --json state` both closed

## Risks

- readState mode coupling in lessons.cjs (write-class entry) → use the
  read-mode precedent from archive.cjs:200-208, never a bare readState
- Migration write-back on load surprises pack-check → keep the
  migration in the explicit project-load path, run pack-check in T7
  done-when
- Second PR rebase noise → serial merges only, zero file overlap
  verified in D-105 dig

## Plan Red Team (Round 4 — DEGRADED inline, breaker tripped)

| Finding | Disposition | Landed as |
|:--|:--|:--|
| F4 [Major] stage commits already on local main (ahead 2), D-105 branch strategy conflicts with reality | ACCEPT | T9 approach: feature branch at head + main reset to origin before PR 1 |
| F5 [Minor] INIT_PHASE home ambiguous across knowledge/render/core layers | ACCEPT | T4 approach: constant lives in bin/lib/core/state.cjs, done-when asserts the import |
| F6 [Minor] T7 migration hook location vague | ACCEPT | T7 approach: loadProject inline backfill per state.cjs:266 precedent |

Verdict: converged (re-attack of the three dispositions against the
revised plan text found no residual gap).
