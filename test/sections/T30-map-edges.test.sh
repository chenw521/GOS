#!/usr/bin/env bash
# gos-map:cmd map
# T30: map 2.0 anchor layer — parseAnchor / five validator classes / universe / last-# split / bans / case normalization
# Covers: D-21, D-22 (R4 plan r2 T1)
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner
T30_DIR=""

t30_setup() {
  T30_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t30"
  mkdir -p "$T30_DIR" && cd "$T30_DIR" || exit 1
}

t30_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T30_DIR"; }

t30_setup
echo "--- T30: anchor layer (parse + 5 validators + universe + bans) ---"

# --- sandbox repo fixture (committed BEFORE queries — fixture-before-init chain) ---
git init -q . && mkdir -p src bin
printf '# Title Here\n\ntext\n' > README.md
printf 'function mainApp() {}\n' > src/app.js
printf 'x\n' > bin/gos.cjs
printf 'y\n' > "we#ird.md"
# sec anchors resolve against THIS repo's test/sections (root-relative since
# the anchor generalization — no longer against the GOS install root)
mkdir -p test/sections && printf '# stub\n' > test/sections/T25-map-selfcheck.test.sh
git add -A && git commit -qm t30-fixture
printf 'z\n' > untracked.md   # exists on disk, NOT tracked, not in scan universe

A() { # A <label> <spec> <wantRC> <wantGrep|- >
  local label="$1" spec="$2" wantRC="$3" wantGrep="$4" out rc
  set +e; out=$(node "$GOS" map anchor "$spec" 2>&1); rc=$?; set -e
  assert_exit "$label" "$wantRC" "$rc"
  if [ "$wantGrep" != "-" ]; then assert_contains "$label (text)" "$wantGrep" "$out"; fi
}

# --- T30.1 five validator classes: bare path / cmd / fn / sec / contract key / h ---
A "T30.1a bare path anchor ok"                     "README.md"                  0 "anchor verified"
A "T30.1b cmd: anchor ok (COMMANDS row)"            "bin/gos.cjs#cmd:map"        0 "anchor verified"
A "T30.1c cmd: unknown command dead"                "bin/gos.cjs#cmd:nonexistent" 1 "dead anchor"
A "T30.1d fn: anchor ok (^function grep)"           "src/app.js#fn:mainApp"      0 "anchor verified"
A "T30.1e fn: missing function dead"                "src/app.js#fn:nope"         1 "dead anchor"
A "T30.1f sec: anchor ok (GOS sections enum)"       "bin/gos.cjs#sec:T25-map-selfcheck" 0 "anchor verified"
A "T30.1g sec: unknown section dead"                "bin/gos.cjs#sec:T99-nope"   1 "dead anchor"
A "T30.1h contract-key anchor ok"                   "bin/gos.cjs#depsTamper"     0 "anchor verified"
A "T30.1i unknown bare word = dead contract key"    "src/app.js#mainApp"         1 "dead anchor"
A "T30.1j h: heading anchor ok"                     "README.md#h:Title Here"     0 "anchor verified"
A "T30.1k h: missing heading dead"                  "README.md#h:No Such"        1 "dead anchor"

# --- T30.2 split rules and bans ---
A "T30.2a line-number anchor banned"                "src/app.js#L42"             1 "line-number anchors are banned"
A "T30.2b path containing # banned (last-# split)"  "we#ird.md#cmd:map"          1 "ambiguous"
A "T30.2c absolute path banned"                     "/etc/passwd"                1 "absolute"
A "T30.2d home-relative path banned"                "~/secret.md"                1 "absolute"

# --- T30.3 universe and normalization ---
A "T30.3a dead path (not in universe)"              "nope.md"                    1 "dead anchor"
A "T30.3b untracked+unscanned file outside universe" "untracked.md"              1 "dead anchor"
A "T30.3c case-normalized tracked match ok"         "readme.md"                  0 "anchor verified"

# --- T30.4 CONTRACTS frozen text present (anchorVerif key family) ---
set +e; COUT=$(node "$GOS" _contract 2>&1); CRC=$?; set -e
assert_exit "_contract callable" 0 "$CRC"
N_ANCHOR=$(printf '%s\n' "$COUT" | grep -c "anchorVerif" || true)
if [ "${N_ANCHOR:-0}" -ge 1 ]; then echo "  ✓ CONTRACTS has anchorVerif key family ($N_ANCHOR)"; PASS=$((PASS+1))
else echo "  ✗ CONTRACTS anchorVerif keys missing"; FAIL=$((FAIL+1)); fi

# --- T30.5 dead-edge text embeds the recovery command ---
set +e; OUT=$(node "$GOS" map anchor "nope.md" 2>&1); RC=$?; set -e
assert_exit "dead anchor exits 1" 1 "$RC"
assert_contains "dead-anchor text embeds recovery command" "gos map edge rewrite" "$OUT"

# --- T30.6 edge CLI: add/rm/rewrite/audit-log + audit receipt + git add enforcement ---
E() { # E <label> <wantRC> <args...>
  local label="$1" wantRC="$2"; shift 2
  local out rc
  set +e; out=$(node "$GOS" map edge "$@" 2>&1); rc=$?   # stay +e: sections own their errexit policy
  assert_exit "$label" "$wantRC" "$rc"
  LAST_EDGE_OUT="$out"; LAST_EDGE_RC="$rc"
}
E "T30.6a add rejects dead anchor" 1 add "nope.md" "README.md#h:Title Here" --type greps
E "T30.6b add creates first edge (+audit receipt)" 0 add "README.md" "bin/gos.cjs#cmd:map" --type greps --note "doc mentions map"
assert_file "edges.json created" ".gos/cache/edges.json"
assert_file "audit receipt file created" ".gos/logs/edge-audit.log"
grep -q "README.md" .gos/logs/edge-audit.log && echo "  ✓ audit receipt records the add" && PASS=$((PASS+1)) || { echo "  ✗ audit receipt missing entry"; FAIL=$((FAIL+1)); }
[ -f .gos/cache/edges.json ] && echo "  ✓ edges.json lives in cache/ (ignored, no staging — Phase W T16)" && PASS=$((PASS+1)) || { echo "  ✗ edges.json missing in cache/"; FAIL=$((FAIL+1)); }
E "T30.6c duplicate add rejected" 1 add "README.md" "bin/gos.cjs#cmd:map" --type greps
E "T30.6d rm removes edge" 0 rm "README.md" "bin/gos.cjs#cmd:map" --type greps
python3 -c "import json;d=json.load(open('.gos/cache/edges.json'));exit(0 if not d['edges'] else 1)" && echo "  ✓ edge removed from edges.json" && PASS=$((PASS+1)) || { echo "  ✗ edge still present"; FAIL=$((FAIL+1)); }
E "T30.6e rewrite migrates anchors" 0 add "src/app.js" "bin/gos.cjs#cmd:map" --type consumes
E "T30.6f rewrite --from/--to swaps" 0 rewrite --from "src/app.js" --to "src/app.js#fn:mainApp"
python3 -c "import json;d=json.load(open('.gos/cache/edges.json'));e=d['edges'];exit(0 if any(x['from']=='src/app.js#fn:mainApp' for x in e) and not any(x['from']=='src/app.js' for x in e) else 1)" && echo "  ✓ rewrite swapped anchor" && PASS=$((PASS+1)) || { echo "  ✗ rewrite did not swap"; FAIL=$((FAIL+1)); }
set +e; AL=$(node "$GOS" map edge audit-log 2>&1); ALRC=$?; set -e
assert_exit "T30.6g audit-log lists history" 0 "$ALRC"
assert_contains "audit-log shows add+rm+rewrite" "rewrite" "$AL"

# --- T30.7 read-failure classes: parse fail / EACCES die (catch-null banned) ---
cp .gos/cache/edges.json .gos/cache/edges.json.bak
printf '{broken' > .gos/cache/edges.json
E "T30.7a parse-fail edges.json dies" 1 add "README.md" "bin/gos.cjs#cmd:map" --type greps
assert_contains "parse-fail frozen text" "edges.json" "$LAST_EDGE_OUT"
cp .gos/cache/edges.json.bak .gos/cache/edges.json
chmod 000 .gos/cache/edges.json
E "T30.7b unreadable edges.json dies (not silent null)" 1 add "README.md" "bin/gos.cjs#cmd:map" --type greps
chmod 644 .gos/cache/edges.json
rm -f .gos/cache/edges.json.bak

# --- T30.8 lock discipline: live lock blocks / stale-mtime fake-live lock breakable / ROOT anchored ---
mkdir -p .gos
printf '{"pid":%d,"started_at":"2026-01-01T00:00:00Z"}' $$ > .gos/.lock
E "T30.8a live-pid lock blocks add" 1 add "README.md" "bin/gos.cjs#cmd:map" --type greps
assert_contains "lock-blocked text has recovery hint" "break-lock\|wait" "$LAST_EDGE_OUT"
touch -d '10 minutes ago' .gos/.lock
E "T30.8b stale mtime + live pid + break-lock succeeds" 0 add "README.md" "bin/gos.cjs#cmd:map" --type greps --break-lock
if [ ! -e .gos/.lock ]; then echo "  ✓ lock cleanly released on exit (process.on exit hook)"; PASS=$((PASS+1))
else echo "  ✗ lock file leaked after successful exit"; FAIL=$((FAIL+1)); fi
E "T30.8c audit-log still consistent after lock cycle" 0 audit-log

# --- T30.9 seeding: adopt --bootstrap creates a valid empty edges.json ---
rm -rf .gos/cache/edges.json .gos/logs/edge-audit.log
E "T30.9a adopt --bootstrap seeds empty edges.json" 0 adopt --bootstrap
python3 -c "import json;d=json.load(open('.gos/cache/edges.json'));exit(0 if d.get('schema_version')==1 and d.get('edges')==[] else 1)" && echo "  ✓ seeded schema valid (v1, empty)" && PASS=$((PASS+1)) || { echo "  ✗ seed schema wrong"; FAIL=$((FAIL+1)); }
E "T30.9b adopt re-anchors freeze when edges.json exists" 0 adopt
assert_file "adopt wrote edges.lock" ".gos/cache/edges.lock"

# --- T30.10 COMMANDS discovery surface: edge subcommand family in help metadata ---
set +e; HJ=$(node "$GOS" help --json 2>/dev/null); HRC=$?; set -e
assert_exit "help --json callable" 0 "$HRC"
python3 -c "
import json,sys,os
d=json.loads(os.environ['HJ'] if False else '''$HJ''')" 2>/dev/null || true
N_SUB=$(printf '%s\n' "$HJ" | grep -o "edge add\|edge rm\|edge adopt\|edge rewrite\|audit-log" | sort -u | wc -l)
if [ "${N_SUB:-0}" -ge 5 ]; then echo "  ✓ COMMANDS exposes edge subfamily ($N_SUB)"; PASS=$((PASS+1))
else echo "  ✗ COMMANDS edge subs missing ($N_SUB)"; FAIL=$((FAIL+1)); fi

# --- T30.11 extractor framework + switch extractor (deps.json semantic.* keys, schema v2) ---
if grep -q "const EXTRACTORS = \[" "$GOS_ROOT/bin/lib/map/engine.cjs"; then
  echo "  ✓ EXTRACTORS registry exists (extensible framework)"; PASS=$((PASS+1))
else echo "  ✗ EXTRACTORS registry missing"; FAIL=$((FAIL+1)); fi
set +e; SR=$(cd "$GOS_ROOT" && node "$GOS" map scan 2>/dev/null); SRC_RC=$?; set -e
assert_exit "T30.11a self-repo scan with extractors exits 0" 0 "$SRC_RC"
python3 - <<'PYEOF'
import json, os, sys
d = json.load(open(os.path.join(os.environ['GOS_ROOT'], '.gos', 'cache', 'deps.json')))
bad = []
if d.get('schema_version') != 3: bad.append(f"schema_version != 3 (got {d.get('schema_version')})")   # [Phase P T2/D-40]
sw = d.get('semantic', {}).get('switch', [])
if not any(e.get('cmd') == 'map' and e.get('fn') == 'cmdMap' for e in sw):   # file field = cmdMap host (map/index.cjs); assert only cmd/fn keys
    bad.append(f'switch edge map->cmdMap missing (got {sw[:3]}...)')
for e in sw:
    if not (e.get('cmd') and e.get('fn') and e.get('file')): bad.append(f'switch edge missing keys: {e}')
print('  ✓ semantic.switch edges present (map→cmdMap, keyed {cmd,fn,file})' if not bad else '  ✗ ' + '; '.join(bad))
sys.exit(1 if bad else 0)
PYEOF
assert_exit "T30.11b semantic.switch schema holds" 0 "$?"
set +e; CL=$(cd "$GOS_ROOT" && node "$GOS" map closure bin/gos.cjs --no-refresh 2>&1); CLRC=$?; set -e
assert_exit "T30.11c legacy consumers (closure) still work on v2 cache" 0 "$CLRC"
rm -f "$GOS_ROOT/.gos/cache/deps.json"

# --- T30.12 extractor call site + contract string + map-ignore (sandbox repo) ---
t30_setup
git init -q . && mkdir -p .gos docs bin
printf 'x\n' > bin/gos.cjs   # anchor host for #cmd:map neighborhood query
printf '# doc\nrun `gos map scan` now\nalso: node bin/gos.cjs commit think\n' > docs/usage.md
printf '#!/usr/bin/env bash\nnode "$GOS" commit think\n' > run.sh
printf 'ignored file mentions gos map scan\n' > ignored.md
printf 'mentions <!-- gos-map:ignore --> gos gate all on this line\n' > lineexempt.md
printf 'frozen string deps.json schema_version not supported by this CLI — refusing cached map appears here\n' > docs/compat.md
printf 'ignored.md\n' > .gos/map-ignore
git add -A && git commit -qm t3012
set +e; OUT=$(node "$GOS" map scan 2>&1); RC=$?; set -e
assert_exit "T30.12a sandbox scan exits 0" 0 "$RC"
python3 - <<'PYEOF'
import json, sys
d = json.load(open('.gos/cache/deps.json'))
sem = d.get('semantic', {})
calls = {(e['file'], e['cmd']) for e in sem.get('calls', [])}
bad = []
if ('docs/usage.md', 'map') not in calls: bad.append('usage.md→map call missing')
if ('docs/usage.md', 'commit') not in calls: bad.append('usage.md→commit call missing')
if ('run.sh', 'commit') not in calls: bad.append('run.sh→commit call missing')
if ('ignored.md', 'map') in calls: bad.append('map-ignore file NOT excluded')
if ('lineexempt.md', 'gate') in calls: bad.append('line-level <!-- gos-map:ignore --> NOT honored')
ct = {(e['file'], e['key']) for e in sem.get('contracts', [])}
if ('docs/compat.md', 'depsSchemaFuture') not in ct: bad.append('contract-string consumer edge missing')
if any(e['file'] == 'bin/gos.cjs' for e in sem.get('contracts', [])): bad.append('defining file (gos.cjs) should not be a contracts consumer edge')
print('  ✓ calls/contracts extractors + map-ignore + line-exemption all hold' if not bad else '  ✗ ' + '; '.join(bad))
sys.exit(1 if bad else 0)
PYEOF
assert_exit "T30.12b semantic.calls/contracts content verified" 0 "$?"
set +e; SHOW=$(node "$GOS" map show "bin/gos.cjs#cmd:map" 2>&1); SHOWRC=$?; set -e
assert_exit "T30.12c map show <anchor> exits 0" 0 "$SHOWRC"
assert_contains "T30.12d R-02: show lists non-import dependents" "usage.md" "$SHOW"

t30_teardown
