---
name: gos-verify
description: "Use before claiming any task complete — evidence-based one-truth-at-a-time verification. Run gos gate all (exit 0 required). Classify gaps for Gap Closure. Iron Law: evidence before assertions."
---

# GOS VERIFY — Goal-Backward Verification (Baseline)

<HARD-GATE>
Law #1: Evidence before assertions. "Should" = lying. Run it, show output.
Law #2: One truth at a time. Never batch. Prevents rubber-stamping.
</HARD-GATE>

## Quick Start

```bash
gos instructions verify    # pending truths list + verification commands
gos gate semantic          # semantic layer: bidirectional coverage + diff-hit + artifacts
gos gate all               # hard gate: must exit 0 before SHIP
```

### impactClosure advisory lines (Phase 6 — read them, never ignore them)

`gate semantic` tail prints ONE of three states about diff dependents NOT covered by task Files:
- `impact closure: N diff dependents ... (advisory, regex-based, may be incomplete)` — N>0: your diff's blast radius exceeds declared task Files. The banner is ADVISORY (exit stays 0) and `impactClean` is NOT a pass verdict. Follow the `run: gos map closure <file> --print0` hint and judge coverage yourself.
- `impact closure: 0 uncovered dependents ...` — impactClean ≠ blast radius verified (regex-based scan; deletions/renames covered via dangling edges, dynamic imports never are).
- `impact closure vacuous (...)` — impactVacuous ≠ clean: nothing was computable (0 scannable sources or diff fully allowlisted).

### Semantic closure section (Phase D — consume it, qualified wording is part of the contract)

- `must-check set (regex-extracted ... NOT exhaustive ...)` — semantic dependents of your diff (calls/contracts/hand edges). Each line names a file + the edge family that links it. Read EVERY line: these files are co-responsible for your change's correctness.
- `must-run test sections (...)` — sections whose commands you touched (hunk→function→cmd mapping). If a section is absent from the last run, `bash test/run-sections.sh <section>` BEFORE claiming verification; the gate manifest check will FAIL on mismatch.
- `run-manifest stale` (gate all FAIL) — sections last ran against a different content tree. Re-run the suite; only use `gos gate --exempt <section> --reason "<why>"` (reason mandatory, ≥10 chars) when you can justify the exemption in your verify notes (one-shot, audited in .gos/logs/exemptions.log).
- Machine consumers: `gos map closure <path> --json` (strict envelope, byte-0 JSON) is the sole structured mode; `--print0` stays paths-only.


Record evidence via the command family — never hand-edit state.json:

```bash
gos truth add "what user can observe"                      # auto-numbered T-NN
gos truth verify --command '["bash","test/run-sections.sh"]' --replay --artifact test/out/ .log
gos truth verify --command "<cmd>" --excerpt "12 passed, 0 failed" --artifact test/out/ .log
```

- `--replay` executes the command (JSON argv) and takes the excerpt from REAL stdout — preferred; manual mode (`--command/--excerpt/--artifact` without `--replay`) marks the truth `manual:true` and gate prints a warning banner.
- evidence = `{command, output_excerpt, artifact_path}` three-element object; old string form is fail-closed rejected.


## Progressive Disclosure

| When | Do | Read for detail |
|:---|:---|:---|
| Entering VERIFY | `gos context verify` (pending truths JSON) | — |
| Want a real example | **Read `examples/verification-report.md` — copy its structure** | `examples/verification-report.md` |
| Truths verification | Present each truth ONE AT A TIME → show evidence → WAIT for yes/issue | — |
| Cold-start (Lv3+) | **RUN `scripts/detect-coldstart.sh`** first → test whatever it flags | — |
| Gap found | Classify: Minor→BUILD, Major→PLAN(Lv3+)/THINK(Lv2), Block→THINK | `reference/gap-classification.md` |
| All truths pass | `gos gate all` → must exit 0 | — |
| Exiting VERIFY | `gos commit verify` | — |

## State

**Read:** state.json (observable_truths)
**Write:** state.json (truths[].verified, truths[].evidence, gaps[])

## Exit Gate

`gos gate all` exits 0 (coverage + truths + requirements + custom gates).

## Anti-Rationalization (top 3)

| Excuse | Reality |
|:---|:---|
| "Tests should pass" | "Should" is not evidence. RUN THEM. |
| "All truths in one table is efficient" | Table = rubber-stamp. One at a time. |
| "I can verify without user" | AI evidence has blind spots. User confirms per truth. |
