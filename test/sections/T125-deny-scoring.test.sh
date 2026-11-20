#!/usr/bin/env bash
# gos-map:none
# Deny scoring is command-kind only — text echoes stay telemetry, never a
# step failure. The harvested fixture test/fixtures/5419521c-deny-slice.log
# carries the text-kind deny lines from the 2026-11-09 04:38 dogfood breaker
# trip: a VERIFY sections spawn echoed the security section's DANGER truth
# table and the dispatch-refuse rows, the post-hoc scan matched them, and
# three text-only trips burned the breaker. Lines are ASCII-transcribed from
# the spawn window (the check marks become [x]).
# Case map:
#   C1  classification: every scan hit on the fixture slice is kind 'text'
#       across the composed restricted deny union; a bash tool_use command
#       line classifies kind 'command' (the shapes the scorer must split)
#   C2  model spawn, post-hoc scan: fixture text in the stream, no advance
#       -> signal rc0-no-advance (never task-failed), deny detail absent,
#       text hits stay reported in the stamp (denyHits > 0, denyCommandHits 0)
#   C3  model spawn, pre-truncation hits: the same fixture hits arriving on
#       preTruncationDenyHits with a benign captured stream -> same outcome
#   C4  command-kind control (model): a bash tool_use deny command in the
#       stream -> task-failed, counted, detail names the deny pattern
#   C5  script stage (the 04:38 incident shape): the Class S sections spawn
#       echoes the fixture slice -> steps pass, VERIFY advances through the
#       commit channel, the loop ships; the stamp carries the text hits
#   C6  command-kind control (script): a bash tool_use deny command in the
#       sections spawn stream -> the step fails task-failed with the deny
#       detail and never advances
# Standalone-safe: self-provisions env when not under test/run-sections.sh.

T125_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T125_STANDALONE=1
  T125_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T125_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T125_SELFROOT"
  export TESTBASE="$(mktemp -d "$T125_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T125_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t125"
mkdir -p "$T125_DIR" && cd "$T125_DIR" || exit 1

PASS=0
FAIL=0
t125_ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
t125_bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
t125_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t125_ok "$label"; else t125_bad "$label (expected '$expected', got '$actual')"; fi
}

t125_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T125_DIR"
  if [ "$T125_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t125_teardown EXIT

T125_FIXTURE="$GOS_ROOT/test/fixtures/5419521c-deny-slice.log"

echo "--- T125: deny scoring command-kind only ---"

# One isolated case world per call: sandbox HOME + XDG_DATA_HOME + a git repo
# with a minimal task state.
t125_case() {
  T125_CASE="$T125_DIR/$1"
  mkdir -p "$T125_CASE/home" "$T125_CASE/xdg" "$T125_CASE/repo/.gos/logs"
  export HOME="$T125_CASE/home"
  export XDG_DATA_HOME="$T125_CASE/xdg"
  cd "$T125_CASE/repo" || exit 1
  git init -q -b work . && git commit -q --allow-empty -m root
}

t125_state() { # $1=current_stage $2=level (default 1) $3=extra json fields
  printf '{"schema_version":6,"level":%s,"current_stage":"%s","completed_stages":["INTENT"],"intent":{"summary":"t125 fixture","confirmed":true},"task_head":"abc123def0123456789abcdef0123456789abcde","spec_path":null,"plan_path":null,"requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{}%s}' \
    "${2:-1}" "$1" "${3:-}"
}

# ---------------------------------------------------------------- C1 --
# Classification split: the fixture slice is deny-bearing text only; the
# bash tool_use command line is the command kind. Both classifications feed
# every later case.
cat > run-c1.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const launcher = require(path.join(GR, 'bin/lib/ops/auto/launcher.cjs'));
const problems = [];
const composed = launcher.compose('restricted', { workspace: process.cwd(), env: process.env, store: { load: () => ({ ok: false }) } });
const text = fs.readFileSync(path.join(GR, 'test', 'fixtures', '5419521c-deny-slice.log'), 'utf8');
const hits = launcher.scanSpawnOutput(text, { deny: composed.deny });
if (!hits.length) problems.push('fixture slice carries no deny hits');
const textHits = hits.filter((h) => h.kind === 'text');
const otherHits = hits.filter((h) => h.kind !== 'text');
if (hits.length !== textHits.length) problems.push('non-text kinds on the fixture slice: ' + JSON.stringify(otherHits.map((h) => h.kind)));
const patterns = new Set(hits.map((h) => h.pattern));
if (!patterns.has('rm -rf /') || !patterns.has('sudo')) problems.push('expected incident patterns missing: ' + [...patterns].join(','));
// the streaming scanner classifies the same split
const streaming = launcher.makeStreamDenyScanner({ deny: composed.deny });
streaming.feed(text.slice(0, 200));
streaming.feed(text.slice(200));
streaming.flush();
const sHits = streaming.hits;
if (!sHits.length || sHits.some((h) => h.kind !== 'text')) problems.push('streaming scanner misclassified the fixture slice');
// the command-kind shape: a bash tool_use event line carrying the deny verb
const cmdLine = JSON.stringify({ type: 'tool_use', part: { type: 'tool', tool: 'bash', input: { command: 'sudo -n /usr/bin/true' } } });
const cmdHits = launcher.scanSpawnOutput(cmdLine, { deny: composed.deny });
if (!cmdHits.length || cmdHits.some((h) => h.kind !== 'command')) problems.push('bash tool_use command line not command-kind: ' + JSON.stringify(cmdHits.map((h) => h.kind)));
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C1_OUT="$(node run-c1.cjs 2>&1 | tail -n 1)"
t125_eq "C1: fixture slice scans text-kind only; bash tool_use command line scans command-kind" "OK" "$C1_OUT"

# ---------------------------------------------------------------- C2 --
# Post-hoc scan path: the spawn's captured stream echoes the incident slice,
# the spawn makes no advance — deny text hits must not fail the step.
t125_case c2
t125_state THINK > .gos/state.json
export GOS_AUTO_TIMEOUT_WALL_SEC=5 GOS_AUTO_TIMEOUT_IDLE_SEC=2
cat > run-c2.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const fixture = fs.readFileSync(path.join(GR, 'test', 'fixtures', '5419521c-deny-slice.log'), 'utf8');
const problems = [];
const spawnRunner = (spec) => {
  if (spec.roWorkspace) return { status: 0, stdout: 'REDTEAM-FINDINGS: 0\n', stderr: '' };
  // the deny echo rides a message event (model streams are event lines; the
  // sections output the session echoed is prose inside the text field)
  return { status: 0, stdout: '{"type":"message","text":' + JSON.stringify(fixture) + '}\n{"type":"result"}\n', stderr: '' };
};
(async () => {
  store.create({ mode: 'on', rootDir, limits: { N: 3, K: 9, B: 9 } });
  const r = await loop.createLoop({ rootDir, host: 'gos-fixture-host', env, maxIterations: 1, spawnRunner }).loop.run();
  const iter = (r.iterations || [])[0] || {};
  if (iter.signal !== 'rc0-no-advance') problems.push('signal is ' + JSON.stringify(iter.signal) + ' (want rc0-no-advance)');
  if (String(iter.detail || '').includes("deny '")) problems.push('deny detail leaked into a text-only outcome');
  const st = store.load(rootDir);
  const stamp = st.ok ? st.store.stamps[iter.spawnId] : null;
  if (!stamp) problems.push('spawn stamp missing');
  else {
    if (!(stamp.denyHits > 0)) problems.push('text hits not reported in the stamp (denyHits ' + JSON.stringify(stamp.denyHits) + ')');
    if (stamp.denyCommandHits !== 0) problems.push('text hits scored as command hits: ' + JSON.stringify(stamp.denyCommandHits));
  }
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C2_OUT="$(node run-c2.cjs 2>&1 | tail -n 1)"
t125_eq "C2: post-hoc text deny hits report as telemetry, never fail the step (rc0-no-advance)" "OK" "$C2_OUT"

# ---------------------------------------------------------------- C3 --
# Pre-truncation path: the streaming scanner caught the fixture hits before
# the captured window went benign — the payload hits must score the same
# command-kind-only split.
t125_case c3
t125_state THINK > .gos/state.json
cat > run-c3.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const launcher = require(path.join(GR, 'bin/lib/ops/auto/launcher.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const fixture = fs.readFileSync(path.join(GR, 'test', 'fixtures', '5419521c-deny-slice.log'), 'utf8');
const problems = [];
const composed = launcher.compose('restricted', { workspace: rootDir, env, store: { load: () => ({ ok: false }) } });
const preTruncationDenyHits = launcher.scanSpawnOutput(fixture, { deny: composed.deny });
const spawnRunner = (spec) => {
  if (spec.roWorkspace) return { status: 0, stdout: 'REDTEAM-FINDINGS: 0\n', stderr: '' };
  return { status: 0, stdout: '{"type":"result"}\n', stderr: '', preTruncationDenyHits };
};
(async () => {
  store.create({ mode: 'on', rootDir, limits: { N: 3, K: 9, B: 9 } });
  const r = await loop.createLoop({ rootDir, host: 'gos-fixture-host', env, maxIterations: 1, spawnRunner }).loop.run();
  const iter = (r.iterations || [])[0] || {};
  if (iter.signal !== 'rc0-no-advance') problems.push('signal is ' + JSON.stringify(iter.signal) + ' (want rc0-no-advance)');
  if (String(iter.detail || '').includes("deny '")) problems.push('deny detail leaked into a text-only outcome');
  const st = store.load(rootDir);
  const stamp = st.ok ? st.store.stamps[iter.spawnId] : null;
  if (!stamp) problems.push('spawn stamp missing');
  else if (!(stamp.denyHits > 0) || stamp.denyCommandHits !== 0) problems.push('stamp telemetry wrong: ' + JSON.stringify({ denyHits: stamp.denyHits, denyCommandHits: stamp.denyCommandHits }));
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C3_OUT="$(node run-c3.cjs 2>&1 | tail -n 1)"
t125_eq "C3: pre-truncation text deny hits score the same command-kind-only split" "OK" "$C3_OUT"

# ---------------------------------------------------------------- C4 --
# Command-kind control (model path): a bash tool_use carrying a deny verb is
# an execution attempt — the step fails task-failed, counted, deny named.
t125_case c4
t125_state THINK > .gos/state.json
cat > run-c4.cjs <<'EOF'
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const rootDir = process.cwd();
const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
const problems = [];
const cmdLine = JSON.stringify({ type: 'tool_use', part: { type: 'tool', tool: 'bash', input: { command: 'sudo -n /usr/bin/true' } } });
const spawnRunner = (spec) => {
  if (spec.roWorkspace) return { status: 0, stdout: 'REDTEAM-FINDINGS: 0\n', stderr: '' };
  return { status: 0, stdout: cmdLine + '\n{"type":"result"}\n', stderr: '' };
};
(async () => {
  store.create({ mode: 'on', rootDir, limits: { N: 3, K: 9, B: 9 } });
  const r = await loop.createLoop({ rootDir, host: 'gos-fixture-host', env, maxIterations: 1, spawnRunner }).loop.run();
  const iter = (r.iterations || [])[0] || {};
  if (iter.signal !== 'task-failed') problems.push('command-kind hit did not fail the step: ' + JSON.stringify(iter.signal));
  if (iter.counted !== true) problems.push('command-kind deny failure not counted toward N');
  if (!String(iter.detail || '').includes("deny 'sudo'")) problems.push('failure detail does not name the deny pattern: ' + JSON.stringify(iter.detail));
  const st = store.load(rootDir);
  const stamp = st.ok ? st.store.stamps[iter.spawnId] : null;
  if (!stamp || !(stamp.denyCommandHits > 0)) problems.push('stamp denyCommandHits missing: ' + JSON.stringify(stamp));
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C4_OUT="$(node run-c4.cjs 2>&1 | tail -n 1)"
t125_eq "C4: command-kind deny hit fails the step, counts, and names the pattern" "OK" "$C4_OUT"

# ---------------------------------------------------------------- C5 --
# The 04:38 incident shape: a script-stage VERIFY whose Class S sections
# spawn echoes the fixture slice — the steps pass, the advance lands through
# the runner-driven commit channel, the loop ships, and the stamp carries
# the text hits as telemetry.
t125_case c5
mkdir -p .gos/task/p0
printf '# Spec\n\np0 auto spec\n' > .gos/task/p0/spec.md
t125_state VERIFY 3 ',"spec_path":".gos/task/p0/spec.md","semantic":{"allowlist":["run-c5.cjs"]}' > .gos/state.json
node -e "const fs=require('fs');const p='.gos/state.json';const st=JSON.parse(fs.readFileSync(p,'utf8'));const {execSync}=require('child_process');st.task_head=execSync('git rev-parse HEAD').toString().trim();fs.writeFileSync(p,JSON.stringify(st,null,2));"
cat > run-c5.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const problems = [];
const world = process.cwd();
const fixture = fs.readFileSync(path.join(GR, 'test', 'fixtures', '5419521c-deny-slice.log'), 'utf8');
(async () => {
  const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
  const probeRunner = () => { throw new Error('host probe must never run for a script stage'); };
  store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
  const specs = [];
  const spawnRunner = (spec) => {
    specs.push(spec);
    return { status: 0, stdout: 'sections pass\n' + fixture, stderr: '' };
  };
  const r = await loop.createLoop({
    rootDir: world, host: 'opencode', env, maxIterations: 3, spawnRunner, probeRunner,
    engineProbe: () => ({ engine: 'bwrap', version: '0.11.0' }),
    legRunner: () => ({ ok: true, verdict: { ok: true, failures: [] } }),
  }).loop.run();
  if (r.status !== 'ship' || r.ok !== true) problems.push('text-hit sections spawn did not ship: ' + r.status + '/' + r.reason + (r.detail ? ':' + String(r.detail).slice(0, 160) : ''));
  const st1 = JSON.parse(fs.readFileSync(path.join(world, '.gos', 'state.json'), 'utf8'));
  if (st1.current_stage !== 'SHIP') problems.push('VERIFY did not advance through the commit channel');
  if (!specs.length || !specs.every((s) => s.kind === 'script')) problems.push('VERIFY composed a non-script spawn');
  const st = store.load(world);
  const stamped = st.ok ? Object.values(st.store.stamps).filter((v) => v.stage === 'VERIFY') : [];
  if (!stamped.length) problems.push('VERIFY sections spawn not stamped');
  else {
    const s = stamped[0];
    if (!(s.denyHits > 0)) problems.push('text hits not reported in the script stamp: ' + JSON.stringify(s.denyHits));
    if (s.denyCommandHits !== 0) problems.push('script stamp scored text hits as commands: ' + JSON.stringify(s.denyCommandHits));
  }
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C5_OUT="$(node run-c5.cjs 2>&1 | tail -n 1)"
t125_eq "C5: incident-shaped sections echo passes the script stage and ships (text hits stay telemetry)" "OK" "$C5_OUT"

# ---------------------------------------------------------------- C6 --
# Command-kind control (script path): a bash tool_use deny verb inside the
# sections spawn stream fails the step — task-failed, deny named, never
# advances.
t125_case c6
mkdir -p .gos/task/p0
printf '# Spec\n\np0 auto spec\n' > .gos/task/p0/spec.md
t125_state VERIFY 3 ',"spec_path":".gos/task/p0/spec.md","semantic":{"allowlist":["run-c6.cjs"]}' > .gos/state.json
node -e "const fs=require('fs');const p='.gos/state.json';const st=JSON.parse(fs.readFileSync(p,'utf8'));const {execSync}=require('child_process');st.task_head=execSync('git rev-parse HEAD').toString().trim();fs.writeFileSync(p,JSON.stringify(st,null,2));"
cat > run-c6.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const problems = [];
const world = process.cwd();
const cmdLine = JSON.stringify({ type: 'tool_use', part: { type: 'tool', tool: 'bash', input: { command: 'sudo -n /usr/bin/true' } } });
(async () => {
  const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
  store.create({ mode: 'on', rootDir: world, limits: { N: 3, K: 9, B: 9 } });
  const spawnRunner = (spec) => ({ status: 0, stdout: 'sections pass\n' + cmdLine + '\n', stderr: '' });
  const r = await loop.createLoop({
    rootDir: world, host: 'opencode', env, maxIterations: 3, spawnRunner,
    probeRunner: () => ({ ok: true, out: 'opencode 1.20.0\n', err: '' }),
    engineProbe: () => ({ engine: 'bwrap', version: '0.11.0' }),
    legRunner: () => ({ ok: true, verdict: { ok: true, failures: [] } }),
  }).loop.run();
  if (r.status === 'ship') problems.push('command-kind sections hit shipped');
  const verify = (r.iterations || []).filter((i) => i.stage === 'VERIFY');
  if (!verify.length || !verify.some((i) => i.signal === 'task-failed')) problems.push('command-kind sections hit did not fail task-failed: ' + JSON.stringify(verify.map((i) => i.signal)));
  if (!verify.some((i) => String(i.detail || '').includes("deny 'sudo'"))) problems.push('failure detail does not name the deny pattern');
  const st1 = JSON.parse(fs.readFileSync(path.join(world, '.gos', 'state.json'), 'utf8'));
  if (st1.current_stage !== 'VERIFY') problems.push('stage advanced past a command-kind deny hit');
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
C6_OUT="$(node run-c6.cjs 2>&1 | tail -n 1)"
t125_eq "C6: command-kind deny hit inside the sections spawn fails the script step" "OK" "$C6_OUT"

echo "--- T125 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
