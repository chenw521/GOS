#!/usr/bin/env bash
# gos-map:none
# gos-tier:main
# Think-trip regression section — the pointer/completed desync that tripped
# the THINK breaker at 2026-11-09T09:17Z. A headless `commit think` executed
# while the stage pointer still sat at INTENT marked THINK completed and
# moved the pointer only to THINK, so current_stage named a stage already in
# completed_stages. The loop re-drove THINK; every clean session that refused
# to fabricate a second advance scored rc0-no-advance until the N layer
# tripped. Case map:
#   C1  a clean rc0 session against a pointer naming a completed stage
#       pauses the loop as stage-already-advanced after one spawn instead of
#       scoring rc0-no-advance into the breaker until the N layer trips
#   C2  the adjacent healthy shape (THINK pointer, INTENT completed) still
#       advances normally — the guard never fires on the normal state
#   C3  a terminal DONE pointer with DONE in completed_stages still ends
#       done (pointer-in-completed is legal at the terminal stage)
# Loop spawns run through injected spawnRunner harnesses only. HOME and
# XDG_DATA_HOME are pinned per case under TESTBASE. Standalone-safe.

T127_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T127_STANDALONE=1
  T127_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T127_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T127_SELFROOT"
  export TESTBASE="$(mktemp -d "$T127_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T127_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t127"
mkdir -p "$T127_DIR" && cd "$T127_DIR" || exit 1

PASS=0
FAIL=0
t127_ok() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
t127_bad() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
t127_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t127_ok "$label"; else
    t127_bad "$label (expected: '$expected', got: '$actual')"
  fi
}

T127_PIDS=""
t127_teardown() {
  for p in $T127_PIDS; do kill "$p" 2>/dev/null; done
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T127_DIR"
  if [ "$T127_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t127_teardown EXIT

echo "--- T127: think-trip pointer/completed desync ---"

t127_case() {
  T127_CASE="$T127_DIR/$1"
  mkdir -p "$T127_CASE/home" "$T127_CASE/xdg" "$T127_CASE/repo/.gos/logs"
  export HOME="$T127_CASE/home"
  export XDG_DATA_HOME="$T127_CASE/xdg"
  cd "$T127_CASE/repo" || exit 1
  git init -q -b work . && git commit -q --allow-empty -m root
}

# ---------------------------------------------------------------- C1 --
t127_case c1
# The exact desync shape from the 2026-11-09T09:17 trip: pointer THINK,
# THINK already completed (INTENT never recorded — headless commit think
# from the INTENT pointer). The spawn harness mirrors the real sessions:
# clean exit, terminal event, no new commit (the duplicate-advance guard
# makes a second stage-labeled commit impossible).
cat > .gos/state.json <<'EOF'
{"schema_version":6,"level":1,"current_stage":"THINK","completed_stages":["THINK"],"intent":{"summary":"t127 fixture","confirmed":true},"task_head":"abc123def0123456789abcdef0123456789abcde","spec_path":null,"plan_path":null,"requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{"THINK":"2026-11-09T09:04:21.679Z"}}
EOF
export GOS_AUTO_TIMEOUT_WALL_SEC=2 GOS_AUTO_TIMEOUT_IDLE_SEC=1
cat > run-c1.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
let spawnCalls = 0;
const spawnRunner = (spec) => {
  spawnCalls += 1;
  if (spec.roWorkspace) return { status: 0, stdout: 'review clean\nREDTEAM-FINDINGS: 0\n', stderr: '' };
  return { status: 0, stdout: '{"type":"message","text":"stage work already settled"}\n{"type":"result"}\n', stderr: '' };
};
store.create({ mode: 'on', rootDir, limits: { N: 3, K: 5, B: 30 } });
loop.createLoop({ rootDir, host: 'gos-fixture-host', env, maxIterations: 9, spawnRunner }).loop.run().then((r) => {
  const st = store.load(rootDir);
  console.log(`RES ${r.status}|${r.reason}`);
  console.log(`SPAWN ${spawnCalls}|${r.iterations.length}`);
  console.log(`STORE ${st.ok ? st.store.counters.spawnCount : -1}|${st.ok ? st.store.counters.tripCount : -1}`);
}).catch((e) => { console.error(e); process.exit(1); });
EOF
C1_OUT="$(node run-c1.cjs 2>&1)"
t127_eq "C1: desync pointer pauses with stage-already-advanced" "paused|stage-already-advanced" "$(printf '%s\n' "$C1_OUT" | grep '^RES ' | cut -d' ' -f2-)"
t127_eq "C1: pause lands after the first clean session (no burn to the trip)" "1|1" "$(printf '%s\n' "$C1_OUT" | grep '^SPAWN ' | cut -d' ' -f2-)"
t127_eq "C1: no breaker trip recorded (counters carry the one spawn only)" "1|0" "$(printf '%s\n' "$C1_OUT" | grep '^STORE ' | cut -d' ' -f2-)"

# ---------------------------------------------------------------- C2 --
t127_case c2
# Adjacent healthy shape: pointer THINK, completed [INTENT]. An advancing
# harness lands the stage-labeled commit and moves the pointer; the guard
# must not fire on the normal state.
cat > .gos/state.json <<'EOF'
{"schema_version":6,"level":1,"current_stage":"THINK","completed_stages":["INTENT"],"intent":{"summary":"t127 fixture","confirmed":true},"task_head":"abc123def0123456789abcdef0123456789abcde","spec_path":null,"plan_path":null,"requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{}}
EOF
cat > run-c2.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const stateFile = path.join(rootDir, '.gos', 'state.json');
const spawnRunner = (spec) => {
  if (spec.roWorkspace) return { status: 0, stdout: 'review clean\nREDTEAM-FINDINGS: 0\n', stderr: '' };
  spawnSync('git', ['commit', '--allow-empty', '-m', `chore(task): advance ${spec.stage.toLowerCase()}`], { cwd: rootDir });
  const st = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
  st.current_stage = 'PLAN';
  st.completed_stages = ['INTENT', 'THINK'];
  fs.writeFileSync(stateFile, JSON.stringify(st, null, 2));
  return { status: 0, stdout: '{"type":"message","text":"stage work done"}\n{"type":"result"}\n', stderr: '' };
};
store.create({ mode: 'on', rootDir, limits: { N: 3, K: 5, B: 30 } });
loop.createLoop({ rootDir, host: 'gos-fixture-host', env, maxIterations: 1, spawnRunner }).loop.run().then((r) => {
  console.log(`RES ${r.status}|${r.iterations.map((i) => i.signal).join(',')}`);
}).catch((e) => { console.error(e); process.exit(1); });
EOF
C2_OUT="$(node run-c2.cjs 2>&1)"
t127_eq "C2: healthy THINK pointer still advances (guard stays silent)" "iteration-cap|advanced" "$(printf '%s\n' "$C2_OUT" | grep '^RES ' | cut -d' ' -f2-)"

# ---------------------------------------------------------------- C3 --
t127_case c3
# Terminal shape: pointer DONE with DONE in completed_stages is the legal
# end state — the loop must end done, not pause on the guard.
cat > .gos/state.json <<'EOF'
{"schema_version":6,"level":1,"current_stage":"DONE","completed_stages":["INTENT","THINK","PLAN","BUILD","REVIEW","VERIFY","DONE"],"intent":{"summary":"t127 fixture","confirmed":true},"task_head":"abc123def0123456789abcdef0123456789abcde","spec_path":null,"plan_path":null,"requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{}}
EOF
cat > run-c3.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
let spawnCalls = 0;
const spawnRunner = () => { spawnCalls += 1; return { status: 0, stdout: '{"type":"result"}\n', stderr: '' }; };
store.create({ mode: 'on', rootDir, limits: { N: 3, K: 5, B: 30 } });
loop.createLoop({ rootDir, host: 'gos-fixture-host', env, maxIterations: 3, spawnRunner }).loop.run().then((r) => {
  console.log(`RES ${r.status}|${r.reason}|${spawnCalls}`);
}).catch((e) => { console.error(e); process.exit(1); });
EOF
C3_OUT="$(node run-c3.cjs 2>&1)"
t127_eq "C3: terminal DONE pointer in completed_stages ends done, zero spawns" "done|stage-done|0" "$(printf '%s\n' "$C3_OUT" | grep '^RES ' | cut -d' ' -f2-)"

echo "--- T127 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
