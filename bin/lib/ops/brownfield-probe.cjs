// ops/brownfield-probe — pure classification probes for `gos brownfield`
// ( , ). Read-only by contract: every function classifies and
// returns; none writes, prompts, stages, or repairs. Consumed by
// ops/brownfield.cjs to build the adopt report; side-effect freedom is
// what lets --json run against a dirty tree without touching it.
// Ownership vocabulary note: a missing hook file classifies as 'missing' —
// the adopt pipeline (caller) maps that to a fresh install, never to 'user'.
// Require direction: probe -> setup (consts only) is one-way; setup must
// never require this module (no cycle).
'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const core = require('../core/index.cjs');
const sibSetup = require('./setup.cjs');

// Shared frozen-contract token derivation (review m9): split a closed-set
// command_contracts value into its tokens, failing LOUDLY at require time
// when the key is missing or empty. Consumed here and re-exported to
// ops/brownfield.cjs so the split + drift rules live in exactly one place
// (the derivation was previously duplicated between the two modules).
function contractTokens(contractKey) {
  const raw = core.CONTRACTS.command_contracts[contractKey];
  if (typeof raw !== 'string' || raw === '') {
    throw new Error(`brownfield-probe: command_contracts.${contractKey} missing or empty — contract drift`);
  }
  return raw.split(' | ');
}

// Frozen preflight reason tokens — derived from the single frozen
// source (CONTRACTS.command_contracts.brownfieldPreflightReasons) by content
// match, never duplicated as literals. A renamed or reordered contract token
// fails this module loudly at require time instead of misreporting silently.
// Review M1: 'symlink escape' — a symlink component in the path chain
// resolving outside realpath(top) is a write-escape channel and refuses the
// path; symlinks resolving INSIDE the repo stay permitted.
const PREFLIGHT_REASON_SET = contractTokens('brownfieldPreflightReasons');
const REASON_OCCUPIED = PREFLIGHT_REASON_SET.find((s) => s.includes('non-directory'));
const REASON_DANGLING = PREFLIGHT_REASON_SET.find((s) => s.includes('dangling'));
const REASON_UNWRITABLE = PREFLIGHT_REASON_SET.find((s) => s.includes('unwritable'));
const REASON_ESCAPE = PREFLIGHT_REASON_SET.find((s) => s.includes('symlink escape'));
if (!REASON_OCCUPIED || !REASON_DANGLING || !REASON_UNWRITABLE || !REASON_ESCAPE) {
  throw new Error('brownfield-probe: command_contracts.brownfieldPreflightReasons drifted — expected tokens matching non-directory/dangling/unwritable/symlink escape');
}

// Hook-master ownership markers. Current masters (wave 1 ) carry the
// '# gos-managed' line (masters ship it below the 3-line header, so the
// marker scan is whole-file); historical masters carried only the
// provenance line as line 2 ('# GOS commit-msg hook:' / '# GOS pre-push
// hook:') — current masters still carry both, so byte equality is tested
// before any marker. Review m10 lineage scoping: provenance evidence counts
// ONLY when (a) the line sits within the FIRST 3 lines (header zone — a
// provenance-looking line deeper in the body is ordinary content) and
// (b) it is the hook's OWN provenance line, derived from the master
// basename (a commit-msg line in a file checked against the pre-push
// master is not pre-push lineage).
const GOS_MANAGED_LINE_RE = /^# gos-managed\b/;
const HOOK_PROVENANCE_LINE_RES = {
  'commit-msg': /^# GOS commit-msg hook:/,
  'pre-push': /^# GOS pre-push hook:/,
};

// Classify core.hooksPath for the repo at <top>: 'unset' (absent or empty —
// the empty string normalizes to unset BEFORE any comparison),
// 'gos_hooks_dir' (any spelling that resolves to <top>/hooks via
// path.resolve: the 'hooks' literal or the absolute path), 'foreign'
// (anything else, e.g. '.husky' relative or absolute). The git-config read
// mirrors setup.cjs gitConfigGet semantics (trim; empty value -> null)
// inline — fn names are globally unique (codemap dup-fn gate), so the probe
// keeps its read local instead of importing the setup helper.
function classifyHooksPath(top) {
  let raw = null;
  try {
    raw = execFileSync('git', ['-C', top, 'config', '--get', 'core.hooksPath'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() || null;
  } catch {
    raw = null;
  }
  if (raw == null || raw === '') return 'unset';
  const gosHooksDir = path.resolve(top, sibSetup.COMMITLINT_HOOKS_PATH_VALUE);
  return path.resolve(top, raw) === gosHooksDir ? 'gos_hooks_dir' : 'foreign';
}

// Classify who owns a hook file by comparing it against its master:
//   gos_bytes       — byte-identical to the master (strongest evidence)
//   gos_marker      — differing bytes but carries the '# gos-managed' line
//   gos_grandfather — differing bytes, no marker, but carries a historical
//                     provenance line in the 3-line header zone (predates
//                     the marker; wave-1 masters still carry the lines,
//                     caught by gos_bytes first)
//   user            — divergent content with no GOS lineage
//   missing         — no file at <file>; the caller decides (fresh install)
// Marker beats grandfather: a modified current-generation copy is a drifted
// managed hook, not a legacy one.
function hookOwnership(file, masterPath) {
  let fileBytes;
  try { fileBytes = fs.readFileSync(file); } catch { return 'missing'; }
  let masterBytes = null;
  try { masterBytes = fs.readFileSync(masterPath); } catch { masterBytes = null; }
  if (masterBytes !== null && Buffer.compare(fileBytes, masterBytes) === 0) return 'gos_bytes';
  const provenanceRe = HOOK_PROVENANCE_LINE_RES[path.basename(masterPath, '.sh')] || null;
  const lines = fileBytes.toString('utf8').split('\n');
  let marker = false;
  let grandfather = false;
  for (const line of lines) {
    if (GOS_MANAGED_LINE_RE.test(line)) marker = true;
  }
  for (const line of lines.slice(0, 3)) {
    if (provenanceRe !== null && provenanceRe.test(line)) grandfather = true;
  }
  if (marker) return 'gos_marker';
  if (grandfather) return 'gos_grandfather';
  return 'user';
}

// Detect commitlint config at <top> over commitlint's REAL resolution set
// : the rc family and the commitlint.config family, each stat'ed
// following filesystem case behavior (candidates come from the setup.cjs
// COMMITLINT_* consts so the strings live in one place), plus package.json
// through its 'commitlint' key (parsed presence; a corrupt or absent
// package.json counts as no detection). Scope is the repo root only —
// nested configs never match. Returns detected candidate names in
// resolution-set order.
function detectCommitlintConfigs(top) {
  const found = [];
  for (const rel of [...sibSetup.COMMITLINT_RC_CANDIDATES, ...sibSetup.COMMITLINT_CONFIG_CANDIDATES]) {
    try { fs.statSync(path.join(top, rel)); found.push(rel); } catch { /* absent */ }
  }
  try {
    const pkg = JSON.parse(fs.readFileSync(path.join(top, 'package.json'), 'utf8'));
    if (pkg && typeof pkg === 'object' && pkg.commitlint != null) found.push('package.json');
  } catch { /* absent or corrupt — no detection */ }
  return found;
}

// Classify one target path for the adopt pipeline: {ok:true} when the path
// can be created/written, else {ok:false, reason} with a reason from the
// frozen closed set. Precedence: a dangling symlink at the path is
// 'dangling symlink'; a non-directory occupying the path — or any entry in
// the ancestor chain up to <top>, including a symlink resolving to a file —
// is 'path occupied by non-directory'; a symlink component anywhere in the
// path chain whose resolution leaves realpath(top) is 'symlink escape'
// (review M1: writes through such a chain land outside the repo — the walk
// resolves the deepest EXISTING entry of the chain via realpathSync and
// requires it to stay at/under realpath(top); symlinks resolving inside the
// repo stay permitted); an existing directory in the ancestor chain (the
// path's own directory included: files must be created inside it) that
// fails W_OK is 'unwritable ancestor'. The walk stops at <top>; nothing
// above the repo root is the adopt pipeline's to complain about.
function preflightPath(top, rel) {
  const abs = path.resolve(top, rel);
  const topAbs = path.resolve(top);
  let lst = null;
  try { lst = fs.lstatSync(abs); } catch { lst = null; }
  if (lst !== null) {
    if (lst.isSymbolicLink()) {
      let st = null;
      try { st = fs.statSync(abs); } catch { st = null; }
      if (st === null) return { ok: false, reason: REASON_DANGLING };
      if (!st.isDirectory()) return { ok: false, reason: REASON_OCCUPIED };
    } else if (!lst.isDirectory()) {
      return { ok: false, reason: REASON_OCCUPIED };
    }
  }
  // Symlink-escape guard: walk the path's components down to the deepest
  // EXISTING entry (the path itself when it exists) and realpath it — a
  // resolved chain that lands outside realpath(top) means some symlink
  // component points out of the repo and any write through the chain
  // escapes. An unresolvable realpath (dangling mid-chain) classifies
  // nothing here: the write itself will fail before leaving the repo.
  let realTop = null;
  try { realTop = fs.realpathSync(topAbs); } catch { realTop = null; }
  if (realTop !== null) {
    let curPath = abs;
    let deepest = null;
    for (;;) {
      let st = null;
      try { st = fs.lstatSync(curPath); } catch { st = null; }
      if (st !== null) { deepest = curPath; break; }
      if (curPath === topAbs) break;
      const parent = path.dirname(curPath);
      if (parent === curPath) break;
      curPath = parent;
    }
    if (deepest !== null) {
      let real = null;
      try { real = fs.realpathSync(deepest); } catch { real = null; }
      if (real !== null && real !== realTop && !real.startsWith(realTop + path.sep)) {
        return { ok: false, reason: REASON_ESCAPE };
      }
    }
  }
  let cur = lst !== null && lst.isDirectory() ? abs : path.dirname(abs);
  for (;;) {
    let st = null;
    try { st = fs.statSync(cur); } catch { st = null; }
    if (st !== null) {
      if (!st.isDirectory()) return { ok: false, reason: REASON_OCCUPIED };
      try { fs.accessSync(cur, fs.constants.W_OK); } catch { return { ok: false, reason: REASON_UNWRITABLE }; }
    }
    if (cur === topAbs) break;
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  return { ok: true };
}

// Preflight every path (repo-relative) in one pass: { <path-as-given>:
// {ok:true} | {ok:false, reason} }. Pure — classification only, no mkdir or
// repair attempts; the adopt pipeline acts on the verdicts afterwards.
function preflight(top, paths) {
  const out = {};
  for (const p of paths) out[p] = preflightPath(top, p);
  return out;
}

module.exports = { classifyHooksPath, hookOwnership, detectCommitlintConfigs, preflight, contractTokens };
