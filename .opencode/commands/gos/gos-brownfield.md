---
name: gos-brownfield
description: Adopt an existing repo into GOS: /gos-brownfield [--json] or --print-agents-skeleton
argument-hint: "[--json] | [--print-agents-skeleton]"
permissions:
   read: true
   write: true
   bash: true
---

<objective>
Adopt an existing (brownfield) repository into GOS: report which GOS assets are live, missing, or inactive, and print numbered remediation steps. Read-mostly and lock-free — a brownfield repo has no `.gos` state yet. "brownfield" here means adopting an existing repo, distinct from the D-22 decision-import sense (where `gos init` detects handwritten decision files and suggests importing them).
</objective>

<process>
Run `gos brownfield$ARGUMENTS` via bash. Act on the remediation steps it prints: typically `gos setup --commitlint` to activate inactive assets, or `gos brownfield --print-agents-skeleton` for a starter AGENTS.md skeleton (stdout only, never written). For machine consumption use `gos brownfield --json`. Once the report is clean, start the first task the usual way (`gos init 3 "<intent>"`), then follow progress with `gos status` and `gos resume`.
</process>
