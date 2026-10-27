# Build Patterns Reference

## TDD Pattern (RED → GREEN → REFACTOR)

### RED: Write a failing test that describes the desired behavior

<Good>
```javascript
test('rejects empty email with 400', async () => {
  const res = await request(app)
    .post('/api/v1/auth/register')
    .send({ email: '', password: 'Pass123!' });
  expect(res.status).toBe(400);
  expect(res.body.error).toContain('email');
});
```
Tests a SPECIFIC behavior with a SPECIFIC assertion. If it fails, you
know exactly what's wrong.
</Good>

<Bad>
```javascript
test('register works', async () => {
  const res = await request(app).post('/api/v1/auth/register').send({...});
  expect(res.status).toBe(201);  // only tests happy path, no edge cases
});
```
Only tests one path. No edge cases. When it passes, you still don't know
if empty email is handled.
</Bad>

### Verify RED

```bash
npm test -- --testPathPattern=auth
# Expected: FAIL (function doesn't exist yet)
```

If the test PASSES at RED → your test is wrong (testing nothing).

### GREEN: Write MINIMUM code to pass

<Good>
```typescript
// src/routes/auth.ts
router.post('/register', async (req, res) => {
  const { email, password } = req.body;
  if (!email || email.trim() === '') {
    return res.status(400).json({ error: 'email is required' });
  }
  // ... rest of registration
});
```
Minimum code to pass the test. Not more, not less.
</Good>

<Bad>
```typescript
// Adding 50 lines of validation, logging, rate limiting, etc.
// before the test even passes. You're building ahead of your tests.
```
</Bad>

### REFACTOR: Improve quality without changing behavior
- Extract duplication
- Improve naming
- Run test again → still PASS

### TDD Anti-Rationalization

| Excuse | Reality |
|:---|:---|
| "I'll write tests after" | After = never. RED first. |
| "This is just a wrapper" | Wrappers have bugs. Test the interface. |
| "The test is harder than the code" | Signal: your design is wrong |
| "I need to see it work first" | That's what the test IS |

## Modifying Existing Code

<Good>
Reads `src/routes/users.ts` (the file being modified) AND
`src/routes/users.test.ts` (existing tests) BEFORE making changes.
Checks that existing tests still pass after modification.
</Good>

<Bad>
Opens the file, makes changes, runs tests → 5 tests fail → "weird, must
be flaky" → proceeds anyway.
</Bad>

## Systematic Debugging

```
Step 1: REPRODUCE
  Write a test that captures the bug. Confirm it fails.

Step 2: LOCATE
  Binary search / git bisect / read error messages CAREFULLY.
  Find ROOT CAUSE, not symptom.

Step 3: FIX
  Write regression test → fix root cause → run test.

Step 4: VERIFY
  Full test suite → check for similar bugs elsewhere.
```

## The 3-Fail Rule

> If you've tried to fix the same bug 3 times and it's still broken, **STOP**.
> The problem is architectural, not implementation.

1. Delete your fix attempts
2. Re-read the spec/plan to confirm understanding
3. Ask: "Is the approach fundamentally wrong?"
4. If yes → `gos stage back think` (fluid workflow)
5. If no → ask the user for help, don't keep guessing

<Good>
3rd attempt fails → STOP. "I've tried X, Y, Z. The issue might be
in the session management design, not the token code. Should we
revisit the approach?"
</Good>

<Bad>
4th, 5th, 6th attempt... each trying a slightly different patch.
Wasting context window and user patience on the wrong layer.
</Bad>

## Parallel Agent Dispatch

**When to dispatch:**
- Tasks are truly independent (no shared files, no shared state)
- Each task is non-trivial (5+ minutes of work)
- You have enough context for precise instructions

**Dispatch template:**

<Good>
```
Agent 1 instructions (fresh context, no assumptions):
 Task: - Create User model with bcrypt
  Files to create: src/models/User.ts, src/models/User.test.ts
  Read first: src/models/Base.ts (for class structure)
  Implement: User class extends BaseModel, passwordHash field,
    setPassword(plain) using bcrypt.hash(plain, 12),
    verifyPassword(plain) using bcrypt.compare
  Test: 4 tests - setPassword hashes, verifyPassword true/false,
    cost is 12, empty password rejected
  Do NOT touch: src/routes/*, src/services/*
```
</Good>

<Bad>
```
Agent 1: Do the user model stuff. You know, like the other models.
```
No files. No approach. No boundaries. Agent will guess and likely conflict.
</Bad>

## Wave Aggregation Protocol (mandatory after parallel waves)

When a wave executed with 2+ parallel agents, you MUST run these three
checks before declaring the wave complete:

### 1. Conflict scan
```bash
git status --porcelain   # any file modified by multiple agents?
```
- Same file touched by 2+ agents → manually merge-review now, not later.
- Adjacent files both changed → check imports/interfaces still align.

### 2. Interface docking
For each agent pair where one `provides` and another `requires`:
- Do the actual signatures match (names, args, return shape)?
- Run a smoke call: import A in B's context, call the joint path once.

### 3. Unified build verification
Each agent's self-test passing ≠ the whole works:
```bash
npm test        # full suite on the MERGED state (not per-agent)
gos gate all    # plus any project-level gates
```

Only after all three pass does the heartbeat report "wave complete".
