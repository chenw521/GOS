# Plan: P4 — Repo Content Policy

> **Date**: 2026-10-22 | **Based on spec**: `.gos/task/p4/spec.md`
> Red Team R4 (plan-attack) findings folded: registry 3-way sync (F-1),
> monopoly-check task (F-2), wave serialization (F-3/F-9), boundary breadth
> (F-4), concrete greps (F-5), task splits (F-6/F-7), i18n probe (F-8),
> truth clauses (F-10), GOS_PATHS timing (F-11).

## Decision Inventory

- [x] D-12: identity de-pathed (v4, repo_id, runtime root) → T3, T4a, T4b
- [x] D-13: dialogue governance → P5 (parking enforced here) → T13
- [x] D-14: obligations attach to tracked files (negative assertion) → T7a, T8, T12
- [x] D-15: flip gate = track command + gate leg → T7a, T7b, T8
- [x] D-16: mirror cure via product migration command → T6
- [x] D-17: language boundary at write path → T5
- [x] D-18: repo_id all-remotes normalized matching → T3, T4a
- [x] D-19: knowledge refresh + THINK hint in P4 → T9, T11
- [x] D-20: navigator tiers → T9, T11

## Requirement Claims

- [x] R-01: sanitized tracked state / flip gate / single-source / navigator → T3-T14

## Patterns to Follow

- Modules: bin/lib/<domain>/<file>.cjs, sibling-requires only (state.cjs style)
- Command registration is 3-WAY sync (R4-F1): state.cjs COMMANDS table +
  bin/lib/nav/registry-consts.cjs (KNOWN_CASES/WRITE_CMDS) + bin/gos.cjs
  dispatch — one command, all three, same commit
- Tests: test/sections/T<N>-<slug>.test.sh, runner rc-checked (next free id: T93)
- New user-facing strings: locales/en.cjs + zh.cjs (dot-key namespaces; verify
  via test/checks/i18n-inventory.sh, not LANG_ greps — R4-F8)
- Census: explicit file paths, lifecycle entries for new zones (dfb28c0f);
  directory-level entries already cover most new files (R4 verified)

## Execution Waves

### Wave 1 (parallel, no deps)

#### T1: gitprobe fail-closed probe module
- **Covers**: (§3.0 primitive for D-14/D-15/D-17)
- **Files**: bin/lib/core/gitprobe.cjs, test/sections/T93-gitprobe.test.sh
- **Read first**: bin/lib/core/fsio.cjs (execFileSync patterns, sanitizeEcho), bin/lib/core/state.cjs
- **Approach**: isTracked = ls-files --cached ∪ cat-file -e HEAD; git failure
  (rc≠0/stderr/exception/GIT_DIR poison) → returns true + cached-failure
  marker; ignoredSet via one porcelain -uall --ignored=matching call;
  canonicalRepoRel via realpath + case guard; export through core index.
- **Done when**: T93 passes: GIT_INDEX_FILE=/dev/null probe → true; untracked
  → false; rm --cached TOCTOU case covered by cat-file leg.
- **Depends on**: none

#### T3: schema v4 — migrateState + repo_id derivation
- **Covers**: D-12, D-18
- **Files**: bin/lib/core/state.cjs, test/sections/T94-schemav4.test.sh, test/sections/T1-schema.test.sh
- **Read first**: bin/lib/core/state.cjs (migrateState), bin/lib/ops/gitseed.cjs:104
- **Approach**: STATE_SCHEMA_VERSION=4; v3→v4 lazy: delete version/project_root,
  add repo_id; deriveRepoId(url): canonical host:port/path (host lowercase,
  IPv6 brackets+hex-lowercase, port defaults 22/443/9418, path case-preserved,
  strip .git/slash/credentials, scp→host:22/…); sha256[:16]; argv reads; raw
  URL never stored. Mutation row 1 (T1-schema → v4).
- **Done when**: T94 URL matrix (11 forms) passes; v3 fixture migrates;
  T1-schema asserts schema_version==4 (row 1 lands here).
- **Depends on**: none

#### T14: gitprobe monopoly check + legacy probe migrations
- **Covers**: §3.7 (RT3-F11) — enforces D-14/D-15/D-17 primitive monopoly
- **Files**: test/checks/gitprobe-monopoly.sh, bin/lib/task/archive.cjs, bin/lib/ops/doctor.cjs
- **Read first**: T1 gitprobe exports, bin/lib/task/archive.cjs:341-346, bin/lib/ops/doctor.cjs:105-125
- **Approach**: banned-strings check: `ls-files --cached` / `check-ignore` /
  `--ignored=matching` must not appear in bin/lib/** except gitprobe.cjs;
  migrate existing violations FIRST (archive.cjs:346, doctor.cjs:112/119 to
  gitprobe calls) so the check lands green; concerns.cjs:33 migration belongs
  to T6 (same file, same wave-2 serial chain).
- **Done when**: `grep -rn "check-ignore\|--ignored=matching\|ls-files --cached" bin/lib --include='*.cjs' | grep -v gitprobe.cjs` returns NOTHING; check script green in isolation; archive/doctor behavior unchanged (existing sections green).
- **Depends on**: T1

### Wave 2 (T5 then T6 — serialized, both touch nav/cmds.cjs gap dispatch: R4-F3)

#### T5: language boundary at all three GOS text stores + gap rewrite
- **Covers**: D-17
- **Files**: bin/lib/core/state.cjs, bin/lib/core/fsio.cjs, bin/lib/knowledge/concerns.cjs, bin/lib/knowledge/lessons-json.cjs, bin/lib/nav/cmds.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs, test/sections/T96-lang-boundary.test.sh
- **Read first**: T1 gitprobe, concerns.cjs (write paths), lessons writer, cmds.cjs:159-192
- **Approach**: trigger = gitprobe.isTracked(state.json ∨ concerns.md ∨
  lessons.json) — boundary enforced at EACH store's write path (writeState
  recursive leaf walk; appendConcernsLine + lessons writer check the new
  line/payload), fail-closed via T1 primitive; zh hit → die w/ bilingual
  guidance (locales dot-keys); `gos gap rewrite <G-id> --text` subcommand
  (sanitized, boundary-checked). T5 OWNS the gap dispatch usage line.
- **Done when**: T96 passes: tracked state + zh decision → exit 1; tracked
  concerns.md + zh `gos concerns add` → exit 1; GIT_DIR poison → still exit 1;
  all-untracked fixture → accepted; gap rewrite clears legacy zh description;
  i18n-inventory hasCJK==0 on touched files; T74 green.
- **Depends on**: T1, T3

#### T6: gap migrate product command + history + anchor bootstrap
- **Covers**: D-16
- **Files**: bin/lib/nav/cmds.cjs, bin/lib/knowledge/concerns.cjs, bin/lib/core/state.cjs, bin/lib/core/locales/{en,zh}.cjs, .gitignore, census.json, test/sections/T97-gap-migrate.test.sh, test/sections/T23-concerns.test.sh
- **Read first**: concerns.cjs:38-90 (anchors + write order), stage.cjs:23-31, concernsRootLock, T5's dispatch shape
- **Approach**: `gos gap migrate` in concernsRootLock: ledger appends
  (per-line JSON.stringify, {ts,text} dedupe, sentinel), edit concerns.md
  FIRST then rebuild anchors + .bak same-transaction; `gos gap history`
  reader (try→skip+count); bootstrap predicate in loadConcerns (anchors
  missing ∧ tracked ∧ hash-object==HEAD blob → rebuild silently, mismatch →
  die); stage.cjs drops mirror call; swap concerns.cjs:33 to gitprobe;
  ledger zone gitignore + census lifecycle; INVERT T23 (row 5).
- **Done when**: T97: mirror fixture → 0 remaining (auto), ledger==removed,
  re-run no-op, `gos concerns list` rc=0, bootstrap rebuilds, tampered dies;
  T23 inverted & green; registry 3-way sync for migrate/history/rewrite.
- **Depends on**: T5, T14

#### T4a: lock guard rewrite + worktree detection
- **Covers**: D-12, D-18
- **Files**: bin/lib/core/lock.cjs, test/sections/T95-repo-id-guard.test.sh, test/sections/T5-guard.test.sh, test/sections/T82-*.test.sh
- **Read first**: lock.cjs:160-201, T3 deriveRepoId export
- **Approach**: guard = repo_id ∈ remote hashes (exact, then lowercase);
  null+remotes → derive+store; mismatch → die w/ anchor-fix hint; no-remotes →
  advisory once; worktree (git-dir ≠ git-common-dir) ∧ state.json tracked →
  die w/ guidance; re-anchor write-back path REMOVED (byte-stability T-01).
- **Done when**: T95: clone fixture guard OK across protocol variants;
  foreign-remotes die; worktree+tracked die; T5-guard/T82 mutations green.
- **Depends on**: T3

### Wave 3 (depends on Wave 2)

#### T4b: consumer re-pointing + anchor fix re-derive + goldens
- **Covers**: D-12
- **Files**: bin/lib/map/anchor.cjs, bin/lib/task/init.cjs, bin/lib/knowledge/phase.cjs, bin/lib/ops/paths.cjs, test/sections/T2-project.test.sh, test/sections/T10-security-e2e.test.sh, test/golden/pre-split/help.txt, test/golden/pre-split/contract.txt
- **Read first**: T4a guard, all project_root consumers (grep list from spec §3.1)
- **Approach**: all writers → currentRootRealpath() (cached); anchor fix
  re-derives repo_id; mutations rows 2, 4, 7 land.
- **Done when**: `grep -rn "state.project_root =" bin/lib/` empty; T2/T10
  mutations + goldens updated; T94-T95 still green.
- **Depends on**: T4a

#### T7a: gos track — validation + surgery + flip core
- **Covers**: D-15, D-14
- **Files**: bin/lib/ops/track.cjs, bin/lib/core/state.cjs, bin/lib/nav/registry-consts.cjs, bin/gos.cjs, bin/lib/core/locales/{en,zh}.cjs, test/sections/T98a-track-core.test.sh
- **Read first**: T1 gitprobe, T5 boundary (pre-scan reuse), census _doc, scripts/census-dispose.sh
- **Approach**: steps 1-5: canonical path + lstat no-symlink + never-track
  zones + unborn die + NOT-tracked precondition + case-variant die;
  tri-store+target pre-scan die-before-touch; sanitize table hit → die w/ hit
  line; `.gos/.gitignore` relative-anchored negation + ignored-diff=={target}
  verify; census-if-present edit; `git add`. Scope `.gos/**` only.
- **Done when**: T98a: flip core green (±census fixture, root-exclude
  positive); negatives die (.env/symlink/zone/unborn/case); registry 3-way:
  `node bin/gos.cjs track --json` rc=0 envelope + registry-consts grep.
- **Depends on**: T5, T6

#### T7b: gos track — manifest + backups + adopt/no-op + preset
- **Covers**: D-15, D-14
- **Files**: bin/lib/ops/track.cjs, bin/lib/core/state.cjs, test/sections/T98b-track-txn.test.sh
- **Read first**: T7a, fsio atomic writes (T1 try/finally)
- **Approach**: manifest append (`.gos/track-manifest.json` {ts,path,head}
  per-line, GOS_PATHS-registered); rename-style backups in
  .gos/cache/track-backup/ (rollback = rename, ENOSPC-safe); adopt semantics
  ({adopted:true} + census check, exit 0); re-run no-op; `--knowledge` preset
  (trio + born-at idempotent replace).
- **Done when**: T98b: injected mid-transaction failure → all stores restored;
  manifest recorded; adopt + no-op + preset cases green.
- **Depends on**: T7a

#### T8: gate flip-reconcile leg
- **Covers**: D-15, D-14
- **Files**: bin/lib/ops/gate.cjs, bin/lib/core/locales/{en,zh}.cjs, test/sections/T99-gate-flip-leg.test.sh
- **Read first**: T7b track, gate.cjs leg registration + gateFail/gateCmd
- **Approach**: file-granular (`git ls-files -z -- .gos`); per-file expected
  value via most-specific census key (census-if-present); lifecycle:true
  exempt; both-direction value mismatch → FAIL; tracked non-zone .gos file
  w/o manifest → FAIL (census-less too); gitprobe-based; gateCmd fix lines;
  self-repo negative assertion (guide trio + concerns + lessons git:false).
- **Done when**: T99: mismatch FAIL both directions; manifest-less FAIL;
  `.gos/task` lifecycle no false-FAIL; self-repo negative green; `gos gate
  all` rc=0 on this repo.
- **Depends on**: T7b, T14

### Wave 4 (T9 after T8 — same gate.cjs region, R4-F9; T10 parallel-safe)

#### T9: navigator bundle — rename + header + THINK hint
- **Covers**: D-19, D-20
- **Files**: bin/lib/ops/gate.cjs, bin/lib/task/context.cjs, skills/gos-think/reference/codebase-mapping.md, census.json, test/sections/T35-codemap-coverage.test.sh, test/sections/T100-navigator.test.sh
- **Read first**: gate.cjs:870-885 (after T8's edits), context.cjs:85-100
- **Approach**: rename untested-fns.txt → unmapped-fns.txt (writer + census +
  readers, both sides declared); gate writes `generated-at: ISO @ HEAD[0:8]`
  header; wording "unmapped fn(s) without test annotation"; T35 line-count
  math accounts header; THINK context navigator hint; codebase-mapping.md
  directory contract + travel tiers (closes #11 half).
- **Done when**: T100: header present; "unmapped" wording; THINK hint in
  context JSON; T35 green; `grep -rn untested-fns bin/ test/ skills/` empty.
- **Depends on**: T8

#### T10: #24 — #N tokens + commit-time neutralization
- **Covers**: R-01 (#24 item)
- **Files**: bin/lib/ops/changelog-core.cjs, bin/lib/task/commit.cjs, bin/lib/ops/push.cjs, test/sections/T101-issue-tokens.test.sh
- **Read first**: changelog validator, commit.cjs message build, push.cjs:137-160
- **Approach**: validator accepts `#N`; neutralize at commit-time choke point
  (shared fn used by commit + aggregate): keyword set {fix,fixes,fixed,
  close,closes,closed,resolve,resolves,resolved} CI + `\s+` adjacency to `#N`
  → `refs #N`, subject AND body, both channels.
- **Done when**: T101: `fixes #12` bullet accepted; committed + aggregate
  messages contain NO trigger sequence (`grep -Ei
  '(fix(es|ed)?|clos(e|es|ed)|resolv(e|es|ed))[[:space:]]+#12'` empty);
  untouched `refs #12` passes through.
- **Depends on**: none (parallel with T9)

#### T11: self-repo knowledge refresh (dogfood)
- **Covers**: D-19, D-20
- **Files**: .gos/codebase/structure.md, .gos/codebase/conventions.md, .gos/codebase/concerns.md, .gos/task/p4/evidence/knowledge-refresh.md
- **Read first**: bin/gos.cjs + bin/lib tree (current truth), T9 naming
- **Approach**: cure drift in guide trio (4800-line claims → 262-line entry +
  bin/lib tree; hotspots to current modules); born-at stamps = refresh HEAD,
  recorded in evidence ledger with the sha; repo STAYS opted out.
- **Done when**: `grep -r 4800 .gos/codebase/` empty; each trio file line 2 =
  `born-at: <sha>` == evidence ledger sha; census git:false unchanged.
- **Depends on**: T9

### Wave 5 (depends on Wave 4)

#### T12: wiring checklist + census/gitignore lifecycle + docs
- **Covers**: D-14, R-01
- **Files**: README.md, AGENTS.md, skills/gos-think/reference/codebase-mapping.md, .gos/README.md, census.json, .gitignore, test/pack-check.sh, test/checks/gitprobe-monopoly.sh
- **Read first**: §3.7, gos paths --markdown flow
- **Approach**: GOS_PATHS registry audit (creators registered their own keys —
  R4-F11; here: README regen no-drift); doc routing rows; pack-check +
  cjk-lint green; census lifecycle audit for every file T1-T11 created.
- **Done when** (concrete greps, R4-F5): (1) `grep -rn "gos track" README.md
  AGENTS.md` ≥1 each + gap migrate/rewrite in codebase-mapping.md ≥1; (2)
  `grep -n "gate.track\|gate.gap" bin/lib/ -r` ≥1; (3) `grep -rn
  "track_manifest\|gap_history\|track_backup" bin/lib/core/state.cjs` ≥3 AND
  `gos paths --markdown` leaves `git status .gos/README.md` clean; (4)
  i18n-inventory hasCJK==0 + T74 green; pack-check rc=0; cjk-lint rc=0.
- **Depends on**: T4b, T5, T6, T7b, T8, T9, T10

#### T13: deferred parking + self-repo migrate + full-suite verification
- **Covers**: D-13, D-16 (self-repo first caller), R-01
- **Files**: .gos/concerns.md, .gos/logs/gap-history.ndjson
- **Read first**: lesson d1d02a55, T6
- **Approach**: `gos concerns add` two deferred anchors (rt2-f9 shared-lock
  redesign; d-13 P5 handoff); run `gos gap migrate` on self-repo; full suite
  SERIAL (63675448): sections + MAIN SUITE gos-cli-tests.sh RC=0 (ead7fa41) +
  self-repo assertions `--fresh` rerun (2c8e1978).
- **Done when**: concerns.md 0 (auto) lines (`grep -c "(auto)"` → 0); 2
  deferred anchors grep-verifiable; main suite RC=0; fresh rerun green; no
  *.tmp* residue in git status.
- **Depends on**: T6, T12

## Observable Truths

### T-01: schema v4 (spec T1)
- **Expected**: no version/project_root; schema_version 4; repo_id 16-hex|null; fresh clone write-class leaves state.json byte-identical
- **Verify**: T94 fixture + `grep -E '"(version|project_root)"' .gos/state.json` empty

### T-02: clone-resume (spec T2)
- **Expected**: clone fixture: gos status works, guard passes, worktree clean, tracked concerns bootstrap silently
- **Verify**: T95 scripted clone fixture rc=0

### T-03: identity guard (spec T3)
- **Expected**: foreign-remotes die w/ hint; URL matrix (11 forms) passes; worktree+tracked die
- **Verify**: T94/T95 matrix cases

### T-04: language boundary (spec T4)
- **Expected**: any store tracked + zh into any string leaf → exit 1 (incl. tracked concerns.md adds); poison → still fires; all untracked → OK; gap rewrite clears legacy CJK description
- **Verify**: T96 assertions

### T-05: gap single-source (spec T5)
- **Expected**: 0 (auto) remain; ledger==removed (dynamic); migrate idempotent; history works; `gos concerns list` exits 0; stage back never touches concerns.md
- **Verify**: T97 + self-repo T13 run + `grep -c "(auto)" .gos/concerns.md` → 0

### T-06: flip transaction (spec T6)
- **Expected**: atomic flip ±census; rollback on injected failure; negatives die (.env/symlink/zone/unborn/case-variant); adopt + no-op semantics
- **Verify**: T98a/T98b assertions

### T-07: gate leg (spec T7)
- **Expected**: census value-equality FAIL both directions; manifest-less FAIL in census-less repo; lifecycle no false-FAIL
- **Verify**: T99 + `gos gate all` rc=0 self-repo

### T-08: navigator (spec T8)
- **Expected**: unmapped-fns.txt generated-at header; "unmapped" wording; THINK hint in context JSON
- **Verify**: T100 assertions

### T-09: knowledge refresh (spec T9)
- **Expected**: no 4800 claims; stamps == evidence-ledger HEAD; files stay untracked
- **Verify**: `grep -r 4800 .gos/codebase/` empty + stamp/ledger compare + census git:false

### T-10: #24 neutralization (spec T10)
- **Expected**: `fixes #12` bullet accepted; NO trigger sequence in any committed message, both channels
- **Verify**: T101 regex probe on commit + aggregate fixtures

## Risks

- Schema v4 breaks shipped sections → mutation rows land IN their owning wave (rows: 1→T3, 2→T4b, 3→T4a, 4→T4b, 5→T6, 6→T9, 7→T4b, 8→T4a); main-suite RC=0 pinned in T13
- Full suite always serial (63675448); wave executors never self-commit (be49bdd4)
- If BUILD overflows: T11 slips to milestone closeout; T10 (#24) is first cut
- Parallel wave dispatch: T5/T6 serialized (cmds.cjs); T7a/T7b serialized; T9 after T8 (gate.cjs region)
