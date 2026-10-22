// core/state.cjs — primitives layer: state/project schema validation + read/write + shared validators
// Require rule: sibling requires only (same directory).
'use strict';

const { execSync } = require('node:child_process');
const { execFileSync } = require('node:child_process');
const os = require('node:os');
const crypto = require('node:crypto');

const fs = require('node:fs');
const path = require('node:path');
const fsio = require('./fsio.cjs');
const gitprobe = require('./gitprobe.cjs');

const STATE_SCHEMA_VERSION = 4;

const PROJECT_SCHEMA_VERSION = 1;

const cpLen = (s) => [...String(s)].length;

const ID_RE = /^[DR]-\d{2,3}$/;

const DECISION_STATUS = new Set(['open', 'covered', 'superseded']);

const REQ_STATUS = new Set(['active', 'dropped']);

const PHASE_STATUS = new Set(['pending', 'active', 'done', 'parked']);

function badText(s) {
  if (typeof s !== 'string') return 'not a string';
  // eslint-disable-next-line no-control-regex
  if (/[\x00-\x1f\x7f]/.test(s)) return 'control characters';
  if (s.includes('$(') || s.includes('`')) return 'shell substitution ($(`/backtick)';
  if (s.includes('<!--') || s.includes('-->')) return 'html comment markers';
  if (/MANUAL:|GENERATED/.test(s)) return 'reserved marker substring (MANUAL:/GENERATED)';
  return null;
}

function badAnchor(a) {
  if (typeof a !== 'string' || a.length === 0) return 'missing';
  if (!/^[\w\p{L}\p{N}.\/#-]+$/u.test(a)) return 'illegal characters';
  if (path.isAbsolute(a)) return 'must be relative';
  const okPrefix = a.startsWith('spec.md') || a.startsWith('task/') || a.startsWith('.gos/archive/');
  if (!okPrefix) return 'must start with spec.md | task/ | .gos/archive/';
  if (a.split('/').includes('..')) return 'no .. segments';
  return null;
}

function validateDecision(d, where) {
  const errs = [];
  if (!d || typeof d !== 'object') return [`${where}: not an object`];
  if (!ID_RE.test(d.id || '')) errs.push(`${where}:id: bad format (want ^[DR]-\\d{2,3}$): '${d.id}'`);
  if (cpLen(d.title || '') === 0 || cpLen(d.title || '') > 120) errs.push(`${where}:title: 1-120 codepoints required`);
  if (d.rationale !== undefined && cpLen(d.rationale) > 200) errs.push(`${where}:rationale: >200 codepoints`);
  if (d.status !== undefined && !DECISION_STATUS.has(d.status)) errs.push(`${where}:status: '${d.status}' not in open|covered|superseded`);
  if (d.anchor !== undefined && d.anchor !== null && badAnchor(d.anchor)) errs.push(`${where}:anchor: ${badAnchor(d.anchor)}`);
  const bt = badText(d.title || '') || (d.rationale !== undefined && badText(d.rationale));
  if (bt) errs.push(`${where}:title/rationale: rejected (${bt})`);
  return errs;
}

function validateRequirement(r, where) {
  const errs = [];
  if (!r || typeof r !== 'object') return [`${where}: not an object`];
  if (!ID_RE.test(r.id || '')) errs.push(`${where}:id: bad format: '${r.id}'`);
  if (typeof r.text !== 'string' || r.text.length === 0) errs.push(`${where}:text: non-empty required`);
  const bt = badText(r.text || '');
  if (bt) errs.push(`${where}:text: rejected (${bt})`);
  if (r.status !== undefined && !REQ_STATUS.has(r.status)) errs.push(`${where}:status: '${r.status}' not in active|dropped`);
  return errs;
}

function validatePhase(p, where) {
  const errs = [];
  if (!p || typeof p !== 'object') return [`${where}: not an object`];
  if (typeof p.name !== 'string' || p.name.length === 0) errs.push(`${where}:name: non-empty required`);
  if (typeof p.goal !== 'string' || p.goal.length === 0) errs.push(`${where}:goal: non-empty required`);
  if (!PHASE_STATUS.has(p.status || '')) errs.push(`${where}:status: '${p.status}' not in pending|active|done|parked`);
  if (p.park_reason !== undefined && typeof p.park_reason !== 'string') errs.push(`${where}:park_reason: must be a string`);
  return errs;
}

// [D-12/D-18] repo identity is de-pathed: a raw remote URL is canonicalized to
// `host:port/path` and hashed — the URL itself is never persisted. Canonical
// rules: host lowercase (IPv6 bracketed, hex lowercase), default ports 22
// (ssh + scp-style) / 443 (https) / 9418 (git://), explicit ports kept,
// path case-preserved with one trailing `.git` and trailing slashes stripped,
// embedded credentials (user:pass@) stripped, scp-style `host:path` →
// `host:22/path` (scp syntax carries no port — git semantics: everything after
// the first colon is the path). Non-URL inputs (local paths, garbage) → null.
const REPO_URL_DEFAULT_PORTS = { ssh: 22, git: 9418, https: 443, http: 80 };

function canonicalRepoUrl(rawUrl) {
  if (typeof rawUrl !== 'string') return null;
  const input = rawUrl.trim();
  if (!input || /\s/.test(input)) return null;
  const schemeM = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/(.*)$/.exec(input);
  let host;
  let port;
  let pathPart;
  if (schemeM) {
    const scheme = schemeM[1].toLowerCase();
    let rest = schemeM[2].replace(/^[^/@]+@/, ''); // strip credentials (user[:pass]@)
    const slashAt = rest.indexOf('/');
    let authority = slashAt === -1 ? rest : rest.slice(0, slashAt);
    pathPart = slashAt === -1 ? '' : rest.slice(slashAt);
    let portText = null;
    if (authority.startsWith('[')) {
      // IPv6 literal: [hex:groups] with optional :port after the closing bracket
      const closeAt = authority.indexOf(']');
      if (closeAt === -1) return null;
      host = '[' + authority.slice(1, closeAt).toLowerCase() + ']';
      const tail = authority.slice(closeAt + 1);
      if (tail.startsWith(':')) portText = tail.slice(1);
      else if (tail !== '') return null;
    } else {
      const colonAt = authority.lastIndexOf(':');
      if (colonAt === -1) {
        host = authority;
      } else {
        host = authority.slice(0, colonAt);
        portText = authority.slice(colonAt + 1);
      }
      host = host.toLowerCase();
      if (host === '') return null;
    }
    if (portText === null || portText === '') {
      port = REPO_URL_DEFAULT_PORTS[scheme];
      if (port === undefined) return null; // scheme without a known default port and no explicit port
    } else {
      if (!/^\d+$/.test(portText)) return null;
      port = parseInt(portText, 10);
    }
  } else {
    // scp-style: [user@]host:path — port is always the ssh default, never parsed
    const scpM = /^(?:[^/@\s]+@)?([^:@/\s]+):(\S+)$/.exec(input);
    if (!scpM) return null;
    host = scpM[1].toLowerCase();
    // host must look like a hostname (dot or localhost) — kills drive letters like C:\x
    if (!host.includes('.') && host !== 'localhost') return null;
    if (!/^[a-z0-9.-]+$/.test(host)) return null;
    port = 22;
    pathPart = '/' + scpM[2];
  }
  let p = pathPart.replace(/\/+$/, '');
  if (p.endsWith('.git') && p.length > '/.git'.length) p = p.slice(0, -'.git'.length);
  p = p.replace(/\/+$/, '');
  return `${host}:${port}${p}`;
}

function deriveRepoId(rawUrl) {
  const canonical = canonicalRepoUrl(rawUrl);
  if (canonical == null) return null;
  return crypto.createHash('sha256').update(canonical).digest('hex').slice(0, 16);
}

// Read the repo's remotes (argv-only git calls — never a shell string) and
// derive one repo_id: origin wins when identifiable; otherwise all remotes
// must agree on a single id; no remotes / disagreement / unidentifiable URLs
// → advisory null (D-18).
function repoIdFromRemotes(rootDir) {
  const root = rootDir || currentRootRealpath() || process.cwd();
  let names;
  try {
    names = execFileSync('git', ['-C', root, 'remote'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).split(/\s+/).filter(Boolean);
  } catch { return null; }
  if (!names.length) return null;
  let originId = null;
  const ids = new Set();
  for (const n of names) {
    let url;
    try {
      url = execFileSync('git', ['-C', root, 'remote', 'get-url', n], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
    } catch { continue; }
    const id = deriveRepoId(url);
    if (id == null) continue;
    ids.add(id);
    if (n === 'origin') originId = id;
  }
  if (originId != null) return originId;
  if (ids.size === 1) return [...ids][0];
  return null;
}

function migrateState(s) {
  const wasLegacy = s.schema_version === undefined;
  const fromV = wasLegacy ? 0 : s.schema_version;
  s.schema_version = STATE_SCHEMA_VERSION;
  // [Phase W T9] v2→v3: pin spec_path/plan_path to task/<id>/ when absent (legacy
  // states predate path pinning). Root-level legacy spec.md/plan.md — if still on
  // disk — are migrated by the T5 batch, NOT here (no dual-read window, D-14).
  if (!s.spec_path) {
    try {
      const tid = currentTaskId(s);
      if (tid != null) {
        s.spec_path = fsio.resolvePath('spec', { task_id: tid });
        s.plan_path = fsio.resolvePath('plan', { task_id: tid });
      }
    } catch { /* leave null — context supplies lazily */ }
  }
  // [T94/D-12] v3→v4: identity de-pathed — drop the dead `version` field and the
  // machine-path `project_root` anchor (repo root is runtime-derived from here
  // on); stamp repo_id from the origin remote URL hash (advisory null without
  // remotes, D-18 — the raw URL is never persisted).
  if (fromV < 4) {
    delete s.version;
    delete s.project_root;
    if (s.repo_id == null) s.repo_id = repoIdFromRemotes();
  }
  if (wasLegacy) console.error('⚠ state migrated to schema v4 (task/<id>/ paths pinned; identity de-pathed — repo_id derived, version/project_root dropped)');
  if (!Array.isArray(s.decisions)) s.decisions = [];
  s.decisions = s.decisions.map((d) => {
    const m = { ...d };
    if (!m.status) m.status = m.covered === true ? 'covered' : 'open'; // derive from legacy covered
    if (m.birth_phase === undefined) m.birth_phase = 'legacy';
    if (m.covered === undefined) m.covered = m.status === 'covered';
    return m;
  });
  if (!Array.isArray(s.gaps)) s.gaps = [];
  s.gaps = s.gaps.map((g) => {
    const m = { ...g };
    if (m.id && /^G-\d+$/.test(m.id) && m.id.length > 6) m.id = `G-${String(m.id).slice(2, 8)}`; // G-<ts> → compact
    return m;
  });
  return s;
}

function validateState(s, mode) {
  const errs = [];
  if (!s || typeof s !== 'object') return ['state.json: not an object'];
  if (!Array.isArray(s.decisions)) errs.push('state.json:decisions: expected array');
  else s.decisions.forEach((d, i) => errs.push(...validateDecision(d, `state.json:decisions[${i}]`)));
  if (!Array.isArray(s.requirements)) errs.push('state.json:requirements: expected array');
  else s.requirements.forEach((r, i) => errs.push(...validateRequirement(r, `state.json:requirements[${i}]`)));
  // T2 [D-30]: verified truths must carry a valid three-element evidence object.
  // Fail-closed on the legacy string form; read-class (warn) keeps going with a banner.
  if (Array.isArray(s.observable_truths)) {
    s.observable_truths.forEach((t, i) => {
      if (t && t.verified === true && t.evidence !== undefined && t.evidence !== null) {
        const evErr = validateEvidenceObject(t.evidence, process.cwd());
        if (evErr) errs.push(`state.json:observable_truths[${i}]${t.id ? ` (${t.id})` : ''}: ${evErr}`);
      }
    });
  }
  if (s.schema_version !== undefined && s.schema_version > STATE_SCHEMA_VERSION) {
    const hint = `state.json:schema_version: ${s.schema_version} > known ${STATE_SCHEMA_VERSION} — upgrade GOS (npm i -g github:chenw521/GOS), or this state was written by a newer CLI`;
    if (mode === 'fail') { fsio.die(hint, 3); }
    console.error(`⚠ ${hint} (continuing read-only, project data not used)`);
    return ['__FUTURE__'];
  }
  if (errs.length && mode === 'fail') {
    console.error('✗ state.json failed schema validation:');
    errs.forEach((e) => console.error(`  ✗ ${e}`));
    console.error('Recovery: fix the field above (see the task spec — gos context think artifact_paths.spec), or restore from git backup, or gos init --force (discloses the task).');
    process.exit(1);
  }
  if (errs.length) {
    console.error(`⚠ state.json schema warnings (read-only mode): ${errs.length} issue(s) — first: ${errs[0]}`);
  }
  return errs;
}

function readState() {
  if (!fs.existsSync(fsio.STATE_PATH)) return null;
  let s;
  try {
    s = JSON.parse(fs.readFileSync(fsio.STATE_PATH, 'utf8'));
  } catch (e) {
    fsio.die(`state.json is corrupted: ${e.message}. Fix it or delete and gos init again.`);
  }
  const mode = (readState._mode === 'write') ? 'fail' : 'warn';
  if (s.schema_version === undefined || s.schema_version < STATE_SCHEMA_VERSION) {
    // legacy/v3 → migrate in-memory (both read and write paths migrate; only write persists)
    s = migrateState(s);
  }
  const errs = validateState(s, mode);
  if (errs.length && mode === 'warn' && errs[0] !== '__FUTURE__') {
    // read-class degradation: sanitize corrupt collections so consumers don't crash (banner already warned)
    if (!Array.isArray(s.decisions)) s.decisions = [];
    if (!Array.isArray(s.requirements)) s.requirements = [];
    if (!Array.isArray(s.gaps)) s.gaps = [];
    if (!Array.isArray(s.observable_truths)) s.observable_truths = [];
  }
  return s;
}

function writeState(stateL) {
  fs.mkdirSync(fsio.GOS_DIR, { recursive: true });
  if (stateL.schema_version === undefined || stateL.schema_version < STATE_SCHEMA_VERSION) stateL = migrateState(stateL);
  validateState(stateL, 'fail');
  // [T5/D-17] language boundary: recursive leaf walk — any CJK string leaf under
  // a git-tracked state.json dies at the write path (knowledge files travel
  // with clones). Cheap-first: the git probe fires only when a CJK leaf exists.
  const cjkLeaf = firstCJKLeaf(stateL);
  if (cjkLeaf !== null) dieTrackedStoreCJK(fsio.STATE_PATH, cjkLeaf.text);
  fsio.writeAtomicJson(fsio.STATE_PATH, stateL);
}

// Depth-first leaf walk over the state object; returns { path, text } of the
// first string leaf carrying CJK, null when clean. Pure detection — the
// tracked probe lives in dieTrackedStoreCJK.
function firstCJKLeaf(v, p = 'state') {
  if (v == null) return null;
  if (typeof v === 'string') return fsio.hasCJK(v) ? { path: p, text: v } : null;
  if (Array.isArray(v)) {
    for (let i = 0; i < v.length; i++) {
      const hit = firstCJKLeaf(v[i], `${p}[${i}]`);
      if (hit !== null) return hit;
    }
    return null;
  }
  if (typeof v === 'object') {
    for (const k of Object.keys(v)) {
      const hit = firstCJKLeaf(v[k], `${p}.${k}`);
      if (hit !== null) return hit;
    }
  }
  return null;
}

// [T5/D-17] shared write-path guard for the git-trackable GOS text stores
// (state.json / concerns.md / lessons.json — and gap text, which flows into
// concerns.md via stage-back write-back): tracked stores are English-only
// because knowledge files travel with clones. Fires only when the candidate
// text carries CJK AND gitprobe.isTracked(<store file>) — the T1 primitive is
// fail-closed (ANY git failure counts as tracked), so the boundary never falls
// open. Guidance is bilingual by design, rendered through t() from the locale
// dot-key 'langBoundary.trackedStore' (en.cjs + zh.cjs); the zh line is forced
// via a GOS_LANG flip on the die path (the process exits immediately, so the
// env mutation cannot leak). i18n is required lazily same-directory — the
// locale catalogs themselves must NOT be required from here: locales → state
// is a banned cross-directory cycle edge (T46 DAG).
function dieTrackedStoreCJK(file, text) {
  if (!fsio.hasCJK(text)) return false;
  if (!gitprobe.isTracked(file)) return false;
  const i18n = require('./i18n.cjs');
  const prevLang = process.env.GOS_LANG;
  const line = (locale) => {
    process.env.GOS_LANG = locale;
    i18n.effectiveLocale(true);
    return i18n.t('langBoundary.trackedStore', { file: path.basename(String(file)) });
  };
  const enLine = line('en');
  const zhLine = line('zh-CN');
  if (prevLang === undefined) delete process.env.GOS_LANG; else process.env.GOS_LANG = prevLang;
  fsio.die(`${enLine}\n  ${zhLine}`);
}

function emptyProject() {
  return { schema_version: PROJECT_SCHEMA_VERSION, last_archived_phase: null, phases: [], decisions: [], requirements: [] };
}

function validateProject(p, mode) {
  const errs = [];
  if (!p || typeof p !== 'object') return ['project.json: not an object'];
  if (p.schema_version > PROJECT_SCHEMA_VERSION) {
    const hint = `project.json:schema_version: ${p.schema_version} > known ${PROJECT_SCHEMA_VERSION} — upgrade GOS`;
    if (mode === 'fail') fsio.die(hint, 3);
    console.error(`⚠ ${hint} (read-only, project data not used)`);
    return ['__FUTURE__'];
  }
  if (!Array.isArray(p.phases)) errs.push('project.json:phases: expected array');
  else p.phases.forEach((ph, i) => errs.push(...validatePhase(ph, `project.json:phases[${i}]`)));
  if (!Array.isArray(p.decisions)) errs.push('project.json:decisions: expected array');
  else p.decisions.forEach((d, i) => errs.push(...validateDecision(d, `project.json:decisions[${i}]`)));
  if (!Array.isArray(p.requirements)) errs.push('project.json:requirements: expected array');
  else p.requirements.forEach((r, i) => errs.push(...validateRequirement(r, `project.json:requirements[${i}]`)));
  const names = new Set();
  if (Array.isArray(p.phases)) {
    for (const ph of p.phases) {
      if (ph && typeof ph.name === 'string') {
        if (names.has(ph.name)) errs.push(`project.json:phases: duplicate name (idempotency key) '${ph.name}'`);
        names.add(ph.name);
      }
    }
  }
  if (errs.length && mode === 'fail') {
    console.error('✗ project.json failed schema validation:');
    errs.forEach((e) => console.error(`  ✗ ${e}`));
    console.error('Recovery: fix the field above, or restore .gos/project/project.json from git.');
    process.exit(1);
  }
  if (errs.length) console.error(`⚠ project.json schema warnings: ${errs.length} issue(s) — first: ${errs[0]}`);
  return errs;
}

function loadProject() {
  const p = path.join(fsio.PROJECT_DIR, 'project.json');
  if (!fs.existsSync(p)) return null;
  let obj;
  try {
    obj = JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch (e) {
    fsio.die(`project.json is corrupted: ${e.message}. Fix it or restore from git.`);
  }
  const mode = (readState._mode === 'write') ? 'fail' : 'warn';
  const errs = validateProject(obj, mode);
  // REVIEW F-3 (D-01/F-8): read-class encountering a FUTURE schema version must REFUSE the data
  // (status/resume still work off state.json) — not just warn and consume it
  if (errs.includes('__FUTURE__')) return null;
  return obj;
}

function saveProject(p) {
  validateProject(p, 'fail');
  fs.mkdirSync(fsio.PROJECT_DIR, { recursive: true });
  fsio.writeAtomicJson(path.join(fsio.PROJECT_DIR, 'project.json'), p);
}

const CONTRACTS = {
  gate_verdicts: {
    allPass: '✓ ALL GATES PASSED',
    gateFailedPrefix: '✗ GATE FAILED',           // used as `✗ GATE FAILED (N):`
    passPrefix: '✓ ',                             // per-gate pass line prefix
    failPrefix: '✗ ',                             // per-gate fail line prefix
    // Phase W (T6, R-06): orphan advisory — FROZEN (spec Appendix A literal). <N> placeholder.
    // Advisory by default; `--strict` escalates to FAIL. Do NOT reword (tests assert it).
    orphanAdvisory: '[orphan-advisory] <N> unregistered entr(y|ies) under .gos/ (scan excludes archive/, active task/, renderers/, *tmp*/lock patterns). If BUILD is in progress, ignore this advisory. Do NOT delete manually — `gos commit ship` (or `gos commit verify` for non-project tasks) adopts them automatically.',
    orphanAdvisoryOne: '[orphan-advisory] 1 unregistered entry under .gos/ (scan excludes archive/, active task/, renderers/, *tmp*/lock patterns). If BUILD is in progress, ignore this advisory. Do NOT delete manually — `gos commit ship` (or `gos commit verify` for non-project tasks) adopts them automatically.',
    readmeDrift: '✗ README drift: .gos/README.md ≠ registry regen — hand edits forbidden; run `gos paths --markdown` to restore',
    // custom-gate hash-trust layer — frozen lines; <name> placeholder is runtime-substituted.
    // Do NOT reword (tests assert from `_contract`).
    trustUntrusted: 'custom gate <name>: not trusted (execution skipped) — review the script, then `gos gate trust <name>`',
    trustDrift: 'custom gate <name>: script changed since trust (execution skipped) — re-review the change, then re-trust: `gos gate trust <name>`',
    trustUnreadableScript: 'custom gate <name>: script unreadable or dangling symlink (execution skipped) — fix the file, then `gos gate trust <name>`',
    trustStoreUnreadable: 'trustStoreUnreadable: .gos/cache/trust.json is unreadable or corrupt — ALL custom gates treated as untrusted (never skip-and-green); fix or delete the file, then re-trust each script via `gos gate trust <name>`',
    trustConfigPolluted: 'config.json must not carry trusted_scripts/confirmed_sections — tracked hashes would re-arm script execution on every clone; move trust state to machine-local .gos/cache/trust.json, delete the keys, then re-register via `gos gate trust <name>`',
    trustCiAdvisory: 'custom gate <name>: untrusted — SKIPPED in CI/audit mode (exit code unaffected); review locally, then `gos gate trust <name>`',
    customGateEmpty: 'no custom gates — add .gos/gates/*.sh (exit 0 = pass, non-zero blocks the stage) or .gos/gates.json rules; seeded example: gos setup',
    trustRegistered: '✓ trusted custom gate: ',
    trustGc: '✓ trust GC: stale entries removed: ',
  },
  state_semantics: {
    noActiveTask: 'No active task.',              // status/no-arg when state.json missing
    initDone: '✓ Initialized',
    committed: '✓ Committed',
    stageAdvanced: '📍 Stage advanced',
    archived: '✓ Archived',
    archiveBlocked: '✗ ARCHIVE BLOCKED',
    commitBlocked: '✗ COMMIT BLOCKED',
    approvalGate: 'approval gate',
    cwdBanner: '📍 ',                              // stderr read-class banner prefix
    lockBlocked: '✗ concurrent GOS invocation detected',
    staleLock: '✗ stale GOS lock',
    // Phase B (T2) state-schema evolution fail-closed messages [D-30/D-31/B-15/B-21/B-22]:
    evidenceLegacy: 'legacy string evidence rejected (fail-closed) — re-record via `gos truth verify`',
    evidenceMissing: 'verified truth missing evidence object — record via `gos truth verify`',
    planDupTask: 'plan.md duplicate task id',
    snapshotStageBlock: 'plan_snapshot refresh requires current_stage=PLAN (BUILD+ re-commit plan is blocked)',
    snapshotMonotonic: 'plan_snapshot monotonicity violated (∪Files / per-task Covers may only grow)',
    snapshotFileSpace: 'plan.md Files entry contains whitespace',
    taskHeadReset: 'task_head_history reset by init --force — diff baseline restarts at current HEAD',
    // Phase C (T3, D-17): command-registry self-check — single die exit for all six
    // structural assertions (T29-9 stderr anchor; extracted from `gos _contract`).
    commandRegistrySelfCheck: 'command registry self-check failed:',
  },
  command_contracts: {
    decisionAdded: '✓ Decision D-',               // + NN + ' added: '
    decisionAmended: '✓ Decision D-',             // amend success prefix
    decisionCovered: 'covered by P',              // cover success
    reqAdded: '✓ Requirement R-',                 // + NN + ' added: '
    renderDone: '✓ rendered:',                    // render success
    contractJson: '_contract',                    // this command's name
    generatedHeader: '<!-- GENERATED by gos — edit via gos decision/requirement/phase commands, not this file -->',
    manualMarker: '<!-- MANUAL:notes -->',
    phaseAdded: '✓ Phase added: ',                // + phase name
    phaseClaimed: '✓ Phase claimed: ',            // + phase name
    // Phase W (T3, D-10): paths command output contracts (additive-only)
    readmeGenerated: '✓ README rendered:',
    readmeHeader: '<!-- GENERATED by gos paths --markdown',
    phaseUnclaimed: '✓ Phase ',                   // + name + ' unclaimed — ...'
    phaseAmended: '✓ Phase amended: ',            // + phase name (pending-goal whole replace)
    amendRefuseActive: 'refused — phase is active (claimed by in-flight state; unclaim first, then amend)',
    amendRefuseDone: 'refused — phase is done (closed history; goal rewrite would falsify the audit record)',
    amendRefuseParked: 'refused — phase is parked (un-park first: `gos phase park <n> --undo`, then amend)',
    anchorFixed: '✓ anchor re-fixed to ',         // + realpath
    archiveIdempotent: '✓ already archived',      // re-archive short-circuit
    renderSkip: '(no project.json — render skipped)', // archive in non-Lv4 repo
    // Phase V [D-05]: list-class rendering — state-only default, --all merged audit view
    listNoSources: 'no state and no project.json — nothing to list',
    listForeignProject: '(--all: project.json exists but this task is not project-bound — showing project view)',
    // Phase V [D-06]: claim gate prev-done+parked + target whitelist (R2-F9)
    claimGatedPrev: 'is pending — close it first (claim gated on predecessor)',
    claimDeferredHint: 'Deliberately deferring it? `gos phase park',
    claimCrossPhaseHint: 'Cross-phase requirements: `gos requirement list --all` / .gos/project/REQUIREMENTS.md',
    claimTargetDone: 'already done — next pending phase is index ',
    claimAllClosed: 'already done — all phases closed',
    claimTargetParked: 'is parked — deliberately deferred. To work on it: `gos phase park',
    doneHintParkedLine: 'parked phase: ',
    doneHintAllDone: 'All roadmap phases done.',
    // Phase V [D-06/T3]: park lifecycle + milestone debt visibility
    phaseParked: '✓ Phase parked: ',
    parkBlocksMilestone: 'parked blocks milestone completion — close out later via `gos phase park <n> --undo` or explicit `gos phase mark-done <n>`',
    parkUndo: '✓ Phase un-parked (back to pending): ',
    parkIdempotent: 'already parked — nothing to do',
    parkUndoIdempotent: 'already pending — nothing to un-park',
    parkRefuseActive: 'refused — phase is active (claimed by in-flight state)',
    parkRefuseDone: 'refused — phase is done (closed phases cannot be parked)',
    parkOrphanWarn: '⚠ state.json still points at this phase mid-flight — orphaned task; `gos init --force` to replace, or `--undo` then re-claim later',
    markDoneCloseOut: 'parked → done (close-out)',
    milestoneBlockedHeader: '⚠ MILESTONE BLOCKED — parked item(s) prevent milestone completion:',
    // Phase V [D-07/T4]: ghost-family self-documentation + archived-entity guards
    ghostFixTeaching: 'Fix: align plan Covers with the state ID set (`gos requirement list` / `gos decision list`); cross-phase needs: `--all` / .gos/project/REQUIREMENTS.md; or `gos stage back plan` to re-plan',
    dupArchivedTeaching: 'belongs to an archived phase (not in current state) — use the next auto-assigned ID, or inspect via `gos decision list --all`',
    archivedRefusedTeaching: 'belongs to an archived phase — cross-phase corrections go through the supersede flow (`gos decision add <new> --supersedes <id>`), not amend/cover',
    // feedback family — user-facing frozen lines (tests assert from `_contract`)
    feedbackAdded: '✓ Feedback FB-',                     // + N + ' added (…)' / ' closed …'
    feedbackClosed: ' closed — resolution recorded: ',   // close success suffix
    feedbackOwnerRefuse: '✗ refusing push: repo owner',  // owner-mismatch guard head
    feedbackPublished: '✓ published: ',                  // push success URL prefix
    feedbackGhMissing: "'gh' executable not found on PATH",
    // brownfield adoption — frozen closed sets (D-88/D-99; tests assert from `_contract`):
    // per-asset outcome taxonomy, dormant-hook state flags, the exit-code table,
    // and the preflight refusal reason vocabulary (placeholders absent — literal sets).
    brownfieldStatusSet: 'created | kept_identical | kept_conflict | locked_user_owned | report_only',
    brownfieldStateFlags: 'inactive | untrusted',
    brownfieldExitCodes: '0 success; 1 generic fatal (incl. corrupt hooks state file); 2 locked-overwrite refused; 3 unknown asset name; 4 non-git or cwd≠toplevel; 5 self-repo',
    brownfieldPreflightReasons: 'path occupied by non-directory | dangling symlink | unwritable ancestor | symlink escape',
  },
  // semantic_checks — Phase B (defect-1 semantic gates) check registry [D-33]:
  // texts frozen from spec §2; skills/tests assert from here (gos _contract).
  // B-3 [R1-F11+R3-F9]: gate subcommand emitting ✓ for a table check ends with `banner`.
  semantic_checks: {
    banner: 'gate checks syntax+consistency only, not semantic quality',
    evidenceShape: '{command, output_excerpt, artifact_path}',
    excerptFeature: 'exit-code|count|path (manual); count|path|KV (replay; synthetic exit/status keys vetoed)',
    bidirectional: 'state.decisions ↔ plan Covers exact equality (R-NN one-way)',
    diffHit: 'task∩diff nonempty AND diff⊆∪Files(allowlist)',
    pathExists: 'artifact_path exists on disk at gate time',
    allowlist: ['.changes.md', 'CHANGELOG.md', 'commitlint.config.yaml', '*.lock', '.gos/**(excl gates.json+gates/)', 'truth artifact_path'],
    lessonsAnchor: 'sidecar hash intact + audit chain valid (B-8/B-9/B-14)',  // [R2-8]
    diffInvocations: 'git -c core.quotepath=off diff --name-only --no-renames -z + git ls-files --others --exclude-standard -z (untracked in, CJK safe, NUL parsed)',  // [R2-5]
    bootstrapBanner: 'lessons sidecar bootstrapped this run (anchor created from current file)',   // [R3-F8]
    skipBanner: 'semantic check skipped (sandbox-bound)',   // [R3-F8]
    manualWarning: 'N manual truths (evidence not replayed)',   // [R3-F8]
    globalWriteHint: 'model-type lesson written globally (visible to all repos)',   // [R3-F8]
    specSha: 'state.spec_sha256 frozen at THINK commit; REVIEW/VERIFY verify consistency',   // [R3-F5]
    lazyFreeze: 'spec/plan freeze fields backfilled via lazy-freeze (pre-existing task, snapshot taken now)',   // [F1] T2 lazy-freeze banner
    // Phase 6 (defect-6 dependency map) frozen texts [D-38/D-39; spec §2, 17 keys]:
    // placeholders (<file>/<paths>/<N>/<top-impact-file>/<subdir>/<root>) are runtime-substituted;
    // tests assert the PLACEHOLDER form against `gos _contract` output, concrete forms in E2E.
    mapBanner: 'regex-based self-scan, no dynamic resolution — results may be incomplete',
    acornMissing: 'acorn not installed — fn-level edges unavailable (npm i in package root); other commands unaffected',
    parseFailures: 'parse failed <N> file(s) — fn edges missing for: <files>',
    fnSetUnavailable: 'fn set unavailable (parse failures) — <M> gos-map:fn annotation(s) not validated',
    closureParseWarn: '⚠ parse_failures=<N> — closure may be incomplete',
    fnNotInGraph: 'fn not in callgraph node set (<anchor>) — isolated or out-of-graph fn; closure may be vacuous (advisory)',
    staleNote: 'stale deps.json (head or worktree anchor mismatch) — cached results used (--no-refresh)',
    probeHint: 'dedicated dep tool config detected (<file>) — prefer it for precision (not guaranteed)',
    depsTamper: 'deps.json integrity check failed (self-anchor mismatch) — refusing cached map, rescan required',
    depsParseFail: 'deps.json unreadable (parse failed) — refusing cached map',
    depsSchemaFuture: 'deps.json schema_version not supported by this CLI — refusing cached map',
    depsSchemaStale: 'deps.json schema v2 cache — fn-level data missing — run: gos map scan',
    noHead: 'not a git repo — deps.json unanchored (freshness unverifiable, auto-rescan on query)',
    headUnborn: 'git repo with no commits — deps.json anchored to empty tree',
    closureUnknownPath: 'closure input not in graph (<paths>) — typo, deleted, or not in scan set — refusing vacuous answer',
    impactClosure: 'impact closure: <N> diff dependents not covered by task Files (advisory, regex-based, may be incomplete)',
    impactClean: 'impact closure: 0 uncovered dependents (regex-based, may be incomplete)',
    impactVacuous: 'impact closure vacuous (0 scannable sources OR diff fully allowlisted) — NOT evidence of clean',
    impactHintRun: 'run: gos map closure <top-impact-file> --print0',
    print0Rule: '--print0 output: NUL-separated paths only, no banners — sole legal machine consumption mode',
    mapCwdBanner: 'run from <subdir> — anchored to repo root <root>',   // [R3-F9] distinct from state_semantics.cwdBanner (📍 pin)
    anchorVerifOk: 'anchor verified (<type>: <detail>)',
    anchorVerifDeadPath: 'dead anchor: path not in universe (<path>) — fix the edge or run: gos map edge rewrite --from <old> --to <new>',
    anchorVerifDeadAnchor: 'dead anchor: <kind> validation failed (<anchor>) — fix the edge or run: gos map edge rewrite --from <old> --to <new>',
    anchorVerifLineBan: 'line-number anchors are banned in edges.json (view-only — regenerated by every scan; use fn:/sec:/cmd:/h:/contract-key anchors)',
    anchorVerifHashInPath: "path segment contains '#' (ambiguous with anchor separator) — rename the file, anchors cannot reference it",
    anchorVerifAbsPath: 'absolute/home paths are banned in edges.json (cross-machine dead-edge hazard) — use repo-relative paths',
    edgesReadFail: 'edges.json unreadable (<err>) — refusing to proceed, never silently treated as empty (restore from git or fix permissions)',
    edgesParseFail: 'edges.json unreadable (parse failed) — fix it, or reseed with: gos map edge adopt --bootstrap',
    edgesSchemaFuture: 'edges.json schema_version not supported by this CLI — refusing',
    edgeDup: 'edge already exists (from/to/type) — refusing duplicate; run: gos map edge rm <from> <to> first if intentional',
    edgeBadType: 'unknown edge type (<type>) — allowed: consumes|asserts|greps|contract-ref|owns|test-of',
    edgeAuditMissing: 'no audit log yet (.gos/logs/edge-audit.log) — nothing recorded',
    edgeAdoptExists: 'edges.json already exists — bootstrap is only for repos without one; to review+reset integrity run: gos map edge adopt',
    edgeAdoptNoLock: 'integrity freeze (.gos/cache/edges.lock) does not exist yet in this repo — plain adopt is only meaningful once the freeze is created by gos commit; to seed an empty edges.json run: gos map edge adopt --bootstrap',
    edgesLockMismatch: 'edges.json ≠ frozen sha256 in .gos/cache/edges.lock — hand edit detected. Review the change, then run: gos map edge adopt, or revert: delete .gos/cache/edges.json',
    edgesTrackedMissing: '<file> is git-tracked but missing on disk — restore it: git checkout -- <file> (never proceed with an integrity anchor deleted)',
    edgesNotFrozen: 'edges.json present but integrity freeze (.gos/cache/edges.lock) not created yet — the next gos commit freezes it (no lazy freeze: never auto-adopt)',
    edgesBootstrapHint: 'map 2.0 not bootstrapped here (no edges.json, not tracked) — optional: gos map edge adopt --bootstrap',
    edgesVerifyOk: 'edges integrity verified (disk sha256 == frozen lock)',
    unannotatedCount: '<N> test section(s) unannotated — must-run section list may be incomplete; annotate section headers with: # gos-map:cmd <cmd>[,<cmd2>] (or # gos-map:none)',
    semClosureHead: 'must-check set (regex-extracted from known edges — NOT exhaustive, only known-edge hits):',
    semClosureMustRun: 'must-run test sections (regex-extracted, NOT exhaustive):',
    semClosureEmpty: 'semantic closure: no known semantic dependents for the current diff (regex-based, may be incomplete — absence is NOT evidence of safety)',
    semClosureUnannotated: '<N> test section(s) unannotated — must-run section list may be incomplete',
    networkMarkerMissing: 'network.md has no MANUAL region marker — refusing to refresh (hand-written content would be destroyed). Restore the marker line or rebuild the file from git: git checkout -- .gos/codebase/network.md',
    manifestNone: 'no .gos/run-manifest.json — sections have not been run since the last change; must-run verification is OFF until a full/partial run writes a manifest',
    manifestStale: 'run-manifest stale — sections were last run against a DIFFERENT content tree. Re-run: bash test/run-sections.sh (then gos gate all)',
    manifestDocOnly: 'run-manifest stale (doc-only diff) — dirty files all semantic-allowlisted and tested tree is a HEAD ancestor; treated as fresh, no re-run needed [U2]',
    manifestMissingSecs: '<secs> in must-run list but absent from run-manifest — run them: bash test/run-sections.sh <sec>',
    exemptCleared: 'exemptions consumed and cleared (auto-expiry — one commit per exemption)',
    concernsBootstrap: 'concerns sidecar bootstrapped this run (anchor created from current file)',
    concernsAnchorFail: 'concerns anchor mismatch — restore .gos/concerns.md from git history or .bak',
    // Phase C (T4, D-15/R1-F5/R3-F4): help envelope + machine-consumption discipline.
    jsonHelpEnvelope: 'envelope {gos_version, schema_version, class_legend, commands} — strict JSON from byte 0 (no banners)',
    jsonMachineMode: '--json is the sole legal machine consumption mode; consumer MUST JSON.parse-verify AND reject schema_version > known — pre-Phase-C gos prints human text with exit 0 on `help --json`',
    // Section-runner freshness enrichment (product `gos section run`):
    // a run that executed NO sections is not freshness evidence; a filtered
    // run stays auditable; an empty must-run closure says so explicitly.
    manifestEmptyRun: 'run-manifest sections_run is empty — a run that executed no sections is not freshness evidence; re-run the sections (full, or with a matching filter)',
    manifestPartialRun: 'manifest is a partial run (filter=<filter>) — sections outside the filter were not exercised in this run (visible for audit; closure responsibility stays on must-run sections)',
    manifestEmptyClosure: 'empty-closure freshness: no must-run sections for this diff — freshness rests on tree equality alone',
  },
  // section_runner — frozen user-facing lines for `gos section run`/`trust`
  // (wave-3 gate_verdicts pattern; runtime substitutes <rc>/<n>/<N>/<filter>).
  // Wording rule: the threat model is FIXTURE ISOLATION — never describe this
  // command as a security boundary of any kind.
  section_runner: {
    threatModel: 'fixture isolation, not a security boundary: sections execute with the user\'s full permissions; the runner pins HOME/XDG/TMPDIR and cwd to a throwaway fixture base and prevents green-without-running — malicious scripts and absolute-path writes are out of scope',
    noSections: 'no test/sections/T*.test.sh in this project — nothing to run (exit 0, no manifest written; must-run verification stays off until a run manifest exists)',
    confirmHeader: 'First run in this project — the following section scripts will execute with your FULL permissions (fixture isolation, not a security boundary):',
    confirmPrompt: 'Proceed? [y/N] ',
    confirmDeclined: 'section list not confirmed — nothing was executed',
    confirmStored: '✓ section list confirmed — hash recorded in machine-local .gos/cache/trust.json',
    headlessUnconfirmed: 'sections are not confirmed on this machine and no interactive terminal is available — nothing executed. Recovery: run `gos section run` once interactively and answer the confirmation, or pre-register the current list: gos section trust',
    ciSkip: 'sections unconfirmed in CI mode (GOS_CI=1) — execution SKIPPED, exit 0. Bootstrap once per machine: gos section trust (after that, CI runs execute normally)',
    bashMissing: 'bash is required for section scripts but was not found on PATH — install bash, then re-run',
    aborted: 'SECTION ABORTED (exit <rc>) — assertions after the failure point may not have run',
    timeout: 'SECTION TIMEOUT after <n>s — killed and counted as a failure',
    markerMissing: 'fixture base marker missing after section — the section deleted or corrupted its own base',
    sweepLine: 'leak sweep: removed <N> stale fixture base(s) from .gos/cache (marker verified + owner pid dead; no-marker directories are never deleted)',
    trustRegistered: '✓ section list confirmed: <N> script(s)',
    trustEmpty: 'no test/sections/T*.test.sh in this project — nothing to confirm (an empty list is never recorded)',
  },
  decorative: {
    instructionsThinkDnn: 'record via gos decision add',  // THINK instruction wording
    // single-point-commit iron rule — frozen phrase; skills (gos-build) and
    // tests assert from this table.
    waveSinglePointCommit: 'during parallel waves executors never run gos commit — the main session commits once per wave after aggregation',
    // Phase U (D-33/T4): in-flow discovery pointer — frozen exact string, asserted by T35-u-status
    fullCapabilityPointer: 'Full capability: gos help [--json]',
  },
};

function currentTaskId(stateL) {
  if (stateL) {
    const pn = String(stateL.phase_name || '');
    if (pn.includes(':')) {
      const code = pn.split(':')[0].trim().toLowerCase();
      // [REVIEW P2-F1] whitelist: phase code is user/LLM-controlled — reject traversal,
      // slashes and odd chars (fall through to task_head channel instead)
      if (code && /^[a-z0-9][a-z0-9_-]{0,63}$/.test(code)) return code;
    }
    const th = String(stateL.task_head || '');
    if (/^[0-9a-f]{8,40}$/i.test(th)) return th.slice(0, 8);
  }
  return null;
}

function ensureTaskDir(stateL) {
  let tid = currentTaskId(stateL);
  if (tid == null) {
    tid = 'ts-' + Date.now();
    console.error(`⚠ GOS_PATHS: no phase code / usable task_head — task dir falls back to ${tid}`);
  }
  const dir = path.join(fsio.GOS_DIR, 'task', tid);
  const marker = path.join(dir, '.task-head');
  const mine = (stateL && typeof stateL.task_head === 'string' && /^[0-9a-f]{8,40}$/i.test(stateL.task_head)) ? stateL.task_head : null;
  const writeMarker = () => {
    if (!mine) return;
    try { fs.writeFileSync(marker, JSON.stringify({ task_head: mine }) + '\n'); }
    catch (e) { fsio.die(`✗ cannot write task ownership marker ${marker}: ${e.message}`); }
  };
  if (fs.existsSync(dir)) {
    let owner = null;
    try { owner = JSON.parse(fs.readFileSync(marker, 'utf8')).task_head || null; } catch { owner = null; }
    if (owner && mine && owner !== mine) {
      fsio.die(`✗ GOS_PATHS: task id conflict — task/${tid}/ already belongs to task_head ${owner.slice(0, 8)}, current task ${mine.slice(0, 8)}; archive first (gos commit ship) or fix the id`);
    }
    if (!owner) writeMarker();
  } else {
    try { fs.mkdirSync(dir, { recursive: true }); } catch (e) { fsio.die(`✗ cannot mkdir task dir ${dir}: ${e.message}`); }
    writeMarker();
  }
  return { tid, dir };
}

function specPathOf(stateL) {
  if (stateL && stateL.spec_path) return stateL.spec_path;
  const tid = currentTaskId(stateL);
  if (tid == null) return fsio.resolvePath('spec', { task_id: 'ts-0' }); // unreachable for valid states (init always anchors one)
  return fsio.resolvePath('spec', { task_id: tid });
}

function planPathOf(stateL) {
  if (stateL && stateL.plan_path) return stateL.plan_path;
  const tid = currentTaskId(stateL);
  if (tid == null) return fsio.resolvePath('plan', { task_id: 'ts-0' });
  return fsio.resolvePath('plan', { task_id: tid });
}

function checkInputConstraint({ value, maxCp, label = 'input', noNewlineListPrefix = false }) {
  if (value == null) return { ok: false, reason: `${label}: value required` };
  const trimmed = String(value).replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, ''); // leading/trailing whitespace trim
  if (!trimmed) return { ok: false, reason: `${label}: empty after trim` };
  const cps = [...trimmed].length; // codepoint length, not utf16 units
  if (maxCp != null && cps > maxCp) return { ok: false, reason: `${label}: ${cps} codepoints exceeds cap ${maxCp}` };
  // badText: control characters (C0/C1 except \t\n\r — those are governed by the single-line rule)
  if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]/.test(trimmed)) {
    return { ok: false, reason: `${label}: control character rejected (badText)` };
  }
  if (noNewlineListPrefix) {
    if (trimmed.includes('\n- [')) return { ok: false, reason: `${label}: "\\n- [" list-entry injection rejected (single-line required)` };
    if (/[\n\r]/.test(trimmed)) return { ok: false, reason: `${label}: newline rejected (single-line required)` };
  }
  return { ok: true, value: trimmed };
}

// D-04 [R-26]: evidence features split per mode. MANUAL keeps the original
// three (exit-code allowed — the manual excerpt bar is unchanged); REPLAY
// widens the count/KV families and is subject to the synthetic-key veto in
// replayEvidenceHit below.
const EVIDENCE_FEATURE_RES_MANUAL = [
  /exit( code)?[ :=]+\d/i,                                         // ① exit code
  /\d+\s+(passed|failed|tests?|assertions?|files?|gates?|条|个)/i,  // ② numeric stats
  /[\/\w@.-]+\.(cjs|js|ts|py|R|sh|md|json)(:\d+)?/,                // ③ file path
];

// Replay-only families, weakest evidence last: ② digit-then-word, ② digit-
// after-word (enumerated forms like `total 165` — generic by design, the veto
// kills the synthetic-key subset), ③ file path, ④ KV `KEY=VALUE`/`KEY: VALUE`.
const EVIDENCE_FEATURE_RES_REPLAY = [
  /\d+\s+(passed|failed|tests?|assertions?|files?|gates?|条|个)/i,  // ②a digit-then-word
  /\b[A-Za-z][A-Za-z_]*\s+\d+/,                                     // ②b digit-after-word
  /[\/\w@.-]+\.(cjs|js|ts|py|R|sh|md|json)(:\d+)?/,                // ③ file path
  /^([A-Za-z_][\w .-]*?)\s*[=:]\s*\S+/,                             // ④ KV family
];

// Tiered replay hit selection (count > path > KV, document order within a
// tier). R1 hardening: (a) synthetic-key veto is LHS-normalized (lowercase +
// strip [_\s-]) against {exit, exitcode, rc, returncode, code, status, ret},
// killing `Exit=0`, `EXIT_CODE=0`, `rc:0`, `status 0` variants in any tier;
// (b) on any `=` line a path hit on the RHS is demoted (never tier ③) and the
// KV tier skips env-noise LHS {path, home, pwd, shell, lang, ls_colors,
// npm_config_*} — `PATH=/usr/.../x.js` can never win the excerpt; (c) ANSI
// CSI sequences are stripped before classification. Widened families raise
// convenience, not authenticity (echo-forgeable; artifact-on-disk is the
// non-forgeable leg) — spec D-04 honest note.
function replayEvidenceHit(stdoutText) {
  const normLhs = (s) => s.toLowerCase().replace(/[_\s-]/g, '');
  const VETO = new Set(['exit', 'exitcode', 'rc', 'returncode', 'returned', 'code', 'status', 'ret']);
  const ENV_NOISE = new Set(['path', 'home', 'pwd', 'shell', 'lang', 'lscolors', 'nodepath', 'pythonpath', 'gemhome']);
  const vetoShape = /^([A-Za-z][\w\s-]*?)\s*(?:[=:]|\s)\s*\d+/;
  const kvShape = EVIDENCE_FEATURE_RES_REPLAY[3];
  const lines = String(stdoutText == null ? '' : stdoutText)
    .replace(/\x1b\[[0-9;?]*[A-Za-z]/g, '') // ANSI CSI strip
    .split(/\r?\n/)
    .map((l) => l.trim());
  const tiers = { count: null, path: null, kv: null };
  for (const l of lines) {
    if (!l || cpLen(l) > 200) continue;
    const vm = vetoShape.exec(l);
    if (vm && VETO.has(normLhs(vm[1]))) continue; // vetoed synthetic key: no tier at all
    const eqAt = l.indexOf('=');
    const pathScope = eqAt >= 0 ? l.slice(0, eqAt) : l; // `=`-RHS path demoted from ③
    const km = kvShape.exec(l);
    const kvLhs = km ? normLhs(km[1]) : null;
    if (!tiers.count && (EVIDENCE_FEATURE_RES_REPLAY[0].test(l) || EVIDENCE_FEATURE_RES_REPLAY[1].test(l))) tiers.count = l;
    if (!tiers.path && EVIDENCE_FEATURE_RES_REPLAY[2].test(pathScope)) tiers.path = l;
    if (!tiers.kv && km && !VETO.has(kvLhs) && !ENV_NOISE.has(kvLhs) && !kvLhs.startsWith('npmconfig')) tiers.kv = l;
  }
  return tiers.count || tiers.path || tiers.kv || null;
}

function validateEvidenceObject(ev, repoRoot) {
  if (ev === undefined || ev === null) return CONTRACTS.state_semantics.evidenceMissing;
  if (typeof ev === 'string') return CONTRACTS.state_semantics.evidenceLegacy;
  if (typeof ev !== 'object' || Array.isArray(ev)) {
    return `evidence: object required, shape ${CONTRACTS.semantic_checks.evidenceShape}`;
  }
  const errs = [];
  const cmd = ev.command;
  if (typeof cmd !== 'string' || cpLen(cmd) === 0) errs.push('evidence.command: non-empty string required');
  else {
    if (cpLen(cmd) > 200) errs.push(`evidence.command: ${cpLen(cmd)} codepoints exceeds cap 200`);
    const bt = badText(cmd);
    if (bt) errs.push(`evidence.command: rejected (${bt})`);
  }
  const exc = ev.output_excerpt;
  if (typeof exc !== 'string' || cpLen(exc) === 0) {
    errs.push(`evidence.output_excerpt: non-empty string required (feature match needed: ${CONTRACTS.semantic_checks.excerptFeature})`);
  } else {
    if (cpLen(exc) > 200) errs.push(`evidence.output_excerpt: ${cpLen(exc)} codepoints exceeds cap 200`);
    const featureOk = ev.replay === true
      ? replayEvidenceHit(exc) !== null
      : EVIDENCE_FEATURE_RES_MANUAL.some((re) => re.test(exc));
    if (!featureOk) {
      errs.push(`evidence.output_excerpt: no feature match (${CONTRACTS.semantic_checks.excerptFeature})`);
    }
    const bt2 = badText(exc);
    if (bt2) errs.push(`evidence.output_excerpt: rejected (${bt2})`);
  }
  const ap = ev.artifact_path;
  if (typeof ap !== 'string' || ap.length === 0) errs.push('evidence.artifact_path: non-empty string required');
  else {
    if (path.isAbsolute(ap)) errs.push('evidence.artifact_path: must be relative to repo root');
    if (ap.split('/').includes('..')) errs.push('evidence.artifact_path: no .. segments');
    if (/[\n\r]/.test(ap)) errs.push('evidence.artifact_path: newline rejected');
    // Machine-local zones (gitignored by design — D-01/D-08 logs/cache, census
    // audit for archive): evidence artifacts there are guaranteed on the
    // AUTHORING machine at verify time (receipt-logged) but never travel with
    // git — a fresh clone must not fail schema validation for their absence.
    // NOTE: the registry archive key says tracked:true while gitignore+census
    // say local — that divergence is DI-6 territory, so the zone list is
    // explicit here instead of derived.
    const ARTIFACT_LOCAL_ZONES = ['.gos/archive/', '.gos/logs/', '.gos/cache/'];
    if (repoRoot && !fs.existsSync(path.resolve(repoRoot, ap)) && !ARTIFACT_LOCAL_ZONES.some((z) => ap.startsWith(z))) {
      errs.push(`evidence.artifact_path: not found on disk (${CONTRACTS.semantic_checks.pathExists})`);
    }
  }
  return errs.length ? errs.join('; ') : null;
}

const idNum = (prefix, id) => parseInt((new RegExp(`^${prefix}-(\\d+)`).exec(String(id)) || [0, 0])[1], 10) || 0;

function extractRequirement(intentText, level) {
  // R-01 = the intent sentence itself. Implicit at Lv0-3, explicit in state.
  const text = (intentText || '').trim() || '(task)';
  return [{ id: 'R-01', text: text.length > 120 ? text.slice(0, 117) + '...' : text, phase: null, level }];
}

function defaultState(level, intentText) {
  return {
    schema_version: STATE_SCHEMA_VERSION,
    repo_id: repoIdFromRemotes(), // D-12/D-18: origin-URL hash identity; advisory null without remotes
    level: level ?? null,
    current_stage: 'INTENT',
    completed_stages: [],
    intent: { summary: intentText || '', confirmed: false },
    approvals: {},  // stage-gate approvals: {THINK:'...', PLAN:'...', ARCHIVE:'...'} — set ONLY via gos approve <stage> (explicit user act)
    spec_path: null,   // T5: backfilled below via ensureTaskDir resolution
    plan_path: null,
    project: false,          // true when init --project (Lv4 truth-source mode)
    requirements: extractRequirement(intentText, level),
    decisions: [],
    observable_truths: [],
    gaps: [],
  };
}

const STAGE_ORDER = ['INTENT', 'THINK', 'PLAN', 'BUILD', 'REVIEW', 'VERIFY', 'SHIP', 'DONE'];

function lessonsPaths(type) {
  // P15 D-64: truth = lessons.json (tracked); md = regenerated view; anchor =
  // derived {live_ids} cache; backup = one-time migration backup (latest generation).
  const ymd = new Date().toISOString().slice(0, 10);
  if (type === 'model') {
    const dir = path.join(os.homedir(), '.config', 'gos');
    return {
      file: path.join(dir, 'lessons.md'),
      truth: path.join(dir, 'lessons.json'),
      truthBak: path.join(dir, '.lessons.json.bak'),
      anchor: path.join(dir, '.lessons-anchors.json'),
      backup: path.join(dir, `lessons-migration-backup-${ymd}.md`),
      lock: path.join(dir, '.anchors.lock'),
      global: true,
    };
  }
  return {
    file: fsio.resolvePath('lessons'),
    truth: fsio.resolvePath('lessons_json'),
    truthBak: null,
    anchor: fsio.resolvePath('lessons_anchors'),
    backup: fsio.resolvePath('lessons_backup', { ymd }),
    lock: null,
    global: false,
  };
}

function currentRootRealpath() {
  try {
    const out = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    return fs.realpathSync(out);
  } catch { return null; }
}

function tryCmd(cmd) {
  try {
    const out = execSync(cmd, { shell: '/bin/bash', stdio: ['pipe', 'pipe', 'pipe'] }).toString();
    return { ok: true, code: 0, out };
  } catch (e) {
    return { ok: false, code: e.status ?? 1, out: (e.stdout || '') + '\n' + (e.stderr || '') };
  }
}

const NO_CMD_KEY = '(no command)';
const COMMANDS = {
  'next': {
    desc: 'guided: what to do right now', class: 'read', aliases: [], core: false,
    subs: [], flags: [], usage: 'gos next',
    next: ['gos', 'gos instructions <stage>'],
    contractKeys: [],
  },
  'instructions': {
    desc: 'stage-by-step guidance for the current task', class: 'read', aliases: [], core: true,
    subs: ['<stage>'], flags: [], usage: 'gos instructions <stage>',
    next: ['gos context <stage>', 'gos commit <stage>'],
    contractKeys: [],
  },
  'status': {
    desc: 'full status (decisions/truths/requirements/gaps)', class: 'read', aliases: [], core: false,
    subs: [], flags: [], usage: 'gos status',
    next: ['gos', 'gos gap list'],
    contractKeys: [],
  },
  '(no command)': {
    desc: 'status alias (no-arg call)', class: 'read', aliasOf: 'status', aliases: [''], core: true,
  },
  'init': {
    desc: 'init task: gos init <level> "<intent>" | --project (Lv4 four-file set)', class: 'write', aliases: [], core: true,
    subs: ['<level> "<intent>"', '--project'], flags: [
      { name: '--force', scope: 'init', effect: 'discard existing task state and re-init', risk: 'destructive' },
    ],
    usage: 'gos init <level> "<intent>" [--project] [--force]',
    next: ['gos', 'gos context think'],
    contractKeys: [],
  },
  'resume': {
    desc: 'print resume summary (paste into a fresh AI session)', class: 'read', aliases: [], core: true,
    subs: [], flags: [], usage: 'gos resume',
    next: ['gos', 'gos instructions <stage>'],
    contractKeys: [],
  },
  'stage': {
    desc: 'stage flow position: show / back <stage> [reason]', class: 'write', aliases: [], core: false,
    subs: ['show', 'back <stage> [reason]'], flags: [],
    usage: 'gos stage <sub>',
    next: ['gos stage show', 'gos instructions <stage>'],
    contractKeys: [],
  },
  'context': {
    desc: 'pre-computed context JSON (read_files, decisions, truths, gates)', class: 'read', aliases: [], core: true,
    subs: ['<stage>'], flags: [], usage: 'gos context <stage>',
    next: ['gos instructions <stage>'],
    contractKeys: [],
  },
  'checkpoint': {
    desc: 'wave/area-level recovery point', class: 'write', aliases: [], core: false,
    subs: ['save --stage <s> --unit <u> --done <n> --remaining <n>'], flags: [],
    usage: 'gos checkpoint save [--stage <s>] [--unit <u>] [--done <n>] [--remaining <n>]',
    next: ['gos', 'gos trace requirements'],
    contractKeys: [],
  },
  'commit': {
    desc: 'atomic commit of stage artifacts + advance stage', class: 'write', aliases: [], core: true,
    subs: ['<stage>'], flags: [],
    usage: 'gos commit <stage>',
    next: ['gos', 'gos gate all'],
    contractKeys: [],
  },
  'archive': {
    desc: 'archive spec/plan + write delta.md, mark DONE', class: 'write', aliases: [], core: false,
    subs: [], flags: [],
    usage: 'gos archive',
    next: ['gos', 'gos phase list'],
    contractKeys: ['command_contracts.archiveIdempotent'],
  },
  'setup': {
    desc: 'install skills symlinks for detected platforms', class: 'global', aliases: [], core: false,
    subs: [], flags: ['--local <path>'], usage: 'gos setup [--local <path>]',
    next: ['gos doctor'],
    contractKeys: [],
  },
  'teardown': {
    desc: 'remove skill symlinks', class: 'global', aliases: [], core: false,
    subs: [], flags: [], usage: 'gos teardown',
    next: ['gos doctor'],
    contractKeys: [],
  },
  'doctor': {
    desc: 'diagnose installation (CLI/skills links/platforms), read-only', class: 'global', aliases: [], core: false,
    subs: [], flags: [], usage: 'gos doctor',
    next: ['gos setup'],
    contractKeys: [],
  },
  'brownfield': {
    desc: 'adopt GOS into an existing repo: classify conflicts, seed missing assets, install dormant hooks (lock-free global class)', class: 'global', aliases: [], core: false,
    subs: [],
    flags: [
      { name: '--json', scope: 'brownfield', effect: 'machine-readable report envelope (sole legal machine mode)', risk: 'safe' },
      { name: '--overwrite', scope: 'brownfield', effect: 'overwrite conflicting assets, optionally limited to one named asset (locked user-owned assets still refuse)', risk: 'mutating' },
      { name: '--print-agents-skeleton', scope: 'brownfield', effect: 'print a starter AGENTS.md skeleton to stdout without touching the repo', risk: 'safe' },
    ],
    usage: 'gos brownfield [--json] [--overwrite [<asset>]] [--print-agents-skeleton]',
    next: ['gos setup --commitlint', 'gos init <level> "<intent>"'],
    contractKeys: ['command_contracts.brownfieldStatusSet', 'command_contracts.brownfieldStateFlags', 'command_contracts.brownfieldExitCodes', 'command_contracts.brownfieldPreflightReasons'],
  },
  '_contract': {
    desc: 'print frozen contract table (tests/skills assert from it)', class: 'global', aliases: [], core: false,
    subs: ['--check-input "<text>" [--max-cp N]'], flags: [],
    usage: 'gos _contract [--check-input "<text>"]',
    next: ['gos help --json'],
    contractKeys: ['command_contracts.contractJson'],
  },
  'paths': {
    desc: 'GOS_PATHS registry query: abs-path JSON (project_root + per-key metadata) or README regen', class: 'write', aliases: [], core: false,
    subs: ['--markdown'], flags: [],
    usage: 'gos paths [--markdown]',
    next: ['gos context build', 'gos gate all'],
    contractKeys: ['command_contracts.readmeGenerated', 'command_contracts.readmeHeader'],
  },
  'gate': {
    desc: 'hard gates: coverage|truths|requirements|lessons|semantic|codemap|all + hash-trust-verified custom gates (--json failures: object-only {code,verdict,evidence[],fix} since P15)', class: 'exec', aliases: [], core: true,
    subs: ['coverage', 'truths', 'requirements', 'lessons', 'semantic', 'codemap', 'all', 'trust <name>', '<custom-gate>'],
    flags: [],
    usage: 'gos gate <name>',
    next: ['gos gate all', 'gos map closure <file>'],
    contractKeys: ['gate_verdicts.trustUntrusted', 'gate_verdicts.trustDrift', 'gate_verdicts.trustUnreadableScript', 'gate_verdicts.trustStoreUnreadable', 'gate_verdicts.trustConfigPolluted', 'gate_verdicts.trustCiAdvisory', 'gate_verdicts.customGateEmpty', 'gate_verdicts.trustRegistered'],
  },
  'section': {
    desc: 'run test/sections/T*.test.sh with fixture isolation (env pins + cwd contract + first-run confirmation + run manifest); trust pre-confirms the list',
    class: 'exec', aliases: [], core: false,
    subs: ['run [name-filter] [--timeout <sec>]', 'trust'],
    flags: [
      { name: '--timeout', scope: 'run', effect: 'per-section hard timeout in seconds (default 120; env GOS_SECTION_TIMEOUT)', risk: 'safe' },
    ],
    usage: 'gos section run [name-filter] [--timeout <sec>] | gos section trust',
    next: ['gos gate all', 'gos section trust'],
    contractKeys: ['section_runner.threatModel', 'section_runner.noSections', 'section_runner.headlessUnconfirmed', 'section_runner.ciSkip', 'section_runner.confirmHeader', 'section_runner.confirmPrompt', 'section_runner.confirmDeclined', 'section_runner.confirmStored', 'section_runner.bashMissing', 'section_runner.aborted', 'section_runner.timeout', 'section_runner.markerMissing', 'section_runner.sweepLine', 'section_runner.trustRegistered', 'section_runner.trustEmpty'],
  },
  'resolve-model': {
    desc: 'subagent model resolution (staffing-aware)', class: 'read', aliases: [], core: false,
    subs: ['<agent>'], flags: [], usage: 'gos resolve-model <agent>',
    next: ['gos config models'],
    contractKeys: [],
  },
  'config': {
    desc: 'show/set model staffing: team | solo | elite | lean', class: 'write', aliases: [], core: false,
    subs: ['models [get|set]'], flags: [], usage: 'gos config models',
    next: ['gos resolve-model <agent>'],
    contractKeys: [],
  },
  'trace': {
    desc: 'trace chain: requirements → decisions → tasks → truths', class: 'read', aliases: [], core: false,
    subs: ['requirements', 'decisions', 'tasks', 'truths'],
    flags: [], usage: 'gos trace <sub>',
    next: ['gos gate coverage'],
    contractKeys: [],
  },
  'decision': {
    desc: 'truth-source decisions: add [id] "title" --rationale | amend | cover | list | import', class: 'write', aliases: [], core: true,
    subs: ['add [id] "<title>" --rationale "<r>"', 'amend <D-NN> --rationale "<r>"', 'cover <D-NN> --by <P-NN>', 'list', 'import [--all|--discard]'],
    flags: [], usage: 'gos decision <sub> [args]',
    next: ['gos decision list', 'gos render'],
    contractKeys: ['command_contracts.decisionAdded', 'command_contracts.decisionAmended', 'command_contracts.decisionCovered', 'command_contracts.ghostFixTeaching', 'command_contracts.dupArchivedTeaching', 'command_contracts.archivedRefusedTeaching'],
  },
  'requirement': {
    desc: 'truth-source requirements: add | list | drop | claim', class: 'write', aliases: [], core: false,
    subs: ['add "<text>"', 'list', 'drop <R-NN>', 'claim <R-NN> --phase "<P: name>"'],
    flags: [], usage: 'gos requirement <sub> [args]',
    next: ['gos requirement list', 'gos gate requirements'],
    contractKeys: ['command_contracts.reqAdded', 'command_contracts.listNoSources', 'command_contracts.listForeignProject'],
  },
  'phase': {
    desc: 'Lv4 phase lifecycle: add | list | claim | unclaim | mark-done', class: 'write', aliases: [], core: true,
    subs: ['add "P: name" --goal "<g>"', 'amend <n> --goal "<g>"', 'list', 'claim <n>', 'unclaim', 'park <n>', 'mark-done <n>'],
    flags: [
      { name: '--force', scope: 'claim', effect: 'bypass DONE/archive preconditions (data-loss risk if task mid-flight)', risk: 'destructive' },
    ],
    usage: 'gos phase <sub> [args]',
    next: ['gos phase list', 'gos phase claim <n>'],
    contractKeys: ['command_contracts.phaseAdded', 'command_contracts.phaseAmended', 'command_contracts.amendRefuseActive', 'command_contracts.amendRefuseDone', 'command_contracts.amendRefuseParked', 'command_contracts.phaseClaimed', 'command_contracts.phaseUnclaimed', 'command_contracts.claimGatedPrev', 'command_contracts.claimDeferredHint', 'command_contracts.claimCrossPhaseHint', 'command_contracts.claimTargetDone', 'command_contracts.claimAllClosed', 'command_contracts.claimTargetParked', 'command_contracts.doneHintParkedLine', 'command_contracts.doneHintAllDone', 'command_contracts.phaseParked', 'command_contracts.parkBlocksMilestone', 'command_contracts.parkUndo', 'command_contracts.parkIdempotent', 'command_contracts.parkUndoIdempotent', 'command_contracts.parkRefuseActive', 'command_contracts.parkRefuseDone', 'command_contracts.parkOrphanWarn', 'command_contracts.markDoneCloseOut', 'command_contracts.milestoneBlockedHeader'],
  },
  'anchor': {
    desc: 're-anchor state.project_root (rescue)', class: 'write', aliases: [], core: false,
    subs: ['fix'], flags: [],
    usage: 'gos anchor fix',
    next: ['gos doctor'],
    contractKeys: ['command_contracts.anchorFixed'],
  },
  'render': {
    desc: 'regenerate DECISIONS/ROADMAP/REQUIREMENTS views from project.json', class: 'write', aliases: [], core: false,
    subs: [], flags: [], usage: 'gos render',
    next: ['gos phase list'],
    contractKeys: ['command_contracts.renderDone', 'command_contracts.renderSkip', 'command_contracts.generatedHeader', 'command_contracts.manualMarker'],
  },
  'auto': {
    desc: 'auto-flow toggle (on | off)', class: 'write', aliases: [], core: false,
    subs: ['on', 'off'], flags: [], usage: 'gos auto <sub>',
    next: ['gos'],
    contractKeys: [],
  },
  'approve': {
    desc: 'record user sign-off for a stage gate', class: 'write', aliases: [], core: false,
    subs: ['<stage>'], flags: [], usage: 'gos approve <stage>',
    next: ['gos commit <stage>'],
    contractKeys: [],
  },
  'lessons': {
    desc: 'lessons json truth: add/rm/amend/list/prune/skip/anchor-rebuild/migrate', class: 'write', aliases: [], core: false,
    subs: ['add', 'rm', 'amend', 'list', 'prune', 'skip', 'anchor-rebuild', 'migrate'],
    flags: [], usage: 'gos lessons <sub> [args]',
    next: ['gos lessons list'],
    contractKeys: [],
  },
  'truth': {
    desc: 'observable truths: add "<desc>" | verify <id> (--replay executes it)', class: 'write', aliases: [], core: false,
    subs: ['add "<desc>"', 'verify <id> --command "<c>" --excerpt "<e>" --artifact <path>'],
    flags: [
      { name: '--replay', scope: 'verify', effect: 'execute --command (JSON argv) and capture real stdout as excerpt', risk: 'safe' },
    ],
    usage: 'gos truth <sub> [args]',
    next: ['gos gate truths'],
    contractKeys: [],
  },
  'logs': {
    desc: 'view runtime audit ledgers: receipts | exemptions | audit (formatted tables, --last N, default 20)', class: 'read', aliases: [], core: false,
    subs: ['receipts', 'exemptions', 'audit'],
    flags: [
      { name: '--last', scope: 'logs', effect: 'show only the last N entries (default 20)', risk: 'safe' },
    ],
    usage: 'gos logs <receipts|exemptions|audit> [--last N]',
    next: ['gos logs receipts', 'gos gate all'],
    contractKeys: [],
  },
  'gap': {
    desc: 'state gaps: list | resolve <G-id> --resolution "<r>" | rewrite <G-id> --text "<t>" | migrate (cure (auto) mirrors into the ledger) | history (fail-closed)', class: 'write', aliases: [], core: false,
    subs: ['list', 'resolve <G-id> --resolution "<r>"', 'rewrite <G-id> --text "<t>"', 'migrate', 'history'], flags: [],
    usage: 'gos gap <sub> [args]',
    next: ['gos gap list'],
    contractKeys: [],
  },
  'map': {
    desc: 'anchor-network map 2.0: edge graph | scan | anchor <spec> | closure | show (fn-level: closure/show <path#fn:x>, graph --fn <anchor>)', class: 'read', aliases: [], core: false,
    subs: ['edge add', 'edge rm', 'edge adopt', 'edge rewrite', 'edge verify', 'edge audit-log', 'anchor <path[#anchor]>', 'scan', 'blast <paths...> (plain-language impact report)', 'closure <paths...>', 'closure <path#fn:x>', 'show', 'allowlist init'],
    flags: [
      { name: '--print0', scope: 'closure', effect: 'NUL-separated paths only (sole legal machine mode)', risk: 'safe' },
      { name: '--forward', scope: 'closure', effect: 'forward closure instead of reverse', risk: 'safe' },
      { name: '--no-refresh', scope: 'closure', effect: 'use cached deps.json without rescan', risk: 'safe' },
      { name: '--type', scope: 'edge add/rm', effect: 'edge type (consumes|asserts|greps|contract-ref|owns|test-of)', risk: 'safe' },
      { name: '--note', scope: 'edge add', effect: 'free-text note (rendered escaped)', risk: 'safe' },
      { name: '--bootstrap', scope: 'edge adopt', effect: 'seed an empty tracked edges.json in a repo without one', risk: 'mutating' },
      { name: '--semantic', scope: 'closure', effect: 'three-source human closure report (qualified wording)', risk: 'safe' },
      { name: '--json', scope: 'closure', effect: 'strict machine envelope (byte-0 JSON, sole machine mode with --print0)', risk: 'safe' },
      { name: '--graph', scope: 'show/graph', effect: 'mermaid rendering (graph=full, show=1-hop neighborhood)', risk: 'safe' },
      { name: '--fn', scope: 'graph', effect: 'fn-neighborhood graph — REQUIRES <path#fn:name> anchor (bare --fn dies; full graph omits fn families by default)', risk: 'safe' },
      { name: '--2hop', scope: 'show/graph --fn', effect: 'extend neighborhood to 2 hops (hub explosion guard: default 1)', risk: 'safe' },
      { name: '--external', scope: 'edge add', effect: 'mark the to-endpoint as external (dead-path exempt, dashed render)', risk: 'safe' },
      { name: '--from/--to', scope: 'edge rewrite', effect: 'batch-migrate anchor endpoints after renames', risk: 'mutating' },
      { name: '--force', scope: 'allowlist init', effect: 'overwrite an existing require-allowlist.json after printing the direction diff', risk: 'destructive' },
    ],
    usage: 'gos map <sub> [args]',
    next: ['gos map show', 'gos map closure bin/gos.cjs#fn:<name>', 'gos gate all'],
    contractKeys: [],
  },
  'concerns': {
    desc: 'curated worry list: add | list | prune (hash sidecar anchored)', class: 'read', aliases: [], core: false,
    subs: ['add "<text>"', 'list', 'prune --contains <substr>'],
    flags: [], usage: 'gos concerns <sub> [args]',
    next: ['gos concerns list'],
    contractKeys: [],
  },
  'changelog': {
    desc: 'single-track CHANGELOG.md: add (instantiated entry; mutates via internal lock) | lint', class: 'read', aliases: [], core: false,
    subs: ['add --summary "<one sentence>" [--type <verb>] [--refs "D-nn,R-nn"]', 'lint'],
    flags: [
      { name: '--summary', scope: 'add', effect: 'one-sentence user summary (cached task-scoped after first use)', risk: 'safe' },
      { name: '--type', scope: 'add', effect: 'category verb override (default Add; must be a changelog-core CATEGORY_VERBS entry)', risk: 'safe' },
      { name: '--refs', scope: 'add', effect: 'explicit D-nn/R-nn trace refs (default: covered decisions + active requirements of the task)', risk: 'safe' },
    ],
    usage: 'gos changelog <sub> [args]',
    next: ['gos changelog add', 'gos changelog lint'],
    contractKeys: [],
  },
  'feedback': {
    desc: 'local feedback drafts (untracked) + gh publication: add | list | close | push (argv-strict, idempotent marker, owner guard)',
    class: 'write', aliases: [], core: false,
    subs: ['add issue|discussion "<title>" [--body "<text>"]', 'list [--type <issue|discussion>] [--status <open|closed>]', 'close <N> --resolution "<text>"', 'push <N> [--to owner/repo]'],
    flags: [
      { name: '--body', scope: 'add', effect: 'entry body text (multi-line allowed)', risk: 'safe' },
      { name: '--type', scope: 'list', effect: 'filter entries by type (issue|discussion)', risk: 'safe' },
      { name: '--status', scope: 'list', effect: 'filter entries by status (open|closed|sending|published)', risk: 'safe' },
      { name: '--resolution', scope: 'close', effect: 'close resolution recorded in the entry file', risk: 'safe' },
      { name: '--to', scope: 'push', effect: 'explicit target repo (overrides origin; required for foreign-owner targets in headless runs)', risk: 'mutating' },
    ],
    usage: 'gos feedback <sub> [args]',
    next: ['gos feedback list', 'gos feedback push <N>'],
    contractKeys: ['command_contracts.feedbackAdded', 'command_contracts.feedbackClosed', 'command_contracts.feedbackOwnerRefuse', 'command_contracts.feedbackPublished', 'command_contracts.feedbackGhMissing'],
  },
  'push': {
    desc: 'aggregate origin/main..HEAD into one semantic commit and push to main (local chain untouched; mutates only the remote)',
    class: 'read', aliases: [], core: false,
    subs: [],
    flags: [
      { name: '--message', scope: 'push', effect: 'explicit aggregate subject (default: CHANGELOG.md [Unreleased] bullets added since origin/main)', risk: 'safe' },
    ],
    usage: 'gos push [--message "<one-liner>"]',
    next: ['gos push', 'gos changelog add'],
    contractKeys: [],
  },
  'help': {
    desc: 'this help (rendered from COMMANDS registry)', class: 'global', aliases: ['--help', '-h'], core: true,
    subs: ['<cmd>'], flags: [{ name: '--json', scope: 'help', effect: 'machine-readable envelope (sole legal machine mode)', risk: 'safe' }],
    usage: 'gos help [<cmd>|--json]',
    next: ['gos help --json'],
    contractKeys: [],
  },
  '--version': {
    desc: 'print version', class: 'global', flagOnly: true, aliases: ['--version', '-v'], core: false,
  },
};

// Path-field registry — single source of truth consumed by three sites: the
// archive rewriter, pre-flight normalization, and validation.
// Pure-data const (no new top-level fns). New state path fields must be
// registered here, or the archive rewriter will not rewrite them.
const STATE_PATH_FIELDS = {
  direct: ['spec_path', 'plan_path'],                                  // top-level string paths
  nested: [['observable_truths', 'evidence', 'artifact_path']],        // paths nested inside array elements
};

module.exports = {
  STATE_PATH_FIELDS,
  NO_CMD_KEY,
  COMMANDS,
  validateDecision,
  validateRequirement,
  validateState,
  validateProject,
  migrateState,
  readState,
  writeState,
  firstCJKLeaf,
  dieTrackedStoreCJK,
  currentTaskId,
  ensureTaskDir,
  specPathOf,
  planPathOf,
  defaultState,
  currentRootRealpath,
  emptyProject,
  loadProject,
  saveProject,
  checkInputConstraint,
  tryCmd,
  badText,
  badAnchor,
  extractRequirement,
  lessonsPaths,
  validateEvidenceObject,
  validatePhase,
  cpLen,
  idNum,
  STATE_SCHEMA_VERSION,
  PROJECT_SCHEMA_VERSION,
  canonicalRepoUrl,
  deriveRepoId,
  repoIdFromRemotes,
  ID_RE,
  DECISION_STATUS,
  REQ_STATUS,
  PHASE_STATUS,
  CONTRACTS,
  STAGE_ORDER,
  EVIDENCE_FEATURE_RES_MANUAL,
  EVIDENCE_FEATURE_RES_REPLAY,
  replayEvidenceHit,
};
