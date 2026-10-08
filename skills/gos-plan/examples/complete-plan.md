# Plan: auth module (COMPLETE EXAMPLE)

> This is a real, complete plan — copy this structure. Every task has
> Covers/Files/Read-first/Done-when/Depends. Coverage adds up to 100%.

> **Date**: 2026-08-14 | **Based on spec**: the spec path from `gos context plan` (artifact_paths.spec)

## Decision Inventory

- [x] D-01: JWT tokens (24h + refresh) → T1, T3
- [x] D-02: bcrypt cost 12 → T1
- [x] D-03: refresh token rotation → T3
- [x] D-04: structured JSON errors → T3

## Requirement Claims

- [x] R-01: user authentication → T1, T3, T5
- [x] R-02: password reset → T6

## Patterns to Follow

- Routes: src/routes/v1/[resource].ts (template: src/routes/v1/users.ts)
- Tests: co-located *.test.ts, describe/it pattern
- Errors: throw new AppError(code, message) — never raw strings

## Execution Waves

### Wave 1 (parallel, no deps)

#### T1: User model with bcrypt password hashing
- **Covers**: D-02, R-01
- **Files**: src/models/User.ts, src/models/User.test.ts
- **Read first**: src/models/Base.ts, src/config/index.ts
- **Approach**: User extends BaseModel; passwordHash field set via
  setPassword(plain) using bcrypt.hash(plain, 12); verifyPassword(plain)
  via bcrypt.compare. Reject empty/multi-byte-truncated passwords.
- **Done when**: `grep "bcrypt.hash(plain, 12)" src/models/User.ts` matches
  AND `npm test -- --testPathPattern=User` passes with ≥4 tests
- **Depends on**: none

#### T2: DB migration for users table
- **Covers**: D-01 (storage prerequisite)
- **Files**: migrations/001_users.sql
- **Read first**: existing migrations in migrations/
- **Approach**: id UUID PK, email UNIQUE NOT NULL, password_hash NOT NULL,
  created_at/updated_at. Use IF NOT EXISTS (idempotent re-run).
- **Done when**: migration applies clean on empty DB twice without error
- **Depends on**: none

### Wave 2 (depends on Wave 1)

#### T3: AuthService (JWT issue/verify/refresh rotation)
- **Covers**: D-01, D-03, D-04, R-01
- **Files**: src/services/AuthService.ts, src/services/AuthService.test.ts
- **Read first**: src/models/User.ts (from T1), src/config/index.ts
- **Approach**: issueToken(user) → JWT 24h; refreshToken flow rotates
  (old refresh invalidated on use); errors as AppError('AUTH_xxx', msg).
- **Done when**: 5 tests pass — issue/verify/expired/refresh-rotates/
  refresh-reuse-rejected AND `grep "AppError" src/services/AuthService.ts` matches
- **Depends on**: T1, T2

### Wave 3 (depends on Wave 2)

#### T4: Auth middleware (route protection)
- **Covers**: D-01
- **Files**: src/middleware/auth.ts, src/middleware/auth.test.ts
- **Read first**: src/services/AuthService.ts
- **Approach**: requireAuth reads Bearer token, verifies, attaches
  req.user; 401 with structured error when missing/expired.
- **Done when**: middleware test covers valid/missing/expired (3 cases)
- **Depends on**: T3

#### T5: Auth routes (register/login/refresh)
- **Covers**: R-01, D-04
- **Files**: src/routes/v1/auth.ts, src/routes/v1/auth.test.ts
- **Read first**: src/routes/v1/users.ts (pattern), src/services/AuthService.ts
- **Approach**: POST /register, /login, /refresh. Validation errors → 400
  structured. Wire requireAuth-protected sample route.
- **Done when**: integration tests: register 201, duplicate 409, login 200
  +token, refresh 200 + old-refresh-rejected 401
- **Depends on**: T3, T4

### Wave 4 (depends on Wave 3)

#### T6: Password reset flow
- **Covers**: R-02
- **Files**: src/services/ResetService.ts, src/routes/v1/reset.ts, tests
- **Read first**: src/services/AuthService.ts
- **Approach**: reset token (single-use, 1h TTL) issued to verified email;
  consume endpoint invalidates token + rehashes password.
- **Done when**: tests: request-issues-token, consume-resets-password,
  reuse-rejected, expired-rejected
- **Depends on**: T5

## Observable Truths

### T-01: New user can register
- **Expected**: POST /api/v1/auth/register → 201, body has id+email
- **Verify**: `curl -s -o /dev/null -w "%{http_code}" -X POST localhost:3000/api/v1/auth/register -H 'Content-Type: application/json' -d '{"email":"t@x.com","password":"Pass123!"}'` → 201

### T-02: Duplicate email rejected
- **Expected**: same register twice → 409 structured error
- **Verify**: run register twice, second returns 409

### T-03: Login returns JWT; refresh rotates
- **Expected**: /login → 200 {token, refreshToken}; /refresh with
  refreshToken → 200 new pair; reusing old refreshToken → 401
- **Verify**: scripted curl sequence, assert codes 200/200/401

### T-04: Protected route rejects anonymous
- **Expected**: GET /api/v1/me without token → 401
- **Verify**: `curl -s -o /dev/null -w "%{http_code}" localhost:3000/api/v1/me` → 401

## Risks

- bcrypt cost 12 slow in CI → allow BCRYPT_COST env override in tests only
- JWT secret sourcing → config/index.ts env required, fail fast on missing
