#!/usr/bin/env bash
# cjk-lint — repo Englishization boundary check.
#
# Every git-tracked file must be free of CJK text unless the hit is covered by
# the machine-readable whitelist (default: .gos/cjk-whitelist.json).
# The whitelist doubles as the migration progress tracker, so it stays green
# while module batches land.
#
# Fail-closed in every direction:
#   - unlisted CJK hit          -> exit 1
#   - whitelist entry matching no tracked file (ghost) -> exit 1
#   - whitelist missing / unparsable / non-ASCII -> exit 1
#   - internal error (git failure, unreadable tracked file) -> exit 1
#
# Usage:
#   cjk-lint.sh [--whitelist <path>] [--json]
#     --whitelist <path>  whitelist location (default .gos/cjk-whitelist.json);
#                         relative paths resolve against the repo root
#     --json              machine mode: violations as a JSON array on stdout,
#                         nothing else; infrastructure errors go to stderr
#
# Exit codes: 0 clean, 1 violations or infrastructure failure.
set -euo pipefail

WHITELIST=".gos/cjk-whitelist.json"
JSON_MODE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --whitelist)
      [ $# -ge 2 ] || { echo "cjk-lint: --whitelist requires a path" >&2; exit 1; }
      WHITELIST="$2"; shift 2 ;;
    --json) JSON_MODE=1; shift ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "cjk-lint: unknown argument: $1" >&2; exit 1 ;;
  esac
done

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "cjk-lint: not inside a git work tree — refusing to run (fail-closed)" >&2
  exit 1
}
cd "$root"

case "$WHITELIST" in
  /*) ;;
  *) WHITELIST="$root/$WHITELIST" ;;
esac
[ -f "$WHITELIST" ] || { echo "cjk-lint: whitelist missing: $WHITELIST (fail-closed)" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Wide CJK class: CJK radicals through unified ideographs, fullwidth forms,
# CJK punctuation. grep -P over per-file content; -I skips binary files.
CJK_GREP='[\x{2e80}-\x{9fff}\x{ff00}-\x{ffef}\x{3000}-\x{303f}]'

list="$tmp/files"
hits="$tmp/hits"
: > "$hits"
git ls-files -z > "$list" || { echo "cjk-lint: git ls-files failed (fail-closed)" >&2; exit 1; }

scanned=0
hitcount=0
while IFS= read -r -d '' f; do
  scanned=$((scanned + 1))
  out=$(grep -nHIP -I -- "$CJK_GREP" "$f" 2>/dev/null) && rc=0 || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "cjk-lint: cannot read tracked file: $f (fail-closed)" >&2
    exit 1
  fi
  [ -z "$out" ] && continue
  while IFS= read -r l; do
    rest=${l#*:}
    no=${rest%%:*}
    text=${rest#*:}
    text=${text//$'\t'/ }
    text=${text%$'\r'}
    printf '%s\t%s\t%s\n' "$f" "$no" "$text" >> "$hits"
    hitcount=$((hitcount + 1))
  done <<< "$out"
done < "$list"

# Whitelist semantics live in node (JSON + glob matching + sha256 pin check);
# node is a hard dependency of this repo (the gate itself runs on it).
cat > "$tmp/helper.cjs" <<'NODE_EOF'
'use strict';
const fs = require('fs');
const { execFileSync } = require('child_process');
const crypto = require('crypto');

const CJK = /[\u2e80-\u9fff\uff00-\uffef\u3000-\u303f]/;
const CATEGORIES = ['sanctioned-zh', 'fixture', 'archive', 'dangling-sha',
  'history-pinned', 'task-artifact', 'machine-exempt', 'in-flight-migration'];

function die(msg) {
  process.stderr.write('cjk-lint: ' + msg + '\n');
  process.exit(3);
}

const wlPath = process.argv[2];
const hitsPath = process.argv[3];
const scanned = parseInt(process.argv[4], 10) || 0;

let raw;
try { raw = fs.readFileSync(wlPath, 'utf8'); }
catch (e) { die('whitelist unreadable: ' + wlPath + ' (' + e.code + ')'); }
if (CJK.test(raw)) die('whitelist itself contains CJK characters — entries and reasons must be pure ASCII English');
let wl;
try { wl = JSON.parse(raw); }
catch (e) { die('whitelist is not valid JSON: ' + e.message); }
if (!Array.isArray(wl) || wl.length === 0) die('whitelist must be a non-empty JSON array');

for (const e of wl) {
  const at = (e && e.path) ? '"' + e.path + '"' : '(malformed entry)';
  if (!e || typeof e !== 'object' || Array.isArray(e)) die('whitelist entry is not an object: ' + at);
  if (typeof e.path !== 'string' || !e.path.trim()) die('whitelist entry missing "path"');
  if (!CATEGORIES.includes(e.category)) die('whitelist entry ' + at + ' has unknown category: ' + String(e.category));
  if (typeof e.reason !== 'string' || e.reason.trim().length < 8) die('whitelist entry ' + at + ' needs a meaningful English "reason"');
  if (e.pin !== undefined) {
    const p = e.pin;
    if (!p || typeof p !== 'object' || Array.isArray(p) || p.type !== 'changes-history-boundary') {
      die('pin on ' + at + ' must be {"type":"changes-history-boundary",...}');
    }
    if (!Number.isInteger(p.minLine) || p.minLine < 1) die('pin.minLine on ' + at + ' must be a positive integer');
    if (typeof p.regionSha256 !== 'string' || !/^[0-9a-f]{64}$/.test(p.regionSha256)) {
      die('pin.regionSha256 on ' + at + ' must be a 64-char hex sha256');
    }
  }
}

let tracked;
try {
  tracked = execFileSync('git', ['ls-files', '-z'], { maxBuffer: 64 * 1024 * 1024 })
    .toString().split('\0').filter(Boolean);
} catch (e) { die('git ls-files failed: ' + e.message); }

// Whitelist paths are literals or globs; "*" and "**" both match any run of
// characters (python-fnmatch style), everything else is matched literally.
const regexes = wl.map((e) => {
  const esc = e.path.replace(/[.+?^${}()|[\]\\]/g, '\\$&').split('*').join('\u0000');
  return new RegExp('^' + esc.split('\u0000').join('.*') + '$');
});

function firstMatch(p) {
  for (let i = 0; i < wl.length; i++) if (regexes[i].test(p)) return wl[i];
  return null;
}

// Hygiene: every whitelist entry must cover at least one tracked file —
// a ghost entry means the tracked tree drifted away from the whitelist.
const ghosts = [];
for (let i = 0; i < wl.length; i++) {
  let ok = false;
  for (const t of tracked) { if (regexes[i].test(t)) { ok = true; break; } }
  if (!ok) ghosts.push(wl[i].path);
}

// History-boundary pin: for a newest-first sealed changelog, lines at or below
// pin.minLine (higher line numbers) are the frozen history; the region hash
// detects any edit inside the frozen region or a shifted boundary.
function verifyPin(entry) {
  let content;
  try { content = fs.readFileSync(entry.path, 'utf8'); }
  catch (e) { return 'pinned file unreadable (' + e.code + ')'; }
  const lines = content.split('\n');
  if (entry.pin.minLine > lines.length) {
    return 'pin.minLine ' + entry.pin.minLine + ' is beyond EOF (' + lines.length + ' lines) — boundary drifted; restore the file or re-pin consciously';
  }
  const region = lines.slice(entry.pin.minLine - 1).join('\n');
  const sha = crypto.createHash('sha256').update(region).digest('hex');
  if (sha !== entry.pin.regionSha256) {
    return 'frozen history region sha256 mismatch — the pinned region changed or the boundary shifted; restore the file or re-pin consciously';
  }
  return null;
}

const violations = [];
const pinVerified = new Set();
const hitLines = fs.readFileSync(hitsPath, 'utf8').split('\n').filter(Boolean);
for (const hl of hitLines) {
  const t1 = hl.indexOf('\t');
  const t2 = hl.indexOf('\t', t1 + 1);
  if (t1 < 0 || t2 < 0) die('internal error: malformed hit record (fail-closed)');
  const p = hl.slice(0, t1);
  const line = parseInt(hl.slice(t1 + 1, t2), 10);
  const excerpt = hl.slice(t2 + 1);
  if (!Number.isInteger(line) || line < 1) die('internal error: unparsable line number in hit record (fail-closed)');
  const entry = firstMatch(p);
  if (!entry) { violations.push({ type: 'cjk-unlisted', path: p, line, excerpt }); continue; }
  if (!entry.pin) continue;
  if (!pinVerified.has(entry.path)) {
    pinVerified.add(entry.path);
    const err = verifyPin(entry);
    if (err) violations.push({ type: 'history-pin-drift', path: entry.path, line: 0, excerpt: err });
  }
  if (line < entry.pin.minLine) {
    violations.push({
      type: 'cjk-outside-pinned-history',
      path: p,
      line,
      excerpt,
      detail: 'line ' + line + ' is above the history boundary (minLine ' + entry.pin.minLine + ') — only the frozen region may contain CJK',
    });
  }
}
for (const g of ghosts) {
  violations.push({ type: 'ghost-whitelist-entry', path: g, line: 0, excerpt: 'whitelist entry matches no tracked file (ghost path)' });
}

process.stdout.write(JSON.stringify({
  violations,
  scannedFiles: scanned,
  trackedFiles: tracked.length,
  cjkHits: hitLines.length,
  entries: wl.length,
}) + '\n');
NODE_EOF

result="$tmp/result.json"
if ! node "$tmp/helper.cjs" "$WHITELIST" "$hits" "$scanned" > "$result"; then
  exit 1
fi

read -r vcount scanned_n tracked_n hits_n entries_n < <(
  # trailing newline is required: read returns non-zero (and set -e aborts)
  # when EOF is reached without one
  node -e '
    const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write([d.violations.length, d.scannedFiles, d.trackedFiles, d.cjkHits, d.entries].join(" ") + "\n");
  ' "$result"
)

if [ "$JSON_MODE" -eq 1 ]; then
  node -e '
    const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write(JSON.stringify(d.violations, null, 2) + "\n");
  ' "$result"
else
  if [ "$vcount" -gt 0 ]; then
    node -e '
      const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      for (const v of d.violations) {
        if (v.type === "cjk-unlisted") console.log("✗ CJK text not whitelisted: " + v.path + ":" + v.line + ": " + v.excerpt);
        else if (v.type === "cjk-outside-pinned-history") console.log("✗ CJK above history pin: " + v.path + ":" + v.line + " — " + v.detail);
        else if (v.type === "ghost-whitelist-entry") console.log("✗ ghost whitelist entry (matches no tracked file): " + v.path);
        else console.log("✗ " + v.type + ": " + v.path + ": " + v.excerpt);
      }
    ' "$result"
  fi
  if [ "$vcount" -eq 0 ]; then
    echo "✓ cjk lint: $scanned_n tracked file(s) scanned, $hits_n CJK line(s), all whitelisted ($entries_n whitelist entries)"
  else
    echo "✗ cjk lint: $vcount violation(s) (scanned=$scanned_n tracked=$tracked_n cjkHits=$hits_n entries=$entries_n)" >&2
  fi
fi

[ "$vcount" -eq 0 ]
