# Review Checklists

## Phase 1: Spec Compliance

### Decision Coverage Audit
| D-NN | Decision | Implemented? | Evidence |
|:---|:---|:---|:---|

### Scope Boundary Check
| Deferred Item | Implemented? (should be No) | Action |
|:---|:---|:---|
| DI-1 | No ✓ / Yes (creep!) | — / Remove |

## Phase 2: Code Quality

### Functional Correctness
- [ ] Edge cases handled (null, empty, extreme)
- [ ] Error handling complete
- [ ] No silent failures

### Code Quality
- [ ] DRY (no duplication)
- [ ] Single responsibility
- [ ] Clear naming (no `data`, `temp`, `x`)
- [ ] No dead code or debug artifacts

### Security
- [ ] No hardcoded secrets
- [ ] User input validated/sanitized
- [ ] SQL parameterized
- [ ] Auth checks on protected routes

### Test Quality
- [ ] Tests test behavior (not "does it run")
- [ ] Clear assertions
- [ ] Edge case tests for critical paths

## Severity Guide

| Severity | Definition | Action |
|:---|:---|:---|
| Critical | Security, spec violation, data loss | MUST fix |
| Major | Functional bug, missing test | MUST fix |
| Minor | Style, naming | CAN defer (log it) |
