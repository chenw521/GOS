#!/usr/bin/env bash
# gos-map:none
# Spawn child-tracking registry section -- every child spawnRun has alive is
# held in a module-level registry from the spawn call until the run settles,
# so a runner shutting down can still reach its children
# (killTrackedChildren is "the sweep" below). Proofs: the identity gate (a
# forged starttime leaves the live child alone and the skip is named), the
# live kill (a registered child dies and the payload names it), the group
# boundary (a child outside its own group is killed by pid only while that
# group's leader lives; the leader of the sweeper's own group is reached by
# pid alone while the sweeper lives), the refusal and skip routes, the
# release-on-settle lifecycle, and the module contract.
# Case map:
#   C1  identity gate: a real sleep child registered by spawnRun survives a
#       sweep after its entry is re-registered with a forged starttime; the
#       skip is named; the true identity restores the kill
#   C2  live kill: an empty registry sweeps to empty lists, the snapshot is
#       a detached copy, the sweep kills the child through its own process
#       group, and the settled run releases the entry
#   C3  group boundary, run inside detached hosts (each its own group
#       leader): a child sharing the host group is killed by pid only and
#       the host lives; the host itself, registered from a non-leading
#       member of its group, is killed by pid only and the member lives
#   C4  refusal and skip routes: the test seam refuses the own pid and
#       malformed ids; a reaped pid skips as dead; a live pid without a
#       recorded starttime is skipped, never killed; a spec without a
#       spawn id is tracked under its pid
#   C5  lifecycle: clean exit and wall kill both release on settle; an
#       earlier run settling under a replaced id keeps the later child
#   C6  module contract: no kill(0) form, no signal to the own process or
#       group, every signal target is a per-entry pid or the group it
#       leads, the group-leadership guard is present, exports keep the
#       runner surface
# HOME is pinned under TESTBASE. Standalone-safe: self-provisions env when
# not under test/run-sections.sh.

T130_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T130_STANDALONE=1
  T130_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T130_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T130_SELFROOT"
  export TESTBASE="$(mktemp -d "$T130_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T130_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t130"
mkdir -p "$T130_DIR" && cd "$T130_DIR" || exit 1

PASS=0
FAIL=0
t130_ok() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
t130_bad() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
t130_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t130_ok "$label"; else
    t130_bad "$label (expected: '$expected', got: '$actual')"
  fi
}

# Runs a driver script and judges the named verdict lines of its output.
# Every driver prints one "<name>=OK" or "<name>=BAD <why>" line per check;
# a crashed driver leaves its lines absent, which reads as a failure that
# carries the driver's own crash line.
t130_drive() { # $1=driver script; $2...=verdict names
  local script="$1" out name line why
  shift
  out="$(node "$script" 2>&1)"
  why="$(printf '%s\n' "$out" | grep -F -m1 -- 'driver=BAD' | cut -c1-240 || true)"
  for name in "$@"; do
    line="$(printf '%s\n' "$out" | grep -F -m1 -- "$name=" || true)"
    if [ "$line" = "$name=OK" ]; then t130_ok "$name"; else
      if [ -n "$line" ]; then t130_bad "$name (${line#*=})"; else t130_bad "$name (no verdict line; ${why:-driver ended without reporting})"; fi
    fi
  done
}

t130_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T130_DIR"
  if [ "$T130_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t130_teardown EXIT

echo "--- T130: spawn child-tracking registry ---"

# Shared driver helpers: the module under test, /proc reads independent of
# it, liveness probes, a bounded driver lifetime, and an exit sweep that
# removes every child a driver started.
cat > t130-lib.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const spawnrun = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/spawnrun.cjs'));

const judge = (name, ok, why) => { console.log(name + '=' + (ok ? 'OK' : 'BAD ' + (why || ''))); };
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch { return false; } };

const statFields = (pid) => {
  try {
    const raw = fs.readFileSync('/proc/' + pid + '/stat', 'utf8');
    return raw.slice(raw.lastIndexOf(')') + 2).split(' ');
  } catch { return null; }
};

const has = (spawnId) => spawnrun.trackedChildren().some((e) => e.spawnId === spawnId);
const entryOf = (spawnId) => spawnrun.trackedChildren().find((e) => e.spawnId === spawnId) || null;
const waitDead = async (pid, attempts) => {
  for (let i = 0; i < (attempts || 150); i += 1) {
    if (!alive(pid)) return true;
    await pause(20);
  }
  return false;
};

const spawned = [];
const remember = (pid) => { if (Number.isInteger(pid) && pid > 0 && pid !== process.pid) spawned.push(pid); };
process.on('exit', () => {
  for (const pid of spawned) { try { process.kill(pid, 'SIGKILL'); } catch { /* already gone */ } }
});

// Ends the driver after its output is flushed, so a child left behind by a
// broken registry cannot keep the driver alive.
const flushExit = (code) => { process.stdout.write('\n', () => process.exit(code)); };

const watchdog = (label, ms) => {
  const timer = setTimeout(() => { console.log(label + '=BAD driver exceeded its time budget'); flushExit(3); }, ms);
  return () => clearTimeout(timer);
};

const run = (main) => {
  const done = watchdog('driver', 15000);
  main().catch((e) => { console.log('driver=BAD ' + ((e && e.stack) || e)); }).then(() => { done(); flushExit(0); });
};

module.exports = { fs, path, spawn, spawnrun, judge, pause, alive, statFields, has, entryOf, waitDead, remember, run };
EOF

# ---------------------------------------------------------------- C1 --
# A real sleep child goes through spawnRun and lands in the registry with
# the starttime /proc reports. Re-registering the id with a forged starttime
# must make the sweep skip the live child and name the skip; restoring the
# true starttime must make the next sweep kill it, after which the settled
# run releases the entry.
cat > run-c1.cjs <<'EOF'
const L = require('./t130-lib.cjs');
L.run(async () => {
  const spawnId = 'identity-gate';
  const pending = L.spawnrun.spawnRun({ argv: ['sleep', '30'], spawnId }, {});
  const entry = L.entryOf(spawnId);
  if (!entry) { L.judge('C1 registry holds the live child under its spawn id', false, 'no entry appeared'); return; }
  L.remember(entry.pid);
  const fields = L.statFields(entry.pid);
  const recorded = Number(fields[19]) === entry.starttime;
  L.judge('C1 registry holds the live child under its spawn id',
    entry.pid > 0 && Object.keys(entry).sort().join(',') === 'pid,spawnId,starttime' && recorded && L.alive(entry.pid),
    JSON.stringify(entry));

  const forged = L.spawnrun.registerTrackedForTest(spawnId, { pid: entry.pid, starttime: entry.starttime + 1 });
  const gated = L.spawnrun.killTrackedChildren();
  await L.pause(300);
  const skip = gated.skipped.filter((s) => s.spawnId === spawnId);
  L.judge('C1 forged starttime gates the kill: the child survives and the skip is named',
    forged.ok === true && L.alive(entry.pid) && gated.killed.length === 0 && gated.pidOnly.length === 0
      && skip.length === 1 && skip[0].reason === 'starttime-mismatch' && skip[0].pid === entry.pid,
    JSON.stringify(gated));

  L.spawnrun.registerTrackedForTest(spawnId, { pid: entry.pid, starttime: entry.starttime });
  const restored = L.spawnrun.killTrackedChildren();
  const dead = await L.waitDead(entry.pid);
  const result = await pending;
  L.judge('C1 restored identity kills the child and the settled run releases the entry',
    restored.killed.length === 1 && restored.killed[0].spawnId === spawnId && restored.killed[0].pid === entry.pid
      && dead && result.status === null && !L.has(spawnId),
    JSON.stringify({ restored, dead, status: result.status, left: L.spawnrun.trackedChildren() }));
});
EOF
t130_drive run-c1.cjs \
  "C1 registry holds the live child under its spawn id" \
  "C1 forged starttime gates the kill: the child survives and the skip is named" \
  "C1 restored identity kills the child and the settled run releases the entry"

# ---------------------------------------------------------------- C2 --
# A fresh driver starts with an empty registry. While the child lives the
# snapshot lists it as a copy (mutating the returned value changes nothing),
# and the sweep kills it through the process group it leads. The sweep
# leaves the entry in place; the killed run settling releases it.
cat > run-c2.cjs <<'EOF'
const L = require('./t130-lib.cjs');
L.run(async () => {
  const empty = L.spawnrun.killTrackedChildren();
  L.judge('C2 empty registry sweeps to empty lists',
    Array.isArray(empty.killed) && empty.killed.length === 0 && Array.isArray(empty.skipped) && empty.skipped.length === 0
      && Array.isArray(empty.pidOnly) && empty.pidOnly.length === 0 && L.spawnrun.trackedChildren().length === 0,
    JSON.stringify(empty));

  const spawnId = 'live-kill';
  const pending = L.spawnrun.spawnRun({ argv: ['sleep', '30'], spawnId }, {});
  const entry = L.entryOf(spawnId);
  if (!entry) { L.judge('C2 snapshot lists the live entry as a detached copy', false, 'no entry appeared'); return; }
  L.remember(entry.pid);
  const snapshot = L.spawnrun.trackedChildren();
  const listed = snapshot.filter((e) => e.spawnId === spawnId);
  const shaped = snapshot.length === 1 && listed.length === 1 && typeof listed[0].spawnId === 'string'
    && Number.isInteger(listed[0].pid) && Number.isInteger(listed[0].starttime);
  snapshot.pop();
  const again = L.spawnrun.trackedChildren();
  L.judge('C2 snapshot lists the live entry as a detached copy',
    shaped && again.length === 1 && again[0].pid === entry.pid,
    JSON.stringify({ snapshot: again }));

  const pgrp = Number(L.statFields(entry.pid)[2]);
  const sweep = L.spawnrun.killTrackedChildren();
  const stillListed = L.has(spawnId);
  const dead = await L.waitDead(entry.pid);
  L.judge('C2 sweep kills the live child through its own process group',
    pgrp === entry.pid && dead && sweep.killed.length === 1 && sweep.killed[0].spawnId === spawnId
      && sweep.killed[0].pid === entry.pid && Object.keys(sweep.killed[0]).sort().join(',') === 'pid,spawnId'
      && sweep.skipped.length === 0 && sweep.pidOnly.length === 0,
    JSON.stringify({ pgrp, pid: entry.pid, sweep }));

  const result = await pending;
  L.judge('C2 sweep keeps the entry until the killed run settles and releases it',
    stillListed && result.status === null && !L.has(spawnId) && L.spawnrun.trackedChildren().length === 0,
    JSON.stringify({ stillListed, status: result.status, left: L.spawnrun.trackedChildren() }));
});
EOF
t130_drive run-c2.cjs \
  "C2 empty registry sweeps to empty lists" \
  "C2 snapshot lists the live entry as a detached copy" \
  "C2 sweep kills the live child through its own process group" \
  "C2 sweep keeps the entry until the killed run settles and releases it"

# ---------------------------------------------------------------- C3 --
# Group boundary. The host is started detached, so it leads its own process
# group; inside it a plain child shares that group without leading it. The
# sweep must reach such a child by pid only and must never signal the group
# it sits in -- the host lives to write its result.
cat > group-host.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const spawnrun = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/spawnrun.cjs'));
const outFile = process.argv[2];
const out = { leader: false, childSharesGroup: false, registered: false, problems: [] };
const finish = (code) => {
  try { fs.writeFileSync(outFile, JSON.stringify(out)); } catch { /* result file is best effort */ }
  process.exit(code);
};
const watchdog = setTimeout(() => { out.problems.push('host watchdog fired'); finish(1); }, 10000);
const statFields = (pid) => {
  try {
    const raw = fs.readFileSync('/proc/' + pid + '/stat', 'utf8');
    return raw.slice(raw.lastIndexOf(')') + 2).split(' ');
  } catch { return null; }
};
out.pgrp = Number((statFields(process.pid) || [])[2]);
out.leader = out.pgrp === process.pid;
if (!out.leader) { out.problems.push('host does not lead its process group'); finish(1); }
const child = spawn('sleep', ['30'], { stdio: 'ignore' });
out.childPid = child.pid;
const fields = statFields(child.pid);
if (!fields) { out.problems.push('child is not readable in /proc'); try { child.kill('SIGKILL'); } catch { /* already gone */ } finish(1); }
out.childSharesGroup = Number(fields[2]) === process.pid && child.pid !== process.pid;
const registered = spawnrun.registerTrackedForTest('nonleader', { pid: child.pid, starttime: Number(fields[19]) });
out.registered = registered.ok === true;
child.on('exit', (code, signal) => { out.childExit = signal; clearTimeout(watchdog); finish(0); });
out.sweep = spawnrun.killTrackedChildren();
setTimeout(() => {
  out.problems.push('child still alive after the sweep');
  try { child.kill('SIGKILL'); } catch { /* already gone */ }
  finish(1);
}, 4000);
EOF
cat > run-c3.cjs <<'EOF'
const L = require('./t130-lib.cjs');
L.run(async () => {
  const outFile = L.path.join(__dirname, 'group-host-result.json');
  const host = L.spawn(process.execPath, [L.path.join(__dirname, 'group-host.cjs'), outFile], { detached: true, stdio: 'ignore' });
  L.remember(host.pid);
  const exit = await new Promise((resolve) => host.on('exit', (code, signal) => resolve({ code, signal })));
  let out = null;
  try { out = JSON.parse(L.fs.readFileSync(outFile, 'utf8')); } catch { out = null; }
  const sweep = (out && out.sweep) || {};
  const killed = sweep.killed || [];
  const pidOnly = sweep.pidOnly || [];
  L.judge('C3 host leads its own process group and the child shares it',
    !!out && out.leader === true && out.childSharesGroup === true && out.registered === true,
    JSON.stringify(out));
  L.judge('C3 child sharing a foreign group is killed by pid only',
    !!out && out.childExit === 'SIGKILL' && killed.length === 1 && killed[0].mode === 'pid-only'
      && killed[0].pid === out.childPid && pidOnly.length === 1 && pidOnly[0].reason === 'not-group-leader'
      && pidOnly[0].pid === out.childPid && (sweep.skipped || []).length === 0,
    JSON.stringify(out));
  L.judge('C3 the group leader survives the sweep',
    !!out && exit.code === 0 && Array.isArray(out.problems) && out.problems.length === 0,
    JSON.stringify({ exit, problems: out && out.problems }));
});
EOF
t130_drive run-c3.cjs \
  "C3 host leads its own process group and the child shares it" \
  "C3 child sharing a foreign group is killed by pid only" \
  "C3 the group leader survives the sweep"

# The other side of the boundary: the leader of the sweeper's own group is
# itself the registered target. Signalling it as a group would take the
# sweeper down with it, so it must be reached by pid alone and the sweeper
# lives to write its result. Every process here sits inside the detached
# host's session, so a wrong signal stays contained.
cat > leader-host.cjs <<'EOF'
const path = require('path');
const { spawn } = require('child_process');
// Stays alive as the group leader until the sweeper settles its fate.
const sweeper = spawn(process.execPath, [path.join(__dirname, 'leader-sweeper.cjs'), process.argv[2]], { stdio: 'ignore' });
sweeper.on('exit', () => process.exit(0));
setInterval(() => {}, 1000);
EOF
cat > leader-sweeper.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const spawnrun = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/spawnrun.cjs'));
const outFile = process.argv[2];
const out = { sweeperAlive: true, problems: [] };
const finish = () => {
  try { fs.writeFileSync(outFile, JSON.stringify(out)); } catch { /* result file is best effort */ }
  process.exit(0);
};
const watchdog = setTimeout(() => { out.problems.push('sweeper watchdog fired'); finish(); }, 8000);
const statFields = (pid) => {
  try {
    const raw = fs.readFileSync('/proc/' + pid + '/stat', 'utf8');
    return raw.slice(raw.lastIndexOf(')') + 2).split(' ');
  } catch { return null; }
};
out.sweeperPid = process.pid;
out.pgrp = Number((statFields(process.pid) || [])[2]);
out.leaderIsOther = Number.isInteger(out.pgrp) && out.pgrp > 0 && out.pgrp !== process.pid;
if (!out.leaderIsOther) { out.problems.push('sweeper does not sit under another leader'); finish(); }
const leader = statFields(out.pgrp) || [];
out.leaderWasLive = !!leader.length && leader[0] !== 'Z';
out.registered = spawnrun.registerTrackedForTest('group-leader', { pid: out.pgrp, starttime: Number(leader[19]) }).ok;
out.sweep = spawnrun.killTrackedChildren();
setTimeout(() => {
  const after = statFields(out.pgrp);
  out.leaderStateAfter = after ? after[0] : null;
  clearTimeout(watchdog);
  finish();
}, 300);
EOF
cat > run-c3b.cjs <<'EOF'
const L = require('./t130-lib.cjs');
L.run(async () => {
  const outFile = L.path.join(__dirname, 'leader-sweeper-result.json');
  const host = L.spawn(process.execPath, [L.path.join(__dirname, 'leader-host.cjs'), outFile], { detached: true, stdio: 'ignore' });
  L.remember(host.pid);
  let out = null;
  for (let i = 0; i < 500 && !out; i += 1) {
    try { out = JSON.parse(L.fs.readFileSync(outFile, 'utf8')); } catch { out = null; }
    if (!out) await L.pause(20);
  }
  if (out && out.sweeperPid) L.remember(out.sweeperPid);
  const sweep = (out && out.sweep) || {};
  const killed = sweep.killed || [];
  const pidOnly = sweep.pidOnly || [];
  L.judge('C3 own group leader is killed by pid only, the sweeper survives',
    !!out && out.leaderIsOther === true && out.leaderWasLive === true && out.registered === true && out.sweeperAlive === true
      && (out.leaderStateAfter === 'Z' || out.leaderStateAfter === null)
      && killed.length === 1 && killed[0].pid === out.pgrp && killed[0].mode === 'pid-only'
      && pidOnly.length === 1 && pidOnly[0].reason === 'own-process-group' && pidOnly[0].pid === out.pgrp
      && (sweep.skipped || []).length === 0 && out.problems.length === 0,
    JSON.stringify(out));
});
EOF
t130_drive run-c3b.cjs \
  "C3 own group leader is killed by pid only, the sweeper survives"

# ---------------------------------------------------------------- C4 --
# Refusal and skip routes. The seam refuses the runner's own pid and
# malformed ids. A reaped pid is skipped as dead. A live child whose
# starttime was never recorded is skipped, never killed. A spec that carries
# no spawn id is tracked under its pid.
cat > run-c4.cjs <<'EOF'
const L = require('./t130-lib.cjs');
L.run(async () => {
  const ownStart = Number(L.statFields(process.pid)[19]);
  const refused = L.spawnrun.registerTrackedForTest('own-pid', { pid: process.pid, starttime: ownStart });
  const zero = L.spawnrun.registerTrackedForTest('zero', { pid: 0, starttime: 1 });
  const negative = L.spawnrun.registerTrackedForTest('negative', { pid: -1, starttime: 1 });
  const textual = L.spawnrun.registerTrackedForTest('textual', { pid: String(process.pid), starttime: 1 });
  const noId = L.spawnrun.registerTrackedForTest('', { pid: process.ppid, starttime: 1 });
  L.judge('C4 test seam refuses the own pid and malformed ids',
    refused.ok === false && refused.reason === 'own-pid' && zero.reason === 'invalid-pid' && negative.reason === 'invalid-pid'
      && textual.reason === 'invalid-pid' && noId.reason === 'invalid-spawn-id' && L.spawnrun.trackedChildren().length === 0,
    JSON.stringify({ refused, zero, negative, textual, noId }));

  const short = L.spawn('true', [], { stdio: 'ignore' });
  await new Promise((resolve) => short.on('exit', resolve));
  if (L.statFields(short.pid)) {
    L.judge('C4 reaped pid is skipped as dead', false, 'pid ' + short.pid + ' is still readable in /proc');
  } else {
    L.spawnrun.registerTrackedForTest('reaped', { pid: short.pid, starttime: 1 });
    const sweep = L.spawnrun.killTrackedChildren();
    L.judge('C4 reaped pid is skipped as dead',
      sweep.skipped.length === 1 && sweep.skipped[0].spawnId === 'reaped' && sweep.skipped[0].reason === 'pid-dead'
        && sweep.skipped[0].pid === short.pid && sweep.killed.length === 0 && sweep.pidOnly.length === 0,
      JSON.stringify(sweep));
  }

  const stranger = L.spawn('sleep', ['30'], { stdio: 'ignore' });
  L.remember(stranger.pid);
  L.spawnrun.registerTrackedForTest('unrecorded', { pid: stranger.pid, starttime: null });
  const unrecorded = L.spawnrun.killTrackedChildren();
  await L.pause(200);
  L.judge('C4 live pid without a recorded starttime is skipped, never killed',
    L.alive(stranger.pid) && unrecorded.killed.length === 0 && unrecorded.pidOnly.length === 0
      && unrecorded.skipped.some((s) => s.spawnId === 'unrecorded' && s.pid === stranger.pid && s.reason === 'starttime-mismatch'),
    JSON.stringify(unrecorded));

  const pending = L.spawnrun.spawnRun({ argv: ['sleep', '30'] }, {});
  const byPid = L.spawnrun.trackedChildren().filter((e) => e.spawnId === String(e.pid));
  const anon = byPid[0];
  if (!anon) { L.judge('C4 spec without a spawn id is tracked under its pid', false, 'no pid-keyed entry appeared'); return; }
  L.remember(anon.pid);
  const keyed = byPid.length === 1 && anon.pid > 0 && L.alive(anon.pid) && Number.isInteger(anon.starttime) && anon.starttime > 0;
  const anonSweep = L.spawnrun.killTrackedChildren();
  const anonResult = await pending;
  L.judge('C4 spec without a spawn id is tracked under its pid',
    keyed && anonSweep.killed.some((k) => k.spawnId === String(anon.pid) && k.pid === anon.pid)
      && anonResult.status === null && !L.spawnrun.trackedChildren().some((e) => e.spawnId === String(anon.pid)),
    JSON.stringify({ byPid, anonSweep, left: L.spawnrun.trackedChildren() }));
});
EOF
t130_drive run-c4.cjs \
  "C4 test seam refuses the own pid and malformed ids" \
  "C4 reaped pid is skipped as dead" \
  "C4 live pid without a recorded starttime is skipped, never killed" \
  "C4 spec without a spawn id is tracked under its pid"

# ---------------------------------------------------------------- C5 --
# Lifecycle. A clean exit and a wall kill each hold their entry while the
# child lives and release it on settle. When a second spawn reuses an id,
# the earlier run settling must not release the later child.
cat > run-c5.cjs <<'EOF'
const L = require('./t130-lib.cjs');
L.run(async () => {
  const clean = L.spawnrun.spawnRun({ argv: ['sleep', '0.2'], spawnId: 'clean-exit' }, {});
  const cleanHeld = L.has('clean-exit');
  const cleanResult = await clean;
  L.judge('C5 clean exit: entry held while alive, released on settle',
    cleanHeld && cleanResult.status === 0 && !cleanResult.error && !L.has('clean-exit'),
    JSON.stringify({ cleanHeld, status: cleanResult.status, left: L.spawnrun.trackedChildren() }));

  const walled = L.spawnrun.spawnRun({ argv: ['sleep', '30'], spawnId: 'wall-kill' }, { wallMs: 250 });
  const wallEntry = L.entryOf('wall-kill');
  L.remember(wallEntry && wallEntry.pid);
  const walledResult = await walled;
  L.judge('C5 wall kill: entry held while alive, released on settle',
    !!wallEntry && wallEntry.pid > 0 && walledResult.status === null && !!walledResult.error && walledResult.error.killed === true
      && !L.has('wall-kill'),
    JSON.stringify({ wallEntry, status: walledResult.status, left: L.spawnrun.trackedChildren() }));

  const first = L.spawnrun.spawnRun({ argv: ['sleep', '0.2'], spawnId: 'replaced' }, {});
  const second = L.spawnrun.spawnRun({ argv: ['sleep', '30'], spawnId: 'replaced' }, {});
  const secondEntry = L.entryOf('replaced');
  L.remember(secondEntry && secondEntry.pid);
  const firstResult = await first;
  const survivors = L.spawnrun.trackedChildren().filter((e) => e.spawnId === 'replaced');
  const secondSweep = L.spawnrun.killTrackedChildren();
  const secondResult = await second;
  L.judge('C5 replaced slot: the earlier run settles without releasing the later child',
    firstResult.status === 0 && !!secondEntry && survivors.length === 1 && survivors[0].pid === secondEntry.pid
      && secondSweep.killed.some((k) => k.spawnId === 'replaced' && k.pid === secondEntry.pid)
      && secondResult.status === null && !L.has('replaced'),
    JSON.stringify({ secondEntry, survivors, secondSweep, status: secondResult.status }));
});
EOF
t130_drive run-c5.cjs \
  "C5 clean exit: entry held while alive, released on settle" \
  "C5 wall kill: entry held while alive, released on settle" \
  "C5 replaced slot: the earlier run settles without releasing the later child"

# ---------------------------------------------------------------- C6 --
# Module contract, read from the source and the loaded module: the runner
# never signals pid zero or its own process, every signal target in the
# module is a per-entry pid or the group it leads, the group-leadership
# guard is in place, and the export surface keeps the runner functions
# beside the registry ones.
T130_SRC="$GOS_ROOT/bin/lib/ops/auto/spawnrun.cjs"
if grep -qE "process\.kill\(\s*0\s*," "$T130_SRC"; then
  t130_bad "C6 no kill(0) form in the runner module"
else
  t130_ok "C6 no kill(0) form in the runner module"
fi
if grep -qE "process\.kill\(\s*-\s*(0|process\.pid|process\.ppid)\s*," "$T130_SRC"; then
  t130_bad "C6 no signal to the own process or group"
else
  t130_ok "C6 no signal to the own process or group"
fi
T130_TARGETS="$(grep -oE "process\.kill\([^,]+," "$T130_SRC" | sed -E 's/^process\.kill\(//; s/,[[:space:]]*$//' | LC_ALL=C sort -u | tr '\n' ' ')"
t130_eq "C6 every signal targets a per-entry pid or its group" "-child.pid -pid pid " "$T130_TARGETS"
if [ "$(grep -c "pgrp" "$T130_SRC")" -ge 2 ]; then
  t130_ok "C6 group-leadership guard present"
else
  t130_bad "C6 group-leadership guard present"
fi
T130_EXPORTS="$(node -e "const path = require('path'); const m = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/spawnrun.cjs')); console.log(Object.keys(m).sort().join(','));")"
t130_eq "C6 module exports keep the runner surface and add the registry" \
  "DEFAULT_HEAD_BYTES,DEFAULT_TAIL_BYTES,killTrackedChildren,registerTrackedForTest,spawnDetached,spawnRun,trackedChildren" "$T130_EXPORTS"

echo "--- T130 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
