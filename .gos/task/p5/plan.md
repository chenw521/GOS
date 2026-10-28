# Plan: P5 dialogue governance

> **Date**: 2026-10-28 | **Based on spec**: .gos/task/p5/spec.md
> Red Team round 4 (plan-attack) dispositioned: F1..F11 all ACCEPT, folded
> below (RT4 markers; T5/T6 merged per RT4-F2).

## Decision Inventory

- [x] D-32: deep-dig teach+shape, five weak-cell controls → T3, T7
- [x] D-33: exemplars-as-contract, 3 de-identified cases → T3, T4
- [x] D-34: card-tail deepen line, new-facts contract → T3
- [x] D-35: Activates header, symmetric non-copy fill → T1, T7
- [x] D-36: message-body rendering, free-text responses → T3
- [x] D-37: Cons+Risks merge, 5-column card → T3, T7
- [x] D-38: plain narration contract (zh middle-school / en CET-4) → T3, T7
- [x] D-39: content-era probing stamp, floor registry, --refreeze, guards → T1, T2, T5, T9, T10

## Requirement Claims

- [x] R-45: dialogue contract upgrade → T3, T10
- [x] R-46: exemplar file + grep check → T4
- [x] R-47: thin-gate v3 → T1, T2, T5, T9
- [x] R-48: seeded surfaces → T7
- [x] R-49: instructions/navigator pointers → T8

## Patterns to Follow

- Gate failures: `core.gateFail(code, {verdict, evidence, fix})` three-part; user-facing strings via locale keys (en.cjs + zh.cjs, T74 parity test).
- Fixtures: test/sections/T*.test.sh, sandbox + `git init`, hand-written scratch state + real `node "$GOS"` invocations (T73 style). run-sections.sh takes ONE filter argument — multi-section runs loop per section (RT4-F4).
- Skill files: skills/ tree is the seeded source (single tree, symlinked by setup) — edit in repo, no census action needed for new files under the tracked skills dir (RT4 census check).
- CHANGELOG via `node bin/gos.cjs changelog add`, never hand-format (RT4-F11).

## Execution Waves

### Wave 1 (parallel, no deps)

#### T1: floor registry + v3 floors in gate.cjs + locales + T73 fixtures
- **Covers**: D-35, D-39 (gate half), R-47
- **Files**: bin/lib/ops/gate.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs, test/sections/T73-gate-evidence.test.sh
- **Read first**: bin/lib/ops/gate.cjs:430-514 (current floor), test/sections/T73-gate-evidence.test.sh, spec §2.1 D-35/D-39 cards, spec §5 parsing contract
- **Approach**: export `SPEC_CARD_FLOORS = {2: fn, 3: fn}` from gate.cjs (single source, RT3-F2; CLI_MAX := Math.max(...Object.keys(SPEC_CARD_FLOORS)) — RT4-F9); v2 = current behavior untouched; v3 adds: canonical table parsing (unescape `\|`, trim, row cell count must equal its own header row, no parse escape hatch), card-table detection (header row starts with Option AND contains Premise — two-column Option|Note exempt), Activates header required on every card table, per-option-row Activates cell non-empty and trim-then-byte-unequal to the Pros cell, heading match prefix-anchored so `D-40: superseding D-39` cannot cross-credit; stamp domain validation {2..CLI_MAX} with `spec-gate-version-unknown` fail-closed (fix text names remedies + `GOS_SPEC_GATE_FLOOR_OVERRIDE` escape honored), lazy probe for absent stamps naming `commit think --refreeze`, floor-version print on every branch. Failure code `spec-gate-card-column`. Locale keys for both new codes. T73 fixtures (hand-written state + gate-driven, no commit-side dependency): good 5-column card, missing-Activates fail, empty cell fail, Pros-copy fail, malformed row fail, v2-stamp grandfather pass, absent-stamp lazy-probe pass, stamp=99 fail-closed, string stamp "3" fail-closed (RT4-F8), override escape honored, superseding-heading no false-pass (11 cases).
- **Done when**: `grep "SPEC_CARD_FLOORS" bin/lib/ops/gate.cjs` matches AND `grep "spec-gate-card-column\|spec-gate-version-unknown" bin/lib/core/locales/en.cjs bin/lib/core/locales/zh.cjs` matches AND `bash test/run-sections.sh T73` exits 0 with all 11 cases
- **Depends on**: none

#### T2: state schema — spec_gate_version validation + version bump + schema tests
- **Covers**: D-39, R-47
- **Files**: bin/lib/core/state.cjs, test/sections/T94-schemav4.test.sh, test/sections/T1-schema.test.sh
- **Read first**: bin/lib/core/state.cjs (validateState, schema version guard ~:274, in-memory migration path), current STATE_SCHEMA_VERSION value, T94/T1-schema literal assertions (RT4-F1)
- **Approach**: add spec_gate_version to validateState type checks (integer when present); bump STATE_SCHEMA_VERSION and update the literal `want 4` assertions in T94/T1-schema to the new value in the SAME task (atomic — the six T94 sites and the T1-schema pair, RT4-F1). Live state carries schema_version=4 + spec_gate_version=2: the in-memory read/write migration must keep both valid (v2 is inside the legal stamp domain).
- **Done when**: `grep -n "spec_gate_version" bin/lib/core/state.cjs` matches validateState AND `bash test/run-sections.sh T94` and `bash test/run-sections.sh T1-schema` each exit 0 AND a scratch-state write/read round-trip exits 0 (write a new-version state via a sandboxed write-class command, read back clean — RT4-F10) AND `node bin/gos.cjs status` exit 0 on the live repo
- **Depends on**: none

#### T3: dialogue-protocol.md contract rewrite (skill layer)
- **Covers**: D-32, D-33, D-34, D-36, D-37, D-38, R-45
- **Files**: skills/gos-think/reference/dialogue-protocol.md
- **Read first**: current dialogue-protocol.md in full, spec §2.1 cards D-32..D-38, spec §5 scope notes on supersede guidance
- **Approach**: rewrite the Decision Card section: 5-column template (Option|Premise|Pros|Cons|Activates) with rendered example; deep-dig round — one instruction line (read examples/deep-dig-cases.md before the first card of a session; dig per domain, at minimum who consumes it and what real data says — starting point, never stopping point); standing deepen line after recommendation (response contract: exemplar-form dig opening with a `new facts:` line; empty increment closes the port); rendering contract (cards in message body, free-text responses, tools only for card-free logistics); plain-narration contract (the reply itself is plain; bans unexplained proper nouns, uncommon-noun overuse, opaque abbreviations; caliber: Chinese middle-school, English CET-4; canonical markers stay, grounded by prose); response-table rows for deepen and plain rephrase; supersede guidance (copied legacy cards rewritten to current era, RT3-F1).
- **Done when**: `grep "Activates" skills/gos-think/reference/dialogue-protocol.md` matches AND `grep "deep-dig-cases" skills/gos-think/reference/dialogue-protocol.md` matches AND `grep "middle-school" skills/gos-think/reference/dialogue-protocol.md` matches AND `grep "new facts:" skills/gos-think/reference/dialogue-protocol.md` matches
- **Depends on**: none

#### T4: exemplar file + de-identification check (own section)
- **Covers**: D-33, R-46
- **Files**: skills/gos-think/examples/deep-dig-cases.md, test/sections/T103-deepdig-exemplars.test.sh
- **Read first**: spec §2.1 D-33 card (RT1-F6/RT2-E9/RT3-F5 constraints), .gos/concerns.md:67/85 (source narratives — for adaptation only, no ids in output), AGENTS.md content policy
- **Approach**: three cases rewritten de-identified (no hex concern ids, no D-NN anchors, no shas, no ISO dates, no task names): positive dig that reshaped a card mid-session; negative card-without-dig whose facts surfaced only under challenge; corpus-quantification dig (regex root-cause + module counts). Each case shows the dig, the card it produced (5-column), and one deepen round with `new facts:`. T103 runs the grep check scoped to this file: concern-id `[0-9a-f]{8}`, `D-[0-9]{2,3}($|[^0-9])`, sha `[0-9a-f]{7,40}`, ISO date `[0-9]{4}-[0-9]{2}-[0-9]{2}` — all zero-hit.
- **Done when**: file exists with 3 cases AND `bash test/run-sections.sh T103` exits 0 AND `grep -cE "[0-9a-f]{8}|D-[0-9]{2,3}($|[^0-9])|[0-9a-f]{7,40}|[0-9]{4}-[0-9]{2}-[0-9]{2}" skills/gos-think/examples/deep-dig-cases.md` returns 0
- **Depends on**: none

### Wave 2 (parallel; T5 owns commit.cjs+gate.cjs exclusively)

#### T5: commit-side stamp lifecycle + --refreeze + stage guard (merged T5+T6, RT4-F2/F6)
- **Covers**: D-39, R-47
- **Files**: bin/lib/task/commit.cjs, bin/lib/ops/gate.cjs, bin/lib/core/locales/en.cjs, bin/lib/core/locales/zh.cjs
- **Read first**: bin/lib/task/commit.cjs:128-290 (usage, freeze, lazy-freeze) + :354-357 (stage advance), T1's SPEC_CARD_FLOORS export, spec D-39 lifecycle paragraphs
- **Approach**: first freeze (THINK commit or lazy-freeze) probes v3 then v2 via the shared registry (require SPEC_CARD_FLOORS from the gate module — no local probe re-implementation, RT4-F9) and stamps the highest passing version; prints stamped version + count of v3-failing tables; content passing none is blocked; re-freeze dispatches the floor on the existing stamp and never upgrades; legacy lazy-frozen (sha, no stamp) states get stamped through the same probe; B-22 mismatch fix text at gate.cjs:573 reworded to name `commit think --refreeze`. `--refreeze` = pure state op (recompute sha, keep/probe stamp, no stage advance, no advance-labeled commit); usage text lists the flag (commit.cjs usage lines); stage-monotonicity guard in cmdCommit's pre-mutation block emits named failure `stage-regression-blocked` (locale keys en+zh).
- **Done when**: `grep "SPEC_CARD_FLOORS" bin/lib/task/commit.cjs` matches (registry import, RT4-F9) AND scratch-state probes: old-format card freezes to stamp 2 under the new CLI, new-format to 3, re-freeze keeps 2, `--refreeze` on a scratch state recomputes sha with no stage change (exit 0) AND `grep "refreeze" bin/lib/ops/gate.cjs` matches AND `grep "stage-regression-blocked" bin/lib/task/commit.cjs bin/lib/core/locales/en.cjs bin/lib/core/locales/zh.cjs` matches AND `bash test/run-sections.sh T73` still exits 0
- **Depends on**: T1, T2

#### T7: seeded surfaces — SKILL rows, router level-card, spec-with-redteam, spec-template
- **Covers**: D-32, D-35, D-37, D-38, R-48
- **Files**: skills/gos-think/SKILL.md, skills/gos-router/SKILL.md, skills/gos-think/examples/spec-with-redteam.md, templates/spec-template.md
- **Read first**: T3's rewritten dialogue-protocol.md (wording source of truth), current four files
- **Approach**: gos-think SKILL.md — per-gray-area row updates (card contract 5-column + dig round + read-exemplars pointer), anti-rationalization table gains the self-check line ("cells with no consumer name after stripping adjectives = no dig"); router SKILL.md — level-choice card rendered example updated to 5-column; spec-with-redteam.md — card example moved to 5-column, legacy anchor wording scrubbed while touching (exempt-marker where illustrative); spec-template.md — D-NN section gains 5-column scaffold with differentiated placeholders (pros…/activates…) + one filled example row, replacing the bullet format.
- **Done when**: `grep "Activates" skills/gos-think/SKILL.md skills/gos-router/SKILL.md skills/gos-think/examples/spec-with-redteam.md templates/spec-template.md` matches all four AND `grep "deep-dig-cases" skills/gos-think/SKILL.md` matches AND `grep "no consumer name\|consumer name" skills/gos-think/SKILL.md` matches
- **Depends on**: T3

#### T8: instructions pointer + navigator hint wording
- **Covers**: R-49
- **Files**: bin/lib/nav/status.cjs, bin/lib/task/context.cjs
- **Read first**: status.cjs:120-133 (structuredNextActions — neighboring lines are hardcoded, not locale-keyed; match that style, RT4-F5), context.cjs:97-133 (navigator + blast hints)
- **Approach**: think-stage next-actions gain one hardcoded line (house style of status.cjs:122-127): read examples/deep-dig-cases.md before the first card; navigator hint wording gains the design-time blast/closure entry (name `gos map closure` / `gos map blast` for impact awareness — 326f6bd8 tail, D-19 goal).
- **Done when**: `grep "deep-dig-cases" bin/lib/nav/status.cjs` matches AND `grep "map closure\|map blast" bin/lib/task/context.cjs` matches AND `node bin/gos.cjs instructions think` output contains the exemplar pointer (T4-truth evidence)
- **Depends on**: T4

### Wave 3 (depends on Wave 2)

#### T9: fixture chain updates + full-suite green
- **Covers**: D-39, R-47
- **Files**: test/sections/T17-semantic-engine.test.sh, test/sections/T22-map-gate-impact.test.sh, test/sections/T31-map-gate.test.sh, test/sections/T33-map-manifest.test.sh
- **Read first**: each file's card fixtures + commit-think steps, T1's fixture style
- **Approach**: update the four fixture cards to the 5-column contract so their real commit-think chains pass the v3 probe (RT1-F1); run per-section then the full suite (run-sections.sh takes one filter — loop, RT4-F4).
- **Done when**: `for s in T17 T22 T31 T33 T73 T103 T94 T1-schema; do bash test/run-sections.sh "$s" || exit 1; done` completes AND full `bash test/run-sections.sh` exits 0
- **Depends on**: T5

#### T10: CHANGELOG + upgrade note
- **Covers**: R-45
- **Files**: CHANGELOG.md
- **Read first**: CHANGELOG.md recent entries (format), spec §7 RT3-F8; `node bin/gos.cjs changelog --help`
- **Approach**: `node bin/gos.cjs changelog add` first (never hand-format, RT4-F11; hand-edit only to align with T55 lint if the CLI lacks a field): 5-column cards with Activates, deep-dig exemplars, standing deepen, plain-narration contract, thin-gate v3 (new failure codes), content-era stamps (in-flight v2 tasks unaffected), --refreeze, GOS_SPEC_GATE_FLOOR_OVERRIDE, schema bump forces one-time CLI upgrade.
- **Done when**: `grep "Activates" CHANGELOG.md` matches AND `grep "refreeze" CHANGELOG.md` matches AND the changelog lint check passes
- **Depends on**: T5

## Truths verification map (VERIFY stage)

- T1: dogfood transcript sampled POST-BUILD (a THINK dialogue after P5 lands — VERIFY-time or next task), saved at .gos/task/p5/evidence/t1-transcript.md; pre-mechanism session cards are origin evidence, not mechanism proof (RT4-F7)
- T2: T73 fixtures (11 cases, see T1) + four-chain suite green (T9)
- T3: T3/T4/T7/T8 done-when greps + file existence
- T4: `node bin/gos.cjs instructions think` contains the pointer

## RT4 disposition note

F1 (schema tests atomic in T2), F2 (T5+T6 merged), F3 (T4 own section T103),
F4 (per-section loop), F5 (hardcoded line per house style), F6 (Files fixed,
CONTRACTS dropped in favor of usage text), F7 (transcript post-BUILD),
F8 (string-stamp fixture + regex tail + count), F9 (registry import grep +
CLI_MAX pin), F10 (scratch write round-trip), F11 (changelog via CLI) — all
ACCEPT and folded above.
