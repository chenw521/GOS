# GOS — Get Organized System

[English](README.md) | [简体中文](README.zh-CN.md)

<p align="center">
  <img src="assets/gos-hero.svg" alt="GOS — Get Organized System: hard gates, verified truths, red-team challenge, full-auto loop" width="100%">
</p>

<p align="center">

[![CI](https://github.com/chenw521/GOS/actions/workflows/ci.yml/badge.svg)](https://github.com/chenw521/GOS/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Release](https://img.shields.io/badge/release-v1.0.0-blue.svg)](https://github.com/chenw521/GOS/releases/tag/v1.0.0)

</p>

> **A deterministic execution layer and adaptive workflow for AI coding agents.**
> Small tasks pass free; big projects get full governance with adversarial challenge.
> Mid-tier models get an exoskeleton they can't skip; flagship models get a challenger they can't charm.

## Why GOS exists

AI coding agents fail in two opposite ways:

- **Mid-tier models** (flash-class, open-source): they skip steps, claim "done" without
  evidence, forget context between sessions, and hallucinate commands. Telling them to
  "be careful" doesn't work — they need **hard gates** (exit 1), **filesystem evidence**
  (can't fake), and **pre-computed next steps** (can't get lost).
- **Flagship models**: they don't need more rules — they need to be **challenged**.
  Spec review by the same model that wrote the spec finds nothing. GOS dispatches
  fresh-context adversarial attackers (a *different* model when available) until a
  round comes back empty.
- **Everyone**: heavy process on a typo fix is a tax; zero process on a feature is a
  gamble. Process weight must scale with task size.

GOS is one independent, zero-dependency system that covers all three — distilled
from systematic analysis of [Superpowers](https://github.com/obra/superpowers),
GSD and OpenSpec into a three-layer architecture with a deterministic CLI underneath.
GOS does not depend on, call out to, or require any of them.

## Evidence

- **Self-hosting**: GOS is developed *with* GOS. The repo itself runs as a Lv4
  project — 20+ tasks/phases shipped through the full pipeline
  (THINK → PLAN → BUILD → REVIEW → VERIFY → SHIP), 70+ project lessons
  accumulated, every release traceable to its decisions and verified truths.
  The regression suite — 106 section suites, 3300+ live assertions — is the
  CI spine.
- **Benchmark in progress**: an external task-suite benchmark is being rebuilt
  against current versions; earlier runs were retired with the versions they
  measured. Numbers will be published when a defensible methodology holds.

## How it works

### The baseline ring — always on, even for a typo

```
INTENT (align) → [adaptive middle] → VERIFY (prove) → TRACE (record)
```

### Adaptive routing — pay only for what the task needs

| Level | Task | Flow |
|:---|:---|:---|
| Lv0 | typo, comment | direct execution |
| Lv1 | small bug | BUILD → VERIFY |
| Lv2 | clear small feature | THINK → BUILD → VERIFY |
| Lv3 | new feature | THINK → PLAN → BUILD → REVIEW → VERIFY → SHIP |
| Lv4 | large project | phase lifecycle: claim → full Lv3 → archive → next |

The agent recommends a level; you can override in one sentence.

### Three layers, one system

| Layer | Levels | Owns |
|:---|:---|:---|
| Engineer | Lv0–Lv2 | direct execution, TDD, systematic debugging, small builds in waves |
| Designer | Lv3 | THINK → PLAN → BUILD → REVIEW → VERIFY → SHIP with gated artifacts |
| Chief Designer | Lv4 | PROJECT/ROADMAP/DECISIONS lifecycle, phase claim → full Lv3 → archive |

### The deterministic layer — what makes it stick

A zero-dependency Node CLI (`gos`, Node ≥ 20) turns workflow promises into
mechanical facts:

- **Hard gates**: `gos gate all` exits 1 on uncovered decisions, unverified
  truths, undeclared file diffs, spec-hash drift — skills route on these verdicts.
- **Filesystem fallback**: "it's done" is rejected unless the artifact exists on
  disk; verified truths require `{command, output, artifact}` evidence and
  `--replay` re-executes the command against *real* stdout.
- **Semantic layer**: plan↔decision bidirectional coverage, diff-hit checks,
  and fn-level call-graph impact closure (`gos map closure`) that tells you
  what your change co-determines *before* tests run.
- **Memory that survives sessions**: audit-chained lessons as tracked JSON
  truth, decision chains with supersede tracking, cross-session `gos resume`.

### Adversarial by default

THINK and PLAN outputs are attacked by fresh-context Red Team rounds (heterogeneous
model when staffed). Every finding needs a disposition — ACCEPT / PARTIAL /
REJECT-with-facts / DEFER. Rubber-stamping is a process violation, not a style choice.

### Lv4 phase lifecycle (for multi-week projects)

Phases are claimed from a roadmap, run a full Lv3 inside, and archive back into
`project.json` (single source of truth) with rendered markdown views. Out-of-order
completion is legal (prev-done gate); deliberately deferred phases get a first-class
`parked` state that stays visible as milestone debt — nothing silently disappears.

## Full-auto mode — `gos auto`

Full-auto removes the "next session, please" tax: a runner drives the active
task through its stages, each stage executed in a **fresh spawned session**
(context never rots), advancing until **SHIP** — where the human regains
control. Hard gates, decision audit and red-team challenge all stay on; only
the stage-boundary handoffs are automated.

```bash
gos auto on                     # enable (config-only): profile, breaker N/K/B, timeouts
gos auto status                 # mode, profile, hardening tier, host matrix, counters, breaker
gos auto run                    # drive the active task (fresh session per stage)
gos auto off                    # disable (--purge also removes the machine-local store)
gos auto disposition <runId> --reason "<text>"   # human verdict on a red/unknown CI run
```

`run` requires an active non-SHIP task (the error guides to `gos init`) and
refuses a main checkout — the loop runs on an `auto/<task-id>` work branch,
so landing on main still goes through a pull request.

### Machine-local trust store

Auto state (mode, profile, breaker counters, approval stamps, dispositions,
run lock) lives in a machine-local store under
`${XDG_DATA_HOME:-~/.local/share}/gos/<repo-id>/` — never committed, never
inherited by teammates. Tracked repo state carries **hashes and counts only**
(no session ids, model names or output tails). A missing or corrupt store fails
closed into a paused state with guidance — never a silent fresh start.

### Delegation with evidence

Stage approvals route three ways: **mechanical** gates pass automatically;
**delegated** THINK/PLAN stages commit a PENDING record in-spawn and the
runner ratifies it from outside against captured-stream stamps. THINK
delegation requires a red-team pass from a **separate read-only spawn**,
passing **twice with zero findings**; any findings escalate to held. Archive
and push stay human.

### The breaker — what stops a runaway loop

| Layer | Default | Trips when |
|:--|:--|:--|
| N — consecutive failures | 3 | one stage fails N times in a row |
| K — stage visits | 5 | the loop re-enters stages K times (ping-pong) |
| B — spawned sessions | 30 | the spawn budget is exhausted |

A trip **pauses** auto — configuration is kept, never auto-resumed. Failures
carry a class tag (task / env / auth / timeout) so environment breakage never
masquerades as task failure, and external mutations pause with a report
instead of a failure count.

### Sandbox tiers — honest about limits

Spawned sessions run under a capability profile — `restricted` (default),
`workspace` or `full` as explicit opt-ins. With bubblewrap present the
launcher builds a kernel sandbox; without one the tier degrades honestly to
**lexical** — and status says so:

- **Network stays open.** There is no egress sandbox.
- **Model-provider auth stays readable by design** — the spawned session has
  to call the model.
- **Credential masking covers the masked paths only**; anything outside that
  list is not hidden.
- **The lexical tier is depth, not redundancy** — an injected deny config
  plus an escape detector, not a kernel boundary.

### Delivery — from SHIP to main

When the GitHub delivery adapter probes green (origin + `gh` auth + CI
presence), the loop continues past SHIP: push the work branch, open a PR with
a runner-rendered body (worker-controlled strings appear only as quoted,
labeled blocks), run the squash-subject lint before merge, then watch CI — a
timeout lands in disposition-unknown awaiting a human, a red run stops the
loop. Repo git metadata is treated as untrusted: the remote is pinned at
probe time and re-verified before every privileged git call. No adapter? The
loop ends cleanly at SHIP and delivery stays fully manual.

## Quick start

### Greenfield — three steps from zero

```bash
npm i -g github:chenw521/GOS   # straight from GitHub, tracks main
# npm i -g @chenw521/gos       # registry drop pending — not live yet
gos setup
```

> ⚠️ **Install the right package.** The package is **`@chenw521/gos`** —
> the binary it provides is `gos`. On the public npm registry an
> **unrelated third-party** package named `gos` already exists; installing
> that one will not give you GOS.

macOS / Linux / Windows (junctions where symlinks need elevation). Node ≥ 20.
Restart your AI assistant and ask it *"list your gos skills"*. Then just
describe a task — GOS auto-activates and recommends a level. Type `gos` (no
arguments) any time for status + what's next.

### Brownfield — adopting an existing repository

Bringing GOS into a repo that already has history, configs and files of its
own? `gos brownfield` probes every relevant path, classifies conflicts, and
seeds only what's missing — adoption, not takeover. It never overwrites an
existing file (`--overwrite <asset>` is explicit; user-owned hooks still
refuse), never writes AGENTS.md/CLAUDE.md/GEMINI.md, and seeded hooks stay
**dormant** until `gos setup --commitlint`.

```bash
gos brownfield          # adoption report (--json for machine output)
```

## The CLI surface that matters

Ten commands cover daily traffic; two small tables cover the rest that
matters per audience. The full command surface — 50+ commands — lives in
`gos help` (rendered from the COMMANDS registry in
[`bin/gos.cjs`](bin/gos.cjs), the single source of truth; `gos help --json`
for machines).

### The core ten

<!-- gos:core-shortlist begin -->
- `gos` (no args) — status + what's next (zero-memorization entry)
- `gos init <level> "<intent>"` — start task
- `gos commit <stage>` — atomic commit + stage advance
- `gos gate all` — hard gates (exit 1 on failure)
- `gos context <stage>` — pre-computed context JSON
- `gos resume` — cross-session resume summary
- `gos instructions <stage>` — stage-by-step guidance
- `gos phase <sub>` — Lv4 phase lifecycle
- `gos decision <sub>` — record/amend decisions
- `gos help [--json]` — full capability discovery

Full capability: `gos help [--json]`
<!-- gos:core-shortlist end -->

### For humans — beyond the core

| Command | What it does |
|:--|:--|
| `gos auto on / run / status` | full-auto loop control |
| `gos brownfield` | adopt GOS into an existing repo |
| `gos setup` / `gos doctor` | install skills / diagnose the installation |

### For agents — beyond the core

| Command | What it does |
|:--|:--|
| `gos next` | what to do right now |
| `gos map closure <file> --semantic` | what your change co-determines (fn call-graph) |
| `gos logs` | runtime audit ledgers (receipts / exemptions / audit) |
| `gos trace` | requirements → decisions → tasks → truths |

## When to use GOS / when not

| Use GOS when... | Think twice when... |
|:--|:--|
| You run mid-tier/cheap models for daily work — they need the exoskeleton | You fully trust the model and want zero governance on small personal scripts |
| Your task sizes are mixed (typos → features) and flat heavy flow annoys you | Every change is large and spec-first, with a compliance process already in place |
| You want cross-task memory: lessons, decisions, verified truths surviving sessions | You need a single-shot answer, not a workflow |
| Flagship + big project: you want the work challenged, not just managed | |

GOS is an independent implementation — it runs standalone, with no runtime
dependency on any other workflow tool.

## Project structure

```
GOS/
├── bin/gos.cjs          # zero-dep* CLI: hard gates, semantic layer, atomic commits
│                        #   (*single dependency: acorn, for the AST call-graph)
├── skills/              # 8 thin skills (routing table + HARD-GATE) + lazy refs
│   ├── gos-router/      # entry: assess → recommend level → chain stages
│   ├── gos-project/     # Lv4 chief designer: PROJECT/ROADMAP/DECISIONS lifecycle
│   ├── gos-think/       # per-gray-area dialogue + D-NN decisions + Red Team
│   ├── gos-plan/        # waves + Decision Coverage + Revision Loop
│   ├── gos-build/       # wave execution + TDD + aggregation protocol
│   ├── gos-review/      # two-phase: spec compliance → code quality
│   ├── gos-verify/      # one-truth-at-a-time + evidence or it didn't happen
│   └── gos-ship/        # change record + archive + cleanup scan
├── templates/           # spec / plan / verify / review / trace skeletons
├── .gos/                # workflow artifacts (project/ tracked; state.json local)
├── .opencode/ .codex/ .claude-plugin/   # platform adapters
└── AGENTS.md            # routing rules + tool mapping
```

## Milestones

Dates before 2026-10-08 are reconstructed from the local development ledger
(the public git history was rebuilt as snapshot commits at 1.0.0-dev).

| Date | Milestone |
|:--|:--|
| 2026-08 | v0.1–v0.2 — skills, templates, platform adapters |
| 2026-09 | Deterministic CLI layer — hard gates, semantic checks, truth evidence |
| 2026-09 | Lv4 phase lifecycle, dogfooded on this repository |
| 2026-10 | Edge-network codemap 2.0 — fn-level call graph, impact closure |
| 2026-10-29 | Full-auto mode — `gos auto` loop, breaker, sandboxed spawns, delivery |
| 2026-10-30 | v1.0.0 public release (GitHub) |
| pending | public npm registry drop (`@chenw521/gos`) |
| pending | external task-suite benchmark rebuild |

## Community

- **Contributing** — read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR
  (local-green-equals-CI-green command list, changelog duty, AI-code disclosure).
- **Changelog** — [CHANGELOG.md](CHANGELOG.md) (Keep a Changelog format; earlier
  history in `git log`).
- **Bugs & feature requests** — [issue forms](https://github.com/chenw521/GOS/issues/new/choose)
  (bug reports carry AI assistant / model / `gos --version` fields).

## License

[MIT](LICENSE)
