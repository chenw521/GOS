#!/usr/bin/env bash
# gos-map:cmd map,_contract
# map contract texts — 17 frozen texts match `gos _contract` output key by key
# Env: GOS (CLI path), TESTBASE (sandbox base), assert helpers sourced by runner
T24_DIR=""

t24_setup() {
  T24_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t24"
  mkdir -p "$T24_DIR" && cd "$T24_DIR" || exit 1
}

t24_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T24_DIR"; }

t24_setup
echo "--- T24: map frozen contract texts (17 keys, exact) ---"

node "$GOS" _contract 2>/dev/null > t24-contract.json
assert_exit "_contract exits 0" 0 "$?"

python3 - <<'PYEOF'
import json, sys

expected = {
  "mapBanner": "regex-based self-scan, no dynamic resolution — results may be incomplete",
  "staleNote": "stale deps.json (head or worktree anchor mismatch) — cached results used (--no-refresh)",
  "probeHint": "dedicated dep tool config detected (<file>) — prefer it for precision (not guaranteed)",
  "depsTamper": "deps.json integrity check failed (self-anchor mismatch) — refusing cached map, rescan required",
  "depsParseFail": "deps.json unreadable (parse failed) — refusing cached map",
  "depsSchemaFuture": "deps.json schema_version not supported by this CLI — refusing cached map",
  "noHead": "not a git repo — deps.json unanchored (freshness unverifiable, auto-rescan on query)",
  "headUnborn": "git repo with no commits — deps.json anchored to empty tree",
  "closureUnknownPath": "closure input not in graph (<paths>) — typo, deleted, or not in scan set — refusing vacuous answer",
  "impactClosure": "impact closure: <N> diff dependents not covered by task Files (advisory, regex-based, may be incomplete)",
  "impactClean": "impact closure: 0 uncovered dependents (regex-based, may be incomplete)",
  "impactVacuous": "impact closure vacuous (0 scannable sources OR diff fully allowlisted) — NOT evidence of clean",
  "impactHintRun": "run: gos map closure <top-impact-file> --print0",
  "print0Rule": "--print0 output: NUL-separated paths only, no banners — sole legal machine consumption mode",
  "mapCwdBanner": "run from <subdir> — anchored to repo root <root>",
  "concernsBootstrap": "concerns sidecar bootstrapped this run (anchor created from current file)",
  "concernsAnchorFail": "concerns anchor mismatch — restore .gos/concerns.md from git history or .bak",
}
actual = json.load(open("t24-contract.json"))["semantic_checks"]
bad = 0
for k, v in expected.items():
    if k not in actual:
        print(f"  ✗ semantic_checks missing key: {k}"); bad += 1
    elif actual[k] != v:
        print(f"  ✗ semantic_checks[{k}] mismatch:\n    expected: {v!r}\n    actual:   {actual[k]!r}"); bad += 1
print(f"  ✓ all 17 map/concerns contract texts exact (frozen)" if bad == 0 else f"  ✗ {bad} contract text mismatch(es)")
# legacy keys must survive (Phase B texts untouched)
for legacy in ("banner", "diffHit", "lessonsAnchor", "allowlist"):
    if legacy not in actual:
        print(f"  ✗ legacy semantic_checks key lost: {legacy}"); bad += 1
sys.exit(1 if bad else 0)
PYEOF
assert_exit "17 new texts exact + legacy keys intact" 0 "$?"

t24_teardown
