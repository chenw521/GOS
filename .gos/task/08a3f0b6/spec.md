# Spec — honor map-ignore at the scan layer (chenw521/GOS#64)

Task: 08a3f0b6 | Level: Lv3 | Branch: fix/64-map-ignore-scan-sources

## Intent

Repos with vendored JS cannot use the codemap gate: `gos map scan` collects
third-party files (FS walker `scanSources` reads only hardcoded skips), the
semantic extractors then parse/dedup that universe, and the gate fail-closes
on parse_failures / dup_names — permanently red, with a fix hint that loops
("run map scan"). The documented exclusion mechanism `.gos/map-ignore` is
consumed only by `semanticUniverse`; it never reaches the file collection
layer. The same vendored blindness hits two SHIP scripts
(cleanup-scan.sh, security.sh) that scan `git ls-files` output.

## Root cause (verified)

- engine.cjs:82 `scanSources` walks the FS with MAP_SKIP_DIRS + `.min.js`
  only; `loadMapIgnore` is never consulted
- engine.cjs:503 `writeDeps` deliberately runs ALL extractors on
  `scan.files` ("SAME file set the import scanner saw")
- callgraph (engine.cjs:345) → parse_failures; testof_fn (engine.cjs:390)
  → dup_names from vendored class fns
- gate.cjs:1090/1095 fail-closed on both; fix hints are dead ends
- Sandbox reproduction: dup mxActor across vendored files → gate red;
  collection-layer filter → gate green (diagnostic patch, reverted)

## Decisions

| ID | Decision | Key evidence |
|:--|:--|:--|
| D-01 | scanSources filters by loadMapIgnore at collection; ignored paths enter no universe (files/edges/semantic) | 9 consumers share one filtered universe; U/P sandbox: dup 1→0, gate red→green; src→vendored degrades to an externals entry |
| D-02 | Polluted peaks: gate advisory attributes missing fns via peak.owners × map-ignore; full coverage guides baseline reset (approve-gated, never auto) | peak.owners exists (engine.cjs:515/gate.cjs:1158); sandbox attribution 2/2; auto-reset would bypass reason-match/single-consumption/archive audit |
| D-03 | Script exclusion: scan materializes `.gos/codebase/map-ignored.txt` (unmapped-fns twin: untracked, regen, provenance header); scripts `grep -vxFf`, missing file → full scan | census layer: tracked trio are non-regenerable truths; map-ignored is regenerable; audit anchor is tracked map-ignore itself |
| D-04 | Discoverability: fix hints name map-ignore; scan prints excluded count; README en+zh gains glob-semantics section | reporter found the mechanism only by reading source; both current fix hints are dead ends |

### D-01 Exclusion scope — chosen: D-01-A (collection-layer filtering)

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| D-01-A | collection-layer filtering; 9 consumers share one filtered universe; vendored dependency degrades to an externals entry | graph/semantic/gate/closure stay consistent; direction assertion loses vendored edge pollution | map show loses vendored nodes (desired here) | all 9 scanSources consumers |
| D-01-B | semantic post-filter; writeDeps:502 SAME-file-set design is deliberate | import graph keeps vendored | two file sets diverge again (this bug's breeding ground); 4 fields filtered separately | deps.json semantic post-processor |
| D-01-C | hybrid keep-vendored-edges; want "who imports vendored" | externals keeps that info already | option value zeroed by evidence | none found |

why-not: D-01-B — reopens the divergence that caused this bug; D-01-C — killed by externals-preservation evidence and 0 issue-history requests.

### D-02 Legacy polluted peaks — chosen: D-02-A (hard-attribution guidance)

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| D-02-A | peak.owners x map-ignore is machine-checkable (sandbox 2/2) | zero schema change; approve gate/single-consumption/archive audit all preserved | none (hard attribution removes the misguidance case) | gate C4 advisory both branches + CONTRACTS en/zh |
| D-02-B | scan auto-reset; zero user action | zero user action | bypasses reason-match/single-consumption/archive chain; breaks peak monotonicity design | none (killed by product discipline) |
| D-02-C | ignored_fns field; attribution needs pre-stored data | precise | data already exists in peak.owners; schema cost wasted | none (killed by existing data) |

why-not: D-02-B — bypasses the three-layer reset audit chain; D-02-C — duplicates data that already exists.

### D-03 Ship-script exclusion mechanism — chosen: D-03-D (materialized list)

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| D-03-D | scan naturally produces the excluded set; codebase dir census already tracked+regen | glob evaluation single-point in scan; scripts stay pure bash grep -vxFf; no semantic copy | freshness depends on scan (bounded by SHIP order) | scan write + both FILES lines + census entry |
| D-03-A | node filter per run; globMatch single implementation | single truth | extra node process per run; embedded node pipeline in bash | both FILES lines |
| D-03-B | bash native matching; zero dependency | none | dual-implementation drift; `?` semantics divergence | same injection point |
| D-03-C | separate .gos/scan-ignore; intent separation | precise intent | second source of truth; census entry; two lists to maintain | new file + census + scripts |

why-not: D-03-A — dominated by D-03-D (same goal, fewer costs); D-03-B — the dual-implementation breeding ground; D-03-C — no consumer asking for separation.

### D-04 Discoverability — chosen: D-04-A (full chain)

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| D-04-A | zero discoverability is a root cause of this bug family | three touchpoints close the loop (fail-time hint / scan-time notice / doc lookup) | widest change surface (gate + locales + scan output + READMEs) | gate.cjs hints + scan line + README section |
| D-04-B | gate hints only; minimal diff | fast | scan/doc sides stay blind; glob semantics undocumented | two lines in gate.cjs |
| D-04-C | A + doctor item; stale-list machine checks | ops completeness | cost paid before any instance exists | A + doctor.cjs |

why-not: D-04-B — leaves the same class of gap this issue reported; D-04-C — pays complexity with no instance (stale hint can ride the R-04 attribution path).

## Requirements

- **R-01 (D-01)**: `scanSources` applies `loadMapIgnore` (exact + globMatch,
  same semantics as `semanticUniverse`) when collecting files; ignored
  paths never appear in deps.json files/edges/semantic. Empty/absent
  map-ignore → behavior identical to today (regression guard).
- **R-02 (D-03)**: `gos map scan` writes `.gos/codebase/map-ignored.txt`
  when ≥1 file is excluded: sorted relative paths, first line provenance
  (`generated-at <iso> HEAD <sha>`), census entry `git:false npm:false`
  mirroring unmapped-fns. Not written when nothing is excluded. Zero-hit
  map-ignore rules (typos, stale paths) print an advisory line naming the
  dead rule (red-team F-2).
- **R-03 (D-03)**: cleanup-scan.sh and security.sh filter FILES via
  `grep -vxFf` against the list; missing list → current behavior (full
  scan), preserving backward compatibility.
- **R-04 (D-02)**: gate C4 missing-vs-peak advisory attributes missing fns
  via peak.owners × exclusion (list membership, fallback globMatch when
  list is stale by provenance HEAD mismatch — attribution only runs when
  provenance HEAD equals current HEAD, else plain advisory); full coverage
  → guide `gos approve baseline-reset` + `gos map baseline reset`;
  partial → annotate "N of M from ignored paths". CONTRACTS en/zh.
- **R-05 (D-04)**: parse-failures fix hint adds "or exclude vendored paths
  via .gos/map-ignore then rescan"; dup-fn fix hint adds "third-party code
  → exclude via .gos/map-ignore"; scan output gains one line reporting
  excluded count + list path when count > 0; README.md + README.zh-CN.md
  gain a map-ignore section documenting the glob semantics table
  (`*` crosses `/`, bare dir name does not match, `**` ≡ `*`, exact
  full-path match) and the layering vs `.min.js`/skip-dirs.
- **R-06**: no-map-ignore repos are byte-identical in behavior; gate all
  green on the GOS self-repo; `bash test/pack-check.sh` green with the new
  census entry (red-team F-4).

## Red-team disposition (inline, 3 rounds)

- F-1 ignore-as-audit-evasion → PARTIAL: existing guards (tracked input,
  dead-annotation FAIL, excluded-count line) cover the realistic cases;
  ignore-face-mutation alert DEFERRED (no instance)
- F-2 zero-hit rules silent → ACCEPTED into R-02
- F-3 stale list x ship scripts → DEFERRED (SHIP order bounds the window;
  failure direction is conservative); R-04 attribution carries the
  provenance-HEAD guard
- F-4 census x pack-check interaction → ACCEPTED into R-06

## Observable truths

- **T-01**: in a repo with vendored dup-fn JS + `.gos/map-ignore` covering
  it, `gos map scan` then `gos gate codemap` exits green (was: permanent
  red on codemap-dup-fn-name).
- **T-02**: after that scan, `.gos/codebase/map-ignored.txt` exists, first
  line carries generated-at + HEAD, and lists exactly the vendored files.
- **T-03**: cleanup-scan.sh and security.sh report clean on that repo
  (vendored console.log/eval no longer flagged); with the list removed
  they reproduce the old findings (fallback parity).
- **T-04**: a polluted pre-fix peak triggers the guided advisory
  ("fully covered by map-ignore — rotate via approve baseline-reset +
  map baseline reset"), and following it clears the advisory.
- **T-05**: both READMEs contain the map-ignore section (readme-sync
  green); both gate fix hints name map-ignore.
- **T-06**: on the GOS self-repo (no map-ignore), scan/gate output and
  deps.json are unchanged vs pre-fix (regression).

## Out of scope

- Auto-reset of polluted peaks (rejected, D-02)
- New `.gos/scan-ignore` (rejected, D-03)
- doctor checks for stale lists (deferred — stale fallback covered by
  provenance-HEAD guard in R-04)
- Issue #63 data-boundary consent gate (separate concern, P24-adjacent
  family but own lifecycle)
