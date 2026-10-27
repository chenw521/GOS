#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/gate.cjs#fn:cmdGate
# gos-map:cmd gate,changelog,commit
# gate wiring — audit mode for stateless trees, changelog lint joins
# gate all (same-source subprocess), CHANGELOG.md allowlist default entry
# (runtime patterns + contract copy), and gos commit staging CHANGELOG.md.
T61_DIR=""

# t61_bare must live OUTSIDE any GOS-managed tree: a stateless exec command
# under a managed ancestor is correctly refused by the cwd guard, while the
# audit scenario models a standalone CI checkout. Default mktemp base is used
# with strict per-scenario teardown below.
t61_bare() {
  T61_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gos-t61-audit-XXXXXX")"
  cd "$T61_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t61-seed
}

t61_new() {
  t61_bare
  GOS_HEADLESS=1 node "$GOS" init 3 "t61 gate wiring" >/dev/null 2>&1
}

t61_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T61_DIR"; }
trap 't61_teardown' EXIT

PASS=0; FAIL=0
echo "--- T61: gate wiring (audit / allowlist / changelog lint) ---"

TODAY="$(node -e "console.log(require('$GOS_ROOT/bin/lib/ops/changelog-core.cjs').utcToday())" 2>/dev/null || true)"

# ===== A: stateless tree + gate all --audit -> structural layer only, exit 0 =====
t61_bare
node "$GOS" paths --markdown >/dev/null 2>&1   # seed .gos/README.md with zero state.json
set +e; OUT=$(node "$GOS" gate all --audit 2>&1); RC=$?; set -e
assert_exit "A1 stateless --audit exit 0" 0 "$RC"
assert_contains "A2 audit banner announces structural-only scope" "audit" "$OUT"
assert_contains "A3 audit runs the readme regen guard" "README regen guard" "$OUT"
assert_contains "A4 audit runs changelog lint" "changelog lint" "$OUT"
if [ ! -f .gos/state.json ]; then echo "  ✓ A5 audit never creates a state file"; PASS=$((PASS+1)); else echo "  ✗ A5 audit created state.json"; FAIL=$((FAIL+1)); fi

# ===== A2: stateless WITHOUT --audit still dies (unchanged contract) =====
set +e; OUT=$(node "$GOS" gate all 2>&1); RC=$?; set -e
assert_exit "A6 stateless plain gate all exit 1" 1 "$RC"
assert_contains "A7 die message points at gos init" "gos init" "$OUT"

# ===== A3: audit keeps structural enforcement — README drift fails =====
echo "hand edit drift" >> .gos/README.md
set +e; OUT=$(node "$GOS" gate all --audit 2>&1); RC=$?; set -e
assert_exit "A8 readme drift under --audit exit 1" 1 "$RC"
assert_contains "A9 drift message surfaced" "README drift" "$OUT"
node "$GOS" paths --markdown >/dev/null 2>&1   # restore the regen'd README

# ===== A4: audit keeps structural enforcement — changelog lint violation fails =====
printf '# Alpha log\n\n# Beta log\n\n## [Unreleased]\n\n- Add today bullet (D-1) [%s]\n' "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" gate all --audit 2>&1); RC=$?; set -e
assert_exit "A10 lint violation under --audit exit 1" 1 "$RC"
assert_contains "A11 duplicate-title violation surfaced" "title" "$OUT"

# ===== A5: stateless audit with a clean CHANGELOG.md -> lint visible and green =====
printf '# Log\n\n## [Unreleased]\n\n- Add today bullet (D-1) [%s]\n' "$TODAY" > CHANGELOG.md
set +e; OUT=$(node "$GOS" gate all --audit 2>&1); RC=$?; set -e
assert_exit "A12 clean changelog under --audit exit 0" 0 "$RC"
assert_contains "A13 lint clean line present" "changelog lint" "$OUT"
t61_teardown

# ===== B: with state — changelog add then gate all stays green (lint joins) =====
t61_new
node "$GOS" changelog add --summary "t61 wiring entry for gate truth" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" gate all 2>&1); RC=$?; set -e
assert_exit "B1 changelog add then gate all exit 0" 0 "$RC"
assert_contains "B2 gate all runs changelog lint" "changelog lint" "$OUT"
assert_contains "B3 no task-level checks were skipped" "coverage" "$OUT"

# ===== B2: subcommand scope — gate semantic does NOT drag changelog lint in =====
set +e; OUT=$(node "$GOS" gate semantic 2>&1); RC=$?; set -e
assert_exit "B4 gate semantic still exit 0" 0 "$RC"
if printf '%s' "$OUT" | grep -q "changelog lint"; then echo "  ✗ B5 lint leaked into gate semantic"; FAIL=$((FAIL+1)); else echo "  ✓ B5 lint scoped to gate all"; PASS=$((PASS+1)); fi

# ===== C: gos commit stages CHANGELOG.md alongside the task artifacts =====
node "$GOS" commit intent --subject "t61 intent with changelog on board" >/dev/null 2>&1
STAT="$(git show --stat --name-only --format= HEAD 2>/dev/null || true)"
assert_contains "C1 CHANGELOG.md present in the stage commit" "CHANGELOG.md" "$STAT"
assert_contains "C2 .gos artifacts present in the same commit" ".gos/" "$STAT"
t61_teardown

# ===== D: allowlist dual-source — runtime default + contract copy =====
node -e '
const g = require(process.argv[1] + "/bin/lib/ops/gate.cjs");
const a = g.loadSemanticAllowlist(null);
process.exit(a.patterns.includes("CHANGELOG.md") && g.semanticAllowlisted("CHANGELOG.md", a) ? 0 : 1);
' "$GOS_ROOT"; D_RC=$?
assert_exit "D1 runtime default allowlist matches CHANGELOG.md" 0 "$D_RC"
ALLOW="$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print('|'.join(json.load(sys.stdin)['semantic_checks']['allowlist']))" 2>/dev/null || true)"
assert_contains "D2 contract copy includes CHANGELOG.md" "CHANGELOG.md" "$ALLOW"
node -e '
const g = require(process.argv[1] + "/bin/lib/ops/gate.cjs");
const a = g.loadSemanticAllowlist(null);
process.exit(g.semanticAllowlisted("docs/other.md", a) ? 1 : 0);
' "$GOS_ROOT"; D_RC2=$?
assert_exit "D3 allowlist stays narrow (random doc not matched)" 0 "$D_RC2"

# ===== E: same-source proof — gate consumes the changelog lint CLI, not a copy =====
if grep -qF "'changelog', 'lint'" "$GOS_ROOT/bin/lib/ops/gate.cjs"; then echo "  ✓ E1 gate invokes the changelog lint command (single implementation)"; PASS=$((PASS+1)); else echo "  ✗ E1 subprocess wiring to changelog lint missing"; FAIL=$((FAIL+1)); fi
if grep -qF "'CHANGELOG.md'" "$GOS_ROOT/bin/lib/ops/gate.cjs" && grep -qF "'CHANGELOG.md'" "$GOS_ROOT/bin/lib/core/state.cjs"; then echo "  ✓ E2 allowlist entry present in both sources"; PASS=$((PASS+1)); else echo "  ✗ E2 allowlist dual-source sync broken"; FAIL=$((FAIL+1)); fi

# ===== F: --audit WITH a state behaves exactly like plain gate all =====
t61_new
set +e; OUT1=$(node "$GOS" gate all --audit 2>&1); RC1=$?; set -e
set +e; OUT2=$(node "$GOS" gate all 2>&1); RC2=$?; set -e
assert_exit "F1 stateful --audit exit 0" 0 "$RC1"
assert_eq "F2 stateful --audit exit matches plain gate all" "$RC2" "$RC1"
if printf '%s' "$OUT1" | grep -q "task-level checks skipped"; then echo "  ✗ F3 stateful audit wrongly skipped task checks"; FAIL=$((FAIL+1)); else echo "  ✓ F3 stateful audit kept task-level checks"; PASS=$((PASS+1)); fi
t61_teardown

echo "--- T61 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
