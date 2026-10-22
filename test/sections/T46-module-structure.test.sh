#!/usr/bin/env bash
# gos-map:cmd gate,map
# gos-map:fn bin/gos.cjs#fn:main bin/lib/ops/gate.cjs#fn:cmdGate bin/lib/map/index.cjs#fn:cmdMap bin/lib/core/fsio.cjs#fn:die bin/lib/knowledge/lessons.cjs#fn:cmdLessons
# T46: module structure guard — twelve contracts on the split module layout
# Data source: independent acorn/grep scan, deps.json must not be consumed;
# acorn require pins to the repo root.
# Expected values are in-section literals (spec + aspect-rosters.json) — keep
# them in sync with the tree.
T46_DIR=""

t46_setup() {
  T46_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t46"
  mkdir -p "$T46_DIR" && cd "$T46_DIR" || exit 1
}

t46_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T46_DIR"; }

# Scanner: node script injected via stdin; cwd=GOS_ROOT so require('acorn') resolves.
# env: SCAN_ROOT (defaults to GOS_ROOT; points at the sandbox copy for fault injection)
t46_scan() {
  (cd "$GOS_ROOT" && SCAN_ROOT="${1:-$GOS_ROOT}" node - <<'T46EOF'
const fs = require('node:fs');
const path = require('node:path');
const acorn = require('acorn');
const ROOT = process.env.SCAN_ROOT;
const bad = [];
const ok = (m) => console.log('  ✓ ' + m);

// ---------- Scan set: filesystem traversal with the same skip rules (no deps.json) ----------
const MAP_EXTS = new Set(['.js', '.cjs', '.mjs', '.ts', '.jsx', '.tsx', '.py', '.R', '.r']);
// Mirrors the bin scanner rules (MAP_SKIP_DIRS + test-* prefix), no additions or omissions — drift between the copies produces false red/green
const SKIP = new Set(['node_modules', '.git', '.gos', '.venv', 'venv', '__pycache__', 'dist', 'build', 'out', 'target', 'test-sections-base']);
const walk = (dir, acc) => {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    if (ent.name.startsWith('test-')) continue;
    const full = path.join(dir, ent.name);
    if (ent.isDirectory()) { if (!SKIP.has(ent.name)) walk(full, acc); continue; }
    const ext = path.extname(ent.name);
    if (ent.name.endsWith('.min.js')) continue;
    if (MAP_EXTS.has(ext)) acc.push(path.relative(ROOT, full));
  }
};
const scanned = [];
walk(ROOT, scanned);
scanned.sort();

// ---- Expected values (in-section literals; spec + aspect-rosters; current state: core/ extracted) ----
const EXPECT = {
  files: ['.opencode/plugins/gos.js', 'bin/gos.cjs', 'bin/lib/core/fsio.cjs', 'bin/lib/core/gitprobe.cjs', 'bin/lib/core/i18n.cjs', 'bin/lib/core/index.cjs', 'bin/lib/core/locales/en.cjs', 'bin/lib/core/locales/zh.cjs', 'bin/lib/core/lock.cjs', 'bin/lib/core/state.cjs', 'bin/lib/map/index.cjs', 'bin/lib/map/allowlist.cjs', 'bin/lib/map/engine.cjs', 'bin/lib/map/edges.cjs', 'bin/lib/map/views.cjs', 'bin/lib/map/anchor.cjs', 'bin/lib/map/contract.cjs', 'bin/lib/knowledge/index.cjs', 'bin/lib/knowledge/lessons-json.cjs', 'bin/lib/knowledge/lessons.cjs', 'bin/lib/knowledge/decisions.cjs', 'bin/lib/knowledge/requirements.cjs', 'bin/lib/knowledge/truth.cjs', 'bin/lib/knowledge/concerns.cjs', 'bin/lib/knowledge/phase.cjs', 'bin/lib/task/index.cjs', 'bin/lib/nav/index.cjs', 'bin/lib/nav/registry.cjs', 'bin/lib/nav/registry-consts.cjs', 'bin/lib/nav/status.cjs', 'bin/lib/nav/help.cjs', 'bin/lib/nav/cmds.cjs', 'bin/lib/render/index.cjs', 'bin/lib/render/views.cjs', 'bin/lib/ops/index.cjs', 'bin/lib/ops/brownfield.cjs', 'bin/lib/ops/brownfield-probe.cjs', 'bin/lib/ops/changelog-core.cjs', 'bin/lib/ops/feedback.cjs', 'bin/lib/ops/gate.cjs', 'bin/lib/ops/section.cjs', 'bin/lib/ops/gitseed.cjs', 'bin/lib/ops/doctor.cjs', 'bin/lib/ops/setup.cjs', 'bin/lib/ops/config.cjs', 'bin/lib/ops/paths.cjs', 'bin/lib/ops/push.cjs', 'bin/lib/task/init.cjs', 'bin/lib/task/commit.cjs', 'bin/lib/task/archive.cjs', 'bin/lib/task/stage.cjs', 'bin/lib/task/checkpoint.cjs', 'bin/lib/task/context.cjs', 'bin/lib/task/plansnap.cjs', 'bin/lib/task/changelog.cjs'],
  fnTotal: 460,                                 // §6a-2: 239 + drift declarations +3 (lock accessor, drift-1.md) +1 (③-T6 fnSetFingerprint) +3 (P12 Wave 1: init coding trio) +11 (P11 Wave 1: changelog-core 7 + gitseed 4) +10 (P11 W2-5) +1 (REVIEW M3 rework) +1 (deferred-findings gate check) +5 (P11 T56: init git 2 + gitseed seed trio 3) +9 (P11 T54: changelog cmd 9) +4 (P11 T60: setup commitlint hook) +1 (P11 T55: changelog lint) +17 (require-allowlist v2: map/allowlist.cjs) +2 (gitseed render helpers) +3 (P12 W3 T8: gate trust pair + setup seeder) +14 (P12 W4 T9: section runner) +16 (P12 W5 T10: feedback family) +2 (P15 REVIEW: lessons-json disposalIdSet + v2TextReservedViolations) +9 (aggregate push command: ops/push.cjs) +1 (P18 W1 T3: brownfield stub) +1 (P1 T2: replayEvidenceHit) +8 (P1 W1 merge: config two-layer +6, render backup views +4, lessons sentinel −2) +12 (P1 W2 merge: auto-render views +4 + decisions hook +2, changelog resolver core +7 + config +1 + task/changelog −2) +2 (P1 T10: PROJECT.md section predicates in phase.cjs) +4 (P1 T12: logs view family in gate.cjs) +13 (P4 W1: gitprobe 10 + state v4 identity trio 3)
  arrowsTotal: 2,                                // snapshot pair cpLen/idNum; _bridge.__inject is a function expression and not counted
  fnDist: { 'bin/gos.cjs': 1, 'bin/lib/core/fsio.cjs': 32, 'bin/lib/core/gitprobe.cjs': 10, 'bin/lib/core/state.cjs': 28, 'bin/lib/core/lock.cjs': 11, 'bin/lib/map/index.cjs': 1, 'bin/lib/map/allowlist.cjs': 17, 'bin/lib/map/engine.cjs': 26, 'bin/lib/map/edges.cjs': 10, 'bin/lib/map/views.cjs': 9, 'bin/lib/map/anchor.cjs': 6, 'bin/lib/map/contract.cjs': 1, 'bin/lib/knowledge/lessons-json.cjs': 39, 'bin/lib/knowledge/lessons.cjs': 12, 'bin/lib/knowledge/decisions.cjs': 13, 'bin/lib/knowledge/requirements.cjs': 5, 'bin/lib/knowledge/truth.cjs': 4, 'bin/lib/knowledge/concerns.cjs': 7, 'bin/lib/knowledge/phase.cjs': 4, 'bin/lib/task/init.cjs': 8, 'bin/lib/task/commit.cjs': 3, 'bin/lib/task/archive.cjs': 3, 'bin/lib/task/stage.cjs': 1, 'bin/lib/task/checkpoint.cjs': 1, 'bin/lib/task/context.cjs': 3, 'bin/lib/task/plansnap.cjs': 5, 'bin/lib/task/changelog.cjs': 8, 'bin/lib/nav/registry.cjs': 3, 'bin/lib/nav/status.cjs': 11, 'bin/lib/nav/help.cjs': 3, 'bin/lib/nav/cmds.cjs': 7, 'bin/lib/render/views.cjs': 16, 'bin/lib/ops/gate.cjs': 24, 'bin/lib/ops/section.cjs': 14, 'bin/lib/ops/doctor.cjs': 4, 'bin/lib/ops/setup.cjs': 11, 'bin/lib/ops/config.cjs': 13, 'bin/lib/ops/paths.cjs': 2, 'bin/lib/ops/push.cjs': 14, 'bin/lib/ops/changelog-core.cjs': 14, 'bin/lib/ops/brownfield.cjs': 15, 'bin/lib/ops/brownfield-probe.cjs': 6, 'bin/lib/ops/gitseed.cjs': 9, 'bin/lib/ops/feedback.cjs': 16 },
  anchors: { 'bin/gos.cjs': { dirname: 0, filename: 0, pkgreq: 0 }, 'bin/lib/core/fsio.cjs': { dirname: 0, filename: 1, pkgreq: 0 } },  // entry pkg-require is zero; package.json access goes through core.PKG
  crossAllow: ['core'],
  exceptions: [['bin/lib/task', 'bin/lib/map'], ['bin/lib/task', 'bin/lib/ops'], ['bin/lib/task', 'bin/lib/knowledge'], ['bin/lib/task', 'bin/lib/render'], ['bin/lib/task', 'bin/lib/nav'], ['bin/lib/nav', 'bin/lib/task'], ['bin/lib/nav', 'bin/lib/knowledge'], ['bin/lib/ops', 'bin/lib/map'], ['bin/lib/ops', 'bin/lib/render'], ['bin/lib/ops', 'bin/lib/nav'], ['bin/lib/ops', 'bin/lib/task'], ['bin/lib/ops', 'bin/lib/knowledge'], ['bin/lib/render', 'bin/lib/map']],  // full set from require-allowlist.json
  consts: Object.fromEntries([
    'GOS_DIR','STATE_PATH','PROJECT_DIR','ARCHIVE_DIR','SKILLS_DIR','GOS_SELF_ROOT','_trackedCache','GOS_PATHS'
  ].map((n) => [n, 'bin/lib/core/fsio.cjs']).concat([
    'STATE_SCHEMA_VERSION','PROJECT_SCHEMA_VERSION','NO_CMD_KEY','COMMANDS','cpLen','idNum','ID_RE','DECISION_STATUS','REQ_STATUS','PHASE_STATUS','CONTRACTS','STAGE_ORDER','EVIDENCE_FEATURE_RES_MANUAL','EVIDENCE_FEATURE_RES_REPLAY'
  ].map((n) => [n, 'bin/lib/core/state.cjs'])).concat([
    'LOCK_PATH','_lockHeld','_edgeRootLock','_edgeRootLockPath','CLI_BREAK_LOCK'
  ].map((n) => [n, 'bin/lib/core/lock.cjs'])).concat([
    'ORPHAN_EXEMPT_TOP','ORPHAN_TRANSIENT_RE','DOCTOR_FIXES','DOCTOR_FIX_RE'
  ].map((n) => [n, 'bin/lib/ops/doctor.cjs'])).concat([
    'EXEMPT_LOG_REL'
  ].map((n) => [n, 'bin/lib/ops/gate.cjs'])).concat([
    'RENDER_BACKUP_DIR','RENDERED_HEADER','MANUAL_MARKER'
  ].map((n) => [n, 'bin/lib/render/views.cjs'])).concat([
    'MODEL_PROFILES','VALID_PROFILES','MODEL_NAME_RE','CONFIG_PATH','SEMANTIC_RUNTIME_BASE','SEMANTIC_RUNTIME'
  ].map((n) => [n, 'bin/lib/ops/config.cjs'])).concat([
    'GOS_SKILL_NAMES'
  ].map((n) => [n, 'bin/lib/ops/setup.cjs'])).concat([
    'SUBCLASS_OVERRIDES','KNOWN_CASES','WRITE_CMDS','READ_CMDS','EXEC_CMDS','GLOBAL_CMDS'
  ].map((n) => [n, 'bin/lib/nav/registry-consts.cjs'])).concat([
    'MAP_EXTS','MAP_SKIP_DIRS','MAP_NOTE','MAP_PATTERNS','SEMANTIC_EXTS','_acorn','EXTRACTORS','SEMANTIC_CODE_EXTS'
  ].map((n) => [n, 'bin/lib/map/engine.cjs'])).concat([
    'EDGE_TYPES','EDGES_NOTE'
  ].map((n) => [n, 'bin/lib/map/edges.cjs'])).concat([
    'NETWORK_MD'
  ].map((n) => [n, 'bin/lib/map/views.cjs'])).concat([
    '_contractKeysFlat'
  ].map((n) => [n, 'bin/lib/map/anchor.cjs'])).concat([
    'REQ_ID_RE'
  ].map((n) => [n, 'bin/lib/knowledge/requirements.cjs'])).concat([
    'LESSONS_ENTRY_RE', 'V2_SEGMENTS', 'RAW_LEGACY_FIELDS', 'V2_FIELDS', 'PLAIN_TAXONOMY', 'LESSONS_JSON_SCHEMA_VERSION', 'DISPOSAL_WHATS', 'MINT_WHATS', 'MD_HEADER_TAIL'
  ].map((n) => [n, 'bin/lib/knowledge/lessons-json.cjs'])).concat([
    'TRUTH_RECEIPTS_PATH'
  ].map((n) => [n, 'bin/lib/knowledge/truth.cjs'])).concat([
    'CONCERNS_HEADER'
  ].map((n) => [n, 'bin/lib/knowledge/concerns.cjs']))),
};

// ---------- Per-file acorn parse ----------
const parse = (rel) => {
  const src = fs.readFileSync(path.join(ROOT, rel), 'utf8');
  // .js dual-mode retry (same as the gos.cjs scanner): try script first, retry as module when ESM traits fail
  try { return { src, ast: acorn.parse(src, { ecmaVersion: 'latest' }) }; }
  catch (e) { return { src, ast: acorn.parse(src, { ecmaVersion: 'latest', sourceType: 'module' }) }; }
};
const filesSrc = {};
const fnCount = {}; const arrows = {}; const topLevelDecl = {}; const requires = {};
for (const rel of scanned) {
  // Initialize before parse — a parse failure (injected copy with bad syntax) must not crash the later traversal (TypeError would mask the real FAIL)
  filesSrc[rel] = ''; fnCount[rel] = 0; arrows[rel] = 0; topLevelDecl[rel] = {}; requires[rel] = [];
  if (path.extname(rel) !== '.js' && path.extname(rel) !== '.cjs' && path.extname(rel) !== '.mjs') continue;
  let p;
  try { p = parse(rel); } catch (e) { bad.push(`parse failure ${rel}: ${e.message}`); continue; }
  filesSrc[rel] = p.src;
  fnCount[rel] = 0; arrows[rel] = 0; topLevelDecl[rel] = {}; requires[rel] = [];
  for (const n of p.ast.body) {
    if (n.type === 'FunctionDeclaration' && n.id) fnCount[rel] += 1;
    if (n.type === 'VariableDeclaration') {
      for (const d of n.declarations) {
        if (d.id && d.id.type === 'Identifier' && d.init) {
          const isAlias = d.init.type === 'MemberExpression' && d.init.object && d.init.object.type === 'Identifier' && d.init.object.name === 'core' && d.init.property && d.init.property.name === d.id.name;
          if (isAlias) continue;   // core.X re-export alias — not a real top-level declaration
          topLevelDecl[rel][d.id.name] = true;
          if (d.init.type === 'ArrowFunctionExpression') arrows[rel] += 1;
        }
      }
    }
  }
  // require edges (static-string relative requires only)
  for (const m of p.src.matchAll(/require\((['"])(\.[^'"]*)\1\)/g)) requires[rel].push(m[2]);
}

// ---------- Scan set freeze ----------
const expFiles = [...EXPECT.files].sort();
if (JSON.stringify(scanned) === JSON.stringify(expFiles)) ok(`scan set frozen (${scanned.length} files)`); else bad.push(`scan set drift: got [${scanned}] want [${expFiles}]`);

// ---------- fn conservation double-count + per-file distribution (arrows cover the same bin/** surface) ----------
const binFiles = scanned.filter((f) => f.startsWith('bin/'));
const totFn = binFiles.reduce((a, f) => a + (fnCount[f] || 0), 0);
const totAr = binFiles.reduce((a, f) => a + (arrows[f] || 0), 0);
if (totFn === EXPECT.fnTotal) ok(`fn total = ${totFn}`); else bad.push(`fn total ${totFn} != ${EXPECT.fnTotal} (plan-declared drift required)`);
if (totAr === EXPECT.arrowsTotal) ok(`arrow fn total = ${totAr}`); else bad.push(`arrow total ${totAr} != ${EXPECT.arrowsTotal} (smuggling channel)`);
for (const [f, n] of Object.entries(EXPECT.fnDist)) {
  if ((fnCount[f] || 0) === n) ok(`fn dist ${f} = ${n}`); else bad.push(`fn dist ${f}: got ${fnCount[f] || 0} want ${n}`);
}

// ---------- Require edge-class rules + DAG + entry index-only ----------
const libDirs = new Set(scanned.filter((f) => f.startsWith('bin/lib/')).map((f) => path.dirname(f)));
const edges = [];  // [fromRel, toRel]
for (const rel of scanned) {
  for (const spec of requires[rel]) {
    const resolved = path.normalize(path.join(path.dirname(rel), spec));
    const toRel = spec.endsWith('.cjs') || spec.endsWith('.js') ? resolved : (['.cjs','.js','.mjs'].map((e) => resolved + e).find((c) => scanned.includes(c)) || resolved + '.cjs');
    edges.push([rel, toRel]);
  }
}
// entry connects only to bin/lib/<mod>/index.cjs
for (const [from, to] of edges) {
  if (from === 'bin/gos.cjs' && to.startsWith('bin/lib/') && !to.endsWith('/index.cjs') && to !== 'bin/lib/index.cjs') bad.push(`entry direct aspect require: ${from} → ${to} (index-only rule)`);
}
// Cross-directory rules
let crossBad = 0;
for (const [from, to] of edges) {
  const fd = path.dirname(from), td = path.dirname(to);
  if (!to.startsWith('bin/lib/')) continue;
  if (fd === td) continue;                             // same directory: free
  if (from === 'bin/gos.cjs') continue;                // entry→index checked above
  const tmod = td.replace(/^bin\/lib\//, '').split('/')[0];
  const fmod = fd.replace(/^bin\/lib\//, '').split('/')[0];
  if (td !== 'bin/lib/core' && !EXPECT.crossAllow.includes(tmod) && !EXPECT.exceptions.some(([a, b]) => fd === a && td === b)) { crossBad++; bad.push(`cross-dir edge violation: ${from} → ${to}`); }
}
if (crossBad === 0) ok(`edge-class rules hold (${edges.length} require edges, whitelist {→core}∪exceptions ${JSON.stringify(EXPECT.exceptions)})`);
// DAG (DFS cycle check) over the cross-directory subgraph — same-directory cycles are a legal CJS load-time pattern; cross-layer cycles deadlock loading and stay banned
const adj = {}; for (const [a, b] of edges) { const ad = path.dirname(a), bd = path.dirname(b); if (ad === bd) continue; (adj[a] = adj[a] || []).push(b); }
const color = {}; let cycle = null;
const dfs = (u) => { color[u] = 1; for (const v of adj[u] || []) { if (color[v] === 1) { cycle = [u, v]; return; } if (!color[v]) dfs(v); } color[u] = 2; };
for (const u of Object.keys(adj)) if (!color[u]) dfs(u);
if (!cycle) ok('require graph is a DAG (DFS cycle check)'); else bad.push(`cycle detected: ${cycle.join(' → ')}`);
// entry full top-level require: every existing bin/lib/<mod>/index.cjs is required by the entry
for (const d of libDirs) {
  const idx = d + '/index.cjs';
  if (scanned.includes(idx) && !edges.some(([f, t]) => f === 'bin/gos.cjs' && t === idx)) bad.push(`entry missing top-level require of ${idx}`);
}

// ---------- No destructuring + zero bare refs to the four mutable identifiers outside core ----------
let destr = 0;
for (const [rel, src] of Object.entries(filesSrc)) {
  for (const line of src.split('\n')) if (/\}\s*=\s*require\(['"]\.\//.test(line)) { destr++; bad.push(`destructive require in ${rel}: ${line.trim().slice(0, 80)}`); }
}
if (destr === 0) ok('no destructured relative requires (namespace-only discipline)');
const MUT = ['_lockHeld', '_edgeRootLock', '_edgeRootLockPath', 'CLI_BREAK_LOCK'];
const coreExists = scanned.some((f) => f.startsWith('bin/lib/core/'));   // gate: before the split the four identifiers live in the monolith (future core content)
let mutBad = 0;
if (coreExists) {
  for (const [rel, src] of Object.entries(filesSrc)) {
    if (rel.startsWith('bin/lib/core/')) continue;        // bare mutable refs inside core are legal
    for (const line of src.split('\n')) {
      if (line.trim().startsWith('//') || line.trim().startsWith('*') || line.trim().startsWith('#')) continue;
      for (const m of MUT) if (new RegExp('(^|[^.\\w\'])' + m + '\\b').test(line) && !line.includes('core.' + m)) { mutBad++; bad.push(`bare mutable ref ${m} outside core in ${rel}: ${line.trim().slice(0, 70)}`); }
    }
  }
}
if (mutBad === 0) ok(`mutable lock identifiers: ${coreExists ? 'zero bare refs outside core' : 'pre-split (still in monolith, core/ absent — rule dormant)'}`);

// ---------- Anchor enumeration (dirname/filename/pkg-require per-file counts) ----------
let anchBad = 0;
for (const rel of scanned) {
  if (!rel.startsWith('bin/')) continue;
  const src = filesSrc[rel] || '';
  const got = { dirname: (src.match(/__dirname/g) || []).length, filename: (src.match(/__filename/g) || []).length, pkgreq: (src.match(/require\((['"])\.\.\/package\.json\1\)/g) || []).length };
  const want = EXPECT.anchors[rel] || { dirname: 0, filename: 0, pkgreq: 0 };
  for (const k of ['dirname', 'filename', 'pkgreq']) if (got[k] !== want[k]) { anchBad++; bad.push(`anchor ${rel} ${k}: got ${got[k]} want ${want[k]}`); }
}
if (anchBad === 0) ok('anchor sites match per-file allowlist (' + JSON.stringify(EXPECT.anchors) + ')');

// ---------- Suffix discipline ----------
let suffixBad = 0;
for (const rel of scanned) if (rel.startsWith('bin/lib/') && !rel.endsWith('.cjs')) { suffixBad++; bad.push(`non-.cjs in bin/lib: ${rel}`); }
if (suffixBad === 0) ok('bin/lib suffix discipline (.cjs only, "type":"module" load-bearing)');

// ---------- Golden presence ----------
const libExists = scanned.some((f) => f.startsWith('bin/lib/') && f.endsWith('.cjs'));
const goldenOk = fs.existsSync(path.join(ROOT, 'test/golden/pre-split/version.txt'));
if (libExists && !goldenOk) bad.push('bin/lib/*.cjs exists but test/golden/pre-split/ missing');
else ok(`golden presence rule (lib=${libExists}, golden=${goldenOk})`);

// ---------- Constant exclusivity ----------
let constBad = 0;
for (const [name, want] of Object.entries(EXPECT.consts)) {
  const hits = scanned.filter((rel) => topLevelDecl[rel] && topLevelDecl[rel][name]);
  if (hits.length !== 1 || hits[0] !== want) { constBad++; bad.push(`const ${name}: declared in [${hits}] want exactly [${want}]`); }
}
if (constBad === 0) ok(`constant exclusivity (${Object.keys(EXPECT.consts).length} frozen names, single-site each)`);

console.log(bad.length ? bad.map((b) => '  ✗ T46 ' + b).join('\n') : '');
process.exit(bad.length ? 1 : 0);
T46EOF
  )
}

t46_setup
echo "--- T46: module structure guard (12 contracts, ②-3 terminal state) ---"

# --- T46.0: main scan (single-file expectations), expect exit 0 ---
set +e; OUT=$(t46_scan "$GOS_ROOT"); RC=$?; set -e
echo "$OUT"
assert_exit "T46 main scan (single-file expectations)" 0 "$RC"

# --- T46.1: fault injection 1, destructured require (contract #5; name avoids existing monolith declarations to prevent a false parse signal) ---
mkdir -p inj1/bin && cp "$GOS_ROOT/bin/gos.cjs" inj1/bin/gos.cjs
printf "\nconst { rogueProbeXyz } = require('./lib/core/index.cjs');\n" >> inj1/bin/gos.cjs
set +e; OUT=$(t46_scan "$T46_DIR/inj1"); RC=$?; set -e
assert_exit "injection 1: destructured require FAILs" 1 "$RC"
assert_contains "injection 1 names the violation" "destructive require" "$OUT"

# --- T46.2: fault injection 2, fn count drift (contract #2: removing one fn breaks the total) ---
mkdir -p inj2/bin && sed 's/^function nulNames(/function nulNames_DISABLED(/' "$GOS_ROOT/bin/gos.cjs" > inj2/bin/gos.cjs
set +e; OUT=$(t46_scan "$T46_DIR/inj2"); RC=$?; set -e
assert_exit "injection 2: fn count drift FAILs" 1 "$RC"
assert_contains "injection 2 names fn total mismatch" "fn total" "$OUT"

# --- T46.3: fault injection 3, .js file under bin/lib (contract #7) ---
mkdir -p inj3/bin/lib/core && cp "$GOS_ROOT/bin/gos.cjs" inj3/bin/ && echo "module.exports={};" > inj3/bin/lib/core/rogue.js
set +e; OUT=$(t46_scan "$T46_DIR/inj3"); RC=$?; set -e
assert_exit "injection 3: non-.cjs in bin/lib FAILs" 1 "$RC"
assert_contains "injection 3 names suffix violation" "non-.cjs" "$OUT"

# Injection artifacts live only inside the $T46_DIR sandbox, removed by teardown; the real tree is read-only to this scan.

t46_teardown
