#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/setup.cjs#fn:cmdSetupCommitlint
# gos-map:cmd setup
# gos setup --commitlint hook
# Cases: A=install basics + non-git guard  B=enforcement (bad/good msg via real npx)
#        C=npx-missing skip  D=teardown/restore/idempotency
#        E=gos-root layout uses master config via --config
#        F=packaging (files array + npm pack)  G=sandbox commit stat carries hooks/
#        H=offline npx classification via PATH shim (fail-open/fail-closed)
T60_DIR=""

t60_setup() {
  T60_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t60"
  mkdir -p "$T60_DIR" && cd "$T60_DIR" || exit 1
}
t60_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T60_DIR"; }

t60_setup
trap 't60_teardown' EXIT
PASS=0; FAIL=0
echo "--- T60: setup --commitlint hook (D-52/R-19) ---"

# Sandbox config used by the enforcement cases below (identical semantics to
# the shipped master; keeps the section hermetic inside TESTBASE).
t60_write_cfg() {
  cat > "$1" <<'EOF'
rules:
  type-empty: [2, never]
  type-enum:
    - 2
    - always
    - [feat, fix, docs, refactor, test, chore, ci, build, perf, revert]
  subject-empty: [2, never]
  subject-full-stop: [2, never, '.']
  subject-case:
    - 2
    - never
    - [sentence-case, start-case, pascal-case, upper-case]
  header-max-length: [2, always, 72]
EOF
}

# TESTBASE sits inside the GOS repo — stop git's upward discovery so non-init'd
# sandboxes are truly "not a git repository" (never touch the real repo).
export GIT_CEILING_DIRECTORIES="$TESTBASE"
# shared npx cache: single commitlint@19 fetch for the whole section
export NPM_CONFIG_CACHE="$TESTBASE/npm-cache-t60"
set +e; WARM=$(npx --yes commitlint@19 --version </dev/null 2>&1); set -e
assert_contains "A0 pre-warm commitlint@19 via shared npx cache" "@commitlint/cli@" "$WARM"

# --- A: install basics (user-repo shape: no gos files at root) ---
t60_setup
git init -q . && git commit -q --allow-empty -m "chore: root"
set +e; AOUT=$(node "$GOS" setup --commitlint 2>&1); ARC=$?; set -e
assert_exit "A1 install exits 0" 0 "$ARC"
assert_contains "A1 output names the installed hook" "hooks/commit-msg" "$AOUT"
assert_file "A2 hook file installed" "hooks/commit-msg"
if [ -x "hooks/commit-msg" ]; then
  echo "  ✓ A3 hook file is executable"; PASS=$((PASS+1))
else
  echo "  ✗ A3 hook file not executable"; FAIL=$((FAIL+1))
fi
assert_eq "A4 core.hooksPath set to hooks" "hooks" "$(git config --get core.hooksPath)"
set +e; node -e "const s=JSON.parse(require('fs').readFileSync('.gos/cache/commitlint-hook.json','utf8'));console.log(s.prior_core_hooks_path===null?'PRIOR_NULL':'PRIOR='+s.prior_core_hooks_path)" > t60a5.txt 2>&1; set -e
assert_contains "A5 backup records prior hooksPath=null (was unset)" "PRIOR_NULL" "$(cat t60a5.txt)"

# --- B: enforcement through a real `git commit` (hook fires, npx commitlint@19) ---
t60_write_cfg commitlint.config.yaml
set +e; BOUT=$(git commit -q --allow-empty -m "bad message no type" 2>&1); BRC=$?; set -e
assert_exit "B1 non-conventional message blocks the commit (exit 1)" 1 "$BRC"
assert_contains "B2 commitlint reports the violation" "type-empty" "$BOUT"
set +e; git commit -q --allow-empty -m "feat(core): test" >/dev/null 2>&1; BRC2=$?; set -e
assert_exit "B3 conventional message passes (exit 0)" 0 "$BRC2"
assert_contains "B4 HEAD carries the conventional subject" "feat(core): test" "$(git log -1 --format=%s)"

# B5: the SHIPPED master config enforces too (no stand-in drift between this
# section's seeded config and templates/git/commitlint.config.yaml).
cp "$GOS_ROOT/templates/git/commitlint.config.yaml" commitlint.config.yaml
git add commitlint.config.yaml >/dev/null 2>&1
set +e; BOUT5=$(git commit --allow-empty -q -m "feat(core): Start Case Subject Must Be Rejected" 2>&1); BRC5=$?; set -e
assert_exit "B5 shipped master rejects start-case subject (exit 1)" 1 "$BRC5"
assert_contains "B5 commitlint names subject-case via shipped master" "subject-case" "$BOUT5"
t60_write_cfg commitlint.config.yaml

# --- C: npx missing → hook exits 0 with skip notice (never blocks on tooling absence) ---
mkdir -p "$T60_DIR/minbin"
ln -s "$(command -v dirname)" "$T60_DIR/minbin/dirname"
printf 'bad message\n' > "$T60_DIR/badmsg.txt"
# direct invocation: shebang resolves /bin/sh without PATH; minbin carries the
# only external binary the skip path needs (dirname) and no node/npx anywhere
set +e; COUT=$(PATH="$T60_DIR/minbin" hooks/commit-msg "$T60_DIR/badmsg.txt" 2>&1); CRC=$?; set -e
assert_exit "C1 npx absent → hook exits 0 (skip, never blocks)" 0 "$CRC"
assert_contains "C2 skip notice printed" "skipping" "$COUT"

# --- D: teardown restores (unset-prior case, same sandbox as B) ---
set +e; DOUT=$(node "$GOS" setup --commitlint --teardown 2>&1); DRC=$?; set -e
assert_exit "D1 teardown exits 0" 0 "$DRC"
assert_eq "D2 core.hooksPath unset (prior was unset)" "" "$(git config --get core.hooksPath 2>/dev/null || true)"
if [ ! -e hooks/commit-msg ]; then
  echo "  ✓ D3 installed hook file removed"; PASS=$((PASS+1))
else
  echo "  ✗ D3 hook file still present"; FAIL=$((FAIL+1))
fi
if [ ! -e .gos/cache/commitlint-hook.json ]; then
  echo "  ✓ D4 backup state file removed"; PASS=$((PASS+1))
else
  echo "  ✗ D4 backup state file still present"; FAIL=$((FAIL+1))
fi
set +e; git commit -q --allow-empty -m "anything goes now" >/dev/null 2>&1; DRC5=$?; set -e
assert_exit "D5 post-teardown commits are no longer linted" 0 "$DRC5"

# --- : prior-value restore + idempotent re-install keeps the ORIGINAL backup
t60_teardown; t60_setup
git init -q . && git commit -q --allow-empty -m "chore: root"
mkdir -p .githooks && printf '#!/bin/sh\nexit 0\n' > .githooks/commit-msg && chmod +x .githooks/commit-msg
git config core.hooksPath .githooks
node "$GOS" setup --commitlint >/dev/null 2>&1
assert_eq "D6 install takes over core.hooksPath" "hooks" "$(git config --get core.hooksPath)"
node "$GOS" setup --commitlint >/dev/null 2>&1
node "$GOS" setup --commitlint --teardown >/dev/null 2>&1
assert_eq "D7 idempotent re-install + teardown restores prior .githooks" ".githooks" "$(git config --get core.hooksPath)"

# --- D8: teardown without install is graceful ---
t60_teardown; t60_setup && git init -q .
set +e; D8OUT=$(node "$GOS" setup --commitlint --teardown 2>&1); D8RC=$?; set -e
assert_exit "D8 teardown without install exits 0 gracefully" 0 "$D8RC"
assert_contains "D8 message says nothing installed" "not installed" "$D8OUT"

# --- A6: install outside a git repository dies (ceiling keeps it a true non-repo) ---
t60_teardown; t60_setup && mkdir -p nogit && cd nogit || exit 1
set +e; NGOUT=$(node "$GOS" setup --commitlint 2>&1); NGRC=$?; set -e
assert_exit "A6 install outside a git repo exits 1" 1 "$NGRC"
assert_contains "A6 error names the git requirement" "git repository" "$NGOUT"
cd "$T60_DIR" || exit 1

# --- E: gos-root layout — hook resolves master config via its own location ---
t60_teardown; t60_setup
git init -q . && git commit -q --allow-empty -m "chore: root"
mkdir -p hooks templates/git
cp "$GOS_ROOT/hooks/commit-msg.sh" hooks/commit-msg && chmod +x hooks/commit-msg
t60_write_cfg templates/git/commitlint.config.yaml
printf 'bad message\n' > badmsg.txt
printf 'feat(core): test\n' > goodmsg.txt
set +e; EOUT=$(sh hooks/commit-msg badmsg.txt 2>&1); ERC=$?; set -e
assert_exit "E1 gos-root layout: master config enforced (exit 1)" 1 "$ERC"
set +e; sh hooks/commit-msg goodmsg.txt >/dev/null 2>&1; ERC2=$?; set -e
assert_exit "E2 gos-root layout: conventional message passes" 0 "$ERC2"

# --- H: offline npx classification via PATH shim
# A shim npx shadows the real one: tool-unrunnable network/registry failures
# (npm ERR! network / ENOTFOUND / ...) fail open — output echoed, exit 0;
# every other non-zero exit (including commitlint validation verdicts)
# propagates — fail-closed bias.
mkdir -p "$T60_DIR/shim-bin"
printf '%s\n' '#!/bin/sh' 'echo "shim-npx: stdout marker"' 'echo "npm ERR! network request to registry failed" >&2' 'exit 3' > "$T60_DIR/shim-bin/npx"
chmod +x "$T60_DIR/shim-bin/npx"
set +e; HOUT=$(PATH="$T60_DIR/shim-bin:$PATH" sh hooks/commit-msg badmsg.txt 2>&1); HRC=$?; set -e
assert_exit "H1 offline npx failure (npm ERR! network) exits 0 (fail-open)" 0 "$HRC"
assert_contains "H2 network-class output echoed verbatim" "npm ERR! network request to registry failed" "$HOUT"
assert_contains "H2 captured stdout echoed too" "shim-npx: stdout marker" "$HOUT"

printf '%s\n' '#!/bin/sh' 'echo "shim-npx: generic tool failure" >&2' 'exit 3' > "$T60_DIR/shim-bin/npx"
chmod +x "$T60_DIR/shim-bin/npx"
set +e; HOUT2=$(PATH="$T60_DIR/shim-bin:$PATH" sh hooks/commit-msg badmsg.txt 2>&1); HRC2=$?; set -e
assert_exit "H3 non-network npx failure propagates (fail-closed, exit 3)" 3 "$HRC2"
assert_contains "H4 propagated failure output visible" "shim-npx: generic tool failure" "$HOUT2"

# H5 (review M2): a forged network token on STDOUT alone must NOT fail the
# hook open. commitlint echoes the commit message on stdout ("⧗ input:
# <subject>"), so a FAILING message containing ENOTFOUND/... could forge the
# network classification when stdout+stderr are captured combined. The hook
# captures them separately and classifies network tokens from STDERR ONLY:
# empty stderr + non-zero rc stays a fail-closed validation failure.
printf '%s\n' '#!/bin/sh' 'echo "⧗ input: feat: forged ENOTFOUND subject"' 'exit 1' > "$T60_DIR/shim-bin/npx"
chmod +x "$T60_DIR/shim-bin/npx"
set +e; HOUT3=$(PATH="$T60_DIR/shim-bin:$PATH" sh hooks/commit-msg badmsg.txt 2>&1); HRC3=$?; set -e
assert_exit "H5 stdout-only network token does NOT fail open (fail-closed, exit 1)" 1 "$HRC3"
assert_contains "H5 forged-stdout failure output still echoed" "ENOTFOUND" "$HOUT3"

# --- G: a committed hooks/ file shows up in git show --stat (wave-commit proxy) ---
git add hooks/commit-msg templates/git/commitlint.config.yaml >/dev/null 2>&1
git commit -q -m "chore: add hook copy" >/dev/null 2>&1
assert_contains "G1 git show --stat carries the hooks/ path" "hooks/commit-msg" "$(git show --stat --format= HEAD)"

# --- F: packaging ships the hook master ---
node -e "const p=require(process.env.GOS_ROOT+'/package.json');console.log(p.files.some(f=>f==='hooks/'||f.startsWith('hooks/'))?'HAS_HOOKS':'MISSING_HOOKS')" > t60f1.txt 2>&1
assert_contains "F1 package.json files array ships hooks/" "HAS_HOOKS" "$(cat t60f1.txt)"
set +e; PACK=$(cd "$GOS_ROOT" && npm pack --dry-run 2>&1); PRC=$?; set -e
assert_exit "F2 npm pack --dry-run exits 0" 0 "$PRC"
assert_contains "F3 tarball listing includes hooks/commit-msg.sh" "hooks/commit-msg.sh" "$PACK"

# F4/F5: both masters carry exactly one `# gos-managed` marker line .
set +e; MC=$(grep -c "gos-managed" "$GOS_ROOT/hooks/commit-msg.sh"); MP=$(grep -c "gos-managed" "$GOS_ROOT/hooks/pre-push.sh"); set -e
assert_eq "F4 commit-msg.sh master is gos-managed (exactly one marker)" "1" "$MC"
assert_eq "F5 pre-push.sh master is gos-managed (exactly one marker)" "1" "$MP"

# --- G: PR-only main discipline (A3 ruling 2026-10-20) — real pushes through
# the installed hook against a bare origin ---
G_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t60g"
mkdir -p "$G_DIR"
git init -q --bare "$G_DIR/origin.git"
mkdir "$G_DIR/work"
cd "$G_DIR/work" || exit 1
git init -q . && git -c user.email=g@t -c user.name=g commit -q --allow-empty -m "chore: root"
set +e; GINST=$(node "$GOS" setup --commitlint 2>&1); GIRC=$?; set -e
assert_exit "G0 hook installed in push sandbox" 0 "$GIRC"
git remote add origin "$G_DIR/origin.git"
set +e; GOUT1=$(git push -q origin HEAD:refs/heads/main 2>&1); GRC1=$?; set -e
assert_exit "G1 bootstrap push creating main is allowed" 0 "$GRC1"
echo more > m.txt && git add m.txt && git -c user.email=g@t -c user.name=g commit -q --no-verify -m "chore: second"
set +e; GOUT2=$(git push -q origin HEAD:refs/heads/main 2>&1); GRC2=$?; set -e
assert_exit "G2 second direct push to main rejected (PR-only)" 1 "$GRC2"
assert_contains "G2 rejection names PR-only" "PR-only" "$GOUT2"
assert_contains "G2 rejection carries the PR path" "pull request" "$GOUT2"
assert_contains "G2 rejection names the emergency escape" "GOS_ALLOW_MAIN_PUSH" "$GOUT2"
set +e; GOUT3=$(GOS_ALLOW_MAIN_PUSH=1 git push -q origin HEAD:refs/heads/main 2>&1); GRC3=$?; set -e
assert_exit "G3 GOS_ALLOW_MAIN_PUSH=1 lands the single commit" 0 "$GRC3"
echo more2 > m2.txt && git add m2.txt && git -c user.email=g@t -c user.name=g commit -q --no-verify -m "chore: third"
echo more3 > m3.txt && git add m3.txt && git -c user.email=g@t -c user.name=g commit -q --no-verify -m "chore: fourth"
set +e; GOUT4=$(GOS_ALLOW_MAIN_PUSH=1 git push -q origin HEAD:refs/heads/main 2>&1); GRC4=$?; set -e
assert_exit "G4 escape hatch still enforces 1-commit discipline" 1 "$GRC4"
set +e; GOUT5=$(git push -q origin HEAD:refs/heads/feature-x 2>&1); GRC5=$?; set -e
assert_exit "G5 feature-branch pushes are unguarded" 0 "$GRC5"
cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$G_DIR"

# G6: CI carries the direct-push alarm (committer must be GitHub = PR merges only)
set +e; GA=$(grep -c 'Direct push discipline' "$GOS_ROOT/.github/workflows/ci.yml"); GB=$(grep -c "github.event_name == 'push' && github.ref == 'refs/heads/main'" "$GOS_ROOT/.github/workflows/ci.yml"); GC=$(grep -c '%cn' "$GOS_ROOT/.github/workflows/ci.yml"); set -e
if [ "$GA" -ge 1 ] && [ "$GB" -ge 1 ] && [ "$GC" -ge 1 ]; then
  echo "  ✓ G6 CI direct-push alarm job present (push+main gate, committer check)"; PASS=$((PASS+1))
else
  echo "  ✗ G6 CI direct-push alarm job missing"; FAIL=$((FAIL+1))
fi

echo "--- T60 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
