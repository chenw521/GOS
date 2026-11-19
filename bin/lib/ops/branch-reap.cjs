// ops/branch-reap — local branch reaping: retire branches whose content has
// already landed in a base ref, keeping a revive ref instead of losing them.
// Verdict per branch: delete (tip tree exists somewhere in base history —
// ancestry, squash and aggregate rebuilds all qualify), manual (content not
// provably contained), keep (exempt: chain/* namespace, reaped/* archive,
// the active auto task work branch, any worktree-checked-out branch
// including pin-worktrees). Tree evidence is evaluated under
// GIT_NO_REPLACE_OBJECTS=1 so replace refs cannot fake ancestry; a non-empty
// refs/replace/ or info/grafts refuses outright instead of judging through a
// locally rewritten history. Dispatched read-class like push: dry-run never
// mutates anything, --apply mutates only git refs (never .gos state), and
// the live-run-lock guard refuses to reap under a running auto runner.
'use strict';

const core = require('../core/index.cjs');
const store = require('./auto/store.cjs');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const USAGE = 'gos branch reap [--dry-run|--apply] --base <ref>';

// Every git invocation here runs with object replacement disabled: the
// delete verdict must reflect real repository objects, never a refs/replace
// rewrite of them.
function gitOutNoReplace(argv) {
  const env = Object.assign({}, process.env, { GIT_NO_REPLACE_OBJECTS: '1', LC_ALL: 'C', LANG: 'C' });
  return execFileSync('git', argv, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], env }).toString();
}

function gitTryNoReplace(argv) {
  try {
    return { ok: true, out: gitOutNoReplace(argv), err: '' };
  } catch (e) {
    return { ok: false, out: '', err: String((e && (e.stderr || e.stdout)) || e.message || '') };
  }
}

function parseReapArgs(args) {
  let mode = null;
  let base = null;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--dry-run') mode = 'dry-run';
    else if (a === '--apply') mode = 'apply';
    else if (a === '--base') {
      const v = args[i + 1];
      if (v == null || v.startsWith('--')) core.die(core.t('branchReap.err.unknownArg', { arg: a, usage: USAGE }));
      base = v;
      i++;
    } else if (a.startsWith('--base=')) {
      base = a.slice('--base='.length);
    } else {
      core.die(core.t('branchReap.err.unknownArg', { arg: a, usage: USAGE }));
    }
  }
  if (mode === null) mode = 'dry-run';
  if (!base) core.die(core.t('branchReap.err.baseRequired', { usage: USAGE }));
  return { mode, base };
}

// Active info/grafts lines: comments and blanks do not count, any other
// line rewrites parentage.
function graftsActive() {
  let text;
  try {
    text = fs.readFileSync(path.join(gitOutNoReplace(['rev-parse', '--absolute-git-dir']).trim(), 'info', 'grafts'), 'utf8');
  } catch {
    return false;
  }
  return text.split('\n').some((l) => l.trim() && !l.trim().startsWith('#'));
}

function replaceRefCount() {
  return gitTryNoReplace(['for-each-ref', 'refs/replace/']).out.split('\n').filter(Boolean).length;
}

// Branches checked out in any worktree. Pin-worktrees are ordinary linked
// worktrees and appear in the porcelain listing; their recorded store
// entries are probed as well so a temporarily unlisted pin (broken prune
// state) still vetsoes deleting whatever it has checked out.
function worktreeBranches() {
  const set = new Set();
  const res = gitTryNoReplace(['worktree', 'list', '--porcelain']);
  if (res.ok) {
    for (const line of res.out.split('\n')) {
      const m = line.match(/^branch refs\/heads\/(.+)$/);
      if (m) set.add(m[1]);
    }
  }
  const pins = store.readPins();
  if (pins && pins.ok) {
    for (const rec of Object.values(pins.pins || {})) {
      if (typeof rec.path !== 'string' || !fs.existsSync(rec.path)) continue;
      const b = gitTryNoReplace(['-C', rec.path, 'branch', '--show-current']);
      if (b.ok && b.out.trim()) set.add(b.out.trim());
    }
  }
  return set;
}

// Work branch of the active auto task, derived from state.json the same way
// the loop derives it (auto/<taskId>). State is optional evidence, never a
// hard dependency: absent or unreadable state simply means no exemption.
function activeTaskBranch() {
  try {
    const st = JSON.parse(fs.readFileSync(path.join(core.GOS_DIR, 'state.json'), 'utf8'));
    const id = core.currentTaskId(st);
    if (!id) return null;
    const slug = String(id).replace(/[^a-z0-9_-]/gi, '-').replace(/^[-.]+|[-.]+$/g, '');
    return slug ? `auto/${slug}` : null;
  } catch {
    return null;
  }
}

function exemptionReason(branch, checkedOut, taskBranch) {
  if (branch.startsWith('chain/')) return 'chain-namespace';
  if (branch.startsWith('reaped/')) return 'reaped-namespace';
  if (taskBranch != null && branch === taskBranch) return 'active-task';
  if (checkedOut.has(branch)) return 'worktree-checked-out';
  return null;
}

// A run lock blocks --apply when its holder could still be alive: a live
// same-host pid (boot-id consistent), or any cross-host holder — this
// machine cannot verify a remote pid, so it fails closed. A dead pid or a
// boot-id mismatch cannot be alive and does not block.
function liveRunLockHolder() {
  const rec = store.readRunLock();
  if (!rec) return null;
  if (rec.hostname !== os.hostname()) return rec;
  let boot = null;
  try { boot = fs.readFileSync('/proc/sys/kernel/random/boot_id', 'utf8').trim(); } catch { /* unavailable */ }
  if (boot && rec.boot_id && boot !== rec.boot_id) return null;
  if (!core.pidAlive(Number(rec.pid))) return null;
  return rec;
}

// One deletion: revive ref first, branch ref second — a crash between the
// two leaves the branch intact (safe direction), never the reverse.
function applyDeletion(branch, sha) {
  const reapedRef = `refs/reaped/${branch}`;
  const made = gitTryNoReplace(['update-ref', reapedRef, sha]);
  if (!made.ok) return { ok: false, stage: 'revive', err: made.err, reapedRef };
  const del = gitTryNoReplace(['update-ref', '-d', `refs/heads/${branch}`]);
  if (!del.ok) return { ok: false, stage: 'delete', err: del.err, reapedRef };
  return { ok: true, reapedRef };
}

function cmdBranch(args) {
  const sub = (args[0] || '').toLowerCase();
  if (sub !== 'reap') core.die(core.t('branchReap.err.unknownSub', { sub: args[0] || '', usage: USAGE }));
  const opts = parseReapArgs(args.slice(1));
  if (!gitTryNoReplace(['rev-parse', '--is-inside-work-tree']).ok) core.die(core.t('branchReap.err.noRepo'));
  // History-rewrite refusal: tier-1 evidence is only trustworthy on the
  // real object graph.
  const nReplace = replaceRefCount();
  if (nReplace > 0) core.die(core.t('branchReap.err.replaceRefs', { n: nReplace }));
  if (graftsActive()) core.die(core.t('branchReap.err.grafts'));
  const baseRes = gitTryNoReplace(['rev-parse', '--verify', `${opts.base}^{commit}`]);
  if (!baseRes.ok) core.die(core.t('branchReap.err.baseMissing', { base: opts.base }));
  const baseSha = baseRes.out.trim();
  if (opts.mode === 'apply') {
    const holder = liveRunLockHolder();
    if (holder) core.die(core.t('branchReap.err.runLockLive', { pid: holder.pid, host: holder.hostname }));
  }
  // Content-landed evidence: the set of every tree object reachable from
  // the base — a branch whose tip tree is a member adds no content the base
  // history does not already carry.
  const baseTrees = new Set(gitOutNoReplace(['log', '--format=%T', baseSha]).split('\n').filter(Boolean));
  const checkedOut = worktreeBranches();
  const taskBranch = activeTaskBranch();
  const rows = [];
  const listing = gitOutNoReplace(['for-each-ref', '--format=%(refname:short)%09%(objectname)%09%(committerdate:iso8601)', 'refs/heads/']);
  for (const line of listing.split('\n').filter(Boolean)) {
    const [branch, sha, when] = line.split('\t');
    const row = { branch, sha, lastCommitIso: when || null };
    const exempt = exemptionReason(branch, checkedOut, taskBranch);
    if (exempt != null) {
      row.action = 'keep';
      row.reason = exempt;
    } else {
      const tree = gitTryNoReplace(['rev-parse', `${sha}^{tree}`]);
      if (tree.ok && baseTrees.has(tree.out.trim())) {
        row.action = 'delete';
        row.reason = 'content-landed-in-base';
        row.reapedRef = `refs/reaped/${branch}`;
        row.revive = ['git', 'branch', branch, sha];
      } else {
        row.action = 'manual';
        row.reason = 'content-not-contained-in-base';
      }
    }
    rows.push(row);
  }
  let applyFailures = 0;
  if (opts.mode === 'apply') {
    for (const row of rows) {
      if (row.action !== 'delete') continue;
      const r = applyDeletion(row.branch, row.sha);
      row.applied = r.ok;
      if (!r.ok) {
        applyFailures++;
        row.errorStage = r.stage;
        row.error = String(r.err || '').split('\n').filter(Boolean).slice(0, 3).join(' | ');
      }
    }
  }
  const summary = { delete: 0, manual: 0, keep: 0 };
  for (const r of rows) summary[r.action]++;
  const payload = { mode: opts.mode, base: opts.base, baseSha, summary, branches: rows };
  console.log(JSON.stringify(payload, null, 2));
  if (applyFailures > 0) {
    console.error(core.t('branchReap.apply.errors', { n: applyFailures }));
    process.exitCode = 1;
  }
}

module.exports = { cmdBranch };
