#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/brownfield.cjs#fn:cmdBrownfield,bin/lib/ops/brownfield.cjs#fn:bfParseFlags,bin/lib/ops/brownfield.cjs#fn:bfGuardEntry,bin/lib/ops/brownfield.cjs#fn:bfProbeAll,bin/lib/ops/brownfield.cjs#fn:bfValidateOverwrite,bin/lib/ops/brownfield.cjs#fn:bfAdopt,bin/lib/ops/brownfield.cjs#fn:bfRenderHuman
# gos-map:cmd brownfield
# T80: brownfield adopt pipeline (T5, D-89/D-91/D-94/D-96/D-97/D-99).
# Ten case groups driven via $GOS in sandbox repos:
# (1) all-conflict fixture — exit 0; locked rows (user hooks) have NO
#     override anywhere; kept_conflict rows (yaml detection, gates.json,
#     check.sh, .gos/.gitignore) each carry an override with a consequence
#     note in the separate override section; every user file byte-identical;
#     row statuses all inside the frozen contract vocabulary;
# (2) husky fixture — core.hooksPath byte-identical before/after, .husky/
#     byte-identical, rows locked_user_owned + chaining guidance;
# (3) unset fixture — hooks seeded to <top>/hooks/ byte-equal to masters,
#     state_flags ["inactive"], remediation ["gos","setup","--commitlint"],
#     bad-message commit NOT rejected (dormant proof), .git/hooks/ never
#     written, .gos/cache/commitlint-hook.json ABSENT (activation owns it);
# (4) gos_hooks_dir fixture — hooks NOT seeded, report_only row with the
#     activation remediation argv;
# (5) .commitlintrc.json detection — yaml NOT seeded (kept_conflict, reason
#     names the detected file); adopted-clean re-run — zero writes
#     (mtime+hash snapshot), identical report, exit 0, statuses
#     kept_identical/report_only only;
# (6) flag matrix — --overwrite <locked> exit 2 + reason; --overwrite
#     <unknown> exit 3; bare --overwrite adopts exactly the kept_conflict
#     set (.gos-bak backups written, locked hook untouched);
# (7) --json — exactly ONE JSON document on stdout on success AND on the
#     exit-4 path (non-git dir + subdir cwd); remediation fields are argv
#     arrays of strings; corrupt hooks state file dies exit 1 with path;
#     human remediation section has no pipeable command line and
#     "--overwrite" appears only in the override section;
# (8) gates — seeded .gos/gates.json has protect/forbid [] and lint null
#     (_comment retained), check.sh exists, trust store unchanged/absent;
# (9) .gos/.gitignore — .lock line present, root .gitignore byte-identical,
#     git check-ignore .gos/.lock exit 0;
# (10) never-created sweep — no .github/, no CODEOWNERS, no CHANGELOG.md in
#     any fixture; module grep — no ask(/onboarding/stdin in brownfield.cjs;
#     review fixes — (11) symlink directory escape blocked + nothing written
#     outside; (12) drifted GOS-lineage hook = kept_conflict with override,
#     --overwrite adopts with .gos-bak; (13) blocked paths report_only
#     (D-89: kept_conflict <=> override, both ways); (14) hooksPath with a
#     space renders shell-quoted; (15) duplicate named --overwrite dies.
# Env: GOS (CLI path), GOS_ROOT, TESTBASE (sandbox base), assert helpers sourced by runner
T80_DIR=""

t80_setup() {
  T80_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t80"
  mkdir -p "$T80_DIR" || exit 1
  cd "$T80_DIR" || exit 1
}

t80_repo() {  # fresh git repo at $T80_DIR/<name>
  mkdir -p "$T80_DIR/$1"
  git init -q -b main "$T80_DIR/$1" || exit 1
}

t80_run() {  # t80_run <repo> [args...] -> human output in $OUT (stdout+stderr), rc in $RC
  local repo="$1"; shift
  OUT=$( cd "$T80_DIR/$repo" && node "$GOS" brownfield "$@" 2>&1 ); RC=$?
}

t80_json() {  # t80_json <repo> [args...] -> stdout ONLY in $OUT, rc in $RC (stderr captured to file)
  local repo="$1"; shift
  OUT=$( cd "$T80_DIR/$repo" && node "$GOS" brownfield "$@" 2>"$T80_DIR/stderr.txt" ); RC=$?
}

t80_row() {  # t80_row <json> <asset> <field> — print a row field (lists as JSON)
  printf '%s' "$1" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
r=[x for x in d['assets'] if x['asset']=='''$2'''][0]
v=r.get('''$3''')
print(v if not isinstance(v,(list,dict)) else json.dumps(v))"
}

t80_ovr() {  # sorted override-section asset names from a report JSON
  printf '%s' "$1" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
print(' '.join(sorted(e['asset'] for e in d.get('overrides',[]))))"
}

t80_sha() { sha256sum "$1" | cut -d' ' -f1; }

t80_snap() {  # content hashes + mtimes of every file under $1 (excl .git) — zero-write proof
  ( cd "$1" && find . -name .git -prune -o -type f -print0 | sort -z | xargs -r -0 sha256sum
    find . -name .git -prune -o -type f -printf '%p %s %T@\n' | sort )
}

t80_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T80_DIR"; }

t80_setup
echo "--- T80: brownfield adopt pipeline ---"
CM_MASTER="$GOS_ROOT/hooks/commit-msg.sh"
PP_MASTER="$GOS_ROOT/hooks/pre-push.sh"
YAML_MASTER="$GOS_ROOT/templates/git/commitlint.config.yaml"

# fixture factory: the all-conflict repo (every adoptable asset conflicts)
t80_conflict_fixture() {
  t80_repo "$1"
  mkdir -p "$T80_DIR/$1/hooks" "$T80_DIR/$1/.gos/gates" "$T80_DIR/$1/.husky"
  printf '#!/bin/sh\necho user commit-msg guard\n' > "$T80_DIR/$1/hooks/commit-msg"
  printf '#!/bin/sh\necho user pre-push guard\n' > "$T80_DIR/$1/hooks/pre-push"
  printf '{ "rules": {} }\n' > "$T80_DIR/$1/.commitlintrc.json"
  printf '{ "protect": [".env"], "lint": "npm run lint" }\n' > "$T80_DIR/$1/.gos/gates.json"
  printf '#!/bin/sh\necho my own gate\n' > "$T80_DIR/$1/.gos/gates/check.sh"
  printf 'node_modules/\n' > "$T80_DIR/$1/.gos/.gitignore"
  printf 'root-keep/\n' > "$T80_DIR/$1/.gitignore"
  printf '# agents\n' > "$T80_DIR/$1/AGENTS.md"
  printf '# claude\n' > "$T80_DIR/$1/CLAUDE.md"
  printf '# gemini\n' > "$T80_DIR/$1/GEMINI.md"
}

# --- G1: all-conflict fixture — safe-skip taxonomy + override/locked partition ---
t80_conflict_fixture ac
AC_HOOK_CM=$(t80_sha "$T80_DIR/ac/hooks/commit-msg")
AC_HOOK_PP=$(t80_sha "$T80_DIR/ac/hooks/pre-push")
AC_RC=$(t80_sha "$T80_DIR/ac/.commitlintrc.json")
AC_GJ=$(t80_sha "$T80_DIR/ac/.gos/gates.json")
AC_CS=$(t80_sha "$T80_DIR/ac/.gos/gates/check.sh")
AC_GI=$(t80_sha "$T80_DIR/ac/.gos/.gitignore")
AC_RT=$(t80_sha "$T80_DIR/ac/.gitignore")
AC_AG=$(t80_sha "$T80_DIR/ac/AGENTS.md")
t80_run ac; OUT_HUMAN="$OUT"
assert_exit "G1a all-conflict run exits 0" 0 "$RC"
assert_eq "G1b user hook byte-identical (locked)" "$AC_HOOK_CM" "$(t80_sha "$T80_DIR/ac/hooks/commit-msg")"
assert_eq "G1c user pre-push byte-identical (locked)" "$AC_HOOK_PP" "$(t80_sha "$T80_DIR/ac/hooks/pre-push")"
assert_eq "G1d external commitlint config byte-identical" "$AC_RC" "$(t80_sha "$T80_DIR/ac/.commitlintrc.json")"
assert_eq "G1e user gates.json byte-identical" "$AC_GJ" "$(t80_sha "$T80_DIR/ac/.gos/gates.json")"
assert_eq "G1f user check.sh byte-identical" "$AC_CS" "$(t80_sha "$T80_DIR/ac/.gos/gates/check.sh")"
assert_eq "G1g user .gos/.gitignore byte-identical" "$AC_GI" "$(t80_sha "$T80_DIR/ac/.gos/.gitignore")"
assert_eq "G1h root .gitignore byte-identical" "$AC_RT" "$(t80_sha "$T80_DIR/ac/.gitignore")"
assert_eq "G1i AGENTS.md byte-identical" "$AC_AG" "$(t80_sha "$T80_DIR/ac/AGENTS.md")"

t80_conflict_fixture acj
t80_json acj --json
assert_exit "G1j all-conflict --json exits 0" 0 "$RC"
assert_eq "G1k hooks/commit-msg locked_user_owned" "locked_user_owned" "$(t80_row "$OUT" hooks/commit-msg status)"
assert_eq "G1l hooks/pre-push locked_user_owned" "locked_user_owned" "$(t80_row "$OUT" hooks/pre-push status)"
assert_eq "G1m core.hooksPath probe row report_only" "report_only" "$(t80_row "$OUT" core.hooksPath status)"
assert_eq "G1n yaml kept_conflict (detection)" "kept_conflict" "$(t80_row "$OUT" commitlint.config.yaml status)"
assert_contains "G1o yaml reason names the detected config" ".commitlintrc.json" "$(t80_row "$OUT" commitlint.config.yaml reason)"
assert_eq "G1p gates.json kept_conflict" "kept_conflict" "$(t80_row "$OUT" .gos/gates.json status)"
assert_eq "G1q check.sh kept_conflict" "kept_conflict" "$(t80_row "$OUT" .gos/gates/check.sh status)"
assert_eq "G1r .gos/.gitignore kept_conflict" "kept_conflict" "$(t80_row "$OUT" .gos/.gitignore status)"
assert_eq "G1s AGENTS.md report_only (present)" "report_only" "$(t80_row "$OUT" AGENTS.md status)"
assert_eq "G1t override section = exactly the kept_conflict set (no locked rows)" \
  ".gos/.gitignore .gos/gates.json .gos/gates/check.sh commitlint.config.yaml" "$(t80_ovr "$OUT")"
printf '%s' "$OUT" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
ovr={e['asset']:e for e in d.get('overrides',[])}
assert all('command' in e and e['command']==['gos','brownfield','--overwrite',e['asset']] for e in ovr.values()), 'override argv shape'
assert all('consequence' in e and e['consequence'] for e in ovr.values()), 'consequence note present'
assert 'hooks/commit-msg' not in ovr and 'hooks/pre-push' not in ovr, 'locked rows never carry overrides'
rows=[r for r in d['assets'] if r['asset'] in ('hooks/commit-msg','hooks/pre-push')]
assert all('override' not in r for r in rows), 'no override field inside locked rows'
print('ok')" ; assert_exit "G1u override entries: argv shape + consequence; locked rows carry none" 0 "$?"
# review M4: D-89 invariant — kept_conflict set == override set, both ways
printf '%s' "$OUT" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
kc={r['asset'] for r in d['assets'] if r['status']=='kept_conflict'}
ovr={e['asset'] for e in d.get('overrides',[])}
assert kc==ovr, ('D-89 kept_conflict <=> override entry', sorted(kc), sorted(ovr))
print('ok')" ; assert_exit "G1u2 D-89: every kept_conflict row carries an override and vice versa" 0 "$?"
# frozen vocabulary: every row status inside the contract set (import, no literals)
T80_STATUS_SET=$(node -e 'console.log(require(process.env.GOS_ROOT+"/bin/lib/core/index.cjs").CONTRACTS.command_contracts.brownfieldStatusSet)')
printf '%s' "$OUT" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
allowed=set('''$T80_STATUS_SET'''.split(' | '))
bad=[r['asset'] for r in d['assets'] if r['status'] not in allowed]
assert not bad, 'out-of-vocabulary statuses: %r' % bad
print('ok')" ; assert_exit "G1v all row statuses inside frozen contract set" 0 "$?"
assert_contains "G1w human report shows escaped-bracket inactive/dormant note" "dormant" "$OUT_HUMAN"

# --- G2: husky fixture — foreign hooksPath is locked, nothing touched ---
t80_repo husky
mkdir -p "$T80_DIR/husky/.husky"
printf '#!/bin/sh\necho husky hook\n' > "$T80_DIR/husky/.husky/pre-commit"
git -C "$T80_DIR/husky" config core.hooksPath .husky
HUSKY_BEFORE=$(git -C "$T80_DIR/husky" config core.hooksPath)
HUSKY_SHA=$(t80_sha "$T80_DIR/husky/.husky/pre-commit")
t80_run husky
assert_exit "G2a husky run exits 0" 0 "$RC"
assert_eq "G2b core.hooksPath byte-identical" "$HUSKY_BEFORE" "$(git -C "$T80_DIR/husky" config core.hooksPath)"
assert_eq "G2c .husky/ file byte-identical" "$HUSKY_SHA" "$(t80_sha "$T80_DIR/husky/.husky/pre-commit")"
t80_json husky --json
assert_eq "G2d hooks row locked_user_owned" "locked_user_owned" "$(t80_row "$OUT" hooks/commit-msg status)"
assert_contains "G2e locked row carries manual-review chaining guidance" "review" "$(t80_row "$OUT" hooks/commit-msg reason)"
assert_eq "G2f no override for the foreign-hooks asset" "" "$(t80_ovr "$OUT" | grep hooks/commit-msg || true)"
if [ ! -e "$T80_DIR/husky/hooks" ]; then echo "  ✓ G2g no hooks/ dir created in the husky repo"; PASS=$((PASS+1));
else echo "  ✗ G2g hooks/ dir must not be created in the husky repo"; FAIL=$((FAIL+1)); fi

# --- G3: unset fixture — dormant hooks seeded, never activated ---
t80_repo clean
printf 'root-keep/\n' > "$T80_DIR/clean/.gitignore"
t80_json clean --json
assert_exit "G3a unset fixture exits 0" 0 "$RC"
assert_file "G3b hooks/commit-msg seeded at <top>/hooks/" "$T80_DIR/clean/hooks/commit-msg"
assert_file "G3c hooks/pre-push seeded at <top>/hooks/" "$T80_DIR/clean/hooks/pre-push"
if cmp -s "$CM_MASTER" "$T80_DIR/clean/hooks/commit-msg"; then echo "  ✓ G3d commit-msg byte-equal to master"; PASS=$((PASS+1));
else echo "  ✗ G3d commit-msg differs from master"; FAIL=$((FAIL+1)); fi
if cmp -s "$PP_MASTER" "$T80_DIR/clean/hooks/pre-push"; then echo "  ✓ G3e pre-push byte-equal to master"; PASS=$((PASS+1));
else echo "  ✗ G3e pre-push differs from master"; FAIL=$((FAIL+1)); fi
assert_eq "G3f hooks row state_flags [inactive]" '["inactive"]' "$(t80_row "$OUT" hooks/commit-msg state_flags)"
assert_eq "G3g hooks row status created" "created" "$(t80_row "$OUT" hooks/commit-msg status)"
assert_eq "G3h hooks remediation = activation argv" '["gos", "setup", "--commitlint"]' "$(t80_row "$OUT" hooks/commit-msg remediation)"
if git -C "$T80_DIR/clean" config --get core.hooksPath >/dev/null 2>&1; then
  echo "  ✗ G3i core.hooksPath must stay unset"; FAIL=$((FAIL+1))
else echo "  ✓ G3i core.hooksPath stays unset (dormant by construction)"; PASS=$((PASS+1)); fi
( cd "$T80_DIR/clean" && git commit -q --allow-empty -m "bad message" ) ; G3C=$?
assert_exit "G3j bad-message commit NOT rejected (dormant proof)" 0 "$G3C"
if [ ! -e "$T80_DIR/clean/.git/hooks/commit-msg" ] && [ ! -e "$T80_DIR/clean/.git/hooks/pre-push" ]; then
  echo "  ✓ G3k .git/hooks/ never written"; PASS=$((PASS+1))
else echo "  ✗ G3k .git/hooks/ was written"; FAIL=$((FAIL+1)); fi
if [ ! -e "$T80_DIR/clean/.gos/cache/commitlint-hook.json" ]; then
  echo "  ✓ G3l hooks state file ABSENT (activation owns creation, R4-F7)"; PASS=$((PASS+1))
else echo "  ✗ G3l hooks state file must not be created"; FAIL=$((FAIL+1)); fi

# --- G4: gos_hooks_dir fixture — live hooks dir is never seeded into ---
t80_repo live
git -C "$T80_DIR/live" config core.hooksPath hooks
t80_json live --json
assert_exit "G4a gos_hooks_dir run exits 0" 0 "$RC"
if [ ! -e "$T80_DIR/live/hooks" ]; then echo "  ✓ G4b hooks NOT seeded (seeding would instantly activate)"; PASS=$((PASS+1));
else echo "  ✗ G4b hooks/ must not be created"; FAIL=$((FAIL+1)); fi
assert_eq "G4c hooks row report_only" "report_only" "$(t80_row "$OUT" hooks/commit-msg status)"
assert_eq "G4d remediation points at the activation path" '["gos", "setup", "--commitlint"]' "$(t80_row "$OUT" hooks/commit-msg remediation)"

# --- G5: commitlint detection + adopted-clean idempotency ---
t80_repo ext
printf '{ "extends": ["@commitlint/config-conventional"] }\n' > "$T80_DIR/ext/.commitlintrc.json"
t80_run ext
assert_exit "G5a external-config run exits 0" 0 "$RC"
if [ ! -e "$T80_DIR/ext/commitlint.config.yaml" ]; then echo "  ✓ G5b yaml NOT seeded beside an external config"; PASS=$((PASS+1));
else echo "  ✗ G5b yaml must not be seeded"; FAIL=$((FAIL+1)); fi
t80_json ext --json
assert_eq "G5c yaml row kept_conflict" "kept_conflict" "$(t80_row "$OUT" commitlint.config.yaml status)"
assert_contains "G5d detection reason text" "existing commitlint config detected" "$(t80_row "$OUT" commitlint.config.yaml reason)"

t80_repo idem
( cd "$T80_DIR/idem" && node "$GOS" brownfield >/dev/null 2>&1 )   # first adopt
S1=$(t80_snap "$T80_DIR/idem")
t80_json idem --json; R1="$OUT"
S2=$(t80_snap "$T80_DIR/idem")
t80_json idem --json; R2="$OUT"
S3=$(t80_snap "$T80_DIR/idem")
assert_exit "G5e re-run exits 0" 0 "$RC"
assert_eq "G5f re-run report identical" "$R1" "$R2"
assert_eq "G5g zero writes (hash+mtime snapshot identical)" "$S1" "$S3"
if [ "$S1" = "$S2" ] && [ "$S2" = "$S3" ]; then echo "  ✓ G5h both re-runs were zero-write"; PASS=$((PASS+1));
else echo "  ✗ G5h a re-run wrote something"; FAIL=$((FAIL+1)); fi
printf '%s' "$R2" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
bad=[r['asset'] for r in d['assets'] if r['status'] not in ('kept_identical','report_only')]
assert not bad, 'non-idempotent rows: %r' % bad
print('ok')" ; assert_exit "G5i adopted-clean re-run: every written asset kept_identical" 0 "$?"
if cmp -s "$YAML_MASTER" "$T80_DIR/idem/commitlint.config.yaml"; then echo "  ✓ G5j seeded yaml byte-equal to master (no self-trigger)"; PASS=$((PASS+1));
else echo "  ✗ G5j seeded yaml differs from master"; FAIL=$((FAIL+1)); fi

# --- G6: flag matrix — exits 2/3, tiered overwrite ---
t80_conflict_fixture ow2
t80_run ow2 --overwrite hooks/commit-msg
assert_exit "G6a --overwrite <locked asset> exits 2" 2 "$RC"
assert_contains "G6b exit-2 reason names the locked asset" "hooks/commit-msg" "$OUT"
assert_contains "G6c exit-2 reason states the locked_user_owned class" "locked_user_owned" "$OUT"
assert_eq "G6d locked hook still byte-identical" "$AC_HOOK_CM" "$(t80_sha "$T80_DIR/ow2/hooks/commit-msg")"
t80_repo ow3
t80_run ow3 --overwrite no-such-asset
assert_exit "G6e --overwrite <unknown name> exits 3" 3 "$RC"
assert_contains "G6f exit-3 reason says unknown asset" "unknown asset" "$OUT"
# kept_conflict-only adoption: divergent gates.json + lock-less .gos/.gitignore + external
# commitlint config; ONE user hook stays locked and must survive every flag
t80_repo ow4
mkdir -p "$T80_DIR/ow4/hooks" "$T80_DIR/ow4/.gos/gates"
printf '#!/bin/sh\necho user commit-msg guard\n' > "$T80_DIR/ow4/hooks/commit-msg"
printf '{ "rules": {} }\n' > "$T80_DIR/ow4/.commitlintrc.json"
printf '{ "protect": [".env"] }\n' > "$T80_DIR/ow4/.gos/gates.json"
printf 'node_modules/\n' > "$T80_DIR/ow4/.gos/.gitignore"
OW4_HOOK=$(t80_sha "$T80_DIR/ow4/hooks/commit-msg")
OW4_GJ=$(t80_sha "$T80_DIR/ow4/.gos/gates.json")
OW4_GI=$(t80_sha "$T80_DIR/ow4/.gos/.gitignore")
t80_run ow4 --overwrite
assert_exit "G6g bare --overwrite exits 0" 0 "$RC"
assert_file "G6h gates.json backup written (.gos-bak)" "$T80_DIR/ow4/.gos/gates.json.gos-bak"
assert_eq "G6i gates.json backup holds the user version" "$OW4_GJ" "$(t80_sha "$T80_DIR/ow4/.gos/gates.json.gos-bak")"
assert_file "G6j .gos/.gitignore backup written (.gos-bak)" "$T80_DIR/ow4/.gos/.gitignore.gos-bak"
assert_eq "G6k gitignore backup holds the user version" "$OW4_GI" "$(t80_sha "$T80_DIR/ow4/.gos/.gitignore.gos-bak")"
printf '%s' "$(cat "$T80_DIR/ow4/.gos/gates.json")" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
assert d['protect']==[] and d['forbid']==[] and d['lint'] is None, d
assert '_comment' in d, 'comment retained'
print('ok')" ; assert_exit "G6l forced gates.json is the EMPTY skeleton (protect/forbid [], lint null)" 0 "$?"
assert_contains "G6m gitignore keeps user lines and gains .lock" ".lock" "$(cat "$T80_DIR/ow4/.gos/.gitignore")"
assert_contains "G6n user line preserved in appended gitignore" "node_modules/" "$(cat "$T80_DIR/ow4/.gos/.gitignore")"
if cmp -s "$YAML_MASTER" "$T80_DIR/ow4/commitlint.config.yaml"; then echo "  ✓ G6o yaml adopted (created despite external config)"; PASS=$((PASS+1));
else echo "  ✗ G6o yaml not created"; FAIL=$((FAIL+1)); fi
assert_eq "G6p locked user hook survives bare --overwrite byte-identical" "$OW4_HOOK" "$(t80_sha "$T80_DIR/ow4/hooks/commit-msg")"
( cd "$T80_DIR/ow4" && git check-ignore -q .gos/.lock ) ; assert_exit "G6q check-ignore .gos/.lock succeeds after adoption" 0 "$?"

# --- G7: --json single document + prompt-free human rendering ---
t80_json clean --json
assert_exit "G7a clean-repo --json exits 0" 0 "$RC"
printf '%s' "$OUT" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
assert isinstance(d,dict) and 'assets' in d and 'overrides' in d
for r in d['assets']:
    rm=r.get('remediation')
    if rm is not None:
        assert isinstance(rm,list) and rm and all(isinstance(x,str) for x in rm), ('remediation must be an argv array of strings', r)
        assert '--overwrite' not in rm, ('remediation never carries --overwrite', r)
print('ok')" ; assert_exit "G7b stdout is one JSON object; remediation = argv arrays without --overwrite" 0 "$?"
mkdir -p "$T80_DIR/nogit"
OUT=$( cd "$T80_DIR/nogit" && GIT_CEILING_DIRECTORIES="$TESTBASE" node "$GOS" brownfield --json 2>/dev/null ); RC=$?
assert_exit "G7c non-git dir --json exits 4" 4 "$RC"
printf '%s' "$OUT" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
assert isinstance(d,dict) and d['error']['code']==4, d
print('ok')" ; assert_exit "G7d exit-4 stdout is one JSON error envelope (code 4)" 0 "$?"
mkdir -p "$T80_DIR/clean/sub/deep"
OUT=$( cd "$T80_DIR/clean/sub/deep" && node "$GOS" brownfield --json 2>/dev/null ); RC=$?
assert_exit "G7e cwd != toplevel exits 4" 4 "$RC"
t80_repo corr
mkdir -p "$T80_DIR/corr/.gos/cache"
printf 'this is { not json' > "$T80_DIR/corr/.gos/cache/commitlint-hook.json"
t80_run corr
assert_exit "G7f corrupt hooks state file exits 1" 1 "$RC"
assert_contains "G7g corrupt-state message prints the file path" "commitlint-hook.json" "$OUT"
# human rendering: remediation steps are numbered prose (never pipeable), --overwrite
# appears ONLY inside the override section
t80_run ac; HUMAN_AC="$OUT"
REM=$(printf '%s\n' "$HUMAN_AC" | awk '/^remediation steps:/{f=1;next} /^override/{f=0} f{print}')
if printf '%s\n' "$REM" | grep -Eq '^[[:space:]]*(gos|git|npx|npm|node|sh|bash|rm|mv|cp|chmod|echo|cat)([[:space:]]|$)'; then
  echo "  ✗ G7h remediation section contains a pipeable command line"; FAIL=$((FAIL+1))
else echo "  ✓ G7h remediation steps are numbered prose (nothing pipeable)"; PASS=$((PASS+1)); fi
OVR_HDR=$(printf '%s\n' "$HUMAN_AC" | grep -n '^override' | head -1 | cut -d: -f1)
LEAK=$(printf '%s\n' "$HUMAN_AC" | awk -v h="$OVR_HDR" 'NR<h && /--overwrite/ {print NR": "$0}')
assert_eq "G7i --overwrite named only in the override section" "" "$LEAK"
t80_run clean; HUMAN_CLEAN="$OUT"
REM2=$(printf '%s\n' "$HUMAN_CLEAN" | awk '/^remediation steps:/{f=1;next} /^override/{f=0} f{print}')
if printf '%s\n' "$REM2" | grep -Eq '^[[:space:]]*(gos|git|npx|npm|node|sh|bash|rm|mv|cp|chmod|echo|cat)([[:space:]]|$)'; then
  echo "  ✗ G7j clean-run remediation contains a pipeable command line"; FAIL=$((FAIL+1))
else echo "  ✓ G7j clean-run remediation steps are numbered prose"; PASS=$((PASS+1)); fi
assert_contains "G7k dormant hook line uses escaped-bracket flags" "hooks/commit-msg \[inactive\]" "$HUMAN_CLEAN"

# --- G8: gates skeleton is EMPTY + untrusted (no auto-trust) ---
python3 - "$T80_DIR/clean/.gos/gates.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d['protect']==[] and d['forbid']==[] and d['lint'] is None, d
assert isinstance(d.get('_comment'),str) and d['_comment'], 'comment retained'
print('ok')
PY
assert_exit "G8a gates.json skeleton: protect/forbid [] + lint null + _comment" 0 "$?"
assert_file "G8b .gos/gates/check.sh seeded" "$T80_DIR/clean/.gos/gates/check.sh"
if [ ! -e "$T80_DIR/clean/.gos/cache/trust.json" ]; then
  echo "  ✓ G8c trust store untouched/absent (no auto-trust, R1-F7)"; PASS=$((PASS+1))
else echo "  ✗ G8c trust store must not be written by brownfield"; FAIL=$((FAIL+1)); fi
t80_json clean --json
assert_eq "G8d check.sh row state_flags [untrusted]" '["untrusted"]' "$(t80_row "$OUT" .gos/gates/check.sh state_flags)"
assert_eq "G8e check.sh remediation = trust-after-review argv" '["gos", "gate", "trust", "check.sh"]' "$(t80_row "$OUT" .gos/gates/check.sh remediation)"

# --- G9: .gos/.gitignore semantics + root .gitignore never touched ---
assert_contains "G9a .gos/.gitignore has the .lock line" ".lock" "$(cat "$T80_DIR/clean/.gos/.gitignore")"
assert_eq "G9b root .gitignore byte-identical (never touched)" "root-keep/" "$(cat "$T80_DIR/clean/.gitignore" 2>/dev/null || true)"
( cd "$T80_DIR/clean" && git check-ignore -q .gos/.lock ) ; assert_exit "G9c git check-ignore .gos/.lock exit 0" 0 "$?"
t80_repo ownlock
mkdir -p "$T80_DIR/ownlock/.gos"
printf '.lock\n# user note\n' > "$T80_DIR/ownlock/.gos/.gitignore"
OWN_SHA=$(t80_sha "$T80_DIR/ownlock/.gos/.gitignore")
t80_json ownlock --json
assert_eq "G9d existing effective .lock line -> kept_identical" "kept_identical" "$(t80_row "$OUT" .gos/.gitignore status)"
assert_eq "G9e effective .lock gitignore left byte-identical" "$OWN_SHA" "$(t80_sha "$T80_DIR/ownlock/.gos/.gitignore")"

# --- G11 (review M1): symlink directory escape — hooks symlinked outside the
# repo is blocked (reason token), nothing is written through the symlink ---
t80_repo esc
mkdir -p "$T80_DIR/esc-outside"   # outside the repo, inside the sandbox (auto-cleaned)
ln -s "$T80_DIR/esc-outside" "$T80_DIR/esc/hooks"
t80_json esc --json
assert_exit "G11a symlink-escape repo run exits 0" 0 "$RC"
assert_eq "G11b hooks row report_only (blocked path, not kept_conflict)" "report_only" "$(t80_row "$OUT" hooks/commit-msg status)"
assert_contains "G11c hooks row reason carries the symlink-escape token" "symlink escape" "$(t80_row "$OUT" hooks/commit-msg reason)"
assert_eq "G11d blocked hooks row carries NO override (D-89)" "" "$(t80_ovr "$OUT" | grep -w hooks/commit-msg || true)"
assert_eq "G11e nothing written through the symlink (outside target stays empty)" "" "$(ls -A "$T80_DIR/esc-outside")"
t80_run esc --overwrite hooks/commit-msg
assert_exit "G11f --overwrite on a symlink-escaped path refuses exit 2" 2 "$RC"
assert_eq "G11g refusal still writes nothing outside" "" "$(ls -A "$T80_DIR/esc-outside")"

# --- G12 (review M3): drifted GOS-lineage hook (gos-managed marker, divergent
# bytes) is a genuine conflict — kept_conflict + override; --overwrite adopts
# with the standard .gos-bak backup (never mislabeled locked_user_owned) ---
t80_repo drift
mkdir -p "$T80_DIR/drift/hooks"
cp "$CM_MASTER" "$T80_DIR/drift/hooks/commit-msg"
printf '# local drift after a gos-managed install\n' >> "$T80_DIR/drift/hooks/commit-msg"
DRIFT_SHA=$(t80_sha "$T80_DIR/drift/hooks/commit-msg")
t80_json drift --json
assert_exit "G12a drifted-marker repo run exits 0" 0 "$RC"
assert_eq "G12b drifted marker hook kept_conflict (not locked_user_owned)" "kept_conflict" "$(t80_row "$OUT" hooks/commit-msg status)"
assert_contains "G12c reason names the drifted-hook class" "local edits" "$(t80_row "$OUT" hooks/commit-msg reason)"
assert_eq "G12d override entry present for the drifted hook" "hooks/commit-msg" "$(t80_ovr "$OUT" | grep -w hooks/commit-msg || true)"
assert_eq "G12e drifted hook byte-identical after the bare run" "$DRIFT_SHA" "$(t80_sha "$T80_DIR/drift/hooks/commit-msg")"
t80_run drift --overwrite hooks/commit-msg
assert_exit "G12f --overwrite hooks/commit-msg adopts the drifted hook" 0 "$RC"
assert_file "G12g drift backup written (.gos-bak)" "$T80_DIR/drift/hooks/commit-msg.gos-bak"
assert_eq "G12h backup holds the drifted bytes" "$DRIFT_SHA" "$(t80_sha "$T80_DIR/drift/hooks/commit-msg.gos-bak")"
if cmp -s "$CM_MASTER" "$T80_DIR/drift/hooks/commit-msg"; then echo "  ✓ G12i adopted hook byte-equal to master"; PASS=$((PASS+1));
else echo "  ✗ G12i adopted hook differs from master"; FAIL=$((FAIL+1)); fi

# --- G13 (review M4): preflight-blocked paths are report_only with the frozen
# reason (kept_conflict is reserved for genuine content conflicts) ---
t80_repo blk
printf 'plain file occupying the hooks dir slot\n' > "$T80_DIR/blk/hooks"
printf 'plain file occupying .gos\n' > "$T80_DIR/blk/.gos"
t80_json blk --json
assert_exit "G13a blocked-path repo run exits 0" 0 "$RC"
assert_eq "G13b hooks row blocked -> report_only" "report_only" "$(t80_row "$OUT" hooks/commit-msg status)"
assert_eq "G13c gates.json row blocked -> report_only" "report_only" "$(t80_row "$OUT" .gos/gates.json status)"
assert_eq "G13d .gos/.gitignore row blocked -> report_only" "report_only" "$(t80_row "$OUT" .gos/.gitignore status)"
assert_contains "G13e blocked row reason carries the preflight token" "non-directory" "$(t80_row "$OUT" hooks/commit-msg reason)"
printf '%s' "$OUT" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
kc={r['asset'] for r in d['assets'] if r['status']=='kept_conflict'}
ovr={e['asset'] for e in d.get('overrides',[])}
assert kc==ovr and not kc, ('blocked fixture must carry zero kept_conflict/override rows', sorted(kc), sorted(ovr))
print('ok')" ; assert_exit "G13f blocked fixture: no kept_conflict rows, no override rows (D-89)" 0 "$?"

# --- G14 (review M5): git-config-controlled hooksPath renders shell-quoted ---
t80_repo spc
git -C "$T80_DIR/spc" config core.hooksPath "my hooks dir"
t80_run spc
assert_exit "G14a space-bearing foreign hooksPath run exits 0" 0 "$RC"
assert_contains "G14b foreign-class reason renders the raw path shell-quoted" "'my hooks dir'" "$OUT"

# --- G15 (review m7): two named --overwrite values die — no silent last-wins ---
t80_repo dup
t80_run dup --overwrite hooks/commit-msg --overwrite hooks/pre-push
assert_exit "G15a duplicate named --overwrite dies exit 1" 1 "$RC"
assert_contains "G15b refusal names the unexpected argument" "unexpected argument" "$OUT"

# --- G10: never-created sweep + prompt-free module grep ---
G10_BAD=$(find "$T80_DIR" -path '*/.git' -prune -o \( -name .github -o -name CODEOWNERS -o -name CHANGELOG.md \) -print | head -5)
assert_eq "G10a no .github//CODEOWNERS/CHANGELOG.md created in any fixture" "" "$G10_BAD"
if grep -q 'ask(' "$GOS_ROOT/bin/lib/ops/brownfield.cjs"; then
  echo "  ✗ G10b brownfield.cjs reaches an interactive primitive (ask()"; FAIL=$((FAIL+1))
else echo "  ✓ G10b no interactive primitive in brownfield.cjs"; PASS=$((PASS+1)); fi
if grep -Eq 'onboarding|process\.stdin' "$GOS_ROOT/bin/lib/ops/brownfield.cjs"; then
  echo "  ✗ G10c brownfield.cjs imports onboarding or reads stdin"; FAIL=$((FAIL+1))
else echo "  ✓ G10c no onboarding import, no stdin read"; PASS=$((PASS+1)); fi

t80_teardown
echo "--- T80 done ---"
