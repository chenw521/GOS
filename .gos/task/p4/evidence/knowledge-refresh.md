# Evidence — P4 T11 self-repo knowledge refresh (dogfood)
sha: 6327369a9feaafee11eb26437c5acc2e5b822158
date: 2026-10-22
task: T11 self-repo knowledge refresh (covers D-19, D-20)

## What changed
- .gos/codebase/structure.md — rewritten from pre-split monolith claims to
  current truth: 263-line bin/gos.cjs entry + bin/lib 7-domain tree (54 lib
  files, 492 fns per T46-module-structure EXPECT); entry index pattern,
  key sizes, invariants, navigator tiers documented.
- .gos/codebase/conventions.md — rewritten: 3-way command sync (D-14),
  sibling/namespace require rules + require-allowlist directions, census
  lifecycle (pack-check + census-dispose), test section conventions,
  drift-ledger protocol (T25/T46, generated-at provenance header), i18n
  locale dot-keys (P15 D-63), commitlint/output discipline.
- .gos/codebase/concerns.md — rewritten: open debt (manual drift ledgers,
  golden pre-split drift, per-wave EXPECT updates, .gos/cache races) and
  current traps/hotspots; no (auto) mirrors.
- Each trio file carries line 2 `born-at: 6327369a9feaafee11eb26437c5acc2e5b822158`
  == this ledger sha == `git rev-parse HEAD` at refresh start.

## What did NOT change
- Repo STAYS opted out of tracking: no `gos track`, no census edits — the trio
  remains git:false machine-local (verified below). No commits made.

## Verification (post-rewrite)
- `grep -r 4800 .gos/codebase/` → empty (monolith line-count claims cured)
- `sed -n 2p` on all three trio files → born-at sha (matches this ledger)
- census.json codebase entries → trio git:false unchanged
- `bash test/run-sections.sh T100` → PASS (T9 navigator assertions intact)
