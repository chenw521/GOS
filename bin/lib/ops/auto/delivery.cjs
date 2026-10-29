'use strict';

// ops/auto/delivery — probe-gated delivery adapter foundation: the
// three-state delivery probe (origin remote + gh auth + CI presence), the
// pinned repo-git-metadata baseline (origin URL + remote HEAD + .git/config
// hash + the resolved active hooks directory, executable non-sample entries
// only, core.hooksPath redirects followed), drift verification that aborts
// into the breaker, and the env-sanitized privileged git runner. Repo git
// metadata is untrusted: every privileged git invocation re-verifies the
// pinned baseline first and runs with global config, system config, terminal
// prompts, ssh config and local hooks all neutralized, so worker-poisoned
// levers (url.insteadOf, credential.helper, core.sshCommand, planted hooks)
// cannot redirect, capture or ride a privileged push. Every external effect
// (git, gh, fs, clock) is injectable; the defaults are real.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const store = require('./store.cjs');
const core = require('../../core/index.cjs');

// Probe identity persisted into the store probeResults ledger.
const PROBE_HOST = 'delivery';
const PROBE_STATES = Object.freeze(['green', 'advisory', 'absent']);

// Terminal-outcome label for a CI watch that expired without a verdict;
// consumed and re-exported by the publish leg.
const DISPOSITION_UNKNOWN = 'disposition-unknown';

// The pinned baseline file lives inside the machine-local store directory
// (same trust root as the store itself), never inside the repository.
const BASELINE_FILE = 'delivery-baseline.json';

// Locale key for the gh-auth-ok-but-no-CI advisory: the workflows may exist
// while a fine-grained PAT without the workflows read scope cannot see them.
const NO_CI_ADVISORY_KEY = 'auto.delivery.probeAdvisory';

function isPlainObject(v) {
  return v != null && typeof v === 'object' && !Array.isArray(v);
}

function guidanceFor(key, params) {
  const v = core.t(key, params);
  if (typeof v === 'string') return { what: v };
  return v;
}

function sha256Of(text) {
  return crypto.createHash('sha256').update(text, 'utf8').digest('hex');
}

// ---------- defaults ----------

// Baseline-capture legs run under the sanitized environment too (no -c
// argv prefix: core.hooksPath must stay resolvable here so redirects are
// followed). Ambient global/system git config is a poison lever exactly like
// it is for the privileged invocation — pinning must observe the same git
// the privileged call will see, never an insteadOf-rewritten remote.
function defaultGitRunner(args, cwd) {
  return spawnSync('git', args, { encoding: 'utf8', cwd, env: privilegedGitEnv(process.env), stdio: ['ignore', 'pipe', 'pipe'] });
}

function defaultGhRunner(args) {
  return spawnSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

// The privileged spawn itself: never inherited env, never local hooks.
function defaultPrivilegedRunner(argv, cwd, env) {
  return spawnSync('git', argv, { encoding: 'utf8', cwd, env, stdio: ['ignore', 'pipe', 'pipe'] });
}

// ---------- probe: three-state classification ----------

// Pure classification over the three probe facts. Absent covers both
// delivery-inapplicable shapes: no origin remote at all, and an origin the
// gh CLI cannot authenticate against. Advisory is the one degraded-but-
// plausible shape: gh auth works, yet no CI workflows are visible — either
// genuinely none, or a fine-grained PAT false negative.
function classifyProbe(facts) {
  const hasOrigin = facts && facts.hasOrigin === true;
  const ghAuthOk = facts && facts.ghAuthOk === true;
  const ciPresent = facts && facts.ciPresent === true;
  if (!hasOrigin) {
    return { state: 'absent', reason: 'no-origin', guidance: guidanceFor('auto.delivery.probeAbsent', { reason: 'no origin remote' }) };
  }
  if (!ghAuthOk) {
    return { state: 'absent', reason: 'gh-auth', guidance: guidanceFor('auto.delivery.probeAbsent', { reason: 'gh auth not available' }) };
  }
  if (ciPresent) return { state: 'green' };
  return {
    state: 'advisory',
    reason: 'gh-no-ci',
    advisory: NO_CI_ADVISORY_KEY,
    advisoryText: guidanceFor(NO_CI_ADVISORY_KEY),
  };
}

// owner/repo slug off a GitHub remote URL (https or ssh spellings); null for
// non-GitHub remotes or unparseable input.
function extractGithubSlug(url) {
  const raw = String(url || '').trim();
  let m = raw.match(/^https?:\/\/(?:[^/@]+@)?github\.com[/:]([^/]+)\/([^/#?]+?)(?:\.git)?\/?$/i);
  if (!m) m = raw.match(/^git@github\.com:([^/]+)\/([^/#?]+?)(?:\.git)?\/?$/i);
  if (!m) return null;
  return m[1] && m[2] ? `${m[1]}/${m[2]}` : null;
}

// CI presence, local leg: .github/workflows exists and holds at least one
// entry (workflow files or subdirectories — a bare directory with nothing in
// it is no CI).
function workflowsDirHasCi(rootDir) {
  try {
    const dir = path.join(rootDir, '.github', 'workflows');
    const entries = fs.readdirSync(dir);
    return entries.length > 0;
  } catch { return false; }
}

// Gather the three probe facts and persist the outcome. Options (all
// injectable, real defaults): rootDir, gitRunner, ghRunner, now.
function probeDelivery(opts = {}) {
  const rootDir = opts.rootDir ? path.resolve(String(opts.rootDir)) : (core.currentRootRealpath() || process.cwd());
  const gitRunner = typeof opts.gitRunner === 'function' ? opts.gitRunner : defaultGitRunner;
  const ghRunner = typeof opts.ghRunner === 'function' ? opts.ghRunner : defaultGhRunner;
  const now = typeof opts.now === 'function' ? opts.now : Date.now;

  const urlRes = gitRunner(['remote', 'get-url', 'origin'], rootDir);
  const hasOrigin = !!(urlRes && urlRes.status === 0 && String(urlRes.stdout || '').trim());
  const remoteUrl = hasOrigin ? String(urlRes.stdout).trim() : null;

  const authRes = ghRunner(['auth', 'status']);
  const ghAuthOk = !!(authRes && authRes.status === 0);

  // CI presence: local workflows directory first (offline, worker-visible
  // truth); when absent and gh is authenticated, one gh api attempt covers
  // the un-cloned-yet shape — subject to the fine-grained PAT advisory.
  let ciPresent = hasOrigin && workflowsDirHasCi(rootDir);
  let ciSource = ciPresent ? 'workflows-dir' : null;
  let slug = null;
  if (!ciPresent && hasOrigin && ghAuthOk) {
    slug = extractGithubSlug(remoteUrl);
    if (slug) {
      const apiRes = ghRunner(['api', `repos/${slug}/actions/workflows`]);
      if (apiRes && apiRes.status === 0) {
        try {
          const parsed = JSON.parse(String(apiRes.stdout || ''));
          const list = parsed && Array.isArray(parsed.workflows) ? parsed.workflows : null;
          if (list && list.length > 0) { ciPresent = true; ciSource = 'gh-api'; }
        } catch { /* malformed body counts as not visible, never as a crash */ }
      }
    }
  }

  const verdict = classifyProbe({ hasOrigin, ghAuthOk, ciPresent });
  const out = {
    ok: true,
    host: PROBE_HOST,
    state: verdict.state,
    reason: verdict.reason || null,
    remoteUrl,
    ghAuthOk,
    ciPresent,
    ciSource,
  };
  if (verdict.advisory) {
    out.advisory = verdict.advisory;
    out.advisoryText = verdict.advisoryText;
  }
  if (verdict.guidance) out.guidance = verdict.guidance;

  // Persist latest-per-host state (the status source). Persistence failure
  // never changes the probe verdict; it is surfaced for the caller.
  const persist = store.saveProbeResult({ host: PROBE_HOST, state: verdict.state, checkedAtIso: new Date(now()).toISOString() }, rootDir);
  out.persist = persist && persist.ok ? { ok: true, path: persist.path } : { ok: false, reason: persist && persist.reason, path: persist && persist.path };
  return out;
}

// ---------- pinned baseline ----------

function hex64(v) {
  return typeof v === 'string' && /^[0-9a-f]{64}$/.test(v);
}

// Absolute path of the git dir (works in worktrees and .git-file clones).
function resolveGitDir(gitRunner, rootDir) {
  const r = gitRunner(['rev-parse', '--absolute-git-dir'], rootDir);
  const out = r && r.status === 0 ? String(r.stdout || '').trim() : '';
  return out || null;
}

// The active hooks directory with core.hooksPath redirects followed:
// absolute config values win, ~/... expands against the real home, anything
// else resolves against the repository root. The default is <gitDir>/hooks.
function resolveHooksDir(gitRunner, rootDir, gitDir) {
  const cfg = gitRunner(['config', '--get', 'core.hooksPath'], rootDir);
  const raw = cfg && cfg.status === 0 ? String(cfg.stdout || '').trim() : '';
  if (!raw) return gitDir ? path.join(gitDir, 'hooks') : null;
  if (raw.startsWith('~')) return path.join(os.homedir(), raw.slice(1));
  if (path.isAbsolute(raw)) return raw;
  return path.resolve(rootDir, raw);
}

function displayPath(rootDir, abs) {
  const rel = path.relative(rootDir, abs);
  return rel && !rel.startsWith('..') && !path.isAbsolute(rel) ? rel.split(path.sep).join('/') : abs;
}

// Fingerprint the active hooks directory: executable non-sample entries only
// — mode carries any exec bit and the name does not end in .sample. Each
// entry contributes its relative name plus a content hash, so planting,
// removing, de-executing, re-executing or rewriting an active hook all move
// the aggregate hash.
function hooksFingerprint(rootDir, hooksDir) {
  const entries = [];
  let names;
  try { names = fs.readdirSync(hooksDir); }
  catch { return { hooksDir, hooksSha256: sha256Of(''), hooksList: [], display: [] }; }
  for (const name of names.sort()) {
    if (name.endsWith('.sample')) continue;
    const abs = path.join(hooksDir, name);
    let st;
    try { st = fs.statSync(abs); } catch { continue; }
    if (!st.isFile()) continue;
    if (!(st.mode & 0o111)) continue;
    let content = '';
    try { content = fs.readFileSync(abs, 'utf8'); }
    catch { content = '\0unreadable'; }
    entries.push(`${name}:${sha256Of(content)}`);
  }
  return {
    hooksDir,
    hooksSha256: sha256Of(entries.join('\n')),
    display: entries.map((e) => displayPath(rootDir, path.join(hooksDir, e.slice(0, e.indexOf(':'))))),
  };
}

// Pre-flight pin of everything a privileged git call must re-verify:
// remote URL, remote HEAD (ls-remote against the pinned URL), .git/config
// content hash, and the resolved active hooks fingerprint.
function captureBaseline(opts = {}) {
  const rootDir = opts.rootDir ? path.resolve(String(opts.rootDir)) : (core.currentRootRealpath() || process.cwd());
  const gitRunner = typeof opts.gitRunner === 'function' ? opts.gitRunner : defaultGitRunner;

  const urlRes = gitRunner(['remote', 'get-url', 'origin'], rootDir);
  const remoteUrl = urlRes && urlRes.status === 0 ? String(urlRes.stdout || '').trim() : '';
  if (!remoteUrl) {
    return { ok: false, status: 'error', reason: 'no-origin', guidance: guidanceFor('auto.delivery.baselineFailed', { detail: 'no origin remote' }) };
  }
  const headRes = gitRunner(['ls-remote', remoteUrl, 'HEAD'], rootDir);
  if (!headRes || headRes.status !== 0) {
    return {
      ok: false, status: 'error', reason: 'remote-head-unreadable', remoteUrl,
      detail: String((headRes && headRes.stderr) || '').trim().slice(0, 240),
      guidance: guidanceFor('auto.delivery.baselineFailed', { detail: 'git ls-remote of the origin URL failed' }),
    };
  }
  const firstLine = String(headRes.stdout || '').split('\n').map((l) => l.trim()).filter(Boolean)[0] || '';
  const remoteHead = firstLine ? firstLine.split(/\s+/)[0] : null;

  const gitDir = resolveGitDir(gitRunner, rootDir);
  if (!gitDir) {
    return { ok: false, status: 'error', reason: 'git-dir-unreadable', guidance: guidanceFor('auto.delivery.baselineFailed', { detail: 'git dir not resolvable' }) };
  }
  let configText;
  try { configText = fs.readFileSync(path.join(gitDir, 'config'), 'utf8'); }
  catch (e) {
    return { ok: false, status: 'error', reason: 'config-unreadable', detail: e.message, guidance: guidanceFor('auto.delivery.baselineFailed', { detail: '.git/config unreadable' }) };
  }
  const hooksDir = resolveHooksDir(gitRunner, rootDir, gitDir);
  if (!hooksDir) {
    return { ok: false, status: 'error', reason: 'hooks-dir-unresolvable', guidance: guidanceFor('auto.delivery.baselineFailed', { detail: 'hooks directory not resolvable' }) };
  }
  const fp = hooksFingerprint(rootDir, hooksDir);
  const baseline = {
    remoteUrl,
    remoteHead,
    configSha256: sha256Of(configText),
    hooksDir,
    hooksSha256: fp.hooksSha256,
    hooksList: fp.display,
    pinnedAtIso: new Date().toISOString(),
  };
  return { ok: true, baseline };
}

// Pin/load the baseline inside the machine-local store directory (outside
// the repository, outside any sandbox the store root masks).
function baselineFile(rootDir) {
  const root = store.storeRoot(rootDir);
  return root == null ? null : path.join(root, BASELINE_FILE);
}

function pinBaseline(baseline, rootDir) {
  const file = baselineFile(rootDir);
  if (file == null) {
    return { ok: false, status: 'error', reason: 'no-data-home', guidance: guidanceFor('auto.delivery.baselineFailed', { detail: 'no XDG data home resolvable' }) };
  }
  if (!validBaseline(baseline)) {
    return { ok: false, status: 'error', reason: 'invalid-baseline' };
  }
  try { core.writeAtomicJson(file, baseline); }
  catch (e) {
    return { ok: false, status: 'error', reason: 'write-failed', path: file, detail: e.message, guidance: guidanceFor('auto.delivery.baselineFailed', { detail: 'baseline write failed' }) };
  }
  return { ok: true, path: file };
}

function validBaseline(b) {
  return isPlainObject(b)
    && typeof b.remoteUrl === 'string' && b.remoteUrl.length > 0
    && (b.remoteHead == null || typeof b.remoteHead === 'string')
    && hex64(b.configSha256)
    && typeof b.hooksDir === 'string' && b.hooksDir.length > 0
    && hex64(b.hooksSha256)
    && Array.isArray(b.hooksList) && b.hooksList.every((n) => typeof n === 'string');
}

function loadPinnedBaseline(rootDir) {
  const file = baselineFile(rootDir);
  if (file == null) return { ok: false, status: 'error', reason: 'no-data-home' };
  let raw;
  try { raw = fs.readFileSync(file, 'utf8'); }
  catch { return { ok: false, status: 'error', reason: 'no-baseline', path: file, guidance: guidanceFor('auto.delivery.baselineFailed', { detail: 'no pinned baseline found' }) }; }
  let parsed;
  try { parsed = JSON.parse(raw); }
  catch { return { ok: false, status: 'error', reason: 'corrupt-baseline', path: file, guidance: guidanceFor('auto.delivery.baselineFailed', { detail: 'pinned baseline unreadable' }) }; }
  if (!validBaseline(parsed)) {
    return { ok: false, status: 'error', reason: 'corrupt-baseline', path: file, guidance: guidanceFor('auto.delivery.baselineFailed', { detail: 'pinned baseline failed shape validation' }) };
  }
  return { ok: true, path: file, baseline: parsed };
}

// ---------- drift ----------

// Pure comparison: pinned baseline vs a freshly captured snapshot. Returns
// null when identical, else a report naming every moved field and every
// planted/removed/rewritten hook path (display paths relative to the repo
// root when inside it).
function driftBetween(pinned, current) {
  const drift = {};
  if (pinned.remoteUrl !== current.remoteUrl) {
    drift.remoteUrl = { from: pinned.remoteUrl, to: current.remoteUrl };
  }
  if (String(pinned.remoteHead || '') !== String(current.remoteHead || '')) {
    drift.remoteHead = { from: pinned.remoteHead, to: current.remoteHead };
  }
  if (pinned.configSha256 !== current.configSha256) {
    drift.configSha256 = { from: pinned.configSha256, to: current.configSha256 };
  }
  if (String(pinned.hooksDir || '') !== String(current.hooksDir || '') || pinned.hooksSha256 !== current.hooksSha256) {
    const from = new Set(pinned.hooksList || []);
    const to = new Set(current.hooksList || []);
    const added = [...to].filter((n) => !from.has(n));
    const removed = [...from].filter((n) => !to.has(n));
    drift.hooks = {
      hooksDir: { from: pinned.hooksDir, to: current.hooksDir },
      from: pinned.hooksSha256,
      to: current.hooksSha256,
      added,
      removed,
    };
  }
  if (!Object.keys(drift).length) return null;
  drift.detail = driftDetail(drift);
  return drift;
}

function driftDetail(drift) {
  const parts = [];
  if (drift.remoteUrl) parts.push(`remote url ${drift.remoteUrl.from} -> ${drift.remoteUrl.to}`);
  if (drift.remoteHead) parts.push(`remote HEAD ${drift.remoteHead.from} -> ${drift.remoteHead.to}`);
  if (drift.configSha256) parts.push('.git/config content changed');
  if (drift.hooks) {
    if (drift.hooks.added.length) parts.push(`executable hooks added: ${drift.hooks.added.join(', ')}`);
    if (drift.hooks.removed.length) parts.push(`executable hooks removed: ${drift.hooks.removed.join(', ')}`);
    if (!drift.hooks.added.length && !drift.hooks.removed.length) parts.push('active executable hooks changed');
  }
  return parts.join('; ');
}

// ---------- sanitized privileged git ----------

// Environment for privileged git: global and system git config neutralized,
// terminal prompts impossible, ssh pinned to no config file — worker-
// poisoned ~/.gitconfig or ssh config levers cannot redirect or capture.
function privilegedGitEnv(baseEnv) {
  return {
    ...(baseEnv || {}),
    GIT_CONFIG_GLOBAL: '/dev/null',
    GIT_CONFIG_SYSTEM: '/dev/null',
    GIT_TERMINAL_PROMPT: '0',
    GIT_SSH_COMMAND: 'ssh -F none',
  };
}

// Argument prefix for privileged git: local hooks can never run.
function privilegedGitArgs(args) {
  return ['-c', 'core.hooksPath=/dev/null', ...(Array.isArray(args) ? args : [])];
}

// Re-capture the live snapshot and compare against the pinned baseline.
// Options: rootDir, gitRunner. Returns {ok:true, drift:null} or
// {ok:false, status:'aborted', reason:'drift', drift} / capture errors.
function verifyBaseline(baseline, opts = {}) {
  const rootDir = opts.rootDir ? path.resolve(String(opts.rootDir)) : (core.currentRootRealpath() || process.cwd());
  const gitRunner = typeof opts.gitRunner === 'function' ? opts.gitRunner : defaultGitRunner;
  if (!validBaseline(baseline)) {
    return { ok: false, status: 'error', reason: 'invalid-baseline', guidance: guidanceFor('auto.delivery.baselineFailed', { detail: 'baseline failed shape validation' }) };
  }
  const cur = captureBaseline({ rootDir, gitRunner });
  if (!cur.ok) {
    return { ok: false, status: 'error', reason: cur.reason, detail: cur.detail, guidance: cur.guidance };
  }
  const drift = driftBetween(baseline, cur.baseline);
  if (drift) {
    return {
      ok: false, status: 'aborted', reason: 'drift', drift,
      guidance: guidanceFor('auto.delivery.driftDetected', { detail: drift.detail }),
    };
  }
  return { ok: true, drift: null };
}

// One privileged git invocation. The pinned baseline is re-verified against
// live repo metadata BEFORE anything runs; any drift aborts into the breaker
// (env class — trust in the repository environment is broken, not the task)
// and the git call never happens. Options: rootDir, baseline (or the pinned
// file is loaded), gitRunner (baseline capture legs), privilegedRunner (the
// sanitized invocation itself), env.
function runPrivilegedGit(args, opts = {}) {
  const rootDir = opts.rootDir ? path.resolve(String(opts.rootDir)) : (core.currentRootRealpath() || process.cwd());
  const gitRunner = typeof opts.gitRunner === 'function' ? opts.gitRunner : defaultGitRunner;
  const privilegedRunner = typeof opts.privilegedRunner === 'function' ? opts.privilegedRunner : defaultPrivilegedRunner;
  const argv = privilegedGitArgs(args);

  let baseline = opts.baseline;
  if (baseline == null) {
    const pinned = loadPinnedBaseline(rootDir);
    if (!pinned.ok) {
      return { ok: false, status: 'error', reason: pinned.reason, path: pinned.path, guidance: pinned.guidance };
    }
    baseline = pinned.baseline;
  }

  const verified = verifyBaseline(baseline, { rootDir, gitRunner });
  if (!verified.ok) {
    if (verified.reason === 'drift') {
      // Drift aborts into the breaker: the loop must stop trusting this
      // repository environment until a human re-pins.
      const rec = store.recordBreaker({ cls: 'env', detail: `delivery drift: ${verified.drift.detail}` }, rootDir);
      return {
        ok: false, status: 'aborted', reason: 'drift', drift: verified.drift, argv,
        guidance: verified.guidance,
        breaker: rec && rec.ok ? { ok: true, record: rec.record } : { ok: false, reason: rec && rec.reason },
      };
    }
    return { ok: false, status: 'error', reason: verified.reason, detail: verified.detail, guidance: verified.guidance };
  }

  const env = privilegedGitEnv(opts.env || process.env);
  const res = privilegedRunner(argv, rootDir, env);
  return {
    ok: !!(res && res.status === 0),
    status: res && res.status === 0 ? 'ok' : 'git-failed',
    rc: res ? res.status : null,
    stdout: String((res && res.stdout) || ''),
    stderr: String((res && res.stderr) || ''),
    argv,
    drift: null,
  };
}

module.exports = {
  PROBE_HOST,
  PROBE_STATES,
  DISPOSITION_UNKNOWN,
  NO_CI_ADVISORY_KEY,
  classifyProbe,
  extractGithubSlug,
  probeDelivery,
  captureBaseline,
  pinBaseline,
  loadPinnedBaseline,
  driftBetween,
  privilegedGitEnv,
  privilegedGitArgs,
  verifyBaseline,
  runPrivilegedGit,
};
