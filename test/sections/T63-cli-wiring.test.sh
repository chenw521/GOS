#!/usr/bin/env bash
# gos-map:cmd help,changelog
# T63: CLI wiring for changelog + init git — registry/help/status surfaces wired
# WITHOUT entering the core set (the core set stays ≤ 10).
# Facts asserted:
#   - registry sets: changelog = read-class whole-command; init = write-class
#     (covers the init git sub-mode); changelog.add declared metadata-write
#     subclass (concerns-family pattern: dispatch stays read, mutation under
#     its own internal lock)
#   - help: index row + detail page for changelog; init detail documents the
#     `git` sub-mode
#   - CLI: bare `gos changelog` fails closed with a usage hint
#   - status: BUILD + SHIP instructions carry the changelog obligation hint
#   - core set unchanged: changelog stays non-core (T29 owns the five-doc layer)
T63_DIR=""

t63_setup() {
  T63_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t63"
  mkdir -p "$T63_DIR" && cd "$T63_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t63-seed
  GOS_HEADLESS=1 node "$GOS" init 3 "t63 cli wiring" >/dev/null 2>&1
}

t63_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T63_DIR"; }

echo "--- T63: CLI wiring (changelog + init git, outside the core set) ---"

# ===== R: registry layer (dispatch sets + subclass metadata) =====
node "$GOS" help --json > env.json 2>/dev/null
R1=$(node -e '
const rc = require(process.env.GOS_ROOT + "/bin/lib/nav/registry-consts.cjs");
const bad = [];
if (!rc.KNOWN_CASES.includes("changelog")) bad.push("changelog absent from KNOWN_CASES");
if (!rc.KNOWN_CASES.includes("init")) bad.push("init absent from KNOWN_CASES");
if (!rc.READ_CMDS.has("changelog")) bad.push("changelog not in READ_CMDS");
if (rc.WRITE_CMDS.has("changelog")) bad.push("changelog wrongly in WRITE_CMDS");
if (!rc.WRITE_CMDS.has("init")) bad.push("init not in WRITE_CMDS");
if (rc.READ_CMDS.has("init")) bad.push("init wrongly in READ_CMDS");
if (rc.SUBCLASS_OVERRIDES["changelog.add"] !== "write") bad.push("changelog.add subclass override missing");
if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
console.log("OK");
' 2>&1)
[ "$R1" = "OK" ] && echo "  ✓ R1 dispatch sets: changelog=read, init=write, changelog.add metadata-write subclass" || echo "  ✗ R1 registry mismatch: $R1"

python3 - <<'PYEOF' && echo "  ✓ R2 COMMANDS facts: changelog read/non-core, init core, core ≤10" || echo "  ✗ R2 COMMANDS facts wrong"
import json
env = json.load(open('env.json'))
cl = env['commands'].get('changelog')
assert cl, 'changelog entry missing from COMMANDS'
assert cl['class'] == 'read', cl['class']
assert cl.get('core') is False, 'changelog must stay OUT of the core set (D-20)'
init = env['commands']['init']
assert init['class'] == 'write' and init.get('core') is True
core = {n for n, e in env['commands'].items() if e.get('core')}
assert len(core) <= 10, len(core)
assert 'changelog' not in core
PYEOF

# ===== H: help surface =====
OUT=$(node "$GOS" help 2>&1)
assert_contains "H1 help index lists changelog row" "changelog" "$OUT"
OUT=$(node "$GOS" help changelog 2>&1)
assert_contains "H2 changelog detail shows usage" "gos changelog <sub>" "$OUT"
assert_contains "H2 changelog detail lists lint sub" "lint" "$OUT"
OUT=$(node "$GOS" help init 2>&1)
assert_contains "H3 init detail documents git sub-mode" "gos init git" "$OUT"

# ===== C: CLI fail-closed behavior =====
set +e; OUT=$(node "$GOS" changelog 2>&1); RC=$?; set -e
assert_exit "C1 bare changelog exits non-zero" 1 "$RC"
assert_contains "C1 bare changelog prints usage" "Usage: gos changelog" "$OUT"

# ===== S: instructions hints (needs active state) =====
t63_setup
OUT=$(node "$GOS" instructions build 2>&1)
assert_contains "S1 BUILD hint carries changelog obligation" "gos changelog add" "$OUT"
OUT=$(node "$GOS" instructions ship 2>&1)
assert_contains "S2 SHIP hint carries changelog obligation" "gos changelog add" "$OUT"
t63_teardown

# ===== F: frozen core-set contract (cheap mirror; T29 owns the doc layer) =====
python3 - <<'PYEOF' && echo "  ✓ F1 core set unchanged (≤10; changelog outside, init inside)" || echo "  ✗ F1 core set drifted"
import json
env = json.load(open('env.json'))
core = {n for n, e in env['commands'].items() if e.get('core')}
assert len(core) <= 10
assert 'changelog' not in core and 'init' in core
PYEOF

echo "--- T63 done ---"
