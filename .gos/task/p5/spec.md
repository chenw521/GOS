# P5 Spec — Dialogue Governance (deep-dig rounds, card contract v2, thin-gate v3)

Phase: P5 · Level 3 · Intent: Mandatory deep-dig rounds before decision cards,
standing deepen option in every card, value-essence (Activates) column, table
rendering contract (message body vs tool picks), thin-gate extension. Re-homes
concern cab1a0f8 from P2. Consumes 326f6bd8 (dialogue-protocol half + navigator
hint wording tail).

> Red Team: R1 (misuse, 10) + R2 (edge, 12 + re-attack verdicts) + R3
> (completeness, 12) all dispositioned in §7 (RT1-Fn / RT2-En / RT3-Fn).

## 1. Problem

The P15 card contract optimized for AI/expert consumption and structural
enforceability but never guaranteed the human consumer comprehension or
dig-before-card behavior: cards get presented without any consumption-chain
reconnaissance (7b0c1d6a — key facts surfaced only after user challenge),
jargon-dense narration made a card unreadable to its primary human consumer
(this session: version-stamp card needed a full plain-language re-telling),
Cons/Risks split columns drift arbitrarily in model practice, and there is no
standing channel to demand another dig round on any option.

## 2. Decisions (recorded via `gos decision add`)

| ID | Decision |
|:--|:--|
| D-32 | Deep-dig = teach + shape: battery in protocol, value-essence column carries the dig, gate checks header only; five weak-cell controls. |
| D-33 | Dig content contract = exemplars-as-contract: 3 real case records + one instruction line; perspectives emerge per domain. |
| D-34 | Standing deepen = card-tail line; rounds exempt from follow-up caps, must surface new facts. |
| D-35 | Value-essence column header = `Activates`; symmetric fill, names a consumer, distinct from Pros. |
| D-36 | Cards render in message body, responses free-text; tools only for card-free logistics. |
| D-37 | Card template merges Cons+Risks into one Cons column; modality carried by wording, 5-column card. |
| D-38 | Plain language = the reply itself, not an added translation layer; bans unexplained proper nouns, uncommon-noun overuse, opaque abbreviations; caliber: Chinese at middle-school level, English at CET-4. |
| D-39 | Gate activation: spec_gate_version 2->3; v3 = v2 floor + Activates header; v2 specs keep old floor. |

## 2.1 Decision cards (v3 contract: Option | Premise | Pros | Cons | Activates)

### D-32: deep-dig mechanism — teeth without bureaucracy?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| teach + shape (chosen) | a cell one cannot fill without digging removes the ritual | zero ceremony; dig-card one flow; gate stays 1 structural regex | weak cells still pass the floor | dialogue-protocol.md card contract + gos-think self-check line |
| marker round + gate existence | auditability strongest | automatic enforcement | performative compliance; user-rejected as over-strict | gate marker line (rejected) |
| teach only | lightest | no gate change at all | relapse shape 7b0c1d6a documented | protocol text alone (rejected) |

why-not: marker round — catalyzes dig-as-compliance, user ruling; teach only — 7b0c1d6a relapse with no mechanism catching it.
recommendation: teach + shape — conditional: five controls vs weak cells (cell micro-format, self-check line, deepen port, recurrence-escalation clause, exemplar anchoring); gate content check only after a proven weak-card relapse.

### D-33: dig content contract — what carries "meaningful digging"?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| exemplars-as-contract (chosen) | cases demonstrate good digging; perspectives emerge per domain | anti-performative (negative case shows the failure shape); no labels to fill | quality depends on exemplar strength + model adherence | examples/deep-dig-cases.md + one instruction line in dialogue-protocol.md |
| hard floor two questions | guaranteed minimum coverage | floor always answered | digging degrades to answer-the-two-questions | protocol checklist (rejected) |
| interactive perspective confirm | user shapes dig direction | user control | contradicts AI-proactive goal; +1 turn per card | dialogue round (rejected) |

why-not: hard floor two questions — checklist thinking turns dig into quiz; interactive perspective confirm — hands initiative back, opposite of the goal.
recommendation: exemplars-as-contract — conditional: instruction line carries two starter questions (who consumes it / what does real data say) as a starting point, never a stopping point; hard floor reconsidered only if logs show digs stopping at the floor. Cases are rewritten de-identified (RT1-F6): no concern hex ids, no D-NN anchors, no commit shas, no dates/task names in file content (AGENTS.md content policy covers product-seeded assets); real-history provenance lives in commit messages; a mechanized grep (concern-id and D-NN patterns zero-hit on examples/) backs it.

### D-34: standing deepen — which form?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| card-tail line (chosen) | visibility = usage; the missing port was the D-13 relapse | always in view; zero structure cost | +1 line per card; banner-blindness risk | dialogue-protocol card template + response-table row |
| literal table row | in-table visibility | none — structural pollution | gate token/why-not semantics break | options table (rejected) |
| response-table entry only | minimal diff | no template change | invisible affordance = does not exist | response table alone (rejected) |

why-not: literal table row — category error, gate extracts it as an option token; response-table entry only — D-13 evidence: unadvertised affordances do not get used.
recommendation: card-tail line — conditional: response contract = one exemplar-form dig with NEW facts, card re-presented; each deepen round opens with a `new facts:` line listing the increment (RT1-F8 — makes the recurrence clause observable; empty increment closes the port with "no new facts"); deepen rounds exempt from the 3-follow-up cap, user-driven, uncapped.

### D-35: value-essence column header — which word?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| `Activates` (chosen) | question-as-header prompts the cell form directly | self-explanatory: the header asks "activates what?" | not the original concern term | gate.cjs header regex + dialogue-protocol template |
| `Value-essence` | cab1a0f8 original term, searchable | traceable to concerns history | noun header invites abstract value talk | gate.cjs header regex (rejected) |
| bilingual loose | zh-friendly | — | violates English-only writing policy; doubles regex surface | locale-dependent regex (rejected) |

why-not: `Value-essence` — needs surrounding prose to explain what goes in the cell; bilingual loose — repo writing policy bans it and false-match surface doubles.
recommendation: `Activates` — conditional: concerns index and exemplar file anchor back to the original term ("value-essence column, header Activates"); symmetric fill is structurally enforced (RT1-F5): every option row's Activates cell must be non-empty and, when both cells parse, not identical to the same row's Pros cell (failure `spec-gate-card-column`); semantic quality (does it truly name a consumer) stays with judgment layers — no pattern sniffing.

### D-36: table rendering contract — where do cards live?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| message body + free text (chosen) | dual consumers re-read history; tool payloads render unreliably | composite replies (deepen + steer) survivable; history re-readable | token typos need model tolerance | dialogue-protocol rendering section + host behavior |
| body + question tool for choice | structured collection | zero choice ambiguity | fixed menus cannot carry composite replies | question-tool flow (rejected) |
| dual track by card size | adaptive | flexible | track choice becomes a laziness exit | conditional flow (rejected) |

why-not: body + question tool for choice — this session's two card reshapes came from free-form steering menus cannot express; dual track by card size — "this card is simple" becomes an excuse to skip the body contract.
recommendation: message body + free text — conditional: structured tools stay legal for card-free logistics (gray-area multiselect, bare confirms); any card-bearing interaction is message-body.

### D-37: Cons vs Risks — merge or keep split?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| merge to one Cons column (chosen) | natural language carries modality natively (will/might) | 6->5 columns; kills the which-column coin flip; no mechanical consumer reads them apart | certainty semantic drops from structure to wording | dialogue-protocol template + router level-card + spec-template.md |
| keep split | risks deserve separate identification | future risk-realization review has anchors | human readability verdict negative; boundary unstable in practice | P15 template (rejected) |
| merge with in-cell prefixes | shape merged, semantics kept | both | unchecked micro-format drifts (D-32 lesson) | template + wording convention (rejected) |

why-not: keep split — no gate or review surface reads the columns apart today, re-split on evidence if that changes; merge with in-cell prefixes — another uncheckable format, decoration not contract.
recommendation: merge — conditional: exemplars demonstrate modality wording (certain costs stated plainly, hazards marked with "may/could"); re-split only when REVIEW actually consumes risks separately.

### D-38: plain language — what is the mechanism?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| the reply itself (chosen) | narration is written plainly from the start; no translation artifacts | zero added structure; understanding forcing function (cannot say plainly = did not understand) | style contracts are uncheckable by gate | dialogue-protocol narration contract + exemplars' prose |
| per-card plain line | every card self-carries a plain sentence | structural guarantee | user ruling: not a new layer | card template line (rejected) |
| on-demand plain port | ask and receive re-telling | zero per-card cost | invisible affordance; cost already paid (user failed to understand) | response-table entry (rejected) |

why-not: per-card plain line — user ruling 2026-10-28: the reply itself must be plain, not an appended translation; on-demand plain port — the comprehension cost is already paid before the port fires.
recommendation: the reply itself — conditional: bans overused uncommon nouns, unexplained proper nouns, uninterpretable abbreviations; caliber anchor: Chinese at middle-school education level, English at CET-4 level; canonical markers (why-not:, option tokens) stay where structure requires, grounded by surrounding plain prose.

### D-39: gate activation — how does the new floor avoid prosecuting old specs?

Stamp lifecycle (RT1-F1..F4 + RT2-E1/E2/E12 folded): the stamp records the
CONTENT's era, not the CLI's era. At first freeze (THINK commit or lazy-freeze)
the freezer probes floors v3 then v2 and stamps the highest version the content
actually passes; content passing none is blocked. Re-freeze checks the floor of
the EXISTING stamp and never upgrades it.

Stamp vocabulary lives in a single floor registry exported once
({v2: fn, v3: fn} from the gate module — RT3-F2); probe and gate call the same
functions, no re-implementation. At gate time an absent stamp (legacy
lazy-frozen population that already passed its freeze event) is lazily probed
with the same registry, the probed floor is enforced for that run, and the
output names `commit think --refreeze` as the persisting path (RT3-F3);
`--refreeze` on a stamp-absent state uses first-freeze probe semantics.

Mixed-era content (RT3-F1): probing is weakest-link — any v2-format table drops
the whole spec to stamp 2. The freezer prints the stamped version and the
count of v3-failing tables; supersede guidance in dialogue-protocol.md requires
copied legacy cards to be rewritten to the current era rather than dragging the
floor down silently. The stamp domain is validated: integer in {2..CLI_MAX}; anything else
(including type errors) fails closed as `spec-gate-version-unknown`, whose fix
text names the remedies (upgrade CLI / return to the newer branch) with an
explicit escape `GOS_SPEC_GATE_FLOOR_OVERRIDE=1` (policy: user-approved only,
GOS_ALLOW_MAIN_PUSH precedent). Stamp-vocabulary growth bumps
STATE_SCHEMA_VERSION so older CLIs die loudly on newer states instead of
vacuous-passing.

`--refreeze` is a pure state operation: recomputes the sha, keeps the stamp
(absent stamp → probe), never advances the stage, never writes an
advance-labeled commit (8630eee9 class). The B-22 mismatch fix text at
gate.cjs:573 is reworded to name `commit think --refreeze`; usage,
CONTRACTS, and locale lines list the flag (RT3-F4). The stage-monotonicity
guard is a named failure (`stage-regression-blocked`) in cmdCommit's
pre-mutation block with locale keys (RT3-F4).

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| content-era probing stamp (chosen) | stamp = highest floor the content passes at first freeze | old-authored specs never prosecuted after crash-upgrade-resume; new content earns v3 automatically; uniform for legacy lazy-frozen states | probing runs two passes at first freeze (cheap, pure functions) | commit.cjs probe+stamp at first freeze / dispatch-on-stamp at re-freeze + gate.cjs v3 branch, fail-closed domain + T73/T17/T22/T31/T33 fixtures |
| first-freeze CLI stamp (RT1 disposition) | stamp = freezing CLI's floor | simple | crash-upgrade-resume prosecutes old-authored cards (RT2-E1 disproof) | rejected — three counter-examples |
| separate boolean flag | per-floor granularity | fine-grained | combinational state space, three surfaces to sync | rejected |

why-not: first-freeze CLI stamp (RT1 disposition) — RT2 counter-evidence: spec authored under old CLI + THINK crash + upgrade + resume runs the new floor on old cards, exactly the D-18 false-positive class; separate boolean flag — self-made drift surface.
recommendation: content-era probing — conditional: re-freeze never upgrades (explicit floor-upgrade path deferred until a real need appears); freeze floor dispatched on the stamp at re-freeze; `gos commit think --refreeze` recomputes sha without advancing stage, plus a stage-monotonicity guard in cmdCommit (RT2-E4 — the never-upgrade lifecycle makes re-freeze first-class, the pre-existing stage-skip trap must close with it).

## 3. Requirements

| ID | Requirement |
|:--|:--|
| R-45 | Dialogue contract upgrade: 5-column card with Activates, exemplars-as-contract dig, standing deepen line, message-body rendering, plain narration |
| R-46 | Exemplar file examples/deep-dig-cases.md: 3 curated real cases + read-before-first-card pointer |
| R-47 | Thin-gate v3: content-era stamp via single floor registry, Activates header + non-empty + not-Pros-identical floors with canonical parsing (`\|` unescaped, cells trimmed, row cell count must equal its own table's header count — trim-then-byte-exact identity; card table = pipe table whose header row starts with Option and contains Premise, two-column Option|Note tables exempt), every card table in a D-NN section carries the Activates header, stamp domain {2..CLI_MAX} fail-closed, locale keys, T73 fixtures (pass / missing-column / v2-grandfather / legacy-lazy probing / stamp=99 / Pros-copy / malformed-row / superseding-heading) |
| R-48 | Seeded surfaces: spec-template card scaffold, gos-think SKILL rows, router level-card, anti-rationalization line |
| R-49 | instructions think and navigator hint point at dig exemplars and blast/closure entry |

Decision coverage: D-32→R-45/R-46/R-48, D-33→R-45/R-46, D-34→R-45, D-35→R-45/R-47/R-48,
D-36→R-45, D-37→R-45/R-48, D-38→R-45/R-48, D-39→R-47, 326f6bd8 tail→R-49.

## 4. Observable Truths

| ID | Truth |
|:--|:--|
| T1 | A fresh post-P5 THINK dialogue presents 5-column cards whose Activates cells name concrete consumers (dogfood transcript excerpt kept at .gos/task/<id>/evidence/t1-transcript.md, machine-local untracked — RT1-F9/RT2-E11/RT3-F6; the cad2c015 untracked-artifact blind spot is an accepted known class, gate checks disk existence only) |
| T2 | T73 fixtures prove: v3 card passes; missing Activates header fails (spec-gate-card-column); v2-stamped spec stays green; legacy lazy-frozen unstamped state probes to its content era; stamp=99 and non-integer stamps fail closed (spec-gate-version-unknown); Pros-copy cell fails; malformed table row fails; superseding headings cross-credit no longer false-pass |
| T3 | dialogue-protocol.md ships dig contract, deepen line, rendering contract, plain-narration contract; examples/deep-dig-cases.md holds 3 curated real cases |
| T4 | gos instructions think output shows the exemplar read-before-first-card pointer |

## 5. Scope (files)

- skills/gos-think/reference/dialogue-protocol.md — contract rewrite (5-column
  card, dig round instruction line, deepen line, rendering contract,
  plain-narration contract, response-table rows for deepen)
- skills/gos-think/SKILL.md — table rows + anti-rationalization self-check line
- skills/gos-think/examples/deep-dig-cases.md — new, 3 curated cases,
  de-identified (RT1-F6), plus a grep check scoped to this file only
  (concern-id, D-NN, sha-length hex, ISO-date patterns zero-hit — RT2-E9,
  RT3-F5; teaching examples elsewhere use the exempt-marker mechanism);
  task names stay manual review; in-file references use repo-root-relative
  paths, §Decision Card anchor stays stable (three external references —
  RT3-F10)
- skills/gos-think/examples/spec-with-redteam.md — card example updated to the
  5-column contract; scrub legacy anchor wording while touching it (RT1-F7)
- skills/gos-router/SKILL.md — level-card contract sync (5-column, plain narration)
- bin/lib/ops/gate.cjs — specCardFloorFailures: Activates header check on
  every Option-headed pipe table in a D-NN section (RT2-E7), non-empty +
  not-Pros-identical cell checks with canonical parsing — unescape `\|`,
  trim cells, column-count mismatch fails, trim-then-byte-exact identity,
  no parse escape hatch (RT2-E6); spec_gate_version 3 branch; stamp domain
  validation {2..CLI_MAX} with `spec-gate-version-unknown` fail-closed and
  remediation-naming fix text + `GOS_SPEC_GATE_FLOOR_OVERRIDE` escape
  (RT2-E3/E5); heading match anchored so superseding headings cannot
  cross-credit (RT2-E8); floor-version print on every branch
- bin/lib/task/commit.cjs — content-era probe + stamp at first freeze
  (including lazy-freeze and legacy unstamped states) via the shared floor
  registry, re-freeze dispatches floor on the existing stamp (RT2-E1/E2/E12,
  RT3-F2); `gos commit think --refreeze` (pure state op: sha recompute, no
  stage advance, no advance-labeled commit), stage-monotonicity guard
  (`stage-regression-blocked`) in the pre-mutation block, usage/CONTRACTS/
  locale lines (RT2-E4, RT3-F4); gate.cjs:573 B-22 fix text reworded to
  name --refreeze
- bin/lib/core/state.cjs — spec_gate_version type check in validateState
  (RT2-E3); STATE_SCHEMA_VERSION bump so older CLIs die loudly on the new
  stamp vocabulary (RT1-F2 residue, RT2-E5)
- bin/lib/core/locales/en.cjs, zh.cjs — new failure strings
- bin/lib/task/context.cjs — navigator hint wording tail (blast/closure entry)
- bin/lib/nav/status.cjs — instructions/next-actions think output carries the
  exemplar read-before-first-card pointer (RT3-F9: this is the instructions
  source, not bin/lib/task/)
- CHANGELOG.md — user-visible contract change entry + upgrade note (schema
  bump semantics, in-flight v2 task behavior, --refreeze, env escape — RT3-F8)
- templates/spec-template.md — 5-column card scaffold with differentiated
  placeholders (`pros…` / `activates…`) plus one filled example row; the
  current bullet-format D-NN section is inconsistent with the v2 floor's
  table requirement and is fixed while touching (RT2-E10)
- test/sections/T73-gate-evidence.test.sh — fixtures: pass / missing-column
  fail / v2-grandfather pass / lazy-freeze stamp / stamp=99 fail-closed /
  Pros-copy fail
- test/sections/T17-semantic-engine.test.sh, T22-map-gate-impact.test.sh,
  T31-map-gate.test.sh, T33-map-manifest.test.sh — fixture cards updated to
  the 5-column contract (RT1-F1: real commit-think chains under the v3 floor)

Out of scope: gate content sniffing, plain-line artifacts, CLI locale overhaul,
Cons/Risks re-split, seeded-asset lifecycle ceremony beyond existing setup paths.

## 6. Deferred Ideas

- Explicit floor-upgrade path (a stamp-2 state whose cards were rewritten to
  v3 has no upgrade route) — defer until a real need appears (RT2-E1 note).
- Red-team battery question targeting weak Activates cells — only if recurrence
  evidence appears (D-32 escalation clause).
- Hard two-question dig floor — only if digs observably stop at the instruction
  line floor (D-33 condition).
- Risk-realization review consuming a re-split risk column (D-37 condition).

## 7. Red Team

### Round 1 (MISUSE) — dispositioned 2026-10-28

| ID | Finding | Disposition |
|:--|:--|:--|
| RT1-F1 | T17/T22/T31/T33 real commit-think fixtures break under v3 floor | ACCEPT — scope + invariant: freeze floor == stamp version |
| RT1-F2 | unknown stamp version fails open (stale CLI, vacuous pass) | ACCEPT — `spec-gate-version-unknown` fail-closed + fixture |
| RT1-F3 | lazy-freeze path never stamps (permanent floor bypass) | ACCEPT — lazy-freeze stamps when unset + fixture |
| RT1-F4 | re-freeze upgrades stamp → retroactive prosecution of old cards | ACCEPT (design altered) — first-freeze-only stamping instead of init-time stamping; keeps the P15 authoring-time semantics without the trap (superseded again by RT2-E1 content-era probing) |
| RT1-F5 | Activates quality all text discipline | PARTIAL — non-empty + not-Pros-identical are structural, accepted into gate; semantic consumer-naming stays with judgment layers (D-32 ruling against pattern sniffing) |
| RT1-F6 | exemplar narratives = AI-process artifacts in seeded assets | ACCEPT — de-identified rewrite + mechanized grep |
| RT1-F7 | spec-with-redteam.md teaches the dead 4+1 format | ACCEPT — scope addition |
| RT1-F8 | deepen "new facts" unauditable | ACCEPT — `new facts:` line convention (transcript-observable) |
| RT1-F9 | plain narration zero verification surface | PARTIAL — T1 verification captures a dogfood transcript excerpt as truth evidence artifact; no new machinery |
| RT1-F10 | Activates check unpinned table in multi-table sections | ACCEPT — E-7 supersedes: every Option-headed pipe table in the section |

### Round 2 (EDGE) — dispositioned 2026-10-28

| ID | Finding | Disposition |
|:--|:--|:--|
| RT1-F4 re-attack | first-freeze CLI stamp prosecutes old-authored specs (crash-upgrade-resume; legacy lazy; re-freeze floor dispatch missing) | FORCED-ACCEPT — reasoning disproven by three counter-examples; superseded by E-1 content-era probing |
| RT1-F2 residue | stale CLI vacuous-pass not closable by new code | ACCEPT — folded into E-5: STATE_SCHEMA_VERSION bump makes old CLIs die loudly |
| RT1-F10 residue | "same table object" has no code referent | ACCEPT — folded into E-7 |
| RT2-E1 | old content prosecuted at new-CLI first freeze (Critical) | ACCEPT — content-era probing stamp |
| RT2-E2 | legacy lazy-frozen fallback floor undefined | ACCEPT — uniform probing resolves (legacy content lands v2) |
| RT2-E3 | stamp value domain fail-open (0/1/"3"/null) | ACCEPT — domain {2..CLI_MAX} validation, fail-closed, validateState type check |
| RT2-E4 | re-freeze via commit think skips stages | ACCEPT — `--refreeze` flag + stage-monotonicity guard |
| RT2-E5 | fail-closed blocks legitimate downgrades with no escape | ACCEPT — remediation-naming fix text + GOS_SPEC_GATE_FLOOR_OVERRIDE (user-approved only) + schema bump |
| RT2-E6 | cell parsing undefined (`\|`, whitespace, column count, case) | ACCEPT — canonical parsing contract, no parse escape hatch |
| RT2-E7 | multi-table sections: which table (Minor) | ACCEPT — every Option-headed pipe table carries the header |
| RT2-E8 | superseding headings cross-credit cards | ACCEPT — prefix-anchored heading match |
| RT2-E9 | de-identification grep covers 2/5 banned classes | ACCEPT — add sha + ISO-date patterns; task names stay manual |
| RT2-E10 | scaffold placeholders fight the cell checks | ACCEPT — differentiated placeholders + filled example row; fix legacy bullet-format section |
| RT2-E11 | Chinese transcript artifact vs cjk-lint | ACCEPT — pinned untracked evidence path |
| RT2-E12 | freeze-floor invariant not wired into commit scope | ACCEPT — wording added; superseded by E-1 lifecycle |

Verified clean this round: locale key parity (T74-i18n), skills seed
consistency (single-tree symlink), stamp write surface (2 sites), fixture
git-dependency (T73 self-inits).

### Round 3 (COMPLETENESS) — dispositioned 2026-10-28

| ID | Finding | Disposition |
|:--|:--|:--|
| RT2-E4 re-attack | guard/error-code/discoverability unpinned (SLINK) | ACCEPT — named failure `stage-regression-blocked` in pre-mutation block; gate.cjs:573 fix text reworded; usage/CONTRACTS/locale lines; --refreeze = pure state op |
| RT2-E11 re-attack | "pinned path" had no path (SLINK) | ACCEPT — named .gos/task/<id>/evidence/t1-transcript.md; cad2c015 tension dispositioned as accepted known class |
| RT3-F1 | mixed-era weakest-link + silent downgrade | ACCEPT — freezer prints stamped version + failing-table count; supersede guidance requires rewriting copied legacy cards |
| RT3-F2 | probe/gate not forced to one implementation | ACCEPT — single floor registry export, both callers, no re-implementation |
| RT3-F3 | stamp-absent-at-gate undefined; legacy frozen population unrecoverable | ACCEPT — lazy probe at gate with same registry + --refreeze as the persisting path |
| RT3-F4 | rescue dead-end + --refreeze behavior hollow | ACCEPT — folded into E-4 re-attack row |
| RT3-F5 | grep scope contradicts teaching examples | ACCEPT — narrowed to deep-dig-cases.md; exempt-marker for teaching examples |
| RT3-F6 | evidence path unnamed | ACCEPT — folded into E-11 re-attack row |
| RT3-F7 | deferred triggers have no evidence channel | PARTIAL — deepen escalation evidence channel = concerns entries citing transcripts (`new facts:` lines make transcripts greppable, 7b0c1d6a precedent); REJECT-with-facts on .gos/logs instrumentation: deepen rounds are dialogue with no CLI hook, and new logging machinery contradicts the user's anti-bureaucracy ruling (2026-10-28) |
| RT3-F8 | CHANGELOG/upgrade comms missing | ACCEPT — scope adds CHANGELOG entry + upgrade note |
| RT3-F9 | scope pointer names wrong file | ACCEPT — instructions source is bin/lib/nav/status.cjs |
| RT3-F10 | reference path form + anchor stability unpinned | ACCEPT — repo-root-relative paths; §Decision Card anchor pinned |
| RT3-F11 | D-36 negative half unverified (inconsistent with D-38) | ACCEPT — PARTIAL recorded: negative constraint is judgment-layer verified, T1 proves the positive half |
| RT3-F12 | column-count reference frame + two-column tables | ACCEPT — row count vs own header count; card table defined (Option+Premise header), Option|Note tables exempt |

Verified clean this round: no generated-view overwrite surface (views.cjs
untouched, static-master files only), reference integrity of the three live
card-format files, exemplar three-way consumer wiring already promised,
schema bump closes stale-CLI vacuous-pass, census/package coverage for the new
examples file.
