#!/usr/bin/env bash
# gos-map:cmd brownfield,_contract,help
# T78: registry + contract wiring for `gos brownfield` (class: global).
# Lock-free registration — the dispatcher's guardCwd takes the .gos/.lock for
# write/exec classes only; brownfield mutates repo files like `setup
# --commitlint` but must stay lock-free (R4-F1). Freezes the _contract
# surface: status set, state_flags set, exit-code table 0-5, preflight
# reason closed set (D-88/D-99).
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner
T78_DIR=""

t78_setup() {
  T78_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t78"
  mkdir -p "$T78_DIR" || exit 1
  cd "$T78_DIR" || exit 1
}

t78_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T78_DIR"; }

t78_setup
echo "--- T78: registry + contract wiring (brownfield, class global) ---"

# --- T78.1: help --json lists brownfield with class global + usage ---
node "$GOS" help --json > help.json 2>help.err || { echo "  ✗ help --json exited non-zero"; FAIL=$((FAIL+1)); }
if [ -s help.err ]; then echo "  ✗ help --json must keep stderr empty"; FAIL=$((FAIL+1)); fi
node -e '
  const j = JSON.parse(require("fs").readFileSync("help.json", "utf8"));
  const e = j.commands && j.commands.brownfield;
  if (!e) { console.error("missing brownfield in commands"); process.exit(1); }
  if (e.class !== "global") { console.error("class is " + e.class + ", expected global"); process.exit(1); }
  const want = "gos brownfield [--json] [--overwrite [<asset>]] [--print-agents-skeleton]";
  if (e.usage !== want) { console.error("usage is " + e.usage); process.exit(1); }
' && { echo "  ✓ help --json lists brownfield (class global, exact usage)"; PASS=$((PASS+1)); } || { echo "  ✗ help --json brownfield entry wrong"; FAIL=$((FAIL+1)); }

# --- T78.2: brownfield in KNOWN_CASES AND GLOBAL_CMDS (exact partition) ---
node -e '
  const s = require(process.env.GOS_ROOT + "/bin/lib/nav/registry-consts.cjs");
  const kc = s.KNOWN_CASES.includes("brownfield");
  const gl = s.GLOBAL_CMDS.has("brownfield");
  const other = [s.WRITE_CMDS, s.READ_CMDS, s.EXEC_CMDS].some((x) => x.has("brownfield"));
  if (!kc) { console.error("brownfield not in KNOWN_CASES"); process.exit(1); }
  if (!gl) { console.error("brownfield not in GLOBAL_CMDS"); process.exit(1); }
  if (other) { console.error("brownfield leaked into write/read/exec set (lock conflict, R4-F1)"); process.exit(1); }
' && { echo "  ✓ brownfield ∈ KNOWN_CASES and ∈ GLOBAL_CMDS only"; PASS=$((PASS+1)); } || { echo "  ✗ classification sets wrong"; FAIL=$((FAIL+1)); }

# --- T78.3: _contract freezes status set / state_flags / exit codes / preflight reasons ---
set +e; CONTRACT_OUT=$(node "$GOS" _contract 2>/dev/null); CRC=$?; set -e
assert_exit "_contract exits 0" 0 "$CRC"
for tok in 'created' 'kept_identical' 'kept_conflict' 'locked_user_owned' 'report_only'; do
  assert_contains "_contract freezes status token $tok" "$tok" "$CONTRACT_OUT"
done
for tok in 'inactive' 'untrusted'; do
  assert_contains "_contract freezes state_flags token $tok" "$tok" "$CONTRACT_OUT"
done
# all 6 exit codes WITH their meanings
assert_contains "exit 0 meaning" '0 success' "$CONTRACT_OUT"
assert_contains "exit 1 meaning" '1 generic fatal' "$CONTRACT_OUT"
assert_contains "exit 1 covers corrupt hooks state file" 'corrupt hooks state file' "$CONTRACT_OUT"
assert_contains "exit 2 meaning" '2 locked-overwrite refused' "$CONTRACT_OUT"
assert_contains "exit 3 meaning" '3 unknown asset name' "$CONTRACT_OUT"
assert_contains "exit 4 meaning" '4 non-git or cwd' "$CONTRACT_OUT"
assert_contains "exit 5 meaning" '5 self-repo' "$CONTRACT_OUT"
# preflight reason closed set (review M1: 'symlink escape' added — a symlink
# component resolving outside realpath(top) blocks the path)
for tok in 'path occupied by non-directory' 'dangling symlink' 'unwritable ancestor' 'symlink escape'; do
  assert_contains "_contract freezes preflight reason '$tok'" "$tok" "$CONTRACT_OUT"
done

# --- T78.4: lock-free proof — real adoption run in a fresh git repo takes no .gos/.lock ---
t78_teardown
T78_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t78"
mkdir -p "$T78_DIR" && cd "$T78_DIR" || exit 1
git init -q . || exit 1
set +e; OUT=$(node "$GOS" brownfield 2>&1); RC=$?; set -e
assert_exit "real brownfield adopts exit 0" 0 "$RC"
assert_contains "adoption report titled" "brownfield" "$OUT"
if [ -e ".gos/.lock" ]; then echo "  ✗ .gos/.lock must not exist (lock-free global class)"; FAIL=$((FAIL+1)); else echo "  ✓ .gos/.lock absent after run"; PASS=$((PASS+1)); fi
if [ -d ".gos" ] && [ -e ".gos/.lock" ]; then echo "  ✗ workspace created but lock present"; FAIL=$((FAIL+1)); else echo "  ✓ .gos workspace lock-free (created sans lock or absent)"; PASS=$((PASS+1)); fi

# --- T78.5: registry self-check passes (--version exit 0) ---
set +e; VER=$(node "$GOS" --version 2>&1); VRC=$?; set -e
assert_exit "self-check + --version exit 0" 0 "$VRC"

t78_teardown
echo "--- T78 done ---"
