# Dogfood report — auto dispatch pipeline on live machinery

Task 7f6b73bf · observer log: store tree observer-session/session.ndjson
(machine-local, relocated after the repo-side cleanup loss) · six fix tasks
landed on dogfood/auto-pipeline-verify.

## Outcome summary

Cycle 1 ran six attempts. The loop machinery is verified live end to end
up to the THINK stage; the remaining blocker is model yield, not
mechanism. Cycle 2 did not run (vehicle never reached BUILD).

## Defects found and fixed (each RED -> GREEN, suite 3546/0 final)

1. Non-wave agent stages (INTENT/THINK/PLAN/REVIEW) issued the commit
   grant but composed without the scratch/ack channel equipage — the
   in-sandbox advance died no-entry against the masked store registry.
   Fix: equipage ships with every work spawn.
2. probeEngine reported the raw `bubblewrap 0.13.1` stdout as the
   version; the dotted-numeric sizing floor rejected it — every
   kernel-tier scratch compose refused on real hosts. Fix: extract the
   numeric token.
3. The runner-side ack responder (store.admitAndAck) had zero live
   callers; the test suite hand-rolled its polling loop. Fix:
   store.serviceRequests + a spawnRun ackTick wired into the loop, the
   script legs, and the wave driver.
4. loopSpawnRunner's whitelist forward dropped the ackTick option, so
   fix 3 never reached spawnRun on live runs. Fix: forward it; the
   regression drives the real default runner.
5. Every deny-pattern match in a stream counted as an escape, so a spawn
   echoing its own permission config or skill docs flipped escapeDriven
   and vetoed a landed advance into an external-mutation pause. Fix:
   hits classify kind=command (bash command field) vs kind=text; only
   command-kind carries the veto and the wave hold; telemetry keeps both
   counts.
6. Task commit probed git bare; inside the sandbox the masked
   ~/.gitconfig read EACCES and git died fatal, the probe flipped
   not-a-repo, and the advance silently skipped its commit while the
   stage still moved (runner rolled it back as a crashed advance).
   Fix: git runs under neutralized global/system config with identity
   captured beforehand; the stamp whitelist also stopped dropping
   denyCommandHits.

## Landmarks (Observable Truths)

- T1 VERIFY-zero-LLM: NOT dynamically verified — cycle halted at THINK.
  Dispatch table and script-leg compose verified by inspection only.
- T2 wave three-contract: NOT dynamically verified — BUILD never
  reached. T108 covers the contracts at fixture level.
- T3 feral checklist: (a) stamps carry echo-kind denyHits > 0 from
  config/doc prose — read denyCommandHits instead (concern c3d4e5f6);
  (b) zero breaker records with cls takeover|env — verified; (c) claims
  verb-set clean (channel grants honored, 13 stamps); (f) no
  command-kind deny attempt across all spawns — the deny lines in the
  final trip detail are TEXT-kind spec prose echoes, confirmed against
  the stream sidecars.
- T4 concern [72b7706e]: ruled KEEP with partial dynamic evidence —
  post-fix INTENT advance attributed and adopted cleanly (d9419c9), zero
  same-signature pause; prune candidate at the next completed cycle.

## Pause ledger (family classification per spec D2)

- external-mutation x2 (attempts 3 and 4): both misattributions by the
  echo-veto (fixed as defect 5).
- crashed-advance recovered x1 (attempt 5): correct rollback, root cause
  defect 6.
- breaker-tripped x1 (attempt 6, cls task layer N): 3 consecutive THINK
  spawns rc0-no-advance — model yield, sessions 25-36 min without
  completing the spec write or the advance.
- Observer-side kills x3 (tool timeouts / known-root-cause stops),
  logged as observer errors, never counted against the loop.

## Landmarks for the machinery that DID verify live

Registered write channel round trip with budget burn; advance commit
attribution via git evidence; echo classification; crashed-advance
rollback; breaker N-trip with a truthful report; stale lock
auto-recovery; per-stage stamp telemetry with dual-window sidecars.

## Follow-ups

- concerns a1f2c3d4 (observer log destroyed by repo cleanup), b2e3f4a5
  (init --force deletes tracked non-active task zones), c3d4e5f6
  (denyHits vs denyCommandHits audit field), d4e5f6a7 (THINK spawn
  yield), e5f6a7b8 (red-team mechanization list triage).
- Re-run the two-cycle dogfood for T1/T2 once spawn yield at THINK is
  addressed.
