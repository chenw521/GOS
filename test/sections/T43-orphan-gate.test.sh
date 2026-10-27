#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/gate.cjs#fn:cmdGate bin/lib/ops/doctor.cjs#fn:detectOrphans
# gos-map:cmd gate
# gate orphan detection (advisory frozen text / --strict escalation / exempt set) + README regen hard check
T43_DIR=""

t43_setup() {
  T43_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t43"
  mkdir -p "$T43_DIR" && cd "$T43_DIR" || exit 1
}
t43_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T43_DIR"; }

t43_setup
trap 't43_teardown' EXIT

PASS=0
FAIL=0

echo "--- T43: gate orphan detection + README regen guard ---"

git init -q . && git commit -q --allow-empty -m root
node "$GOS" init 1 "t43 orphan probe" >/dev/null 2>&1
node "$GOS" paths --markdown >/dev/null 2>&1   # README exists (init seeds it post-T6; explicit here for pre-seed compat)

# .1 clean repo: gate all emits no orphan warning
set +e
OUT1="$(node "$GOS" gate all 2>&1)"; RC1=$?
set -e
if [ "$RC1" -eq 0 ] && ! printf '%s' "$OUT1" | grep -q "orphan-advisory"; then
  echo "  ✓ T43.1 clean repo: no orphan advisory"; PASS=$((PASS+1))
else
  echo "  ✗ T43.1 clean repo flagged (rc=$RC1): $(printf '%s' "$OUT1" | grep -o 'orphan-advisory.*' | head -1)"; FAIL=$((FAIL+1))
fi

# .2 probe file -> advisory (frozen text) + exit stays 0
echo probe > .gos/probe.txt
set +e
OUT2="$(node "$GOS" gate all 2>&1)"; RC2=$?
set -e
if [ "$RC2" -eq 0 ] && printf '%s' "$OUT2" | grep -q "\[orphan-advisory\] 1 unregistered"; then
  echo "  ✓ T43.2 probe file → frozen advisory text, exit stays 0"; PASS=$((PASS+1))
else
  echo "  ✗ T43.2 rc=$RC2 out=$(printf '%s' "$OUT2" | grep -o '\[orphan-advisory\][^,]*' | head -1)"; FAIL=$((FAIL+1))
fi

# .3 BUILD mid-flight pre-declaration appears in the advisory block
if printf '%s' "$OUT2" | grep -q "BUILD is in progress"; then
  echo "  ✓ T43.3 BUILD-in-progress precondition present"; PASS=$((PASS+1))
else
  echo "  ✗ T43.3 precondition line missing"; FAIL=$((FAIL+1))
fi

# .4 --strict escalates to fail (exit != 0)
set +e
node "$GOS" gate all --strict >/dev/null 2>&1; RC4=$?
set -e
if [ "$RC4" -ne 0 ]; then
  echo "  ✓ T43.4 --strict escalates orphan to fail"; PASS=$((PASS+1))
else
  echo "  ✗ T43.4 --strict still exits 0"; FAIL=$((FAIL+1))
fi

# .5 exempt set: archive/, current task/, transient tmp/lock do not warn
rm -f .gos/probe.txt
mkdir -p .gos/archive/some-phase .gos/cache/backups
echo x > .gos/archive/some-phase/old.md
echo x > .gos/cache/backups/network.md.6
echo x > .gos/tmpfile.tmp
echo x > .gos/foo.lock   # note: NOT .gos/.lock — that IS the live GOS lockfile (acquireLock would block the gate itself)
set +e
OUT5="$(node "$GOS" gate all 2>&1)"; RC5=$?
set -e
if [ "$RC5" -eq 0 ] && ! printf '%s' "$OUT5" | grep -q "orphan-advisory"; then
  echo "  ✓ T43.5 archive/cache-backups/tmp/lock excluded"; PASS=$((PASS+1))
else
  echo "  ✗ T43.5 exempt zones flagged (rc=$RC5): $(printf '%s' "$OUT5" | tail -3)"; FAIL=$((FAIL+1))
fi
rm -f .gos/tmpfile.tmp .gos/foo.lock

# .6 README hand-edited -> regen diff check fails (anti-drift hard gate)
printf 'hand-edited\n' >> .gos/README.md
set +e
node "$GOS" gate all >/dev/null 2>&1; RC6=$?
set -e
if [ "$RC6" -ne 0 ] && node "$GOS" gate all 2>&1 | grep -q "README"; then
  echo "  ✓ T43.6 hand-edited README → regen guard fails gate"; PASS=$((PASS+1))
else
  echo "  ✗ T43.6 hand-edited README not caught (rc=$RC6)"; FAIL=$((FAIL+1))
fi

# .7 regen restores -> gate green
node "$GOS" paths --markdown >/dev/null 2>&1
set +e
node "$GOS" gate all >/dev/null 2>&1; RC7=$?
set -e
if [ "$RC7" -eq 0 ]; then
  echo "  ✓ T43.7 regen restores gate green"; PASS=$((PASS+1))
else
  echo "  ✗ T43.7 still red after regen (rc=$RC7)"; FAIL=$((FAIL+1))
fi

# .9 tracked-but-unregistered (via a real gos track flip) → registry-gap advisory
#    (not orphan), never fails even under --strict
echo live > .gos/legacy-tracked.md
echo ".gos/legacy-tracked.md" >> .gitignore && git add .gitignore && git commit -q -m gi
node "$GOS" track .gos/legacy-tracked.md >/dev/null 2>&1
set +e
OUT9="$(node "$GOS" gate all 2>&1)"; RC9=$?
set -e
if [ "$RC9" -eq 0 ] && ! printf '%s' "$OUT9" | grep -q "orphan-advisory" && printf '%s' "$OUT9" | grep -q "registry-gap"; then
  echo "  ✓ T43.9 tracked registry-gap → advisory tier, not orphan"; PASS=$((PASS+1))
else
  echo "  ✗ T43.9 rc=$RC9 orphan_line=$(printf '%s' "$OUT9" | grep -o 'orphan-advisory[^,]*' | head -1) gap=$(printf '%s' "$OUT9" | grep -c registry-gap)"; FAIL=$((FAIL+1))
fi
set +e
node "$GOS" gate all --strict >/dev/null 2>&1; RC9B=$?
set -e
if [ "$RC9B" -eq 0 ]; then
  echo "  ✓ T43.9b registry-gap stays advisory under --strict"; PASS=$((PASS+1))
else
  echo "  ✗ T43.9b --strict escalated the registry-gap tier (rc=$RC9B)"; FAIL=$((FAIL+1))
fi
rm -f .gos/legacy-tracked.md
git rm -q --cached .gos/legacy-tracked.md 2>/dev/null

# .8 freeze non-regression: existing verdicts keys untouched
for key in allPass gateFailedPrefix passPrefix failPrefix; do
  if node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); assert '$key' in d['gate_verdicts']" 2>/dev/null; then
    echo "  ✓ T43.8 verdict key intact: $key"; PASS=$((PASS+1))
  else
    echo "  ✗ T43.8 verdict key LOST: $key"; FAIL=$((FAIL+1))
  fi
done

echo "--- T43 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
