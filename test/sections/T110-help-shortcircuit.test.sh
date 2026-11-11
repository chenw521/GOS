#!/usr/bin/env bash
# gos-map:cmd help,gate,phase
# help-flag short-circuit — `gos <cmd> --help|-h` in FLAG position prints the
# command's help page BEFORE guardCwd/lock: no .gos/ creation, no lock, and
# write/exec-class commands never execute.
# Facts asserted:
#   - flag-position --help/-h after a registered read/exec/write command
#     routes to the command's help page (exit 0) with zero filesystem side
#     effects (no .gos/ appears in a pristine dir)
#   - value-position --help (the value of a value-taking option, here --goal)
#     REACHES the command: the roadmap usage error fires on an empty project,
#     and a real phase add stores the literal goal
#   - `--` terminates flag parsing: `status -- --help` runs status
#   - unknown command + --help keeps the existing non-zero unknown-command
#     error, byte-identical to the bare unknown command
#   - help family dispatch unchanged: `help --json` envelope shape, top-level
#     `--help` index, `help <cmd>` == `<cmd> --help`, `help --help` host page
T110_DIR=""

t110_setup() {
  T110_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t110"
  mkdir -p "$T110_DIR" && cd "$T110_DIR" || exit 1
}

t110_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T110_DIR"; }

echo "--- T110: help-flag short-circuit (flag position, zero side effects) ---"

# ===== S: short-circuit routing (pristine dir — no .gos/ may appear) =====
t110_setup
set +e
OUT_S1=$(node "$GOS" status --help 2>&1); RC_S1=$?
OUT_S2=$(node "$GOS" gate --help 2>&1); RC_S2=$?
OUT_S3=$(node "$GOS" gate -h 2>&1); RC_S3=$?
OUT_S4=$(node "$GOS" decision --help 2>&1); RC_S4=$?
set -e
assert_exit "S1 status --help exits 0" 0 "$RC_S1"
assert_contains "S1 status --help renders the help page, not status" "usage:" "$OUT_S1"
assert_exit "S2 gate --help exits 0 (gate never runs)" 0 "$RC_S2"
assert_contains "S2 gate --help renders the gate help page" "usage:" "$OUT_S2"
assert_exit "S3 gate -h exits 0" 0 "$RC_S3"
assert_contains "S3 gate -h renders the gate help page" "usage:" "$OUT_S3"
assert_exit "S4 decision --help exits 0 (write-class never runs)" 0 "$RC_S4"
assert_contains "S4 decision --help renders the decision help page" "usage:" "$OUT_S4"
if [ ! -e .gos ]; then echo "  ✓ S5 zero filesystem side effects (no .gos/ created)"; else echo "  ✗ S5 guardCwd ran (.gos/ exists)"; fi
t110_teardown

# ===== T: `--` terminates flag parsing =====
t110_setup
set +e; OUT_T1=$(node "$GOS" status -- --help 2>&1); RC_T1=$?; set -e
assert_exit "T1 status -- --help still runs status" 0 "$RC_T1"
assert_contains "T1 status output shown, not the help page" "o active task" "$OUT_T1"
t110_teardown

# ===== V: value-position --help reaches the command =====
# Sandboxes are initialized first: guardCwd's ancestor check must pass so the
# command's OWN parsing (which consumes --help as a value) is what runs.
t110_setup
git init -q . && git commit -q --allow-empty -m t110-seed
GOS_HEADLESS=1 node "$GOS" init 2 "t110 empty roadmap" >/dev/null 2>&1
set +e; OUT_V1=$(node "$GOS" phase amend 5 --goal "--help" 2>&1); RC_V1=$?; set -e
assert_exit "V1 value-position --help hits the command usage error" 1 "$RC_V1"
assert_contains "V1 phase amend usage error reached (goal consumed --help as its value)" "out of range" "$OUT_V1"
t110_teardown

t110_setup
git init -q . && git commit -q --allow-empty -m t110-seed
GOS_HEADLESS=1 node "$GOS" init 2 "t110 value position" --project >/dev/null 2>&1
set +e; OUT_V2=$(node "$GOS" phase add "P1: live pain" --goal "--help" 2>&1); RC_V2=$?; set -e
assert_exit "V2 phase add --goal --help executes (write lands)" 0 "$RC_V2"
assert_contains "V2 phase add echoes the new phase" "P1: live pain" "$OUT_V2"
OUT_V2L=$(node "$GOS" phase list 2>&1)
assert_contains "V2 phase list shows the literal --help goal" "P1: live pain | --help" "$OUT_V2L"
t110_teardown

# ===== U: unknown command keeps the non-zero error =====
# Initialized sandbox: with local state present, guardCwd passes and the
# unknown-command die (not the ancestor check) is the observed error.
t110_setup
git init -q . && git commit -q --allow-empty -m t110-seed
GOS_HEADLESS=1 node "$GOS" init 2 "t110 unknown cmd" >/dev/null 2>&1
set +e
OUT_U1=$(node "$GOS" frobnicate 2>&1); RC_U1=$?
OUT_U2=$(node "$GOS" frobnicate --help 2>&1); RC_U2=$?
set -e
assert_exit "U1 bare unknown command non-zero" 1 "$RC_U1"
assert_exit "U2 unknown + --help non-zero" 1 "$RC_U2"
assert_contains "U2 unknown-command error preserved" "Unknown command" "$OUT_U2"
assert_eq "U2 output byte-identical to the bare unknown command" "$OUT_U1" "$OUT_U2"
t110_teardown

# ===== J: help family surfaces unchanged =====
OUT_J1=$(node "$GOS" help --json 2>/dev/null)
J1=$(printf '%s' "$OUT_J1" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["schema_version"] == 1
assert d["commands"]["status"]["class"] == "read"
assert d["commands"]["gate"]["class"] == "exec"
print("OK")
' 2>&1)
[ "$J1" = "OK" ] && echo "  ✓ J1 help --json envelope shape unchanged" || echo "  ✗ J1 envelope shape drifted: $J1"
OUT_J2=$(node "$GOS" --help 2>&1)
assert_contains "J2 top-level --help index unchanged" "Usage: gos <command>" "$OUT_J2"
OUT_J3A=$(node "$GOS" help status 2>&1)
OUT_J3B=$(node "$GOS" status --help 2>&1)
assert_eq "J3 <cmd> --help matches gos help <cmd> byte-for-byte" "$OUT_J3A" "$OUT_J3B"
OUT_J4=$(node "$GOS" help --help 2>&1)
assert_contains "J4 help --help keeps the host-page detail" "rendered from COMMANDS registry" "$OUT_J4"

echo "--- T110 done ---"
