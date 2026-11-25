#!/usr/bin/env bash
# gos-map:none
# tier-roster semantics — the runner's --tier pr|main selection contract:
# PR tier = affected subset ∪ invariant enumeration ∪ unmarked gos-map:none
# floor − gos-tier:main-marked sections whose files are NOT in the input (a
# marked section whose file IS in the input keeps its slot — new-section
# precedence); main tier carries the whole map:none family plus the
# invariants; gos-tier:main on a non-map:none section is a roster-build
# error; self-selection injects section names from the raw input before the
# empty-input exits; the blast call is skipped (the map:none floor still
# joins) when the pre-filter empties the input on a pre-selected roster.
# Rosters are observed through GOS_SECTIONS_ROSTER_ONLY=1 (no section
# executes, the roster prints one name per line); the input set is pinned
# with explicit file arguments so assertions are deterministic.
GOS_ROOT="${GOS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
T137_RUNNER="$GOS_ROOT/test/run-sections.sh"
T137_SECS_TREE="${GOS_SECTIONS_TREE:-$GOS_ROOT}"

t137_roster() {
  ( cd "$GOS_ROOT" && GOS_SECTIONS_ROSTER_ONLY=1 bash "$T137_RUNNER" "$@" 2>/dev/null )
}

t137_roster_all() {
  ( cd "$GOS_ROOT" && GOS_SECTIONS_ROSTER_ONLY=1 bash "$T137_RUNNER" "$@" 2>&1 )
}

t137_has() { printf '%s\n' "$1" | grep -qx "$2"; }

# base = parent of the most recent commit touching a section file: the diff
# always carries at least one test/sections/T*.test.sh path, so the blast
# path below exercises a real code-touching selection
T137_BASE="$(git -C "$GOS_ROOT" log --format=%H -n 1 -- 'test/sections/T*.test.sh')^"

PASS=0; FAIL=0
echo "--- T137: tier-roster selection semantics (--tier pr|main) ---"

# ===== (a) PR tier: invariants + unmarked floor stay, marked rides main =====
# explicit file input pins self-selection to an unmarked section, so every
# marked section is off-input here
PR_A="$(t137_roster --tier pr --base HEAD test/sections/T35-u-negative.test.sh)"
for n in T46-module-structure T66-census-reconcile T85-security-depth T102-ai-trace T109-changelog-structural; do
  if t137_has "$PR_A" "$n"; then echo "  ✓ a1 invariant $n in the PR roster"; PASS=$((PASS+1))
  else echo "  ✗ a1 invariant $n missing from the PR roster"; FAIL=$((FAIL+1)); fi
done
for n in T35-u-negative T37-phase-ux T39-render-park; do
  if t137_has "$PR_A" "$n"; then echo "  ✓ a2 unmarked floor $n in the PR roster"; PASS=$((PASS+1))
  else echo "  ✗ a2 unmarked floor $n missing from the PR roster"; FAIL=$((FAIL+1)); fi
done
if t137_has "$PR_A" "T104-auto-core"; then echo "  ✗ a3 marked T104-auto-core must ride the main closeout"; FAIL=$((FAIL+1))
else echo "  ✓ a3 marked T104-auto-core excluded from the PR roster"; PASS=$((PASS+1)); fi

# ===== (b) main tier carries the whole map:none family =====
PR_M="$(t137_roster --tier main --base HEAD test/sections/T35-u-negative.test.sh)"
for n in T104-auto-core T35-u-negative T46-module-structure; do
  if t137_has "$PR_M" "$n"; then echo "  ✓ b1 main roster carries $n"; PASS=$((PASS+1))
  else echo "  ✗ b1 main roster missing $n"; FAIL=$((FAIL+1)); fi
done

# ===== (c) marked section in the input keeps its PR slot (precedence) =====
PR_C="$(t137_roster --tier pr --base HEAD test/sections/T104-auto-core.test.sh)"
if t137_has "$PR_C" "T104-auto-core"; then echo "  ✓ c1 marked in-input T104-auto-core keeps its PR slot"; PASS=$((PASS+1))
else echo "  ✗ c1 marked in-input T104-auto-core dropped from the PR roster"; FAIL=$((FAIL+1)); fi

# ===== (d) plain --affected keeps the full map:none floor and gains self-selection =====
PLAIN="$(t137_roster --affected --base HEAD test/sections/T35-u-negative.test.sh)"
if t137_has "$PLAIN" "T35-u-negative"; then echo "  ✓ d1 plain affected self-selects T35-u-negative"; PASS=$((PASS+1))
else echo "  ✗ d1 plain affected did not self-select T35-u-negative"; FAIL=$((FAIL+1)); fi
if t137_has "$PLAIN" "T104-auto-core"; then echo "  ✓ d2 plain affected floor keeps T104-auto-core (no tier strip)"; PASS=$((PASS+1))
else echo "  ✗ d2 plain affected floor dropped T104-auto-core"; FAIL=$((FAIL+1)); fi

# ===== (e) code-touching diff drives the blast path =====
PR_E="$(t137_roster --tier pr --base "$T137_BASE")"
for n in T46-module-structure T35-u-negative; do
  if t137_has "$PR_E" "$n"; then echo "  ✓ e1 blast-path PR roster keeps $n"; PASS=$((PASS+1))
  else echo "  ✗ e1 blast-path PR roster dropped $n"; FAIL=$((FAIL+1)); fi
done
LOG_E="$(t137_roster_all --tier pr --base "$T137_BASE")"
if printf '%s\n' "$LOG_E" | grep -q "self-selected section files"; then echo "  ✓ e2 selection log shows the self-selected group"; PASS=$((PASS+1))
else echo "  ✗ e2 selection log has no self-selected group"; FAIL=$((FAIL+1)); fi

# ===== (f) marker misuse is a roster-build error =====
# The f-case materializes a bad-marker fixture inside the sections tree; a
# read-only sections tree (the local verify script-leg writable surface)
# cannot host it, so the case degrades to an explicit skip there — CI's
# writable checkout always exercises it.
T137_FIX="$T137_SECS_TREE/test/sections/T901-tier-marker-bad.test.sh"
if [ -d "$T137_SECS_TREE/test/sections" ] && [ -w "$T137_SECS_TREE/test/sections" ]; then
  printf '#!/usr/bin/env bash\n# gos-tier:main\necho "  never runs"\n' > "$T137_FIX"
  OUT_F="$(t137_roster_all --tier pr --base HEAD)"; RC_F=$?
  rm -f "$T137_FIX"
  if [ "$RC_F" -ne 0 ]; then echo "  ✓ f1 marker misuse fails the roster build (exit $RC_F)"; PASS=$((PASS+1))
  else echo "  ✗ f1 marker misuse exited 0"; FAIL=$((FAIL+1)); fi
  if printf '%s\n' "$OUT_F" | grep -q "roster error"; then echo "  ✓ f2 roster error names the marker misuse"; PASS=$((PASS+1))
  else echo "  ✗ f2 roster error line missing"; FAIL=$((FAIL+1)); fi
else
  echo "  skip f1/f2: sections tree read-only (sandbox VERIFY surface; CI checkout exercises these)"
fi

# ===== (g) unknown tier value is rejected =====
OUT_G="$(t137_roster_all --tier bogus --base HEAD)"; RC_G=$?
if [ "$RC_G" -ne 0 ]; then echo "  ✓ g1 unknown tier rejected (exit $RC_G)"; PASS=$((PASS+1))
else echo "  ✗ g1 unknown tier accepted"; FAIL=$((FAIL+1)); fi
if printf '%s\n' "$OUT_G" | grep -q "unknown tier"; then echo "  ✓ g2 error names the bad tier value"; PASS=$((PASS+1))
else echo "  ✗ g2 unknown-tier error line missing"; FAIL=$((FAIL+1)); fi

echo "--- T137 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
