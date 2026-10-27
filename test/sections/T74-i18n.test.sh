#!/usr/bin/env bash
# gos-map:cmd setup,status,gate,lessons
# : i18n zh lint + goldens + locale invariants
# Cases: zh command-token lint against CLI registry / goldens per surface family
# (gate FAIL, status Next, setup prompt) run under en + zh-CN / locale-invariant
# fields byte-equal across locales / normalization edges / unknown-locale
# advisory fallback / runner pin GOS_LANG=en
# Env: GOS, TESTBASE, assert helpers. Global paths use fake-HOME
T74_DIR=""
T74_HOME=""

t74_setup() {
  T74_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t74"
  mkdir -p "$T74_DIR" && cd "$T74_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m root
  printf ".gos/state.json\n.gos/cache/\n" > .gitignore && git add .gitignore && git commit -q -m gi
  T74_HOME="$T74_DIR/home"
  mkdir -p "$T74_HOME"
}

t74_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T74_DIR"; }

t74_g() { HOME="$T74_HOME" node "$GOS" "$@"; }

t74_setup
echo "--- T74: i18n zh lint + goldens + locale invariants ---"

# --- .1: zh lint — every command-like token in zh.cjs validates against the CLI registry
OUT=$(node -e '
const zh = require(process.env.GOS_ROOT + "/bin/lib/core/locales/zh.cjs");
const state = require(process.env.GOS_ROOT + "/bin/lib/core/state.cjs");
const cmds = new Set(Object.keys(state.COMMANDS));
const bad = [];
const scan = (v, key) => {
  const s = typeof v === "string" ? v : [v.what, v.why, v.fix].filter(Boolean).join(" ");
  for (const m of s.matchAll(/\bgos ([a-z][a-z0-9_-]*)/g)) {
    if (!cmds.has(m[1])) bad.push(`${key}: "gos ${m[1]}" not in CLI registry`);
  }
  for (const m of s.matchAll(/\{cmd:([a-z0-9_-]+)\}/g)) {
    if (!cmds.has(m[1])) bad.push(`${key}: placeholder {cmd:${m[1]}} not in CLI registry`);
  }
};
for (const [k, v] of Object.entries(zh)) scan(v, k);
if (bad.length) { console.error(bad.join("\n")); process.exit(1); }
console.log("zh-lint-clean");
' 2>&1); RC=$?
assert_exit "zh command-token lint green" "0" "$RC"
assert_contains "lint clean marker" "zh-lint-clean" "$OUT"

OUT=$(node -e '
const core = require(process.env.GOS_ROOT + "/bin/lib/core/index.cjs");
const n = core.normalizeLocale;
const cases = [["zh","zh-CN"],["ZH","zh-CN"],["zh_CN","zh-CN"],["zh_CN.UTF-8","zh-CN"],["zh-TW","zh-CN"],["zh-cn","zh-CN"],["en","en"],["en_US.UTF-8","en"],["",null],["garbage",null],[null,null]];
for (const [raw, want] of cases) {
  const got = n(raw);
  if (got !== want) { console.error(`normalizeLocale(${JSON.stringify(raw)}) = ${got}, want ${want}`); process.exit(1); }
}
console.log("normalization-ok");
' 2>&1); RC=$?
assert_exit "normalization edges (zh/zh_*/zh-*/en/en_* case-insensitive)" "0" "$RC"
assert_contains "normalization marker" "normalization-ok" "$OUT"

# --- .3: unknown locale → advisory + en fallback, exit 0
OUT=$(GOS_LANG=klingon t74_g status 2>&1); RC=$?
assert_exit "unknown GOS_LANG exits 0 with en fallback" "0" "$RC"
assert_contains "unknown locale advisory on stderr" "falling back to English" "$OUT"
assert_contains "en fallback line rendered" "locale: en" "$OUT"

# --- .4: goldens — gate FAIL block under en + zh (3-part, localized verdict, invariant fields)
t74_g init 3 "t74 goldens" >/dev/null 2>&1
python3 - <<'PYEOF'
import json
p='.gos/state.json'
s=json.load(open(p))
s['current_stage']='BUILD'
s['decisions']=[{'id':'D-01','title':'storage','covered':False}]
json.dump(s,open(p,'w'),indent=2)
PYEOF
EN=$(GOS_LANG=en t74_g gate coverage 2>&1)
ZH=$(GOS_LANG=zh-CN t74_g gate coverage 2>&1)
assert_contains "en golden: head code prefix" "✗ coverage-uncovered:" "$EN"
assert_contains "en golden: 3-part evidence" "evidence: D-01" "$EN"
assert_contains "en golden: fix present" "fix:" "$EN"
assert_contains "zh golden: localized verdict" "没有任何任务覆盖" "$ZH"
assert_contains "zh golden: head code prefix (invariant)" "✗ coverage-uncovered:" "$ZH"
if printf '%s' "$ZH" | grep -q "decisions recorded in state"; then
  echo "  ✗ zh render leaked en verdict"; FAIL=$((FAIL+1))
else
  echo "  ✓ zh verdict localized (no en leak)"; PASS=$((PASS+1))
fi
# locale-invariant: evidence + fix lines byte-equal across locales
EN_EV=$(printf '%s\n' "$EN" | grep "evidence:" | head -1)
ZH_EV=$(printf '%s\n' "$ZH" | grep "evidence:" | head -1)
assert_eq "evidence byte-equal across locales" "$EN_EV" "$ZH_EV"

# --- .5: goldens — status guidance under en + zh
EN_S=$(GOS_LANG=en t74_g status 2>&1)
ZH_S=$(GOS_LANG=zh-CN t74_g status 2>&1)
assert_contains "en status locale line" "locale: en (source: env (GOS_LANG))" "$EN_S"
assert_contains "zh status locale line" "语言: zh-CN" "$ZH_S"
# cmd placeholder resolved from registry, both locales
assert_contains "zh placeholder resolves to registry command" "gos setup --lang" "$ZH_S"

# --- .6: setup --lang validation + persistence
OUT=$(t74_g setup --lang xx 2>&1); RC=$?
assert_exit "invalid --lang dies listing valid values" "1" "$RC"
assert_contains "valid values listed" "en | zh-CN" "$OUT"
OUT=$(HOME="$T74_HOME" GOS_LANG= t74_g setup --lang zh-CN --no-onboard 2>&1); RC=$?
assert_exit "valid --lang accepted" "0" "$RC"
if python3 -c "import json; c=json.load(open('.gos/config.json')); assert c.get('locale')=='zh-CN'" 2>/dev/null; then
  echo "  ✓ locale persisted to project config"; PASS=$((PASS+1))
else
  echo "  ✗ locale not persisted"; FAIL=$((FAIL+1))
fi
OUT=$(GOS_LANG= t74_g status 2>&1)
assert_contains "project config locale now effective (zh line)" "zh-CN（来源: project config" "$OUT"
# cleanup: reset locale so later cases stay deterministic
python3 -c "
import json
p='.gos/config.json'
c=json.load(open(p)); c['locale']='en'
json.dump(c,open(p,'w'),indent=2)"

# --- .7: runner pin — the section runner exports GOS_LANG=en
assert_contains "runner pins GOS_LANG=en" "GOS_LANG=en" "$(cat "$GOS_ROOT/test/run-sections.sh")"

# --- .8: en catalog vs CONTRACTS full-set alias check (fail-closed)
# Every contract.* en key must byte-equal its CONTRACTS source (references,
# never copies); no NON-contract key may equal any CONTRACTS string either.
OUT=$(node -e '
const en = require(process.env.GOS_ROOT + "/bin/lib/core/locales/en.cjs");
const { CONTRACTS } = require(process.env.GOS_ROOT + "/bin/lib/core/state.cjs");
const strs = new Set();
const collectInto = (set) => (v) => {
  if (typeof v === "string") set.add(v);
  else if (Array.isArray(v)) v.forEach(collectInto(set));
  else if (v && typeof v === "object") Object.values(v).forEach(collectInto(set));
};
const collect = collectInto(strs);
collect(CONTRACTS);
const errs = [];
let contractN = 0;
for (const [k, v] of Object.entries(en)) {
  const leafs = new Set();
  collectInto(leafs)(v);
  if (k.startsWith("contract.")) {
    contractN++;
    for (const s of leafs) if (!strs.has(s)) errs.push(`contract alias drifted from CONTRACTS source: ${k}`);
  } else {
    for (const s of leafs) if (strs.has(s)) errs.push(`non-contract key copies a CONTRACTS string: ${k}`);
  }}
if (contractN < 5) errs.push(`expected >=5 contract.* aliases, found ${contractN}`);
if (errs.length) { console.error(errs.join("\n")); process.exit(1); }
console.log("aliases-fullset-clean");
' 2>&1); RC=$?
assert_exit "en CONTRACTS aliases full-set check (references only, no copies)" "0" "$RC"
assert_contains "alias full-set marker" "aliases-fullset-clean" "$OUT"

# --- .9: console taxonomy labels localized via t(); md view stays locale-invariant en
GOS_LANG=zh-CN t74_g lessons add --type project --scene t74 --lesson taxonomy-console >/dev/null 2>&1
GOS_LANG=zh-CN t74_g lessons add --type model --scene t74 --lesson taxonomy-global >/dev/null 2>&1
OUT_ZH=$(GOS_LANG=zh-CN t74_g lessons list 2>&1)
OUT_EN=$(GOS_LANG=en t74_g lessons list 2>&1)
assert_contains "zh console: project taxonomy localized" "仓库知识" "$OUT_ZH"
assert_contains "zh console: model taxonomy localized" "跨仓库行为" "$OUT_ZH"
assert_contains "en console: project taxonomy label" "repo knowledge" "$OUT_EN"
assert_contains "en console: model taxonomy label" "cross-repo behavior" "$OUT_EN"
MD_PROJ=$(cat .gos/lessons.md 2>/dev/null)
MD_GLOB=$(cat "$T74_HOME/.config/gos/lessons.md" 2>/dev/null)
assert_contains "project md header stays en" "repo knowledge · never expires" "$MD_PROJ"
assert_contains "global md header stays en" "cross-repo behavior · expires on date" "$MD_GLOB"
if { printf '%s' "$MD_PROJ$MD_GLOB"; } | grep -qE "仓库知识|跨仓库行为"; then
  echo "  ✗ md view localized (must stay locale-invariant en)"; FAIL=$((FAIL+1))
else
  echo "  ✓ md view locale-invariant (no zh leak)"; PASS=$((PASS+1))
fi

# --- .10: key parity — zh⊆en, and en keys missing zh are EXACTLY the known-gap set
# Fail-closed: any gap fails immediately. The pilot batch backfilled the 5
# contract keys, so the gap set is empty — any future en key without a zh
# entry fails here.
cat > "$T74_DIR/parity-check.cjs" <<'PAREOF'
const en = require(process.argv[2]);
const zh = require(process.argv[3]);
const KNOWN_GAPS = new Set([]);
const enKeys = new Set(Object.keys(en));
const zhKeys = new Set(Object.keys(zh));
const errs = [];
for (const k of zhKeys) if (!enKeys.has(k)) errs.push(`zh key missing from en: ${k}`);
const gaps = [...enKeys].filter((k) => !zhKeys.has(k));
for (const g of gaps) if (!KNOWN_GAPS.has(g)) errs.push(`en key missing zh (outside known-gap set): ${g}`);
for (const g of KNOWN_GAPS) if (!gaps.includes(g)) errs.push(`known-gap key unexpectedly backfilled — empty the hardcoded set: ${g}`);
if (errs.length) { console.error(errs.join('\n')); process.exit(1); }
console.log('parity-clean');
PAREOF
OUT=$(node "$T74_DIR/parity-check.cjs" "$GOS_ROOT/bin/lib/core/locales/en.cjs" "$GOS_ROOT/bin/lib/core/locales/zh.cjs" 2>&1); RC=$?
assert_exit "key parity holds for the real catalog" "0" "$RC"
assert_contains "parity clean marker" "parity-clean" "$OUT"
# negative: a scratch zh copy missing a NON-contract key must fail parity
node -e '
const fs = require("fs");
const zh = require(process.env.GOS_ROOT + "/bin/lib/core/locales/zh.cjs");
delete zh["gate.coverage-uncovered"];
fs.writeFileSync(process.argv[1], "module.exports = " + JSON.stringify(zh, null, 2) + ";\n");
' "$T74_DIR/zh-scratch.cjs"
OUT=$(node "$T74_DIR/parity-check.cjs" "$GOS_ROOT/bin/lib/core/locales/en.cjs" "$T74_DIR/zh-scratch.cjs" 2>&1); RC=$?
assert_exit "scratch zh copy with a deleted key fails parity" "1" "$RC"
assert_contains "parity failure names the deleted key" "gate.coverage-uncovered" "$OUT"

t74_teardown
