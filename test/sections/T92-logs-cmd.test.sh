#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/gate.cjs#fn:cmdLogs bin/lib/ops/gate.cjs#fn:readExemptions bin/lib/knowledge/truth.cjs#fn:appendTruthReceipt
# gos-map:cmd help,truth,gate,_contract
# : logs presentation ( ) — write-side enrichment + `gos logs` view.
# Facts asserted:
#   - receipts carry the truth text: `<iso8601> <id> replay-verified: <cmd> :: <truth text (first 80cp)>`
#     and the verify echo names the registry rel path (.gos/logs/truth-receipts.md)
#   - gate --exempt --reason is MANDATORY (>=10 codepoints after sanitization);
#     exemption line grammar `<iso8601> <section> :: <reason>` (single line, no #)
#   - readExemptions reads FIELD 2; enriched lines round-trip through the
#     one-shot reader (exempt honored by checkManifest, consumed at commit)
#   - gos logs <receipts|exemptions|audit> [--last N] renders formatted tables
#     (default last 20); gos help renders the logs row; dispatch class READ
# Standalone-safe: self-provisions env when not run under test/run-sections.sh.

T92_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T92_STANDALONE=1
  T92_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T92_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T92_SELFROOT"
  export TESTBASE="$(mktemp -d "$T92_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T92_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t92"
mkdir -p "$T92_DIR" && cd "$T92_DIR" || exit 1

t92_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T92_DIR"
  if [ "$T92_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t92_teardown EXIT

PASS=0
FAIL=0

echo "--- T92: logs presentation (D-02/R-35) ---"

# --- L1: dispatch wiring — logs = READ-class across every wiring point ---
R1=$(node -e '
const rc = require(process.env.GOS_ROOT + "/bin/lib/nav/registry-consts.cjs");
const state = require(process.env.GOS_ROOT + "/bin/lib/core/state.cjs");
const bad = [];
if (!rc.KNOWN_CASES.includes("logs")) bad.push("logs absent from KNOWN_CASES");
if (!rc.READ_CMDS.has("logs")) bad.push("logs not in READ_CMDS");
if (rc.WRITE_CMDS.has("logs")) bad.push("logs wrongly in WRITE_CMDS");
if (rc.EXEC_CMDS.has("logs")) bad.push("logs wrongly in EXEC_CMDS");
if (rc.GLOBAL_CMDS.has("logs")) bad.push("logs wrongly in GLOBAL_CMDS");
const e = state.COMMANDS.logs;
if (!e) bad.push("logs entry missing from COMMANDS");
else {
  if (e.class !== "read") bad.push("COMMANDS.logs class=" + e.class);
  if (e.core) bad.push("logs must stay outside the core set (D-20)");
  if (!e.usage || !e.usage.includes("--last")) bad.push("usage missing --last");
}
const coreN = Object.values(state.COMMANDS).filter((x) => x.core).length;
if (coreN > 10) bad.push("core set " + coreN + " > 10");
if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
console.log("OK");
' 2>&1)
if [ "$R1" = "OK" ]; then
  echo "  ✓ L1 wiring: KNOWN_CASES + READ_CMDS + COMMANDS(read, non-core) + core<=10"; PASS=$((PASS+1))
else
  echo "  ✗ L1 wiring: $R1"; FAIL=$((FAIL+1))
fi

# --- L2: help surfaces — index row + detail page (registry self-check stays green) ---
node "$GOS" help > t92-help.txt 2>&1; HELP_RC=$?
L2_OK=1
[ "$HELP_RC" -ne 0 ] && L2_OK=0
grep -qE '^  logs[[:space:]]+\S' t92-help.txt || L2_OK=0
node "$GOS" help logs > t92-detail.txt 2>&1 || L2_OK=0
grep -qF 'gos logs <receipts|exemptions|audit> [--last N]' t92-detail.txt || L2_OK=0
if [ "$L2_OK" -eq 1 ]; then
  echo "  ✓ L2 help: index logs row + detail usage verbatim"; PASS=$((PASS+1))
else
  echo "  ✗ L2 help surfaces (rc=$HELP_RC)"; FAIL=$((FAIL+1))
fi

# --- sandbox: an initialized task for truth/ledger writes ---
git init -q . && git commit -q --allow-empty -m t92-seed
node "$GOS" init 1 "t92 logs presentation" >/dev/null 2>&1
mkdir -p .gos/logs .gos/cache
printf '.gos/logs/\n' >> .gitignore
git add -A >/dev/null 2>&1 && git commit -qm t92-base >/dev/null 2>&1

# --- L3: receipts enrichment + echo path fixed to registry rel ---
node "$GOS" truth add "counts files from stdout fixture" >/dev/null 2>&1
node "$GOS" truth add "long description truth line feeding the eighty codepoint clip assertion of the receipts view" >/dev/null 2>&1
touch art.txt   # evidence artifact must exist at verify time (validateEvidenceObject)
node "$GOS" truth verify T1 --replay --command '["node","-e","console.log(\"7 files listed\")"]' --artifact art.txt > t92-echo.txt 2>&1; E1=$?
node "$GOS" truth verify T2 --replay --command '["node","-e","console.log(\"total 165\")"]' --artifact art.txt >/dev/null 2>&1; E2=$?
L3=$(python3 - <<'PYEOF'
import json, re, sys
rc = open('.gos/logs/truth-receipts.md', encoding='utf-8').read().strip().split('\n')
bad = []
if len(rc) != 2:
    bad.append('receipt line count=%d' % len(rc)); print('BAD ' + '; '.join(bad)); raise SystemExit
m = re.match(r'^(\d{4}-\d{2}-\d{2}T[0-9:.]+Z) (T1) replay-verified: (\[.*\]) :: (.+)$', rc[0])
if not m: bad.append('T1 line grammar miss: %r' % rc[0][:90])
else:
    if not m.group(3).startswith('["node"'): bad.append('cmd not JSON argv')
    if m.group(4) != 'counts files from stdout fixture': bad.append('truth text=%r' % m.group(4))
m2 = re.match(r'^(\d{4}-\d{2}-\d{2}T[0-9:.]+Z) (T2) replay-verified: (\[.*\]) :: (.+)$', rc[1])
if not m2: bad.append('T2 line grammar miss: %r' % rc[1][:90])
else:
    if len(m2.group(4)) != 80: bad.append('clip len=%d (expect 80)' % len(m2.group(4)))
    if not m2.group(4).startswith('long description truth'): bad.append('clip start=%r' % m2.group(4)[:20])
print('BAD ' + '; '.join(bad) if bad else 'OK')
PYEOF
)
if [ "$E1" -eq 0 ] && [ "$E2" -eq 0 ] && [ "$L3" = "OK" ] && grep -qF '.gos/logs/truth-receipts.md' t92-echo.txt; then
  echo "  ✓ L3 receipts: <iso> <id> replay-verified: <cmd> :: <truth 80cp> + echo names registry rel"; PASS=$((PASS+1))
else
  echo "  ✗ L3 receipts: e1=$E1 e2=$E2 parse=$L3 echo=$(grep -c 'truth-receipts' t92-echo.txt)"; FAIL=$((FAIL+1))
fi

# --- L4: gos logs receipts — formatted table, --last N, default 20 ---
node "$GOS" logs receipts > t92-rec-all.txt 2>&1; RALL=$?
node "$GOS" logs receipts --last 1 > t92-rec-1.txt 2>&1; R1L=$?
L4_OK=1
[ "$RALL" -ne 0 ] && L4_OK=0
[ "$R1L" -ne 0 ] && L4_OK=0
# --last 1 = ONLY the newest entry ( : long description, command echoes "total 165")
grep -qF 'total 165' t92-rec-1.txt || L4_OK=0
grep -qE 'T2[[:space:]]' t92-rec-1.txt || L4_OK=0
grep -qF 'long description truth' t92-rec-1.txt || L4_OK=0
if grep -qE 'T1[[:space:]]' t92-rec-1.txt || grep -qF 'counts files from stdout fixture' t92-rec-1.txt; then L4_OK=0; fi
grep -qF 'counts files from stdout fixture' t92-rec-all.txt || L4_OK=0   # default shows both
grep -qF 'showing last' t92-rec-all.txt || L4_OK=0
set +e
node "$GOS" logs receipts --last 0 >/dev/null 2>&1; RL0=$?
node "$GOS" logs receipts --last x >/dev/null 2>&1; RLX=$?
node "$GOS" logs bogus >/dev/null 2>&1; RB=$?
node "$GOS" logs >/dev/null 2>&1; RNONE=$?
node "$GOS" logs receipts --bogus >/dev/null 2>&1; RBF=$?

[ "$RL0" -ne 0 ] && [ "$RLX" -ne 0 ] && [ "$RB" -ne 0 ] && [ "$RNONE" -ne 0 ] && [ "$RBF" -ne 0 ] || L4_OK=0
if [ "$L4_OK" -eq 1 ]; then
  echo "  ✓ L4 logs receipts: table + truth text + --last N + fail-closed usage"; PASS=$((PASS+1))
else
  echo "  ✗ L4 logs receipts (all=$RALL last1=$R1L, usage rc: 0=$RL0 x=$RLX bogus=$RB none=$RNONE flag=$RBF)"; FAIL=$((FAIL+1))
fi

# --- L5: gate --exempt --reason mandatory, >=10cp, line grammar pinned ---
set +e
node "$GOS" gate --exempt T92-noreason >/dev/null 2>&1; XNR=$?
node "$GOS" gate --exempt T92-short --reason "short" >/dev/null 2>&1; XSH=$?
node "$GOS" gate --exempt T92-missing --reason >/dev/null 2>&1; XMV=$?
node "$GOS" gate --exempt T92-sec --reason "flaky section parked pending upstream fix" > t92-exempt.txt 2>&1; XOK=$?

L5=0
if [ "$XNR" -ne 0 ] && [ "$XSH" -ne 0 ] && [ "$XMV" -ne 0 ] && [ "$XOK" -eq 0 ]; then L5=1; fi
if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z T92-sec :: flaky section parked pending upstream fix$' .gos/logs/exemptions.log 2>/dev/null; then :; else L5=0; fi
if [ "$L5" -eq 1 ]; then
  echo "  ✓ L5 gate --exempt: --reason mandatory (>=10cp), grammar <iso> <section> :: <reason>"; PASS=$((PASS+1))
else
  echo "  ✗ L5 gate --exempt: noreason=$XNR short=$XSH missing=$XMV ok=$XOK line=$(cat .gos/logs/exemptions.log 2>/dev/null)"; FAIL=$((FAIL+1))
fi

# --- L6: reason sanitization — single line, no #; reader still sees field 2 ---
node "$GOS" gate --exempt T92-hash --reason "reason with # hash and
newline inside" >/dev/null 2>&1
L6=$(python3 - <<'PYEOF'
lines = open('.gos/logs/exemptions.log', encoding='utf-8').read().split('\n')
lines = [l for l in lines if l.strip()]
hash_lines = [l for l in lines if 'T92-hash' in l]
bad = []
if len(hash_lines) != 1: bad.append('hash entries=%d' % len(hash_lines))
else:
    l = hash_lines[0]
    if '#' in l: bad.append('literal # survived: %r' % l)
    if not l.startswith('20'): bad.append('grammar head broken: %r' % l[:30])
    if 'reason with' not in l or 'newline inside' not in l: bad.append('content lost: %r' % l)
print('BAD ' + '; '.join(bad) if bad else 'OK')
PYEOF
)
RD2=$(node -e '
const gate = require(process.env.GOS_ROOT + "/bin/lib/ops/gate.cjs");
const arr = gate.readExemptions(process.cwd());
console.log(JSON.stringify(arr));
' 2>/dev/null)
if [ "$L6" = "OK" ] && printf '%s' "$RD2" | grep -qF '"T92-hash"'; then
  echo "  ✓ L6 sanitization: no #, single line; readExemptions reads field 2"; PASS=$((PASS+1))
else
  echo "  ✗ L6 sanitization: parse=$L6 read=$RD2"; FAIL=$((FAIL+1))
fi

# --- L7: enriched exemption round-trips through the one-shot reader ( compat)
printf '.gos/logs/exemptions.log\n' >> .gitignore
git add -A >/dev/null 2>&1 && git commit -qm t92-ledger >/dev/null 2>&1
T92_TREE="$(git rev-parse 'HEAD^{tree}')"
printf '{"schema_version":2,"sections_run":["T92-other"],"head_tree":"%s","patch_sha":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","finished_at":"z"}\n' "$T92_TREE" > .gos/cache/run-manifest.json
M_MISS() {
  node -e '
  const gate = require(process.env.GOS_ROOT + "/bin/lib/ops/gate.cjs");
  const r = gate.checkManifest(process.cwd(), ["T92-rt", "T92-other"], null);
  console.log(r.failures.map((f) => f.code + ":" + f.evidence.join(",")).join(" | "));
  ' 2>/dev/null
}
MISS_BEFORE="$(M_MISS)"
node "$GOS" gate --exempt T92-rt --reason "round trip proof through the one-shot reader" >/dev/null 2>&1
MISS_AFTER="$(M_MISS)"
node -e '
const gate = require(process.env.GOS_ROOT + "/bin/lib/ops/gate.cjs");
gate.consumeExemptions(process.cwd());
' >/dev/null 2>&1
CONSUMED=0
{ [ ! -e .gos/logs/exemptions.log ] || [ ! -s .gos/logs/exemptions.log ]; } && CONSUMED=1
if printf '%s' "$MISS_BEFORE" | grep -q 'manifest-missing-sections:T92-rt' && [ -z "$MISS_AFTER" ] && [ "$CONSUMED" -eq 1 ]; then
  echo "  ✓ L7 round-trip: enriched line honored by one-shot reader, consumed at commit"; PASS=$((PASS+1))
else
  echo "  ✗ L7 round-trip: before='$MISS_BEFORE' after='$MISS_AFTER' consumed=$CONSUMED"; FAIL=$((FAIL+1))
fi

# --- L8: logs exemptions + audit views render; empty ledger message ---
node "$GOS" gate --exempt T92-view --reason "exemption view rendering check" >/dev/null 2>&1
node "$GOS" logs exemptions > t92-ex.log 2>&1; EXV=$?
printf '2026-10-15T00:00:00.000Z edge-add bin/gos.cjs#fn:main -> bin/lib/nav/help.cjs#fn:cmdHelp asserts\n' > .gos/logs/edge-audit.log
node "$GOS" logs audit > t92-au.log 2>&1; AUV=$?
node "$GOS" logs audit --last 5 >> t92-au.log 2>&1; AUV5=$?
# empty ledger: receipts ledger emptied (consumed view path) — use a fresh key set via removal
mv .gos/logs/truth-receipts.md .gos/logs/truth-receipts.md.bak
node "$GOS" logs receipts > t92-empty.txt 2>&1; EMV=$?
mv .gos/logs/truth-receipts.md.bak .gos/logs/truth-receipts.md
L8_OK=1
[ "$EXV" -ne 0 ] && L8_OK=0
grep -qE 'T92-view' t92-ex.log && grep -qF 'exemption view rendering check' t92-ex.log || L8_OK=0
[ "$AUV" -ne 0 ] && L8_OK=0
[ "$AUV5" -ne 0 ] && L8_OK=0
grep -qF 'edge-add' t92-au.log || L8_OK=0
[ "$EMV" -ne 0 ] && L8_OK=0
grep -qiF 'no entries' t92-empty.txt || L8_OK=0
if [ "$L8_OK" -eq 1 ]; then
  echo "  ✓ L8 logs exemptions/audit render; empty ledger advisory + exit 0"; PASS=$((PASS+1))
else
  echo "  ✗ L8 views (exv=$EXV auv=$AUV/$AUV5 empty=$EMV)"; FAIL=$((FAIL+1))
fi

echo "--- T92 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
