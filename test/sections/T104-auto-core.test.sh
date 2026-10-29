#!/usr/bin/env bash
# gos-map:none
# Full-auto core section — the observable-truths spec section against the landed auto modules
# (store/breaker/loop/ratify/redteam/delivery-publish) and the CLI surface.
# Case map (truth id -> case):
#   truth-one  C1  loop advances a fixture task across stage boundaries on the fake
#           host; every spawn recorded in the external trust store (counters + stamps)
#   truth-two  C2  `gos auto status` prints mode/profile/limits, hardening tier,
#           host tri-state and counters
#   truth-three  C3  PENDING recorded in-spawn (CLI), blocks the next advance (CLI),
#           runner ratifies from the store stamp (module)
#   truth-four  C4  N consecutive failures trip the breaker -> paused; resume shows
#           the breaker line and spawns nothing
#   truth-five  C5  red CI run holds until a recorded disposition; watch timeout
#           lands disposition-unknown (never the N layer)
#   truth-eight  C6  probe failures fail closed naming the matrix entry; non-verified
#           hosts are display-only and refuse real runs
#   truth-eleven C7  GOS_AUTO_SPAWNED marker refuses on/off/run/disposition (status
#           stays readable)
#   truth-twelve C8  double-zero rule, findings>0 held, prompt source hashes to the
#           runner-held template, archive approval stays a human gate
#   truth-thirteen C9  external mutation mid-loop pauses (never counts into N); a store
#           deleted mid-run pauses-with-guidance and tracked counters survive
#   truth-fourteen C10 future store schema / truncated stream / N=0 each fail into named
#           errors, never silent acceptance
#   truth-fifteen C11 K, B, failure class, timeout and rc0-no-advance verified
#           independently
#   truth-sixteen C12 live lock refuses --break-lock (recorded as takeover); cross-host
#           lock names the owning clone and recovers; a second auto run is
#           refused pointing at the live instance
#   C16 cli surface: --allow-full round-trips into the store and the status
#           first line (profile full without the flag still fails compose;
#           the flag without the profile is refused); auto run --break-lock
#           releases a stale lock and refuses a live holder; unknown
#           subcommands exit non-zero; --timeout-* flags persist into the
#           store and the loop resolves them as defaults (env still wins)
#   runner-legs case (extends the ratification + red-team truths): in-spawn
#           PENDING -> red-team double-zero (two findings=0) -> ratification
#           -> advance proceeds; a lone zero or findings>0 holds the gate
#           without ratifying (human approval required)
#   delivery case (extends the publish truths): the publish leg runs at SHIP
#           when the fixture delivery adapter is green (closure record
#           written); a red CI run pauses the loop awaiting disposition
#           (never the N layer)
#   mutation case (extends the external-mutation truth): spawn-authored
#           non-advancing commits count into N (rc0-no-advance), an external
#           stage change pauses with a report
# Fake host: GOS_AUTO_TEST_FIXTURE=1 activates the registry fixture row
# (gos-fixture-host; probe answers from recorded data, never a live spawn).
# Loop spawns run through injected spawnRunner harnesses only — no real host
# spawn ever happens in this section. HOME and XDG_DATA_HOME are pinned per
# case under TESTBASE; GOS_AUTO_TIMEOUT_*_SEC are micro-overridden wherever a
# loop runs. Standalone-safe: self-provisions env when not under
# test/run-sections.sh.

T104_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T104_STANDALONE=1
  T104_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T104_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T104_SELFROOT"
  export TESTBASE="$(mktemp -d "$T104_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T104_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t104"
mkdir -p "$T104_DIR" && cd "$T104_DIR" || exit 1

PASS=0
FAIL=0
t104_ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
t104_bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
t104_contains() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then t104_ok "$label"; else
    t104_bad "$label (expected: '$expected')"
    echo "    actual: $(printf '%s' "$actual" | head -c 160)"
  fi
}
t104_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t104_ok "$label"; else t104_bad "$label (expected: '$expected', got: '$actual')"; fi
}
t104_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then t104_ok "$label (exit $actual)"; else t104_bad "$label (expected exit $expected, got '${actual:-<none>}')"; fi
}

T104_PIDS=""
t104_teardown() {
  for p in $T104_PIDS; do kill "$p" 2>/dev/null; done
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T104_DIR"
  if [ "$T104_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t104_teardown EXIT

echo "--- T104: auto core (T1,T2,T3,T4,T5,T8,T11,T12,T13,T14,T15,T16) ---"

# One isolated case world per call: sandbox HOME + XDG_DATA_HOME + a git repo
# with a minimal task state. Remote-less repos get per-clone store dirs
# (local:<hash>), so cases never share store state.
t104_case() {
  T104_CASE="$T104_DIR/$1"
  mkdir -p "$T104_CASE/home" "$T104_CASE/xdg" "$T104_CASE/repo/.gos/logs"
  export HOME="$T104_CASE/home"
  export XDG_DATA_HOME="$T104_CASE/xdg"
  cd "$T104_CASE/repo" || exit 1
  git init -q -b work . && git commit -q --allow-empty -m root
}

# Minimal task state fixture on stdout; caller redirects into .gos/state.json.
t104_state() { # $1=current_stage $2=level (default 1) $3=extra json fields
  printf '{"schema_version":6,"level":%s,"current_stage":"%s","completed_stages":["INTENT"],"intent":{"summary":"t104 fixture","confirmed":true},"task_head":"abc123def0123456789abcdef0123456789abcdef","spec_path":null,"plan_path":null,"requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{}%s}' \
    "${2:-1}" "$1" "${3:-}"
}

# ---------------------------------------------------------------- C1 --
t104_case c1
t104_state THINK > .gos/state.json
export GOS_AUTO_TIMEOUT_WALL_SEC=2 GOS_AUTO_TIMEOUT_IDLE_SEC=1
cat > run-t1.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const NEXT = { THINK: 'PLAN', PLAN: 'SHIP' };
const stateFile = path.join(rootDir, '.gos', 'state.json');
function setStage(s) {
  const st = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
  st.current_stage = s;
  fs.writeFileSync(stateFile, JSON.stringify(st, null, 2));
}
// fake host session: one stage-advance commit + state move + terminal event;
// red-team review spawns (read-only workspace) answer a findings=0 verdict
const spawnRunner = (spec) => {
  if (spec.roWorkspace) return { status: 0, stdout: 'review clean\nREDTEAM-FINDINGS: 0\n', stderr: '' };
  spawnSync('git', ['commit', '--allow-empty', '-m', `chore(task): advance ${spec.stage.toLowerCase()}`], { cwd: rootDir });
  setStage(NEXT[spec.stage]);
  return { status: 0, stdout: '{"type":"message","text":"stage work done"}\n{"type":"result"}\n', stderr: '' };
};
store.create({ mode: 'on', rootDir, limits: { N: 3, K: 5, B: 30 } });
loop.createLoop({ rootDir, host: 'gos-fixture-host', env, maxIterations: 5, spawnRunner }).loop.run().then((r) => {
  const st = store.load(rootDir);
  const stamps = st.ok ? Object.keys(st.store.stamps).length : -1;
  console.log(`RES ${r.status}|${r.reason}|${r.deliveryAdapter}`);
  console.log(`ITER ${r.iterations.length}|${r.iterations.map((i) => i.signal).join(',')}`);
  console.log(`STORE ${st.ok ? st.store.counters.spawnCount : -1}|${stamps}|${st.ok ? st.store.counters.tripCount : -1}`);
}).catch((e) => { console.error(e); process.exit(1); });
EOF
T1_OUT="$(node run-t1.cjs 2>&1)"
t104_eq "T1: fake-host loop ends at SHIP with no delivery adapter" "ship|stage-ship|false" "$(printf '%s\n' "$T1_OUT" | grep '^RES ' | cut -d' ' -f2-)"
t104_eq "T1: every spawn advanced its stage (one fresh session per stage)" "2|advanced,advanced" "$(printf '%s\n' "$T1_OUT" | grep '^ITER ' | cut -d' ' -f2-)"
t104_eq "T1: store records every spawn (counters>0); stamps cover stage spawns and red-team rounds" "2|4|0" "$(printf '%s\n' "$T1_OUT" | grep '^STORE ' | cut -d' ' -f2-)"

# ---------------------------------------------------------------- C2 --
# the CLI write-class guard requires an active task in the case root (a
# project root sits above TESTBASE on developer machines)
t104_case c2
t104_state THINK > .gos/state.json
node "$GOS" auto on > t2-on.txt 2>&1; T2_ONRC=$?
t104_exit "T2: auto on creates the store (advisories non-fatal)" 0 "$T2_ONRC"
t104_contains "T2: auto on announces mode/limits" "auto mode ON — profile restricted, limits N=3/K=5/B=30" "$(cat t2-on.txt)"
GOS_AUTO_TEST_FIXTURE=1 node "$GOS" auto status > t2-status.txt 2>&1; T2_SRC=$?
t104_exit "T2: auto status exits 0 with a healthy store" 0 "$T2_SRC"
t104_contains "T2: status prints mode + profile + limits" "auto: mode on · profile restricted · limits N=3/K=5/B=30" "$(cat t2-status.txt)"
t104_contains "T2: status prints counters" "counters: spawns 0 · trips 0" "$(cat t2-status.txt)"
t104_contains "T2: status host tri-state shows the verified fixture row as selectable" "host gos-fixture-host: 9.9.9 @ gos-fixture-host@>=0.0.1 [verified] — selectable" "$(cat t2-status.txt)"
if grep -q 'tier bubblewrap' t2-status.txt || grep -q 'tier lexical' t2-status.txt; then
  t104_ok "T2: status prints the hardening tier (kernel bubblewrap or honest lexical degrade)"
else
  t104_bad "T2: status prints the hardening tier (kernel bubblewrap or honest lexical degrade)"
fi
# fixture rows are gated: without the test env the fixture host is unknown
node "$GOS" auto status > t2-nofix.txt 2>&1
if grep -q 'gos-fixture-host' t2-nofix.txt; then
  t104_bad "T2: fixture host hidden outside the test env gate"
else
  t104_ok "T2: fixture host hidden outside the test env gate"
fi
t104_case c2b
t104_state THINK > .gos/state.json
node "$GOS" auto status > t2-absent.txt 2>&1; T2_ARC=$?
t104_exit "T2: status stays readable with no store (never enabled)" 0 "$T2_ARC"
t104_contains "T2: status names the absent store" "auto was never enabled" "$(cat t2-absent.txt)"

# ---------------------------------------------------------------- C3 --
t104_case c3
mkdir -p .gos/task/x
printf '# Spec\n\nminimal t3 spec\n' > .gos/task/x/spec.md
t104_state THINK 2 ',"spec_path":".gos/task/x/spec.md"' > .gos/state.json
# in-spawn delegated commit: structural checks only -> PENDING, no evidence
GOS_AUTO_SPAWNED=1 node "$GOS" commit think > t3-pending.txt 2>&1; T3_PRC=$?
t104_exit "T3: in-spawn commit on a delegated stage succeeds structurally" 0 "$T3_PRC"
t104_contains "T3: in-spawn commit records a PENDING auto-approval (no evidence claim)" "approval recorded as PENDING" "$(cat t3-pending.txt)"
T3_APPT="$(python3 -c "import json;a=json.load(open('.gos/state.json'))['approvals']['THINK'];print(a['status'],a['mode'],('evidence' in a))")"
t104_eq "T3: persisted approval is PENDING/auto with zero evidence keys" "PENDING auto False" "$T3_APPT"
# a PENDING without runner ratification blocks the next stage advance
node "$GOS" commit build > t3-block.txt 2>&1; T3_BRC=$?
t104_exit "T3: unratified PENDING blocks the next stage advance" 1 "$T3_BRC"
t104_contains "T3: block names the ratification boundary" "ratification boundary" "$(cat t3-block.txt)"
# runner-side ratification from the store stamp (outside the sandbox)
cat > t3-ratify.cjs <<'EOF'
const path = require('path');
const crypto = require('crypto');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const ratify = require(path.join(GR, 'bin/lib/ops/auto/ratify.cjs'));
const rootDir = process.cwd();
const stream = '{"type":"message","text":"stage work"}\n{"type":"result"}\n';
const sha = crypto.createHash('sha256').update(stream).digest('hex');
const problems = [];
const pend = ratify.recordPending({ stage: 'THINK', spawnId: 'spawn-t3' });
if (!pend.ok || pend.approval.status !== 'PENDING' || 'evidence' in pend.approval) problems.push('recordPending shape');
store.create({ mode: 'on', rootDir });
const noStamp = ratify.ratify({ stage: 'THINK', spawnId: 'spawn-t3', streamSha256: sha }, { rootDir });
if (noStamp.status !== 'refused' || noStamp.reason !== 'stamp-missing') problems.push('ratify without stamp accepted');
if (!store.stampStream('spawn-t3', 'THINK', sha, new Date().toISOString(), rootDir).ok) problems.push('stamp failed');
const wrongHash = ratify.ratify({ stage: 'THINK', spawnId: 'spawn-t3', streamSha256: 'f'.repeat(64) }, { rootDir });
if (wrongHash.reason !== 'hash-mismatch') problems.push('hash mismatch not refused');
const wrongStage = ratify.ratify({ stage: 'PLAN', spawnId: 'spawn-t3', streamSha256: sha }, { rootDir });
if (wrongStage.reason !== 'stage-mismatch') problems.push('stage mismatch not refused');
const ok = ratify.ratify({ stage: 'THINK', spawnId: 'spawn-t3', streamSha256: sha }, { rootDir });
if (!ok.ok || !ok.replacedPending) problems.push('ratify did not replace the PENDING');
const ev = ok.stored && ok.stored.evidence;
if (!ev || ev.spawnId !== 'spawn-t3' || ev.streamSha256 !== sha || ev.stampCount !== 1) problems.push('evidence shape');
if (ok.stored.mode !== 'auto' || ok.stored.status !== 'ratified') problems.push('ratified record mode/status');
if (ratify.advanceBlocker({ THINK: ok.stored })) problems.push('ratified still blocks');
if (!ratify.advanceBlocker({ THINK: ratify.recordPending({ stage: 'THINK' }).approval })) problems.push('PENDING does not block');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
T3_RAT="$(node t3-ratify.cjs 2>&1 | tail -n 1)"
t104_eq "T3: ratify verifies the store stamp pairing (missing/mismatch/stage refusals, then mode+evidence)" "OK" "$T3_RAT"

# ---------------------------------------------------------------- C4 --
t104_case c4
t104_state THINK > .gos/state.json
export GOS_AUTO_TIMEOUT_WALL_SEC=2 GOS_AUTO_TIMEOUT_IDLE_SEC=1
cat > run-t4.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
let spawnCalls = 0;
const spawnRunner = () => { spawnCalls += 1; return { status: 1, stdout: '', stderr: 'fixture host broke' }; };
store.create({ mode: 'on', rootDir, limits: { N: 2, K: 9, B: 9 } });
loop.createLoop({ rootDir, host: 'gos-fixture-host', env, maxIterations: 9, spawnRunner }).loop.run().then((r) => {
  const st = store.load(rootDir);
  const last = st.ok ? [...st.store.breaker.records].reverse().find((x) => x.layer) : null;
  console.log(`RES ${r.status}|${r.reason}|${r.trip && r.trip.layer}|${r.trip && r.trip.cls}`);
  console.log(`SPAWN ${spawnCalls}|${r.iterations.length}`);
  console.log(`STORE ${st.ok ? st.store.counters.tripCount : -1}|${last ? last.layer + '/' + last.cls : 'none'}`);
}).catch((e) => { console.error(e); process.exit(1); });
EOF
T4_OUT="$(node run-t4.cjs 2>&1)"
t104_eq "T4: N consecutive failures trip the breaker -> paused" "paused|breaker-tripped|N|task" "$(printf '%s\n' "$T4_OUT" | grep '^RES ' | cut -d' ' -f2-)"
t104_eq "T4: loop stops spawning at the trip (no third spawn)" "2|2" "$(printf '%s\n' "$T4_OUT" | grep '^SPAWN ' | cut -d' ' -f2-)"
t104_eq "T4: trip persisted to the store (counter + layer record)" "1|N/task" "$(printf '%s\n' "$T4_OUT" | grep '^STORE ' | cut -d' ' -f2-)"
# resume surfaces the breaker first-line and spawns nothing (counters frozen)
node "$GOS" resume > t4-resume.txt 2>&1; T4_RRC=$?
t104_exit "T4: resume exits 0 (report only)" 0 "$T4_RRC"
t104_contains "T4: resume shows the breaker trip first-line" "breaker TRIPPED N/task" "$(cat t4-resume.txt)"
T4_AFTER="$(node -e "
const path=require('path');const s=require(path.join(process.env.GOS_ROOT,'bin/lib/ops/auto/store.cjs'));
const r=s.load(process.cwd());console.log(r.store.counters.spawnCount);")"
t104_eq "T4: resume spawned nothing (spawn counter frozen at the trip)" "2" "$T4_AFTER"

# ---------------------------------------------------------------- C5 --
t104_case c5
git remote add origin https://github.com/octocat/widget.git
cat > run-t5.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const breaker = require(path.join(GR, 'bin/lib/ops/auto/breaker.cjs'));
const delivery = require(path.join(GR, 'bin/lib/ops/auto/delivery.cjs'));
const publish = require(path.join(GR, 'bin/lib/ops/auto/delivery-publish.cjs'));
const rootDir = process.cwd();
const problems = [];
// offline origin: ls-remote is the only leg that would touch the network —
// every other git answer is the real repository's own metadata
const gitRunner = (args) => {
  if (args[0] === 'ls-remote') return { status: 0, stdout: 'f'.repeat(40) + '\tHEAD\n', stderr: '' };
  return null; // fall through to real git below
};
const capOpts = { rootDir, gitRunner: (args) => gitRunner(args) || require('child_process').spawnSync('git', args, { cwd: rootDir, encoding: 'utf8' }) };
const pinned = delivery.captureBaseline(capOpts);
if (!pinned.ok) throw new Error('baseline capture failed: ' + pinned.reason);
if (!delivery.pinBaseline(pinned.baseline, rootDir).ok) problems.push('baseline pin failed');
store.create({ mode: 'on', rootDir });
const mk = (ci) => ({
  rootDir,
  taskId: 'p0',
  subject: 'fix widget ratchet for ci gate',
  gitRunner: capOpts.gitRunner,
  ghRunner: (args) => (args[0] === 'pr' ? { status: 0, stdout: 'https://github.com/octocat/widget/pull/7\n', stderr: '' }
    : { status: 0, stdout: '{}', stderr: '' }),
  privilegedRunner: () => ({ status: 0, stdout: '', stderr: '' }),
  lintRunner: () => ({ status: 0, stdout: '', stderr: '' }),
  ciStatus: ci,
  sleep: () => Promise.resolve(),
});
(async () => {
  const red = await publish.publish(mk(async () => ({ state: 'red', runId: '987' })));
  if (red.status !== 'held' || red.reason !== 'red-run' || red.requiresDisposition !== true) problems.push('red not held: ' + red.status + '/' + red.reason);
  const none = publish.dispositionFor('987', rootDir);
  if (none.status !== 'not-found') problems.push('disposition found before recording');
  const w = publish.writeDisposition({ runId: '987', reason: 'flake acknowledged', by: 't104' }, rootDir);
  if (!w.ok || !w.ledgerMirror || !/^[0-9a-f]{64}$/.test(w.ledgerMirror.sha256)) problems.push('disposition write/mirror shape');
  const again = await publish.publish(mk(async () => ({ state: 'red', runId: '987' })));
  if (again.status !== 'red-dispositioned') problems.push('red did not clear after disposition: ' + again.status);
  const watch = await publish.watchCi({
    ciStatus: async () => ({ state: 'pending', runId: '988' }),
    timeoutMs: 150, pollMs: 30, sleep: () => Promise.resolve(),
  });
  if (watch.status !== publish.DISPOSITION_UNKNOWN || watch.signal !== publish.CI_WATCH_TIMEOUT_SIGNAL) {
    problems.push('watch timeout not disposition-unknown: ' + watch.status);
  }
  const tax = breaker.classify('ci-watch-timeout');
  if (!tax.ok || tax.countsTowardN !== false || tax.disposition !== 'unknown') problems.push('ci-watch-timeout counted toward N');
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
T5_RED="$(node run-t5.cjs 2>&1 | tail -n 1)"
t104_eq "T5: red CI run holds for a recorded disposition; watch timeout lands disposition-unknown (never N)" "OK" "$T5_RED"

# ---------------------------------------------------------------- C6 --
t104_case c6
t104_state THINK > .gos/state.json
mkdir -p "$HOME/.codex" # codex config root so its probe passes shape checks
cat > run-t8.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const registry = require(path.join(GR, 'bin/lib/ops/auto/adapters/registry.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const ctx = { env, home: process.env.HOME };
const problems = [];
// broken host: probe fails -> refusal names the matrix entry
const broken = registry.hostStatus('opencode', { ...ctx, runner: () => ({ ok: false, out: '', err: 'rc=1' }) });
if (broken.selectable) problems.push('broken probe selectable');
const msg = broken.failure && broken.failure.message || '';
if (!msg.includes('opencode@>=1.18.0 <2.0.0 [verified]')) problems.push('failure does not name the matrix entry: ' + msg);
// non-verified host: probe passes, status fixture-tested -> display-only
const passRunner = (c, a) => (a[0] === '--version' ? { ok: true, out: 'codex 0.30.1\n', err: '' } : { ok: true, out: 'usage: --json\n', err: '' });
const codex = registry.hostStatus('codex', { ...ctx, runner: passRunner });
if (codex.selectable || codex.status !== 'fixture-tested') problems.push('fixture-tested host selectable');
if (!(codex.failure && codex.failure.message.includes('display-only'))) problems.push('codex refusal not display-only guidance');
// fixture host unknown without the env gate
const hidden = registry.hostStatus('gos-fixture-host', { env: { ...env, GOS_AUTO_TEST_FIXTURE: '' } });
if (hidden.known || hidden.selectable || hidden.failure.class !== 'unknown-host') problems.push('fixture host known outside gate');
(async () => {
// the loop refuses to start on both shapes
store.create({ mode: 'on', rootDir });
const r1 = await loop.createLoop({ rootDir, host: 'opencode', env, probeRunner: () => ({ ok: false, out: '', err: 'rc=1' }) }).loop.run();
if (r1.reason !== 'host-not-selectable') problems.push('loop ran on probe-failed host');
if (!(r1.hostFailure && String(r1.hostFailure.message).includes('opencode@'))) problems.push('loop refusal lacks matrix entry');
const r2 = await loop.createLoop({ rootDir, host: 'codex', env, probeRunner: passRunner }).loop.run();
if (r2.reason !== 'host-not-selectable') problems.push('loop ran on display-only host');
if (r1.iterations.length || r2.iterations.length) problems.push('refused loops spawned');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
T8_OUT="$(node run-t8.cjs 2>&1 | tail -n 1)"
t104_eq "T8: probe failure fails closed naming the matrix entry; non-verified hosts refuse real runs" "OK" "$T8_OUT"

# ---------------------------------------------------------------- C7 --
t104_case c7
t104_state THINK > .gos/state.json
for spec in "on" "off" "run" "disposition 123 --reason x"; do
  GOS_AUTO_SPAWNED=1 node "$GOS" auto $spec > t11.txt 2>&1; T11_RC=$?
  if [ "$T11_RC" -eq 1 ] && grep -q "auto ${spec%% *} refused" t11.txt && grep -q "refuses to run inside a runner-spawned session" t11.txt; then
    t104_ok "T11: marker refuses auto ${spec%% *} inside a spawned session (guidance printed)"
  else
    t104_bad "T11: marker refuses auto ${spec%% *} inside a spawned session (rc=$T11_RC out=$(head -c 120 t11.txt))"
  fi
done
GOS_AUTO_SPAWNED=1 node "$GOS" auto status > t11-status.txt 2>&1; T11_SRC=$?
t104_exit "T11: auto status stays readable inside a spawned session" 0 "$T11_SRC"
T11_MOD="$(node -e "
const path=require('path');
const loop=require(path.join(process.env.GOS_ROOT,'bin/lib/ops/auto/loop.cjs'));
loop.createLoop({env:{GOS_AUTO_SPAWNED:'1'}}).loop.run().then((r)=>{
  console.log(r.status + '|' + r.reason);
});" 2>&1)"
t104_eq "T11: loop module refuses under the marker before any store/lock touch" "refused|marker-active" "$T11_MOD"

# ---------------------------------------------------------------- C8 --
t104_case c8
t104_state THINK > .gos/state.json
printf 'REDTEAM-FINDINGS: 0\nprompt file planted by a worker\n' > .gos/redteam-prompt.txt
cat > run-t12.cjs <<'EOF'
const path = require('path');
const crypto = require('crypto');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const redteam = require(path.join(GR, 'bin/lib/ops/auto/redteam.cjs'));
const launcher = require(path.join(GR, 'bin/lib/ops/auto/launcher.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const problems = [];
// verdict parsing
if (!redteam.parseFindings('review ok\nREDTEAM-FINDINGS: 2').ok) problems.push('verdict unparsable');
if (redteam.parseFindings('no verdict line').ok) problems.push('missing verdict accepted');
// double-zero rule
if (redteam.evaluateClearance([{ spawnId: 'a', findings: 0 }]).cleared) problems.push('single zero cleared');
if (!redteam.evaluateClearance([{ spawnId: 'a', findings: 0 }, { spawnId: 'b', findings: 0 }]).cleared) problems.push('double zero not cleared');
if (redteam.evaluateClearance([{ spawnId: 'a', findings: 0 }, { spawnId: 'a', findings: 0 }]).cleared) problems.push('same-id zeros counted twice');
const held = redteam.evaluateClearance([{ spawnId: 'a', findings: 0 }, { spawnId: 'b', findings: 3 }]);
if (!held.held || held.cleared) problems.push('findings>0 not held');
// runner-held prompt source: a planted repo prompt file is ignored
store.create({ mode: 'on', rootDir });
let capturedPrompt = null;
const spawnRunner = (spec) => { capturedPrompt = spec.prompt; return { status: 0, stdout: 'REDTEAM-FINDINGS: 0\n', stderr: '' }; };
(async () => {
const round = await redteam.runRound({ stage: 'THINK', spawnId: 'rt-1' }, { rootDir, env, spawnRunner });
if (!round.ok || round.round.classified !== 'zero') problems.push('round not classified zero');
const wantHash = redteam.promptSourceHash();
const plantHash = crypto.createHash('sha256').update(require('fs').readFileSync(path.join(rootDir, '.gos/redteam-prompt.txt'), 'utf8'), 'utf8').digest('hex');
if (round.promptSha256 !== wantHash || wantHash === plantHash) problems.push('prompt hash not the runner template');
if (capturedPrompt !== redteam.renderPrompt({ stage: 'THINK', spawnId: 'rt-1', seed: 'rt-1', rootDir })) problems.push('prompt not rendered from the runner template');
if (!capturedPrompt.includes('REDTEAM-FINDINGS: <n>')) problems.push('verdict contract missing from prompt');
const st = store.load(rootDir);
if (!st.ok || !st.store.stamps['rt-1']) problems.push('redteam stream not stamped');
// archive approval stays a human gate inside spawned sessions: the deny
// baseline carries the command and the escape detector scores any attempt
const composed = launcher.compose('restricted', { workspace: rootDir, env, store });
if (!composed.ok || !composed.deny.includes('gos approve archive')) problems.push('archive approval not denied by baseline');
const hits = launcher.scanSpawnOutput('worker tried: gos approve archive --reason x', { deny: composed.deny });
if (!hits.length) problems.push('escape detector missed archive approval attempt');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
T12_OUT="$(node run-t12.cjs 2>&1 | tail -n 1)"
t104_eq "T12: double-zero gate, findings held, prompt source = runner template, archive approval denied in-spawn" "OK" "$T12_OUT"

# ---------------------------------------------------------------- C9 --
t104_case c9
t104_state THINK > .gos/state.json
export GOS_AUTO_TIMEOUT_WALL_SEC=2 GOS_AUTO_TIMEOUT_IDLE_SEC=1
cat > run-t13.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const problems = [];
const stateFile = path.join(rootDir, '.gos', 'state.json');
function setStage(s) {
  const st = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
  st.current_stage = s;
  fs.writeFileSync(stateFile, JSON.stringify(st, null, 2));
}
// external mutation mid-loop: the spawn advances THINK->PLAN normally; after
// the loop's post-spawn refresh, a human-shaped edit (stage moved outside
// the loop, no loop-owned commit) is served by the state reader — the next
// iteration's identity revalidation must pause with a report, and the
// mutation never counts into N (the successful spawn kept consecutive=0).
let reads = 0;
const stateReader = () => {
  reads += 1;
  const raw = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
  if (reads >= 4) raw.current_stage = 'VERIFY'; // human stage-back observed on revalidation
  return raw;
};
const spawnRunner = (spec) => {
  spawnSync('git', ['commit', '--allow-empty', '-m', `chore(task): advance ${spec.stage.toLowerCase()}`], { cwd: rootDir });
  setStage('PLAN');
  return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
};
(async () => {
store.create({ mode: 'on', rootDir, limits: { N: 2, K: 9, B: 9 } });
const r = await loop.createLoop({ rootDir, host: 'gos-fixture-host', env, maxIterations: 9, spawnRunner, stateReader }).loop.run();
if (r.status !== 'paused' || r.reason !== 'external-mutation') problems.push('mutation not paused: ' + r.status + '/' + r.reason);
if (!String(r.detail || '').includes('stage')) problems.push('mutation report lacks fields');
if (!r.breaker || r.breaker.consecutive !== 0) problems.push('mutation counted into N');
if (r.iterations.length !== 1 || r.iterations[0].signal !== 'advanced') problems.push('iteration shape wrong');
// store deleted mid-run: next touch pauses with guidance, tracked mirrors survive
const root2 = path.join(path.dirname(rootDir), 'c9b');
fs.mkdirSync(path.join(root2, '.gos', 'logs'), { recursive: true });
fs.copyFileSync(stateFile, path.join(root2, '.gos', 'state.json'));
spawnSync('git', ['init', '-q', '-b', 'work', '.'], { cwd: root2 });
spawnSync('git', ['commit', '--allow-empty', '-m', 'root'], { cwd: root2 });
store.create({ mode: 'on', rootDir: root2, mirrors: { spawnCount: 2, tripCount: 1 } });
const kept = store.load(root2);
if (!kept.ok || kept.store.counters.spawnCount !== 2 || kept.store.counters.tripCount !== 1) problems.push('mirror counters did not survive');
fs.rmSync(store.storeRoot(root2), { recursive: true, force: true });
const after = store.load(root2);
if (after.status !== 'paused' || after.reason !== 'missing' || !after.guidance) problems.push('deleted store not paused-with-guidance');
const loopAfter = await loop.createLoop({ rootDir: root2, host: 'gos-fixture-host', env }).loop.run();
if (loopAfter.status !== 'paused' || loopAfter.reason !== 'missing') problems.push('loop ran on deleted store');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
T13_OUT="$(node run-t13.cjs 2>&1 | tail -n 1)"
t104_eq "T13: external mutation pauses with a report (never into N); deleted store pauses with guidance, counters survive" "OK" "$T13_OUT"

# --------------------------------------------------------------- C10 --
t104_case c10
t104_state THINK > .gos/state.json
node "$GOS" auto on --max-retries 0 > t14-limits.txt 2>&1; T14_LRC=$?
t104_exit "T14: N=0 user input fails closed (validation)" 1 "$T14_LRC"
t104_contains "T14: N=0 names the integer floor" "N must be an integer >= 1" "$(cat t14-limits.txt)"
cat > run-t14.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const adapter = require(path.join(GR, 'bin/lib/ops/auto/adapters/opencode.cjs'));
const breaker = require(path.join(GR, 'bin/lib/ops/auto/breaker.cjs'));
const rootDir = process.cwd();
const problems = [];
// future store schema: named version-mismatch, never silent acceptance
const base = store.create({ mode: 'on', rootDir });
if (!base.ok) problems.push('store create failed');
base.store.store_schema_version = 99;
fs.writeFileSync(path.join(store.storeRoot(rootDir), 'store.json'), JSON.stringify(base.store));
const v = store.load(rootDir);
if (v.status !== 'paused' || v.reason !== 'version-mismatch') problems.push('future schema not version-mismatch: ' + v.reason);
if (!(v.guidance && String(v.guidance.what).includes('v99'))) problems.push('version error not named');
// truncated stream: named failure class, parser never throws
const trunc = adapter.parseEventStream('{"type":"message","text":"half of a js');
if (trunc.ok || trunc.failure.class !== 'stream-malformed-json') problems.push('truncated stream not malformed-json');
const noTerm = adapter.parseEventStream('{"type":"message"}\n');
if (noTerm.ok || noTerm.failure.class !== 'stream-no-terminal-event') problems.push('no-terminal stream misclassified');
if (!adapter.parseEventStream('{"type":"result"}\n').ok) problems.push('terminal stream failed');
// validation: limits and timeout overrides fail with named errors
if (breaker.validateLimits({ N: 0, K: 1, B: 1 }).reason !== 'invalid-limits') problems.push('N=0 accepted by validator');
if (breaker.timeoutPolicy({ GOS_AUTO_TIMEOUT_WALL_SEC: 'abc' }).reason !== 'invalid-timeout') problems.push('malformed timeout override accepted');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
T14_OUT="$(node run-t14.cjs 2>&1 | tail -n 1)"
t104_eq "T14: future store schema / truncated stream / malformed inputs fail into named errors" "OK" "$T14_OUT"

# --------------------------------------------------------------- C11 --
t104_case c11
export GOS_AUTO_TIMEOUT_WALL_SEC=1 GOS_AUTO_TIMEOUT_IDLE_SEC=1
cat > run-t15.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const breaker = require(path.join(GR, 'bin/lib/ops/auto/breaker.cjs'));
const problems = [];
const mk = (limits) => {
  const root = path.join(process.cwd(), 's' + Math.random().toString(36).slice(2, 8));
  const created = store.create({ mode: 'on', rootDir: root, limits });
  if (!created.ok) throw new Error('store create failed');
  return { root, made: breaker.createBreaker({ rootDir: root, limits }) };
};
// K only: advance/regress ping-pong trips only K
const k = mk({ N: 9, K: 2, B: 9 });
if (!k.made.breaker.visit('THINK').ok) problems.push('visit 1 failed');
k.made.breaker.visit('PLAN');
const kt = k.made.breaker.visit('THINK');
if (!kt.tripped || kt.layer !== 'K') problems.push('ping-pong did not trip K');
if (!String(kt.reason).includes('re-entered')) problems.push('K reason wrong');
if (k.made.breaker.state().consecutive !== 0) problems.push('K trip counted N');
// B only: budget exhaustion trips only B
const b = mk({ N: 9, K: 9, B: 2 });
store.bumpSpawn(b.root); store.bumpSpawn(b.root);
const bt = b.made.breaker.checkBudget();
if (!bt.tripped || bt.layer !== 'B') problems.push('budget did not trip B');
if (!String(bt.reason).includes('spawn budget exhausted')) problems.push('B reason wrong');
// failure classes: env/auth tagged, not task
if (breaker.classify('spawn-error').cls !== 'env') problems.push('spawn-error not env');
if (breaker.classify('auth-rejected').cls !== 'auth') problems.push('auth-rejected not auth');
if (breaker.classify('wall-timeout').cls !== 'timeout') problems.push('wall-timeout not timeout');
if (breaker.classify('bogus-signal').ok) problems.push('unknown signal accepted');
const e = mk({ N: 2, K: 9, B: 9 });
e.made.breaker.recordFailure('THINK', 'env');
const et = e.made.breaker.recordFailure('THINK', 'env');
if (!et.tripped || et.layer !== 'N' || et.cls !== 'env') problems.push('env failures tripped wrong layer/class');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
T15_A="$(node run-t15.cjs 2>&1 | tail -n 1)"
t104_eq "T15: K (ping-pong), B (budget), failure classes verified independently" "OK" "$T15_A"
# timeout expiry counts into N: the micro-overridden wall clock drives a real
# sleep spawn to ETIMEDOUT; rc0 without a stage-labeled commit scores failure
t104_state THINK > .gos/state.json
cat > run-t15b.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1', GOS_AUTO_TIMEOUT_WALL_SEC: '1' };
const stateFile = path.join(rootDir, '.gos', 'state.json');
const problems = [];
function subrepo(name) {
  const dir = path.join(rootDir, name);
  fs.mkdirSync(path.join(dir, '.gos', 'logs'), { recursive: true });
  fs.copyFileSync(stateFile, path.join(dir, '.gos', 'state.json'));
  spawnSync('git', ['init', '-q', '-b', 'work', '.'], { cwd: dir });
  spawnSync('git', ['commit', '--allow-empty', '-m', 'root'], { cwd: dir });
  return dir;
}
(async () => {
  // wall timeout: the injected runner honors ctx.wallMs with a real sleep
  const ta = subrepo('ta');
  store.create({ mode: 'on', rootDir: ta, limits: { N: 1, K: 9, B: 9 } });
  const sleepRunner = (spec, ctx) => spawnSync('sleep', ['30'], { timeout: ctx.wallMs });
  const r1 = await loop.createLoop({ rootDir: ta, host: 'gos-fixture-host', env, spawnRunner: sleepRunner }).loop.run();
  if (r1.reason !== 'breaker-tripped' || r1.trip.layer !== 'N' || r1.trip.cls !== 'timeout') problems.push('wall timeout not N/timeout: ' + JSON.stringify(r1.trip && r1.trip.layer));
  if (r1.iterations[0].signal !== 'wall-timeout' || !r1.iterations[0].counted) problems.push('timeout not counted');
  // rc0 + terminal event but no new stage-labeled commit since pre-spawn HEAD
  const tb = subrepo('tb');
  store.create({ mode: 'on', rootDir: tb, limits: { N: 1, K: 9, B: 9 } });
  const idleRunner = () => ({ status: 0, stdout: '{"type":"result"}\n', stderr: '' });
  const r2 = await loop.createLoop({ rootDir: tb, host: 'gos-fixture-host', env, spawnRunner: idleRunner }).loop.run();
  if (r2.reason !== 'breaker-tripped' || r2.trip.layer !== 'N') problems.push('rc0-no-advance did not trip N');
  if (r2.iterations[0].signal !== 'rc0-no-advance' || !r2.iterations[0].counted) problems.push('rc0-no-advance not counted as failure');
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
T15_B="$(node run-t15b.cjs 2>&1 | tail -n 1)"
t104_eq "T15: micro-overridden wall timeout counts into N; rc0 with no advance records as failure" "OK" "$T15_B"

# --------------------------------------------------------------- C12 --
t104_case c12
t104_state THINK > .gos/state.json
cat > run-t16.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const rootDir = process.cwd();
const problems = [];
store.create({ mode: 'on', rootDir });
// live pid + matching hostname: --break-lock refused, attempt recorded
const acq = store.acquireRunLock({ rootDir });
if (!acq.ok) problems.push('initial acquire failed');
const brk = store.breakRunLock(rootDir);
if (brk.ok || !brk.refused || !(brk.holder && brk.holder.pid === process.pid)) problems.push('live lock was breakable');
const st1 = store.load(rootDir);
const rec = st1.ok ? [...st1.store.breaker.records].reverse().find((x) => x.cls === 'takeover') : null;
if (!rec || !String(rec.detail).includes('refused --break-lock')) problems.push('takeover attempt not recorded');
store.releaseRunLock(rootDir);
// stale cross-host lock: refusal names the owning clone; recovery via break
const lp = path.join(store.storeRoot(rootDir), 'run.lock');
const now = new Date().toISOString();
const deadPid=(()=>{try{const mx=parseInt(fs.readFileSync('/proc/sys/kernel/pid_max','utf8'),10)||4194304;for(let p=mx-1;p>1;p--){try{process.kill(p,0);}catch(e){if(e.code==='ESRCH')return p;}}}catch(e){}return 999999;})();
fs.writeFileSync(lp, JSON.stringify({ hostname: 't104-other-box', pid: deadPid, boot_id: null, clone_path: '/t104/other-clone', started_at: now, heartbeat_at: now }));
const xh = store.acquireRunLock({ rootDir });
if (xh.ok || xh.reason !== 'cross-host') problems.push('cross-host lock acquired');
if (!(xh.holder && xh.holder.clone_path === '/t104/other-clone')) problems.push('refusal lacks owning clone');
if (!(xh.guidance && String(xh.guidance.what).includes('/t104/other-clone'))) problems.push('guidance does not name the clone');
const rec2 = store.acquireRunLock({ rootDir, breakLock: true });
if (!rec2.ok) problems.push('cross-host break-lock recovery failed');
store.releaseRunLock(rootDir);
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
T16_A="$(node run-t16.cjs 2>&1 | tail -n 1)"
t104_eq "T16: live lock refuses --break-lock (takeover recorded); cross-host refusal names the clone and recovers" "OK" "$T16_A"
# concurrent second auto run: a live child holds the lock; the CLI refuses
cat > t16-child.cjs <<'EOF'
const path = require('path');
const store = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/store.cjs'));
const r = store.acquireRunLock({ rootDir: process.argv[2] });
if (!r.ok) { console.error('child acquire failed'); process.exit(1); }
console.log('READY');
setInterval(() => {}, 1000);
EOF
node t16-child.cjs "$PWD" > t16-ready.txt 2>&1 &
T16_CHILD=$!
T104_PIDS="$T104_PIDS $T16_CHILD"
for i in $(seq 1 50); do grep -q READY t16-ready.txt 2>/dev/null && break; sleep 0.1; done
GOS_AUTO_TEST_FIXTURE=1 node "$GOS" auto run > t16-run.txt 2>&1; T16_RRC=$?
t104_exit "T16: second concurrent auto run refuses while the first holds the lock" 1 "$T16_RRC"
t104_contains "T16: refusal points at the live instance (pid)" "an auto run is already active (pid $T16_CHILD" "$(cat t16-run.txt)"
kill "$T16_CHILD" 2>/dev/null
T104_PIDS=""

# ------------------------------------------- runner legs (delegation) ------
# runner legs end to end: the fake host runs the REAL in-spawn commit for the
# delegated stages (PENDING recorded by the commit gate), red-team rounds
# answer findings=0 twice, and the loop ratifies from the store stamp before
# the next stage spawn proceeds.
t104_case c13
mkdir -p .gos/task/p0
printf '# Spec\n\np0 auto spec\n' > .gos/task/p0/spec.md
printf '# Plan\n\np0 auto plan\n' > .gos/task/p0/plan.md
t104_state THINK 3 ',"spec_path":".gos/task/p0/spec.md","plan_path":".gos/task/p0/plan.md"' > .gos/state.json
export GOS_AUTO_TIMEOUT_WALL_SEC=5 GOS_AUTO_TIMEOUT_IDLE_SEC=2
cat > run-c13.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const problems = [];
const stateFile = path.join(rootDir, '.gos', 'state.json');
const NEXT = { BUILD: 'REVIEW', REVIEW: 'VERIFY', VERIFY: 'SHIP' };
function setStage(s) {
  const st = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
  st.current_stage = s;
  fs.writeFileSync(stateFile, JSON.stringify(st, null, 2));
}
const gosCommit = (stage) => spawnSync(process.execPath, [path.join(GR, 'bin', 'gos.cjs'), 'commit', stage], {
  cwd: rootDir, env: { ...process.env, GOS_AUTO_SPAWNED: '1' }, encoding: 'utf8',
});
const spawnRunner = (spec) => {
  if (spec.roWorkspace) return { status: 0, stdout: 'independent review\nREDTEAM-FINDINGS: 0\n', stderr: '' };
  if (spec.stage === 'THINK' || spec.stage === 'PLAN') {
    const r = gosCommit(spec.stage.toLowerCase());
    if (r.status !== 0) problems.push(`in-spawn commit ${spec.stage} rc=${r.status}: ${String(r.stderr || r.stdout).slice(0, 200)}`);
    return { status: 0, stdout: '{"type":"message","text":"stage work done"}\n{"type":"result"}\n', stderr: '' };
  }
  spawnSync('git', ['commit', '--allow-empty', '-m', `chore(task): advance ${spec.stage.toLowerCase()}`], { cwd: rootDir });
  setStage(NEXT[spec.stage]);
  return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
};
(async () => {
  store.create({ mode: 'on', rootDir, limits: { N: 3, K: 9, B: 30 } });
  const r = await loop.createLoop({ rootDir, host: 'gos-fixture-host', env, maxIterations: 9, spawnRunner }).loop.run();
  if (r.status !== 'ship' || r.ok !== true) problems.push('loop did not ship: ' + r.status + '/' + r.reason);
  const st = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
  const aT = (st.approvals || {}).THINK || {};
  const aP = (st.approvals || {}).PLAN || {};
  if (aT.status !== 'ratified' || aT.mode !== 'auto') problems.push('THINK not ratified: ' + JSON.stringify(aT));
  if (aP.status !== 'ratified' || aP.mode !== 'auto') problems.push('PLAN not ratified: ' + JSON.stringify(aP));
  const thinkIter = (r.iterations || []).find((i) => i.stage === 'THINK');
  if (!thinkIter) problems.push('no THINK iteration recorded');
  else {
    const dl = thinkIter.delegation;
    if (!dl || !dl.redteam || dl.redteam.rounds !== 2 || dl.redteam.zeros !== 2) problems.push('THINK red-team leg summary missing');
    if (aT.evidence && aT.evidence.spawnId !== thinkIter.spawnId) problems.push('evidence does not pair the stage spawn');
  }
  const s = store.load(rootDir);
  const rt1 = s.ok && s.store.stamps[`${thinkIter.spawnId}-rt1`];
  const rt2 = s.ok && s.store.stamps[`${thinkIter.spawnId}-rt2`];
  if (!rt1 || !rt2 || rt1.stage !== 'redteam' || rt2.stage !== 'redteam') problems.push('red-team rounds not stamped under the redteam stage');
  const pend = Object.values(st.approvals || {}).filter((v) => v && v.status === 'PENDING');
  if (pend.length) problems.push('PENDING approvals remain: ' + pend.length);
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
T13A_OUT="$(node run-c13.cjs 2>&1 | tail -n 1)"
t104_eq "T3: runner legs — in-spawn PENDING, double-zero red-team, ratification, advance proceeds" "OK" "$T13A_OUT"

# ------------------------------------------- held gates (delegation) ------
# held gates: a lone findings=0 round never clears the double-zero rule and
# findings>0 holds outright — the PENDING approval stays unratified (the next
# advance stays blocked at the ratification boundary) and the breaker's
# consecutive layer never moves.
t104_case c13b
mkdir -p .gos/task/p0
printf '# Spec\n\np0 auto spec\n' > .gos/task/p0/spec.md
t104_state THINK 3 ',"spec_path":".gos/task/p0/spec.md"' > .gos/state.json
cat > run-c13b.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const problems = [];
function mkWorld(name, verdictFor) {
  const dir = path.join(process.cwd(), name);
  fs.mkdirSync(path.join(dir, '.gos', 'task', 'p0'), { recursive: true });
  fs.mkdirSync(path.join(dir, '.gos', 'logs'), { recursive: true });
  fs.copyFileSync(path.join(process.cwd(), '.gos', 'task', 'p0', 'spec.md'), path.join(dir, '.gos', 'task', 'p0', 'spec.md'));
  const base = JSON.parse(fs.readFileSync(path.join(process.cwd(), '.gos', 'state.json'), 'utf8'));
  fs.writeFileSync(path.join(dir, '.gos', 'state.json'), JSON.stringify(base));
  spawnSync('git', ['init', '-q', '-b', 'work', '.'], { cwd: dir });
  spawnSync('git', ['commit', '--allow-empty', '-m', 'root'], { cwd: dir });
  const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
  const spawnRunner = (spec) => {
    if (spec.roWorkspace) return { status: 0, stdout: verdictFor(spec.spawnId), stderr: '' };
    if (spec.stage !== 'THINK') throw new Error('unexpected stage ' + spec.stage);
    const r = spawnSync(process.execPath, [path.join(GR, 'bin', 'gos.cjs'), 'commit', 'think'], {
      cwd: dir, env: { ...process.env, GOS_AUTO_SPAWNED: '1' }, encoding: 'utf8',
    });
    if (r.status !== 0) problems.push(`in-spawn commit rc=${r.status}: ${String(r.stderr || r.stdout).slice(0, 200)}`);
    return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
  };
  return { dir, env, spawnRunner };
}
(async () => {
  const cases = [
    { name: 'single-zero', verdict: (id) => (id.endsWith('-rt1') ? 'REDTEAM-FINDINGS: 0\n' : 'reviewer said nothing verdict-shaped\n') },
    { name: 'findings', verdict: () => 'REDTEAM-FINDINGS: 3\n' },
  ];
  for (const c of cases) {
    const w = mkWorld(c.name, c.verdict);
    store.create({ mode: 'on', rootDir: w.dir, limits: { N: 3, K: 9, B: 30 } });
    const r = await loop.createLoop({ rootDir: w.dir, host: 'gos-fixture-host', env: w.env, maxIterations: 5, spawnRunner: w.spawnRunner }).loop.run();
    if (r.status !== 'paused' || r.reason !== 'delegation-held' || r.held !== true) problems.push(c.name + ' not held: ' + r.status + '/' + r.reason);
    if (!r.guidance || !String(r.guidance.what).includes('THINK')) problems.push(c.name + ' guidance lacks the stage');
    if (!r.breaker || r.breaker.consecutive !== 0) problems.push(c.name + ' counted into N');
    const st = JSON.parse(fs.readFileSync(path.join(w.dir, '.gos', 'state.json'), 'utf8'));
    const aT = (st.approvals || {}).THINK || {};
    if (aT.status !== 'PENDING') problems.push(c.name + ' approval left the PENDING state: ' + JSON.stringify(aT.status));
    const blocked = spawnSync(process.execPath, [path.join(GR, 'bin', 'gos.cjs'), 'commit', 'plan'], { cwd: w.dir, encoding: 'utf8' });
    if (blocked.status !== 1 || !String(blocked.stderr || '').includes('ratification boundary')) problems.push(c.name + ' next advance not blocked at the boundary');
  }
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
T13B_OUT="$(node run-c13b.cjs 2>&1 | tail -n 1)"
t104_eq "T12: single zero and findings>0 hold the gate — PENDING stays, next advance blocked, never N" "OK" "$T13B_OUT"

# ------------------------------------------- publish leg at SHIP ------
# publish leg at SHIP: with a green fixture delivery adapter (probe state in
# the store) the loop invokes publish (push -> PR -> subject lint -> squash
# merge -> CI watch) and the closure record lands in the repo ledger mirror;
# a red CI run pauses the loop awaiting a human disposition (never N). With no
# adapter the loop still ends cleanly at SHIP (covered by C1).
t104_case c14
git remote add origin https://github.com/octocat/widget.git
t104_state BUILD > .gos/state.json
cat > run-c14.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const delivery = require(path.join(GR, 'bin/lib/ops/auto/delivery.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const problems = [];
const templateState = JSON.parse(fs.readFileSync(path.join(process.cwd(), '.gos', 'state.json'), 'utf8'));
const NEXT = { BUILD: 'VERIFY', VERIFY: 'SHIP' };
function mkWorld(name) {
  const dir = path.join(process.cwd(), name);
  fs.mkdirSync(path.join(dir, '.gos', 'logs'), { recursive: true });
  fs.writeFileSync(path.join(dir, '.gos', 'state.json'), JSON.stringify(templateState));
  spawnSync('git', ['init', '-q', '-b', 'work', '.'], { cwd: dir });
  spawnSync('git', ['remote', 'add', 'origin', 'https://github.com/octocat/widget.git'], { cwd: dir });
  spawnSync('git', ['commit', '--allow-empty', '-m', 'root'], { cwd: dir });
  const stateFile = path.join(dir, '.gos', 'state.json');
  const setStage = (s) => {
    const st = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
    st.current_stage = s;
    fs.writeFileSync(stateFile, JSON.stringify(st, null, 2));
  };
  const gitRunner = (args) => (args[0] === 'ls-remote'
    ? { status: 0, stdout: 'f'.repeat(40) + '\tHEAD\n', stderr: '' }
    : spawnSync('git', args, { cwd: dir, encoding: 'utf8' }));
  const spawnRunner = (spec) => {
    if (spec.roWorkspace) return { status: 0, stdout: 'REDTEAM-FINDINGS: 0\n', stderr: '' };
    spawnSync('git', ['commit', '--allow-empty', '-m', `chore(task): advance ${spec.stage.toLowerCase()}`], { cwd: dir });
    setStage(NEXT[spec.stage]);
    return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
  };
  return { dir, stateFile, gitRunner, spawnRunner };
}
const deliveryOpts = (baseline, ci) => ({
  subject: 'fix widget ratchet for ci gate',
  baseline,
  ghRunner: (args) => (args[0] === 'pr' ? { status: 0, stdout: 'https://github.com/octocat/widget/pull/9\n', stderr: '' } : { status: 0, stdout: '{}', stderr: '' }),
  privilegedRunner: () => ({ status: 0, stdout: '', stderr: '' }),
  lintRunner: () => ({ status: 0, stdout: '', stderr: '' }),
  ciStatus: ci,
  sleep: () => Promise.resolve(),
  timeoutMs: 400,
  pollMs: 40,
});
(async () => {
  const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
  // green CI: publish completes, closure record written
  const g = mkWorld('green');
  store.create({ mode: 'on', rootDir: g.dir });
  store.saveProbeResult({ host: 'delivery', state: 'green', checkedAtIso: new Date().toISOString() }, g.dir);
  const pinned = delivery.captureBaseline({ rootDir: g.dir, gitRunner: g.gitRunner });
  if (!pinned.ok) throw new Error('baseline capture failed: ' + pinned.reason);
  if (!delivery.pinBaseline(pinned.baseline, g.dir).ok) problems.push('baseline pin failed');
  const green = await loop.createLoop({
    rootDir: g.dir, host: 'gos-fixture-host', env, maxIterations: 6,
    spawnRunner: g.spawnRunner, gitRunner: g.gitRunner,
    delivery: deliveryOpts(pinned.baseline, async () => ({ state: 'green', runId: '555' })),
  }).loop.run();
  if (green.status !== 'ship' || green.ok !== true) problems.push('green run did not ship: ' + green.status + '/' + green.reason);
  if (green.deliveryAdapter !== true) problems.push('deliveryAdapter not reported active');
  if (!green.delivery || green.delivery.status !== 'green' || !green.delivery.closure) problems.push('green publish outcome missing');
  const steps = green.delivery && Array.isArray(green.delivery.steps) ? green.delivery.steps.map((s) => s.name).join(',') : '';
  if (!steps.includes('subject-lint') || !steps.includes('ci-watch')) problems.push('publish steps missing: ' + steps);
  const ledger = fs.readFileSync(path.join(g.dir, '.gos', 'logs', 'auto-ledger.ndjson'), 'utf8');
  if (!ledger.includes('"kind":"closure"') || !ledger.includes('"555"')) problems.push('closure record not written to the ledger mirror');
  // red CI: pause awaiting disposition, never into N
  const w = mkWorld('red');
  store.create({ mode: 'on', rootDir: w.dir });
  store.saveProbeResult({ host: 'delivery', state: 'green', checkedAtIso: new Date().toISOString() }, w.dir);
  const pinned2 = delivery.captureBaseline({ rootDir: w.dir, gitRunner: w.gitRunner });
  if (!delivery.pinBaseline(pinned2.baseline, w.dir).ok) problems.push('baseline pin 2 failed');
  const red = await loop.createLoop({
    rootDir: w.dir, host: 'gos-fixture-host', env, maxIterations: 6,
    spawnRunner: w.spawnRunner, gitRunner: w.gitRunner,
    delivery: deliveryOpts(pinned2.baseline, async () => ({ state: 'red', runId: '999' })),
  }).loop.run();
  if (red.status !== 'paused' || red.reason !== 'red-run' || red.requiresDisposition !== true) problems.push('red CI did not hold: ' + red.status + '/' + red.reason);
  if (!red.breaker || red.breaker.consecutive !== 0) problems.push('red CI counted into N');
  if (!red.guidance || !String(red.guidance.what).includes('999')) problems.push('red-run guidance lacks the run id');
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
T14_OUT="$(node run-c14.cjs 2>&1 | tail -n 1)"
t104_eq "T5: publish leg at SHIP — green adapter publishes with a closure record; red CI pauses for disposition (never N)" "OK" "$T14_OUT"

# ------------------------------------------- mutation classification ------
# mutation classification: head drift from the spawn's own non-advancing
# commits is rc0-no-advance (counts into N, never an external-mutation
# pause); a stage identity move during the spawn window is an external
# mutation (pause with a report, never into N).
t104_case c15
t104_state THINK > .gos/state.json
cat > run-c15.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const problems = [];
const templateState = fs.readFileSync(path.join(process.cwd(), '.gos', 'state.json'), 'utf8');
function mkSub(name, startStage) {
  const dir = path.join(process.cwd(), name);
  fs.mkdirSync(path.join(dir, '.gos', 'logs'), { recursive: true });
  const base = JSON.parse(templateState);
  base.current_stage = startStage;
  fs.writeFileSync(path.join(dir, '.gos', 'state.json'), JSON.stringify(base));
  spawnSync('git', ['init', '-q', '-b', 'work', '.'], { cwd: dir });
  spawnSync('git', ['commit', '--allow-empty', '-m', 'root'], { cwd: dir });
  return dir;
}
(async () => {
  const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
  // spawn-authored non-advance commit: rc0-no-advance into N (two spawns:
  // the first must not pause on its own head drift, the second trips N)
  const d1 = mkSub('d1', 'THINK');
  store.create({ mode: 'on', rootDir: d1, limits: { N: 2, K: 9, B: 9 } });
  const wipRunner = (spec) => {
    if (spec.roWorkspace) return { status: 0, stdout: 'REDTEAM-FINDINGS: 0\n', stderr: '' };
    spawnSync('git', ['commit', '--allow-empty', '-m', 'wip scratch work'], { cwd: d1 });
    return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
  };
  const r1 = await loop.createLoop({ rootDir: d1, host: 'gos-fixture-host', env, maxIterations: 5, spawnRunner: wipRunner }).loop.run();
  if (r1.reason === 'external-mutation' || r1.status !== 'paused' || r1.reason !== 'breaker-tripped' || !r1.trip || r1.trip.layer !== 'N') {
    problems.push('wip commit misrouted: ' + r1.status + '/' + r1.reason);
  }
  if (!r1.iterations.length || r1.iterations[0].signal !== 'rc0-no-advance' || r1.iterations[0].counted !== true) problems.push('rc0-no-advance not scored');
  // external stage change mid-window: pause with a report, never into N
  const d2 = mkSub('d2', 'PLAN');
  store.create({ mode: 'on', rootDir: d2, limits: { N: 3, K: 9, B: 9 } });
  const d2State = path.join(d2, '.gos', 'state.json');
  let reads = 0;
  const stateReader = () => {
    reads += 1;
    const raw = JSON.parse(fs.readFileSync(d2State, 'utf8'));
    if (reads >= 3) raw.current_stage = 'THINK';
    return raw;
  };
  const idleRunner = () => ({ status: 0, stdout: '{"type":"result"}\n', stderr: '' });
  const r2 = await loop.createLoop({ rootDir: d2, host: 'gos-fixture-host', env, maxIterations: 5, spawnRunner: idleRunner, stateReader }).loop.run();
  if (r2.status !== 'paused' || r2.reason !== 'external-mutation') problems.push('stage-back not paused: ' + r2.status + '/' + r2.reason);
  if (!String(r2.detail || '').includes('stage')) problems.push('stage-back report lacks the field');
  if (!r2.breaker || r2.breaker.consecutive !== 0) problems.push('stage-back counted into N');
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
T15C_OUT="$(node run-c15.cjs 2>&1 | tail -n 1)"
t104_eq "T13: spawn-authored non-advance counts into N; external stage change pauses with a report" "OK" "$T15C_OUT"

# ------------------------------------------- cli surface (C16) -------------
# CLI surface: the --allow-full gate, the --break-lock entry, unknown
# subcommands and timeout persistence. The capability-upgrade flag is the
# only surface that may unlock the full profile compose; the break-lock flag
# routes through the store's audited takeover path; timeout flags persist
# into the store and serve as loop defaults under the env overrides.
t104_case c16
t104_state THINK > .gos/state.json
node "$GOS" auto on --profile full --allow-full > t16f-on.txt 2>&1; C16_ONRC=$?
t104_exit "C16: auto on --profile full --allow-full succeeds" 0 "$C16_ONRC"
t104_contains "C16: status first line carries the allow-full indicator" "profile full · allow-full" "$(node "$GOS" auto status 2>&1 | head -n 1)"
T16F_AF="$(node -e "
const path=require('path');
const s=require(path.join(process.env.GOS_ROOT,'bin/lib/ops/auto/store.cjs'));
const r=s.load(process.cwd());
console.log(r.ok ? r.store.allowFull === true : 'load-failed');")"
t104_eq "C16: allowFull round-trips through the store" "true" "$T16F_AF"
T16F_COMP="$(node -e "
const path=require('path');
const l=require(path.join(process.env.GOS_ROOT,'bin/lib/ops/auto/launcher.cjs'));
const r=l.compose('full',{workspace:process.cwd()});
console.log(r.ok, r.code);")"
t104_eq "C16: profile full without --allow-full still fails compose at the gate" "false auto.launcher.full-flag-required" "$T16F_COMP"
T16F_OK="$(node -e "
const path=require('path');
const l=require(path.join(process.env.GOS_ROOT,'bin/lib/ops/auto/launcher.cjs'));
const r=l.compose('full',{workspace:process.cwd(),allowFull:true});
console.log(r.ok);")"
t104_eq "C16: the persisted allowFull gate unlocks the full profile compose" "true" "$T16F_OK"
node "$GOS" auto on --allow-full > t16f-no.txt 2>&1; C16_NO=$?
t104_exit "C16: --allow-full without profile full is refused" 1 "$C16_NO"
t104_contains "C16: refusal explains the flag scope" "--allow-full only applies to the full profile" "$(cat t16f-no.txt)"

# stale lock: --break-lock releases it (audited takeover), then the run ends
# cleanly at a SHIP-stage task before any host negotiation or spawn
t104_case c16b
t104_state SHIP > .gos/state.json
node "$GOS" auto on > /dev/null 2>&1
node -e "
const fs=require('fs');const path=require('path');const os=require('os');
const s=require(path.join(process.env.GOS_ROOT,'bin/lib/ops/auto/store.cjs'));
const now=new Date().toISOString();
const deadPid=(()=>{try{const mx=parseInt(fs.readFileSync('/proc/sys/kernel/pid_max','utf8'),10)||4194304;for(let p=mx-1;p>1;p--){try{process.kill(p,0);}catch(e){if(e.code==='ESRCH')return p;}}}catch(e){}return 999999;})();
fs.writeFileSync(path.join(s.storeRoot(process.cwd()),'run.lock'),JSON.stringify({hostname:os.hostname(),pid:deadPid,boot_id:null,clone_path:process.cwd(),started_at:now,heartbeat_at:now}));
console.log('planted');" > /dev/null
node "$GOS" auto run --break-lock > t16b-run.txt 2>&1; C16B_RC=$?
t104_exit "C16: --break-lock releases a stale lock (run then ends at SHIP)" 0 "$C16B_RC"
t104_contains "C16: stale lock break is reported" "stale run lock broken (stale)" "$(cat t16b-run.txt)"
T16B_GONE="$(node -e "
const path=require('path');
const s=require(path.join(process.env.GOS_ROOT,'bin/lib/ops/auto/store.cjs'));
console.log(s.readRunLock(process.cwd()) === null);")"
t104_eq "C16: broken lock is gone after the run" "true" "$T16B_GONE"

# live holder: --break-lock refused with the audited takeover attempt
t104_case c16c
t104_state THINK > .gos/state.json
node "$GOS" auto on > /dev/null 2>&1
cat > t16c-child.cjs <<'EOF'
const path = require('path');
const store = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/store.cjs'));
const r = store.acquireRunLock({ rootDir: process.argv[2] });
if (!r.ok) { console.error('child acquire failed'); process.exit(1); }
console.log('READY');
setInterval(() => {}, 1000);
EOF
node t16c-child.cjs "$PWD" > t16c-ready.txt 2>&1 &
C16C_CHILD=$!
T104_PIDS="$T104_PIDS $C16C_CHILD"
for i in $(seq 1 50); do grep -q READY t16c-ready.txt 2>/dev/null && break; sleep 0.1; done
node "$GOS" auto run --break-lock > t16c-run.txt 2>&1; C16C_RC=$?
t104_exit "C16: --break-lock refused while the holder pid is alive" 1 "$C16C_RC"
t104_contains "C16: live-pid refusal names the holder" "pid $C16C_CHILD is alive" "$(cat t16c-run.txt)"
kill "$C16C_CHILD" 2>/dev/null
T104_PIDS=""

# unknown subcommand exits non-zero after printing usage
t104_case c16d
t104_state THINK > .gos/state.json
node "$GOS" auto xyz > t16d-usage.txt 2>&1; C16D_RC=$?
t104_exit "C16: unknown auto subcommand exits non-zero" 1 "$C16D_RC"
t104_contains "C16: unknown subcommand prints the usage line" "Usage:" "$(cat t16d-usage.txt)"

# timeout flags persist into the store and serve as loop defaults; env wins
t104_case c16e
t104_state THINK > .gos/state.json
node "$GOS" auto on --timeout-wall 120 --timeout-idle 30 > /dev/null 2>&1; C16E_ON=$?
t104_exit "C16: auto on --timeout-wall/--timeout-idle succeeds" 0 "$C16E_ON"
T16E_STORE="$(node -e "
const path=require('path');
const s=require(path.join(process.env.GOS_ROOT,'bin/lib/ops/auto/store.cjs'));
const r=s.load(process.cwd());
console.log(r.ok ? r.store.timeouts.wallSec + '/' + r.store.timeouts.idleSec : 'load-failed');")"
t104_eq "C16: timeout flags persist into the store config" "120/30" "$T16E_STORE"
cat > run-c16e.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const rootDir = process.cwd();
const captured = [];
const spawnRunner = (spec, ctx) => { captured.push(ctx.wallMs); return { status: 1, stdout: '', stderr: 'fixture host broke' }; };
const baseEnv = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
delete baseEnv.GOS_AUTO_TIMEOUT_WALL_SEC;
delete baseEnv.GOS_AUTO_TIMEOUT_IDLE_SEC;
(async () => {
  await loop.createLoop({ rootDir, host: 'gos-fixture-host', env: baseEnv, limits: { N: 1, K: 9, B: 9 }, spawnRunner }).loop.run();
  const envWin = { ...baseEnv, GOS_AUTO_TIMEOUT_WALL_SEC: '5' };
  await loop.createLoop({ rootDir, host: 'gos-fixture-host', env: envWin, limits: { N: 1, K: 9, B: 9 }, spawnRunner }).loop.run();
  console.log('WALL ' + captured.join(','));
})().catch((e) => { console.error(e); process.exit(1); });
EOF
T16E_LOOP="$(node run-c16e.cjs 2>&1 | grep '^WALL ' | cut -d' ' -f2-)"
t104_eq "C16: loop resolves store timeouts as defaults; the env override still wins" "120000,5000" "$T16E_LOOP"

# A spawn-attributed advance may settle in the state file one read after
# its git commit: the post-spawn snapshot still shows the old stage while
# the next top-of-loop read shows the new one. The only-moved-field-is-
# stage delta rebases the baseline; anything else still pauses.
t104_case c17
mkdir -p .gos/task/p0 .gos/logs
printf '# Spec\n\np0 auto spec\n' > .gos/task/p0/spec.md
t104_state THINK 3 ',"spec_path":".gos/task/p0/spec.md"' > .gos/state.json
cat > run-c17.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const problems = [];
const world = process.cwd();
store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
function snapshotState() {
  try { return JSON.parse(fs.readFileSync(path.join(world, '.gos', 'state.json'), 'utf8')); } catch { return null; }
}
(async () => {
  let servedStale = false;
  const stateReader = () => {
    let raw = null;
    try { raw = JSON.parse(fs.readFileSync(path.join(world, '.gos', 'state.json'), 'utf8')); } catch { return null; }
    if (!servedStale && String(raw.current_stage) === 'BUILD') {
      servedStale = true;
      return { ...raw, current_stage: 'THINK' };
    }
    return raw;
  };
  const spawnRunner = (spec) => {
    if (spec.roWorkspace) return { status: 0, stdout: 'REDTEAM-FINDINGS: 0\n', stderr: '' };
    spawnSync(process.execPath, [path.join(GR, 'bin', 'gos.cjs'), 'commit', 'think'], {
      cwd: world, env: { ...process.env, GOS_AUTO_SPAWNED: '1' }, encoding: 'utf8',
    });
    return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
  };
  const r = await loop.createLoop({ rootDir: world, host: 'gos-fixture-host', env: { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' }, maxIterations: 2, spawnRunner, stateReader }).loop.run();
  if (r.reason === 'external-mutation') problems.push('late-settling advance paused the loop: ' + String(r.detail).slice(0, 80));
  if (r.status === 'paused') problems.push('unexpected pause: ' + r.status + '/' + r.reason);
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C17_OUT="$(node run-c17.cjs 2>&1 | tail -n 1)"
t104_eq "late-settling spawn advance rebases the baseline instead of pausing" "OK" "$C17_OUT"

# Crash-safe delegation: a runner that died between a delegated advance and
# its ratification leaves an orphaned PENDING. A fresh loop recovers the leg
# from the store stamp, runs the red-team double-zero and ratifies before
# any new spawn — without it, the next stage advance would block forever.
t104_case c18
mkdir -p .gos/task/p0 .gos/logs
printf '# Spec\n\np0 auto spec\n' > .gos/task/p0/spec.md
t104_state THINK 3 ',"spec_path":".gos/task/p0/spec.md","approvals":{"THINK":{"status":"PENDING","ts":"2026-01-01T00:00:00.000Z","mode":"auto","stage":"THINK"}}' > .gos/state.json
cat > run-c18.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const GR = process.env.GOS_ROOT;
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const problems = [];
const world = process.cwd();
store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
const sha = crypto.createHash('sha256').update('orphan stream').digest('hex');
store.stampStream('legacy-run-1', 'THINK', sha, '2026-01-01T00:00:00.000Z', world);
// a previous recovery attempt already stamped its (verdict-less) rounds —
// retry round ids must not collide with those streams
const staleSha = crypto.createHash('sha256').update('stale round').digest('hex');
store.stampStream('legacy-run-1-rt1', 'THINK', staleSha, '2026-01-01T00:01:00.000Z', world);
store.stampStream('legacy-run-1-rt2', 'THINK', staleSha, '2026-01-01T00:02:00.000Z', world);
const spawnRunner = (spec) => {
  if (spec.roWorkspace) return { status: 0, stdout: 'REDTEAM-FINDINGS: 0\n', stderr: '' };
  problems.push('unexpected working spawn before orphan legs completed');
  return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
};
(async () => {
  const r = await loop.createLoop({ rootDir: world, host: 'gos-fixture-host', env: { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' }, maxIterations: 1, spawnRunner }).loop.run();
  if (r.reason === 'orphan-pending-unrecoverable') problems.push('stamp present but orphan declared unrecoverable');
  const st = JSON.parse(fs.readFileSync(path.join(world, '.gos', 'state.json'), 'utf8'));
  const aT = (st.approvals || {}).THINK || {};
  if (aT.status !== 'ratified') problems.push('orphan PENDING not ratified: ' + JSON.stringify(aT.status));
  if (r.status === 'paused' && r.reason !== 'iteration-cap') problems.push('paused: ' + r.reason);
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C18_OUT="$(node run-c18.cjs 2>&1 | tail -n 1)"
t104_eq "orphaned PENDING is recovered from the store stamp and ratified at loop start" "OK" "$C18_OUT"

echo "--- T104 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
