// knowledge/lessons.cjs — lessons command family (json truth era).
// Truth = lessons.json {schema_version, entries[], audit[], chain_head} (tracked);
// lessons.md = regenerated view; sidecar = derived {live_ids} cache.
// Command family: add/rm/amend/list/prune/skip/anchor-rebuild/migrate.
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const core = require('../core/index.cjs');
const j = require('./lessons-json.cjs');

function todayYmd() { return new Date().toISOString().slice(0, 10); }

function dieFailures(ctx, failures) {
  // Failures are gateFail objects — render the 3-part block, not [object Object].
  for (const f of failures) {
    if (typeof f === 'string') { console.error(`✗ ${ctx}: ${f}`); continue; }
    console.error(`✗ ${ctx}: ${f.code}: ${f.verdict}`);
    for (const e of f.evidence || []) console.error(`    evidence: ${e}`);
    console.error(`    fix: ${f.fix}`);
  }
  process.exit(1);
}

function assertTruthWritable(P) {
  for (const p of [P.truth, P.file]) {
    if (fs.existsSync(p)) {
      const st = fs.lstatSync(p);
      if (!st.isFile()) core.die(`lessons ${P.global ? 'global' : 'project'}: ${path.basename(p)} is not a regular file (symlink?) — write refused (B-18)`);
    }
  }
}

// Adjudicating load inside a mutation: ensureMigrated + full verification.
// Channels can be narrowed (anchor-rebuild is the sanctioned recovery for the
// sidecar channel, so it must not die on it).
function loadOrDie(P, ctx, opts = {}) {
  const res = j.loadStore(P, opts);
  if (res.status === 'corrupt') dieFailures(ctx, res.failures);
  if (res.status === 'missing') {
    // ensureMigrated guarantees existence — reaching here means it refused (die above)
    core.die(`lessons ${ctx}: lessons.json missing and migration refused — see messages above`);
  }
  if (res.failures.length) dieFailures(ctx, res.failures);
  return res.store;
}

function withSide(P, ctx, fn, opts = {}) {
  const run = () => {
    if (P.global) assertTruthWritable(P);
    j.ensureMigrated(P);
    fn();
  };
  if (P.global) return core.withGlobalAnchorsLock(run);
  core.acquireLock(); // reentrant — CLI dispatch already holds .gos/.lock for write-class
  return run();
}

function parseTags(raw) {
  if (raw == null) return null;
  const parts = String(raw).split(',').map((t) => t.trim()).filter((t) => t !== '');
  for (const t of parts) {
    if (/[|,\n\r]/.test(t)) core.die(`lessons: tag '${t}' contains reserved character (| , newline)`);
    const c = core.checkInputConstraint({ value: t, maxCp: 50, label: 'tag' });
    if (!c.ok) core.die(`lessons: ${c.reason}`);
  }
  return parts;
}

function sanitize(label, value, maxCp) {
  const bt = core.badText(value == null ? '' : value);
  if (bt) core.die(`lessons ${label}: rejected: ${bt}`);
  const c = core.checkInputConstraint({ value: value == null ? '' : value, maxCp, label, noNewlineListPrefix: true });
  if (!c.ok) core.die(`lessons ${label}: ${c.reason}`);
  return c.value;
}

function isPermanentEntry(e) {
  return e.permanent === true || /\[permanent\]/.test(e.text || '') || String(e.text || '').includes('\u6c38\u4e45\u6559\u8bad'); // legacy zh "permanent lesson" marker
}

function resolveByPrefix(store, prefix, cmd) {
  if (!prefix || !/^[0-9a-f]+$/.test(prefix) || prefix.length < 4) {
    core.die(`lessons ${cmd}: give an entry id prefix (≥4 hex chars) — see \`gos lessons list\` for ids`);
  }
  const hits = store.entries.filter((e) => e.id.startsWith(prefix));
  if (!hits.length) core.die(`lessons ${cmd}: no entry matches prefix '${prefix}' — see \`gos lessons list\``);
  if (hits.length > 1) {
    console.error(`✗ lessons ${cmd}: prefix '${prefix}' is ambiguous — ${hits.length} candidates:`);
    for (const h of hits) console.error(`    ${h.id}${h.salt ? ' (salted)' : ''} ${h.at} ${String(h.lesson || h.text || '').slice(0, 60)}`);
    process.exit(1);
  }
  return hits[0];
}

function expiryFor(type, expires) {
  if (expires != null) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(expires)) core.die('lessons add: --expires must be YYYY-MM-DD [R1-F9]');
    const d = new Date(expires + 'T00:00:00');
    const t0 = new Date(); t0.setHours(0, 0, 0, 0);
    if (Number.isNaN(d.getTime()) || d < t0) core.die(`lessons add: --expires ${expires} is before today [R1-F9]`);
    return expires;
  }
  if (type === 'model') {
    const d = new Date(); d.setDate(d.getDate() + 90); // model lessons auto-expire after +90d
    return d.toISOString().slice(0, 10);
  }
  return null;
}

// Migration is a mutation — both sides serialize through their locks even when
// auto-triggered from a read-shaped command (list).
function ensureMigratedLocked(P) {
  if (P.global) return core.withGlobalAnchorsLock(() => j.ensureMigrated(P, { quiet: true }));
  core.acquireLock(); // reentrant under the dispatch-level write lock
  return j.ensureMigrated(P, { quiet: true });
}

function cmdLessons(args) {
  const sub = (args[0] || 'list').toLowerCase();
  const rest = args.slice(1);

  if (sub === 'add') {
    let type = null, scene = null, lesson = null, text = null, tagsRaw = null, expires = null, permanent = false;
    for (let i = 0; i < rest.length; i++) {
      const a = rest[i];
      if (a === '--type') type = rest[++i];
      else if (a === '--scene') scene = rest[++i];
      else if (a === '--lesson') lesson = rest[++i];
      else if (a === '--text') text = rest[++i];
      else if (a === '--tags') tagsRaw = rest[++i];
      else if (a === '--expires') expires = rest[++i];
      else if (a === '--permanent') permanent = true;
      else core.die(`lessons add: unknown argument '${a}'`);
    }
    if (type !== 'model' && type !== 'project') core.die(`lessons add: --type must be model|project (got '${type}') [R1-F9]`);
    if (scene != null) scene = sanitize('--scene', scene, 200);
    if (lesson != null) lesson = sanitize('--lesson', lesson, 500);
    if (text != null) text = sanitize('--text', text, 500);
    const tags = parseTags(tagsRaw) || [];
    if (text == null && lesson == null) core.die('lessons add: --lesson "<what was learned>" is required (or legacy --text shorthand)');
    const exp = expiryFor(type, expires);
    const P = core.lessonsPaths(type);
    withSide(P, 'add', () => {
      const store = loadOrDie(P, 'add');
      const entry = {
        at: todayYmd(),
        type,
        ...(scene != null ? { scene } : {}),
        ...(text != null ? { text } : {}),
        ...(lesson != null ? { lesson } : {}),
        tags,
        ...(exp ? { expires: exp } : {}),
        ...(permanent ? { permanent: true } : {}),
        origin: 'v2',
      };
      const errs = [...j.validateEntryFields(entry), ...j.v2TextReservedViolations(entry)];
      if (errs.length) core.die(`lessons add: ${errs.join('; ')}`);
      const ids = new Set(store.entries.map((e) => e.id));
      const { id, salt } = j.mintId(entry, (cand) => ids.has(cand));
      const full = { id, ...entry, ...(salt != null ? { salt } : {}) };
      store.entries.push(full);
      j.appendAuditRow(store, 'add', `add ${type} lesson${scene ? ` (${scene})` : ''}`, { new_id: id });
      j.saveStore(P, store);
    });
    if (type === 'model') console.log(`⚠ ${core.CONTRACTS.semantic_checks.globalWriteHint}`);
    if (text != null && lesson == null) {
      console.log('⚠ --text stored as unstructured text — structured fields (--scene/--lesson/--tags) group and surface lessons better');
    }
    console.log(`✓ lesson recorded (${type})`);
    return;
  }

  if (sub === 'rm') {
    const prefix = rest.find((a) => !a.startsWith('--'));
    let reason = null;
    const force = rest.includes('--force');
    for (let i = 0; i < rest.length; i++) if (rest[i] === '--reason') reason = rest[++i];
    if (reason == null || reason === '') core.die('lessons rm: --reason "<why this entry is disposed>" is mandatory (audit trail)');
    reason = sanitize('--reason', reason, 200);
    const P = core.lessonsPaths('project');
    if (rest.includes('--type')) core.die('lessons rm: per-entry commands are project-side only (global lessons are model-type by definition)');
    withSide(P, 'rm', () => {
      const store = loadOrDie(P, 'rm');
      const entry = resolveByPrefix(store, prefix, 'rm');
      if (isPermanentEntry(entry) && !force) {
        core.die(`lessons rm: entry ${entry.id} is PERMANENT — disposal needs --force:\n    ${String(entry.lesson || entry.text || '').slice(0, 80)}`);
      }
      const prevSha = j.sha16Of(entry);
      store.entries = store.entries.filter((e) => e.id !== entry.id);
      j.appendAuditRow(store, 'rm', reason, { old_id: entry.id, prev_sha: prevSha });
      j.saveStore(P, store);
      console.log(`✓ entry removed (${entry.id.slice(0, 8)}) — disposal audit row recorded`);
    });
    return;
  }

  if (sub === 'amend') {
    const prefix = rest.find((a) => !a.startsWith('--'));
    let scene = null, lesson = null, tagsRaw = null;
    for (let i = 0; i < rest.length; i++) {
      if (rest[i] === '--scene') scene = rest[++i];
      else if (rest[i] === '--lesson') lesson = rest[++i];
      else if (rest[i] === '--tags') tagsRaw = rest[++i];
    }
    if (scene == null && lesson == null && tagsRaw == null) {
      core.die('lessons amend: nothing to amend — pass --scene/--lesson/--tags (structured rewrite)');
    }
    if (scene != null) scene = sanitize('--scene', scene, 200);
    if (lesson != null) lesson = sanitize('--lesson', lesson, 500);
    const tags = parseTags(tagsRaw);
    const P = core.lessonsPaths('project');
    withSide(P, 'amend', () => {
      const store = loadOrDie(P, 'amend');
      const old = resolveByPrefix(store, prefix, 'amend');
      const prevSha = j.sha16Of(old);
      // promotion: origin immutable; providing --lesson retires the prose text
      // (structured rewrite), otherwise legacy text is preserved
      const keepText = lesson != null ? null : old.text;
      const next = {
        at: old.at,
        type: old.type,
        ...(scene != null ? { scene } : old.scene != null ? { scene: old.scene } : {}),
        ...(keepText != null ? { text: keepText } : {}),
        ...(lesson != null ? { lesson } : old.lesson != null ? { lesson: old.lesson } : {}),
        tags: tags != null ? tags : old.tags != null ? old.tags : [],
        ...(old.expires != null ? { expires: old.expires } : {}),
        ...(old.permanent != null ? { permanent: old.permanent } : {}),
        origin: old.origin,
      };
      const errs = [...j.validateEntryFields(next), ...j.v2TextReservedViolations(next)];
      if (errs.length) core.die(`lessons amend: ${errs.join('; ')}`);
      const ids = new Set(store.entries.filter((e) => e.id !== old.id).map((e) => e.id));
      const { id, salt } = j.mintId(next, (cand) => ids.has(cand));
      const full = { id, ...next, ...(salt != null ? { salt } : {}) };
      store.entries = store.entries.filter((e) => e.id !== old.id);
      store.entries.push(full);
      j.appendAuditRow(store, 'edit', `amend ${old.id.slice(0, 8)}→${id.slice(0, 8)}`, { old_id: old.id, new_id: id, prev_sha: prevSha });
      j.saveStore(P, store);
      console.log(`✓ entry amended: ${old.id.slice(0, 8)} → ${id.slice(0, 8)} (origin preserved: ${old.origin}; lineage in audit row)`);
    });
    return;
  }

  if (sub === 'list') {
    const rows = [];
    for (const side of ['project', 'model']) {
      const P = core.lessonsPaths(side);
      const label = P.global ? 'global' : 'project';
      assertTruthWritable(P);
      ensureMigratedLocked(P);
      const res = j.loadStore(P);
      if (res.status === 'corrupt' || res.failures.length) {
        // adjudicating read: fail closed (spec §3.3 load semantics)
        dieFailures('lessons list', res.status === 'corrupt' ? res.failures : res.failures);
      }
      const store = res.store;
      if (!store.entries.length) continue;
      rows.push(`[${label}] ${core.t(`lessons.${side}Label`)}`);
      for (const e of store.entries.slice().sort((a, b) => String(b.at).localeCompare(String(a.at)))) {
        const tags = (e.tags || []).map((t) => `#${t}`).join(' ');
        const coreText = e.text != null && e.text !== '' ? e.text : `${e.scene ? e.scene + ': ' : ''}${e.lesson || ''}`;
        const exp = e.expires ? ` (expires ${e.expires})` : '';
        rows.push(`  (${e.id.slice(0, 8)}) ${e.at} ${tags ? tags + ' ' : ''}— ${coreText}${exp}`);
      }
    }
    if (!rows.length) console.log('- no lessons recorded yet');
    else for (const r of rows) console.log(r);
    return;
  }

  if (sub === 'prune') {
    let type = 'project';
    for (let i = 0; i < rest.length; i++) if (rest[i] === '--type') type = rest[++i];
    if (type !== 'model' && type !== 'project') core.die(`lessons: --type must be model|project (got '${type}') [R1-F9]`);
    const force = rest.includes('--force');
    const P = core.lessonsPaths(type);
    withSide(P, 'prune', () => {
      const store = loadOrDie(P, 'prune');
      const today = new Date();
      const expired = store.entries.filter((e) => e.expires && new Date(e.expires + 'T23:59:59') < today);
      const blocked = expired.filter((e) => isPermanentEntry(e) && !force);
      if (blocked.length) {
        console.error(`✗ lessons prune: ${blocked.length} PERMANENT expired lesson(s) — needs --force:`);
        for (const b of blocked) console.error(`    ${b.id} ${String(b.lesson || b.text || '').slice(0, 60)}...`);
        process.exit(1);
      }
      if (!expired.length) {
        console.log('- nothing to prune (no expired entries)');
        return;
      }
      const ids = expired.map((e) => e.id);
      store.entries = store.entries.filter((e) => !ids.includes(e.id));
      j.appendAuditRow(store, 'prune', `pruned ${ids.length} expired`, { count: ids.length, old_ids: ids });
      j.saveStore(P, store);
      console.log(`✓ pruned ${ids.length} expired (disposal audit row recorded)`);
    });
    return;
  }

  if (sub === 'skip') {
    let reason = null;
    for (let i = 0; i < rest.length; i++) if (rest[i] === '--reason') reason = rest[++i];
    if (reason == null || String(reason).trim() === '') core.die('lessons skip: --reason "<why this residual risk is accepted>" is mandatory');
    reason = sanitize('--reason', reason, 200);
    const P = core.lessonsPaths('project'); // skip is a project-context audit action
    withSide(P, 'skip', () => {
      const store = loadOrDie(P, 'skip');
      j.appendAuditRow(store, 'skip', reason);
      j.saveStore(P, store);
      const count = store.audit.filter((r) => r.what === 'skip').length;
      console.log(`✓ skip recorded (audit row); cumulative skips: ${count}`);
    });
    return;
  }

  if (sub === 'anchor-rebuild') {
    let type = 'project';
    for (let i = 0; i < rest.length; i++) if (rest[i] === '--type') type = rest[++i];
    if (type !== 'model' && type !== 'project') core.die(`lessons: --type must be model|project (got '${type}') [R1-F9]`);
    const force = rest.includes('--force');
    const P = core.lessonsPaths(type);
    withSide(P, 'anchor-rebuild', () => {
      j.ensureMigrated(P);
      // the sidecar channel is what this command recovers from — verify the
      // other channels only (chain/entries/git stay fail-closed here)
      const res = j.loadStore(P, { channels: ['chain', 'entries', 'git'] });
      if (res.status !== 'ok') dieFailures('lessons anchor-rebuild', res.failures);
      const store = res.store;
      const sidecar = j.loadSidecar(P);
      if (sidecar) {
        const entryIds = new Set(store.entries.map((e) => e.id));
        const vanished = sidecar.live_ids.filter((id) => !entryIds.has(id));
        if (vanished.length && !force) {
          console.error(`✗ lessons anchor-rebuild: ${vanished.length} entry id(s) vanished since last sync — disposal needs --force (B-13 anti-bypass):`);
          for (const v of vanished) console.error(`    ${v}`);
          process.exit(1);
        }
        if (vanished.length && force) {
          j.appendAuditRow(store, 'prune', 'forced disposal via anchor-rebuild --force', { old_ids: vanished });
        }
      }
      j.appendAuditRow(store, 'rebuild', 'sidecar re-derived from json truth');
      j.saveStore(P, store);
      console.log(`✓ anchor rebuilt: ${store.entries.length} entries live (derived cache; lessons.json is the truth)`);
    });
    return;
  }

  if (sub === 'migrate') {
    for (const side of ['project', 'model']) {
      const P = core.lessonsPaths(side);
      withSide(P, 'migrate', () => {
        j.ensureMigrated(P);
      });
    }
    return;
  }

  if (sub === 'rebase-anchor') {
    core.die('lessons rebase-anchor was renamed anchor-rebuild (P15 D-64) — run: gos lessons anchor-rebuild [--type model|project] [--force]');
  }

  console.log('Usage: gos lessons <add|rm|amend|list|prune|skip|anchor-rebuild|migrate>');
  console.log('  add --type model|project [--scene "<s>"] --lesson "<l>" [--tags a,b] [--expires YYYY-MM-DD]');
  console.log('  rm <id-prefix> --reason "<why>" [--force]    per-entry disposal (permanent needs --force)');
  console.log('  amend <id-prefix> [--scene ...] [--lesson ...] [--tags ...]   structured rewrite (promotion)');
  console.log('  list [--type model|project]                 grouped view, ids addressable');
  console.log('  prune [--type] [--force]                    batch expired disposal');
  console.log('  skip --reason "<why>"                       F-1 exemption audit row (json chain)');
  console.log('  anchor-rebuild [--type] [--force]           re-derive sidecar from json truth');
  console.log('  migrate                                     explicit md→json migration (auto on first mutation)');
}

module.exports = {
  cmdLessons,
  isPermanentEntry,
  sanitize,
  parseTags,
};
