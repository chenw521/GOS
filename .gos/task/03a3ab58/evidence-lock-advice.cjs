const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const GR = path.resolve(__dirname, '..', '..', '..');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'lockadv-'));
fs.mkdirSync(path.join(dir, '.gos'), { recursive: true });
const lockPath = path.join(dir, '.gos', '.lock');
fs.writeFileSync(lockPath, JSON.stringify({ pid: process.pid, started_at: new Date().toISOString() }));
const past = new Date(Date.now() - 300000);
fs.utimesSync(lockPath, past, past);
const r = spawnSync(process.execPath, ['-e', `
  const core = require(${JSON.stringify(path.join(GR, 'bin/lib/core/index.cjs'))});
  try { core.acquireLock(false); console.log('LOCK-ACQUIRED'); } catch (e) { console.log('THREW', e.message); }
`], { env: { ...process.env, GOS_DIR_OVERRIDE: dir }, encoding: 'utf8', cwd: dir });
const out = String(r.stdout || '') + String(r.stderr || '');
fs.rmSync(dir, { recursive: true, force: true });
if (r.status !== 1) { console.log('BAD expected exit 1, got ' + r.status + ' :: ' + out.slice(0, 150)); process.exit(1); }
if (!out.includes('ALIVE')) { console.log('BAD alive branch not taken: ' + out.slice(0, 150)); process.exit(1); }
if (out.includes('re-run with --break-lock')) { console.log('BAD break-lock advised against a live pid'); process.exit(1); }
console.log('aliveBranch=1 breakLockAdvice=0 exit=1 OK');
