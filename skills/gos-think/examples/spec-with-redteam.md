# Spec: doctor command (COMPLETE EXAMPLE with Red Team record)

> Copy this structure: decisions with rationale, requirements with IDs,
> truths with verify commands, AND the Red Team rounds record with the
> findings that changed the design. The Red Team section is what makes
> this a GOS spec — a spec without attack history is untested.

> **Date**: 2026-08-14 | **Level**: Lv2 | **Status**: user-approved

## Goal

Add `gos doctor`: read-only diagnosis of GOS installation (CLI version /
skills link integrity / platform detection) with repair suggestions,
semantic exit codes (0 healthy / 1 issues).

## Requirements

- **R-01**: Diagnose installation state and suggest fixes (from intent)

## Decisions

### D-01': Fix suggestions come from a HARDCODED frozen table

Decision card (P15 D-62 — every decision shows its options symmetrically):

| Option | Premise | Pros | Cons | Risks |
|:--|:--|:--|:--|:--|
| Frozen table | repair text is safety-relevant | drift-proof, testable | edits need code change | table goes stale |
| Soft whitelist | text discipline | flexible | violates standing lesson | relay can mutate |
| Freeform generation | best phrasing | adapts | unreviewable output | hallucinated commands |

why-not: Soft whitelist — text discipline = no discipline (round 1 finding);
Freeform generation — a weak-model relay can mutate the output
recommendation: Frozen table — unconditional here because the output is
safety-relevant and the frozen-value test channel already exists

- **Decision**: `DOCTOR_FIXES = Object.freeze({...})` is the only source
  of repair text. Paths never enter command strings; drift case outputs
  literal `<repo-path>` placeholder.
- **Rationale**: originally a soft text whitelist. Red Team round 1
  (misuse) classified it as text discipline = no discipline. Upgraded to
  code per the standing lesson: user-facing command output constraints
  must be code-level.

### D-01b: Fail-closed output guard
- **Decision**: every Fix line must match whitelist regex
  `^(gos (setup|teardown)…|reinstall GOS…|report issue…)$`; non-match →
  exit 2 and the line is NOT printed.
- **Rationale**: defense in depth — future edits to the table can't
  reintroduce dangerous output.

### D-02: Anti-misread output contract
- **Decision**: explicit text states (`✓ OK:`/`⚠ MISSING:`/`⚠ BROKEN:`),
  mandatory trailing `RESULT: HEALTHY(n)/ISSUES FOUND(n) — exit code`,
  exit semantics documented in output tail.
- **Rationale**: primary consumers are often weak models relaying to
  users; they must relay correctly with zero inference.

### D-03: Unknown-exception fallback is reporting, never reinstall
- **Decision**: `unknown → report issue at <repo>/issues with doctor
  output` (+ note that .gos/ task state survives reinstall).
- **Rationale**: reinstall is the heaviest destructive op; unknown cases
  need diagnosis, not nuking. Red Team round 2 (edge) finding.

## Observable Truths

- **T1**: healthy env → all ✓, `RESULT: HEALTHY (0 warnings)`, exit 0 — verify: run doctor in clean fake-HOME
- **T2**: broken link → precise MISSING/BROKEN + fix + exit 1 — verify: unlink one skill, run doctor
- **T3**: discoverable — `gos help` lists doctor; no platforms → Fix: gos setup
- **T4**: security — output greps 0 for rm/unlink/sudo; all Fix lines match whitelist; RESULT line present — verify: TD-05 assertions in test suite

## Deferred Ideas

- DI-1: `--fix` auto-repair mode (needs setup idempotency per-platform)
- DI-2: `--json` machine output for CI

## Risks

- Probe heuristics on exotic platforms → drift classification may be
  conservative (reports BROKEN for unexpected-but-working links);
  accepted: false-positive warning is safe-direction failure
- Platform set fixed (3) → new assistants need code change; accepted
  for current scope, tracked as future extensibility decision

## Lessons Applied

- [2026-08-14] soft-text-whitelist lesson → D-01' hardened BEFORE any
  user challenge this time (the lesson working as designed)

## Red Team Record

| Round | Perspective | Findings | Dispositions |
|:---|:---|:---|:---|
| 1 | Misuse/Safety | 2 (soft whitelist is text discipline; path interpolation risk) | ACCEPT×2 → D-01', D-01b (changes landed in spec above) |
| 2 | Edge/Exception | 1 (unknown fallback implicitly reinstall) | ACCEPT → D-03 |
| 3 | Completeness | 0 — converged (attacked: constraint verifiability / unasked gray areas / lessons.md cross-check) | — |

> (This example shows ACCEPT-heavy rounds. A REJECT would need: finding ID,
> factual counter-evidence quoted, attacker round-N+1 verdict CONFIRMED-REJECTED.)

> Round 3 converged. Spec approved by user after this record was shown.
