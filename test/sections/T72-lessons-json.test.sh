#!/usr/bin/env bash
# gos-map:cmd lessons
# : lessons-json formal suite
# Cases: five invariants / preserved-id mutation / shape injection / promotion
# lineage / salt collision / prefix ambiguity / concurrent mutation lock / regen
# survival / display-load degrade / fresh-clone anchor-rebuild / downgrade
# attack / global recovery rehearsal
# Env: GOS, TESTBASE, assert helpers. Global-path assertions use fake-HOME
T72_DIR=""
T72_HOME=""

t72_setup() {
  T72_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t72"
  mkdir -p "$T72_DIR" && cd "$T72_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
  T72_HOME="$T72_DIR/home"
  mkdir -p "$T72_HOME"
}

t72_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T72_DIR"; }

t72_g() { HOME="$T72_HOME" node "$GOS" "$@"; }

t72_node() { HOME="$T72_HOME" node -e "$1"; }

t72_setup
echo "--- T72: lessons-json truth formal suite ---"

t72_g init 2 "t72 lessons json" >/dev/null 2>&1

# shared fixture: store with a legacy + a v2 entry, saved through the module
t72_node '
const j = require(process.env.GOS_ROOT + "/bin/lib/knowledge/lessons-json.cjs");
const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
const store = j.emptyStore();
const line = "- [2026-08-14] [model] legacy fixture entry (expires 2026-12-31)";
store.entries.push({ id: core.sha16(line), at: "2026-08-14", type: "model", text: "legacy fixture entry", expires: "2026-12-31", origin: "legacy" });
const base = { at: "2026-09-24", type: "project", scene: "t72", lesson: "v2 fixture entry", tags: ["t72"], origin: "v2" };
const { id } = j.mintId(base, () => false);
store.entries.push({ id, ...base });
j.appendAuditRow(store, "migrate", "fixture", { count: 2 });
store.entries.forEach((e) => j.appendAuditRow(store, "add", "fixture add", { new_id: e.id }));
j.saveStore({ truth: ".gos/lessons.json", truthBak: null, anchor: ".gos/cache/.lessons-anchors.json", file: ".gos/lessons.md", global: false }, store);
'

# --- .1: regen survival — md regen cycles never move lessons.json bytes (C8)
J1=$(sha256sum .gos/lessons.json | cut -d' ' -f1)
t72_node '
const j = require(process.env.GOS_ROOT + "/bin/lib/knowledge/lessons-json.cjs");
const fs = require("fs");
const P = { truth: ".gos/lessons.json", anchor: ".gos/cache/.lessons-anchors.json", file: ".gos/lessons.md", global: false };
const store = JSON.parse(fs.readFileSync(P.truth, "utf8"));
fs.appendFileSync(P.file, "\n- hand edit to force regen\n");   // drift the view
j.ensureLessonsMdFresh(P, store, { lockHeld: false });          // regen 1
const md1 = fs.readFileSync(P.file, "utf8");
j.writeLessonsMd(P, store);                                     // regen 2
const md2 = fs.readFileSync(P.file, "utf8");
if (md1 !== md2) process.exit(10);                              // deterministic render
if (!md2.startsWith("<!-- gos:generated lessons-md render-hash:")) process.exit(11);
'
RC=$?
assert_exit "md regen deterministic + header present" "0" "$RC"
J2=$(sha256sum .gos/lessons.json | cut -d' ' -f1)
assert_eq "lessons.json bytes unchanged across md regen cycles" "$J1" "$J2"

# --- .2: preserved-id mutation → fail-closed (F2)
cp .gos/lessons.json /tmp-store.json 2>/dev/null || cp .gos/lessons.json t72-store.bak
python3 - <<'PYEOF'
import json
p = '.gos/lessons.json'
s = json.load(open(p))
for e in s['entries']:
    if e.get('text') is not None:
        e['text'] = e['text'] + ' MUTATED'
json.dump(s, open(p, 'w'), indent=2)
PYEOF
OUT=$(t72_g lessons list 2>&1); RC=$?
assert_exit "legacy content mutation with kept id → fail-closed" "1" "$RC"
assert_contains "mutation names the content-id bind" "content-id bind" "$OUT"
cp t72-store.bak .gos/lessons.json

# --- .3: shape injection — v2 fields onto raw legacy (fifth invariant)
python3 - <<'PYEOF'
import json
p = '.gos/lessons.json'
s = json.load(open(p))
for e in s['entries']:
    if e.get('origin') == 'legacy':
        e['permanent'] = True   # classic rm-guard gaming
json.dump(s, open(p, 'w'), indent=2)
PYEOF
OUT=$(t72_g lessons list 2>&1); RC=$?
assert_exit "injected permanent on raw legacy → fail-closed" "1" "$RC"
assert_contains "shape whitelist named" "non-legacy field" "$OUT"
cp t72-store.bak .gos/lessons.json

# --- .4: downgrade attack — v2 origin rewritten into legacy shape
t72_node '
const j = require(process.env.GOS_ROOT + "/bin/lib/knowledge/lessons-json.cjs");
const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
const fs = require("fs");
const s = JSON.parse(fs.readFileSync(".gos/lessons.json", "utf8"));
const line = "- [2026-09-24] [project] downgraded v2 entry";
for (let i = s.entries.length - 1; i >= 0; i--) if (s.entries[i].origin === "v2") s.entries.splice(i, 1);
s.entries.push({ id: core.sha16(line), at: "2026-09-24", type: "project", text: "downgraded v2 entry", origin: "v2" });
j.saveStore({ truth: ".gos/lessons.json", anchor: ".gos/cache/.lessons-anchors.json", file: ".gos/lessons.md", global: false }, s);
'
OUT=$(t72_g lessons list 2>&1); RC=$?
assert_exit "v2-origin entry in legacy shape → drift fail-closed" "1" "$RC"
assert_contains "origin immutability named" "downgrade attack" "$OUT"

# restore fixture store (module-built, ids valid)
t72_node '
const j = require(process.env.GOS_ROOT + "/bin/lib/knowledge/lessons-json.cjs");
const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
const fs = require("fs");
const s = JSON.parse(fs.readFileSync(".gos/lessons.json", "utf8"));
const line = "- [2026-09-24] [project] downgraded v2 entry";
s.entries = s.entries.filter((e) => !(e.origin === "v2" && e.text === "downgraded v2 entry"));
const base = { at: "2026-09-24", type: "project", scene: "t72", lesson: "v2 fixture entry", tags: ["t72"], origin: "v2" };
const { id } = j.mintId(base, () => false);
s.entries.push({ id, ...base });
j.saveStore({ truth: ".gos/lessons.json", anchor: ".gos/cache/.lessons-anchors.json", file: ".gos/lessons.md", global: false }, s);
'

# --- .5: promotion amend lineage — legacy → structured, origin preserved
LEGPREFIX=$(python3 -c "import json; s=json.load(open('.gos/lessons.json')); print([e['id'] for e in s['entries'] if e.get('origin')=='legacy'][0][:8])")
OUT=$(t72_g lessons amend "$LEGPREFIX" --scene "deploy" --lesson "promoted structured lesson" --tags ops 2>&1); RC=$?
assert_exit "amend promotes legacy entry" "0" "$RC"
if python3 -c "
import json
s = json.load(open('.gos/lessons.json'))
e = [x for x in s['entries'] if x.get('lesson') == 'promoted structured lesson']
assert e and e[0]['origin'] == 'legacy' and not e[0]['id'].startswith('$LEGPREFIX')
r = [x for x in s['audit'] if x['what'] == 'edit'][-1]
assert r['old_id'].startswith('$LEGPREFIX') and r['new_id'] == e[0]['id'] and len(r['prev_sha']) == 16
" 2>/dev/null; then
  echo "  ✓ promotion lineage {old_id,new_id,prev_sha} + origin preserved"; PASS=$((PASS+1))
else
  echo "  ✗ promotion lineage wrong"; FAIL=$((FAIL+1))
fi
OUT=$(t72_g gate lessons 2>&1); RC=$?
assert_exit "gate green after promotion (store verifies)" "0" "$RC"

# --- .6: id salt collision — same content twice mints two ids
t72_g lessons add --type project --scene "dup" --lesson "identical twin entry" >/dev/null 2>&1
t72_g lessons add --type project --scene "dup" --lesson "identical twin entry" >/dev/null 2>&1
if python3 -c "
import json
s = json.load(open('.gos/lessons.json'))
twins = [e for e in s['entries'] if e.get('lesson') == 'identical twin entry']
assert len(twins) == 2 and twins[0]['id'] != twins[1]['id'], 'same-text-different-id expected'
assert any(t.get('salt') for t in twins), 'second twin must carry ordinal salt'
" 2>/dev/null; then
  echo "  ✓ same-text-different-id via ordinal salt (§8 intended semantics)"; PASS=$((PASS+1))
else
  echo "  ✗ salt collision handling wrong"; FAIL=$((FAIL+1))
fi

# --- .7: prefix ambiguity → reject + list (brute-forced shared 4-prefix pair)
AMBP=$(t72_node '
const j = require(process.env.GOS_ROOT + "/bin/lib/knowledge/lessons-json.cjs");
const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
const fs = require("fs");
const s = JSON.parse(fs.readFileSync(".gos/lessons.json", "utf8"));
const mk = (n) => ({ at: "2026-09-24", type: "project", scene: "amb" + n, lesson: "ambiguity probe " + n, tags: [], origin: "v2" });
const a = mk(0);
const ia = core.sha16(j.canonV2(a));
for (let i = 1; i < 500000; i++) {
  const b = mk(i);
  if (core.sha16(j.canonV2(b)).slice(0, 4) === ia.slice(0, 4)) {
    const ib = core.sha16(j.canonV2(b));
    s.entries.push({ id: ia, ...a }, { id: ib, ...b });
    j.saveStore({ truth: ".gos/lessons.json", anchor: ".gos/cache/.lessons-anchors.json", file: ".gos/lessons.md", global: false }, s);
    console.log(ia.slice(0, 4));
    process.exit(0);
  }
}
process.exit(1);
')
if [ -n "$AMBP" ]; then
  OUT=$(t72_g lessons rm "$AMBP" --reason "ambiguous" 2>&1); RC=$?
  assert_exit "ambiguous prefix rejected" "1" "$RC"
  assert_contains "candidates listed with full ids" "candidates" "$OUT"
  if echo "$OUT" | grep -q "$AMBP"; then
    echo "  ✓ ambiguity lists candidate ids"; PASS=$((PASS+1))
  else
    echo "  ✗ candidate ids missing from ambiguity output"; FAIL=$((FAIL+1))
  fi
else
  echo "  ✗ ambiguity pair not fabricated"; FAIL=$((FAIL+1))
fi

# --- .8: concurrent mutation — a live lock holder blocks a second mutation
python3 - <<'PYEOF' &
import json, os, time
lock = '.gos/.lock'
with open(lock, 'w') as f:
    json.dump({'pid': os.getpid(), 'started_at': '2026-09-24T00:00:00'}, f)
time.sleep(6)
PYEOF
LOCKPID=$!
sleep 0.4
OUT=$(t72_g lessons add --type project --scene "race" --lesson "must block" 2>&1); RC=$?
assert_exit "live lock holder blocks concurrent mutation" "1" "$RC"
kill $LOCKPID 2>/dev/null; wait $LOCKPID 2>/dev/null
t72_g lessons add --type project --scene "race" --lesson "after lock release" >/dev/null 2>&1
if python3 -c "import json; s=json.load(open('.gos/lessons.json')); assert any(e.get('scene')=='race' for e in s['entries'])" 2>/dev/null; then
  echo "  ✓ mutation proceeds after lock release"; PASS=$((PASS+1))
else
  echo "  ✗ post-lock mutation failed"; FAIL=$((FAIL+1))
fi

# --- .9: display-load degrade — corrupt json must not brick status (N9)
cp .gos/lessons.json t72-good.json
echo '{corrupt' > .gos/lessons.json
OUT=$(t72_g status 2>&1); RC=$?
assert_exit "corrupt lessons json does NOT brick status" "0" "$RC"
OUT=$(t72_g context build 2>&1); RC=$?
assert_exit "corrupt lessons json does NOT brick context" "0" "$RC"
cp t72-good.json .gos/lessons.json

# --- .10: fresh-clone semantics — committed json, no sidecar, no md
rm -f .gos/cache/.lessons-anchors.json .gos/lessons.md
OUT=$(t72_g lessons list 2>&1); RC=$?
assert_exit "missing sidecar+md do not brick adjudicating read" "0" "$RC"
OUT=$(t72_g lessons anchor-rebuild 2>&1); RC=$?
assert_exit "anchor-rebuild legal on fresh clone" "0" "$RC"
assert_file "sidecar re-derived" .gos/cache/.lessons-anchors.json
assert_file "md regenerated" .gos/lessons.md

# --- .11: global recovery rehearsal — corrupt global json → die
# points at .bak + backup; restore via runbook passes ---
mkdir -p "$T72_HOME/.config/gos"
t72_g lessons add --type model --scene "g" --lesson "global recovery seed" >/dev/null 2>&1
cp "$T72_HOME/.config/gos/lessons.json" t72-global-good.json
echo '{corrupt' > "$T72_HOME/.config/gos/lessons.json"
OUT=$(t72_g lessons add --type model --scene "g2" --lesson "must fail" 2>&1); RC=$?
assert_exit "corrupt global json → mutation fails closed" "1" "$RC"
assert_contains "recovery points at .lessons.json.bak" ".lessons.json.bak" "$OUT"
cp t72-global-good.json "$T72_HOME/.config/gos/lessons.json"
OUT=$(t72_g lessons list 2>&1); RC=$?
assert_exit "global side green after runbook restore" "0" "$RC"
if echo "$OUT" | grep -q "global recovery seed"; then
  echo "  ✓ global entry survived via bak restore"; PASS=$((PASS+1))
else
  echo "  ✗ global entry lost after restore"; FAIL=$((FAIL+1))
fi

# --- .12: gate lessons green end-to-end on the fixture store
OUT=$(t72_g gate lessons 2>&1); RC=$?
assert_exit "gate lessons green" "0" "$RC"
assert_contains "integrity ✓ line" "json truth intact" "$OUT"

# --- .13: batch disposal (prune old_ids) recognized by BOTH channels
# fixture gap this closes: lessons.json is now tracked at git HEAD, so the
# out-of-band git channel (not just the sidecar channel) adjudicates the load
t72_node '
const j = require(process.env.GOS_ROOT + "/bin/lib/knowledge/lessons-json.cjs");
const store = j.loadStore({ truth: ".gos/lessons.json", anchor: ".gos/cache/.lessons-anchors.json", file: ".gos/lessons.md", global: false }).store;
const mk = (scene) => {
  const base = { at: "2026-01-01", type: "project", scene, lesson: "expired " + scene, tags: [], origin: "v2", expires: "2026-01-02" };
  const { id } = j.mintId(base, () => false);
  store.entries.push({ id, ...base });
  j.appendAuditRow(store, "add", "fixture", { new_id: id });
};
mk("px1"); mk("px2");
j.saveStore({ truth: ".gos/lessons.json", anchor: ".gos/cache/.lessons-anchors.json", file: ".gos/lessons.md", global: false }, store);
'
git add .gos/lessons.json && git commit -q -m track-lessons-json
OUT=$(t72_g lessons prune 2>&1); RC=$?
assert_exit "prune of git-tracked expired entries exits 0" "0" "$RC"
OUT=$(t72_g lessons list 2>&1); RC=$?
assert_exit "adjudicating load green after batch prune (git + sidecar channels)" "0" "$RC"
if printf '%s' "$OUT" | grep -qi "deletion audit\|git HEAD has entry"; then
  echo "  ✗ sanctioned batch disposal read as tamper (old_ids not retired)"; FAIL=$((FAIL+1))
else
  echo "  ✓ no false B-8 alarm after batch prune"; PASS=$((PASS+1))
fi
OUT=$(t72_g gate lessons 2>&1); RC=$?
assert_exit "gate lessons still green after prune" "0" "$RC"
git rm -q --cached .gos/lessons.json >/dev/null 2>&1

# --- .14: v2 pipe reserved characters — input reject + load-side shape check
OUT=$(t72_g lessons add --type project --scene 'a|b' --lesson x 2>&1); RC=$?
assert_exit "pipe in --scene rejected at input" "1" "$RC"
assert_contains "reserved-character wording" "reserved character" "$OUT"
OUT=$(t72_node '
const j = require(process.env.GOS_ROOT + "/bin/lib/knowledge/lessons-json.cjs");
const a = { at: "2026-01-01", type: "project", scene: "x", text: "y|z", tags: [], origin: "v2" };
const b = { at: "2026-01-01", type: "project", scene: "x|y", text: "z", tags: [], origin: "v2" };
if (j.canonV2(a) !== j.canonV2(b)) { console.error("pipe-shift premise broken"); process.exit(1); }
const { id } = j.mintId(b, () => false);
const forged = { id, ...a };
const v = j.verifyId(forged);
if (!v.ok) { console.error("verifyId unexpectedly failed"); process.exit(1); }
const errs = j.shapeViolations(forged, v.cls);
if (!errs.some((e) => e.includes("reserved character"))) { console.error("shape check missed: " + JSON.stringify(errs)); process.exit(1); }
console.log("pipe-shift-blocked");
' 2>&1); RC=$?
assert_exit "pipe-shift forge fails v2 shape check" "0" "$RC"
assert_contains "pipe-shift blocked marker" "pipe-shift-blocked" "$OUT"

# --- .15: migration preserves non-matching md (backup on ANY content)
T72B="$TESTBASE/test-$(date +%s)-$RANDOM-t72b"
mkdir -p "$T72B/.gos"
(cd "$T72B" && git init -q . && git commit -q --allow-empty -m root)
printf '# hand notes\nhand-maintained variant content\n' > "$T72B/.gos/lessons.md"
(cd "$T72B" && HOME="$T72_HOME" node "$GOS" init 1 t72b >/dev/null 2>&1)
OUT=$(cd "$T72B" && HOME="$T72_HOME" node "$GOS" lessons migrate 2>&1); RC=$?
assert_exit "migrate with non-matching md exits 0" "0" "$RC"
assert_contains "advisory names the preserved original" "no entries matched the legacy format" "$OUT"
T72B_BK=$(ls "$T72B"/.gos/lessons-migration-backup-*.md 2>/dev/null | head -1)
if [ -n "$T72B_BK" ] && grep -q "hand-maintained variant content" "$T72B_BK"; then
  echo "  ✓ original content preserved in migration backup"; PASS=$((PASS+1))
else
  echo "  ✗ backup missing or original content lost"; FAIL=$((FAIL+1))
fi
rm -rf "$T72B"

rm -f t72-store.bak t72-good.json t72-global-good.json /tmp-store.json
t72_teardown
