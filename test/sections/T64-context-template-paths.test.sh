#!/usr/bin/env bash
# gos-map:fn bin/lib/task/context.cjs#fn:cmdContext
# gos-map:cmd context
# T64: context template fields must carry GOS_SELF_ROOT-joined absolute paths
# (real files on disk) + a readonly hint — cwd-relative "templates/..." strings
# are dead links in product installs where GOS lives in node_modules/gos.
T64_DIR=""

t64_setup() {
  T64_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t64"
  mkdir -p "$T64_DIR" && cd "$T64_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
}
t64_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T64_DIR"; }

# All absolute-path tokens in a ctx JSON "template" field must sit under
# <root> and exist on disk; prints OK or ERR: <reason> (never exits non-zero).
t64_paths() {
  python3 -c "
import json, os, re, sys
root = os.path.realpath(sys.argv[1])
try:
    t = json.load(open(sys.argv[2]))['template']
except Exception as e:
    print('ERR: bad ctx json: %s' % e); sys.exit(0)
paths = [p.rstrip('/') for p in re.findall(r'/[^\s()]+', t)]
if not paths:
    print('ERR: no absolute path in template field: %r' % t); sys.exit(0)
for p in paths:
    if not p.startswith(root + os.sep):
        print('ERR: %r not under self-root %s' % (p, root)); sys.exit(0)
    if not os.path.exists(p):
        print('ERR: dead link %r' % p); sys.exit(0)
print('OK')
" "$1" "$2"
}

t64_hint() {
  T="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["template"])' "$1" 2>/dev/null)"
  if printf '%s' "$T" | grep -qi 'readonly\|copy'; then
    echo "  ✓ T64 $2 template field carries readonly hint"; PASS=$((PASS+1))
  else
    echo "  ✗ T64 $2 template field lacks readonly hint: ${T:0:120}"; FAIL=$((FAIL+1))
  fi
}

t64_setup
trap 't64_teardown' EXIT
PASS=0
FAIL=0
echo "--- T64: context template paths (self-root + readonly hint) ---"

GOS_REAL="$(cd "$GOS_ROOT" && pwd -P)"

# --- T64.1 dev-repo mode: every stage's template paths resolve to real files ---
node "$GOS" init 1 "t64 template paths" >/dev/null 2>&1
node "$GOS" context think  > ct.json 2>/dev/null
node "$GOS" context plan   > cp.json 2>/dev/null
node "$GOS" context verify > cv.json 2>/dev/null
for pair in "ct.json:think" "cp.json:plan" "cv.json:verify"; do
  F="${pair%%:*}"; S="${pair#*:}"
  R="$(t64_paths "$GOS_REAL" "$F")"
  if [ "$R" = "OK" ]; then
    echo "  ✓ T64.1 $S template paths absolute under self-root + exist"; PASS=$((PASS+1))
  else
    echo "  ✗ T64.1 $S $R"; FAIL=$((FAIL+1))
  fi
  t64_hint "$F" "$S"
done

# --- T64.2 product-install mode: npm pack → unpack → CLI from the tarball copy;
# cwd-relative paths die here (sandbox repo has no ./templates) ---
t64_teardown; t64_setup
PKG="$T64_DIR/pkg"; mkdir -p "$PKG"
( cd "$GOS_ROOT" && npm pack --pack-destination "$PKG" >/dev/null 2>&1 )
if tar -xzf "$PKG"/*.tgz -C "$PKG" 2>/dev/null && [ -f "$PKG/package/bin/gos.cjs" ]; then
  echo "  ✓ T64.2 npm pack + unpack produced a runnable package copy"; PASS=$((PASS+1))
else
  echo "  ✗ T64.2 npm pack/unpack failed"; FAIL=$((FAIL+1))
fi
node "$PKG/package/bin/gos.cjs" init 1 "t64 product install" >/dev/null 2>&1
node "$PKG/package/bin/gos.cjs" context think > pt.json 2>/dev/null
R="$(t64_paths "$PKG/package" pt.json)"
if [ "$R" = "OK" ]; then
  echo "  ✓ T64.2 pack-mode think template paths live inside unpacked package"; PASS=$((PASS+1))
else
  echo "  ✗ T64.2 pack-mode $R"; FAIL=$((FAIL+1))
fi
t64_hint pt.json "pack-mode-think"

echo "--- T64 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
