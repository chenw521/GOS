const s = require('/home/bio-06/.local/share/gos/85af56a090a78924/store.json');
const fs = require('fs');
const trips = s.breaker.records.filter((r) => String(r.detail).includes('VERIFY'));
const denyHits = trips.reduce((n, r) => n + (String(r.detail).match(/deny '/g) || []).length, 0);
const seedLive = fs.readFileSync('.gos/logs/auto-run-2360842-1793375330237.log', 'utf8').includes('auto seed: stripped');
const channelUses = fs.readFileSync('.gos/logs/auto-run-2360842-1793375330237.log', 'utf8').length >= 0;
console.log(`dogfood-mechanism: verify-trips=${trips.length} deny-hits=${denyHits} seed-sanitize-live=${seedLive} logs=section-runs/dogfood-round{2,3}.log`);
