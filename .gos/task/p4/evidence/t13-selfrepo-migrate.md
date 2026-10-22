# T13 Evidence: deferred parking + self-repo migrate + full suite

Date: 2026-10-22 (BUILD, P4 Wave 5)

## Deferred anchors (d-13 parking)

Two deferred concern anchors recorded via `gos concerns add` (English,
boundary-clean — store untracked in self-repo):

1. `rt2-f9 deferred: shared-lock redesign` — concernsRootLock re-entrancy
   relies on same-pid exemption; cross-process shared-lock design owed before
   more write-class commands nest under the root lock.
2. `d-13 deferred: dialogue governance P5 handoff` — navigator hint wording
   and THINK dialogue protocol changes parked for P5; seed P5 claim from
   this phase's evidence (knowledge-refresh.md sha).

Grep: `grep -cE "rt2-f9 deferred|d-13 deferred" .gos/concerns.md` → 2.

## Self-repo gap migrate (d-16 first product caller)

- `gos gap migrate` on this repo: **88 mirror line(s)** removed from
  `.gos/concerns.md`, appended to `.gos/logs/gap-history.ndjson`
  (88 ledger lines, {ts,text} NDJSON).
- Re-run: no-op ("no (auto) mirror lines — nothing to migrate").
- `grep -c "(auto)" .gos/concerns.md` → **0**.
- `gos concerns list` rc=0 after migrate.
- Note: anchor sidecar was stale after a manual junk-line deletion during
  T13; migrate's unconditional anchor rebuild cured it (documented behavior:
  anchors are regenerable cache, census purge:regen).

## Full suite (serial, lessons 63675448 / ead7fa41)

- Main suite `bash test/gos-cli-tests.sh`: **57 passed, 0 failed, RC=0**.
- Self-repo assertions: `gos status --fresh` rc=0.
- No `*.tmp*` residue in git status after the runs.

## Gate state

`gos gate all` remaining signal before stage exit: none after this evidence
file landed (T13's declared `.gos/concerns.md` + ledger are machine-local
zones in the opted-out self-repo — they never enter a git diff, hence this
tracked evidence artifact carries the T13 diff-hit).
