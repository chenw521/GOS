#!/usr/bin/env bash
# gos-map:cmd gate,lessons
# : inversion exemption (json audit) + gate lessons five invariants + dual-side expiry
# Env: GOS, TESTBASE, assert helpers. Global-path assertions use fake-HOME [R3-F7]
T18_DIR=""
T18_HOME=""

t18_setup() {
  T18_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t18"
  mkdir -p "$T18_DIR" && cd "$T18_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
  T18_HOME="$T18_DIR/home"
  mkdir -p "$T18_HOME"
}

t18_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T18_DIR"; }

t18_g() { HOME="$T18_HOME" node "$GOS" "$@"; }

t18_mkstate() { # $1 = python snippet mutating state
  python3 - "$1" <<'PYEOF'
import json,sys
p='.gos/state.json'
s=json.load(open(p))
exec(sys.argv[1])
json.dump(s,open(p,'w'),indent=2)
PYEOF
}

t18_node() { HOME="$T18_HOME" node -e "$1"; }

t18_setup
echo "--- T18: F-1 exemption (json audit) + gate lessons json integrity ---"

t18_g init 3 "t18 f1 gate lessons" >/dev/null 2>&1

# incident state: gaps + redteam findings + archive approval + ship check skipped
t18_mkstate "s['gaps']=[{'stage':'VERIFY','what':'minor gap'}]; s['redteam_rounds']=[{'round':1,'findings':2}]; s.setdefault('approvals',{})['ARCHIVE']=True"

# --- .1: incident task, no lesson today, no skip → archive exit 1 ( two-of-two missing)
export GOS_SKIP_SHIP_CHECK=1
OUT=$(t18_g archive 2>&1); RC=$?
assert_exit "incident archive without lesson/skip → exit 1" "1" "$RC"
assert_contains "F-1 failure mentions the two options" "lessons skip --reason" "$OUT"

# --- T18.2: lessons skip --reason → archive passes + reason + cumulative count [D-34/R4-F7] ---
OUT=$(t18_g lessons skip --reason "t18 accepted residual risk" 2>&1); RC=$?
assert_exit "skip records successfully" "0" "$RC"
if python3 -c "import json; s=json.load(open('.gos/lessons.json')); assert any(r['what']=='skip' for r in s['audit'])" 2>/dev/null; then
  echo "  ✓ skip audit row lives in json truth"; PASS=$((PASS+1))
else
  echo "  ✗ skip audit row missing from json"; FAIL=$((FAIL+1))
fi
OUT=$(t18_g archive 2>&1); RC=$?
assert_exit "archive passes after skip exemption" "0" "$RC"
assert_contains "archive output shows skip reason" "t18 accepted residual risk" "$OUT"
assert_contains "archive output shows cumulative skip count" "cumulative skips: 1" "$OUT"
unset GOS_SKIP_SHIP_CHECK

# --- T18.2b (REVIEW #3): a YESTERDAY skip never exempts today's archive [D-34 per-archive] ---
T18_STALE="$TESTBASE/test-$(date +%s)-$RANDOM-t18stale"
mkdir -p "$T18_STALE/.gos/cache" && cd "$T18_STALE" || exit 1
git init -q . && git commit -q --allow-empty -m root
printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
t18_g init 3 "t18 stale skip" >/dev/null 2>&1
t18_node '
const j = require(process.env.GOS_ROOT + "/bin/lib/knowledge/lessons-json.cjs");
const fs = require("fs");
const store = j.emptyStore();
const base = { at: "2020-01-01", type: "project", scene: "seed", lesson: "stale seed lesson", tags: [], origin: "v2" };
const { id } = j.mintId(base, () => false);
store.entries.push({ id, ...base });
j.appendAuditRow(store, "add", "seed", { new_id: id });
const row = { at: "2020-01-01T00:00:00.000Z", what: "skip", why: "ancient skip", tty_derived: false };
row.prev = store.audit[store.audit.length - 1].self;
row.self = j.auditSelfHash(row);
store.audit.push(row);
store.chain_head = row.self;
j.saveStore({ truth: ".gos/lessons.json", anchor: ".gos/cache/.lessons-anchors.json", file: ".gos/lessons.md", global: false }, store);
'
t18_mkstate "s['gaps']=[{'stage':'VERIFY','what':'g'}]; s['redteam_rounds']=[{'round':1,'findings':1}]; s.setdefault('approvals',{})['ARCHIVE']=True"
OUT=$(GOS_SKIP_SHIP_CHECK=1 t18_g archive 2>&1); RC=$?
assert_exit "stale (yesterday) skip does NOT exempt" "1" "$RC"
assert_contains "still demands lesson or fresh skip" "lessons skip --reason" "$OUT"
cd "$T18_DIR" || exit 1
rm -rf "$T18_STALE"

# --- .2c: skip never touches .changes.md (sealed archive), symlink moot
t18_g init 3 "t18 symlink changes" >/dev/null 2>&1
rm -f real-changes.md && echo "victim" > real-changes.md
rm -f .changes.md; ln -s real-changes.md .changes.md
OUT=$(t18_g lessons skip --reason "symlink attack" 2>&1); RC=$?
assert_exit "skip succeeds without touching .changes.md" "0" "$RC"
if grep -q "symlink attack" real-changes.md 2>/dev/null; then
  echo "  ✗ symlink attack wrote through"; FAIL=$((FAIL+1))
else
  echo "  ✓ no write-through to symlink target"; PASS=$((PASS+1))
fi
rm -f .changes.md real-changes.md

# --- T18.3: gate lessons — pure deletion from json → exit 1 [B-8] ---
t18_g init 3 "t18 gate lessons deletion" >/dev/null 2>&1
t18_g lessons add --type project --scene "d" --lesson "deletion canary lesson" >/dev/null 2>&1
python3 - <<'PYEOF'
import json
p = '.gos/lessons.json'
s = json.load(open(p))
s['entries'] = [e for e in s['entries'] if e.get('scene') != 'd']
json.dump(s, open(p, 'w'), indent=2)
PYEOF
OUT=$(t18_g gate lessons 2>&1); RC=$?
assert_exit "gate lessons fails on pure deletion" "1" "$RC"
assert_contains "pure-deletion failure names B-8" "pure-deletion" "$OUT"
OUT=$(t18_g lessons anchor-rebuild --force 2>&1); RC=$?
assert_exit "anchor-rebuild --force records disposal, recovers gate" "0" "$RC"
OUT=$(t18_g gate lessons 2>&1); RC=$?
assert_exit "gate lessons green after disposal" "0" "$RC"
assert_contains "gate lessons green line" "✓ lessons" "$OUT"

# --- T18.4: gate lessons expiry checks BOTH sides from json (advisory, exit 0) [B-11] ---
mkdir -p "$T18_HOME/.config/gos"
t18_node '
const j = require(process.env.GOS_ROOT + "/bin/lib/knowledge/lessons-json.cjs");
const fs = require("fs");
const os = require("os");
const dir = process.env.HOME + "/.config/gos";
fs.mkdirSync(dir, { recursive: true });
const store = j.emptyStore();
const base = { at: "2026-01-01", type: "model", scene: "g", lesson: "stale global model lesson", tags: [], expires: "2026-01-02", origin: "v2" };
const { id } = j.mintId(base, () => false);
store.entries.push({ id, ...base });
j.appendAuditRow(store, "add", "fixture", { new_id: id });
j.saveStore({ truth: dir + "/lessons.json", truthBak: dir + "/.lessons.json.bak", anchor: dir + "/.lessons-anchors.json", file: dir + "/lessons.md", global: true }, store);
'
OUT=$(t18_g gate lessons 2>&1); RC=$?
assert_contains "expired GLOBAL lesson warned" "stale global model lesson" "$OUT"
if echo "$OUT" | grep -q "global"; then
  echo "  ✓ dual-file expiry tags source (global)"; PASS=$((PASS+1))
else
  echo "  ✗ expiry output lacks global source tag"; FAIL=$((FAIL+1))
fi
assert_exit "expiry is advisory (exit 0)" "0" "$RC"

# --- T18.5: cmdContext read_files includes global lessons view + untrusted annotation [B-16/R1-F8] ---
GLBMD="$T18_HOME/.config/gos/lessons.md"
t18_g init 3 "t18 context untrusted" >/dev/null 2>&1
t18_mkstate "s['current_stage']='THINK'"
OUT=$(t18_g context 2>&1)
assert_contains "read_files includes global lessons view path" "$GLBMD" "$OUT"
assert_contains "untrusted annotation present" "untrusted historical notes — verify before acting" "$OUT"
OUT=$(t18_g instructions think 2>&1)
assert_contains "instructions think mentions dual files" "global" "$OUT"

# --- T18.6: B-21 archive-side — plan drift vs frozen snapshot → warn banner [R4-F8] ---
t18_g init 3 "t18 b21 drift" >/dev/null 2>&1
T18_TID="$(python3 -c 'import json;print(json.load(open(".gos/state.json"))["task_head"][:8])')"
mkdir -p ".gos/task/$T18_TID"
t18_mkstate "s['current_stage']='VERIFY'; s['plan_path']=('.gos/task/'+s['task_head'][:8]+'/plan.md'); s['plan_snapshot']={'tasks':[{'id':'T1','covers':['D-01'],'files':['a.txt']},{'id':'T2','covers':['D-02'],'files':['b.txt']}],'audit':[]}; s['gaps']=[]; s['redteam_rounds']=[{'round':1,'findings':0}]; s.setdefault('approvals',{})['ARCHIVE']=True"
cat > ".gos/task/$T18_TID/plan.md" <<'EOF'
# Plan
### Wave 1
#### T1: first
- **Covers**: D-01
- **Files**: a.txt
EOF
OUT=$(GOS_SKIP_SHIP_CHECK=1 t18_g archive 2>&1)
assert_contains "B-21 drift warning emitted" "B-21" "$OUT"

t18_teardown
