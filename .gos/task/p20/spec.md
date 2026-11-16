# Spec: Milestone lifecycle mechanics and ceremony (P20)

> **Date**: 2026-11-12 | **Level**: Lv3 | **Status**: Draft (post red-team, dispositions folded)

## Goal

Implement the hierarchical milestone model (B-double-prime): project.json is the
Lv4 parent container, phase entries gain additive snapshot fields, the wrapper
state class is eliminated, close-with-parked carries debt forward, and the
v1.0.0-dev milestone closes into a fresh publicize milestone with P2/P3
re-homed unchanged.

## Motivation

Milestone identity currently lives in no truth source: the archive slug prefix
`v1.0.0` is the npm package version by accident, the `.gos/project/milestones/`
naming was hand-applied across two eras, and the gos-project skill still runs a
superseded GSD-era shell script. The wrapper state (project=true, no
phase_name) is a second truth source D-59 ruled out, and the every(done) gate
makes parked P2/P3 a structural deadlock for closing v1.0.0-dev.

## Requirements (R-NN)

- **R-01**: Milestone lifecycle mechanics and ceremony on the hierarchical
  model (auto from claim — goal text is the frozen master)
- **R-02**: `gos milestone open <name>` writes project.json
  `milestone: {name, opened_at}`; the name is slug-sanitized AT IDENTITY TIME
  (stored form = sanitized form: `[^a-z0-9]+`→`-`, length cap, non-empty,
  reject `v`+digits-only reserved shapes); slug and snapshot names derive ONLY
  from the stored form. Lifecycle is an explicit state machine: open REFUSES
  when an unclosed milestone exists (names it, points to close); close stamps
  `closed_at` onto the milestone object; open may only succeed over a closed
  object. `init --project` is bootstrap-only, converges on open's internals,
  never writes a state file, and requires `--fresh` when the repo has Lv4
  trace (clone-divergence guard)
- **R-03**: `gos milestone close [--carry-parked]` transaction contract:
  validate → render → dual-channel snapshot → stat-verify snapshots on disk →
  single writeAtomicJson wipe, all under `.gos/.lock`; `milestone` registers
  as WRITE-class in the dispatch table. Validation domain: every phase with
  status ∈ {done, parked} must be done (parked allowed only under the flag);
  **pending phases are exempt and carried in place**; the ceremony host must
  be done (close refuses an active host). Vacuum close (zero done phases)
  refuses without `--empty`. The embedded auto-close in archive.cjs:693 is
  REMOVED and routed through this implementation; close with no milestone
  object refuses and points to `gos milestone open`
- **R-04**: The selective wipe is an exhaustive five-class disposition:
  (1) parked phase entries + rows they own by phase field → survive in place,
  verbatim; (2) pending phase entries → survive in place; (3) done phase
  entries + done-owned requirement/decision rows + the ceremony host's rows →
  wipe with history; (4) null-phase rows → wipe with history; (5) dropped
  rows and ghost-phase rows (phase field references no existing phase) →
  wipe with history, counted separately in the report. Guard domain for the
  nonexistent-phase refusal = surviving classes only (1)(2); ghost rows in
  classes (4)(5) never block. `last_archived_phase` resets to null
  (archive.cjs:701 semantics preserved). The close report prints per-class
  counts AND per-row ID lists (kept/wiped); T-truths assert BOTH sides
- **R-05**: Close backups: default is dry-run (full ID disposition, no
  mutation); execution requires `--yes` after a dry-run or a recorded
  `gos approve milestone-close`; before any wipe, the pre-close project.json
  ORIGINAL is copied to BOTH channels as `<name>-<date>-preclose.json`
  (structured, lossless) plus dated view snapshots
  `<name>-<date>-{ROADMAP,REQUIREMENTS,DECISIONS}.md` in
  `.gos/project/milestones/` (never overwriting existing files — dated names
  sidestep the two hand-named eras) and the archive channel
  `milestone-record/`. Standalone close without a resolvable task_ref
  (mark-done-only milestones, deleted archive dirs) synthesizes
  `.gos/archive/<date>-<name>-close/milestone-record/`; task_ref resolution
  stat-verifies the directory exists and fails closed
- **R-06**: Snapshot channel two also carries the views as rendered on disk
  (copy the rendered files — never re-render at close time, so MANUAL regions
  survive verbatim)
- **R-07**: Archive path stamps `task_ref` (basename of the home it actually
  created; stable across idempotent re-entry which resolves by listing, never
  recomputation) and `completed_at`; `phase mark-done` stamps `completed_at`
  only (task_ref stays null — never-ran close-out). PROJECT_SCHEMA_VERSION
  bumps 1→2; validatePhase gains shape checks (task_ref: basename string|null
  — no path separators; completed_at: ISO|null); emptyProject() seeds
  `milestone: null`
- **R-08**: Repo-level Lv4-ness = tracked marker `.gos/project/lv4.json`
  (one line, seeded by milestone open/init bootstrap via the census/track
  discipline) OR project.json existence. The marker travels with clones —
  fresh clones stay Lv4 (project.json itself is machine-local by census). All
  8 `state.project` consumers re-point in one commit; child-state
  `project:true` from claim stays untouched. Legacy tracked wrapper states
  (project=true, no phase_name, stage INTENT|DONE) get a one-shot retirement
  prompt on read: confirm → delete state.json (the parent view takes over)
- **R-09**: Stateless `gos resume` composes the parent view BUT: first line
  is a machine-greppable `NO ACTIVE TASK` banner; when a tracked project
  marker/state exists but local state.json is absent, the claim hint
  downgrades to a clone warning (state.json is machine-local — an in-flight
  task may live on another machine) instead of an action invitation
- **R-10**: `gos phase move <from> <to>` verb: `<from>` accepts name-prefix
  (index-free, aligned with claim) plus optional `--expect <current-index>`
  guard; refuses active targets; one-time P0 → index 0 reorder lands before
  the v1.0.0-dev close so the closing snapshot reads monotonically
- **R-11**: Archive slug prefix switches from PKG.version to the stored
  milestone name for NEW archives only (historical basenames never rewritten);
  in the closed-not-reopened gap the slug carries NO version prefix; T10:281
  parametric assertion updates in the same change
- **R-12**: The gos-project skill's archive-milestone.sh is replaced IN-REPO
  by a refusing stub (exit 1, prints `use gos milestone close`); SKILL.md
  rows re-point to the new verb family
- **R-13**: Pre-close data normalization: decision/requirement rows whose
  phase field uses a bare prefix ("P0" vs the canonical "P0: full-auto
  mode") are normalized to the canonical phase name via the existing
  rename reference-rewrite channel BEFORE the wipe predicate runs; fixtures
  seed both spellings plus dropped ghost rows
- **R-14**: Spec truths are registered mechanically: plan task 0 registers
  all spec truths via `gos truth add` before the first BUILD commit; the
  VERIFY checklist includes a BUILD-closeout truths>0 check
- **R-15**: Ceremony: close v1.0.0-dev (parked P2/P3 + pending P21/P22/P23
  carried; P20's own entry done by its archive), open publicize — P2/P3
  re-homed unchanged (stale park_reason text stays: unchanged is the
  contract)

## Approach

### Selected Approach

project.json grows additive fields only: `milestone: {name, opened_at,
closed_at?}` and per-phase `task_ref`/`completed_at` — under schema v2 with
shape validation. The resident state stays a single-slot child; claim keeps
seeding it; the wrapper class dies at its only birthplace (init.cjs:201) and
its tracked zombies get a one-shot retirement. Milestone ceremony is a new
top-level WRITE-class verb family owning identity (sanitized at entry),
validation, dual-channel snapshot (lossless preclose JSON + dated views),
and the exhaustive five-class wipe. Lv4-ness of the repo derives from a
tracked marker surviving clones. Slug prefix becomes the milestone name.

### Alternatives (Rejected)

- ~~Option B (card 2)~~: reuse `init --project "<name>"` as the opener —
  welds project birth to cycle opening; third milestone breaks the semantics.
- ~~Option B (card 3)~~: full wipe + re-home re-add — a second truth pass
  over the same data, pure transcription risk (5b0059ce class).
- ~~Option B (card 4)~~: lazy derivation at resume only — two ways to be
  Lv4 forever, the second-truth-source D-59 ruled against.
- ~~Rename P0 → slot-fitting number (card 5)~~: cascades against the D-58
  ruling; 21+ birth_phase rewrites for zero mechanical gain.

## Design Decisions (D-NN)

### D-66: Phase snapshot field semantics

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. task_ref = archive-dir basename (chosen) | each done-with-work phase has exactly one archive dir | unique, relative, self-locating; stat-able directly | long; breaks if archive dirs are ever renamed | resume composition, milestone close snapshot, audit joins |
| B. object {tid, archive} | tid short and readable | dual-channel join | two fields to sync; tid derivable | nothing today needs id-join |
| C. tid only | shortest | none | glob re-derivation on every read; truncation collisions | a future resolver nobody wrote |

why-not: B. object {tid, archive} — no consumer needs id-join; C. tid only — the join back to evidence is the whole point, glob re-derives it per read.
recommendation: A — conditional: mark-done close-outs leave task_ref null;
archive writes the basename of the home it actually created; idempotent
re-entry resolves by listing (R3 risk cure).
deepen: any option — ask for another dig round.

### D-67: Milestone ceremony and parent identity

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. gos milestone open/close family; project.json +milestone {name, opened_at} (chosen) | milestone identity in NO truth source (0 grep hits; slug = PKG.version accident) | single verb owns lifecycle; name tracked once | new command surface; slug semantics change (1 parametric fixture) | slug derivation, snapshot naming, status banner, gos-project close flow |
| B. init --project "<name>" as opener | init already builds skeleton | zero new verbs | init is task vocabulary; re-init to open cycle is backwards | only init itself |
| C. phase milestone subs | reuses phase family | zero top-level growth | milestone ≠ phase; phase family already 27 keys | nothing new |

why-not: B. init --project "<name>" as opener — project birth ≠ cycle opening; C. phase milestone subs — hierarchy error.
recommendation: A — conditional: slug prefix switches for new archives only;
init --project converges on open's internals; T10:281 rides along; name is
sanitized at identity time (red-team R1-F1).
deepen: any option — ask for another dig round.

### D-68: Close-with-parked carry semantics (post red-team: five-class disposition)

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. Selective wipe (chosen, extended) | 11 live reqs must survive verbatim; pending P21-23 must survive too (R3-F1); done-owned 40+53 rows and null-phase 15 rows wipe | no transcription step; R-NN continuity; both sides asserted | predicate classifies 5 classes (machine-counted) | milestone close implementation; future P2/P3 + P21-23 claim inheritance |
| B. Full wipe + re-home re-add | total wipe, no classification | explicit auditable carry | second truth pass; transcription bug class | a re-add routine that does not exist |
| C. Full wipe, phases only | smallest carry | simplest | 11 rows + 3 pending phases die; violates frozen "unchanged" | a future repair task |

why-not: B. Full wipe + re-home re-add — transcription risk with zero new information; C. Full wipe, phases only — kills the contract P2/P3 AND P21-23 will claim against.
recommendation: A — conditional: exhaustive five-class table (R-04),
pre-close name normalization (R-13), per-ID dry-run report (R-05), verbatim
deep-compare assertion against the preclose backup (red-team R1-F8).
deepen: any option — ask for another dig round.

### D-69: Resume composition and wrapper elimination

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. Lv4-ness from tracked marker + project.json existence (chosen) | 8 counted consumers; claim already sets project:true on children; fresh clones must stay Lv4 (R2-F1) | wrapper class dies root and branch; clones keep identity | 8 consumers rewired in one commit (0d2eedee class); zombie wrappers retired one-shot | phase add gate, decision/requirement dual-store, stateless resume |
| B. lazy derivation at resume only | minimal diff | smallest | dual Lv4 signal forever | nothing structural |
| C. kill writer only, consumers stay | 3 lines | smallest | stateless windows degrade vs today | nothing — pure regression |

why-not: B. lazy derivation at resume only — the second truth source D-59 rejected; C. kill writer only, consumers stay — strictly worse in stateless windows.
recommendation: A — conditional: tracked lv4.json marker (clone survival),
zombie retirement prompt (R2-F6), NO ACTIVE TASK banner + clone warning on
stateless resume (R-09).
deepen: any option — ask for another dig round.

### D-70: P0 insertion-order fix

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. gos phase move verb + one-time P0 → index 0 (chosen) | names are the idempotency key (21 birth_phase refs, two spellings — normalized R-13); array order feeds render + adjacency only | monotonic closing snapshot; generic ceremony for future fixes | new sub to test; index hints shift | phase command family; closing ROADMAP snapshot |
| B. rename P0 → slot-fitting number | name-position strict match | none | cascades against D-58 ruling; 21+ birth_phase rewrites | a rename cascade nobody needs |
| C. leave, footnote the snapshot | zero change | free | cuts the frozen goal text | nothing |

why-not: B. rename P0 → slot-fitting number — rename storm against a standing ruling; C. leave, footnote the snapshot — the goal names this fix explicitly.
recommendation: A — conditional: move takes name-prefix `<from>` with
optional --expect guard, refuses active targets; executes before the
v1.0.0-dev close.
deepen: any option — ask for another dig round.

### D-71: Publication truth — gh issues vs tracked feedback ledger

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| A. gh issues sole truth; ledger demoted to untracked cache (chosen) | the tracked ledger became a second publication surface beside issues | single publication truth; ledger stays as a machine-side buffer | census flip + gitignore reconciliation needed | feedback push flows, census disposition of .gos/FEEDBACK.md |
| B. keep the tracked ledger as a second surface | zero migration | none | two publication truths diverge (the D-59 class) | nothing — the divergence already bit the concurrent stream |
| C. delete the ledger outright | one less file | simplest | loses the machine-side buffer between push windows | a re-add nobody asked for |

why-not: B. keep the tracked ledger as a second surface — a second truth source is the standing anti-pattern; C. delete the ledger outright — the buffer has push-window value.
recommendation: A — conditional: the demotion (census flip via the
track/gap discipline) and the issues-only publication contract are
implemented by a later task in the registering stream; P20 records this
card so the decision is covered and auditable (user ruling 2026-11-16).
deepen: any option — ask for another dig round.

## Scope

### In Scope

- `gos milestone open|close` verb family (registry WRITE-class, locales,
  contracts, census/audit-trail ledger entries, tests)
- `gos approve milestone-close` approval surface
- Additive project.json fields under PROJECT_SCHEMA_VERSION 2: milestone
  object, phase task_ref/completed_at (+ validatePhase shape checks)
- Exhaustive five-class selective wipe with dual-channel lossless snapshots
  (preclose JSON + dated views; synthesized standalone close home)
- Tracked Lv4 marker (.gos/project/lv4.json via track discipline) +
  8-consumer re-point sweep + zombie wrapper retirement
- Stateless resume composition (NO ACTIVE TASK banner + clone warning)
- `gos phase move` verb + one-time P0 reorder
- Slug prefix switch (new archives only) + gap-period no-prefix rule +
  T10:281 update
- gos-project archive-milestone.sh refusing stub + SKILL.md re-pointing
- Pre-close bare-prefix normalization (rename reference-rewrite channel)
- Ceremony: close v1.0.0-dev (P2/P3 parked + P21-23 pending carried),
  open publicize
- Module-landing checklist (6d5568e4): gate codemap BEFORE full suite; T46
  ledger scan-set/fnTotal/fnDist/anchors drift + T25 frozen-set drift in the
  same change; global fn-name uniqueness (shared helpers hoisted, no
  destructured requires)
- Test surface (5+ sections; PLAN must `ls test/sections/` for max+1 —
  currently T113): milestone open/close contract incl. wipe classes;
  phase move; stateless resume; slug prefix + T10:281; init bootstrap-only
- Truths registration task (R-14) as plan task 0

### Out of Scope

- P2/P3/P21-23 execution (stays with the phases themselves)
- Parent state file / state.json schema changes (D-59 bans)
- Historical archive slug/basename rewrites (D-66 stability)
- park_reason text edits on carried phases ("unchanged" is the contract)
- Tracked/exportable snapshot channel beyond local dual copies (privacy
  audit first — DI-4)
- queue_version counter for array-order staleness (DI-3)

## Deferred Ideas

- [DI-1]: milestone render surface in `gos status` banner beyond one identity
  line (add when a second consumer asks)
- [DI-2]: `milestone list` history view reading milestones/ README table
  (needs the P2 archive-contract decision first)
- [DI-3]: queue_version counter on project.json to mechanically detect stale
  phase-list advice (R1-F7 partial)
- [DI-4]: tracked/exportable milestone snapshot channel (`gos milestone
  export`) — requires CJK/privacy audit of goals/rationales before census
  change (R2-F2 partial)

## Observable Truths (registered by plan task 0 — R-14)

- **T-01**: `gos phase list` shows P0 at index 0 and names in monotonic order
- **T-02**: after archive of a phase task, its project.json entry carries
  task_ref = archive basename and completed_at ISO stamp
- **T-03**: `gos milestone close --carry-parked --yes` on v1.0.0-dev leaves
  P2/P3 + 11 parked-owned rows + P21/P22/P23 entries present in
  project.json, byte-equal to the preclose backup (deep compare); snapshots
  exist at milestones/v1.0.0-dev-<date>-*.md + preclose.json and in the
  closing milestone-record/
- **T-04**: `gos milestone open publicize` stamps milestone
  {name: "publicize", opened_at}; the NEXT archived task's slug prefix reads
  publicize; in the closed-not-reopened gap slugs carry no version prefix
- **T-05**: with state.json absent and the Lv4 marker present, `gos resume`
  prints NO ACTIVE TASK + milestone identity + phase queue + clone warning
  (exit 0)
- **T-06**: `gos init --project` in a fresh repo creates project.json,
  lv4.json marker, and views but no state.json; `init --project` on a repo
  with Lv4 trace refuses without --fresh
- **T-07**: `gos phase mark-done` on a never-claimed phase stamps
  completed_at and leaves task_ref null
- **T-08**: post-close project.json: decisions array empty (or milestone-
  owned only), done-owned requirement rows = 0, dropped/ghost rows counted
  in the report, last_archived_phase null
- **T-09**: `gos milestone open evil/../x` and `` open `id` `` die with a
  sanitization contract error; a tainted name never reaches a path, slug,
  or echo line
- **T-10**: legacy wrapper state (project=true, no phase_name) triggers the
  retirement prompt; after retirement, stateless resume takes over

## Red Team Record (Lv3 — 3 rounds, all dispositions folded)

| Round | Perspective | Findings | Dispositions (A/AP/R-with-facts/D) |
|:--|:--|:--|:--|
| 1 | misuse/safety | 9 (2C/4M/3m): name sanitization; wipe approval/backup; lifecycle state machine; auto-close divergence; script stub; resume probing; move drift; verbatim assertion; flag naming | 8 ACCEPT (folded R-02..R-10), 1 PARTIAL: move name-prefix ACCEPT, queue_version DEFER→DI-3 |
| 2 | edge/exception | 7 (2C/4M/1m): clone Lv4 loss (verified: .gos/project 0 git files); lossy snapshots; standalone close home; transaction contract; schema v2 + validation; zombie wrappers; filename collisions + gap slug | 6 ACCEPT (folded R-03..R-08, R-11), 1 PARTIAL: preclose JSON ACCEPT, tracked export DEFER→DI-4. Non-problem verifications recorded (mark-done/claim conflicts unreachable; re-entry slug stability confirmed in code) |
| 3 | completeness | 6 (2C/2M/2m): pending/active validation hole (P21-23 carry); five-class wipe gap + decisions 70/70 unclassified + wipe-side unasserted; ghost/bare-P0 join instability (machine-counted: 12 bare, 1 dropped ghost); truths registration; module-landing tax; test surface enumeration (max=T113) | 6 ACCEPT (folded R-03/R-04/R-13/R-14 + Scope checklist + T-08/T-09/T-10) |

> Verdict: escalated-then-converged — rounds 1-2 structural findings
> reshaped R-02..R-08; round 3's two Criticals rewrote the wipe contract
> (R-04) and validation domain (R-03). Zero REJECT-with-facts.

## Risks

- [R1] 8-consumer sweep misses a consumer → Lv4 detection splits into two
  answers → mitigation: census-first grep in the sweep commit + fixture
  asserting stateless phase add (0d2eedee pattern)
- [R2] Five-class predicate misclassifies a row → silent requirement loss →
  mitigation: dry-run per-ID report + refuse on unknown classification +
  preclose JSON backup + byte-equal deep compare (T-03)
- [R3] Slug prefix switch breaks archive-idempotency re-entry → mitigation:
  re-entry resolves basenames by listing, never recomputation; gap-period
  no-prefix rule asserted (T-04)
- [R4] move verb used mid-flight → status desync → mitigation: move refuses
  active targets; name-prefix from + --expect guard
- [R5] Old global gos binary reads schema v2 project.json → mitigation: the
  existing future-version guard fails closed with the upgrade hint (designed
  semantics); ceremony runs on repo CLI only (AGENTS.md rule)
- [R6] Standalone close synthesizes a home the census does not know →
  mitigation: `<date>-<name>-close/` registered in the .gos/archive census
  zone class within the same change
