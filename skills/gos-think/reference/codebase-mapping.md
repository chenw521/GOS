# Codebase Mapping (brownfield, lightweight)

## When

THINK entry, no `.gos/codebase/` exists, and the repo has existing code
(non-trivial: >5 source files). One-time investment (~10 min), benefits
every later task.

Router/THINK should OFFER it once: "Existing code detected but no
codebase map. Map first? (~10 min, benefits all future tasks) — yes /
skip this task / never for this repo (record in lessons as [project])."

## Output: 3 files in `.gos/codebase/` (committed, like project/)

### structure.md (one page)

```
## Layout
src/
  models/     — data classes, extend BaseModel
  services/   — business logic, no HTTP
  routes/v1/  — controllers, thin
  middleware/ — auth etc.
## Entry points
- server.ts (HTTP), cli.ts (commands)
## Key invariants
- errors: always AppError(code, msg) — never raw strings
```

### conventions.md (what PLAN's "Patterns to Follow" copies from)

- Naming (files/classes/functions), error handling pattern, test
  framework + location + assertion style, config access pattern,
  import ordering. ONE example file reference per convention
  ("see src/routes/v1/users.ts for the route template").

### concerns.md (integration risk map — feeds Red Team round 3)

- Known traps: "migration X conflicts if users table exists"
- Coupling hotspots: "models/Base.ts is touched by everything —
  parallel agents editing it WILL conflict"
- External deps with sharp edges: "external payment API 2s timeout"

## How to produce (fast path)

1. `ls` tree + read entry points + 1-2 representative files per layer.
2. Grep for patterns: error style, test layout, config access.
3. Ask the USER for concerns.md seeds: "any known traps in this repo?"
   (their answers → also candidate lessons `[project]` entries).
4. Write the 3 files. `gos commit` them with the next stage commit.

## Refresh triggers

- concerns.md: append whenever a BUILD/VERIFY gap reveals an unknown
  trap (alongside the lessons entry).
- structure/conventions: re-check on demand when PLAN's "Patterns to
  Follow" contradicts what BUILD actually finds (drift = update map).
- `gos context think` auto-includes existing map files in read_files.
