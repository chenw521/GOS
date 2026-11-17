#!/usr/bin/env bash
# gos-map:fn bin/lib/knowledge/milestone.cjs#fn:openMilestone bin/lib/knowledge/milestone.cjs#fn:closeMilestone bin/lib/knowledge/milestone.cjs#fn:classifyRowDisposition
# gos-map:cmd milestone
# milestone open/close — open-name sanitization and lifecycle refusals, close
# disposition over a five-class replica (done-owned / null-phase / ghost /
# dropped / parked-owned + pending-owned carried), dry-run zero-mutation,
# dual-channel dated snapshots with MANUAL-region byte copies, approval
# consume-once and freshness, vacuum refusal, and the three crash windows.
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
T114_DIR=""

t114_setup() {
  [ -n "$TESTBASE" ] || TESTBASE="$(mktemp -d)"
  T114_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t114"
  mkdir -p "$T114_DIR" && cd "$T114_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/.lock\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
}

t114_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T114_DIR"; }

# Replica truth source: phases and rows across every disposition class.
# Phase layout: done tail, one parked, pending head. Rows carry bare code refs
# (canonicalized at close), null refs, ghost refs, dropped status, and rows
# owned by parked/pending phases that must survive the close verbatim.
t114_replica() {
  node -e '
const fs = require("fs");
const p = JSON.parse(fs.readFileSync(".gos/project/project.json", "utf8"));
const done = (n) => ({ name: `P${n}: d${n}`, goal: "g", status: "done", completed_at: "2026-11-01T00:00:00.000Z" });
p.phases = [done(0), done(1), done(2), done(3), done(4), done(5),
  { name: "PK: parked", goal: "g", status: "parked", park_reason: "deps" },
  { name: "P7: pend", goal: "g", status: "pending" },
  { name: "P8: pend", goal: "g", status: "pending" },
  { name: "P9: pend", goal: "g", status: "pending" },
  { name: "PA: pend", goal: "g", status: "pending" },
  { name: "PB: pend", goal: "g", status: "pending" }];
const dec = [];
const decRow = (id, phase, status) => ({ id, title: `t${id}`, rationale: "", birth_phase: phase, status: status || "open", anchor: null, covered: false, covered_by: null });
for (let i = 1; i <= 30; i++) dec.push(decRow(`D-${String(i).padStart(2, "0")}`, `P${(i % 6)}: d${(i % 6)}`));
for (let i = 31; i <= 40; i++) dec.push(decRow(`D-${i}`, null));
for (let i = 41; i <= 50; i++) dec.push(decRow(`D-${i}`, "G9: ghost"));
dec.push(decRow("D-51", "P1: d1"));
dec.push(decRow("D-52", "PK: parked"));
for (let i = 53; i <= 62; i++) dec.push(decRow(`D-${i}`, "P7: pend"));
for (let i = 63; i <= 70; i++) dec.push(decRow(`D-${i}`, "PB: pend"));
p.decisions = dec;
const req = [];
const reqRow = (id, phase, status) => ({ id, text: `r${id}`, phase, status: status || "active" });
for (let i = 1; i <= 20; i++) req.push(reqRow(`R-${String(i).padStart(2, "0")}`, `P${(i % 6)}: d${(i % 6)}`));
for (let i = 21; i <= 30; i++) req.push(reqRow(`R-${i}`, null));
for (let i = 31; i <= 40; i++) req.push(reqRow(`R-${i}`, "G9: ghost"));
for (let i = 41; i <= 50; i++) req.push(reqRow(`R-${i}`, "P1: d1", "dropped"));
req.push(reqRow("R-51", "G9: ghost", "dropped"));
req.push(reqRow("R-52", "PK: parked"));
req.push(reqRow("R-53", "PK: parked", "dropped"));
for (let i = 54; i <= 60; i++) req.push(reqRow(`R-${i}`, "P8: pend"));
for (let i = 61; i <= 67; i++) req.push(reqRow(`R-${i}`, "PA: pend"));
p.requirements = req;
p.last_archived_phase = "P5: d5";
fs.writeFileSync(".gos/project/project.json", JSON.stringify(p, null, 2));
'
}

# Deep-compare survivors: every post-close row/phase entry must be byte-equal
# (JSON identity) to the preclose snapshot entry with the same id/name.
t114_survivors_equal() {
  node -e '
const fs = require("fs");
const pre = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const post = JSON.parse(fs.readFileSync(".gos/project/project.json", "utf8"));
const byKey = (rows, k) => { const m = new Map(); for (const r of rows) m.set(r[k], r); return m; };
const same = (rowsPost, rowsPre, k) => {
  const preM = byKey(rowsPre, k);
  if (rowsPost.length !== [...preM.keys()].filter((x) => rowsPost.some((r) => r[k] === x)).length) return "count";
  for (const r of rowsPost) {
    const q = preM.get(r[k]);
    if (!q || JSON.stringify(q) !== JSON.stringify(r)) return "body:" + r[k];
  }
  return "ok";
};
const out = [
  same(post.decisions, pre.decisions, "id"),
  same(post.requirements, pre.requirements, "id"),
  same(post.phases, pre.phases, "name"),
].join("|");
const wipeOk = (post.decisions.every((d) => ["PK: parked", "P7: pend", "PB: pend"].includes(d.birth_phase))
  && post.requirements.every((r) => ["PK: parked", "P8: pend", "PA: pend"].includes(r.phase))) ? "ok" : "class";
console.log(out + "|" + wipeOk);
' "$1"
}

echo "--- T114: milestone open/close ---"

# ===== part 1: open-name sanitization =====
t114_setup
set +e; OUT=$(node "$GOS" milestone open 'evil/../x' 2>&1); RC=$?; set -e
assert_exit "open tainted path-like name sanitizes and succeeds" 0 "$RC"
assert_contains "sanitized identity echo names the stored slug" "stored as 'evil-x'" "$OUT"
assert_contains "opened line carries the sanitized name" "Milestone opened: evil-x" "$OUT"
STORED=$(node -e "console.log(require('./.gos/project/project.json').milestone.name)")
[ "$STORED" = "evil-x" ] && { echo "  ✓ stored milestone name is the sanitized slug"; PASS=$((PASS+1)); } || { echo "  ✗ stored name is '$STORED'"; FAIL=$((FAIL+1)); }
assert_contains "raw input quoted once for teaching (sanitizeEcho pipeline)" "input was 'evil/../x'" "$OUT"
if printf '%s' "$STORED" | grep -qE '\.\.|/|`'; then
  echo "  ✗ tainted bytes reached the stored slug"; FAIL=$((FAIL+1))
else
  echo "  ✓ tainted bytes never reach the stored slug"; PASS=$((PASS+1))
fi

set +e; OUT=$(node "$GOS" milestone open 'milestone-1 is open' 2>&1); RC=$?; set -e
assert_exit "second open while open refuses" 1 "$RC"
assert_contains "open-refuses-open names the live milestone" "milestone 'evil-x' is open — close it before opening another" "$OUT"

# reserved and empty slug shapes die with the sanitization contract
set +e; OUT=$(node "$GOS" milestone open 'v12' 2>&1); RC=$?; set -e
assert_exit "bare version name refused" 1 "$RC"
assert_contains "bare version refusal carries the slug contract" "name must resolve to a non-empty slug" "$OUT"
set +e; OUT=$(node "$GOS" milestone open '!!! ???' 2>&1); RC=$?; set -e
assert_exit "symbol-only name refused" 1 "$RC"
assert_contains "empty-slug refusal carries the slug contract" "name must resolve to a non-empty slug" "$OUT"
set +e; OUT=$(node "$GOS" milestone open 2>&1); RC=$?; set -e
assert_exit "open without a name exits 1" 1 "$RC"
assert_contains "open usage line" "Usage: gos milestone open <name>" "$OUT"

# close on a milestone with no done phases is a vacuum refusal
node "$GOS" phase add "P1: only" --goal g >/dev/null 2>&1
set +e; OUT=$(node "$GOS" milestone close 2>&1); RC=$?; set -e
assert_exit "vacuum close refused" 1 "$RC"
assert_contains "vacuum refusal names the cure" "no done phases (vacuum close) — pass --empty" "$OUT"

# empty close is the explicit escape (approval-gated)
node "$GOS" init 3 "approval holder" >/dev/null 2>&1
node "$GOS" approve milestone-close >/dev/null 2>&1
set +e; OUT=$(node "$GOS" milestone close --empty --yes 2>&1); RC=$?; set -e
assert_exit "empty close executes under approval" 0 "$RC"
assert_contains "empty close stamps closed_at" "Milestone closed: evil-x" "$OUT"
set +e; OUT=$(node "$GOS" milestone close --yes 2>&1); RC=$?; set -e
assert_exit "close on a closed milestone refuses" 1 "$RC"
assert_contains "already-closed refusal names the timestamp" "already closed at" "$OUT"
set +e; OUT=$(node "$GOS" milestone open 'fresh cycle' 2>&1); RC=$?; set -e
assert_exit "re-open after close succeeds" 0 "$RC"
REOPEN=$(node -e "
const m=require('./.gos/project/project.json').milestone;
console.log([m.name, typeof m.opened_at === 'string', 'closed_at' in m].join('|'))")
[ "$REOPEN" = "fresh-cycle|true|false" ] && { echo "  ✓ re-open replaced the milestone object (name slug-sanitized)"; PASS=$((PASS+1)); } || { echo "  ✗ re-open shape wrong: $REOPEN"; FAIL=$((FAIL+1)); }
t114_teardown

# ===== part 2: five-class replica — dry run, ceremony, byte-equal survivors =====
t114_setup
node "$GOS" init --project --project=replica >/dev/null 2>&1
t114_replica
# MANUAL region rides DECISIONS.md so the snapshot byte-copy guarantee covers
# preserved manual content
printf '\n<!-- MANUAL:notes -->\nceremony note kept verbatim through close\n' >> .gos/project/DECISIONS.md
node "$GOS" render >/dev/null 2>&1
cp .gos/project/project.json preclose-ref.json
cp .gos/project/DECISIONS.md decisions-ref.md
cp .gos/project/ROADMAP.md roadmap-ref.md
cp .gos/project/REQUIREMENTS.md requirements-ref.md

set +e; OUT=$(node "$GOS" milestone close --carry-parked 2>&1); RC=$?; set -e
assert_exit "dry run exits 0" 0 "$RC"
assert_contains "dry-run banner promises zero mutation" "dry run (no --yes): nothing is written" "$OUT"
assert_contains "report counts done-owned decisions" "done-owned — wiped with history (31)" "$OUT"
assert_contains "report counts null-phase decisions" "null-phase — wiped with history (10)" "$OUT"
assert_contains "report counts ghost decisions" "ghost phase ref — wiped with history (10)" "$OUT"
assert_contains "report counts parked-owned decisions" "parked-owned — carried verbatim (1)" "$OUT"
assert_contains "report counts pending-owned decisions" "pending-owned — carried verbatim (18)" "$OUT"
assert_contains "report counts dropped requirements" "dropped — wiped with history (11)" "$OUT"
assert_contains "report separates phases wipe/carry" "done, wiped with history (6)" "$OUT"
assert_contains "dry-run next step names the approval" "record the MILESTONE-CLOSE approval" "$OUT"
if cmp -s .gos/project/project.json preclose-ref.json; then
  echo "  ✓ dry run left project.json byte-identical"; PASS=$((PASS+1))
else
  echo "  ✗ dry run mutated project.json"; FAIL=$((FAIL+1))
fi

# approval freshness: a stale record dies before anything is written
node "$GOS" init 3 "replica holder" >/dev/null 2>&1
node "$GOS" approve milestone-close >/dev/null 2>&1
node -e "
const fs = require('fs');
const s = JSON.parse(fs.readFileSync('.gos/state.json', 'utf8'));
s.approvals['MILESTONE-CLOSE'].ts = '2026-11-01T00:00:00.000Z';
fs.writeFileSync('.gos/state.json', JSON.stringify(s, null, 2));"
set +e; OUT=$(node "$GOS" milestone close --carry-parked --yes 2>&1); RC=$?; set -e
assert_exit "stale approval refuses the close" 1 "$RC"
assert_contains "stale refusal names freshness" "stale or malformed (older than 24h)" "$OUT"
if cmp -s .gos/project/project.json preclose-ref.json; then
  echo "  ✓ stale-approval refusal mutated nothing"; PASS=$((PASS+1))
else
  echo "  ✗ stale-approval refusal mutated project.json"; FAIL=$((FAIL+1))
fi

# missing approval refuses
node -e "
const fs = require('fs');
const s = JSON.parse(fs.readFileSync('.gos/state.json', 'utf8'));
delete s.approvals['MILESTONE-CLOSE'];
fs.writeFileSync('.gos/state.json', JSON.stringify(s, null, 2));"
set +e; OUT=$(node "$GOS" milestone close --carry-parked --yes 2>&1); RC=$?; set -e
assert_exit "close without approval refuses" 1 "$RC"
assert_contains "missing-approval refusal demands sign-off" "requires a recorded MILESTONE-CLOSE approval" "$OUT"

# the real ceremony
node "$GOS" approve milestone-close >/dev/null 2>&1
set +e; OUT=$(node "$GOS" milestone close --carry-parked --yes 2>&1); RC=$?; set -e
assert_exit "close under approval exits 0" 0 "$RC"
assert_contains "approval consumed once" "✓ approval consumed (single-use): MILESTONE-CLOSE" "$OUT"
assert_contains "snapshots stat-verified across both channels" "8 snapshot file(s) stat-verified" "$OUT"
assert_contains "closed line stamps the name" "✓ Milestone closed: replica" "$OUT"
assert_contains "post-close guidance opens the next cycle" "open the next cycle" "$OUT"

CLOSE_DATE=$(date -u +%F)
assert_file "preclose snapshot in project channel" ".gos/project/milestones/replica-$CLOSE_DATE-preclose.json"
assert_file "ROADMAP snapshot in project channel" ".gos/project/milestones/replica-$CLOSE_DATE-ROADMAP.md"
assert_file "REQUIREMENTS snapshot in project channel" ".gos/project/milestones/replica-$CLOSE_DATE-REQUIREMENTS.md"
assert_file "DECISIONS snapshot in project channel" ".gos/project/milestones/replica-$CLOSE_DATE-DECISIONS.md"
CLOSE_HOME=$(ls -d .gos/archive/*/milestone-record 2>/dev/null | head -1)
assert_file "closing record materialized in the archive channel" "$CLOSE_HOME"
assert_file "preclose snapshot in archive channel" "$CLOSE_HOME/replica-$CLOSE_DATE-preclose.json"
if cmp -s ".gos/project/milestones/replica-$CLOSE_DATE-preclose.json" preclose-ref.json; then
  echo "  ✓ preclose.json snapshot is the byte-equal pre-close truth source"; PASS=$((PASS+1))
else
  echo "  ✗ preclose.json snapshot drifted from the pre-close copy"; FAIL=$((FAIL+1))
fi
for V in ROADMAP REQUIREMENTS DECISIONS; do
  REF="roadmap-ref.md"; [ "$V" = "REQUIREMENTS" ] && REF="requirements-ref.md"; [ "$V" = "DECISIONS" ] && REF="decisions-ref.md"
  if cmp -s ".gos/project/milestones/replica-$CLOSE_DATE-$V.md" "$REF"; then
    echo "  ✓ $V.md snapshot byte-equal to the pre-close view (never re-rendered)"; PASS=$((PASS+1))
  else
    echo "  ✗ $V.md snapshot is not a byte copy of the pre-close view"; FAIL=$((FAIL+1))
  fi
done
if grep -q 'ceremony note kept verbatim through close' ".gos/project/milestones/replica-$CLOSE_DATE-DECISIONS.md"; then
  echo "  ✓ MANUAL region survived into the snapshot byte copy"; PASS=$((PASS+1))
else
  echo "  ✗ MANUAL region lost from the snapshot"; FAIL=$((FAIL+1))
fi

SURV=$(t114_survivors_equal preclose-ref.json)
[ "$SURV" = "ok|ok|ok|ok" ] && { echo "  ✓ survivors byte-equal to preclose (rows|reqs|phases|classes)"; PASS=$((PASS+1)); } || { echo "  ✗ survivor drift: $SURV"; FAIL=$((FAIL+1)); }
POST=$(node -e "
const p = require('./.gos/project/project.json');
const doneReqs = p.requirements.filter((r) => r.status !== 'dropped' && ['P0: d0','P1: d1','P2: d2','P3: d3','P4: d4','P5: d5'].includes(r.phase)).length;
console.log([p.phases.map((x) => x.status), p.decisions.length, p.requirements.length, doneReqs, JSON.stringify(p.last_archived_phase), typeof p.milestone.closed_at === 'string'].join('|'))")
[ "$POST" = "parked,pending,pending,pending,pending,pending|19|16|0|null|true" ] && { echo "  ✓ post-close wipe side (carried 6 phases, 19 dec, 16 req, 0 done-owned reqs, last_archived null, closed_at stamped)"; PASS=$((PASS+1)); } || { echo "  ✗ post-close shape wrong: $POST"; FAIL=$((FAIL+1)); }
APPROVED=$(node -e "const s=require('./.gos/state.json'); console.log(('MILESTONE-CLOSE' in (s.approvals||{})) ? 'left' : 'consumed')")
[ "$APPROVED" = "consumed" ] && { echo "  ✓ approval record consumed by the executing close"; PASS=$((PASS+1)); } || { echo "  ✗ approval record survived the close"; FAIL=$((FAIL+1)); }
if grep -q 'ceremony note kept verbatim through close' .gos/project/DECISIONS.md; then
  echo "  ✓ post-close re-render preserved the MANUAL region"; PASS=$((PASS+1))
else
  echo "  ✗ post-close re-render lost MANUAL content"; FAIL=$((FAIL+1))
fi

# same-day close of a fresh milestone proceeds (dated names never collide across names)
node "$GOS" approve milestone-close >/dev/null 2>&1
node "$GOS" milestone open 'replica-two' >/dev/null 2>&1
set +e; OUT=$(node "$GOS" milestone close --empty --carry-parked --yes 2>&1); RC=$?; set -e
assert_exit "same-day close of a new milestone may proceed (fresh dated names)" 0 "$RC"
t114_teardown

# ===== part 2b: bare phase-code refs canonicalize at classification, nothing persisted =====
t114_setup
node "$GOS" init --project --project=bare-refs >/dev/null 2>&1
node -e '
const fs = require("fs");
const p = JSON.parse(fs.readFileSync(".gos/project/project.json", "utf8"));
p.phases = [{ name: "P0: d0", goal: "g", status: "done", completed_at: "2026-11-01T00:00:00.000Z" }, { name: "PK: parked", goal: "g", status: "parked", park_reason: "deps" }];
p.decisions = [{ id: "D-01", title: "bare code ref", rationale: "", birth_phase: "P0", status: "open", anchor: null, covered: false, covered_by: null }];
p.requirements = [{ id: "R-01", text: "canonical too", phase: "PK", status: "active" }];
fs.writeFileSync(".gos/project/project.json", JSON.stringify(p, null, 2));'
cp .gos/project/project.json bare-pre.json
set +e; OUT=$(node "$GOS" milestone close --carry-parked 2>&1); RC=$?; set -e
assert_exit "bare-ref dry run exits 0" 0 "$RC"
assert_contains "bare decision ref classified against the canonical owner" "done-owned — wiped with history (1): D-01" "$OUT"
assert_contains "bare requirement ref classified against the parked owner" "parked-owned — carried verbatim (1): R-01" "$OUT"
if cmp -s .gos/project/project.json bare-pre.json; then
  echo "  ✓ canonicalization stays in memory through the dry run"; PASS=$((PASS+1))
else
  echo "  ✗ dry run persisted canonicalized refs"; FAIL=$((FAIL+1))
fi
t114_teardown

# ===== part 3: crash windows — validate / snapshot / wipe =====
t114_setup
node "$GOS" init --project >/dev/null 2>&1
node "$GOS" phase add "P1: done one" --goal g >/dev/null 2>&1
node "$GOS" phase add "P2: parked one" --goal g >/dev/null 2>&1
node "$GOS" phase add "P3: pend" --goal g >/dev/null 2>&1
node "$GOS" phase mark-done 0 >/dev/null 2>&1
node "$GOS" phase park 1 --reason debt >/dev/null 2>&1
node "$GOS" render >/dev/null 2>&1
node "$GOS" init 3 "window holder" >/dev/null 2>&1
node "$GOS" approve milestone-close >/dev/null 2>&1
cp .gos/project/project.json win-pre.json

set +e; OUT=$(GOS_TEST_BREAK_CLOSE=validate node "$GOS" milestone close --carry-parked --yes 2>&1); RC=$?; set -e
[ "$RC" -ne 0 ] && { echo "  ✓ validate-window crash exits non-zero"; PASS=$((PASS+1)); } || { echo "  ✗ validate-window crash returned 0"; FAIL=$((FAIL+1)); }
assert_contains "validate-window error names the injected stage" "GOS_TEST_BREAK_CLOSE: injected validate failure" "$OUT"
if cmp -s .gos/project/project.json win-pre.json; then
  echo "  ✓ validate window: nothing written"; PASS=$((PASS+1))
else
  echo "  ✗ validate window mutated project.json"; FAIL=$((FAIL+1))
fi
if [ ! -e .gos/project/milestones ]; then
  echo "  ✓ validate window: no snapshots materialized"; PASS=$((PASS+1))
else
  echo "  ✗ validate window materialized snapshots"; FAIL=$((FAIL+1))
fi
if node -e "const s=require('./.gos/state.json'); process.exit('MILESTONE-CLOSE' in s.approvals ? 0 : 1)"; then
  echo "  ✓ validate window: approval NOT consumed"; PASS=$((PASS+1))
else
  echo "  ✗ validate window consumed the approval"; FAIL=$((FAIL+1))
fi

set +e; OUT=$(GOS_TEST_BREAK_CLOSE=snapshot node "$GOS" milestone close --carry-parked --yes 2>&1); RC=$?; set -e
[ "$RC" -ne 0 ] && { echo "  ✓ snapshot-window crash exits non-zero"; PASS=$((PASS+1)); } || { echo "  ✗ snapshot-window crash returned 0"; FAIL=$((FAIL+1)); }
assert_contains "snapshot-window error names the injected stage" "GOS_TEST_BREAK_CLOSE: injected snapshot failure" "$OUT"
NSNAP=$(ls .gos/project/milestones 2>/dev/null | wc -l | tr -d ' ')
assert_eq "snapshot window: snapshots exist" "4" "$NSNAP"
if cmp -s .gos/project/project.json win-pre.json; then
  echo "  ✓ snapshot window: project still whole"; PASS=$((PASS+1))
else
  echo "  ✗ snapshot window wiped project.json early"; FAIL=$((FAIL+1))
fi
if node -e "const s=require('./.gos/state.json'); process.exit('MILESTONE-CLOSE' in s.approvals ? 0 : 1)"; then
  echo "  ✓ snapshot window: approval NOT consumed"; PASS=$((PASS+1))
else
  echo "  ✗ snapshot window consumed the approval"; FAIL=$((FAIL+1))
fi

rm -rf .gos/project/milestones .gos/archive/*close* 2>/dev/null
set +e; OUT=$(GOS_TEST_BREAK_CLOSE=wipe node "$GOS" milestone close --carry-parked --yes 2>&1); RC=$?; set -e
[ "$RC" -ne 0 ] && { echo "  ✓ wipe-window crash exits non-zero"; PASS=$((PASS+1)); } || { echo "  ✗ wipe-window crash returned 0"; FAIL=$((FAIL+1)); }
assert_contains "wipe-window error names the injected stage" "GOS_TEST_BREAK_CLOSE: injected wipe failure" "$OUT"
WIPE=$(node -e "
const p = require('./.gos/project/project.json');
console.log([p.phases.map((x) => x.status).join(','), typeof p.milestone.closed_at === 'string', JSON.stringify(p.last_archived_phase)].join('|'))")
[ "$WIPE" = "parked,pending|true|null" ] && { echo "  ✓ wipe window: project wiped (survivors kept, closed_at stamped, last_archived null)"; PASS=$((PASS+1)); } || { echo "  ✗ wipe-window shape wrong: $WIPE"; FAIL=$((FAIL+1)); }
if node -e "const s=require('./.gos/state.json'); process.exit('MILESTONE-CLOSE' in s.approvals ? 1 : 0)"; then
  echo "  ✓ wipe window: approval consumed"; PASS=$((PASS+1))
else
  echo "  ✗ wipe window left the approval unconsumed"; FAIL=$((FAIL+1))
fi

t114_teardown
echo "--- T114 done: PASS=$PASS FAIL=$FAIL ---"
[ "$FAIL" -eq 0 ] || exit 1
