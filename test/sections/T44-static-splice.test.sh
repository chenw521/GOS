#!/usr/bin/env bash
# gos-map:cmd gate
# static assertion — bin/gos.cjs must not gain unregistered .gos/ path literals (anti-regression)
# legal = root-level reserved items + directory-level registered prefixes + contract glob strings + legacy markers; illegal = unknown .gos/ subpaths
T44_DIR=""

t44_setup() {
  T44_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t44"
  mkdir -p "$T44_DIR" && cd "$T44_DIR" || exit 1
}
t44_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T44_DIR"; }

t44_setup
trap 't44_teardown' EXIT

PASS=0
FAIL=0

echo "--- T44: static assertion — no new unregistered .gos/ literals ---"

cat > "$T44_DIR/scanner.py" <<'PYEOF'
import re, sys
src = open(sys.argv[1]).read().split('\n')
viol = []
ROOT_LEGAL = {'.gos/', '.venv', 'venv', 'spec.md', 'plan.md', 'edges.json', 'edges.lock', 'run-manifest.json', 'deps.json', 'exemptions.log', 'edge-audit.log', 'state.json', 'config.json', 'gates.json', 'concerns.md',
              'lessons.md', 'map-ignore', 'README.md', '.lock', '.gitignore', 'track-manifest.json'}
DIR_LEGAL = ('project/', 'codebase/', 'archive/', 'gates/', 'renderers/', 'task/', 'cache/', 'logs/')
for i, ln in enumerate(src, 1):
    stripped = ln.strip()
    if stripped.startswith('//'):
        continue
    if '[T5-legacy-splice]' in ln:
        continue
    hits = []
    m1 = re.search(r"'\.gos/([^']*)'", ln)
    if m1:
        hits.append(m1.group(1))
    for m2 in re.finditer(r"'\.gos'\s*,\s*'([^']+)'", ln):
        hits.append(m2.group(1))
    for rel in hits:
        if rel == '' or rel.endswith('(') or '**' in rel:
            continue  # bare '.gos/' (ADD_PATHS top-level) — legal
            continue  # contract glob strings like '.gos/**(excl ...)'
        if rel in ROOT_LEGAL or rel.startswith(DIR_LEGAL) or (rel + '/') in DIR_LEGAL:
            continue
        viol.append(f'{i}: {stripped[:100]} (literal .gos/{rel})')
print('OK' if not viol else 'VIOLATIONS:\n' + '\n'.join(viol[:10]))
PYEOF

# .1 scan surface = the frozen set from the same source (a single-file surface silently shrinks as literals migrate)
# frozen set = the 19 files matching the terminal state
GOS_SRC_FILES="$(ls $GOS_ROOT/bin/gos.cjs $GOS_ROOT/bin/lib/*/[a-z]*.cjs 2>/dev/null)"
[ -z "$(ls $GOS_ROOT/bin/lib/core/index.cjs 2>/dev/null)" ] && GOS_SRC_FILES="$GOS_ROOT/bin/gos.cjs"
SCAN_ALL_OK=1; SCAN_OUT=""
for f in $GOS_SRC_FILES; do
  R="$(python3 "$T44_DIR/scanner.py" "$f")"
  if [ "$R" != "OK" ]; then SCAN_ALL_OK=0; SCAN_OUT="$SCAN_OUT $f: $R"; fi
done
if [ "$SCAN_ALL_OK" = "1" ]; then
  echo "  ✓ T44.1 no unregistered .gos/ literals (frozen file set)"; PASS=$((PASS+1))
else
  echo "  ✗ T44.1 $SCAN_OUT"; FAIL=$((FAIL+1))
fi

cat > "$T44_DIR/inject.py" <<'PYEOF'
import sys
src = open(sys.argv[1]).read()
marker = 'function cmdPaths(args) {'
src = src.replace(marker, "const LEAK = path.join(root, '.gos', 'leaked-zone', 'x.txt');\n" + marker, 1)
open(sys.argv[2], 'w').write(src)
PYEOF
python3 "$T44_DIR/inject.py" "$GOS_ROOT/bin/lib/ops/paths.cjs" "$T44_DIR/injected.cjs"
RES="$(python3 "$T44_DIR/scanner.py" "$T44_DIR/injected.cjs")"
if printf '%s' "$RES" | grep -q "leaked-zone"; then
  echo "  ✓ T44.2 injected unregistered path self-flags (assertion live)"; PASS=$((PASS+1))
else
  echo "  ✗ T44.2 injection NOT caught — assertion dead"; FAIL=$((FAIL+1))
fi

echo "--- T44 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
