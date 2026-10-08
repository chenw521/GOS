#!/usr/bin/env bash
# Line-level i18n inventory scanner for the P13 Englishization migration.
# Emits one row per literal-bearing call site: {file, line, callKind, hasCJK}.
# Usage: i18n-inventory.sh [--json | --markdown]  (default: human summary)
# Output contract: --json prints ONLY the JSON array on stdout (diagnostics to
# stderr); exits non-zero on any internal error; never silently empty.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

python3 - "$@" <<'PYEOF'
import json
import os
import re
import sys


def fail(msg, code=1):
    print(f"i18n-inventory: {msg}", file=sys.stderr)
    sys.exit(code)


mode = "summary"
for arg in sys.argv[1:]:
    if arg == "--json":
        mode = "json"
    elif arg == "--markdown":
        mode = "markdown"
    else:
        fail(f"unknown argument: {arg!r}", 2)

# Scan classes: a superset of the legacy file-level regex. The legacy scan
# missed `throw new Error(` and `process.stdout.write(` entirely; both are
# counted here (callKind=other).
CALL_PATTERNS = [
    ("die", re.compile(r"\bcore\.die\(")),
    ("die", re.compile(r"\bfsio\.die\(")),
    ("die", re.compile(r"\bdie\(")),
    ("console", re.compile(r"\bconsole\.(?:log|error|warn)\(")),
    ("other", re.compile(r"\bthrow\s+new\s+Error\(")),
    ("other", re.compile(r"\bprocess\.stdout\.write\(")),
]
# Wide CJK class: radicals through unified ideographs, fullwidth forms,
# CJK punctuation.
CJK_RE = re.compile(r"[\u2e80-\u9fff\uff00-\uffef\u3000-\u303f]")
# Legacy noise heuristic: a string-literal lead made purely of punctuation,
# symbols, digits, or whitespace is not a migration target.
NOISE_CONTENT_RE = re.compile(r"[✓✗⚈=+|{}\-*/_.:,\s\d<>()\[\]#$]*")


def literal_lead(text, pos):
    """Offset of the first non-whitespace char at/after pos if it is a quote
    (string-literal lead), else -1. Skips newlines so a multi-line call counts
    once, at its first line."""
    n = len(text)
    while pos < n and text[pos] in " \t\r\n":
        pos += 1
    return pos if pos < n and text[pos] in "'\"`" else -1


def literal_end(text, start):
    """Offset just past the closing quote of the literal starting at `start`
    (escape-aware; naive for template literals). Falls back to EOF if the
    literal never closes, so CJK content stays visible rather than hidden."""
    quote = text[start]
    i = start + 1
    n = len(text)
    while i < n:
        c = text[i]
        if c == "\\":
            i += 2
        elif c == quote:
            return i + 1
        else:
            i += 1
    return n


if not os.path.isdir("bin"):
    fail("bin/ not found — run against a repo checkout")

rows = []
for dp, dirnames, filenames in os.walk("bin"):
    dirnames[:] = [d for d in dirnames if d != "node_modules"]
    for fn in sorted(filenames):
        if not fn.endswith((".cjs", ".js")):
            continue
        rel = os.path.join(dp, fn)
        with open(rel, encoding="utf-8") as fh:
            text = fh.read()
        lines = text.split("\n")
        line_starts = [0]
        for m in re.finditer("\n", text):
            line_starts.append(m.end())
        for li, line_text in enumerate(lines):
            cands = []
            for kind, rx in CALL_PATTERNS:
                for m in rx.finditer(line_text):
                    cands.append((m.start(), m.end(), kind))
            cands.sort()
            for _, end, kind in cands:
                lead = literal_lead(text, line_starts[li] + end)
                if lead < 0:
                    continue
                lend = literal_end(text, lead)
                closed = lend < len(text) and text[lend - 1] == text[lead]
                content = text[lead + 1 : lend - 1] if closed else text[lead + 1 :]
                if NOISE_CONTENT_RE.fullmatch(content):
                    continue
                rows.append(
                    {
                        "file": rel,
                        "line": li + 1,
                        "callKind": kind,
                        "hasCJK": bool(CJK_RE.search(content)),
                    }
                )
                break

if not rows:
    fail("scan produced 0 rows — refusing to emit an empty inventory")

rows.sort(key=lambda r: (r["file"], r["line"]))

files = {}
for r in rows:
    s = files.setdefault(r["file"], {"rows": 0, "cjk": 0})
    s["rows"] += 1
    s["cjk"] += 1 if r["hasCJK"] else 0
kinds = {k: sum(1 for r in rows if r["callKind"] == k) for k in ("die", "console", "other")}
total = len(rows)
total_cjk = sum(1 for r in rows if r["hasCJK"])

if mode == "json":
    json.dump(rows, sys.stdout, indent=1)
    print()
elif mode == "markdown":
    out = [
        f"## Inventory v2 (line-level): {total} rows across {len(files)} files",
        "",
        (
            f"Split: {total_cjk} CJK-bearing vs {total - total_cjk} already-English "
            f"(direct-replace). By callKind: die={kinds['die']}, "
            f"console={kinds['console']}, other={kinds['other']}."
        ),
        "",
        "| File | Rows | CJK | non-CJK |",
        "|:--|--:|--:|--:|",
    ]
    for f in sorted(files):
        s = files[f]
        out.append(f"| `{f}` | {s['rows']} | {s['cjk']} | {s['rows'] - s['cjk']} |")
    out.append(f"| **Total** | **{total}** | **{total_cjk}** | **{total - total_cjk}** |")
    print("\n".join(out))
else:
    print(f"i18n inventory: {total} rows across {len(files)} files")
    print(
        f"callKind: die={kinds['die']} console={kinds['console']} other={kinds['other']}"
    )
    print(
        f"hasCJK: {total_cjk} CJK-bearing / {total - total_cjk} already-English "
        "(direct-replace)"
    )
    print()
    print(f"{'File':<42}{'Rows':>6}{'CJK':>6}{'en':>6}")
    for f in sorted(files):
        s = files[f]
        print(f"{f:<42}{s['rows']:>6}{s['cjk']:>6}{s['rows'] - s['cjk']:>6}")
PYEOF
