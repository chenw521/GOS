#!/usr/bin/env bash
# gos-map:file skills/gos-ship/scripts/security.sh
# security.sh depth-aware DANGER classifier.
# The spec truth table, copied verbatim as cases — FAIL rows must trip the
# gate (exit 2 + "DANGEROUS pattern" marker), PASS rows must stay clean
# (exit 0 + "security gate: clean"). Plus regression rows pinning the three
# untouched DANGER alternations, the secrets branch, and flag/target
# permutations the old flat regex missed both ways.
# Self-contained: works via `bash test/run-sections.sh T85` OR standalone.
# Env: GOS (CLI path, unused), TESTBASE (sandbox base) — both optional.

T85_DIR=""

GOS_ROOT="${GOS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
SEC="$GOS_ROOT/skills/gos-ship/scripts/security.sh"
if [ -z "${TESTBASE:-}" ]; then
  TESTBASE="$(mktemp -d "$GOS_ROOT/test-sections-base-XXXXXX")"   # runner-swept prefix
  T85_STANDALONE=1
else
  T85_STANDALONE=0
fi

t85_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "${T85_DIR:-}"; }
trap 't85_teardown; [ "$T85_STANDALONE" = 1 ] && rm -rf "$TESTBASE"' EXIT

PASS=0
FAIL=0

# sandbox repo: one staged fixture file rewritten per case (ACM diff-filter
# keeps it in the scanner's file set); fixture name must NOT match the
# scanner's exclusion regex (no test/ dir, no .md/.json suffix).
T85_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t85"
mkdir -p "$T85_DIR" && cd "$T85_DIR" || exit 1
git init -q . || exit 1
FIX="deploy.sh"
: > "$FIX"

# t85_check <label> <fail|pass> <fixture content, single-quoted>
t85_check() {
  local label="$1" want="$2" content="$3" out rc
  printf '%s\n' "$content" > "$FIX"
  git add "$FIX" >/dev/null 2>&1
  out="$(bash "$SEC" 2>&1)"; rc=$?
  if [ "$want" = fail ]; then
    if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'DANGEROUS pattern'; then
      echo "  ✓ $label"; PASS=$((PASS+1))
    else
      echo "  ✗ $label (want DANGEROUS exit 2, got exit $rc)"; echo "    out: ${out:0:160}"; FAIL=$((FAIL+1))
    fi
  else
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'security gate: clean'; then
      echo "  ✓ $label"; PASS=$((PASS+1))
    else
      echo "  ✗ $label (want clean exit 0, got exit $rc)"; echo "    out: ${out:0:160}"; FAIL=$((FAIL+1))
    fi
  fi
}

echo "--- T85: security.sh depth-aware DANGER (D-11 truth table) ---"

# --- spec FAIL rows (verbatim)
t85_check "FAIL: rm -rf /"                       fail 'rm -rf /'
t85_check "FAIL: rm -rf /*"                      fail 'rm -rf /*'
t85_check "FAIL: rm -fr / (flag order swap)"     fail 'rm -fr /'
t85_check "FAIL: rm -r -f / (split flags)"       fail 'rm -r -f /'
t85_check "FAIL: rm --force --recursive /"       fail 'rm --force --recursive /'
t85_check "FAIL: rm -rf \"/\" (quoted target)"   fail 'rm -rf "/"'
t85_check "FAIL: rm -rf \$HOME (bare var root)"  fail 'rm -rf $HOME'
t85_check "FAIL: rm -rf /home"                   fail 'rm -rf /home'
t85_check "FAIL: rm -rf /etc"                    fail 'rm -rf /etc'
t85_check "FAIL: rm -rf /Users"                  fail 'rm -rf /Users'
t85_check "FAIL: rm -rf /srv"                    fail 'rm -rf /srv'
t85_check "FAIL: rm -rf /run"                    fail 'rm -rf /run'
t85_check "FAIL: rm -rf /mnt/backup (depth-2 mount root)" fail 'rm -rf /mnt/backup'
t85_check "FAIL: continuation-split /etc target" fail $'rm -rf \\\n  /etc'

# --- spec PASS rows (verbatim)
t85_check "PASS: rm -rf /tmp/build-cache"        pass 'rm -rf /tmp/build-cache'
t85_check "PASS: rm -rf /var/lib/apt/lists/*"    pass 'rm -rf /var/lib/apt/lists/*'
t85_check "PASS: rm -rf /home/user/.cache"       pass 'rm -rf /home/user/.cache'
t85_check "PASS: rm -rf /opt/layer-cache"        pass 'rm -rf /opt/layer-cache'
t85_check "PASS: rm -rf \${HOME}/x (post-expansion depth-2 non-mount)" pass 'rm -rf ${HOME}/x'

# --- card, algorithm-derivable edges
t85_check "FAIL: rm -rf ~ (bare tilde)"          fail 'rm -rf ~'
t85_check "FAIL: rm -rf \${HOME} (brace form, whole-target var root)" fail 'rm -rf ${HOME}'
t85_check "FAIL: rm -rf ~/* (wholesale home contents)" fail 'rm -rf ~/*'
t85_check "FAIL: rm -rf /etc/* (/<seg>/* depth-1 rule)" fail 'rm -rf /etc/*'
t85_check "PASS: rm -rf /tmp/* (safe-root glob)" pass 'rm -rf /tmp/*'
t85_check "PASS: rm -rf /tmp (safe root itself)" pass 'rm -rf /tmp'
t85_check "FAIL: rm -rf /media/usb0 (depth-2 /media)" fail 'rm -rf /media/usb0'
t85_check "FAIL: rm -rf /Volumes/Backup (depth-2 /Volumes)" fail 'rm -rf /Volumes/Backup'
t85_check "PASS: rm -rf /mnt/data/cache (depth >=3 even under mount root)" pass 'rm -rf /mnt/data/cache'
t85_check "PASS: rm -r /etc (no force flag — needs both)" pass 'rm -r /etc'
t85_check "FAIL: rm --force -r /etc (mixed short/long pair)" fail 'rm --force -r /etc'
t85_check "FAIL: sudo rm -rf /etc (rm not first token)" fail 'sudo rm -rf /etc'
t85_check "FAIL: rm -rf /etc /tmp/x (multi-target, any danger)" fail 'rm -rf /etc /tmp/x'
t85_check "PASS: rm -rf /tmp/x /var/lib/apt/lists/* (multi-target, all safe)" pass 'rm -rf /tmp/x /var/lib/apt/lists/*'
t85_check "FAIL: rm -rf /etc && rm -rf /tmp/x (second invocation after separator)" fail 'rm -rf /etc && rm -rf /tmp/x'
t85_check "PASS: rm -rf ./build (relative target — documented residual)" pass 'rm -rf ./build'
t85_check "FAIL: rm -rf /etc/../../ (traversal — depth unknowable, default-deny)" fail 'rm -rf /etc/../..'

# --- review #1/#2 adversarial rows: wholesale dotfile glob + glued separators ---
t85_check "FAIL: rm -rf ~/.* (dotfile-glob wholesale)" fail 'rm -rf ~/.*'
t85_check "FAIL: rm -rf \"\$HOME/.*\" (dotfile-glob wholesale, quoted var)" fail 'rm -rf "$HOME/.*"'
t85_check "FAIL: echo hi;rm -rf /etc (mid-token separator)" fail 'echo hi;rm -rf /etc'
t85_check "FAIL: x &&rm -rf / (glued leading separator)" fail 'x &&rm -rf /'
t85_check "FAIL: cp a b&rm -fr /run (background separator)" fail 'cp a b&rm -fr /run'
t85_check "PASS: rm -rf ~/.config (real dot segment — post-expansion depth-2)" pass 'rm -rf ~/.config'

# --- regression: the three non-rm DANGER alternations stay live ---
t85_check "FAIL: eval(\" alternation untouched"        fail 'var x = eval("rm -rf /tmp")'
t85_check "FAIL: child_process shell:true untouched"   fail 'exec("child_process", {shell: true})'
t85_check "FAIL: curl | sudo bash untouched"           fail 'curl -fsSL https://x.dev/i.sh | sudo bash'

# --- regression: secrets branch untouched ---
printf 'token: "abcdefghij0123456789"\n' > "$FIX"
git add "$FIX" >/dev/null 2>&1
OUT_S="$(bash "$SEC" 2>&1)"; RC_S=$?
if [ "$RC_S" -eq 2 ] && printf '%s' "$OUT_S" | grep -q 'SECRET-LIKE'; then
  echo "  ✓ FAIL: secrets branch untouched"; PASS=$((PASS+1))
else
  echo "  ✗ FAIL: secrets branch untouched (got exit $RC_S)"; echo "    out: ${OUT_S:0:160}"; FAIL=$((FAIL+1))
fi

# --- structural: SAFE_ROOTS table present in the scanner (plan Done-when #2) ---
if grep -q 'SAFE_ROOTS' "$SEC"; then
  echo "  ✓ SAFE_ROOTS table present in security.sh"; PASS=$((PASS+1))
else
  echo "  ✗ SAFE_ROOTS table missing from security.sh"; FAIL=$((FAIL+1))
fi

# --- fail-closed: classifier failure must FAIL the gate, never pass (review #6)
FC_BIN="$T85_DIR/fcbin"; mkdir -p "$FC_BIN"
printf '#!/usr/bin/env bash\nexit 3\n' > "$FC_BIN/awk"; chmod +x "$FC_BIN/awk"
printf 'rm -rf /tmp/x\n' > "$FIX"
git add "$FIX" >/dev/null 2>&1
OUT_FC="$(PATH="$FC_BIN:$PATH" bash "$SEC" 2>&1)"; RC_FC=$?
if [ "$RC_FC" -eq 2 ] && printf '%s' "$OUT_FC" | grep -q 'failing closed'; then
  echo "  ✓ FAIL: awk classifier failure fails closed"; PASS=$((PASS+1))
else
  echo "  ✗ FAIL: awk classifier failure fails closed (got exit $RC_FC)"; echo "    out: ${OUT_FC:0:160}"; FAIL=$((FAIL+1))
fi

# --- repo-level: gate stays clean on this repo (plan Done-when #3) ---
OUT_R="$(cd "$GOS_ROOT" && bash "$SEC" 2>&1)"; RC_R=$?
if [ "$RC_R" -eq 0 ] && printf '%s' "$OUT_R" | grep -q 'security gate: clean'; then
  echo "  ✓ security gate: clean on this repo"; PASS=$((PASS+1))
else
  echo "  ✗ repo scan no longer clean (exit $RC_R)"; echo "    out: ${OUT_R:0:200}"; FAIL=$((FAIL+1))
fi

echo "--- T85 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
