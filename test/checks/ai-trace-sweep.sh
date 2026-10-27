#!/usr/bin/env bash
# ai-trace-sweep — the only legal batch runner for anchor-comment sweeps.
#
# A sweep batch never edits the tree by hand: the operator records a plan
# (the harness snapshots every lint-flagged line in the batch and refuses
# everything else), applies edits, then runs verify. Verify enforces the
# batch discipline mechanically:
#   - changed lines (against HEAD) must fall inside the precomputed
#     allowed set — modify or delete a flagged line, nothing else;
#     insertions and binary edits are refused outright
#   - no new anchor may appear anywhere in the batch (codemod pollution
#     guard); every deleted anchor id must reconcile into the tracked
#     ledger, which is re-parsed after the append (silent-miss guard)
#   - the whitelist is regenerated through the lint's baseline emitter,
#     proven byte-stable by a second regeneration, and may only shrink
#   - the post-sweep lint must exit clean over the whole tree
#   - content, whitelist and ledger are staged together in one index
#
# Operator flow (two-step, explicit):
#   bash test/checks/ai-trace-sweep.sh plan <batch-file>
#     ...apply edits to the printed lines only (or run unlock to abandon)...
#   bash test/checks/ai-trace-sweep.sh verify <batch-file>
#   bash test/checks/ai-trace-sweep.sh unlock     # drop an abandoned session
#
# Batch file contract: one repo-relative tracked path per line; blank
# lines and lines starting with '#' are ignored. The batch label is the
# file basename without its extension; the label rides in the ledger.
#
# Tracked sidecar ledger (.gos/ai-trace-sweep-ledger.ndjson): one JSON
# object per line, appended by verify only —
#   {"batch":label,"ts":utc-iso,"path":member,"ids":[deleted anchor ids]}
# The CHANGELOG itself never carries ids: the operator lands one
# validator-clean single-sentence [Unreleased] entry (category verb plus
# decision/requirement trace refs only) per batch; when the repo CLI is
# present verify runs its changelog lint as a blocking check.
#
# Serial discipline: a lockfile under .gos/logs/ refuses a second session
# while one is open; a stale session (clean worktree) is recovered with a
# notice; an open session over a dirty tree must be verified or unlocked.
#
# This script is the only sanctioned consumer of the lint's hit-census
# and baseline emitters. It resolves the lint as its sibling file and the
# repository through git, so it runs unchanged inside any git work tree
# (the embedded self-test builds a disposable sandbox repo this way).
#
# Usage:
#   ai-trace-sweep.sh plan <batch-file>
#   ai-trace-sweep.sh verify <batch-file>
#   ai-trace-sweep.sh unlock
#   ai-trace-sweep.sh --self-test
#   ai-trace-sweep.sh -h | --help
#
# Fail-closed: every guard failure aborts the batch, restores the batch
# members, whitelist and ledger to HEAD, drops the session and exits
# nonzero. No partial batch is ever left staged.
set -euo pipefail

WL_REL=".gos/ai-trace-whitelist.json"
LEDGER_REL=".gos/ai-trace-sweep-ledger.ndjson"
LOGS_REL=".gos/logs"
SESS_REL="$LOGS_REL/ai-trace-sweep"
LOCK_REL="$LOGS_REL/ai-trace-sweep.lock"

die() { echo "✗ ai-trace-sweep: $*" >&2; exit 1; }
info() { echo "ℹ ai-trace-sweep: $*"; }

resolve_root() {
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null) ||
    die "not inside a git work tree — refusing to run (fail-closed)"
  SESS="$ROOT/$SESS_REL"
  LOCK="$ROOT/$LOCK_REL"
  LOGS="$ROOT/$LOGS_REL"
}

resolve_lint() {
  local dir
  dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
  LINT="$dir/ai-trace-lint.sh"
  [ -f "$LINT" ] || die "cannot find the ai-trace lint next to this script: $LINT"
  command -v node >/dev/null || die "node is required (the lint and this harness both need it)"
}

# Machine-zone noise filter: .gos/logs is a machine-local zone and may be
# visible to git status in repositories without ignore rules for it.
filtered_status() {
  git --no-pager -C "$ROOT" status --porcelain | grep -v '\.gos/logs/' || true
}

worktree_clean() { [ -z "$(filtered_status)" ]; }

drop_session() { rm -rf "$SESS"; rm -f "$LOCK"; }

acquire_lock() {
  mkdir -p "$LOGS"
  if ( set -o noclobber; : > "$LOCK" ) 2>/dev/null; then
    printf 'session=%s-%s started=%s\n' \
      "$(date -u +%Y%m%dT%H%M%SZ)" "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$LOCK"
    return 0
  fi
  if [ -f "$SESS/state.json" ]; then
    if worktree_clean; then
      info "stale plan session found with a clean worktree — recovering it"
      drop_session
    else
      die "a plan session is open over a dirty worktree — run verify <batch-file> to finish it or unlock to abandon it"
    fi
  else
    info "orphan lockfile found with no session state — removing it"
    rm -f "$LOCK"
  fi
  ( set -o noclobber; : > "$LOCK" ) 2>/dev/null ||
    die "a concurrent sweep session holds the lock — refusing to run"
  printf 'session=%s-%s started=%s\n' \
    "$(date -u +%Y%m%dT%H%M%SZ)" "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$LOCK"
}

parse_batch() {
  local batch="$1" line
  [ -f "$batch" ] || die "batch file not found: $batch"
  BATCH_LABEL=$(basename "$batch"); BATCH_LABEL="${BATCH_LABEL%%.*}"
  [ -n "$BATCH_LABEL" ] || die "batch file name yields an empty label"
  : > "$SESS/paths.txt"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in
      /*) die "absolute path in batch file: $line" ;;
      *..*) die "parent-escaping path in batch file: $line" ;;
    esac
    git -C "$ROOT" ls-files --error-unmatch -- "$line" >/dev/null 2>&1 ||
      die "batch member is not git-tracked: $line"
    [ -f "$ROOT/$line" ] || die "batch member is not a readable file: $line"
    printf '%s\n' "$line" >> "$SESS/paths.txt"
  done < "$batch"
  sort -u "$SESS/paths.txt" -o "$SESS/paths.txt"
  [ -s "$SESS/paths.txt" ] || die "batch file lists no member paths"
}

# Shared anchor-token extractor written once per session; both the plan
# snapshot and the verify guards require it so id extraction can never
# drift between the two steps.
write_extract_helper() {
  cat > "$SESS/extract.cjs" <<'NODE_EOF'
'use strict';
const fs = require('fs');

// Bracket anchors: scan from each '[' to the nearest ']' (or end of line
// when unclosed); the head must match the lint's bracket grammar.
function bracketTokens(text) {
  const out = [];
  const head = /^\[[A-Za-z]+(?:[ -][A-Za-z]+)*[ -]?[0-9\/]/;
  let i = 0;
  while ((i = text.indexOf('[', i)) !== -1) {
    const j = text.indexOf(']', i);
    const cand = j === -1 ? text.slice(i) : text.slice(i, j + 1);
    if (head.test(cand)) out.push(cand);
    i += cand.length || 1;
  }
  return out;
}

const RESIDUAL = [
  /[A-Za-z]+\d+-[A-Za-z]+\d+/g,
  /(?:^|[^A-Za-z])((?:D|R|B|F)-\d+)/g,
  /\bWave\s+\d+\b/g,
  /(?:^|[^A-Za-z])((?:W|T)\d+)\b/g,
];

function tokens(text) {
  const found = bracketTokens(text);
  let rest = text;
  for (const b of found) rest = rest.split(b).join(' ');
  for (const re of RESIDUAL) {
    re.lastIndex = 0;
    let m;
    const hits = [];
    while ((m = re.exec(rest)) !== null) hits.push(m[1] || m[0]);
    if (hits.length) {
      found.push(...hits);
      for (const h of hits) rest = rest.split(h).join(' ');
    }
  }
  return found;
}

module.exports = { tokens };
NODE_EOF
}

emit_hits() {
  local out="$1"
  bash "$LINT" --emit-hits "$out" >/dev/null ||
    die "the lint refused to emit its hit census (infrastructure failure)"
}

emit_baseline() {
  local out="$1"
  bash "$LINT" --emit-baseline "$out" >/dev/null ||
    die "the lint refused to emit the whitelist baseline (infrastructure failure)"
}

# ---------------------------------------------------------------------------
# plan <batch-file>
# ---------------------------------------------------------------------------
cmd_plan() {
  [ "$#" -eq 1 ] || die "usage: ai-trace-sweep.sh plan <batch-file>"
  resolve_root
  resolve_lint
  acquire_lock
  mkdir -p "$SESS"

  if ! worktree_clean; then
    drop_session
    die "worktree is not clean — commit or stash everything, then re-run plan"
  fi

  local batch="$1"
  BATCH_REL=$(cd -- "$(dirname -- "$batch")" && pwd)/$(basename -- "$batch")
  BATCH_HASH=$(sha256sum "$batch" | cut -d' ' -f1)
  HEAD_SHA=$(git -C "$ROOT" rev-parse HEAD) || { drop_session; die "HEAD unreadable"; }
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  parse_batch "$batch"

  if ! emit_hits "$SESS/hits.json"; then drop_session; die "hit census failed"; fi

  write_extract_helper

  node - "$SESS/hits.json" "$SESS/paths.txt" "$ROOT" "$SESS/state.json" \
       "$BATCH_LABEL" "$BATCH_REL" "$BATCH_HASH" "$HEAD_SHA" "$TS" <<'NODE_EOF' || { drop_session; die "state snapshot failed"; }
'use strict';
const fs = require('fs');
const [hitsF, pathsF, root, out, label, batchRel, batchHash, head, ts] = process.argv.slice(2);
const { tokens } = require(root + '/.gos/logs/ai-trace-sweep/extract.cjs');
const hits = JSON.parse(fs.readFileSync(hitsF, 'utf8'));
const paths = fs.readFileSync(pathsF, 'utf8').split('\n').filter(Boolean);
const pset = new Set(paths);
const byKey = new Map();
for (const h of hits) {
  if (!pset.has(h.path)) continue;
  const key = h.path + '\u0000' + h.line;
  if (!byKey.has(key)) byKey.set(key, { path: h.path, line: h.line, tier: h.tier, matched: h.matched });
}
const preHits = [];
const fileCache = new Map();
for (const rec of byKey.values()) {
  if (!fileCache.has(rec.path)) {
    fileCache.set(rec.path, fs.readFileSync(root + '/' + rec.path, 'utf8').split('\n'));
  }
  const text = fileCache.get(rec.path)[rec.line - 1] || '';
  rec.text = text;
  rec.tokens = tokens(text);
  preHits.push(rec);
}
preHits.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : a.line - b.line));
const allowed = {};
for (const rec of preHits) {
  (allowed[rec.path] = allowed[rec.path] || []).push(rec.line);
}
const state = { label, batchFile: batchRel, batchHash, head, startedIso: ts, preHits, allowed };
fs.writeFileSync(out, JSON.stringify(state, null, 2) + '\n');
NODE_EOF

  # Machine-artifact backups so any later abort can restore byte-exactly.
  # Symlinks are never dereferenced (a copy would follow the target).
  if [ -L "$ROOT/$WL_REL" ] || [ -f "$ROOT/$WL_REL" ]; then
    if [ ! -L "$ROOT/$WL_REL" ]; then cp "$ROOT/$WL_REL" "$SESS/whitelist.backup"; fi
    : > "$SESS/had-whitelist"
  fi
  if [ -L "$ROOT/$LEDGER_REL" ] || [ -e "$ROOT/$LEDGER_REL" ]; then
    if [ ! -L "$ROOT/$LEDGER_REL" ] && [ -f "$ROOT/$LEDGER_REL" ]; then
      cp "$ROOT/$LEDGER_REL" "$SESS/ledger.backup"
    fi
    : > "$SESS/had-ledger"
  fi

  echo "✓ plan recorded — batch '$BATCH_LABEL' with $(wc -l < "$SESS/paths.txt") member file(s)"
  node - "$SESS/state.json" <<'NODE_EOF'
'use strict';
const st = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
for (const p of Object.keys(st.allowed).sort()) {
  console.log('  editable ' + p + ' — line(s) ' + st.allowed[p].join(', ') + ' (' + st.allowed[p].length + ' hit line(s))');
}
NODE_EOF
  echo "  next: edit ONLY the listed lines (modify or delete; inserting lines is refused),"
  echo "        then run: bash $0 verify <batch-file>"
  echo "        abandon: bash $0 unlock"
  if [ -f "$ROOT/bin/gos.cjs" ]; then
    if ! (cd "$ROOT" && node bin/gos.cjs changelog lint >/dev/null 2>&1); then
      info "changelog lint is currently red — the batch must land a validator-clean single-sentence [Unreleased] entry before verify can pass"
    fi
  fi
}

# ---------------------------------------------------------------------------
# verify <batch-file>
# ---------------------------------------------------------------------------
restore_member() { # path relative to root
  git -C "$ROOT" checkout HEAD -- "$1" 2>/dev/null || true
}

restore_artifact() { # tracked → checkout; new/untracked → remove
  local p="$1"
  if git -C "$ROOT" ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
    git -C "$ROOT" checkout HEAD -- "$p" 2>/dev/null || true
  else
    rm -f "$ROOT/$p"
  fi
}

restore_all() {
  local p
  while IFS= read -r p; do restore_member "$p"; done < "$SESS/paths.txt"
  if [ -f "$SESS/had-whitelist" ]; then
    restore_artifact "$WL_REL"
  else
    rm -f "$ROOT/$WL_REL"
  fi
  if [ -f "$SESS/had-ledger" ]; then
    restore_artifact "$LEDGER_REL"
  else
    rm -f "$ROOT/$LEDGER_REL"
  fi
}

abort_restore() { # every guard failure path: pristine tree, dropped session
  restore_all
  drop_session
}

cmd_verify() {
  [ "$#" -eq 1 ] || die "usage: ai-trace-sweep.sh verify <batch-file>"
  resolve_root
  resolve_lint
  [ -f "$SESS/state.json" ] || die "no plan session — run plan <batch-file> first"

  local batch="$1"
  local hash; hash=$(sha256sum "$batch" | cut -d' ' -f1)
  local label; label=$(basename "$batch"); label="${label%%.*}"
  node - "$SESS/state.json" "$hash" "$label" <<'NODE_EOF' || die "session does not match this batch — re-run plan"
'use strict';
const st = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
if (st.batchHash !== process.argv[3]) { process.stderr.write('batch file changed since plan\n'); process.exit(1); }
if (st.label !== process.argv[4]) { process.stderr.write('batch label differs from the planned session\n'); process.exit(1); }
NODE_EOF

  local head_now; head_now=$(git -C "$ROOT" rev-parse HEAD)
  if [ "$head_now" != "$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).head)' "$SESS/state.json")" ]; then
    drop_session
    die "HEAD moved since plan — re-run plan against the new baseline"
  fi

  mapfile -t PATHS < "$SESS/paths.txt"

  # Dirt gate: only batch members, the changelog and the machine zone may
  # differ from HEAD when verify starts.
  local allow=" CHANGELOG.md "
  local p
  for p in "${PATHS[@]}"; do allow="$allow$p "; done
  local dirt; dirt=$(filtered_status)
  local bad_paths=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    local rp=${line:3}
    case "$allow" in *" $rp "*) ;; *) bad_paths="$bad_paths $rp" ;; esac
  done <<< "$dirt"
  if [ -n "$bad_paths" ]; then
    die "worktree holds changes outside the batch (resolving to:$bad_paths) — clean them or unlock, then re-plan"
  fi

  git --no-pager -C "$ROOT" diff HEAD -U0 -- "${PATHS[@]}" > "$SESS/diff.txt"
  [ -s "$SESS/diff.txt" ] || die "no edits detected for the batch — apply the planned edits, then verify again"

  if ! emit_hits "$SESS/post-hits.json"; then die "post-edit hit census failed"; fi

  # Guards: allowed-set containment, insertion refusal, new-anchor refusal,
  # deleted-id extraction — all in one pass over the diff plus both censuses.
  node - "$SESS/state.json" "$SESS/paths.txt" "$SESS/diff.txt" "$SESS/post-hits.json" "$ROOT" "$SESS/verdict.json" <<'NODE_EOF' || { abort_restore; die "guard evaluation failed"; }
'use strict';
const fs = require('fs');
const [stateF, pathsF, diffF, postF, root, outF] = process.argv.slice(2);
const { tokens } = require(root + '/.gos/logs/ai-trace-sweep/extract.cjs');
const state = JSON.parse(fs.readFileSync(stateF, 'utf8'));
const pset = new Set(fs.readFileSync(pathsF, 'utf8').split('\n').filter(Boolean));
const diffText = fs.readFileSync(diffF, 'utf8');

// Parse the unified diff (zero context): file headers only count directly
// after a 'diff --git' line so content lines starting with markers can
// never impersonate them.
const outOfSet = [];
const removedByPath = {};
let path = null;
let expectHeaders = false;
let orig = 0, rem = 0, add = 0, inHunk = false;
const flushHunk = () => {
  if (!inHunk) return;
  if (add > rem) outOfSet.push({ path: path || '', line: 0, reason: 'insertion — added lines exceed removed lines' });
  inHunk = false;
};
for (const raw of diffText.split('\n')) {
  if (raw.startsWith('diff --git ')) { flushHunk(); path = null; expectHeaders = true; continue; }
  if (expectHeaders && raw.startsWith('--- ')) { continue; }
  if (expectHeaders && raw.startsWith('+++ ')) { path = raw.slice(6); expectHeaders = false; continue; }
  if (raw.startsWith('Binary files')) { flushHunk(); outOfSet.push({ path: path || '', line: 0, reason: 'binary content change' }); path = null; continue; }
  if (raw.startsWith('@@')) {
    flushHunk();
    const m = /^@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@/.exec(raw);
    if (!m) { outOfSet.push({ path: path || '', line: 0, reason: 'unparseable hunk header' }); continue; }
    orig = parseInt(m[1], 10); rem = 0; add = 0; inHunk = true; continue;
  }
  if (!inHunk || !path) { continue; }
  if (raw.startsWith('-')) {
    rem++;
    (removedByPath[path] = removedByPath[path] || []).push(orig);
    orig++;
  } else if (raw.startsWith('+')) {
    add++;
  }
}
flushHunk();

const allowed = new Map();
for (const h of state.preHits) {
  if (!allowed.has(h.path)) allowed.set(h.path, new Set());
  allowed.get(h.path).add(h.line);
}
for (const [p, lines] of Object.entries(removedByPath)) {
  for (const ln of lines) {
    const okSet = allowed.get(p);
    if (!okSet || !okSet.has(ln)) outOfSet.push({ path: p, line: ln, reason: 'line was never flagged by the lint' });
  }
}

// Token bags per path: pre from the plan snapshot, post from the current
// content of every hit line the lint reports now.
const bag = (m, p, t) => { (m[p] = m[p] || new Map()); m[p].set(t, (m[p].get(t) || 0) + 1); };
const preBag = {};
for (const h of state.preHits) for (const t of h.tokens) bag(preBag, h.path, t);
const postBag = {};
const postHits = JSON.parse(fs.readFileSync(postF, 'utf8'));
const seen = new Set();
const cache = new Map();
for (const h of postHits) {
  if (!pset.has(h.path)) continue;
  const key = h.path + '\u0000' + h.line;
  if (seen.has(key)) continue;
  seen.add(key);
  if (!cache.has(h.path)) cache.set(h.path, fs.readFileSync(root + '/' + h.path, 'utf8').split('\n'));
  const text = cache.get(h.path)[h.line - 1] || '';
  for (const t of tokens(text)) bag(postBag, h.path, t);
}
const newAnchors = [];
const deletedByPath = {};
const paths = new Set([...Object.keys(preBag), ...Object.keys(postBag)]);
for (const p of paths) {
  const a = preBag[p] || new Map();
  const b = postBag[p] || new Map();
  for (const [t, n] of b) {
    const left = n - (a.get(t) || 0);
    if (left > 0) newAnchors.push({ path: p, token: t });
  }
  const gone = [];
  for (const [t, n] of a) {
    const left = n - (b.get(t) || 0);
    for (let k = 0; k < left; k++) gone.push(t);
  }
  if (gone.length) deletedByPath[p] = gone.sort();
}
fs.writeFileSync(outF, JSON.stringify({ outOfSet, newAnchors, deletedByPath }, null, 2) + '\n');
NODE_EOF

  if [ -n "$(node -e 'const v=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(v.outOfSet.length?"x":"")' "$SESS/verdict.json")" ]; then
    node - "$SESS/verdict.json" <<'NODE_EOF'
'use strict';
const v = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
for (const o of v.outOfSet) {
  console.error('  ' + (o.line ? o.path + ':' + o.line : o.path) + ' — ' + o.reason);
}
NODE_EOF
    abort_restore
    die "sweep abort: out-of-set edit — only pre-flagged lines may change; batch restored"
  fi

  if [ -n "$(node -e 'const v=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(v.newAnchors.length?"x":"")' "$SESS/verdict.json")" ]; then
    node - "$SESS/verdict.json" <<'NODE_EOF'
'use strict';
const v = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
for (const n of v.newAnchors) console.error('  ' + n.path + ' — ' + n.token);
NODE_EOF
    abort_restore
    die "sweep abort: new anchor introduced — sweeps may only remove or rewrite flagged lines; batch restored"
  fi

  # Ledger reconciliation: append one record per path with deleted ids,
  # then re-parse the whole ledger and prove the coverage (silent-miss guard).
  local has_deleted
  has_deleted=$(node -e 'const v=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));process.stdout.write(Object.keys(v.deletedByPath).length?"x":"")' "$SESS/verdict.json")
  if [ -n "$has_deleted" ]; then
    mkdir -p "$(dirname -- "$ROOT/$LEDGER_REL")"
    node - "$SESS/verdict.json" "$label" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SESS/ledger.lines" <<'NODE_EOF' || { abort_restore; die "sweep abort: ledger reconciliation failed — record build error"; }
'use strict';
const v = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
for (const p of Object.keys(v.deletedByPath).sort()) {
  console.log(JSON.stringify({ batch: process.argv[3], ts: process.argv[4], path: p, ids: v.deletedByPath[p] }));
}
NODE_EOF
    if ! cat "$SESS/ledger.lines" >> "$ROOT/$LEDGER_REL" 2> "$SESS/append.err"; then
      abort_restore
      die "sweep abort: ledger reconciliation failed — cannot append the record (entry missing): $(tr '\n' ' ' < "$SESS/append.err")"
    fi
    node - "$ROOT/$LEDGER_REL" "$SESS/verdict.json" "$label" <<'NODE_EOF' || { abort_restore; die "sweep abort: ledger reconciliation failed — ledger invalid or id coverage incomplete (wrong entry)"; }
'use strict';
const fs = require('fs');
const [ledgerF, verdictF, label] = process.argv.slice(2);
const v = JSON.parse(fs.readFileSync(verdictF, 'utf8'));
const raw = fs.readFileSync(ledgerF, 'utf8');
if (raw.length > 0 && !raw.endsWith('\n')) { process.stderr.write('ledger last line lacks a newline\n'); process.exit(1); }
const lines = raw.split('\n').filter((l) => l.length > 0);
const byPath = {};
lines.forEach((l, idx) => {
  let r;
  try { r = JSON.parse(l); } catch (e) { process.stderr.write('ledger line ' + (idx + 1) + ' is not valid JSON\n'); process.exit(1); }
  if (!r || typeof r !== 'object' || Array.isArray(r)) { process.stderr.write('ledger line ' + (idx + 1) + ' is not an object\n'); process.exit(1); }
  const keys = Object.keys(r).sort().join(',');
  if (keys !== 'batch,ids,path,ts') { process.stderr.write('ledger line ' + (idx + 1) + ' has a wrong key set\n'); process.exit(1); }
  if (typeof r.batch !== 'string' || typeof r.ts !== 'string' || typeof r.path !== 'string'
      || !Array.isArray(r.ids) || r.ids.length === 0 || r.ids.some((i) => typeof i !== 'string' || !i)) {
    process.stderr.write('ledger line ' + (idx + 1) + ' has a malformed field\n'); process.exit(1);
  }
  if (r.batch === label) (byPath[r.path] = byPath[r.path] || []).push(...r.ids);
});
for (const p of Object.keys(v.deletedByPath)) {
  const got = (byPath[p] || []).sort();
  const want = v.deletedByPath[p].slice().sort();
  if (got.length !== want.length || got.some((x, i) => x !== want[i])) {
    process.stderr.write('ledger coverage mismatch for ' + p + '\n');
    process.exit(1);
  }
}
NODE_EOF
    info "ledger reconciled: $(wc -l < "$SESS/ledger.lines" | tr -d ' ') record(s) appended under batch '$label'"
  else
    info "no anchor ids deleted in this batch — ledger untouched"
  fi

  # Whitelist regeneration: shrink-only, byte-stable, installed atomically
  # after both properties are proven.
  emit_baseline "$SESS/wl-new.json"
  node - "$ROOT/$WL_REL" "$SESS/wl-new.json" "$SESS/shrink.json" <<'NODE_EOF' || { abort_restore; die "sweep abort: whitelist growth — a batch may only shrink the tracker"; }
'use strict';
const fs = require('fs');
const [oldF, newF, outF] = process.argv.slice(2);
const read = (f) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) { return []; } };
const oldE = read(oldF), newE = read(newF);
const inflight = (es) => es.filter((e) => e.category === 'in-flight-sweep').reduce((a, e) => a + e.maxHits, 0);
const stats = { oldEntries: oldE.length, newEntries: newE.length, oldInflight: inflight(oldE), newInflight: inflight(newE) };
fs.writeFileSync(outF, JSON.stringify(stats));
if (newE.length > oldE.length || inflight(newE) > inflight(oldE)) process.exit(1);
NODE_EOF
  cp "$SESS/wl-new.json" "$ROOT/$WL_REL"
  emit_baseline "$SESS/wl-new2.json"
  cmp -s "$SESS/wl-new.json" "$SESS/wl-new2.json" || { abort_restore; die "sweep abort: whitelist regeneration is not byte-stable"; }

  if ! bash "$LINT" > "$SESS/lint-final.log" 2>&1; then
    cat "$SESS/lint-final.log" >&2
    abort_restore
    die "sweep abort: post-sweep lint failed over the tree"
  fi

  if [ -f "$ROOT/bin/gos.cjs" ]; then
    if ! (cd "$ROOT" && node bin/gos.cjs changelog lint > "$SESS/changelog.log" 2>&1); then
      cat "$SESS/changelog.log" >&2 || true
      abort_restore
      die "sweep abort: changelog lint failed — land one validator-clean single-sentence [Unreleased] entry for this batch, then re-plan and re-apply"
    fi
  fi

  # Stage content, whitelist and ledger as one unit.
  local add_list=("${PATHS[@]}" "$WL_REL")
  if [ -e "$ROOT/$LEDGER_REL" ]; then add_list+=("$LEDGER_REL"); fi
  if [ -n "$(git --no-pager -C "$ROOT" status --porcelain -- CHANGELOG.md)" ]; then
    add_list+=("CHANGELOG.md")
  fi
  git -C "$ROOT" add -- "${add_list[@]}"

  local staged
  staged=$(git --no-pager -C "$ROOT" diff --cached --name-only)
  node - "$SESS/shrink.json" <<'NODE_EOF'
'use strict';
const s = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
console.log('  whitelist: entries ' + s.oldEntries + ' -> ' + s.newEntries + ', in-flight hit count ' + s.oldInflight + ' -> ' + s.newInflight);
NODE_EOF
  drop_session
  echo "✓ sweep batch complete — staged for commit:"
  printf '  %s\n' $staged
  echo "  remember: one validator-clean single-sentence [Unreleased] changelog entry per batch (category verb + decision/requirement trace refs only)"
}

# ---------------------------------------------------------------------------
# unlock
# ---------------------------------------------------------------------------
cmd_unlock() {
  resolve_root
  if [ -d "$SESS" ] || [ -f "$LOCK" ]; then
    rm -rf "$SESS"
    rm -f "$LOCK"
    info "session dropped — the plan snapshot is gone; tracked files were not touched"
  else
    info "no session open — nothing to unlock"
  fi
}

# ---------------------------------------------------------------------------
# --self-test — hermetic sandbox repo, three guard scenarios
# ---------------------------------------------------------------------------
cmd_self_test() {
  local n1=101 n2=102 n3=103 n4=104
  local sb_parent
  resolve_root
  sb_parent="$ROOT"
  SB_TEST="$sb_parent/test-$(date +%Y%m%d-%H%M%S)-ai-trace-sweep-selftest"
  trap 'rm -rf "$SB_TEST"' EXIT
  rm -rf "$SB_TEST"
  mkdir -p "$SB_TEST"

  local lint_src
  lint_src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/ai-trace-lint.sh

  ST_PASS=0; ST_FAIL=0
  st_pass() { echo "  ✓ $1"; ST_PASS=$((ST_PASS + 1)); }
  st_fail() { echo "  ✗ $1"; ST_FAIL=$((ST_FAIL + 1)); }
  expect_zero() { if [ "$2" -eq 0 ]; then st_pass "$1"; else st_fail "$1 (exit $2)"; fi; }
  expect_nonzero() { if [ "$2" -ne 0 ]; then st_pass "$1"; else st_fail "$1 (unexpectedly exited zero)"; fi; }
  expect_contains() {
    if grep -q -- "$3" "$2" 2>/dev/null; then st_pass "$1"; else st_fail "$1 (pattern not found in output)"; fi
  }

  sbgit() { git --no-pager -C "$SB_TEST" "$@"; }
  # All scenario logs live in the sandbox machine zone (gitignored) so the
  # assertions about a pristine tree never see harness chatter.
  local L="$SB_TEST/.gos/logs"
  SWEEP_RC=0
  sbrun() { # capture harness invocation: sbrun <log-name> <args...>
    local log="$1"; shift
    SWEEP_RC=0
    ( cd "$SB_TEST" && bash test/checks/ai-trace-sweep.sh "$@" ) > "$L/$log" 2>&1 || SWEEP_RC=$?
  }

  echo "scenario zero — sandbox fixture repo"
  git -C "$SB_TEST" init -q -b main
  git -C "$SB_TEST" config user.name "sweep self-test"
  git -C "$SB_TEST" config user.email "selftest@example.invalid"
  printf '.gos/logs/\n' > "$SB_TEST/.gitignore"
  mkdir -p "$SB_TEST/test/checks" "$SB_TEST/bin" "$SB_TEST/batches" "$SB_TEST/.gos/logs"
  cp "$lint_src" "$SB_TEST/test/checks/ai-trace-lint.sh"
  cp "$0" "$SB_TEST/test/checks/ai-trace-sweep.sh"

  A1="// [D-${n1}] lineage note - frobnicate the input stream" \
  A2="// ported from the old builder (D-${n2})" \
  A3="// [REVIEW M${n3}] audit marker - map the labels" \
  A4="// [T ${n4}] old task marker - resolve labels" \
  node - "$SB_TEST" <<'NODE_EOF'
'use strict';
const fs = require('fs');
const root = process.argv[2];
const a = process.env;
fs.writeFileSync(root + '/bin/one.cjs', [
  "'use strict';",
  a.A1,
  '// plain purpose comment',
  a.A2,
  'function frobnicate(stream) {',
  '  return stream.trim();',
  '}',
  '',
].join('\n'));
fs.writeFileSync(root + '/bin/two.cjs', [
  "'use strict';",
  a.A3,
  a.A4,
  'function mapLabels(v) {',
  '  return v;',
  '}',
  '',
].join('\n'));
NODE_EOF
  printf 'bin/one.cjs\n' > "$SB_TEST/batches/one-only.txt"
  printf 'bin/one.cjs\nbin/two.cjs\n' > "$SB_TEST/batches/mixed.txt"
  sbgit add -A >/dev/null && sbgit commit -q -m "plant sweep fixtures"
  ( cd "$SB_TEST" && bash test/checks/ai-trace-lint.sh --emit-baseline "$SB_TEST/.gos/ai-trace-whitelist.json" >/dev/null )
  sbgit add .gos/ai-trace-whitelist.json >/dev/null
  sbgit commit -q -m "land generated baseline whitelist"
  local rc=0
  ( cd "$SB_TEST" && bash test/checks/ai-trace-lint.sh >/dev/null 2>&1 ) || rc=1
  expect_zero "baseline lint green in sandbox" "$rc"

  echo "scenario one — out-of-set edit guard trips and restores"
  sbrun s1-plan.log plan batches/one-only.txt
  expect_zero "plan accepts the one-member batch" "$SWEEP_RC"
  CODE_OLD="return stream.trim();" CODE_NEW="return stream.trim() + '!';" \
    node - "$SB_TEST" <<'NODE_EOF'
'use strict';
const fs = require('fs');
const p = process.argv[2] + '/bin/one.cjs';
const t = fs.readFileSync(p, 'utf8');
if (!t.includes(process.env.CODE_OLD)) process.exit(2);
fs.writeFileSync(p, t.replace(process.env.CODE_OLD, process.env.CODE_NEW));
NODE_EOF
  [ $? -eq 0 ] || st_fail "planted out-of-set edit"
  sbrun s1-verify.log verify batches/one-only.txt
  expect_nonzero "verify refuses the out-of-set edit" "$SWEEP_RC"
  expect_contains "refusal names the out-of-set guard" "$L/s1-verify.log" "out-of-set"
  local dirty
  dirty=$(git --no-pager -C "$SB_TEST" status --porcelain | grep -v '\.gos/logs/' || true)
  if [ -z "$dirty" ]; then st_pass "tree restored pristine after the abort"; else st_fail "tree left dirty after the abort: $dirty"; fi
  sbrun s1-again.log verify batches/one-only.txt
  expect_nonzero "aborted session is dropped (second verify fails)" "$SWEEP_RC"
  expect_contains "second verify names the missing session" "$L/s1-again.log" "no plan session"

  echo "scenario two — unreconciled ledger guard trips (corrupt content)"
  printf 'not json {' > "$SB_TEST/.gos/ai-trace-sweep-ledger.ndjson"
  sbgit add .gos/ai-trace-sweep-ledger.ndjson >/dev/null
  sbgit commit -q -m "plant corrupt ledger"
  sbrun s2a-plan.log plan batches/one-only.txt
  expect_zero "plan runs over the corrupt tracked ledger" "$SWEEP_RC"
  B1_OLD="// [D-${n1}] lineage note - frobnicate the input stream" B1_NEW="// frobnicate the input stream" \
  B2_OLD="// ported from the old builder (D-${n2})" B2_NEW="// ported from the old builder" \
    node - "$SB_TEST" <<'NODE_EOF'
'use strict';
const fs = require('fs');
const p = process.argv[2] + '/bin/one.cjs';
let t = fs.readFileSync(p, 'utf8');
if (!t.includes(process.env.B1_OLD) || !t.includes(process.env.B2_OLD)) process.exit(2);
t = t.replace(process.env.B1_OLD, process.env.B1_NEW).replace(process.env.B2_OLD, process.env.B2_NEW);
fs.writeFileSync(p, t);
NODE_EOF
  sbrun s2a-verify.log verify batches/one-only.txt
  expect_nonzero "verify fails on an unparsable ledger line" "$SWEEP_RC"
  expect_contains "failure names the ledger reconciliation guard" "$L/s2a-verify.log" "ledger reconciliation failed"
  dirty=$(git --no-pager -C "$SB_TEST" status --porcelain | grep -v '\.gos/logs/' || true)
  if [ -z "$dirty" ]; then st_pass "tree restored pristine after ledger abort"; else st_fail "tree left dirty after ledger abort: $dirty"; fi
  sbgit rm -q .gos/ai-trace-sweep-ledger.ndjson
  sbgit commit -q -m "remove corrupt ledger"

  echo "scenario two — unreconciled ledger guard trips (missing append)"
  # An unwritable ledger makes the append land nowhere; permission blocks
  # are bypassed by the superuser, so that case degrades to a notice.
  printf '{"batch":"seed","ts":"2026-01-01T00:00:00Z","path":"bin/none.cjs","ids":["x"]}\n' \
    > "$SB_TEST/.gos/ai-trace-sweep-ledger.ndjson"
  sbgit add .gos/ai-trace-sweep-ledger.ndjson >/dev/null
  sbgit commit -q -m "plant valid ledger"
  if [ "$(id -u)" -eq 0 ]; then
    info "running as root — the unwritable-ledger leg is skipped (root bypasses file modes)"
  else
    chmod 0444 "$SB_TEST/.gos/ai-trace-sweep-ledger.ndjson"
    sbrun s2b-plan.log plan batches/one-only.txt
    expect_zero "plan runs over the unwritable ledger" "$SWEEP_RC"
    C1_OLD="// [D-${n1}] lineage note - frobnicate the input stream" C1_NEW="// frobnicate the input stream" \
      node - "$SB_TEST" <<'NODE_EOF'
'use strict';
const fs = require('fs');
const p = process.argv[2] + '/bin/one.cjs';
const t = fs.readFileSync(p, 'utf8');
if (!t.includes(process.env.C1_OLD)) process.exit(2);
fs.writeFileSync(p, t.replace(process.env.C1_OLD, process.env.C1_NEW));
NODE_EOF
    sbrun s2b-verify.log verify batches/one-only.txt
    expect_nonzero "verify fails when the ledger append cannot land" "$SWEEP_RC"
    expect_contains "failure names the ledger reconciliation guard" "$L/s2b-verify.log" "ledger reconciliation failed"
    dirty=$(git --no-pager -C "$SB_TEST" status --porcelain | grep -v '\.gos/logs/' || true)
    if [ -z "$dirty" ]; then st_pass "tree restored pristine after failed append"; else st_fail "tree left dirty after failed append: $dirty"; fi
    chmod u+w "$SB_TEST/.gos/ai-trace-sweep-ledger.ndjson"
  fi
  sbgit rm -q .gos/ai-trace-sweep-ledger.ndjson
  sbgit commit -q -m "remove planted ledger"

  echo "scenario three — a valid micro-batch round-trips green"
  sbrun s3-plan.log plan batches/mixed.txt
  expect_zero "plan records the two-member batch" "$SWEEP_RC"
  D1_OLD="// [D-${n1}] lineage note - frobnicate the input stream" D1_NEW="// frobnicate the input stream" \
  D2_OLD="// ported from the old builder (D-${n2})" D2_NEW="// ported from the old builder" \
  D3_OLD="// [T ${n4}] old task marker - resolve labels" \
    node - "$SB_TEST" <<'NODE_EOF'
'use strict';
const fs = require('fs');
const root = process.argv[2];
let one = fs.readFileSync(root + '/bin/one.cjs', 'utf8');
if (!one.includes(process.env.D1_OLD) || !one.includes(process.env.D2_OLD)) process.exit(2);
one = one.replace(process.env.D1_OLD, process.env.D1_NEW).replace(process.env.D2_OLD, process.env.D2_NEW);
fs.writeFileSync(root + '/bin/one.cjs', one);
let two = fs.readFileSync(root + '/bin/two.cjs', 'utf8');
if (!two.includes(process.env.D3_OLD)) process.exit(2);
fs.writeFileSync(root + '/bin/two.cjs', two.replace(process.env.D3_OLD + '\n', ''));
NODE_EOF
  [ $? -eq 0 ] || st_fail "applied the planned dispositions"
  sbrun s3-verify.log verify batches/mixed.txt
  expect_zero "verify passes the valid batch end to end" "$SWEEP_RC"
  expect_contains "success lists the staged set" "$L/s3-verify.log" "staged for commit"
  local staged_names
  staged_names=$(sbgit diff --cached --name-only | tr '\n' ' ')
  local want
  for want in bin/one.cjs bin/two.cjs .gos/ai-trace-whitelist.json .gos/ai-trace-sweep-ledger.ndjson; do
    case " $staged_names " in *" $want "*) st_pass "staged: $want" ;; *) st_fail "staged: $want (got: $staged_names)" ;; esac
  done
  if node - "$SB_TEST" "$n1" "$n2" "$n4" <<'NODE_EOF'
'use strict';
const fs = require('fs');
const root = process.argv[2];
const lines = fs.readFileSync(root + '/.gos/ai-trace-sweep-ledger.ndjson', 'utf8').split('\n').filter(Boolean);
const records = lines.map((l) => JSON.parse(l));
const byPath = {};
for (const r of records) (byPath[r.batch] = byPath[r.batch] || {})[r.path] = r.ids;
const b = byPath['mixed'] || {};
const sort = (a) => a.slice().sort();
const wantOne = sort(['[D-' + process.argv[3] + ']', 'D-' + process.argv[4]]);
const wantTwo = sort(['[T ' + process.argv[5] + ']']);
const ok = b['bin/one.cjs'] && JSON.stringify(sort(b['bin/one.cjs'])) === JSON.stringify(wantOne)
  && b['bin/two.cjs'] && JSON.stringify(sort(b['bin/two.cjs'])) === JSON.stringify(wantTwo);
process.exit(ok ? 0 : 1);
NODE_EOF
  then st_pass "ledger record content matches the deleted ids"; else st_fail "ledger record content matches the deleted ids"; fi
  if node - "$SB_TEST/.gos/ai-trace-whitelist.json" <<'NODE_EOF'
'use strict';
const wl = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
const one = wl.filter((e) => e.path === 'bin/one.cjs');
const two = wl.filter((e) => e.path === 'bin/two.cjs' && e.category === 'in-flight-sweep');
process.exit(one.length === 0 && two.length === 1 && two[0].maxHits === 1 ? 0 : 1);
NODE_EOF
  then st_pass "whitelist shrank exactly (removed entry + reduced entry)"; else st_fail "whitelist shrank exactly (removed entry + reduced entry)"; fi
  rc=0
  ( cd "$SB_TEST" && bash test/checks/ai-trace-lint.sh >/dev/null 2>&1 ) || rc=1
  expect_zero "full-tree lint green after the batch (harness script included)" "$rc"
  local first_record
  first_record=$(head -n 1 "$SB_TEST/.gos/ai-trace-sweep-ledger.ndjson")
  echo "  ledger first record: $first_record"
  if command -v python3 >/dev/null 2>&1; then
    if head -n 1 "$SB_TEST/.gos/ai-trace-sweep-ledger.ndjson" | python3 -m json.tool >/dev/null 2>&1; then
      st_pass "ledger first record parses as JSON (python3 json.tool)"
    else
      st_fail "ledger first record failed python3 json.tool"
    fi
  else
    info "python3 unavailable — skipping the json.tool cross-check (node parse above already covers it)"
  fi
  sbgit commit -q -m "sweep batch mixed" >/dev/null
  dirty=$(git --no-pager -C "$SB_TEST" status --porcelain | grep -v '\.gos/logs/' || true)
  if [ -z "$dirty" ]; then st_pass "sandbox tree clean after committing the batch"; else st_fail "sandbox tree dirty after the batch: $dirty"; fi

  echo "self-test summary: $ST_PASS passed, $ST_FAIL failed"
  rm -rf "$SB_TEST"
  trap - EXIT
  [ "$ST_FAIL" -eq 0 ] || die "self-test failed ($ST_FAIL assertion(s))"
  info "self-test passed — sandbox removed"
}

# ---------------------------------------------------------------------------
case "${1:-}" in
  plan) shift; cmd_plan "$@" ;;
  verify) shift; cmd_verify "$@" ;;
  unlock) shift; [ "$#" -eq 0 ] || die "unlock takes no arguments"; cmd_unlock ;;
  --self-test) shift; [ "$#" -eq 0 ] || die "self-test takes no arguments"; cmd_self_test ;;
  -h|--help) sed -n '2,54p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") die "missing subcommand — usage: ai-trace-sweep.sh plan|verify|unlock <batch-file> (or --self-test / --help)" ;;
  *) die "unknown subcommand: $1 — usage: ai-trace-sweep.sh plan|verify|unlock <batch-file> (or --self-test / --help)" ;;
esac
