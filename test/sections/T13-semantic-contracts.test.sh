#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/gate.cjs#fn:cmdGate bin/lib/map/contract.cjs#fn:cmdContract
# gos-map:cmd gate,_contract
# : CONTRACTS.semantic_checks contract layer + input constraint helpers + table-driven downgrade banner (existing subcommands)
# Env: GOS (CLI path), TESTBASE (isolated base), assert helpers sourced by runner
T13_DIR=""

t13_setup() {
  T13_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t13"
  mkdir -p "$T13_DIR" && cd "$T13_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t13_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T13_DIR"; }

t13_setup
echo "--- T13: semantic_checks contract + input constraints + downgrade banner ---"

# --- T13.1: `_contract` semantic_checks layer has ≥14 keys (13 spec §2 + lazyFreeze [F1]) ---
NKEYS=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)['semantic_checks']))" 2>/dev/null)
if [ "${NKEYS:-0}" -ge 14 ] 2>/dev/null; then
  echo "  ✓ semantic_checks has ≥14 keys ($NKEYS)"; PASS=$((PASS+1))
else
  echo "  ✗ semantic_checks key count '${NKEYS:-<none>}' < 14"; FAIL=$((FAIL+1))
fi

# --- .2: required key set present (spec 13 keys + lazyFreeze)
KEYS=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print(','.join(sorted(json.load(sys.stdin)['semantic_checks'].keys())))" 2>/dev/null)
MISSING=$(python3 - "$KEYS" <<'PYEOF'
import sys
keys = set(filter(None, sys.argv[1].split(',')))
need = {'banner','evidenceShape','excerptFeature','bidirectional','diffHit','pathExists',
        'allowlist','lessonsAnchor','diffInvocations','bootstrapBanner','skipBanner',
        'manualWarning','globalWriteHint','specSha','lazyFreeze'}
print(','.join(sorted(need - keys)))
PYEOF
)
assert_eq "all 15 required keys present" "" "$MISSING"

# --- .3: spec texts frozen verbatim (banner + evidenceShape + allowlist array)
BANNER=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['semantic_checks']['banner'])")
assert_eq "banner frozen verbatim from spec §2" "gate checks syntax+consistency only, not semantic quality" "$BANNER"
EVID=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['semantic_checks']['evidenceShape'])")
assert_eq "evidenceShape frozen verbatim" "{command, output_excerpt, artifact_path}" "$EVID"
ALLOW=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print('|'.join(json.load(sys.stdin)['semantic_checks']['allowlist']))" 2>/dev/null)
assert_eq "allowlist is the 6-entry spec array" ".changes.md|CHANGELOG.md|commitlint.config.yaml|*.lock|.gos/**(excl gates.json+gates/)|truth artifact_path" "$ALLOW"
LZF=$(node "$GOS" _contract 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['semantic_checks'].get('lazyFreeze',''))")
if [ -n "$LZF" ]; then
  echo "  ✓ lazyFreeze banner key non-empty [F1]"; PASS=$((PASS+1))
else
  echo "  ✗ lazyFreeze banner key missing/empty [F1]"; FAIL=$((FAIL+1))
fi

# --- .4: table-driven emission — banner text appears in CLI source exactly once (the table)
# CONTRACTS table lives in core/state.cjs — counted surface is the -shared frozen set (multi-file grep)
OCC=$(cat "$GOS" "$GOS_ROOT/bin/lib/core/fsio.cjs" "$GOS_ROOT/bin/lib/core/state.cjs" "$GOS_ROOT/bin/lib/core/lock.cjs" 2>/dev/null | grep -c "gate checks syntax+consistency only")
assert_eq "banner text lives only in CONTRACTS table (not in cmdGate)" "1" "$OCC"

# --- .5: sandbox state — covered decision + verified truth + lessons fixture
# (T2 migration: string evidence → three-element object [D-30]; artifact must exist)
node "$GOS" init 3 "semantic contracts" >/dev/null 2>&1
mkdir -p test/out && echo "45 passed, 0 failed" > test/out/t13.log
python3 -c "
import json; s=json.load(open('.gos/state.json'))
s['decisions']=[{'id':'D-01','title':'semantic gates','covered':True}]
s['observable_truths']=[{'id':'T-01','description':'banner emitted','verified':True,'evidence':{'command':'bash test/run-sections.sh T13','output_excerpt':'45 passed, 0 failed','artifact_path':'test/out/t13.log'}}]
json.dump(s,open('.gos/state.json','w'),indent=2)"
printf '# frozen lessons (test fixture)\n' > .gos/lessons.md
# P15 : lessons gate reads json truth — seed a real store (md fixture alone
# is pre-migration and checks nothing)
node "$GOS" lessons add --type project --scene "t13" --lesson "semantic contracts fixture" >/dev/null 2>&1

# --- .6: four EXISTING subcommands — output has ✓ AND last non-empty line == table banner
# (gate semantic deliberately NOT tested — creates it, asserts)
for SUB in all truths coverage lessons; do
  set +e; GOUT=$(node "$GOS" gate "$SUB" 2>&1); RC=$?; set -e
  assert_exit "gate $SUB passes" 0 "$RC"
  if printf '%s\n' "$GOUT" | grep -q '✓'; then
    echo "  ✓ gate $SUB emitted a ✓ line"; PASS=$((PASS+1))
  else
    echo "  ✗ gate $SUB printed no ✓ (fixture broken)"; FAIL=$((FAIL+1))
  fi
  LAST=$(printf '%s\n' "$GOUT" | grep -v '^[[:space:]]*$' | tail -1)
  assert_eq "gate $SUB last line is table-driven ⚠ banner" "⚠ $BANNER" "$LAST"
done

# --- .7: no ✓ → no banner (gate lessons without any lessons truth = nothing to check)
# (sentinel deleted : the gate reads truth-file existence only — no config key)
rm -f .gos/lessons.md .gos/lessons.json .gos/cache/.lessons-anchors.json
set +e; LOUT=$(node "$GOS" gate lessons 2>&1); LRC=$?; set -e
assert_exit "gate lessons without lessons truth exits 0" 0 "$LRC"
if printf '%s\n' "$LOUT" | grep -q "$BANNER"; then
  echo "  ✗ banner must not print when no ✓ line emitted"; FAIL=$((FAIL+1))
else
  echo "  ✓ no banner without ✓ (nothing-to-check path)"; PASS=$((PASS+1))
fi

# --- T13.8: input-constraint helper via `_contract --check-input` [R1-F9] ---
set +e
node "$GOS" _contract --check-input "normal text" --max-cp 200 2>/dev/null; RC_OK=$?
node "$GOS" _contract --check-input "$(python3 -c 'print("x"*201, end="")')" --max-cp 200 2>/dev/null; RC_LONG=$?
node "$GOS" _contract --check-input "$(printf 'bad\x01ctrl')" --max-cp 200 2>/dev/null; RC_CTRL=$?
node "$GOS" _contract --check-input "$(printf 'line1\n- [x] inject')" --max-cp 200 2>/dev/null; RC_NLLIST=$?
node "$GOS" _contract --check-input "$(python3 -c 'print("😀"*120, end="")')" --max-cp 200 2>/dev/null; RC_EMOJI_OK=$?
node "$GOS" _contract --check-input "$(python3 -c 'print("😀"*201, end="")')" --max-cp 200 2>/dev/null; RC_EMOJI_LONG=$?
node "$GOS" _contract --check-input "'\$(touch pwned)'" --max-cp 200 2>/dev/null; RC_CANARY=$?
set -e
assert_exit "normal text accepted" 0 "$RC_OK"
assert_exit "over-200cp rejected" 1 "$RC_LONG"
assert_exit "control char rejected (badText)" 1 "$RC_CTRL"
assert_exit "newline list-entry '\\n- [' rejected" 1 "$RC_NLLIST"
assert_exit "120 emoji = 120 cps accepted (codepoint cap, not utf16)" 0 "$RC_EMOJI_OK"
assert_exit "201 emoji rejected (codepoint cap)" 1 "$RC_EMOJI_LONG"
assert_exit "canary text itself not executed-error" 0 "$RC_CANARY"
if [ -e "$T13_DIR/pwned" ]; then
  echo "  ✗ CANARY: pwned side-effect file created — injection executed"; FAIL=$((FAIL+1))
else
  echo "  ✓ canary: single-quote injection not executed (no side-effect file)"; PASS=$((PASS+1))
fi

# --- .9: `_contract` default mode unchanged — banner-free JSON ( .5 parity for new layer)
FIRST=$(node "$GOS" _contract 2>/dev/null | head -1)
assert_eq "_contract stdout line 1 still '{' (no CLI banner)" "{" "$FIRST"

t13_teardown
