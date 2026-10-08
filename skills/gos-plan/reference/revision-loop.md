# Revision Loop Protocol

## When to Engage

After `gos gate coverage` exits 1 (uncovered D-NNs found), OR after
self-review finds MECE violations, OR Pre-Mortem identifies a critical gap.

## Loop Structure (max 3 iterations)

### Iteration 1: Direct Fix

**Strategy**: Add missing tasks for uncovered D-NNs.

1. For each uncovered D-NN:
   - Can it be covered by extending an existing task? → add `Covers: D-NN`
   - Does it need a new task? → create one with proper format
2. Re-run `gos gate coverage`
3. Pass? → Done. Fail? → Iteration 2.

<Good>
"D-05 (rate limiting) uncovered → extend T4 (middleware) to include
rate limiting logic, add Covers: D-05 to T4."
</Good>

<Bad>
"D-05 uncovered → I'll handle it during BUILD" (deferred silently)
</Bad>

### Iteration 2: Strategy Change

**Strategy**: Try a different decomposition angle.

If Iteration 1's direct fix didn't resolve everything, the problem might
be structural. Try:
- Switch from by-layer to by-feature-slice decomposition
- Or: merge two conflicting tasks, then split differently
- Or: check if the D-NN is actually two decisions masquerading as one

1. Restructure affected tasks
2. Re-run `gos gate coverage`
3. Pass? → Done. Fail? → Iteration 3.

### Iteration 3: Final Attempt + Stall Detection

**Strategy**: Last aggressive restructuring.

**Stall check**: Compare issue count with Iteration 2.
- If issue count DECREASED → one more attempt allowed
- If issue count SAME or INCREASED → STALL → go to User Decision

After this iteration, if still failing → STALL → User Decision.

## User Decision on Stall

Present to user:

```
Revision Loop stalled after 3 iterations.

Unresolved gaps:
- D-05: rate limiting — conflicts with D-02 (session design)
- D-08: audit logging — no clear integration point

Options:
1. Re-plan: completely different approach (back to Step 3)
2. Defer: mark D-05/D-08 as deferred, add to spec's Deferred Ideas
3. Guidance: you suggest how to handle these
4. Proceed: accept gaps, handle adaptively during BUILD
```

**STOP and wait.** Record user's choice in state.json:
```json
{"revision_history": [
  {"iter": 1, "issues": 3, "fixed": 2},
  {"iter": 2, "issues": 1, "fixed": 0, "strategy": "by-feature"},
  {"iter": 3, "issues": 1, "stalled": true, "user_decision": "defer D-05"}
]}
```

## Why This Matters

For small tasks (Lv2, 3-5 decisions), a single plan pass is usually enough.
For complex tasks (Lv3 hard, Lv4), a single pass WILL have gaps. The
Revision Loop is the structural defense against "plan looks complete but isn't."

## Weak Model Mitigation

If the model can't self-detect issues:
- After Iteration 1, explicitly ask: "Does every D-NN have a Covers tag in plan.md?"
- If the model can't answer confidently → skip to User Decision
- The user's judgment replaces the model's self-review capability
- `gos gate coverage` is the objective check — it doesn't rely on model insight
