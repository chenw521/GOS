// ops/push — remote aggregation: everything in origin/main..HEAD becomes ONE
// semantic commit (tree = HEAD tree, parent = origin/main tip) pushed to
// refs/heads/main; local refs are never rewritten. Fail-closed: without
// --message the subject must come from CHANGELOG.md [Unreleased] bullets added
// between origin/main and HEAD. Dispatched read-class like the changelog
// family: push never touches .gos state and git itself serializes remote
// updates, so the shared die-on-contention .gos/.lock must not gate it.
'use strict';

const core = require('../core/index.cjs');
const clcore = require('./changelog-core.cjs');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const MAIN_REF = 'refs/heads/main';
// Permission-class rejections: HTTP auth codes, SSH/collaborator denials,
// server-side hook declines and branch-protection refusals all route to the
// PR path instead of a raw git error dump.
const PERMISSION_FAILURE_RE = /(^|\W)(401|403)(\W|$)|permission denied|pre-receive hook declined|protected branch|branch protection|GH00\d/i;
// Fallback conventional token set when no commitlint yaml resolves.
const STANDARD_TYPES = ['feat', 'fix', 'docs', 'refactor', 'test', 'chore', 'ci', 'build', 'perf', 'revert'];
const STANDARD_SCOPES = null; // null = any scope allowed

// Aggregate subjects are commit messages, not changelog prose: the trace
// refs and date stamp are changelog metadata and never belong in a subject.
function stripChangelogMetadata(text) {
  return text.replace(/\s*\([^()]*\)\s*\[\d{4}-\d{2}-\d{2}\]\s*$/, '').replace(/\s*\[\d{4}-\d{2}-\d{2}\]\s*$/, '').trim();
}

// Minimal Conventional Commits validator: type/scope enums and header length
// read from the same commitlint yaml the commit-msg hook uses (seeded repo
// config first, then the shipped master). Deliberately dependency-free —
// npx is not a push prerequisite.
function loadCommitlintRules() {
  const candidates = [
    path.join(process.cwd(), 'commitlint.config.yaml'),
    path.join(core.GOS_SELF_ROOT, 'templates', 'git', 'commitlint.config.yaml'),
  ];
  for (const cfgPath of candidates) {
    let text;
    try {
      text = fs.readFileSync(cfgPath, 'utf8');
    } catch {
      continue;
    }
    const types = extractEnum(text, /type-enum:[\s\S]*?- always\n((?:\s+- \w+\n?)+)/);
    const scopes = extractEnum(text, /scope-enum:[\s\S]*?- always\n((?:\s+- \w+\n?)+)/);
    if (types.length) return { types, scopes, source: cfgPath };
  }
  return { types: STANDARD_TYPES, scopes: STANDARD_SCOPES, source: 'built-in conventional set' };
}

function extractEnum(text, re) {
  const m = String(text || '').match(re);
  if (!m) return [];
  return m[1].split('\n').map((l) => l.trim()).filter((l) => l.startsWith('- ')).map((l) => l.slice(2).trim()).filter(Boolean);
}

function validateSubject(subject) {
  const rules = loadCommitlintRules();
  const errors = [];
  if (subject.length > 72) errors.push(`header exceeds 72 chars (${subject.length})`);
  const m = subject.match(/^(\w+)(?:\(([^)]+)\))?:\s+.+$/);
  if (!m) {
    errors.push(`not Conventional Commits shaped "type(scope): subject" — allowed types: ${rules.types.join('|')}`);
  } else {
    if (!rules.types.includes(m[1])) errors.push(`type '${m[1]}' not in type-enum (${rules.types.join('|')}) — from ${path.basename(rules.source)}`);
    if (rules.scopes && m[2] && !rules.scopes.includes(m[2])) errors.push(`scope '${m[2]}' not in scope-enum (${rules.scopes.join('|')}) — from ${path.basename(rules.source)}`);
    // CI-parity case rules (commitlint.config.yaml): aggregates bypass the
    // commit-msg hook (commit-tree), so push is the last local line of defense
    // — the push-range lint in CI rejects exactly these shapes.
    const subj = subject.replace(/^(\w+)(?:\([^)]+\))?:\s+/, '');
    const hasLetter = /[A-Za-z]/.test(subj);
    const isUpper = hasLetter && subj === subj.toUpperCase();
    const isSentence = hasLetter && /^[A-Z][^A-Z]*$/.test(subj);
    const isStart = hasLetter && subj.split(/\s+/).every((w) => /^[A-Z]/.test(w));
    const isPascal = hasLetter && /^[A-Z][a-z0-9]*([A-Z][a-z0-9]+)+$/.test(subj);
    if (isUpper || isSentence || isStart || isPascal) errors.push('subject must not be sentence-case, start-case, pascal-case, upper-case [subject-case] — start lowercase');
    if (subj.endsWith('.')) errors.push('subject must not end with a full stop [subject-full-stop]');
  }
  return { ok: errors.length === 0, errors };
}

function gitOut(argv) {
  // LC_ALL=C pins git's stderr/output language: the permission-class
  // classifier below matches protocol strings, not localized catalogs.
  const env = Object.assign({}, process.env, { LC_ALL: 'C', LANG: 'C' });
  return execFileSync('git', argv, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], env }).toString();
}

function gitTry(argv) {
  try {
    return { ok: true, out: gitOut(argv), err: '' };
  } catch (e) {
    return { ok: false, out: '', err: String((e && (e.stderr || e.stdout)) || e.message || '') };
  }
}

function firstStderrLines(text, max) {
  return String(text || '').split('\n').filter(Boolean).slice(0, max || 12).join('\n');
}

function parsePushArgs(args) {
  let message = null;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--message') {
      const v = args[i + 1];
      if (v == null || v.startsWith('--')) core.die('push: --message requires a value — usage: gos push [--message "<one-liner>"]');
      message = v;
      i++;
    } else if (a.startsWith('--message=')) {
      message = a.slice('--message='.length);
    } else {
      core.die(`push: unknown argument '${a}' — usage: gos push [--message "<one-liner>"]`);
    }
  }
  if (message != null && !message.trim()) core.die('push: --message must not be empty — refusing an unlabelled aggregate');
  return { message: message == null ? null : message.trim() };
}

// Bullets present in HEAD's [Unreleased] but absent from the base revision's
// [Unreleased] — the changelog delta introduced by the commits being
// aggregated. Committed content only (working-tree edits never feed the
// aggregate subject).
function changelogDeltaBullets(baseSha, headSha) {
  const headTxt = gitTry(['show', `${headSha}:CHANGELOG.md`]);
  if (!headTxt.ok) return [];
  const baseTxt = gitTry(['show', `${baseSha}:CHANGELOG.md`]);
  const had = new Set(baseTxt.ok ? clcore.parseChangelog(baseTxt.out).unreleased : []);
  // parseChangelog hands back "- <text>" bullets; the aggregate message wants
  // the bare text (subject line, body lines).
  return clcore.parseChangelog(headTxt.out).unreleased.filter((b) => !had.has(b)).map((b) => b.replace(/^- /, ''));
}

function buildAggregateMessage(subject, rest, ahead, baseSha, headSha) {
  const lines = [subject];
  if (rest.length) {
    lines.push('');
    lines.push(...rest);
  }
  lines.push('');
  lines.push(`Aggregated ${ahead} commit(s) ${baseSha.slice(0, 8)}..${headSha.slice(0, 8)} into one semantic commit.`);
 // choke point: the whole aggregate (subject + body bullets) passes
  // through the shared neutralizer — derived changelog bullets and explicit
  // --message subjects alike must never carry a close/fix keyword + #N.
  return clcore.neutralizeIssueTriggers(lines.join('\n'));
}

function printPrGuidance(errText) {
  console.error('✗ push rejected — main is not directly pushable from here (permission boundary, not a tooling failure).');
  console.error(`  git stderr: ${firstStderrLines(errText, 3).split('\n').join(' | ')}`);
  console.error('PR path:');
  console.error('  1. raw-push a feature branch (unguarded by design): git push origin HEAD:refs/heads/<branch>');
  console.error('  2. open a pull request into main from that branch');
  console.error('  3. have it squash-merged — the aggregate lands as one problem-per-commit');
}

function cmdPush(args) {
  const { message } = parsePushArgs(args);
  if (!gitTry(['rev-parse', '--is-inside-work-tree']).ok) core.die('push: not a git work tree — run from inside the repository you want to publish');
  if (!gitTry(['remote', 'get-url', 'origin']).ok) core.die('push: no origin remote configured — gos push publishes the aggregate to origin');
  const fetched = gitTry(['fetch', 'origin']);
  if (!fetched.ok) core.die(`push: git fetch origin failed:\n${firstStderrLines(fetched.err)}`);
  const baseRes = gitTry(['rev-parse', '--verify', 'origin/main']);
  if (!baseRes.ok) core.die('push: origin/main not found — the aggregator builds on an existing remote main (bootstrap origin/main first, then re-run)');
  const baseSha = baseRes.out.trim();
  const headSha = gitOut(['rev-parse', 'HEAD']).trim();
  const headTree = gitOut(['rev-parse', 'HEAD^{tree}']).trim();
  const baseTree = gitOut(['rev-parse', `${baseSha}^{tree}`]).trim();
  // Content-equality no-op: covers both "nothing ahead" and "already
  // aggregated" (the aggregate is not an ancestor of HEAD, so rev-list alone
  // cannot detect the re-run case).
  if (headTree === baseTree) {
    console.log('✓ nothing to aggregate — origin/main already carries the HEAD tree');
    return;
  }
  const ahead = parseInt(gitOut(['rev-list', '--count', `${baseSha}..HEAD`]).trim(), 10);
  if (!Number.isFinite(ahead) || ahead <= 0) {
    core.die('push: origin/main tree differs from HEAD with nothing ahead — review the remote first (aggregation never rewrites remote content backwards)');
  }
  // Divergence guard: refuse when the remote carries CONTENT HEAD does not
  // (aggregating from a stale clone would fast-forward main and silently
  // drop it). Topology-only divergence is legitimate — history rebuilds
  // re-commit trees HEAD already knows — so the test is tree containment:
  // every behind commit's tree must already exist in HEAD's ancestry.
  const behind = parseInt(gitOut(['rev-list', '--count', `HEAD..${baseSha}`]).trim(), 10) || 0;
  if (behind > 0) {
    const localTrees = new Set(gitOut(['log', '--format=%T', 'HEAD']).split('\n').filter(Boolean));
    const foreign = gitOut(['log', '--format=%T', `HEAD..${baseSha}`]).split('\n').filter(Boolean).filter((t) => !localTrees.has(t));
    if (foreign.length) {
      core.die(`push: origin/main has ${behind} commit(s) not in HEAD, ${foreign.length} with trees absent from local history — stale or diverged clone; fetch and rebase/merge first (aggregating from here would silently drop remote content)`);
    }
    console.log(`… topology-only divergence: ${behind} rebuilt commit(s) whose trees are known locally — proceeding`);
  }
  let subject = message;
  let rest = [];
  if (subject == null) {
    const bullets = changelogDeltaBullets(baseSha, headSha).map(stripChangelogMetadata);
    if (!bullets.length) {
      core.die('push: refusing — no --message and no new CHANGELOG.md [Unreleased] bullets between origin/main and HEAD; write the entry first (gos changelog add --summary "<one sentence>")');
    }
    subject = bullets[0];
    rest = bullets.slice(1);
  }
  const verdict = validateSubject(subject);
  if (!verdict.ok) {
    console.error('push: aggregate subject fails the conventional-format contract:');
    for (const e of verdict.errors) console.error(`  ✗ ${e}`);
    core.die('push: refusing — pass --message "type(scope): one-liner" (the derived changelog bullet is prose, not a commit subject)');
  }
  const aggregateMessage = buildAggregateMessage(subject, rest, ahead, baseSha, headSha);
  // commit-tree only creates an unreachable object — local branches and the
  // atomic chain stay exactly as they are until the push succeeds.
  const aggSha = gitOut(['commit-tree', headTree, '-p', baseSha, '-m', aggregateMessage]).trim();
  console.log(`… aggregate ${aggSha.slice(0, 8)} = tree ${headTree.slice(0, 8)} on parent ${baseSha.slice(0, 8)} (${ahead} commit(s), local refs untouched)`);
  const pushed = gitTry(['push', 'origin', `${aggSha}:${MAIN_REF}`]);
  if (!pushed.ok) {
    if (PERMISSION_FAILURE_RE.test(pushed.err)) {
      printPrGuidance(pushed.err);
      process.exit(1);
    }
    core.die(`push: git push failed:\n${firstStderrLines(pushed.err)}`);
  }
  console.log(`✓ pushed ${aggSha.slice(0, 8)} → origin/main (${ahead} commit(s) → 1 semantic commit)`);
  convergeLocalMain(aggSha);
}

// Post-push convergence: preserve the atomic chain on an audit branch, then
// move local main onto the aggregate (identical tree, worktree untouched).
// Runs only on success, only when HEAD is main and the tree is clean — any
// other situation keeps the old divergence with a notice instead of a
// destructive reset.
function convergeLocalMain(aggSha) {
  const branch = gitOut(['branch', '--show-current']).trim();
  // Tracked modifications only: untracked files (e.g. installed hooks)
  // survive `git reset --hard` untouched, so they must not block convergence.
  const dirty = gitTry(['status', '--porcelain', '--untracked-files=no']).out.trim().length > 0;
  if (branch !== 'main' || dirty) {
    console.log(`… convergence skipped (${branch !== 'main' ? `HEAD is '${branch}', not main` : 'working tree not clean'}) — audit branch not created, local chain stays as is`);
    return;
  }
  const preHead = gitOut(['rev-parse', 'HEAD']).trim();
  let name = `chain/pre-${preHead.slice(0, 8)}`;
  try {
    const st = JSON.parse(fs.readFileSync(path.join(core.GOS_DIR, 'state.json'), 'utf8'));
    const m = String((st && st.spec_path) || '').match(/\.gos\/task\/([^/]+)\//);
    if (m) name = `chain/${m[1]}`;
  } catch { /* state optional — fallback name stands */ }
  gitOut(['branch', '-f', name, preHead]);
  gitOut(['reset', '--hard', aggSha]);
  console.log(`✓ converged: atomic chain preserved on ${name}, main now at the aggregate ${aggSha.slice(0, 8)}`);
}

// Single source for the archive-time hint: the archive flow prints this line
// after completing locally; the push itself stays user-executed.
function archivePushHint() {
  return 'Next: gos push — aggregates commits ahead of origin/main into one semantic commit (message auto-derives from CHANGELOG.md [Unreleased] at push time)';
}

module.exports = { cmdPush, archivePushHint };
