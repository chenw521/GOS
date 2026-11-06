# Spec — Restore THINK spawn yield: worker-shaped stage contracts in the auto dispatch prompts

## Intent

The auto loop's dispatched THINK sessions drown: three consecutive sandboxed
spawns (2026-11-05, stamps ed8b66ce-2/3/4) read extensively (20-54 commands,
103-128K tokens, 25-36 min) but never wrote the spec nor advanced — the
breaker tripped at layer N (concern d4e5f6a7). Root cause is the prompt, not
the channel or the sandbox: the generic five-line stage prompt sends the
spawned session into the interactive stage protocol (decision cards, red-team
attacker sub-sessions, lesson archaeology) that a headless one-shot worker
cannot complete, while the sandbox deny channel and INTENT round-trips worked
exactly as designed. Fix the dispatch prompts so every authoring-stage spawn
ends with a hard, worker-shaped contract.

## Scope

In: `bin/lib/ops/auto/loop.cjs` (defaultPrompt / prompt composition), unit
coverage in the auto section tests (T104/T107 style: inject a spawn runner,
capture `spec.prompt`, assert contract lines and regression pins).

Out: sandbox axis (tier/profile/deny — verified working, untouched); context
trimming of the spawned session's inherited context (74+22 lessons, skill
tree) stays deferred per the handoff ruling — revisit only if cycle 2 still
stalls at THINK; monolithic BUILD path keeps the generic prompt (no failure
evidence; wave-era vehicles use stageExitPrompt); PLAN/REVIEW live evidence
(their contract lines ride the same table but their first live run is cycle
2).

## Decisions

### D1 — Unified worker contract: preamble plus per-stage artifact table (THINK/PLAN/REVIEW)

User ruling 2026-11-06 on the draft card. The mismatch is
generic-prompt-vs-interactive-protocol, not THINK-specific; cycle 2's Lv3
vehicle hits PLAN/REVIEW through the same mechanism. All authoring stages get:
(a) a shared worker preamble — headless one-shot (no questions or choice
cards; decide and proceed), no attacker/red-team/parallel helper sessions, the
machine-local store (~/.local/share/gos) is audit evidence never to be
modified or "cleaned" (lesson 047cbe80), no archaeology (no lesson
enumeration, no skill-tree touring); (b) a per-stage ending contract rendered
in order: THINK = write the spec to the canonical path, PLAN = write the plan
to the canonical path, REVIEW = run the REVIEW checks; then
`node bin/gos.cjs commit <stage>`; then exit — the advance commit is the only
success signal; (c) an iteration line: the commit gate is the floor oracle —
fix reported floor failures and re-run the advance until it succeeds or a
clear error makes progress impossible. INTENT keeps the current generic
prompt (proven passing); BUILD keeps stageExitPrompt; VERIFY/SHIP are script
legs (no prompt spawn).

### D2 — Canonical path inline, derived from taskId — never raw state strings

User ruling 2026-11-06, amended by red team M1. The contract inlines the
exact artifact path (zero derivation left to the worker — the failing
sessions' signature was exactly read-then-derail), but the path is derived
canonically as `.gos/task/<taskId>/spec.md` (resp. `plan.md`) with a strict
taskId shape check — the raw `state.spec_path` value is never inlined into
prompt text. A non-canonical taskId or a state spec_path that deviates from
canonical fails closed: the spawn composes a refusal prompt path (refuse
spawn with a clear error surfacing the corruption) rather than emitting
state-derived free text into the prompt (prompt-injection vector — a
restricted-profile spawn can write inside .gos, so state fields are
attacker-reachable).

## Mechanization concerns surfaced by red team (log at TRACE, not this task)

- Profile integrity: templates/auto-profiles/ sits inside the BUILD
  workspace-writable surface; a drifted BUILD worker could weaken a profile
  for future spawns. Current defenses are PR-only main plus review; no
  per-spawn profile-file assertion exists.
- Monolithic BUILD spawns still receive the generic prompt; no live evidence
  against it, but the D1 mechanism would extend naturally if it ever trips.

## Observable Truths

1. Unit-captured THINK prompt contains: the canonical spec path line, the
   `node bin/gos.cjs commit think` command, all four worker-preamble clauses,
   and the commit-gate iteration line.
2. Unit-captured PLAN prompt carries the canonical plan path and commit plan
   command; REVIEW prompt carries the review-checks line and commit review
   command (no artifact line).
3. INTENT prompt is byte-identical to the pre-change generic rendering
   (regression pin).
4. BUILD stageExitPrompt is byte-identical to the pre-change rendering
   (regression pin).
5. Poisoned-state fixture (multi-line spec_path, non-canonical taskId): the
   spawn fails closed; no state-derived free text appears in any composed
   prompt.
6. Auto section battery green (T104/T105/T106/T107/T108) and the full check
   suite passes.

## Execution sequence

1. TDD red: add prompt-contract unit tests (capture spec.prompt via injected
   spawn runner, per T104's red-team harness precedent) — THINK contract,
   PLAN/REVIEW lines, INTENT/BUILD regression pins, poisoned-state
   fail-closed.
2. Green: implement the preamble + stage contract table in loop.cjs;
   canonical path derivation with shape check and fail-closed refusal.
3. Full section battery + repo checks; changelog entry; PR.

## Red Team record (3 rounds, Lv2 mandatory set)

- R1 misuse: M1 (Critical) state.spec_path free-text inlined into prompts is
  a prompt-injection vector (state fields are writable by restricted
  spawns) — ACCEPT: canonical derivation + fail-closed refusal (D2
  amendment). M2 (minor) preamble "decide and proceed" misread as license to
  skip floors — ACCEPT: commit-gate-as-oracle iteration line bounds it
  (gate is outside worker control).
- R2 edge: E1 (minor) retry with pre-existing spec — "Write" is overwrite
  semantics, correct. E2 (minor) opts.prompt override precedence preserved
  (trusted runner-side escape hatch). E3 (minor) monolithic BUILD out of
  scope — filed as concern. E4 (low) prompt stays silent on approval gates —
  contract vs enforcement separation; gate errors guide the worker.
- R3 completeness: C1 (minor) no consumer pins defaultPrompt text (grep
  verified: exports + call site only; redteam pins its own template hash) —
  additive tests only. C2 (minor) floors pointed at the commit gate, not
  enumerated in the prompt — no drift surface. C3 (minor) no doc quotes the
  prompt text (grep verified). C4 (low) profile-integrity residual risk —
  filed as concern.

## Deferred

- Context trimming (74+22 lessons, skill tree) — staged fallback per the
  handoff card, only if cycle 2 THINK still stalls after the prompt fix.
- Live PLAN/REVIEW evidence — cycle 2 is the first live run through the new
  contract lines.
