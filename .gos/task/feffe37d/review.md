# Review Record — stage-dispatch blueprint

Date: 2026-11-02 | Reviewer: two-phase (spec auditor + quality reviewer, fresh contexts)

## Phase 1 — spec compliance: PASS

All decisions D-49..D-57 implemented with file:line evidence; R-01's five
intent elements present; zero scope creep (DI-1..DI-5 and the four ruled-out
concerns verified absent from the diff).

## Phase 2 — code quality: FAIL → cured

| # | Severity | Finding | Disposition |
|:--|:--|:--|:--|
| C1 | Critical | wave spawn env leaked runner credentials (spread-copy overlay bypassed adapter sanitization) | FIXED — original env ref + separate baseline; overlays sanitized (T108 C14) |
| C2 | Critical | wave deny scan ran on the tail window only — denial evidence truncatable | FIXED — preTruncationDenyHits preferred; denyHits in stamp telemetry; sidecars written (T108 C15) |
| C3 | Critical | request/ack admission was self-signable from the RW scratch | FIXED — acks live store-side, ro-bound at /run/gos-acks; scratch read path removed (T106 C10) |
| M1 | Major | Class S spawn argv lacked the engine executable — real runs ENOENT | FIXED — composed.engine prefixes argv everywhere (T107 C18) |
| M2 | Major | held waves indistinguishable from crashes; reconcile trusted scratch-written evidence | FIXED — store-side waveStarts/heldWaves records; scratch marker removed; reconcile reads store only, refuses deny-stamped waves (T108 C16) |
| M3 | Major | crashed-advance recovery adopted a spawn-writable snapshot | FIXED — adoption gated on recorded baseline state hash (T104 c29) |
| M4 | Major | single-wave plans froze without wave stamps and wedged at BUILD entry | FIXED — stampWave on >=1 wave (T105 PS-f) |

## Deferred minors (logged, not blocking)

breaker OID_RE caps at 40 hex; hardcoded engine string remnants; nested
mutate cross-root lock nesting; claims ledger rewrite non-atomic; wave marker
fsync absence (moot — marker removed); UTF-16 length accounting in spawnrun
capture; loop comment-block drift; gate console-patch exit-window;
waveUnitLabel null-guard asymmetry.

## Verdict

PASS — all Critical/Major cured with RED-first negative fixtures; sections
T104 93/0, T105 31/0, T106 37/0, T107 71/0, T108 62/0; map family green;
pack-check 0; cjk-lint 0; gate codemap green.
