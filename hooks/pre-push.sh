#!/bin/sh
# GOS pre-push hook: aggregate-push discipline on refs/heads/main.
# Installed by `gos setup --commitlint` (copies this master to <toplevel>/hooks/pre-push).
# Removed by `gos setup --commitlint --teardown`.
# gos-managed: GOS hook master - local edits are overwritten by re-running gos setup.
#
# Policy: refs/heads/main is PR-only (A3 ruling 2026-10-20 — branch-protection
# parity during the private period): direct raw pushes are rejected with the
# PR path; GOS_ALLOW_MAIN_PUSH=1 is the auditable emergency escape, beneath
# which the aggregate discipline still applies (1 commit per push, no
# tree-empty, no advance-template subjects). Bootstrap pushes that CREATE
# refs/heads/main and pushes whose remote tip is unavailable locally are not
# banned. Deleting refs/heads/main is rejected outright. Non-main refs are
# never inspected.
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

  # PR-only main (A3): direct pushes rejected unless the explicit escape is set.
  if [ "${GOS_ALLOW_MAIN_PUSH:-0}" != "1" ]; then
    echo "gos pre-push: rejected — refs/heads/main is PR-only (direct pushes disabled)" >&2
    echo "PR path:" >&2
    echo "  1. git push origin HEAD:refs/heads/<branch>  (feature branches are unguarded)" >&2
    echo "  2. open a pull request into main from that branch (PR template carries Closes #N)" >&2
    echo "  3. squash-merge it — one semantic commit lands on main, CI gates the merge" >&2
    echo "emergency direct path: GOS_ALLOW_MAIN_PUSH=1 (auditable; the 1-commit aggregate discipline still applies)" >&2
    exit 1
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
