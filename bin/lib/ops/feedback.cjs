// ops/feedback — `gos feedback` command family: local draft store +
// gh-backed publication (network-dependency truth rule: suite tests run
// against test/fixtures/gh-stub/gh; real gh only under GOS_E2E_NETWORK=1).
//
// Draft store (.gos/project/feedback/, GOS_PATHS key `feedback`,
// tracked:false + gitignored): one markdown file per entry
// FB-<N>-<type>.md with a `---` front header (id/type/title/created/state
// plus close/push fields) and a free-form body. Closed files stay on disk —
// ids are allocated max+1 across ALL files so a tombstone always occupies
// its number (never reused). All local mutations run under the dispatch
// write lock (feedback is write-class; guardCwd serializes add/close/push).
//
// push: target = --to (validated) or the project's origin (github.com only,
// gitseed inferRepoSlug contract — upstream is never consulted). Pre-flight
// `gh repo view <slug> --json owner,viewerPermission,visibility` +
// `gh api user --jq .login`; when the repo owner ≠ the authenticated user
// an implicit-origin push is refused (headless: guidance to pass --to;
// interactive: y/N after printing destination+visibility), while an
// explicit --to prints destination+visibility for the record and proceeds.
// Idempotency: every published body embeds `<!-- GOS-FB-<id>@<slug> -->`;
// before creating, `gh search issues --repo <slug> <marker> --json url` —
// a hit adopts the URL with no create (discussions ride the same issues
// search: the GraphQL discussion search is not worth a second code path,
// and v1 creates both types via `gh issue create`). The sending intent
// (state:sending + target slug) is written BEFORE spawning the create, so
// a crash mid-push leaves a recoverable, re-detectable entry. Success
// backfills state published + url and appends ONE row to the tracked
// ledger .gos/FEEDBACK.md — the only feedback data renderPathsMarkdown
// ever consumes (drafts have zero tracked footprint).
//
// Subprocess discipline: every gh/git invocation is execFileSync with an
// ARGV ARRAY — titles/bodies never touch a shell string.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const core = require('../core/index.cjs');
const gitseed = require('./gitseed.cjs');

const FEEDBACK_TYPES = ['issue', 'discussion'];
const ENTRY_NAME_RE = /^FB-(\d+)-(issue|discussion)\.md$/;
const LEDGER_HEADER = [
  '<!-- GENERATED ledger — rows are appended by `gos feedback push`; drafts live untracked under .gos/project/feedback/ and never render -->',
  '# Feedback Ledger (published)',
  '',
  '| ID | Type | Title | URL |',
  '|:--|:--|:--|:--|',
  '',
].join('\n');

function feedbackDir() {
  return core.resolvePath('feedback');
}

function entryFiles() {
  try {
    return fs.readdirSync(feedbackDir())
      .filter((f) => ENTRY_NAME_RE.test(f))
      .sort((a, b) => parseInt(a.match(/^FB-(\d+)-/)[1], 10) - parseInt(b.match(/^FB-(\d+)-/)[1], 10));
  } catch { return []; }
}

function nextFeedbackId() {
  let max = 0;
  for (const f of entryFiles()) {
    const m = f.match(/^FB-(\d+)-/);
    if (m) max = Math.max(max, parseInt(m[1], 10));
  }
  return max + 1;
}

function entryFileFor(n) {
  return entryFiles().find((f) => f.startsWith(`FB-${n}-`)) || null;
}

function parseEntryText(text) {
  const lines = String(text).split(/\r?\n/);
  if (lines[0] !== '---') return null;
  const end = lines.indexOf('---', 1);
  if (end === -1) return null;
  const fields = {};
  for (const l of lines.slice(1, end)) {
    const i = l.indexOf(': ');
    if (i > 0) fields[l.slice(0, i)] = l.slice(i + 2);
  }
  return { fields, body: lines.slice(end + 1).join('\n') };
}

function serializeEntry(entry) {
  const order = ['id', 'type', 'title', 'created', 'state', 'resolution', 'target', 'marker', 'url'];
  const lines = ['---'];
  for (const k of order) {
    if (entry.fields[k] != null && entry.fields[k] !== '') lines.push(`${k}: ${entry.fields[k]}`);
  }
  lines.push('---');
  lines.push(entry.body);
  return lines.join('\n').replace(/\n*$/, '\n');
}

function loadEntryOrDie(n) {
  const name = entryFileFor(n);
  if (!name) core.die(`feedback: FB-${n} not found — list entries: gos feedback list`);
  const file = path.join(feedbackDir(), name);
  let entry;
  try {
    entry = parseEntryText(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    core.die(`feedback: FB-${n} unreadable (${e.message})`);
  }
  if (!entry || !entry.fields.id) core.die(`feedback: FB-${n} has a corrupt front header — restore it or delete the file`);
  entry.file = file;
  return entry;
}

function takeFlagValue(rest, name) {
  const out = { value: null, rest: [] };
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === name) {
      const v = rest[i + 1];
      if (v == null || v.startsWith('--')) core.die(`feedback: ${name} requires a value`);
      out.value = v;
      i += 1;
      continue;
    }
    out.rest.push(rest[i]);
  }
  return out;
}

function cmdFeedback(args) {
  const sub = String((args || [])[0] || '').toLowerCase();
  const rest = (args || []).slice(1);
  if (sub === 'add') { cmdFeedbackAdd(rest); return; }
  if (sub === 'list') { cmdFeedbackList(rest); return; }
  if (sub === 'close') { cmdFeedbackClose(rest); return; }
  if (sub === 'push') {
    cmdFeedbackPush(rest).catch((e) => core.die(`feedback push: ${e && e.message ? e.message : e}`));
    return;
  }
  core.die('Usage: gos feedback add issue|discussion "<title>" [--body "<text>"] | gos feedback list [--type <issue|discussion>] [--status <open|closed>] | gos feedback close <N> --resolution "<text>" | gos feedback push <N> [--to owner/repo]');
}

function cmdFeedbackAdd(rest) {
  const type = String(rest[0] || '').toLowerCase();
  if (!FEEDBACK_TYPES.includes(type)) {
    core.die(`feedback add: type must be issue or discussion (got '${type || '<none>'}')`);
  }
  const title = core.sanitizeSingleLine(rest[1]);
  if (!title) core.die('feedback add: a non-empty "<title>" is required');
  const bodyFlag = takeFlagValue(rest.slice(2), '--body');
  if (bodyFlag.rest.length) core.die(`feedback add: unknown argument '${bodyFlag.rest[0]}' (flags: --body)`);
  const n = nextFeedbackId();
  const entry = {
    fields: { id: `FB-${n}`, type, title, created: new Date().toISOString(), state: 'open' },
    body: typeof bodyFlag.value === 'string' ? bodyFlag.value : '',
  };
  const file = path.join(feedbackDir(), `FB-${n}-${type}.md`);
  core.writeAtomicText(file, serializeEntry(entry));
  console.log(`${core.CONTRACTS.command_contracts.feedbackAdded}${n} added (${type}): ${title}`);
  console.log(`  draft (untracked): ${path.relative(process.cwd(), file)} — publish with: gos feedback push ${n}`);
}

function cmdFeedbackList(rest) {
  const typeFlag = takeFlagValue(rest, '--type');
  const statusFlag = takeFlagValue(typeFlag.rest, '--status');
  if (statusFlag.rest.length) core.die(`feedback list: unknown argument '${statusFlag.rest[0]}' (flags: --type, --status)`);
  if (typeFlag.value != null && !FEEDBACK_TYPES.includes(typeFlag.value.toLowerCase())) {
    core.die(`feedback list: --type must be issue or discussion (got '${typeFlag.value}')`);
  }
  const rows = [];
  for (const f of entryFiles()) {
    const n = parseInt(f.match(/^FB-(\d+)-/)[1], 10);
    const entry = loadEntryOrDie(n);
    const fl = entry.fields;
    if (typeFlag.value != null && fl.type !== typeFlag.value.toLowerCase()) continue;
    if (statusFlag.value != null && fl.state !== statusFlag.value.toLowerCase()) continue;
    const status = fl.state === 'published' && fl.url ? `published ${fl.url}` : fl.state;
    rows.push(`${String(fl.id).padEnd(6)} ${String(fl.type).padEnd(11)} ${String(status).padEnd(11)} ${fl.title}`);
  }
  if (!rows.length) {
    console.log('(no feedback entries match — add one: gos feedback add issue "<title>")');
    return;
  }
  console.log(`${'ID'.padEnd(6)} ${'Type'.padEnd(11)} ${'Status'.padEnd(11)} Title`);
  for (const r of rows) console.log(r);
}

function cmdFeedbackClose(rest) {
  const n = parseInt(String(rest[0] || ''), 10);
  if (!Number.isInteger(n) || n <= 0) core.die('feedback close: a numeric <N> is required');
  const resFlag = takeFlagValue(rest.slice(1), '--resolution');
  if (resFlag.rest.length) core.die(`feedback close: unknown argument '${resFlag.rest[0]}' (flags: --resolution)`);
  const resolution = core.sanitizeSingleLine(resFlag.value);
  if (!resolution) core.die('feedback close: --resolution "<text>" is required');
  const entry = loadEntryOrDie(n);
  if (entry.fields.state === 'closed') {
    core.die(`feedback close: FB-${n} is already closed (resolution: ${entry.fields.resolution || '<none>'})`);
  }
  entry.fields.state = 'closed';
  entry.fields.resolution = resolution;
  core.writeAtomicText(entry.file, serializeEntry(entry));
  console.log(`${core.CONTRACTS.command_contracts.feedbackAdded}${n}${core.CONTRACTS.command_contracts.feedbackClosed}${resolution}`);
}

// gh subprocess wrapper — argv arrays only. gh missing from
// PATH is a clean pre-flight death (the entry file is still untouched);
// command-level failures throw so callers can layer recovery guidance.
function ghRunOrDie(argv) {
  let out;
  try {
    // 30s cap per gh call — a hung network path must never wedge the
    // process (the CLI lock is released before push spawns gh, but the
    // command itself should still terminate).
    out = execFileSync('gh', argv, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000 });
  } catch (e) {
    if (e.code === 'ENOENT') {
      core.die(`✗ feedback push: ${core.CONTRACTS.command_contracts.feedbackGhMissing} — install the GitHub CLI (https://cli.github.com/), entry left untouched`);
    }
    if (e.killed || e.signal === 'SIGTERM') {
      core.die(`feedback push: gh ${argv.slice(0, 2).join(' ')} timed out after 30s — check network/proxy; entry left in its current state`);
    }
    const tail = core.sanitizeEcho(String(e.stderr || e.message || 'gh failed'));
    throw new Error(`gh ${argv.slice(0, 2).join(' ')} failed: ${tail}`);
  }
  return out;
}

async function cmdFeedbackPush(rest) {
  const T = core.CONTRACTS.command_contracts;
  const n = parseInt(String(rest[0] || ''), 10);
  if (!Number.isInteger(n) || n <= 0) core.die('feedback push: a numeric <N> is required');
  const toFlag = takeFlagValue(rest.slice(1), '--to');
  if (toFlag.rest.length) core.die(`feedback push: unknown argument '${toFlag.rest[0]}' (flags: --to)`);
  // Release the CLI lock before any network/interactive work: push may spend
  // minutes in gh calls and prompts (gate B-19 precedent — locks never span
  // user scripts/network). Entry mutations stay atomic via writeAtomicText.
  try { core.releaseLock(); } catch { /* not held — fine */ }
  const entry = loadEntryOrDie(n);
  if (entry.fields.state === 'published' && entry.fields.url) {
    console.log(`✓ Feedback FB-${n} already published: ${entry.fields.url}`);
    return;
  }
  let slug = null;
  if (toFlag.value != null) {
    try {
      slug = gitseed.validateRepoSlug(toFlag.value);
    } catch (e) {
      core.die(`feedback push: invalid --to value — ${e.message}`);
    }
  } else {
    const root = core.currentRootRealpath() || process.cwd();
    slug = gitseed.inferRepoSlug(root);
    if (!slug) {
      core.die('feedback push: no usable target — the origin remote is missing or not a github.com repo; pass --to owner/repo explicitly');
    }
  }

  let repoView;
  let viewer;
  try {
    repoView = JSON.parse(ghRunOrDie(['repo', 'view', slug, '--json', 'owner,viewerPermission,visibility']));
    viewer = String(ghRunOrDie(['api', 'user', '--jq', '.login'])).trim();
  } catch (e) {
    core.die(`feedback push: pre-flight failed — ${e.message}`);
  }
  const owner = repoView && repoView.owner && repoView.owner.login;
  if (!owner) core.die(`feedback push: gh repo view returned no owner for ${slug}`);
  const targetLine = `target ${slug} (visibility: ${repoView.visibility || 'unknown'}, permission: ${repoView.viewerPermission || 'unknown'})`;
  console.log(targetLine);
  if (owner !== viewer) {
    if (toFlag.value == null) {
      if (core.isHeadlessEnv()) {
        core.die(`${T.feedbackOwnerRefuse} ${owner} ≠ authenticated gh user ${viewer} — implicit origin pushes only target repos you own; pass --to ${slug} to confirm this destination explicitly`);
      }
      const ans = await core.ask(`Proceed to push to ${slug}? [y/N] `);
      if (typeof ans !== 'string' || !['y', 'yes'].includes(ans.toLowerCase())) {
        core.die('feedback push: declined — entry untouched');
      }
    } else {
      console.log(`note: explicit --to to a repo owned by ${owner}, not by you (${viewer}) — proceeding as instructed`);
    }
  }

  const marker = `<!-- GOS-FB-${n}@${slug} -->`;
  let hits = [];
  try {
    hits = JSON.parse(ghRunOrDie(['search', 'issues', '--repo', slug, marker, '--json', 'url']) || '[]');
  } catch (e) {
    core.die(`feedback push: idempotent search failed — ${e.message}`);
  }
  if (Array.isArray(hits) && hits.length && hits[0] && hits[0].url) {
    finalizePublished(entry, n, String(hits[0].url), marker);
    console.log(`✓ Feedback FB-${n} already published — adopted existing URL: ${hits[0].url}`);
    return;
  }

  entry.fields.state = 'sending';
  entry.fields.target = slug;
  entry.fields.marker = marker;
  core.writeAtomicText(entry.file, serializeEntry(entry));
  const body = [String(entry.body || '').trim(), marker].filter(Boolean).join('\n\n');
  let url;
  try {
    url = String(ghRunOrDie(['issue', 'create', '--repo', slug, '--title', entry.fields.title, '--body', body])).trim();
  } catch (e) {
    core.die(`✗ Feedback FB-${n}: push failed after the sending intent was recorded (${e.message}) — the issue MAY already exist on GitHub. Re-run gos feedback push ${n}: the idempotent search adopts an existing issue instead of creating a duplicate (entry kept, nothing was rolled back)`);
  }
  finalizePublished(entry, n, url, marker);
  console.log(`✓ Feedback FB-${n}${T.feedbackPublished}${url}`);
}

function finalizePublished(entry, n, url, marker) {
  entry.fields.state = 'published';
  entry.fields.marker = marker;
  entry.fields.url = url;
  core.writeAtomicText(entry.file, serializeEntry(entry));
  appendLedgerRow(entry);
  console.log(`  ledger row appended: ${path.relative(process.cwd(), core.resolvePath('feedback_ledger'))}`);
}

function appendLedgerRow(entry) {
  const ledger = core.resolvePath('feedback_ledger');
  const row = `| ${entry.fields.id} | ${entry.fields.type} | ${core.escCellMd(entry.fields.title)} | ${entry.fields.url} |`;
  if (!fs.existsSync(ledger)) {
    core.writeAtomicText(ledger, LEDGER_HEADER + row + '\n');
    return;
  }
  fs.appendFileSync(ledger, row + '\n');
}

module.exports = { cmdFeedback };
