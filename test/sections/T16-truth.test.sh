#!/usr/bin/env bash
# gos-map:cmd truth
# T16: truth command family — add continuous numbering + manual verify + --replay execution + receipts + manualWarning
# Covers: input constraint table, synthetic exit-code lines not counted as hits, canary injection
# Env: GOS (CLI path), TESTBASE (isolated base), assert helpers sourced by runner
T16_DIR=""

t16_setup() {
  T16_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t16"
  mkdir -p "$T16_DIR" && cd "$T16_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t16_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T16_DIR"; }

t16_g() { node "$GOS" "$@"; }

t16_st() { python3 -c "$1" 2>/dev/null; }   # state.json assertion helper (exit 0/1)

t16_setup
echo "--- T16: truth add 续号 + manual/replay verify + receipts + manualWarning ---"

t16_g init 2 "t16 truth family" >/dev/null 2>&1
echo "evidence artifact body" > art.txt

# --- T16.1: truth add continuous numbering — first→T1, second→T2 ---
OUT=$(t16_g truth add "first truth" 2>&1); RC=$?
assert_exit "truth add exits 0" "0" "$RC"
assert_contains "first add → id T1" "T1" "$OUT"
OUT=$(t16_g truth add "second truth" 2>&1); RC=$?
assert_exit "second add exits 0" "0" "$RC"
assert_contains "second add → T2 (续号)" "T2" "$OUT"
if t16_st 'import json
s=json.load(open(".gos/state.json"))
ts=s["observable_truths"]
assert [t["id"] for t in ts]==["T1","T2"], [t["id"] for t in ts]
assert all(t["verified"] is False and t["evidence"] is None for t in ts)'; then
  echo "  ✓ state holds T1,T2 unverified (verified:false, evidence:null)"; PASS=$((PASS+1))
else
  echo "  ✗ state truth entries wrong shape/order"; FAIL=$((FAIL+1))
fi

# --- T16.2: manual verify — excerpt 'passed' alone hits NO feature regex → exit 1 [B-1] ---
OUT=$(t16_g truth verify T1 --command "node bin/gos.cjs gate all" --excerpt "passed" --artifact art.txt 2>&1); RC=$?
assert_exit "single-word 'passed' excerpt → no feature match → exit 1" "1" "$RC"
if t16_st 'import json
s=json.load(open(".gos/state.json"))
t=[x for x in s["observable_truths"] if x["id"]=="T1"][0]
assert t["verified"] is False'; then
  echo "  ✓ failed verify does NOT set verified"; PASS=$((PASS+1))
else
  echo "  ✗ T1 set despite validation failure"; FAIL=$((FAIL+1))
fi

# --- T16.3: manual verify with stats excerpt + existing artifact → exit 0 + manual:true ---
OUT=$(t16_g truth verify T1 --command "bash test/run-sections.sh" --excerpt "5 passed, 0 failed" --artifact art.txt 2>&1); RC=$?
assert_exit "manual verify exits 0" "0" "$RC"
if t16_st 'import json
s=json.load(open(".gos/state.json"))
t=[x for x in s["observable_truths"] if x["id"]=="T1"][0]
assert t["verified"] is True
ev=t["evidence"]
assert ev["manual"] is True and ev["command"]=="bash test/run-sections.sh"
assert ev["output_excerpt"]=="5 passed, 0 failed" and ev["artifact_path"]=="art.txt"'; then
  echo "  ✓ state shows T1 verified + evidence{manual:true}"; PASS=$((PASS+1))
else
  echo "  ✗ T1 evidence manual shape wrong"; FAIL=$((FAIL+1))
fi

# --- T16.4: artifact nonexistent → exit 1 [B-1 pathExists] ---
OUT=$(t16_g truth verify T2 --command "bash test/run-sections.sh" --excerpt "3 tests passed" --artifact nope/missing.txt 2>&1); RC=$?
assert_exit "nonexistent artifact → exit 1" "1" "$RC"

# --- T16.5: replay empty stdout (["true"]) → exit 1 [B-1/R2-6] ---
OUT=$(t16_g truth verify T2 --replay --command '["true"]' --artifact art.txt 2>&1); RC=$?
assert_exit "replay ['true'] empty stdout → exit 1" "1" "$RC"

# --- T16.6: replay synthetic exit-code-only line matches ① only → exit 1 [R2-6] ---
OUT=$(t16_g truth verify T2 --replay --command '["bash","-c","echo exit code: 0"]' --artifact art.txt 2>&1); RC=$?
assert_exit "exit-code-only stdout line → replay rejects (needs ②count/③path) → exit 1" "1" "$RC"
if t16_st 'import json
s=json.load(open(".gos/state.json"))
t=[x for x in s["observable_truths"] if x["id"]=="T2"][0]
assert t["verified"] is False and t["evidence"] is None'; then
  echo "  ✓ T2 still untouched after all failed verifies"; PASS=$((PASS+1))
else
  echo "  ✗ T2 modified by failed verify attempts"; FAIL=$((FAIL+1))
fi

# --- T16.7: replay normal command → exit 0 + evidence from ACTUAL stdout + receipt [B-1/B-20] ---
OUT=$(t16_g truth verify T2 --replay --command '["node","-e","console.log(\"42 tests passed\")"]' --artifact art.txt 2>&1); RC=$?
assert_exit "replay verify exits 0" "0" "$RC"
if t16_st 'import json
s=json.load(open(".gos/state.json"))
t=[x for x in s["observable_truths"] if x["id"]=="T2"][0]
assert t["verified"] is True
ev=t["evidence"]
assert ev.get("replay") is True and ev.get("manual") is None
assert ev["output_excerpt"]=="42 tests passed", ev["output_excerpt"]
assert ev["command"].startswith("[\"node\""), ev["command"]'; then
  echo "  ✓ evidence.replay:true + excerpt taken from actual stdout"; PASS=$((PASS+1))
else
  echo "  ✗ replay evidence shape wrong"; FAIL=$((FAIL+1))
fi
assert_file "receipt file .gos/logs/truth-receipts.md exists" ".gos/logs/truth-receipts.md"
if grep -q "T2 replay-verified" ".gos/logs/truth-receipts.md" 2>/dev/null; then
  echo "  ✓ receipt line 'T2 replay-verified: <command>' present"; PASS=$((PASS+1))
else
  echo "  ✗ receipt line missing"; FAIL=$((FAIL+1))
fi
if [ "$(grep -c . ".gos/logs/truth-receipts.md" 2>/dev/null || echo 0)" = "1" ]; then
  echo "  ✓ exactly one receipt line (manual verify wrote none)"; PASS=$((PASS+1))
else
  echo "  ✗ receipt line count ≠ 1"; FAIL=$((FAIL+1))
fi

# --- T16.8: gate truths manualWarning — N substituted from CONTRACTS template [B-1/R3-F8] ---
OUT=$(t16_g gate truths 2>&1); RC=$?
assert_exit "gate truths exits 0 (all verified)" "0" "$RC"
assert_contains "manualWarning text present" "manual truths (evidence not replayed)" "$OUT"
assert_contains "manualWarning N=1 (T1 manual, T2 replay)" "1 manual truths" "$OUT"
# add + manual-verify a third truth → N=2, and add numbering continues at T3
t16_g truth add "third truth" >/dev/null 2>&1
t16_g truth verify T3 --command "bash test/run-sections.sh" --excerpt "7 files checked" --artifact art.txt >/dev/null 2>&1
OUT=$(t16_g gate truths 2>&1)
assert_contains "manualWarning escalates to N=2" "2 manual truths" "$OUT"

# --- T16.9: dispatch registered — no 'Unknown command' [R4-F4] ---
OUT=$(t16_g truth add "x" 2>&1)
if echo "$OUT" | grep -q "Unknown command"; then
  echo "  ✗ truth still unknown in dispatch"; FAIL=$((FAIL+1))
else
  echo "  ✓ truth dispatch registered"; PASS=$((PASS+1))
fi

# --- T16.10: input constraints — codepoint cap + injection canaries [B-17/R1-F9] ---
LONG=$(python3 -c "print('a'*501)")
OUT=$(t16_g truth add "$LONG" 2>&1); RC=$?
assert_exit "desc >500 codepoints rejected" "1" "$RC"
rm -f pwned
OUT=$(t16_g truth add "'\$(touch pwned)'" 2>&1); RC=$?
assert_exit "shell-substitution canary rejected" "1" "$RC"
if [ -e pwned ]; then
  echo "  ✗ canary EXECUTED (pwned exists)"; FAIL=$((FAIL+1))
else
  echo "  ✓ no canary side effect"; PASS=$((PASS+1))
fi
OUT=$(t16_g truth add $'- line\n- [injected] fake truth' 2>&1); RC=$?
assert_exit "newline list-entry injection rejected" "1" "$RC"

t16_teardown
