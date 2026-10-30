--- T106: spawn write channel (channel-admit, channel-negative, cli-surface) ---
C1: channel-admit (real descendant, registered, live fresh holder)
  ✓ real descendant admitted
  ✓ window admits multiple whitelisted commands
  ✓ truth verify admitted
  ✓ exhausted window budget refused (exit REFUSED budget-exhausted)
C2: channel-negative (refusal matrix)
  ✓ missing entry refused (exit REFUSED no-entry)
  ✓ unset spawn id refused (exit REFUSED no-entry)
  ✓ redteam entry never writes (exit REFUSED redteam-no-write)
  ✓ non-whitelisted command refused (exit REFUSED not-whitelisted)
  ✓ truth add refused (verify only) (exit REFUSED not-whitelisted)
  ✓ stage mismatch refused (exit REFUSED stage-mismatch)
  ✓ dead holder refused (exit REFUSED holder-dead)
  ✓ pid-reuse (starttime mismatch) refused (exit REFUSED holder-starttime)
  ✓ non-ancestor holder refused (exit REFUSED not-ancestor)
  ✓ pid-1 holder never validates (exit REFUSED not-ancestor)
  ✓ stale heartbeat refused (exit REFUSED stale-heartbeat)
C3: cli-surface (marker-active CLI runs)
  ✓ marker + decision add refused
  ✓ refusal exits non-zero (exit 1)
  ✓ marker + commit without entry refused
  ✓ no-entry exits non-zero (exit 1)
  ✓ map/gate lock acquisition refused under marker
  ✓ edge acquisition exits non-zero (exit 1)
C4: human gates refuse under the marker (approve/archive/push)
  ✓ approve refused in spawn
  ✓ approve refusal exits non-zero (exit 1)
  ✓ archive refused in spawn
  ✓ archive refusal exits non-zero (exit 1)
  ✓ push refused in spawn
  ✓ push refusal exits non-zero (exit 1)
C5: sanitized seed (compose form + strip rules)
  ✓ sanitized seed: strip rules + compose form + invariant
C6: crashed-advance rollback (state wrote, commit never landed)
  ✓ crashed advance rolls back and re-drives
--- T106 summary: 29 passed, 0 failed ---
