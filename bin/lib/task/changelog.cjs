// task/changelog — `gos changelog` command family: the single-track
// CHANGELOG.md writer plus its structure linter.
//
// `add` is a template-instantiated entry generator, never free text. The
// generated bullet contract (enforced by ops/changelog-core.validateEntry,
// consumed same-source so generator and linter can never drift):
//   `- <CategoryVerb> <one-sentence user summary> (<D-nn/R-nn refs>) [YYYY-MM-DD]`
// Deterministic defaults:
//   - CategoryVerb: --type value, else 'Add'; must be one of
//     changelog-core.CATEGORY_VERBS (fail-closed, full list on miss).
//   - user summary: --summary arg > task-scoped state.json cache
//     (changelog_user_summary) > interactive TTY ask; none available and
//     non-TTY/headless → refuse (no silent fallback). First successful value
//     is cached task-scoped in state.json.
//   - trace refs: --refs "D-nn,R-nn" override, else derived from the active
//     task = covered decisions then active requirements (state order),
//     '/'-joined; empty derivation → refuse (fail-closed).
//   - date stamp: changelog-core.utcToday() — the single UTC time source.
// Write safety: a missing CHANGELOG.md bootstraps from
// templates/git/CHANGELOG.md.tpl resolved off GOS_SELF_ROOT (a decoy
// ./templates in the target repo cannot shadow the master); the
// CHANGELOG.md + state.json read-modify-write runs under a dedicated O_EXCL
// lockfile (.gos/cache/changelog.lock) with bounded wait-retry so concurrent
// adds serialize instead of dying or losing entries; file replacement is
// temp-write + atomic rename. The family is read-class at dispatch level and
// mutates under its own internal lock (the concerns pattern — the shared
// .gos/.lock is die-on-contention and must not gate concurrent adds).
// .changes.md is sealed read-only history: this module never touches it.
// `lint` is the post-hoc enforcement sweep — read-only, no lock, exits 1
// listing every violation individually (English).
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const core = require('../core/index.cjs');
const clcore = require('../ops/changelog-core.cjs');

const CHANGELOG_MD = path.resolve('CHANGELOG.md');
const CHANGELOG_LOCK = path.join(core.GOS_DIR, 'cache', 'changelog.lock');
const TEMPLATE_MASTER = path.join(core.GOS_SELF_ROOT, 'templates', 'git', 'CHANGELOG.md.tpl');
const LOCK_WAIT_MS = 15000;
const LOCK_RETRY_MS = 50;
const LOCK_STALE_MS = 120000;

let lockOwned = false;

function cmdChangelog(args) {
  const sub = String((args || [])[0] || '').toLowerCase();
  if (sub === 'add') {
    cmdChangelogAdd((args || []).slice(1)).catch((e) => {
      core.die(`changelog add: ${e && e.message ? e.message : e}`);
    });
    return;
  }
  if (sub === 'lint') {
    cmdChangelogLint();
    return;
  }
  core.die('Usage: gos changelog add [--summary "<one sentence>"] [--type <verb>] [--refs "D-nn,R-nn"] | gos changelog lint');
}

// Fail-closed order: active-state gate → summary resolution (arg > cache >
// TTY ask; exhausted non-TTY → refuse) → verb/refs contract → shared
// validator → bootstrap/insert under the changelog lock. The TTY ask runs
// BEFORE the lock is taken: waiting on a human while holding the write lock
// would block every other add for the whole prompt duration.
async function cmdChangelogAdd(rest) {
  const opts = parseAddArgs(rest);

  core.readState._mode = 'write';
  const st = core.readState();
  if (!st) core.die(`${core.CONTRACTS.state_semantics.noActiveTask} \`gos init\` first.`);

  let summary = null;
  if (typeof opts.summary === 'string' && opts.summary.trim()) {
    summary = opts.summary.trim();
  } else if (typeof st.changelog_user_summary === 'string' && st.changelog_user_summary.trim()) {
    summary = st.changelog_user_summary.trim();
  } else if (!core.isHeadlessEnv() && process.stdin.isTTY) {
    console.log('changelog add: no --summary and no cached summary for this task.');
    const ans = await core.ask('One-sentence user-facing summary of this task: ');
    if (typeof ans === 'string' && ans.trim()) summary = ans.trim();
  }
  if (summary == null) {
    core.die('changelog add: no user summary available — pass --summary "<one sentence>" or run once from an interactive terminal to cache it for this task (non-interactive has no fallback)');
  }

  // If the summary already opens with a category verb, do not stack another
  // one on top ("Add Fix ..." reads as a duplication artifact). A Conventional
  // Commits token (e.g. "feat:" / "fix(ops):") passes through verbatim so the
  // bullet derives a well-formed aggregate subject at push time.
  let verb = opts.type || null;
  const conventional = typeof verb === 'string' && /^(feat|fix|docs|refactor|test|chore|ci|build|perf|revert)(\([a-z0-9-]+\))?:$/.test(verb);
  if (!verb) {
    const first = String(summary).split(/\s+/)[0];
    verb = clcore.CATEGORY_VERBS.includes(first) ? '' : 'Add';
  }
  if (verb && !conventional && !clcore.CATEGORY_VERBS.includes(verb)) {
    core.die(`changelog add: --type '${verb}' is not a category verb or conventional token (feat:|fix(ops):…) — allowed verbs: ${clcore.CATEGORY_VERBS.join(', ')}`);
  }
  const refsArg = opts.refs ? parseRefsArg(opts.refs) : null;

  acquireChangelogLock();
  try {
    const st2 = core.readState();
    if (!st2) core.die(`${core.CONTRACTS.state_semantics.noActiveTask} \`gos init\` first.`);
    const derived = refsArg ? { refs: refsArg } : deriveTraceRefs(st2);
    if (derived.tooBroad) {
      core.die(`changelog add: ${derived.refs.length}+ trace refs derivable (too broad for one entry) — pass --refs "D-nn,R-nn" (max 4) naming the refs this change actually belongs to`);
    }
    const refs = derived.refs;
    if (!refs.length) {
      core.die('changelog add: no trace refs derivable from the active task (no covered decisions, no active requirements) — pass --refs "D-nn,R-nn" explicitly');
    }
    const entry = `- ${[verb, summary].filter(Boolean).join(' ')} (${refs.join('/')}) [${clcore.utcToday()}]`;
    const verdict = clcore.validateEntry(entry);
    if (!verdict.ok) {
      console.error('✗ changelog add: generated entry rejected by the shared validator — rewrite the summary:');
      for (const e of verdict.errors) console.error(`  ✗ ${e}`);
      process.exit(1);
    }

    let text;
    let bootstrapped = false;
    try {
      text = fs.readFileSync(CHANGELOG_MD, 'utf8');
    } catch {
      text = loadChangelogSkeleton();
      bootstrapped = true;
    }
    const parsed = clcore.parseChangelog(text);
    if (!parsed.hasHeader) {
      core.die(`changelog add: CHANGELOG.md lacks a top-level '# ' title — restore the Keep a Changelog header or delete the file so add can bootstrap it (master: ${path.relative(core.GOS_SELF_ROOT, TEMPLATE_MASTER)})`);
    }
    if (!parsed.hasUnreleasedHeading) {
      core.die("changelog add: CHANGELOG.md has no '## [Unreleased]' section — add the heading (Keep a Changelog skeleton) or delete the file so add can bootstrap it");
    }
    const ins = insertUnreleasedTop(text, entry);
    if (!ins.ok) core.die(`changelog add: cannot insert entry — ${ins.reason}`);
    core.writeAtomicText(CHANGELOG_MD, ins.text);
    if (bootstrapped) console.log('✓ bootstrapped CHANGELOG.md from the Keep a Changelog master template');
    if (st2.changelog_user_summary !== summary) {
      st2.changelog_user_summary = summary;
      core.writeState(st2);
    }
    console.log('✓ changelog entry written to CHANGELOG.md [Unreleased]:');
    console.log(`  ${entry}`);
  } finally {
    releaseChangelogLock();
  }
}

// Post-hoc enforcement over CHANGELOG.md using the same changelog-core
// validators the add generator pre-writes with — one validator, zero drift.
// Zone discriminant: [Unreleased] is the add-generated zone, so every entry
// gets full validateEntry; versioned sections are promote products plus
// hand-written history, so they get the structural three-checks only and are
// never entry-validated. A missing file is an advisory, not a failure —
// obligations start once the file exists, and the next `add` bootstraps it.
// Without an active task state (state.json is gitignored, so CI and audit
// contexts have none) the today-obligation check downgrades to an advisory;
// every other check stays hard.
function cmdChangelogLint() {
  let text;
  try {
    text = fs.readFileSync(CHANGELOG_MD, 'utf8');
  } catch {
    console.log("⚠ changelog lint: CHANGELOG.md not found — obligations start once the file exists; the next 'gos changelog add' bootstraps it from the Keep a Changelog master template (advisory, not blocking)");
    process.exit(0);
  }

  const hasState = !!core.readState();
  const violations = [];
  const advisories = [];

  for (const err of clcore.validateStructure(text).errors) {
    if (!hasState && err.startsWith("structure: today's obligation")) {
      advisories.push(`${err} — downgraded to advisory (no .gos/state.json, CI or audit context)`);
    } else {
      violations.push(err);
    }
  }

  const parsed = clcore.parseChangelog(text);
  const lineOfFirst = new Map();
  text.split(/\r?\n/).forEach((l, i) => {
    const m = l.match(/^[ \t]*-[ \t]+(\S.*)$/);
    if (!m) return;
    const norm = `- ${m[1].trim()}`;
    if (!lineOfFirst.has(norm)) lineOfFirst.set(norm, i + 1);
  });
  for (const entry of parsed.unreleased) {
    const verdict = clcore.validateEntry(entry);
    if (verdict.ok) continue;
    const at = lineOfFirst.get(entry);
    const loc = at ? `CHANGELOG.md:${at}` : 'CHANGELOG.md';
    for (const e of verdict.errors) violations.push(`${loc}: [Unreleased] entry '${entry}' — ${e}`);
  }

  if (violations.length) {
    console.error(`✗ changelog lint: ${violations.length} violation(s) in CHANGELOG.md:`);
    for (const v of violations) console.error(`  ✗ ${v}`);
    process.exit(1);
  }
  for (const a of advisories) console.log(`⚠ changelog lint: ${a}`);
  const n = parsed.unreleased.length;
  console.log(`✓ changelog lint: CHANGELOG.md clean — structural three-checks pass, ${n} [Unreleased] ${n === 1 ? 'entry' : 'entries'} validated, ${parsed.versions.length} version section(s) checked structurally`);
  process.exit(0);
}

function parseAddArgs(rest) {
  const out = { summary: null, type: null, refs: null };
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (a !== '--summary' && a !== '--type' && a !== '--refs') {
      core.die(`changelog add: unknown argument '${a}' (flags: --summary, --type, --refs)`);
    }
    const v = rest[++i];
    if (v == null || v.startsWith('--')) {
      const hint = a === '--summary' ? '"<one sentence>"'
        : a === '--type' ? '<category verb like Add, Fix, ...>'
          : '"D-42,R-05"';
      core.die(`changelog add: ${a} requires a value — ${hint}`);
    }
    if (a === '--summary') out.summary = v;
    else if (a === '--type') out.type = v;
    else out.refs = v;
  }
  return out;
}

function parseRefsArg(raw) {
  const refs = [];
  for (const tok of String(raw).split(/[,/\s]+/).filter(Boolean)) {
    if (!/^[DR]-\d+$/.test(tok)) {
      core.die(`changelog add: --refs token '${tok}' is malformed — only D-nn/R-nn tokens separated by ',' or '/' are allowed`);
    }
    if (!refs.includes(tok)) refs.push(tok);
  }
  if (!refs.length) core.die('changelog add: --refs is empty — pass tokens like "D-42,R-05"');
  return refs;
}

// Covered decisions first, then active requirements, in state order; both
// id shapes are re-checked so a hand-edited state cannot smuggle garbage
// into the generated parenthetical.
function deriveTraceRefs(stateL) {
  const refs = [];
  const push = (id) => {
    if (/^[DR]-\d+$/.test(String(id)) && !refs.includes(id)) refs.push(id);
  };
  for (const d of stateL.decisions || []) {
    if (d && d.id && d.status === 'covered') push(d.id);
  }
  for (const r of stateL.requirements || []) {
    if (r && r.id && (r.status || 'active') === 'active') push(r.id);
  }
  // A derived ref list that spans the whole registry (12 decisions + 20
  // requirements) is noise, not traceability — cap it and demand an explicit
  // --refs when the task's surface is too broad to summarize.
  if (refs.length > 4) return { tooBroad: true, refs: refs.slice(0, 4) };
  return { refs };
}

// O_EXCL acquire with bounded wait: a live holder is waited out (concurrent
// adds serialize), a dead-pid / stale-heartbeat / corrupt holder is broken.
function acquireChangelogLock() {
  fs.mkdirSync(path.dirname(CHANGELOG_LOCK), { recursive: true });
  const deadline = Date.now() + LOCK_WAIT_MS;
  for (;;) {
    let fd = null;
    try {
      fd = fs.openSync(CHANGELOG_LOCK, 'wx');
    } catch (e) {
      if (e.code !== 'EEXIST') core.die(`changelog lock: open failed (${e.message})`);
      let info = null;
      try { info = JSON.parse(fs.readFileSync(CHANGELOG_LOCK, 'utf8')); } catch { /* empty or corrupt */ }
      let mtimeStale = false;
      try { mtimeStale = Date.now() - fs.statSync(CHANGELOG_LOCK).mtimeMs > LOCK_STALE_MS; } catch { mtimeStale = false; }
      // Dead-owner evidence: re-read and only break the lock that still carries
      // the pid we judged dead (a fresh owner may have replaced it meanwhile).
      if (info !== null && !core.pidAlive(info.pid)) {
        let cur = null;
        try { cur = JSON.parse(fs.readFileSync(CHANGELOG_LOCK, 'utf8')); } catch { /* gone or corrupt */ }
        if (cur !== null && cur.pid === info.pid) {
          try { fs.unlinkSync(CHANGELOG_LOCK); } catch { /* racing */ }
        }
        continue;
      }
      // Age evidence: an empty/corrupt lock younger than LOCK_STALE_MS may be
      // mid-write by a just-started holder (open 'wx' precedes the pid write) —
      // breaking it here would let two writers hold the lock at once.
      if (mtimeStale) {
        try { fs.unlinkSync(CHANGELOG_LOCK); } catch { /* racing */ }
        continue;
      }
      if (Date.now() > deadline) {
        core.die(`changelog lock: held by live pid ${info.pid} (since ${info.started_at}) — waited ${LOCK_WAIT_MS}ms; inspect ${CHANGELOG_LOCK}`);
      }
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, LOCK_RETRY_MS);
      continue;
    }
    try {
      fs.writeSync(fd, JSON.stringify({ pid: process.pid, started_at: new Date().toISOString() }));
    } finally {
      fs.closeSync(fd);
    }
    lockOwned = true;
    process.on('exit', () => { releaseChangelogLock(); });
    return;
  }
}

// Ownership flag guards the unlink: after an intentional release a new
// process may already hold a fresh lock at the same path — never remove it.
function releaseChangelogLock() {
  if (!lockOwned) return;
  lockOwned = false;
  try { fs.unlinkSync(CHANGELOG_LOCK); } catch { /* already gone */ }
}

function loadChangelogSkeleton() {
  try {
    return fs.readFileSync(TEMPLATE_MASTER, 'utf8');
  } catch (e) {
    core.die(`changelog add: CHANGELOG.md missing and the master template is unreadable (${e.message}) — expected ${TEMPLATE_MASTER}`);
  }
}

// Insert as the first bullet of [Unreleased]: skip the single blank line
// under the heading, then splice the entry (plus a separating blank unless
// another bullet follows directly).
function insertUnreleasedTop(text, entry) {
  const lines = String(text).split(/\r?\n/);
  const idx = lines.findIndex((l) => /^##\s*\[\s*Unreleased\s*\]/i.test(l));
  if (idx === -1) return { ok: false, reason: "no '## [Unreleased]' heading" };
  let at = idx + 1;
  if (lines[at] === '') at += 1;
  const bulletFollows = at < lines.length && /^[ \t]*- /.test(lines[at]);
  lines.splice(at, 0, ...(bulletFollows ? [entry] : [entry, '']));
  return { ok: true, text: lines.join('\n') };
}

module.exports = { cmdChangelog, cmdChangelogAdd };
