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
const workers = require('./workers.cjs');
const { renderSpawnOutput } = require('../../core/sanitize.cjs');

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

// Distinct breaker layers currently reading TRIPPED in a loaded store:
// layer-carrying breaker records are trips; class-only records (takeover
// audit events) never gate the re-enable.
function trippedLayersOf(st) {
  const records = st != null && Array.isArray(st.breaker.records) ? st.breaker.records : [];
  return [...new Set(records.filter((r) => r != null && r.layer).map((r) => String(r.layer)))];
}

// Evidence read for the re-enable gate: a run record reads green when the
// end state is ok, every recorded stage advanced in INTENT->SHIP order,
// and the sandboxed VERIFY entry carries at least one step with every
// step status passed. Anything weaker is not evidence the gate accepts.
function latestRunRecordReadsGreen(rec) {
  if (!store.isPlainObject(rec)) return { green: false, detail: 'latest run record unreadable' };
  const es = store.isPlainObject(rec.endState) ? rec.endState : null;
  if (es == null || es.ok !== true) {
    return { green: false, detail: `end state not ok (${es != null && es.status ? es.status : 'unknown'})` };
  }
  const stages = Array.isArray(rec.stages) ? rec.stages : [];
  let prev = -1;
  let verify = null;
  for (const s of stages) {
    const name = s != null && typeof s.stage === 'string' ? s.stage : '';
    const idx = workers.STAGES.indexOf(name);
    if (idx < 0) return { green: false, detail: `unknown stage ${JSON.stringify(name)}` };
    if (idx < prev) return { green: false, detail: 'stage entries out of INTENT->SHIP order' };
    prev = idx;
    if (s.advanced !== true) return { green: false, detail: `stage ${name} did not advance` };
    if (name === 'VERIFY') verify = s;
  }
  if (verify == null) return { green: false, detail: 'no VERIFY stage entry (sandboxed VERIFY evidence absent)' };
  const steps = Array.isArray(verify.steps) ? verify.steps : [];
  if (steps.length === 0) return { green: false, detail: 'VERIFY entry carries no step statuses' };
  if (steps.some((sp) => !store.isPlainObject(sp) || sp.status !== 'passed')) {
    return { green: false, detail: 'VERIFY steps not all passed' };
  }
  return { green: true, detail: `end state ${es.status}` };
}

// Explicit breaker reset (operator flag): drop the trip-layer records,
// zero the spawn/trip counters, and append a disposition entry to the
// store's dispositions ledger naming who reset what and when. Audit-only
// breaker records (takeover class entries) ride over untouched. The whole
// reset runs through the store mutation mutex (a live detached runner's
// stamp writes must never be lost under this reset) and refuses while a
// run-lock holder that could still be alive exists.
function resetBreakerState(mods, loaded) {
  const st = loaded.store;
  const lock = mods.store.readRunLock();
  if (lock) {
    const os = require('os');
    const crossHost = lock.hostname !== os.hostname();
    let bootMismatch = false;
    try {
      const boot = require('fs').readFileSync('/proc/sys/kernel/random/boot_id', 'utf8').trim();
      bootMismatch = Boolean(boot && lock.boot_id && boot !== lock.boot_id);
    } catch { /* unavailable — fail closed */ }
    const alive = crossHost || (!bootMismatch && core.pidAlive(Number(lock.pid)));
    if (alive) {
      core.die(core.t('auto.cli.on.reenable.resetRefusedLive', { pid: lock.pid, host: lock.hostname }));
    }
  }
  const layers = trippedLayersOf(st);
  const prevSpawns = st.counters.spawnCount;
  const prevTrips = st.counters.tripCount;
  const ts = new Date().toISOString();
  const by = `${(require('os').userInfo().username || process.env.USER || 'unknown')}@${require('os').hostname()}`;
  const r = mods.store.mutate(undefined, (cur) => {
    cur.breaker = { records: cur.breaker.records.filter((row) => !(row != null && row.layer)) };
    cur.counters = { spawnCount: 0, tripCount: 0 };
    cur.dispositions = [...(cur.dispositions || []), {
      runId: `breakers-reset-${ts}`,
      ts,
      reason: `auto on --reset-breakers: cleared trip layers [${layers.join(', ')}], counters spawns ${prevSpawns}->0 trips ${prevTrips}->0`,
      by,
    }].slice(-200);
    return cur;
  });
  if (!r.ok) {
    core.die(`auto on --reset-breakers: store mutation failed: ${r.reason}${r.detail ? `: ${r.detail}` : ''}`);
  }
  return core.t('auto.cli.on.reenable.breakersReset', {
    layers: layers.length ? layers.join(', ') : 'none',
    spawns: prevSpawns,
    trips: prevTrips,
  });
}

function autoOn(mods, rest, ui) {
  ui.refuseIfSpawned('on');
  const limits = { ...mods.store.DEFAULT_LIMITS };
  let profile = mods.launcher.DEFAULT_PROFILE;
  let wall = null;
  let idle = null;
  let allowFull = false;
  let resetBreakers = false;
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
    else if (a === '--reset-breakers') resetBreakers = true;
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

  // Evidence-gated re-enable: a tripped breaker never re-enables blindly.
  // With run records present the latest must read green; a store with no
  // records yet is a cold start and proceeds with a logged disposition.
  // The explicit operator reset clears trip layers and counters first and
  // records its own disposition entry.
  let reenableDisposition = null;
  const pre = mods.store.load();
  if (resetBreakers) {
    if (pre.ok) reenableDisposition = resetBreakerState(mods, pre);
  } else if (pre.ok) {
    const layers = trippedLayersOf(pre.store);
    if (layers.length) {
      const records = Array.isArray(pre.store.runRecords) ? pre.store.runRecords : [];
      if (records.length === 0) {
        reenableDisposition = core.t('auto.cli.on.reenable.coldStart', { layers: layers.join(', ') });
      } else {
        const latest = records[records.length - 1];
        const verdict = latestRunRecordReadsGreen(latest);
        if (!verdict.green) {
          const es = store.isPlainObject(latest.endState) ? latest.endState : {};
          ui.dieGuidance('auto on refused', ui.guidanceOf('auto.cli.on.reenable.refused', {
            layers: layers.join(', '),
            runId: latest.runId,
            end: es.status || 'unknown',
            reason: es.reason || verdict.detail,
            why: verdict.detail,
          }));
        }
        reenableDisposition = core.t('auto.cli.on.reenable.greenEvidence', { runId: latest.runId, end: latest.endState.status });
      }
    }
  }

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
  if (reenableDisposition) console.log(reenableDisposition);

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

// Per-stage dispatch view for `auto status`: one compact line per stage
// resolved from the stage-dispatch table (worker form, capability profile,
// model slot, verb grants, use cap, dispatch unit; BUILD carries its
// wave-dispatch suffix). The table load is read-only and failure-tolerant —
// a missing or corrupt table renders nothing (status never mkdirs or probes
// for the table).
function dispatchViewLines(opts) {
  let load;
  try { load = workers.loadDispatchTable(opts || {}); }
  catch { return []; }
  if (!load || load.ok !== true || !load.table || !load.table.stages) return [];
  const lines = ['dispatch:'];
  for (const stage of workers.STAGES) {
    const e = load.table.stages[stage];
    if (!e || typeof e !== 'object') continue;
    let line = `  ${stage} ${e.worker} ${e.profile} ${e.model_slot} [${Array.isArray(e.verbs) ? e.verbs.join(' ') : ''}] cap${e.use_cap} unit=${e.unit}`;
    if (e.wave_dispatch) line += ` wave-dispatch model=${e.model_slot}`;
    lines.push(line);
  }
  return lines.length > 1 ? lines : [];
}

// Three-tier clearance vocabulary for the delegated-stage approval records:
// mechanical clearance (store-verified vs pre-loop legacy trust flavors),
// human approval, pending mechanical clearance, or a hold. Advisory
// contexts pass only the live store stamps — a pairing-free record then
// reads pre-loop legacy, never a hold (age alone proves nothing either way
// here). Returns one term per delegated stage carrying a record.
function clearanceTerms(approvals, stamps) {
  const ratify = require('./ratify.cjs');
  const out = [];
  if (!store.isPlainObject(approvals)) return out;
  for (const stage of ratify.DELEGATED_STAGES) {
    const rec = approvals[stage];
    if (rec === undefined || rec === null) continue;
    const desc = ratify.describeApproval(rec, { stamps });
    if (desc === 'cleared (store-verified)') out.push(`${stage} mechanical clearance (store-verified)`);
    else if (desc === 'cleared (pre-loop legacy)') out.push(`${stage} mechanical clearance (pre-loop legacy)`);
    else if (desc === 'human') out.push(`${stage} human approval`);
    else if (desc === 'pending') out.push(`${stage} pending mechanical clearance`);
    else out.push(`${stage} claimed-not-verified (held for human approval)`);
  }
  return out;
}

// Tracked approvals for the current repo, or null when no readable task
// state exists (read-only; the render stays silent rather than guessing).
function trackedApprovals() {
  try {
    const stJson = JSON.parse(fs.readFileSync(path.join(process.cwd(), '.gos', 'state.json'), 'utf8'));
    return store.isPlainObject(stJson.approvals) ? stJson.approvals : null;
  } catch { return null; }
}

// Breaker trip details quote spawn streams (deny lines with raw JSON, host
// stderr slices) — every byte rendered to humans passes the spawn-output
// sanitizer so escape sequences cannot ride along.
function tripDetailArg(detail) {
  return detail ? ` ${renderSpawnOutput(detail)}` : '';
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
    if (lastTrip) console.log(core.t('auto.cli.status.breakerTripped', { layer: lastTrip.layer, cls: lastTrip.cls, ts: lastTrip.ts, detail: tripDetailArg(lastTrip.detail) }));
    else console.log(core.t('auto.cli.status.breakerClean', { n: st.breaker.records.length }));
    // Clearance summary: the three-tier vocabulary over the delegated-stage
    // approval records, trust-flavored from the live store stamps.
    const clearance = clearanceTerms(trackedApprovals(), store.isPlainObject(st.stamps) ? st.stamps : undefined);
    if (clearance.length) console.log(`clearance: ${clearance.join(' · ')}`);
    // A held delegation is only decidable with its evidence: surface the
    // stored review rounds when a delegated stage waits on a human.
    const ratify = require('./ratify.cjs');
    const approvals = trackedApprovals();
    const blocker = approvals ? ratify.advanceBlocker(approvals) : null;
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
    for (const line of dispatchViewLines()) console.log(line);
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
  // Detach is the survival default (the enclosing operator terminal may time
  // out and group-kill its process tree); --fg opts back into the foreground.
  let detach = true;
  for (const a of rest) {
    if (a === '--detach') detach = true;
    else if (a === '--fg') detach = false;
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
  if (detach) {
    // The detached child is a GOS invocation in its own right and takes the
    // repo command lock at its entry; the parent holds nothing past the
    // fork point (its remaining work is read-and-print only).
    core.releaseLock();
    // Forward the original invocation to the detached child; the loop strips
    // detach-class flags and appends --fg (the child never re-detaches).
    opts.detachArgv = process.argv.slice(2);
  }
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
    if (report.status === 'detached') {
      if (Number.isInteger(report.completed)) {
        console.log(core.t('autoDetach.completed', { code: report.completed, log: report.log || '(none)' }));
      } else {
        console.log(core.t('auto.cli.run.detached', { pid: report.pid, log: report.log || '.gos/logs/auto-run-*.log' }));
      }
      process.exitCode = report.ok ? 0 : 1;
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
      console.log(`  ${core.t('auto.cli.status.breakerTripped', { layer: report.breaker.layer, cls: report.breaker.cls, ts: report.breaker.ts || '', detail: tripDetailArg(report.breaker.reason || '') })}`);
    }
    const g = report.guidance;
    if (g) {
      console.log(`✗ ${g.what}`);
      if (g.why) console.log(`    why: ${g.why}`);
      if (g.fix) console.log(`    fix: ${g.fix}`);
    }
    if (report.status === 'sentinel-timeout') {
      console.log(`  ${core.t('autoDetach.waitTimeout', { sec: report.waitSec || 5, log: report.log || '(none)' })}`);
    }
    if (report.status === 'sentinel-missing') {
      console.log(`  ${core.t('autoDetach.exitedUnproven', { log: report.log || '(none)' })}`);
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

module.exports = { cmdAuto, autoResumeLine, dispatchViewLines, clearanceTerms, autoHintProvider };

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
  const clearance = clearanceTerms(trackedApprovals(), store.isPlainObject(st.stamps) ? st.stamps : undefined);
  if (clearance.length) console.log(`auto clearance: ${clearance.join(' · ')}`);
}

// Nav hint provider: compact auto-loop orientation lines for surfaces that
// want one read-only glance (the nav summary wires this). One
// kind-discriminated object:
//   {kind:'marker',  lines:[...]}  inside a runner-spawned session — the
//                                  worker orientation (tracked artifact,
//                                  advance verb, human-only gates)
//   {kind:'mode-on', lines:[...]}  auto configured and enabled — loop state
//   {kind:'none',    lines:[]}     nothing auto-shaped to say
// Store and dispatch-table reads are read-only and failure-tolerant; trip
// details quoted into a line pass the spawn-output sanitizer.
function autoHintProvider(ctx = {}) {
  const env = ctx.env || process.env;
  if (env[loop.SPAWN_MARKER_ENV]) {
    const spawnId = typeof env.GOS_AUTO_SPAWN_ID === 'string' && env.GOS_AUTO_SPAWN_ID ? env.GOS_AUTO_SPAWN_ID : '(unknown)';
    return {
      kind: 'marker',
      lines: [
        `auto loop session ${spawnId}: stage work lands through 'gos commit <stage>' on the tracked task state (.gos/state.json)`,
        'archive and push stay human gates — they are never delegated to a spawned session',
      ],
    };
  }
  let loaded;
  try { loaded = store.load(ctx.rootDir); }
  catch { loaded = { ok: false }; }
  if (loaded && loaded.ok && loaded.store.mode === 'on') {
    const st = loaded.store;
    const lines = [`auto mode on — profile ${st.profile}, limits N=${st.limits.N}/K=${st.limits.K}/B=${st.limits.B}`];
    const lastTrip = [...st.breaker.records].reverse().find((r) => r.layer);
    if (lastTrip) {
      lines.push(`breaker TRIPPED ${lastTrip.layer}/${lastTrip.cls}${tripDetailArg(lastTrip.detail)}`);
    }
    const dispatch = dispatchViewLines(typeof ctx.tablePath === 'string' ? { tablePath: ctx.tablePath } : {});
    if (dispatch.length) lines.push(`${dispatch[0]} (${dispatch.length - 1} stages)`);
    return { kind: 'mode-on', lines };
  }
  return { kind: 'none', lines: [] };
}
