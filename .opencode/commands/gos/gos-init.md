---
name: gos-init
description: Start a task: /gos-init <level> "<intent>" or --project for Lv4
argument-hint: "<level> \"<intent>\" | --project"
permissions:
   read: true
   write: true
   bash: true
---

<objective>
Initialize a GOS task (creates .gos/state.json, records R-01 from intent). With --project, creates the Lv4 four-file set.
</objective>

<process>
Run `gos init$ARGUMENTS` via bash. Read its output and act on the "Next:" hints — load the suggested skill and continue the flow.
</process>
