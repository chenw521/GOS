#!/usr/bin/env bash
# gos-map:fn bin/lib/task/archive.cjs#fn:cmdArchive bin/lib/ops/doctor.cjs#fn:detectOrphans
# gos-map:cmd archive
# : ship two-phase transaction — normal archive / rollback / idempotent re-entry / mtime exemption / owned-orphan re-homing
T45_DIR=""

t45_setup() {
  T45_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t45"
  mkdir -p "$T45_DIR" && cd "$T45_DIR" || exit 1
}
t45_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T45_DIR"; }

t45_setup
trap 't45_teardown' EXIT

PASS=0
FAIL=0

echo "--- T45: ship two-phase transaction (5 scenarios) ---"

seed_ship_ready() {
  mkdir -p "$T45_DIR/s-$1" && cd "$T45_DIR/s-$1" || exit 1   # per-scenario sandbox (archive dirs must not collide)
  git init -q . && git commit -q --allow-empty -m root
  node "$GOS" init 1 "t45 ship $1" >/dev/null 2>&1
  node "$GOS" commit intent >/dev/null 2>&1
  SPEC="$(node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])')"
  mkdir -p "$(dirname "$SPEC")"; echo "# spec" > "$SPEC"
  node "$GOS" approve think >/dev/null 2>&1
  node "$GOS" commit think >/dev/null 2>&1
  node "$GOS" stage build >/dev/null 2>&1
  node "$GOS" approve archive >/dev/null 2>&1
}

# --- .1 normal archive: task/<id>/ dir moves into archive + strays adopted into orphans/ + rescan clean
seed_ship_ready a
echo junk > .gos/old-stray.txt
sleep 1
touch -d "10 minutes ago" .gos/old-stray.txt   # past the quiet window (adoptable)
set +e
OUT1="$(GOS_SKIP_SHIP_CHECK=1 node "$GOS" archive 2>&1)"; RC1=$?
set -e
AD=$(ls -d .gos/archive/*/ | head -1)
# [T45 debug-keep] structural dump on failure path
find .gos/archive -maxdepth 3 > "$T45_DIR/s-a/structure.txt" 2>/dev/null || true
if [ "$RC1" -eq 0 ] && [ -d "$AD" ] && [ -f "$AD/orphans/old-stray.txt" ]; then
  echo "  ✓ T45.1 normal ship: task dir + orphans/ adopted"; PASS=$((PASS+1))
else
  echo "  ✗ T45.1 rc=$RC1 out=$(printf '%s' "$OUT1" | tail -3)"; FAIL=$((FAIL+1))
fi
TID_REL="$(printf '%s' "$SPEC" | sed 's|.*\.gos/||; s|^task/||; s|/spec.md$||')"   # e.g. a1b2c3d4
if [ -f "$AD/task/$TID_REL/spec.md" ] && [ ! -e ".gos/task/$TID_REL" ]; then
  echo "  ✓ T45.1b task/<id>/ moved wholesale into archive (id layer kept)"; PASS=$((PASS+1))
else
  echo "  ✗ T45.1b archived=$([ -f "$AD/task/$TID_REL/spec.md" ] 2>/dev/null && echo yes || echo no) tid=$TID_REL"; FAIL=$((FAIL+1))
fi

# --- .2 rollback: injected staging write failure -> original paths kept + die
seed_ship_ready b
echo stray > .gos/old2.txt; touch -d "10 minutes ago" .gos/old2.txt
set +e
OUT2="$(GOS_SKIP_SHIP_CHECK=1 GOS_TEST_BREAK_SHIP=staging node "$GOS" archive 2>&1)"; RC2=$?
set -e
SPEC2="$(node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null)"
if [ -n "$SPEC2" ] && [ -f "$SPEC2" ]; then
  echo "  ✓ T45.2 rollback keeps task artifacts at origin (spec intact)"; PASS=$((PASS+1))
else
  echo "  ✗ T45.2 spec lost after failed ship (SPEC2=$SPEC2)"; FAIL=$((FAIL+1))
fi

# --- .3 idempotent re-entry: manual staging leftover -> next archive restores first, then finishes
seed_ship_ready c
mkdir -p .gos/.ship-staging/task
SPEC3="$(node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])')"
mkdir -p "$(dirname "$SPEC3")"; echo "# recovered" > "$SPEC3"
set +e
OUT3="$(GOS_SKIP_SHIP_CHECK=1 node "$GOS" archive 2>&1)"; RC3=$?
set -e
if printf '%s' "$OUT3" | grep -q "idempotent re-entry" && [ "$RC3" -eq 0 ] && [ ! -d .gos/.ship-staging ]; then
  echo "  ✓ T45.3 stale staging recovered + ship completed"; PASS=$((PASS+1))
else
  echo "  ✗ T45.3 rc=$RC3 recovered=$(printf '%s' "$OUT3" | grep -c idempotent) staging_left=$([ -d .gos/.ship-staging ] && echo yes || echo no)"; FAIL=$((FAIL+1))
fi

# --- .4 mtime exemption: orphans younger than 5min are skipped, rescan assertion skipped too
seed_ship_ready d
echo fresh > .gos/fresh-orphan.txt   # mtime=now -> must be exempt
set +e
OUT4="$(GOS_SKIP_SHIP_CHECK=1 node "$GOS" archive 2>&1)"; RC4=$?
set -e
AD4=$(ls -d .gos/archive/*task/ 2>/dev/null | head -1)
if [ "$RC4" -eq 0 ] && [ -f .gos/fresh-orphan.txt ] && [ ! -f "$AD4/orphans/fresh-orphan.txt" ]; then
  echo "  ✓ T45.4 fresh orphan exempted (mtime quiet period), stays at origin"; PASS=$((PASS+1))
else
  echo "  ✗ T45.4 rc=$RC4 fresh_at_origin=$([ -f .gos/fresh-orphan.txt ] && echo yes || echo no)"; FAIL=$((FAIL+1))
fi

# --- .4b phase-b injected failure: rename dies midway -> rollback keeps the task in place (full staging transaction path)
seed_ship_ready d2
set +e
OUT4B="$(GOS_SKIP_SHIP_CHECK=1 GOS_TEST_BREAK_SHIP=phase-b node "$GOS" archive 2>&1)"; RC4B=$?
set -e
SPEC4B="$(node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null)"
if [ -n "$SPEC4B" ] && [ -f "$SPEC4B" ]; then
  echo "  ✓ T45.4b phase-b break rolls back, task artifacts intact"; PASS=$((PASS+1))
else
  echo "  ✗ T45.4b rc=$RC4B spec=$SPEC4B"; FAIL=$((FAIL+1))
fi

# --- .5 owned-orphan re-homing: task/<code>/ leftover -> pre-seeded legacy phase-w archive directory
seed_ship_ready e
mkdir -p .gos/archive/2026-01-01-v0.0.0-phase-w-legacy/gone
mkdir -p .gos/task/w
echo residue > .gos/task/w/old-evidence.log
touch -d "10 minutes ago" .gos/task/w/old-evidence.log
set +e
OUT5="$(GOS_SKIP_SHIP_CHECK=1 node "$GOS" archive 2>&1)"; RC5=$?
set -e
HIT="$(grep -rl "residue" .gos/archive/*phase-w*/ 2>/dev/null | head -1)"
if [ -n "$HIT" ]; then
  echo "  ✓ T45.5 phase-owned orphan (task/w/) routed to phase-w archive"; PASS=$((PASS+1))
else
  echo "  ✗ T45.5 rc=$RC5 hit=$HIT out=$(printf '%s' "$OUT5" | tail -2)"; FAIL=$((FAIL+1))
fi

echo "--- T45 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
