# Spec: Harden auto supervision (user rulings 2026-10-30)

> **Date**: 2026-10-30 | **Level**: Lv1

## Goal

Two supervision hardenings ruled by the user after the first full-auto
dogfood, both in one motion: stage commits inside spawned sessions can
never sweep a supervisor's uncommitted files, and the spawn execution model
goes async so run-lock heartbeats stay live and stalled streams die at the
idle limit instead of being classified afterwards.

## Decisions (prose)

D-1 Dirty-snapshot guard (ruling: option A). The loop snapshots
`git status --porcelain -uall` before each spawn (bounded, capped) and
carries the path list in the spawn env as `GOS_AUTO_DIRTY_BASELINE`; the
in-spawn stage commit, when the marker and baseline are both present,
unstages any baseline path that the directory sweep staged (the state file
stays stageable — an advance is meaningless without it) and prints a loud
exclusion line. This is a hygiene guard, not a trust boundary: trust
decisions keep reading the masked store.

D-2 Async spawn execution (ruling: option A). The working and review
runners drive detached child process groups with live event loops: the
wall clock kills the group at the limit, every stream chunk re-arms the
idle killer, and the runner's interval timers (run-lock heartbeat plus a
repo-root lock mtime refresh) keep firing during waits. A live idle kill
reports `idle: true` and scores as the idle-timeout class. Lock advice
never suggests `--break-lock` against a pid that is alive — verification
guidance first, break only after the pid is confirmed dead.

## Scope

- bin/lib/ops/auto/loop.cjs — async runner, group kill, baseline capture,
  heartbeat mtime refresh, idle scoring
- bin/lib/ops/auto/redteam.cjs — async review runner with the same kill
  contract
- bin/lib/task/commit.cjs — baseline exclusion at the staging sweep
- bin/lib/core/lock.cjs — alive-pid break-lock advice softening
- test/sections/T104-auto-core.test.sh — c20 baseline guard, c21 async
  kill contract

## Deferred

- Default-profile selection (needs a better solution than a blunt
  workspace default — parked in concerns).
- status read-class exemption from the root lock (heartbeats now prevent
  the false stale signal; full exemption is a separate ruling).
