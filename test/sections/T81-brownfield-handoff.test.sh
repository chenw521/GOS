#!/usr/bin/env bash
# gos-map:cmd brownfield
# gos-map:fn bin/lib/ops/brownfield.cjs#fn:cmdBrownfield,bin/lib/ops/brownfield.cjs#fn:bfParseFlags,bin/lib/ops/brownfield.cjs#fn:bfRun,bin/lib/ops/brownfield.cjs#fn:bfRenderHuman
# : brownfield handoff + skeleton + locales ( , ).
# Seven case groups:
# (1) handoff block at report end — map preview line points at the single
# trigger (`gos init <level>`, ), no map is ever run (.gos/codebase
#     and .gos/cache/deps.json absent); per-platform link rows via
#     detectPlatforms under fake HOMEs (linked -> ok, unlinked -> missing,
# nothing detected -> none-detected row, ) + frozen --no-onboard
#     remediation argv in the --json envelope;
# (2) --print-agents-skeleton — exit 0, skeleton on stdout with
#     intro/build/test/conventions placeholders ONLY; no routing block, no
# /level presets, no slash-command content; sandbox tree
#     unchanged including no .gos/ creation; --json envelope carries it;
#     combined with --overwrite it dies;
# (3) locale catalog discipline — `brownfield.` key-line counts en == zh and
# >= 15; en/zh brownfield key sets identical ( same batch);
# (4) locale render — GOS_LANG=zh-CN renders handoff + skeleton in Chinese;
#     unset / explicit en stays English (no zh leak);
# (5) i18n inventory check green;
# (6) prompt-free module grep — no ask( / onboarding / stdin reach in
# (7) regression still green (embedded run, zero failing assertions);
# (8) review m12/OT-5 — the printed `gos setup --no-onboard` remediation
#     EXECUTED under a sandbox fake HOME: skills link, zero AGENTS.md writes.
# Env: GOS (CLI path), GOS_ROOT, TESTBASE (sandbox base), assert helpers sourced by runner
T81_DIR=""

t81_setup() {
  T81_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t81"
  mkdir -p "$T81_DIR" || exit 1
  cd "$T81_DIR" || exit 1
}

t81_repo() {  # fresh git repo at $T81_DIR/<name>
  mkdir -p "$T81_DIR/$1"
  git init -q -b main "$T81_DIR/$1" || exit 1
}

# HOME-controlled runs: GOS_LANG + OPENCODE_CONFIG_DIR stripped for probe
# determinism (detectPlatforms honors both); T81_ENV re-injects GOS_LANG.
t81_run() {  # t81_run <repo> <home> [args...] -> human output in $OUT (stdout+stderr), rc in $RC
  local repo="$1" home="$2"; shift 2
  OUT=$( cd "$T81_DIR/$repo" && env -u GOS_LANG -u OPENCODE_CONFIG_DIR HOME="$home" ${T81_ENV:-} node "$GOS" brownfield "$@" 2>&1 ); RC=$?
}

t81_json() {  # stdout ONLY in $OUT (stderr to file), rc in $RC
  local repo="$1" home="$2"; shift 2
  OUT=$( cd "$T81_DIR/$repo" && env -u GOS_LANG -u OPENCODE_CONFIG_DIR HOME="$home" ${T81_ENV:-} node "$GOS" brownfield "$@" 2>"$T81_DIR/stderr.txt" ); RC=$?
}

t81_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T81_DIR"; }

t81_setup
echo "--- T81: brownfield handoff + skeleton + locales ---"

HOME_OC="$T81_DIR/home-oc"          # opencode platform present, links absent
HOME_LINKED="$T81_DIR/home-linked"  # opencode platform present, skills link ok
HOME_NONE="$T81_DIR/home-none"      # nothing detectable
HOME_CODEX="$T81_DIR/home-codex"    # codex platform present (.agents), link absent
mkdir -p "$HOME_OC/.config/opencode" "$HOME_LINKED/.config/opencode/skills/gos" "$HOME_NONE" "$HOME_CODEX/.agents"

# --- G1: handoff — map preview line + platform rows at report end
t81_repo g1
t81_run g1 "$HOME_OC"
assert_exit "G1a handoff run exits 0" 0 "$RC"
assert_contains "G1b map preview names the init trigger + level hint" "gos init <level>" "$OUT"
assert_contains "G1c preview line states the single-trigger rule" "single trigger" "$OUT"
ASSETS_N=$(printf '%s\n' "$OUT" | grep -n '^assets:' | head -1 | cut -d: -f1)
HANDOFF_N=$(printf '%s\n' "$OUT" | grep -n '^next steps:' | head -1 | cut -d: -f1)
PREVIEW_N=$(printf '%s\n' "$OUT" | grep -n 'gos init <level>' | head -1 | cut -d: -f1)
if [ -n "$ASSETS_N" ] && [ -n "$HANDOFF_N" ] && [ -n "$PREVIEW_N" ] && [ "$HANDOFF_N" -gt "$ASSETS_N" ] && [ "$PREVIEW_N" -gt "$HANDOFF_N" ]; then
  echo "  ✓ G1d handoff block at report end (preview inside the trailing block)"; PASS=$((PASS+1))
else
  echo "  ✗ G1d handoff block at report end (assets=$ASSETS_N handoff=$HANDOFF_N preview=$PREVIEW_N)"; FAIL=$((FAIL+1))
fi
assert_contains "G1e platform row rendered for opencode" "opencode:" "$OUT"
assert_contains "G1f unlinked platform reported missing" "opencode-commands: missing" "$OUT"
assert_contains "G1g remediation names the wizard-free setup argv" "gos setup --no-onboard" "$OUT"
TAIL8=$(printf '%s\n' "$OUT" | grep -v '^[[:space:]]*$' | tail -8)
assert_contains "G1h closing block carries the remediation line" "gos setup --no-onboard" "$TAIL8"
if [ -e "$T81_DIR/g1/.gos/codebase" ]; then
  echo "  ✗ G1i codebase map must not run (D-90 preview only)"; FAIL=$((FAIL+1))
else echo "  ✓ G1i no .gos/codebase (D-90: preview only, never triggered)"; PASS=$((PASS+1)); fi
if [ -e "$T81_DIR/g1/.gos/cache/deps.json" ]; then
  echo "  ✗ G1j deps.json must not be written by adoption"; FAIL=$((FAIL+1))
else echo "  ✓ G1j no .gos/cache/deps.json written"; PASS=$((PASS+1)); fi

t81_run g1 "$HOME_LINKED"
assert_contains "G1k linked platform reports ok" "opencode: ok" "$OUT"
assert_contains "G1l missing sibling platform still reported" "opencode-commands: missing" "$OUT"
t81_run g1 "$HOME_CODEX"
assert_contains "G1m codex platform row reported" "codex: missing" "$OUT"
t81_run g1 "$HOME_NONE"
assert_contains "G1n no-platform row rendered" "none detected" "$OUT"
assert_contains "G1o no-platform row carries the same remediation" "gos setup --no-onboard" "$OUT"

t81_json g1 "$HOME_OC" --json
printf '%s' "$OUT" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
h=d.get('handoff'); assert isinstance(h,dict), 'handoff missing from json report'
assert h.get('map_trigger')==['gos','init','<level>'], h.get('map_trigger')
plats=h.get('platforms'); assert isinstance(plats,list) and len(plats)>=1, plats
assert all(p.get('status') in ('ok','missing') for p in plats), plats
assert any(p.get('name')=='opencode' for p in plats), plats
assert h.get('platform_remediation')==['gos','setup','--no-onboard'], h.get('platform_remediation')
print('ok')" ; assert_exit "G1p json handoff: map_trigger argv + platform rows + frozen remediation argv" 0 "$?"

# --- G2: --print-agents-skeleton — stdout-only skeleton, zero repo mutation
t81_repo skel
SNAP_A=$( cd "$T81_DIR/skel" && find . -name .git -prune -o -print | sort )
t81_json skel "$HOME_NONE" --print-agents-skeleton
assert_exit "G2a --print-agents-skeleton exits 0" 0 "$RC"
assert_contains "G2b intro placeholder present" "Introduction" "$OUT"
assert_contains "G2c build placeholder present" "## Build" "$OUT"
assert_contains "G2d test placeholder present" "## Test" "$OUT"
assert_contains "G2e conventions placeholder present" "## Conventions" "$OUT"
G2_BANNED=0
for BANNED in 'GOS Routing' 'Lv0' 'Lv1' 'Lv2' 'Lv3' 'Lv4' '/gos'; do
  if printf '%s\n' "$OUT" | grep -q -- "$BANNED"; then
    echo "  ✗ G2f skeleton must not contain '$BANNED' (no presets, no routing block)"; FAIL=$((FAIL+1)); G2_BANNED=1
  fi
done
[ "$G2_BANNED" -eq 0 ] && { echo "  ✓ G2f no routing block / level presets / slash-command content"; PASS=$((PASS+1)); }
SNAP_B=$( cd "$T81_DIR/skel" && find . -name .git -prune -o -print | sort )
assert_eq "G2g sandbox tree unchanged (stdout only; no .gos/ creation)" "$SNAP_A" "$SNAP_B"
t81_run skel "$HOME_NONE" --print-agents-skeleton
assert_exit "G2h human mode exits 0" 0 "$RC"
assert_contains "G2i stdout-only note on stderr" "stdout only" "$OUT"
t81_json skel "$HOME_NONE" --print-agents-skeleton --json
printf '%s' "$OUT" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
assert isinstance(d,dict) and '## Build' in d.get('skeleton',''), d.keys()
print('ok')" ; assert_exit "G2j --json envelope carries the skeleton (one JSON object)" 0 "$?"
t81_run skel "$HOME_NONE" --print-agents-skeleton --overwrite
assert_exit "G2k combining with --overwrite dies (generic fatal)" 1 "$RC"
assert_contains "G2l combo refusal explains alone-usage" "alone" "$OUT"
SNAP_C=$( cd "$T81_DIR/skel" && find . -name .git -prune -o -print | sort )
assert_eq "G2m refused combo still writes nothing" "$SNAP_A" "$SNAP_C"

# --- G3: locale catalog discipline ( en canonical + zh same batch)
EN_LOC="$GOS_ROOT/bin/lib/core/locales/en.cjs"
ZH_LOC="$GOS_ROOT/bin/lib/core/locales/zh.cjs"
EN_N=$(grep -c "brownfield\." "$EN_LOC" || true)
ZH_N=$(grep -c "brownfield\." "$ZH_LOC" || true)
if [ "${EN_N:-0}" -ge 15 ]; then
  echo "  ✓ G3a en catalog carries >= 15 brownfield key lines ($EN_N)"; PASS=$((PASS+1))
else
  echo "  ✗ G3a en catalog has only ${EN_N:-0} brownfield key lines (want >= 15)"; FAIL=$((FAIL+1))
fi
assert_eq "G3b zh key-line count equals en (same batch)" "$EN_N" "$ZH_N"
OUT=$(node -e '
const en = require(process.env.GOS_ROOT + "/bin/lib/core/locales/en.cjs");
const zh = require(process.env.GOS_ROOT + "/bin/lib/core/locales/zh.cjs");
const ek = Object.keys(en).filter((k) => k.startsWith("brownfield."));
const zk = Object.keys(zh).filter((k) => k.startsWith("brownfield."));
const miss = ek.filter((k) => !(k in zh));
const extra = zk.filter((k) => !(k in en));
if (!ek.length || miss.length || extra.length) {
  console.error("missing zh: [" + miss.join(", ") + "] extra zh: [" + extra.join(", ") + "]");
  process.exit(1);
}
console.log("bf-parity-clean:" + ek.length);
' 2>&1); RC=$?
assert_exit "G3c en/zh brownfield key sets identical" 0 "$RC"
assert_contains "G3c parity marker" "bf-parity-clean" "$OUT"

# --- G4: locale render — zh via GOS_LANG, en default without it ---
T81_ENV="GOS_LANG=zh-CN"
t81_run g1 "$HOME_NONE"
assert_contains "G4a zh handoff header" "下一步" "$OUT"
assert_contains "G4b zh no-platform row" "未检测到任何 AI 平台" "$OUT"
t81_run skel "$HOME_NONE" --print-agents-skeleton
assert_contains "G4c zh skeleton build section" "## 构建" "$OUT"
if printf '%s\n' "$OUT" | grep -q 'Lv[0-4]'; then
  echo "  ✗ G4d zh skeleton must not carry level presets"; FAIL=$((FAIL+1))
else echo "  ✓ G4d zh skeleton free of level presets"; PASS=$((PASS+1)); fi
T81_ENV=""
t81_run g1 "$HOME_OC"
assert_contains "G4e unset locale stays English (title)" "adoption report" "$OUT"
assert_contains "G4f unset locale handoff header English" "next steps:" "$OUT"
if printf '%s\n' "$OUT" | grep -q '接管'; then
  echo "  ✗ G4g zh leak under unset locale"; FAIL=$((FAIL+1))
else echo "  ✓ G4g no zh leak under unset locale"; PASS=$((PASS+1)); fi
T81_ENV="GOS_LANG=en"
t81_run g1 "$HOME_OC"
assert_contains "G4h explicit en stays English" "next steps:" "$OUT"
T81_ENV=""

# --- G5: i18n inventory check stays green ---
OUT=$(bash "$GOS_ROOT/test/checks/i18n-inventory.sh" 2>&1); RC=$?
assert_exit "G5 i18n inventory check green" 0 "$RC"

# --- G6: prompt-free module check
if grep -q 'ask(' "$GOS_ROOT/bin/lib/ops/brownfield.cjs"; then
  echo "  ✗ G6a brownfield.cjs reaches an interactive primitive (ask("; FAIL=$((FAIL+1))
else echo "  ✓ G6a no interactive primitive in brownfield.cjs"; PASS=$((PASS+1)); fi
if grep -Eq 'onboarding|process\.stdin' "$GOS_ROOT/bin/lib/ops/brownfield.cjs"; then
  echo "  ✗ G6b brownfield.cjs imports onboarding or reads stdin"; FAIL=$((FAIL+1))
else echo "  ✓ G6b no onboarding import, no stdin read"; PASS=$((PASS+1)); fi

# --- G7: regression still green (embedded; output captured so the
# runner's ✓/✗ counting is not double-fed) ---
T80OUT=$(bash "$GOS_ROOT/test/sections/T80-brownfield-adopt.test.sh" 2>&1); T80RC=$?
assert_exit "G7a embedded T80 section completes" 0 "$T80RC"
T80F=$(printf '%s\n' "$T80OUT" | grep -c '^  ✗' || true)
assert_eq "G7b T80 regression zero failing assertions" "0" "${T80F:-0}"
assert_contains "G7c T80 section reaches its done marker" "T80 done" "$T80OUT"

# --- G8 (review m12 / OT-5): EXECUTE the printed platform remediation
# (`gos setup --no-onboard`) in a sandbox fake HOME — it links skills and
# must NEVER write AGENTS.md anywhere (host HOME or the repo) ---
t81_repo rem
HOME_REM="$T81_DIR/home-remediation"
mkdir -p "$HOME_REM/.config/opencode"   # pre-create so opencode is detectable
set +e
OUT=$( cd "$T81_DIR/rem" && env -u GOS_LANG -u OPENCODE_CONFIG_DIR HOME="$HOME_REM" node "$GOS" setup --no-onboard 2>&1 ); RC=$?
set -e
assert_exit "G8a executed remediation (gos setup --no-onboard) exits 0" 0 "$RC"
assert_file "G8b remediation linked skills under the sandbox HOME (did its job)" "$HOME_REM/.config/opencode/skills/gos"
if [ ! -e "$HOME_REM/AGENTS.md" ]; then
  echo "  ✓ G8c no AGENTS.md written to the (sandbox) HOME (OT-5)"; PASS=$((PASS+1))
else echo "  ✗ G8c remediation must never write AGENTS.md to HOME"; FAIL=$((FAIL+1)); fi
if [ ! -e "$T81_DIR/rem/AGENTS.md" ]; then
  echo "  ✓ G8d no AGENTS.md written into the repo"; PASS=$((PASS+1))
else echo "  ✗ G8d remediation must not create AGENTS.md in the repo"; FAIL=$((FAIL+1)); fi

t81_teardown
echo "--- T81 done ---"
