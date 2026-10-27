# Thinking Models for Plan Quality

Run these BEFORE presenting the plan to the user. Each takes 1-2 minutes.

## 1. Pre-Mortem Analysis

**Question**: "Assume this plan was executed and it FAILED. What are the
3 most likely reasons?"

**Steps**:
1. List 3 failure scenarios (be specific to THIS plan, not generic)
2. For each: can a task or constraint mitigate it?
3. If yes → add mitigation task or note in plan
4. If no → add to Risks section with "accepted risk" note

<Good>
"Failure 1: bcrypt slows down registration under load.
Mitigation: add benchmark test in (max 100ms per hash)."

"Failure 2: migration conflicts with existing users table.
Mitigation: reads existing schema first, uses IF NOT EXISTS."
</Good>

<Bad>
"Failure 1: something goes wrong." — Not specific. Not actionable.
</Bad>

## 2. MECE Decomposition Check

**Question**: "Are tasks Mutually Exclusive and Collectively Exhaustive?"

**Steps**:
1. **Mutually Exclusive**: No two tasks modify the same code section
   - If overlap → one task will clobber the other's changes
   - Fix: merge overlapping tasks or clearly partition the file
2. **Collectively Exhaustive**: Together they cover the entire spec
   - Run `gos gate coverage` — every D-NN has a task
   - Check R-NN coverage too (Lv4)

## 3. Constraint Analysis

**Question**: "What's the hardest constraint? Is it addressed early enough?"

**Steps**:
1. Identify the hardest technical constraint (performance, compatibility,
   external API, legacy code integration)
2. Check: is there a task addressing it in Wave 1-2?
3. If it's in the LAST wave → move it earlier
   - Rationale: if the hardest thing fails, you want to know BEFORE doing
     all the easy work

<Good>
"Hardest constraint: external payment API has 2s timeout.
 includes a timeout test. If it fails, we pivot before building UI."
</Good>

## 4. Reversibility Test

**Question**: "Which decisions are reversible vs irreversible?"

**Steps**:
1. For each task: if we do it wrong, how expensive is undo?
2. **Reversible** (code change, config): less planning, just do
3. **Irreversible** (DB migration, API published, data transform):
   more planning, double-check approach
4. Flag irreversible tasks with `[IRREVERSIBLE]` in the plan

## 5. Curse of Knowledge Counter

**Question**: "Pretend you've never seen this codebase. Re-read each task."

**Steps**:
1. For each task, check: does `Read first` give enough context?
2. Would a new developer understand the `Approach` without asking questions?
3. If not → add more detail to `Read first` or `Approach`

<Good>
"Read first: src/models/Base.ts (lines 1-30 for class structure,
lines 45-60 for validation pattern)"
</Good>

## 6. Base Rate Neglect Counter

**Question**: "Am I overweighting LOW-confidence research suggestions?"

**Steps**:
1. Identify any task based on unproven assumptions
   ("library X should support Y")
2. Mark with `[UNVERIFIED]` in the plan
3. The task should include a quick verification step before committing
   to the approach
