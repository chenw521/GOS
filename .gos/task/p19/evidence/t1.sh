#!/usr/bin/env bash
# T-01 evidence: structural obligation across midnight (stale stamp + new bullet)
R=$(git rev-parse --show-toplevel)
c=$(node -e '
const c = require(process.argv[1] + "/bin/lib/ops/changelog-core.cjs");
const head = "# L\n\n## [Unreleased]\n\n- Add fresh entry (D-61) [2026-11-09]\n";
const base = "# L\n\n## [Unreleased]\n\n- Add old entry (D-61) [2026-11-09]\n";
const pass = c.batchAddsChangelogRecord(head, base, { taskRefs: ["D-61"] });
const fail = c.batchAddsChangelogRecord(base, base, { taskRefs: ["D-61"] });
console.log("pass=" + (pass.ok ? 1 : 0) + " fail=" + (!fail.ok ? 1 : 0));' "$R")
echo "T1 $c"
