# Mode: complete-milestone

## When
All phases in ROADMAP.md are done (or user declares the milestone over).

## Flow

1. **Pre-close audit**:
   - `gos gate all` — must pass (especially `requirements`: every R-NN claimed AND shipped in a completed phase).
   - Unshipped requirements → user decides: defer explicitly (move to PROJECT.md "Future") or reopen a phase.

2. **Gather stats** (cheap, for the record):
   - `git log --oneline | wc -l` since milestone start; files changed: `git diff --stat <start>..HEAD | tail -1`.

3. **PROJECT.md full review** (three-section migration):
   - "What This Is" ← what actually shipped.
   - "Core Value" ← validated priorities.
   - "Requirements Evolution" ← milestone summary line.

4. **ROADMAP.md archive**:
   - `mkdir -p .gos/project/milestones && git mv .gos/project/ROADMAP.md .gos/project/milestones/v0.1-ROADMAP.md` (commit BEFORE delete-order: archive → commit → then write fresh empty ROADMAP for next milestone).

5. **REQUIREMENTS.md reset**: archive alongside ROADMAP; next milestone's new-project regenerates it.

6. **Retrospective** (3 questions, ≤5 bullets each — value is in reflecting, not volume):
   - What went well? / What was harder than expected? / What would we do differently?
   - Append to `.gos/project/RETROSPECTIVE.md` (create if missing). Cross-milestone patterns matter.

7. **Tag**: `git tag -a v0.1 -m "milestone: <name>"`.

8. **User gate**: show audit + stats + retro summary → "Milestone complete. Start next milestone (new-project mode) or stop here?"

## Rules
- Archive commit ordering matters: commit the archive BEFORE removing originals (GSD bug #2630 lesson).
- Never delete DECISIONS.md — it survives milestones (rolling, pruned, never reset).
