# Plan: Assertion-debt rewrite for the changelog/gate test trio

> **Date**: 2026-11-06 | **Based on spec**: .gos/task/a6dfc894/spec.md

Two-wave rewrite of the recorded assertion debt in the T55/T57/T61 section
trio: three grep-shaped assertions become behavior assertions, five
structural source contracts are annotated exempt, and concern `b275a446` is
reclassified through the concerns CLI. Test-side changes only — no product
source under `bin/`, `hooks/`, `scripts/` may change (scope freeze).

## Decision Inventory

- [x] No D-NN decisions registered — the headless-auto THINK spec deliberately
  references no decision ids (frozen intent restates every choice inline);
  coverage gate is trivially green with zero decisions.

## Requirement Claims

- [x] R-01: Deliver concern b275a446 (assertion-debt rewrite, two waves) → T1, T2, T3, T4

## Patterns to Follow

- CLI under test is ALWAYS `node bin/gos.cjs` — never the global gos binary.
- Section verification: TESTBASE-pinned `bash test/run-sections.sh T<NN>` with
  a writable absolute sandbox base (e.g. under `.gos/cache/` or the spawn
  scratch dir) — the literal mktemp fallback dies on read-only tree sandboxes.
  Every run tees to `.gos/cache/section-runs/<ts>.log`; diagnose failures from
  the log, never re-run a suite just to see its output. Baseline verified
  green 2026-11-06: T55 31/0, T57 23/0, T61 28/0.
- Fixtures stay inside the section's own sandbox (t55_new/t57_new/t61_bare
  pattern); the machine-local store `~/.local/share/gos/85af56a090a78924` is
  live dogfood evidence — never touch it; any fixture store is XDG-overridden
  inside the sandbox.
- No AI-process artifacts in file content: exemption markers state the
  structural-contract fact (what the assertion pins and why it has no behavior
  surface), never task narrative or decision anchors.
- All written output English (cjk-lint boundary); commits Conventional
  Commits via the stage advances.
- The concerns ledger is hash-anchored: edit ONLY through
  `node bin/gos.cjs concerns prune --contains <substr>` / `concerns add "text"`
  — hand-editing `.gos/concerns.md` breaks the sidecar verification.

## Execution Waves

### Wave 1 (parallel — behavior rewrites in T55/T57)

#### T1: T55-G1 becomes changelog-lint/core verdict equivalence
- **Covers**: R-01
- **Files**: test/sections/T55-changelog-lint.test.sh
- **Read first**: test/sections/T55-changelog-lint.test.sh (G-suite at the end), bin/lib/task/changelog.cjs (cmdChangelogLint), bin/lib/ops/changelog-core.cjs (module.exports: validateStructure/validateEntry/parseChangelog/utcToday)
- **Approach**: Delete the G1 source grep (`grep -q "changelog-core" .../bin/lib/task/changelog.cjs`). Replace it with a G-suite equivalence harness: for each discriminating fixture — duplicate title, dates not newest-first, undated version heading, unmet today-obligation, plus one clean file — a `node -e` harness requires `$GOS_ROOT/bin/lib/ops/changelog-core.cjs` directly and computes the core verdict exactly as the CLI calls it (`validateStructure(text)` with the default today source, `validateEntry(entry)` per parsed [Unreleased] entry), inside a state-present sandbox (t55_new) so the today-obligation stays hard. Each fixture carries a discriminating keyword (title / newest-first / valid date / today's obligation); the harness asserts the keyword is a substring of the core's first violation AND of the `gos changelog lint` output, and that the CLI exit code agrees with the harness verdict (exit 1 iff the core finds ≥1 violation, exit 0 on the clean fixture). Z1 (zero-CJK product scan) is untouched here — its exemption marker lands in T4.
- **Done when**: `grep -n 'grep -q "changelog-core"' test/sections/T55-changelog-lint.test.sh` returns nothing AND the G-suite fixtures cover all four failure classes plus the clean file AND `TESTBASE=<writable-base> bash test/run-sections.sh T55` exits 0
- **Depends on**: none

#### T2: T57 consumes the malformed spec_path as a commit-think rejection
- **Covers**: R-01
- **Files**: test/sections/T57-archive-single-track.test.sh
- **Read first**: test/sections/T57-archive-single-track.test.sh (gos_spec + t57_ready), bin/lib/task/commit.cjs (THINK artifact gate: `spec file not found: <path>`)
- **Approach**: Repair `t57_ready` to store the well-formed `spec_path` returned by `gos_spec()` (drop the embedded surrounding double quotes) and keep materializing the stub spec file at that real path. Add an R-suite scenario: sandbox whose state has `current_stage='THINK'` and `spec_path` carrying the quoted (never-existing) form, fed to `GOS_HEADLESS=1 node "$GOS" commit think` — assert exit 1 and that the output carries the spec-not-found block naming the malformed path (pin `spec file not found:` plus the quoted path text, not just the exit code, so an unrelated gate failure cannot fake a pass).
- **Done when**: the t57_ready body stores the unquoted `s['spec_path']='$(gos_spec)'` AND a scenario asserts `spec file not found` against the quoted form AND `TESTBASE=<writable-base> bash test/run-sections.sh T57` exits 0 (delta.md assertions must still hold once the well-formed spec_path becomes readable by delta generation)
- **Depends on**: none

### Wave 2 (depends on Wave 1 — T61 wiring + exemption bookkeeping)

#### T3: T61-E1 gate wiring observable through audit output; E2 marker
- **Covers**: R-01
- **Files**: test/sections/T61-gate-wiring.test.sh
- **Read first**: test/sections/T61-gate-wiring.test.sh (A-suite audit scenarios + E-suite), bin/lib/ops/gate.cjs (changelog lint subprocess wiring, tail-3 surfacing)
- **Approach**: Remove the E1 source grep (`grep -qF "'changelog', 'lint'" .../bin/lib/ops/gate.cjs`). Replace with output-level wiring proof on a discriminating changelog fixture: in a stateless bare tree (t61_bare + `paths --markdown` seed, A-suite pattern), write a CHANGELOG.md whose `[Unreleased]` section carries one malformed entry at a known line (single top-level title, dates valid — the entry violation is the only failure class), then `node "$GOS" gate all --audit` must exit 1 and its output must carry the entry-validation violation class token (`structure:`) together with the file:line locator `CHANGELOG.md:<n>` and the entry text — deep lint behavior only the real lint implementation surfaces. Keep the locator within the gate's tail-3 surfacing by keeping the fixture to a single violation. The clean-changelog case stays as A12/A13. E2 (allowlist dual-source sync) keeps its source-level assertion and gains a factual structural-exemption marker comment: it pins the allowlist-present-in-both-sources wiring fact, which has no CLI surface.
- **Done when**: `grep -n "\"'changelog', 'lint'\"" test/sections/T61-gate-wiring.test.sh` returns nothing AND the new scenario asserts exit 1 + `structure:` + `CHANGELOG.md:` locator AND the E2 assertion carries the structural-exemption marker AND `TESTBASE=<writable-base> bash test/run-sections.sh T61` exits 0
- **Depends on**: none (wave dispatch orders it after Wave 1)

#### T4: T55-L134 exemption marker + concern b275a446 reclassification
- **Covers**: R-01
- **Files**: test/sections/T55-changelog-lint.test.sh, .gos/concerns.md
- **Read first**: test/sections/T55-changelog-lint.test.sh (Z-suite), .gos/concerns.md (entry b275a446), bin/lib/knowledge/concerns.cjs (prune/add CLI)
- **Approach**: Add the factual structural-exemption marker comment to the T55 Z-suite (zero-CJK product scan): it pins a static source fact with no behavior surface. Correct the ledger through the CLI only: `node bin/gos.cjs concerns prune --contains "[b275a446]"` (the hash token matches exactly the one misclassified entry), then `node bin/gos.cjs concerns add "<corrected text>"` stating the reclassification — 3 behavior rewrites (T55-G1 core-verdict equivalence, T57 malformed-spec_path consumed as commit-think rejection, T61-E1 gate-output wiring), 5 structural exemptions scoped to exactly the five named sites (T51-E, T51-F1, T51-F2, T61-E2, T55-L134), original 2026-09-21 wording preserved by reference, and any further source-grep assertion is debt again. The prune+re-add runs only after T1/T3 rewrites land (this wave).
- **Done when**: the Z-suite assertion carries the structural-exemption marker AND `node bin/gos.cjs concerns list` exits 0 (anchor sidecar verifies) and its output carries one entry naming 3 rewrites + 5 structural exemptions + the five sites AND no `- [.*b275a446.*]` line remains AND `TESTBASE=<writable-base> bash test/run-sections.sh T55` exits 0
- **Depends on**: T1, T3

## Observable Truths

Registration note: `gos truth add` is never spawn-granted (verify-class
whitelist, evidence replay only) — the five truths below are registered
operator-side at VERIFY entry, verbatim from this section, then verified
with `gos truth verify` against the section runs named in each Verify line.

### T-01: T55 same-source proof is behavioral
- **Expected**: T55's G-suite runs a core-verdict equivalence harness over
  the four failure-class fixtures plus a clean file; no assertion in the file
  greps changelog.cjs source for the validator wiring (Z1's zero-CJK scan
  remains, carrying its exemption marker)
- **Verify**: `TESTBASE=<writable-base> bash test/run-sections.sh T55` exit 0

### T-02: T57 feeds the malformed spec_path to the rejection surface
- **Expected**: the happy-path fixture carries a well-formed spec_path; the
  R-suite feeds the quoted form to `GOS_HEADLESS=1 commit think` and asserts
  exit 1 plus the spec-not-found message naming the malformed path
- **Verify**: `TESTBASE=<writable-base> bash test/run-sections.sh T57` exit 0

### T-03: T61 gate wiring is observable through gate output
- **Expected**: on a malformed-entry CHANGELOG.md, `gate all --audit` exits 1
  with the violation class token plus `CHANGELOG.md:<n>` locator; the
  `'changelog', 'lint'` source grep is gone; E2 carries the exemption marker
- **Verify**: `TESTBASE=<writable-base> bash test/run-sections.sh T61` exit 0

### T-04: Concern ledger reclassified and verifiable
- **Expected**: the corrected entry states 3 rewrites + 5 structural
  exemptions scoped to the five named sites; the concerns hash sidecar
  verifies
- **Verify**: `node bin/gos.cjs concerns list` exit 0 with the reclassified
  entry and no b275a446 line

### T-05: Test-side only, suite green
- **Expected**: all three sections pass under the section runner with
  fixture isolation; the task diff touches only the three declared test
  files plus concern-ledger bookkeeping (machine-local) — no product source
  changes
- **Verify**: `TESTBASE=<writable-base> bash test/run-sections.sh T55` (or
  the gos runner) then T57, T61 all exit 0; diff inspection shows zero
  changes under bin/, hooks/, scripts/

## Risks

- Harness drift risk (red-team R1): the fixture set must keep one fixture per
  violation class plus the clean file so a validator differing on any class
  fails at least one assertion; options mirror the CLI's actual calls
  (default today source, state-present context).
- Wrong-reason blocking (red-team R2): the T57 rejection scenario runs under
  `GOS_HEADLESS=1` and pins the spec-not-found message text, so an
  approval-mode or unrelated gate change cannot satisfy it.
- Blanket-license risk (red-team R3, PARTIAL): nothing mechanized prevents a
  sixth source grep — the corrected ledger entry scopes the exemption to the
  five named sites and declares any further grep new debt.
- Gate surfaces only the lint tail (last 3 lines): keep the T61 fixture to a
  single entry violation so the locator line rides the surfaced tail.
- T57 delta.md content shifts once spec_path is well-formed (delta can now
  read the stub spec): no existing assertion pins the old fallback, but the
  full section must re-run green.
- Read-only PLAN-tree sandboxes: section runs need the writable TESTBASE pin
  (literal mktemp under GOS_ROOT dies on read-only mounts); never write
  fixtures outside the sandbox base or the machine-local store.
