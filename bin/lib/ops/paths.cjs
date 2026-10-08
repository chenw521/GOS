// ops/paths — placement per aspect-rosters-v2.json
'use strict';

const core = require('../core/index.cjs');
const render = require('../render/index.cjs');
const fs = require('fs');
const path = require('path');

function registeredPaths() {
  const files = [], dirs = [];
  for (const [k, e] of Object.entries(core.GOS_PATHS)) {
    if (e.rel.includes('<')) continue; // dynamic keys resolved elsewhere (active task)
    const abs = path.join(core.GOS_DIR, e.rel);
    (e.granularity === 'dir' ? dirs : files).push(abs);
  }
  return { files, dirs };
}

function cmdPaths(args) {
  const a = args || [];
  if (a.includes('--markdown')) {
    const top = core.currentRootRealpath();
    const here = fs.realpathSync('.');
    if (!top || here !== top) core.die('✗ paths --markdown must run at the project root (git toplevel) — it writes .gos/README.md');
    const md = render.renderPathsMarkdown();
    const dest = core.resolvePath('readme');
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, md);
    console.log(`${core.CONTRACTS.command_contracts.readmeGenerated} ${path.relative(process.cwd(), dest)}`);
    return;
  }
  const root = core.currentRootRealpath() || process.cwd();
  let state = null;
  try { state = JSON.parse(fs.readFileSync(core.STATE_PATH, 'utf8')); } catch { /* no task — dynamic keys null */ }
  const tid = core.currentTaskId(state);
  const paths = {};
  for (const [k, e] of Object.entries(core.GOS_PATHS)) {
    const entry = { rel: e.rel, abs: null, producer: e.producer, readers: e.readers, purge: e.purge, tracked: !!e.tracked, granularity: e.granularity };
    if (!e.rel.includes('<')) {
      entry.abs = path.join(core.GOS_DIR, e.rel);
    } else if (tid != null) {
      try { entry.abs = core.resolvePath(k, { task_id: tid, ymd: new Date().toISOString().slice(0, 10) }); } catch { entry.abs = null; entry.hint = `placeholder unresolvable for '${k}'`; }
    } else {
      entry.hint = 'no active task — dynamic keys unresolved';
    }
    paths[k] = entry;
  }
  console.log(JSON.stringify({ project_root: root, paths }, null, 2));
}

module.exports = { registeredPaths, cmdPaths };
