# Triage ledger: 95 sandbox failures at head 5419521c (classification; T9b families verified)

Full-suite sandboxed (bwrap, read-only-rootfs) run at head 5419521c:
`=== Sections total: 3468 passed, 95 failed ===`. This ledger accounts
for 95/95 of those failures across 19 failing sections, each with a
legal exit and an owning task. No skip, no writable widening, zero
unclassified blockers.

Counting convention (matches the runner's own accounting in
test/run-sections.sh): the 95 = per-section failed assertions plus one
extra failure for each section that aborted mid-script (the runner
echoes a distinct SECTION-ABORTED line and adds it to TOTAL_FAIL). The
per-section numbers below are byte-identical to the runner's
`failed sections:` line in the evidence window. Two sections (T105,
T106) carry failures from two different roots, so each is split into
two rows; the failures column is the split, not the section total.

## Main table

| section | failures | family | planned exit | owning task |
|---|---|---|---|---|
| T102-ai-trace | 13 | fixed-by-R1 partial (see T9b verification) | T1 enumerated writable set carries the TMPDIR scratch point (host TMPDIR /work/rstudio_tmp is not mounted in the sandbox) | T9b |
| T104-auto-core | 10 | fixed-by-R2 landed | T2 env registry: run-sections.sh unsets GOS_AUTO_* literals at runtime so fixture spawns stop seeing the enclosing VERIFY spawn | T9b |
| T105-auto-depth | 1 | fixed-by-R1 landed | T1 writable set carries /work/rstudio_tmp (fs.mkdtemp 'd7-rich-XXXXXX' under it hits ENOENT) | T9b |
| T105-auto-depth | 5 | fixed-by-R2 landed | T2 env registry clears the leaked spawn id (AB approvals-baseline legs) | T9b |
| T106-auto-spawn-channel | 1 | fixed-by-R1 landed | T1 writable set carries /work/rstudio_tmp (fs.mkdtemp 'hostcfg-XXXXXX' under it hits ENOENT) | T9b |
| T106-auto-spawn-channel | 11 | fixed-by-R2 landed | T2 env registry clears the leaked spawn id (C1-C3 channel verdicts) | T9b |
| T108-auto-wave-contracts | 4 | fixed-by-R2 landed | T2 env registry: the C13 loop child inherits the real marker env and reads the masked real store | T9b |
| T25-map-selfcheck | 2 | worktree-conversion | T7 worktree helper: self-repo map scan runs in a detached worktree with its own .gos/cache | T9c (converted+verified 2026-11-19) |
| T30-map-edges | 2 | worktree-conversion | T7 worktree helper (T30.11a self-repo scan with extractors writes the same cache) | T9c (converted+verified 2026-11-19) |
| T34-map-tsection | 2 | worktree-conversion | T7 worktree helper (T34.1a self-repo scan; the window also shows the deps.json cleanup rm failing read-only) | T9c (converted+verified 2026-11-19) |
| T36-callgraph | 7 | worktree-conversion | T7 worktree helper isolates .gos lock+cache from the enclosing runner | T9c (blocked-needs-source 2026-11-19: duplicate fn names gitOut/gitTry at bin/lib/ops/branch-reap.cjs:27,32 and bin/lib/ops/push.cjs:85,92 — every fresh-scan gate codemap exit-0 leg fails codemap-dup-fn-name; see evidence notes) |
| T47-module-require-direction | 1 | worktree-conversion | T7 worktree helper (self-repo gate codemap leg) | T9c (blocked-needs-source 2026-11-19: same duplicate-fn defect as T36 — the converted leg's fresh scan fails codemap-dup-fn-name) |
| T48-byname-tiers | 3 | worktree-conversion | T7 worktree helper (self-repo gate codemap + zero-duplicate legs hit the live-runner lock) | T9c (blocked-needs-source 2026-11-19: same duplicate-fn defect as T36 — the zero-duplicate green line asserts exactly what HEAD violates) |
| T60-commitlint-hook | 1 | fixed-by-R1 landed | T1 writable set carries TMPDIR so the hook's mktemp succeeds and the documented fail-open stream separation engages | T9b |
| T61-gate-wiring | 1 | fixed-by-R1 landed | T1 writable set carries TMPDIR (section dies at mktemp before any assertion) | T9b |
| T65-allowlist-product | 1 | worktree-conversion | T7 worktree helper (i1 self-repo gate codemap leg) | T9c (blocked-needs-source 2026-11-19: same duplicate-fn defect as T36) |
| T66-census-reconcile | 7 | XDG-fixture-conversion | T9c converts the section off machine-local toolchain assumptions: sandbox PATH resolves npm 10.2.4 (column-padded listing) while the host toolchain (nvm npm 11.9.0) is unmounted; pack-check's dir-presence greps must tolerate the 10.x listing format | T9c (blocked-needs-source 2026-11-19: test/pack-check.sh:32 sed leaves npm 10.x column padding on the paths so the ^dir/ greps at test/pack-check.sh:42 miss skills/, templates/, .opencode/, hooks/ — no section-side conversion can cure a parse bug in the checked script without shimming npm; see evidence notes) |
| T67-gates-trust | 1 | fixed-by-R1 | T1 writable set carries TMPDIR (section dies at mktemp before any assertion) | T9b |
| T69-init-coding | 1 | XDG-fixture-conversion | T9c TESTBASE-fixture conversion: the non-git fixture's ceiling shield must cover the actual TESTBASE location, which sits inside the spawn scratch git work tree | T9c (converted+verified 2026-11-19) |
| T72-lessons-json | 18 | XDG-fixture-conversion | T9c fixture conversion: bake the backup under TESTBASE instead of preferring an absolute /tmp-store.json that only fails on the host (bwrap's tmpfs root is writable, so the first cp succeeds, no .bak exists, and every later restore fails) | T9c (converted+verified 2026-11-19) |
| T99-gate-flip-leg | 3 | worktree-conversion | T7 worktree helper (S1 self-repo gate flip refused by the live-runner lock) | T9c (converted+verified 2026-11-19) |

## Family subtotals (sum to 95)

- fixed-by-R1 (writable set / compose refusal; owning T9b): 18 — landed
  2026-11-18 (5/5 single-failure rows verified green in-sandbox; T102's 13
  cleared of the TMPDIR mechanism but carry a blocked whitelist re-pin,
  see T9b verification)
  - T102-ai-trace 13, T105-auto-depth 1, T106-auto-spawn-channel 1,
    T60-commitlint-hook 1, T61-gate-wiring 1, T67-gates-trust 1
- fixed-by-R2 (GOS_AUTO_* env leak; owning T9b): 30 — landed 2026-11-18
  (30/30 verified green in-sandbox, zero stage-mismatch occurrences)
  - T104-auto-core 10, T105-auto-depth 5, T106-auto-spawn-channel 11,
    T108-auto-wave-contracts 4
- worktree-conversion (real-repo-checkout assumption; owning T9c, T7 helper): 21
  - T25-map-selfcheck 2, T30-map-edges 2, T34-map-tsection 2,
    T36-callgraph 7, T47-module-require-direction 1, T48-byname-tiers 3,
    T65-allowlist-product 1, T99-gate-flip-leg 3
  - T9c status: T25/T30/T34/T99 converted+verified (2026-11-19,
    worktree-helper conversion green in the restricted sandbox);
    T36/T47/T48/T65 (12 failures) blocked-needs-source on the duplicate
    fn-name defect below — not convertible to green until the source is
    cured, no skip and no assertion weakening available.
- XDG-fixture-conversion (machine-local state / fixture placement; owning T9c): 26
  - T66-census-reconcile 7, T69-init-coding 1, T72-lessons-json 18
  - T9c status: T69/T72 converted+verified (2026-11-19); T66 (7 failures)
    blocked-needs-source on the pack-check npm-10 listing parse below.
- T7-direct (failure covered by the helper itself, no conversion): 0
- unclassified-blocker: 0

18 + 30 + 21 + 26 = 95.

## Evidence notes (one line per row whose root is not visible in the row)

- T102 (13): ai-trace-lint.sh and cjk-lint.sh both call bare
  `mktemp -d`, which honors TMPDIR=/work/rstudio_tmp; inside the sandbox
  that path does not exist, so the lint infra-fails in every context -
  exit-1 probes (A1, C2, C3, E1) pass by coincidence, the expected-0
  probes (B1, C1, F2, H1) fail, and every machine-verdict assert fails
  on empty JSON. G1's negative control lists ai-trace-lint and cjk-lint
  firing for this same infra reason.
- T104 (10): every failing assert is a spawn-channel refusal quoting
  "spawn 5419521c-...-1-sections is assigned stage VERIFY, not think" -
  the code under test resolves the REAL spawn id from the leaked env and
  finds the enclosing runner's store entry instead of the fixture one;
  the runner-legs, T12-gate and baseline-guard asserts are downstream of
  the same refusal (the advance never lands).
- T105 R1 row (1): the D7 probe's raw output in the window is
  `Error: ENOENT ... mkdtemp '/work/rstudio_tmp/d7-rich-XXXXXX'`.
- T105 R2 row (5): the AB refusals quote the same stage-mismatch text
  and a Python `KeyError: 'THINK'` from parsing the refusal instead of
  a PENDING approval.
- T106 R2 row (11): C1's "REFUSED stage-mismatch"/"REFUSED
  budget-exhausted" verdicts and C2's "got REFUSED stage-mismatch"
  (expected no-entry/redteam-no-write) all show the channel resolving
  the real store entry for the leaked spawn id; the forged-cache and
  no-entry negatives cannot even reach their own refusal classes.
- T108 (4): C13's output carries "no host opencode config found" plus
  "pin-module-unloadable: Cannot find module '/home/bio-06/.local/share/
  gos/85af56a0...'...ratify.cjs" - the loop child, stamped with the real
  marker env, reads the masked real store instead of the fixture store
  the section exported via XDG_DATA_HOME.
- T25/T30/T34/T36/T47/T48/T65/T99 (worktree, 21): each runs `node
  $GOS map scan` / `gate codemap` / `gate flip` with cwd inside the real
  repo checkout; the window shows both refusal modes - the deps.json
  cache write/cleanup failing with "Read-only file system" and gos
  write-class commands refusing with "concurrent GOS invocation detected
  (pid 3565331 is ALIVE)" (the enclosing spawn holds the real repo's
  .gos lock for the whole suite). A detached worktree under TESTBASE
  gives each run its own .gos lock and cache, clearing both.
- T60 (1): hooks/commit-msg documents the exact degrade - "When stream
  separation is impossible (mktemp unavailable) no fail-open
  classification is attempted at all"; H1's shim npx prints the network
  token on stderr, but the hook captured combined streams because
  `mktemp "${TMPDIR:-/tmp}/gos-commitmsg.XXXXXX"` failed, so exit 3
  propagated fail-closed.
- T61 (1) / T67 (1): the only failure line in each section is the abort
  marker; the window carries `mktemp: failed to create directory via
  template '/work/rstudio_tmp/gos-t61-audit-XXXXXX': No such file or
  directory` (and the gos-t67-trust twin) - the sections die at setup
  before their first assertion (both green on the host with a pinned
  TESTBASE, per the earlier dogfood window at 2026-11-09T04:03).
- T66 (7): reproduced in a local bwrap harness matching the compose
  shape (ro-bind repo, tmpfs /, no /work): sandbox npm is 10.2.4
  (/usr/local/bin/npm, node 21.6.0 - the same versions named in the
  window's T105/T106 stack traces) while the host toolchain is nvm npm
  11.9.0 (node 24.14.0) under /work/run/projects/bio-06/.nvm, which the
  sandbox does not mount. npm 10.x right-aligns the "Tarball Contents"
  listing with padding spaces; after the sed strip the paths carry
  leading spaces, so pack-check's `^dir/` greps miss skills/,
  templates/, .opencode/, hooks/ while census-1..3 still report ok -
  exactly the captured shape of A1, B1 (fixture sandbox, not the real
  repo) and g2.
- T69 (1): the H-case fixture runs `gos init coding` in a non-git dir
  with GIT_CEILING_DIRECTORIES=$GOS_ROOT - on the host TESTBASE lives
  under the repo root so discovery stops; in the sandbox TESTBASE is the
  spawn scratch testbed, which sits inside the spawn workspace git work
  tree, so git finds a toplevel and gos refuses "must run at the project
  root" instead of printing the git-init hint.
- T72 (18): reproduced - bwrap's root is a writable tmpfs (a probe file
  at / is creatable), so the fixture chain
  `cp .gos/lessons.json /tmp-store.json || cp .gos/lessons.json
  t72-store.bak` takes the first branch (it fails on the host, where /
  is not user-writable), no t72-store.bak is baked, both restores fail
  ("cp: cannot stat 't72-store.bak'"), and the un-restored mutated
  stores cascade the id-recompute fail-closed verdict through every
  later case including the global-side rehearsal.
- T99 (3): S1's captured actual is the lock refusal
  "concurrent GOS invocation detected (pid 3565331 is ALIVE...)" - the
  self-repo flip cannot run while the enclosing spawn holds the lock.
- T36/T47/T48/T65 blocked row (12 failures, duplicate fn names): the
  worktree conversion recipe was proven end to end inside the restricted
  sandbox (prepareSectionWorktree checkout, tracked .gos/state.json removed
  per the lock.cjs linked-worktree guard, gate trust opt-in for the fresh
  checkout): map scan exits 0, but gate codemap exits 1 with two
  codemap-dup-fn-name verdicts - gitOut and gitTry are defined in BOTH
  bin/lib/ops/branch-reap.cjs:27,32 and bin/lib/ops/push.cjs:85,92 at HEAD.
  A fresh scan of the real repo on the host reproduces the same verdicts
  (the passing host runs were reading a stale machine-local deps.json that
  predates the duplication). Sections asserting codemap exit 0 or the
  dup_names = empty green line cannot pass against fresh HEAD content;
  renaming one fn pair (source files, outside T9c's boundary) unblocks all
  four rows.
- T66 blocked row (7 failures, npm 10.x listing parse): reproduced inside
  the restricted sandbox - PATH resolves npm 10.2.4, and test/pack-check.sh
  fails with four "npm pack manifest is missing '<dir>/' entries" lines
  (skills/, templates/, .opencode/, hooks/). The sed at
  test/pack-check.sh:32 strips only one space after the size token, so the
  10.x column-padded "Tarball Contents" lines keep leading spaces and the
  ^dir/ greps at test/pack-check.sh:42 miss four of the five roots (the
  census node prelude trims per-line, which is why census-1..3 still report
  ok). The nvm npm 11.9.0 the host sections assume lives under /work and is
  not mounted in the sandbox, so no section-side conversion reaches green
  without editing pack-check itself or shimming npm (both out of bounds).
- T9c conversion patterns (one line each): worktree family - self-repo legs
  cd into a prepareSectionWorktree checkout under the section's own
  TESTBASE subdir (tracked .gos/state.json removed, sweep in teardown); T69
  - GIT_CEILING_DIRECTORIES covers $TESTBASE:$GOS_ROOT so discovery stops
  at the actual base; T72 - the lessons.json backup bakes beside the store
  under TESTBASE instead of a writable-root /tmp path.

## T9b verification (fixed-by-R1 / fixed-by-R2, 2026-11-18)

Method: every row ran inside the real Class S compose (workers
composeScriptSpawn, bubblewrap tier) with the spec env the live loop hands
a VERIFY sections step — sanitized passthrough, compose channel vars,
marker + spawn id (the R-2 leak trigger) and an untouched
TMPDIR=/work/rstudio_tmp (the R-1 trigger). Two modes: pinned
(GOS_SECTIONS_TREE_OVERRIDE=HEAD — sections from a clean HEAD checkout,
verifies the landed surfaces) and live (no override — sections from the
ro-bound working tree, verifies the uncommitted section edits; T126 W4
precedent). Evidence artifacts: per-run driver transcripts and salvaged
runner logs under .gos/cache/section-runs/t9b-evidence/.

- T104-auto-core (10): verified green — pinned run 93 passed, 0 failed
  (T104-auto-core.r2.* evidence).
- T108-auto-wave-contracts (4): verified green — pinned run 63 passed,
  0 failed (T108-auto-wave-contracts.r2.*).
- T105-auto-depth (1 R1 + 5 R2): pinned run red only at the D7 mkdtemp
  ENOENT (R-2 legs cleared: no stage-mismatch text); after the section
  edit, live sandbox run 33 passed, 0 failed.
- T106-auto-spawn-channel (1 R1 + 11 R2): pinned run red only at the C5
  mkdtemp ENOENT; after the section edit, live sandbox run 38 passed,
  0 failed.
- T60-commitlint-hook (1): pinned run red exactly at H1 (hook mktemp
  fail-closed, exit 3); after the section edit, live sandbox run 51
  passed, 0 failed.
- T61-gate-wiring (1): pinned run red exactly at the setup abort; after
  the section edit, live sandbox run 31 passed, 0 failed.
- T67-gates-trust (1): pinned run red exactly at the setup abort; after
  the section edit, live sandbox run 51 passed, 0 failed.
- T102-ai-trace (13): PARTIAL — blocked residual. The landed R-1 surface
  does not neutralize the leaked TMPDIR (the spec env passes it through;
  /work/rstudio_tmp is not mounted inside the compose), so the section
  got a first-usable-base TMPDIR pin. In-sandbox the run improved from
  8 passed / 13 failed to 18 passed / 3 failed: every mktemp-infra leg
  (C1, F2, H1, machine verdicts) cleared. The remaining 3 (B1, G1,
  abort) are NOT sandbox-specific: the tracked whitelist
  .gos/ai-trace-whitelist.json is stale against HEAD — the 4ace2aa and
  f46fb82 landings shifted pinned lines in bin/lib/ops/gate.cjs (939,
  961, 1009, 1014, 1213, 1223, 1528, 1564, 1601), bin/gos.cjs (265),
  bin/lib/core/state.cjs (1467), test/run-sections.sh (92) and .gitignore
  (region sha) without re-pinning. A pristine `git archive HEAD` checkout
  lints red on the host too (rc=1, 107 findings), and the host-literal
  section shows the identical 3 failures — this red predates T9b and is
  outside its file boundary (re-pin .gos/ai-trace-whitelist.json, or
  restore the drifted lines; owner: the landing batch / coding-standards
  sweep, not a section edit).

Section edits landed by T9b (all verified green in-sandbox AND
host-literal with an isolated TESTBASE pin; host-literal outputs in
t9b-evidence/*.lit.out):

- test/sections/T102-ai-trace.test.sh — pin TMPDIR to the first usable
  base before any lint check runs (the checks scratch via bare mktemp).
- test/sections/T60-commitlint-hook.test.sh — pin TMPDIR to the first
  usable base so hooks/commit-msg stream separation can engage.
- test/sections/T61-gate-wiring.test.sh — t61_bare mktemp base falls
  back to /tmp when TMPDIR is unusable (stays outside any GOS-managed
  tree).
- test/sections/T67-gates-trust.test.sh — same fallback in t67_setup.
- test/sections/T105-auto-depth.test.sh — run-d7.cjs scratch dirs move
  from os.tmpdir() to a probed usable base.
- test/sections/T106-auto-spawn-channel.test.sh — C5 scratch dirs move
  from os.tmpdir() to a probed usable base.

## Appendix: evidence provenance

- Window (READ ONLY, machine-local dogfood store):
  /home/bio-06/.local/share/gos/85af56a090a78924/windows/5419521c-07e0-465a-b41d-d5b072d827e2-1-sections.head.txt
  /home/bio-06/.local/share/gos/85af56a090a78924/windows/5419521c-07e0-465a-b41d-d5b072d827e2-1-sections.tail.txt
  (the -2- variants are byte-identical, verified with diff -q)
- Total line (window tail, line 4198):
  `=== Sections total: 3468 passed, 95 failed ===`
- Per-section distribution (window tail, line 4199, verbatim):
  `failed sections: T102-ai-trace(13) T104-auto-core(10) T105-auto-depth(6) T106-auto-spawn-channel(12) T108-auto-wave-contracts(4) T25-map-selfcheck(2) T30-map-edges(2) T34-map-tsection(2) T36-callgraph(7) T47-module-require-direction(1) T48-byname-tiers(3) T60-commitlint-hook(1) T61-gate-wiring(1) T65-allowlist-product(1) T66-census-reconcile(7) T67-gates-trust(1) T69-init-coding(1) T72-lessons-json(18) T99-gate-flip-leg(3)`
- The same 95-failure shape is stable across the earlier sandbox
  windows d87f0e31-...-{2,3,4}-sections.tail.txt (3446 passed,
  95 failed), so the classification target is not a one-off flake.
- Root-cause probes for T66, T72, T69 and the TMPDIR/mktemp family were
  reproduced in a throwaway bwrap harness replicating the compose shape
  (ro-bind /usr etc., tmpfs /tmp, ro-bind repo with rw .git, absent
  /work, TMPDIR=/work/rstudio_tmp) outside this repository; no repo file
  was modified.
- Section sources read for classification (current tree):
  test/sections/{T102,T104,T105,T106,T108,T25,T30,T34,T36,T47,T48,T60,
  T61,T65,T66,T67,T69,T72,T99}*.test.sh, test/run-sections.sh,
  test/checks/ai-trace-lint.sh, test/checks/cjk-lint.sh,
  test/pack-check.sh, hooks/commit-msg,
  bin/lib/ops/auto/launcher.cjs (composeArgv), bin/lib/ops/gate.cjs.
- Verification note: the runner's FILTER is substring-based, so T9b/T9c
  re-verification runs can select split rows by full section name
  (e.g. `bash test/run-sections.sh T105-auto-depth`).
