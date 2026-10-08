---
name: gos-resume
description: Print resume summary for a fresh session
permissions:
   read: true
   write: true
   bash: true
---

<objective>
Print the cross-session resume summary — paste target for a fresh session continuing an interrupted task.
</objective>

<process>
Run `gos resume$ARGUMENTS` via bash. Read its output and act on the "Next:" hints — load the suggested skill and continue the flow.
</process>
