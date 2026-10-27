#!/usr/bin/env bash
# gos-map:cmd truth,gate,commit
# : three-layer mounting — gate all chaining + BUILD/VERIFY commit embedding + sandbox escape hatch + spec_sha256 + status
# Env: GOS, TESTBASE, assert helpers
T19_DIR=""

# fixture paths follow the CLI supply (task/<id>/) — never hardcode .gos/ root
gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }
gos_plan() { node "$GOS" context plan 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["plan"])' 2>/dev/null; }

t19_setup() {
  T19_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t19"
  mkdir -p "$T19_DIR" && cd "$T19_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t19_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T19_DIR"; }

t19_mkstate() { python3 - "$1" <<'PYEOF'
import json,sys
p='.gos/state.json'
s=json.load(open(p))
exec(sys.argv[1])
json.dump(s,open(p,'w'),indent=2)
PYEOF
}

t19_semok() { # seed a semantically-passable state: D-01 covered by T1 whose file we touch
  rm -rf .gos
  # fixture hygiene: a prior section's bootstrap may have git-added the sidecar; a
 # tracked-but-missing sidecar is a LEGIT failure — clear it so semok starts clean
  node "$GOS" init 3 "t19 mounting" >/dev/null 2>&1
 # fixture hygiene AFTER init: init seeds edges.json+stages it (Phase D) — clear so this fixture's diff stays clean ( pattern)
  git rm -q --cached .gos/cache/edges.json 2>/dev/null || true
  git rm -q --cached .gos/cache/edges.lock 2>/dev/null || true   # [Phase D compat] one pathspec per call: multi-path rm fails WHOLE if any path unmatched
  git rm -q --cached .gos/logs/edge-audit.log 2>/dev/null || true
  git rm -q --cached .gos/.lessons-anchors.json 2>/dev/null || true
  HEAD=$(git rev-parse HEAD)
  t19_mkstate "s['current_stage']='BUILD'
s['decisions']=[{'id':'D-01','title':'d','rationale':'r','status':'covered','covered':True,'anchor':None}]
s['requirements']=[{'id':'R-01','text':'t','status':'active'}]
s['observable_truths']=[]
s['plan_snapshot']={'tasks':[{'id':'T1','covers':['D-01'],'files':['src/t19.js']}],'audit':[]}
s['task_head']='$HEAD'
s['task_head_pending']=False"
  echo "# t19 spec" > "$(gos_spec)"
  mkdir -p src
  echo "// t19" > src/t19.js
  echo "// marker $(date +%s%N)-$RANDOM" >> src/t19.js # ensure worktree diff hits T1 Files
}

t19_setup
echo "--- T19: mounting — gate all embed + commit embed + sandbox escape + spec_sha256 ---"

# --- T19.1: semantic failure (zero-hit Files) → commit build exit 1 [B-10] ---
node "$GOS" init 3 "t19 zero hit" >/dev/null 2>&1
HEAD=$(git rev-parse HEAD)
t19_mkstate "s['current_stage']='BUILD'
s['decisions']=[{'id':'D-01','title':'d','rationale':'r','status':'covered','covered':True,'anchor':None}]
s['requirements']=[{'id':'R-01','text':'t','status':'active'}]
s['observable_truths']=[]
s['plan_snapshot']={'tasks':[{'id':'T1','covers':['D-01'],'files':['zzz-never-touched.txt']}],'audit':[]}
s['task_head']='$HEAD'
s['task_head_pending']=False"
OUT=$(node "$GOS" commit build 2>&1); RC=$?
assert_exit "semantic zero-hit blocks BUILD commit" "1" "$RC"
assert_contains "failure names the zero-hit task" "T1" "$OUT"

# --- T19.2: bare GOS_SKIP_SEMANTIC=1 in production → exit 1 with unset guidance [B-10/R2-11] ---
OUT=$(GOS_SKIP_SEMANTIC=1 node "$GOS" commit build 2>&1); RC=$?
assert_exit "bare skip refused in production" "1" "$RC"
assert_contains "refusal mentions unset GOS_SKIP_SEMANTIC" "unset GOS_SKIP_SEMANTIC" "$OUT"
assert_contains "refusal mentions single-point commit rule" "single-point" "$OUT"

# --- T19.3: sandbox-bound escape → commit passes + skipBanner + state.semantic_skips [B-10/R4-F7] ---
rm -rf .gos && t19_semok
export GOS_TEST_SANDBOX="$(pwd -P)"
OUT=$(GOS_SKIP_SEMANTIC=1 node "$GOS" commit build 2>&1); RC=$?
assert_exit "sandbox-bound skip lets commit pass" "0" "$RC"
assert_contains "skip banner emitted" "semantic check skipped (sandbox-bound)" "$OUT"
SKIPS=$(python3 -c "import json;print(len(json.load(open('.gos/state.json')).get('semantic_skips',[])))")
assert_eq "semantic_skips recorded in state (sole writer)" "1" "$SKIPS"
unset GOS_TEST_SANDBOX

# --- T19.4: status shows skip count [R4-F9] ---
OUT=$(node "$GOS" status 2>&1)
assert_contains "status shows semantic skip count" "semantic skips" "$OUT"

# --- .3b (REVIEW #4): escape hatch skips ONLY the engine — deletion still blocks
rm -rf .gos && t19_semok
node "$GOS" lessons add --type project --scene "hatch" --lesson "b8 under escape hatch" >/dev/null 2>&1
python3 - <<'PYEOF'
import json
p = '.gos/lessons.json'
s = json.load(open(p))
s['entries'] = [e for e in s['entries'] if e.get('scene') != 'hatch']
json.dump(s, open(p, 'w'), indent=2)
PYEOF
export GOS_TEST_SANDBOX="$(pwd -P)"
OUT=$(GOS_SKIP_SEMANTIC=1 node "$GOS" commit build 2>&1); RC=$?
assert_exit "sandbox escape does NOT bypass B-8 lessons deletion" "1" "$RC"
assert_contains "B-8 refusal names pure-deletion" "pure-deletion" "$OUT"
node "$GOS" lessons anchor-rebuild --force >/dev/null 2>&1
OUT=$(GOS_SKIP_SEMANTIC=1 node "$GOS" commit build 2>&1); RC=$?
assert_exit "after disposal, escape-hatch commit passes" "0" "$RC"
unset GOS_TEST_SANDBOX

# --- .3c (REVIEW #11): negative escape paths — relative/other-dir/missing sandbox → refused
rm -rf .gos && t19_semok
OUT=$(GOS_TEST_SANDBOX="." GOS_SKIP_SEMANTIC=1 node "$GOS" commit build 2>&1); RC=$?
assert_exit "relative sandbox path refused" "1" "$RC"
assert_contains "refusal is from the hatch, not semantics" "unset GOS_SKIP_SEMANTIC" "$OUT"
OUT=$(GOS_TEST_SANDBOX="/tmp" GOS_SKIP_SEMANTIC=1 node "$GOS" commit build 2>&1); RC=$?
assert_exit "other-dir sandbox binding refused" "1" "$RC"
assert_contains "other-dir refusal names unset" "unset GOS_SKIP_SEMANTIC" "$OUT"
OUT=$(GOS_TEST_SANDBOX="/nonexistent/no-such-dir" GOS_SKIP_SEMANTIC=1 node "$GOS" commit build 2>&1); RC=$?
assert_exit "nonexistent sandbox path refused" "1" "$RC"

# --- .3d (Phase-1 audit): gate semantic carries spec-hash check
rm -rf .gos && t19_semok
t19_mkstate "s['spec_sha256']='deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef'"
OUT=$(node "$GOS" gate semantic 2>&1); RC=$?
assert_exit "gate semantic fails on tampered spec hash" "1" "$RC"
assert_contains "gate semantic names B-22" "B-22" "$OUT"
t19_mkstate "import hashlib,sys; s['spec_sha256']=hashlib.sha256(open('"$(gos_spec)"','rb').read()).hexdigest()"
OUT=$(node "$GOS" gate semantic 2>&1); RC=$?
assert_exit "gate semantic green with matching hash" "0" "$RC"
assert_contains "spec frozen check line present" "spec frozen" "$OUT"

# --- T19.5: gate all includes semantic chain + downgrade banner last line [D-33] ---
rm -rf .gos && t19_semok
# flip-reconcile leg (P4 ): earlier `commit build` runs git-committed .gos
# files whose task ids are one-shot — init never reseeds them, so the product
# adopt path cannot run on a rebuilt tree. Record them as adopted flips (the
# exact record shape `gos track` appends) so the leg sees an accounted trail.
git ls-files -- .gos | while read -r f; do
  case "$f" in
    .gos/cache/*|.gos/logs/*|.gos/archive/*|.gos/.lock|.gos/.ship-staging/*) continue ;;
  esac
  printf '{"ts":"%s","path":"%s","head":"%s","adopted":true}\n' \
    "$(date -u +%FT%TZ)" "$f" "$(git rev-parse HEAD)" >> .gos/track-manifest.json
done
OUT=$(node "$GOS" gate all 2>&1); RC=$?
# show failures inline when red (temporary diagnosis aid)
if [ "$RC" -ne 0 ]; then printf '%s\n' "$OUT" | grep -E "✗|evidence|fix:|README drift|orphan" | head -16 >&2; git ls-files -- .gos >&2; fi
assert_exit "gate all green on passable semantics" "0" "$RC"
assert_contains "gate all runs bidirectional check" "bidirectional" "$OUT"
LAST=$(printf '%s\n' "$OUT" | grep -v '^\s*$' | tail -1)
assert_contains "downgrade banner is LAST line" "gate checks syntax+consistency only" "$LAST"

# --- T19.6: gate semantic standalone ✓ also ends with banner [B-3] ---
OUT=$(node "$GOS" gate semantic 2>&1); RC=$?
assert_exit "gate semantic green" "0" "$RC"
LAST=$(printf '%s\n' "$OUT" | grep -v '^\s*$' | tail -1)
assert_contains "gate semantic banner last" "gate checks syntax+consistency only" "$LAST"

# --- T19.7: spec tampered after freeze → commit exit 1 [B-22] ---
t19_mkstate "s['spec_sha256']='deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef'"
echo "# tampered spec" > "$(gos_spec)"
OUT=$(node "$GOS" commit build 2>&1); RC=$?
assert_exit "spec tamper blocks commit" "1" "$RC"
assert_contains "spec mismatch names B-22 / re-commit think" "commit think" "$OUT"

# --- T19.8: VERIFY lazy-freeze path (no spec_sha256) walks through [F1] ---
rm -rf .gos && t19_semok
t19_mkstate "s['current_stage']='VERIFY'"
OUT=$(node "$GOS" commit verify 2>&1); RC=$?
assert_exit "VERIFY commit passes on sound semantics" "0" "$RC"
assert_contains "lazy-freeze banner on missing spec_sha256" "lazy-freeze" "$OUT"

# --- T19.9: pending task_head auto-anchor at commit [B-4③] ---
T19_P="$TESTBASE/test-$(date +%s)-$RANDOM-t19p"
mkdir -p "$T19_P" && cd "$T19_P" || exit 1
git init -q .
printf ".gos/state.json\n.gos/cache/\n" > .gitignore
node "$GOS" init 3 "t19 pending anchor" >/dev/null 2>&1
git add .gitignore && git commit -q -m first
OUT=$(node "$GOS" commit build 2>&1); RC=$?
assert_exit "pending anchor commit passes" "0" "$RC"
assert_contains "auto-anchor banner shown" "auto-anchored" "$OUT"
PENDING=$(python3 -c "import json;print(json.load(open('.gos/state.json')).get('task_head_pending'))")
assert_eq "pending flag cleared after anchor" "False" "$PENDING"
cd "$T19_DIR" || exit 1
rm -rf "$T19_P"

t19_teardown
