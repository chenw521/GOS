#!/usr/bin/env bash
# gos-map:cmd init
# gos-map:fn bin/lib/task/init.cjs#fn:cmdInitGit bin/lib/ops/gitseed.cjs#fn:seed bin/lib/ops/gitseed.cjs#fn:renderSelf bin/lib/ops/gitseed.cjs#fn:askConflict
# gos init git seeding command — verb-first dispatch before
# level/intent parsing, layered seeding (universal always, node iff package.json),
# conflict safety (keep by default, .gos-bak on overwrite, symlink refusal,
# unreadable kept), task-state immunity, --render-self self-render idempotency.
# Cases: A=clean non-Node repo  A8=json report  B=clean Node repo  C=non-git refusal
#        D=non-TTY conflicts kept + two-state report  E=--non-interactive beats TTY
#        F/G=pty overwrite/keep  H=ask timeout falls back to keep
#        I=in-flight immunity + state untouched  K=level-path regression
#        L=--render-self sandbox (node layer exempt, idempotent)
#        M=symlink refusal  N=--force rejected  O=--overwrite  P=unreadable kept
#        Q=codeowner fail-closed
# NOTE: non-interactive cases pin stdin to /dev/null (stdin inheritance would
#       otherwise make ask() block on the developer's terminal); pty cases use
# `env -u GOS_HEADLESS script -qec` with piped answers ( pattern).
T56_DIR=""

t56_setup() {
  T56_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t56"
  mkdir -p "$T56_DIR" && cd "$T56_DIR" || exit 1
}

t56_mkrepo() {  # fresh git repo sandbox inside T56_DIR + cd into it
  local d="$T56_DIR/$1"
  mkdir -p "$d" && cd "$d" || exit 1
  git init -q . && git commit -q --allow-empty -m t56-seed
}

t56_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T56_DIR"; }

UNIVERSAL_FILES=".github/ISSUE_TEMPLATE/bug_report.yml .github/ISSUE_TEMPLATE/feature_request.yml .github/ISSUE_TEMPLATE/config.yml .github/PULL_REQUEST_TEMPLATE.md .github/CODEOWNERS commitlint.config.yaml CHANGELOG.md"

t56_json_counts() {  # parse init-git --json stdout -> "created=N skipped=N overwritten=N rootkey=bool"
  python3 -c "
import json,sys
try:
    d=json.loads(sys.stdin.read())
    print('created=%d skipped=%d overwritten=%d rootkey=%s' % (len(d['created']),len(d['skipped']),len(d['overwritten']),'root' in d))
except Exception as e:
    print('BADJSON:'+str(e))"
}

t56_setup
trap 't56_teardown' EXIT
PASS=0; FAIL=0
echo "--- T56: gos init git (R-01/R-03) ---"

# --- A: clean non-Node repo → universal layer only ---
t56_mkrepo plain
out=$(node "$GOS" init git --codeowner '@octocat' --repo octocat/widget </dev/null 2>&1); rc=$?
assert_exit "A1 clean non-Node repo exit 0" 0 "$rc"
for f in $UNIVERSAL_FILES; do
  if [ -f "$f" ]; then echo "  ✓ A2 seeded: $f"; PASS=$((PASS+1))
  else echo "  ✗ A2 missing: $f"; FAIL=$((FAIL+1)); fi
done
if [ -e ".github/workflows" ]; then echo "  ✗ A3 node layer seeded without package.json"; FAIL=$((FAIL+1))
else echo "  ✓ A3 node layer withheld (no package.json)"; PASS=$((PASS+1)); fi
assert_contains "A4 CODEOWNERS rendered with codeowner" "@octocat" "$(cat .github/CODEOWNERS 2>/dev/null)"
STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
assert_eq "A5 nothing auto-staged" "0" "$STAGED"
if [ -f .gos/state.json ]; then echo "  ✗ A6 init git created state.json"; FAIL=$((FAIL+1))
else echo "  ✓ A6 no state.json created"; PASS=$((PASS+1)); fi

t56_mkrepo plainjson
jout=$(node "$GOS" init git --codeowner '@octocat' --repo octocat/widget --json </dev/null 2>/dev/null)
assert_contains "A8 json report (7 created / 0 / 0, root key)" "created=7 skipped=0 overwritten=0 rootkey=True" "$(printf '%s' "$jout" | t56_json_counts)"

# --- B: clean Node repo → universal + node layer ---
t56_mkrepo noderepo
printf '{ "name": "t56-node", "version": "0.0.1" }\n' > package.json
out=$(node "$GOS" init git --codeowner '@octocat' --repo octocat/widget </dev/null 2>&1); rc=$?
assert_exit "B1 clean Node repo exit 0" 0 "$rc"
for f in .github/workflows/ci.yml .github/workflows/release.yml; do
  if [ -f "$f" ]; then echo "  ✓ B2 node layer seeded: $f"; PASS=$((PASS+1))
  else echo "  ✗ B2 node layer missing: $f"; FAIL=$((FAIL+1)); fi
done
assert_contains "B3 report names node layer detection" "universal + node (package.json detected)" "$out"

# --- C: non-git dir refused with git init hint (ceiling stops discovery at the repo containing TESTBASE) ---
mkdir -p "$T56_DIR/nogit" && cd "$T56_DIR/nogit" || exit 1
out=$(GIT_CEILING_DIRECTORIES="$GOS_ROOT" node "$GOS" init git --codeowner '@octocat' --repo octocat/widget </dev/null 2>&1); rc=$?
assert_exit "C1 non-git work-tree refused (exit 1)" 1 "$rc"
assert_contains "C2 hint suggests git init" "git init" "$out"
cd "$T56_DIR" || exit 1

# --- D: non-TTY conflicts — user versions kept, two-state report ---
t56_mkrepo conflicts
printf '# user-tweaked commitlint\n' > commitlint.config.yaml
printf '# user changelog\n' > CHANGELOG.md
out=$(node "$GOS" init git --codeowner '@octocat' --repo octocat/widget </dev/null 2>&1); rc=$?
assert_exit "D1 non-TTY conflicts exit 0" 0 "$rc"
assert_eq "D2 user commitlint kept" "# user-tweaked commitlint" "$(cat commitlint.config.yaml)"
assert_eq "D2 user changelog kept" "# user changelog" "$(cat CHANGELOG.md)"
BAKS=$(find . -name '*.gos-bak' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "D3 no .gos-bak written (nothing overwritten)" "0" "$BAKS"
t56_mkrepo conflictsjson
printf '# user-tweaked commitlint\n' > commitlint.config.yaml
printf '# user changelog\n' > CHANGELOG.md
jout=$(node "$GOS" init git --codeowner '@octocat' --repo octocat/widget --json </dev/null 2>/dev/null)
assert_contains "D4 json two-state report (5 created / 2 kept / 0 overwritten)" "created=5 skipped=2 overwritten=0" "$(printf '%s' "$jout" | t56_json_counts)"
assert_contains "D5 human report marks kept files" "kept (2)" "$out"

# --- E: --non-interactive beats an answering TTY ---
t56_mkrepo forcedkeep
printf '# user version\n' > commitlint.config.yaml
printf 'y\n' | env -u GOS_HEADLESS script -qec "node '$GOS' init git --codeowner '@octocat' --repo octocat/widget --non-interactive" /dev/null >"$T56_DIR/e.out" 2>&1; erc=$?
assert_exit "E1 --non-interactive under pty exit 0" 0 "$erc"
assert_eq "E2 flag beats TTY input — user file kept" "# user version" "$(cat commitlint.config.yaml)"
EBAK=$([ -f commitlint.config.yaml.gos-bak ] && echo yes || echo no)
assert_eq "E3 no backup written" "no" "$EBAK"

# --- F: interactive overwrite via pty — .gos-bak before replace ---
t56_mkrepo ptyover
printf '# user version\n' > commitlint.config.yaml
printf 'y\n' | env -u GOS_HEADLESS script -qec "node '$GOS' init git --codeowner '@octocat' --repo octocat/widget" /dev/null >"$T56_DIR/f.out" 2>&1; frc=$?
assert_exit "F1 pty overwrite exit 0" 0 "$frc"
if cmp -s commitlint.config.yaml "$GOS_ROOT/templates/git/commitlint.config.yaml"; then
  echo "  ✓ F2 file replaced with rendered master"; PASS=$((PASS+1))
else echo "  ✗ F2 file does not match master"; FAIL=$((FAIL+1)); fi
assert_eq "F3 .gos-bak preserves user version" "# user version" "$(cat commitlint.config.yaml.gos-bak 2>/dev/null)"

# --- G: interactive keep via pty ---
t56_mkrepo ptykeep
printf '# user version\n' > commitlint.config.yaml
printf 'n\n' | env -u GOS_HEADLESS script -qec "node '$GOS' init git --codeowner '@octocat' --repo octocat/widget" /dev/null >"$T56_DIR/g.out" 2>&1; grc=$?
assert_exit "G1 pty keep exit 0" 0 "$grc"
assert_eq "G2 user file kept on 'n'" "# user version" "$(cat commitlint.config.yaml)"
if [ ! -f commitlint.config.yaml.gos-bak ]; then echo "  ✓ G3 no backup when kept"; PASS=$((PASS+1))
else echo "  ✗ G3 unexpected backup for kept file"; FAIL=$((FAIL+1)); fi

# --- H: ask inactivity timeout falls back to keep (short timeout injected) ---
t56_mkrepo asktimeout
printf '# user version\n' > commitlint.config.yaml
cat > "$T56_DIR/timeout-probe.cjs" <<'HP'
const g = require(process.env.GOS_ROOT + '/bin/lib/ops/gitseed.cjs');
g.seed({ root: process.cwd(), codeowner: '@octocat', repo: 'octocat/widget', askTimeoutMs: 400 })
  .then((r) => console.log('RESULT kept=' + r.skipped.includes('commitlint.config.yaml') + ' created=' + r.created.length))
  .catch((e) => { console.error('PROBE-ERR ' + e.message); process.exit(1); });
HP
hstart=$(date +%s)
env -u GOS_HEADLESS script -qec "GOS_ROOT='$GOS_ROOT' node '$T56_DIR/timeout-probe.cjs'" /dev/null </dev/null >"$T56_DIR/h.out" 2>&1; hrc=$?
hend=$(date +%s)
assert_exit "H1 timeout probe exit 0" 0 "$hrc"
assert_contains "H2 silence falls back to keep (no overwrite)" "kept=true" "$(cat "$T56_DIR/h.out")"
if [ $((hend - hstart)) -lt 25 ]; then echo "  ✓ H3 bounded wait ($((hend - hstart))s < 25s, not the 30s default)"; PASS=$((PASS+1))
else echo "  ✗ H3 probe took $((hend - hstart))s — timeout not bounded"; FAIL=$((FAIL+1)); fi

# --- I: in-flight task present — seeding still runs, state untouched ---
t56_mkrepo inflight
node "$GOS" init 1 "t56 in-flight task" </dev/null >/dev/null 2>&1
SHA_BEFORE=$(sha256sum .gos/state.json 2>/dev/null | cut -d' ' -f1)
out=$(node "$GOS" init git --codeowner '@octocat' --repo octocat/widget </dev/null 2>&1); rc=$?
assert_exit "I1 seeding runs despite in-flight task" 0 "$rc"
SHA_AFTER=$(sha256sum .gos/state.json 2>/dev/null | cut -d' ' -f1)
assert_eq "I2 state.json untouched (byte-identical)" "$SHA_BEFORE" "$SHA_AFTER"

# --- K: level-path regression + first-positional reservation edges ---
t56_mkrepo regression
out=$(node "$GOS" init 2 "t56 level regression" </dev/null 2>&1); rc=$?
assert_exit "K1 gos init 2 keeps original semantics" 0 "$rc"
assert_eq "K1 level recorded" "2" "$(python3 -c "import json;print(json.load(open('.gos/state.json'))['level'])")"

t56_mkrepo regression2
node "$GOS" init 1 git "t56 git-themed intent" </dev/null >/dev/null 2>&1; rc=$?
assert_exit "K2 escape hatch: level-first git intent still a task" 0 "$rc"
assert_contains "K2 summary keeps the word git" "git" "$(python3 -c "import json;print(json.load(open('.gos/state.json'))['intent']['summary'])")"

t56_mkrepo regression3
out=$(node "$GOS" init git --repo octocat/widget "stray intent" </dev/null 2>&1); rc=$?
assert_exit "K3 stray positional after git refused" 1 "$rc"
assert_contains "K3 message explains the level-first escape hatch" "level" "$out"

# --- L: --render-self in a sandboxed copy of the self repo ---
SELFD="$T56_DIR/selfrepo"
mkdir -p "$SELFD"
cp -r "$GOS_ROOT/bin" "$SELFD/bin"
cp -r "$GOS_ROOT/templates" "$SELFD/templates"
cp "$GOS_ROOT/package.json" "$SELFD/package.json"
( cd "$SELFD" && git init -q . && git commit -q --allow-empty -m t56-self ) || exit 1
out=$(cd "$SELFD" && node "$SELFD/bin/gos.cjs" init git --render-self --repo chenw521/GOS </dev/null 2>&1); rc=$?
assert_exit "L1 render-self exit 0" 0 "$rc"
for f in $UNIVERSAL_FILES; do
  if [ -f "$SELFD/$f" ]; then echo "  ✓ L2 self-rendered: $f"; PASS=$((PASS+1))
  else echo "  ✗ L2 missing after render-self: $f"; FAIL=$((FAIL+1)); fi
done
if [ -e "$SELFD/.github/workflows/ci.yml" ]; then echo "  ✗ L3 node master leaked into self render"; FAIL=$((FAIL+1))
else echo "  ✓ L3 node layer exempt from render-self"; PASS=$((PASS+1)); fi
assert_contains "L4 self CODEOWNERS pinned to the self codeowner" "@chenw521" "$(cat "$SELFD/.github/CODEOWNERS" 2>/dev/null)"
( cd "$SELFD" && find .github commitlint.config.yaml CHANGELOG.md -type f 2>/dev/null | sort | xargs sha256sum ) > "$T56_DIR/self.sha1"
out2=$(cd "$SELFD" && node "$SELFD/bin/gos.cjs" init git --render-self --repo chenw521/GOS </dev/null 2>&1); rc2=$?
assert_exit "L5 re-render exit 0" 0 "$rc2"
( cd "$SELFD" && find .github commitlint.config.yaml CHANGELOG.md -type f 2>/dev/null | sort | xargs sha256sum ) > "$T56_DIR/self.sha2"
if cmp -s "$T56_DIR/self.sha1" "$T56_DIR/self.sha2"; then
  echo "  ✓ L6 re-run diff=empty (idempotent, universal layer)"; PASS=$((PASS+1))
else echo "  ✗ L6 re-run changed files:"; diff "$T56_DIR/self.sha1" "$T56_DIR/self.sha2"; FAIL=$((FAIL+1)); fi
assert_contains "L7 re-run reports all kept" "kept (5)" "$out2"

# L8: a live CHANGELOG.md (accumulated entries) must survive render-self —
# regression guard for the entry-erasure incident.
printf -- '- Add live entry before re-render (R-01) [2026-09-21]\n' >> "$SELFD/CHANGELOG.md"
out3=$(cd "$SELFD" && node "$SELFD/bin/gos.cjs" init git --render-self --repo chenw521/GOS </dev/null 2>&1); rc3=$?
assert_exit "L8 render-self with live changelog exit 0" 0 "$rc3"
if grep -q "live entry before re-render" "$SELFD/CHANGELOG.md"; then
  echo "  ✓ L8 live changelog entries survive render-self"; PASS=$((PASS+1))
else echo "  ✗ L8 render-self erased live changelog entries"; FAIL=$((FAIL+1)); fi

# L9: a personalized config.yml Discussions URL must also survive — it is
# repo-specific data (master carries a placeholder), bootstrap-only.
sed -i 's#github.com/[^/]*/[^/]*/discussions#github.com/octocat/widget/discussions#' "$SELFD/.github/ISSUE_TEMPLATE/config.yml"
out4=$(cd "$SELFD" && node "$SELFD/bin/gos.cjs" init git --render-self --repo chenw521/GOS </dev/null 2>&1); rc4=$?
assert_exit "L9 render-self with personalized config exit 0" 0 "$rc4"
if grep -q "octocat/widget/discussions" "$SELFD/.github/ISSUE_TEMPLATE/config.yml"; then
  echo "  ✓ L9 personalized Discussions URL survives render-self"; PASS=$((PASS+1))
else echo "  ✗ L9 render-self reset the personalized Discussions URL"; FAIL=$((FAIL+1)); fi

# --- M: symlink conflict — refuse passthrough, unlink then recreate ---
t56_mkrepo symrepo
printf 'PRECIOUS\n' > secret.txt
ln -s secret.txt commitlint.config.yaml
out=$(node "$GOS" init git --codeowner '@octocat' --repo octocat/widget --overwrite </dev/null 2>&1); rc=$?
assert_exit "M1 symlink conflict with --overwrite exit 0" 0 "$rc"
if [ -L commitlint.config.yaml ]; then echo "  ✗ M2 still a symlink (would keep the passthrough surface)"; FAIL=$((FAIL+1))
else echo "  ✓ M2 replaced by a regular file (unlink + recreate)"; PASS=$((PASS+1)); fi
assert_eq "M3 link target untouched" "PRECIOUS" "$(cat secret.txt)"
if cmp -s commitlint.config.yaml "$GOS_ROOT/templates/git/commitlint.config.yaml"; then
  echo "  ✓ M4 new file carries master content"; PASS=$((PASS+1))
else echo "  ✗ M4 content mismatch after symlink replacement"; FAIL=$((FAIL+1)); fi
assert_eq "M5 backup captured the old linked content" "PRECIOUS" "$(cat commitlint.config.yaml.gos-bak 2>/dev/null)"

# --- N: --force rejected (destructive task-state semantics stay with init) ---
t56_mkrepo forceflag
out=$(node "$GOS" init git --force --codeowner '@octocat' </dev/null 2>&1); rc=$?
assert_exit "N1 --force rejected for init git" 1 "$rc"
assert_contains "N1 message points to --overwrite" "overwrite" "$out"

# --- O: --overwrite replaces conflicts non-interactively, with backup ---
t56_mkrepo overflag
printf '# user version\n' > commitlint.config.yaml
jout=$(node "$GOS" init git --codeowner '@octocat' --repo octocat/widget --overwrite --json </dev/null 2>/dev/null); rc=$?
assert_exit "O1 --overwrite exit 0" 0 "$rc"
assert_contains "O2 json three-state report (6 created / 0 kept / 1 overwritten)" "created=6 skipped=0 overwritten=1" "$(printf '%s' "$jout" | t56_json_counts)"
assert_eq "O3 user version preserved in .gos-bak" "# user version" "$(cat commitlint.config.yaml.gos-bak 2>/dev/null)"

# --- P: unreadable file kept even under --overwrite ---
t56_mkrepo unreadable
printf '# user version\n' > commitlint.config.yaml
chmod 000 commitlint.config.yaml
out=$(node "$GOS" init git --codeowner '@octocat' --repo octocat/widget --overwrite </dev/null 2>&1); rc=$?
chmod 644 commitlint.config.yaml
if [ "$(id -u)" -eq 0 ]; then
  echo "  ✓ P skipped (running as root — chmod 000 stays readable)"; PASS=$((PASS+1))
else
  assert_exit "P1 unreadable file kept (exit 0)" 0 "$rc"
  assert_eq "P1 unreadable content untouched" "# user version" "$(cat commitlint.config.yaml)"
  if [ ! -f commitlint.config.yaml.gos-bak ]; then echo "  ✓ P2 no backup attempted for kept file"; PASS=$((PASS+1))
  else echo "  ✗ P2 backup written for a kept file"; FAIL=$((FAIL+1)); fi
fi

# --- Q: illegal codeowner — fail-closed, zero files written ---
t56_mkrepo badco
out=$(node "$GOS" init git --codeowner 'bad owner' </dev/null 2>&1); rc=$?
assert_exit "Q1 illegal codeowner refused" 1 "$rc"
assert_contains "Q1 fail-closed message" "codeowner" "$out"
if [ -e .github ]; then echo "  ✗ Q2 files written before validation"; FAIL=$((FAIL+1))
else echo "  ✓ Q2 zero files written"; PASS=$((PASS+1)); fi

echo "--- T56 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
