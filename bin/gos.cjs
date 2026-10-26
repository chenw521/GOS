#!/usr/bin/env node
/**
 * GOS — Get Organized System CLI
 *
 * Zero-dependency Node CLI. The hard-gate layer of GOS:
 * weak models physically cannot skip these checks (exit 1).
 *
 * Commands (<= 9, zero-memorization design):
 *   gos              no args = status + what's next
 *   gos next         guided: what to do right now
 *   gos status       full 3-layer status (project/phase/task)
 *   gos init         init a task (or --project for Lv4 project)
 *   gos gate         hard gates: coverage|truths|requirements|all
 *   gos commit       atomic per-stage commit
 *   gos archive      archive current phase artifacts
 *   gos resume       print resume summary for a fresh session
 *   gos help
 *
 * Also (setup layer):
 *   gos setup        install skills symlinks for detected platforms
 *   gos teardown     remove skill symlinks
 */

'use strict';

const core = require('./lib/core/index.cjs');
const knowledge = require('./lib/knowledge/index.cjs');
const map = require('./lib/map/index.cjs');
const task = require('./lib/task/index.cjs');
const nav = require('./lib/nav/index.cjs');
const render = require('./lib/render/index.cjs');
const ops = require('./lib/ops/index.cjs');

const fs = require('fs');
const path = require('path');

// ---------- helpers ----------

// ---------- T1: atomic write + schema validation + migration (D-01/18/19) ----------

// ops.registeredPaths(): whitelist structure for gate orphan-detection (T6) —
// { files: [abs exact-match], dirs: [abs prefix-match] }.

// ---------- Phase W (T6, D-12/R-06): orphan detection ----------
// Walk .gos/ tree; a FILE is an orphan when it is neither registry-exact nor inside a
// registry dir-zone, and not in an exempt zone (archive/ history, active task/<id>/,
// renderers/ user zone, .ship-staging/) nor transient (*.tmp*, *.lock).

// task.archiveSlugParts(state): {date, slug} for archive dir naming (T4 extracted from
// cmdArchive so context SHIP can PREVIEW the same destination — single source).

// ---------- Phase W (T3): gos paths — registry query (JSON, abs paths) +
// README auto-generation (--markdown, deterministic: no timestamps — regen diff
// must be empty, R-03 gate check consumes this). ----------

// ---------- Phase C (T1, D-14): COMMANDS registry — single source of truth for
// command discovery (gos help renders from here; T3 self-check + T29 assert against
// it). Entry types: normal (full fields) / sentinel '(no command)' (aliasOf delegate,
// aliases:[''] — name is display-only, contributes aliases ONLY to switchUniverse) /
// flagOnly (flag-shaped case host, no usage/subs/next). class mirrors the :3303
// ternary classification result. desc is ENGLISH-only (D-16/R3-F3); CJK belongs to
// render layer. next is NON-CONTRACTUAL static navigation (R3-F2) — makes no
// same-source claim against runtime Next: chains. flags: {name, scope, effect, risk}
// where risk is 'destructive'|'mutating'|'safe' (R1-F4). core:true = user-adjudicated
// D-20 core set (exactly 10, feeds doc shortlists). This table mirrors main()'s
// switch — same file, same PR (D-14). ----------
const NO_CMD_KEY = core.NO_CMD_KEY;
const COMMANDS = core.COMMANDS;   // registry truth lives in core/state (EXTRACTORS in map/engine consume it); entry keeps the switch/dispatch face
// switchUniverse normalization (R2-F1): flagOnly and sentinel entries contribute
// ONLY their aliases; the sentinel name is a display key. Canonical formula —
// runtime self-check (T3) and T29-2 source self-parse both anchor here.
// Sub-class overrides — REGISTRY METADATA ONLY.
// Dispatch consumption is limited to replacing the lessons inline special-case
// below; 'concerns' deliberately STAYS read-class at dispatch level (repo-level,
// not task-level — no state anchoring; mutating subs acquire .gos/.lock
// themselves, [R2-F9] design intent preserved, zero behavior change).
// Phase C (T3): nav.KNOWN_CASES hoisted to module level (was local to main) —
// verifyCommandRegistry needs it, and T29-2 source self-parse greps it from
// anywhere. Dispatch self-check below is unchanged.
// Phase C (T3, D-17): registry self-check — six structural assertions, single
// die exit (state_semantics.commandRegistrySelfCheck). Placement iron rule
// (R1-F9): pure in-memory constant comparison, called BEFORE guardCwd —
// integrity checks precede ALL filesystem side effects (mkdir .gos / lock /
// lazy re-anchor state writes).

// ---------- Phase B (T2): evidence three-element object validator [D-30] ----------
// ONE validator, multiple consumers: validateState (fail path → gate truths / write-class
// commands all fail-closed here) and cmdCommit VERIFY. T4 CONSUMPTION POINT [R4-F14]:
// `gos truth verify` must call validateEvidenceObject(ev, repoRoot) DIRECTLY — never
// re-implement this logic. Catches hand-edited state: legacy string form, fake excerpt
// (feature-regex miss), oversized fields, missing/traversing artifact_path.

// ---------- T7: renderer — project.json → three GENERATED views (D-04/05/12) ----------

// `--replay` = argv JSON actually executed via execFileSync, excerpt taken from REAL
// stdout (feature ②count/③path only — synthetic exit-code ① never counts [R2-6]),
// receipt appended to .gos/truth-receipts.md (single O_APPEND appendFileSync, B-20).
// All truth subcommands are write-class: lock held from guardCwd through writeState.

// ---------- Phase 6 (defect-6): dependency map — scanner core + deps.json cache ----------
// D-35/D-36/D-39 + red-team R1-F1/F4/F7/F8/F9, R2-F3/F11/F12/F13, R3-F7, plan W1-T1.
// deps.json is a MACHINE cache: self-anchored (self_sha256), atomically written,
// untracked (R3-F5 gitignore), NEVER read by gate (D-36 amended: gate recomputes
// in memory, T3). `map` is READ-class for guardCwd on purpose: it never touches
// state.json/project.json; deps.json concurrency is atomic-rename last-writer-wins
// (the .gos/.lock protects state serialization, not this cache) [R4-F2].

// ---------- concerns curation layer — command family + hash companion anchors + gap write-back ----------
// D-41 + R1-F5 + R2-F8/F9/F10 + R3-F1/F2. Sidecar {.concerns-anchors.json} + .bak shadow;
// line hashes are CR-stripped (CRLF checkout immune); WHOLE-FILE atomic rewrite (never
// append — the append+sidecar crash window dies with it); ALL write paths (add/prune +
// stage back write-back) share one sanitized entry point; anchor mismatch → exit 1,
// no rebase laundering (recovery = git checkout / .bak).

// ---------- main ----------

// Write-class commands (T5 will replace with full dispatch table incl. new families)
// Exec-class: runs user scripts (gate). Global: project-independent commands.
// Read-class: known read-only commands. Unknown/unregistered → default WRITE (deny-by-default).
// Phase C (T3): 'stage' was in BOTH nav.WRITE_CMDS and nav.READ_CMDS — the :3303 ternary
// resolves WRITE first, so runtime behavior was already write-class. Removed from
// nav.READ_CMDS only (classification sets now partition exactly — self-check #2 asserts).

// ---------- T5: concurrency lock + cwd guard (D-06/10/17) ----------

process.on('exit', core.releaseLock);

function main() {
  const argv = process.argv.slice(2);
  const breakLock = argv.includes('--break-lock');
  core.setBreakLock(breakLock);   // [Phase D T2] pass-through for subcommand-level locks (map edge)
  const cleanArgs = argv.filter(a => a !== '--break-lock');
  const [cmd, ...args] = cleanArgs;
  const cname = (cmd || '').toLowerCase();
  // Phase C (T3, R1-F9 placement iron rule): registry integrity check BEFORE any
  // filesystem side effect (guardCwd below mkdirs .gos and takes the lock).
  nav.verifyCommandRegistry();
  // REVIEW F-8 (D-06): known reads → read; unknown/unregistered → WRITE (deny-by-default)
  let cls = nav.WRITE_CMDS.has(cname) ? 'write' : nav.EXEC_CMDS.has(cname) ? 'exec' : nav.GLOBAL_CMDS.has(cname) ? 'global' : nav.READ_CMDS.has(cname) ? 'read' : 'write';
  if (cname === 'lessons') { const sc = nav.subclassOf(cname, (args[0] || 'list').toLowerCase()); if (sc) cls = sc; } // B-19: lessons list = read-class
  // 'concerns' stays read-class for guardCwd (repo-level, not task-level — no state
  // anchoring), but mutating subcommands acquire the .gos/.lock themselves [R2-F9].
  // (Phase C/T3: concerns.* overrides in nav.SUBCLASS_OVERRIDES are registry metadata
  // only — dispatch deliberately does NOT consume them; zero behavior change.)
  core.readState._mode = (cls === 'write' || cls === 'exec') ? 'write' : 'read';
  core.guardCwd(cls, cname, breakLock); // D-06/17: lock + anchor + banner (order matters: lock before state ops)
  // D-01: write-class loads project.json too — fail-closed validation applies to both stores
  if ((cls === 'write' || cls === 'exec') && fs.existsSync(path.join(core.PROJECT_DIR, 'project.json'))) {
    core.loadProject();
  }
  // REVIEW F-8 (D-06): dispatch self-check — every switch case must be classified in one of the 4 sets
  for (const c of nav.KNOWN_CASES) {
    if (!nav.WRITE_CMDS.has(c) && !nav.EXEC_CMDS.has(c) && !nav.GLOBAL_CMDS.has(c) && !nav.READ_CMDS.has(c)) {
      core.die(`dispatch self-check failed: command "${c}" unclassified — add to WRITE/EXEC/GLOBAL/READ set (deny-by-default requires explicit classification).`);
    }
  }
  switch (cname) {
    case '': nav.cmdStatus(); break;
    case 'next': nav.cmdNext(); break;
    case 'instructions': nav.cmdInstructions(args); break;
    case 'status': nav.cmdStatus(); break;
    case 'init': task.cmdInit(args); break;
    case 'resume': nav.cmdResume(); break;
    case 'stage': task.cmdStage(args); break;
    case 'context': task.cmdContext(args); break;
    case 'checkpoint': task.cmdCheckpoint(args); break;
    case 'commit': task.cmdCommit(args); break;
    case 'archive': task.cmdArchive(); break;
    case 'setup': ops.cmdSetup(args); break;
    case 'teardown': ops.cmdTeardown(); break;
    case 'doctor': ops.cmdDoctor(); break;
    case 'brownfield': ops.cmdBrownfield(args); break;
    case '_contract': map.cmdContract(args); break;
    case 'paths': ops.cmdPaths(args); break;
    case 'gate': ops.cmdGate(args); break;
    case 'section': ops.cmdSection(args); break;
    case 'resolve-model': ops.cmdResolveModel(args); break;
    case 'config': ops.cmdConfig(args); break;
    case 'trace': nav.cmdTrace(args); break;
    case 'decision': knowledge.cmdDecision(args); break;
    case 'requirement': knowledge.cmdRequirement(args); break;
    case 'phase': knowledge.cmdPhase(args); break;
    case 'anchor': map.cmdAnchor(args); break;
    case 'lessons': knowledge.cmdLessons(args); break;
    case 'gap': nav.cmdGap(args); break;
    case 'truth': knowledge.cmdTruth(args); break;
    case 'logs': ops.cmdLogs(args); break; // R-35/D-02: runtime ledger view (READ-class)
    case 'map': map.cmdMap(args); break;
    case 'concerns': knowledge.cmdConcerns(args); break;
    case 'changelog': task.cmdChangelog(args); break;
    case 'feedback': ops.cmdFeedback(args); break;
    case 'push': ops.cmdPush(args); break;
    case 'track': ops.cmdTrack(args); break;
    case 'render': render.cmdRender(args); break; // T8/D-03: --force bypasses the manifest refusal
    case 'auto': nav.cmdAuto(args); break;
    case 'approve': nav.cmdApprove(args); break;
    case 'help': case '--help': case '-h': nav.cmdHelp(args); break;
    case '--version': case '-v': { let v = 'unknown'; try { v = core.PKG.version || 'unknown'; } catch { /* REVIEW-F11 */ } console.log(v); break; }
    default: core.die(`Unknown command "${cmd}". Try \`gos help\`.`);
  }
}

// ---------- D-11: model staffing system (team/solo/elite/lean) ----------

// Semantic tiers per agent per staffing profile (single source of truth).
// Tiers: strong / current / fast / different / inherit
// 'different' = a model DIFFERENT from the session model (heterogeneous cross-check, GOS-original)

// Semantic tier -> actual model resolution.
// 'inherit' returns the literal 'inherit' (caller must OMIT model param, GSD rule).
// 'current' also maps to 'inherit' (session model = current model).
// 'strong'/'fast' probe opencode config; probe failure -> fallback inherit + hint.
// 'different' picks a probed model that differs from session model; failure -> inherit.

// Probe available models from opencode config (heuristic classification).

// ---------- stage-gate approvals (user-act-only, same principle as intent.confirmed) ----------

// ---------- trace: cross-phase requirement traceability (Lv4 gap fix) ----------

// ---------- T3 (W2): decision command family — add/amend/cover/list/import ----------
// Covers D-02 (conclusion-level shape + anchor whitelist), D-03, D-09 (merge semantics),
// D-11 (argv charset + id space cap), D-19 (cover validation + P:n:T format),
// D-20 (dual-store write), D-22 (brownfield import)

// ---------- tiered auto mode (flagship+large: pass routine gates, hold decision gates) ----------

// Fluid workflow support (OpenSpec DNA): allow going back to earlier stages

// ---------- Phase B (T5): semantic engine [D-31/D-33, B-2/B-4/B-5/B-6] ----------
// Gate semantic checks for the minimal commands; 'gate all' chains them and commit
// embeds them — both reuse the functions in this section.
// git invocations always go through execFileSync argv (repo rule; the diffInvocations
// spec pins the flags).

// T5 runtime strings. NOT a CONTRACTS entry: T9 pins the exact top-level CONTRACTS
// key set and the semantic_checks 15-key table is frozen — new user-visible strings
// live here as a module const. Every degradation line keeps the word 'skip'.
// REVIEW #9: runtime banner texts are user-visible → they live IN the frozen contract
// table (single source of truth, tests assert from here via `gos _contract`). Merged
// into CONTRACTS.semantic_checks at load; SEMANTIC_RUNTIME stays as the local handle.
// SEMANTIC_RUNTIME_BASE merge lives in ops/config.cjs (executed at load time).
// Covers R-NN ⊆ state.requirements ids (one-way).

// B-5 allowlist: defaults + state.semantic.allowlist[] extras (defensive read)
// + verified-truth evidence.artifact_path exact-exempt. Load-time strength check:
// bare ** / * / /* → exit 1 (fail-closed). '.gos/gates.json' + '.gos/gates/**' are
// HARD-EXCLUDED from '.gos/**' (gate-config changes must be declared in Files).

// B-4 diff baseline shas: task_head + every task_head_history row (append-only —
// diff scope = union of all segments; re-claiming never launders it).

// ② B-6 diffHitCheck — closureFn interface slot (reserved for the defect-6 impact closure):
// closureFn=null → direct mode (declared-Files literal membership). Once the impact
// closure lands, a (file, task) => closureReachable predicate upgrades direct hits to
// closure hits — initially null.

// ② B-4 diff phase: degradation ladder first (skip banner / FAIL), then diff set +
// diffHitCheck. Prints its own ✓/⚠ lines; returns {failures, pass}.

// D-01b: exit guard — every Fix line must match this whitelist or be suppressed (fail-closed, exit 2).

main();
