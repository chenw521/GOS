#!/usr/bin/env bash
# gos-map:none
# Dogfood acceptance section — the restart-safe auto loop kill/restart cycle
# driven end to end through the real CLI operating on the committed dogfood
# fixture (build.sh + seed-store.sh, per the fixture's seed-notes contract).
# One heavy case; every step bounded, every kill pid-targeted:
#   C1  environment preflight (sandbox engine probe, launcher semantics; a
#       failure — or T136_FORCE_NO_BWRAP=1 — emits the `── SKIP` sentinel
#       and exits 0) → fixture build + store seed → sentinel marker deleted
#       (first-pass blocking re-armed, the kill window) → runner spawned in
#       the fixture env → marker poll (≤250ms, 120s bound) → SIGTERM to the
#       runner PID only (never a group) → exit 128+15 → killed children
#       silent in /proc → `auto kill:` telemetry naming spawn ids (runner
#       kill, not kernel PDEATHSIG) → killed record read from the store
#       between kill and restart (exactly one, reason SIGTERM, in-flight
#       VERIFY entry with steps) → run.lock absent → restart → two-pass
#       sentinel instant green → ship record with every VERIFY step passed
#       → `auto status` latest-run line → pin-live markers in both round
#       logs.
# NO baseline floor entry: the section is skippable on hosts without a
# working sandbox engine, and a floor would mask the skip. manifest-coverage
# iterates baseline.json keys for floors, so the absent key means no floor;
# the skip stays visible in the runner summary and the manifest.
# Parallel-suite safe: the fixture and both runner logs live under TESTBASE.

T136_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T136_STANDALONE=1
  T136_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T136_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T136_SELFROOT"
  export TESTBASE="$(mktemp -d "$T136_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

PASS=0
FAIL=0
T136_PIDS=""
T136_SP=""
t136_ok() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
t136_bad() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
t136_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t136_ok "$label"; else
    t136_bad "$label (expected: '$expected', got: '$actual')"
  fi
}
t136_contains() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then t136_ok "$label"; else
    t136_bad "$label (expected: '$expected')"
    echo "    actual: $(printf '%s' "$actual" | head -c 200)"
  fi
}

t136_teardown() {
  for p in $T136_PIDS; do kill -9 "$p" 2>/dev/null; done
  if [ -n "$T136_SP" ]; then kill -9 "$T136_SP" 2>/dev/null; fi
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T136_DIR"
  if [ "$T136_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t136_teardown EXIT

# Environment preflight: the sandbox engine must resolve and prove one
# minimal sandbox start — the same shape the launcher's engine probe uses
# (version presence alone is not capability).
t136_engine_reason=""
t136_engine_ok() {
  if ! command -v bwrap >/dev/null 2>&1; then
    t136_engine_reason="sandbox engine unavailable: no bwrap on PATH"
    return 1
  fi
  if ! bwrap --ro-bind /usr /usr --ro-bind-try /bin /bin --ro-bind-try /lib /lib \
       --ro-bind-try /lib64 /lib64 --dev /dev --proc /proc -- /bin/true >/dev/null 2>&1; then
    t136_engine_reason="sandbox engine present but cannot start a sandbox (launcher probe semantics)"
    return 1
  fi
  return 0
}
if [ "${T136_FORCE_NO_BWRAP:-0}" = "1" ]; then
  echo "── SKIP T136-auto-dogfood-restart: self-invocation with T136_FORCE_NO_BWRAP=1 (skip plumbing probe)"
  exit 0
fi
if ! t136_engine_ok; then
  echo "── SKIP T136-auto-dogfood-restart: $t136_engine_reason"
  exit 0
fi

echo "--- T136: dogfood restart-safe auto loop (kill + restart) ---"

# Wait for a background pid to exit. Sets T136_EXIT_RC; returns 1 when the
# SIGKILL fallback had to fire (the case fails with a named message).
t136_wait_exit() {
  T136_EXIT_RC=""
  local dl=$(( $(date +%s) + $2 ))
  while kill -0 "$1" 2>/dev/null; do
    if [ "$(date +%s)" -ge "$dl" ]; then
      kill -9 "$1" 2>/dev/null
      T136_EXIT_RC=timeout
      return 1
    fi
    sleep 0.25
  done
  wait "$1" 2>/dev/null
  T136_EXIT_RC=$?
  return 0
}

# Spawn the real runner operating on the fixture: env -i contract from the
# fixture seed notes, cwd = fixture root, node <real repo>/bin/gos.cjs. The
# compound is backgrounded as one job of the SECTION shell and exec makes
# the pid the node pid — no command substitution (it would strand the job
# in a throwaway subshell and orphan the runner) and no extra layer (the
# kill must land on the runner itself).
t136_launch() { # $1=log path; sets T136_NEWPID
  (
    cd "$T136_FIX" || exit 1
    exec env -i \
      PATH="$PATH" \
      HOME="$T136_FIX/home" \
      XDG_DATA_HOME="$T136_FIX/xdg/data" \
      LANG=C.UTF-8 LC_ALL=C.UTF-8 \
      GIT_AUTHOR_NAME=gos-fixture GIT_AUTHOR_EMAIL=fixture@test.invalid \
      GIT_COMMITTER_NAME=gos-fixture GIT_COMMITTER_EMAIL=fixture@test.invalid \
      GOS_HEADLESS=1 GOS_LANG=en \
      node "$GOS_ROOT/bin/gos.cjs" auto run --fg
  ) > "$1" 2>&1 &
  T136_NEWPID=$!
}

# ---------------------------------------------------------------- C1 --
t136_c1() {
  T136_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t136"
  mkdir -p "$T136_DIR"
  T136_FIX="$T136_DIR/fix"
  T136_MARKER="$T136_FIX/.gos/cache/dogfood-sentinel.marker"

  # Fixture + store. build.sh is deterministic; seed-store.sh seeds the
  # machine-local store inside the fixture's xdg/ override and pre-arms the
  # marker (the kill round deletes it immediately after).
  local seed_out
  if ! seed_out="$(bash "$GOS_ROOT/test/sections/fixtures/dogfood/build.sh" "$T136_FIX" 2>&1)"; then
    t136_bad "C1: fixture built"
    printf '%s\n' "$seed_out"
    return 1
  fi
  t136_ok "C1: fixture built ($seed_out)"
  if ! seed_out="$(bash "$GOS_ROOT/test/sections/fixtures/dogfood/seed-store.sh" "$T136_FIX" 2>&1)"; then
    t136_bad "C1: store seeded"
    printf '%s\n' "$seed_out"
    return 1
  fi
  T136_STORE="$(printf '%s\n' "$seed_out" | sed -n 's/^store: //p' | head -n 1)"
  # Pre-spawn assert: the resolved store must live inside the fixture dir.
  case "$T136_STORE" in
    "$T136_FIX"/*) t136_ok "C1: store resolved inside the fixture dir" ;;
    *) t136_bad "C1: store resolved inside the fixture dir (got: '$T136_STORE')"; return 1 ;;
  esac
  rm -f "$T136_MARKER"
  if [ -f "$T136_MARKER" ]; then
    t136_bad "C1: sentinel marker deleted (first-pass blocking re-armed)"
    return 1
  fi
  t136_ok "C1: sentinel marker deleted — first-pass blocking re-armed (the kill window)"

  # ---- round 1: spawn, poll the arming marker, SIGTERM the runner ----
  T136_R1_LOG="$T136_DIR/runner-round1.log"
  t136_launch "$T136_R1_LOG"
  T136_R1="$T136_NEWPID"
  T136_PIDS="$T136_R1"
  local dl=$(( $(date +%s) + 120 ))
  while [ ! -f "$T136_MARKER" ]; do
    if ! kill -0 "$T136_R1" 2>/dev/null; then
      t136_bad "C1: sentinel marker armed (runner died early)"
      echo "    runner log tail: $(tail -n 3 "$T136_R1_LOG" | tr '\n' '|')"
      return 1
    fi
    if [ "$(date +%s)" -ge "$dl" ]; then
      t136_bad "C1: sentinel marker armed within 120s — SIGKILL fallback fired"
      kill -9 "$T136_R1" 2>/dev/null
      return 1
    fi
    sleep 0.25
  done
  t136_ok "C1: sentinel marker armed (first pass blocking in the 600s window)"
  T136_SP="$(sed -n 's/^pid=//p' "$T136_MARKER" | head -n 1)"
  case "$T136_SP" in
    ''|*[!0-9]*) t136_bad "C1: marker carries a numeric sentinel pid (got: '$T136_SP')"; return 1 ;;
    *) t136_ok "C1: marker carries the sentinel pid ($T136_SP)" ;;
  esac
  kill -0 "$T136_SP" 2>/dev/null || { t136_bad "C1: sentinel process alive at kill time"; return 1; }

  # Kill discipline: SIGTERM to the runner PID ONLY — never a group.
  kill -TERM "$T136_R1"
  if t136_wait_exit "$T136_R1" 30; then
    t136_eq "C1: SIGTERM lands the runner at 128+15" "143" "$T136_EXIT_RC"
  else
    t136_bad "C1: runner ignored SIGTERM past 30s — SIGKILL fallback fired (exit $T136_EXIT_RC)"
    return 1
  fi

  # Children dead: the sentinel (sleep-holding bash named in the marker)
  # must be reaped by the kill path, not left orphaned.
  dl=$(( $(date +%s) + 10 ))
  while kill -0 "$T136_SP" 2>/dev/null && [ "$(date +%s)" -lt "$dl" ]; do sleep 0.25; done
  if kill -0 "$T136_SP" 2>/dev/null; then
    t136_bad "C1: killed child silent in /proc within 10s (pid $T136_SP alive)"
  else
    t136_ok "C1: killed child silent in /proc (pid $T136_SP gone)"
  fi

  # Kill telemetry: the handler's stderr lines name the spawn ids — the
  # discriminator between a runner-driven kill and kernel PDEATHSIG cleanup.
  local kill_line
  kill_line="$(grep '^auto kill:' "$T136_R1_LOG" | head -n 1)"
  t136_contains "C1: kill telemetry on the runner stderr" "auto kill: killed=" "${kill_line:-<none>}"
  if printf '%s' "${kill_line:-}" | grep -Eq '\(pid=[0-9]+\)'; then
    t136_ok "C1: kill telemetry names the spawn id and pid"
  else
    t136_bad "C1: kill telemetry names the spawn id and pid (line: ${kill_line:-<none>})"
  fi

  # Killed record, read between kill and restart (after the restart the
  # latest record is the green one).
  local rec_check
  rec_check="$(STORE="$T136_STORE" python3 - <<'PYEOF'
import json, os
problems = []
try:
    d = json.load(open(os.path.join(os.environ["STORE"], "store.json")))
except Exception as e:
    print("BAD store unreadable: %s" % e)
    raise SystemExit
killed = [r for r in d.get("runRecords", [])
          if isinstance(r.get("endState"), dict) and r["endState"].get("status") == "killed"]
if len(killed) != 1:
    problems.append("killed records=%d (want exactly 1)" % len(killed))
else:
    es = killed[0]["endState"]
    if es.get("reason") != "SIGTERM":
        problems.append("reason=%r (want SIGTERM)" % es.get("reason"))
    vs = [s for s in killed[0].get("stages", []) if s.get("stage") == "VERIFY"]
    if not vs:
        problems.append("no in-flight VERIFY stage entry")
    elif not vs[0].get("steps"):
        problems.append("VERIFY entry carries no steps (in-flight fold missing)")
print("BAD " + "; ".join(problems) if problems else "OK")
PYEOF
)"
  t136_eq "C1: killed record — exactly one, reason SIGTERM, in-flight VERIFY entry with steps" "OK" "$rec_check"

  # Lock acquirable: the exit hook released the run lock with the runner.
  if [ -f "$T136_STORE/run.lock" ]; then
    t136_bad "C1: run lock released (run.lock still present in the store)"
  else
    t136_ok "C1: run lock released (no run.lock in the store dir)"
  fi

  # ---- round 2: restart — the marker now exists, the sentinel takes its
  # second-pass instant-green path and the cycle completes at SHIP ----
  T136_R2_LOG="$T136_DIR/runner-round2.log"
  t136_launch "$T136_R2_LOG"
  T136_R2="$T136_NEWPID"
  T136_PIDS="$T136_R2"
  if t136_wait_exit "$T136_R2" 420; then
    t136_eq "C1: restarted runner completes (exit 0, inside the 420s bound)" "0" "$T136_EXIT_RC"
  else
    t136_bad "C1: restarted runner past the 420s bound — SIGKILL fallback fired"
    return 1
  fi

  local ship_check
  ship_check="$(STORE="$T136_STORE" python3 - <<'PYEOF'
import json, os
problems = []
try:
    d = json.load(open(os.path.join(os.environ["STORE"], "store.json")))
except Exception as e:
    print("BAD store unreadable: %s" % e)
    raise SystemExit
rs = d.get("runRecords", [])
if not rs:
    problems.append("no records after the restart")
else:
    es = rs[-1].get("endState") or {}
    if es.get("ok") is not True or es.get("status") != "ship":
        problems.append("latest endState=%r (want ok/ship)" % es)
    vs = [s for s in rs[-1].get("stages", []) if s.get("stage") == "VERIFY"]
    if not vs:
        problems.append("ship record has no VERIFY stage entry")
    else:
        steps = vs[0].get("steps") or []
        if not steps:
            problems.append("VERIFY steps empty")
        elif not all(x.get("status") == "passed" for x in steps):
            problems.append("not every VERIFY step passed: %r" % steps)
print("BAD " + "; ".join(problems) if problems else "OK")
PYEOF
)"
  t136_eq "C1: restarted run reaches a GREEN record with every pin leg passing" "OK" "$ship_check"

  local status_out
  status_out="$(cd "$T136_FIX" && env -i \
    PATH="$PATH" HOME="$T136_FIX/home" XDG_DATA_HOME="$T136_FIX/xdg/data" \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    GIT_AUTHOR_NAME=gos-fixture GIT_AUTHOR_EMAIL=fixture@test.invalid \
    GIT_COMMITTER_NAME=gos-fixture GIT_COMMITTER_EMAIL=fixture@test.invalid \
    GOS_HEADLESS=1 GOS_LANG=en \
    node "$GOS_ROOT/bin/gos.cjs" auto status 2>&1)"
  t136_contains "C1: auto status carries the latest-run line" "latest run: ship" "$status_out"

  if grep -q 'pin-live:' "$T136_R1_LOG"; then
    t136_ok "C1: round 1 log carries the pin-live markers"
  else
    t136_bad "C1: round 1 log carries the pin-live markers"
  fi
  if grep -q 'pin-live:' "$T136_R2_LOG"; then
    t136_ok "C1: round 2 log carries the pin-live markers"
  else
    t136_bad "C1: round 2 log carries the pin-live markers"
  fi
}

t136_c1

echo "--- T136 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
