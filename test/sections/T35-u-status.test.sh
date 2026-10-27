#!/usr/bin/env bash
# gos-map:cmd help,status
# T35b: status screen frozen pointer line + headless usage only in detail/--json, never the default page
# Covers: (plan ; grep -F discipline)
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner

T35S_DIR=""

t35s_setup() {
  T35S_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t35s"
  mkdir -p "$T35S_DIR" && cd "$T35S_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t35s-seed
}

t35s_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T35S_DIR"; }

t35s_setup
echo "--- T35b: status pointer line + headless doc placement ---"

# S1 zero-arg screen carries the frozen pointer line (exact string, CONTRACTS.decorative.fullCapabilityPointer)
OUT=$(node "$GOS" 2>&1)
assert_contains "S1 zero-arg screen pointer" "Full capability: gos help \[--json\]" "$OUT"

# S2 CONTRACTS frozen constant exists (single source of truth)
node "$GOS" _contract 2>/dev/null | grep -q "fullCapabilityPointer"
assert_exit "S2 CONTRACTS key exists" 0 "$?"

# S3 help --json carries headless_mode (the only machine-readable doc entry)
J=$(node "$GOS" help --json 2>/dev/null | python3 -c "import json,sys;d=json.load(sys.stdin);print('headless_mode' in d)")
assert_eq "S3 help --json has headless_mode" "True" "$J"

# S4 help init detail page carries the headless note (explicit lookup surface)
H=$(node "$GOS" help init 2>&1)
assert_contains "S4 help init detail headless" "headless" "$H"

# S5 default help human overview page has zero GOS_HEADLESS hits (no bypass teaching)
IDX=$(node "$GOS" help 2>&1)
if echo "$IDX" | grep -q "GOS_HEADLESS"; then
  echo "  ✗ S5 default index leaks GOS_HEADLESS"
else
  echo "  ✓ S5 default index clean (no GOS_HEADLESS)"
fi

# S6 zero-arg status screen (with task state) also carries the pointer line
t35s_teardown; t35s_setup
node "$GOS" init 1 "s6 pointer" >/dev/null 2>&1
OUT2=$(node "$GOS" status 2>&1)
assert_contains "S6 status screen pointer" "Full capability: gos help \[--json\]" "$OUT2"

t35s_teardown
echo "T35b-u-status done"
