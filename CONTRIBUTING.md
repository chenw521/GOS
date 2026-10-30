# Contributing to GOS

Thanks for contributing to GOS (Get Organized System) — an adaptive workflow
plugin for AI coding assistants. This guide covers how to propose changes,
set up a development environment, and get a PR merged. For what GOS is and
why it exists, start with the [README](README.md).

## Ways to Contribute

- **Ask a question or float an idea** — open a thread in
  [Discussions](https://github.com/chenw521/GOS/discussions). The issue
  chooser links there for anything open-ended.
- **Report a bug** — use the bug report issue form
  (`.github/ISSUE_TEMPLATE/bug_report.yml`).
- **Propose a feature** — use the feature request issue form
  (`.github/ISSUE_TEMPLATE/feature_request.yml`).
- **Improve code, docs, or skills** — PRs welcome, following the
  [issue-first policy](#issue-first-policy) below.

Blank issues are disabled on purpose: the two forms capture the information
maintainers need to triage. Please use them.

## Issue First Policy

Every non-trivial change starts as an issue before a PR, so design feedback
lands before code is written. Triage tiers:

| Change size | Process |
| --- | --- |
| Typo / minor doc fix | Skip the issue, open a PR directly. |
| Small fix or improvement | Open an issue first (bug or feature form); the PR references it with `Closes #N`. |
| Large feature or behavior change | Start a Discussion or open a feature issue and wait for maintainer direction before implementing. |

## Development Setup

Prerequisites: Git, Node.js >= 20 (CI additionally tests Node 22), npm.

```bash
git clone https://github.com/chenw521/GOS.git
cd GOS
npm install

# Skill development: register this checkout with detected platforms
# (OpenCode etc.) so your local edits are the skills that load.
node bin/gos.cjs setup --local

# Install the commit-msg hook that enforces Conventional Commits.
node bin/gos.cjs setup --commitlint
```

The commitlint hook never blocks a commit on tooling absence — if `npx` is
missing it prints a notice and exits 0. Remove it anytime with
`node bin/gos.cjs setup --commitlint --teardown`.

## Local Green = CI Green

CI (`.github/workflows/ci.yml`) runs: `gate` (audit mode), `sections`
(Node 20 + Node 22 matrix), `pack` (npm pack manifest), `masters`
(template consistency), `commitlint` (pull requests only) and a
direct-push guard (main pushes only). Everything except the last two is
reproducible with four local commands — run them before every PR:

```bash
node bin/gos.cjs gate all --audit   # gate job: hard gates in audit mode
bash test/run-sections.sh          # sections job: section regression suite
bash test/pack-check.sh            # pack job: npm pack manifest integrity
bash test/workflow-lint.sh         # structural lint for .github/workflows/
```

The remaining two jobs:

- **masters** — re-renders the universal template layer and requires a zero
  diff over the seeded files. Only relevant when you touch generated files;
  reproduce locally with `node bin/gos.cjs init git --render-self` followed
  by `git diff --exit-code -- .github/ .` on the affected paths.
- **commitlint** — lints every commit in the PR range against
  `commitlint.config.yaml`. Reproduce locally with
  `npx --yes commitlint@19 --config commitlint.config.yaml --from origin/main --to HEAD`.

If the four commands above pass locally, CI passes. If you believe you found
a case where they diverge, that is a bug in the repo — please open an issue.

## Commit Message Conventions

Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
in the form `type(scope): imperative subject`:

- **type** — one of: `feat` `fix` `docs` `refactor` `test` `chore` `ci`
  `build` `perf` `revert`
- **scope** — a short module name, e.g. `core`, `task`, `render`, `ops`
- **subject** — imperative mood, lowercase, no trailing period, at most 72
  characters

Example: `feat(task): require changelog entry before verify passes`

Enforcement is layered: the commit-msg hook you installed during setup lints
each commit as you make it, and the CI commitlint job re-checks the full PR
range. A PR whose commits fail lint cannot merge, so fix history (e.g. with
an interactive rebase) before requesting review.

## Changelog Obligation

Any user-visible change — new behavior, a bug fix users would notice, a CLI
surface change — needs an entry under `[Unreleased]` in
[CHANGELOG.md](CHANGELOG.md) before the PR is considered reviewable.

The preferred path is the CLI, run from the repository root inside an active
GOS task (create one first with `gos init` if you developed the change
through GOS — see the README):

```bash
node bin/gos.cjs changelog add --summary "Fix gate audit false positive on empty task state"
```

The entry is a single user-facing sentence; traceability refs are derived
from the task automatically. Validate the file afterwards:

```bash
node bin/gos.cjs changelog lint
```

If you developed without GOS task state, add the one-line entry under
`[Unreleased]` by hand, following the existing entries' style.

## AI Assistance Declaration

GOS is built by humans working with AI tools, and AI-assisted contributions
are welcome — but they must be declared. If any part of your contribution
was produced with AI assistance, state in the PR:

1. **Assistant / harness** — the tool you used (opencode, Claude Code, etc.)
2. **Model** — which model wrote or modified the contribution
3. **Your verification** — what you personally reviewed, ran, and confirmed

The PR template has a section for this. The declaration is about honesty,
not permission: an accurate "the model wrote most of it, I reviewed the diff
and ran the test suite" is perfectly acceptable. Undeclared AI-authored
contributions will be asked to add the declaration before review proceeds.

## Pull Request Checklist

Before requesting review, confirm every item:

- [ ] Title follows `type(scope): imperative subject` (Conventional Commits,
      subject <= 72 characters)
- [ ] An issue is linked (`Closes #N`) — or the change is a typo-class fix
      and the PR says why there is none
- [ ] The four local commands from [Local Green = CI Green](#local-green--ci-green)
      pass and the commands you ran are listed in the PR
- [ ] A changelog entry exists for user-visible changes
- [ ] AI assistance is declared per the section above (or the PR states the
      change is fully human-authored)

## License

By contributing, you agree that your contributions will be licensed under
the [MIT License](LICENSE).
