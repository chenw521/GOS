# Dogfood fixture runbook

Workspace fixture for the restart-safe auto loop acceptance.
`build.sh <target-dir>` materializes a self-contained gos workspace repo
(deterministic by contract — two fresh builds diff clean). No remote is
configured; the workspace owns its whole history.

## Layout

- `bin/`, `templates/` — the gos exec tree, copied from the source
  checkout at build time and committed (production shape for a user
  workspace; no package.json — the CLI is zero-dependency and the acorn
  callgraph leg degrades to an advisory)
- `test/run-sections.sh` — minimal deterministic section runner (discovers
  `T*.test.sh`, counts ✓/✗, tees to `.gos/cache/section-runs/`, writes
  `.gos/cache/run-manifest.json`)
- `test/sections/T1-fixture-trivial.test.sh` — always-green section
- `test/sections/T2-fixture-sentinel.test.sh` — two-pass arming sentinel
- `.gitignore` — `.gos/cache/` (machine-local run state)

## Sentinel behavior

- Pass 1 (marker absent): writes `.gos/cache/dogfood-sentinel.marker`
  (pid/pgid/timestamp), then blocks for a bounded 600s — kill the
  enclosing runner inside this window.
- Pass 2 (marker present, i.e. a restarted run): exits 0 immediately —
  a restarted run cannot re-block.
- `DOGFOOD_SENTINEL_RESET=1` deletes the marker and exits 0.

## Post-ship cycle

- Run one real kill/restart dogfood cycle after this task ships; a
  skip-only record leaves the regression surface uncovered.
