---
name: gos-think
description: "Use when designing a feature or making decisions — interactive per-gray-area dialogue with one decision per message, D-NN decision tracking, and Observable Truths definition. Iron Law: no implementation before design approved."
---

# GOS THINK — Requirements & Design

<HARD-GATE>
Law #1: No implementation before design approved. HARD GATE.
Law #2: One decision per message. Never batch unrelated decisions.
</HARD-GATE>

## Quick Start

```bash
gos instructions think    # step-by-step guidance for current task
```

## Progressive Disclosure

| When | Do | Read for detail |
|:---|:---|:---|
| Entering THINK | Read state.json intent + spec (if Lv4: read DECISIONS.md first) | — |
| **Existing repo, no .gos/codebase/ map** | **OFFER one-time mapping (~10min, 3 files: structure/conventions/concerns) — benefits all future tasks** | `reference/codebase-mapping.md` |
| Lv2 light confirm | Restate requirement → define 1-3 truths → WAIT for "yes" | — |
| Lv3+ exploring codebase | Search patterns, conventions, existing utilities | `reference/gray-areas.md` |
| Identifying gray areas | Generate domain-specific (not generic) → multiSelect to user → WAIT | `reference/gray-areas.md` |
| Per gray area | One question per message → **decision card contract** (options × premise/pros/cons/risks + why-not: + conditional recommendation) → record D-NN → checkpoint | `reference/dialogue-protocol.md` §Decision Card (mandatory, gate-enforced) |
| **User mentions a trap/scar ("this has a pitfall / stepped on this before")** | **Capture IMMEDIATELY via `gos lessons add --type project --text "…"` (or `--type model` for model-behavior corrections → global file, auto-expires +90d) — don't wait for SHIP. `gos lessons list` merges both files; incident tasks may take `gos lessons skip --reason "…"` instead of a lesson (D-34 two-of-one, audit-recorded)** | — |
| Defining truths | "What can user observe when done?" → 1 truth per feature | — |
| Scope creep | Redirect to Deferred Ideas, don't reject | — |
| **Spec self-review done** | **Red Team rounds — DEFAULT: dispatch `prompts/red-team-attacker.md` with resolve-model think-redteam (heterogeneous); inline only as degraded fallback (announce it)**. Lv0-1: 1 round safety; Lv2+: 3 rounds. **Every finding MUST get a disposition (ACCEPT/PARTIAL/REJECT-with-facts/DEFER) — see red-team.md Findings Disposition Protocol** | `reference/red-team.md` + `prompts/red-team-attacker.md` |
| Writing spec | Compile D-NN → the spec path from `gos context think` (artifact_paths.spec, under `.gos/task/<id>/`) → self-review → Red Team → WAIT for approval | — |
| Exiting THINK | `gos commit think` after user approves | — |

## State

**Read:** `.gos/state.json` (intent, level) + `.gos/project/DECISIONS.md` (Lv4)
**Write:** the spec at the context-supplied path + decisions via `gos decision add D-NN "<conclusion>" --rationale "..."` (Lv3+; never hand-edit state.json) + state.json (spec_path, requirements, observable_truths)

## Exit Gate

User approves spec (Lv3+) or verbally confirms (Lv2). HARD GATE.
Then `gos approve think` (records the sign-off) → `gos commit think`.

## Anti-Rationalization (top 3)

| Excuse | Reality |
|:---|:---|
| "Simple enough to skip spec" | Simple features still have edge cases |
| "I'll batch all decisions for efficiency" | Batch = rubber-stamp. One per message. |
| "Red Team found nothing on a quick glance" | A glance is not an attack. Run the perspective questions in reference/red-team.md honestly. |
