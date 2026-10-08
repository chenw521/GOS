// map/allowlist — require-allowlist v2: module-root inference, baseline init
// command, and the gate-side direction assertion. The allowlist file is the
// single truth source consumed by `gos gate` (codemap layer); v2 generalizes
// the original bin/lib-scoped rules to arbitrary repos.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const core = require('../core/index.cjs');
const engine = require('./engine.cjs');

function allowlistPath(root) {
  return path.join(root, '.gos', 'codebase', 'require-allowlist.json');
}

// ---------- module-root inference (documented algorithm) ----------
// Input: file-level require edges. Output: the minimal set of directory roots
// such that every endpoint file belongs to exactly one root (longest match)
// and same-directory / same-subtree files stay inside one module.
// Algorithm (top-down directory splitting): start at the LCA directory of all
// edge endpoints. Partition the endpoints under a directory into groups — the
// files directly in it (group '') plus one group per endpoint-bearing child
// segment. If any require edge crosses two different groups, the directory
// SPLITS: its direct files register it as a module root and each child group
// recurses; otherwise the whole subtree stays a single module (one root).
// Deterministic: groups visited in sorted order, roots returned sorted.

function dirSegments(dir) {
  return dir === '.' ? [] : String(dir).split('/');
}

function lcaDir(a, b) {
  const as = dirSegments(a), bs = dirSegments(b);
  const out = [];
  for (let i = 0; i < Math.min(as.length, bs.length) && as[i] === bs[i]; i++) out.push(as[i]);
  return out.length ? out.join('/') : '.';
}

function groupKeyOf(file, dir) {
  let rest;
  if (dir === '.') rest = file;
  else if (file.startsWith(dir + '/')) rest = file.slice(dir.length + 1);
  else return null;
  const i = rest.indexOf('/');
  return i === -1 ? '' : rest.slice(0, i);
}

function deriveModuleRoots(edges) {
  const endpoints = new Set();
  for (const e of edges || []) {
    if (e && e.from && e.to) { endpoints.add(String(e.from)); endpoints.add(String(e.to)); }
  }
  if (!endpoints.size) return [];
  const files = [...endpoints].sort();
  let lca = null;
  for (const f of files) lca = lca === null ? path.posix.dirname(f) : lcaDir(lca, path.posix.dirname(f));
  const roots = [];
  const walk = (dir) => {
    const groups = new Map();
    for (const f of files) {
      const k = groupKeyOf(f, dir);
      if (k === null) continue;
      if (!groups.has(k)) groups.set(k, []);
      groups.get(k).push(f);
    }
    if (groups.size === 0) return;
    if (groups.size === 1) {
      const only = [...groups.keys()][0];
      if (only === '') { roots.push(dir); return; }
      walk(dir === '.' ? only : dir + '/' + only);   // LCA degenerate case: everything under one child
      return;
    }
    let cross = false;
    for (const e of edges || []) {
      const g1 = groupKeyOf(String(e.from), dir), g2 = groupKeyOf(String(e.to), dir);
      if (g1 !== null && g2 !== null && g1 !== g2) { cross = true; break; }
    }
    if (!cross) { roots.push(dir); return; }          // no boundary evidence — one module
    if (groups.has('')) roots.push(dir);              // direct files keep dir as their root
    for (const k of [...groups.keys()].sort()) if (k !== '') walk(dir === '.' ? k : dir + '/' + k);
  };
  walk(lca);
  return [...new Set(roots)].sort();
}

// longest-matching root wins: sub-directory files belong to their deepest root
function rootOf(file, rootsByLength) {
  for (const r of rootsByLength) {
    if (r === '.' || file.startsWith(r + '/')) return r;
  }
  return null;
}

// shared-foundation convention: a module root literally named `core` that
// requires nothing from sibling modules is the universal dependency floor —
// every module may require it without a direction entry (v1 core_free parity).
function deriveFreeTo(edges, roots) {
  const byLen = [...roots].sort((a, b) => b.length - a.length);
  const out = [];
  for (const r of roots) {
    if (path.posix.basename(r) !== 'core') continue;
    const hasOut = (edges || []).some((e) => rootOf(String(e.from || ''), byLen) === r
      && rootOf(String(e.to || ''), byLen) !== r
      && rootOf(String(e.to || ''), byLen) !== null);
    if (!hasOut) out.push(r);
  }
  return out.sort();
}

function deriveDirections(edges, roots, freeTo) {
  const byLen = [...roots].sort((a, b) => b.length - a.length);
  const free = new Set(freeTo || []);
  const counts = new Map();
  for (const e of edges || []) {
    const fr = rootOf(String(e.from || ''), byLen), tr = rootOf(String(e.to || ''), byLen);
    if (!fr || !tr || fr === tr) continue;
    if (free.has(tr)) continue;
    const k = fr + '\u0000' + tr;
    counts.set(k, (counts.get(k) || 0) + 1);
  }
  return [...counts.entries()]
    .map(([k, n]) => { const [from, to] = k.split('\u0000'); return { from, to, edges: n }; })
    .sort((a, b) => (a.from === b.from ? (a.to < b.to ? -1 : 1) : (a.from < b.from ? -1 : 1)));
}

// ---------- allowlist file loading + validation ----------

function loadAllowlistFile(root) {   // null = absent; {ok:false,err} = parse failure; {ok:true,doc}
  const p = allowlistPath(root);
  if (!fs.existsSync(p)) return null;
  try { return { ok: true, doc: JSON.parse(fs.readFileSync(p, 'utf8')) }; }
  catch (err) { return { ok: false, err: err.message }; }
}

function isV2(doc) {
  return !!(doc && typeof doc === 'object' && Array.isArray(doc.moduleRoots));
}

function validateV2(doc, depsFiles) {   // → problems[] (empty = healthy)
  const problems = [];
  const roots = doc.moduleRoots;
  if (roots.length === 0) problems.push('moduleRoots is empty');
  const files = new Set(depsFiles || []);
  const fileArr = depsFiles || [];
  for (const r of roots) {
    if (typeof r !== 'string' || !r) { problems.push('moduleRoots contains a non-string entry'); continue; }
    const exists = r === '.' ? fileArr.length > 0 : fileArr.some((f) => String(f).startsWith(r + '/'));
    if (!exists) problems.push(`moduleRoot "${r}" has no files in deps.json`);
  }
  const rootSet = new Set(roots);
  for (const d of doc.directions || []) {
    if (!d || typeof d !== 'object' || !rootSet.has(d.from) || !rootSet.has(d.to)) {
      problems.push(`direction ${d && d.from}→${d && d.to} endpoint is not a registered moduleRoot`);
    }
  }
  for (const ft of doc.free_to || []) {
    if (!rootSet.has(ft)) problems.push(`free_to entry "${ft}" is not a registered moduleRoot`);
  }
  return problems;
}

// violations under a HEALTHY doc (v1 or v2) for the given deps — shared by the
// gate assertion and the init confirmation gate
function edgeViolations(doc, deps) {
  const edges = deps.edges || [];
  const files = deps.files || [];
  const out = [];
  if (isV2(doc)) {
    const byLen = [...doc.moduleRoots].sort((a, b) => b.length - a.length);
    const dirs = new Set((doc.directions || []).map((d) => `${d.from}\u0000${d.to}`));
    const free = new Set(doc.free_to || []);
    for (const e of edges) {
      const fr = rootOf(String(e.from || ''), byLen), tr = rootOf(String(e.to || ''), byLen);
      if (!fr && !tr) continue;                     // both endpoints outside the module tree
      if (fr && tr) {
        if (fr === tr) continue;                    // same module (incl. subdirs): free
        if (free.has(tr)) continue;                 // shared foundation: free
        if (dirs.has(`${fr}\u0000${tr}`)) continue; // registered direction
        out.push({ from: e.from, to: e.to, fr, tr });
        continue;
      }
      // one endpoint outside every registered root = module drift after the
      // baseline was frozen (new module/file entered the require graph)
      const effFrom = fr || path.posix.dirname(String(e.from || ''));
      const effTo = tr || path.posix.dirname(String(e.to || ''));
      out.push({ from: e.from, to: e.to, fr: effFrom, tr: effTo, drift: true });
    }
    return out;
  }
  // legacy v1 shape: scope = bin/lib↔bin/lib file edges
  const dirsRaw = (doc.rules && doc.rules.directions_module) || doc.directions_module || [];
  const dirs = new Set(dirsRaw.map((d) => `bin/lib/${d.from}|bin/lib/${d.to}`));
  for (const e of edges) {
    if (!String(e.from || '').startsWith('bin/lib/') || !String(e.to || '').startsWith('bin/lib/')) continue;
    const fd = path.dirname(e.from), td = path.dirname(e.to);
    if (fd === td) continue;
    if (td === 'bin/lib/core') continue;            // →core free (v1 crossAllow)
    const fmod = fd.replace(/^bin\/lib\//, '').split('/')[0], tmod = td.replace(/^bin\/lib\//, '').split('/')[0];
    if (fmod === tmod) continue;                    // cross-aspect within one module
    if (!dirs.has(`${fd}|${td}`)) out.push({ from: e.from, to: e.to, fr: fd, tr: td });
  }
  return out;
}

// ---------- gate-side assertion (called from ops/gate codemap layer) ----------

function directionAssertion(root, deps) {   // → { lines: string[], failures: gateFail[] } (D-66 switch)
  const lines = [];
  const failures = [];
  const loaded = loadAllowlistFile(root);
  if (loaded === null) {
    lines.push('⚠ codemap: no require-allowlist.json — direction assertion off (generate with: gos map allowlist init) [advisory]');
    return { lines, failures };
  }
  if (!loaded.ok) {
    failures.push(core.gateFail('allowlist-parse-failed', { verdict: `codemap: require-allowlist.json parse failed (${loaded.err})`, evidence: ['require-allowlist.json'], fix: 'run: gos map allowlist init — regenerate the allowlist (path: .gos/codebase/require-allowlist.json)' }));
    return { lines, failures };
  }
  const doc = loaded.doc;
  const files = deps.files || [];
  if (!isV2(doc)) {
    const hasBinLib = files.some((f) => String(f).startsWith('bin/lib/'));
    if (!hasBinLib) {
      failures.push(core.gateFail('allowlist-legacy-v1', { verdict: 'codemap: require-allowlist.json is legacy v1 but deps.json has no bin/lib/* files', evidence: ['require-allowlist.json'], fix: 'run: gos map allowlist init — migrate the allowlist to v2' }));
      return { lines, failures };
    }
    const bad = edgeViolations(doc, deps);
    if (bad.length) {
      for (const b of bad.slice(0, 5)) failures.push(core.gateFail('require-direction-violation', { verdict: `codemap: ${core.t('map.allowlist.dirViolation', { from: b.from, to: b.to, fr: b.fr, tr: b.tr, drift: '' })}`, evidence: [`${b.from} → ${b.to}`], fix: 'fix the require or extend the whitelist: .gos/codebase/require-allowlist.json' }));
    } else {
      const n = ((doc.rules && doc.rules.directions_module) || doc.directions_module || []).length;
      const scoped = (deps.edges || []).filter((e) => String(e.from || '').startsWith('bin/lib/') && String(e.to || '').startsWith('bin/lib/')).length;
      if (n > 0 && scoped === 0) {
        lines.push('⚠ codemap: direction allowlist asserted 0 edges — no lib↔lib edges under bin/lib/ (vacuous pass flagged, not silent green)');
      } else {
        lines.push(`✓ codemap: ${core.t('map.allowlist.v1Green', { n })}`);
      }
    }
    return { lines, failures };
  }
  const problems = validateV2(doc, files);
  if (problems.length) {
    for (const p of problems.slice(0, 5)) failures.push(core.gateFail('allowlist-v2-invalid', { verdict: `codemap: require-allowlist.json v2 invalid: ${p}`, evidence: ['require-allowlist.json'], fix: 'run: gos map allowlist init — regenerate the allowlist' }));
    return { lines, failures };
  }
  const bad = edgeViolations(doc, deps);
  let scopeEdges = 0;
  const byLen = [...doc.moduleRoots].sort((a, b) => b.length - a.length);
  for (const e of deps.edges || []) {
    if (rootOf(String(e.from || ''), byLen) && rootOf(String(e.to || ''), byLen)) scopeEdges++;
  }
  if (bad.length) {
    for (const b of bad.slice(0, 5)) failures.push(core.gateFail('require-direction-violation', { verdict: `codemap: ${core.t('map.allowlist.dirViolation', { from: b.from, to: b.to, fr: b.fr, tr: b.tr, drift: b.drift ? core.t('map.allowlist.moduleDrift') : '' })}`, evidence: [`${b.from} → ${b.to}`], fix: 'run: gos map allowlist init — regenerate after fixing the require or moduleRoots' }));
    return { lines, failures };
  }
  const dirN = (doc.directions || []).length;
  if (dirN > 0 && scopeEdges === 0) {
    lines.push('⚠ codemap: direction allowlist asserted 0 edges — moduleRoots do not intersect the require graph (vacuous pass flagged, not silent green)');
    return { lines, failures };
  }
  lines.push(`✓ codemap: ${core.t('map.allowlist.v2Green', { modules: doc.moduleRoots.length, dirs: dirN, edges: scopeEdges })}`);
  return { lines, failures };
}

// ---------- init command ----------

async function confirmProceed(promptText) {   // null = headless/declined/unreadable
  if (core.detectActivationSource() === 'headless') return null;
  // core.ask (not raw readSync): libuv sets fd0 non-blocking, a raw read can
  // EAGAIN under a pty — the ask() stream path is the established pattern.
  try {
    const ans = await core.ask(promptText);
    return String(ans || '').trim().toLowerCase();
  } catch { return null; }
}

function sameStringSet(a, b) {
  if ((a || []).length !== (b || []).length) return false;
  const sa = new Set(a || []), sb = new Set(b || []);
  if (sa.size !== sb.size) return false;
  for (const x of sa) if (!sb.has(x)) return false;
  return true;
}

function sameEdgeSet(a, b) {
  const ka = (a || []).map((e) => `${e.from}\u0000${e.to}`).sort();
  const kb = (b || []).map((e) => `${e.from}\u0000${e.to}`).sort();
  return JSON.stringify(ka) === JSON.stringify(kb);
}

async function initAllowlist(root, opts) {
  const force = !!(opts && opts.force);
  const deps = engine.loadDeps(root);
  if (!deps) core.die('no deps.json on disk — run `gos map scan` first, then `gos map allowlist init`');
  // freshness gate: when the deps anchor does not match the worktree, re-scan in
  // memory and require the file set + require edges to be identical (the same
  // recompute-without-writing pattern the gate uses for closure truth)
  if (!engine.depsIsFresh(root, deps)) {
    const cur = engine.scanSources(root);
    if (!sameStringSet(cur.files, deps.files) || !sameEdgeSet(cur.edges, deps.edges)) {
      core.die('deps.json is stale vs the worktree (file set / require edges drifted) — run: gos map scan first');
    }
  }
  const roots = deriveModuleRoots(deps.edges || []);
  if (!roots.length) core.die('no require edges — nothing to assert, refusing to write an allowlist');
  const freeTo = deriveFreeTo(deps.edges || [], roots);
  const directions = deriveDirections(deps.edges || [], roots, freeTo);
  if (!directions.length) core.die('no cross-module require edges — nothing to assert, refusing to write an allowlist');
  const existing = loadAllowlistFile(root);
  if (existing && !existing.ok) core.die(`existing require-allowlist.json is unparseable (${existing.err}) — fix or delete it first`);
  if (existing && !force) {
    core.die('require-allowlist.json already exists — re-run with --force to review the direction diff and overwrite');
  }
  console.log(`derived ${roots.length} module root(s):`);
  for (const r of roots) console.log(`  ${r}`);
  console.log(freeTo.length ? `free targets (shared foundation, direction-free): ${freeTo.join(', ')}` : 'free targets: (none)');
  console.log(`directions (${directions.length}):`);
  for (const d of directions) console.log(`  ${d.from} → ${d.to} (${d.edges} edge${d.edges === 1 ? '' : 's'})`);
  if (existing) {
    if (isV2(existing.doc)) {
      const oldD = new Set((existing.doc.directions || []).map((d) => `${d.from}→${d.to}`));
      const newD = new Set(directions.map((d) => `${d.from}→${d.to}`));
      const added = [...newD].filter((k) => !oldD.has(k)).sort();
      const removed = [...oldD].filter((k) => !newD.has(k)).sort();
      console.log('direction diff (old → new):');
      if (!added.length && !removed.length) console.log('  (no changes)');
      for (const k of added) console.log(`  + ${k}`);
      for (const k of removed) console.log(`  - ${k}`);
    } else {
      console.log('direction diff (old → new): legacy v1 file — module-name directions do not map 1:1; the new baseline lists every current cross-module direction');
    }
    // confirmation gate: never silently legitimize edges the CURRENT file flags
    const curBad = edgeViolations(existing.doc, deps);
    if (curBad.length) {
      console.log(`⚠ ${curBad.length} edge(s) violate the CURRENT allowlist and the new baseline would legitimize them:`);
      for (const b of curBad.slice(0, 10)) console.log(`  ${b.from} → ${b.to} (${b.fr} → ${b.tr})`);
      if (curBad.length > 10) console.log(`  …(+${curBad.length - 10} more)`);
      const ans = await confirmProceed('proceed? [y/N] ');
      if (ans === null) core.die(`headless/unreadable input: refusing to auto-legitimize ${curBad.length} violation edge(s) — re-run from an interactive terminal or fix the edges first`);
      if (ans !== 'y') core.die('aborted — nothing written');
    }
  }
  const doc = {
    schema_version: 2,
    _comment: 'require-direction allowlist (generated by `gos map allowlist init`). moduleRoots: longest-match module dirs derived from require-edge endpoints; same-module edges are free; cross-module edges need a direction entry; free_to roots are direction-free targets.',
    moduleRoots: roots,
    directions,
    free_to: freeTo,
    generated_at: new Date().toISOString(),
  };
  core.writeAtomicJson(allowlistPath(root), doc);
  console.log(`✓ wrote .gos/codebase/require-allowlist.json (v2: ${roots.length} module root(s), ${directions.length} direction(s))`);
  console.log('Next: gos gate codemap — the direction assertion should turn green');
}

Object.assign(module.exports, {
  allowlistPath,
  deriveModuleRoots,
  deriveFreeTo,
  deriveDirections,
  loadAllowlistFile,
  directionAssertion,
  initAllowlist,
});
