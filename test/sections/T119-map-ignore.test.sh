#!/usr/bin/env bash
# gos-map:cmd map,gate
# gos-map:fn bin/lib/map/engine.cjs#fn:scanSources
# gos-map:file skills/gos-ship/scripts/cleanup-scan.sh
# gos-map:file skills/gos-ship/scripts/security.sh
# map-ignore E2E — vendored repo goes green, exclusion-list lifecycle, ship-script parity
# Env: GOS (CLI path), GOS_ROOT (repo root), TESTBASE (sandbox base), assert helpers sourced by runner
T119_DIR=""

t119_setup() {
  T119_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t119"
  mkdir -p "$T119_DIR" && cd "$T119_DIR" || exit 1
}

t119_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T119_DIR"; }

# Vendored repo: two vendored files redefine the same top-level fn (duplicate
# name across files); one carries a debug console.log, the other a string eval
# — both ship blockers while unfiltered. src/app.js imports the vendored file
# plus one local module so the import graph has both shapes to filter.
mk_vendored_repo() { # $1 = target dir (created, git init, one fixture commit)
  mkdir -p "$1/src" "$1/vendor/mxgraph"
  printf '// vendored mxgraph-style source (third-party, not ours to edit)\nfunction mxActor() { console.log(\x27debug\x27); }\nfunction mxShape() {}\n' > "$1/vendor/mxgraph/actor.js"
  printf '// vendored file redefining the same class-name fn\nfunction mxActor() { return eval(\x27x\x27); }\n' > "$1/vendor/mxgraph/shape.js"
  printf 'function utilWork() { return 1; }\nmodule.exports = { utilWork };\n' > "$1/src/util.js"
  printf "const actor = require('../vendor/mxgraph/actor.js');\nconst util = require('./util.js');\nfunction appMain() { return actor || util.utilWork(); }\n" > "$1/src/app.js"
  ( cd "$1" && git init -q . && git add -A && git commit -qm t119-vendored-fixture )
}

# Control repo: comments-only rule file from the very first scan (zero exclusions).
mk_control_repo() { # $1 = target dir (created, git init, one fixture commit)
  mkdir -p "$1/src" "$1/.gos"
  printf 'function ctrlMain() { return 1; }\n' > "$1/src/app.js"
  printf '# no active rules — every path scannable\n' > "$1/.gos/map-ignore"
  ( cd "$1" && git init -q . && git add -A && git commit -qm t119-control-fixture )
}

# Unborn variant of the vendored fixture: git init only, no first commit —
# the scan/gate contracts must hold on a HEAD-less repo.
mk_vendored_unborn() { # $1 = target dir (created, git init, fixtures left staged-nowhere)
  mkdir -p "$1/src" "$1/vendor/mxgraph"
  printf '// vendored mxgraph-style source (third-party, not ours to edit)\nfunction mxActor() { console.log(\x27debug\x27); }\nfunction mxShape() {}\n' > "$1/vendor/mxgraph/actor.js"
  printf '// vendored file redefining the same class-name fn\nfunction mxActor() { return eval(\x27x\x27); }\n' > "$1/vendor/mxgraph/shape.js"
  printf 'function utilWork() { return 1; }\nmodule.exports = { utilWork };\n' > "$1/src/util.js"
  printf "const actor = require('../vendor/mxgraph/actor.js');\nconst util = require('./util.js');\nfunction appMain() { return actor || util.utilWork(); }\n" > "$1/src/app.js"
  ( cd "$1" && git init -q . )
}

t119_setup
echo "--- T119: map-ignore E2E (vendored green + list lifecycle + script parity + polluted peak) ---"

# ===== act 1: vendored repo goes green + exclusion-list lifecycle + ship-script parity =====

# --- .1 unfiltered baseline: no rule file yet — duplicate fn keeps gate red, planted blockers visible to ship scripts
mk_vendored_repo "$T119_DIR/vendored"
cd "$T119_DIR/vendored" || exit 1
set +e; SOUT=$(node "$GOS" map scan 2>&1); SRC=$?; set -e
assert_exit "T119.1a scan without rule file exits 0" 0 "$SRC"
set +e; GOUT=$(node "$GOS" gate codemap 2>&1); GRC=$?; set -e
assert_exit "T119.1b gate codemap red on vendored duplicate fn" 1 "$GRC"
assert_contains "T119.1c red verdict names codemap-dup-fn-name" "codemap-dup-fn-name" "$GOUT"
set +e; COUT=$(bash "$GOS_ROOT/skills/gos-ship/scripts/cleanup-scan.sh" 2>&1); CRC=$?; set -e
assert_exit "T119.1d cleanup-scan reports findings while unfiltered" 1 "$CRC"
assert_contains "T119.1e findings name the vendored console.log file" "vendor/mxgraph/actor.js" "$COUT"
assert_contains "T119.1f findings verdict line" "RESULT: FINDINGS" "$COUT"

# --- .2 vendor/* rule: scan reports exclusions, gate goes green, list + deps reflect the filter
mkdir -p .gos && printf 'vendor/*\n' > .gos/map-ignore
git add .gos/map-ignore && git commit -qm t119-vendor-rule
set +e; SOUT=$(node "$GOS" map scan 2>&1); SRC=$?; set -e
assert_exit "T119.2a scan with vendor/* rule exits 0" 0 "$SRC"
assert_contains "T119.2b scan prints the excluded-count line" "excluded 2 file(s) via .gos/map-ignore — list: .gos/codebase/map-ignored.txt" "$SOUT"
set +e; GOUT=$(node "$GOS" gate codemap 2>&1); GRC=$?; set -e
assert_exit "T119.2c gate codemap green with vendored excluded" 0 "$GRC"
assert_contains "T119.2d repo-wide unique-name assertion green" "unique-name assertion green" "$GOUT"
assert_file "T119.2e exclusion list file written" ".gos/codebase/map-ignored.txt"
if head -1 .gos/codebase/map-ignored.txt | grep -Eq '^generated-at: .+ @ ([0-9a-f]{8}|unborn)$'; then
  echo "  ✓ T119.2f list provenance first line (generated-at + HEAD8|unborn)"; PASS=$((PASS+1))
else
  echo "  ✗ T119.2f list provenance first line (generated-at + HEAD8|unborn)"; FAIL=$((FAIL+1))
fi
LIST_BODY=$(tail -n +2 .gos/codebase/map-ignored.txt)
assert_eq "T119.2g list body is exactly the vendored files, sorted" $'vendor/mxgraph/actor.js\nvendor/mxgraph/shape.js' "$LIST_BODY"
if printf '%s\n' "$LIST_BODY" | grep -q '^src/'; then
  echo "  ✗ T119.2h no src/ file in the exclusion list"; FAIL=$((FAIL+1))
else
  echo "  ✓ T119.2h no src/ file in the exclusion list"; PASS=$((PASS+1))
fi
set +e
python3 - <<'PYEOF'
import json, sys
d = json.load(open('.gos/cache/deps.json'))
bad = []
def leaks(nodes):
    out = []
    for e in nodes:
        if isinstance(e, dict):
            out += [e[k] for k in ('from', 'to', 'file') if isinstance(e.get(k), str) and e[k].startswith('vendor/')]
    return out
if [f for f in d.get('files', []) if f.startswith('vendor/')]: bad.append('vendored path in files')
if leaks(d.get('edges', [])): bad.append('vendored path in edges')
if leaks(d.get('externals', [])): bad.append('vendored path in externals')
for fam, rows in d.get('semantic', {}).items():
    if isinstance(rows, list) and leaks(rows): bad.append(f'vendored path in semantic.{fam}')
if 'mxActor' in d.get('semantic', {}).get('fn_universe', []): bad.append('vendored duplicate fn entered fn_universe')
if d.get('ignored') != ['vendor/mxgraph/actor.js', 'vendor/mxgraph/shape.js']:
    bad.append(f"ignored != sorted vendored relpaths (got {d.get('ignored')})")
if not any(e.get('from') == 'src/app.js' and 'vendor/mxgraph/actor.js' in e.get('spec', '') for e in d.get('externals', [])):
    bad.append('src->vendored import did not degrade to an externals entry')
print('  ✓ T119.2i deps.json: vendored absent from files/edges/externals/semantic + ignored key + externals degradation' if not bad else '  ✗ T119.2i ' + '; '.join(bad))
sys.exit(1 if bad else 0)
PYEOF
PYRC=$?
set -e
assert_exit "T119.2i deps.json reflects the scan-layer filter" 0 "$PYRC"

# --- .3 ship-script parity: list present → clean; list deleted or unreadable → unfiltered fallback
SHIP="$GOS_ROOT/skills/gos-ship/scripts"
set +e; COUT=$(bash "$SHIP/cleanup-scan.sh" 2>&1); CRC=$?; set -e
assert_exit "T119.3a cleanup-scan clean with the list present" 0 "$CRC"
assert_contains "T119.3b clean verdict line" "RESULT: CLEAN" "$COUT"
set +e; SECOUT=$(bash "$SHIP/security.sh" 2>&1); SECRC=$?; set -e
assert_exit "T119.3c security.sh standalone clean with the list" 0 "$SECRC"
rm .gos/codebase/map-ignored.txt
set +e; COUT=$(bash "$SHIP/cleanup-scan.sh" 2>&1); CRC=$?; set -e
assert_exit "T119.3d list deleted → cleanup-scan falls back to full scan (findings)" 1 "$CRC"
assert_contains "T119.3e fallback findings name vendored code" "vendor/mxgraph" "$COUT"
set +e; SECOUT=$(bash "$SHIP/security.sh" 2>&1); SECRC=$?; set -e
assert_exit "T119.3f security.sh flags the string eval without the list (exit 2)" 2 "$SECRC"
set +e; node "$GOS" map scan >/dev/null 2>&1; RESCAN_RC=$?; set -e
assert_exit "T119.3g rescan rematerializes the list" 0 "$RESCAN_RC"
chmod 000 .gos/codebase/map-ignored.txt
set +e; COUT=$(bash "$SHIP/cleanup-scan.sh" 2>&1); CRC=$?; set -e
assert_exit "T119.3h unreadable list restores unfiltered files (grep rc>=2 contract)" 1 "$CRC"
assert_contains "T119.3i unreadable-list findings still name vendored code" "vendor/mxgraph" "$COUT"
chmod 644 .gos/codebase/map-ignored.txt

# --- .4 dead rule: a rule matching nothing is reported; live exclusion is unaffected
printf 'vendor/*\ntypo/*.js\n' > .gos/map-ignore
git add .gos/map-ignore && git commit -qm t119-dead-rule
set +e; SOUT=$(node "$GOS" map scan 2>&1); SRC=$?; set -e
assert_exit "T119.4a scan with a dead rule still exits 0" 0 "$SRC"
assert_contains "T119.4b scan prints the dead-rule advisory" "map-ignore rule(s) matched nothing (typo or stale path" "$SOUT"
assert_contains "T119.4c advisory names the dead rule" "typo/" "$SOUT"
assert_file "T119.4d list still written while live rules match" ".gos/codebase/map-ignored.txt"

# --- .5 rule removal: rescan deletes the stale list, ship scripts scan unfiltered again
printf '# no active rules — every path scannable\n' > .gos/map-ignore
git add .gos/map-ignore && git commit -qm t119-rule-removed
set +e; SOUT=$(node "$GOS" map scan 2>&1); SRC=$?; set -e
assert_exit "T119.5a rescan after rule removal exits 0" 0 "$SRC"
if [ ! -e .gos/codebase/map-ignored.txt ]; then
  echo "  ✓ T119.5b stale list deleted at zero exclusions (rematerialize semantics)"; PASS=$((PASS+1))
else
  echo "  ✗ T119.5b stale list deleted at zero exclusions (rematerialize semantics)"; FAIL=$((FAIL+1))
fi
set +e
python3 - <<'PYEOF'
import json, sys
d = json.load(open('.gos/cache/deps.json'))
bad = []
if 'ignored' in d: bad.append('ignored key present at zero exclusions')
if 'ignore_dead' in d: bad.append('ignore_dead key present at zero exclusions')
print('  ✓ T119.5c deps.json carries no exclusion keys at zero exclusions' if not bad else '  ✗ T119.5c ' + '; '.join(bad))
sys.exit(1 if bad else 0)
PYEOF
PYRC=$?
set -e
assert_exit "T119.5c deps.json carries no exclusion keys at zero exclusions" 0 "$PYRC"
set +e; COUT=$(bash "$SHIP/cleanup-scan.sh" 2>&1); CRC=$?; set -e
assert_exit "T119.5d ship scripts scan unfiltered again after rule removal" 1 "$CRC"

# --- .6 control sandbox: comments-only rule file from the first scan — no excluded line, no list, no keys
mk_control_repo "$T119_DIR/control"
cd "$T119_DIR/control" || exit 1
set +e; SOUT=$(node "$GOS" map scan 2>&1); SRC=$?; set -e
assert_exit "T119.6a scan with comments-only rule file exits 0" 0 "$SRC"
if printf '%s' "$SOUT" | grep -q 'via .gos/map-ignore'; then
  echo "  ✗ T119.6b no excluded-count line at zero exclusions"; FAIL=$((FAIL+1))
else
  echo "  ✓ T119.6b no excluded-count line at zero exclusions"; PASS=$((PASS+1))
fi
if [ ! -e .gos/codebase/map-ignored.txt ]; then
  echo "  ✓ T119.6c no list file at zero exclusions"; PASS=$((PASS+1))
else
  echo "  ✗ T119.6c no list file at zero exclusions"; FAIL=$((FAIL+1))
fi
set +e
python3 - <<'PYEOF'
import json, sys
d = json.load(open('.gos/cache/deps.json'))
bad = []
if 'ignored' in d: bad.append('ignored key present')
if 'ignore_dead' in d: bad.append('ignore_dead key present')
print('  ✓ T119.6d deps.json carries no exclusion keys' if not bad else '  ✗ T119.6d ' + '; '.join(bad))
sys.exit(1 if bad else 0)
PYEOF
PYRC=$?
set -e
assert_exit "T119.6d deps.json carries no exclusion keys" 0 "$PYRC"

# ===== act 2: polluted peak guided reset =====
# A scan that runs BEFORE any ignore rule absorbs the vendored fn universe
# into the baseline peak; adding vendor/* afterwards shrinks current while the
# peak stays monotonic, so gate codemap attributes every missing fn to
# map-ignored paths and prints the approve-gated rotation guidance.

# --- .7 guided advisory + hard gate: pollute the peak first, then exclude
mk_vendored_repo "$T119_DIR/peakpoll"
cd "$T119_DIR/peakpoll" || exit 1
set +e; SOUT=$(node "$GOS" map scan 2>&1); SRC=$?; set -e
assert_exit "T119.7a pre-rule scan (peak absorbs vendored fns) exits 0" 0 "$SRC"
set +e
python3 - <<'PYEOF'
import json, sys
d = json.load(open('.gos/codebase/edge-baseline.json'))
bad = []
if 'mxActor' not in d['peak'].get('fns', []): bad.append('mxActor not in peak.fns')
if 'mxShape' not in d['peak'].get('fns', []): bad.append('mxShape not in peak.fns')
print('  ✓ T119.7b peak absorbed the vendored fn universe' if not bad else '  ✗ T119.7b ' + '; '.join(bad))
sys.exit(1 if bad else 0)
PYEOF
PYRC=$?
set -e
assert_exit "T119.7b peak absorbed the vendored fn universe" 0 "$PYRC"
printf 'vendor/*\n' > .gos/map-ignore
git add .gos/map-ignore && git commit -qm t119-peakpoll-rule
set +e; SOUT=$(node "$GOS" map scan 2>&1); SRC=$?; set -e
assert_exit "T119.7c rescan with the vendor rule exits 0" 0 "$SRC"
set +e; GOUT=$(node "$GOS" gate codemap 2>&1); GRC=$?; set -e
assert_exit "T119.7d gate codemap green with a polluted peak (advisory only)" 0 "$GRC"
assert_contains "T119.7e missing-vs-peak advisory lists the vendored fns" "fn missing vs peak (2)" "$GOUT"
assert_contains "T119.7f guided advisory names full map-ignore coverage" "fully covered by map-ignore" "$GOUT"
assert_contains "T119.7g guided advisory names the approve step" "baseline-reset" "$GOUT"
assert_contains "T119.7h guided advisory names the reset step" "map baseline reset" "$GOUT"
set +e; ROUT=$(node "$GOS" map baseline reset --reason test 2>&1); RRC=$?; set -e
assert_exit "T119.7i baseline reset without the approve record dies" 1 "$RRC"
assert_contains "T119.7j refusal names the approve hard gate" "approve hard gate" "$ROUT"

# --- .8 stateless-safe approve: record the sign-off, rotate the peak, advisory gone
mk_vendored_repo "$T119_DIR/peakreset"
cd "$T119_DIR/peakreset" || exit 1
set +e; node "$GOS" map scan >/dev/null 2>&1; SRC=$?; set -e
assert_exit "T119.8a pre-rule scan exits 0" 0 "$SRC"
printf 'vendor/*\n' > .gos/map-ignore
git add .gos/map-ignore && git commit -qm t119-peakreset-rule
set +e; node "$GOS" map scan >/dev/null 2>&1; SRC=$?; set -e
assert_exit "T119.8b rescan with the vendor rule exits 0" 0 "$SRC"
set +e; GOUT=$(node "$GOS" gate codemap 2>&1); GRC=$?; set -e
assert_contains "T119.8c guided advisory present before the reset" "fully covered by map-ignore" "$GOUT"
printf '{\n  "schema_version": 6,\n  "task_id": "t119-fixture",\n  "current_stage": "INTENT",\n  "decisions": [],\n  "requirements": [],\n  "approvals": {}\n}\n' > .gos/state.json
set +e; AOUT=$(env -u GOS_AUTO_SPAWNED node "$GOS" approve baseline-reset --reason test 2>&1); ARC=$?; set -e
assert_exit "T119.8d approve records the sign-off (stateless-safe, marker-pinned)" 0 "$ARC"
assert_contains "T119.8e approve output confirms the approval" "BASELINE_RESET approved" "$AOUT"
set +e; ROUT=$(node "$GOS" map baseline reset --reason test 2>&1); RRC=$?; set -e
assert_exit "T119.8f baseline reset consumes the approval" 0 "$RRC"
assert_contains "T119.8g reset output confirms the re-anchor" "re-anchored to current" "$ROUT"
assert_file "T119.8h old peak archived to edge-history.ndjson" ".gos/codebase/edge-history.ndjson"
set +e
python3 - <<'PYEOF'
import json, sys
bad = []
st = json.load(open('.gos/state.json'))
if st.get('approvals') != {}: bad.append('approvals not consumed')
bl = json.load(open('.gos/codebase/edge-baseline.json'))
if sorted(bl['peak'].get('fns', [])) != sorted(bl['current'].get('fns', [])): bad.append('peak != current after rotation')
if 'mxActor' in bl['peak'].get('fns', []): bad.append('polluted fn still in peak')
print('  ✓ T119.8i approval consumed once + peak rotated to current' if not bad else '  ✗ T119.8i ' + '; '.join(bad))
sys.exit(1 if bad else 0)
PYEOF
PYRC=$?
set -e
assert_exit "T119.8i approval consumed once + peak rotated to current" 0 "$PYRC"
set +e; GOUT=$(node "$GOS" gate codemap 2>&1); GRC=$?; set -e
assert_exit "T119.8j gate codemap green after the rotation" 0 "$GRC"
if printf '%s\n' "$GOUT" | grep -q 'fn missing vs peak'; then
  echo "  ✗ T119.8k no missing-vs-peak advisory after the rotation"; FAIL=$((FAIL+1))
else
  echo "  ✓ T119.8k no missing-vs-peak advisory after the rotation"; PASS=$((PASS+1))
fi

# --- .9 stale exclusion list: provenance HEAD mismatch degrades to the plain advisory
mk_vendored_repo "$T119_DIR/peakstale"
cd "$T119_DIR/peakstale" || exit 1
set +e; node "$GOS" map scan >/dev/null 2>&1; SRC=$?; set -e
assert_exit "T119.9a pre-rule scan exits 0" 0 "$SRC"
printf 'vendor/*\n' > .gos/map-ignore
git add .gos/map-ignore && git commit -qm t119-peakstale-rule
set +e; node "$GOS" map scan >/dev/null 2>&1; SRC=$?; set -e
assert_exit "T119.9b rescan with the vendor rule exits 0" 0 "$SRC"
sed -i '1s/.*/generated-at: 2020-01-01T00:00:00Z @ deadbeef/' .gos/codebase/map-ignored.txt
if [ "$(head -1 .gos/codebase/map-ignored.txt)" = "generated-at: 2020-01-01T00:00:00Z @ deadbeef" ]; then
  echo "  ✓ T119.9c list provenance header hand-staled"; PASS=$((PASS+1))
else
  echo "  ✗ T119.9c list provenance header hand-staled"; FAIL=$((FAIL+1))
fi
set +e; GOUT=$(node "$GOS" gate codemap 2>&1); GRC=$?; set -e
assert_exit "T119.9d gate codemap green with a stale list" 0 "$GRC"
assert_contains "T119.9e plain missing-vs-peak advisory still prints" "fn missing vs peak" "$GOUT"
if printf '%s\n' "$GOUT" | grep -q 'baseline-reset'; then
  echo "  ✗ T119.9f stale list suppresses the reset guidance"; FAIL=$((FAIL+1))
else
  echo "  ✓ T119.9f stale list suppresses the reset guidance"; PASS=$((PASS+1))
fi

# --- .10 unborn repo: null-safe head merge, unborn==unborn counts as fresh
mk_vendored_unborn "$T119_DIR/peakunborn"
cd "$T119_DIR/peakunborn" || exit 1
set +e; SOUT=$(node "$GOS" map scan 2>&1); SRC=$?; set -e
assert_exit "T119.10a scan before the first commit exits 0" 0 "$SRC"
assert_contains "T119.10b scan prints the unborn anchor advisory" "no commits" "$SOUT"
printf 'vendor/*\n' > .gos/map-ignore
set +e; SOUT=$(node "$GOS" map scan 2>&1); SRC=$?; set -e
assert_exit "T119.10c rescan with the vendor rule exits 0" 0 "$SRC"
assert_contains "T119.10d rescan still prints the exclusion line" "excluded 2 file(s) via .gos/map-ignore" "$SOUT"
if head -1 .gos/codebase/map-ignored.txt | grep -q '@ unborn$'; then
  echo "  ✓ T119.10e list provenance carries the unborn marker"; PASS=$((PASS+1))
else
  echo "  ✗ T119.10e list provenance carries the unborn marker"; FAIL=$((FAIL+1))
fi
set +e; GOUT=$(node "$GOS" gate codemap 2>&1); GRC=$?; set -e
assert_exit "T119.10f gate codemap on an unborn repo does not throw" 0 "$GRC"
assert_contains "T119.10g unborn==unborn freshness still yields the guided advisory" "fully covered by map-ignore" "$GOUT"

# --- .11 tier-2 by-dir listing: same attribution helper above the 50-fn threshold
mk_vendored_repo "$T119_DIR/peaktier2"
cd "$T119_DIR/peaktier2" || exit 1
mkdir -p vendor/gen
for i in $(seq 1 30); do
  printf '// generated vendored fixture\nfunction g%sa() {}\nfunction g%sb() {}\n' "$i" "$i" > "vendor/gen/g$i.js"
done
git add vendor/gen && git commit -qm "land tier2 fixture"
set +e; node "$GOS" map scan >/dev/null 2>&1; SRC=$?; set -e
assert_exit "T119.11a pre-rule scan with 62 vendored fns exits 0" 0 "$SRC"
set +e
python3 - <<'PYEOF'
import json, sys
d = json.load(open('.gos/codebase/edge-baseline.json'))
n = d['peak'].get('fn_count', 0)
print(f'  ✓ T119.11b peak.fn_count {n} exceeds the tier-2 threshold' if n > 50 else f'  ✗ T119.11b peak.fn_count {n} not above 50')
sys.exit(0 if n > 50 else 1)
PYEOF
PYRC=$?
set -e
assert_exit "T119.11b peak.fn_count exceeds the tier-2 threshold" 0 "$PYRC"
printf 'vendor/*\n' > .gos/map-ignore
git add .gos/map-ignore && git commit -qm "land vendor rule"
set +e; node "$GOS" map scan >/dev/null 2>&1; SRC=$?; set -e
assert_exit "T119.11c rescan with the vendor rule exits 0" 0 "$SRC"
set +e; GOUT=$(node "$GOS" gate codemap 2>&1); GRC=$?; set -e
assert_exit "T119.11d gate codemap green in the by-dir tier" 0 "$GRC"
assert_contains "T119.11e by-dir aggregate names the generated tree" "by dir: vendor/gen: 60" "$GOUT"
assert_contains "T119.11f tier-2 guided advisory names full coverage" "fully covered by map-ignore" "$GOUT"
assert_contains "T119.11g tier-2 guided advisory names the approve step" "baseline-reset" "$GOUT"

# ===== act 3: self-repo regression + docs presence =====
# The GOS repo itself carries no .gos/map-ignore: the scan/gate contract must
# hold exactly as before the feature (no excluded line, no exclusion keys in
# deps.json, no list byproduct), while docs and gate fix hints carry the
# feature text.

# --- .12 self-repo scan: pre-fix structural contract
set +e; SOUT=$(cd "$GOS_ROOT" && node "$GOS" map scan 2>&1); SRC=$?; set -e
assert_exit "T119.12a self-repo scan (no rule file) exits 0" 0 "$SRC"
if printf '%s\n' "$SOUT" | grep -q 'via .gos/map-ignore'; then
  echo "  ✗ T119.12b self-repo scan prints no excluded-count line"; FAIL=$((FAIL+1))
else
  echo "  ✓ T119.12b self-repo scan prints no excluded-count line"; PASS=$((PASS+1))
fi
set +e
python3 - <<'PYEOF'
import json, os, sys
d = json.load(open(os.path.join(os.environ['GOS_ROOT'], '.gos/cache/deps.json')))
bad = []
if d.get('schema_version') != 3: bad.append(f"schema_version {d.get('schema_version')} != 3")
if 'ignored' in d: bad.append('ignored key present')
if 'ignore_dead' in d: bad.append('ignore_dead key present')
print('  ✓ T119.12c self-repo deps.json keeps the pre-fix structure (schema 3, no exclusion keys)' if not bad else '  ✗ T119.12c ' + '; '.join(bad))
sys.exit(1 if bad else 0)
PYEOF
PYRC=$?
set -e
assert_exit "T119.12c self-repo deps.json keeps the pre-fix structure" 0 "$PYRC"
if [ -e "$GOS_ROOT/.gos/codebase/map-ignored.txt" ]; then
  echo "  ✗ T119.12d no map-ignored.txt byproduct on the self repo"; FAIL=$((FAIL+1))
else
  echo "  ✓ T119.12d no map-ignored.txt byproduct on the self repo"; PASS=$((PASS+1))
fi

# --- .13 self-repo gate audit legs: the codemap family must be green; the
# all-leg may carry in-flight task debt (plan covers / changelog obligation /
# ai-trace pin drift) but never a codemap-family failure, and any ai-trace
# red is displaced legacy pins, not new anchor debt
set +e; COUT=$(cd "$GOS_ROOT" && node "$GOS" gate codemap --audit 2>&1); CRC=$?; set -e
assert_exit "T119.13a self-repo gate codemap --audit exits 0" 0 "$CRC"
set +e; AOUT=$(cd "$GOS_ROOT" && node "$GOS" gate all --audit 2>&1); set -e
set +e; AFAILS=$(printf '%s\n' "$AOUT" | grep '✗' || true); set -e
if printf '%s\n' "$AFAILS" | grep -Eq 'codemap|dup-fn|unmapped|parse-failures'; then
  echo "  ✗ T119.13b self-repo gate all --audit carries no codemap-family failure"; FAIL=$((FAIL+1))
else
  echo "  ✓ T119.13b self-repo gate all --audit carries no codemap-family failure"; PASS=$((PASS+1))
fi
set +e
(cd "$GOS_ROOT" && bash test/checks/ai-trace-lint.sh --json) > "$T119_DIR/ai-trace.json" 2>/dev/null
python3 - "$T119_DIR/ai-trace.json" <<'PYEOF'
import json, sys
violations = json.load(open(sys.argv[1]))
allowed = {'pin-mismatch', 'ai-trace-unregistered'}
bad = [e for e in violations if e.get('type') not in allowed]
print(f'  ✓ T119.13c ai-trace red is displaced-pin debt only ({len(violations)} violation(s), no new anchor type)' if not bad else '  ✗ T119.13c unexpected ai-trace violation types: ' + str(sorted({e.get("type") for e in bad})))
sys.exit(1 if bad else 0)
PYEOF
PYRC=$?
set -e
assert_exit "T119.13c ai-trace red is displaced-pin debt only" 0 "$PYRC"

# --- .14 pack-check invariants for the new census entry. Full pack-check
# cannot pass inside an in-flight section sandbox: census source 4 flags
# every untracked file, and this section file plus the runner's sandbox base
# are untracked by construction until the batch lands. The two cheapest
# invariants stand in: the census entry itself and its gitignore coverage.
set +e
python3 - <<'PYEOF'
import json, os, sys
c = json.load(open(os.path.join(os.environ['GOS_ROOT'], 'census.json')))
e = c.get('entries', {}).get('.gos/codebase/map-ignored.txt')
bad = []
if e is None: bad.append('census entry .gos/codebase/map-ignored.txt missing')
else:
    if e.get('git') is not False: bad.append('entry git label is not false')
    if e.get('npm') is not False: bad.append('entry npm label is not false')
print('  ✓ T119.14a census registers map-ignored.txt as git:false npm:false' if not bad else '  ✗ T119.14a ' + '; '.join(bad))
sys.exit(1 if bad else 0)
PYEOF
PYRC=$?
set -e
assert_exit "T119.14a census registers map-ignored.txt as git:false npm:false" 0 "$PYRC"
set +e; git -C "$GOS_ROOT" check-ignore -q .gos/codebase/map-ignored.txt; CIRC=$?; set -e
assert_exit "T119.14b gitignore covers .gos/codebase/map-ignored.txt" 0 "$CIRC"

# --- .15/.16 docs presence: both READMEs carry the map-ignore section, all
# four glob-table rows, and the byproduct note
set +e; EOUT=$(cat "$GOS_ROOT/README.md"); set -e
assert_contains "T119.15a en README has the map-ignore section" "Excluding vendored code" "$EOUT"
assert_contains "T119.15b en row: * crosses /" 'crosses `/`' "$EOUT"
assert_contains "T119.15c en row: bare directory name" "bare directory name has no prefix semantics" "$EOUT"
assert_contains "T119.15d en row: ** same as *" "has no special meaning" "$EOUT"
assert_contains "T119.15e en row: exact relpath" "exactly that relpath" "$EOUT"
assert_contains "T119.15f en byproduct note names the list file" ".gos/codebase/map-ignored.txt" "$EOUT"
set +e; ZSEC=$(awk '/^### .*\.gos\/map-ignore/{p=1; next} /^### /{p=0} p' "$GOS_ROOT/README.zh-CN.md"); set -e
assert_contains "T119.16a zh README has the map-ignore section" ".gos/map-ignore" "$ZSEC"
assert_contains "T119.16b zh row: * crosses /" 'vendor/a/b.js' "$ZSEC"
assert_contains "T119.16c zh row: bare directory name" '`vendor` |' "$ZSEC"
assert_contains "T119.16d zh row: ** same as *" 'vendor/**' "$ZSEC"
assert_contains "T119.16e zh row: exact relpath" 'src/gen/api.ts' "$ZSEC"
assert_contains "T119.16f zh byproduct note names the list file" ".gos/codebase/map-ignored.txt" "$ZSEC"

# --- .17 gate fix hints: both map gate fix strings name map-ignore
set +e; HINTS=$(grep -c "via .gos/map-ignore" "$GOS_ROOT/bin/lib/ops/gate.cjs"); set -e
assert_eq "T119.17a both gate fix hints name map-ignore" "2" "$HINTS"

# --- .18 ship-script parity on the self repo: no list file -> full scan, clean
set +e; COUT=$(cd "$GOS_ROOT" && bash skills/gos-ship/scripts/cleanup-scan.sh 2>&1); CRC=$?; set -e
assert_exit "T119.18a self-repo cleanup-scan exits 0" 0 "$CRC"
assert_contains "T119.18b self-repo cleanup-scan verdict line" "RESULT: CLEAN" "$COUT"

t119_teardown
