#!/usr/bin/env bash
# gos-map:cmd gate,map
# gos-map:fn bin/lib/ops/gate.cjs#fn:cmdGate
# T47: require-direction assertion — allowlist CODE-ized defense line
# Single source of truth consumed: .gos/codebase/require-allowlist.json (shared by T46/T47/gate)
# fixture pattern follows T36: sandbox git init -> real scan -> inject edge -> self_sha256 re-sign
T47_DIR=""

t47_setup() {
  T47_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t47"
  mkdir -p "$T47_DIR" && cd "$T47_DIR" || exit 1
}

t47_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T47_DIR"; }

t47_setup
echo "--- T47: require-direction assertion (R-30) ---"

# --- T47.1: self-repo gate codemap carries the direction-assertion green line ---
set +e; OUT=$(cd "$GOS_ROOT" && node "$GOS" map scan >/dev/null 2>&1; node "$GOS" gate codemap 2>&1); RC=$?; set -e
assert_exit "self-repo gate codemap exits 0" 0 "$RC"
assert_contains "direction assertion green line present" "require direction assertion green" "$OUT"

# --- T47.2: fixture repo generates a v2 baseline, then an illegal edge is injected (map→nav banned direction) -> gate red ---
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

# --- T47.3: missing allowlist -> advisory downgrade (gate does not crash) ---
rm "$T47_DIR/violation/.gos/codebase/require-allowlist.json"
set +e; MOUT=$(cd "$T47_DIR/violation" && node "$GOS" gate codemap 2>&1); MRC=$?; set -e
assert_exit "missing allowlist keeps gate exit 0" 0 "$MRC"
assert_contains "missing allowlist degrades to advisory" "direction assertion off" "$MOUT"

# --- T47.4: direction assertion stays green after a self-repo deps rebuild (scan→gate closed loop) ---
set +e; SOUT=$(cd "$GOS_ROOT" && node "$GOS" map scan 2>&1); SRC=$?; set -e
assert_exit "self scan exits 0" 0 "$SRC"
set +e; GOUT=$(cd "$GOS_ROOT" && node "$GOS" gate codemap 2>&1); GRC=$?; set -e
assert_exit "post-scan gate codemap exits 0" 0 "$GRC"
assert_contains "post-scan direction green" "require direction assertion green" "$GOUT"

t47_teardown
