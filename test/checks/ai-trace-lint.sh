#!/usr/bin/env bash
# ai-trace-lint — AI-process artifact boundary check.
#
# Bans AI-process lineage markers from git-tracked file content so comments
# and docs describe WHAT the code does, never WHY a task decided it:
#   tier A (strong tokens, matched anywhere in a file):
#     - bracket anchors: bracket, letter words with optional space/hyphen
#       breaks, then a digit or slash (catches [D-NN], [REVIEW Mn], [T n],
#       [Phase W Tn] and every letter casing)
#     - dash compounds: letters+digits, hyphen, letters+digits (RTn-Fn,
#       Rn-Fn, Wn-Tn shapes)
#     - spec-section citations: section marker then a digit (spec §n.n,
#       §na-n shapes)
#   tier B (weak forms, comment lines only):
#     - bare wave/task ids: Wn, Tn, Wave n
#     - bare and parenthesized finding ids: D-nn, (D-nn), slash compounds
#       D-nn/R-nn
#     - task-narrative phrases ("this phase|wave|task adds|ships|introduces")
#
# Comment-line detection per filetype (in the node helper): "#" for shell,
# yaml and unknown text types (over-flag beats under-flag); "//", "/*" and
# "*" continuation lines for JS-like files; markdown scans every line.
# Structural plan-format exemption: Wave headings and Covers / Depends-on
# lines inside *.md never count as hits (the product's own plan grammar).
# Path carve-outs: CHANGELOG.md, .changes.md and .gos/** are never
# violations; the .gos/** anchor hit count is printed as a sidecar metric
# so exempt-layer debt stays visible.
#
# Whitelist (default .gos/ai-trace-whitelist.json): an array of entries
# whose identity is the path + category pair, so one path may carry several
# entries. Categories:
#   in-flight-sweep    per-path maxHits, exact equality (the sweep tracker)
#   lint-fixture       per-path maxHits, exact equality (planted fixtures)
#   meta-doc-quoting   per-path maxHits plus a region sha pin
#   drift-ledger       explicit line list; anchors live on those lines only
#   frozen-string      explicit line list with per-line sha pins
# Exact equality means the live hit count must equal the registered count
# in both directions; entries whose path is not tracked, capped entries
# left with nothing to cover, drifted pins and hand shapes the generator
# cannot produce are all violations (fail-closed).
#
# Machine views — one flag per consumer class, no overloading:
#   --json               violations only (gate evidence; registered hits
#                        are hidden)
#   --emit-hits [<out>]  full per-hit census including registered hits
#                        (sweep harness and disposition consumers)
#   --emit-baseline [<out>]
#                        regenerate the full whitelist from the lint's own
#                        patterns (landing and regen guard); deterministic
#                        path-then-category sort, byte-stable output
#
# Usage:
#   ai-trace-lint.sh [--whitelist <path>] [--json]
#   ai-trace-lint.sh [--whitelist <path>] --emit-hits [<out>]
#   ai-trace-lint.sh [--whitelist <path>] --emit-baseline [<out>]
#     --whitelist <path>  whitelist location (default .gos/ai-trace-whitelist.json);
#                         relative paths resolve against the repo root; a
#                         missing whitelist file means every hit is a
#                         violation (pre-whitelist behavior)
#     --json              machine mode: violations as a JSON array on stdout,
#                         nothing else; infrastructure errors go to stderr
#     --emit-hits [<out>]
#                         write one record per hit, each
#                         {path, line, tier, matched, category, registered},
#                         to <out> (default stdout); emission exits zero
#                         regardless of violations — the census is a view,
#                         not a verdict
#     --emit-baseline [<out>]
#                         regenerate the whitelist: every path holding
#                         uncovered hits gains an in-flight-sweep entry with
#                         the exact count, existing entries carry over per
#                         path + category key; <out> file (default stdout);
#                         relative out paths resolve against the working
#                         directory at invocation
#
# Fail-closed in every direction:
#   - unregistered anchor hit outside a carve-out -> exit 1
#   - whitelist unparsable, non-ASCII, invalid shape, drifted pin,
#     ghost entry, broken count equality     -> exit 1
#   - not inside a git work tree              -> exit 1
#   - internal error (git failure, unreadable tracked file) -> exit 1
#
# Exit codes: 0 clean (or emission done), 1 violations or infrastructure
# failure.
set -euo pipefail

WHITELIST=".gos/ai-trace-whitelist.json"
MODE="lint"
OUT=""
invocation_dir=$PWD

while [ $# -gt 0 ]; do
  case "$1" in
    --whitelist)
      [ $# -ge 2 ] || { echo "ai-trace-lint: --whitelist requires a path" >&2; exit 1; }
      WHITELIST="$2"; shift 2 ;;
    --json)
      [ "$MODE" = "lint" ] || { echo "ai-trace-lint: --json conflicts with another mode flag" >&2; exit 1; }
      MODE="json"; shift ;;
    --emit-hits)
      [ "$MODE" = "lint" ] || { echo "ai-trace-lint: --emit-hits conflicts with another mode flag" >&2; exit 1; }
      MODE="emit-hits"; shift
      if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then OUT="$1"; shift; fi ;;
    --emit-baseline)
      [ "$MODE" = "lint" ] || { echo "ai-trace-lint: --emit-baseline conflicts with another mode flag" >&2; exit 1; }
      MODE="emit-baseline"; shift
      if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then OUT="$1"; shift; fi ;;
    -h|--help) sed -n '2,83p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "ai-trace-lint: unknown argument: $1" >&2; exit 1 ;;
  esac
done

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "ai-trace-lint: not inside a git work tree — refusing to run (fail-closed)" >&2
  exit 1
}
cd "$root"

case "$WHITELIST" in
  /*) ;;
  *) WHITELIST="$root/$WHITELIST" ;;
esac
if [ -f "$WHITELIST" ]; then WL_ARG="$WHITELIST"; else WL_ARG="-"; fi

if [ -n "$OUT" ]; then
  case "$OUT" in
    /*) ;;
    *) OUT="$invocation_dir/$OUT" ;;
  esac
else
  OUT="-"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Bash lists tracked files only; every classification, pattern and whitelist
# decision lives in the node helper below (no grep dialect dependence).
list="$tmp/files"
git ls-files -z > "$list" || { echo "ai-trace-lint: git ls-files failed (fail-closed)" >&2; exit 1; }

cat > "$tmp/helper.cjs" <<'NODE_EOF'
'use strict';
const fs = require('fs');
const crypto = require('crypto');

const listFile = process.argv[2];
const MODE = process.argv[3];        // lint | json | emit-hits | emit-baseline
const WL_ARG = process.argv[4];      // '-' or absolute whitelist path
const OUT = process.argv[5];         // '-' or absolute emission path
const RESULT = process.argv[6];

function die(msg) {
  process.stderr.write('ai-trace-lint: ' + msg + '\n');
  process.exit(3);
}

// Grammar. Every pattern requires a real digit, so the digit-free
// placeholder spellings used throughout this script cannot match it.
const TIER_A = [
  // bracket + letter words (space/hyphen separated) + optional final
  // separator + digit or slash; required separators keep matching linear
  { name: 'bracket-anchor', re: /\[[A-Za-z]+(?:[ -][A-Za-z]+)*[ -]?[0-9/]/ },
  // letters+digits, hyphen, letters+digits (RTn-Fn / Rn-Fn / Wn-Tn shapes)
  { name: 'dash-compound', re: /\b[A-Za-z]+\d+-[A-Za-z]+\d+\b/ },
  // section marker then a digit (spec citation shapes)
  { name: 'spec-citation', re: /§\s*\d/ },
];

// Weak forms: only tested on comment lines (every line in markdown).
const TIER_B = [
  { name: 'wave-id', re: /\bWave\s+\d+\b/ },
  { name: 'wave-token', re: /\bW\d+\b/ },
  { name: 'task-token', re: /\bT\d+\b/ },
  { name: 'finding-id', re: /\b(?:D|R|B|F)-\d+\b/ },
  { name: 'task-narrative', re: /\bthis\s+(?:phase|wave|task)\s+(?:adds|ships|introduces)\b/i },
];

// Comment-line classification per filetype. Unknown text types default to
// "#" (over-flag beats under-flag).
const SLASH_FAMILY = new Set(['js', 'cjs', 'mjs', 'ts', 'tsx', 'jsx', 'json',
  'java', 'c', 'h', 'cpp', 'hpp', 'cc', 'cxx', 'go', 'rs', 'swift', 'kt',
  'kts', 'scala', 'css', 'scss', 'less', 'php', 'groovy', 'dart']);
const MD_FAMILY = new Set(['md', 'markdown']);

const HASH_LINE = /^\s*#/;
const SLASH_LINE = /^\s*(?:\/\/|\/\*|\*)/;

function extOf(path) {
  const base = path.slice(path.lastIndexOf('/') + 1);
  const dot = base.lastIndexOf('.');
  return dot > 0 ? base.slice(dot + 1).toLowerCase() : '';
}

function isCommentLine(ext, text) {
  if (MD_FAMILY.has(ext)) return true;
  if (SLASH_FAMILY.has(ext)) return SLASH_LINE.test(text);
  return HASH_LINE.test(text);
}

// Product plan grammar inside *.md: Wave headings and Covers / Depends-on
// lines are format, not trace — structurally exempt, never counted.
const PLAN_WAVE_HEADING = /^\s*#{1,6}\s+Wave\s+\d+\b/;
const PLAN_META_LINE = /^\s*(?:[-*+]\s*)?(?:\*\*)?\s*(?:[Cc]overs|[Dd]epends on)\s*(?:\*\*)?\s*:/;

let listBuf;
try { listBuf = fs.readFileSync(listFile); }
catch (e) { die('tracked file list unreadable: ' + e.message); }
const files = listBuf.toString('utf8').split('\0').filter(Boolean);
const trackedSet = new Set(files);

// Hit census records: {path, line, tier, matched}; the whitelist engine
// annotates them with category and registered flags downstream.
const hits = [];
const hitsByPath = new Map();
let gosAnchorHits = 0;
let tierA = 0;
let tierB = 0;

function record(path, line, tier, matched) {
  if (path.startsWith('.gos/')) { gosAnchorHits++; return; }
  const h = { path, line, tier, matched, registered: false, category: null };
  hits.push(h);
  if (!hitsByPath.has(path)) hitsByPath.set(path, []);
  hitsByPath.get(path).push(h);
  if (tier === 'A') tierA++; else tierB++;
}

for (const p of files) {
  // Path carve-outs: the changelog layers are not scanned at all; .gos/**
  // is scanned for the sidecar debt metric only (record() drops the hit
  // from the census).
  if (p === 'CHANGELOG.md' || p === '.changes.md') continue;
  let buf;
  try { buf = fs.readFileSync(p); }
  catch (e) { die('cannot read tracked file: ' + p + ' (' + e.code + ')'); }
  if (buf.includes(0)) continue; // binary file, not text content
  const ext = extOf(p);
  const isMd = MD_FAMILY.has(ext);
  const lines = buf.toString('utf8').split('\n');
  for (let i = 0; i < lines.length; i++) {
    const text = lines[i];
    if (isMd && (PLAN_WAVE_HEADING.test(text) || PLAN_META_LINE.test(text))) continue;
    for (const pat of TIER_A) {
      const m = pat.re.exec(text);
      if (m) { record(p, i + 1, 'A', m[0]); break; }
    }
    if (isCommentLine(ext, text)) {
      for (const pat of TIER_B) {
        const m = pat.re.exec(text);
        if (m) { record(p, i + 1, 'B', m[0]); break; }
      }
    }
  }
}

// ---------------------------------------------------------------- whitelist
const CATEGORIES = ['in-flight-sweep', 'lint-fixture', 'meta-doc-quoting',
  'drift-ledger', 'frozen-string'];
const CAPPED = new Set(['in-flight-sweep', 'lint-fixture', 'meta-doc-quoting']);
const KEY_SETS = {
  'in-flight-sweep': ['path', 'category', 'maxHits', 'reason'],
  'lint-fixture': ['path', 'category', 'maxHits', 'reason'],
  'meta-doc-quoting': ['path', 'category', 'maxHits', 'reason', 'pin'],
  'drift-ledger': ['path', 'category', 'reason', 'lines'],
  'frozen-string': ['path', 'category', 'reason', 'lines'],
};
const HEX64 = /^[0-9a-f]{64}$/;
const GENERATED_REASON = 'Legacy AI-process anchor comments pending the domain sweep; the count tracks unswept hits and must shrink to removal.';

function lineSha(text) {
  return crypto.createHash('sha256').update(text, 'utf8').digest('hex');
}

const lineCache = new Map();
function fileLines(p) {
  if (!lineCache.has(p)) {
    try { lineCache.set(p, fs.readFileSync(p, 'utf8').split('\n')); }
    catch (e) { return null; }
  }
  return lineCache.get(p);
}

function badEntry(e, detail) {
  return {
    type: 'invalid-whitelist-entry',
    path: (e && typeof e.path === 'string') ? e.path : '',
    line: 0,
    detail,
  };
}

// Entry shapes must be exactly what emit-baseline can produce; anything
// hand-invented fails closed as an invalid-whitelist-entry violation.
function validateEntry(e) {
  if (!e || typeof e !== 'object' || Array.isArray(e)) return badEntry(e, 'entry is not an object');
  if (typeof e.path !== 'string' || !e.path.trim()) return badEntry(e, 'missing "path"');
  if (typeof e.category !== 'string' || !KEY_SETS[e.category]) return badEntry(e, 'unknown category: ' + String(e.category));
  if (typeof e.reason !== 'string' || e.reason.trim().length < 8) return badEntry(e, 'needs a meaningful English "reason"');
  const want = KEY_SETS[e.category];
  const keys = Object.keys(e);
  if (keys.length !== want.length || !want.every((k) => keys.includes(k))) {
    return badEntry(e, 'key set must be exactly: ' + want.join(', '));
  }
  if (CAPPED.has(e.category) && (!Number.isInteger(e.maxHits) || e.maxHits < 1)) {
    return badEntry(e, '"maxHits" must be an integer of at least one');
  }
  if (e.category === 'meta-doc-quoting') {
    const p = e.pin;
    const pw = ['type', 'minLine', 'regionSha256'];
    if (!p || typeof p !== 'object' || Array.isArray(p)) return badEntry(e, '"pin" must be an object');
    const pk = Object.keys(p);
    if (pk.length !== pw.length || !pw.every((k) => pk.includes(k))) return badEntry(e, 'pin key set must be: ' + pw.join(', '));
    if (p.type !== 'region-sha256') return badEntry(e, 'pin.type must be "region-sha256"');
    if (!Number.isInteger(p.minLine) || p.minLine < 1) return badEntry(e, 'pin.minLine must be a positive integer');
    if (typeof p.regionSha256 !== 'string' || !HEX64.test(p.regionSha256)) return badEntry(e, 'pin.regionSha256 must be a sixty-four char lowercase hex sha');
  }
  if (e.category === 'drift-ledger') {
    if (!Array.isArray(e.lines) || e.lines.length === 0) return badEntry(e, '"lines" must be a non-empty array');
    for (const n of e.lines) if (!Number.isInteger(n) || n < 1) return badEntry(e, 'every listed line must be a positive integer');
    for (let i = 1; i < e.lines.length; i++) if (e.lines[i] <= e.lines[i - 1]) return badEntry(e, '"lines" must be strictly ascending');
  }
  if (e.category === 'frozen-string') {
    if (!Array.isArray(e.lines) || e.lines.length === 0) return badEntry(e, '"lines" must be a non-empty array');
    for (const l of e.lines) {
      if (!l || typeof l !== 'object' || Array.isArray(l)) return badEntry(e, 'each pinned line must be an object');
      const lw = ['line', 'sha256'];
      const lk = Object.keys(l);
      if (lk.length !== lw.length || !lw.every((k) => lk.includes(k))) return badEntry(e, 'pinned line key set must be: line, sha256');
      if (!Number.isInteger(l.line) || l.line < 1) return badEntry(e, 'pinned "line" must be a positive integer');
      if (typeof l.sha256 !== 'string' || !HEX64.test(l.sha256)) return badEntry(e, 'pinned "sha256" must be a sixty-four char lowercase hex sha');
    }
    for (let i = 1; i < e.lines.length; i++) if (e.lines[i].line <= e.lines[i - 1].line) return badEntry(e, 'pinned lines must be strictly ascending');
  }
  return null;
}

let existing = [];
const wlInvalid = [];
if (WL_ARG !== '-') {
  let raw;
  try { raw = fs.readFileSync(WL_ARG, 'utf8'); }
  catch (e) { die('whitelist unreadable: ' + WL_ARG + ' (' + e.code + ')'); }
  if (!/^[\x20-\x7e\n\r\t]*$/.test(raw)) die('whitelist contains non-printable-ASCII characters — entries and reasons must be pure ASCII English');
  let parsed;
  try { parsed = JSON.parse(raw); }
  catch (e) { die('whitelist is not valid JSON: ' + e.message); }
  if (!Array.isArray(parsed)) die('whitelist must be a JSON array');
  const seen = new Set();
  for (const e of parsed) {
    let bad = validateEntry(e);
    if (!bad) {
      const key = e.path + '\u0000' + e.category;
      if (seen.has(key)) bad = badEntry(e, 'duplicate path + category pair — the pair is the entry identity');
      else seen.add(key);
    }
    if (bad) { wlInvalid.push(bad); continue; }
    existing.push(e);
  }
  if (MODE.startsWith('emit-') && wlInvalid.length > 0) {
    // Regeneration must never launder a hand shape into a landed whitelist.
    die('whitelist entry invalid, emission refuses to carry it: ' + wlInvalid[0].path + ' — ' + wlInvalid[0].detail);
  }
}

const catAsc = (a, b) => (a.category < b.category ? -1 : a.category > b.category ? 1 : 0);
const entryCmp = (a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : catAsc(a, b));

// Coverage engine shared by every view. Line categories (frozen-string,
// drift-ledger) pin hits to exact lines — a frozen pin outranks a ledger
// listing when both name the same line. Capped categories then compete for
// the remaining hits of the path in category order; exact equality means
// the capped maxHits must consume the leftovers exactly. Returns the
// leftover count per path (what in-flight-sweep regeneration must absorb)
// and the set of paths whose capped equality is broken.
function evaluate(entries) {
  const violations = [];
  const entriesByPath = new Map();
  for (const e of entries) {
    if (!trackedSet.has(e.path)) {
      violations.push({ type: 'ghost-whitelist-entry', path: e.path, line: 0, category: e.category, detail: 'path is not git-tracked' });
      continue;
    }
    if (!entriesByPath.has(e.path)) entriesByPath.set(e.path, []);
    entriesByPath.get(e.path).push(e);
  }
  const leftoverByPath = new Map();
  const cappedBroken = new Set();
  for (const [path, list] of entriesByPath) {
    const pathHits = hitsByPath.get(path) || [];
    const hitLines = new Set(pathHits.map((h) => h.line));
    const lineCat = new Map();
    for (const e of list) {
      if (e.category !== 'drift-ledger') continue;
      for (const n of e.lines) {
        if (!hitLines.has(n)) {
          violations.push({ type: 'stale-or-exceeded', path, line: n, category: e.category, detail: 'ledger line holds no anchor — the line list drifted, regenerate the whitelist' });
        } else if (!lineCat.has(n)) {
          lineCat.set(n, e.category);
        }
      }
    }
    for (const e of list) {
      if (e.category !== 'frozen-string') continue;
      const lines = fileLines(path);
      for (const pin of e.lines) {
        if (!lines || pin.line > lines.length) {
          violations.push({ type: 'pin-mismatch', path, line: pin.line, category: e.category, detail: 'pinned line is beyond end of file — the pin drifted' });
          continue;
        }
        if (lineSha(lines[pin.line - 1]) !== pin.sha256) {
          violations.push({ type: 'pin-mismatch', path, line: pin.line, category: e.category, detail: 'line sha differs from the pin — content drifted; restore it or re-pin consciously' });
          continue;
        }
        lineCat.set(pin.line, e.category);
      }
    }
    for (const e of list) {
      if (e.category !== 'meta-doc-quoting') continue;
      const lines = fileLines(path);
      if (!lines || e.pin.minLine > lines.length) {
        violations.push({ type: 'pin-mismatch', path, line: 0, category: e.category, detail: 'pin.minLine is beyond end of file — the boundary drifted' });
      } else if (lineSha(lines.slice(e.pin.minLine - 1).join('\n')) !== e.pin.regionSha256) {
        violations.push({ type: 'pin-mismatch', path, line: 0, category: e.category, detail: 'region sha differs from the pin — the quoted region changed or the boundary shifted' });
      }
    }
    for (const h of pathHits) {
      if (lineCat.has(h.line)) { h.registered = true; h.category = lineCat.get(h.line); }
    }
    const capped = list.filter((e) => CAPPED.has(e.category)).sort(catAsc);
    const open = pathHits.filter((h) => h.category === null);
    if (capped.length === 0) {
      leftoverByPath.set(path, open.length);
      continue;
    }
    const sum = capped.reduce((a, e) => a + e.maxHits, 0);
    if (open.length === 0) {
      for (const e of capped) violations.push({ type: 'ghost-whitelist-entry', path, line: 0, category: e.category, detail: 'capped entry covers no hit — the sweep finished, remove the entry' });
      leftoverByPath.set(path, 0);
    } else if (sum !== open.length) {
      for (const e of capped) violations.push({ type: 'stale-or-exceeded', path, line: 0, category: e.category, detail: 'exact-equality broken: entry registers ' + e.maxHits + ', path holds ' + open.length + ' uncovered hit(s), capped entries sum to ' + sum + ' — regenerate the whitelist' });
      cappedBroken.add(path);
      leftoverByPath.set(path, Math.max(0, open.length - sum));
    } else {
      let idx = 0;
      for (const e of capped) {
        for (let k = 0; k < e.maxHits; k++) {
          const h = open[idx++];
          h.registered = true;
          h.category = e.category;
        }
      }
      leftoverByPath.set(path, 0);
    }
  }
  for (const [path, pathHits] of hitsByPath) {
    if (!entriesByPath.has(path)) leftoverByPath.set(path, pathHits.length);
  }
  return { violations, leftoverByPath, cappedBroken };
}

function writeOut(text) {
  if (OUT === '-') process.stdout.write(text);
  else {
    try { fs.writeFileSync(OUT, text); }
    catch (e) { die('cannot write emission file: ' + OUT + ' (' + e.code + ')'); }
  }
}

// Census records are materialized after evaluate() so the registered and
// category annotations are live.
function makeCensus() {
  return hits.map((h) => ({
    path: h.path, line: h.line, tier: h.tier, matched: h.matched,
    category: h.category, registered: h.registered,
  }));
}

const summary = {
  violations: [],
  hits: [],
  scannedFiles: files.length,
  tierA,
  tierB,
  gosAnchorHits,
};

if (MODE === 'emit-baseline') {
  // Regeneration view: in-flight-sweep entries are rebuilt from the
  // leftovers the permanent categories cannot cover; every other entry
  // carries over byte-stable per its path + category key.
  const permanent = existing.filter((e) => e.category !== 'in-flight-sweep');
  const templates = new Map(existing.filter((e) => e.category === 'in-flight-sweep').map((e) => [e.path, e]));
  const view = evaluate(permanent);
  const emitted = permanent.map((e) => Object.assign({}, e));
  let inFlight = 0;
  for (const [path, count] of view.leftoverByPath) {
    if (count < 1) continue;
    const tmpl = templates.get(path);
    if (tmpl) {
      const c = Object.assign({}, tmpl);
      c.maxHits = count;
      emitted.push(c);
    } else {
      emitted.push({ path, category: 'in-flight-sweep', maxHits: count, reason: GENERATED_REASON });
    }
    inFlight++;
  }
  emitted.sort(entryCmp);
  writeOut(JSON.stringify(emitted, null, 2) + '\n');
  summary.hits = makeCensus();
  summary.emitted = { view: 'baseline', out: OUT, entries: emitted.length, inFlight, carried: permanent.length };
} else {
  // Verdict view: lint, --json and --emit-hits all see the same coverage;
  // only the rendering differs per mode.
  const view = evaluate(existing);
  const violations = wlInvalid.concat(view.violations);
  for (const h of hits) {
    if (h.registered) continue;
    if (view.cappedBroken.has(h.path)) continue; // entry-level report already covers it
    violations.push({ type: 'ai-trace-unregistered', path: h.path, line: h.line, tier: h.tier, matched: h.matched });
  }
  summary.violations = violations;
  summary.registeredHits = hits.filter((h) => h.registered).length;
  summary.whitelistEntries = existing.length;
  summary.hits = makeCensus();
  if (MODE === 'emit-hits') {
    writeOut(JSON.stringify(summary.hits, null, 2) + '\n');
    summary.emitted = { view: 'hits', out: OUT, records: summary.hits.length };
  }
}

try { fs.writeFileSync(RESULT, JSON.stringify(summary) + '\n'); }
catch (e) { die('cannot write result file: ' + e.message); }
NODE_EOF

result="$tmp/result.json"
if ! node "$tmp/helper.cjs" "$list" "$MODE" "$WL_ARG" "$OUT" "$result"; then
  exit 1
fi

if [ "$MODE" = "emit-hits" ] || [ "$MODE" = "emit-baseline" ]; then
  node -e '
    const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const e = d.emitted;
    if (e.out === "-") console.error("ℹ ai-trace lint: emitted " + e.view + " view to stdout");
    else console.log("ℹ ai-trace lint: emitted " + e.view + " view to " + e.out);
  ' "$result"
  exit 0
fi

read -r vcount scanned_n goscount ta tb < <(
  # trailing newline is required: read returns non-zero (and set -e aborts)
  # when EOF is reached without one
  node -e '
    const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write([d.violations.length, d.scannedFiles, d.gosAnchorHits, d.tierA, d.tierB].join(" ") + "\n");
  ' "$result"
)

if [ "$MODE" = "json" ]; then
  node -e '
    const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(JSON.stringify(d.violations, null, 2) + "\n");
  ' "$result"
else
  if [ "$vcount" -gt 0 ]; then
    node -e '
      const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      for (const v of d.violations) {
        if (v.type === "ai-trace-unregistered") console.log("✗ ai-trace: " + v.path + ":" + v.line + " [tier " + v.tier + "] " + v.matched);
        else console.log("✗ ai-trace whitelist: " + v.type + " " + v.path + (v.line ? ":" + v.line : "") + " — " + v.detail);
      }
    ' "$result"
    echo "✗ ai-trace lint: $vcount violation(s) — tier A: $ta, tier B: $tb (scanned=$scanned_n tracked file(s))" >&2
  else
    reg_n=$(node -e 'const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); process.stdout.write(String(d.registeredHits));' "$result")
    wl_n=$(node -e 'const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); process.stdout.write(String(d.whitelistEntries));' "$result")
    echo "✓ ai-trace lint: $scanned_n tracked file(s) scanned, 0 violation(s), $reg_n hit(s) registered ($wl_n whitelist entries)"
  fi
  echo "ℹ ai-trace lint: $goscount anchor hit(s) under .gos/ (carve-out layer — visible debt, not violations)"
fi

[ "$vcount" -eq 0 ]
