#!/usr/bin/env bash
# gos-map:fn bin/lib/task/commit.cjs#fn:cmdCommit bin/lib/nav/status.cjs#fn:cmdStatus
# gos-map:cmd commit,status
# T12: wiring completeness + SHIP ritual gate (legacy instruction strings zeroed / help family / context routing /
#      contract round-trip / CHANGELOG.md same-day duty gate: fail-closed + skippable + version-discipline warn)
# Env: GOS (CLI path), TESTBASE (repo root for sandbox), + assert helpers sourced by runner
T12_DIR=""

# [Phase W T5] fixture paths follow the CLI supply (task/<id>/) — never hardcode .gos/ root
gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }
gos_plan() { node "$GOS" context plan 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["plan"])' 2>/dev/null; }

t12_setup() {
  T12_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t12"
  mkdir -p "$T12_DIR" && cd "$T12_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/.lock\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t12_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T12_DIR"; }

t12_setup
echo "--- T12: wiring completeness + SHIP gate ---"
unset GOS_SKIP_SHIP_CHECK   # this section exercises the gate for real

# --- T12.1: old hand-edit instruction eradicated (source-level wiring audit) ---
OLD=$(grep -c "record D-NN in state.json" "$GOS_ROOT/bin/gos.cjs" || true)
assert_eq "no 'record D-NN in state.json' left in gos.cjs" "0" "$OLD"

# --- T12.2: help lists every command family (decision/requirement/phase/anchor/_contract) ---
HELP=$(node "$GOS" help 2>&1)
MISSING=""
for kw in decision requirement phase anchor _contract; do
  echo "$HELP" | grep -q "$kw" || MISSING="$MISSING$kw "
done
assert_eq "help covers decision/requirement/phase/anchor/_contract" "" "$MISSING"

# --- T12.3: context think routes decisions via the command (not hand-editing) ---
node "$GOS" init 3 "wiring" >/dev/null 2>&1
CTX=$(node "$GOS" context think 2>&1)
assert_contains "context think mentions gos decision add" "gos decision add" "$CTX"

# --- T12.4: spec template teaches the command ---
assert_contains "spec-template records via gos decision add" "gos decision add" "$(cat "$GOS_ROOT/templates/spec-template.md")"

# --- T12.5: contract round-trip — frozen table value + live phase add emission match ---
PA=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['command_contracts']['phaseAdded'])")
assert_eq "table phaseAdded frozen value" "✓ Phase added: " "$PA"
t12_teardown; t12_setup
node "$GOS" init 4 "plat" --project >/dev/null 2>&1
set +e; OUT=$(node "$GOS" phase add "P1: core" --goal "g" 2>&1); RC=$?; set -e
assert_exit "phase add exits 0" 0 "$RC"
assert_contains "live phase add emits table prefix" "${PA}P1: core" "$OUT"

# --- T12.6: SHIP gate fail-closed — archive preconditions met but no CHANGELOG.md today → blocked ---
t12_teardown; t12_setup
node "$GOS" init 3 "ship gate" >/dev/null 2>&1
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='DONE'; s['approvals']={'ARCHIVE':'ok'}; s['spec_path']='\"$(gos_spec)\"'
json.dump(s,open('.gos/state.json','w'),indent=2)"
echo spec > "$(gos_spec)"
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "archive blocked without CHANGELOG.md" 1 "$RC"
assert_contains "block message is SHIP BLOCKED" "SHIP BLOCKED" "$OUT"
assert_contains "block message tells what to do" "gos changelog add" "$OUT"
printf '# Changelog\n\n## [Unreleased]\n\n- Test stale stamp (R-01) [%s]\n' "$(date -u -d yesterday +%F)" > CHANGELOG.md
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "archive blocked without today-stamped bullet" 1 "$RC"

# --- T12.7: today's CHANGELOG.md [Unreleased] bullet → archive passes + version-discipline warn on success path ---
printf '# Changelog\n\n## [Unreleased]\n\n- Test wiring ship gate (R-01) [%s]\n' "$(date -u +%F)" > CHANGELOG.md
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "archive passes with today-stamped CHANGELOG bullet" 0 "$RC"
assert_contains "version discipline warn on success path" "version discipline" "$OUT"

# --- T12.8: GOS_SKIP_SHIP_CHECK=1 bypasses the ritual gate (tests/non-release archives) ---
t12_teardown; t12_setup
node "$GOS" init 3 "skip check" >/dev/null 2>&1
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['current_stage']='DONE'; s['approvals']={'ARCHIVE':'ok'}; s['spec_path']='"$(gos_spec)"'
json.dump(s,open('.gos/state.json','w'),indent=2)"
echo spec > "$(gos_spec)"
set +e; OUT=$(GOS_SKIP_SHIP_CHECK=1 node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "skip-env archive proceeds without CHANGELOG.md" 0 "$RC"

t12_teardown; t12_setup

# --- T12.9 (Phase B T8): help wires semantic gate + truth/lessons families ---
HELP=$(node "$GOS" help 2>&1)
CNT=$(printf '%s\n' "$HELP" | grep -ci "truth\|lessons\|semantic" || true)
if [ "${CNT:-0}" -ge 3 ]; then
  echo "  ✓ help mentions truth/lessons/semantic ($CNT lines)"; PASS=$((PASS+1))
else
  echo "  ✗ help wiring thin: only $CNT truth/lessons/semantic lines"; FAIL=$((FAIL+1))
fi
assert_contains "help gate line lists semantic" "semantic" "$HELP"

# --- T12.10 (T8): four SKILL.md files carry the new keywords ---
for pair in "gos-verify:semantic" "gos-verify:truth" "gos-think:lessons" "gos-build:gos commit" "gos-ship:truth-receipts"; do
  SK="${pair%%:*}"; KW="${pair#*:}"
  if grep -q "$KW" "$GOS_ROOT/skills/$SK/SKILL.md" 2>/dev/null; then
    echo "  ✓ skills/$SK mentions $KW"; PASS=$((PASS+1))
  else
    echo "  ✗ skills/$SK missing keyword '$KW'"; FAIL=$((FAIL+1))
  fi
done

# --- T12.11 (T8): frozen single-point-commit phrase in gos-build SKILL.md + CONTRACTS ---
if grep -q "executors never run gos commit" "$GOS_ROOT/skills/gos-build/SKILL.md"; then
  echo "  ✓ gos-build SKILL carries the single-point-commit rule"; PASS=$((PASS+1))
else
  echo "  ✗ single-point-commit phrase missing in gos-build SKILL.md"; FAIL=$((FAIL+1))
fi
DC=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['decorative'].get('waveSinglePointCommit',''))")
assert_contains "CONTRACTS.decorative freezes the rule" "during parallel waves executors never run gos commit — the main session commits once per wave after aggregation" "$DC"

# --- T12.12 (T8): static grep — dispatch lock classification complete [R4-F4] ---
WC=$(grep -o "WRITE_CMDS = new Set(\[[^]]*\]" "$GOS_ROOT/bin/lib/nav/registry-consts.cjs" || true)
for cmd in truth lessons; do
  if echo "$WC" | grep -q "'$cmd'"; then
    echo "  ✓ $cmd registered in WRITE_CMDS"; PASS=$((PASS+1))
  else
    echo "  ✗ $cmd missing from WRITE_CMDS"; FAIL=$((FAIL+1))
  fi
done
for pat in "case 'truth':" "case 'lessons':" "lessons list = read-class"; do
  if grep -qF "$pat" "$GOS_ROOT/bin/gos.cjs"; then
    echo "  ✓ dispatch/lock-class pattern present: $pat"; PASS=$((PASS+1))
  else
    echo "  ✗ dispatch/lock-class pattern missing: $pat"; FAIL=$((FAIL+1))
  fi
done

t12_teardown
