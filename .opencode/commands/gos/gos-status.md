---
name: gos-status
description: Full 3-layer status (project/phase/task)
permissions:
   read: true
   write: true
   bash: true
---

<objective>
Show full status: stage progress, decisions coverage, truths verification, requirements claims, open gaps.
</objective>

<process>
Run `gos status$ARGUMENTS` via bash. Read its output and act on the "Next:" hints — load the suggested skill and continue the flow.
</process>
