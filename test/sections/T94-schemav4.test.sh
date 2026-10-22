#!/usr/bin/env bash
# gos-map:fn bin/lib/core/state.cjs#fn:migrateState bin/lib/core/state.cjs#fn:deriveRepoId
# gos-map:cmd init,status,checkpoint
# T94: schema v4 (D-12, D-18) — migrateState v3→v4 + repo_id URL derivation.
# Facts asserted:
#   - STATE_SCHEMA_VERSION=4; fresh init writes schema_version 4 and drops the
#     dead `version` key; repo_id derived from origin (advisory null w/o remotes)
#   - deriveRepoId 11-form URL matrix: canonical host:port/path — host lowercase,
#     IPv6 brackets + lowercase hex, default ports 22 (scp/ssh) / 443 (https) /
#     9418 (git://), path case-preserved, trailing .git/slashes stripped,
#     embedded credentials stripped, scp `host:path` → `host:22/path`;
#     same-repo spellings → same sha256[:16]; distinct spellings → distinct ids
#   - v3 fixture (version + project_root) loads through migrateState → v4:
#     both keys deleted, repo_id present (origin) or null (no remote)
#   - read-class leaves a v3 disk state untouched; write-class persists v4
#   - raw URL never stored in state.json bytes
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

echo "--- T94: schema v4 — migrateState + repo_id derivation (D-12/D-18) ---"

# --- U1: module surface — STATE_SCHEMA_VERSION=4 + exports ---
U1=$(node -e '
const s = require(process.env.GOS_ROOT + "/bin/lib/core/state.cjs");
const bad = [];
if (s.STATE_SCHEMA_VERSION !== 4) bad.push("STATE_SCHEMA_VERSION=" + s.STATE_SCHEMA_VERSION + " (want 4)");
if (typeof s.deriveRepoId !== "function") bad.push("deriveRepoId not exported");
if (typeof s.canonicalRepoUrl !== "function") bad.push("canonicalRepoUrl not exported");
if (bad.length) { console.error(bad.join("; ")); process.exit(1); }
console.log("OK");
' 2>&1)
if [ "$U1" = "OK" ]; then t94_ok "U1 surface: STATE_SCHEMA_VERSION=4, deriveRepoId + canonicalRepoUrl exported"; else t94_bad "U1 surface: $U1"; fi

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
if (s.schema_version !== 4) problems.push('schema_version=' + s.schema_version + ' (want 4)');
if ('version' in s) problems.push('dead version key survived');
if ('project_root' in s) problems.push('project_root survived');
const expect = state.deriveRepoId(process.env.T94_REMOTE_URL || null);
if (s.repo_id !== expect) problems.push('repo_id=' + s.repo_id + ' want ' + expect);
if (process.env.T94_REMOTE_URL && s.repo_id === null) problems.push('repo_id null while origin remote present');
// idempotent re-migration
const s2 = state.migrateState(s);
if (s2.schema_version !== 4 || s2.repo_id !== expect) problems.push('re-migration not idempotent');
if ('version' in s2 || 'project_root' in s2) problems.push('re-migration resurrected dropped keys');
// legacy (pre-schema) state migrates straight to v4
const l = fixture(); delete l.schema_version;
const s3 = state.migrateState(l);
if (s3.schema_version !== 4) problems.push('legacy → v' + s3.schema_version);
if (s3.repo_id !== expect) problems.push('legacy repo_id=' + s3.repo_id);
// v2→v3 semantics ride through: arrays stay arrays
if (!Array.isArray(s3.decisions) || !Array.isArray(s3.gaps)) problems.push('array normalization lost');
console.log(problems.length ? 'BAD ' + problems.join('; ') : 'OK');
process.exit(problems.length ? 1 : 0);
EOF
U3=$(node ../t94-migrate.cjs 2>&1)
if printf '%s\n' "$U3" | tail -n 1 | grep -qx 'OK' && ! printf '%s' "$U3" | grep -q 'BAD'; then
  t94_ok "U3 v3 fixture migrates: version/project_root dropped, repo_id derived, idempotent, legacy→4"; else t94_bad "U3 migration: $U3"
fi

# --- U4: no-remote repo — repo_id advisory null (D-18) ---
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
if (s.schema_version !== 4) problems.push('disk schema_version=' + s.schema_version);
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
  t94_ok "U5b write-class persists v4: keys dropped, repo_id hashed, raw URL absent"; else t94_bad "U5b write-class: rc=$CPRC disk=$DISK"
fi

# --- U6: fresh init writes schema v4 with repo_id, no dead version key ---
cd "$T94_DIR" && mkdir -p repo-fresh && cd repo-fresh
git init -q . && git commit -q --allow-empty -m root
git remote add origin https://github.com/octocat/widget.git
node "$GOS" init 1 "t94 fresh v4" >/dev/null 2>&1; IRC=$?
cat > ../t94-fresh.cjs <<'EOF'
const fs = require('fs');
const path = require('path');
const state = require(path.join(process.env.GOS_ROOT, 'bin/lib/core/state.cjs'));
const problems = [];
const s = JSON.parse(fs.readFileSync('.gos/state.json', 'utf8'));
if (s.schema_version !== 4) problems.push('fresh schema_version=' + s.schema_version);
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
  t94_ok "U6 fresh init: schema 4, no version key, repo_id derived, URL never stored"; else t94_bad "U6 fresh init: rc=$IRC fresh=$FRESH"
fi

echo "--- T94 summary: $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
