#!/usr/bin/env bash
# gos-map:none
# gos-tier:main
# Branch reap proof section -- the reaping verdicts and guards of
# `gos branch reap` proven on fixture repos only (real-repo dry-run moves to
# a machine-local verification step: the real branch set moves as PRs land).
# Case map:
#   C1  replace-ref refusal -- a non-empty refs/replace/* refuses outright
#       before any verdict, loud failure, zero mutation
#   C2  stale-base refusal -- a --base that does not resolve fails loud,
#       zero mutation
#   C3  live-lock refusal -- a planted live run lock (real hostname, real
#       boot id, live pid) refuses --apply; dry-run needs no lock
#   C4  chain/* exemption -- a chain/ branch whose content IS landed reads
#       keep/chain-namespace and survives --apply
#   C5  worktree exemption -- a content-landed branch checked out in a
#       linked worktree reads keep/worktree-checked-out and survives --apply
#   C6  ref-revive past aggressive gc -- after --apply, refs/reaped/* pins
#       the commit through `git gc --prune=now --aggressive` and the printed
#       revive argv-array restores the branch at the original sha
#   C7  JSON shape -- dry-run stdout is strict JSON; per-branch action is
#       one of delete/manual/keep; revive commands are string argv arrays
# Per case: sandbox HOME + XDG_DATA_HOME + a fresh fixture repo under
# TESTBASE. Standalone-safe: self-provisions env when not under
# test/run-sections.sh.

T121_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T121_STANDALONE=1
  T121_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T121_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T121_SELFROOT"
  export TESTBASE="$(mktemp -d "$T121_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T121_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t121"
mkdir -p "$T121_DIR" && cd "$T121_DIR" || exit 1

PASS=0
FAIL=0
t121_ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
t121_bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
t121_contains() {
  local label="$1" expected="$2" actual="$3"
  if printf '%s' "$actual" | grep -qF -- "$expected"; then t121_ok "$label"; else
    t121_bad "$label (expected: '$expected')"
    echo "    actual: $(printf '%s' "$actual" | head -c 200)"
  fi
}
t121_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t121_ok "$label"; else t121_bad "$label (expected: '$expected', got: '$actual')"; fi
}
t121_exit() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then t121_ok "$label (exit $actual)"; else
    t121_bad "$label (expected exit $expected, got '${actual:-<none>}')"; fi
}

t121_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T121_DIR"
  if [ "$T121_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t121_teardown EXIT

echo "--- T121: branch reap proofs (refusals, exemptions, revive past gc, JSON shape) ---"

# One case world per call: sandbox HOME + XDG_DATA_HOME + a fixture repo on
# branch main with two commits (HEAD~1 tree is content-landed in main).
t121_case() {
  T121_CASE="$T121_DIR/$1"
  mkdir -p "$T121_CASE/home" "$T121_CASE/xdg" "$T121_CASE/repo"
  export HOME="$T121_CASE/home"
  export XDG_DATA_HOME="$T121_CASE/xdg"
  cd "$T121_CASE/repo" || exit 1
  git init -q -b main .
  git commit -q --allow-empty -m A
  git commit -q --allow-empty -m B
}

# Heads + reaped refs snapshot -- refusal cases must not move either.
t121_refs() { git for-each-ref --format='%(refname) %(objectname)' refs/heads/ refs/reaped/; }

# Field of one branch row from a payload file (NO-JSON/NO-ROW/NO-FIELD on
# any miss; arrays print as JSON).
t121_row() { # $1=payload file $2=branch $3=field
  node -e '
    const fs = require("fs");
    let p; try { p = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch { console.log("NO-JSON"); process.exit(0); }
    const row = (p.branches || []).find((b) => b.branch === process.argv[2]);
    if (!row) { console.log("NO-ROW"); process.exit(0); }
    const v = row[process.argv[3]];
    console.log(v === undefined ? "NO-FIELD" : (typeof v === "object" ? JSON.stringify(v) : v));
  ' "$1" "$2" "$3"
}

t121_summary() { # $1=payload file -> delete=N,manual=N,keep=N
  node -e '
    const fs = require("fs");
    let p; try { p = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch { console.log("NO-JSON"); process.exit(0); }
    console.log("delete=" + p.summary.delete + ",manual=" + p.summary.manual + ",keep=" + p.summary.keep);
  ' "$1"
}

# ---------------------------------------------------------------- C1 --
# Replace-ref refusal: one refs/replace/* entry rewrites history and could
# fake the content-landed verdict, so reap refuses outright (tier-1, before
# any mode handling) -- loud failure, no branch or reaped ref moved.
t121_case c1
git replace HEAD~1 HEAD
C1_BEFORE="$(t121_refs)"
node "$GOS" branch reap --dry-run --base main > c1-out.txt 2> c1-err.txt; C1_RC=$?
t121_exit "C1: non-empty refs/replace refuses outright (exit 1)" 1 "$C1_RC"
t121_contains "C1: refusal names the replace-ref rewrite hazard" "refs/replace/* is non-empty" "$(cat c1-err.txt)"
t121_eq "C1: refusal mutates nothing (heads and reaped refs unchanged)" "$C1_BEFORE" "$(t121_refs)"
if printf '%s' "$(cat c1-out.txt)" | grep -q '"mode"'; then t121_bad "C1: refused run must emit no verdict payload"; else t121_ok "C1: refused run emits no verdict payload"; fi
cd "$T121_DIR"

# ---------------------------------------------------------------- C2 --
# Stale-base refusal: --base pointing at a ref that does not resolve fails
# loud before any judgment -- zero mutation.
t121_case c2
git branch side HEAD~1
C2_BEFORE="$(t121_refs)"
node "$GOS" branch reap --dry-run --base refs/heads/does-not-exist > c2-out.txt 2> c2-err.txt; C2_RC=$?
t121_exit "C2: unresolvable --base fails loud (exit 1)" 1 "$C2_RC"
t121_contains "C2: refusal names the missing base ref" "base ref 'refs/heads/does-not-exist' does not resolve to a commit" "$(cat c2-err.txt)"
t121_eq "C2: stale-base refusal mutates nothing" "$C2_BEFORE" "$(t121_refs)"
cd "$T121_DIR"

# ---------------------------------------------------------------- C3 --
# Live-lock refusal: a planted run lock whose holder is provably live (real
# hostname, real boot id, the live section shell pid) blocks --apply only;
# dry-run needs no lock and still reports verdicts.
t121_case c3
git branch doomed HEAD~1
cat > c3-plant.cjs <<'EOF'
const fs = require('fs');
const os = require('os');
const path = require('path');
const store = require(path.join(process.env.GOS_ROOT, 'bin/lib/ops/auto/store.cjs'));
const root = process.argv[2];
const dir = store.storeRoot(root);
fs.mkdirSync(dir, { recursive: true });
let boot = null;
try { boot = fs.readFileSync('/proc/sys/kernel/random/boot_id', 'utf8').trim(); } catch { /* unavailable */ }
const rec = {
  pid: process.ppid, hostname: os.hostname(), boot_id: boot,
  started_at: new Date().toISOString(), heartbeat_at: new Date().toISOString(),
  clone_path: root,
};
fs.writeFileSync(path.join(dir, 'run.lock'), JSON.stringify(rec) + '\n');
console.log(rec.pid);
EOF
C3_PID="$(node c3-plant.cjs "$PWD")"
C3_BEFORE="$(t121_refs)"
node "$GOS" branch reap --apply --base main > c3-out.txt 2> c3-err.txt; C3_RC=$?
t121_exit "C3: live run lock refuses --apply (exit 1)" 1 "$C3_RC"
t121_contains "C3: refusal names the live holder pid" "a live auto run lock is held by pid $C3_PID" "$(cat c3-err.txt)"
t121_eq "C3: refused apply mutates nothing" "$C3_BEFORE" "$(t121_refs)"
node "$GOS" branch reap --dry-run --base main > c3-dry.txt 2>/dev/null; C3_DRY_RC=$?
t121_exit "C3: dry-run still works under the live lock (exit 0)" 0 "$C3_DRY_RC"
t121_eq "C3: dry-run under lock still reports the verdicts" "delete=1,manual=0,keep=1" "$(t121_summary c3-dry.txt)"
cd "$T121_DIR"

# ---------------------------------------------------------------- C4 --
# chain/* exemption: a chain-namespace branch whose content IS landed in the
# base reads keep/chain-namespace and is never deleted, --apply included.
t121_case c4
git branch chain/t4b-landed HEAD~1
node "$GOS" branch reap --dry-run --base main > c4-dry.txt 2>/dev/null; C4_DRY_RC=$?
t121_exit "C4: dry-run on a landed chain/ branch runs clean (exit 0)" 0 "$C4_DRY_RC"
t121_eq "C4: landed chain/ branch reads action keep" "keep" "$(t121_row c4-dry.txt chain/t4b-landed action)"
t121_eq "C4: keep reason is the chain namespace" "chain-namespace" "$(t121_row c4-dry.txt chain/t4b-landed reason)"
node "$GOS" branch reap --apply --base main > c4-apply.txt 2>/dev/null; C4_APPLY_RC=$?
t121_exit "C4: --apply completes (exit 0)" 0 "$C4_APPLY_RC"
t121_eq "C4: apply summary has zero deletions" "delete=0,manual=0,keep=2" "$(t121_summary c4-apply.txt)"
if git rev-parse --verify --quiet refs/heads/chain/t4b-landed >/dev/null; then t121_ok "C4: chain/ branch survives --apply"; else t121_bad "C4: chain/ branch was deleted by --apply"; fi
cd "$T121_DIR"

# ---------------------------------------------------------------- C5 --
# Worktree exemption: a content-landed branch checked out in a linked
# worktree reads keep/worktree-checked-out and survives --apply.
t121_case c5
git branch wt-landed HEAD~1
git worktree add "$T121_CASE/wt5" wt-landed > c5-wt.log 2>&1
node "$GOS" branch reap --dry-run --base main > c5-dry.txt 2>/dev/null; C5_DRY_RC=$?
t121_exit "C5: dry-run with a worktree-checked-out branch runs clean (exit 0)" 0 "$C5_DRY_RC"
t121_eq "C5: landed branch checked out in a worktree reads action keep" "keep" "$(t121_row c5-dry.txt wt-landed action)"
t121_eq "C5: keep reason is the worktree checkout" "worktree-checked-out" "$(t121_row c5-dry.txt wt-landed reason)"
node "$GOS" branch reap --apply --base main > c5-apply.txt 2>/dev/null; C5_APPLY_RC=$?
t121_exit "C5: --apply completes (exit 0)" 0 "$C5_APPLY_RC"
if git rev-parse --verify --quiet refs/heads/wt-landed >/dev/null; then t121_ok "C5: worktree-checked-out branch survives --apply"; else t121_bad "C5: worktree-checked-out branch was deleted by --apply"; fi
cd "$T121_DIR"

# ---------------------------------------------------------------- C6 --
# Ref-revive past aggressive gc: --apply leaves refs/reaped/<branch> at the
# original sha; the commit survives `git gc --prune=now --aggressive`; the
# printed revive argv-array restores the branch at exactly that sha.
t121_case c6
git branch gone HEAD~1
C6_SHA="$(git rev-parse gone)"
node "$GOS" branch reap --dry-run --base main > c6-dry.txt 2>/dev/null; C6_DRY_RC=$?
t121_exit "C6: dry-run flags the landed branch for deletion (exit 0)" 0 "$C6_DRY_RC"
t121_eq "C6: verdict row reads action delete" "delete" "$(t121_row c6-dry.txt gone action)"
t121_eq "C6: revive is the argv array [git branch <name> <sha>]" '["git","branch","gone","'"$C6_SHA"'"]' "$(t121_row c6-dry.txt gone revive)"
node "$GOS" branch reap --apply --base main > c6-apply.txt 2>/dev/null; C6_APPLY_RC=$?
t121_exit "C6: --apply deletes the branch (exit 0)" 0 "$C6_APPLY_RC"
if git rev-parse --verify --quiet refs/heads/gone >/dev/null; then t121_bad "C6: branch ref must be gone after --apply"; else t121_ok "C6: branch ref is gone after --apply"; fi
t121_eq "C6: revive ref pins the original sha" "$C6_SHA" "$(git rev-parse refs/reaped/gone)"
git gc --prune=now --aggressive > c6-gc.log 2>&1; C6_GC_RC=$?
t121_exit "C6: aggressive gc with prune=now completes" 0 "$C6_GC_RC"
cat > c6-revive.cjs <<'EOF'
const fs = require('fs');
const { spawnSync } = require('child_process');
const p = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const row = p.branches.find((b) => b.branch === process.argv[3]);
if (!row || !Array.isArray(row.revive)) { console.log('NO-REVIVE'); process.exit(0); }
const r = spawnSync(row.revive[0], row.revive.slice(1), { cwd: process.argv[4], encoding: 'utf8' });
if (r.status !== 0) console.log('STDERR: ' + String(r.stderr || '').slice(0, 200));
console.log('REVIVE-EXIT=' + r.status);
EOF
C6_REVIVE="$(node c6-revive.cjs c6-apply.txt gone "$PWD")"
t121_contains "C6: the printed revive argv runs clean past gc" "REVIVE-EXIT=0" "$C6_REVIVE"
t121_eq "C6: revived branch points at the original sha" "$C6_SHA" "$(git rev-parse refs/heads/gone)"
cd "$T121_DIR"

# ---------------------------------------------------------------- C7 --
# JSON shape: dry-run stdout is one strict JSON document; per-branch action
# is one of delete/manual/keep; delete rows carry string argv-array revive
# commands; summary counts recount the rows.
t121_case c7
git branch landme HEAD~1
git checkout -q -b fresh
echo fresh-content > fresh.txt
git add fresh.txt
git commit -q -m C
git checkout -q main
git branch chain/shape HEAD
node "$GOS" branch reap --dry-run --base main > c7-out.json 2> c7-err.txt; C7_RC=$?
t121_exit "C7: dry-run on the mixed fixture runs clean (exit 0)" 0 "$C7_RC"
cat > c7-shape.cjs <<'EOF'
const fs = require('fs');
const problems = [];
let p;
try { p = JSON.parse(fs.readFileSync(process.argv[2], 'utf8')); }
catch (e) { console.log('T121-BAD stdout is not strict JSON: ' + e.message); process.exit(0); }
if (p.mode !== 'dry-run') problems.push('mode is not dry-run');
if (p.base !== 'main' || !/^[0-9a-f]{40}$/.test(p.baseSha || '')) problems.push('base/baseSha malformed');
if (!Array.isArray(p.branches)) problems.push('branches is not an array');
const actions = new Set(['delete', 'manual', 'keep']);
const recount = { delete: 0, manual: 0, keep: 0 };
for (const row of p.branches || []) {
  if (!actions.has(row.action)) problems.push('bad action for ' + row.branch);
  if (!/^[0-9a-f]{40}$/.test(row.sha || '')) problems.push('bad sha for ' + row.branch);
  recount[row.action] += 1;
  if (row.action === 'delete') {
    if (!Array.isArray(row.revive) || !row.revive.every((x) => typeof x === 'string')) {
      problems.push('revive not a string argv array for ' + row.branch);
    } else if (row.revive[0] !== 'git' || row.revive[1] !== 'branch') {
      problems.push('revive argv does not start git branch for ' + row.branch);
    }
  }
}
for (const k of ['delete', 'manual', 'keep']) {
  if (p.summary[k] !== recount[k]) problems.push('summary.' + k + ' disagrees with rows');
}
const expect = { landme: 'delete', fresh: 'manual', 'chain/shape': 'keep', main: 'keep' };
for (const [name, action] of Object.entries(expect)) {
  const row = p.branches.find((b) => b.branch === name);
  if (!row) problems.push('missing row ' + name);
  else if (row.action !== action) problems.push(name + ' expected ' + action + ' got ' + row.action);
}
console.log(problems.length ? 'T121-BAD ' + problems.join('; ') : 'T121-OK');
console.log('SUM[delete:' + recount.delete + ',manual:' + recount.manual + ',keep:' + recount.keep + ']');
EOF
C7_SHAPE="$(node c7-shape.cjs c7-out.json)"
t121_contains "C7: stdout is strict JSON with delete/manual/keep actions, argv-array revives, recounted summary" "T121-OK" "$C7_SHAPE"
t121_contains "C7: verdict mix is exactly delete=1, manual=1, keep=2" "SUM[delete:1,manual:1,keep:2]" "$C7_SHAPE"
cd "$T121_DIR"

echo "--- T121 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
