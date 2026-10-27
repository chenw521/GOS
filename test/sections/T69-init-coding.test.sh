#!/usr/bin/env bash
# gos-map:fn bin/lib/task/init.cjs#fn:cmdInitCoding
# gos-map:cmd init
# : gos init coding — seed the coding-standards book set
# (00-general/shell/node/python) into <repo>/docs/coding-standards/, reusing
# the gitseed seed() conflict contract (create / identical-skip / keep on
# conflict, .gos-bak only on explicit overwrite), task-state immunity, and
# the per-book anchor+license attribution line (grep-checkable).
# Cases: A=clean repo 4 books + no staging/no state  B=attribution lines
#        C=byte-identical masters  D=json report  E=idempotent re-run all skip
#        F=conflict kept without --overwrite  G=--overwrite + .gos-bak
#        H=non-git refusal  I=level-first escape hatch + stray positional
#        J=--force rejected  K=in-flight immunity
T69_DIR=""

t69_setup() {
  T69_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t69"
  mkdir -p "$T69_DIR" && cd "$T69_DIR" || exit 1
}

t69_mkrepo() {  # fresh git repo sandbox inside T69_DIR + cd into it
  local d="$T69_DIR/$1"
  mkdir -p "$d" && cd "$d" || exit 1
  git init -q . && git commit -q --allow-empty -m t69-seed
}

t69_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T69_DIR"; }

BOOKS="docs/coding-standards/00-general.md docs/coding-standards/shell.md docs/coding-standards/node.md docs/coding-standards/python.md"

t69_json_counts() {  # parse init-coding --json stdout -> "created=N skipped=N overwritten=N"
  python3 -c "
import json,sys
try:
    d=json.loads(sys.stdin.read())
    print('created=%d skipped=%d overwritten=%d' % (len(d['created']),len(d['skipped']),len(d['overwritten'])))
except Exception as e:
    print('BADJSON:'+str(e))"
}

t69_setup
trap 't69_teardown' EXIT
PASS=0; FAIL=0
echo "--- T69: gos init coding (D-58/R-07) ---"

# --- A: clean repo → all 4 books land under docs/coding-standards/ ---
t69_mkrepo plain
out=$(node "$GOS" init coding </dev/null 2>&1); rc=$?
assert_exit "A1 clean repo exit 0" 0 "$rc"
for f in $BOOKS; do
  if [ -f "$f" ]; then echo "  ✓ A2 seeded: $f"; PASS=$((PASS+1))
  else echo "  ✗ A2 missing: $f"; FAIL=$((FAIL+1)); fi
done
STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
assert_eq "A3 nothing auto-staged" "0" "$STAGED"
if [ -f .gos/state.json ]; then echo "  ✗ A4 init coding created state.json"; FAIL=$((FAIL+1))
else echo "  ✓ A4 no state.json created (verb, not task init)"; PASS=$((PASS+1)); fi

# --- B: every book carries an anchor/license attribution line ---
for f in $BOOKS; do
  if grep -q "CC-BY\|PSF\|Airbnb\|Google" "$f" 2>/dev/null; then echo "  ✓ B1 attribution line: $f"; PASS=$((PASS+1))
  else echo "  ✗ B1 no attribution line in: $f"; FAIL=$((FAIL+1)); fi
done

# --- C: seeded files are byte-identical to the masters (no substitution) ---
for f in $BOOKS; do
  m="$GOS_ROOT/templates/coding-standards/$(basename "$f")"
  if cmp -s "$f" "$m"; then echo "  ✓ C1 identical to master: $(basename "$f")"; PASS=$((PASS+1))
  else echo "  ✗ C1 differs from master: $(basename "$f")"; FAIL=$((FAIL+1)); fi
done

# --- D: --json machine report ---
t69_mkrepo jsonrepo
jout=$(node "$GOS" init coding --json </dev/null 2>/dev/null)
assert_contains "D1 json report (4 created / 0 / 0)" "created=4 skipped=0 overwritten=0" "$(printf '%s' "$jout" | t69_json_counts)"

# --- E: re-run idempotent — identical files all skip, nothing rewritten ---
t69_mkrepo idem
node "$GOS" init coding </dev/null >/dev/null 2>&1
( find docs/coding-standards -type f | sort | xargs sha256sum ) > "$T69_DIR/run1.sha"
jout=$(node "$GOS" init coding --json </dev/null 2>/dev/null)
assert_contains "E1 re-run json (0 created / 4 skipped / 0 overwritten)" "created=0 skipped=4 overwritten=0" "$(printf '%s' "$jout" | t69_json_counts)"
( find docs/coding-standards -type f | sort | xargs sha256sum ) > "$T69_DIR/run2.sha"
if cmp -s "$T69_DIR/run1.sha" "$T69_DIR/run2.sha"; then
  echo "  ✓ E2 re-run byte-identical (idempotent)"; PASS=$((PASS+1))
else echo "  ✗ E2 re-run changed files"; FAIL=$((FAIL+1)); fi
BAKS=$(find docs/coding-standards -name '*.gos-bak' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "E3 no .gos-bak on idempotent re-run" "0" "$BAKS"

# --- F: pre-existing conflicting file kept without --overwrite ---
t69_mkrepo conflict
mkdir -p docs/coding-standards
printf '# team-local python rules\n' > docs/coding-standards/python.md
out=$(node "$GOS" init coding </dev/null 2>&1); rc=$?
assert_exit "F1 conflicting file, non-interactive exit 0" 0 "$rc"
assert_eq "F2 user python.md kept" "# team-local python rules" "$(cat docs/coding-standards/python.md)"
for f in 00-general.md shell.md node.md; do
  if [ -f "docs/coding-standards/$f" ]; then echo "  ✓ F3 non-conflicting book still seeded: $f"; PASS=$((PASS+1))
  else echo "  ✗ F3 missing: $f"; FAIL=$((FAIL+1)); fi
done
if [ -f docs/coding-standards/python.md.gos-bak ]; then echo "  ✗ F4 backup written for a kept file"; FAIL=$((FAIL+1))
else echo "  ✓ F4 no backup when kept"; PASS=$((PASS+1)); fi
assert_contains "F5 human report marks kept" "kept (1)" "$out"

# --- G: --overwrite replaces the conflict, .gos-bak preserves the user copy ---
t69_mkrepo overflag
mkdir -p docs/coding-standards
printf '# user version\n' > docs/coding-standards/shell.md
jout=$(node "$GOS" init coding --overwrite --json </dev/null 2>/dev/null)
assert_contains "G1 --overwrite json (3 created / 0 skipped / 1 overwritten)" "created=3 skipped=0 overwritten=1" "$(printf '%s' "$jout" | t69_json_counts)"
assert_eq "G2 user version preserved in .gos-bak" "# user version" "$(cat docs/coding-standards/shell.md.gos-bak 2>/dev/null)"
if cmp -s docs/coding-standards/shell.md "$GOS_ROOT/templates/coding-standards/shell.md"; then
  echo "  ✓ G3 replaced with master content"; PASS=$((PASS+1))
else echo "  ✗ G3 content mismatch after overwrite"; FAIL=$((FAIL+1)); fi

# --- H: non-git dir refused ---
mkdir -p "$T69_DIR/nogit" && cd "$T69_DIR/nogit" || exit 1
out=$(GIT_CEILING_DIRECTORIES="$GOS_ROOT" node "$GOS" init coding </dev/null 2>&1); rc=$?
assert_exit "H1 non-git work-tree refused (exit 1)" 1 "$rc"
assert_contains "H2 hint suggests git init" "git init" "$out"
cd "$T69_DIR" || exit 1

# --- I: level-first escape hatch + stray positional refused ---
t69_mkrepo regression
out=$(node "$GOS" init 2 "t69 coding-themed intent" </dev/null 2>&1); rc=$?
assert_exit "I1 gos init 2 keeps original task semantics" 0 "$rc"
assert_contains "I1 summary keeps the word coding" "coding" "$(python3 -c "import json;print(json.load(open('.gos/state.json'))['intent']['summary'])")"

t69_mkrepo regression2
out=$(node "$GOS" init coding "stray intent" </dev/null 2>&1); rc=$?
assert_exit "I2 stray positional after coding refused" 1 "$rc"
assert_contains "I2 message explains the level-first escape hatch" "level" "$out"

# --- J: --force rejected (destructive semantics stay with task init) ---
t69_mkrepo forceflag
out=$(node "$GOS" init coding --force </dev/null 2>&1); rc=$?
assert_exit "J1 --force rejected for init coding" 1 "$rc"
assert_contains "J1 message points to --overwrite" "overwrite" "$out"

# --- K: in-flight task present — seeding still runs, state untouched ---
t69_mkrepo inflight
node "$GOS" init 1 "t69 in-flight task" </dev/null >/dev/null 2>&1
SHA_BEFORE=$(sha256sum .gos/state.json 2>/dev/null | cut -d' ' -f1)
out=$(node "$GOS" init coding </dev/null 2>&1); rc=$?
assert_exit "K1 seeding runs despite in-flight task" 0 "$rc"
SHA_AFTER=$(sha256sum .gos/state.json 2>/dev/null | cut -d' ' -f1)
assert_eq "K2 state.json untouched (byte-identical)" "$SHA_BEFORE" "$SHA_AFTER"

echo "--- T69 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
