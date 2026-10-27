# Artifact Lifecycle Management

## Lifecycle Rules per Artifact Type

| Artifact | Created In | Updated In | Archived In | Size Rule |
|:---|:---|:---|:---|:---|
| `.gos/task/<id>/spec.md` (path via `gos context think`) | THINK | — | SHIP → `.gos/archive/` (whole task/<id>/ dir) | <300 lines |
| `.gos/task/<id>/plan.md` (path via `gos context plan`) | PLAN | — | SHIP → `.gos/archive/` | <200 lines |
| `.gos/state.json` | INTENT | Every stage | SHIP → `.gos/archive/` | <50 lines |
| `.changes.md` | First SHIP | Every SHIP | Never (append) | Trim >6mo |
| `docs/decisions.md` | THINK (Lv4) | THINK+SHIP | SHIP → merge | Rolling |

## Archive Process

```bash
mkdir -p .gos/archive/[date]/
# ship is now a two-phase transaction — task/<id>/ moves WHOLESALE:
#   .gos/task/<id>/  →  .gos/archive/<date-slug>/task/<id>/  (+ orphans/ adoption)
# manual mv is obsolete — never hand-move

# Archive state
mkdir -p .gos/archive/
mv .gos/state.json .gos/archive/[date].json
```

## Why Archive Instead of Delete?

- Specs contain decision rationale (why, not just what)
- Reference for similar future features
- Audit trail for compliance
- Onboarding material for new team members

## Cleanup Checklist Details

```bash
# Check for debug artifacts
grep -rn "console\.\|print(\|debugger\|TODO\|FIXME" src/ \
  --include="*.ts" --include="*.js" --include="*.py"
# Should return nothing (or only intentional TODOs with issue refs)

# Check for secrets
grep -rn "password\|secret\|api_key\|token" src/ \
  --include="*.ts" --include="*.js" --include="*.py" \
  | grep -v "process.env\|config\.\|\.test\."
# Should return nothing
```
