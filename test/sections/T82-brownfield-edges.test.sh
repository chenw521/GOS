#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/brownfield.cjs#fn:cmdBrownfield,bin/lib/ops/brownfield.cjs#fn:bfGuardEntry,bin/lib/ops/brownfield.cjs#fn:bfRun
# gos-map:cmd brownfield
# T82: brownfield edge & invariant section (T7, D-97, R-01).
# Seven deterministic case groups via $GOS in sandbox repos (plus one
# sandbox clone that runs its OWN bin/gos.cjs for the self-repo guard):
# (1) subdirectory invocation — cwd != toplevel dies exit 4 with the
#     toplevel remediation, and nothing is created anywhere in the repo
#     (the guard precedes every write);
# (2) self-repo — clone $GOS_ROOT into the sandbox (never run the live
#     CLI against the live repo: lock/state hazards), run the CLONE's own
#     bin/gos.cjs with cwd = clone toplevel so its GOS_SELF_ROOT (resolved
#     from the running CLI's __filename, never env) equals the repo root
#     -> exit 5 human + --json error envelope code 5, whole-tree content
#     hash identical across both runs (zero mutation);
# (3) in-flight task — fixture .gos/state.json + .gos/task/ in a sandbox
#     repo, brownfield adopts (sanctioned seeds DO land: gates.json,
#     gates/check.sh, .gos/.gitignore) while state.json and task files stay
#     byte-identical; no .gos/.lock is ever taken;
# (4) corrupt .gos/cache/commitlint-hook.json — exit 1 with the file path
#     in the --json error envelope, and no seeding happened (guard order:
#     corrupt-state dies before the adopt phase);
# (5) concurrency — two brownfield processes racing in one repo both exit
#     0; every seeded file byte-equal to its master; gates.json is the
#     empty skeleton; no .gos/.lock; no atomic-write temp leftovers
#     (.*.tmp<pid>-<ts> pattern from writeAtomicText);
# (6) stdin closed (0<&-) — byte-identical report (root-path normalized)
#     and identical exit code vs an stdin-open run of an identical repo;
# (7) zero-network — `unshare -rn` (user-ns root mapping; plain unshare -n
#     EPERMs unprivileged) when available, else the NODE_OPTIONS require
#     hook net stub as first-class fallback (both mechanisms shipped);
#     the stub's tripwire proves it throws on real socket attempts;
#     brownfield exits 0 and completes adoption under whichever ran —
#     at least one mechanism MUST have run (never silently pass).
# Env: GOS (CLI path), GOS_ROOT, TESTBASE (sandbox base), assert helpers sourced by runner
T82_DIR=""

t82_setup() {
  T82_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t82"
  mkdir -p "$T82_DIR" || exit 1
  cd "$T82_DIR" || exit 1
}

t82_repo() {  # fresh git repo at $T82_DIR/<name>
  mkdir -p "$T82_DIR/$1"
  git init -q -b main "$T82_DIR/$1" || exit 1
}

t82_run() {  # t82_run <repo> [env-prefix args...] — plain human run, OUT/RC
  local repo="$1"; shift
  OUT=$( cd "$T82_DIR/$repo" && node "$GOS" brownfield "$@" 2>&1 ); RC=$?
}

t82_sha() { sha256sum "$1" | cut -d' ' -f1; }

t82_snap() {  # whole-tree content hash (excl .git) — zero-mutation proof
  ( cd "$1" && find . -name .git -prune -o -type f -print0 | sort -z | xargs -r -0 sha256sum | sha256sum | cut -d' ' -f1 )
}

t82_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T82_DIR"; }

t82_setup
echo "--- T82: brownfield edges & invariants ---"
CM_MASTER="$GOS_ROOT/hooks/commit-msg.sh"
PP_MASTER="$GOS_ROOT/hooks/pre-push.sh"
YAML_MASTER="$GOS_ROOT/templates/git/commitlint.config.yaml"
CS_MASTER="$GOS_ROOT/templates/gates/check.sh"

# --- G1: subdirectory invocation — cwd != toplevel, exit 4, zero writes ---
t82_repo sub
mkdir -p "$T82_DIR/sub/nested/deep"
OUT=$( cd "$T82_DIR/sub" && node "$GOS" brownfield 2>&1 ); RC=$?
assert_exit "G1a toplevel run of the same repo exits 0 (repo is valid)" 0 "$RC"
G1_BEFORE=$(t82_snap "$T82_DIR/sub")
OUT=$( cd "$T82_DIR/sub/nested/deep" && node "$GOS" brownfield 2>&1 ); RC=$?
assert_exit "G1b subdirectory cwd exits 4" 4 "$RC"
assert_contains "G1c exit-4 remediation names the toplevel" "toplevel" "$OUT"
assert_eq "G1d guarded subdir run adds nothing (whole-tree hash identical)" "$G1_BEFORE" "$(t82_snap "$T82_DIR/sub")"

# --- G2: self-repo — sandbox clone running its OWN CLI -> exit 5, zero mutation ---
# Deterministic self-root: the clone's bin/gos.cjs resolves GOS_SELF_ROOT from
# its own __filename (= clone root) and cwd == clone toplevel -> realTop ===
# GOS_SELF_ROOT. The live CLI is never pointed at the live repo.
git clone -q --no-hardlinks "$GOS_ROOT" "$T82_DIR/self" || exit 1
SELF_CLI="$T82_DIR/self/bin/gos.cjs"
G2_BEFORE=$(t82_snap "$T82_DIR/self")
OUT=$( cd "$T82_DIR/self" && node "$SELF_CLI" brownfield 2>&1 ); RC=$?
G2_MID=$(t82_snap "$T82_DIR/self")
assert_exit "G2a self-repo (clone CLI at clone toplevel) exits 5" 5 "$RC"
assert_contains "G2b self-repo refusal names the dev-action rule" "self" "$OUT"
OUT=$( cd "$T82_DIR/self" && node "$SELF_CLI" brownfield --json 2>/dev/null ); RC=$?
G2_AFTER=$(t82_snap "$T82_DIR/self")
assert_exit "G2c self-repo --json exits 5" 5 "$RC"
printf '%s' "$OUT" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
assert isinstance(d,dict) and d['error']['code']==5, d
print('ok')" ; assert_exit "G2d self-repo --json stdout is one error envelope (code 5)" 0 "$?"
assert_eq "G2e self-repo guard mutates nothing (human run)" "$G2_BEFORE" "$G2_MID"
assert_eq "G2f self-repo guard mutates nothing (json run)" "$G2_BEFORE" "$G2_AFTER"
assert_eq "G2g git sees no worktree changes after the self guard" "" "$(git -C "$T82_DIR/self" status --porcelain --untracked-files=all)"

# --- G3: in-flight task — adoption proceeds, task state byte-identical ---
t82_repo inflight
mkdir -p "$T82_DIR/inflight/.gos/task/abc123" "$T82_DIR/inflight/.gos/cache"
# [T4a/T94] v4 in-flight fixture — schema 4, repo_id advisory null (no remotes)
printf '{"schema_version":4,"repo_id":null,"level":2,"current_stage":"BUILD","intent":{"summary":"x","confirmed":true},"completed_stages":["INTENT","THINK"],"decisions":[],"observable_truths":[]}' > "$T82_DIR/inflight/.gos/state.json"
printf '# task notes in flight\n' > "$T82_DIR/inflight/.gos/task/abc123/notes.md"
G3_STATE=$(t82_sha "$T82_DIR/inflight/.gos/state.json")
G3_NOTES=$(t82_sha "$T82_DIR/inflight/.gos/task/abc123/notes.md")
G3_TASKTREE=$( ( cd "$T82_DIR/inflight/.gos/task" && find . -type f -print0 | sort -z | xargs -r -0 sha256sum | sha256sum | cut -d' ' -f1 ) )
t82_run inflight
assert_exit "G3a in-flight repo run exits 0" 0 "$RC"
assert_eq "G3b .gos/state.json byte-identical" "$G3_STATE" "$(t82_sha "$T82_DIR/inflight/.gos/state.json")"
assert_eq "G3c task notes byte-identical" "$G3_NOTES" "$(t82_sha "$T82_DIR/inflight/.gos/task/abc123/notes.md")"
assert_eq "G3d whole .gos/task/ tree byte-identical" "$G3_TASKTREE" "$( cd "$T82_DIR/inflight/.gos/task" && find . -type f -print0 | sort -z | xargs -r -0 sha256sum | sha256sum | cut -d' ' -f1 )"
assert_file "G3e sanctioned seed .gos/gates.json landed (adoption was not blocked)" "$T82_DIR/inflight/.gos/gates.json"
assert_file "G3f sanctioned seed .gos/gates/check.sh landed" "$T82_DIR/inflight/.gos/gates/check.sh"
assert_file "G3g sanctioned seed .gos/.gitignore landed" "$T82_DIR/inflight/.gos/.gitignore"
if [ ! -e "$T82_DIR/inflight/.gos/.lock" ]; then
  echo "  ✓ G3h no .gos/.lock taken (lock-free global class, R2-F13)"; PASS=$((PASS+1))
else echo "  ✗ G3h .gos/.lock must never be created"; FAIL=$((FAIL+1)); fi

# --- G4: corrupt hooks state file — exit 1 envelope, path shown, zero seeding ---
t82_repo corrj
mkdir -p "$T82_DIR/corrj/.gos/cache"
printf 'this is { not json' > "$T82_DIR/corrj/.gos/cache/commitlint-hook.json"
OUT=$( cd "$T82_DIR/corrj" && node "$GOS" brownfield --json 2>/dev/null ); RC=$?
assert_exit "G4a corrupt hooks state file exits 1 (--json)" 1 "$RC"
printf '%s' "$OUT" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
assert isinstance(d,dict) and d['error']['code']==1, d
assert 'commitlint-hook.json' in d['error']['message'], d
print('ok')" ; assert_exit "G4b exit-1 --json envelope: code 1 + state-file path in message" 0 "$?"
if [ ! -e "$T82_DIR/corrj/hooks" ] && [ ! -e "$T82_DIR/corrj/commitlint.config.yaml" ] && [ ! -e "$T82_DIR/corrj/.gos/gates" ]; then
  echo "  ✓ G4c corrupt-state guard precedes all seeding (nothing written)"; PASS=$((PASS+1))
else echo "  ✗ G4c corrupt-state guard must fire before any write"; FAIL=$((FAIL+1)); fi

# --- G5: concurrent double-run — lock-free by design, atomic renames ---
t82_repo conc
printf 'race\n' > "$T82_DIR/conc/keep.txt"
( cd "$T82_DIR/conc" && node "$GOS" brownfield --json >/dev/null 2>&1 ) & P1=$!
( cd "$T82_DIR/conc" && node "$GOS" brownfield --json >/dev/null 2>&1 ) & P2=$!
wait "$P1"; R1=$?
wait "$P2"; R2=$?
assert_exit "G5a concurrent run #1 exits 0" 0 "$R1"
assert_exit "G5b concurrent run #2 exits 0" 0 "$R2"
if cmp -s "$CM_MASTER" "$T82_DIR/conc/hooks/commit-msg"; then echo "  ✓ G5c commit-msg byte-equal to master after the race"; PASS=$((PASS+1));
else echo "  ✗ G5c commit-msg corrupted by the race"; FAIL=$((FAIL+1)); fi
if cmp -s "$PP_MASTER" "$T82_DIR/conc/hooks/pre-push"; then echo "  ✓ G5d pre-push byte-equal to master after the race"; PASS=$((PASS+1));
else echo "  ✗ G5d pre-push corrupted by the race"; FAIL=$((FAIL+1)); fi
if cmp -s "$YAML_MASTER" "$T82_DIR/conc/commitlint.config.yaml"; then echo "  ✓ G5e yaml byte-equal to master"; PASS=$((PASS+1));
else echo "  ✗ G5e yaml differs from master"; FAIL=$((FAIL+1)); fi
if cmp -s "$CS_MASTER" "$T82_DIR/conc/.gos/gates/check.sh"; then echo "  ✓ G5f check.sh byte-equal to master"; PASS=$((PASS+1));
else echo "  ✗ G5f check.sh differs from master"; FAIL=$((FAIL+1)); fi
python3 - "$T82_DIR/conc/.gos/gates.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d['protect']==[] and d['forbid']==[] and d['lint'] is None, d
print('ok')
PY
assert_exit "G5g raced gates.json is still the empty skeleton" 0 "$?"
assert_contains "G5h raced .gos/.gitignore carries the .lock line" ".lock" "$(cat "$T82_DIR/conc/.gos/.gitignore")"
if [ ! -e "$T82_DIR/conc/.gos/.lock" ]; then
  echo "  ✓ G5i no lock file after the race (never taken)"; PASS=$((PASS+1))
else echo "  ✗ G5i .gos/.lock left behind"; FAIL=$((FAIL+1)); fi
G5_TMP=$(find "$T82_DIR/conc" -path '*/.git' -prune -o -name '*.tmp*' -print)
assert_eq "G5j no atomic-write temp leftovers (.*.tmp<pid>-<ts>)" "" "$G5_TMP"

# --- G6: stdin closed — identical behavior (prompt-free proof) ---
t82_repo sopen
printf 'k\n' > "$T82_DIR/sopen/keep.txt"
t82_repo sclosed
printf 'k\n' > "$T82_DIR/sclosed/keep.txt"
OUT_A=$( cd "$T82_DIR/sopen" && node "$GOS" brownfield </dev/null 2>&1 ); RC_A=$?
OUT_B=$( cd "$T82_DIR/sclosed" && node "$GOS" brownfield 0<&- 2>&1 ); RC_B=$?
assert_exit "G6a stdin-open run exits 0" 0 "$RC_A"
assert_exit "G6b stdin-closed run exits 0" 0 "$RC_B"
assert_eq "G6c report byte-identical (root-path normalized)" \
  "$(printf '%s' "$OUT_A" | sed "s|$T82_DIR/sopen|ROOT|g")" \
  "$(printf '%s' "$OUT_B" | sed "s|$T82_DIR/sclosed|ROOT|g")"
assert_file "G6d stdin-closed run completed adoption (hooks seeded)" "$T82_DIR/sclosed/hooks/commit-msg"

# --- G7: zero-network — unshare -rn primary, require-hook net stub fallback ---
# The stub ships in the section itself (first-class fallback): it replaces
# net.connect/createConnection/createServer + http(s).request/get with
# throwers; the tripwire proves a real socket attempt dies with the marker.
cat > "$T82_DIR/netstub.cjs" <<'STUB'
// T82 net stub — any socket attempt throws with a greppable marker.
function die(what) { throw new Error('T82-NET-BLOCKED: ' + what + ' attempted'); }
try {
  const net = require('net');
  net.connect = () => die('net.connect');
  net.createConnection = () => die('net.createConnection');
  net.createServer = () => die('net.createServer');
  const http = require('http');
  http.request = () => die('http.request');
  http.get = () => die('http.get');
  const https = require('https');
  https.request = () => die('https.request');
  https.get = () => die('https.get');
} catch (e) { /* module unavailable: nothing to stub */ }
STUB
OUT=$( cd "$T82_DIR" && NODE_OPTIONS="--require $T82_DIR/netstub.cjs" node -e "require('http').get('http://127.0.0.1:1/')" 2>&1 ); TRIP=$?
if [ "$TRIP" -ne 0 ] && printf '%s' "$OUT" | grep -q 'T82-NET-BLOCKED'; then
  echo "  ✓ G7a net stub tripwire: socket attempt dies with the marker"; PASS=$((PASS+1))
else echo "  ✗ G7a net stub tripwire did not fire (stub is dead code)"; FAIL=$((FAIL+1)); fi
G7_MECH=""
if unshare -rn true >/dev/null 2>&1; then
  t82_repo netns
  OUT=$( cd "$T82_DIR/netns" && unshare -rn node "$GOS" brownfield --json 2>&1 ); RC=$?
  assert_exit "G7b unshare -rn (no netns) run exits 0" 0 "$RC"
  assert_file "G7c unshare run completed adoption (hooks seeded)" "$T82_DIR/netns/hooks/commit-msg"
  G7_MECH="unshare"
else
  echo "  ○ G7b unshare -rn unavailable here — net stub is the fallback"
fi
t82_repo netstub
OUT=$( cd "$T82_DIR/netstub" && NODE_OPTIONS="--require $T82_DIR/netstub.cjs" node "$GOS" brownfield --json 2>&1 ); RC=$?
assert_exit "G7d net-stub run exits 0 (all sockets throw)" 0 "$RC"
assert_file "G7e net-stub run completed adoption (hooks seeded)" "$T82_DIR/netstub/hooks/commit-msg"
if [ -n "$G7_MECH" ] || [ "$RC" -eq 0 ]; then
  echo "  ✓ G7f at least one zero-network mechanism ran (mech: ${G7_MECH:-net-stub})"; PASS=$((PASS+1))
else echo "  ✗ G7f no zero-network mechanism executed"; FAIL=$((FAIL+1)); fi

t82_teardown
echo "--- T82 done ---"
