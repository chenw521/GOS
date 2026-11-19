#!/usr/bin/env bash
# gos-map:none
# Run-record persistence section — every loop exit route leaves one
# per-run record in the machine-local trust store (run identity, per-stage
# outcomes incl. the script-VERIFY step statuses, end state, timestamps).
# The record family is the evidence substrate the re-enable gate reads.
# Case map:
#   C1  harness-driven run: a script-VERIFY stage driven green through the
#       runner-driven commit channel ends at SHIP and leaves exactly one
#       record the store validator accepts; the record carries the stage
#       outcome (advanced, signal, spawnId), the three VERIFY steps with
#       P/S kinds all passed, and the ship end state
#   C2  every-exit coverage: a stage-already-advanced pause leaves a record
#       whose stage entry keeps the null signal (unscored session), and a
#       no-task refusal leaves a pre-run record with empty stages and a
#       null task id
#   C3  store surface: an old-shape store without the key loads unchanged
#       and the first write initializes the array; a malformed record reads
#       as corrupt (fail-closed); writeRunRecord refuses malformed input;
#       the append family stays bounded; latest/read helpers expose the
#       evidence read-only
# Loop spawns run through injected spawnRunner/legRunner harnesses only.
# HOME and XDG_DATA_HOME are pinned per case under TESTBASE. Standalone-safe.

T128_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T128_STANDALONE=1
  T128_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T128_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T128_SELFROOT"
  export TESTBASE="$(mktemp -d "$T128_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T128_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t128"
mkdir -p "$T128_DIR" && cd "$T128_DIR" || exit 1

PASS=0
FAIL=0
t128_ok() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
t128_bad() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
t128_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t128_ok "$label"; else
    t128_bad "$label (expected: '$expected', got: '$actual')"
  fi
}

t128_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T128_DIR"
  if [ "$T128_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t128_teardown EXIT

echo "--- T128: run-record persistence ---"

t128_case() {
  T128_CASE="$T128_DIR/$1"
  mkdir -p "$T128_CASE/home" "$T128_CASE/xdg" "$T128_CASE/repo/.gos/logs"
  export HOME="$T128_CASE/home"
  export XDG_DATA_HOME="$T128_CASE/xdg"
  cd "$T128_CASE/repo" || exit 1
  git init -q -b work . && git commit -q --allow-empty -m root
}

# ---------------------------------------------------------------- C1 --
t128_case c1
# Green ship through the script VERIFY worker: pinned legs green, the
# sections spawn rc0, the stage advances through the commit channel, the
# loop ends at SHIP. The record must carry the stage outcome with the
# three builtin VERIFY steps all passed, and reload through load() must
# accept the persisted shape.
mkdir -p .gos/task/p0 .gos/logs
printf '# Spec\n\np0 auto spec\n' > .gos/task/p0/spec.md
printf '{"schema_version":6,"level":3,"current_stage":"VERIFY","completed_stages":["INTENT","THINK","PLAN","BUILD","REVIEW"],"intent":{"summary":"t128 fixture","confirmed":true},"task_head":"abc123def0123456789abcdef0123456789abcde","spec_path":".gos/task/p0/spec.md","plan_path":null,"requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{},"semantic":{"allowlist":["run-c1.cjs"]}}' > .gos/state.json
node -e "const fs=require('fs');const p='.gos/state.json';const st=JSON.parse(fs.readFileSync(p,'utf8'));const {execSync}=require('child_process');st.task_head=execSync('git rev-parse HEAD').toString().trim();fs.writeFileSync(p,JSON.stringify(st,null,2));"
export GOS_AUTO_TIMEOUT_WALL_SEC=2 GOS_AUTO_TIMEOUT_IDLE_SEC=1
cat > run-c1.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const core = require(path.join(GR, 'bin/lib/core/index.cjs'));
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const world = process.cwd();
const problems = [];
const isoOk = (v) => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(v);
(async () => {
  const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
  const probeRunner = () => { throw new Error('host probe must never run for a script stage'); };
  store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
  const specs = [];
  const spawnRunner = (spec) => { specs.push(spec); return { status: 0, stdout: 'sections pass\n', stderr: '' }; };
  const r = await loop.createLoop({
    rootDir: world, host: 'opencode', env, maxIterations: 3, spawnRunner, probeRunner,
    engineProbe: () => ({ engine: 'bwrap', version: '0.11.0' }),
    legRunner: () => ({ ok: true, verdict: { ok: true, failures: [] } }),
  }).loop.run();
  if (r.status !== 'ship' || r.ok !== true) {
    problems.push('run did not reach SHIP: ' + r.status + '/' + r.reason + (r.detail ? ': ' + String(r.detail).slice(0, 200) : ''));
  }
  const list = store.readRunRecords(world);
  if (!list.ok) problems.push('readRunRecords failed: ' + list.reason);
  else {
    if (!Array.isArray(list.runRecords) || list.runRecords.length !== 1) {
      problems.push('expected exactly one record, got ' + (list.runRecords || []).length);
    } else {
      const rec = list.runRecords[0];
      const stateNow = JSON.parse(require('fs').readFileSync(path.join(world, '.gos', 'state.json'), 'utf8'));
      const wantTask = core.currentTaskId(stateNow) || 'task';
      if (typeof rec.runId !== 'string' || !/^[0-9a-f-]{36}$/.test(rec.runId)) problems.push('runId not a uuid: ' + JSON.stringify(rec.runId));
      if (typeof rec.runTag !== 'string' || rec.runTag.length !== 8) problems.push('runTag not 8 chars: ' + JSON.stringify(rec.runTag));
      if (rec.taskId !== wantTask) problems.push('taskId=' + JSON.stringify(rec.taskId) + ' want ' + JSON.stringify(wantTask));
      if (!isoOk(rec.startedAtIso)) problems.push('startedAtIso not ISO');
      if (!isoOk(rec.endedAtIso)) problems.push('endedAtIso not ISO');
      if (Date.parse(rec.endedAtIso) < Date.parse(rec.startedAtIso)) problems.push('endedAtIso before startedAtIso');
      const es = rec.endState || {};
      if (es.ok !== true || es.status !== 'ship' || es.reason !== 'stage-ship') {
        problems.push('endState=' + JSON.stringify(es));
      }
      const stages = rec.stages || [];
      if (stages.length !== 1) problems.push('stages length ' + stages.length + ' (want 1)');
      else {
        const s = stages[0];
        const iter = (r.iterations || [])[0];
        if (s.stage !== 'VERIFY') problems.push('stage=' + s.stage);
        if (s.signal !== 'advanced') problems.push('signal=' + JSON.stringify(s.signal));
        if (s.advanced !== true) problems.push('advanced not true');
        if (s.counted !== false) problems.push('counted not false');
        if (!iter || s.spawnId !== iter.spawnId) problems.push('spawnId mismatch vs iteration');
        const steps = s.steps || [];
        const want = ['gate:P', 'sections:S', 'truth:P'];
        const got = steps.map((x) => x.id + ':' + x.kind).join(',');
        if (got !== want.join(',')) problems.push('steps=' + got + ' want ' + want.join(','));
        if (!steps.every((x) => x.status === 'passed')) problems.push('not every step passed');
      }
      if ((r.iterations || [])[0] && !String((r.iterations || [])[0].spawnId).startsWith(rec.runId)) {
        problems.push('iteration spawnId does not carry the record run id');
      }
    }
  }
  // the persisted record must survive a full load (validator accepts it)
  const reload = store.load(world);
  if (!reload.ok) problems.push('reload refused the persisted record: ' + reload.reason + '/' + reload.detail);
  else if (!Array.isArray(reload.store.runRecords) || reload.store.runRecords.length !== 1) {
    problems.push('reload lost the record');
  }
  const latest = store.latestRunRecord(world);
  if (!latest.ok || !latest.record || latest.record.endState.status !== 'ship') {
    problems.push('latestRunRecord did not surface the ship record');
  }
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C1_OUT="$(node run-c1.cjs 2>&1 | tail -n 1)"
t128_eq "C1: green ship run leaves one validated record (stage outcome, VERIFY steps, end state)" "OK" "$C1_OUT"

# ---------------------------------------------------------------- C2 --
t128_case c2
# Pause ends are recorded too: the pointer/completed desync shape pauses as
# stage-already-advanced after one clean-but-unproductive session — the
# stage entry keeps the in-memory score (rc0-no-advance, never counted
# into the breaker). A no-task refusal leaves the pre-run record shape
# (empty stages, null task id) through the same store.
cat > .gos/state.json <<'EOF'
{"schema_version":6,"level":1,"current_stage":"THINK","completed_stages":["THINK"],"intent":{"summary":"t128 fixture","confirmed":true},"task_head":"abc123def0123456789abcdef0123456789abcde","spec_path":null,"plan_path":null,"requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{"THINK":"2026-11-09T09:04:21.679Z"}}
EOF
export GOS_AUTO_TIMEOUT_WALL_SEC=2 GOS_AUTO_TIMEOUT_IDLE_SEC=1
cat > run-c2a.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const world = process.cwd();
const problems = [];
(async () => {
  const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
  const spawnRunner = (spec) => {
    if (spec.roWorkspace) return { status: 0, stdout: 'review clean\nREDTEAM-FINDINGS: 0\n', stderr: '' };
    return { status: 0, stdout: '{"type":"message","text":"settled"}\n{"type":"result"}\n', stderr: '' };
  };
  store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 5, B: 30 } });
  const r = await loop.createLoop({ rootDir: world, host: 'gos-fixture-host', env, maxIterations: 9, spawnRunner }).loop.run();
  if (r.status !== 'paused' || r.reason !== 'stage-already-advanced') {
    problems.push('run did not pause as expected: ' + r.status + '/' + r.reason);
  }
  const recs = store.readRunRecords(world);
  if (!recs.ok || recs.runRecords.length !== 1) problems.push('pause run left ' + (recs.runRecords || []).length + ' records');
  else {
    const rec = recs.runRecords[0];
    if (rec.endState.ok !== false || rec.endState.status !== 'paused' || rec.endState.reason !== 'stage-already-advanced') {
      problems.push('pause endState=' + JSON.stringify(rec.endState));
    }
    if (rec.stages.length !== 1) problems.push('pause stages length ' + rec.stages.length);
    else {
      const s = rec.stages[0];
      // the clean session scored rc0-no-advance in memory but never entered
      // the breaker (counted false) — the record keeps exactly that.
      if (s.stage !== 'THINK' || s.signal !== 'rc0-no-advance' || s.advanced !== false || s.counted !== false) {
        problems.push('paused stage entry=' + JSON.stringify({ stage: s.stage, signal: s.signal, advanced: s.advanced, counted: s.counted }));
      }
    }
  }
  // second run on the same store: no active task — the pre-run refusal
  // leaves its own record with the empty evidence shape
  fs.rmSync(path.join(world, '.gos', 'state.json'));
  const r2 = await loop.createLoop({ rootDir: world, host: 'gos-fixture-host', env, maxIterations: 3, spawnRunner }).loop.run();
  if (r2.status !== 'refused' || r2.reason !== 'no-task') problems.push('second run did not refuse no-task: ' + r2.status + '/' + r2.reason);
  const recs2 = store.readRunRecords(world);
  if (!recs2.ok || recs2.runRecords.length !== 2) problems.push('store carries ' + recs2.runRecords.length + ' records (want 2)');
  else {
    const pre = recs2.runRecords[1];
    if (pre.taskId !== null) problems.push('pre-run record taskId=' + JSON.stringify(pre.taskId) + ' (want null)');
    if (pre.stages.length !== 0) problems.push('pre-run record stages not empty');
    if (pre.endState.ok !== false || pre.endState.status !== 'refused' || pre.endState.reason !== 'no-task') {
      problems.push('pre-run endState=' + JSON.stringify(pre.endState));
    }
    if (store.latestRunRecord(world).record.runId !== pre.runId) problems.push('latest is not the newest record');
  }
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C2_OUT="$(node run-c2a.cjs 2>&1 | tail -n 1)"
t128_eq "C2: pause and pre-run refusal ends each leave their record on every exit route" "OK" "$C2_OUT"

# ---------------------------------------------------------------- C3 --
t128_case c3
cat > run-c3.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const problems = [];
const storeFile = path.join(store.storeRoot(world), 'store.json');
const now = new Date().toISOString();
const goodRecord = (n) => ({
  runId: '00000000-0000-0000-0000-' + String(n).padStart(12, '0'),
  runTag: 'tag' + String(n).padStart(5, '0'),
  taskId: 'fixture01',
  startedAtIso: now, endedAtIso: now,
  endState: { ok: false, status: 'paused', reason: 'fixture' },
  stages: [{ stage: 'VERIFY', signal: 'task-failed', advanced: false, counted: true, spawnId: 's-' + n, steps: [{ id: 'gate', kind: 'P', status: 'failed' }] }],
});
store.create({ mode: 'on', rootDir: world });
// old-shape store: the key stripped entirely loads unchanged (back-compat)
const old = JSON.parse(fs.readFileSync(storeFile, 'utf8'));
delete old.runRecords;
fs.writeFileSync(storeFile, JSON.stringify(old, null, 2));
const oldLoad = store.load(world);
if (!oldLoad.ok) problems.push('old-shape store refused: ' + oldLoad.reason + '/' + oldLoad.detail);
else if (oldLoad.store.runRecords !== undefined) problems.push('pure load invented the key');
const firstWrite = store.writeRunRecord(goodRecord(1), world);
if (!firstWrite.ok) problems.push('first write over old store failed: ' + firstWrite.reason);
const after = JSON.parse(fs.readFileSync(storeFile, 'utf8'));
if (!Array.isArray(after.runRecords) || after.runRecords.length !== 1) problems.push('first write did not initialize the array');
// malformed persisted record reads as corrupt (fail-closed), never repaired
const corrupt = JSON.parse(fs.readFileSync(storeFile, 'utf8'));
corrupt.runRecords.push({ runId: 'x', stages: 'nope' });
fs.writeFileSync(storeFile, JSON.stringify(corrupt));
const bad = store.load(world);
if (bad.status !== 'paused' || bad.reason !== 'corrupt' || !String(bad.detail || '').includes('runRecords')) {
  problems.push('malformed record not refused corrupt: ' + bad.status + '/' + bad.reason + '/' + bad.detail);
}
// writeRunRecord validates its input before the store ever sees it
fs.writeFileSync(storeFile, JSON.stringify(JSON.parse(fs.readFileSync(storeFile, 'utf8')), null, 2));
const stillCorrupt = store.load(world);
if (stillCorrupt.ok) problems.push('setup error: expected the corrupt fixture to stay corrupt');
// reset to a clean store for the refusal and cap cases
fs.rmSync(path.dirname(storeFile), { recursive: true, force: true });
store.create({ mode: 'on', rootDir: world });
if (store.writeRunRecord(null, world).reason !== 'invalid-run-record') problems.push('non-object accepted');
const noEnd = goodRecord(2); delete noEnd.endState;
if (store.writeRunRecord(noEnd, world).reason !== 'invalid-run-record') problems.push('missing endState accepted');
const badStep = goodRecord(3); badStep.stages[0].steps[0].kind = 'Q';
if (store.writeRunRecord(badStep, world).reason !== 'invalid-run-record') problems.push('unknown step kind accepted');
const badIso = goodRecord(4); badIso.startedAtIso = 'yesterday';
if (store.writeRunRecord(badIso, world).reason !== 'invalid-run-record') problems.push('non-ISO timestamp accepted');
if (store.readRunRecords(world).runRecords.length !== 0) problems.push('a refused write still persisted');
// bounded append family: past the cap the oldest records drop
const cap = store.RUN_RECORDS_CAP;
for (let i = 0; i < cap + 5; i += 1) {
  const r = store.writeRunRecord(goodRecord(100 + i), world);
  if (!r.ok) { problems.push('cap-loop write failed at ' + i + ': ' + r.reason); break; }
}
const capped = store.readRunRecords(world);
if (capped.runRecords.length !== cap) problems.push('cap not enforced: ' + capped.runRecords.length);
else if (capped.runRecords[0].runId !== goodRecord(105).runId) problems.push('oldest kept is not the expected survivor');
if (store.latestRunRecord(world).record.runId !== goodRecord(100 + cap + 4).runId) problems.push('latest not the newest append');
// the capped store still validates on load
if (!store.load(world).ok) problems.push('capped store stopped validating');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C3_OUT="$(node run-c3.cjs 2>&1 | tail -n 1)"
t128_eq "C3: old stores load and adopt lazily; malformed records fail closed; writes validate; appends stay capped" "OK" "$C3_OUT"

echo "--- T128 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
