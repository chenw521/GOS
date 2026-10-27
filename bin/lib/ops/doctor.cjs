// ops/doctor — placement per aspect-rosters-v2.json
'use strict';

const core = require('../core/index.cjs');
const sibPaths = require('./paths.cjs');
const navHelp = require('../nav/help.cjs');       // direct aspect require (acyclic)
const navRegistry = require('../nav/registry.cjs');  // direct aspect require (acyclic)
const sibSetup = require('./setup.cjs');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

// Top-level dirs exempt from the orphan check (regenerated / staging surfaces).
const ORPHAN_EXEMPT_TOP = new Set(['archive', 'renderers', '.ship-staging']);

const ORPHAN_TRANSIENT_RE = /(^|\/)([^/]*\.tmp[^/]*|[^/]*\.lock)$/;

const DOCTOR_FIXES = Object.freeze({
  no_platform: 'gos setup',
  skills_missing: 'reinstall GOS (npm i -g) or git pull, then gos setup',
  link_missing: 'gos setup',
  link_broken: 'gos teardown && gos setup',
  link_drifted: 'gos teardown && gos setup --local <repo-path>',
  lock_gitignore: 'echo ".gos/.lock" >> .gitignore',
  unknown: `report issue at ${repoIssuesUrl()} with doctor output (your .gos/ task state is never affected by reinstall)`,
});

const DOCTOR_FIX_RE = /^(gos setup|echo "\.gos\/\.lock" >> \.gitignore|gos teardown && gos setup( --local <repo-path>)?|reinstall GOS \(npm i -g\) or git pull, then gos setup|report issue at \S+ with doctor output \(your \.gos\/ task state is never affected by reinstall\))$/;

function detectOrphans(state) {
  const wl = sibPaths.registeredPaths();
  const wlFiles = new Set(wl.files.map((p) => path.relative(core.GOS_DIR, p)));
  const wlDirs = wl.dirs.map((p) => path.relative(core.GOS_DIR, p));
  const tid = core.currentTaskId(state);
  const out = [];
  const walk = (dir) => {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      const full = path.join(dir, e.name);
      const rel = path.relative(core.GOS_DIR, full);
      if (e.isDirectory()) {
        if (ORPHAN_EXEMPT_TOP.has(e.name) && path.dirname(rel) === '.') continue; // top-level exempt zones
        if (tid != null && rel === path.join('task', tid)) continue; // active task free zone
        walk(full);
      } else {
        if (ORPHAN_TRANSIENT_RE.test(rel)) continue;
        if (wlFiles.has(rel)) continue;
        if (wlDirs.some((d) => (rel + path.sep).startsWith(d + path.sep))) continue;
        out.push(rel);
      }
    }
  };
  walk(core.GOS_DIR);
  return out.sort();
}

function orphanAdvisoryLine(n) {
  const t = core.CONTRACTS.gate_verdicts.orphanAdvisory;
  return n === 1 ? core.CONTRACTS.gate_verdicts.orphanAdvisoryOne : t.split('<N>').join(String(n));
}

function repoIssuesUrl() {
  try {
    const r = core.PKG.repository;
    const url = typeof r === 'string' ? r : (r && r.url);
    if (!url) return 'GOS repository issues page';
    return url.replace(/^git\+/, '').replace(/^github:/, 'https://github.com/').replace(/\.git$/, '') + '/issues';
  } catch { return 'GOS repository issues page'; }
}

function cmdDoctor() {
  let pkg = null;
  try { pkg = core.PKG; } catch { /* REVIEW-F10: broken install — diagnose, don't crash */ }
  const warnings = [];
  let guardFailed = false;
  const warn = (msg) => { warnings.push(msg); console.log(`  ⚠ ${msg}`); };
  const fix = (key) => {
    const cmd = DOCTOR_FIXES[key];
    if (!cmd || !DOCTOR_FIX_RE.test(cmd)) { guardFailed = true; return; } // fail-closed: print nothing risky
    console.log(`  Fix: \`${cmd}\``);
  };

  console.log('GOS doctor — installation diagnostics (read-only)\n');

 // /F8: effective locale + source — visible in diagnostics so a wrong
  // language is explainable without guessing which config won.
  {
    const eff = core.effectiveLocale();
    console.log(`  locale: ${eff.locale} (source: ${eff.source})`);
  }

  // [C-1] Phase C (T4, R3-F4): help --json envelope self-check — strict JSON,
  // version consistency, schema floor (machine consumers rely on this contract).
  try {
    const env = navHelp.helpEnvelope();
    const ver = (pkg && pkg.version) || 'unknown';
    const ok = typeof env.gos_version === 'string' && typeof env.schema_version === 'number'
      && env.schema_version >= 1 && env.commands && navRegistry.switchUniverse(env.commands).size > 0
      && navRegistry.switchUniverse(env.commands).size === navRegistry.switchUniverse(core.COMMANDS).size
      && (env.gos_version === ver || env.gos_version === 'unknown');
    if (ok) console.log(`  ✓ OK: help --json envelope (schema_version ${env.schema_version}, gos_version ${env.gos_version})`);
    else warn('help --json envelope malformed (schema_version/gos_version/commands mismatch)');
  } catch (e) { warn(`help --json envelope construction failed: ${e.message}`); }

 // [0] Repo hygiene (REVIEW ): .gos/.lock must be gitignored (machine-local pid file)
  // only checked when a lock file actually exists in this repo (avoids noise in fresh clones)
  const repoRoot = (() => { try { return execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8', stdio: ['ignore','pipe','ignore'] }).trim(); } catch { return null; } })();
  if (repoRoot && fs.existsSync(path.join(repoRoot, '.gos', '.lock'))) {
 // the ignore verdict goes through gitprobe's
    // ignoredSet() (its truth source collapses covered directories to a
    // single trailing-slash entry, so a wholesale `.gos/` rule counts too —
    // the same recursive verdict the retired one-shot probe gave). Any git
    // failure yields an empty set → not-ignored → warn + fix, the exact
    // direction the old catch → false took.
    const ign = core.ignoredSet();
    const lockIgn = '.gos/.lock';
    const ignored = ign.has(lockIgn) || ign.has(lockIgn + '/')
      || [...ign].some((e) => e.endsWith('/') && (lockIgn + '/').startsWith(e));
    if (!ignored) { warn('MISSING: .gos/.lock not gitignored — add ".gos/.lock" to .gitignore (concurrency lock is machine-local)'); fix('lock_gitignore'); }
    else console.log('  ✓ OK: .gos/.lock gitignored');
  }
 // [0b] : lessons sidecar must be in git index once it exists (tracked → deletable/recoverable)
  if (repoRoot && fs.existsSync(path.join(repoRoot, '.gos', core.GOS_PATHS.lessons_anchors.rel))) {
 // trackedness goes through gitprobe's isTracked
    // (index UNION HEAD blob). Fail-closed: any git failure reports tracked —
    // strictly more conservative than the old one-shot probe's catch → false.
    const inIndex = core.isTracked('.gos/cache/.lessons-anchors.json');
    if (!inIndex) warn('MISSING: .gos/.lessons-anchors.json not in git index — run `git add .gos/.lessons-anchors.json` (deletion detection requires tracking)');
    else console.log('  ✓ OK: lessons sidecar tracked in git index');
  }

  // [1] CLI environment (C1 — informational)
  console.log('[1] CLI environment');
  console.log(`  ✓ OK: node ${process.version}`);
  console.log(`  ✓ OK: GOS v${pkg.version}`);
  const installMode = core.GOS_SELF_ROOT.split(path.sep).includes('node_modules') ? 'npm package' : 'local clone';
  console.log(`  ✓ OK: installation mode: ${installMode} (${core.GOS_SELF_ROOT})`);
  // npm package mode: skills live INSIDE the installed package (self-contained).
  // Drift-check compares against this package's own skills dir, which is correct here.

  // [2] Skills source (C2)
  console.log(`\n[2] Skills source (${core.SKILLS_DIR})`);
  const srcDirs = fs.existsSync(core.SKILLS_DIR) ? fs.readdirSync(core.SKILLS_DIR).filter(d => { try { return fs.statSync(path.join(core.SKILLS_DIR, d)).isDirectory(); } catch { return false; } }) : [];
  const incomplete = srcDirs.filter(d => !fs.existsSync(path.join(core.SKILLS_DIR, d, 'SKILL.md')));
  if (!srcDirs.length) {
    warn('MISSING: skills source directory is empty or absent');
    fix('skills_missing');
  } else if (incomplete.length) {
    warn(`MISSING: ${incomplete.length} skill dir(s) lack SKILL.md: ${incomplete.join(', ')}`);
    fix('skills_missing');
  } else {
    console.log(`  ✓ OK: ${srcDirs.length} skill(s) with SKILL.md`);
  }

  // [3] Platform detection (C3)
  console.log('\n[3] Platform detection');
  const platforms = sibSetup.detectPlatforms(os.homedir());
  if (!platforms.length) {
    warn('MISSING: no supported AI assistant detected (opencode/codex/claude)');
    fix('no_platform');
  } else {
    for (const p of platforms) console.log(`  ✓ OK: ${p.name} detected`);
  }

  // [4] Skills links (C4) — exists → is symlink → target resolves → points at current source
  console.log('\n[4] Skills links');
  if (!platforms.length) {
    console.log('  (skipped — no platform detected)');
  } else {
    let skillsReal = null;
    try { skillsReal = fs.realpathSync(core.SKILLS_DIR); } catch { /* source missing, already warned */ }
    const checkLink = (label, linkPath, expectPath) => {
      const expected = expectPath ? (() => { try { return fs.realpathSync(expectPath); } catch { return expectPath; } })() : skillsReal;
      let st;
      try { st = fs.lstatSync(linkPath); } catch {
        warn(`MISSING: ${label} (not linked — run setup to create it)`);
        fix('link_missing');
        return;
      }
      if (!st.isSymbolicLink()) {
        warn(`BROKEN: ${label} — exists but is not a GOS-managed symlink (left untouched)`);
        fix('unknown');
        return;
      }
      let real;
      try { real = fs.realpathSync(linkPath); } catch {
        warn(`BROKEN: ${label} — dangling symlink (target no longer exists)`);
        fix('link_broken');
        return;
      }
      if (expected && real !== expected) {
        warn(`BROKEN: ${label} — drifted: points to ${real}, expected ${expected}`);
        fix('link_drifted');
        return;
      }
      console.log(`  ✓ OK: ${label}`);
    };
    for (const p of platforms) {
      // commands layer: advisory only (appendix of the opencode platform, not standalone)
      if (p.source === 'commands') continue;
      if (p.shape === 'parent') checkLink(`${p.name}: skills/gos (${p.link})`, p.link);
      else for (const s of sibSetup.GOS_SKILL_NAMES) checkLink(`${p.name}: skills/${s}`, path.join(p.linkDir, s), path.join(core.SKILLS_DIR, s)); // individual links expect skills/<name>, not skills/
    }
  }

  // [5] Custom gates discoverability
  const gjPath2 = path.join(core.GOS_DIR, 'gates.json');
  const gDir2 = path.join(core.GOS_DIR, 'gates');
  const hasGj2 = fs.existsSync(gjPath2);
  const gScripts2 = fs.existsSync(gDir2) ? fs.readdirSync(gDir2).filter(f => /\.(sh|js|cjs)$/.test(f)) : [];
  console.log('\n[5] Custom gates');
  if (hasGj2 || gScripts2.length) {
    if (hasGj2) console.log('  ✓ gates.json detected (protect/lint/forbid active)');
    for (const s of gScripts2) console.log('  ✓ gates/' + s + ' (runs in gos gate all)');
  } else {
    console.log('  (none — add .gos/gates.json rules or .gos/gates/*.sh scripts; see gos-help-gate)');
    console.log('   built-in cleanup/security still run at ship stage)');
  }

 // Summary (explicit machine-readable verdict)
  console.log('');
  if (guardFailed) {
    console.error('✗ internal error: a fix directive failed the safety whitelist and was suppressed.');
    process.exitCode = 2;
    return;
  }
  if (warnings.length) {
    console.log(`RESULT: ISSUES FOUND (${warnings.length} warning${warnings.length > 1 ? 's' : ''}) — exit code 1 (diagnostic only, not a crash)`);
    process.exitCode = 1;
  } else {
    console.log('RESULT: HEALTHY (0 warnings) — exit code 0');
    console.log('exit code meaning: 0 = healthy, 1 = issues found, 2 = internal error (none is a crash)');
  }
}

module.exports = { DOCTOR_FIXES, DOCTOR_FIX_RE, ORPHAN_EXEMPT_TOP, ORPHAN_TRANSIENT_RE, detectOrphans, orphanAdvisoryLine, repoIssuesUrl, cmdDoctor };
