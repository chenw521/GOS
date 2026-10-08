// core/locales/en.cjs — en canonical catalog (P15 D-63)
// Existing frozen copy = REFERENCES into core.CONTRACTS (single source; copies
// forbidden). New P15+ strings live here as the en canonical home. Structured
// {what, why, fix?} entries are for actionable surfaces (3-part rendered by
// code); non-actionable strings stay plain.
'use strict';

const { CONTRACTS } = require('../state.cjs');

module.exports = {
  // ---- gate-family actionable entries, keyed by failure code (D-66 join) ----
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

  // ---- lessons attribution (D-67; CONSOLE-only localization — the md view
  // stays locale-invariant en by design, F8) ----
  'lessons.attribution': 'lessons: {projN} project + {globN} global loaded (project: {projPath}; global: {globPath}) — expiring soon: {expiring}',
  'lessons.unavailable': 'lessons: unavailable ({reason}) — the most-run command must never be bricked; fix: `gos lessons list` shows the failure detail',
  'lessons.stageSubsetHeader': 'lessons tagged #{stage} (stage-relevant subset):',
  'lessons.remainderPointer': '… +{n} more lessons (repo memory beyond this stage) — full list: `gos lessons list`',
  'lessons.projectLabel': 'repo knowledge · never expires',
  'lessons.modelLabel': 'cross-repo behavior · expires on date',

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
};
