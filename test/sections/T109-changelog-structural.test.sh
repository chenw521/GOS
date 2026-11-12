#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/changelog-core.cjs#fn:batchAddsChangelogRecord
# changelog structural-delta predicate (head-vs-base record detection).
# Pure-module section: drives bin/lib/ops/changelog-core.cjs directly, no CLI
# and no task state. Consumers (gate audit / SHIP ritual) assert their own
# wiring in their own sections.
T109_DIR=""

t109_setup() {
  T109_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t109"
  mkdir -p "$T109_DIR" && cd "$T109_DIR" || exit 1
}
t109_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T109_DIR"; }

t109_setup
trap 't109_teardown' EXIT
PASS=0; FAIL=0
echo "--- T109: changelog structural-delta predicate (D-62/R-60) ---"

cat > harness.cjs <<'EOF'
'use strict';
// Drives the module under test and prints one "CASE <id>: OK|FAIL" line per
// assertion group; the bash side turns each line into one assert_contains.
const path = require('path');
const core = require(path.join(process.env.GOS_ROOT, 'bin', 'lib', 'ops', 'changelog-core.cjs'));

const results = []; // every verdict returned, for the shape and reason sweeps

function run(head, base, opts) {
  const r = core.batchAddsChangelogRecord(head, base, opts);
  results.push(r);
  return r;
}

function check(id, fn) {
  try {
    const d = fn();
    if (d === true) console.log(`CASE ${id}: OK`);
    else console.log(`CASE ${id}: FAIL ${String(d).slice(0, 240)}`);
  } catch (e) {
    console.log(`CASE ${id}: FAIL exception: ${e.message}`);
  }
}

const BASE = [
  '# Changelog',
  '',
  'All notable changes to this project are documented in this file.',
  '',
  '## [Unreleased]',
  '',
  '- Fix archive sweep orphan edge (R-44) [2026-11-09]',
  '',
  '## [1.2.0] - 2026-10-20',
  '',
  '- Add lint command shell (R-06) [2026-10-01]',
  '',
  '## [1.1.0] - 2026-08-15',
  '',
  '- Add initial template set (R-02) [2026-08-15]',
  '',
].join('\n');

// head adds one fresh bullet under [Unreleased]
const HEAD_ADDED = BASE.replace(
  '- Fix archive sweep orphan edge (R-44) [2026-11-09]',
  '- Fix archive sweep orphan edge (R-44) [2026-11-09]\n- Add batch changelog record predicate (D-62) [2026-11-10]',
);

// head re-lists a bullet whose text already exists in base (relocated from an
// old version section into [Unreleased]) — no byte of bullet text is new
const HEAD_REWRITTEN = [
  '# Changelog',
  '',
  'All notable changes to this project are documented in this file.',
  '',
  '## [Unreleased]',
  '',
  '- Add initial template set (R-02) [2026-08-15]',
  '',
  '## [1.2.0] - 2026-10-20',
  '',
  '- Add lint command shell (R-06) [2026-10-01]',
  '',
  '## [1.1.0] - 2026-08-15',
  '',
  '- Add initial template set (R-02) [2026-08-15]',
  '',
].join('\n');

// promote shape: [Unreleased] emptied into a brand-new version section and
// entry stamps stripped (the unstamped bullets remain substrings of base)
const HEAD_PROMOTED = [
  '# Changelog',
  '',
  'All notable changes to this project are documented in this file.',
  '',
  '## [Unreleased]',
  '',
  '## [1.3.0] - 2026-11-10',
  '',
  '- Fix archive sweep orphan edge (R-44)',
  '',
  '## [1.2.0] - 2026-10-20',
  '',
  '- Add lint command shell (R-06) [2026-10-01]',
  '',
  '## [1.1.0] - 2026-08-15',
  '',
  '- Add initial template set (R-02) [2026-08-15]',
  '',
].join('\n');

function isFailWithReason(r) {
  return r.ok === false && typeof r.reason === 'string' && r.reason.length > 0;
}

// --- B: structural-delta verdicts --------------------------------------------

check('B1', () => {
  const r = run(HEAD_ADDED, BASE);
  return (r.ok === true && r.reason === null) ? true : JSON.stringify(r);
});

check('B2', () => {
  const r = run(BASE, BASE);
  return isFailWithReason(r) ? true : JSON.stringify(r);
});

check('B3', () => {
  const r = run(HEAD_REWRITTEN, BASE);
  return isFailWithReason(r) ? true : JSON.stringify(r);
});

check('B4', () => {
  const r = run(HEAD_PROMOTED, BASE);
  return (r.ok === true && r.reason === null) ? true : JSON.stringify(r);
});

// --- T: taskRefs filter ------------------------------------------------------

check('B5', () => {
  const r = run(HEAD_ADDED, BASE, { taskRefs: ['R-60'] });
  return isFailWithReason(r) ? true : JSON.stringify(r);
});

check('B6', () => {
  const head = BASE.replace(
    '- Fix archive sweep orphan edge (R-44) [2026-11-09]',
    '- Fix archive sweep orphan edge (R-44) [2026-11-09]\n- Secure push gate against stale locks (D-62, R-60) [2026-11-10]',
  );
  const r = run(head, BASE, { taskRefs: ['R-60'] });
  return (r.ok === true && r.reason === null) ? true : JSON.stringify(r);
});

check('B7', () => {
  const r = run(HEAD_PROMOTED, BASE, { taskRefs: ['R-99'] });
  return isFailWithReason(r) ? true : JSON.stringify(r);
});

// --- F: file-shape fallback (no base snapshot) -------------------------------

check('F1', () => {
  const r = run(HEAD_ADDED, null);
  return (r.ok === true && r.reason === null) ? true : JSON.stringify(r);
});

check('F2', () => {
  const r = run(HEAD_PROMOTED, null);
  return (!r.ok && r.reason === 'unreleased-nonempty') ? true : JSON.stringify(r);
});

check('F3', () => {
  const r = run(HEAD_PROMOTED, BASE, { noBaseText: true });
  return (!r.ok && r.reason === 'unreleased-nonempty') ? true : JSON.stringify(r);
});

// --- R/M/Z: verdict shape, API surface, reason charset -----------------------

check('R1', () => {
  if (results.length < 10) return `too few recorded verdicts: ${results.length}`;
  const bad = results.filter((r) => !(
    typeof r.ok === 'boolean'
    && ((r.ok === true && r.reason === null)
      || (r.ok === false && typeof r.reason === 'string' && r.reason.length > 0))
  ));
  return bad.length === 0 ? true : `bad verdict shape: ${JSON.stringify(bad.slice(0, 3))}`;
});

check('M1', () => (typeof core.batchAddsChangelogRecord === 'function') ? true : 'not exported as a function');

check('M2', () => {
  const a = core.batchAddsChangelogRecord(HEAD_ADDED, BASE, { taskRefs: ['D-62'] });
  const b = core.batchAddsChangelogRecord(HEAD_ADDED, BASE, { taskRefs: ['D-62'] });
  return JSON.stringify(a) === JSON.stringify(b) ? true : `nondeterministic: ${JSON.stringify(a)} vs ${JSON.stringify(b)}`;
});

check('Z1', () => {
  const reasons = results.filter((r) => r && typeof r.reason === 'string').map((r) => r.reason);
  const bad = reasons.filter((m) => !/^[\x20-\x7E]+$/.test(m));
  return bad.length === 0 ? true : `non-printable-ASCII reason: ${JSON.stringify(bad)}`;
});
EOF

set +e; HOUT="$(node harness.cjs 2>&1)"; HRC=$?; set -e

ALL_CASES="B1 B2 B3 B4 B5 B6 B7 F1 F2 F3 R1 M1 M2 Z1"
for c in $ALL_CASES; do
  assert_contains "case $c" "CASE $c: OK" "$HOUT"
done

HFAILS="$(printf '%s\n' "$HOUT" | grep -c ': FAIL' || true)"
echo "--- T109 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ] && [ "$HFAILS" -eq 0 ] && [ "$HRC" -eq 0 ] && [ -n "$HOUT" ]
