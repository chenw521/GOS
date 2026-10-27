# Mode: evolve (phase transition)

## When
A phase just SHIPped (`gos archive` done) and another phase remains in ROADMAP.

## Flow

1. **Drift check** (the whole point of this mode):
   - Read PROJECT.md "What This Is" + REQUIREMENTS.md + user's recent messages.
   - Ask: "During Phase N we learned X. Does this change the roadmap or any requirement?"
   - If yes → update ROADMAP.md / append or amend R-NN **with user approval** (show the diff before writing).

2. **PROJECT.md evolution** (mandatory checklist, not optional):
   - [ ] "What This Is" still accurate? Update if the system's identity shifted.
   - [ ] "Core Value" still the priority order? Reorder if learned otherwise.
 - [ ] "Requirements Evolution" — append one line: `P2 done: auth shipped; deferred (reason)`.

3. **DECISIONS.md rolling update**:
 - Append this phase's decisions as one-liners: `### P2: auth` + `- : JWT 24h — user chose over sessions`.
   - **Prune if file > 150 lines**: drop entries older than 2 completed phases (detail lives in `.gos/archive/*/delta.md`).

4. **Next-phase handoff**:
   - Show: "Next: P3 — [goal]. Unclaimed reqs: [list]. Decisions inherited: [count]."
   - Remind that P3's THINK must read DECISIONS.md first (no re-asking).
   - `gos commit ship` if not yet committed.

## Rules
- Never renumber phases; insert decimals for gap-closure (P3.1), like GSD.
- If drift is fundamental (vision changed), stop and run complete-milestone's retrospective early, then re-run new-project's breakdown.
