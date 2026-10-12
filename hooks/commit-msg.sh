#!/bin/sh
# GOS commit-msg hook: enforce Conventional Commit messages via commitlint.
# Installed by `gos setup --commitlint` (copies this master to <toplevel>/hooks/commit-msg).
# Removed by `gos setup --commitlint --teardown`.
# gos-managed: GOS hook master - local edits are overwritten by re-running gos setup.
#
# Policy: never block a commit on tooling absence - when npx is not on PATH we
# print a skip notice and exit 0; offline network/registry npx failures fail
# open the same way (see run_commitlint). Any other commitlint failure
# propagates.
set -u

msg_file="${1:-}"

if ! command -v npx >/dev/null 2>&1; then
  echo "gos commitlint: npx not found - skipping commit message lint"
  exit 0
fi

# Resolve the GOS root from this script's own location (shipped layout:
# <gos-root>/hooks/commit-msg[.sh]); GOS_SELF_ROOT may override. In a target
# repo the same expression yields the repo root.
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
gos_root="${GOS_SELF_ROOT:-$(dirname "$script_dir")}"
repo_root=$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$(dirname "$script_dir")")

# Config resolution, in order:
# 1. the repo's own gos-seeded config (commitlint.config.yaml, seeded by
#    `gos init git`) - note commitlint's cosmiconfig default search does NOT
#    include this filename, so it must be passed explicitly;
# 2. the hook master config shipped inside a gos root (self-repo case);
# 3. commitlint default search (repo provides its own .commitlintrc* etc.).
seeded_cfg="$repo_root/commitlint.config.yaml"
master_cfg="$gos_root/templates/git/commitlint.config.yaml"

# Run commitlint and classify the outcome (D-94; review M2: stdout and
# stderr are captured SEPARATELY — commitlint echoes the commit message on
# stdout ("input: <subject>"), so a FAILING message containing a network
# token (ENOTFOUND, ETIMEDOUT, ETARGET, E404, "npm ERR! network") could
# forge the fail-open classification when both streams are captured
# combined. Network tokens are matched against STDERR ONLY; empty stderr
# with a non-zero exit stays a fail-closed validation failure). A non-zero
# npx exit whose STDERR matches a network/registry token means the tool is
# unrunnable offline: echo both captured streams and exit 0. Any other
# non-zero exit - including every commitlint validation verdict - echoes
# both streams and propagates the same code (fail-closed bias). When stream
# separation is impossible (mktemp unavailable) no fail-open classification
# is attempted at all - the exit code always propagates.
run_commitlint() {
  cm_err=$(mktemp "${TMPDIR:-/tmp}/gos-commitmsg.XXXXXX" 2>/dev/null) || cm_err=
  if [ -n "$cm_err" ]; then
    so=$(npx --yes commitlint@19 "$@" 2>"$cm_err"); rc=$?
    se=$(cat "$cm_err" 2>/dev/null || printf '')
    rm -f "$cm_err"
  else
    so=$(npx --yes commitlint@19 "$@" 2>&1); rc=$?
    se=
  fi
  if [ "$rc" -eq 0 ]; then
    [ -n "$so" ] && printf '%s\n' "$so"
    exit 0
  fi
  case "$se" in
    *ENOTFOUND*|*ETIMEDOUT*|*ETARGET*|*E404*|"npm ERR! network"*)
      [ -n "$so" ] && printf '%s\n' "$so"
      [ -n "$se" ] && printf '%s\n' "$se"
      echo "gos commitlint: npx unreachable (network/registry) - skipping commit message lint"
      exit 0
      ;;
  esac
  [ -n "$so" ] && printf '%s\n' "$so" >&2
  [ -n "$se" ] && printf '%s\n' "$se" >&2
  exit "$rc"
}

# Pinned major matches templates/git/node/ci.yml (commitlint@19).
if [ -f "$seeded_cfg" ]; then
  run_commitlint --config "$seeded_cfg" --edit "$msg_file"
fi
if [ -f "$master_cfg" ]; then
  run_commitlint --config "$master_cfg" --edit "$msg_file"
fi
run_commitlint --edit "$msg_file"
