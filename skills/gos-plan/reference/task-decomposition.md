# Task Decomposition Patterns

## Sizing Rules

| Task Size | Duration | Action |
|:---|:---|:---|
| Too small (<5 min) | Trivial change | Merge with related task |
| Right (5-30 min) | One focused change | Keep as-is |
| Too big (>30 min) | Multi-concern | Split into 2-3 tasks |

## Decomposition Strategies

### Strategy A: By Layer (default for most features)
```
Data layer:   T1 (model + migration)
Logic layer:  T2 (service/business logic)
Interface:    T3 (route/controller/UI)
Tests:        T4 (integration tests)
```
Best when: feature touches multiple layers of the stack.

### Strategy B: By Feature Slice (for multi-feature phases)
```
T1 (auth: model + service + route + test)
T2 (profile: model + service + route + test)
T3 (settings: model + service + route + test)
```
Best when: features are independent and each is a vertical slice.

### Strategy C: By Risk (for uncertain/experimental features)
```
T1 (spike: prove the hardest technical risk)
T2 (foundation: models + config)
T3 (implementation: build on proven foundation)
T4 (polish: error handling + edge cases)
```
Best when: technical approach is unproven.

## Good vs Bad Decomposition

<Good>
```
T1: Create User model + password hashing (D-02, R-01)
  Files: src/models/User.ts, src/models/User.test.ts
  Read first: src/models/Base.ts
  Done when: grep "bcrypt" src/models/User.ts AND 4 tests pass
  Wave: 1

T2: Create DB migration for users table (D-01)
  Files: migrations/001_users.sql
  Read first: existing migrations in migrations/
  Done when: migration runs clean on empty DB
  Wave: 1 (parallel with T1)

T3: Create AuthService (D-03, R-01)
  Files: src/services/AuthService.ts, src/services/AuthService.test.ts
  Read first: src/models/User.ts (from T1)
  Done when: generateToken + verifyToken work, 5 tests pass
  Wave: 2 (depends on T1)
```
Each task: focused, specific files, clear done-when, dependencies mapped.
</Good>

<Bad>
```
T1: Do the backend stuff
T2: Do the frontend
T3: Tests
```
No files. No approach. No done-when. No D-NN coverage. No dependencies.
Executor has to reverse-engineer the entire plan.
</Bad>

## Common Anti-Patterns

| Anti-pattern | Why it fails | Fix |
|:---|:---|:---|
| **God task** ("implement auth") | 2-hour task touching 10 files | Split by concern: model, service, route, test |
| **Vague done-when** ("works correctly") | Can't verify programmatically | Use grep/test command as done-when |
| **Missing Read first** | Executor reads wrong files first | List the 1-3 files that contain relevant patterns |
| **Implicit dependency** ("T3 probably needs T1") | Parallel execution breaks | Make explicit: `Depends on: T1` |
| **Test after** ("write tests when done") | Tests never get written | Include test files in each task's Files |
