#!/usr/bin/env bash
# Pinned family-coverage diff for G0b — classifies the extracted literal set
# against the six families + F-unknown exactly as enumerated in spec.md D2.
# Usage: bash .gos/task/7f6b73bf/g0b-diff.sh
# Exit 0 = every literal matches an exact member or declared wildcard;
# exit 1 = unmatched literals exist (pre-flight blocked until the family
# table is amended and this script's tables are updated to match).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

F_EXT="external-mutation advance-state-mismatch orphan-pending-unrecoverable dispatch-table-drift prompt-template-drift pin-tampered"
F_CONTRACT="completion-unattributable post-wave-unreadable post-crash-evidence wave-held advance-check-failed"
F_HELD="delegation-held delivery-held red-run subject-lint ci-watch-timeout no-disposition ratify-refused redteam-round-failed"
F_INFRA="compose-failed compose-refused launch-failed spawn-register-failed grant-manifest-failed refs-unreadable git-failed state-corrupt state-unreadable breaker-unavailable budget-write-failed budget-read-failed no-head dispatch-table-unavailable dispatch-table-unreadable work-branch-failed build-entry-refused worker-plan-unresolved"
F_USAGE="no-task mode-off marker-active detached-head wrong-branch unknown-profile stage-invalid"
F_TRIP="breaker-tripped"
# User ruling 2026-11-04: literals below are DECLARED F-unknown members —
# any pause carrying one follows the F-unknown action only (no resume, no
# abort, attribution line, surface to user). Enumerated in spec.md D2a G0b.
F_UNKNOWN_DECLARED="absent approvals-baseline-missing approvals-diffusion branch-required ci-status-failed ci-status-required claimed-not-verified claim-write-failed config-unreadable corrupt-baseline cross-host drift gh-auth gh-no-ci git-dir-unreadable hash-mismatch hooks-dir-unresolvable loop-module-unavailable merge-failed mutex-create-failed network-store no-baseline no-data-home no-entry no-lock no-origin no-store not-a-dir not-github-remote not-owner outside-store-root pin-unavailable race rejected remote-head-unreadable remove-failed stage-mismatch stamp-conflict stamp-failed stamp-missing status-unreadable store-busy subject-required unknown-signal unparsable unreadable unwritable use-cap-over-ceiling wave-record-conflict write-failed"

in_list() {
  local lit="$1"; shift
  local m
  for m in "$@"; do [ "$lit" = "$m" ] && return 0; done
  return 1
}

litfile=$(mktemp)
unmatched=$(mktemp)
trap 'rm -f "$litfile" "$unmatched"' EXIT

bash .gos/task/7f6b73bf/g0b-extract.sh > "$litfile"

total=0; matched=0
while IFS= read -r lit; do
  total=$((total+1))
  fam=""
  case "$lit" in
    host-*) fam=F-infra ;;
    leg-*)  fam=F-infra ;;
    invalid-*) fam=F-usage ;;
  esac
  if [ -z "$fam" ] && in_list "$lit" $F_EXT;      then fam=F-ext;      fi
  if [ -z "$fam" ] && in_list "$lit" $F_CONTRACT; then fam=F-contract; fi
  if [ -z "$fam" ] && in_list "$lit" $F_HELD;     then fam=F-held;     fi
  if [ -z "$fam" ] && in_list "$lit" $F_INFRA;    then fam=F-infra;    fi
  if [ -z "$fam" ] && in_list "$lit" $F_USAGE;    then fam=F-usage;    fi
  if [ -z "$fam" ] && in_list "$lit" $F_TRIP;     then fam=F-trip;     fi
  if [ -z "$fam" ] && in_list "$lit" $F_UNKNOWN_DECLARED; then fam=F-unknown; fi
  if [ -n "$fam" ]; then matched=$((matched+1)); else echo "$lit" >> "$unmatched"; fi
done < "$litfile"

echo "G0b diff: total=$total matched=$matched unmatched=$((total-matched))"
if [ "$total" -ne "$matched" ]; then
  echo "--- unmatched literals (match no exact member, no declared wildcard) ---"
  cat "$unmatched"
  exit 1
fi
echo "G0b: PASS"
