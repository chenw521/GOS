#!/usr/bin/env bash
# Bilingual README sync check: structural diff (heading tree + anchor set)
# between README.md and README.zh-CN.md, required-content checks, and
# banned-strings grep. Language difference is allowed in TEXT, never in
# STRUCTURE (heading levels, count, order; per-file anchor uniqueness).
# Exit 0 only when every check passes.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EN="$ROOT/README.md"
ZH="$ROOT/README.zh-CN.md"
BANNED="$ROOT/test/banned-strings.txt"
FAIL=0

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; FAIL=1; }

echo "--- readme-sync: bilingual structural consistency ---"

for f in "$EN" "$ZH"; do
  if [ -f "$f" ]; then pass "input present: $(basename "$f")"; else fail "input missing: $f"; fi
done
if [ "$FAIL" = 1 ]; then echo "readme-sync: FAIL (missing inputs)"; exit 1; fi

# --- structural layer: heading tree + GitHub-style anchor slugs ---
python3 - "$EN" "$ZH" <<'PYEOF'
import re, sys

def headings(path):
    out, fence = [], False
    for line in open(path, encoding='utf-8'):
        if line.lstrip().startswith('```'):
            fence = not fence
            continue
        if fence:
            continue
        m = re.match(r'^(#{1,6})\s+(.+?)\s*$', line)
        if m:
            out.append((len(m.group(1)), m.group(2).strip()))
    return out

def slug(text):
    # GitHub anchor form: lowercase, drop punctuation (keep word chars,
    # hyphens, spaces), spaces -> hyphens. CJK word chars survive.
    s = re.sub(r'[^\w\- ]', '', text.lower())
    return s.replace(' ', '-')

en, zh = headings(sys.argv[1]), headings(sys.argv[2])
bad = 0

if len(en) != len(zh):
    print(f'  ✗ heading count differs: README.md={len(en)} README.zh-CN.md={len(zh)}')
    bad += 1
else:
    pass_msg = f'heading count matches ({len(en)})'

lvl_en = [l for l, _ in en]
lvl_zh = [l for l, _ in zh]
if lvl_en != lvl_zh:
    for i, (a, b) in enumerate(zip(lvl_en, lvl_zh)):
        if a != b:
            print(f'  ✗ heading #{i+1} level differs: EN=H{a} "{en[i][1]}" vs ZH=H{b} "{zh[i][1]}"')
            bad += 1
    if len(lvl_en) != len(lvl_zh):
        print('  ✗ level sequence length differs (see count above)')
        bad += 1
else:
    print(f'  ✓ heading tree identical (level sequence of {len(lvl_en)} headings)')
    if bad == 0 and len(en) == len(zh):
        print(f'  ✓ {pass_msg}')

for name, hs in (('README.md', en), ('README.zh-CN.md', zh)):
    slugs = [slug(t) for _, t in hs]
    empties = [t for t, s in zip(hs, slugs) if not s]
    dups = sorted({s for s in slugs if slugs.count(s) > 1})
    if empties:
        print(f'  ✗ {name}: headings slug to empty anchor: {[t for _, t in empties]}')
        bad += 1
    if dups:
        print(f'  ✗ {name}: duplicate anchors {dups}')
        bad += 1
    if not empties and not dups:
        print(f'  ✓ {name}: {len(slugs)} anchors, all non-empty and unique')

if len({slug(t) for _, t in en}) != len({slug(t) for _, t in zh}):
    print('  ✗ distinct anchor counts differ between languages')
    bad += 1

sys.exit(1 if bad else 0)
PYEOF
[ $? = 0 ] || FAIL=1

# --- required content: install command, wrong-package warning, badges ---
for f in "$EN" "$ZH"; do
  n="$(basename "$f")"
  grep -q 'npm i -g @chenw521/gos' "$f" \
    && pass "$n: beta install command present" \
    || fail "$n: missing 'npm i -g @chenw521/gos'"
  grep -Eq 'actions/workflows/ci\.yml/badge\.svg' "$f" \
    && pass "$n: CI badge image present" \
    || fail "$n: missing CI badge image URL"
  grep -Eq '\(https://github\.com/chenw521/GOS/actions/workflows/ci\.yml\)' "$f" \
    && pass "$n: CI badge link target correct" \
    || fail "$n: missing/incorrect CI badge link target"
done
grep -Eq 'unrelated third-party' "$EN" \
  && pass "README.md: wrong-package warning present" \
  || fail "README.md: missing wrong-package warning"
grep -Eq '抢注|无关第三方' "$ZH" \
  && pass "README.zh-CN.md: wrong-package warning present" \
  || fail "README.zh-CN.md: missing wrong-package warning"

# --- banned layer: early-conformation residue grep ---
if [ ! -f "$BANNED" ]; then
  fail "banned list missing: $BANNED"
else
  HITS=0
  while IFS= read -r pat; do
    case "$pat" in ''|'#'*) continue ;; esac
    grep -Eq "$pat" /dev/null 2>/dev/null
    rc=$?
    if [ "$rc" = 2 ]; then
      fail "banned pattern does not compile: $pat"
      continue
    fi
    for f in "$EN" "$ZH"; do
      if grep -Eq "$pat" "$f"; then
        fail "banned pattern hit in $(basename "$f"): $pat"
        grep -En "$pat" "$f" | sed 's/^/      /'
        HITS=$((HITS + 1))
      fi
    done
  done < "$BANNED"
  [ "$HITS" = 0 ] && pass "banned-strings grep clean on both READMEs" || true
fi

if [ "$FAIL" = 0 ]; then
  echo "readme-sync: PASS"
  exit 0
else
  echo "readme-sync: FAIL"
  exit 1
fi
