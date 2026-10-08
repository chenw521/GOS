#!/usr/bin/env bash
# gos-map:cmd phase
# T27: structured archive directory naming — <date>-v<version>-<phase-N|task>-<ascii-topic>
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner
T27_DIR=""

# [Phase W T5] fixture paths follow the CLI supply (task/<id>/) — never hardcode .gos/ root
gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }
gos_plan() { node "$GOS" context plan 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["plan"])' 2>/dev/null; }

t27_setup() {
  T27_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t27"
  mkdir -p "$T27_DIR" && cd "$T27_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  echo ".gos/state.json" > .gitignore && git add .gitignore && git commit -q -m gi
  export GOS_SKIP_SHIP_CHECK=1
}

t27_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T27_DIR"; unset GOS_SKIP_SHIP_CHECK; }

t27_setup
echo "--- T27: structured archive slug ---"
TODAY=$(date +%Y-%m-%d)

# --- T27.1: non-phase task — task segment + ascii topic ---
node "$GOS" init 2 "fix nav hints ascii topic" >/dev/null 2>&1
echo spec > "$(gos_spec)"
node "$GOS" approve archive >/dev/null 2>&1
node "$GOS" archive >/dev/null 2>&1
DIR1=$(ls .gos/archive/ | grep "^${TODAY}" | head -1)
if [ -n "$DIR1" ]; then echo "  ✓ archive dir created: $DIR1"; PASS=$((PASS+1)); else echo "  ✗ no archive dir"; FAIL=$((FAIL+1)); fi
echo "$DIR1" | grep -q "^${TODAY}-v[0-9]\+\.[0-9]\+\.[0-9]\+\(-[0-9A-Za-z.-]\+\)\?-task-" && echo "  ✓ non-phase slug shape <date>-v<semver[-prerelease]>-task-" && PASS=$((PASS+1)) || { echo "  ✗ bad shape: $DIR1"; FAIL=$((FAIL+1)); }
echo "$DIR1" | grep -q "fix-nav-hints-ascii-topic" && echo "  ✓ ascii topic preserved" && PASS=$((PASS+1)) || { echo "  ✗ topic missing: $DIR1"; FAIL=$((FAIL+1)); }

# --- T27.2: phased task — phase-N segment (first token of a CJK phase name) ---
t27_teardown; t27_setup
node "$GOS" init --project 4 "batch3" --force >/dev/null 2>&1
node "$GOS" phase add "6: 依赖地图" --goal "g" >/dev/null 2>&1
node "$GOS" phase claim 0 >/dev/null 2>&1
echo spec > "$(gos_spec)"
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='DONE'; s['completed_at']='2026-08-25T00:00:00.000Z'
json.dump(s,open('.gos/state.json','w'),indent=2)"
node "$GOS" approve archive >/dev/null 2>&1
node "$GOS" archive >/dev/null 2>&1
DIR2=$(ls .gos/archive/ | grep "^${TODAY}" | head -1)
echo "$DIR2" | grep -q -- "-phase-6-" && echo "  ✓ phase segment from CJK phase name first token (6)" && PASS=$((PASS+1)) || { echo "  ✗ no phase-6 segment: $DIR2"; FAIL=$((FAIL+1)); }

# --- T27.3: idempotency — repeated archive on the same state short-circuits ---
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "re-archive idempotent exits 0" 0 "$RC"
assert_contains "idempotent short-circuit message" "already archived" "$OUT"
N=$(ls .gos/archive/ | grep -c "^${TODAY}" || true)
assert_eq "no duplicate dir created" "1" "$N"

t27_teardown
