// knowledge/truth.cjs — knowledge module aspect: observable-truth command family.
// Sibling requires are free; cross-directory requires go to core only.
'use strict';

const { execFileSync } = require('node:child_process');

const fs = require('node:fs');
const path = require('node:path');
const core = require('../core/index.cjs');

const TRUTH_RECEIPTS_PATH = core.resolvePath('truth_receipts');

function truthNextId(state) {
  let max = 0;
  for (const t of state.observable_truths || []) {
    const m = /^T-?(\d+)$/i.exec(String((t && t.id) || ''));
    if (m) max = Math.max(max, parseInt(m[1], 10));
  }
  return `T${max + 1}`;
}

function truthFind(state, id) {
  return (state.observable_truths || []).find((t) => t && t.id === id) || null;
}

function appendTruthReceipt(id, commandStr) {
  // B-18-class hardening: a tracked symlink (.gos/truth-receipts.md → arbitrary
  // file) must not redirect receipt content; lstat regular-file check + O_NOFOLLOW.
  if (fs.existsSync(TRUTH_RECEIPTS_PATH) && !fs.lstatSync(TRUTH_RECEIPTS_PATH).isFile()) {
    core.die(`truth receipt: ${TRUTH_RECEIPTS_PATH} is not a regular file (symlink?) — write refused (B-18)`);
  }
  let needsNl = false;
  fs.mkdirSync(path.dirname(TRUTH_RECEIPTS_PATH), { recursive: true }); // logs/ may not exist yet
  try { const prev = fs.readFileSync(TRUTH_RECEIPTS_PATH, 'utf8'); needsNl = prev.length > 0 && !prev.endsWith('\n'); } catch { /* first receipt */ }
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  const line = `- [${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}] ${id} replay-verified: ${commandStr}\n`;
  fs.appendFileSync(TRUTH_RECEIPTS_PATH, (needsNl ? '\n' : '') + line,
    { flag: fs.constants.O_APPEND | fs.constants.O_CREAT | fs.constants.O_WRONLY | fs.constants.O_NOFOLLOW });
}

function cmdTruth(args) {
  const state = core.readState();
  if (!state) core.die(`${core.CONTRACTS.state_semantics.noActiveTask} \`gos init\` first.`);
  const sub = (args[0] || '').toLowerCase();
  const rest = args.slice(1);

  if (sub === 'add') {
    if (rest.length !== 1) core.die('Usage: gos truth add "<desc>" (one description argument, ≤500 codepoints)');
    const desc = rest[0];
    const bt = core.badText(desc);
    if (bt) core.die(`truth add: desc rejected: ${bt}`);
    const c = core.checkInputConstraint({ value: desc, maxCp: 500, label: 'desc', noNewlineListPrefix: true });
    if (!c.ok) core.die(`truth add: ${c.reason}`);
    const t = { id: truthNextId(state), description: c.value, verified: false, evidence: null };
    state.observable_truths.push(t);
    core.writeState(state);
    console.log(`Truth ${t.id} added: ${c.value}`);
    console.log('Next: gos truth verify ' + t.id + ' --command <c> --excerpt <e> --artifact <a> [--replay]');
    return;
  }

  if (sub === 'verify') {
    const id = rest[0];
    if (!id || id.startsWith('--')) core.die('Usage: gos truth verify <id> --command <c> --excerpt <e> --artifact <a> [--replay]');
    const truthL = truthFind(state, id);
    if (!truthL) core.die(`truth verify: ${id} not found`);
    let command = null, excerpt = null, artifact = null, replay = false;
    for (let i = 1; i < rest.length; i++) {
      if (rest[i] === '--command') command = rest[++i];
      else if (rest[i] === '--excerpt') excerpt = rest[++i];
      else if (rest[i] === '--artifact') artifact = rest[++i];
      else if (rest[i] === '--replay') replay = true;
      else core.die(`truth verify: unknown argument '${rest[i]}'`);
    }
    const repoRoot = core.currentRootRealpath() || process.cwd();

    if (replay) {
      if (excerpt !== null) core.die('truth verify --replay: --excerpt is derived from actual stdout — do not pass it');
      let argv = null;
      try { argv = JSON.parse(command); } catch { /* rejected below */ }
      if (!Array.isArray(argv) || argv.length === 0 || !argv.every((x) => typeof x === 'string')) {
        core.die(`truth verify --replay: --command must be a JSON array of strings, e.g. --command '["node","-e","console.log(3)"]' [B-1]`);
      }
      let stdout = '';
      try {
        stdout = execFileSync(argv[0], argv.slice(1), {
          cwd: repoRoot, stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000, encoding: 'utf8',
        });
      } catch (e) {
        const why = /timed out/i.test(String(e.message)) ? 'timed out (>30s)' : `command failed (${e.message.split('\n')[0]})`;
        core.die(`truth verify --replay: ${why} — evidence NOT set [B-1]`);
      }
      // The excerpt must be an actual stdout line hitting feature ② count-stats or
      // ③ path — the synthetic exit-code ① form is explicitly NOT a replay hit.
      const lines = String(stdout).split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
      const hit = lines.find((l) => core.cpLen(l) <= 200 && (core.EVIDENCE_FEATURE_RES[1].test(l) || core.EVIDENCE_FEATURE_RES[2].test(l)));
      if (!hit) {
        core.die(`truth verify --replay: no stdout line hits a required feature (count-stats or path; synthetic exit-code line does not count)${lines.length ? '' : ' — stdout empty'} [B-1/R2-6]`);
      }
      const commandStr = JSON.stringify(argv);
      const ev = { command: commandStr, output_excerpt: hit, artifact_path: artifact, replay: true };
      const evErr = core.validateEvidenceObject(ev, repoRoot);
      if (evErr) core.die(`truth verify: ${evErr}`);
      truthL.verified = true;
      truthL.evidence = ev;
      core.writeState(state);
      appendTruthReceipt(id, commandStr);
      console.log(`✓ truth ${id} replay-verified (evidence from actual stdout; receipt appended to .gos/truth-receipts.md)`);
      return;
    }

    // manual mode (default): three-element validation, no execution, manual:true flag
    const ev = { command, output_excerpt: excerpt, artifact_path: artifact, manual: true };
    const evErr = core.validateEvidenceObject(ev, repoRoot);
    if (evErr) core.die(`truth verify: ${evErr}`);
    truthL.verified = true;
    truthL.evidence = ev;
    core.writeState(state);
    console.log(`✓ truth ${id} verified (manual evidence — replay is the verification bar, gate will flag it)`);
    return;
  }

  if (sub === 'waive') {
    const id = rest[0];
    if (!id || id.startsWith('--') || !rest.includes('--reason')) {
      core.die('Usage: gos truth waive <id> --reason "<why external/blocked>"');
    }
    const reason = rest[rest.indexOf('--reason') + 1];
    if (!reason || reason.length < 10) core.die('truth waive: --reason must be at least 10 codepoints (auditable why)');
    const truthL = truthFind(state, id);
    if (!truthL) core.die(`truth waive: ${id} not found`);
    if (truthL.verified) core.die(`truth waive: ${id} is already verified — waive only applies to blocked truths`);
    truthL.waived = true;
    truthL.waive_reason = reason;
    truthL.waived_at = new Date().toISOString();
    core.writeState(state);
    console.log(`⚠ truth ${id} waived — external/blocked verification; gate will warn and track it, not block on it`);
    return;
  }

  console.log('Usage: gos truth <add|verify|waive>');
  console.log('  add "<desc>"                    register observable truth (auto id T1/T2…)');
  console.log('  waive <id> --reason "<why>"     park a blocked truth (external dependency) — gate warns, never silently passes');
  console.log('  add "<desc>"                    register observable truth (auto id T1/T2…)');
  console.log('  verify <id> --command <c> --excerpt <e> --artifact <a>          manual evidence');
  console.log('  verify <id> --replay --command \'<JSON argv>\' --artifact <a>    execute & capture stdout');
}

Object.assign(module.exports, {
  truthNextId,
  truthFind,
  appendTruthReceipt,
  cmdTruth,
  TRUTH_RECEIPTS_PATH,
});   // assignment (not reassignment): sibling modules hold live references to this export
