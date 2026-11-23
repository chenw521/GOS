#!/usr/bin/env bash
# gos-map:none
# Pin self-heal choke point section — loadPinnedModuleWithHeal wraps the
# Class P module load with a bounded, anchor-gated rebuild: a load that
# fails because the pinned worktree itself is unresolvable or tampered may
# be healed only when the store record still proves all three trust
# anchors (loop-start commit identity, a fresh tree-sha resolution at the
# live repo root, path containment in the pin slot), only under a
# caller-owned budget, and only through the existing recycle + materialize
# + single-retry composite. Everything else fails closed with nothing
# removed.
# Case map:
#   C1  heal success: a healthy load passes through untouched (no budget
#       change); a deterministically deleted worktree heals once —
#       healed:true, budget.heals === 1, module loads from the
#       re-materialized worktree, record rewritten in place
#   C2  budget exhausted: with the same budget (cap 2) the second dead-pin
#       load heals to heals === cap; the third returns exactly
#       heal-budget-exhausted with the exceed count in the detail and the
#       store record intact
#   C3  anchor mismatch: a poisoned record treeSha (C3a), a mismatched
#       expected loop-start commit (C3b), and an out-of-slot record path
#       (C3c) each refuse heal-anchor-mismatch naming the failed anchor,
#       with the target directory still on disk and the record unchanged
#   C4  no-heal classifications: pin-unknown (record dropped) and
#       pin-module-unloadable (module missing from a healthy tree) return
#       the original failure without healing or touching the budget;
#       malformed accounting (budget shape, expected commit shape) refuses
#       closed before any load
# HOME and XDG_DATA_HOME are pinned per case under TESTBASE. Standalone-safe.

T132_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T132_STANDALONE=1
  T132_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T132_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T132_SELFROOT"
  export TESTBASE="$(mktemp -d "$T132_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T132_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t132"
mkdir -p "$T132_DIR" && cd "$T132_DIR" || exit 1

PASS=0
FAIL=0
t132_ok() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
t132_bad() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
t132_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then t132_ok "$label"; else
    t132_bad "$label (expected: '$expected', got: '$actual')"
  fi
}

t132_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T132_DIR"
  if [ "$T132_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t132_teardown EXIT

echo "--- T132: pin self-heal choke point ---"

t132_case() {
  T132_CASE="$T132_DIR/$1"
  mkdir -p "$T132_CASE/home" "$T132_CASE/xdg" "$T132_CASE/repo/.gos/logs"
  export HOME="$T132_CASE/home"
  export XDG_DATA_HOME="$T132_CASE/xdg"
  cd "$T132_CASE/repo" || exit 1
  git init -q -b work . && git commit -q --allow-empty -m root
}

# ---------------------------------------------------------------- C1 --
t132_case c1
# Deterministic deleter: the worktree directory is removed outright, which
# leaves the store record pointing at an unresolvable checkout — exactly
# the kill/restart residue the heal path exists for.
cat > "$T132_CASE/run-c1.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const workers = require(path.join(GR, 'bin/lib/ops/auto/workers.cjs'));
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const repo = process.cwd();
const problems = [];
const git = (args, cwd) => spawnSync('git', args, { cwd: cwd || repo, encoding: 'utf8' });
fs.mkdirSync(path.join(repo, 'legs'), { recursive: true });
fs.writeFileSync(path.join(repo, 'legs', 'trust-leg.cjs'),
  "'use strict'; module.exports = { verdict: function () { return { pass: true, source: 'heal-fixture' }; } };\n");
if (git(['add', 'legs']).status !== 0) problems.push('fixture add failed');
if (git(['commit', '-q', '-m', 'seed-leg']).status !== 0) problems.push('fixture commit failed');
const head = String(git(['rev-parse', 'HEAD']).stdout || '').trim();
const tree = String(git(['rev-parse', 'HEAD^{tree}']).stdout || '').trim();
if (!/^[0-9a-f]{40}$/.test(head) || !/^[0-9a-f]{40}$/.test(tree)) problems.push('fixture head/tree unresolvable');
if (!store.create({ mode: 'on', rootDir: repo }).ok) problems.push('store create refused');
const budget = { heals: 0, cap: 2 };
const pin = workers.materializePin(repo, { loopStartCommit: head, runTag: 'pin-heal-first' });
if (!pin.ok) problems.push('materializePin refused: ' + pin.reason + '/' + (pin.detail || ''));
if (pin.ok) {
  const healthy = workers.loadPinnedModuleWithHeal({ runTag: 'pin-heal-first', rootDir: repo }, 'legs/trust-leg.cjs',
    { rootDir: repo, expectedLoopStartCommit: head, budget });
  if (!healthy.ok) problems.push('healthy load refused: ' + healthy.reason + '/' + (healthy.detail || ''));
  else {
    if ('healed' in healthy) problems.push('healthy passthrough carries healed=' + JSON.stringify(healthy.healed));
    if (!healthy.module || typeof healthy.module.verdict !== 'function' || healthy.module.verdict().source !== 'heal-fixture') {
      problems.push('healthy load did not return the fixture module');
    }
  }
  if (budget.heals !== 0) problems.push('healthy passthrough consumed budget (heals=' + budget.heals + ')');
  fs.rmSync(pin.path, { recursive: true, force: true });
  if (fs.existsSync(pin.path)) problems.push('worktree kill left the directory on disk');
  const healed = workers.loadPinnedModuleWithHeal({ runTag: 'pin-heal-first', rootDir: repo }, 'legs/trust-leg.cjs',
    { rootDir: repo, expectedLoopStartCommit: head, budget });
  if (!healed.ok) problems.push('heal refused: ' + healed.reason + '/' + (healed.detail || ''));
  else {
    if (healed.healed !== true) problems.push('heal verdict lacks healed:true');
    if (healed.heals !== 1) problems.push('heal verdict heals=' + healed.heals + ' (want 1)');
    if (budget.heals !== 1) problems.push('caller budget not accounted (heals=' + budget.heals + ')');
    if (healed.treeSha !== tree) problems.push('healed load carries tree ' + healed.treeSha + ' (want ' + tree + ')');
    if (!healed.module || typeof healed.module.verdict !== 'function' || healed.module.verdict().source !== 'heal-fixture') {
      problems.push('healed load did not return the fixture module');
    }
  }
  if (!fs.existsSync(pin.path)) problems.push('re-materialized worktree missing on disk');
  const pins = store.readPins(repo);
  const rec = pins.ok ? pins.pins['pin-heal-first'] : null;
  if (!rec) problems.push('pin record dropped after heal');
  else if (rec.treeSha !== tree || rec.loopStartCommit !== head) problems.push('rewritten record fields wrong');
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C1_OUT="$(node "$T132_CASE/run-c1.cjs" 2>&1 | tail -n 1)"
t132_eq "C1: dead worktree heals once under a fresh budget (healthy passthrough untouched, healed:true, record rewritten in place)" "OK" "$C1_OUT"

# ---------------------------------------------------------------- C2 --
t132_case c2
# Budget ceiling: cap 2 admits exactly two heals; the third dead-pin load
# refuses with the exceed count and never recycles the live record.
cat > "$T132_CASE/run-c2.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const workers = require(path.join(GR, 'bin/lib/ops/auto/workers.cjs'));
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const repo = process.cwd();
const problems = [];
const git = (args, cwd) => spawnSync('git', args, { cwd: cwd || repo, encoding: 'utf8' });
fs.mkdirSync(path.join(repo, 'legs'), { recursive: true });
fs.writeFileSync(path.join(repo, 'legs', 'trust-leg.cjs'),
  "'use strict'; module.exports = { verdict: function () { return { pass: true, source: 'heal-fixture' }; } };\n");
if (git(['add', 'legs']).status !== 0) problems.push('fixture add failed');
if (git(['commit', '-q', '-m', 'seed-leg']).status !== 0) problems.push('fixture commit failed');
const head = String(git(['rev-parse', 'HEAD']).stdout || '').trim();
const tree = String(git(['rev-parse', 'HEAD^{tree}']).stdout || '').trim();
if (!store.create({ mode: 'on', rootDir: repo }).ok) problems.push('store create refused');
const pin = workers.materializePin(repo, { loopStartCommit: head, runTag: 'pin-heal-cap' });
if (!pin.ok) problems.push('materializePin refused: ' + pin.reason + '/' + (pin.detail || ''));
if (pin.ok) {
  const budget = { heals: 0, cap: 2 };
  const call = () => workers.loadPinnedModuleWithHeal({ runTag: 'pin-heal-cap', rootDir: repo }, 'legs/trust-leg.cjs',
    { rootDir: repo, expectedLoopStartCommit: head, budget });
  const kill = () => fs.rmSync(pin.path, { recursive: true, force: true });
  kill();
  const first = call();
  if (!first.ok) problems.push('first heal refused: ' + first.reason + '/' + (first.detail || ''));
  else if (first.heals !== 1 || budget.heals !== 1) problems.push('first heal accounting wrong (heals=' + budget.heals + ')');
  kill();
  const second = call();
  if (!second.ok) problems.push('second heal refused: ' + second.reason + '/' + (second.detail || ''));
  else if (second.heals !== 2 || budget.heals !== 2) problems.push('second heal accounting wrong (heals=' + budget.heals + ')');
  kill();
  const third = call();
  if (third.ok) problems.push('third dead-pin load healed past the cap');
  else {
    if (third.reason !== 'heal-budget-exhausted') problems.push('third refusal reason=' + third.reason);
    if (third.detail !== 'heals 2 >= cap 2') problems.push('exhaustion detail=' + JSON.stringify(third.detail));
  }
  if (budget.heals !== 2) problems.push('exhaustion refusal bumped the budget to ' + budget.heals);
  const pins = store.readPins(repo);
  const rec = pins.ok ? pins.pins['pin-heal-cap'] : null;
  if (!rec) problems.push('record dropped on budget exhaustion');
  else if (rec.treeSha !== tree || rec.loopStartCommit !== head) problems.push('record fields drifted on exhaustion');
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C2_OUT="$(node "$T132_CASE/run-c2.cjs" 2>&1 | tail -n 1)"
t132_eq "C2: third dead-pin load with heals === cap refuses heal-budget-exhausted (exceed count in detail, record intact)" "OK" "$C2_OUT"

# ---------------------------------------------------------------- C3a --
t132_case c3a
# Poisoned tree anchor: the record's treeSha no longer matches what the
# expected loop-start commit resolves to at the live repo root. The
# worktree's git linkage is corrupted (not deleted) so the refusal must
# leave the directory and the record exactly as they were.
cat > "$T132_CASE/run-c3a.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const workers = require(path.join(GR, 'bin/lib/ops/auto/workers.cjs'));
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const repo = process.cwd();
const problems = [];
const git = (args, cwd) => spawnSync('git', args, { cwd: cwd || repo, encoding: 'utf8' });
fs.mkdirSync(path.join(repo, 'legs'), { recursive: true });
fs.writeFileSync(path.join(repo, 'legs', 'trust-leg.cjs'),
  "'use strict'; module.exports = { verdict: function () { return { pass: true, source: 'heal-fixture' }; } };\n");
if (git(['add', 'legs']).status !== 0) problems.push('fixture add failed');
if (git(['commit', '-q', '-m', 'seed-leg']).status !== 0) problems.push('fixture commit failed');
const head = String(git(['rev-parse', 'HEAD']).stdout || '').trim();
if (!store.create({ mode: 'on', rootDir: repo }).ok) problems.push('store create refused');
const pin = workers.materializePin(repo, { loopStartCommit: head, runTag: 'pin-heal-sha' });
if (!pin.ok) problems.push('materializePin refused: ' + pin.reason + '/' + (pin.detail || ''));
if (pin.ok) {
  const forged = store.recordPin(repo, { runTag: 'pin-heal-sha', path: pin.path, treeSha: 'e'.repeat(40), loopStartCommit: head });
  if (!forged.ok) problems.push('poisoned recordPin refused: ' + forged.reason);
  fs.writeFileSync(path.join(pin.path, '.git'), 'gitdir: /nonexistent-t132/gitdir\n');
  const before = JSON.stringify((store.readPins(repo).pins || {})['pin-heal-sha']);
  const out = workers.loadPinnedModuleWithHeal({ runTag: 'pin-heal-sha', rootDir: repo }, 'legs/trust-leg.cjs',
    { rootDir: repo, expectedLoopStartCommit: head, budget: { heals: 0, cap: 2 } });
  if (out.ok) problems.push('healed under a poisoned record tree sha');
  else {
    if (out.reason !== 'heal-anchor-mismatch') problems.push('poisoned treeSha refusal reason=' + out.reason);
    if (!/tree-sha/.test(out.detail || '')) problems.push('poisoned treeSha detail does not name the tree-sha anchor: ' + out.detail);
  }
  if (!fs.existsSync(pin.path)) problems.push('worktree directory removed on anchor refusal');
  const after = JSON.stringify((store.readPins(repo).pins || {})['pin-heal-sha']);
  if (after !== before) problems.push('record mutated on anchor refusal');
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C3A_OUT="$(node "$T132_CASE/run-c3a.cjs" 2>&1 | tail -n 1)"
t132_eq "C3a: poisoned record treeSha refuses heal-anchor-mismatch naming tree-sha, nothing removed" "OK" "$C3A_OUT"

# ---------------------------------------------------------------- C3b --
t132_case c3b
# Commit-identity anchor: the caller expects a different loop-start commit
# than the record carries. The refusal names commit-identity and removes
# nothing.
cat > "$T132_CASE/run-c3b.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const workers = require(path.join(GR, 'bin/lib/ops/auto/workers.cjs'));
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const repo = process.cwd();
const problems = [];
const git = (args, cwd) => spawnSync('git', args, { cwd: cwd || repo, encoding: 'utf8' });
fs.mkdirSync(path.join(repo, 'legs'), { recursive: true });
fs.writeFileSync(path.join(repo, 'legs', 'trust-leg.cjs'),
  "'use strict'; module.exports = { verdict: function () { return { pass: true, source: 'heal-fixture' }; } };\n");
if (git(['add', 'legs']).status !== 0) problems.push('fixture add failed');
if (git(['commit', '-q', '-m', 'seed-leg']).status !== 0) problems.push('fixture commit failed');
const headA = String(git(['rev-parse', 'HEAD']).stdout || '').trim();
fs.writeFileSync(path.join(repo, 'extra.cjs'), "'use strict';\n");
if (git(['add', 'extra.cjs']).status !== 0) problems.push('fixture add 2 failed');
if (git(['commit', '-q', '-m', 'second']).status !== 0) problems.push('fixture commit 2 failed');
const headB = String(git(['rev-parse', 'HEAD']).stdout || '').trim();
if (headA === headB) problems.push('fixture commits collapsed into one');
if (!store.create({ mode: 'on', rootDir: repo }).ok) problems.push('store create refused');
const pin = workers.materializePin(repo, { loopStartCommit: headA, runTag: 'pin-heal-commit' });
if (!pin.ok) problems.push('materializePin refused: ' + pin.reason + '/' + (pin.detail || ''));
if (pin.ok) {
  fs.writeFileSync(path.join(pin.path, '.git'), 'gitdir: /nonexistent-t132/gitdir\n');
  const before = JSON.stringify((store.readPins(repo).pins || {})['pin-heal-commit']);
  const out = workers.loadPinnedModuleWithHeal({ runTag: 'pin-heal-commit', rootDir: repo }, 'legs/trust-leg.cjs',
    { rootDir: repo, expectedLoopStartCommit: headB, budget: { heals: 0, cap: 2 } });
  if (out.ok) problems.push('healed under a mismatched expected loop-start commit');
  else {
    if (out.reason !== 'heal-anchor-mismatch') problems.push('mismatched commit refusal reason=' + out.reason);
    if (!/commit-identity/.test(out.detail || '')) problems.push('mismatched commit detail does not name the commit-identity anchor: ' + out.detail);
  }
  if (!fs.existsSync(pin.path)) problems.push('worktree directory removed on anchor refusal');
  const after = JSON.stringify((store.readPins(repo).pins || {})['pin-heal-commit']);
  if (after !== before) problems.push('record mutated on anchor refusal');
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C3B_OUT="$(node "$T132_CASE/run-c3b.cjs" 2>&1 | tail -n 1)"
t132_eq "C3b: mismatched expected loop-start commit refuses heal-anchor-mismatch naming commit-identity, nothing removed" "OK" "$C3B_OUT"

# ---------------------------------------------------------------- C3c --
t132_case c3c
# Path-containment anchor: the record path is rewritten outside the pin
# slot (direct store.json edit — recordPin itself enforces containment, so
# the poison must bypass it). recyclePin force-removes rec.path, so the
# refusal must leave both the sentinel target and the real worktree alive.
cat > "$T132_CASE/run-c3c.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const workers = require(path.join(GR, 'bin/lib/ops/auto/workers.cjs'));
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const repo = process.cwd();
const problems = [];
const git = (args, cwd) => spawnSync('git', args, { cwd: cwd || repo, encoding: 'utf8' });
fs.mkdirSync(path.join(repo, 'legs'), { recursive: true });
fs.writeFileSync(path.join(repo, 'legs', 'trust-leg.cjs'),
  "'use strict'; module.exports = { verdict: function () { return { pass: true, source: 'heal-fixture' }; } };\n");
if (git(['add', 'legs']).status !== 0) problems.push('fixture add failed');
if (git(['commit', '-q', '-m', 'seed-leg']).status !== 0) problems.push('fixture commit failed');
const head = String(git(['rev-parse', 'HEAD']).stdout || '').trim();
if (!store.create({ mode: 'on', rootDir: repo }).ok) problems.push('store create refused');
const pin = workers.materializePin(repo, { loopStartCommit: head, runTag: 'pin-heal-slot' });
if (!pin.ok) problems.push('materializePin refused: ' + pin.reason + '/' + (pin.detail || ''));
if (pin.ok) {
  const sentinel = path.join(path.dirname(repo), 'outside-slot-sentinel');
  fs.mkdirSync(sentinel, { recursive: true });
  fs.writeFileSync(path.join(sentinel, 'keep'), 'sentinel');
  const storeFile = path.join(store.storeRoot(repo), 'store.json');
  const doc = JSON.parse(fs.readFileSync(storeFile, 'utf8'));
  doc.pinWorktrees['pin-heal-slot'].path = sentinel;
  fs.writeFileSync(storeFile, JSON.stringify(doc));
  const out = workers.loadPinnedModuleWithHeal({ runTag: 'pin-heal-slot', rootDir: repo }, 'legs/trust-leg.cjs',
    { rootDir: repo, expectedLoopStartCommit: head, budget: { heals: 0, cap: 2 } });
  if (out.ok) problems.push('healed under an out-of-slot record path');
  else {
    if (out.reason !== 'heal-anchor-mismatch') problems.push('out-of-slot path refusal reason=' + out.reason);
    if (!/path-containment/.test(out.detail || '')) problems.push('out-of-slot path detail does not name the path-containment anchor: ' + out.detail);
  }
  if (!fs.existsSync(path.join(sentinel, 'keep'))) problems.push('sentinel target removed on anchor refusal');
  if (!fs.existsSync(pin.path)) problems.push('true worktree removed on anchor refusal');
  const after = JSON.parse(fs.readFileSync(storeFile, 'utf8'));
  if (after.pinWorktrees['pin-heal-slot'].path !== sentinel) problems.push('record path mutated on anchor refusal');
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C3C_OUT="$(node "$T132_CASE/run-c3c.cjs" 2>&1 | tail -n 1)"
t132_eq "C3c: out-of-slot record path refuses heal-anchor-mismatch naming path-containment, sentinel and worktree survive" "OK" "$C3C_OUT"

# ---------------------------------------------------------------- C4 --
t132_case c4
# Non-healable classifications return the original failure with the budget
# untouched and the worktree intact; malformed accounting (budget shape,
# expected commit shape) refuses closed before any load runs.
cat > "$T132_CASE/run-c4.cjs" <<'EOF'
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = process.env.GOS_ROOT;
const workers = require(path.join(GR, 'bin/lib/ops/auto/workers.cjs'));
const store = require(path.join(GR, 'bin/lib/ops/auto/store.cjs'));
const repo = process.cwd();
const problems = [];
const git = (args, cwd) => spawnSync('git', args, { cwd: cwd || repo, encoding: 'utf8' });
fs.mkdirSync(path.join(repo, 'legs'), { recursive: true });
fs.writeFileSync(path.join(repo, 'legs', 'trust-leg.cjs'),
  "'use strict'; module.exports = { verdict: function () { return { pass: true, source: 'heal-fixture' }; } };\n");
if (git(['add', 'legs']).status !== 0) problems.push('fixture add failed');
if (git(['commit', '-q', '-m', 'seed-leg']).status !== 0) problems.push('fixture commit failed');
const head = String(git(['rev-parse', 'HEAD']).stdout || '').trim();
if (!store.create({ mode: 'on', rootDir: repo }).ok) problems.push('store create refused');
const budget = { heals: 0, cap: 2 };
const dead = workers.materializePin(repo, { loopStartCommit: head, runTag: 'pin-heal-unknown' });
if (!dead.ok) problems.push('materializePin (dead) refused: ' + dead.reason + '/' + (dead.detail || ''));
const live = workers.materializePin(repo, { loopStartCommit: head, runTag: 'pin-heal-live' });
if (!live.ok) problems.push('materializePin (live) refused: ' + live.reason + '/' + (live.detail || ''));
if (dead.ok) {
  store.dropPin(repo, 'pin-heal-unknown');
  fs.rmSync(dead.path, { recursive: true, force: true });
  const unknown = workers.loadPinnedModuleWithHeal({ runTag: 'pin-heal-unknown', rootDir: repo }, 'legs/trust-leg.cjs',
    { rootDir: repo, expectedLoopStartCommit: head, budget });
  if (unknown.ok || unknown.reason !== 'pin-unknown') {
    problems.push('dropped record not refused pin-unknown: ' + (unknown.ok ? 'ok' : unknown.reason));
  }
}
if (live.ok) {
  const unloadable = workers.loadPinnedModuleWithHeal({ runTag: 'pin-heal-live', rootDir: repo }, 'legs/never-committed.cjs',
    { rootDir: repo, expectedLoopStartCommit: head, budget });
  if (unloadable.ok || unloadable.reason !== 'pin-module-unloadable') {
    problems.push('missing module not refused pin-module-unloadable: ' + (unloadable.ok ? 'ok' : unloadable.reason));
  }
  if (!fs.existsSync(live.path)) problems.push('non-healable failure recycled the worktree');
  const pins = store.readPins(repo);
  if (!pins.ok || !pins.pins['pin-heal-live']) problems.push('record dropped on a non-healable failure');
  const badBudgets = [null, {}, { heals: 0 }, { heals: -1, cap: 2 }, { heals: 0.5, cap: 2 }, { heals: 0, cap: 0 }];
  for (const bb of badBudgets) {
    const r = workers.loadPinnedModuleWithHeal({ runTag: 'pin-heal-live', rootDir: repo }, 'legs/trust-leg.cjs',
      { rootDir: repo, expectedLoopStartCommit: head, budget: bb });
    if (r.ok || r.reason !== 'heal-budget-invalid') {
      problems.push('budget ' + JSON.stringify(bb) + ' not refused heal-budget-invalid: ' + (r.ok ? 'ok' : r.reason));
    }
  }
  const badCommit = workers.loadPinnedModuleWithHeal({ runTag: 'pin-heal-live', rootDir: repo }, 'legs/trust-leg.cjs',
    { rootDir: repo, expectedLoopStartCommit: 'nothash', budget: { heals: 0, cap: 2 } });
  if (badCommit.ok || badCommit.reason !== 'pin-commit-invalid') {
    problems.push('malformed expectedLoopStartCommit not refused pin-commit-invalid: ' + (badCommit.ok ? 'ok' : badCommit.reason));
  }
  if (!fs.existsSync(live.path)) problems.push('accounting refusals removed the worktree');
}
if (budget.heals !== 0) problems.push('non-healable paths consumed budget (heals=' + budget.heals + ')');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
EOF
C4_OUT="$(node "$T132_CASE/run-c4.cjs" 2>&1 | tail -n 1)"
t132_eq "C4: pin-unknown and pin-module-unloadable return the original failure unhealed; malformed accounting refuses closed" "OK" "$C4_OUT"

echo "--- T132 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
