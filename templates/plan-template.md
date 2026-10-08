# Plan: [Task/Feature Name]

> **Date**: YYYY-MM-DD | **Based on spec**: .gos/spec.md

## Decision Inventory

<!-- Verify every D-NN from spec has a task (Decision Coverage Gate) -->

- [ ] D-01: [decision] → T__
- [ ] D-02: [decision] → T__

## Requirement Claims

<!-- Each R-NN must be claimed by ≥1 task. gos gate requirements checks at Lv4. -->

- [ ] R-01: [requirement] → T__
- [ ] R-02: [requirement] → T__

## Execution Waves

### Wave 1 (no dependencies, parallel)

#### T1: [Task name]
- **Covers**: D-01, R-01
- **Files**: [which files]
- **Read first**: [prerequisite files]
- **Done when**: [grep-verifiable criteria]
- **Depends on**: none

#### T2: [Task name]
- **Covers**: D-02
- **Files**: [which files]
- **Read first**: [prerequisite files]
- **Done when**: [completion criteria]
- **Depends on**: none

### Wave 2 (depends on Wave 1)

#### T3: [Task name]
- **Covers**: D-03, R-02
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
- [Risk 1]: [Mitigation]
