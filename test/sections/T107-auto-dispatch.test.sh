#!/usr/bin/env bash
# gos-map:none
# Auto-dispatch section — the stage-dispatch blueprint surface for the auto
# loop. First case set: the spawn-text sanitizer module (core/sanitize.cjs)
# that every render surface funnels spawn-originated bytes through before
# showing them to humans. Second case set: the stage-dispatch table template
# (templates/auto-dispatch.json) behind its fail-closed loader
# (ops/auto/workers.cjs), where the table is pure data and every value
# bound lives in loader code.
# Case map (truth id -> case):
#   sanitize-strip  C1  a string carrying SGR color runs, cursor/erase
#                   sequences, OSC payloads (BEL- and ST-terminated), a
#                   charset escape, and bare C0 controls renders escape-free
#                   with every visible word intact and byte-exact spacing
#   spawn-marker    C2  markSpawnOutput prefixes the spawn-output marker,
#                   renderSpawnOutput(raw) equals mark(sanitize(raw)) exactly
#   dispatch-load   C3  the shipped dispatch table loads all seven stages;
#                   BUILD carries wave_dispatch true under unit stage-wave
#                   with the hard-ceiling use cap and profile workspace,
#                   every other stage stays restricted and wave-free
#   dispatch-refuse C4  sandbox tables mutated one field at a time each
#                   refuse with their named reason: unknown-stage,
#                   unknown-worker, unknown-verb, bad-unit, bad-profile,
#                   cap-over-ceiling, schema-version, missing-worker-form
#   compose-base  C5  launcher compose with no new opts pins today's argv
#                   bytes (rebuilt golden: fixed prefix, resolv stub, home,
#                   workspace + .git, writable roots, masks shallow-first)
#                   and today's env shape (config content only)
#   compose-scratch C6  a per-spawn scratch dir is created, rw-bound AFTER
#                   every mask mount, exported as GOS_AUTO_SPAWN_SCRATCH,
#                   and /tmp carries an explicitly sized tmpfs
#                   (--size 536870912 --tmpfs /tmp); the store mask stays
#                   and nothing else re-exposes the store tree
#   compose-testbase C7  testBase composes TESTBASE at the scratch testbed
#                   subdir (created) plus its rw bind after the masks
#   compose-grant C8  grantManifestPath ro-binds after the masks at the
#                   fixed /run/gos-grants.json (with --dir /run only when
#                   nothing else already mounts /run) and exports
#                   GOS_AUTO_GRANT_MANIFEST
#   compose-derive C9  spawnId alone derives the spawnreg scratch
#                   convention (<storeRoot>/spawnreg/<spawnId>.scratch)
#                   and creates it
#   compose-sizegate C10  bwrap older than 0.7.0 (or version unknown)
#                   refuses a scratch compose (tmpfs sizing unsupported);
#                   lexical tier + scratch composes without --size tokens
#   compose-tier  C11  requiresKernelTier under a lexical probe refuses
#                   code auto.launcher.kernel-tier-required with the probe
#                   reason; under bwrap it composes
#   compose-identity C12  git identity env lands on workspace profiles and
#                   buildSpawn entries, stays off restricted spawns, and
#                   gitIdentity:false suppresses it
#   git-identity-die C13  a pure-git fixture: identity-less commit dies,
#                   the same commit with the four gos-auto identity vars
#                   lands
# Standalone-safe: self-provisions env when not under test/run-sections.sh.

T107_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T107_STANDALONE=1
  T107_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T107_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T107_SELFROOT"
  export TESTBASE="$(mktemp -d "$T107_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T107_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t107"
mkdir -p "$T107_DIR" && cd "$T107_DIR" || exit 1

PASS=0
FAIL=0
t107_ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
t107_bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
t107_contains() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then t107_ok "$label"; else
    t107_bad "$label (expected: '$expected')"
    echo "    actual: $(printf '%s' "$actual" | head -c 200)"
  fi
}
t107_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then t107_ok "$label (exit $actual)"; else
    t107_bad "$label (expected exit $expected, got '${actual:-<none>}')"; fi
}

t107_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T107_DIR"
  if [ "$T107_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t107_teardown EXIT

echo "--- T107: auto dispatch (sanitize-strip, spawn-marker, dispatch-load, dispatch-refuse, launcher compose) ---"

SAN="$T107_DIR/sanitize-probe.cjs"
cat > "$SAN" <<'EOF'
const path = require('path');
const sanitize = require(path.join(process.env.GOS_ROOT, 'bin/lib/core/sanitize.cjs'));
const problems = [];

// Escape families a spawned worker emits: SGR color runs, cursor movement
// and erase, OSC payloads (BEL- and ST-terminated), charset selection, and
// bare C0 controls (NUL/SOH/BEL/BS/CR) riding between visible words.
const raw =
  'plain \x1b[31mred\x1b[0m \x1b[2Kwiped\x1b[1;5H' +
  '\x1b]0;title\x07hybrid \x1b]8;;http://unit.invalid/a\x1b\\link' +
  ' \x00\x01\x07\x08\x0dctl\x1b(B end';

const expected = 'plain red wipedhybrid link ctl end';
const clean = sanitize.sanitizeSpawnText(raw);
if (clean.includes('\x1b')) problems.push('ESC byte survived');
if (/[\u0000-\u0008\u000b-\u001f\u007f\u0080-\u009f]/.test(clean)) problems.push('C0/C1 control survived');
if (clean !== expected) problems.push('strip result not byte-exact: ' + JSON.stringify(clean));
if (sanitize.sanitizeSpawnText(clean) !== clean) problems.push('sanitize not idempotent');
const plainText = 'untouched text\nsecond line\ttabbed';
if (sanitize.sanitizeSpawnText(plainText) !== plainText) problems.push('plain text altered (LF/TAB must survive)');
if (sanitize.sanitizeSpawnText(undefined) !== '') problems.push('undefined input does not yield empty string');
console.log(problems.length ? 'SANITIZE-BAD ' + problems.join('; ') : 'SANITIZE-OK');
console.log('CLEAN[' + clean + ']');

const marker = sanitize.SPAWN_OUTPUT_MARKER;
const marked = sanitize.markSpawnOutput(clean);
if (typeof marker !== 'string' || marker === '') problems.push('SPAWN_OUTPUT_MARKER missing');
if (marked.indexOf(marker) !== 0) problems.push('marker does not prefix the output');
if (!marked.includes(clean)) problems.push('marked output lost the cleaned text');
if (sanitize.renderSpawnOutput(raw) !== marked) problems.push('renderSpawnOutput != mark(sanitize(raw))');
if (sanitize.renderSpawnOutput(raw).includes('\x1b')) problems.push('renderSpawnOutput leaked an escape');
console.log(problems.length ? 'MARK-BAD ' + problems.join('; ') : 'MARK-OK');
console.log('RENDER[' + sanitize.renderSpawnOutput(raw) + ']');
EOF

# ---------------------------------------------------------------- C1 --
echo "C1: sanitize-strip (SGR + cursor + OSC + charset + bare C0)"
SAN_OUT="$(node "$SAN" 2>&1)"; RC=$?
t107_exit "probe runs clean" "0" "$RC"
t107_contains "all escape families stripped, visible words intact" "SANITIZE-OK" "$SAN_OUT"
t107_contains "strip result is byte-exact" "CLEAN[plain red wipedhybrid link ctl end]" "$SAN_OUT"

# ---------------------------------------------------------------- C2 --
echo "C2: spawn-marker (prefix + combined render form)"
t107_contains "marker prefixes, render equals mark(sanitize(raw))" "MARK-OK" "$SAN_OUT"
t107_contains "combined render output pinned" "RENDER[[spawn] plain red wipedhybrid link ctl end]" "$SAN_OUT"

# ---------------------------------------------------------------- C3 --
echo "C3: dispatch-load (shipped table: seven stages, BUILD wave_dispatch)"
DISPATCH="$T107_DIR/dispatch-probe.cjs"
cat > "$DISPATCH" <<'EOF'
const fs = require('fs');
const path = require('path');
const workers = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/workers.cjs'));
const limits = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/limits.cjs'));
const sandbox = process.env.T107_SANDBOX;
const problems = [];
const SEVEN = ['INTENT', 'THINK', 'PLAN', 'BUILD', 'REVIEW', 'VERIFY', 'SHIP'];

const load = workers.loadDispatchTable();
if (!load.ok) problems.push('shipped table refused: ' + JSON.stringify(load));
if (load.ok) {
  const keys = Object.keys(load.table.stages);
  if (keys.length !== 7 || SEVEN.some((s) => !keys.includes(s))) {
    problems.push('stage set is not exactly the seven: ' + keys.join(','));
  }
  const b = load.table.stages.BUILD;
  if (b.wave_dispatch !== true) problems.push('BUILD wave_dispatch is not true');
  if (b.unit !== 'stage-wave') problems.push('BUILD unit is not stage-wave');
  if (b.use_cap !== limits.HARD_USE_CAP_CEILING) problems.push('BUILD use_cap is not the hard ceiling');
  if (b.profile !== 'workspace') problems.push('BUILD profile is not workspace');
  if (b.verbs.indexOf('checkpoint') === -1) problems.push('BUILD verbs lack checkpoint');
  if (b.model_slot !== 'implementer') problems.push('BUILD model_slot is not implementer');
  for (const s of SEVEN) {
    if (s === 'BUILD') continue;
    const e = load.table.stages[s];
    if (e.wave_dispatch) problems.push(s + ' carries wave_dispatch');
    if (e.profile !== 'restricted') problems.push(s + ' profile is not restricted');
  }
}
console.log(problems.length ? 'DISPATCH-POS-BAD ' + problems.join('; ') : 'DISPATCH-POS-OK');

// One mutated copy of the shipped table per named refusal, written into the
// section sandbox and loaded via tablePath — every mutation touches exactly
// one field so the surfaced reason stays attributable.
if (!load.ok) {
  console.log('NEG-SKIP: shipped table did not load');
} else {
  const shipped = JSON.parse(fs.readFileSync(load.file, 'utf8'));
  const refuse = (name, mutate) => {
    const t = JSON.parse(JSON.stringify(shipped));
    mutate(t);
    const p = path.join(sandbox, 'neg-' + name + '.json');
    fs.writeFileSync(p, JSON.stringify(t, null, 2));
    const r = workers.loadDispatchTable({ tablePath: p });
    console.log(r.ok ? 'NEG-' + name + ':BAD(loaded)' : 'NEG-' + name + ':' + r.reason);
  };
  refuse('unknown-stage', (t) => { t.stages.OBSERVE = JSON.parse(JSON.stringify(t.stages.INTENT)); });
  refuse('unknown-worker', (t) => { t.stages.THINK.worker = 'llm'; });
  refuse('unknown-verb', (t) => { t.stages.PLAN.verbs = ['sudo'].concat(t.stages.PLAN.verbs); });
  refuse('bad-unit', (t) => { t.stages.REVIEW.unit = 'free-form'; });
  refuse('bad-profile', (t) => { t.stages.THINK.profile = 'full'; });
  refuse('cap-over-ceiling', (t) => { t.stages.VERIFY.use_cap = 999; });
  refuse('schema-version', (t) => { t.dispatch_schema_version = 2; });
  refuse('missing-worker-form', (t) => { delete t.stages.SHIP.worker; });
}
EOF
DISPATCH_OUT="$(T107_SANDBOX="$T107_DIR" node "$DISPATCH" 2>&1)"; RC=$?
t107_exit "dispatch probe runs clean" "0" "$RC"
t107_contains "shipped template loads with the seven stages and stage bounds" "DISPATCH-POS-OK" "$DISPATCH_OUT"

# ---------------------------------------------------------------- C4 --
echo "C4: dispatch-refuse (named fail-closed reasons)"
t107_contains "extra stage key -> unknown-stage" "NEG-unknown-stage:unknown-stage" "$DISPATCH_OUT"
t107_contains "worker 'llm' -> unknown-worker" "NEG-unknown-worker:unknown-worker" "$DISPATCH_OUT"
t107_contains "verb 'sudo' -> unknown-verb" "NEG-unknown-verb:unknown-verb" "$DISPATCH_OUT"
t107_contains "unit 'free-form' -> bad-unit" "NEG-bad-unit:bad-unit" "$DISPATCH_OUT"
t107_contains "profile 'full' on THINK -> bad-profile" "NEG-bad-profile:bad-profile" "$DISPATCH_OUT"
t107_contains "use_cap 999 -> cap-over-ceiling" "NEG-cap-over-ceiling:cap-over-ceiling" "$DISPATCH_OUT"
t107_contains "dispatch_schema_version 2 -> schema-version" "NEG-schema-version:schema-version" "$DISPATCH_OUT"
t107_contains "absent worker field -> missing-worker-form" "NEG-missing-worker-form:missing-worker-form" "$DISPATCH_OUT"

# ---------------------------------------------------------------- C5 --
echo "C5: compose-base (no new opts: argv + env byte-shape pinned)"
T107_L="$T107_DIR/lfx"
mkdir -p "$T107_L/home/.config/gh" "$T107_L/home/.config/git" "$T107_L/home/.config/opencode" \
  "$T107_L/home/.local/share/opencode" "$T107_L/home/.cache/opencode" \
  "$T107_L/home/.ssh" "$T107_L/home/.aws" "$T107_L/home/.gnupg" \
  "$T107_L/xdg/gos" "$T107_L/repo/.gos"
: > "$T107_L/home/.gitconfig"
: > "$T107_L/home/.netrc"
: > "$T107_L/home/.git-credentials"
export HOME="$T107_L/home"
export XDG_DATA_HOME="$T107_L/xdg"

cat > "$T107_DIR/launch-base.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const launcher = require(path.join(GR, 'bin/lib/ops/auto/launcher.cjs'));
const problems = [];
const home = process.env.HOME;
const xdg = process.env.XDG_DATA_HOME;
const repo = path.join(path.dirname(home), 'repo');
const env = { ...process.env };
const bwrapStub = () => ({ engine: 'bwrap', version: '0.11.0' });
const c = launcher.compose('restricted', {
  workspace: repo, env, engineProbe: bwrapStub,
  writableRoots: [path.join(repo, '.gos')],
});
if (!c.ok) problems.push('baseline compose refused: ' + c.code);
if (c.ok) {
  // Golden argv rebuilt from the same building blocks the composer uses:
  // fixed system prefix, optional resolv stub bind (host-dependent, so the
  // detection is replicated verbatim), home ro-bind-try, workspace ro +
  // .git rw, writable roots, then every mask shallowest-first.
  const prof = JSON.parse(fs.readFileSync(path.join(GR, 'templates/auto-profiles/restricted.json'), 'utf8'));
  let resolv = null;
  try {
    const rr = fs.realpathSync('/etc/resolv.conf');
    if (rr !== '/etc/resolv.conf' && rr.startsWith('/run/')) {
      const seg = '/' + rr.split('/').slice(1, 3).join('/');
      let st = null;
      try { st = fs.lstatSync(seg); } catch { st = null; }
      if (st && st.isDirectory() && !st.isSymbolicLink()) resolv = seg;
    }
  } catch { /* resolv.conf unreadable */ }
  const expected = [
    '--die-with-parent',
    '--ro-bind', '/usr', '/usr',
    '--ro-bind-try', '/bin', '/bin',
    '--ro-bind-try', '/lib', '/lib',
    '--ro-bind-try', '/lib64', '/lib64',
    '--ro-bind-try', '/sbin', '/sbin',
    '--ro-bind-try', '/etc', '/etc',
    '--ro-bind-try', '/sys', '/sys',
    '--proc', '/proc',
    '--dev', '/dev',
    '--tmpfs', '/tmp',
  ];
  if (resolv) expected.push('--ro-bind-try', resolv, resolv);
  expected.push(
    '--ro-bind-try', home, home,
    '--ro-bind', repo, repo,
    '--bind', path.join(repo, '.git'), path.join(repo, '.git'),
    '--bind', path.join(repo, '.gos'), path.join(repo, '.gos'),
  );
  const masks = prof.masks.map((m) => ({ ...m, dest: path.resolve(launcher.resolveTokenPath(m.path, env)) }))
    .sort((a, b) => a.dest.split(path.sep).length - b.dest.split(path.sep).length || (a.dest < b.dest ? -1 : 1));
  for (const m of masks) {
    if (m.kind === 'empty') expected.push('--ro-bind', '/dev/null', m.dest);
    else expected.push('--tmpfs', m.dest);
  }
  if (JSON.stringify(c.argv) !== JSON.stringify(expected)) {
    problems.push('baseline argv drifted: got ' + JSON.stringify(c.argv) + ' want ' + JSON.stringify(expected));
  }
  const envKeys = Object.keys(c.env).sort();
  if (JSON.stringify(envKeys) !== JSON.stringify(['OPENCODE_CONFIG_CONTENT'])) {
    problems.push('baseline env keys drifted: ' + envKeys.join(','));
  }
  if (!c.deny.includes('sudo')) problems.push('baseline deny floor lost');
}
console.log(problems.length ? 'BASE-BAD ' + problems.join('; ') : 'BASE-OK');
EOF
BASE_OUT="$(node "$T107_DIR/launch-base.cjs" 2>&1)"; RC=$?
t107_exit "baseline probe runs clean" "0" "$RC"
t107_contains "no-opts compose argv and env stay byte-shaped like today" "BASE-OK" "$BASE_OUT"

# ---------------------------------------------------------------- C6..C12 --
cat > "$T107_DIR/launch-classs.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const GR = process.env.GOS_ROOT;
const launcher = require(path.join(GR, 'bin/lib/ops/auto/launcher.cjs'));
const spawnreg = require(path.join(GR, 'bin/lib/core/spawnreg.cjs'));
const problems = [];
const home = process.env.HOME;
const xdg = process.env.XDG_DATA_HOME;
const storePrefix = path.join(xdg, 'gos');
const repo = path.join(path.dirname(home), 'repo');
const env = { ...process.env };
const bwrapStub = () => ({ engine: 'bwrap', version: '0.11.0' });
const lexicalStub = () => ({ engine: 'none', reason: 'not installed' });

function ops(argv) {
  const out = [];
  for (let i = 0; i < argv.length;) {
    const t = argv[i];
    if (['--ro-bind', '--ro-bind-try', '--bind', '--bind-try', '--dev-bind'].includes(t)) { out.push({ op: t, src: argv[i + 1], dest: argv[i + 2], index: i }); i += 3; }
    else if (['--tmpfs', '--proc', '--dev', '--dir'].includes(t)) { out.push({ op: t, dest: argv[i + 1], index: i }); i += 2; }
    else i += 1;
  }
  return out;
}
function maxMaskMountIndex(composed) {
  const os = ops(composed.argv);
  let max = -1;
  for (const m of composed.meta.masks) {
    const impl = os.filter((o) => o.dest === m.dest
      && (m.kind === 'empty' ? (o.op === '--ro-bind' && o.src === '/dev/null') : o.op === '--tmpfs'));
    if (impl.length) max = Math.max(max, impl[impl.length - 1].index);
  }
  return max;
}
const baseOpts = { workspace: repo, env, engineProbe: bwrapStub, writableRoots: [path.join(repo, '.gos')] };

// C6: scratch compose contract
{
  const S = path.join(storePrefix, 'k1', 'spawnreg', 'sp-1.scratch');
  const c = launcher.compose('restricted', { ...baseOpts, scratchDir: S });
  if (!c.ok) problems.push('scratch compose refused: ' + c.code);
  else {
    let st = null; try { st = fs.statSync(S); } catch {}
    if (!st || !st.isDirectory()) problems.push('scratch dir not created by compose');
    if (c.env.GOS_AUTO_SPAWN_SCRATCH !== S) problems.push('GOS_AUTO_SPAWN_SCRATCH not pinned to the scratch dir');
    const bindAt = c.argv.findIndex((_, i) => c.argv[i] === '--bind' && c.argv[i + 1] === S && c.argv[i + 2] === S);
    if (bindAt < 0) problems.push('scratch not rw-bound');
    const lastMask = maxMaskMountIndex(c);
    if (bindAt >= 0 && !(bindAt > lastMask)) problems.push('scratch bind does not come after every mask mount');
    const sized = c.argv.some((_, i) => c.argv[i] === '--size' && c.argv[i + 1] === '536870912'
      && c.argv[i + 2] === '--tmpfs' && c.argv[i + 3] === '/tmp');
    if (!sized) problems.push('/tmp tmpfs not explicitly sized (--size 536870912 --tmpfs /tmp)');
    const bare = c.argv.some((_, i) => c.argv[i] === '--tmpfs' && c.argv[i + 1] === '/tmp' && c.argv[i - 1] !== '536870912');
    if (bare) problems.push('unsized /tmp tmpfs survived');
    if (!c.argv.some((_, i) => c.argv[i] === '--tmpfs' && c.argv[i + 1] === storePrefix)) problems.push('store prefix mask lost');
    const inside = ops(c.argv).filter((o) => o.dest && (o.dest === storePrefix || o.dest.startsWith(storePrefix + path.sep)));
    if (!inside.every((o) => (o.op === '--tmpfs' && o.dest === storePrefix) || (o.op === '--bind' && o.dest === S && o.src === S))) {
      problems.push('store tree re-exposed beyond the scratch carve-out: ' + JSON.stringify(inside));
    }
    if (!launcher.maskOverBindHolds(c)) problems.push('mask-over-bind invariant violated with scratch present');
  }
  console.log(problems.length ? 'SCR-BAD ' + problems.join('; ') : 'SCR-OK');
}

// C7: TESTBASE pin
{
  const before = problems.length;
  const S = path.join(storePrefix, 'k1', 'spawnreg', 'sp-2.scratch');
  const TB = path.join(S, 'testbed');
  const c = launcher.compose('restricted', { ...baseOpts, scratchDir: S, testBase: true });
  if (!c.ok) problems.push('testBase compose refused: ' + c.code);
  else {
    let st = null; try { st = fs.statSync(TB); } catch {}
    if (!st || !st.isDirectory()) problems.push('testbed dir not created');
    if (c.env.TESTBASE !== TB) problems.push('TESTBASE not pinned to the testbed dir');
    const bindAt = c.argv.findIndex((_, i) => c.argv[i] === '--bind' && c.argv[i + 1] === TB && c.argv[i + 2] === TB);
    if (bindAt < 0) problems.push('testbed not rw-bound');
    if (bindAt >= 0 && !(bindAt > maxMaskMountIndex(c))) problems.push('testbed bind does not come after every mask mount');
    if (!launcher.maskOverBindHolds(c)) problems.push('mask-over-bind invariant violated with testbed');
  }
  console.log(problems.length > before ? 'TB-BAD ' + problems.slice(before).join('; ') : 'TB-OK');
}

// C8: grant manifest mount
{
  const before = problems.length;
  const M = path.join(storePrefix, 'k1', 'spawnreg', 'sp-1.manifest.json');
  fs.writeFileSync(M, JSON.stringify({ spawn_id: 'sp-1', stage: 'BUILD', grants: ['commit'], use_cap: 4 }));
  const c = launcher.compose('restricted', { ...baseOpts, grantManifestPath: M });
  if (!c.ok) problems.push('grant compose refused: ' + c.code);
  else {
    const bindAt = c.argv.findIndex((_, i) => c.argv[i] === '--ro-bind' && c.argv[i + 1] === M && c.argv[i + 2] === '/run/gos-grants.json');
    if (bindAt < 0) problems.push('grant manifest not ro-bound at the fixed path');
    if (bindAt >= 0 && !(bindAt > maxMaskMountIndex(c))) problems.push('grant bind does not come after every mask mount');
    const runMounted = ops(c.argv).some((o) => o.dest === '/run' && o.op !== '--dir');
    const hasDir = c.argv.some((_, i) => c.argv[i] === '--dir' && c.argv[i + 1] === '/run');
    if (!runMounted && !hasDir) problems.push('--dir /run missing with no other /run mount');
    if (runMounted && hasDir) problems.push('--dir /run would shadow an earlier /run bind');
    if (c.env.GOS_AUTO_GRANT_MANIFEST !== '/run/gos-grants.json') problems.push('GOS_AUTO_GRANT_MANIFEST not pinned');
    if (!launcher.maskOverBindHolds(c)) problems.push('mask-over-bind invariant violated with grant manifest');
  }
  console.log(problems.length > before ? 'GRANT-BAD ' + problems.slice(before).join('; ') : 'GRANT-OK');
}

// C9: default scratch derivation via spawnId
{
  const before = problems.length;
  const c = launcher.compose('restricted', { ...baseOpts, spawnId: 'sp-9' });
  const want = spawnreg.scratchPath(path.resolve(repo), 'sp-9');
  if (!c.ok) problems.push('spawnId compose refused: ' + c.code);
  else if (want == null) problems.push('spawnreg convention itself unresolvable in fixture');
  else {
    if (c.env.GOS_AUTO_SPAWN_SCRATCH !== want) problems.push('derived scratch != spawnreg convention: ' + c.env.GOS_AUTO_SPAWN_SCRATCH + ' vs ' + want);
    let st = null; try { st = fs.statSync(want); } catch {}
    if (!st || !st.isDirectory()) problems.push('derived scratch dir not created');
  }
  console.log(problems.length > before ? 'DERIVE-BAD ' + problems.slice(before).join('; ') : 'DERIVE-OK');
}

// C10: tmpfs sizing gate
{
  const before = problems.length;
  const S = path.join(storePrefix, 'k1', 'spawnreg', 'sp-3.scratch');
  const old = launcher.compose('restricted', { ...baseOpts, engineProbe: () => ({ engine: 'bwrap', version: '0.6.1' }), scratchDir: S });
  if (old.ok || old.code !== 'auto.launcher.tmpfs-sizing-unsupported') problems.push('0.6.1 not refused: ' + JSON.stringify(old.ok ? 'ok' : old.code));
  const nov = launcher.compose('restricted', { ...baseOpts, engineProbe: () => ({ engine: 'bwrap' }), scratchDir: S });
  if (nov.ok || nov.code !== 'auto.launcher.tmpfs-sizing-unsupported') problems.push('versionless probe not refused: ' + JSON.stringify(nov.ok ? 'ok' : nov.code));
  const S2 = path.join(storePrefix, 'k1', 'spawnreg', 'sp-4.scratch');
  const lex = launcher.compose('restricted', { ...baseOpts, engineProbe: lexicalStub, scratchDir: S2 });
  if (!lex.ok || lex.tier !== 'lexical') problems.push('lexical scratch compose refused: ' + (lex.ok ? lex.tier : lex.code));
  else {
    if (lex.env.GOS_AUTO_SPAWN_SCRATCH !== S2) problems.push('lexical scratch env missing');
    if (!lex.argv.some((_, i) => lex.argv[i] === '--tmpfs' && lex.argv[i + 1] === '/tmp')) problems.push('lexical argv lost the /tmp tmpfs');
    if (lex.argv.includes('--size')) problems.push('lexical argv carries --size (inert argv must not pretend to size)');
  }
  console.log(problems.length > before ? 'SIZE-BAD ' + problems.slice(before).join('; ') : 'SIZE-OK');
}

// C11: kernel-tier requirement
{
  const before = problems.length;
  const refused = launcher.compose('restricted', { ...baseOpts, engineProbe: lexicalStub, requiresKernelTier: true });
  if (refused.ok || refused.code !== 'auto.launcher.kernel-tier-required') problems.push('lexical not refused fail-closed: ' + JSON.stringify(refused.ok ? 'ok' : refused.code));
  if (!refused.ok && !String(refused.detail || '').includes('not installed')) problems.push('refusal lost the probe reason: ' + refused.detail);
  const allowed = launcher.compose('restricted', { ...baseOpts, requiresKernelTier: true });
  if (!allowed.ok || allowed.tier !== 'bubblewrap') problems.push('bwrap-tier entry refused: ' + (allowed.ok ? allowed.tier : allowed.code));
  console.log(problems.length > before ? 'TIER-BAD ' + problems.slice(before).join('; ') : 'TIER-OK');
}

// C12: git identity injection
{
  const before = problems.length;
  const ID_KEYS = ['GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL'];
  const hasId = (e) => e.GIT_AUTHOR_NAME === 'gos-auto' && e.GIT_AUTHOR_EMAIL === 'gos-auto@invalid'
    && e.GIT_COMMITTER_NAME === 'gos-auto' && e.GIT_COMMITTER_EMAIL === 'gos-auto@invalid';
  const ws = launcher.compose('workspace', baseOpts);
  if (!ws.ok) problems.push('workspace compose refused: ' + ws.code);
  else if (!hasId(ws.env)) problems.push('workspace profile lacks the runner git identity');
  const rs = launcher.compose('restricted', baseOpts);
  if (!rs.ok) problems.push('restricted compose refused: ' + rs.code);
  else if (ID_KEYS.some((k) => k in rs.env)) problems.push('restricted spawn carries identity env uninvited');
  const bs = launcher.compose('restricted', { ...baseOpts, buildSpawn: true });
  if (!bs.ok) problems.push('buildSpawn compose refused: ' + bs.code);
  else if (!hasId(bs.env)) problems.push('buildSpawn entry lacks the runner git identity');
  const off = launcher.compose('workspace', { ...baseOpts, gitIdentity: false });
  if (!off.ok) problems.push('gitIdentity:false compose refused: ' + off.code);
  else if (ID_KEYS.some((k) => k in off.env)) problems.push('gitIdentity:false still injects identity');
  console.log(problems.length > before ? 'ID-BAD ' + problems.slice(before).join('; ') : 'ID-OK');
}
EOF
CLASSS_OUT="$(node "$T107_DIR/launch-classs.cjs" 2>&1)"; RC=$?

echo "C6: compose-scratch (rw bind after masks, scratch env, sized tmpfs, store mask intact)"
t107_exit "class-S probe runs clean" "0" "$RC"
t107_contains "scratch dir created, rw-bound after every mask, sized /tmp, store tree stays masked" "SCR-OK" "$CLASSS_OUT"

echo "C7: compose-testbase (TESTBASE pin + testbed rw bind)"
t107_contains "TESTBASE points at the scratch testbed subdir, created and rw-bound after masks" "TB-OK" "$CLASSS_OUT"

echo "C8: compose-grant (fixed-path manifest ro-bind + env)"
t107_contains "grant manifest ro-bound after masks at /run/gos-grants.json with env pin" "GRANT-OK" "$CLASSS_OUT"

echo "C9: compose-derive (spawnId -> spawnreg scratch convention)"
t107_contains "spawnId derives <storeRoot>/spawnreg/<spawnId>.scratch and creates it" "DERIVE-OK" "$CLASSS_OUT"

echo "C10: compose-sizegate (old/versionless bwrap refuses; lexical stays unsized)"
t107_contains "bwrap < 0.7.0 or unknown version refuses the scratch compose; lexical argv carries no --size" "SIZE-OK" "$CLASSS_OUT"

echo "C11: compose-tier (kernel-tier requirement refuses lexical fail-closed)"
t107_contains "requiresKernelTier + lexical refuses auto.launcher.kernel-tier-required with probe reason; bwrap composes" "TIER-OK" "$CLASSS_OUT"

echo "C12: compose-identity (runner git identity on workspace/buildSpawn only)"
t107_contains "identity env on workspace + buildSpawn, off restricted, gitIdentity:false suppresses" "ID-OK" "$CLASSS_OUT"

# ---------------------------------------------------------------- C13 --
echo "C13: git-identity-die (identity-less git refuses; gos-auto identity commits)"
T107_GIT="$T107_DIR/gitfx"
mkdir -p "$T107_GIT/home"
: > "$T107_GIT/home/.gitconfig"
git init -q -b work "$T107_GIT/repo" 2>/dev/null
GITNEG_RC=0
( cd "$T107_GIT/repo" && env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
    GIT_CONFIG_NOSYSTEM=1 HOME="$T107_GIT/home" \
    git -c user.useConfigOnly=true commit --allow-empty -m nope ) >/dev/null 2>&1 || GITNEG_RC=$?
GITPOS_RC=1
( cd "$T107_GIT/repo" && env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL \
    GIT_CONFIG_NOSYSTEM=1 HOME="$T107_GIT/home" \
    GIT_AUTHOR_NAME=gos-auto GIT_AUTHOR_EMAIL=gos-auto@invalid \
    GIT_COMMITTER_NAME=gos-auto GIT_COMMITTER_EMAIL=gos-auto@invalid \
    git -c user.useConfigOnly=true commit --allow-empty -m ok ) >/dev/null 2>&1 && GITPOS_RC=0
if [ "$GITNEG_RC" -ne 0 ]; then t107_ok "identity-less git commit dies (exit $GITNEG_RC)"; else
  t107_bad "identity-less git commit was allowed to land"; fi
t107_exit "same commit with the four gos-auto identity vars lands" "0" "$GITPOS_RC"

echo "--- T107 summary: $PASS passed, $FAIL failed ---"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
