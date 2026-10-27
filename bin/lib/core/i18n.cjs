// core/i18n.cjs — locale resolution + catalog lookup (P15 )
// en canonical = locales/en.cjs (existing frozen strings as CONTRACTS aliases —
// copies forbidden); zh = translation layer, command tokens NEVER embedded
// literally ({cmd:<name>} placeholders resolve from the CLI registry).
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const fsio = require('./fsio.cjs');
const state = require('./state.cjs');

const VALID_LOCALES = Object.freeze(['en', 'zh-CN']);

// {zh, zh_*, zh-*} (case-insensitive) → zh-CN; {en*} → en; '' = unset; else null.
function normalizeLocale(raw) {
  if (raw == null) return null;
  const s = String(raw).trim();
  if (s === '') return null;
  const lower = s.toLowerCase();
  if (lower === 'en' || lower.startsWith('en_') || lower.startsWith('en-')) return 'en';
  if (lower === 'zh' || lower.startsWith('zh_') || lower.startsWith('zh-')) return 'zh-CN';
  return null;
}

function globalConfigPath() { return path.join(os.homedir(), '.config', 'gos', 'config.json'); }

function readConfigLocale(p) {
  try {
    const c = JSON.parse(fs.readFileSync(p, 'utf8'));
    return { raw: c.locale, normalized: normalizeLocale(c.locale) };
  } catch { return { raw: undefined, normalized: null }; }
}

// Precedence env > project config > global config > default en (nearest-wins,
// git semantics — F15: env wins for CI/scripts, visibility compensates).
// Unknown non-empty GOS_LANG → stderr advisory + en (never a crash, N8).
function resolveLocale() {
  const envRaw = process.env.GOS_LANG;
  if (envRaw != null && String(envRaw).trim() !== '') {
    const n = normalizeLocale(envRaw);
    if (n) return { locale: n, source: 'env (GOS_LANG)' };
    console.error(`⚠ GOS_LANG='${envRaw}' is unknown (valid: ${VALID_LOCALES.join(' | ')}) — falling back to English`);
    return { locale: 'en', source: 'env (unknown → en fallback)' };
  }
  const proj = readConfigLocale(path.join(fsio.GOS_DIR, 'config.json'));
  if (proj.normalized) return { locale: proj.normalized, source: `project config (${proj.raw})` };
  const glob = readConfigLocale(globalConfigPath());
  if (glob.normalized) return { locale: glob.normalized, source: `global config (${glob.raw})` };
  return { locale: 'en', source: 'default' };
}

let _resolved = null;
function effectiveLocale(refresh = false) {
  if (refresh || !_resolved) _resolved = resolveLocale();
  return _resolved;
}

// {cmd:<name>} placeholders resolve against the CLI registry single source —
// zh strings stay command-token-free by construction (renames go red in ).
function resolveCmdPlaceholders(s) {
  return String(s).replace(/\{cmd:([a-z0-9_-]+)\}/g, (m, name) => {
    const known = Object.prototype.hasOwnProperty.call(state.COMMANDS, name) || name === '';
    return known ? `gos ${name}`.trim() : m;
  });
}

function interpolate(v, params) {
  if (typeof v === 'string') {
    let out = resolveCmdPlaceholders(v);
    for (const [k, val] of Object.entries(params || {})) out = out.split(`{${k}}`).join(String(val));
    return out;
  }
  const out = {};
  for (const [k, val] of Object.entries(v)) {
    out[k] = typeof val === 'string' ? interpolate(val, params) : val;
  }
  return out;
}

// Console width hygiene (U26 budget): project paths relative to cwd, global
// paths ~-abbreviated — attribution lines stay scannable on narrow terminals.
function shortPath(p) {
  const home = os.homedir();
  let s = String(p || '');
  if (s.startsWith(home + path.sep)) return '~' + s.slice(home.length);
  const rel = path.relative(process.cwd(), s);
  if (rel && !rel.startsWith('..')) return rel;
  return s;
}

// t(key, params) → string | {what, why, fix?} object (structured entries render
// 3-part by the consuming code, never prose discipline). Missing zh key → en
// fallback + advisory; missing everywhere → the key itself (never crash, never
// empty).
function t(key, params) {
  const eff = effectiveLocale();
  const en = require('./locales/en.cjs');
  let used = 'en';
  let v = en[key] != null ? en[key] : null;
  if (eff.locale === 'zh-CN') {
    const zh = require('./locales/zh.cjs');
    if (zh[key] != null) { v = zh[key]; used = 'zh-CN'; }
    else if (v != null) console.error(`⚠ i18n: missing zh-CN key '${key}' — falling back to en`);
  }
  if (v == null) return key;
  return params || typeof v === 'object' ? interpolate(v, params) : v;
}

// ↔ join (C4): localized what/why for a gate failure code; evidence and
// fix NEVER pass through here (locale-invariant by construction).
function gateVerdictParts(code) {
  const v = t(`gate.${code}`);
  if (v && typeof v === 'object' && v.what != null) return { what: v.what, why: v.why || '' };
  return null;
}

module.exports = {
  VALID_LOCALES,
  normalizeLocale,
  resolveLocale,
  effectiveLocale,
  globalConfigPath,
  resolveCmdPlaceholders,
  shortPath,
  t,
  gateVerdictParts,
};
