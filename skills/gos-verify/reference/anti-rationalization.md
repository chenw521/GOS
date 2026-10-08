# Anti-Rationalization & Red Flags for gos-verify

## Rationalization Table

| Excuse | Reality |
|:---|:---|
| "The tests should pass" | "Should" is not evidence. RUN THEM. |
| "I reviewed the code, it looks correct" | Code review is not execution. Run it. |
| "It worked in my head" | Heads don't have compilers. Run it. |
| "I'm confident this is correct" | Confidence is not evidence. Show the output. |
| "The gap is minor, let me skip it" | Minor gaps accumulate. Log or fix. |
| "I'll verify after SHIP" | SHIP means done. Verify BEFORE or it's not done. |
| "Cold-start test isn't needed for this" | If there's a server/db → it IS needed |
| "Gap Closure will take too long" | Shipping broken takes longer |
| "Lv2 doesn't need truth verification" | Lv2 truths are informal but still must be checked |
| "No plan.md means no truths to verify" | Truths are in state.json, not plan.md |

## Red Flags — STOP If You Notice These

| Thought | Correct Action |
|:---|:---|
| "I'll mark it PASS without running checks" | That's lying. Run the checks. |
| "The output is too long to show" | Show the summary line (passed/failed count) |
| "This truth can't be tested automatically" | Test it manually and show what you did |
| "Gap Closure Loop is taking too many iterations" | After 3 loops, escalate to user |
| "The user wants to ship, I'll skip cold-start" | Cold-start failures are the worst bugs. Do it. |
| "Truths from state.json might be stale" | They were set by THINK/PLAN; trust the chain |
