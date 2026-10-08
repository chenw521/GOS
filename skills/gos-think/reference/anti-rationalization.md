# Anti-Rationalization & Red Flags for gos-think

## Rationalization Table

| Excuse | Reality |
|:---|:---|
| "This is simple enough to skip the spec" | Simple features still have edge cases; 5 min of spec saves 1 hr of rework |
| "I'll explore options while coding" | Coding before deciding leads to sunk-cost attachment to first approach |
| "The user wants speed, not documents" | The user wants results; a spec prevents building the wrong thing fast |
| "I don't need to explore the codebase, I know it" | Codebases change; assumptions are the #1 source of integration bugs |
| "Gray areas can be decided during implementation" | Implementation-time decisions are rushed, undocumented, and often wrong |
| "Truths can be defined during VERIFY" | VERIFY needs truths to exist BEFORE implementation; no truths = no verification |
| "Lv2 doesn't need truths" | Even Lv2 needs informal truths — otherwise VERIFY has nothing to check |

## Red Flags — STOP If You Notice These

| Thought | Correct Action |
|:---|:---|
| "I'll just write a quick spec without exploring options" | Present at least 2 approaches |
| "The user didn't mention X, so it's not needed" | Ask about gray areas explicitly |
| "I can start coding while waiting for spec approval" | No. HARD GATE. Wait. |
| "This decision is obvious, no need for a D-NN" | If it's obvious, documenting it takes 10 seconds |
| "I'll add that feature since we're already here" | Scope guardrail → add to Deferred Ideas |
| "Truths aren't needed for this small feature" | Even small features have observable behaviors |
