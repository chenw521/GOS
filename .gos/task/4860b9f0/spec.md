# Spec: Cure between-tasks gate false reds

> **Date**: 2026-10-30 | **Level**: Lv2 | **Status**: Draft

## Goal

When an archived task is left in `.gos/state.json` (the between-tasks window
that lasts until the next `gos init`), `gos gate all` must stop hard-failing
on the dead task's account: the coverage check and the semantic-layer checks
(diff-hit, manifest-stale) downgrade to visible advisory lines that carry a
`gos init` hint, and the gate exits 0 when nothing else is red.

## Motivation

Two live incidents of the same class:

1. **2026-09-23 (concerns ledger, dffa50f0)** — after the P12 archive, two
   docs-only commits made `gate all` fail on the dead task's coverage and
   diff-hit checks: the archived task's decisions lost their plan-scan
   coverage source (plan.md moved to `.gos/archive/`), and post-archive
   commits fell outside every plan task's Files declarations.
2. **2026-10-29 (P0 closeout)** — `gate all` after the P0 ship hit
   `manifest-stale`: the run-manifest was written during P0's verify against
   a tree the archive transaction then moved past, so freshness comparison
   turned stale against a task that no longer exists.

Root cause is one predicate missing: DONE-state task data still feeds
task-level checks that are only meaningful for an active task. `--audit`
already treats DONE as "no active task" for audit purposes, but the plain
(non-audit) gate path — the one a human runs at closeout — has no such
notion, so every between-tasks run gambles on dead-task state.

## Requirements

- **R-01**: Cure between-tasks false reds: with a DONE-state task left in
  state.json, `gos gate all` downgrades coverage/diff-hit/manifest-stale
  checks to advisory lines with an init hint instead of hard-failing.

## Approach

### Selected Approach

Add an "archived idle" predicate to the gate command: a state that is both
`current_stage === 'DONE'` and carries `completed_at` (the same archival
discriminator the archive idempotency path uses). When the predicate holds,
the coverage branch and the semantic branch of `cmdGate` print one advisory
line each (wording pinned in `SEMANTIC_RUNTIME`), count as checked without
arming the green-light downgrade banner, and emit no failures. The
`semanticChecks` engine itself is untouched, so live-task commit embeds and
gate runs cannot inherit the downgrade. `--json` mode reports the idle lines
in its `advisories` array.

### Alternatives (Rejected)

- ~~Extend `--audit` semantics to DONE~~: audit mode *skips* task-level
  checks silently and requires a flag the closeout human did not pass; the
  cure must be the default behavior with visible advisories, not a second
  mode to remember.
- ~~Rewrite the checks to tolerate archived state individually~~: coverage,
  diff-hit, and manifest-stale would each grow archive-aware branches inside
  the shared engine, leaking the downgrade into the commit embed path where
  it could weaken live-task checks.

## Decision Cards (Lv2 — prose decisions, not `decision add` registrations)

### D-1: What counts as "between tasks" (the idle predicate)

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| bare DONE | `current_stage === 'DONE'` alone marks task end | one-field check, trivially testable | also silences the verified-but-unarchived window where plan and manifest checks still carry live meaning; hand-set DONE would mute real reds | the gate guards; the discriminator test fixtures |
| DONE + completed_at | `completed_at` is written only by the archive transaction, so the pair means "archived task retained in state.json" | matches the between-tasks window exactly; same discriminator the archive idempotency path already trusts; pre-archive DONE keeps checks live | two-field coupling; if archive ever changes its marker the idle detector must follow | the gate guards in cmdGate; T-1 replay fixture asserts idle exit 0; regression fixture asserts bare-DONE stays live |
| task dir absent | plan gone from `.gos/task/` is the structural fact | checks literally cannot run against an archived plan | conflates "no plan yet" (Lv0/1, skipNoPlan advisory) with "archived"; filesystem shape becomes gate semantics | nothing — rejected |

why-not: bare DONE — silences the commit-verify-to-archive window where the
checks are still green-able and truthful; task dir absent — plan absence is
ambiguous between never-planned and archived, and the state file already
carries the unambiguous archival marker.

recommendation: DONE + completed_at — conditional: if a future flow ever
writes `completed_at` outside the archive transaction, revisit the pair.

deepen: any option — ask for another dig round

### D-2: Where the downgrade lives and how it accounts

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| branch guards in cmdGate | the two branch heads in the gate dispatch are the only read surfaces that reach the false-red checks with DONE state (commit embed is unreachable from DONE by stage monotonicity) | one small guard per branch; the semanticChecks engine and its commit embed stay byte-identical; standalone `gate coverage` / `gate semantic` inherit the guard for free | per-branch advisory text to maintain | cmdGate coverage + semantic branch guards; `--json` advisories array; T-1 replay asserts both lines |
| flag into semanticChecks | pass `doneIdle` down into the engine | per-check advisory granularity (separate lines for diff-hit vs manifest) | the engine is shared with the commit embed; a predicate bug there weakens live-task commits — the exact failure class this repo's lessons warn about | nothing — rejected as primary |
| reuse auditNoState | fold DONE into the existing audit skip | zero new code | audit *skips silently*; the ruling demands visible advisory lines with an init hint, and folding DONE into auditNoState would also change `--audit` output | nothing — rejected |

why-not: flag into semanticChecks — shared-engine blast radius for a
read-path-only cure; reuse auditNoState — silent skip contradicts the
advisory-lines requirement.

recommendation: branch guards in cmdGate — conditional: if a future caller
invokes semanticChecks with archived state directly, add the predicate at
that caller too rather than inside the engine.

deepen: any option — ask for another dig round

### D-3: Scope boundary — which checks idle, which stay live

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| exactly two branches (coverage + semantic) | the named false-red families all surface through these two branch heads; everything else is either green-by-construction at DONE (truths verified, requirements claimed) or task-independent (lessons integrity, codemap, flip, README, changelog, lints) | surgical: live-task behavior bit-for-bit unchanged outside the two guards; the T33.3a stale-manifest contract for live tasks stays as the regression guard | none observed |
| every task-level branch (including truths/requirements) | idle everything task-shaped for symmetry | simpler mental model | truths/requirements/lessons are real health signals that are green at DONE by construction — idling them would only hide hand-corruption | nothing — rejected |
| coverage only | the dffa50f0 incident named coverage first | smallest diff | leaves the P0-closeout manifest-stale class red; intent explicitly names diff-hit and manifest-stale | nothing — rejected |

why-not: every task-level branch — hides truthful reds (hand-corrupted
truths, broken lessons chain) that cost nothing to keep; coverage only —
fails the second incident.

recommendation: exactly two branches — conditional: if a future task-level
check joins the gate and can false-red on archived state, it opts into the
same guard explicitly rather than by default.

deepen: any option — ask for another dig round

## Scope

### In Scope

- `bin/lib/ops/gate.cjs`: idle predicate helper + guards on the coverage and
  semantic branches of `cmdGate` (covering `gate all`, `gate coverage`,
  `gate semantic` invocations); idle lines appended to the `--json`
  `advisories` array.
- `bin/lib/ops/config.cjs`: two pinned `SEMANTIC_RUNTIME` strings
  (`doneIdleCoverage`, `doneIdleSemantic`), each ending with the
  `gos init <level> "<intent>"` hint; static text (no timestamps, no
  interpolation) so assertions stay deterministic.
- Section test extension (T33 host — it already owns manifest-freshness gate
  behavior and the Lv3 fixture machinery needed to reach an archived state
  with a live plan snapshot): DONE+completed_at → `gate all` / `gate
  coverage` / `gate semantic` exit 0 with both advisory lines and the init
  hint; `--json` verdict pass with idle advisories; bare-DONE (no
  completed_at) with a stale manifest still exits 1; live-task stale
  manifest still exits 1 (existing contract); `--audit` output unchanged.

### Out of Scope

- Any change to `semanticChecks`, `checkManifest`, `diffHitCheck`, or the
  commit embed path.
- Any change to `--audit` semantics (DONE already skips task-level checks
  there with its own line).
- Idling truths, requirements, lessons, codemap, flip, orphans, README,
  changelog, CJK/ascii/ai-trace lints.
- Teaching `gos status` / `gos next` to surface the idle state (see DI-1).
- zh locale coverage for the `SEMANTIC_RUNTIME` string family (see DI-2).

## Deferred Ideas

- DI-1: surface the archived-idle state in `gos status` / `gos next` output
  (banner suggesting init) — when the UX batch touching status lands.
- DI-2: route the `SEMANTIC_RUNTIME` string family through the zh locale —
  when the locale completeness batch lands.

## Red Team Record

### Round 1 — MISUSE

| ID | Finding | Disposition |
|:--|:--|:--|
| RT1-F1 | A lazy agent can hand-write DONE+completed_at into state.json mid-task to silence coverage/semantic reds | ACCEPT-PARTIAL — the advisory is loud by design (its own line, init hint, never a bare pass) and names the idle checks; state.json tampering is already the trust boundary everywhere (spec_sha256 freeze, decisions) so the marginal cost drop is one writeState-shaped edit, not a new capability |
| RT1-F2 | A CI consumer relying on the current DONE-state red as a "stale state left behind" tripwire loses it | REJECT — with facts: CI uses `--audit`/`GOS_CI` (the custom-gate skip path documents this), whose output is unchanged; no such consumer exists in-repo (`gate all --json` callers are local) |

### Round 2 — EDGE

| ID | Finding | Disposition |
|:--|:--|:--|
| RT2-F1 | `gate semantic --audit` with DONE state: auditNoState only folds DONE in when `which === 'all'`, so the standalone semantic subcommand under `--audit` still ran task-level checks today (latent variant of the same false red) | ACCEPT — the branch guards apply to the standalone subcommands regardless of audit flag; the test matrix covers `gate semantic` standalone |
| RT2-F2 | DONE + completed_at but the task dir still exists (mid-archive crash window): checks could still run against a resurrected plan | ACCEPT — design answer: idle anyway; the archived marker, not the directory shape, owns the decision (D-1); fixture writes the state directly so both shapes assert the same |
| RT2-F3 | Non-git worktree / corrupt state: new guard must not change those paths | REJECT — with facts: corrupt state fails `readState` → the existing no-active-task die; non-git skips live inside `semanticChecks`, which the guard runs before (guard is at the branch head in cmdGate, state read already succeeded) |
| RT2-F4 | Uncommitted docs edits + DONE state now gate green instead of red | ACCEPT — this is the requested behavior (dffa50f0: docs commits post-archive); the next init re-arms the checks; noted in Scope so VERIFY does not "fix" it |

### Round 3 — COMPLETENESS

| ID | Finding | Disposition |
|:--|:--|:--|
| RT3-F1 | Enumerated every `gate all` branch against DONE+archived state for other false-red families: truths (verified by construction), requirements (Lv2 implicit / Lv4 claimed), lessons integrity (task-independent), codemap/flip/README/changelog/CJK/ascii/ai-trace (structural), orphans (advisory tier) — none can false-red on archived state | no finding — convergence evidence |
| RT3-F2 | Advisory text with dynamic content (task id, timestamps) would make assertions brittle | ACCEPT — wording contract added to Scope: static pinned strings, no interpolation |
| RT3-F3 | `gos status` between tasks shows a DONE task without an init nudge | DEFER — DI-1 |

> Verdict: converged — Round 3 produced zero un-dispositioned findings.

## Risks

- Predicate drift (archive changes its marker) → the idle guards silently
  stop matching and the old false reds return → mitigated by the regression
  fixtures asserting both the idle exit-0 and the bare-DONE live path; the
  D-1 recommendation line names the revisit condition.
- Downgrade over-reach (silencing a real red) → mitigated by the two-branch
  scope, the loud advisory lines, and the live-task stale-manifest contract
  staying green in the suite.

## Verification (Observable Truths)

- **T-1**: With a DONE+completed_at (archived) task left in state.json,
  `node bin/gos.cjs gate all` exits 0 and prints one coverage idle advisory
  and one semantic idle advisory, each carrying the `gos init` hint; the
  standalone `gate coverage` and `gate semantic` subcommands behave the
  same; `--json` reports verdict pass with the idle lines in advisories.
  Replay: section-test fixture sandbox (Lv3 task driven to archive, then a
  post-archive commit, then the gate runs).
- **T-2**: A live task with a stale run-manifest still fails `gate all`
  (exit 1, manifest-stale), and a bare-DONE state without completed_at keeps
  task-level checks live — the downgrade is exclusive to the archived
  window. Replay: section-test fixture sandbox (stale-manifest live task;
  hand-written bare-DONE state).
