#!/usr/bin/env bash
# gos-map:cmd help,_contract
# : command registry — COMMANDS ↔ switch ↔ docs three-layer consistency + fail-closed demo
# Env: GOS (CLI path), TESTBASE (mktemp sandbox), assert helpers exported by runner
# Discipline: sandbox base is mktemp-derived (never repo root); runner counts rc≠0 as FAIL.
T29_DIR=""
PKG="$(dirname "$GOS")/../package.json"

t29_setup() {
  T29_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t29"
  mkdir -p "$T29_DIR" && cd "$T29_DIR" || exit 1
}
t29_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T29_DIR"; }

# contract-key value extracted from `gos _contract` (single source of truth — no
# second hardcoding in tests; ). REVIEW-F6: guard — empty key would make every
# grep -q "" anchor pass vacuously.
SELF_CHECK_KEY=$(node "$GOS" _contract 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state_semantics"]["commandRegistrySelfCheck"])')
if [ -z "$SELF_CHECK_KEY" ]; then echo "  ✗ SELF_CHECK_KEY extraction failed — mutation anchors would be vacuous"; exit 1; fi

t29_setup
echo "--- T29: command registry ---"

# REVIEW-F12a: shared python helper (universe expansion was duplicated 3x)
cat > universe.py <<'PYH'
import json
def load_env(path='env.json'):
    return json.load(open(path))
def universe(cmds):
    u = set()
    for name, e in cmds.items():
        u.update(e.get('aliases', []))
        if not e.get('flagOnly') and name != '(no command)':
            u.add(name)
    return u
PYH

# ============ structure layer ============
# -1: help --json is strict JSON from byte 0; gos_version === package.json version
node "$GOS" help --json > env.json 2>err1.txt; RC=$?
assert_exit "help --json exits 0" 0 "$RC"
python3 - "$PKG" <<'PYEOF' && echo "  ✓ envelope strict-JSON + version match" || echo "  ✗ envelope strict-JSON + version match"
import json, sys
env = json.load(open('env.json'))
pkg = json.load(open(sys.argv[1]))
assert env['gos_version'] == pkg['version'], (env['gos_version'], pkg['version'])
assert env['schema_version'] >= 1
assert sorted(env['class_legend'].keys()) == ['exec','global','read','write']
PYEOF
[ ! -s err1.txt ] && echo "  ✓ stderr empty (no banners)" || echo "  ✗ stderr non-empty: $(head -1 err1.txt)"

# -2: source self-parse — case labels inside function main() === registry universe
awk '/^function main\(\) \{/,/^}$/' "$GOS" | grep -o "case '[^']*':" | sed "s/^case '//;s/'.*//" | sort -u > cases.txt
python3 - <<'PYEOF' && echo "  ✓ source self-parse: case labels === switchUniverse" || echo "  ✗ source self-parse mismatch"
import universe
env = universe.load_env()
u = universe.universe(env['commands'])
cases = set(l.rstrip('\n') for l in open('cases.txt'))
# NOTE: '' (empty tag) is a LEGAL switch label (sentinel aliases:['']) — do not discard
if u != cases:
    print('  only-registry:', sorted(u - cases)[:8]); print('  only-source:', sorted(cases - u)[:8])
    raise SystemExit(1)
PYEOF

# -3: usage/next non-empty for normal entries (subs MAY be empty — subcommand-less
# commands like status/resume legitimately have no subs); combo-die, unknown-die, sentinel
python3 - <<'PYEOF' && echo "  ✓ normal entries have usage/next non-empty" || echo "  ✗ empty usage/next"
import json
env = json.load(open('env.json'))
for name, e in env['commands'].items():
    if e.get('flagOnly') or e.get('aliasOf') or name == '(no command)': continue
    assert e.get('usage'), name
    assert e.get('next'), name
PYEOF
node "$GOS" help nosuch >/dev/null 2>&1; assert_exit "unknown command dies" 1 "$?"
node "$GOS" help --json phase >/dev/null 2>&1; assert_exit "--json + <cmd> combo dies" 1 "$?"
node "$GOS" help phase add >/dev/null 2>&1; assert_exit "extra args die (usage)" 1 "$?"
OUT=$(node "$GOS" help '' 2>&1); assert_contains "help '' renders status detail" "full status" "$OUT"
OUT=$(node "$GOS" help '(no command)' 2>&1); assert_contains "sentinel by name renders status detail" "full status" "$OUT"
OUT=$(node "$GOS" help PHASE 2>&1); assert_contains "case-insensitive lookup" "Lv4 phase lifecycle" "$OUT"
# REVIEW-F3: alias routing (spec / ) — alias labels resolve to HOST entries
OUT=$(node "$GOS" help -h 2>&1); assert_contains "alias -h renders help host detail" "rendered from COMMANDS registry" "$OUT"
OUT=$(node "$GOS" help --help 2>&1); assert_contains "alias --help renders help host detail" "rendered from COMMANDS registry" "$OUT"
OUT=$(node "$GOS" help -v 2>&1); assert_contains "alias -v renders flagOnly page" "flag — run" "$OUT"
node "$GOS" help constructor >/dev/null 2>&1; assert_exit "prototype key (constructor) dies as unknown" 1 "$?"
node "$GOS" help __proto__ >/dev/null 2>&1; assert_exit "prototype key (__proto__) dies as unknown" 1 "$?"

# ============ derivation layer ============
# REVIEW-F12a: shared python helper (universe expansion was duplicated 3×)
cat > universe.py <<'PYH'
import json
def load_env(path='env.json'):
    return json.load(open(path))
def universe(cmds):
    u = set()
    for name, e in cmds.items():
        u.update(e.get('aliases', []))
        if not e.get('flagOnly') and name != '(no command)':
            u.add(name)
    return u
PYH
# -4: row grammar — human index rows === normal names ∪ sentinel; group headers
# + tail note present (REVIEW-F14: / delegated assertions live here)
node "$GOS" help > human.txt 2>&1
grep -cE '^  (\(no command\)|[a-z_][a-z0-9_-]*)\s{2,}\S' human.txt > rowcount.txt
assert_contains "index has group header (write)" "— write (" "$(cat human.txt)"
assert_contains "index has group header (read)" "— read (" "$(cat human.txt)"
assert_contains "index has tail Next-hint note" "ends with a" "$(cat human.txt)"
assert_contains "index surfaces destructive flag inline (REVIEW-F2)" "⚠" "$(cat human.txt)"
python3 - <<'PYEOF' && echo "  ✓ row grammar: tokens === registry names" || echo "  ✗ row grammar mismatch"
import re
import universe
env = universe.load_env()
expect = {n for n, e in env['commands'].items() if not e.get('flagOnly')}
rows = [l for l in open('human.txt') if re.match(r'^  (\(no command\)|[a-z_][a-z0-9_-]*)\s{2,}\S', l)]
got = {re.match(r'^  (\(no command\)|[a-z_][a-z0-9_-]*)\s{2,}', l).group(1) for l in rows}
assert got == expect, ('missing', sorted(expect-got)[:6], 'extra', sorted(got-expect)[:6])
assert len(rows) == int(open('rowcount.txt').read().strip())
PYEOF

# -5: detail page literally contains usage + every sub string (pure python — no
# generated bash, avoids quoting traps)
python3 - "$GOS" <<'PYEOF' > detailout.txt 2>&1
import json, subprocess, sys
env = json.load(open('env.json'))
bad = 0
for name, e in env['commands'].items():
    if e.get('flagOnly') or e.get('aliasOf') or name == '(no command)': continue
    out = subprocess.run(['node', sys.argv[1], 'help', name], capture_output=True, text=True).stdout
    if e['usage'] not in out:
        print(f'  ✗ detail {name}: usage not verbatim'); bad += 1
    else:
        print(f'  ✓ detail {name}: usage verbatim')
    for s in e.get('subs', []):
        if s not in out:
            print(f'  ✗ detail {name}: sub [{s}] missing'); bad += 1
        else:
            print(f'  ✓ detail {name}: sub [{s}]')
print(f'  RESULT {"PASS" if bad == 0 else "FAIL:" + str(bad)}')
raise SystemExit(1 if bad else 0)
PYEOF
RC=$?
[ "$RC" = "0" ] && echo "  ✓ T29-5 all details derived (0 mismatches)" || { echo "  ✗ T29-5 detail mismatches (see above)"; FAILROWS=$((FAILROWS+1)); }

# -6: next anti-hallucination — every `gos <word>` in next[] ∈ universe ∪ {--break-lock}
python3 - <<'PYEOF' && echo "  ✓ next[] anti-hallucination (0 ghost commands)" || echo "  ✗ next[] references ghost command"
import universe
import re
env = universe.load_env()
u = universe.universe(env['commands'])
u.add('--break-lock')
ghost = []
for name, e in env['commands'].items():
    for n in e.get('next', []):
        m = re.match(r'gos ([a-z_][a-z0-9_-]*)', n)
        if m and m.group(1) not in u: ghost.append((name, m.group(1)))
assert not ghost, ghost
PYEOF

# ============ contract layer ============
# -7: contract keys bidirectional + python smoke on sentinel key
python3 - "$GOS" <<'PYEOF' && echo "  ✓ contract keys bidirectional (no orphans)" || echo "  ✗ contract key orphan/mismatch"
import json, subprocess, sys
env = json.load(open('env.json'))
contracts = json.loads(subprocess.run(['node', sys.argv[1], '_contract'], capture_output=True, text=True).stdout)
cc = set(contracts['command_contracts'].keys())
referenced = set()
for name, e in env['commands'].items():
    for ck in e.get('contractKeys', []):
        sec, key = ck.split('.', 1)
        assert key in contracts.get(sec, {}), f'{name}: {ck} not in CONTRACTS'
        referenced.add(key)
orphan = cc - referenced
assert not orphan, sorted(orphan)
PYEOF
python3 -c 'import json; e=json.load(open("env.json")); print(e["commands"]["(no command)"]["desc"], "|", e["gos_version"])' >/dev/null && echo "  ✓ python smoke: sentinel key + gos_version fetchable" || echo "  ✗ python smoke failed"

# ============ fail-closed demo (copy isolation; last task to touch bin/gos.cjs) ============
# -9: positive control, three mutations (delete entry / bad class / strip risk),
# syntax-corruption negative control, sha256 teardown. Copy layout preserves ../package.json.
ORIG_SHA=$(sha256sum "$GOS" | cut -d' ' -f1)
D="$T29_DIR/copy-$$"; mkdir -p "$D/bin" && cp "$GOS" "$D/bin/" && cp -r "$GOS_ROOT/bin/lib" "$D/bin/lib" && cp "$PKG" "$D/"
# positive control — pristine copy works
node "$D/bin/gos.cjs" help --json > pc.json 2>&1; RC=$?
assert_exit "positive control: pristine copy help --json" 0 "$RC"
# mutation A: delete the 'gap' entry block
python3 - "$D/bin/lib/core/state.cjs" <<'PYEOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
s2 = re.sub(r"  'gap': \{[\s\S]*?\n  \},\n", "", s, count=1)
open(p, 'w').write(s2)
PYEOF
node "$D/bin/gos.cjs" status >/dev/null 2>mA.txt; RC=$?
assert_exit "mutation A (delete entry) dies" 1 "$RC"
grep -q "$SELF_CHECK_KEY" mA.txt && echo "  ✓ mutation A stderr matches self-check contract key" || echo "  ✗ mutation A stderr lacks contract key"
# mutation B: corrupt class value
cp "$GOS" "$D/bin/gos.cjs" && cp -r "$GOS_ROOT/bin/lib" "$D/bin/lib" && cp "$PKG" "$D/" 2>/dev/null
python3 - "$D/bin/lib/core/state.cjs" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p).read()
s2 = s.replace("'phase': {\n    desc: 'Lv4 phase lifecycle: add | list | claim | unclaim | mark-done', class: 'write'",
               "'phase': {\n    desc: 'Lv4 phase lifecycle: add | list | claim | unclaim | mark-done', class: 'bogus'", 1)
open(p, 'w').write(s2)
PYEOF
node "$D/bin/gos.cjs" status >/dev/null 2>mB.txt; RC=$?
assert_exit "mutation B (bogus class) dies" 1 "$RC"
grep -q "$SELF_CHECK_KEY" mB.txt && echo "  ✓ mutation B stderr matches contract key" || echo "  ✗ mutation B stderr lacks contract key"
# mutation C: strip destructive risk from --force
cp "$GOS" "$D/bin/gos.cjs" && cp -r "$GOS_ROOT/bin/lib" "$D/bin/lib"
python3 - "$D/bin/lib/core/state.cjs" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p).read()
s2 = s.replace("effect: 'bypass DONE/archive preconditions (data-loss risk if task mid-flight)', risk: 'destructive'",
               "effect: 'bypass DONE/archive preconditions (data-loss risk if task mid-flight)', risk: 'safe'", 1)
open(p, 'w').write(s2)
PYEOF
node "$D/bin/gos.cjs" status >/dev/null 2>mC.txt; RC=$?
assert_exit "mutation C (stripped risk) dies" 1 "$RC"
grep -q "$SELF_CHECK_KEY" mC.txt && echo "  ✓ mutation C stderr matches contract key" || echo "  ✗ mutation C stderr lacks contract key"
# syntax-corruption negative control — must NOT match self-check key (distinguishable)
cp "$GOS" "$D/bin/gos.cjs" && cp -r "$GOS_ROOT/bin/lib" "$D/bin/lib"
printf 'const SYNTAX_BREAKER = (((;\n' >> "$D/bin/gos.cjs"
node "$D/bin/gos.cjs" status >/dev/null 2>syn.txt; RC=$?
assert_exit "syntax corruption exits non-zero" 1 "$RC"
grep -q "$SELF_CHECK_KEY" syn.txt && echo "  ✗ syntax error FALSELY matches contract key" || echo "  ✓ syntax error distinguishable from self-check die"
# teardown: original untouched (sha + git status scoped — REVIEW-F7: both elements)
NOW_SHA=$(sha256sum "$GOS" | cut -d' ' -f1)
assert_eq "original bin/gos.cjs sha256 unchanged" "$ORIG_SHA" "$NOW_SHA"
GS=$(cd "$GOSROOT_DIR" 2>/dev/null && git status --porcelain -- bin/gos.cjs | wc -l)
assert_eq "git status clean for bin/gos.cjs" "0" "$GS"

# ============ document layer ============
# -11: glob-wide scan — list/table rows with backticked `gos <word>` ∈ universe ∪ exemptions
GOSROOT_DIR=$(dirname "$(dirname "$GOS")")
python3 - "$GOSROOT_DIR" <<'PYEOF' > docscan.txt 2>&1 && echo "  ✓ doc glob scan: 0 out-of-registry command mentions" || { echo "  ✗ doc scan violations:"; head -8 docscan.txt; }
import re, sys, glob, os
root = sys.argv[1]
patterns = ['AGENTS.md', 'README*', 'skills/*/SKILL.md',
            '.opencode/plugins/*.js', '.opencode/commands/**/*.md', '.claude-plugin/**', '.codex/**']
files = set()
for pat in patterns:
    files.update(glob.glob(os.path.join(root, pat), recursive=True))
import universe as _um
universe = _um.universe(_um.load_env(os.path.join(os.getcwd(), 'env.json'))['commands'])
exempt = {'skills'}  # Appendix D closed list
row_re = re.compile(r'^\s*(?:[-|]|[0-9]+[.)])')
cmd_re = re.compile(r'`gos ([a-z_][a-z0-9_-]*)')
bad = []
for f in sorted(files):
    try: lines = open(f, encoding='utf-8', errors='replace').read().splitlines()
    except OSError: continue
    in_block = False
    for i, l in enumerate(lines, 1):
        if l.strip().startswith('```'): in_block = not in_block; continue
        if in_block: continue  # fenced code blocks are prose-shape, exempt
        if not row_re.match(l): continue
        for m in cmd_re.finditer(l):
            if m.group(1) not in universe and m.group(1) not in exempt:
                bad.append(f'{f}:{i}: gos {m.group(1)}')
for b in bad: print(b)
raise SystemExit(1 if bad else 0)
PYEOF

# -12: five delimited docs — shortlist name-set === core set (bidirectional); pointer sentence
python3 - "$GOSROOT_DIR" <<'PYEOF' && echo "  ✓ five docs: delimited shortlist === core set + pointer" || echo "  ✗ shortlist mismatch (details above)"
import json, re, sys, os
env = json.load(open('env.json'))
core = {n for n, e in env['commands'].items() if e.get('core')}
assert len(core) <= 10, f'core set {len(core)} > 10'
docs = [os.path.join(sys.argv[1], p) for p in ['.opencode/plugins/gos.js', 'README.md', 'README.zh-CN.md', 'skills/gos-router/SKILL.md']]
failed = False
for d in docs:
    s = open(d, encoding='utf-8').read()
    m = re.search(r'gos:core-shortlist begin([\s\S]*?)gos:core-shortlist end', s)
    if not m:
        print(f'  ✗ no delimiters in {os.path.basename(d)}'); failed = True; continue
    zone = m.group(1)
    got = set()
    for mm in re.finditer(r'`gos(?: ([a-z-]+))?`?', zone):
        got.add(mm.group(1) if mm.group(1) else '(no command)')
    if got != core:
        print(f'  ✗ {os.path.basename(d)}: missing {sorted(core-got)} extra {sorted(got-core)}'); failed = True
    if not re.search(r'(?:Full capability|全量能力)[^\n]*gos help \[--json\]', zone):
        print(f'  ✗ {os.path.basename(d)}: pointer sentence missing'); failed = True
raise SystemExit(1 if failed else 0)
PYEOF

# rc discipline lives in the runner (counts ✓/✗ + rc≠0=FAIL). REVIEW-F8: dead scaffolding removed.
t29_teardown
echo "--- T29 done (runner counts this section's ✓/✗ and enforces rc≠0=FAIL) ---"
