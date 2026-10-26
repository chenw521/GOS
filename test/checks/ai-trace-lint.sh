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
# Fail-closed in every direction:
#   - anchor hit outside a carve-out   -> exit 1
#   - not inside a git work tree       -> exit 1
#   - internal error (git failure, unreadable tracked file) -> exit 1
#
# Usage:
#   ai-trace-lint.sh [--json]
#     --json              machine mode: violations as a JSON array on stdout,
#                         nothing else; infrastructure errors go to stderr
#
# Exit codes: 0 clean, 1 violations or infrastructure failure.
set -euo pipefail

JSON_MODE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON_MODE=1; shift ;;
    -h|--help) sed -n '2,39p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "ai-trace-lint: unknown argument: $1" >&2; exit 1 ;;
  esac
done

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "ai-trace-lint: not inside a git work tree — refusing to run (fail-closed)" >&2
  exit 1
}
cd "$root"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Bash lists tracked files only; every classification and pattern decision
# lives in the node helper below (no grep dialect dependence).
list="$tmp/files"
git ls-files -z > "$list" || { echo "ai-trace-lint: git ls-files failed (fail-closed)" >&2; exit 1; }

cat > "$tmp/helper.cjs" <<'NODE_EOF'
'use strict';
const fs = require('fs');

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
try { listBuf = fs.readFileSync(process.argv[2]); }
catch (e) { die('tracked file list unreadable: ' + e.message); }
const files = listBuf.toString('utf8').split('\0').filter(Boolean);

// Hit census records: {path, line, tier, matched}. Whitelist filtering will
// sit between this census and the violations view.
const hits = [];
let gosAnchorHits = 0;
let tierA = 0;
let tierB = 0;

function record(path, line, tier, matched) {
  if (path.startsWith('.gos/')) { gosAnchorHits++; return; }
  hits.push({ path, line, tier, matched });
  if (tier === 'A') tierA++; else tierB++;
}

for (const p of files) {
  // Path carve-outs: the changelog layers are not scanned at all; .gos/**
  // is scanned for the sidecar debt metric only (record() drops the hit
  // from the violation set).
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

// Pre-whitelist stage: every census hit is a violation. The hits census and
// the sidecar metric ride along so later machine views extend this without
// rescanning.
process.stdout.write(JSON.stringify({
  violations: hits,
  hits,
  scannedFiles: files.length,
  tierA,
  tierB,
  gosAnchorHits,
}) + '\n');
NODE_EOF

result="$tmp/result.json"
if ! node "$tmp/helper.cjs" "$list" > "$result"; then
  exit 1
fi

read -r vcount scanned_n goscount ta tb < <(
  # trailing newline is required: read returns non-zero (and set -e aborts)
  # when EOF is reached without one
  node -e '
    const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    process.stdout.write([d.violations.length, d.scannedFiles, d.gosAnchorHits, d.tierA, d.tierB].join(" ") + "\n");
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
        console.log("✗ ai-trace: " + v.path + ":" + v.line + " [tier " + v.tier + "] " + v.matched);
      }
    ' "$result"
    echo "✗ ai-trace lint: $vcount violation(s) — tier A: $ta, tier B: $tb (scanned=$scanned_n tracked file(s))" >&2
  else
    echo "✓ ai-trace lint: $scanned_n tracked file(s) scanned, 0 violation(s)"
  fi
  echo "ℹ ai-trace lint: $goscount anchor hit(s) under .gos/ (carve-out layer — visible debt, not violations)"
fi

[ "$vcount" -eq 0 ]
