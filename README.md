# GOS — Get Organized System

[English](README.md) | [简体中文](README.zh-CN.md)

[![CI](https://github.com/chenw521/GOS/actions/workflows/ci.yml/badge.svg)](https://github.com/chenw521/GOS/actions/workflows/ci.yml)
> [!NOTE]
> Not yet published — GOS is being polished before its first release
> (private beta on GitHub Packages or a direct public-npm launch; the
> decision comes after polishing). The public-npm name is reserved.
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

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

GOS is one system that handles all three — it absorbs the best of
[Superpowers](https://github.com/obra/superpowers) (process discipline),
GSD (project machinery) and OpenSpec (artifact lifecycle) into a single
zero-configuration workflow with a deterministic CLI underneath.

## Evidence

- **Self-hosting**: GOS is developed *with* GOS. The repo itself runs as a Lv4
  project — 20+ tasks/phases shipped through the full pipeline
  (THINK → PLAN → BUILD → REVIEW → VERIFY → SHIP), 30 project lessons accumulated,
  every release since v0.11 traceable to its decisions and verified truths. The
  regression suite — 64 section suites, 1500+ live assertions — is the CI spine.
- **Benchmark in progress**: an external task-suite benchmark is being rebuilt
  against current versions; earlier runs were retired with the versions they
  measured. Numbers will be published when a defensible methodology holds.

## How it works

### The baseline ring — always on, even for a typo

```
INTENT (align) → [adaptive middle] → VERIFY (prove) → TRACE (record)
```

### Adaptive routing — you never pay for what you don't use

| Level | Task | Flow |
|:---|:---|:---|
| Lv0 | typo, comment | direct execution |
| Lv1 | small bug | BUILD → VERIFY |
| Lv2 | clear small feature | THINK → BUILD → VERIFY |
| Lv3 | new feature | THINK → PLAN → BUILD → REVIEW → VERIFY → SHIP |
| Lv4 | large project | phase lifecycle: claim → full Lv3 → archive → next |

The agent recommends a level; you can override in one sentence.

### Three layers, one system

| Layer | Levels | DNA | Owns |
|:---|:---|:---|:---|
| Engineer | Lv0–Lv2 | Superpowers discipline | direct execution, TDD, systematic debugging, small builds in waves |
| Designer | Lv3 | OpenSpec lifecycle | THINK → PLAN → BUILD → REVIEW → VERIFY → SHIP with gated artifacts |
| Chief Designer | Lv4 | GSD project machinery | PROJECT/ROADMAP/DECISIONS lifecycle, phase claim → full Lv3 → archive |

### The deterministic layer — what makes it stick

A zero-dependency Node CLI (`gos`, Node ≥ 20) turns workflow promises into
mechanical facts:

- **Hard gates**: `gos gate all` exits 1 on uncovered decisions, unverified truths,
  undeclared file diffs, spec-hash drift. Skills route on these verdicts.
- **Filesystem fallback**: "it's done" is rejected unless the artifact exists on disk;
  verified truths require `{command, output, artifact}` evidence — `--replay` mode
  re-executes the command and takes the excerpt from *real* stdout.
- **Semantic layer**: plan Covers ↔ decisions exact bidirectional matching; diff-hit
  checks (declared Files ⊇ actual diff); fn-level call-graph impact closure
  (`gos map closure`) tells you what your change co-determines *before* tests run.
- **Memory that survives sessions**: typed lessons as tracked JSON truth
  (`.gos/lessons.json` — audit-chained, tamper-evident; the markdown view is
  regenerated, hand edits are overwritten by design) — project lessons persist
  forever, model-type lessons auto-expire +90d; decision chains with supersede
  tracking, cross-session `gos resume`.
- **First-language clarity**: gate rejections print what happened / why it
  matters / the exact fix command (`{code, verdict, evidence, fix}` — machine
  consumers get the same objects from `gate --json`), and the CLI speaks en or
  zh-CN (`gos setup --lang zh-CN`, or `GOS_LANG=zh` per run).

### Adversarial by default

THINK and PLAN outputs are attacked by fresh-context Red Team rounds (heterogeneous
model when staffed). Every finding needs a disposition — ACCEPT / PARTIAL /
REJECT-with-facts / DEFER. Rubber-stamping is a process violation, not a style choice.

### Lv4 phase lifecycle (for multi-week projects)

Phases are claimed from a roadmap, run a full Lv3 inside, and archive back into
`project.json` (single source of truth) with rendered markdown views. Real-world
friction is handled explicitly: out-of-order completion is legal (prev-done gate),
deliberately deferred phases get a first-class `parked` state that stays visible
as milestone debt — nothing silently disappears.

## Quick start

### Greenfield — three steps from zero

```bash
npm i -g @chenw521/gos        # from the public npm registry
# pre-publish alternative (works today, tracks main):
# npm i -g github:chenw521/GOS
gos setup
```

> ⚠️ **Install the right package.** The package is **`@chenw521/gos`** —
> the binary it provides is `gos`. On the public npm registry an
> **unrelated third-party** package named `gos` already exists; installing
> that one will not give you GOS.

macOS / Linux / Windows (junctions where symlinks need elevation). Node ≥ 20.
Restart your AI assistant and ask it *"list your gos skills"*. Then just describe a
task — GOS auto-activates and recommends a level:

```
Use GOS to build a user-auth feature        # or just: fix this bug for me
```

Type `gos` (no arguments) any time for status + what's next.

### Brownfield — adopting an existing repository

Bringing GOS into a repo that already has history, configs and files of its
own? `gos brownfield` probes every relevant path, classifies conflicts, and
seeds only what's missing — adoption, not takeover:

```bash
gos brownfield          # adoption report (--json for machine output)
```

```
brownfield adoption report — '/path/to/repo'
core.hooksPath: unset — seeded hooks are dormant (git reads .git/hooks/; GOS never writes .git/hooks/ or git config)
assets:
  created            hooks/commit-msg [inactive]
  report_only        AGENTS.md
remediation steps:
  1. hooks/commit-msg: run gos setup --commitlint
  2. AGENTS.md: run gos brownfield --print-agents-skeleton
```

What it never does: never overwrites an existing file (explicit
`gos brownfield --overwrite <asset>` only — user-owned hooks still refuse);
never writes AGENTS.md / CLAUDE.md / GEMINI.md (`--print-agents-skeleton`
prints a starter skeleton to stdout); seeded hooks stay **dormant** until
`gos setup --commitlint`; the template bundle still arrives via
`gos init git`, not here. Terminology note: "brownfield" here means *adopting
GOS into an existing repo* — unrelated to the decision-import "brownfield
import" used elsewhere in GOS history.

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

<details>
<summary>More CLI surfaces</summary>

```bash
gos gate semantic                 # bidirectional coverage + diff-hit + impact closure
gos map closure <file> --semantic # what your change co-determines (fn call-graph)
gos lessons add --type project "..." # repo memory that survives sessions
gos truth verify T1 --replay      # evidence from real stdout, not claims
gos render                        # regenerate DECISIONS/ROADMAP/REQUIREMENTS views
gos setup --local                 # dev mode: symlink from a git checkout
gos teardown                      # remove skill links
```

</details>

## When to use GOS / when not to

| Use GOS when... | Prefer something else when... |
|:---|:---|
| You run mid-tier/cheap models for daily tasks — they need the exoskeleton | You need UAT/security/UI phase machinery and multi-repo workstreams out of the box → **GSD** |
| Your task sizes are mixed (typos → features) and heavy flow on small tasks annoys you | Your spec IS the deliverable (contract-first, compliance) → **OpenSpec** |
| You want cross-task memory (lessons, decisions, verified truths) | You fully trust the model and want zero governance → plain skills (**Superpowers**) |
| Flagship + big project: you want it challenged, not just managed | |

GOS is a fusion layer, not a replacement: if Superpowers is installed, `gos-build`
auto-activates its tactical skills (TDD, debugging, parallel agents); without it,
GOS runs standalone.

## Project structure

```
GOS/
├── bin/gos.cjs          # zero-dep* CLI: hard gates, semantic layer, atomic commits
│                        #   (*single dependency: acorn, for the AST call-graph)
├── skills/              # 8 thin skills (<55 lines: routing table + HARD-GATE) + lazy refs
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

## Sources & status

Built on systematic analysis of [Superpowers](https://github.com/obra/superpowers)
(v5.0.6), GSD (v1.38.5) and OpenSpec (v1.2.0) — distilled into GOS's
three-layer architecture rather than carried over wholesale.

| Milestone | Status |
|:---|:---|
| v0.1–v0.2 skills + templates + adapters | ✅ |
| Deterministic CLI layer (gates, semantic checks, truth evidence) | ✅ |
| Edge-network codemap 2.0 (fn-level call graph, impact closure) | ✅ |
| Lv4 phase lifecycle, dogfooded through v0.11→v0.15 | ✅ |
| npm distribution (GitHub Packages beta → public npm at launch) + CI | ongoing |
| v1.0 public release | 📋 |

## CLI reference

<!-- gos:core-shortlist begin -->
- `gos` (no args) — status + what's next (zero-memorization entry)
- `gos init <level> "<intent>"` — start task
- `gos commit <stage>` — atomic commit + stage advance
- `gos gate all` — hard gates (exit 1 on failure)
- `gos context <stage>` — pre-computed context JSON
- `gos resume` — cross-session resume summary
- `gos instructions <stage>` — stage-by-stage guidance
- `gos phase <sub>` — Lv4 phase lifecycle
- `gos decision <sub>` — record/amend decisions
- `gos help [--json]` — full capability discovery

Full capability: `gos help [--json]`
<!-- gos:core-shortlist end -->

## Community

- **Contributing** — read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR
  (local-green-equals-CI-green command list, changelog duty, AI-code disclosure).
- **Changelog** — [CHANGELOG.md](CHANGELOG.md) (Keep a Changelog format; earlier
  history in `git log`).
- **Bugs & feature requests** — [issue forms](https://github.com/chenw521/GOS/issues/new/choose)
  (bug reports carry AI assistant / model / `gos --version` fields).

## License

[MIT](LICENSE)
