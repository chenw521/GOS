# P4 Spec — Repo Content Policy (sanitized tracked state, flip gate, navigator contract)

Phase: P4 · Level 3 · Intent: Sanitized tracked state as an opt-in product capability
(clone-resume for private collaborative repos) with self-repo opt-out; schema v4
cleanup; tracked-flip transaction gate; stage-back gap exhaust single-sourced;
navigator directory contract. Issues: #11 (file-availability half), #24 (re-triage).

> Red Team: R1 (misuse, 14) + R2 (edge, 14) + R3 (completeness, 12) all
> dispositioned and folded below (RT1-Fn / RT2-Fn / RT3-Fn markers).

## 1. Problem

Tracked `.gos/` state carries machine-local payload and has no product story for
private-collab clone-resume; the ignored→tracked boundary has no transaction
enforcement; `stage back` dual-writes gap exhaust (88 auto mirrors) into
concerns.md; `.gos/codebase/` mixes three artifact tiers under one directory with
a drifting guide layer and a mislabeled byproduct report.

## 2. Decisions (recorded via `gos decision add`)

| ID | Decision |
|:--|:--|
| D-12 | Identity de-pathed: v4 drops `version` + `project_root`; `repo_id` = remote-URL hash; root runtime-derived. No-remote: advisory. |
| D-13 | Dialogue governance → phase P5 (not P4). |
| D-14 | Obligations attach to tracked files; no repo-mode flag; self-repo opt-out = negative test assertions. |
| D-15 | Flip gate = `gos track` executor + `gos gate` reconcile leg; no hook layer. |
| D-16 | 88 auto mirrors → `.gos/logs/gap-history.ndjson` (untracked); concerns.md curated-only. |
| D-17 | Language boundary at GOS text stores, tracked-conditional. |
| D-18 | repo_id matched against all remotes; normalization matrix. |
| D-19 | BUILD adds: self-repo knowledge refresh + THINK navigator hint. |
| D-20 | Navigator tiers: data (map trio, tracked) · guide (hand-written trio, flips+stamp) · byproduct (renamed, regenerates, header). |

## 2.1 Decision cards (dialogue artifacts, gate-enforced)


### D-12: identity de-pathing — how does the lock guard identify the repo?

| Option | Premise | Pros | Cons | Risks |
|:--|:--|:--|:--|:--|
| repo_id hash (chosen) | guard's real job is repo identity, implemented today as path equality | keeps cross-repo guard strength; kills machine paths; worktree churn ends | new field + migration | remote URL churn needs anchor fix |
| no guard | minimal surface after dropping paths | simplest | loses anti-contamination net | 3 permanent lessons document the incident class |
| keep field null | template already nulls it | smallest diff | forever-dead field contradicts v4 cleanup | semantics confusion |

why-not: no guard — documented incident class (d6c3264d/a152b6dc); keep field null — v4 exists to remove dead fields, not add one.
recommendation: repo_id hash — conditional: downgrade to no-guard + status hint if no-remote private repos prove mainstream.

### D-13: dialogue-presentation governance — where does it land?

| Option | Premise | Pros | Cons | Risks |
|:--|:--|:--|:--|:--|
| independent small phase | fix is skill-contract text + thin-gate column, small blast radius | right-sized; ships before P2 | one more phase | scheduling overhead |
| P4 absorbs | session relapse evidence is fresh | soonest | P4 scope grows beyond content policy | dilutes exit gate |
| stay in P2 | cab1a0f8 family (decision science) | batch coherence | P2 parked past release — governance stays unfixed | recorded-but-undelivered (#15/#21 pattern) |

why-not: P4 absorbs — scope creep dilutes P4's exit gate; stay in P2 — parked = no teeth (this session's relapse proves it).
recommendation: independent small phase — conditional: phase created as P5 this session.

### D-14: opt-in mechanism — how do repos declare collab tracking?

| Option | Premise | Pros | Cons | Risks |
|:--|:--|:--|:--|:--|
| obligations attach to files | census + cjk-whitelist already form the file-attached signal surface | zero new truth source; opt-out = one negative assertion | capability described by docs recipe | future same-set-different-policy needs a mode |
| config profile flag | explicit, predictable gate behavior | auditable | fourth truth source needing reconciliation | #20 three-ledger precedent |
| derived mode | no flag, gate infers from tracked set | always matches reality | inference rule itself becomes a contract | debugging indirection |

why-not: config profile flag — #20 precedent with no real requirement; derived mode — one more indirection for a word.
recommendation: obligations attach to files — conditional: upgrade to config flag only if same-set-different-policy emerges (with #20 reconciliation landed first).

### D-15: tracked-flip gate architecture

| Option | Premise | Pros | Cons | Risks |
|:--|:--|:--|:--|:--|
| command + product gate | executor guarantees atomicity, shipped detection guarantees visibility | single-process surgery w/ rollback; gate leg covers all repos | new command surface | detection latency until next gate run |
| + pre-commit hook | commit-time interception | zero-latency catch | hooks opt-in per clone, --no-verified bypassable | taxing all commits for rare events |
| docs recipe only | flips are rare | zero surface | intent says ENFORCING | gitignore hand-surgery has incident record (d2477ec8) |

why-not: + pre-commit hook — bypassable prevention taxing every commit; docs recipe only — not a gate, contradicts intent.
recommendation: command + product gate — conditional: add hook layer when a real rogue flip costs more than a gate round-trip.

### D-16: curing the 88 auto mirrors

| Option | Premise | Pros | Cons | Risks |
|:--|:--|:--|:--|:--|
| migrate to local ledger | event history earns one file | reversible; concerns.md returns to curated-only | one-time migration cost | ledger can become dust |
| delete outright | mirrors have no mechanical consumer | simplest | only structured event history lost, irreversibly | future audit has no source |
| keep + stop increments | zero migration risk | — | violates intent "cured"; disease remains | 88 lines keep polluting |

why-not: delete outright — irreversible (user initially chose this, then revised); keep + stop — intent already ruled the cure.
recommendation: migrate to local ledger — user final ruling; dust check after 6 months.

### D-17: language boundary placement (CJK × tracked state)

| Option | Premise | Pros | Cons | Risks |
|:--|:--|:--|:--|:--|
| write-path single point | boundary condition is a file property (tracked?) | one check covers ALL text fields | hot-path cost (cached git probe) | CJK rejection friction for zh users |
| per-command patches | only some commands take user text | precise | scattered checks | new commands forget = silent holes (2a8df30f shape) |
| whitelist state.json | zero new check code | one step | CJK enters public history | fail-closed structure eroded by wholesale exemption |

why-not: per-command patches — coverage holes by construction; whitelist state.json — exemption channel misuse, breaks public discipline.
recommendation: write-path single point — conditional: degrade to schema-layer check only if measured cost >10ms/cmd.

### D-18: repo_id matching semantics

| Option | Premise | Pros | Cons | Risks |
|:--|:--|:--|:--|:--|
| all-remotes + normalized hash | protocol heterogeneity (https/ssh same repo) is first-class | fork passes via upstream; tokens stay out | normalizer needs test matrix | unseen URL forms mismatch (anchor fix rescues) |
| origin-exact | private collab shares origin | simplest | fork rejected; protocol mix rejected | false positives erode guard credibility → bypass culture |
| plaintext URL | debuggable | readable | URLs carry credentials/usernames | contradicts sanitization premise |

why-not: origin-exact — false-positive machine (https/ssh mixing is normal on GitHub); plaintext URL — the phase IS about sanitizing tracked state.
recommendation: all-remotes + normalized hash — conditional: narrow to origin+upstream two-level if normalizer exceeds ~80 lines.



### D-19: self-repo knowledge refresh + THINK navigator hint in P4?

| Option | Premise | Pros | Cons | Risks |
|:--|:--|:--|:--|:--|
| in P4 | recipe without a reference implementation is paper; drift poison is live (4800-line claims injected every task) | dogfoods the flip recipe; this phase benefits directly | +1 BUILD task (small) | mild scope growth |
| separate small task | clean P4 boundary | focused rebuild | context switch; poison keeps firing | never gets scheduled (#21 family inertia) |

why-not: separate small task — recorded-but-unscheduled is the documented #21 failure mode.
recommendation: in P4 — conditional: as a late-BUILD independent task; may slip to milestone closeout if BUILD overflows.

### D-20: navigator tiers — what travels and what regenerates?

| Option | Premise | Pros | Cons | Risks |
|:--|:--|:--|:--|:--|
| tiered (guide flips w/ stamp, data tracked, byproduct regenerates) | only non-regenerable assets earn travel; gate inputs need cross-machine identity | set = hand-written trio; untested-fns regenerates per gate run | stamp wiring at track+map | manual edits can miss stamp refresh |
| four files (intent literal) | matches intent enumeration | none | tracks a gate OUTPUT (build artifact, dfb28c0f family) | per-gate dirty worktree; stale list misleads clones |
| four files + gate age leg | lifecycle enforcement | staleness becomes visible | new gate leg = new scope | #21 family belongs to P2 |

why-not: four files (intent literal) — tracking derived build artifacts violates census disposition philosophy; gate age leg — right direction, wrong phase (P2).
recommendation: tiered — conditional: mechanical stamp upgrades seamlessly to a P2 lifecycle leg's anchor if that lands.



### 3.0 Shared fail-closed probe primitive (RT1-F1/F2/F7 root cause)

New module `bin/lib/core/gitprobe.cjs` — the ONLY sanctioned "tracked?/ignored?"
policy probe:

- `isTracked(path)`: `git ls-files --cached -- <path>` ∪ `git cat-file -e
  HEAD:<path>` (index ∪ HEAD). Any git failure (non-zero exit, stderr,
  exception, poisoned GIT_DIR/GIT_INDEX_FILE) → **treated as tracked**;
  failure state cached distinctly from untracked.
- `ignoredSet(paths)`: single `git status --porcelain -uall --ignored=matching`;
  check-ignore exit codes (0/1/128) never collapsed to boolean.
- Canonical repo-relative path: derived from `realpath` (fixes case-insensitive
  FS drift, RT2-F14); argv ≠ canonical → die with correction hint
  (`diskHasCaseVariant` precedent).
- Atomic-write primitives: try/finally unlink tmp residue (RT2-F10).
- Consumers: §3.2 boundary, §3.4 track validation + gate leg. No other module
  probes git for policy decisions.

### 3.1 Schema v4 (D-12, D-18; RT1-F8, RT2-F9/F11)

- `migrateState` v3→v4: delete `version`/`project_root`, add `repo_id`; lazy
  at first write-class command (D-10 precedent). Future-version guard unchanged.
- `repo_id = sha256(host + ':' + port + '/' + path)[:16]`; host lowercased
  (IPv6 literals KEEP brackets, hex lowercase — RT2-F11; matrix row added);
  port defaults (22/443/9418) filled from scheme; path case-preserved,
  trailing `.git`/slash stripped, credentials stripped; scp-form → `host:22/…`.
  Case-insensitive matching only at comparison (lowercase second pass). Test
  matrix: scp/ssh/https/git-proto/port-explicit/default/credentials/trailing
  .git/slash/case/IPv6.
- URL reads argv-form only; URL text never lands in state (hash only); URL
  interpolated into output passes `sanitizeEcho`.
- Lock guard: stored repo_id ∈ remote hashes (exact, then lowercase) → proceed;
  null + remotes exist → derive+store; mismatch → die with `gos map anchor fix`
  hint; no remotes → advisory once. Guard = coherence check, NOT
  anti-exfiltration. Subdir walk unchanged. **Worktree guard (RT2-F9)**: when
  `--git-dir ≠ --git-common-dir` (linked worktree) AND state.json tracked →
  die with worktree guidance (shared-lock redesign deferred, scope guard).
- All `state.project_root` consumers → `currentRootRealpath()` (cached).
  `gos map anchor fix` re-derives repo_id.

### 3.2 Language boundary at GOS text stores (D-17; RT1-F1/F6, RT2-F7)

- Trigger: ANY GOS text store tracked (state.json ∨ concerns.md ∨ lessons.json,
  via §3.0, fail-closed). All untracked → no constraint.
- Scan: recursive string-leaf walk of the store's JSON; CJK → fail-closed,
  bilingual guidance.
- **Remediation for frozen fields (RT2-F7)**: `gos gap rewrite <G-id> --text
  "…"` subcommand (description rewrite, sanitized); intent summary remediation
  via existing stage-back path. Flip-time pre-scan (§3.4 step 2a) reports all
  three stores BEFORE any mutation.

### 3.3 Gap exhaust single-source (D-16; RT1-F5, RT2-F6/F8, RT3-F4/F9)

- `stage.cjs` drops the mirror call.
- Migration is a PRODUCT command `gos gap migrate` (RT3-F4 — the shipped
  `stage.cjs:31` mirror has already polluted every downstream repo; a
  repo-local script would strand them): wrapped in `concernsRootLock`,
  idempotent via completion sentinel, `{ts,text}`-deduped ledger appends:
  1. write ledger records for ALL `(auto)` lines (dynamic count, RT3-F9 —
     never hardcode 88)
  2. edit concerns.md first, then rebuild anchors from retained lines in the
     same transaction (concerns.cjs:77-84 precedent order), sync `.bak`
  3. abort on any inconsistency → restore from in-transaction backup
  - Self-repo is the command's first caller (BUILD task).
- Read surface: `gos gap history` (per-line try→skip+count, never crash).
- **Fresh-clone anchor bootstrap (RT2-F6)**: anchors missing ∧ tracked
  concerns.md ∧ `git hash-object(worktree) == HEAD:.gos/concerns.md` → rebuild
  anchors silently; mismatch (real out-of-band edit) → die (anti-whitewash
  holds).
- Ledger untracked (gitignore + census entry).

### 3.4 Tracked-flip transaction gate (D-15; RT1-F2/3/4/7/9/10/14, RT2-F2/F3/F5/F12/F13)

New product command `gos track <path>` — scope `.gos/**` only, no escape:

1. validate: canonical path (§3.0); `lstat` regular file, `!isSymbolicLink()`,
   realpath inside repo root; never-track zones (`.gos/archive/`, `.gos/logs/`,
   `.gos/cache/`, `.gos/.lock`, `.gos/.ship-staging/`) → die; unborn HEAD → die
   with teaching (RT2-F12); precondition = NOT tracked (index∪HEAD, §3.0 —
   RT2-F2: brownfield repos have untracked-but-not-ignored files; gitignore
   surgery runs only when target ∈ ignoredSet); census.json present → entry
   git:false; **already-tracked (RT3-F7): manifest record present ∧ census
   consistent → exit 0 no-op; legacy-tracked without manifest → ADOPT: append
   `{adopted:true}` record after census consistency check, exit 0; census
   contradiction → die**; argv case-variant of canonical path → die with
   correction hint (RT3-F12, T6 negative)
2. language: **pre-scan ALL THREE trigger stores (§3.2) + target file**,
   per-store report, die-before-touch; then independent single-file CJK scan of
   target (same regex class as cjk-lint; cjk-lint.sh untouched, no whitelist
   dependency — RT1-F9)
3. sanitize: runtime (`os.homedir()`, `os.tmpdir()`) ∪ fixed (`/home/`,
   `/Users/`, `/root/`, `/mnt/`, `/srv/`, `[A-Z]:\Users`, `~`, `file://`) ∪
   `os.hostname()` exact; **hit → die-before-touch reporting the hit line**
   (same shape as language pre-scan, RT3-F3); scan covers target content only
   (manifest/census notes written by the command itself are constructed
   verified)
4. gitignore surgery (RT2-F3, RT3-F1): append negation to **`.gos/.gitignore`**
   (deeper file wins over root-directory excludes; same-file negation provably
   loses to parent-dir rules). **Pattern is relative to `.gos/`** (nested
   .gitignore anchoring: `!/concerns.md`, NOT `!/.gos/concerns.md`); create
   file if absent (brownfield precedent); CRLF-normalized; verify: pre/post
   ignored-set diff == {target} else rollback. T6 includes a positive case:
   root .gitignore has file-level exclude → deep negation works.
5. census edit (census-if-present): git:true + note
6. **flip manifest (RT2-F5)**: append record to `.gos/track-manifest.json`
   (tracked; `{ts, path, head}` per-line JSON), making flips auditable in ANY
   repo
7. `git add` target (+ `.gos/.gitignore` + manifest); manifest printed
- Backups: rename-style staging into `.gos/cache/track-backup/` (rollback =
  rename back — ENOSPC-safe, RT2-F10); success deletes staging.
- Failure at ANY step → all stores restored, exit 1.
- `--knowledge` preset: guide trio + `born-at: <HEAD[0:8]>` first-line,
  idempotent replace.
- Gate flip-reconcile leg (shipped): **file-granular (RT2-F4)** — tracked set =
  `git ls-files -z -- .gos`; per file, expected value from most-specific census
  key (census-if-present); `lifecycle:true` keys exempt from existence
  assertions; census `.gos/**` entries with git:true but untracked (and
  inverse) → FAIL; any tracked `.gos/**` file outside never-track zones
  without manifest record → FAIL in census-less repos too (manifest is
  product-shipped); isTracked via §3.0 (fail-closed). Fix lines via `gateCmd`.
- Self-repo negative assertion (D-14): guide trio + concerns + lessons stay
  git:false in census (test-enforced).

### 3.5 Navigator directory contract (D-19, D-20)

- Rename `untested-fns.txt` → `unmapped-fns.txt`; gate writes `generated-at:
  <ISO> @ <HEAD[0:8]>` header; wording "unmapped fn(s) without test annotation".
- Guide trio born-at stamps (track preset; self-repo refresh stamps manually).
- codebase-mapping.md documents directory contract + travel tiers (closes #11
  file-availability half).
- THINK context: navigator hint line (closure/blast, parity with BUILD's
  blast_hint wiring in context.cjs).
- Self-repo knowledge refresh (BUILD task): cure drift ("~4800 lines" →
  262-line entry + bin/lib tree), refresh stamps; repo stays opted OUT.

### 3.6 #24 (include; RT1-F12 + RT2-F1 + RT3-F6 neutralization)

Changelog validator accepts `#N`. Neutralization at **commit time** (single
choke point BEFORE the message enters history, covering BOTH channels —
aggregate push AND raw-push/PR squash, RT3-F6): keyword set
`{fix, fixes, fixed, close, closes, closed, resolve, resolves, resolved}`
(case-insensitive, `\s+` separators) adjacent to `#N` in ANY staged commit
message line (subject + body) → rewritten to `refs #N`. Auto-close only via
explicit structured `closes:` field (not P4). T10 asserts: bullet `fixes #12`
→ committed message (subject AND body) contains NO trigger sequence, in both
push channels.

### 3.7 Wiring checklist (RT3-F5 — lesson 68ceb54b, its self-declared R3
### must-check) + deferred parking (RT3-F10) + probe monopoly (RT3-F11)

Every new surface ships with ALL FOUR wirings, each grep-verifiable:
1. skill/doc routing lines (codebase-mapping.md directory contract, README
   command families, AGENTS.md touchpoints)
2. CLI hard gates with `gate.<code>` contract codes; `gos track`/`gos gap
   migrate`/`gos gap rewrite` exit codes registered
3. **command registry** (state.cjs table: class/desc + `--json` envelope) AND
   **GOS_PATHS registry** entries for track-manifest / gap-history /
   track-backup (`paths --markdown` regen, no readme-drift)
4. **i18n catalogs**: all new user-facing strings live in locales/en.cjs
   (canonical) with zh.cjs mirror — no inline strings

Deferred items get ENFORCED parking (d1d02a55): two `gos concerns add` entries
at BUILD — cross-worktree shared-lock redesign (anchor: rt2-f9), P5 dialogue
governance handoff (anchor: d-13) — orphan-discovery gate reads the anchors.

gitprobe monopoly is CODE: new banned-strings check — `bin/lib/**` except
gitprobe.cjs must not contain policy-type `ls-files --cached` / `check-ignore`
/ `--ignored=matching` invocations (test/checks/).

## 4. Scope guard

NOT in P4: dialogue governance (P5); knowledge lifecycle gate leg (#21/P2);
hook layer (evidence-triggered); config repo-mode flag (rejected); `--any-path`
(rejected); archive state snapshots; **cross-worktree shared-lock redesign
(RT2-F9 detection-only here)**.

## 5. Observable Truths (draft — register via `gos truth add`)

1. **T1 schema**: no `version`/`project_root`; `schema_version: 4`; repo_id
   16-hex or null. Fresh clone + write-class cmd → state.json byte-identical.
2. **T2 clone-resume**: clone with tracked state: `gos status` works; remotes
   match across protocol variants; worktree stays clean; tracked concerns.md +
   missing anchors bootstrap silently (RT2-F6).
3. **T3 identity**: foreign-remotes state → write-class dies w/ anchor-fix
   hint; URL matrix (11 forms incl. IPv6) → expected ids; worktree +
   tracked-state → die w/ guidance.
4. **T4 language boundary**: any store tracked + CJK into any string leaf →
   exit 1 + guidance; GIT_DIR poisoning → still fires; all untracked →
   accepted; `gos gap rewrite` clears legacy CJK description.
5. **T5 gap single-source**: zero `(auto)` lines remain; ledger_count ==
   removed_count (dynamic, no hardcoded 88); `gos gap migrate` idempotent on
   re-run; `gos concerns list` exits 0; `gos gap history` works; `stage back`
   never touches concerns.md.
6. **T6 flip transaction**: fixture (with/without census): track flips
   atomically (negation in `.gos/.gitignore` relative-anchored,
   ignored-diff == {target}, census+manifest+stamps); root-exclude positive
   case; injected failure → all restored; sanitize hit (a `/home/` line, a
   hostname line) → die-before-touch with hit-line report; negatives: `.env`
   → die, symlink → die, `.gos/archive/x` → die, unborn HEAD → die, re-run
   tracked target → exit 0, legacy-tracked no manifest → adopt record + exit
   0, case-variant argv → die with correction.
7. **T7 gate leg**: census git:true but untracked (and inverse) → FAIL;
   tracked `.gos/**` w/o manifest (census-less repo) → FAIL; lifecycle:true
   `.gos/task` post-archive → no false FAIL.
8. **T8 navigator**: `unmapped-fns.txt` header; "unmapped" wording; THINK
   context JSON has navigator hint.
9. **T9 knowledge refresh**: `grep -r 4800 .gos/codebase/` empty; born-at
   stamps == the HEAD recorded in the refresh evidence ledger (not live HEAD —
   RT3-F8: later stage commits move HEAD).
10. **T10 #24**: `fixes #12` bullet accepted; aggregate subject AND body
    contain no trigger sequence (neutralized).

## 6. Risks / lesson wiring

- Section runners never parallel (63675448); bracket-escape asserts (265a5dd3);
  section ids max+1 (855aa993); census lifecycle entries, explicit paths
  (dfb28c0f); renames declare both sides (10790266); plan edits assert-matched
  (96615604); wave executors never self-commit (be49bdd4).

## 7. Open items for PLAN

- Waves: (a) gitprobe + schema v4 + guard + worktree detection; (b) write-path
  boundary + gap rewrite; (c) `gos gap migrate` + history reader + anchor
  bootstrap; (d) track command + manifest + gate leg; (e) navigator bundle +
  knowledge refresh + THINK hint; (f) #24 commit-time neutralization; (g)
  wiring checklist (§3.7) + docs (#11 half) + census/gitignore entries.
- **Test mutation table (RT3-F2 — ead7fa41)** — existing assertions P4 breaks,
  each needing an in-wave update: T1-schema (schema_version==3 → 4); T2-project
  (project_root anchor assertions removed); T5-guard (lazy re-anchor semantics
  → repo_id); T10-security-e2e (fake anchor-root injection → repo_id fixture);
  **T23-concerns (stage-back `(auto)` mirror assertion INVERTED to
  never-touches)**; T35-codemap-coverage (untested-fns.txt rename + header
  line shifts line-count math); goldens help.txt/contract.txt (anchor/paths
  desc strings); T82 (v3 fixture → v4). SHIP assertion pins **main suite RC=0**
  (ead7fa41), self-repo assertions re-run `--fresh` (2c8e1978). Self-repo v4
  migration mid-task is safe: `.gos/**` sits in the gate undeclared-diff
  allowlist (gate.cjs:87); task_head baseline and edges.lock unaffected.
- Test section numbers reserved against test/sections/.
