#!/usr/bin/env bash
# Census disposition executor. Reads pending items from census.json
# and processes them ONE AT A TIME — there is no batch mode and none may be
# added. Behavior is derived from the item's census labels (four-combination
# matrix):
#   git:true                    -> `git rm` ONLY (single-item y/N confirm;
#                                  history keeps the file recoverable);
#   git:false + npm:true        -> confirm, then edit package.json files to
#                                  stop shipping it (diff printed first);
#   git:false + npm:false +
#   removal ask on an untracked -> HARD ERROR; only --allow-untracked-rm AND
#   path                          typing back the exact full path allows rm;
#   git:false + npm:false other -> no verb: display + manual guidance only.
# Disposition paths must be literal census entry keys (exact match); a
# directory path is refused outright. Each executed (or acknowledged) item is
# marked done in census.json via an atomic rewrite.
# Usage: scripts/census-dispose.sh [--allow-untracked-rm]
set -uo pipefail

cd "$(dirname "$0")/.."

ALLOW_UNTRACKED_RM=0
for arg in "$@"; do
  case "$arg" in
    --allow-untracked-rm) ALLOW_UNTRACKED_RM=1 ;;
    -h|--help)
      sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "census-dispose: unknown option '$arg' (no batch mode exists; only --allow-untracked-rm is accepted)" >&2
      exit 1
      ;;
  esac
done

command -v node >/dev/null 2>&1 || { echo "census-dispose: node is required" >&2; exit 1; }
[ -f census.json ] || { echo "census-dispose: census.json not found at repo root" >&2; exit 1; }

# Validate + emit pending items as TSV: path, action, git, npm (exact-key rule).
PENDING="$(node -e '
const fs = require("fs");
const c = JSON.parse(fs.readFileSync("census.json", "utf8"));
const norm = (s) => (s.endsWith("/") ? s.slice(0, -1) : s);
const keys = new Set(Object.keys(c.entries || {}).map(norm));
for (const d of c.dispositions || []) {
  if (d.status === "done") continue;
  if (typeof d.path !== "string" || !keys.has(norm(d.path))) {
    console.error(`census-dispose: disposition path is not a census entry: ${d.path}`);
    process.exit(1);
  }
}
for (const d of c.dispositions || []) {
  if (d.status === "done") continue;
  const e = c.entries[Object.keys(c.entries).find((k) => norm(k) === norm(d.path))];
  console.log([d.path, String(d.action || ""), String(e.git), String(e.npm)].join("\t"));
}
' 2>&1)" || { printf '%s\n' "$PENDING" >&2; exit 1; }

mark_done() {  # $1 = path — flip its pending disposition to done (atomic)
  node -e '
const fs = require("fs");
const p = process.argv[1];
const c = JSON.parse(fs.readFileSync(p, "utf8"));
let hit = false;
for (const d of c.dispositions || []) {
  if (d.path === process.argv[2] && d.status !== "done") {
    d.status = "done";
    d.note = `${d.note || ""} [executed ${new Date().toISOString()}]`.trim();
    hit = true;
  }
}
if (!hit) { console.error(`census-dispose: pending disposition not found: ${process.argv[2]}`); process.exit(1); }
const tmp = `${p}.tmp`;
fs.writeFileSync(tmp, JSON.stringify(c, null, 2) + "\n");
fs.renameSync(tmp, p);
' census.json "$1"
}

unship_plan() {  # $1 = path — print which files-array elements would be removed
  node -e '
const fs = require("fs");
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
const target = process.argv[1];
const norm = (s) => (s.endsWith("/") ? s.slice(0, -1) : s);
const rm = (pkg.files || []).filter((e) => norm(e) === target || target.startsWith(norm(e) + "/"));
console.log(rm.length ? rm.join("\t") : "");
' "$1"
}

unship_apply() {  # $1 = path — remove covering files-array elements (atomic)
  node -e '
const fs = require("fs");
const p = "package.json";
const pkg = JSON.parse(fs.readFileSync(p, "utf8"));
const target = process.argv[1];
const norm = (s) => (s.endsWith("/") ? s.slice(0, -1) : s);
const rm = (pkg.files || []).filter((e) => norm(e) === target || target.startsWith(norm(e) + "/"));
if (!rm.length) process.exit(0);
pkg.files = pkg.files.filter((e) => !rm.includes(e));
const tmp = `${p}.tmp`;
fs.writeFileSync(tmp, JSON.stringify(pkg, null, 2) + "\n");
fs.renameSync(tmp, p);
' "$1"
}

n=0
while IFS=$'\t' read -r p action glab nlab <&3; do
  [ -z "${p:-}" ] && continue
  n=$((n + 1))
  echo "[census-dispose] item $n: $p"
  if [ "$action" != "delete" ] && [ "$action" != "archive" ] && [ "$action" != "unship" ]; then
    echo "  ERROR: unsupported action '$action' (allowed: delete | archive | unship)" >&2
    exit 1
  fi
  if [ -d "$p" ]; then
    echo "  ERROR: '$p' is a directory — dispositions accept literal file paths only (no directory prefixes)" >&2
    exit 1
  fi
  if git ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then tracked=yes; else tracked=no; fi
  echo "  action: $action   labels: git=$glab npm=$nlab   tracked: $tracked"

  if [ "$glab" = "true" ]; then
    echo "  verb: git rm -- $p (tracked file — history keeps it recoverable)"
    printf '  proceed? [y/N] '
    read -r ans
    if [ "${ans:-}" = "y" ] || [ "${ans:-}" = "Y" ]; then
      git rm -q -- "$p" || { echo "  ERROR: git rm failed" >&2; exit 1; }
      mark_done "$p" || exit 1; echo "  done: removed via git rm; disposition marked done"
    else
      echo "  skipped (stays pending)"
    fi
  elif [ "$nlab" = "true" ]; then
    UNPLAN="$(unship_plan "$p")"
    if [ -z "$UNPLAN" ]; then
      echo "  nothing to unship: no package.json files element covers $p"
      echo "  manual guidance: decide where this npm-only file belongs, then update the census labels."
      printf '  acknowledge as handled manually? [y/N] '
      read -r ans
      if [ "${ans:-}" = "y" ] || [ "${ans:-}" = "Y" ]; then mark_done "$p" || exit 1; echo "  done: acknowledged"; fi
    else
      echo "  verb: remove from package.json files (prospective diff):"
      printf '%s\n' "$UNPLAN" | while IFS= read -r el; do echo "    - \"$el\""; done
      printf '  proceed? [y/N] '
      read -r ans
      if [ "${ans:-}" = "y" ] || [ "${ans:-}" = "Y" ]; then
        unship_apply "$p" || exit 1; mark_done "$p" || exit 1; echo "  done: package.json files updated; disposition marked done"
      else
        echo "  skipped (stays pending)"
      fi
    fi
  elif [ "$tracked" != "yes" ] && { [ "$action" = "delete" ] || [ "$action" = "archive" ]; }; then
    if [ "$ALLOW_UNTRACKED_RM" = "1" ]; then
      echo "  untracked file — removal requires typing back the exact full path"
      printf '  full path: '
      read -r typed
      if [ "$typed" = "$(pwd)/$p" ]; then
        rm -f -- "$p" || { echo "  ERROR: rm failed" >&2; exit 1; }
        mark_done "$p" && echo "  done: removed after exact-path confirmation; disposition marked done"
      else
        echo "  ERROR: typed path does not match $(pwd)/$p — refusing to remove" >&2
        exit 1
      fi
    else
      echo "  HARD ERROR: '$p' is untracked (no git record) — delete is refused; re-run with --allow-untracked-rm and confirm by typing the exact full path" >&2
      exit 1
    fi
  else
    echo "  no automated verb for git:false+npm:false — manual guidance:"
    echo "    archive or delete the file by hand (it has no git history to preserve),"
    echo "    then mark this disposition done or drop the census entry."
    printf '  acknowledge as handled manually? [y/N] '
    read -r ans
    if [ "${ans:-}" = "y" ] || [ "${ans:-}" = "Y" ]; then mark_done "$p" || exit 1; echo "  done: acknowledged"; fi
  fi
done 3< <(printf '%s\n' "$PENDING")

if [ "$n" -eq 0 ]; then
  echo "census-dispose: no pending dispositions"
fi
