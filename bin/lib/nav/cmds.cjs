// nav/cmds — placement per aspect-rosters-v2.json
'use strict';

const core = require('../core/index.cjs');
const task = require('../task/plansnap.cjs');  // direct aspect require (dependency DAG)
const sibStatus = require('./status.cjs');
const knowledge = require('../knowledge/lessons-json.cjs');  // nav→knowledge (D-67 attribution; display-load, never throws)
const concernsMod = require('../knowledge/concerns.cjs');    // nav→knowledge (T5 gap rewrite boundary trigger path)
const fs = require('fs');
const path = require('path');

// lessons attribution block + tags-based progressive disclosure
// stage-relevant subset shown, remainder referenced via `gos lessons list`
// (never silently dropped).
function lessonsAttributionBlock(stage) {
  const attr = knowledge.lessonsAttribution(stage);
  if (!attr.project.ok) {
    console.log(core.t('lessons.unavailable', { reason: attr.project.reason }));
    return;
  }
  console.log(core.t('lessons.attribution', {
    projN: attr.project.count,
    globN: attr.global.ok ? attr.global.count : 0,
    projPath: core.shortPath(attr.project.path),
    globPath: core.shortPath(attr.global.path),
    expiring: (attr.project.expiring || 0) + (attr.global.ok ? attr.global.expiring || 0 : 0),
  }));
  if (attr.stageTagged.length) {
    console.log(core.t('lessons.stageSubsetHeader', { stage: attr.stage }));
    for (const e of attr.stageTagged.slice(0, 8)) {
      console.log(`  (${String(e.id).slice(0, 8)}) ${e.at} — ${e.text != null ? e.text : `${e.scene ? e.scene + ': ' : ''}${e.lesson || ''}`}`.slice(0, 180));
    }
  }
  if (attr.rest > 0) console.log(core.t('lessons.remainderPointer', { n: attr.rest }));
}

function cmdInstructions(args) {
  const state = core.readState();
  if (!state) core.die(core.CONTRACTS.state_semantics.noActiveTask);
  const stage = (args[0] || state.current_stage || '').toUpperCase();
  if (!stage || sibStatus.stageIndex(stage) === -1) {
    console.log('Usage: gos instructions <stage>');
    console.log('Stages: INTENT THINK PLAN BUILD REVIEW VERIFY SHIP');
    return;
  }
  const saved = state.current_stage;
  state.current_stage = stage;
  console.log(`=== Instructions for ${stage} ===\n`);
  lessonsAttributionBlock(stage);
  console.log('');
  for (const line of sibStatus.structuredNextActions(state)) console.log(line);
  state.current_stage = saved;
}

function cmdResume() {
  const state = core.readState();
  if (!state) core.die('No state to resume. Start with `gos init`.');
  console.log('=== GOS Resume Summary ===');
  console.log(`Task: ${core.sanitizeEcho(state.intent.summary)} (Lv${state.level ?? '?'})`);
  console.log(`Completed: ${state.completed_stages.join(' → ') || '(none)'}`);
  console.log(`Current stage: ${state.current_stage}`);
 // Checkpoint takes precedence (finer recovery point than stage level)
  const cps = (state.checkpoints || []).filter(c => !c.consumed);
  if (cps.length) {
    const latest = cps[cps.length - 1];
    console.log(`Checkpoint (wave/area level): ${latest.stage}/${latest.unit} — done: ${latest.done}, remaining: ${latest.remaining}`);
  }
 // stored paths are repo-relative; resolve for display/stat (the
  // absolute form is machine-local and never persisted).
  const specAbs = core.specPathOf(state);
  const planAbs = core.planPathOf(state);
  if (specAbs && fs.existsSync(specAbs)) console.log(`Spec: ${specAbs}`);
  if (planAbs && fs.existsSync(planAbs)) console.log(`Plan: ${planAbs}`);
  if (state.project && fs.existsSync(path.join(core.PROJECT_DIR, 'project.json'))) {
    console.log('→ Lv4: DECISIONS/ROADMAP/REQUIREMENTS are GENERATED views — edit via gos decision/requirement/phase commands.');
  }
  if (state.decisions.length) {
    console.log('Decisions:');
    for (const d of state.decisions) console.log(`  ${d.id}: ${d.title} ${d.covered ? '✓covered' : '✗uncovered'}`);
  }
  if (state.observable_truths.length) {
    console.log('Truths:');
    for (const t of state.observable_truths) console.log(`  ${t.id}: ${t.verified ? '✓verified' : '✗pending'}`);
  }
  console.log(`\nNext:\n${sibStatus.nextHint(state)}`);
  // Machine-local auto runtime: one line when a store exists (breaker trip
  // first when present), silent when auto was never configured here.
  printAutoResumeLine();
}

function cmdApprove(args) {
  const state = core.readState();
  if (!state) core.die(core.CONTRACTS.state_semantics.noActiveTask);
  const what = (args[0] || '').toLowerCase();
  const valid = ['think', 'plan', 'archive', 'baseline-reset'];
  if (!valid.includes(what)) {
    console.log('Usage: gos approve <think|plan|archive|baseline-reset> [--reason "<why>"]');
    console.log('Approvals record EXPLICIT user sign-off; models must core.ask first.');
    const have = Object.keys(state.approvals || {});
    console.log(have.length ? `Current approvals: ${have.join(', ')}` : 'No approvals yet.');
    return;
  }
  state.approvals = state.approvals || {};
  if (what === 'baseline-reset') {
    // approve baseline-reset records {ts, reason}; reset consumes the record once and clears it
    let reason = null;
    for (let i = 1; i < args.length; i++) if (args[i] === '--reason') reason = args[++i];
    if (!reason) core.die('Usage: gos approve baseline-reset --reason "<why>" — a reason is required (consistency-checked against reset --reason)');
    state.approvals.BASELINE_RESET = { ts: new Date().toISOString(), reason };
    core.writeState(state);
    console.log(`✓ BASELINE_RESET approved (reason: ${reason}) — single-consumption: gos map baseline reset --reason "${reason}"`);
    return;
  }
  state.approvals[what.toUpperCase()] = new Date().toISOString();
  core.writeState(state);
  console.log(`✓ ${what.toUpperCase()} approved at ${state.approvals[what.toUpperCase()]}`);
  console.log(what === 'archive' ? 'Next: `gos archive` (will now pass the approval gate)' : `Next: \`gos commit ${what}\` (will now pass the approval gate)`);
}

function cmdTrace(args) {
  const what = (args[0] || 'requirements').toLowerCase();
  const state = core.readState();
  if (!state) core.die(core.CONTRACTS.state_semantics.noActiveTask);
  if (what === 'requirements' || what === 'reqs') {
    // R-NN → phase claim → task Covers (scan plan.md) → truth status
    const planTasks = task.parsePlanMd() || [];
    const rByTask = {};
    for (const t of planTasks) for (const c of t.covers) (rByTask[c] = rByTask[c] || []).push(t.id);
    console.log('| R-NN | Requirement | Phase | Tasks (this phase) | Status |');
    console.log('|:---|:---|:---|:---|:---|');
    for (const r of state.requirements) {
      const tasks = (rByTask[r.id] || []).join(',') || '—';
      console.log(`| ${r.id} | ${r.text.slice(0, 50)} | ${r.phase || '⚠ UNCLAIMED'} | ${tasks} | ${r.done ? '✓' : (r.phase ? 'claimed' : 'open')} |`);
    }
    const unclaimed = state.requirements.filter(r => !r.phase);
    if (unclaimed.length) {
      console.error(`\n⚠ ${unclaimed.length} unclaimed: ${unclaimed.map(r => r.id).join(', ')}`);
      process.exit(1);
    }
  } else if (what === 'decisions' || what === 'dnn') {
    console.log('| D-NN | Decision | Covered | Task |');
    console.log('|:---|:---|:---|:---|');
    for (const d of state.decisions) console.log(`| ${d.id} | ${d.title.slice(0, 50)} | ${d.covered ? '✓' : '✗'} | ${d.task || '—'} |`);
  } else {
    console.log('Usage: gos trace [requirements|decisions]');
  }
}

// auto — full-auto runner family. Runtime state (mode/profile/limits,
// counters, breaker records, dispositions) lives in the machine-local store
// under ${XDG_DATA_HOME:-$HOME/.local/share}/gos/<repo-id>/ — never in
// tracked task state. Probes (host/delivery/launcher/store) print as
// three-state advisories; only an unusable store is fatal. The auto family
// refuses to run inside runner-spawned sessions (marker env).
function cmdAuto(args) {
  const store = require('../ops/auto/store.cjs');
  const registry = require('../ops/auto/adapters/registry.cjs');
  const launcher = require('../ops/auto/launcher.cjs');
  const breaker = require('../ops/auto/breaker.cjs');
  const loop = require('../ops/auto/loop.cjs');
  const delivery = require('../ops/auto/delivery.cjs');
  const publish = require('../ops/auto/delivery-publish.cjs');
  const mods = { store, registry, launcher, breaker, loop, delivery, publish };
  const sub = (args[0] || '').toLowerCase();
  const rest = args.slice(1);

  const guidanceOf = (key, params) => {
    const v = core.t(key, params);
    return typeof v === 'string' ? { what: v } : v;
  };
  const dieGuidance = (lead, g) => {
    console.error(`${lead}:`);
    console.error(`✗ ${g.what}`);
    if (g.why) console.error(`    why: ${g.why}`);
    if (g.fix) console.error(`    fix: ${g.fix}`);
    process.exit(1);
  };
  // The spawned-session marker is the family boundary: a spawned stage
  // session must never drive the runner surface (status stays readable).
  const refuseIfSpawned = (which) => {
    if (!process.env[loop.SPAWN_MARKER_ENV]) return;
    dieGuidance(`auto ${which} refused`, guidanceOf('auto.loop.markerActive'));
  };

  if (sub === 'on') return autoOn(mods, rest, { guidanceOf, dieGuidance, refuseIfSpawned });
  if (sub === 'off') return autoOff(mods, rest, { guidanceOf, dieGuidance, refuseIfSpawned });
  if (sub === 'status') return autoStatus(mods, { guidanceOf });
  if (sub === 'run') return autoRun(mods, rest, { guidanceOf, dieGuidance, refuseIfSpawned });
  if (sub === 'disposition') return autoDisposition(mods, rest, { guidanceOf, dieGuidance, refuseIfSpawned });
  console.log(core.t('auto.cli.usage'));
  console.log(core.t('auto.cli.subs'));
}

// Reconfigure an existing healthy store (mode/profile/limits). Only fields
// the on/off surface owns are touched; every other record (counters,
// breaker, dispositions, snapshots, probes) rides over untouched through
// the same atomic writer the store module uses.
function autoReconfigureStore(mods, loaded, patch) {
  const next = { ...loaded.store };
  if (patch.mode != null) next.mode = patch.mode;
  if (patch.profile != null) next.profile = patch.profile;
  if (patch.limits != null) next.limits = patch.limits;
  const v = mods.breaker.validateLimits(next.limits);
  if (!v.ok) return v;
  next.limits = v.limits;
  try { core.writeAtomicJson(loaded.path, next); }
  catch (e) {
    return { ok: false, status: 'error', reason: 'write-failed', detail: e.message };
  }
  return { ok: true, path: loaded.path, store: next };
}

// Three-state advisory line for one host: selectable / display-only /
// probe-failed. Classifications are locale-invariant tokens; the failure
// detail names the matrix entry.
function autoHostLine(mods, host) {
  const hs = mods.registry.hostStatus(host);
  if (hs.selectable) {
    return { state: 'verified', line: `host ${host}: ${hs.version || '?'} @ ${mods.registry.entryLabel(hs.entry)} — selectable` };
  }
  if (hs.status === 'fixture-tested' || hs.status === 'probe-pending') {
    return { state: 'display-only', line: `host ${host}: ${mods.registry.entryLabel(hs.entry)} — display-only (not selectable for runs)` };
  }
  const f = hs.failure || {};
  return { state: 'failed', line: `host ${host}: ${f.message || hs.status}` };
}

function autoOn(mods, rest, ui) {
  ui.refuseIfSpawned('on');
  const limits = { ...mods.store.DEFAULT_LIMITS };
  let profile = mods.launcher.DEFAULT_PROFILE;
  let wall = null;
  let idle = null;
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    const val = () => {
      const v = rest[++i];
      if (v == null || v.startsWith('--')) core.die(core.t('auto.cli.on.usage'));
      return v;
    };
    if (a === '--profile') profile = val();
    else if (a === '--max-retries') limits.N = val();
    else if (a === '--max-visits') limits.K = val();
    else if (a === '--max-sessions') limits.B = val();
    else if (a === '--timeout-wall') wall = val();
    else if (a === '--timeout-idle') idle = val();
    else core.die(core.t('auto.cli.unknownArg', { sub: 'on', arg: a }));
  }
  for (const k of ['N', 'K', 'B']) {
    // strict integer grammar before parsing — decimals never truncate silently
    if (!/^-?[0-9]+$/.test(String(limits[k]))) {
      ui.dieGuidance('auto on', ui.guidanceOf('auto.breaker.invalidLimits', { detail: `${k} must be an integer >= 1 (got ${JSON.stringify(String(limits[k]))})` }));
    }
    limits[k] = Number.parseInt(limits[k], 10);
  }
  if (!mods.launcher.KNOWN_PROFILES.includes(profile)) {
    ui.dieGuidance('auto on', ui.guidanceOf('auto.launcher.unknown-profile', { name: profile, known: mods.launcher.KNOWN_PROFILES.join(', ') }));
  }
  const lv = mods.breaker.validateLimits(limits);
  if (!lv.ok) ui.dieGuidance('auto on', lv.guidance);
  // Timeout flags ride the same fail-closed grammar the runner reads at
  // spawn time (env channel); validation here fails before any store change.
  const envForPolicy = { ...process.env };
  if (wall != null) envForPolicy.GOS_AUTO_TIMEOUT_WALL_SEC = wall;
  if (idle != null) envForPolicy.GOS_AUTO_TIMEOUT_IDLE_SEC = idle;
  const tp = mods.breaker.timeoutPolicy(envForPolicy);
  if (!tp.ok) ui.dieGuidance('auto on', tp.guidance);

  const made = mods.store.create({ mode: 'on', profile, limits });
  if (!made.ok) {
    if (made.guidance) ui.dieGuidance('auto on', made.guidance);
    core.die(`auto on: ${made.reason}${made.detail ? `: ${made.detail}` : ''}`);
  }
  let finalStore = made.store;
  if (made.created) {
    console.log(core.t('auto.cli.on.created', { path: made.path }));
    if (made.impliedHistory && made.guidance) {
      const g = made.guidance;
      console.log(`⚠ ${g.what}`);
      if (g.fix) console.log(`  ${g.fix}`);
    }
  } else {
    const rc = autoReconfigureStore(mods, made, { mode: 'on', profile, limits });
    if (!rc.ok) core.die(`auto on: ${rc.reason}${rc.detail ? `: ${rc.detail}` : ''}`);
    finalStore = rc.store;
    console.log(core.t('auto.cli.on.reconfigured', { path: rc.path }));
  }

  // Three-state advisories: none fatal (the store itself already proved
  // writable by the create above).
  console.log(core.t('auto.cli.probe.header'));
  console.log(`  ${core.t('auto.cli.probe.store')}: writable — ${made.path}`);
  const hostLine = autoHostLine(mods, 'opencode');
  console.log(`  ${core.t('auto.cli.probe.host')}: ${hostLine.line}`);
  if (hostLine.state === 'failed') console.log(`    ${core.t('auto.cli.probe.hint')}`);
  const dp = mods.delivery.probeDelivery();
  const dpLabel = dp.state === 'green' ? 'green' : dp.state === 'advisory' ? `advisory (${dp.advisoryText || dp.reason || '?'})` : `absent (${dp.reason || 'not configured'})`;
  console.log(`  ${core.t('auto.cli.probe.delivery')}: ${dpLabel}`);
  const ep = mods.launcher.probeEngine();
  if (ep.engine) console.log(`  ${core.t('auto.cli.probe.engine')}: ${ep.engine} (${ep.version || 'version unknown'}) — tier ${ep.tier}`);
  else {
    console.log(`  ${core.t('auto.cli.probe.engine')}: none — tier lexical`);
    console.log(`    ${core.t('auto.launcher.tier-lexical')}`);
  }
  console.log(core.t('auto.cli.on.done', {
    profile: finalStore.profile, n: finalStore.limits.N, k: finalStore.limits.K, b: finalStore.limits.B,
  }));
  console.log(`  ${core.t('auto.cli.timeoutPolicy', { wall: tp.wallSec, idle: tp.idleSec })}`);
}

function autoOff(mods, rest, ui) {
  ui.refuseIfSpawned('off');
  let purge = false;
  for (const a of rest) {
    if (a === '--purge') purge = true;
    else core.die(core.t('auto.cli.unknownArg', { sub: 'off', arg: a }));
  }
  if (purge) {
    const r = mods.publish.purge();
    if (!r.ok) core.die(`auto off --purge: ${r.reason}${r.detail ? `: ${r.detail}` : ''}`);
    const g = r.guidance || { what: core.t('auto.publish.purged', { path: r.path || '' }) };
    console.log(g.what);
    return;
  }
  const loaded = mods.store.load();
  if (!loaded.ok) {
    if (loaded.reason === 'missing') { console.log(core.t('auto.cli.off.already')); return; }
    ui.dieGuidance('auto off', loaded.guidance);
  }
  const rc = autoReconfigureStore(mods, loaded, { mode: 'off' });
  if (!rc.ok) core.die(`auto off: ${rc.reason}${rc.detail ? `: ${rc.detail}` : ''}`);
  console.log(core.t('auto.cli.off.done', { path: rc.path }));
  console.log(core.t('auto.cli.off.purgeHint'));
}

function autoStatus(mods, ui) {
  const loaded = mods.store.load();
  if (loaded.ok) {
    const st = loaded.store;
    console.log(core.t('auto.cli.status.head', {
      mode: st.mode, profile: st.profile, n: st.limits.N, k: st.limits.K, b: st.limits.B,
    }));
  } else if (loaded.reason === 'missing') {
    console.log(core.t('auto.cli.status.absent', { path: loaded.path || '' }));
  } else {
    console.log(core.t('auto.cli.status.paused', { reason: loaded.reason }));
    const g = loaded.guidance;
    if (g) {
      console.log(`✗ ${g.what}`);
      if (g.why) console.log(`    why: ${g.why}`);
      if (g.fix) console.log(`    fix: ${g.fix}`);
    }
  }

  const am = mods.registry.activeMatrix(process.env);
  if (am.error) console.log(`  host matrix: ${am.error}`);
  else {
    const hosts = [...new Set(am.rows.map((r) => r.host))];
    console.log(core.t('auto.cli.status.hostMatrix', { n: am.rows.length }));
    for (const row of am.rows) console.log(`  ${mods.registry.entryLabel(row)}`);
    for (const host of hosts) console.log(`  ${autoHostLine(mods, host).line}`);
  }

  const dp = mods.delivery.probeDelivery();
  const dpLabel = dp.state === 'green' ? 'green' : dp.state === 'advisory' ? `advisory (${dp.advisoryText || dp.reason || '?'})` : `absent (${dp.reason || 'not configured'})`;
  console.log(`${core.t('auto.cli.probe.delivery')}: ${dpLabel}`);

  const wp = mods.store.probeWritable();
  console.log(`${core.t('auto.cli.probe.store')}: ${wp.ok ? `writable — ${wp.path}` : `unwritable (${wp.detail || wp.reason})`}`);

  const ep = mods.launcher.probeEngine();
  if (ep.engine) console.log(`${core.t('auto.cli.probe.engine')}: ${ep.engine} (${ep.version || 'version unknown'}) — tier ${ep.tier}`);
  else {
    console.log(`${core.t('auto.cli.probe.engine')}: none — tier lexical`);
    console.log(`  ${core.t('auto.launcher.tier-lexical')}`);
  }

  const tp = mods.breaker.timeoutPolicy(process.env);
  if (tp.ok) console.log(`${core.t('auto.cli.timeoutPolicy', { wall: tp.wallSec, idle: tp.idleSec })}`);
  else console.log(`⚠ ${tp.guidance.what}`);

  if (loaded.ok) {
    const st = loaded.store;
    console.log(core.t('auto.cli.status.counters', { spawns: st.counters.spawnCount, trips: st.counters.tripCount }));
    const lastTrip = [...st.breaker.records].reverse().find((r) => r.layer);
    if (lastTrip) console.log(core.t('auto.cli.status.breakerTripped', { layer: lastTrip.layer, cls: lastTrip.cls, ts: lastTrip.ts, detail: lastTrip.detail || '' }));
    else console.log(core.t('auto.cli.status.breakerClean', { n: st.breaker.records.length }));
    const lock = mods.store.readRunLock();
    if (lock) console.log(core.t('auto.cli.status.lock', { pid: lock.pid, host: lock.hostname }));
  } else {
    console.log(core.t('auto.cli.status.countersAbsent'));
  }
}

function autoRun(mods, rest, ui) {
  ui.refuseIfSpawned('run');
  let detach = false;
  for (const a of rest) {
    if (a === '--detach') detach = true;
    else core.die(core.t('auto.cli.unknownArg', { sub: 'run', arg: a }));
  }
  const loaded = mods.store.load();
  const opts = { detach };
  if (loaded.ok) {
    opts.profile = loaded.store.profile;
    opts.limits = loaded.store.limits;
  }
  const created = mods.loop.create(opts);
  if (!created.ok) {
    if (created.guidance) ui.dieGuidance('auto run', created.guidance);
    core.die(`auto run: ${created.reason}${created.detail ? `: ${created.detail}` : ''}`);
  }
  created.loop.run().then((report) => {
    if (report.ok && report.status === 'detached') {
      console.log(core.t('auto.cli.run.detached', { pid: report.pid }));
      return;
    }
    console.log(core.t('auto.cli.run.report', { status: report.status, reason: report.reason || '' }));
    if (Number.isInteger(report.iterations)) console.log(`  ${core.t('auto.cli.run.iterations', { n: report.iterations })}`);
    if (report.breaker && report.breaker.tripped) {
      console.log(`  ${core.t('auto.cli.status.breakerTripped', { layer: report.breaker.layer, cls: report.breaker.cls, ts: report.breaker.ts || '', detail: report.breaker.reason || '' })}`);
    }
    const g = report.guidance;
    if (g) {
      console.log(`✗ ${g.what}`);
      if (g.why) console.log(`    why: ${g.why}`);
      if (g.fix) console.log(`    fix: ${g.fix}`);
    }
    process.exitCode = report.ok ? 0 : 1;
  }).catch((e) => {
    console.error(`auto run: ${e && e.message ? e.message : e}`);
    process.exitCode = 1;
  });
}

function autoDisposition(mods, rest, ui) {
  ui.refuseIfSpawned('disposition');
  const runId = rest[0];
  let reason = null;
  let by = null;
  for (let i = 1; i < rest.length; i++) {
    const a = rest[i];
    const val = () => {
      const v = rest[++i];
      if (v == null) core.die(core.t('auto.cli.disposition.usage'));
      return v;
    };
    if (a === '--reason') reason = val();
    else if (a === '--by') by = val();
    else core.die(core.t('auto.cli.unknownArg', { sub: 'disposition', arg: a }));
  }
  if (!runId || runId.startsWith('--')) core.die(core.t('auto.cli.disposition.usage'));
  const cRun = core.checkInputConstraint({ value: runId, maxCp: 200, label: 'auto disposition <runId>', noNewlineListPrefix: true });
  if (!cRun.ok) core.die(`✗ ${cRun.reason}`);
  const cReason = core.checkInputConstraint({ value: reason, maxCp: 500, label: 'auto disposition --reason' });
  if (!cReason.ok) core.die(`✗ ${cReason.reason}`);
  if (by == null) by = `${(require('os').userInfo().username || process.env.USER || 'unknown')}@${require('os').hostname()}`;
  const cBy = core.checkInputConstraint({ value: by, maxCp: 100, label: 'auto disposition --by', noNewlineListPrefix: true });
  if (!cBy.ok) core.die(`✗ ${cBy.reason}`);
  // writeDisposition's ledger mirror takes an explicit repo root (no
  // internal default) — resolve it the way the store module does.
  const rootDir = core.currentRootRealpath() || process.cwd();
  const r = mods.publish.writeDisposition({ runId: cRun.value, reason: cReason.value, by: cBy.value }, rootDir);
  if (!r.ok) {
    if (r.guidance) ui.dieGuidance('auto disposition', r.guidance);
    core.die(`auto disposition: ${r.reason}${r.detail ? `: ${r.detail}` : ''}`);
  }
  console.log(core.t('auto.cli.disposition.recorded', { runId: r.disposition.runId, by: r.disposition.by }));
  if (r.ledgerMirror && r.ledgerMirror.path) console.log(`  ${core.t('auto.cli.disposition.mirror', { path: r.ledgerMirror.path })}`);
  const g = r.guidance;
  if (g) console.log(`✓ ${g.what}`);
}

// Resume tail: one machine-local auto line when a store exists — breaker
// trip first when present — and silence when auto was never configured here.
function printAutoResumeLine() {
  const store = require('../ops/auto/store.cjs');
  const loaded = store.load();
  if (!loaded.ok) {
    if (loaded.reason === 'missing') return;
    console.log(core.t('auto.cli.resume.paused', { reason: loaded.reason }));
    return;
  }
  const st = loaded.store;
  const lastTrip = [...st.breaker.records].reverse().find((r) => r.layer);
  if (lastTrip) console.log(core.t('auto.cli.resume.tripped', { mode: st.mode, profile: st.profile, layer: lastTrip.layer, cls: lastTrip.cls, ts: lastTrip.ts }));
  else console.log(core.t('auto.cli.resume.auto', { mode: st.mode, profile: st.profile }));
}

function cmdGap(args) {
  // gap resolve <G-id> --resolution "..." — closes a stage-back gap (fail-closed)
  // Mirrors the lessons/truth command families: fail-closed argument checks +
  // explicit resolution semantics (a gap is never closed without a resolution).
  const sub = (args[0] || 'list').toLowerCase();
  const rest = args.slice(1);
  // [T6/D-16] migrate/history operate on repo-level stores (concerns.md + the
  // gap-history ledger), NOT task state — they must run post-archive (the cure
  // for a repo whose mirrors outlived its task), so they sit BEFORE the
  // readState gate. Serialization: the write-class dispatch guard already holds
  // the root .gos/.lock for this process (acquireEdgeLock's re-entrancy
  // precedent) — only take concernsRootLock when it does not.
  if (sub === 'migrate') {
    for (const a of rest) core.die(`gap migrate: unknown argument '${a}'`);
    const P = concernsMod.concernsPaths();
    let ownLock = false;
    if (core.holdsLock()) {
      try { ownLock = JSON.parse(fs.readFileSync(path.join(P.root, '.gos', '.lock'), 'utf8')).pid === process.pid; } catch { ownLock = false; }
    }
    const run = () => concernsMod.migrateGapMirrors(P);
    const res = ownLock ? run() : core.concernsRootLock(P, run);
    if (!res.removed) console.log(core.t('gap.migrate.none'));
    else {
      console.log(core.t('gap.migrate.removed', { n: res.removed }));
      if (res.deduped) console.log(core.t('gap.migrate.dupes', { n: res.deduped }));
    }
    return;
  }
  if (sub === 'history') {
    for (const a of rest) core.die(`gap history: unknown argument '${a}'`);
    const { entries, skipped } = concernsMod.readGapHistoryLedger(concernsMod.concernsPaths());
    if (!entries.length) console.log(core.t('gap.history.empty'));
    for (const e of entries) console.log(`${e.ts} ${e.text}`);
    if (skipped) console.log(core.t('gap.history.skipped', { n: skipped }));
    return;
  }
  const state = core.readState();
  if (!state) core.die(`${core.CONTRACTS.state_semantics.noActiveTask} \`gos init\` first.`);
  if (!Array.isArray(state.gaps)) state.gaps = [];
  if (sub === 'list') {
    if (!state.gaps.length) { console.log('(no gaps)'); return; }
    for (const g of state.gaps) console.log(`${g.id} [${g.status}] ${g.description}${g.resolution ? `\n    ↳ fixed: ${g.resolution}` : ''}`);
    return;
  }
  if (sub === 'resolve') {
    const id = rest[0];
    let resolution = null;
    for (let i = 1; i < rest.length; i++) {
      if (rest[i] === '--resolution') resolution = rest[++i];
      else core.die(`gap resolve: unknown argument '${rest[i]}'`);
    }
    if (!id || id.startsWith('--')) core.die('Usage: gos gap resolve <G-id> --resolution "..."');
    if (!resolution || !resolution.trim()) core.die('gap resolve: --resolution is required (fail-closed: closing without a resolution = silent whitewash)');
    if (core.cpLen(resolution) > 300) core.die('gap resolve: resolution exceeds 300 codepoints');
    const g = state.gaps.find((x) => x.id === id);
    if (!g) core.die(`gap resolve: ${id} not found (gos gap list)`);
    if (g.status === 'fixed') core.die(`gap resolve: ${id} already fixed — ${g.resolution || '(no resolution recorded)'}`);
    g.status = 'fixed';
    g.resolution = resolution.trim();
    g.resolved_at = new Date().toISOString();
    core.writeState(state);
    console.log(`✓ gap ${id} fixed: ${g.resolution}`);
    return;
  }
  if (sub === 'rewrite') {
    // [T5/D-17] gap rewrite: replaces a gap description (the sanctioned path to
    // clear legacy zh descriptions). Text passes the tracked-store boundary
    // with concerns.md as the trigger file — gap descriptions flow into
    // concerns.md via the stage-back (auto) write-back, so tracked concerns.md
    // means gap text is clone-traveling content too.
    const id = rest[0];
    let text = null;
    for (let i = 1; i < rest.length; i++) {
      if (rest[i] === '--text') text = rest[++i];
      else core.die(`gap rewrite: unknown argument '${rest[i]}'`);
    }
    if (!id || id.startsWith('--')) core.die('Usage: gos gap rewrite <G-id> --text "<text>"');
    if (!text || !text.trim()) core.die('gap rewrite: --text is required (fail-closed: rewriting without text = silent history edit)');
    const c = core.checkInputConstraint({ value: text, maxCp: 300, label: 'gap text', noNewlineListPrefix: true });
    if (!c.ok) core.die(`✗ ${c.reason}`);
    core.dieTrackedStoreCJK(concernsMod.concernsPaths().file, c.value);
    const g = state.gaps.find((x) => x.id === id);
    if (!g) core.die(`gap rewrite: ${id} not found (gos gap list)`);
    g.description = c.value;
    g.rewritten_at = new Date().toISOString();
    core.writeState(state);
    console.log(`✓ gap ${id} description rewritten`);
    return;
  }
  core.die('Usage: gos gap <list|resolve|rewrite|migrate|history>');
}

module.exports = { cmdInstructions, cmdResume, cmdApprove, cmdTrace, cmdAuto, cmdGap };