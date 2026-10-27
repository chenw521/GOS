// map/views.cjs — map module aspect (render outlets: mermaid/ascii/html/dot + network.md)
// Require rules: same-directory mutual requires are free; cross-directory only → core
'use strict';

const engine = require('./engine.cjs');
const edges = require('./edges.cjs');
const anchor = require('./anchor.cjs');


const fs = require('node:fs');
const path = require('node:path');
const core = require('../core/index.cjs');

function mermaidEscapeLabel(t) {
  return String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;').replace(/[\n\r]/g, ' ');
}

function renderMermaid(pairs) {   // pairs: [{from, to, label, note?, external?}] — parallel (from,to) auto-aggregated
  const ids = [...new Set(pairs.flatMap((p) => [p.from, p.to]))].sort();   // dict order → stable ids (R2-F10)
  const idOf = new Map(ids.map((p, i) => [p, `n${i + 1}`]));
  const lines = ['graph TD'];
  for (const p of ids) lines.push(`  ${idOf.get(p)}["${mermaidEscapeLabel(p)}"]`);
 // aggregate parallel edges: same (from,to) → one line with n×type label
  const agg = new Map();
  for (const e of pairs) {
    const k = `${e.from}\u0000${e.to}\u0000${e.external ? 'ext' : 'std'}`;
    if (!agg.has(k)) agg.set(k, { from: e.from, to: e.to, external: e.external, types: new Map(), notes: [] });
    const a = agg.get(k);
    a.types.set(e.label, (a.types.get(e.label) || 0) + 1);
    if (e.note) a.notes.push(e.note);
  }
  for (const a of [...agg.values()].sort((x, y) => (x.from + x.to).localeCompare(y.from + y.to))) {
    const lbl = [...a.types.entries()].map(([t, n]) => (n > 1 ? `${n}×${t}` : t)).join('+');
    const arrow = a.external ? '-.->' : '-->';
    lines.push(`  ${idOf.get(a.from)} ${arrow}|"${mermaidEscapeLabel(lbl)}"| ${idOf.get(a.to)}${a.notes.length ? ` "${mermaidEscapeLabel(a.notes.join('; '))}"` : ''}`);
  }
  return '```mermaid\n' + lines.join('\n') + '\n```';
}

function renderMermaidClustered(pairs) {   // graph TD + per-layer subgraphs around the plain renderer's nodes
  const ids = [...new Set(pairs.flatMap((p) => [p.from, p.to]))].sort();
  const idOf = new Map(ids.map((p, i) => [p, `n${i + 1}`]));
  const byLayer = new Map();
  for (const n of ids) {
    const l = engine.layerOf(n);
    if (!byLayer.has(l)) byLayer.set(l, []);
    byLayer.get(l).push(n);
  }
  const header = ['graph TD'];
  for (const [l, nodes] of [...byLayer.entries()].sort()) {
    header.push(`  subgraph L_${l}["${l}"]`);
    for (const n of nodes) header.push(`    ${idOf.get(n)}["${mermaidEscapeLabel(n)}"]`);
    header.push('  end');
  }
  // edges (same aggregation as renderMermaid)
  const agg = new Map();
  for (const e of pairs) {
    const k = `${e.from}\u0000${e.to}\u0000${e.external ? 'ext' : 'std'}`;
    if (!agg.has(k)) agg.set(k, { from: e.from, to: e.to, external: e.external, types: new Map(), notes: [] });
    const a = agg.get(k);
    a.types.set(e.label, (a.types.get(e.label) || 0) + 1);
    if (e.note) a.notes.push(e.note);
  }
  for (const a of [...agg.values()].sort((x, y) => (x.from + x.to).localeCompare(y.from + y.to))) {
    const lbl = [...a.types.entries()].map(([t, n]) => (n > 1 ? `${n}×${t}` : t)).join('+');
    const arrow = a.external ? '-.->' : '-->';
    const unv = a.external ? ' (unverifiable)' : '';   // [P1-m1] external annotation
    header.push(`  ${idOf.get(a.from)} ${arrow}|"${mermaidEscapeLabel(lbl + unv)}"| ${idOf.get(a.to)}`);
  }
  return '```mermaid\n' + header.join('\n') + '\n```';
}

function renderAscii(pairs) {   // box-drawing tree grouped by layer (R-05)
  const byLayer = new Map();
  const nodes = [...new Set(pairs.flatMap((p) => [p.from, p.to]))].sort();
  for (const n of nodes) {
    const l = engine.layerOf(n);
    if (!byLayer.has(l)) byLayer.set(l, []);
    byLayer.get(l).push(n);
  }
  const adj = new Map();   // node → [label target]
  for (const p of pairs) {
    if (!adj.has(p.from)) adj.set(p.from, []);
    adj.get(p.from).push(`${p.label}→ ${p.to}${p.external ? ' (ext)' : ''}`);
  }
  const lines = ['anchor network (ascii quick view — `gos map graph --html` for interactive)'];
  for (const [l, ns] of [...byLayer.entries()].sort()) {
    lines.push(`${l}/`);
    ns.forEach((n, i) => {
      const branch = i === ns.length - 1 ? '└── ' : '├── ';
      lines.push(`  ${branch}${n}`);
      const outs = adj.get(n) || [];
      outs.forEach((o, j) => {
        const sub = i === ns.length - 1 ? '    ' : '│   ';
        const b2 = j === outs.length - 1 ? '└── ' : '├── ';
        lines.push(`  ${sub}${b2}${o}`);
      });
    });
  }
  return lines.join('\n');
}

function renderHtml(pairs) {   // self-contained single file: embedded data + vanilla JS (R-05)
  const data = JSON.stringify({ pairs });
  const esc = (t) => String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const byLayer = new Map();
  const nodes = [...new Set(pairs.flatMap((p) => [p.from, p.to]))].sort();
  for (const n of nodes) {
    const l = engine.layerOf(n);
    if (!byLayer.has(l)) byLayer.set(l, []);
    byLayer.get(l).push(n);
  }
  let body = '';
  for (const [l, ns] of [...byLayer.entries()].sort()) {
    body += `<details open><summary>${esc(l)} (${ns.length})</summary><ul>`;
    for (const n of ns) body += `<li class="node" data-n="${esc(n)}">${esc(n)}</li>`;
    body += '</ul></details>';
  }
  return `<!DOCTYPE html>
<html lang="zh"><head><meta charset="utf-8"><title>GOS anchor network</title>
<style>
body{font-family:ui-monospace,monospace;margin:1em;max-width:72em}
input{width:24em;padding:.3em;margin-bottom:.8em}
details{margin:.4em 0}summary{cursor:pointer;font-weight:700}
li.node{cursor:pointer;padding:.1em .4em;border-radius:4px;list-style:none}
li.node:hover{background:#e8f0fe}
li.node.sel{background:#c8daf8}
#edges{margin-top:1em;border-top:1px solid #ccc;padding-top:.6em;white-space:pre-wrap}
</style></head><body>
<h3>GOS anchor network</h3>
<input id="q" placeholder="search nodes…" autofocus>
${body}
<div id="edges">click a node to see its edges</div>
<script id="data" type="application/json">${data.replace(/</g, '\\u003c')}</script>
<script>
const D = JSON.parse(document.getElementById('data').textContent);
const q = document.getElementById('q'), EV = document.getElementById('edges');
q.addEventListener('input', () => {
  const t = q.value.toLowerCase();
  document.querySelectorAll('li.node').forEach((li) => {
    li.style.display = !t || li.dataset.n.toLowerCase().includes(t) ? '' : 'none';
  });
});
document.querySelectorAll('li.node').forEach((li) => li.addEventListener('click', () => {
  document.querySelectorAll('li.node').forEach((x) => x.classList.remove('sel'));
  li.classList.add('sel');
  const n = li.dataset.n;
  const out = D.pairs.filter((p) => p.from === n || p.to === n)
    .map((p) => (p.from === n ? p.label + ' --> ' + p.to : p.from + ' --> (' + p.label + ')'))
    .join('\\n');
  EV.textContent = out || '(no edges)';
}));
</script></body></html>`;
}

function renderDot(pairs) {   // graphviz contract format (external renderer interface)
  const ids = [...new Set(pairs.flatMap((p) => [p.from, p.to]))].sort();
  const idOf = new Map(ids.map((p, i) => [p, `n${i}`]));
  const q = (t) => `"${String(t).replace(/"/g, '\\"')}"`;
  const lines = ['digraph gos_anchor_network {', '  rankdir=LR;'];
  for (const n of ids) lines.push(`  ${idOf.get(n)} [label=${q(n)}];`);
  const agg = new Map();
  for (const e of pairs) {
    const k = `${e.from}\u0000${e.to}\u0000${e.external ? 1 : 0}`;
    if (!agg.has(k)) agg.set(k, { from: e.from, to: e.to, external: e.external, types: new Map() });
    const a = agg.get(k);
    a.types.set(e.label, (a.types.get(e.label) || 0) + 1);
  }
  for (const a of agg.values()) {
    const lbl = [...a.types.entries()].map(([t, n]) => (n > 1 ? `${n}x${t}` : t)).join('+');
    lines.push(`  ${idOf.get(a.from)} -> ${idOf.get(a.to)} [label=${q(lbl)}${a.external ? ',style=dashed' : ''}];`);
  }
  lines.push('}');
  return lines.join('\n');
}

const NETWORK_MD = path.join('.gos', 'codebase', 'network.md');

function networkBackupDir(root) { return path.join(root, '.gos', core.GOS_PATHS.backups_dir.rel); }

function renderNetworkMd(root, sem, hand) {
  const lines = [
    core.CONTRACTS.command_contracts.generatedHeader,
    '# GOS Anchor Network (map 2.0)',
    '',
    core.t('map.net.intro'),
    '',
    '## ' + core.t('map.net.autoSection'),
    '',
    '### ' + core.t('map.net.familyStats'),
    '',
    '| family | count |',
    '|:--|:--|',
  ];
  const fams = [
    [core.t('map.family.calls'), (sem.calls || []).length],
    [core.t('map.family.contracts'), (sem.contracts || []).length],
    ['switch (④case↔cmdXxx)', (sem.switch || []).length],
    [core.t('map.family.testof'), (sem.testof || []).length],
    [core.t('map.family.hand'), hand ? hand.edges.length : 0],
  ];
 // single loop over the FULL family registry
  // future families only need a row here (or ride semantic.* automatically below)
  for (const [n, c] of fams) lines.push(`| ${n} | ${c} |`);
  const fnFams = [
    ['callgraph (⑥fn↔fn, acorn)', (sem.callgraph || []).length],
    [core.t('map.family.testof_fn'), (sem.testof_fn || []).length],
  ];
  for (const [n, c] of fnFams) lines.push(`| ${n} | ${c} |`);
  const pfN = (sem.parse_failures || []).length;
  if (pfN) lines.push(`| parse_failures | ${pfN} |`);
  if (sem.acorn_missing) lines.push('| acorn_missing | true |');
  lines.push('', '### ' + core.t('map.net.handDetail'), '', '| from | to | type | note |', '|:--|:--|:--|:--|');
  if (hand && hand.edges.length) {
    for (const e of hand.edges) lines.push(`| ${core.escCellMd(e.from)} | ${core.escCellMd(e.to)} | ${core.escCellMd(e.type)} | ${core.escCellMd(e.note || '')} |`);
  } else {
    lines.push('| (none) | | | |');
  }
  lines.push('', '### ' + core.t('map.net.closureQuickRef'), '', '| cmd | sections |', '|:--|:--|');
  const byCmd = new Map();
  for (const t of sem.testof || []) {
    if (!byCmd.has(t.cmd)) byCmd.set(t.cmd, new Set());
    byCmd.get(t.cmd).add(t.sec);
  }
  for (const [cmd, secs] of [...byCmd.entries()].sort()) lines.push(`| ${core.escCellMd(cmd)} | ${core.escCellMd([...secs].sort().join(', '))} |`);
 // fn-level quick reference: fn → testing sections (from testof_fn)
  const byFn = new Map();
  for (const t of sem.testof_fn || []) {
    const k = `${t.file}#fn:${t.fn}`;
    if (!byFn.has(k)) byFn.set(k, new Set());
    byFn.get(k).add(t.sec);
  }
  lines.push('', '### ' + core.t('map.net.fnQuickRef'), '', '| fn | sections |', '|:--|:--|');
  if (byFn.size) {
    for (const [fn, secs] of [...byFn.entries()].sort()) lines.push(`| ${core.escCellMd(fn)} | ${core.escCellMd([...secs].sort().join(', '))} |`);
  } else {
    lines.push('| (none — annotate test section headers with `gos-map:fn <name>`) | |');   // [REVIEW m6] 2 cells to match header
  }
  // mermaid full graph (same pairs logic as map graph)
  const pairs = [];
  const seen = new Set();
  const push = (from, to, label, note, external) => {
    const k = `${from}\u0000${to}\u0000${label}`;
    if (seen.has(k)) return;
    seen.add(k);
    pairs.push({ from, to, label, note, external });
  };
  for (const e of sem.calls || []) push(e.file, `cmd:${e.cmd}`, 'calls');
  for (const e of sem.contracts || []) push(e.file, `key:${e.key}`, 'asserts');
  for (const e of sem.switch || []) push(`cmd:${e.cmd}`, `fn:${e.fn}`, 'dispatches');
  for (const e of sem.testof || []) push(`sec:${e.sec}`, `cmd:${e.cmd}`, 'tested-by');
  if (hand) for (const e of hand.edges) push(core.pathOf(e.from), core.pathOf(e.to), e.type, e.note, !!e.external);
  lines.push('', '### ' + core.t('map.net.fullGraph'), '', renderMermaid(pairs), '',
    core.CONTRACTS.command_contracts.manualMarker,
    '<!-- MANUAL region: hand-written notes live BELOW this line and survive every scan -->',
    '');
  return lines.join('\n');
}

function refreshNetworkMd(root) {
  const SC = core.CONTRACTS.semantic_checks;
  const sem = engine.runExtractors(root, engine.scanSources(root).files, (f) => fs.readFileSync(path.join(root, f), 'utf8'));
  const hand = edges.loadEdges(root);
  const target = path.join(root, NETWORK_MD);
  let manual = null;
  if (fs.existsSync(target)) {
    const prev = fs.readFileSync(target, 'utf8');
    manual = anchor.manualRegion(prev);
    if (manual === null) core.die(`✗ ${SC.networkMarkerMissing}`);   // R2-F8: refuse, never burn
    try {   // backup rotation (keep 5 — render-backup precedent)
      fs.mkdirSync(networkBackupDir(root), { recursive: true });
      for (let i = 4; i >= 1; i--) {
        const from = path.join(networkBackupDir(root), `network.md.${i}`);
        const to = path.join(networkBackupDir(root), `network.md.${i + 1}`);
        if (fs.existsSync(from)) fs.renameSync(from, to);
      }
      fs.copyFileSync(target, path.join(networkBackupDir(root), 'network.md.1'));
    } catch { /* backup best-effort; refresh itself is atomic below */ }
  }
  const body = renderNetworkMd(root, sem, hand);
  const out = manual ? body.replace(new RegExp(core.CONTRACTS.command_contracts.manualMarker.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '[\\s\\S]*$'), () => manual) : body;   // [R2-M1] function form: $&/$`/$' in manual text must never be interpreted
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const tmp = target + '.tmp';
  fs.writeFileSync(tmp, out);
  fs.renameSync(tmp, target);
}

Object.assign(module.exports, {
  mermaidEscapeLabel,
  renderMermaid,
  renderMermaidClustered,
  renderAscii,
  renderHtml,
  renderDot,
  networkBackupDir,
  renderNetworkMd,
  refreshNetworkMd,
  NETWORK_MD,
});   // assign, not reassign: keeps live references across the same-directory require cycle (CJS value semantics)
