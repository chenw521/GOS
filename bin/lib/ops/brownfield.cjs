// ops/brownfield — `gos brownfield`: adopt GOS into an existing repo.
// Lock-free global class (registry-consts GLOBAL_CMDS, ): mutates repo
// files like `setup --commitlint`, never takes the .gos/.lock; concurrency
// safety = every write goes through the gitseed engine's temp+fsync+rename.
// : entry guards (exit 4/4/5/1, ), preflight , the
// three-way hooksPath rule with DORMANT seeding, commitlint detection
// , the empty gates skeleton landed UNTRUSTED , the
// .gos/.gitignore semantic lock check , the binary skip
// taxonomy with the remediation/override partition, and the --json
// single-object envelope (fatal envelope on stdout, stack on stderr).
// Prompt-free by construction: no interactive primitive is imported or
// reached; the engine always runs nonInteractive. Status/state-flag/exit
// tokens are imported from command_contracts (single frozen source, loud on
// drift — same pattern as brownfield-probe.cjs). Wave 4 (T6) landed the
// handoff block ( map preview, platform probe), the
// --print-agents-skeleton (stdout only) and the core.t() locale migration:
// EVERY human-readable string flows through brownfield.* locale keys (en
// canonical + zh same batch, ) via the single H render block — JSON
// field names and status/flag/exit tokens stay locale-invariant.
// Review-fix wave (brownfield review): M1 symlink-escape preflight token
// (probe-side guard), M3 drifted GOS-lineage hooks are conflict-kept and
// overridable (never-overwrite list = user-owned hooks only), M4 blocked /
// engine-skip / write-failed rows are report_only so kept_conflict ⟺
// override entry ( both ways), M5 dynamic paths render shell-quoted,
// m7 duplicate named --overwrite dies, m8 gates skeleton derived once,
// m9 shared contract-token derivation (probe.contractTokens), m11 self-root
// guard realpaths both sides.
'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');
const core = require('../core/index.cjs');
const probe = require('./brownfield-probe.cjs');
const gitseed = require('./gitseed.cjs');
const sibSetup = require('./setup.cjs');

// ---- frozen vocabulary import (command_contracts is the only source) ----

function bfToken(contractKey, wanted, desc) {
  const hit = probe.contractTokens(contractKey).find((s) => s === wanted);
  if (!hit) {
    throw new Error(`brownfield: command_contracts.${contractKey} drifted — expected token '${wanted}' (${desc})`);
  }
  return hit;
}

// Slice pin (review m9): every brownfieldExitCodes segment leads with its
// single exit digit ('0 success; 1 generic fatal; …5 self-repo' — digits
// 0-5 frozen in state.cjs + ), so the leading char IS the code; the
// /^\d/ guard above rejects a segment that stops leading with a digit. If a
// future exit code ever grows past one digit this one-char slice truncates
// — extend it together with the contract, not silently here.
function bfExitCode(keyword) {
  const seg = String(core.CONTRACTS.command_contracts.brownfieldExitCodes || '').split('; ')
    .find((s) => s.includes(keyword));
  if (!seg || !/^\d/.test(seg)) {
    throw new Error(`brownfield: command_contracts.brownfieldExitCodes drifted — no segment matching '${keyword}'`);
  }
  return Number(seg.slice(0, 1));
}

const BF_STATUS = {
  created: bfToken('brownfieldStatusSet', 'created', 'lifecycle status'),
  keptIdentical: bfToken('brownfieldStatusSet', 'kept_identical', 'lifecycle status'),
  keptConflict: bfToken('brownfieldStatusSet', 'kept_conflict', 'lifecycle status'),
  locked: bfToken('brownfieldStatusSet', 'locked_user_owned', 'lifecycle status'),
  reportOnly: bfToken('brownfieldStatusSet', 'report_only', 'lifecycle status'),
};
const BF_FLAG_INACTIVE = bfToken('brownfieldStateFlags', 'inactive', 'state flag');
const BF_FLAG_UNTRUSTED = bfToken('brownfieldStateFlags', 'untrusted', 'state flag');
const BF_EXIT = {
  fatal: bfExitCode('generic fatal'),
  locked: bfExitCode('locked-overwrite'),
  unknown: bfExitCode('unknown asset'),
  notGit: bfExitCode('non-git'),
  self: bfExitCode('self-repo'),
};
// Frozen preflight reason tokens — derived via the shared helper (review
// m9) so the split + drift rules live only in brownfield-probe.cjs.
const BF_PF_SET = probe.contractTokens('brownfieldPreflightReasons');
const BF_PF_OCCUPIED = BF_PF_SET.find((s) => s.includes('non-directory'));
const BF_PF_DANGLING = BF_PF_SET.find((s) => s.includes('dangling'));
const BF_PF_UNWRITABLE = BF_PF_SET.find((s) => s.includes('unwritable'));
if (!BF_PF_OCCUPIED || !BF_PF_DANGLING || !BF_PF_UNWRITABLE) {
  throw new Error('brownfield: command_contracts.brownfieldPreflightReasons drifted — expected non-directory/dangling/unwritable tokens');
}

// ---- asset ids, fixed row order, remediation argv constants ----

const BF_HOOK_RELS = [sibSetup.COMMITLINT_HOOK_REL, sibSetup.PRE_PUSH_HOOK_REL];
const BF_HOOKS_PATH_ROW = 'core.hooksPath';
const BF_YAML_REL = 'commitlint.config.yaml';
const BF_GATES_JSON_REL = path.join('.gos', 'gates.json');
const BF_CHECK_SH_REL = path.join('.gos', 'gates', 'check.sh');
const BF_GOSIGNORE_REL = path.join('.gos', core.GOS_PATHS.gitignore.rel);
const BF_AGENTS_RELS = ['AGENTS.md', 'CLAUDE.md', 'GEMINI.md'];
const BF_ROW_ORDER = [...BF_HOOK_RELS, BF_HOOKS_PATH_ROW, BF_YAML_REL, BF_GATES_JSON_REL, BF_CHECK_SH_REL, BF_GOSIGNORE_REL, ...BF_AGENTS_RELS];
const BF_RM_ACTIVATE = ['gos', 'setup', '--commitlint'];
const BF_RM_TRUST = ['gos', 'gate', 'trust', 'check.sh'];
const BF_RM_SKELETON = ['gos', 'brownfield', '--print-agents-skeleton'];
const BF_RM_LINK = ['gos', 'setup', '--no-onboard'];
const BF_MAP_TRIGGER = ['gos', 'init', '<level>'];
const BF_GITIGNORE_TEXT = '.lock\n';

// ---- entry ----

function cmdBrownfield(args) {
  const opts = bfParseFlags(Array.isArray(args) ? args : []);
  // bfRun is async — it rejects through this .catch, never throws sync
  // (review m7: the old outer try/catch was dead code around a promise).
  bfRun(opts).catch((e) => {
    bfFatal(opts.json, BF_EXIT.fatal, `brownfield: ${e.message}`, e);
  });
}

function bfParseFlags(args) {
  const jsonMode = args.includes('--json');
  let overwriteAll = false;
  let overwriteAsset = null;
  let printSkeleton = false;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--json') continue;
    if (a === '--print-agents-skeleton') { printSkeleton = true; continue; }
    if (a === '--overwrite') {
      const nxt = args[i + 1];
      if (nxt !== undefined && !nxt.startsWith('--')) {
        // review m7: a SECOND named value is not silent last-wins — the
        // flag is single-use (bare or one asset name)
        if (overwriteAsset !== null) bfFatal(jsonMode, BF_EXIT.fatal, H.errUnexpectedArg(nxt));
        overwriteAsset = nxt; i++;
      }
      else overwriteAll = true;
      continue;
    }
    if (a.startsWith('--')) bfFatal(jsonMode, BF_EXIT.fatal, H.errUnknownFlag(a));
    bfFatal(jsonMode, BF_EXIT.fatal, H.errUnexpectedArg(a));
  }
  if (overwriteAsset !== null && overwriteAll) bfFatal(jsonMode, BF_EXIT.fatal, H.errDoubleOverwrite());
 // : the skeleton print is a standalone stdout offer — mixing it with
  // repo-mutating flags would blur the never-writes guarantee.
  if (printSkeleton && (overwriteAll || overwriteAsset !== null)) bfFatal(jsonMode, BF_EXIT.fatal, H.errSkeletonCombo());
  return { json: jsonMode, overwriteAll, overwriteAsset, printSkeleton };
}

// One exit path for every die-class: --json prints the error envelope on
// stdout (stack, when present, goes to stderr); human mode prints one line.
function bfFatal(jsonMode, code, message, err) {
  if (jsonMode) {
    console.log(JSON.stringify({ error: { code, message } }));
  } else {
    console.error(H.fatalLine(message));
  }
  if (err && err.stack) console.error(err.stack);
  process.exit(code);
}

// Guard order is frozen ( /exit table): non-git -> 4; cwd != toplevel ->
// 4; self-repo -> 5; hooks state file exists-but-corrupt -> 1 with path.
// A missing state file is NOT created here — activation (`setup
// --commitlint`) owns its creation .
function bfGuardEntry(opts) {
  let top = null;
  try {
    top = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() || null;
  } catch { top = null; }
  if (!top) bfFatal(opts.json, BF_EXIT.notGit, H.errNotGit());
  let realTop = top;
  try { realTop = fs.realpathSync(top); } catch { /* keep git's answer */ }
  let here = realTop;
  try { here = fs.realpathSync('.'); } catch { /* keep */ }
  if (here !== realTop) bfFatal(opts.json, BF_EXIT.notGit, H.errCwd(top));
  // review m11: realpath BOTH sides — a self-repo reached through a
  // symlinked path must still trip the guard (string compare of a raw
  // GOS_SELF_ROOT against realTop would miss it)
  let realSelf = core.GOS_SELF_ROOT;
  try { realSelf = fs.realpathSync(realSelf); } catch { /* keep raw */ }
  if (realTop === realSelf) bfFatal(opts.json, BF_EXIT.self, H.errSelf());
  const statePath = path.join(realTop, sibSetup.COMMITLINT_STATE_REL);
  if (fs.existsSync(statePath)) {
    try { JSON.parse(fs.readFileSync(statePath, 'utf8')); }
    catch { bfFatal(opts.json, BF_EXIT.fatal, H.errCorruptState(statePath)); }
  }
  return realTop;
}

// ---- masters + derived content ----

function bfReadMasters() {
  const read = (p) => {
    try { return fs.readFileSync(p, 'utf8'); }
    catch (e) { throw new Error(`master missing: ${p} (${e.message}) — reinstall GOS`); }
  };
  const hookSrc = (rel) => path.join(core.GOS_SELF_ROOT, 'hooks', `${path.basename(rel)}.sh`);
  return {
    hooks: Object.fromEntries(BF_HOOK_RELS.map((rel) => [rel, read(hookSrc(rel))])),
    yaml: read(path.join(core.GOS_SELF_ROOT, 'templates', 'git', BF_YAML_REL)),
    checkSh: read(path.join(core.GOS_SELF_ROOT, 'templates', 'gates', 'check.sh')),
  };
}

// Empty gates skeleton, derived at runtime from the setup-path template:
// protect/forbid emptied, lint nulled, _comment retained. The template's
// ACTIVE example rules never land verbatim ( /F3-1).
function bfGatesSkeletonText() {
  const tpl = JSON.parse(fs.readFileSync(path.join(core.GOS_SELF_ROOT, 'templates', 'gates', 'gates.json'), 'utf8'));
  const out = {};
  if (typeof tpl._comment === 'string') out._comment = tpl._comment;
  out.protect = [];
  out.forbid = [];
  out.lint = null;
  return JSON.stringify(out, null, 2) + '\n';
}

// Semantic .lock check : an effective ignore line for the machine
// lock inside .gos/.gitignore — literal '.lock', anchored '/.lock', or the
// '*.lock' glob all ignore .gos/.lock; comments/other lines do not.
function bfGitignoreHasLock(text) {
  for (let raw of String(text).split('\n')) {
    const line = raw.replace(/\r$/, '').trim();
    if (!line || line.startsWith('#')) continue;
    if (line === '.lock' || line === '/.lock' || line === '*.lock') return true;
  }
  return false;
}

// ---- classification (probe is the truth-source; no writes here) ----

// Per-asset dispositions (internal vocabulary):
//   blocked          path/ancestor refused by preflight (frozen reason kept)
//   live_dir         hooks under a hooksPath that resolves to <top>/hooks
//   foreign          hooks under a foreign hooks manager (husky/lefthook/…)
//   locked           user-owned hook file (probe ownership)
//   create / identical / conflict   engine-shaped file dispositions
//   detect_conflict  yaml absent but an external commitlint config exists
//   has_lock / no_lock  .gos/.gitignore semantic states
function bfProbeAll(top) {
  const masters = bfReadMasters();
  // review m8: the gates skeleton is derived ONCE here (probe pass) and
  // carried in the plan — the adopt pass used to re-read + re-parse the
  // template a second time.
  masters.skeleton = bfGatesSkeletonText();
  const hooksClass = probe.classifyHooksPath(top);
  let rawHooksPath = null;
  try {
    rawHooksPath = execFileSync('git', ['-C', top, 'config', '--get', 'core.hooksPath'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() || null;
  } catch { rawHooksPath = null; }
  const detected = probe.detectCommitlintConfigs(top);
  // review m6: 'hooks' is the only directory position probed — the file
  // paths walk their own ancestor chains inside preflightPath (occupancy,
  // writability, symlink escape), so separate '.gos'/'.gos/gates' entries
  // computed nothing that was ever consumed.
  const pf = probe.preflight(top, [
    'hooks',
    ...BF_HOOK_RELS, BF_YAML_REL, BF_GATES_JSON_REL, BF_CHECK_SH_REL, BF_GOSIGNORE_REL,
  ]);
  // File-path verdict: a regular file at the path is a CONTENT conflict the
  // engine owns (kept/locked taxonomy), not a path block; a directory, a
  // dangling symlink, a symlink escaping the repo, or an unwritable
  // ancestor is a block with the frozen reason. The 'hooks' directory
  // position blocks the whole hook group (covers an entry the per-file walk
  // cannot flag).
  const verdict = (rel) => {
    const v = pf[rel];
    if (!v || v.ok) return { ok: true };
    if (v.reason === BF_PF_OCCUPIED) {
      let st = null;
      try { st = fs.lstatSync(path.join(top, rel)); } catch { st = null; }
      if (st !== null && st.isFile()) return { ok: true };
    }
    return { ok: false, reason: v.reason };
  };
  const dirBlocked = (rel) => (pf[rel] && !pf[rel].ok) ? pf[rel].reason : null;
  const engineDisp = (rel, content) => {
    const v = verdict(rel);
    if (!v.ok) return { disp: 'blocked', pfReason: v.reason };
    let bytes = null;
    try { bytes = fs.readFileSync(path.join(top, rel)); } catch { bytes = null; }
    if (bytes === null) return { disp: 'create' };
    if (Buffer.compare(bytes, Buffer.from(content, 'utf8')) === 0) return { disp: 'identical' };
    return { disp: 'conflict' };
  };

  const assets = {};
  for (const rel of BF_HOOK_RELS) {
    const ownership = probe.hookOwnership(path.join(top, rel), path.join(core.GOS_SELF_ROOT, 'hooks', `${path.basename(rel)}.sh`));
    if (hooksClass === 'gos_hooks_dir') assets[rel] = { kind: 'hook', disp: 'live_dir' };
    else if (hooksClass === 'foreign') assets[rel] = { kind: 'hook', disp: 'foreign' };
    else {
      const dirReason = dirBlocked('hooks');
      if (dirReason) assets[rel] = { kind: 'hook', disp: 'blocked', pfReason: dirReason };
      else if (ownership === 'user') assets[rel] = { kind: 'hook', disp: 'locked' };
      else assets[rel] = { kind: 'hook', ownership, ...engineDisp(rel, masters.hooks[rel]) };
    }
  }
  assets[BF_HOOKS_PATH_ROW] = { kind: 'config-probe' };
  {
    const v = verdict(BF_YAML_REL);
    if (!v.ok) assets[BF_YAML_REL] = { kind: 'yaml', disp: 'blocked', pfReason: v.reason };
    else {
      const d = engineDisp(BF_YAML_REL, masters.yaml);
      if (d.disp === 'create' && detected.length) assets[BF_YAML_REL] = { kind: 'yaml', disp: 'detect_conflict' };
      else assets[BF_YAML_REL] = { kind: 'yaml', ...d };
    }
  }
  assets[BF_GATES_JSON_REL] = { kind: 'gates', ...engineDisp(BF_GATES_JSON_REL, masters.skeleton) };
  assets[BF_CHECK_SH_REL] = { kind: 'checksh', ...engineDisp(BF_CHECK_SH_REL, masters.checkSh) };
  {
    const v = verdict(BF_GOSIGNORE_REL);
    if (!v.ok) assets[BF_GOSIGNORE_REL] = { kind: 'gosignore', disp: 'blocked', pfReason: v.reason };
    else {
      let text = null;
      try { text = fs.readFileSync(path.join(top, BF_GOSIGNORE_REL), 'utf8'); } catch { text = null; }
      assets[BF_GOSIGNORE_REL] = text === null
        ? { kind: 'gosignore', disp: 'create' }
        : { kind: 'gosignore', disp: bfGitignoreHasLock(text) ? 'has_lock' : 'no_lock' };
    }
  }
  for (const rel of BF_AGENTS_RELS) {
    let st = null;
    try { st = fs.lstatSync(path.join(top, rel)); } catch { st = null; }
    assets[rel] = { kind: 'agent', state: st === null ? 'absent' : st.isFile() ? 'file' : 'other' };
  }
  return { masters, hooksClass, rawHooksPath, detected, assets };
}

// ---- tiered overwrite validation ( : exit 2 refused / exit 3 unknown)

function bfValidateOverwrite(plan, opts) {
  if (!opts.overwriteAsset) return;
  const name = opts.overwriteAsset;
  const a = plan.assets[name];
  if (!a) bfFatal(opts.json, BF_EXIT.unknown, H.errUnknownAsset(name, BF_ROW_ORDER));
  const refuse = (why) => bfFatal(opts.json, BF_EXIT.locked, H.errLockedOverwrite(name, why));
  if (a.kind === 'config-probe') refuse(H.whyNeverConfig());
  if (a.kind === 'agent') refuse(H.whyAgent());
  if (a.disp === 'blocked') refuse(H.whyBlocked(a.pfReason));
  if (a.kind === 'hook') {
    if (a.disp === 'foreign') refuse(H.whyForeignHooks());
    if (a.disp === 'live_dir') refuse(H.whyLiveDir());
    if (a.disp === 'locked') refuse(H.whyUserHook());
  }
}

// The force set: bare --overwrite adopts exactly the overridable conflict
// set; --overwrite <asset> adopts exactly one (already validated above).
function bfForceSet(plan, opts) {
  const forced = new Set();
  if (opts.overwriteAsset) {
    forced.add(opts.overwriteAsset);
    return forced;
  }
  if (!opts.overwriteAll) return forced;
  const conflictKind = { hook: ['conflict'], yaml: ['conflict', 'detect_conflict'], gates: ['conflict'], checksh: ['conflict'], gosignore: ['no_lock'] };
  for (const [id, a] of Object.entries(plan.assets)) {
    if ((conflictKind[a.kind] || []).includes(a.disp)) forced.add(id);
  }
  return forced;
}

// ---- adopt: engine calls per asset, rows + override section ----

async function bfAdopt(top, plan, forced) {
  const rows = {};
  const overrides = [];
  const m = plan.masters;
  const skeletonText = m.skeleton;

  // One engine call per destination — exact per-asset force control; each
  // call is temp+fsync+rename atomic and never stages anything. The
  // neverOverwrite hard line is for USER-owned hooks only (review M3):
  // drifted GOS-lineage hooks (gos_marker/gos_grandfather with bytes ≠
  // master) are genuine content conflicts — conflict-kept with an override
  // entry, overridable via --overwrite through the standard engine path
  // (backup .gos-bak first).
  const engineOutcome = async (rel, content, force, never) => {
    const res = await gitseed.seed({
      root: top,
      files: { [rel]: content },
      overwrite: !!force,
      neverOverwrite: never ? [rel] : [],
      nonInteractive: true,
    });
    if (res.created.includes(rel)) return 'created';
    if (res.overwritten.includes(rel)) return 'overwritten';
    const d = res.skippedDetail.find((x) => x.dest === rel);
    return d ? d.reason : 'identical';
  };
  const row = (rel, status, extra) => { rows[rel] = { asset: rel, status, state_flags: [], ...extra }; };
  const overrideEntry = (rel, consequence) => {
    overrides.push({ asset: rel, command: ['gos', 'brownfield', '--overwrite', rel], consequence });
  };
  const chmodIfExecutable = (rel) => {
    try { fs.chmodSync(path.join(top, rel), 0o755); } catch { /* best-effort */ }
  };

 // ---- hooks: three-way rule
  // Review M4: preflight-blocked, write-failed and engine-structural-skip
  // rows are report_only (manual remediation) — kept_conflict is reserved
  // for genuine content conflicts and always carries an override entry
 // ( : kept_conflict ⟺ overridable, both directions).
  for (const rel of BF_HOOK_RELS) {
    const a = plan.assets[rel];
    if (a.disp === 'live_dir') { row(rel, BF_STATUS.reportOnly, { reason: H.whyLiveDirRow(), remediation: [...BF_RM_ACTIVATE] }); continue; }
    if (a.disp === 'foreign') { row(rel, BF_STATUS.locked, { reason: H.whyForeignRow(plan.rawHooksPath) }); continue; }
    if (a.disp === 'blocked') { row(rel, BF_STATUS.reportOnly, { state_flags: [BF_FLAG_INACTIVE], reason: H.whyBlocked(a.pfReason) }); continue; }
    if (a.disp === 'locked') { row(rel, BF_STATUS.locked, { state_flags: [BF_FLAG_INACTIVE], reason: H.whyUserHookRow() }); continue; }
    let outcome;
    try { outcome = await engineOutcome(rel, m.hooks[rel], forced.has(rel), a.ownership === 'user'); }
    catch (e) { row(rel, BF_STATUS.reportOnly, { state_flags: [BF_FLAG_INACTIVE], reason: H.whyWriteFailed(e) }); continue; }
    if (outcome === 'created' || outcome === 'overwritten') {
      chmodIfExecutable(rel);
      row(rel, BF_STATUS.created, { state_flags: [BF_FLAG_INACTIVE], remediation: [...BF_RM_ACTIVATE] });
    } else if (outcome === 'identical') {
      row(rel, BF_STATUS.keptIdentical, { state_flags: [BF_FLAG_INACTIVE], remediation: [...BF_RM_ACTIVATE] });
    } else if (outcome === 'never') {
      row(rel, BF_STATUS.locked, { state_flags: [BF_FLAG_INACTIVE], reason: H.whyUserHookRow() });
    } else if (outcome === 'conflict-kept') {
      row(rel, BF_STATUS.keptConflict, { state_flags: [BF_FLAG_INACTIVE], reason: H.whyDriftedHookRow() });
      overrideEntry(rel, H.consReplace(rel));
    } else {
      row(rel, BF_STATUS.reportOnly, { state_flags: [BF_FLAG_INACTIVE], reason: H.whyEngineSkip(outcome) });
    }
  }
  row(BF_HOOKS_PATH_ROW, BF_STATUS.reportOnly, { reason: H.whyHooksPathRow(plan.hooksClass) });

  // ---- commitlint.config.yaml: detection beats creation unless forced ----
  {
    const rel = BF_YAML_REL;
    const a = plan.assets[rel];
    if (a.disp === 'blocked') { row(rel, BF_STATUS.reportOnly, { reason: H.whyBlocked(a.pfReason) }); }
    else if (a.disp === 'detect_conflict' && !forced.has(rel)) {
      row(rel, BF_STATUS.keptConflict, { reason: H.whyDetected(plan.detected) });
      overrideEntry(rel, H.consCreateBeside(plan.detected));
    } else {
      let outcome;
      try { outcome = await engineOutcome(rel, m.yaml, forced.has(rel), false); }
      catch (e) { row(rel, BF_STATUS.reportOnly, { reason: H.whyWriteFailed(e) }); }
      if (rows[rel] === undefined) {
        if (outcome === 'created' || outcome === 'overwritten') row(rel, BF_STATUS.created, {});
        else if (outcome === 'identical') row(rel, BF_STATUS.keptIdentical, {});
        else if (outcome === 'conflict-kept') {
          row(rel, BF_STATUS.keptConflict, { reason: H.whyDivergedYamlRow() });
          overrideEntry(rel, H.consReplace(rel));
        } else row(rel, BF_STATUS.reportOnly, { reason: H.whyEngineSkip(outcome) });
      }
    }
  }

  // ---- gates: empty skeleton + untrusted check.sh (never auto-trusted) ----
  const gateAssets = [
    [BF_GATES_JSON_REL, skeletonText, []],
    [BF_CHECK_SH_REL, m.checkSh, [BF_FLAG_UNTRUSTED]],
  ];
  for (const [grel, content, flags] of gateAssets) {
    const isSh = grel === BF_CHECK_SH_REL;
    const extra = isSh ? { remediation: [...BF_RM_TRUST] } : {};
    const a = plan.assets[grel];
    if (a.disp === 'blocked') { row(grel, BF_STATUS.reportOnly, { state_flags: flags, reason: H.whyBlocked(a.pfReason), ...extra }); continue; }
    let outcome;
    try { outcome = await engineOutcome(grel, content, forced.has(grel), false); }
    catch (e) { row(grel, BF_STATUS.reportOnly, { state_flags: flags, reason: H.whyWriteFailed(e), ...extra }); continue; }
    if (outcome === 'created' || outcome === 'overwritten') {
      if (isSh) chmodIfExecutable(grel);
      row(grel, BF_STATUS.created, { state_flags: flags, ...extra });
    } else if (outcome === 'identical') {
      row(grel, BF_STATUS.keptIdentical, { state_flags: flags, ...extra });
    } else if (outcome === 'conflict-kept') {
      row(grel, BF_STATUS.keptConflict, { state_flags: flags, reason: H.whyDivergedGateRow(), ...extra });
      overrideEntry(grel, H.consReplace(grel));
    } else {
      row(grel, BF_STATUS.reportOnly, { state_flags: flags, reason: H.whyEngineSkip(outcome), ...extra });
    }
  }

  // ---- .gos/.gitignore: semantic .lock check; root .gitignore never touched ----
  {
    const rel = BF_GOSIGNORE_REL;
    const a = plan.assets[rel];
    if (a.disp === 'blocked') { row(rel, BF_STATUS.reportOnly, { reason: H.whyBlocked(a.pfReason) }); }
    else if (a.disp === 'has_lock') { row(rel, BF_STATUS.keptIdentical, {}); }
    else if (a.disp === 'create') {
      let failed = false;
      let outcome = null;
      try { outcome = await engineOutcome(rel, BF_GITIGNORE_TEXT, forced.has(rel), false); }
      catch (e) { row(rel, BF_STATUS.reportOnly, { reason: H.whyWriteFailed(e) }); failed = true; }
      if (!failed) {
        if (outcome === 'created' || outcome === 'overwritten') row(rel, BF_STATUS.created, {});
        else if (outcome === 'identical') row(rel, BF_STATUS.keptIdentical, {});
        else row(rel, BF_STATUS.reportOnly, { reason: H.whyEngineSkip(outcome) });
      }
    } else if (a.disp === 'no_lock' && !forced.has(rel)) {
      row(rel, BF_STATUS.keptConflict, { reason: H.whyNoLock() });
      overrideEntry(rel, H.consAppend(rel));
    } else {
      // no_lock + forced: repair, not replace — keep the user's lines, append
      // the missing .lock line; the engine still writes backup + atomic body.
      let failed = false;
      let outcome = null;
      try {
        let cur = '';
        try { cur = fs.readFileSync(path.join(top, rel), 'utf8'); } catch { /* race: treat as empty */ }
        const merged = cur === '' || cur.endsWith('\n') ? cur : `${cur}\n`;
        outcome = await engineOutcome(rel, merged + BF_GITIGNORE_TEXT, true, false);
      } catch (e) {
        row(rel, BF_STATUS.reportOnly, { reason: H.whyWriteFailed(e) });
        failed = true;
      }
      if (!failed) {
        if (outcome === 'created' || outcome === 'overwritten') row(rel, BF_STATUS.created, { reason: H.noteAppended() });
        else row(rel, BF_STATUS.reportOnly, { reason: H.whyEngineSkip(outcome) });
      }
    }
  }

 // ---- AGENTS family: report rows only — never a write
  for (const arel of BF_AGENTS_RELS) {
    const a = plan.assets[arel];
    if (a.state === 'absent') row(arel, BF_STATUS.reportOnly, { reason: H.whyAgentAbsent(), remediation: [...BF_RM_SKELETON] });
    else if (a.state === 'file') row(arel, BF_STATUS.reportOnly, { reason: H.whyAgentPresent() });
    else row(arel, BF_STATUS.reportOnly, { reason: H.whyAgentIrregular() });
  }

  const assets = BF_ROW_ORDER.filter((id) => rows[id]).map((id) => rows[id]);
  const orderIdx = (id) => BF_ROW_ORDER.indexOf(id);
  overrides.sort((x, y) => orderIdx(x.asset) - orderIdx(y.asset));
  return { assets, overrides };
}

// ---- pipeline + rendering ----

async function bfRun(opts) {
 // skeleton offer: standalone stdout print, exit 0, zero writes — it
  // runs before any entry guard so it works from any directory (the file is
  // the user's to create, never GOS's to write).
  if (opts.printSkeleton) {
    const text = H.skeletonBody();
    if (opts.json) console.log(JSON.stringify({ skeleton: text, note: H.skeletonNote() }));
    else {
      console.log(text);
      console.error(H.skeletonNote());
    }
    return;
  }
  const top = bfGuardEntry(opts);
  const plan = bfProbeAll(top);
  bfValidateOverwrite(plan, opts);
  const forced = bfForceSet(plan, opts);
  const { assets, overrides } = await bfAdopt(top, plan, forced);
 // closing platform probe: pure reads via the setup-module detector
  // (the linking command itself is never executed); shape 'parent' links one
  // dir, shape 'individual' links per-skill entries — ok requires every one.
 // Kept inline (no new top-level fn: fnDist freeze).
  const platforms = sibSetup.detectPlatforms(os.homedir()).map((p) => {
    const linked = p.shape === 'parent'
      ? fs.existsSync(p.link)
      : sibSetup.GOS_SKILL_NAMES.length > 0 && sibSetup.GOS_SKILL_NAMES.every((s) => fs.existsSync(path.join(p.linkDir, s)));
    return { name: p.name, status: linked ? 'ok' : 'missing' };
  });
  const report = {
    root: top,
    hooks_path_class: plan.hooksClass,
    assets,
    overrides,
    handoff: {
      map_trigger: [...BF_MAP_TRIGGER],
      platforms,
      platform_remediation: [...BF_RM_LINK],
    },
  };
  if (opts.json) console.log(JSON.stringify(report));
  else bfRenderHuman(report);
}

// Human report: numbered remediation steps (prose, never pipeable shell
// lines), override commands in their own section with consequence notes,
// every rendered path shell-quoted , closing handoff block ( )
// at the very end.
function bfRenderHuman(report) {
  console.log(H.title(report.root));
  console.log(H.hooksClassLine(report.hooks_path_class));
  console.log('');
  console.log(H.assetsHeader());
  for (const r of report.assets) {
    const flags = r.state_flags.length ? ` [${r.state_flags.join(', ')}]` : '';
    console.log(H.assetLine(r.status, r.asset, flags));
    if (r.reason) console.log(`      ${H.reasonLine(r.reason)}`);
  }
  const remRows = report.assets.filter((r) => r.remediation);
  if (remRows.length) {
    console.log('');
    console.log(H.remHeader());
    let i = 1;
    for (const r of remRows) console.log(`  ${H.remStep(i++, r.asset, r.remediation.join(' '))}`);
  }
  if (report.overrides.length) {
    console.log('');
    console.log(H.ovrHeader());
    let i = 1;
    for (const e of report.overrides) {
      console.log(`  ${H.ovrStep(i++, e.asset, e.command.join(' '))}`);
      console.log(`     ${H.ovrConsequence(e.consequence)}`);
    }
  }
  if (report.handoff) {
    console.log('');
    console.log(H.handoffHeader());
    console.log(`  1. ${H.handoffMapPreview()}`);
    console.log(`  2. ${H.handoffPlatformsHeader()}`);
    for (const p of report.handoff.platforms) console.log(`     - ${H.handoffPlatformRow(p.name, p.status)}`);
    if (!report.handoff.platforms.length) console.log(`     - ${H.handoffNoPlatform()}`);
    else if (report.handoff.platforms.some((p) => p.status === 'missing')) console.log(`     ${H.handoffPlatformFix()}`);
  }
}

// ---- H: render layer — every human-readable string flows through core.t()
// (brownfield.* locale keys, en canonical + zh same batch, ); layout
// indentation stays in code; status/flag/exit tokens and JSON field names
// are locale-invariant by contract ----

const H = {
  fatalLine: (msg) => core.t('brownfield.fatal.line', { msg }),
  title: (root) => core.t('brownfield.title', { root: core.shellQ(root) }),
  hooksClassLine: (cls) => core.t(cls === 'unset'
    ? 'brownfield.hooksClass.unset'
    : cls === 'gos_hooks_dir'
      ? 'brownfield.hooksClass.gosHooksDir'
      : 'brownfield.hooksClass.foreign', {}),
  assetsHeader: () => core.t('brownfield.assetsHeader', {}),
  assetLine: (status, asset, flags) => `  ${status.padEnd(18)} ${asset}${flags}`,
  reasonLine: (reason) => core.t('brownfield.reasonLine', { reason }),
  remHeader: () => core.t('brownfield.rem.header', {}),
  remStep: (n, asset, command) => core.t('brownfield.rem.step', { n, asset, command }),
  ovrHeader: () => core.t('brownfield.ovr.header', {}),
  ovrStep: (n, asset, command) => core.t('brownfield.ovr.step', { n, asset, command }),
  ovrConsequence: (text) => core.t('brownfield.ovr.consequence', { text }),
  errNotGit: () => core.t('brownfield.err.notGit', {}),
  errCwd: (top) => core.t('brownfield.err.cwd', { top: core.shellQ(top) }),
  errSelf: () => core.t('brownfield.err.self', {}),
  errCorruptState: (p) => core.t('brownfield.err.corruptState', { path: core.shellQ(p) }),
  errUnknownFlag: (a) => core.t('brownfield.err.unknownFlag', { flag: a }),
  errUnexpectedArg: (a) => core.t('brownfield.err.unexpectedArg', { arg: core.sanitizeEcho(a) }),
  errDoubleOverwrite: () => core.t('brownfield.err.doubleOverwrite', {}),
  errUnknownAsset: (name, known) => core.t('brownfield.err.unknownAsset', { name: core.sanitizeEcho(name), known: known.join(', ') }),
  errLockedOverwrite: (name, why) => core.t('brownfield.err.lockedOverwrite', { asset: core.shellQ(name), why }),
  errSkeletonCombo: () => core.t('brownfield.err.skeletonCombo', {}),
  whyNeverConfig: () => core.t('brownfield.why.neverConfig', {}),
  whyAgent: () => core.t('brownfield.why.agent', {}),
  whyUserHook: () => core.t('brownfield.why.userHook', {}),
  whyForeignHooks: () => core.t('brownfield.why.foreignHooks', {}),
  whyLiveDir: () => core.t('brownfield.why.liveDir', {}),
  whyBlocked: (reason) => core.t('brownfield.why.blocked', { reason }),
  whyUserHookRow: () => core.t('brownfield.why.userHookRow', {}),
  whyDriftedHookRow: () => core.t('brownfield.why.driftedHookRow', {}),
  // review M5: the raw hooksPath is git-config controlled — render it
 // shell-quoted exactly like every other dynamic path
  whyForeignRow: (raw) => core.t('brownfield.why.foreignRow', { raw: core.shellQ(raw || 'set') }),
  whyLiveDirRow: () => core.t('brownfield.why.liveDirRow', {}),
  whyHooksPathRow: (cls) => core.t(cls === 'unset'
    ? 'brownfield.why.hooksPathRow.unset'
    : cls === 'gos_hooks_dir'
      ? 'brownfield.why.hooksPathRow.gosHooksDir'
      : 'brownfield.why.hooksPathRow.foreign', {}),
  whyDetected: (names) => core.t('brownfield.why.detected', { names: names.join(', ') }),
  whyDivergedYamlRow: () => core.t('brownfield.why.divergedYamlRow', {}),
  whyDivergedGateRow: () => core.t('brownfield.why.divergedGateRow', {}),
  whyNoLock: () => core.t('brownfield.why.noLock', {}),
  noteAppended: () => core.t('brownfield.note.appended', {}),
  whyAgentAbsent: () => core.t('brownfield.why.agentAbsent', {}),
  whyAgentPresent: () => core.t('brownfield.why.agentPresent', {}),
  whyAgentIrregular: () => core.t('brownfield.why.agentIrregular', {}),
  whyWriteFailed: (e) => core.t('brownfield.why.writeFailed', { message: e.message }),
  whyEngineSkip: (outcome) => core.t('brownfield.why.engineSkip', { outcome }),
  consReplace: (rel) => core.t('brownfield.cons.replace', { path: core.shellQ(`${rel}.gos-bak`) }),
  consCreateBeside: (names) => core.t('brownfield.cons.createBeside', { names: names.join(', ') }),
  consAppend: (rel) => core.t('brownfield.cons.append', { path: core.shellQ(`${rel}.gos-bak`) }),
  handoffHeader: () => core.t('brownfield.handoff.header', {}),
  handoffMapPreview: () => core.t('brownfield.handoff.mapPreview', {}),
  handoffPlatformsHeader: () => core.t('brownfield.handoff.platformsHeader', {}),
  handoffPlatformRow: (name, status) => core.t('brownfield.handoff.platformRow', { name, status }),
  handoffPlatformFix: () => core.t('brownfield.handoff.platformFix', {}),
  handoffNoPlatform: () => core.t('brownfield.handoff.noPlatform', {}),
  skeletonBody: () => core.t('brownfield.skeleton.body', {}),
  skeletonNote: () => core.t('brownfield.skeleton.note', {}),
};

module.exports = { cmdBrownfield };
