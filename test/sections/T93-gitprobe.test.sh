#!/usr/bin/env bash
# gos-map:file bin/lib/core/gitprobe.cjs
# T93: gitprobe fail-closed probe module (§3.0 primitive for D-14/D-15/D-17).
# Facts asserted:
#   - isTracked = ls-files --cached UNION cat-file -e HEAD:<rel>; TOCTOU: a file
#     `git rm --cached`'d (index gone, HEAD blob alive) stays tracked via the
#     cat-file leg; wrong-case index twin with on-disk variant → true (doubt)
#   - ANY git failure (rc!=0, stderr chatter on rc=0, poisoned GIT_INDEX_FILE /
#     GIT_DIR env, not-a-repo cwd) → true + cached-failure marker exposed via
#     lastFailure() (single line, non-empty); the failure cache short-circuits
#     later probes and ignoredSet fails closed to the empty set
#   - ignoredSet: exactly ONE `status --porcelain -uall --ignored=matching`
#     call, `!!` records only
#   - canonicalRepoRel: realpath + case guard → repo-relative form; symlinked
#     input canonicalizes; outside-worktree and ENOENT → null
#   - surface exported through bin/lib/core/index.cjs spread-merge
# Standalone-safe: self-provisions env when not run under test/run-sections.sh.

T93_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T93_STANDALONE=1
  T93_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T93_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T93_SELFROOT"
  export TESTBASE="$(mktemp -d "$T93_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T93_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t93"
NOGIT_DIR="$TESTBASE/nogit-t93"
mkdir -p "$T93_DIR" && cd "$T93_DIR" || exit 1

t93_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T93_DIR" "$NOGIT_DIR"
  if [ "$T93_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t93_teardown EXIT

PASS=0
FAIL=0

echo "--- T93: gitprobe fail-closed probe module ---"

# --- L1: export surface — all four probes reachable through the core index ---
R1=$(node -e '
const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
const bad = [];
for (const n of ["isTracked", "ignoredSet", "canonicalRepoRel", "lastFailure"]) {
  if (typeof core[n] !== "function") bad.push(n + " not exported through core index");
}
if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
console.log("OK");
' 2>&1)
if [ "$R1" = "OK" ]; then
  echo "  ✓ L1 exports: isTracked/ignoredSet/canonicalRepoRel/lastFailure via core index"; PASS=$((PASS+1))
else
  echo "  ✗ L1 exports: $R1"; FAIL=$((FAIL+1))
fi

# --- sandbox: one seeded worktree with a HEAD commit ---
git init -q .
printf 'ignored.log\n' > .gitignore
printf 'a\n' > tracked.txt
mkdir -p sub && printf 'n\n' > sub/nested.txt
git add .gitignore tracked.txt sub/nested.txt
git commit -qm t93-seed
printf 'x\n' > ignored.log
printf 'u\n' > untracked.txt

# --- L2: healthy triage — index leg true, negative legs false, cache clean ---
R2=$(node -e '
const gp = require(process.env.GOS_ROOT + "/bin/lib/core/gitprobe.cjs");
const bad = [];
if (gp.isTracked("tracked.txt") !== true) bad.push("tracked.txt not tracked");
if (gp.isTracked("sub/nested.txt") !== true) bad.push("nested not tracked");
if (gp.isTracked(process.cwd() + "/tracked.txt") !== true) bad.push("absolute input not tracked");
if (gp.isTracked("untracked.txt") !== false) bad.push("untracked reported tracked");
if (gp.isTracked("UNTRACKED.TXT") !== false) bad.push("wrong-case untracked reported tracked");
if (gp.isTracked("TRACKED.TXT") !== true) bad.push("wrong-case index twin with disk variant not tracked");
if (gp.lastFailure() !== null) bad.push("healthy probes polluted failure cache: " + gp.lastFailure());
if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
console.log("OK");
' 2>&1)
if [ "$R2" = "OK" ]; then
  echo "  ✓ L2 healthy: index leg true; untracked + wrong-case-untracked false; cache clean"; PASS=$((PASS+1))
else
  echo "  ✗ L2 healthy: $R2"; FAIL=$((FAIL+1))
fi

# --- L3: TOCTOU — rm --cached drops the index entry, HEAD blob keeps the truth ---
git rm -q --cached tracked.txt
R3=$(node -e '
const gp = require(process.env.GOS_ROOT + "/bin/lib/core/gitprobe.cjs");
const bad = [];
if (gp.isTracked("tracked.txt") !== true) bad.push("rm --cached file lost from HEAD leg");
if (gp.isTracked("untracked.txt") !== false) bad.push("negative cat-file leg reported tracked");
if (gp.lastFailure() !== null) bad.push("expected-negative stderr poisoned the cache: " + gp.lastFailure());
if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
console.log("OK");
' 2>&1)
if [ "$R3" = "OK" ]; then
  echo "  ✓ L3 TOCTOU: rm --cached stays tracked via cat-file HEAD leg; clean negative stays false"; PASS=$((PASS+1))
else
  echo "  ✗ L3 TOCTOU: $R3"; FAIL=$((FAIL+1))
fi

# --- L4: fail-closed on poisoned index — /dev/null index, cached marker ---
R4=$(GIT_INDEX_FILE=/dev/null node -e '
const gp = require(process.env.GOS_ROOT + "/bin/lib/core/gitprobe.cjs");
const bad = [];
if (gp.isTracked("untracked.txt") !== true) bad.push("GIT_INDEX_FILE=/dev/null did not fail closed");
const m = gp.lastFailure();
if (typeof m !== "string" || m.length === 0 || m.includes("\n")) bad.push("bad marker: " + JSON.stringify(m));
if (gp.isTracked("untracked.txt") !== true) bad.push("cached failure short-circuit broken");
if (gp.lastFailure() !== m) bad.push("marker not stable across probes");
if (gp.ignoredSet().size !== 0) bad.push("ignoredSet must fail closed to empty set");
if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
console.log("OK");
' 2>&1)
if [ "$R4" = "OK" ]; then
  echo "  ✓ L4 poison index: untracked → true + cached marker; ignoredSet fails closed empty"; PASS=$((PASS+1))
else
  echo "  ✗ L4 poison index: $R4"; FAIL=$((FAIL+1))
fi

# --- L5: fail-closed variants — dead GIT_DIR, stderr chatter, not-a-repo cwd ---
R5A=$(GIT_DIR="$HOME" node -e '
const gp = require(process.env.GOS_ROOT + "/bin/lib/core/gitprobe.cjs");
const ok = gp.isTracked("untracked.txt") === true && typeof gp.lastFailure() === "string" && gp.lastFailure().length > 0;
if (!ok) { console.error("GIT_DIR non-repo: got " + gp.isTracked("untracked.txt") + " marker=" + JSON.stringify(gp.lastFailure())); process.exit(1); }
console.log("OK");
' 2>&1)
R5B=$(GIT_TRACE=1 node -e '
const gp = require(process.env.GOS_ROOT + "/bin/lib/core/gitprobe.cjs");
const ok = gp.isTracked("untracked.txt") === true && typeof gp.lastFailure() === "string" && gp.lastFailure().length > 0;
if (!ok) { console.error("stderr chatter on rc=0: got " + gp.isTracked("untracked.txt") + " marker=" + JSON.stringify(gp.lastFailure())); process.exit(1); }
console.log("OK");
' 2>&1)
mkdir -p "$NOGIT_DIR"
R5C="$(cd "$NOGIT_DIR" && GIT_CEILING_DIRECTORIES="$TESTBASE" node -e '
const gp = require(process.env.GOS_ROOT + "/bin/lib/core/gitprobe.cjs");
const ok = gp.isTracked("untracked.txt") === true && typeof gp.lastFailure() === "string" && gp.lastFailure().length > 0;
if (!ok) { console.error("not-a-repo cwd: got " + gp.isTracked("untracked.txt") + " marker=" + JSON.stringify(gp.lastFailure())); process.exit(1); }
console.log("OK");
' 2>&1)"
if [ "$R5A" = "OK" ] && [ "$R5B" = "OK" ] && [ "$R5C" = "OK" ]; then
  echo "  ✓ L5 fail-closed variants: dead GIT_DIR (rc!=0) + stderr chatter (GIT_TRACE) + not-a-repo cwd"; PASS=$((PASS+1))
else
  echo "  ✗ L5 fail-closed variants: a=[$R5A] b=[$R5B] c=[$R5C]"; FAIL=$((FAIL+1))
fi

# --- L6: ignoredSet — exactly one porcelain -uall --ignored=matching call ---
R6=$(node -e '
const cp = require("node:child_process");
const calls = [];
const orig = cp.spawnSync;
cp.spawnSync = function (...a) { calls.push([a[0], ...(a[1] || [])].join(" ")); return orig.apply(this, a); };
const gp = require(process.env.GOS_ROOT + "/bin/lib/core/gitprobe.cjs");
const s = gp.ignoredSet();
cp.spawnSync = orig;
const bad = [];
if (!(s instanceof Set)) bad.push("not a Set");
if (calls.length !== 1) bad.push("expected exactly 1 git call, got " + calls.length + ": " + calls.join(" | "));
const one = calls[0] || "";
for (const f of ["status", "--porcelain", "-uall", "--ignored=matching"]) {
  if (!one.includes(f)) bad.push("call missing " + f);
}
if (!s.has("ignored.log")) bad.push("ignored.log missing from set");
for (const p of ["untracked.txt", "tracked.txt", ".gitignore"]) {
  if (s.has(p)) bad.push(p + " wrongly in ignored set");
}
if (gp.lastFailure() !== null) bad.push("failure cache polluted: " + gp.lastFailure());
if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
console.log("OK");
' 2>&1)
if [ "$R6" = "OK" ]; then
  echo "  ✓ L6 ignoredSet: one porcelain -uall --ignored=matching call; !! records only"; PASS=$((PASS+1))
else
  echo "  ✗ L6 ignoredSet: $R6"; FAIL=$((FAIL+1))
fi

# --- L7: canonicalRepoRel — realpath + case guard, outside/ENOENT → null ---
mkdir -p sub && ln -sfn sub link
printf 's\n' > sub/real.txt
touch "$HOME/outside-t93.txt"
R7=$(node -e '
const gp = require(process.env.GOS_ROOT + "/bin/lib/core/gitprobe.cjs");
const cwd = process.cwd();
const bad = [];
if (gp.canonicalRepoRel(cwd + "/tracked.txt") !== "tracked.txt") bad.push("absolute → repo-rel");
if (gp.canonicalRepoRel("sub/../tracked.txt") !== "tracked.txt") bad.push("dot-segment not normalized");
if (gp.canonicalRepoRel(cwd + "/link/real.txt") !== "sub/real.txt") bad.push("symlink not canonicalized");
if (gp.canonicalRepoRel(cwd) !== "") bad.push("worktree root should map to empty rel");
if (gp.canonicalRepoRel(process.env.HOME + "/outside-t93.txt") !== null) bad.push("outside-worktree not null");
if (gp.canonicalRepoRel("/definitely/not/here/t93") !== null) bad.push("ENOENT not null");
if (gp.lastFailure() !== null) bad.push("canonicalization polluted failure cache: " + gp.lastFailure());
if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
console.log("OK");
' 2>&1)
if [ "$R7" = "OK" ]; then
  echo "  ✓ L7 canonicalRepoRel: abs/dot-segment/symlink canonical; root empty; outside+ENOENT null"; PASS=$((PASS+1))
else
  echo "  ✗ L7 canonicalRepoRel: $R7"; FAIL=$((FAIL+1))
fi

echo "--- T93 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
