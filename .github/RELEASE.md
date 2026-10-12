# Release Process

Maintainer-facing operations guide for releasing GOS. This documents what
IS — the automation lives in `.github/workflows/release.yml` and
`test/release-validate.sh`; nothing here overrides them. End-user
documentation stays in the top-level `README.md` / `README.zh-CN.md`.

## Workflow stages (release.yml)

Releases are **manual dispatch only** (GitHub Actions
`workflow_dispatch`, input: `tag`) — a single-person human gate ahead of
every irreversible action. Three ordered stages:

1. **validate** — every precondition must pass before anything runs:
   semver tag shape, `tag == package.json version`, tag above the newest
   CHANGELOG version, non-empty `[Unreleased]`, working npm credentials
   (`test/release-validate.sh`). The exact rules are enforced by code;
   this table is a map, not the law.
2. **publish** — `npm publish` (irreversible) with the version already
   validated to equal the tag.
3. **promote** — only after a successful publish: fold `[Unreleased]`
   into the version section, commit `CHANGELOG.md`, create the GitHub
   Release from that section.

Irreversible actions always run last, so a failed validation can never
leave a half-released state behind. Between stages the workflow re-pins
the commit SHA, so a stage cannot silently run against a moving ref.

## Tag discipline

- Tags are `vX.Y.Z` (exact semver), must equal `package.json` `version`,
  and must sort above the newest version section already in
  `CHANGELOG.md`.
- `[Unreleased]` must be non-empty at validate time — the change record
  is part of the delivery, not an afterthought (changelog lint's
  same-day obligation enforces this during development; ship gate
  blocks otherwise).
- Version bumps are deliberate commits (`version` chore), not drive-by
  edits.

## npm publish

- Publishes to **registry.npmjs.org** as the scoped package
  `@chenw521/gos` (name ruling D-50; the registry itself moved from the
  GitHub Packages private beta to npmjs per D-78 — `publishConfig`
  points at npmjs and `.npmrc` is deliberately not tracked).
- Credentials come from the `NPM_TOKEN` secret; validate runs a real
  credential check (`npm whoami` class) before anything irreversible.
- Scoped packages default to restricted access; public visibility is an
  explicit access decision at publish/afterwards, aligned with the
  publicize milestone (branch-protection and access rulings parked
  under the publicize trigger, concern 98c5d641).

## Benchmark pinning (dormant)

The external task-suite benchmark is currently retired and being
rebuilt (see README "Benchmark in progress"). **No live pinning
obligation exists today.** When the benchmark returns, each release
must re-sync the benchmark's pinned GOS version+SHA, and a history
rewrite (as in D-69/D-74) additionally requires grepping the benchmark
repo for cross-repository SHA references before force-pushing. The rule
is recorded here so the obligation revives with the benchmark.

## Rollback & concurrency

- `release-<ref>` has `cancel-in-progress: true`: a second dispatch on
  the same ref cancels a running one. A run cancelled **between publish
  and promote** leaves exactly the half-released state the stage
  ordering tries to prevent — npm has the version, `CHANGELOG.md` does
  not. Recovery: complete the promote steps manually (fold
  `[Unreleased]`, commit, create the GitHub Release) rather than
  re-dispatching.
- `npm unpublish` is limited (72h window, and only if no dependents);
  treat publish as irreversible in practice. A bad release is fixed by
  a patch release, not by unpublish.
- The GitHub Release body regenerates from the CHANGELOG section —
  re-editing the release after the fact is safe; the CHANGELOG commit
  is the source of truth.
