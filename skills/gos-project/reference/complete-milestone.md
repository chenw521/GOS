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

4. **Milestone close** (the verb owns snapshots and the selective wipe):
   - Dry-run first: `gos milestone close --carry-parked` — inspect the five-class disposition report (kept: parked phases + their rows + pending phases; wiped: done-owned + null-phase + ghost/dropped rows).
   - Arm it: `gos approve milestone-close --reason "<why>"`, then `gos milestone close --carry-parked --yes`.
   - Dated snapshots land in `.gos/project/milestones/` (preclose.json + ROADMAP/REQUIREMENTS/DECISIONS views) and in the closing archive's `milestone-record/` — no manual `git mv` of views.

5. **REQUIREMENTS.md / DECISIONS.md reset**: the close wipe handles both — done-owned rows wipe with history; parked-owned rows survive in place. Views re-render from the post-close project.json.

6. **Retrospective** (3 questions, ≤5 bullets each — value is in reflecting, not volume):
   - What went well? / What was harder than expected? / What would we do differently?
   - Append to `.gos/project/RETROSPECTIVE.md` (create if missing). Cross-milestone patterns matter.

7. **Tag** (optional, git-side record): `git tag -a v0.1 -m "milestone: <name>"`.

8. **User gate**: show audit + stats + retro summary → "Milestone complete. Start next milestone (new-project mode) or stop here?"

## Rules
- Never batch destructive acts: dry-run → user inspects → approve → execute, one step at a time.
- Never delete view files by hand — `gos milestone close` is the only wipe path and it snapshots before wiping.
