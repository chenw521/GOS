#!/bin/sh
# GOS pre-push hook: aggregate-push discipline on refs/heads/main.
# Installed by `gos setup --commitlint` (copies this master to <toplevel>/hooks/pre-push).
# Removed by `gos setup --commitlint --teardown`.
# gos-managed: GOS hook master - local edits are overwritten by re-running gos setup.
#
# Policy: a raw push that would land more than one commit on refs/heads/main,
# or land a tree-empty commit, or land an advance-template subject, is
# rejected with a hint pointing at `gos push` (the aggregation command).
# Deleting refs/heads/main is rejected outright. Non-main refs are never
# inspected.
set -u

ADVANCE_RE='^chore\(task\): advance( |$)'

reject() {
  echo "gos pre-push: rejected — $1" >&2
  echo "hint: run 'gos push' — it aggregates the atomic chain into one semantic commit on refs/heads/main" >&2
  exit 1
}

# All-zero sha (also matches the empty string, which never reaches the loop).
is_zero_sha() {
  case "$1" in
    *[!0]*) return 1 ;;
    *) return 0 ;;
  esac
}

# A commit is tree-empty when its tree is identical to its sole parent's
# tree; a root commit compares against the empty tree; merges are never
# flagged (same rule as the push-range guard in test/checks).
is_tree_empty() {
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

# stdin lines: <local ref> SP <local sha> SP <remote ref> SP <remote sha>
while read -r local_ref local_sha remote_ref remote_sha; do
  [ "$remote_ref" = "refs/heads/main" ] || continue

  if is_zero_sha "$local_sha"; then
    reject "deleting refs/heads/main is not allowed"
  fi

  if is_zero_sha "$remote_sha"; then
    echo "gos pre-push: creating refs/heads/main — push-range checks skipped" >&2
    continue
  fi

  if ! git rev-parse --quiet --verify "$remote_sha^{commit}" >/dev/null 2>&1; then
    echo "gos pre-push: remote tip $remote_sha not available locally — push-range checks skipped" >&2
    continue
  fi

  count=$(git rev-list --count "$remote_sha..$local_sha" 2>/dev/null)
  case "$count" in
    ''|*[!0-9]*)
      echo "gos pre-push: cannot count range $remote_sha..$local_sha — push-range checks skipped" >&2
      continue
      ;;
  esac

  if [ "$count" -gt 1 ]; then
    reject "$count commits would land on refs/heads/main (discipline allows 1 per push)"
  fi

  for commit in $(git rev-list --reverse "$remote_sha..$local_sha"); do
    subject=$(git log -1 --format=%s "$commit")
    if is_tree_empty "$commit"; then
      reject "tree-empty commit $(git rev-parse --short "$commit"): $subject"
    fi
    if printf '%s\n' "$subject" | grep -Eq "$ADVANCE_RE"; then
      reject "advance-template subject on $(git rev-parse --short "$commit"): $subject"
    fi
  done
done

exit 0
