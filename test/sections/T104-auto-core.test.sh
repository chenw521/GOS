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
#   dispatch case: per-stage composition is table-driven — THINK restricted
#           with four-verb grants and no model argv under inherit, BUILD
#           workspace with git identity, five-verb grants, kernel tier and a
#           resolved --model pin (c19); unknown stages and mid-run table
#           flips pause as external-mutation before the next consume (c22);
#           telemetry stamps carry the advisory self-report fields (c23);
#           script-stage VERIFY never probes the host and advances through
#           the runner-driven commit channel (c24)
#   status surfaces case: auto status prints the per-stage dispatch
#           view (worker form, profile, model slot, verb grants, cap, unit;
#           BUILD adds wave-dispatch) read-only and failure-tolerant, the
#           counters line format stays stable (c25); status/resume/SHIP
#           ledger render the three-tier clearance vocabulary with the
#           store-verified vs pre-loop-legacy distinction (c26); the nav
#           hint provider returns the kind-discriminated shape with
#           sanitized trip details (c27); an ANSI-laden deny trip renders
#           stripped and spawn-marked (c28); README and gos-verify carry
#           the mechanical-clearance wording and the script-worker note (c29)
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
# Channel setup mirrors the real runner: this bash process holds the lock
# (the CLI child descends from it) and the spawn is registered for THINK.
node -e "
const sr = require(process.env.GOS_ROOT + '/bin/lib/core/spawnreg.cjs');
const fs = require('fs');
fs.writeFileSync('.gos/.lock', JSON.stringify({pid: process.ppid, started_at: new Date().toISOString(), boot_id: null, starttime: sr.procStartTime(process.ppid)}));
sr.writeEntry(process.cwd(), {spawnId: 't3', kind: 'work', stage: 'THINK', pid: process.ppid, wallMs: 600000});
"
T3_BASE="$(node -e "console.log(require('crypto').createHash('sha256').update('{}').digest('hex'))")" # runner-passed approvals baseline (empty map)
GOS_AUTO_SPAWNED=1 GOS_AUTO_SPAWN_ID=t3 GOS_AUTO_APPROVALS_BASELINE="$T3_BASE" node "$GOS" commit think > t3-pending.txt 2>&1; T3_PRC=$?
rm -f .gos/.lock   # the runner releases between spawns — later probes must meet the PENDING boundary, not the lock
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
if (ok.stored.mode !== 'auto' || ok.stored.status !== 'cleared') problems.push('ratified record mode/status');
if (ratify.advanceBlocker({ THINK: ok.stored })) problems.push('ratified still blocks');
if (!ratify.advanceBlocker({ THINK: ratify.recordPending({ stage: 'THINK' }).approval })) problems.push('PENDING does not block');
{
  const cStream = '{"type":"message","text":"classification probe"}\n';
  const cSha = crypto.createHash('sha256').update(cStream).digest('hex');
  const cSt = store.stampStream('spawn-t3c', 'THINK', cSha, new Date().toISOString(), rootDir, { denyHits: 3, denyCommandHits: 1 });
  if (!cSt.ok || cSt.stamp.denyCommandHits !== 1) problems.push('stamp drops denyCommandHits: ' + JSON.stringify(cSt.stamp));
}
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
# runner legs end to end over the dispatch table: the fake host runs the REAL
# in-spawn commit for the delegated stages (PENDING recorded by the commit
# gate), red-team rounds answer findings=0 twice, and the loop ratifies from
# the store stamp before the next stage spawn proceeds. BUILD runs the wave
# driver over the frozen two-wave snapshot (one commit per wave touching only
# declared files) and exits through one final advance spawn running the real
# `gos commit build`; VERIFY runs as a script stage (pinned legs + a Class S
# sections spawn, never a model spawn) and its advance is runner-driven.
t104_case c13
mkdir -p .gos/task/p0
printf '# Spec\n\np0 auto spec\n' > .gos/task/p0/spec.md
PLAN_W1='### Wave 1'
PLAN_W2='### Wave 2'
cat > .gos/task/p0/plan.md <<PLAN
# Plan

${PLAN_W1}

#### T13a: first fixture wave
**Files**: src/w1.txt

${PLAN_W2}

#### T13b: second fixture wave
**Files**: src/w2.txt
PLAN
t104_state THINK 3 ',"spec_path":".gos/task/p0/spec.md","plan_path":".gos/task/p0/plan.md","semantic":{"allowlist":["run-c13.cjs"]}' > .gos/state.json
node -e "const fs=require('fs');const p='.gos/state.json';const st=JSON.parse(fs.readFileSync(p,'utf8'));const {execSync}=require('child_process');st.task_head=execSync('git rev-parse HEAD').toString().trim();fs.writeFileSync(p,JSON.stringify(st,null,2));"
export GOS_AUTO_TIMEOUT_WALL_SEC=5 GOS_AUTO_TIMEOUT_IDLE_SEC=2
cat > run-c13.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const problems = [];
const stateFile = path.join(rootDir, '.gos', 'state.json');
const NEXT = { REVIEW: 'VERIFY', VERIFY: 'SHIP' };
const sha = (t) => crypto.createHash('sha256').update(t, 'utf8').digest('hex');
function readState() { return JSON.parse(fs.readFileSync(stateFile, 'utf8')); }
function setStage(s) { const st = readState(); st.current_stage = s; fs.writeFileSync(stateFile, JSON.stringify(st, null, 2)); }
function gosCommit(stage, specEnv) {
  const sr = require(path.join(GR, 'bin/lib/core/spawnreg.cjs'));
  fs.writeFileSync(path.join(rootDir, '.gos', '.lock'), JSON.stringify({ pid: process.pid, started_at: new Date().toISOString(), boot_id: null, starttime: sr.procStartTime(process.pid) }));
  const childEnv = { ...process.env, GOS_AUTO_SPAWNED: '1', GOS_AUTO_SPAWN_ID: specEnv.GOS_AUTO_SPAWN_ID, GOS_AUTO_APPROVALS_BASELINE: specEnv.GOS_AUTO_APPROVALS_BASELINE };
  if (specEnv.GOS_AUTO_DIRTY_BASELINE) childEnv.GOS_AUTO_DIRTY_BASELINE = specEnv.GOS_AUTO_DIRTY_BASELINE;
  const r = spawnSync(process.execPath, [path.join(GR, 'bin', 'gos.cjs'), 'commit', stage], { cwd: rootDir, env: childEnv, encoding: 'utf8' });
  try { fs.unlinkSync(path.join(rootDir, '.gos', '.lock')); } catch { /* gone */ }
  return r;
}
const seen = [];
const spawnRunner = (spec) => {
  seen.push(spec);
  if (spec.roWorkspace) return { status: 0, stdout: 'independent review\nREDTEAM-FINDINGS: 0\n', stderr: '' };
  if (spec.kind === 'script') return { status: 0, stdout: 'sections pass\n', stderr: '' };
  if (Number.isInteger(spec.wave)) {
    for (const p of spec.declaredFiles) {
      const abs = path.join(rootDir, p);
      fs.mkdirSync(path.dirname(abs), { recursive: true });
      fs.writeFileSync(abs, `wave ${spec.wave} content\n`);
    }
    spawnSync('git', ['add', ...spec.declaredFiles], { cwd: rootDir });
    spawnSync('git', ['commit', '-q', '-m', `wave ${spec.wave} work`], { cwd: rootDir });
    return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
  }
  if (spec.stageExit) {
    const r = gosCommit('build', spec.env);
    if (r.status !== 0) problems.push(`advance build rc=${r.status}: ${String(r.stderr || r.stdout).slice(0, 300)}`);
    return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
  }
  if (spec.stage === 'THINK' || spec.stage === 'PLAN') {
    const want = sha(JSON.stringify((readState().approvals) || {}));
    if (spec.env.GOS_AUTO_APPROVALS_BASELINE !== want) problems.push(`${spec.stage} spawn env approvals baseline mismatch`);
    const r = gosCommit(spec.stage.toLowerCase(), spec.env);
    if (r.status !== 0) problems.push(`in-spawn commit ${spec.stage} rc=${r.status}: ${String(r.stderr || r.stdout).slice(0, 200)}`);
    return { status: 0, stdout: '{"type":"message","text":"stage work done"}\n{"type":"result"}\n', stderr: '' };
  }
  spawnSync('git', ['commit', '--allow-empty', '-m', `chore(task): advance ${spec.stage.toLowerCase()}`], { cwd: rootDir });
  setStage(NEXT[spec.stage]);
  return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
};
(async () => {
  store.create({ mode: 'on', rootDir, limits: { N: 3, K: 9, B: 60 } });
  const r = await loop.createLoop({
    rootDir, host: 'gos-fixture-host', env, maxIterations: 9, spawnRunner,
    engineProbe: () => ({ engine: 'bwrap', version: '0.11.0' }),
    legRunner: () => ({ ok: true, verdict: { ok: true, failures: [] } }),
  }).loop.run();
  if (r.status !== 'ship' || r.ok !== true) problems.push('loop did not ship: ' + r.status + '/' + r.reason + (r.detail ? ':' + String(r.detail).slice(0, 160) : ''));
  const st = readState();
  const aT = (st.approvals || {}).THINK || {};
  const aP = (st.approvals || {}).PLAN || {};
  if (aT.status !== 'cleared' || aT.mode !== 'auto') problems.push('THINK not ratified: ' + JSON.stringify(aT));
  if (aP.status !== 'cleared' || aP.mode !== 'auto') problems.push('PLAN not ratified: ' + JSON.stringify(aP));
  const thinkIter = (r.iterations || []).find((i) => i.stage === 'THINK');
  if (!thinkIter) problems.push('no THINK iteration recorded');
  else {
    const dl = thinkIter.delegation;
    if (!dl || !dl.redteam || dl.redteam.rounds !== 2 || dl.redteam.zeros !== 2) problems.push('THINK red-team leg summary missing');
    if (aT.evidence && aT.evidence.spawnId !== thinkIter.spawnId) problems.push('evidence does not pair the stage spawn');
  }
  // BUILD: two waves released through the driver + one advance spawn
  const waveRecs = store.readWaveRecords(rootDir);
  const waveKeys = Object.keys(waveRecs.waves || {}).filter((k) => /\/W[12]$/.test(k));
  if (waveKeys.length !== 2) problems.push('wave completion records missing: ' + JSON.stringify(Object.keys(waveRecs.waves || {})));
  const waveSpecs = seen.filter((s) => Number.isInteger(s.wave));
  if (waveSpecs.length !== 2) problems.push('wave spawn count ' + waveSpecs.length + ' != 2');
  for (const ws of waveSpecs) {
    if (!/^GOS auto BUILD wave \d+ — tasks T13[ab]\.$/.test(String(ws.prompt || '').split('\n')[0])) problems.push('wave prompt is not the pointer-only render');
    if (!ws.env.GOS_AUTO_APPROVALS_BASELINE) problems.push('wave spawn lacks the approvals baseline env');
  }
  const buildIter = (r.iterations || []).find((i) => i.stage === 'BUILD');
  if (!buildIter || buildIter.signal !== 'advanced') problems.push('BUILD advance spawn missing or not advanced: ' + JSON.stringify(buildIter && buildIter.signal));
  if (buildIter && (!Array.isArray(buildIter.waves) || buildIter.waves.some((w) => w.status !== 'released'))) problems.push('BUILD iteration lacks the released-wave summary');
  // VERIFY: script spawns only, never a model spawn
  if (seen.some((s) => s.stage === 'VERIFY' && s.kind !== 'script' && !Number.isInteger(s.wave))) problems.push('VERIFY composed a model spawn');
  if (!seen.some((s) => s.kind === 'script')) problems.push('VERIFY sections step never composed a script spawn');
  const s = store.load(rootDir);
  const stampKeys = s.ok && store.isPlainObject(s.store.stamps) ? Object.keys(s.store.stamps) : [];
  const roundStage = (prefix) => {
    const key = stampKeys.find((k) => k === prefix || k.startsWith(prefix + '-'));
    return key ? s.store.stamps[key].stage : null;
  };
  if (roundStage(`${thinkIter.spawnId}-rt1`) !== 'redteam' || roundStage(`${thinkIter.spawnId}-rt2`) !== 'redteam') problems.push('red-team rounds not stamped under the redteam stage');
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
    const sr = require(path.join(GR, 'bin/lib/core/spawnreg.cjs'));
    fs.writeFileSync(path.join(dir, '.gos', '.lock'), JSON.stringify({ pid: process.pid, started_at: new Date().toISOString(), boot_id: null, starttime: sr.procStartTime(process.pid) }));
    sr.writeEntry(dir, { spawnId: spec.spawnId, kind: 'work', stage: 'THINK', pid: process.pid, wallMs: 600000 });
    const approvalsNow = (JSON.parse(fs.readFileSync(path.join(dir, '.gos', 'state.json'), 'utf8')).approvals) || {};
    const r = spawnSync(process.execPath, [path.join(GR, 'bin', 'gos.cjs'), 'commit', 'think'], {
      cwd: dir, env: { ...process.env, GOS_AUTO_SPAWNED: '1', GOS_AUTO_SPAWN_ID: spec.spawnId, GOS_AUTO_APPROVALS_BASELINE: require('crypto').createHash('sha256').update(JSON.stringify(approvalsNow)).digest('hex') }, encoding: 'utf8',
    });
    try { fs.unlinkSync(path.join(dir, '.gos', '.lock')); } catch { /* gone */ }
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
# publish leg at SHIP: entering at VERIFY (a script stage — pinned gate and
# truth legs plus a Class S sections spawn, never a model spawn) the loop
# advances through the runner-driven commit channel, reaches SHIP and, with a
# green fixture delivery adapter (probe state in the store), invokes publish
# (push -> PR -> subject lint -> squash merge -> CI watch); the closure record
# lands in the repo ledger mirror. A red CI run pauses the loop awaiting a
# human disposition (never N). With no adapter the loop still ends cleanly at
# SHIP (covered by C1).
t104_case c14
git remote add origin https://github.com/octocat/widget.git
mkdir -p .gos/task/p0
printf '# Spec\n\np0 auto spec\n' > .gos/task/p0/spec.md
t104_state VERIFY 3 ',"spec_path":".gos/task/p0/spec.md","semantic":{"allowlist":["run-c14.cjs"]}' > .gos/state.json
node -e "const fs=require('fs');const p='.gos/state.json';const st=JSON.parse(fs.readFileSync(p,'utf8'));const {execSync}=require('child_process');st.task_head=execSync('git rev-parse HEAD').toString().trim();fs.writeFileSync(p,JSON.stringify(st,null,2));"
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
function mkWorld(name) {
  const dir = path.join(process.cwd(), name);
  fs.mkdirSync(path.join(dir, '.gos', 'task', 'p0'), { recursive: true });
  fs.mkdirSync(path.join(dir, '.gos', 'logs'), { recursive: true });
  fs.copyFileSync(path.join(process.cwd(), '.gos', 'task', 'p0', 'spec.md'), path.join(dir, '.gos', 'task', 'p0', 'spec.md'));
  fs.writeFileSync(path.join(dir, '.gos', 'state.json'), JSON.stringify(templateState));
  spawnSync('git', ['init', '-q', '-b', 'work', '.'], { cwd: dir });
  spawnSync('git', ['remote', 'add', 'origin', 'https://github.com/octocat/widget.git'], { cwd: dir });
  spawnSync('git', ['commit', '-q', '--allow-empty', '-m', 'root'], { cwd: dir });
  const spawnRunner = (spec) => {
    if (spec.kind === 'script') return { status: 0, stdout: 'sections pass\n', stderr: '' };
    problems.push('unexpected non-script spawn at VERIFY: ' + JSON.stringify(spec.stage));
    return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
  };
  const gitRunner = (args) => (args[0] === 'ls-remote'
    ? { status: 0, stdout: 'f'.repeat(40) + '\tHEAD\n', stderr: '' }
    : spawnSync('git', args, { cwd: dir, encoding: 'utf8' }));
  return { dir, gitRunner, spawnRunner };
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
  const loopOpts = (dir, spawnRunner, gitRunner) => ({
    rootDir: dir, host: 'gos-fixture-host', env, maxIterations: 6,
    spawnRunner, gitRunner,
    engineProbe: () => ({ engine: 'bwrap', version: '0.11.0' }),
    legRunner: () => ({ ok: true, verdict: { ok: true, failures: [] } }),
  });
  // green CI: VERIFY advances runner-side, publish completes, closure written
  const g = mkWorld('green');
  store.create({ mode: 'on', rootDir: g.dir });
  store.saveProbeResult({ host: 'delivery', state: 'green', checkedAtIso: new Date().toISOString() }, g.dir);
  const pinned = delivery.captureBaseline({ rootDir: g.dir, gitRunner: g.gitRunner });
  if (!pinned.ok) throw new Error('baseline capture failed: ' + pinned.reason);
  if (!delivery.pinBaseline(pinned.baseline, g.dir).ok) problems.push('baseline pin failed');
  const green = await loop.createLoop({
    ...loopOpts(g.dir, g.spawnRunner, g.gitRunner),
    delivery: deliveryOpts(pinned.baseline, async () => ({ state: 'green', runId: '555' })),
  }).loop.run();
  if (green.status !== 'ship' || green.ok !== true) problems.push('green run did not ship: ' + green.status + '/' + green.reason + (green.detail ? ':' + String(green.detail).slice(0, 160) : ''));
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
    ...loopOpts(w.dir, w.spawnRunner, w.gitRunner),
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
    const sr = require(path.join(GR, 'bin/lib/core/spawnreg.cjs'));
    fs.writeFileSync(path.join(world, '.gos', '.lock'), JSON.stringify({ pid: process.pid, started_at: new Date().toISOString(), boot_id: null, starttime: sr.procStartTime(process.pid) }));
    sr.writeEntry(world, { spawnId: spec.spawnId, kind: 'work', stage: 'THINK', pid: process.pid, wallMs: 600000 });
    const approvalsNow = (JSON.parse(fs.readFileSync(path.join(world, '.gos', 'state.json'), 'utf8')).approvals) || {};
    spawnSync(process.execPath, [path.join(GR, 'bin', 'gos.cjs'), 'commit', 'think'], {
      cwd: world, env: { ...process.env, GOS_AUTO_SPAWNED: '1', GOS_AUTO_SPAWN_ID: spec.spawnId, GOS_AUTO_APPROVALS_BASELINE: require('crypto').createHash('sha256').update(JSON.stringify(approvalsNow)).digest('hex') }, encoding: 'utf8',
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
  if (aT.status !== 'cleared') problems.push('orphan PENDING not ratified: ' + JSON.stringify(aT.status));
  if (r.status === 'paused' && r.reason !== 'iteration-cap') problems.push('paused: ' + r.reason);
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C18_OUT="$(node run-c18.cjs 2>&1 | tail -n 1)"
t104_eq "orphaned PENDING is recovered from the store stamp and ratified at loop start" "OK" "$C18_OUT"

# Dispatch-table compose shapes: per-stage composition is entry-driven —
# THINK pins restricted (no rw repo bind, four-verb grants, cap 16, no --model
# argv while the slot resolves to inherit) while BUILD pins workspace (repo
# root rw at the kernel tier, runner git identity, five-verb grants incl.
# checkpoint at cap 64, --model argv when the slot resolves, scratch +
# testbed + grant manifest equipage) and exits through one stage-exit spawn
# after the waves release.
t104_case c19
mkdir -p .gos/task/p0 .gos/logs
PLAN_W1='### Wave 1'
PLAN_W2='### Wave 2'
cat > .gos/task/p0/plan.md <<PLAN
# Plan

${PLAN_W1}

#### T19a: fixture wave one
**Files**: src/w1.txt

${PLAN_W2}

#### T19b: fixture wave two
**Files**: src/w2.txt
PLAN
cat > run-c19.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const spawnreg = require(path.join(GR, 'bin/lib/core/spawnreg.cjs'));
const crypto = require('crypto');
const problems = [];
const world = process.cwd();
const snapshot = {
  tasks: [
    { id: 'T19a', covers: [], files: ['src/w1.txt'], wave: 1 },
    { id: 'T19b', covers: [], files: ['src/w2.txt'], wave: 2 },
  ],
  audit: [],
  meta: { waveValidation: { ok: true, waves: 2 } },
};
const baseState = { schema_version: 6, level: 3, current_stage: 'THINK', completed_stages: ['INTENT'], intent: { summary: 'c19', confirmed: true }, task_head: 'abc123def0123456789abcdef0123456789abcdef', spec_path: '.gos/task/p0/spec.md', plan_path: '.gos/task/p0/plan.md', requirements: [], decisions: [], observable_truths: [], gaps: [], checkpoints: [], approvals: {} };
fs.writeFileSync(path.join(world, '.gos', 'task', 'p0', 'spec.md'), '# Spec\n\nc19 spec\n');
function writeState(stage) {
  const st = { ...baseState, current_stage: stage, plan_snapshot: snapshot };
  fs.writeFileSync(path.join(world, '.gos', 'state.json'), JSON.stringify(st, null, 2));
}
store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 60 } });
const seen = [];
const liveReg = [];
const spawnRunner = (spec) => {
  seen.push(spec);
  const ent = spawnreg.readEntry(world, spec.spawnId);
  let m = null;
  try { m = JSON.parse(fs.readFileSync(spawnreg.manifestPath(world, spec.spawnId), 'utf8')); } catch { /* no manifest on this shape */ }
  liveReg.push({ stage: spec.stage, wave: spec.wave, stageExit: spec.stageExit === true, entry: ent, manifest: m });
  if (Number.isInteger(spec.wave)) {
    fs.mkdirSync(path.join(spec.scratch, 'testbed'), { recursive: true });
    fs.writeFileSync(path.join(spec.scratch, 'noop'), 'fixture no-op wave\n');
    return { status: 0, stdout: 'noop wave\n', stderr: '' };
  }
  if (spec.stageExit) {
    spawnSync('git', ['commit', '--allow-empty', '-m', 'chore(task): advance build'], { cwd: world });
    const st = JSON.parse(fs.readFileSync(path.join(world, '.gos', 'state.json'), 'utf8'));
    st.current_stage = 'REVIEW';
    fs.writeFileSync(path.join(world, '.gos', 'state.json'), JSON.stringify(st, null, 2));
    return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
  }
  return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
};
const argvHas = (argv, ...toks) => { const i = argv.findIndex((_, k) => toks.every((t, j) => argv[k + j] === t)); return i >= 0; };
(async () => {
  const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
  const probe = () => ({ engine: 'bwrap', version: '0.11.0' });
  const stateOf = () => JSON.parse(fs.readFileSync(path.join(world, '.gos', 'state.json'), 'utf8'));
  // THINK: restricted + four-verb grants + inherit (no --model argv)
  writeState('THINK');
  seen.length = 0;
  await loop.createLoop({ rootDir: world, host: 'gos-fixture-host', env, maxIterations: 1, spawnRunner, stateReader: stateOf }).loop.run();
  const think = seen.find((s) => s.stage === 'THINK' && !s.roWorkspace);
  if (!think) problems.push('no THINK spawn composed');
  else {
    if (think.profile !== 'restricted') problems.push('THINK compose profile not the table pin: ' + think.profile);
    if (argvHas(think.argv, '--model')) problems.push('THINK spawn pinned a --model argv while the slot resolves inherit');
    const regT = liveReg.find((r) => r.stage === 'THINK');
    const grantsT = regT && regT.entry && regT.entry.grants;
    if (JSON.stringify(grantsT) !== JSON.stringify(['commit', 'gate', 'section', 'truth'])) problems.push('THINK grants not the four-verb entry set: ' + JSON.stringify(grantsT));
    if (regT && regT.entry && regT.entry.use_cap !== 16) problems.push('THINK use_cap not 16');
    if (think.tier === 'bubblewrap' && argvHas(think.argv, '--bind', world, world)) problems.push('THINK compose bound the repo root writable');
    if (think.env.GIT_AUTHOR_NAME === 'gos-auto') problems.push('THINK compose carries the BUILD runner identity');
    const wantBase = crypto.createHash('sha256').update('{}').digest('hex');
    if (think.env.GOS_AUTO_APPROVALS_BASELINE !== wantBase) problems.push('THINK spawn env lacks the approvals baseline');
  }
  // BUILD: workspace + identity + five-verb grants + kernel tier + model pin
  writeState('BUILD');
  seen.length = 0;
  await loop.createLoop({ rootDir: world, host: 'gos-fixture-host', env, maxIterations: 1, spawnRunner, engineProbe: probe, modelResolver: () => ({ model: 'zai/glm-mini' }), stateReader: stateOf }).loop.run();
  const adv = seen.find((s) => s.stageExit === true);
  if (!adv) problems.push('no BUILD stage-exit spawn composed');
  else {
    if (adv.profile !== 'workspace') problems.push('BUILD compose profile not the table pin: ' + adv.profile);
    if (adv.tier !== 'bubblewrap') problems.push('BUILD compose not kernel tier');
    if (!argvHas(adv.argv, '--bind', world, world)) problems.push('workspace compose did not bind the repo root read-write');
    if (!argvHas(adv.argv, '--model', 'zai/glm-mini')) problems.push('BUILD spawn lacks the resolved --model argv');
    if (adv.env.GIT_AUTHOR_NAME !== 'gos-auto' || adv.env.GIT_COMMITTER_EMAIL !== 'gos-auto@invalid') problems.push('BUILD spawn lacks the runner git identity');
    if (adv.env.TESTBASE !== path.join(adv.scratch, 'testbed')) problems.push('BUILD spawn lacks the testbed env pin');
    if (adv.env.GOS_AUTO_GRANT_MANIFEST !== '/run/gos-grants.json') problems.push('BUILD spawn lacks the grant manifest env');
    const regB = liveReg.find((r) => r.stageExit);
    if (!regB || !regB.manifest || !regB.manifest.grants.includes('checkpoint') || regB.manifest.use_cap !== 64) problems.push('BUILD grants not the entry five-verb/cap-64 set: ' + JSON.stringify(regB && regB.manifest));
    if (!regB || !regB.entry || regB.entry.use_cap !== 64) problems.push('BUILD registration cap not 64');
  }
  const st = store.load(world);
  if (st.ok) {
    const pinnedStamps = Object.values(st.store.stamps).filter((v) => v && v.stage === 'BUILD' && v.modelPinned);
    if (pinnedStamps.length !== 1 || pinnedStamps[0].modelPinned !== 'zai/glm-mini') problems.push('BUILD stamp lacks the pinned-model telemetry: ' + JSON.stringify(pinnedStamps.map((v) => v.modelPinned)));
  }
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C19_OUT="$(node run-c19.cjs 2>&1 | tail -n 1)"
t104_eq "workspace-writing profiles grant the repo root; restricted never does" "OK" "$C19_OUT"

# Spawn baseline guard: files already uncommitted when the spawn started are
# never swept into the advance commit, with a loud exclusion line; the
# session's own new files still land.
t104_case c20
mkdir -p .gos/task/p0 .gos/logs test
printf '# Spec\n\np0 auto spec\n' > .gos/task/p0/spec.md
t104_state THINK 3 ',"spec_path":".gos/task/p0/spec.md"' > .gos/state.json
cat > run-c20.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const problems = [];
const world = process.cwd();
store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
// supervisor dirt: written after the case world settled, before the loop
fs.writeFileSync(path.join(world, 'test', 'supervisor-scratch.txt'), 'supervisor scratch\n');
const spawnreg = require(path.join(GR, 'bin', 'lib', 'core', 'spawnreg.cjs'));
const spawnRunner = (spec) => {
  if (spec.roWorkspace) return { status: 0, stdout: 'REDTEAM-FINDINGS: 0\n', stderr: '' };
  if (!spec.env || !spec.env.GOS_AUTO_DIRTY_BASELINE) problems.push('spawn env lacks the dirty baseline');
  else if (!JSON.parse(spec.env.GOS_AUTO_DIRTY_BASELINE).includes('test/supervisor-scratch.txt')) problems.push('baseline missing the supervisor file');
  // Runner-side channel setup: the holder lock (this harness process) and
  // the registered spawn entry admit exactly one assigned advance.
  fs.writeFileSync(path.join(world, '.gos', '.lock'), JSON.stringify({ pid: process.pid, started_at: new Date().toISOString(), boot_id: null, starttime: spawnreg.procStartTime(process.pid) }));
  spawnreg.writeEntry(world, { spawnId: 'c20', kind: 'work', stage: 'THINK', pid: process.pid, wallMs: 600000 });
  fs.writeFileSync(path.join(world, 'test', 'session-work.txt'), 'session output\n');
  const r = spawnSync(process.execPath, [path.join(GR, 'bin', 'gos.cjs'), 'commit', 'think'], {
    cwd: world, env: { ...process.env, GOS_AUTO_SPAWNED: '1', GOS_AUTO_SPAWN_ID: 'c20', GOS_AUTO_DIRTY_BASELINE: spec.env.GOS_AUTO_DIRTY_BASELINE, GOS_AUTO_APPROVALS_BASELINE: require('crypto').createHash('sha256').update(JSON.stringify((JSON.parse(fs.readFileSync(path.join(world, '.gos', 'state.json'), 'utf8')).approvals) || {})).digest('hex') }, encoding: 'utf8',
  });
  const childAll = String(r.stdout || '').concat(r.stderr || '');
  if (!(childAll.includes('spawn baseline guard') && childAll.includes('test/supervisor-scratch.txt'))) problems.push('exclusion warning missing');
  return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
};
const stateReader = () => { try { return JSON.parse(fs.readFileSync(path.join(world, '.gos', 'state.json'), 'utf8')); } catch { return null; } };
(async () => {
  await loop.createLoop({ rootDir: world, host: 'gos-fixture-host', env: { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' }, maxIterations: 1, spawnRunner, stateReader }).loop.run();
  const show = spawnSync('git', ['show', '--name-only', '--format=', 'HEAD'], { cwd: world, encoding: 'utf8' });
  const committed = String(show.stdout || '');
  if (committed.includes('supervisor-scratch.txt')) problems.push('supervisor file swept into the advance commit');
  if (!committed.includes('test/session-work.txt')) problems.push('session file missing from the advance commit');
  const still = fs.existsSync(path.join(world, 'test', 'supervisor-scratch.txt'));
  if (!still) problems.push('supervisor file vanished');
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C20_OUT="$(node run-c20.cjs 2>&1 | tail -n 1)"
t104_eq "spawn baseline guard excludes supervisor dirt from advance commits" "OK" "$C20_OUT"

# Async spawn runner: idle kills a silent stream live, the wall clock kills a
# chatty one, and a healthy command resolves rc 0 — all with the event loop
# (and therefore the runner's heartbeats) alive.
t104_case c21
mkdir -p .gos/logs
cat > run-c21.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const problems = [];
(async () => {
  const t0 = Date.now();
  const idle = await loop.loopSpawnRunner({ argv: ['/bin/sh', '-c', 'sleep 30'], env: process.env, cwd: process.cwd() }, { wallMs: 25000, idleMs: 1000 });
  const idleMs = Date.now() - t0;
  if (!(idle.error && idle.error.idle === true && idle.error.killed === true)) problems.push('silent stream not idle-killed: ' + JSON.stringify(idle.error && idle.error.message));
  if (idleMs > 5000) problems.push('idle kill arrived late: ' + idleMs + 'ms');
  const t1 = Date.now();
  const wall = await loop.loopSpawnRunner({ argv: ['/bin/sh', '-c', 'while :; do echo tick; sleep 0.2; done'], env: process.env, cwd: process.cwd() }, { wallMs: 1500, idleMs: 10000 });
  const wallMs = Date.now() - t1;
  if (!(wall.error && wall.error.killed === true)) problems.push('chatty stream not wall-killed');
  if (wallMs > 4000) problems.push('wall kill arrived late: ' + wallMs + 'ms');
  if (!/tick/.test(String(wall.stdout || ''))) problems.push('stream chunks not captured');
  const okRun = await loop.loopSpawnRunner({ argv: ['/bin/sh', '-c', 'echo healthy'], env: process.env, cwd: process.cwd() }, { wallMs: 5000, idleMs: 2000 });
  if (okRun.status !== 0 || !String(okRun.stdout || '').includes('healthy')) problems.push('healthy run misresolved: ' + JSON.stringify(okRun.status));
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C21_OUT="$(node run-c21.cjs 2>&1 | tail -n 1)"
t104_eq "async spawn runner: live idle kill, live wall kill, healthy resolution" "OK" "$C21_OUT"

# Dispatch-table drift: an unknown stage key and a mid-run flip of the
# stamped table file both pause as external-mutation before the next consume
# (compose/grant registration read the table only under a matching stamp).
t104_case c22
t104_state FOO > .gos/state.json
cat > run-c22.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const problems = [];
const world = process.cwd();
(async () => {
  const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
  store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
  // unknown stage: the closed table is the vocabulary — a stage outside it
  // pauses as external-mutation, never as a spawn
  const r1 = await loop.createLoop({ rootDir: world, host: 'gos-fixture-host', env, spawnRunner: () => { problems.push('unknown stage spawned'); return { status: 0, stdout: '', stderr: '' }; } }).loop.run();
  if (r1.status !== 'paused' || r1.reason !== 'external-mutation' || !/stage/.test(String(r1.detail || ''))) {
    problems.push('unknown stage not an external-mutation pause: ' + r1.status + '/' + r1.reason);
  }
  // mid-run table flip: first THINK spawn advances, the file then drifts, the
  // next consume re-verifies the stamp and pauses before composing again
  const stateFile = path.join(world, '.gos', 'state.json');
  const setStage = (s) => { const st = JSON.parse(fs.readFileSync(stateFile, 'utf8')); st.current_stage = s; fs.writeFileSync(stateFile, JSON.stringify(st, null, 2)); };
  const tableCopy = path.join(world, 'fixture-dispatch.json');
  fs.copyFileSync(path.join(GR, 'templates', 'auto-dispatch.json'), tableCopy);
  const state2 = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
  state2.current_stage = 'THINK';
  fs.writeFileSync(stateFile, JSON.stringify(state2, null, 2));
  let spawns = 0;
  const spawnRunner = (spec) => {
    if (!spec.roWorkspace) spawns += 1;
    if (spec.roWorkspace) return { status: 0, stdout: 'REDTEAM-FINDINGS: 0\n', stderr: '' };
    if (spec.stage === 'THINK') {
      spawnSync('git', ['commit', '--allow-empty', '-m', 'chore(task): advance think'], { cwd: world });
      setStage('PLAN');
      const tbl = JSON.parse(fs.readFileSync(tableCopy, 'utf8'));
      tbl.stages.PLAN.use_cap = 8;
      fs.writeFileSync(tableCopy, JSON.stringify(tbl, null, 2) + '\n');
    }
    return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
  };
  const r2 = await loop.createLoop({ rootDir: world, host: 'gos-fixture-host', env, maxIterations: 5, spawnRunner, tablePath: tableCopy }).loop.run();
  if (r2.status !== 'paused' || r2.reason !== 'external-mutation' || !/dispatch table/i.test(String(r2.detail || ''))) {
    problems.push('mid-run table drift not an external-mutation pause: ' + r2.status + '/' + r2.reason + '/' + String(r2.detail || '').slice(0, 80));
  }
  if (spawns !== 1) problems.push('table drift pause did not freeze spawns (count ' + spawns + ')');
  const v = loop.verifyDispatchTableStamp(world, tableCopy);
  if (v.ok || v.reason !== 'dispatch-table-drift') problems.push('verify helper did not name the drift: ' + JSON.stringify(v.reason));
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C22_OUT="$(node run-c22.cjs 2>&1 | tail -n 1)"
t104_eq "dispatch-table integration: unknown stage and mid-run table drift pause as external-mutation before the next consume" "OK" "$C22_OUT"

# Telemetry stamps: at spawn exit the store v2 stamp carries the advisory fields —
# modelPinned from the entry resolution, modelObserved/commandCount from the
# adapter telemetry over the parsed stream, denyHits from the windows, and
# the head/tail window sidecars land with their hashes and byte total.
t104_case c23
t104_state THINK > .gos/state.json
cat > run-c23.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const problems = [];
const world = process.cwd();
const stateFile = path.join(world, '.gos', 'state.json');
const head = Buffer.from('{"type":"message","text":"hi","model":"glm-5.3"}\n');
const tail = Buffer.from('{"type":"tool_use","part":{"tool":"bash"}}\n{"type":"tool_use","part":{"tool":"read"}}\n{"type":"result"}\n');
(async () => {
  store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
  const spawnRunner = (spec) => {
    if (spec.roWorkspace) return { status: 0, stdout: 'REDTEAM-FINDINGS: 0\n', stderr: '' };
    spawnSync('git', ['commit', '--allow-empty', '-m', 'chore(task): advance think'], { cwd: world });
    const st = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
    st.current_stage = 'PLAN';
    fs.writeFileSync(stateFile, JSON.stringify(st, null, 2));
    return {
      status: 0, stdout: head.toString('utf8') + tail.toString('utf8'), stderr: '',
      preTruncationDenyHits: [],
      totalBytes: { stdout: head.length + tail.length, stderr: 0 },
      windowHead: { stdout: head, stderr: Buffer.alloc(0) },
      windowTail: { stdout: tail, stderr: Buffer.alloc(0) },
    };
  };
  const r = await loop.createLoop({
    rootDir: world, host: 'gos-fixture-host', env: { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' },
    maxIterations: 1, spawnRunner,
    modelResolver: () => ({ model: 'zai/glm-5.3' }),
  }).loop.run();
  const st = store.load(world);
  const iter = (r.iterations || []).find((i) => i.stage === 'THINK');
  const stamp = st.ok && iter ? st.store.stamps[iter.spawnId] : null;
  if (!stamp) problems.push('THINK stamp missing');
  else {
    if (stamp.modelPinned !== 'zai/glm-5.3') problems.push('modelPinned not the entry resolution: ' + JSON.stringify(stamp.modelPinned));
    if (stamp.modelObserved !== 'glm-5.3') problems.push('modelObserved not the host self-report: ' + JSON.stringify(stamp.modelObserved));
    if (stamp.commandCount !== 2) problems.push('commandCount not the tool_use count: ' + JSON.stringify(stamp.commandCount));
    if (stamp.denyHits !== 0) problems.push('denyHits not carried: ' + JSON.stringify(stamp.denyHits));
    if (!/^[0-9a-f]{64}$/.test(String(stamp.headSha256 || '')) || !/^[0-9a-f]{64}$/.test(String(stamp.tailSha256 || ''))) problems.push('window hashes not stamped');
    if (stamp.totalBytes !== head.length + tail.length) problems.push('totalBytes not the sidecar byte total: ' + JSON.stringify(stamp.totalBytes));
    const dir = path.join(store.storeRoot(world), 'windows');
    const sid = iter.spawnId;
    if (!fs.existsSync(path.join(dir, `${sid}.head.txt`)) || !fs.existsSync(path.join(dir, `${sid}.tail.txt`))) problems.push('window sidecars missing');
  }
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C23_OUT="$(node run-c23.cjs 2>&1 | tail -n 1)"
t104_eq "telemetry stamps carry the D-5 fields with window sidecars at spawn exit" "OK" "$C23_OUT"

# Script-stage VERIFY never probes the host: with a probe stub that throws if
# called, the stage runs its pinned legs and the Class S sections spawn,
# advances through the runner-driven commit channel, and the loop ends at
# SHIP. A failing pinned leg scores task-failed into the breaker instead.
t104_case c24
mkdir -p .gos/task/p0 .gos/logs
printf '# Spec\n\np0 auto spec\n' > .gos/task/p0/spec.md
t104_state VERIFY 3 ',"spec_path":".gos/task/p0/spec.md","semantic":{"allowlist":["run-c24.cjs"]}' > .gos/state.json
node -e "const fs=require('fs');const p='.gos/state.json';const st=JSON.parse(fs.readFileSync(p,'utf8'));const {execSync}=require('child_process');st.task_head=execSync('git rev-parse HEAD').toString().trim();fs.writeFileSync(p,JSON.stringify(st,null,2));"
cat > run-c24.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const problems = [];
const world = process.cwd();
(async () => {
  const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
  const probeRunner = () => { throw new Error('host probe must never run for a script stage'); };
  // zero-host happy path: legs green, sections spawn rc0, advance lands
  store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
  const specs = [];
  const spawnRunner = (spec) => { specs.push(spec); return { status: 0, stdout: 'sections pass\n', stderr: '' }; };
  const r1 = await loop.createLoop({
    rootDir: world, host: 'opencode', env, maxIterations: 3, spawnRunner, probeRunner,
    engineProbe: () => ({ engine: 'bwrap', version: '0.11.0' }),
    legRunner: () => ({ ok: true, verdict: { ok: true, failures: [] } }),
  }).loop.run();
  if (r1.status !== 'ship' || r1.ok !== true) problems.push('zero-host VERIFY did not reach SHIP: ' + r1.status + '/' + r1.reason + (r1.detail ? ':' + String(r1.detail).slice(0, 160) : ''));
  const st1 = JSON.parse(fs.readFileSync(path.join(world, '.gos', 'state.json'), 'utf8'));
  if (st1.current_stage !== 'SHIP') problems.push('VERIFY stage did not advance through the commit channel');
  if (!specs.length || !specs.every((s) => s.kind === 'script')) problems.push('VERIFY composed a non-script spawn');
  const st = store.load(world);
  const stamped = st.ok ? Object.entries(st.store.stamps).filter(([, v]) => v.stage === 'VERIFY') : [];
  if (!stamped.length) problems.push('VERIFY sections spawn not stamped');
  // failing pinned leg: scored task-failed into N, loop keeps driving
  const st2 = JSON.parse(fs.readFileSync(path.join(world, '.gos', 'state.json'), 'utf8'));
  st2.current_stage = 'VERIFY';
  (st2.completed_stages = st2.completed_stages || []).push('VERIFY');
  delete st2.approvals;
  fs.writeFileSync(path.join(world, '.gos', 'state.json'), JSON.stringify(st2, null, 2));
  const r2 = await loop.createLoop({
    rootDir: world, host: 'opencode', env, maxIterations: 1, spawnRunner, probeRunner,
    engineProbe: () => ({ engine: 'bwrap', version: '0.11.0' }),
    legRunner: (step) => (step.id === 'gate' ? { ok: true, verdict: { ok: false, failures: ['coverage gate red'] } } : { ok: true, verdict: { ok: true, failures: [] } }),
  }).loop.run();
  const vi = (r2.iterations || []).find((i) => i.stage === 'VERIFY');
  if (!vi || vi.signal !== 'task-failed' || vi.counted !== true) problems.push('failing leg not scored task-failed/counted: ' + JSON.stringify(vi && vi.signal) + '/' + JSON.stringify(vi && vi.counted));
  if (!r2.breaker || r2.breaker.consecutive !== 1) problems.push('failing leg did not count one consecutive failure');
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C24_OUT="$(node run-c24.cjs 2>&1 | tail -n 1)"
t104_eq "script-stage VERIFY runs zero-host; failing pinned legs score task-failed" "OK" "$C24_OUT"

# ------------------------------------------- status surfaces case ----------
# Dispatch view: auto status resolves the stage-dispatch table read-only and
# prints one compact line per stage (worker form, profile, model slot, verb
# grants, use cap, unit; BUILD carries the wave-dispatch suffix). The table
# load is failure-tolerant — missing or corrupt prints nothing extra and the
# counters line format never moves.
t104_case c25
t104_state THINK > .gos/state.json
node "$GOS" auto on > /dev/null 2>&1
GOS_AUTO_TEST_FIXTURE=1 node "$GOS" auto status > t25-status.txt 2>&1; T25_SRC=$?
t104_exit "T18: status with the dispatch view exits 0" 0 "$T25_SRC"
t104_contains "T18: dispatch block header prints" "dispatch:" "$(cat t25-status.txt)"
t104_contains "T18: THINK dispatch line (agent, restricted, default slot, four verbs, cap, unit)" "  THINK agent restricted default [commit gate section truth] cap16 unit=stage" "$(cat t25-status.txt)"
t104_contains "T18: BUILD dispatch line adds wave-dispatch with the implementer slot" "  BUILD agent workspace implementer [commit gate section truth checkpoint] cap64 unit=stage-wave wave-dispatch model=implementer" "$(cat t25-status.txt)"
t104_contains "T18: VERIFY dispatch line shows the script worker" "  VERIFY script restricted default [commit gate section truth] cap16 unit=stage" "$(cat t25-status.txt)"
t104_contains "T18: counters line format stays stable" "counters: spawns 0 · trips 0" "$(cat t25-status.txt)"
T25_U="$(node -e "
const path = require('path');
const fs = require('fs');
const cli = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/cli.cjs'));
const out = [];
out.push('missing:' + cli.dispatchViewLines({ tablePath: 'no-such-dir-t104/auto-dispatch.json' }).length);
fs.writeFileSync('corrupt-table.json', '{not json');
out.push('corrupt:' + cli.dispatchViewLines({ tablePath: 'corrupt-table.json' }).length);
fs.copyFileSync(path.join(process.env.GOS_ROOT, 'templates', 'auto-dispatch.json'), 'good-table.json');
const good = cli.dispatchViewLines({ tablePath: 'good-table.json' });
out.push('good:' + good.length + ':' + good[0] + ':' + good[1].trim().split(' ')[0]);
console.log(out.join('|'));
")"
t104_eq "T18: dispatch view failure-tolerant; good table renders header + stage lines in stage order" "missing:0|corrupt:0|good:8:dispatch::INTENT" "$T25_U"

# Clearance renders: status and resume print the three-tier vocabulary per
# delegated stage — a cleared record pairing a live store stamp renders
# store-verified, an unpaired cleared record renders pre-loop legacy
# (advisory status never holds on age alone), PENDING renders pending, and
# the SHIP delivery ledger labels the same tiers with human counts.
t104_case c26
t104_state THINK 3 ',"approvals":{"THINK":{"status":"cleared","ts":"2026-01-01T00:00:00.000Z","mode":"auto","stage":"THINK","evidence":{"spawnId":"c26-think","streamSha256":"1111111111111111111111111111111111111111111111111111111111111111","stampCount":1}},"PLAN":{"status":"PENDING","ts":"2026-01-01T00:01:00.000Z","mode":"auto","stage":"PLAN"}}' > .gos/state.json
node "$GOS" auto on > /dev/null 2>&1
node -e "
const path = require('path');
const store = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/store.cjs'));
store.stampStream('c26-think', 'THINK', '1111111111111111111111111111111111111111111111111111111111111111', '2026-01-01T00:00:00.000Z', process.cwd());
"
GOS_AUTO_TEST_FIXTURE=1 node "$GOS" auto status > t26-status.txt 2>&1
t104_contains "T18: status clearance line — store-verified mechanical clearance" "clearance: THINK mechanical clearance (store-verified) · PLAN pending mechanical clearance" "$(cat t26-status.txt)"
node "$GOS" resume > t26-resume.txt 2>&1; T26_RRC=$?
t104_exit "T18: resume with a clearance line exits 0" 0 "$T26_RRC"
t104_contains "T18: resume handoff carries the same clearance vocabulary" "auto clearance: THINK mechanical clearance (store-verified)" "$(cat t26-resume.txt)"
T26_LEDGER="$(node -e "
const path = require('path');
const fs = require('fs');
const archive = require(path.join(process.env.GOS_ROOT, 'bin/lib/task/archive.cjs'));
const clearedPaired = JSON.parse(fs.readFileSync('.gos/state.json', 'utf8')).approvals.THINK;
const state = {
  approvals: {
    THINK: clearedPaired,
    PLAN: { status: 'cleared', ts: '2026-01-01T00:00:00.000Z', mode: 'auto', stage: 'PLAN', evidence: { spawnId: 'c26-unknown', streamSha256: '2222222222222222222222222222222222222222222222222222222222222222', stampCount: 1 } },
    REVIEW: { status: 'PENDING', ts: '2026-01-01T00:02:00.000Z', mode: 'auto', stage: 'REVIEW' },
    ARCHIVE: '2026-01-02T00:00:00.000Z',
  },
};
const lines = archive.shipLedgerLines(state);
console.log(lines.join('\n'));
")"
t104_contains "T18: SHIP ledger labels mechanical clearance with both trust flavors" "  mechanical clearance: THINK (store-verified), PLAN (pre-loop legacy), REVIEW (pending)" "$T26_LEDGER"
t104_contains "T18: SHIP ledger counts human approvals with the pending suffix" "  human approvals: 1 (+1 pending)" "$T26_LEDGER"
t104_contains "T18: SHIP ledger names the progress-release tier on the red-team line" "  progress release: red-team findings" "$T26_LEDGER"

# Nav hint provider: one kind-discriminated object {kind, lines} — marker
# orientation inside a spawned session (artifact, advance verb, human-only
# gates), loop state when auto mode is on, none otherwise. Trip details
# quoted into a line pass the spawn-output sanitizer.
t104_case c27
t104_state THINK > .gos/state.json
node "$GOS" auto on > /dev/null 2>&1
T27_HINT="$(node -e "
const path = require('path');
const fs = require('fs');
const cli = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/cli.cjs'));
const out = [];
const mk = cli.autoHintProvider({ env: { GOS_AUTO_SPAWNED: '1', GOS_AUTO_SPAWN_ID: 'hint-1' }, rootDir: process.cwd() });
out.push('marker:' + mk.kind + ':' + mk.lines.length + ':' + (mk.lines.join(' ').includes('gos commit') && mk.lines.join(' ').includes('.gos/state.json') && mk.lines.join(' ').includes('push')));
const none = cli.autoHintProvider({ env: {}, rootDir: fs.mkdtempSync(path.join(process.cwd(), 'bare-')) });
out.push('none:' + none.kind + ':' + none.lines.length);
const esc = String.fromCharCode(27);
cli.autoHintProvider; // shape read below runs with a planted trip
const store = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/store.cjs'));
store.recordTrip({ layer: 'N', cls: 'task', detail: \"deny 'gos approve archive': \" + esc + '[31m{\"type\":\"message\"}' + esc + '[0m' }, process.cwd());
const mo = cli.autoHintProvider({ env: {}, rootDir: process.cwd() });
const joined = mo.lines.join('\n');
out.push('mode-on:' + mo.kind + ':' + (joined.includes('auto mode on') && joined.includes('profile restricted') && joined.includes('dispatch:')));
out.push('sanitized:' + joined.includes('[spawn] deny') + ':' + !joined.includes(esc));
console.log(out.join('|'));
")"
t104_eq "T18: hint provider marker/mode-on/none shapes with sanitized trip bytes" "marker:marker:2:true|none:none:0|mode-on:mode-on:true|sanitized:true:true" "$T27_HINT"

# Sanitizer on status trip details: a breaker record quoting deny lines with
# raw ANSI-laden JSON renders stripped and carries the spawn-output marker.
t104_case c28
t104_state THINK > .gos/state.json
node "$GOS" auto on > /dev/null 2>&1
node -e "
const path = require('path');
const store = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/store.cjs'));
const esc = String.fromCharCode(27);
store.recordTrip({ layer: 'N', cls: 'task', detail: \"deny 'gos approve archive': \" + esc + '[31m{\"type\":\"message\",\"text\":\"tried\"}' + esc + '[0m' }, process.cwd());
"
GOS_AUTO_TEST_FIXTURE=1 node "$GOS" auto status > t28-status.txt 2>&1; T28_SRC=$?
t104_exit "T18: status with an ANSI-laden trip detail exits 0" 0 "$T28_SRC"
t104_contains "T18: trip detail renders through the spawn-output sanitizer (marked)" "[spawn] deny 'gos approve archive': {\"type\":\"message\"" "$(cat t28-status.txt)"
if grep -qF "$(printf '\033')" t28-status.txt; then
  t104_bad "T18: no escape byte survives into the status render"
else
  t104_ok "T18: no escape byte survives into the status render"
fi

# Wording surfaces: the three-tier vocabulary and the script-worker note
# live in the README auto section and the gos-verify skill.
T104_ROOT="$(cd "$GOS_ROOT" && pwd)"
if grep -qF "mechanical clearance" "$T104_ROOT/README.md"; then
  t104_ok "T18: README names mechanical clearance"
else
  t104_bad "T18: README names mechanical clearance"
fi
if grep -qF "mechanical clearance" "$T104_ROOT/skills/gos-verify/SKILL.md"; then
  t104_ok "T18: gos-verify names mechanical clearance"
else
  t104_bad "T18: gos-verify names mechanical clearance"
fi
if grep -qF "script worker" "$T104_ROOT/skills/gos-verify/SKILL.md"; then
  t104_ok "T18: gos-verify carries the script-worker note"
else
  t104_bad "T18: gos-verify carries the script-worker note"
fi

# Crashed-advance trust boundary: .gos/cache/state.snapshot lives inside
# spawn-writable roots, so snapshot adoption is gated on the runner's own
# store-side baseline hash — a crafted snapshot carrying attacker-chosen
# approvals content is NOT adopted and the loop pauses external-mutation.
t104_case c29
mkdir -p .gos/task/p0 .gos/cache
printf '# Spec\n\np0 auto spec\n' > .gos/task/p0/spec.md
cat > run-c29.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const problems = [];
const world = process.cwd();
spawnSync('git', ['init', '-q', '-b', 'work', '.'], { cwd: world });
spawnSync('git', ['-c', 'user.name=gos-test', '-c', 'user.email=t@invalid', 'commit', '--allow-empty', '-m', 'root'], { cwd: world });
const pre = { schema_version: 6, level: 1, current_stage: 'BUILD', completed_stages: ['INTENT'], intent: { summary: 'c29', confirmed: true }, task_head: 'abc', requirements: [], decisions: [], observable_truths: [], gaps: [], checkpoints: [], approvals: {} };
const preRaw = JSON.stringify(pre);
fs.writeFileSync(path.join(world, '.gos', 'state.json'), preRaw);
let stateNow = pre;
let spawnN = 0;
const spawnRunner = (spec) => {
  spawnN += 1;
  if (spawnN === 1) {
    // The crash window: the state moved forward and the labeled commit
    // never landed — but the "pre-advance snapshot" carries attacker-chosen
    // approvals content instead of the world the runner validated.
    const forged = { ...pre, approvals: { BUILD: { status: 'cleared', ts: '2000-01-01T00:00:00.000Z', mode: 'auto', stage: 'BUILD' } } };
    fs.writeFileSync(path.join(world, '.gos', 'cache', 'state.snapshot'), JSON.stringify(forged));
    stateNow = { ...pre, current_stage: 'VERIFY', completed_stages: ['INTENT', 'BUILD'] };
    return { status: null, stdout: '', stderr: '', error: Object.assign(new Error('spawn killed'), { killed: true }) };
  }
  return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
};
(async () => {
  store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 5, B: 30 } });
  const r = await loop.createLoop({ rootDir: world, host: 'gos-fixture-host', env: { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' }, maxIterations: 2, spawnRunner, stateReader: () => stateNow }).loop.run();
  if (r.status !== 'paused' || r.reason !== 'external-mutation') problems.push('crafted snapshot was adopted or mis-paused: ' + r.status + '/' + r.reason);
  const stateAfter = JSON.parse(fs.readFileSync(path.join(world, '.gos', 'state.json'), 'utf8'));
  if (stateAfter.approvals && stateAfter.approvals.BUILD) problems.push('attacker-chosen approvals content landed in the state file');
  if (typeof store.readBaselineState !== 'function') problems.push('store exposes no readBaselineState');
  else {
    const bl = store.readBaselineState(world);
    if (!bl.ok || !bl.baselineState || bl.baselineState.sha256 !== crypto.createHash('sha256').update(preRaw).digest('hex')) {
      problems.push('baseline state hash not recorded store-side: ' + JSON.stringify(bl.baselineState || null));
    }
  }
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C29_OUT="$(node run-c29.cjs 2>&1 | tail -n 1)"
t104_eq "crafted crashed-advance snapshot with attacker approvals is refused by the baseline-hash gate" "OK" "$C29_OUT"

echo "--- T104 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
