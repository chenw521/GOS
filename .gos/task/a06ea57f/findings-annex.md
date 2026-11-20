# Findings Annex (raw evidence from the p21 dogfood cycle)

- Finding A: a SIGTERM'd detached runner leaves NO run record. The
  exception-record route (loop.cjs runLoop catch) covers in-process throws
  only; OS signal termination bypasses it. The killed run (which had
  advanced INTENT and BUILD) is absent from the store's runRecords.
- Finding B: after a mid-VERIFY SIGTERM, the restarted run's pinned
  post-suite legs read the pin worktree as dead: pin-tampered / pinned
  worktree HEAD unresolvable / fatal: not a git repository:
  .git/worktrees/9a07a154-pin - although the suite itself ran inside that
  pin minutes earlier. Three retries tripped layer N.
- Evidence pointers:
  - runbook: .gos/archive/2026-11-20-publicize-phase-p21-make-gos-auto-survivable-on-a-/task/p21/dogfood-runbook.md
  - machine-local dogfood store (READ ONLY): /home/bio-06/.local/share/gos/85af56a090a78924/store.json
  - kill-window suite logs: .gos/cache/section-runs/20261120T04*.log
  - pin lifecycle surfaces: bin/lib/ops/auto/workers.cjs
    (prepareSectionWorktree / sweepSectionWorktrees / lazyRecyclePins),
    loop.cjs runLoop finally
- Open question to triage first: the full suite includes nine
  worktree-conversion sections calling prepare/sweep with a real rootDir
  from inside the pinned tree; whether a mid-suite sweep or the SIGTERM'd
  run's stale registration kills the live pin is undetermined.
