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

# The lint records only the first match per tier per line, so a comment
# line can hold several anchors; the strip runs the lint's own grammar
# to exhaustion so nothing anchor-shaped survives on a swept line.
A = re.ASCII
TIER_A = [
    re.compile(r'\[[A-Za-z]+(?:[ -][A-Za-z]+)*[ -]?[0-9/]', A),
    re.compile(r'\b[A-Za-z]+\d+-[A-Za-z]+\d+\b', A),
    re.compile(r'§\s*\d', A),
]
TIER_B = [
    re.compile(r'\bWave\s+\d+\b', A),
    re.compile(r'\bW\d+\b', A),
    re.compile(r'\bT\d+\b', A),
    re.compile(r'\b(?:D|R|B|F)-\d+\b', A),
    re.compile(r'\bthis\s+(?:phase|wave|task)\s+(?:adds|ships|introduces)\b', re.I | A),
]


def strip_all_anchors(text):
    """Remove every anchor shape from a comment line, extending brackets,
    section citations and slash compounds to their full human form."""
    out = text
    changed = True
    while changed:
        changed = False
        for pat in TIER_A + TIER_B:
            m = pat.search(out)
            if not m:
                continue
            tok = m.group(0)
            i, e = m.start(), m.end()
            if tok.startswith('['):
                close = out.find(']', e)
                if close >= 0:
                    e = close + 1
                else:
                    while e < len(out) and out[e] not in ' \t,.;:':
                        e += 1
            elif tok.lstrip().startswith('§'):
                while e < len(out) and re.match(r'[0-9a-zA-Z.-]', out[e]):
                    e += 1
            if i > 0 and e < len(out) and out[i - 1] in PAIRS and out[e] == PAIRS[out[i - 1]]:
                inner = out[i:e]
                if not re.search(r'[,;=]|->', inner):
                    i -= 1
                    e += 1
            while e + 1 < len(out) and out[e] == '/' and re.match(r'[A-Za-z]+-\d+|[0-9]+', out[e + 1:]):
                nxt = out.index(' ', e + 1) if ' ' in out[e + 1:] else len(out)
                seg = re.match(r'[A-Za-z]+-\d+|[0-9]+', out[e + 1:nxt]).group(0)
                e += 1 + len(seg)
            out = out[:i] + ' ' + out[e:]
            changed = True
    return out


def load_rows():
    rows = collections.defaultdict(lambda: collections.defaultdict(list))
    cur = None
    import os
    remedial_only = os.environ.get('SWEEP_REMEDIAL') == '1'
    seen_remedial = False
    for line in open(DISPOSITION, encoding='utf8'):
        if remedial_only:
            if line.startswith('## Remedial batch'):
                seen_remedial = True
                continue
            if not seen_remedial:
                continue
        m = re.match(r'^### (\S+) \((\d+) hit', line)
        if m:
            cur = m.group(1)
            continue
        m = re.match(r'^\| (\d+) \| ([AB]) \| ([^|]+?) \| ([ABD]) \|', line)
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
    # slash compounds: the census records the first element; absorb the chain
    while end + 1 < len(text) and text[end] == '/' and re.match(r'[A-Za-z]+-\d+', text[end + 1:]):
        nxt = text.index(' ', end + 1) if ' ' in text[end + 1:] else len(text)
        seg = text[end + 1:nxt]
        seg = re.match(r'[A-Za-z]+-\d+', seg).group(0)
        end += 1 + len(seg)
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


def tidy_comment(text):
    t = tidy(text)
    # comment lines only: drop wrapper parens left holding a lone connector
    t = re.sub(r'\(\s*(join|see|refs?|and|or|cf|via|per)\s*\)', ' ', t)
    t = re.sub(r'\(\s+([a-z]{1,10})\s+\)', r'(\1)', t)
    return tidy(t)


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
            is_comment = bool(re.match(r'^\s*(#|//|/\*|\*|<!--)', text)) or p.endswith(('.md', '.markdown'))
            if is_comment:
                text = strip_all_anchors(text)
            elif ' // ' in text:
                # trailing comment on a code line: strip the tail segment only
                cut = text.rindex(' // ')
                head, tail = text[:cut + 1], text[cut + 1:]
                text = head + strip_all_anchors(tail)
            else:
                spans = []
                for tier, tok, letter in rs:
                    i, e = extend_token(tok, text)
                    if i is None:
                        print(f'WARN miss {p}:{ln} {tok!r}')
                        continue
                    spans.append((i, e))
                for i, e in sorted(spans, reverse=True):
                    text = text[:i] + ' ' + text[e:]
            text2 = tidy_comment(text) if is_comment else tidy(text)
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
