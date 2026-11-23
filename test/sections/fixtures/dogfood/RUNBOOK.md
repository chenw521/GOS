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
- a minimal always-green section and a two-pass arming sentinel section
  under the fixture's `test/sections/`
- `.gitignore` — `.gos/cache/` (machine-local run state)

## Sentinel behavior

- Pass 1 (marker absent): writes `.gos/cache/dogfood-sentinel.marker`
  (pid/pgid/timestamp), then blocks for a bounded 600s — kill the
  enclosing runner inside this window.
- Pass 2 (marker present, i.e. a restarted run): exits 0 immediately —
  a restarted run cannot re-block.
- `DOGFOOD_SENTINEL_RESET=1` deletes the marker and exits 0.

## Post-ship cycle

Once the restart-safety changes land on the dogfood host, run one real
post-ship cycle on that host — operational, not harnessable by the section
alone:

1. Start one real detached auto cycle through the CLI, as the dogfood
   host runs it.
2. Kill the enclosing runner mid-VERIFY, inside the sentinel's block
   window.
3. Restart, and confirm the restarted run reaches a green record end to
   end.
4. A host where the section only ever SKIPs does not satisfy this cycle —
   the kill/restart regression surface stays uncovered (pairs with the
   T136 SKIP accounting).
5. Evidence lives in the run log (`.gos/cache/section-runs/<ts>.log`) and
   the store record written by the restarted run.
