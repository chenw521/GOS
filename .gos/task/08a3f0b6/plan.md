# Plan: honor .gos/map-ignore at the scan layer (chenw521/GOS#64)

> **Date**: 2026-11-17 | **Based on spec**: .gos/task/08a3f0b6/spec.md
> **Branch**: fix/64-map-ignore-scan-sources (already checked out)
> **Red Team round 4 (plan-attack)**: 12 findings — 11 ACCEPT + 1 ACCEPT-PARTIAL, all folded in below; disposition table at the end.

## Decision Inventory

- [x] D-01: scanSources filters by loadMapIgnore at collection; ignored paths enter no universe → T1, T8
- [x] D-02: gate advisory attributes missing fns via peak.owners x map-ignore; full coverage guides baseline reset → T5, T9
- [x] D-03: scan materializes map-ignored.txt; scripts grep -vxFf → T2, T3, T8
- [x] D-04: fix hints name map-ignore; scan prints excluded count; README en+zh glob-semantics section → T2, T4, T6, T10

## Requirement Claims

- [x] R-01: scanSources applies loadMapIgnore; ignored paths absent from deps.json files/edges/semantic; empty/absent list = today's behavior → T1, T8, T10
- [x] R-02: scan rematerializes .gos/codebase/map-ignored.txt every run (provenance header, sorted, census entry, deleted at 0 exclusions, dead-rule advisory) → T2, T8
- [x] R-03: cleanup-scan.sh and security.sh filter FILES via grep -vxFf with a pinned exit-code contract; missing/unreadable list = full scan → T3, T8
- [x] R-04: gate C4 advisory attributes missing fns via peak.owners x exclusion; full coverage guides baseline reset; partial annotates "N of M" → T5, T9
- [x] R-05: gate fix hints name map-ignore; scan excluded-count line; README en+zh glob-semantics section → T2, T4, T6, T10
- [x] R-06: no-map-ignore repos byte-identical (additive keys omitted when empty); self-repo structural gates green; pack-check green with new census entry → T1, T10

## Patterns to Follow

- Sandbox test pattern: `t30_setup` … `git init -q .` … asserts via `assert_exit` / `assert_contains` (test/sections/T30-map-edges.test.sh:158-193)
- Provenance header format: `generated-at: <ISO> @ <HEAD[0:8]|unborn>` — null-safe head merge exactly like gate.cjs:1131 (`h ? h.slice(0,8) : 'unborn'`)
- Glob semantics single point: `core.globMatch` (core/fsio.cjs:185) — same call shape as semanticUniverse (engine.cjs:207): `ig.has(p) || [...ig].some((g) => g.includes('*') && core.globMatch(g, p))`
- Census regenerable artifact: `.gos/codebase/unmapped-fns.txt` entry shape (census.json, git:false npm:false; `.gitignore` `.gos/codebase/*` already covers the new sibling — no .gitignore edit)
- CONTRACTS i18n: key added in bin/lib/core/state.cjs `semantic_checks` (en) AND bin/lib/core/locales/zh.cjs (zh) — placeholder form, tests assert placeholders
- Gate surface discipline: stateless sandboxes assert via `gate codemap` / `gate all --audit` (structural-only legs, gate.cjs:905-911); plain `gate all` needs task state and is a VERIFY-stage duty
- Approve-gated flows under dispatch: `env -u GOS_AUTO_SPAWNED node "$GOS" approve …` — humanGateGuard (state.cjs:1492-1497) exits 1 in runner-spawned sessions

## Execution Waves

### Wave 1 (parallel, no deps — file-disjoint: T1 engine.cjs+T30 / T3 ship scripts / T4 gate.cjs / T6 READMEs)

#### T1: scanSources collection-layer map-ignore filter
- **Covers**: D-01, R-01, R-06
- **Files**: bin/lib/map/engine.cjs, test/sections/T30-map-edges.test.sh, test/sections/T46-module-structure.test.sh
- **Read first**: bin/lib/map/engine.cjs:82-211 (scanSources + loadMapIgnore + semanticUniverse), test/sections/T30-map-edges.test.sh:134-193, test/sections/T46-module-structure.test.sh:50-52
- **Approach**: In `scanSources`, after `walk(root); files.sort()` and BEFORE the pass-1 read loop, load `ig = loadMapIgnore(root)` and partition `files`: a path is excluded when `ig.has(rel) || [...ig].some((g) => g.includes('*') && core.globMatch(g, rel))` (identical semantics to semanticUniverse:207). Excluded files are dropped before any read/guard/pattern scan, so they produce no rawPairs, no edges, no externals, and never enter `finalFiles` — one filtered universe for all 9 scanSources consumers (gate.cjs:387, map/index.cjs:185/216/297/302, allowlist.cjs:299, engine.cjs:639/716, views.cjs:263). Return shape: the two new keys are CONDITIONAL — set `ignored` (sorted excluded relpaths) and `ignore_dead` (rules matching nothing in walker-admitted set UNION `core.trackedFiles(root)` — semantic-only rules like T30.12's `ignored.md` must NOT be flagged dead) ONLY when non-empty; empty/absent map-ignore → return object has NEITHER key, so writeDeps' spread (engine.cjs:504) keeps no-map-ignore deps.json byte-identical (R-06 literal truth; no snapshot asserts needed). Prefer implementing the partition inline or as a non-exported local to keep the T46 fn ledger untouched; if a top-level fn is unavoidable, declare the drift in T46 EXPECT (fnTotal + fnDist) in the same task. Extend the T30.12 sandbox: add a vendored `vendor/lib.js` with a dup top-level fn, cover it with a `vendor/*` rule, assert it is absent from deps.json `files`/`edges`/`semantic`; keep the existing no-vendored asserts green (regression: empty rule set changes nothing).
- **Done when**: `grep -n "loadMapIgnore" bin/lib/map/engine.cjs` shows the call inside `scanSources` AND `grep "'ignored'" bin/lib/map/engine.cjs` matches the return shape AND `bash test/run-sections.sh T30` green AND (if T46 touched) `bash test/run-sections.sh T46` green
- **Depends on**: none

#### T3: ship-script exclusion via grep -vxFf (pinned exit-code contract)
- **Covers**: D-03, R-03
- **Files**: skills/gos-ship/scripts/cleanup-scan.sh, skills/gos-ship/scripts/security.sh
- **Read first**: skills/gos-ship/scripts/cleanup-scan.sh:1-27, skills/gos-ship/scripts/security.sh:116-121
- **Approach**: In cleanup-scan.sh after line 6 and in security.sh after line 118 (FILES fully built), add the same block with a pinned exit-code contract: `LIST=.gos/codebase/map-ignored.txt`; if the file exists: `ORIG=$FILES; FILES=$(printf '%s\n' "$FILES" | grep -vxFf "$LIST"); rc=$?; [ "$rc" -le 1 ] || FILES="$ORIG"` — grep 0 (all kept) and 1 (some filtered) are accepted; rc ≥ 2 (unreadable list, IO error) restores the unfiltered FILES (full scan — the unknown-fallback is the SAFE direction, never an empty universe). Missing list file → FILES untouched (current behavior). The provenance header line inside the list can never equal a path so it is a harmless pattern. Keep pure bash — no node invocation (D-03-D).
- **Done when**: `grep -c "grep -vxFf" skills/gos-ship/scripts/cleanup-scan.sh skills/gos-ship/scripts/security.sh` = 1 each AND `grep -c 'rc.*-le 1' skills/gos-ship/scripts/cleanup-scan.sh skills/gos-ship/scripts/security.sh` ≥ 1 each AND `bash skills/gos-ship/scripts/cleanup-scan.sh` still exits 0 on the self-repo (no list file → fallback parity)
- **Depends on**: none

#### T4: gate fix hints name map-ignore
- **Covers**: D-04, R-05
- **Files**: bin/lib/ops/gate.cjs
- **Read first**: bin/lib/ops/gate.cjs:1088-1096
- **Approach**: parse-failures fix (gate.cjs:1090) gains " — or exclude vendored paths via .gos/map-ignore then rescan"; dup-fn fix (gate.cjs:1095) gains " — third-party code: exclude via .gos/map-ignore". Text only, verdict logic untouched; no new fns → no T46 drift.
- **Done when**: `grep -n "map-ignore" bin/lib/ops/gate.cjs` matches inside both `codemap-parse-failures` and `codemap-dup-fn-name` fix strings
- **Depends on**: none

#### T6: README en+zh map-ignore section
- **Covers**: D-04, R-05
- **Files**: README.md, README.zh-CN.md
- **Read first**: README.md:81-102 (deterministic layer section), README.zh-CN.md counterpart, test/readme-sync.sh
- **Approach**: Add a `### Excluding vendored code — .gos/map-ignore` subsection (zh mirror with the SAME heading level and anchor shape) under the deterministic-layer/codemap area of both READMEs: glob semantics table (`*` crosses `/`; bare dir name does NOT match; `**` ≡ `*`; exact full-path match), layering vs `.min.js`/skip-dirs (skip-dirs are hardcoded and unconditional; map-ignore is repo-authored and evaluated as full relpath exact-or-glob), the `.gos/codebase/map-ignored.txt` byproduct (rematerialized by every scan — written when ≥1 excluded, deleted when 0 — consumed by ship scripts), and a pointer from the codemap-gate failure hints. English only in README.md, Chinese only in README.zh-CN.md (cjk-lint boundary).
- **Done when**: `grep -c "map-ignore" README.md` ≥ 4 AND `grep -c "map-ignore" README.zh-CN.md` ≥ 4 AND both contain all four glob-table rows (`\*` crosses, bare dir, `\*\*`, exact) AND `bash test/checks/cjk-lint.sh` green AND `bash test/readme-sync.sh` exit 0
- **Depends on**: none

### Wave 2 (depends on Wave 1)

#### T2: scan rematerializes map-ignored.txt + excluded-count line + census entry
- **Covers**: D-03, D-04, R-02, R-05
- **Files**: bin/lib/map/index.cjs, census.json, bin/lib/core/state.cjs, bin/lib/core/locales/zh.cjs, test/sections/T46-module-structure.test.sh
- **Read first**: bin/lib/map/index.cjs:184-203 (scan handler), bin/lib/ops/gate.cjs:1128-1133 (provenance twin), census.json `.gos/codebase/unmapped-fns.txt` entry
- **Approach**: In the `map scan` handler after `writeDeps`: REMATERIALIZE on every scan — if `scan.ignored` has ≥1 entry, write `.gos/codebase/map-ignored.txt`: first line `generated-at: <ISO> @ <HEAD[0:8]|unborn>` (null-safe merge, mirror gate.cjs:1131), then the sorted excluded paths; if 0 entries AND the file exists, DELETE it (a removed/loosened rule must not leave a permanently stale list that ship scripts would keep skipping — fail-open direction closed; the "not written when nothing excluded" invariant is preserved as zero footprint). Scan output gains one line when count > 0: excluded N file(s) via .gos/map-ignore — list: .gos/codebase/map-ignored.txt. Zero-hit rules (`scan.ignore_dead`) print an advisory naming each dead rule (typos/stale paths, red-team F-2). New CONTRACTS semantic_checks keys (en in state.cjs, zh in locales/zh.cjs, placeholder form) for the excluded-count line and the dead-rule advisory. Census entry `.gos/codebase/map-ignored.txt`: `{git:false, npm:false, note}` mirroring the unmapped-fns twin (regenerable byproduct; `.gitignore` `.gos/codebase/*` already covers it — no .gitignore edit). Inline the logic in the scan handler or reuse engine exports from T1; any top-level fn added here or in T5 → declare T46 drift in the SAME task (EXPECT.fnTotal + fnDist).
- **Done when**: `grep -n "map-ignored.txt" bin/lib/map/index.cjs` matches the write + delete + print sites AND `grep -n "map-ignored" census.json` matches the entry AND `bash test/pack-check.sh` green AND `node bin/gos.cjs map scan` on the self-repo prints no excluded-count line (no map-ignore present)
- **Depends on**: T1

#### T5: gate C4 polluted-peak attribution advisory (single helper, both tiers)
- **Covers**: D-02, R-04
- **Files**: bin/lib/ops/gate.cjs, bin/lib/core/state.cjs, bin/lib/core/locales/zh.cjs, test/sections/T46-module-structure.test.sh
- **Read first**: bin/lib/ops/gate.cjs:1135-1171 (C4 block, BOTH tier branches), bin/lib/map/index.cjs:496-510 (baseline reset approve gate), engine.cjs:500-523 (peak.owners producer)
- **Approach**: Implement ONE attribution helper (not per-tier copies) used by BOTH C4 missing-fns branches (tier-1 full list ≤50 and tier-2 by-dir >50): load the exclusion set — when `.gos/codebase/map-ignored.txt` exists AND its provenance HEAD slice equals `h = core.gitHeadSha(); h ? h.slice(0, 8) : 'unborn'` (null-safe — unborn/non-git must not throw), use list membership; when the list is stale (provenance HEAD mismatch) or absent, fall back to live `loadMapIgnore(cmRoot)` + `globMatch` per path. Attribute a missing fn via `peak.owners[f] || f`. Full coverage (every missing fn attributed): print the guided advisory — fns fully covered by map-ignore, rotate via `gos approve baseline-reset --reason "<why>"` + `gos map baseline reset --reason "<why>"` (approve-gated, never auto). Partial: annotate "N of M missing fn(s) from map-ignored paths". The full-coverage RESET GUIDANCE only prints when the list is fresh (provenance HEAD == current head, where unborn==unborn counts as fresh); on stale data the branch degrades to the plain advisory (spec R-04 both-branch guard). New CONTRACTS keys en+zh (placeholder form). Top-level helper fn → T46 drift declaration lands in this task.
- **Done when**: `grep -n "baseline-reset" bin/lib/ops/gate.cjs` matches the guidance site AND `grep -n "map-ignored" bin/lib/ops/gate.cjs` matches the loader AND the attribution helper appears ONCE (single implementation shared by both tiers — grep the helper name, expect one definition) AND new CONTRACTS keys exist in BOTH state.cjs and locales/zh.cjs AND `bash test/run-sections.sh T74` (i18n inventory) green AND (if T46 touched) `bash test/run-sections.sh T46` green
- **Depends on**: T1, T2

### Wave 3 (STRICT SERIAL CHAIN — same test file + same runner + shared manifest; never parallel-dispatch these)

#### T8: E2E section act 1 — vendored repo goes green + list lifecycle + script parity
- **Covers**: D-01, D-03, R-01, R-02, R-03
- **Files**: test/sections/T119-map-ignore.test.sh
- **Read first**: test/sections/T30-map-edges.test.sh:158-193 (sandbox pattern), test-20261117-112508-mapignore-repro/ (THINK reproduction sandbox)
- **Approach**: Sandbox repo (t30_setup style, own tmp dir): vendored `vendor/mxgraph/*.js` with a dup top-level fn `mxActor` (two files) + `src/app.js` importing vendored + own clean code + `.gos/map-ignore` with `vendor/*`. ALL fixture files (vendored included) are `git add` + committed — `git ls-files` must see them or the script-parity asserts are vacuous. Asserts: (a) `map scan` exits 0 and prints the excluded-count line; (b) `node "$GOS" gate codemap` exits 0 — stateless structural leg, NOT `gate all` (which refuses on stateless trees by design, gate.cjs:905-911) — was permanent red on codemap-dup-fn-name (T-01); (c) `.gos/codebase/map-ignored.txt` exists, first line matches `^generated-at: .+ @ ([0-9a-f]{8}|unborn)$`, body lists exactly the vendored files sorted, no `src/` file (T-02); (d) deps.json: vendored absent from files/edges/externals/semantic, src→vendored import degrades to an externals entry (D-01-A); (e) script parity in this order — run from INSIDE the sandbox with the absolute script path (`cd "$SANDBOX" && bash "$GOS_ROOT/skills/gos-ship/scripts/cleanup-scan.sh"`): first prove findings EXIST with no list (plant `console.log` + `eval(` only in vendored files, list absent → findings), then with the list present → exit 0 clean, then remove the list → findings reproduce (fallback parity, T-03); also `chmod 000` the list → findings still reproduce (rc≥2 restores unfiltered FILES, exit-code contract); `chmod 644` after. (f) a dead rule `typo/*.js` in map-ignore → scan prints the advisory naming it (R-02); (g) list lifecycle: empty map-ignore control sandbox → deps.json lacks both new keys AND `map-ignored.txt` absent; rule-removal — after a scan that wrote the list, delete the `vendor/*` rule and rescan → the list file is DELETED (rematerialize semantics) and cleanup-scan findings return (regression + R-01).
- **Done when**: `bash test/run-sections.sh T119` green (act 1 asserts) — the run manifest evidence is read ONCE, after T10's final T119 run
- **Depends on**: T1, T2, T3

#### T9: E2E section act 2 — polluted peak guided reset (stateless-safe approve)
- **Covers**: D-02, R-04
- **Files**: test/sections/T119-map-ignore.test.sh
- **Read first**: bin/lib/map/index.cjs:496-510, bin/lib/ops/gate.cjs:1135-1171, bin/lib/nav/cmds.cjs:128-135 (approve guards)
- **Approach**: In the T119 sandbox: run scan/gate BEFORE adding the map-ignore rule (peak absorbs the vendored fns), then add `vendor/*` and rescan. The sandbox seeds a minimal legal `.gos/state.json` (with `approvals: {}`) so `cmdApprove` passes its noActiveTask die (cmds.cjs:130-131). Approve invocations are pinned as `env -u GOS_AUTO_SPAWNED node "$GOS" approve baseline-reset --reason test` — humanGateGuard (state.cjs:1492-1497) refuses runner-spawned sessions; the assert must not depend on dispatch environment. Asserts: (a) gate codemap prints the guided advisory naming `approve baseline-reset` + `map baseline reset` (fresh provenance HEAD == current HEAD after rescan); (b) `map baseline reset --reason test` WITHOUT the approve gate dies (hard gate intact); (c) after `env -u GOS_AUTO_SPAWNED … approve baseline-reset --reason test` (assert its output confirms the approval) + `map baseline reset --reason test`, re-running gate codemap shows no missing-vs-peak advisory (peak rotated, T-04); (d) stale-list branch: hand-edit the list provenance HEAD to a bogus sha → gate degrades to plain advisory, no reset guidance; (e) unborn branch: fresh sandbox before its first commit → scan+gate codemap run without throwing (null-safe head merge) and guidance freshness treats unborn==unborn as fresh; (f) tier-2 coverage: generate 51+ fns (shell loop) in the vendored tree so peak.fn_count > 50 → by-dir branch with the SAME attribution helper — one fresh/full assertion cycle.
- **Done when**: `bash test/run-sections.sh T119` green covering acts 1+2 (all six polluted-peak asserts)
- **Depends on**: T5, T8

#### T10: E2E section act 3 — self-repo regression + docs/hints presence
- **Covers**: R-01, R-05, R-06, D-04
- **Files**: test/sections/T119-map-ignore.test.sh
- **Read first**: test/pack-check.sh:1-30, README.md new section (from T6), bin/lib/ops/gate.cjs:905-911
- **Approach**: Asserts on the GOS self-repo (no `.gos/map-ignore`): (a) `map scan` exits 0, output contains no excluded-count line, deps.json has NEITHER new key and keeps schema_version 3 — structural equality with the pre-fix contract (files set unchanged because the keys are omitted when empty; no baked file-list snapshot) (T-06); (b) `node bin/gos.cjs gate all --audit` exit 0 (structural-only audit leg runs on any tree; plain `gate all` truths-unverified is a VERIFY-stage duty, not BUILD); (c) `bash test/pack-check.sh` green with the new census entry (F-4); (d) both READMEs contain the map-ignore section with all four glob rows; (e) grepping gate.cjs shows both fix hints name map-ignore (T-05); (f) cleanup-scan.sh exits 0 on self-repo (no list file → full scan parity). Closing duty: re-run `bash test/run-sections.sh T119` as the LAST run and only then read .gos/cache/section-runs/ + run-manifest.json evidence (siblings' earlier runs may have overwritten the manifest — serial chain makes this deterministic).
- **Done when**: final `bash test/run-sections.sh T119` green AND `node bin/gos.cjs gate all --audit` exit 0 on the self-repo AND run-manifest.json records 0 failed sections for T119
- **Depends on**: T9 (strict serial: same test file, same runner, shared manifest)

## Observable Truths

### T-01: vendored repo gate green
- **Expected**: sandbox with dup-fn vendored JS + `.gos/map-ignore` covering it: `map scan` then `gate codemap` exits 0 (was: permanent red on codemap-dup-fn-name)
- **Verify**: `bash test/run-sections.sh T119` (act 1 assert b)

### T-02: map-ignored.txt twin exists with provenance
- **Expected**: after that scan, `.gos/codebase/map-ignored.txt` first line carries generated-at + HEAD, body lists exactly the vendored files; deleted when exclusions drop to 0
- **Verify**: `head -1` matches the provenance regex; `grep -c '^vendor/'` equals the vendored file count; act 1 assert (g)

### T-03: ship scripts honor the list, fallback parity, unreadable-safe
- **Expected**: cleanup-scan.sh + security.sh clean on vendored console.log/eval with the list present; findings reproduce with the list removed AND with the list chmod 000
- **Verify**: T119 act 1 asserts (e)

### T-04: polluted peak guided rotation clears the advisory
- **Expected**: pre-fix peak triggers "fully covered by map-ignore — rotate via approve baseline-reset + map baseline reset"; following it clears the advisory
- **Verify**: T119 act 2 asserts (a)-(c)

### T-05: discoverability chain closed
- **Expected**: both READMEs contain the map-ignore section; both gate fix hints name map-ignore; scan prints excluded count
- **Verify**: grep in T119 act 3 + `grep -rn "map-ignore" README.md README.zh-CN.md bin/lib/ops/gate.cjs`

### T-06: no-map-ignore repos byte-identical
- **Expected**: on the GOS self-repo, scan output and deps.json unchanged vs pre-fix (new keys omitted when empty); pack-check green with the new census entry
- **Verify**: `node bin/gos.cjs map scan && node bin/gos.cjs gate all --audit && bash test/pack-check.sh`; full `gate all` exit 0 lands in VERIFY after truths verification

## Risks

- **scanSources callers assume the frozen return shape**: new keys are conditional (present only when non-empty); deps.json gains them only in repos that actually exclude — self_sha256 recomputed last (verifier parity holds). Mitigation: T30 + T46 + full section suite in Wave 3.
- **T46 frozen ledger (fnTotal 919 + fnDist)**: any top-level fn added by T1/T2/T5 must declare the drift in the SAME task and run T46 — the plan wires this per-task instead of hoping REVIEW notices.
- **T74 i18n inventory**: every new CONTRACTS key must land in en+zh simultaneously — T2/T5 done-when include the T74 run.
- **Gate branch parity**: R-04 semantics are branch-heavy (fresh/stale list x full/partial coverage x tier-1/tier-2 x unborn); T9 asserts every combination explicitly, and tier-2 must reuse the single attribution helper (no branch copies).
- **Dispatch-environment dependence**: approve-gated asserts run under `env -u GOS_AUTO_SPAWNED` with a seeded minimal state.json — plain invocation would die twice over (noActiveTask + humanGateGuard).
- **Wave 3 is a strict serial chain** (same test file, same runner, shared run-manifest) — parallel dispatch would double-edit T119 and race the section runner (paid-for lessons 63675448 / f2589acd / 0ed07587).
- **Sandbox hygiene**: all T119 sandboxes live under the section's own tmp dir (t30_setup pattern); the THINK repro dir `test-20261117-112508-mapignore-repro/` stays untouched (root-level `test-*` dirs are scan-excluded by engine.cjs:92) — removal is SHIP cleanup, not this task.

## Red Team round 4 disposition (plan-attack, 2026-11-17)

| Finding | Disposition | Landed as |
|:--|:--|:--|
| F-1 approve dies in stateless sandbox (noActiveTask + GOS_AUTO_SPAWNED guard) — Critical | ACCEPT | T9: seeded minimal state.json + `env -u GOS_AUTO_SPAWNED` pinned invocation + output grep |
| F-2 plain `gate all` refuses on stateless trees — Critical | ACCEPT | T8(b)/T-01 switched to `gate codemap`; Patterns section records the discipline |
| F-3 self-repo `gate all` red on truths-unverified during BUILD — Major | ACCEPT | T10 done-when → `gate all --audit`; full `gate all` moved to VERIFY |
| F-4 wave-3 parallel same-file/runner/manifest races — Major | ACCEPT | Wave 3 declared strict serial chain T8→T9→T10; manifest read after final run |
| F-5 rule-removal leaves permanently stale list (fail-open for security.sh) — Major | ACCEPT | T2: rematerialize every scan — delete at 0 exclusions; T8(g) asserts the lifecycle |
| F-6 grep -vxFf rc=2 fail-open (unreadable list → empty FILES) — Major | ACCEPT | T3: pinned exit-code contract (rc≤1 accept, ≥2 restore ORIG); T8(e) chmod 000 assert |
| F-7 T46 frozen fn-ledger drift unowned — Major | ACCEPT | T1/T2/T5 carry same-task T46 drift declaration + T46 run in done-when |
| F-8 additive empty keys falsify T-06 byte-identical claim — Major | ACCEPT (option a) | T1: omit `ignored`/`ignore_dead` when empty; T10(a) asserts key absence, no baked snapshot |
| F-9 provenance-HEAD formula TypeError on unborn/non-git — Major | ACCEPT | T5: null-safe `h ? h.slice(0,8) : 'unborn'` pinned; T9(e) unborn sandbox assert |
| F-10 readme-sync.sh never run — Minor | ACCEPT | T6 done-when adds `bash test/readme-sync.sh` exit 0 |
| F-11 T8(e) wrong-repo scan + vacuous parity assert — Minor | ACCEPT | T8(e): committed vendored fixtures, cd sandbox + absolute script path, findings-exist-first ordering |
| F-12 tier-2 by-dir branch modified but uncovered — Minor | ACCEPT-PARTIAL | T5: single attribution helper shared by both tiers (mandatory); T9(f) one tier-2 fresh/full cycle via loop-generated 51+ fns |
