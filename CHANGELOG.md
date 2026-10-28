# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- Add dialogue governance upgrade: decision cards become 5-column with an Activates column naming the consumer each option turns on, deep-dig exemplars land at skills/gos-think/examples/deep-dig-cases.md with a read-before-first-card pointer in gos instructions think, every card carries a standing deepen line under the new-facts contract, replies follow the plain-narration contract, spec thin-gate v3 adds the spec-gate-card-column and spec-gate-version-unknown failure codes with content-era stamping so in-flight v2 tasks stay unaffected as old specs keep their floor, gos commit think --refreeze recomputes the spec sha without advancing the stage behind a stage-regression-blocked guard, the GOS_SPEC_GATE_FLOOR_OVERRIDE=1 escape stays user-approved only, and the state schema bump to v5 makes older CLIs exit loudly on newer states so a one-time CLI upgrade is required (D-39/R-45) [2026-10-28]
- Fix archive orphan adoption to never touch git-tracked files via a two-tier orphan scan with registry-gap advisory, and cure the concerns sidecar corrosion chain after sidecar loss (R-01) [2026-10-27]
- Fix the sweep ledger extractor prefix-capture defect and rebuild its deleted-id records from repository history, clear anchor-strip punctuation shells across the product tree, close a whitelist ASCII fail-open gap and re-anchor the curated concern ledger after an unanchored write (D-24/D-28/R-43) [2026-10-27]
- Remove anchor fragments left behind by the early sweep batches with deleted ids reconciled into the tracked sweep ledger (D-24/R-43) [2026-10-27]
- Remove legacy anchor comments across the product docs, hooks, scripts and skills with example ids converted to placeholder spellings and deleted ids reconciled into the tracked sweep ledger (D-24/R-43) [2026-10-27]
- Remove legacy anchor comments across the section suite with deleted ids reconciled into the tracked sweep ledger (D-24/R-43) [2026-10-27]
- Remove legacy anchor comments across the test checks, fixtures and golden trees with deleted ids reconciled into the tracked sweep ledger (D-24/R-43) [2026-10-27]
- Remove legacy anchor comments across the bin ops, map, nav and render modules and the CLI entry with deleted ids reconciled into the tracked sweep ledger (D-24/R-43) [2026-10-27]
- Remove legacy anchor comments across the bin core, task and knowledge modules with deleted ids reconciled into the tracked sweep ledger and contract strings pinned as frozen surface (D-24/R-43) [2026-10-27]
- Fix gitprobe HEAD-negative stderr matrix now recognizes the git 2.55 phrasing so clean negatives stop poisoning the fail-closed cache on CI runners (D-12) [2026-10-26]
- Fix review fixes cure machine paths in tracked state by storing task spec and plan paths repo-relative with read-time normalization, and track rollback now sweeps the git index and surfaces incomplete rollbacks (D-12/D-15) [2026-10-26]
- Add self-repo gap migrate cured 88 auto mirrors into the ledger with two deferred anchors parked and full suite green (D-16/D-13) [2026-10-22]
- Add wiring docs and census lifecycle audit with gap-history GOS_PATHS registration and suffixed task-id plan parsing fix (D-14/R-01) [2026-10-22]
- Add self-repo guide trio refreshed to current tree truth with born-at stamps recorded in the evidence ledger (D-19/D-20) [2026-10-22]
- Add changelog validator accepts issue-ref tokens with commit-time neutralization of close-keyword triggers in both commit channels (R-01) [2026-10-22]
- Add navigator bundle renamed to unmapped-fns with generated-at provenance header and THINK context hint (D-19/D-20) [2026-10-22]
- Add gate flip-reconcile leg enforcing census and manifest agreement on tracked dot-gos files (D-15/D-14) [2026-10-22]
- Add gos track flip transaction with validation, census-aware surgery, rollback backups, manifest, adopt and knowledge preset (D-15/D-14) [2026-10-22]
- Add project_root consumers re-pointed to runtime-derived root with anchor fix re-deriving repo_id (D-12) [2026-10-22]
- Add gos gap migrate and history cure auto-mirror concerns lines into a local NDJSON ledger (D-16) [2026-10-22]
- Add repo_id lock guard with remote-set matching and linked-worktree detection (D-12/D-18) [2026-10-22]
- Add English-only language boundary at the write path of the three GOS text stores with gos gap rewrite (D-17) [2026-10-22]
- Add gitprobe fail-closed probe primitive plus schema v4 repo_id identity with lazy migration dropping version and project_root (D-12/D-18) [2026-10-22]
- Add claim-boundary output and seeded-intent status now carry the fresh-session handoff block (R-01) [2026-10-21]
- Add main becomes PR-only locally with GOS_ALLOW_MAIN_PUSH emergency escape plus a CI direct-push alarm job (R-01) [2026-10-20]
- Add census lifecycle entries fix the dead-task-dir false red on fresh checkouts (R-01) [2026-10-20]
- Add push aggregate subject-case parity and machine-local evidence zones fix the red CI commitlint and gate audit lines (R-01) [2026-10-20]
- Add P1 verify pass: all 13 observable truths replay-verified against the post-review tree with enriched receipts (R-01) [2026-10-20]
- Add P1 review fixes seal security tokenizer escapes with dotfile-glob and glued-separator rows plus fail-closed pin, and harden changelog lock, render backup, exemptions symlink guard and evidence veto sets (D-11/D-02) [2026-10-19]
- Add P1 stop-bleed batch: depth-aware security rm gate, widened truth replay evidence with --timeout cap, two-layer config with sentinel deletion, auto-rendered views with manifest reconciliation, changelog-path resolver, render-backup cache relocation, PROJECT.md archive gate, machine-local ledgers with gos logs, issue triage gate (D-11/D-09/D-03/D-02) [2026-10-15]
- Add Milestone trust-repair intake completed: 23 open issues triaged and labelled, 24 requirements mapped across three phases, seeded-asset lifecycle audit filed as issues 18 to 23, milestone archives documented (R-01) [2026-10-14]
- Change Milestone v1.0.0-dev closed with roadmap and requirements archived to milestones and an annotated tag cut, and the successor milestone initialized for the 17 open self-hosting issues across three phases (R-01) [2026-10-13]
- Add delta.md renders spec decision titles for decision-less Lv1/2 archives with provenance marker (R-01) [2026-10-12]
- Add P14 closeout — ascii filename guard wired into CI and gate all beside cjk-lint, plus release process docs at .github/RELEASE.md with dormant benchmark rule (R-01) [2026-10-12]
- Add gos brownfield unified adoption for existing repositories — safe-skip conflicts with tiered overwrite, dormant hooks, guidance-only AGENTS, single-object JSON report (D-88/D-89/D-90/D-91/D-92/D-93/D-94/D-95/D-96/D-97/D-98/D-99/D-100/R-01) [2026-10-12]
- feat: aggregate subjects carry a conventional-format contract enforced at three layers, and gos push converges local main onto the aggregate after success (R-01) [2026-10-09]
- Add gos push distinguishes content divergence from history-rebuild topology divergence via tree containment (R-01) [2026-10-09]
- Add gos push refuses diverged clones instead of silently dropping remote-only content, permission errors are locale-neutral, and the aggregate guard self-test now runs in CI (R-01) [2026-10-09]
- Add gos push aggregates the local atomic chain into one semantic remote commit on main, with a pre-push hook master and CI guard rejecting raw multi-commit, tree-empty, and advance-template pushes (R-01) [2026-10-08]
- Add publish the self-hosted codemap and map mechanism data (D-81): network.md swept and englishized, allowlist + baseline tracked, census split recorded (R-01) [2026-10-08]
- Change P13 complete: full-repo englishization landed and the public history rebuilt as 32 milestone snapshot commits - all seven observable truths replay green, remote force-pushed, benchmark synced (D-74/R-01) [2026-09-30]
- Change P13 waves 1-3: CJK boundary lint + whitelist wired into gate/CI, i18n inventory v2 line-level, CONTRACTS frozen strings migrated to English, all bin/ modules englishized per the audience split - product face bilingual via catalog, contributor face direct English (R-01) [2026-09-29]
- Fix P15 review findings across lessons disposal audit, content-id binding, blast vacuity refusal, and migration backup safety (D-62/D-63/D-64/D-65) [2026-09-28]
- Add P15 beta-feedback UX rebuild: lessons tracked JSON truth with five invariants and per-entry commands, gate failures as structured three-part blocks, zh-CN locale support, gos map blast pre-change impact reports, lessons attribution in status and instructions, decision-card contract in skills (D-62/D-63/D-64/D-65/D-66/D-67, R-01) (R-01) [2026-09-24]
- Add Product integrity batch P12 shipped (D-55/D-56/D-57/D-58/D-59/D-60/D-61) [2026-09-23]
- Add Product integrity batch P12 (D-55/R-48/R-56/R-57/D-56/R-51/D-57/R-52/D-58/R-53/D-59/R-55/D-60/D-61) [2026-09-22]
- Drop T2 nested-fn anchoring from active queue as data-backed YAGNI with boundary fixed in ADR-T2 (D-54) [2026-09-21]
- Add Switch distribution to GitHub Packages private beta as @chenw521/gos (D-50) [2026-09-21]
- Fix review findings across commit guard, changelog lock, semver compare, and archive transaction (D-51/D-53/R-05/R-10) [2026-09-21]
- Add git workflow template asset with seeding command, changelog single-track system, and repository governance foundation (R-01) [2026-09-20]

<!-- New entries accumulate under [Unreleased] and are promoted into a version
     section at release time. Public history begins at 1.0.0-dev: releases
     before it were internal milestones and are not part of this changelog. -->
