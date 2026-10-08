#!/usr/bin/env bash
# gos-map:cmd commit,gate
# T35c: closure human summary (one-line commit/gate tail summary; explicit hint on an empty edge net; advisory)
# Covers: D-35 (cmdCommit region shares serial execution with T4)
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner

T35C_DIR=""

t35c_setup() {
  T35C_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t35c"
  mkdir -p "$T35C_DIR" && cd "$T35C_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t35c-seed
}

t35c_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T35C_DIR"; }

t35c_setup
echo "--- T35c: R-06 closure human summary ---"

# C1 empty edge net: commit tail states the non-coverage explicitly (silence was once misread as checked)
node "$GOS" init 1 "c1 empty net" >/dev/null 2>&1
OUT=$(node "$GOS" commit intent 2>&1)
assert_contains "C1 empty-net explicit hint" "the edge net does not cover this change" "$OUT"

# C2 non-empty net: manual edges trigger the impact summary (mustCheck>=1 -> the N number appears)
t35c_teardown; t35c_setup
node "$GOS" init 1 "c2 with edge" >/dev/null 2>&1
node "$GOS" commit intent >/dev/null 2>&1
mkdir -p src
printf 'module.exports = 1;\n' > src/util.js
printf "const u = require('./util');\nmodule.exports = { u };\n" > src/app.js
git add -A && git commit -q -m chain
node "$GOS" map edge add src/app.js src/util.js >/dev/null 2>&1
printf '// touch\n' >> src/app.js
OUT2=$(node "$GOS" commit think 2>&1 || true)
# commit think at Lv1 skips THINK spec checks; summary rides the closure block either way
SUM=$(printf '%s' "$OUT2" | grep -c "📎 Summary: this change touches [1-9][0-9]* file(s)")
if [ "${SUM:-0}" -ge 1 ]; then echo "  ✓ C2 edge-net summary with N"; else
  # fallback: commit may have printed advisory closure path with 0 (edge dead?) — explicit check
  echo "  ✗ C2 edge-net summary missing (out tail below)"; printf '%s\n' "$OUT2" | tail -8
fi

# C3 gate all exit code unaffected by the summary (summary is purely advisory — gate semantics unchanged)
t35c_teardown; t35c_setup
node "$GOS" init 0 "c3 advisory" >/dev/null 2>&1
node "$GOS" commit intent >/dev/null 2>&1
node "$GOS" gate all >/dev/null 2>&1; RC_BEFORE=$?
node "$GOS" commit verify >/dev/null 2>&1
node "$GOS" gate all >/dev/null 2>&1; RC_AFTER=$?
assert_eq "C3 gate rc unchanged by summary" "$RC_BEFORE" "$RC_AFTER"

t35c_teardown
echo "T35c-u-closure-summary done"
