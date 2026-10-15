#!/usr/bin/env bash
# Built-in security gate: blocks commit if secrets or dangerous patterns
# are present in staged/tracked source files. Exit non-zero = gate failed.
# Used by `gos gate` (custom-gate layer) — copy/symlink into .gos/gates/ to activate.

set -uo pipefail

PATTERNS_SECRETS='(api[_-]?key|secret|password|token)\s*[:=]\s*["'"'"'][A-Za-z0-9+/_-]{16,}'
# D-11 (R-25): the rm branch left this regex for the token classifier below —
# a flat `rm -rf /x` regex both over-blocks Dockerfile cleanup lines
# (/var/lib/apt/lists/*, /home/user/.cache) and under-blocks flag/target
# permutations (-fr, -r -f, --force --recursive, quoted or $HOME targets).
PATTERNS_DANGER='(eval\s*\(\s*["'"'"']|child_process.*shell.*true|curl.*\|\s*sudo\s*bash)'

FAILED=0

# rm-invocation classifier (D-11 depth-aware default-deny).
# Preprocessing per line: join `\<newline>` continuations, strip surrounding
# quotes on target tokens, ${VAR} -> $VAR. Flags tokenized: recursive and
# force must BOTH be present — short-flag letters (any order/grouping, e.g.
# -rf/-fr/-r -f/-rvf) or long flags (--recursive/--force, any mix) qualify.
# Target classification by path depth after normalization:
#   depth-0 (`/` bare, `/*`) and var-roots (`~`, `$HOME` as the whole target,
#   or wholesale `~/*`/`$HOME/*` contents) are DANGER;
#   depth-1 or `/<seg>/*` is DANGER unless the root is in SAFE_ROOTS
#   {/tmp, /var/tmp, /dev/shm, /opt, /workspace, /app, /build, /dist};
#   depth-2 is DANGER only under mount/backup roots {/mnt, /media, /Volumes};
#   depth >= 3 passes. `..` segments are DANGER (depth unknowable).
# Residual (documented, not gated): relative-target and unknown-$VAR rm
# semantics under a changed WORKDIR.
RM_DANGER_AWK='
function issep(t) { return (t ~ /^(&&|\|\||;|&|\||>>|>|<<|<|2>|2>&1)$/) ? 1 : 0 }
function clean(t) {            # strip shell punctuation glued to the token
  sub(/^\(+/, "", t)
  sub(/[;,)]+$/, "", t)
  return t
}
function normalize(t,  m) {    # clean + strip surrounding quotes + ${VAR} -> $VAR
  t = clean(t)
  if (length(t) >= 2 && (substr(t, 1, 1) == "\"" || substr(t, 1, 1) == "\047") && substr(t, 1, 1) == substr(t, length(t), 1))
    t = substr(t, 2, length(t) - 2)
  while (match(t, /\$\{[^}]*\}/)) {
    m = substr(t, RSTART, RLENGTH)
    t = substr(t, 1, RSTART - 1) "$" substr(m, 3, length(m) - 3) substr(t, RSTART + RLENGTH)
  }
  return t
}
function danger(t,   rest, seg, n, k, d, root) {
  if (t == "~" || t == "~/" || t == "$HOME" || t == "$HOME/") return 1
  if (substr(t, 1, 2) == "~/") rest = substr(t, 3)
  else if (substr(t, 1, 6) == "$HOME/") rest = substr(t, 7)
  else rest = ""
  if (rest != "")                                        # var-root subpath:
    return (rest ~ /^[/*]+$/) ? 1 : 0                    #   wholesale = DANGER, real segment = post-expansion depth, passes
  if (substr(t, 1, 1) != "/") return 0                   # relative / unknown $VAR: residual, passes
  n = split(t, seg, "/")
  d = 0; root = ""
  for (k = 1; k <= n; k++) {
    if (seg[k] == "" || seg[k] == "." || seg[k] == "*") continue
    if (seg[k] == "..") return 1                         # traversal: depth unknowable, default-deny
    d++
    if (d == 1) root = seg[k]
  }
  if (d == 0) return 1                                   # `/` bare or `/*`
  if (d == 1) return (("/" root) in SAFE_ROOTS) ? 0 : 1
  if (d == 2) return (root == "mnt" || root == "media" || root == "Volumes") ? 1 : 0
  return 0                                               # depth >= 3
}
BEGIN {
  n = split("/tmp /var/tmp /dev/shm /opt /workspace /app /build /dist", sroots, " ")
  for (k = 1; k <= n; k++) SAFE_ROOTS[sroots[k]] = 1
}
{
  line = $0
  while (line ~ /\\$/) {                                 # join `\<newline>` continuations
    if ((getline nxt) <= 0) break
    sub(/\\$/, "", line)
    line = line " " nxt
  }
  n = split(line, tok, /[ \t]+/)
  for (i = 1; i <= n; i++) {
    if (clean(tok[i]) != "rm") continue
    hasr = 0; hasf = 0; lr = 0; lf = 0; dd = 0; nt = 0   # tokenize one rm invocation
    for (j = i + 1; j <= n; j++) {
      t = tok[j]
      if (t == "") continue
      if (issep(t)) break                                # shell separator ends the invocation
      if (dd == 0 && t == "--") { dd = 1; continue }
      if (dd == 0 && t ~ /^--/) {
        s = t; sub(/^--/, "", s); sub(/=.*$/, "", s)
        if (s == "recursive") lr = 1
        if (s == "force") lf = 1
        continue
      }
      if (dd == 0 && t ~ /^-/) {
        s = t; sub(/^-+/, "", s)
        if (s ~ /^[A-Za-z]+$/) {
          s = tolower(s)
          if (index(s, "r") > 0) hasr = 1
          if (index(s, "f") > 0) hasf = 1
          continue
        }
      }
      t = normalize(t)
      if (t != "") T[++nt] = t
    }
    if ((hasr || lr) && (hasf || lf))                    # recursive AND force, short/long any mix
      for (j = 1; j <= nt; j++)
        if (danger(T[j])) { print NR ":" line; next }
  }
}
'

# Scan staged + tracked files (skip tests/fixtures/docs/markdown)
FILES=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null; git ls-files 2>/dev/null | grep -v '^\.gos/' )
FILES=$(echo "$FILES" | sort -u | grep -Ev '\.(md|lock|json)$|(^|/)(test|tests|fixtures|mocks)/|^gates/|security\.sh$' || true)

for f in $FILES; do
  [ -f "$f" ] || continue
  if grep -Enq "$PATTERNS_SECRETS" "$f" 2>/dev/null; then
    echo "SECRET-LIKE pattern in $f:" >&2
    grep -En "$PATTERNS_SECRETS" "$f" 2>/dev/null | head -3 >&2
    FAILED=1
  fi
  if grep -Enq "$PATTERNS_DANGER" "$f" 2>/dev/null; then
    echo "DANGEROUS pattern in $f:" >&2
    grep -En "$PATTERNS_DANGER" "$f" 2>/dev/null | head -3 >&2
    FAILED=1
  fi
  # D-11 (R-25): rm branch — tokenized depth-aware classification
  RM_ALL="$(awk "$RM_DANGER_AWK" "$f" 2>/dev/null)"
  if [ $? -ne 0 ]; then
    echo "DANGEROUS pattern in $f: (rm classifier failed — failing closed)" >&2
    FAILED=1
  elif [ -n "$RM_ALL" ]; then
    echo "DANGEROUS pattern in $f:" >&2
    printf '%s\n' "$RM_ALL" | head -3 >&2
    FAILED=1
  fi
done

if [ $FAILED -ne 0 ]; then
  echo "security gate: FAIL — resolve above or move values to env/config" >&2
  exit 2
fi
echo "security gate: clean"
exit 0
