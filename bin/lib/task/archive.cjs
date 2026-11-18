'use strict';

const core = require('../core/index.cjs');
const ops = require('../ops/doctor.cjs');  // direct aspect require (dependency DAG)
const render = require('../render/views.cjs');
const sibPlansnap = require('./plansnap.cjs');
const clcore = require('../ops/changelog-core.cjs');  // task→ops (single-track gate primitives)
const sibPush = require('../ops/push.cjs');  // archive→ops push hint (single source for the printed line)
const knowledge = require('../knowledge/lessons-json.cjs');  // task→knowledge (DAG: json truth loads)
const phasegate = require('../knowledge/phase.cjs');  // task→knowledge (DAG precedent) — D-06 predicate home
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

// archiveSlugParts lives in context.cjs (census context domain home; breaks the archive↔ops/doctor file cycle)

// specDecisionTitles: for decision-less states (Lv1/2 keep decisions in
// spec prose, never in state.json), extract the decision lead lines from
// the archived spec.md's "## Decisions" section so delta.md never shows a
// false vacancy. A decision lead = the paragraph's first line carrying a
// "label: sentence" shape. Returns [] when the section or leads are absent.
function specDecisionTitles(specPath) {
  let text;
  try { text = fs.readFileSync(specPath, 'utf8'); } catch { return []; }
  const head = text.match(/^## Decisions[^\n]*$/m);
  if (!head) return [];
  const after = text.slice(head.index + head[0].length);
  const nextSec = after.search(/^## /m);
  const section = nextSec === -1 ? after : after.slice(0, nextSec);
  const titles = [];
  // Per-line lead matching (paragraph splitting merged adjacent decision
  // lines into one block). A lead = "Decision-token [(label)]: sentence" or
  // "D-NN: sentence" at line start within the Decisions section.
  const LEAD_RE = /^((?:D-\d+|Decision[\w-]{1,32})(?:\s*\([^)\n]{1,50}\))?[^:\n]{0,16}):\s*(\S.*)$/;
  for (const line of section.split('\n')) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const lead = t.match(LEAD_RE);
    if (lead) titles.push(`${lead[1].trim()}: ${lead[2].trim()}`);
  }
  return titles;
}

function archiveDirExists(date, slug) {
  if (!fs.existsSync(core.ARCHIVE_DIR)) return false;
  const base = `${date}-${slug}`;
  return fs.readdirSync(core.ARCHIVE_DIR).some((d) => d === base || new RegExp(`^${base}-\\d+$`).test(d));
}

// SHIP ledger: counts-only provenance of how this task crossed its gates,
// rendered at ship for human final review. Approval provenance reads the
// three-tier vocabulary: delegated records render as mechanical clearance
// with their trust flavor (store-verified pairs live machine-local store
// stamps; unpaired cleared records read pre-loop legacy — advisory here,
// never a hold), a lingering PENDING is a clearance still awaiting runner
// verification, and legacy string approvals are explicit human acts.
// Progress-release evidence (red-team rounds) and VERIFY truth counts
// follow. Evidence detail (hashes, session ids, output tails) stays
// machine-local — only counts and tier labels render here.
function shipLedgerLines(state) {
  const approvals = (state && state.approvals) || {};
  let stamps;
  try {
    const autoStore = require('../ops/auto/store.cjs');
    const loaded = autoStore.load();
    if (loaded.ok && autoStore.isPlainObject(loaded.store.stamps)) stamps = loaded.store.stamps;
  } catch { /* advisory: without readable stamps, cleared records read pre-loop legacy */ }
  const describe = (v) => {
    try { return require('../ops/auto/ratify.cjs').describeApproval(v, { stamps }); }
    catch { return null; }
  };
  const mechanical = [];
  let pendingCount = 0;
  let humanCount = 0;
  for (const name of Object.keys(approvals)) {
    const v = approvals[name];
    if (v != null && typeof v === 'object') {
      if (v.mode === 'auto') {
        const desc = describe(v);
        if (desc === 'cleared (store-verified)') mechanical.push(`${name} (store-verified)`);
        else if (desc === 'cleared (pre-loop legacy)') mechanical.push(`${name} (pre-loop legacy)`);
        else if (desc === 'claimed-not-verified') mechanical.push(`${name} (claimed-not-verified, held for human)`);
        else if (desc === 'pending') { mechanical.push(`${name} (pending)`); pendingCount++; }
        else humanCount++;
      } else humanCount++;
    } else if (typeof v === 'string' && v) humanCount++;
  }
  const truths = Array.isArray(state && state.observable_truths) ? state.observable_truths : [];
  const verifiedCount = truths.filter((t) => t && t.verified === true).length;
  const rtRounds = Array.isArray(state && state.redteam_rounds) ? state.redteam_rounds : [];
  const rtFindings = rtRounds.reduce((n, r) => n + ((r && Number.isInteger(r.findings)) ? r.findings : 0), 0);
  return [
    'SHIP ledger — human final review:',
    `  mechanical clearance: ${mechanical.length ? mechanical.join(', ') : 'none (every gate crossed by explicit human approval)'}`,
    `  human approvals: ${humanCount}${pendingCount ? ` (+${pendingCount} pending)` : ''}`,
    `  VERIFY truths: ${verifiedCount}/${truths.length} verified`,
    `  progress release: red-team findings ${rtFindings} across ${rtRounds.length} round(s)`,
  ];
}

// Newest archive dest holding task/<tid> — the tid's current archive home.
// The slug is just a name; the tid is the identity: a dest containing the id
// marks that this task's directory already moved.
function archivedTidHomeDir(state) {
  const tid = core.currentTaskId(state);
  if (!tid || !fs.existsSync(core.ARCHIVE_DIR)) return null;
  const dirs = fs.readdirSync(core.ARCHIVE_DIR)
    .filter((d) => fs.existsSync(path.join(core.ARCHIVE_DIR, d, 'task', tid)))
    .sort();
  return dirs.length ? dirs[dirs.length - 1] : null;
}

// Registered state paths resolve into .gos/archive/<home>/ — direct fields
// must live there; nested evidence paths only disqualify when they still
// point at the live task zone (evidence may legitimately live outside .gos).
function statePathsResolveIntoArchiveHome(state, home) {
  const prefix = `${path.join(path.relative('.', core.ARCHIVE_DIR), home)}${path.sep}`;
  const tid = core.currentTaskId(state);
  for (const f of core.STATE_PATH_FIELDS.direct) {
    const v = state[f];
    if (typeof v === 'string' && v && !v.startsWith(prefix)) return false;
  }
  if (tid) {
    const liveZone = `.gos${path.sep}task${path.sep}${tid}${path.sep}`;
    for (const t of state.observable_truths || []) {
      const ap = t && t.evidence && t.evidence.artifact_path;
      if (typeof ap === 'string' && ap && ap.startsWith(liveZone)) return false;
    }
  }
  return true;
}

// Archived-idle path evidence: the tid lives in an archive dest whose layout
// the state's own paths agree with. Consumed by the gate idle branch and the
// tid idempotency check — a state whose paths still point at the live task
// zone is NOT idle: it still needs the archive repair pass.
function archivedTidIdle(state) {
  const home = archivedTidHomeDir(state);
  return !!home && statePathsResolveIntoArchiveHome(state, home);
}

// Half-transaction completion: an archive dest already holds task/<tid>, the
// live task dir is gone, the state is approved but not yet stamped DONE (the
// crash window between dest materialization and writeState — direct rerun or
// the commit-chain catch). Registry-driven rewrites + DONE + completed_at
// land on disk; true when the completion ran, false when no dest matched.
function landHalfTransaction(state) {
  const tid0 = core.currentTaskId(state);
  const taskDir0 = tid0 ? path.join(core.GOS_DIR, 'task', tid0) : null;
  if (state.current_stage === 'DONE' || !(state.approvals || {}).ARCHIVE || !tid0 || fs.existsSync(taskDir0)) return false;
  const cands = fs.existsSync(core.ARCHIVE_DIR)
    ? fs.readdirSync(core.ARCHIVE_DIR).filter((d) => {
        const p = path.join(core.ARCHIVE_DIR, d, 'task', tid0);
        return fs.existsSync(p);
      }).sort()
    : [];
  if (!cands.length) return false;
  const done = path.join(core.ARCHIVE_DIR, cands[cands.length - 1]);
  const relDone = path.relative('.', done);
  // Field-level rewrite per the registry (full-text replace forbidden)
  for (const f of core.STATE_PATH_FIELDS.direct) {
    const v = state[f];
    if (typeof v === 'string' && v.includes(`.gos/task/${tid0}/`)) state[f] = v.replace(`.gos/task/${tid0}/`, `${relDone}/task/${tid0}/`);
  }
  for (const t of state.observable_truths || []) {
    const ev = t && t.evidence;
    if (ev && typeof ev.artifact_path === 'string' && ev.artifact_path.includes(`.gos/task/${tid0}/`)) ev.artifact_path = ev.artifact_path.replace(`.gos/task/${tid0}/`, `${relDone}/task/${tid0}/`);
  }
  state.current_stage = 'DONE';
  state.checkpoints = [];
  state.completed_at = new Date().toISOString();
  core.writeState(state);
  console.log(`✓ ship: half-transaction completed idempotently (dest was materialized, state now written) → ${relDone}`);
  // Returning (never exiting) keeps the commit-chain caller alive: the git
  // commit that finalizes the staged renames still has to run.
  return true;
}

function cmdArchive(opts = {}) {
 const fromCommit = !!opts.fromCommit; // invoked from cmdCommit — gates degrade to warn+skip (never kill the commit mid-flow)
 if (!fromCommit) core.humanGateGuard('archive'); // direct invocation is the human act; the commit-chain call is not
  // Registry-driven walker: one traversal for direct + nested fields (single-source consumption —
  // newly registered fields are picked up by the rewrite/normalization automatically)
  const walkPaths = (obj, fn) => {
    for (const f of core.STATE_PATH_FIELDS.direct) obj[f] = fn(obj[f], [f]);
    for (const pathArr of core.STATE_PATH_FIELDS.nested) {
      const [arrKey, subKey, valKey] = pathArr;
      for (const item of obj[arrKey] || []) {
        const sub = item && item[subKey];
        if (sub) sub[valKey] = fn(sub[valKey], pathArr);
      }
    }
  };
  // Recovery load: two signature-matched surgical repairs when readState refuses to load
  // (registry field-level rewrites only — never a full-text replace):
  //  ① half-transaction (crash window): approved + task/<id>/ already moved + an archive dest
  //     contains that id → rewrite paths to the new home
  //  ② absolute-path state: repo-root-prefixed absolute paths → relativized
  // Any other signature keeps the original noActiveTask die semantics (no overreaching repair).
  const state = (function loadStateWithRecovery() {
    // write-class commands (entry:147) make readState fail strictly — the recovery path first
    // loads leniently to inspect the damage: only the two signatures (half-transaction /
    // absolute paths) trigger surgical repair; otherwise strict mode is restored and the
    // original die semantics apply.
    const prevMode = core.readState._mode;
    core.readState._mode = 'read';
    const st = core.readState();
    if (!st) { core.readState._mode = prevMode; core.die(core.CONTRACTS.state_semantics.noActiveTask); }
    const tid = core.currentTaskId(st);
    const root = core.currentRootRealpath();
    let absFixed = false;
    const norm = (v) => (typeof v === 'string' && path.isAbsolute(v) && root && v.startsWith(root + path.sep) ? ((absFixed = true), path.relative(root, v)) : v);
    walkPaths(st, (v) => norm(v));
    let halfTx = false;
    if (tid && (st.approvals || {}).ARCHIVE && st.current_stage !== 'DONE') {
      const taskDir = path.join(core.GOS_DIR, 'task', tid);
      if (!fs.existsSync(taskDir) && fs.existsSync(core.ARCHIVE_DIR)) {
        const cands = fs.readdirSync(core.ARCHIVE_DIR).filter((d) => fs.existsSync(path.join(core.ARCHIVE_DIR, d, 'task', tid))).sort();
        if (cands.length) {
          halfTx = true;
          const relD = path.relative('.', path.join(core.ARCHIVE_DIR, cands[cands.length - 1]));
          const rw = (v) => (typeof v === 'string' && v.includes(`.gos/task/${tid}/`) ? v.replace(`.gos/task/${tid}/`, `${relD}/task/${tid}/`) : v);
          for (const f of core.STATE_PATH_FIELDS.direct) st[f] = rw(st[f]);
          for (const t of st.observable_truths || []) if (t && t.evidence) t.evidence.artifact_path = rw(t.evidence.artifact_path);
        }
      }
    }
    if (!absFixed && !halfTx) {
      // No recovery signature matched → restore write-class strict loading (original die semantics kept)
      core.readState._mode = prevMode;
      const s2 = core.readState();
      if (!s2) core.die(core.CONTRACTS.state_semantics.noActiveTask);
      return s2;
    }
    core.validateState(st, 'fail');   // validate after repair, before persisting — bad values never touch disk
    core.writeAtomicJson(core.resolvePath('state'), st);
    core.readState._mode = prevMode;
    const st2 = core.readState();
    if (!st2) core.die(core.CONTRACTS.state_semantics.noActiveTask);
    console.log(`⚠ archive: recovery-load applied (${[halfTx && 'half-transaction path rewrite', absFixed && 'absolute-path normalization'].filter(Boolean).join(' + ') || 'no-op'}) — STATE_PATH_FIELDS registry-driven`);
    return st2;
  })();
  if (!state) core.die(core.CONTRACTS.state_semantics.noActiveTask);

 // ---- : lessons enforcement (fail-closed)
  // If this task had gaps or red-team findings, a lesson MUST be recorded first.
  const gapCount = (state.gaps || []).length; // any gap history counts
  const rtFindings = ((state.redteam_rounds || []).reduce((n, r) => n + (r.findings || 0), 0)) || 0;
  const hadIncidents = gapCount > 0 || rtFindings > 0;
  // cleanup-scan pre-archive (wired enforcement — script verdict, not model claim)
  const cleanupScript = path.join(core.GOS_SELF_ROOT, 'skills', 'gos-ship', 'scripts', 'cleanup-scan.sh');
  if (fromCommit) { /* commit-invoked: adoption-only, ritual gates live in direct gos archive */ }
  else if (fs.existsSync(cleanupScript)) {
    const scan = core.tryCmd(`bash ${core.shellQ(cleanupScript)}`);
    if (!scan.ok) {
      console.error(`${core.CONTRACTS.state_semantics.archiveBlocked} (cleanup-scan):`);
      console.error(scan.out.split('\n').slice(0, 12).join('\n'));
      console.error('Fix Critical/Major findings, re-run, then archive.');
      process.exit(1);
    }
    console.log('✓ cleanup-scan clean');
  }
  // ---- SHIP ritual gate — batch changelog record (fail-closed) + version discipline (warn) ----
  // Structural obligation: this task's batch must ADD a changelog record.
  // The shared predicate (changelog-core.batchAddsChangelogRecord) compares
  // the working-tree changelog against the task_head baseline snapshot — a
  // just-written uncommitted bullet counts, and a stale-dated bullet written
  // inside the batch counts too (the date stamp is writer metadata, not the
  // obligation). Refs must intersect the task's own decision + requirement
  // ids. Non-git repos use the file-shape fallback ([Unreleased] non-empty).
  // A missing CHANGELOG.md blocks with the bootstrap advisory — the
  // next `gos changelog add` creates the file from the master template. The
  // version warn below compares the latest git tag against package.json by
  // design; CHANGELOG.md is deliberately not consulted for version truth.
  // GOS_SKIP_SHIP_CHECK=1 skips both (tests / non-release archives).
  if (!fromCommit && process.env.GOS_SKIP_SHIP_CHECK !== '1') {
 // ---- /: PROJECT.md pre-flight — same slot as the SHIP ritual
    // Validate-then-mutate (lesson 8a11d879): the refusal lands BEFORE any
    // project.json mutation, task collection (staging), or auto-render, so a
    // skeleton PROJECT.md never strands a half-archived phase. Applies only
    // when a PROJECT.md exists (plain tasks seed none).
    {
      const pmPath = path.join(core.PROJECT_DIR, 'PROJECT.md');
      let pmText = null;
      if (fs.existsSync(pmPath)) { try { pmText = fs.readFileSync(pmPath, 'utf8'); } catch { /* unreadable */ } }
      if (pmText !== null) {
        const report = phasegate.projectMdSectionReport(pmText);
        if (report.sections.length === 0 || report.lacking.length > 0) {
          console.error(`${core.CONTRACTS.state_semantics.archiveBlocked} (PROJECT.md gate):`);
          if (report.sections.length === 0) {
            console.error('  ✗ .gos/project/PROJECT.md carries no `## ` section — a filled project vision needs at least one.');
          } else {
            console.error(`  ✗ .gos/project/PROJECT.md has ${report.lacking.length} unfilled section(s): ${report.lacking.map((s) => s.name).join(', ')}`);
          }
          console.error('  Fix: fill every `## ` section (replace the TODO guidance lines with real content, at least 20 codepoints per section), then re-run `gos archive`.');
          process.exit(1);
        }
      }
    }
  // the obligation reads through the single root-anchored resolver
    // a relocated changelog (gos config changelog-path) is honored here.
    let changelogText = null;
    const changelogAbs = clcore.resolveChangelogMd();
    try { changelogText = fs.readFileSync(changelogAbs, 'utf8'); } catch { /* absent */ }
    if (changelogText === null) {
      console.error(`${core.CONTRACTS.state_semantics.archiveBlocked} (SHIP ritual):`);
      console.error('  ✗ SHIP BLOCKED: CHANGELOG.md not found — obligations start once the file exists');
      console.error('    Run `gos changelog add --summary "<one sentence>"` first (it bootstraps CHANGELOG.md from the master template), then re-run `gos archive`.');
      process.exit(1);
    }
    const shipTaskRefs = [];
    {
      const seen = new Set();
      const push = (id) => {
        const t = String(id);
        if (/^[DR]-\d+$/.test(t) && !seen.has(t)) { seen.add(t); shipTaskRefs.push(t); }
      };
      for (const d of state.decisions || []) if (d && d.id) push(d.id);
      for (const r of state.requirements || []) if (r && r.id) push(r.id);
    }
    const shipVerdict = (() => {
      if (!core.gitInWorkTree()) {
        return clcore.batchAddsChangelogRecord(changelogText, null, { taskRefs: shipTaskRefs });
      }
      const th = typeof state.task_head === 'string' && /^[0-9a-f]{8,40}$/i.test(state.task_head) ? state.task_head : null;
      if (!th) {
        console.error(`${core.CONTRACTS.state_semantics.archiveBlocked} (SHIP ritual):`);
        console.error('  ✗ SHIP BLOCKED: the live task carries no task_head — the changelog record check needs the batch baseline commit');
        console.error('    Re-claim the task (`gos init`) or re-run its stage commits so task_head re-anchors the diff baseline, then re-run `gos archive`.');
        process.exit(1);
      }
      if (!core.shaReachable(th)) {
        console.error(`${core.CONTRACTS.state_semantics.archiveBlocked} (SHIP ritual):`);
        console.error(`  ✗ SHIP BLOCKED: task_head ${th.slice(0, 10)} is unreachable in this git repo — the batch baseline snapshot cannot be read`);
        console.error('    Fetch the full history (git fetch --unshallow) or re-anchor the task (gos init), then re-run `gos archive`.');
        process.exit(1);
      }
      const top = core.gitToplevelRealpath();
      const rel = top ? path.relative(top, changelogAbs).split(path.sep).join('/') : null;
      if (!rel) {
        // in a work tree yet the toplevel will not resolve — no baseline
        // snapshot can be read; degrade loudly to the file-shape fallback
        console.log('⚠ ship changelog check: repo toplevel unresolvable — falling back to the file-shape check ([Unreleased] non-empty)');
        return clcore.batchAddsChangelogRecord(changelogText, null, { taskRefs: shipTaskRefs });
      }
      // base snapshot: the file as it stood at task_head; absent there means
      // every current bullet is new (the whole changelog is this batch's record).
      // Three-state shared helper: a git failure is {ok:false} — fail closed,
      // never conflated with absence (which would satisfy the obligation vacuously)
      const snap = clcore.showPathSnapshot(th, rel);
      if (!snap.ok) {
        console.log('⚠ ship changelog check: base snapshot unreadable — failing closed');
        return { ok: false, reason: 'base-unreadable' };
      }
      // absent-from-base means the whole changelog is this batch's record
      // (empty base text), never the file-shape fallback trigger (null)
      return clcore.batchAddsChangelogRecord(changelogText, snap.text == null ? '' : snap.text, { taskRefs: shipTaskRefs });
    })();
    if (!shipVerdict.ok) {
      console.error(`${core.CONTRACTS.state_semantics.archiveBlocked} (SHIP ritual):`);
      console.error(`  ✗ SHIP BLOCKED: this batch adds no changelog record (${shipVerdict.reason}) — nothing new in CHANGELOG.md against the task_head baseline`);
      console.error('    Run `gos changelog add` to write this batch\'s entry, then re-run `gos archive`.');
      process.exit(1);
    }
    let ver = 'unknown';
    try { ver = core.PKG.version; } catch { /* no package.json */ }
    const tag = core.safeGitArgv(['describe', '--abbrev=0', '--tags']).trim() || 'none';
    console.log(`⚠ version discipline: package.json=${ver} latest tag=${tag} — bump if this is a version-level iteration`);
  }
  // stage-gate approval: archive = user accepts delivery (explicit act only)
  if (!(state.approvals || {}).ARCHIVE) {
    if (fromCommit) { console.log('⚠ post-commit archive skipped (no `gos approve archive` yet) — orphan adoption deferred to gos archive'); return; }
    console.error(`${core.CONTRACTS.state_semantics.archiveBlocked} (${core.CONTRACTS.state_semantics.approvalGate}):`);
    console.error('  Archive marks the task DONE — that is the USER\'s call, not the model\'s.');
    console.error('  Present the delivery summary, get acceptance, then `gos approve archive`.');
    process.exit(1);
  }
  if (hadIncidents) {
    // incident → two-of-one: a lesson for THIS task (either side) OR a skip
    // covering the current incident count. Task-anchored audit rows (the
    // details.task payload flattened onto the row by appendAuditRow) satisfy
    // across calendar days — the lessons gate follows the task lifecycle,
    // not the wall clock. Unanchored legacy rows keep the today-only match
    // of the pre-anchor era.
    const today = new Date().toISOString().slice(0, 10);
    const tid = core.currentTaskId(state);
    const incidentsNow = gapCount + rtFindings;
    const projDisp = knowledge.loadStoreDisplay(core.lessonsPaths('project'));
    const globDisp = knowledge.loadStoreDisplay(core.lessonsPaths('model'));
    const auditOf = (disp) => ((disp.ok && disp.store && Array.isArray(disp.store.audit)) ? disp.store.audit : []);
    const hasTaskLesson = (disp) => {
      if (!disp.ok || !disp.store || !Array.isArray(disp.store.entries)) return false;
      const live = new Set(disp.store.entries.map((e) => (e ? e.id : null)));
      // add rows anchor the original entry; edit rows re-anchor the amended
      // successor (an amend must not silently drop the task anchor)
      return auditOf(disp).some((r) => r && (r.what === 'add' || r.what === 'edit') && r.new_id && r.task === tid && live.has(r.new_id));
    };
    // legacy fallback: entry dated today whose add row carries no task anchor
    const legacyTodayIn = (disp) => {
      if (!disp.ok || !disp.store || !Array.isArray(disp.store.entries)) return false;
      const anchorOf = new Map(auditOf(disp).filter((r) => r && r.what === 'add' && r.new_id).map((r) => [r.new_id, r.task || null]));
      return disp.store.entries.some((e) => e && e.at === today && !anchorOf.get(e.id));
    };
    const hasLesson = hasTaskLesson(projDisp) || hasTaskLesson(globDisp) || legacyTodayIn(projDisp) || legacyTodayIn(globDisp);
    // skip exemption: an anchored skip must cover the current incident
    // snapshot (re-arms on new incidents); a legacy unanchored skip exempts
    // this archive only when taken today
    let skipInfo = null;
    const skips = auditOf(projDisp).filter((r) => r && r.what === 'skip');
    const exempts = skips.filter((r) => (r.task === tid && Number.isInteger(r.incidents) && r.incidents >= incidentsNow)
      || (!r.task && String(r.at || '').startsWith(today)));
    if (exempts.length) skipInfo = { count: skips.length, last: exempts[exempts.length - 1] };
    if (!hasLesson && !skipInfo) {
      console.error(`${core.CONTRACTS.state_semantics.archiveBlocked} (F-1 lessons enforcement):`);
      console.error(`  This task had ${gapCount} gap(s) / ${rtFindings} red-team finding(s).`);
      console.error('  Record a lesson for this task first (either side counts):');
      console.error(`    gos lessons add --type project --scene "<scene>" --lesson "<what changed>"`);
      console.error(`    gos lessons add --type model --scene "<scene>" --lesson "<what changed>"`);
      console.error('  …or take the explicit exemption (re-arms on new incidents):');
      console.error('    gos lessons skip --reason "<why this residual risk is accepted>"');
      console.error('  Then re-run `gos archive`.');
      process.exit(1);
    }
    if (skipInfo && !hasLesson) {
      console.log(`⚠ F-1 exemption taken — last skip reason: ${skipInfo.last.why} (cumulative skips: ${skipInfo.count})`);
    }
  }

  // ---- B-21 [R4-F8]: archive-side drift check — frozen snapshot vs final plan.md (warn only) ----
  if (state.plan_snapshot && Array.isArray(state.plan_snapshot.tasks) && fs.existsSync(core.planPathOf(state))) {
    try {
      const liveTasks = sibPlansnap.buildPlanSnapshotTasks(sibPlansnap.parsePlanMd());
      const snapMap = new Map(state.plan_snapshot.tasks.map((t) => [t.id, t]));
      let drift = liveTasks.length !== state.plan_snapshot.tasks.length;
      if (!drift) {
        for (const lt of liveTasks) {
          const st = snapMap.get(lt.id);
          if (!st) { drift = true; break; }
          if (JSON.stringify([...(st.covers || [])].sort()) !== JSON.stringify([...(lt.covers || [])].sort()) ||
              JSON.stringify([...(st.files || [])].sort()) !== JSON.stringify([...(lt.files || [])].sort())) { drift = true; break; }
        }
      }
      if (drift) {
        let dirty = false;
        try {
          const so = execFileSync('git', ['status', '--porcelain', '--', core.planPathOf(state)], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
          dirty = so.trim().length > 0;
        } catch { /* non-git */ }
        console.log(`⚠ plan.md drifted from frozen plan_snapshot (B-21)${dirty ? ' and has uncommitted changes' : ''} — re-commit plan (PLAN stage) or archive knowingly`);
      }
    } catch (e) { if (e && e.message) console.log(`⚠ plan drift check skipped: ${String(e.message).split('\n')[0]}`); }
  }

 // DRY: slug logic lives in sibContext.archiveSlugParts (single source — the
  // context SHIP preview consumes the same function, no drift)
  const { date, slug } = sibContext.archiveSlugParts(state);
  // ---- : idempotency — DONE + archived tid + (completed_at or paths already home)
  // tid-based idempotency: re-running archive on an already-archived task after a slug change
  // (version bump / date rollover) is a no-op while an archive dest contains this task id
  // AND the state's own paths agree with that home — completed_at stamped, or the
  // STATE_PATH_FIELDS rewrites already landed. A stamp whose tid never archived falls
  // through (nothing to be idempotent about); an archived tid whose paths still point at
  // the live .gos/task/<tid>/ zone falls through too — the full archive path below
  // performs the repair (path rewrite + stamp) instead of no-op'ing.
  {
    const tidIdem = core.currentTaskId(state);
    const homeIdem = archivedTidHomeDir(state);
    if (state.current_stage === 'DONE' && tidIdem && homeIdem && (state.completed_at || statePathsResolveIntoArchiveHome(state, homeIdem))) {
      if (fromCommit) return;
      console.log(`${core.CONTRACTS.command_contracts.archiveIdempotent} — nothing to do (task ${tidIdem} already archived)`);
      process.exit(0);
    }
  }
  if (state.current_stage === 'DONE' && state.completed_at && archiveDirExists(date, slug)) {
    if (fromCommit) return; // commit flow continues — nothing to adopt
    console.log(`${core.CONTRACTS.command_contracts.archiveIdempotent} — nothing to do`);
    process.exit(0);
  }
  // ---- half-transaction completion (crash window: dest materialized but writeState never ran) ----
  // Scenario: the previous run crashed after Phase B and before writeState → the directory has
  // moved, state is still pre-DONE. Detection + repair live in landHalfTransaction (shared with
  // the commit-chain catch): rewrite paths per the registry, land DONE + completed_at — no new
  // dest, no double adoption.
  if (landHalfTransaction(state)) return;
  // ---- pre-flight: path normalization (absolute → project_root-relative) + validate before touching files ----
  if (process.env.GOS_TEST_BREAK_SHIP === 'pre-flight') throw new Error('GOS_TEST_BREAK_SHIP: injected pre-flight failure (nothing materialized)');
  {
    const root0 = core.currentRootRealpath();
    const norm = (v) => (typeof v === 'string' && path.isAbsolute(v) && root0 && v.startsWith(root0 + path.sep) ? path.relative(root0, v) : v);
    for (const f of core.STATE_PATH_FIELDS.direct) state[f] = norm(state[f]);
    for (const t of state.observable_truths || []) {
      if (t && t.evidence && typeof t.evidence.artifact_path === 'string') t.evidence.artifact_path = norm(t.evidence.artifact_path);
    }
    core.validateState(state, 'fail');   // pre-validate: fail fast at zero cost on a pre-existing bad state (the main repair is the adoption rewrite below)
  }
 // ---- : dest collision — same-day same-slug task appends -2, -3... until free
  let dest = path.join(core.ARCHIVE_DIR, `${date}-${slug}`);
  for (let i = 2; fs.existsSync(dest); i++) dest = path.join(core.ARCHIVE_DIR, `${date}-${slug}-${i}`);
  fs.mkdirSync(dest, { recursive: true });
  // spec/plan fallback to the canonical paths (pre-existing null spec_path state —
  // SHIP-dogfood fix: every other consumer falls back to '.gos/spec.md', moves didn't)
 // ---- Phase W: two-phase ship transaction + orphan adoption
  // Phase A: stage everything into .gos/.ship-staging/ — tracked via `git mv` (rename
  // history preserved), untracked via fs.renameSync. Any failure rolls staging back to
  // the original paths; nothing half-moves. Phase B: git add + rename staging → dest +
  // commit. Idempotent re-entry: leftover staging from a crashed run is restored first.
  const staging = core.resolvePath('ship_staging');
  let moved = 0; // hoisted for the final archived summary line
 // /: gitprobe is the only fail-closed probing
  // primitive. Its ignored-scan truth source lists exact files and collapses
  // covered directories to a single trailing-slash entry, so "rel is ignored"
  // = rel itself listed, or rel living under a listed directory — the same
  // recursive verdict the retired one-shot probe gave.
  const isIgnoredRel = (ignored, rel) => ignored.has(rel) || ignored.has(rel + '/')
    || [...ignored].some((e) => e.endsWith('/') && (rel + '/').startsWith(e));
  const gitMvOrRename = (src, dst) => {
    const trackedSrc = core.safeGitArgv(['ls-files', '--error-unmatch', path.relative(process.cwd(), src)]) !== '';
    // Machine-local archive policy: when the destination is gitignored, a
    // tracked source must leave the index (rm --cached) instead of git-mv —
    // `git mv` stages the target explicitly and would smuggle archive
    // content back into the index past the ignore rule.
    // dst never exists yet (only its parent does, created just above), so the
    // repo-relative spelling rides the parent's canonical form. Any git
    // failure fails closed the same way the old probe's '' → false did:
    // canonicalRepoRel → null, ignoredSet → empty set → dstIgnored false.
    const parentRel = core.canonicalRepoRel(path.dirname(dst));
    const dstIgnored = parentRel != null && isIgnoredRel(core.ignoredSet(), `${parentRel}/${path.basename(dst)}`);
    if (trackedSrc && !dstIgnored) {
      try {
        execFileSync('git', ['mv', path.relative(process.cwd(), src), path.relative(process.cwd(), dst)], { stdio: ['ignore', 'pipe', 'ignore'] });
      } catch (e) {
        // [REVIEW hotfix] mixed tracked/untracked dirs can fail `git mv` — fall back to a
        // plain rename (atomic, content-preserving; rename-history granularity is lost for
        // this directory but the two-phase transaction guarantees are untouched)
        try { fs.renameSync(src, dst); }
        catch (e2) { throw new Error(`git mv and rename both failed for ${src}: ${e.message} / ${e2.message}`); }
      }
    } else if (trackedSrc && dstIgnored) {
      try { execFileSync('git', ['rm', '--cached', '-q', path.relative(process.cwd(), src)], { stdio: ['ignore', 'pipe', 'ignore'] }); } catch { /* already out of index */ }
      fs.renameSync(src, dst);
    } else fs.renameSync(src, dst);
  };
  const restoreStaging = () => {
    if (!fs.existsSync(staging)) return;
    const moveMerge = (from, to) => {
      // dir→existing dir must MERGE (rename fails EEXIST/ENOTEMPTY across existing dirs)
      for (const e of fs.readdirSync(from)) {
        const f = path.join(from, e), t = path.join(to, e);
        if (fs.statSync(f).isDirectory() && fs.existsSync(t) && fs.statSync(t).isDirectory()) moveMerge(f, t);
        else { try { if (fs.existsSync(t)) fs.rmSync(t, { recursive: true, force: true }); } catch { /* best effort */ } fs.renameSync(f, t); }
      }
      try { fs.rmdirSync(from); } catch { /* best effort */ }
    };
    for (const e of fs.readdirSync(staging)) {
      const back = path.join(core.GOS_DIR, e);
      if (fs.existsSync(back) && fs.statSync(back).isDirectory() && fs.statSync(path.join(staging, e)).isDirectory()) moveMerge(path.join(staging, e), back);
      else { try { if (fs.existsSync(back)) fs.rmSync(back, { recursive: true, force: true }); } catch { /* best effort */ } fs.renameSync(path.join(staging, e), back); }
    }
    try { fs.rmdirSync(staging); } catch { /* non-empty → keep for forensics */ }
  };
  // ① idempotent re-entry: crashed previous run left staging behind → restore, then redo
  if (fs.existsSync(staging)) {
    restoreStaging();
    console.log('⚠ ship: recovered interrupted staging from previous run (idempotent re-entry)');
  }
  fs.mkdirSync(staging, { recursive: true });
  const rollback = (err) => {
    restoreStaging();
    core.die(`✗ ship transaction failed, staging rolled back: ${err.message || err}`);
  };
  try {
    // ② stage task/<id>/ (spec/plan/evidence — the whole phase dir moves atomically)
    const { tid, dir: taskDir } = (() => ({ tid: core.currentTaskId(state), dir: path.join(core.GOS_DIR, 'task', core.currentTaskId(state) || '') }))();
    if (tid && fs.existsSync(taskDir)) {
      // keep the full task/<id> hierarchy in staging (never flatten the id layer —
      // rollback must land the dir back exactly where it came from)
      const stTaskId = path.join(staging, 'task', tid);
      fs.mkdirSync(path.dirname(stTaskId), { recursive: true });
      gitMvOrRename(taskDir, stTaskId);
      moved++;
    } else {
 // legacy: spec/plan loose at root (pre- states)
      for (const p of [core.specPathOf(state), core.planPathOf(state)]) {
        if (fs.existsSync(p)) { gitMvOrRename(p, path.join(staging, path.basename(p))); moved++; }
      }
    }
 // ③ orphan adoption : registry-external files, with guards
    //    - mtime quiet period <5min → skip + rescan-exempt (never mv in-flight BUILD files)
    //    - active anchor lock (.anchors.lock) → refuse adoption entirely
    const adoptDir = path.join(dest, 'orphans');
    const now = Date.now();
    const anchorLock = path.join(core.GOS_DIR, '.anchors.lock');
    const anchorLockHeld = fs.existsSync(anchorLock) && (Date.now() - fs.statSync(anchorLock).mtimeMs < 120000);
    const orphanTier = ops.detectOrphans(state);
    if (orphanTier.probeFailure && orphanTier.probeFailure !== 'no-git') {
      // fail-closed: adoption is destructive relocation — without git truth
      // nothing moves (the tier reports every candidate as tracked-side, so
      // the rescan below stays consistent with what was refused)
      console.log(`⚠ orphan adoption refused — git probe unavailable: ${orphanTier.probeFailure}`);
    }
    const orphans = orphanTier.orphans;
    const adopted = [], skipped = [];
    for (const rel of orphans) {
      const src = path.join(core.GOS_DIR, rel);
      let st; try { st = fs.statSync(src); } catch { continue; }
      if (now - st.mtimeMs < 5 * 60 * 1000) { skipped.push(rel); continue; } // quiet-period exempt
      if (anchorLockHeld) { skipped.push(rel); console.log(`⚠ anchor lock held — orphan adoption deferred: ${rel}`); continue; }
 // adoption goes through staging too — "nothing half-moves" holds:
      // rollback restores staged orphans along with task/<id>/, dest only materializes in Phase B
      const dstRel = path.join('orphans', rel);
      const dstAbs = path.join(staging, dstRel);
      fs.mkdirSync(path.dirname(dstAbs), { recursive: true });
      // phase-owned orphans: task/<code>/ residue routes to that phase's archive dir
      const m = rel.match(/^task\/([a-z0-9][a-z0-9_-]*)\//i); // [REVIEW P2-F11] include '-' so ts-<epoch> ids route
      if (m && m[1].toLowerCase() !== String(tid || '').toLowerCase()) {
        const candidates = fs.existsSync(core.ARCHIVE_DIR) ? fs.readdirSync(core.ARCHIVE_DIR).filter((d) => d.includes(`phase-${m[1]}-`) || d.includes(`-phase-${m[1]}-`)) : [];
        if (candidates.length) {
 const dirName = candidates.sort().pop(); // pop once, reuse for the log line
          const target = path.join(staging, 'reroute', dirName, path.basename(rel));
          fs.mkdirSync(path.dirname(target), { recursive: true });
          gitMvOrRename(src, target);
          adopted.push(`${rel} → archive/${dirName}/`);
          continue;
        }
      }
      gitMvOrRename(src, dstAbs);
      adopted.push(rel);
    }
    if (orphanTier.unregisteredTracked.length) {
      console.log(`⚠ ${orphanTier.unregisteredTracked.length} tracked file(s) lack GOS_PATHS registry entries — left in place (registry-gap):`);
      console.log('  ' + orphanTier.unregisteredTracked.join('\n  '));
    }
    if (process.env.GOS_TEST_BREAK_SHIP === 'staging') throw new Error('GOS_TEST_BREAK_SHIP: injected staging failure');
    // ④ Phase B: rename staging into the archive destination; reroute/<dir>/ lands in core.ARCHIVE_DIR/<dir>/
    if (process.env.GOS_TEST_BREAK_SHIP === 'phase-b') throw new Error('GOS_TEST_BREAK_SHIP: injected phase-b failure');
    const rerouteDir = path.join(staging, 'reroute');
    for (const e of fs.readdirSync(staging)) {
      if (e === 'reroute') continue;
      fs.renameSync(path.join(staging, e), path.join(dest, e));
    }
    if (fs.existsSync(rerouteDir)) {
      for (const dirName of fs.readdirSync(rerouteDir)) {
        const target = path.join(core.ARCHIVE_DIR, dirName);
        fs.mkdirSync(target, { recursive: true });
        for (const f of fs.readdirSync(path.join(rerouteDir, dirName))) {
          fs.renameSync(path.join(rerouteDir, dirName, f), path.join(target, f));
        }
      }
      fs.rmSync(rerouteDir, { recursive: true, force: true });
    }
    try { fs.rmdirSync(staging); } catch { /* keep */ }
    if (process.env.GOS_TEST_BREAK_SHIP === 'after-dest') throw new Error('GOS_TEST_BREAK_SHIP: injected after-dest failure (crash window: dest materialized, state not yet written)');
    // ⑤ rescan zero-assertion: non-transient orphans must be zero (manual adjudication on failure)
    const rest = ops.detectOrphans(state).orphans.filter((r) => !skipped.includes(r));
    if (rest.length) {
 // dest is born in THIS transaction — removing it avoids a half-archived
      // stray that rescan can never reach again (archive/ is the exempt zone)
      try { fs.rmSync(dest, { recursive: true, force: true }); } catch { /* best effort */ }
      restoreStaging();
      console.error(`✗ ship rescan: ${rest.length} orphan(s) remain — manual adjudication required:`);
      console.error('  ' + rest.join('\n  '));
      process.exit(1);
    }
    if (adopted.length) console.log(`✓ ship adoption: ${adopted.length} orphan(s) → ${dest.includes('archive') ? 'archive' : dest} (${skipped.length} quiet-period/lock exempt)`);
 // step6: README regen rides the ship transaction (machine-triggered)
  } catch (e) {
    rollback(e);
  }
  if (process.env.GOS_TEST_BREAK_SHIP === 'pre-stamp') throw new Error('GOS_TEST_BREAK_SHIP: injected pre-stamp failure (dest materialized, state unstamped)');
  // delta.md: what this phase changed (compact record)
  const delta = [
    `# Delta: ${core.sanitizeEcho(state.intent.summary)}`,
    ``,
    `- Level: Lv${state.level ?? '?'}`,
    `- user_summary: ${core.sanitizeEcho(state.changelog_user_summary ?? '')}`,
    `- Completed: ${state.completed_stages.join(' → ')}`,
    `- Decisions: ${state.decisions.map(d => `${d.id} ${d.title}`).join('; ') || (() => {
      const tidD = core.currentTaskId(state);
      const specTitles = tidD ? specDecisionTitles(path.join(dest, 'task', tidD, 'spec.md')) : [];
      return specTitles.length ? `${specTitles.join('; ')} (from spec.md)` : 'none recorded — see spec.md';
    })()}`,
    `- Truths: ${state.observable_truths.map(t => `${t.id} ${t.verified ? '✓' : '✗'}`).join(' ') || 'none'}`,
    `- Requirements: ${state.requirements.map(r => r.id).join(', ')}`,
  ].join('\n');
  fs.writeFileSync(path.join(dest, 'delta.md'), delta + '\n');
 // ---- : project.json integration (Lv4 truth source) — merge back, phase done, render views
  const project = core.loadProject();
  if (!project) {
    console.log(core.CONTRACTS.command_contracts.renderSkip); // no auto-vivify — truth source only via init --project / phase add
  } else {
 // merge state→project, upsert by id, STATE VERSION WINS (fixes amend-then-archive deadlock )
    const birthDefault = state.phase_name || 'legacy';
    const sDecs = Array.isArray(state.decisions) ? state.decisions : [];
    const sReqs = Array.isArray(state.requirements) ? state.requirements : [];
    for (const d of sDecs) {
      if (!d || !d.id) continue;
      const rec = { ...d };
      if (!rec.birth_phase) rec.birth_phase = birthDefault;
      const i = project.decisions.findIndex((x) => x && x.id === rec.id);
      if (i >= 0) project.decisions[i] = rec; else project.decisions.push(rec);
    }
    for (const r of sReqs) {
      if (!r || !r.id) continue;
      const i = project.requirements.findIndex((x) => x && x.id === r.id);
      if (i >= 0) project.requirements[i] = { ...r }; else project.requirements.push({ ...r });
    }
    if (state.phase_name) {
      const ph = project.phases.find((p) => p && p.name === state.phase_name);
      if (ph) {
        ph.status = 'done';
        // task_ref anchors the phase entry to the basename of the home THIS
        // run created (dest itself, never recomputed from slug parts). A
        // pre-existing stamp names an earlier home from a prior run and is
        // left verbatim — idempotent re-entry never re-stamps a different
        // value.
        if (ph.task_ref === undefined || ph.task_ref === null) ph.task_ref = path.basename(dest);
        ph.completed_at = state.completed_at || new Date().toISOString();
      }
      project.last_archived_phase = state.phase_name;
    }
    const allDone = project.phases.length > 0 && project.phases.every((entry) => entry && entry.status === 'done');
    if (allDone) {
      // Milestone closure is a dedicated verb: archive never wipes. The
      // final done phase only points the user at the close flow (snapshots
      // and the wipe live there, approval-gated).
      console.log(core.t('milestone.closeReadyHint', {}));
    } else {
      // [D-06/T3] milestone debt visibility: parked phases block completion (every(done))
      // — say so LOUDLY at the moment the user just archived, not silently never.
      const parkedLeft = project.phases.map((p, i) => ({ p, i })).filter((x) => x.p && x.p.status === 'parked');
      if (parkedLeft.length) {
        console.log(core.CONTRACTS.command_contracts.milestoneBlockedHeader);
        for (const x of parkedLeft) {
          console.log(`    parked: [${x.i}] ${x.p.name} — close out: \`gos phase park ${x.i} --undo\` then claim, or \`gos phase mark-done ${x.i}\` (explicit close-out)`);
        }
      }
    }
    // ANCHOR REWRITE: spec.md moved into this archive dir — current-phase anchors follow it.
    // Runs on every merge now: the all-done branch no longer wipes, so its
    // merged rows need the archive prefix too.
    const prefix = `.gos/archive/${path.basename(dest)}/`;
    for (const d of project.decisions) {
      if (d && typeof d.anchor === 'string' && (d.anchor.startsWith('spec.md') || d.anchor.startsWith('task/')) && d.birth_phase === state.phase_name) {
        d.anchor = prefix + d.anchor;
      }
    }
    core.saveProject(project);
    render.renderProjectViews(project);
    console.log('✓ rendered views (DECISIONS/ROADMAP/REQUIREMENTS)');
  }
  state.current_stage = 'DONE';
 // ---- : clear checkpoints (prevent pollution of next task's resume)
  state.checkpoints = [];
  state.completed_at = new Date().toISOString();
  // ---- adoption-time rewrite of state path references (registry field-level; full-text replace forbidden) ----
  // Root-cause fix for the 09-14 deadlock: writeState's validateState checks artifact_path
  // existence — once the directory has moved, the old paths are dead. Rewriting at adoption
  // keeps state consistent with the new home, so writeState passes on the first try.
  {
    const tidW = core.currentTaskId(state);
    if (tidW) {
      const relDest = path.relative('.', dest);
      const rw = (v) => (typeof v === 'string' && v.includes(`.gos/task/${tidW}/`) ? v.replace(`.gos/task/${tidW}/`, `${relDest}/task/${tidW}/`) : v);
      walkPaths(state, (v) => rw(v));
    }
  }
  core.writeState(state);
  console.log(`${core.CONTRACTS.state_semantics.archived} ${moved} file(s) + delta.md → ${path.relative('.', dest)}`);
  console.log('Next: state.json kept locally until you start a new task (gos init --force)');
  // SHIP ledger: auto-mode gate provenance for the human final review —
  // rendered BEFORE the push hint so the ready-to-run push line stays last.
  for (const line of shipLedgerLines(state)) console.log(line);
  // Remote publication hint: printed, never invoked — pushing stays a
  // user-executed act (message derives from [Unreleased] at push time).
  console.log(sibPush.archivePushHint());
}

const sibContext = require('./context.cjs');  // home of archiveSlugParts

module.exports = { archiveDirExists, archivedTidHomeDir, archivedTidIdle, cmdArchive, landHalfTransaction, specDecisionTitles, shipLedgerLines, statePathsResolveIntoArchiveHome };
