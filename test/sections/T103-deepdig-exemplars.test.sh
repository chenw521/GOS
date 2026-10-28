#!/usr/bin/env bash
# gos-map:none
# Static check for the dig exemplar file: existence, exactly three case
# records, one 5-column card per case, a deepen-round marker, and the
# de-identification grep (concern hex ids, decision ids, sha-shaped hex
# runs, ISO dates) zero-hit on this file only.
# Standalone-safe: self-provisions env when not run under test/run-sections.sh.

T103_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T103_STANDALONE=1
  T103_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS_ROOT="$T103_ROOT"
  export TESTBASE="$(mktemp -d "$GOS_ROOT/test-sections-base-XXXXXX")"
fi

t103_teardown() {
  if [ "$T103_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t103_teardown EXIT

PASS=0
FAIL=0
t103_ok()  { echo "  ✓ $1"; PASS=$((PASS+1)); }
t103_bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

echo "--- T103: dig exemplar file + de-identification ---"

EXEMPLAR="$GOS_ROOT/skills/gos-think/examples/deep-dig-cases.md"

# --- .1: exemplar file exists and is non-empty
if [ -s "$EXEMPLAR" ]; then
  t103_ok "exemplar file exists and is non-empty"
else
  t103_bad "exemplar file missing or empty: $EXEMPLAR"
fi

# --- .2: exactly three case records
CASES=$(grep -c "^## Case" "$EXEMPLAR" || true)
if [ "${CASES:-0}" = "3" ]; then
  t103_ok "exactly 3 case records (## Case headings = $CASES)"
else
  t103_bad "case record count = ${CASES:-0}, want 3"
fi

# --- .3: de-identification grep is zero-hit on this file
# (concern hex ids, D-NN ids, sha-length hex runs, ISO dates; grep exits
# 1 on zero matches — coalesce and compare the printed count to 0)
DEID=$(grep -cE '[0-9a-f]{8}|D-[0-9]{2,3}($|[^0-9])|[0-9a-f]{7,40}|[0-9]{4}-[0-9]{2}-[0-9]{2}' "$EXEMPLAR" || true)
if [ "${DEID:-1}" = "0" ]; then
  t103_ok "de-identification grep zero-hit (hex ids / decision ids / shas / dates)"
else
  t103_bad "de-identification grep hit ${DEID:-1} line(s), want 0"
fi

# --- .4: one 5-column card table per case
CARDS=$(grep -c '^| Option | Premise | Pros | Cons | Activates |' "$EXEMPLAR" || true)
if [ "${CARDS:-0}" -ge 3 ]; then
  t103_ok "5-column card header present in every case (count = $CARDS, want >= 3)"
else
  t103_bad "5-column card headers = ${CARDS:-0}, want >= 3"
fi

# --- .5: at least one deepen-round opening marker
NEWFACTS=$(grep -c "new facts:" "$EXEMPLAR" || true)
if [ "${NEWFACTS:-0}" -ge 1 ]; then
  t103_ok "deepen round marker present (new facts: lines = $NEWFACTS)"
else
  t103_bad "no 'new facts:' line found in exemplar file"
fi

echo "--- T103 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
