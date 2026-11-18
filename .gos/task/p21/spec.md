# Spec: P21 auto loop robustness

> **Date**: 2026-11-18 | **Level**: Lv3 | **Status**: Draft

## Goal

Make `gos auto` survivable on a real host: the VERIFY script spawn must run the section suite green inside the bwrap sandbox, the loop must survive operator terminal death, local branches must have a content-landed reaping tool, and the dig-closure floor must mechanize card discipline before auto re-enables.

## Motivation

The 2026-11-09 dogfood run burned the full spawn budget (B=30, layer B TRIPPED at 10:49Z) in VERIFY: the sandboxed section runner died on a read-only `.gos` (`run-manifest.json: Read-only file system`, full log `5419521c-…-1-sections`), and 95 environment-dependent section failures kept the exit code at 1 (`test/run-sections.sh:304`) even where writes succeeded. Separately, spawned BUILD workers die through the `--die-with-parent` pdeathsig chain when the operator terminal times out, and 18 local branches look unlanded to every stock git tool because squash-merge erases patch-ids. During this phase's own THINK, a card was twice shipped with known-undug items — the discipline gap that D-106 mechanizes.

## Requirements (R-NN)

- **R-1**: VERIFY script spawn composes with a **step-level enumerated writable set** (`.gos/cache` plus each individually-proven write point, e.g. the lessons files) — the whole `.gos` tree is forbidden; `compose()` fails closed when `meta.writableShadowed` is non-empty (turning the existing detection into a gate); three compose invariants asserted (writable ⊆ enumerated set, workspace stays ro-bind, argv never carries `--unshare-pid`/`--unshare-all`).
- **R-2**: Class S env is composed from a source-side whitelist (commit-channel env never injected into script spawns; `run-sections.sh` unset becomes defense-in-depth); the whitelist is a single exported registry (`ALL_GOS_AUTO_ENV`) spanning loop/launcher/redteam injection sites, with a drift assertion section (every `GOS_AUTO_*` literal in bin/ ⊆ registry) and a loud runner guard.
- **R-3**: Self-repo sections run against a `git worktree add --detach` full checkout under TESTBASE (no shallow — the mechanism does not exist; disk preflight fails loud); node_modules ro-bind/hardlink from the real repo (sandbox has no network); Class S compose injects a pre-created absolute TESTBASE pin; the helper is idempotent (prunes its own worktree prefix) and `git worktree prune` joins the leak sweep; `head_tree` in the manifest comes from a `GOS_SECTIONS_TREE_OVERRIDE` pin (live rev-parse only when unpinned, source distinguished).
- **R-4**: The 95 failures triage to zero with a machine-checked acceptance: sandbox run-manifest `sections_run` ≡ the full `T*.test.sh` set (name+count, compared in a gate script), per-section pass counts ≥ a tracked baseline snapshot, and the triage dispositions land in a tracked ledger (fixed/converted/anchored-by). The only legal exit for machine-local-state sections is XDG/fixture conversion — widening writable roots or skipping is forbidden in R-4 text.
- **R-5**: `gos auto run` defaults to detached: the detacher forwards the original argv (minus detach-class flags) plus a child-contract flag forcing the child foreground — no re-detach chain (negative invariant test); the child writes a lock-acquired sentinel and the parent forwards output and exits non-zero if the sentinel does not arrive ("started" is proven by lock, not fork); `--fg` opts back in with a risk note; `--die-with-parent` unchanged; run logs rotate (keep last N).
- **R-6**: `gos branch reap`: tree-membership under `GIT_NO_REPLACE_OBJECTS=1` (refuse tier-1 outright when `refs/replace` or `info/grafts` is non-empty); `--apply` requires an explicit `--base <ref>` passing freshness validation; hard namespace exemptions (`chain/*`, `refs/reaped/*`, the active task's branch, anything checked out in any worktree incl. pin-worktrees); live run-lock blocks `--apply`; deletions land as `git update-ref refs/reaped/<branch> <tip>` (objects stay reachable past gc; ledger is the index), revive rebuilds from the ref; output is machine-parseable JSON with `action: delete|manual|keep` and argv-array commands; unborn/no-main fails loud.
- **R-7**: Dig-closure floor: a decision records only with a syntactically-closed deepen line **and ≥1 dig evidence object** (zero anchors = refusal — empty enumeration is a failure state, not a pass); `--dig-waiver` is refused inside marker sessions (human channel only); anchors are stamp-time-ordered before card freeze (store stamps reused); token-format and why-not-hit floors stay with P24 v4.
- **R-8**: Re-enable gate: `gos auto on` refuses while any breaker layer is TRIPPED unless the store's latest run record for the repo reads INTENT→SHIP green with the sandboxed VERIFY step passed (evidence read by the command itself, not runbook order); after R-1..R-7 + R-9 + R-10 land, one full auto cycle on the dogfood store runs green end to end, then counters reset through that same path.

- **R-9**: Class S deny scoring counts only `kind === 'command'` hits (streaming `preTruncationDenyHits` and post-hoc scan alike); a persisted full-suite log fed to the scanner must yield zero step-failing hits. Regression anchor: the 2026-11-09T04:38 VERIFY trip detail (deny 'sudo' ✓ lines from the suite's own output).
- **R-10**: THINK-trip triage (`terminal ok but no new stage-labeled commit reachable from HEAD`, store 2026-11-09T09:17): root-caused from the store record plus the section-runs log of that window, with a regression truth simulating the cause; R-8 does not execute before this lands.

## Observable Truths

- **T-1**: A sandboxed VERIFY spawn writes its manifest into the TESTBASE namespace (`$TESTBASE/run-manifest.json`, pinned — the repo-root manifest belongs to literal runs only) and the section-runs log is retrievable; the suite exits 0.
- **T-2**: The store's VERIFY step record for the sandboxed run reads **passed** (suite printing `0 failed` alone is not enough — the deny scorer must not fail the step on the suite's own output).
- **T-3**: `gos auto run` backgrounds itself (prints pid + log); after the launching terminal exits, `gos auto status` still shows fresh heartbeats; `--fg` still works; a second concurrent run surfaces its lock refusal to the operator (sentinel contract).
- **T-3b**: A detached loop SIGTERM'd mid-VERIFY restarts to consistent state (or rolls back via the crashed-advance path with a visible warning line), leaves no zero-byte orphan lock, and the next cycle does not pause.
- **T-4**: `gos branch reap --dry-run` lists all 18 local branches with `action: delete|manual|keep` in JSON; `--apply` leaves only keep-tier branches; every deleted tip is revivable from `refs/reaped/<branch>` past any gc.
- **T-5**: Negative gate tests cover: open deepen line, unanchored enumeration, waiver-only evidence inside a marker session, forged anchor (post-freeze stamp), and the omission card (zero anchors, closed line) — spec-gate refuses all five; all P21 cards pass the same gate.
- **T-6**: The THINK-trip cause (R-10) is reproduced and neutralized in a regression truth; the dogfood cycle completes INTENT→SHIP green in one run with the store VERIFY step passed; `gos auto on` succeeds through its evidence gate; breaker counters read zero.

## Approach

### Selected Approach

P1 restricted skeleton (enumerated writable roots under `.gos` per R-1 — the whole-tree form in D-107's premise wording is superseded; source-side env registry; worktree fixture-ization), default-detach survival, two-tier branch reaping, and the minimal dig-closure floor — all under the existing restricted profile and mask invariants.

### Alternatives (Rejected)

- ~~workspace-profile compose for VERIFY~~ — the env leak and lock clash are profile-independent, so widening the profile buys nothing and costs the verifier's write boundary (D-107).
- ~~lock env redirection / lock release window / unshare-pid~~ — each opens a dangerous product surface or a stale-break hazard; fixture-ization resolves lock+state+writes at once (D-108).
- ~~attach default + recovery patches~~ — death still burns spawn budget every terminal timeout; recovery machinery already exists (D-109).
- ~~patch-id hybrid reaping~~ — patch-id is squash-blind by evidence; mixing it in only adds false-delete risk (D-110).
- ~~full card floor v4 in P21~~ — token-format and why-not-hit assertions stay with P24 on the shared floor-registry extension point (D-106).

## Design Decisions (D-NN)

### D-106: dig-closure floor in P21

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| M1 | minimal loop in P21 — auto THINK spawns present cards this phase | protects P21 itself; P24 reuses the skeleton | scope +1; heuristic first cut | spec-gate floor registry + card template |
| M2 | all in P24 v4 — P24 owns card floors | single battlefield | P21/P3 window unprotected | future v4 |
| M3 | template-only hotfix — one doc line | fastest | no gate = discipline contract | skill readers only |

why-not: M2 — the re-enable window runs bare; M3 — an ungated template is the discredited trust-the-agent mode.
recommendation: M1 — deepen-closed required before record; gate rejects unanchored dig-target enumerations; v4 tokens stay in P24.
deepen: closed — floor registry (gate.cjs:1737), template closer (dialogue-protocol.md:55), anchor ledger (`--dig` objects), phase order all dug.

### D-107: VERIFY sandbox fix = P1 skeleton

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| P1 | writableRoots=[.gos] + env unset closure — EROFS spans cache/codebase/lessons; leak is profile-independent | verifier stays read-only outside `.gos`; store stays masked | sandbox may write any `.gos` file (env+store guards hold) | script spawn compose + runner unset surface |
| P2 | workspace profile + same fixes — dispatch one-line | (none — fixes still required) | pure trust-boundary loss | all stage profile resolution |
| P3 | cache-only + per-failure waivers — smallest first diff | — | three subtrees stay dead; waivers weaken VERIFY | new waiver contract |

why-not: P2 — the mandatory env fix proves widening buys nothing; P3 — fake economy, waiver machinery is the biggest hidden cost.
recommendation: P1 — mask-invariant assertion required; inject-set audit anchors R-2; residuals become R-4.
deepen: closed — EROFS line (run-sections.sh:301), exit law (:304), inject sites (loop.cjs:1420/1515-1518), mask order (launcher:253-258), pack-check neutrality (test/pack-check.sh:126).

### D-108: lock-clash isolation = fixture-ization

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| L-a | TESTBASE worktree helper for self-repo sections — scan/flip input is a file tree | resolves lock+state+writes at once | six-ish sections to convert | runner helper + self-repo sections |
| L-b | lock env redirection — one CLI change | small | product-wide lock bypass surface | lock.cjs consumers |
| L-c | lock release window — zero suite change | — | redesigns crash recovery + heartbeat | loop drive semantics |
| L-d | unshare-pid — one compose flag | — | kill -0 fails → stale-break of a live lock | every sandbox spawn |

why-not: L-b/L-c/L-d — bypass surface, recovery redesign, reverse-disaster break respectively.
recommendation: L-a — worktree (no network, exact HEAD tree); list from triage; T99 anchored.
deepen: closed — lock hardcode (lock.cjs:65), structural hold (loop.cjs:747-752), shared proc (launcher:233), T99 concurrent-classified live.

### D-109: survival = default detach

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| G1 | default detach, --fg opt-in — death chain is pdeathsig, not groups (spawnRun detached already) | zero new machinery; orphan-reaping intact | background loses live output | every auto run session |
| G2 | attach + recovery polish — death unpreventable | zero default change | budget keeps burning per timeout | recovery patches |
| G3 | pdeathsig-breaking relay — sandbox outlives runner | — | unreapable orphan sandboxes; new supervisor | sandbox lifecycle contract |

why-not: G2 — treats symptoms of a severed binding; G3 — destroys a working safety design for what G1 gives free.
recommendation: G1 — print pid+log+watch on start; `--fg` carries the risk note.
deepen: closed — spawnRun detached (spawnrun.cjs:80), die-with-parent (launcher:225), flag default (cli.cjs:359), recovery inventory (loop.cjs:793, store.cjs:1008-1035).

### D-110: branch reap two-tier

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| R1 | tree-membership + patch-content tier — 6/6 sampled hit | zero false delete; three-tier report + audit ledger | suspect tier stays manual | `gos branch reap` consumers |
| R2 | tree-membership only — smallest | zero false delete | potential zombies remain | same, smaller |
| R3 | patch-id hybrid — widest deletion | — | squash-blind evidence; false-delete risk | same, dangerous |

why-not: R2 — the suspect tier costs nothing and retires observation debt; R3 — proven-blind tool in the hot path.
recommendation: R1 — auto-delete only on tree-membership; audited tips revivable; dry-run default.
deepen: closed — 6/6 sample (f1/task-p0/dogfood/chore/docs/fix), chain semantics (push.cjs:236-255), delete surface (branch -D).

## Scope

### In Scope

- loop.cjs script-spawn compose writableRoots; run-sections.sh unset surface + worktree helper
- self-repo section conversions from the triage list; 95-failure triage itself
- auto run default-detach + `--fg`; branch reap command + audit ledger
- spec-gate dig-closure floor + card-template closed semantics; negative gate test
- dogfood re-enable run book (one green cycle then `gos auto on`)

### Out of Scope

- P24 floor v4 (token-format, why-not-hit assertions)
- sandboxing the `--fresh` CI-parity mode (helper may serve it later)
- patch-content suspect tier auto-deletion (report-only first)
- breaker limit tuning (N/K/B stay as-is)

## Deferred Ideas

- [DI-1]: patch-content equality tier for reap auto-delete (after first dry-run reports show a real zombie population)
- [DI-2]: `--fresh` mode sandbox compose reuse of the worktree helper (P21 lands the helper only)
- [DI-3]: agent-spawn writable surface (restricted `[.gos, .gos/logs]`, loop.cjs:1150-1153) — pre-existing trust-model territory; narrowing it to the R-1 enumerated form needs its own write-point census (red-team round 4, plan-attack F3)

## Red Team Record (Lv2+ mandatory before user approval)

| Round | Perspective | Findings | Dispositions (A/AP/R-with-facts/D) |
|:---|:---|:---|:---|
| 1 | misuse/safety | 10 (fork-bomb detach chain C; gc-rotten revive C; .gos-wide write + state tamper M; env patch at wrong end M; stale-main delete + chain wipe M; waiver/forged-anchor escapes M; omission bypass M; ungated auto-on M; output injection m; unbounded logs/worktrees m) | A ×9, AP ×1 (omission: structural inversion — zero anchors = refusal — is the code-reachable ceiling on knowing non-enumeration; waiver refusal + stamp ordering close the self-attestation half) |
| 2 | edge/exception | 10 (replace-ref ancestry forgery M; liveness gates M; lock refusal buried in detached log M; write-surface width + writableShadowed not gating M; audit anchored to wrong files M; fixture topology undefined M; head_tree not the tested tree M; unborn fail-loud m; detacher hardcoded argv m) | A ×10 (merged into R-1..R-6 hard constraints; tags/checked-out/shallow questions attacked and verified safe with file:line) |
| 3 | completeness | 10 (deny-scan noise laundering the 04:38 trip C; ungated re-arm C; THINK trip undug M; hollow 0-failed M; sweep cross-delete coincidences M; manifest clobber race M; no truth executes group-kill M; audit-only R-2 m; gc-dependent revive m; worktree lifecycle m) | A ×10 (R-9/R-10 added; T-2 raised to store-step-passed; T-3b added; R-4 acceptance mechanized; R-2 registry-fied) |

> Verdict: converged after disposition — all 29 findings landed as spec text; round-3 F1 (deny-scan) and round-1 F1 (fork-bomb) closed gaps the designer's own dig missed.

## Risks

- Enumerated writable set may miss a write point the triage uncovers late → each addition requires its own proof (section-level evidence), and the drift assertion keeps the registry honest.
- Worktree helper adds per-VERIFY clone cost (full checkout — no shallow mechanism exists) → disk preflight fails loud; idempotent prune bounds residue.
- Default-detach changes operator habit → sentinel contract surfaces lock refusals; startup prints the watch command; run logs rotate.
- Dig-closure floor cannot fully close the knowing-omission hole (what the card never says) → structural inversion (zero anchors = refusal) + waiver refusal in marker sessions + stamp ordering bound the reachable surface; the residual is user-challenge territory by design (deepen line stays).
- Deny-scoring narrowed to command-kind weakens the text-signal channel for genuinely malicious script output → the escape detector still scans and reports text hits; they stop failing steps (visibility preserved, lethality removed).
- refs/reaped namespace longevity → objects stay reachable as refs; reap re-run tolerates the namespace (exempt from tier-1).
