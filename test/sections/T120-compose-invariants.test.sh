#!/usr/bin/env bash
# gos-map:none
# Compose-invariants section — the Class S (script-spawn) writable surface
# and the argv invariants every sandbox frame holds.
# Case map:
#   script-enum     C1  composeScriptSpawn composes an enumerated writable
#                    set: the workspace lands ro-bound, the only rw binds
#                    inside it are .git and .gos/cache, the argv never
#                    carries --unshare-pid/--unshare-all, and
#                    meta.writableShadowed stays empty
#   script-refuse   C2  writable roots outside the enumerated set refuse
#                    the compose fail-closed (bare .gos, the workspace
#                    root, an unlisted path); a refused compose leaves no
#                    spawnreg registration behind
#   shadow-refuse   C3  a policy-bound compose whose writable root sits
#                    under a mask mount refuses (writableShadowed
#                    fail-closed); the same compose without the policy
#                    stays ok and only reports meta.writableShadowed
#   agent-unchanged C4  agent-path shapes (restricted [.gos, .gos/logs],
#                    workspace [root, .gos, .gos/logs]) compose unchanged:
#                    the same rw binds as before and no unshare flags
# Fixture home carries every mandatory mask destination so masks land
# exactly (no ancestor climbs); the store lives under a pinned XDG root.
# Standalone-safe: self-provisions env when not under test/run-sections.sh.

T120_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T120_STANDALONE=1
  T120_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T120_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T120_SELFROOT"
  export TESTBASE="$(mktemp -d "$T120_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T120_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t120"
mkdir -p "$T120_DIR" && cd "$T120_DIR" || exit 1
export T120_DIR

PASS=0
FAIL=0
t120_ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
t120_bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
t120_contains() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then t120_ok "$label"; else
    t120_bad "$label (expected: '$expected')"
    echo "    actual: $(printf '%s' "$actual" | head -c 200)"
  fi
}
t120_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then t120_ok "$label (exit $actual)"; else
    t120_bad "$label (expected exit $expected, got '${actual:-<none>}')"; fi
}

t120_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T120_DIR"
  if [ "$T120_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t120_teardown EXIT

echo "--- T120: compose invariants (script writable enum, refusal, shadow fail-closed, agent unchanged) ---"

T120_L="$T120_DIR/env"
mkdir -p "$T120_L/home/.config/gh" "$T120_L/home/.config/git" "$T120_L/home/.config/opencode" \
  "$T120_L/home/.local/share/opencode" "$T120_L/home/.cache/opencode" \
  "$T120_L/home/.ssh" "$T120_L/home/.aws" "$T120_L/home/.gnupg" \
  "$T120_L/xdg/gos" "$T120_L/ws-repo/.gos/cache" "$T120_L/ws-repo/src"
: > "$T120_L/home/.gitconfig"
: > "$T120_L/home/.netrc"
: > "$T120_L/home/.git-credentials"
export HOME="$T120_L/home"
export XDG_DATA_HOME="$T120_L/xdg"

cat > "$T120_DIR/compose-invariants.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const workers = require(path.join(GR, 'bin/lib/ops/auto/workers.cjs'));
const launcher = require(path.join(GR, 'bin/lib/ops/auto/launcher.cjs'));
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const problems = [];
const home = process.env.HOME;
const ws = path.join(path.dirname(home), 'ws-repo');
const env = { ...process.env };
const bwrap = () => ({ engine: 'bwrap', version: '0.11.0' });
const step = { id: 'sections', command: ['bash', 'test/run-sections.sh'] };

const BIND_OPS = ['--ro-bind', '--ro-bind-try', '--bind', '--bind-try', '--dev-bind'];
const DEST_OPS = ['--tmpfs', '--proc', '--dev', '--dir'];
function ops(argv) {
  const out = [];
  for (let i = 0; i < argv.length;) {
    const t = argv[i];
    if (BIND_OPS.includes(t)) { out.push({ op: t, src: argv[i + 1], dest: argv[i + 2] }); i += 3; }
    else if (DEST_OPS.includes(t)) { out.push({ op: t, dest: argv[i + 1] }); i += 2; }
    else i += 1;
  }
  return out;
}
const under = (root, p) => p === root || p.startsWith(root + path.sep);
const rwRel = (argv, root) => ops(argv)
  .filter((o) => o.op === '--bind' && under(root, o.dest))
  .map((o) => path.relative(root, o.dest)).sort();
const noUnshare = (argv) => !argv.includes('--unshare-pid') && !argv.includes('--unshare-all');

// C1: the script-spawn frame carries the enumerated writable set
const c = workers.composeScriptSpawn(step, {
  stage: 'VERIFY', spawnId: 't120.c1.sp1', rootDir: ws, workspace: ws,
  env, engineProbe: bwrap,
});
if (!c.ok) problems.push('script compose refused: ' + (c.code || c.reason) + ' ' + (c.detail || ''));
let scriptRw = [];
if (c.ok) {
  scriptRw = rwRel(c.argv, ws);
  if (!ops(c.argv).some((o) => o.op === '--ro-bind' && o.dest === ws)) problems.push('workspace not ro-bound');
  if (ops(c.argv).some((o) => o.op === '--bind' && o.dest === ws)) problems.push('workspace rw-bound');
  if (!ops(c.argv).some((o) => o.op === '--bind' && o.dest === path.join(ws, '.gos', 'cache'))) {
    problems.push('enumerated writable .gos/cache missing');
  }
  if (!noUnshare(c.argv)) problems.push('script argv carries an unshare flag');
  if (!Array.isArray(c.meta.writableShadowed) || c.meta.writableShadowed.length) {
    problems.push('script meta.writableShadowed not empty');
  }
}

// C2: writable roots outside the enumerated set refuse fail-closed
const refusals = [];
for (const [tag, roots] of [
  ['gos', [path.join(ws, '.gos')]],
  ['wsroot', [ws]],
  ['src', [path.join(ws, 'src')]],
]) {
  const r = workers.composeScriptSpawn(step, {
    stage: 'VERIFY', spawnId: 't120.c2.' + tag, rootDir: ws, workspace: ws,
    env, engineProbe: bwrap, writableRoots: roots,
  });
  refusals.push(tag + ':' + (r.ok ? 'ok' : (r.code || r.reason)));
}
const regDir = path.join(store.storeRoot(ws), 'spawnreg');
let leftovers = [];
try { leftovers = fs.readdirSync(regDir).filter((n) => n.startsWith('t120.c2.')); } catch {}

// C3: policy-bound compose fails closed on a mask-shadowed writable root;
// the same compose without the policy reports the shadow and stays ok
const maskDir = path.join(home, '.local', 'share', 'opencode');
const shadowRoot = path.join(maskDir, 'w');
const pol = launcher.compose('restricted', {
  workspace: ws, env, engineProbe: bwrap,
  writableRoots: [shadowRoot], writablePolicy: { allow: [shadowRoot] },
});
const bare = launcher.compose('restricted', {
  workspace: ws, env, engineProbe: bwrap,
  writableRoots: [shadowRoot],
});
const bareShadowed = bare.ok && Array.isArray(bare.meta.writableShadowed)
  ? bare.meta.writableShadowed.length : -1;

// C4: agent-path shapes compose unchanged
const agR = launcher.compose('restricted', {
  workspace: ws, env, engineProbe: bwrap,
  writableRoots: [path.join(ws, '.gos'), path.join(ws, '.gos', 'logs')],
});
const agW = launcher.compose('workspace', {
  workspace: ws, env, engineProbe: bwrap,
  writableRoots: [ws, path.join(ws, '.gos'), path.join(ws, '.gos', 'logs')],
});
if (agR.ok && (!noUnshare(agR.argv) || !Array.isArray(agR.meta.writableShadowed) || agR.meta.writableShadowed.length)) {
  problems.push('restricted agent shape drifted');
}
if (agW.ok && !noUnshare(agW.argv)) problems.push('workspace agent shape carries an unshare flag');

console.log(problems.length ? 'T120-BAD ' + problems.join('; ') : 'T120-OK');
console.log('SCRIPTRW[' + scriptRw.join(',') + ']');
console.log('REFUSE[' + refusals.join(',') + ']');
console.log('NOREG[' + (leftovers.length ? 'left:' + leftovers.join(',') : 'clean') + ']');
console.log('SHADOW[policy:' + (pol.ok ? 'ok' : pol.code) + ',bare:' + (bare.ok ? 'ok:' + bareShadowed : 'refused') + ']');
console.log('AGENTRW[restricted:' + (agR.ok ? rwRel(agR.argv, ws).join(',') : 'refused')
  + ';workspace:' + (agW.ok ? rwRel(agW.argv, ws).join(',') : 'refused') + ']');
EOF
INV_OUT="$(node "$T120_DIR/compose-invariants.cjs" 2>&1)"; RC=$?
t120_exit "compose-invariants probe runs clean" "0" "$RC"
t120_contains "script frame: workspace ro, writable enum .gos/cache, no unshare flags, shadow empty" "T120-OK" "$INV_OUT"
t120_contains "script rw binds inside the workspace are exactly .git and .gos/cache" "SCRIPTRW[.git,.gos/cache]" "$INV_OUT"
t120_contains "bare .gos, workspace root and unlisted writable each refuse outside-policy" "REFUSE[gos:auto.launcher.writable-outside-policy,wsroot:auto.launcher.writable-outside-policy,src:auto.launcher.writable-outside-policy]" "$INV_OUT"
t120_contains "refused composes leave no spawnreg registration" "NOREG[clean]" "$INV_OUT"
t120_contains "policy compose fails closed on the shadowed writable; no-policy stays report-only" "SHADOW[policy:auto.launcher.writable-shadowed,bare:ok:1]" "$INV_OUT"
t120_contains "agent-path rw binds unchanged (restricted and workspace shapes)" "AGENTRW[restricted:.git,.gos,.gos/logs;workspace:,.git,.gos,.gos/logs]" "$INV_OUT"

echo "--- T120 done: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
