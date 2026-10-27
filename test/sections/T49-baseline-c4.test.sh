#!/usr/bin/env bash
# gos-map:cmd map,gate
# gos-map:fn bin/lib/map/engine.cjs#fn:writeDeps bin/lib/ops/gate.cjs#fn:cmdGate
# : C4 baseline alarm + admission protocol
# A: fn removal -> full list + fingerprint; B: scan writes no history; C: reset without approve refused; D: approve -> single-consume reset + peak archived; E: large-repo dir aggregation
T49_DIR=""

t49_setup() {
  T49_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t49"
  mkdir -p "$T49_DIR" && cd "$T49_DIR" || exit 1
}

t49_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T49_DIR"; }

gen_fns() { # $1=file $2=prefix $3=count
  { echo "'use strict';"; for i in $(seq 1 "$3"); do echo "function $2$i() { return $i; }"; done; echo "module.exports = {};"; } > "$1"
}

t49_setup
echo "--- T49: C4 baseline alarm (D-30) ---"

# --- .A: small repo (5 fn), remove 1 fn -> full list + fingerprint change
mkdir -p small/lib && cd "$T49_DIR/small" || exit 1
git init -q . && git commit -q --allow-empty -m root
node "$GOS" init 1 "t49 small" >/dev/null 2>&1
gen_fns lib/x.cjs fn 5
set +e; node "$GOS" map scan >/dev/null 2>&1; set -e
rm lib/x.cjs
gen_fns lib/y.cjs other 3
set +e; node "$GOS" map scan >/dev/null 2>&1; GOUT=$(node "$GOS" gate codemap 2>&1); set -e
assert_contains "A1 fn missing vs peak full list (small repo)" "fn missing vs peak" "$GOUT"
assert_contains "A2 fingerprint-changed row" "fingerprint changed" "$GOUT"
assert_contains "A3 list includes the deleted fn" "fn1" "$GOUT"

# --- .B: scan adds no history entries (scan has no write access to history)
HIST=".gos/codebase/edge-history.ndjson"
if [ -f "$HIST" ]; then N1=$(wc -l < "$HIST"); else N1=0; fi
set +e; node "$GOS" map scan >/dev/null 2>&1; set -e
if [ -f "$HIST" ]; then N2=$(wc -l < "$HIST"); else N2=0; fi
assert_eq "B1 scan adds no history entry" "$N1" "$N2"

# --- .C: reset without approve -> refused
set +e; ROUT=$(node "$GOS" map baseline reset --reason "no approve" 2>&1); RRC=$?; set -e
assert_exit "C1 reset without approve is refused (exit 1)" 1 "$RRC"
assert_contains "C2 refusal message carries the approve pointer" "approve baseline-reset" "$ROUT"

# --- .D: approve -> reset single consumption + peak archived + re-anchor
set +e; AOUT=$(node "$GOS" approve baseline-reset --reason "legit re-anchor" 2>&1); ARC=$?; set -e
assert_exit "D1 approve baseline-reset succeeds" 0 "$ARC"
set +e; ROUT2=$(node "$GOS" map baseline reset --reason "legit re-anchor" 2>&1); RRC2=$?; set -e
assert_exit "D2 reset with approve succeeds" 0 "$RRC2"
assert_contains "D3 old peak archived into history" "oldPeak" "$(cat "$HIST" 2>/dev/null)"
node -e "
const bl=JSON.parse(require('fs').readFileSync('.gos/codebase/edge-baseline.json','utf8'));
console.log((bl.peak && bl.current && bl.peak.fn_count===bl.current.fn_count)?'OK peak==current':'BAD peak!=current');
" > t49d.txt 2>&1 || true
assert_contains "D4 peak re-anchored to current" "OK peak==current" "$(cat t49d.txt)"
set +e; ROUT3=$(node "$GOS" map baseline reset --reason "legit re-anchor" 2>&1); RRC3=$?; set -e
assert_exit "D5 single-consume: second reset is refused" 1 "$RRC3"

# --- .E: large repo (>50 fn) per-directory aggregation
cd "$T49_DIR" || exit 1
mkdir -p big/lib/dirA big/lib/dirB && cd "$T49_DIR/big" || exit 1
git init -q . && git commit -q --allow-empty -m root
node "$GOS" init 1 "t49 big" >/dev/null 2>&1
gen_fns lib/dirA/a.cjs alpha 30
gen_fns lib/dirB/b.cjs beta 30
set +e; node "$GOS" map scan >/dev/null 2>&1; set -e
rm -rf lib/dirB
gen_fns lib/filler.cjs fill 5
set +e; node "$GOS" map scan >/dev/null 2>&1; GOUT2=$(node "$GOS" gate codemap 2>&1); set -e
assert_contains "E1 large repo aggregates by directory (by dir)" "by dir" "$GOUT2"
assert_contains "E2 aggregate points at dirB" "dirB" "$GOUT2"

t49_teardown
