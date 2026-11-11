# Spec: P19 — live pain bugs and archive integrity

## 1. Goals

Cure the user-visible bugs the 2026-11-09/10 sessions lived through and
restore archive integrity: the changelog same-day obligation tripping on
landings across UTC midnight (#49), the closing-keyword channel (#24), the
between-tasks gate false-red on DONE-resident state (dffa50f0 recurrence),
the census fresh-checkout optional-entry class (73cef6ab — re-grounded by
red team RT3-F2, see R-66), the fromCommit archive path skipping the
completed_at stamp, the deficient `-der` archive payload rebuild and
one-time retro-stamp, the `--help` short-circuit, a phase rename verb, and
— added by user ruling mid-THINK (D-63) — the mechanized card-preflight
dig floor (e5e75820).

## 2. Requirements (as amended by red-team dispositions)

- **R-01** (seeded goal): the phase goal as claimed.
- **R-60** — Changelog obligation becomes a structural delta with an
  explicitly defined predicate: the batch diff (base..head) adds at least
  one NEW bullet in `[Unreleased]` **or the newest version section**
  (promote day: version-heading + bullets added there satisfies it); a
  "new" bullet's text must not exist anywhere in the base changelog
  (rewriting one bullet every batch cannot launder the obligation); the
  bullet's trace-ref group must intersect the current task's
  requirements/decisions (a sibling task's bullet cannot satisfy this
  task's ritual). Bases are pinned per site: CI on main diffs
  `HEAD^1..HEAD --first-parent`; the PR job diffs
  `merge-base...PR_HEAD_SHA` (the true head sha, never the merge ref) with
  `fetch-depth: 0`; the SHIP ritual diffs task_head against the working
  tree (a just-written uncommitted bullet must count). Base fallbacks are
  pinned per case: unborn/zero-parent first landing → exempt with a loud
  output line; missing/unresolvable task_head → fail-closed with re-claim
  guidance; non-git repos → file-shape fallback ("[Unreleased] non-empty")
  so plain-git product users never lose the check entirely. Standalone
  `gos changelog lint` keeps format-only checks (no base exists); the
  obligation predicate is one shared export consumed by gate --audit and
  the SHIP ritual, replacing both duplicated clock predicates. CI changelog
  paths resolve through the root-anchored resolver (config changelog-path),
  never a hardcoded CHANGELOG.md.
- **R-61** — Closing keywords ride the PR body: neutralizeIssueTriggers
  unchanged; pure `#N` groups stay legal bullet content. The teaching
  surface becomes frozen-string contract output (not prose): archivePushHint
  is re-pointed to the PR flow and carries a fixed discipline line
  ("refer with `refs #N` unless the PR must close it — closing keywords
  belong in the PR body"); hints branch on `git remote` presence (no remote
  → keep the plain-git `gos push` line: local-only/plain-git repos are a
  retained product surface, D-61). T76's hint assertions follow the new
  frozen copy.
- **R-62** — completed_at cure, three halves: (a) the commit chain merges
  the archive's disk writes with a PINNED bidirectional field list —
  archive-won fields: current_stage=DONE, completed_at, cleared
  checkpoints, all STATE_PATH_FIELDS rewrites, evidence artifact paths;
  commit-won fields: everything else (approvals, spec_sha256,
  plan_snapshot, completed_stages backfill) — T2 asserts both sides
  survive; (b) fromCommit catch discipline: if the nested archive threw
  after materializing a dest containing the tid, the commit chain runs the
  half-transaction completion (stamp + path rewrite + DONE) before
  advancing; if it threw with no dest, the advance is refused — never
  advance past a failed archive (RT2-F1 Critical); (c) idle and idempotency
  semantics are DISJUNCTIVE, not replacement: `doneIdle = DONE &&
  (completed_at || (archiveDirContainsTid && canonicalPathsResolveIntoThatArchive))`
  — the archive-dir evidence alone never idles a state whose paths still
  point at the live zone (kills the plantable-key attack RT1-F2 and keeps
  fresh clones safe: tracked state carries the stamp, archive dirs are
  machine-local, RT3-F3). The tid-based archive idempotency early-returns
  only under the same two-part condition; a bare-DONE resident state whose
  tid is archived but whose paths are stale FALLS THROUGH to repair
  (path rewrite + stamp), preserving today's only self-heal path (RT1-F1
  Critical). The slug-based idempotency keeps its completed_at condition.
- **R-63** — `-der` archive repair as a documented manual ritual (no
  in-repo one-off script: pack-check rejects unregistered untracked files,
  RT3-F5): rebuild `task/1a2e46f3/` containing a state snapshot byte-equal
  to state@493a9e7 except for exactly two added fields — `completed_at`
  (= 493a9e7 commit timestamp) and a structured retro marker
  (`completed_at_retro: true`) so audit consumers can distinguish
  retro-stamped from live-stamped values (RT1-F11/RT2-F12) — plus
  PROVENANCE.md with fixed front-matter keys naming the destruction class
  (b2e3f4a5), the reconstruction sources, and the receipt trail.
  T4 is a local-only, non-replayable truth (manual evidence in
  truth-receipts; archive zones are machine-local). The six-instance
  roster is logged as a concern; the five siblings keep delta.md as their
  final record.
- **R-64** — help-flag short-circuit with pinned semantics: the exact
  tokens `--help`/`-h` are recognized ONLY in flag position (a token in a
  value position — e.g. `--summary "--help"` — is a value; `--` terminates
  flag parsing); routing happens BEFORE guardCwd/lock (a help request has
  zero filesystem side effects); only registered commands short-circuit to
  their help (unknown commands keep the non-zero error); `gos help --json`
  and topic pages are unchanged; write-class AND exec-class commands never
  execute on a help request (T5 includes an exec-class case).
- **R-65** — `gos phase rename <n> "<new name>"` for pending phases only;
  active/done/parked refused; the new name is rejected on equality or
  prefix collision with ANY existing phase name in ANY status (archive
  locates phases by exact name — a collision would mis-mark a done phase
  and wedge the milestone chain, RT1-F8/RT2-F6); name grammar enforced
  (keep the `Pn:` prefix shape, length cap, no newlines); the command is
  wired into the command registry (T29 registry↔switch self-check), prints
  old→new, and supports `--expect "<old name>"` as a mis-target guard;
  re-rendered views (including the TRACKED .gos/README.md) are declared in
  plan Files (lesson 10790226).
- **R-66** — Census optional entries, re-grounded (RT3-F2): fresh clones
  already pass pack-check today (transient escape hatch + directory-probe
  fallback cover absent machine-local dirs; verified by experiment), so
  this requirement is (a) hotfix cleanup: remove the residual
  `mkdir -p .gos/cache` at ci.yml:95; (b) explicit declaration:
  entries gain `optional: true`, VALIDATED to be legal only on paths
  covered by .gitignore (a tracked-path optional entry fails pack-check,
  RT1-F12), subsuming the derived transient rule for the same entry
  (no stacking, RT3-F12); gitignore reconciliation (source-3) stays
  unconditional. T7 carries a negative control: stripping gitignore
  coverage from an optional entry must turn the check red.
- **R-67** — Card-preflight dig floor with era semantics (RT3-F1
  Critical): decision records gain a `dig` field whose value MUST be an
  evidence object shape (at least one {command, output_excerpt} pair plus
  a resolvable file:line anchor — a free-text sentence is not evidence,
  RT1-F4), validated at `gos decision add` time; spec freeze (and the
  floor family) refuses decisions lacking dig evidence ONLY for decisions
  born after R-67 lands — decided by an explicit born-at/era field; the
  60 legacy project decisions and this task's own D-61..D-65 are
  grandfathered with a loud advisory (3d40eaaf precedent). The floor is a
  freeze-time check OUTSIDE the SPEC_CARD_FLOORS probe sequence (a probe
  would pass dig-less content as v3 and never block, RT3-F1); it reads
  state decisions AND the spec's `## Decisions` headings so Lv1/Lv2 specs
  are covered too (RT1-F5).

## 3. Ground truth (digs each requirement stands on)

| Fact | Evidence |
|:--|:--|
| validateStructure evaluates `utcToday()` at run time; three clock shapes; PR #46 green 2026-10-30T15:39Z failed main run 41159440811 after a 02:19Z merge | changelog-core.cjs:235-273; issue #49 |
| The SHIP ritual accepts only clock shape 1 (calendar-exact `endsWith`) — the two predicates already disagree | archive.cjs:225-231 vs changelog-core.cjs:265-271 |
| 8/8 recent main landings carry a `[Unreleased]` bullet addition; PR #46's bullet existed with a stale date — the date is a clock proxy for the structural invariant | git log origin/main -- CHANGELOG.md, 11-02..11-10 |
| Pure `#N` groups are already legal; neutralizeIssueTriggers rewrites keyword-adjacent `#N` to `refs #N` at commit.cjs:564 and push.cjs:148 (added f3b390a) | changelog-core.cjs:75-77,116-122 |
| PR template line 15 invites `Closes #N`; squash body = PR body — the PR channel closes issues today with zero code | .github/PULL_REQUEST_TEMPLATE.md:15 |
| 6 of 7 main landings 11-06..11-10 carry no `(#N)` suffix — aggregate push was the de facto landing path; archivePushHint still teaches it | git log origin/main; push.cjs:259-261 |
| commit.cjs:555 writes its stale in-memory state AFTER the fromCommit archive's disk write — completed_at AND adoption path rewrites are clobbered (dead-path states) | commit.cjs:445→552-555 vs archive.cjs:632-641 |
| 4/4 direct-archive landings STAMPED with archive paths; 2/2 Lv1 fromCommit landings bare with dead task paths (Lv3 self-heals via a later explicit archive; Lv1 has none) | git history of .gos/state.json, 11-06..11-10 |
| gate.cjs:703 `doneIdle` requires `DONE && completed_at` — "Bare DONE keeps every task-level check live"; archive.cjs:316 idempotency uses completed_at as a conjunct | gate.cjs:696-713; archive.cjs:309-326 |
| tid derives primarily from the phase code in phase_name (user/LLM-controlled), task_head short-hash as fallback — "archive dir contains tid" alone is a plantable key | state.cjs currentTaskId; phase.cjs:187 |
| `-der` archive = delta.md + orphans only; tid 1a2e46f3 appears in no archive and no git commit; its truth receipts are alive in .gos/logs/truth-receipts.md (03:40Z 11-10); state@493a9e7 committed and complete except the stamp | archive dir listing; git ls-tree; receipts tail |
| 32/62 archives lack `task/`: 26 pre-convention (by-era design), 6 convention-era deficient (4 manual-only rounds, wave-dispatch, -der) — all Lv1, same delta+orphans shape | archive scan 2026-11-11 |
| No code parses archived `state.json` copies — consumers are existence scans only (idempotency tid walks) | grep ARCHIVE_DIR/state.json across bin/lib |
| `gos status --help` executes status (flag swallowed); no command module handles `--help`; only the command-position help at gos.cjs:195 | live probe 2026-11-11 |
| Fresh clone minus `.gos/cache` passes `bash test/pack-check.sh` TODAY (RC=0): the transient escape hatch (pack-check.sh:121-131) and directory-probe fallback (:96-102) already cover absent machine-local dirs — 73cef6ab is stale; ci.yml:95 is residual | RT3 experiment, fresh clone, 2026-11-11 |
| census.json entries carry no optionality axis; ci.yml:95 provisions `mkdir -p .gos/cache` | census.json entries; .github/workflows/ci.yml:95 |
| e5e75820: the dig contract has no mechanical floor; second live instance this session (GA-2 card reshaped + a broken pipeline artifact retracted only under a user-demanded deepen) | concerns.md; lesson recorded 2026-11-10 |
| probeSpecFloor returns the FIRST passing floor (gate.cjs:1632-1640) — a dig floor inside the probe sequence would never block dig-less content; B-22 spec-hash re-freeze would lock this task's own card-less decisions | RT3 code reading; commit.cjs:456 |

## 4. Decisions

### D-61 — landing unified on PR+squash; #24 closes via PR body

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| `--closes-tail` | aggregates were the de facto main channel | explicit intent channel | new flag + two-sided neutralizer tests | GitHub closer on aggregate tails |
| `drop-neutralizer` | aggregates are human-seen | smallest diff | reopens the accidental-close hole f3b390a closed; "human-seen" has no mechanism | every push becomes a close decision |
| `PR-body` (chosen) | user ruling: unify on PR+squash; squash IS the aggregation on the PR path (one semantic commit per batch, stage noise stays on branch) | zero new close machinery; template line 15 works today; neutralizer keeps its full accident protection | aggregate-push landing loses auto-close — accepted because that path stops being this repo's landing channel | PR bodies → squash commits → GitHub closer; archivePushHint re-points to the PR flow |

why-not: `--closes-tail` — serves a path the ruling retires; `drop-neutralizer` — reopens the f3b390a hole.
recommendation (ratified): C. `gos push` stays a product capability for
local-only/plain-git repos.

### D-62 — #49 cure: structural delta, no clock

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| `structural-delta` (chosen) | the real invariant is "every batch carries a record"; 8/8 landings pass; PR #46 would have passed | midnight class structurally impossible; deterministic; unifies the two predicates | three base wirings; standalone lint drops the today-check | lint (format-only), gate audit, SHIP ritual on one shared predicate |
| `rolling-window` | clock semantics, minimal diff | smaller diff | the class survives at longer horizons (weekend batches) | same three consumers, age predicate |
| `landing-restamp` | stamp fidelity | exact dates | server-side squash escapes local hooks; CI-writes-main violates PR-only | new main write surface |
| `status-quo` | — | — | night merges recur by habit | none |

why-not: `rolling-window` — the class survives at longer horizons; `landing-restamp` — server-side squash escapes local hooks; `status-quo` — night merges recur by habit. Red team amended the predicate: promote-day shape,
rewrite/cross-task laundering guards, per-site base pinning with explicit
fallbacks, non-git file-shape fallback (R-60 as amended).

### D-64 — completed_at: write-site merge + guard re-key (both halves)

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| `both` (chosen) | clobber proven at commit.cjs:555; -der-shape archives are invisible to stamp-only guards — both halves forced | root cure + resilience to future stamp loss; idempotency gains tid protection | two change surfaces | commit-chain merge; gate idle guard; archive idempotency; P20 snapshot fields |
| `write-site-only` | single-point symptom | minimal diff | guards stay stamp-dependent; any future loss path re-arms dffa50f0 | commit.cjs only |
| `guard-rekey-only` | false-red is the user pain | low risk | state never stamps — P20 starves, -der retro-stamp has no anchor | gate + idempotency only |

why-not: `write-site-only` — zero resilience; `guard-rekey-only` — three downstream consumers stay hungry.
Red team amended the semantics: DISJUNCTIVE idle (stamp OR
tid-in-archive+canonical-paths), pinned bidirectional merge field lists,
fromCommit catch discipline with half-tx completion (R-62 as amended).

### D-65 — `-der` rebuild: single instance, verifiable parts only

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| `der-only` (chosen) | no live gate consumes dead tasks' tid dirs; history has delta.md; -der's evidence is richest (git snapshot + live receipts + landing commit) | smallest honest repair; retro-stamp makes the snapshot self-describing | five siblings stay skeleton-less (accepted: delta is their final record) | archive history surface; roster concern |
| `class-rebuild` | uniform class integrity | all self-describing | per-instance archaeology; some snapshots provably absent → PROVENANCE-only skeletons; beyond goal text | 6× PROVENANCE maintenance |
| `loss-markers` | cheapest | — | no place for the mandated retro-stamp; markers ≤ delta information | none |

why-not: `class-rebuild` — pays archaeology for a surface with no consumer; `loss-markers` — violates the retro-stamp obligation. Red team amendments folded into R-63: structured
retro marker, manual-ritual mechanism, local-only truth.

### D-63 — P19 scope +1: mechanized dig floor

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| `fold-into-P19` (chosen) | second live instance hit THIS phase's own THINK; auto mode runs THINK delegated with no human deepen backstop | floor lands before the next auto cycle; live instance drives the design | P19 grows one requirement (goal text stays frozen — amend refuses active) | R-67: dig evidence in state + freeze-time enforcement |
| `leave-at-trigger` | e5e75820 already names a trigger (next think/dialectic phase) | P19 stays seven items | auto mode stays exposed through P20..P23 — at least four more phases of gameable cards | nothing — the concern keeps aging |

why-not: `leave-at-trigger` — leaves auto mode exposed for at least four
more phases while the second live instance is still fresh. Ratified by user
ruling 2026-11-10 (mid-THINK scope addition).

## 5. Scope and non-goals

- The promote-day lint rule (cc928b96) stays P23 — the structural-delta
  predicate now defines the promote-day shape natively (R-60 amendment).
- `gos push` machinery is unchanged — it remains a product capability for
  local-only/plain-git repos; only this repo's ceremony re-points to PRs.
- The five sibling archives stay untouched; delta.md is their final record.
- The router INTENT gate (4f316c16) is out of scope — the dig floor (R-67)
  covers the think-side only.
- No `--closes` flag; the neutralizer keeps its current contract.
- Class-level archive rebuild deferred (Deferred Ideas).
- A `[skip ci]` squash landing bypasses CI entirely — accepted residual
  (rare; subject lint already discourages it), noted for the P23 gate
  batch.

## 6. Observable Truths (draft — register as an explicit early-BUILD task)

- **T1**: structural-delta obligation — fixtures: new bullet + stale stamp
  across midnight passes; no new bullet fails; rewritten bullet (text
  existed in base) fails; sibling-task bullet (refs disjoint from task
  state) fails the ritual; promote-only diff (version section added) passes.
- **T2**: after a Lv1 fromCommit chain archive, the landed state.json
  carries completed_at AND archive-rewritten paths AND surviving
  approvals/spec_sha256/plan_snapshot/completed_stages (pinned field lists).
- **T3**: DONE-resident idle semantics — disjunctive fixtures: stamp-only
  idles; tid-in-archive + paths-into-archive idles; planted tid dir with
  paths still on the live zone does NOT idle; no stamp + no archive does
  not idle.
- **T4** (local-only, non-replayable):
  `…-der/task/1a2e46f3/state.json` is byte-equal to state@493a9e7 except
  exactly two added fields (completed_at, completed_at_retro); PROVENANCE.md
  present with fixed front-matter keys. Manual evidence in truth-receipts.
- **T5**: `gos <cmd> --help`/`-h` for a registered command prints help and
  exits without executing (write-class AND exec-class cases); a value
  position holding the literal token `--help` does not trigger; unknown
  commands still exit non-zero; `gos help --json` unchanged.
- **T6**: `gos phase rename` renames a pending phase, re-renders views,
  refuses active/done/parked, refuses name collisions with any existing
  phase, supports --expect.
- **T7**: census — fresh checkout without `.gos/cache` passes (negative
  control included: optional entry losing gitignore coverage must red);
  ci.yml no longer mkdirs.
- **T8**: dig floor — spec freeze refuses a post-era decision lacking
  evidence-object dig evidence; grandfathered legacy decisions pass with a
  loud advisory; `gos decision add` without dig evidence is refused.

## 7. Red Team (3 rounds, heterogeneous, dispatched)

### Round 1 — MISUSE

| ID | Finding | Disposition |
|:--|:--|:--|
| RT1-F1 | tid idempotency re-key (replacement semantics) destroys the only self-heal path and locks bare states on dead paths | ACCEPT — R-62(c): disjunctive two-part condition; stale-path states fall through to repair |
| RT1-F2 | "archive dir contains tid" is a plantable key (tid = phase code) | ACCEPT — folded into the same two-part condition (canonical paths must resolve into the archive) |
| RT1-F3 | merge field list undefined; three archive return shapes | ACCEPT — R-62(a) pinned bidirectional lists; T2 asserts both sides |
| RT1-F4 | dig floor: free text is gameable | ACCEPT — R-67: evidence-object shape {command, output_excerpt} + file:line anchor |
| RT1-F5 | floor misses Lv1/Lv2 spec decisions and BUILD-time adds | ACCEPT — floor reads spec `## Decisions` headings too; decision-add-time validation |
| RT1-F6 | --help: value-position false trigger; guardCwd side effects; exec-class unnamed | ACCEPT — R-64: flag-position parsing, pre-guardCwd routing, exec-class included |
| RT1-F7 | rewrite-laundering + cross-task bullet stealing | ACCEPT — R-60: not-in-base-text + refs-intersect-task guards |
| RT1-F8 | rename collisions mis-mark done phases | ACCEPT — R-65: collision rejection across all statuses |
| RT1-F9 | ceremony teaching is text-only | PARTIAL — frozen-string contract hints (R-61) land; PR-body lint via gh deferred (aggregates retired for this repo) |
| RT1-F10 | CI base semantics + [skip ci] residual | PARTIAL — first-parent semantics pinned (R-60); [skip ci] accepted residual, noted for P23 |
| RT1-F11 | retro-stamp indistinguishable from live stamps | ACCEPT — R-63: completed_at_retro marker |
| RT1-F12 | optional:true unbounded | ACCEPT — R-66: optional legal only on gitignored paths |

### Round 2 — EDGE

| ID | Finding | Disposition |
|:--|:--|:--|
| RT2-F1 | fromCommit catch swallows archive failure → advance anyway → one-step -der creation (Lv3 too) | ACCEPT — R-62(b): half-tx completion or refused advance |
| RT2-F2 | PR merge-ref diff false-greens stale PRs | ACCEPT — R-60: `mb...PR_HEAD_SHA` + fetch-depth 0 |
| RT2-F3 | unknown-base fallbacks undefined | ACCEPT — R-60: per-case verdicts (exempt-loud / fail-closed / file-shape) |
| RT2-F4 | promote day contradicts the [Unreleased]-only predicate | ACCEPT — R-60: newest-version-section shape + promote fixture |
| RT2-F5 | literal re-key re-arms false-reds (clones, pre-convention residents) | ACCEPT — R-62(c) disjunction |
| RT2-F6 | rename collision wedges milestone chain | ACCEPT — R-65 |
| RT2-F7 | dig floor has no grandfather clause → freeze deadlock | ACCEPT — R-67 era semantics + loud advisory |
| RT2-F8 | --help value-position + unknown-command exit 0 | ACCEPT — R-64 |
| RT2-F9 | SHIP ritual base: committed-only diff misses fresh bullets | ACCEPT — R-60: task_head vs working tree |
| RT2-F10 | lint obligation removal leaves no backstop; census axis interactions | PARTIAL — obligation lives in gate --audit (base-ful); R-66 axis semantics pinned (no stacking, source-3 unconditional) |
| RT2-F11 | CI carrier for the obligation unnamed | ACCEPT — R-60 names the carrier steps and inputs |
| RT2-F12 | completed_at second semantics | ACCEPT — R-63 retro marker |
| RT2-F13 | PR-flow hint breaks plain-git repos | ACCEPT — R-61: branch on git remote presence |

### Round 3 — COMPLETENESS

| ID | Finding | Disposition |
|:--|:--|:--|
| RT3-F1 | dig floor unimplementable in the floor-probe sequence; would lock P19 itself | ACCEPT — R-67: freeze-time check outside SPEC_CARD_FLOORS, era field, grandfather+advisory |
| RT3-F2 | R-66 premise falsified: fresh clone passes pack-check today (verified by experiment) | ACCEPT — R-66 re-grounded: hotfix cleanup + explicit-declaration axis + negative control |
| RT3-F3 | literal re-key re-arms dffa50f0 on fresh clones (tracked state, machine-local archive) | ACCEPT — R-62(c) disjunction |
| RT3-F4 | promote-day contradiction + rewrite-as-new laundering | ACCEPT — R-60 amendments |
| RT3-F5 | R-63 has no CI-verifiable surface; in-repo one-off script fails pack-check | ACCEPT — R-63: manual ritual + local-only truth + receipts evidence |
| RT3-F6 | non-git repos lose the obligation entirely | ACCEPT — R-60: file-shape fallback |
| RT3-F7 | --help over-broad predicate; ordering vs guardCwd; help --json stability | ACCEPT — R-64 |
| RT3-F8 | fixture/churn inventory missing; T57-G3 flips; README.md tracked-render declaration; T109+ numbering | ACCEPT — §9 Fixture impact added |
| RT3-F9 | rename: registry wiring, name grammar, --expect guard, old→new output | ACCEPT — R-65 |
| RT3-F10 | ceremony surface is prose | PARTIAL — same as RT1-F9 |
| RT3-F11 | CI steps must resolve changelog path via the root-anchored resolver | ACCEPT — R-60 |
| RT3-F12 | third absence axis vs transient/lifecycle undefined | ACCEPT — R-66: optional subsumes derived transient per entry; no stacking |

## 8. Deferred Ideas

- Class-level rebuild of the five sibling archives if the retrospective
  surface (P2) ever needs state detail beyond delta.md.
- Requirement amend verb (concern 690bcff8).
- Router INTENT staged gates mechanization (4f316c16).
- PR-body closing-keyword lint (gh pr view) at the push/merge flow layer.
- `[skip ci]` landing backstop in the P23 release-gate batch.

## 9. Fixture impact (BUILD churn inventory)

- T53/T54/T55 family: obligation copy + todayUtc injection fixtures move
  to the structural predicate.
- T57 G3 ("today bullet in a version section still blocks") flips to pass
  under the amended predicate — update the fixture contract.
- T76: archivePushHint assertions move to the new frozen copy.
- T61/T8/T27/T50: idle guard + idempotency + archive-chain fixtures gain
  the disjunctive and repair-branch cases (T2/T3 truth fixtures).
- T66 + pack-check + `--fresh` mode: census optional-axis cases (T7).
- T63/T29: command registry self-check picks up `phase rename`.
- T71/T37/T2: phase-verb coverage for rename (collision refusals).
- T101: neutralizer contract stays — add the guard assertion that it is
  unchanged (D-61).
- New sections take numbers T109+ (tree already carries T35 collision
  debt; check `ls test/sections/` before creating).
- ci.yml edits: YAML block-scalar indentation class (cd2e99a1) — the CI
  parse backstop covers it; keep the diff minimal.
- .gos/README.md re-render from `phase rename` is a TRACKED artifact —
  declare it in plan Files (10790226).
