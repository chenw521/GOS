# Spec: Defect Batch — Archive Orphan-Adoption Safety and Concerns Sidecar Bootstrap

> **Date**: 2026-10-27 | **Level**: Lv2 | **Status**: Draft (post red-team revision)

## Goal

Fix two live product defects diagnosed during the P6 closeout, both
recurring on every session:

1. **Archive orphan-adoption swallows census-tracked live files.** During
   `gos archive`, `.gos/ai-trace-whitelist.json` and
   `.gos/ai-trace-sweep-ledger.ndjson` were hoisted into
   `archive/orphans/` — the orphan scanner has no GOS_PATHS entries for
   them, and adoption has no tracked-file guard (incident 4819be22,
   recovered by git restore).
2. **Concerns sidecar corrosion chain.** When the anchor sidecar is
   absent, the untracked-store bootstrap path of `loadConcernsAnchor`
   returns an empty hash set **without writing**; the next `concerns add`
   then pushes a single hash to disk, and every later concerns command
   dies with anchor-mismatch (concern 9e216512; drove the P6 BUILD-era
   hand-edit cycle, manually cured twice on 2026-10-27).

## Requirements (R-NN)

- **R-01** (from intent): both defects root-cured — adoption never touches
  census-tracked files; the sidecar chain can no longer break via
  bootstrap.
- **R-02**: GOS_PATHS registry gains `ai_trace_whitelist`
  (`.gos/ai-trace-whitelist.json`) and `ai_trace_sweep_ledger`
  (`.gos/ai-trace-sweep-ledger.ndjson`) entries, `tracked: true`,
  granularity `file`, shaped after the existing `cjk_whitelist` entry.
- **R-03**: `detectOrphans` becomes two-tier: it returns untracked strays
  as **orphans** (current semantics minus tracked files) and reports
  git-tracked-but-registry-missing files separately as
  **unregisteredTracked**. Census `.gos` root-note updated to name the
  ai-trace assets.
- **R-04**: gate orphan advisory gains an additive, advisory-only
  registry-gap verdict for unregisteredTracked (capped output like the
  orphan advisory; never fails, not even under `--strict` — no
  dffa50f0-shaped false reds). The frozen `orphanAdvisory`/`orphanAdvisoryOne`
  contract copy stays untouched; the new key follows the verdict catalog
  discipline, both locales.
- **R-05**: archive orphan adoption moves **orphans only**;
  unregisteredTracked files stay in place with a registry-gap hint;
  adoption logs distinguish the two tiers.
- **R-06**: git probe containment — inside a git repo, any tracked-set
  probe failure during adoption makes adoption fail-closed (refuse to
  move, report the probe error); outside a git repo, fall back to the
  registry-only whitelist (the tracked concept does not exist there).
- **R-07**: `loadConcernsAnchor`'s untracked-store bootstrap branch returns
  the **full hash set derived from the file** (empty file → empty set),
  not an empty set. Read paths (`concerns list`) keep zero write
  side effects — persistence stays with the write paths (`add`/`prune`),
  which now persist a full consistent set by construction.
- **R-08**: views registry explainer line and zh/en locales updated for
  the two-tier semantics; section tests gain negative-path assertions:
  tracked-but-unregistered file is not adopted, probe failure refuses
  adoption, sidecar-loss bootstrap followed by two consecutive adds
  succeeds.

## Approach

### Decisions (Lv2 prose record)

- **Two-tier orphan semantics (user ruling, option C).** Chosen over
  adoption-only filtering (B) and single-tier untracked-only exclusion
  (A). A-alone would silence the registration-forcing advisory that
  currently catches track-without-register gaps — the gap prompt layer and
  the adoption safety layer must land together. The deep-dive consumer-chain
  survey that motivated this ruling surfaced only after user challenge;
  recorded as dialogue-governance evidence (concern logged 2026-10-27).
- **Fail-closed probe containment (user ruling).** Adoption is
  destructive relocation; inside a repo, missing git truth must refuse the
  move (the incident shape) rather than fall back to hoisting. Non-git
  roots never had tracked semantics and keep the registry-only behavior.
- **Bootstrap returns the derived set, writes stay at the write path.**
  The corruption lived in the bootstrap branch's return value; fixing the
  return (not adding load-path writes) keeps `concerns list` read-pure and
  makes the crash window between load and write self-healing (next load
  re-derives the same set).

### Implementation Sketch

1. `bin/lib/core/state.cjs` — two GOS_PATHS entries (after `cjk_whitelist`).
2. `bin/lib/ops/doctor.cjs` — `detectOrphans(state)` →
   `{ orphans, unregisteredTracked }`; tracked-set probe = one
   `git ls-files` rooted at the repo top (`--` pathspec `.gos` prefix),
   cached per call; probe failure returns a sentinel consumed per R-06;
   callers (`gate.cjs`, `task/archive.cjs`) adapted; gate prints the
   registry-gap advisory line (both locales, catalog discipline).
3. `bin/lib/task/archive.cjs` — adoption loop consumes `orphans` tier
   only; unregisteredTracked listed as skipped-with-hint; probe-failure
   sentinel aborts adoption with the probe error (fail-closed); rescan
   reuses the same tier split.
4. `bin/lib/knowledge/concerns.cjs` — bootstrap branch (sidecar absent,
   untracked or empty store) returns
   `{ hashes: entryLines.map(concernsLineHash) }`; bootstrap banner
   wording unchanged; no new writes in read paths.
5. `census.json` — `.gos` root note names the ai-trace assets (disposition
   unchanged: git:true by inheritance).
6. `bin/lib/render/views.cjs` + locales — registry explainer sentence and
   the new advisory strings.
7. `test/sections/` — extend the concerns/ship/orphan-scan sections with
   the R-08 negative paths.

## Red Team (3 rounds, Lv2)

- **Misuse**: mass-tracking junk under `.gos/` floods the advisory —
  capped output (slice 10 + overflow count) matches the orphan advisory
  precedent, and the census/pack-check layer owns tracked-ness
  adjudication; "tracked is safe" as a junk-tracking excuse is out of
  mechanism scope, the advisory keeps prompting. Accepted.
- **Edge**: fresh-clone tracked set (state/config/gates/cjk-whitelist/
  lessons.json/track-manifest/README/codebase/*) is fully covered by
  registry entries after R-02 → zero registry-gap noise on clone;
  subdirectory cwd handled by rooting the probe at the git toplevel;
  rename/delete races during adoption already guarded (statSync
  continue); empty concerns store bootstraps to `{hashes: []}` and the
  first add persists a one-element set consistent with a one-line file;
  stale `.bak` left by a lost sidecar is overwritten on the next write
  (add/prune write both). No design change required.
- **Completeness**: `--strict` semantics fixed as advisory-only for the
  new tier (R-04); zh locale must carry the full dynamic tail
  (catalog discipline, no hardcoded drops); rescan zero-assertion must
  filter by the same skipped bookkeeping; views explainer updated in the
  same batch. Two implementation notes folded into the sketch (advisory
  cap, toplevel-rooted probe).

## Observable Truths

- **T1**: detectOrphans excludes git-tracked files from the orphan set,
  reporting them separately as unregisteredTracked.
- **T2**: gos archive leaves every git-tracked file in place even when its
  GOS_PATHS entry is missing.
- **T3**: after deleting `.gos/cache/.concerns-anchors.json`, two
  consecutive `concerns add` calls both succeed with no anchor-mismatch.

## Verification

- New section-test negative paths (R-08) green; existing T45-family
  (ship sandbox adoption), T8a (transient zone), T6-family (concerns)
  assertions green without semantic regressions.
- `gos gate all` green (including the new advisory tier producing zero
  noise on this repo after R-02 registers the two files).
- Truths T1–T3 verified via replayed commands on isolated fixtures.

## Out of Scope

- Hand-edited tracked `concerns.md` with a live sidecar still dies
  (anti-tamper semantics unchanged).
- Registry completeness reconciliation beyond the prompt layer
  (registry-census-gitignore divergence guard stays with the separately
  tracked ledger line).
- No advisory escalation of the registry-gap tier under `--strict`.
