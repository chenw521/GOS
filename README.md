# GOS — Get Organized System

[English](README.md) | [简体中文](README.zh-CN.md)

[![CI](https://github.com/chenw521/GOS/actions/workflows/ci.yml/badge.svg)](https://github.com/chenw521/GOS/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Release](https://img.shields.io/badge/release-v1.0.0-blue.svg)](https://github.com/chenw521/GOS/releases/tag/v1.0.0)

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
(no session ids, model names or output tails); the repo-local ledger under
`.gos/logs/` is a debug mirror. A missing or corrupt store fails closed into
a paused state with guidance — never a silent fresh start. `gos resume`
reports auto mode (breaker first-line when tripped) but never auto-spawns,
and the auto family refuses to run inside its own spawned sessions
(`GOS_AUTO_SPAWNED` marker), so a working session cannot switch the loop
back on.

### Delegation with evidence

Stage approvals route three ways: **mechanical** gates pass automatically;
**delegated** THINK/PLAN stages commit a PENDING record in-spawn and the
runner ratifies it from outside against captured-stream stamps — an
unratified PENDING blocks the next stage advance. THINK delegation requires
a red-team pass from a **separate read-only spawn** whose prompt comes from
a runner-held template (never repo files), passing **twice with zero
findings**; any findings escalate to held. Archive and push stay human.

### The breaker — what stops a runaway loop

| Layer | Default | Trips when |
|:--|:--|:--|
| N — consecutive failures | 3 | one stage fails N times in a row |
| K — stage visits | 5 | the loop re-enters stages K times (ping-pong) |
| B — spawned sessions | 30 | the spawn budget is exhausted |

Floors are >=1 (fail-closed validation; override with `--max-retries`,
`--max-visits`, `--max-sessions` at `auto on`). A trip **pauses** auto —
configuration is kept, never auto-resumed; explicit `gos auto on` re-enables.
CI-watch timeouts route to disposition-unknown rather than the N layer (a
slow green is not bad work), and external mutations (human stage-back,
archive mid-loop, a concurrent supervised commit) pause with a report —
never a failure count. Failures carry a class tag (task / env / auth /
timeout) so environment breakage never masquerades as task failure.

### Sandbox tiers — honest about limits

Spawned sessions run under a capability profile — `restricted` (default),
`workspace` or `full` as explicit opt-ins (`full` additionally requires a
later explicit upgrade; the active profile prints first-line in status).
With bubblewrap present the launcher builds a kernel sandbox: tmpfs masks
are layered over the trust store, delivery credentials (gh/git/ssh/netrc),
the global git config and host state dirs, with mask-over-bind ordering so
a mask always wins over a later bind of the same path. Without a sandbox
engine the tier degrades honestly to **lexical** — and status says so:

- **Network stays open.** There is no egress sandbox; the launcher restricts
  filesystem reach, not network access.
- **Model-provider auth stays readable by design** — the spawned session has
  to call the model.
- **Credential masking covers the masked paths only** (trust store, gh /
  git / ssh / netrc, global git config, host state dirs); anything outside
  that list is not hidden.
- **The lexical tier is depth, not redundancy**: an injected deny config
  plus an escape detector add a second layer, not a kernel boundary.

### Delivery — from SHIP to main

When the GitHub delivery adapter probes green at `auto on` (origin + `gh`
auth + CI presence — the three-state result shows in `auto status`), the
loop continues past SHIP: push the work branch, open a PR with a
runner-rendered body (worker-controlled strings appear only as quoted,
labeled blocks), run the squash-subject lint before merge, then watch CI
for 45 minutes — a timeout lands in disposition-unknown awaiting a human
`gos auto disposition`, and a red run stops the loop for one. Repo git
metadata is treated as untrusted: the remote is pinned at probe time and
re-verified before every privileged git call, and any drift (remote swap,
planted hook) aborts into the breaker instead of pushing. No adapter? The
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
gos truth verify --replay # evidence from real stdout, not claims
gos track <path-under-.gos>       # atomic ignored->tracked flip (gitignore negation + census + manifest; rollback-safe)
gos track --knowledge             # preset: flip the .gos/codebase guide trio + born-at stamps
gos gap migrate                   # cure stage-back (auto) mirrors into the gap-history ledger
gos gap history                   # fail-closed view of the gap ledger (.gos/logs/gap-history.ndjson)
gos gap rewrite <G-id> --text "..." # rewrite a gap (language-boundary checked)
gos render                        # regenerate DECISIONS/ROADMAP/REQUIREMENTS views
gos setup --local                 # dev mode: symlink from a git checkout
gos teardown                      # remove skill links
gos auto on|off|status|run/disposition  # full-auto stage loop (see "Full-auto mode" above)
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

## Sources & status

Built on systematic analysis of [Superpowers](https://github.com/obra/superpowers)
(v5.0.6), GSD (v1.38.5) and OpenSpec (v1.2.0) — distilled into GOS's
three-layer architecture rather than carried over wholesale.

| Milestone | Status |
|:---|:---|
| v0.1–v0.2 skills + templates + adapters | ✅ |
| Deterministic CLI layer (gates, semantic checks, truth evidence) | ✅ |
| Edge-network codemap 2.0 (fn-level call graph, impact closure) | ✅ |
| Lv4 phase lifecycle, dogfooded through the self-hosted project | ✅ |
| v1.0 public release (GitHub, 2026-10-30) | ✅ |
| public npm registry drop (`@chenw521/gos`) | 📋 pending |
| External task-suite benchmark (rebuild in progress) | 📋 |

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
