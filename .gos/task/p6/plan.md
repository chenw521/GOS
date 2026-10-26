# Plan: P6 — Comment Hygiene and Coding Standards (ai-trace lint + sweep)

> **Date**: 2026-10-26 | **Based on spec**: .gos/task/p6/spec.md (rev 2 — plan-attack fixes folded in)

## Decision Inventory

<!-- Verify every D-NN from spec has a task (Decision Coverage Gate) -->

- [x] D-21: two-tier patterns (strong anywhere, weak comment-only) → T1
- [x] D-22: carve-outs (.changes.md/CHANGELOG/.gos + sidecar count) + categorized whitelist → T1, T4, T5
- [x] D-23: whitelist-as-tracker, blocking day one, shrink-on-main → T4, T5, T10, T11, T12, T13
- [x] D-24: three-way disposition + frozen-string audit → T7, T9, T10, T11, T12
- [x] D-25: seeding entry stays `gos init coding`; setup hint line → T3
- [x] D-26: self-repo lint covers templates/; books gain missing forms → T2, T8
- [x] D-27: census-first; `--emit-baseline` generates landing whitelist + regen guard → T4, T5
- [x] D-28: exact-equality maxHits; bare Wave N demoted to tier B; plan-format exempt → T1, T4, T8
- [x] D-29: backfill into CHANGELOG.md [Unreleased] + tracked sweep ledger; digit-free teaching → T2, T7, T10, T11, T12, T13
- [x] D-30: sweep harness mechanizes batch discipline → T7, T8
- [x] D-31: amended reading — hint says `gos init coding`; user-repo enforcement parked DI-1 → T3, T13

## Requirement Claims

<!-- Each R-NN must be claimed by ≥1 task. gos gate requirements checks at Lv4. -->

- [x] R-01: root-cure AI-process artifacts (lint + sweep + books + seeding hint) → T13 (goal closure; all tasks contribute)
- [x] R-40: ai-trace-lint.sh two-tier, fail-closed, --json, cjk-lint homolog → T1, T4, T8
- [x] R-41: categorized whitelist, exact maxHits, ghost detection, shrink discipline → T4, T5, T8
- [x] R-42: gate all runs ai-trace-lint as blocking, self-repo scope → T6, T8
- [x] R-43: three-way disposition sweep of bin/ + test/ in batches with changelog backfill → T7, T9, T10, T11, T12, T13
- [x] R-44: books teach the full anchor ban; setup onboarding hints `gos init coding` → T2, T3, T8

## Patterns to Follow

- Lint structure: test/checks/cjk-lint.sh (bash wrapper: args + `git ls-files` listing;
  embedded node helper: ALL pattern matching + whitelist semantics + JSON). Copy the
  shape, not the grep — ai-trace matching lives 100% in node (no `grep -P` dialect debt).
- Gate wiring: bin/lib/ops/gate.cjs selfRepo block (~line 1118, cjk-lint peer) —
  execFileSync bash, tail-3 evidence, `core.gateFail()` object failures, last-line pass echo.
- Whitelist file under .gos/ flips ignored→tracked via `node bin/gos.cjs track`
  (never hand-negate .gitignore); census.json reconciled by test/pack-check.sh.
- Test sections: test/sections/T*.test.sh (next free: T102), sourced assert helpers,
  run via `bash test/run-sections.sh --affected` per batch; assertions on lint output use
  machine-mode fields + exit codes only — never unescaped brackets in assert_contains
  (lesson 265a5dd3).
- Locale keys: bin/lib/core/locales/en.cjs + zh.cjs (`setup.onboard.*` naming),
  rendered via `core.t()` in bin/lib/ops/setup.cjs onboarding().
- CHANGELOG entries: single bullet, category verb first, `[YYYY-MM-DD]` tail, trace-refs
  `(...)` carrying ONLY D-nn/R-nn tokens; entry bodies must stay validator-clean —
  changelog-core.cjs bans `§\d`, `T-\d+`, `DI-\d+`, and `wave n`/`phase` narration in
  body text (BARE_T_RE/SECTION_MARK_RE/NARRATION_RES, changelog-core.cjs:80-86). Deleted
  anchor ids therefore ride the tracked sweep ledger, never the entry body.
- Machine views: `--json` = violations only (gate + failure evidence); `--emit-hits` =
  full per-line hit census incl. registered hits (harness + disposition consumers);
  `--emit-baseline` = whitelist regeneration. One flag per consumer class, no overloading.

## Execution Waves

### Wave 1 (parallel, no deps)

#### T1: ai-trace lint detection core
- **Covers**: D-21, D-22 (carve-out half), D-28 (tier demotion + plan-format exemption), R-40
- **Files**: test/checks/ai-trace-lint.sh
- **Read first**: test/checks/cjk-lint.sh (structural homolog), .gos/task/p6/spec.md Approach §1
- **Approach**: new file (cjk-lint homolog). Bash wrapper (arg parse, `git ls-files -z` loop, tmp hits file — cjk-lint
  shape) + node helper holding every pattern: tier A anywhere (generalized bracket family
  `\[[A-Za-z]+[ -]?[0-9/]` case-insensitive REVIEW, `RT3-F7`/`R3-F1` dash compounds,
  `spec §3.4`/`§6a-2` citations, `W1-T5` compounds); tier B comment lines only (bare
  `W\d+`/`T\d+`/`Wave \d+`, bare + parenthesized `(D|R|B|F)-\d+` incl. slash compounds,
  narrative phrases `this (phase|wave|task) (adds|ships|introduces)`). Comment-line
  detection per filetype in node: `#` for sh/yml/yaml (unknown text types default `#`),
  `^\s*//` + `/* */` for the JS family, markdown scans all lines. Path carve-outs:
  `CHANGELOG.md`, `.changes.md`, `.gos/**` — with a sidecar line printing the `.gos/**`
  anchor hit count so exempt-layer debt stays visible. Plan-format structural exemption:
  `### Wave N` headings and `Covers:`/`Depends on:` lines inside *.md never count as hits.
  `--json` mode (violations array only), exit 0/1, fail-closed on git/read errors.
  Whitelist hook point stubbed (hits recorded with path:line:tier fields). The lint's
  own source + docs use digit-free placeholder spellings.
- **Done when**: `bash test/checks/ai-trace-lint.sh --help` prints usage AND a planted
  fixture with a bracket anchor in a scratch tracked file yields `--json` violation with
  `"tier":"A"` AND a `// W3 note` comment line yields `"tier":"B"` AND the same bare id
  in a code line yields no violation AND clean tree exits 0 (self-check in task sandbox)
- **Depends on**: none

#### T2: coding-standards books — placeholder spellings + missing banned forms
- **Covers**: D-26 (books half), D-29 (teaching half), R-44
- **Files**: templates/coding-standards/00-general.md, templates/coding-standards/node.md, templates/coding-standards/python.md, templates/coding-standards/shell.md
- **Read first**: .gos/task/p6/spec.md Approach §5, templates/coding-standards/00-general.md §"Ticket and review anchors"
- **Approach**: replace digit-bearing examples (`[REVIEW M1]` → `[REVIEW Mn]`,
  `T-123` → `T-nnn`, `JIRA-455` → `JIRA-nnn`) in all books; extend the banned-forms
  section in 00-general.md to name every lint shape digit-free: bracket decision anchors
  (`[D-NN]`, `[REVIEW Mn]`), bare and parenthesized decision/requirement ids (`D-nn`,
  `(R-nn/F-nn)`), wave/task ids (`Wn`, `Wn-Tn`), dash compounds (`RTn-Fn`),
  spec-section citations (`spec §n.n`), task-narrative phrases ("this wave adds…"),
  with the rule: lineage lives in commit bodies and CHANGELOG, WHAT stays in comments.
  Per-language books each gain one digit-free banned + one compliant example pair.
- **Done when**: `grep -rE '\[[A-Za-z]+[ -]?[0-9/]|\b[DRBF]-[0-9]+\b|\b[WT][0-9]+\b|§[0-9]' templates/coding-standards/` returns 0 hits (oracle mirrors the tier-A/B grammar — hyphen and slash bracket forms, single-digit bare ids included) AND `grep -c 'REVIEW Mn' templates/coding-standards/00-general.md` ≥ 1 AND every book names ≥ 1 narrative-phrase ban
- **Depends on**: none

#### T3: setup onboarding hint — locale key pair + rendered helper
- **Covers**: D-25, D-31 (wording half), R-44
- **Files**: bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs, bin/lib/ops/setup.cjs
- **Read first**: bin/lib/ops/setup.cjs onboarding() step-4 tail, bin/lib/core/locales/en.cjs `setup.onboard.*`
- **Approach**: add one key pair `setup.onboard.codingHint` (en + zh) whose text names
  the seeding verb verbatim: "Seed the coding-standards book set into this repo: gos
  init coding" (zh copy mirrors the sentence; the command spelling stays verbatim).
  Print it once in onboarding() after the
  gates step. Rendering goes through a small exported helper `renderCodingHint()` in
  setup.cjs (returns the locale-resolved hint line; onboarding() consumes it) so the
  output path is assertable without a TTY. No wizard step, no new prompts — single
  master stays `gos init coding` (T69 coverage untouched).
- **Done when**: `grep -c "codingHint" bin/lib/core/locales/en.cjs bin/lib/core/locales/zh.cjs` = 1 each AND both locale values contain the literal `gos init coding` AND setup.cjs exports `renderCodingHint` consumed by onboarding() (grep both)
- **Depends on**: none

### Wave 2 (depends on Wave 1)

#### T4: whitelist semantics + `--emit-baseline` + `--emit-hits`
- **Covers**: D-22 (whitelist half), D-23 (tracker semantics), D-27, D-28 (equality), R-40, R-41
- **Files**: test/checks/ai-trace-lint.sh
- **Read first**: T1's landed helper, .gos/cjk-whitelist.json (entry shape precedent), .gos/task/p6/spec.md Approach §2
- **Approach**: extend the T1 helper. Whitelist `.gos/ai-trace-whitelist.json` — array of `{path, category,
  reason, ...}`; entry identity is the `(path, category)` pair: one path may carry
  several entries (e.g. bin/lib/core/state.cjs holds both an `in-flight-sweep` count
  over its ~38 anchor lines and a `frozen-string` line-pin on the lessonsAnchor
  contract line). Categories: `in-flight-sweep` (per-path `maxHits`), `drift-ledger`
  (`lines: [n…]` — uncapped exactly on listed lines, any anchor off-list fails),
  `meta-doc-quoting` (`maxHits` + region-sha256 pin, cjk history-pin homolog),
  `lint-fixture` (`maxHits`), `frozen-string` (`lines` + per-line sha256 pins).
  Exact-equality `maxHits`: actual == registered, both directions violate
  (`stale-or-exceeded`); ghost entries (a `(path, category)` pair whose path is not
  tracked, or a capped entry left with zero remaining anchor) fail. `--emit-baseline
  [out]`: regenerate the full whitelist from the lint's own final patterns over
  `git ls-files` — new dirty paths enter `in-flight-sweep` with exact counts; existing
  entries carry over per `(path, category)` key byte-stable (deterministic sort: path
  asc, then category). Hand-authored entry shapes not producible by emit-baseline are
  lint-time validation errors. `--emit-hits [out]`: full machine census — one record
  per hit `{path, line, tier, matched, category|null, registered:bool}` including
  REGISTERED hits (violations view hides them; the harness and the disposition census
  consume this view).
- **Done when**: `--emit-baseline` emits parseable JSON whose in-flight-sweep counts equal current registered hit counts per path AND planted fixture with maxHits N: N+k and N−k anchors both yield `stale-or-exceeded` AND ghost entry (path not tracked) yields `ghost-whitelist-entry` AND a dual-category fixture (one path, in-flight-sweep + frozen-string) validates and round-trips through emit-baseline byte-stable AND `--emit-hits` emits registered hits with `registered:true`
- **Depends on**: T1

### Wave 3 (depends on Wave 2)

#### T5: baseline landing — census, curation, track, guards
- **Covers**: D-22 (entries landing), D-23 (blocking-day-one prerequisite + shrink check), D-27 (regen guard), R-41
- **Files**: .gos/ai-trace-whitelist.json, test/checks/ai-trace-shrink.sh, .github/workflows/ci.yml, census.json
- **Read first**: T4's landed emit-baseline, .gos/concerns.md FB-4 line, census.json `_doc`
- **Approach**: the whitelist is new and generated; census.json updates via `gos track`. Run `--emit-baseline` → curate ONLY categories whose files already
  exist: assign `drift-ledger` to the T46 fnTotal ledger line (test/sections/T46…),
  `meta-doc-quoting` to AGENTS.md / .gitignore / .gitattributes digit-quote lines
  (`.gitignore:82 [P1…`, `.gitattributes:1 [R2…`), `frozen-string` to contract/locale
  strings (e.g. bin/lib/core/state.cjs `lessonsAnchor` line). NO `lint-fixture` entries
  yet — fixture files are created and registered together in T8 (registering a path
  that does not exist = ghost = lint red). Re-run `--emit-baseline` after curation
  until output is byte-stable (carry-over proves the curation is generator-
  representable). Commit via `node bin/gos.cjs track .gos/ai-trace-whitelist.json` +
  pack-check reconcile. `test/checks/ai-trace-shrink.sh`: fail-closed growth guard —
  vs origin/main, the whitelist may only shrink (entries and sum-of-counts);
  `git diff --name-status origin/main...HEAD -- .gos/ai-trace-whitelist.json` showing
  **A** (first landing) passes on a zero baseline; **R** or **D** status is a red exit
  (rename/delete must not silently void the discipline); missing origin/main skips with
  an explicit advisory line. Wired as a ci.yml step. This task lands the whitelist
  BEFORE the gate wiring so the blocking flip (T6) is green from its first commit
  (D-23 day-one shape): in-flight-sweep exact counts cover every current legacy hit,
  so the lint exits 0 the moment the whitelist lands.
- **Done when**: `git ls-files .gos/ai-trace-whitelist.json` tracked AND `bash test/checks/ai-trace-lint.sh` exits 0 on the curated tree AND re-running `--emit-baseline` diff vs committed whitelist is empty AND `bash test/checks/ai-trace-shrink.sh` exits 0 on the landing commit (A-status path) AND pack-check reconciles census
- **Depends on**: T4

### Wave 4 (depends on Wave 3; T6 ∥ T7)

#### T6: gate wiring — ai-trace as blocking check
- **Covers**: D-23 (blocking day one), R-42
- **Files**: bin/lib/ops/gate.cjs
- **Read first**: bin/lib/ops/gate.cjs cjk-lint selfRepo block (~1118-1158), T5's landed whitelist
- **Approach**: inside the existing `which === 'all' && selfRepo` block, add ai-trace as
  the cjk-lint peer: execFileSync bash test/checks/ai-trace-lint.sh, 120s timeout; on
  failure `core.gateFail('ai-trace-lint', …)` with verdict carrying `violationCount` +
  a pointer to `--json` for the machine view — NO inline excerpts, fix-string says
  "remove the anchor / rewrite the comment to WHAT — lineage belongs in the commit body
  or CHANGELOG.md" and must NOT suggest adding whitelist entries; printed evidence lines
  ANSI-stripped; pass line echoes the lint's own ✓ summary (includes .gos sidecar count).
- **Done when**: `node bin/gos.cjs gate all` prints an ai-trace ✓ line AND `node bin/gos.cjs gate all --json` failure set contains object-only failures when the lint is forced red in a sandbox AND grep for the fix-string shows no "whitelist" invitation
- **Depends on**: T5

#### T7: sweep harness — sole legal batch runner
- **Covers**: D-24 (mechanized guard half), D-29 (ledger mechanism), D-30, R-43
- **Files**: test/checks/ai-trace-sweep.sh
- **Read first**: .gos/task/p6/spec.md Approach §4, T4's landed `--emit-hits`/`--emit-baseline` contracts, bin/lib/ops/changelog-core.cjs validateEntry (entry-body bans), .gos/lessons.json entries 63675448 / 96615604 / de0eb49f
- **Approach**: new file. `ai-trace-sweep.sh <batch-file>` where batch-file lists member paths.
  Pipeline: (1) precompute allowed editable line set from lint `--emit-hits` over batch
  paths (hit lines only, registered and unregistered alike); (2) require clean worktree,
  then apply the operator's edits; (3) guard: `git diff -U0` changed lines ⊆ allowed
  set (anything else = abort + restore); (4) re-run lint over the batch — every
  previously-hit anchor either gone or whitelist-registered; (5) reconciliation rides a
  TRACKED sidecar ledger `.gos/ai-trace-sweep-ledger.ndjson`: harness extracts deleted
  anchor ids from removed diff lines and appends `{batch, ts, path, ids[]}`; the
  CHANGELOG `[Unreleased]` entry stays validator-clean single-sentence prose (category
  verb + D-nn/R-nn trace refs only — `§`, `T-nn`, `DI-nn`, wave/phase words never enter
  the body); (6) regen whitelist via `--emit-baseline`, byte-compare, stage ledger +
  whitelist + content together. Serial/main-session discipline: a lockfile under
  `.gos/logs/` refuses concurrent runs; harness is the only legal consumer of
  `--emit-hits`/`--json`. Self-test: embedded `--self-test` (sandbox repo fixture with
  planted anchor; asserts the out-of-set edit guard trips, the unreconciled-id guard
  trips, and a valid micro-batch round-trips green) — no test/sections file in this
  task (T8 owns T102; harness guards get their section coverage inside T8).
- **Done when**: `bash test/checks/ai-trace-sweep.sh --self-test` exit 0 (all three guard scenarios) AND grep confirms no other repo file consumes `--json`/`--emit-hits` outside harness + gate + T8 section AND ledger append format validates as NDJSON
- **Depends on**: T5

### Wave 5 (depends on Wave 4)

#### T8: test section T102 — lint/whitelist/gate/fixtures/templates/hint evidence
- **Covers**: D-26 (templates-clean test), D-28 (equality both directions), D-23, R-40, R-41, R-42, R-44
- **Files**: test/sections/T102-ai-trace.test.sh, test/fixtures/ai-trace/, .gos/ai-trace-whitelist.json
- **Read first**: test/sections/T101-*.test.sh (section conventions), T4 machine-view contracts, T6 gate line
- **Approach**: both section and fixture files are new; whitelist gains lint-fixture entries with in-task regen. FIRST plant the permanent fixture files under test/fixtures/ai-trace/
  (digit-bearing anchors by design), register them as `lint-fixture` entries, and
  re-run `--emit-baseline` until byte-stable — fixtures + whitelist land in the SAME
  task so no committed state ever holds a ghost entry. Section asserts with machine
  fields + exit codes only (no unescaped brackets in assert_contains): red path = copy
  fixtures into a scratch repo WITHOUT the registration and run the lint there →
  exit 1 with per-tier counts; tracked green = full-tree lint exit 0 proves the
  registration permanent; sandbox: maxHits N with N+k → `stale-or-exceeded`, N−k →
  same class (both directions); ghost entry → fail; regen guard: mutate whitelist →
  emit-baseline diff non-empty → check fails; gate integration: plant anchor in a
  selfRepo-scoped sandbox → gate path fails with ai-trace-lint code; templates/ clean:
  `--emit-hits` over the tree has zero records with `path` under `templates/`; setup
  hint: `renderCodingHint()` output contains `gos init coding` under BOTH locales
  (GOS_LANG=en/zh, direct function call — output-path grade without TTY).
- **Done when**: `bash test/run-sections.sh T102` green with ≥ 9 assertions covering scratch-red/tracked-green/equality-both-ways/ghost/regen/gate/templates/hint-en/hint-zh AND full `--affected` run stays green AND whitelist regen byte-stable with fixtures registered
- **Depends on**: T6, T7

#### T9: census freeze + disposition triage table
- **Covers**: D-24 (judgment half), R-43
- **Files**: .gos/task/p6/disposition.md, .gos/task/p6/batches/
- **Read first**: T5 whitelist output, T7 batch-file contract, spec Approach §4 dispositions
- **Approach**: both are new task-local working artifacts (disposition table + batch membership files). Run lint `--emit-hits` over bin/ + test/ (in-flight-sweep membership;
  `--emit-hits` exposes registered hit lines, so the triage is per-line complete), PLUS
  the meta-doc lines already registered at T5 (.gitattributes:1, .gitignore:82,
  AGENTS.md digit quotes — disposition row each: strip if decorative, else stay
  meta-doc-quoting; a strip decision at T12 removes the entry in the same commit via
  regen). Per-line judgment in the MAIN SESSION: classify every hit as A
  strip-anchor-keep-WHAT / B delete-with-backfill / C leave-whitelisted / D
  string-context (rewrite anchor-free where the label is ours; pin frozen-string where
  a contract string). Freeze batch membership: batch 1 bin/lib core+task+knowledge,
  batch 2 bin/lib ops + bin root, batch 3 test/checks + fixtures + golden +
  .gitattributes (if disposition says strip), batch 4 test/sections (split 4a/4b by
  file count if census says > 30 min; split preserves serial order). Batch file path
  union == in-flight-sweep paths ∪ {meta paths marked for stripping}.
- **Done when**: disposition.md lists every in-flight-sweep hit line exactly once with a disposition letter (counts reconcile: per-path maxHits == disposition line count) AND batch files exist covering exactly the frozen union AND T7 harness accepts each batch file (dry-run parse)
- **Depends on**: T5, T8

### Wave 6 (serial, main session only)

#### T10: sweep batch 1 — bin/lib core + task + knowledge
- **Covers**: D-24, D-23 (shrink), D-29 (backfill + ledger), R-43
- **Files**: bin/lib/core/*.cjs, bin/lib/task/*.cjs, bin/lib/knowledge/*.cjs, CHANGELOG.md, .gos/ai-trace-whitelist.json, .gos/ai-trace-sweep-ledger.ndjson
- **Read first**: .gos/task/p6/disposition.md batch 1, test/checks/ai-trace-sweep.sh usage
- **Approach**: batch membership = disposition.md batch 1. Run harness on batch-1 file; apply per-line dispositions (strip WHAT-
  preserving rewrites by hand; delete lineage-only lines); harness appends deleted ids
  to the tracked ledger; CHANGELOG `[Unreleased]` gains one validator-clean `Chore …`
  entry (prose + D-nn/R-nn trace refs only); whitelist regen shrinks batch-1
  in-flight-sweep entries to zero; `bash test/run-sections.sh --affected` green.
- **Done when**: harness exit 0 AND lint exit 0 AND `jq '[.[]|select(.category=="in-flight-sweep")]|length' .gos/ai-trace-whitelist.json` == (pre-batch count − batch-1 path count, both recorded in harness log — no cap slack) AND --affected green AND `node bin/gos.cjs changelog lint` clean AND ledger carries the batch-1 id set
- **Depends on**: T9

#### T11: sweep batch 2 — bin/lib ops + bin root
- **Covers**: D-24, D-23, D-29, R-43
- **Files**: bin/lib/ops/*.cjs, bin/*.cjs, CHANGELOG.md, .gos/ai-trace-whitelist.json, .gos/ai-trace-sweep-ledger.ndjson
- **Read first**: disposition.md batch 2
- **Approach**: batch membership = disposition.md batch 2. Same harness discipline as T10 on batch 2 (serial after T10; lockfile enforces).
- **Done when**: harness exit 0 AND lint exit 0 AND in-flight-sweep entries for batch-2 paths == 0 (harness log reconciles pre/post counts) AND --affected green AND changelog lint clean
- **Depends on**: T10

#### T12: sweep batch 3 + 4 — test/ tree (+ .gitattributes disposition closure)
- **Covers**: D-24 (incl. string-context audit closure), D-23, D-29, R-43
- **Files**: test/checks/, test/fixtures/, test/golden/, test/sections/*.test.sh, .gitattributes, CHANGELOG.md, .gos/ai-trace-whitelist.json, .gos/ai-trace-sweep-ledger.ndjson
- **Read first**: disposition.md batches 3-4, T8's lint-fixture registrations
- **Approach**: batches 3 then 4, serially, in the order frozen at T9 (batch 4 splits 4a/4b the same way if so frozen; test/fixtures/ scope excludes the permanent ai-trace fixtures; .gitattributes only if its disposition row says strip). Plan-format
  heredoc fixtures inside sections are functional parse data — never edited (structural
  exemption proves them invisible to the lint; any that still hit were mis-categorized
  at T9, fix the category, not the fixture). String-context assertions: rename
  assert-label ids anchor-free where the label is ours; pin true contract strings as
  frozen-string. `.gitattributes:1` follows its frozen disposition row: strip → entry
  removed in the same commit via `--emit-baseline` regen; stay → meta-doc-quoting entry
  remains. test/fixtures/ai-trace/ lint-fixture files are NEVER swept (permanent red
  fixtures by design).
- **Done when**: harness exit 0 per batch AND lint exit 0 AND in-flight-sweep count == 0 across the whole whitelist AND full `bash test/run-sections.sh` (not just --affected) green in main session
- **Depends on**: T11

### Wave 7 (depends on Wave 6)

#### T13: endgame — final state, concerns close-out, ledger audit
- **Covers**: D-23 (end state), D-24, D-29 (ledger reconciliation audit), D-31 (DI-1/DI-2 parking), R-01, R-43
- **Files**: .gos/concerns.md, .gos/ai-trace-whitelist.json, .gos/ai-trace-sweep-ledger.ndjson, CHANGELOG.md, .gos/task/p6/
- **Read first**: .gos/concerns.md FB-4 entry + parking-anchor format, .gos/task/p6/spec.md Deferred Ideas
- **Approach**: task dir receives the ship-stage delta inputs. Verify terminal whitelist = permanent categories only (in-flight-sweep
  zero, shrink check green vs main); mark FB-4 cured in concerns.md with date +
  evidence; add parking anchors `DI-1 ai-trace-user-repo` and
  `DI-2 tier-b-block-comments` (deferred-findings gate enforces presence); audit the
  sweep ledger: union of ids across batches == ids the harness collected, every batch
  has a validator-clean CHANGELOG entry; final full gate + suite already green from
  T12 — record receipts for VERIFY truths.
- **Done when**: `jq '[.[]|select(.category=="in-flight-sweep")]|length' .gos/ai-trace-whitelist.json` == 0 AND concerns.md contains the FB-4 cure line + both DI anchors AND `node bin/gos.cjs gate all` green AND ledger audit reconciles (harness logs retained under .gos/task/p6/)
- **Depends on**: T12

## Observable Truths

### T1: lint fails on planted anchor, passes clean tree
- **Expected**: `bash test/checks/ai-trace-lint.sh --json` on a planted bracket fixture (unregistered scratch copy) → non-empty violations, exit 1; clean tree → exit 0
- **Verify**: T8 section scratch-red / tracked-green assertions (`bash test/run-sections.sh T102`)

### T2: gate all lists ai-trace as blocking; planted anchor flips the gate
- **Expected**: `node bin/gos.cjs gate all` output contains the ai-trace line; planted anchor → gate fail with ai-trace-lint code
- **Verify**: T8 gate-integration assertion + `node bin/gos.cjs gate all | grep ai-trace`

### T3: count-cap equality fails both directions
- **Expected**: maxHits N with N+k planted anchors → `stale-or-exceeded`; N−k → same violation class
- **Verify**: T8 equality assertions over sandbox whitelist

### T4: post-sweep lint clean; whitelist holds only permanent categories
- **Expected**: lint exit 0 on the repo AND in-flight-sweep entries == 0
- **Verify**: `bash test/checks/ai-trace-lint.sh && jq '[.[]|select(.category=="in-flight-sweep")]|length' .gos/ai-trace-whitelist.json` → 0

### T5: templates teach the full ban digit-free
- **Expected**: lint reports zero hit records under templates/; 00-general.md names decision anchors, wave/task ids, spec-citations, and narrative phrases
- **Verify**: T8 templates-clean assertion (`--emit-hits` path filter) + `grep -cE 'REVIEW Mn|Wn-Tn|RTn-Fn|§n' templates/coding-standards/00-general.md` ≥ 3

### T6: setup onboarding prints the hint in both locales
- **Expected**: `renderCodingHint()` renders the `gos init coding` hint under en and zh locales; onboarding() consumes the same helper
- **Verify**: T8 hint assertions (GOS_LANG=en/zh direct call) + grep of onboarding() consumption

## Risks

- Tier-B narrative grammar fuzzy → census (T9) pins the real grammar from `--emit-hits` output before patterns freeze is final; narrow-start, extend-on-miss is spec'd (spec Risks).
- Whitelist landing chore is large (53+ bracket files, ~660 bare-form lines) → emit-baseline generates it mechanically; curation touches only the 3 permanent-category paths existing at T5 (fixtures join at T8).
- test/sections string assertions citing D-nn ids may be product-contract fixtures → disposition D pins (frozen-string) rather than rewrites; mis-triage at T9 surfaces as T12 lint red, not silent loss.
- Equality counts raise edit friction after landing → accepted deliberately (spec Risks); harness regen step makes the re-baseline one command.
- Gate red between T5 and T6 on CI main → ordering: whitelist lands (T5) before wiring (T6); in-flight-sweep exact counts make the lint green at T5, so the T6 flip is green from its first commit.
- Batch 4 (test/sections) may exceed 30 min → T9 freezes an explicit 4a/4b serial split; the harness lock keeps the split disciplined.
- CHANGELOG validator bans id-bearing bodies (§, T-nn, DI-nn, wave/phase) → ids ride the tracked NDJSON ledger; entries stay single-sentence prose (plan-attack F1, changelog-core.cjs:74-86).
