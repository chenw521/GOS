#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/gate.cjs#fn:cmdGate bin/lib/ops/gate.cjs#fn:cmdGateTrust bin/lib/ops/setup.cjs#fn:seedGatesExamples
# gos-map:cmd gate,setup
# : custom-gate hash-trust layer + teaching templates + setup seeding
# Sandboxes live OUTSIDE any GOS-managed tree (mktemp base, precedent):
# stateless scenarios (pre-init trust seeding, stateless --audit) are correctly
# refused by the cwd guard when nested under a managed ancestor like TESTBASE.
T67_DIR=""

t67_setup() {
  [ -n "$T67_DIR" ] && rm -rf "$T67_DIR"   # sweep the previous scenario dir — no /tmp leaks
  T67_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gos-t67-trust-XXXXXX")"
  cd "$T67_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t67-seed
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t67_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T67_DIR"; }
trap 't67_teardown' EXIT

t67_trust_keys() {
  python3 -c "import json;print('|'.join(sorted(json.load(open('.gos/cache/trust.json'))['trusted_scripts'].keys())))" 2>/dev/null
}

t67_trust_sha_matches() {
  python3 - "$1" <<'PYEOF'
import hashlib, json, sys
name = sys.argv[1]
store = json.load(open('.gos/cache/trust.json'))
actual = hashlib.sha256(open('.gos/gates/' + name, 'rb').read()).hexdigest()
print('OK' if store.get('trusted_scripts', {}).get(name) == actual else 'MISMATCH')
PYEOF
}

t67_setup
PASS=0; FAIL=0
echo "--- T67: custom-gate hash trust + teaching templates + setup seeding ---"
set -e
TPL="$GOS_ROOT/templates/gates"

# ===== A: templates are real, not placeholder-empty =====
if grep -q 'npm run lint' "$TPL/gates.json" && grep -q '"protect"' "$TPL/gates.json" && grep -q '"forbid"' "$TPL/gates.json"; then
  echo "  ✓ A1 gates.json template carries real values (protect/lint/forbid)"; PASS=$((PASS+1))
else
  echo "  ✗ A1 gates.json template is placeholder-empty"; FAIL=$((FAIL+1))
fi
if grep -q 'PRIVATE KEY' "$TPL/check.sh" && grep -q 'npm test' "$TPL/check.sh"; then
  echo "  ✓ A2 check.sh template has a real private-key check + commented test hook"; PASS=$((PASS+1))
else
  echo "  ✗ A2 check.sh template lacks real check logic"; FAIL=$((FAIL+1))
fi
set +e; bash "$TPL/check.sh" >/dev/null 2>&1; RC=$?; set -e
assert_exit "A3 check.sh safe to run anywhere (no staged key -> 0)" 0 "$RC"

# ===== B(a): seeding registers trust; gate all runs both layers green =====
printf '{ "name": "t67-proj", "version": "0.0.0", "scripts": { "lint": "node -e 0" } }\n' > package.json
set +e
node -e '
const s = require(process.argv[1] + "/bin/lib/ops/setup.cjs");
const r = s.seedGatesExamples();
process.exit(r.check_sh && r.gates_json && r.trusted.includes("check.sh") ? 0 : 1);
' "$GOS_ROOT"; SEED_RC=$?
set -e
assert_exit "B1 seedGatesExamples copies both examples + registers trust" 0 "$SEED_RC"
assert_file "B2 seeded .gos/gates.json" ".gos/gates.json"
assert_file "B3 seeded .gos/gates/check.sh" ".gos/gates/check.sh"
assert_file "B4 trust store written" ".gos/cache/trust.json"
set +e; [ "$(t67_trust_sha_matches check.sh)" = "OK" ]; SHA_RC=$?; set -e
assert_exit "B5 seeded hash matches file content" 0 "$SHA_RC"
GOS_HEADLESS=1 node "$GOS" init 1 "t67 trust" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" gate all 2>&1); RC=$?; set -e
assert_exit "B6 seeded gates run green (script trusted at seed time)" 0 "$RC"
assert_contains "B7 custom script executed and marked trusted" "check.sh: passed (trusted)" "$OUT"
assert_contains "B8 declarative layer executed (protect rule live)" "protect" "$OUT"
assert_contains "B9 lint rule executed" "lint:" "$OUT"

# ===== B(i): seeded check.sh actually detects a staged private key =====
printf -- '-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA\n-----END RSA PRIVATE KEY-----\n' > leaked.pem
git add leaked.pem
set +e; OUT=$(node "$GOS" gate all 2>&1); RC=$?; set -e
assert_exit "i1 staged private key blocks the gate" 1 "$RC"
assert_contains "i2 failure names the custom script" "custom gate check.sh" "$OUT"
git restore --staged leaked.pem && rm -f leaked.pem
set +e; bash .gos/gates/check.sh >/dev/null 2>&1; RC=$?; set -e
assert_exit "i3 unstage restores a passing direct run" 0 "$RC"

# ===== C(b): hand-added untrusted script -> skip + FAIL naming it; trust -> runs =====
printf '#!/bin/bash\nexit 0\n' > .gos/gates/extra.sh
set +e; OUT=$(node "$GOS" gate all 2>&1); RC=$?; set -e
assert_exit "b1 untrusted script fails the gate" 1 "$RC"
assert_contains "b2 FAIL line names the script" "extra.sh" "$OUT"
assert_contains "b3 recovery hint points at gate trust" "gate trust extra.sh" "$OUT"
set +e; OUT=$(node "$GOS" gate trust extra.sh 2>&1); RC=$?; set -e
assert_exit "b4 gate trust exits 0" 0 "$RC"
assert_contains "b5 trust registration confirmed" "trusted custom gate: extra.sh" "$OUT"
set +e; OUT=$(node "$GOS" gate all 2>&1); RC=$?; set -e
assert_exit "b6 trusted script now runs green" 0 "$RC"
assert_contains "b7 both scripts executed" "extra.sh: passed (trusted)" "$OUT"

# ===== C(c): tamper a trusted script -> hash drift FAIL =====
printf '# tampered after trust\n' >> .gos/gates/extra.sh
set +e; OUT=$(node "$GOS" gate all 2>&1); RC=$?; set -e
assert_exit "c1 drifted script fails the gate" 1 "$RC"
assert_contains "c2 drift wording points at re-trust" "changed since trust" "$OUT"
node "$GOS" gate trust extra.sh >/dev/null 2>&1

# ===== C(d): tracked config.json carrying trust keys -> independent FAIL =====
printf '{"model_profile":"team","trusted_scripts":{"check.sh":"deadbeef"}}\n' > .gos/config.json
set +e; OUT=$(node "$GOS" gate all 2>&1); RC=$?; set -e
assert_exit "d1 polluted config.json fails the gate" 1 "$RC"
assert_contains "d2 migration guidance names the machine-local store" "cache/trust.json" "$OUT"
assert_contains "d3 pollution line is explicit about the keys" "trusted_scripts" "$OUT"
rm -f .gos/config.json

# ===== C(e): corrupt trust store -> trustStoreUnreadable + all untrusted =====
printf 'CORRUPT-NOT-JSON{{{' > .gos/cache/trust.json
set +e; OUT=$(node "$GOS" gate all 2>&1); RC=$?; set -e
assert_exit "e1 corrupt store fails the gate (never skip-and-green)" 1 "$RC"
assert_contains "e2 independent trustStoreUnreadable line" "trustStoreUnreadable" "$OUT"
assert_contains "e3 scripts treated as untrusted" "extra.sh" "$OUT"
rm -f .gos/cache/trust.json
node "$GOS" gate trust check.sh >/dev/null 2>&1
node "$GOS" gate trust extra.sh >/dev/null 2>&1

# ===== D(f): GOS_CI / --audit -> untrusted skipped with advisory, exit 0 =====
t67_setup
GOS_HEADLESS=1 node "$GOS" init 1 "t67 ci mode" >/dev/null 2>&1
mkdir -p .gos/gates && printf '#!/bin/bash\nexit 0\n' > .gos/gates/fresh.sh
set +e; OUT=$(GOS_CI=1 node "$GOS" gate all 2>&1); RC=$?; set -e
assert_exit "f1 GOS_CI=1 keeps exit 0" 0 "$RC"
assert_contains "f2 advisory names the skipped script" "fresh.sh" "$OUT"
assert_contains "f3 advisory says SKIPPED" "SKIPPED" "$OUT"
set +e; OUT=$(node "$GOS" gate all --audit 2>&1); RC=$?; set -e
assert_exit "f4 --audit also skips untrusted without failing" 0 "$RC"
assert_contains "f5 --audit advisory present" "SKIPPED" "$OUT"
# stateless fresh clone (CI checkout): no state, no trust store anywhere
t67_setup
mkdir -p .gos/gates && printf '#!/bin/bash\nexit 0\n' > .gos/gates/fresh.sh
node "$GOS" paths --markdown >/dev/null 2>&1
set +e; OUT=$(node "$GOS" gate all --audit 2>&1); RC=$?; set -e
assert_exit "f6 stateless fresh clone --audit stays green" 0 "$RC"

# ===== E(g): rename -> new name untrusted; gate trust GCs stale entries =====
t67_setup
GOS_HEADLESS=1 node "$GOS" init 1 "t67 rename gc" >/dev/null 2>&1
mkdir -p .gos/gates && cp "$TPL/check.sh" .gos/gates/check.sh
node "$GOS" gate trust check.sh >/dev/null 2>&1
assert_eq "g1 trust store holds the seeded name only" "check.sh" "$(t67_trust_keys)"
mv .gos/gates/check.sh .gos/gates/moved.sh
set +e; OUT=$(node "$GOS" gate all 2>&1); RC=$?; set -e
assert_exit "g2 renamed script is untrusted -> gate red" 1 "$RC"
assert_contains "g3 FAIL names the new name" "moved.sh" "$OUT"
set +e; OUT=$(node "$GOS" gate trust moved.sh 2>&1); RC=$?; set -e
assert_exit "g4 trust under new name exits 0" 0 "$RC"
assert_contains "g5 GC reports the stale entry" "check.sh" "$OUT"
assert_eq "g6 trust store has no orphan entries" "moved.sh" "$(t67_trust_keys)"
# dangling symlink -> FAIL line, not a crash
ln -s /nonexistent-t67-target .gos/gates/dangling.sh
set +e; OUT=$(node "$GOS" gate all 2>&1); RC=$?; set -e
assert_exit "g7 dangling symlink fails without crashing" 1 "$RC"
assert_contains "g8 unreadable-script wording" "dangling" "$OUT"
rm -f .gos/gates/dangling.sh
node "$GOS" gate trust moved.sh >/dev/null 2>&1

# ===== F(h): empty custom layer -> one advisory hint line =====
t67_setup
GOS_HEADLESS=1 node "$GOS" init 1 "t67 empty" >/dev/null 2>&1
set +e; OUT=$(node "$GOS" gate all 2>&1); RC=$?; set -e
assert_exit "h1 empty custom layer keeps gate green" 0 "$RC"
assert_contains "h2 empty-state hint appears" "no custom gates" "$OUT"
assert_contains "h3 hint points at seeding" "gos setup" "$OUT"

# ===== G: registry surface (help / paths / contracts) =====
set +e; HELP=$(node "$GOS" help gate 2>&1); RC=$?; set -e
assert_exit "G1 help gate exits 0" 0 "$RC"
assert_contains "G2 gate trust documented in help" "trust <name>" "$HELP"
TRUST_REL=$(node "$GOS" paths 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['paths'].get('trust',{}).get('rel',''))" 2>/dev/null)
assert_eq "G3 GOS_PATHS trust key registered" "cache/trust.json" "$TRUST_REL"
CONTRACT_OK=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; gv=json.load(sys.stdin).get('gate_verdicts',{}); print('OK' if gv.get('trustStoreUnreadable') and gv.get('trustUntrusted') else 'MISSING')" 2>/dev/null)
assert_eq "G4 trust contract keys frozen in CONTRACTS" "OK" "$CONTRACT_OK"

t67_teardown
echo "--- T67 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
