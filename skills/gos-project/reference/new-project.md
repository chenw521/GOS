# Mode: new-project

## When
Lv4 task and `.gos/project/PROJECT.md` does not exist.

## Flow

1. **Run** `gos init 4 "<one-line vision>" --project` — creates state + four-file skeleton.

2. **Deep questioning** (one question per message, from gos-think Iron Law #2):
   - "What are we building?" → refine the vision sentence.
   - "Who is it for? What does success look like in 3 months?"
   - Surface requirements one by one. Each user commitment = one R-NN line
     appended to `.gos/project/REQUIREMENTS.md`:
 `| | user auth with JWT | |`
   - Scope creep → defer explicitly (Deferred section in PROJECT.md), never silently.

3. **Milestone + phase breakdown** (2-6 phases per milestone):
   - Fill ROADMAP.md: `| P1 | foundation: models + migrations | pending |`
 - Each phase claims requirements: REQUIREMENTS.md ` → P1`.
   - **Hard rule**: every R-NN must be claimed by some phase (`gos gate requirements` enforces).

4. **Seed DECISIONS.md** with any decisions already made during this dialogue
 (format: `- : monorepo over polyrepo — user chose`).

5. **User approval gate**: show ROADMAP + REQUIREMENTS summary.
   > "Project initialized: [N] requirements → [M] phases. Approve to start Phase 1?"

6. On approval: `gos commit intent`, then enter Phase 1 via gos-think (Lv3 flow).

## Rules
- Don't over-plan phase internals here — phases plan themselves (gos-plan).
- If vision is unclear after ~5 questions, propose 2-3 alternative visions (options + trade-offs), let user pick.
- RECORD as you go: every R-NN/D-NN goes into files immediately (crash recovery).
