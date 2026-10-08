#!/usr/bin/env bash
# gos map graph --renderer echarts
# Receives the full graph JSON on stdin: {"pairs":[{from,to,label,note,external}...]}
# Emits a self-contained interactive HTML (force-directed, ECharts 5 via CDN) on stdout.
# Usage: node bin/gos.cjs map graph --renderer echarts > net.html && open net.html
PAYLOAD="$(cat)"   # stdin carries the graph JSON — capture BEFORE the heredoc takes over
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

nodes_seq = []
seen = set()
for p in pairs:
    for k in (p['from'], p['to']):
        if k not in seen:
            seen.add(k); nodes_seq.append(k)

CATS = ['impl', 'command', 'tests', 'docs', 'contract']
cat_idx = {c: i for i, c in enumerate(CATS)}

deg = {}
nodes = []
for n in nodes_seq:
    nodes.append({'id': n, 'name': n, 'category': cat_idx[layer_of(n)], 'symbolSize': 6})
for p in pairs:
    deg[p['from']] = deg.get(p['from'], 0) + 1
    deg[p['to']] = deg.get(p['to'], 0) + 1
for nd in nodes:
    k = deg.get(nd['id'], 0)
    nd['symbolSize'] = min(8 + k * 2.2, 44)
    nd['value'] = k

links = []
ldeg = {}
for p in pairs:
    k = f"{p['from']}\u0000{p['to']}"
    ldeg[k] = ldeg.get(k, 0) + 1
for p in pairs:
    k = f"{p['from']}\u0000{p['to']}"
    if ldeg[k] == -1: continue
    n_edge = ldeg[k]; ldeg[k] = -1
    lbl = p['label'] + (f' ×{n_edge}' if n_edge > 1 else '')
    links.append({
        'source': p['from'], 'target': p['to'],
        'value': lbl,
        'lineStyle': {'width': min(1 + n_edge * 0.6, 5), 'opacity': 0.55,
                      **({'type': 'dashed', 'opacity': 0.35} if p.get('external') else {})},
    })

payload = json.dumps({'nodes': nodes, 'links': links, 'cats': CATS}, ensure_ascii=False)
title = html.escape(f"GOS anchor network — {len(nodes)} nodes / {len(links)} edges")

print(f"""<!DOCTYPE html>
<html lang="zh"><head><meta charset="utf-8"><title>GOS anchor network</title>
<script src="https://cdn.jsdelivr.net/npm/echarts@5.5.0/dist/echarts.min.js"></script>
<style>
html,body{{margin:0;height:100%;background:#0f1420;overflow:hidden}}
#chart{{width:100vw;height:100vh}}
#tip{{position:fixed;left:12px;top:10px;color:#8ab;font:12px ui-monospace,monospace;z-index:9}}
</style></head><body>
<div id="tip">{title} — scroll to zoom / drag to pan / click a node to highlight its neighborhood / legend toggles layers</div>
<div id="chart"></div>
<script>
const D = {payload};
const PALETTE = ['#4992ff','#fac858','#3fe1b1','#b56cf5','#68d6ff'];
const chart = echarts.init(document.getElementById('chart'), null, {{renderer:'canvas'}});
chart.setOption({{
  backgroundColor:'#0f1420',
  tooltip:{{formatter:(p)=>p.dataType==='edge' ? (p.data.source+'<br/>──['+p.data.value+']──▶<br/>'+p.data.target) : (p.name+'<br/>'+p.data.value+' edges')}},
  legend:{{data:D.cats,textStyle:{{color:'#9db4d0'}},top:8,right:12,selectedMode:'multiple'}},
  series:[{{
    type:'graph', layout:'force', roam:true, draggable:true,
    categories:D.cats.map((c,i)=>({{name:c,itemStyle:{{color:PALETTE[i]}}}})),
    color:PALETTE,
    force:{{repulsion:170,edgeLength:[35,140],gravity:0.08,friction:0.25}},
    data:D.nodes, links:D.links,
    label:{{show:true,color:'#c9d8ee',fontSize:10,formatter:(p)=>p.name.length>28?p.name.slice(0,26)+'…':p.name}},
    emphasis:{{focus:'adjacency',lineStyle:{{width:6,opacity:1}},label:{{fontSize:13,fontWeight:'bold'}}}},
    lineStyle:{{curveness:0.18,color:'#5a7bb0',opacity:0.5}},
    arrowTypeInLink: true,
    scaleLimit:{{min:0.25,max:6}},
  }}],
}});
window.addEventListener('resize',()=>chart.resize());
</script></body></html>""", end='')
PYEOF
