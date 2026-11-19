# Plan: P21 auto loop robustness

> **Date**: 2026-11-18 | **Based on spec**: .gos/task/p21/spec.md
> Note: D-107's premise wording ("writableRoots=[.gos]") is superseded by R-1's enumerated-set text — R-1 governs.

## Decision Inventory

- [x] D-106: dig-closure floor → T5a, T5b
- [x] D-107: VERIFY P1 skeleton (enumerated writable + env registry) → T1, T2, T9a, T9b, T9c, T9z
- [x] D-108: lock isolation via fixture-ization → T7, T9c
- [x] D-109: default-detach survival → T3
- [x] D-110: branch reap two-tier → T4a, T4b

## Requirement Claims

- [x] R-1: enumerated writable set + compose invariants → T1
- [x] R-2: GOS_AUTO_* registry + source-side whitelist → T2
- [x] R-3: worktree helper topology → T7
- [x] R-4: 95-failure triage to machine-checked zero → T9a, T9b, T9c, T9z
- [x] R-5: default detach with child contract + sentinel → T3
- [x] R-6: branch reap with refs/reaped revive → T4a, T4b
- [x] R-7: dig-closure floor + five negative cases → T5a, T5b
- [x] R-8: evidence-gated re-enable + green cycle → T10a, T10b, T11
- [x] R-9: deny scoring command-kind only → T8
- [x] R-10: THINK-trip triage → T6

## Shared Contracts (docking surfaces)

- **Manifest contract** (T7 produces, T9z consumes): when `GOS_SECTIONS_TREE_OVERRIDE` is set, run-sections.sh writes the manifest to `$TESTBASE/run-manifest.json` (repo-root manifest belongs to literal runs only) and emits fields `tree_source: "pinned"|"live"` + `pin: <sha|null>`; manifest-coverage.sh takes the manifest PATH as an argument (no hardcoding).
- **Section numbering**: new sections are T120-compose-invariants, T121-branch-reap, T122-dig-closure-floor, T123-auto-detach, T124-env-registry, T125-deny-scoring, T126-worktree-helper, T127-think-trip (T111/T112 already exist; runner FILTER is substring — always use full names).
- **File merge order**: T1 owns compose/writableRoots in loop.cjs + launcher.cjs; T2 (serial after T1) owns env/registry surfaces in the same files.

## Patterns to Follow

- Module style: bin/lib/ops/auto/*.cjs (header comment = purpose, export object at foot)
- Tests: test/sections/T*.test.sh (runner-sourced asserts, TESTBASE isolation, standalone-safe head)
- Locale strings: bin/lib/core/locales/{en,zh}.cjs keyed entries — never inline UI text
- Gates: floor registry pattern at bin/lib/ops/gate.cjs for registry-side floors; registry-EXternal checks follow the dig-floor precedent (gate.cjs:1984-1991 probe-first semantics note)
- **Every new tracked file**: census.json disposition + `bash test/pack-check.sh` green + charset clean (✓/✗ and CJK rules apply to fixtures too)

## Execution Waves

### Wave 1 (parallel, no deps)

#### T1: enumerated writable set (script-spawn path) + compose invariants
- **Covers**: D-107, R-01
- **Files**: bin/lib/ops/auto/workers.cjs, bin/lib/ops/auto/launcher.cjs, bin/lib/ops/auto/loop.cjs, test/sections/T120-compose-invariants.test.sh
- **Read first**: launcher.cjs:766-935, loop.cjs:1402-1413, workers.cjs:300-345, loop.cjs:1147-1154 (the agent path — explicitly OUT of scope here)
- **Approach**: composeScriptSpawn passes an enumerated writable list (`.gos/cache` + proven points); the refusal predicate is scoped to the script-spawn compose call: writable ⊆ enumerated set AND contains no ancestor of `.gos` itself. The agent path (`loop.cjs:1150-1153` restricted `[.gos, .gos/logs]`) is explicitly exempted this phase — its state-tamper surface is pre-existing trust-model territory (identityDiff + crashed-advance + baseline guards), recorded as DI-3. `compose()` fails closed when `meta.writableShadowed` is non-empty. Invariants (workspace ro-bind; argv never carries `--unshare-pid`/`--unshare-all`) asserted in T120.
- **Done when**: `grep -n "writableShadowed" bin/lib/ops/auto/launcher.cjs` shows the fail-closed branch AND T120 asserts: script-spawn compose refuses a bare-`.gos` ancestor entry, agent-path compose still passes unchanged, both invariants hold
- **Depends on**: none

#### T3: default-detach survival (child contract + sentinel + rotation)
- **Covers**: D-109, R-01
- **Files**: bin/lib/ops/auto/cli.cjs, bin/lib/ops/auto/loop.cjs, bin/lib/core/locales/{en,zh}.cjs, test/sections/T123-auto-detach.test.sh
- **Read first**: cli.cjs:355-400, loop.cjs:386-520, loop.cjs:395 (log path), spawnrun.cjs:171-183
- **Approach**: default `detach=true`, `--fg` opts in; detacher forwards original argv minus detach-class flags plus `--fg` on the child argv (forward-equivalence asserted — no re-detach chain); child writes a lock-acquired sentinel; parent bounded-waits (5s), forwards output, exits non-zero on missing sentinel ("started" is proven by lock, not fork); run-log rotation keep-last-N at detach start.
- **Done when**: T123 proves: child argv carries the opt-out flag (negative invariant vs re-detach), sentinel surfaces a simulated lock refusal to the parent's exit code, rotation prunes to N
- **Depends on**: none

#### T4a: branch reap mechanism
- **Covers**: D-110, R-01 (mechanism half)
- **Files**: bin/lib/ops/branch-reap.cjs, bin/gos.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs, bin/lib/core/state.cjs, bin/lib/nav/registry-consts.cjs, bin/lib/ops/index.cjs
- **Read first**: bin/lib/ops/push.cjs:236-255, store.cjs run-lock API (store.cjs:1027+), lock.cjs holder shape
- **Approach**: `reap [--dry-run|--apply] --base <ref>`: tree-membership under `GIT_NO_REPLACE_OBJECTS=1` (tier-1 refused outright when refs/replace or info/grafts non-empty; unborn/no-base fails loud); `--apply` requires fresh base + no live run-lock + namespace exemptions (`chain/*`, `refs/reaped/*`, active-task branch, worktree-checked-out incl. pin-worktrees); deletions land as `refs/reaped/<branch>`; output JSON `action: delete|manual|keep` + argv-array revive commands; dry-run default; census + pack-check for the new file.
- **Done when**: `grep -n "GIT_NO_REPLACE_OBJECTS" bin/lib/ops/branch-reap.cjs` matches AND `node bin/gos.cjs branch reap --dry-run --base origin/main` runs on this repo printing JSON without mutating anything
- **Depends on**: none

#### T5a: dig-closure floor mechanism
- **Covers**: D-106, R-01 (mechanism half)
- **Files**: bin/lib/knowledge/decisions.cjs, bin/lib/ops/gate.cjs
- **Read first**: gate.cjs:1890-2010 (floor v3 + the registry-EXternal dig-floor precedent at 1984-1991), decisions.cjs:45-96 (digEvidenceErr/digAnchorErr), store stamps keying (store.cjs:200-205 — spawnId-keyed, hex64, NOT reusable here)
- **Approach**: decision records gain `dug_at` + dig-object hash at `decision add` time; the freeze check compares `dug_at < freeze_at` (no store stamps — their shape is spawnId-keyed telemetry with 1000-entry eviction, unfit for decision anchoring; missing `dug_at` reads pre-era and grandfathers loudly). Recording requires deepen line in closed state AND ≥1 dig object (zero anchors = refusal); `--dig-waiver` refused under marker env. Check sits registry-external (dig-floor precedent side).
- **Done when**: `grep -n "dug_at" bin/lib/knowledge/decisions.cjs` matches AND `grep -n "dig-closure" bin/lib/ops/gate.cjs` matches the external check
- **Depends on**: none

#### T6: THINK-trip triage (store 2026-11-09T09:17)
- **Covers**: R-01
- **Files**: .gos/task/p21/think-trip-triage.md, .gos/task/p21/evidence/, test/sections/T127-think-trip.test.sh
- **Read first**: store.json breaker records, loop.cjs:793-827, the section-runs log window 20261109T09* (machine-local — harvest first)
- **Approach**: harvest the breaker record + matching log window into evidence/ (the dogfood store is the only source); reproduce on a fixture; land cause as code fix + regression assertion or documented non-code cause with fixture proof.
- **Done when**: the triage doc contains grep-able lines `root-cause:` and `evidence:` naming its regression section AND (if code) the T127 reproduction goes green after the fix
- **Depends on**: none

#### T9a: triage ledger (classification only, zero code)
- **Covers**: D-107, R-01 (classification half)
- **Files**: .gos/task/p21/triage-ledger.md
- **Read first**: the 95-failure distribution in the 5419521c head log, the failing sections' sources
- **Approach**: classify each of the 95 into families with a legal exit each (fixed-by-R1 / fixed-by-R2 / worktree-conversion / XDG-fixture-conversion); no skips, no writable widening. Ledger rows: section, failure count, family, planned exit, owning task.
- **Done when**: ledger accounts for 95/95 with every row naming a legal exit and an owning task (T9b/T9c/T7-covered-by-R1/R2)
- **Depends on**: none

### Wave 2 (depends on Wave 1)

#### T2: GOS_AUTO_* registry + source-side Class S whitelist
- **Covers**: D-107, R-01
- **Files**: bin/lib/ops/auto/launcher.cjs, bin/lib/ops/auto/loop.cjs, test/run-sections.sh, test/sections/T124-env-registry.test.sh
- **Read first**: launcher.cjs:66-71, loop.cjs:1414-1422 (post-T1 shape), spawnreg.cjs (ACK_WAIT env et al must join the registry), redteam.cjs timeout env, run-sections.sh:107-111
- **Approach**: single exported `ALL_GOS_AUTO_ENV` registry covering launcher/loop/redteam/ratify/workers/cli/breaker/core/spawnreg literals; Class S spec env keeps marker + spawnId only; run-sections.sh unsets from the registry at runtime + grep-able warning on survivors; T124 asserts every `GOS_AUTO_` literal under bin/ ⊆ registry (drift checker takes a target root argument so scratch-copy negatives work).
- **Done when**: `grep -n "ALL_GOS_AUTO_ENV" bin/lib/ops/auto/launcher.cjs` matches AND `bash test/run-sections.sh T124-env-registry` passes AND the scratch-copy negative reds
- **Depends on**: T1

#### T4b: branch reap proof section
- **Covers**: D-110, R-01 (proof half)
- **Files**: test/sections/T121-branch-reap.test.sh
- **Read first**: T4a's branch-reap.cjs
- **Approach**: fixture repos only (real-repo dry-run is NOT asserted here — the branch set changes as P21's own PRs land; it moves to T-4's machine-local verification step). Cases: replace-ref refusal, stale-base refusal, live-lock refusal, chain/* exemption, worktree-checked-out exemption, ref-revive past `git gc --prune=now --aggressive`, JSON shape with argv-array commands.
- **Done when**: all seven cases green in T121
- **Depends on**: T4a

#### T5b: dig-closure negative cases
- **Covers**: D-106, R-01 (proof half)
- **Files**: test/sections/T122-dig-closure-floor.test.sh, skills/gos-think/reference/dialogue-protocol.md
- **Read first**: T5a mechanism, dialogue-protocol.md closed-state line update (skills/gos-think/reference/dialogue-protocol.md — deepen line semantics)
- **Approach**: five negatives — open deepen line, unanchored enumeration, waiver-only inside a marker session, forged post-freeze anchor (`dug_at` after freeze), omission card (zero anchors, closed line). Then D-106..D-110 pass the same floor via `gos gate section`.
- **Done when**: all five negatives red in T122 AND `node bin/gos.cjs gate section` passes with the floor active
- **Depends on**: T5a

#### T8: deny scoring command-kind only
- **Covers**: R-01
- **Files**: bin/lib/ops/auto/loop.cjs, bin/lib/ops/auto/launcher.cjs, test/fixtures/5419521c-deny-slice.log, test/sections/T125-deny-scoring.test.sh, .gitignore
- **Read first**: loop.cjs:1445-1465, launcher.cjs makeStreamDenyScanner, store breaker 2026-11-09T04:38 detail
- **Approach**: step-failing hits = `kind === 'command'` only (both `preTruncationDenyHits` and post-hoc scan); text hits stay reported. Fixture strategy: harvest the minimal deny-bearing lines from the machine-local full log into test/fixtures/ (census + charset clean); T125 feeds the fixture and asserts zero step-failing hits, plus a synthetic command-hit still fails.
- **Done when**: `grep -n "kind === 'command'" bin/lib/ops/auto/loop.cjs` matches AND T125 green over the tracked fixture AND the synthetic command-hit case reds before the gate
- **Depends on**: T1

#### T7: worktree helper topology
- **Covers**: D-108, R-01
- **Files**: test/run-sections.sh, test/sections/T126-worktree-helper.test.sh, bin/lib/ops/auto/workers.cjs, test/checks/manifest-coverage.sh
- **Read first**: run-sections.sh:36-56, 293-302 (manifest block — this task lands the Shared Manifest Contract), workers.cjs:366-430, engine.cjs:212
- **Approach**: helper = `git worktree add --detach` full checkout under TESTBASE + disk preflight; node_modules ro-bind/hardlink from the real repo; Class S compose pre-creates the absolute TESTBASE pin (asserted in the writable set); idempotent prefix prune + `git worktree prune` in the leak sweep; `GOS_SECTIONS_TREE_OVERRIDE` drives `head_tree`/`patch_sha` and relocates the manifest to `$TESTBASE/run-manifest.json` with `tree_source` + `pin` fields (contract above).
- **Done when**: T126 proves a self-repo section passing inside the restricted sandbox via the helper AND the manifest shows `tree_source: "pinned"` AND worktree count returns to baseline after teardown
- **Depends on**: T1, T2

### Wave 3 (depends on Wave 2)

#### T9b: sandbox-fixable family conversions
- **Covers**: D-107, R-01
- **Files**: test/sections/*.test.sh, .gos/task/p21/triage-ledger.md
- **Read first**: T9a ledger rows, T1/T2 landed surfaces
- **Approach**: verify each ledger row's failure actually clears under the landed R-1/R-2 surfaces; section edits only where the failure reveals a real defect (not sandbox noise); update ledger rows to landed state.
- **Done when**: every `fixed-by-R1/R2` ledger row verified green in a sandbox run (partial suite acceptable, filter by full name)
- **Depends on**: T9a, T7, T8

#### T9c: conversion families (worktree + XDG-fixture)
- **Covers**: D-108, R-01
- **Files**: test/sections/*.test.sh, .gos/task/p21/triage-ledger.md
- **Read first**: T7 helper, T100/T104/T105 fixture precedents
- **Approach**: convert self-repo sections to the worktree helper; convert machine-local-state sections to XDG/TESTBASE fixtures (lesson 047cbe80); no skips, no writable widening.
- **Done when**: every converted section green in the sandbox AND ledger rows updated
- **Depends on**: T9a, T7

### Wave 4 (depends on Wave 3)

#### T9z: baseline snapshot + manifest coverage + full green
- **Covers**: D-107, R-01 (acceptance half)
- **Files**: test/sections/baseline.json, test/checks/manifest-coverage.sh, test/sections/T25-map-selfcheck.test.sh, test/sections/T46-module-structure.test.sh
- **Read first**: T9b/T9c ledger end-state, the Shared Manifest Contract
- **Approach**: snapshot per-section pass counts; coverage script asserts sandbox manifest `sections_run` ≡ full `T*.test.sh` set (name+count) and per-section pass ≥ baseline; then the full sandboxed suite runs `Sections total: N passed, 0 failed`.
- **Done when**: `bash test/checks/manifest-coverage.sh "$TESTBASE/run-manifest.json"` exits 0 AND the sandboxed full suite prints 0 failed
- **Depends on**: T9b, T9c

#### T10a: run-record persistence
- **Covers**: R-01 (evidence half)
- **Files**: bin/lib/ops/auto/loop.cjs, bin/lib/ops/auto/store.cjs, test/sections/
- **Read first**: loop.cjs endWith paths, store.cjs:193+ schema validation, existing store schema test sections
- **Approach**: loop writes a per-run record (stages + VERIFY step status + end state) to the store; schema version bump with validator + census-clean new fields; this is the substrate T10b's gate reads (none exists today).
- **Done when**: a harness-driven run leaves a validated run record in a fixture store AND the schema assertion section passes
- **Depends on**: T9z (loop surface stable)

### Wave 5 (depends on Wave 4)

#### T10b: evidence-gated re-enable
- **Covers**: R-01 (gate half)
- **Files**: bin/lib/ops/auto/cli.cjs, bin/lib/core/locales/{en,zh}.cjs, test/sections/
- **Read first**: cli.cjs:96-158, T10a record shape
- **Approach**: `auto on` refuses while any layer TRIPPED **when run records exist** (latest must read INTENT→SHIP green with sandboxed VERIFY passed); cold start (no records yet) proceeds but logs a grep-able disposition line; breaker counter reset goes through an explicit `--reset-breakers` operator flag that records a disposition. Negative test plants a red record and asserts refusal.
- **Done when**: refusal branch + cold-start disposition + negative case green AND `grep -n "reset-breakers" bin/lib/ops/auto/cli.cjs` matches
- **Depends on**: T10a, T3, T6, T9z, T5b (R-7 precedes re-enable per R-8; T4a/T4b exempt — no re-enable coupling, recorded here)

#### T11: dogfood green cycle + re-enable
- **Covers**: R-01, T-3b
- **Files**: .gos/task/p21/dogfood-runbook.md
- **Read first**: T-6 acceptance, T3 detached flow
- **Approach**: one full auto cycle on the dogfood store in detached mode; mid-VERIFY SIGTERM restart (T-3b); capture store snapshot JSON with counters zero + green run record; `gos auto on` through the evidence gate; runbook carries the grep-able line `T-3b: sigterm-restart ok`.
- **Done when**: `grep "T-3b: sigterm-restart ok" .gos/task/p21/dogfood-runbook.md` matches AND store counters read zero AND last run record green
- **Depends on**: T10b

## Observable Truths

### T-1: sandboxed VERIFY writes its namespaced manifest
- **Verify**: harness run then `test -f "$TESTBASE/run-manifest.json" && jq -r .tree_source "$TESTBASE/run-manifest.json"` → `pinned`

### T-2: store VERIFY step reads passed
- **Verify**: `jq` over the store run record — `.verify.status == "passed"`

### T-3 / T-3b: detach survival + SIGTERM recovery
- **Verify**: `gos auto status` heartbeat age < threshold after terminal kill; `grep "T-3b: sigterm-restart ok" .gos/task/p21/dogfood-runbook.md`

### T-4: reap classifies and revives
- **Verify** (dogfood machine): `node bin/gos.cjs branch reap --dry-run --base origin/main | jq '.branches | length'` == `git branch --list | wc -l`; post-apply revive green in T121

### T-5: five negative floor cases refuse
- **Verify**: `bash test/run-sections.sh T122-dig-closure-floor` green

### T-6: green cycle + counters zero
- **Verify**: `gos auto status` → mode on, no TRIPPED layer, counters zero
