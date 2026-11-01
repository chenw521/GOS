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
#   gate-parity   C14  on red and green git fixtures the programmatic
#                   verdict entry returns the same failure set the CLI
#                   prints: identical stdout lines, identical rendered
#                   failure block and header, failures deep-equal the
#                   CLI --json failure array, ok mirrors the CLI exit code
#   gate-red-hold C15  a red gate computes as data in-process: ok:false,
#                   findings list with code/verdict/evidence/fix, no
#                   refusal, zero stdout/stderr bytes from the call, no
#                   process exit (the probe completing is the proof); the
#                   findings carry the hold surface, never a breaker count
#   testbase-pin  C16  run-sections.sh accepts an env-pinned absolute
#                   TESTBASE (used verbatim: home artifact lands inside,
#                   the pin survives the run, sections green); a missing or
#                   unwritable pin fails loudly without literal fallback;
#                   unset or relative TESTBASE keeps the literal mktemp
#                   base (real section green, base swept on exit)
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
  [ -n "${T107_FX:-}" ] && rm -rf "$T107_FX"
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

# ---------------------------------------------------------------- C14 --
echo "C14: gate-parity (programmatic verdicts identical to the CLI path)"
# Gate fixtures live OUTSIDE the repo (gates-trust section precedent):
# stateless --audit runs nested under a managed ancestor would resolve the
# wrong project root. Each fixture is a git repo with .gos/ seeded for its
# verdict shape.
T107_FX="$(mktemp -d "${TMPDIR:-/tmp}/gos-t107-gate-XXXXXX")"
t107_gate_fx() {   # $1=fixture name -> git-seeded dir with .gos/, cwd inside
  local d="$T107_FX/$1"
  mkdir -p "$d/.gos"
  cd "$d" || exit 1
  git init -q . && git commit -q --allow-empty -m seed
  printf '.gos/state.json\n.gos/cache/\n' > .gitignore
  git add .gitignore && git commit -q -m gi
}
t107_gate_fx redA; printf '{bad json' > .gos/gates.json
t107_gate_fx redB; printf '{"protect":["protected.txt"]}\n' > .gos/gates.json; printf 'touch\n' > protected.txt
t107_gate_fx green; printf '{}\n' > .gos/gates.json; node "$GOS" paths --markdown >/dev/null 2>&1

cat > "$T107_FX/gate-parity.cjs" <<'EOF'
const path = require('path');
const { execFileSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const gate = require(path.join(GR, 'bin/lib/ops/gate.cjs'));
const problems = [];
const runCli = (args) => {
  try {
    return { rc: 0, out: execFileSync(process.execPath, [path.join(GR, 'bin', 'gos.cjs'), ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }), err: '' };
  } catch (e) {
    return { rc: e.status == null ? 1 : e.status, out: e.stdout || '', err: e.stderr || '' };
  }
};
const human = runCli(['gate', 'all', '--audit']);
const jsonLeg = runCli(['gate', 'all', '--audit', '--json']);
// --json output carries the per-check lines before the JSON blob (the CLI
// prints check progress in every mode) — the blob starts at the first line
// opening with '{'
const jsonLines = jsonLeg.out.split('\n');
let jsonAt = jsonLines.findIndex((l) => l.startsWith('{'));
if (jsonAt < 0) jsonAt = jsonLines.length;
let jsonFailures = null;
try { jsonFailures = JSON.parse(jsonLines.slice(jsonAt).join('\n')).failures; }
catch (e) { problems.push('CLI --json output unparseable: ' + e.message); }

// Programmatic entry on the same fixture: verdicts as data, in-process.
const v = gate.computeGateVerdicts({ which: 'all', auditMode: true });
if (v.ok !== (human.rc === 0)) problems.push('ok disagrees with CLI exit: ok=' + v.ok + ' rc=' + human.rc);
if (v.ok !== (jsonLeg.rc === 0)) problems.push('ok disagrees with CLI --json exit');
if (v.refused != null) problems.push('unexpected refusal: ' + v.refused);
if (jsonFailures) {
  const norm = (fs) => JSON.stringify(fs.map((f) => ({ code: f.code, verdict: f.verdict, evidence: f.evidence, fix: f.fix })));
  if (norm(jsonFailures) !== norm(v.failures)) problems.push('failure set differs from CLI --json array');
}
// stdout parity: the CLI's stdout is the replayed verdict lines plus the
// renderer tail (green ends with the all-pass line; red stdout stops at the
// lines — the failure block renders on stderr)
const expectedOut = v.lines.map((l) => l + '\n').join('') + (v.ok ? '\n✓ ALL GATES PASSED\n' : '');
if (human.out !== expectedOut) problems.push('CLI stdout differs from replayed verdict lines');
// stderr parity: red renders the exact header + failure block from the data
if (!v.ok) {
  const expectedErr = '\n' + '✗ GATE FAILED' + ' (' + v.failures.length + '):\n' + gate.renderGateFailures(v.failures) + '\n';
  if (human.err !== expectedErr) problems.push('CLI stderr differs from data-rendered failure block');
} else if (human.err !== '') {
  problems.push('green run wrote stderr bytes');
}
console.log(problems.length ? 'PARITY-BAD ' + problems.join('; ') : 'PARITY-OK');
console.log('COUNT[' + v.failures.length + ']');
EOF
cd "$T107_FX/redA" || exit 1
P_REDA="$(node "$T107_FX/gate-parity.cjs" 2>/dev/null)"; RC=$?
t107_exit "parity probe (redA) runs clean" "0" "$RC"
t107_contains "redA: programmatic verdicts identical to the CLI path" "PARITY-OK" "$P_REDA"
t107_contains "redA: two findings" "COUNT[2]" "$P_REDA"
cd "$T107_FX/redB" || exit 1
P_REDB="$(node "$T107_FX/gate-parity.cjs" 2>/dev/null)"; RC=$?
t107_exit "parity probe (redB) runs clean" "0" "$RC"
t107_contains "redB: programmatic verdicts identical to the CLI path" "PARITY-OK" "$P_REDB"
t107_contains "redB: two findings" "COUNT[2]" "$P_REDB"
cd "$T107_FX/green" || exit 1
P_GREEN="$(node "$T107_FX/gate-parity.cjs" 2>/dev/null)"; RC=$?
t107_exit "parity probe (green) runs clean" "0" "$RC"
t107_contains "green: programmatic verdicts identical to the CLI path" "PARITY-OK" "$P_GREEN"
t107_contains "green: zero findings" "COUNT[0]" "$P_GREEN"

# ---------------------------------------------------------------- C15 --
echo "C15: gate-red-hold (red gate computes as data, no exit, no stdout)"
cd "$T107_FX/redA" || exit 1
cat > "$T107_FX/gate-hold.cjs" <<'EOF'
const path = require('path');
const gate = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/gate.cjs'));
const v = gate.computeGateVerdicts({ which: 'all', auditMode: true });
const codes = v.failures.map((f) => f.code).sort().join(',');
const shaped = !v.ok && v.refused == null && v.failures.length === 2
  && v.failures.every((f) => f.code && f.verdict && Array.isArray(f.evidence) && f.fix);
console.log(shaped ? 'HOLD-SHAPE-OK' : 'HOLD-SHAPE-BAD ok=' + v.ok + ' refused=' + v.refused + ' n=' + v.failures.length);
console.log('CODES[' + codes + ']');
console.log('CHECKED[' + v.checked + ']');
EOF
node "$T107_FX/gate-hold.cjs" > "$T107_FX/hold.out" 2> "$T107_FX/hold.err"; RC=$?
t107_exit "red-hold probe completes (process alive, no exit)" "0" "$RC"
printf 'HOLD-SHAPE-OK\nCODES[gates-json-invalid,readme-drift]\nCHECKED[4]\n' > "$T107_FX/hold-expected.out"
if diff -q "$T107_FX/hold-expected.out" "$T107_FX/hold.out" >/dev/null 2>&1; then
  t107_ok "ok:false, findings shaped, zero stdout bytes from the call itself"
else
  t107_bad "hold probe stdout not byte-exact (stdout side effect or shape drift): $(head -c 160 "$T107_FX/hold.out")"
fi
if [ ! -s "$T107_FX/hold.err" ]; then
  t107_ok "zero stderr bytes from the compute call"
else
  t107_bad "compute leaked stderr: $(head -c 120 "$T107_FX/hold.err")"
fi

# ---------------------------------------------------------------- C16 --
echo "C16: testbase-pin (env-pinned TESTBASE + literal fallback)"
cd "$T107_DIR" || exit 1
T107_PIN="$T107_DIR/tb-pin"
mkdir -p "$T107_PIN"
env -u XDG_DATA_HOME TESTBASE="$T107_PIN" bash "$GOS_ROOT/test/run-sections.sh" T12-wiring > "$T107_DIR/pin-run.out" 2>&1; PIN_RC=$?
t107_exit "pinned TESTBASE section run green" "0" "$PIN_RC"
if grep -q "Sections total: [0-9]* passed, 0 failed" "$T107_DIR/pin-run.out"; then
  t107_ok "pinned run reports zero failures"
else
  t107_bad "pinned run total line missing or failing: $(grep 'Sections total' "$T107_DIR/pin-run.out" | head -c 120)"
fi
if [ -d "$T107_PIN/home" ]; then t107_ok "home artifact landed inside the pin (base actually used)"; else
  t107_bad "no artifact inside the pin — runner did not use it"; fi
if [ -d "$T107_PIN" ]; then t107_ok "pin survives the run (caller owns cleanup)"; else
  t107_bad "runner deleted the pinned base"; fi
T107_BASES_BEFORE="$(ls -d "$GOS_ROOT"/test-sections-base-* 2>/dev/null | sort)"
env -u TESTBASE -u XDG_DATA_HOME bash "$GOS_ROOT/test/run-sections.sh" T12-wiring > "$T107_DIR/lit-run.out" 2>&1; LIT_RC=$?
t107_exit "unset TESTBASE keeps the literal base path green" "0" "$LIT_RC"
if grep -q "Sections total: [0-9]* passed, 0 failed" "$T107_DIR/lit-run.out"; then
  t107_ok "literal fallback run reports zero failures"
else
  t107_bad "literal fallback run failing: $(grep 'Sections total' "$T107_DIR/lit-run.out" | head -c 120)"; fi
T107_BASES_AFTER="$(ls -d "$GOS_ROOT"/test-sections-base-* 2>/dev/null | sort)"
if [ "$T107_BASES_BEFORE" = "$T107_BASES_AFTER" ]; then
  t107_ok "literal base swept on exit (no new repo leftovers, enclosing base untouched)"
else
  t107_bad "base set drifted across the literal run: $(printf '%s' "$T107_BASES_AFTER" | head -c 160)"
fi
env -u XDG_DATA_HOME TESTBASE="$T107_DIR/no-such-pin" bash "$GOS_ROOT/test/run-sections.sh" T12-wiring > "$T107_DIR/pin-miss.out" 2>&1; MISS_RC=$?
if [ "$MISS_RC" -ne 0 ] && grep -q "TESTBASE" "$T107_DIR/pin-miss.out"; then
  t107_ok "missing pin refuses loudly (no silent fallback)"
else
  t107_bad "missing pin not refused loudly (rc=$MISS_RC)"
fi
env -u XDG_DATA_HOME TESTBASE=/dev/null bash "$GOS_ROOT/test/run-sections.sh" T12-wiring > "$T107_DIR/pin-file.out" 2>&1; FILE_RC=$?
if [ "$FILE_RC" -ne 0 ] && grep -q "TESTBASE" "$T107_DIR/pin-file.out"; then
  t107_ok "non-directory pin refuses loudly"
else
  t107_bad "non-directory pin not refused (rc=$FILE_RC)"
fi
env -u XDG_DATA_HOME TESTBASE="rel-not-a-pin" bash "$GOS_ROOT/test/run-sections.sh" NO-SUCH-SECTION > "$T107_DIR/rel-run.out" 2>&1; REL_RC=$?
t107_exit "relative TESTBASE ignored (literal fallback, zero-section run)" "0" "$REL_RC"
if grep -q "Sections total: 0 passed, 0 failed" "$T107_DIR/rel-run.out"; then
  t107_ok "relative pin ignored, literal base created and swept"
else
  t107_bad "relative-pin run did not fall back cleanly"
fi

echo "--- T107 summary: $PASS passed, $FAIL failed ---"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
