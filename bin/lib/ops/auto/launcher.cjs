// ops/auto/launcher — capability-profile composition for sandboxed spawns.
// Composes bubblewrap argument vectors with mask-over-bind ordering (binds
// first, tmpfs/empty masks layered over them, runner-held seed ro-binds
// last), probes the sandbox engine chain (bwrap, degrading to a lexical
// tier when absent), unions profile deny baselines one-way over the user's
// resolved permission config, and scans captured spawn streams for deny
// escapes. Profiles are tracked JSON data under templates/auto-profiles/.
'use strict';

const core = require('../../core/index.cjs');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('node:crypto');
const { spawnSync } = require('child_process');

const PROFILE_DIR = path.join(core.GOS_SELF_ROOT, 'templates', 'auto-profiles');
const KNOWN_PROFILES = Object.freeze(['restricted', 'workspace', 'full']);
const DEFAULT_PROFILE = 'restricted';
const EMPTY_SRC = '/dev/null'; // empty-mount source for masked file paths

// Mask paths every profile must carry, as profile tokens: the runner trust
// store prefix, delivery credentials (gh/git/ssh/netrc), global git config,
// and host state dirs. compose() fails closed when a profile drops any.
const MANDATORY_MASK_TOKENS = Object.freeze([
  '$GOS_STORE',
  '$HOME/.config/gh',
  '$HOME/.gitconfig',
  '$HOME/.git-credentials',
  '$HOME/.config/git',
  '$HOME/.ssh',
  '$HOME/.netrc',
  '$HOME/.aws',
  '$HOME/.gnupg',
  '$HOME/.config/opencode',
  '$HOME/.local/share/opencode',
  '$HOME/.cache/opencode',
]);

// Engine probe chain, strongest first. v1 ships bwrap only; later engines
// (landlock helper, systemd-run) append here and the tier degrades to
// 'lexical' when none is present.
const ENGINE_CHAIN = Object.freeze([
  { name: 'bwrap', tier: 'bubblewrap' },
]);

const MASK_KINDS = Object.freeze(['tmpfs', 'empty', 'seed']);
const DENY_BASELINE_SNAPSHOT = 'deny-baseline';
const SEED_SNAPSHOT_NAMES = Object.freeze(['host-config', 'host-data']);
// Fallback deny floor for the detector when the default profile file cannot
// be read (fail toward detection, never toward silence).
const DETECTOR_FLOOR_DENY = Object.freeze(['sudo', 'su -', 'su root', 'gos auto']);

// Profile tokens resolve to machine-absolute paths at compose time so the
// tracked JSON stays correct on every host.
function resolveTokenPath(p, env) {
  const e = env || process.env;
  const home = e.HOME || os.homedir();
  const xdgData = e.XDG_DATA_HOME && String(e.XDG_DATA_HOME).trim()
    ? String(e.XDG_DATA_HOME)
    : path.join(home, '.local', 'share');
  if (p === '$GOS_STORE') return path.join(xdgData, 'gos');
  if (p === '$HOME') return home;
  if (typeof p === 'string' && p.startsWith('$HOME/')) return path.join(home, p.slice('$HOME/'.length));
  return p;
}

function loadProfile(name) {
  if (typeof name !== 'string' || !KNOWN_PROFILES.includes(name)) {
    return { ok: false, code: 'auto.launcher.unknown-profile', name: name || null, known: KNOWN_PROFILES.slice() };
  }
  const file = path.join(PROFILE_DIR, `${name}.json`);
  let raw;
  try { raw = fs.readFileSync(file, 'utf8'); }
  catch (e) { return { ok: false, code: 'auto.launcher.profile-unreadable', name, file, detail: e.message }; }
  let obj;
  try { obj = JSON.parse(raw); }
  catch (e) { return { ok: false, code: 'auto.launcher.profile-corrupt', name, file, detail: e.message }; }
  const bad = (detail) => ({ ok: false, code: 'auto.launcher.profile-corrupt', name, file, detail });
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return bad('root is not a JSON object');
  if (!Array.isArray(obj.deny)) return bad('deny is not an array');
  if (!Array.isArray(obj.writable)) return bad('writable is not an array');
  if (!Array.isArray(obj.masks) || !obj.masks.length) return bad('masks is not a non-empty array');
  for (const m of obj.masks) {
    if (!m || typeof m !== 'object') return bad('mask entry is not an object');
    if (typeof m.path !== 'string' || !m.path) return bad('mask entry lacks a string path');
    if (!MASK_KINDS.includes(m.kind)) return bad(`mask ${m.path} has unknown kind ${JSON.stringify(m.kind)}`);
    if (m.kind === 'seed' && typeof m.seed !== 'string') return bad(`seed mask ${m.path} lacks a seed name`);
  }
  return { ok: true, profile: obj, file };
}

// Fail-closed check that the profile carries every mandatory mask token.
function missingMandatoryMasks(maskEntries) {
  const present = new Set(maskEntries.map((m) => m.path));
  return MANDATORY_MASK_TOKENS.filter((t) => !present.has(t));
}

// Engine probe. opts.engineProbe (stub) short-circuits the chain for tests;
// otherwise each candidate is probed with `<name> --version` under opts.env.
function probeEngine(opts) {
  const o = opts || {};
  const probed = ENGINE_CHAIN.map((c) => c.name).join('->');
  if (typeof o.engineProbe === 'function') {
    const r = o.engineProbe() || {};
    const hit = ENGINE_CHAIN.find((c) => c.name === r.engine);
    if (hit) return { engine: hit.name, tier: hit.tier, version: r.version || null, probed };
    return { engine: null, tier: 'lexical', reason: r.reason || 'engine unavailable', probed };
  }
  const env = o.env || process.env;
  for (const c of ENGINE_CHAIN) {
    let r;
    try { r = spawnSync(c.name, ['--version'], { env, encoding: 'utf8' }); }
    catch { r = { error: new Error('spawn failed') }; }
    if (r && !r.error && r.status === 0) {
      // Version presence is not capability: a binary that cannot map a user
      // namespace (kernel policy, AppArmor, setuid helpers missing) would
      // report a bubblewrap tier whose every spawn dies at setup. Probe with
      // a minimal real sandbox before trusting the engine.
      let cap = null;
      try {
        cap = spawnSync(c.name, [
          '--ro-bind', '/usr', '/usr',
          '--ro-bind-try', '/bin', '/bin',
          '--ro-bind-try', '/lib', '/lib',
          '--ro-bind-try', '/lib64', '/lib64',
          '--dev', '/dev', '--proc', '/proc',
          '--', '/bin/true',
        ], { env, encoding: 'utf8', timeout: 15000 });
      } catch { cap = { error: new Error('capability probe failed') }; }
      if (cap && !cap.error && cap.status === 0) {
        return { engine: c.name, tier: c.tier, version: (r.stdout || '').trim() || null, probed };
      }
      return {
        engine: null, tier: 'lexical',
        reason: `${c.name} present but cannot start a sandbox: ${cap && cap.error ? cap.error.message : 'uid map or mount setup refused'}`,
        probed,
      };
    }
  }
  return { engine: null, tier: 'lexical', reason: 'no sandbox engine found on PATH', probed };
}

// ---- argv composer ---------------------------------------------------------

const SRC_DEST_OPS = Object.freeze(['--ro-bind', '--ro-bind-try', '--bind', '--bind-try', '--dev-bind']);
const DEST_ONLY_OPS = Object.freeze(['--tmpfs', '--proc', '--dev', '--dir']);

function parseArgvOps(argv) {
  const ops = [];
  for (let i = 0; i < argv.length;) {
    const t = argv[i];
    if (SRC_DEST_OPS.includes(t)) { ops.push({ op: t, src: argv[i + 1], dest: argv[i + 2], index: i }); i += 3; }
    else if (DEST_ONLY_OPS.includes(t)) { ops.push({ op: t, dest: argv[i + 1], index: i }); i += 2; }
    else i += 1; // flags and the trailing command take no parsed operands
  }
  return ops;
}

// True when `anc` equals `desc` or is a path-prefix directory of it.
function isAncestorPath(anc, desc) {
  const a = path.resolve(String(anc));
  const d = path.resolve(String(desc));
  return a === d || d.startsWith(a + path.sep);
}

// Argument ordering: system ro-binds, home/workspace binds, adapter writable
// binds, then every tmpfs/empty mask OVER the binds (bwrap later-mount-wins,
// so masks must come after any bind they cover), then seed ro-binds inside
// seeded tmpfs mounts. Mask entries must not nest inside each other.
// The repository .git dir is bound read-write right after its read-only
// workspace: every stage session runs `gos commit`, which writes
// .git/objects and the index, so a read-only .git would dead-end every
// kernel-tier spawn. .git is never a mask dest, so masks keep winning for
// store/credential paths.
function composeArgv(ctx) {
  const argv = [
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
  // DNS: a stub resolv.conf managed by systemd-resolved or NetworkManager
  // symlinks outside /etc into /run, which is not mounted — the link would
  // dangle and name resolution would die inside the sandbox
  if (ctx.resolvBind) argv.push('--ro-bind-try', ctx.resolvBind, ctx.resolvBind);
  if (ctx.home) argv.push('--ro-bind-try', ctx.home, ctx.home);
  if (ctx.workspace) {
    argv.push('--ro-bind', ctx.workspace, ctx.workspace);
    const gitDir = path.join(ctx.workspace, '.git');
    argv.push('--bind', gitDir, gitDir);
  }
  for (const w of ctx.writableRoots) argv.push('--bind', w, w);
  for (const rb of (ctx.roBinds || [])) argv.push('--ro-bind', rb, rb);
  // Shallowest dest first: an ancestor tmpfs mounted before a nested mask
  // lets the deeper mount win explicitly, so nested hides stay visible in argv.
  const orderedMasks = ctx.masks.slice().sort((a, b) => a.dest.split(path.sep).length - b.dest.split(path.sep).length || (a.dest < b.dest ? -1 : 1));
  for (const m of orderedMasks) {
    if (m.kind === 'empty') argv.push('--ro-bind', EMPTY_SRC, m.dest);
    else argv.push('--tmpfs', m.dest); // tmpfs and seed kinds
  }
  const seeds = {};
  const seedsSkipped = [];
  for (const m of orderedMasks) {
    if (m.kind !== 'seed') continue;
    const root = ctx.seedRoots ? ctx.seedRoots[m.seed] : null;
    if (!root) { seedsSkipped.push(m.seed); continue; }
    const abs = path.resolve(String(root));
    let entries;
    try { entries = fs.readdirSync(abs, { withFileTypes: true }); }
    catch { seedsSkipped.push(m.seed); continue; }
    seeds[m.seed] = abs;
    for (const e of entries) argv.push('--ro-bind', path.join(abs, e.name), path.join(m.dest, e.name));
  }
  for (const af of (ctx.authFiles || [])) argv.push('--ro-bind', af.src, af.dest);
  return { argv, seeds, seedsSkipped };
}

// maskOverBindHolds(spec) — ordering invariant checker. Accepts a compose()
// result object (full check via meta.masks) or a raw argv array
// (ordering-only check). Full check per mask: (1) a tmpfs or empty mount
// exists at the mask dest, (2) any bind covering that dest comes BEFORE the
// mask mount, (3) no later op remounts the dest or an ancestor of it, and
// (4) later ops strictly inside the dest are only ro-binds sourced from a
// recorded runner-held seed root.
function maskMountOp(ops, mask, emptySrc) {
  const impl = ops.filter((o) => {
    if (o.dest !== mask.dest) return false;
    if (mask.kind === 'empty') return o.op === '--ro-bind' && o.src === (emptySrc || EMPTY_SRC);
    return o.op === '--tmpfs';
  });
  return impl.length ? impl[impl.length - 1] : null; // last mount wins
}

function maskOverBindHolds(spec) {
  let argv;
  let meta = null;
  if (Array.isArray(spec)) argv = spec;
  else if (spec && Array.isArray(spec.argv)) {
    argv = spec.argv;
    meta = spec.meta && typeof spec.meta === 'object' ? spec.meta : null;
  } else return false;
  const ops = parseArgvOps(argv);
  if (ops.some((o) => typeof o.dest !== 'string' || !o.dest || !path.isAbsolute(o.dest))) return false;
  if (!meta || !Array.isArray(meta.masks)) {
    for (const o of ops) {
      if (o.op !== '--tmpfs') continue;
      for (const later of ops) {
        if (later.index <= o.index) continue;
        if (isAncestorPath(later.dest, o.dest)) return false;
      }
    }
    return true;
  }
  const seedRoots = Object.values(meta.seeds || {}).map(String);
  for (const m of meta.masks) {
    if (!m || typeof m.dest !== 'string' || !m.dest) return false;
    const mo = maskMountOp(ops, m, meta.emptySrc);
    if (!mo) return false;
    for (const b of ops) {
      if (!SRC_DEST_OPS.includes(b.op)) continue;
      if (!isAncestorPath(b.dest, m.dest)) continue; // bind covering the mask path
      if (b.index > mo.index) return false;          // a later bind would re-expose it
    }
    for (const later of ops) {
      if (later.index <= mo.index) continue;
      if (isAncestorPath(later.dest, m.dest)) {
        // a later ancestor mount normally re-exposes, except when it is
        // itself another recorded mask (an ancestor tmpfs hides more,
        // never less)
        const ancestorMask = meta.masks.some((n) => n !== m && n.dest === later.dest
          && maskMountOp([later], n, meta.emptySrc));
        if (!ancestorMask) return false;
        continue;
      }
      if (isAncestorPath(m.dest, later.dest)) {
        const seeded = later.op === '--ro-bind' && typeof later.src === 'string'
          && seedRoots.some((r) => isAncestorPath(r, later.src));
        const authed = later.op === '--ro-bind' && typeof later.src === 'string'
          && Array.isArray(meta.authFiles) && meta.authFiles.some((a) => a.src === later.src);
        const nestedMask = meta.masks.some((n) => n !== m && n.dest === later.dest
          && maskMountOp([later], n, meta.emptySrc));
        if (!seeded && !authed && !nestedMask) return false; // deeper mask mounts win; anything else re-exposes
      }
    }
  }
  return true;
}

// ---- read-union-inject -----------------------------------------------------

// Store dependency is lazy: injected via opts.store when present, else a
// require at call time so this module loads before store.cjs exists.
function getStore(opts) {
  if (opts && opts.store) return opts.store;
  try { return require('./store.cjs'); }
  catch { return null; }
}

function readUserConfigFromDisk(env) {
  const e = env || process.env;
  if (e.OPENCODE_CONFIG_CONTENT) {
    try {
      const obj = JSON.parse(e.OPENCODE_CONFIG_CONTENT);
      if (obj && typeof obj === 'object') return obj;
    } catch { /* fall through to config files */ }
  }
  const home = e.HOME || os.homedir();
  const cfgDir = e.OPENCODE_CONFIG_DIR || path.join(home, '.config', 'opencode');
  try {
    const obj = JSON.parse(fs.readFileSync(path.join(cfgDir, 'opencode.json'), 'utf8'));
    if (obj && typeof obj === 'object') return obj;
  } catch { /* missing or unparsable user config is a legal empty base */ }
  return {};
}

// Snapshot read bridge: accepts either store surface — loadSnapshot(name),
// or load() returning {ok, store:{snapshots:{[kind]:{content, sha256}}}} —
// trying each candidate kind name in order. Missing or paused stores
// resolve to null (safe empty base, never a crash).
function readSnapshotEntry(store, candidates) {
  if (!store) return null;
  if (typeof store.loadSnapshot === 'function') {
    for (const k of candidates) {
      try {
        const snap = store.loadSnapshot(k);
        if (snap && typeof snap.content === 'string') return snap;
      } catch { /* next candidate */ }
    }
    return null;
  }
  if (typeof store.load === 'function') {
    let r;
    try { r = store.load(); } catch { return null; }
    const snaps = r && r.ok && r.store && r.store.snapshots ? r.store.snapshots : null;
    if (!snaps) return null;
    for (const k of candidates) {
      const e = snaps[k];
      if (e && typeof e.content === 'string') return e;
    }
  }
  return null;
}

// Resolved permission read, runner-held view, in precedence order:
// injected config object > store deny-baseline snapshot > disk/env config.
function readResolvedPermissionConfig(opts) {
  const o = opts || {};
  if (o.userConfig && typeof o.userConfig === 'object') return o.userConfig;
  const snap = readSnapshotEntry(getStore(o), [DENY_BASELINE_SNAPSHOT, 'denyBaseline']);
  if (snap) {
    try {
      const cfg = JSON.parse(snap.content);
      if (cfg && typeof cfg === 'object') return cfg;
    } catch { /* fall through to disk */ }
  }
  return readUserConfigFromDisk(o.env);
}

// One-way deny union: user entries first, profile entries appended, no
// removals — injecting a profile deny over a stricter user deny can only
// grow the set.
function unionDeny(userDeny, profileDeny) {
  const out = [];
  const seen = new Set();
  for (const d of [...(Array.isArray(userDeny) ? userDeny : []), ...(Array.isArray(profileDeny) ? profileDeny : [])]) {
    const k = String(d);
    if (!seen.has(k)) { seen.add(k); out.push(k); }
  }
  return out;
}

// Merge the profile deny into a resolved config object without touching any
// other key (allow lists, edit/webfetch policy, arbitrary user keys survive).
function injectPermissionConfig(userConfig, profileDeny) {
  const base = userConfig && typeof userConfig === 'object' && !Array.isArray(userConfig) ? userConfig : {};
  const merged = { ...base };
  const perm = { ...((merged.permission && typeof merged.permission === 'object') ? merged.permission : {}) };
  // Host permission rules are shaped as capability -> { command pattern ->
  // action literal }, so each deny entry becomes a key mapped to "deny".
  // A key already carrying an allow from the user config is overwritten:
  // the deny union is one-way.
  const bash = { ...((perm.bash && typeof perm.bash === 'object') ? perm.bash : {}) };
  const legacyDeny = Array.isArray(bash.deny) ? bash.deny : [];
  delete bash.deny;
  const denyPatterns = unionDeny(legacyDeny, profileDeny);
  for (const p of denyPatterns) bash[String(p)] = 'deny';
  perm.bash = bash;
  merged.permission = perm;
  return { config: merged, denyPatterns };
}

// ---- snapshots (store-facing helpers) --------------------------------------

// Load host-state seed snapshots through the store bridge; unreadable or
// missing names map to null (the spawn then sees an empty tmpfs there).
// Seed names bridge to the store's hostSeed snapshot kind.
function seedSnapshots(store, names) {
  const want = Array.isArray(names) && names.length ? names : SEED_SNAPSHOT_NAMES.slice();
  const out = {};
  for (const n of want) {
    out[n] = readSnapshotEntry(store, [n, 'hostSeed']);
  }
  return out;
}

// Persist the runner-held deny baseline into the store. Signature is
// detected from the save function arity: (kind, content) for the store
// module, (name, {content, sha256}) for injected two-argument stores.
function recordDenyBaseline(store, configObj) {
  const content = JSON.stringify(configObj && typeof configObj === 'object' ? configObj : {});
  const sha256 = crypto.createHash('sha256').update(content, 'utf8').digest('hex');
  if (store && typeof store.saveSnapshot === 'function') {
    const res = store.saveSnapshot.length >= 3
      ? store.saveSnapshot('denyBaseline', content)
      : store.saveSnapshot(DENY_BASELINE_SNAPSHOT, { content, sha256 });
    return { ...(res && typeof res === 'object' ? res : {}), content, sha256 };
  }
  return { ok: false, reason: 'no-store', content, sha256 };
}

// ---- escape detector -------------------------------------------------------

// Deny pattern -> line matcher: `*` and `?` are glob chars, everything else
// is literal; a word boundary guards the start (and the end when the pattern
// ends on a word character) so short tokens do not fire inside longer words.
function globToRegExp(pattern) {
  let body = '';
  for (const ch of String(pattern)) {
    if (ch === '*') body += '.*';
    else if (ch === '?') body += '.';
    else body += ch.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }
  const tail = /\w$/.test(String(pattern)) ? '\\b' : '';
  return new RegExp(`\\b${body}${tail}`);
}

// Scan a captured spawn stream for deny-pattern hits. Defaults to the
// restricted profile deny baseline; pass opts.deny to scan the actual
// injected union. Returns an array of {pattern, match, line} hits.
function scanSpawnOutput(text, opts) {
  const o = opts || {};
  let deny;
  if (Array.isArray(o.deny)) deny = o.deny.map(String);
  else {
    const lp = loadProfile(DEFAULT_PROFILE);
    deny = lp.ok ? lp.profile.deny.map(String) : DETECTOR_FLOOR_DENY.slice();
  }
  const hits = [];
  for (const line of String(text == null ? '' : text).split(/\r?\n/)) {
    if (!line) continue;
    for (const pat of deny) {
      const m = globToRegExp(pat).exec(line);
      if (m) hits.push({ pattern: pat, match: m[0], line: line.slice(0, 240) });
    }
  }
  return hits;
}

// Streaming form of the escape detector: deny patterns match against every
// line AS IT ARRIVES, so a large benign tail can never push early deny
// lines out of the captured window before the post-hoc scan runs. Line
// fragments carry across feed() calls.
function makeStreamDenyScanner(opts) {
  const o = opts || {};
  let deny;
  if (Array.isArray(o.deny)) deny = o.deny.map(String);
  else {
    const lp = loadProfile(DEFAULT_PROFILE);
    deny = lp.ok ? lp.profile.deny.map(String) : DETECTOR_FLOOR_DENY.slice();
  }
  const seen = [];
  let buf = '';
  const scanBuffer = (flush) => {
    const lines = buf.split(/\r?\n/);
    buf = flush ? '' : lines.pop(); // keep the trailing fragment for the next chunk
    for (const line of lines) {
      if (!line) continue;
      for (const pat of deny) {
        const m = globToRegExp(pat).exec(line);
        if (m) seen.push({ pattern: pat, match: m[0], line: line.slice(0, 240), preTruncation: true });
      }
    }
  };
  return {
    feed(chunk) { buf += String(chunk); scanBuffer(false); },
    flush() { scanBuffer(true); },
    hits: seen,
  };
}

// Sanitized host-config seed: the runner is the gatekeeper of what a spawn
// sees of the host's opencode config. Provider API keys, mcp server
// definitions (env/headers carry credentials), and permission expansions
// are stripped — the spawn gets the model/provider shape, never the keys,
// never a second permission source competing with the injected deny.
// Executable-ish trees (agents/commands/plugins) are skipped wholesale:
// their frontmatter can widen tools beyond the profile's intent.
const SEED_SKIP_ENTRIES = new Set(['agent', 'agents', 'command', 'commands', 'plugin', 'plugins', 'node_modules', 'log', 'cache', 'storage']);
const SANITIZE_STRIP_KEYS = new Set(['apikey', 'api_key', 'mcp', 'permission']);

function stripSecretsDeep(v, stripped, trail) {
  if (Array.isArray(v)) { for (const x of v) stripSecretsDeep(x, stripped, trail); return v; }
  if (v && typeof v === 'object') {
    for (const k of Object.keys(v)) {
      const kk = String(k).toLowerCase();
      if (SANITIZE_STRIP_KEYS.has(kk)) {
        delete v[k];
        stripped.push(`${trail}${k}`);
      } else {
        stripSecretsDeep(v[k], stripped, `${trail}${k}.`);
      }
    }
  }
  return v;
}

function sanitizeHostConfig(env) {
  const dirRaw = resolveTokenPath('$HOME/.config/opencode', env);
  let dir;
  try { dir = fs.realpathSync(dirRaw); } catch { return { ok: false, reason: 'absent', dir: dirRaw }; }
  let st;
  try { st = fs.statSync(dir); } catch { return { ok: false, reason: 'absent', dir }; }
  if (!st.isDirectory()) return { ok: false, reason: 'not-a-dir', dir };
  const files = {};
  const stripped = [];
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
  catch (e) { return { ok: false, reason: 'unreadable', dir, detail: e.message }; }
  for (const e of entries) {
    if (SEED_SKIP_ENTRIES.has(e.name.toLowerCase())) { stripped.push(`${e.name}/ (executable tree skipped)`); continue; }
    if (!e.isFile()) { stripped.push(`${e.name} (non-file skipped)`); continue; }
    if (/\.(json|jsonc|toml|ya?ml|txt|md)$/i.test(e.name) === false) { stripped.push(`${e.name} (non-config skipped)`); continue; }
    const p = path.join(dir, e.name);
    let text;
    try { text = fs.readFileSync(p, 'utf8'); } catch { stripped.push(`${e.name} (unreadable skipped)`); continue; }
    if (text.length > 1024 * 1024) { stripped.push(`${e.name} (oversized skipped)`); continue; }
    if (/\.jsonc?$/i.test(e.name)) {
      try {
        const obj = JSON.parse(text);
        stripSecretsDeep(obj, stripped, `${e.name}:`);
        files[e.name] = JSON.stringify(obj, null, 2);
        continue;
      } catch { /* not valid JSON — seed as opaque text */ }
    }
    files[e.name] = text;
  }
  return { ok: true, dir, files, stripped };
}

// Materialize a sanitized snapshot dir for seedRoots consumption; the caller
// owns cleanup of the returned directory.
function materializeSeedDir(files, baseDir, prefix) {
  const dir = fs.mkdtempSync(path.join(baseDir, `${prefix}-`));
  for (const [name, content] of Object.entries(files || {})) {
    fs.writeFileSync(path.join(dir, name), content);
  }
  return dir;
}

// ---- compose ---------------------------------------------------------------

// compose(profileName, opts) -> { ok, profile, tier, engine, argv, env, deny,
// meta } on success, or { ok: false, code, ... } fail-closed results.
// opts:
//   allowFull      boolean  explicit gate for the full profile
//   workspace      string   repo root, ro-bound into the sandbox
//   writableRoots  string[] adapter-declared writable binds (e.g. .gos/, scratch)
//   seedRoots      object   seed name -> materialized snapshot dir on disk
//   store          object   store API injection (saveSnapshot/loadSnapshot);
//                           defaults to a lazy require of ./store.cjs
//   env            object   env for token resolution and the engine probe
//   engineProbe    function () -> {engine, version?, reason?} probe stub
//   userConfig     object   resolved permission config override (tests/runner)
function compose(profileName, opts) {
  const o = opts || {};
  const env = o.env || process.env;
  const probe = probeEngine(o);
  const base = { tier: probe.tier, engine: probe.engine };
  const name = typeof profileName === 'string' && profileName ? profileName : DEFAULT_PROFILE;
  const load = loadProfile(name);
  if (!load.ok) return { ok: false, code: load.code, profile: name, ...base, ...(load.known ? { known: load.known } : {}), ...(load.detail ? { detail: load.detail } : {}), ...(load.file ? { file: load.file } : {}) };
  if (name === 'full' && !o.allowFull) {
    return { ok: false, code: 'auto.launcher.full-flag-required', profile: name, ...base };
  }
  const missing = missingMandatoryMasks(load.profile.masks);
  if (missing.length) {
    return { ok: false, code: 'auto.launcher.missing-mandatory-mask', profile: name, ...base, missing };
  }
  const resolved = load.profile.masks.map((m) => ({ ...m, dest: path.resolve(resolveTokenPath(m.path, env)) }));
  // A masked path is only mountable when the sandbox sees a real file or
  // directory at the destination: bwrap cannot create a missing mountpoint
  // on a read-only bind, and it refuses to mount over a symlink. Credential
  // files that are absent or dangle outside the bind set are skipped (they
  // are already invisible). Host-state directories are different: the host
  // process needs those paths to EXIST and be writable inside the sandbox,
  // so an unmountable destination climbs to its nearest real ancestor and
  // mounts the tmpfs there — deeper mask mounts still win, so nested masks
  // (for example the trust store under a masked share dir) stay hidden. A
  // symlink whose real target lives inside the home bind is masked at the
  // resolved path instead.
  const homeRoot = env.HOME || os.homedir();
  const masks = [];
  const masksSkipped = [];
  for (const m of resolved) {
    let st = null;
    try { st = fs.lstatSync(m.dest); } catch { st = null; }
    if (st && !st.isSymbolicLink()) { masks.push(m); continue; }
    let real = null;
    if (st) { try { real = fs.realpathSync(m.dest); } catch { real = null; } }
    let rst = null;
    if (real) { try { rst = fs.lstatSync(real); } catch { rst = null; } }
    if (real && rst && real !== m.dest
      && (real === homeRoot || real.startsWith(homeRoot + path.sep))) {
      masks.push({ ...m, dest: real, symlinkOf: m.dest });
      continue;
    }
    if (m.kind === 'empty') { masksSkipped.push(m.path); continue; }
    let anc = path.dirname(m.dest);
    let ancOk = false;
    while (anc !== homeRoot && anc !== path.parse(anc).root) {
      let ast = null;
      try { ast = fs.lstatSync(anc); } catch { ast = null; }
      if (ast && ast.isDirectory() && !ast.isSymbolicLink()) { ancOk = true; break; }
      anc = path.dirname(anc);
    }
    if (ancOk) masks.push({ ...m, dest: anc, redirectTo: anc });
    else masksSkipped.push(m.path);
  }
  const writableRoots = (Array.isArray(o.writableRoots) ? o.writableRoots : [])
    .filter((w) => typeof w === 'string' && w)
    .map((w) => path.resolve(w));
  // Adapter-declared read-only mounts (the host exec tree). Never a symlink
  // and never the filesystem root — the mount must exist inside the sandbox
  // without pulling the whole host in.
  const roBinds = [];
  for (const rb of (Array.isArray(o.roBinds) ? o.roBinds : [])) {
    if (typeof rb !== 'string' || !path.isAbsolute(rb)) continue;
    const abs = path.resolve(rb);
    let st = null;
    try { st = fs.lstatSync(abs); } catch { st = null; }
    if (st && !st.isSymbolicLink() && abs !== path.parse(abs).root) roBinds.push(abs);
  }
  // Resolve the DNS stub chain: when /etc/resolv.conf is a symlink into an
  // unmounted tree, bind its top-level directory so the link resolves.
  let resolvBind = null;
  try {
    const rr = fs.realpathSync('/etc/resolv.conf');
    if (rr !== '/etc/resolv.conf' && rr.startsWith('/run/')) {
      const seg = '/' + rr.split('/').slice(1, 3).join('/');
      let st = null;
      try { st = fs.lstatSync(seg); } catch { st = null; }
      if (st && st.isDirectory() && !st.isSymbolicLink()) resolvBind = seg;
    }
  } catch { /* resolv.conf unreadable: system mounts carry whatever exists */ }
  // Adapter-declared model-provider auth files: readable by design even
  // though their directory is masked; bound read-only after the mask mounts
  // so the mountpoint lands inside the fresh tmpfs.
  const authFiles = [];
  for (const af of (Array.isArray(o.authFiles) ? o.authFiles : [])) {
    if (typeof af !== 'string' || !path.isAbsolute(af)) continue;
    let real = null;
    try { real = fs.realpathSync(af); } catch { real = null; }
    let st = null;
    if (real) { try { st = fs.lstatSync(real); } catch { st = null; } }
    if (real && st && st.isFile()) authFiles.push({ src: real, dest: path.resolve(af) });
  }
  const { argv, seeds, seedsSkipped } = composeArgv({
    home: env.HOME || os.homedir(),
    workspace: o.workspace ? path.resolve(String(o.workspace)) : null,
    writableRoots,
    roBinds,
    resolvBind,
    authFiles,
    seedRoots: o.seedRoots && typeof o.seedRoots === 'object' ? o.seedRoots : {},
    masks,
  });
  const injected = injectPermissionConfig(readResolvedPermissionConfig(o), load.profile.deny);
  const envOut = {
    ...(o.envPassthrough && typeof o.envPassthrough === 'object' ? o.envPassthrough : {}),
    OPENCODE_CONFIG_CONTENT: JSON.stringify(injected.config),
  };
  const writableShadowed = writableRoots.filter((w) => masks.some((m) => isAncestorPath(m.dest, w)));
  return {
    ok: true,
    profile: name,
    tier: probe.tier,
    engine: probe.engine,
    engineVersion: probe.version || null,
    argv,
    env: envOut,
    deny: Array.isArray(injected.denyPatterns) ? injected.denyPatterns.slice() : [],
    meta: {
      masks,
      masksSkipped,
      roBinds,
      resolvBind,
      authFiles,
      seeds,
      seedsSkipped,
      writableShadowed,
      emptySrc: EMPTY_SRC,
      defaultProfile: DEFAULT_PROFILE,
      phases: ['ro-binds', 'writable-binds', 'mask-mounts', 'seed-ro-binds'],
    },
  };
}

module.exports = {
  DEFAULT_PROFILE,
  KNOWN_PROFILES,
  MANDATORY_MASK_TOKENS,
  EMPTY_SRC,
  DENY_BASELINE_SNAPSHOT,
  SEED_SNAPSHOT_NAMES,
  compose,
  maskOverBindHolds,
  probeEngine,
  resolveTokenPath,
  readResolvedPermissionConfig,
  readSnapshotEntry,
  unionDeny,
  injectPermissionConfig,
  seedSnapshots,
  recordDenyBaseline,
  scanSpawnOutput,
  makeStreamDenyScanner,
  sanitizeHostConfig,
  materializeSeedDir,
};
