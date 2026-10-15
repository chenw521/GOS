// map/edges.cjs — map module aspect (hand-edge store + integrity freeze + audit log)
// Require rules: same-directory mutual requires are free; cross-directory only → core
'use strict';

const anchor = require('./anchor.cjs');

const fs = require('node:fs');
const path = require('node:path');
const core = require('../core/index.cjs');

function edgeStats(deps) {
  const sem = deps.semantic || {};
  const fams = [(deps.edges || []).length, (sem.callgraph || []).length, (sem.testof_fn || []).length, (sem.testof || []).length, (sem.contracts || []).length, (sem.sec_contracts || []).length];
  return { total: fams.reduce((a, b) => a + b, 0), callgraph: (sem.callgraph || []).length, testof_fn: (sem.testof_fn || []).length, fn_count: sem.fn_count };
}

const EDGES_NOTE = 'MAINTAINED via gos map edge add/rm ONLY — integrity-checked; hand edits fail the freeze';

const EDGE_TYPES = new Set(['consumes', 'asserts', 'greps', 'contract-ref', 'owns', 'test-of']);

function edgesPath(root) { return path.join(root, '.gos', core.GOS_PATHS.edges.rel); }

function edgeAuditPath(root) { return path.join(root, '.gos', core.GOS_PATHS.edge_audit.rel); }

function loadEdges(root) {
  const SC = core.CONTRACTS.semantic_checks;
  const p = edgesPath(root);
  let raw;
  try { raw = fs.readFileSync(p, 'utf8'); }
  catch (e) {
    if (e.code === 'ENOENT') return null;
    core.die(`✗ ${SC.edgesReadFail.replace('<err>', e.code || String(e.message))}`);
  }
  let d;
  try { d = JSON.parse(raw); } catch { core.die(`✗ ${SC.edgesParseFail}`); }
  if (!d || d.schema_version !== 1) core.die(`✗ ${SC.edgesSchemaFuture}`);
  if (!Array.isArray(d.edges)) core.die(`✗ ${SC.edgesParseFail}`);
  return d;
}

function writeEdges(root, edgesL, existed) {
  core.writeAtomicJson(edgesPath(root), { schema_version: 1, note: EDGES_NOTE, edges: edgesL });   // frozen key: edges.json schema keeps `edges` (edgesL is a shadow-defense rename); logs staging removed (D-01: machine-local)
}

function auditEdge(root, action, from, to, type) {
  try {
    fs.mkdirSync(path.join(root, '.gos'), { recursive: true });
    const ap = edgeAuditPath(root);
    fs.mkdirSync(path.dirname(ap), { recursive: true }); // T16: logs/ may not exist yet
    fs.appendFileSync(ap, `${new Date().toISOString()} ${action} ${from} -> ${to} ${type}\n`);
  } catch { /* audit best-effort; the edges write itself already succeeded */ }
}

function edgesLockPath(root) { return path.join(root, '.gos', core.GOS_PATHS.edges_lock.rel); }

function deadEdgesIn(root) {   // [R1-C1 fix] R-01: scan/gate face — every hand edge's BOTH endpoints validated
  const d = loadEdges(root);
  if (!d) return [];
  const bad = [];
  for (const e of d.edges) {
    if (e.external) continue;   // exempt by declaration (§4.2)
    for (const side of ['from', 'to']) {
      const v = anchor.validateAnchor(e[side], root);
      if (!v.ok) bad.push(`${side}:${e[side]} — ${v.msg.replace(/^✗ /, '')}`);
    }
  }
  return bad;
}

function checkEdgesIntegrity(root) {   // → {status: ok|advisory|die, msg} — gate reuses (T7)
  const SC = core.CONTRACTS.semantic_checks;
  const ep = edgesPath(root), lp = edgesLockPath(root);
  const tracked = core.trackedFiles(root).exact;
  const edgesExists = fs.existsSync(ep);
  const edgesTracked = tracked.has('.gos/edges.json');
  const lockTracked = tracked.has('.gos/edges.lock');
  if (!edgesExists && edgesTracked) {
    return { status: 'die', msg: `✗ ${SC.edgesTrackedMissing.replace(/<file>/g, '.gos/edges.json')}` };
  }
  if (fs.existsSync(lp) && !fs.existsSync(ep)) {
    return { status: 'die', msg: `✗ ${SC.edgesTrackedMissing.replace(/<file>/g, '.gos/edges.json')}` };
  }
  if (!edgesExists) {
    if (lockTracked) return { status: 'die', msg: `✗ ${SC.edgesTrackedMissing.replace(/<file>/g, '.gos/edges.lock')}` };
    return { status: 'advisory', msg: `⚠ ${SC.edgesBootstrapHint}` };
  }
  if (fs.existsSync(lp)) {
    let lock = null;
    try { lock = JSON.parse(fs.readFileSync(lp, 'utf8')); } catch { /* corrupt lock */ }
    let disk = null;
    try { disk = core.sha256FileSync(ep); } catch (e) { return { status: 'die', msg: `✗ ${SC.edgesReadFail.replace('<err>', e.code || e.message)}` }; }   // [P1-M6] unreadable ≠ crash
    if (!lock || typeof lock.edges_sha256 !== 'string' || lock.edges_sha256 !== disk) {
      return { status: 'die', msg: `✗ ${SC.edgesLockMismatch}` };
    }
    return { status: 'ok', msg: `✓ ${SC.edgesVerifyOk}` };
  }
  if (lockTracked) return { status: 'die', msg: `✗ ${SC.edgesTrackedMissing.replace(/<file>/g, '.gos/edges.lock')}` };
  return { status: 'advisory', msg: `⚠ ${SC.edgesNotFrozen}` };   // seed exists, first commit will freeze
}

function freezeEdgesLock(root) {   // commit-time freeze + CLI transactional re-freeze (T5)
  if (!fs.existsSync(edgesPath(root))) return false;
  core.writeAtomicJson(edgesLockPath(root), { edges_sha256: core.sha256FileSync(edgesPath(root)) });
  return true;
}

Object.assign(module.exports, {
  edgesPath,
  edgeAuditPath,
  loadEdges,
  writeEdges,
  auditEdge,
  edgesLockPath,
  deadEdgesIn,
  checkEdgesIntegrity,
  freezeEdgesLock,
  edgeStats,
  EDGES_NOTE,
  EDGE_TYPES,
});   // assign, not reassign: keeps live references across the same-directory require cycle (CJS value semantics)
