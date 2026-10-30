#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/changelog-core.cjs#fn:parseChangelog bin/lib/ops/changelog-core.cjs#fn:validateEntry bin/lib/ops/changelog-core.cjs#fn:validateStructure bin/lib/ops/changelog-core.cjs#fn:promoteUnreleased
# changelog single-source validator core.
# Pure-module section: drives bin/lib/ops/changelog-core.cjs directly, no CLI and
# no task state. The add-generator and lint shell assert same-source
# consumption of this module in their own sections.
T53_DIR=""

t53_setup() {
  T53_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t53"
  mkdir -p "$T53_DIR" && cd "$T53_DIR" || exit 1
}
t53_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T53_DIR"; }

t53_setup
trap 't53_teardown' EXIT
PASS=0; FAIL=0
echo "--- T53: changelog-core validator module (R-05/R-06/R-08) ---"

cat > harness.cjs <<'EOF'
'use strict';
// Drives the module under test and prints one "CASE <id>: OK|FAIL" line per
// assertion group; the bash side turns each line into one assert_contains.
const path = require('path');
const core = require(path.join(process.env.GOS_ROOT, 'bin', 'lib', 'ops', 'changelog-core.cjs'));

const collectedErrors = []; // every rejection message seen, for the zero-CJK sweep

function check(id, fn) {
  try {
    const d = fn();
    if (d === true) console.log(`CASE ${id}: OK`);
    else console.log(`CASE ${id}: FAIL ${String(d).slice(0, 240)}`);
  } catch (e) {
    console.log(`CASE ${id}: FAIL exception: ${e.message}`);
  }
}

function entryReject(id, entry, expectSub) {
  check(id, () => {
    const r = core.validateEntry(entry);
    if (r.ok) return 'accepted but should be rejected';
    if (!r.errors.some((m) => m.includes(expectSub))) return `no error contains '${expectSub}': ${JSON.stringify(r.errors)}`;
    collectedErrors.push(...r.errors);
    return true;
  });
}

function structReject(id, doc, opts, expectSub) {
  check(id, () => {
    const r = core.validateStructure(doc, opts);
    if (r.ok) return 'accepted but should be rejected';
    if (!r.errors.some((m) => m.includes(expectSub))) return `no error contains '${expectSub}': ${JSON.stringify(r.errors)}`;
    collectedErrors.push(...r.errors);
    return true;
  });
}

const DOC_OK = [
  '# Changelog',
  '',
  'All notable changes to this project are documented in this file.',
  '',
  '## [Unreleased]',
  '',
  '- Add shared changelog validator module (D-42) [2026-09-18]',
  '- Fix date stamp stripping in promote (R-08) [2026-09-19]',
  '',
  '## [1.2.0] - 2026-09-01',
  '',
  '- Add lint command shell (R-06) [2026-09-01]',
  '',
  '## [1.1.0] - 2026-08-15',
  '',
  '- Add initial template set (R-02) [2026-08-15]',
  '',
].join('\n');

const DOC_NO_UNREL = [
  '# Changelog',
  '',
  'All notable changes to this project are documented in this file.',
  '',
  '## [1.2.0] - 2026-09-19',
  '',
  '- Add lint command shell (R-06) [2026-09-19]',
  '',
  '## [1.1.0] - 2026-08-15',
  '',
  '- Add initial template set (R-02) [2026-08-15]',
  '',
].join('\n');

// --- A: validateEntry -------------------------------------------------------

check('A0', () => {
  const legal = [
    '- Add shared changelog validator module (D-42) [2026-09-18]',
    '- Fix date stamp stripping in promote (R-08) [2026-09-19]',
    '- CI pin workflow actions to major versions (R-09, D-41) [2026-09-18]',
  ];
  const bad = legal.map((e) => core.validateEntry(e)).filter((r) => !r.ok);
  return bad.length === 0 ? true : `legal entries rejected: ${JSON.stringify(bad)}`;
});

// seven forbidden classes, each with its own fixture
entryReject('A1', '- Add DI-42 guard to the validator (R-05) [2026-09-18]', 'bare DI-');
entryReject('A2', '- Fix parse bug noted in T-53 review (R-06) [2026-09-18]', 'bare T-');
entryReject('A3', '- Change gate order to run semantic checks first (R-06) [2026-09-18] with circled mark \u2460 here', 'circled numeral');
entryReject('A4', '- Fix lint \u00A73 heading check (R-06) [2026-09-18]', 'section marker');
entryReject('A5', '- D-42 adds the shared validator (R-05) [2026-09-18]', 'decision id as grammatical subject');
entryReject('A6a', '- Add validator hardening after red team review (D-42) [2026-09-18]', 'process-narration');
entryReject('A6b', '- Change gate wiring in wave 2 of the rollout (D-43) [2026-09-18]', 'process-narration');
entryReject('A6c', '- P11 wires the registry into the CLI (D-42) [2026-09-18]', 'process-narration');
entryReject('A6d', '- Add \u9636\u6BB5 guard to the runner (D-43) [2026-09-18]', 'process-narration');
entryReject('A7', '- Add validator core module. Also wire lint to it (R-05) [2026-09-18]', 'multi-sentence');

// structural rejections
entryReject('SA', 'Add shared validator (D-42) [2026-09-18]', 'bullet line');
entryReject('SB', '- Makes the validator shared (D-42) [2026-09-18]', 'category verb');
entryReject('SC', '- Add shared validator module [2026-09-18]', 'trace refs');
entryReject('SD', '- Add shared validator (task T53) [2026-09-18]', 'malformed trace refs');
entryReject('SE', '- Add shared validator (D-42)', 'date stamp');
entryReject('SF', '- Add (D-42) [2026-09-18]', 'summary');

// --- V: validateStructure (three checks) -----------------------------------

check('V0', () => {
  const r = core.validateStructure(DOC_OK, { todayUtc: '2026-09-19' });
  return r.ok ? true : `healthy doc rejected: ${JSON.stringify(r.errors)}`;
});

const DOC_TWO_TITLES = DOC_OK + '\n# Duplicate Title\n';
structReject('V1', DOC_TWO_TITLES, { todayUtc: '2026-09-19' }, 'exactly one top-level');

const DOC_ASC_DATES = DOC_OK.replace('2026-09-01', '2026-08-15').replace('## [1.1.0] - 2026-08-15', '## [1.1.0] - 2026-09-01');
structReject('V2', DOC_ASC_DATES, { todayUtc: '2026-09-19' }, 'newest-first');

structReject('V3', DOC_OK, { todayUtc: '2099-01-01' }, "today's obligation");

check('V4', () => {
  const r = core.validateStructure(DOC_NO_UNREL, { todayUtc: '2026-09-19' });
  return r.ok ? true : `obligation via latest version rejected: ${JSON.stringify(r.errors)}`;
});

const DOC_PROMOTE_TODAY = [
  '# Changelog',
  '',
  'All notable changes to this project are documented in this file.',
  '',
  '## [Unreleased]',
  '',
  '## [1.2.0] - 2026-09-19',
  '',
  '- Add lint command shell (R-06)',
  '',
  '## [1.1.0] - 2026-08-15',
  '',
  '- Add initial template set (R-02) [2026-08-15]',
  '',
].join('\n');

check('V4b', () => {
  const r = core.validateStructure(DOC_PROMOTE_TODAY, { todayUtc: '2026-09-19' });
  return r.ok ? true : `same-day promote (empty [Unreleased], stamped entries stripped, section heading dated today) rejected: ${JSON.stringify(r.errors)}`;
});

const DOC_BAD_DATE = DOC_OK.replace('## [1.2.0] - 2026-09-01', '## [1.2.0] - 20260901');
structReject('V5', DOC_BAD_DATE, { todayUtc: '2026-09-19' }, 'valid date');

check('V6', () => {
  // no opts: default today must come from the same utcToday() the add path uses
  const today = core.utcToday();
  const doc = `# Changelog\n\n## [Unreleased]\n\n- Add fresh entry (D-42) [${today}]\n`;
  const r = core.validateStructure(doc);
  return r.ok ? true : `default todayUtc mismatch: ${JSON.stringify(r.errors)}`;
});

// --- P: promoteUnreleased ---------------------------------------------------

check('P1', () => {
  const r = core.promoteUnreleased(DOC_OK, '1.3.0');
  if (!r.ok) return `promote failed: ${JSON.stringify(r)}`;
  const p = core.parseChangelog(r.text);
  const want = ['- Add shared changelog validator module (D-42)', '- Fix date stamp stripping in promote (R-08)'];
  if (p.versions[0].tag !== '1.3.0') return `new tag: ${p.versions[0].tag}`;
  if (p.versions[0].date !== core.utcToday()) return `new date: ${p.versions[0].date}`;
  if (JSON.stringify(p.versions[0].entries) !== JSON.stringify(want)) return `stamped entries not stripped: ${JSON.stringify(p.versions[0].entries)}`;
  if (p.unreleased.length !== 0) return `unreleased not empty: ${JSON.stringify(p.unreleased)}`;
  if (p.versions[1].tag !== '1.2.0' || p.versions[1].entries.length !== 1) return 'old latest version mangled';
  if (!r.text.includes('## [Unreleased]')) return 'unreleased heading dropped';
  return true;
});

check('P2', () => {
  const doc = '# Changelog\n\n## [Unreleased]\n\n## [1.0.0] - 2026-01-01\n\n- Add seed (D-1) [2026-01-01]\n';
  const r = core.promoteUnreleased(doc, '2.0.0');
  return (!r.ok && r.reason === 'nothing-to-release') ? true : JSON.stringify(r);
});

check('P3a', () => {
  const doc = '## [Unreleased]\n\n- Add x (D-1) [2026-09-18]\n\n## [1.0.0] - 2026-01-01\n\n- Add seed (D-1) [2026-01-01]\n';
  const r = core.promoteUnreleased(doc, '1.1.0');
  return (!r.ok && r.reason === 'no-header') ? true : JSON.stringify(r);
});

check('P3b', () => {
  const doc = '# Changelog\n\n## [1.0.0] - 2026-01-01\n\n- Add seed (D-1) [2026-01-01]\n';
  const r = core.promoteUnreleased(doc, '1.1.0');
  return (!r.ok && r.reason === 'no-header') ? true : JSON.stringify(r);
});

check('P4a', () => {
  const r = core.promoteUnreleased(DOC_OK, '1.2.0');
  return (!r.ok && r.reason === 'version-rollback') ? true : JSON.stringify(r);
});

check('P4b', () => {
  const r = core.promoteUnreleased(DOC_OK, '1.0.5');
  return (!r.ok && r.reason === 'version-rollback') ? true : JSON.stringify(r);
});

// Prerelease precedence: 1.2.0-rc.1 < 1.2.0, so promoting it against the
// same latest tag must be refused as rollback (mirrors release-validate.sh).
check('P4c', () => {
  const r = core.promoteUnreleased(DOC_OK, '1.2.0-rc.1');
  return (!r.ok && r.reason === 'version-rollback') ? true : JSON.stringify(r);
});

// Double-digit minor must not compare lexically (1.10.0 > 1.9.0).
check('P4d', () => {
  const doc = '# C\n\n## [Unreleased]\n\n- Add x (R-01) [2026-09-20]\n\n## [1.9.0] - 2026-09-01\n\n- Add y (R-01)\n';
  const ok = core.promoteUnreleased(doc, '1.10.0');
  if (!ok.ok) return JSON.stringify(ok);
  return ok.text.indexOf('## [1.10.0]') < ok.text.indexOf('## [1.9.0]') ? true : 'order wrong';
});

// v-prefix equivalence: v1.3.0 == 1.3.0 numerically, higher than 1.2.0.
check('P4e', () => {
  const r = core.promoteUnreleased(DOC_OK, 'v1.3.0');
  if (!r.ok) return JSON.stringify(r);
  return r.text.includes('## [v1.3.0]') || r.text.includes('## [1.3.0]') ? true : 'version section missing';
});

// --- Q: parseChangelog ------------------------------------------------------

check('Q1', () => {
  const p = core.parseChangelog(DOC_OK);
  if (!p.header.includes('# Changelog')) return 'header missing title';
  if (p.unreleased.length !== 2) return `unreleased count: ${p.unreleased.length}`;
  if (p.versions.length !== 2 || p.versions[0].tag !== '1.2.0' || p.versions[1].tag !== '1.1.0') return `tags: ${JSON.stringify(p.versions.map((v) => v.tag))}`;
  if (p.versions[0].date !== '2026-09-01' || p.versions[1].date !== '2026-08-15') return `dates: ${JSON.stringify(p.versions.map((v) => v.date))}`;
  if (!p.versions[1].entries[0].includes('R-02')) return 'version entries missing';
  return true;
});

check('Q2', () => {
  const p = core.parseChangelog(DOC_NO_UNREL);
  return (p.unreleased.length === 0) ? true : `unreleased should be empty: ${JSON.stringify(p.unreleased)}`;
});

// --- M: API surface + time source -------------------------------------------

check('M1', () => {
  const fns = ['parseChangelog', 'validateEntry', 'validateStructure', 'promoteUnreleased', 'utcToday'];
  const missing = fns.filter((k) => typeof core[k] !== 'function');
  return missing.length === 0 ? true : `not exported as functions: ${missing.join(', ')}`;
});

check('M2', () => /^\d{4}-\d{2}-\d{2}$/.test(core.utcToday()) ? true : `bad utcToday: ${core.utcToday()}`);

// --- Z1: every rejection message is English (zero CJK) ----------------------

check('Z1', () => {
  if (collectedErrors.length < 10) return `too few collected errors: ${collectedErrors.length}`;
  const bad = collectedErrors.filter((m) => /[\u4e00-\u9fff]/.test(m));
  return bad.length === 0 ? true : `CJK in error messages: ${JSON.stringify(bad.slice(0, 3))}`;
});
EOF

set +e; HOUT="$(node harness.cjs 2>&1)"; HRC=$?; set -e

ALL_CASES="A0 A1 A2 A3 A4 A5 A6a A6b A6c A6d A7 SA SB SC SD SE SF V0 V1 V2 V3 V4 V4b V5 V6 P1 P2 P3a P3b P4a P4b P4c P4d P4e Q1 Q2 M1 M2 Z1"
for c in $ALL_CASES; do
  assert_contains "case $c" "CASE $c: OK" "$HOUT"
done

# Z2: the module source itself must contain zero CJK (comments included)
CJK_HITS="$(grep -rlP '[\x{4e00}-\x{9fff}]' "$GOS_ROOT/bin/lib/ops/changelog-core.cjs" 2>/dev/null || true)"
if [ -z "$CJK_HITS" ]; then
  echo "  ✓ Z2 module source contains zero CJK"; PASS=$((PASS+1))
else
  echo "  ✗ Z2 CJK found in module source: $CJK_HITS"; FAIL=$((FAIL+1))
fi

HFAILS="$(printf '%s\n' "$HOUT" | grep -c ': FAIL' || true)"
echo "--- T53 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ] && [ "$HFAILS" -eq 0 ] && [ "$HRC" -eq 0 ] && [ -n "$HOUT" ]
