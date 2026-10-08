#!/bin/sh
# GOS commit-msg hook: enforce Conventional Commit messages via commitlint.
# Installed by `gos setup --commitlint` (copies this master to <toplevel>/hooks/commit-msg).
# Removed by `gos setup --commitlint --teardown`.
#
# Policy: never block a commit on tooling absence - when npx is not on PATH we
# print a skip notice and exit 0. Any other commitlint failure propagates.
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

# Pinned major matches templates/git/node/ci.yml (commitlint@19).
if [ -f "$seeded_cfg" ]; then
  exec npx --yes commitlint@19 --config "$seeded_cfg" --edit "$msg_file"
fi
if [ -f "$master_cfg" ]; then
  exec npx --yes commitlint@19 --config "$master_cfg" --edit "$msg_file"
fi
exec npx --yes commitlint@19 --edit "$msg_file"
