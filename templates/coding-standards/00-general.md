# Coding Standards — General Principles (Book 0)

> Anchored set: Google Shell Style Guide (CC-BY 4.0) — https://google.github.io/styleguide/shellguide.html ·
> Airbnb JavaScript Style Guide (MIT) — https://github.com/airbnb/javascript ·
> Google JavaScript Style Guide (CC-BY 4.0) — https://google.github.io/styleguide/jsguide.html ·
> PEP 8 & PEP 257 (PSF License) — https://peps.python.org/pep-0008/ · https://peps.python.org/pep-0257/

This book governs how code is **written and commented** across the whole set.
The per-language books carry the anchored baseline rules; this one carries the
principles that apply to every file regardless of language.

## The Book Set

| Book | Anchored baseline | License of the anchor |
|:---|:---|:---|
| `00-general.md` | this file — GOS house layer | — |
| `shell.md` | Google Shell Style Guide | CC-BY 4.0 |
| `node.md` | Airbnb JS + Google JS + JSDoc | MIT / CC-BY 4.0 / Apache-2.0 |
| `python.md` | PEP 8 + PEP 257 | PSF License |

## 1. Comments: say what code cannot

A comment exists only to carry information the code itself cannot express.
Everything else is noise that future readers must skip — and noise accumulates
faster than signal.

**The judgment test.** For every comment you write or review, ask:

> *If I delete this comment, what does the reader lose?*

- **Nothing** → delete the comment.
- **Something** → keep it, and make sure it states that thing as tightly as possible.

### Forbidden comment patterns

❌ **Restating the code** (zero information):

```js
i++; // increment i
const timeoutMs = 5000; // timeout in milliseconds
```

❌ **AI conversational phrasing** — no assistant, reviewer, or author talks to
the reader through comments:

```js
// It is worth noting that this function returns null on empty input
// As per the requirement, we validate the input here
// Let's iterate over the items and process each one
// In this section, we will implement the retry logic
```

❌ **Process-decision talk** — which option was chosen, what the previous
version did, what changed recently:

```js
// per option B we retry twice instead of three times
// v2 switched to a connection pool (v1 opened one per request)
// this loop was rewritten for performance
```

Historical narrative belongs in **git blame and commit messages**, never in
comments. A comment that narrates history is wrong the day after the next
change.

❌ **Ticket and review anchors** — traceability IDs pointing at process tools:

```js
// [REVIEW Mn] fixed the off-by-one here
// T-nnn: handle the empty-list case
// TODO(JIRA-nnn): remove this after migration
```

Review findings, task IDs, and sprint references rot instantly; the code stays.
Link them from the issue tracker, the PR description, or the commit body.

The full banned family, named digit-free — every digit-bearing shape of these
is a trace artifact:

- bracket decision anchors: `[D-NN]`, `[REVIEW Mn]` (slash compounds stay parenthesized, see below)
- bare and parenthesized decision/requirement ids: `D-nn`, `R-nn`, `F-nn`,
  `(R-nn/F-nn)`
- wave and task ids: `Wn`, `Tn`, `Wn-Tn`
- dash compounds: `RTn-Fn`
- spec-section citations: `spec §n.n`, `§n.n`
- task-narrative phrases: this <phase|wave|task> <adds|ships|introduces> … —
  narrating the task in a comment instead of describing WHAT

**The rule: lineage lives in commit bodies and the CHANGELOG; comments keep
the WHAT.** A trace-free comment states a constraint, a contract, or a reason
the code cannot express — never which task, wave, or review produced it.

✅ **What a surviving comment looks like** — a constraint, a contract, or a
reason that the code cannot state:

```js
// Retries are capped at 2: the upstream API rate-limits at 3 failures/min.
// Must return null (not throw) on empty input — callers branch on null.
```

## 2. Comment density

- **File header: at most 5 lines.** One line of purpose, optionally one line
  of non-obvious scope. No copyright essays, no change logs, no author lists —
  git owns that.
- **Explain WHY, not WHAT.** Code already says what it does; comments must say
  why that choice was made or what external contract forces the shape.
- **No commented-out code.** Dead code in comments is the worst of both
  worlds: it rots silently and git already keeps every version ever written.
  Delete it; recover it from history if it ever comes back.
- **No ownerless TODOs.** A TODO must name an owner and an actionable next
  step (`// TODO(alice): switch to pooled clients once auth lands`). A bare
  `// TODO` is a permanent resident.

## 3. Precedence: this repo wins over the anchors

Each per-language book anchors its baseline in a public authoritative standard.
**When a rule in this set conflicts with the anchor standard, the rules in
this set win.** The anchors supply the default; the house layer tightens or
overrides. Anything not covered here falls back to the anchor standard, and
anything not covered there falls back to the language's own ecosystem norm.

## 4. Reading order

1. This book — always applies.
2. Your language's book — applies to every file in that language.
3. The anchor standard — fills every remaining gap.
