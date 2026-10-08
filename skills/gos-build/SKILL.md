---
name: gos-build
description: "Use when implementing code — wave-based TDD execution with 3-fail architecture rule, parallel dispatch with mandatory aggregation. Run gos instructions build for task list from plan.md."
---

# GOS BUILD — Execute Implementation

<HARD-GATE>
No untested code ships. Every new feature gets TDD (RED→GREEN→REFACTOR).
"It's too simple to test" = the test is also simple. Write it.
</HARD-GATE>

## Quick Start

```bash
gos instructions build    # parses the live plan (path from `gos context plan`), returns tasks with files/read-first/done-when
```

## Progressive Disclosure

| When | Do | Read for detail |
|:---|:---|:---|
| Entering BUILD | `gos instructions build` → todowrite per task — **update todo status in REAL TIME (mark in_progress when starting, completed immediately when done — never batch-update)** | — |
| New feature | TDD: write failing test → confirm RED → minimal code → GREEN → refactor | `reference/build-patterns.md` |
| Dispatching parallel tasks | **Copy `prompts/implementer.md` template — never freestyle agent instructions** | `prompts/implementer.md` |
| Modifying code | Read existing → understand why → minimum change → run existing tests | `reference/build-patterns.md` |
| Fixing bug | Reproduce test → locate root cause → fix → regression test | `reference/build-patterns.md` |
| 3 fix attempts failed | STOP. Question architecture. `gos stage back think` if needed. | `reference/build-patterns.md` |
| 2+ independent tasks | Dispatch parallel agents with precise instructions + boundaries | `reference/build-patterns.md` |
| After parallel wave | **RUN `scripts/aggregate.sh`** (all 3 checks, one verdict) | `reference/build-patterns.md` |
| **Parallel-wave iron rule** | **during parallel waves executors never run gos commit — the main session commits once per wave after aggregation** (frozen phrase, CONTRACTS.decorative.waveSinglePointCommit; executors commit NOTHING — main session merges + commits) | — |
| Global-file tests | fake-HOME always (`HOME=$sandbox/home`) — never pollute real `~/.config/gos/` | — |
| **Modified a file others import/source** | **Pre-run check BEFORE tests: `gos map closure <file>`** — list dependents, extend verification scope to them. Discovering blast radius only at the commit gate = rework (tests rerun, waves reopened) | — |
| Gate emits `impactClosure` N>0 | Execute the printed `run: gos map closure <file> --print0` hint — blast radius exceeds declared Files; `impactClean` ≠ verified, `impactVacuous` ≠ clean (advisory, regex-based) | — |
| Wave complete | Heartbeat report → next wave or REVIEW | — |
| Exiting BUILD | `gos commit build` | — |

## State

**Read:** the plan (path from `gos context plan` artifact_paths.plan) (tasks, waves, dependencies)
**Write:** state.json (build_summary: files_changed, known_issues)

## Exit Gate

All tasks done + tests pass. Then `gos commit build`.

## Anti-Rationalization (top 3)

| Excuse | Reality |
|:---|:---|
| "I'll write tests after" | After = never. RED first, always. |
| "Tried twice, third time's the charm" | After 3 fails → question architecture, not implementation |
| "Debug logging can stay" | Remove ALL debug artifacts before REVIEW |
