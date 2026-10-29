// ops/auto/adapters/registry — host adapter registry + capability negotiation.
//
// Fail-closed contract: a host is selectable for real runs ONLY when all of
// the following hold — (1) the host has a matrix row in registry.json, (2)
// that row's status is 'verified' AND its selectable flag is true (statuses
// 'fixture-tested' and 'probe-pending' are display-only), (3) a live probe
// passes every step: binary version parses, the version satisfies the row's
// version_range via semantic predicates (>=, >, <, <= — identity pins are
// invalid and fail-closed), the help output carries the required flags, and
// the host config root resolves. Unknown hosts, probe failures, and
// non-verified statuses are never selectable. Every probe failure message
// names the matrix entry (host@range [status]) it failed against.
//
// Fixture gating: registry.json `fixture_hosts` rows join the active matrix
// only while GOS_AUTO_TEST_FIXTURE is set; their probe answers come from
// recorded probe_fixture data, never a live spawn. Without the env the
// fixture hosts are unknown.
//
// Locale contract: failures carry { key, params } for auto.host.* entries;
// the inline English `message` is the pre-locale rendering so callers can
// print immediately while locale integration lands separately.
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const REGISTRY_PATH = path.join(__dirname, 'registry.json');
const FIXTURE_ENV = 'GOS_AUTO_TEST_FIXTURE';
const PROBE_TIMEOUT_MS = 15000;
const PROBE_MAX_BUFFER = 4 * 1024 * 1024;
const VALID_STATUSES = ['verified', 'fixture-tested', 'probe-pending'];
const RANGE_OPS = ['>=', '>', '<', '<='];

// Host → adapter module (spawn surface). Display-only hosts still resolve so
// status surfaces can show their recorded fixtures; their spawn is refused.
const ADAPTER_MODULES = {
  opencode: './opencode.cjs',
  codex: './codex.cjs',
  'gos-fixture-host': './opencode.cjs',
};

function fixtureEnvActive(env) {
  return ['1', 'true', 'yes', 'on'].includes(String((env || process.env)[FIXTURE_ENV] || '').trim().toLowerCase());
}

function loadRegistryFile() {
  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(REGISTRY_PATH, 'utf8'));
  } catch (e) {
    return { error: `registry.json unreadable: ${e && e.message}` };
  }
  if (!Array.isArray(raw.matrix)) return { error: 'registry.json: matrix array missing' };
  return { matrix: raw.matrix, fixtureHosts: Array.isArray(raw.fixture_hosts) ? raw.fixture_hosts : [] };
}

// Active matrix rows: base matrix always; fixture rows only under the env gate.
function activeMatrix(env) {
  const reg = loadRegistryFile();
  if (reg.error) return { error: reg.error, rows: [] };
  const rows = fixtureEnvActive(env) ? reg.matrix.concat(reg.fixtureHosts) : reg.matrix.slice();
  return { rows };
}

function entryLabel(entry) {
  return `${entry.host}@${entry.version_range} [${entry.status}]`;
}

// ---------- semantic version predicates ----------

// "1.21.3" → [1,21,3]; undefined when no x.y.z triplet is present.
function parseVersion(text) {
  const m = String(text == null ? '' : text).match(/(\d+)\.(\d+)\.(\d+)/);
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : undefined;
}

function cmpVersion(a, b) {
  for (let i = 0; i < 3; i++) {
    if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1;
  }
  return 0;
}

// Range grammar: space-separated comparators (">=1.18.0 <2.0.0"). Semantic
// predicates only — identity pins ("=1.2.3", bare "1.2.3") are a config
// error and fail closed (the row can never match).
function parseRange(range) {
  const parts = String(range == null ? '' : range).trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return { error: 'empty version_range' };
  const comparators = [];
  for (const p of parts) {
    const m = p.match(/^(>=|>|<=|<)?(\d+)\.(\d+)\.(\d+)$/);
    if (!m || !m[1]) return { error: `invalid comparator '${p}' (semantic predicates >=,>,<,<= only — identity pins forbidden)` };
    comparators.push({ op: m[1], version: [Number(m[2]), Number(m[3]), Number(m[4])] });
  }
  return { comparators };
}

function satisfies(version, range) {
  const v = parseVersion(version);
  if (!v) return { ok: false, error: `unparsable version '${version}'` };
  const pr = parseRange(range);
  if (pr.error) return { ok: false, error: pr.error };
  for (const c of pr.comparators) {
    const r = cmpVersion(v, c.version);
    if (c.op === '>=' && r < 0) return { ok: false };
    if (c.op === '>' && r <= 0) return { ok: false };
    if (c.op === '<' && r >= 0) return { ok: false };
    if (c.op === '<=' && r > 0) return { ok: false };
  }
  return { ok: true };
}

// ---------- config resolution (host state root) ----------

// opencode: $OPENCODE_CONFIG_DIR or ~/.config/opencode; codex: ~/.codex or
// ~/.agents (the same detection shapes setup.cjs uses). Fixture host: always
// resolvable — its world is the recorded fixture.
function configResolve(host, ctx) {
  const c = ctx || {};
  const home = c.home || os.homedir();
  const env = c.env || process.env;
  const candidates = [];
  if (host === 'opencode') {
    if (env.OPENCODE_CONFIG_DIR) candidates.push(env.OPENCODE_CONFIG_DIR);
    candidates.push(path.join(home, '.config', 'opencode'));
  } else if (host === 'codex') {
    candidates.push(path.join(home, '.codex'), path.join(home, '.agents'));
  } else if (host === 'gos-fixture-host') {
    return { ok: true, dir: '(fixture)', detail: 'fixture host — config always resolves under GOS_AUTO_TEST_FIXTURE' };
  } else {
    return { ok: false, detail: `no config resolution rule for host '${host}'` };
  }
  for (const dir of candidates) {
    try { if (fs.statSync(dir).isDirectory()) return { ok: true, dir, detail: `resolved ${dir}` }; } catch { /* candidate absent */ }
  }
  return { ok: false, detail: `no host config root resolves (tried: ${candidates.join(', ')})` };
}

// ---------- probe ----------

// Default live runner: spawnSync with a hard timeout; returns
// { ok, out, err } — ok=false covers spawn errors, non-zero rc, and timeout.
function liveRunner(command, args) {
  let r;
  try {
    r = spawnSync(command, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: PROBE_TIMEOUT_MS, maxBuffer: PROBE_MAX_BUFFER });
  } catch (e) {
    return { ok: false, out: '', err: `spawn exception: ${e && e.message}` };
  }
  if (r.error) return { ok: false, out: '', err: `spawn error: ${r.error.message}` };
  if (r.status !== 0) return { ok: false, out: String(r.stdout || ''), err: `rc=${r.status}` };
  return { ok: true, out: String(r.stdout || ''), err: String(r.stderr || '') };
}

function registryFail(classTag, key, params, message) {
  return { class: classTag, key, params: params || {}, message };
}

// Probe one host against its matrix rows. ctx: { runner, home, env, matrix }
// — runner injectable for tests (signature runner(command, args) →
// {ok,out,err}); matrix injectable for tests (array of matrix rows replacing
// the registry.json load).
function probeHost(host, ctx) {
  const c = ctx || {};
  const runner = c.runner || liveRunner;
  const am = Array.isArray(c.matrix) ? { rows: c.matrix.slice() } : activeMatrix(c.env);
  if (am.error) return { ok: false, steps: [], failure: registryFail('registry-unreadable', 'auto.host.registryUnreadable', { error: am.error }, `host registry unreadable: ${am.error}`) };
  const rows = am.rows.filter((r) => r.host === host);
  if (!rows.length) {
    return { ok: false, steps: [], failure: registryFail('unknown-host', 'auto.host.unknown', { host: String(host) }, `unknown host '${host}' — no matrix entry in registry.json`) };
  }
  const entryList = rows.map(entryLabel).join(', ');

  // Fixture rows answer from recorded data — never a live spawn.
  const fixtureRow = rows.find((r) => r.probe_fixture);
  if (fixtureRow && fixtureEnvActive(c.env)) {
    return {
      ok: true,
      version: fixtureRow.probe_fixture.version,
      matchedEntry: fixtureRow,
      steps: [
        { id: 'version', ok: true, detail: `recorded fixture version ${fixtureRow.probe_fixture.version}` },
        { id: 'help-flags', ok: true, detail: 'recorded fixture: required flags present' },
        { id: 'config-resolve', ok: true, detail: 'recorded fixture: config resolves' },
      ],
    };
  }

  const binary = rows[0].binary || host;
  const steps = [];
  // Help/version text is read from stdout UNION stderr: hosts differ in
  // which stream carries it (observed: opencode prints `run --help` to
  // stderr with rc=0); rc still governs success, so this stays fail-closed.
  const combined = (r) => `${r.out || ''}\n${r.err || ''}`;

  // Step 1: version parses AND satisfies exactly one row's range. A row
  // missing version_command falls back to ['--version'] everywhere the
  // command is rendered, so a missing field classifies a failure instead
  // of crashing.
  const versionCommand = rows[0].version_command || ['--version'];
  const vr = runner(binary, versionCommand);
  const parsed = vr.ok ? parseVersion(combined(vr)) : undefined;
  const versionText = parsed ? parsed.join('.') : null;
  if (!vr.ok || !parsed) {
    const detail = vr.ok ? `no x.y.z version in '${binary} ${versionCommand.join(' ')}' output` : `${binary} ${versionCommand.join(' ')}: ${vr.err || 'no output'}`;
    steps.push({ id: 'version', ok: false, detail });
    return { ok: false, steps, failure: registryFail('probe-version', 'auto.host.probeVersion',
      { host: binary, detail, entries: entryList },
      `host '${host}' probe failed (version step): ${detail} (matrix entries: ${entryList})`) };
  }
  let matched = null;
  const matchErrors = [];
  for (const row of rows) {
    const s = satisfies(versionText, row.version_range);
    if (s.error) matchErrors.push(`${entryLabel(row)}: ${s.error}`);
    else if (s.ok) { matched = row; break; }
  }
  if (matchErrors.length && !matched) {
    steps.push({ id: 'version', ok: false, detail: matchErrors.join('; ') });
    return { ok: false, steps, failure: registryFail('invalid-row', 'auto.host.invalidRow',
      { entries: entryList, detail: matchErrors.join('; ') },
      `host '${host}' probe failed (version step): matrix row(s) invalid — ${matchErrors.join('; ')} (matrix entries: ${entryList})`) };
  }
  if (!matched) {
    const detail = `installed version ${versionText} satisfies no matrix entry`;
    steps.push({ id: 'version', ok: false, detail });
    return { ok: false, steps, failure: registryFail('probe-no-match', 'auto.host.probeNoMatch',
      { host: String(host), version: versionText, entries: entryList },
      `host '${host}' probe failed (version step): ${detail} (matrix entries: ${entryList}) — update the host or add a registry.json row`) };
  }
  steps.push({ id: 'version', ok: true, detail: `${binary} ${versionText} matches ${entryLabel(matched)}` });

  // Step 2: help output carries the required flags.
  const helpCmd = matched.help_command || rows[0].help_command || ['--help'];
  const required = Array.isArray(matched.required_flags) ? matched.required_flags : [];
  const hr = runner(binary, helpCmd);
  if (!hr.ok) {
    const detail = `${binary} ${helpCmd.join(' ')}: ${hr.err || 'no output'}`;
    steps.push({ id: 'help-flags', ok: false, detail });
    return { ok: false, steps, matchedEntry: matched, failure: registryFail('probe-help-flags', 'auto.host.probeHelpFlags',
      { entry: entryLabel(matched), detail },
      `host '${host}' probe failed (help-flags step) against matrix entry ${entryLabel(matched)}: ${detail}`) };
  }
  const missing = required.filter((f) => !combined(hr).includes(f));
  if (missing.length) {
    const detail = `required flag(s) ${missing.join(', ')} absent from '${binary} ${helpCmd.join(' ')}' output`;
    steps.push({ id: 'help-flags', ok: false, detail });
    return { ok: false, steps, matchedEntry: matched, failure: registryFail('probe-help-flags', 'auto.host.probeHelpFlags',
      { entry: entryLabel(matched), flags: missing.join(', ') },
      `host '${host}' probe failed (help-flags step) against matrix entry ${entryLabel(matched)}: ${detail}`) };
  }
  steps.push({ id: 'help-flags', ok: true, detail: required.length ? `flags ${required.join(', ')} present` : 'no flags required' });

  // Step 3: config root resolves.
  const cr = configResolve(host, c);
  steps.push({ id: 'config-resolve', ok: cr.ok, detail: cr.detail });
  if (!cr.ok) {
    return { ok: false, steps, matchedEntry: matched, failure: registryFail('probe-config', 'auto.host.probeConfig',
      { entry: entryLabel(matched), detail: cr.detail },
      `host '${host}' probe failed (config-resolve step) against matrix entry ${entryLabel(matched)}: ${cr.detail}`) };
  }

  return { ok: true, version: versionText, matchedEntry: matched, steps };
}

// Pure evaluation: probe result + matrix row → selectability verdict. Exposed
// so callers can classify stubbed probe results without any spawn.
function evaluateProbe(host, probeResult) {
  const entry = probeResult && probeResult.matchedEntry;
  if (!probeResult || !probeResult.ok) {
    return { selectable: false, entry: entry || null, failure: (probeResult && probeResult.failure) || registryFail('unknown-host', 'auto.host.unknown', { host: String(host) }, `unknown host '${host}' — no matrix entry in registry.json`) };
  }
  if (!entry) return { selectable: false, entry: null, failure: registryFail('no-entry', 'auto.host.unknown', { host: String(host) }, `host '${host}' probe passed but matched no matrix entry`) };
  if (!VALID_STATUSES.includes(entry.status) || (entry.selectable !== true) || entry.status !== 'verified') {
    return { selectable: false, entry, failure: registryFail('status-not-selectable', 'auto.host.statusNotSelectable',
      { entry: entryLabel(entry), status: String(entry.status) },
      `host '${host}' matrix entry ${entryLabel(entry)} is display-only (status not verified) — not selectable for runs`) };
  }
  return { selectable: true, entry, failure: null };
}

// Composite status: matrix + live probe + policy. Fail-closed on every leg.
function hostStatus(host, opts) {
  const o = opts || {};
  const probe = probeHost(host, { runner: o.runner, home: o.home, env: o.env });
  const verdict = evaluateProbe(host, probe);
  return {
    host: String(host),
    known: !!(probe.matchedEntry || (probe.steps && probe.steps.length)),
    status: verdict.entry ? verdict.entry.status : (probe.failure && probe.failure.class === 'unknown-host' ? 'unknown' : 'unmatched'),
    version_range: verdict.entry ? verdict.entry.version_range : null,
    version: probe.version || null,
    selectable: verdict.selectable,
    spawnMode: verdict.entry ? verdict.entry.spawn_mode : null,
    adapter: ADAPTER_MODULES[String(host)] ? String(host) : null,
    entry: verdict.entry,
    probe,
    failure: verdict.failure,
  };
}

function requireAdapter(host) {
  const mod = ADAPTER_MODULES[String(host)];
  return mod ? require(mod) : null;
}

// Credential-class env names stripped from every spawned-session
// environment: runner and delivery credentials (gh, git, ssh, aws) never
// cross the sandbox boundary. Model-provider auth (ANTHROPIC_/OPENAI_/
// GEMINI_/GOOGLE_/OPENROUTER_ API keys) is the one credential class a
// spawned session may read by design.
const STRIP_SPAWN_ENV_EXACT = Object.freeze([
  'GH_TOKEN',
  'GITHUB_TOKEN',
  'GITHUB_ENTERPRISE_TOKEN',
  'GITHUB_PAT',
  'GIT_ASKPASS',
  'GIT_ASKPASS_HELPER',
  'GIT_SSH_COMMAND',
  'GIT_CONFIG',
  'GIT_CONFIG_COUNT',
  'GIT_CONFIG_SYSTEM',
  'GIT_CONFIG_GLOBAL',
  'SSH_AUTH_SOCK',
  'SSH_AGENT_PID',
  'AWS_ACCESS_KEY_ID',
  'AWS_SECRET_ACCESS_KEY',
  'AWS_SESSION_TOKEN',
  'AWS_PROFILE',
  'AWS_DEFAULT_PROFILE',
  'AWS_WEB_IDENTITY_TOKEN_FILE',
]);

// Conservative generic net for the same credential families: GH_/GITHUB_/
// AWS_ names carrying TOKEN/SECRET/KEY/CREDENTIAL after the prefix. Kept
// anchored and case-sensitive so PATH/HOME/LANG/TERM/XDG_* and other
// vendors' keys never match.
const STRIP_SPAWN_ENV_PATTERN = /^(GH|GITHUB|AWS)_.*(TOKEN|SECRET|KEY|CREDENTIAL)/;

// Copy of baseEnv (default process.env) with every credential-class entry
// removed. Callers apply their own overrides AFTER this so runner-injected
// values (OPENCODE_CONFIG_CONTENT, the spawned-session marker) always land.
function sanitizedSpawnEnv(baseEnv) {
  const src = baseEnv && typeof baseEnv === 'object' ? baseEnv : process.env;
  const out = {};
  for (const k of Object.keys(src)) {
    if (STRIP_SPAWN_ENV_EXACT.includes(k)) continue;
    if (STRIP_SPAWN_ENV_PATTERN.test(k)) continue;
    out[k] = src[k];
  }
  return out;
}

module.exports = {
  hostStatus,
  probeHost,
  evaluateProbe,
  activeMatrix,
  satisfies,
  parseRange,
  parseVersion,
  configResolve,
  requireAdapter,
  entryLabel,
  fixtureEnvActive,
  sanitizedSpawnEnv,
  STRIP_SPAWN_ENV_EXACT,
  FAKE_HOST: 'gos-fixture-host',
  FIXTURE_ENV,
  VALID_STATUSES,
};
