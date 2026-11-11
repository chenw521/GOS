# Plan: P19 — live pain bugs and archive integrity

> **Date**: 2026-11-11 | **Based on spec**: .gos/task/p19/spec.md
> Plan-attack round 4 (RT4) dispositions folded in: predicate/callers split
> per RT4-F3, idempotency fixture ownership per RT4-F2, T0/T9 done-when
> pinned per RT4-F1/F12, W1 serialization per RT4-F4, interface docking per
> RT4-F8/F9, CI depth per RT4-F6, fallback fixtures per RT4-F7, spec §9
> README.md item voided by verified fact per RT4-F10.

## Decision Inventory

- [x] D-61: PR-body closing channel + ceremony re-point → T3
- [x] D-62: structural-delta obligation → T1, T2
- [x] D-63: mechanized dig floor → T8
- [x] D-64: completed_at cure (merge + catch + disjunctive re-key) → T7
- [x] D-65: -der single-instance repair → T9

## Requirement Claims

- [x] R-01: phase goal → T0, T10 (registration + closeout)
- [x] R-60: structural obligation → T1, T2
- [x] R-61: PR-body channel/ceremony → T3
- [x] R-62: completed_at cure → T7
- [x] R-63: -der repair → T9
- [x] R-64: help short-circuit → T4
- [x] R-65: phase rename → T5
- [x] R-66: census optional + hotfix removal → T6
- [x] R-67: dig floor → T8

## Patterns to Follow

- Test sections: bash, test/sections/T*.test.sh style; NEW sections take
  numbers T109+ (tree max is T108; verify with `ls test/sections/`).
- Locales: every user-facing verdict/hint ships BOTH en and zh-CN keys
  (verdict-catalog discipline). W1 note (RT4-F4): T3 serializes after T5 —
  both add locale keys; never run them concurrently against the same tree.
- Frozen-string contracts: hint text asserted byte-exact in sections.
- Module rules: global fn-name uniqueness, no nav→ops edges, ledger
  sections (T46 scan set, T25) updated in the same change when declared
  functions move.
- Stage commits stage only declared Files (ADD_PATHS discipline); plan
  Files snapshots are BUILD-immutable except via stage-back.
- Landing: PR-only; squash subjects pass
  `bash test/checks/push-lint-squash.sh --subject "<candidate>"` BEFORE
  `gh pr merge --squash`.
- Spec §9 correction (RT4-F10, verified): `renderProjectViews` writes only
  machine-local `.gos/project/{DECISIONS,ROADMAP,REQUIREMENTS}.md`
  (views.cjs:382-465); `phase rename` has NO tracked render surface — the
  spec §9 README.md declaration item is void; T5 declares no tracked file.

## Execution Waves

### Wave 1 (parallel except T3-after-T5; file ownership serialized where noted)

#### T0: register observable truths
- **Covers**: R-01
- **Files**: .gos/state.json
- **Read first**: spec §6; skills/gos-plan/reference/truths-format.md;
  bin/lib/knowledge/truth.cjs:50-70 (add shape: {id, description,
  verified:false, evidence:null} — artifact paths arrive at verify time)
- **Approach**: register T-01..T-08 from spec §6 via `gos truth add`
  (description carries the expected/verify contract text).
- **Done when**: `python3 -c "import json;s=json.load(open('.gos/state.json'));ts=s['observable_truths'];assert len(ts)==8 and all(t['verified'] is False and t['evidence'] is None for t in ts);print('ok')"`
  → ok
- **Depends on**: none

#### T1: structural-delta predicate core (ADD-ONLY; no consumer changes)
- **Covers**: D-62, R-60
- **Files**: bin/lib/ops/changelog-core.cjs, test/sections/T109-changelog-structural.test.sh
- **Read first**: bin/lib/ops/changelog-core.cjs (parseChangelog,
  validateStructure — DO NOT MODIFY in this task), T53/T55 fixtures
- **Approach**: new export with pinned interface (RT4-F8):
  `batchAddsChangelogRecord(headText, baseText, opts) -> {ok: boolean, reason: string|null}`
  — true when ≥1 bullet in [Unreleased] OR the newest version section is
  new vs base (promote shape); "new" = bullet text absent from the ENTIRE
  base text; `opts.taskRefs: string[]` (normalized `D-NN`/`R-NN` upper) —
  when non-empty, the new bullet's ref group must intersect it; opts
  accepts `noBaseText` (null) → file-shape fallback verdict
  ("unreleased-nonempty") for non-git callers. Injectable, deterministic.
- **Done when**: `grep -c "function batchAddsChangelogRecord" bin/lib/ops/changelog-core.cjs` = 1
  AND T109 green — fixtures: new-bullet-passes / no-new-bullet-fails /
  rewritten-bullet-fails / promote-shape-passes / cross-task-refs-fails /
  file-shape-fallback-both-ways / reason-populated-on-fail
- **Depends on**: none

#### T3: ceremony re-point + neutralizer guard
- **Covers**: D-61, R-61
- **Files**: bin/lib/ops/push.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh-CN.cjs, .github/PULL_REQUEST_TEMPLATE.md, templates/git/PULL_REQUEST_TEMPLATE.md, test/sections/T76-*.test.sh, test/sections/T101-*.test.sh
- **Read first**: push.cjs:259-261 (archivePushHint), T76 + T101 fixtures
- **Approach**: archivePushHint frozen copy teaches the PR flow (branch →
  PR → squash with `bash test/checks/push-lint-squash.sh --subject` guard)
  + discipline line "refer with refs #N unless the PR must close it —
  closing keywords belong in the PR body"; branches on `git remote`
  presence (absent → keep the plain-git gos push line); PR template
  comment gains the same guidance; T76 asserts the new frozen copy; T101
  gains a guard assertion that neutralizeIssueTriggers is byte-unchanged.
- **Done when**: `grep "closing keywords belong in the PR body" bin/lib/core/locales/en.cjs` matches
  AND T76 green AND T101 green (guard assertion present: `grep -c "neutralizeIssueTriggers" test/sections/T101-*.test.sh` ≥ 2)
- **Depends on**: T5 (locale file serialization, RT4-F4)

#### T4: help-flag short-circuit
- **Covers**: R-64
- **Files**: bin/gos.cjs, test/sections/T110-help-shortcircuit.test.sh
- **Read first**: bin/gos.cjs main() ordering (verifyCommandRegistry →
  classification → guardCwd — insert between registry and guardCwd),
  bin/lib/nav/help.cjs (cmdHelp), T63 (help/registry self-checks)
- **Approach**: exact tokens `--help`/`-h` recognized only in flag
  position (value positions exempt; `--` terminates); route to
  cmdHelp([cmd]) BEFORE guardCwd/lock; registered commands only (unknown
  keeps non-zero exit); `gos help --json` and topic pages unchanged;
  write+exec class never execute.
- **Done when**: T110 green — `node bin/gos.cjs status --help` prints help
  and does NOT run status; `node bin/gos.cjs gate --help` never executes
  gate; value-position case does reach the command; unknown + --help
  exits non-zero; `node bin/gos.cjs help --json` output unchanged
- **Depends on**: none

#### T5: phase rename verb
- **Covers**: R-65
- **Files**: bin/lib/knowledge/phase.cjs, bin/lib/nav/registry-consts.cjs, bin/lib/core/state.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh-CN.cjs, test/sections/T111-phase-rename.test.sh
- **Read first**: phase.cjs amend block (:104-125), claim name-prefix
  matching, archive.cjs:589 phase-by-name lookup, views.cjs:382-465
  (render surface — machine-local only), T71/T37/T2 fixtures
- **Approach**: `rename <n> "<new name>"` pending-only; refuse active/done/
  parked; refuse equality/prefix collision with ANY existing phase name;
  name grammar (keep `Pn:` prefix shape, length cap, no newlines); registry
  entry + usage lines; prints old→new; `--expect "<old>"` guard; views
  re-rendered via the same renderProjectViews call amend uses.
- **Done when**: T111 green — rename applies + project views re-rendered;
  collision with a done phase refused; active refused; --expect mismatch
  refused; `node bin/gos.cjs help phase` shows rename; T29 registry
  self-check green
- **Depends on**: none

#### T6: census optional axis + hotfix removal
- **Covers**: R-66
- **Files**: census.json, test/pack-check.sh, .github/workflows/ci.yml, test/sections/T66-*.test.sh
- **Read first**: test/pack-check.sh:96-131 (dir-probe + transient escape),
  census.json entries, ci.yml:95
- **Approach**: entries gain `optional: true` semantics — legal ONLY on
  paths covered by .gitignore (tracked-path optional = pack-check FAIL);
  marks `.gos/cache`; subsumes the derived transient rule per entry (no
  stacking); source-3 gitignore reconciliation stays unconditional; remove
  ci.yml:95 mkdir line.
- **Done when**: `rm -rf .gos/cache && bash test/pack-check.sh` rc 0;
  negative control: marking a tracked entry optional → pack-check
  non-zero; `grep -c "mkdir -p .gos/cache" .github/workflows/ci.yml` = 0
- **Depends on**: none

### Wave 2 (single owner of commit/archive/gate + their legacy fixtures)

#### T7: completed_at cure
- **Covers**: D-64, R-62
- **Files**: bin/lib/task/commit.cjs, bin/lib/task/archive.cjs, bin/lib/ops/gate.cjs, test/sections/T112-completed-at-cure.test.sh, test/sections/T8-phase-archive.test.sh, test/sections/T27-*.test.sh, test/sections/T50-*.test.sh, test/sections/T61-*.test.sh
- **Read first**: commit.cjs:440-560 (fromCommit call + advance write),
  archive.cjs:309-365 (idempotency + half-tx), gate.cjs:696-713 (doneIdle),
  T8-phase-archive.test.sh:170 (-2 suffix fixture — its completed_at-reset
  premise changes under the two-part condition: migrate it to assert the
  new early-return + repair split), T27/T50/T61 idempotency fixtures
- **Approach**: (a) after cmdArchive({fromCommit:true}) returns, re-read
  disk state and merge with PINNED field lists — archive-won:
  current_stage/completed_at/cleared checkpoints/STATE_PATH_FIELDS
  rewrites/evidence paths; commit-won: everything else; (b) fromCommit
  catch: if a dest containing the tid materialized, run half-tx completion
  (stamp + rewrite + DONE) before advancing, else refuse the advance;
  (c) doneIdle and tid-idempotency become DISJUNCTIVE:
  `DONE && (completed_at || (archiveDirContainsTid && canonicalPathsResolveIntoThatArchive))`;
  tid-idempotency early-return requires the two-part condition — stale
  paths fall through to repair; slug idempotency unchanged.
- **Done when**: T112 green — Lv1 chain-archive fixture lands completed_at
  + rewritten paths + surviving approvals/spec_sha256/plan_snapshot/
  completed_stages; planted-tid-with-live-paths does NOT idle; stamp-only
  idles; catch-with-dest completes half-tx; catch-without-dest refuses
  advance; migrated T8-phase-archive -2 fixture green under the new
  semantics
- **Depends on**: none (file-serialized behind W1 by wave order)

### Wave 3 (owns the obligation cutover; after T1 interface + T7 files)

#### T2: obligation cutover + consumer rewiring + CI wiring
- **Covers**: D-62, R-60
- **Files**: bin/lib/ops/changelog-core.cjs, bin/lib/ops/gate.cjs, bin/lib/task/archive.cjs, bin/lib/task/changelog.cjs, bin/lib/core/lock.cjs, bin/lib/core/state.cjs, .github/workflows/ci.yml, test/sections/T53-*.test.sh, test/sections/T54-*.test.sh, test/sections/T55-*.test.sh, test/sections/T57-*.test.sh, test/sections/T12-wiring.test.sh, test/sections/T46-module-structure.test.sh, test/sections/T91-ledger-reconcile.test.sh, test/sections/T107-auto-dispatch.test.sh
- **Read first**: T1's batchAddsChangelogRecord contract; gate.cjs:1097-1121
  (changelog-lint verdict wiring); archive.cjs:225-231 (SHIP ritual);
  T53:139 / T54 / T55 S3+G4 / T57:57 fixtures (all reference the clock
  obligation — migrate them IN THIS TASK)
- **Approach**: validateStructure drops the clock obligation (format-only;
  today-check leaves standalone lint entirely); SHIP ritual rewritten on
  the shared predicate, base = task_head vs working tree, id set =
  state decisions+requirements claims; gate --audit gains the structural
  obligation check (base: GOS_CHANGELOG_BASE env override, else HEAD^1;
  id set = parse .gos/state.json — parse failure degrades the refs filter
  to a LOUD exempt line, never silent); fallback verdicts pinned with
  named fixtures: unborn/zero-parent base → exempt + loud line;
  unresolvable HEAD^1 on main (shallow) → fail-closed; missing task_head
  → fail-closed with re-claim guidance; non-git → file-shape fallback.
  CI: gate job gets fetch-depth: 0; same job branches on
  github.event_name (push → base HEAD^1; pull_request →
  `git diff <mb>...${{ github.event.pull_request.head.sha }}`, never the
  merge ref); changelog path via root-anchored resolver.
- **Done when**: T53/T54/T55 migrated green (no `today's obligation`
  assertions remain: `grep -rc "today's obligation" test/sections/` = 0);
  T57 G3 flipped green; SHIP fixture: fresh uncommitted bullet passes;
  `grep "GOS_CHANGELOG_BASE" .github/workflows/ci.yml` matches;
  `grep "pull_request.head.sha" .github/workflows/ci.yml` matches;
  `grep -A2 "fetch-depth" .github/workflows/ci.yml` shows 0 on the gate
  job; unborn/shallow/missing-task_head/non-git fixtures assert their
  named verdict lines
- **Depends on**: T1, T7

### Wave 4 (owns decisions/commit/gate after T7/T2)

#### T8: card-preflight dig floor
- **Covers**: D-63, R-67
- **Files**: bin/lib/knowledge/decisions.cjs, bin/lib/task/commit.cjs, bin/lib/ops/gate.cjs, bin/lib/core/state.cjs, templates/spec-template.md, skills/gos-think/SKILL.md, test/sections/T113-dig-floor.test.sh, test/sections/T3-decision.test.sh, test/sections/T10-security-e2e.test.sh, test/sections/T106-auto-spawn-channel.test.sh, test/sections/T12-wiring.test.sh, test/sections/T14-state-b.test.sh, test/sections/T17-semantic-engine.test.sh, test/sections/T22-map-gate-impact.test.sh, test/sections/T23-concerns.test.sh, test/sections/T31-map-gate.test.sh, test/sections/T33-map-manifest.test.sh, test/sections/T39-render-park.test.sh, test/sections/T54-changelog-add.test.sh, test/sections/T55-changelog-lint.test.sh, test/sections/T88-autorender.test.sh, test/sections/T96-lang-boundary.test.sh
- **Read first**: decisions.cjs (add/amend constructors :169 — verify state
  schema survival of NEW fields on decision objects BEFORE relying on
  them), commit.cjs THINK freeze block (:445-475),
  gate.cjs:1632-1640 (probeSpecFloor — do NOT extend the probe sequence)
- **Approach**: decisions.cjs exports `DIG_FLOOR_ERA` (ISO timestamp of
  T8's landing; single home, consumed by both decision add and the freeze
  check — no dual brain, RT4-F9); decision records gain `dig` (evidence
  object: ≥1 {command, output_excerpt} + resolvable file:line anchor;
  explicit user-ruling citation or waiver tokens accepted as alternates)
  and `born_at`; `gos decision add` validates dig evidence at write time;
  spec freeze runs a SEPARATE check (outside SPEC_CARD_FLOORS): every
  decision born after DIG_FLOOR_ERA carries dig evidence; legacy + pre-era
  grandfather with a loud advisory; the check reads state decisions AND
  spec `## Decisions` headings.
- **Done when**: T113 green — post-era decision without dig refused at add
  AND at freeze; grandfathered decision passes with advisory line;
  evidence-object shape enforced (free-text sentence rejected);
  `grep -c "DIG_FLOOR_ERA" bin/lib/knowledge/decisions.cjs` ≥ 2
- **Depends on**: T7, T2

### Wave 5 (data repair + closeout; no code-file overlap)

#### T9: -der archive repair ritual (manual, local-only)
- **Covers**: D-65, R-63
- **Files**: .gos/archive/2026-11-10-v1.0.0-task-commit-advance-destination-der/task/1a2e46f3/state.json, .gos/archive/2026-11-10-v1.0.0-task-commit-advance-destination-der/task/1a2e46f3/PROVENANCE.md, .gos/concerns.md, .gos/logs/truth-receipts.md, .gos/task/p19/evidence/t4.sh
- **Read first**: spec R-63; `git show 493a9e7:.gos/state.json`
- **Approach**: snapshot = byte-faithful from `git show 493a9e7:.gos/state.json`
  plus exactly two added fields: completed_at = 2026-11-10T05:42:18Z and
  completed_at_retro: true; PROVENANCE.md with fixed front-matter keys
  (class: zone-destroyed-pre-archive, sources: [493a9e7,
  truth-receipts], lost: [zone payload]); roster concern naming all 6
  instances; manual receipt appended.
- **Done when**: pinned byte-level check (RT4-F12) passes verbatim:
  `diff <(git show 493a9e7:.gos/state.json) <(sed '/"completed_at"/d;/completed_at_retro/d' .gos/archive/2026-11-10-v1.0.0-task-commit-advance-destination-der/task/1a2e46f3/state.json)` → empty
  AND `python3 -c "import json;a=json.loads(open('.gos/archive/2026-11-10-v1.0.0-task-commit-advance-destination-der/task/1a2e46f3/state.json').read());b=json.loads(__import__('subprocess').check_output(['git','show','493a9e7:.gos/state.json']));assert set(a)-set(b)=={'completed_at','completed_at_retro'};print('ok')"` → ok
  AND PROVENANCE.md carries the three front-matter keys AND `grep "1a2e46f3" .gos/concerns.md` matches
- **Depends on**: T7 (retro-stamp semantics must match the landed idle semantics)

#### T10: closeout suite + truths evidence
- **Covers**: R-01
- **Files**: .gos/cache/run-manifest.json, CHANGELOG.md
- **Read first**: spec §6; .gos/lessons.md (suite rules)
- **Approach**: full-suite run in the MAIN session only (serialized,
  never parallel with anything); stage evidence artifacts BEFORE the run;
  truth verify replays T-01..T-08 with evidence artifact paths (T-04 via
  manual local receipt); changelog entry for the batch.
- **Done when**: full suite green (run-manifest failed_sections empty);
  `node bin/gos.cjs truth verify` all green; CHANGELOG [Unreleased] holds
  the batch bullet
- **Depends on**: T1, T2, T3, T4, T5, T6, T7, T8, T9

## Observable Truths

### T-01: structural obligation across midnight
- **Expected**: batch adding a new bullet passes with a stale stamp; batch adding none fails
- **Verify**: T109 fixture run — both directions assert via injected base/head

### T-02: Lv1 chain archive lands completed_at + paths + commit fields
- **Expected**: landed state carries completed_at, archive-rewritten paths, surviving approvals/spec_sha256/plan_snapshot/completed_stages
- **Verify**: T112 sandbox fixture asserts all field groups on the landed state.json

### T-03: disjunctive idle semantics
- **Expected**: stamp-only idles; tid+paths idles; planted tid with live-zone paths does not idle
- **Verify**: T112 gate fixtures — three assertions, one per shape

### T-04: -der payload restored (local-only, non-replayable)
- **Expected**: task/1a2e46f3/state.json byte-equal to 493a9e7 plus exactly {completed_at, completed_at_retro}; PROVENANCE.md present
- **Verify**: T9's pinned diff + key-set commands, recorded in truth-receipts

### T-05: help never executes
- **Expected**: every registered command with --help/-h prints help, rc 0, zero side effects; value-position tokens exempt; unknown commands exit non-zero
- **Verify**: T110 section green (includes write-class and exec-class probes)

### T-06: rename verb safe
- **Expected**: pending rename applies + views re-render; collisions and non-pending refused; --expect guard works
- **Verify**: T111 section green

### T-07: fresh checkout passes census without hotfix
- **Expected**: .gos/cache absent → pack-check green; tracked-entry-optional negative control red; ci.yml mkdir gone
- **Verify**: `rm -rf .gos/cache && bash test/pack-check.sh` rc 0; negative control rc != 0

### T-08: dig floor enforced
- **Expected**: post-era decisions without evidence-object dig refused at add and freeze; grandfathered pass with advisory
- **Verify**: T113 section green

## Risks

- probeSpecFloor interplay (T8) — the floor must stay OUT of the probe
  sequence; if the freeze hook shape resists, fall back to a pre-freeze
  check in cmdCommit before stamping (same contract).
- T2 CI wiring needs a real PR run to exercise the head-sha path —
  schedule the P19 PR itself as the live carrier; watch gh pr checks to
  terminal-green before merge.
- T8-phase-archive -2 fixture migration (T7) is the highest-blast-radius
  legacy edit — if additional sections surface red after the semantics
  change, enumerate them honestly in a plan stage-back rather than
  bulk-editing outside declared Files.
- Section runs are strictly sequential; full suite ONLY in T10 main
  session; every suite tee goes to .gos/cache/section-runs/ (never pipe
  through truncating filters).
- T9 touches only machine-local zones — no census/flip implications; keep
  it out of stage commits (ADD_PATHS hygiene).
