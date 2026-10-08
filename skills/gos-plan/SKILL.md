---
name: gos-plan
description: "Use when breaking a spec into executable tasks — run gos instructions plan for step-by-step guidance, gos gate coverage to enforce Decision Coverage before exiting."
---

# GOS PLAN — Task Breakdown

<HARD-GATE>
Run `gos gate coverage` before exiting. exit 1 = uncovered decisions = cannot leave PLAN.
</HARD-GATE>

## Quick Start

```bash
gos instructions plan    # get step-by-step guidance for THIS task
```

The CLI returns: decision inventory, uncovered D-NN list, requirement
claims status, and the exact steps to produce the plan (path supplied by `gos context plan` → artifact_paths.plan — under `.gos/task/<id>/`)

## Progressive Disclosure

| When | Do | Read for detail |
|:---|:---|:---|
| Entering PLAN | `gos context plan` (pre-computed JSON) → follow it | — |
| Want a real example | **Read `examples/complete-plan.md` — copy its structure** | `examples/complete-plan.md` |
| Decomposing tasks | Follow CLI steps 1-3 | `reference/task-decomposition.md` (Good/Bad patterns) |
| Checking coverage | `gos gate coverage` | `reference/revision-loop.md` (if exit 1) |
| Large plan (>20 tasks) | Offer Phase Split to user | — |
| Stress-testing | Apply Pre-Mortem + MECE | `reference/thinking-models.md` |
| **Before user confirms plan (Lv3+)** | **Red Team round 4 (plan-attack): dispatch `../gos-think/prompts/red-team-attacker.md` on the plan — wave deps / interface docking / untestable done-when** | `../gos-think/reference/red-team.md` Attack Scope |
| Defining truths | One truth per feature with curl/test command | `reference/truths-format.md` |
| Exiting PLAN | `gos gate coverage` exit 0 + `gos approve plan` → `gos commit plan` | — |

## State

**Read:** `.gos/state.json` (spec_path, decisions, requirements)
**Write:** the plan at the path from `gos context plan` (artifact_paths.plan) + update state.json (plan_path, decisions[].covered, observable_truths)
**Advance:** `gos commit plan`

## Exit Gate (must pass ALL)

1. `gos gate coverage` → exit 0 (every D-NN has Covers tag in plan.md)
2. `gos gate requirements` → exit 0 at Lv4 (every R-NN claimed)
3. User confirms plan → `gos approve plan`

## Anti-Rationalization (top 3)

| Excuse | Reality |
|:---|:---|
| "D-05 is minor, skip coverage" | `gos gate coverage` will exit 1. It doesn't care about "minor". |
| "I'll figure out task details in BUILD" | BUILD executes. PLAN designs. Do your job. |
| "Truths can wait until VERIFY" | Truths defined HERE. VERIFY checks them. No truths = no verification. |
