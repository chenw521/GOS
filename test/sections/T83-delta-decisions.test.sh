#!/usr/bin/env bash
# gos-map:fn bin/lib/task/archive.cjs#fn:specDecisionTitles
# gos-map:cmd archive
# delta.md decision rendering — decision-less states (Lv1/2) extract
# decision titles from the archived spec.md instead of printing the false
# vacancy "Decisions: none"; states that DO carry decisions render unchanged.
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner
T83_DIR=""

t83_setup() {
  T83_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t83"
  mkdir -p "$T83_DIR" && cd "$T83_DIR" || exit 1
  git init -q . || exit 1
  git config user.email t@t.local && git config user.name t || exit 1
  echo x > f.txt && git add f.txt && git commit -q -m "chore: seed" || exit 1
}
t83_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T83_DIR"; }

t83_setup
trap 't83_teardown' EXIT

PASS=0
FAIL=0

echo "--- T83: delta.md renders spec decisions for decision-less states ---"

# Harness ( pattern): Lv1 task through approve-archive, custom spec content
t83_run() {
  node "$GOS" init --force 1 "t83 delta $1" >/dev/null 2>&1
  node "$GOS" commit intent >/dev/null 2>&1
  # task id = task_head sha prefix (init does not materialize .gos/task/ —
  # the spec writer creates it; context-think JSON is the CLI-native source
  # but the id is deterministic from state)
  TID_DIR="$(node -e 'try{const s=require(process.argv[1]+"/.gos/state.json");process.stdout.write(String(s.task_head||"").slice(0,8))}catch{}' "$PWD")"
  [ -n "$TID_DIR" ] || TID_DIR="$(ls .gos/task 2>/dev/null | head -1)"
  SPEC=".gos/task/$TID_DIR/spec.md"
  mkdir -p "$(dirname "$SPEC")"
  printf '%s' "$2" > "$SPEC"
  node "$GOS" approve think >/dev/null 2>&1
  node "$GOS" commit think >/dev/null 2>&1
  node "$GOS" stage build >/dev/null 2>&1
  node "$GOS" approve archive >/dev/null 2>&1
  GOS_SKIP_SHIP_CHECK=1 node "$GOS" archive >/dev/null 2>&1
  AD="$(ls -dt .gos/archive/2*/ | head -1)"
  cat "$AD/task/$TID_DIR/delta.md" 2>/dev/null || cat "$AD/delta.md" 2>/dev/null
}

SPEC_WITH='# Spec — fixture
## Decisions (Lv1/2 — prose)
Decision-alpha (guard wiring): the guard runs in the gate job and gate all.
Decision-beta (doc placement): the doc lives beside the workflow it describes.
## Observable Truths
1. something observable.
'

SPEC_WITHOUT='# Spec — fixture
## Observable Truths
1. something observable.
'

# --- .1 spec decisions present -> delta lists titles, never "none"
D1="$(t83_run with-decisions "$SPEC_WITH")"
DLINE1="$(printf '%s\n' "$D1" | grep '^- Decisions:')"
if printf '%s' "$DLINE1" | grep -q 'Decision-alpha (guard wiring)' && printf '%s' "$DLINE1" | grep -q 'Decision-beta (doc placement)'; then
  echo "  ✓ T83.1a delta lists both spec decision titles"; PASS=$((PASS+1))
else
  echo "  ✗ T83.1a delta Decisions line: $DLINE1"; FAIL=$((FAIL+1))
fi
if printf '%s' "$DLINE1" | grep -q 'from spec.md'; then
  echo "  ✓ T83.1b provenance marker (from spec.md)"; PASS=$((PASS+1))
else
  echo "  ✗ T83.1b provenance marker missing: $DLINE1"; FAIL=$((FAIL+1))
fi
if ! printf '%s' "$DLINE1" | grep -q 'Decisions: none'; then
  echo "  ✓ T83.1c no false vacancy"; PASS=$((PASS+1))
else
  echo "  ✗ T83.1c still prints none"; FAIL=$((FAIL+1))
fi

# --- .2 spec WITHOUT decisions section -> graceful vacancy with pointer
D2="$(t83_run without-decisions "$SPEC_WITHOUT")"
DLINE2="$(printf '%s\n' "$D2" | grep '^- Decisions:')"
if printf '%s' "$DLINE2" | grep -q 'none recorded' && printf '%s' "$DLINE2" | grep -q 'spec.md'; then
  echo "  ✓ T83.2 graceful vacancy names spec.md"; PASS=$((PASS+1))
else
  echo "  ✗ T83.2 Decisions line: $DLINE2"; FAIL=$((FAIL+1))
fi

# --- .3 unit: extractor is pure and closed over the section
cat > "$T83_DIR/unit-spec.md" <<'SPECEOF'
# Spec — fixture
## Decisions (Lv1/2 — prose)
Decision-alpha (guard wiring): the guard runs in the gate job and gate all.
Decision-beta (doc placement): the doc lives beside the workflow it describes.
## Observable Truths
1. something observable.
SPECEOF
U="$(node -e '
const m = require(process.argv[1] + "/bin/lib/task/archive.cjs");
const t = m.specDecisionTitles(process.argv[2]);
console.log(Array.isArray(t) && t.length === 2 ? "unit-ok " + t.length : "unit-bad " + JSON.stringify(t));
' "$GOS_ROOT" "$T83_DIR/unit-spec.md" 2>&1)"
if printf '%s' "$U" | grep -q 'unit-ok 2'; then
  echo "  ✓ T83.3 extractor returns both titles"; PASS=$((PASS+1))
else
  echo "  ✗ T83.3 extractor: $U"; FAIL=$((FAIL+1))
fi

echo "--- T83 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
