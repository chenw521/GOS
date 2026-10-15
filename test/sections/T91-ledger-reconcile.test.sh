#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/gate.cjs#fn:readExemptions bin/lib/ops/gate.cjs#fn:checkManifest bin/lib/ops/gate.cjs#fn:consumeExemptions
# gos-map:cmd gate,_contract
# T91: audit-ledger reconciliation (D-01/R-34) — GOS_PATHS logs trio machine-local
# (tracked:false + purge "runtime state, machine-local"), zero residual git-add of
# logs paths in gate/edges (grep = counter-evidence leg only), .gitignore carries
# no !.gos/logs reversal while the dir rule keeps census coverage, and the
# readExemptions ledger round-trips: written by gate --exempt, honored by
# checkManifest, consumed (cleared) by consumeExemptions.
# Standalone-safe: self-provisions env when not run under test/run-sections.sh.

T91_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T91_STANDALONE=1
  T91_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T91_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T91_SELFROOT"
  export TESTBASE="$(mktemp -d "$T91_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T91_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t91"
mkdir -p "$T91_DIR" && cd "$T91_DIR" || exit 1

t91_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T91_DIR"
  if [ "$T91_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t91_teardown EXIT

PASS=0
FAIL=0

echo "--- T91: audit-ledger reconciliation (D-01/R-34) ---"

# --- T91.1 registry leg: logs trio tracked === false + machine-local purge note ---
node "$GOS" _contract 2>/dev/null > contract.json
python3 - contract.json <<'PYEOF' > t91-reg.txt 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
pr = d['paths_registry']
bad = []
for k in ('truth_receipts', 'exemptions', 'edge_audit'):
    e = pr.get(k)
    if not isinstance(e, dict):
        bad.append('%s:missing' % k); continue
    if e.get('tracked') is not False:
        bad.append('%s:tracked=%r' % (k, e.get('tracked')))
    if e.get('purge') != 'runtime state, machine-local':
        bad.append('%s:purge=%r' % (k, e.get('purge')))
print('OK' if not bad else 'BAD ' + '; '.join(bad))
PYEOF
if [ "$(cat t91-reg.txt 2>/dev/null)" = "OK" ]; then
  echo "  ✓ T91.1 registry trio tracked:false + purge 'runtime state, machine-local'"; PASS=$((PASS+1))
else
  echo "  ✗ T91.1 registry leg: $(cat t91-reg.txt 2>/dev/null)"; FAIL=$((FAIL+1))
fi

# --- T91.2 reconciliation must not move paths: rel/granularity unchanged ---
python3 - contract.json <<'PYEOF' > t91-shape.txt 2>/dev/null
import json, sys
pr = json.load(open(sys.argv[1]))['paths_registry']
expect = {
    'truth_receipts': ('logs/truth-receipts.md', 'file'),
    'exemptions': ('logs/exemptions.log', 'file'),
    'edge_audit': ('logs/edge-audit.log', 'file'),
}
bad = []
for k, (rel, gran) in expect.items():
    e = pr.get(k, {})
    if e.get('rel') != rel: bad.append('%s:rel=%r' % (k, e.get('rel')))
    if e.get('granularity') != gran: bad.append('%s:gran=%r' % (k, e.get('granularity')))
print('OK' if not bad else 'BAD ' + '; '.join(bad))
PYEOF
if [ "$(cat t91-shape.txt 2>/dev/null)" = "OK" ]; then
  echo "  ✓ T91.2 trio rel/granularity stable (reconcile flips flags, not paths)"; PASS=$((PASS+1))
else
  echo "  ✗ T91.2 shape leg: $(cat t91-shape.txt 2>/dev/null)"; FAIL=$((FAIL+1))
fi

# --- T91.3 counter-evidence leg: zero residual git-add of logs paths ---
RES_G=$(grep -cF "git', ['-C', root, 'add'" "$GOS_ROOT/bin/lib/ops/gate.cjs" || true)
RES_E=$(grep -cF "git', ['-C', root, 'add'" "$GOS_ROOT/bin/lib/map/edges.cjs" || true)
ADD_G=$(grep -c "'add'" "$GOS_ROOT/bin/lib/ops/gate.cjs" || true)
ADD_E=$(grep -c "'add'" "$GOS_ROOT/bin/lib/map/edges.cjs" || true)
if [ "${RES_G:-0}" -eq 0 ] && [ "${RES_E:-0}" -eq 0 ] && [ "${ADD_G:-0}" -eq 0 ] && [ "${ADD_E:-0}" -eq 0 ]; then
  echo "  ✓ T91.3 no git-add residue in gate.cjs/edges.cjs (logs or otherwise)"; PASS=$((PASS+1))
else
  echo "  ✗ T91.3 residue: gate staged=$RES_G/'$ADD_G' edges staged=$RES_E/'$ADD_E'"; FAIL=$((FAIL+1))
fi

# --- T91.4 .gitignore: zero !.gos/logs reversal + dead comment gone + dir rule kept ---
REV=$(grep -c '!\.gos/logs' "$GOS_ROOT/.gitignore" || true)
DEAD=$(grep -c 'audit logs stay tracked' "$GOS_ROOT/.gitignore" || true)
if [ "${REV:-1}" -eq 0 ] && [ "${DEAD:-1}" -eq 0 ] && grep -qx '.gos/logs/' "$GOS_ROOT/.gitignore"; then
  echo "  ✓ T91.4 .gitignore: zero reversal, no dead comment, dir rule keeps coverage"; PASS=$((PASS+1))
else
  echo "  ✗ T91.4 .gitignore: reversal=$REV dead-comment=$DEAD dir-rule=$(grep -x '.gos/logs/' "$GOS_ROOT/.gitignore" | wc -l)"; FAIL=$((FAIL+1))
fi

# --- T91.5 tracked generated view (repo README) reflects machine-local rows ---
if [ -f "$GOS_ROOT/.gos/README.md" ]; then
  ROWS_OK=0
  for rel in logs/truth-receipts.md logs/exemptions.log logs/edge-audit.log; do
    if grep -F "| \`$rel\` |" "$GOS_ROOT/.gos/README.md" | grep -qF 'runtime state, machine-local | no |'; then
      ROWS_OK=$((ROWS_OK+1))
    fi
  done
  if [ "$ROWS_OK" -eq 3 ]; then
    echo "  ✓ T91.5 .gos/README.md logs rows render machine-local (tracked no)"; PASS=$((PASS+1))
  else
    echo "  ✗ T91.5 README logs rows stale ($ROWS_OK/3 machine-local — regen: gos paths --markdown)"; FAIL=$((FAIL+1))
  fi
else
  echo "  ○ T91.5 skipped: .gos/README.md absent (fresh checkout)"; PASS=$((PASS+1))
fi

# --- T91.6 readExemptions round-trip: write (CLI) -> honored (checkManifest) -> consumed ---
git init -q . && git commit -q --allow-empty -m root
node "$GOS" init 1 "t91 ledger reconcile" >/dev/null 2>&1
mkdir -p .gos/logs .gos/cache
# D-01 semantics: logs are machine-local — ignore them so writing the ledger
# never dirties the content tree the manifest freshness hash covers.
printf '.gos/logs/\n' >> .gitignore
git add -A >/dev/null 2>&1 && git commit -qm t91-base >/dev/null 2>&1
# fresh-tree manifest (clean tree, HEAD tree, ancestor branch): T91-other ran, T91-roundtrip missing
T91_TREE="$(git rev-parse 'HEAD^{tree}')"
printf '{"schema_version":2,"sections_run":["T91-other"],"head_tree":"%s","patch_sha":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","finished_at":"z"}\n' "$T91_TREE" > .gos/cache/run-manifest.json

MISS_BEFORE="$(node -e '
const gate = require(process.argv[2] + "/bin/lib/ops/gate.cjs");
const r = gate.checkManifest(process.argv[1], ["T91-roundtrip", "T91-other"], null);
console.log(r.failures.map((f) => f.code + ":" + f.evidence.join(",")).join(" | "));
' "$PWD" "$GOS_ROOT" 2>/dev/null)"

set +e
node "$GOS" gate --exempt T91-roundtrip --reason "roundtrip fixture for the one-shot reader" > exempt.out 2>&1; EXRC=$?
set +e
EXLOG_OK=0
grep -q 'T91-roundtrip' .gos/logs/exemptions.log 2>/dev/null && EXLOG_OK=1

RD_JSON="$(node -e '
const gate = require(process.argv[2] + "/bin/lib/ops/gate.cjs");
console.log(JSON.stringify(gate.readExemptions(process.argv[1])));
' "$PWD" "$GOS_ROOT" 2>/dev/null)"

MISS_AFTER="$(node -e '
const gate = require(process.argv[2] + "/bin/lib/ops/gate.cjs");
const r = gate.checkManifest(process.argv[1], ["T91-roundtrip", "T91-other"], null);
console.log(r.failures.map((f) => f.code + ":" + f.evidence.join(",")).join(" | "));
' "$PWD" "$GOS_ROOT" 2>/dev/null)"

node -e '
const gate = require(process.argv[2] + "/bin/lib/ops/gate.cjs");
gate.consumeExemptions(process.argv[1]);
' "$PWD" "$GOS_ROOT" >/dev/null 2>&1
CONSUMED_OK=0
{ [ ! -e .gos/logs/exemptions.log ] || [ ! -s .gos/logs/exemptions.log ]; } && CONSUMED_OK=1

if printf '%s' "$MISS_BEFORE" | grep -q 'manifest-missing-sections:T91-roundtrip' \
   && [ "$EXRC" -eq 0 ] && [ "$EXLOG_OK" -eq 1 ] \
   && [ "$RD_JSON" = '["T91-roundtrip"]' ] \
   && [ -z "$MISS_AFTER" ] && [ "$CONSUMED_OK" -eq 1 ]; then
  echo "  ✓ T91.6 exemptions round-trip: written -> honored -> consumed+cleared"; PASS=$((PASS+1))
else
  echo "  ✗ T91.6 round-trip: before='$MISS_BEFORE' exrc=$EXRC log=$EXLOG_OK read='$RD_JSON' after='$MISS_AFTER' consumed=$CONSUMED_OK"; FAIL=$((FAIL+1))
fi

echo "--- T91 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
