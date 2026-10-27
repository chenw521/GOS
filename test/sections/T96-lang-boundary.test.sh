#!/usr/bin/env bash
# gos-map:cmd gap,concerns,lessons,decision
# language boundary at all three GOS text stores + gap rewrite.
# Facts asserted:
#   - boundary trigger = gitprobe.isTracked(<store file>) at EACH store's write
#     path: tracked state.json + zh decision → exit 1; tracked concerns.md +
#     zh `gos concerns add` → exit 1; tracked lessons.json + zh lessons add →
#     exit 1 — bilingual guidance (en + zh) pulled from the locale catalogs
#   - fail-closed: GIT_DIR poison with ALL stores untracked still exits 1
# (the boundary never falls open; primitive)
#   - all-untracked fixture: CJK accepted normally (no behavior change)
#   - `gos gap rewrite <G-id> --text` clears a legacy zh gap description when
#     untracked; tracked concerns.md + zh --text → exit 1 (gap text flows into
#     concerns.md via stage-back write-back)
#   - i18n-inventory hasCJK==0 on the touched bin/ files
# Env: GOS, TESTBASE, assert helpers sourced by runner (standalone-safe).
T96_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T96_STANDALONE=1
  T96_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T96_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T96_SELFROOT"
  export TESTBASE="$(mktemp -d "$T96_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T96_DIR=""

t96_fresh() {
  T96_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t96"
  mkdir -p "$T96_DIR" && cd "$T96_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t96_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T96_DIR"; }

# assert helpers: counter-bumping versions of the runner's four (identical
# ✓/✗ output format — the runner counts output rows; the counters feed this
# section's own exit gate, so standalone runs signal failures via rc too).
assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if [ -z "$expected" ]; then
    echo "  ✗ $label (empty pattern always matches — use assert_file/assert_eq)"; FAIL=$((FAIL+1))
  elif echo "$actual" | grep -q "$expected"; then
    echo "  ✓ $label"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected: '$expected')"
    echo "    actual: ${actual:0:160}"; FAIL=$((FAIL+1))
  fi
}
assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then
    echo "  ✓ $label (exit $actual)"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected exit $expected, got '${actual:-<none>}')"; FAIL=$((FAIL+1))
  fi
}
assert_file() {
  local label="$1" fpath="$2"
  if [ -n "$fpath" ] && [ -e "$fpath" ]; then
    echo "  ✓ $label"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (missing: '${fpath:-<none>}')"; FAIL=$((FAIL+1))
  fi
}
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ✓ $label"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected: '$expected', got: '$actual')"; FAIL=$((FAIL+1))
  fi
}

PASS=0
FAIL=0

echo "--- T96: language boundary at the three GOS text stores + gap rewrite ---"

# --- L1: export surface — hasCJK + firstCJKLeaf + dieTrackedStoreCJK via core index ---
t96_fresh
R1=$(node -e '
const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
const bad = [];
if (core.hasCJK("plain ascii text") !== false) bad.push("ascii flagged CJK");
if (core.hasCJK("decision title") !== false) bad.push("english flagged CJK");
if (core.hasCJK("中文标题") !== true) bad.push("cjk ideograph missed");
if (core.hasCJK("fullwidth ＡＢ") !== true) bad.push("fullwidth missed");
if (core.hasCJK("punctuation 、。") !== true) bad.push("cjk punctuation missed");
if (typeof core.dieTrackedStoreCJK !== "function") bad.push("dieTrackedStoreCJK not exported");
const hit = core.firstCJKLeaf({ a: { b: ["ok", "中文"] }, c: "x" });
if (!hit || hit.path !== "state.a.b[1]" || hit.text !== "中文") bad.push("firstCJKLeaf hit wrong: " + JSON.stringify(hit));
if (core.firstCJKLeaf({ a: "clean" }) !== null) bad.push("firstCJKLeaf false positive");
if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
console.log("OK");
' 2>&1)
if [ "$R1" = "OK" ]; then
  echo "  ✓ L1 exports: hasCJK/firstCJKLeaf/dieTrackedStoreCJK via core index"; PASS=$((PASS+1))
else
  echo "  ✗ L1 exports: $R1"; FAIL=$((FAIL+1))
fi
t96_teardown

# --- L2: store 1 state.json — tracked + zh decision dies at writeState (leaf walk) ---
t96_fresh
node "$GOS" init 3 "t96 state boundary" >/dev/null 2>&1
git add -f .gos/state.json && git commit -q -m track-state
set +e; OUT=$(node "$GOS" decision add D-01 "中文决策标题必须被拒绝" --rationale "r" 2>&1); RC=$?; set -e
assert_exit "L2 tracked state + zh decision → exit 1" "1" "$RC"
assert_contains "L2 bilingual: en guidance" "language boundary: state.json is git-tracked" "$OUT"
assert_contains "L2 bilingual: zh guidance" "仅允许英文" "$OUT"
if grep -q "中文决策标题" .gos/state.json 2>/dev/null; then
  echo "  ✗ L2 zh leaked into state.json (died after write)"; FAIL=$((FAIL+1))
else
  echo "  ✓ L2 state.json unchanged (die precedes the write)"; PASS=$((PASS+1))
fi
t96_teardown

# --- L3: store 2 concerns.md — tracked + zh `gos concerns add` dies ---
t96_fresh
node "$GOS" concerns add "baseline english worry" >/dev/null 2>&1
git add .gos/concerns.md && git commit -q -m track-concerns
set +e; OUT=$(node "$GOS" concerns add "中文担忧条目" 2>&1); RC=$?; set -e
assert_exit "L3 tracked concerns.md + zh add → exit 1" "1" "$RC"
assert_contains "L3 bilingual: en guidance" "language boundary: concerns.md is git-tracked" "$OUT"
assert_contains "L3 bilingual: zh guidance" "仅允许英文" "$OUT"
N=$(grep -c '^- \[' .gos/concerns.md)
assert_eq "L3 concerns.md unchanged (1 entry)" "1" "$N"
t96_teardown

# --- L4: store 3 lessons.json — tracked + zh lessons add dies at the mint chokepoint ---
t96_fresh
node "$GOS" init 3 "t96 lessons boundary" >/dev/null 2>&1
node "$GOS" lessons add --type project --scene t96 --lesson "english baseline lesson" >/dev/null 2>&1
git add .gos/lessons.json && git commit -q -m track-lessons
set +e; OUT=$(node "$GOS" lessons add --type project --scene t96 --lesson "中文教训不能入库" 2>&1); RC=$?; set -e
assert_exit "L4 tracked lessons.json + zh add → exit 1" "1" "$RC"
assert_contains "L4 bilingual: en guidance" "language boundary: lessons.json is git-tracked" "$OUT"
assert_contains "L4 bilingual: zh guidance" "仅允许英文" "$OUT"
N=$(python3 -c "import json; print(len(json.load(open('.gos/lessons.json'))['entries']))")
assert_eq "L4 lessons.json unchanged (1 entry)" "1" "$N"
t96_teardown

# --- L5: fail-closed — GIT_DIR poison with all stores untracked still exits 1 ---
t96_fresh
node "$GOS" concerns add "english seed worry" >/dev/null 2>&1
set +e; OUT=$(GIT_DIR="$T96_DIR/dead-git-dir" node "$GOS" concerns add "中毒环境下的中文" 2>&1); RC=$?; set -e
assert_exit "L5 concerns: GIT_DIR poison + zh → exit 1 (fail-closed)" "1" "$RC"
assert_contains "L5 concerns bilingual guidance" "language boundary" "$OUT"
t96_teardown
t96_fresh
node "$GOS" init 3 "t96 poison state" >/dev/null 2>&1
set +e; OUT=$(GIT_DIR="$T96_DIR/dead-git-dir" node "$GOS" decision add D-01 "毒化状态写入" --rationale "r" 2>&1); RC=$?; set -e
assert_exit "L5 state: GIT_DIR poison + zh → exit 1 (fail-closed)" "1" "$RC"
assert_contains "L5 state bilingual guidance" "language boundary" "$OUT"
t96_teardown

# --- L6: all-untracked fixture — CJK accepted normally (no behavior change) ---
t96_fresh
set +e; OUT=$(node "$GOS" concerns add "未跟踪存储接受中文" 2>&1); RC=$?; set -e
assert_exit "L6 untracked concerns: zh accepted" "0" "$RC"
grep -q "未跟踪存储接受中文" .gos/concerns.md && echo "  ✓ L6 zh concern line recorded"; PASS=$((PASS+1)) || { echo "  ✗ L6 zh concern line missing"; FAIL=$((FAIL+1)); }
node "$GOS" init 3 "t96 untracked accept" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" decision add D-01 "未跟踪状态的中文决策" --rationale "中文理由" 2>&1); RC=$?; set -e
assert_exit "L6 untracked state: zh decision accepted" "0" "$RC"
set +e; OUT=$(node "$GOS" lessons add --type project --scene t96 --lesson "未跟踪教训可以中文" 2>&1); RC=$?; set -e
assert_exit "L6 untracked lessons: zh accepted" "0" "$RC"
N=$(python3 -c "import json; print(len(json.load(open('.gos/lessons.json'))['entries']))")
assert_eq "L6 zh lesson recorded (1 entry)" "1" "$N"
t96_teardown

# --- L7: gap rewrite — clears legacy zh description; boundary on tracked concerns.md ---
t96_fresh
node "$GOS" init 3 "t96 gap rewrite" >/dev/null 2>&1
python3 - <<'PYEOF'
import json
p = '.gos/state.json'
s = json.load(open(p))
s['gaps'] = [{'id': 'G-123456', 'type': 'major', 'description': '遗留的中文缺口描述', 'status': 'open'}]
json.dump(s, open(p, 'w'), indent=2)
PYEOF
set +e; OUT=$(node "$GOS" gap rewrite G-123456 --text "clean english gap text" 2>&1); RC=$?; set -e
assert_exit "L7a gap rewrite (untracked) exits 0" "0" "$RC"
D=$(python3 -c "import json; s=json.load(open('.gos/state.json')); print([g['description'] for g in s['gaps'] if g['id']=='G-123456'][0])")
assert_eq "L7a legacy zh description cleared" "clean english gap text" "$D"
if grep -q "遗留的中文缺口描述" .gos/state.json; then
  echo "  ✗ L7a zh still present in state.json"; FAIL=$((FAIL+1))
else
  echo "  ✓ L7a zh gone from state.json"; PASS=$((PASS+1))
fi
# tracked concerns.md trigger: zh --text dies, description untouched
node "$GOS" concerns add "en worry for rewrite gate" >/dev/null 2>&1
git add .gos/concerns.md && git commit -q -m track-concerns
set +e; OUT=$(node "$GOS" gap rewrite G-123456 --text "重写为中文必须拒绝" 2>&1); RC=$?; set -e
assert_exit "L7b tracked concerns.md + zh gap text → exit 1" "1" "$RC"
assert_contains "L7b bilingual: en guidance" "language boundary: concerns.md is git-tracked" "$OUT"
assert_contains "L7b bilingual: zh guidance" "仅允许英文" "$OUT"
D=$(python3 -c "import json; s=json.load(open('.gos/state.json')); print([g['description'] for g in s['gaps'] if g['id']=='G-123456'][0])")
assert_eq "L7b description unchanged after refused rewrite" "clean english gap text" "$D"
# fail-closed argument shapes
set +e; OUT=$(node "$GOS" gap rewrite G-999999 --text "x" 2>&1); RC=$?; set -e
assert_exit "L7c unknown G-id → exit 1" "1" "$RC"
assert_contains "L7c not-found wording" "not found" "$OUT"
set +e; OUT=$(node "$GOS" gap rewrite G-123456 2>&1); RC=$?; set -e
assert_exit "L7d missing --text → exit 1" "1" "$RC"
set +e; OUT=$(node "$GOS" gap bogus 2>&1); RC=$?; set -e
assert_exit "L7e unknown sub → exit 1 (usage line)" "1" "$RC"
assert_contains "L7e usage lists rewrite" "Usage: gos gap <list|resolve|rewrite|migrate|history>" "$OUT"
t96_teardown

# --- L8: i18n-inventory hasCJK==0 on the touched bin/ files ---
INV=$( cd "$GOS_ROOT" && bash test/checks/i18n-inventory.sh --json 2>/dev/null ); IRC=$?
if [ "$IRC" -eq 0 ]; then PASS=$((PASS+1)); echo "  ✓ L8 inventory scanner exit 0"; else FAIL=$((FAIL+1)); echo "  ✗ L8 inventory scanner rc=$IRC"; fi
CJKROWS=$(printf '%s' "$INV" | python3 -c '
import json, sys
rows = json.load(sys.stdin)
touched = ["bin/lib/core/state.cjs", "bin/lib/core/fsio.cjs", "bin/lib/knowledge/concerns.cjs",
           "bin/lib/knowledge/lessons-json.cjs", "bin/lib/nav/cmds.cjs", "bin/lib/core/locales/en.cjs"]
hits = [r for r in rows if r["file"] in touched and r["hasCJK"]]
print(len(hits))
for h in hits[:5]: print(h["file"] + ":" + str(h["line"]), file=sys.stderr)
')
assert_eq "L8 hasCJK==0 on touched bin files" "0" "$CJKROWS"

t96_teardown
if [ "$T96_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi

echo "--- T96 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
