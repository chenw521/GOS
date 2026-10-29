# T104-auto-core — verification transcript (fresh run)

```
=== T104-auto-core ===
--- T104: auto core (T1,T2,T3,T4,T5,T8,T11,T12,T13,T14,T15,T16) ---
  ✓ T1: fake-host loop ends at SHIP with no delivery adapter
  ✓ T1: every spawn advanced its stage (one fresh session per stage)
  ✓ T1: store records every spawn (counters>0); stamps cover stage spawns and red-team rounds
  ✓ T2: auto on creates the store (advisories non-fatal) (exit 0)
  ✓ T2: auto on announces mode/limits
  ✓ T2: auto status exits 0 with a healthy store (exit 0)
  ✓ T2: status prints mode + profile + limits
  ✓ T2: status prints counters
  ✓ T2: status host tri-state shows the verified fixture row as selectable
  ✓ T2: status prints the hardening tier (kernel bubblewrap or honest lexical degrade)
  ✓ T2: fixture host hidden outside the test env gate
  ✓ T2: status stays readable with no store (never enabled) (exit 0)
  ✓ T2: status names the absent store
  ✓ T3: in-spawn commit on a delegated stage succeeds structurally (exit 0)
  ✓ T3: in-spawn commit records a PENDING auto-approval (no evidence claim)
  ✓ T3: persisted approval is PENDING/auto with zero evidence keys
  ✓ T3: unratified PENDING blocks the next stage advance (exit 1)
  ✓ T3: block names the ratification boundary
  ✓ T3: ratify verifies the store stamp pairing (missing/mismatch/stage refusals, then mode+evidence)
  ✓ T4: N consecutive failures trip the breaker -> paused
  ✓ T4: loop stops spawning at the trip (no third spawn)
  ✓ T4: trip persisted to the store (counter + layer record)
  ✓ T4: resume exits 0 (report only) (exit 0)
  ✓ T4: resume shows the breaker trip first-line
  ✓ T4: resume spawned nothing (spawn counter frozen at the trip)
  ✓ T5: red CI run holds for a recorded disposition; watch timeout lands disposition-unknown (never N)
  ✓ T8: probe failure fails closed naming the matrix entry; non-verified hosts refuse real runs
  ✓ T11: marker refuses auto on inside a spawned session (guidance printed)
  ✓ T11: marker refuses auto off inside a spawned session (guidance printed)
  ✓ T11: marker refuses auto run inside a spawned session (guidance printed)
  ✓ T11: marker refuses auto disposition inside a spawned session (guidance printed)
  ✓ T11: auto status stays readable inside a spawned session (exit 0)
  ✓ T11: loop module refuses under the marker before any store/lock touch
  ✓ T12: double-zero gate, findings held, prompt source = runner template, archive approval denied in-spawn
  ✓ T13: external mutation pauses with a report (never into N); deleted store pauses with guidance, counters survive
  ✓ T14: N=0 user input fails closed (validation) (exit 1)
  ✓ T14: N=0 names the integer floor
  ✓ T14: future store schema / truncated stream / malformed inputs fail into named errors
  ✓ T15: K (ping-pong), B (budget), failure classes verified independently
  ✓ T15: micro-overridden wall timeout counts into N; rc0 with no advance records as failure
  ✓ T16: live lock refuses --break-lock (takeover recorded); cross-host refusal names the clone and recovers
  ✓ T16: second concurrent auto run refuses while the first holds the lock (exit 1)
  ✓ T16: refusal points at the live instance (pid)
  ✓ T3: runner legs — in-spawn PENDING, double-zero red-team, ratification, advance proceeds
  ✓ T12: single zero and findings>0 hold the gate — PENDING stays, next advance blocked, never N
  ✓ T5: publish leg at SHIP — green adapter publishes with a closure record; red CI pauses for disposition (never N)
  ✓ T13: spawn-authored non-advance counts into N; external stage change pauses with a report
  ✓ C16: auto on --profile full --allow-full succeeds (exit 0)
  ✓ C16: status first line carries the allow-full indicator
  ✓ C16: allowFull round-trips through the store
  ✓ C16: profile full without --allow-full still fails compose at the gate
  ✓ C16: the persisted allowFull gate unlocks the full profile compose
  ✓ C16: --allow-full without profile full is refused (exit 1)
  ✓ C16: refusal explains the flag scope
  ✓ C16: --break-lock releases a stale lock (run then ends at SHIP) (exit 0)
  ✓ C16: stale lock break is reported
  ✓ C16: broken lock is gone after the run
  ✓ C16: --break-lock refused while the holder pid is alive (exit 1)
  ✓ C16: live-pid refusal names the holder
  ✓ C16: unknown auto subcommand exits non-zero (exit 1)
  ✓ C16: unknown subcommand prints the usage line
  ✓ C16: auto on --timeout-wall/--timeout-idle succeeds (exit 0)
  ✓ C16: timeout flags persist into the store config
  ✓ C16: loop resolves store timeouts as defaults; the env override still wins
--- T104 summary: 64 passed, 0 failed ---
--- T104-auto-core: 64 passed, 0 failed ---

=== Sections total: 64 passed, 0 failed ===
full log: /work/run/projects/bio-06/GOS/.gos/cache/section-runs/20261029T120346Z-full13647.log
```
