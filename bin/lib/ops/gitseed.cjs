// ops/gitseed — git workflow template masters: layered file registry, render,
// and conflict-safe seeding.
// Masters live under <repo>/templates/git and are ALWAYS resolved from
// GOS_SELF_ROOT (never cwd), so a decoy ./templates/git in the target repo
// cannot shadow the masters. Layer split:
//   universal — seeded for every repository, master-diff invariant applies;
//   node      — seeded only when the target repo has a package.json.
// Render contract: fail-closed. validateCodeowner/validateRepoSlug run BEFORE
// any substitution; illegal values throw (never sanitize-and-continue). The
// template variable budget is exactly two: {{CODEOWNER}} and {{REPO}}.
'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const core = require('../core/index.cjs');

const TEMPLATE_DIR = path.join(core.GOS_SELF_ROOT, 'templates', 'git');

// Destination path (repo-relative) -> master path (relative to TEMPLATE_DIR).
const LAYER_FILES = {
  universal: {
    '.github/ISSUE_TEMPLATE/bug_report.yml': 'ISSUE_TEMPLATE/bug_report.yml',
    '.github/ISSUE_TEMPLATE/feature_request.yml': 'ISSUE_TEMPLATE/feature_request.yml',
    '.github/ISSUE_TEMPLATE/config.yml': 'ISSUE_TEMPLATE/config.yml',
    '.github/PULL_REQUEST_TEMPLATE.md': 'PULL_REQUEST_TEMPLATE.md',
    '.github/CODEOWNERS': 'CODEOWNERS.tpl',
    'commitlint.config.yaml': 'commitlint.config.yaml',
    'CHANGELOG.md': 'CHANGELOG.md.tpl',
  },
  node: {
    '.github/workflows/ci.yml': 'node/ci.yml',
    '.github/workflows/release.yml': 'node/release.yml.tpl',
  },
};

const CODEOWNER_RE = /^@?[A-Za-z0-9][A-Za-z0-9-]*(\/[A-Za-z0-9][A-Za-z0-9-]*)?$/;
const CODEOWNER_MAX_LEN = 64;
const REPO_SLUG_RE = /^[\w.-]+\/[\w.-]+$/;
const REPO_SLUG_MAX_LEN = 100;
const PLACEHOLDER_RE = /\{\{[A-Z][A-Z0-9_]*\}\}/g;

// Validate a codeowner value; returns it on success, throws on any violation.
// Accepts `@user`, `user`, `@org/team`, `org/team` (single slash segment);
// rejects empty/non-string, multi-line, whitespace, >64 chars, and any value
// outside the pattern (including `@org/team/sub` — max one path segment).
function validateCodeowner(value) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error('invalid codeowner: must be a non-empty string');
  }
  if (/[\r\n]/.test(value)) {
    throw new Error('invalid codeowner: must be a single line');
  }
  if (/\s/.test(value)) {
    throw new Error('invalid codeowner: whitespace is not allowed');
  }
  if (value.length > CODEOWNER_MAX_LEN) {
    throw new Error(`invalid codeowner: exceeds maximum length of ${CODEOWNER_MAX_LEN} characters`);
  }
  if (!CODEOWNER_RE.test(value)) {
    throw new Error(`invalid codeowner: expected a GitHub username or org/team path like '@octocat' or '@org/team' (got: ${value})`);
  }
  return value;
}

// Validate an owner/repo slug; returns it on success, throws on any
// violation. Accepts `owner/repo` (GitHub forms); rejects empty/non-string,
// multi-line, whitespace, >100 chars, a missing or extra `/` separator, and
// a trailing `.git` (normalization strips one suffix, so a surviving suffix
// means the value never had a clean slug shape — strip-then-revalidate).
function validateRepoSlug(value) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error('invalid repo slug: must be a non-empty string');
  }
  if (/[\r\n]/.test(value)) {
    throw new Error('invalid repo slug: must be a single line');
  }
  if (/\s/.test(value)) {
    throw new Error('invalid repo slug: whitespace is not allowed');
  }
  if (value.length > REPO_SLUG_MAX_LEN) {
    throw new Error(`invalid repo slug: exceeds maximum length of ${REPO_SLUG_MAX_LEN} characters`);
  }
  if (/\.git$/.test(value)) {
    throw new Error(`invalid repo slug: must not carry a '.git' suffix (got: ${value})`);
  }
  if (!REPO_SLUG_RE.test(value)) {
    throw new Error(`invalid repo slug: expected an 'owner/repo' form like 'octocat/widget' (got: ${value})`);
  }
  return value;
}

// Infer an owner/repo slug from the origin remote of the repository at
// `root`. Only `git remote get-url origin` is consulted — upstream and other
// remotes are never read. Normalization runs BEFORE validation: strip the
// scheme, strip an ssh user, require a github.com host, strip one trailing
// `.git`, lowercase the owner; validateRepoSlug then re-checks the result,
// rejecting malformed paths (e.g. a slug still ending in `.git`). Returns
// null whenever the slug cannot be inferred — callers fail closed and demand
// an explicit value instead of guessing.
function inferRepoSlug(root) {
  let url;
  try {
    url = execFileSync('git', ['-C', root, 'remote', 'get-url', 'origin'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  } catch { return null; }
  let s = url.replace(/^[A-Za-z][A-Za-z0-9+.-]*:\/\//, '');
  s = s.replace(/^[^/@]+@/, '');
  if (s.startsWith('github.com:')) s = `github.com/${s.slice('github.com:'.length)}`;
  if (!s.startsWith('github.com/')) return null;
  s = s.slice('github.com/'.length).replace(/\/+$/, '');
  if (s.endsWith('.git')) s = s.slice(0, -'.git'.length);
  const slash = s.indexOf('/');
  if (slash <= 0 || s.indexOf('/', slash + 1) !== -1) return null;
  const slug = `${s.slice(0, slash).toLowerCase()}/${s.slice(slash + 1)}`;
  try { return validateRepoSlug(slug); } catch { return null; }
}

// Read one layer's masters and substitute {{CODEOWNER}}/{{REPO}}. Values
// must already be validated (fail-closed callers). After substitution any
// remaining {{UPPERCASE}} placeholder means the budget was exceeded — throw
// instead of emitting a partially rendered file.
function renderFiles(fileMap, codeowner, repoSlug) {
  const out = {};
  for (const [dest, masterRel] of Object.entries(fileMap)) {
    let content = fs.readFileSync(path.join(TEMPLATE_DIR, masterRel), 'utf8');
    if (content.includes('{{CODEOWNER}}')) {
      content = content.split('{{CODEOWNER}}').join(codeowner);
    }
    if (content.includes('{{REPO}}')) {
      content = content.split('{{REPO}}').join(repoSlug);
    }
    const leftover = content.match(PLACEHOLDER_RE);
    if (leftover) {
      throw new Error(`template variable budget exceeded: unresolved placeholder ${leftover[0]} in ${masterRel} (only {{CODEOWNER}} and {{REPO}} are defined)`);
    }
    out[dest] = content;
  }
  return out;
}

// Render ALL layers: { repoRelativePath -> content }. Validates both
// variables first (fail-closed); illegal values prevent any file from being
// produced.
function render(variables) {
  const vars = variables && typeof variables === 'object' ? variables : {};
  const codeowner = validateCodeowner(vars.codeowner);
  const repoSlug = validateRepoSlug(vars.repo);
  return {
    ...renderFiles(LAYER_FILES.universal, codeowner, repoSlug),
    ...renderFiles(LAYER_FILES.node, codeowner, repoSlug),
  };
}

// Render a single layer: 'universal' | 'node' (used by conditional seeding).
function renderLayer(layer, variables) {
  const fileMap = LAYER_FILES[layer];
  if (!fileMap) {
    throw new Error(`unknown git-seed layer '${layer}' (expected 'universal' or 'node')`);
  }
  const vars = variables && typeof variables === 'object' ? variables : {};
  const codeowner = validateCodeowner(vars.codeowner);
  const repoSlug = validateRepoSlug(vars.repo);
  return renderFiles(fileMap, codeowner, repoSlug);
}

// ---- seeding (conflict safety bundle) ----

// Fixed codeowner for rendering the template bundle into this repository
// itself (self-render mode / CI master-consistency check).
const SELF_CODEOWNER = '@chenw521';

// Self-repo slug for the config.yml Discussions URL in self-render mode —
// always passed explicitly, never inferred from a remote.
const SELF_REPO_SLUG = 'chenw521/GOS';

// Inactivity timeout for the interactive conflict prompt: silence never
// overwrites a user file — the answer falls back to 'keep'.
const ASK_TIMEOUT_MS = 30000;

// Built-in per-file conflict prompt. Mirrors core ask() semantics: non-TTY
// resolves 'keep' immediately (pipe/stdin-closed environments never prompt);
// a TTY waits for one answer line, bounded by the inactivity timeout. Prompts
// go to stderr so stdout stays machine-clean for --json reports.
function askConflict(destRel, timeoutMs) {
  return new Promise((resolve) => {
    const stdin = process.stdin;
    if (!stdin.isTTY) { resolve('keep'); return; }
    process.stderr.write(`overwrite ${destRel}? [y/N] `);
    let settled = false;
    const finish = (v) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      stdin.pause();
      stdin.off('data', onData);
      stdin.off('end', onHangup);
      stdin.off('close', onHangup);
      stdin.off('error', onHangup);
      resolve(v);
    };
    const onData = (d) => {
      const s = String(d).trim().toLowerCase();
      finish(s === 'y' || s === 'yes' ? 'overwrite' : 'keep');
    };
    const onHangup = () => finish('keep');
    const timer = setTimeout(() => finish('keep'), timeoutMs || ASK_TIMEOUT_MS);
    stdin.setEncoding('utf8');
    stdin.resume();
    stdin.on('data', onData);
    stdin.on('end', onHangup);
    stdin.on('close', onHangup);
    stdin.on('error', onHangup);
  });
}

// Seed rendered templates into a target repository root. Conflict policy:
//   missing file            -> create
//   existing identical file -> keep (re-run friendly, no prompt, no backup)
//   directory at the path   -> keep (never seed over a directory)
//   unreadable file         -> keep (fail-closed, no overwrite attempt)
//   conflicting file        -> overwrite ONLY via --overwrite or an explicit
//                              interactive 'y'; every overwrite first writes
//                              <file>.gos-bak, then renames the new content
//                              into place (a symlink dest is replaced as an
//                              entry — refuse passthrough).
// neverOverwrite (array of repo-relative dest paths) draws a hard line ABOVE
// the conflict ladder: a listed dest that conflicts is ALWAYS kept — the
// doOverwrite decision (flag or ask) is never even consulted for it. This is
// the brownfield-adoption guard for files whose live content is authoritative
// (e.g. an adopted repo's own README).
// All file writes (create, .gos-bak, overwrite) go through
// core.writeAtomicText — temp file + fsync + rename — so a reader (or a
// concurrent seed of the same dest) never observes a torn or empty file; the
// rename replaces a symlink dest atomically (refuse passthrough without the
// missing-file window of the old unlink+recreate).
// opts: { root, codeowner, repo | files, overwrite, nonInteractive, ask, askTimeoutMs, neverOverwrite }
// Returns { created, skipped, overwritten, skippedDetail } — skippedDetail is
// a parallel array of { dest, reason } aligned with skipped by index, with
// reason from the closed set:
//   identical | conflict-kept | never | directory | unreadable
// (consumed by the brownfield command's five-state file vocabulary).
// Nothing is ever staged — `git add` stays a user act.
async function seed(opts) {
  const o = opts && typeof opts === 'object' ? opts : {};
  const root = o.root;
  if (!root || typeof root !== 'string') {
    throw new Error('seed: root (git toplevel) is required');
  }
  const neverList = o.neverOverwrite === undefined ? [] : o.neverOverwrite;
  if (!Array.isArray(neverList) || neverList.some((p) => typeof p !== 'string')) {
    throw new Error('seed: neverOverwrite must be an array of destination paths');
  }
  const never = new Set(neverList);
  let files;
  if (o.files && typeof o.files === 'object') {
    files = o.files;
  } else {
    const codeowner = validateCodeowner(o.codeowner);
    const repoSlug = validateRepoSlug(o.repo);
    files = renderFiles(LAYER_FILES.universal, codeowner, repoSlug);
    if (fs.existsSync(path.join(root, 'package.json'))) {
      Object.assign(files, renderFiles(LAYER_FILES.node, codeowner, repoSlug));
    }
  }
  const ask = typeof o.ask === 'function' ? o.ask : askConflict;
  const created = [];
  const skipped = [];
  const skippedDetail = [];
  const overwritten = [];
  const skip = (dest, reason) => { skipped.push(dest); skippedDetail.push({ dest, reason }); };
  for (const dest of Object.keys(files).sort()) {
    const content = files[dest];
    const abs = path.join(root, dest);
    let st = null;
    try { st = fs.lstatSync(abs); } catch { st = null; }
    if (!st) {
      core.writeAtomicText(abs, content);
      created.push(dest);
      continue;
    }
    if (st.isDirectory()) { skip(dest, 'directory'); continue; }
    let existing;
    try { existing = fs.readFileSync(abs); } catch { skip(dest, 'unreadable'); continue; }
    if (Buffer.compare(existing, Buffer.from(content, 'utf8')) === 0) { skip(dest, 'identical'); continue; }
    if (never.has(dest)) { skip(dest, 'never'); continue; }
    let doOverwrite = o.overwrite === true;
    if (!doOverwrite) {
      if (o.nonInteractive === true) doOverwrite = false;
      else doOverwrite = (await ask(dest, o.askTimeoutMs)) === 'overwrite';
    }
    if (!doOverwrite) { skip(dest, 'conflict-kept'); continue; }
    core.writeAtomicText(`${abs}.gos-bak`, existing);
    core.writeAtomicText(abs, content);
    overwritten.push(dest);
  }
  return { created, skipped, overwritten, skippedDetail };
}

// Render the universal layer with self-repo arguments. Single entry point for
// master-consistency checking (re-render and diff against the repo); the node
// layer is exempt — this repo's CI is maintained as its own file, never from
// the node masters.
// Files the self-render must never overwrite once they exist: CHANGELOG.md
// accumulates entries via `gos changelog add`, and config.yml carries the
// repo-specific Discussions URL (placeholder in the master) — both are
// bootstrap-only; re-rendering over them would erase live data.
const SELF_BOOTSTRAP_ONLY = ['CHANGELOG.md', '.github/ISSUE_TEMPLATE/config.yml'];

function renderSelf() {
  const files = renderFiles(LAYER_FILES.universal, SELF_CODEOWNER, SELF_REPO_SLUG);
  for (const rel of SELF_BOOTSTRAP_ONLY) {
    if (fs.existsSync(path.join(core.GOS_SELF_ROOT, rel))) delete files[rel];
  }
  return files;
}

module.exports = { render, renderLayer, validateCodeowner, validateRepoSlug, inferRepoSlug, seed, renderSelf, SELF_CODEOWNER, SELF_REPO_SLUG };
