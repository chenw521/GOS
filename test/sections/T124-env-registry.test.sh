#!/usr/bin/env bash
# gos-map:file bin/lib/ops/auto/launcher.cjs
# gos-map:file bin/lib/ops/auto/loop.cjs
# gos-map:file test/run-sections.sh
# Env-registry section — every GOS_AUTO_* env name the auto family defines
# lives in one exported registry (launcher ALL_GOS_AUTO_ENV); the section
# runner sweeps from that registry at runtime, and the Class S spec env
# adds only the session pair (marker + spawn id) over the compose channel
# vars, so runner-side GOS_AUTO_* values never ride the passthrough.
# Case map:
#   drift      C1  every GOS_AUTO_[A-Z0-9_]+ literal in source files under a
#                  target root is a registry member (the checker takes the
#                  root as an argument, so scratch-copy negatives work)
#   drift-neg  C2  a scratch copy of bin/ carrying one planted unregistered
#                  literal reds the same checker
#   coherence  C3  run-sections.sh sweeps from the registry: planted members
#                  (marker pair + a timeout channel) vanish before sections
#                  run, an unregistered survivor is named in a grep-able
#                  warning, and the zero-section run stays rc 0
#   class-s    C4  the Class S spec env allowlist holds: marker + spawn id
#                  over the compose channel vars; planted runner-side leaks
#                  (fixture switch, timeout channels, ack wait, stale session
#                  pair, approvals baseline) never cross into the spawn env
# Standalone-safe: self-provisions env when not under test/run-sections.sh.

T124_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T124_STANDALONE=1
  T124_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T124_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T124_SELFROOT"
  export TESTBASE="$(mktemp -d "$T124_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi
# The section runner exports GOS_ROOT; any other entry mode derives it from
# the script location so both see the same tree.
if [ -z "${GOS_ROOT:-}" ]; then
  T124_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS_ROOT="$T124_SELFROOT"
  export GOS="$T124_SELFROOT/bin/gos.cjs"
fi

T124_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t124"
mkdir -p "$T124_DIR" && cd "$T124_DIR" || exit 1
export T124_DIR

PASS=0
FAIL=0
t124_ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
t124_bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
t124_contains() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then t124_ok "$label"; else
    t124_bad "$label (expected: '$expected')"
    echo "    actual: $(printf '%s' "$actual" | head -c 200)"
  fi
}
t124_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then t124_ok "$label (exit $actual)"; else
    t124_bad "$label (expected exit $expected, got '${actual:-<none>}')"; fi
}

t124_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T124_DIR"
  if [ "$T124_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t124_teardown EXIT

echo "--- T124: GOS_AUTO_* env registry (drift, runner sweep, Class S allowlist) ---"

# ---------------------------------------------------------------- C1 --
# Drift checker: takes the target root as an argument, collects every
# GOS_AUTO_[A-Z0-9_]+ literal from source files under it, and reports any
# literal missing from the launcher registry.
cat > "$T124_DIR/env-registry-drift.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const root = path.resolve(process.argv[2]);
const reg = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/launcher.cjs')).ALL_GOS_AUTO_ENV;
const registry = new Set(Array.isArray(reg) ? reg : []);
const EXTS = new Set(['.cjs', '.js', '.mjs', '.json']);
const found = new Set();
(function walk(dir) {
  let names = [];
  try { names = fs.readdirSync(dir); } catch { return; }
  for (const name of names) {
    const p = path.join(dir, name);
    let st = null;
    try { st = fs.statSync(p); } catch { continue; }
    if (st.isDirectory()) {
      if (name !== 'node_modules') walk(p);
      continue;
    }
    if (!EXTS.has(path.extname(name))) continue;
    let text = '';
    try { text = fs.readFileSync(p, 'utf8'); } catch { continue; }
    // Scan quoted spans per line: env names are always quoted at their
    // definition sites, line scoping keeps comment apostrophes from pairing
    // across lines, and the registry's own export name (an unquoted
    // identifier) never matches itself.
    for (const line of text.split('\n')) {
      for (const q of line.matchAll(/'([^']*)'|"([^"]*)"/g)) {
        const s = q[1] != null ? q[1] : q[2];
        for (const m of s.matchAll(/GOS_AUTO_[A-Z0-9_]+/g)) found.add(m[0]);
      }
    }
  }
})(root);
const missing = [...found].filter((n) => !registry.has(n)).sort();
console.log('LITERALS[' + [...found].sort().join(',') + ']');
console.log(missing.length ? 'DRIFT[' + missing.join(',') + ']' : 'DRIFT[none]');
EOF

DRIFT_OUT="$(node "$T124_DIR/env-registry-drift.cjs" "$GOS_ROOT/bin" 2>&1)"; DRIFT_RC=$?
t124_exit "drift probe runs clean over the live bin/ tree" "0" "$DRIFT_RC"
t124_contains "every GOS_AUTO_ literal under bin/ is a registry member" "DRIFT[none]" "$DRIFT_OUT"

# ---------------------------------------------------------------- C2 --
# Negative: the same checker over a scratch copy of bin/ with one planted
# unregistered literal must red — the copy lives under the section sandbox,
# never the repo tree.
mkdir -p "$T124_DIR/scrneg"
cp -r "$GOS_ROOT/bin" "$T124_DIR/scrneg/bin"
printf '\nconst PLANTED_LEAK_ENV = %s;\n' "'GOS_AUTO_PLANTED_REGISTRY_LEAK'" >> "$T124_DIR/scrneg/bin/lib/ops/auto/launcher.cjs"
NEG_OUT="$(node "$T124_DIR/env-registry-drift.cjs" "$T124_DIR/scrneg/bin" 2>&1)"; NEG_RC=$?
t124_exit "negative probe runs clean over the scratch copy" "0" "$NEG_RC"
t124_contains "planted unregistered literal reds the drift checker" "DRIFT[GOS_AUTO_PLANTED_REGISTRY_LEAK]" "$NEG_OUT"

# ---------------------------------------------------------------- C3 --
# Registry-vs-runner coherence: the section runner sweeps from the registry
# at runtime. Members planted in the env (the session pair plus a timeout
# channel the old hand list never covered) vanish; an unregistered survivor
# is named in a grep-able warning; a zero-section run stays rc 0.
if grep -q "ALL_GOS_AUTO_ENV" "$GOS_ROOT/test/run-sections.sh"; then
  t124_ok "run-sections.sh reads the launcher registry"
else
  t124_bad "run-sections.sh does not reference ALL_GOS_AUTO_ENV (hand list drift)"
fi
T124_PIN="$T124_DIR/tb-pin"
mkdir -p "$T124_PIN"
env -u XDG_DATA_HOME TESTBASE="$T124_PIN" \
  GOS_AUTO_SPAWNED=1 GOS_AUTO_SPAWN_ID=t124-sweep GOS_AUTO_TIMEOUT_WALL_SEC=999 \
  GOS_AUTO_PLANTED_SURVIVOR=1 \
  bash "$GOS_ROOT/test/run-sections.sh" NO-SUCH-SECTION-T124 > "$T124_DIR/sweep.out" 2>&1
SWEEP_RC=$?
t124_exit "zero-section sweep run stays green (warning, not failure)" "0" "$SWEEP_RC"
SURV_LINE="$(grep 'env-sweep-survivors' "$T124_DIR/sweep.out" | head -n 1)"
if [ -n "$SURV_LINE" ]; then
  t124_ok "survivor warning is grep-able in runner output"
else
  t124_bad "no env-sweep-survivors warning line in runner output"
fi
t124_contains "unregistered survivor is named in the warning" "GOS_AUTO_PLANTED_SURVIVOR" "$SURV_LINE"
if printf '%s' "$SURV_LINE" | grep -q "GOS_AUTO_TIMEOUT_WALL_SEC"; then
  t124_bad "registry member GOS_AUTO_TIMEOUT_WALL_SEC survived the sweep (sweep not registry-driven)"
else
  t124_ok "registry members (session pair, timeout channel) swept before sections"
fi
if printf '%s' "$SURV_LINE" | grep -q "GOS_AUTO_SPAWNED"; then
  t124_bad "marker survived the sweep"
else
  t124_ok "marker pair swept (no false survivor)"
fi

# ---------------------------------------------------------------- C4 --
# Class S spec env allowlist: through a loop-driven VERIFY stage (pinned
# legs stubbed green, sections spawn captured), the script spawn env holds
# only the session pair beyond the compose channel vars — planted
# runner-side GOS_AUTO_* values never cross the passthrough.
T124_WS="$T124_DIR/ws-repo"
mkdir -p "$T124_WS/.gos/task/p1" "$T124_DIR/xdg"
printf '# Spec\n\np1 spec\n' > "$T124_WS/.gos/task/p1/spec.md"
git -C "$T124_WS" init -q
git -C "$T124_WS" commit -q --allow-empty -m root
git -C "$T124_WS" config user.name gos-test
git -C "$T124_WS" config user.email gos-test@test.invalid
T124_HEAD="$(git -C "$T124_WS" rev-parse HEAD)"
printf '{"schema_version":6,"level":3,"current_stage":"VERIFY","completed_stages":["INTENT"],"intent":{"summary":"t124 fixture","confirmed":true},"task_head":"%s","spec_path":".gos/task/p1/spec.md","plan_path":null,"requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{},"semantic":{"allowlist":["t124-classs.cjs"]}}' \
  "$T124_HEAD" > "$T124_WS/.gos/state.json"

cat > "$T124_DIR/t124-classs.cjs" <<'EOF'
const store = require(require('path').join(process.env.GOS_ROOT, 'bin/lib/ops/auto/store.cjs'));
const loop = require(require('path').join(process.env.GOS_ROOT, 'bin/lib/ops/auto/loop.cjs'));
const problems = [];
const world = process.env.T124_WS;
(async () => {
  const specs = [];
  const spawnRunner = (spec) => { specs.push(spec); return { status: 0, stdout: 'sections pass\n', stderr: '' }; };
  const probeRunner = () => { throw new Error('host probe must never run for a script stage'); };
  const env = {
    ...process.env,
    GOS_AUTO_TEST_FIXTURE: '1',
    GOS_AUTO_TIMEOUT_WALL_SEC: '123',
    GOS_AUTO_TIMEOUT_IDLE_SEC: '45',
    GOS_AUTO_SPAWN_ACK_WAIT_MS: '777',
    GOS_AUTO_DIRTY_BASELINE: '[]',
    GOS_AUTO_APPROVALS_BASELINE: '0'.repeat(64),
  };
  store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
  const r = await loop.createLoop({
    rootDir: world, host: 'opencode', env, maxIterations: 3, spawnRunner, probeRunner,
    engineProbe: () => ({ engine: 'bwrap', version: '0.11.0' }),
    legRunner: () => ({ ok: true, verdict: { ok: true, failures: [] } }),
  }).loop.run();
  const spec = specs.find((s) => s.kind === 'script');
  if (!spec) problems.push('no script spawn composed');
  else {
    const allowed = ['GOS_AUTO_ACK_DIR', 'GOS_AUTO_GRANT_MANIFEST', 'GOS_AUTO_SPAWN_ID', 'GOS_AUTO_SPAWNED', 'GOS_AUTO_SPAWN_SCRATCH'];
    for (const k of Object.keys(spec.env)) {
      if (k.startsWith('GOS_AUTO_') && !allowed.includes(k)) problems.push('unexpected GOS_AUTO_* in the spec env: ' + k);
    }
    if (spec.env.GOS_AUTO_SPAWNED !== '1') problems.push('session marker missing from the spec env');
    if (spec.env.GOS_AUTO_SPAWN_ID !== spec.spawnId) problems.push('spec env spawn id is not the composed id: ' + String(spec.env.GOS_AUTO_SPAWN_ID));
    for (const leaked of ['GOS_AUTO_TEST_FIXTURE', 'GOS_AUTO_TIMEOUT_WALL_SEC', 'GOS_AUTO_TIMEOUT_IDLE_SEC', 'GOS_AUTO_SPAWN_ACK_WAIT_MS', 'GOS_AUTO_DIRTY_BASELINE', 'GOS_AUTO_APPROVALS_BASELINE']) {
      if (spec.env[leaked] !== undefined) problems.push('runner-side value leaked into the Class S spec env: ' + leaked);
    }
  }
  console.log(problems.length ? 'C4-BAD ' + problems.join('; ') : 'C4-OK');
  console.log('RUN[' + r.status + '/' + (r.ok ? 'ok' : String(r.reason || '')) + ']');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C4_OUT="$(env T124_WS="$T124_WS" XDG_DATA_HOME="$T124_DIR/xdg" node "$T124_DIR/t124-classs.cjs" 2>&1)"; C4_RC=$?
t124_exit "class-s probe runs clean" "0" "$C4_RC"
t124_contains "Class S spec env = marker + spawn id over the compose channel vars" "C4-OK" "$C4_OUT"
t124_contains "VERIFY stage still advances through the exit channel" "RUN[ship/ok]" "$C4_OUT"

echo "--- T124 done: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
