# Spec: stage back explicit-reason refusal

> **Date**: 2026-11-05 | **Level**: Lv3 | **Status**: Draft (auto dogfood cycle 1 vehicle, task 5dafe9ee)

## Goal

`gos stage back <STAGE>` must refuse (exit 1, no state change) when no
explicit reason is supplied, replacing the silent empty-reason template at
bin/lib/task/stage.cjs. The matching negative assertions land in
test/sections/T51-commit-guard.test.sh.

## Motivation

Concern [6dd52a5c] item 1. Today `stage back` folds a missing reason into
`'discovered during ' + <target stage>` (stage.cjs fallback on the reason
line), so the gap record — the only trace of WHY a task went backward —
carries zero diagnostic content exactly when the writer had nothing to say.
Real data: the gap ledger (.gos/logs/gap-history.ndjson) holds 61 records
whose description is the bare template ("discovered during PLAN" ×56,
VERIFY ×2, THINK ×2, BUILD ×1). The gap is the unit VERIFY and humans
reason over; a templated gap is a hole in that record.

## Requirements (R-NN)

- **R-01**: (auto from intent — scope-binding) The live dogfood store at
  ~/.local/share/gos/85af56a090a78924 is never touched by fixture runs;
  fixture stores are XDG-overridden inside the test sandbox. Work lands
  only on the files the frozen plan snapshot declares for this task.
- **R-02**: (from intent, deliverable) `stage back` with a missing or
  blank reason refuses with exit 1 BEFORE any state mutation is written;
  the error names the requirement and shows a copyable correct invocation.
- **R-03**: (from intent, deliverable) The refusal is proven by behavior
  assertions in T51: exit code, error content, byte-identical state file,
  unchanged gaps count — not by grepping source strings.
- **R-04**: (discovered dependency) The one existing no-reason call site
  in the suite (T23.6) is updated to pass an explicit fixture reason so
  its invariants (gap in state.gaps only, no concerns.md mirror, injected
  reason still refused) keep testing what they were built to test.

## Approach

### Selected Approach

Extend the existing input-boundary family in `cmdStage` (stage.cjs):
trim the joined reason args; empty → `core.die` with a usage-bearing
message, placed first in the validation chain (empty → length/injection
constraint → reserved `(auto)` forgery), all ahead of `writeState` —
preserving the existing ordering-fatal invariant that a die on the
boundary leaves both stores untouched. Delete the template fallback.
Update the `stage` usage footer to show the reason as required. Add the
T51 case block; update the T23.6 call site.

### Alternatives (Rejected)

- ~~Interactive prompt for the missing reason~~ — the CLI has no
  interactive contract; scripted/agent callers (the dominant consumers)
  would hang on non-tty stdin.
- ~~Keep the template, print a warning~~ — the observed defect is the
  gap RECORD, not the console; 61 ledger occurrences prove the template
  is what lands.

## Design Decisions

Spawn-channel note: this session's grants exclude the decision verb, so
decisions live here as spec sections (the dispatch-table design; the
plan/bidirectional gates pass vacuously with an empty state decision set).

### Decision 1: refusal semantics — fail-closed die before write

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. die on empty (chosen) | reason is the only record of why a back happened; 61/61 template records carry no why | gap records always carry an author's words; exit 1 matches the existing boundary-refusal family; no state touched | breaks any caller that relied on the template (census: exactly one, T23.6 — updated in Decision 3) | every `gos stage back` invocation; T51 refusal assertions; `gos gap list` readers who now always see a why |
| B. interactive prompt when reason missing | a human at a tty can supply it late | zero-typing for interactive users | hangs scripted/agent callers (the counted majority: skills docs + tests, no tty); two behavior paths to test | only a hypothetical tty user; everyone else inherits the hang |
| C. template + warning line | console visibility is cheap | no caller breaks | the record stays fuzzy — the exact observed defect persists; warning is invisible to the gap ledger | nothing new — same single-user assumption |

why-not: B — non-tty consumers are the counted majority and a hang is
worse than a refusal; C — the ledger count proves the template is the
defect, not the missing warning.

recommendation: A — conditional: the die message must contain a stable
grep anchor ("explicit reason") and a copyable full-command example, so
stale docs that show no-reason invocations land on a teaching error.

deepen: any option — ask for another dig round.

### Decision 2: validation placement — first slot in the existing chain

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. extend the existing validation block (chosen) | stage.cjs already runs a three-stage reason boundary (constraint → forgery) ahead of writeState, documented as ordering-fatal | ~4-line diff; the empty check joins the family it belongs to; T23's injected-reason case keeps its exact behavior | none observed | the stage.cjs boundary chain; T23.6 injection sub-case (unchanged) |
| B. hoist reason validation above target validation | fail fast on the most common mistake | rejects the reason before telling the caller their stage name is wrong — inverted error priority | one more reorder of long-stable code for no behavior gain | none beyond A |
| C. extract a pre-flight validator function | shared boundary helpers read cleanly | reuse potential | there is exactly one consumer; abstraction adds a seam for ~6 lines of checks | a future second caller that does not exist today |

why-not: B — target-validity errors are more fundamental and must stay
first (existing usage error already covers them); C — single consumer,
no second call site in the census.

recommendation: A — conditional: the trimmed value (not the raw join)
feeds `checkInputConstraint`, so leading/trailing blanks cannot reach the
gap record; maxCp 400 / newline list-prefix injection / `(auto)` forgery
rules are untouched.

deepen: any option — ask for another dig round.

### Decision 3: test placement — T51 negative block + T23.6 call-site repair

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. T51 case block + one-line T23.6 fix (chosen) | the observer pre-adjudicated T51 as the refusal's home; the dig found T23.6 (T23-concerns.test.sh, the `stage back with normal reason exits 0` assertion) silently depends on the removed template — it invokes with NO reason and asserts 0 | refusal behavior proven by exit codes + error text + sha-identical state + gaps-count-0 + whitespace variant + positive control; T23.6 keeps testing its real invariants with a fixture reason | file set grows beyond the adjudicated {stage.cjs, T51} — a plan-freeze delta the observer must rule on (expected, surfaced, not silent) | section suite T23/T51; the plan file-set diff at snapshot freeze; every future editor of the gap write path |
| B. T51 block only, leave T23 untouched | strictly inside the adjudicated file set | zero gate friction | T23 goes red the moment the refusal lands — knowingly shipping a broken section; the suite is a diagnosable artifact, not a scoreboard | a VERIFY-stage gap that this spec can predict today |
| C. put the refusal tests in T23 instead of T51 | T23 already hosts the stage-back write-back case | thematically adjacent | contradicts the pre-adjudicated home; splits the refusal family across sections; T23 is anchored to the concerns command family, not stage flow | none — moves the problem, solves nothing |

why-not: B — predicted-red sections are defects, not deference;
C — the adjudication already chose T51 and section cohesion argues the
same way.

recommendation: A — conditional: the T51 block is behavior-only (no
source-string greps — assertion-debt lesson [b275a446]), and the spec
flags the file-set delta so the observer rules at plan freeze, not at
BUILD impact.

deepen: any option — ask for another dig round.

### Decision 4: usage-text alignment — in-file only, doc sweep deferred

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. update stage.cjs footer now, defer the rest (chosen) | stage.cjs's own footer documents `[reason]` as optional — wrong the moment the refusal lands; the help-registry copy (core state.cjs desc/subs) and skills docs sit OUTSIDE the frozen file set | the file being edited anyway carries the truth; every stale doc invocation now terminates in the teaching die message | two doc surfaces keep stale `[reason]` wording until a later sweep | `gos stage` bare invocation; readers of skills/gos-build and skills/gos-verify examples |
| B. sweep all usage text now | one coherent docs moment | no stale surface at all | grows the diff across out-of-set files (core state.cjs help strings, four skills files) with zero test surface | the plan-freeze gate (four extra out-of-set files to rule on) |
| C. touch no usage text | minimal diff | none | the file's own usage line would document an optional form that now refuses — a lie in the same commit as the fix | nobody — the misinformation persists |

why-not: B — doc-only edits outside the adjudicated set buy no behavior
and expand the freeze-delta the observer must adjudicate; C — the usage
footer is inside the file being fixed; leaving it wrong is free misinformation.

recommendation: A — conditional: the footer text matches the die
message's example form verbatim; the sweep lands as a deferred idea.

deepen: any option — ask for another dig round.

## Scope

### In Scope

- bin/lib/task/stage.cjs: empty/blank reason refusal (die, first slot in
  the validation chain, before any state write) + usage footer `[reason]`
  → required-reason form; template fallback deleted.
- test/sections/T51-commit-guard.test.sh: new case block — no-reason and
  whitespace-only refusals (exit 1, "explicit reason" in output, state
  sha byte-identical, gaps count unchanged) + positive control with an
  explicit reason (exit 0, gap description carries the reason text);
  header case legend gains the new letter.
- test/sections/T23-concerns.test.sh: the one no-reason call site gains a
  fixture reason; no other line changes.

### Out of Scope

- Concern [6dd52a5c] item 2 (commit-forward open-gap check) — deferred by
  the observer's spec.
- Help-registry wording in bin/lib/core/state.cjs; skills doc examples
  (gos-build SKILL/reference, gos-verify gap-classification) showing
  no-reason invocations.
- Any change to gap record shape, gap type ('major'), or the `(auto)`
  reserved-word boundary.

## Deferred Ideas

- DI-1: help-registry `[reason]` wording in bin/lib/core/state.cjs
  (desc + subs strings) — next touch of the help registry.
- DI-2: skills doc sweep for no-reason `stage back` examples — bundle
  with the router/intent UX doc phase.
- DI-3: concern [6dd52a5c] item 2 — separate small task per the observer
  spec's Deferred section.

## Red Team Record (Lv2+ mandatory before user approval)

| Round | Perspective | Findings | Dispositions (A/AP/R-with-facts/D) |
|:--|:--|:--|:--|
| 1 | misuse/safety | pending | pending |
| 2 | edge/exception | pending | pending |
| 3 | completeness | pending | pending |

> Disposition key: ACCEPT(design change landed) / ACCEPT-PARTIAL /
> REJECT(factual counter-evidence cited) / DEFER(to DI-n).

## Risks

- Plan-freeze file-set delta (T23 joins the declared set) → surfaced in
  Decision 3 and here; the observer's plan gate rules at freeze — an
  expected pause, not a defect.
- Die-message/T51 coupling → the T51 assertion greps the stable anchor
  "explicit reason", not the full sentence; wording may evolve freely.
- Consumers following stale skills docs → every stale invocation lands on
  the teaching refusal message (usage example inline), verified by the
  positive-control case.

## Observable Truths

Recorded via `gos truth add`; verified at VERIFY with sandboxed
reproduction (XDG-overridden fixture store per R-01):

1. `gos stage back <STAGE>` with no reason — and with whitespace-only
   reason — exits 1, prints a message containing "explicit reason", and
   leaves .gos/state.json byte-identical with the gaps count unchanged.
2. `gos stage back <STAGE> "<reason>"` exits 0 and records a gap whose
   description reads `Fluid back to <STAGE>: <reason>`, with no mirror
   line in .gos/concerns.md.
3. The full section suite is green with the change landed (run manifest
   failed_sections empty), including T23 and T51.
