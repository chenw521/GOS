#!/usr/bin/env bash
# gos-map:fn bin/lib/core/lock.cjs#fn:guardCwd bin/lib/core/gitprobe.cjs#fn:isTracked
# gos-map:cmd status,checkpoint,stage,init
# repo-id guard + worktree detection (T4a) — Truths T-01/T-02/T-03.
# Facts asserted:
#   - static: lock.cjs carries no project_root re-anchor (identity is de-pathed)
#   - protocol-variant self-consistency: guard passes when state.repo_id is the
#     hash of origin's URL, for https (plain/credentials) / scp / ssh:// / git://
#   - multi-remote set span: state bound to the https family passes while the
#     repo's remotes spell the same repo across families (origin rotated too)
#   - uppercase-hex repo_id accepted via the lowercase retry
#   - fresh clone w/ tracked v4 state: read-class (status) AND write-class
#     (stage show — lock taken, no semantic write) leave state.json
#     byte-identical; the clone's worktree stays clean (T-01/T-02)
#   - foreign remotes → write-class dies exit 1 with the anchor-fix hint;
#     state.json byte-identical after the die (guard wrote nothing)
#   - linked worktree + tracked state.json → die with guidance on BOTH the
#     read and the write class (worktrees share one state file)
#   - no remotes → advisory pass (no die): repo_id null is SILENT (null IS the
# advisory record); a stamped binding warns exactly once per invocation
#   - repo_id null + remotes present → guard derives and stores (the ONE
#     sanctioned opportunistic state write): untracked after init, and a
#     tracked state whose ONLY delta is the repo_id stamp
# Standalone-safe: self-provisions env when not run under test/run-sections.sh.

T95_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T95_STANDALONE=1
  T95_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T95_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T95_SELFROOT"
  export TESTBASE="$(mktemp -d "$T95_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T95_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t95"
mkdir -p "$T95_DIR" && cd "$T95_DIR" || exit 1

t95_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T95_DIR"
  if [ "$T95_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t95_teardown EXIT

PASS=0
FAIL=0
t95_ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
t95_bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

t95_sha() { sha256sum "$1" | cut -d' ' -f1; }

t95_id() {  # t95_id <url> — deriveRepoId via the module (never a hardcoded hash)
  node -e '
    const s = require(process.env.GOS_ROOT + "/bin/lib/core/state.cjs");
    const id = s.deriveRepoId(process.argv[1]);
    if (id == null) { console.error("deriveRepoId(" + process.argv[1] + ") = null"); process.exit(1); }
    console.log(id);
  ' "$1"
}

t95_state() {  # t95_state <repo_id|'null'> — write a v4 fixture state into ./.gos
  REPO_ID="$1" python3 - <<'PYEOF'
import json, os, sys
rid = os.environ["REPO_ID"]
st = {
    "schema_version": 4,
    "repo_id": None if rid == "null" else rid,
    "level": 2,
    "current_stage": "BUILD",
    "completed_stages": ["INTENT", "THINK", "PLAN"],
    "intent": {"summary": "t95 fixture", "confirmed": True},
    "approvals": {},
    "spec_path": None,
    "plan_path": None,
    "project": False,
    "requirements": [{"id": "R-01", "text": "t95 fixture", "phase": None, "level": 2}],
    "decisions": [],
    "observable_truths": [],
    "gaps": [],
    "checkpoints": [],
}
os.makedirs(".gos", exist_ok=True)
json.dump(st, open(".gos/state.json", "w"), indent=2)
PYEOF
}

V_HTTPS="https://github.com/octocat/widget.git"
V_HTTPS_CREDS="https://user:secret@github.com/octocat/widget.git"
V_SCP="git@github.com:octocat/widget.git"
V_SSHURL="ssh://git@github.com:22/octocat/widget.git"
V_GITURL="git://github.com/octocat/widget.git"
V_FOREIGN="https://github.com/alice/foreigner.git"

echo "--- T95: repo-id guard + worktree detection (T4a, D-12/D-18) ---"

# --- V1: static — the project_root re-anchor write-back path is gone ---
V1=$(grep -c "project_root" "$GOS_ROOT/bin/lib/core/lock.cjs" || true)
if [ "$V1" = "0" ]; then t95_ok "V1 lock.cjs carries no project_root re-anchor (de-pathed identity)"; else t95_bad "V1 lock.cjs still mentions project_root ($V1 hit(s))"; fi

# --- V2: protocol-variant self-consistency — state stamped from origin's own spelling ---
V2_N=0; V2_FAIL=0
for U in "$V_HTTPS" "$V_HTTPS_CREDS" "$V_SCP" "$V_SSHURL" "$V_GITURL"; do
  V2_N=$((V2_N+1))
  mkdir -p "var-$V2_N" && cd "var-$V2_N" || exit 1
  git init -q -b main . && git commit -q --allow-empty -m root
  ID=$(t95_id "$U") || { t95_bad "V2.$V2_N id derivation failed for $U"; cd "$T95_DIR"; V2_FAIL=1; break; }
  t95_state "$ID"
  git remote add origin "$U"
  set +e; OUT=$(node "$GOS" stage show 2>&1); RC=$?; set -e
  if [ "$RC" -eq 0 ]; then t95_ok "V2.$V2_N guard passes for origin spelling: $U"; else t95_bad "V2.$V2_N guard died for $U (rc=$RC): $(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"; V2_FAIL=1; fi
  cd "$T95_DIR"
done
[ "$V2_FAIL" -eq 0 ] || :

# --- V3: fresh clone w/ tracked v4 state — byte-identical + clean worktree (T-01/T-02) ---
mkdir -p origin && cd origin
git init -q -b main . && git commit -q --allow-empty -m root
ID_HTTPS=$(t95_id "$V_HTTPS")
t95_state "$ID_HTTPS"
git add -f .gos/state.json && git commit -q -m "tracked state"
cd "$T95_DIR"
git clone -q "$T95_DIR/origin" clone
cd clone
git remote set-url origin "$V_HTTPS"   # real clones carry real URLs, not local paths
S0=$(t95_sha .gos/state.json)
set +e; OUT_R=$(node "$GOS" status 2>&1); RC_R=$?; set -e
S1=$(t95_sha .gos/state.json)
set +e; OUT_W=$(node "$GOS" stage show 2>&1); RC_W=$?; set -e
S2=$(t95_sha .gos/state.json)
if [ "$RC_R" -eq 0 ] && [ "$S0" = "$S1" ]; then t95_ok "V3a read-class (status) works, state.json byte-identical"; else t95_bad "V3a read-class: rc=$RC_R sha $S0 -> $S1"; fi
if [ "$RC_W" -eq 0 ] && [ "$S1" = "$S2" ]; then t95_ok "V3b write-class (stage show, no semantic write) leaves state.json byte-identical"; else t95_bad "V3b write-class byte-stability: rc=$RC_W sha $S1 -> $S2"; fi
V3_DIRTY=$(git status --porcelain --untracked-files=all)
if [ -z "$V3_DIRTY" ]; then t95_ok "V3c clone worktree stays clean (no stray .gos writes)"; else t95_bad "V3c clone worktree dirty: $V3_DIRTY"; fi

# --- V4: multi-remote family span + origin rotation + uppercase retry ---
git remote add up-scp "$V_SCP"
git remote add up-git "$V_GITURL"
set +e; OUT=$(node "$GOS" stage show 2>&1); RC=$?; set -e
if [ "$RC" -eq 0 ]; then t95_ok "V4a https-family state passes with ssh/git-family sibling remotes (set semantics)"; else t95_bad "V4a multi-family remote set: rc=$RC $(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"; fi
git remote set-url origin "$V_SCP"    # rotate origin across families — membership must still hold
git remote set-url up-scp "$V_HTTPS"  # the set spans families even with origin rotated off https
set +e; OUT=$(node "$GOS" stage show 2>&1); RC=$?; set -e
if [ "$RC" -eq 0 ]; then t95_ok "V4b origin rotated to scp spelling still passes (membership, not origin-wins)"; else t95_bad "V4b origin rotation: rc=$RC"; fi
python3 -c "
import json
s = json.load(open('.gos/state.json')); s['repo_id'] = s['repo_id'].upper()
json.dump(s, open('.gos/state.json', 'w'), indent=2)"
set +e; OUT=$(node "$GOS" stage show 2>&1); RC=$?; set -e
if [ "$RC" -eq 0 ]; then t95_ok "V4c uppercase-hex repo_id accepted via lowercase retry"; else t95_bad "V4c uppercase retry: rc=$RC"; fi
python3 -c "
import json
s = json.load(open('.gos/state.json')); s['repo_id'] = s['repo_id'].lower()
json.dump(s, open('.gos/state.json', 'w'), indent=2)"
git remote set-url origin "$V_HTTPS"

# --- V5: foreign remotes → die with anchor-fix hint, state untouched ---
S_F=$(t95_sha .gos/state.json)
git remote set-url origin "$V_FOREIGN"
git remote remove up-scp; git remote remove up-git
set +e; OUT=$(node "$GOS" checkpoint save --stage BUILD --unit u --done d 2>&1); RC=$?; set -e
if [ "$RC" -eq 1 ]; then t95_ok "V5a foreign-remotes state dies exit 1 on write-class"; else t95_bad "V5a foreign-remotes: rc=$RC (want 1)"; fi
if printf '%s' "$OUT" | grep -q "repo identity mismatch"; then t95_ok "V5b die names the repo identity mismatch"; else t95_bad "V5b die message lacks identity wording: $(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"; fi
if printf '%s' "$OUT" | grep -q "anchor fix"; then t95_ok "V5c die carries the anchor-fix hint"; else t95_bad "V5c die lacks anchor-fix hint"; fi
if [ "$S_F" = "$(t95_sha .gos/state.json)" ]; then t95_ok "V5d state.json byte-identical after the guard die (no rogue write)"; else t95_bad "V5d guard die mutated state.json"; fi

# --- V6: linked worktree + tracked state.json → die (read AND write class) ---
git worktree add -q "$T95_DIR/wt" -b wt95 2>/dev/null || true
if [ -d "$T95_DIR/wt" ]; then
  cd "$T95_DIR/wt"
  set +e; OUT=$(node "$GOS" status 2>&1); RC=$?; set -e
  if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "worktree"; then t95_ok "V6a worktree+tracked state: read-class dies with guidance"; else t95_bad "V6a worktree read-class: rc=$RC out=$(printf '%s' "$OUT" | head -1)"; fi
  set +e; OUT=$(node "$GOS" checkpoint save --stage BUILD --unit u --done d 2>&1); RC=$?; set -e
  if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "worktree"; then t95_ok "V6b worktree+tracked state: write-class dies with guidance"; else t95_bad "V6b worktree write-class: rc=$RC"; fi
  cd "$T95_DIR/clone"
  git worktree remove --force "$T95_DIR/wt" 2>/dev/null || true
else
  t95_bad "V6 worktree add failed — section cannot verify the die"
fi

# --- V7: no remotes → advisory pass (no die; null is silent, stamped warns once) ---
cd "$T95_DIR"
mkdir -p adv-null && cd adv-null
git init -q -b main . && git commit -q --allow-empty -m root
t95_state "null"
set +e; OUT=$(node "$GOS" checkpoint save --stage BUILD --unit a --done b 2>&1); RC=$?; set -e
if [ "$RC" -eq 0 ] && ! printf '%s' "$OUT" | grep -q "advisory"; then t95_ok "V7a no remotes + repo_id null → silent advisory pass (null IS the D-18 record), write proceeds"; else t95_bad "V7a no-remotes null: rc=$RC out=$(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"; fi
cd "$T95_DIR"
mkdir -p adv-stamped && cd adv-stamped
git init -q -b main . && git commit -q --allow-empty -m root
t95_state "$ID_HTTPS"   # stamped id, but the repo has no remotes to verify against
set +e; OUT=$(node "$GOS" checkpoint save --stage BUILD --unit a --done b 2>&1); RC=$?; set -e
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "advisory"; then t95_ok "V7b no remotes + stamped repo_id → advisory pass (no die)"; else t95_bad "V7b no-remotes stamped: rc=$RC out=$(printf '%s' "$OUT" | head -2 | tr '\n' ' ')"; fi
ADV_N=$(printf '%s' "$OUT" | grep -c "advisory" || true)
if [ "$ADV_N" -eq 1 ]; then t95_ok "V7c advisory warns exactly once per invocation"; else t95_bad "V7c advisory line count = $ADV_N (want 1)"; fi

# --- V8: repo_id null + remotes → guard derives and stores (the sanctioned write) ---
cd "$T95_DIR"
mkdir -p ds-init && cd ds-init
git init -q -b main . && git commit -q --allow-empty -m root
node "$GOS" init 2 "t95 derive+store" >/dev/null 2>&1; IRC=$?
git remote add origin "$V_HTTPS"
set +e; node "$GOS" stage show >/dev/null 2>&1; SRC=$?; set -e   # write-class w/o semantic write — only the guard can stamp
DS1=$(python3 -c "
import json
s = json.load(open('.gos/state.json'))
print('%s|%s|%s' % (s.get('repo_id'), s.get('schema_version'), 'version' in s))")
if [ "$IRC" -eq 0 ] && [ "$SRC" -eq 0 ] && [ "$DS1" = "$ID_HTTPS|5|False" ]; then
  t95_ok "V8a null+remotes: guard stamps repo_id (origin-wins), v5 clean, no dead version key"; else t95_bad "V8a derive+store: init rc=$IRC stage rc=$SRC state=$DS1 want $ID_HTTPS|5|False"; fi
cd "$T95_DIR"
mkdir -p ds-tracked && cd ds-tracked
git init -q -b main . && git commit -q --allow-empty -m root
t95_state "null"
git add -f .gos/state.json && git commit -q -m "state"
git remote add origin "$V_HTTPS"
set +e; node "$GOS" stage show >/dev/null 2>&1; SRC=$?; set -e
MIN=$(T95_ID_HTTPS="$ID_HTTPS" python3 - <<'PYEOF'
import json, os
after = json.load(open('.gos/state.json'))
want = after.get('repo_id')
problems = []
if os.environ['T95_ID_HTTPS'] not in (want or ''):
    problems.append('repo_id=' + str(want))
# only-delta check: mask repo_id, deep-compare against git HEAD's copy of the file
import subprocess
head = subprocess.run(['git', 'show', 'HEAD:.gos/state.json'], capture_output=True, text=True).stdout
before = json.loads(head)
a2 = dict(after); b2 = dict(before)
a2['repo_id'] = None; b2['repo_id'] = None
if a2 != b2:
    problems.append('non-repo_id delta')
print('BAD ' + '; '.join(problems) if problems else 'OK')
PYEOF
) || MIN="BAD python-fixture-check"
if [ "$SRC" -eq 0 ] && [ "$MIN" = "OK" ]; then t95_ok "V8b tracked state: only delta is the repo_id stamp (conservative minimal write)"; else t95_bad "V8b tracked derive+store: rc=$SRC check=$MIN"; fi

echo "--- T95 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
