#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/changelog-core.cjs#fn:neutralizeIssueTriggers
# T101: #N tokens — changelog validator accepts issue references in bullets,
# and close/fix keywords adjacent to #N are neutralized at the commit choke
# points (commit.cjs message build + push.cjs aggregate) so a gos commit can
# never close a GitHub issue by accident (R-01).
# Cases: A=validator acceptance N=neutralizer unit C=commit channel
#        P=aggregate channel V=changelog add/lint E2E S=single-source static
T101_DIR=""

t101_new() {
  T101_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t101"
  mkdir -p "$T101_DIR" && cd "$T101_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t101-seed
  GOS_HEADLESS=1 node "$GOS" init 1 "t101 issue tokens" >/dev/null 2>&1
}

t101_psetup() {
  T101_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t101"
  mkdir -p "$T101_DIR" || exit 1
  git init -q --bare "$T101_DIR/origin.git"
  git init -q -b main "$T101_DIR/work"
  cd "$T101_DIR/work" || exit 1
  git remote add origin "$T101_DIR/origin.git"
  echo base > root.txt && git add root.txt && git commit -q -m "chore: seed base" || exit 1
  git push -q origin HEAD:refs/heads/main || exit 1
  git fetch -q origin || exit 1
}

t101_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T101_DIR"; }

PASS=0; FAIL=0
echo "--- T101: #N tokens + commit-time neutralization ---"

TRIGGER_GREP='(fix(es|ed)?|clos(e|es|ed)|resolv(e|es|ed))[[:space:]]+#[0-9]+'

t101_no_trigger() { # label text
  if printf '%s' "$2" | grep -Eqi "$TRIGGER_GREP"; then
    echo "  ✗ $1 (trigger sequence present)"; FAIL=$((FAIL+1))
  else
    echo "  ✓ $1"; PASS=$((PASS+1))
  fi
}

# ===== A: validator accepts #N — inline, issue-ref group; obligation intact =====
node -e "
const cc = require('$GOS_ROOT/bin/lib/ops/changelog-core.cjs');
const r1 = cc.validateEntry('- Fix harden parser against rewind fixes #12 (R-01) [2026-10-22]');
console.log(r1.ok ? 'A1-OK' : 'A1-FAIL ' + r1.errors.join('; '));
const r2 = cc.validateEntry('- Fix parser flaw (#24) (R-01) [2026-10-22]');
console.log(r2.ok ? 'A2-OK' : 'A2-FAIL ' + r2.errors.join('; '));
const r3 = cc.validateEntry('- Fix parser flaw (#24) [2026-10-22]');
console.log(!r3.ok && r3.errors.some((e) => e.includes('missing required trace refs')) ? 'A3-OK' : 'A3-FAIL ' + r3.errors.join('; '));
const r4 = cc.validateEntry('- Fix mixed group (#24, R-01) [2026-10-22]');
console.log(!r4.ok && r4.errors.some((e) => e.includes('malformed trace refs')) ? 'A4-OK' : 'A4-FAIL ' + r4.errors.join('; '));
const r5 = cc.validateEntry('- Fix bare task id T-9 (R-01) [2026-10-22]');
console.log(!r5.ok ? 'A5-OK' : 'A5-FAIL (T-n token ban loosened)');
" > t101-a.out 2>&1
for c in A1 A2 A3 A4 A5; do
  if grep -q "^$c-OK$" t101-a.out; then echo "  ✓ $c validator verdict"; PASS=$((PASS+1));
  else echo "  ✗ $c validator verdict: $(grep "^$c-" t101-a.out)"; FAIL=$((FAIL+1)); fi
done

# ===== N: neutralizer unit — keyword set, CI, whitespace, passthrough =====
node -e "
const cc = require('$GOS_ROOT/bin/lib/ops/changelog-core.cjs');
const n = cc.neutralizeIssueTriggers;
if (typeof n !== 'function') { console.log('N0-FAIL export missing'); process.exit(0); }
console.log('N0-OK');
const eq = (id, got, want) => console.log(got === want ? id + '-OK' : id + '-FAIL got=\"' + got + '\" want=\"' + want + '\"');
eq('N1', n('fixes #12'), 'refs #12');
eq('N2', n('Fixed  #3'), 'refs  #3');
eq('N3', n('Closes #7'), 'refs #7');
eq('N4', n('resolved #42'), 'refs #42');
eq('N5', n('refs #12'), 'refs #12');
eq('N6', n('refixes #12 stays'), 'refixes #12 stays');
eq('N7', n('fixing #12 stays'), 'fixing #12 stays');
const multi = n('chore(task): advance build — guard fixes #12\n\nDecisions: none\ncloses #13 in body');
console.log(multi === 'chore(task): advance build — guard refs #12\n\nDecisions: none\nrefs #13 in body' ? 'N8-OK' : 'N8-FAIL got=' + JSON.stringify(multi));
" > t101-n.out 2>&1
for c in N0 N1 N2 N3 N4 N5 N6 N7 N8; do
  if grep -q "^$c-OK$" t101-n.out; then echo "  ✓ $c neutralizer verdict"; PASS=$((PASS+1));
  else echo "  ✗ $c neutralizer verdict: $(grep "^$c-" t101-n.out)"; FAIL=$((FAIL+1)); fi
done

# ===== C: commit channel — subject with `fixes #12` lands neutralized =====
t101_new
set +e; OUT=$(node "$GOS" commit intent --subject "harden token guard fixes #12" 2>&1); RC=$?; set -e
assert_exit "C1 commit with trigger subject rc" 0 "$RC"
CMSG="$(git log -1 --format=%B)"
assert_contains "C2 committed message carries refs #12" "refs #12" "$CMSG"
t101_no_trigger "C3 committed message has no trigger sequence" "$CMSG"
t101_teardown

# ===== P: aggregate channel — derived bullets + --message both neutralized =====
t101_psetup
printf '# Changelog\n\n## [Unreleased]\n\n- feat: aggregate token guard fixes #12 (D-83) [2026-10-08]\n- Fix follow-up closes #13 (R-02) [2026-10-08]\n' > CHANGELOG.md
git add CHANGELOG.md && git commit -q -m "docs: changelog entry" || exit 1
echo a > a.txt && git add a.txt && git commit -q -m "feat: a" || exit 1
set +e; OUT=$(node "$GOS" push 2>&1); RC=$?; set -e
assert_exit "P1 aggregate push with trigger bullets rc" 0 "$RC"
git fetch -q origin
PMSG="$(git log -1 --format=%B origin/main)"
assert_contains "P2 aggregate subject neutralized" "refs #12" "$PMSG"
assert_contains "P3 aggregate body bullet neutralized" "refs #13" "$PMSG"
t101_no_trigger "P4 aggregate message has no trigger sequence" "$PMSG"
echo n4 > n4.txt && git add n4.txt && git commit -q -m "feat: n4" || exit 1
set +e; OUT=$(node "$GOS" push --message "fix(ops): closes #34 manually" 2>&1); RC=$?; set -e
assert_exit "P5 --message push rc" 0 "$RC"
git fetch -q origin
PMSG2="$(git log -1 --format=%B origin/main)"
assert_contains "P6 explicit message neutralized" "refs #34" "$PMSG2"
t101_no_trigger "P7 explicit message has no trigger sequence" "$PMSG2"
t101_teardown

# ===== P2: untouched `refs #N` passes through (no double transform) =====
t101_psetup
printf '# Changelog\n\n## [Unreleased]\n\n- feat: keep plain refs #12 intact (D-83) [2026-10-08]\n' > CHANGELOG.md
git add CHANGELOG.md && git commit -q -m "docs: changelog entry" || exit 1
echo r > r.txt && git add r.txt && git commit -q -m "feat: r" || exit 1
set +e; OUT=$(node "$GOS" push 2>&1); RC=$?; set -e
assert_exit "P8 refs passthrough push rc" 0 "$RC"
git fetch -q origin
assert_eq "P9 refs #12 subject passes through untouched" "feat: keep plain refs #12 intact" "$(git log -1 --format=%s origin/main)"
t101_teardown

# ===== V: changelog add + lint E2E — #N content accepted verbatim =====
t101_new
set +e; OUT=$(node "$GOS" changelog add --summary "harden rewind fixes #12" --type Fix 2>&1); RC=$?; set -e
assert_exit "V1 add with inline fixes #12 rc" 0 "$RC"
if grep -qF 'Fix harden rewind fixes #12 (R-01)' CHANGELOG.md; then echo "  ✓ V2 bullet written verbatim (validator accepted)"; PASS=$((PASS+1)); else echo "  ✗ V2 bullet missing or mangled"; FAIL=$((FAIL+1)); fi
set +e; OUT=$(node "$GOS" changelog add --summary "issue group (#24) acceptance" --type Fix 2>&1); RC=$?; set -e
assert_exit "V3 add with (#24) group rc" 0 "$RC"
if grep -qF '(#24)' CHANGELOG.md; then echo "  ✓ V4 issue-ref group written"; PASS=$((PASS+1)); else echo "  ✗ V4 issue-ref group rejected"; FAIL=$((FAIL+1)); fi
set +e; OUT=$(node "$GOS" changelog lint 2>&1); RC=$?; set -e
assert_exit "V5 lint over #N bullets rc" 0 "$RC"
t101_teardown

# ===== S: single-source — both channels consume the shared neutralizer =====
for f in bin/lib/ops/changelog-core.cjs bin/lib/task/commit.cjs bin/lib/ops/push.cjs; do
  if grep -q 'neutralizeIssueTriggers' "$GOS_ROOT/$f"; then echo "  ✓ S1 $f wired to the shared neutralizer"; PASS=$((PASS+1));
  else echo "  ✗ S1 $f missing the shared neutralizer"; FAIL=$((FAIL+1)); fi
done

echo "--- T101 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
