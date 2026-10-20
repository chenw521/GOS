#!/usr/bin/env bash
# npm pack manifest integrity check (R-09): the published tarball must carry
# the plugin's runtime directories and must NOT carry repo-internal files.
# Asserts from the actual `npm pack --dry-run` manifest (never assumptions):
#   - entries under bin/, skills/, templates/, .opencode/, hooks/ exist
#     (any missing -> exit 1);
#   - AGENTS.md is absent from the manifest (repo agent instructions are not
#     part of the shipped package; if this fails, remove "AGENTS.md" from the
#     package.json files array).
# Census reconciliation (census.json): four sources cross-checked against the
# file census, all violations exit 1 naming the file/entry —
#   census-1  npm pack manifest <-> npm:true labels (both directions)
#             + symlink rule: a tracked symlink must sit under a git:true +
#             npm:false entry (npm never packs symlinks — verified behavior);
#   census-2  git ls-files top-level segments <-> git:true labels;
#   census-3  .gitignore <-> git:false entries (must be covered) and
#             git:true entries (must not be ignored) via git check-ignore;
#   census-4  untracked files (git -c core.quotepath=off status --porcelain
#             -uall --; XY codes stripped, rename arrows split, trailing '/'
#             stripped, exact-string census match) must resolve to a git:false
#             entry — anything else is an unregistered untracked file;
#   census-v  validator: root-matching entry keys rejected; every entry must
#             match at least one real file (ls-files union pack union disk).
# Usage: bash test/pack-check.sh    (exit 0 = pass, 1 = violation)
set -uo pipefail

cd "$(dirname "$0")/.."

# Manifest lines look like: "npm notice 3.4kB skills/gos-verify/SKILL.md".
paths="$(npm pack --dry-run 2>&1 | grep -E '^npm notice +[0-9.]+[kMG]?B ' | sed 's/^npm notice *[^ ]* //')"

fail=0

if [ -z "$paths" ]; then
  echo "FAIL: npm pack produced no manifest entries"
  exit 1
fi

for dir in bin skills templates .opencode hooks; do
  if printf '%s\n' "$paths" | grep -q "^$dir/"; then
    echo "ok: '$dir/' entries present in npm pack manifest"
  else
    echo "FAIL: npm pack manifest is missing '$dir/' entries"
    fail=1
  fi
done

if printf '%s\n' "$paths" | grep -qx 'AGENTS.md'; then
  echo "FAIL: AGENTS.md must not be in the npm pack manifest (repo-internal file; remove it from package.json files)"
  fail=1
else
  echo "ok: AGENTS.md absent from npm pack manifest"
fi

# ---- census four-way reconciliation ----
if [ ! -f census.json ]; then
  echo "FAIL: census.json missing at repo root (R-09 file census)"
  exit 1
fi
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
printf '%s\n' "$paths" > "$tmpdir/pack.txt"
git -c core.quotepath=off ls-files > "$tmpdir/ls.txt" 2>/dev/null || : > "$tmpdir/ls.txt"
git -c core.quotepath=off status --porcelain -uall -- > "$tmpdir/porcelain.txt" 2>/dev/null || : > "$tmpdir/porcelain.txt"

if ! node - "$tmpdir" <<'NODE'
const fs = require('fs');
const { execFileSync } = require('child_process');
const tmp = process.argv[2];
const readLines = (f) => fs.readFileSync(`${tmp}/${f}`, 'utf8').split('\n').map((s) => s.trim()).filter(Boolean);
const packList = readLines('pack.txt');
const ls = readLines('ls.txt');
const porcelain = fs.readFileSync(`${tmp}/porcelain.txt`, 'utf8');

let census;
try { census = JSON.parse(fs.readFileSync('census.json', 'utf8')); }
catch (e) { console.log(`census-v: FAIL cannot parse census.json (${e.message})`); process.exit(1); }
if (census.schema_version !== 1) { console.log('census-v: FAIL unsupported census schema_version'); process.exit(1); }

const entries = census.entries || {};
const rawKeys = Object.keys(entries);
const norm = (k) => (k.endsWith('/') ? k.slice(0, -1) : k);
const byNorm = {};
for (const k of rawKeys) byNorm[norm(k)] = entries[k];

function resolve(p) {
  let best = null;
  for (const k of rawKeys) {
    const kk = norm(k);
    if (!kk) continue;
    if (p === kk || p.startsWith(kk + '/')) {
      if (best === null || kk.length > best.length) best = kk;
    }
  }
  return best;
}
function ignored(p) {
  // A trailing slash forces directory semantics so `dir/` rules also match
  // paths that do not exist on disk yet (fresh clone before runtime use).
  try { execFileSync('git', ['check-ignore', '-q', '--', p], { stdio: 'ignore' }); return true; }
  catch {
    try { execFileSync('git', ['check-ignore', '-q', '--', p + '/'], { stdio: 'ignore' }); return true; }
    catch { return false; }
  }
}

const counts = { 1: 0, 2: 0, 3: 0, 4: 0, v: 0 };
const bad = (src, msg) => { console.log(`census-${src}: FAIL ${msg}`); counts[src]++; };

// validator: shape, root-matching keys, dead entries
const ROOT_SET = new Set(['', '.', '..', '*']);
for (const k of rawKeys) {
  const e = entries[k];
  if (!e || typeof e.git !== 'boolean' || typeof e.npm !== 'boolean') {
    bad('v', `entry "${k}" must carry boolean git/npm labels`);
    continue;
  }
  const kk = norm(k);
  if (ROOT_SET.has(kk) || kk.startsWith('/')) { bad('v', `root-matching entry key "${k}" rejected`); continue; }
  // Transient machine-local entries (git:false + covered by .gitignore) may
  // legitimately be absent on an idle tree — e.g. .gos/.lock exists only while
  // a gos process runs. They are never dead; their existence check is the
  // gitignore reconciliation (source 3), not presence here. Lifecycle entries
  // (lifecycle:true) are the tracked counterpart: present while a task is in
  // flight, legally absent on idle/archived trees and fresh clones (the dir
  // never travels once archived).
  const transient = (!e.git && ignored(kk)) || e.lifecycle === true;
  const alive = transient
    || ls.some((f) => f === kk || f.startsWith(kk + '/'))
    || packList.some((f) => f === kk || f.startsWith(kk + '/'))
    || fs.existsSync(kk);
  if (!alive) bad('v', `dead entry "${k}" matches nothing real (ls-files | pack | filesystem)`);
}

// source 1: pack manifest <-> npm:true (both directions) + symlink rule
for (const f of packList) {
  const r = resolve(f);
  if (r === null) { bad('1', `packed file not registered in census: ${f}`); continue; }
  if (!byNorm[r].npm) bad('1', `packed file resolves to npm:false entry "${r}": ${f}`);
}
for (const r of Object.keys(byNorm)) {
  if (!byNorm[r].npm) continue;
  if (!packList.some((f) => f === r || f.startsWith(r + '/'))) {
    bad('1', `npm:true entry "${r}" never appears in the pack manifest`);
  }
}
for (const f of ls) {
  let st; try { st = fs.lstatSync(f); } catch { continue; }
  if (!st.isSymbolicLink()) continue;
  const r = resolve(f);
  if (r === null) { bad('1', `tracked symlink not registered in census: ${f}`); continue; }
  if (!(byNorm[r].git === true && byNorm[r].npm === false)) {
    bad('1', `symlink ${f} sits under entry "${r}" — symlink entries must be git:true+npm:false (npm never packs symlinks)`);
  }
}

// source 2: tracked top-level segments must resolve git:true
const tops = new Set(ls.map((f) => f.split('/')[0]).filter(Boolean));
for (const t of tops) {
  const r = resolve(t);
  if (r === null) { bad('2', `tracked top-level path not registered in census: ${t}/`); continue; }
  if (!byNorm[r].git) bad('2', `tracked top-level path ${t}/ resolves to git:false entry "${r}"`);
}

// source 3: gitignore <-> census (git:false covered, git:true not ignored)
for (const k of rawKeys) {
  const e = entries[k];
  if (!e || typeof e.git !== 'boolean') continue;
  const kk = norm(k);
  if (e.git) {
    const rep = ls.find((f) => f === kk || f.startsWith(kk + '/'));
    if (rep === undefined) continue; // dead-entry verdict already emitted
    if (ignored(rep)) bad('3', `git:true entry "${k}" is ignored by .gitignore (representative ${rep})`);
  } else {
    let probe = kk;
    try { if (!fs.statSync(kk).isFile()) probe = `${kk}/probe`; } catch { probe = `${kk}/probe`; }
    if (!ignored(probe)) bad('3', `git:false entry "${k}" not covered by .gitignore (checked ${probe}) — gitignore drift`);
  }
}

// source 4: untracked files must resolve to a git:false entry
for (const line of porcelain.split('\n')) {
  if (!line.startsWith('??')) continue;
  const rest = line.slice(3);
  for (let q of rest.split(' -> ')) {
    q = q.replace(/\/+$/, '');
    if (!q) continue;
    const r = resolve(q);
    if (r !== null && byNorm[r].git === false) continue; // registered machine-local zone
    if (r === null) bad('4', `unregistered untracked file (no census entry): ${q}`);
    else bad('4', `unregistered untracked file (entry "${r}" is git:true — stage or commit it): ${q}`);
  }
}

const labels = {
  1: 'npm pack manifest <-> npm:true',
  2: 'ls-files top-level <-> git:true',
  3: 'gitignore <-> git:false',
  4: 'untracked <-> census git:false',
  v: 'census validator',
};
for (const s of ['1', '2', '3', '4', 'v']) {
  if (counts[s] === 0) console.log(`census-${s}: ok (${labels[s]})`);
}
process.exit(Object.values(counts).some((n) => n > 0) ? 1 : 0);
NODE
then
  fail=1
fi

if (( fail )); then
  echo "pack-check: FAIL"
  exit 1
fi
echo "pack-check: all checks passed"
