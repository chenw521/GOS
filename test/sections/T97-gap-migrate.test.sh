#!/usr/bin/env bash
# gos-map:cmd gap,concerns
# : gap migrate + gap history + anchor bootstrap predicate.
# Facts asserted:
#   - `gos gap migrate` (concernsRootLock): legacy "(auto)" mirror lines in
#     concerns.md are removed AND archived to the gap-history ledger
#     (.gos/logs/gap-history.ndjson — one JSON {ts,text} per line); ledger
#     lines == removed mirror lines; anchors + .bak rebuilt from the kept
#     lines in the same transaction; `gos concerns list` verifies rc=0 after
#   - re-run migrate = no-op (nothing-to-migrate wording, ledger unchanged)
#   - dedupe by text: a re-appeared mirror line re-curates the file but never
#     duplicates a ledger row
#   - `gos gap history`: renders ledger entries; malformed lines are skipped
#     and counted, never fatal; empty ledger renders the empty placeholder
#   - bootstrap predicate in loadConcerns: tracked concerns.md + missing
#     anchor + disk blob == HEAD blob → silent anchor rebuild; divergence
#     (uncommitted hand edit) → exit 1, no rebuild (no laundering)
#   - registry 3-way sync: COMMANDS.gap subs + registry-consts sets + gos.cjs
#     dispatch + usage die all carry migrate/history
# Env: GOS, TESTBASE, assert helpers sourced by runner (standalone-safe).
T97_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T97_STANDALONE=1
  T97_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T97_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T97_SELFROOT"
  export TESTBASE="$(mktemp -d "$T97_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T97_DIR=""

t97_fresh() {
  T97_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t97"
  mkdir -p "$T97_DIR" && cd "$T97_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
  # write-class dispatch guard: TESTBASE sits inside GOS_ROOT (an ancestor with
  # .gos/state.json) — a local task state is required for ANY write-class call
  # (same sandbox layout constraint every write-class section runs under).
  node "$GOS" init 1 "t97 gap migrate fixture" >/dev/null 2>&1
}

t97_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T97_DIR"; }

# Append a legacy stage-back mirror line to concerns.md AND keep the hash
# sidecar in sync (the historical writer maintained the anchor — the fixture
# must replicate that, not a desync). $1 = mirror text (sans the sentinel).
t97_add_mirror() {
  node -e '
    const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
    const fs = require("node:fs");
    const line = `- [2026-10-20] [feed0001] ${process.argv[1]} (auto)`;
    let body = "";
    try { body = fs.readFileSync(".gos/concerns.md", "utf8"); } catch { body = "# Concerns (curated worry list — gos concerns add/prune)\n"; }
    if (!body.endsWith("\n")) body += "\n";
    fs.writeFileSync(".gos/concerns.md", body + line + "\n");
    const anchor = JSON.parse(fs.readFileSync(".gos/cache/.concerns-anchors.json", "utf8"));
    anchor.hashes.push(core.sha16(line));
    fs.writeFileSync(".gos/cache/.concerns-anchors.json", JSON.stringify(anchor, null, 2) + "\n");
    fs.writeFileSync(".gos/cache/.concerns-anchors.bak", JSON.stringify(anchor, null, 2) + "\n");
  ' "$1"
}

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

echo "--- T97: gap migrate + gap history + anchor bootstrap (D-16) ---"

# --- M1: mirror fixture → migrate (ledger == removed, 0 remaining (auto)) ---
t97_fresh
node "$GOS" concerns add "manual curated worry" >/dev/null 2>&1
t97_add_mirror "[gap] Fluid back to think: legacy mirror one"
t97_add_mirror "[gap] Fluid back to think: legacy mirror two"
N=$(grep -c '(auto)' .gos/concerns.md || true)
assert_eq "M1 fixture carries 2 mirror lines" "2" "$N"
set +e; OUT=$(node "$GOS" gap migrate 2>&1); RC=$?; set -e
assert_exit "M1 migrate exits 0" "0" "$RC"
assert_contains "M1 migrate reports 2 migrated" "migrated 2" "$OUT"
N=$(grep -c '(auto)' .gos/concerns.md || true)
assert_eq "M1 concerns.md cured (0 (auto) lines)" "0" "$N"
assert_file "M1 ledger created" ".gos/logs/gap-history.ndjson"
L=$(wc -l < .gos/logs/gap-history.ndjson)
assert_eq "M1 ledger lines == removed mirrors" "2" "$L"
FMT=$(python3 -c '
import json, sys
rows = [json.loads(l) for l in open(".gos/logs/gap-history.ndjson") if l.strip()]
assert len(rows) == 2, rows
for r in rows:
    assert set(r.keys()) == {"ts", "text"}, r
    assert isinstance(r["ts"], str) and "T" in r["ts"] and isinstance(r["text"], str), r
assert any("legacy mirror one" in r["text"] for r in rows)
assert all(r["text"].endswith("(auto)") for r in rows)
print("OK")
' 2>&1)
assert_eq "M1 ledger rows are {ts,text} JSON with full mirror text" "OK" "$FMT"
set +e; OUT=$(node "$GOS" concerns list 2>&1); RC=$?; set -e
assert_exit "M1 concerns list verifies after migrate" "0" "$RC"
assert_contains "M1 curated line survives" "manual curated worry" "$OUT"
K=$(python3 -c "import json; print(len(json.load(open('.gos/cache/.concerns-anchors.json'))['hashes']))")
assert_eq "M1 sidecar re-anchored to 1 hash" "1" "$K"

# --- M2: re-run migrate = no-op ---
set +e; OUT=$(node "$GOS" gap migrate 2>&1); RC=$?; set -e
assert_exit "M2 re-run exits 0" "0" "$RC"
assert_contains "M2 nothing-to-migrate wording" "nothing to migrate" "$OUT"
L=$(wc -l < .gos/logs/gap-history.ndjson)
assert_eq "M2 ledger unchanged on no-op" "2" "$L"

# --- M3: dedupe by text — re-appeared mirror never duplicates a ledger row ---
t97_add_mirror "[gap] Fluid back to think: legacy mirror one"
set +e; OUT=$(node "$GOS" gap migrate 2>&1); RC=$?; set -e
assert_exit "M3 re-migrate of known mirror exits 0" "0" "$RC"
assert_contains "M3 dedupe advisory shown" "already in the ledger" "$OUT"
N=$(grep -c '(auto)' .gos/concerns.md || true)
assert_eq "M3 concerns.md cured again" "0" "$N"
L=$(wc -l < .gos/logs/gap-history.ndjson)
assert_eq "M3 ledger still 2 rows (dedupe by text)" "2" "$L"
t97_teardown

# --- M4: history reader — render, malformed skip+count, empty placeholder ---
t97_fresh
node "$GOS" concerns add "m4 seed" >/dev/null 2>&1
t97_add_mirror "[gap] Fluid back to plan: history reads me"
node "$GOS" gap migrate >/dev/null 2>&1
set +e; OUT=$(node "$GOS" gap history 2>&1); RC=$?; set -e
assert_exit "M4 history exits 0" "0" "$RC"
assert_contains "M4 history renders ledger text" "history reads me" "$OUT"
printf 'not-json {\n' >> .gos/logs/gap-history.ndjson
printf '{"ts": 42}\n' >> .gos/logs/gap-history.ndjson
set +e; OUT=$(node "$GOS" gap history 2>&1); RC=$?; set -e
assert_exit "M4 history never dies on malformed lines" "0" "$RC"
assert_contains "M4 skip count advisory" "skipped 2" "$OUT"
assert_contains "M4 good rows still render past malformed" "history reads me" "$OUT"
t97_teardown
t97_fresh
set +e; OUT=$(node "$GOS" gap history 2>&1); RC=$?; set -e
assert_exit "M4 empty ledger exits 0" "0" "$RC"
assert_contains "M4 empty placeholder" "(no gap history" "$OUT"
t97_teardown

# --- M5: bootstrap predicate — tracked + clean + missing anchor → silent rebuild ---
t97_fresh
node "$GOS" concerns add "tracked clean worry" >/dev/null 2>&1
git add .gos/concerns.md && git commit -q -m concerns
rm -f .gos/cache/.concerns-anchors.json .gos/cache/.concerns-anchors.bak
set +e; OUT=$(node "$GOS" concerns list 2>&1); RC=$?; set -e
assert_exit "M5 tracked+clean+missing-anchor list exits 0" "0" "$RC"
if echo "$OUT" | grep -q "bootstrapped"; then
  echo "  ✗ M5 rebuild was not silent (banner leaked)"; FAIL=$((FAIL+1))
else
  echo "  ✓ M5 anchor rebuilt silently"; PASS=$((PASS+1))
fi
assert_file "M5 sidecar recreated" ".gos/cache/.concerns-anchors.json"
assert_file "M5 .bak shadow recreated" ".gos/cache/.concerns-anchors.bak"
K=$(python3 -c "import json; print(len(json.load(open('.gos/cache/.concerns-anchors.json'))['hashes']))")
assert_eq "M5 rebuilt sidecar carries 1 hash" "1" "$K"
t97_teardown

# --- M6: bootstrap predicate — tracked + diverged (hand edit) → die, no rebuild ---
t97_fresh
node "$GOS" concerns add "tracked honest worry" >/dev/null 2>&1
git add .gos/concerns.md && git commit -q -m concerns
printf -- '- [2026-10-21] [bad00001] smuggled hand edit\n' >> .gos/concerns.md
rm -f .gos/cache/.concerns-anchors.json .gos/cache/.concerns-anchors.bak
set +e; OUT=$(node "$GOS" concerns list 2>&1); RC=$?; set -e
assert_exit "M6 tampered tracked file + missing anchor exits 1" "1" "$RC"
assert_contains "M6 die names the HEAD divergence" "differs from the HEAD blob" "$OUT"
if [ -e .gos/cache/.concerns-anchors.json ]; then
  echo "  ✗ M6 anchor rebuilt for a tampered file (laundering)"; FAIL=$((FAIL+1))
else
  echo "  ✓ M6 no rebuild on tamper"; PASS=$((PASS+1))
fi
t97_teardown

# --- M7: registry 3-way sync (COMMANDS + registry-consts + gos.cjs dispatch) ---
REG=$(node -e '
  const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
  const rc = require(process.env.GOS_ROOT + "/bin/lib/nav/registry-consts.cjs");
  const bad = [];
  const subs = core.COMMANDS.gap.subs.join(",");
  if (!/\bmigrate\b/.test(subs)) bad.push("COMMANDS.gap.subs missing migrate");
  if (!/\bhistory\b/.test(subs)) bad.push("COMMANDS.gap.subs missing history");
  if (!rc.KNOWN_CASES.includes("gap")) bad.push("KNOWN_CASES missing gap");
  if (!rc.WRITE_CMDS.has("gap")) bad.push("WRITE_CMDS missing gap");
  if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
  console.log("OK");
' 2>&1)
assert_eq "M7 registry tables carry migrate/history" "OK" "$REG"
DISP=$(grep -c "case 'gap':" "$GOS_ROOT/bin/gos.cjs" || true)
assert_eq "M7 gos.cjs dispatch routes gap" "1" "$DISP"
HELP=$(node "$GOS" help gap 2>&1)
assert_contains "M7 help renders migrate" "migrate" "$HELP"
assert_contains "M7 help renders history" "history" "$HELP"
t97_fresh   # usage die needs a state-bearing cwd (write-class guard runs first)
set +e; OUT=$(node "$GOS" gap bogus 2>&1); RC=$?; set -e
assert_exit "M7 unknown sub exits 1" "1" "$RC"
assert_contains "M7 usage die lists all five subs" "list|resolve|rewrite|migrate|history" "$OUT"

t97_teardown
if [ "$T97_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi

echo "--- T97 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
