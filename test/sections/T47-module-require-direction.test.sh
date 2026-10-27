#!/usr/bin/env bash
# gos-map:cmd gate,map
# gos-map:fn bin/lib/ops/gate.cjs#fn:cmdGate
# : require-direction assertion — allowlist CODE-ized defense line
# Single source of truth consumed: .gos/codebase/require-allowlist.json (shared by / /gate)
# fixture pattern follows : sandbox git init -> real scan -> inject edge -> self_sha256 re-sign
T47_DIR=""

t47_setup() {
  T47_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t47"
  mkdir -p "$T47_DIR" && cd "$T47_DIR" || exit 1
}

t47_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T47_DIR"; }

t47_setup
echo "--- T47: require-direction assertion (R-30) ---"

# --- .1: self-repo gate codemap stays healthy (green when the machine-local
#     codebase layer exists; advisory-off but exit 0 on a fresh clone) ---
set +e; OUT=$(cd "$GOS_ROOT" && node "$GOS" map scan >/dev/null 2>&1; node "$GOS" gate codemap 2>&1); RC=$?; set -e
assert_exit "self-repo gate codemap exits 0" 0 "$RC"

# --- .2: fixture repo generates a v2 baseline, then an illegal edge is injected (map→nav banned direction) -> gate red
mkdir -p "$T47_DIR/violation/bin/lib/nav" "$T47_DIR/violation/bin/lib/map" "$T47_DIR/violation/bin/lib/core"
cd "$T47_DIR/violation" || exit 1
git init -q . && git commit -q --allow-empty -m root
cat > bin/lib/nav/index.cjs <<'NAV'
'use strict';
const map = require('../map/index.cjs');
function cmdBadNav() { return map.edgeStats ? 1 : 0; }
module.exports = { cmdBadNav };
NAV
printf 'module.exports = {};\n' > bin/lib/map/index.cjs
printf 'module.exports = {};\n' > bin/lib/core/index.cjs
git add -A && git commit -q -m fixture
set +e; (cd "$T47_DIR/violation" && node "$GOS" map scan >/dev/null 2>&1 && node "$GOS" init 1 "t47-violation" >/dev/null 2>&1 && node "$GOS" map allowlist init >/dev/null 2>&1); set -e
assert_file "v2 baseline generated in fixture" "$T47_DIR/violation/.gos/codebase/require-allowlist.json"
# .1b: the fixture's legal dependency direction (nav->map) asserts green — this is
# the sandboxed replacement for the old self-repo green-line check (fresh clones carry
# no .gos/codebase, so the self repo can only promise exit 0 there)
set +e; GOUT0=$(cd "$T47_DIR/violation" && node "$GOS" gate codemap 2>&1); GRC0=$?; set -e
assert_exit "fixture gate codemap exits 0" 0 "$GRC0"
assert_contains "direction assertion green line present" "require direction assertion green" "$GOUT0"
# inject the illegal map→nav edge (banned direction; gate reads the cache without rescanning) + re-sign
node -e "
const fs=require('fs'),crypto=require('crypto');
const p='$T47_DIR/violation/.gos/cache/deps.json';
const d=JSON.parse(fs.readFileSync(p,'utf8'));
d.edges.push({from:'bin/lib/map/index.cjs',to:'bin/lib/nav/index.cjs',kind:'require'});
delete d.self_sha256;
d.self_sha256=crypto.createHash('sha256').update(JSON.stringify(d,null,2)+'\n','utf8').digest('hex');
fs.writeFileSync(p,JSON.stringify(d,null,2));
"
set +e; VOUT=$(cd "$T47_DIR/violation" && node "$GOS" gate codemap 2>&1); VRC=$?; set -e
assert_exit "violation fails gate codemap" 1 "$VRC"
assert_contains "violation names map→nav outside whitelist" "not in the allowlist" "$VOUT"

# --- .3: missing allowlist -> advisory downgrade (gate does not crash)
rm "$T47_DIR/violation/.gos/codebase/require-allowlist.json"
set +e; MOUT=$(cd "$T47_DIR/violation" && node "$GOS" gate codemap 2>&1); MRC=$?; set -e
assert_exit "missing allowlist keeps gate exit 0" 0 "$MRC"
assert_contains "missing allowlist degrades to advisory" "direction assertion off" "$MOUT"

# --- .4: direction assertion stays green on a clean fixture (scan→gate closed loop)
mkdir -p "$T47_DIR/green/bin/lib/nav" "$T47_DIR/green/bin/lib/map" "$T47_DIR/green/bin/lib/core"
cd "$T47_DIR/green" || exit 1
git init -q . && git commit -q --allow-empty -m root
printf "'use strict';\nconst map = require('../map/index.cjs');\nfunction cmdNav() { return map.edgeStats ? 1 : 0; }\nmodule.exports = { cmdNav };\n" > bin/lib/nav/index.cjs
printf 'module.exports = {};\n' > bin/lib/map/index.cjs
printf 'module.exports = {};\n' > bin/lib/core/index.cjs
git add -A && git commit -q -m fixture
set +e; (node "$GOS" map scan >/dev/null 2>&1 && node "$GOS" init 1 "t47-green" >/dev/null 2>&1 && node "$GOS" map allowlist init >/dev/null 2>&1); RC_INIT=$?; set -e
assert_exit "green fixture bootstrap (scan+init+allowlist)" 0 "$RC_INIT"
set +e; GOUT=$(node "$GOS" gate codemap 2>&1); GRC=$?; set -e
assert_exit "post-scan gate codemap exits 0" 0 "$GRC"
assert_contains "post-scan direction green" "require direction assertion green" "$GOUT"

t47_teardown
