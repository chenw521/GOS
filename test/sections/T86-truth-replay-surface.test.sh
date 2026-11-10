#!/usr/bin/env bash
# gos-map:cmd truth
# truth replay execution surface — widened evidence features, tiered hit
# selection, LHS-normalized synthetic-key veto + --timeout flag
# with self-describing failures + explicit maxBuffer 64 MiB +
# the artifact-path contract (tracked or machine-local zone).
# Env: GOS (CLI path), TESTBASE (isolated base), assert helpers sourced by runner
T86_DIR=""

t86_setup() {
  T86_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t86"
  mkdir -p "$T86_DIR" && cd "$T86_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t86_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T86_DIR"; }

t86_g() { node "$GOS" "$@"; }

t86_excerpt() {
  python3 -c "
import json
s = json.load(open('.gos/state.json'))
t = [x for x in s['observable_truths'] if x['id'] == '$1'][0]
ev = t.get('evidence') or {}
print(ev.get('output_excerpt', ''))" 2>/dev/null
}

t86_verified() {
  python3 -c "
import json
s = json.load(open('.gos/state.json'))
t = [x for x in s['observable_truths'] if x['id'] == '$1'][0]
print('yes' if t.get('verified') else 'no')" 2>/dev/null
}

t86_unverify() {
  python3 -c "
import json
s = json.load(open('.gos/state.json'))
s['observable_truths'][0]['verified'] = False
s['observable_truths'][0]['evidence'] = None
json.dump(s, open('.gos/state.json', 'w'), indent=2)"
}

t86_setup
echo "--- T86: truth replay evidence surface (D-04) + timeout/maxBuffer (D-05) ---"

t86_g init 2 "replay surface" >/dev/null 2>&1
echo "artifact body" > art.txt
git add art.txt
t86_g truth add "surface truth" >/dev/null 2>&1

# --- A: widened features accepted as replay hits (KV family + digit-after-word) ---
OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo push URL=DISABLE"]' --artifact art.txt 2>&1); RC=$?
assert_exit "A1 KV line 'push URL=DISABLE' accepted as replay hit" 0 "$RC"
assert_eq "A1 excerpt is the URL line itself" "push URL=DISABLE" "$(t86_excerpt T1)"

OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo total 165"]' --artifact art.txt 2>&1); RC=$?
assert_exit "A2 digit-after-word 'total 165' accepted as replay hit" 0 "$RC"
assert_eq "A2 excerpt is 'total 165'" "total 165" "$(t86_excerpt T1)"

# --- B: adversarial vector table — LHS-normalized synthetic-key veto (all rejected) ---
python3 -c "
import json
s = json.load(open('.gos/state.json'))
s['observable_truths'][0]['verified'] = False
s['observable_truths'][0]['evidence'] = None
json.dump(s, open('.gos/state.json', 'w'), indent=2)"
for V in 'exit=0' 'Exit=0' 'EXIT_CODE=0' 'rc:0' 'returncode=0' 'status 0'; do
  OUT=$(t86_g truth verify T1 --replay --command "[\"bash\",\"-c\",\"echo $V\"]" --artifact art.txt 2>&1); RC=$?
  assert_exit "B veto '$V' rejected (LHS-normalized synthetic key)" 1 "$RC"
done
assert_eq "B failed verifies never set verified" "no" "$(t86_verified T1)"

# --- C: env-dump steal killed structurally ---
OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo PATH=/usr/lib/x.js:/usr/bin; echo URL=DISABLE"]' --artifact art.txt 2>&1); RC=$?
assert_exit "C1 env-dump replay succeeds via the URL line" 0 "$RC"
assert_eq "C1 excerpt is URL=DISABLE (PATH=...x.js did not steal it)" "URL=DISABLE" "$(t86_excerpt T1)"

OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo PATH=/usr/lib/x.js"]' --artifact art.txt 2>&1); RC=$?
assert_exit "C2 PATH=RHS-path line alone is no hit (env-noise skip + demotion)" 1 "$RC"

# --- D: tiered selection pinned (count > path > KV, document order within tier) ---
OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo src/a.cjs; echo total 165"]' --artifact art.txt 2>&1); RC=$?
assert_exit "D1 count-vs-path case succeeds" 0 "$RC"
assert_eq "D1 count beats path regardless of line order" "total 165" "$(t86_excerpt T1)"

OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo push URL=DISABLE; echo total 165"]' --artifact art.txt 2>&1); RC=$?
assert_exit "D2 KV-vs-count case succeeds" 0 "$RC"
assert_eq "D2 count beats KV" "total 165" "$(t86_excerpt T1)"

OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo URL=DISABLE; echo src/a.cjs"]' --artifact art.txt 2>&1); RC=$?
assert_exit "D3 path-vs-KV case succeeds" 0 "$RC"
assert_eq "D3 path beats KV regardless of line order" "src/a.cjs" "$(t86_excerpt T1)"

OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo CONF=/repo/x.js; echo plain.md"]' --artifact art.txt 2>&1); RC=$?
assert_exit "D4 =-RHS path demotion case succeeds" 0 "$RC"
assert_eq "D4 RHS path demoted to KV; real path line wins" "plain.md" "$(t86_excerpt T1)"

# --- E: ANSI CSI sequences stripped before classification ---
OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","printf \"\\033[32mtotal 165\\033[0m\\n\""]' --artifact art.txt 2>&1); RC=$?
assert_exit "E1 ANSI-wrapped count line accepted" 0 "$RC"
assert_eq "E1 excerpt is ANSI-stripped" "total 165" "$(t86_excerpt T1)"

# --- F: manual-mode excerpt bar unchanged (MANUAL keeps the original three) ---
OUT=$(t86_g truth verify T1 --command "bash test/x.sh" --excerpt "all good" --artifact art.txt 2>&1); RC=$?
assert_exit "F1 manual pure-prose excerpt still rejected" 1 "$RC"
OUT=$(t86_g truth verify T1 --command "bash test/x.sh" --excerpt "exit code: 0" --artifact art.txt 2>&1); RC=$?
assert_exit "F2 manual exit-code excerpt still allowed (bar unchanged)" 0 "$RC"

# --- G: replay evidence passes downstream validation (replay branch of the feature check) ---
OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo URL=DISABLE"]' --artifact art.txt 2>&1); RC=$?
assert_exit "G1 re-verify with widened KV excerpt exits 0" 0 "$RC"
OUT=$(t86_g gate truths 2>&1); RC=$?
assert_exit "G2 gate truths accepts replay evidence with KV excerpt" 0 "$RC"
EXC=$(t86_g _contract 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["semantic_checks"]["excerptFeature"])')
assert_contains "G3 contract string documents replay families" "count|path|KV" "$EXC"

# --- H: maxBuffer 64 MiB (Node default 1 MiB kills >1MB stdout with a misleading error) ---
OUT=$(t86_g truth verify T1 --replay --command '["node","-e","const s=\"x\".repeat(1000);for(let i=0;i<1100;i++)console.log(s);console.log(\"total 165\")"]' --artifact art.txt 2>&1); RC=$?
assert_exit "H1 >1MB stdout succeeds (maxBuffer raised to 64 MiB)" 0 "$RC"
OUT=$(t86_g truth verify T1 --replay --command '["node","-e","const s=\"x\".repeat(1024);for(let i=0;i<70000;i++)console.log(s)"]' --artifact art.txt 2>&1); RC=$?
assert_exit "H2 >64 MiB stdout fails (own maxBuffer branch)" 1 "$RC"
assert_contains "H2 failure names maxBuffer" "maxBuffer" "$OUT"

# --- I: failure diagnostics append the stderr tail (evidence stays stdout-only) ---
OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo boom-stderr-tail >&2; exit 7"]' --artifact art.txt 2>&1); RC=$?
assert_exit "I1 nonzero exit fails replay" 1 "$RC"
assert_contains "I1 diagnostics carry the stderr tail" "boom-stderr-tail" "$OUT"

# --- J: --timeout flag (digits only, 1..600000, flag only, no env var)
OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo total 165"]' --artifact art.txt --timeout 600000 2>&1); RC=$?
assert_exit "J1 --timeout 600000 (cap, inclusive) accepted" 0 "$RC"
for BAD in '0' '1e5' '+5' '0.5' '600001'; do
  OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo total 165"]' --artifact art.txt --timeout "$BAD" 2>&1); RC=$?
  assert_exit "J2 --timeout '$BAD' rejected (/^\d+$/, 1..600000)" 1 "$RC"
  if printf '%s\n' "$OUT" | grep -q -- "--timeout"; then
    echo "  ✓ J2 '$BAD' error names --timeout"; PASS=$((PASS+1))
  else
    echo "  ✗ J2 '$BAD' error does not name --timeout"; FAIL=$((FAIL+1))
  fi
done
OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo total 165"]' --artifact art.txt --timeout 2>&1); RC=$?
assert_exit "J3 --timeout with missing operand dies" 1 "$RC"
assert_contains "J3 missing operand dies with usage copy" "Usage" "$OUT"
OUT=$(t86_g truth verify T1 --command "bash test/x.sh" --excerpt "5 passed, 0 failed" --artifact art.txt --timeout 5000 2>&1); RC=$?
assert_exit "J4 --timeout without --replay rejected" 1 "$RC"

# --- K: 30s default budget + --timeout override (spec truth; slow block ~62s)
OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","sleep 31; echo total 165"]' --artifact art.txt 2>&1); RC=$?
assert_exit "K1 sleep 31 without the flag fails (default 30s budget)" 1 "$RC"
if printf '%s\n' "$OUT" | grep -q -- "--timeout"; then
  echo "  ✓ K1 failure names --timeout (self-describing exit)"; PASS=$((PASS+1))
else
  echo "  ✗ K1 failure does not name --timeout"; FAIL=$((FAIL+1))
fi
OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","sleep 31; echo total 165"]' --artifact art.txt --timeout 120000 2>&1); RC=$?
assert_exit "K2 sleep 31 with --timeout 120000 succeeds" 0 "$RC"

# --- M: artifact-path contract — tracked or machine-local zone, two-phase rejection ---
t86_unverify
echo doomed-body > doomed.txt
OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo contract-marker > exec-sentinel.txt; echo total 165"]' --artifact doomed.txt 2>&1); RC=$?
assert_exit "M1 pre-existing untracked artifact rejected before execution" 1 "$RC"
assert_contains "M1 rejection names the staging cure" "git add doomed.txt" "$OUT"
assert_contains "M1 rejection names the zone cure" "machine-local zone" "$OUT"
if [ -e exec-sentinel.txt ]; then
  echo "  ✗ M1 replay command executed despite the early rejection"; FAIL=$((FAIL+1))
else
  echo "  ✓ M1 replay command never executed"; PASS=$((PASS+1))
fi
assert_eq "M1 failed early check leaves the truth unverified" "no" "$(t86_verified T1)"

git add doomed.txt
OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo total 165"]' --artifact doomed.txt 2>&1); RC=$?
assert_exit "M2 staged artifact records (git add is the cure)" 0 "$RC"

mkdir -p .gos/logs && echo zone-body > .gos/logs/zone-artifact.txt
OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo total 165"]' --artifact .gos/logs/zone-artifact.txt 2>&1); RC=$?
assert_exit "M3 zone artifact records with no git operation" 0 "$RC"

echo real-target > target.txt
ln -s target.txt link.txt
git add target.txt link.txt
t86_unverify
OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo total 165"]' --artifact link.txt 2>&1); RC=$?
assert_exit "M4 tracked symlink artifact rejected (non-regular file)" 1 "$RC"
assert_contains "M4 rejection names the regular-file requirement" "regular file" "$OUT"
assert_eq "M4 failed check leaves the truth unverified" "no" "$(t86_verified T1)"

t86_unverify
OUT=$(t86_g truth verify T1 --replay --command '["bash","-c","echo total 165 > gen-out.txt; echo total 165"]' --artifact gen-out.txt 2>&1); RC=$?
assert_exit "M5 command-generated untracked artifact rejected after execution" 1 "$RC"
assert_contains "M5 rejection carries the same cures" "git add gen-out.txt" "$OUT"
assert_file "M5 the replay command did execute (gen-out.txt exists)" "gen-out.txt"
assert_eq "M5 failed check leaves the truth unverified" "no" "$(t86_verified T1)"

echo manual-body > manual-art.txt
OUT=$(t86_g truth verify T1 --command "bash test/x.sh" --excerpt "exit code: 0" --artifact manual-art.txt 2>&1); RC=$?
assert_exit "M6 manual untracked artifact rejected by the same rule" 1 "$RC"
assert_contains "M6 rejection names the staging cure" "git add manual-art.txt" "$OUT"
git add manual-art.txt
OUT=$(t86_g truth verify T1 --command "bash test/x.sh" --excerpt "exit code: 0" --artifact manual-art.txt 2>&1); RC=$?
assert_exit "M7 manual staged artifact records" 0 "$RC"

# fresh-clone read: tracked + zone evidence validates where no machine-local files exist
t86_g truth verify T1 --replay --command '["bash","-c","echo total 165"]' --artifact art.txt >/dev/null 2>&1
t86_g truth add "zone artifact truth" >/dev/null 2>&1
t86_g truth verify T2 --replay --command '["bash","-c","echo total 165"]' --artifact .gos/logs/zone-artifact.txt >/dev/null 2>&1
git commit -qm artifacts
CLONE="$T86_DIR-clone"
git clone -q "$T86_DIR" "$CLONE" 2>/dev/null
mkdir -p "$CLONE/.gos"
cp .gos/state.json "$CLONE/.gos/state.json"
COUT=$(cd "$CLONE" && node -e "require('$GOS_ROOT/bin/lib/core/index.cjs').readState()" 2>&1)
if printf '%s\n' "$COUT" | grep -q "artifact_path"; then
  echo "  ✗ M8 fresh clone flags tracked/zone evidence"; FAIL=$((FAIL+1))
else
  echo "  ✓ M8 fresh clone validates tracked + zone evidence"; PASS=$((PASS+1))
fi

# git probe failure (unusable git environment) degrades to the legacy
# existence check — GIT_DIR pointing nowhere makes every git call fail while
# the sandbox itself stays a valid nested repo
M9DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t86brokengit"
mkdir -p "$M9DIR" && cd "$M9DIR" || exit 1
git init -q . && git commit -q --allow-empty -m m9
t86_g init 2 "broken-git sandbox" >/dev/null 2>&1
echo loose-body > loose.txt
t86_g truth add "broken-git truth" >/dev/null 2>&1
OUT=$(GIT_DIR="$M9DIR/broken-git" t86_g truth verify T1 --replay --command '["bash","-c","echo total 165"]' --artifact loose.txt 2>&1); RC=$?
assert_exit "M9 git-probe failure degrades to legacy existence check" 0 "$RC"
cd "$T86_DIR" || exit 1
rm -rf "$M9DIR"

# --- L: structure contract (same-commit sync with / )
if grep -q 'EVIDENCE_FEATURE_RES_MANUAL' "$GOS_ROOT/bin/lib/core/state.cjs"; then
  echo "  ✓ L1 state.cjs declares EVIDENCE_FEATURE_RES_MANUAL"; PASS=$((PASS+1))
else
  echo "  ✗ L1 EVIDENCE_FEATURE_RES_MANUAL missing from state.cjs"; FAIL=$((FAIL+1))
fi
if grep -q 'EVIDENCE_FEATURE_RES_REPLAY' "$GOS_ROOT/bin/lib/core/state.cjs"; then
  echo "  ✓ L2 state.cjs declares EVIDENCE_FEATURE_RES_REPLAY"; PASS=$((PASS+1))
else
  echo "  ✗ L2 EVIDENCE_FEATURE_RES_REPLAY missing from state.cjs"; FAIL=$((FAIL+1))
fi
if grep -q 'maxBuffer' "$GOS_ROOT/bin/lib/knowledge/truth.cjs"; then
  echo "  ✓ L3 truth.cjs pins maxBuffer explicitly"; PASS=$((PASS+1))
else
  echo "  ✗ L3 maxBuffer not pinned in truth.cjs"; FAIL=$((FAIL+1))
fi
if node -e "const z=require('$GOS_ROOT/bin/lib/core/state.cjs').ARTIFACT_LOCAL_ZONES; process.exit(Array.isArray(z)&&z.includes('.gos/logs/')?0:1)" 2>/dev/null; then
  echo "  ✓ L4 state.cjs exports ARTIFACT_LOCAL_ZONES"; PASS=$((PASS+1))
else
  echo "  ✗ L4 ARTIFACT_LOCAL_ZONES not exported from state.cjs"; FAIL=$((FAIL+1))
fi
if grep -q 'artifactPathError' "$GOS_ROOT/bin/lib/knowledge/truth.cjs"; then
  echo "  ✓ L5 truth.cjs consumes the shared predicate"; PASS=$((PASS+1))
else
  echo "  ✗ L5 truth.cjs does not reference artifactPathError"; FAIL=$((FAIL+1))
fi
if grep -q 'tracked or machine-local zone' "$GOS_ROOT/bin/lib/knowledge/truth.cjs"; then
  echo "  ✓ L6 usage text carries the artifact qualifier"; PASS=$((PASS+1))
else
  echo "  ✗ L6 usage qualifier missing from truth.cjs"; FAIL=$((FAIL+1))
fi

t86_teardown
