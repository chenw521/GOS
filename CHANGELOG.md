# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
