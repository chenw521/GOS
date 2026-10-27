#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/gitseed.cjs#fn:render bin/lib/ops/gitseed.cjs#fn:renderLayer bin/lib/ops/gitseed.cjs#fn:validateCodeowner
# gos-map:cmd init
# : templates/git layered masters + render functions ( , )
# Cases: A=master inventory + zero-CJK  B=render byte-exact + variable budget
#        C=renderLayer split + fail-closed  D=validateCodeowner (4 rejections + @org/team)
#        E=destination path map + GOS_SELF_ROOT anchoring  F=master content spot checks
T52_DIR=""
GSEED="$GOS_ROOT/bin/lib/ops/gitseed.cjs"
TDIR="$GOS_ROOT/templates/git"

t52_setup() {
  T52_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t52"
  mkdir -p "$T52_DIR" && cd "$T52_DIR" || exit 1
}
t52_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T52_DIR"; }

t52_setup
trap 't52_teardown' EXIT
PASS=0; FAIL=0
echo "--- T52: git seed masters + render (R-01/R-02/R-04) ---"

# --- A: master inventory (universal 7 + node 2) + zero-CJK invariant ---
for f in \
  ISSUE_TEMPLATE/bug_report.yml \
  ISSUE_TEMPLATE/feature_request.yml \
  ISSUE_TEMPLATE/config.yml \
  PULL_REQUEST_TEMPLATE.md \
  CODEOWNERS.tpl \
  commitlint.config.yaml \
  CHANGELOG.md.tpl \
  node/ci.yml \
  node/release.yml.tpl; do
  if [ -f "$TDIR/$f" ]; then echo "  ✓ A master present: $f"; PASS=$((PASS+1))
  else echo "  ✗ A master missing: $f"; FAIL=$((FAIL+1)); fi
done
CJK=$(grep -rlP '[\x{4e00}-\x{9fff}]' "$TDIR" 2>/dev/null || true)
if [ -z "$CJK" ]; then echo "  ✓ A masters contain zero CJK characters"; PASS=$((PASS+1))
else echo "  ✗ A CJK found in masters: $CJK"; FAIL=$((FAIL+1)); fi

# --- B: render() — layer union, byte-exact substitution, variable budget ---
set +e; BCOUNT=$(GSEED="$GSEED" node -e "const g=require(process.env.GSEED);console.log(Object.keys(g.render({codeowner:'@octocat',repo:'octocat/widget'})).length)" 2>&1); BRC=$?; set -e
assert_exit "B1 render() succeeds" 0 "$BRC"
assert_eq "B1 render() emits universal+node layers (9 files)" "9" "$BCOUNT"

EXP_CO="$(sed 's/{{CODEOWNER}}/@octocat/g' "$TDIR/CODEOWNERS.tpl")"
set +e; OUT_CO=$(GSEED="$GSEED" node -e "const g=require(process.env.GSEED);process.stdout.write(g.render({codeowner:'@octocat',repo:'octocat/widget'})['.github/CODEOWNERS']||'')" 2>&1); set -e
assert_eq "B2 rendered CODEOWNERS = master with variable substituted (byte-exact)" "$EXP_CO" "$OUT_CO"

set +e; OUT_PLAIN=$(TDIR="$TDIR" GSEED="$GSEED" node -e "
const g=require(process.env.GSEED);
const m=g.render({codeowner:'@octocat',repo:'octocat/widget'});
const fs=require('fs');
const src=fs.readFileSync(process.env.TDIR+'/ISSUE_TEMPLATE/bug_report.yml','utf8');
process.stdout.write(m['.github/ISSUE_TEMPLATE/bug_report.yml']===src?'IDENTICAL':'DIFFERS')" 2>&1); set -e
assert_contains "B3 variable-free master rendered byte-identical" "IDENTICAL" "$OUT_PLAIN"

N_BUDGET=$(grep -rlE '\{\{[A-Z][A-Z0-9_]*\}\}' "$TDIR" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "B4 masters carrying a render variable (CODEOWNER + REPO)" "2" "$N_BUDGET"
if grep -qF '{{CODEOWNER}}' "$TDIR/CODEOWNERS.tpl" 2>/dev/null; then
  echo "  ✓ B4 the single variable is {{CODEOWNER}} in CODEOWNERS.tpl"; PASS=$((PASS+1))
else echo "  ✗ B4 {{CODEOWNER}} missing from CODEOWNERS.tpl"; FAIL=$((FAIL+1)); fi
set +e; LEFT=$(GSEED="$GSEED" node -e "
const g=require(process.env.GSEED);
const bad=Object.entries(g.render({codeowner:'@octocat',repo:'octocat/widget'})).filter((e)=>/\{\{[A-Z][A-Z0-9_]*\}\}/.test(e[1])).map((e)=>e[0]).join(',');
console.log(bad||'NONE')" 2>&1); set -e
assert_eq "B5 no unresolved placeholders remain in rendered output" "NONE" "$LEFT"

# --- C: renderLayer() — split, unknown layer, validation inherited ---
set +e; CU=$(GSEED="$GSEED" node -e "
const g=require(process.env.GSEED);
const ks=Object.keys(g.renderLayer('universal',{codeowner:'@octocat',repo:'octocat/widget'}));
console.log(ks.length+'|'+ks.some((k)=>k.includes('workflows')))" 2>&1); set -e
assert_contains "C1 universal layer = 7 files, no node/workflows entries" "7|false" "$CU"

set +e; CN=$(GSEED="$GSEED" node -e "const g=require(process.env.GSEED);console.log(Object.keys(g.renderLayer('node',{codeowner:'@octocat',repo:'octocat/widget'})).sort().join(' '))" 2>&1); set -e
assert_eq "C2 node layer = ci.yml + release.yml destinations" ".github/workflows/ci.yml .github/workflows/release.yml" "$CN"

set +e; CB=$(GSEED="$GSEED" node -e "const g=require(process.env.GSEED);try{g.renderLayer('staging',{codeowner:'@octocat',repo:'octocat/widget'});console.log('BAD:no-throw')}catch(e){console.log('THREW')}" 2>&1); set -e
assert_contains "C3 unknown layer name throws" "THREW" "$CB"

set +e; CV=$(GSEED="$GSEED" node -e "const g=require(process.env.GSEED);try{g.renderLayer('universal',{codeowner:'@octo cat'});console.log('BAD:no-throw')}catch(e){console.log('THREW:'+e.message.slice(0,17))}" 2>&1); set -e
assert_contains "C4 renderLayer validates codeowner (fail-closed)" "THREW:invalid codeowner" "$CV"

set +e; D1=$(GSEED="$GSEED" node -e "const g=require(process.env.GSEED);try{g.validateCodeowner('');console.log('BAD:no-throw')}catch(e){console.log('THREW:'+e.message.slice(0,17))}" 2>&1); set -e
assert_contains "D1 empty codeowner rejected" "THREW:invalid codeowner" "$D1"

set +e; D2=$(GSEED="$GSEED" node -e "const g=require(process.env.GSEED);try{g.validateCodeowner('octocat\noctocat');console.log('BAD:no-throw')}catch(e){console.log('THREW:'+e.message.slice(0,17))}" 2>&1); set -e
assert_contains "D2 multi-line codeowner rejected" "THREW:invalid codeowner" "$D2"

set +e; D3=$(GSEED="$GSEED" node -e "const g=require(process.env.GSEED);try{g.validateCodeowner('@octo cat');console.log('BAD:no-throw')}catch(e){console.log('THREW:'+e.message.slice(0,17))}" 2>&1); set -e
assert_contains "D3 codeowner containing a space rejected" "THREW:invalid codeowner" "$D3"

set +e; D4=$(GSEED="$GSEED" node -e "const g=require(process.env.GSEED);try{g.validateCodeowner('a'.repeat(65));console.log('BAD:no-throw')}catch(e){console.log('THREW:'+e.message.slice(0,17))}" 2>&1); set -e
assert_contains "D4 codeowner longer than 64 chars rejected" "THREW:invalid codeowner" "$D4"

set +e; D5=$(GSEED="$GSEED" node -e "const g=require(process.env.GSEED);try{console.log('OK:'+g.validateCodeowner('@org/team'))}catch(e){console.log('THREW')}" 2>&1); set -e
assert_contains "D5 @org/team accepted (red-team R4-F7 positive)" "OK:@org/team" "$D5"

set +e; D6=$(GSEED="$GSEED" node -e "const g=require(process.env.GSEED);const r=[g.validateCodeowner('octocat'),g.validateCodeowner('org/team')].join(',');console.log(r==='octocat,org/team'?'OK-bare-forms':'BAD:'+r)" 2>&1); set -e
assert_contains "D6 bare user and org/team forms accepted" "OK-bare-forms" "$D6"

set +e; D7=$(GSEED="$GSEED" node -e "const g=require(process.env.GSEED);try{g.render({codeowner:'@octo cat'});console.log('BAD:no-throw')}catch(e){console.log('THREW')}" 2>&1); set -e
assert_contains "D7 render() refuses to run with illegal codeowner" "THREW" "$D7"

# --- E: destination path map + GOS_SELF_ROOT anchoring ( flavor)
set +e; EK=$(GSEED="$GSEED" node -e "
const g=require(process.env.GSEED);
const want=['.github/ISSUE_TEMPLATE/bug_report.yml','.github/ISSUE_TEMPLATE/feature_request.yml','.github/ISSUE_TEMPLATE/config.yml','.github/PULL_REQUEST_TEMPLATE.md','.github/CODEOWNERS','commitlint.config.yaml','CHANGELOG.md','.github/workflows/ci.yml','.github/workflows/release.yml'];
const got=Object.keys(g.render({codeowner:'@octocat',repo:'octocat/widget'})).sort();
console.log(JSON.stringify(got)===JSON.stringify(want.slice().sort())?'EXACT':'GOT:'+got.join(' '))" 2>&1); set -e
assert_contains "E1 destination path map exact (9 landing paths)" "EXACT" "$EK"

mkdir -p "$T52_DIR/decoy/templates/git"
printf '* decoy-owner\n' > "$T52_DIR/decoy/templates/git/CODEOWNERS.tpl"
set +e; DEC=$(cd "$T52_DIR/decoy" && GSEED="$GSEED" node -e "const g=require(process.env.GSEED);process.stdout.write(g.render({codeowner:'@octocat',repo:'octocat/widget'})['.github/CODEOWNERS']||'')" 2>&1); set -e
assert_contains "E2 decoy cwd templates ignored (GOS_SELF_ROOT anchored)" "@octocat" "$DEC"
if printf '%s' "$DEC" | grep -q 'decoy-owner'; then
  echo "  ✗ E2 decoy content leaked into render output"; FAIL=$((FAIL+1))
else echo "  ✓ E2 no decoy content in render output"; PASS=$((PASS+1)); fi

# --- F: master content spot checks ---
CFG=$(cat "$TDIR/ISSUE_TEMPLATE/config.yml" 2>/dev/null || true)
assert_contains "F1 config.yml declares a Discussions contact link" "discussions" "$CFG"
assert_contains "F1 config.yml notes the Discussions dependency" "Discussions" "$CFG"

BUG=$(cat "$TDIR/ISSUE_TEMPLATE/bug_report.yml" 2>/dev/null || true)
assert_contains "F2 bug form captures AI assistant" "AI assistant" "$BUG"
assert_contains "F2 bug form captures model" "Model" "$BUG"
assert_contains "F2 bug form captures gos --version" "gos --version" "$BUG"
assert_contains "F2 bug form captures Node.js version" "Node.js version" "$BUG"

PRT=$(cat "$TDIR/PULL_REQUEST_TEMPLATE.md" 2>/dev/null || true)
assert_contains "F3 PR template shows Conventional title shape" "type(scope):" "$PRT"
assert_contains "F3 PR template requires AI declaration" "AI assistance" "$PRT"

CL=$(cat "$TDIR/commitlint.config.yaml" 2>/dev/null || true)
assert_contains "F4 commitlint config lists feat type" "feat" "$CL"
assert_contains "F4 commitlint config lists revert type" "revert" "$CL"
assert_contains "F4 commitlint config forbids empty subject" "subject-empty" "$CL"

if grep -qF '## [Unreleased]' "$TDIR/CHANGELOG.md.tpl" 2>/dev/null; then
  echo "  ✓ F5 changelog skeleton carries empty [Unreleased] section"; PASS=$((PASS+1))
else echo "  ✗ F5 changelog skeleton missing [Unreleased]"; FAIL=$((FAIL+1)); fi

CIY=$(cat "$TDIR/node/ci.yml" 2>/dev/null || true)
assert_contains "F6 user ci.yml pins commitlint major version" "commitlint@19" "$CIY"
assert_contains "F6 user ci.yml declares least-privilege permissions" "contents: read" "$CIY"
if printf '%s' "$CIY" | grep -q 'pull_request_target:'; then
  echo "  ✗ F6 user ci.yml uses forbidden pull_request_target"; FAIL=$((FAIL+1))
else echo "  ✓ F6 user ci.yml never uses pull_request_target"; PASS=$((PASS+1)); fi

echo "--- T52 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
