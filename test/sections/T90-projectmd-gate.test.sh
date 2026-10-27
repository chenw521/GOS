#!/usr/bin/env bash
# gos-map:fn bin/lib/knowledge/phase.cjs#fn:projectMdSectionReport bin/lib/knowledge/phase.cjs#fn:projectMdFilled bin/lib/task/archive.cjs#fn:cmdArchive bin/lib/task/context.cjs#fn:cmdContext
# gos-map:cmd archive,context
# PROJECT.md gate — approve-archive pre-flight refuses a TODO-only
#      skeleton / three junk lines / a section-less file before any mutation; a filled
#      PROJECT.md passes, joins `gos context think` read_files, and init seeds TODO
#      guidance that brownfield detection ignores.
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by the runner;
# direct invocation defines its own fallbacks ( pattern).
PASS=0
FAIL=0
command -v assert_exit >/dev/null || assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected exit $expected, got '${actual:-<none>}')"; FAIL=$((FAIL+1)); fi
}
command -v assert_contains >/dev/null || assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if [ -z "$expected" ]; then
    echo "  ✗ $label (empty pattern always matches)"; FAIL=$((FAIL+1))
  elif printf '%s' "$actual" | grep -q "$expected"; then
    echo "  ✓ $label"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected: '$expected')"; echo "    actual: ${actual:0:200}"; FAIL=$((FAIL+1))
  fi
}
command -v assert_file >/dev/null || assert_file() {
  local label="$1" fpath="$2"
  if [ -n "$fpath" ] && [ -e "$fpath" ]; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (missing: '${fpath:-<none>}')"; FAIL=$((FAIL+1)); fi
}

GOS="${GOS:-$(git rev-parse --show-toplevel 2>/dev/null)/bin/gos.cjs}"
[ -n "${GOS_ROOT:-}" ] || GOS_ROOT="$(cd "$(dirname "$GOS")/.." && pwd)"
[ -n "${TESTBASE:-}" ] || TESTBASE="$(mktemp -d)"
T90_DIR=""

# Fixture paths follow the CLI supply (task/<id>/) — never hardcode the .gos/ root
gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }

t90_setup() {
  T90_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t90"
  mkdir -p "$T90_DIR" && cd "$T90_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/.lock\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t90_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T90_DIR"; }

# Bring the seeded wrapper state to the approve-archive point: DONE + spec
# materialized + the user's explicit `gos approve archive` recorded.
t90_ship_ready() {
  python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='DONE'
s['spec_path']='\"$(gos_spec)\"'
json.dump(s,open('.gos/state.json','w'),indent=2)"
  echo spec > "$(gos_spec)"
  node "$GOS" approve archive >/dev/null 2>&1
}

t90_setup
echo "--- T90: PROJECT.md gate (TODO markers + approve-archive pre-flight + THINK read_files) ---"

# --- .0: source contract — init seeds TODO guidance lines
TODON=$(grep -c 'TODO' "$GOS_ROOT/bin/lib/task/init.cjs" || true)
if [ "${TODON:-0}" -ge 1 ]; then
  echo "  ✓ T90.0a init.cjs carries TODO guidance (count=$TODON)"; PASS=$((PASS+1))
else
  echo "  ✗ T90.0a init.cjs carries no TODO guidance"; FAIL=$((FAIL+1))
fi

# --- .1: seeded skeleton is TODO-marked, brownfield-ignored, NOT pushed to THINK
OUT=$(node "$GOS" init 4 "projmd gate" --project 2>&1)
assert_file "T90.1a PROJECT.md seeded" ".gos/project/PROJECT.md"
if grep -qF 'TODO:' .gos/project/PROJECT.md 2>/dev/null; then
  echo "  ✓ T90.1b seeded skeleton carries TODO: guidance lines"; PASS=$((PASS+1))
else
  echo "  ✗ T90.1b seeded skeleton lacks TODO: guidance lines"; FAIL=$((FAIL+1))
fi
if printf '%s' "$OUT" | grep -q 'handwritten content detected in: PROJECT.md'; then
  echo "  ✗ T90.1c TODO-only PROJECT.md must not read as brownfield"; FAIL=$((FAIL+1))
else
  echo "  ✓ T90.1c TODO-only skeleton is not brownfield"; PASS=$((PASS+1))
fi
CTX=$(node "$GOS" context think 2>&1)
if printf '%s' "$CTX" | grep -qF '.gos/project/PROJECT.md'; then
  echo "  ✗ T90.1d skeleton PROJECT.md must NOT join THINK read_files"; FAIL=$((FAIL+1))
else
  echo "  ✓ T90.1d skeleton PROJECT.md withheld from THINK read_files"; PASS=$((PASS+1))
fi

# --- .2: TODO-only skeleton refused at approve-archive pre-flight, zero mutation
t90_ship_ready
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "T90.2a TODO-only skeleton refuses archive" 1 "$RC"
assert_contains "T90.2b gate banner names PROJECT.md gate" "ARCHIVE BLOCKED (PROJECT.md gate)" "$OUT"
assert_contains "T90.2c fix hint tells filling" "fill every" "$OUT"
if [ -e .gos/archive ]; then
  echo "  ✗ T90.2d refusal must precede every mutation (no .gos/archive/)"; FAIL=$((FAIL+1))
else
  echo "  ✓ T90.2d validate-then-mutate: no dest materialized"; PASS=$((PASS+1))
fi

# --- .3: three junk non-TODO lines (-/x/n/a) still refuse
cat > .gos/project/PROJECT.md <<'EOF'
# Project

## What This Is
-
x
n/a

## Core Value
TODO: placeholder guidance

## Requirements Evolution
TODO: placeholder guidance
EOF
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "T90.3a junk lines refuse archive" 1 "$RC"
assert_contains "T90.3b gate banner names PROJECT.md gate" "ARCHIVE BLOCKED (PROJECT.md gate)" "$OUT"

# --- .4: section-less file refuses (no vacuous pass)
cat > .gos/project/PROJECT.md <<'EOF'
# Project

This file deliberately carries no section header at all — only prose that
is long enough to look like real content, so only the at-least-one-section
rule can reject it here.
EOF
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "T90.4a section-less file refuses archive" 1 "$RC"
assert_contains "T90.4b gate banner names PROJECT.md gate" "ARCHIVE BLOCKED (PROJECT.md gate)" "$OUT"

# --- .5: filled PROJECT.md joins THINK read_files and the archive passes
cat > .gos/project/PROJECT.md <<'EOF'
# Project

## What This Is

GOS is a self-hosted process layer for AI-assisted development: it turns
intent into archived, evidence-backed phases.

## Core Value

Trust comes from mechanized gates and replayable evidence, never from
discipline or documentation promises alone.

## Requirements Evolution

Requirements are recorded per phase, claimed by tasks, and closed with
verifiable truths that cite their issue numbers.
EOF
CTX=$(node "$GOS" context think 2>&1)
if printf '%s' "$CTX" | grep -qF '.gos/project/PROJECT.md'; then
  echo "  ✓ T90.5a filled PROJECT.md joins THINK read_files"; PASS=$((PASS+1))
else
  echo "  ✗ T90.5a filled PROJECT.md missing from THINK read_files"; FAIL=$((FAIL+1))
fi
node "$GOS" changelog add --summary "fill the project vision gate fixture" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "T90.5b filled PROJECT.md archive passes" 0 "$RC"
AD=$(ls -d .gos/archive/*/ 2>/dev/null | head -1)
assert_file "T90.5c archive dest materialized" "$AD"
assert_file "T90.5d PROJECT.md survives the archive (render never owns it)" ".gos/project/PROJECT.md"

t90_teardown
echo "--- T90 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
