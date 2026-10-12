#!/usr/bin/env bash
# gos-map:fn bin/lib/ops/brownfield-probe.cjs#fn:classifyHooksPath,bin/lib/ops/brownfield-probe.cjs#fn:hookOwnership,bin/lib/ops/brownfield-probe.cjs#fn:detectCommitlintConfigs,bin/lib/ops/brownfield-probe.cjs#fn:preflight
# T79: brownfield probe module (T4, pure classification — D-94/D-96/R-01).
# Four read-only classifiers driven through a node driver against sandboxes:
# (1) classifyHooksPath — core.hooksPath unset/empty (= unset, empty is
#     normalized BEFORE comparison), 'hooks' literal or absolute <top>/hooks
#     (= gos_hooks_dir, resolved via path.resolve), anything else foreign;
# (2) hookOwnership — byte-identical -> gos_bytes; '# gos-managed' line with
#     differing bytes -> gos_marker; historical provenance line ('# GOS
#     commit-msg hook:' / '# GOS pre-push hook:') without marker ->
#     gos_grandfather; divergent -> user; missing file -> 'missing'
#     (documented caller-handled state, never asserted as 'user'); review m10:
#     provenance lines match only within the FIRST 3 lines (header zone) and
#     only the hook's OWN kind (cross-kind / below-zone lines -> user);
# (3) detectCommitlintConfigs — commitlint's real resolution set via the
#     setup.cjs COMMITLINT_* consts (rc family + commitlint.config family +
#     package.json 'commitlint' key), per-candidate statSync following
#     filesystem case behavior (.COMMITLINTRC.YML NOT detected on a
#     case-sensitive fs), repo-root scope only;
# (4) preflight — per-path {ok, reason}; every refusal reason asserted
#     byte-equal against the frozen command_contracts tokens imported from
#     core (import, not grep); review M1 — a symlink component resolving
#     outside realpath(top) -> 'symlink escape' (inside-repo symlinks stay
#     permitted).
# Env: GOS (CLI path), GOS_ROOT, TESTBASE (sandbox base), assert helpers sourced by runner
T79_DIR=""

t79_setup() {
  T79_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t79"
  mkdir -p "$T79_DIR" || exit 1
  cd "$T79_DIR" || exit 1
  cat > "$T79_DIR/probe.cjs" <<'PB'
// T79 probe driver — one probe op per argv; plain string for string results,
// JSON for structured ones.
const p = require(process.env.GOS_ROOT + '/bin/lib/ops/brownfield-probe.cjs');
const a = (i) => process.argv[i];
let out;
switch (a(2)) {
  case 'classify': out = p.classifyHooksPath(a(3)); break;
  case 'own': out = p.hookOwnership(a(3), a(4)); break;
  case 'detect': out = p.detectCommitlintConfigs(a(3)); break;
  case 'preflight': out = p.preflight(a(3), JSON.parse(a(4))); break;
  default: console.error('unknown probe op'); process.exit(2);
}
console.log(typeof out === 'string' ? out : JSON.stringify(out));
PB
}

t79_repo() {  # fresh git repo at $T79_DIR/<name> (no commits needed — probes are read-only)
  mkdir -p "$T79_DIR/$1"
  git init -q -b main "$T79_DIR/$1" || exit 1
}

t79_teardown() { cd "$TESTBASE" >/dev/null 2>&1; rm -rf "$T79_DIR"; }

t79_setup
echo "--- T79: brownfield probe (pure classification) ---"
CM_MASTER="$GOS_ROOT/hooks/commit-msg.sh"
PP_MASTER="$GOS_ROOT/hooks/pre-push.sh"

# --- T79.1: classifyHooksPath ---
t79_repo w1
assert_eq "1a no core.hooksPath -> unset" "unset" "$(node "$T79_DIR/probe.cjs" classify "$T79_DIR/w1")"
git -C "$T79_DIR/w1" config core.hooksPath ""
assert_eq "1b set-to-empty-string normalizes to unset" "unset" "$(node "$T79_DIR/probe.cjs" classify "$T79_DIR/w1")"
git -C "$T79_DIR/w1" config core.hooksPath hooks
assert_eq "1c 'hooks' literal -> gos_hooks_dir" "gos_hooks_dir" "$(node "$T79_DIR/probe.cjs" classify "$T79_DIR/w1")"
git -C "$T79_DIR/w1" config core.hooksPath "$T79_DIR/w1/hooks"
assert_eq "1d absolute <top>/hooks -> gos_hooks_dir" "gos_hooks_dir" "$(node "$T79_DIR/probe.cjs" classify "$T79_DIR/w1")"
git -C "$T79_DIR/w1" config core.hooksPath .husky
assert_eq "1e '.husky' -> foreign" "foreign" "$(node "$T79_DIR/probe.cjs" classify "$T79_DIR/w1")"
git -C "$T79_DIR/w1" config core.hooksPath "$T79_DIR/w1/.husky"
assert_eq "1f absolute foreign dir -> foreign" "foreign" "$(node "$T79_DIR/probe.cjs" classify "$T79_DIR/w1")"

# --- T79.2: hookOwnership ---
mkdir -p "$T79_DIR/own"
cp "$CM_MASTER" "$T79_DIR/own/bytes.sh"
assert_eq "2a byte-identical copy of master -> gos_bytes" "gos_bytes" "$(node "$T79_DIR/probe.cjs" own "$T79_DIR/own/bytes.sh" "$CM_MASTER")"
cp "$CM_MASTER" "$T79_DIR/own/marker.sh"
printf '# local customization appended after install\n' >> "$T79_DIR/own/marker.sh"
assert_eq "2b gos-managed marker + differing bytes -> gos_marker" "gos_marker" "$(node "$T79_DIR/probe.cjs" own "$T79_DIR/own/marker.sh" "$CM_MASTER")"
printf '#!/bin/sh\n# GOS commit-msg hook: enforce Conventional Commit messages via commitlint.\n# local guard from before gos-managed markers existed\necho custom\n' > "$T79_DIR/own/grandfather-cm.sh"
assert_eq "2c commit-msg provenance line, no marker -> gos_grandfather" "gos_grandfather" "$(node "$T79_DIR/probe.cjs" own "$T79_DIR/own/grandfather-cm.sh" "$CM_MASTER")"
printf '#!/bin/sh\n# GOS pre-push hook: aggregate-push discipline on refs/heads/main.\n# local guard predating markers\necho custom\n' > "$T79_DIR/own/grandfather-pp.sh"
assert_eq "2d pre-push provenance line, no marker -> gos_grandfather" "gos_grandfather" "$(node "$T79_DIR/probe.cjs" own "$T79_DIR/own/grandfather-pp.sh" "$PP_MASTER")"
printf '#!/bin/sh\necho user hook\n' > "$T79_DIR/own/user.sh"
assert_eq "2e divergent user file -> user" "user" "$(node "$T79_DIR/probe.cjs" own "$T79_DIR/own/user.sh" "$CM_MASTER")"
assert_eq "2f missing file -> missing (caller decides, never asserted 'user')" "missing" "$(node "$T79_DIR/probe.cjs" own "$T79_DIR/own/nope.sh" "$CM_MASTER")"
# review m10: lineage scoping — cross-kind provenance lines and provenance
# lines below the 3-line header zone are NOT lineage evidence -> user
printf '#!/bin/sh\n# GOS commit-msg hook: enforce Conventional Commit messages via commitlint.\necho drifted\n' > "$T79_DIR/own/cross-kind.sh"
assert_eq "2g cross-kind provenance (commit-msg line, pre-push master) ignored -> user" "user" "$(node "$T79_DIR/probe.cjs" own "$T79_DIR/own/cross-kind.sh" "$PP_MASTER")"
printf '#!/bin/sh\n# line one\n# line two\n# line three\n# GOS commit-msg hook: provenance below the header zone\necho custom\n' > "$T79_DIR/own/deep-provenance.sh"
assert_eq "2h provenance line past the 3-line header zone -> user" "user" "$(node "$T79_DIR/probe.cjs" own "$T79_DIR/own/deep-provenance.sh" "$CM_MASTER")"

# --- T79.3: detectCommitlintConfigs ---
t79_repo d1
printf '{}\n' > "$T79_DIR/d1/.commitlintrc.json"
assert_eq "3a .commitlintrc.json detected" '[".commitlintrc.json"]' "$(node "$T79_DIR/probe.cjs" detect "$T79_DIR/d1")"
t79_repo d2
printf 'module.exports = { extends: ["@commitlint/config-conventional"] };\n' > "$T79_DIR/d2/commitlint.config.js"
assert_eq "3b commitlint.config.js detected" '["commitlint.config.js"]' "$(node "$T79_DIR/probe.cjs" detect "$T79_DIR/d2")"
t79_repo d3
printf '{"name":"x","commitlint":{"extends":["@commitlint/config-conventional"]}}\n' > "$T79_DIR/d3/package.json"
assert_eq "3c package.json commitlint key detected" '["package.json"]' "$(node "$T79_DIR/probe.cjs" detect "$T79_DIR/d3")"
t79_repo d4
printf '{"name":"x"}\n' > "$T79_DIR/d4/package.json"
assert_eq "3d package.json without commitlint key -> empty" "[]" "$(node "$T79_DIR/probe.cjs" detect "$T79_DIR/d4")"
t79_repo d5
mkdir -p "$T79_DIR/d5/sub"
printf '{}\n' > "$T79_DIR/d5/sub/.commitlintrc.json"
assert_eq "3e root scope only (nested config ignored) -> empty" "[]" "$(node "$T79_DIR/probe.cjs" detect "$T79_DIR/d5")"
t79_repo d6
printf '{}\n' > "$T79_DIR/d6/.COMMITLINTRC.YML"
assert_eq "3f uppercase .COMMITLINTRC.YML NOT detected (case-sensitive fs)" "[]" "$(node "$T79_DIR/probe.cjs" detect "$T79_DIR/d6")"

# --- T79.4: preflight (reasons byte-equal to the frozen contract tokens) ---
t79_repo p1
assert_eq "4a clean paths -> ok:true" '{"hooks":{"ok":true},".gos":{"ok":true}}' "$(node "$T79_DIR/probe.cjs" preflight "$T79_DIR/p1" '["hooks",".gos"]')"
t79_repo p2
printf 'i am a plain file, not a directory\n' > "$T79_DIR/p2/hooks"
EXP_OCC=$(node -e 'const r=require(process.env.GOS_ROOT+"/bin/lib/core/index.cjs").CONTRACTS.command_contracts.brownfieldPreflightReasons.split(" | ");console.log(JSON.stringify({hooks:{ok:false,reason:r[0]}}))')
assert_eq "4b hooks occupied by plain file -> frozen occupied token" "$EXP_OCC" "$(node "$T79_DIR/probe.cjs" preflight "$T79_DIR/p2" '["hooks"]')"
t79_repo p3
printf 'not a dir\n' > "$T79_DIR/p3/.gos"
EXP_GOS=$(node -e 'const r=require(process.env.GOS_ROOT+"/bin/lib/core/index.cjs").CONTRACTS.command_contracts.brownfieldPreflightReasons.split(" | ");console.log(JSON.stringify({".gos":{ok:false,reason:r[0]}}))')
assert_eq "4c .gos occupied by plain file -> same occupied class" "$EXP_GOS" "$(node "$T79_DIR/probe.cjs" preflight "$T79_DIR/p3" '[".gos"]')"
t79_repo p4
ln -s "$T79_DIR/p4/gone-missing" "$T79_DIR/p4/hooks"
EXP_DAN=$(node -e 'const r=require(process.env.GOS_ROOT+"/bin/lib/core/index.cjs").CONTRACTS.command_contracts.brownfieldPreflightReasons.split(" | ");console.log(JSON.stringify({hooks:{ok:false,reason:r[1]}}))')
assert_eq "4d dangling symlink -> frozen dangling token" "$EXP_DAN" "$(node "$T79_DIR/probe.cjs" preflight "$T79_DIR/p4" '["hooks"]')"
if [ "$(id -u)" -eq 0 ]; then
  echo "  ○ noted: running as root — chmod 555 cannot make a dir unwritable (spec-sanctioned skip, cf. T77)"
else
  t79_repo p5
  mkdir -p "$T79_DIR/p5/locked"
  chmod 555 "$T79_DIR/p5/locked"
  EXP_UNW=$(node -e 'const r=require(process.env.GOS_ROOT+"/bin/lib/core/index.cjs").CONTRACTS.command_contracts.brownfieldPreflightReasons.split(" | ");console.log(JSON.stringify({"locked/hooks":{ok:false,reason:r[2]}}))')
  assert_eq "4e unwritable ancestor dir -> frozen unwritable token" "$EXP_UNW" "$(node "$T79_DIR/probe.cjs" preflight "$T79_DIR/p5" '["locked/hooks"]')"
  chmod 755 "$T79_DIR/p5/locked"
fi
t79_repo p6
mkdir -p "$T79_DIR/p6/realhooks"
ln -s "$T79_DIR/p6/realhooks" "$T79_DIR/p6/hooks"
assert_eq "4f symlink to a real directory stays clean (only dangling ones refuse)" '{"hooks":{"ok":true}}' "$(node "$T79_DIR/probe.cjs" preflight "$T79_DIR/p6" '["hooks"]')"
# review M1: a symlink component resolving OUTSIDE realpath(top) is a
# directory-escape channel for later writes -> blocked with the frozen
# 'symlink escape' token; symlinks resolving INSIDE stay permitted (4f pin)
t79_repo p7
mkdir -p "$T79_DIR/outside-p7"
ln -s "$T79_DIR/outside-p7" "$T79_DIR/p7/hooks"
EXP_ESC=$(node -e 'const r=require(process.env.GOS_ROOT+"/bin/lib/core/index.cjs").CONTRACTS.command_contracts.brownfieldPreflightReasons.split(" | ");console.log(JSON.stringify({hooks:{ok:false,reason:r[3]}}))')
assert_eq "4g symlink to an OUTSIDE directory -> frozen symlink-escape token" "$EXP_ESC" "$(node "$T79_DIR/probe.cjs" preflight "$T79_DIR/p7" '["hooks"]')"
t79_repo p8
mkdir -p "$T79_DIR/outside-p8"
ln -s "$T79_DIR/outside-p8" "$T79_DIR/p8/.gos"
EXP_ESC2=$(node -e 'const r=require(process.env.GOS_ROOT+"/bin/lib/core/index.cjs").CONTRACTS.command_contracts.brownfieldPreflightReasons.split(" | ");console.log(JSON.stringify({".gos/gates.json":{ok:false,reason:r[3]}}))')
assert_eq "4h escape via an ancestor component (.gos symlink outside) blocks deep paths" "$EXP_ESC2" "$(node "$T79_DIR/probe.cjs" preflight "$T79_DIR/p8" '[".gos/gates.json"]')"

t79_teardown
echo "--- T79 done ---"
