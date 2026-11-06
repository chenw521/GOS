# Spec — assertion-debt rewrite for the changelog/gate test trio (Lv3, task a6dfc894)

Headless-auto THINK output. The runner intent is frozen and is the decision
authority for this task; every directive below restates a pre-frozen choice
together with the alternatives that were weighed. No live decision records are
registered from the spawn session, so this spec deliberately references no
decision ids.

## Context and problem

Concern `b275a446` (2026-09-21, P11 review minors #17/#18) records assertion
debt: several section assertions grep product source strings instead of
asserting observable behavior, and the T57 fixture embeds a malformed
`spec_path` that no assertion consumes. The original concern text counts "11
grep assertions" as rewrite debt; that count is a misclassification. Of those
grep-shaped assertions, three are genuine behavior rewrites and five are
structural source contracts that are asserted at source level by design (they
pin static wiring facts with no behavior surface). The reclassification:

- 3 behavior rewrites: T55-G1, T61-E1, and the T57 malformed-`spec_path`
  fixture consumption.
- 5 structural exemptions: T51-E, T51-F1, T51-F2, T61-E2, T55-L134.

Empirical grounding for the malformed-`spec_path` mechanism: the T57 fixture
line builds `spec_path` as `'"$(gos_spec)"'`, embedding the resolved path
wrapped in literal double quotes. The stored value therefore names a path that
never exists (leading quote character). Archive consumes it nowhere — the
archive move relocates the whole `task/<id>/` directory and delta generation
falls back to "none recorded — see spec.md" — while the commit-side THINK
artifact gate does reject it observably ("spec file not found: <path>").
That rejection is the already-existing behavior surface the fixture feeds.

## Scope freeze

In scope (declared by the frozen intent):

- `test/sections/T55-changelog-lint.test.sh`
- `test/sections/T57-archive-single-track.test.sh`
- `test/sections/T61-gate-wiring.test.sh`
- Concern-ledger bookkeeping: correcting the `b275a446` entry text in
  `.gos/concerns.md` through the concerns CLI (`prune --contains` + `add`),
  which keeps the hash sidecar consistent. Hand-editing the ledger file is
  forbidden — entries are hash-anchored.

Out of scope:

- Any product source under `bin/`, `hooks/`, `scripts/` — the rewrites must
  land as test-side changes only; the suite must stay green without touching
  product code.
- `test/sections/T51-commit-guard.test.sh` — its three structural assertions
  (T51-E, T51-F1, T51-F2) are exempt and the file is not in the frozen list;
  their exemption is recorded in the corrected concern text only.
- Concern `4b55189d` (release-promote semver gate + changelog lock). The
  intent's parenthetical cross-reference is metadata; that concern's file is
  outside the frozen list and stays untouched.

## Directive W1-A — T55-G1 becomes changelog-lint/core verdict equivalence

Replace the source grep (`grep -q "changelog-core" .../changelog.cjs`) with a
behavior equivalence check: a `node -e` harness requires
`bin/lib/ops/changelog-core.cjs` directly and computes the core verdict for
each discriminating fixture; the `gos changelog lint` exit code must agree
with the harness verdict (exit 1 iff the core finds a violation, exit 0 on
the clean fixture) and the CLI output must surface the same violation keyword
the core reports. Fixture set: one per failure class — duplicate title, dates
not newest-first, undated version heading, unmet today-obligation — plus one
clean file. A drifted in-shell copy of the validator fails at least one
fixture; the same-source property is then observed, not asserted by text.

| Option | Premise | Pros | Cons | Activates |
| --- | --- | --- | --- | --- |
| core-verdict equivalence harness | the no-drift property is observable as verdict agreement between the CLI and the validator module | real behavior proof; reuses existing fixture style; no product change | harness must mirror the CLI's validator options faithfully | T55 G-suite rewrite |
| keep the source grep with a comment | cheapest change; the grep does detect a severed require | still text-not-behavior, which is the recorded debt | comment cannot detect drift | nothing (debt stays) |
| mutate the core module mid-suite | mutation testing would prove consumption directly | strongest causal proof | mutates product source during a suite that other sections run against; forbidden by the scope freeze | rejected |

why-not: keep the source grep — it is the debt being cured; a comment cannot
detect a drifted copy.

## Directive W1-B — T57 consumes the malformed spec_path as a rejection assertion

The happy-path fixture (`t57_ready`) stops embedding the quoted form: it
stores the well-formed `spec_path` returned by `gos_spec()` (no surrounding
quotes) and materializes the stub spec file at that real path. A new scenario
asserts the rejection surface instead: a THINK-stage sandbox state whose
`spec_path` carries the quoted (never-existing) form is fed to
`GOS_HEADLESS=1 node "$GOS" commit think`, which must exit 1 and print the
spec-not-found block naming the malformed path. The assertion pins the
message text, not just the exit code, so an unrelated gate failure (for
example an approval-mode change) cannot fake a pass.

| Option | Premise | Pros | Cons | Activates |
| --- | --- | --- | --- | --- |
| commit-think rejection assertion | the THINK artifact gate already rejects an unresolvable spec_path observably | consumes the exact malformation the fixture produced; no product change | needs the headless env pin so approval cannot block first | T57 R-scenario + repaired t57_ready |
| pin archive's silent tolerance | archive falls back to "none recorded — see spec.md" when the spec cannot be read | also observable, via delta.md text | blesses silent tolerance as the contract; weaker than the existing rejection | rejected |
| drop spec_path surgery from the fixture | removing the field removes the malformed value | simplest fixture | erases the scenario instead of consuming it; the debt resurfaces later | rejected |

why-not: pin archive's silent tolerance — the archive move relocates
`task/<id>/` wholesale, so the malformed value is never read there; the
observable rejection lives at the commit gate and that is what the fixture
should feed.

## Directive W2-A — T61-E1 gate wiring observable through gate output

Remove the source grep for `'changelog', 'lint'` in `gate.cjs`. Replace it
with output-level wiring proof on a discriminating changelog fixture: with a
CHANGELOG.md whose `[Unreleased]` section carries a malformed entry, `gate
all --audit` must exit 1 and its output must carry the entry-validation
violation class token together with the file:line locator
(`CHANGELOG.md:<n>`) — deep lint behavior that only the real lint
implementation produces; a stale in-gate copy would not surface it. The
clean-changelog case (audit exit 0 with the lint line visible) already exists
as A12/A13 and stays.

| Option | Premise | Pros | Cons | Activates |
| --- | --- | --- | --- | --- |
| discriminating-fixture output assertion | wiring is proven if gate output carries lint behavior only the real lint subprocess produces | observable end to end; no source inspection; complements A4/A13 | fixture must stay inside the audit-mode contract | T61 E1 rewrite |
| grep for the subprocess spawn site | textually confirms gate spawns the CLI | one-line change | same text-not-behavior debt, just a different string | nothing (debt moves) |
| stub the changelog CLI on PATH | intercepting the spawn proves invocation | causal proof of invocation | depends on PATH resolution order inside CI sandboxes; brittle across runners | rejected |

why-not: grep for the subprocess spawn site — relocating the grep from the
wiring literal to the spawn literal is the same debt under a different
string.

## Directive W2-B — five structural exemptions annotated, concern reclassified

The five structural source contracts stay as source-level assertions by
design and are annotated as exempt where the file is in scope: an inline
marker comment on T55-L134 (zero-CJK product scan) and on T61-E2 (allowlist
dual-source sync), stating the structural-contract status factually. T51-E,
T51-F1, and T51-F2 are out-of-scope files; their exemption is recorded in the
ledger. The `b275a446` entry is corrected through the concerns CLI only —
`gos concerns prune --contains` for the old entry, then `gos concerns add`
with the corrected text (3 rewrites + 5 structural exemptions, original
wording preserved inside the entry). The corrected entry scopes the exemption
to exactly the five named sites and states that any further source-grep
assertion is debt again; it is pruned only after the rewrites land.

| Option | Premise | Pros | Cons | Activates |
| --- | --- | --- | --- | --- |
| CLI prune + re-add with corrected text | the ledger stays hash-anchored and consistent | sanctioned path; corrected count is audit-visible; rollback is trivial | entry date/ordering changes | concerns ledger + exemption markers |
| rewrite all five as behavior assertions | maximizes behavior coverage | none beyond principle | static wiring facts (staging path membership, allow-empty exemption count, dual-source allowlist sync) have no behavior surface without product changes the freeze forbids | rejected |
| hand-edit the concerns file | direct text control | none | breaks the hash sidecar anchor; the next concerns command dies on verification | rejected |

why-not: rewrite all five as behavior assertions — structural contracts pin
source-level facts (ADD_PATHS membership, single allow-empty exemption site,
allowlist present in both sources, zero-CJK product source) that cannot be
observed through any CLI surface, and manufacturing one would require product
changes outside the frozen file list.

## Observable truths

What a stranger can observe when this task is done (registered as task
truths; verification happens in the later stages):

1. T55's same-source proof runs a core-verdict equivalence harness over
   discriminating fixtures; no assertion in the file greps
   `changelog.cjs` source for the validator wiring.
2. T57's happy-path fixture carries a well-formed `spec_path`, and a new
   scenario feeds the quoted malformed form to `commit think` under
   `GOS_HEADLESS=1`, asserting exit 1 plus the spec-not-found message naming
   the malformed path.
3. T61's E1 asserts gate wiring through `gate all --audit` output (violation
   class token plus file:line locator on a malformed-entry changelog); the
   `'changelog', 'lint'` source grep is gone; E2 carries the structural
   exemption marker.
4. The corrected `b275a446` ledger entry states the reclassification (3
   rewrites, 5 structural exemptions, exemption scoped to the five named
   sites) and the concerns hash sidecar verifies.
5. All three sections pass under the section runner with fixture isolation,
   and the task diff touches only the three declared test files plus concern
   ledger bookkeeping — no product source changes.

## Red-team dispositions

Three rounds (misuse / edge / completeness) run headless; dispositions are
recorded inline here.

- Round 1 — misuse: could the equivalence harness pass against a drifted
  copy? Disposition ACCEPT with constraint: the fixture set must include one
  fixture per violation class plus a clean file, so any validator whose
  behavior differs from the core on any class fails at least one assertion;
  the harness options are pinned to mirror the CLI's actual validator calls.
- Round 2 — edge: could the commit-think rejection assertion block for the
  wrong reason? Disposition ACCEPT with constraint: the scenario runs under
  `GOS_HEADLESS=1` (T55 precedent) and asserts the spec-not-found message
  text, so an approval-mode or unrelated gate change cannot satisfy it.
- Round 3 — completeness: could the exemption markers become a blanket
  license for source greps? Disposition PARTIAL: the corrected concern entry
  scopes the exemption to exactly the five named sites and declares any
  further source-grep assertion new debt; nothing mechanized prevents a sixth
  grep, the ledger is the guard.

## Constraints (frozen by the runner)

- The machine-local store `~/.local/share/gos/85af56a090a78924` is live
  dogfood evidence: never delete, reset, or overwrite it; any fixture store
  is XDG-overridden inside the test sandbox.
- Model policy: accept the dispatch-table pinning; no model substitution.
- Human takeover at the advance step on pause is expected behavior, not an
  anomaly.
- Work only the files the frozen declaration lists for these tasks.
