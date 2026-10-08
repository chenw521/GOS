# Per-Gray-Area Dialogue Protocol

## Core Rule

**One question per message.** Present ONE decision point, wait for response,
then move to next. Never batch unrelated decisions.

## Decision Card (mandatory contract — P15 D-62)

Every gray area is presented as a **decision card** — a symmetric options
table plus the rejected side made explicit. A decision without shown
alternatives is a model preference, not a decision. The card is also the
spec-gate structural floor (gate + THINK commit enforce it on specs frozen
under post-P15 CLIs).

### Card template

```
D-NN: <one-line question>

| Option | Premise | Pros | Cons | Risks |
|:--|:--|:--|:--|:--|
| <A>  | when this holds… | … | … | … |
| <B>  | when this holds… | … | … | … |
| <C>  | when this holds… | … | … | … |

why-not: <B> — <reason>; <C> — <reason>
recommendation: <A> — conditional: if <premise X> then A; if <premise Y> then B
```

Rules:
- **≥2 option rows**, first column = the option token (a short name usable
  in why-not lines).
- Options are **symmetric**: every option gets premise/pros/cons/risks —
  an option that only lists cons while the favorite gets a full narrative
  is advocacy, not a card (this was FB-1).
- `why-not:` (English-canonical marker) names the rejected option token(s)
  and the reason. Never omit it.
- The recommendation is **conditional** ("if you prioritize X → A; if Y →
  B"), never bare preference. A single unconditional pick must name the
  premise it stands on.
- The card lives in the spec's own `## D-NN …` section (any heading whose
  text contains the id). Fenced-code examples and
  `<!-- gos:spec-gate:exempt -->` lines are excluded from the gate scan —
  use exempt only for illustrative examples, never for the real card.

### Rendered example

```
D-62: Decision card = skill contract + thin spec gate

| Option | Premise | Pros | Cons | Risks |
|:--|:--|:--|:--|:--|
| Skill contract + thin gate | cards are habit-forming; gate must stay cheap | consistent + enforceable | floor is structural only | weak cards pass |
| Gate-only (no contract) | enforcement drives quality | automatic | boxes without judgment | cargo-cult tables |
| Contract-only | quality needs culture | honest | unenforceable | drift |
| Review-only | humans judge best | flexible | late + non-blocking | process theater |

why-not: Gate-only — structural boxes can be cargo-culted; Contract-only —
has no teeth; Review-only — defects land before anyone reads them
recommendation: Skill contract + thin gate — conditional: the floor
(enforcement) exists BECAUSE the contract (format) is teachable; if gate
runs prove noisy, thin the floor, keep the contract
```

## Dialogue Flow per Gray Area

```
Turn 1: Present options + recommendation
  → User picks option, proposes alternative, or says "you decide"

Turn 2 (if needed): Follow-up on user's choice
  → Only if the choice opens a sub-decision

Turn 3 (if needed): Final clarification
  → Max 3 follow-ups per area — then decide and move on

Record D-NN → Update state.json checkpoint → Next area
```

## Handling User Responses

| User says | Action |
|:---|:---|
| Picks an option | Record as D-NN with their choice |
| "You decide" / "whatever works" | AI picks best option, records D-NN with note "AI-decided (user deferred)" |
| Proposes alternative | Evaluate feasibility → if viable, record as D-NN |
| "Tell me more about X" | Provide explanation, then re-ask the question |
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

## Checkpoint Protocol

After each gray area is resolved:
```bash
# Update state.json with new D-NN
# This enables crash recovery mid-THINK
```

If session crashes during THINK:
- Resume reads state.json
- Shows "Areas resolved: D-01, D-02. Remaining: [list]"
- Asks "Continue from Area C?"

## Lv4 Adaptation

For Lv4 with many gray areas (8-20):
- Group related areas into **themes** (e.g., "Auth theme" = session + token + password)
- Present themes as multiSelect first
- Within each theme, still one-decision-per-message
- After each theme, offer break: "Theme resolved. Take a break or continue?"
