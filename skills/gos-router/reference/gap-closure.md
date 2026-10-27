# Gap Closure Decision Tree

Detailed gap classification for gos-router Step 5 and gos-verify Step 4.

## Classification Decision Tree

```
Gap found in VERIFY
  │
  ├─ Is the core feature working at all?
  │    ├─ No → Is it a design flaw?
  │    │    ├─ Yes → BLOCK → return to THINK (Lv2/Lv3+)
  │    │    └─ No → MAJOR → return to PLAN (Lv3+) or THINK (Lv2)
  │    └─ Yes → continue
  │
  ├─ Does it affect the spec's stated goals?
  │    ├─ Yes → MAJOR
  │    └─ No → continue
  │
  ├─ Is it a security issue?
  │    ├─ Yes → MAJOR (never minor)
  │    └─ No → continue
  │
  └─ It's an edge case or polish → MINOR → fix in BUILD
```

## Level-Specific Loop Destinations (B2 Fix)

|:---|:---|:---|:---|
| **Minor** | Fix directly | Fix in BUILD | Fix in BUILD |
| **Major** | Upgrade to Lv2 → THINK | Return to **THINK** | Return to **PLAN** (add gap-closure tasks) |
| **Block** | Return to THINK | Return to **THINK** | Return to **THINK** (re-examine) |

**Key insight**: Lv2 has no PLAN stage, so major gaps go back to THINK, not PLAN.

## Gap Records in state.json

```json
{
  "gaps": [
    {
      "id": "G-01",
      "type": "minor",
      "description": "Missing edge case: empty input",
      "truth_affected": "T-02",
      "action": "BUILD",
      "status": "open"
    }
  ]
}
```

## Gap Closure Loop Limits

- After **3 gap closure iterations** without convergence → escalate to user
- After **5 total iterations** → consider Block (fundamental approach may be wrong)
- Each iteration updates state.json `gaps[].status` from `open` → `fixed`
