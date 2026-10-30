// Dogfood evidence: the live `gos auto run` runner drives the VERIFY stage
// through the registered spawn write channel. Prints repo-local facts only:
// runner identity, spawn registry entry, admitted channel uses, deny-detail
// scan over the tee'd section-runs logs of this runner window.
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..', '..');
const spawnId = process.env.GOS_AUTO_SPAWN_ID || '(none)';

function read(p) { try { return fs.readFileSync(p, 'utf8'); } catch { return ''; } }

const lock = JSON.parse(read(path.join(ROOT, '.gos', '.lock')) || '{}');
let runnerCmd = '(unreadable)';
try {
  runnerCmd = fs.readFileSync(`/proc/${lock.pid}/cmdline`, 'utf8').split('\0').filter(Boolean).join(' ');
} catch { runnerCmd = `(pid ${lock.pid} unreadable)`; }
const isAutoRun = /gos\.cjs auto run/.test(runnerCmd);

const regDir = path.join(ROOT, '.gos', 'cache', 'auto-spawn');
const regFiles = fs.readdirSync(regDir).filter((f) => f.endsWith('.json'));
const own = regFiles.map((f) => JSON.parse(read(path.join(regDir, f)))).find((e) => e.spawn_id === spawnId);

const claimLines = read(path.join(regDir, `${spawnId}.claim`)).split('\n').filter((l) => l.trim()).length;

// Deny-detail format written by the loop when a spawn stream hits a deny
// pattern: `deny '<pattern>': <line>` — expected zero across this window.
const runsDir = path.join(ROOT, '.gos', 'cache', 'section-runs');
const runnerStart = Date.parse(lock.started_at);
let teedLogs = 0;
let denyDetails = 0;
for (const f of fs.readdirSync(runsDir)) {
  const full = path.join(runsDir, f);
  if (fs.statSync(full).mtimeMs < runnerStart) continue;
  teedLogs += 1;
  if (/deny '/.test(read(full))) denyDetails += 1;
}

console.log(`dogfood: runner=${isAutoRun ? 'gos-auto-run' : 'other'} pid=${lock.pid}`);
console.log(`dogfood: spawn=${spawnId} kind=${own ? own.kind : '?'} stage=${own ? own.stage : '?'} live=${own ? Date.now() < own.expires_at : false}`);
console.log(`dogfood: channel-uses=${claimLines} deny-details-in-teed-logs=${denyDetails} teed-logs-this-runner=${teedLogs}`);
