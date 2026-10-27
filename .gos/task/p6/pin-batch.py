#!/usr/bin/env python3
"""Pin the D-class lines of a sweep batch as frozen-string whitelist entries.

Usage: python3 .gos/task/p6/pin-batch.py <batch-file>

Line numbers in the landed state are precomputed by simulating the
B-row deletions bottom-up (A rows keep their line, D rows never move).
Pins merge into an existing frozen-string entry for the same path; the
entry sort stays path asc then category asc so regeneration carries
them byte-stable.
"""
import hashlib
import json
import re
import sys
import collections

WL = '.gos/ai-trace-whitelist.json'
DISPOSITION = '.gos/task/p6/disposition.md'


def load_rows():
    rows = collections.defaultdict(lambda: collections.defaultdict(list))
    cur = None
    for line in open(DISPOSITION, encoding='utf8'):
        m = re.match(r'^### (\S+) \((\d+) hit', line)
        if m:
            cur = m.group(1)
            continue
        m = re.match(r'^\| (\d+) \| ([AB]) \| (\S+) \| ([ABD]) \|', line)
        if m and cur:
            rows[cur][int(m.group(1))].append((m.group(2), m.group(3), m.group(4)))
    return rows


def main():
    batch_file = sys.argv[1]
    batch = [p.strip() for p in open(batch_file) if p.strip() and not p.startswith('#')]
    rows = load_rows()
    sha = lambda s: hashlib.sha256(s.encode('utf8')).hexdigest()

    wl = json.load(open(WL))
    by_key = {(e['path'], e['category']): e for e in wl}
    batch_set = set(batch)

    for p in batch:
        plines = rows.get(p, {})
        dlines = sorted(ln for ln, rs in plines.items() if any(r[2] == 'D' for r in rs))
        if not dlines:
            continue
        bdeleted_above = lambda target: sum(
            1 for ln in plines
            if ln < target and any(r[2] == 'B' for r in plines[ln]))
        content = open(p, encoding='utf8').read().split('\n')
        pins = []
        for ln in dlines:
            landed = ln - bdeleted_above(ln)
            pins.append({'line': landed, 'sha256': sha(content[ln - 1])})
        key = (p, 'frozen-string')
        if key in by_key:
            old = {x['sha256']: x for x in by_key[key]['lines']}
            for pin in pins:
                old[pin['sha256']] = pin
            by_key[key]['lines'] = sorted(old.values(), key=lambda x: x['line'])
        else:
            entry = {
                'path': p, 'category': 'frozen-string',
                'reason': 'Contract strings, regex character classes and prompt text quote anchor-shaped tokens by design; pinned as frozen product surface.',
                'lines': pins,
            }
            wl.append(entry)
            by_key[key] = entry

    # drop any stale pin rows on batch paths whose lines no longer exist in the
    # landed state (line moved or content gone): keep pins whose sha matches the
    # landed content
    bdel_total = {}
    for p in batch:
        plines = rows.get(p, {})
        bdel_total[p] = sum(1 for ln, rs in plines.items() if any(r[2] == 'B' for r in rs))
    for e in wl:
        if e['category'] != 'frozen-string' or e['path'] not in batch_set:
            continue
        plines = rows.get(e['path'], {})
        deleted = {ln for ln, rs in plines.items() if any(r[2] == 'B' for r in rs)}
        keep = []
        for pin in e['lines']:
            landed = pin['line']
            # invert the shift: original = landed + deletions above landed
            orig = landed + sum(1 for ln in deleted if ln - sum(
                1 for d in deleted if d < ln) <= landed)
            content = open(e['path'], encoding='utf8').read().split('\n')
            ok = orig - 1 < len(content) and sha(content[orig - 1]) == pin['sha256']
            if not ok:
                # try locating by sha directly in landed positions
                for i, l in enumerate(content):
                    if sha(l) == pin['sha256']:
                        pin['line'] = i + 1
                        ok = True
                        break
            if ok:
                keep.append(pin)
        e['lines'] = sorted(keep, key=lambda x: x['line'])

    wl.sort(key=lambda e: (e['path'], e['category']))
    open(WL, 'w').write(json.dumps(wl, indent=2) + '\n')
    print('entries:', len(wl))


if __name__ == '__main__':
    main()
