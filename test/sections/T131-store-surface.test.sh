#!/usr/bin/env bash
# gos-map:none
# Store/spawnreg surface section — additive persistence primitives the
# restart-safe loop builds on: takeover audits on the run lock (tookOver
# carries the broken holder plus a closed reason enum), spawn registry
# entries that round-trip holder liveness (pid, starttime, and the sections
# suite's test_base pin), the run-record drop sidecar queue with its
# quarantine file, and writeRunRecord's bounded-wait passthrough.
# Case map:
#   C1  run-lock takeover audit: each break reason (dead-pid, boot-changed,
#       heartbeat-stale, cross-host, unreadable) surfaces tookOver with the
#       holder identity it could prove; a clean acquire carries no tookOver
#       at all; cross-host and heartbeat-stale keeps their breaker events
#   C2  spawn entry liveness: registerSpawn stamps pid + starttime itself,
#       validates an optional test_base; updateEntryFields stamps the
#       sections testbed pin after the fact (fail-closed on missing entry
#       and unknown fields); listSpawnEntries reads entries regardless of
#       window expiry and names unreadable ones
#   C3  drop sidecar cycle: append queues raw records (null refused), read
#       returns raw lines, the exported runRecordRejection judges them,
#       moveCorruptDropLines quarantines bad lines, truncate removes the
#       live queue without touching the quarantine file
#   C4  writeRunRecord opts passthrough: a foreign live mutate lock with
#       waitMs 0 reports store-busy as data (twice), and the same opts on a
#       free lock land the record; the two-arg shape still works
# HOME and XDG_DATA_HOME are pinned per case under TESTBASE. Standalone-safe.

T131_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T131_STANDALONE=1
  T131_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T131_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T131_SELFROOT"
  export TESTBASE="$(mktemp -d "$T131_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T131_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t131"
mkdir -p "$T131_DIR" && cd "$T131_DIR" || exit 1

PASS=0
FAIL=0
t131_ok() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
t131_bad() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
t131_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t131_ok "$label"; else
    t131_bad "$label (expected: '$expected', got: '$actual')"
  fi
}

t131_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T131_DIR"
  if [ "$T131_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t131_teardown EXIT

echo "--- T131: store/spawnreg surface ---"

t131_case() {
  T131_CASE="$T131_DIR/$1"
  mkdir -p "$T131_CASE/home" "$T131_CASE/xdg" "$T131_CASE/repo/.gos/logs"
  export HOME="$T131_CASE/home"
  export XDG_DATA_HOME="$T131_CASE/xdg"
  cd "$T131_CASE/repo" || exit 1
  git init -q -b work . && git commit -q --allow-empty -m root
}

# ---------------------------------------------------------------- C1 --
t131_case c1
# Break-path audit: every takeover branch names its reason from the closed
# enum and carries whatever holder identity the broken record proved. The
# refusal paths (cross-host without break, live holder) refuse unchanged,
# and the two audited breaks still land their takeover breaker records.
cat > run-c1.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const problems = [];
const bootId = (() => {
  try { return fs.readFileSync('/proc/sys/kernel/random/boot_id', 'utf8').trim(); } catch { return null; }
})();
const lockFile = path.join(store.storeRoot(world), 'run.lock');
store.create({ mode: 'on', rootDir: world });
const acquire = (o) => store.acquireRunLock({ rootDir: world, ...(o || {}) });
const craft = (rec) => fs.writeFileSync(lockFile, JSON.stringify(rec));
const isoAgo = (ms) => new Date(Date.now() - ms).toISOString();
const holderShape = (over) => ({
  hostname: os.hostname(), pid: process.pid, boot_id: bootId,
  clone_path: '/tmp/t131-holder', started_at: isoAgo(3600000), heartbeat_at: isoAgo(1000), ...over,
});
const check = (label, res, wantReason, wantPid, wantHostname) => {
  if (!res.ok) { problems.push(label + ': acquire refused (' + res.reason + ')'); return; }
  const t = res.tookOver;
  if (!t || t.reason !== wantReason) problems.push(label + ': tookOver=' + JSON.stringify(t));
  else {
    if (wantPid !== undefined && t.pid !== wantPid) problems.push(label + ': tookOver.pid=' + t.pid + ' (want ' + wantPid + ')');
    if (wantHostname !== undefined && t.hostname !== wantHostname) problems.push(label + ': tookOver.hostname=' + t.hostname);
  }
  const rel = store.releaseRunLock(world);
  if (!rel.ok) problems.push(label + ': release failed (' + rel.reason + ')');
};
// dead pid: same host, matching boot, pid that exited — auto-recovery
const dead = spawnSync('true', { encoding: 'utf8' }).pid;
craft(holderShape({ pid: dead }));
check('dead-pid', acquire(), 'dead-pid', dead, os.hostname());
// boot changed: same host, live pid, boot_id from a previous boot
craft(holderShape({ boot_id: 'f'.repeat(32) }));
check('boot-changed', acquire(), 'boot-changed', process.pid, os.hostname());
// heartbeat stale: live pid, fresh boot, heartbeat hours old — break needed
craft(holderShape({ heartbeat_at: isoAgo(4 * 3600000) }));
const staleNoBreak = acquire();
if (staleNoBreak.ok || staleNoBreak.reason !== 'heartbeat-stale') {
  problems.push('stale lock without breakLock not refused heartbeat-stale: ' + JSON.stringify(staleNoBreak.reason));
} else {
  store.releaseRunLock(world);
}
craft(holderShape({ heartbeat_at: isoAgo(4 * 3600000) }));
check('heartbeat-stale', acquire({ breakLock: true }), 'heartbeat-stale', process.pid, os.hostname());
// cross-host: foreign hostname — refused without break, takeover with it
craft(holderShape({ hostname: 't131-other-host' }));
const xhostNoBreak = acquire();
if (xhostNoBreak.ok || xhostNoBreak.reason !== 'cross-host') {
  problems.push('cross-host without breakLock not refused cross-host');
} else {
  store.releaseRunLock(world);
}
craft(holderShape({ hostname: 't131-other-host' }));
check('cross-host', acquire({ breakLock: true }), 'cross-host', process.pid, 't131-other-host');
// unreadable: no proven owner at all
fs.writeFileSync(lockFile, '{not-json');
check('unreadable', acquire(), 'unreadable', null, null);
// the two audited breaks kept their takeover breaker events
const brk = store.load(world);
const details = brk.ok && brk.store.breaker && Array.isArray(brk.store.breaker.records)
  ? brk.store.breaker.records.filter((r) => r.cls === 'takeover').map((r) => r.detail || '').join('\n')
  : '';
if (!/heartbeat-stale break/.test(details)) problems.push('heartbeat-stale breaker event missing');
if (!/cross-host break/.test(details)) problems.push('cross-host breaker event missing');
// clean acquire: no existing lock carries NO tookOver field (absent, not null)
fs.rmSync(lockFile, { force: true });
const clean = acquire();
if (!clean.ok) problems.push('clean acquire refused: ' + clean.reason);
else if ('tookOver' in clean) problems.push('clean acquire carries tookOver=' + JSON.stringify(clean.tookOver));
else store.releaseRunLock(world);
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C1_OUT="$(node run-c1.cjs 2>&1 | tail -n 1)"
t131_eq "C1: every takeover break carries tookOver (closed reason enum + proven holder identity); clean acquire carries none" "OK" "$C1_OUT"

# ---------------------------------------------------------------- C2 --
t131_case c2
# Entry liveness round-trip: registration stamps pid + starttime from the
# running process (call sites stay pid-free), an optional test_base rides
# the entry when provided, the post-registration pin update lands in the
# entry doc, and the listing reads files directly (window expiry hides
# nothing, unreadable entries are named, manifests are not entries).
cat > run-c2.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const sr = require(path.join(GR, 'bin/lib/core/spawnreg.cjs'));
const world = process.cwd();
const problems = [];
store.create({ mode: 'on', rootDir: world });
const empty = store.listSpawnEntries(world);
if (!empty.ok || !Array.isArray(empty.entries) || empty.entries.length !== 0) {
  problems.push('empty registry not listed as empty: ' + JSON.stringify(empty.ok ? empty.entries : empty.reason));
}
const reg = store.registerSpawn({ spawnId: 't131c2', kind: 'work', stage: 'BUILD', wallMs: 600000 }, world);
if (!reg.ok) problems.push('registerSpawn failed: ' + reg.reason + '/' + reg.detail);
else {
  const doc = JSON.parse(fs.readFileSync(sr.entryPath(world, 't131c2'), 'utf8'));
  if (doc.pid !== process.pid) problems.push('doc.pid=' + doc.pid + ' (want the registering process pid ' + process.pid + ')');
  if (!('starttime' in doc)) problems.push('doc lacks a starttime field');
  else {
    const st = sr.procStartTime(process.pid);
    if (st != null && doc.starttime !== st) problems.push('doc.starttime=' + doc.starttime + ' (want ' + st + ')');
  }
  if ('test_base' in doc) problems.push('entry carries a test_base the caller never provided');
}
const regTb = store.registerSpawn({ spawnId: 't131c2b', kind: 'work', stage: 'BUILD', wallMs: 600000, test_base: '/tmp/t131-testbed' }, world);
if (!regTb.ok) problems.push('registerSpawn with absolute test_base refused: ' + regTb.reason);
else {
  const doc = JSON.parse(fs.readFileSync(sr.entryPath(world, 't131c2b'), 'utf8'));
  if (doc.test_base !== '/tmp/t131-testbed') problems.push('test_base not persisted: ' + JSON.stringify(doc.test_base));
}
const regRel = store.registerSpawn({ spawnId: 't131c2rel', kind: 'work', stage: 'BUILD', wallMs: 600000, test_base: 'relative/path' }, world);
if (regRel.ok || regRel.reason !== 'invalid-test-base') problems.push('relative test_base not refused: ' + JSON.stringify(regRel.reason));
const regPid = store.registerSpawn({ spawnId: 't131c2pid', kind: 'work', stage: 'BUILD', wallMs: 600000, pid: 'not-a-pid' }, world);
if (regPid.ok || regPid.reason !== 'invalid-pid') problems.push('non-integer pid not refused: ' + JSON.stringify(regPid.reason));
const upd = sr.updateEntryFields(world, 't131c2', { test_base: '/var/tmp/t131-pin' });
if (!upd.ok) problems.push('updateEntryFields failed: ' + upd.reason + '/' + upd.detail);
else {
  const doc = JSON.parse(fs.readFileSync(sr.entryPath(world, 't131c2'), 'utf8'));
  if (doc.test_base !== '/var/tmp/t131-pin') problems.push('updated doc test_base=' + JSON.stringify(doc.test_base));
  if (doc.pid !== process.pid) problems.push('update dropped the pid field');
}
const updRel = sr.updateEntryFields(world, 't131c2', { test_base: 'rel/x' });
if (updRel.ok || updRel.reason !== 'invalid-test-base') problems.push('update with relative test_base accepted');
const updGhost = sr.updateEntryFields(world, 't131c2-ghost', { test_base: '/abs/x' });
if (updGhost.ok || updGhost.reason !== 'no-entry') problems.push('ghost update not refused no-entry: ' + JSON.stringify(updGhost.reason));
const updUnknown = sr.updateEntryFields(world, 't131c2', { uses: 5 });
if (updUnknown.ok || updUnknown.reason !== 'invalid-fields') problems.push('unknown field accepted into the entry doc');
const dir = sr.spawnregDir(world);
fs.writeFileSync(path.join(dir, 't131c2-bad.json'), 'not-json');
fs.writeFileSync(path.join(dir, 't131c2.manifest.json'), '{}');
sr.saveEntryDoc(world, { spawn_id: 't131c2-exp', kind: 'work', stage: 'BUILD', grants: [], use_cap: 1, uses: 0, window_expiry: Date.now() - 1000, pid: process.pid });
const ls = store.listSpawnEntries(world);
if (!ls.ok) problems.push('listSpawnEntries failed: ' + ls.reason);
else {
  const ids = ls.entries.map((e) => e.spawnId);
  if (!ids.includes('t131c2')) problems.push('listing lacks the registered entry');
  if (!ids.includes('t131c2-exp')) problems.push('window-expired entry hidden from the listing');
  if (ids.some((i) => i.endsWith('.manifest'))) problems.push('manifest file listed as an entry');
  if (!Array.isArray(ls.skipped) || !ls.skipped.includes('t131c2-bad')) problems.push('unreadable entry not named: ' + JSON.stringify(ls.skipped));
  const c2 = ls.entries.find((e) => e.spawnId === 't131c2');
  if (!c2 || c2.entry.test_base !== '/var/tmp/t131-pin') problems.push('listed entry lacks the updated test_base');
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C2_OUT="$(node run-c2.cjs 2>&1 | tail -n 1)"
t131_eq "C2: entries round-trip pid/starttime/test_base (stamped registration, post-hoc pin update, expiry-blind listing)" "OK" "$C2_OUT"

# ---------------------------------------------------------------- C3 --
t131_case c3
# Sidecar cycle: the drop file is a raw queue — appends never validate
# beyond refusing null, reads return raw lines, the exported record
# validator judges them, bad lines move to the quarantine file, and
# truncate removes the live queue without touching the quarantine.
cat > run-c3.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const problems = [];
const dropPath = path.join(store.storeRoot(world), 'runrecords-drop.ndjson');
const corruptPath = path.join(store.storeRoot(world), 'runrecords-drop.corrupt.ndjson');
const now = new Date().toISOString();
const goodRec = {
  runId: '00000000-0000-0000-0000-000000000131', runTag: 'tag00131', taskId: 't131',
  startedAtIso: now, endedAtIso: now,
  endState: { ok: false, status: 'paused', reason: 'fixture' }, stages: [],
};
const absent = store.readRunRecordDrops(world);
if (!absent.ok || !Array.isArray(absent.lines) || absent.lines.length !== 0) {
  problems.push('absent drop file not an empty queue');
}
if (!store.appendRunRecordDrop(world, goodRec).ok) problems.push('append of a good record refused');
if (!store.appendRunRecordDrop(world, { nonsense: true }).ok) {
  problems.push('append of a crafted-invalid record refused (validation belongs to the drain reader)');
}
const nullAppend = store.appendRunRecordDrop(world, null);
if (nullAppend.ok || nullAppend.reason !== 'invalid-drop-record') problems.push('null record not refused');
const read1 = store.readRunRecordDrops(world);
if (!read1.ok || read1.lines.length !== 2) problems.push('queue holds ' + (read1.lines || []).length + ' lines (want 2)');
else {
  const good = JSON.parse(read1.lines[0]);
  if (store.runRecordRejection(good) !== null) problems.push('runRecordRejection refuses a valid record');
  const rejection = store.runRecordRejection(JSON.parse(read1.lines[1]));
  if (typeof rejection !== 'string' || !rejection) problems.push('runRecordRejection accepts a crafted bad record');
}
const move = store.moveCorruptDropLines(world, [read1.lines[1]]);
if (!move.ok || move.moved !== 1) problems.push('quarantine move failed: ' + JSON.stringify(move));
else {
  const quarantined = fs.readFileSync(corruptPath, 'utf8').trim().split('\n');
  if (quarantined.length !== 1 || quarantined[0] !== read1.lines[1]) problems.push('quarantine file holds the wrong lines');
  if (store.readRunRecordDrops(world).lines.length !== 2) problems.push('quarantine move mutated the live queue');
}
if (store.moveCorruptDropLines(world, 'not-an-array').ok) problems.push('non-array quarantine move accepted');
const trunc = store.truncateRunRecordDrops(world);
if (!trunc.ok) problems.push('truncate failed: ' + trunc.reason);
else {
  if (fs.existsSync(dropPath)) problems.push('truncate left the live queue file behind');
  if (store.readRunRecordDrops(world).lines.length !== 0) problems.push('queue not empty after truncate');
  if (!fs.existsSync(corruptPath)) problems.push('truncate destroyed the quarantine file');
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C3_OUT="$(node run-c3.cjs 2>&1 | tail -n 1)"
t131_eq "C3: append/read/validate/quarantine/truncate sidecar cycle over the drop queue" "OK" "$C3_OUT"

# ---------------------------------------------------------------- C4 --
t131_case c4
# Bounded-wait passthrough: a live foreign mutate lock with waitMs 0 turns
# the record write into the store-busy verdict as data (deterministically,
# no sleeps), the lock released plus the same opts lands the record, and
# the historical two-arg call shape keeps working.
cat > run-c4.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawn } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const sr = require(path.join(GR, 'bin/lib/core/spawnreg.cjs'));
const world = process.cwd();
const problems = [];
const now = new Date().toISOString();
const rec = (n) => ({
  runId: '00000000-0000-0000-0000-' + String(n).padStart(12, '0'),
  runTag: 'tag' + n, taskId: null, startedAtIso: now, endedAtIso: now,
  endState: { ok: false, status: 'paused', reason: 'fixture' }, stages: [],
});
store.create({ mode: 'on', rootDir: world });
const child = spawn('sleep', ['10']);
const mutexPath = store.mutateLockPath(world);
try {
  fs.writeFileSync(mutexPath, JSON.stringify({
    hostname: os.hostname(), pid: child.pid, boot_id: null,
    starttime: sr.procStartTime(child.pid), created_at: new Date().toISOString(),
  }));
  const busy1 = store.writeRunRecord(rec(1), world, { waitMs: 0 });
  if (busy1.ok !== false || busy1.reason !== 'store-busy') {
    problems.push('foreign live lock with waitMs 0 not store-busy: ' + JSON.stringify(busy1.ok ? 'ok' : busy1.reason));
  }
  const busy2 = store.writeRunRecord(rec(2), world, { waitMs: 0 });
  if (busy2.ok !== false || busy2.reason !== 'store-busy') {
    problems.push('second zero-wait attempt did not stay store-busy');
  }
} finally {
  child.kill();
  try { fs.unlinkSync(mutexPath); } catch { /* gone */ }
}
const landed = store.writeRunRecord(rec(3), world, { waitMs: 0 });
if (!landed.ok) problems.push('write on the freed lock failed: ' + landed.reason + '/' + landed.detail);
const legacy = store.writeRunRecord(rec(4), world);
if (!legacy.ok) problems.push('two-arg call shape broke: ' + legacy.reason);
const list = store.readRunRecords(world);
if (!list.ok || list.runRecords.length !== 2) {
  problems.push('store carries ' + (list.runRecords || []).length + ' records (want 2)');
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C4_OUT="$(node run-c4.cjs 2>&1 | tail -n 1)"
t131_eq "C4: writeRunRecord forwards opts (waitMs 0 — store-busy as data under a foreign lock, lands once freed)" "OK" "$C4_OUT"

echo "--- T131 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
