# Plan: P0 full-auto mode

> **Date**: 2026-10-29 | **Based on spec**: .gos/task/p0/spec.md
> Plan-attack (RT4): 13 findings folded — per-task module ownership (no
> shared section files), honest wave deps, commit protocol, store record
> API, node-assert venue, CI bwrap, per-task locales, god-task splits.

## Decision Inventory

- [x] D-40: spawn contract + host adapters → T2, T5
- [x] D-41: approval routing 3 classes + two-phase ratification → T6a, T6b
- [x] D-42: 3-layer breaker → T4, T5
- [x] D-43: evidence privacy (hash/count tracked, detail local) → T4, T6a, T7b
- [x] D-44: probe-gated delivery adapter → T7a, T7b
- [x] D-45: machine-local runtime + explicit resume → T1, T5, T8
- [x] D-46: host capability negotiation → T2
- [x] D-47: capability depth (profiles + launcher + detector) → T3
- [x] D-48: external trust store masked from sandbox → T1, T3

## Requirement Claims

- [x] R-01: auto on/off/status → T8
- [x] R-50: breaker → T4
- [x] R-51: runtime persistence → T1, T8
- [x] R-52: capability negotiation → T2
- [x] R-53: evidence privacy → T6a, T7b
- [x] R-54: auto surface → T8
- [x] R-55: fresh-session loop → T2, T5
- [x] R-56: approval routing → T6a, T6b
- [x] R-57: delivery adapter → T7a, T7b
- [x] R-58: capability depth → T3

## Aggregation & Commit Protocol (RT4-F3, mechanized lessons)

- Executors NEVER run `gos commit` and never `git commit` — waves are
  aggregated and committed by the main session only, staging exactly the
  declared Files of the tasks in that wave (be49bdd4, 4446cf98).
- Executors run at most their own filtered verification (`node -e`
  asserts from done-whens); full section suites run only from the main
  session, strictly sequential (f44c8122, 63675448).
- Section fixtures live ONLY in T10 — no other task touches
  test/sections/ (RT4-F1 single-owner rule).

## Pre-decided no-ops (RT4-F11, recorded to close VERIFY liability)

- `auto status` stays inside the write-class `auto` family (registry
  WRITE_CMDS default): it performs no writes; no read-class split shipped.
- `.gitignore`: `.gos/logs/` is already ignored wholesale — the debug
  mirror needs no new entries (verified no-op).
- census: `bin/` and `templates/` prefix inheritance covers every new
  file (incl. registry.json and profiles) — T9 runs pack-check as
  verification, adds no census rows.

## Interface pins (RT4-F4/F12)

- Store record shapes (T1 owns the API, all consumers import it):
  stampStream(spawnId, stage, streamSha256, spawnedAtIso);
  dispositions: {runId, ts, reason, by}; snapshots: {denyBaseline,
  hostSeed, redteamPrompt, prTemplate} each stored as content+sha256;
  probeResults: {host, state, checkedAtIso}.
- Stamp write timing: the loop writes the stamp at spawn exit, before
  ratification reads it (T5 writer, T6a reader).
- Timeout overrides: env `GOS_AUTO_TIMEOUT_WALL_SEC` /
  `GOS_AUTO_TIMEOUT_IDLE_SEC` (seconds) — read by the loop (T4/T5),
  settable via T8 flags, referenced by T10 fixtures.

## Patterns to Follow

- Module families: bin/lib/ops/<family>/ (spawnSync/env patterns:
  bin/lib/ops/section.cjs; adversarial pre-flight + stderr-only failure
  classification: bin/lib/core/gitprobe.cjs)
- Failure strings: every task that emits user-visible failures adds its
  en+zh locale keys in its own Files (68ceb54b; T2-T7 included below)
- Version constants: semantic predicates (>=), same-commit grep of every
  consumer when bumping (STATE_SCHEMA_VERSION precedent)
- No *.test.cjs files exist in this repo — asserts run via `node -e`
  (done-whens) and inside T10 sections (RT4-F5)

## Execution Waves

### Wave 1 (parallel, no deps)

#### T1: External trust store + full record API + lock family (D-48, D-45)
- **Covers**: D-48, D-45, R-51
- **Files**: bin/lib/ops/auto/store.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: bin/lib/core/lock.cjs (pidAlive, dead-pid recovery), bin/lib/core/state.cjs (repo-id derivation, validateState)
- **Approach**: store at ${XDG_DATA_HOME:-$HOME/.local/share}/gos/<repo-id>/ with store_schema_version + the full record API pinned above (stamps, dispositions, snapshots, probe results, counters, breaker records); missing OR corrupt OR unknown-higher version → paused-with-guidance object, never silent fresh start; tracked cumulative spawn/trip count mirrors returned; lock record {hostname,pid,boot_id,clone_path} with hostname-matched staleness, --break-lock refused while pid+hostname live (takeover recorded breaker-class), local: repo-id fallback, writability probe helper.
- **Done when**: `grep -c "store_schema_version" bin/lib/ops/auto/store.cjs` >= 1 AND `node -e "const s=require('./bin/lib/ops/auto/store.cjs'); if(!s.stampStream||!s.recordDisposition||!s.saveSnapshot||!s.saveProbeResult) process.exit(1)"` exits 0 AND corrupt-input helper returns paused state AND locale keys for store failures exist in en+zh
- **Depends on**: none

#### T2: Host adapter registry + capability negotiation (D-40, D-46)
- **Covers**: D-40, D-46, R-52, R-55
- **Files**: bin/lib/ops/auto/adapters/registry.cjs, bin/lib/ops/auto/adapters/opencode.cjs, bin/lib/ops/auto/adapters/codex.cjs, bin/lib/ops/auto/adapters/registry.json, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: bin/lib/ops/setup.cjs (host detection), bin/lib/core/gitprobe.cjs (probe classification)
- **Approach**: registry.json rows {host, version_range, status: verified|fixture-tested|probe-pending, selectable}; probe = version + help-flags + config resolve with semantic predicates; probe failure message names the matrix entry; opencode adapter spawns `opencode run --format json` (fresh session each call), parses terminal events, no-terminal-event/malformed JSON = failure never crash, any streamed event refreshes the idle clock; codex adapter against recorded fixtures (display-only); test-verified fake host row active only under GOS_AUTO_TEST_FIXTURE.
- **Done when**: `grep -c "selectable" bin/lib/ops/auto/adapters/registry.cjs` >= 1 AND `node -e "const r=require('./bin/lib/ops/auto/adapters/registry.cjs'); if(r.hostStatus('codex').selectable) process.exit(1)"` exits 0 AND fake-host gating assert via node -e with/without GOS_AUTO_TEST_FIXTURE AND probe-failure locale keys exist en+zh
- **Depends on**: none

#### T3: Capability profiles + kernel launcher + escape detector (D-47, D-48)
- **Covers**: D-47, D-48, R-58
- **Files**: bin/lib/ops/auto/launcher.cjs, templates/auto-profiles/restricted.json, templates/auto-profiles/workspace.json, templates/auto-profiles/full.json, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: bin/lib/ops/config.cjs (debug-config read), AGENTS.md census rules
- **Approach**: profile JSON {deny, writable (adapter-supplied), masks[]}; masks always include store prefix, delivery credentials (gh/git/ssh/netrc), global git config, host state dirs (seeded tmpfs from runner snapshots via T1 API); bwrap composer with mask-over-bind ordering; engine probe chain bwrap→none with tier result; read-union-inject (resolved permission read, one-way deny union, OPENCODE_CONFIG_CONTENT inject); restricted default, full needs explicit flag; escape detector scans captured streams for deny hits; snapshots loaded/stored via T1 API.
- **Done when**: three profile files exist AND `node -e "const l=require('./bin/lib/ops/auto/launcher.cjs'); const args=l.compose('restricted',{}); if(!l.maskOverBindHolds(args)) process.exit(1)"` exits 0 AND union assert: injecting over a stricter user deny never removes it AND tier degrades to lexical when bwrap missing AND locale keys en+zh
- **Depends on**: none (uses T1 API signature only — imports land functionally at wave aggregation)

### Wave 2

#### T4: Breaker + failure taxonomy (D-42, D-43)
- **Covers**: D-42, D-43, R-50
- **Files**: bin/lib/ops/auto/breaker.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: bin/lib/ops/auto/store.cjs (T1), spec D-42 all conditions
- **Approach**: N=3 consecutive per stage (classes task/env/auth/timeout count), K=5 visits per stage (ping-pong), B=30 spawned sessions; floors >=1 validation; trip = paused record {layer, stage, class, reason, ts} persisted via store + tracked count mirrors; advance detection = new stage-labeled commit reachable from current HEAD absent the pre-spawn HEAD oid; GOS_AUTO_TIMEOUT_WALL_SEC/_IDLE_SEC honored; CI-watch timeout excluded from N.
- **Done when**: `node -e` asserts trip layers independently (ping-pong trips only K; budget only B; consecutive only N) AND `grep -c "GOS_AUTO_TIMEOUT_WALL_SEC" bin/lib/ops/auto/breaker.cjs` >= 1 AND trip records carry class tags AND locale keys en+zh
- **Depends on**: T1

### Wave 3

#### T5: Loop runner (D-40, D-42, D-45)
- **Covers**: D-40, D-42, D-45, R-55
- **Files**: bin/lib/ops/auto/loop.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: T2 adapter interface, T3 launcher interface, T4 breaker, bin/lib/task/commit.cjs stage semantics
- **Approach**: refuses main checkout (creates/joins phase work branch); requires active non-SHIP task (guidance to gos init); per iteration: revalidate task/phase/stage identity + delta origin (external mutation → pause report, never N); spawn fresh session via adapter with launcher profile; stamp stream at spawn exit (T1 API); heartbeat during spawn-wait; GOS_AUTO_SPAWNED marker in spawned env; second instance refused via store lock; clean SHIP termination without any delivery adapter; --detach mode.
- **Done when**: `node -e` asserts: main-checkout refusal branch; external-stage-back returns pauseReport not failure; marker set in spawn env template AND `grep -c "stampStream" bin/lib/ops/auto/loop.cjs` >= 1 AND locale keys en+zh
- **Depends on**: T1, T2, T3, T4

### Wave 4 (parallel — disjoint files)

#### T6a: Ratification boundary — PENDING + approvals schema (D-41, D-43)
- **Covers**: D-41, D-43, R-56, R-53
- **Files**: bin/lib/ops/auto/ratify.cjs, bin/lib/task/commit.cjs, bin/lib/core/state.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: bin/lib/task/commit.cjs:296-330 (approval gates), T1 store API
- **Approach**: delegated-stage in-spawn commit records PENDING {ts, mode:auto, stage} with no evidence; ratify.cjs (runner-side) verifies stamps+stream hashes and writes ratified {ts, mode, evidence}; PENDING without ratification blocks next advance (commit gate branch); approvals become objects (today: bare ts strings, state.cjs:877 — backward-compatible read for legacy string values); tracked records carry hash/count only.
- **Done when**: `node -e` asserts PENDING blocks and ratify unblocks via the exported functions AND `grep -c "PENDING" bin/lib/task/commit.cjs` >= 1 AND legacy string approvals still pass the existing gate AND locale keys en+zh
- **Depends on**: T1, T5

#### T6b: Red-team orchestration + SHIP ledger (D-41)
- **Covers**: D-41, R-56
- **Files**: bin/lib/ops/auto/redteam.cjs, bin/lib/task/archive.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: T5 loop spawn interface, skills/gos-think/reference/red-team.md, spec D-41 conditions ②③④
- **Approach**: separate redteam spawn with workspace ro-mount + runner-held prompt template (source hash recorded); double-zero rule (second independent pass before delegation); findings>0 → held always; rounds stamped via T1 API; SHIP ledger in archive surface lists delegated approvals + VERIFY truths + rt findings counts.
- **Done when**: `node -e` asserts: single findings=0 does not clear delegation gate; findings>0 forces held; prompt source hash equals runner template hash AND `grep -c "ledger\|delegat" bin/lib/task/archive.cjs` >= 1 AND locale keys en+zh
- **Depends on**: T1, T5

### Wave 5

#### T7a: Delivery probe + sanitized privileged git + drift (D-44)
- **Covers**: D-44, R-57
- **Files**: bin/lib/ops/auto/delivery.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: bin/lib/ops/push.cjs, test/checks/push-lint-squash.sh, spec D-44
- **Approach**: probe (origin + gh auth + CI presence, fine-grained PAT advisory) three-state persisted via T1 probeResults; pinned remote re-verified before every privileged op; .git/config + resolved active hooks dir hashed (executable non-sample only); privileged git env-sanitized (GIT_CONFIG_GLOBAL=/dev/null, GIT_CONFIG_SYSTEM=/dev/null, GIT_TERMINAL_PROMPT=0, ssh -F none, -c core.hooksPath=/dev/null); drift aborts into breaker.
- **Done when**: `grep -c "GIT_CONFIG_GLOBAL" bin/lib/ops/auto/delivery.cjs` >= 1 AND `node -e` asserts drift detection on a fixture hooks-plant AND probe three-state helper returns advisory on gh-without-CI AND locale keys en+zh
- **Depends on**: T1, T5

### Wave 6

#### T7b: Publish leg + CI watch + dispositions + purge (D-44, D-43)
- **Covers**: D-44, D-43, R-57, R-53
- **Files**: bin/lib/ops/auto/delivery-publish.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: T7a probe interface, test/checks/push-lint-squash.sh usage
- **Approach**: branch push (the T5 work branch) → PR (runner-held template, worker strings quoted labeled blocks) → subject lint (push-lint-squash --subject) → squash merge → CI watch 45m (timeout → disposition-unknown) → terminal-green closure record (run id + status + ts tracked; detail local via T1 dispositions); `gos auto disposition <run> --reason` writes store + ledger hash mirror; `auto off --purge`.
- **Done when**: `node -e` asserts: watch timeout yields disposition-unknown (never an N increment); red run requires disposition before continue AND `grep -c "disposition-unknown\|dispositionUnknown" bin/lib/ops/auto/delivery.cjs` >= 1 AND PR render wraps worker strings in quoted blocks AND locale keys en+zh
- **Depends on**: T7a, T6a

### Wave 7

#### T8: CLI surface + state schema + resume (D-45, R-01, R-54)
- **Covers**: D-45, R-01, R-51, R-54
- **Files**: bin/lib/nav/cmds.cjs, bin/gos.cjs, bin/lib/core/state.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: bin/lib/nav/cmds.cjs:146-161 (stub), STATE_SCHEMA_VERSION consumer grep (0d2eedee)
- **Approach**: auto on [--profile --max-retries --max-visits --max-sessions --timeout-wall --timeout-idle] / off [--purge] / status / run [--detach]; on validates floors, probes host/delivery/launcher/store-writability with three-state advisories; status prints mode/profile/tier/host-matrix/counters/breaker; resume shows auto + breaker first-line; auto_mode stub removed, schema bumped with same-commit consumer grep (STATE + STORE).
- **Done when**: `node bin/gos.cjs auto status` prints tier + tri-state + counters AND `node bin/gos.cjs help --json` lists all auto subs AND `grep -rn "auto_mode" bin/lib/core/state.cjs | wc -l` = 0 AND locale parity green for every new key
- **Depends on**: T1, T2, T3, T4, T5, T7a, T7b

### Wave 8 (parallel — disjoint files)

#### T9: Docs + pack verification (RT3-F9/F10)
- **Covers**: D-40, D-44, D-45 (wiring halves)
- **Files**: README.md, README.zh-CN.md, CHANGELOG.md, skills/gos-router/SKILL.md, skills/gos-verify/SKILL.md
- **Read first**: AGENTS.md census rules, test/pack-check.sh
- **Approach**: README auto sections (en+zh) with honesty lines (network open, lexical depth, credential masking); CHANGELOG entry; router auto row; verify breaker/ledger reading; pack-check + cjk-lint as verification (no census rows — see no-ops).
- **Done when**: `bash test/pack-check.sh` exit 0 AND `bash test/checks/cjk-lint.sh` exit 0 AND both READMEs contain the auto section heading
- **Depends on**: T8

#### T10: Section fixtures T1..T16 + CI bwrap + dogfood evidence (all)
- **Covers**: D-41, D-42, D-44, D-47, D-48 (adversarial halves)
- **Files**: test/sections/T104-auto-core.test.sh, test/sections/T105-auto-depth.test.sh, .github/workflows/ci.yml, .gos/task/p0/evidence/t1-dogfood.md
- **Read first**: test/sections/ harness + run-sections contract, spec §4
- **Approach**: single owner of both sections; map every truth T1..T16 to a fixture (mapping table in spec §4 of this plan); XDG_DATA_HOME pinned into TESTBASE; GOS_AUTO_TIMEOUT_*_SEC micro-overridden; trap-kill spawned processes; sequential runs; fake host carries determinism; real opencode dogfood transcript as tracked manual evidence; ci.yml sections job installs bubblewrap so T6-tier asserts stay live in CI (RT4-F6).
- **Done when**: every truth id T1..T16 appears in an assertion comment across T104/T105 AND both sections pass rc=0 via run-sections AND `grep -c "bubblewrap" .github/workflows/ci.yml` >= 1 AND evidence/t1-dogfood.md exists
- **Depends on**: T5, T6a, T6b, T7a, T7b, T8

## Observable Truths

Spec §4 T1..T16 is the truth set; verification mapping (T12 semantics
ruled at PLAN: archive-approval refusal is enforced via the
GOS_AUTO_SPAWNED marker — humans outside spawned envs remain legitimate
approvers; T10 asserts the ruled semantics):

- T1 (loop advances, spawns recorded) → T104 fixture on fake host + evidence/t1-dogfood.md
- T2 (status surface) → T104: `gos auto status` output assertions
- T3 (PENDING/ratification) → T104 routing fixtures
- T4 (breaker trips → paused, resume reports) → T104
- T5 (delivery absent ends at SHIP — fake host present as SPAWN adapter, delivery adapter absent; red/unknown disposition) → T104 + T105
- T6 (bwrap masks + poisoning isolation + degrade) → T105 (CI installs bubblewrap)
- T7 (tracked privacy grep) → T105
- T8 (probe fail-closed + non-verified refusal) → T104
- T9 (tamper does not satisfy gates) → T105
- T10 (hook/remote/insteadOf plants abort) → T105
- T11 (marker refuses auto family) → T104
- T12 (double-zero, findings held, prompt source hash, archive refusal per marker ruling) → T104
- T13 (external mutation pause; store deletion survival) → T104
- T14 (version/stream/validation named errors) → T104
- T15 (K/B/class/timeout/no-advance independently) → T104
- T16 (lock family) → T104

## Risks

- opencode stream format drift → probe + version matrix catch at spawn (T2)
- Suite duration: fixtures micro-override all timeouts; sections sequential (T10)
- State schema bump ripple → same-commit grep of STATE_SCHEMA_VERSION +
  STORE_SCHEMA_VERSION consumers (T8, lesson 0d2eedee)
- ci.yml gains an apt dependency (bubblewrap) → cached-runner weight is
  one apt package; fallback if apt flaky: env-gated half + manual evidence
