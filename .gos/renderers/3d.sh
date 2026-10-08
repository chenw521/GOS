#!/usr/bin/env bash
# gos map graph --renderer 3d
# stdin: {"pairs":[...]} — emits a self-contained interactive 3D HTML (3d-force-graph / three.js WebGL, CDN).
# Usage: node bin/gos.cjs map graph --renderer 3d > net-3d.html && open net-3d.html
PAYLOAD="$(cat)"
python3 - "$PAYLOAD" <<'PYEOF'
import json, sys, html

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

CATS = ['impl', 'command', 'tests', 'docs', 'contract']
CAT_COLOR = {'impl': '#4992ff', 'command': '#ffb84d', 'tests': '#3fe1b1', 'docs': '#b56cf5', 'contract': '#68d6ff'}

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
        nodes.append({'id': k, 'name': k, 'cat': layer_of(k), 'val': 1 + deg.get(k, 0) * 1.6})

links = [{'source': p['from'], 'target': p['to'], 'label': p['label']} for p in pairs]

payload = json.dumps({'nodes': nodes, 'links': links, 'colors': CAT_COLOR, 'cats': CATS}, ensure_ascii=False)
title = html.escape(f"GOS 3D — {len(nodes)} nodes / {len(links)} edges")

print(f"""<!DOCTYPE html>
<html lang="zh"><head><meta charset="utf-8"><title>GOS 3D anchor network</title>
<style>html,body{{margin:0;height:100%;background:#000009;overflow:hidden}}
#tip{{position:fixed;left:14px;top:12px;color:#7ecbff;font:12px ui-monospace,monospace;z-index:9;text-shadow:0 0 8px #0af}}
</style></head><body>
<div id="tip">{title} — drag to rotate / scroll to zoom / click a node to highlight its neighborhood / double-click background to reset</div>
<script src="https://unpkg.com/3d-force-graph@1"></script>
<script>
const D = {payload};
const el = document.createElement('div');
document.body.appendChild(el);
const Graph = ForceGraph3D()(el)
  .backgroundColor('#000009')
  .nodeLabel(n => n.name)
  .nodeColor(n => D.colors[n.cat])
  .nodeVal(n => n.val)
  .nodeOpacity(0.95)
  .linkColor(() => 'rgba(110,160,230,0.28)')
  .linkOpacity(0.28)
  .linkWidth(0.35)
  .graphData(D);

// click → adjacency spotlight (double-click background resets)
const HIGHLIGHT = {{color:'#ffffff'}};
Graph.onNodeClick(n => {{
  const keep = new Set([n.id, ...D.links.filter(l => l.source===n.id || l.target===n.id)
    .flatMap(l => [l.source===n.id?l.target:l.source])]);
  Graph.nodeColor(o => keep.has(o.id) ? D.colors[o.cat] : 'rgba(40,60,90,0.18)')
       .linkColor(l => (l.source===n.id || l.target===n.id) ? 'rgba(160,220,255,0.9)' : 'rgba(30,45,70,0.12)')
       .linkWidth(l => (l.source===n.id || l.target===n.id) ? 1.2 : 0.1);
}});
Graph.onBackgroundClick(() => {{
  Graph.nodeColor(o => D.colors[o.cat]).linkColor(() => 'rgba(110,160,230,0.28)').linkWidth(0.35);
}});
// slow auto-rotate until first interaction
Graph.controls().autoRotate = true;
Graph.controls().autoRotateSpeed = 0.6;
el.addEventListener('pointerdown', () => {{ Graph.controls().autoRotate = false; }}, {{once:true}});
</script></body></html>""", end='')
PYEOF
