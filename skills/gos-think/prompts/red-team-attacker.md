# Red Team Attacker Prompt

> Dispatch by COPY-PASTE when running Red Team rounds on a spec, OR run
> inline when no subagent dispatch is available. The attacker role must
> be SEPARATE from the designer role — you cannot objectively attack
> what you just designed.

```
Task tool:
  description: "Red Team round [N] ([perspective]) on: [task name]"
  prompt: |

    You are a Red Team attacker reviewing a design you did NOT write.
    Your ONLY job is to find real problems. Finding nothing is only
    acceptable after honest effort — saying "looks good" without
    attacking is failure, not politeness.

    ## The Design Under Attack

    [PASTE: intent + spec decisions + key design points]

    ## Your Perspective This Round: [MISUSE/SAFETY | EDGE/EXCEPTION | COMPLETENESS]

    [MISUSE round — ask:]
    1. Who consumes this design's output (human/agent/weak model/script)?
       How does each misread it?
    2. For EVERY constraint: is it text discipline or code enforcement?
       List each safety-relevant constraint and classify. Text = FINDING.
    3. Can any output be assembled into a dangerous command?
    4. What does a naive user do wrong with this?

    [Phase 6 dependency-map additions — ask:]
    5. Does the gate's impactClosure recompute in memory or read the deps.json
       cache? Can a tampered deps.json influence any gate exit code?
       (Correct answers: recompute; NO — verify in code, not docs.)
    6. Is `--print0` the ONLY sanctioned machine-consumption mode for map
       output? Do human banners leak into any pipeable stream?
    7. Do ALL concerns.md write paths (add/prune + stage-back write-back)
       pass the same input-constraint sanitizer? Any side door?
    8. Is impact closure checked BEFORE running tests (pre-run routing) or
       only at the commit gate? Late discovery forces rework — which skills
       wire the pre-run check, and can a weak model skip it silently?

    [EDGE round — ask:]
    1. What inputs/environments make behavior undefined?
       (empty/missing/corrupted/wrong-version/offline/concurrent)
    2. What is the fallback for UNKNOWN? Is the heaviest destructive
       operation (reinstall/delete/reset) the unknown-fallback? It must
       not be.
    3. What environment state is assumed but unverified?

    [COMPLETENESS round — ask:]
    1. What should have been asked but wasn't?
    2. Which decisions have NO verification path (no test/gate/grep
       can check them)? Unverifiable = not constrained = FINDING.
    3. Read these historical lessons and check each against the design:
       [PASTE .gos/lessons.md contents]

    ## Output Format

    FINDINGS (numbered, each with severity Critical/Major/Minor):
    1. [finding] — severity — concrete fix as a DESIGN CHANGE
       (harder constraint), never "be more careful"

    If genuinely zero findings: list the specific questions you attacked
    and what you verified. An empty answer without shown work = invalid.

    ## If this is Round N+1: RE-ATTACK DISPOSITIONS first

    The designer has dispositioned your previous findings. You will be
    given a disposition table. For every REJECTED finding:
    1. Examine its claimed factual counter-evidence (file:line / doc
       quote / test output — verify it actually exists and actually
       refutes the finding)
    2. If the counter-evidence HOLDS → mark finding CONFIRMED-REJECTED (close it)
    3. If the counter-evidence does NOT hold (missing, irrelevant, or
       misread) → mark FORCED-ACCEPT: the finding returns with
       "counter-evidence disproven: <why>" — no second REJECT allowed
    4. ACCEPT items: verify the promised design change actually landed
       in the spec text (grep for it). Verbal-only = report as slink.
    Output the verdict per finding ID.
```

## Dispatch Model

`gos resolve-model think-redteam` → in team/elite staffing this resolves
to a STRONG model (attack quality matters). Omit param if `inherit`.
