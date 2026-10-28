# GOS — Agent Instructions

Environment rules for AI sessions developing this repo. Product
mechanics live in README.md and skills/; guardrails are mechanized —
this file only tells you where they are.

## Rules

- Always run the repo CLI: `node bin/gos.cjs <cmd>`. The global `gos`
  binary lags the repo and once caused a misdiagnosis (2026-08-24).
- All written output (comments, commits, docs, changelog) is English;
  README.zh-CN.md is the only sanctioned Chinese file.
- Commits: Conventional Commits, functional-domain scope — enforced by
  commitlint (commitlint.config.yaml) + the charset policy
  (test/checks/commitlint-charset.sh). Subjects are imperative verb-object
  clauses a stranger can parse as an action ("fix stale lock check in push",
  "add squash-suffix stripping to push lint"), never state summaries or
  premise fragments ("main is PR-only") — user ruling 2026-10-26.
- Squash-merge subjects (and PR titles destined for squash): pass
  `bash test/checks/push-lint-squash.sh --subject "<candidate>"` BEFORE
  `gh pr merge --squash` — the platform builds the commit server-side where
  no local hook can intercept, and the push-range lint only fires after
  main has gone red — user ruling 2026-10-28.
- File disposition (git/npm/local): the census ledger is the truth —
  census.json, reconciled by test/pack-check.sh; CJK boundary by
  test/checks/cjk-lint.sh. Run pack-check before touching layout.
- Ignored-to-tracked flips under .gos/ go through `gos track` (atomic:
  gitignore negation + census + flip manifest, rollback on failure) —
  never hand-negate .gitignore for .gos files. Stage-back `(auto)` mirrors
  in concerns.md are cured by `gos gap migrate` (append-only ledger at
  .gos/logs/gap-history.ndjson, machine-local).
- Issues: read the matching .github/ISSUE_TEMPLATE form before opening one;
  issues opened through the CLI (`gh issue create`) must carry that form's
  type label (bug or enhancement) — the triage-gate workflow
  (.github/workflows/triage-gate.yml) closes unlabelled issues once with
  relabel guidance.
- Main is PR-only: never develop or commit task work on main. Every batch
  lands via feature branch → pull request → squash-merge; the pre-push
  guard rejects direct main pushes (emergency escape `GOS_ALLOW_MAIN_PUSH`
  requires explicit user approval — never self-serve it).

## Code Style

- No AI-process artifacts in ANY written file — comments, assertion wording,
  docs, templates, and seeded assets alike. Banned: decision anchors
  (`[D-NN]`, `[T-NN]`, `[REVIEW M1]`, `[Phase W T5]`, `RT2-F5`, `B-4`),
  spec-section citations in code comments (`spec §3.4`), task narrative
  ("this phase adds…"), AI meta-phrasing. Traceability lives in commit
  bodies and `.changes.md`, never in file content — user rulings
  2026-09-18 (39dad6a4/59ce99c5) and 2026-10-26 (extended to all file
  content, both self-repo and product-seeded assets).
- Comments that stay: section dividers, function purpose, parameter/return
  notes, invariants a stranger needs to work on the code. When in doubt,
  describe WHAT the code does, never WHY a task decided it.
- Existing anchor-style comments are legacy debt (do not imitate, do not
  add new ones); the mechanized sweep is tracked in the coding-standards
  phase.
