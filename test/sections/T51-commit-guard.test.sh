#!/usr/bin/env bash
# gos-map:fn bin/lib/task/commit.cjs#fn:cmdCommit
# gos-map:cmd commit
# T51: commit generator guard bundle + ADD_PATHS expansion
# Cases: A=empty-commit guard (duplicate run) B=CJK subject guard
#        C=--subject english escape hatch D=git-failure state rollback
#        E=ADD_PATHS static assertions F=no --allow-empty
T51_DIR=""

t51_setup() {
  T51_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t51"
  mkdir -p "$T51_DIR" && cd "$T51_DIR" || exit 1
}

t51_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T51_DIR"; }

t51_state_field() { python3 -c "import json;print(json.load(open('.gos/state.json'))['$1'])" 2>/dev/null; }
t51_state_sha() { sha256sum .gos/state.json 2>/dev/null | cut -d' ' -f1; }

t51_setup
trap 't51_teardown' EXIT
PASS=0; FAIL=0
echo "--- T51: commit guard bundle + ADD_PATHS ---"

# --- A: duplicate run with a fully settled worktree → exit 1, HEAD and stage frozen ---
t51_setup
git init -q . && git commit -q --allow-empty -m root
node "$GOS" init 1 "t51 dup run" >/dev/null 2>&1
node "$GOS" commit intent >/dev/null 2>&1
git add -A && git commit -q -m settle
HEAD_A0=$(git rev-parse HEAD); SHA_A0=$(t51_state_sha); STAGE_A0=$(t51_state_field current_stage)
set +e; AOUT=$(node "$GOS" commit intent 2>&1); ARC=$?; set -e
assert_exit "A1 no changes → exit 1" 1 "$ARC"
assert_contains "A2 error says no changes to commit" "no changes to commit" "$AOUT"
assert_eq "A3 HEAD unchanged" "$HEAD_A0" "$(git rev-parse HEAD)"
assert_eq "A4 state.stage unchanged" "$STAGE_A0" "$(t51_state_field current_stage)"
assert_eq "A5 state file untouched (byte-identical)" "$SHA_A0" "$(t51_state_sha)"

# --- B: CJK intent summary without --subject → exit 1, no state advance ---
t51_teardown; t51_setup
git init -q . && git commit -q --allow-empty -m root
node "$GOS" init 1 "中文意图空壳提交回归" >/dev/null 2>&1
HEAD_B0=$(git rev-parse HEAD); SHA_B0=$(t51_state_sha); STAGE_B0=$(t51_state_field current_stage)
set +e; BOUT=$(node "$GOS" commit intent 2>&1); BRC=$?; set -e
assert_exit "B1 CJK subject without --subject → exit 1" 1 "$BRC"
assert_contains "B2 error suggests --subject escape hatch" '\-\-subject' "$BOUT"
assert_eq "B3 HEAD unchanged" "$HEAD_B0" "$(git rev-parse HEAD)"
assert_eq "B4 state.stage not advanced" "$STAGE_B0" "$(t51_state_field current_stage)"
assert_eq "B5 state file untouched" "$SHA_B0" "$(t51_state_sha)"

# --- C: --subject english escape hatch succeeds (english intent: D-17 boundary
# forbids CJK state content once the store is tracked by the commit flip) ---
t51_teardown; t51_setup
git init -q . && git commit -q --allow-empty -m root
node "$GOS" init 1 "english intent escape hatch t51" >/dev/null 2>&1
HEAD_C0=$(git rev-parse HEAD); STAGE_C0=$(t51_state_field current_stage)
set +e; COUT=$(node "$GOS" commit intent --subject "english escape subject t51" 2>&1); CRC=$?; set -e
assert_exit "C1 --subject english → exit 0" 0 "$CRC"
if [ "$(git rev-parse HEAD)" != "$HEAD_C0" ]; then
  echo "  ✓ C2 HEAD advanced (real commit created)"; PASS=$((PASS+1))
else
  echo "  ✗ C2 HEAD did not advance"; FAIL=$((FAIL+1))
fi
assert_contains "C3 commit subject uses the explicit english text" "english escape subject t51" "$(git log -1 --format=%s)"
if [ "$(t51_state_field current_stage)" != "$STAGE_C0" ]; then
  echo "  ✓ C4 state.stage advanced"; PASS=$((PASS+1))
else
  echo "  ✗ C4 state.stage stuck at $STAGE_C0"; FAIL=$((FAIL+1))
fi

# --- D: git commit failure (pre-commit hook) → exit 1 + state write rolled back ---
t51_teardown; t51_setup
git init -q . && git commit -q --allow-empty -m root
printf '#!/bin/sh\nexit 1\n' > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
node "$GOS" init 1 "t51 rollback probe" >/dev/null 2>&1
HEAD_D0=$(git rev-parse HEAD); SHA_D0=$(t51_state_sha); STAGE_D0=$(t51_state_field current_stage)
set +e; DOUT=$(node "$GOS" commit intent 2>&1); DRC=$?; set -e
assert_exit "D1 git failure → exit 1 (no silent advance)" 1 "$DRC"
assert_contains "D2 rollback announced" "rolled back" "$DOUT"
assert_eq "D3 HEAD unchanged" "$HEAD_D0" "$(git rev-parse HEAD)"
assert_eq "D4 state.stage not advanced" "$STAGE_D0" "$(t51_state_field current_stage)"
assert_eq "D5 state file restored to pre-run bytes" "$SHA_D0" "$(t51_state_sha)"

# --- E: ADD_PATHS contains the five new entries (static) ---
for p in '.github/' 'CHANGELOG.md' '.changes.md' 'hooks/' 'scripts/'; do
  if grep -qF "'$p'" "$GOS_ROOT/bin/lib/task/commit.cjs"; then
    echo "  ✓ E ADD_PATHS has $p"; PASS=$((PASS+1))
  else
    echo "  ✗ E ADD_PATHS missing $p"; FAIL=$((FAIL+1))
  fi
done

# --- F: --allow-empty confined to the single stage-advance exemption site (static) ---
N_EMPTY=$(grep -c 'allow-empty' "$GOS_ROOT/bin/lib/task/commit.cjs" || true)
assert_eq "F1 allow-empty occurrences = 1 (stage-advance exemption only)" "1" "$N_EMPTY"
N_EXEMPT=$(grep -c "const advancing" "$GOS_ROOT/bin/lib/task/commit.cjs" || true)
assert_eq "F2 exemption keyed on current-stage match" "1" "$N_EXEMPT"

# --- G: stage-advance exemption — clean-tree FIRST advance succeeds, duplicate blocked ---
t51_setup
git init -q . && git commit -q --allow-empty -m root
printf '.gos/state.json\n.gos/.lock\n.gos/cache/\n' > .gitignore
git add .gitignore && git commit -q -m ignore
node "$GOS" init 1 "t51 advance" >/dev/null 2>&1
set +e; GOUT=$(node "$GOS" commit intent 2>&1); GRC=$?; set -e
assert_exit "G1 clean-tree first advance commit succeeds" 0 "$GRC"
assert_contains "G2 stage advanced past INTENT (Lv1 flow)" "BUILD" "$(t51_state_field current_stage)"
HEAD_G0=$(git rev-parse HEAD)
set +e; GOUT2=$(node "$GOS" commit intent 2>&1); GRC2=$?; set -e
assert_exit "G3 duplicate advance after progress → exit 1" 1 "$GRC2"
assert_contains "G4 duplicate says no changes to commit" "no changes to commit" "$GOUT2"
assert_eq "G5 HEAD unchanged by duplicate" "$HEAD_G0" "$(git rev-parse HEAD)"
t51_teardown; t51_setup

echo "--- T51 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
