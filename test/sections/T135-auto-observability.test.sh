#!/usr/bin/env bash
# gos-map:none
# gos-tier:main
# Auto liveness telemetry + status latest-run line — the pin survival path
# made operator-visible. Three surfaces, one story:
#   C1  pin-liveness probes bracket every Class S step: the run log carries
#       `pin-live: pre-spawn` and `pin-live: post-settle` lines around the
#       script-step window, in order, both reporting the pin registration
#       live
#   C2  a heal is one stderr line (runTag, budget remaining) and one
#       persisted count: a pin killed mid-run heals on the next pinned leg,
#       the log carries `pin-heal:` with heals=1/2, and the run record
#       carries heals:1
#   C3  `auto status` renders a latest-run line (end status, dropped
#       records, pin heals) when the store holds run records, and renders
#       nothing on an empty store — no empty-field noise
#   C4  locale parity: en and zh both carry the latest-run key
# Loop spawns run through injected spawnRunner/legRunner harnesses only.
# HOME and XDG_DATA_HOME are pinned per case under TESTBASE. Standalone-safe.

T135_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T135_STANDALONE=1
  T135_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T135_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T135_SELFROOT"
  export TESTBASE="$(mktemp -d "$T135_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T135_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t135"
mkdir -p "$T135_DIR" && cd "$T135_DIR" || exit 1

PASS=0
FAIL=0
t135_ok() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
t135_bad() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
t135_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t135_ok "$label"; else
    t135_bad "$label (expected: '$expected', got: '$actual')"
  fi
}

t135_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T135_DIR"
  if [ "$T135_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t135_teardown EXIT

echo "--- T135: auto liveness telemetry + status latest-run ---"

# One isolated case world per call: sandbox HOME + XDG_DATA_HOME + a git
# repo with a minimal task state (the auto section case-world shape).
t135_case() {
  T135_CASE="$T135_DIR/$1"
  mkdir -p "$T135_CASE/home" "$T135_CASE/xdg" "$T135_CASE/repo/.gos/logs"
  export HOME="$T135_CASE/home"
  export XDG_DATA_HOME="$T135_CASE/xdg"
  cd "$T135_CASE/repo" || exit 1
  git init -q -b work . && git commit -q --allow-empty -m root
}

# Minimal task state fixture pinned at VERIFY (level 3): the script worker
# stage whose steps the harness answers.
t135_state_verify() {
  mkdir -p .gos/task/p0 .gos/logs
  printf '# Spec\n\np0 auto spec\n' > .gos/task/p0/spec.md
  printf '{"schema_version":6,"level":3,"current_stage":"VERIFY","completed_stages":["INTENT","THINK","PLAN","BUILD","REVIEW"],"intent":{"summary":"t135 fixture","confirmed":true},"task_head":"abc123def0123456789abcdef0123456789abcde","spec_path":".gos/task/p0/spec.md","plan_path":null,"requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{},"semantic":{"allowlist":["run.cjs"]}}' > .gos/state.json
  node -e "const fs=require('fs');const p='.gos/state.json';const st=JSON.parse(fs.readFileSync(p,'utf8'));const {execSync}=require('child_process');st.task_head=execSync('git rev-parse HEAD').toString().trim();fs.writeFileSync(p,JSON.stringify(st,null,2));"
}

# ---------------------------------------------------------------- C1 --
# Bracketing: a harness-driven script-VERIFY run (green legs, echo child)
# whose stderr carries pin-live pre-spawn + post-settle around the script
# step marker, order-correct, both live.
t135_case c1
t135_state_verify
export GOS_AUTO_TIMEOUT_WALL_SEC=2 GOS_AUTO_TIMEOUT_IDLE_SEC=1
cat > run.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const world = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
const spawnRunner = (spec) => {
  process.stderr.write('SCRIPT-STEP-RAN\n');
  return { status: 0, stdout: 'sections pass\n', stderr: '' };
};
loop.createLoop({
  rootDir: world, host: 'opencode', env, maxIterations: 3, spawnRunner,
  engineProbe: () => ({ engine: 'bwrap', version: '0.11.0' }),
  legRunner: () => ({ ok: true, verdict: { ok: true, failures: [] } }),
}).loop.run().then((r) => {
  console.log(`RES ${r.status}|${r.reason || ''}`);
}).catch((e) => { console.error(e); process.exit(1); });
EOF
C1_ALL="$(node run.cjs 2>&1)"
C1_OUT="$(printf '%s\n' "$C1_ALL" | grep -v '^RES ')"
t135_eq "C1: run reaches SHIP" "ship|stage-ship" "$(printf '%s\n' "$C1_ALL" | grep '^RES ' | cut -d' ' -f2-)"
t135_eq "C1: pre-spawn probe fires and reports a live pin" "yes" "$(printf '%s\n' "$C1_OUT" | grep 'pin-live: pre-spawn' | head -1 | sed 's/.*live=//')"
C1_PRE="$(printf '%s\n' "$C1_OUT" | grep -n 'pin-live: pre-spawn' | head -1 | cut -d: -f1)"
C1_STEP="$(printf '%s\n' "$C1_OUT" | grep -n 'SCRIPT-STEP-RAN' | head -1 | cut -d: -f1)"
C1_POST="$(printf '%s\n' "$C1_OUT" | grep -n 'pin-live: post-settle' | head -1 | cut -d: -f1)"
if [ -n "$C1_PRE" ] && [ -n "$C1_STEP" ] && [ -n "$C1_POST" ] && [ "$C1_PRE" -lt "$C1_STEP" ] && [ "$C1_STEP" -lt "$C1_POST" ]; then
  t135_ok "C1: probes bracket the script-step window in order (pre $C1_PRE < step $C1_STEP < post $C1_POST)"
else
  t135_bad "C1: probes bracket the script-step window in order (pre '${C1_PRE:-none}', step '${C1_STEP:-none}', post '${C1_POST:-none}')"
fi
t135_eq "C1: post-settle probe reports a live pin" "yes" "$(printf '%s\n' "$C1_OUT" | grep 'pin-live: post-settle' | head -1 | sed 's/.*live=//')"

# ---------------------------------------------------------------- C2 --
# Heal line + persisted count: no legRunner injection — the legs load
# through the pin. The fixture repo carries a minimal gate leg module at
# the loop-start commit; the sections spawnRunner kills the pin worktree
# mid-run, so the truth leg heals it. stderr carries one pin-heal line with
# heals=1/2 and the run record carries heals:1.
t135_case c2
mkdir -p bin/lib/ops
cat > bin/lib/ops/gate.cjs <<'EOF'
module.exports = { computeGateVerdicts: () => ({ ok: true, failures: [] }) };
EOF
git add bin/lib/ops/gate.cjs && git commit -q -m "fixture: gate leg module"
t135_state_verify
cat > run.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const world = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
const spawnRunner = (spec) => {
  const pins = store.readPins(world);
  if (pins.ok) {
    for (const rec of Object.values(pins.pins)) {
      try { fs.rmSync(rec.path, { recursive: true, force: true }); } catch { /* already gone */ }
    }
  }
  process.stderr.write('PIN-KILLED\n');
  return { status: 0, stdout: 'sections pass\n', stderr: '' };
};
loop.createLoop({
  rootDir: world, host: 'opencode', env, maxIterations: 3, spawnRunner,
  engineProbe: () => ({ engine: 'bwrap', version: '0.11.0' }),
}).loop.run().then((r) => {
  const list = store.readRunRecords(world);
  const rec = list.ok && list.runRecords.length ? list.runRecords[list.runRecords.length - 1] : null;
  console.log(`RES ${r.status}|${r.reason || ''}`);
  console.log(`RECORD-HEALS ${rec && Number.isInteger(rec.heals) ? rec.heals : 'absent'}`);
}).catch((e) => { console.error(e); process.exit(1); });
EOF
C2_ALL="$(node run.cjs 2>&1)"
C2_ERR="$(printf '%s\n' "$C2_ALL" | grep -v '^RES \|RECORD-HEALS ')"
t135_eq "C2: run reaches SHIP through the healed pin" "ship|stage-ship" "$(printf '%s\n' "$C2_ALL" | grep '^RES ' | cut -d' ' -f2-)"
t135_eq "C2: pin was actually killed mid-run" "1" "$(printf '%s\n' "$C2_ALL" | grep -c 'PIN-KILLED')"
t135_eq "C2: heal line carries the budget spent and remaining" "1" "$(printf '%s\n' "$C2_ERR" | grep -c 'pin-heal: runTag=.* heals=1/2')"
t135_eq "C2: run record carries the persisted heal count" "1" "$(printf '%s\n' "$C2_ALL" | grep '^RECORD-HEALS ' | cut -d' ' -f2-)"
C2_HEALS="$(printf '%s\n' "$C2_ERR" | grep -n 'pin-heal:' | head -1 | cut -d: -f1)"
C2_KILL="$(printf '%s\n' "$C2_ERR" | grep -n 'PIN-KILLED' | head -1 | cut -d: -f1)"
if [ -n "$C2_KILL" ] && [ -n "$C2_HEALS" ] && [ "$C2_KILL" -lt "$C2_HEALS" ]; then
  t135_ok "C2: heal line follows the kill (kill line $C2_KILL < heal line $C2_HEALS)"
else
  t135_bad "C2: heal line follows the kill (kill '${C2_KILL:-none}', heal '${C2_HEALS:-none}')"
fi

# ---------------------------------------------------------------- C3 --
# Status latest-run line: a seeded store (2 dropped records + 1 latest ship
# record with heals:1) renders the line with all three fields; an empty
# store renders no latest-run line at all.
t135_case c3a
node -e "
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
const base = { runId: '11111111-1111-4111-8111-111111111111', runTag: 'tagaa11', taskId: 'task', startedAtIso: '2026-01-01T00:00:00.000Z', endedAtIso: '2026-01-01T00:05:00.000Z', endState: { ok: false, status: 'killed', reason: 'SIGTERM' }, stages: [] };
store.writeRunRecord({ ...base, droppedRecord: true }, world);
store.writeRunRecord({ ...base, runId: '22222222-2222-4222-8222-222222222222', runTag: 'tagbb22', droppedRecord: true }, world);
store.writeRunRecord({ ...base, runId: '33333333-3333-4333-8333-333333333333', runTag: 'tagcc33', endState: { ok: true, status: 'ship', reason: 'stage-ship' }, heals: 1 }, world);
"
GOS_AUTO_TEST_FIXTURE=1 node "$GOS" auto status > c3-status.txt 2>&1
t135_eq "C3: status renders the latest-run line with all three fields" "1" "$(grep -c 'latest run: ship · dropped records: 2 · pin heals: 1' c3-status.txt)"

t135_case c3b
node -e "
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
store.create({ mode: 'on', rootDir: process.cwd(), limits: { N: 3, K: 9, B: 9 } });
"
GOS_AUTO_TEST_FIXTURE=1 node "$GOS" auto status > c3b-status.txt 2>&1
t135_eq "C3: empty store renders no latest-run line" "0" "$(grep -c 'latest run:' c3b-status.txt)"

# ---------------------------------------------------------------- C4 --
# Locale parity: the key exists in en and zh (same placeholder surface).
t135_eq "C4: en carries the latest-run key" "1" "$(grep -c 'auto.cli.status.latestRun' "$GOS_ROOT/bin/lib/core/locales/en.cjs")"
t135_eq "C4: zh carries the latest-run key" "1" "$(grep -c 'auto.cli.status.latestRun' "$GOS_ROOT/bin/lib/core/locales/zh.cjs")"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
