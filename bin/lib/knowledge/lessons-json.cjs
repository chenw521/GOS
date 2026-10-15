// knowledge/lessons-json.cjs — lessons JSON truth store.
// Canonical serialization + entry id engine (pure — spec §8 normative).
// Truth store + derived sidecar + five invariants (spec §3.3).
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const core = require('../core/index.cjs');

// §8 v2 hash-input field order (FROZEN per schema_version): 9 segments, 8 '|'.
// Absent values emit empty segments; tags comma-joined; id/origin excluded.
const V2_SEGMENTS = ['at', 'type', 'scene', 'text', 'lesson', 'tags', 'expires', 'permanent', 'salt'];

// Per-class shape whitelists (fifth invariant). raw-legacy = migrated verbatim
// entry; v2-shape = new entries AND promoted (amended) legacy entries.
const RAW_LEGACY_FIELDS = new Set(['id', 'at', 'type', 'text', 'expires', 'origin']);
const V2_FIELDS = new Set(['id', 'at', 'type', 'scene', 'text', 'lesson', 'tags', 'expires', 'permanent', 'salt', 'origin']);

const LESSONS_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function canonV2(entry) {
  const e = entry || {};
  const seg = (f) => {
    const v = e[f];
    if (f === 'tags') return Array.isArray(v) ? v.join(',') : '';
    if (v === true) return 'true';
    if (v === false || v == null) return '';
    return String(v);
  };
  return V2_SEGMENTS.map(seg).join('|');
}

// §8 legacy-line reconstruction: `- [<at>] [<type>] <text>` + ` (expires <d>)`.
// Defined only when the entry carries verbatim at/type/text (raw legacy shape).
// Byte-exact against the legacy lessons.md line whose sha16 is the kept id.
function canonLegacy(entry) {
  const e = entry || {};
  if (e.at == null || e.type == null || e.text == null) return null;
  let line = `- [${e.at}] [${e.type}] ${e.text}`;
  if (e.expires != null && e.expires !== '') line += ` (expires ${e.expires})`;
  return line;
}

// Class resolution: raw-legacy (line-hash id) checked FIRST so that a
// promoted-field injection onto a raw entry falls through to the raw shape
// whitelist (invariant 5 catches what invariant 4's legacy form would forgive).
function verifyId(entry) {
  const e = entry || {};
  if (typeof e.id !== 'string' || !/^[0-9a-f]{16}$/.test(e.id)) {
    return { ok: false, cls: null, canonical: null, reason: `id malformed ('${e.id}')` };
  }
  const legacyLine = canonLegacy(e);
  if (legacyLine !== null && e.id === core.sha16(legacyLine)) {
    return { ok: true, cls: 'raw-legacy', canonical: legacyLine };
  }
  const v2 = canonV2(e);
  if (e.id === core.sha16(v2)) {
    return { ok: true, cls: 'v2-shape', canonical: v2 };
  }
  return { ok: false, cls: null, canonical: v2, reason: 'id ≠ sha16(canonical form) — content mutated with preserved id' };
}

// sha16 of the canonical serialization keyed by the entry's verified class
// (legacy reconstruction for raw-legacy; v2 canonical otherwise) — prev_sha source.
function sha16Of(entry) {
  const v = verifyId(entry);
  if (!v.ok) return null;
  return core.sha16(v.canonical);
}

// Mint a v2-canonical id, asserting global uniqueness via the caller-supplied
// membership test. Collision → ordinal salt field + rehash (§8: salt joins the
// canonical string, so salted ids recompute stably; same-text-different-id is
// intended semantics). Returns { id, salt } — salt null when unsalted.
function mintId(entry, hasId) {
  const has = typeof hasId === 'function' ? hasId : () => false;
  for (let n = 0; n < 1000; n++) {
    const salt = n === 0 ? null : String(n);
    const cand = { ...entry };
    if (salt === null) delete cand.salt; else cand.salt = salt;
    const id = core.sha16(canonV2(cand));
    if (!has(id)) return { id, salt };
  }
  throw new Error('lessons mintId: ordinal salt exhausted (1000 collisions) — refusing');
}

// Field-level validation shared by shape whitelist + command input paths.
// v2 canonical segments are pipe-delimited: a pipe or newline inside
// scene/text/lesson would let content shift across field boundaries while the
// id stays valid (invariant 4 bypass). Legacy line-hash entries are exempt —
// their canon is the single reconstructed line, not pipe segments.
function v2TextReservedViolations(entry) {
  const e = entry || {};
  const errs = [];
  for (const f of ['scene', 'text', 'lesson']) {
    if (typeof e[f] === 'string' && /[|\n\r]/.test(e[f])) errs.push(`${f} contains a reserved character (| or newline) — not storable in v2 entries`);
  }
  return errs;
}

function validateEntryFields(entry) {
  const e = entry || {};
  const errs = [];
  if (!LESSONS_DATE_RE.test(String(e.at || ''))) errs.push(`at must be YYYY-MM-DD (got '${e.at}')`);
  if (e.type !== 'project' && e.type !== 'model') errs.push(`type must be model|project (got '${e.type}')`);
  if (e.expires != null && e.expires !== '' && !LESSONS_DATE_RE.test(String(e.expires))) errs.push(`expires must be YYYY-MM-DD (got '${e.expires}')`);
  if (e.tags != null) {
    if (!Array.isArray(e.tags)) errs.push('tags must be an array');
    else {
      for (const t of e.tags) {
        if (typeof t !== 'string' || t === '') { errs.push('tags entries must be non-empty strings'); break; }
        if (/[|,\n\r]/.test(t)) { errs.push(`tag '${t}' contains reserved character (| , newline)`); break; }
      }
    }
  }
  if (e.permanent != null && typeof e.permanent !== 'boolean') errs.push('permanent must be boolean');
  if (e.salt != null && (typeof e.salt !== 'string' || e.salt === '')) errs.push('salt must be a non-empty string');
  if (e.scene != null && typeof e.scene !== 'string') errs.push('scene must be a string');
  if (e.text != null && typeof e.text !== 'string') errs.push('text must be a string');
  if (e.lesson != null && typeof e.lesson !== 'string') errs.push('lesson must be a string');
  return errs;
}

// Fifth invariant: strict per-class shape whitelist. Returns violation strings.
// Class comes from verifyId; origin constraint enforced here (downgrade attack:
// origin 'v2' entry carrying a raw-legacy line-hash = drift; origin immutable).
function shapeViolations(entry, cls) {
  const e = entry || {};
  const errs = [];
  if (cls === 'raw-legacy') {
    if (e.origin !== 'legacy') errs.push(`raw-legacy class requires origin 'legacy' (got '${e.origin}') — downgrade attack (origin immutable)`);
    for (const k of Object.keys(e)) if (!RAW_LEGACY_FIELDS.has(k)) errs.push(`legacy entry carries non-legacy field '${k}' (raw shape: id/at/type/text/expires/origin) — drift`);
    if (e.text == null || e.text === '') errs.push('legacy entry missing text');
  } else if (cls === 'v2-shape') {
    if (e.origin !== 'legacy' && e.origin !== 'v2') errs.push(`v2-shape class requires origin 'legacy'|'v2' (got '${e.origin}')`);
    for (const k of Object.keys(e)) if (!V2_FIELDS.has(k)) errs.push(`entry carries unknown field '${k}' — drift`);
    if (e.text == null && e.lesson == null) errs.push('v2-shape entry needs text or lesson');
    errs.push(...v2TextReservedViolations(e));
  } else {
    errs.push('shape check unreachable without a verified class');
  }
  return errs;
}

// ---------------------------------------------------------------------------
// Truth store + audit chain + derived sidecar + five invariants
// ---------------------------------------------------------------------------

// schema_version 2 = json-truth era (1 = legacy md sidecar era, kept implicit).
// Skew rule: store.schema_version > CLI known → upgrade guidance, never tamper.
const LESSONS_JSON_SCHEMA_VERSION = 2;

const DISPOSAL_WHATS = new Set(['rm', 'prune', 'edit', 'migrate']);
const MINT_WHATS = new Set(['add', 'edit']);

// Disposal coverage set: single-entry rows carry `old_id`; batch rows (prune,
// anchor-rebuild --force) carry `old_ids[]`. Both spellings must retire ids or
// a sanctioned batch disposal reads as a hand deletion (B-8 false alarm).
function disposalIdSet(rows) {
  const s = new Set();
  for (const r of rows) {
    if (!DISPOSAL_WHATS.has(r.what)) continue;
    if (r.old_id) s.add(r.old_id);
    if (Array.isArray(r.old_ids)) for (const id of r.old_ids) s.add(id);
  }
  return s;
}

function emptyStore() {
  return { schema_version: LESSONS_JSON_SCHEMA_VERSION, entries: [], audit: [], chain_head: 'GENESIS' };
}

// Audit chain — 1:1 port of the sidecar era (same self-hash formula INCLUDING
// the 8-hex digest length, same prev/GENESIS semantics); rows may carry detail
// fields (old_id/new_id/prev_sha/count) which deliberately stay OUTSIDE the
// self-hash payload.
function auditSelfHash(row) {
  return require('node:crypto').createHash('sha256')
    .update(JSON.stringify({ at: row.at, what: row.what, why: row.why, tty_derived: row.tty_derived, prev: row.prev }), 'utf8')
    .digest('hex').slice(0, 8);
}

function appendAuditRow(store, what, why, details = {}) {
  const prev = store.audit.length ? store.audit[store.audit.length - 1].self : 'GENESIS';
  const row = {
    at: new Date().toISOString(),
    what,
    why: String(why || '').slice(0, 200),
    tty_derived: !!process.stdout.isTTY,
    prev,
    ...details,
  };
  row.self = auditSelfHash(row);
  store.audit.push(row);
  store.chain_head = row.self;
  return row;
}

// Invariant ③ — chain verify (B-14, byte-identical semantics to the sidecar era).
function chainViolations(store, where) {
  const errs = [];
  if (!store || typeof store !== 'object' || !Array.isArray(store.audit) || !Array.isArray(store.entries) || typeof store.chain_head !== 'string') {
    return [lf('lessons-store-malformed', `lessons json ${where}: malformed store (want {schema_version, entries[], audit[], chain_head})`, 'restore lessons.json from git (tracked truth) — never hand-rebuild it')];
  }
  if (store.schema_version > LESSONS_JSON_SCHEMA_VERSION) {
    errs.push(lf('lessons-schema-skew', `lessons json ${where}: schema_version ${store.schema_version} > CLI known ${LESSONS_JSON_SCHEMA_VERSION} — upgrade GOS (never hand-edit the file)`, 'upgrade the GOS CLI to a version that knows this schema'));
  }
  let prev = 'GENESIS';
  for (const row of store.audit) {
    if (row.prev !== prev) { errs.push(lf('lessons-chain-broken', `lessons json ${where}: audit chain broken at prev-link (${row.what}) — fail-closed (B-14)`, 'restore lessons.json from git — the audit chain is tamper-evident, not repairable in place')); break; }
    if (row.self !== auditSelfHash(row)) { errs.push(lf('lessons-chain-broken', `lessons json ${where}: audit row self-hash mismatch (${row.what}) — fail-closed (B-14)`, 'restore lessons.json from git — the audit chain is tamper-evident, not repairable in place')); break; }
    prev = row.self;
  }
  if (store.chain_head !== prev) errs.push(lf('lessons-chain-broken', `lessons json ${where}: chain_head ≠ last audit self — fail-closed (B-14)`, 'restore lessons.json from git — the audit chain is tamper-evident, not repairable in place'));
  return errs;
}

// Invariants ④ + ⑤ — id recompute equals content; per-class shape whitelist.
// Also: field validation + global id uniqueness.
function entryViolations(store, where) {
  const errs = [];
  const seen = new Map();
  for (const e of store.entries) {
    if (!e || typeof e !== 'object') { errs.push(lf('lessons-store-malformed', `lessons json ${where}: non-object entry`, 'restore lessons.json from git')); continue; }
    const v = verifyId(e);
    if (!v.ok) {
      errs.push(lf('lessons-id-recompute', `lessons json ${where}: entry ${e.id || '<no id>'} — ${v.reason} (fail-closed, content-id bind)`, 'restore the entry from git, then amend via `gos lessons amend` — ids are bound to content'));
      continue;
    }
    const clsErrs = shapeViolations(e, v.cls);
    for (const ce of clsErrs) errs.push(lf('lessons-shape-whitelist', `lessons json ${where}: entry ${e.id} — ${ce}`, 'restore the entry from git; structured changes go through `gos lessons amend` (promotion), never hand edits'));
    const fldErrs = validateEntryFields(e);
    for (const fe of fldErrs) errs.push(lf('lessons-field-invalid', `lessons json ${where}: entry ${e.id} — ${fe}`, 'restore the entry from git; field constraints are enforced at the command layer'));
    if (seen.has(e.id)) errs.push(lf('lessons-dup-id', `lessons json ${where}: duplicate entry id ${e.id} (mint uniqueness violated)`, 'restore lessons.json from git — duplicate ids break addressability'));
    seen.set(e.id, true);
  }
  return errs;
}

// Derived sidecar: { live_ids: [...], synced_to: chain_head-at-last-sync }.
// Cache, never an authority — but a stale cache is a legitimate witness of a
// hand edit between sanctioned mutations (1:1 port of the old anchorFileDiff).
function loadSidecar(P) {
  if (!fs.existsSync(P.anchor)) return null;
  try {
    const sc = JSON.parse(fs.readFileSync(P.anchor, 'utf8'));
    if (!sc || !Array.isArray(sc.live_ids)) return null;
    return sc;
  } catch { return null; }
}

function writeSidecar(P, store) {
  const sc = { live_ids: store.entries.map((e) => e.id), synced_to: store.chain_head };
  core.writeAtomicJson(P.anchor, sc);
}

// Invariants ① + ② via the sidecar diff. Vanished ids (sidecar has, store
// lacks) need a disposal row AFTER the sync point; added ids (store has,
// sidecar lacks) need a minting row AFTER it.
function sidecarViolations(store, sidecar, where) {
  if (!sidecar) return [];
  const errs = [];
  const liveIds = new Set(sidecar.live_ids);
  const entryIds = new Set(store.entries.map((e) => e && e.id));
  const idx = store.audit.findIndex((r) => r.self === sidecar.synced_to);
  if (idx === -1) {
    return [lf('lessons-sidecar-future', `lessons ${where}: derived sidecar references a chain head absent from the json (json rolled back?)`, 'run `gos lessons anchor-rebuild` to re-derive, or git-restore the json')];
  }
  const since = store.audit.slice(idx + 1);
  const retiredSince = disposalIdSet(since);
  const mintedSince = new Set(since.filter((r) => MINT_WHATS.has(r.what)).map((r) => r.new_id).filter(Boolean));
  for (const id of liveIds) {
    if (!entryIds.has(id) && !retiredSince.has(id)) {
      errs.push(lf('lessons-deletion-audit', `lessons ${where}: entry ${id} deleted without disposal audit row (B-8 pure-deletion)`, '`gos lessons rm/prune` records it; hand edits are not a disposal path — restore the entry then dispose via the command', [id]));
    }
  }
  for (const id of entryIds) {
    if (!liveIds.has(id) && !mintedSince.has(id)) {
      errs.push(lf('lessons-unknown-id', `lessons ${where}: entry ${id} present without a minting audit row (drift)`, '`gos lessons add` or `anchor-rebuild` legitimizes entries', [id]));
    }
  }
  return errs;
}

// Git out-of-band channel (B-9 precedent): json is tracked, so a hand-deleted
// entry shows in the HEAD diff even after the sidecar has been laundered via
// anchor-rebuild. Skipped when HEAD copy is unavailable (first commit pending,
// non-git). Global side has no git — sidecar channel is its only diff witness.
function gitChannelViolations(P, store, where) {
  if (P.global) return [];
  const rel = path.relative(core.currentRootRealpath() || process.cwd(), P.truth);
  let headText = null;
  try { headText = execFileSync('git', ['show', `HEAD:${rel}`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }); }
  catch { return []; }
  let headStore = null;
  try { headStore = JSON.parse(headText); } catch { return []; }
  if (!headStore || !Array.isArray(headStore.entries)) return [];
  const errs = [];
  const idsHead = new Set(headStore.entries.map((e) => e && e.id));
  const idsWork = new Set(store.entries.map((e) => e && e.id));
  const retired = disposalIdSet(store.audit);
  const minted = new Set(store.audit.filter((r) => MINT_WHATS.has(r.what)).map((r) => r.new_id).filter(Boolean));
  for (const id of idsHead) {
    if (!idsWork.has(id) && !retired.has(id)) {
      errs.push(lf('lessons-git-deletion', `lessons ${where}: git HEAD has entry ${id} but working json does not, and no disposal audit row covers it (B-8)`, 'restore the file (git restore) or record `gos lessons rm`', [id]));
    }
  }
  for (const id of idsWork) {
    if (!idsHead.has(id) && !minted.has(id)) {
      errs.push(lf('lessons-git-drift', `lessons ${where}: working json has entry ${id} absent from git HEAD with no minting audit row (drift)`, 'mint entries via `gos lessons add` — hand-crafted entries do not carry audit lineage', [id]));
    }
  }
  return errs;
}

// All five invariants. opts.channels narrows the check set (anchor-rebuild is
// the sanctioned recovery for the sidecar channel — it must not die on it).
// Returns { failures: string[] }; the gateFail-object shape switch lives in
// the command layer, not here.
function verifyStore(store, P, opts = {}) {
  const where = opts.where || (P && P.global ? 'global' : 'project');
  const channels = opts.channels || ['chain', 'entries', 'sidecar', 'git'];
  const failures = [];
  if (channels.includes('chain')) failures.push(...chainViolations(store, where));
  if (channels.includes('entries')) failures.push(...entryViolations(store, where));
  if (channels.includes('sidecar')) failures.push(...sidecarViolations(store, P ? loadSidecar(P) : null, where));
  if (channels.includes('git') && (!P || !P.global)) failures.push(...gitChannelViolations(P, store, where));
  return { failures };
}

// Adjudicating load: parse + full verification. Statuses:
//   'missing' — no json yet (pre-migration world; command layer decides)
//   'corrupt' — unparseable / sentinel=true expectations live in the caller
//   'ok'      — store loaded; failures[] still carries invariant violations
function loadStore(P, opts = {}) {
  const where = opts.where || (P.global ? 'global' : 'project');
  if (!fs.existsSync(P.truth)) return { status: 'missing', store: null, failures: [] };
  let raw;
  try { raw = fs.readFileSync(P.truth, 'utf8'); }
  catch (e) { return { status: 'corrupt', store: null, failures: [lf('lessons-store-unreadable', `lessons json ${where}: unreadable (${e.message})`, `recover via git restore${P.global ? ' / cp .lessons.json.bak lessons.json' : ''}`)] }; }
  let store;
  try { store = JSON.parse(raw); }
  catch { return { status: 'corrupt', store: null, failures: [lf('lessons-store-corrupt', `lessons json ${where}: PARSE FAILED`, `recover via git restore${P.global ? ` or cp ${path.basename(P.truthBak)} lessons.json` : ''} (json is tracked truth; restore — never delete-and-remigrate)`)] }; }
  const res = verifyStore(store, P, opts);
  return { status: 'ok', store, failures: res.failures };
}

// Display load: never dies, never bricks the most-run commands (N9). Missing/
// empty → zero-entry render; corrupt → degraded reason line.
function loadStoreDisplay(P) {
  try {
    if (!fs.existsSync(P.truth)) return { ok: true, store: emptyStore(), reason: null };
    const store = JSON.parse(fs.readFileSync(P.truth, 'utf8'));
    const res = verifyStore(store, P);
    if (res.failures.length) return { ok: false, store: null, reason: res.failures[0] };
    return { ok: true, store, reason: null };
  } catch (e) {
    return { ok: false, store: null, reason: `lessons unavailable (${e.message})` };
  }
}

// Save = atomic truth write + global truth-bak shadow + sidecar sync + md view
// regen. Json is the sole input of every derived artifact — survival
// regression asserts lessons.json bytes never move across regen cycles.
function saveStore(P, store) {
  core.writeAtomicJson(P.truth, store);
  if (P.global && P.truthBak) {
    try { core.writeAtomicJson(P.truthBak, store); }
    catch (e) { core.die(`lessons json global: .lessons.json.bak shadow write failed: ${e.message}`); }
  }
  writeSidecar(P, store);
  writeLessonsMd(P, store);
}

// ---------------------------------------------------------------------------
// Md view renderer + render-hash + read-path validation
// ---------------------------------------------------------------------------

// Md view labels are LOCALE-INVARIANT English: the tracked file must not
// jitter bytes with the operator's locale. Localized labels live in console
// renders only.
const MD_HEADER_TAIL = ' DO NOT EDIT: regenerated from lessons.json on every mutation; hand edits are overwritten by design. -->';

const PLAIN_TAXONOMY = {
  project: 'repo knowledge · never expires',
  model: 'cross-repo behavior · expires on date',
};

function entryBodyLine(e) {
  const id8 = String(e.id || '').slice(0, 8);
  const core_ = e.text != null && e.text !== ''
    ? e.text
    : `${e.scene ? e.scene + ': ' : ''}${e.lesson || ''}`;
  const tags = (e.tags || []).map((t) => `#${t}`).join(' ');
  const exp = e.expires ? ` (expires ${e.expires})` : '';
  return `- (${id8}) ${core_}${tags ? ' ' + tags : ''}${exp}`;
}

function renderLessonsMdBody(store) {
  const out = ['# Lessons (cross-task experience library)', ''];
  for (const type of ['project', 'model']) {
    const group = store.entries.filter((e) => e && e.type === type);
    if (!group.length) continue;
    out.push(`## [${type}] ${PLAIN_TAXONOMY[type]}`);
    out.push('');
    // tag clusters (untagged first), then date desc within each cluster
    const clusters = new Map();
    for (const e of group) {
      const key = (e.tags && e.tags.length) ? e.tags.slice().sort().join(' ') : '';
      if (!clusters.has(key)) clusters.set(key, []);
      clusters.get(key).push(e);
    }
    for (const [key, entries] of [...clusters.entries()].sort((a, b) => (a[0] === '' ? -1 : b[0] === '' ? 1 : a[0].localeCompare(b[0])))) {
      for (const e of entries.sort((a, b) => String(b.at).localeCompare(String(a.at)))) {
        if (key) {
          out.push(`### ${e.at} · ${key.split(' ').map((t) => `#${t}`).join(' ')}`);
          out.push('');
        }
        out.push(entryBodyLine(e));
        if (key) out.push('');
      }
    }
    out.push('');
  }
  out.push('<!-- taxonomy: [project] = repo/domain knowledge, never expires; [model] = model-behavior correction, expires (90d default). ids are entry address prefixes: gos lessons rm/amend <id-prefix>. -->');
  out.push('');
  return out.join('\n');
}

function renderLessonsMd(store) {
  const body = renderLessonsMdBody(store);
  return `<!-- gos:generated lessons-md render-hash:${core.sha16(body)} —${MD_HEADER_TAIL}\n\n${body}`;
}

function writeLessonsMd(P, store) {
  core.writeAtomicText(P.file, renderLessonsMd(store));
}

// Read-path validation: header render-hash must equal sha16(body). Hand edits
// drift the hash → warn + regen. Regen only when the lessons lock is free;
// locked readers (gate inside a mutation) degrade to an advisory.
function verifyLessonsMd(P, store) {
  let text = '';
  try { text = fs.readFileSync(P.file, 'utf8'); }
  catch (e) {
    if (e.code === 'ENOENT') return { status: 'absent' };
    return { status: 'unreadable', reason: e.message };
  }
  const m = text.match(/^<!-- gos:generated lessons-md render-hash:([0-9a-f]{16}) —/);
  if (!m) return { status: 'no-header', reason: 'generated header missing (hand-edited or pre-migration file)' };
  const body = text.slice(text.indexOf('\n\n') + 2);
  if (core.sha16(body) !== m[1]) return { status: 'mismatch', reason: 'render-hash ≠ sha16(body) — hand edit detected' };
  if (store) {
    const expect = renderLessonsMd(store);
    if (expect !== text) return { status: 'stale', reason: 'hash intact but body ≠ current json render' };
  }
  return { status: 'ok' };
}

function ensureLessonsMdFresh(P, store, opts = {}) {
  const v = verifyLessonsMd(P, store);
  if (v.status === 'ok' || v.status === 'absent') return v;
  const side = P.global ? 'global' : 'project';
  if (opts.lockHeld || core.holdsLock()) {
    console.error(`⚠ lessons md ${side}: ${v.reason} — regeneration deferred (lock held); next mutation regenerates`);
    return v;
  }
  console.error(`⚠ lessons md ${side}: ${v.reason} — regenerating from lessons.json (hand edits are not a sanctioned path; use gos lessons amend/rm)`);
  writeLessonsMd(P, store);
  return { status: 'regenerated' };
}

// ---------------------------------------------------------------------------
// Legacy md parsing + sentinel + migration state machine
// ---------------------------------------------------------------------------

const LESSONS_ENTRY_RE = /^- \[(\d{4}-\d{2}-\d{2})\] \[(project|model)\] (.+)$/;

// Lessons integrity failures are gateFail objects (single
// constructor, 3-part discipline). `fix` text keeps the recovery pointer each
// invariant always carried; test assertions match on verdict substrings.
function lf(code, verdict, fix, evidence = []) {
  return core.gateFail(code, { verdict, fix, evidence });
}


// Verbatim parse: at/type/text/expires kept exactly as written so the §8 legacy
// line reconstruction is byte-exact and the kept line-hash ids re-verify.
function parseLegacyMd(text) {
  const entries = [];
  for (const line of String(text || '').split('\n')) {
    const m = line.match(LESSONS_ENTRY_RE);
    if (!m) continue;
    let t = m[3];
    let expires;
    const em = t.match(/ \(expires (\d{4}-\d{2}-\d{2})\)$/);
    if (em) { expires = em[1]; t = t.slice(0, em.index); }
    const e = { id: core.sha16(line), at: m[1], type: m[2], text: t, origin: 'legacy' };
    if (expires) e.expires = expires;
    entries.push(e);
  }
  return { entries };
}

// D-09 sentinel deletion: the lessons_migrated sentinel is gone outright.
// Its launder-protection role moved to the genesis guards below + the
// generated-md header guard (generatedMdPresent).

// Genesis guard (project side, R1-F6a): a tracked lessons.json that vanished
// from the worktree must be RESTORED, never re-migrated — `git log -- <path>`
// finds any ancestor commit carrying it (a fresh migration would mint a new
// audit chain and launder the deletion). Non-git dirs degrade to the header
// guard (returns 0).
function genesisHistoryCount(P) {
  const root = core.currentRootRealpath();
  if (!root) return 0;
  const rel = path.relative(root, P.truth);
  try {
    const out = execFileSync('git', ['-C', root, 'log', '--format=%H', '--', rel], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    return out.split('\n').filter(Boolean).length;
  } catch { return 0; } // git failure ≠ proof of history — degrade to the header guard
}

// Genesis guard (global side, R1-F6b): no git here — the one-time migration
// backup and the truth-bak shadow are the witnesses that a store ever existed.
function globalMigrationBackups(P) {
  try { return fs.readdirSync(path.dirname(P.truth)).filter((f) => /^lessons-migration-backup-\d{4}-\d{2}-\d{2}\.md$/.test(f)); }
  catch { return []; }
}

function generatedMdPresent(P) {
  try { return fs.readFileSync(P.file, 'utf8').startsWith('<!-- gos:generated'); } catch { return false; }
}

// Old-era sidecar reader for the 1:1 audit port: {hashes, chain_head, audit}
// without live_ids = legacy format. Returns null for the new derived cache.
function readOldAnchor(P) {
  if (!fs.existsSync(P.anchor)) return null;
  try {
    const a = JSON.parse(fs.readFileSync(P.anchor, 'utf8'));
    if (Array.isArray(a.audit) && typeof a.chain_head === 'string' && !Array.isArray(a.live_ids)) return a;
    return null;
  } catch { return null; }
}

// One-time md→json migration (spec §3.3 pinned state machine; D-09 sentinel-free):
// resume = state-derived (json parses ⇒ ingest done — never re-parse md) and may
// only REGENERATE the md view after chain verification — the sidecar is NEVER
// rewritten here (a stale sidecar is the sanctioned witness of hand edits;
// healing it would launder deletions, R1-F6c).
// Genesis guards precede any bootstrap: restore, don't remigrate.
// Write order ①backup(read-back verified, abort-on-fail) ②json atomic ③sidecar
// ④md. Version skew dies as upgrade, never tamper.
function migrateLegacy(P, opts = {}) {
  const side = P.global ? 'global' : 'project';
  if (fs.existsSync(P.truth)) {
    let st = null;
    try { st = JSON.parse(fs.readFileSync(P.truth, 'utf8')); } catch { st = null; }
    if (st && Array.isArray(st.entries)) {
      // resume-heal: md view regeneration ONLY, gated on chain verification
      // (R1-F6c). The sidecar stays untouched — a missing/stale sidecar
      // resolves through the next sanctioned saveStore, never here.
      if (chainViolations(st, side).length === 0 && verifyLessonsMd(P, st).status !== 'ok') {
        writeLessonsMd(P, st);
      }
      return { already: true, count: st.entries.length };
    }
    core.die(`lessons ${side}: lessons.json exists but is unusable — recover via git restore${P.global ? ` or cp ${P.truthBak} ${P.truth}` : ''}; never delete-and-remigrate (the audit chain lives in the json)`);
  }
  // genesis guards (D-09, sentinel replacement): a store that ever existed must
  // be restored, never re-migrated through a fresh (laundered) audit chain
  if (!P.global) {
    const ancestors = genesisHistoryCount(P);
    if (ancestors > 0) {
      core.die(`lessons ${side}: lessons.json is missing but ${ancestors} ancestor commit(s) carry it — restore, don't remigrate (git restore .gos/lessons.json; the audit chain lives in the json, a fresh migration would launder it)`);
    }
  } else {
    const backups = globalMigrationBackups(P);
    const hasTruthBak = P.truthBak && fs.existsSync(P.truthBak);
    if (backups.length || hasTruthBak) {
      const found = backups.length ? `migration backup(s) ${backups.join(', ')}` : `truth-bak ${path.basename(P.truthBak)}`;
      core.die(`lessons ${side}: lessons.json is missing but ${found} exist${backups.length && hasTruthBak ? '' : 's'} — restore, don't remigrate (cp ${P.truthBak} ${P.truth}, or recover entries from the backup); never delete-and-remigrate`);
    }
  }
  if (generatedMdPresent(P)) {
    core.die(`lessons ${side}: lessons.json missing while a GENERATED lessons.md view exists — the view is derived, not truth; recover the json (git restore${P.global ? ` or cp ${P.truthBak} ${P.truth}` : ''}) instead of re-deriving`);
  }
  let mdText = '';
  try { mdText = fs.readFileSync(P.file, 'utf8'); } catch { /* none */ }
  const parsed = parseLegacyMd(mdText);
  // ① backup whenever the legacy file carries ANY content. A non-matching md
  // (hand-maintained or variant format) parses to zero entries but is still
  // the only copy of that text — it must survive the generated view that the
  // migration is about to write over it.
  if (mdText.trim()) {
    try {
      fs.mkdirSync(path.dirname(P.backup), { recursive: true });
      fs.copyFileSync(P.file, P.backup);
      if (fs.readFileSync(P.backup, 'utf8') !== mdText) throw new Error('read-back mismatch');
    } catch (e) {
      core.die(`lessons ${side}: migration backup failed (${e.message}) — migration ABORTED with zero side effects`);
    }
    if (!parsed.entries.length) {
      console.error(`⚠ lessons ${side}: md content present but no entries matched the legacy format — original preserved at ${P.backup}`);
    }
    // latest-generation lifecycle: prior backup dates removed after success
    const dir = path.dirname(P.backup);
    const keep = path.basename(P.backup);
    try {
      for (const f of fs.readdirSync(dir)) {
        if (/^lessons-migration-backup-\d{4}-\d{2}-\d{2}\.md$/.test(f) && f !== keep) {
          try { fs.unlinkSync(path.join(dir, f)); } catch { /* best effort */ }
        }
      }
    } catch { /* dir listing */ }
  }
  // ② store: entries verbatim (kept line-hash ids) + audit chain PORTED 1:1 from
  // the old sidecar when present and intact, else fresh
  const store = emptyStore();
  store.entries.push(...parsed.entries);
  const oldAnchor = readOldAnchor(P);
  let ported = false;
  if (oldAnchor && Array.isArray(oldAnchor.audit) && typeof oldAnchor.chain_head === 'string') {
    const synthetic = { audit: oldAnchor.audit, chain_head: oldAnchor.chain_head };
    if (chainViolations({ ...synthetic, entries: [], schema_version: 1 }, side).length === 0) {
      store.audit = oldAnchor.audit;
      store.chain_head = oldAnchor.chain_head;
      ported = true;
    } else {
      core.die(`lessons ${side}: legacy sidecar audit chain is broken — fix it BEFORE migrating (B-14); migration refuses to launder a broken chain`);
    }
  }
  appendAuditRow(store, 'migrate', `md→json one-time migration (${parsed.entries.length} entries, legacy line-hash ids kept)`, { count: parsed.entries.length });
  saveStore(P, store); // ② json atomic → ③ sidecar → ④ md (pinned order inside; sentinel write deleted — D-09)
  // sidecar-era global .bak retired (truth-bak replaced it)
  if (P.global) {
    try { fs.unlinkSync(path.join(path.dirname(P.truth), '.lessons-anchors.bak')); } catch { /* absent */ }
  }
  if (!opts.quiet) {
    console.log(`✓ lessons ${side}: migrated ${parsed.entries.length} entries to lessons.json (ids kept, audit chain ${ported ? 'ported 1:1' : 'started fresh'}; backup: ${path.basename(P.backup)})`);
  }
  return { already: false, count: parsed.entries.length };
}

// Adjudicating/mutation entry point: guarantee a valid json exists afterwards.
function ensureMigrated(P, opts = {}) {
  return migrateLegacy(P, opts);
}

// ---------------------------------------------------------------------------
// Lessons surfacing: attribution + stage-tagged progressive
// disclosure. Display loads only — a bad store degrades, never bricks.
// ---------------------------------------------------------------------------

function expiringSoon(store, days = 14) {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() + days);
  return store.entries.filter((e) => e && e.expires && new Date(e.expires + 'T23:59:59') <= cutoff).length;
}

// Side summary for a display load (never throws).
function sideSummary(P) {
  const d = loadStoreDisplay(P);
  if (!d.ok) return { ok: false, reason: d.reason, count: null, expiring: null, path: P.truth };
  return { ok: true, count: d.store.entries.length, expiring: expiringSoon(d.store), path: P.truth, store: d.store };
}

// Full attribution snapshot for status/instructions/context surfaces.
function lessonsAttribution(stage) {
  const proj = sideSummary(core.lessonsPaths('project'));
  const glob = sideSummary(core.lessonsPaths('model'));
  const tag = (stage || '').toLowerCase();
  let stageTagged = [];
  let rest = 0;
  if (proj.ok && tag) {
    const all = proj.store.entries;
    stageTagged = all.filter((e) => (e.tags || []).includes(tag));
    rest = all.length - stageTagged.length;
  }
  return { project: proj, global: glob, stageTagged, rest, stage: tag };
}

module.exports = {
  V2_SEGMENTS,
  LESSONS_JSON_SCHEMA_VERSION,
  PLAIN_TAXONOMY,
  canonV2,
  canonLegacy,
  verifyId,
  sha16Of,
  mintId,
  validateEntryFields,
  v2TextReservedViolations,
  shapeViolations,
  emptyStore,
  auditSelfHash,
  appendAuditRow,
  chainViolations,
  entryViolations,
  loadSidecar,
  writeSidecar,
  sidecarViolations,
  gitChannelViolations,
  verifyStore,
  loadStore,
  loadStoreDisplay,
  saveStore,
  renderLessonsMd,
  renderLessonsMdBody,
  writeLessonsMd,
  verifyLessonsMd,
  ensureLessonsMdFresh,
  parseLegacyMd,
  readOldAnchor,
  genesisHistoryCount,
  globalMigrationBackups,
  migrateLegacy,
  ensureMigrated,
  lessonsAttribution,
};
