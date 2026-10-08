# Gap Classification & Closure Loop

## One-Truth-at-a-Time Presentation Script

Present each truth in its OWN message with this format:

```
─── Truth T-01: User can register ───

Expected: POST /api/v1/auth/register → 201 with {id, email}

Running verification:
$ curl -s -o /dev/null -w "%{http_code}" -X POST localhost:3000/api/v1/auth/register \
    -H 'Content-Type: application/json' \
    -d '{"email":"test@x.com","password":"Pass123!"}'
201

Result: ✅ PASS — HTTP 201 returned.

Does this match expectations? (yes / issue found)
```

→ STOP. Wait for user response. Never present T-02 in the same message.

### Anti-pattern (never do this)

```
T-01: register → ✅
T-02: login → ✅
T-03: protected route → ✅
All pass! Moving on.
```
Batch presentation. User rubber-stamps. No evidence shown. No stopping.

## Handling User Responses

| User says | Action |
|:---|:---|
| "yes" / "OK" / "good" | Mark truth verified + evidence in state.json. Move to next. |
| "issue" / "problem" / "wait" | Record gap with user's description. Classify below. Continue to next truth. |
| "skip" | Mark unverified. Note in state.json. Continue. |
| "that's wrong" | Don't argue. Record as gap. The truth definition may need updating. |

## Cold-Start Smoke Test

Check if the implementation has:

| Component | Test |
|:---|:---|
| Server entry (server.ts/app.ts) | kill instance → fresh start → health check returns 200 |
| DB migrations | run from scratch on clean DB → no errors |
| Config files | load without optional env vars → graceful failure |
| External services | unreachable → graceful degradation, not crash |

<Good>
```bash
kill $(lsof -ti:3000) 2>/dev/null; npm start &
sleep 3
curl -s localhost:3000/health
> {"status":"ok","uptime":"3.1s"}     ← EVIDENCE: cold start works
```
</Good>

## Gap Classification Decision Tree

```
Gap found
  │
  ├─ Core feature not working at all?
  │    ├─ Yes → Is it a design flaw?
  │    │    ├─ Yes → BLOCK → gos stage back think
  │    │    └─ No → MAJOR
  │    └─ No → continue
  │
  ├─ Affects a spec'd requirement (R-NN)?
  │    ├─ Yes → MAJOR
  │    └─ No → continue
  │
  ├─ Security issue? (always MAJOR, never minor)
  │    ├─ Yes → MAJOR
  │    └─ No → continue
  │
  └─ Edge case / cosmetic → MINOR
```

| Gap Type | Lv2 Action | Lv3+ Action |
|:---|:---|:---|
| **Minor** | Fix in BUILD → re-VERIFY | Fix in BUILD → re-VERIFY |
| **Major** | `gos stage back think` | `gos stage back plan` |
| **Block** | `gos stage back think` | `gos stage back think` |

## Closure Loop Limits

- **3 gap closure iterations** without convergence → escalate to user
- **5 total iterations** → consider Block (approach may be wrong)
- Each iteration: update `state.json.gaps[].status` from `open` → `fixed`
