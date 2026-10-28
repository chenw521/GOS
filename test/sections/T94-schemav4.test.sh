#!/usr/bin/env bash
# gos-map:fn bin/lib/core/state.cjs#fn:migrateState bin/lib/core/state.cjs#fn:deriveRepoId
# gos-map:cmd init,status,checkpoint
# state schema (current v5) — migrateState + repo_id URL derivation + stamp survival.
# Facts asserted:
#   - STATE_SCHEMA_VERSION=5; fresh init writes schema_version 5 and drops the
#     dead `version` key; repo_id derived from origin (advisory null w/o remotes)
#   - deriveRepoId 11-form URL matrix: canonical host:port/path — host lowercase,
#     IPv6 brackets + lowercase hex, default ports 22 (scp/ssh) / 443 (https) /
#     9418 (git://), path case-preserved, trailing .git/slashes stripped,
#     embedded credentials stripped, scp `host:path` → `host:22/path`;
#     same-repo spellings → same sha256[:16]; distinct spellings → distinct ids
#   - v3 fixture (version + project_root) loads through migrateState → v5:
#     both keys deleted, repo_id present (origin) or null (no remote)
#   - read-class leaves a v3 disk state untouched; write-class persists v5
#   - raw URL never stored in state.json bytes
# - U7 ( path discipline): spec_path/plan_path stored repo-relative
#     taskPathRel relativizes repo-root absolutes, drops outside-repo
#     absolutes to null; readState normalizes legacy v4 states carrying
#     machine paths and the next write persists the cure; specPathOf/planPathOf
#     resolve stored relative values back to absolute at the consumption site
# - U8 (stamp survival): an in-flight v4 state carrying spec_gate_version
#     round-trips readState→writeState to the current schema version with the
#     stamp preserved; validateState enforces integer-when-present on the stamp
# Standalone-safe: self-provisions env when not run under test/run-sections.sh.

T94_STANDALONE=0
if [ -z "${TESTBASE:-}" ]; then
  T94_STANDALONE=1
  T94_SELFROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  export GOS="$T94_SELFROOT/bin/gos.cjs"
  export GOS_ROOT="$T94_SELFROOT"
  export TESTBASE="$(mktemp -d "$T94_SELFROOT/test-sections-base-XXXXXX")"
  export HOME="$TESTBASE/home"
  mkdir -p "$HOME"
  export GIT_AUTHOR_NAME="gos-test" GIT_AUTHOR_EMAIL="gos-test@test.invalid"
  export GIT_COMMITTER_NAME="gos-test" GIT_COMMITTER_EMAIL="gos-test@test.invalid"
  export GOS_HEADLESS=1 GOS_LANG=en
fi

T94_DIR="$TESTBASE/test-$(date +%s)-$RANDOM-t94"
mkdir -p "$T94_DIR" && cd "$T94_DIR" || exit 1

t94_teardown() {
  cd "$TESTBASE" >/dev/null 2>&1
  rm -rf "$T94_DIR"
  if [ "$T94_STANDALONE" -eq 1 ]; then rm -rf "$TESTBASE"; fi
}
trap t94_teardown EXIT

PASS=0
FAIL=0
t94_ok() { echo "  ✓ $1"; PASS=$((PASS+1)); }
t94_bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }

echo "--- T94: schema v5 — migrateState + repo_id derivation (D-12/D-18) ---"

# --- U1: module surface — STATE_SCHEMA_VERSION=5 + exports ---
U1=$(node -e '
const s = require(process.env.GOS_ROOT + "/bin/lib/core/state.cjs");
const bad = [];
  if (s.STATE_SCHEMA_VERSION !== 5) bad.push("STATE_SCHEMA_VERSION=" + s.STATE_SCHEMA_VERSION + " (want 5)");
if (typeof s.deriveRepoId !== "function") bad.push("deriveRepoId not exported");
if (typeof s.canonicalRepoUrl !== "function") bad.push("canonicalRepoUrl not exported");
if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
console.log("OK");
' 2>&1)
if [ "$U1" = "OK" ]; then t94_ok "U1 surface: STATE_SCHEMA_VERSION=5, deriveRepoId + canonicalRepoUrl exported"; else t94_bad "U1 surface: $U1"; fi

# --- U2: URL matrix — 11 forms, canonical host:port/path + id equality ---
cat > t94-urls.cjs <<'EOF'
const path = require('path');
const crypto = require('crypto');
const state = require(path.join(process.env.GOS_ROOT, 'bin/lib/core/state.cjs'));
const problems = [];
const canonical = state.canonicalRepoUrl;
const idOf = state.deriveRepoId;
// 11 spellings across three scheme families of the same repo
const FORMS = [
  // https family → github.com:443/octocat/widget
  ['https://github.com/octocat/widget.git',             'github.com:443/octocat/widget'],
  ['https://github.com/octocat/widget',                 'github.com:443/octocat/widget'],
  ['https://github.com:443/octocat/widget.git',         'github.com:443/octocat/widget'],
  ['https://user:secret@github.com/octocat/widget.git', 'github.com:443/octocat/widget'],
  ['https://GitHub.COM/octocat/widget.git/',            'github.com:443/octocat/widget'],
  // ssh/scp family → github.com:22/octocat/widget
  ['git@github.com:octocat/widget.git',                 'github.com:22/octocat/widget'],
  ['ssh://git@github.com/octocat/widget.git',           'github.com:22/octocat/widget'],
  ['ssh://git@github.com:22/octocat/widget.git',        'github.com:22/octocat/widget'],
  ['ssh://github.com:22/octocat/widget.git',            'github.com:22/octocat/widget'],
  // git:// family → github.com:9418/octocat/widget
  ['git://github.com/octocat/widget.git',               'github.com:9418/octocat/widget'],
  ['git://GitHub.com:9418/octocat/widget.git',          'github.com:9418/octocat/widget'],
];
for (const [u, want] of FORMS) {
  const got = canonical(u);
  if (got !== want) problems.push('canonical(' + u + ')=' + got + ' want ' + want);
  if (!/^[0-9a-f]{16}$/.test(String(idOf(u)))) problems.push('id(' + u + ') not sha256[:16] hex');
}
const ids = FORMS.map(([u]) => idOf(u));
const httpsId = ids[0], sshId = ids[5], gitId = ids[9];
for (let i = 1; i <= 4; i++) if (ids[i] !== httpsId) problems.push('https family split at form ' + (i + 1));
for (let i = 6; i <= 8; i++) if (ids[i] !== sshId) problems.push('ssh/scp family split at form ' + (i + 1));
if (ids[10] !== gitId) problems.push('git:// family split at form 11');
if (httpsId === sshId || sshId === gitId || httpsId === gitId) problems.push('cross-family id collision');
const wantHash = crypto.createHash('sha256').update('github.com:443/octocat/widget').digest('hex').slice(0, 16);
if (ids[0] !== wantHash) problems.push('id != sha256(canonical)[:16]');
// negative controls (outside the 11): port/case distinction + IPv6 + null inputs
const NEG = [
  ['ssh://git@github.com:2222/octocat/widget.git',  'github.com:2222/octocat/widget'],
  ['https://github.com/OctoCat/Widget.git',         'github.com:443/OctoCat/Widget'],
  ['ssh://git@[2001:DB8::A]:2222/octocat/widget.git', '[2001:db8::a]:2222/octocat/widget'],
  ['ssh://[2001:db8::a]/x.git',                     '[2001:db8::a]:22/x'],
  ['ssh://git@[2001:DB8::A]:22/x.git',              '[2001:db8::a]:22/x'],
  ['https://user:pw@[2001:DB8::A]:443/x',           '[2001:db8::a]:443/x'],
];
for (const [u, want] of NEG) {
  const got = canonical(u);
  if (got !== want) problems.push('canonical(' + u + ')=' + got + ' want ' + want);
}
if (idOf('ssh://git@github.com:2222/octocat/widget.git') === sshId) problems.push('explicit port 2222 collapsed onto :22');
if (idOf('https://github.com/OctoCat/Widget.git') === httpsId) problems.push('path case not preserved');
if (idOf('ssh://[2001:db8::a]/x.git') !== idOf('ssh://git@[2001:DB8::A]:22/x.git')) problems.push('IPv6 spellings disagree');
for (const u of ['', null, undefined, '/local/repo', 'relative/path', 'github.com']) {
  if (idOf(u) !== null) problems.push('idOf(' + JSON.stringify(u) + ') must be null (non-URL input)');
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
process.exit(problems.length ? 1 : 0);
EOF
U2=$(node t94-urls.cjs 2>&1)
if [ "$U2" = "OK" ]; then t94_ok "U2 URL matrix: 11 forms canonical + families + sha256[:16] + negatives"; else t94_bad "U2 URL matrix: $U2"; fi

# --- U3: v3 fixture migrates (module level) — with-remote repo ---
mkdir -p repo-remote && cd repo-remote && git init -q . && git commit -q --allow-empty -m root
git remote add origin git@github.com:octocat/widget.git
export T94_REMOTE_URL="git@github.com:octocat/widget.git"
cat > ../t94-migrate.cjs <<'EOF'
const path = require('path');
const state = require(path.join(process.env.GOS_ROOT, 'bin/lib/core/state.cjs'));
const problems = [];
const fixture = () => ({
  version: '0.5',
  schema_version: 3,
  level: 2,
  current_stage: 'PLAN',
  completed_stages: ['INTENT', 'THINK'],
  intent: { summary: 't94 v3 fixture', confirmed: true },
  spec_path: null, plan_path: null,
  project_root: '/old/machine/path',
  requirements: [{ id: 'R-01', text: 't94 v3 fixture', phase: null, level: 2 }],
  decisions: [], observable_truths: [], gaps: [], checkpoints: [],
});
const s = state.migrateState(fixture());
if (s.schema_version !== 5) problems.push('schema_version=' + s.schema_version + ' (want 5)');
if ('version' in s) problems.push('dead version key survived');
if ('project_root' in s) problems.push('project_root survived');
const expect = state.deriveRepoId(process.env.T94_REMOTE_URL || null);
if (s.repo_id !== expect) problems.push('repo_id=' + s.repo_id + ' want ' + expect);
if (process.env.T94_REMOTE_URL && s.repo_id === null) problems.push('repo_id null while origin remote present');
// idempotent re-migration
const s2 = state.migrateState(s);
if (s2.schema_version !== 5 || s2.repo_id !== expect) problems.push('re-migration not idempotent');
if ('version' in s2 || 'project_root' in s2) problems.push('re-migration resurrected dropped keys');
// legacy (pre-schema) state migrates straight to v4
const l = fixture(); delete l.schema_version;
const s3 = state.migrateState(l);
if (s3.schema_version !== 5) problems.push('legacy → v' + s3.schema_version);
if (s3.repo_id !== expect) problems.push('legacy repo_id=' + s3.repo_id);
// v2→v3 semantics ride through: arrays stay arrays
if (!Array.isArray(s3.decisions) || !Array.isArray(s3.gaps)) problems.push('array normalization lost');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
process.exit(problems.length ? 1 : 0);
EOF
U3=$(node ../t94-migrate.cjs 2>&1)
if printf '%s\n' "$U3" | tail -n 1 | grep -qx 'OK' && ! printf '%s' "$U3" | grep -q 'BAD'; then
  t94_ok "U3 v3 fixture migrates: version/project_root dropped, repo_id derived, idempotent, legacy→5"; else t94_bad "U3 migration: $U3"
fi

# --- U4: no-remote repo — repo_id advisory null
mkdir -p ../repo-bare && cd ../repo-bare && git init -q . && git commit -q --allow-empty -m root
unset T94_REMOTE_URL
U4=$(node ../t94-migrate.cjs 2>&1)
if printf '%s\n' "$U4" | tail -n 1 | grep -qx 'OK' && ! printf '%s' "$U4" | grep -q 'BAD'; then
  t94_ok "U4 no-remote repo: repo_id advisory null, keys still dropped"; else t94_bad "U4 no-remote: $U4"
fi

# --- U5: E2E disk flow — v3 fixture on disk, read vs write class ---
cd "$T94_DIR/repo-remote"
mkdir -p .gos
export T94_REMOTE_URL="git@github.com:octocat/widget.git"
python3 - <<'PYEOF'
import json
state = {
  "version": "0.5", "schema_version": 3, "level": 2,
  "current_stage": "PLAN", "completed_stages": ["INTENT", "THINK"],
  "intent": {"summary": "t94 v3 fixture", "confirmed": True},
  "spec_path": None, "plan_path": None, "project_root": "/old/machine/path",
  "requirements": [{"id": "R-01", "text": "t94 v3 fixture", "phase": None, "level": 2}],
  "decisions": [], "observable_truths": [], "gaps": [], "checkpoints": []
}
json.dump(state, open('.gos/state.json', 'w'), indent=2)
PYEOF
set +e
node "$GOS" status > t94-status.txt 2>&1; SRC=$?
READK=$(python3 -c "
import json; s = json.load(open('.gos/state.json'))
print('%s|%s|%s' % (s.get('schema_version'), 'version' in s, 'project_root' in s))")
node "$GOS" checkpoint save --stage PLAN --unit t94 --done m > t94-cp.txt 2>&1; CPRC=$?
cat > ../t94-disk.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const state = require(path.join(process.env.GOS_ROOT, 'bin/lib/core/state.cjs'));
const problems = [];
const s = JSON.parse(fs.readFileSync('.gos/state.json', 'utf8'));
if (s.schema_version !== 5) problems.push('disk schema_version=' + s.schema_version);
if ('version' in s) problems.push('dead version key on disk');
if ('project_root' in s) problems.push('project_root on disk');
const expect = state.deriveRepoId(process.env.T94_REMOTE_URL);
if (s.repo_id !== expect) problems.push('disk repo_id=' + s.repo_id + ' want ' + expect);
const raw = fs.readFileSync('.gos/state.json', 'utf8');
if (raw.includes('octocat') || raw.includes('github.com') || raw.includes('widget')) {
  problems.push('raw URL fragments stored in state.json');
}
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
process.exit(problems.length ? 1 : 0);
EOF
DISK=$(node ../t94-disk.cjs 2>&1)
if [ "$SRC" -eq 0 ] && [ "$READK" = "3|True|True" ]; then
  t94_ok "U5a read-class leaves v3 disk untouched (no rogue write)"; else t94_bad "U5a read-class: rc=$SRC disk=$READK"
fi
if [ "$CPRC" -eq 0 ] && [ "$DISK" = "OK" ]; then
  t94_ok "U5b write-class persists v5: keys dropped, repo_id hashed, raw URL absent"; else t94_bad "U5b write-class: rc=$CPRC disk=$DISK"
fi

# --- U6: fresh init writes schema v5 with repo_id, no dead version key ---
cd "$T94_DIR" && mkdir -p repo-fresh && cd repo-fresh
git init -q . && git commit -q --allow-empty -m root
git remote add origin https://github.com/octocat/widget.git
node "$GOS" init 1 "t94 fresh v5" >/dev/null 2>&1; IRC=$?
cat > ../t94-fresh.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const state = require(path.join(process.env.GOS_ROOT, 'bin/lib/core/state.cjs'));
const problems = [];
const s = JSON.parse(fs.readFileSync('.gos/state.json', 'utf8'));
if (s.schema_version !== 5) problems.push('fresh schema_version=' + s.schema_version);
if ('version' in s) problems.push('dead version key in fresh state');
const expect = state.deriveRepoId('https://github.com/octocat/widget.git');
if (s.repo_id !== expect) problems.push('fresh repo_id=' + s.repo_id + ' want ' + expect);
const raw = fs.readFileSync('.gos/state.json', 'utf8');
if (raw.includes('octocat') || raw.includes('github.com')) problems.push('raw URL fragments in fresh state.json');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
process.exit(problems.length ? 1 : 0);
EOF
FRESH=$(node ../t94-fresh.cjs 2>&1)
if [ "$IRC" -eq 0 ] && [ "$FRESH" = "OK" ]; then
  t94_ok "U6 fresh init: schema 5, no version key, repo_id derived, URL never stored"; else t94_bad "U6 fresh init: rc=$IRC fresh=$FRESH"
fi

# --- U7: path discipline — task path fields are repo-relative on disk
cd "$T94_DIR" && mkdir -p repo-paths && cd repo-paths
git init -q . && git commit -q --allow-empty -m root
git remote add origin git@github.com:octocat/widget.git
mkdir -p .gos
cat > ../t94-paths.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const state = require(path.join(process.env.GOS_ROOT, 'bin/lib/core/state.cjs'));
const problems = [];
const root = process.cwd();
// module semantics
if (state.taskPathRel('.gos/task/x/spec.md') !== '.gos/task/x/spec.md') problems.push('relative passthrough broken');
if (state.taskPathRel(path.join(root, '.gos/task/x/spec.md')) !== '.gos/task/x/spec.md') problems.push('repo-root absolute not relativized');
if (state.taskPathRel('/elsewhere/spec.md') !== null) problems.push('outside-repo absolute not dropped');
const n = state.normalizeTaskPaths({ spec_path: path.join(root, '.gos/task/y/plan.md'), plan_path: '/other/machine/plan.md' });
if (n.spec_path !== '.gos/task/y/plan.md') problems.push('normalizeTaskPaths spec_path=' + n.spec_path);
if (n.plan_path !== null) problems.push('normalizeTaskPaths outside-repo plan_path not nulled');
const resolved = state.specPathOf({ spec_path: '.gos/task/x/spec.md' });
if (resolved !== path.join(root, '.gos/task/x/spec.md')) problems.push('specPathOf relative resolution=' + resolved);
// disk cure: a v4 state carrying machine paths → write-class persists the cure
const disk = {
  schema_version: 4, level: 2, repo_id: state.deriveRepoId('git@github.com:octocat/widget.git'),
  current_stage: 'PLAN', completed_stages: ['INTENT', 'THINK'],
  intent: { summary: 't94 path cure', confirmed: true },
  spec_path: path.join(root, '.gos/task/p7/spec.md'), plan_path: '/old/machine/plan.md',
  requirements: [{ id: 'R-01', text: 't94 path cure', phase: null, level: 2 }],
  decisions: [], observable_truths: [], gaps: [], checkpoints: [],
};
fs.mkdirSync(path.join(root, '.gos/task/p7'), { recursive: true });
fs.writeFileSync(path.join(root, '.gos/state.json'), JSON.stringify(disk, null, 2));
const s = state.readState();
if (s.spec_path !== '.gos/task/p7/spec.md') problems.push('readState in-memory cure spec_path=' + s.spec_path);
if (s.plan_path !== null) problems.push('readState in-memory cure plan_path=' + s.plan_path);
state.writeState(s);
const after = JSON.parse(fs.readFileSync(path.join(root, '.gos/state.json'), 'utf8'));
if (after.spec_path !== '.gos/task/p7/spec.md') problems.push('disk cure spec_path=' + after.spec_path);
if (after.plan_path !== null) problems.push('disk cure plan_path=' + after.plan_path);
const raw = fs.readFileSync(path.join(root, '.gos/state.json'), 'utf8');
if (raw.includes(root) || raw.includes('/old/machine')) problems.push('machine paths persisted in tracked state bytes');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
process.exit(problems.length ? 1 : 0);
EOF
U7=$(node ../t94-paths.cjs 2>&1)
if [ "$U7" = "OK" ]; then
  t94_ok "U7 D-12 path discipline: repo-relative storage, outside-repo → null, v4 cure persisted, resolvers absolute"; else t94_bad "U7 path discipline: $U7"
fi
# fresh init stores relative paths from birth (no absolute ever hits disk)
cd "$T94_DIR" && mkdir -p repo-relinit && cd repo-relinit
git init -q . && git commit -q --allow-empty -m root
node "$GOS" init 1 "t94 rel init" >/dev/null 2>&1; IRC2=$?
RELINIT=$(python3 -c "
import json; s = json.load(open('.gos/state.json'))
import os
sp, pp = s.get('spec_path') or '', s.get('plan_path') or ''
print('OK' if not sp.startswith('/') and not pp.startswith('/') and 'task/' in sp else 'BAD %s|%s' % (sp, pp))")
if [ "$IRC2" -eq 0 ] && [ "$RELINIT" = "OK" ]; then
  t94_ok "U7b fresh init pins spec/plan repo-relative from birth"; else t94_bad "U7b fresh init: rc=$IRC2 rel=$RELINIT"
fi

# --- U8: in-flight v4 + stamp survival — v4→v5 round-trip keeps spec_gate_version;
# validateState enforces integer-when-present on the stamp
cd "$T94_DIR" && mkdir -p repo-stamp && cd repo-stamp
git init -q . && git commit -q --allow-empty -m root
git remote add origin git@github.com:octocat/widget.git
mkdir -p .gos
cat > ../t94-stamp.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const state = require(path.join(process.env.GOS_ROOT, 'bin/lib/core/state.cjs'));
const problems = [];
const root = process.cwd();
// disk: in-flight v4 state carrying a stamp — the round-trip migrates to the
// current schema version and preserves the stamp
const disk = {
  schema_version: 4, spec_gate_version: 2, level: 2,
  repo_id: state.deriveRepoId('git@github.com:octocat/widget.git'),
  current_stage: 'PLAN', completed_stages: ['INTENT', 'THINK'],
  intent: { summary: 't94 stamp survival', confirmed: true },
  spec_path: null, plan_path: null,
  requirements: [{ id: 'R-01', text: 't94 stamp survival', phase: null, level: 2 }],
  decisions: [], observable_truths: [], gaps: [], checkpoints: [],
};
fs.writeFileSync(path.join(root, '.gos/state.json'), JSON.stringify(disk, null, 2));
const s = state.readState();
state.writeState(s);
const after = JSON.parse(fs.readFileSync(path.join(root, '.gos/state.json'), 'utf8'));
if (after.schema_version !== 5) problems.push('round-trip schema_version=' + after.schema_version + ' (want 5)');
if (after.spec_gate_version !== 2) problems.push('round-trip spec_gate_version=' + after.spec_gate_version + ' (want 2 preserved)');
// validateState type gate: integer required when present (range is gate-side)
const base = { schema_version: 5, decisions: [], requirements: [] };
if (state.validateState({ ...base, spec_gate_version: '3' }).length === 0) problems.push('string stamp accepted');
if (state.validateState({ ...base, spec_gate_version: 1.5 }).length === 0) problems.push('float stamp accepted');
if (state.validateState({ ...base }).length !== 0) problems.push('absent stamp rejected');
if (state.validateState({ ...base, spec_gate_version: 3 }).length !== 0) problems.push('integer stamp rejected');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
process.exit(problems.length ? 1 : 0);
EOF
U8=$(node ../t94-stamp.cjs 2>&1)
if printf '%s\n' "$U8" | tail -n 1 | grep -qx 'OK' && ! printf '%s' "$U8" | grep -q 'BAD'; then
  t94_ok "U8 stamp survival: in-flight v4+stamp round-trips to v5, spec_gate_version integer-when-present"; else t94_bad "U8 stamp survival: $U8"
fi

echo "--- T94 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
