#!/usr/bin/env bash
# stale-verb guard — command docs x nav registry ( doc-drift failure mode).
#
# Every backticked `gos <verb> ...` reference in .opencode/commands/gos/*.md
# must name a verb that still exists. KNOWN_CASES is obtained via require()
# of bin/lib/nav/registry-consts.cjs (single source of truth; text-grepping
# the registry is brittle and forbidden). Extraction is backtick-span-only:
# prose mentions ("the gos commands") never trip the guard, and
# `gos brownfield --json` counts by its first token after `gos`.
# `node bin/gos.cjs <verb> ...` spans follow the same first-token rule.
#
# Exit codes: 0 all references live, 1 stale reference(s) found,
#             2 usage or internal error (registry unreadable, empty scan).
#
# Usage:
#   bash test/checks/stale-verbs.sh              scan the real command docs
#   bash test/checks/stale-verbs.sh --selftest   inject a fake verb, assert exit 1
#
# Env overrides (used by --selftest, also handy for ad-hoc probes):
#   STALE_VERBS_SCAN_ROOT  dir of *.md to scan (default .opencode/commands/gos)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat >&2 <<'EOF'
usage: test/checks/stale-verbs.sh [--selftest]
EOF
}

# scan: node driver over ${STALE_VERBS_SCAN_ROOT:-.opencode/commands/gos};
# propagates the driver's exit code (0 clean / 1 violations / 2 internal).
scan() {
  (
    cd "$REPO_ROOT"
    STALE_VERBS_REPO_ROOT="$REPO_ROOT" node - <<'NODEEOF'
'use strict';
const fs = require('fs');
const path = require('path');

const die = (msg, code) => { console.error(`stale-verbs: ${msg}`); process.exit(code); };

const repoRoot = process.env.STALE_VERBS_REPO_ROOT;
if (!repoRoot) die('STALE_VERBS_REPO_ROOT not set (internal wiring error)', 2);

let KNOWN_CASES;
try {
  // Single source of truth: require() the registry, never text-grep it.
  ({ KNOWN_CASES } = require(path.join(repoRoot, 'bin/lib/nav/registry-consts.cjs')));
} catch (e) {
  die(`cannot require bin/lib/nav/registry-consts.cjs: ${e.message}`, 2);
}
if (!Array.isArray(KNOWN_CASES) || KNOWN_CASES.length === 0)
  die('KNOWN_CASES missing or empty in registry-consts.cjs', 2);
const known = new Set(KNOWN_CASES);

const scanRoot = process.env.STALE_VERBS_SCAN_ROOT || '.opencode/commands/gos';
let names;
try {
  names = fs.readdirSync(path.resolve(repoRoot, scanRoot), { withFileTypes: true })
    .filter((d) => d.isFile() && d.name.endsWith('.md'))
    .map((d) => d.name)
    .sort();
} catch (e) {
  die(`cannot read scan root ${scanRoot}: ${e.message}`, 2);
}
if (names.length === 0)
  die(`scan root ${scanRoot} contains no .md files - refusing to pass vacuously`, 2);

// Backtick code spans only (inline code; spans are single-line, fences never
// yield a gos-first span). Prose outside backticks is never scanned.
const SPAN = /`([^`\n]+)`/g;
// The verb is the first word after `gos` (or after bin/gos.cjs); later
// flags/args such as --json are ignored.
const GOS = /(?:^|\s)gos\s+([A-Za-z0-9][A-Za-z0-9_-]*)/;
const CLI = /(?:^|\s)node\s+bin\/gos\.cjs\s+([A-Za-z0-9][A-Za-z0-9_-]*)/;

const violations = [];
for (const name of names) {
  const text = fs.readFileSync(path.resolve(repoRoot, scanRoot, name), 'utf8');
  let m;
  while ((m = SPAN.exec(text)) !== null) {
    const span = m[1];
    for (const re of [GOS, CLI]) {
      const t = span.match(re);
      if (t && !known.has(t[1])) {
        const line = text.slice(0, m.index).split('\n').length;
        violations.push(
          `${scanRoot}/${name}:${line} unknown gos verb '${t[1]}' (span: \`${span}\`)`
        );
        break; // one hit per span is enough for the report
      }
    }
  }
}

if (violations.length > 0) {
  for (const v of violations) console.error(`stale-verbs: ${v}`);
  console.error(
    `stale-verbs: ${violations.length} stale reference(s); live verbs are KNOWN_CASES in bin/lib/nav/registry-consts.cjs`
  );
  process.exit(1);
}
console.log(
  `stale-verbs: ${names.length} command file(s) in ${scanRoot}, every backticked gos verb is live (KNOWN_CASES: ${known.size})`
);
NODEEOF
  )
}

# expect <wanted-exit> <label> <scan-root>: assert the driver's verdict and
# echo the captured output on mismatch (aggregate-guard self-test pattern).
expect() {
  local want="$1" label="$2" root="$3" got=0 out
  out="$(STALE_VERBS_SCAN_ROOT="$root" scan 2>&1)" || got=$?
  if [ "$got" -ne "$want" ]; then
    printf 'FAIL: %s (wanted exit %s, got %s)\n%s\n' \
      "$label" "$want" "$got" "$out" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$label"
  LAST_OUT="$out"
}

self_test() {
  # tmp must stay global: the EXIT trap runs after this function's scope is
  # gone, and with set -u a local would die as "unbound variable" there.
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/gos-stale-verbs-selftest.XXXXXX")"
  trap 'rm -rf "$tmp"' EXIT

  local clean="$tmp/clean" stale="$tmp/stale" empty="$tmp/empty"
  mkdir -p "$clean" "$stale" "$empty"

  # 1. a clean copy of a real command doc must pass (no false positives on
  #    live doc content, including its `gos init$ARGUMENTS` style spans)
  cp "$REPO_ROOT/.opencode/commands/gos/gos-init.md" "$clean/gos-clean.md"
  expect 0 'clean command doc passes' "$clean"

  # 2. an injected fake verb inside a backtick span must fail, and the
  #    report must name both the file and the token
  cp "$REPO_ROOT/.opencode/commands/gos/gos-init.md" "$stale/gos-stale.md"
  printf '\nprobe: run `gos definitely-not-a-verb --json` and report.\n' \
    >> "$stale/gos-stale.md"
  expect 1 'injected stale verb rejected' "$stale"
  case "$LAST_OUT" in
    *definitely-not-a-verb*) ;;
    *) printf 'FAIL: report omits the injected token\n%s\n' "$LAST_OUT" >&2; exit 1 ;;
  esac
  case "$LAST_OUT" in
    *gos-stale.md*) ;;
    *) printf 'FAIL: report omits the offending file\n%s\n' "$LAST_OUT" >&2; exit 1 ;;
  esac

  # 3. an empty scan root is an internal error, never a vacuous pass
  expect 2 'empty scan root refused' "$empty"

  printf 'stale-verbs self-test: 3/3 cases passed\n'
}

if [ "${1:-}" = '--selftest' ] || [ "${1:-}" = '--self-test' ]; then
  self_test
  exit 0
fi
if [ "${1:-}" = '-h' ] || [ "${1:-}" = '--help' ]; then
  usage
  exit 0
fi
if [ "$#" -gt 0 ]; then
  printf 'FAIL: unknown argument: %s\n' "$1" >&2
  usage
  exit 2
fi
scan
