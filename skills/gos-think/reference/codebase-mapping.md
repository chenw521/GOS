# Codebase Mapping (brownfield, lightweight)

## When

THINK entry, no `.gos/codebase/` exists, and the repo has existing code
(non-trivial: >5 source files). One-time investment (~10 min), benefits
every later task.

Router/THINK should OFFER it once: "Existing code detected but no
codebase map. Map first? (~10 min, benefits all future tasks) — yes /
skip this task / never for this repo (record in lessons as [project])."

## Directory contract: 7 files in `.gos/codebase/`

This doc is the single doc surface for the directory. Every file that
can appear there, its producer command, and its tracked status:

| File | Producer | Git status |
|---|---|---|
| structure.md | THINK codemap (hand-written) | machine-local |
| conventions.md | THINK codemap (hand-written) | machine-local |
| concerns.md | THINK codemap (hand-written) | machine-local |
| network.md | `node bin/gos.cjs map scan` | tracked |
| edge-baseline.json | `node bin/gos.cjs map scan` | tracked |
| require-allowlist.json | `node bin/gos.cjs map allowlist init` | tracked |
| unmapped-fns.txt | `node bin/gos.cjs gate codemap` | machine-local |

Tracked status is enforced by `.gitignore`: `.gos/codebase/*` is
ignored, with whitelist negations for exactly network.md,
edge-baseline.json, require-allowlist.json (the three machine-readable
map-2.0 files — their diffs are reviewable evidence). The four
machine-local files are per-clone views or drafts and never enter git.

An eighth artifact can appear after a baseline rotation:
`edge-history.ndjson` (append-only, gitignored) — see edge-baseline.json
below.

## Travel tiers (D-20) — what a fresh clone actually has

File availability is tiered; never assume a file exists because it
existed on the machine that wrote it:

| Tier | Files | Present on a fresh clone? |
|---|---|---|
| Static guides | structure.md, conventions.md, concerns.md | No — hand-written, machine-local; regenerate by re-running the THINK codemap pass |
| Map data | network.md, edge-baseline.json, require-allowlist.json | Yes — git-tracked; the ONLY tier that travels with clones |
| Regenerable byproducts | unmapped-fns.txt, edge-history.ndjson | No — rebuilt by the next `gate codemap` / baseline rotation; unmapped-fns.txt carries its own provenance header (`generated-at: <ISO> @ <HEAD[0:8]>`) so a stale copy is detectable |

A clone with no `.gos/codebase/` has guides absent and map data absent
until someone commits the tracked tier and runs the producers; `gos
context think` reports this via `has_codebase_map`/`suggest` and the
`navigator` hint (tier contract in one field).

## THINK codemap files (hand-written, no CLI producer)

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

Regeneration semantics: none — these three are written once by the
agent during the THINK codemap pass (no command generates them) and
live only on the machine that ran THINK. `gos context think`
auto-includes them in read_files; a clone without them simply gets no
codemap context until the pass is re-run.

## map 2.0 files (CLI-generated, git-tracked)

### network.md

- Producer: `node bin/gos.cjs map scan` (refreshed at the end of every
  scan).
- Purpose: hybrid anchor-network view — CLI-rendered edge/fn graph
  tables plus a manual region under the `<!-- MANUAL:notes -->` marker
  for agent annotations.
- Regeneration semantics: full rewrite of the CLI-rendered body; the
  manual region is preserved verbatim. If the marker is missing the
  refresh refuses to run (never burns hand-written notes). A rotation
  of up to 5 backups (network.md.1 … .5) is kept before overwrite.

### edge-baseline.json

- Producer: `node bin/gos.cjs map scan` (written alongside deps.json).
- Purpose: two-layer edge-count baseline `{current, peak}` for
  extractor-degradation detection in `gate codemap` (drop vs peak,
  fn-set fingerprint).
- Regeneration semantics: `current` is updated by every scan; `peak`
  is monotonic (growth-only) — a self-healing scan can never wash out
  peak evidence. The only peak-rotation exit is
  `node bin/gos.cjs map baseline reset --reason "<why>"`, gated by
  `gos approve baseline-reset`; the old peak is archived append-only to
  `edge-history.ndjson` (gitignored, never deleted).

### require-allowlist.json

- Producer: `node bin/gos.cjs map allowlist init` (v2 schema: module
  roots + allowed require directions).
- Purpose: direction assertion feed for `gate codemap` — a require
  that crosses a disallowed direction fails the gate.
- Regeneration semantics: refuses to overwrite an existing file unless
  `--force` is passed (direction diff printed first). Hand-edits are
  legitimate (whitelist extensions) — that is why it is tracked.

## Coverage file (CLI-generated, machine-local)

### unmapped-fns.txt

- Producer: `node bin/gos.cjs gate codemap` (best-effort; rewritten on
  each run).
- Purpose: full list of callgraph fns with no test annotation coverage
  (unmapped — the annotation map does not cover them), backing the
  gate's coverage summary line.
- Provenance header: the first line is
  `generated-at: <ISO> @ <HEAD[0:8]>` (e.g.
  `generated-at: 2026-10-22T14:08:49Z @ 63273690`); in an unborn repo
  the anchor degrades to `@ unborn`. A copy whose header sha does not
  match the checked-out HEAD predates (or postdates) the working tree —
  regenerate before trusting it.
- Regeneration semantics: disposable view — safe to delete, recreated
  by the next `gate codemap` run.

## How to produce (fast path)

1. `ls` tree + read entry points + 1-2 representative files per layer.
2. Grep for patterns: error style, test layout, config access.
3. Ask the USER for concerns.md seeds: "any known traps in this repo?"
   (their answers → also candidate lessons `[project]` entries).
4. Write the 3 hand-written files; run `node bin/gos.cjs map scan` and
   `node bin/gos.cjs map allowlist init` for the machine layer.
   Commit the three tracked files with the next stage commit; the four
   machine-local files stay out of git.

## Refresh triggers

- concerns.md: append whenever a BUILD/VERIFY gap reveals an unknown
  trap (alongside the lessons entry).
- structure/conventions: re-check on demand when PLAN's "Patterns to
  Follow" contradicts what BUILD actually finds (drift = update map).
- network.md / edge-baseline.json: every `map scan` (automatic).
- require-allowlist.json: only via `map allowlist init [--force]` or
  deliberate hand-edit when a new direction is blessed.
- `gos context think` auto-includes existing map files in read_files.
