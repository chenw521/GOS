#!/usr/bin/env bash
# Structural lint for .github/workflows/*.yml (red-team : grep-based
# checks stand in for a non-existent external workflow linter — zero extra
# dependencies, works offline). Per workflow it asserts:
#   1. an `on:` trigger key exists;
#   2. `jobs:` exists and declares at least one job id;
#   3. the `needs:` graph is acyclic (Kahn peeling);
#   4. `permissions` grants `contents: read` — either at top level (applies to
#      every job that does not override it) or in every job block.
# Usage: bash test/workflow-lint.sh    (exit 0 = pass, 1 = violation)
set -uo pipefail

GOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WF_DIR="$GOS_ROOT/.github/workflows"

fail=0
found=0

# Emit one job id per line for a workflow (ids = 2-space-indented keys under
# the top-level `jobs:` mapping).
wf_jobs() {
  awk '
    /^jobs:/ { injobs = 1; next }
    injobs && /^[^ \t]/ { injobs = 0 }
    injobs && /^  [A-Za-z0-9_-]+:/ {
      id = $1; sub(/:$/, "", id); print id
    }
  ' "$1"
}

# Emit "job dep" edges from `needs:` values (inline scalar, inline [list],
# or block-style list items under `needs:`).
wf_edges() {
  awk '
    /^jobs:/ { injobs = 1; next }
    injobs && /^[^ \t]/ { injobs = 0 }
    injobs && /^  [A-Za-z0-9_-]+:/ {
      cur = $1; sub(/:$/, "", cur); inneeds = 0; next
    }
    injobs && cur != "" && /^    needs:/ {
      inneeds = 1
      v = $0; sub(/^    needs:/, "", v); gsub(/[\[\], \t]/, " ", v)
      n = split(v, a, / +/)
      for (i = 1; i <= n; i++) if (a[i] != "") print cur, a[i]
      next
    }
    injobs && inneeds && /^ +- / {
      v = $0; sub(/^ +- /, "", v); gsub(/[\[\],]/, "", v); gsub(/ /, "", v)
      if (v != "") print cur, v
      next
    }
    injobs && /^    [A-Za-z0-9_-]+:/ { inneeds = 0 }
  ' "$1"
}

# Kahn peeling over jobs+edges; returns 1 when the needs graph has a cycle
# (a dep that never resolves keeps its job stranded — that is a failure too).
needs_has_cycle() {
  local jobs_file="$1" edges_file="$2"
  local -A deps=() done=()
  local j d ok progress total=0
  while IFS= read -r j; do
    [ -n "$j" ] || continue
    deps["$j"]=""; total=$((total + 1))
  done < "$jobs_file"
  while IFS= read -r j d; do
    [ -n "$j" ] || continue
    deps["$j"]="${deps[$j]:-} $d"
  done < "$edges_file"
  progress=1
  while (( progress )); do
    progress=0
    for j in "${!deps[@]}"; do
      [ -n "${done[$j]:-}" ] && continue
      ok=1
      for d in ${deps[$j]}; do
        [ -z "${done[$d]:-}" ] && { ok=0; break; }
      done
      if (( ok )); then done["$j"]=1; progress=1; fi
    done
  done
  (( ${#done[@]} < total ))
}

for wf in "$WF_DIR"/*.yml; do
  [ -e "$wf" ] || continue
  found=1
  rel="${wf#"$GOS_ROOT"/}"

  if ! grep -Eq '^on:' "$wf"; then
    echo "FAIL $rel: missing 'on:' trigger key"
    fail=1
  fi

  jobs_file="$(mktemp)"; edges_file="$(mktemp)"
  wf_jobs "$wf" > "$jobs_file"
  wf_edges "$wf" > "$edges_file"
  job_count="$(grep -c . "$jobs_file" || true)"
  if [ "$job_count" -lt 1 ]; then
    echo "FAIL $rel: 'jobs:' missing or no job ids declared"
    fail=1
  else
    if needs_has_cycle "$jobs_file" "$edges_file"; then
      echo "FAIL $rel: 'needs:' graph contains a cycle (or an unresolvable dep)"
      fail=1
    fi
  fi
  rm -f "$jobs_file" "$edges_file"

  if grep -q '^permissions:' "$wf" && \
     awk '/^permissions:/{f=1;next} f && /^[^ \t]/{f=0} f && /contents: read/{ok=1} END{exit !ok}' "$wf"; then
    : # top-level contents: read covers every job that does not override it
  else
    bad_jobs="$(awk '
      /^jobs:/ { injobs = 1; next }
      injobs && /^[^ \t]/ { injobs = 0 }
      injobs && /^  [A-Za-z0-9_-]+:/ {
        if (cur != "" && (perm == 0 || cr == 0)) print cur
        cur = $1; sub(/:$/, "", cur); perm = 0; cr = 0; next
      }
      injobs && cur != "" && /^ +permissions:/ { perm = 1 }
      injobs && cur != "" && /contents: read/ { cr = 1 }
      END { if (cur != "" && (perm == 0 || cr == 0)) print cur }
    ' "$wf")"
    if [ -n "$bad_jobs" ]; then
      echo "FAIL $rel: job(s) without 'permissions: contents: read':$(printf '\n  %s' $bad_jobs)"
      fail=1
    fi
  fi
done

if (( ! found )); then
  echo "FAIL: no workflow files found under .github/workflows/"
  exit 1
fi

if (( fail )); then
  echo "workflow-lint: FAIL"
  exit 1
fi
echo "workflow-lint: all checks passed"
