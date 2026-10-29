// ops/auto/delivery-publish — the publish leg of the delivery adapter:
// push the per-task work branch through the env-sanitized privileged git
// runner against the pinned remote, open a PR rendered from the runner-held
// template (worker-originated strings appear only inside quoted labeled
// blocks), lint the squash subject pre-merge, squash-merge via gh api, then
// watch CI on the base branch up to a 45-minute budget. A red run stops for
// an explicit human disposition; a watch that expires ends in the
// disposition-unknown outcome and produces the non-counting ci-watch-timeout
// signal; terminal green writes a closure record of public facts only
// (run id + status + ts) into the repo-local ledger mirror, with full
// disposition detail staying in the machine-local store. Every external
// effect (git, gh, lint, CI status, clock, sleep) is injectable; the
// defaults are real.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const store = require('./store.cjs');
const delivery = require('./delivery.cjs');
const loop = require('./loop.cjs');
const core = require('../../core/index.cjs');

// Outcome label for a CI watch that expired without a verdict: the run's
// true state is unknown, so it routes to the human disposition path.
const DISPOSITION_UNKNOWN = delivery.DISPOSITION_UNKNOWN;

// Signal handed to the breaker taxonomy for the watch-timeout outcome. The
// taxonomy maps it to countsTowardN=false — a queued green at minute 46 is
// not bad work.
const CI_WATCH_TIMEOUT_SIGNAL = 'ci-watch-timeout';

const DEFAULT_WATCH_TIMEOUT_MS = 45 * 60 * 1000;
const DEFAULT_POLL_MS = 30 * 1000;
const DEFAULT_BASE_BRANCH = 'main';

// Repo-local debug mirror for closure and disposition-hash records. Never a
// trust input; never read back by any gate.
const AUTO_LEDGER_FILE = 'auto-ledger.ndjson';

// Runner-held PR template: the structure and every fixed label live here,
// never in repo files and never in worker output.
const PR_TEMPLATE = Object.freeze({
  header: 'This pull request was opened by the gos auto delivery leg. Content outside the quoted blocks below is runner-generated; quoted blocks reproduce worker session output verbatim and are untrusted.',
  sections: Object.freeze({
    shipLedger: 'SHIP ledger summary',
    workerTitle: 'Worker-proposed title (untrusted, quoted verbatim)',
    workerSummary: 'Worker session summary (untrusted, quoted verbatim)',
  }),
  mergeNote: 'Merge is squash-only; the squash subject passed the repository subject lint before the merge was attempted.',
});

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

function resolveRoot(rootDir) {
  return rootDir ? path.resolve(String(rootDir)) : (core.currentRootRealpath() || process.cwd());
}

// ---------- defaults ----------

function defaultGhRunner(args) {
  return spawnSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

// The repo's own subject-lint guard, invoked exactly as the push ruling
// prescribes: bash test/checks/push-lint-squash.sh --subject <candidate>.
function defaultLintScript() {
  return path.resolve(__dirname, '..', '..', '..', '..', 'test', 'checks', 'push-lint-squash.sh');
}

function defaultLintRunner(subject) {
  return spawnSync('bash', [defaultLintScript(), '--subject', subject], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

function defaultSleep(ms) {
  return new Promise((resolve) => { setTimeout(resolve, ms); });
}

// gh-based CI status for one branch: the newest run is pending until its
// status is completed, then green only on conclusion success.
function defaultCiStatus({ ghRunner, slug, branch }) {
  const run = typeof ghRunner === 'function' ? ghRunner : defaultGhRunner;
  if (!slug || !branch) return null;
  return function ciStatus() {
    const res = run(['run', 'list', '--branch', branch, '--limit', '1', '--json', 'status,conclusion,databaseId']);
    if (!res || res.status !== 0) {
      return { state: 'error', detail: String((res && res.stderr) || 'gh run list failed').trim().slice(0, 240) };
    }
    let newest = null;
    try {
      const parsed = JSON.parse(String(res.stdout || ''));
      newest = Array.isArray(parsed) ? parsed[0] : null;
    } catch { newest = null; }
    if (!isPlainObject(newest)) return { state: 'error', detail: 'gh run list output held no runs' };
    const runId = newest.databaseId != null ? String(newest.databaseId) : null;
    if (newest.status !== 'completed') return { state: 'pending', runId };
    return { state: newest.conclusion === 'success' ? 'green' : 'red', runId, conclusion: newest.conclusion || null };
  };
}

// ---------- PR rendering ----------

// Wrap one worker-originated string as a labeled quoted block: every line,
// blank lines included, carries the '>' quote prefix so no worker content
// can ever render outside the block.
function renderQuotedBlock(label, text) {
  const body = String(text == null ? '' : text).replace(/\r/g, '');
  const quoted = body.split('\n').map((line) => '> ' + line).join('\n');
  return `**${label}**\n\n${quoted}`;
}

// Normalize a SHIP ledger summary to counts only: numbers pass through,
// arrays of approval records count the mode:'auto' delegated entries
// (legacy bare-string approvals are human, not delegated), any other arrays
// count entries. Anything absent stays absent.
function shipLedgerCounts(ledger) {
  if (!isPlainObject(ledger)) return null;
  const delegated = (v) => (Array.isArray(v) ? v.filter((e) => isPlainObject(e) && e.mode === 'auto').length : v);
  const plain = (v) => (Array.isArray(v) ? v.length : v);
  const out = {};
  if (ledger.delegatedApprovals != null) out.delegatedApprovals = delegated(ledger.delegatedApprovals);
  if (ledger.verifyTruths != null) out.verifyTruths = plain(ledger.verifyTruths);
  if (ledger.redteamFindings != null) out.redteamFindings = plain(ledger.redteamFindings);
  return Object.keys(out).length ? out : null;
}

// Render the PR body from the runner-held template: runner facts (task id,
// branches) and SHIP ledger counts render bare; worker strings render only
// inside quoted labeled blocks.
function renderPrBody(ctx = {}) {
  const lines = [];
  lines.push(PR_TEMPLATE.header);
  lines.push('');
  lines.push(`- task: ${ctx.taskId != null ? String(ctx.taskId) : '(unknown)'}`);
  lines.push(`- branch: ${String(ctx.branch || '(unknown)')}`);
  lines.push(`- base: ${String(ctx.base || DEFAULT_BASE_BRANCH)}`);
  const counts = shipLedgerCounts(ctx.shipLedger);
  if (counts) {
    lines.push('');
    lines.push(`### ${PR_TEMPLATE.sections.shipLedger}`);
    if (counts.delegatedApprovals != null) lines.push(`- delegated approvals: ${counts.delegatedApprovals}`);
    if (counts.verifyTruths != null) lines.push(`- VERIFY truths: ${counts.verifyTruths}`);
    if (counts.redteamFindings != null) lines.push(`- red-team findings: ${counts.redteamFindings}`);
  }
  const workerTitle = isPlainObject(ctx.worker) && typeof ctx.worker.title === 'string' ? ctx.worker.title : null;
  const workerSummary = isPlainObject(ctx.worker) && typeof ctx.worker.summary === 'string' ? ctx.worker.summary : null;
  if (workerTitle != null) {
    lines.push('');
    lines.push(renderQuotedBlock(PR_TEMPLATE.sections.workerTitle, workerTitle));
  }
  if (workerSummary != null) {
    lines.push('');
    lines.push(renderQuotedBlock(PR_TEMPLATE.sections.workerSummary, workerSummary));
  }
  lines.push('');
  lines.push(PR_TEMPLATE.mergeNote);
  return lines.join('\n');
}

// ---------- ledger mirror ----------

// Append one ndjson record to the repo-local auto ledger mirror (hash/count
// facts only — never session detail).
function appendLedgerMirror(rootDir, entry) {
  try {
    const dir = path.join(rootDir, '.gos', 'logs');
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, AUTO_LEDGER_FILE);
    fs.appendFileSync(file, JSON.stringify(entry) + '\n', 'utf8');
    return { ok: true, path: file };
  } catch (e) {
    return { ok: false, reason: 'write-failed', detail: e.message };
  }
}

// ---------- dispositions ----------

// Latest recorded disposition for one CI run, or not-found. Verification
// reads the machine-local store only; the repo ledger mirror is never a
// read source.
function dispositionFor(runId, rootDir) {
  if (typeof runId !== 'string' || !runId) return { ok: false, status: 'error', reason: 'invalid-run-id' };
  const cur = store.load(rootDir);
  if (!cur.ok) return cur;
  const found = [...cur.store.dispositions].reverse().find((d) => d.runId === runId) || null;
  if (!found) return { ok: false, status: 'not-found', reason: 'no-disposition', runId };
  return { ok: true, disposition: found };
}

// `gos auto disposition <run> --reason` surface: record into the store,
// mirror only the record hash into the repo-local ledger.
function writeDisposition(input, rootDir) {
  if (!isPlainObject(input)) return { ok: false, status: 'error', reason: 'invalid-disposition' };
  const ts = new Date().toISOString();
  const r = store.recordDisposition({ runId: input.runId, ts, reason: input.reason, by: input.by }, rootDir);
  if (!r.ok) return r;
  const sha256 = sha256Of(JSON.stringify(r.disposition));
  const mirror = appendLedgerMirror(rootDir, { kind: 'disposition', runId: r.disposition.runId, sha256, ts });
  return {
    ok: true,
    disposition: r.disposition,
    ledgerMirror: { sha256, path: mirror.ok ? mirror.path : undefined, write: mirror },
    guidance: guidanceFor('auto.publish.dispositionRecorded', { runId: r.disposition.runId }),
  };
}

// ---------- CI watch ----------

// Poll the CI status source until green/red, until the timeout budget is
// spent, or until the status source itself fails (fast-fail: a dead gh must
// not burn the whole budget). Timeout returns the disposition-unknown
// outcome carrying the ci-watch-timeout signal — never a breaker count.
async function watchCi(opts = {}) {
  const timeoutMs = Number.isFinite(opts.timeoutMs) && opts.timeoutMs > 0 ? opts.timeoutMs : DEFAULT_WATCH_TIMEOUT_MS;
  const pollMs = Number.isFinite(opts.pollMs) && opts.pollMs > 0 ? opts.pollMs : DEFAULT_POLL_MS;
  const now = typeof opts.now === 'function' ? opts.now : Date.now;
  const sleep = typeof opts.sleep === 'function' ? opts.sleep : defaultSleep;
  const ciStatus = typeof opts.ciStatus === 'function' ? opts.ciStatus : defaultCiStatus(opts);
  if (typeof ciStatus !== 'function') {
    return {
      ok: false, status: 'error', reason: 'ci-status-required',
      guidance: guidanceFor('auto.publish.watchFailed', { detail: 'no CI status source (inject ciStatus, or ghRunner with slug and branch)' }),
    };
  }
  const startedAt = now();
  const maxPolls = Math.ceil(timeoutMs / pollMs) + 1;
  let polls = 0;
  let lastRunId = null;
  for (;;) {
    let st;
    try { st = await ciStatus(); }
    catch (e) { st = { state: 'error', detail: e && e.message }; }
    if (isPlainObject(st) && typeof st.runId === 'string' && st.runId) lastRunId = st.runId;
    if (isPlainObject(st) && st.state === 'green') {
      return { ok: true, state: 'green', runId: st.runId || lastRunId, polls: polls + 1 };
    }
    if (isPlainObject(st) && st.state === 'red') {
      return { ok: true, state: 'red', runId: st.runId || lastRunId, polls: polls + 1 };
    }
    if (isPlainObject(st) && st.state === 'error') {
      return {
        ok: false, status: 'error', reason: 'ci-status-failed', detail: st.detail,
        runId: lastRunId, polls: polls + 1,
        guidance: guidanceFor('auto.publish.watchFailed', { detail: st.detail || 'CI status source failed' }),
      };
    }
    polls += 1;
    const elapsed = now() - startedAt;
    if (elapsed >= timeoutMs || polls >= maxPolls) {
      return {
        ok: false, status: DISPOSITION_UNKNOWN, signal: CI_WATCH_TIMEOUT_SIGNAL,
        runId: lastRunId, elapsedMs: elapsed, polls,
      };
    }
    await sleep(pollMs);
  }
}

// ---------- publish flow ----------

// The full publish leg: push -> PR create -> subject lint -> squash merge
// -> CI watch -> closure/held. The branch defaults to the loop's per-task
// work branch name; pushes always target the pinned remote URL. Options
// (all injectable, real defaults): rootDir, taskId or branch, base,
// baseline, subject (required squash-subject candidate), worker {title,
// summary}, shipLedger, gitRunner, privilegedRunner, ghRunner, lintRunner,
// ciStatus, prNumber, now, sleep, timeoutMs, pollMs.
async function publish(opts = {}) {
  const rootDir = resolveRoot(opts.rootDir);
  const now = typeof opts.now === 'function' ? opts.now : Date.now;
  const steps = [];

  const taskId = opts.taskId != null ? String(opts.taskId) : null;
  const branch = typeof opts.branch === 'string' && opts.branch
    ? opts.branch
    : (taskId ? loop.workBranchName(taskId) : null);
  if (!branch) {
    return { ok: false, status: 'error', reason: 'branch-required', guidance: guidanceFor('auto.publish.branchRequired') };
  }

  const subject = typeof opts.subject === 'string' ? opts.subject.trim() : '';
  if (!subject) {
    return { ok: false, status: 'error', reason: 'subject-required', guidance: guidanceFor('auto.publish.subjectRequired') };
  }

  let baseline = opts.baseline;
  if (baseline == null) {
    const pinned = delivery.loadPinnedBaseline(rootDir);
    if (!pinned.ok) return { ok: false, status: 'error', reason: pinned.reason, path: pinned.path, guidance: pinned.guidance };
    baseline = pinned.baseline;
  }
  const slug = delivery.extractGithubSlug(baseline.remoteUrl);
  if (!slug) {
    return {
      ok: false, status: 'error', reason: 'not-github-remote', remoteUrl: baseline.remoteUrl,
      guidance: guidanceFor('auto.publish.prCreateFailed', { detail: 'the pinned origin is not a GitHub remote' }),
    };
  }
  const base = typeof opts.base === 'string' && opts.base ? opts.base : DEFAULT_BASE_BRANCH;

  // 1. branch push — privileged, pinned URL, baseline re-verified first.
  const refspec = `refs/heads/${branch}:refs/heads/${branch}`;
  const pushRes = delivery.runPrivilegedGit(['push', baseline.remoteUrl, refspec], {
    rootDir, baseline, gitRunner: opts.gitRunner, privilegedRunner: opts.privilegedRunner,
  });
  steps.push({ name: 'push', ok: pushRes.ok === true, refspec });
  if (!pushRes.ok) {
    return {
      ok: false, status: pushRes.status === 'aborted' ? 'aborted' : 'error',
      reason: pushRes.reason || 'push-failed', branch, refspec,
      drift: pushRes.drift, breaker: pushRes.breaker, argv: pushRes.argv,
      detail: pushRes.detail, steps,
      guidance: pushRes.guidance || guidanceFor('auto.publish.branchPushFailed', { branch }),
    };
  }

  // 2. PR create — runner-held template, worker strings quoted.
  const ghRunner = typeof opts.ghRunner === 'function' ? opts.ghRunner : defaultGhRunner;
  const body = renderPrBody({ taskId, branch, base, worker: opts.worker, shipLedger: opts.shipLedger });
  const prRes = ghRunner(['pr', 'create', '--title', subject, '--body', body, '--base', base, '--head', branch]);
  const prUrl = prRes && prRes.status === 0 ? String(prRes.stdout || '').trim() : null;
  let prNumber = Number.isInteger(opts.prNumber) ? opts.prNumber : null;
  if (prNumber == null && prUrl) {
    const m = prUrl.match(/\/pull\/(\d+)/);
    if (m) prNumber = Number(m[1]);
  }
  steps.push({ name: 'pr-create', ok: !!(prRes && prRes.status === 0 && prNumber != null), prNumber });
  if (!prRes || prRes.status !== 0 || prNumber == null) {
    return {
      ok: false, status: 'error',
      reason: prRes && prRes.status === 0 ? 'pr-number-unparsed' : 'pr-create-failed',
      branch, prUrl, steps,
      detail: String((prRes && prRes.stderr) || '').trim().slice(0, 240),
      guidance: guidanceFor('auto.publish.prCreateFailed', { detail: prUrl ? 'PR created but its number is not parsable from the URL' : 'gh pr create failed' }),
    };
  }

  // 3. subject lint pre-merge — failure holds, never a force-merge.
  const lintRunner = typeof opts.lintRunner === 'function' ? opts.lintRunner : defaultLintRunner;
  const lintRes = lintRunner(subject);
  steps.push({ name: 'subject-lint', ok: !!(lintRes && lintRes.status === 0) });
  if (!lintRes || lintRes.status !== 0) {
    return {
      ok: false, status: 'held', reason: 'subject-lint', merged: false,
      subject, prNumber, prUrl, steps,
      detail: String((lintRes && lintRes.stderr) || '').trim().slice(0, 240),
      guidance: guidanceFor('auto.publish.subjectLintHeld', { subject }),
    };
  }

  // 4. squash merge via gh api — the linted subject becomes the commit title.
  const mergeRes = ghRunner([
    'api', '-X', 'PUT', `repos/${slug}/pulls/${prNumber}/merge`,
    '-f', 'merge_method=squash', '-f', `commit_title=${subject}`,
  ]);
  steps.push({ name: 'merge', ok: !!(mergeRes && mergeRes.status === 0), prNumber });
  if (!mergeRes || mergeRes.status !== 0) {
    return {
      ok: false, status: 'error', reason: 'merge-failed', prNumber, prUrl, steps,
      detail: String((mergeRes && mergeRes.stderr) || '').trim().slice(0, 240),
      guidance: guidanceFor('auto.publish.mergeFailed', { prNumber }),
    };
  }

  // 5. CI watch on the base branch.
  let ciStatus = typeof opts.ciStatus === 'function' ? opts.ciStatus : null;
  if (ciStatus == null) {
    ciStatus = defaultCiStatus({ ghRunner, slug, branch: base });
    if (ciStatus == null) {
      return {
        ok: false, status: 'error', reason: 'ci-status-required', prNumber, prUrl, steps,
        guidance: guidanceFor('auto.publish.watchFailed', { detail: 'no CI status source for the base branch' }),
      };
    }
  }
  const watch = await watchCi({ ciStatus, timeoutMs: opts.timeoutMs, pollMs: opts.pollMs, now, sleep: opts.sleep });
  steps.push({ name: 'ci-watch', ok: watch.ok === true, state: watch.state || null, polls: watch.polls });

  if (!watch.ok && watch.status === DISPOSITION_UNKNOWN) {
    return {
      ok: false, status: DISPOSITION_UNKNOWN, reason: 'ci-watch-timeout',
      signal: watch.signal, runId: watch.runId || null,
      elapsedMs: watch.elapsedMs, polls: watch.polls, prNumber, prUrl, steps,
      guidance: guidanceFor('auto.publish.ciUnknown', {
        minutes: Math.round((Number.isFinite(opts.timeoutMs) && opts.timeoutMs > 0 ? opts.timeoutMs : DEFAULT_WATCH_TIMEOUT_MS) / 60000),
      }),
    };
  }
  if (!watch.ok) {
    return {
      ok: false, status: 'error', reason: watch.reason, detail: watch.detail,
      runId: watch.runId || null, prNumber, steps, guidance: watch.guidance,
    };
  }

  // 6. terminal outcome. Red requires a recorded human disposition before
  // the flow may continue; green closes directly. Closure records carry
  // public facts only.
  const runId = watch.runId || `pr-${prNumber}`;
  if (watch.state === 'red') {
    const disp = dispositionFor(runId, rootDir);
    if (!disp.ok) {
      return {
        ok: false, status: 'held', reason: 'red-run', runId,
        prNumber, prUrl, steps, requiresDisposition: true,
        guidance: guidanceFor('auto.publish.redRun', { runId }),
      };
    }
    const closure = { runId, status: 'red-dispositioned', ts: new Date(now()).toISOString() };
    const mirror = appendLedgerMirror(rootDir, { kind: 'closure', ...closure });
    return { ok: true, status: 'red-dispositioned', runId, disposition: disp.disposition, closure, ledger: mirror, prNumber, prUrl, steps };
  }

  const closure = { runId, status: 'green', ts: new Date(now()).toISOString() };
  const mirror = appendLedgerMirror(rootDir, { kind: 'closure', ...closure });
  return { ok: true, status: 'green', runId, closure, ledger: mirror, prNumber, prUrl, steps };
}

// ---------- teardown ----------

// `gos auto off --purge` surface: remove this repo's machine-local store.
function purge(rootDir) {
  const r = store.purgeStore(rootDir);
  if (!r.ok) return r;
  return { ...r, guidance: guidanceFor('auto.publish.purged', { path: r.path || '' }) };
}

module.exports = {
  DISPOSITION_UNKNOWN,
  CI_WATCH_TIMEOUT_SIGNAL,
  DEFAULT_WATCH_TIMEOUT_MS,
  DEFAULT_POLL_MS,
  DEFAULT_BASE_BRANCH,
  PR_TEMPLATE,
  renderQuotedBlock,
  renderPrBody,
  shipLedgerCounts,
  watchCi,
  publish,
  dispositionFor,
  writeDisposition,
  purge,
};
