#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/gitseed.cjs#fn:seed
# gos-map:cmd init
# : gitseed seed() engine upgrade ( neverOverwrite, atomic
# writes, brownfield prerequisite) — three changes with `init git`
# output bytes pinned unchanged: (1) neverOverwrite array opt, a listed
# conflicting dest is ALWAYS kept and doOverwrite is never consulted for it;
# (2) create/overwrite paths write temp + fsync + rename (.gos-bak still
# written before overwrite); (3) skipped gains a parallel skippedDetail
# array of {dest, reason} with the closed set
# {identical, conflict-kept, never, directory, unreadable}.
# Cases: A=never beats --overwrite AND an ask() answering 'overwrite'
#        B=non-listed conflict still overwrites with .gos-bak first
#        C=CLI regression — $GOS init git --overwrite replaces a differing
#          CHANGELOG.md, report bytes unchanged
#        D=skippedDetail reason tokens for every skip cause (unreadable via
#          chmod 000 when not root; else noted, spec-sanctioned fallback)
#        E=two concurrent seeds of the same dest — byte-exact rendered
#          variant, parses cleanly (no torn write), no temp litter
T77_DIR=""

t77_setup() {
  T77_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t77"
  mkdir -p "$T77_DIR" || exit 1
  cd "$T77_DIR" || exit 1
  cat > "$T77_DIR/probe.cjs" <<'PB'
// T77 probe: seed() with files + opts from argv, print result JSON.
const g = require(process.env.GOS_ROOT + '/bin/lib/ops/gitseed.cjs');
const o = { root: process.argv[2], files: JSON.parse(process.argv[3]), ...JSON.parse(process.argv[4] || '{}') };
if (typeof o.askAnswer === 'string') o.ask = async () => o.askAnswer;
g.seed(o)
  .then((r) => console.log(JSON.stringify(r)))
  .catch((e) => { console.error('PROBE-ERR ' + e.message); process.exit(1); });
PB
}

t77_seed() {  # t77_seed <root> <files-json> [opts-json] -> seed() result JSON on stdout
  if [ $# -ge 3 ]; then
    node "$T77_DIR/probe.cjs" "$1" "$2" "$3" 2>&1
  else
    node "$T77_DIR/probe.cjs" "$1" "$2" 2>&1
  fi
}

t77_field() {  # t77_field <dotpath> — read a field from the JSON on stdin
  python3 -c "
import json,sys
d=json.load(sys.stdin)
v=d
for k in '''$1'''.split('.'):
    v=v[int(k)] if isinstance(v,list) else v[k]
print(v if not isinstance(v,list) else ' '.join(v))"
}

t77_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T77_DIR"; }

t77_setup
echo "--- T77: gitseed neverOverwrite + atomic writes + skippedDetail ---"

# --- A: never-listed conflict is ALWAYS kept; doOverwrite never consulted ---
mkdir -p "$T77_DIR/a"
printf '# user version\n' > "$T77_DIR/a/KEEP.md"
RES=$(t77_seed "$T77_DIR/a" '{"KEEP.md":"rendered-v1"}' '{"overwrite":true,"neverOverwrite":["KEEP.md"]}'); RC=$?
assert_exit "A1 seed with overwrite:true + neverOverwrite exits 0" 0 "$RC"
assert_eq "A2 never-listed file lands in skipped" "KEEP.md" "$(printf '%s' "$RES" | t77_field skipped.0)"
assert_eq "A3 overwritten stays empty despite --overwrite" "" "$(printf '%s' "$RES" | t77_field overwritten)"
assert_eq "A4 file content untouched" "# user version" "$(cat "$T77_DIR/a/KEEP.md")"
assert_eq "A5 skip reason is never" "never" "$(printf '%s' "$RES" | t77_field skippedDetail.0.reason)"
mkdir -p "$T77_DIR/a2"
printf '# user version\n' > "$T77_DIR/a2/KEEP.md"
RES=$(t77_seed "$T77_DIR/a2" '{"KEEP.md":"rendered-v1"}' '{"askAnswer":"overwrite","neverOverwrite":["KEEP.md"]}'); RC=$?
assert_exit "A6 seed with ask->overwrite + neverOverwrite exits 0" 0 "$RC"
assert_eq "A7 ask() never consulted for a never-listed conflict (would answer overwrite)" "never" "$(printf '%s' "$RES" | t77_field skippedDetail.0.reason)"
assert_eq "A8 kept even though ask would have said yes" "# user version" "$(cat "$T77_DIR/a2/KEEP.md")"

# --- B: non-listed conflict still overwrites, .gos-bak written first ---
mkdir -p "$T77_DIR/b"
printf '# user version\n' > "$T77_DIR/b/GO.md"
RES=$(t77_seed "$T77_DIR/b" '{"GO.md":"rendered-v2"}' '{"overwrite":true,"neverOverwrite":["OTHER.md"]}'); RC=$?
assert_exit "B1 seed overwrite exits 0" 0 "$RC"
assert_eq "B2 non-listed conflict overwritten" "GO.md" "$(printf '%s' "$RES" | t77_field overwritten.0)"
assert_eq "B3 new content in place" "rendered-v2" "$(cat "$T77_DIR/b/GO.md")"
assert_eq "B4 .gos-bak preserves the user version" "# user version" "$(head -1 "$T77_DIR/b/GO.md.gos-bak" 2>/dev/null)"
assert_eq "B5 skipped empty" "" "$(printf '%s' "$RES" | t77_field skipped)"
assert_eq "B6 skippedDetail empty for a pure overwrite" "" "$(printf '%s' "$RES" | t77_field skippedDetail)"

# --- C: CLI regression — $GOS init git --overwrite still replaces CHANGELOG.md ---
mkdir -p "$T77_DIR/c" && ( cd "$T77_DIR/c" && git init -q . && git commit -q --allow-empty -m t77-c ) || exit 1
printf '# local changelog\n' > "$T77_DIR/c/CHANGELOG.md"
OUT=$(cd "$T77_DIR/c" && node "$GOS" init git --codeowner '@x' --repo o/r --overwrite </dev/null 2>&1); CRC=$?
assert_exit "C1 init git --overwrite exit 0" 0 "$CRC"
EXPECTED=$(node -e "
const g = require(process.env.GOS_ROOT + '/bin/lib/ops/gitseed.cjs');
process.stdout.write(g.renderLayer('universal', { codeowner: '@x', repo: 'o/r' })['CHANGELOG.md'])")
if [ "$EXPECTED" = "$(cat "$T77_DIR/c/CHANGELOG.md")" ]; then
  echo "  ✓ C2 CHANGELOG.md replaced with the rendered master"; PASS=$((PASS+1))
else echo "  ✗ C2 CHANGELOG.md does not match the rendered master"; FAIL=$((FAIL+1)); fi
assert_eq "C3 user changelog preserved in .gos-bak" "# local changelog" "$(head -1 "$T77_DIR/c/CHANGELOG.md.gos-bak" 2>/dev/null)"
assert_contains "C4 report bytes unchanged (overwritten block)" "overwritten (1) — previous copies saved as <file>.gos-bak:" "$OUT"
assert_contains "C5 report lists CHANGELOG.md under overwritten" "CHANGELOG.md" "$OUT"

# --- D: skippedDetail reason tokens for every skip cause ---
mkdir -p "$T77_DIR/d1"
printf 'same\n' > "$T77_DIR/d1/SAME.md"
RES=$(t77_seed "$T77_DIR/d1" '{"SAME.md":"same\n"}'); RC=$?
assert_exit "D1 seed identical exits 0" 0 "$RC"
assert_eq "D1 identical content -> reason identical" "identical" "$(printf '%s' "$RES" | t77_field skippedDetail.0.reason)"
mkdir -p "$T77_DIR/d2"
printf '# user version\n' > "$T77_DIR/d2/KEEP.md"
RES=$(t77_seed "$T77_DIR/d2" '{"KEEP.md":"rendered-v1"}' '{"nonInteractive":true}'); RC=$?
assert_exit "D2 seed non-interactive exits 0" 0 "$RC"
assert_eq "D2 conflict kept non-interactively -> reason conflict-kept" "conflict-kept" "$(printf '%s' "$RES" | t77_field skippedDetail.0.reason)"
mkdir -p "$T77_DIR/d3"
printf '# user version\n' > "$T77_DIR/d3/NEVER.md"
RES=$(t77_seed "$T77_DIR/d3" '{"NEVER.md":"rendered-v1"}' '{"overwrite":true,"neverOverwrite":["NEVER.md"]}'); RC=$?
assert_exit "D3 seed never-listed exits 0" 0 "$RC"
assert_eq "D3 never-listed conflict -> reason never" "never" "$(printf '%s' "$RES" | t77_field skippedDetail.0.reason)"
mkdir -p "$T77_DIR/d4/DIR.md"
RES=$(t77_seed "$T77_DIR/d4" '{"DIR.md":"rendered-v1"}'); RC=$?
assert_exit "D4 seed directory-at-path exits 0" 0 "$RC"
assert_eq "D4 directory at path -> reason directory" "directory" "$(printf '%s' "$RES" | t77_field skippedDetail.0.reason)"
assert_eq "D4b skippedDetail dest aligns with skipped entry" "DIR.md" "$(printf '%s' "$RES" | t77_field skippedDetail.0.dest)"
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$T77_DIR/d5"
  printf '# user version\n' > "$T77_DIR/d5/UNREAD.md"
  chmod 000 "$T77_DIR/d5/UNREAD.md"
  RES=$(t77_seed "$T77_DIR/d5" '{"UNREAD.md":"rendered-v1"}' '{"overwrite":true}'); RC=$?
  chmod 644 "$T77_DIR/d5/UNREAD.md"
  assert_exit "D5 seed unreadable exits 0" 0 "$RC"
  assert_eq "D5 unreadable file (chmod 000) -> reason unreadable" "unreadable" "$(printf '%s' "$RES" | t77_field skippedDetail.0.reason)"
  assert_eq "D6 unreadable content untouched even under --overwrite" "# user version" "$(cat "$T77_DIR/d5/UNREAD.md")"
else
  echo "  ○ D5 note: running as root — chmod 000 stays readable, unreadable not exercisable here (directory-at-path covers the remaining closed-set cause)"
fi

# --- E: concurrent seeds of the same dest — byte-exact variant, no torn write ---
mkdir -p "$T77_DIR/e"
cat > "$T77_DIR/e/race.cjs" <<'PB'
// T77 race: one process seeds ONE large dest; variant comes from the env.
const g = require(process.env.GOS_ROOT + '/bin/lib/ops/gitseed.cjs');
const v = process.env.T77_VARIANT;
const payload = JSON.stringify({ variant: v, data: v.repeat(65536) }) + '\n';
g.seed({ root: process.env.T77_ROOT, files: { 'race.json': payload }, overwrite: true, nonInteractive: true })
  .then((r) => console.log('RACE-OK ' + JSON.stringify(r)))
  .catch((e) => { console.error('RACE-ERR ' + e.message); process.exit(1); });
PB
E_FAILS=0
for round in 1 2 3 4 5; do
  rm -f "$T77_DIR/e/race.json" "$T77_DIR/e/race.json.gos-bak"
  T77_ROOT="$T77_DIR/e" T77_VARIANT=A node "$T77_DIR/e/race.cjs" >/dev/null 2>&1 &
  P1=$!
  T77_ROOT="$T77_DIR/e" T77_VARIANT=B node "$T77_DIR/e/race.cjs" >/dev/null 2>&1 &
  P2=$!
  wait "$P1"; R1=$?
  wait "$P2"; R2=$?
  VERDICT=$(node -e "
const fs = require('fs');
let d;
try { d = JSON.parse(fs.readFileSync('$T77_DIR/e/race.json', 'utf8')); }
catch (e) { console.log('TORN'); process.exit(0); }
if ((d.variant === 'A' || d.variant === 'B') && d.data.length === 65536) console.log('CLEAN ' + d.variant);
else console.log('BAD');")
  if [ "$R1" -ne 0 ] || [ "$R2" -ne 0 ]; then
    echo "  ✗ E1 round $round a racer failed (rc=$R1/$R2)"; FAIL=$((FAIL+1)); E_FAILS=$((E_FAILS+1))
  elif [ "$VERDICT" != "CLEAN A" ] && [ "$VERDICT" != "CLEAN B" ]; then
    echo "  ✗ E1 round $round not a byte-exact rendered variant (verdict=$VERDICT)"; FAIL=$((FAIL+1)); E_FAILS=$((E_FAILS+1))
  fi
done
if [ "$E_FAILS" -eq 0 ]; then
  echo "  ✓ E1 5/5 concurrent rounds land on a byte-exact rendered variant, JSON parses cleanly"; PASS=$((PASS+1))
fi
TMPS=$(find "$T77_DIR/e" -maxdepth 1 -name '*.tmp*' | wc -l | tr -d ' ')
assert_eq "E2 no temp-file litter left behind" "0" "$TMPS"

t77_teardown
echo "--- T77 done ---"
