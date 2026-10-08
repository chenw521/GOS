#!/usr/bin/env bash
# gos map graph --renderer g6
# stdin: {"pairs":[...]} — emits a self-contained interactive HTML (AntV G6 v5, CDN).
# Usage: node bin/gos.cjs map graph --renderer g6 > net-g6.html && open net-g6.html
PAYLOAD="$(cat)"
python3 - "$PAYLOAD" <<'PYEOF'
import json, sys

d = json.loads(sys.argv[1])
pairs = d.get('pairs', [])

def layer_of(n):
    if n.startswith('cmd:'): return 'command'
    if n.startswith('sec:'): return 'tests'
    if n.startswith('key:'): return 'contract'
    if n.startswith('fn:'): return 'impl'
    top = n.split('/')[0]
    if top in ('skills', 'docs', 'commands', '.opencode', '.claude-plugin', '.codex') or top.startswith('README'): return 'docs'
    if top == 'test': return 'tests'
    return 'impl'

deg = {}
for p in pairs:
    deg[p['from']] = deg.get(p['from'], 0) + 1
    deg[p['to']] = deg.get(p['to'], 0) + 1

nodes, seen = [], set()
for p in pairs:
    for k in (p['from'], p['to']):
        if k in seen:
            continue
        seen.add(k)
        nodes.append({'id': k, 'data': {'cat': layer_of(k), 'deg': deg.get(k, 0)}})

edges = [{'source': p['from'], 'target': p['to'], 'data': {'label': p['label'], 'ext': bool(p.get('external'))}} for p in pairs]

payload = json.dumps({'nodes': nodes, 'edges': edges}, ensure_ascii=False)
title = 'GOS 3D-free — %d nodes / %d edges (AntV G6 v5)' % (len(nodes), len(edges))

page = r"""<!DOCTYPE html>
<html lang="zh"><head><meta charset="utf-8"><title>GOS anchor network (G6)</title>
<script src="https://unpkg.com/@antv/g6@5/dist/g6.min.js"></script>
<style>
html,body{margin:0;height:100%;overflow:hidden}
body{background:radial-gradient(ellipse at 50% 30%,#0d1526 0%,#05080f 75%)}
#tip{position:fixed;left:14px;top:10px;color:#7ecbff;font:12px ui-monospace,monospace;z-index:9}
</style></head><body>
<div id="tip">TITLE_PLACEHOLDER — scroll to zoom / drag canvas and nodes / hover an edge for details</div>
<div id="container" style="width:100vw;height:100vh"></div>
<script>
const D = DATA_PLACEHOLDER;
const PALETTE = {impl:'#4992ff', command:'#ffb84d', tests:'#3fe1b1', docs:'#b56cf5', contract:'#68d6ff'};
const graph = new G6.Graph({
  container: 'container',
  autoFit: 'view',
  data: D,
  node: {
    style: (n) => ({
      size: Math.min(10 + n.data.deg * 1.6, 40),
      fill: PALETTE[n.data.cat] || '#7a8ba6',
      stroke: 'rgba(255,255,255,0.45)', lineWidth: 1.4,
      shadowBlur: n.data.deg >= 12 ? 16 : 6, shadowColor: PALETTE[n.data.cat] || '#7a8ba6',
      labelText: n.id,
      label: n.data.deg >= 12,
      labelFill: '#e8f2ff', labelFontSize: 12, labelFontWeight: 600,
      labelFontFamily: 'ui-monospace', labelBackground: true,
      labelBackgroundFill: 'rgba(5,8,15,0.75)', labelBackgroundRadius: 4,
      labelPlacement: 'right', labelPadding: [0, 2],
    }),
  },
  edge: {
    style: (e) => ({
      stroke: {calls:'#4a9eff', asserts:'#b56cf5', dispatches:'#3fe1b1', 'tested-by':'#5ad8c8', hand:'#ffb84d'}[e.data.label] || '#7a8ba6',
      lineWidth: 0.9, opacity: 0.5, curveOffset: 12,
      endArrow: true, endArrowSize: 6,
      dashed: e.data.ext,
    }),
  },
  layout: {
    type: 'd3-force',
    manyBody: { strength: -320 },
    link: { distance: 100 },
    x: { strength: 0.04 }, y: { strength: 0.04 },
  },
  behaviors: ['zoom-canvas', 'drag-canvas', 'drag-element'],
  plugins: [
    { type: 'tooltip',
      getContent: (e) => {
        const t = e.targetType === 'edge'
          ? e.target.data.source + '<br/><b style="color:#8fd0ff">──[' + e.target.data.label + ']──▶</b><br/>' + e.target.data.target
          : '<b>' + e.target.id + '</b><br/>' + e.target.data.cat + ' · ' + e.target.data.deg + ' edges';
        return '<div style="font-family:ui-monospace;font-size:12px">' + t + '</div>';
      } },
  ],
});
graph.render();
</script></body></html>"""

page = page.replace('TITLE_PLACEHOLDER', title).replace('DATA_PLACEHOLDER', payload)
sys.stdout.write(page)
PYEOF
