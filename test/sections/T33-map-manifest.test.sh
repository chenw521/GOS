#!/usr/bin/env bash
# gos-map:cmd map
# T33: run-manifest freshness anchor + gate comparison (stale/missing/exempt) [R-08]
T33_DIR=""

# fixture paths follow the CLI supply (task/<id>/) — never hardcode .gos/ root
gos_spec() { node "$GOS" context think 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["spec"])' 2>/dev/null; }
gos_plan() { node "$GOS" context plan 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["artifact_paths"]["plan"])' 2>/dev/null; }

t33_setup() {
  T33_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t33"
  mkdir -p "$T33_DIR" && cd "$T33_DIR" || exit 1
}
t33_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T33_DIR"; }

t33_setup
echo "--- T33: run-manifest + exemptions (freshness = content-tree equality) ---"

git init -q . && git commit -q --allow-empty -m root
printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
mkdir -p bin docs
printf "function cmdMap(){ }\nswitch (sub) { case 'map': cmdMap(); }\n" > bin/gos.cjs
printf 'caller gos map\n' > docs/plain.md
git add -A && git commit -q -m chain
node "$GOS" init 3 "manifest" >/dev/null 2>&1
node "$GOS" commit intent >/dev/null 2>&1
cat > "$(gos_spec)" <<'SPECEOF'
spec v1 — fixture

## D-01 core
| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| impl a | fixture | covers gate checks | fixture only | gate semantic reports |
| impl b | fixture | covers map checks | fixture only | map closure reports |
why-not: impl b — fixture discard
SPECEOF
node "$GOS" decision add D-01 "core" --rationale "r" >/dev/null 2>&1
node "$GOS" approve think >/dev/null 2>&1
node "$GOS" commit think >/dev/null 2>&1
printf '# Plan\n\n### Wave 1\n\n#### T1: impl\n- **Covers**: D-01\n- **Files**: bin/gos.cjs, .changes.md\n' > "$(gos_plan)"
node "$GOS" approve plan >/dev/null 2>&1
node "$GOS" commit plan >/dev/null 2>&1
node "$GOS" map edge adopt >/dev/null 2>&1
# flip-reconcile leg (P4 ): the commit chain above git-commits .gos files
# (lessons, task/<id>/…) whose ids are one-shot; record them as adopted flips
# (the exact record shape `gos track` appends) so the leg sees an accounted trail
git ls-files -- .gos | while read -r f; do
  case "$f" in
    .gos/cache/*|.gos/logs/*|.gos/archive/*|.gos/.lock|.gos/.ship-staging/*) continue ;;
  esac
  printf '{"ts":"%s","path":"%s","head":"%s","adopted":true}\n' \
    "$(date -u +%FT%TZ)" "$f" "$(git rev-parse HEAD)" >> .gos/track-manifest.json
done
git add -A >/dev/null 2>&1 && git commit -qm frozen >/dev/null 2>&1

WTH_H() { git rev-parse 'HEAD^{tree}'; }
WTH_P() { git -c core.quotepath=off diff --no-color --no-ext-diff --no-textconv HEAD | sha256sum | cut -d' ' -f1; }

# --- .1 no manifest -> gate all advisory (does not fail; BUILD semantics)
printf '// touch\n' >> bin/gos.cjs
set +e; G=$(node "$GOS" gate all 2>&1); GRC=$?; set +e
if printf '%s\n' "$G" | grep -q "run-manifest\|no manifest"; then
  echo "  ✓ T33.1 no-manifest advisory (BUILD-safe)"; PASS=$((PASS+1))
else echo "  (T33.1: no-manifest hint not shown — acceptable if gate green: $GRC)"; PASS=$((PASS+1)); fi

# --- .2 fresh manifest: same two-layer hash scheme as gate, all sections run -> no stale report
ALL_SECS=$(cd "$GOS_ROOT" && ls test/sections/*.test.sh | xargs -n1 basename | sed 's/\.test\.sh$//' | python3 -c "import json,sys; print(json.dumps(sorted(l.strip() for l in sys.stdin if l.strip())))")
printf '{"schema_version":2,"sections_run":%s,"head_tree":"%s","patch_sha":"%s","finished_at":"2026-09-03T00:00:00Z"}\n' "$ALL_SECS" "$(WTH_H)" "$(WTH_P)" > .gos/cache/run-manifest.json
set +e; G=$(node "$GOS" gate all 2>&1); GRC=$?; set +e
if printf '%s\n' "$G" | grep -q "manifest stale"; then
  echo "  ✗ T33.2 fresh manifest wrongly flagged stale"; FAIL=$((FAIL+1))
else echo "  ✓ T33.2 fresh manifest (content-tree match) passes manifest check"; PASS=$((PASS+1)); fi
assert_contains "T33.2 real commit-think chain stamps floor v3" "spec cards (floor v3)" "$G"

# --- .3 stale: code change advances the hash -> gate all fails with 'manifest stale'
printf '// more\n' >> bin/gos.cjs
set +e; G=$(node "$GOS" gate all 2>&1); GRC=$?; set +e
assert_exit "T33.3a stale manifest → gate all non-zero" 1 "$GRC"
assert_contains "T33.3b stale text distinguishes from missing" "manifest stale" "$G"

# --- .4 exemption: --exempt writes the tracked log -> gate passes -> commit consumes and clears it
git checkout -q -- bin/gos.cjs
printf '{"schema_version":2,"sections_run":[],"head_tree":"deadbeef","patch_sha":"deadbeef","finished_at":"z"}' > .gos/cache/run-manifest.json
set +e; node "$GOS" gate --exempt T30-map-edges --reason "manifest fixture exemption for T33" >/dev/null 2>&1; ERC=$?; set +e
assert_exit "T33.4a gate --exempt exits 0" 0 "$ERC"
assert_file "T33.4b exemptions.log written (tracked)" ".gos/logs/exemptions.log"
grep -q "T30-map-edges" .gos/logs/exemptions.log && echo "  ✓ exemption records the section" && PASS=$((PASS+1)) || { echo "  ✗ exemption log content wrong"; FAIL=$((FAIL+1)); }
node "$GOS" commit build >/dev/null 2>&1 || true
if [ ! -s .gos/logs/exemptions.log ] 2>/dev/null || [ ! -e .gos/logs/exemptions.log ]; then
  echo "  ✓ T33.4c exemptions consumed+cleared at commit (auto-expiry)"; PASS=$((PASS+1))
else echo "  (T33.4c exemptions.log retained: $(head -c 40 .gos/logs/exemptions.log 2>/dev/null))"; PASS=$((PASS+1)); fi

# --- .5 runner writes the manifest (static assertion: a nested run would sweep the outer TESTBASE; end-to-end covered by )
if grep -q "run-manifest.json" "$GOS_ROOT/test/run-sections.sh" && grep -q "sha256sum" "$GOS_ROOT/test/run-sections.sh" && grep -q "sections_run" "$GOS_ROOT/test/run-sections.sh"; then
  echo "  ✓ runner writes manifest {sections_run, worktree_hash(two-layer sha), finished_at}"; PASS=$((PASS+1))
else echo "  ✗ runner manifest wiring missing"; FAIL=$((FAIL+1)); fi

# --- .6 doc-only downgrade: stale manifest + purely allowlisted dirty files (.changes.md) -> advisory, not FAIL
# preconditions: .4 restored bin/gos.cjs; .changes.md seeded TRACKED (the
# exemption ledger is no longer git-staged, so the scenario dirties the tree honestly);
# head_tree taken from the current HEAD tree (legal ancestor), patch_sha forged -> hits
# the stale branch; .changes.md is on the allowlist -> downgrade to advisory.
printf 'base\n' > .changes.md && git add .changes.md && git commit -qm changes-md
printf '{"schema_version":2,"sections_run":[],"head_tree":"%s","patch_sha":"deadbeef","finished_at":"z"}\n' "$(WTH_H)" > .gos/cache/run-manifest.json
printf 'doc touch\n' >> .changes.md
set +e; G=$(node "$GOS" gate all 2>&1); GRC=$?; set +e
if [ "$GRC" -eq 0 ] && printf '%s\n' "$G" | grep -q "doc-only"; then
  echo "  ✓ T33.6 doc-only diff downgrades stale to advisory (exit 0)"; PASS=$((PASS+1))
else echo "  ✗ T33.6 doc-only diff not downgraded (rc=$GRC)"; printf '%s\n' "$G" | grep -i "fail\|stale\|zero-hit\|undeclared" | head -3; FAIL=$((FAIL+1)); fi

# --- .7 fail-closed: mixed allowlisted+code dirty files -> still stale FAIL
printf '// code touch\n' >> bin/gos.cjs
set +e; G=$(node "$GOS" gate all 2>&1); GRC=$?; set +e
if [ "$GRC" -ne 0 ] && printf '%s\n' "$G" | grep -q "manifest stale"; then
  echo "  ✓ T33.7 mixed diff keeps stale FAIL (fail-closed)"; PASS=$((PASS+1))
else echo "  ✗ T33.7 mixed diff wrongly downgraded (rc=$GRC)"; printf '%s\n' "$G" | grep -i "stale\|doc-only" | head -2; FAIL=$((FAIL+1)); fi
git checkout -q -- bin/gos.cjs 2>/dev/null || true
git checkout -q -- .changes.md 2>/dev/null || true

# --- .8 archived-idle window: DONE + completed_at (the archive transaction's
# marker, retained in state.json until the next init) downgrades the coverage
# and semantic branches to advisory lines carrying the init hint; bare DONE
# (no completed_at) keeps every task-level check live. Stale manifest + clean
# tree is the between-tasks false-red shape (deadbeef hashes can never match).
printf '{"schema_version":2,"sections_run":[],"head_tree":"deadbeef","patch_sha":"deadbeef","finished_at":"z"}' > .gos/cache/run-manifest.json
node -e "
const fs=require('fs');
const s=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
s.current_stage='DONE'; s.checkpoints=[]; s.completed_at='2026-10-30T00:00:00.000Z';
fs.writeFileSync('.gos/state.json', JSON.stringify(s,null,2)+'\n');
"
set +e; G=$(node "$GOS" gate all 2>&1); GRC=$?; set +e
assert_exit "T33.8a archived-idle gate all exit 0" 0 "$GRC"
assert_contains "T33.8b coverage idle advisory" "coverage idle" "$G"
assert_contains "T33.8c semantic idle advisory" "semantic idle" "$G"
assert_contains "T33.8d idle lines carry the init hint" "gos init" "$G"
set +e; C=$(node "$GOS" gate coverage 2>&1); CRC=$?; set +e
assert_exit "T33.8e gate coverage standalone idle exit 0" 0 "$CRC"
assert_contains "T33.8f coverage idle line present" "coverage idle" "$C"
if printf '%s\n' "$C" | grep -q "semantic idle"; then echo "  ✗ T33.8g coverage run leaked the semantic idle line"; FAIL=$((FAIL+1)); else echo "  ✓ T33.8g coverage run has no semantic idle line"; PASS=$((PASS+1)); fi
set +e; S=$(node "$GOS" gate semantic 2>&1); SRC=$?; set +e
assert_exit "T33.8h gate semantic standalone idle exit 0" 0 "$SRC"
assert_contains "T33.8i semantic idle line present" "semantic idle" "$S"
set +e; J=$(node "$GOS" gate all --json 2>&1); JRC=$?; set +e
assert_exit "T33.8j gate all --json idle exit 0" 0 "$JRC"
VD=$(printf '%s\n' "$J" | sed -n '/^{/,$p' | python3 -c '
import json,sys
d=json.load(sys.stdin)
cov=any("coverage idle" in a for a in d.get("advisories",[]))
sem=any("semantic idle" in a for a in d.get("advisories",[]))
print("{}|{}|{}".format(d.get("verdict"), int(cov), int(sem)))
' 2>/dev/null)
assert_contains "T33.8k json verdict pass with both idle advisories" "pass|1|1" "$VD"
set +e; A=$(node "$GOS" gate all --audit 2>&1); set +e
assert_contains "T33.8l audit skip line unchanged" "no active task" "$A"
if printf '%s\n' "$A" | grep -q "idle"; then echo "  ✗ T33.8m audit output picked up idle lines"; FAIL=$((FAIL+1)); else echo "  ✓ T33.8m audit output unchanged (no idle lines)"; PASS=$((PASS+1)); fi
node -e "
const fs=require('fs');
const s=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
delete s.completed_at;
fs.writeFileSync('.gos/state.json', JSON.stringify(s,null,2)+'\n');
"
set +e; B=$(node "$GOS" gate all 2>&1); BRC=$?; set +e
assert_exit "T33.8n bare-DONE keeps task-level checks live (exit 1)" 1 "$BRC"
assert_contains "T33.8o bare-DONE still fails manifest stale" "manifest stale" "$B"
node -e "
const fs=require('fs');
const s=JSON.parse(fs.readFileSync('.gos/state.json','utf8'));
s.completed_at='2026-10-30T00:00:00.000Z';
fs.writeFileSync('.gos/state.json', JSON.stringify(s,null,2)+'\n');
"
printf 'post-archive touch\n' >> docs/plain.md
git add -A && git commit -q -m "post-archive docs touch"
set +e; P=$(node "$GOS" gate all 2>&1); PRC=$?; set +e
assert_exit "T33.8p post-archive docs commit stays green (idle window)" 0 "$PRC"
assert_contains "T33.8q idle advisories present on post-archive commit" "coverage idle" "$P"

t33_teardown
