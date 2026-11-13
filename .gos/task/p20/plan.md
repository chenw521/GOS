# Plan: Milestone lifecycle mechanics and ceremony (P20)

> **Date**: 2026-11-12 | **Based on spec**: .gos/task/p20/spec.md
>
> **Landing strategy (mechanized)**: P20 = ONE feature branch
> (feat/p20-milestone-lifecycle), ONE squash-PR; waves are commits on the
> branch; T13 lands BEFORE merge (main never goes red on ledger drift).
> Every task that adds/renames functions updates T46 EXPECT (fnTotal/fnDist/
> scan set) and the T25 FROZEN set IN THE SAME COMMIT (incremental drift —
> no end-of-task batch). Drift values are recomputed against the branch
> HEAD at commit time — precomputed values are forbidden (parallel waves
> may land between drafting and committing).

## Decision Inventory

- [x] D-66: task_ref = archive basename at archive time; completed_at stamps → T2, T6
- [x] D-67: gos milestone open/close; project.json +milestone object → T4
- [x] D-68: selective wipe, five-class disposition, verbatim carry → T5
- [x] D-69: wrapper elimination, Lv4 marker, stateless resume → T8, T9
- [x] D-70: gos phase move + one-time P0 reorder → T10

## Requirement Claims

- [x] R-01: umbrella (goal text frozen master) → T13
- [x] R-02: milestone open verb, sanitization, state machine, bootstrap-only init → T4
- [x] R-03: close transaction contract + validation domain + auto-close removal → T5, T6
- [x] R-04: five-class wipe disposition → T5
- [x] R-05: dry-run/approve/preclose backups/standalone home → T5, T7
- [x] R-06: snapshots copy rendered files (MANUAL survives) → T5, T12
- [x] R-07: archive stamps task_ref/completed_at; schema v2 shapes → T2, T6
- [x] R-08: tracked Lv4 marker + 8-consumer sweep + zombie retirement → T4, T8
- [x] R-09: stateless resume NO ACTIVE TASK + clone warning → T9
- [x] R-10: phase move verb + P0 → index 0 → T10
- [x] R-11: slug prefix switch + gap no-prefix + T10:281 → T3
- [x] R-12: archive-milestone.sh refusing stub + SKILL.md re-point → T11
- [x] R-13: pre-close bare-P0 normalization → T2, T5
- [x] R-14: truths registered mechanically + test surface → T1, T12
- [x] R-15: ceremony close v1.0.0-dev + open publicize → T14a

## Patterns to Follow

- Commands: bin/lib/knowledge/*.cjs module + dispatch = bin/gos.cjs switch
  case + knowledge/index forward (phase/truth precedent — ops/index spread
  is the ops-family precedent, not knowledge's) + COMMANDS entry in
  bin/lib/core/state.cjs (verifyCommandRegistry cross-checks the switch
  universe against KNOWN_CASES — missing either side fails self-check) +
  registry entry in bin/lib/nav/registry-consts.cjs KNOWN_CASES + WRITE
  class; locale keys live in
  bin/lib/core/locales/en.cjs AND zh.cjs (T74 parity check) — never i18n.cjs
- Shared helpers: hoist into dependency-free modules via non-destructured
  requires (contract-banned otherwise); global fn-name uniqueness
- Tests: test/sections/T<NNN>-<slug>.test.sh, mktemp sandbox + pwd guard,
  assert_contains is grep -q — bracket-free substrings only; fixture
  stores XDG-overridden; sections run serially in the main session only
- Truths: two-column contract — BUILD side (fixture section assertion,
  verifiable at VERIFY) + CEREMONY side (literal `gos truth verify` lines
  embedded in the T14a runbook, executed post-archive). VERIFY checks the
  BUILD side only; ceremony-side lines are the runbook's mechanical spine.

## Execution Waves

### Wave 1 (T1 ∥ T2; then T3)

#### T1: Register spec truths
- **Covers**: R-14
- **Files**: .gos/state.json
- **Read first**: .gos/task/p20/spec.md truths section
- **Approach**: `gos truth add` for the ten truths. IDs are CLI-generated
  (truthNextId emits the un-hyphenated `T1`..`T10` form — the CLI takes no
  ID argument); after registration, record the actual-ID ↔ semantic-number
  mapping at the top of the plan's Observable Truths section. BUILD-side
  verification is executed in T12 (sections green → `gos truth verify` with
  --replay JSON-argv evidence or manual --command/--excerpt); T13's gate-all
  exit 0 is the closeout (gate all fails on any registered-unverified truth).
  Ceremony-side commands go into the T14a runbook.
- **Done when**: `node -e "const s=require('./.gos/state.json');const t=s.observable_truths||[];process.exit(t.length===10&&t.every(x=>!x.verified)?0:1)"` exits 0
- **Depends on**: none

#### T2: PROJECT_SCHEMA_VERSION 2 + phase snapshot shapes + normalization helper
- **Covers**: D-66, R-07, R-13
- **Files**: bin/lib/core/state.cjs, test/sections/T46-module-structure.test.sh, test/sections/T25-map-selfcheck.test.sh
- **Read first**: bin/lib/core/state.cjs (validateProject/validatePhase/emptyProject), T111 rename guards (collision/--expect conventions — verified NOT a reference-rewrite channel: phase.cjs rename never mutates rows)
- **Approach**: bump PROJECT_SCHEMA_VERSION 1→2; emptyProject seeds
  milestone:null; validateProject validates milestone object
  {name:slug-shape, opened_at:ISO, closed_at:ISO|undefined}; validatePhase
  accepts task_ref (basename shape — reject path separators) | null and
  completed_at (ISO|null); export normalizeRowPhaseRefs(rows, phases, field)
  — a NEW helper (the rename verb never rewrites row references; its T111
  channel is pending-only name rewrite); field-selective: decisions pass
  'birth_phase', requirements pass 'phase' (live data: 12 bare prefixes all
  sit in decisions.birth_phase, requirements.phase has 0 bare/15 null);
  bare prefix ("P0") → canonical ("P0: full-auto mode") via longest-prefix
  match; an ambiguous bare prefix (two canonical phases share it) dies
  naming both candidates. Same-commit ledger drift for any new/renamed fn.
- **Done when**: `grep -n "PROJECT_SCHEMA_VERSION = 2" bin/lib/core/state.cjs` matches AND `grep -n "normalizeRowPhaseRefs" bin/lib/core/state.cjs` matches AND `node -e "const s=require('./bin/lib/core/state.cjs');['P0: full-auto mode'].includes(s.normalizeRowPhaseRefs([{birth_phase:'P0'}],[{name:'P0: full-auto mode'}],'birth_phase')[0].birth_phase)"` exits 0 AND seeded v1 project with new fields validates while task_ref containing "/" fails AND T25+T46 pass with same-commit drift
- **Depends on**: none

#### T3: Slug prefix switch + gap rule + T10:281
- **Covers**: R-11
- **Files**: bin/lib/task/context.cjs, test/sections/T10-security-e2e.test.sh, test/sections/T46-module-structure.test.sh, test/sections/T25-map-selfcheck.test.sh
- **Read first**: bin/lib/task/context.cjs archiveSlugParts, archive.cjs idempotent re-entry (resolves by listing)
- **Approach**: archiveSlugParts reads
  loadProject().milestone.name (stored sanitized form): open milestone →
  prefix = name; closed-not-reopened gap → NO version prefix; no milestone
  object (pre-v2 repos) → legacy PKG.version fallback, PERMANENT documented
  fallback for non-Lv4 repos (not a sunset). Update T10:281 expectation
  (legacy branch stays parametric).
- **Done when**: `grep -n "milestone" bin/lib/task/context.cjs` matches AND T10 section passes AND a node-level assertion with a hand-planted v2 project.json fixture proves prefix = stored name (inline `node -e` smoke in this task; T117 formalizes it later) AND T25+T46 drift same-commit
- **Depends on**: T2

### Wave 2 (serial: T4 → T5 → {T6 ∥ T7})

#### T4: milestone open verb + init bootstrap-only + Lv4 marker
- **Covers**: D-67, R-02, R-08 (marker side)
- **Files**: bin/lib/knowledge/milestone.cjs, bin/lib/knowledge/index.cjs, bin/gos.cjs, bin/lib/core/state.cjs, bin/lib/nav/registry-consts.cjs, bin/lib/task/init.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs, test/sections/T2-project.test.sh, test/sections/T46-module-structure.test.sh, test/sections/T25-map-selfcheck.test.sh
- **Read first**: bin/lib/knowledge/phase.cjs (claim structure, name-prefix parsing), init.cjs:165-210 (wrapper birth to delete), census/track flow
- **Approach**: `gos milestone open <name>`: sanitize at identity
  (`[^a-z0-9]+`→`-`, ≤40, non-empty, reject ^v\d+$) — SANITIZED form stored;
  state machine: refuse unclosed milestone (name it, point to close); write
  {name, opened_at}; render views. Marker seeding: `milestone open` in the
  live repo WRITES the one-line .gos/project/lv4.json marker itself (open
  is the seed writer — init bootstrap too); the tracked flip (`gos track`)
  happens at the ceremony (T14a step 8; the file exists because step 6 ran
  open); SANDBOX FIXTURES hand-write the one-line marker directly (no
  track in fixtures). init --project: remove the wrapper write
  (init.cjs:201 block), converge on open's internals (default name
  "milestone-1" if unnamed), require --fresh when Lv4 trace exists (marker
  OR project.json OR tracked wrapper state). Register `milestone`: switch
  case + knowledge/index forward + COMMANDS entry in state.cjs
  (verifyCommandRegistry cross-checks switch universe ↔ KNOWN_CASES) +
  KNOWN_CASES WRITE-class. Same-commit ledger drift.
- **Done when**: `grep -n "state.project = true" bin/lib/task/init.cjs` returns nothing AND `grep -n "sanitiz" bin/lib/knowledge/milestone.cjs` matches AND dispatch lists milestone WRITE-class AND sandbox smoke: open publicize → second open dies naming the live milestone AND T74 locale parity passes AND T25+T46 drift same-commit
- **Depends on**: T3

#### T5: milestone close verb — transaction + five-class wipe
- **Covers**: D-68, R-03, R-04, R-05, R-06, R-13
- **Files**: bin/lib/knowledge/milestone.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs, bin/lib/task/archive.cjs, test/sections/T46-module-structure.test.sh, test/sections/T25-map-selfcheck.test.sh
- **Read first**: archive.cjs:667-757 (close/reset to replace), state.cjs normalizeRowPhaseRefs (T2), cmds.cjs approvals
- **Approach**: close [--carry-parked] [--yes] [--empty]: under .gos/.lock —
  (1) normalize row phase refs; (2) validate: {done,parked} phases must be
  done (parked only under flag), pending exempt (carried), active host
  refuses, vacuum refuses without --empty, milestone object required; (3)
  render final views; (4) snapshot: copy preclose project.json + the
  rendered .md files ON DISK (COPY artifacts — MANUAL regions survive
  byte-for-byte) to milestones/<name>-<date>-{ROADMAP,REQUIREMENTS,DECISIONS}.md
  + <name>-<date>-preclose.json (dated names never overwrite) AND archive
  channel: resolve last-done task_ref by listing (stat-verify, fail closed;
  none resolvable → synthesize .gos/archive/<date>-<name>-close/
  milestone-record/ — covered by the EXISTING .gos/archive census zone key,
  no new census key); (5) stat-verify every snapshot; (6) dry-run default:
  five-class per-ID disposition printed, NO mutation, exit 0; (7) execution:
  --yes requires a recorded approval (state.approvals['MILESTONE-CLOSE']=
  {ts,reason}, consumed-once, ≤24h fresh) — R-05 OR semantics: the approval
  IS the code gate; the dry-run→inspect→approve sequence is enforced by
  the ceremony runbook steps (3→4), not by a cross-process dry-run receipt
  (an AND gate was rejected as an unmechanized semantic tightening;
  same-invocation print-then-wipe remains FORBIDDEN); (8) single
  writeAtomicJson: wipe done-owned + null-phase + ghost/dropped classes,
  keep parked + pending verbatim, stamp milestone.closed_at,
  last_archived_phase=null; (9) per-class counts + ID report. The wipe
  predicate is a named export classifyRowDisposition(row, phases) — refuses
  on unknown classification. GOS_TEST_BREAK injection points at
  validate/snapshot/wipe windows. Same-commit ledger drift.
- **Done when**: `grep -n "classifyRowDisposition" bin/lib/knowledge/milestone.cjs` matches (refuse-on-unknown classification) AND sandbox smoke: 3-class micro-fixture dry-run leaves project.json byte-identical (`cmp`) AND --yes without approval dies AND with consumed approval wipes exactly the per-ID report AND a MANUAL-region fixture survives snapshot byte-equal (`cmp` dated .md vs pre-close disk file) AND T25+T46 drift same-commit
- **Depends on**: T4

#### T6: archive integration — auto-close removal + task_ref stamping
- **Covers**: D-66, R-03, R-07
- **Files**: bin/lib/task/archive.cjs, bin/lib/knowledge/phase.cjs, test/sections/T8-phase-archive.test.sh, test/sections/T46-module-structure.test.sh, test/sections/T25-map-selfcheck.test.sh
- **Read first**: archive.cjs:667-757, T5 close implementation, phase.cjs mark-done
- **Approach**: remove the embedded every(done) close/reset block
  (archive.cjs:693-727): final-done phase prints guidance pointing to
  `gos milestone close` (never wipes); merge-back + parked-debt lines stay;
  phase entry stamping at merge: task_ref = basename of the home this run
  created (same variable as dest — never recomputed), completed_at =
  state.completed_at; mark-done (phase.cjs) stamps completed_at = now,
  task_ref untouched. Same-commit ledger drift.
- **Done when**: `grep -n "every((p)" bin/lib/task/archive.cjs` returns nothing AND `grep -n "task_ref" bin/lib/task/archive.cjs` matches AND `grep -n "completed_at" bin/lib/knowledge/phase.cjs` matches AND sandbox smoke: a fixture archive stamps both fields onto the phase entry AND T25+T46 drift same-commit
- **Depends on**: T5

#### T7: approve milestone-close surface
- **Covers**: R-05
- **Files**: bin/lib/nav/cmds.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: cmds.cjs cmdApprove (baseline-reset pattern: record {ts,reason}, consume-once)
- **Approach**: extend cmdApprove valid set with milestone-close
  (records MILESTONE-CLOSE {ts, reason?}); consumption contract implemented
  in T5 (consume-once, ≤24h). DATA-ONLY invariant: an array entry + locale
  strings, zero new/renamed function declarations — T46/T25 drift N/A by
  invariant (cmds.cjs fnDist unchanged); if the invariant breaks, drift
  lands same-commit per the landing strategy. No new locale-file surprises:
  en+zh both.
- **Done when**: `grep -n "milestone-close" bin/lib/nav/cmds.cjs` matches AND humanGateGuard covers it AND sandbox smoke: approve → close --yes succeeds consuming the approval → second close --yes without re-approve dies AND T74 parity passes
- **Depends on**: T5

### Wave 3 (serial: T8 → T9)

#### T8: 8-consumer re-point sweep + zombie retirement
- **Covers**: D-69, R-08
- **Files**: bin/lib/knowledge/phase.cjs, bin/lib/knowledge/decisions.cjs, bin/lib/knowledge/requirements.cjs, bin/lib/nav/cmds.cjs, bin/lib/core/state.cjs, test/sections/T46-module-structure.test.sh, test/sections/T25-map-selfcheck.test.sh
- **Read first**: all state.project consumer sites (three spellings: === true, !== true, truthy &&), claim's isPhaseOwned logic
- **Approach**: core.isLv4Repo() = marker exists OR project.json exists;
  census-first grep replaces every repo-level consumer — phase add gate
  (phase.cjs:69 `state.project !== true`), dual-store routing
  (decisions.cjs:146, requirements.cjs:66), resume hint (cmds.cjs truthy
  spelling) — in ONE commit; task-boundness consumers (claim's children
  project:true) untouched, each whitelisted with an isLv4Repo comment.
  Zombie retirement: checked at the dispatch entry (NOT the readState hot
  path — no interactive prompt inside lock-holding commands);
  project===true && !phase_name && stage ∈ {INTENT,DONE}: interactive TTY
  → confirm prompt; GOS_RETIRE_WRAPPER=1 → delete state.json; non-TTY
  (piped/section runs) → one-shot notice, no mutation, no block.
  Sandbox marker-only fixture: hand-write one-line .gos/project/lv4.json
  (per T4 note) with NO project.json. Same-commit ledger drift.
- **Done when**: whitelist audit passes — `grep -rn "state\.project\b" bin/lib | grep -v "state.project_name"` output matches EXACTLY the enumerated post-sweep whitelist. Current 10 lines: init.cjs:201 (writer — DELETED), phase.cjs:69, requirements.cjs:66 (comment wording rewritten) /67/75/89, decisions.cjs:146/355, cmds.cjs:74 — all nine repo-level sites re-point to isLv4Repo() and stop matching the grep pattern; surviving output lines = task-boundness sites only (claim child-stamp literals never matched this grep), each carrying the isLv4Repo comment AND sandbox: stateless `phase add` succeeds with marker-only Lv4 AND zombie wrapper fixture triggers retirement then parent view AND T25+T46 drift same-commit
- **Depends on**: T4

#### T9: stateless resume composition
- **Covers**: D-69, R-09
- **Files**: bin/lib/nav/cmds.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: cmdResume, sibStatus.structuredNextActions
- **Approach**: readState() null + isLv4Repo() → first line `NO ACTIVE TASK`
  banner, then milestone identity (name/opened_at or closed notice), phase
  queue tail, and: tracked Lv4 trace but no local state → clone warning
  (state.json machine-local; in-flight task may live on another machine)
  instead of claim invitation; exit 0.
- **Done when**: `grep -n "NO ACTIVE TASK" bin/lib/nav/cmds.cjs` matches AND sandbox: marker-only fixture resume exits 0 printing the banner AND T74 parity passes
- **Depends on**: T4, T8

### Wave 4 (T10 ∥ T11)

#### T10: phase move verb + one-time P0 reorder
- **Covers**: D-70, R-10
- **Files**: bin/lib/knowledge/phase.cjs, bin/lib/core/state.cjs, bin/lib/nav/registry-consts.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs, test/sections/T46-module-structure.test.sh, test/sections/T25-map-selfcheck.test.sh
- **Read first**: phase.cjs name-prefix parsing (claim), park undo patterns
- **Approach**: `gos phase move <from> <to>`: from accepts name-prefix
  (digits keep legacy), optional --expect <current-index> guard (mismatch
  dies); refuse active targets; splice + saveProject + autoRenderViews;
  print post-move queue with indices. Live `phase move p0 0` executes in
  T14a pre-close step. Same-commit ledger drift.
- **Done when**: move subcommand exists AND sandbox: active-target move dies AND wrong --expect dies AND name-prefix move reorders AND T74 parity AND T25+T46 drift same-commit
- **Depends on**: T8

#### T11: gos-project skill stub + re-point
- **Covers**: R-12
- **Files**: skills/gos-project/scripts/archive-milestone.sh, skills/gos-project/SKILL.md
- **Read first**: current script + SKILL.md milestone rows
- **Approach**: replace script body with refusing stub (exit 1, print
  `retired: use gos milestone close`); SKILL.md complete-milestone row
  re-points to the new flow; remove git mv/tag ceremony description.
- **Done when**: `bash skills/gos-project/scripts/archive-milestone.sh v0.1` exits 1 printing the pointer AND `grep -n "milestone close" skills/gos-project/SKILL.md` matches
- **Depends on**: T5

### Wave 5 (serial: T12 → T13 → T14a)

#### T12: test sections T114-T118
- **Covers**: R-14, R-06 (assertion home)
- **Files**: test/sections/T114-milestone-open-close.test.sh, test/sections/T115-phase-move.test.sh, test/sections/T116-stateless-resume.test.sh, test/sections/T117-slug-prefix-init-bootstrap.test.sh, test/sections/T118-milestone-ceremony.test.sh
- **Read first**: T111/T110/T113 conventions; max existing number verified T113
- **Approach**: T114: open sanitization (evil/../x, backtick names die;
  sanitized form stored), lifecycle (open-refuses-open, close-stamps
  closed_at), five-class wipe on a seeded 12-phase/67-req/70-dec replica
  with bare-P0 + dropped-ghost rows, byte-equal deep-compare survivors vs
  preclose.json, MANUAL-region fixture + `cmp` on all three dated .md
  snapshots, dry-run zero-mutation (`cmp`), approval consume-once + 24h
  freshness, vacuum refusal, crash-window injections; T115: move
  name-prefix/--expect/active-refusal + P0-to-0 outcome; T116: stateless
  resume banner/exit-0/clone-warning + zombie retirement; T117: slug prefix
  (open/gap/legacy-permanent) + init bootstrap-only (no state.json) +
  --fresh guard; T118: seeded end-to-end ceremony (close → open next →
  carried rows + pending survival + last_archived_phase null + standalone
  home synthesis when all mark-done). Census-style legacy-section sweep:
  grep every section referencing `init --project` (18 today: T2/T3/T4/
  T6/T7/T8/T10/T12/T14/T26/T27/T37/T39/T71/T88/T90/T110/T111) — classify
  fixture-usage (works unchanged: bootstrap-only init + isLv4Repo() keeps
  phase verbs alive) vs behavior assertions (rewrite to the new contract);
  claim each in the commit body. BUILD-side truth closeout: once sections
  are green, record evidence per truth via `gos truth verify` (--replay
  JSON-argv against the section, or manual --command/--excerpt; artifact
  under .gos/{logs,cache}/ machine-local zones — gate all fails on any
  registered-unverified truth, so this closes before T13).
- **Done when**: all five sections pass standalone serially AND ai-trace lint clean on them AND `node -e "const s=require('./.gos/state.json');const t=s.observable_truths||[];process.exit(t.length>0&&t.every(x=>x.verified||x.waived)?0:1)"` exits 0 (BUILD-side truths verified)
- **Depends on**: T6, T7, T8, T9, T10, T11

#### T13: module-landing checklist + census
- **Covers**: R-01
- **Files**: census.json, .gos/codebase/network.md, .gos/codebase/unmapped-fns.txt, test/sections/T46-module-structure.test.sh, test/sections/T25-map-selfcheck.test.sh
- **Read first**: lesson 6d5568e4; current T46/T25 declared drift values; test/pack-check.sh
- **Approach**: gate codemap FIRST (fn uniqueness, no nav→ops edges,
  milestone wired through ops/index); T46/T25 final reconciliation (drift
  already updated per-commit — this is the terminal check); census.json at
  repo root: NO lv4.json pre-registration (the gos track step at ceremony
  writes it atomically — a pre-registered tracked key with no file fails
  pack-check); synthesized close-home needs NO new key (existing .gos/
  archive machine-local zone key covers it). pack-check run if layout
  touched. Same-commit drift audit: `git log --stat` over the branch —
  every commit touching bin/lib with a function-count change must also
  diff T46/T25 in the same commit. Full-suite merge gate: `bash
  test/run-sections.sh` (serial, main session) exit 0 BEFORE the squash
  merge — main never goes red (landing strategy; lesson 6d5568e4 orders
  codemap first, full suite still owed).
- **Done when**: `node bin/gos.cjs gate codemap` exits 0 AND `node bin/gos.cjs gate all` exits 0 (truths all verified/waived) AND `bash test/run-sections.sh` exits 0 AND T25+T46 pass AND `bash test/pack-check.sh` exits 0 AND census.json contains no dead keys
- **Depends on**: T12

#### T14a: ceremony runbook (BUILD deliverable; execution is T14b, post-archive, OUTSIDE this plan's completion claim)
- **Covers**: R-15, R-10 (live P0 move)
- **Files**: .gos/task/p20/ceremony-runbook.md
- **Read first**: T5 close output contract, spec R-15
- **Approach**: author the runbook; execution happens post-archive (close
  refuses an active host by design — R-03). Steps (each with the exact
  command and a user-confirmation gate; destructive acts never batched):
  (1) verify P20 done via phase list; (2) `phase move p0 0` + inspect; (3)
  `milestone close --carry-parked` DRY-RUN — inspect five-class report
  (expect kept: P2/P3 + 11 rows + P21/22/23; wiped: done-owned + null-phase
  + ghosts); (4) user confirms → `gos approve milestone-close` →
  `milestone close --carry-parked --yes`; (5) verify preclose.json + dated
  snapshots on disk; (6) `milestone open publicize`; (7) dry-run on
  publicize (expect vacuum refusal); (8) `gos track` the lv4.json marker
  (the file already exists — step 6's `milestone open` wrote it);
  (9) run the embedded ceremony-side truth-verify lines (executable
  forms — CLI truth ID from the T1 mapping, manual mode:
  `gos truth verify <T-id> --command '<cmd>' --excerpt '<expected line>'
  --artifact '.gos/logs/<file>'` for the T-01/T-03/T-04 live sides; the
  un-hyphenated CLI ID replaces the T-0N spelling); (10) record outcomes into the closing
  milestone-record/ directory (post-archive home — the task dir moves at
  archive, so records land in milestone-record/).
- **Done when**: `grep -c "^## Step" .gos/task/p20/ceremony-runbook.md` ≥ 10 AND every step names an exact command (`grep -c "gos \|node \|bash " ≥ 10`) AND the three truth-verify lines exist verbatim (`grep -c "gos truth verify T" = 3`)
- **Depends on**: T1, T12, T13

## T14b (post-archive ceremony execution — NOT a BUILD task)

The live runbook executes after P20's archive (P20 done) with user
confirmation per step. This plan delivers the runbook only (T14a) and does
NOT claim T14b completion. Outcomes land in the closing milestone-record/.

## Observable Truths

BUILD side (asserted by sections; evidence recorded via `gos truth
verify` in T12 once green) + CEREMONY side (runbook literal verify lines,
post-archive). Registered IDs are CLI-generated (`T1`..`T10` un-hyphenated
— truthNextId takes no ID argument); the `T-01`..`T-10` labels below are
semantic numbers, and the actual-ID ↔ semantic mapping is recorded at T1:

### T-01: P0 at index 0, monotonic names
- **Expected**: phase list P0 first; names monotonic
- **Verify (BUILD)**: T115 P0-to-0 outcome assertion green
- **Verify (CEREMONY)**: runbook line `gos truth verify T-01 --command 'node bin/gos.cjs phase list | head -4'`

### T-02: archive stamps phase snapshots
- **Expected**: post-archive entry carries task_ref basename + completed_at
- **Verify (BUILD)**: T6 sandbox smoke + T118 assertion green
- **Verify (CEREMONY)**: post-archive `gos truth verify T-02 --command "node -e ...task_ref..."` on the live P20 entry

### T-03: carried rows byte-equal (both sides)
- **Expected**: survivors identical to preclose backup — requirements AND decisions AND phase entries
- **Verify (BUILD)**: T118 deep-compare (all three families) green
- **Verify (CEREMONY)**: runbook diff covering reqs+decs+phases vs preclose.json

### T-04: publicize identity + slug prefix + gap rule
- **Expected**: milestone {name: publicize}; next slug prefix publicize; gap no prefix
- **Verify (BUILD)**: T117 section green
- **Verify (CEREMONY)**: `node -e "console.log(require('./.gos/project/project.json').milestone.name)"` → publicize

### T-05: stateless resume composes
- **Expected**: NO ACTIVE TASK banner + queue + clone warning, exit 0
- **Verify (BUILD)**: T116 section green

### T-06: init bootstrap-only
- **Expected**: fresh-repo init --project creates project.json + views, NO state.json; --fresh guard on Lv4 repos
- **Verify (BUILD)**: T117 assertions

### T-07: mark-done stamps completed_at only
- **Expected**: never-claimed mark-done → completed_at set, task_ref null
- **Verify (BUILD)**: T114 assertion

### T-08: wipe side asserted
- **Expected**: post-close decisions empty, done-owned reqs 0, ghosts counted, last_archived_phase null
- **Verify (BUILD)**: T118 assertions on the seeded replica

### T-09: name sanitization
- **Expected**: evil/../x and backtick names die; sanitized form stored
- **Verify (BUILD)**: T114 assertions

### T-10: zombie wrapper retirement
- **Expected**: wrapper state triggers retirement prompt; parent view takes over
- **Verify (BUILD)**: T116 retirement-flow assertions

## Red Team Record (PLAN — round 4 plan-attack)

| Round | Perspective | Findings | Dispositions |
|:--|:--|:--|:--|
| 4 | plan-attack: wave deps / interface docking / testable done-when / parallel-wave aggregation | 10 (3C/4M/3m) | 9 ACCEPT + 1 ACCEPT-PARTIAL, 0 REJECT, 0 DEFER — F1 truth lifecycle (ID form, verify flags, closeout ownership) → T1/T12/T13/T14a; F2 legacy-section drift + full-suite gate → T4/T6 Files, T12 sweep, T13 run-sections; F3 rename-rewrite channel nonexistent → field-aware new helper (T2); F4 gos.cjs + COMMANDS wiring → T4/T10/Patterns; F5 unmechanized dry-run receipt → R-05 OR restored, runbook enforces order (T5); F6 open seeds the lv4 marker (T4/T14a); F7 T7 data-only invariant + HEAD-recomputed drift (landing strategy); F8 done-when mechanization — partial (T2/T5/T8/T3/T13); F9 Covers/Claims alignment (T5 += R-13; R-01 → T13); F10 non-TTY retirement semantics + dispatch-entry mount (T8). Axis A verified clean: no cycles, wave layout serializes every declared edge; missing T14a→T1 edge added. |

## Risks

- Schema v2 vs old global gos binary → runbook pins repo CLI (AGENTS.md); future-version guard fails closed with upgrade hint
- Ledger drift timing → per-commit same-commit rule + T13 terminal check + one-PR landing (F1 cure)
- Ceremony sequencing (close refuses active host) → T14a/T14b split makes the boundary honest
- run-sections serialization → all section runs serial in main session
- approve freshness window (24h) vs long gaps → runbook re-approves in the same session as execution
