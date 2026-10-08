---
name: gos-project
description: "Use when starting a Lv4 multi-phase project or completing a milestone — manages PROJECT/ROADMAP/DECISIONS/REQUIREMENTS lifecycle, cross-phase context via rolling DECISIONS.md, drift check at transitions."
---

# GOS PROJECT — Chief Designer (Lv4)

<HARD-GATE>
project.json is the single source of truth. ROADMAP/DECISIONS/REQUIREMENTS are
GENERATED views — edit via gos decision/requirement/phase commands, never by hand.
ROADMAP defines what's next, DECISIONS defines what's decided (never re-ask).
Files win over memory.
</HARD-GATE>

## Quick Start

```bash
gos init 4 "<vision>" --project    # creates project.json truth source + GENERATED four-file set
gos status                          # shows decisions/truths/requirements + DECISIONS.md size
gos gate all                        # hard gates (requirements claim-check active at Lv4)
```

## Progressive Disclosure (mode routing — read ONLY the relevant mode)

| When | Mode | Read |
|:---|:---|:---|
| Lv4 + no PROJECT.md | new-project | `reference/new-project.md` |
| Phase transition (SHIP done, next phase) | evolve | `reference/evolve.md` |
| All phases done / milestone end | complete-milestone (**archive via `scripts/archive-milestone.sh`** — atomic order) | `reference/complete-milestone.md` |

## Core Rules

- Phase CONTENT flows through 7 core skills (THINK→...→SHIP at Lv3 depth)
- This skill manages the project ENVELOPE only
- THINK of each new phase MUST read DECISIONS.md first — do NOT re-ask
- Phase lifecycle via `gos phase add/claim` — ROADMAP.md regenerates from project.json at archive/render
- Requirements claimed per phase via `gos requirement claim` (REQUIREMENTS.md is a GENERATED view); unclaimed at milestone = gate failure
- DECISIONS.md is a GENERATED view (active + 2 recent phases, auto-scoped); project.json >50 entries → prune-decisions.sh advisory
- Atomic commits: `gos commit <stage>` per stage, includes project files

## Anti-Rationalization (top 3)

| Excuse | Reality |
|:---|:---|
| "Roadmap in my head is fine" | Memory drifts. ROADMAP.md doesn't. |
| "I'll re-ask that decision to be safe" | Re-asking wastes trust. Read DECISIONS.md. |
| "One unclaimed requirement is OK" | `gos gate requirements` exits 1. It's not OK. |
