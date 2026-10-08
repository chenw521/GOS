# Verify Report: [Task Name]

> **Date**: YYYY-MM-DD | **Level**: Lv___

## Gate Check

```bash
$ gos gate all
# paste output here
```

## Automated Checks

| Check | Command | Result | Evidence |
|:---|:---|:---|:---|
| lint | `[cmd]` | ✅/❌ | [output] |
| typecheck | `[cmd]` | ✅/❌ | [output] |
| tests | `[cmd]` | ✅/❌ | [N passed] |
| build | `[cmd]` | ✅/❌ | [output] |

## Observable Truths (verified one-by-one with user)

<!-- Present each truth sequentially. Never batch. -->

| Truth | Expected | Evidence | Status |
|:---|:---|:---|:---|
| T-01 | [expected] | [evidence] | ✅/❌ |
| T-02 | [expected] | [evidence] | ✅/❌ |

## Gap Classification (if any)

| Gap | Type | Action |
|:---|:---|:---|
| [desc] | Minor/Major/Block | BUILD/THINK/PLAN |

## Conclusion

- [ ] `gos gate all` exits 0
- [ ] All truths confirmed (one-by-one)
- [ ] No open gaps

**Result: ✅ ALL PASS → SHIP | ❌ GAPS → Gap Closure**
