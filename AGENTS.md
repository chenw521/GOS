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
  (test/checks/commitlint-charset.sh).
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
