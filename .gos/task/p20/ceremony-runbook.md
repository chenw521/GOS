# Ceremony Runbook: close v1.0.0-dev, open publicize (P20)

> Execution contract: T14b runs POST-ARCHIVE (P20 done, close refuses an
> active host by design). One step at a time — every destructive act has
> its own user-confirmation gate; never batch. All commands run from the
> repo root via the repo CLI (`node bin/gos.cjs <cmd>` — never a global
> gos binary). Each tee writes the evidence file the truth-verify lines
> cite in Step 10.

## Step 1: Pre-flight — verify the host state

- `node bin/gos.cjs phase list`
- Expect: P20 status `done` (archived), P2/P3 `parked`, P21/P22/P23
  `pending`, no `active` phase anywhere.
- Expect: `node bin/gos.cjs status` shows no in-flight task (NO ACTIVE
  TASK composition) or the task list shows P20 archived.
- Gate: STOP if any phase is active — close will refuse anyway (R-03).

## Step 2: Register the v1.0.0-dev identity (late identity backfill)

- `node bin/gos.cjs milestone open v1-0-0-dev`
- Rationale: the historical `v1.0.0` slug prefix was the package version
  by accident — the repo never had a milestone object, and close refuses
  when none exists (R-03). The stored sanitized form is `v1-0-0-dev`
  (rejected-reserved shapes are bare `v`+digits only).
- Expect: confirmation line naming the sanitized stored form; the lv4
  marker file appears (untracked at this point — Step 9 flips it).
- Gate: confirm the echoed stored identity before continuing.

## Step 3: One-time P0 reorder — monotonic closing snapshot

- `node bin/gos.cjs phase move p0 0 --expect 5`
- Expect: `Phase moved: P0: full-auto mode (index 5 → 0)` (name-prefix
  source; the guard pins the current index so stale advice dies).
- Inspect: `node bin/gos.cjs phase list | head -4` — P0 must read at
  index 0 and names must run monotonically.
- Gate: user confirms the queue reads correctly before touching the
  milestone.

## Step 4: Close dry-run — inspect the five-class disposition

- `node bin/gos.cjs milestone close --carry-parked`
- Expect exit 0 and a per-class per-ID report. Kept (verbatim):
  parked phases P2/P3 + their parked-owned rows + pending phases
  P21/P22/P23. Wiped (with history): done phase entries + done-owned
  requirement/decision rows + null-phase rows + dropped/ghost rows
  (counted separately). `last_archived_phase` resets in the execution
  pass only.
- Verify: dry-run mutates nothing — project.json byte-identical.
- Gate: user reads the FULL report. Any surprising ID → STOP and
  investigate; the predicate refuses unknown classes, so surprises are
  data problems, not classification problems.

## Step 5: Arm and execute the close

- `node bin/gos.cjs approve milestone-close --reason "v1.0.0-dev ceremony"`
- `node bin/gos.cjs milestone close --carry-parked --yes`
- Expect: dual-channel snapshots written and stat-verified, approval
  consumed (single-use), single atomic wipe, per-class counts + ID
  report, `milestone.closed_at` stamped.
- Gate: the approval is consumed by the first successful execution — a
  second `--yes` invocation must die. Do not re-approve unless returning
  to Step 4 for a fresh dry-run.

## Step 6: Verify the snapshot channel on disk

- `ls .gos/project/milestones/` — expect `v1-0-0-dev-<date>-preclose.json`
  plus `v1-0-0-dev-<date>-{ROADMAP,REQUIREMENTS,DECISIONS}.md`.
- `ls .gos/archive/ | grep milestone-record` or the dated close home —
  the archive channel copy exists in the closing milestone-record.
- Byte-check one view: `cmp .gos/project/milestones/v1-0-0-dev-<date>-DECISIONS.md <the pre-close rendered DECISIONS.md restored from preclose run>` —
  snapshots are copies of the rendered files, MANUAL regions included.

## Step 7: Open the publicize milestone

- `node bin/gos.cjs milestone open publicize`
- Expect: `milestone {name: "publicize", opened_at: <ISO>}` written; the
  next archived task's slug prefix reads `publicize`; between Step 5 and
  here (closed-not-reopened gap) slugs carried no prefix.
- Gate: confirm before the vacuum probe.

## Step 8: Vacuum probe on the fresh milestone

- `node bin/gos.cjs milestone close`
- Expect: REFUSAL — `no done phases (vacuum close)` pointing at
  `--empty`. This proves the new cycle starts empty (P21-23 pending
  carried, nothing done).

## Step 9: Flip the lv4 marker to tracked

- `node bin/gos.cjs track .gos/project/lv4.json`
- The marker file exists (Step 2 wrote it); track performs the atomic
  ignored-to-tracked flip (gitignore negation + census + manifest).
- Expect: census ledger row added, marker now tracked — fresh clones
  stay Lv4 (R-08).

## Step 10: Ceremony-side truth verification (live evidence)

- `node bin/gos.cjs phase list | tee .gos/logs/ceremony-phase-list.log`
- `node -e "const p=require('./.gos/project/project.json');const pre=require('./.gos/project/milestones/v1-0-0-dev-<date>-preclose.json');const pick=(o)=>({phases:o.phases,decisions:o.decisions,requirements:o.requirements});const a=pick(p),b=pick(pre);const kept=(x)=>JSON.stringify(x);const fail=['phases','decisions','requirements'].filter(k=>JSON.stringify(a[k].filter(r=>['P2: decision archival','P3: adoption redesign'].some(n=>JSON.stringify(r).includes(n))||r.status==='pending'))!==JSON.stringify(b[k].filter(r=>JSON.stringify(r).includes('P2: decision archival')||JSON.stringify(r).includes('P3: adoption redesign')||r.status==='pending')));console.log(fail.length? 'DEEP-COMPARE FAIL: '+fail.join(',') : 'deep-compare: all survivor families byte-equal')" | tee .gos/logs/ceremony-t3-deepcompare.log`
- `node bin/gos.cjs truth verify T1 --replay --command '["node","bin/gos.cjs","phase","list"]' --artifact '.gos/logs/ceremony-phase-list.log'` (= `gos truth verify T1 --replay ...`)
- `node bin/gos.cjs truth verify T3 --command 'node -e deep-compare survivors vs preclose' --excerpt 'deep-compare: all survivor families byte-equal' --artifact '.gos/logs/ceremony-t3-deepcompare.log'` (= `gos truth verify T3 --command ... --excerpt ... --artifact ...`)
- `node bin/gos.cjs truth verify T4 --replay --command '["node","-e","console.log(require(process.argv[1]).milestone.name)",".gos/project/project.json"]' --artifact '.gos/logs/ceremony-milestone-name.log'` (= `gos truth verify T4 --replay ...`)
- The three verify lines overwrite the BUILD-side replay evidence with
  live ceremony evidence (two-column contract: sections proved the
  mechanics; this proves the live artifact).

## Step 11: Record outcomes into the closing milestone-record

- `cp .gos/logs/ceremony-phase-list.log .gos/logs/ceremony-t3-deepcompare.log <closing-milestone-record-dir>/`
- The task dir moved at archive; the closing home is the archive
  channel directory from Step 6 (or the synthesized
  `.gos/archive/<date>-v1-0-0-dev-close/milestone-record/`).
- Append a one-line outcome note per step (date, outcome, anomaly).

## Step 12: Final state audit

- `node bin/gos.cjs phase list` — P2/P3 + P21/P22/P23 present, P0 at
  index 0, done phases wiped from the live view (they live in the
  snapshots now).
- `node bin/gos.cjs resume` — NO ACTIVE TASK banner + publicize identity
  + carried queue + clone warning, exit 0.
- `node bin/gos.cjs gate all` — expect ALL GATES PASSED (truths verified,
  no phantom requirement rows).
- `bash test/pack-check.sh` — census reconciles with the newly tracked
  marker.
