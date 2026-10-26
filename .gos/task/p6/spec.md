# Spec: P6 — Comment Hygiene and Coding Standards

> **Date**: 2026-10-26 | **Level**: Lv3 | **Status**: Draft (post red-team revision)

## Goal

Root-cure AI-process artifacts in file content: a mechanized, fail-closed
ai-trace lint wired into `gos gate all` as blocking, a batch sweep of the
legacy anchor comments across the tracked tree, and closure of the
coding-standards loop (books teach the full ban in placeholder spelling,
setup points at the seeding verb). Closes 39dad6a4 59ce99c5 db3d0fd8 FB-4.

## Motivation

Three user rulings (2026-09-18, 2026-10-26) banned decision anchors,
spec-section citations, and task narrative from ALL file content. The ban
has no mechanical enforcement: anchor comments survive across the tree
(bracket forms alone: ~171 lines / 42 files under bin/ and test/; bare
`D-NN`/`R-NN`/`B-NN` forms are larger — 650/219/86 line hits), and
convention-mimicry keeps teaching new sessions the wrong style (global
lesson 4846277e names this as the recurrence root cause). FB-4 concern
6f1e5559 records the unmet demand: audit cmd + sweep pass.

## Requirements (R-NN)

- **R-01**: Mechanized ai-trace lint wired into gate all as blocking; sweep
  legacy anchors in batches; ship coding-standard templates seedable via
  gos; apply the lint to product-seeded assets (auto from intent).
- **R-02**: `test/checks/ai-trace-lint.sh` — two-tier patterns, fail-closed
  in every direction, `--json` machine mode. ALL pattern matching lives in
  the node helper (bash lists files only — no grep dialect dependence;
  cjk-lint's `grep -P` is recorded as existing GNU-only debt).
- **R-03**: Machine-generated whitelist (`.gos/ai-trace-whitelist.json`,
  committed via `gos track` + census): `--emit-baseline` derives the landing
  whitelist from the lint's own final patterns over `git ls-files`;
  exact-equality `maxHits` (actual == registered, both directions fail);
  ghost-entry hygiene; regen guard — hand-edited baselines that diverge from
  regenerated output fail.
- **R-04**: `gate all` runs the lint as blocking, self-repo scope (same
  guard as cjk-lint/ascii-filenames); failure evidence carries
  `violationCount` + a pointer to `--json` (no inline excerpts); fix-string
  must NOT suggest adding whitelist entries; printed lines are ANSI-stripped.
- **R-05**: Harness-driven sweep (three dispositions + frozen-string audit)
  in domain batches, with backfill into `CHANGELOG.md` `[Unreleased]`
  (validator-clean prose entries; deleted anchor ids reconcile through a
  tracked sweep ledger `.gos/ai-trace-sweep-ledger.ndjson` — the changelog
  validator bans id-bearing bodies: `§`, `T-nn`, `DI-nn`, wave/phase words,
  changelog-core.cjs:74-86) (`.changes.md` is SEALED — never appended).
- **R-06**: Coding-standards books name every banned form in digit-free
  placeholder spelling; setup onboarding prints a `gos init coding` hint
  (both locales); existing digit-bearing quotes in AGENTS.md, `.gitignore`,
  `.gitattributes` land in `meta-doc-quoting` per-path entries.

## Approach

### Selected Approach

1. **Lint** (`test/checks/ai-trace-lint.sh` + node helper, cjk-lint
   structural homolog):
   - Tier A (anywhere in tracked files): generalized bracket family
     `\[[A-Za-z]+[ -]?[0-9/]` (case-insensitive REVIEW), bare dash-findings
     `RT3-F7` / `R3-F1`, spec-section citations `spec §3.4` / `§6a-2`,
     `W1-T5` compounds. Bare `Wave N` is NOT tier A — it is the product's
     own plan.md heading syntax (templates, fixtures, skills examples) and
     drops to tier B comment lines.
   - Tier B (comment lines only): bare `W\d+`/`T\d+`/`Wave \d+`, bare and
     parenthesized `(D|R|B|F)-\d+` (incl. slash compounds), task-narrative
     phrases (`this (phase|wave|task) (adds|ships|introduces)`).
   - Comment-line detection per filetype in the node helper: `#` for
     shell/yml/yaml (unknown text types default to `#` — over-flag beats
     under-flag), `^\s*//` and `/* */` for the JS family (URLs in strings
     never match because `//` must be line-initial). Markdown scans all.
   - Self-reference: the lint's own patterns and docs use digit-free
     placeholder spellings (`[D-NN]`, `Wn-Tn`, `RTn-Fn`), which digit-
     requiring patterns cannot match. Digit-bearing quotes that must stay
     (ban-definition lines in AGENTS.md / .gitignore / .gitattributes) are
     `meta-doc-quoting` entries.
2. **Baseline**: landing whitelist is GENERATED (`--emit-baseline` over
   `git ls-files` × final patterns), never hand-copied; a regen check in
   the new test section fails on divergence. Categories:
   `in-flight-sweep` (per-path, exact-equality counts), `drift-ledger`
   (explicit line-number lists — e.g. the T46 EXPECT `fnTotal` ledger line
   — uncapped on listed lines, any anchor off-list fails), `meta-doc-quoting`
   (capped; region-sha256 pin like cjk history pins), `lint-fixture`
   (permanent red/green fixtures), `frozen-string` (CONTRACTS/locale/error-
   teaching strings carrying anchors in string context, e.g. state.cjs
   `lessonsAnchor`; line-pinned).
3. **Migration**: lint lands blocking on day one together with the
   generated baseline. Exact-equality counts mean every content change
   updates the count in the same commit — stale caps and slack are
   structurally impossible. Whitelist growth vs origin/main fails the CI
   check (entries and sum-of-counts may only shrink on main).
4. **Sweep** (four dispositions per line):
   A) mixed lines → strip anchor, keep WHAT content;
    B) lineage-only lines → delete + backfill into CHANGELOG.md
  `[Unreleased]` in the same batch (entry stays validator-clean prose;
  deleted ids ride the tracked sweep ledger the harness reconciles);
   C) whitelisted (drift ledger, meta-doc) → untouched;
   D) string-context anchors → one-time audit: non-contract strings
   rewritten anchor-free; frozen strings pinned under `frozen-string`.
    The sweep harness (script under test/) is the only legal batch runner:
    it precomputes the allowed editable line set from the lint classifier
    (the `--emit-hits` machine view — `--json` violations alone go empty
    once the baseline lands), asserts post-codemod `git diff -U0` changes ⊆
    allowed set, runs the grep assertions on landed content (lesson
    96615604), and reconciles every deleted anchor id against the batch's
    entry in the tracked sweep ledger. Batches
   run serially in the MAIN SESSION only (lesson 63675448: section runners
   must never run in parallel); per batch `run-sections.sh --affected`;
   full suite once at phase end, main session. Heredoc plan fixtures are
   functional parse data — never swept, plan-format exempt.
5. **Product side**: self-repo lint covers `templates/`; the books gain the
   missing banned forms as digit-free placeholder examples, and a test
   asserts templates/ lint hits == 0 (placeholder spelling keeps this
   true). AGENTS.md/.gitignore/.gitattributes digit quotes get
   `meta-doc-quoting` entries. Setup onboarding gains one hint line
   (`gos init coding`) via a locale key pair (en/zh).

### Alternatives (Rejected)
- ~~Single-tier strong-token lint~~ — weak forms are the mimicry shapes
  (D-21).
- ~~Sweep first, lint last / advisory flip~~ — protection gap + soft
  constraints unenforced for AI sessions (D-23; lesson 5162fc2c).
- ~~Mechanical token strip / bulk deletion~~ — wreckage, string pollution
  (de0eb49f), destroys drift ledger (D-24).
- ~~Hand-copied census~~ — three red-team rounds proved hand counts wrong
  in both directions (42 vs 87 files; bracket-only vs dominant bare forms)
  (D-27).
- ~~maxHits as ≤ cap~~ — partial sweeps leave injection slack; equality
  removes the entire failure class (D-28).
- ~~Backfill into .changes.md~~ — the file is SEALED (header forbids
  appends); CHANGELOG.md [Unreleased] is the live log (D-29).
- ~~Setup wizard seeding step~~ — unlisted cross-domain require for one
  wizard step (D-25).

## Design Decisions (D-NN)

### D-21: Two-tier pattern architecture
- **Decision**: tier-A strong tokens match anywhere; tier-B weak patterns
  (bare wave/task/decision ids, narrative phrases) match comment lines only.
- **Rationale**: bare ids flood false positives on assertion labels inside
  string literals (T55/T89 `"W1 clean rc"`); comment scoping covers the
  real recurrence shapes without drowning functional strings.

| Option | Premise | Pros | Cons | Risks |
|:---|:---|:---|:---|:---|
| two-tier | legacy hits are comment-position; false positives live on code lines | covers weak-form recurrence without string floods | two pattern classes, per-filetype comment detection | block-comment interiors under-matched |
| strong-only | strong tokens are distinctive enough | simplest spec, near-zero false positives | bare wave/task ids and narrative slip through | mimicry vector stays open |
| comment-only | all anchors are comments/prose | absolute string safety | misses anchors rendered to users; heaviest lexer | md fences over-lint examples |

why-not: strong-only — weak forms are exactly what new mimicry produces
(global lesson 4846277e names them the recurrence root); comment-only —
misses string-context anchors later confirmed real by red team (25% of
sampled hits) and needs the heaviest lexing.

### D-22: Exemption boundary = carve-outs + categorized whitelist
- **Decision**: carve out `CHANGELOG.md`, `.changes.md` (untracked,
  defensive note), `.gos/**` (with a sidecar `.gos/**` hit count printed by
  the lint so debt hiding there stays visible); whitelist categories cover
  the scattered legal cases.
- **Rationale**: test `# Covers:` headers have no tool consumer
  (plansnap.cjs reads plan.md only); `.gos/codebase/` is the anchor
  knowledge layer by design; the drift ledger stays covered by line lists
   instead of a convention rewrite.

| Option | Premise | Pros | Cons | Risks |
|:---|:---|:---|:---|:---|
| carveouts-plus-whitelist | scattered legal cases exceed path shapes | one mechanism; migration tracker; ghost hygiene | whitelist file to maintain | dumping ground without caps |
| pure-path-exempt | few directories need exemption | zero whitelist maintenance | T46 ledger and digit-quote docs have no home | gate red on day one |
| inline-pragma | line-grain suppression needed | surgical | an AI-reachable off switch | defeats fail-closed philosophy |

why-not: pure-path-exempt — the T46 drift ledger and digit-bearing quotes
in AGENTS.md/.gitignore empirically need entries beyond path carve-outs;
inline-pragma — the lint guarding against AI self-leniency must not ship
an AI-reachable suppression switch.

### D-23: Whitelist-as-migration-tracker, blocking from day one
- **Decision**: lint lands blocking with the generated baseline; batches
  shrink entries; ghost entries fail.
- **Rationale**: cjk-lint-validated migration shape (the count-cap is new
  machinery, defined by D-28 equality semantics); whitelist size is
  machine-visible remaining debt.

| Option | Premise | Pros | Cons | Risks |
|:---|:---|:---|:---|:---|
| tracker-day-one | cjk-lint proved the shape in this repo | protection closes at landing; batches are ordinary PRs | initial registration chore | caps set wrong without generation (solved by D-27) |
| sweep-first | one scoped effort cleans everything | zero migration machinery | whole sweep window unprotected | new anchors land in swept files unseen |
| advisory-flip | gradual tightening | early visibility | advisory is ignorable by AI sessions | flip moment forgotten = forever soft |

why-not: sweep-first — the sweep crosses many commits with zero
protection; advisory-flip — soft constraints are unenforced for AI
sessions (lesson 5162fc2c) and the flip is a manual step.

### D-24: Four-way disposition sweep (three + frozen-string audit)
- **Decision**: strip-anchor-keep-WHAT / delete-with-CHANGELOG-backfill /
  leave-whitelisted / string-context audit (rewrite or pin as frozen-string).
- **Rationale**: ~25% of hits sit in string context incl. frozen contract
  strings asserted via `gos _contract` (T9/T13) — a comment-only view
  would leave them unnamed and unconstrained.

| Option | Premise | Pros | Cons | Risks |
|:---|:---|:---|:---|:---|
| judgment-disposition | mixed lines carry real WHAT content | zero information loss; end-state comment quality | slowest; needs disposition rules pinned | judgment drift across batches |
| mechanical-strip | anchor tokens are regular | fastest, batchable | grammatical wreckage; string pollution (de0eb49f) | codemod touches literals |
| bulk-delete | anchor lines have no standalone value | fastest, cleanest terminal state | kills mixed-line invariants and the drift ledger | golden/source-parse tests break |

why-not: mechanical-strip — leaves half-sentences and risks the exact
codemod string pollution this repo already recorded; bulk-delete — would
destroy the T46 drift ledger line and function comments riding anchor
lines.

### D-25: Seeding entry stays `gos init coding`; setup gains a hint line
- **Decision**: single seeding master; one locale key pair adds the hint.
- **Rationale**: seeding is fully delivered and T69-tested; a wizard step
  needs an unlisted cross-domain require — cost overruns benefit.

| Option | Premise | Pros | Cons | Risks |
|:---|:---|:---|:---|:---|
| single-master-hint | seeding delivered; only discoverability lags | one locale key pair; zero duplication | user types one extra command | none material |
| wizard-step | users expect one-stop onboarding | strongest discoverability | unlisted ops→task require; longer wizard | architecture loosens for a hint |
| migrate-entry | phase text letter | matches phase wording | breaks T69 and init verb symmetry | command compatibility break |

why-not: wizard-step — needs an unlisted cross-domain require for one
wizard step; migrate-entry — destroys the init git/coding verb symmetry
and T69 coverage.

### D-26: Product-side scope = self-repo enforcement over templates/
- **Decision**: lint covers templates/ with placeholder-spelling books;
  user-repo enforcement capability deferred.
- **Rationale**: phase text applies the lint TO the assets; cjk-lint
  self-repo-only precedent holds. NOTE: the intent phrase "so user
  repositories inherit the discipline" is escalated for user ruling
  (see Escalation) — this decision documents the proposed reading, not a
  self-approved   intent amendment.

| Option | Premise | Pros | Cons | Risks |
|:---|:---|:---|:---|:---|
| literal-scope | phase text applies the lint TO the assets | zero scope growth; precedent-consistent | user repos get no mechanical check | none (DI-1 parks the capability) |
| ship-capability | gates seeded=trusted channel exists | optional adoption path | scope + template + bootstrap UX | unproven adoption surface |
| default-enforce | strongest inheritance | maximal discipline spread | breaks self-repo-only precedent | user repos red on day one, hostile |

why-not: ship-capability — beyond the phase's literal scope, deferred as
DI-1; default-enforce — imposes authoring discipline on consumers who
never opted in and would fail their existing comments without a bootstrap.

### D-27: Census-first patterns; whitelist is lint-generated
- **Decision**: the lint ships `--emit-baseline`; the landing whitelist is
  its machine output; a regen guard fails divergence; hand edits rejected.
- **Rationale**: red-team rounds 1-3 independently disproved every hand
  census (narrower patterns, wrong scope); whitelist == lint output is the
  only reproducible invariant.

| Option | Premise | Pros | Cons | Risks |
|:---|:---|:---|:---|:---|
| emit-baseline | the lint is the only authority on its own patterns | reproducible; regen guard kills drift | generation mode must exist | none structural |
| hand-census | a careful grep suffices | zero tooling | three rounds proved hand counts wrong both ways | landing-day gate red on unregistered files |
| no-baseline | exempt legacy wholesale | simplest | no migration tracking; debt invisible | whitelist never shrinks |

why-not: hand-census — 42-file vs 87-file and bracket-only vs bare-form
errors were both made by the designer before red team caught them;
no-baseline — removes the machine-visible debt metric and any shrink
discipline.

### D-28: Exact-equality counts; Wave N demoted; plan-format exempt
- **Decision**: `maxHits` means actual == registered (both directions
  fail); bare `Wave N` moves to tier B; plan-syntax lines (wave headings,
  Covers lines inside plan fixtures) are structurally exempt.
- **Rationale**: equality kills stale-cap slack and forces same-commit
  count updates; `### Wave 1` is the product's own plan.md grammar —
  tier-A would permanently red on functional data.

| Option | Premise | Pros | Cons | Risks |
|:---|:---|:---|:---|:---|
| equality-counts | counts are state, not ceilings | slack structurally impossible; auto-tightening | every edit re-runs emit-baseline | friction (accepted deliberately) |
| cap-upper-bound | counts as ceilings only | fewer whitelist touches | partial sweeps leave injection budget | stale caps hide new anchors |
| line-count-unit | cjk homolog counts lines | matches precedent | multi-anchor lines decay invisibly | per-occurrence truth lost |

why-not: cap-upper-bound — a cap set at 20 with 8 swept leaves 12 free
injections forever; line-count-unit — one line holding five anchors can
lose four without the count moving.

The Wave-demotion half of this decision:

| Option | Premise | Pros | Cons | Risks |
|:---|:---|:---|:---|:---|
| demote-to-tier-b | Wave N is plan syntax, not an AI trace | functional data never flagged | one weak form leaves tier A | plan files gain tier-B exposure only in comments |
| keep-and-whitelist | plan files get permanent entries | tier A stays maximal | ~10 permanent entries for product grammar | every new plan fixture needs an entry |
| drop-wave-pattern | nobody writes Wave N as a trace | zero conflicts | real wave-narrative comments escape | recurrence vector |

why-not: keep-and-whitelist — permanent whitelist entries for the
product's own file format is inversion (the lint exists to catch traces,
not grammar); drop-wave-pattern — wave narrative in comments is a real
banned form, tier B keeps it covered where it actually occurs.

### D-29: Backfill target is CHANGELOG.md [Unreleased]; placeholder teaching
- **Decision**: deleted lineage backfills into CHANGELOG.md; teaching docs
  write banned forms digit-free.
- **Rationale**: .changes.md carries a SEALED header forbidding appends;
  digit-bearing teaching examples are real tier-A hits (books' `[REVIEW M1]`
  lines proved this).

| Option | Premise | Pros | Cons | Risks |
|:---|:---|:---|:---|:---|
| changelog-backfill | CHANGELOG [Unreleased] is the live log | appendable; lint carve-out compatible | ids must reconcile somewhere assertable (tracked sweep ledger) | entry format drift |
| changes-md | spec draft's first instinct | single traceability home | the file is SEALED, appends forbidden | violates its own header |
| no-backfill | deleted lineage lives in git blame | zero extra writes | sweep deletions lose their audit trail | red team R3-F6 verification gap |

why-not: changes-md — the file's own SEALED header forbids appends (red
team R3-F5 caught the spec draft violating it); no-backfill — git blame
cannot be asserted by any gate, the reconciliation check would have
nothing to verify.

Placeholder teaching half: teaching docs name banned forms digit-free
(`[D-NN]`, `Wn-Tn`) — digit-bearing examples are themselves tier-A hits,
so the books' current `[REVIEW M1]` lines switch to `[REVIEW Mn]` and a
test pins templates/ lint hits == 0.

| Option | Premise | Pros | Cons | Risks |
|:---|:---|:---|:---|:---|
| placeholder-spelling | digit-free text cannot trip digit patterns | templates stay whitelist-free clean | examples slightly less literal | none |
| digit-examples-plus-whitelist | examples look exactly like the ban | maximal teaching fidelity | books need permanent entries | every example is a gate-time hit |

why-not: digit-examples-plus-whitelist — teaching the ban with text that
violates the ban, then whitelisting it, inverts the message the phase
exists to send.

### D-30: Sweep harness mechanizes the batch discipline
- **Decision**: harness precomputes allowed lines, guards diff ⊆ allowed,
  reconciles deleted anchor ids against the batch CHANGELOG entry, runs
  assertions; batches serial, main session only; lint assertions in tests
  use `--json` fields + exit codes (never unescaped brackets in
  assert_contains — lesson 265a5dd3).
- **Rationale**: all four sweep disciplines were text-only with no
  verification path (red team R1-F5/R3-F6); the harness is the sole legal
  consumer of `--json`.

| Option | Premise | Pros | Cons | Risks |
|:---|:---|:---|:---|:---|
| harness-runner | disciplines need code enforcement | one guard covers all batches | build cost up front | false sense if harness itself untested (needs its own section) |
| per-batch-manual | batches are few, reviewer is careful | zero build cost | four text constraints re-verged every batch | exactly the de0eb49f/96615604 incident shapes |

why-not: per-batch-manual — every incident this repo recorded in the
sweep class (codemod string pollution, silent replace misses, parallel
runner races) happened under manual discipline; red team R1-F5/R3-F6
confirmed the four constraints had no verification path without a harness.

### D-31: Intent deviation ruling — seeding entry + user-repo enforcement
- **Decision**: seeding reads "via gos init coding" (setup gains a hint
  line); user-repo enforcement stays deferred as DI-1. Recorded as the
  user's ruling at spec approval; goal-backward verification reads this
  over the intent's literal wording.
- **Rationale**: the intent letter ("seedable by gos setup", "user
  repositories inherit the discipline") conflicts with the delivered
  reality (seeding verb is `gos init coding`, T69-tested) and with the
  phase's self-repo lint scope; a spec may not silently shrink a confirmed
  intent, so the conflict was escalated and ruled.

| Option | Premise | Pros | Cons | Risks |
|:---|:---|:---|:---|:---|
| amend-reading | seeding is delivered; only the wording lags | zero scope growth; honors D-25/D-26 | intent text stays stale in state | none once the ruling is ledger-recorded |
| pull-into-scope | user-repo enforcement is the phase's soul | strongest inheritance | scope grows (gates example + whitelist bootstrap UX) | unproven adoption surface rushed into the phase |

why-not: pull-into-scope — the user chose the amended reading at the
2026-10-26 approval dialogue; user-repo enforcement is parked as DI-1 with
an enforced concerns.md anchor instead.

## Scope

### In Scope
- `test/checks/ai-trace-lint.sh` (node helper) + generated whitelist +
  `--emit-baseline` + regen guard
- gate all blocking wiring (self-repo guard, violationCount, ANSI strip,
  non-inviting fix-string); whitelist growth-vs-main CI check
- New test section(s): red/green fixtures (lint-fixture category), count
  equality both directions, ghost detection, regen guard, gate integration
  (planted anchor → gate fails), templates/ clean assertion
- Sweep harness + domain batches across bin/ and test/ (+ .gitattributes
  real-anchor line), CHANGELOG backfill per batch
- Books placeholder-form additions; setup hint line (en/zh);
  meta-doc-quoting entries for AGENTS.md/.gitignore/.gitattributes
- concerns.md close-out: FB-4 cure + DI-1/DI-2 parking anchors

### Out of Scope
- Rewriting the T46 drift-declaration convention (line-list whitelisted)
- Sweeping `.gos/**` (exempt layer, sidecar metric only)
- User-repo lint capability (parked as DI-1 pending user ruling)
- Phase P5 dialogue-governance re-home (separate phase)
- cjk-lint `grep -P` migration (recorded as debt; separate fix)

## Deferred Ideas
- DI-1: ship an adoptable ai-trace lint example through the gates
  seeded=trusted channel so user repos can opt into the discipline.
  Parking: concerns.md entry with anchor `DI-1 ai-trace-user-repo` at
  close-out (enforced by the deferred-findings gate).
- DI-2: stateful block-comment lexing for tier-B interiors. Parking:
  concerns.md entry with anchor `DI-2 tier-b-block-comments`.

## Escalation (user ruling recorded)

The phase intent (confirmed) reads "... templates ... seedable by **gos
setup**" and "apply the same lint to product-seeded assets **so user
repositories inherit the discipline**". The spec proposes: seeding stays
on `gos init coding` with a setup hint (D-25), and user-repo enforcement
is deferred (D-26, DI-1).

**Ruling (user, 2026-10-26, at spec approval)**: amend the reading —
seeding means `gos init coding` (setup gains a hint line); user-repo
enforcement stays deferred as DI-1. Recorded as D-31; goal-backward
verification reads D-31 over the intent's literal wording. No state
intent rewrite (`init --force` resets the diff baseline — never
mid-task); the ruling lives in the decision ledger, which is the
traceability home.

## Red Team Record (Lv2+ mandatory before user approval)

| Round | Perspective | Findings | Dispositions (A/AP/R-with-facts/D) |
|:---|:---|:---|:---|
| 1 | misuse/safety | 8 | 7 ACCEPT (baseline D-27, plan-format D-28, capped categories+pins, equality+fix-string+growth check, harness D-30, violationCount, ANSI strip), 1 ACCEPT-PARTIAL (.gos carve-out kept + sidecar count metric) |
| 2 | edge/exception | 9 | 9 ACCEPT (D-27 generated census, placeholder spellings, D-28 equality, drift-ledger line lists, lint-fixture category, node-helper matching, yml/# default table, README placeholder, gos track + .changes.md note) |
| 3 | completeness | 10 | 9 ACCEPT (census-first tier-B grammar, D-27, book placeholders + templates-clean test, frozen-string class, D-29 CHANGELOG, D-30 mechanized guards, spec-pinned verify commands, concerns parking, serial execution + json assertions), 1 escalated-to-user → ruled (D-31) |
| 4 | plan-attack | 11 | 10 ACCEPT (sweep ledger replaces id-bearing changelog bodies F1; lint-fixture registration moves to fixture-creating task F2; `--emit-hits` registered-hit view F3; whitelist entry key = (path, category) F4; batch done-when exact equality F5; shrink check fail-closed on R/D F6; census scope covers meta-doc paths F7; harness self-test embedded not sectioned F8; T2 grep oracle mirrors tier grammar F9; red assertions on unregistered scratch copies F10), 1 ACCEPT-PARTIAL (hint truth asserts renderCodingHint() output path both locales; full TTY capture impractical F11) |

> Verdict: not converged-zero — rounds 1-3: 27 findings, 26 accepted (several
> merged into D-27..D-30), 1 escalated-to-user and ruled (D-31); round 4
> (plan-attack, on the plan): 11 findings, 10 accepted + 1 accepted-partial,
> folded into plan rev 2 and the R-05/D-29/§4 mechanism edits above.

## Risks
- Tier-B narrative regex is fuzzy → start narrow, extend on real misses;
  census-first task sizes the true grammar before patterns freeze.
- Block-comment interiors under-matched for tier B → DI-2; tier A still
  matches there.
- Sweep touches test fixtures whose plan heredocs are functional data →
  plan-format exemption + harness allowed-line guard.
- Whitelist growth check depends on PR flow (main is PR-only) → verified
  in CI against origin/main diff.
- Exact-equality counts raise edit friction (any anchor-adjacent edit
  must re-run --emit-baseline) → accepted deliberately: friction is the
  enforcement.

## Verification methods (pinned per truth)

- T1: `bash test/checks/ai-trace-lint.sh --json` on planted fixture →
  non-empty violations, exit 1; clean tree → exit 0.
- T2: `node bin/gos.cjs gate all` output contains `ai-trace` check line;
  planted anchor (in a lint-fixture sandbox) flips the gate to fail.
- T3: register fixture with maxHits=N; plant N+k anchors → count-equality
  violation `stale-or-exceeded`; plant N−k → same violation class.
- T4: `ai-trace-lint.sh` exit 0 AND `jq '[.[] | select(.category=="in-flight-sweep")] | length' == 0` over the whitelist.
- T5: per-pattern grep over templates/coding-standards/ for digit-bearing
  anchor forms → 0 hits; books name placeholder forms.
- T6: setup onboarding output (both locales) contains the hint string
  (assertion-grade, T-section).
