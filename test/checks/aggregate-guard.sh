#!/usr/bin/env bash
# Aggregate-push guard: enforce the one-aggregate-commit-per-push discipline
# over a push range bounded by BEFORE/AFTER shas (GitHub push event payload).
#   reject: tree-empty commits (no tree change vs sole parent),
#           advance-template subjects (chore(task): advance ...),
#           more than 1 commit in the range;
#   skip  : all checks when BEFORE is all zeros (branch creation);
#   --forced: skip ONLY the count rule (per-commit checks still apply).
# Exit codes: 0 pass or documented skip, 1 discipline violated, 2 usage error.
set -euo pipefail

ADVANCE_RE='^chore\(task\): advance( |$)'
ALL_ZERO_RE='^0+$'
ZERO_SHA=0000000000000000000000000000000000000000

usage() {
  cat >&2 <<'EOF'
usage: test/checks/aggregate-guard.sh [--forced] <before> <after>
       test/checks/aggregate-guard.sh --self-test
EOF
}

# A commit is tree-empty when its tree is identical to its sole parent's
# tree; a root commit compares against the empty tree; merges are never
# flagged (a merge may legitimately match one parent's tree).
is_tree_empty() {
  local parents tree ptree
  parents=$(git rev-list --parents -n 1 "$1")
  set -- $parents
  case "$#" in
    1) ptree=$(git hash-object -t tree /dev/null) ;;
    2) ptree=$(git rev-parse --quiet --verify "$2^{tree}") || return 1 ;;
    *) return 1 ;;
  esac
  tree=$(git rev-parse --quiet --verify "$1^{tree}")
  [ "$tree" = "$ptree" ]
}

# guard <before> <after> <forced:0|1> -> 0 pass or documented skip, 1 violation
guard() {
  local before="$1" after="$2" forced="$3"
  local count c subject bad=0

  if printf '%s\n' "$before" | grep -qE "$ALL_ZERO_RE"; then
    echo 'SKIP: all-zero BEFORE (branch creation) — push range guard not applicable'
    return 0
  fi

  for ref in "$before" "$after"; do
    if ! git rev-parse --quiet --verify "$ref^{commit}" >/dev/null 2>&1; then
      printf 'FAIL: cannot resolve sha %s in this repository\n' "$ref" >&2
      return 1
    fi
  done

  count=$(git rev-list --count "$before..$after")
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    subject=$(git log -1 --format=%s "$c")
    if is_tree_empty "$c"; then
      printf 'FAIL: tree-empty commit %s: %s\n' \
        "$(git rev-parse --short "$c")" "$subject" >&2
      bad=1
    fi
    if printf '%s\n' "$subject" | grep -qE "$ADVANCE_RE"; then
      printf 'FAIL: advance-template subject on %s: %s\n' \
        "$(git rev-parse --short "$c")" "$subject" >&2
      bad=1
    fi
  done < <(git rev-list --reverse "$before..$after")

  if [ "$count" -gt 1 ] && [ "$forced" -ne 1 ]; then
    printf 'FAIL: %s commits in push range %s..%s (discipline allows 1)\n' \
      "$count" "$before" "$after" >&2
    bad=1
  fi

  [ "$bad" -eq 0 ] || return 1
  printf 'PASS: push range %s..%s clean (%s commit(s), forced=%s)\n' \
    "$(git rev-parse --short "$before")" \
    "$(git rev-parse --short "$after")" "$count" "$forced"
}

self_test() {
  local fixture before after
  # tmp stays at script scope: the EXIT trap must still see it after return
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  fixture="$tmp/fixture"
  git init -q "$fixture"
  g() { git -C "$fixture" "$@"; }
  g config user.name 'aggregate-guard self-test'
  g config user.email 'self-test@example.invalid'
  g config commit.gpgsign false
  echo base > "$fixture/base.txt"
  g add -A
  g commit -q --no-verify -m 'chore: base'
  before=$(g rev-parse HEAD)

  # expect <wanted-exit:0|1> <label> <guard-args...>: assert guard's verdict;
  # guard uses plain git, so run it with the fixture repo as cwd (CI runs the
  # script at repo root the same way).
  expect() {
    local want="$1" label="$2" got=0 out
    shift 2
    out=$(cd "$fixture" && guard "$@" 2>&1) || got=1
    if [ "$got" -ne "$want" ]; then
      printf 'FAIL: %s (wanted exit %s, got %s)\n%s\n' \
        "$label" "$want" "$got" "$out" >&2
      exit 1
    fi
    printf 'PASS: %s\n' "$label"
  }

  # 1. tree-empty commit (created via --allow-empty) must be rejected
  g commit -q --no-verify --allow-empty -m 'chore: no changes'
  after=$(g rev-parse HEAD)
  expect 1 'tree-empty commit rejected' "$before" "$after" 0
  g reset -q --hard "$before"

  # 2. advance-template subject must be rejected (with a real tree change)
  echo change > "$fixture/x.txt"
  g add -A
  g commit -q --no-verify -m 'chore(task): advance P15'
  after=$(g rev-parse HEAD)
  expect 1 'advance-template subject rejected' "$before" "$after" 0
  g reset -q --hard "$before"

  # 3. multi-commit range must be rejected
  echo one > "$fixture/one.txt"; g add -A
  g commit -q --no-verify -m 'feat: one'
  echo two > "$fixture/two.txt"; g add -A
  g commit -q --no-verify -m 'feat: two'
  after=$(g rev-parse HEAD)
  expect 1 'multi-commit range rejected' "$before" "$after" 0
  g reset -q --hard "$before"

  # 4. single clean commit must pass
  echo real > "$fixture/real.txt"; g add -A
  g commit -q --no-verify -m 'feat: real change'
  after=$(g rev-parse HEAD)
  expect 0 'single clean commit accepted' "$before" "$after" 0
  g reset -q --hard "$before"

  # 5. all-zero BEFORE (branch creation) skips all checks
  expect 0 'all-zero BEFORE skips checks (branch creation)' "$ZERO_SHA" "$after" 0

  # 6. --forced skips only the count rule: two clean commits pass
  echo a > "$fixture/a.txt"; g add -A
  g commit -q --no-verify -m 'feat: first half'
  echo b > "$fixture/b.txt"; g add -A
  g commit -q --no-verify -m 'feat: second half'
  after=$(g rev-parse HEAD)
  expect 0 'forced push accepts multi-commit (count rule skipped)' "$before" "$after" 1

  echo 'aggregate-guard self-test: 6/6 cases passed'
}

if [ "${1:-}" = '--self-test' ]; then
  self_test
  exit 0
fi

forced=0
before=''
after=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --forced) forced=1 ;;
    -h|--help) usage; exit 0 ;;
    --*) printf 'FAIL: unknown option: %s\n' "$1" >&2; usage; exit 2 ;;
    *)
      if [ -z "$before" ]; then before="$1"
      elif [ -z "$after" ]; then after="$1"
      else
        printf 'FAIL: unexpected extra argument: %s\n' "$1" >&2
        usage
        exit 2
      fi
      ;;
  esac
  shift
done
if [ -z "$before" ] || [ -z "$after" ]; then
  printf 'FAIL: BEFORE and AFTER shas are both required\n' >&2
  usage
  exit 2
fi
guard "$before" "$after" "$forced"
