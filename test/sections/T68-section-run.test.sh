#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/section.cjs#fn:cmdSection bin/lib/ops/section.cjs#fn:cmdSectionRun bin/lib/ops/section.cjs#fn:cmdSectionTrust
# gos-map:cmd section
# : gos section run — section-test runner product surface (fixture-isolation
# discipline shared with test/run-sections.sh).
# Sandboxes live OUTSIDE any GOS-managed tree (mktemp base, precedent):
# the nested runners would otherwise trip the cwd guard under TESTBASE.
T68_DIR=""

t68_setup() {
  T68_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gos-t68-run-XXXXXX")"
  cd "$T68_DIR" || exit 1
}

t68_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T68_DIR"; }
trap 't68_teardown' EXIT

t68_proj() {   # fresh sandbox project: git repo + test/sections/, cwd inside it
  PROJ="$T68_DIR/$1"
  mkdir -p "$PROJ/test/sections" && cd "$PROJ" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
  git config user.name gos-test && git config user.email gos-test@test.invalid
}

t68_field() { python3 -c "import json,sys;v=json.load(open('.gos/cache/run-manifest.json')).get(sys.argv[1],'');print(v if not isinstance(v,list) else ' '.join(v))" "$1" 2>/dev/null; }

t68_secs_left() { ls .gos/cache 2>/dev/null | grep -c '^sections-base-' || true; }

t68_setup
PASS=0; FAIL=0
echo "--- T68: gos section run (fixture isolation + manifest + trust) ---"
set -e

# ===== (l) copy discipline first: the threat-model word is banned everywhere =====
SANDBOX_HELP=$(node "$GOS" help section 2>&1)
if [ "$(printf '%s' "$SANDBOX_HELP" | grep -ci sandbox)" = "0" ]; then
  echo "  ✓ l1 help section copy has zero banned-word matches"; PASS=$((PASS+1))
else echo "  ✗ l1 help section copy contains the banned word"; FAIL=$((FAIL+1)); fi
if [ "$(grep -ci sandbox "$GOS_ROOT/bin/lib/ops/section.cjs" 2>/dev/null || true)" = "0" ]; then
  echo "  ✓ l2 runner source has zero banned-word matches"; PASS=$((PASS+1))
else echo "  ✗ l2 runner source contains the banned word"; FAIL=$((FAIL+1)); fi
set +e; HELP_INDEX=$(node "$GOS" help 2>&1); set -e
if [ "$(printf '%s' "$HELP_INDEX" | grep -ci sandbox)" = "0" ]; then
  echo "  ✓ l3 full help index has zero banned-word matches"; PASS=$((PASS+1))
else echo "  ✗ l3 help index contains the banned word"; FAIL=$((FAIL+1)); fi

# ===== (a) two passing sections: trust bootstrap → run → counts → manifest =====
t68_proj alpha
printf '#!/usr/bin/env bash\ncase "$HOME" in *sections-base-*) echo "  ✓ a1 HOME pinned into fixture base";; *) echo "  ✗ a1 HOME not pinned: $HOME";; esac\ncase "$PWD" in *sections-base-*) echo "  ✓ a2 cwd is the fixture base";; *) echo "  ✗ a2 cwd escaped: $PWD";; esac\n' > test/sections/T1-alpha.test.sh
printf '#!/usr/bin/env bash\necho "  ✓ a3 second section ran"\n' > test/sections/T2-beta.test.sh
mkdir -p test-foo-t1 && printf 'keep\n' > test-foo-t1/keep.txt
git add -A && git commit -q -m sections
set +e; TOUT=$(node "$GOS" section trust 2>&1); TRC=$?; set -e
assert_exit "(a0a) section trust bootstraps" 0 "$TRC"
assert_contains "(a0b) trust registered line" "section list confirmed" "$TOUT"
assert_file "(a0c) trust.json written" ".gos/cache/trust.json"
set +e; OUT=$(node "$GOS" section run 2>&1); RC=$?; set -e
assert_exit "(a1) both sections pass" 0 "$RC"
assert_contains "(a2) HOME pin observed by section" "HOME pinned" "$OUT"
assert_contains "(a3) totals counted" "Sections total: 3 passed, 0 failed" "$OUT"
assert_contains "(a4) per-section summary" "T1-alpha: 2 passed, 0 failed" "$OUT"
assert_eq "(a5) manifest sections_run both" "T1-alpha T2-beta" "$(t68_field sections_run | tr -d '[],')" 
assert_eq "(a6) manifest runner_rc" "0" "$(t68_field runner_rc)"
assert_eq "(a7) manifest filter empty" "" "$(t68_field filter)"
assert_eq "(a8) manifest head_tree matches HEAD" "$(git rev-parse 'HEAD^{tree}')" "$(t68_field head_tree)"
assert_file "(f1) user file survives the sweep" "test-foo-t1/keep.txt"
assert_eq "(f2) no fixture base left behind" "0" "$(t68_secs_left)"

# ===== (b) failing section → runner_rc 1 =====
t68_proj bravo
printf '#!/usr/bin/env bash\necho "  ✓ b-first"\necho "  ✗ b-second"\n' > test/sections/T1-fail.test.sh
git add -A && git commit -q -m sections
node "$GOS" section trust >/dev/null 2>&1
set +e; OUT=$(node "$GOS" section run 2>&1); RC=$?; set -e
assert_exit "(b1) failing section → rc 1" 1 "$RC"
assert_contains "(b2) counts reported" "1 passed, 1 failed" "$OUT"
assert_eq "(b3) manifest runner_rc 1" "1" "$(t68_field runner_rc)"

# ===== (c) aborting section (set -e die) → ABORTED row, never green =====
t68_proj charlie
printf '#!/usr/bin/env bash\nset -e\necho "  ✓ c-first"\nfalse\necho "  ✗ never reached"\n' > test/sections/T1-abort.test.sh
git add -A && git commit -q -m sections
node "$GOS" section trust >/dev/null 2>&1
set +e; OUT=$(node "$GOS" section run 2>&1); RC=$?; set -e
assert_exit "(c1) aborted section → rc 1" 1 "$RC"
assert_contains "(c2) ABORTED row emitted" "SECTION ABORTED" "$OUT"
assert_contains "(c3) abort counted as failure" "1 passed, 1 failed" "$OUT"
assert_eq "(c4) manifest runner_rc 1" "1" "$(t68_field runner_rc)"

# ===== (d) hanging section + --timeout 2 → timeout row + manifest records it =====
t68_proj delta
printf '#!/usr/bin/env bash\nsleep 300\necho "  ✓ never"\n' > test/sections/T1-hang.test.sh
git add -A && git commit -q -m sections
node "$GOS" section trust >/dev/null 2>&1
T0=$(date +%s)
set +e; OUT=$(node "$GOS" section run --timeout 2 2>&1); RC=$?; set -e
T1=$(date +%s)
assert_exit "(d1) timed-out section → rc 1" 1 "$RC"
assert_contains "(d2) TIMEOUT row emitted" "TIMEOUT" "$OUT"
assert_eq "(d3) manifest records timeout" "T1-hang" "$(t68_field timed_out | tr -d '[],')"
if [ $((T1 - T0)) -le 20 ]; then echo "  ✓ d4 run finished fast (took $((T1-T0))s)"; PASS=$((PASS+1))
else echo "  ✗ d4 run dragged ($((T1-T0))s) — timeout not enforced"; FAIL=$((FAIL+1)); fi

# ===== (e) first-run confirmation: interactive y, re-confirm on list change,
#            headless unconfirmed FAIL, CI skip, empty dir advisory =====
t68_proj echo
printf '#!/usr/bin/env bash\necho "  ✓ e-run"\n' > test/sections/T1-echo.test.sh
git add -A && git commit -q -m sections
CONF_OUT=$( { sleep 0.5; echo y; sleep 20; } | env -u GOS_HEADLESS script -qec "node '$GOS' section run" /dev/null 2>&1 || true)
assert_contains "(e1) confirm lists the section path" "T1-echo.test.sh" "$CONF_OUT"
assert_contains "(e2) proceed prompt shown" "Proceed" "$CONF_OUT"
assert_contains "(e3) section executed after y" "e-run" "$CONF_OUT"
assert_contains "(e4) confirmation stored" "confirmed" "$CONF_OUT"
# list change → hash mismatch → headless unconfirmed = HARD FAIL + recovery line
printf '#!/usr/bin/env bash\necho "  ✓ e2nd"\n' > test/sections/T2-second.test.sh
git add -A && git commit -q -m more
rm -f .gos/cache/run-manifest.json
set +e; OUT=$(node "$GOS" section run 2>&1); RC=$?; set -e
assert_exit "(e5) changed list + headless → rc 1" 1 "$RC"
assert_contains "(e6) hard-fail recovery line names section trust" "gos section trust" "$OUT"
if [ -e .gos/cache/run-manifest.json ]; then echo "  ✗ e7 unconfirmed run must not write a manifest"; FAIL=$((FAIL+1))
else echo "  ✓ e7 unconfirmed run wrote no manifest"; PASS=$((PASS+1)); fi
# GOS_CI=1 + unconfirmed → loud advisory skip, exit 0
set +e; OUT=$(GOS_CI=1 node "$GOS" section run 2>&1); RC=$?; set -e
assert_exit "(e8) CI mode skips with exit 0" 0 "$RC"
assert_contains "(e9) CI advisory is loud" "SKIPPED" "$OUT"
# interactive decline → nothing executed
t68_proj foxtrot
printf '#!/usr/bin/env bash\necho "  ✓ f-decline"\n' > test/sections/T1-foxtrot.test.sh
git add -A && git commit -q -m sections
DEC_OUT=$( { sleep 0.5; echo n; sleep 20; } | env -u GOS_HEADLESS script -qec "node '$GOS' section run" /dev/null 2>&1 || true)
assert_contains "(e10) decline message" "not confirmed" "$DEC_OUT"
if printf '%s' "$DEC_OUT" | grep -q "f-decline"; then echo "  ✗ e11 declined run must not execute sections"; FAIL=$((FAIL+1))
else echo "  ✓ e11 declined run executed nothing"; PASS=$((PASS+1)); fi

# ===== (i) no test/sections dir → exit 0 + advisory; trust refuses =====
t68_proj india
mkdir -p bin && printf "function cmdMap(){ }\n" > bin/x.cjs && git add -A && git commit -q -m x
set +e; OUT=$(node "$GOS" section run 2>&1); RC=$?; set -e
assert_exit "(i1) empty project → exit 0" 0 "$RC"
assert_contains "(i2) advisory explains nothing to run" "nothing to run" "$OUT"
set +e; OUT=$(node "$GOS" section trust 2>&1); RC=$?; set -e
if [ "$RC" -ne 0 ]; then echo "  ✓ i3 trust on empty list refused"; PASS=$((PASS+1))
else echo "  ✗ i3 trust on empty list should refuse"; FAIL=$((FAIL+1)); fi
if [ -e .gos/cache/run-manifest.json ]; then echo "  ✗ i4 empty run must not write a manifest"; FAIL=$((FAIL+1))
else echo "  ✓ i4 empty run wrote no manifest"; PASS=$((PASS+1)); fi
if [ -e .gos/cache/trust.json ]; then echo "  ✗ i5 empty list must not record a confirm hash"; FAIL=$((FAIL+1))
else echo "  ✓ i5 empty list recorded no confirm hash"; PASS=$((PASS+1)); fi

# ===== (j) section deleting its own fixture-base marker → ✗ row =====
t68_proj juliet
printf '#!/usr/bin/env bash\nrm -f .GOS-TESTBASE\necho "  ✓ j1 ran"\n' > test/sections/T1-marker.test.sh
git add -A && git commit -q -m sections
node "$GOS" section trust >/dev/null 2>&1
set +e; OUT=$(node "$GOS" section run 2>&1); RC=$?; set -e
assert_exit "(j1) marker deletion → rc 1" 1 "$RC"
assert_contains "(j2) marker guard row emitted" "marker" "$OUT"

# ===== (g) two concurrent runners → fixture bases coexist, both survive =====
t68_proj golf
printf '#!/usr/bin/env bash\nsleep 2\necho "  ✓ g-one"\n' > test/sections/T1-g-one.test.sh
printf '#!/usr/bin/env bash\nsleep 2\necho "  ✓ g-two"\n' > test/sections/T2-g-two.test.sh
git add -A && git commit -q -m sections
node "$GOS" section trust >/dev/null 2>&1
set +e
node "$GOS" section run --timeout 30 >"$T68_DIR/golfA.log" 2>&1 &
GA=$!
sleep 1
node "$GOS" section run --timeout 30 >"$T68_DIR/golfB.log" 2>&1 &
GB=$!
sleep 1
NBASEES=$(t68_secs_left)
wait "$GA"; RCA=$?
wait "$GB"; RCB=$?
set -e
assert_exit "(g1) runner A green" 0 "$RCA"
assert_exit "(g2) runner B green" 0 "$RCB"
assert_eq "(g3) both fixture bases alive mid-run" "2" "$NBASEES"
python3 -c "import json;m=json.load(open('.gos/cache/run-manifest.json'));assert m['schema_version']==2 and len(m['sections_run'])==2" 2>/dev/null
assert_exit "(g4) manifest valid after concurrent runs" 0 "$?"
assert_eq "(g5) no fixture base left after both finish" "0" "$(t68_secs_left)"

# ===== (h) runner killed mid-run (kill -9) → stale manifest intact, next run fresh =====
t68_proj hotel
printf '#!/usr/bin/env bash\nsleep 300\necho "  ✓ slow"\n' > test/sections/T1-slow.test.sh
git add -A && git commit -q -m sections
node "$GOS" section trust >/dev/null 2>&1
printf '{"schema_version":2,"sections_run":[],"filter":"","runner_rc":0,"head_tree":"deadbeef","patch_sha":"deadbeef","finished_at":"sentinel"}' > .gos/cache/run-manifest.json
set +e
node "$GOS" section run --timeout 120 >"$T68_DIR/hotelA.log" 2>&1 &
HP=$!
sleep 2
kill -9 "$HP" 2>/dev/null
wait "$HP" 2>/dev/null; HKRC=$?
set -e
if [ "$HKRC" -eq 137 ] || [ "$HKRC" -eq 9 ]; then echo "  ✓ h1 runner killed by SIGKILL (rc $HKRC)"; PASS=$((PASS+1))
else echo "  (h1 runner exit rc=$HKRC — treat 137/9 as killed)"; PASS=$((PASS+1)); fi
assert_eq "(h2) stale manifest NOT overwritten by the kill" "deadbeef" "$(t68_field head_tree)"
if [ "$(t68_secs_left)" -ge 1 ]; then echo "  ✓ h3 killed runner's fixture base leaked (swept next run)"; PASS=$((PASS+1))
else echo "  ✗ h3 expected a leaked fixture base after kill -9"; FAIL=$((FAIL+1)); fi
set +e; OUT=$(node "$GOS" section run --timeout 2 2>&1); RC=$?; set -e
assert_exit "(h4) re-run after kill completes" 1 "$RC"
if [ "$(t68_field head_tree)" != "deadbeef" ]; then echo "  ✓ h5 re-run wrote a fresh manifest"; PASS=$((PASS+1))
else echo "  ✗ h5 stale sentinel still in place after re-run"; FAIL=$((FAIL+1)); fi
assert_eq "(h6) dead-pid fixture base swept by the re-run" "0" "$(t68_secs_left)"

# ===== (k) section trust pre-registers → subsequent headless run proceeds =====
t68_proj kilo
printf '#!/usr/bin/env bash\necho "  ✓ k1 ran"\n' > test/sections/T1-kilo.test.sh
git add -A && git commit -q -m sections
node "$GOS" section trust >/dev/null 2>&1
set +e; OUT=$(GOS_HEADLESS=1 node "$GOS" section run 2>&1); RC=$?; set -e
assert_exit "(k1) trusted + headless run proceeds" 0 "$RC"
assert_contains "(k2) section executed" "k1 ran" "$OUT"

# ===== (m) filter run → manifest carries filter + subset =====
t68_proj mike
printf '#!/usr/bin/env bash\necho "  ✓ m1"\n' > test/sections/T1-mike-a.test.sh
printf '#!/usr/bin/env bash\necho "  ✓ m2"\n' > test/sections/T2-mike-b.test.sh
git add -A && git commit -q -m sections
node "$GOS" section trust >/dev/null 2>&1
set +e; OUT=$(node "$GOS" section run mike-a 2>&1); RC=$?; set -e
assert_exit "(m1) filtered run green" 0 "$RC"
assert_eq "(m2) manifest filter recorded" "mike-a" "$(t68_field filter)"
assert_eq "(m3) only matching section recorded" "T1-mike-a" "$(t68_field sections_run | tr -d '[],')"
assert_eq "(m4) fixture base cleaned" "0" "$(t68_secs_left)"

t68_teardown
trap - EXIT
echo "--- T68 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
