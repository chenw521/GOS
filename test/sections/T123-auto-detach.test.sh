#!/usr/bin/env bash
# gos-map:none
# gos-tier:main
# Auto default-detach survival section -- `auto run` detaches by default so a
# BUILD worker survives its enclosing operator terminal timing out. Three
# proofs: the child argv contract (forwarded invocation minus detach-class
# flags, always exactly one trailing --fg -- a detached child never
# re-detaches), the lock-acquired sentinel (started is proven by the run
# lock, not by the fork; a simulated lock refusal surfaces through the
# sentinel to the parent's exit code), and run-log rotation (keep-last-N
# pruning at detach start).
# Case map:
#   C1  injected detacher captures the composed child argv: entry through
#       bin/gos.cjs, forwarded flags preserved, no --detach, exactly one
#       trailing --fg (negative invariant vs the re-detach chain)
#   C2  default detach e2e -- live lock holder: parent exits 1, the
#       holder-naming refusal is forwarded from the detached child, and the
#       planted run-log backlog is pruned to keep-last-5
#   C3  missing sentinel -- no store: the child exits before proving the
#       lock; the parent fails fast with the exited-unproven line
#   C4  quick completion -- SHIP-stage task: the child acquires the lock
#       (sentinel ok), finishes inside the window; parent exits 0 with the
#       completed line and the run lock is released
#   C5  --fg opts back into the foreground -- in-process run, no run log
#       created, nothing rotated, no detach lines
#   C6  locale parity -- the autoDetach keys exist non-empty in en + zh
# HOME and XDG_DATA_HOME are pinned per case under TESTBASE. Standalone-safe:
# self-provisions env when not under test/run-sections.sh.

T123_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T123_STANDALONE=1
  T123_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T123_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T123_SELFROOT"
  export TESTBASE="$(mktemp -d "$T123_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T123_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t123"
mkdir -p "$T123_DIR" && cd "$T123_DIR" || exit 1

PASS=0
FAIL=0
t123_ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
t123_bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
t123_contains() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then t123_ok "$label"; else
    t123_bad "$label (expected: '$expected')"
    echo "    actual: $(printf '%s' "$actual" | head -c 200)"
  fi
}
t123_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t123_ok "$label"; else t123_bad "$label (expected: '$expected', got: '$actual')"; fi
}
t123_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then t123_ok "$label (exit $actual)"; else t123_bad "$label (expected exit $expected, got '${actual:-<none>}')"; fi
}

T123_PIDS=""
t123_teardown() {
  for p in $T123_PIDS; do kill "$p" 2>/dev/null; done
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T123_DIR"
  if [ "$T123_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t123_teardown EXIT

echo "--- T123: auto default-detach survival ---"

# One isolated case world per call: sandbox HOME + XDG_DATA_HOME + a git repo
# with a minimal task state (same shape as the auto-core fixture).
t123_case() {
  T123_CASE="$T123_DIR/$1"
  mkdir -p "$T123_CASE/home" "$T123_CASE/xdg" "$T123_CASE/repo/.gos/logs"
  export HOME="$T123_CASE/home"
  export XDG_DATA_HOME="$T123_CASE/xdg"
  cd "$T123_CASE/repo" || exit 1
  git init -q -b work . && git commit -q --allow-empty -m root
}

t123_state() { # $1=current_stage
  printf '{"schema_version":6,"level":1,"current_stage":"%s","completed_stages":["INTENT"],"intent":{"summary":"t123 fixture","confirmed":true},"task_head":"abc123def0123456789abcdef0123456789abcde","spec_path":null,"plan_path":null,"requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{}}' "$1"
}

t123_lockgone() { # $1=label
  local out
  out="$(node -e "
const path=require('path');
const s=require(path.join(process.env.GOS_ROOT,'bin/lib/ops/auto/store.cjs'));
console.log(s.readRunLock(process.cwd()) === null);")"
  t123_eq "$1" "true" "$out"
}

t123_logcount() { # $1=label $2=expected count
  local n
  n="$(find .gos/logs -maxdepth 1 -name 'auto-run-*.log' 2>/dev/null | wc -l | tr -d ' ')"
  t123_eq "$1" "$2" "$n"
}

# ---------------------------------------------------------------- C1 --
# Child argv contract through the loop detach branch with an injected
# detacher (no real spawn): the forwarded argv drops every detach-class flag
# and carries exactly one trailing --fg.
mkdir -p c1 && cd c1
cat > run-c1.cjs <<'EOF'
const path = require('path');
const loop = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/loop.cjs'));
const captured = [];
const detacher = (command, args, opts) => {
  captured.push({ command, args: args.slice() });
  if (!(opts && opts.rootDir)) captured.push({ args: ['missing-rootDir'] });
  return { pid: 4321, log: 'injected.log' };
};
(async () => {
  const r = await loop.createLoop({
    rootDir: process.cwd(),
    env: { GOS_AUTO_TEST_FIXTURE: '1' },
    detach: true,
    detachArgv: ['auto', 'run', '--detach', '--fg', '--break-lock'],
    detacher,
  }).loop.run();
  const c = captured[0] || { args: [] };
  const fgCount = c.args.filter((a) => a === '--fg').length;
  const problems = [];
  if (!r.ok || r.status !== 'detached') problems.push('report not detached-ok: ' + r.status + '/' + r.reason);
  if (captured.length !== 1) problems.push('detacher called with unexpected shape: ' + captured.length);
  if (c.command !== process.execPath) problems.push('child command is not the node entry');
  if (!c.args[0] || !c.args[0].endsWith('gos.cjs')) problems.push('child argv does not enter through bin/gos.cjs');
  if (c.args[1] !== 'auto' || c.args[2] !== 'run') problems.push('forwarded subcommand lost: ' + JSON.stringify(c.args.slice(0, 4)));
  if (c.args.includes('--detach')) problems.push('child argv carries --detach (re-detach chain)');
  if (fgCount !== 1) problems.push('child argv must carry exactly one --fg, got ' + fgCount);
  if (!c.args.includes('--break-lock')) problems.push('non-detach flag not forwarded');
  if (c.args[c.args.length - 1] !== '--fg') problems.push('child argv does not end in --fg');
  console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
})().catch((e) => { console.error(e); process.exit(1); });
EOF
T123_C1="$(node run-c1.cjs 2>&1 | tail -n 1)"
t123_eq "C1: child argv carries --fg, never --detach; forwarded flags preserved" "OK" "$T123_C1"
cd "$T123_DIR"

# ---------------------------------------------------------------- C2 --
# Default detach e2e: no flags at all. A live holder keeps the run lock, so
# the detached child refuses at lock acquisition; the refusal must reach the
# parent's exit code with the holder-naming output forwarded, and the
# planted run-log backlog must prune to keep-last-5 at detach start.
t123_case c2
t123_state SHIP > .gos/state.json
node "$GOS" auto on > /dev/null 2>&1
for i in 1 2 3 4 5 6 7; do
  printf 'stale %s\n' "$i" > ".gos/logs/auto-run-90000-1000000$i.log"
  touch -d "$((i + 1)) hours ago" ".gos/logs/auto-run-90000-1000000$i.log"
done
cat > c2-holder.cjs <<'EOF'
const path = require('path');
const store = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/store.cjs'));
const r = store.acquireRunLock({ rootDir: process.argv[2] });
if (!r.ok) { console.error('holder acquire failed'); process.exit(1); }
console.log('READY');
setInterval(() => {}, 1000);
EOF
node c2-holder.cjs "$PWD" > c2-ready.txt 2>&1 &
C2_HOLDER=$!
T123_PIDS="$T123_PIDS $C2_HOLDER"
for i in $(seq 1 50); do grep -q READY c2-ready.txt 2>/dev/null && break; sleep 0.1; done
GOS_AUTO_TEST_FIXTURE=1 node "$GOS" auto run > c2-run.txt 2>&1; C2_RC=$?
t123_exit "C2: lock refusal surfaces to the parent exit code" 1 "$C2_RC"
t123_contains "C2: holder-naming refusal forwarded from the detached child" "an auto run is already active (pid $C2_HOLDER" "$(cat c2-run.txt)"
t123_contains "C2: parent reports the refused status" "auto run: refused" "$(cat c2-run.txt)"
t123_logcount "C2: run-log rotation prunes the backlog to keep-last-5" "5"
if [ ! -f .gos/logs/auto-run-90000-10000007.log ]; then t123_ok "C2: oldest planted log pruned"; else t123_bad "C2: oldest planted log survived rotation"; fi
if [ -f .gos/logs/auto-run-90000-10000004.log ]; then t123_ok "C2: newest kept boundary log survives"; else t123_bad "C2: newest kept boundary log was pruned"; fi
kill "$C2_HOLDER" 2>/dev/null
T123_PIDS=""

# ---------------------------------------------------------------- C3 --
# Missing sentinel: with no store the child exits before lock acquisition
# and never writes the sentinel; the parent must fail (started is proven by
# the lock, not by the fork) naming the unproven exit.
t123_case c3
t123_state SHIP > .gos/state.json
GOS_AUTO_TEST_FIXTURE=1 node "$GOS" auto run > c3-run.txt 2>&1; C3_RC=$?
t123_exit "C3: child exit without the lock proof fails the parent" 1 "$C3_RC"
t123_contains "C3: exited-unproven line names the missing proof" "exited before confirming the run lock" "$(cat c3-run.txt)"

# ---------------------------------------------------------------- C4 --
# Quick completion: a SHIP-stage task ends the child loop cleanly inside the
# wait window; the parent observes the exit (completed line, exit 0) and the
# run lock is released by the time the parent returns.
t123_case c4
t123_state SHIP > .gos/state.json
node "$GOS" auto on > /dev/null 2>&1
GOS_AUTO_TEST_FIXTURE=1 node "$GOS" auto run > c4-run.txt 2>&1; C4_RC=$?
t123_exit "C4: quick detached run completes with exit 0" 0 "$C4_RC"
t123_contains "C4: completed line reports the observed child exit code" "detached runner finished (exit 0)" "$(cat c4-run.txt)"
t123_lockgone "C4: run lock released after the observed child exit"

# ---------------------------------------------------------------- C5 --
# --fg opts back into the foreground: in-process run, no detacher effects.
t123_case c5
t123_state SHIP > .gos/state.json
node "$GOS" auto on > /dev/null 2>&1
printf 'stale\n' > .gos/logs/auto-run-80000-20000001.log
node "$GOS" auto run --fg > c5-run.txt 2>&1; C5_RC=$?
t123_exit "C5: --fg runs in-process and completes" 0 "$C5_RC"
t123_logcount "C5: --fg creates no run log and rotates nothing" "1"
if printf '%s' "$(cat c5-run.txt)" | grep -q 'detached runner'; then t123_bad "C5: --fg output must not carry detach lines"; else t123_ok "C5: --fg output carries no detach lines"; fi
t123_lockgone "C5: run lock released after the in-process run"

# ---------------------------------------------------------------- C6 --
# Locale parity: the detach keys exist non-empty in both catalogs.
T123_C6="$(node -e "
const path = require('path');
const en = require(path.join(process.env.GOS_ROOT, 'bin/lib/core/locales/en.cjs'));
const zh = require(path.join(process.env.GOS_ROOT, 'bin/lib/core/locales/zh.cjs'));
const keys = ['autoDetach.completed', 'autoDetach.waitTimeout', 'autoDetach.exitedUnproven'];
const bad = keys.filter((k) => !en[k] || !zh[k]);
console.log(bad.length ? 'BAD ' + bad.join(',') : 'OK');")"
t123_eq "C6: autoDetach keys present in en and zh locales" "OK" "$T123_C6"

echo "--- T123 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
