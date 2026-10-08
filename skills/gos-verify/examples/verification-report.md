# Verification Report: auth module (COMPLETE EXAMPLE)

> Copy this structure. Evidence = actual command output pasted, never
> "should work". Truths presented ONE AT A TIME to the user with
> evidence, user confirms each before the next.

> **Date**: 2026-08-14 | **Level**: Lv3

## Step 1: Automated Checks (evidence shown)

```
$ npm run lint
> ✓ No errors (0 warnings)

$ npm test
> ✓ 23 passed, 0 failed (3.1s)

$ npm run build
> ✓ Build successful (dist/ 41 files)
```

## Step 2: Observable Truths — one at a time

### ─── Truth T-01: New user can register ───

Expected: POST /api/v1/auth/register → 201, body has id+email

```
$ curl -s -w "\nHTTP:%{http_code}" -X POST localhost:3000/api/v1/auth/register \
    -H 'Content-Type: application/json' \
    -d '{"email":"t@x.com","password":"Pass123!"}'
{"id":"a1b2...","email":"t@x.com"}
HTTP:201
```

Result: ✅ PASS — 201 with id+email.

> User: "yes" → recorded, evidence: "curl 201 + id/email body"

### ─── Truth T-02: Duplicate email rejected ───

Expected: second register with same email → 409 structured error

```
$ curl -s -w "\nHTTP:%{http_code}" -X POST localhost:3000/api/v1/auth/register \
    -H 'Content-Type: application/json' -d '{"email":"t@x.com","password":"Pass123!"}'
{"error":{"code":"AUTH_DUPLICATE","message":"email already registered"}}
HTTP:409
```

Result: ✅ PASS — 409 with structured error body.

> User: "yes" → recorded

### ─── Truth T-03: Login returns JWT; refresh rotates; reuse rejected ───

Expected: login 200 {token, refreshToken}; refresh 200 new pair; old refresh reuse 401

```
$ TOKENS=$(curl -s -X POST localhost:3000/api/v1/auth/login -H 'Content-Type: application/json' -d '{"email":"t@x.com","password":"Pass123!"}')
$ echo "$TOKENS" | jq -r '.token' | head -c 20
eyJhbGciOiJIUzI1NiIs...          ← 200 with JWT
$ OLD_RT=$(echo "$TOKENS" | jq -r '.refreshToken')
$ NEW=$(curl -s -X POST localhost:3000/api/v1/auth/refresh -d "{\"refreshToken\":\"$OLD_RT\"}")
$ echo "$NEW" | jq -r '.refreshToken' | head -c 10
9f8e7d6c5b                        ← rotated: new pair issued
$ curl -s -o /dev/null -w "%{http_code}" -X POST localhost:3000/api/v1/auth/refresh -d "{\"refreshToken\":\"$OLD_RT\"}"
401                               ← reuse rejected
```

Result: ✅ PASS — 200/rotated/401 sequence complete.

> User: "yes" → recorded

### ─── Truth T-04: Protected route rejects anonymous ───

```
$ curl -s -o /dev/null -w "%{http_code}" localhost:3000/api/v1/me
401
```

Result: ✅ PASS.

> User: "yes" → recorded

## Step 3: Cold-Start (server present)

```
$ kill $(lsof -ti:3000) 2>/dev/null; npm start & sleep 3
$ curl -s localhost:3000/health
{"status":"ok","uptime":"3.1s"}      ← cold start works
$ npm run migrate -- --from-scratch
> ✓ 1 migration applied clean
```

✅ PASS.

## Step 4: Gap Classification

One truth initially failed T-04 (middleware order bug) → Minor (edge
case, core working) → fixed in BUILD → re-verified above.

| Gap | Type | Action | Status |
|:---|:---|:---|:---|
| T-04 401 before fix (middleware registered after routes) | Minor | BUILD fix + regression test | fixed |

## Step 5: Final Gate

```
$ gos gate all
✓ coverage: 4/4 decisions covered (4 via plan.md scan)
✓ truths: 4/4 verified with evidence
- requirements: Lv3 implicit, skip
✓ ALL GATES PASSED
```

**Result: ✅ ALL PASS → SHIP**
