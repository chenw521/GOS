#!/usr/bin/env bash
# gos-map:none
# Evidence-gated re-enable section — `auto on` never re-enables past a
# TRIPPED breaker blindly: when run records exist the latest must read
# green (every recorded stage advanced in INTENT->SHIP order, sandboxed
# VERIFY steps all passed, end state ok); a store with no records yet is
# a cold start and proceeds with a logged, grep-able disposition. The
# explicit operator reset (`--reset-breakers`) clears trip layers and
# counters and records a disposition entry naming who/when/what.
# Case map:
#   C1  red latest record + a tripped layer -> refusal (exit 1) naming
#       the layer, the record id and its end state; the store mode is
#       left untouched
#   C2  cold start: tripped layer, zero run records -> re-enable proceeds
#       and prints the cold-start disposition token
#   C3  green latest record (full INTENT->VERIFY ladder advanced, VERIFY
#       steps all passed, ship end state) + a tripped layer -> re-enable
#       proceeds and prints the green-evidence disposition token
#   C4  operator reset: the same red fixture that refused now re-enables
#       with `--reset-breakers`; trip-layer records are gone, counters
#       are zeroed, a disposition entry (reason/by/ts) landed in the
#       store, and mode reads on
#   C5  refusal names every tripped layer when several are present
# Loop spawns never run here; fixture stores are planted through the
# store API. HOME and XDG_DATA_HOME are pinned per case under TESTBASE.
# Standalone-safe.

T129_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T129_STANDALONE=1
  T129_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T129_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T129_SELFROOT"
  export TESTBASE="$(mktemp -d "$T129_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T129_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t129"
mkdir -p "$T129_DIR" && cd "$T129_DIR" || exit 1

PASS=0
FAIL=0
t129_ok() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
t129_bad() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
t129_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t129_ok "$label"; else
    t129_bad "$label (expected: '$expected', got: '$actual')"
  fi
}
t129_has() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then t129_ok "$label"; else
    t129_bad "$label (missing: '$needle')"
  fi
}

t129_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T129_DIR"
  if [ "$T129_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t129_teardown EXIT

echo "--- reenable gate: evidence-gated auto on ---"

t129_case() {
  T129_CASE="$T129_DIR/$1"
  mkdir -p "$T129_CASE/home" "$T129_CASE/xdg" "$T129_CASE/repo/.gos/logs"
  export HOME="$T129_CASE/home"
  export XDG_DATA_HOME="$T129_CASE/xdg"
  cd "$T129_CASE/repo" || exit 1
  git init -q -b work . && git commit -q --allow-empty -m root
  # minimal active task so the CLI write-class guard accepts this root
  printf '{"schema_version":6,"level":1,"current_stage":"THINK","completed_stages":["INTENT"],"intent":{"summary":"reenable gate fixture","confirmed":true},"task_head":"abc123def0123456789abcdef0123456789abcde","spec_path":null,"plan_path":null,"requirements":[],"decisions":[],"observable_truths":[],"gaps":[],"checkpoints":[],"approvals":{}}' > .gos/state.json
}

# Plant a fixture store through the store API: mode, trip layers, and one
# run record whose shape the caller picks (red / green / none).
cat > planter.cjs <<'EOF'
const path = require('path');
const store = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/store.cjs'));
const world = process.cwd();
const now = new Date().toISOString();
const mode = process.argv[2] === 'on' ? 'on' : 'off';
const shape = process.argv[3] || 'none';
const layers = String(process.argv[4] || '').split(',').map((s) => s.trim()).filter(Boolean);
store.create({ mode, rootDir: world, limits: { N: 3, K: 5, B: 30 } });
for (const layer of layers) store.recordTrip({ layer, cls: 'task', detail: 'fixture trip' }, world);
if (shape === 'red') {
  store.bumpSpawn(world);
  store.writeRunRecord({
    runId: '22222222-2222-4222-8222-222222222222', runTag: 'redrun', taskId: 'fixture-red',
    startedAtIso: now, endedAtIso: now,
    endState: { ok: false, status: 'paused', reason: 'budget-burned' },
    stages: [{
      stage: 'VERIFY', signal: 'task-failed', advanced: false, counted: true, spawnId: 'spawn-red',
      steps: [{ id: 'gate', kind: 'P', status: 'passed' }, { id: 'sections', kind: 'S', status: 'failed' }],
    }],
  }, world);
} else if (shape === 'green') {
  const adv = (stage, extra) => Object.assign(
    { stage, signal: 'advanced', advanced: true, counted: false, spawnId: 'spawn-' + stage.toLowerCase() },
    extra || {},
  );
  store.writeRunRecord({
    runId: '11111111-1111-4111-8111-111111111111', runTag: 'greenrun', taskId: 'fixture-green',
    startedAtIso: now, endedAtIso: now,
    endState: { ok: true, status: 'ship', reason: 'stage-ship' },
    stages: [
      adv('INTENT'), adv('THINK'), adv('PLAN'), adv('BUILD'), adv('REVIEW'),
      adv('VERIFY', { steps: [
        { id: 'gate', kind: 'P', status: 'passed' },
        { id: 'sections', kind: 'S', status: 'passed' },
        { id: 'truth', kind: 'P', status: 'passed' },
      ] }),
    ],
  }, world);
}
console.log('PLANTED ' + mode + ' ' + shape + ' [' + layers.join(',') + ']');
EOF

# One-line store snapshot: mode|spawns|trips|layerRecords|runRecords|dispositions
t129_snapshot() {
  node -e '
const p = require("path");
const store = require(p.join(process.env.GOS_ROOT, "bin/lib/ops/auto/store.cjs"));
const r = store.load(process.cwd());
if (!r.ok) { console.log("ERR " + r.reason); process.exit(0); }
const st = r.store;
console.log([st.mode, st.counters.spawnCount, st.counters.tripCount,
  st.breaker.records.filter((x) => x && x.layer).length,
  (st.runRecords || []).length, (st.dispositions || []).length].join("|"));
'
}

# ---------------------------------------------------------------- C1 --
t129_case c1
node "$T129_DIR/planter.cjs" off red B > /dev/null
node "$GOS" auto on > c1-on.txt 2>&1; C1_RC=$?
t129_eq "refusal exit code on a red latest record under a tripped layer" 1 "$C1_RC"
t129_has "refusal says auto on refused" "auto on refused" "$(cat c1-on.txt)"
t129_has "refusal names the tripped layer" "TRIPPED (B)" "$(cat c1-on.txt)"
t129_has "refusal names the latest record id" "22222222-2222-4222-8222-222222222222" "$(cat c1-on.txt)"
t129_has "refusal names the latest record end state" "end state: paused" "$(cat c1-on.txt)"
t129_has "refusal points at the explicit reset escape" "--reset-breakers" "$(cat c1-on.txt)"
t129_eq "store mode untouched by the refusal" "off|1|1|1|1|0" "$(t129_snapshot)"

# ---------------------------------------------------------------- C2 --
t129_case c2
node "$T129_DIR/planter.cjs" off none B > /dev/null
node "$GOS" auto on > c2-on.txt 2>&1; C2_RC=$?
t129_eq "cold start (tripped, zero records) re-enables" 0 "$C2_RC"
t129_has "cold start prints the grep-able disposition token" "cold-start-no-run-records" "$(cat c2-on.txt)"
t129_eq "cold start flips the store mode on" "on|0|1|1|0|0" "$(t129_snapshot)"

# ---------------------------------------------------------------- C3 --
t129_case c3
node "$T129_DIR/planter.cjs" off green B > /dev/null
node "$GOS" auto on > c3-on.txt 2>&1; C3_RC=$?
t129_eq "green latest record under a tripped layer re-enables" 0 "$C3_RC"
t129_has "green path prints the evidence disposition token" "reenable-evidence-green" "$(cat c3-on.txt)"
t129_has "green path names the evidence record" "11111111-1111-4111-8111-111111111111" "$(cat c3-on.txt)"
t129_eq "green path flips the store mode on" "on|0|1|1|1|0" "$(t129_snapshot)"

# ---------------------------------------------------------------- C4 --
t129_case c4
node "$T129_DIR/planter.cjs" off red N,B > /dev/null
node "$GOS" auto on > c4-pre.txt 2>&1; C4_PRE=$?
t129_eq "the same fixture refuses without the operator flag" 1 "$C4_PRE"
node "$GOS" auto on --reset-breakers > c4-on.txt 2>&1; C4_RC=$?
t129_eq "operator reset re-enables past the tripped layers" 0 "$C4_RC"
t129_has "reset output announces the cleared state" "breakers reset" "$(cat c4-on.txt)"
t129_eq "reset clears layers/counters and records a disposition" "on|0|0|0|1|1" "$(t129_snapshot)"
node -e '
const p = require("path");
const store = require(p.join(process.env.GOS_ROOT, "bin/lib/ops/auto/store.cjs"));
const r = store.load(process.cwd());
const problems = [];
if (!r.ok) problems.push("store unreadable: " + r.reason);
else {
  const d = r.store.dispositions || [];
  if (d.length !== 1) problems.push("expected one disposition, got " + d.length);
  else {
    if (!String(d[0].reason || "").includes("reset-breakers")) problems.push("reason does not name the reset: " + d[0].reason);
    if (!String(d[0].by || "").includes("@")) problems.push("by lacks the user@host shape: " + d[0].by);
    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(String(d[0].ts || ""))) problems.push("ts not ISO: " + d[0].ts);
    if (!String(d[0].runId || "").startsWith("breakers-reset-")) problems.push("runId not reset-tagged: " + d[0].runId);
  }
  for (const rec of r.store.breaker.records) {
    if (rec && rec.layer) problems.push("layer record survived: " + JSON.stringify(rec));
  }
}
console.log(problems.length ? "BAD " + problems.join("; ") : "OK");
' > c4-disp.txt 2>&1
t129_eq "disposition entry carries who/when/what and layers stay cleared" "OK" "$(tail -n 1 c4-disp.txt)"

# ---------------------------------------------------------------- C5 --
t129_case c5
node "$T129_DIR/planter.cjs" off red N,B > /dev/null
node "$GOS" auto on > c5-on.txt 2>&1; C5_RC=$?
t129_eq "multi-layer fixture still refuses" 1 "$C5_RC"
t129_has "refusal names every tripped layer" "TRIPPED (N, B)" "$(cat c5-on.txt)"

echo "--- reenable gate summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
