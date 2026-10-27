---
name: gos-ship
description: "Use when VERIFY passes — archive phase artifacts with delta.md, write change record with D-NN/R-NN traceability, run cleanup checklist, atomic commit. Every task leaves a trace."
---

# GOS SHIP — Archive & Record (Baseline)

<HARD-GATE>
Every task leaves a trace. Even a typo fix gets a change record.
"Too small to document" is not valid.
</HARD-GATE>

## Quick Start

```bash
gos archive    # moves spec/plan to .gos/archive/, writes delta.md, marks DONE
```

## Progressive Disclosure

| When | Do | Read for detail |
|:---|:---|:---|
| Entering SHIP | Read state.json (all stage outputs) | — |
| Write change record | `CHANGELOG.md` via `gos changelog add` (D-NN/R-NN trace refs derived from the task) | `../../templates/trace-template.md` |
| **Before `gos archive`** | **Ensure `CHANGELOG.md` [Unreleased] has a bullet stamped with today's UTC date — `gos changelog add` writes it (archive gate blocks otherwise; tests use GOS_SKIP_SHIP_CHECK=1) + package.json version bumped if this is a version-level iteration. Lv4 rendered views (DECISIONS/ROADMAP/REQUIREMENTS) auto-generate at archive — never edit them by hand.** | — |
| **Gap or user-challenge occurred** | **Record via `gos lessons add --type project\|model --text "…"` (scene → lesson). VERIFY gaps and user pushback that changed design BOTH count. Alternative: `gos lessons skip --reason` ( exemption, audited + mirrored to .changes.md)** | `reference/artifact-lifecycle.md` |
| Never archived/cleaned | `.gos/logs/truth-receipts.md` (replay receipts stay forever, machine-local) + `.gos/lessons.md` + sidecar `.gos/cache/.lessons-anchors.json` (cache zone, machine-regenerated) | `reference/artifact-lifecycle.md` |
| Cleanup checklist | **RUN `scripts/cleanup-scan.sh`** (exit 1 = findings block archive) | `reference/artifact-lifecycle.md` |
| Archive | Present delivery summary → user accepts → `gos approve archive` → `gos archive` | `reference/artifact-lifecycle.md` |
| Retrospective (Lv3+) | 3 questions ≤5 bullets each | — |
| Exit | Task DONE | — |

## State

**Read:** state.json (spec_path, plan_path, decisions, truths, review_findings)
**Write:** `CHANGELOG.md` (via `gos changelog add`) + state.json (current_stage: DONE, completed_at)

## Cleanup Checklist (always)

- [ ] No debug artifacts (console.log/print/debugger)
- [ ] No dead code (commented code, unused vars)
- [ ] No secrets (API keys, passwords)
- [ ] Documentation updated (README if features changed)

## Anti-Rationalization (top 3)

| Excuse | Reality |
|:---|:---|
| "Change record can wait" | Write NOW. Tomorrow you forget the details. |
| "Console.log is harmless" | Remove ALL debug artifacts. No exceptions. |
| "Skip retrospective, it went fine" | "Fine" hides insights. Even good work has lessons. |
