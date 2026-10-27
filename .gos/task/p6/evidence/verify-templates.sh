#!/usr/bin/env bash
# Templates-side evidence: the lint census holds zero records under
# templates/, and the general book names every banned-form family in
# digit-free placeholder spelling.
set -u
cd "$(dirname "$0")/../../../.." || exit 1
tmp_out=$(mktemp)
trap 'rm -f "$tmp_out"' EXIT
bash test/checks/ai-trace-lint.sh --emit-hits "$tmp_out" > /dev/null 2>&1 || exit 1
tpl_hits=$(node -e 'const fs=require("fs");const h=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.stdout.write(String(h.filter(r=>r.path.startsWith("templates/")).length))' "$tmp_out")
book_hits=$(grep -cE 'REVIEW Mn|Wn-Tn|RTn-Fn|§n' templates/coding-standards/00-general.md)
echo "templates_hit_records=${tpl_hits} general_book_placeholder_families=${book_hits}"
test "$tpl_hits" -eq 0 -a "$book_hits" -ge 3
