#!/usr/bin/env bash
# gos-map:fn bin/lib/task/commit.cjs#fn:cmdCommit
# gos-map:file census.json
# gos-map:file test/pack-check.sh
# gos-map:file scripts/census-dispose.sh
# T66: census.json four-way reconciliation + disposition executor
# Cases: A=real-repo pack-check green  B=sandbox baseline green
#        b..j=mutation experiments (each must turn red / stay quiet)
#        k1..k7=dispose executor four-label matrix
# Runs pack-check against controlled sandbox copies built via git archive;
# the real repo itself is only read (plus gitignored machine-local anchors).
T66_DIR=""

t66_setup() {
  T66_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t66"
  mkdir -p "$T66_DIR"
}

t66_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T66_DIR"; }

t66_mksandbox() {  # $1 = sandbox dir; a committed copy of the tracked tree + census
  mkdir -p "$1"
  git -C "$GOS_ROOT" archive HEAD | tar -x -C "$1"
  cp "$GOS_ROOT/census.json" "$1/census.json" 2>/dev/null || true
  cp "$GOS_ROOT/test/pack-check.sh" "$1/test/pack-check.sh" 2>/dev/null || true
  cp "$GOS_ROOT/scripts/census-dispose.sh" "$1/scripts/census-dispose.sh" 2>/dev/null || true
  # gitignore-covered machine-local anchors (git:false census entries must be alive)
  mkdir -p "$1/.gos/cache" "$1/.gos/task" "$1/.gos/archive" "$1/.gos/project/milestones" "$1/.gos/project/feedback"
  [ -e "$1/.gos/state.json" ] || : > "$1/.gos/state.json"
  [ -e "$1/.gos/.lock" ] || : > "$1/.gos/.lock"
  [ -e "$1/.gos/project/RETROSPECTIVE.md" ] || : > "$1/.gos/project/RETROSPECTIVE.md"
  [ -e "$1/.changes.md" ] || : > "$1/.changes.md"
  [ -e "$1/hooks/commit-msg" ] || : > "$1/hooks/commit-msg"
  : > "$1/.gos/cache/probe"
  git -C "$1" init -q
  git -C "$1" add -A
  git -C "$1" commit -q -m t66-sandbox
}

t66_census_add() {  # $1=sandbox $2=key $3=git $4=npm — add/override a census entry
  node -e '
    const fs = require("fs");
    const c = JSON.parse(fs.readFileSync(process.argv[1] + "/census.json", "utf8"));
    c.entries[process.argv[2]] = { git: process.argv[3] === "true", npm: process.argv[4] === "true", note: "t66 mutation" };
    fs.writeFileSync(process.argv[1] + "/census.json", JSON.stringify(c, null, 2) + "\n");
  ' "$1" "$2" "$3" "$4"
}

t66_census_add_disp() {  # $1=sandbox $2=path $3=action — push a pending disposition
  node -e '
    const fs = require("fs");
    const p = process.argv[1] + "/census.json";
    const c = JSON.parse(fs.readFileSync(p, "utf8"));
    c.dispositions = c.dispositions || [];
    c.dispositions.push({ path: process.argv[2], action: process.argv[3], status: "pending", note: "t66" });
    fs.writeFileSync(p, JSON.stringify(c, null, 2) + "\n");
  ' "$1" "$2" "$3"
}

t66_run_pack() {  # $1=sandbox → PACK_OUT/PACK_RC
  PACK_OUT="$(cd "$1" && bash "$1/test/pack-check.sh" 2>&1)"; PACK_RC=$?
}

t66_pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
t66_fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
t66_assert_labeled() {  # label expected_rc actual_rc needle output source-tag
  if [ "$2" = "$3" ]; then t66_pass "$1 (exit $3)"; else t66_fail "$1 (expected exit $2, got $3)"; fi
  if printf '%s' "$5" | grep -q "$4"; then t66_pass "$1 message [$4]"; else t66_fail "$1 missing message [$4] in: $(printf '%s' "$5" | grep '^census' | head -3)"; fi
}
t66_assert_quiet() {  # label forbidden-needle output
  if printf '%s' "$2" | grep -q "$1"; then t66_fail "expected no line matching [$1]"; else t66_pass "no line matching [$1]"; fi
}

t66_setup
trap 't66_teardown' EXIT
PASS=0; FAIL=0
echo "--- T66: census four-way reconciliation + dispose executor ---"

# --- A: real repo reconciliation green ---
[ -e "$GOS_ROOT/.gos/state.json" ] || : > "$GOS_ROOT/.gos/state.json"
[ -e "$GOS_ROOT/.gos/.lock" ] || : > "$GOS_ROOT/.gos/.lock"
mkdir -p "$GOS_ROOT/.gos/cache"
RA_OUT="$(bash "$GOS_ROOT/test/pack-check.sh" 2>&1)"; RA_RC=$?
t66_assert_labeled "A1 real repo pack-check green" 0 "$RA_RC" "all checks passed" "$RA_OUT"

# --- B: sandbox baseline green (committed tracked tree + census) ---
t66_mksandbox "$T66_DIR/sb-base"
t66_run_pack "$T66_DIR/sb-base"
t66_assert_labeled "B1 sandbox baseline pack-check green" 0 "$PACK_RC" "all checks passed" "$PACK_OUT"

# --- b: unregistered untracked top-level dir → source ④ red ---
t66_mksandbox "$T66_DIR/sb-b"
mkdir -p "$T66_DIR/sb-b/stray-top" && echo x > "$T66_DIR/sb-b/stray-top/file.txt"
t66_run_pack "$T66_DIR/sb-b"
t66_assert_labeled "b untracked top-level dir rejected by ④" 1 "$PACK_RC" "unregistered untracked" "$PACK_OUT"

# --- c: npm-shipped path under npm:false entry → source ① red ---
t66_mksandbox "$T66_DIR/sb-c"
node -e '
  const fs = require("fs");
  const p = process.argv[1] + "/package.json";
  const pkg = JSON.parse(fs.readFileSync(p, "utf8"));
  pkg.files.push("test/");
  fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + "\n");
' "$T66_DIR/sb-c"
t66_run_pack "$T66_DIR/sb-c"
t66_assert_labeled "c npm-shipped npm:false path rejected by ①" 1 "$PACK_RC" "npm:false" "$PACK_OUT"

# --- d: npm:true entry never shipped → source ① red (missing direction) ---
t66_mksandbox "$T66_DIR/sb-d"
t66_census_add "$T66_DIR/sb-d" "docs" "true" "true"
t66_run_pack "$T66_DIR/sb-d"
t66_assert_labeled "d npm:true never-packed entry rejected by ①" 1 "$PACK_RC" "never appears in the pack" "$PACK_OUT"

# --- e + j: gitignore drift red via ③, and ④ stays quiet for the same probe ---
t66_mksandbox "$T66_DIR/sb-e"
sed -i '/^\.gos\/cache\/$/d' "$T66_DIR/sb-e/.gitignore"
t66_run_pack "$T66_DIR/sb-e"
t66_assert_labeled "e gitignore drift rejected by ③" 1 "$PACK_RC" "gitignore drift" "$PACK_OUT"
t66_assert_quiet "unregistered untracked file: .gos/cache/probe" "$PACK_OUT"

# --- f: root-matching entry → validator red ---
t66_mksandbox "$T66_DIR/sb-f"
t66_census_add "$T66_DIR/sb-f" "." "true" "true"
t66_run_pack "$T66_DIR/sb-f"
t66_assert_labeled "f root-matching entry rejected by validator" 1 "$PACK_RC" "root-matching" "$PACK_OUT"

# --- g: dead entry → validator red ---
t66_mksandbox "$T66_DIR/sb-g"
t66_census_add "$T66_DIR/sb-g" "path/that/never/exists" "true" "false"
t66_run_pack "$T66_DIR/sb-g"
t66_assert_labeled "g dead entry rejected by validator" 1 "$PACK_RC" "dead entry" "$PACK_OUT"

# --- h: tracked symlink under npm:true entry → source ① red ---
t66_mksandbox "$T66_DIR/sb-h"
ln -s ../../README.md "$T66_DIR/sb-h/skills/gos-link.md"
git -C "$T66_DIR/sb-h" add skills/gos-link.md
t66_run_pack "$T66_DIR/sb-h"
t66_assert_labeled "h symlink under npm:true entry rejected by ①" 1 "$PACK_RC" "symlink" "$PACK_OUT"

# --- i: gos commit stages census.json (ADD_PATHS static) ---
if grep -qF "'census.json'" "$GOS_ROOT/bin/lib/task/commit.cjs"; then
  t66_pass "i ADD_PATHS contains census.json"
else
  t66_fail "i ADD_PATHS missing census.json"
fi

# --- k1: git:true disposition → git rm only ---
t66_mksandbox "$T66_DIR/sb-k1"
t66_census_add "$T66_DIR/sb-k1" "scripts/release-validate.sh" "true" "false"
t66_census_add_disp "$T66_DIR/sb-k1" "scripts/release-validate.sh" "delete"
K1_OUT="$(printf 'y\n' | bash "$T66_DIR/sb-k1/scripts/census-dispose.sh" 2>&1)"; K1_RC=$?
if [ "$K1_RC" = 0 ]; then t66_pass "k1 dispose git:true exit 0"; else t66_fail "k1 dispose git:true exit $K1_RC: $K1_OUT"; fi
if [ -e "$T66_DIR/sb-k1/scripts/release-validate.sh" ]; then t66_fail "k1 file still on disk"; else t66_pass "k1 file removed from disk"; fi
if git -C "$T66_DIR/sb-k1" ls-files --error-unmatch scripts/release-validate.sh >/dev/null 2>&1; then t66_fail "k1 still tracked"; else t66_pass "k1 no longer tracked"; fi
D=$(node -e 'const c=require(process.argv[1]+"/census.json");const d=(c.dispositions||[]).find(x=>x.path==="scripts/release-validate.sh");console.log(d?d.status:"none")' "$T66_DIR/sb-k1")
[ "$D" = "done" ] && t66_pass "k1 disposition marked done" || t66_fail "k1 disposition status=$D"

# --- k2: untracked delete is a hard error without the flag ---
t66_mksandbox "$T66_DIR/sb-k2"
echo stray > "$T66_DIR/sb-k2/orphan.txt"
t66_census_add "$T66_DIR/sb-k2" "orphan.txt" "false" "false"
t66_census_add_disp "$T66_DIR/sb-k2" "orphan.txt" "delete"
K2_OUT="$(printf 'y\n' | bash "$T66_DIR/sb-k2/scripts/census-dispose.sh" 2>&1)"; K2_RC=$?
t66_assert_labeled "k2 untracked delete hard error" 1 "$K2_RC" "untracked" "$K2_OUT"
[ -e "$T66_DIR/sb-k2/orphan.txt" ] && t66_pass "k2 file preserved after refusal" || t66_fail "k2 file vanished after refusal"

# --- k2b: --allow-untracked-rm + typing back the exact full path ---
SB_ABS="$(cd "$T66_DIR/sb-k2" && pwd)"
K2B_OUT="$(printf '%s\n' "$SB_ABS/orphan.txt" | bash "$T66_DIR/sb-k2/scripts/census-dispose.sh" --allow-untracked-rm 2>&1)"; K2B_RC=$?
if [ "$K2B_RC" = 0 ]; then t66_pass "k2b echo-back removal exit 0"; else t66_fail "k2b exit $K2B_RC: $K2B_OUT"; fi
[ -e "$T66_DIR/sb-k2/orphan.txt" ] && t66_fail "k2b file still on disk" || t66_pass "k2b file removed"

# --- k3: git:false+npm:true → unship via package.json files edit ---
t66_mksandbox "$T66_DIR/sb-k3"
mkdir -p "$T66_DIR/sb-k3/extra" && echo mod > "$T66_DIR/sb-k3/extra/mod.md"
node -e '
  const fs = require("fs");
  const p = process.argv[1] + "/package.json";
  const pkg = JSON.parse(fs.readFileSync(p, "utf8"));
  pkg.files.push("extra/");
  fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + "\n");
' "$T66_DIR/sb-k3"
t66_census_add "$T66_DIR/sb-k3" "extra/mod.md" "false" "true"
t66_census_add_disp "$T66_DIR/sb-k3" "extra/mod.md" "unship"
K3_OUT="$(printf 'y\n' | bash "$T66_DIR/sb-k3/scripts/census-dispose.sh" 2>&1)"; K3_RC=$?
if [ "$K3_RC" = 0 ]; then t66_pass "k3 unship exit 0"; else t66_fail "k3 exit $K3_RC: $K3_OUT"; fi
if printf '%s' "$K3_OUT" | grep -q "package.json"; then t66_pass "k3 names the files-array change"; else t66_fail "k3 output never mentions package.json"; fi
F=$(node -e 'const p=require(process.argv[1]+"/package.json");console.log((p.files||[]).includes("extra/")?"present":"gone")' "$T66_DIR/sb-k3")
[ "$F" = "gone" ] && t66_pass "k3 files array no longer ships extra/" || t66_fail "k3 files array still ships extra/"
[ -e "$T66_DIR/sb-k3/extra/mod.md" ] && t66_pass "k3 file untouched (unship only edits manifest)" || t66_fail "k3 unship deleted the file"

# --- k4: git:false+npm:false → no verb, display + manual guidance only ---
t66_mksandbox "$T66_DIR/sb-k4"
echo stray > "$T66_DIR/sb-k4/orphan2.txt"
t66_census_add "$T66_DIR/sb-k4" "orphan2.txt" "false" "false"
t66_census_add_disp "$T66_DIR/sb-k4" "orphan2.txt" "unship"
K4_OUT="$(printf 'y\n' | bash "$T66_DIR/sb-k4/scripts/census-dispose.sh" 2>&1)"; K4_RC=$?
if [ "$K4_RC" = 0 ]; then t66_pass "k4 display-only exit 0"; else t66_fail "k4 exit $K4_RC: $K4_OUT"; fi
if printf '%s' "$K4_OUT" | grep -q "manual"; then t66_pass "k4 prints manual guidance"; else t66_fail "k4 no manual guidance line"; fi
[ -e "$T66_DIR/sb-k4/orphan2.txt" ] && t66_pass "k4 file untouched" || t66_fail "k4 display-only removed the file"

# --- k5: directory path refused ---
t66_mksandbox "$T66_DIR/sb-k5"
t66_census_add_disp "$T66_DIR/sb-k5" "scripts" "delete"
K5_OUT="$(printf 'y\n' | bash "$T66_DIR/sb-k5/scripts/census-dispose.sh" 2>&1)"; K5_RC=$?
t66_assert_labeled "k5 directory disposition refused" 1 "$K5_RC" "directory" "$K5_OUT"

# --- k6: disposition path not a census entry refused ---
t66_mksandbox "$T66_DIR/sb-k6"
t66_census_add_disp "$T66_DIR/sb-k6" "not-in-census.txt" "delete"
K6_OUT="$(printf 'y\n' | bash "$T66_DIR/sb-k6/scripts/census-dispose.sh" 2>&1)"; K6_RC=$?
t66_assert_labeled "k6 non-census path refused" 1 "$K6_RC" "not a census entry" "$K6_OUT"

# --- k7: no batch mode / unknown flag refused ---
t66_mksandbox "$T66_DIR/sb-k7"
K7_OUT="$(bash "$T66_DIR/sb-k7/scripts/census-dispose.sh" --yes 2>&1)"; K7_RC=$?
t66_assert_labeled "k7 unknown flag refused (no batch mode)" 1 "$K7_RC" "unknown option" "$K7_OUT"

echo "--- T66 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
