# D-71 Follow-up: feedback ledger demotion (placeholder card)

> Recorded by P20 as a covering card only — the implementation belongs to
> a later task in the stream that registered D-71 (2026-11-16).

## Decision (registered as D-71)

gh issues are the sole publication truth; the feedback ledger
(.gos/FEEDBACK.md) is demoted to untracked cache.

## What the implementing task must do (not P20)

1. Demote .gos/FEEDBACK.md from tracked to untracked cache: census flip
   plus gitignore reconciliation through the track/gap discipline —
   never a hand-negated gitignore entry.
2. Publication surface (issues users read) lives exclusively in gh
   issues; the local ledger is a machine-side buffer, never a second
   truth source (the same single-truth-source ruling that killed the
   wrapper state class).
3. Push flows that today write both (ledger row + issue) keep the issue
   as the canonical outcome and treat the ledger row as cache.

## Why P20 only records this card

D-71 was registered mid-P20 by a concurrent stream (2026-11-16 14:50,
issues #65-67 pushed live from that stream). Its birth_phase is P20, so
the coverage gate requires a covering task in P20's plan; the
implementation stays with the registering stream per the user ruling.
