# Dogfood Runbook — Auto Loop Green Cycle

Operational record for the auto-loop survivability acceptance: one full
auto cycle on the dogfood store, detached, with a mid-VERIFY SIGTERM
restart, ending with counters zero and a green run record, then
re-enable through the evidence gate.

## Sequencing note

The dogfood cycle runs against a fresh minimal task, so it executes
after this task ships (the loop drives the repository's current task;
driving this task mid-flight would double-drive the manual stages).
Evidence lands here after that run completes.

## Protocol

1. Preconditions: auto mode on, breaker tripped, zero run records
   (cold start) — verified via `gos auto status`.
2. `gos auto on` — cold-start disposition, proceeds.
3. `gos auto run` — defaults to detached (pid + log printed); child
   argv carries the foreground flag (no re-detach chain).
4. Mid-VERIFY SIGTERM: kill the detached runner during the VERIFY
   script step; observe either consistent restart or the
   crashed-advance rollback with a visible warning; no zero-byte
   orphan lock remains; the next cycle does not pause.
5. After the cycle reads green: `gos auto on` through the evidence
   gate (latest run record INTENT-to-SHIP green, sandboxed VERIFY
   steps passed), then `gos auto on --reset-breakers` records the
   disposition and zeroes the counters.
6. Capture the store snapshot JSON (counters zero + latest run record
   green) below.

## Evidence

- pre-run status: (pending)
- detach pid/log: (pending)
- sigterm restart: (pending)
- T-3b: (pending)
- store snapshot: (pending)
- re-enable gate: (pending)
