#!/usr/bin/env bash
# ascii-filenames: repo hygiene guard — every tracked filename (each path
# segment) must be pure ASCII (bytes 0x00-0x7F). Name discipline is
# complementary to cjk-lint (content) and commitlint-charset (commit
# subjects); none of them covers names.
# Exit codes: 0 clean | 1 violations listed | 2 internal error (not a git
# repo, git failure, EMPTY track list) — an empty list can never pass
# vacuously (stale-verbs precedent).
# --selftest: scratch-repo driven proof of all four verdict paths; never
# touches the real index or worktree (red-team F3: git ls-files reads the
# index, so injecting into the real tree would require staging a violation).
# Env: ASCII_FILENAMES_ROOT overrides the repo root (used by --selftest).
set -uo pipefail
export LC_ALL=C

GOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

scan() {
  # $1 = repo root. Prints offenders (\xNN-escaped) and a summary count line;
  # exits 0/1/2 per contract.
  local root="$1"
  if ! git -C "$root" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "ascii-filenames: not a git repository: $root" >&2
    exit 2
  fi
  local out rc offenders total
  out="$(git -C "$root" ls-files -z | node -e '
    const chunks = [];
    process.stdin.on("data", (d) => chunks.push(d));
    process.stdin.on("end", () => {
      const buf = Buffer.concat(chunks);
      const files = buf.length ? buf.toString("latin1").split("\0") : [];
      const bad = files.filter(Boolean).filter((f) => /[^\x00-\x7F]/.test(f));
      const esc = (s) => s.replace(/[^\x20-\x7E]/g, (c) => "\\x" + c.charCodeAt(0).toString(16).padStart(2, "0"));
      for (const f of bad) console.log(esc(f));
      console.log("ASCII_SCAN_TOTAL=" + files.filter(Boolean).length);
      process.exitCode = bad.length ? 1 : 0;
      if (files.filter(Boolean).length === 0) process.exitCode = 2;
    });
  ')" rc=$?
  # Propagate the node child's verdict (busybox sh: rc from command subst).
  rc=$?
  total="$(printf '%s\n' "$out" | grep -o 'ASCII_SCAN_TOTAL=[0-9]*' | tail -1 | cut -d= -f2)"
  offenders="$(printf '%s\n' "$out" | grep -v 'ASCII_SCAN_TOTAL=')"
  if [ "${rc}" -eq 2 ] || [ "${total:-0}" -eq 0 ]; then
    echo "ascii-filenames: empty track list in $root — refusing vacuous pass" >&2
    exit 2
  fi
  if [ -n "$offenders" ]; then
    echo "ascii-filenames: non-ASCII tracked filename(s):"
    printf '%s\n' "$offenders" | sed 's/^/  /'
    exit 1
  fi
  echo "ascii-filenames: ${total} tracked file(s), all names pure ASCII"
  exit 0
}

selftest() {
  local tmp rc ok=0 fail=0
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  # Case 1: clean scratch repo -> 0
  mkdir -p "$tmp/clean/sub" && git -C "$tmp/clean" init -q
  printf 'x' > "$tmp/clean/ok.txt"; printf 'y' > "$tmp/clean/sub/ok2.txt"
  git -C "$tmp/clean" add -A
  if ASCII_FILENAMES_ROOT="$tmp/clean" bash "$0" >/dev/null 2>&1; then echo "  ok: clean scratch -> 0"; ok=$((ok+1)); else echo "  FAIL: clean scratch should pass"; fail=$((fail+1)); fi
  # Case 2: offender -> 1 AND named in output
  mkdir -p "$tmp/dirty" && git -C "$tmp/dirty" init -q
  printf 'x' > "$tmp/dirty/ok.txt"
  # Offender filename built from byte escapes (no literal CJK in source —
  # cjk-lint content discipline applies to this file itself).
  printf 'x' > "$tmp/dirty/$(printf '\xe4\xb8\xad\xe6\x96\x87').md"
  git -C "$tmp/dirty" add -A
  local out2 rc2
  out2="$(ASCII_FILENAMES_ROOT="$tmp/dirty" bash "$0" 2>&1)"; rc2=$?
  if [ "$rc2" -eq 1 ] && printf '%s' "$out2" | grep -q '\\xe4'; then
    echo "  ok: offender -> 1 and escaped name in output"; ok=$((ok+1))
  else
    echo "  FAIL: offender case rc=$rc2 out=$out2"; fail=$((fail+1))
  fi
  # Case 3: empty repo -> 2
  mkdir -p "$tmp/empty" && git -C "$tmp/empty" init -q
  if ASCII_FILENAMES_ROOT="$tmp/empty" bash "$0" >/dev/null 2>&1; then echo "  FAIL: empty repo should exit 2"; fail=$((fail+1)); else echo "  ok: empty repo -> 2"; ok=$((ok+1)); fi
  # Case 4: non-repo dir -> 2
  mkdir -p "$tmp/plain"
  if ASCII_FILENAMES_ROOT="$tmp/plain" bash "$0" >/dev/null 2>&1; then echo "  FAIL: non-repo should exit 2"; fail=$((fail+1)); else echo "  ok: non-repo -> 2"; ok=$((ok+1)); fi
  echo "ascii-filenames self-test: $ok/4 cases passed"
  [ "$fail" -eq 0 ] || exit 1
  exit 0
}

main() {
  local root="${ASCII_FILENAMES_ROOT:-}"
  if [ -z "$root" ]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ascii-filenames: not a git repository (cwd)" >&2; exit 2; }
  fi
  scan "$root"
}

case "${1:-}" in
  --selftest|--self-test) selftest ;;
  ""|--scan|*) [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] && { sed -n '2,12p' "$0"; exit 0; }
    main "$@" ;;
esac
