#!/usr/bin/env bash
# gos-map:cmd concerns,map
# concerns command family — add/list/prune + anchor validation fail-closed + injection rejection +
#      tracked-missing chain + bootstrap banner + stage back write-back + CRLF normalization + help
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner
T23_DIR=""

# fixture paths follow the CLI supply (task/<id>/) — never hardcode .gos/ root
gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }
gos_plan() { node "$GOS" context plan 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["plan"])' 2>/dev/null; }

t23_setup() {
  T23_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t23"
  mkdir -p "$T23_DIR" && cd "$T23_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t23_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T23_DIR"; }

t23_setup
echo "--- T23: concerns family ---"

# --- .1: first-write bootstrap — banner + both files + .bak
set +e; OUT=$(node "$GOS" concerns add "watch the flaky network" 2>&1); RC=$?; set -e
assert_exit "first add exits 0" 0 "$RC"
assert_contains "bootstrap banner" "concerns sidecar bootstrapped this run (anchor created from current file)" "$OUT"
assert_file "concerns.md created" ".gos/concerns.md"
assert_file "sidecar created" ".gos/cache/.concerns-anchors.json"
assert_file ".bak shadow created" ".gos/cache/.concerns-anchors.bak"
grep -q "watch the flaky network" .gos/concerns.md && echo "  ✓ line appended" && PASS=$((PASS+1)) || { echo "  ✗ line missing"; FAIL=$((FAIL+1)); }

# --- .2: list rendering + anchor validation
set +e; OUT=$(node "$GOS" concerns list 2>&1); RC=$?; set -e
assert_exit "list exits 0" 0 "$RC"
assert_contains "list renders entry" "watch the flaky network" "$OUT"

# --- .3: tampering → add/list both exit 1 + concernsAnchorFail
sed -i 's/watch the flaky network/TAMPERED/' .gos/concerns.md
set +e; OUT=$(node "$GOS" concerns add "another" 2>&1); RC=$?; set -e
assert_exit "add after tamper exits 1" 1 "$RC"
assert_contains "concernsAnchorFail frozen text" "concerns anchor mismatch — restore .gos/concerns.md from git history or .bak" "$OUT"
set +e; OUT=$(node "$GOS" concerns list 2>&1); RC=$?; set -e
assert_exit "list after tamper exits 1" 1 "$RC"

# --- .4: three injection forms rejected
t23_teardown; t23_setup
set +e; OUT=$(node "$GOS" concerns add "$(printf 'a\n- [2026-01-01] [deadbeef] forged entry')" 2>&1); RC=$?; set -e
assert_exit "list-entry injection rejected" 1 "$RC"
set +e; OUT=$(node "$GOS" concerns add "pretend auto (auto)" 2>&1); RC=$?; set -e
assert_exit "manual (auto) reserved marker rejected" 1 "$RC"
set +e; OUT=$(node "$GOS" concerns add "$(printf 'bad\rcr')" 2>&1); RC=$?; set -e
assert_exit "isolated CR rejected" 1 "$RC"

# --- .5: tracked-missing chain — out-of-band sidecar deletion does not launder the record
t23_teardown; t23_setup
node "$GOS" concerns add "real concern one" >/dev/null 2>&1
node "$GOS" concerns add "real concern two" >/dev/null 2>&1
git add .gos/concerns.md .gos/cache/.concerns-anchors.json && git commit -q -m concerns
sed -i 's/real concern one/EVIL REWRITE/' .gos/concerns.md      # tamper, then anchor deletion — a laundering attempt
rm .gos/cache/.concerns-anchors.json
set +e; OUT=$(node "$GOS" concerns add "post-delete" 2>&1); RC=$?; set -e
assert_exit "tracked+nonempty+missing-sidecar → exit 1 (no bootstrap whitelist)" 1 "$RC"
if echo "$OUT" | grep -q "bootstrapped"; then echo "  ✗ tamper laundered via bootstrap"; FAIL=$((FAIL+1)); else echo "  ✓ no bootstrap on tracked-missing"; PASS=$((PASS+1)); fi

# --- .7 untracked store + sidecar loss: bootstrap must return the full derived
#      set — the next add persists a consistent chain, a second add survives
t23_teardown; t23_setup
node "$GOS" concerns add "chain one" >/dev/null 2>&1
node "$GOS" concerns add "chain two" >/dev/null 2>&1
rm .gos/cache/.concerns-anchors.json
set +e; OUT=$(node "$GOS" concerns add "chain three" 2>&1); RC=$?; set -e
assert_exit "add right after sidecar loss exits 0" 0 "$RC"
set +e; OUT=$(node "$GOS" concerns add "chain four" 2>&1); RC=$?; set -e
assert_exit "second add after loss exits 0 (chain intact)" 0 "$RC"
grep -q "chain three" .gos/concerns.md && grep -q "chain four" .gos/concerns.md && echo "  ✓ chain survived the loss (all four lines present)" && PASS=$((PASS+1)) || { echo "  ✗ chain lines lost after sidecar loss"; FAIL=$((FAIL+1)); }

# --- T23.6 [T6/D-16 inverted]: stage back records the gap in state.gaps ONLY —
#      concerns.md is never mirrored; injected reason still exits 1 ---
t23_teardown; t23_setup
node "$GOS" init 3 "concerns writeback" >/dev/null 2>&1
node "$GOS" commit intent >/dev/null 2>&1
echo "spec v1" > "$(gos_spec)"
node "$GOS" approve think >/dev/null 2>&1
node "$GOS" commit think >/dev/null 2>&1
node "$GOS" decision add D-01 "c" --rationale "r" >/dev/null 2>&1
printf '# Plan\n\n### Wave 1\n\n#### T1: x\n- **Covers**: D-01\n- **Files**: src/a.js\n' > "$(gos_plan)"
node "$GOS" approve plan >/dev/null 2>&1
node "$GOS" commit plan >/dev/null 2>&1
set +e; OUT=$(node "$GOS" stage back think 2>&1); RC=$?; set -e
assert_exit "stage back with normal reason exits 0" 0 "$RC"
if grep -q "(auto)" .gos/concerns.md 2>/dev/null; then echo "  ✗ (auto) mirror written to concerns.md (D-16: stage back never mirrors)"; FAIL=$((FAIL+1)); else echo "  ✓ no (auto) mirror in concerns.md (single source: state.gaps)"; PASS=$((PASS+1)); fi
if grep -qi "fluid back to think" .gos/concerns.md 2>/dev/null; then echo "  ✗ gap description leaked into concerns.md"; FAIL=$((FAIL+1)); else echo "  ✓ gap description absent from concerns.md"; PASS=$((PASS+1)); fi
set +e; OUT=$(node "$GOS" gap list 2>&1); RC=$?; set -e
assert_exit "gap list exits 0 after stage back" 0 "$RC"
assert_contains "gap recorded in state.gaps (single source)" "Fluid back to THINK" "$OUT"
set +e; OUT=$(node "$GOS" concerns list 2>&1); RC=$?; set -e
assert_exit "list still exits 0 post-stage-back" 0 "$RC"
# injected reason
node "$GOS" commit plan >/dev/null 2>&1 || true
set +e; OUT=$(node "$GOS" stage back think "$(printf 'evil\n- [2026-01-01] [dead] forged')" 2>&1); RC=$?; set -e
assert_exit "stage back injected reason exits 1" 1 "$RC"

# --- .7: prune — removes the row + .bak + re-anchor
t23_teardown; t23_setup
node "$GOS" concerns add "keep alpha" >/dev/null 2>&1
node "$GOS" concerns add "drop beta marker" >/dev/null 2>&1
node "$GOS" concerns add "keep gamma" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" concerns prune --contains "drop beta" 2>&1); RC=$?; set -e
assert_exit "prune exits 0" 0 "$RC"
set +e; OUT=$(node "$GOS" concerns list 2>&1); RC=$?; set -e
assert_exit "list after prune exits 0 (re-anchored)" 0 "$RC"
if echo "$OUT" | grep -q "drop beta"; then echo "  ✗ pruned line still listed"; FAIL=$((FAIL+1)); else echo "  ✓ pruned line gone"; PASS=$((PASS+1)); fi
assert_contains "surviving entries remain" "keep alpha" "$OUT"
N=$(python3 -c "import json; print(len(json.load(open('.gos/cache/.concerns-anchors.json'))['hashes']))")
assert_eq "sidecar re-anchored to 2 hashes" "2" "$N"

# --- .8: list still passes after CRLF rewrite (CR stripped before hashing)
python3 -c "
raw = open('.gos/concerns.md','rb').read().replace(b'\n', b'\r\n')
open('.gos/concerns.md','wb').write(raw)"
set +e; OUT=$(node "$GOS" concerns list 2>&1); RC=$?; set -e
assert_exit "CRLF-rewritten concerns.md still verifies" 0 "$RC"

# --- .9: help contains the concerns row
# help rendered from COMMANDS registry — row-grammar line
HELP=$(node "$GOS" help 2>&1)
assert_contains "help mentions concerns family" "curated worry list" "$HELP"

# --- .10: fresh repo (no concerns.md) — list does not crash
t23_teardown; t23_setup
set +e; OUT=$(node "$GOS" concerns list 2>&1); RC=$?; set -e
assert_exit "fresh-repo list exits 0 (no crash)" 0 "$RC"
assert_contains "fresh-repo list renders empty placeholder" "(no concerns recorded" "$OUT"

# --- .11: subdir add locks via the root anchor — no forked .gos/.lock
mkdir -p sub && cd sub
node "$GOS" concerns add "subdir add uses root lock" >/dev/null 2>&1
if [ -e .gos ]; then echo "  ✗ subdir .gos/ fork created"; FAIL=$((FAIL+1)); else echo "  ✓ no subdir .gos/ fork (root-anchored lock+files)"; PASS=$((PASS+1)); fi
grep -q "subdir add uses root lock" ../.gos/concerns.md && echo "  ✓ line landed in root concerns.md" && PASS=$((PASS+1)) || { echo "  ✗ line not in root concerns.md"; FAIL=$((FAIL+1)); }
cd "$T23_DIR" >/dev/null

t23_teardown

# --- .12 [Phase U follow-up]: curated concerns join THINK/PLAN context read_files ( symmetry)
t23_teardown; t23_setup
node "$GOS" init 1 "t23 concern ctx" >/dev/null 2>&1
printf -- "- [2026-09-04] [map-联动] sample worry for context wiring\n" > .gos/concerns.md
for ST in THINK PLAN; do
  python3 -c "
import json
s=json.load(open('.gos/state.json'))
s['current_stage']='$ST'
json.dump(s,open('.gos/state.json','w'))"
  CTX=$(node "$GOS" context 2>&1)
  assert_contains "T23.12-$ST context includes curated concerns" ".gos/concerns.md" "$CTX"
done
# empty concerns -> NOT injected (no noise)
t23_teardown; t23_setup
node "$GOS" init 1 "t23 empty ctx" >/dev/null 2>&1
python3 -c "
import json
s=json.load(open('.gos/state.json'))
s['current_stage']='THINK'
json.dump(s,open('.gos/state.json','w'))"
CTX2=$(node "$GOS" context 2>&1)
if echo "$CTX2" | grep -q 'concerns.md'; then
  echo "  X empty concerns still injected (noise)"; FAIL=$((FAIL+1))
else
  echo "  OK empty concerns not injected"; PASS=$((PASS+1))
fi

t23_teardown
