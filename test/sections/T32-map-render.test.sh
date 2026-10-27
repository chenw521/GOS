#!/usr/bin/env bash
# gos-map:cmd map
# mermaid renderer (escape/dict-order/parallel-aggregation/external-dashed)
# graph three forms + closure --json strict envelope
T32_DIR=""

t32_setup() {
  T32_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t32"
  mkdir -p "$T32_DIR" && cd "$T32_DIR" || exit 1
}
# --- .8 network.md hybrid rendering (idempotent / marker die / manual region preserved / backup)
t32_setup
git init -q . && mkdir -p bin docs
printf "function cmdMap(){ }\nswitch (sub) { case 'map': cmdMap(); }\n" > bin/gos.cjs
printf 'caller gos map\n' > docs/plain.md
git add -A && git commit -qm t328
set +e; S1=$(node "$GOS" map scan 2>&1); R1=$?; set +e
assert_exit "T32.8a scan refreshes network.md" 0 "$R1"
assert_file "T32.8b network.md created" ".gos/codebase/network.md"
if grep -q "calls (②" .gos/codebase/network.md; then echo "  ✓ T32.8c network.md carries semantic data (calls family)"; PASS=$((PASS+1)); else echo "  ✗ network.md missing semantic data"; FAIL=$((FAIL+1)); fi
printf 'HAND NOTES LINE ONE\nHAND NOTES LINE TWO\n' >> .gos/codebase/network.md
node "$GOS" map scan >/dev/null 2>&1
grep -q "HAND NOTES LINE TWO" .gos/codebase/network.md && echo "  ✓ manual region survives rescan" && PASS=$((PASS+1)) || { echo "  ✗ manual region lost"; FAIL=$((FAIL+1)); }
cp .gos/codebase/network.md /tmp/t32-net-snap
node "$GOS" map scan >/dev/null 2>&1
if diff -q /tmp/t32-net-snap .gos/codebase/network.md >/dev/null 2>&1; then
  echo "  ✓ idempotent: second scan produces zero diff (frozen input)"; PASS=$((PASS+1))
else echo "  ✗ idempotency broken (diff non-empty)"; FAIL=$((FAIL+1)); fi
rm -f /tmp/t32-net-snap
# marker deleted -> die refuses rescan + backup exists
grep -v "MANUAL region" .gos/codebase/network.md | sed "/<!-- MANUAL/d" > /tmp/t32-nomarker && cp /tmp/t32-nomarker .gos/codebase/network.md && rm -f /tmp/t32-nomarker
set +e; DN=$(node "$GOS" map scan 2>&1); DNRC=$?; set +e
assert_exit "T32.8d marker-missing → scan die (refuse refresh)" 1 "$DNRC"
assert_contains "die text says refused (not destroyed)" "refusing to refresh" "$DN"
assert_file "backup exists after die" ".gos/cache/backups/network.md.1"

t32_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T32_DIR"; }

t32_setup
echo "--- T32: mermaid rendering + three outlets ---"

git init -q . && mkdir -p bin docs
printf "function cmdMap(){ }\nswitch (sub) { case 'map': cmdMap(); }\n" > bin/gos.cjs
printf 'calls gos map scan\n' > "docs/weird(){}.md"
printf '# 标题 中文\n\ncalls gos map too\n' > "docs/中文笔记.md"
printf 'plain caller\n' > docs/plain.md
git add -A && git commit -qm t32-fixture

# manual edges: parallel x2 (same from-to, different type) + external + CJK note
node "$GOS" map edge adopt --bootstrap >/dev/null 2>&1
node "$GOS" map edge add docs/plain.md "bin/gos.cjs#cmd:map" --type greps >/dev/null 2>&1
node "$GOS" map edge add docs/plain.md "bin/gos.cjs#cmd:map" --type consumes >/dev/null 2>&1
node "$GOS" map edge add "docs/中文笔记.md" "bin/gos.cjs#cmd:map" --type consumes --note "备注→转义" >/dev/null 2>&1 || echo "  (CJK edge add failed — check anchor)"

# --- .1 whole-graph mermaid syntax skeleton
set +e; G=$(node "$GOS" map graph 2>/dev/null); GRC=$?; set +e
assert_exit "T32.1a map graph exits 0" 0 "$GRC"
assert_contains "T32.1b mermaid fence present" '```mermaid' "$G"
assert_contains "T32.1c graph directive" "graph" "$G"

# --- .2 escaping: special-char paths/titles must not break the syntax
assert_contains "T32.2a special-char path present (escaped label)" "weird" "$G"
python3 - "$G" <<'PYEOF2'
import sys, re
g = sys.argv[1]
bad = [l for l in g.split('\n') if re.match(r'^\s+n\d+\[', l) and not re.match(r'^\s+n\d+\["[^"\n]*"\]$', l)]
print('  ✓ every node line is strictly nN["escaped-label"] (sanitize holds)' if not bad else '  ✗ node lines violate strict form: ' + bad[0])
sys.exit(1 if bad else 0)
PYEOF2
[ $? -eq 0 ] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))
if printf '%s\n' "$G" | grep -q "中文笔记"; then
  echo "  ✓ CJK path rendered (in quoted label)"; PASS=$((PASS+1))
else echo "  ✗ CJK path missing from graph"; FAIL=$((FAIL+1)); fi

# --- .3 parallel-edge aggregation: same from-to with two types -> single counted label
N_AGG=$(printf '%s\n' "$G" | grep -cE '\-\-\>\|.*greps\+consumers?\|\||-->\|?"greps+consumes"|greps\+consumes' || true)
N_AGG=$(printf '%s\n' "$G" | grep -c "greps+consumes" || true)
if [ "${N_AGG:-0}" -eq 1 ]; then
  echo "  ✓ parallel edges aggregated into ONE edge line (greps+consumes)"; PASS=$((PASS+1))
else echo "  ✗ parallel aggregation broken (agg lines: $N_AGG)"; FAIL=$((FAIL+1)); fi

# --- .4 external edge dashed (manual external:true)
printf '{"schema_version":1,"note":"MAINTAINED","edges":[{"from":"docs/plain.md","to":"docs/elsewhere.md","type":"owns","external":true}]}' > /tmp/t32edges.json 2>/dev/null
cp .gos/cache/edges.json .gos/cache/edges.json.bak && cp /tmp/t32edges.json .gos/cache/edges.json && node "$GOS" map edge adopt >/dev/null 2>&1
set +e; G2=$(node "$GOS" map graph 2>/dev/null); set +e
if printf '%s\n' "$G2" | grep -q -- "-\.->"; then
  echo "  ✓ external edge rendered dashed (-.->)"; PASS=$((PASS+1))
else echo "  ✗ external edge not dashed"; FAIL=$((FAIL+1)); fi
cp .gos/cache/edges.json.bak .gos/cache/edges.json && node "$GOS" map edge adopt >/dev/null 2>&1 && rm -f .gos/cache/edges.json.bak /tmp/t32edges.json

# --- .5 neighborhood subgraph: show --graph defaults to 1 hop
set +e; NG=$(node "$GOS" map show "bin/gos.cjs#cmd:map" --graph 2>/dev/null); NGRC=$?; set +e
assert_exit "T32.5a neighborhood graph exits 0" 0 "$NGRC"
assert_contains "T32.5b neighborhood includes caller" "plain.md" "$NG"

# --- .6 closure --json strict envelope
printf '// touch\n' >> bin/gos.cjs
set +e; J=$(node "$GOS" map closure bin/gos.cjs --json 2>/dev/null); JRC=$?; set +e
assert_exit "T32.6a closure --json exits 0" 0 "$JRC"
python3 - "$J" <<'PYEOF'
import json, sys
raw = sys.argv[1]
bad = []
if not raw.startswith('{'): bad.append('stdout does not start with { (byte 0 envelope violated)')
try:
    d = json.loads(raw)
    assert 'schema_version' in d and 'closure' in d
    c = d['closure']
    assert isinstance(c.get('mustCheck'), list) and isinstance(c.get('mustRun'), list)
except Exception as e:
    bad.append(f'envelope parse failed: {e}')
print('  ✓ strict JSON envelope: byte0, schema_version, closure{mustCheck,mustRun}' if not bad else '  ✗ ' + '; '.join(bad))
sys.exit(1 if bad else 0)
PYEOF
assert_exit "T32.6b envelope structure verified" 0 "$?"
if printf '%s\n' "$J" | head -1 | grep -q "📍\|Next"; then
  echo "  ✗ banner/Next leaked into --json stdout"; FAIL=$((FAIL+1))
else echo "  ✓ no banner/Next pollution in --json mode"; PASS=$((PASS+1)); fi

# --- .7 --print0 stays paths-only permanently
set +e; P0=$(node "$GOS" map closure bin/gos.cjs --print0 2>/dev/null | tr '\0' '\n' | head -2); PRC=$?; set +e
if printf '%s\n' "$P0" | grep -qv "/" && [ -n "$(printf '%s\n' "$P0" | grep -v '^$' | grep -v '/')" ]; then
  echo "  ✗ non-path content leaked into print0"; FAIL=$((FAIL+1))
else echo "  ✓ print0 stays paths-only"; PASS=$((PASS+1)); fi

# --- .9 human-visible map (ascii/html/dot/renderer plugins)
t32_setup
git init -q . && mkdir -p bin docs
printf "function cmdMap(){ }\nswitch (sub) { case 'map': cmdMap(); }\n" > bin/gos.cjs
printf 'caller gos map\n' > docs/plain.md
git add -A && git commit -qm t329

set +e; A=$(node "$GOS" map graph --ascii 2>/dev/null); ARC=$?; set +e
assert_exit "T32.9a --ascii exits 0" 0 "$ARC"
if printf '%s\n' "$A" | grep -qE "├──|└──|──"; then
  echo "  ✓ ascii box-drawing tree rendered"; PASS=$((PASS+1))
else echo "  ✗ ascii output has no tree glyphs"; FAIL=$((FAIL+1)); fi
if printf '%s\n' "$A" | grep -q "plain.md"; then
  echo "  ✓ ascii shows node names"; PASS=$((PASS+1))
else echo "  ✗ ascii missing node"; FAIL=$((FAIL+1)); fi

set +e; H=$(node "$GOS" map graph --html 2>/dev/null); HRC=$?; set +e
assert_exit "T32.9b --html exits 0" 0 "$HRC"
assert_contains "T32.9c html doctype" "<!DOCTYPE html>" "$H"
if printf '%s\n' "$H" | grep -qE 'src="http|href="http'; then
  echo "  ✗ html references external resources (must be self-contained)"; FAIL=$((FAIL+1))
else echo "  ✓ html self-contained (no external src/href)"; PASS=$((PASS+1)); fi
assert_contains "T32.9d html embeds data+script" "application/json" "$H"

set +e; DT=$(node "$GOS" map graph --dot 2>/dev/null); DRC=$?; set +e
assert_exit "T32.9e --dot exits 0" 0 "$DRC"
assert_contains "T32.9f dot digraph" "digraph" "$DT"
if printf '%s\n' "$DT" | grep -q -- " -> "; then echo "  ✓ dot edge syntax (n0 -> n1)"; PASS=$((PASS+1)); else echo "  ✗ dot edge syntax missing"; FAIL=$((FAIL+1)); fi

# renderer plugin: .gos/renderers/<name>.sh consumes stdin JSON
mkdir -p .gos/renderers
cat > .gos/renderers/echo.sh <<'REOF'
#!/usr/bin/env bash
# receives graph JSON on stdin
python3 -c 'import json,sys; d=json.load(sys.stdin); print("PLUGIN-OK pairs=", len(d.get("pairs",[])))'
REOF
chmod +x .gos/renderers/echo.sh
set +e; PL=$(node "$GOS" map graph --renderer echo 2>&1); PRC=$?; set +e
assert_exit "T32.9h --renderer plugin executes" 0 "$PRC"
assert_contains "plugin received graph JSON" "PLUGIN-OK" "$PL"
set +e; node "$GOS" map graph --renderer nonexist >/dev/null 2>&1; NRC=$?; set +e
assert_exit "T32.9i unknown renderer dies" 1 "$NRC"

t32_teardown
