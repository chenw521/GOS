---
name: gos-router
description: "Use when starting any development task or resuming a GOS session — auto-activates to assess complexity, recommend level (Lv0~Lv4), enforce baseline ring (INTENT→VERIFY→TRACE), and chain stages."
---

# GOS Router — Entry Point

<HARD-GATE>
Every task passes INTENT → VERIFY → TRACE. Waiting for user confirmation IS part of INTENT — proceeding without it is the #1 rationalization.
</HARD-GATE>

## Quick Start

<!-- gos:core-shortlist begin -->
- `gos` (no args) — status + what's next (zero-memorization entry)
- `gos init <level> "<intent>"` — start task
- `gos commit <stage>` — atomic commit + stage advance
- `gos gate all` — hard gates (exit 1 on failure)
- `gos context <stage>` — pre-computed context JSON
- `gos resume` — cross-session resume summary
- `gos instructions <stage>` — stage-by-step guidance
- `gos phase <sub>` — Lv4 phase lifecycle
- `gos decision <sub>` — record/amend decisions
- `gos help [--json]` — full capability discovery

Full capability: `gos help [--json]`
<!-- gos:core-shortlist end -->

- `gos brownfield` — adopting an existing repo (probe, safe-skip seed, dormant hooks; not part of the core shortlist set)

```bash
gos                # no args = status + what's next (zero-memorization)
gos init <level> "<intent>" # start a task (creates state.json + )
```

## Progressive Disclosure

| When | Do | Read for detail |
|:---|:---|:---|
| **FIRST STEP (state-first guard)** | **Check for an in-flight task BEFORE anything else: `gos status`. Active task exists (not DONE)? → take the `gos resume` branch — present the summary, continue from its current stage. NEVER re-init over live state, NEVER re-ask INTENT for a task already in flight. Only when no active task exists → New task flow.** | — |
| Existing repo, no GOS assets yet | `gos brownfield` — read the adoption report (safe-skip seed, dormant hooks), then continue with New task flow | — |
| New task | Restate intent → present options with trade-offs → WAIT for confirm | — |
| Assessing level | Show ALL levels with recommendation highlighted → WAIT | `reference/complexity-matrix.md` |
| User confirms level | `gos init <level> "<intent>"` | — |
| Resuming session | `gos resume` → present summary → ask "Continue?" | — |
| Stage transition | `gos commit <stage>` → advances automatically | — |
| Gap found in VERIFY | Minor→BUILD, Major→PLAN(Lv3+)/THINK(Lv2), Block→THINK | `reference/gap-closure.md` |
| User override | "simpler"→downgrade, "full flow"→upgrade | — |
| Tool names unclear (non-opencode host) | Check the shared platform mapping | `reference/tool-mapping.md` |

## INTENT Requirements (always)

**Sub-step 0 — Expectation exploration (conditional brainstorm):**
Trigger when the request is a greenfield/vague idea ("I want to build X but haven't thought it through yet").
Ask ONE open question at a time: target users? success in 3 months? what it is NOT?
2-4 questions max, then converge to a one-line vision. Skip entirely for clear
requests (bugfix, specific feature) — they go straight to step 1.

1. Restate task in one sentence → WAIT for "yes"
2. Present 2-3 design options with pros/cons (never just your preference)
3. Show all levels with 👉 marking recommendation → WAIT
4. After confirm: `gos init` then enter first stage

**Level choice is a decision card (P15 ).** The level recommendation is the
biggest single decision a user makes — present it as the same card contract as
THINK gray areas (`skills/gos-think/reference/dialogue-protocol.md` §Decision
Card): options = the candidate levels, each with **premise** (when this level
is right) / pros / cons / risks symmetrically, a `why-not:` line naming the
rejected levels, and a **conditional recommendation** ("if the change is <one
file, obvious> → Lv1; if it touches shared surfaces → Lv3"). Never present
only your favorite level — the card is the difference between a routed
decision and a model preference.

Rendered example (Lv1 vs Lv2 vs Lv3 for a small feature):

| Option | Premise | Pros | Cons | Risks |
|:--|:--|:--|:--|:--|
| Lv1 (INTENT→BUILD) | isolated fix, zero ambiguity | fast | no spec | wrong-fix cost on subtle bugs |
| Lv2 (+THINK) | fix with 1-2 gray areas | decisions recorded | +1 stage | mild ceremony |
| Lv3 (+PLAN/REVIEW) | new feature, shared surfaces | full traceability | heaviest | overkill on trivia |

why-not: Lv1 — the change touches shared gate behavior; Lv3 — no architecture
moves here, the review cost buys nothing
recommendation: Lv2 — conditional: if a second gray area appears during THINK,
upgrade to Lv3 (route gap-closure)

## Level Routes

| Level | Flow |
|:---|:---|
| Lv0 | INTENT → exec → VERIFY → TRACE |
| Lv1 | INTENT → BUILD → VERIFY → TRACE |
| Lv2 | INTENT → THINK → BUILD → VERIFY → TRACE |
| Lv3 | INTENT → THINK → PLAN → BUILD → REVIEW → VERIFY → SHIP |
| Lv4 | gos-project → [Lv3 phases × N] → complete-milestone |

## Anti-Rationalization (top 3)

| Excuse | Reality |
|:---|:---|
| "Request is obvious, skip confirm" | Misunderstanding costs 10x more than 5-second confirm |
| "I'll show only my preferred option" | Without alternatives, user can't make informed choice |
| "Skip VERIFY, it's just formality" | Baseline ring is non-negotiable |
