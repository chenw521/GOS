// ops/section — `gos section run`: product port of the repo's bash section-test
// runner discipline for USER projects (test/sections/T*.test.sh).
//
// Threat model (frozen wording): FIXTURE ISOLATION, not a security boundary.
// Sections execute with the user's full permissions. This runner prevents
// (a) fixture pollution of the user environment — every section runs with
// cwd=<fixture base> and HOME/XDG/TMPDIR pinned inside it, stdin never
// inherited — and (b) green-without-running — rc capture, ✓/✗ counting,
// per-section timeouts and a fail-closed run manifest. It does NOT defend
// against malicious scripts or absolute-path writes (out of scope; same-UID
// accidental-harm boundary, not anti-adversary).
'use strict';

const core = require('../core/index.cjs');
const sibGate = require('./gate.cjs');
const fs = require('fs');
const path = require('path');
const crypto = require('node:crypto');
const { spawnSync } = require('child_process');

const TESTBASE_PREFIX = 'sections-base-';
const TESTBASE_MARKER = '.GOS-TESTBASE';
const HELPERS_FILE = '.gos-section-helpers.sh';
const DEFAULT_TIMEOUT_SEC = 120;

// Shared assert helpers handed to every section (same contracts as the repo's
// own runner: two-space ✓/✗ output lines are the counting currency).
const SECTION_HELPERS = [
  'assert_contains() {',
  '  local label="$1" expected="$2" actual="$3"',
  '  if [ -z "$expected" ]; then',
  '    echo "  ✗ $label (empty pattern always matches — use assert_file/assert_eq)"',
  '  elif echo "$actual" | grep -q "$expected"; then',
  '    echo "  ✓ $label"',
  '  else',
  '    echo "  ✗ $label (expected: \'$expected\')"',
  '    echo "    actual: ${actual:0:160}"',
  '  fi',
  '}',
  'assert_exit() {',
  '  local label="$1" expected="$2" actual="$3"',
  '  if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then',
  '    echo "  ✓ $label (exit $actual)"',
  '  else',
  '    echo "  ✗ $label (expected exit $expected, got \'${actual:-<none>}\')"',
  '  fi',
  '}',
  'assert_file() {',
  '  local label="$1" fpath="$2"',
  '  if [ -n "$fpath" ] && [ -e "$fpath" ]; then',
  '    echo "  ✓ $label"',
  '  else',
  '    echo "  ✗ $label (missing: \'${fpath:-<none>}\')"',
  '  fi',
  '}',
  'assert_eq() {',
  '  local label="$1" expected="$2" actual="$3"',
  '  if [ "$expected" = "$actual" ]; then',
  '    echo "  ✓ $label"',
  '  else',
  '    echo "  ✗ $label (expected: \'$expected\', got: \'$actual\')"',
  '  fi',
  '}',
  'export -f assert_contains assert_exit assert_file assert_eq',
  'export PASS=0 FAIL=0',
].join('\n');

let ownTestbase = null;

function cleanupOwnTestbase() {
  if (!ownTestbase) return;
  try { fs.rmSync(ownTestbase, { recursive: true, force: true }); } catch { /* best-effort */ }
  ownTestbase = null;
}
process.on('exit', cleanupOwnTestbase);
for (const sig of ['SIGINT', 'SIGTERM']) {
  // Node keeps custom listeners installed across self-signals — re-killing
  // here would re-enter this handler forever. Clean up, then exit with the
  // conventional 128+signal code (130/143) instead of re-raising.
  process.on(sig, () => { cleanupOwnTestbase(); process.exit(sig === 'SIGINT' ? 130 : 143); });
}

function sectionFileNames(root) {
  let names = [];
  try {
    names = fs.readdirSync(path.join(root, 'test', 'sections')).filter((f) => /^T.*\.test\.sh$/.test(f)).sort();
  } catch { names = []; }
  return names;
}

function sectionsListHash(names) {
  return crypto.createHash('sha256').update([...names].sort().join('\n'), 'utf8').digest('hex');
}

function loadSectionTrust() {
  const res = sibGate.loadTrustStore();
  if (!res.ok) {
    console.log('⚠ trust store unreadable/corrupt — section confirmation treated as missing (fail-closed; rebuild via gos section trust)');
    return { schema_version: 1, trusted_scripts: {}, confirmed_sections: '' };
  }
  return res.store;
}

function saveSectionTrust(store) {
  core.writeAtomicJson(path.join(core.GOS_DIR, core.GOS_PATHS.trust.rel), store);
}

async function confirmSectionList(root, names) {
  // Returns 'run' (confirmed or already trusted) | 'skip' (CI advisory exit 0).
  // Hard-fail paths (headless-unconfirmed, declined) exit here.
  const SR = core.CONTRACTS.section_runner;
  const hash = sectionsListHash(names);
  const store = loadSectionTrust();
  if ((store.confirmed_sections || '') === hash) return 'run';
  const ciMode = ['1', 'true', 'yes', 'on'].includes(String(process.env.GOS_CI || '').trim().toLowerCase());
  if (ciMode) {
    console.log(`⚠ ${SR.ciSkip}`);
    return 'skip';
  }
  if (core.isHeadlessEnv() || !process.stdin.isTTY) {
    core.die(SR.headlessUnconfirmed);
  }
  console.log(SR.confirmHeader);
  for (const n of names) console.log(`  ${path.join(root, 'test', 'sections', n)}`);
  // core.ask reads one line via the stdin stream (raw readSync on fd 0 would
  // race libuv's non-blocking mode once the handle initializes)
  const ans = await core.ask(SR.confirmPrompt);
  console.log('');
  if (ans !== 'y' && ans !== 'yes') core.die(SR.confirmDeclined);
  store.confirmed_sections = hash;
  saveSectionTrust(store);
  console.log(SR.confirmStored);
  return 'run';
}

function cmdSectionTrust(args) {
  const SR = core.CONTRACTS.section_runner;
  if ((args || []).length) core.die('Usage: gos section trust   (no extra arguments)');
  const root = core.mapRootDir();
  const names = sectionFileNames(root);
  if (!names.length) core.die(SR.trustEmpty);
  const store = loadSectionTrust();
  const hash = sectionsListHash(names);
  store.confirmed_sections = hash;
  saveSectionTrust(store);
  console.log(`${SR.trustRegistered.replace('<N>', String(names.length))} (sha256 ${hash.slice(0, 16)})`);
}

function probeBash() {
  try {
    const r = spawnSync('bash', ['--version'], { stdio: ['ignore', 'pipe', 'pipe'] });
    if (!r.error && r.status === 0) return true;
  } catch { /* fallthrough */ }
  return false;
}

function makeTestbase(cacheDir) {
  const base = path.join(cacheDir, `${TESTBASE_PREFIX}${process.pid}-${Date.now()}`);
  for (const d of ['home', path.join('xdg', 'config'), path.join('xdg', 'data'), 'tmp']) {
    fs.mkdirSync(path.join(base, d), { recursive: true });
  }
  fs.writeFileSync(path.join(base, TESTBASE_MARKER), `${JSON.stringify({ pid: process.pid, started_at: new Date().toISOString() })}\n`);
  fs.writeFileSync(path.join(base, HELPERS_FILE), `${SECTION_HELPERS}\n`);
  return base;
}

function sectionChildEnv(base) {
  // Spawn markers are runner-session context, not fixture context: sections
  // drive the auto loop through module APIs and would refuse (marker-active)
  // if a spawned `gos section` call leaked its own marker into them. Sections
  // testing marker behavior set the vars explicitly per case.
  const parent = { ...process.env };
  delete parent.GOS_AUTO_SPAWNED;
  delete parent.GOS_AUTO_SPAWN_ID;
  return Object.assign(parent, {
    HOME: path.join(base, 'home'),
    GIT_AUTHOR_NAME: 'gos-test',
    GIT_AUTHOR_EMAIL: 'gos-test@test.invalid',
    GIT_COMMITTER_NAME: 'gos-test',
    GIT_COMMITTER_EMAIL: 'gos-test@test.invalid',
    GOS_HEADLESS: '1',
    XDG_CONFIG_HOME: path.join(base, 'xdg', 'config'),
    XDG_DATA_HOME: path.join(base, 'xdg', 'data'),
    TMPDIR: path.join(base, 'tmp'),
  });
}

function spawnOneSection(secPath, name, base, timeoutSec, emit) {
  // cwd=base (absolute TESTBASE) is the structural cd-escape guard: a child
  // process cannot move the parent's cwd, so a section that cd's elsewhere
  // only harms itself. The bash-runner's post-run `pwd` check is replaced by
  // the post-section marker lstat below (deletion/mutation of the fixture base is
  // the observable escape signal a parent CAN detect).
  const SR = core.CONTRACTS.section_runner;
  const res = spawnSync('bash', ['-c', '. "$1"; shift; bash "$@"', '_gos_section', path.join(base, HELPERS_FILE), secPath], {
    cwd: base,
    env: sectionChildEnv(base),
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: timeoutSec * 1000,
    maxBuffer: 16 * 1024 * 1024,
  });
  const out = `${res.stdout || ''}${res.stderr || ''}`;
  emit(res.stdout || '');
  emit(res.stderr || '');
  let extraFail = 0;
  if (res.error && res.error.code === 'ETIMEDOUT') {
    emit(`  ✗ ${SR.timeout.replace('<n>', String(timeoutSec))}\n`);
    extraFail++;
  } else if (res.status !== 0) {
    emit(`  ✗ ${SR.aborted.replace('<rc>', String(res.status))}\n`);
    extraFail++;
  }
  try { fs.lstatSync(path.join(base, TESTBASE_MARKER)); }
  catch {
    emit(`  ✗ ${SR.markerMissing}\n`);
    extraFail++;
  }
  const passN = (out.match(/^  ✓/gm) || []).length;
  const failN = (out.match(/^  ✗/gm) || []).length;
  emit(`--- ${name}: ${passN} passed, ${failN} failed ---\n`);
  return { pass: passN, fail: failN + extraFail, timedOut: !!(res.error && res.error.code === 'ETIMEDOUT') };
}

function sweepStaleTestbases(cacheDir) {
  // GOS-owned prefix ONLY; marker must be present; an embedded live pid makes
  // a base untouchable (concurrent runner); no-marker dirs are NEVER deleted.
  let entries = [];
  try { entries = fs.readdirSync(cacheDir); } catch { return 0; }
  let removed = 0;
  for (const e of entries) {
    if (!e.startsWith(TESTBASE_PREFIX)) continue;
    const full = path.join(cacheDir, e);
    let st = null;
    try { st = fs.lstatSync(full); } catch { continue; }
    if (!st.isDirectory()) continue;
    try { fs.lstatSync(path.join(full, TESTBASE_MARKER)); } catch { continue; }
    const pid = parseInt(e.slice(TESTBASE_PREFIX.length).split('-')[0], 10);
    if (!pid || pid === process.pid || core.pidAlive(pid)) continue;
    try { fs.rmSync(full, { recursive: true, force: true }); removed++; } catch { /* racing */ }
  }
  if (removed > 0) console.log(`✓ ${core.CONTRACTS.section_runner.sweepLine.replace('<N>', String(removed))}`);
  return removed;
}

async function cmdSectionRun(args) {
  const SR = core.CONTRACTS.section_runner;
  const pos = [];
  let timeoutSec = DEFAULT_TIMEOUT_SEC;
  if (process.env.GOS_SECTION_TIMEOUT != null && process.env.GOS_SECTION_TIMEOUT !== '') {
    const t = parseInt(process.env.GOS_SECTION_TIMEOUT, 10);
    if (!(t > 0)) core.die(`GOS_SECTION_TIMEOUT must be a positive integer (seconds), got '${process.env.GOS_SECTION_TIMEOUT}'`);
    timeoutSec = t;
  }
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--timeout') {
      const n = parseInt(args[i + 1], 10);
      if (!(args[i + 1] != null && n > 0)) core.die('Usage: gos section run [name-filter] [--timeout <seconds>]   (--timeout needs a positive integer)');
      timeoutSec = n;
      i++;
    } else if (String(args[i]).startsWith('--')) {
      core.die(`Unknown flag '${args[i]}' — usage: gos section run [name-filter] [--timeout <seconds>]`);
    } else {
      pos.push(args[i]);
    }
  }
  if (pos.length > 1) core.die('Usage: gos section run [name-filter] [--timeout <seconds>]   (at most one name filter)');
  const filter = pos[0] || '';
  if (!probeBash()) core.die(SR.bashMissing);

  const root = core.mapRootDir();
  const allNames = sectionFileNames(root);
  if (!allNames.length) {
    console.log(`- ${SR.noSections}`);
    return;
  }
  if (await confirmSectionList(root, allNames) === 'skip') return;

  // Sections may invoke gos in this project — holding the main lock would
  // deadlock every nested write-class call (gate precedent: user scripts
  // run unlocked).
  core.releaseLock();

  const cacheDir = path.join(root, '.gos', 'cache');
  const base = makeTestbase(cacheDir);
  ownTestbase = base;
  // Full-run log: every byte the runner prints is teed to a per-run file so a
  // failure can be diagnosed from the artifact instead of re-running the suite.
  const logsDir = path.join(cacheDir, 'section-runs');
  fs.mkdirSync(logsDir, { recursive: true });
  const logRel = path.join('.gos', 'cache', 'section-runs',
    `${new Date().toISOString().replace(/[-:]/g, '').replace(/\..+$/, '')}-${(filter || 'all').replace(/[^A-Za-z0-9._-]+/g, '-')}.log`);
  const logStream = fs.createWriteStream(path.join(root, logRel), { flags: 'a' });
  const emit = (s) => { process.stdout.write(s); logStream.write(s); };
  const ranNames = [];
  const timedOut = [];
  const results = {};
  let totalPass = 0;
  let totalFail = 0;
  try {
    for (const fname of allNames) {
      const name = fname.replace(/\.test\.sh$/, '');
      if (filter && !name.includes(filter)) continue;
      ranNames.push(name);
      emit(`=== ${name} ===\n`);
      const r = spawnOneSection(path.join(root, 'test', 'sections', fname), name, base, timeoutSec, emit);
      totalPass += r.pass;
      totalFail += r.fail;
      results[name] = { pass: r.pass, fail: r.fail };
      if (r.timedOut) timedOut.push(name);
    }
  } finally {
    cleanupOwnTestbase();
  }
  sweepStaleTestbases(cacheDir);

  const failedSections = Object.entries(results).filter(([, r]) => r.fail > 0).map(([n, r]) => `${n}(${r.fail})`).sort();
  emit('\n');
  emit(`=== Sections total: ${totalPass} passed, ${totalFail} failed ===\n`);
  if (failedSections.length) emit(`failed sections: ${failedSections.join(', ')}\n`);
  emit(`full log: ${path.join(root, logRel)}\n`);
  logStream.end();
  const wth = core.worktreeContentHash(root);
  core.writeAtomicJson(path.join(root, '.gos', core.GOS_PATHS.run_manifest.rel), {
    schema_version: 2,
    sections_run: ranNames.slice().sort(),
    filter,
    runner_rc: totalFail === 0 ? 0 : 1,
    head_tree: wth ? wth.head_tree : 'unknown',
    patch_sha: wth ? wth.patch_sha : 'unknown',
    timed_out: timedOut.slice().sort(),
    failed_sections: failedSections.map((s) => s.replace(/\(\d+\)$/, '')).sort(),
    results,
    log: logRel,
    finished_at: new Date().toISOString(),
  });
  process.exitCode = totalFail === 0 ? 0 : 1;
}

function cmdSection(args) {
  const sub = String((args || [])[0] || 'run').toLowerCase();
  if (sub === 'trust') { cmdSectionTrust(args.slice(1)); return; }
  if (sub === 'run') {
    cmdSectionRun(args.slice(1)).catch((e) => {
      console.error(`✗ section run failed: ${e && e.message ? e.message : e}`);
      process.exitCode = 1;
    });
    return;
  }
  core.die(`Unknown section subcommand '${sub}'. Usage: gos section run [name-filter] [--timeout <seconds>] | gos section trust`);
}

module.exports = { sectionFileNames, sectionsListHash, loadSectionTrust, saveSectionTrust, confirmSectionList, cmdSectionTrust, probeBash, makeTestbase, sectionChildEnv, spawnOneSection, sweepStaleTestbases, cmdSectionRun, cmdSection };
