# P0 Spec — Full-Auto Mode (auto loop, approval routing, capability depth)

Phase: P0 · Level 3 · Intent: Ship gos auto on/off/status — toggle full-auto
at any stage boundary; per-stage fresh-session auto-loop; persists across
sessions, resume auto-continues; hard gates + D-NN audit stay; guards: push
sign-off, dangerous-cmd gates, retry cap after N exit-1, main-push CI closure
check (every push terminal-green or dispositioned, 91848545 twice-lived);
ends at SHIP.

> Red Team: R1 (misuse, 12) + R2 (edge, 18) + R3 (completeness, 16) — all
> 46 dispositioned in §7 (44 ACCEPT / 2 ACCEPT-PARTIAL, zero unresolved).

## 1. Problem

Supervised GOS needs a human at every stage boundary: each `gos commit
<stage>` waits for the next session, and the session driving it is one long
conversation whose context degrades (6a83e11f — claim-boundary rotation
exists precisely because context bloat corrupts work). The existing
`gos auto on` writes a `tiered` auto_mode that has zero consumers — a stub.
Meanwhile two live incidents demand mechanization: main pushes went red
unnoticed twice (91848545 + 02fa2607) because no flow step triages CI to a
terminal state, and single-session full-flow orchestration has a documented
history of gates being skipped or self-run (c81cbeab, 09ce3e57).

Full-auto must therefore ship the loop AND the guards in one motion:
fresh-session-per-stage spawning, pre-delegated approvals with segregated
evidence, a breaker, kernel-grade capability restriction, and a CI closure
check — ending at SHIP, where the human regains control.

The controlling security fact (RT1-F1): the spawned working session MUST be
able to write `.gos/` (it produces spec/plan and runs `gos commit`), so
nothing the runner trusts may live inside the repo. Machine-local is not
outside-sandbox — the runner's trust state lives in an unmasked-elsewhere
store the sandbox cannot see.

## 2. Decisions (recorded via `gos decision add`)

| ID | Decision |
|:--|:--|
| D-40 | Full-auto = channel-agnostic spawn contract + host adapters; v1 opencode, codex fixture, rest fail-closed |
| D-41 | Auto approvals: mechanical=auto; think/plan delegated with runner-spawned redteam evidence; archive+push always held |
| D-42 | Auto breaker = 3 layers: consecutive N=3, visits K=5, budget B=30; trip pauses (resume reports, explicit re-enable) |
| D-43 | Auto evidence privacy: tracked records hash/count only; session ids, models, tails in untracked .gos/logs ledger |
| D-44 | Delivery = probe-gated adapter (v1 PR+squash); push sign-off + CI closure bind to it; SHIP termination works without it |
| D-45 | Auto runtime machine-local (.gos/auto.json + ledger); auto run exclusive lock; resume reports, never auto-spawns |
| D-46 | Host version policy = capability negotiation: spawn-time probe + version matrix data + fail-closed + semantic predicates |
| D-47 | Danger gates = profile deny + read-union-inject + bwrap launcher (probe-gated) + escape detector; loop never in-host |
| D-48 | Trust state outside sandbox: XDG store masked via tmpfs; breaker/lock/approval-creds verified against it, never .gos/ |

## 2.1 Decision cards (v3 contract: Option | Premise | Pros | Cons | Activates)

### D-40: spawn architecture — who spawns each fresh stage session?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| channel-agnostic contract + adapters (chosen) | opencode run verified headless (rc=0, JSON events, fresh session, --auto, OPENCODE_CONFIG_CONTENT); codex exec JSONL + sandbox matrix verified from source; engine-client split in both ecosystems | architecture open to future hosts with zero speculative code; desktop = another client, no adapter needed | long-lived runner process tied to one terminal (resume recovery); adapter surface must stay at 3 frozen capabilities | adapter registry + spawn-with-profile / outcome-stream / probe-status contract; B/C/D/E/F all hang off it |
| host-side skill self-loop | zero new code | none worth naming | preserves the one-long-conversation mode the intent bans; guards lose their mechanical carrier | nothing — the existing resume paste protocol |
| external watcher (cron/systemd) | unattended machines | survives terminal death | system-level config burden; conflicts with human-at-the-edge (push sign-off) | an unattended-host scenario with no current consumer |

why-not: host-side skill self-loop — it is the exact banned mode and leaves all four guards unmechanized; external watcher (cron/systemd) — no real consumer today, systemd user session degraded on this machine (probe fact).
recommendation: contract + adapters — conditional: v1 ships opencode process channel verified; codex probe-registered fail-closed with fixture tests (selectable only when dogfood-verified — RT1-F8); workbuddy/future hosts and the server channel (opencode serve --attach / codex app-server) probe-registered fail-closed; adapter interface frozen at 3 capabilities.

### D-41: approval routing — what does full-auto mean for user gates?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| 3-class routing with segregated evidence (chosen) | disposition-completeness gate, state.redteam_rounds and resolve-model think-redteam already shipped; only provenance is missing | process-level separation of scrutinizer from scrutinized (fresh session + heterogeneous model + captured stream); audit schema superset of today's bare ts | redteam quality could still be shallow — mitigated by runner-owned spawn, ro-mount, and the double-zero rule | approval record schema {ts, mode, evidence}; two-phase ratification (in-spawn PENDING, runner ratifies from outside); SHIP delegation ledger |
| binary auto except archive+push | simplest mental model | minimal schema | zero scrutiny crossing decision lines; discards the already-shipped disposition gate and heterogeneous dispatch | a mode flag only |
| full-auto restricted to BUILD..VERIFY | no delegation-legitimacy problem | P16 ruling untouched | contradicts intent (any boundary, resume continues, ends at SHIP); resume strands at every decision stage | none |

why-not: binary auto except archive+push — replaces existing scrutiny machinery with nothing, strictly worse; full-auto restricted to BUILD..VERIFY — violates the phase intent text directly.
recommendation: 3-class routing — conditional: ① THINK delegation requires redteam rounds written by the runner from the captured stream of a separately spawned redteam session (resolve-model think-redteam), stamped into the D-48 store (hash creds — the store is unwritable by the sandbox, so the pairing cannot be forged from inside); ② the redteam spawn mounts the workspace read-only and takes its task prompt from a runner-held template, never from repo files (RT1-F5 injection face); ③ delegated THINK additionally requires the double-zero rule: findings=0 from a SECOND independent redteam pass, else held (RT1-F5); ④ any round with findings>0 escalates to held — in auto mode dispositions are never written by the working session (RT1-F7); ⑤ PLAN delegation is purely mechanical (commit-plan gates green); ⑥ archive and push are never delegated; ⑦ VERIFY truths stay mechanical and are listed in the SHIP ledger for human final review; ⑧ ratification is two-phase because the commit gate runs INSIDE the sandbox while the store is invisible there (RT2-C1): in-spawn `gos commit` on a delegated stage performs structural checks only and records a PENDING auto-approval with no evidence claim; the runner, after spawn exit, verifies the captured-stream hashes against the store and writes the ratified {ts, mode, evidence} record itself from outside the sandbox — a PENDING without matching runner ratification blocks the next stage advance.

### D-42: breaker — what stops a runaway loop?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| 3-layer (chosen) | empty-return failure class proven (ae2e474c); stage-back ping-pong resets consecutive-only counters; unattended runs need a cost cap | covers same-wall retry, ping-pong, and runaway cost with one layer each; paused preserves user config | three numbers to document; defaults guessed from this repo's cadence | D-48 store counters; breaker record + resume first-line; runner loop guards |
| single-layer consecutive exit-1 | simplest | one number | blind to rc=0 silent stalls and ping-pong; auto off destroys user config | minimal |
| no breaker | none | zero code | intent lists the retry cap as a P0 guard; unattended cost runaway | none |

why-not: single-layer — provably blind to two real death modes; no breaker — violates the guard list in the intent.
recommendation: 3-layer — conditional: trip action is paused (config kept in the D-48 store, unwritable from inside the sandbox — RT1-F1), never auto-resumed (explicit `gos auto on` re-enables, and auto-family commands refuse under the GOS_AUTO_SPAWNED marker — RT1-F6); defaults 3/5/30 overrideable and visible in status, N/K/B are validated as integers >= 1 with unknown profile names a hard error (RT2-m2); B counts spawned sessions; every spawn carries a wall-clock timeout (default 60 min, >= 2x the worst legitimate stage) and an output-idle timeout (default 10 min, measured from the LAST stream event under the adapter keepalive contract — a live 18-minute silent test suite is not idle because the stream keeps emitting; RT2-M5) whose expiry counts as a failure into the N layer (RT1-F9); rc=0-no-advance counts as failure, where advance = a new stage-labeled commit reachable from current HEAD and absent from the pre-spawn HEAD (recorded as an oid, never a timestamp — RT1-F1d, RT2-m8); failures carry a class tag (task/env/auth/timeout) in breaker records so environment failures do not masquerade as task failures and emit re-probe guidance (RT2-m3); a stream that exits without a terminal success event, or parses as malformed JSON, is a failure — the runner never crashes on stream shape (RT2-m4); every trip writes a breaker record surfaced first-line in resume.

### D-43: evidence privacy — what may enter tracked state?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| hash/count in tracked, detail local (chosen) | state.json is git-tracked (38239056); session ids/models/tails are machine metadata; D-01 machine-local logs precedent | team clones leak nothing; hash is leak-free and strictly stronger than today's bare-ts approvals | debugging a dead loop needs the local store present | tracked approval/closure/breaker record shapes; D-48 store keyed by hash |
| full detail in tracked state | one-stop audit | — | leaks session/model/output content to every cloner | none |
| no auto evidence at all | — | — | approvals degrade below today's honesty | none |

why-not: full detail in tracked state — re-opens the exact machine-metadata leak the user flagged; no auto evidence at all — less auditable than the status quo.
recommendation: hash/count tracked, detail local — conditional: closure ledger may carry run id + terminal status + ts (public CI facts); session/model/content-shaped detail stays in the D-48 store; tracked approval records carry mode + evidence hash whose verification reads the store (hash pairing cannot be satisfied from inside the sandbox).

### D-44: delivery — how does published work reach main?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| probe-gated delivery adapter (chosen) | users span local-only / plain-git / github repos; guards must bind to actions that exist | non-gitHub users carry zero burden (adapter absent → loop ends at SHIP); self-repo dogfood fully active closes 91848545 | adapter interface grows by one family; probe misfires (gh but no CI) need degraded advisory | delivery adapter registry entry; probe (origin + gh auth + CI presence); closure ledger; gos auto disposition command |
| publish hardcoded into loop | assumes GitHub PR flow everywhere | fastest for that one shape | burden on every other user shape; loop core polluted by GitHub semantics | negative |
| publish always outside the loop | current practice | zero polling code | 91848545 stays unmechanized; loop ends before the delivery point | none |

why-not: publish hardcoded into loop — one collaboration shape taxed onto all users; publish always outside the loop — sacrifices the mechanized closure this repo itself needs.
recommendation: adapter — conditional: probe at `gos auto on`, three-state result in auto status; push sign-off + CI closure exist only when active; SHIP termination must work with no delivery adapter (zero-burden hard test); pre-merge subject lint (9f30d213), 45-minute watch timeout enters the human-disposition path with state unknown (never the N layer — a queued green at minute 46 is not bad work; RT2-M6), red runs stop for human `gos auto disposition <run> --reason` only (dispositions live in the D-48 store; the repo ledger mirrors their hashes — RT2-m5); the loop runs on a non-main work branch: `auto run` refuses a main checkout (or creates/joins the phase work branch), aligning with the PR-only ruling, and the adapter pushes exactly that branch (RT3-F7); the adapter treats repo git metadata as untrusted (RT1-F2): remote URL pinned at probe and re-verified before every privileged operation, `.git/config` + the resolved active hooks directory hashed pre-flight (executable non-sample hooks only, core.hooksPath redirects followed — RT2-m6) with drift aborting into the breaker, privileged git runs with `-c core.hooksPath=/dev/null` and resolves the remote from the pinned value only; privileged git also runs env-sanitized with GIT_CONFIG_GLOBAL=/dev/null, GIT_CONFIG_SYSTEM=/dev/null, GIT_TERMINAL_PROMPT=0 and ssh -F none, so worker-poisoned ~/.gitconfig levers (url.insteadOf, credential.helper, core.sshCommand) cannot redirect or credential-capture a privileged push (RT2-M1); PR title/body render from a runner-held structured template with worker-controlled strings quoted as labeled plain-text blocks (RT1-F11); delivery credentials (gh/git/ssh/netrc) are tmpfs-masked inside every spawn profile so held gates cannot be bypassed by direct token use (RT1-F3); probe advisories note fine-grained PAT workflow-scope false-negatives (836a45f).

### D-45: persistence — where does auto state live and who resumes it?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| machine-local runtime + explicit resume (chosen) | state.json is tracked — team clones must not inherit machine behavior; D-01/D-16 machine-local precedents; .lock family exists | zero surprise surface; breaker survives runner death; multi-machine safe | "resume auto-continues" = one command, not zero | D-48 store (mode/profile/N-K-B/counters/breaker/probe results) + local ledger mirror; exclusive run lock; resume auto+breaker section; auto_mode stub migration |
| tracked runtime + resume auto-spawns | maximum continuation | none worth the cost | teammates inherit auto-on; read command becomes long-running writer | negative |
| no persistence | — | — | violates the intent text | none |

why-not: tracked runtime — machine behavior in a shared repo re-offends D-43's principle and breaks the read/write command class contract; no persistence — intent violation.
recommendation: machine-local — conditional: the runtime store lives under `${XDG_DATA_HOME:-$HOME/.local/share}/gos/<repo-id>/` (writability probed at `auto on` with guidance on failure — RT2-m1) and the launcher masks that prefix to a nonexistent tmpfs inside every sandbox (RT1-F1 — counters, breaker, lock, and approval creds are beyond the sandbox's write and read reach); the repo-local `.gos/logs/auto-ledger.ndjson` remains as a debug mirror only, never a trust input; repo-id falls back to a `local:`-prefixed hash of the resolved absolute clone path for remote-less repos (RT2-M9); the run lock record carries {hostname, pid, boot_id, clone_path} — staleness judgments require hostname match, refusal names the owning clone, and NFS-resident stores get an advisory at `auto on` (shared-home double-runner hazard — RT2-M2); the runner heartbeats during spawn waits and CI watch with a threshold above the max watch timeout, `--break-lock` refuses while the recorded pid/hostname is alive, and any takeover is recorded as a breaker-class event (RT2-M3); each loop iteration revalidates task/phase/stage identity and delta origin — mutations caused outside the loop (human stage-back, archive mid-loop, concurrent supervised commit from another terminal) pause with a report instead of counting into N (RT2-M8); second `auto run` instance refuses and points at the live one; resume shows mode + breaker (breaker first-line when tripped); the GOS_AUTO_SPAWNED marker makes `auto on/off/run/disposition` refuse inside spawned sessions (RT1-F6); auto_mode migrates out of the state schema (zero consumers, safe); any future "resume auto-spawns" ships behind an explicit flag, never as default.

### D-46: host evolution — how do adapters survive host updates?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| capability negotiation (chosen) | hosts churn for real: opencode v2 announced, codex renamed --full-auto; version-skew caused a live misdiagnosis (ba3b30f1) | breakage diagnosed at spawn time, not after burning budget; adapter maintenance = data rows; per-machine self-diagnosis | per-host probe scripts and matrix rows are a standing (small) obligation | probe family; adapter matrix data file; auto status --hosts; breaker wiring for drift |
| hard version window | simple rejection | fast | forces host version choices on users; matrix degenerates to one line | none |
| no policy, breaker absorbs | zero cost | — | five-second diagnosis becomes a burned budget; misdiagnosis incubator | none |

why-not: hard version window — coarser than the matrix and stricter on users; no policy, breaker absorbs — repeats the ba3b30f1 failure shape deliberately.
recommendation: capability negotiation — conditional: probe failure text names the matrix entry and the update path; ONLY verified hosts are selectable for real runs — fixture-tested and probe-pending statuses are display-only (RT1-F8); verified status only via real dogfood; v1 starts opencode 1.18.x=verified, opencode 2.x=probe-pending, codex=fixture-tested (not selectable); semantic predicates (>=) only, never identity.

### D-47: danger gates — how are dangerous commands stopped?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| 3-layer depth (chosen) | bwrap + userns + env-passthrough + kernel write-block all probe-verified this session; plugin cannot sandbox its parent (recursion) | lexical bypass no longer equals success; degrade chain honest; plugin/desktop/CLI each in their place | writable-path mapping is a fresh fragility (adapter-declared); network stays open (model API) = no exfiltration protection | templates/auto-profiles (restricted/workspace/full); read-union-inject with the deny baseline held outside the sandbox and ro-bound in (RT1-F4); bwrap launcher + probe chain; escape detector → breaker; hardening tier status |
| lexical layer only | minimal | fastest | kernel-grade explicitly demanded; empty interface slot violates the wiring-list discipline | interface placeholder |
| launcher mandatory | strongest gate | no degrade ambiguity | machines without bwrap lose full-auto entirely; conflicts with the probe-degrade family | none |

why-not: lexical layer only — the kernel launcher was explicitly requested and its interface placeholder is a 68ceb54b-class violation; launcher mandatory — turns an optional hardening into a hard product dependency.
recommendation: 3-layer — conditional: engine chain v1 = bwrap only (landlock helper / systemd-run later), no engine → lexical + detector with honest tier display; the default profile is restricted and upgrades require an explicit flag shown first-line in status (RT1-F12); host state dirs (~/.config/opencode and friends) are NEVER writable-bound into the sandbox — each spawn gets a tmpfs seeded from a runner-held snapshot, so one compromised stage cannot persist config/plugin poisoning into the next "fresh" spawn, and the union-inject deny baseline is computed against the runner-held snapshot, not against files the sandbox may have rewritten between spawns (RT1-F4); delivery-credential paths (gh/git/ssh/netrc) are tmpfs-masked in every profile including full — model-provider auth is the only credential class the sandbox may read (RT1-F3); launcher failure counts into the breaker; honesty lines (network open, model-key readable by design; lexical layer is depth not redundancy) print in help and status; restricted profile may add workspace-ro + tmpfs scratch; loop never runs inside the host process (plugin = control surface, desktop = observer, detach survives app close).

### D-48: where does the runner's trust state live?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| external store, masked from sandbox (chosen) | the working session must write .gos/ (spec/plan/commit), so every in-repo counter, cred, lock, and approval is forgeable from inside; bwrap can make a path nonexistent via tmpfs | the sandbox cannot forge what it cannot see; single verification point for breaker, lock, creds, and staged approvals | two stores to keep coherent (repo state for task truth, external for runner trust); machine-local debugging needs the store present | XDG_DATA_HOME/gos/<repo-id>/ store; tmpfs mask in every launcher profile; commit-gate auto-approval verification reads the store; GOS_AUTO_SPAWNED marker; runner-held snapshots (deny baseline, host seed, PR template) |
| in-repo machine-local (.gos/) | single-tree debugging | — | RT1-F1: all trust inputs inside the sandbox's writable set — breaker, creds, approvals, lock all forgeable | negative |
| OS keychain / DBus secrets | strongest storage | hardware-backed | new dependency surface; unavailable on HPC nodes; overkill for hash/count records | none |

why-not: in-repo machine-local (.gos/) — the controlling security fact makes every in-repo trust input self-satisfiable from inside the sandbox; OS keychain / DBus secrets — dependency and availability cost without addressing the masking requirement, which stays either way.
recommendation: external masked store — conditional: store layout = {store_schema_version, mode, profile, N/K/B, counters, breaker records, approval stamps, probe results, dispositions, snapshots (deny baseline, host seed, redteam prompt, PR template)} keyed by repo-id; the store carries its own schema version with unknown-higher versions failing into an explicit version-mismatch message and migrations co-versioned with the state-schema bump rule (RT2-M7); a MISSING store is treated identically to a corrupt one — paused with guidance, never a silent fresh start (RT2-M4); tracked state carries cumulative spawn-count and trip-count mirrors (D-43-legal counts) so cost history survives store loss and `auto on` warns when recreating over implied prior history; the repo-local ledger stays as a debug mirror; every verification (ratification, lock, counter reads) queries the store, never the mirror; store corruption fails closed (unknown → paused, never run-on); the launcher contract pins mask-over-bind argument ordering (tmpfs masks must win over any later bind of the same path — RT2-m7).

## 3. Requirements

| ID | Requirement |
|:---|:--|
| R-01 | Ship gos auto on/off/status — toggle full-auto at any stage boundary (intent) |
| R-50 | 3-layer breaker: N=3 / K=5 / B=30 (B = spawned sessions, floors >=1), paused semantics, failure-class taxonomy (task/env/auth/timeout), per-spawn wall-clock 60m + idle 10m-from-last-event timeouts, CI-watch timeout routes to disposition-unknown not N |
| R-51 | Machine-local runtime: D-48 external store (${XDG_DATA_HOME:-$HOME/.local/share}/gos/<repo-id>/, local: fallback repo-id) + repo debug mirror; cross-host lock record {hostname,pid,boot_id,clone_path} + heartbeat + break-lock rules; store schema versioning; missing store = paused; resume never auto-spawns; auto_mode stub migrates out |
| R-52 | Host capability negotiation: spawn-time probe, matrix data, fail-closed guidance, semantic predicates; only verified hosts selectable |
| R-53 | Evidence privacy: hashes/counts tracked; session ids, models, tails local; verification reads the D-48 store |
| R-54 | auto surface: on/off/status/run, profile + N/K/B + timeout overrides, default restricted + explicit upgrade, hardening tier, host tri-state, breaker first-line in resume, external-mutation pause reports; `run` requires an active non-SHIP task (error guides to gos init), `on` is config-only; `auto off --purge` removes the store (RT3-F11) |
| R-55 | Fresh-session loop via spawn contract; adapters opencode verified / codex fixture (display-only) / rest fail-closed |
| R-56 | Approval routing: mechanical auto / delegated (think = runner redteam ro-mount + double-zero + two-phase ratification: in-spawn PENDING, runner ratifies from outside; plan = mechanical; findings>0 always held) / held (archive+push); records {ts,mode,evidence} |
| R-57 | Delivery adapter probe-gated PR+squash v1: lint pre-merge, CI watch 45min → disposition-unknown, closure ledger, red=human disposition in store; git metadata untrusted (pinned remote, config/hooks hash, hooksPath=/dev/null, GIT_CONFIG_GLOBAL/SYSTEM=/dev/null env sanitization); PR body runner-rendered |
| R-58 | Capability depth: profiles + read-union-inject (baseline from runner snapshot) + bwrap launcher (tmpfs masks: D-48 store, delivery credentials, host state dirs seeded read-only) + escape detector; loop never in-host |

Decision coverage: D-40→R-55/R-52, D-41→R-56/R-53, D-42→R-50,
D-43→R-53, D-44→R-57, D-45→R-51/R-54, D-46→R-52, D-47→R-58/R-54,
D-48→R-51/R-53/R-56/R-58, intent→R-01.

## 4. Observable Truths

| ID | Truth |
|:--|:--|
| T1 | `gos auto on` then `gos auto run` advances a fixture task across at least one stage boundary using one fresh spawned session per stage; the D-48 store records every spawn (count > 0) |
| T2 | `gos auto status` prints mode, profile, hardening tier (kernel/lexical), host tri-state (verified/fixture/probe-pending), and counters |
| T3 | Ratification boundary (RT2-C1): inside a spawned session, `gos commit` on a delegated stage records a PENDING approval and any PENDING without a matching runner ratification blocks the next stage advance; with store-stamped creds (fixture-captured stream hash) the runner ratifies from outside and the approval record carries mode + evidence hash |
| T4 | Driving the same stage to N consecutive failures trips the breaker: auto enters paused, the resume output shows the breaker first-line and spawns nothing |
| T5 | With the delivery adapter absent the loop ends cleanly at SHIP; with a fixture adapter active, publish runs subject lint before merge, a simulated red CI run stops the loop until a recorded disposition, and a shortened fixture watch timeout lands in disposition-unknown (never N) awaiting human disposition (RT3-F6) |
| T6 | Under the bwrap tier a spawned process cannot write outside declared writable paths AND cannot see the D-48 store or delivery-credential paths (probe assertions); on an engine-less machine status degrades to lexical tier honestly; a fixture host-state poisoning file written in one spawn is absent from the next spawn, which sees the runner-seeded snapshot, and the deny baseline derives from the runner snapshot regardless of sandbox-writable files (RT3-F4) |
| T7 | A fixture state.json contains zero session ids, model names, or output tails (grep assertions); the D-48 store carries them keyed by hash |
| T8 | A host whose probe fails (fixture: broken flag set) refuses `gos auto run` start with a message naming the matrix entry; selecting a fixture-tested (non-verified) host for a real run is refused with display-only guidance (RT3-F5) |
| T9 | Adversarial: a fixture working session that tampers with repo-local counters/ledger/approval records does NOT un-pause, reset, or satisfy any gate — verification reads the masked store and the tamper is surfaced |
| T10 | Adversarial: a fixture `.git/hooks/pre-push` plant, remote rewrite, or `~/.gitconfig` url.insteadOf plant makes the delivery adapter abort into the breaker instead of pushing |
| T11 | Adversarial: `gos auto on` (and off/run/disposition) executed inside a GOS_AUTO_SPAWNED session refuses with guidance |
| T12 | Adversarial: a fixture redteam pass returning findings=0 only once does NOT delegate THINK (double-zero rule); a pass with findings>0 escalates to held; the redteam prompt source hashes to the runner-held template (a fake prompt file in the repo is ignored — RT3-F15); `gos approve archive` executed in auto mode is refused (RT3-F15) |
| T13 | Adversarial/edge: an external mutation mid-loop (human stage-back, archive, or concurrent supervised commit) pauses with a report and never counts into N; a store deleted mid-run yields paused-with-guidance on next touch, with the tracked cumulative counters surviving |
| T14 | Edge: a fixture store at an unknown-higher store_schema_version, a truncated outcome stream, and an N=0 user input each fail into explicit named errors (version mismatch / stream failure / validation), never silent acceptance or runner crash |
| T15 | Breaker layers verified independently (RT3-F2): a fixture ping-pong (advance+regress cycle) trips only K; budget exhaustion trips only B; a fixture broken PATH/auth environment records env/auth failure classes (not task); a micro-overridden timeout expiry counts into N; rc=0 with no new stage-labeled commit since the pre-spawn HEAD records as failure |
| T16 | Lock family (RT3-F3): a live lock record (live pid + matching hostname) refuses --break-lock and records the takeover attempt as a breaker event; a stale cross-host lock is recoverable and the refusal names the owning clone; a concurrent second `auto run` is refused pointing at the live instance |

## 5. Scope (files — PLAN refines)

- bin/lib/ops/auto/ — new module family: loop, spawn contract, breaker,
  external store (D-48: schema version, locks {hostname,pid,boot_id,
  clone_path}, heartbeat, snapshots), launcher (bwrap composer + engine
  probe chain + tmpfs masks with mask-over-bind ordering), escape
  detector, env-sanitized privileged-git runner, keepalive contract
- bin/lib/ops/auto/adapters/ — opencode.cjs (verified), codex.cjs
  (fixture, display-only), registry.cjs + version matrix data
- templates/auto-profiles/ — restricted / workspace / full profile data
  (restricted default; masks: D-48 store, delivery credentials, host state
  dirs, global git config)
- bin/lib/nav/cmds.cjs — cmdAuto rewrite (on/off/status/run subcommands,
  flags for profile + N/K/B, GOS_AUTO_SPAWNED refusal), resume
  auto+breaker section
- bin/lib/task/commit.cjs — delegated-stage PENDING approval records
  (structural checks in-spawn; evidence never claimed in-spawn — RT2-C1)
- bin/lib/core/state.cjs — approvals record shape ({ts, mode, evidence,
  pending}), cumulative spawn/trip count mirrors, auto_mode stub removal +
  STATE_SCHEMA_VERSION bump with same-commit grep of every
  version-constant consumer INCLUDING STORE_SCHEMA_VERSION (0d2eedee,
  RT3-F13)
- bin/lib/task/archive.cjs — SHIP delegation ledger surface (rtFindings
  precedent)
- .gitignore — repo debug mirror entries
- help/CONTRACTS/locale lines for every new command and failure (68ceb54b
  wiring list: route table row, CLI hard gate, template, executor
  awareness)
- CHANGELOG.md — user-visible entry
- test/sections/T?? — new section(s); PLAN checks existing numbering
  (855aa993) and lands fixtures for T1..T16 (positive + adversarial +
  edge); the registry carries a `test-verified` deterministic fake-host
  row selectable only under test-env pins so T1 runs in CI/--fresh while
  real opencode dogfood lands as manual tracked evidence (RT3-F8);
  sections pin XDG_DATA_HOME into TESTBASE, micro-override all timeouts,
  trap-kill spawned processes in teardown, and stay strictly sequential
  (RT3-F14/F16, 63675448); truth evidence artifacts are tracked fixture
  transcripts, never store paths (e34eaeb8)
- census + layout guards: census.json entries for new tracked dirs
  (templates/auto-profiles/, adapters matrix), test/pack-check.sh +
  test/checks/cjk-lint.sh + i18n inventory (every new failure string
  en+zh) run before layout lands (RT3-F9)
- docs + wiring (RT3-F10): README.md + README.zh-CN.md auto sections;
  gos-router skill auto routing row; gos-verify skill breaker/ledger
  reading; help --json CONTRACTS rows for every new subcommand; registry
  write-class audit (auto family in WRITE_CMDS; read-only status
  exemption decided at PLAN)

Out of scope: gate content sniffing beyond structural floors; opencode v2
adapter (probe-pending until dogfood); landlock/systemd-run engines; solo
direct-push delivery variant; gos.js plugin control surface; server-channel
spawn (--attach); remote/cloud loop triggers; per-spawn token cost hard cap
(advisory count only — DI).

## 6. Deferred Ideas

- DI-1: landlock helper and systemd-run launcher engines (when a machine
  lacks bwrap but has them)
- DI-2: solo direct-push delivery variant (same adapter interface)
- DI-3: gos.js plugin control surface (/gos slash commands bridging the CLI)
- DI-4: opencode v2 adapter (matrix row exists; verify by dogfood)
- DI-5: server-channel spawn adapter (opencode serve --attach, codex
  app-server)
- DI-6: watcher as a second runner trigger source (unattended machines)
- DI-7: per-spawn token/cost hard cap (advisory counts ship first)

## 7. Red Team

### Round 1 (MISUSE) — dispositioned 2026-10-29

| ID | Finding | Disposition |
|:--|:--|:---|
| RT1-F1 | all runner trust state inside sandbox-writable set (counters/creds/lock/approvals forgeable) | ACCEPT — D-48 external masked store; gate/lock/counter verification reads it; advance = stage delta + stage-labeled commit |
| RT1-F2 | privileged runner actions inherit worker-writable git metadata (pre-push hook, remote rewrite, credential.helper) | ACCEPT — adapter treats git metadata untrusted: pinned remote, config+hooks hash pre-flight, core.hooksPath=/dev/null |
| RT1-F3 | credentials readable + network open bypass every held gate via direct token use | ACCEPT — delivery-credential tmpfs masks in all profiles incl. full; model-provider auth the only readable class; honesty line updated |
| RT1-F4 | host state dirs persist poisoning across "fresh" spawns; union input rewritable | ACCEPT — host dirs tmpfs + runner-held seed; deny baseline computed from runner snapshot, ro-bound in |
| RT1-F5 | redteam session consumes attacker content, findings=0 passes clean | ACCEPT-PARTIAL — ro-mount + runner-held prompt (ACCEPT); second-pass requirement folded into double-zero rule (T12) |
| RT1-F6 | gos auto on self-runnable by spawned session (09ce3e57 shape) | ACCEPT — GOS_AUTO_SPAWNED marker refusal + store outside sandbox |
| RT1-F7 | dispositions worker-self-written in auto ("never auto-dispositioned" = text) | ACCEPT — findings>0 always held in auto; runner stamps rounds into the store |
| RT1-F8 | codex fixture selectable while opencode v2 fail-closed — inconsistent | ACCEPT — only verified hosts selectable; fixture/probe-pending display-only |
| RT1-F9 | no spawn timeout; B unit undefined — hung spawn wedges breaker | ACCEPT — per-spawn wall-clock + idle timeout into N layer; B = spawned sessions |
| RT1-F10 | truths all positive-path, zero adversarial | ACCEPT — T9..T12 added |
| RT1-F11 | PR body assembled from worker content misleads the human gate | ACCEPT — runner-rendered template, worker strings as labeled quoted blocks |
| RT1-F12 | default profile unspecified | ACCEPT — restricted default, explicit upgrade, status first-line |

### Round 2 (EDGE) — dispositioned 2026-10-29

| ID | Finding | Disposition |
|:--|:--|:---|
| RT2-C1 | commit gate runs inside the sandbox but the store is invisible there — T3/T6 unsatisfiable as written | ACCEPT — two-phase ratification: in-spawn PENDING, runner ratifies from outside; PENDING without ratification blocks advance; T3 rewritten |
| RT2-M1 | worker-poisoned global git config (insteadOf/credential.helper/core.sshCommand) bypasses pinned remote | ACCEPT — GIT_CONFIG_GLOBAL/SYSTEM=/dev/null + GIT_TERMINAL_PROMPT=0 + ssh -F none on privileged git; global git config masked in all profiles; T10 extended |
| RT2-M2 | NFS-shared home: repo-id collision, cross-machine lock liveness wrong (pidAlive false stale/live) | ACCEPT — lock record {hostname,pid,boot_id,clone_path}; hostname-matched staleness; refusal names clone; NFS advisory at auto on |
| RT2-M3 | orphaned run lock / heartbeat vs 45-min quiet phases invites break-lock on a live runner | ACCEPT — heartbeat during spawn-wait and CI-watch, threshold > max watch, break-lock refused while pid/hostname alive, takeover recorded as breaker-class event |
| RT2-M4 | missing store ≠ corrupted; deleting store silently resets budget/breaker | ACCEPT — missing = paused with guidance; tracked cumulative spawn/trip mirrors; auto on warns over implied history |
| RT2-M5 | per-spawn timeout defaults absent; legit 18-min silent suite would trip naive idle | ACCEPT — wall-clock default 60m; idle 10m from last stream event under keepalive contract; timeout flags in R-54 |
| RT2-M6 | CI-watch timeout counted as failure mislabels slow-green as red | ACCEPT — timeout routes to human disposition with state unknown, never the N layer |
| RT2-M7 | D-48 store has no schema version — upgrades/downgrades false-corrupt | ACCEPT — store_schema_version, unknown-higher = explicit mismatch, migrations co-versioned |
| RT2-M8 | external mutations (human stage-back, archive, concurrent commit) misread as task failures | ACCEPT — per-iteration identity/delta revalidation; external mutation → pause-with-report, never N |
| RT2-M9 | remote-less repos have no repo-id yet are in scope | ACCEPT — local: absolute-path-hash fallback namespace, documented |
| RT2-m1 | XDG_DATA_HOME unset/non-writable undefined | ACCEPT — ${XDG_DATA_HOME:-$HOME/.local/share} + writability probe at auto on |
| RT2-m2 | N/K/B=0/negative; unknown profile silent fallback | ACCEPT — integer floors >=1; unknown profile hard error |
| RT2-m3 | env-class failures pollute breaker diagnosis | ACCEPT — failure-class taxonomy (task/env/auth/timeout) in breaker records + re-probe guidance |
| RT2-m4 | truncated/malformed outcome stream undefined; runner parse crash orphans lock | ACCEPT — no terminal event or malformed JSON = failure, never crash |
| RT2-m5 | disposition record location unspecified (forgeable if tracked) | ACCEPT — dispositions live in the D-48 store; ledger mirrors hashes |
| RT2-m6 | hooks hash vacuous under core.hooksPath redirects; *.sample churn false drift | ACCEPT — resolve active hooksPath, hash executable non-sample hooks only |
| RT2-m7 | odd paths (spaces/unicode/symlink roots) and bwrap mask/bind ordering unpinned | ACCEPT — odd-path fixtures + mask-over-bind ordering rule in launcher contract |
| RT2-m8 | timestamp-based advance attribution skew-prone (GIT_COMMITTER_DATE/NTP) | ACCEPT — pre-spawn HEAD oid + commit reachability + monotonic elapsed |

### Round 3 (COMPLETENESS) — dispositioned 2026-10-29

| ID | Finding | Disposition |
|:--|:--|:---|
| RT3-F1 | §5 still promised T1..T12 fixtures after truths grew | ACCEPT — scope rewritten to T1..T16 with explicit edge fixtures |
| RT3-F2 | only the N layer of the breaker had a truth (K/B/class/timeout/no-advance unverified) | ACCEPT — T15 added |
| RT3-F3 | lock family (hostname staleness, break-lock refusal, second instance) unverified | ACCEPT — T16 added |
| RT3-F4 | host-state poisoning isolation had no adversarial truth | ACCEPT — T6 extended |
| RT3-F5 | verified-only host selectability unverified (RT1-F8 was verbal) | ACCEPT — T8 extended |
| RT3-F6 | CI-watch disposition-unknown path unverified | ACCEPT — T5 extended |
| RT3-F7 | loop branch discipline undefined — auto on a main checkout violates the PR-only ruling | ACCEPT — auto run refuses main checkout / creates phase work branch; adapter pushes exactly that branch |
| RT3-F8 | T1 untestable in CI (real host + auth + network) | ACCEPT — test-verified deterministic fake host under test-env pins; real dogfood as manual tracked evidence |
| RT3-F9 | census/pack-check/cjk-lint/i18n absent from scope | ACCEPT — census entries + pack-check + cjk-lint + en/zh inventory added |
| RT3-F10 | README/skills/help wiring absent despite invoking 68ceb54b | ACCEPT — README (en+zh) auto sections, router row, verify reading, CONTRACTS rows, write-class audit |
| RT3-F11 | D-48 store lifecycle has no exit (orphans on clone move/teardown) | ACCEPT — `auto off --purge` + doctor advisory |
| RT3-F12 | auto preconditions undefined (no task / DONE / Lv0) | ACCEPT — run requires active non-SHIP task; on is config-only; error guides to init |
| RT3-F13 | STORE_SCHEMA_VERSION outside the 0d2eedee grep scope | ACCEPT — grep scope extended |
| RT3-F14 | store-based evidence vs tracked-artifact truth rule (--fresh dies) | ACCEPT — TESTBASE-pinned XDG_DATA_HOME in sections; truths cite tracked fixture transcripts |
| RT3-F15 | D-41 scattered unverifiables (prompt source, PR quoting, archive refusal, SHIP ledger) | ACCEPT — T12/T5 extended |
| RT3-F16 | fixture durations would blow the 18-min suite; section runner hygiene | ACCEPT — micro timeouts, teardown traps, sequential sections |

Verified clean this round: no SLINK in R2 spot-checks; lessons honored
(e1f51ac2, 9f30d213, 0d2eedee, f6a4a9ff, 8c4c23fe, 782629a7, 855aa993);
836a45f folded as a probe advisory.

Convergence: three mandatory rounds complete; all 46 findings
(12+18+16) dispositioned — 44 ACCEPT / 2 ACCEPT-PARTIAL, zero unresolved.
Escalation rule never fired (no FORCED-ACCEPT chain).
