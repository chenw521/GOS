# Plan: [Task or Feature Name]

> **Date**: YYYY-MM-DD | **Based on spec**: .gos/spec.md

## Decision Inventory

<!-- Verify every D-NN from spec has a task (Decision Coverage Gate) -->

- [ ] D-nn: [decision] → T__
- [ ] D-nn: [decision] → T__

## Requirement Claims

<!-- Each R-NN must be claimed by ≥1 task. gos gate requirements checks at Lv4. -->

- [ ] R-nn: [requirement] → T__
- [ ] R-nn: [requirement] → T__

## Execution Waves

### Wave 1 (no dependencies, parallel)

#### Tn: [Task name]
- **Covers**: D-nn, R-nn
- **Files**: [which files]
- **Read first**: [prerequisite files]
- **Done when**: [grep-verifiable criteria]
- **Depends on**: none

#### Tn: [Task name]
- **Covers**: D-nn
- **Files**: [which files]
- **Read first**: [prerequisite files]
- **Done when**: [completion criteria]
- **Depends on**: none

### Wave 2 (depends on Wave 1)

#### Tn: [Task name]
- **Covers**: D-nn, R-nn
- **Depends on**: T1, T2

## Observable Truths

<!-- For VERIFY stage: what can the user observe when this works? -->

### T-01: [Observable behavior]
- **Expected**: [what should happen]
- **Verify**: [command or test]

### T-02: [Observable behavior]
- **Expected**: [what should happen]
- **Verify**: [command or test]

## Risks
- [Risk n]: [Mitigation]
