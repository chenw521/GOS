#!/usr/bin/env python3
"""Apply frozen dispositions to a sweep batch (deterministic from disposition.md).

Usage: python3 .gos/task/p6/apply-batch.py <batch-file>

Letters: A strip the anchor tokens, keep the WHAT · B delete the line ·
D leave untouched (pinned separately as frozen-string surface).
Edits run bottom-up so line numbers stay valid; tokens extend to the
full human form (bracket through ], section marks through the citation,
parenthesized ids absorb their wrapper).
"""
import re
import sys
import collections

DISPOSITION = '.gos/task/p6/disposition.md'
PAIRS = {'(': ')', '[': ']'}
MARKERS = re.compile(r'^\s*(#|//|/\*|\*|<!--|\*/)?\s*$')


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


def extend_token(tok, text):
    idx = text.find(tok)
    if idx < 0:
        return None, None
    end = idx + len(tok)
    if tok.startswith('['):
        close = text.find(']', end)
        if close >= 0:
            end = close + 1
        else:
            while end < len(text) and text[end] not in ' \t,.;:':
                end += 1
    elif tok.startswith('§'):
        while end < len(text) and re.match(r'[0-9a-zA-Z.-]', text[end]):
            end += 1
    if idx > 0 and end < len(text) and text[idx - 1] in PAIRS and text[end] == PAIRS[text[idx - 1]]:
        inner = text[idx:end]
        if not re.search(r'[,;=]|->', inner):
            idx -= 1
            end += 1
    return idx, end


def tidy(text):
    t = text
    for _ in range(3):
        t = re.sub(r'[ \t]{2,}', ' ', t)
        t = re.sub(r'[\s]+([-*—–:;,]+)\s*$', '', t)
    return t.rstrip()


def main():
    batch_file = sys.argv[1]
    batch = [p.strip() for p in open(batch_file) if p.strip() and not p.startswith('#')]
    rows = load_rows()
    stats = {'A': 0, 'B': 0, 'D': 0}
    for p in batch:
        lines = open(p, encoding='utf8').read().split('\n')
        plines = rows.get(p, {})
        for ln in sorted(plines, reverse=True):
            rs = plines[ln]
            letters = {r[2] for r in rs}
            if 'D' in letters:
                stats['D'] += 1
                continue
            if 'B' in letters:
                del lines[ln - 1]
                stats['B'] += 1
                continue
            text = lines[ln - 1]
            spans = []
            for tier, tok, letter in rs:
                i, e = extend_token(tok, text)
                if i is None:
                    print(f'WARN miss {p}:{ln} {tok!r}')
                    continue
                spans.append((i, e))
            for i, e in sorted(spans, reverse=True):
                text = text[:i] + ' ' + text[e:]
            text2 = tidy(text)
            if MARKERS.match(text2):
                del lines[ln - 1]
                stats['B'] += 1
            else:
                lines[ln - 1] = text2
                stats['A'] += 1
        open(p, 'w', encoding='utf8').write('\n'.join(lines))
    print(stats)


if __name__ == '__main__':
    main()
