#!/usr/bin/env bash
# gos-map:fn bin/lib/task/archive.cjs#fn:cmdArchive bin/lib/core/state.cjs#fn:validateState
# gos-map:cmd archive
# Cases: A = evidence pointing at old task/ paths rewritten during archive; B = crash injection, rerun idempotently completes; C = absolute path normalization
T50_DIR=""

t50_setup() {
  T50_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t50"
  mkdir -p "$T50_DIR" && cd "$T50_DIR" || exit 1
}
t50_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T50_DIR"; }

t50_setup
trap 't50_teardown' EXIT
PASS=0; FAIL=0
echo "--- T50: archive transaction fix (D-31) ---"

# seed: one step before SHIP + a verified truth whose evidence points into task/<id>/
seed_ship() {
  mkdir -p "$T50_DIR/s-$1" && cd "$T50_DIR/s-$1" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  node "$GOS" init 1 "t50 $1" >/dev/null 2>&1
  node "$GOS" commit intent >/dev/null 2>&1
  SPEC="$(node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])')"
  mkdir -p "$(dirname "$SPEC")"; echo "# spec" > "$SPEC"
  node "$GOS" approve think >/dev/null 2>&1
  node "$GOS" commit think >/dev/null 2>&1
  node "$GOS" stage build >/dev/null 2>&1
  TID="$(printf '%s' "$SPEC" | sed 's|.*\.gos/task/||; s|/spec.md$||')"
  echo "receipt-body" > ".gos/task/$TID/receipt.md"
  node "$GOS" truth add "T50 truth $1" >/dev/null 2>&1
  node "$GOS" truth verify T1 --command '["echo","ok50"]' --excerpt 'exit code 0' --artifact ".gos/task/$TID/receipt.md" >/dev/null 2>&1
  node "$GOS" approve archive >/dev/null 2>&1
}

# --- .A: regression — evidence points at old task/ paths, archive must succeed and rewrite all three paths
seed_ship a
set +e; AOUT=$(GOS_SKIP_SHIP_CHECK=1 node "$GOS" archive 2>&1); ARC=$?; set -e
assert_exit "A1 deadlock regression: archive succeeds" 0 "$ARC"
AD="$(ls -d .gos/archive/*/ 2>/dev/null | head -1)"
if [ -n "$AD" ] && [ -f "$AD/task/$TID/receipt.md" ]; then
  echo "  ✓ A2 evidence file landed in archive"; PASS=$((PASS+1))
else
  echo "  ✗ A2 archive dir or receipt missing (AD=$AD TID=$TID)"; FAIL=$((FAIL+1))
fi
node -e "
const s=JSON.parse(require('fs').readFileSync('.gos/state.json','utf8'));
const ev=(s.observable_truths||[])[0].evidence.artifact_path;
const specOK=String(s.spec_path||'').includes('/task/$TID/spec.md') && !String(s.spec_path||'').startsWith('.gos/task/');
const evOK=String(ev||'').includes('archive/') && !String(ev||'').startsWith('.gos/task/');
console.log((specOK&&evOK)?'OK rewritten spec='+s.spec_path+' ev='+ev:'BAD spec='+s.spec_path+' ev='+ev);
" > t50a.txt 2>&1 || true
assert_contains "A3 state paths rewritten to archive (registry-driven)" "OK rewritten" "$(cat t50a.txt)"

# --- .B: crash injection (after-dest) -> die; rerun -> idempotent completion
seed_ship b
set +e; BOUT=$(GOS_TEST_BREAK_SHIP=after-dest GOS_SKIP_SHIP_CHECK=1 node "$GOS" archive 2>&1); BRC=$?; set -e
assert_exit "B1 crash injection dies in window" 1 "$BRC"
BD="$(ls -d .gos/archive/*/ 2>/dev/null | head -1)"
if [ -n "$BD" ] && [ -f "$BD/task/$TID/spec.md" ] && [ ! -e ".gos/task/$TID" ]; then
  echo "  ✓ B2 half-transaction state: dest materialized, task dir gone"; PASS=$((PASS+1))
else
  echo "  ✗ B2 not a half-transaction (BD=$BD)"; FAIL=$((FAIL+1))
fi
set +e; BOUT2=$(GOS_SKIP_SHIP_CHECK=1 node "$GOS" archive 2>&1); BRC2=$?; set -e
assert_exit "B3 re-run completes idempotently" 0 "$BRC2"
assert_contains "B4 completion banner present" "half-transaction completed idempotently" "$BOUT2"
node -e "
const s=JSON.parse(require('fs').readFileSync('.gos/state.json','utf8'));
const ok=s.current_stage==='DONE' && String(s.spec_path||'').includes('archive/');
console.log(ok?'OK done+rewritten':'BAD stage='+s.current_stage+' spec='+s.spec_path);
" > t50b.txt 2>&1 || true
assert_contains "B5 state DONE + spec_path rewritten" "OK done+rewritten" "$(cat t50b.txt)"

# --- .C: absolute path normalization — truths evidence stored absolute -> archive still succeeds
seed_ship c
ROOT_ABS="$(pwd -P)"
node -e "
const fs=require('fs');
const s=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
s.observable_truths[0].evidence.artifact_path=process.argv[1]+'/.gos/task/'+process.argv[2]+'/receipt.md';
fs.writeFileSync('.gos/state.json', JSON.stringify(s,null,2));
" "$ROOT_ABS" "$TID"
set +e; COUT=$(GOS_SKIP_SHIP_CHECK=1 node "$GOS" archive 2>&1); CRC=$?; set -e
assert_exit "C1 absolute-path state archives fine (normalized)" 0 "$CRC"
node -e "
const s=JSON.parse(require('fs').readFileSync('.gos/state.json','utf8'));
const ev=String((s.observable_truths||[])[0].evidence.artifact_path);
console.log(ev.includes('archive/') && !ev.startsWith('/') ? 'OK relative archive path: '+ev : 'BAD ev='+ev);
" > t50c.txt 2>&1 || true
assert_contains "C2 final evidence path is archive-relative" "OK relative archive path" "$(cat t50c.txt)"

# --- .D: registry single-source static assertion — all three consumers reference STATE_PATH_FIELDS, zero hardcoded lists
N_REG=$(grep -c "STATE_PATH_FIELDS" "$GOS_ROOT/bin/lib/task/archive.cjs" 2>/dev/null || echo 0)
if [ "${N_REG:-0}" -ge 3 ]; then
  echo "  ✓ D1 archive consumes registry ($N_REG sites)"; PASS=$((PASS+1))
else
  echo "  ✗ D1 registry consumption sites: $N_REG (<3)"; FAIL=$((FAIL+1))
fi
N_TXT=$(grep -cE "replace\([^)]*task/[^)]*state\.|JSON\.stringify\(state[^)]*\)\.replace" "$GOS_ROOT/bin/lib/task/archive.cjs" 2>/dev/null || true); N_TXT=${N_TXT:-0}
if [ "${N_TXT:-0}" -eq 0 ]; then
  echo "  ✓ D2 no whole-JSON text replace (field-level only)"; PASS=$((PASS+1))
else
  echo "  ✗ D2 suspicious text-level replace found"; FAIL=$((FAIL+1))
fi

echo "--- T50 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
