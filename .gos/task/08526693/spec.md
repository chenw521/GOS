# Spec — Enforce the artifact-path contract at truth-verify authoring time (Lv2, task 08526693)

Headline: the evidence `artifact_path` predicate that the state validator
applies at gate time becomes the same predicate `truth verify` applies at
authoring time, from one shared source, so the fresh-clone CI failure of
issue #57 becomes impossible to record in the first place.

## Context and problem

Issue #57: `truth verify` accepts any `--artifact` value; the validator
(`bin/lib/core/state.cjs`, `validateEvidenceObject`) exempts only
`ARTIFACT_LOCAL_ZONES = ['.gos/archive/', '.gos/logs/', '.gos/cache/']`
from its on-disk existence check. An artifact pointing at a machine-local
file outside those zones (observed: `.gos/concerns.md`) passes every local
gate and fails `gate all --audit` on a fresh CI checkout.

Two measured facts shape the design (session dig, 2026-11-09):

- Enforcement points already exist: `truth verify` calls
  `core.validateEvidenceObject` on both the replay path and the manual
  path — the defect is the weak predicate inside the validator
  (existsSync ∪ zone ⇒ any existing file passes), not a missing call.
- The historical artifact corpus is empty: zero `artifact_path` values
  across repo state, repo archives, and the dogfood store — tightening
  the predicate breaks nothing retroactively.

## Scope freeze

In scope:

- `bin/lib/core/state.cjs` — extract the artifact-path check into a
  reusable `artifactPathError(ap, repoRoot)` helper consumed by
  `validateEvidenceObject`; sharpen the predicate (below).
- `bin/lib/knowledge/truth.cjs` — one arg-parse-time early call of the
  shared helper for pre-existing artifact paths; usage/help text.
- `test/sections/T86-truth-replay-surface.test.sh` — behavior cases.

Out of scope: `bin/lib/task/commit.cjs` (commit-time enforcement was
weighed and rejected — outside the freeze and still a late failure), the
manual-mode help banner, any change to zone membership itself.

## Directive W1 — shared predicate, two-phase rejection (decision G1-A′)

`validateEvidenceObject`'s artifact branch becomes a call to
`artifactPathError(ap, repoRoot)`. Predicate, in order:

1. shape checks unchanged: relative, no `..`, no newlines;
2. zone paths (prefix match against the zones array, now hoisted next to
   the helper) pass without any filesystem or git probe;
3. non-zone paths require: present in the git index (`git ls-files
   --error-unmatch <path>`) AND an `lstat` regular file (symlinks
   rejected — B-18 precedent: a tracked symlink passes locally while its
   target is absent on fresh clones);
4. if the git probe itself errors (no `.git`, broken repo), degrade to
   the legacy predicate (existsSync only) — fail-open on environment
   failure, fail-closed on policy violation.

`truth verify` gains one arg-parse-time call of the same helper when the
artifact file already exists — a doomed pre-existing path dies before the
replay command executes (the 10-minute-suite blind spot). The existing
post-execution `validateEvidenceObject` call stays and now enforces the
same sharpened rule for command-generated artifacts. Rejection text names
both cures inline: stage the file (`git add <path>`) and re-run, or move
it under a machine-local zone; the zone list in the message renders from
the shared zones array, never a second literal.

The manual evidence path (decision G3) rides the same validator call it
already makes — no manual-specific branch, no fast-fail (manual executes
nothing). Usage lines gain a "(tracked or machine-local zone)" qualifier
(decision G2-A).

| Option | Premise | Pros | Cons | Activates |
| --- | --- | --- | --- | --- |
| shared validator predicate + early call (chosen) | the enforcement point already exists; drift was the disease | one source consumed by verify, gate, CLI; drift structurally impossible | gate tightens for legacy states (measured corpus: zero) | helper extraction + early call + T86 |
| predicate inside truth.cjs, zones exported | check lives at authoring | same authoring effect | two predicates can drift again — the #57 recurrence path | rejected |
| post-execution check only | single point | simplest | burns the replay cycle the fix exists to save | rejected |
| commit-time enforcement | checks the actual traveling tree | theoretically exactest | outside the frozen file list; still a late failure | rejected |

why-not: predicate inside truth.cjs — a second copy of the rule is a
second chance to drift; commit-time — late and out of scope.

## Observable truths

1. Recording evidence whose artifact path is outside the zones, not in
   the git index, and already on disk is rejected at argument-parse time
   — the replay command never executes — and the rejection text names
   both cures (git add and re-run, or move under a machine-local zone).
2. After `git add`, the same path records successfully; a zone path
   records without any git operation; a tracked symlink artifact is
   rejected as a non-regular file; a command-generated non-zone artifact
   is rejected after execution with the same guidance.
3. A state whose truth artifacts are zone paths or tracked regular files
   survives `gate all --audit` in a fresh clone (no .gitignore'd
   machine-local files), and the T86 section passes.

## Red-team dispositions (3 rounds, inline — no heterogeneous
resolve-model dispatch available in this session; announced fallback per
protocol)

- Round 1 — misuse: can an agent bypass the check by staging a symlink
  (git add link) so it enters the index while pointing at a machine-local
  file? Disposition ACCEPT with constraint: the lstat regular-file leg
  rejects indexed symlinks regardless of target (case 3 of the
  predicate), mirroring the B-18 receipt hardening.
- Round 2 — edge: what happens in sandboxes without git (T86 fixture
  always runs `git init`, but ad-hoc runs may not)? Disposition ACCEPT
  with constraint: git-probe failure degrades to the legacy predicate
  (case 4) — the check may under-enforce in a broken environment but
  never hard-dies on it.
- Round 3 — completeness: does the fix cover manual-mode evidence, and
  artifacts generated by the replay command itself? Disposition ACCEPT:
  manual mode already routes through the same validator call (decision
  G3); generated artifacts hit the post-execution call, and the error
  text teaches staging plus re-run. Known residual: a generated
  non-zone artifact still costs one replay execution before rejection —
  accepted, the pre-existing case (the expensive one) dies at parse.

## Constraints

- All written output English; no AI-process artifacts in file content
  (error strings describe the contract, no decision anchors).
- The machine-local store `~/.local/share/gos/85af56a090a78924` stays
  read-only; any fixture state is created inside the T86 sandbox with
  TESTBASE isolation.
- Section verification: TESTBASE-pinned `bash test/run-sections.sh T86`.
