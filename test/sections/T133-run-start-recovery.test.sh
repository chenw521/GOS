#!/usr/bin/env bash
# gos-map:none
# Run-start recovery section — the restart-safe loop's opening sweep, pinned
# between the detach sentinel and the seed materialization: the crash-side
# record queue drains into runRecords (bounded, corrupt lines quarantine),
# stray pinned worktrees recycle, spawnreg-driven sections-tree entries sweep
# only through their recorded test_base, and orphaned auto-seed dirs clear.
# A live-looking takeover holder pauses the run before any destructive step.
# Case map:
#   C1  drain: valid sidecar lines land in runRecords flagged droppedRecord,
#       crafted-invalid and malformed lines quarantine, the live queue
#       clears to absent-or-empty, and the persisted store still validates
#   C1b drain bound: 60 queued lines process at most 50 per run — the
#       overflow stays queued for the next run (truncate re-queues it)
#   C2  testBase gate: a stray entry with a recorded test_base sweeps its
#       sections-tree; a stray entry with NO test_base is removed without
#       rm-ing anything outside any recorded testBase
#   C3  live-pid pause: break of a live-pid stale-heartbeat lock pauses with
#       a named reason and guidance — the planted stray pin, stray entry,
#       and sidecar lines all survive the paused run untouched
#   C4  stray recycle: a pin whose worktree dir vanished recycles (record +
#       registration gone); a dead-pid entry with a test_base sweeps its
#       sections-tree dir and is removed
#   C5  seed sweep: fake auto-seed-* dirs under .gos/cache are removed,
#       unrelated cache entries stay
#   C7  rewrite-failure injection: the overflow rebuild goes through the
#       store's tmp+rename rewrite — a failed rewrite sets the drain error
#       and leaves the sidecar holding every original line for the next run
#   C8  recovery-error surfacing: a failed drain reaches stderr as
#       `⚠ auto recovery: <error>` before the recoveryDrained summary line
# HOME and XDG_DATA_HOME are pinned per case under TESTBASE. Standalone-safe.

T133_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T133_STANDALONE=1
  T133_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T133_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T133_SELFROOT"
  export TESTBASE="$(mktemp -d "$T133_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T133_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t133"
mkdir -p "$T133_DIR" && cd "$T133_DIR" || exit 1

PASS=0
FAIL=0
t133_ok() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
t133_bad() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
t133_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t133_ok "$label"; else
    t133_bad "$label (expected: '$expected', got: '$actual')"
  fi
}

t133_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T133_DIR"
  if [ "$T133_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t133_teardown EXIT

echo "--- T133: run-start recovery ---"

t133_case() {
  T133_CASE="$T133_DIR/$1"
  mkdir -p "$T133_CASE/home" "$T133_CASE/xdg" "$T133_CASE/repo/.gos/logs"
  export HOME="$T133_CASE/home"
  export XDG_DATA_HOME="$T133_CASE/xdg"
  cd "$T133_CASE/repo" || exit 1
  git init -q -b work . && git commit -q --allow-empty -m root
}

# Shared no-task harness: the run refuses no-task after recovery has run, so
# every recovery effect is observable through the store and filesystem.
t133_write_harness() {
  cat > run-t133.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const world = process.cwd();
store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const noSpawn = () => { throw new Error('a no-task run must never spawn'); };
const opts = {
  rootDir: world, host: 'gos-fixture-host', env, maxIterations: 1,
  spawnRunner: noSpawn, probeRunner: noSpawn,
};
if (process.env.T133_BREAK_LOCK === '1') opts.breakLock = true;
loop.createLoop(opts).loop.run().then((r) => {
  console.log('RESULT ' + JSON.stringify({ ok: r.ok, status: r.status, reason: r.reason || null, paused: r.paused === true }));
}).catch((e) => { console.error(e); process.exit(1); });
EOF
}

# Rewrite-failure harness: the same no-task driver, but the store's overflow
# rewrite primitive is patched to fail after require (the driver requires
# the repo modules directly, so the patch lands on the shared module
# instance the loop calls through). The patch records every invocation and
# the original is restored once the run settles.
t133_write_rewrite_fail_harness() {
  cat > run-t133-rf.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const origRewrite = store.rewriteRunRecordDrops;
const calls = [];
store.rewriteRunRecordDrops = function patchedRewrite(rootDir, lines) {
  calls.push({ lines: Array.isArray(lines) ? lines.slice() : null });
  return { ok: false, status: 'error', reason: 'rewrite-failed' };
};
const world = process.cwd();
store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const noSpawn = () => { throw new Error('a no-task run must never spawn'); };
const opts = {
  rootDir: world, host: 'gos-fixture-host', env, maxIterations: 1,
  spawnRunner: noSpawn, probeRunner: noSpawn,
};
loop.createLoop(opts).loop.run().then((r) => {
  store.rewriteRunRecordDrops = origRewrite;
  fs.writeFileSync('rewrite-call.json', JSON.stringify(calls));
  console.log('RESULT ' + JSON.stringify({ ok: r.ok, status: r.status, reason: r.reason || null, paused: r.paused === true }));
}).catch((e) => { console.error(e); process.exit(1); });
EOF
}

# ---------------------------------------------------------------- C1 --
t133_case c1
# Drain cycle: two valid queued records adopt into runRecords flagged
# droppedRecord, the crafted-invalid and malformed lines quarantine verbatim,
# the live queue clears to absent-or-empty, and the persisted store still
# loads clean.
t133_write_harness
cat > seed-c1.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const now = new Date().toISOString();
const rec = (n) => ({
  runId: '00000000-0000-0000-0000-' + String(n).padStart(12, '0'),
  runTag: 'tag' + n, taskId: null, startedAtIso: now, endedAtIso: now,
  endState: { ok: false, status: 'paused', reason: 'fixture' }, stages: [],
});
const root = store.storeRoot(world);
fs.mkdirSync(root, { recursive: true });
const bad1 = JSON.stringify({ nonsense: true });
const bad2 = '{not-json';
fs.writeFileSync(path.join(root, 'runrecords-drop.ndjson'),
  [JSON.stringify(rec(1)), JSON.stringify(rec(2)), bad1, bad2].join('\n') + '\n');
EOF
node seed-c1.cjs
T133_OUT="$(node run-t133.cjs 2>&1 | tail -n 1)"
case "$T133_OUT" in *'"reason":"no-task"'*) ;; *) echo "harness did not refuse no-task: $T133_OUT" >&2 ;; esac
cat > check-c1.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const problems = [];
const root = store.storeRoot(world);
const dropPath = path.join(root, 'runrecords-drop.ndjson');
const corruptPath = path.join(root, 'runrecords-drop.corrupt.ndjson');
if (fs.existsSync(dropPath) && fs.readFileSync(dropPath, 'utf8') !== '') {
  problems.push('live queue survived the drain holding content');
}
if (!fs.existsSync(corruptPath)) problems.push('quarantine file missing');
else {
  const lines = fs.readFileSync(corruptPath, 'utf8').split('\n').filter((l) => l !== '');
  if (lines.length !== 2) problems.push('quarantine holds ' + lines.length + ' lines (want 2)');
  else {
    if (JSON.parse(lines[0]).nonsense !== true) problems.push('quarantine line 1 not the crafted-invalid record');
    if (lines[1] !== '{not-json') problems.push('quarantine line 2 not the malformed JSON verbatim');
  }
}
const recs = store.readRunRecords(world);
if (!recs.ok) problems.push('readRunRecords failed: ' + recs.reason);
else {
  const dropped = recs.runRecords.filter((r) => r.droppedRecord === true);
  if (dropped.length !== 2) problems.push('droppedRecord-flagged records: ' + dropped.length + ' (want 2)');
  const tail = recs.runRecords[recs.runRecords.length - 1];
  if (!tail || tail.endState.reason !== 'no-task') problems.push('the no-task refusal record is missing from the store tail');
}
const reload = store.load(world);
if (!reload.ok) problems.push('store with drained records does not load: ' + reload.reason + '/' + reload.detail);
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C1_OUT="$(node check-c1.cjs 2>&1 | tail -n 1)"
t133_eq "C1: drain adopts valid drops flagged droppedRecord, quarantines bad lines verbatim, clears the live queue" "OK" "$C1_OUT"

# ---------------------------------------------------------------- C1b --
t133_case c1b
# Drain bound: 60 queued valid records — at most 50 process per run, the
# overflow stays queued (truncate re-queues it) for the next run.
t133_write_harness
cat > seed-c1b.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const now = new Date().toISOString();
const root = store.storeRoot(world);
fs.mkdirSync(root, { recursive: true });
const lines = [];
for (let i = 1; i <= 60; i += 1) {
  const n = String(i).padStart(12, '0');
  lines.push(JSON.stringify({
    runId: '00000000-0000-0000-0000-' + n, runTag: 'tag' + i, taskId: null,
    startedAtIso: now, endedAtIso: now,
    endState: { ok: false, status: 'paused', reason: 'fixture' }, stages: [],
  }));
}
fs.writeFileSync(path.join(root, 'runrecords-drop.ndjson'), lines.join('\n') + '\n');
EOF
node seed-c1b.cjs
T133_OUT="$(node run-t133.cjs 2>&1 | tail -n 1)"
case "$T133_OUT" in *'"reason":"no-task"'*) ;; *) echo "harness did not refuse no-task: $T133_OUT" >&2 ;; esac
cat > check-c1b.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const problems = [];
const root = store.storeRoot(world);
const dropPath = path.join(root, 'runrecords-drop.ndjson');
if (!fs.existsSync(dropPath)) problems.push('overflow drain removed the live queue file (bound must leave the remainder queued)');
else {
  const left = store.readRunRecordDrops(world).lines.length;
  if (left !== 10) problems.push('queue holds ' + left + ' lines (want the 10 unprocessed)');
}
const recs = store.readRunRecords(world);
if (!recs.ok) problems.push('readRunRecords failed: ' + recs.reason);
else {
  const dropped = recs.runRecords.filter((r) => r.droppedRecord === true).length;
  // cap parity: 50 drained then the no-task record trims the oldest drained
  if (recs.runRecords.length !== 50) problems.push('runRecords length ' + recs.runRecords.length + ' (want the 50 cap)');
  if (dropped !== 49) problems.push('droppedRecord count ' + dropped + ' (want 49 after the cap trim)');
  const tail = recs.runRecords[recs.runRecords.length - 1];
  if (!tail || tail.endState.reason !== 'no-task') problems.push('store tail is not the no-task record');
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C1B_OUT="$(node check-c1b.cjs 2>&1 | tail -n 1)"
t133_eq "C1b: drain processes at most 50 lines per run — the overflow stays queued for the next run" "OK" "$C1B_OUT"

# ---------------------------------------------------------------- C2 --
t133_case c2
# TestBase gate: the stray entry WITH a recorded test_base sweeps its
# sections-tree; the stray entry with NO test_base is removed without
# touching anything outside any recorded testBase.
mkdir -p elsewhere testbedA/sections-tree-wt
echo keep > elsewhere/target
echo junk > testbedA/sections-tree-wt/f
t133_write_harness
cat > seed-c2.cjs <<'EOF'
const { spawnSync } = require('child_process');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const sr = require(path.join(GR, 'bin/lib/core/spawnreg.cjs'));
const world = process.cwd();
const dead = spawnSync('true').pid;
const a = store.registerSpawn({ spawnId: 't133c2a', kind: 'work', stage: 'BUILD', wallMs: 600000, pid: dead }, world);
if (!a.ok) { console.error('register a failed: ' + a.reason); process.exit(1); }
const tb = path.resolve(process.env.T133_TESTBED_A);
const upd = sr.updateEntryFields(world, 't133c2a', { test_base: tb });
if (!upd.ok) { console.error('update test_base failed: ' + upd.reason); process.exit(1); }
const b = store.registerSpawn({ spawnId: 't133c2b', kind: 'work', stage: 'BUILD', wallMs: 600000, pid: dead }, world);
if (!b.ok) { console.error('register b failed: ' + b.reason); process.exit(1); }
EOF
T133_TESTBED_A="$T133_CASE/repo/testbedA" node seed-c2.cjs
T133_OUT="$(node run-t133.cjs 2>&1 | tail -n 1)"
case "$T133_OUT" in *'"reason":"no-task"'*) ;; *) echo "harness did not refuse no-task: $T133_OUT" >&2 ;; esac
cat > check-c2.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const problems = [];
if (!fs.existsSync(path.resolve(process.env.T133_ELSEWHERE, 'target'))) {
  problems.push('the forged no-test_base target outside any recorded testBase was removed');
}
if (fs.existsSync(path.resolve(process.env.T133_TESTBED_A, 'sections-tree-wt'))) {
  problems.push('the recorded-testBase sections-tree dir survived the sweep');
}
const ls = store.listSpawnEntries(world);
if (!ls.ok) problems.push('listSpawnEntries failed: ' + ls.reason);
else if (ls.entries.length !== 0) problems.push('stray entries survived: ' + ls.entries.map((e) => e.spawnId).join(','));
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C2_OUT="$(T133_ELSEWHERE="$T133_CASE/repo/elsewhere" T133_TESTBED_A="$T133_CASE/repo/testbedA" node check-c2.cjs 2>&1 | tail -n 1)"
t133_eq "C2: stray sweep is testBase-gated — a recorded testBase sweeps, a no-test_base entry is removed without rm-ing anything" "OK" "$C2_OUT"

# ---------------------------------------------------------------- C3 --
t133_case c3
# Live-pid pause: breaking a live-pid stale-heartbeat lock pauses the run
# with a named reason and guidance BEFORE any sweep — the planted stray pin,
# stray entry, and queued sidecar line all survive untouched.
t133_write_harness
cat > seed-c3.cjs <<'EOF'
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const workers = require(path.join(GR, 'bin/lib/ops/auto/workers.cjs'));
const world = process.cwd();
const problems = [];
const now = new Date().toISOString();
store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
// stray sidecar line
const root = store.storeRoot(world);
fs.mkdirSync(root, { recursive: true });
fs.writeFileSync(path.join(root, 'runrecords-drop.ndjson'), JSON.stringify({
  runId: '00000000-0000-0000-0000-000000000133', runTag: 'tag00133', taskId: null,
  startedAtIso: now, endedAtIso: now,
  endState: { ok: false, status: 'paused', reason: 'fixture' }, stages: [],
}) + '\n');
// stray pin (live record, then the recovery must NOT recycle it)
const head = require('child_process').execSync('git rev-parse HEAD', { cwd: world }).toString().trim();
const pin = workers.materializePin(world, { loopStartCommit: head });
if (!pin.ok) { console.error('materializePin failed: ' + pin.reason + '/' + pin.detail); process.exit(1); }
fs.writeFileSync(process.env.T133_PIN_TAG_FILE, pin.runTag);
// stray entry
const { spawnSync } = require('child_process');
const dead = spawnSync('true').pid;
const reg = store.registerSpawn({ spawnId: 't133c3', kind: 'work', stage: 'BUILD', wallMs: 600000, pid: dead }, world);
if (!reg.ok) { console.error('register failed: ' + reg.reason); process.exit(1); }
// live-pid stale-heartbeat lock holder
const holder = spawn('sleep', ['300'], { stdio: 'ignore' });
holder.unref();
fs.writeFileSync(process.env.T133_HOLDER_PID_FILE, String(holder.pid));
const bootId = fs.readFileSync('/proc/sys/kernel/random/boot_id', 'utf8').trim();
const ago = (ms) => new Date(Date.now() - ms).toISOString();
fs.writeFileSync(path.join(root, 'run.lock'), JSON.stringify({
  hostname: os.hostname(), pid: holder.pid, boot_id: bootId,
  clone_path: world, started_at: ago(4 * 3600000), heartbeat_at: ago(4 * 3600000),
}));
console.log('OK');
EOF
T133_PIN_TAG="$T133_CASE/T133-pin-tag"
HOLD_PID_FILE="$T133_CASE/T133-holder.pid"
T133_PIN_TAG_FILE="$T133_PIN_TAG" T133_HOLDER_PID_FILE="$HOLD_PID_FILE" node seed-c3.cjs >/dev/null 2>&1 || { t133_bad "C3 seed failed"; }
HOLD_PID="$(cat "$HOLD_PID_FILE" 2>/dev/null || true)"
T133_OUT="$(T133_BREAK_LOCK=1 node run-t133.cjs 2>&1 | tail -n 1)"
[ -n "$HOLD_PID" ] && kill "$HOLD_PID" 2>/dev/null
case "$T133_OUT" in
  *'"status":"paused"'*'"reason":"recovery-live-holder"'*'"paused":true'*) t133_ok "C3: a live-pid stale-heartbeat break pauses with the recovery-live-holder reason" ;;
  *) t133_bad "C3: live-pid pause did not happen ($T133_OUT)" ;;
esac
cat > check-c3.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const problems = [];
const root = store.storeRoot(world);
const lines = store.readRunRecordDrops(world).lines.length;
if (lines !== 1) problems.push('paused run drained the sidecar queue (' + lines + ' lines left, want 1)');
const pins = store.readPins(world);
const tag = fs.readFileSync(process.env.T133_PIN_TAG_FILE, 'utf8').trim();
if (!pins.ok || !pins.pins[tag]) problems.push('paused run recycled the stray pin record');
if (!fs.existsSync(path.join(root, 'pin-worktrees', tag))) problems.push('paused run removed the stray pin worktree');
const ls = store.listSpawnEntries(world);
if (!ls.ok || ls.entries.length !== 1 || ls.entries[0].spawnId !== 't133c3') {
  problems.push('paused run swept the stray entry');
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C3_OUT="$(T133_PIN_TAG_FILE="$T133_PIN_TAG" node check-c3.cjs 2>&1 | tail -n 1)"
t133_eq "C3: the paused run swept nothing — sidecar line, stray pin, and stray entry all survive" "OK" "$C3_OUT"

# ---------------------------------------------------------------- C4 --
t133_case c4
# Stray recycle: a pin whose worktree dir vanished recycles (record gone);
# a dead-pid entry with a test_base sweeps its sections-tree and is removed.
mkdir -p testbedB/sections-tree-junk
echo junk > testbedB/sections-tree-junk/f
t133_write_harness
cat > seed-c4.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const workers = require(path.join(GR, 'bin/lib/ops/auto/workers.cjs'));
const sr = require(path.join(GR, 'bin/lib/core/spawnreg.cjs'));
const world = process.cwd();
store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
const head = require('child_process').execSync('git rev-parse HEAD', { cwd: world }).toString().trim();
const pin = workers.materializePin(world, { loopStartCommit: head });
if (!pin.ok) { console.error('materializePin failed: ' + pin.reason); process.exit(1); }
fs.writeFileSync(process.env.T133_PIN_TAG_FILE, pin.runTag);
fs.rmSync(pin.path, { recursive: true, force: true });
const dead = spawnSync('true').pid;
const reg = store.registerSpawn({ spawnId: 't133c4', kind: 'work', stage: 'BUILD', wallMs: 600000, pid: dead }, world);
if (!reg.ok) { console.error('register failed: ' + reg.reason); process.exit(1); }
const upd = sr.updateEntryFields(world, 't133c4', { test_base: path.resolve(process.env.T133_TESTBED_B) });
if (!upd.ok) { console.error('update test_base failed: ' + upd.reason); process.exit(1); }
console.log('OK');
EOF
T133_TESTBED_B="$T133_CASE/repo/testbedB" T133_PIN_TAG_FILE="$T133_CASE/T133-pin-tag" node seed-c4.cjs >/dev/null 2>&1 || { t133_bad "C4 seed failed"; }
T133_OUT="$(node run-t133.cjs 2>&1 | tail -n 1)"
case "$T133_OUT" in *'"reason":"no-task"'*) ;; *) echo "harness did not refuse no-task: $T133_OUT" >&2 ;; esac
cat > check-c4.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const problems = [];
const pins = store.readPins(world);
const tag = fs.readFileSync(process.env.T133_PIN_TAG_FILE, 'utf8').trim();
if (!pins.ok) problems.push('readPins failed: ' + pins.reason);
else if (pins.pins[tag]) problems.push('the orphaned pin record survived recovery');
if (fs.existsSync(path.resolve(process.env.T133_TESTBED_B, 'sections-tree-junk'))) {
  problems.push('the dead-pid entry sections-tree dir survived the sweep');
}
const ls = store.listSpawnEntries(world);
if (!ls.ok) problems.push('listSpawnEntries failed: ' + ls.reason);
else if (ls.entries.length !== 0) problems.push('the dead stray entry survived: ' + ls.entries.map((e) => e.spawnId).join(','));
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C4_OUT="$(T133_PIN_TAG_FILE="$T133_CASE/T133-pin-tag" T133_TESTBED_B="$T133_CASE/repo/testbedB" node check-c4.cjs 2>&1 | tail -n 1)"
t133_eq "C4: a vanished pin worktree recycles its record; a dead-pid test_base entry sweeps its sections-tree" "OK" "$C4_OUT"

# ---------------------------------------------------------------- C5 --
t133_case c5
# Seed sweep: fake auto-seed-* dirs under .gos/cache are removed; unrelated
# cache entries stay.
mkdir -p .gos/cache/auto-seed-fake1/nested .gos/cache/auto-seed-fake2 .gos/cache/keepme
echo x > .gos/cache/auto-seed-fake1/nested/f
t133_write_harness
T133_OUT="$(node run-t133.cjs 2>&1 | tail -n 1)"
case "$T133_OUT" in *'"reason":"no-task"'*) ;; *) echo "harness did not refuse no-task: $T133_OUT" >&2 ;; esac
if [ ! -d .gos/cache/auto-seed-fake1 ] && [ ! -d .gos/cache/auto-seed-fake2 ] && [ -d .gos/cache/keepme ]; then
  t133_ok "C5: stray auto-seed-* dirs under .gos/cache are swept, unrelated entries stay"
else
  t133_bad "C5: seed sweep left auto-seed dirs or removed unrelated cache entries"
fi

# ---------------------------------------------------------------- C7 --
t133_case c7
# Rewrite-failure injection: 52 valid queued lines drain (50 adopt, 2 stay
# as overflow), the overflow rebuild runs through the store's tmp+rename
# rewrite — patched to fail — and the failure leaves the sidecar holding
# every original line for the next run's retry, with the adopted records
# already in the store (append lands before the rewrite).
t133_write_rewrite_fail_harness
cat > seed-c7.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const now = new Date().toISOString();
const root = store.storeRoot(world);
fs.mkdirSync(root, { recursive: true });
const lines = [];
for (let i = 1; i <= 52; i += 1) {
  lines.push(JSON.stringify({
    runId: '00000000-0000-0000-0000-' + String(i).padStart(12, '0'),
    runTag: 'tag' + i, taskId: null, startedAtIso: now, endedAtIso: now,
    endState: { ok: false, status: 'paused', reason: 'fixture' }, stages: [],
  }));
}
fs.writeFileSync(path.join(root, 'runrecords-drop.ndjson'), lines.join('\n') + '\n');
EOF
node seed-c7.cjs
T133_OUT="$(node run-t133-rf.cjs 2>&1 | tail -n 1)"
case "$T133_OUT" in *'"reason":"no-task"'*) ;; *) echo "harness did not refuse no-task: $T133_OUT" >&2 ;; esac
cat > check-c7.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const problems = [];
const root = store.storeRoot(world);
const dropPath = path.join(root, 'runrecords-drop.ndjson');
const lines = fs.readFileSync(dropPath, 'utf8').split('\n').filter((l) => l !== '');
if (lines.length !== 52) problems.push('sidecar holds ' + lines.length + ' lines (want all 52 originals)');
if (lines.length === 52) {
  if (!lines[0].includes('"runTag":"tag1"')) problems.push('sidecar line 1 is not the original first record');
  if (!lines[51].includes('"runTag":"tag52"')) problems.push('sidecar line 52 is not the original last record');
}
const calls = JSON.parse(fs.readFileSync('rewrite-call.json', 'utf8'));
if (calls.length !== 1) problems.push('rewrite primitive calls: ' + calls.length + ' (want 1)');
else if (!Array.isArray(calls[0].lines) || calls[0].lines.length !== 2) {
  problems.push('rewrite received ' + (calls[0].lines || []).length + ' lines (want the 2-line overflow)');
}
const recs = store.readRunRecords(world);
if (!recs.ok) problems.push('readRunRecords failed: ' + recs.reason);
else {
  const dropped = recs.runRecords.filter((r) => r.droppedRecord === true).length;
  // cap parity: 50 drained then the no-task record trims the oldest drained
  if (recs.runRecords.length !== 50) problems.push('runRecords length ' + recs.runRecords.length + ' (want the 50 cap)');
  if (dropped !== 49) problems.push('droppedRecord count ' + dropped + ' (want 49 after the cap trim)');
  const tail = recs.runRecords[recs.runRecords.length - 1];
  if (!tail || tail.endState.reason !== 'no-task') problems.push('store tail is not the no-task record');
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C7_OUT="$(node check-c7.cjs 2>&1 | tail -n 1)"
t133_eq "C7: a failed overflow rewrite sets the drain error and leaves the sidecar holding all 52 original lines" "OK" "$C7_OUT"

# ---------------------------------------------------------------- C8 --
t133_case c8
# Recovery-error surfacing: with the rewrite failing, the recovery error
# reaches stderr as `⚠ auto recovery: <error>` BEFORE the recoveryDrained
# summary line — a failed step never sits silently in a result object
# nobody reads. GOS_LANG pinned so the summary-line order grep is stable.
t133_write_rewrite_fail_harness
cat > seed-c8.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const now = new Date().toISOString();
const root = store.storeRoot(world);
fs.mkdirSync(root, { recursive: true });
fs.writeFileSync(path.join(root, 'runrecords-drop.ndjson'), JSON.stringify({
  runId: '00000000-0000-0000-0000-000000000001', runTag: 'tag1', taskId: null,
  startedAtIso: now, endedAtIso: now,
  endState: { ok: false, status: 'paused', reason: 'fixture' }, stages: [],
}) + '\n');
EOF
node seed-c8.cjs
T133_ERRLOG="$T133_CASE/repo/recovery-stderr.log"
T133_OUT="$(GOS_LANG=en node run-t133-rf.cjs 2>"$T133_ERRLOG" | tail -n 1)"
case "$T133_OUT" in *'"reason":"no-task"'*) ;; *) echo "harness did not refuse no-task: $T133_OUT" >&2 ;; esac
C8_WARN="$(grep -n '⚠ auto recovery:' "$T133_ERRLOG" | head -n 1 | cut -d: -f1)"
C8_REASON="$(grep -c 'rewrite-failed' "$T133_ERRLOG")"
C8_SUM="$(grep -n 'dropped run record' "$T133_ERRLOG" | head -n 1 | cut -d: -f1)"
if [ -n "$C8_WARN" ] && [ "$C8_REASON" -ge 1 ] && [ -n "$C8_SUM" ] && [ "$C8_WARN" -lt "$C8_SUM" ]; then
  t133_ok "C8: the recovery error surfaces on stderr before the recoveryDrained summary"
else
  t133_bad "C8: recovery error not surfaced before the summary (warn line: ${C8_WARN:-none}, reason hits: $C8_REASON, summary line: ${C8_SUM:-none})"
fi

# ------------------------------------------------------- locale parity --
LOCALE_OUT="$(GOS_ROOT="$GOS_ROOT" node -e '
const path = require("path");
const en = require(path.join(process.env.GOS_ROOT, "bin/lib/core/locales/en.cjs"));
const zh = require(path.join(process.env.GOS_ROOT, "bin/lib/core/locales/zh.cjs"));
const bad = [];
for (const k of ["auto.loop.recoveryLiveHolder", "auto.loop.recoveryDrained"]) {
  if (en[k] == null) bad.push("en missing " + k);
  if (zh[k] == null) bad.push("zh missing " + k);
}
console.log(bad.length ? "BAD " + bad.join("; ") : "OK");
')"
t133_eq "locale parity: recoveryLiveHolder + recoveryDrained exist in en and zh" "OK" "$LOCALE_OUT"

echo "--- T133 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
