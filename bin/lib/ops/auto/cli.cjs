// ops/auto/cli.cjs — gos auto command family (on/off/status/run/disposition).
// Runtime state lives in the machine-local trust store; this module only
// parses args, validates floors and renders advisories. The family refuses
// to run inside runner-spawned sessions (marker env).
'use strict';

const core = require('../../core/index.cjs');
const fs = require('node:fs');
const path = require('node:path');
const store = require('./store.cjs');
const registry = require('./adapters/registry.cjs');
const launcher = require('./launcher.cjs');
const breaker = require('./breaker.cjs');
const loop = require('./loop.cjs');
const delivery = require('./delivery.cjs');
const publish = require('./delivery-publish.cjs');

// auto — full-auto runner family. Runtime state (mode/profile/limits,
// counters, breaker records, dispositions) lives in the machine-local store
// under ${XDG_DATA_HOME:-$HOME/.local/share}/gos/<repo-id>/ — never in
// tracked task state. Probes (host/delivery/launcher/store) print as
// three-state advisories; only an unusable store is fatal. The auto family
// refuses to run inside runner-spawned sessions (marker env).
function cmdAuto(args) {
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
  process.exitCode = 1;
}

// Reconfigure an existing healthy store (mode/profile/limits/timeouts).
// Only fields the on/off surface owns are touched; every other record
// (counters, breaker, dispositions, snapshots, probes) rides over untouched
// through the same atomic writer the store module uses.
function autoReconfigureStore(mods, loaded, patch) {
  const next = { ...loaded.store };
  if (patch.mode != null) next.mode = patch.mode;
  if (patch.profile != null) next.profile = patch.profile;
  if (patch.limits != null) next.limits = patch.limits;
  if (patch.timeouts != null) next.timeouts = patch.timeouts;
  if (patch.allowFull !== undefined) next.allowFull = patch.allowFull;
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
  let allowFull = false;
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
    else if (a === '--allow-full') allowFull = true;
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
  // The capability-upgrade flag only means something for the full profile —
  // accepting it elsewhere would let the gate look satisfied by accident.
  if (allowFull && profile !== 'full') {
    ui.dieGuidance('auto on', ui.guidanceOf('auto.cli.on.allowFullWithoutFull', { profile }));
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
  const timeouts = { wallSec: tp.wallSec, idleSec: tp.idleSec };

  const made = mods.store.create({ mode: 'on', profile, limits, timeouts, allowFull });
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
    const rc = autoReconfigureStore(mods, made, { mode: 'on', profile, limits, timeouts, allowFull });
    if (!rc.ok) core.die(`auto on: ${rc.reason}${rc.detail ? `: ${rc.detail}` : ''}`);
    finalStore = rc.store;
    console.log(core.t('auto.cli.on.reconfigured', { path: rc.path }));
  }

  // Three-state advisories: none fatal (the store itself already proved
  // writable by the create above).
  console.log(core.t('auto.cli.probe.header'));
  console.log(`  ${core.t('auto.cli.probe.store')}: writable — ${made.path}`);
  const nfs = mods.store.networkFsUnderStore();
  if (nfs) console.log(`  ⚠ ${core.t('auto.cli.on.nfsAdvisory', { fstype: nfs.fstype, mount: nfs.mount })}`);
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
  if (finalStore.allowFull === true) console.log(`  ${core.t('auto.cli.status.allowFullTag').trim()}`);
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
      full: st.allowFull === true ? core.t('auto.cli.status.allowFullTag') : '',
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
    // A held delegation is only decidable with its evidence: surface the
    // stored review rounds when a delegated stage waits on a human.
    const ratify = require('./ratify.cjs');
    let blocker = null;
    try {
      const stJson = JSON.parse(fs.readFileSync(path.join(process.cwd(), '.gos', 'state.json'), 'utf8'));
      blocker = ratify.advanceBlocker(stJson.approvals);
    } catch { blocker = null; }
    if (blocker && ratify.isDelegatedStage(blocker.stage)) {
      const rounds = store.isPlainObject(st.reviewRounds) ? st.reviewRounds : {};
      const recent = Object.entries(rounds).sort((a, b) => String(a[1].ts).localeCompare(String(b[1].ts))).slice(-4);
      for (const [id, r] of recent) {
        console.log(core.t('auto.cli.status.heldRound', { stage: blocker.stage, id: id.slice(-24), findings: r.findings == null ? '?' : r.findings, cls: r.classified }));
      }
      if (recent.length) console.log(core.t('auto.cli.status.heldWhere'));
    }
    const lock = mods.store.readRunLock();
    if (lock) console.log(core.t('auto.cli.status.lock', { pid: lock.pid, host: lock.hostname }));
  } else {
    console.log(core.t('auto.cli.status.countersAbsent'));
  }
}

function autoRun(mods, rest, ui) {
  ui.refuseIfSpawned('run');
  // The CLI entry strips --break-lock from argv (the flag doubles as the
  // top-level command-lock break), so the run subcommand recovers it from
  // the raw process argv — for `auto run` it targets the store's run lock.
  const breakLock = rest.includes('--break-lock') || process.argv.slice(2).includes('--break-lock');
  let detach = false;
  for (const a of rest) {
    if (a === '--detach') detach = true;
    else if (a === '--break-lock') continue;
    else core.die(core.t('auto.cli.unknownArg', { sub: 'run', arg: a }));
  }
  // Explicit lock takeover: the store refuses while the recorded pid+hostname
  // is alive and records every attempt as a takeover breaker event.
  if (breakLock) {
    const br = mods.store.breakRunLock();
    if (!br.ok) {
      if (br.guidance) ui.dieGuidance('auto run --break-lock refused', br.guidance);
      core.die(`auto run --break-lock: ${br.reason}${br.detail ? `: ${br.detail}` : ''}`);
    }
    if (!br.absent) console.log(core.t('auto.cli.run.lockBroken', { broke: br.broke }));
  }
  const loaded = mods.store.load();
  const opts = { detach };
  if (loaded.ok) {
    opts.profile = loaded.store.profile;
    opts.limits = loaded.store.limits;
    opts.allowFull = loaded.store.allowFull === true;
  }
  const created = mods.loop.createLoop(opts);
  if (!created.ok) {
    if (created.guidance) ui.dieGuidance('auto run', created.guidance);
    core.die(`auto run: ${created.reason}${created.detail ? `: ${created.detail}` : ''}`);
  }
  created.loop.run().then((report) => {
    if (report.ok && report.status === 'detached') {
      console.log(core.t('auto.cli.run.detached', { pid: report.pid, log: report.log || '.gos/logs/auto-run-*.log' }));
      return;
    }
    console.log(core.t('auto.cli.run.report', { status: report.status, reason: report.reason || '' }));
    // Full report for post-mortem: the compact summary cannot carry the
    // identity snapshots a pause diagnosis needs.
    try {
      const logDir = path.join(process.cwd(), '.gos', 'logs');
      fs.mkdirSync(logDir, { recursive: true });
      fs.writeFileSync(path.join(logDir, `auto-report-${Date.now()}.json`), JSON.stringify(report, null, 1));
    } catch { /* unwritable: the summary above still printed */ }
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

module.exports = { cmdAuto, autoResumeLine };

// Resume tail: one machine-local auto line when a store exists — breaker
// trip first when present — and silence when auto was never configured here.
// Called by the entry dispatch after the resume summary (the store API owns
// repo-key derivation, including remote-less local clones).
function autoResumeLine() {
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
