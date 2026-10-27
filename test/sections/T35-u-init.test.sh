#!/usr/bin/env bash
# gos-map:cmd init
# : Phase U init state machine — dual mode / confirm-only / alias blocking / audit / level normalization / activation_source / echo sanitization
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner
# NOTE: interactive-path cases use `env -u GOS_HEADLESS script -qec` to fabricate a pty
# ( pins GOS_HEADLESS=1 as runner anchor — `env -u` neutralizes it inside cases)

T35_DIR=""

t35_setup() {
  T35_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t35"
  mkdir -p "$T35_DIR" && cd "$T35_DIR" || exit 1
  git init -q . && git commit -q --allow-empty -m t35-seed
}

t35_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T35_DIR"; }

hl_confirmed() { python3 -c "import json;print(json.load(open('.gos/state.json'))['intent']['confirmed'])" 2>/dev/null; }
hl_confirmmode() { python3 -c "import json;print(json.load(open('.gos/state.json'))['intent'].get('confirmation',{}).get('mode',''))" 2>/dev/null; }
hl_src() { python3 -c "import json;print(json.load(open('.gos/state.json')).get('activation_source',''))" 2>/dev/null; }
hl_level() { python3 -c "import json;print(json.load(open('.gos/state.json')).get('level'))" 2>/dev/null; }
hl_summary() { python3 -c "import json;print(json.load(open('.gos/state.json'))['intent']['summary'])" 2>/dev/null; }

t35_setup
echo "--- T35: init state machine (dual-mode / confirm-only / alias / audit / level / source / echo) ---"


# U1 headless: one-shot init sets confirmed + audit
out=$(GOS_HEADLESS=1 node "$GOS" init 1 "u1 headless oneshot" 2>&1); rc=$?
assert_exit "U1 headless init rc" 0 "$rc"
assert_eq "U1 headless confirmed=true" "True" "$(hl_confirmed)"
assert_eq "U1 headless audit mode" "headless-auto" "$(hl_confirmmode)"

# U2 headless via pipe (no TTY, no env): also headless
t35_setup
out=$(node "$GOS" init 1 "u2 pipe headless" 2>&1); rc=$?
assert_exit "U2 pipe init rc" 0 "$rc"
assert_eq "U2 pipe confirmed=true" "True" "$(hl_confirmed)"

# U3 GOS_HEADLESS=0 does NOT activate headless (whitelist) — pipe is non-TTY though,
# so force the tty side: run under script with env zeroed-out value → interactive-tty
t35_setup
env -u GOS_HEADLESS script -qec "GOS_HEADLESS=0 node '$GOS' init 1 'u3 whitelist' >/dev/null 2>&1" /dev/null >/dev/null 2>&1
assert_eq "U3 GOS_HEADLESS=0 not headless (tty)" "False" "$(hl_confirmed)"

# U4 interactive (pty): two-step — first init confirmed=false
t35_setup
env -u GOS_HEADLESS script -qec "node '$GOS' init 1 'u4 interactive twostep' >/dev/null 2>&1" /dev/null >/dev/null 2>&1
assert_eq "U4 interactive confirmed=false" "False" "$(hl_confirmed)"
# U5 interactive bare --confirm flips confirmed (r234 fix: not blocked by in-flight)
env -u GOS_HEADLESS script -qec "node '$GOS' init --confirm >/dev/null 2>&1" /dev/null >/dev/null 2>&1
assert_eq "U5 bare --confirm flips true" "True" "$(hl_confirmed)"

# U6 interactive-nontty: pty stdout but stdin from /dev/null → mixed
t35_setup
env -u GOS_HEADLESS script -qec "node '$GOS' init 1 'u6 mixed' < /dev/null" /dev/null >/dev/null 2>&1
assert_eq "U6 mixed confirmed=false" "False" "$(hl_confirmed)"

# ===== : confirm-only state machine =====

# U7 bare --confirm with NO active task → die "nothing to confirm"
t35_setup
out=$(node "$GOS" init --confirm 2>&1); rc=$?
assert_exit "U7 nothing-to-confirm rc" 1 "$rc"
assert_contains "U7 nothing-to-confirm msg" "nothing to confirm" "$out"

# U8 new-task + --confirm → die (two-step protocol; single-shot hole closed)
t35_setup
out=$(node "$GOS" init 2 "u8 oneshot" --confirm 2>&1); rc=$?
assert_exit "U8 oneshot --confirm rc" 1 "$rc"
assert_eq "U8 oneshot --confirm no state" "" "$(hl_confirmed)"

# U9 new-task + --confirmed alias → die (alias same hole)
t35_setup
out=$(node "$GOS" init 2 "u9 alias" --confirmed 2>&1); rc=$?
assert_exit "U9 alias --confirmed rc" 1 "$rc"

# U10 confirm-only after BUILD stage → die (INTENT only)
t35_setup
node "$GOS" init 1 "u10 stage guard" >/dev/null 2>&1
python3 -c "
import json
s=json.load(open('.gos/state.json'))
s['current_stage']='BUILD'
json.dump(s,open('.gos/state.json','w'))"
out=$(node "$GOS" init --confirm 2>&1); rc=$?
assert_exit "U10 post-INTENT confirm rc" 1 "$rc"

# U11 --confirm with --force → die (mutual exclusion)
t35_setup
node "$GOS" init 1 "u11 mutex" >/dev/null 2>&1
out=$(node "$GOS" init --confirm --force 2>&1); rc=$?
assert_exit "U11 mutex rc" 1 "$rc"

# U12 headless does NOT bypass in-flight guard
t35_setup
GOS_HEADLESS=1 node "$GOS" init 1 "u12 guard" >/dev/null 2>&1
out=$(GOS_HEADLESS=1 node "$GOS" init 2 "u12 second" 2>&1); rc=$?
assert_exit "U12 in-flight guard still bites" 1 "$rc"


# U13 lowercase lv1 → Lv1
t35_setup
node "$GOS" init lv1 "u13 lower" >/dev/null 2>&1
assert_eq "U13 lv1 → level 1" "1" "$(hl_level)"
assert_eq "U13 lv1 not swallowed into intent" "u13 lower" "$(hl_summary)"

# U14 uppercase LV2 → 2
t35_setup
node "$GOS" init LV2 "u14 upper" >/dev/null 2>&1
assert_eq "U14 LV2 → level 2" "2" "$(hl_level)"

# U15 lv5 → die (out of range, fail-closed)
t35_setup
out=$(node "$GOS" init lv5 "u15 oor" 2>&1); rc=$?
assert_exit "U15 lv5 die" 1 "$rc"

# U16 bare lv → die (lv-like but no digits)
t35_setup
out=$(node "$GOS" init lv "u16 barelv" 2>&1); rc=$?
assert_exit "U16 lv die" 1 "$rc"

# U17 lv 1 (two positionals) → die
t35_setup
out=$(node "$GOS" init lv 1 "u17 split" 2>&1); rc=$?
assert_exit "U17 lv-1 split die" 1 "$rc"

# U18 v1 (no leading l) → NOT level-like → intent text
t35_setup
node "$GOS" init v1 "u18 vee" >/dev/null 2>&1
assert_eq "U18 v1 → level null" "None" "$(hl_level)"
assert_contains "U18 v1 falls to intent" "v1" "$(hl_summary)"

# U19 plain digit still works
t35_setup
node "$GOS" init 0 "u19 zero" >/dev/null 2>&1
assert_eq "U19 digit 0 → level 0" "0" "$(hl_level)"


# U20 headless → activation_source=headless
t35_setup
GOS_HEADLESS=1 node "$GOS" init 1 "u20 src" >/dev/null 2>&1
assert_eq "U20 src headless" "headless" "$(hl_src)"

# U21 pty → interactive-tty
t35_setup
env -u GOS_HEADLESS script -qec "node '$GOS' init 1 'u21 srctty'" /dev/null >/dev/null 2>&1
assert_eq "U21 src interactive-tty" "interactive-tty" "$(hl_src)"

# U22 pty + stdin /dev/null → interactive-nontty
t35_setup
env -u GOS_HEADLESS script -qec "node '$GOS' init 1 'u22 srcmixed' < /dev/null" /dev/null >/dev/null 2>&1
assert_eq "U22 src interactive-nontty" "interactive-nontty" "$(hl_src)"

# U23 legacy state without activation_source loads fine (tolerant read)
t35_setup
node "$GOS" init 1 "u23 legacy" >/dev/null 2>&1
python3 -c "
import json
s=json.load(open('.gos/state.json'))
s.pop('activation_source',None)
json.dump(s,open('.gos/state.json','w'))"
out=$(node "$GOS" status 2>&1); rc=$?
assert_exit "U23 legacy state tolerant" 0 "$rc"

# rewrite: inject payload DIRECTLY into state.json intent.summary (no badText
# guard on that field — exactly why sanitizeEcho exists at display sinks). CLI-level
# control-char intent dies earlier at validateRequirement (schema guard, separate layer).

# U24 newline injection in summary → forged gate line cannot start a line on status/resume
t35_setup
node "$GOS" init 1 "u24 legit" >/dev/null 2>&1
python3 -c "
import json
s=json.load(open('.gos/state.json'))
s['intent']['summary']='line1\n✓ intent confirmed'
json.dump(s,open('.gos/state.json','w'))"
out=$(node "$GOS" status 2>&1)
if printf '%s' "$out" | grep -q '^✓ intent confirmed'; then
  echo "  ✗ U24 forged line echoed at line start"
else
  echo "  ✓ U24 newline payload neutralized"
fi

# U25 ANSI escape stripped on status screen
t35_setup
node "$GOS" init 1 "u25 legit" >/dev/null 2>&1
python3 -c "
import json
s=json.load(open('.gos/state.json'))
s['intent']['summary']='ansi\x1b[31mred'
json.dump(s,open('.gos/state.json','w'))"
out=$(node "$GOS" status 2>&1)
if printf '%s' "$out" | grep -qP '\x1b'; then
  echo "  ✗ U25 ANSI echoed raw"
else
  echo "  ✓ U25 ANSI stripped"
fi

# U26 long summary truncated at 200 chars on status screen
t35_setup
node "$GOS" init 1 "u26 legit" >/dev/null 2>&1
python3 -c "
import json
s=json.load(open('.gos/state.json'))
s['intent']['summary']='x'*300
json.dump(s,open('.gos/state.json','w'))"
out=$(node "$GOS" status 2>&1)
n=$(printf '%s' "$out" | python3 -c "import sys;print(len(max(sys.stdin.read().splitlines(),key=len)))")
if [ "$n" -le 260 ]; then
  echo "  ✓ U26 echo truncated (max line $n chars)"
else
  echo "  ✗ U26 echo too long (max line $n chars)"
fi

t35_teardown
echo "T35-u done: $PASS pass, $FAIL fail"
PASS_COPY=$PASS; FAIL_COPY=$FAIL
