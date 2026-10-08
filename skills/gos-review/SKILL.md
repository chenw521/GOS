---
name: gos-review
description: "Use when reviewing completed code — two-phase review (spec compliance first, then code quality). Run gos gate coverage to audit decisions. Never skip Phase 1."
---

# GOS REVIEW — Two-Phase Code Review

<HARD-GATE>
Review spec compliance (Phase 1) BEFORE code quality (Phase 2).
It doesn't matter how good the code is if it solves the wrong problem.
</HARD-GATE>

## Quick Start

```bash
gos instructions review    # decision inventory + requirement status for audit
```

## Semantic Closure Consumption (Phase D)

When reviewing changes to `bin/gos.cjs` or any file named in a task's Files:
1. Run `gos map closure <changed-file> --semantic` — the must-check set names files whose
   correctness your reviewed change co-determines (calls/contracts/hand edges). A review
   that ignores a listed dependent is incomplete.
2. The must-run section list (hunk→fn→cmd) defines minimum test evidence: cite it in the
   review verdict. Missing runs → finding, not opinion.
3. `gos map edge verify` failing (hand edit / stale freeze) is an automatic MAJOR finding —
   integrity anchors are non-negotiable.

## Progressive Disclosure

| When | Do | Read for detail |
|:---|:---|:---|
| Entering REVIEW | Read state.json decisions + build_summary | — |
| Curated concerns | `gos context review` read_files includes non-empty `.gos/concerns.md` — READ it; stale/resolved entries → `gos concerns prune --contains <substring>` (anchored, auditable); never hand-edit (anchor locks) | — |
| Phase 1: D-NN audit | **Dispatch `prompts/spec-reviewer.md`** (fresh-context, assume omission) or run inline | `prompts/spec-reviewer.md` |
| Phase 1: R-NN audit | For each R-NN: shipped? evidence? | — |
| Phase 1: scope check | Deferred Ideas NOT implemented? | — |
| Phase 1 FAIL | Return to BUILD with specific issues | — |
| Phase 2: quality | **Dispatch `prompts/code-quality-reviewer.md`** or agents/code-reviewer | `prompts/code-quality-reviewer.md` + `reference/review-checklists.md` |
| Phase 2: severity | Critical/Major must fix; Minor can defer | `reference/review-checklists.md` |
| Phase 2 FAIL | Return to BUILD with findings | — |
| Writing review report | Use skeleton `../../templates/review-checklist.md` | — |
| Exiting REVIEW | `gos commit review` | — |

## State

**Read:** state.json (decisions, requirements, build_summary)
**Write:** state.json (review_findings: severity, issue, status)

## Exit Gate

All Critical/Major fixed → `gos commit review`.

## Anti-Rationalization (top 3)

| Excuse | Reality |
|:---|:---|
| "Code looks fine, skip to VERIFY" | Phase 1 catches wrong-thing-built. Do both. |
| "That Critical isn't really critical" | Security/spec/data = Critical. No negotiation. |
| "Minor issues can wait" | True, but log them. Unlogged = forgotten. |
