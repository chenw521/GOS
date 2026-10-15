// ops/changelog-core — single-source CHANGELOG.md validator primitives.
// Shared implementation for `gos changelog add` (pre-write gate) and
// `gos changelog lint` (post-hoc enforcement): one validator, zero drift (R-05).
// The validator family stays pure — no filesystem access, no CLI side effects;
// the command shells live in bin/lib/task/changelog.cjs and consume this module.
//
// D-07 (R-32) widens the module with the single root-anchored changelog
// LOCATION resolver + the shared changelog lock: `path.resolve('CHANGELOG.md')`
// at require time was cwd-anchored — subdir invocations bootstrapped a foreign
// CHANGELOG and archive misreported. The resolver folds the two former
// hardcodes (task/changelog.cjs + task/archive.cjs) into one function anchored
// at the PROJECT ROOT (git toplevel → nearest .gos ancestor → cwd), reading
// the PROJECT-layer config key `changelog_path` (global layer is never
// consulted — a global value could not pass in-root validation for other
// repos, D-07 R3-F8). Validation runs on BOTH the config-set write side and
// the resolver read side (R1-F5) from one implementation below.
//
// Entry format contract (bullet inside [Unreleased] or a version section):
//   `- <CategoryVerb> <one-sentence summary> (<D-nn|R-nn refs>) [YYYY-MM-DD]`
// The trailing bracket is a UTC date stamp (R-08); `promoteUnreleased` strips
// stamps when moving entries into a released version section. All date math
// flows through `utcToday()` — the single time source shared by add and lint.
//
// Forbidden entry classes (each rejected independently; all errors English):
//   F1  bare `DI-<n>` token anywhere — internal finding ids never enter entries
//   F2  bare `T-<n>` token outside trace-ref parentheses — task ids belong in
//       commit bodies; parenthesised trace refs accept only D-nn/R-nn tokens
//   F3  circled numerals (U+2460..U+24FF) — use separate bullets, not
//       circled-number-style marks
//   F4  `U+00A7<digit>` section markers — reference documents by name, not
//       section number
//   F5  decision id as grammatical subject — the sentence must not start with
//       `D-<n>`
//   F6  process-narration markers — /red[- ]team/i, /\bwave\s*\d+/i,
//       /\bphase\b/i, a leading `P<n>` phase prefix, plus the CJK equivalents
//       of "stage" and "wave"; entries describe outcomes, not process
//   F7  multi-sentence entries — sentence-ending punctuation followed by more
//       content; exactly one sentence per bullet
//
// Structural checks for validateStructure (the R-06 three checks):
//   S1  exactly one top-level `# ` title
//   S2  version dates newest-first (descending); each version heading carries
//       a valid `YYYY-MM-DD` date
//   S3  today's obligation — a bullet stamped with today's UTC date exists in
//       [Unreleased] or in the latest version section

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const core = require('../core/index.cjs');

// Imperative category verbs an entry must start with (exact word, imperative
// form). Exported so the add generator templates its output from the same
// single source (R-05); extending the list here extends both consumers.
const CATEGORY_VERBS = [
  'Add', 'Bump', 'Change', 'Chore', 'CI', 'Deprecate', 'Docs', 'Document',
  'Drop', 'Fix', 'Init', 'Move', 'Perf', 'Promote', 'Refactor', 'Remove',
  'Rename', 'Revert', 'Secure', 'Split', 'Test', 'Wire',
];
const VERB_RE = new RegExp(`^(?:${CATEGORY_VERBS.join('|')})\\b`);
// Conventional Commits prefix a bullet may carry instead of a category verb
// ("feat: ...", "fix(ops): ...") so the bullet doubles as an aggregate subject.
const CONVENTIONAL_VERB_RE = /^(feat|fix|docs|refactor|test|chore|ci|build|perf|revert)(\([a-z0-9-]+\))?:\s/;

const H1_RE = /^#[ \t]+\S/;
const H2_RE = /^##(?:[ \t]|$)/;
const UNRELEASED_RE = /^##\s*\[\s*Unreleased\s*\]/i;
const VERSION_HEADING_RE = /^##\s*\[([^\]]+)\](?:\s*-\s*(\S+))?/;
const BULLET_RE = /^[ \t]*-[ \t]+(\S.*)$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const STAMP_TAIL_RE = /\s*\[(\d{4}-\d{2}-\d{2})\]\s*$/;
const TRACE_GROUP_RE = /\(([^()]*)\)/g;
const TRACE_WELL_FORMED_RE = /^(?:[DR]-\d+)(?:\s*[,/]\s*(?:[DR]-\d+))*$/;
const BARE_DI_RE = /\bDI-\d+/;
const BARE_T_RE = /\bT-\d+/;
const CIRCLED_RE = /[\u2460-\u24FF]/;
const SECTION_MARK_RE = /\u00A7\s*\d/;
const SUBJECT_DEC_RE = /^D-\d+/;
const PHASE_PREFIX_RE = /^P\d+\b/;
const NARRATION_RES = [
  /red[- ]team/i,
  /\bwave\s*\d+/i,
  /\bphase\b/i,
  /\u9636\u6bb5/, // CJK "stage"
  /\u6ce2\u6b21/, // CJK "wave"
];
// Sentence boundary: an ender followed by inline whitespace and visible text.
// ASCII enders only count when the next visible char is a letter, so version
// strings like "v1.2.0" or "node.js" never trigger a false positive; CJK
// enders are stricter because CJK prose does not use inter-word spaces.
const SENT_END_PAIR_RE = /([.!?\uFF1B\uFF01\uFF1F\u3002;])[ \t]+(\S)/;
const CJK_ENDERS = '\u3002\uFF01\uFF1F\uFF1B';

function hasMultiSentence(body) {
  const m = body.match(SENT_END_PAIR_RE);
  if (!m) return false;
  if (CJK_ENDERS.includes(m[1])) return true;
  return /[A-Za-z]/.test(m[2]);
}

// The single time source (R-08): every "today" decision in add/lint/promote
// resolves through this function so UTC semantics can never drift per caller.
function utcToday() {
  return new Date().toISOString().slice(0, 10);
}

// Tolerant parse of a Keep-a-Changelog-style document. Never throws; a missing
// [Unreleased] section yields an empty array, and prose between bullets is
// ignored. `versions` preserves file order (expected newest-first; structural
// enforcement lives in validateStructure, not here).
function parseChangelog(text) {
  const src = String(text == null ? '' : text);
  const lines = src.split(/\r?\n/);
  const hasHeader = lines.some((l) => H1_RE.test(l));
  const hasUnreleasedHeading = lines.some((l) => UNRELEASED_RE.test(l));
  const firstH2 = lines.findIndex((l) => H2_RE.test(l));
  const headerEnd = firstH2 === -1 ? lines.length : firstH2;
  const header = lines.slice(0, headerEnd).join('\n');
  const unreleased = [];
  const versions = [];
  let current = null; // null | 'unreleased' | version object
  for (const line of lines) {
    if (H2_RE.test(line)) {
      if (UNRELEASED_RE.test(line)) {
        current = 'unreleased';
      } else {
        const vm = line.match(VERSION_HEADING_RE);
        current = vm
          ? { tag: vm[1].trim(), date: vm[2] || '', entries: [] }
          : null;
        if (current) versions.push(current);
      }
      continue;
    }
    const bm = line.match(BULLET_RE);
    if (bm && current) {
      const entry = `- ${bm[1].trim()}`;
      if (current === 'unreleased') unreleased.push(entry);
      else current.entries.push(entry);
    }
  }
  return { header, hasHeader, hasUnreleasedHeading, unreleased, versions };
}

// Fail-closed entry gate shared by add (pre-write) and lint (post-hoc).
// Returns every violation found so callers can surface a full rewrite list.
function validateEntry(entry) {
  const errors = [];
  const raw = String(entry == null ? '' : entry).replace(/\r/g, '');
  const line = raw.split('\n')[0].trim();
  const singleLine = raw.trim().split('\n').length === 1;
  if (!singleLine || !line.startsWith('- ')) {
    errors.push("structure: entry must be a single bullet line starting with '- '");
  }
  const content = line.replace(/^-[ \t]+/, '').trim();

  const wm = content.match(/^(\S+)(?:\s+([\s\S]*))?$/);
  const verb = wm ? wm[1] : '';
  const rest = wm && wm[2] ? wm[2].trim() : '';
  if (!verb || (!VERB_RE.test(content) && !CONVENTIONAL_VERB_RE.test(content))) {
    errors.push(`structure: entry must start with a category verb or conventional token (feat:/fix(ops):) — allowed: ${CATEGORY_VERBS.join(', ')}`);
  }

  if (!STAMP_TAIL_RE.test(rest)) {
    errors.push('structure: missing UTC date stamp — entry must end with [YYYY-MM-DD]');
  }
  const body = rest.replace(STAMP_TAIL_RE, '');

  const groups = [];
  let g;
  const groupRe = new RegExp(TRACE_GROUP_RE.source, 'g');
  while ((g = groupRe.exec(body)) !== null) groups.push(g[1].trim());
  if (groups.length === 0) {
    errors.push("structure: missing required trace refs — add a group like '(D-42)' or '(R-05, D-42)'");
  }
  for (const gr of groups) {
    if (!TRACE_WELL_FORMED_RE.test(gr)) {
      errors.push(`structure: malformed trace refs '(${gr})' — only D-nn/R-nn tokens separated by ',' or '/' are allowed`);
    }
  }

  const summary = body.replace(/\([^()]*\)/g, ' ').replace(/\s+/g, ' ').trim();
  if (!summary) {
    errors.push('structure: missing one-sentence summary after the category verb');
  }

  if (BARE_DI_RE.test(content)) {
    errors.push('forbidden: bare DI-<n> token — internal finding ids never belong in changelog entries');
  }
  const outsideParens = content.replace(/\([^()]*\)/g, ' ');
  if (BARE_T_RE.test(outsideParens)) {
    errors.push('forbidden: bare T-<n> token — task ids belong in commit bodies, not entries (trace refs must be D-nn/R-nn)');
  }
  if (CIRCLED_RE.test(content)) {
    errors.push('forbidden: circled numerals (U+2460 range) — use separate bullets instead of numbered marks');
  }
  if (SECTION_MARK_RE.test(content)) {
    errors.push('forbidden: section marker (U+00A7 + digit) — reference documents by name, not section number');
  }
  if (SUBJECT_DEC_RE.test(content)) {
    // Defensive redundancy: the category-verb rule usually rejects a leading
    // "D-<n>" first; this guard keeps the ban explicit if that rule is ever
    // relaxed, and appends a clearer reason when both fire.
    errors.push("forbidden: decision id as grammatical subject — do not start the sentence with 'D-<n>'");
  }
  if (PHASE_PREFIX_RE.test(content) || NARRATION_RES.some((re) => re.test(content))) {
    errors.push('forbidden: process-narration marker — describe the change outcome, not the process (banned: red team, wave <n>, phase, leading P<n>)');
  }
  if (hasMultiSentence(body)) {
    errors.push('forbidden: multi-sentence entry — exactly one sentence per bullet');
  }

  return { ok: errors.length === 0, errors };
}

// The R-06 three structural checks. `todayUtc` is injectable for deterministic
// tests; when absent it defaults to utcToday() — the same single time source
// the add path uses (R-08).
function validateStructure(text, opts) {
  const errors = [];
  const injected = opts && typeof opts.todayUtc === 'string' ? opts.todayUtc : '';
  const today = DATE_RE.test(injected) ? injected : utcToday();
  const lines = String(text == null ? '' : text).split(/\r?\n/);

  const titleCount = lines.filter((l) => H1_RE.test(l)).length;
  if (titleCount !== 1) {
    errors.push(`structure: exactly one top-level '# ' title required (found ${titleCount})`);
  }

  const parsed = parseChangelog(text);
  for (const v of parsed.versions) {
    if (!DATE_RE.test(v.date)) {
      errors.push(`structure: version [${v.tag}] heading must carry a valid date — expected '## [tag] - YYYY-MM-DD', found '${v.date || 'none'}'`);
    }
  }
  for (let i = 0; i + 1 < parsed.versions.length; i++) {
    const a = parsed.versions[i];
    const b = parsed.versions[i + 1];
    if (DATE_RE.test(a.date) && DATE_RE.test(b.date) && a.date < b.date) {
      errors.push(`structure: version dates must be newest-first — [${b.tag}] (${b.date}) is newer than [${a.tag}] (${a.date}) listed above it`);
    }
  }

  const stampedToday = (e) => e.endsWith(`[${today}]`);
  const latest = parsed.versions[0];
  const met = parsed.unreleased.some(stampedToday)
    || (latest !== undefined && latest.entries.some(stampedToday));
  if (!met) {
    errors.push(`structure: today's obligation unmet — no entry stamped '[${today}]' (UTC) in [Unreleased] or the latest version section`);
  }

  return { ok: errors.length === 0, errors };
}

// Semver-ish tag comparison: optional leading v, dot-separated numeric
// segments compared numerically, non-numeric segments compared lexically.
// Returns <0 when a sorts before (older than) b.
function compareTag(a, b) {
  // Semver-aware: numeric triple first, then prerelease precedence (absence
  // ranks higher; numeric identifiers rank below alphanumeric). Non-semver
  // strings fall back to per-segment comparison. Mirrors the comparator in
  // scripts/release-validate.sh — keep the two verdicts identical.
  const parse = (t) => {
    const s = String(t).replace(/^v/i, '').trim();
    const m = /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$/.exec(s);
    return m ? { core: [+m[1], +m[2], +m[3]], pre: m[4] ? m[4].split('.') : [], semver: true }
             : { raw: s.split('.'), semver: false };
  };
  const A = parse(a), B = parse(b);
  if (!A.semver || !B.semver) {
    const as = A.semver ? [A.core.join('.')] : A.raw, bs = B.semver ? [B.core.join('.')] : B.raw;
    const n = Math.max(as.length, bs.length);
    for (let i = 0; i < n; i++) {
      const x = as[i], y = bs[i];
      if (x === undefined) return -1;
      if (y === undefined) return 1;
      let c;
      if (/^\d+$/.test(x) && /^\d+$/.test(y)) c = parseInt(x, 10) - parseInt(y, 10);
      else c = x < y ? -1 : x > y ? 1 : 0;
      if (c !== 0) return c < 0 ? -1 : 1;
    }
    return 0;
  }
  for (let i = 0; i < 3; i++) if (A.core[i] !== B.core[i]) return A.core[i] < B.core[i] ? -1 : 1;
  if (A.pre.length === 0 && B.pre.length === 0) return 0;
  if (A.pre.length === 0) return 1;
  if (B.pre.length === 0) return -1;
  for (let i = 0; i < Math.max(A.pre.length, B.pre.length); i++) {
    const x = A.pre[i], y = B.pre[i];
    if (x === undefined) return -1;
    if (y === undefined) return 1;
    const xn = /^\d+$/.test(x), yn = /^\d+$/.test(y);
    if (xn && yn) { if (+x !== +y) return +x < +y ? -1 : 1; }
    else if (xn) return -1;
    else if (yn) return 1;
    else if (x !== y) return x < y ? -1 : 1;
  }
  return 0;
}

// Fold [Unreleased] entries into a new version section (D-43: no backfill;
// accumulate then promote). Boundary order: skeleton integrity first
// ('no-header'), then tag sanity ('version-rollback'), then content presence
// ('nothing-to-release'). Entries keep their text but lose the UTC date
// stamps — the stamp is an [Unreleased]-period marker only (R-08).
function promoteUnreleased(text, tag) {
  const src = String(text == null ? '' : text);
  const parsed = parseChangelog(src);
  if (!parsed.hasHeader || !parsed.hasUnreleasedHeading) {
    return { ok: false, reason: 'no-header' };
  }
  if (parsed.versions.length && compareTag(tag, parsed.versions[0].tag) <= 0) {
    return { ok: false, reason: 'version-rollback' };
  }
  if (parsed.unreleased.length === 0) {
    return { ok: false, reason: 'nothing-to-release' };
  }
  const lines = src.split(/\r?\n/);
  const unrelIdx = lines.findIndex((l) => UNRELEASED_RE.test(l));
  let end = lines.length;
  for (let i = unrelIdx + 1; i < lines.length; i++) {
    if (H2_RE.test(lines[i])) { end = i; break; }
  }
  const stripped = parsed.unreleased.map((e) => e.replace(/\s*\[\d{4}-\d{2}-\d{2}\]\s*$/, ''));
  const out = lines.slice(0, unrelIdx + 1); // up to and including the [Unreleased] heading (now empty)
  out.push('');
  out.push(`## [${String(tag).trim()}] - ${utcToday()}`);
  out.push('');
  out.push(...stripped);
  out.push('');
  out.push(...lines.slice(end));
  return { ok: true, text: out.join('\n') };
}

// ---- D-07 (R-32): single changelog location resolver + shared lock ----

const CHANGELOG_PATH_KEY = 'changelog_path';
const DEFAULT_CHANGELOG_REL = 'CHANGELOG.md';

// Project root for changelog resolution — NEVER process cwd (R2-4): git
// toplevel first (sandbox-isolation safe: every managed repo is its own git
// tree, and a bare ancestor can never be mistaken for the project), then the
// nearest ancestor carrying a .gos/ directory (non-git managed trees), then
// cwd as the base of last resort for genuinely unmanaged trees.
// Self-root carve-out: a resolved root equal to the CLI's OWN checkout is
// never adopted from a nested cwd — scratch directories inside the
// installation tree (the repo's test sandboxes) are unmanaged context, not
// project subdirs (same interference pattern `run-sections --fresh` and T61
// sidestep by placing fixtures outside the self-repo). At the self root
// itself the root still wins: running AT the checkout is project context.
function changelogProjectRoot() {
  let here = process.cwd();
  try { here = fs.realpathSync(here); } catch { /* keep cwd */ }
  let selfRoot = core.GOS_SELF_ROOT;
  try { selfRoot = fs.realpathSync(selfRoot); } catch { /* keep lexical */ }
  const top = core.gitToplevelRealpath();
  if (top) {
    if (top === here) return top;
    if (top === selfRoot) return here; // nested inside the CLI checkout — unmanaged
    return top;
  }
  let dir = here;
  for (;;) {
    try { if (fs.statSync(path.join(dir, '.gos')).isDirectory() && dir !== selfRoot) return dir; } catch { /* not here */ }
    const parent = path.dirname(dir);
    if (parent === dir) return here;
    dir = parent;
  }
}

// Path-shape validation shared by `gos config changelog-path` (write side) and
// the resolver (read side) — R1-F5 dual validation, one implementation.
// Rejects: absolute paths, '..' segments (raw input AND normalized escape),
// realpath escapes via symlink chains, anything under .git/, node_modules/,
// or .gos/ entirely (R3-F8: agent artifacts never live at the .gos/ root —
// orphan scan and ship adoption would sweep the file away), and any suffix
// other than .md. Returns { ok, rel (posix), abs } or { ok: false, reason }.
function validateChangelogRelPath(raw, root) {
  const input = String(raw == null ? '' : raw).trim();
  if (!input) return { ok: false, reason: 'path is empty — pass a repo-relative path like docs/CHANGELOG.md' };
  if (path.isAbsolute(input)) {
    return { ok: false, reason: `'${input}' is absolute — changelog-path is repo-relative and resolves against the project root` };
  }
  for (const seg of input.split(/[\\/]+/)) {
    if (seg === '..') return { ok: false, reason: `'${input}' contains a '..' segment — the changelog must stay inside the project root` };
  }
  const abs = path.resolve(root, input);
  const rel = path.relative(root, abs);
  if (!rel || rel === '' || rel.startsWith('..') || path.isAbsolute(rel)) {
    return { ok: false, reason: `'${input}' does not resolve inside the project root (${root})` };
  }
  const segs = rel.split(path.sep);
  if (segs[0] === '.gos') {
    return { ok: false, reason: `'${input}' lives under .gos/ (including .gos/cache/) — agent artifacts never live there; orphan scan and ship adoption would sweep the file away` };
  }
  if (segs.includes('.git')) return { ok: false, reason: `'${input}' lives under .git/ — git internals are off-limits` };
  if (segs.includes('node_modules')) return { ok: false, reason: `'${input}' lives under node_modules/ — dependencies are off-limits` };
  if (!/\.md$/.test(rel)) return { ok: false, reason: `'${input}' must end with .md` };
  // Symlink containment: realpath the nearest existing ancestor — a link chain
  // escaping the project root is rejected even when the lexical path is clean.
  let probe = abs;
  const tail = [];
  for (;;) {
    if (fs.existsSync(probe)) break;
    tail.unshift(path.basename(probe));
    const parent = path.dirname(probe);
    if (parent === probe) { probe = null; break; }
    probe = parent;
  }
  if (probe !== null) {
    let rp = null;
    try { rp = fs.realpathSync(probe); } catch { rp = null; }
    if (rp !== null) {
      const deep = tail.length ? path.join(rp, ...tail) : rp;
      const relReal = path.relative(root, deep);
      if (relReal === '' || relReal.startsWith('..') || path.isAbsolute(relReal)) {
        return { ok: false, reason: `'${input}' resolves (realpath) outside the project root — symlink escape` };
      }
    }
  }
  return { ok: true, rel: segs.join('/'), abs };
}

// Project-layer `changelog_path` (never the merged two-layer view — the key is
// project-owned by ruling). Read-side fail-closed: a corrupt layer DIES here
// (no silent fallback to the default location; the quarantine rename stays a
// config-command behavior — read-class commands never mutate).
function configuredChangelogRel(root) {
  const p = path.join(root, '.gos', 'config.json');
  let raw;
  try {
    raw = fs.readFileSync(p, 'utf8');
  } catch (e) {
    if (e && e.code === 'ENOENT') return null;
    core.die(`changelog: project config ${p} is unreadable (${e.message}) — fix the file, then re-run`);
  }
  let obj;
  try {
    obj = JSON.parse(raw);
  } catch (e) {
    core.die(`changelog: project config ${p} is corrupt (${e.message}) — fix or delete it (the next \`gos config\` write command quarantines it), then re-run. Refusing to fall back to the default location silently.`);
  }
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) {
    core.die(`changelog: project config ${p} is not a JSON object — fix or delete it, then re-run`);
  }
  const v = obj[CHANGELOG_PATH_KEY];
  if (v === undefined || v === null) return null;
  return String(v);
}

// THE resolver (folds the former changelog.cjs:38 + archive.cjs:144
// hardcodes): absolute path of the changelog, anchored at the project root and
// reading the project-layer config. Hand-edited config values are re-validated
// here (R1-F5 read-side half) — invalid stored values die with fix guidance.
function resolveChangelogMd() {
  const root = changelogProjectRoot();
  const rel = configuredChangelogRel(root);
  if (rel == null) return path.join(root, DEFAULT_CHANGELOG_REL);
  const v = validateChangelogRelPath(rel, root);
  if (!v.ok) {
    core.die(`changelog: configured changelog_path '${rel}' is invalid — ${v.reason}. Fix it with \`gos config changelog-path <repo-relative .md path>\` or remove '${CHANGELOG_PATH_KEY}' from ${path.join(root, '.gos', 'config.json')}`);
  }
  return v.abs;
}

// ---- shared changelog lock (moved from task/changelog.cjs — D-07) ----
// Root-anchored (was cwd-anchored) so every consumer serializes on one lock
// file per project. Lock ordering is pinned: .gos/.lock → changelog.lock
// (R2-4); `gos config changelog-path` (write-class dispatch already holds
// .gos/.lock) acquires this second and holds both across the whole mv.

const CHANGELOG_LOCK_WAIT_MS = 15000;
const CHANGELOG_LOCK_RETRY_MS = 50;
const CHANGELOG_LOCK_STALE_MS = 120000;

let _changelogLockOwned = false;

function changelogLockPath() {
  return path.join(changelogProjectRoot(), '.gos', 'cache', 'changelog.lock');
}

// O_EXCL acquire with bounded wait: a live holder is waited out (concurrent
// adds / config-set moves serialize), a dead-pid / stale-heartbeat / corrupt
// holder is broken.
function acquireChangelogLock() {
  const lockPath = changelogLockPath();
  fs.mkdirSync(path.dirname(lockPath), { recursive: true });
  const deadline = Date.now() + CHANGELOG_LOCK_WAIT_MS;
  for (;;) {
    let fd = null;
    try {
      fd = fs.openSync(lockPath, 'wx');
    } catch (e) {
      if (e.code !== 'EEXIST') core.die(`changelog lock: open failed (${e.message})`);
      let info = null;
      try { info = JSON.parse(fs.readFileSync(lockPath, 'utf8')); } catch { /* empty or corrupt */ }
      let mtimeStale = false;
      try { mtimeStale = Date.now() - fs.statSync(lockPath).mtimeMs > CHANGELOG_LOCK_STALE_MS; } catch { mtimeStale = false; }
      // Dead-owner evidence: re-read and only break the lock that still carries
      // the pid we judged dead (a fresh owner may have replaced it meanwhile).
      if (info !== null && !core.pidAlive(info.pid)) {
        let cur = null;
        try { cur = JSON.parse(fs.readFileSync(lockPath, 'utf8')); } catch { /* gone or corrupt */ }
        if (cur !== null && cur.pid === info.pid) {
          try { fs.unlinkSync(lockPath); } catch { /* racing */ }
        }
        continue;
      }
      // Age evidence: an empty/corrupt lock younger than CHANGELOG_LOCK_STALE_MS
      // may be mid-write by a just-started holder (open 'wx' precedes the pid
      // write) — breaking it here would let two writers hold the lock at once.
      if (mtimeStale) {
        try { fs.unlinkSync(lockPath); } catch { /* racing */ }
        continue;
      }
      if (Date.now() > deadline) {
        core.die(`changelog lock: held by live pid ${info.pid} (since ${info.started_at}) — waited ${CHANGELOG_LOCK_WAIT_MS}ms; inspect ${lockPath}`);
      }
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, CHANGELOG_LOCK_RETRY_MS);
      continue;
    }
    try {
      fs.writeSync(fd, JSON.stringify({ pid: process.pid, started_at: new Date().toISOString() }));
    } finally {
      fs.closeSync(fd);
    }
    _changelogLockOwned = true;
    process.on('exit', () => { releaseChangelogLock(); });
    return;
  }
}

// Ownership flag guards the unlink: after an intentional release a new
// process may already hold a fresh lock at the same path — never remove it.
function releaseChangelogLock() {
  if (!_changelogLockOwned) return;
  _changelogLockOwned = false;
  try { fs.unlinkSync(changelogLockPath()); } catch { /* already gone */ }
}

module.exports = {
  CATEGORY_VERBS,
  parseChangelog,
  validateEntry,
  validateStructure,
  promoteUnreleased,
  utcToday,
  changelogProjectRoot,
  validateChangelogRelPath,
  configuredChangelogRel,
  resolveChangelogMd,
  changelogLockPath,
  acquireChangelogLock,
  releaseChangelogLock,
};
