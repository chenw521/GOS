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
- Issues: read the matching .github/ISSUE_TEMPLATE form before opening one;
  issues opened through the CLI (`gh issue create`) must carry that form's
  type label (bug or enhancement) — the triage-gate workflow
  (.github/workflows/triage-gate.yml) closes unlabelled issues once with
  relabel guidance.
