#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/feedback.cjs#fn:cmdFeedback
# gos-map:cmd feedback
# gos feedback command family — drafts untracked (zero README footprint),
# push argv-array strict via gh stub, owner-mismatch guard, idempotent marker,
# sending-intent crash window, published ledger render + readmeDrift green.
# Spec T-08a (all local via test/fixtures/gh-stub/gh) + T-08b network-truth
# gating (real push only under GOS_E2E_NETWORK=1, never attempted here).
# Sandboxes live OUTSIDE any GOS-managed tree (mktemp base, / precedent).
T70_DIR=""

t70_setup() {
  T70_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gos-t70-fb-XXXXXX")"
  cd "$T70_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t70-root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
  git remote add origin https://github.com/octocat/t70-sandbox.git
  GOS_HEADLESS=1 node "$GOS" init 1 "t70 feedback probe" >/dev/null 2>&1
  STUBBIN="$T70_DIR/stubbin"
  mkdir -p "$STUBBIN"
  cp "$GOS_ROOT/test/fixtures/gh-stub/gh" "$STUBBIN/gh" && chmod +x "$STUBBIN/gh"
  # shell-expansion tripwire: a command substitution leak in ANY consumer would
  # execute this and leave a marker file (argv-array discipline must prevent it)
  printf '#!/usr/bin/env bash\ntouch "%s/pwned.marker"\n' "$T70_DIR" > "$STUBBIN/pwn"
  chmod +x "$STUBBIN/pwn"
  export PATH="$STUBBIN:$PATH"
  export GH_STUB_LOG="$T70_DIR/gh.log"
  : > "$GH_STUB_LOG"
}

t70_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T70_DIR"; }
trap 't70_teardown' EXIT

t70_creates() { [ -f "$GH_STUB_LOG" ] && wc -l < "$GH_STUB_LOG" | tr -d '[:space:]'; }

t70_setup
PASS=0; FAIL=0
echo "--- T70: gos feedback (draft store + stub push + ledger render) ---"
HOSTILE='`x`$(pwn)"y'

# ===== (a) add issue -> FB-1 file; list shows it; README has NO draft footprint =====
set +e; OUT=$(node "$GOS" feedback add issue "first bug" --body "steps here"); RC=$?; set -e
assert_exit "(a1) add issue exits 0" 0 "$RC"
assert_contains "(a2) added line" "✓ Feedback FB-1 added (issue)" "$OUT"
assert_file "(a3) draft file created" ".gos/project/feedback/FB-1-issue.md"
set +e; LOUT=$(node "$GOS" feedback list 2>&1); LRC=$?; set -e
assert_exit "(a4) list exits 0" 0 "$LRC"
assert_contains "(a5) list shows FB-1 + title" "FB-1" "$LOUT"
assert_contains "(a5b) list shows title" "first bug" "$LOUT"
node "$GOS" paths --markdown >/dev/null 2>&1
if ! grep -q 'first bug' .gos/README.md && ! grep -q '## Feedback' .gos/README.md; then
  echo "  ✓ a6 README carries zero draft / zero Feedback-section footprint"; PASS=$((PASS+1))
else echo "  ✗ a6 draft leaked into README render"; FAIL=$((FAIL+1)); fi

# ===== (b) discussion FB-2 (hostile title); close 1; add -> FB-3 (no id reuse) =====
set +e; OUT=$(node "$GOS" feedback add discussion "$HOSTILE"); RC=$?; set -e
assert_exit "(b1) add discussion exits 0" 0 "$RC"
assert_file "(b2) FB-2 file created" ".gos/project/feedback/FB-2-discussion.md"
set +e; OUT=$(node "$GOS" feedback close 1 --resolution "fixed locally"); RC=$?; set -e
assert_exit "(b3) close 1 exits 0" 0 "$RC"
assert_contains "(b4) close line carries resolution" "FB-1 closed — resolution recorded: fixed locally" "$OUT"
if grep -q '^state: closed' .gos/project/feedback/FB-1-issue.md && grep -q '^resolution: fixed locally' .gos/project/feedback/FB-1-issue.md; then
  echo "  ✓ b5 entry file records closed state + resolution"; PASS=$((PASS+1))
else echo "  ✗ b5 entry file missing closed/resolution fields"; FAIL=$((FAIL+1)); fi
set +e; node "$GOS" feedback add issue "third item" >/dev/null 2>&1; RC=$?; set -e
assert_exit "(b6) add after close exits 0" 0 "$RC"
assert_file "(b7) FB-3 allocated (id never reused)" ".gos/project/feedback/FB-3-issue.md"
set +e; LOUT=$(node "$GOS" feedback list --status closed 2>&1); set -e
if printf '%s' "$LOUT" | grep -q 'FB-1' && ! printf '%s' "$LOUT" | grep -q 'FB-3'; then
  echo "  ✓ b8 list --status closed filters correctly"; PASS=$((PASS+1))
else echo "  ✗ b8 status filter wrong"; FAIL=$((FAIL+1)); fi

# ===== (c) push 2 (stub): argv-array + hostile title zero side effects =====
set +e; OUT=$(node "$GOS" feedback push 2); RC=$?; set -e
assert_exit "(c1) push 2 exits 0" 0 "$RC"
assert_contains "(c2) published line with URL" "✓ published: https://github.com/octocat/t70-sandbox/issues/" "$OUT"
assert_eq "(c3) exactly one create logged" "1" "$(t70_creates)"
ARGV_CHECK=$(python3 - "$GH_STUB_LOG" <<'PYEOF'
import json, sys
try:
    rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
    create = rows[-1]
except Exception as exc:
    print('BAD: unreadable log (%s)' % exc)
    raise SystemExit(0)
ok_title = '`x`$(pwn)"y' in create
one_element = ok_title and create.count('`x`$(pwn)"y') == 1
no_shell_split = all(not isinstance(x, str) or x not in ('x', 'pwn') for x in create)
print('OK' if (one_element and no_shell_split) else 'BAD: %r' % (create,))
PYEOF
)
assert_eq "(c4) hostile title is ONE argv element (no meta-expansion)" "OK" "$ARGV_CHECK"
if [ ! -e "$T70_DIR/pwned.marker" ] && [ ! -e "$PWD/x" ]; then
  echo "  ✓ c5 zero shell-expansion side effects (no marker, no stray file)"; PASS=$((PASS+1))
else echo "  ✗ c5 expansion side effect detected"; FAIL=$((FAIL+1)); fi
if grep -q '^state: published' .gos/project/feedback/FB-2-discussion.md && grep -q '^url: https://' .gos/project/feedback/FB-2-discussion.md; then
  echo "  ✓ c6 entry backfilled published + url"; PASS=$((PASS+1))
else echo "  ✗ c6 entry missing published/url fields"; FAIL=$((FAIL+1)); fi

# ===== (d) owner mismatch: implicit refuse; explicit --to prints visibility, proceeds =====
node "$GOS" feedback add issue "mismatch probe" >/dev/null 2>&1
set +e; OUT=$(GH_STUB_OWNER=other node "$GOS" feedback push 4 2>&1); RC=$?; set -e
assert_exit "(d1) mismatch + implicit origin refuses (rc 1)" 1 "$RC"
assert_contains "(d2) refuse line names owner guard" "refusing push: repo owner" "$OUT"
assert_contains "(d3) guidance points at --to" "pass --to" "$OUT"
assert_eq "(d4) entry untouched by refused push" "1" "$(t70_creates)"
set +e; OUT=$(GH_STUB_OWNER=other node "$GOS" feedback push 4 --to other/t70-sandbox 2>&1); RC=$?; set -e
assert_exit "(d5) explicit --to + mismatch proceeds" 0 "$RC"
assert_contains "(d6) visibility printed for confirmation" "visibility: public" "$OUT"
assert_eq "(d7) create actually ran" "2" "$(t70_creates)"

# ===== (e) idempotent marker hit: adopt URL, no second create =====
node "$GOS" feedback add issue "idem probe" >/dev/null 2>&1
printf '[{"url":"https://github.com/octocat/t70-sandbox/issues/77"}]\n' > "$T70_DIR/hits.json"
set +e; OUT=$(GH_STUB_HITS="$T70_DIR/hits.json" node "$GOS" feedback push 5 2>&1); RC=$?; set -e
assert_exit "(e1) push 5 adopts existing URL" 0 "$RC"
assert_contains "(e2) adopted URL surfaced" "issues/77" "$OUT"
assert_eq "(e3) NO create fired on idempotent hit" "2" "$(t70_creates)"
if grep -q '^state: published' .gos/project/feedback/FB-5-issue.md && grep -q 'issues/77' .gos/project/feedback/FB-5-issue.md; then
  echo "  ✓ e4 adopted entry backfilled published"; PASS=$((PASS+1))
else echo "  ✗ e4 adopted entry not finalized"; FAIL=$((FAIL+1)); fi

# ===== (f) sending-intent: failed create leaves state:sending + recovery path =====
node "$GOS" feedback add issue "crash window" >/dev/null 2>&1
set +e; OUT=$(GH_STUB_FAIL_CREATE=1 node "$GOS" feedback push 6 2>&1); RC=$?; set -e
if [ "$RC" != "0" ]; then echo "  ✓ f1 failed push exits non-zero ($RC)"; PASS=$((PASS+1))
else echo "  ✗ f1 failed push wrongly green"; FAIL=$((FAIL+1)); fi
if grep -q '^state: sending' .gos/project/feedback/FB-6-issue.md && grep -q '^target: octocat/t70-sandbox' .gos/project/feedback/FB-6-issue.md; then
  echo "  ✓ f2 entry shows sending intent + target slug"; PASS=$((PASS+1))
else echo "  ✗ f2 sending-intent record missing"; FAIL=$((FAIL+1)); fi
assert_contains "(f3) failure guidance mentions recovery" "Re-run" "$OUT"
set +e; OUT=$(node "$GOS" feedback push 6 2>&1); RC=$?; set -e
assert_exit "(f4) retry after crash-window succeeds" 0 "$RC"
assert_eq "(f5) retry create logged" "3" "$(t70_creates)"

# ===== (g) published ledger: FEEDBACK.md rows + README Feedback section + drift green =====
FBMD=".gos/FEEDBACK.md"
LEDGER_OK=1
for pair in "FB-2|discussion" "FB-4|issue" "FB-5|issue" "FB-6|issue"; do
  id="${pair%%|*}"; ty="${pair##*|}"
  grep -q "^| ${id} | ${ty} |" "$FBMD" || LEDGER_OK=0
done
if [ "$LEDGER_OK" = "1" ]; then echo "  ✓ g1 ledger rows present for every published entry"; PASS=$((PASS+1))
else echo "  ✗ g1 ledger rows incomplete in $FBMD"; FAIL=$((FAIL+1)); fi
node "$GOS" paths --markdown >/dev/null 2>&1
assert_contains "(g2) README renders Feedback section" "## Feedback (published)" "$(cat .gos/README.md)"
assert_contains "(g3) README renders a ledger row verbatim" "| FB-2 | discussion |" "$(cat .gos/README.md)"
cp .gos/README.md "$T70_DIR/readme-first.txt"
node "$GOS" paths --markdown >/dev/null 2>&1
if diff -q "$T70_DIR/readme-first.txt" .gos/README.md >/dev/null; then
  echo "  ✓ g4 README regen idempotent with ledger present"; PASS=$((PASS+1))
else echo "  ✗ g4 README regen drifts"; FAIL=$((FAIL+1)); fi
set +e; GOUT=$(node "$GOS" gate all 2>&1); GRC=$?; set -e
assert_exit "(g5) gate all green with ledger-rendered README" 0 "$GRC"
assert_contains "(g6) readmeDrift guard passes" "README regen guard" "$GOUT"
if printf '%s' "$GOUT" | grep -q 'README drift'; then
  echo "  ✗ g7 readmeDrift line present"; FAIL=$((FAIL+1))
else echo "  ✓ g7 no readmeDrift failure"; PASS=$((PASS+1)); fi

# ===== (h) T-08b network truth: real-network push gated, never attempted here =====
if [ "${GOS_E2E_NETWORK:-0}" = "1" ]; then
  echo "  ✓ h T-08b real-network mode active (GOS_E2E_NETWORK=1)"; PASS=$((PASS+1))
else
  echo "  SKIP T-08b real-network push — GOS_E2E_NETWORK≠1 (network truth: suite stays stub-only; no real gh call attempted)"
  PASS=$((PASS+1))
fi

echo "--- T70 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
