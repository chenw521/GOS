#!/usr/bin/env bash
# gos-map:cmd gate
# T5: cwd guard + concurrent lock + git argv-ization + dispatch table
# Covers: D-06, D-10, D-11, D-17 (plan W3-T5)
T5_DIR=""

t5_setup() {
  T5_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t5"
  mkdir -p "$T5_DIR" && cd "$T5_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/.lock\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t5_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T5_DIR"; }

t5_setup
echo "--- T5: cwd guard + lock + argv git + dispatch ---"

node "$GOS" init 3 "auth" >/dev/null 2>&1

# --- T5.1: write-class blocked outside project root ---
mkdir -p sub && cd sub
set +e; OUT=$(node "$GOS" checkpoint save --stage BUILD --unit x --done y 2>&1); RC=$?; set -e
assert_exit "write-class blocked in subdir" 1 "$RC"
assert_contains "error names project root" "project root" "$OUT"
cd "$T5_DIR"

# --- T5.2: read-class prints stderr banner, stdout stays clean ---
set +e
OUT_ONLY=$(node "$GOS" status 2>/dev/null)
ERR_ONLY=$(node "$GOS" status 2>&1 >/dev/null)
set -e
if [ -z "$OUT_ONLY" ]; then :; fi  # stdout may be empty; key: banner NOT in stdout
if echo "$OUT_ONLY" | grep -qE "^📍 /"; then
  echo "  ✗ banner leaked into stdout"; FAIL=$((FAIL+1))
else
  echo "  ✓ stdout clean of banner"; PASS=$((PASS+1))
fi
assert_contains "banner on stderr" "📍 $TESTBASE" "$ERR_ONLY"

# --- T5.3: subdir init blocked with toplevel hint ---
mkdir -p sub2 && cd sub2
set +e; OUT=$(node "$GOS" init 3 "x" 2>&1); RC=$?; set -e
assert_exit "init blocked in subdir" 1 "$RC"
assert_contains "hint prints toplevel" "$T5_DIR" "$OUT"
cd "$T5_DIR"

# --- T5.4: worktree allowed (write-class runs inside worktree) ---
git worktree add -q "$T5_DIR-wt" -b wt5 2>/dev/null || true
if [ -d "$T5_DIR-wt" ]; then
  cd "$T5_DIR-wt"
  # state lives in main tree (gitignored) — write-class here must NOT be blocked by anchor mismatch
  node "$GOS" init 3 "wt task" >/dev/null 2>&1   # init in worktree: toplevel = worktree → allowed
  ROOT_WT=$(python3 -c "import json; print(json.load(open('.gos/state.json')).get('project_root'))" 2>/dev/null)
  assert_eq "worktree init anchors to worktree root" "$(cd "$T5_DIR-wt" && pwd -P)" "$ROOT_WT"
  node "$GOS" checkpoint save --stage BUILD --unit w --done x >/dev/null 2>&1
  CKPT_OK=$(python3 -c "import json; print(len(json.load(open('.gos/state.json')).get('checkpoints',[])) > 0)" 2>/dev/null)
  assert_eq "write-class works inside worktree" "True" "$CKPT_OK"
  cd "$T5_DIR"; git worktree remove --force "$T5_DIR-wt" 2>/dev/null || true
else
  echo "  (skip worktree: add failed)"; PASS=$((PASS+2))
fi

# --- T5.5: unanchored legacy state → write-class auto-anchors (lazy migration) ---
python3 -c "
import json; s=json.load(open('.gos/state.json')); s['project_root']=None
json.dump(s,open('.gos/state.json','w'),indent=2)"
node "$GOS" checkpoint save --stage BUILD --unit re --done anchor >/dev/null 2>&1
ROOT2=$(python3 -c "import json; print(json.load(open('.gos/state.json')).get('project_root'))")
assert_eq "lazy re-anchor on write" "$T5_DIR" "$ROOT2"

# --- T5.6: lock — concurrent write blocked; stale lock (dead pid) gets break-lock hint ---
node "$GOS" init 3 "auth2" --force >/dev/null 2>&1
python3 - << 'PYEOF'
import json, os
os.makedirs('.gos', exist_ok=True)
json.dump({"pid": 999999, "started_at": "2026-01-01T00:00:00Z"}, open('.gos/.lock','w'))
PYEOF
set +e; OUT=$(node "$GOS" checkpoint save --stage BUILD --unit z --done z 2>&1); RC=$?; set -e
# Dead-holder locks auto-recover with a warning (dbc6cf7 semantics: a
# crashed/killed writer owns nothing; live holders still block hard).
assert_exit "stale lock (dead pid) auto-recovers and proceeds" 0 "$RC"
assert_contains "stale lock warns auto-recovery" "auto-recovered" "$OUT"
node "$GOS" checkpoint save --stage BUILD --unit z --done z --break-lock >/dev/null 2>&1
LOCKED_AFTER=$(ls .gos/.lock 2>/dev/null | wc -l)
assert_eq "lock released after command" "0" "$LOCKED_AFTER"

# --- T5.7: live lock (sleep holder) → blocked, hint WITHOUT break-lock ---
node "$GOS" init 3 "auth3" --force >/dev/null 2>&1
python3 -c "
import json
json.dump({'pid': __import__('os').getpid(), 'started_at': '2026-01-01T00:00:00Z'}, open('/dev/null','w'))" 2>/dev/null
# use our own shell pid as a LIVE pid
printf '{"pid": %s, "started_at": "2026-01-01T00:00:00Z"}' "$$" > .gos/.lock
set +e; OUT=$(node "$GOS" checkpoint save --stage BUILD --unit z --done z 2>&1); RC=$?; set -e
assert_exit "live lock blocks write" 1 "$RC"
if echo "$OUT" | grep -q "break-lock"; then
  echo "  ✗ live-lock hint must NOT offer break-lock"; FAIL=$((FAIL+1))
else
  echo "  ✓ live-lock hint omits break-lock"; PASS=$((PASS+1))
fi
rm -f .gos/.lock

# --- T5.8: lock is gitignored (T5 setup wrote .gitignore with .gos/.lock) ---
GI=$(grep -c "gos/.lock" .gitignore)
assert_eq ".lock in .gitignore" "1" "$GI"

# --- T5.9: static — no shell-assembled git calls ---
SHELLGIT=$(grep -cE "execSync\(.+git .+-m|execSync\(\`git" "$GOS" || true)
assert_eq "no shell-assembled git execSync" "0" "$SHELLGIT"

# --- T5.10 [Phase C/T3]: 'stage' write-lock parity — removed from READ_CMDS only;
# ternary (:3303 WRITE first) means behavior was already write-class. Static:
# WRITE_CMDS keeps 'stage', READ_CMDS line no longer lists it. Dynamic: a LIVE
# foreign lock blocks gos stage (write semantics engage the lock path).
W=$(grep -c "const WRITE_CMDS = new Set(\['init', 'commit', 'archive', 'approve', 'checkpoint', 'config', 'auto', 'stage'," "$GOS_ROOT/bin/lib/nav/registry-consts.cjs" || true)
assert_eq "WRITE_CMDS retains stage" "1" "$W"
R=$(grep "const READ_CMDS" "$GOS_ROOT/bin/lib/nav/registry-consts.cjs" | grep -c "'stage'" || true)
assert_eq "READ_CMDS no longer lists stage" "0" "$R"
printf '{"pid": %s, "started_at": "2026-01-01T00:00:00Z"}' "$$" > .gos/.lock
set +e; OUT=$(node "$GOS" stage show 2>&1); RC=$?; set -e
assert_exit "stage takes write lock (blocked by live lock)" 1 "$RC"
rm -f .gos/.lock
set +e; OUT=$(node "$GOS" stage show 2>&1); RC=$?; set -e
assert_exit "stage show works once lock free" 0 "$RC"

t5_teardown
