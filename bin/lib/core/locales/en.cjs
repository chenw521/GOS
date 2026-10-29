// core/locales/en.cjs — en canonical catalog (P15 )
// Existing frozen copy = REFERENCES into core.CONTRACTS (single source; copies
// forbidden). New P15+ strings live here as the en canonical home. Structured
// {what, why, fix?} entries are for actionable surfaces (3-part rendered by
// code); non-actionable strings stay plain.
'use strict';

const { CONTRACTS } = require('../state.cjs');

module.exports = {
 // ---- gate-family actionable entries, keyed by failure code
  'gate.coverage-uncovered': {
    what: 'decisions recorded in state but not covered by any plan task',
    why: 'a decision without a covering task is a decision that will never land',
  },
  'gate.decision-uncovered': {
    what: 'decisions recorded in state but not covered by any plan task',
    why: 'a decision without a covering task is a decision that will never land',
  },
  'gate.truths-unverified': {
    what: 'observable truths recorded but not yet verified',
    why: 'an unverified truth is a claim — the gate cannot green-light claims',
  },
  'gate.diff-zero-hit': {
    what: 'a task declared Files but none of them appear in the diff',
    why: 'the plan claims work that never happened — a no-op masquerading as progress',
  },
  'gate.undeclared-diff-file': {
    what: 'a changed file is declared by no plan task and not allowlisted',
    why: 'undeclared changes are how side effects slip past review',
  },
  'gate.spec-gate-card-missing': {
    what: 'a decision has no options card in the spec',
    why: 'a decision without shown alternatives is a model preference, not a decision',
  },
  'gate.lessons-deletion-audit': {
    what: 'a lessons entry was deleted with no disposal audit row (B-8 pure-deletion)',
    why: 'unlogged deletions are how inconvenient lessons silently vanish',
  },
  'gate.orphan-deferred-finding': {
    what: 'a deferred review finding has no parking spot',
    why: 'it dies with the task archive and nobody will remember it',
  },
  'gate.changelog-lint': {
    what: 'CHANGELOG.md failed the changelog lint',
    why: 'the change record is part of the delivery, not an afterthought',
  },
  'gate.gates-lint-exit': {
    what: 'a configured lint rule failed',
    why: 'repo-level lint rules are hard gates, not suggestions',
  },
  'gate.registry-gap-advisory': '[registry-gap] {n} tracked file(s) under .gos/ lack GOS_PATHS registry entries — tracked files are never adopted; register them to silence this. Advisory only (never fails, also under --strict).',

  // ---- status / guidance surfaces (first-user high-frequency, FB-1) ----
  'status.localeLine': 'locale: {locale} (source: {source}) — change via GOS_LANG or `gos setup --lang <en|zh-CN>`',
  'status.noActiveTask.next': 'Next: `gos init <level> "<intent>"` to start one',
  'status.headlessAutoConfirm': '📍 task auto-confirmed in headless mode (audited)',
  'status.aiChatStart': '→ Or in AI chat: "use GOS ..."',
  'status.aiChatContinue': '→ In AI chat: "continue with GOS"',
  'guidance.intent.confirm1': '→ Confirm intent with user. Present 2-3 design options with trade-offs.',
  'guidance.intent.confirm2': '→ Show all levels (Lv0-Lv4) with recommendation highlighted.',
  'guidance.intent.confirm3': '→ After user confirms: `gos init <level> "<confirmed intent>"`',
  'guidance.build.core': '→ Pre-change habit: `gos map blast <paths>` before editing shared files — it lists what else must be checked and why.',
  'guidance.build.aggregate': '→ After each parallel wave: run the aggregation script (one command = conflict scan + docking + unified build).',
  'guidance.build.commit': '→ All tasks done + tests green: `gos commit build` then load `gos-review`.',

  // ---- setup surfaces ----
  'setup.lang.prompt': 'Language [1] English  [2] 中文 (zh-CN) — Enter = keep current: ',
  'setup.lang.saved': 'language saved: {locale} ({source})',
  'help.contractKeysHeader': '  contract keys (not commands — used by test assertions):',

 // ---- logs view surfaces ( / : runtime ledger rendering; paths/counts
  // interpolate — the ledgers themselves are locale-invariant machine files) ----
  'logs.receipts.title': 'truth receipts — {path} (showing last {n} of {total})',
  'logs.exemptions.title': 'gate exemptions — {path} (showing last {n} of {total})',
  'logs.audit.title': 'edge audit — {path} (showing last {n} of {total})',
  'logs.empty': 'no entries yet — the ledger fills as the corresponding commands run',

 // ---- lessons attribution ( ; CONSOLE-only localization — the md view
  // stays locale-invariant en by design, F8) ----
  'lessons.attribution': 'lessons: {projN} project + {globN} global loaded (project: {projPath}; global: {globPath}) — expiring soon: {expiring}',
  'lessons.unavailable': 'lessons: unavailable ({reason}) — the most-run command must never be bricked; fix: `gos lessons list` shows the failure detail',
  'lessons.stageSubsetHeader': 'lessons tagged #{stage} (stage-relevant subset):',
  'lessons.remainderPointer': '… +{n} more lessons (repo memory beyond this stage) — full list: `gos lessons list`',
  'lessons.projectLabel': 'repo knowledge · never expires',
  'lessons.modelLabel': 'cross-repo behavior · expires on date',

 // ---- / language boundary (tracked stores are English-only)
  'langBoundary.trackedStore': 'language boundary: {file} is git-tracked — tracked GOS stores are English-only; rewrite the content in English before saving (untracked stores accept any language)',

 // ---- / gap migrate/history + concerns anchor bootstrap predicate
  'gap.migrate.removed': '✓ migrated {n} stage-back mirror line(s) from concerns.md to the gap-history ledger — state.gaps stays the single source',
  'gap.migrate.none': 'no (auto) mirror lines in concerns.md — nothing to migrate',
  'gap.migrate.dupes': '⚠ {n} mirror line(s) already in the ledger (deduped by text) — cured from concerns.md without re-appending',
  'gap.history.empty': '(no gap history — stage-back mirrors land here via {cmd:gap} migrate)',
  'gap.history.skipped': '⚠ skipped {n} malformed ledger line(s) (.gos/logs/gap-history.ndjson)',
  'concerns.err.anchorMissingDirty': 'concerns.md is git-tracked but .concerns-anchors.json is missing and the file differs from the HEAD blob — hand edit suspected; restore via git checkout, or commit the change first (bootstrap forbidden, no laundering)',

 // ---- T7a/ gos track — validated ignored→tracked flip (validation dies,
  // pre-scan reports, surgery verify, success lines) ----
  'track.err.notRepo': 'track: not a git repository — gos track flips files inside a git worktree only',
  'track.err.notFound': 'track: {path} cannot be resolved to a regular file inside this repository (missing, a directory, or outside the worktree)',
  'track.err.scope': 'track: {path} is outside the .gos/ scope — gos track flips ignored files under .gos/ only',
  'track.err.symlink': 'track: {path} does not resolve to itself (symlinked or traversed argv; canonical: {canon}) — tracked GOS stores must be regular files; point at the real file',
  'track.err.caseArg': 'track: case mismatch — argv says {arg}, the canonical path is {canon}; re-run with the canonical spelling (case-insensitive clones would fork the two)',
  'track.err.caseDisk': 'track: case collision on disk — {other} differs from {path} only by letter case; a case-insensitive clone would clobber one of them, rename one file first',
  'track.err.zone': 'track: {path} is inside the never-track zone {zone} — machine-local by design, nothing there may ever be flipped',
  'track.err.env': 'track: {path} is a secrets file (.env family) — secrets must never be git-tracked',
  'track.err.unborn': 'track: this repository has no commits yet (unborn HEAD) — the flip reconciles against the HEAD blob; make the first commit, then re-run',
  'track.err.tracked': 'track: {path} is already tracked — nothing to flip (re-runs on tracked targets become a verified no-op, and legacy-tracked files get adopt bookkeeping, once the flip manifest transaction lands)',
  'track.err.gitignoreUnsafe': 'track: {path} contains a path component gitignore patterns cannot express verbatim (leading ! or #, trailing space) — rename the file first',
  'track.err.gitAdd': 'track: git add failed for {path}: {err} — the flip was rolled back: worktree files restored byte-identical and the git index swept clean; resolve the git error and re-run',
  'track.err.rollbackIncomplete': 'track: rollback incomplete — {items}; pre-transaction bytes are kept under {dir} (rename them back manually before re-running)',
  'track.prescan.storeCjk': 'track: language pre-scan — tracked store {file} carries CJK at {where}: {text} — tracked GOS stores are English-only; rewrite the content first (the flip touches nothing until every store is clean)',
  'track.prescan.targetCjk': 'track: target {path} carries CJK at line {line}: {text} — tracked stores are English-only; write the file in English, then re-run',
  'track.prescan.sanitize': 'track: sanitize pre-scan hit in {path} at line {line} ({pattern}): {text} — machine-local data must not travel with the repo; remove the leak, then re-run',
  'track.surgery.verifyFail': 'track: gitignore surgery failed verification — the ignored-set diff was [{diff}], expected exactly the target; rolled back, nothing was changed',
  'track.done.surgery': '✓ tracked {path} — .gos/.gitignore negation {negation} verified (ignored-set diff == target), {census}, staged via git add',
  'track.done.noSurgery': '✓ tracked {path} — target not ignored (no gitignore surgery needed), {census}, staged via git add',
 // ---- T7b/ flip transaction: manifest, adopt/no-op , preset
  'track.done.manifest': '  flip manifest: {path} recorded at HEAD {head} (staged with the flip)',
  'track.adopt.done': '✓ adopted {path} — already git-tracked without a manifest record; adopt record appended to .gos/track-manifest.json ({census}), staged via git add',
  'track.noop.done': '✓ {path} already tracked — manifest record present, {census}; verified no-op, zero mutations',
  'track.err.censusContradiction': 'track: {path} is git-tracked but census entry {key} says git:false — contradiction needs human eyes: fix census.json (or untrack the file), then re-run',
  'track.preset.err.missing': 'track --knowledge: {path} is missing — the preset requires all three guide-trio files (.gos/codebase/structure.md, conventions.md, concerns.md)',
  'track.knowledge.done': '✓ knowledge preset complete: {n} file(s) stamped born-at: {head}',

 // ---- / gate flip-reconcile leg (census/git/manifest agreement on
 // tracked .gos files; failure codes join the locale renderer)
  'gate.flip-git-probe-failed': {
    what: 'git truth could not be established for the flip-reconcile leg',
    why: 'fail-closed: with no probe truth the gate refuses to reconcile rather than guess',
  },
  'gate.flip-census-corrupt': {
    what: 'census.json is not parseable JSON at gate time',
    why: 'the disposition ledger is the reconciliation source — a broken ledger fails closed',
  },
  'gate.flip-census-contradicts': {
    what: 'a tracked .gos file is covered by a census entry saying git:false',
    why: 'census and git disagree about the tracked set — one of them no longer describes reality',
  },
  'gate.flip-census-phantom': {
    what: 'a census .gos entry declares git:true but nothing under it is tracked',
    why: 'a declared-tracked zone with no tracked files is ledger drift',
  },
  'gate.flip-manifest-missing': {
    what: 'a tracked .gos file has neither census git:true sanction nor a flip-manifest record',
    why: 'obligations attach to tracked files — a tracked file with no ledger trail is an unaccounted flip',
  },
  'gate.flip.pass': '✓ flip-reconcile: {n} tracked .gos file(s) — census/git values agree, manifest obligations met',
  'gate.flip.skipNoGit': 'flip-reconcile: not a git worktree — no tracked-set truth to reconcile, leg skipped',

  // ---- CONTRACTS aliases (frozen strings — reference, never copy) ----
  'contract.gateFailedPrefix': CONTRACTS.gate_verdicts.gateFailedPrefix,
  'contract.allPass': CONTRACTS.gate_verdicts.allPass,
  'contract.noActiveTask': CONTRACTS.state_semantics.noActiveTask,
  'contract.commitBlocked': CONTRACTS.state_semantics.commitBlocked,
  'contract.globalWriteHint': CONTRACTS.semantic_checks.globalWriteHint,
  "setup.onboard.agentsDesc1": "┃ AGENTS.md injection: add a \"run /gos first for dev tasks\" pointer to ./AGENTS.md,",
  "setup.onboard.agentsDesc2": "┃ so new AI sessions proactively use GOS (creates the file if absent; skips if a GOS block exists).",
  "setup.onboard.agentsPrompt": "    Write the AGENTS.md pointer? [Y/n]: ",
  "setup.onboard.agentsSkip": "┃ ✓ AGENTS.md already has the GOS block — skipped",
  "setup.onboard.agentsWritten": "┃ ✓ wrote {path}",
  "setup.onboard.checkerDesc": "┃  checker (reviewer, the soul of the team profile): cross-validate with a model different from your main one",
  "setup.onboard.checkerPrompt": "    checker model [Enter={suggestion}]: ",
  "setup.onboard.codingHint": "┃ Seed the coding-standards book set into this repo: gos init coding",
  "setup.onboard.doneRestart": "│ Restart your AI assistant, then:                             │",
  "setup.onboard.doneStart": "│   Start: say \"help me with GOS ...\" or type /gos             │",
  "setup.onboard.doneTitle": "╭─ Done ───────────────────────────────────────────────────────╮",
  "setup.onboard.doneVerify": "│   Verify: ask it \"list your gos skills\" (should list 8)      │",
  "setup.onboard.eliteDesc": "┃  3) elite      strong models across the board. Quality first for critical projects, highest cost",
  "setup.onboard.implementerPrompt": "    implementer model [Enter={def}]: ",
  "setup.onboard.langKept": "┃ kept current",
  "setup.onboard.leanDesc": "┃  4) lean       cost first: fast models for execution/research, strong for design. Best for small batch tasks",
  "setup.onboard.otherRoles": "┃ (other roles keep the probed mapping; adjust anytime with gos config models set <agent> <model>)",
  "setup.onboard.pinRoles": "┃ Semantic tiers map automatically, but you can pin key roles (Enter = accept the probed value):",
  "setup.onboard.probeFailed": "┃ Could not auto-probe your model list (no provider config found in opencode.json).",
  "setup.onboard.probeResult": "┃ Probed model pool (strong guess = {strong}, fast guess = {fast}).",
  "setup.onboard.profilePrompt": "Choose [1-4] (Enter = 1 team, current: {current}): ",
  "setup.onboard.profileSaved": "┃ ✓ profile = {profile}",
  "setup.onboard.selfCheck": "┃ Self-check: run `gos doctor` for the full diagnostic (skill links / platforms / staffing).",
  "setup.onboard.skipRefine": "┃ Skipping refinement; everything stays inherit for now — pin roles manually later with:",
  "setup.onboard.soloChangeLater": "┃ (change later: gos config models profile <name>)",
  "setup.onboard.soloDesc": "┃  2) solo       everyone follows the current session model. Simplest, zero extra cost, but no cross-validation",
  "setup.onboard.soloNoRefine": "┃ solo needs no refinement: every subagent directly inherits your session model.",
  "setup.onboard.step1Desc": "┃ Language for GOS output text (commands, code paths, ✓/✗ symbols stay the same in every locale).",
  "setup.onboard.step1Options": "┃  1) English  2) 中文 (zh-CN)",
  "setup.onboard.step1Title": "┏━ [1/4] Language",
  "setup.onboard.step2Desc1": "┃ This decides which model tier GOS dispatches subtasks with (implementation / review / red-team).",
  "setup.onboard.step2Desc2": "┃ It affects cost, speed, and — most importantly — whether the reviewer cross-checks your main model from a different perspective.",
  "setup.onboard.step2Title": "┏━ [2/4] Team staffing (who does the work for you)",
  "setup.onboard.step3Title": "┏━ [3/4] Tier refinement (semantic tier → your concrete model)",
  "setup.onboard.subtitle": "│ 4 steps · Enter = recommended · Ctrl+C keeps defaults        │",
  "setup.onboard.teamDesc": "┃  1) team ★recommended  strong model for design/review, executor follows current; the reviewer cross-checks with a heterogeneous model",
  "setup.onboard.teamWhy": "┃                        (why: the blind spots of your main model are exactly what a different model sees)",
  "setup.onboard.title": "╭─ GOS Onboarding Wizard ──────────────────────────────────────╮",
  "map.net.intro": "Nodes = path anchors (human and machine share the same key); edges = semantic dependencies (five extracted families + hand edges). Usage: change any node → inspect its closure and check the must-check files alongside.",
  "map.net.autoSection": "Auto section (data-derived — do not edit; regenerated by every scan)",
  "map.net.familyStats": "Edge family counts",
  "map.family.calls": "calls (② call sites → cmd anchors)",
  "map.family.contracts": "contracts (③ contract-string consumers)",
  "map.family.testof": "testof (⑤ section annotations → cmd)",
  "map.family.hand": "hand (hand edges from edges.json)",
  "map.family.testof_fn": "testof_fn (⑦ section annotations → fn)",
  "map.net.handDetail": "Hand-edge detail (edges.json)",
  "map.net.closureQuickRef": "Closure quick reference (cmd → must-run sections)",
  "map.net.fnQuickRef": "fn quick reference (fn → sections testing it)",
  "map.net.fullGraph": "Full graph (mermaid)",
  "map.closure.summaryHit": "Summary: this change touches {files} file(s) and {sections} test section(s) — checklist above; self-check and run must-run sections before committing",
  "map.closure.summaryNone": "Summary: the edge net does not cover this change (no known impact — not a safety proof)",
  "map.allowlist.v1Green": "require direction assertion green (lib↔lib edges ⊆ allowlist v1, {n} directions)",
  "map.allowlist.v2Green": "require direction assertion green (v2: {modules} modules, {dirs} directions, {edges} edges)",
  "map.allowlist.dirViolation": "require direction violation: {from} → {to} (module direction {fr}→{tr} not in the allowlist{drift})",
  "map.allowlist.moduleDrift": "; module drift — endpoint not under any registered moduleRoot",

 // ---- brownfield adoption surfaces (status/
  // state-flag/exit tokens and JSON field names stay locale-invariant) ----
  'brownfield.fatal.line': '✗ {msg}',
  'brownfield.title': 'brownfield adoption report — {root}',
  'brownfield.hooksClass.unset': 'core.hooksPath: unset — seeded hooks are dormant (git reads .git/hooks/; GOS never writes .git/hooks/ or git config)',
  'brownfield.hooksClass.gosHooksDir': 'core.hooksPath: resolves to <top>/hooks — a live gos hooks dir; nothing is seeded into it',
  'brownfield.hooksClass.foreign': 'core.hooksPath: foreign hooks manager in charge — GOS never touches git config or its hooks dir',
  'brownfield.assetsHeader': 'assets:',
  'brownfield.reasonLine': 'reason: {reason}',
  'brownfield.rem.header': 'remediation steps:',
  'brownfield.rem.step': '{n}. {asset}: run {command}',
  'brownfield.ovr.header': 'override (destructive — read the consequence before running anything):',
  'brownfield.ovr.step': '{n}. adopt {asset}: run {command}',
  'brownfield.ovr.consequence': 'consequence: {text}',
  'brownfield.err.notGit': 'not a git repository — {cmd:brownfield} adopts an existing repository (exit 4)',
  'brownfield.err.cwd': 'cwd is not the repository toplevel — run from {top} (exit 4; the CLI resolves .gos/ relative to cwd)',
  'brownfield.err.self': 'this is the GOS repository itself — self-adoption is a dev action, refused (exit 5)',
  'brownfield.err.corruptState': 'corrupt hooks state file (not parseable JSON): {path} — fix or remove it, then re-run; it drives teardown restore and is never rewritten (exit 1)',
  'brownfield.err.unknownFlag': 'unknown flag for brownfield: {flag} (known: --json, --overwrite [<asset>], --print-agents-skeleton)',
  'brownfield.err.unexpectedArg': 'unexpected argument for brownfield: {arg}',
  'brownfield.err.doubleOverwrite': 'pass the overwrite flag once — either bare or with a single asset name',
  "brownfield.err.unknownAsset": "unknown asset name for --overwrite: '{name}' (probed assets: {known})",
  'brownfield.err.lockedOverwrite': '--overwrite refused for {asset}: {why}',
  'brownfield.err.skeletonCombo': 'pass --print-agents-skeleton alone — it prints a starter skeleton to stdout and exits (no repo work happens)',
  'brownfield.why.neverConfig': 'core.hooksPath is probed read-only — never modified by GOS',
  'brownfield.why.agent': 'AGENTS.md / CLAUDE.md / GEMINI.md are user-owned guidance files — never written by GOS (print a skeleton instead)',
  'brownfield.why.userHook': 'user-owned hook file (locked_user_owned) — GOS never replaces user hooks; review and chain manually',
  'brownfield.why.foreignHooks': 'foreign hooks manager owns core.hooksPath (locked_user_owned) — never modified by GOS; review chaining manually',
  'brownfield.why.liveDir': 'core.hooksPath already resolves to <top>/hooks — seeding would instantly activate the hooks; the activation command owns that dir',
  'brownfield.why.blocked': 'path is not adoptable ({reason})',
  'brownfield.why.userHookRow': 'user-owned hook (locked_user_owned) — manual review only; never auto-replaced',
  'brownfield.why.driftedHookRow': 'GOS-lineage hook with local edits — kept as-is',
  'brownfield.why.foreignRow': 'foreign hooks manager owns core.hooksPath ({raw}) — chaining requires manual review; GOS never modifies it',
  'brownfield.why.liveDirRow': 'core.hooksPath resolves to <top>/hooks — seeding would instantly activate; the activation path owns this directory',
  'brownfield.why.hooksPathRow.unset': 'unset — hooks seeded dormant; GOS never writes .git/hooks/ or git config',
  'brownfield.why.hooksPathRow.gosHooksDir': 'resolves to <top>/hooks — already the activation layout',
  'brownfield.why.hooksPathRow.foreign': 'foreign value — probed read-only, never modified',
  'brownfield.why.detected': 'existing commitlint config detected ({names}) — not shadowed by a seeded yaml',
  'brownfield.why.divergedYamlRow': 'commitlint.config.yaml diverges from the GOS master — kept as-is',
  'brownfield.why.divergedGateRow': 'file diverges from the GOS-seeded content — kept as-is',
  'brownfield.why.noLock': '`.lock` not ignored — machine lock may be committed',
  'brownfield.note.appended': 'missing .lock line appended',
  'brownfield.why.agentAbsent': 'absent — a starter skeleton can be printed via {cmd:brownfield} --print-agents-skeleton (stdout only, never written); "brownfield" here means adopting an existing repo, not the D-22 decision-import',
  'brownfield.why.agentPresent': 'present — user-owned file, never touched',
  'brownfield.why.agentIrregular': 'path occupied by a non-regular entry — review manually',
  'brownfield.why.writeFailed': 'write failed: {message}',
  'brownfield.why.engineSkip': 'not adoptable this run — engine skip reason: {outcome}; clear the entry at the path (directory or unreadable file) manually, then re-run',
  'brownfield.cons.replace': 'replaces your file; backup at {path}',
  "brownfield.cons.createBeside": "creates 'commitlint.config.yaml' — it takes precedence over your existing config ({names})",
  'brownfield.cons.append': 'appends the missing .lock line to your file; backup at {path}',
  'brownfield.handoff.header': 'next steps:',
  'brownfield.handoff.mapPreview': 'codebase map: not run here — the single trigger is {cmd:init} <level> (Lv3 recommends, Lv4 auto-generates)',
  'brownfield.handoff.platformsHeader': 'AI-platform skills links (read-only probe):',
  'brownfield.handoff.platformRow': '{name}: {status}',
  'brownfield.handoff.platformFix': 'fix missing links: run {cmd:setup} --no-onboard',
  'brownfield.handoff.noPlatform': 'none detected — run {cmd:setup} --no-onboard to link GOS skills',
  'brownfield.skeleton.body': '# AGENTS.md — starter skeleton\n# (fill in each section, then delete these comment lines)\n\nIntroduction: what this repository is and who uses it (one short paragraph).\n\n## Build\n\nHow to build or compile this project — commands and what a successful build looks like.\n\n## Test\n\nHow to run the test suite — the command and how to read the results.\n\n## Conventions\n\nThe conventions contributors must follow (code style, commit messages, review flow).\n',
  'brownfield.skeleton.note': 'printed to stdout only — GOS never writes AGENTS.md/CLAUDE.md/GEMINI.md; save it yourself with a redirect if you want the file',

  // ---- spec gate floors (card column contract, stamp domain) ----
  'gate.spec-gate-card-column': {
    what: 'a decision card table violates the column contract',
    why: 'the Activates column is missing, a cell is empty, or a cell copies the Pros column — a value-essence cell that names no consumer is decoration, not a decision',
  },
  'gate.spec-gate-version-unknown': {
    what: 'the spec gate stamp is outside the floor domain this CLI knows',
    why: 'an unknown stamp fails closed so a newer state can never vacuous-pass under an older CLI',
  },

  // ---- commit-side guards (stage monotonicity) ----
  'commit.stage-regression-blocked': {
    what: 'requested stage {stage} is behind the current stage {current}',
    why: 'an already-passed stage cannot re-advance — the commit would write an advance label history already moved past',
    fix: 're-run the current stage commit if idempotent redelivery is intended; to re-freeze a frozen spec use gos commit think --refreeze (state-only, no stage advance)',
  },

  // ---- auto mode: runner trust store (machine-local) ----
  'auto.store.missing': {
    what: 'auto runtime store not found at {path}',
    why: 'a missing store is treated like a corrupt one — never a silent fresh start',
    fix: 'run `gos auto on` to create it (tracked counters warn over implied prior history)',
  },
  'auto.store.corrupt': {
    what: 'auto runtime store at {path} is corrupt or failed schema validation',
    why: 'runner trust state (counters, breaker, lock, approvals) cannot be verified from a damaged store',
    fix: 'inspect the file; if unrecoverable run `gos auto off --purge` then `gos auto on` — cost history survives via tracked mirror counters',
  },
  'auto.store.versionMismatch': {
    what: 'store schema v{found} is not known to this CLI (knows v{known})',
    why: 'a future-shaped store may contain records this version would misread',
    fix: 'upgrade GOS to the version that wrote the store; never hand-edit store_schema_version',
  },
  'auto.store.unwritable': {
    what: 'auto runtime store directory {path} is not writable',
    why: 'the auto loop cannot persist counters, breaker state, or the run lock without it',
    fix: 'check ownership/permissions (and the XDG_DATA_HOME override), then re-run `gos auto on`',
  },
  'auto.store.lockHeld': {
    what: 'an auto run is already active (pid {pid}, since {since})',
    why: 'the run lock is exclusive per machine and repository',
    fix: 'wait for it to finish; if it is genuinely stuck, wait for heartbeat staleness or remove it deliberately only after verifying no gos process runs',
  },
  'auto.store.lockHeartbeatStale': {
    what: 'auto run lock held by pid {pid} but its heartbeat is stale',
    why: 'pid reuse can fake liveness; the stale heartbeat is the second signal',
    fix: 're-run with --break-lock once the holder is confirmed dead',
  },
  'auto.store.lockCrossHost': {
    what: 'auto run lock held by another machine ({hostname}, clone {clone})',
    why: 'this machine-local store cannot judge a remote pid — cross-host staleness is unverifiable from here',
    fix: 'confirm no runner is live on that host, then re-run with --break-lock (recorded as a takeover event)',
  },
  'auto.store.lockBreakRefused': {
    what: '--break-lock refused: pid {pid} is alive on {hostname}',
    why: 'a live pid with a fresh heartbeat owns the lock; breaking it would corrupt a running loop (attempt recorded as a takeover event)',
    fix: 'wait for the run to finish; only break after the holder process is dead',
  },
  'auto.store.recreatedOverHistory': {
    what: 'creating a fresh store while tracked counters imply prior history (spawns {spawnCount}, trips {tripCount})',
    why: 'cost history must not silently reset when the store is lost',
    fix: 'confirm this is intended — counters carry over from the tracked mirrors',
  },

  // ---- auto mode: host adapters / capability negotiation ----
  'auto.host.unknown': {
    what: 'host has no registry.json matrix row',
    why: 'fail-closed on unknown hosts',
    fix: 'install a supported host or add a registry.json row',
  },
  'auto.host.probeVersion': {
    what: 'binary version missing/unparsable',
    why: 'spawn-time capability check failed',
    fix: 'update the host binary; matrix entries named in message',
  },
  'auto.host.probeNoMatch': {
    what: 'installed version satisfies no matrix entry',
    why: 'version skew',
    fix: 'update the host or add a registry.json row',
  },
  'auto.host.probeHelpFlags': {
    what: 'help output lacks required flags',
    why: 'CLI contract changed',
    fix: 'update the host or the row\u0027s required_flags',
  },
  'auto.host.probeConfig': {
    what: 'host config root unresolvable',
    why: 'adapter needs a config root',
    fix: 'create the host config dir or set OPENCODE_CONFIG_DIR',
  },
  'auto.host.invalidRow': {
    what: 'matrix row has invalid version_range',
    why: 'identity pins are forbidden policy',
    fix: 'use semantic predicates (>=, <) in registry.json',
  },
  'auto.host.registryUnreadable': {
    what: 'registry.json missing/corrupt',
    why: 'negotiation data unavailable',
    fix: 'reinstall GOS or repair registry.json',
  },
  'auto.host.statusNotSelectable': {
    what: 'matrix status is not verified',
    why: 'fixture-tested/probe-pending are display-only',
    fix: 'host becomes selectable after dogfood verification flips the row',
  },
  'auto.host.streamMalformed': {
    what: 'event stream contained malformed JSON',
    why: 'stream contract broken',
    fix: 'classified failure — counts into the breaker, never crashes',
  },
  'auto.host.streamNoTerminal': {
    what: 'stream ended without a terminal event',
    why: 'no verifiable outcome',
    fix: 'counts as failure; re-probe the host version',
  },
  'auto.host.displayOnly': {
    what: 'spawn attempted on a display-only host',
    why: 'adapter has no live path',
    fix: 'use a verified host',
  },
  'auto.host.spawnError': {
    what: 'host process failed to spawn/timeout',
    why: 'environment failure',
    fix: 'counts as env-class failure into the breaker',
  },

  // ---- auto mode: capability launcher (profiles + sandbox engine) ----
  'auto.launcher.unknown-profile': {
    what: "auto profile '{name}' is not one of: {known}",
    why: 'an unknown profile must never fall back silently — the mask and deny posture would be a guess',
    fix: 'pass one of {known} (default: restricted); full additionally requires an explicit allowFull flag',
  },
  'auto.launcher.full-flag-required': {
    what: 'the full capability profile was requested without an explicit upgrade flag',
    why: 'full lowers the deny baseline, so it must be a deliberate choice rather than a default drift',
    fix: 're-run with the explicit allowFull option, or keep restricted/workspace',
  },
  'auto.launcher.missing-mandatory-mask': {
    what: "profile '{profile}' is missing mandatory masks: {missing}",
    why: 'the trust store, delivery credentials, and host state dirs must stay masked in every profile — dropping one reopens a bypass',
    fix: 'restore the mask entries in the profile file or update the CLI so profiles stay complete',
  },
  'auto.launcher.profile-corrupt': {
    what: "auto profile '{name}' failed validation: {detail}",
    why: 'a malformed capability profile cannot be composed safely',
    fix: 'fix the JSON in {file} or reinstall the templates',
  },
  'auto.launcher.profile-unreadable': {
    what: "auto profile '{name}' could not be read ({detail})",
    why: 'the launcher refuses to spawn without a verified profile',
    fix: 'restore {file} or reinstall the CLI package',
  },
  'auto.launcher.escape-detected': {
    what: "spawned stream matched deny pattern '{pattern}': {line}",
    why: 'the lexical layer is depth, not redundancy — a deny hit in the captured stream means the injected config was bypassed or ignored',
    fix: 'review the spawn record in the store; the breaker counts this as a failure',
  },
  'auto.launcher.tier-lexical': 'hardening tier: lexical — no sandbox engine (bwrap) on PATH; deny is enforced by the injected config and the escape detector only (network stays open; model-provider auth readable by design)',
};
