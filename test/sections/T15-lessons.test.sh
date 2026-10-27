#!/usr/bin/env bash
# gos-map:cmd lessons
# : lessons JSON truth store + command family (P15 wave 1 rewrite)
# Covers: five invariants, migrate state machine, add/rm/amend/list/prune/
#         skip/anchor-rebuild/migrate, canary injection, promotion lineage
# Env: GOS (CLI path), TESTBASE (isolated base), assert helpers sourced by runner
# ALL global-path assertions use fake-HOME (HOME=$T15_DIR/home) [R3-F7]
T15_DIR=""
T15_HOME=""

t15_setup() {
  T15_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t15"
  mkdir -p "$T15_DIR" && cd "$T15_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
  T15_HOME="$T15_DIR/home"
  mkdir -p "$T15_HOME"
}

t15_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T15_DIR"; }

t15_g() { HOME="$T15_HOME" node "$GOS" "$@"; }

# node helper against the CLI's own lessons-json module (fixture fabrication
# with VALID ids/hashes — never hand-rolled bytes)
t15_node() { HOME="$T15_HOME" node -e "$1"; }

t15_setup
echo "--- T15: lessons json truth + command family ---"

t15_g init 2 "t15 project lessons" >/dev/null 2>&1

if [ -e "$HOME/.config/gos/lessons.json" ]; then
  echo "  ✗ REAL HOME polluted before test"; FAIL=$((FAIL+1))
else
  echo "  ✓ real HOME clean before test"; PASS=$((PASS+1))
fi

# --- .1: structured model add → global json truth + truth-bak + auto+90d + audit row
OUT=$(t15_g lessons add --type model --scene "deploy" --lesson "canary model lesson for T15" --tags ops,canary 2>&1)
GJSON="$T15_HOME/.config/gos/lessons.json"
EXP90=$(date -d "+90 days" +%F 2>/dev/null || date -v+90d +%F)
if [ -f "$GJSON" ] && grep -q "canary model lesson for T15" "$GJSON" && grep -q '"scene": "deploy"' "$GJSON"; then
  echo "  ✓ model lesson structured in global lessons.json"; PASS=$((PASS+1))
else
  echo "  ✗ model lesson NOT structured in global json"; echo "    out: $OUT"; FAIL=$((FAIL+1))
fi
assert_contains "model auto-expires +90d ($EXP90)" "(expires $EXP90)" "$(t15_g lessons list 2>&1)"
assert_contains "globalWriteHint line printed" "model-type lesson written globally" "$OUT"
if [ -f "$T15_HOME/.config/gos/.lessons.json.bak" ]; then
  echo "  ✓ global truth-bak shadow exists"; PASS=$((PASS+1))
else
  echo "  ✗ global .lessons.json.bak missing"; FAIL=$((FAIL+1))
fi
if python3 -c "import json; s=json.load(open('$GJSON')); assert any(r['what']=='add' and r.get('new_id') for r in s['audit'])" 2>/dev/null; then
  echo "  ✓ add audit row with new_id in json chain"; PASS=$((PASS+1))
else
  echo "  ✗ add audit row missing"; FAIL=$((FAIL+1))
fi

# --- .2: project add → .gos/lessons.json + derived sidecar + generated md
OUT=$(t15_g lessons add --type project --scene "build" --lesson "project lesson entry" --tags p15 2>&1)
if [ -f ".gos/lessons.json" ] && grep -q "project lesson entry" ".gos/lessons.json"; then
  echo "  ✓ project lesson in .gos/lessons.json (tracked truth)"; PASS=$((PASS+1))
else
  echo "  ✗ project lesson NOT in json"; echo "    out: $OUT"; FAIL=$((FAIL+1))
fi
if python3 -c "import json; s=json.load(open('.gos/cache/.lessons-anchors.json')); assert isinstance(s.get('live_ids'), list) and len(s['live_ids'])==1" 2>/dev/null; then
  echo "  ✓ derived sidecar {live_ids} synced"; PASS=$((PASS+1))
else
  echo "  ✗ derived sidecar wrong"; FAIL=$((FAIL+1))
fi
if grep -q "gos:generated lessons-md render-hash:" ".gos/lessons.md" 2>/dev/null && grep -q "project lesson entry" ".gos/lessons.md"; then
  echo "  ✓ md view regenerated with render-hash header"; PASS=$((PASS+1))
else
  echo "  ✗ md view missing/ungenerated"; FAIL=$((FAIL+1))
fi

# --- .2b: --text legacy shorthand accepted with advisory
OUT=$(t15_g lessons add --type project --text "bare text shorthand" 2>&1); RC=$?
assert_exit "--text shorthand accepted" "0" "$RC"
if python3 -c "import json; s=json.load(open('.gos/lessons.json')); e=[x for x in s['entries'] if x.get('text')=='bare text shorthand']; assert e and e[0]['origin']=='v2'" 2>/dev/null; then
  echo "  ✓ text stored as text field (origin v2)"; PASS=$((PASS+1))
else
  echo "  ✗ text shorthand not stored"; FAIL=$((FAIL+1))
fi
assert_contains "advisory recommends structured fields" "structured" "$OUT"

# --- .3: list grouped render — taxonomy labels + id prefix + source
OUT=$(t15_g lessons list 2>&1); RC=$?
assert_exit "list exits 0" "0" "$RC"
assert_contains "plain taxonomy project label" "repo knowledge" "$OUT"
assert_contains "plain taxonomy model label" "cross-repo behavior" "$OUT"
if echo "$OUT" | grep -qE '\([0-9a-f]{8}\)'; then
  echo "  ✓ id prefix shown for addressability"; PASS=$((PASS+1))
else
  echo "  ✗ no id prefixes in list"; FAIL=$((FAIL+1))
fi

# --- T15.4: injection canaries [B-17] ---
rm -f pwned
OUT=$(t15_g lessons add --type project --lesson "'\$(touch pwned)'" 2>&1); RC=$?
assert_exit "shell-substitution canary rejected" "1" "$RC"
if [ -e pwned ]; then echo "  ✗ canary EXECUTED"; FAIL=$((FAIL+1)); else echo "  ✓ no canary side effect"; PASS=$((PASS+1)); fi
OUT=$(t15_g lessons add --type project --scene "s" --lesson $'- line\n- [injected] fake' 2>&1); RC=$?
assert_exit "newline list-entry injection rejected" "1" "$RC"
if grep -q "injected" ".gos/lessons.json" 2>/dev/null; then echo "  ✗ injected line landed in json"; FAIL=$((FAIL+1)); else echo "  ✓ no injected line in json"; PASS=$((PASS+1)); fi

OUT=$(t15_g lessons add --type wrong --lesson x 2>&1); RC=$?
assert_exit "illegal --type rejected" "1" "$RC"
OUT=$(t15_g lessons add --type model --lesson x --expires 2020-01-01 2>&1); RC=$?
assert_exit "past --expires rejected" "1" "$RC"
OUT=$(t15_g lessons add --type model --lesson x --expires notadate 2>&1); RC=$?
assert_exit "malformed --expires rejected" "1" "$RC"
OUT=$(t15_g lessons add --type project --lesson x --tags "a,b|c" 2>&1); RC=$?
assert_exit "tag with reserved pipe rejected" "1" "$RC"

# --- .6: hand-delete entry from json → adjudicating read fails closed; anchor-rebuild --force recovers
T15_TARGET=$(python3 -c "import json; s=json.load(open('.gos/lessons.json')); print([e['id'] for e in s['entries'] if e.get('scene')=='build'][0])")
python3 - "$T15_TARGET" <<'PYEOF'
import json, sys
p = '.gos/lessons.json'
s = json.load(open(p))
s['entries'] = [e for e in s['entries'] if e['id'] != sys.argv[1]]
json.dump(s, open(p, 'w'), indent=2)
PYEOF
OUT=$(t15_g lessons list 2>&1); RC=$?
assert_exit "hand-deleted entry → adjudicating load fails closed" "1" "$RC"
assert_contains "B-8 pure-deletion named" "pure-deletion" "$OUT"
OUT=$(t15_g lessons anchor-rebuild --force 2>&1); RC=$?
assert_exit "anchor-rebuild --force recovers (forced disposal audit row)" "0" "$RC"
OUT=$(t15_g lessons list 2>&1); RC=$?
assert_exit "list green after forced disposal" "0" "$RC"

# --- T15.7: audit chain tamper → fail-closed [B-14] ---
cp .gos/lessons.json lessons.bak.json
python3 - <<'PYEOF'
import json
p = '.gos/lessons.json'
s = json.load(open(p))
if s['audit']:
    s['audit'][0]['why'] = (s['audit'][0].get('why') or 'x') + 'TAMPER'
json.dump(s, open(p, 'w'), indent=2)
PYEOF
OUT=$(t15_g lessons add --type project --lesson "after tamper" 2>&1); RC=$?
assert_exit "tampered audit row → chain broken fail-closed" "1" "$RC"
assert_contains "B-14 named" "B-14" "$OUT"
cp lessons.bak.json .gos/lessons.json

# --- .8: preserve-id mutation (F2) — edit content keep id → drift
python3 - <<'PYEOF'
import json
p = '.gos/lessons.json'
s = json.load(open(p))
if s['entries']:
    s['entries'][0]['lesson'] = s['entries'][0].get('lesson', 'x') + ' MUTATED'
json.dump(s, open(p, 'w'), indent=2)
PYEOF
OUT=$(t15_g lessons list 2>&1); RC=$?
assert_exit "content mutated with preserved id → fail-closed" "1" "$RC"
cp lessons.bak.json .gos/lessons.json

# --- .9: shape injection into a raw legacy entry (fifth invariant; isolated sandbox)
T15_SHAPE="$TESTBASE/test-$(date +%s)-$RANDOM-t15shape"
mkdir -p "$T15_SHAPE/.gos/cache" && cd "$T15_SHAPE" || exit 1
git init -q . && git commit -q --allow-empty -m root
printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
t15_g init 2 "t15 shape" >/dev/null 2>&1
t15_node '
const j = require(process.env.GOS_ROOT + "/bin/lib/knowledge/lessons-json.cjs");
const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
const fs = require("fs");
const line = "- [2026-08-14] [project] legacy raw entry for shape test";
const store = j.emptyStore();
store.entries.push({ id: core.sha16(line), at: "2026-08-14", type: "project", text: "legacy raw entry for shape test", origin: "legacy", tags: ["injected"] });
j.appendAuditRow(store, "migrate", "fixture", { count: 1 });
fs.mkdirSync(".gos/cache", { recursive: true });
j.saveStore({ truth: ".gos/lessons.json", anchor: ".gos/cache/.lessons-anchors.json", file: ".gos/lessons.md", global: false }, store);
'
OUT=$(t15_g lessons list 2>&1); RC=$?
assert_exit "injected tags on raw legacy entry → drift fail-closed" "1" "$RC"
assert_contains "shape whitelist named" "non-legacy field" "$OUT"
cd "$T15_DIR" || exit 1
rm -rf "$T15_SHAPE"

# --- .10: auto-migration on first mutation — kept line-hash ids + backup + sentinel
T15_MIG="$TESTBASE/test-$(date +%s)-$RANDOM-t15mig"
mkdir -p "$T15_MIG/.gos" && cd "$T15_MIG" || exit 1
git init -q . && git commit -q --allow-empty -m root
printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
cat > .gos/lessons.md <<'EOF'
# Lessons (cross-task experience library)
- [2026-08-14] [model] legacy model line kept verbatim (expires 2026-11-12)
- [2026-08-18] [project] legacy project line kept verbatim
EOF
t15_g init 2 "t15 migrate" >/dev/null 2>&1
OUT=$(t15_g lessons add --type project --scene "m" --lesson "post-migration add" 2>&1); RC=$?
assert_exit "first mutation auto-migrates" "0" "$RC"
if python3 -c "
import json, hashlib
s = json.load(open('.gos/lessons.json'))
line = '- [2026-08-14] [model] legacy model line kept verbatim (expires 2026-11-12)'
want = hashlib.sha256(line.encode()).hexdigest()[:16]
assert any(e['id'] == want and e['origin'] == 'legacy' for e in s['entries']), 'kept id mismatch'
assert any(e.get('scene') == 'm' for e in s['entries']), 'new entry missing'
assert any(r['what'] == 'migrate' for r in s['audit']), 'migrate row missing'
" 2>/dev/null; then
  echo "  ✓ legacy ids kept byte-exact + migrate audit row"; PASS=$((PASS+1))
else
  echo "  ✗ migration entries/audit wrong"; FAIL=$((FAIL+1))
fi
if ls .gos/lessons-migration-backup-*.md >/dev/null 2>&1 && grep -q "legacy model line kept verbatim" .gos/lessons-migration-backup-*.md; then
  echo "  ✓ migration backup exists with original content"; PASS=$((PASS+1))
else
  echo "  ✗ migration backup missing"; FAIL=$((FAIL+1))
fi
# genesis guard ( , sentinel deleted): a deleted-but-committed lessons.json
# must be RESTORED, never re-migrated (fresh chain would launder the deletion)
git add .gos/lessons.json >/dev/null 2>&1 && git commit -q -m "lessons: track migrated truth"
rm -f .gos/lessons.json
OUT=$(t15_g lessons add --type project --scene "gx" --lesson "genesis probe" 2>&1); RC=$?
assert_exit "deleted-but-committed lessons.json refuses re-migration" "1" "$RC"
assert_contains "genesis guard says restore, don't remigrate" "restore, don't remigrate" "$OUT"
cd "$T15_DIR" || exit 1
rm -rf "$T15_MIG"

# --- .11: rm — reason mandatory, disposal audit row
T15_RM=$(python3 -c "import json; s=json.load(open('.gos/lessons.json')); print([e for e in s['entries'] if e.get('text')=='bare text shorthand'][0]['id'][:6])")
OUT=$(t15_g lessons rm "$T15_RM" 2>&1); RC=$?
assert_exit "rm without --reason rejected" "1" "$RC"
OUT=$(t15_g lessons rm "$T15_RM" --reason "t15 rm canary" 2>&1); RC=$?
assert_exit "rm with reason succeeds" "0" "$RC"
if python3 -c "
import json
s = json.load(open('.gos/lessons.json'))
assert not any(e['id'].startswith('$T15_RM') for e in s['entries']), 'entry still present'
assert any(r['what']=='rm' and r.get('old_id','').startswith('$T15_RM') and r.get('prev_sha') for r in s['audit']), 'rm audit row missing'
" 2>/dev/null; then
  echo "  ✓ rm disposal audit row {old_id, prev_sha}"; PASS=$((PASS+1))
else
  echo "  ✗ rm audit wrong"; FAIL=$((FAIL+1))
fi
OUT=$(t15_g lessons rm "$T15_RM" --reason "again" 2>&1); RC=$?
assert_exit "rm unknown prefix → no match die" "1" "$RC"

# --- .12: prefix ambiguity → reject + list candidates
t15_node '
const j = require(process.env.GOS_ROOT + "/bin/lib/knowledge/lessons-json.cjs");
const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
const fs = require("fs");
const s = JSON.parse(fs.readFileSync(".gos/lessons.json", "utf8"));
const mk = (n) => ({ at: "2026-09-24", type: "project", scene: "amb" + n, lesson: "ambiguity probe " + n, tags: [], origin: "v2" });
let a = mk(1);
for (let i = 2; i < 200000; i++) {
  const b = mk(i);
  if (core.sha16(j.canonV2(b)).slice(0, 4) === core.sha16(j.canonV2(a)).slice(0, 4)) {
    const ia = core.sha16(j.canonV2(a)), ib = core.sha16(j.canonV2(b));
    s.entries.push({ id: ia, ...a }, { id: ib, ...b });
    fs.writeFileSync(".gos/amb-prefix", ia.slice(0, 4));
    break;
  }
}
j.saveStore({ truth: ".gos/lessons.json", anchor: ".gos/cache/.lessons-anchors.json", file: ".gos/lessons.md", global: false }, s);
'
if [ -f .gos/amb-prefix ]; then
  AMBP=$(cat .gos/amb-prefix)
  OUT=$(t15_g lessons rm "$AMBP" --reason "ambiguous" 2>&1); RC=$?
  assert_exit "ambiguous prefix rejected" "1" "$RC"
  assert_contains "ambiguity lists candidates" "candidates" "$OUT"
else
  echo "  ✗ ambiguity pair not fabricated"; FAIL=$((FAIL+1))
fi

# --- .13: amend promotion — origin stays legacy, new id, lineage row
T15_PROM="$TESTBASE/test-$(date +%s)-$RANDOM-t15prom"
mkdir -p "$T15_PROM/.gos/cache" && cd "$T15_PROM" || exit 1
git init -q . && git commit -q --allow-empty -m root
printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
t15_g init 2 "t15 promote" >/dev/null 2>&1
t15_node '
const j = require(process.env.GOS_ROOT + "/bin/lib/knowledge/lessons-json.cjs");
const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
const fs = require("fs");
const line = "- [2026-08-18] [project] legacy prose entry awaiting structured rewrite";
const store = j.emptyStore();
store.entries.push({ id: core.sha16(line), at: "2026-08-18", type: "project", text: "legacy prose entry awaiting structured rewrite", origin: "legacy" });
j.appendAuditRow(store, "migrate", "fixture", { count: 1 });
j.saveStore({ truth: ".gos/lessons.json", anchor: ".gos/cache/.lessons-anchors.json", file: ".gos/lessons.md", global: false }, store);
console.log(core.sha16(line).slice(0, 6));
' > .gos/prom-prefix
PROM=$(cat .gos/prom-prefix)
OUT=$(t15_g lessons amend "$PROM" --scene "deploy" --lesson "rewritten structured lesson" --tags ops 2>&1); RC=$?
assert_exit "amend promotes legacy entry" "0" "$RC"
if python3 -c "
import json
s = json.load(open('.gos/lessons.json'))
e = [x for x in s['entries'] if x.get('lesson') == 'rewritten structured lesson']
assert e and e[0]['origin'] == 'legacy' and not e[0]['id'].startswith('$PROM'), 'promotion shape wrong'
r = [x for x in s['audit'] if x['what'] == 'edit']
assert r and r[-1].get('old_id','').startswith('$PROM') and r[-1].get('new_id') == e[0]['id'] and r[-1].get('prev_sha'), 'lineage row missing'
" 2>/dev/null; then
  echo "  ✓ promotion: origin preserved + edit lineage {old_id,new_id,prev_sha}"; PASS=$((PASS+1))
else
  echo "  ✗ promotion lineage wrong"; FAIL=$((FAIL+1))
fi
OUT=$(t15_g lessons list 2>&1); RC=$?
assert_exit "store still verifies after promotion" "0" "$RC"
cd "$T15_DIR" || exit 1
rm -rf "$T15_PROM"

# --- .14: prune — expired batch + permanent block
t15_node '
const j = require(process.env.GOS_ROOT + "/bin/lib/knowledge/lessons-json.cjs");
const fs = require("fs");
const store = j.emptyStore();
const mk = (scene, lesson, expires, permanent) => {
  const base = { at: "2026-01-01", type: permanent ? "project" : "model", scene, lesson, tags: [], origin: "v2", ...(expires ? { expires } : {}), ...(permanent ? { permanent: true } : {}) };
  const { id } = j.mintId(base, () => false);
  store.entries.push({ id, ...base });
  j.appendAuditRow(store, "add", "fixture", { new_id: id });
};
mk("x", "expired normal", "2026-01-02", false);
mk("y", "expired permanent", "2026-01-02", true);
j.saveStore({ truth: ".gos/lessons.json", anchor: ".gos/cache/.lessons-anchors.json", file: ".gos/lessons.md", global: false }, store);
'
OUT=$(t15_g lessons prune --type project 2>&1); RC=$?
if echo "$OUT" | grep -qi "permanent" && [ "$RC" = "1" ]; then
  echo "  ✓ prune refuses permanent expired entry"; PASS=$((PASS+1))
else
  echo "  ✗ permanent block failed (rc=$RC out=$OUT)"; FAIL=$((FAIL+1))
fi
OUT=$(t15_g lessons prune --type project --force 2>&1); RC=$?
assert_exit "prune --force disposes expired" "0" "$RC"
if python3 -c "import json; s=json.load(open('.gos/lessons.json')); assert not any(e.get('scene')=='x' or e.get('scene')=='y' for e in s['entries'])" 2>/dev/null; then
  echo "  ✓ expired entries disposed"; PASS=$((PASS+1))
else
  echo "  ✗ expired entries still present"; FAIL=$((FAIL+1))
fi

# --- .15: skip → json audit row + cumulative count; sealed .changes.md untouched
OUT=$(t15_g lessons skip --reason "t15 skip reason canary" 2>&1); RC=$?
assert_exit "skip exits 0" "0" "$RC"
assert_contains "skip output shows audit-row record" "audit row" "$OUT"
assert_contains "skip output shows cumulative count" "cumulative skips: 1" "$OUT"
if python3 -c "import json; s=json.load(open('.gos/lessons.json')); assert any(r['what']=='skip' and r['why']=='t15 skip reason canary' for r in s['audit'])" 2>/dev/null; then
  echo "  ✓ skip audit row in json chain"; PASS=$((PASS+1))
else
  echo "  ✗ skip audit row missing"; FAIL=$((FAIL+1))
fi

# --- .16: legacy spelling rebase-anchor rejected with pointer
OUT=$(t15_g lessons rebase-anchor --type project 2>&1); RC=$?
assert_exit "rebase-anchor rejected" "1" "$RC"
assert_contains "pointer to anchor-rebuild" "anchor-rebuild" "$OUT"

# --- .17: json missing + generated md view present → header guard fails closed
# (genesis degradation: this sandbox never committed the json, so the git-log
# genesis guard has no ancestor to catch — the generated-md header guard owns it)
rm -f .gos/lessons.json
OUT=$(t15_g lessons list 2>&1); RC=$?
assert_exit "json missing with generated md view fails closed" "1" "$RC"
assert_contains "recovery points at git restore/backup" "restore" "$OUT"

# --- T15.18: symlinked global truth file → write refused [B-18] ---
rm -rf "$T15_HOME/.config/gos2"; mkdir -p "$T15_HOME/.config/gos2"
mv "$T15_HOME/.config/gos/lessons.json" "$T15_HOME/.config/gos2/real.json" 2>/dev/null
ln -s /etc/passwd "$T15_HOME/.config/gos/lessons.json"
OUT=$(t15_g lessons add --type model --lesson "symlink attack" 2>&1); RC=$?
assert_exit "symlinked global lessons.json write rejected" "1" "$RC"
rm -f "$T15_HOME/.config/gos/lessons.json"
mv "$T15_HOME/.config/gos2/real.json" "$T15_HOME/.config/gos/lessons.json" 2>/dev/null

# --- .19: fresh-clone semantics — sidecar discardable, anchor-rebuild legal
T15_FC="$TESTBASE/test-$(date +%s)-$RANDOM-t15fc"
mkdir -p "$T15_FC/.gos/cache" && cd "$T15_FC" || exit 1
git init -q . && git commit -q --allow-empty -m root
printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
t15_g init 2 "t15 fresh clone" >/dev/null 2>&1
t15_g lessons add --type project --scene "fc" --lesson "fresh clone entry" >/dev/null 2>&1
rm -f .gos/cache/.lessons-anchors.json
OUT=$(t15_g lessons list 2>&1); RC=$?
assert_exit "missing sidecar does not brick reads (fresh-clone semantics)" "0" "$RC"
OUT=$(t15_g lessons anchor-rebuild 2>&1); RC=$?
assert_exit "anchor-rebuild re-derives sidecar (legal any time)" "0" "$RC"
if python3 -c "import json; s=json.load(open('.gos/cache/.lessons-anchors.json')); assert s.get('live_ids'); a=json.load(open('.gos/lessons.json')); assert any(r['what']=='rebuild' for r in a['audit'])" 2>/dev/null; then
  echo "  ✓ rebuild audit row + sidecar restored"; PASS=$((PASS+1))
else
  echo "  ✗ rebuild artifacts missing"; FAIL=$((FAIL+1))
fi
cd "$T15_DIR" || exit 1
rm -rf "$T15_FC"

# --- .20: dispatch registered — no 'Unknown command'
OUT=$(t15_g lessons list 2>&1)
if echo "$OUT" | grep -q "Unknown command"; then
  echo "  ✗ lessons still unknown in dispatch"; FAIL=$((FAIL+1))
else
  echo "  ✓ lessons dispatch registered"; PASS=$((PASS+1))
fi

t15_teardown
