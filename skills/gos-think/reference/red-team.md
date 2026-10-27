# Red Team Adversarial Self-Review Protocol

## Why This Exists

The doctor-command incident (2026-08-14): the AI's initial design had a
"soft whitelist" — a TEXT rule saying "only output GOS commands." It took
the user challenging 3 times before the constraint became CODE (hardcoded
frozen table + fail-closed exit guard + test assertions). If the user
hadn't pushed back, the weak version would have shipped.

**Lesson: user pushback is not a mechanism. Self-challenge must be.**

## Dispatch Rule (revised — heterogeneous by DEFAULT)

> **Default: DISPATCH the attacker** using `prompts/red-team-attacker.md`
> with `gos resolve-model think-redteam` (in team/elite staffing this
> resolves to a DIFFERENT/stonger model). Inline self-run is the
> FALLBACK for environments without subagent dispatch.
>
> **If you must run inline (same model):** announce explicitly —
> "Red Team running in DEGRADED mode (self-attack). Shared-prior blind
> spots cannot be caught this round." Self-attack finds random errors,
> not consensus errors — the model's own blind spots survive it.

## Attack Scope (revised — spec AND plan)

| Phase | Round | Attack surface |
|:---|:---|:---|
| THINK (after spec self-review) | R1 misuse / R2 edge / R3 completeness | the SPEC's decisions |
| PLAN (before user confirmation, Lv3+) | R4 plan-attack | wave dependency errors, interface docking gaps (A provides ≠ B requires), untestable done-when, missing aggregation risk in parallel waves |

Round 4 reuses the same attacker prompt with the plan as material — its
three questions map to the aggregation protocol's checks, catching
design-level parallelism risks BEFORE agents collide in BUILD.

## Level-Based Mandatory Scope

| Level | Rounds | Perspectives |
|:---|:---|:---|
| Lv0-1 | 1 | Misuse/Safety only |
| Lv2-3 | 3 | Misuse → Edge/Exception → Completeness |
| Lv4 | 3+ | Same 3, plus per-milestone in evolve mode |

## Round 1 — Misuse/Safety Perspective

Attack questions (ask yourself, answer honestly):

1. **Who consumes this design's output?** A human? An AI agent? A weak
   model? A script? What does each misread?
2. **Is every constraint TEXT discipline or CODE enforcement?**
   - Text: "only output safe commands" → a weak model CAN violate it
   - Code: frozen lookup table + fail-closed guard → it CANNOT
   - **Any constraint whose violation causes real harm MUST be code.**
3. **Can any output be assembled into a dangerous command?**
   - Paths interpolated into shell strings? User-copied partial commands?
   - Fix advice that says "delete X" instead of running a safe subcommand?
4. **What does this look like to a naive user?** Would they paste
   something harmful? Would they disable something critical?

**Output of the round:** findings list → each finding's fix must be a
DESIGN change (harder constraint), not a promise (be more careful).

## Round 2 — Edge/Exception Perspective

1. **What inputs/environments make behavior undefined?**
   (empty, missing, corrupted, wrong-version, offline, concurrent)
2. **What is the fallback for the UNKNOWN case?**
   - The heaviest destructive operations (reinstall, delete, reset) must
     NEVER be the unknown-fallback. Unknown → collect info & report.
3. **Does anything depend on environment state I haven't verified?**
   (PATH, versions, permissions, platform)

## Round 3 — Completeness Perspective

1. **What should I have asked but didn't?** Re-scan gray areas not selected.
2. **Is every D-NN constraint verifiable?** How? By test? By gate? By grep?
   - A constraint with no verification path = not actually constrained.
3. **Read `.gos/lessons.md` — has this class of problem bitten before?**
   Historical lessons are pre-loaded attack vectors.

## Findings Disposition Protocol (anti-slink / anti-sophistry)

After Red Team returns findings, the designer model MUST fill a
disposition table — free-form responses are forbidden:

| Finding | Disposition (one of 4, no blanks) | Evidence |
|:---|:---|:---|
| | ACCEPT → design change X | new spec section (grep-able) |
| | ACCEPT-PARTIAL → change Y | spec edit |
| | REJECT → factual counter-evidence required | code line / doc quote |
| | DEFER → to DI-n | Deferred Ideas entry |

Hard rules:
- **REJECT requires FACTS** (file:line, doc quote, test output) — opinion-level
  rebuttal ("I think it's fine") is invalid and must be re-dispositioned
- **ACCEPT must land as a design change** in the spec — verbal "will be
  careful" does not count
- Dispositions are recorded in `state.redteam_rounds[].dispositions` (auditable)
- **Round N+1 re-attacks REJECTED items first** — the attacker verifies
  whether the counter-evidence actually holds. If the attacker disproves
  the counter-evidence, that finding becomes FORCED-ACCEPT (no second REJECT)
- Three consecutive FORCED-ACCEPTs in one session → stop, report to user:
  the designer model is rationalizing; user judgment required

Why: the same-session model being "beaten" tends to either capitulate
mechanically or deflect with sophistry. The table removes both paths —
every finding gets a structured, verifiable outcome.

## Convergence Rules

- A round with ZERO new findings → converged → proceed to user approval
- Findings → fix design → next round (with the FIXED design)
- 3 rounds, still findings → STOP. Present to user:
  ```
  Red Team could not fully resolve:
  - [issue] — my proposed mitigation: [...], residual risk: [...]
  ```
  Never silently swallow known issues.

## State Tracking

Record rounds in state.json (crash-recoverable, auditable):
```json
"redteam_rounds": [
  {"round": 1, "perspective": "misuse", "findings": 2, "fixed": 2},
  {"round": 2, "perspective": "edge", "findings": 0, "converged": true}
]
```

## Worked Example (from the doctor incident)

```
Initial design: doctor outputs fix suggestions from a soft whitelist rule.

Red Team Round 1 (misuse):
  Q: Who consumes the output? → Often an AI agent relaying to user.
  Q: Text or code? → TEXT. A weak model can violate it.
  Q: Assemblable into danger? → Yes: path + rm pattern possible.
  FINDING: constraint must be code.
  FIX (design change): DOCTOR_FIXES frozen table + whitelist regex
  guard that fails CLOSED (exit 2, no output) + test assertion that
  greps for rm/unlink/sudo = 0 occurrences.

Round 2 (edge):
  Q: Unknown failure fallback? → was implicit "reinstall".
  FINDING: reinstall is too heavy for unknown.
  FIX: unknown → "report issue with doctor output"; state that
  .gos/ task data survives reinstall (verified fact, reduces fear).

Round 3 (completeness):
  Q: Verifiable constraints? → yes, each fix line matches regex, tested.
  Zero new findings → converged.
```

## Cross-Task Evolution (lessons.md)

When VERIFY finds a gap, or user pushback exposes a design blind spot,
gos-ship records one line to `.gos/lessons.md`:

```
- [2026-08-14] doctor fix-suggestions: soft text whitelist survived
  self-review; only hardened after 3 user challenges. LESSON: any
  constraint on user-facing command output must be CODE-level (frozen
  table + fail-closed guard), Red Team round 1 must ask this.
```

Every future Red Team round 3 reads this file first — yesterday's bite
becomes today's checklist item.
