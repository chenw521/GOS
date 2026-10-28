# Per-Gray-Area Dialogue Protocol

## Core Rule

**One question per message.** Present ONE decision point, wait for response,
then move to next. Never batch unrelated decisions.

## Decision Card (mandatory contract — P15 )

Every gray area is presented as a **decision card** — a symmetric options
table plus the rejected side made explicit. A decision without shown
alternatives is a model preference, not a decision. The card is also the
spec-gate structural floor (gate + THINK commit enforce it; every spec is
held to the floor of the era its content was frozen in).

**Dig before each card.** Before presenting the first card of a session,
read `skills/gos-think/examples/deep-dig-cases.md`. Before every card, dig
per domain — at minimum *who consumes this decision's output* and *what
real data says* — as a starting point, never a stopping point.

### Card template

```
D-NN: <one-line question>

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| <A> | when this holds… | … | … | <the consumer this option turns on> |
| <B> | when this holds… | … | … | … |
| <C> | when this holds… | … | … | … |

why-not: <B> — <reason>; <C> — <reason>
recommendation: <A> — conditional: if <premise X> then A; if <premise Y> then B
deepen: any option — ask for another dig round
```

Rules:
- **≥2 option rows**, first column = the option token (a short name usable
  in why-not lines).
- Options are **symmetric**: every option gets premise/pros/cons/activates
  — all five columns filled. An option that only lists cons while the
  favorite gets a full narrative is advocacy, not a card.
- **Cons merges the former Cons+Risks** columns: state certain costs
  plainly ("one extra round"), carry hazards in wording ("may drift",
  "could land late"). Never re-split into a separate risks column.
- The **Activates** cell names the consumer or surface this option would
  turn on — a concrete downstream artifact, command, file, or person.
  Pros states the benefit; Activates states who or what consumes the
  decision. They are different answers.
- `why-not:` (English-canonical marker) names the rejected option token(s)
  and the reason. Never omit it.
- The recommendation is **conditional** ("if you prioritize X → A; if Y →
  B"), never bare preference. A single unconditional pick must name the
  premise it stands on.
- Every card closes with the **deepen tail line** — `deepen: any option —
  ask for another dig round` — right after the recommendation.
- The card lives in the spec's own `## D-NN …` section (any heading whose
  text contains the id). Fenced-code examples and
  `<!-- gos:spec-gate:exempt -->` lines are excluded from the gate scan —
  use exempt only for illustrative examples, never for the real card.

### Rendered example

```
D-NN: card quality — teach a contract, or gate alone?

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| Skill contract + thin gate | cards are habit-forming; a gate must stay cheap | consistent + enforceable | floor is structural only — weak cards may still pass | dialogue-protocol.md card contract + the gate's table scan |
| Gate-only (no contract) | enforcement drives quality | automatic | boxes without judgment — could turn into cargo-cult tables | the gate scan alone, with no teachable format behind it |
| Contract-only | quality needs culture | honest | unenforceable — wording may drift silently | protocol text that nothing enforces |
| Review-only | humans judge best | flexible | late and non-blocking — defects could land before anyone reads them | reviewer attention, at read time only |

why-not: Gate-only — structural boxes can be cargo-culted; Contract-only —
has no teeth; Review-only — defects land before anyone reads them
recommendation: Skill contract + thin gate — conditional: the floor
(enforcement) exists BECAUSE the contract (format) is teachable; if gate
runs prove noisy, thin the floor, keep the contract
deepen: any option — ask for another dig round
```

### Deepen contract

The card-tail line is a standing offer of another dig round. When the
user takes it, the reply opens with a `new facts:` line listing the
increment in the exemplar form shown in
`skills/gos-think/examples/deep-dig-cases.md`; if the new facts move any
cell of the card, re-present the card. An empty increment closes the
port — answer "no new facts" and the card stands. Deepen rounds are
user-driven, exempt from the 3-follow-up cap, and uncapped; every round
must surface new facts to continue.

### Rendering contract

Decision cards render in the message body as real markdown tables — never
inside a structured tool payload. User responses are free text, and
composite replies ("deepen option B and also change the premise") are
first-class: handle each part in order. Structured tools (multiselect,
question dialogs) are reserved for card-free logistics — bare confirms
and gray-area multiselect. Any card-bearing interaction lives in the
message body.

### Plain-narration contract

Every reply is written plainly from the start: the reply itself is the
plain-language layer, never a translation appended after the fact. If a
point cannot be said plainly, it was not understood. Bans: unexplained
proper nouns, overused uncommon nouns, opaque abbreviations — introduce
any term in plain words at first use. Caliber anchor: Chinese at
middle-school education level, English at CET-4 level. Canonical markers
(`why-not:`, `recommendation:`, `deepen:`, `new facts:`, option tokens)
stay where structure requires them, grounded by surrounding plain prose.

### Superseding legacy cards

When copying or superseding a card written under an older contract era
(for example a four-column card with a separate Risks column), rewrite it
to the current five-column contract instead of dragging the old shape
forward. The spec gate enforces the floor of the era the content was
frozen in; new and copied cards always use the current contract.

## Dialogue Flow per Gray Area

```
Turn 1: Present card — options + recommendation + deepen line
  → User picks option, proposes alternative, asks to deepen, or says "you decide"

Turn 2 (if needed): Follow-up on user's choice
  → Only if the choice opens a sub-decision

Turn 3 (if needed): Final clarification
  → Max 3 follow-ups per area — then decide and move on
  → Deepen rounds run outside this cap (user-driven, need new facts)

Record D-NN → Update state.json checkpoint → Next area
```

## Handling User Responses

| User says | Action |
|:---|:---|
| Picks an option | Record as D-NN with their choice |
| "You decide" / "whatever works" | AI picks best option, records D-NN with note "AI-decided (user deferred)" |
| Proposes alternative | Evaluate feasibility → if viable, record as D-NN |
| "Tell me more about X" | Provide explanation, then re-ask the question |
| "deepen <option>" / "dig more on X" | Run a deepen round — open with `new facts:`, re-present the card if the facts changed it; "no new facts" closes the port |
| "say it plainly" / "plain rephrase" | Re-tell the same content within the plain-narration contract — same facts, same structure, no new layers |
| "Skip this" | Record as deferred, add to Deferred Ideas |
| Changes earlier decision | Go back, update the earlier D-NN, check downstream impact |

## When to Ask Follow-Ups

Ask a follow-up ONLY when:
1. The user's choice opens a necessary sub-decision (e.g., "You chose JWT → where to store it?")
2. The user's answer is ambiguous (e.g., "something secure" → "httpOnly cookie or server-side session?")

Do NOT ask follow-ups when:
1. The user's choice is clear and complete
2. The sub-decision can be reasonably defaulted
3. You've already asked 3 follow-ups (stop, record, move on)

Deepen rounds do not count against the cap: they answer user requests,
open with `new facts:`, and continue only while new facts appear.

## Checkpoint Protocol

After each gray area is resolved:
```bash
# Update state.json with new D-NN
# This enables crash recovery mid-THINK
```

If session crashes during THINK:
- Resume reads state.json
- Shows "Areas resolved: , . Remaining: [list]"
- Asks "Continue from Area C?"

## Lv4 Adaptation

For Lv4 with many gray areas (8-20):
- Group related areas into **themes** (e.g., "Auth theme" = session + token + password)
- Present themes as multiSelect first
- Within each theme, still one-decision-per-message
- After each theme, offer break: "Theme resolved. Take a break or continue?"
