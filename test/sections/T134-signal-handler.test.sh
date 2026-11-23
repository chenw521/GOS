#!/usr/bin/env bash
# gos-map:none
# Signal-handler section — the restart-safe shutdown path: one synchronous
# handler for SIGTERM/SIGHUP/SIGINT kills tracked children, lands the killed
# run record (store, or the crash-side drop sidecar under store-busy), and
# exits 128 + signum so the run lock's exit hook releases the lock. The
# handler arms only after the run lock, recovery, and runner state exist;
# every normal exit route disarms before its record write.
# Case map:
#   C1  SIGTERM mid-step: child exits 143, the store holds the killed record
#       (in-flight VERIFY entry, completed steps only), the handler telemetry
#       line prints, the lock is re-acquirable, and a restart harness run
#       acquires and exits cleanly
#   C2  disarm proof: a normal run completes with all three listener counts
#       back at zero (printed by the harness child itself)
#   C3  store-busy: a foreign live mutate lock routes the killed record to
#       the drop sidecar (one structurally valid line, nothing in
#       runRecords); exit stays 143
#   C4  latch: two rapid self-sent SIGTERMs produce exactly one killed record
#   C5  SIGHUP variant: exit 129, endState reason SIGHUP
# Subprocess-driven: every loop run lives in its own node child; the parent
# signals the child's pid directly (no bwrap). HOME and XDG_DATA_HOME are
# pinned per case under TESTBASE. Standalone-safe.
# Loop spawns run through injected spawnRunner/legRunner harnesses only.

T134_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T134_STANDALONE=1
  T134_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T134_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T134_SELFROOT"
  export TESTBASE="$(mktemp -d "$T134_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T134_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t134"
mkdir -p "$T134_DIR" && cd "$T134_DIR" || exit 1

PASS=0
FAIL=0
T134_PIDS=""
t134_ok() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
t134_bad() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
t134_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t134_ok "$label"; else
    t134_bad "$label (expected: '$expected', got: '$actual')"
    echo "    actual: $(printf '%s' "$actual" | head -c 200)"
  fi
}
t134_contains() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then t134_ok "$label"; else
    t134_bad "$label (expected substring: '$expected')"
    echo "    actual: $(printf '%s' "$actual" | head -c 200)"
  fi
}

t134_teardown() {
  for p in $T134_PIDS; do kill -9 "$p" 2>/dev/null; done
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T134_DIR"
  if [ "$T134_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t134_teardown EXIT

echo "--- T134: signal handler (killed record, child kill, lock release) ---"

t134_case() {
  T134_CASE="$T134_DIR/$1"
  mkdir -p "$T134_CASE/home" "$T134_CASE/xdg" "$T134_CASE/repo/.gos/logs"
  export HOME="$T134_CASE/home"
  export XDG_DATA_HOME="$T134_CASE/xdg"
  cd "$T134_CASE/repo" || exit 1
  git init -q -b work . && git commit -q --allow-empty -m root
}

# VERIFY-stage fixture with task_head pinned to HEAD (the script stage never
# probes the host; P legs ride the injected legRunner, the first S step runs
# through the injected spawnRunner).
t134_write_state() {
  printf '{"schema_version":6,"level":3,"current_stage":"VERIFY","completed_stages":["INTENT","THINK","PLAN","BUILD","REVIEW"],"intent":{"summary":"t134 fixture","confirmed":true},"task_head":"abc123def0123456789abcdef0123456789abcde","spec_path":null,"plan_path":null,"requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{}}' > .gos/state.json
  node -e "const fs=require('fs');const p='.gos/state.json';const st=JSON.parse(fs.readFileSync(p,'utf8'));const {execSync}=require('child_process');st.task_head=execSync('git rev-parse HEAD').toString().trim();fs.writeFileSync(p,JSON.stringify(st,null,2));"
}

# Harness child: drives one real runLoop run. T134_MODE selects the spawn
# runner shape — blocked (write the marker, never resolve), latch (self-send
# two SIGTERMs then block), normal (quick pass-through for exit-route runs).
t134_write_harness() {
  cat > harness.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const world = process.cwd();
const mode = process.env.T134_MODE || 'blocked';
store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
const marker = path.join(world, 'blocked.marker');
const env = { ...process.env };
// A never-resolving promise holds no event-loop handle: without a live
// ref'd timer the loop empties and the child exits 0 before any signal
// can land. The ref'd interval keeps the blocked run open.
const hang = () => { setInterval(() => {}, 1 << 30); };
const blockedRunner = () => new Promise(() => {
  fs.writeFileSync(marker, String(process.pid));
  hang();
});
const spawnRunner = mode === 'latch'
  ? () => {
      fs.writeFileSync(marker, String(process.pid));
      process.kill(process.pid, 'SIGTERM');
      process.kill(process.pid, 'SIGTERM');
      hang();
      return new Promise(() => {});
    }
  : blockedRunner;
const opts = {
  rootDir: world, host: 'opencode', env, maxIterations: 3,
  spawnRunner: mode === 'normal'
    ? () => ({ status: 0, stdout: 'sections pass\n', stderr: '' })
    : spawnRunner,
  probeRunner: () => { throw new Error('script stage never probes the host'); },
  engineProbe: () => ({ engine: 'bwrap', version: '0.11.0' }),
  legRunner: () => ({ ok: true, verdict: { ok: true, failures: [] } }),
};
loop.createLoop(opts).loop.run().then((r) => {
  console.log(`RESULT ${r.status}|${r.reason || ''}`);
  console.log(`SIGLISTEN ${process.listeners('SIGTERM').length} ${process.listeners('SIGHUP').length} ${process.listeners('SIGINT').length}`);
}).catch((e) => { console.error(e && e.message ? e.message : e); process.exit(1); });
EOF
}

# Poll for the marker file; echoes 0 when it appeared, 1 on timeout.
t134_wait_marker() {
  for _ in $(seq 1 150); do
    [ -f blocked.marker ] && { echo 0; return 0; }
    sleep 0.1
  done
  echo 1
}

# ---------------------------------------------------------------- C1 --
t134_case c1
t134_write_state
t134_write_harness
T134_MODE=blocked node harness.cjs > c1.out 2>&1 &
C1_PID=$!
T134_PIDS="$T134_PIDS $C1_PID"
if [ "$(t134_wait_marker)" = "0" ]; then
  t134_ok "C1: harness blocked mid-step (marker up)"
  kill -TERM "$C1_PID"
  wait "$C1_PID"; C1_RC=$?
  T134_PIDS="$(printf '%s\n' "$T134_PIDS" | tr ' ' '\n' | grep -vx "$C1_PID" | tr '\n' ' ')"
  t134_eq "C1: SIGTERM exits 128+15" 143 "$C1_RC"
  t134_contains "C1: handler telemetry line on stderr" "auto kill: killed=" "$(cat c1.out)"
  cat > check-c1.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const problems = [];
const list = store.readRunRecords(world);
if (!list.ok || list.runRecords.length !== 1) problems.push('records=' + (list.runRecords || []).length + ' (want 1)');
else {
  const rec = list.runRecords[0];
  if (store.runRecordRejection(rec) !== null) problems.push('record invalid: ' + store.runRecordRejection(rec));
  const es = rec.endState || {};
  if (es.ok !== false || es.status !== 'killed' || es.reason !== 'SIGTERM') problems.push('endState=' + JSON.stringify(es));
  const stages = rec.stages || [];
  if (stages.length !== 1 || stages[0].stage !== 'VERIFY') problems.push('stages=' + JSON.stringify(stages.map((s) => s.stage)));
  else {
    const s = stages[0];
    if (s.advanced !== false || s.counted !== false) problems.push('inflight flags=' + JSON.stringify({ advanced: s.advanced, counted: s.counted }));
    if (typeof s.spawnId !== 'string' || !s.spawnId) problems.push('inflight spawnId empty');
    if (!Array.isArray(s.steps) || s.steps.length !== 1 || s.steps[0].id !== 'gate' || s.steps[0].status !== 'passed') {
      problems.push('steps=' + JSON.stringify(s.steps) + ' (want the completed gate leg only)');
    }
  }
}
const acq = store.acquireRunLock({ rootDir: world });
if (!acq.ok) problems.push('lock not re-acquirable: ' + (acq.reason || '?'));
else store.releaseRunLock(world);
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
  t134_eq "C1: killed record (SIGTERM, in-flight VERIFY entry, completed steps only) + lock re-acquirable" "OK" "$(node check-c1.cjs 2>&1 | tail -n 1)"
  rm .gos/state.json
  T134_MODE=normal node harness.cjs > c1b.out 2>&1
  C1B_RC=$?
  t134_eq "C1: restart harness acquires cleanly (exit 0)" 0 "$C1B_RC"
  t134_contains "C1: restart run refuses no-task through the full loop path" "RESULT refused|no-task" "$(cat c1b.out)"
else
  kill -9 "$C1_PID" 2>/dev/null
  t134_bad "C1: harness never blocked mid-step (marker missing)"
fi

# ---------------------------------------------------------------- C2 --
t134_case c2
t134_write_harness
T134_MODE=normal node harness.cjs > c2.out 2>&1
C2_RC=$?
t134_eq "C2: normal run exits 0" 0 "$C2_RC"
t134_contains "C2: run completes through a normal exit route" "RESULT refused|no-task" "$(cat c2.out)"
t134_contains "C2: post-run listener counts are zero (mechanical disarm proof)" "SIGLISTEN 0 0 0" "$(cat c2.out)"

# ---------------------------------------------------------------- C3 --
t134_case c3
t134_write_state
t134_write_harness
T134_MODE=blocked node harness.cjs > c3.out 2>&1 &
C3_PID=$!
T134_PIDS="$T134_PIDS $C3_PID"
if [ "$(t134_wait_marker)" = "0" ]; then
  SLEEP_PID=""
  SLEEP_LOCKED=""
  node -e "
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawn } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const sr = require(path.join(GR, 'bin/lib/core/spawnreg.cjs'));
const child = spawn('sleep', ['60'], { stdio: 'ignore' });
child.unref();
fs.writeFileSync(path.join(store.mutateLockPath(process.cwd())), JSON.stringify({
  hostname: os.hostname(), pid: child.pid, boot_id: null,
  starttime: sr.procStartTime(child.pid), created_at: new Date().toISOString(),
}));
console.log(child.pid);
" > c3.helper 2>/dev/null
  SLEEP_PID="$(cat c3.helper 2>/dev/null)"
  [ -n "$SLEEP_PID" ] && T134_PIDS="$T134_PIDS $SLEEP_PID" && SLEEP_LOCKED=1
  kill -TERM "$C3_PID"
  wait "$C3_PID"; C3_RC=$?
  T134_PIDS="$(printf '%s\n' "$T134_PIDS" | tr ' ' '\n' | grep -vx "$C3_PID" | tr '\n' ' ')"
  t134_eq "C3: exit stays 128+15 under store-busy" 143 "$C3_RC"
  cat > check-c3.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const problems = [];
const dropPath = path.join(store.storeRoot(world), 'runrecords-drop.ndjson');
let lines = [];
try { lines = fs.readFileSync(dropPath, 'utf8').split('\n').filter((l) => l !== ''); } catch { lines = []; }
if (lines.length !== 1) problems.push('sidecar lines=' + lines.length + ' (want 1)');
else {
  let rec = null;
  try { rec = JSON.parse(lines[0]); } catch { rec = null; }
  if (!rec || store.runRecordRejection(rec) !== null) problems.push('sidecar line does not validate structurally');
  else if (rec.endState.status !== 'killed' || rec.endState.reason !== 'SIGTERM') problems.push('sidecar endState=' + JSON.stringify(rec.endState));
}
const list = store.readRunRecords(world);
if (!list.ok || list.runRecords.length !== 0) problems.push('runRecords=' + (list.runRecords || []).length + ' (want 0 — the killed record lives on the sidecar only)');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
  t134_eq "C3: store-busy routes the killed record to the drop sidecar (one valid line, runRecords untouched)" "OK" "$(node check-c3.cjs 2>&1 | tail -n 1)"
  if [ -n "$SLEEP_LOCKED" ]; then
    t134_ok "C3: foreign live mutate lock planted before the kill"
    kill -9 "$SLEEP_PID" 2>/dev/null
    T134_PIDS="$(printf '%s\n' "$T134_PIDS" | tr ' ' '\n' | grep -vx "$SLEEP_PID" | tr '\n' ' ')"
  else
    t134_bad "C3: foreign live mutate lock not planted"
  fi
else
  kill -9 "$C3_PID" 2>/dev/null
  t134_bad "C3: harness never blocked mid-step (marker missing)"
fi

# ---------------------------------------------------------------- C4 --
t134_case c4
t134_write_state
t134_write_harness
T134_MODE=latch node harness.cjs > c4.out 2>&1 &
C4_PID=$!
T134_PIDS="$T134_PIDS $C4_PID"
if [ "$(t134_wait_marker)" = "0" ]; then
  wait "$C4_PID"; C4_RC=$?
  T134_PIDS="$(printf '%s\n' "$T134_PIDS" | tr ' ' '\n' | grep -vx "$C4_PID" | tr '\n' ' ')"
  t134_eq "C4: rapid double SIGTERM still exits 143" 143 "$C4_RC"
  cat > check-c4.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const problems = [];
const list = store.readRunRecords(world);
if (!list.ok || list.runRecords.length !== 1) problems.push('records=' + (list.runRecords || []).length + ' (want exactly 1)');
else {
  const es = list.runRecords[0].endState || {};
  if (es.status !== 'killed' || es.reason !== 'SIGTERM') problems.push('endState=' + JSON.stringify(es));
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
  t134_eq "C4: latch holds — exactly one killed record for the signal burst" "OK" "$(node check-c4.cjs 2>&1 | tail -n 1)"
else
  kill -9 "$C4_PID" 2>/dev/null
  t134_bad "C4: harness never reached the self-signal step (marker missing)"
fi

# ---------------------------------------------------------------- C5 --
t134_case c5
t134_write_state
t134_write_harness
T134_MODE=blocked node harness.cjs > c5.out 2>&1 &
C5_PID=$!
T134_PIDS="$T134_PIDS $C5_PID"
if [ "$(t134_wait_marker)" = "0" ]; then
  kill -HUP "$C5_PID"
  wait "$C5_PID"; C5_RC=$?
  T134_PIDS="$(printf '%s\n' "$T134_PIDS" | tr ' ' '\n' | grep -vx "$C5_PID" | tr '\n' ' ')"
  t134_eq "C5: SIGHUP exits 128+1" 129 "$C5_RC"
  cat > check-c5.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const problems = [];
const latest = store.latestRunRecord(world);
if (!latest.ok || !latest.record) problems.push('no record');
else {
  const es = latest.record.endState || {};
  if (es.status !== 'killed' || es.reason !== 'SIGHUP') problems.push('endState=' + JSON.stringify(es));
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
  t134_eq "C5: killed record carries the signal name (SIGHUP)" "OK" "$(node check-c5.cjs 2>&1 | tail -n 1)"
else
  kill -9 "$C5_PID" 2>/dev/null
  t134_bad "C5: harness never blocked mid-step (marker missing)"
fi

echo "--- T134 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
