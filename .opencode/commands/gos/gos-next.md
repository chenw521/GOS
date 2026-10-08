---
name: gos-next
description: Guided next actions for the current stage
permissions:
   read: true
   write: true
   bash: true
---

<objective>
Show structured next-actions for the current stage — what to do right now and which skill to load.
</objective>

<process>
Run `gos next$ARGUMENTS` via bash. Read its output and act on the "Next:" hints — load the suggested skill and continue the flow.
</process>
