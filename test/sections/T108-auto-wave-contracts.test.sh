#!/usr/bin/env bash
# gos-map:none
# Auto wave contracts section — the BUILD wave driver over the frozen plan
# snapshot (ops/auto/workers.cjs runWaveDispatch/reconcileWaves), its
# runner-held prompt template, the store's wave completion records and
# dispatch-table stamp, and the breaker's wave unit labels.
# Case map (case -> what must hold):
#   wave-happy    C1  a two-wave fixture plan drives two spawns with
#                   pointer-only prompts (wave number + task ids, no repo
#                   prose, no leftover braces); each wave releases on
#                   exactly one commit touching only its declared files;
#                   completion records land in the store; the composed
#                   spawn carries the full BUILD equipage (bwrap frame,
#                   scratch + testbed + grant manifest binds, workspace
#                   identity, spawn id env)
#   input-contract C2 template drift refuses the whole dispatch before any
#                   spawn (prompt-template-drift); a template carrying any
#                   brace token beyond {wave}/{taskIds} refuses
#                   (prompt-token-refused); the stamped hash is stable
#   wave-negatives C3 undeclared-path / frozen-edit / second-commit /
#                   ref-move each hold with the named violation, write no
#                   completion record, and count one stage failure
#   silence-hold  C4 rc0 with no commit and no no-op evidence holds
#                   (no-commit) and scores task-failed — rc0-no-advance is
#                   never the wave signal
#   noop-release  C5 an evidenced no-op marker releases the wave as
#                   skipped-noop with the reason recorded, and never counts
#                   as a failure
#   table-roll    C6 a red-team-passed declared edit of the dispatch table
#                   releases and rolls the store stamp (sha + rolledByWave);
#                   a findings round holds the wave without rolling
#   crash-resume  C7 a runner dying mid-check leaves the marker; reconcile
#                   adopts the attributable commit, re-runs only the release
#                   check (no re-spawn), and a re-dispatch skips the
#                   completed wave and drives only the remaining one
#   completion-rerun C8 waves with existing completion records re-run only
#                   the release check — the spawn runner is never invoked
#   breaker-k     C9 five healthy distinct waves never trip K; one wave
#                   re-entered five times trips K on its own label
#   breaker-n     C10 three consecutive failed waves trip N as one stage
#                   streak while each wave's K label stays at one visit
#   store-shapes  C11 wave record conflicts refuse; malformed waves keys
#                   read as corrupt; the dispatch-table stamp validates its
#                   wave-key shape
#   unit-labels   C12 waveUnitLabel/validation surface: closed enum, digit
#                   rule, breaker visit refusal for slash-carrying labels
#                   outside the enum
#   loop-wired    C13 the auto loop drives BUILD through the wave driver:
#                   two waves release, the stage exits through one advance
#                   spawn (`gos commit build`), the run-start dispatch-table
#                   stamp pins the loaded file, wave spawns carry the
#                   approvals baseline, and the advance spawn pins the
#                   resolved model
#   wave-env      C14 a wave spawn's env never carries credential-class
#                   entries planted in the loop env: the driver routes its
#                   env overlay through the sanitizer, so GH_TOKEN /
#                   AWS_SECRET_ACCESS_KEY / GITHUB_*KEY die while benign
#                   overlay entries (PATH-class, fixture gates) survive
#   deny-flood    C15 a wave spawn that prints one deny line and then floods
#                   past the capture cap still classifies deny-hit: the
#                   driver prefers the pre-truncation streaming hits exactly
#                   like the loop scorer, stamps denyHits telemetry, and
#                   writes the dual-window sidecars for the wave spawn
#   held-vs-crash C16 a held wave is not a crash: the hold writes a
#                   store-side held record and tears the spawn down, and
#                   reconcile never adopts it; crash pre-evidence
#                   (preHead/preRefsText/preDirty) is store-side at wave
#                   START, so a tampered scratch marker cannot steer
#                   reconcile; a crashed wave whose stamp shows denyHits>0
#                   is unattributable
# Standalone-safe: self-provisions env when not under test/run-sections.sh.

T108_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T108_STANDALONE=1
  T108_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T108_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T108_SELFROOT"
  export TESTBASE="$(mktemp -d "$T108_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T108_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t108"
mkdir -p "$T108_DIR" && cd "$T108_DIR" || exit 1
export T108_DIR
export XDG_DATA_HOME="$T108_DIR/xdg"

PASS=0
FAIL=0
t108_ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
t108_bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
t108_contains() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then t108_ok "$label"; else
    t108_bad "$label (expected: '$expected')"
    echo "    actual: $(printf '%s' "$actual" | head -c 240)"
  fi
}
t108_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then t108_ok "$label (exit $actual)"; else
    t108_bad "$label (expected exit $expected, got '${actual:-<none>}')"; fi
}

t108_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T108_DIR"
  if [ "$T108_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t108_teardown EXIT

echo "--- T108: auto wave contracts (wave driver, three contracts, breaker wave accounting) ---"

# Shared fixture library: fixture repos over the frozen snapshot shape,
# fake spawn runners running the real git a wave would run, driver ctx
# assembly, and a throwing runner proving reconcile never spawns.
cat > "$T108_DIR/t108-lib.cjs" <<'EOF'
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const workers = require(path.join(GR, 'bin/lib/ops/auto/workers.cjs'));
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const breakerMod = require(path.join(GR, 'bin/lib/ops/auto/breaker.cjs'));
const crypto = require('crypto');

const TASK = 'T108fx';
const BRANCH = 'auto/T108fx';

function git(cwd, args) {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} rc=${r.status}: ${r.stderr}`);
  return String(r.stdout || '');
}

function sha256Text(t) { return crypto.createHash('sha256').update(String(t), 'utf8').digest('hex'); }

// Fixture repo: work branch, task spec + frozen spec sha, .gos/state.json
// carrying the plan snapshot (tasks with wave numbers + declared files),
// and a created store under the sandbox XDG root. waves: [[{id, files}]].
function makeRepo(dir, waves) {
  fs.mkdirSync(path.join(dir, '.gos'), { recursive: true });
  fs.mkdirSync(path.join(dir, 'task', TASK), { recursive: true });
  const specFile = path.join(dir, 'task', TASK, 'spec.md');
  fs.writeFileSync(specFile, '# fixture spec\n');
  const tasks = [];
  waves.forEach((ws, i) => {
    for (const t of ws) tasks.push({ id: t.id, covers: [], files: t.files, wave: i + 1 });
  });
  const snapshot = { tasks, audit: [], meta: { waveValidation: { ok: true, waves: waves.length } } };
  fs.writeFileSync(path.join(dir, '.gos', 'state.json'), JSON.stringify({
    task_id: TASK,
    current_stage: 'BUILD',
    spec_sha256: sha256Text(fs.readFileSync(specFile, 'utf8')),
    plan_snapshot: snapshot,
  }, null, 2));
  fs.writeFileSync(path.join(dir, '.gitignore'), '.gos/\n');
  git(dir, ['init', '-q', '-b', BRANCH]);
  git(dir, ['add', '-A']);
  git(dir, ['commit', '-q', '-m', 'fixture seed']);
  const created = store.create({ rootDir: dir, mode: 'on' });
  if (!created.ok) throw new Error('fixture store refused: ' + created.reason);
  return { dir, snapshot };
}

// Fake spawn runner: runs the real git a wave spawn would run, per
// behavior. roWorkspace specs are red-team rounds over the wave diff.
function makeRunner(log, behavior) {
  return async function spawnRunner(spec) {
    log.push(spec);
    if (spec.roWorkspace === true) {
      const n = behavior.rt === 'findings' ? 2 : 0;
      return { status: 0, stdout: `review over the wave diff\nREDTEAM-FINDINGS: ${n}\n`, stderr: '' };
    }
    const commit = (files, msg) => {
      for (const [p, content] of Object.entries(files)) {
        const abs = path.join(spec.cwd, p);
        fs.mkdirSync(path.dirname(abs), { recursive: true });
        fs.writeFileSync(abs, content);
      }
      git(spec.cwd, ['add', ...Object.keys(files)]);
      git(spec.cwd, ['commit', '-q', '-m', msg]);
    };
    switch (behavior.kind) {
      case 'good':
        commit(Object.fromEntries(spec.declaredFiles.map((p) => [p, `wave ${spec.wave} content\n`])), `wave ${spec.wave} work`);
        break;
      case 'noop':
        fs.mkdirSync(spec.scratch, { recursive: true });
        fs.writeFileSync(path.join(spec.scratch, 'noop'), 'already landed upstream — nothing to do\n');
        break;
      case 'nocommit': break;
      case 'undeclared':
        commit({ [spec.declaredFiles[0]]: 'x\n', 'src/rogue.txt': 'rogue\n' }, 'rogue wave');
        break;
      case 'frozen': {
        commit({ [spec.declaredFiles[0]]: 'x\n' }, 'frozen probe');
        const sp = path.join(spec.cwd, '.gos', 'state.json');
        const st = JSON.parse(fs.readFileSync(sp, 'utf8'));
        st.plan_snapshot.tasks[0].files.push('src/smuggled.txt');
        fs.writeFileSync(sp, JSON.stringify(st, null, 2));
        break;
      }
      case 'second':
        commit({ [spec.declaredFiles[0]]: 'x\n' }, 'first');
        commit({ [spec.declaredFiles[0]]: 'y\n' }, 'second');
        break;
      case 'refmove':
        commit({ [spec.declaredFiles[0]]: 'x\n' }, 'refmove wave');
        git(spec.cwd, ['branch', 'evil-side']);
        break;
      case 'dirty':
        commit({ [spec.declaredFiles[0]]: 'x\n' }, 'dirty wave');
        fs.writeFileSync(path.join(spec.cwd, 'stray.txt'), 'left behind\n');
        break;
      case 'table': {
        const tp = path.join(spec.cwd, 'templates', 'auto-dispatch.json');
        const tbl = JSON.parse(fs.readFileSync(tp, 'utf8'));
        tbl.description = 'rolled by fixture wave ' + spec.wave;
        fs.writeFileSync(tp, JSON.stringify(tbl, null, 2) + '\n');
        git(spec.cwd, ['add', 'templates/auto-dispatch.json']);
        git(spec.cwd, ['commit', '-q', '-m', 'table roll wave']);
        break;
      }
      default: throw new Error('unknown behavior ' + behavior.kind);
    }
    return { status: 0, stdout: `wave ${spec.wave} done\n`, stderr: '' };
  };
}

function throwingRunner() {
  return async function () { throw new Error('reconcile must never spawn'); };
}

function makeBreaker(N, K, B, rootDir) {
  const made = breakerMod.createBreaker({ rootDir, limits: { N, K, B } });
  if (!made.ok) throw new Error('breaker refused: ' + made.reason);
  return made.breaker;
}

function ctxFor(repo, spawnRunner, breaker, extra) {
  return Object.assign({
    rootDir: repo.dir,
    taskId: TASK,
    workBranch: BRANCH,
    env: { ...process.env },
    engineProbe: () => ({ engine: 'bwrap', version: '0.11.0' }),
    spawnRunner,
    breaker,
    gitRunner: (args, cwd) => spawnSync('git', args, { cwd: cwd || repo.dir, encoding: 'utf8' }),
  }, extra || {});
}

function headOf(dir) { return git(dir, ['rev-parse', 'HEAD']).trim(); }
function changedOf(dir, head) {
  return git(dir, ['diff', '--name-only', `${head}^`, head]).split('\n').map((s) => s.trim()).filter(Boolean);
}

module.exports = {
  workers, store, breakerMod, TASK, BRANCH,
  makeRepo, makeRunner, throwingRunner, makeBreaker, ctxFor,
  headOf, changedOf, sha256Text,
};
EOF

# ---------------------------------------------------------------- C1 + C2 --
echo "C1: wave-happy (two waves, pointer-only prompts, one declared commit each)"
cat > "$T108_DIR/c1.cjs" <<'EOF'
const path = require('path');
const problems = [];
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
const repo = L.makeRepo(path.join(process.env.T108_DIR, 'c1-repo'), [
  [{ id: 'T108a', files: ['src/a.txt'] }],
  [{ id: 'T108b', files: ['src/b.txt'] }],
]);
const log = [];
const breaker = L.makeBreaker(3, 5, 100, repo.dir);
(async () => {
  const res = await L.workers.runWaveDispatch(repo.snapshot, L.ctxFor(repo, L.makeRunner(log, { kind: 'good' }), breaker));
  if (!res.ok || res.status !== 'complete') problems.push('dispatch not complete: ' + JSON.stringify({ ok: res.ok, status: res.status, reason: res.reason, detail: res.detail }));
  if (res.waves.length !== 2 || res.waves.some((w) => w.status !== 'released')) {
    problems.push('wave statuses not released/released: ' + JSON.stringify(res.waves.map((w) => w.status)));
  }
  if (log.length !== 2) problems.push('spawn count ' + log.length + ' != 2');
  // pointer-only prompts
  log.forEach((spec, i) => {
    const want = L.workers.renderWavePrompt({ wave: i + 1, taskIds: [i === 0 ? 'T108a' : 'T108b'] });
    if (!want.ok || spec.prompt !== want.prompt) problems.push(`wave ${i + 1} prompt is not the pointer-only render`);
    if (spec.prompt.includes('{') || spec.prompt.includes('}')) problems.push(`wave ${i + 1} prompt carries leftover braces`);
    if (spec.prompt.includes('src/a.txt') || spec.prompt.includes('src/b.txt')) problems.push(`wave ${i + 1} prompt interpolates repo file paths (prose)`);
  });
  if (!log[0].prompt.includes('wave 1') || !log[0].prompt.includes('T108a')) problems.push('wave 1 prompt lacks its pointers');
  // one commit per wave over declared files only
  const w1 = res.waves[0], w2 = res.waves[1];
  const c1 = L.changedOf(repo.dir, w1.head), c2 = L.changedOf(repo.dir, w2.head);
  if (JSON.stringify(c1) !== JSON.stringify(['src/a.txt'])) problems.push('wave 1 changed ' + JSON.stringify(c1));
  if (JSON.stringify(c2) !== JSON.stringify(['src/b.txt'])) problems.push('wave 2 changed ' + JSON.stringify(c2));
  if (w1.head === w2.head) problems.push('waves did not each land their own commit');
  // completion records
  const recs = L.store.readWaveRecords(repo.dir);
  const r1 = recs.ok && recs.waves['T108fx/W1'], r2 = recs.ok && recs.waves['T108fx/W2'];
  if (!r1 || r1.head !== w1.head || !/^[0-9a-f]{64}$/.test(r1.refsPointer)) problems.push('W1 completion record malformed');
  if (!r2 || r2.head !== w2.head) problems.push('W2 completion record malformed');
  if (r1 && r1.noop === true) problems.push('W1 wrongly recorded as no-op');
  // composed equipage (argv + env, never executed)
  const spec = log[1];
  if (spec.argv[0] !== 'bwrap') problems.push('wave spawn not composed at the kernel tier: ' + spec.argv[0]);
  const at = spec.argv.findIndex((_, ix) => spec.argv[ix] === '--bind' && spec.argv[ix + 1] === spec.scratch && spec.argv[ix + 2] === spec.scratch);
  if (at < 0) problems.push('scratch not rw-bound in the wave frame');
  const gAt = spec.argv.findIndex((_, ix) => spec.argv[ix] === '--ro-bind' && spec.argv[ix + 2] === '/run/gos-grants.json');
  if (gAt < 0) problems.push('grant manifest not ro-bound at the fixed path');
  const term = spec.argv.indexOf('--');
  if (term < 0 || spec.argv[term + 1] !== 'opencode') problems.push('adapter command missing after --');
  if (spec.env.GOS_AUTO_SPAWNED !== '1' || spec.env.GOS_AUTO_SPAWN_ID !== spec.spawnId) problems.push('spawn id env missing');
  if (spec.env.GIT_AUTHOR_NAME !== 'gos-auto' || spec.env.GIT_AUTHOR_EMAIL !== 'gos-auto@invalid') problems.push('workspace identity env missing');
  if (spec.env.TESTBASE !== path.join(spec.scratch, 'testbed')) problems.push('testbed env missing');
  if (spec.stage !== 'BUILD' || spec.wave !== 2 || spec.unitLabel !== 'BUILD/W2') problems.push('wave spawn labels malformed');
  if (spec.tier !== 'bubblewrap' || spec.profile !== 'workspace') problems.push('wave spawn tier/profile wrong');
  // breaker: success streak reset, no trip
  const st = breaker.state();
  if (st.tripped || st.consecutive !== 0) problems.push('breaker state after two releases: ' + JSON.stringify(st));
  // prompt snapshot stamped and stable
  const ens = L.workers.ensureWavePromptRecorded(repo.dir);
  if (!ens.ok || ens.sha256 !== L.workers.wavePromptSourceHash()) problems.push('wave prompt stamp unstable');
  console.log(problems.length ? 'C1-BAD ' + problems.join('; ') : 'C1-OK');
  console.log('WAVES[' + res.waves.map((w) => w.wave + ':' + w.status).join(' ') + ']');
  console.log('SPAWNS[' + log.length + ']');
  console.log('PROMPT1[' + log[0].prompt.split('\n')[0] + ']');
})().catch((e) => { console.log('C1-BAD ' + e.message); process.exitCode = 1; });
EOF
C1_OUT="$(node "$T108_DIR/c1.cjs" 2>&1)"; RC=$?
t108_exit "happy-path probe runs clean" "0" "$RC"
t108_contains "two waves release on one declared commit each with pointer-only prompts" "C1-OK" "$C1_OUT"
t108_contains "wave statuses released" "WAVES[1:released 2:released]" "$C1_OUT"
t108_contains "exactly two spawns" "SPAWNS[2]" "$C1_OUT"
t108_contains "prompt first line carries wave + task pointers" "GOS auto BUILD wave 1 — tasks T108a." "$C1_OUT"

echo "C2: input-contract (template drift refuses before any spawn; token refusal)"
cat > "$T108_DIR/c2.cjs" <<'EOF'
const path = require('path');
const problems = [];
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
const repo = L.makeRepo(path.join(process.env.T108_DIR, 'c2-repo'), [[{ id: 'T108a', files: ['src/a.txt'] }]]);
(async () => {
  // drifted store stamp: an earlier run under a different template
  const seeded = L.store.saveSnapshot('wavePrompt', 'a drifted template {wave}', repo.dir);
  if (!seeded.ok) problems.push('seeding drifted snapshot refused');
  const log = [];
  const res = await L.workers.runWaveDispatch(repo.snapshot, L.ctxFor(repo, L.makeRunner(log, { kind: 'good' }), L.makeBreaker(3, 5, 100, repo.dir)));
  if (res.ok || res.reason !== 'prompt-template-drift') problems.push('drifted template not refused: ' + JSON.stringify(res.reason));
  if (log.length !== 0) problems.push('a spawn ran under a drifted template');
  // unsanctioned token: repo prose cannot ride in through the template
  const bad = L.workers.renderWavePrompt({ wave: 1, taskIds: ['T1'] }, 'work {wave} {taskIds} plus {repoProse}');
  if (bad.ok || bad.reason !== 'prompt-token-refused') problems.push('unsanctioned token not refused');
  const noIds = L.workers.renderWavePrompt({ wave: 1, taskIds: [] });
  if (noIds.ok) problems.push('empty taskIds accepted');
  // the shipped template carries exactly the two sanctioned tokens
  const tokens = [...L.workers.WAVE_PROMPT_TEMPLATE.matchAll(/\{([A-Za-z][A-Za-z\d]*)\}/g)].map((m) => m[1]);
  if (JSON.stringify([...new Set(tokens)].sort()) !== JSON.stringify(['taskIds', 'wave'])) problems.push('template tokens drifted: ' + tokens.join(','));
  console.log(problems.length ? 'C2-BAD ' + problems.join('; ') : 'C2-OK');
  console.log('DRIFT[' + res.reason + ']');
})().catch((e) => { console.log('C2-BAD ' + e.message); process.exitCode = 1; });
EOF
C2_OUT="$(node "$T108_DIR/c2.cjs" 2>&1)"; RC=$?
t108_exit "input-contract probe runs clean" "0" "$RC"
t108_contains "drifted template refuses the dispatch before any spawn" "C2-OK" "$C2_OUT"
t108_contains "refusal named" "DRIFT[prompt-template-drift]" "$C2_OUT"

# ---------------------------------------------------------------- C3 --
echo "C3: wave-negatives (undeclared-path, frozen-edit, second-commit, ref-move, dirty-drift)"
cat > "$T108_DIR/c3.cjs" <<'EOF'
const path = require('path');
const problems = [];
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
const CASES = [
  ['undeclared', 'undeclared-path'],
  ['frozen', 'frozen-edit'],
  ['second', 'second-commit'],
  ['refmove', 'ref-move'],
  ['dirty', 'dirty-drift'],
];
(async () => {
  const lines = [];
  for (const [kind, wantViolation] of CASES) {
    const repo = L.makeRepo(path.join(process.env.T108_DIR, 'c3-' + kind), [[{ id: 'T108a', files: ['src/a.txt'] }]]);
    const breaker = L.makeBreaker(3, 5, 100, repo.dir);
    const log = [];
    const res = await L.workers.runWaveDispatch(repo.snapshot, L.ctxFor(repo, L.makeRunner(log, { kind }), breaker));
    const w = res.waves[0] || {};
    if (res.ok || res.status !== 'held') lines.push(kind + ':not-held(status=' + res.status + ')');
    else if (w.violation !== wantViolation) lines.push(kind + ':violation=' + w.violation + '(want ' + wantViolation + ')');
    else {
      const recs = L.store.readWaveRecords(repo.dir);
      if (recs.ok && recs.waves['T108fx/W1']) lines.push(kind + ':record-written');
      if (breaker.state().consecutive !== 1) lines.push(kind + ':consecutive=' + breaker.state().consecutive);
    }
  }
  problems.push(...lines);
  console.log(problems.length ? 'C3-BAD ' + problems.join('; ') : 'C3-OK');
  for (const [kind, want] of CASES) {
    const repoDir = path.join(process.env.T108_DIR, 'c3-' + kind);
    console.log('NEG-' + kind + ':' + want);
  }
})().catch((e) => { console.log('C3-BAD ' + e.message); process.exitCode = 1; });
EOF
C3_OUT="$(node "$T108_DIR/c3.cjs" 2>&1)"; RC=$?
t108_exit "negatives probe runs clean" "0" "$RC"
t108_contains "all five negatives hold with their named violation, no record, one stage failure" "C3-OK" "$C3_OUT"
t108_contains "undeclared path classified" "NEG-undeclared:undeclared-path" "$C3_OUT"
t108_contains "frozen edit classified" "NEG-frozen:frozen-edit" "$C3_OUT"
t108_contains "second commit classified" "NEG-second:second-commit" "$C3_OUT"
t108_contains "ref move classified" "NEG-refmove:ref-move" "$C3_OUT"
t108_contains "dirty drift classified" "NEG-dirty:dirty-drift" "$C3_OUT"

# ---------------------------------------------------------------- C4 + C5 --
echo "C4: silence-hold (rc0, no commit, no no-op evidence — never rc0-no-advance)"
cat > "$T108_DIR/c4.cjs" <<'EOF'
const path = require('path');
const problems = [];
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
const repo = L.makeRepo(path.join(process.env.T108_DIR, 'c4-repo'), [[{ id: 'T108a', files: ['src/a.txt'] }]]);
const breaker = L.makeBreaker(3, 5, 100, repo.dir);
(async () => {
  const res = await L.workers.runWaveDispatch(repo.snapshot, L.ctxFor(repo, L.makeRunner([], { kind: 'nocommit' }), breaker));
  const w = res.waves[0] || {};
  if (res.ok || w.violation !== 'no-commit') problems.push('silence not held as no-commit: ' + JSON.stringify(w.violation));
  if (w.signal !== 'task-failed') problems.push('held wave signal ' + w.signal + ' — wave iterations never score rc0-no-advance');
  if (w.signal === 'rc0-no-advance') problems.push('rc0-no-advance leaked into wave scoring');
  if (breaker.state().consecutive !== 1) problems.push('silence did not count one stage failure');
  console.log(problems.length ? 'C4-BAD ' + problems.join('; ') : 'C4-OK');
  console.log('SIGNAL[' + w.signal + ':' + w.violation + ']');
})().catch((e) => { console.log('C4-BAD ' + e.message); process.exitCode = 1; });
EOF
C4_OUT="$(node "$T108_DIR/c4.cjs" 2>&1)"; RC=$?
t108_exit "silence probe runs clean" "0" "$RC"
t108_contains "rc0 silence holds as no-commit scoring task-failed" "C4-OK" "$C4_OUT"
t108_contains "wave signal pinned" "SIGNAL[task-failed:no-commit]" "$C4_OUT"

echo "C5: noop-release (evidenced no-op releases as wave-skipped-noop)"
cat > "$T108_DIR/c5.cjs" <<'EOF'
const path = require('path');
const problems = [];
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
const repo = L.makeRepo(path.join(process.env.T108_DIR, 'c5-repo'), [[{ id: 'T108a', files: ['src/a.txt'] }]]);
const breaker = L.makeBreaker(3, 5, 100, repo.dir);
(async () => {
  const before = L.headOf(repo.dir);
  const res = await L.workers.runWaveDispatch(repo.snapshot, L.ctxFor(repo, L.makeRunner([], { kind: 'noop' }), breaker));
  const w = res.waves[0] || {};
  if (!res.ok || w.status !== 'skipped-noop') problems.push('no-op wave not released as skipped-noop: ' + JSON.stringify(w.status));
  if (w.noop !== true || !/nothing to do/.test(String(w.noopReason))) problems.push('no-op reason not carried');
  const recs = L.store.readWaveRecords(repo.dir);
  const rec = recs.ok && recs.waves['T108fx/W1'];
  if (!rec || rec.noop !== true || !rec.noopReason) problems.push('no-op completion record malformed');
  if (L.headOf(repo.dir) !== before) problems.push('no-op wave moved the head');
  if (breaker.state().consecutive !== 0 || breaker.state().tripped) problems.push('no-op release counted as a failure');
  console.log(problems.length ? 'C5-BAD ' + problems.join('; ') : 'C5-OK');
  console.log('NOOP[' + w.status + ':' + (rec && rec.noopReason) + ']');
})().catch((e) => { console.log('C5-BAD ' + e.message); process.exitCode = 1; });
EOF
C5_OUT="$(node "$T108_DIR/c5.cjs" 2>&1)"; RC=$?
t108_exit "no-op probe runs clean" "0" "$RC"
t108_contains "evidenced no-op releases without counting a failure" "C5-OK" "$C5_OUT"
t108_contains "no-op record shape" "NOOP[skipped-noop:already landed upstream — nothing to do]" "$C5_OUT"

# ---------------------------------------------------------------- C6 --
echo "C6: table-roll (red-team-passed table edit rolls the stamp; findings hold)"
cat > "$T108_DIR/c6.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const problems = [];
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
function tableRepo(name) {
  const repo = L.makeRepo(path.join(process.env.T108_DIR, name), [[{ id: 'T108a', files: ['templates/auto-dispatch.json'] }]]);
  fs.mkdirSync(path.join(repo.dir, 'templates'), { recursive: true });
  fs.copyFileSync(path.join(process.env.GOS_ROOT, 'templates', 'auto-dispatch.json'), path.join(repo.dir, 'templates', 'auto-dispatch.json'));
  const { spawnSync } = require('child_process');
  spawnSync('git', ['add', 'templates/auto-dispatch.json'], { cwd: repo.dir });
  spawnSync('git', ['commit', '-q', '-m', 'seed table'], { cwd: repo.dir });
  return repo;
}
(async () => {
  // pass: findings 0 -> release + stamp roll
  const pass = tableRepo('c6-pass');
  const resPass = await L.workers.runWaveDispatch(pass.snapshot, L.ctxFor(pass, L.makeRunner([], { kind: 'table', rt: 'zero' }), L.makeBreaker(3, 5, 100, pass.dir)));
  const wp = resPass.waves[0] || {};
  if (!resPass.ok || wp.status !== 'released') problems.push('table wave not released: ' + JSON.stringify({ status: resPass.status, reason: resPass.reason, v: wp.violation }));
  if (wp.rolledTable !== true) problems.push('released table edit not marked rolledTable');
  const stampRead = L.store.readDispatchTableStamp(pass.dir);
  const liveSha = L.sha256Text(fs.readFileSync(path.join(pass.dir, 'templates', 'auto-dispatch.json'), 'utf8'));
  if (!stampRead.ok || !stampRead.stamp || stampRead.stamp.sha256 !== liveSha) problems.push('stamp does not pin the edited table');
  if (stampRead.stamp && stampRead.stamp.rolledByWave !== 'T108fx/W1') problems.push('rolledByWave not the wave key');
  // findings: round holds, no roll, no record
  const held = tableRepo('c6-held');
  const resHeld = await L.workers.runWaveDispatch(held.snapshot, L.ctxFor(held, L.makeRunner([], { kind: 'table', rt: 'findings' }), L.makeBreaker(3, 5, 100, held.dir)));
  const wh = resHeld.waves[0] || {};
  if (resHeld.ok || wh.violation !== 'redteam-findings') problems.push('findings round not held: ' + JSON.stringify(wh.violation));
  const st2 = L.store.readDispatchTableStamp(held.dir);
  if (st2.ok && st2.stamp != null) problems.push('stamp rolled despite findings');
  const recs2 = L.store.readWaveRecords(held.dir);
  if (recs2.ok && recs2.waves['T108fx/W1']) problems.push('completion record written despite findings');
  console.log(problems.length ? 'C6-BAD ' + problems.join('; ') : 'C6-OK');
  console.log('ROLL[' + wp.status + ':' + (stampRead.stamp ? stampRead.stamp.rolledByWave : 'none') + ']');
  console.log('HELD[' + wh.violation + ']');
})().catch((e) => { console.log('C6-BAD ' + e.message); process.exitCode = 1; });
EOF
C6_OUT="$(node "$T108_DIR/c6.cjs" 2>&1)"; RC=$?
t108_exit "table-roll probe runs clean" "0" "$RC"
t108_contains "zero round releases the table edit and rolls the stamp; findings hold without rolling" "C6-OK" "$C6_OUT"
t108_contains "stamp rolled by the wave key" "ROLL[released:T108fx/W1]" "$C6_OUT"
t108_contains "findings round held" "HELD[redteam-findings]" "$C6_OUT"

# ---------------------------------------------------------------- C7 --
echo "C7: crash-resume (adopt the attributable commit, release check only, no re-spawn)"
cat > "$T108_DIR/c7.cjs" <<'EOF'
const path = require('path');
const { spawnSync } = require('child_process');
const problems = [];
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
const repo = L.makeRepo(path.join(process.env.T108_DIR, 'c7-repo'), [
  [{ id: 'T108a', files: ['src/a.txt'] }],
  [{ id: 'T108b', files: ['src/b.txt'] }],
]);
(async () => {
  // crash: the runner dies at the post-spawn rev-list; the commit landed,
  // the marker + spawn survive, no completion record exists
  const crashGit = (args, cwd) => {
    if (args[0] === 'rev-list') return { status: 128, stdout: '', stderr: 'simulated crash mid-check' };
    return spawnSync('git', args, { cwd: cwd || repo.dir, encoding: 'utf8' });
  };
  const goodLog = [];
  const crashed = await L.workers.runWaveDispatch(repo.snapshot, L.ctxFor(repo, L.makeRunner(goodLog, { kind: 'good' }), L.makeBreaker(3, 5, 100, repo.dir), { gitRunner: crashGit }));
  if (crashed.ok || crashed.reason !== 'git-failed') problems.push('crash simulation not paused as git-failed: ' + JSON.stringify(crashed.reason));
  if (goodLog.length !== 1) problems.push('crash run spawn count ' + goodLog.length);
  const landed = L.headOf(repo.dir);
  // resume: reconcile adopts the attributable commit without spawning
  const rec = await L.workers.reconcileWaves(repo.snapshot, L.ctxFor(repo, L.throwingRunner(), L.makeBreaker(3, 5, 100, repo.dir)));
  const rw1 = rec.waves.find((w) => w.wave === 1), rw2 = rec.waves.find((w) => w.wave === 2);
  if (!rec.ok || !rw1 || rw1.action !== 'adopted' || rw1.head !== landed) {
    problems.push('wave 1 not adopted from the attributable commit: ' + JSON.stringify(rw1));
  }
  if (!rw2 || rw2.action !== 'not-started') problems.push('wave 2 not reported not-started: ' + JSON.stringify(rw2));
  const recs = L.store.readWaveRecords(repo.dir);
  if (!recs.ok || !recs.waves['T108fx/W1'] || recs.waves['T108fx/W1'].head !== landed) problems.push('adopted record missing');
  // re-dispatch: the completed wave re-runs only its release check; only
  // the remaining wave spawns
  const log2 = [];
  const again = await L.workers.runWaveDispatch(repo.snapshot, L.ctxFor(repo, L.makeRunner(log2, { kind: 'good' }), L.makeBreaker(3, 5, 100, repo.dir)));
  if (!again.ok || again.status !== 'complete') problems.push('re-dispatch not complete: ' + JSON.stringify({ status: again.status, reason: again.reason }));
  const aw1 = again.waves.find((w) => w.wave === 1), aw2 = again.waves.find((w) => w.wave === 2);
  if (!aw1 || aw1.status !== 'already-released') problems.push('completed wave re-ran instead of release-checking: ' + JSON.stringify(aw1));
  if (!aw2 || aw2.status !== 'released') problems.push('remaining wave not driven: ' + JSON.stringify(aw2));
  if (log2.length !== 1) problems.push('re-dispatch spawned ' + log2.length + ' waves (want 1)');
  console.log(problems.length ? 'C7-BAD ' + problems.join('; ') : 'C7-OK');
  console.log('ADOPT[' + (rw1 && rw1.action) + ':' + String(rw1 && rw1.head).slice(0, 10) + ']');
  console.log('REDISPATCH[' + (aw1 && aw1.status) + ',' + (aw2 && aw2.status) + ':' + log2.length + ']');
})().catch((e) => { console.log('C7-BAD ' + e.message); process.exitCode = 1; });
EOF
C7_OUT="$(node "$T108_DIR/c7.cjs" 2>&1)"; RC=$?
t108_exit "crash-resume probe runs clean" "0" "$RC"
t108_contains "reconcile adopts the attributable commit, never re-spawns" "C7-OK" "$C7_OUT"
t108_contains "adoption action + head" "ADOPT[adopted:" "$C7_OUT"
t108_contains "re-dispatch release-checks wave 1 and drives wave 2" "REDISPATCH[already-released,released:1]" "$C7_OUT"

# ---------------------------------------------------------------- C8 --
echo "C8: completion-rerun (existing records release-check only; runner never invoked)"
cat > "$T108_DIR/c8.cjs" <<'EOF'
const path = require('path');
const problems = [];
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
const repo = L.makeRepo(path.join(process.env.T108_DIR, 'c8-repo'), [
  [{ id: 'T108a', files: ['src/a.txt'] }],
  [{ id: 'T108b', files: ['src/b.txt'] }],
]);
(async () => {
  const first = await L.workers.runWaveDispatch(repo.snapshot, L.ctxFor(repo, L.makeRunner([], { kind: 'good' }), L.makeBreaker(3, 5, 100, repo.dir)));
  if (!first.ok) problems.push('fixture run not green');
  const rec = await L.workers.reconcileWaves(repo.snapshot, L.ctxFor(repo, L.throwingRunner(), L.makeBreaker(3, 5, 100, repo.dir)));
  if (!rec.ok) problems.push('reconcile not green: ' + JSON.stringify(rec.waves));
  const actions = rec.waves.map((w) => w.wave + ':' + w.action).join(' ');
  if (actions !== '1:release-checked 2:release-checked') problems.push('actions not release-checked: ' + actions);
  console.log(problems.length ? 'C8-BAD ' + problems.join('; ') : 'C8-OK');
  console.log('ACTIONS[' + actions + ']');
})().catch((e) => { console.log('C8-BAD ' + e.message); process.exitCode = 1; });
EOF
C8_OUT="$(node "$T108_DIR/c8.cjs" 2>&1)"; RC=$?
t108_exit "completion-rerun probe runs clean" "0" "$RC"
t108_contains "recorded waves re-run only the release check without spawning" "C8-OK" "$C8_OUT"
t108_contains "both waves release-checked" "ACTIONS[1:release-checked 2:release-checked]" "$C8_OUT"

# ---------------------------------------------------------------- C9 --
echo "C9: breaker-k (five distinct waves never trip K; one wave re-entered five times does)"
cat > "$T108_DIR/c9.cjs" <<'EOF'
const path = require('path');
const problems = [];
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
(async () => {
  // five healthy distinct waves, K=5: each label visited once, no trip
  const five = L.makeRepo(path.join(process.env.T108_DIR, 'c9-five'), [
    [{ id: 'T1a', files: ['src/w1.txt'] }],
    [{ id: 'T1b', files: ['src/w2.txt'] }],
    [{ id: 'T1c', files: ['src/w3.txt'] }],
    [{ id: 'T1d', files: ['src/w4.txt'] }],
    [{ id: 'T1e', files: ['src/w5.txt'] }],
  ]);
  const healthy = L.makeBreaker(3, 5, 100, five.dir);
  const res5 = await L.workers.runWaveDispatch(five.snapshot, L.ctxFor(five, L.makeRunner([], { kind: 'good' }), healthy));
  if (!res5.ok || res5.status !== 'complete') problems.push('five-wave run not complete: ' + JSON.stringify({ status: res5.status, reason: res5.reason }));
  const st5 = healthy.state();
  if (st5.tripped) problems.push('five distinct waves tripped K: ' + JSON.stringify(st5.tripped));
  const visits = Object.values(st5.visits);
  if (visits.length !== 5 || !visits.every((v) => v === 1)) problems.push('visit counts not one per label: ' + JSON.stringify(st5.visits));
  // one stuck wave re-entered five times under one breaker: K trips on the label
  const stuck = L.makeRepo(path.join(process.env.T108_DIR, 'c9-stuck'), [[{ id: 'T1a', files: ['src/w1.txt'] }]]);
  const stuckBreaker = L.makeBreaker(10, 5, 100, stuck.dir);
  let last = null;
  for (let i = 1; i <= 5; i += 1) {
    last = await L.workers.runWaveDispatch(stuck.snapshot, L.ctxFor(stuck, L.makeRunner([], { kind: 'nocommit' }), stuckBreaker));
  }
  if (last.ok || last.reason !== 'breaker-tripped') problems.push('fifth re-entry not breaker-tripped: ' + JSON.stringify(last.reason));
  const trip = last.trip || (stuckBreaker.tripped && stuckBreaker.tripped());
  if (!trip || trip.layer !== 'K' || !/re-entered 5/.test(trip.reason)) {
    problems.push('trip is not K on the wave label: ' + JSON.stringify(trip));
  }
  console.log(problems.length ? 'C9-BAD ' + problems.join('; ') : 'C9-OK');
  console.log('HEALTHY[tripped:' + JSON.stringify(st5.tripped) + ']');
  console.log('STUCK[' + (trip ? trip.layer + ' ' + trip.reason : 'none') + ']');
})().catch((e) => { console.log('C9-BAD ' + e.message); process.exitCode = 1; });
EOF
C9_OUT="$(node "$T108_DIR/c9.cjs" 2>&1)"; RC=$?
t108_exit "breaker-k probe runs clean" "0" "$RC"
t108_contains "five distinct waves stay untripped; five re-entries trip K on the label" "C9-OK" "$C9_OUT"
t108_contains "healthy run never trips" "HEALTHY[tripped:null]" "$C9_OUT"
t108_contains "stuck wave trips layer K" "stage BUILD/W1: re-entered 5 times" "$C9_OUT"

# ---------------------------------------------------------------- C10 --
echo "C10: breaker-n (three consecutive failed waves trip N as one stage streak)"
cat > "$T108_DIR/c10.cjs" <<'EOF'
const path = require('path');
const problems = [];
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
(async () => {
  // the driver stops at the first held wave (sequential: nothing builds on
  // a broken wave), so the stage streak accumulates across re-entries —
  // exactly the loop's consecutive-layer semantics
  const repo = L.makeRepo(path.join(process.env.T108_DIR, 'c10-repo'), [[{ id: 'T1a', files: ['src/w1.txt'] }]]);
  const breaker = L.makeBreaker(3, 50, 100, repo.dir);
  const held = [];
  let last = null;
  for (let i = 1; i <= 3; i += 1) {
    last = await L.workers.runWaveDispatch(repo.snapshot, L.ctxFor(repo, L.makeRunner([], { kind: 'nocommit' }), breaker));
    if (last.status === 'held') held.push(last.waves[0]);
  }
  if (held.length !== 2) problems.push('first two re-entries not held: ' + held.length);
  if (held.some((w) => w.violation !== 'no-commit')) problems.push('held violations not no-commit');
  if (last.ok || last.reason !== 'breaker-tripped') problems.push('third failed wave did not pause breaker-tripped: ' + JSON.stringify(last.reason));
  const trip = last.trip;
  if (!trip || trip.layer !== 'N') problems.push('trip layer is not N: ' + JSON.stringify(trip));
  const st = breaker.state();
  if (st.consecutive !== 3) problems.push('stage streak not three: ' + st.consecutive);
  // the K layer stayed out of it: the wave label was visited 3x under K=50
  if (st.visits['BUILD/W1'] !== 3) problems.push('wave label visits not three: ' + JSON.stringify(st.visits));
  if (trip && /re-entered/.test(trip.reason)) problems.push('trip reason is a K re-entry trip: ' + trip.reason);
  console.log(problems.length ? 'C10-BAD ' + problems.join('; ') : 'C10-OK');
  console.log('TRIP[' + (trip ? trip.layer : 'none') + ' consecutive:' + st.consecutive + ']');
})().catch((e) => { console.log('C10-BAD ' + e.message); process.exitCode = 1; });
EOF
C10_OUT="$(node "$T108_DIR/c10.cjs" 2>&1)"; RC=$?
t108_exit "breaker-n probe runs clean" "0" "$RC"
t108_contains "three consecutive failed waves trip N while K labels stay at one visit" "C10-OK" "$C10_OUT"
t108_contains "stage streak pinned" "TRIP[N consecutive:3]" "$C10_OUT"

# ---------------------------------------------------------------- C11 --
echo "C11: store-shapes (record conflicts, corrupt waves keys, stamp validation)"
cat > "$T108_DIR/c11.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const problems = [];
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
const repo = L.makeRepo(path.join(process.env.T108_DIR, 'c11-repo'), [[{ id: 'T108a', files: ['src/a.txt'] }]]);
(async () => {
  const rec = L.store.recordWaveCompletion(repo.dir, { task: 'T108fx', wave: 1, head: '0123456789abcdef0123456789abcdef01234567', refsPointer: 'f'.repeat(64) });
  if (!rec.ok) problems.push('record refused: ' + rec.reason);
  const again = L.store.recordWaveCompletion(repo.dir, { task: 'T108fx', wave: 1, head: '0123456789abcdef0123456789abcdef01234567', refsPointer: 'f'.repeat(64) });
  if (!again.ok) problems.push('identical re-record refused');
  const conflict = L.store.recordWaveCompletion(repo.dir, { task: 'T108fx', wave: 1, head: 'fedcba9876543210fedcba9876543210fedcba98', refsPointer: 'f'.repeat(64) });
  if (conflict.ok || conflict.reason !== 'wave-record-conflict') problems.push('conflicting re-record not refused');
  const badStamp = L.store.rollDispatchTableStamp(repo.dir, { sha256: 'a'.repeat(64), rolledByWave: 'not-a-wave-key' });
  if (badStamp.ok) problems.push('malformed rolledByWave accepted');
  const goodStamp = L.store.rollDispatchTableStamp(repo.dir, { sha256: 'a'.repeat(64), rolledByWave: 'T108fx/W1' });
  if (!goodStamp.ok || !goodStamp.stamp.rolledAtIso) problems.push('valid roll refused');
  // run-start provenance: the loop's load-time stamp records '<runTag>/start'
  const startStamp = L.store.rollDispatchTableStamp(repo.dir, { sha256: 'b'.repeat(64), rolledByWave: 'run0a1b2c3d/start' });
  if (!startStamp.ok || startStamp.stamp.rolledByWave !== 'run0a1b2c3d/start') problems.push('run-start stamp refused: ' + JSON.stringify(startStamp.reason));
  const badStart = L.store.rollDispatchTableStamp(repo.dir, { sha256: 'b'.repeat(64), rolledByWave: 'run0a1b2c3d/started' });
  if (badStart.ok) problems.push('non-/start provenance accepted');
  // the prompt snapshot kind is part of the closed set (before corruption)
  const seeded = L.store.saveSnapshot('wavePrompt', 'x', repo.dir);
  if (!seeded.ok) problems.push('wavePrompt snapshot kind refused');
  // malformed waves key reads the whole store as corrupt (fail closed)
  const file = L.store.load(repo.dir).path;
  const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
  raw.waves['bad key'] = { head: 'x', refsPointer: 'y', releasedAtIso: 'z' };
  fs.writeFileSync(file, JSON.stringify(raw));
  const loaded = L.store.load(repo.dir);
  if (loaded.ok || loaded.reason !== 'corrupt') problems.push('malformed waves key not corrupt: ' + JSON.stringify(loaded.reason));
  console.log(problems.length ? 'C11-BAD ' + problems.join('; ') : 'C11-OK');
  console.log('CONFLICT[' + conflict.reason + ']');
})().catch((e) => { console.log('C11-BAD ' + e.message); process.exitCode = 1; });
EOF
C11_OUT="$(node "$T108_DIR/c11.cjs" 2>&1)"; RC=$?
t108_exit "store-shapes probe runs clean" "0" "$RC"
t108_contains "record conflicts refuse, malformed waves keys read corrupt, stamp validates" "C11-OK" "$C11_OUT"
t108_contains "conflict reason named" "CONFLICT[wave-record-conflict]" "$C11_OUT"

# ---------------------------------------------------------------- C12 --
echo "C12: unit-labels (closed enum, digit rule, visit validation)"
cat > "$T108_DIR/c12.cjs" <<'EOF'
const path = require('path');
const problems = [];
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
const b = L.breakerMod;
if (b.waveUnitLabel(3) !== 'BUILD/W3') problems.push('waveUnitLabel(3) not BUILD/W3');
if (b.waveUnitLabel(0) !== null || b.waveUnitLabel('3') !== null || b.waveUnitLabel(1.5) !== null) {
  problems.push('waveUnitLabel accepts non-positive-integer waves');
}
for (const bad of ['BUILD/W', 'BUILD/w3', 'BUILD/W03a', 'THINK/W1', 'BUILD/W-1', 'BUILD/W 3']) {
  if (b.isWaveUnitLabel(bad)) problems.push('isWaveUnitLabel accepted ' + bad);
}
if (!b.isWaveUnitLabel('BUILD/W12')) problems.push('isWaveUnitLabel rejected BUILD/W12');
const made = b.createBreaker({ limits: { N: 3, K: 5, B: 10 } });
for (const bad of ['BUILD/W', 'THINK/W1', 'BUILD/w3']) {
  const v = made.breaker.visit(bad);
  if (v.ok || v.reason !== 'invalid-stage') problems.push('visit accepted ' + bad);
}
const v3 = made.breaker.visit('BUILD/W3');
if (!v3.ok || v3.visits !== 1) problems.push('valid unit label not accepted');
console.log(problems.length ? 'C12-BAD ' + problems.join('; ') : 'C12-OK');
console.log('LABEL[' + b.waveUnitLabel(3) + ']');
EOF
C12_OUT="$(node "$T108_DIR/c12.cjs" 2>&1)"; RC=$?
t108_exit "unit-label probe runs clean" "0" "$RC"
t108_contains "closed enum + digit rule + visit validation hold" "C12-OK" "$C12_OUT"
t108_contains "label derivation pinned" "BUILD/W3" "$C12_OUT"

# ---------------------------------------------------------------- C13 --
echo "C13: loop-wired waves (the auto loop drives BUILD through the wave driver)"
cat > "$T108_DIR/c13.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
const loop = require(path.join(GR, 'bin/lib/ops/auto/loop.cjs'));
const problems = [];
const dir = path.join(process.env.T108_DIR, 'c13-repo');
fs.mkdirSync(path.join(dir, '.gos'), { recursive: true });
const specFile = path.join(dir, 'task', 'fx', 'spec.md');
fs.mkdirSync(path.dirname(specFile), { recursive: true });
fs.writeFileSync(specFile, '# c13 spec\n');
fs.writeFileSync(path.join(dir, '.gitignore'), '.gos/\n');
const git = (args) => { const r = spawnSync('git', args, { cwd: dir, encoding: 'utf8' }); if (r.status !== 0) throw new Error(`git ${args.join(' ')}: ${r.stderr}`); return String(r.stdout || ''); };
git(['init', '-q', '-b', 'work']);
git(['add', '-A']);
git(['commit', '-q', '-m', 'fixture seed']);
// task_head anchors the real diff baseline; the task id derives from it the
// way currentTaskId does, so the work branch and wave-record keys line up.
const rootCommit = git(['rev-parse', 'HEAD']).trim();
const TASKID = rootCommit.slice(0, 8);
git(['checkout', '-q', '-b', `auto/${TASKID}`]);
const snapshot = {
  tasks: [
    { id: 'T13a', covers: [], files: ['src/w1.txt'], wave: 1 },
    { id: 'T13b', covers: [], files: ['src/w2.txt'], wave: 2 },
  ],
  audit: [],
  meta: { waveValidation: { ok: true, waves: 2 } },
};
fs.writeFileSync(path.join(dir, '.gos', 'state.json'), JSON.stringify({
  schema_version: 6, level: 3, current_stage: 'BUILD', completed_stages: ['INTENT', 'THINK', 'PLAN'],
  intent: { summary: 'c13', confirmed: true },
  task_head: rootCommit,
  spec_path: 'task/fx/spec.md', spec_sha256: crypto.createHash('sha256').update('# c13 spec\n').digest('hex'),
  plan_snapshot: snapshot,
  requirements: [], decisions: [], observable_truths: [], gaps: [], checkpoints: [], approvals: {},
}, null, 2));
const created = L.store.create({ rootDir: dir, mode: 'on', limits: { N: 3, K: 5, B: 100 } });
if (!created.ok) throw new Error('store refused: ' + created.reason);
const seen = [];
function gosCommit(stage, specEnv) {
  const sr = require(path.join(GR, 'bin/lib/core/spawnreg.cjs'));
  fs.writeFileSync(path.join(dir, '.gos', '.lock'), JSON.stringify({ pid: process.pid, started_at: new Date().toISOString(), boot_id: null, starttime: sr.procStartTime(process.pid) }));
  const r = spawnSync(process.execPath, [path.join(GR, 'bin', 'gos.cjs'), 'commit', stage], {
    cwd: dir,
    env: { ...process.env, GOS_AUTO_SPAWNED: '1', GOS_AUTO_SPAWN_ID: specEnv.GOS_AUTO_SPAWN_ID, GOS_AUTO_APPROVALS_BASELINE: specEnv.GOS_AUTO_APPROVALS_BASELINE },
    encoding: 'utf8',
  });
  try { fs.unlinkSync(path.join(dir, '.gos', '.lock')); } catch { /* gone */ }
  return r;
}
const spawnRunner = (spec) => {
  seen.push(spec);
  if (spec.roWorkspace) return { status: 0, stdout: 'REDTEAM-FINDINGS: 0\n', stderr: '' };
  if (Number.isInteger(spec.wave)) {
    for (const p of spec.declaredFiles) {
      const abs = path.join(dir, p);
      fs.mkdirSync(path.dirname(abs), { recursive: true });
      fs.writeFileSync(abs, `wave ${spec.wave} content\n`);
    }
    git(['add', ...spec.declaredFiles]);
    git(['commit', '-q', '-m', `wave ${spec.wave} work`]);
    return { status: 0, stdout: `wave ${spec.wave} done\n`, stderr: '' };
  }
  if (spec.stageExit) {
    const r = gosCommit('build', spec.env);
    if (r.status !== 0) problems.push(`advance build rc=${r.status}: ${String(r.stderr || r.stdout).slice(0, 300)}`);
    return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
  }
  return { status: 0, stdout: '{"type":"result"}\n', stderr: '' };
};
(async () => {
  const env = { ...process.env, GOS_AUTO_TEST_FIXTURE: '1' };
  const r = await loop.createLoop({
    rootDir: dir, host: 'gos-fixture-host', env, maxIterations: 1, spawnRunner,
    engineProbe: () => ({ engine: 'bwrap', version: '0.11.0' }),
    modelResolver: () => ({ model: 'zai/glm-5.3' }),
  }).loop.run();
  if (r.status !== 'iteration-cap' || r.ok !== true) problems.push('run did not end at the cap: ' + r.status + '/' + r.reason + (r.detail ? ':' + String(r.detail).slice(0, 160) : ''));
  const bi = (r.iterations || []).find((i) => i.stage === 'BUILD');
  if (!bi || bi.signal !== 'advanced') problems.push('BUILD iteration not advanced: ' + JSON.stringify(bi && bi.signal));
  if (bi && (!Array.isArray(bi.waves) || bi.waves.length !== 2 || bi.waves.some((w) => w.status !== 'released'))) {
    problems.push('BUILD iteration lacks the released-wave summary: ' + JSON.stringify(bi && bi.waves));
  }
  const stateAfter = JSON.parse(fs.readFileSync(path.join(dir, '.gos', 'state.json'), 'utf8'));
  if (stateAfter.current_stage !== 'REVIEW') problems.push('stage did not move to REVIEW: ' + stateAfter.current_stage);
  const subj = spawnSync('git', ['log', '-1', '--format=%s'], { cwd: dir, encoding: 'utf8' });
  if (!/^chore\(task\): advance build\b/.test(String(subj.stdout || ''))) problems.push('HEAD is not the labeled advance commit: ' + String(subj.stdout).slice(0, 60));
  // wave completion records through the loop
  const recs = L.store.readWaveRecords(dir);
  if (!recs.ok || !recs.waves[`${TASKID}/W1`] || !recs.waves[`${TASKID}/W2`]) problems.push('wave records missing: ' + JSON.stringify(Object.keys(recs.waves || {})));
  // run-start table stamp: pins the loaded file with run-start provenance
  const tableFile = path.join(GR, 'templates', 'auto-dispatch.json');
  const stampRead = L.store.readDispatchTableStamp(dir);
  const liveSha = crypto.createHash('sha256').update(fs.readFileSync(tableFile)).digest('hex');
  if (!stampRead.ok || !stampRead.stamp || stampRead.stamp.sha256 !== liveSha) problems.push('run-start stamp does not pin the live table');
  if (stampRead.stamp && !/\/start$/.test(stampRead.stamp.rolledByWave)) problems.push('run-start stamp provenance not <runTag>/start: ' + stampRead.stamp.rolledByWave);
  // wave spawns: driver prompts + baseline env; advance spawn: model pin + equipage
  const waveSpecs = seen.filter((s) => Number.isInteger(s.wave));
  if (waveSpecs.length !== 2) problems.push('wave spawn count ' + waveSpecs.length + ' != 2');
  for (const ws of waveSpecs) {
    const want = L.workers.renderWavePrompt({ wave: ws.wave, taskIds: ws.wave === 1 ? ['T13a'] : ['T13b'] });
    if (!want.ok || ws.prompt !== want.prompt) problems.push(`wave ${ws.wave} prompt is not the pointer-only render`);
    if (!ws.env.GOS_AUTO_APPROVALS_BASELINE) problems.push(`wave ${ws.wave} spawn lacks the approvals baseline env`);
  }
  const adv = seen.find((s) => s.stageExit === true);
  if (!adv) problems.push('no stage-exit advance spawn');
  else {
    const i = adv.argv.indexOf('--model');
    if (i < 0 || adv.argv[i + 1] !== 'zai/glm-5.3') problems.push('advance spawn lacks the resolved --model argv');
    if (adv.env.GIT_AUTHOR_NAME !== 'gos-auto') problems.push('advance spawn lacks the runner git identity');
  }
  if (bi) {
    const st = L.store.load(dir);
    const stamp = st.ok ? st.store.stamps[bi.spawnId] : null;
    if (!stamp || stamp.modelPinned !== 'zai/glm-5.3') problems.push('advance stamp lacks the pinned-model telemetry');
  }
  if (r.breaker && r.breaker.tripped) problems.push('breaker tripped on a green run');
  console.log(problems.length ? 'C13-BAD ' + problems.join('; ') : 'C13-OK');
  console.log('ITER[' + (bi && bi.signal) + ' waves:' + (bi && bi.waves ? bi.waves.map((w) => w.status).join(',') : 'none') + ']');
  console.log('STAGE[' + stateAfter.current_stage + ']');
  console.log('STAMP[' + (stampRead.stamp ? stampRead.stamp.rolledByWave.slice(-6) : 'none') + ']');
})().catch((e) => { console.log('C13-BAD ' + e.message); process.exitCode = 1; });
EOF
C13_OUT="$(node "$T108_DIR/c13.cjs" 2>&1)"; RC=$?
t108_exit "loop-wired wave probe runs clean" "0" "$RC"
t108_contains "the loop drives BUILD waves, exits through one advance spawn, stamps the run-start table" "C13-OK" "$C13_OUT"
t108_contains "BUILD iteration advanced over two released waves" "ITER[advanced waves:released,released]" "$C13_OUT"
t108_contains "stage moved past BUILD" "STAGE[REVIEW]" "$C13_OUT"
t108_contains "run-start stamp provenance" "STAMP[/start]" "$C13_OUT"

# ---------------------------------------------------------------- C14 --
echo "C14: wave-env (credential-class entries never reach a wave spawn env)"
cat > "$T108_DIR/c14.cjs" <<'EOF'
const path = require('path');
const problems = [];
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
const repo = L.makeRepo(path.join(process.env.T108_DIR, 'c14-repo'), [[{ id: 'T108a', files: ['src/a.txt'] }]]);
const log = [];
// The loop env carries planted credentials (as a compromised or CI-loaded
// environment would): the wave compose must not pass them through as an
// unsanitized adapter env overlay.
const planted = {
  ...process.env,
  GH_TOKEN: 'planted-gh-token',
  GITHUB_ENTERPRISE_TOKEN: 'planted-ghe',
  AWS_SECRET_ACCESS_KEY: 'planted-aws-secret',
  GITHUB_DEPLOY_KEY: 'planted-deploy-key',
  GOS_C14_MARKER: 'carries',
};
(async () => {
  const res = await L.workers.runWaveDispatch(repo.snapshot, L.ctxFor(repo, L.makeRunner(log, { kind: 'good' }), L.makeBreaker(3, 5, 100, repo.dir), { env: planted }));
  if (!res.ok || res.status !== 'complete') problems.push('dispatch not complete: ' + JSON.stringify({ ok: res.ok, status: res.status, reason: res.reason, detail: res.detail }));
  if (log.length !== 1) problems.push('spawn count ' + log.length + ' != 1');
  const spec = log[0];
  for (const k of ['GH_TOKEN', 'GITHUB_ENTERPRISE_TOKEN', 'AWS_SECRET_ACCESS_KEY', 'GITHUB_DEPLOY_KEY']) {
    if (spec.env[k] !== undefined) problems.push(k + ' leaked into the wave spawn env');
  }
  if (spec.env.GOS_C14_MARKER !== 'carries') problems.push('benign overlay entry dropped from the wave spawn env');
  if (spec.env.GOS_ROOT !== process.env.GOS_ROOT) problems.push('loop env base lost from the wave spawn env');
  console.log(problems.length ? 'C14-BAD ' + problems.join('; ') : 'C14-OK');
  console.log('ENV[' + (spec.env.GH_TOKEN === undefined ? 'clean' : 'leaked') + ' marker:' + (spec.env.GOS_C14_MARKER || 'gone') + ']');
})().catch((e) => { console.log('C14-BAD ' + e.message); process.exitCode = 1; });
EOF
C14_OUT="$(node "$T108_DIR/c14.cjs" 2>&1)"; RC=$?
t108_exit "wave-env probe runs clean" "0" "$RC"
t108_contains "credential-class env entries never reach the wave spawn" "C14-OK" "$C14_OUT"
t108_contains "planted credentials stripped, benign overlay survives" "ENV[clean marker:carries]" "$C14_OUT"

# ---------------------------------------------------------------- C15 --
echo "C15: deny-flood (one deny line flooded out of the capture window still holds)"
cat > "$T108_DIR/c15.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const problems = [];
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
const repo = L.makeRepo(path.join(process.env.T108_DIR, 'c15-repo'), [[{ id: 'T108a', files: ['src/a.txt'] }]]);
// The spawn lands a perfect-looking wave commit, then its stream carries one
// deny line (captured by the streaming scanner) followed by a huge benign
// tail that pushes the line out of every captured window. The post-hoc scan
// of the captured text finds nothing; only the pre-truncation hits hold it.
const denyFloodRunner = async function (spec) {
  const git = (args) => { const r = spawnSync('git', args, { cwd: spec.cwd, encoding: 'utf8' }); if (r.status !== 0) throw new Error(r.stderr); return String(r.stdout || ''); };
  for (const p of spec.declaredFiles) {
    const abs = path.join(spec.cwd, p);
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    fs.writeFileSync(abs, 'wave content\n');
  }
  git(['add', ...spec.declaredFiles]);
  git(['commit', '-q', '-m', 'flooded wave']);
  return {
    status: 0,
    stdout: 'benign progress line\n'.repeat(60000),
    stderr: '',
    preTruncationDenyHits: [{ pattern: 'sudo', match: 'sudo', kind: 'command', line: 'escalating with sudo to break out' }],
    windowHead: { stdout: 'head-bytes-of-stream', stderr: '' },
    windowTail: { stdout: 'tail-bytes-of-stream', stderr: '' },
  };
};
(async () => {
  const res = await L.workers.runWaveDispatch(repo.snapshot, L.ctxFor(repo, denyFloodRunner, L.makeBreaker(3, 5, 100, repo.dir)));
  const w = res.waves[0] || {};
  if (res.ok || res.status !== 'held') problems.push('flooded deny wave not held: ' + JSON.stringify({ status: res.status, reason: res.reason }));
  if (w.violation !== 'deny-hit') problems.push('violation is ' + JSON.stringify(w.violation) + ' — the flooded deny line escaped scoring');
  if (/sudo/.test(String(res.waves[0] && res.waves[0].detail)) !== true) problems.push('held detail does not name the deny pattern');
  const st = L.store.load(repo.dir);
  const stamps = st.ok ? st.store.stamps : {};
  const spawnIds = Object.keys(stamps).filter((k) => stamps[k].stage === 'BUILD');
  const stamp = spawnIds.length ? stamps[spawnIds[0]] : null;
  if (!stamp) problems.push('wave spawn not stamped');
  else {
    if (stamp.denyHits !== 1) problems.push('stamp denyHits telemetry is ' + JSON.stringify(stamp.denyHits) + ' (want 1)');
    const winDir = path.join(L.store.storeRoot(repo.dir), 'windows');
    for (const sfx of ['head', 'tail']) {
      if (!fs.existsSync(path.join(winDir, `${spawnIds[0]}.${sfx}.txt`))) problems.push(sfx + ' window sidecar missing for the wave spawn');
    }
  }
  const recs = L.store.readWaveRecords(repo.dir);
  if (recs.ok && recs.waves['T108fx/W1']) problems.push('deny-held wave wrote a completion record');
  console.log(problems.length ? 'C15-BAD ' + problems.join('; ') : 'C15-OK');
  console.log('FLOOD[' + (w.violation || res.reason) + ' denyHits:' + (stamp ? stamp.denyHits : 'none') + ']');
})().catch((e) => { console.log('C15-BAD ' + e.message); process.exitCode = 1; });
EOF
C15_OUT="$(node "$T108_DIR/c15.cjs" 2>&1)"; RC=$?
t108_exit "deny-flood probe runs clean" "0" "$RC"
t108_contains "pre-truncation deny hits hold the wave despite the benign flood" "C15-OK" "$C15_OUT"
t108_contains "deny hit classified with telemetry" "FLOOD[deny-hit denyHits:1]" "$C15_OUT"

# ---------------------------------------------------------------- C16 --
echo "C16: held-vs-crash (store-side held records and start evidence; scratch markers are inert)"
cat > "$T108_DIR/c16.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const problems = [];
const L = require(path.join(process.env.T108_DIR, 't108-lib.cjs'));
const spawnreg = require(path.join(process.env.GOS_ROOT, 'bin/lib/core/spawnreg.cjs'));
const git = (cwd, args) => {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} rc=${r.status}: ${r.stderr}`);
  return String(r.stdout || '');
};
(async () => {
  // ---- held wave: store-side held record, no crash shape, never adopted
  const heldRepo = L.makeRepo(path.join(process.env.T108_DIR, 'c16-held'), [[{ id: 'T108a', files: ['src/a.txt'] }]]);
  const denyRunner = async function (spec) {
    for (const p of spec.declaredFiles) {
      const abs = path.join(spec.cwd, p);
      fs.mkdirSync(path.dirname(abs), { recursive: true });
      fs.writeFileSync(abs, 'deny wave content\n');
    }
    git(spec.cwd, ['add', ...spec.declaredFiles]);
    git(spec.cwd, ['commit', '-q', '-m', 'deny wave work']);
    // A real escape attempt: the deny verb sits inside a bash command field,
    // not in echoed prose — only command-kind hits hold a wave.
    const ev = JSON.stringify({ type: 'tool_use', part: { type: 'tool', tool: 'bash', state: { status: 'completed', input: { command: 'sudo breakout attempt' } } } });
    return { status: 0, stdout: `doing work\n${ev}\n`, stderr: '' };
  };
  const held = await L.workers.runWaveDispatch(heldRepo.snapshot, L.ctxFor(heldRepo, denyRunner, L.makeBreaker(3, 5, 100, heldRepo.dir)));
  if (held.ok || (held.waves[0] || {}).violation !== 'deny-hit') problems.push('deny wave not held: ' + JSON.stringify({ status: held.status, v: held.waves[0] && held.waves[0].violation }));
  if (typeof L.store.readHeldWaves !== 'function') problems.push('store exposes no readHeldWaves');
  else {
    const heldRead = L.store.readHeldWaves(heldRepo.dir);
    const rec = heldRead.ok && heldRead.heldWaves['T108fx/W1'];
    if (!rec || rec.reason !== 'deny-hit' || !rec.spawnId) problems.push('held record malformed: ' + JSON.stringify(rec));
  }
  // the held spawn is torn down: no scratch survives to masquerade as a crash
  const startReadHeld = typeof L.store.readWaveStarts === 'function' ? L.store.readWaveStarts(heldRepo.dir) : { ok: false };
  const heldSpawnId = startReadHeld.ok && startReadHeld.waveStarts['T108fx/W1'] ? startReadHeld.waveStarts['T108fx/W1'].spawnId : null;
  if (heldSpawnId && fs.existsSync(spawnreg.scratchPath(heldRepo.dir, heldSpawnId))) problems.push('held wave left its scratch (crash shape)');
  const recsHeld = L.store.readWaveRecords(heldRepo.dir);
  if (recsHeld.ok && recsHeld.waves['T108fx/W1']) problems.push('held wave wrote a completion record');
  const recHeld = await L.workers.reconcileWaves(heldRepo.snapshot, L.ctxFor(heldRepo, L.throwingRunner(), L.makeBreaker(3, 5, 100, heldRepo.dir)));
  const rh1 = (recHeld.waves || []).find((w) => w.wave === 1);
  if (recHeld.ok || !rh1 || rh1.action === 'adopted' || rh1.action === 'adopted-noop') problems.push('reconcile adopted (or mis-reported) the held wave: ' + JSON.stringify(rh1));
  else if (rh1.action !== 'held') problems.push('held wave reconcile action is ' + rh1.action + ' (want held)');

  // ---- crash: store-side start evidence; a tampered scratch marker is inert
  const repo = L.makeRepo(path.join(process.env.T108_DIR, 'c16-crash'), [
    [{ id: 'T108a', files: ['src/a.txt'] }],
    [{ id: 'T108b', files: ['src/b.txt'] }],
  ]);
  const crashGit = (args, cwd) => {
    if (args[0] === 'rev-list') return { status: 128, stdout: '', stderr: 'simulated crash mid-check' };
    return spawnSync('git', args, { cwd: cwd || repo.dir, encoding: 'utf8' });
  };
  const crashed = await L.workers.runWaveDispatch(repo.snapshot, L.ctxFor(repo, L.makeRunner([], { kind: 'good' }), L.makeBreaker(3, 5, 100, repo.dir), { gitRunner: crashGit }));
  if (crashed.ok || crashed.reason !== 'git-failed') problems.push('crash simulation not paused: ' + JSON.stringify(crashed.reason));
  const landed = L.headOf(repo.dir);
  // tamper: rewrite the scratch marker (pre-crash evidence forged) and plant
  // a wave-2 marker that never ran — reconcile must read neither
  if (typeof L.store.readWaveStarts !== 'function') problems.push('store exposes no readWaveStarts');
  const startRead = L.store.readWaveStarts(repo.dir);
  const w1 = startRead.ok ? startRead.waveStarts['T108fx/W1'] : null;
  if (!w1 || !w1.spawnId || !/^[0-9a-f]{7,64}$/.test(w1.preHead) || typeof w1.preRefsText !== 'string' || !Array.isArray(w1.preDirty)) {
    problems.push('wave-start record malformed: ' + JSON.stringify(w1));
  }
  if (w1 && w1.spawnId) {
    const scratch = spawnreg.scratchPath(repo.dir, w1.spawnId);
    fs.mkdirSync(scratch, { recursive: true });
    fs.writeFileSync(path.join(scratch, 'wave.json'), JSON.stringify({
      task: 'T108fx', wave: 1, spawnId: w1.spawnId,
      preHead: '0000000000000000000000000000000000000000',
      preRefsText: 'refs/heads/evil 0000000000000000000000000000000000000000',
      preDirty: ['src/smuggled.txt'], startedAtIso: '2000-01-01T00:00:00.000Z',
    }));
    fs.writeFileSync(path.join(scratch, 'wave2.json'), JSON.stringify({
      task: 'T108fx', wave: 2, spawnId: 'never-ran',
      preHead: '0000000000000000000000000000000000000001', preRefsText: '', preDirty: [],
      startedAtIso: '2000-01-01T00:00:00.000Z',
    }));
    const stray = spawnreg.scratchPath(repo.dir, 'never-ran');
    fs.mkdirSync(stray, { recursive: true });
    fs.writeFileSync(path.join(stray, 'wave.json'), JSON.stringify({
      task: 'T108fx', wave: 2, spawnId: 'never-ran',
      preHead: '0000000000000000000000000000000000000002', preRefsText: 'forged', preDirty: [],
      startedAtIso: '2000-01-01T00:00:00.000Z',
    }));
  }
  const rec1 = await L.workers.reconcileWaves(repo.snapshot, L.ctxFor(repo, L.throwingRunner(), L.makeBreaker(3, 5, 100, repo.dir)));
  const r1w1 = (rec1.waves || []).find((w) => w.wave === 1);
  const r1w2 = (rec1.waves || []).find((w) => w.wave === 2);
  if (!rec1.ok || !r1w1 || r1w1.action !== 'adopted' || r1w1.head !== landed) {
    problems.push('tampered marker changed the crash verdict: ' + JSON.stringify({ ok: rec1.ok, w1: r1w1 }));
  }
  if (!r1w2 || r1w2.action !== 'not-started') problems.push('planted wave-2 marker was consumed by reconcile: ' + JSON.stringify(r1w2));

  // ---- deny-stamped crash start: adoption refused on the stamp's telemetry
  let rec2 = null;
  if (typeof L.store.recordWaveStart === 'function' && typeof L.store.stampStream === 'function') {
    const denySpawn = 'T108fx-W2-denyprobe';
    const sr2 = L.store.recordWaveStart(repo.dir, {
      task: 'T108fx', wave: 2, spawnId: denySpawn,
      preHead: L.headOf(repo.dir), preRefsText: '', preDirty: [],
    });
    if (!sr2.ok) problems.push('manual wave-start record refused: ' + sr2.reason);
    const st2 = L.store.stampStream(denySpawn, 'BUILD', L.sha256Text('deny stream'), new Date().toISOString(), repo.dir, { denyHits: 2, denyCommandHits: 2 });
    if (!st2.ok) problems.push('deny stamp refused: ' + st2.reason);
    for (const p of ['src/b.txt']) {
      const abs = path.join(repo.dir, p);
      fs.mkdirSync(path.dirname(abs), { recursive: true });
      fs.writeFileSync(abs, 'a perfectly attributable wave 2 commit\n');
    }
    git(repo.dir, ['add', 'src/b.txt']);
    git(repo.dir, ['commit', '-q', '-m', 'wave 2 work']);
    rec2 = await L.workers.reconcileWaves(repo.snapshot, L.ctxFor(repo, L.throwingRunner(), L.makeBreaker(3, 5, 100, repo.dir)));
    const r2w2 = (rec2.waves || []).find((w) => w.wave === 2);
    if (rec2.ok || !r2w2 || r2w2.action === 'adopted') problems.push('deny-stamped crash start was adopted: ' + JSON.stringify(r2w2));
    else if (r2w2.action !== 'unattributable') problems.push('deny-stamped reconcile action is ' + r2w2.action + ' (want unattributable)');
    const recs2 = L.store.readWaveRecords(repo.dir);
    if (recs2.ok && recs2.waves['T108fx/W2']) problems.push('deny-stamped wave wrote a completion record');
  } else {
    problems.push('store lacks recordWaveStart/stampStream surface');
  }
  console.log(problems.length ? 'C16-BAD ' + problems.join('; ') : 'C16-OK');
  console.log('HELD[' + (rh1 && rh1.action) + '] ADOPT[' + (r1w1 && r1w1.action) + ':' + String(r1w1 && r1w1.head).slice(0, 10) + '] W2[' + (r1w2 && r1w2.action) + '] DENY[' + ((rec2 || {}).waves ? ((rec2.waves || []).find((w) => w.wave === 2) || {}).action : 'n/a') + ']');
})().catch((e) => { console.log('C16-BAD ' + e.message); process.exitCode = 1; });
EOF
C16_OUT="$(node "$T108_DIR/c16.cjs" 2>&1)"; RC=$?
t108_exit "held-vs-crash probe runs clean" "0" "$RC"
t108_contains "held waves never adopted; start evidence is store-side; tampered scratch markers are inert" "C16-OK" "$C16_OUT"
t108_contains "held wave reconcile action" "HELD[held]" "$C16_OUT"
t108_contains "crashed wave still adopted from store evidence" "ADOPT[adopted:" "$C16_OUT"
t108_contains "planted wave-2 marker inert" "W2[not-started]" "$C16_OUT"
t108_contains "deny-stamped crash start unattributable" "DENY[unattributable]" "$C16_OUT"

echo "--- T108 summary: $PASS passed, $FAIL failed ---"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0