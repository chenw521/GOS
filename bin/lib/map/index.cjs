// map/index.cjs — module entry: command surface + spread-merged aspects (the single entry wiring point)
'use strict';

const { execFileSync } = require('node:child_process');

const fs = require('node:fs');
const path = require('node:path');
const core = require('../core/index.cjs');
const engine = require('./engine.cjs');
const edges = require('./edges.cjs');
const views = require('./views.cjs');
const anchor = require('./anchor.cjs');
const contract = require('./contract.cjs');
const allowlist = require('./allowlist.cjs');


function cmdMap(args) {
  const sub = args[0];
  const SC = core.CONTRACTS.semantic_checks;
  const root = core.mapRootDir();
  const here = fs.realpathSync('.');
  if (here !== root) console.error(`⚠ ${SC.mapCwdBanner.replace('<subdir>', path.relative(root, here) || '.').replace('<root>', root)}`);
  if (sub === 'graph') {   // T8+R-05: graph family — mermaid (default) | --ascii | --html | --dot | --renderer | --fn <anchor> (fn neighborhood)
 // --fn requires an anchor argument: renders that fn's 1-hop
    // neighborhood (callers + testing sections); --2hop extends caller depth. Bare --fn dies.
    const fnIdx = args.indexOf('--fn');
    if (fnIdx >= 0) {
      const spec = args[fnIdx + 1];
      if (!spec || spec.startsWith('--') || /#fn:/.test(spec) === false) core.die('Usage: gos map graph --fn <path#fn:name> [--2hop] — a fn anchor is required (the full graph deliberately omits fn families)');
      const i = spec.lastIndexOf('#fn:');
      const changed = [{ file: spec.slice(0, i), fn: spec.slice(i + 4) }];
      const deps = engine.loadDeps(root);
      if (!deps) core.die('✗ no deps.json on disk — run `gos map scan` first (--fn reads the v3 cache)');
      const r = engine.fnClosure(deps, changed);
      const twohopFn = args.includes('--2hop');
      const pairs = [];
      for (const [k, callers] of r.fnMustCheck) for (const c of callers) pairs.push({ from: c, to: k, label: 'called-by' });
      for (const [sec, fns] of r.fnMustRun) for (const f of fns) pairs.push({ from: `sec:${sec}`, to: f, label: 'tests' });
      if (twohopFn) {
        // extend one more reverse hop: callers-of-callers
        const edgesL = (deps.semantic || {}).callgraph || [];
        const seenK = new Set([...r.fnMustCheck.values()].flatMap((s) => [...s]));
        for (const k of [...r.fnMustCheck.values()].flatMap((s) => [...s])) {
          const [file, fn] = [k.slice(0, k.lastIndexOf('#fn:')), k.slice(k.lastIndexOf('#fn:') + 4)];
          for (const e of edgesL) if (e.file === file && e.to === fn && !seenK.has(`${e.file}#fn:${e.from}`)) pairs.push({ from: `${e.file}#fn:${e.from}`, to: k, label: 'called-by-2' });
        }
      }
      if (!pairs.length) pairs.push({ from: spec, to: '(no known callers/tests)', label: 'verified-empty' });
      if (args.includes('--ascii')) console.log(views.renderAscii(pairs));
      else console.log(views.renderMermaid(pairs));
      console.error(SC.mapBanner);
      return;
    }
    const { pairs } = engine.buildGraphPairs(root);
    if (args.includes('--ascii')) {
      console.log(views.renderAscii(pairs));
    } else if (args.includes('--html')) {
      console.log(views.renderHtml(pairs));   // self-contained single file; redirect to .html and open
    } else if (args.includes('--dot')) {
      console.log(views.renderDot(pairs));   // contract format for external renderers (graphviz & friends)
    } else if (args.includes('--renderer')) {
      const ri = args.indexOf('--renderer');
      const name = args[ri + 1];
      if (!name || name.startsWith('--')) core.die('Usage: gos map graph --renderer <name> (scripts in .gos/renderers/<name>.sh receive graph JSON on stdin)');
      const script = path.join(root, '.gos', 'renderers', `${name}.sh`);
      if (!fs.existsSync(script)) core.die(`✗ renderer plugin not found: ${script} — create it (executable, receives {"pairs":[...]} on stdin, prints anything)`);
      const payload = JSON.stringify({ pairs, hint: 'see .gos/renderers/ — stdin is the graph JSON' });
      try {
        console.log(execFileSync('bash', [script], { input: payload, encoding: 'utf8', stdio: ['pipe', 'pipe', 'inherit'] }).trimEnd());
      } catch (e) { core.die(`✗ renderer plugin failed (${name}): ${e.message}`); }
    } else {
      console.log(views.renderMermaidClustered(pairs));   // default: mermaid (platform-rendered)
    }
    console.error(SC.mapBanner);   // advisory goes to stderr — stdout stays the artifact
    return;
  }
  if (sub === 'anchor') {   // T1 (D-21/D-22): single-anchor validation — read-class debug exit
    const spec = args[1];
    if (!spec || args.length > 2) core.die('Usage: gos map anchor <path[#anchor]>');
    const v = anchor.validateAnchor(spec, root);
    if (!v.ok) core.die(v.msg);
    console.log(`✓ ${SC.anchorVerifOk.replace('<type>', v.type).replace('<detail>', v.detail)}`);
    return;
  }
  if (sub === 'edge') {   // T2 (D-22): hand-edge CLI — ROOT-locked, audited, atomic
    const esub = args[1];
    const pos = args.slice(2).filter((a) => !a.startsWith('--'));
    const flag = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
    if (esub === 'add') {
      const [from, to] = pos;
      const type = flag('--type') || 'consumes';
      const note = flag('--note') || '';
      const external = args.includes('--external');   // §4.2: cross-repo/unverifiable endpoint
      if (!from || !to || !edges.EDGE_TYPES.has(type)) core.die(`Usage: gos map edge add <from> <to> [--type t] [--note n] [--external]\n${from && to ? `✗ ${SC.edgeBadType.replace('<type>', type)}` : ''}`);
      core.acquireEdgeLock();   // [R2-C2 fix] ROOT-anchored (cwd fork bypassed mutual exclusion)
      const d = edges.loadEdges(root);
      const existed = !!d;
      const edgesL = d ? d.edges : [];
      if (edgesL.some((e) => e.from === from && e.to === to && e.type === type)) core.die(`✗ ${SC.edgeDup}`);
      for (const [label, spec2] of [['from', from], ['to', to]]) {   // dead edges never enter the file (R-01)
        if (external && label === 'to') continue;   // §4.2: external endpoint exempt from dead-path die
        const v = anchor.validateAnchor(spec2, root);
        if (!v.ok) core.die(`${v.msg} (${label}: ${spec2})`);
      }
      const rec = { from, to, type };
      if (note) rec.note = note;
      if (external) rec.external = true;   // exempt from dead-path die; rendered dashed + unverifiable
      edgesL.push(rec);
      edges.writeEdges(root, edgesL, existed);
      if (fs.existsSync(edges.edgesLockPath(root))) edges.freezeEdgesLock(root);   // transactional re-freeze (R2-F2)
      edges.auditEdge(root, 'add', from, to, type);
      console.log(`✓ edge added: ${from} --[${type}]--> ${to} (${edgesL.length} edge(s))`);
      return;
    }
    if (esub === 'rm') {
      const [from, to] = pos;
      const type = flag('--type');
      if (!from || !to) core.die('Usage: gos map edge rm <from> <to> [--type t]');
      core.acquireEdgeLock();
      const d = edges.loadEdges(root);
      if (!d) core.die(`✗ ${SC.edgesParseFail} — no edges.json on disk; run: gos map edge adopt --bootstrap`);
      const before = d.edges.length;
      d.edges = d.edges.filter((e) => !(e.from === from && e.to === to && (!type || e.type === type)));
      if (d.edges.length === before) core.die(`✗ no matching edge (${from} -> ${to}) — nothing removed`);
      edges.writeEdges(root, d.edges, true);
      if (fs.existsSync(edges.edgesLockPath(root))) edges.freezeEdgesLock(root);
      edges.auditEdge(root, 'rm', from, to, type || '*');
      console.log(`✓ edge removed: ${from} -> ${to} (${d.edges.length} edge(s) left)`);
      return;
    }
    if (esub === 'rewrite') {
      const from = flag('--from'), to = flag('--to');
      if (!from || !to) core.die('Usage: gos map edge rewrite --from <oldAnchor> --to <newAnchor>');
      core.acquireEdgeLock();
      const d = edges.loadEdges(root);
      if (!d) core.die(`✗ ${SC.edgesParseFail} — no edges.json on disk; run: gos map edge adopt --bootstrap`);
      const v = anchor.validateAnchor(to, root);
      if (!v.ok) core.die(`${v.msg} (--to: ${to})`);   // never rewrite INTO a dead anchor
      let n = 0;
      for (const e of d.edges) {
        if (e.from === from) { e.from = to; n++; }
        else if (e.to === from) { e.to = to; n++; }
      }
      if (!n) core.die(`✗ no edge references ${from} — nothing rewritten`);
      edges.writeEdges(root, d.edges, true);
      if (fs.existsSync(edges.edgesLockPath(root))) edges.freezeEdgesLock(root);
      edges.auditEdge(root, 'rewrite', from, to, '*');
      console.log(`✓ rewrote ${n} edge endpoint(s): ${from} => ${to}`);
      return;
    }
    if (esub === 'adopt') {
      const bootstrap = args.includes('--bootstrap');
      core.acquireEdgeLock();
      if (bootstrap) {
        if (fs.existsSync(edges.edgesPath(root))) core.die(`✗ ${SC.edgeAdoptExists}`);
        edges.writeEdges(root, [], false);
        console.log(`✓ seeded empty tracked edges.json (${edges.edgesPath(root)}) — git add forced`);
        return;
      }
 // plain adopt = "I reviewed the current edges.json" → (re)freeze the tracked anchor .
 // LEGITIMATE rescue path after merges/rebases — audit-logged.
      if (!fs.existsSync(edges.edgesPath(root))) core.die(`✗ ${SC.edgeAdoptNoLock}`);
      edges.freezeEdgesLock(root);
      try { execFileSync('git', ['-C', root, 'add', '--', '.gos/edges.lock']); } catch { /* non-git */ }
      edges.auditEdge(root, 'adopt', '-', '-', 'freeze');
      console.log(`✓ integrity freeze (re)anchored to current edges.json (${edges.edgesLockPath(root)})`);
      return;
    }
    if (esub === 'verify') {   // explicit integrity check — gate reuses the same function (T7)
      const v = edges.checkEdgesIntegrity(root);
      console.log(v.msg);
      if (v.status === 'die') process.exit(1);
      return;
    }
    if (esub === 'audit-log') {
      const p = edges.edgeAuditPath(root);
      if (!fs.existsSync(p)) core.die(`✗ ${SC.edgeAuditMissing}`);
      const txt = fs.readFileSync(p, 'utf8').trimEnd();
      console.log(txt ? txt : SC.edgeAuditMissing);
      return;
    }
    core.die('Usage: gos map edge <add|rm|adopt|rewrite|verify|audit-log> ...');
  }
  if (sub === 'scan') {
    const scan = engine.scanSources(root);
    const obj = engine.writeDeps(root, scan);
    console.log(`✓ scanned ${scan.files.length} source file(s) — ${scan.edges.length} edge(s), ${scan.externals.length} external(s), skipped ${scan.skipped_binary} binary / ${scan.skipped_huge} huge${scan.skipped_dir ? ` / ${scan.skipped_dir} unreadable dir(s)` : ''}${scan.unreadable_file ? ` / ${scan.unreadable_file} unreadable file(s)` : ''}`);
    for (const f of ['.dependency-cruiser.cjs', '.dependency-cruiser.json', '.import-linter.cfg']) {   // third-party config probe
      if (fs.existsSync(path.join(root, f))) { console.log(`⚠ ${SC.probeHint.replace('<file>', f)}`); break; }
    }
    if (obj.head === 'unborn') console.log(`⚠ ${SC.headUnborn}`);
    else if (obj.head === null) console.log(`⚠ ${SC.noHead}`);
    {   // dead hand edges fail the SCAN (any single failure dies scan/gate)
      const dead = edges.deadEdgesIn(root);
      if (dead.length) {
        for (const d of dead) console.error(`✗ dead edge ${d}`);
        core.die(`✗ ${dead.length} dead edge(s) in edges.json — fix or migrate: gos map edge rewrite --from <old> --to <new> (see each line above)`);
      }
    }
    try { views.refreshNetworkMd(root); console.log('✓ network.md refreshed (hybrid view)'); } catch (e) { console.error(`⚠ network.md refresh skipped: ${e.message}`); }   // marker-missing dies inside (process.exit) — other refresh errors are advisory
    console.log(SC.mapBanner);   // bare frozen line — exact-line assertable (no decorative prefix)
    console.log('Next:\n  gos map closure <file> — who is impacted by changes');
    return;
  }
  if (sub === 'blast') {   // [P15 D-65] plain-language facade over semantic closure
    const flags = args.slice(1).filter((a) => a.startsWith('--'));
    const paths = args.slice(1).filter((a) => !a.startsWith('--'));
    const json = flags.includes('--json');
    const print0 = flags.includes('--print0');
    if (flags.filter((f) => !['--json', '--print0'].includes(f)).length) core.die('Usage: gos map blast <paths...> [--json | --print0]');
    if (!paths.length) core.die('Usage: gos map blast <paths...> — name the file(s) you are about to change; the report shows what else must be checked and why (plain-language facade over the closure engine)');
    const rel = paths.map((p) => path.relative(root, path.resolve(here, p)).split(path.sep).join('/'));
    // Anti-vacuity, same contract as closure: a path unknown to the scan
    // universe dies even when it exists on disk — an existing-but-unscanned
    // file (docs, config, a directory) must never read as verified safety.
    const known = engine.mapKnownKeys(engine.scanSources(root));
    // File-anchor exemption: an input unknown to the code-scan universe may
    // still be named by a section's `# gos-map:file` header (layout/config
    // data the static graph never sees). Such inputs carry section hits —
    // dying here would hide exactly the linkage the anchor exists for.
    const knownFiles = new Set();
    try {
      const secDir = path.join(root, 'test', 'sections');
      for (const f of fs.readdirSync(secDir).filter((x) => /^T.*\.test\.sh$/.test(x))) {
        const head = fs.readFileSync(path.join(secDir, f), 'utf8').split('\n').slice(0, 6);
        for (const l of head) { const m = l.match(/^#\s*gos-map:file\s+(\S+)/); if (m) knownFiles.add(m[1]); }
      }
    } catch { /* no sections dir */ }
    const unknown = rel.filter((p) => !known.has(p) && !knownFiles.has(p));
    if (unknown.length) {
      if (print0) { console.error(`blast: unknown path(s): ${unknown.join(', ')} — nothing to report`); process.exit(1); }
      core.die(`blast: ${SC.closureUnknownPath.replace('<paths>', unknown.join(', '))}`);
    }
    const r = engine.semanticClosure(root, rel);
    const inputs = new Set(rel);
    const impacted = [...r.mustCheck.entries()].filter(([f]) => !inputs.has(f)).sort((a, b) => a[0].localeCompare(b[0]));
    const sections = [...r.mustRun.entries()].sort((a, b) => a[0].localeCompare(b[0]));
    if (json) {   // machine envelope (same advisory semantics as closure --json)
      console.log(JSON.stringify({
        gos_version: core.PKG.version,
        schema_version: 1,
        advisory: true,
        blast: {
          inputs: rel,
          impacted: impacted.map(([file, vias]) => ({ file, via: [...vias] })),
          mustRun: sections.map(([sec, cmds]) => ({ section: sec, cmds: [...cmds] })),
        },
      }));
      return;
    }
    if (print0) {   // xargs semantics: empty NUL stream = verified success
      process.stdout.write(impacted.length ? impacted.map(([f]) => f).join('\0') + '\0' : '');
      return;
    }
 // human report — fixed self-labeling header ; qualification banners to
    // stderr when stdout is not a TTY (piped consumers keep clean data).
    console.log('blast report — human report; machine consumers: --json/--print0');
    console.log(`inputs: ${rel.join(', ')}`);
    if (!impacted.length) {
      console.log('no impacted files — nothing else needs checking for these inputs (per the current map)');
    } else {
      console.log(`impacted files (must also check these):`);
      for (const [f, vias] of impacted) {
        console.log(`  ${f}`);
        for (const v of vias) console.log(`    reason: ${v.replace(/#/g, '.')}`);
      }
    }
    if (sections.length) {
      console.log('must-run test sections (they assert these surfaces):');
      for (const [sec, cmds] of sections) console.log(`  ${sec} (cmds: ${[...cmds].join(', ')})`);
    } else {
      console.log('must-run test sections: none known for these inputs');
    }
    console.log(`summary: ${impacted.length} impacted file(s), ${sections.length} must-run section(s)`);
    console.log('next: declare impacted files in plan Files; run sections: bash test/run-sections.sh <section>');
    if (!process.stdout.isTTY) console.error('blast: advisory — map data is regex/AST-extracted, not exhaustive; absence of impact is NOT a safety proof');
    return;
  }
  if (sub === 'closure' || sub === 'show') {
    const flags = args.slice(1).filter((a) => a.startsWith('--'));
    const paths = args.slice(1).filter((a) => !a.startsWith('--'));
    const forward = flags.includes('--forward');
    const print0 = flags.includes('--print0');
    const noRefresh = flags.includes('--no-refresh');
 const semantic = flags.includes('--semantic'); // three-source human closure report
 const graph = flags.includes('--graph'); // neighborhood mermaid (1 hop; --2hop explicit)
    const twohop = flags.includes('--2hop');
    if (sub === 'closure' && !paths.length) core.die('Usage: gos map closure <paths...> [--forward] [--print0] [--no-refresh]');
 // show evolved: 0 args = legacy overview; 1 anchor arg = neighborhood . REVIEW #7 preserved for >1.
    if (flags.filter((f) => !['--forward', '--print0', '--no-refresh', '--semantic', '--graph', '--2hop', '--json'].includes(f)).length) core.die('Usage: unknown flag for map ' + sub);
    if (print0 && noRefresh) core.die('Usage: --print0 recomputes in memory by design — --no-refresh is contradictory here');   // REVIEW #8
    // load cache (triple fail-closed when file exists: tamper/parse/schema)
    let deps = engine.loadDeps(root);
    let usedStale = false;
    if (!engine.depsIsFresh(root, deps)) {
      if (print0) {
        deps = engine.scanSources(root);                     // [R3-F7] print0: in-memory recompute, NEVER writes/locks
      } else if (noRefresh) {
        if (!deps) core.die('✗ no deps.json on disk — run `gos map scan` first (or drop --no-refresh)');
        usedStale = true;                             // staleNote only after paths resolve (R3-F12 order)
      } else {
        deps = engine.writeDeps(root, engine.scanSources(root));    // [D-36] interactive auto-rescan (cache semantics)
      }
    }
    // unborn caches are pinned fresh — file changes since the
    // scan are undetectable without a HEAD anchor; say so instead of implying freshness.
    if (deps && deps.head === 'unborn') console.log('(unborn anchor — file changes since scan are not detectable; re-run gos map scan if in doubt)');
 // fn-level closure: `closure <path#fn:x> ...` — deps.json v3 is the
    // ONLY data source (fnClosure); --print0 conflicts (fn mode is name-keyed, not path output).
    const fnPaths = paths.filter((p) => /#fn:/.test(p)).map((p) => {
      const i = p.lastIndexOf('#fn:');
      return { file: p.slice(0, i), fn: p.slice(i + 4) };
    });
    if (sub === 'closure' && fnPaths.length) {
      if (fnPaths.length !== paths.length) core.die('Usage: mixing fn anchors and plain paths in one closure query is ambiguous — split the calls');
      if (print0) core.die('Usage: --print0 is file-path output — fn closure is name-keyed, use --json instead');
      if (!deps) core.die('✗ no deps.json on disk — run `gos map scan` first (fn closure reads the v3 cache only)');
      const r = engine.fnClosure(deps, fnPaths);
      const nodeKeys = new Set();
      for (const e of ((deps.semantic || {}).callgraph || [])) { nodeKeys.add(`${e.file}#fn:${e.from}`); nodeKeys.add(`${e.file}#fn:${e.to}`); }
      for (const t of (deps.semantic.testof_fn || [])) nodeKeys.add(`${t.file}#fn:${t.fn}`);
      for (const cf of fnPaths) {
        const k = `${cf.file}#fn:${cf.fn}`;
        if (!nodeKeys.has(k)) console.log(`⚠ ${SC.fnNotInGraph.replace('<anchor>', k)}`);
      }
      if (graph) {   // [R-05] neighborhood mermaid: changed fn + callers + tested-by sections
        const pairs = [];
        for (const [k, callers] of r.fnMustCheck) for (const c of callers) pairs.push({ from: c, to: k, label: 'called-by' });
        for (const [sec, fns] of r.fnMustRun) for (const f of fns) pairs.push({ from: `sec:${sec}`, to: f, label: 'tests' });
        if (!pairs.length) pairs.push({ from: paths[0], to: '(no known callers/tests)', label: 'verified-empty' });
        console.log(views.renderMermaid(pairs));
        console.error(SC.mapBanner);
        return;
      }
      if (args.includes('--json')) {   // [R-05] strict machine envelope
        const out = {
          gos_version: core.PKG.version,
          schema_version: 3,
          advisory: true,   // AST-derived but not scope-resolved (R-03 boundary)
          closure: {
            changed: paths,
            fnMustCheck: [...r.fnMustCheck.entries()].map(([fn, callers]) => ({ fn, callers: [...callers].sort() })).sort((a, b) => a.fn.localeCompare(b.fn)),
            fnMustRun: [...r.fnMustRun.entries()].map(([sec, fns]) => ({ section: sec, fns: [...fns].sort() })).sort((a, b) => a.section.localeCompare(b.section)),
            parseFailures: ((deps.semantic || {}).parse_failures || []).length,
          },
        };
        console.log(JSON.stringify(out));
        return;
      }
      console.log(`fn closure for: ${paths.join(', ')}`);
      for (const [k, callers] of r.fnMustCheck) {
        console.log(`  ${k}`);
        console.log(`    must-check fns (callers): ${callers.size ? [...callers].sort().join(', ') : '(none — leaf fn)'}`);
      }
      const runs = [...r.fnMustRun.entries()].sort((a, b) => a[0].localeCompare(b[0]));
      if (runs.length) for (const [sec, fns] of runs) console.log(`    must-run section: ${sec} (tests ${[...fns].sort().join(', ')})`);
      else console.log('    must-run sections: (none — no gos-map:fn annotations cover this fn or its callers)');
      const pf = ((deps.semantic || {}).parse_failures || []).length;
      if (pf) console.log(`  ${SC.closureParseWarn.replace('<N>', String(pf))}`);
 console.log(SC.mapBanner); // text form: banner on stdout like every other text closure form
      return;
    }
    if (sub === 'closure' && semantic && !graph) {   // [T7] human semantic closure (block-headed, qualified)
      engine.printSemanticClosure(root, paths);
      return;
    }
    if ((sub === 'closure') && graph) {   // [P1-M5] closure GRAPH form (D-24 third form): mermaid of the must-check/must-run set
      const r = engine.semanticClosure(root, paths);
      const pairs = [];
      for (const [file, vias] of r.mustCheck.entries()) for (const v of vias) pairs.push({ from: file, to: `closure:${v}`, label: 'must-check' });
      for (const [sec, cmds] of r.mustRun.entries()) for (const c of cmds) pairs.push({ from: `sec:${sec}`, to: `cmd:${c}`, label: 'must-run' });
      if (!pairs.length) pairs.push({ from: paths[0] || 'query', to: '(no known dependents)', label: 'verified-empty' });
      console.log(views.renderMermaid(pairs));
      console.error(SC.mapBanner);
      return;
    }
    if (sub === 'closure' && args.includes('--json')) {   // [T8] strict machine envelope (R-09)
      const r = engine.semanticClosure(root, paths);
      const out = {
        gos_version: core.PKG.version,
        schema_version: 1,
        advisory: true,   // regex-extracted, NOT exhaustive (D-26)
        closure: {
          changed: paths,
          mustCheck: [...r.mustCheck.entries()].map(([file, vias]) => ({ file, via: [...vias] })).sort((a, b) => a.file.localeCompare(b.file)),
          mustRun: [...r.mustRun.entries()].map(([sec, cmds]) => ({ section: sec, cmds: [...cmds] })).sort((a, b) => a.section.localeCompare(b.section)),
          unannotated: r.unannotated,
        },
      };
      console.log(JSON.stringify(out));   // byte 0 = '{' — banners live on stderr only
      return;
    }
    if (sub === 'closure') {
      const rel = paths.map((p) => path.relative(root, path.resolve(here, p)).split(path.sep).join('/'));  // [R2-F7]
      const known = engine.mapKnownKeys(deps);
      const unknown = rel.filter((p) => !known.has(p));
      if (unknown.length) {                           // [R3-F12] unknown-path FIRST; [R2-F2] refuse vacuous answer
        if (print0) process.exit(1);                  // zero bytes on stdout
        core.die(`✗ ${SC.closureUnknownPath.replace('<paths>', unknown.join(', '))}`);
      }
      const result = engine.computeClosure(rel, deps, { forward });
      if (print0) {
        process.stdout.write(result.length ? result.join('\0') + '\0' : '');
        return;
      }
      for (const p of result) console.log(p);
      if (usedStale) console.log(SC.staleNote);
      console.log(SC.mapBanner);
      console.log('Next:\n  gos map show — full dependency overview');
      return;
    }
 // show: anchor neighborhood OR legacy overview + externals + banner
    if (sub === 'show' && paths.length === 1) {
      const spec = paths[0];
      const v = anchor.validateAnchor(spec, root);
      if (!v.ok) core.die(v.msg);
      const sem = deps.semantic || {};
      const kind = v.type, p = anchor.parseAnchor(spec);
      const rows = [];   // [consumer, relation, target]
      for (const e of sem.calls || []) {
        if (kind === 'file' && e.file === p.path) rows.push([e.file, 'calls', `#cmd:${e.cmd}`]);
        else if (kind === 'cmd' && e.cmd === v.detail) rows.push([e.file, 'calls', `#cmd:${e.cmd}`]);
      }
      for (const e of sem.contracts || []) {
        if (kind === 'file' && e.file === p.path) rows.push([e.file, 'asserts/greps', e.key]);
        else if (kind === 'contractKey' && e.key === v.detail) rows.push([e.file, 'asserts/greps', e.key]);
      }
      for (const e of sem.switch || []) {
        if (kind === 'file' && e.file === p.path) rows.push([e.file, 'dispatches', `#fn:${e.fn}`]);
        else if (kind === 'cmd' && e.cmd === v.detail) rows.push([e.file, 'dispatches', `#fn:${e.fn}`]);
        else if (kind === 'fn' && e.fn === v.detail) rows.push([e.file, 'dispatched-by', `#cmd:${e.cmd}`]);
      }
      for (const e of sem.testof || []) {
        if (kind === 'cmd' && e.cmd === v.detail) rows.push([e.sec, 'tested-by', `#sec:${e.sec}`]);
        else if (kind === 'sec' && e.sec === v.detail) rows.push([e.sec, 'tests', `#cmd:${e.cmd}`]);
      }
 // fn-anchored neighborhood: callers + callees + testing sections (deps v3 families)
      if (kind === 'fn') {
        const fname = v.detail;
        for (const e of sem.callgraph || []) {
          if (e.file === p.path && e.to === fname) rows.push([e.file, 'called-by', `#fn:${e.from}`]);
          else if (e.file === p.path && e.from === fname) rows.push([e.file, 'calls-fn', `#fn:${e.to}`]);
        }
        for (const e of sem.testof_fn || []) {
          if (e.file === p.path && e.fn === fname) rows.push([e.sec, 'tested-by', `#sec:${e.sec}`]);
        }
      }
      const d = edges.loadEdges(root);   // hand edges: from/to endpoints touching this anchor (D-22)
      if (d) for (const e of d.edges) {
        if (e.from === spec || e.to === spec) rows.push([e.from, e.type, e.to]);
      }
      if (graph) {   // neighborhood mermaid (default 1 hop; 2-hop needs explicit flag — D-24 hub guard)
        const pairs = rows.map(([f, rel, tgt]) => ({ from: f, to: tgt.startsWith('#') ? `${f}${tgt}` : tgt, label: rel }))
          .map((p) => ({ from: p.from, to: p.to.startsWith('#') ? core.pathOf(p.from) + p.to : p.to, label: p.label }));
        if (twohop && rows.length) {
          // second hop: neighbors of the first-hop files' edges (bounded by known rows)
          for (const [f, rel, tgt] of rows) pairs.push({ from: tgt, to: f, label: rel + ':back' });
        }
        console.log(views.renderMermaid(pairs));
        console.error(SC.mapBanner);
        return;
      }
      console.log(`▸ anchor ${spec} — ${rows.length} semantic relation(s):`);
      const seenRow = new Set();
      for (const [f, rel, tgt] of rows) {
        const rk = `${f}\u0000${rel}\u0000${tgt}`;
 if (seenRow.has(rk)) continue; // dedupe fn call edges (multiple call sites → one relation)
        seenRow.add(rk);
        console.log(`  ${f}  --[${rel}]-->  ${tgt}`);
      }
      if (!rows.length) console.log('  (no semantic edges touch this anchor)');
      if (usedStale) console.log(SC.staleNote);
      console.log(SC.mapBanner);
      return;
    }
    if (sub === 'show' && paths.length > 1) core.die('Usage: gos map show [anchor] — at most one anchor per query');
    const depsOf = new Map();
    for (const e of deps.edges || []) { if (!depsOf.has(e.from)) depsOf.set(e.from, []); depsOf.get(e.from).push(e.to); }
    console.log(`files: ${(deps.files || []).length} | edges: ${(deps.edges || []).length} | externals: ${(deps.externals || []).length}${usedStale ? ' (stale cache)' : ''}`);
    for (const f of deps.files || []) {
      const list = depsOf.get(f) || [];
      console.log(`  ${f} → ${list.length ? list.join(', ') : '(no file deps)'}`);
    }
    const extByFrom = new Map();
    for (const x of deps.externals || []) { if (!extByFrom.has(x.from)) extByFrom.set(x.from, []); extByFrom.get(x.from).push(x.spec); }
    if (extByFrom.size) {
      console.log('externals:');
      for (const [from, specs] of extByFrom) console.log(`  ${from} ⇒ ${specs.map((s) => JSON.stringify(s)).join(', ')}`);
    }
    if (usedStale) console.log(SC.staleNote);
    console.log(SC.mapBanner);
    console.log('Next:\n  gos map closure <file> — impact of changes');
    return;
  }
  if (sub === 'baseline') {
    // baseline reset --reason is the ONLY peak-rotation exit (approve hard gate + single consumption)
    const rsub = args[1] || '';
  let reasonFlag = null;
  for (let i = 2; i < args.length; i++) if (args[i] === '--reason') reasonFlag = args[i + 1] ?? null;
    if (rsub !== 'reset') core.die('Usage: gos map baseline reset --reason "<why>"  (prerequisite: gos approve baseline-reset --reason "<why>")');
    const reason = reasonFlag;
    if (!reason) core.die('Usage: gos map baseline reset --reason "<why>" — a rotation reason is required (audit trail)');
    const st = core.readState();
    const appr = (st && st.approvals || {}).BASELINE_RESET;
    if (!appr || typeof appr !== 'object') core.die('✗ baseline reset requires the approve hard gate: gos approve baseline-reset --reason "<why>" (single consumption)');
    if (appr.reason && reason !== appr.reason) core.die(`✗ --reason does not match the reason recorded at approve time — re-approve or reuse the original reason: "${appr.reason}"`);
    const blPath = path.join(root, '.gos', 'codebase', 'edge-baseline.json');
    if (!fs.existsSync(blPath)) core.die('✗ no edge-baseline.json — run: gos map scan first');
    const bl = JSON.parse(fs.readFileSync(blPath, 'utf8'));
    const histPath = path.join(root, '.gos', 'codebase', 'edge-history.ndjson');
    fs.mkdirSync(path.dirname(histPath), { recursive: true });
    fs.appendFileSync(histPath, JSON.stringify({ reset: true, oldPeak: bl.peak || null, reason, at: new Date().toISOString() }) + '\n');   // old peak archived; append-only, never deleted
    bl.peak = Object.assign({}, bl.current);   // re-anchor: peak = current
    core.writeAtomicJson(blPath, bl);
    delete st.approvals.BASELINE_RESET;   // single consumption
    core.writeState(st);
    console.log(`✓ baseline peak re-anchored to current (old peak archived to edge-history.ndjson) — reason: ${reason}`);
    return;
  }

  if (sub === 'allowlist') {   // require-direction baseline: generate the v2 allowlist from deps.json
    const asub = args[1];
    if (asub !== 'init') core.die('Usage: gos map allowlist init [--force]');
    allowlist.initAllowlist(root, { force: args.includes('--force') }).catch((e) => core.die(`map allowlist init: ${e && e.message ? e.message : e}`));
    return;
  }

  core.die('Usage: gos map <scan|closure <paths...>|show|allowlist init>  (see `gos help`)');
}
Object.assign(module.exports, {
  ...Object.assign({}, require('./engine.cjs'), require('./edges.cjs'), require('./views.cjs'), require('./anchor.cjs'), require('./contract.cjs'), require('./allowlist.cjs')),
  cmdMap,
});
