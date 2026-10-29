# T105-auto-depth — verification transcript (fresh run)

```
=== T105-auto-depth ===
--- T105: auto adversarial depth (T5,T6,T7,T9,T10) ---
  ✓ T5: delivery adapter absent — loop ends at SHIP; probe classifies absent shapes and persists its state
  ✓ T6: bwrap masks (store + credentials) over binds; poisoning isolated to runner snapshots; lexical degrade honest
  ✓ T7: tracked state carries hash/count only — zero session ids, model names or output tails; store keyed by hash
  ✓ T9: forged ledger/counter/approval records satisfy no gate — verification reads the store, tamper surfaced
  ✓ T9: status counters come from the masked store, not the forged mirror
  ✓ T10: hook/remote/insteadOf plants abort into the breaker; global-config poison neutralized by sanitized privileged git
  ✓ RT1-F3: spawn env strips gh/git/ssh/aws credentials; PATH + model keys survive; overrides land last
  ✓ RT1-F3: .git-credentials/.aws/.gnupg masked in every profile; repo .git rw-bound at kernel tier; ordering intact
  ✓ registry: row without version_command classifies a probe failure (fallback --version), never crashes
--- T105 summary: 9 passed, 0 failed ---
--- T105-auto-depth: 9 passed, 0 failed ---

=== Sections total: 9 passed, 0 failed ===
full log: /work/run/projects/bio-06/GOS/.gos/cache/section-runs/20261029T120155Z-full28148.log
```
