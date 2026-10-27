#!/usr/bin/env bash
# gos-map:cmd track
# T98a: gos track — validation steps 1-5 + tri-store/target pre-scan
# + .gos/.gitignore relative-anchored negation surgery + census-if-present edit
# + git add (flip core; manifest/backups/adopt/no-op are T7b on this seam).
# Facts asserted:
#   - flip core green WITHOUT census: ignored target (root .gitignore file-level
#     exclude) → .gos/.gitignore negation line `!<rel>`, check-ignore flips to
#     rc!=0, target staged via git add, no census.json created (census-if-present)
#   - flip core green WITH census: exact git:false entry flips git:true,
#     census.json itself staged
# - brownfield not-ignored target : no surgery (advisory), covering
#     git:false dir entry untouched, EXACT census key added git:true, staged
#   - negatives die (validation, die-before-touch): .env secrets, symlink,
#     never-track zone (.gos/cache/**), unborn HEAD, case collision on disk,
#     already-tracked precondition (adopt/no-op hint wording)
#   - pre-scan die-before-touch: tracked concerns.md carrying CJK blocks ANY
#     flip (offending line reported); target CJK dies; sanitize table hit
#     (/home/) dies with the hit line
#   - registry 3-way: COMMANDS.track + KNOWN_CASES/WRITE_CMDS + gos.cjs
#     dispatch + `track --json` no-target help envelope rc=0 (byte-0 JSON)
# - self-repo negative: knowledge stores stay git:false in the real
#     repo census after this wave (self-repo opts out of tracking)
# Env: GOS, TESTBASE, assert helpers sourced by runner (standalone-safe).
T98A_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T98A_STANDALONE=1
  T98A_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T98A_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T98A_SELFROOT"
  export TESTBASE="$(mktemp -d "$T98A_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T98A_DIR=""

t98a_fresh() {
  T98A_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t98a"
  mkdir -p "$T98A_DIR" && cd "$T98A_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
  # write-class dispatch guard: TESTBASE sits inside GOS_ROOT (an ancestor with
 # .gos/state.json) — every fixture carries its own task state ( pattern).
  node "$GOS" init 1 "t98a track fixture" >/dev/null 2>&1
}

t98a_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T98A_DIR"; }

# counter-bumping assert helpers (runner-parity output; own exit gate)
assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if [ -z "${expected:-}" ]; then
    echo "  ✗ $label (empty pattern always matches — use assert_file/assert_eq)"; FAIL=$((FAIL+1))
  elif echo "$actual" | grep -q "$expected"; then
    echo "  ✓ $label"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected: '$expected')"
    echo "    actual: ${actual:0:160}"; FAIL=$((FAIL+1))
  fi
}
assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ -n "${actual:-}" ] && [ "$actual" = "$expected" ]; then
    echo "  ✓ $label (exit $actual)"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected exit $expected, got '${actual:-<none>}')"; FAIL=$((FAIL+1))
  fi
}
assert_file() {
  local label="$1" fpath="$2"
  if [ -n "$fpath" ] && [ -e "$fpath" ]; then
    echo "  ✓ $label"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (missing: '${fpath:-<none>}')"; FAIL=$((FAIL+1))
  fi
}
assert_no_file() {
  local label="$1" fpath="$2"
  if [ -n "$fpath" ] && [ ! -e "$fpath" ]; then
    echo "  ✓ $label"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (unexpectedly present: '${fpath:-<none>}')"; FAIL=$((FAIL+1))
  fi
}
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ✓ $label"; PASS=$((PASS+1))
  else
    echo "  ✗ $label (expected: '$expected', got: '$actual')"; FAIL=$((FAIL+1))
  fi
}

PASS=0
FAIL=0

echo "--- T98a: gos track — validation + surgery + flip core (D-15/D-14) ---"

# --- C1: flip core green WITHOUT census (root .gitignore file-level exclude) ---
t98a_fresh
printf ".gos/concerns.md\n" >> .gitignore
mkdir -p .gos && printf '# Concerns (curated worry list)\n\nclean english worry text\n' > .gos/concerns.md
git check-ignore -q .gos/concerns.md
assert_exit "C1 fixture: target ignored before flip" "0" "$?"
set +e; OUT=$(node "$GOS" track .gos/concerns.md 2>&1); RC=$?; set -e
assert_exit "C1 track exits 0" "0" "$RC"
assert_contains "C1 success line names the target" ".gos/concerns.md" "$OUT"
assert_file "C1 .gos/.gitignore created by surgery" ".gos/.gitignore"
NEG=$(grep -c '^!/concerns\.md$' .gos/.gitignore || true)
assert_eq "C1 negation is relative-anchored (!/concerns.md)" "1" "$NEG"
set +e; git check-ignore -q .gos/concerns.md; CIR=$?; set -e
if [ "$CIR" -ne 0 ]; then
  echo "  ✓ C1 check-ignore flips to not-ignored (rc=$CIR)"; PASS=$((PASS+1))
else
  echo "  ✗ C1 target still ignored after surgery"; FAIL=$((FAIL+1))
fi
set +e; git ls-files --error-unmatch -- .gos/concerns.md >/dev/null 2>&1; LSR=$?; set -e
assert_exit "C1 target staged via git add (index)" "0" "$LSR"
STAGED=$(git diff --cached --name-only)
assert_contains "C1 target in staged diff" ".gos/concerns.md" "$STAGED"
assert_contains "C1 .gos/.gitignore staged alongside" ".gos/.gitignore" "$STAGED"
assert_no_file "C1 census-if-present: no census.json created" "census.json"
t98a_teardown

# --- C2: flip core green WITH census fixture (exact git:false entry flips) ---
t98a_fresh
printf ".gos/concerns.md\n" >> .gitignore
mkdir -p .gos && printf 'census fixture content\n' > .gos/concerns.md
cat > census.json <<'CENEOF'
{
  "schema_version": 1,
  "_doc": "fixture census",
  "entries": {
    ".gos/concerns.md": { "git": false, "npm": false, "note": "machine-local (gitignored)" }
  },
  "dispositions": []
}
CENEOF
git add census.json && git commit -q -m census
set +e; OUT=$(node "$GOS" track .gos/concerns.md 2>&1); RC=$?; set -e
assert_exit "C2 track exits 0 with census present" "0" "$RC"
FLIP=$(python3 -c 'import json; print(json.load(open("census.json"))["entries"].get(".gos/concerns.md", {}).get("git"))' 2>&1 || true)
assert_eq "C2 census entry flipped git:true" "True" "$FLIP"
STAGED=$(git diff --cached --name-only)
assert_contains "C2 census.json staged by the flip" "census.json" "$STAGED"
assert_contains "C2 target staged" ".gos/concerns.md" "$STAGED"
t98a_teardown

# --- C3: brownfield not-ignored target — no surgery, covering entry untouched ---
t98a_fresh
mkdir -p .gos/team && printf 'shared roster notes\n' > .gos/team/roster.md
cat > census.json <<'CENEOF'
{
  "schema_version": 1,
  "_doc": "fixture census",
  "entries": {
    ".gos/team": { "git": false, "npm": false, "note": "team drafts stay local" }
  },
  "dispositions": []
}
CENEOF
git add census.json && git commit -q -m census
set +e; OUT=$(node "$GOS" track .gos/team/roster.md 2>&1); RC=$?; set -e
assert_exit "C3 not-ignored target tracks without surgery" "0" "$RC"
assert_contains "C3 advisory: no gitignore surgery needed" "no gitignore surgery" "$OUT"
assert_no_file "C3 no .gos/.gitignore created" ".gos/.gitignore"
EXACT=$(python3 -c 'import json; e=json.load(open("census.json"))["entries"]; print(e.get(".gos/team/roster.md", {}).get("git"), e[".gos/team"]["git"])' 2>&1 || true)
assert_eq "C3 exact key added git:true, covering dir entry stays false" "True False" "$EXACT"
set +e; git ls-files --error-unmatch -- .gos/team/roster.md >/dev/null 2>&1; LSR=$?; set -e
assert_exit "C3 not-ignored target staged" "0" "$LSR"
t98a_teardown

# --- N1: .env secrets negative (die-before-touch) ---
t98a_fresh
mkdir -p .gos && printf 'API_TOKEN=hush\n' > .gos/.env
set +e; OUT=$(node "$GOS" track .gos/.env 2>&1); RC=$?; set -e
assert_exit "N1 .env target dies" "1" "$RC"
assert_contains "N1 secrets wording" "secrets" "$OUT"
t98a_teardown

# --- N2: symlink negative (die-before-touch; link resolves INSIDE .gos) ---
t98a_fresh
mkdir -p .gos && printf 'real regular file\n' > .gos/real.md
ln -s real.md .gos/link.md
set +e; OUT=$(node "$GOS" track .gos/link.md 2>&1); RC=$?; set -e
assert_exit "N2 symlinked target dies" "1" "$RC"
assert_contains "N2 symlink wording" "symlink" "$OUT"
t98a_teardown

# --- N3: never-track zone negative (.gos/cache/**) ---
t98a_fresh
mkdir -p .gos/cache && printf '{}\n' > .gos/cache/deps.json
set +e; OUT=$(node "$GOS" track .gos/cache/deps.json 2>&1); RC=$?; set -e
assert_exit "N3 never-track zone dies" "1" "$RC"
assert_contains "N3 zone wording names .gos/cache" ".gos/cache" "$OUT"
t98a_teardown

# --- N4: unborn HEAD negative ---
T98A_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t98a"
mkdir -p "$T98A_DIR/.gos" && cd "$T98A_DIR" || exit 1
git init -q .
printf '{}' > .gos/state.json   # satisfies the write-class anchor guard; HEAD stays unborn
printf 'unborn target\n' > .gos/concerns.md
set +e; OUT=$(node "$GOS" track .gos/concerns.md 2>&1); RC=$?; set -e
assert_exit "N4 unborn repo dies" "1" "$RC"
assert_contains "N4 unborn teaching" "no commits" "$OUT"
t98a_teardown

# --- N5: case collision on disk negative ---
t98a_fresh
mkdir -p .gos && printf 'lower note\n' > .gos/notes.md && printf 'upper note\n' > .gos/NOTES.md
set +e; OUT=$(node "$GOS" track .gos/notes.md 2>&1); RC=$?; set -e
assert_exit "N5 case-collision target dies" "1" "$RC"
assert_contains "N5 case-collision wording" "case" "$OUT"
t98a_teardown

# --- N6: already-tracked target → adopt bookkeeping (T7b landed : the
# T7a die is replaced by {adopted:true} manifest record + exit 0; deep
# adopt/no-op/rollback coverage lives in T98b) ---
t98a_fresh
mkdir -p .gos && printf 'already tracked content\n' > .gos/concerns.md
git add -f .gos/concerns.md && git commit -q -m pretrack
set +e; OUT=$(node "$GOS" track .gos/concerns.md 2>&1); RC=$?; set -e
assert_exit "N6 legacy-tracked target adopts (exit 0)" "0" "$RC"
assert_contains "N6 adopt wording" "adopt" "$OUT"
AREC=$(grep -c '"adopted": *true' .gos/track-manifest.json || true)
assert_eq "N6 adopt record written to the manifest" "1" "$AREC"
t98a_teardown

# --- P1: tri-store pre-scan — tracked concerns.md with CJK blocks ANY flip ---
t98a_fresh
printf ".gos/concerns.md\n.gos/other.md\n" >> .gitignore
mkdir -p .gos && printf -- '- [2026-10-22] 团队协作中文担忧内容\n' > .gos/concerns.md
printf 'clean english note\n' > .gos/other.md
git add -f .gos/concerns.md && git commit -q -m zhstore
set +e; OUT=$(node "$GOS" track .gos/other.md 2>&1); RC=$?; set -e
assert_exit "P1 tracked CJK store blocks the flip" "1" "$RC"
assert_contains "P1 die names concerns.md" "concerns.md" "$OUT"
assert_contains "P1 die reports the offending line" "中文担忧" "$OUT"
set +e; git ls-files --error-unmatch -- .gos/other.md >/dev/null 2>&1; LSR=$?; set -e
if [ "$LSR" -ne 0 ]; then
  echo "  ✓ P1 die-before-touch: target NOT staged"; PASS=$((PASS+1))
else
  echo "  ✗ P1 target staged despite pre-scan die"; FAIL=$((FAIL+1))
fi
t98a_teardown

# --- P2: target CJK pre-scan dies with the line ---
t98a_fresh
printf ".gos/zh-note.md\n" >> .gitignore
mkdir -p .gos && printf 'good line\n中文目标文件\n' > .gos/zh-note.md
set +e; OUT=$(node "$GOS" track .gos/zh-note.md 2>&1); RC=$?; set -e
assert_exit "P2 CJK target dies" "1" "$RC"
assert_contains "P2 die reports the CJK line" "中文目标文件" "$OUT"
t98a_teardown

# --- P3: sanitize table hit dies with the hit line ---
t98a_fresh
printf ".gos/leak.md\n" >> .gitignore
mkdir -p .gos && printf 'shared doc\nsee /home/alice/notes for details\n' > .gos/leak.md
set +e; OUT=$(node "$GOS" track .gos/leak.md 2>&1); RC=$?; set -e
assert_exit "P3 sanitize hit dies" "1" "$RC"
assert_contains "P3 die reports the /home/ pattern" "/home/" "$OUT"
assert_contains "P3 die reports the hit line" "/home/alice/notes" "$OUT"
t98a_teardown

# --- R1: registry 3-way sync (COMMANDS + registry-consts + gos.cjs dispatch) ---
REG=$(node -e '
  const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
  const rc = require(process.env.GOS_ROOT + "/bin/lib/nav/registry-consts.cjs");
  const bad = [];
  const e = core.COMMANDS.track;
  if (!e) bad.push("COMMANDS.track missing");
  else {
    if (e.class !== "write") bad.push("COMMANDS.track class != write");
    if (!e.usage) bad.push("COMMANDS.track usage empty");
    if (!e.next || !e.next.length) bad.push("COMMANDS.track next empty");
  }
  if (!rc.KNOWN_CASES.includes("track")) bad.push("KNOWN_CASES missing track");
  if (!rc.WRITE_CMDS.has("track")) bad.push("WRITE_CMDS missing track");
  if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
  console.log("OK");
' 2>&1)
assert_eq "R1 COMMANDS + registry-consts carry track" "OK" "$REG"
DISP=$(grep -c "case 'track':" "$GOS_ROOT/bin/gos.cjs" || true)
assert_eq "R1 gos.cjs dispatch routes track" "1" "$DISP"
WIRE=$(grep -c "require('./track.cjs')" "$GOS_ROOT/bin/lib/ops/index.cjs" || true)
assert_eq "R1 ops index wiring present" "1" "$WIRE"
HELP=$(node "$GOS" help track 2>&1)
assert_contains "R1 help renders track usage" "gos track" "$HELP"
KC=$(grep "^const KNOWN_CASES" "$GOS_ROOT/bin/lib/nav/registry-consts.cjs" | grep -c "'track'" || true)
assert_eq "R1 registry-consts literal grep: track in KNOWN_CASES" "1" "$KC"

# --- R2: track --json no-target help envelope (rc=0, byte-0 JSON) + usage die ---
t98a_fresh
set +e; ENV_OUT=$(node "$GOS" track --json 2>/dev/null); RC=$?; set -e
assert_exit "R2 track --json (no target) exits 0" "0" "$RC"
ENVCHK=$(printf '%s' "$ENV_OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d.get("command") == "track", d
assert d.get("usage"), d
assert d.get("scope"), d
print("OK")
' 2>&1)
assert_eq "R2 envelope is byte-0 JSON with command/usage/scope" "OK" "$ENVCHK"
set +e; OUT=$(node "$GOS" track 2>&1); RC=$?; set -e
assert_exit "R2 bare track usage-dies" "1" "$RC"
assert_contains "R2 usage die names the command" "Usage: gos track" "$OUT"
set +e; OUT=$(node "$GOS" track .gos/concerns.md extra 2>&1); RC=$?; set -e
assert_exit "R2 extra positional dies" "1" "$RC"
t98a_teardown

# --- R3: self-repo negative — knowledge stores stay git:false in census
SELF=$(python3 -c '
import json, os
c = json.load(open(os.path.join(os.environ["GOS_ROOT"], "census.json")))
bad = []
for k in (".gos/concerns.md", ".gos/lessons.json", ".gos/lessons.md"):
    e = c["entries"].get(k)
    v = e.get("git") if e else None
    if v is not False:
        bad.append(f"{k}: git={v}")
print("; ".join(bad) if bad else "OK")
' 2>&1)
assert_eq "R3 self-repo census: knowledge stores stay git:false (D-14)" "OK" "$SELF"

if [ "$T98A_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi

echo "--- T98a summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
