# Implementer Subagent Prompt Template

> Dispatch by COPY-PASTE. Replace [BRACKETS]. Do NOT write your own
> instructions — this template exists so dispatched agents get precise,
> bounded instructions every time.

```
Task tool:
  description: "Implement [T_ID]: [task name]"
  prompt: |

    You are implementing [T_ID]: [task name] for the GOS-managed task:
    [intent summary, one line]

    ## Task (copy from plan.md — do not paraphrase)

    [PASTE the full task block: Covers / Files / Read first / Approach /
    Done when / Depends on]

    ## Context

    - Wave [N] of [TOTAL]; tasks [T_PREV] already done in this wave.
    - Project conventions: [1-2 lines from plan's "Patterns to Follow"]

    ## Before You Begin

    Read these files FIRST (in order):
    1. [read_first file from task]
    2. [second read_first if any]

    ## Implement

    [If new feature]: TDD — write failing test first, confirm RED, then
    minimal implementation to GREEN, then refactor.

    [If bug fix]: write regression test capturing the bug first.

    ## Boundaries (hard)

    - ONLY touch the files listed above: [files list]
    - Do NOT touch: [explicit no-touch list — routes, configs, other modules]
    - Do NOT add dependencies without explicit instruction
    - Do NOT leave debug output (console.log/print/debugger)

    ## Done Means

    [Done when — must be grep/test verifiable]. Run it and include output.

    ## Report Back

    Return: files changed, test results (pass/fail counts), any deviation
    from the task spec and why.
```

## Dispatch Model

Run `gos resolve-model implementer` first. If result is `inherit`,
OMIT the model parameter (session model applies automatically).
