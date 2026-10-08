# GOS — Agent Instructions

Rules for developing GOS itself. Every AI session in this repo reads
this file by default, so it stays minimal and normative — what to do
and what not to do. Product capabilities (routing, stages, mechanisms)
are documented in README.md and skills/, not here.

## CLI version discipline (CRITICAL)

While developing in this repo, always run `node bin/gos.cjs <cmd>` —
the repo code is always newest. The global `gos` binary is banned for
this repo's own development: the npm snapshot necessarily lags the
repo, and once caused a misdiagnosis after the wrapper-claim fix
(lessons 2026-08-24). The global build exists only for consumption by
other repos (e.g. GOS-benchmark); release sync is push + tag +
`npm i -g`.

## Code Style (binding for all AI sessions)

- Language: code comments, commit messages, docs, changelog entries
  MUST be English. README.zh-CN.md is the only sanctioned Chinese file.
- Comments: write only what code cannot say — section purpose, function
  contract, non-obvious invariants/params. FORBIDDEN: decision IDs
  (D-XX), finding refs ([REVIEW ...], [P1-F2]), phase/stage markers
  ([Split-③]), process narration. Traceability lives in commit bodies,
  never in code comments.
- Commits: Conventional Commits — `type(scope): imperative subject`
  (type: feat/fix/docs/refactor/test/chore/ci/build/perf/revert). The
  scope must be a FUNCTIONAL domain — core/map/task/nav/ops/render/
  knowledge/gate/cli/ux/i18n/docs/release/changelog/codemap/router/
  benchmark/skills/templates/workflows/test/repo/verify/changes/
  roadmap — never the product name (gos), a phase/task id (P13), or
  any process label. Subject must be pure ASCII, <= 72 chars, body
  explains what/why, breaking changes via `!` or BREAKING CHANGE
  footer. Enforcement: commitlint scope-enum + charset policy; the
  advance-commit template is chore(task): advance <stage>.

## Repo layout invariants

- The public tree ships the product only: `bin/` (CLI runtime),
  `skills/`, `templates/`, `hooks/commit-msg.sh` (hook master),
  `.opencode/` (plugin + slash commands), plus repo metadata.
- Development process artifacts (`.gos/task/`, `.gos/archive/`,
  `.gos/project/` history, `.changes.md`, `hooks/commit-msg` install
  copy) are machine-local and gitignored — never commit them.
- `census.json` is the file-disposition ledger; `test/pack-check.sh`
  reconciles it against git/npm/gitignore, and `scripts/census-dispose.sh`
  executes dispositions one at a time. New top-level paths must be
  recorded there.

## GOS CLI quick reference

<!-- gos:core-shortlist begin -->
- `gos` (no args) — status + what's next (zero-memorization entry)
- `gos init <level> "<intent>"` — start task
- `gos commit <stage>` — atomic commit + stage advance
- `gos gate all` — hard gates (exit 1 on failure)
- `gos context <stage>` — pre-computed context JSON
- `gos resume` — cross-session resume summary
- `gos instructions <stage>` — stage-by-step guidance
- `gos phase <sub>` — Lv4 phase lifecycle
- `gos decision <sub>` — record/amend decisions
- `gos help [--json]` — full capability discovery

Full capability: `gos help [--json]`
<!-- gos:core-shortlist end -->

