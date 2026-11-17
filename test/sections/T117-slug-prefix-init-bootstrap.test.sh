#!/usr/bin/env bash
# gos-map:fn bin/lib/task/context.cjs#fn:archiveSlugParts bin/lib/task/init.cjs#fn:cmdInitProject
# gos-map:cmd init,archive
# slug-prefix + bootstrap lane — init --project writes the container (views,
# project.json, the lv4.json repo marker) and NEVER a task state; a repo with
# Lv4 trace refuses re-bootstrap unless --fresh resets the container. The
# archive slug prefix tracks the milestone lifecycle: an open milestone lends
# its stored name, the closed-not-reopened gap carries no prefix at all, and
# repos without a milestone object keep the permanent package-version prefix.
PASS=0; FAIL=0
command -v assert_exit >/dev/null || assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected exit $expected, got '${actual:-<none>}')"; FAIL=$((FAIL+1)); fi
}
command -v assert_contains >/dev/null || assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected: '$expected')"; echo "    actual: ${actual:0:200}"; FAIL=$((FAIL+1)); fi
}
command -v assert_file >/dev/null || assert_file() {
  local label="$1" fpath="$2"
  if [ -n "$fpath" ] && [ -e "$fpath" ]; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (missing: '${fpath:-<none>}')"; FAIL=$((FAIL+1)); fi
}
command -v assert_eq >/dev/null || assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "  ✓ $label"; PASS=$((PASS+1)); else echo "  ✗ $label (expected: '$expected', got: '$actual')"; FAIL=$((FAIL+1)); fi
}
GOS="${GOS:-$(git rev-parse --show-toplevel 2>/dev/null)/bin/gos.cjs}"
T117_DIR=""
T117_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VER="${T117_VER:-$(node -e "console.log(require(process.argv[1] + '/package.json').version)" "$T117_SELFROOT")}"
UDATE="$(date -u +%F)"

t117_setup() {
  [ -n "$TESTBASE" ] || TESTBASE="$(mktemp -d)"
  T117_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t117"
  mkdir -p "$T117_DIR" && cd "$T117_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/.lock\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
  export GOS_SKIP_SHIP_CHECK=1
}

t117_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T117_DIR"; }

# Bring the claimed phase task to the archive point: DONE stage, spec on
# disk, user approval recorded, lessons entry present.
t117_archive_ready() {
  node -e "
const fs = require('fs');
const s = JSON.parse(fs.readFileSync('.gos/state.json', 'utf8'));
s.current_stage = 'DONE';
s.approvals = { ARCHIVE: 'ok' };
s.spec_path = '.gos/task/$1/spec.md';
fs.writeFileSync('.gos/state.json', JSON.stringify(s, null, 2));"
  mkdir -p ".gos/task/$1" && echo "spec $1" > ".gos/task/$1/spec.md"
  mkdir -p .gos && echo "- [$(date -u +%F)] fixture scene → fixture lesson" >> .gos/lessons.md
}

echo "--- T117: slug prefix + init bootstrap ---"

# ===== bootstrap writes the container, never task state =====
t117_setup
set +e; OUT=$(node "$GOS" init --project 2>&1); RC=$?; set -e
assert_exit "init --project exits 0" 0 "$RC"
assert_contains "bootstrap banner names the truth source" "Lv4 project container bootstrapped (truth source: .gos/project/project.json; no task state is written here)" "$OUT"
assert_file "project.json created" ".gos/project/project.json"
assert_file "lv4.json repo marker created" ".gos/project/lv4.json"
assert_file "ROADMAP view created" ".gos/project/ROADMAP.md"
assert_file "DECISIONS view created" ".gos/project/DECISIONS.md"
assert_file "REQUIREMENTS view created" ".gos/project/REQUIREMENTS.md"
assert_file "PROJECT.md skeleton created" ".gos/project/PROJECT.md"
if [ ! -e .gos/state.json ]; then
  echo "  ✓ bootstrap wrote no state.json"; PASS=$((PASS+1))
else
  echo "  ✗ bootstrap leaked a task state.json"; FAIL=$((FAIL+1))
fi
MARKER=$(cat .gos/project/lv4.json 2>/dev/null)
assert_eq "marker line is the stable lv4 JSON" '{"lv4":true}' "$MARKER"
MS=$(node -e "
const m = require('./.gos/project/project.json').milestone;
console.log([m.name, typeof m.opened_at === 'string', 'closed_at' in m].join('|'))")
assert_eq "default milestone opened, still open" "milestone-1|true|false" "$MS"

# ===== trace refusal + --fresh reset =====
set +e; OUT=$(node "$GOS" init --project 2>&1); RC=$?; set -e
assert_exit "re-bootstrap without fresh refuses" 1 "$RC"
assert_contains "refusal names the Lv4 trace" "Lv4 trace already present" "$OUT"
assert_contains "refusal names the fresh escape" "re-bootstrap requires --fresh" "$OUT"
node "$GOS" phase add "P1: seeded" --goal g >/dev/null 2>&1
set +e; OUT=$(node "$GOS" init --project --fresh 2>&1); RC=$?; set -e
assert_exit "fresh re-bootstrap exits 0" 0 "$RC"
assert_contains "fresh reset banner" "resets the existing Lv4 container" "$OUT"
RESET=$(node -e "
const p = require('./.gos/project/project.json');
console.log([p.phases.length, p.decisions.length, p.milestone.name, 'closed_at' in p.milestone].join('|'))")
assert_eq "fresh reset restored an empty container with a fresh open milestone" "0|0|milestone-1|false" "$RESET"
t117_teardown

# ===== bootstrap name forms: --project=<name>, positional <name>, misuse dies =====
t117_setup
set +e; OUT=$(node "$GOS" init --project=flag-beta 2>&1); RC=$?; set -e
assert_exit "init --project=<name> routes to the bootstrap lane" 0 "$RC"
if [ ! -e .gos/state.json ]; then
  echo "  ✓ flag form wrote no state.json"; PASS=$((PASS+1))
else
  echo "  ✗ flag form leaked a task state.json"; FAIL=$((FAIL+1))
fi
assert_eq "flag form stores the sanitized name" "flag-beta" "$(node -e "console.log(require('./.gos/project/project.json').milestone.name)")"
set +e; OUT=$(node "$GOS" init --project positional-beta --fresh 2>&1); RC=$?; set -e
assert_exit "positional name form bootstraps" 0 "$RC"
assert_eq "positional form stores the name" "positional-beta" "$(node -e "console.log(require('./.gos/project/project.json').milestone.name)")"
set +e; OUT=$(node "$GOS" init --project a b --fresh 2>&1); RC=$?; set -e
assert_exit "two positionals die" 1 "$RC"
assert_contains "two positionals refusal names the cap" "at most one milestone name" "$OUT"
set +e; OUT=$(node "$GOS" init --project=flag-beta extra --fresh 2>&1); RC=$?; set -e
assert_exit "name given twice dies" 1 "$RC"
assert_contains "double-name refusal" "name given twice" "$OUT"
t117_teardown

# ===== open-milestone name prefix rides the archive slug =====
t117_setup
node "$GOS" init --project --project=pub-beta >/dev/null 2>&1
node "$GOS" phase add "P1: core" --goal "goal one" >/dev/null 2>&1
node "$GOS" phase claim 0 >/dev/null 2>&1
t117_archive_ready t1
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "archive under an open milestone exits 0" 0 "$RC"
assert_file "slug carries the publicized milestone name" ".gos/archive/$UDATE-pub-beta-phase-p1-goal-one"
STAMP=$(node -e "
const p = require('./.gos/project/project.json');
const ph = p.phases[0];
console.log([ph.status, ph.task_ref, typeof ph.completed_at === 'string' && ph.completed_at.length >= 20 ? 'iso' : 'bad'].join('|'))")
assert_eq "phase entry stamped (status|task_ref=archive basename|completed_at ISO)" "done|$UDATE-pub-beta-phase-p1-goal-one|iso" "$STAMP"

# ===== closed-not-reopened gap: no prefix at all =====
node "$GOS" phase add "P2: second" --goal "goal two" >/dev/null 2>&1
node "$GOS" phase mark-done 0 >/dev/null 2>&1
node "$GOS" init 3 "close holder" >/dev/null 2>&1
node "$GOS" approve milestone-close >/dev/null 2>&1
node "$GOS" milestone close --yes >/dev/null 2>&1
node "$GOS" phase claim 0 >/dev/null 2>&1
t117_archive_ready t2
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "archive in the closed gap exits 0" 0 "$RC"
assert_file "gap slug carries no prefix and no version" ".gos/archive/$UDATE-phase-p2-goal-two"
if ls -d .gos/archive/$UDATE-v*-phase-p2-goal-two >/dev/null 2>&1; then
  echo "  ✗ gap slug leaked a version prefix"; FAIL=$((FAIL+1))
else
  echo "  ✓ gap slug has neither milestone nor version prefix"; PASS=$((PASS+1))
fi

# ===== milestone-less repo: permanent package-version prefix =====
node -e "
const fs = require('fs');
const p = JSON.parse(fs.readFileSync('.gos/project/project.json', 'utf8'));
delete p.milestone;
fs.writeFileSync('.gos/project/project.json', JSON.stringify(p, null, 2));"
node "$GOS" phase add "P3: legacy lane" --goal "goal three" >/dev/null 2>&1
node "$GOS" phase claim 1 >/dev/null 2>&1
t117_archive_ready t3
set +e; OUT=$(node "$GOS" archive 2>&1); RC=$?; set -e
assert_exit "archive without a milestone object exits 0" 0 "$RC"
assert_file "legacy slug carries the package version prefix (read parametrically)" ".gos/archive/$UDATE-v$VER-phase-p3-goal-three"
t117_teardown

echo "--- T117 done: PASS=$PASS FAIL=$FAIL ---"
[ "$FAIL" -eq 0 ] || exit 1
