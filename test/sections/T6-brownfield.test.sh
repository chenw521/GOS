#!/usr/bin/env bash
# gos-map:cmd decision
T6_DIR=""

t6_setup() {
  T6_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t6"
  mkdir -p "$T6_DIR" && cd "$T6_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/.lock\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t6_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T6_DIR"; }

t6_setup
echo "--- T6: brownfield import detection ---"

# --- .1: existing handwritten DECISIONS.md → init --project warns + suggests import
mkdir -p .gos/project
cat > .gos/project/DECISIONS.md << 'EOF'
# Decision Index

| ID | Decision |
|:---|:---|
| D-01 | use JWT auth |
| D-02 | bcrypt cost 12 |
EOF
set +e; OUT=$(node "$GOS" init 4 "platform" --project 2>&1); RC=$?; set -e
assert_exit "init succeeds with brownfield present" 0 "$RC"
assert_contains "detects brownfield content" "existing" "$OUT"
assert_contains "suggests import command" "decision import" "$OUT"

# --- .2: import --all pulls brownfield entries in
set +e; OUT=$(node "$GOS" decision import --all 2>&1); RC=$?; set -e
assert_exit "import --all runs" 0 "$RC"
CNT=$(python3 -c "import json; print(len(json.load(open('.gos/project/project.json'))['decisions']))")
assert_eq "project.json has 2 imported decisions" "2" "$CNT"

# --- .3: empty template files → no brownfield warning
t6_teardown; t6_setup
set +e; OUT=$(node "$GOS" init 4 "platform" --project 2>&1); RC=$?; set -e
assert_exit "init succeeds on greenfield" 0 "$RC"
if echo "$OUT" | grep -q "decision import"; then
  echo "  ✗ greenfield must not warn"; FAIL=$((FAIL+1))
else
  echo "  ✓ greenfield silent (no import warning)"; PASS=$((PASS+1))
fi

t6_teardown
