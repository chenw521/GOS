#!/usr/bin/env bash
# gos-map:none
# Auto-dispatch section — the stage-dispatch blueprint surface for the auto
# loop. First case set: the spawn-text sanitizer module (core/sanitize.cjs)
# that every render surface funnels spawn-originated bytes through before
# showing them to humans.
# Case map (truth id -> case):
#   sanitize-strip  C1  a string carrying SGR color runs, cursor/erase
#                   sequences, OSC payloads (BEL- and ST-terminated), a
#                   charset escape, and bare C0 controls renders escape-free
#                   with every visible word intact and byte-exact spacing
#   spawn-marker    C2  markSpawnOutput prefixes the spawn-output marker,
#                   renderSpawnOutput(raw) equals mark(sanitize(raw)) exactly
# Standalone-safe: self-provisions env when not under test/run-sections.sh.

T107_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T107_STANDALONE=1
  T107_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T107_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T107_SELFROOT"
  export TESTBASE="$(mktemp -d "$T107_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T107_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t107"
mkdir -p "$T107_DIR" && cd "$T107_DIR" || exit 1

PASS=0
FAIL=0
t107_ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
t107_bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
t107_contains() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then t107_ok "$label"; else
    t107_bad "$label (expected: '$expected')"
    echo "    actual: $(printf '%s' "$actual" | head -c 200)"
  fi
}
t107_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then t107_ok "$label (exit $actual)"; else
    t107_bad "$label (expected exit $expected, got '${actual:-<none>}')"; fi
}

t107_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T107_DIR"
  if [ "$T107_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t107_teardown EXIT

echo "--- T107: auto dispatch (sanitize-strip, spawn-marker) ---"

SAN="$T107_DIR/sanitize-probe.cjs"
cat > "$SAN" <<'EOF'
const path = require('path');
const sanitize = require(path.join(process.env.GOS_ROOT, 'bin/lib/core/sanitize.cjs'));
const problems = [];

// Escape families a spawned worker emits: SGR color runs, cursor movement
// and erase, OSC payloads (BEL- and ST-terminated), charset selection, and
// bare C0 controls (NUL/SOH/BEL/BS/CR) riding between visible words.
const raw =
  'plain \x1b[31mred\x1b[0m \x1b[2Kwiped\x1b[1;5H' +
  '\x1b]0;title\x07hybrid \x1b]8;;http://unit.invalid/a\x1b\\link' +
  ' \x00\x01\x07\x08\x0dctl\x1b(B end';

const expected = 'plain red wipedhybrid link ctl end';
const clean = sanitize.sanitizeSpawnText(raw);
if (clean.includes('\x1b')) problems.push('ESC byte survived');
if (/[\u0000-\u0008\u000b-\u001f\u007f\u0080-\u009f]/.test(clean)) problems.push('C0/C1 control survived');
if (clean !== expected) problems.push('strip result not byte-exact: ' + JSON.stringify(clean));
if (sanitize.sanitizeSpawnText(clean) !== clean) problems.push('sanitize not idempotent');
const plainText = 'untouched text\nsecond line\ttabbed';
if (sanitize.sanitizeSpawnText(plainText) !== plainText) problems.push('plain text altered (LF/TAB must survive)');
if (sanitize.sanitizeSpawnText(undefined) !== '') problems.push('undefined input does not yield empty string');
console.log(problems.length ? 'SANITIZE-BAD ' + problems.join('; ') : 'SANITIZE-OK');
console.log('CLEAN[' + clean + ']');

const marker = sanitize.SPAWN_OUTPUT_MARKER;
const marked = sanitize.markSpawnOutput(clean);
if (typeof marker !== 'string' || marker === '') problems.push('SPAWN_OUTPUT_MARKER missing');
if (marked.indexOf(marker) !== 0) problems.push('marker does not prefix the output');
if (!marked.includes(clean)) problems.push('marked output lost the cleaned text');
if (sanitize.renderSpawnOutput(raw) !== marked) problems.push('renderSpawnOutput != mark(sanitize(raw))');
if (sanitize.renderSpawnOutput(raw).includes('\x1b')) problems.push('renderSpawnOutput leaked an escape');
console.log(problems.length ? 'MARK-BAD ' + problems.join('; ') : 'MARK-OK');
console.log('RENDER[' + sanitize.renderSpawnOutput(raw) + ']');
EOF

# ---------------------------------------------------------------- C1 --
echo "C1: sanitize-strip (SGR + cursor + OSC + charset + bare C0)"
SAN_OUT="$(node "$SAN" 2>&1)"; RC=$?
t107_exit "probe runs clean" "0" "$RC"
t107_contains "all escape families stripped, visible words intact" "SANITIZE-OK" "$SAN_OUT"
t107_contains "strip result is byte-exact" "CLEAN[plain red wipedhybrid link ctl end]" "$SAN_OUT"

# ---------------------------------------------------------------- C2 --
echo "C2: spawn-marker (prefix + combined render form)"
t107_contains "marker prefixes, render equals mark(sanitize(raw))" "MARK-OK" "$SAN_OUT"
t107_contains "combined render output pinned" "RENDER[[spawn] plain red wipedhybrid link ctl end]" "$SAN_OUT"

echo "--- T107 summary: $PASS passed, $FAIL failed ---"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
