# Dogfood fixture seed notes

Discovery log for the fixture smoke: how the builder's committed GOS task
state was shaped until the fixture's own pinned verify legs pass, the
runtime seeding contract, and the one product blocker the smoke surfaced.

## Iteration log

Each round: build fixture, run the failing consumer directly, read the
failure, extend the committed shape, rebuild.

1. **Builder whitelist filter crashed (EISDIR).** The first filter
   one-liner destructured argv strings as pairs. Fixed the pairing loop;
   both Englishization whitelists are now filtered to `bin/**` entries
   (the fixture tracks the full bin tree plus its own suite; every other
   source-repo path the whitelists name is absent here, and a whitelist
   entry without its tracked file is a ghost = hard fail).
2. **Fixture CLI died on a missing package.json.**
   `bin/lib/core/fsio.cjs` requires `../../../package.json` for version
   metadata at module load, so any real CLI call (builder-time
   `paths --markdown`, run-time gate legs) needs it committed. The
   builder now copies the source repo's package.json with the exec tree.
3. **Plan parse came back empty.** Task ids in plan headings must match
   `T<digits><optional letter>` (`T301`), not `T-301` — the plan parser
   regex has no hyphen slot. Renamed; `coverage` then reported the
   decision covered via the plan.md scan and bidirectional went green.
4. **gate all green on the first full run** (advisories only: no
   lessons.json, no deps.json, no run-manifest yet, registry-gap on the
   two task-zone files). The committed shape that made it pass:
   - `.gos/state.json` schema v6, level 3, `current_stage: VERIFY`,
     completed INTENT..REVIEW, one covered decision, one requirement,
     one verified truth with the three-element evidence object
     (artifact_path `census.json` — tracked + on disk, unlike
     `.gos/cache/...` which does not exist before the first run),
     legacy ts-string approvals (not the auto-routed shape, so the
     schema validator leaves them alone), `spec_sha256` +
     `spec_gate_version: 2` frozen at build time, `task_head` = the
     first fixture commit, and `semantic.allowlist: ["census.json"]`
     (root-level seed data no plan task declares; everything under
     `.gos/**` is allowlisted by the default patterns).
   - `.gos/task/df01a/spec.md` with one decision card (options pipe
     table with three option tokens + a why-not line naming rejected
     tokens) — the v2 spec-card floor requirement.
   - `.gos/task/df01a/plan.md` with one `### Wave 1` / `#### T301`
     task, Covers the decision, **no Files line** (a Files-declaring
     task with an empty diff is a zero-hit failure; an empty diff from
     the task_head anchor is exactly what the verify cycle produces).
   - `census.json` marking `.gos/` as `git: true, lifecycle: true` —
     the flip-reconcile leg exempts lifecycle zones, which is what
     keeps six tracked .gos files reconciled without a flip manifest.
   - `.gos/README.md` rendered by the fixture's own CLI
     (`node bin/gos.cjs paths --markdown`) so the regen guard compares
     equal. Deterministic: the renderer is a pure function of the
     registry and the fixture has no FEEDBACK.md.
   - `test/checks/{cjk-lint,ascii-filenames,ai-trace-lint}.sh` copied
     from the source repo: the fixture IS a self-repo for its CLI
     (cwd toplevel == the CLI's own root), and gate all runs all three
     lints there.
5. **First runner cycle: undeclared diff files + cjk-lint EISDIR-style
   failure.** Two roots, both env/seed related:
   - The seeded `xdg/` and `home/` directories and the runner's own
     `.gos/logs/` were untracked, so the semantic diff-hit (which
     includes untracked files) saw them as undeclared changes. Fix:
     the fixture `.gitignore` now covers `.gos/cache/`, `.gos/logs/`,
     `xdg/`, `home/`.
   - `grep -P` with `\x{...}` classes fails with rc=2 ("character
     value in \x{} or \o{} is too large") under the C locale, which
     cjk-lint treats as an unreadable tracked file. Fix: the runner env
     must carry a UTF-8 locale (see env contract).
6. **Second runner cycle: all three verify legs green** (gate:P,
   sections:S — the real bwrap sandbox actually ran the fixture suite —
   truth:P), then the stage-exit advance commit died `rc=1`. Two stacked
   roots, fixed in order:
   - The exit-spawn env was marker-only (see "Blocker" below — fixed in
     loop.cjs: the childEnv now mirrors the Class S arm, so the commit
     child keeps HOME/XDG_DATA_HOME/PATH/LANG with credential-class and
     GOS_AUTO_* keys stripped).
   - With the channel admitting, the advance died `manifest-stale`
     instead: the fixture runner's manifest lacked the `patch_sha`
     field the commit-time freshness check requires (`!m.patch_sha`
     reads as stale regardless of tree equality). The runner now
     computes it exactly like the product runner — sha256 of
     `git diff HEAD` at suite end (empty-diff sha on a clean tree,
     `unknown` if git fails) — and writes it into the manifest JSON.
     With both in place the full cycle runs green: advance commit
     lands, stage VERIFY -> SHIP, and the run record ends
     `{"ok":true,"status":"ship"}` (verified twice on fresh builds).

## The blocker: exit-spawn env is marker-only

`bin/lib/ops/auto/loop.cjs` (scriptIteration, stage exit) spawns
`gos commit <stage>` with:

```js
const childEnv = {
  ...(env === process.env ? {} : env),   // <-- CLI runs always hit the {} arm
  [SPAWN_MARKER_ENV]: '1',
  GOS_AUTO_SPAWN_ID: exitSpawnId,
  [baselineEnvName]: baselineSha,
};
```

Every CLI-driven run (`auto run --fg`, and the detached child it forks)
has `env === process.env` true, so the child gets ONLY the three marker
variables. Consequences inside `gos commit verify`:

- No `HOME`: `captureIdentity()`'s `git config --global` probe prints
  `fatal: $HOME not set` (harmless, caught) and contributes no
  identity. Cured fixture-side by the repo-local `[user]` config.
- No `XDG_DATA_HOME`: the spawn channel's entry lookup
  (`spawnreg.storeSpawnRoot`) falls back to `os.homedir()` — with no
  `HOME` env that is the passwd home of the invoking user — so the
  child looks for the registry entry under the REAL user's
  `~/.local/share/gos/local:<repoKey>` while the runner registered it
  under the fixture's XDG override. Result: `spawn channel refused
  (no-entry)` → commit exits 1 → `rc0-no-advance`/`task-failed` → with
  breaker N=1 the run trips immediately. No green record is possible.

Contrast: the Class S sections step in the same file assembles its env
as `sanitizedSpawnEnv(env === process.env ? undefined : env)` — the
`undefined` arm deliberately returns the full sanitized environment.
The exit spawn's `{}` arm is the odd one out (introduced with the
dispatch-table rework; the pre-table loop passed no env option at all,
inheriting the full runner env). The detach path likewise forwards
`{...env}`.

**Fixture-layer options are exhausted**: the store path derivation has
no other injection channel (the scratch/ack channel env vars are also
absent from childEnv, and the exit spawn bypasses the spawn runner's
ackTick anyway), and polluting the real user's data home to satisfy the
passwd fallback violates test isolation. The fix belongs in
`bin/lib/ops/auto/loop.cjs`: the exit-spawn childEnv must carry the
runner env (mirror the sections-step arm — `undefined` instead of `{}`,
or an explicit allowlist that at minimum includes XDG_DATA_HOME, HOME,
PATH, LANG/LC_*), minus `GOS_AUTO_*` via the existing strip helper.

**RESOLVED**: the fix landed — childEnv now spreads
`launcher.stripGosAutoEnv(registry.sanitizedSpawnEnv(...))` plus the
marker/spawn-id/baseline vars, so the commit child keeps
HOME/XDG_DATA_HOME/PATH/LANG. Combined with the manifest `patch_sha`
fix above, the smoke cycle is green end to end on the current tree.

## Env contract for spawning the runner

From a scratch TESTBASE (all paths absolute, `env -i` base):

```bash
FIX=<fixture-dir>
cd "$FIX"
env -i \
  PATH="$PATH" \
  HOME="$FIX/home" \
  XDG_DATA_HOME="$FIX/xdg/data" \
  LANG=C.UTF-8 LC_ALL=C.UTF-8 \
  GIT_AUTHOR_NAME=gos-fixture GIT_AUTHOR_EMAIL=fixture@test.invalid \
  GIT_COMMITTER_NAME=gos-fixture GIT_COMMITTER_EMAIL=fixture@test.invalid \
  GOS_HEADLESS=1 GOS_LANG=en \
  node bin/gos.cjs auto run --fg
```

- `XDG_DATA_HOME` + `HOME`: pin the store and every home-deriving
  surface inside the fixture (seeded by `seed-store.sh`).
- `LANG`/`LC_ALL` UTF-8: the self-repo cjk lint needs a UTF-8 locale
  for `grep -P` unicode classes; a bare `env -i` default (C locale)
  turns every scan into a fail-closed unreadable-file error.
- `GIT_*` identity: the runner's own git operations (work branch,
  advance attribution) and the child commit fallback.
- `GOS_HEADLESS`/`GOS_LANG`: headless, English output.
- No `GOS_AUTO_*` in the outer env: the loop's registry-driven strip
  removes them from nested spawns by design, so timeout policy must
  ride the STORE (seeded `--timeout-wall 180 --timeout-idle 60`), never
  the environment.

cwd must be the fixture root (the CLI derives repo root, task state,
and pin/pin-worktree anchors from it).

## Wall-budget arithmetic

- Nested wall: 180s (store) — must be >= 120s so the sentinel section's
  600s first-pass sleep can never be wall-killed by the nested timer
  before the acceptance's scripted kill lands (a wall-kill is SIGKILL:
  it would fake-fail the killed-record assert with a timeout-class
  record instead of the killed-class one).
- Nested idle: 60s.
- Outer step budget: >= nested wall + 180s margin (420s in the smoke
  commands; the acceptance section should use the same or larger). The
  outer kill is SIGKILL and must never fire first.
- Sentinel block window: 600s, comfortably above nested wall 180s —
  the section harness's own kill is the only thing that can end it.

## Sentinel marker rule

`seed-store.sh` pre-creates
`<fixture>/.gos/cache/dogfood-sentinel.marker` so the sentinel section
takes its second-pass instant-green path and a smoke cycle cannot hang
in the 600s block. **The kill/restart acceptance must DELETE this
marker before its first run** (that re-arms first-pass blocking, which
is the kill window) — after the kill+restart, the restarted run finds
the marker the killed run armed and passes immediately. Repeat cycles
set `DOGFOOD_SENTINEL_RESET=1` in a scratch pass or delete the marker
again.

## Sandbox engine behavior

`composeScriptSpawn` resolves the sandbox engine through the launcher
probe (bwrap first). On this host: `bwrap` 0.13.1 at
`/usr/local/bin/bwrap`, tier `bubblewrap` — the sections step composes
a real bwrap frame (ro-bound workspace, writable `.gos/cache` + scratch
testbed pin). With bwrap absent the compose degrades to the lexical
tier (no kernel sandbox) but still runs; the fixture makes no engine
assumption beyond "the frame executes `bash test/run-sections.sh`
with `.gos/cache` writable".

## T9a contract

1. `bash test/sections/fixtures/dogfood/build.sh <fixture-dir>` (fresh,
   empty target).
2. `bash test/sections/fixtures/dogfood/seed-store.sh <fixture-dir>`
   (store inside `<fixture-dir>/xdg`, marker pre-armed).
3. **Delete** `<fixture-dir>/.gos/cache/dogfood-sentinel.marker`.
4. Spawn the runner per the env contract above with an outer SIGTERM
   plan inside the 600s window; assert the killed run record; restart;
   assert the green record via the store's runRecords (last
   `endState.ok === true`) or `auto status`.
5. Everything the cycle writes stays inside the fixture dir (store,
   home, cache, logs) — no system surface is touched.

## Builder/store split (sanctioned adjustment)

`build.sh` stays deterministic and idempotent (two builds diff -r
empty). Store seeding writes timestamps and machine-local lock records,
so it lives in `seed-store.sh`, invoked at runtime — the smoke and the
acceptance section call it explicitly. `auto on` re-running against an
existing healthy store reconfigures mode/limits/timeouts in place, so
the seeder is safely re-runnable (verified: limits N=1, wall 180s,
idle 60s, mode on after a double seed).
