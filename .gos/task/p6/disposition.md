# Disposition census — frozen batch membership

Every registered in-flight-sweep hit line carries exactly one disposition
letter; permanently registered lines carry C rows for completeness.

Letters: A strip-anchor-keep-WHAT · B delete-with-backfill (ids ride the
sweep ledger) · C leave-whitelisted · D string-context audit (rewrite
anchor-free where the label is ours, pin frozen-string where a contract).

In-flight paths: 191 · hit rows: 1761 · permanent C rows: 22

Batches: 1 bin/lib core+task+knowledge · 2 bin/lib rest + bin root ·
3 test tree outside sections · 4 test/sections (serial split 4a/4b by file
count allowed at sweep time) · 5 product docs, hooks, scripts and skills.

## Permanent registrations (C)

| path | line | category |
|:--|:--|:--|
| .gitattributes | 1 | meta-doc-quoting |
| .gitignore | 75 | meta-doc-quoting |
| .gitignore | 75 | meta-doc-quoting |
| .gitignore | 80 | meta-doc-quoting |
| .gitignore | 80 | meta-doc-quoting |
| .gitignore | 82 | meta-doc-quoting |
| AGENTS.md | 41 | meta-doc-quoting |
| AGENTS.md | 41 | meta-doc-quoting |
| AGENTS.md | 42 | meta-doc-quoting |
| AGENTS.md | 43 | meta-doc-quoting |
| bin/lib/core/state.cjs | 565 | frozen-string |
| test/fixtures/ai-trace/anchors.json | 3 | lint-fixture |
| test/fixtures/ai-trace/anchors.json | 4 | lint-fixture |
| test/fixtures/ai-trace/anchors.json | 5 | lint-fixture |
| test/fixtures/ai-trace/anchors.json | 6 | lint-fixture |
| test/fixtures/ai-trace/anchors.md | 10 | lint-fixture |
| test/fixtures/ai-trace/anchors.md | 11 | lint-fixture |
| test/fixtures/ai-trace/anchors.md | 12 | lint-fixture |
| test/fixtures/ai-trace/anchors.sh | 3 | lint-fixture |
| test/fixtures/ai-trace/anchors.sh | 4 | lint-fixture |
| test/fixtures/ai-trace/anchors.sh | 5 | lint-fixture |
| test/sections/T46-module-structure.test.sh | 50 | drift-ledger |

## In-flight dispositions

### .github/RELEASE.md (3 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 44 | B | D-50 | A | strip anchor, keep the WHAT |
| 45 | B | D-78 | A | strip anchor, keep the WHAT |
| 60 | B | D-69 | A | strip anchor, keep the WHAT |

### .github/workflows/ci.yml (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 5 | B | R-09 | A | strip anchor, keep the WHAT |

### .github/workflows/triage-gate.yml (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 1 | B | D-10 | A | strip anchor, keep the WHAT |
| 18 | B | T13 | A | strip anchor, keep the WHAT |
| 61 | B | D-10 | A | strip anchor, keep the WHAT |
| 187 | B | D-10 | A | strip anchor, keep the WHAT |

### .opencode/commands/gos/gos-brownfield.md (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 12 | B | D-22 | A | strip anchor, keep the WHAT |

### .opencode/commands/gos/gos-init.md (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 12 | B | R-01 | A | strip anchor, keep the WHAT |

### README.md (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 190 | B | T1 | A | strip anchor, keep the WHAT |

### README.zh-CN.md (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 141 | B | T1 | A | strip anchor, keep the WHAT |

### bin/gos.cjs (59 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 39 | B | T1 | A | strip anchor, keep the WHAT |
| 41 | B | T6 | A | strip anchor, keep the WHAT |
| 44 | B | T6 | B | delete lineage-only line, ids ride the ledger |
| 49 | B | T4 | A | strip anchor, keep the WHAT |
| 52 | B | T3 | A | strip anchor, keep the WHAT |
| 54 | B | R-03 | A | strip anchor, keep the WHAT |
| 56 | B | T1 | A | strip anchor, keep the WHAT |
| 57 | B | T3 | A | strip anchor, keep the WHAT |
| 61 | A | R3-F3 | A | strip anchor, keep the WHAT |
| 61 | B | D-16 | A | strip anchor, keep the WHAT |
| 62 | A | R3-F2 | A | strip anchor, keep the WHAT |
| 64 | A | R1-F4 | A | strip anchor, keep the WHAT |
| 65 | B | D-20 | A | strip anchor, keep the WHAT |
| 66 | B | D-14 | A | strip anchor, keep the WHAT |
| 69 | A | R2-F1 | A | strip anchor, keep the WHAT |
| 71 | B | T3 | A | strip anchor, keep the WHAT |
| 76 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 77 | B | T3 | A | strip anchor, keep the WHAT |
| 78 | B | T29 | A | strip anchor, keep the WHAT |
| 80 | B | T3 | A | strip anchor, keep the WHAT |
| 82 | A | R1-F9 | A | strip anchor, keep the WHAT |
| 86 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 86 | B | T2 | A | strip anchor, keep the WHAT |
| 88 | A | [R4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 88 | B | T4 | A | strip anchor, keep the WHAT |
| 93 | B | T7 | A | strip anchor, keep the WHAT |
| 96 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 97 | B | B-20 | A | strip anchor, keep the WHAT |
| 101 | A | R1-F1 | B | delete lineage-only line, ids ride the ledger |
| 101 | B | W1 | B | delete lineage-only line, ids ride the ledger |
| 103 | A | R3-F5 | A | strip anchor, keep the WHAT |
| 103 | B | D-36 | A | strip anchor, keep the WHAT |
| 104 | B | T3 | A | strip anchor, keep the WHAT |
| 106 | A | [R4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 109 | A | R1-F5 | A | strip anchor, keep the WHAT |
| 109 | B | D-41 | A | strip anchor, keep the WHAT |
| 117 | B | T5 | A | strip anchor, keep the WHAT |
| 120 | B | T3 | A | strip anchor, keep the WHAT |
| 124 | B | T5 | A | strip anchor, keep the WHAT |
| 131 | A | [Phase D T2 | A | strip anchor, keep the WHAT |
| 135 | A | R1-F9 | A | strip anchor, keep the WHAT |
| 135 | B | T3 | A | strip anchor, keep the WHAT |
| 138 | B | F-8 | A | strip anchor, keep the WHAT |
| 142 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 143 | B | T3 | A | strip anchor, keep the WHAT |
| 147 | B | D-01 | A | strip anchor, keep the WHAT |
| 151 | B | F-8 | A | strip anchor, keep the WHAT |
| 203 | B | D-11 | A | strip anchor, keep the WHAT |
| 221 | B | W2 | A | strip anchor, keep the WHAT |
| 222 | B | D-02 | A | strip anchor, keep the WHAT |
| 223 | B | D-11 | A | strip anchor, keep the WHAT |
| 224 | B | D-20 | A | strip anchor, keep the WHAT |
| 230 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 230 | B | T5 | B | delete lineage-only line, ids ride the ledger |
| 236 | B | T5 | A | strip anchor, keep the WHAT |
| 245 | B | B-5 | A | strip anchor, keep the WHAT |
| 250 | B | B-4 | A | strip anchor, keep the WHAT |
| 253 | B | B-6 | A | strip anchor, keep the WHAT |
| 258 | B | B-4 | A | strip anchor, keep the WHAT |

### bin/lib/core/fsio.cjs (12 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 60 | A | [P4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 60 | B | D-15 | A | strip anchor, keep the WHAT |
| 88 | B | D-01 | A | strip anchor, keep the WHAT |
| 112 | A | [REVIEW P2 | A | strip anchor, keep the WHAT |
| 170 | A | [T5 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 170 | B | T5 | A | strip anchor, keep the WHAT |
| 215 | A | R2-F9 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 278 | A | [T1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 278 | B | T10 | A | strip anchor, keep the WHAT |
| 297 | B | D-66 | A | strip anchor, keep the WHAT |
| 316 | B | D-66 | A | strip anchor, keep the WHAT |
| 318 | B | D-63 | A | strip anchor, keep the WHAT |

### bin/lib/core/gitprobe.cjs (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 1 | A | §3 | A | strip anchor, keep the WHAT |
| 1 | B | D-14 | A | strip anchor, keep the WHAT |
| 140 | A | R2-F9 | A | strip anchor, keep the WHAT |
| 170 | B | T8 | A | strip anchor, keep the WHAT |

### bin/lib/core/i18n.cjs (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 1 | B | D-63 | A | strip anchor, keep the WHAT |
| 61 | B | T74 | A | strip anchor, keep the WHAT |
| 63 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 111 | B | D-63 | A | strip anchor, keep the WHAT |

### bin/lib/core/locales/en.cjs (14 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 1 | B | D-63 | A | strip anchor, keep the WHAT |
| 11 | B | D-66 | A | strip anchor, keep the WHAT |
| 60 | A | Lv0-Lv4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 71 | B | D-02 | A | strip anchor, keep the WHAT |
| 78 | B | D-67 | A | strip anchor, keep the WHAT |
| 87 | B | T5 | A | strip anchor, keep the WHAT |
| 90 | B | T6 | A | strip anchor, keep the WHAT |
| 98 | B | D-15 | A | strip anchor, keep the WHAT |
| 119 | A | RT3-F7 | A | strip anchor, keep the WHAT |
| 119 | B | D-15 | A | strip anchor, keep the WHAT |
| 127 | B | T8 | A | strip anchor, keep the WHAT |
| 128 | B | D-66 | A | strip anchor, keep the WHAT |
| 160 | A | [Y/ | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 215 | B | T6 | A | strip anchor, keep the WHAT |

### bin/lib/core/locales/zh.cjs (16 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 1 | B | D-63 | A | strip anchor, keep the WHAT |
| 3 | B | T74 | A | strip anchor, keep the WHAT |
| 9 | B | D-68 | A | strip anchor, keep the WHAT |
| 15 | B | D-66 | A | strip anchor, keep the WHAT |
| 61 | B | D-02 | B | delete lineage-only line, ids ride the ledger |
| 70 | A | Lv0-Lv4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 81 | B | D-67 | B | delete lineage-only line, ids ride the ledger |
| 89 | B | T5 | B | delete lineage-only line, ids ride the ledger |
| 92 | B | T6 | B | delete lineage-only line, ids ride the ledger |
| 100 | B | D-15 | B | delete lineage-only line, ids ride the ledger |
| 120 | A | RT3-F7 | B | delete lineage-only line, ids ride the ledger |
| 120 | B | D-15 | B | delete lineage-only line, ids ride the ledger |
| 128 | B | T8 | A | strip anchor, keep the WHAT |
| 129 | B | D-66 | B | delete lineage-only line, ids ride the ledger |
| 161 | A | [Y/ | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 216 | B | T6 | B | delete lineage-only line, ids ride the ledger |

### bin/lib/core/lock.cjs (10 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 48 | A | R2-F9 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 78 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 115 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 151 | A | [T4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 151 | B | D-12 | A | strip anchor, keep the WHAT |
| 170 | B | D-18 | A | strip anchor, keep the WHAT |
| 187 | A | [T4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 228 | A | [T4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 228 | B | D-12 | A | strip anchor, keep the WHAT |
| 236 | B | D-18 | A | strip anchor, keep the WHAT |

### bin/lib/core/state.cjs (69 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 83 | A | [D-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 83 | B | D-12 | A | strip anchor, keep the WHAT |
| 97 | A | [A-Za-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 141 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 160 | B | D-18 | B | delete lineage-only line, ids ride the ledger |
| 185 | B | D-12 | A | strip anchor, keep the WHAT |
| 224 | A | [Phase W T9 | A | strip anchor, keep the WHAT |
| 224 | B | T9 | A | strip anchor, keep the WHAT |
| 226 | B | T5 | A | strip anchor, keep the WHAT |
| 227 | B | D-12 | A | strip anchor, keep the WHAT |
| 231 | A | [T9 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 231 | B | T94 | A | strip anchor, keep the WHAT |
| 234 | B | D-18 | A | strip anchor, keep the WHAT |
| 265 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 265 | B | T2 | A | strip anchor, keep the WHAT |
| 306 | B | D-12 | A | strip anchor, keep the WHAT |
| 325 | A | [T5 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 325 | B | T5 | A | strip anchor, keep the WHAT |
| 355 | A | [T5 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 355 | B | T5 | A | strip anchor, keep the WHAT |
| 359 | B | T1 | A | strip anchor, keep the WHAT |
| 366 | B | T46 | A | strip anchor, keep the WHAT |
| 432 | B | F-3 | A | strip anchor, keep the WHAT |
| 450 | B | T6 | A | strip anchor, keep the WHAT |
| 479 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 479 | B | T2 | A | strip anchor, keep the WHAT |
| 487 | B | T3 | A | strip anchor, keep the WHAT |
| 488 | B | T29 | A | strip anchor, keep the WHAT |
| 502 | B | T3 | A | strip anchor, keep the WHAT |
| 513 | A | [D-0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 513 | B | D-05 | A | strip anchor, keep the WHAT |
| 516 | A | [D-0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 516 | B | D-06 | A | strip anchor, keep the WHAT |
| 525 | A | [D-0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 525 | B | T3 | A | strip anchor, keep the WHAT |
| 536 | A | [D-0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 536 | B | T4 | A | strip anchor, keep the WHAT |
| 546 | B | D-88 | A | strip anchor, keep the WHAT |
| 554 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 554 | B | D-33 | A | strip anchor, keep the WHAT |
| 555 | A | §2 | A | strip anchor, keep the WHAT |
| 556 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 556 | B | B-3 | A | strip anchor, keep the WHAT |
| 566 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 567 | A | [R3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 568 | A | [R3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 569 | A | [R3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 570 | A | [R3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 571 | A | [R3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 572 | A | [F1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 573 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 573 | B | D-38 | A | strip anchor, keep the WHAT |
| 596 | A | [R3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 624 | A | [U2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 629 | A | R1-F5 | A | strip anchor, keep the WHAT |
| 629 | B | T4 | A | strip anchor, keep the WHAT |
| 647 | A | [y/ | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 665 | B | T4 | A | strip anchor, keep the WHAT |
| 675 | A | [REVIEW P2 | A | strip anchor, keep the WHAT |
| 677 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 713 | B | D-12 | A | strip anchor, keep the WHAT |
| 752 | A | [R-2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 752 | B | D-04 | A | strip anchor, keep the WHAT |
| 781 | B | D-04 | A | strip anchor, keep the WHAT |
| 842 | B | D-01 | A | strip anchor, keep the WHAT |
| 860 | B | R-01 | A | strip anchor, keep the WHAT |
| 887 | B | D-64 | A | strip anchor, keep the WHAT |
| 1234 | A | [P4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 1234 | B | D-15 | A | strip anchor, keep the WHAT |

### bin/lib/knowledge/concerns.cjs (13 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 31 | A | [T6 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 31 | B | T6 | A | strip anchor, keep the WHAT |
| 37 | A | [T6 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 37 | B | T6 | A | strip anchor, keep the WHAT |
| 58 | A | [T6 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 58 | B | T6 | A | strip anchor, keep the WHAT |
| 94 | A | [T5 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 94 | B | T5 | A | strip anchor, keep the WHAT |
| 95 | B | T1 | A | strip anchor, keep the WHAT |
| 118 | A | [T6 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 118 | B | T6 | A | strip anchor, keep the WHAT |
| 122 | B | D-16 | A | strip anchor, keep the WHAT |
| 230 | B | B-9 | A | strip anchor, keep the WHAT |

### bin/lib/knowledge/decisions.cjs (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 10 | B | D-03 | A | strip anchor, keep the WHAT |

### bin/lib/knowledge/lessons-json.cjs (15 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 2 | A | §8 | A | strip anchor, keep the WHAT |
| 3 | A | §3 | A | strip anchor, keep the WHAT |
| 12 | A | §8 | A | strip anchor, keep the WHAT |
| 35 | A | §8 | A | strip anchor, keep the WHAT |
| 74 | A | §8 | A | strip anchor, keep the WHAT |
| 77 | A | [T5 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 77 | B | T5 | A | strip anchor, keep the WHAT |
| 173 | B | B-8 | A | strip anchor, keep the WHAT |
| 214 | B | B-14 | A | strip anchor, keep the WHAT |
| 300 | B | B-9 | A | strip anchor, keep the WHAT |
| 502 | A | §8 | A | strip anchor, keep the WHAT |
| 520 | B | D-09 | A | strip anchor, keep the WHAT |
| 561 | A | §3 | A | strip anchor, keep the WHAT |
| 561 | B | D-09 | A | strip anchor, keep the WHAT |
| 585 | B | D-09 | A | strip anchor, keep the WHAT |

### bin/lib/knowledge/lessons.cjs (6 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 99 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 102 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 137 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 255 | A | §3 | A | strip anchor, keep the WHAT |
| 276 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 321 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### bin/lib/knowledge/phase.cjs (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 18 | B | D-06 | A | strip anchor, keep the WHAT |
| 31 | B | D-06 | A | strip anchor, keep the WHAT |
| 209 | A | [T4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 209 | B | D-12 | A | strip anchor, keep the WHAT |

### bin/lib/knowledge/requirements.cjs (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 48 | B | R-01 | A | strip anchor, keep the WHAT |
| 59 | B | R-02 | A | strip anchor, keep the WHAT |

### bin/lib/knowledge/truth.cjs (13 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 27 | B | B-18 | A | strip anchor, keep the WHAT |
| 35 | B | D-02 | A | strip anchor, keep the WHAT |
| 78 | A | [R-2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 78 | B | D-05 | A | strip anchor, keep the WHAT |
| 98 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 103 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 103 | B | D-04 | A | strip anchor, keep the WHAT |
| 112 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 115 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 119 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 121 | B | D-04 | A | strip anchor, keep the WHAT |
| 125 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 135 | B | R-35 | A | strip anchor, keep the WHAT |

### bin/lib/map/allowlist.cjs (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 338 | A | [y/ | D | string-context audit: rewrite anchor-free or pin frozen-string |

### bin/lib/map/anchor.cjs (8 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 29 | A | [T4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 29 | B | D-12 | A | strip anchor, keep the WHAT |
| 30 | B | D-18 | A | strip anchor, keep the WHAT |
| 43 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 81 | A | §4 | A | strip anchor, keep the WHAT |
| 94 | A | R2-F9 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 99 | A | [P1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 131 | B | D-23 | A | strip anchor, keep the WHAT |

### bin/lib/map/contract.cjs (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 9 | B | T1 | A | strip anchor, keep the WHAT |
| 20 | B | T1 | A | strip anchor, keep the WHAT |

### bin/lib/map/edges.cjs (3 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 56 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 61 | A | §4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 91 | A | [P1 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### bin/lib/map/engine.cjs (27 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 70 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 96 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 116 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 240 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 256 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 281 | A | [Phase S/ | A | strip anchor, keep the WHAT |
| 284 | B | R-10 | A | strip anchor, keep the WHAT |
| 340 | A | [REVIEW M1 | A | strip anchor, keep the WHAT |
| 350 | A | [REVIEW m8 | A | strip anchor, keep the WHAT |
| 359 | A | [REVIEW m4 | A | strip anchor, keep the WHAT |
| 374 | A | [Phase P T6 | A | strip anchor, keep the WHAT |
| 401 | A | [Phase S/ | A | strip anchor, keep the WHAT |
| 401 | B | D-02 | A | strip anchor, keep the WHAT |
| 409 | A | [Phase S/ | A | strip anchor, keep the WHAT |
| 417 | A | [REVIEW M2 | A | strip anchor, keep the WHAT |
| 440 | A | [REVIEW M1 | A | strip anchor, keep the WHAT |
| 450 | A | [Phase S/ | A | strip anchor, keep the WHAT |
| 502 | A | [Phase D T3 | A | strip anchor, keep the WHAT |
| 502 | B | T3 | A | strip anchor, keep the WHAT |
| 504 | A | [Phase P T2 | A | strip anchor, keep the WHAT |
| 532 | A | [Phase P T2 | A | strip anchor, keep the WHAT |
| 532 | B | T2 | A | strip anchor, keep the WHAT |
| 585 | A | [m2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 650 | A | [m8 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 703 | A | [P1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 715 | A | [Phase P T7 | A | strip anchor, keep the WHAT |
| 753 | B | R-06 | A | strip anchor, keep the WHAT |

### bin/lib/map/index.cjs (31 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 24 | A | [Phase P T7 | A | strip anchor, keep the WHAT |
| 24 | B | T7 | A | strip anchor, keep the WHAT |
| 93 | A | §4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 95 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 101 | A | §4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 110 | A | R2-F2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 160 | B | T5 | A | strip anchor, keep the WHAT |
| 161 | A | R2-F3 | A | strip anchor, keep the WHAT |
| 205 | A | [P1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 255 | B | D-65 | A | strip anchor, keep the WHAT |
| 285 | A | [Phase D T7 | A | strip anchor, keep the WHAT |
| 286 | A | [Phase D T8 | A | strip anchor, keep the WHAT |
| 289 | A | [Phase D T4 | A | strip anchor, keep the WHAT |
| 289 | B | T4 | A | strip anchor, keep the WHAT |
| 297 | A | [R3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 300 | A | R3-F12 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 302 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 308 | A | [Phase P T5 | A | strip anchor, keep the WHAT |
| 308 | B | T5 | A | strip anchor, keep the WHAT |
| 326 | A | [R-0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 335 | A | [R-0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 360 | A | [REVIEW m5 | A | strip anchor, keep the WHAT |
| 363 | A | [T7 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 367 | A | [P1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 377 | A | [T8 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 394 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 397 | A | [R3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 412 | B | T4 | A | strip anchor, keep the WHAT |
| 437 | A | [Phase P T7 | A | strip anchor, keep the WHAT |
| 437 | B | T7 | A | strip anchor, keep the WHAT |
| 467 | A | [Phase P T7 | A | strip anchor, keep the WHAT |

### bin/lib/map/views.cjs (10 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 20 | A | R2-F10 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 24 | B | D-24 | A | strip anchor, keep the WHAT |
| 68 | A | [P1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 203 | A | [Phase P T7 | A | strip anchor, keep the WHAT |
| 203 | B | T7 | A | strip anchor, keep the WHAT |
| 227 | A | [Phase P T7 | A | strip anchor, keep the WHAT |
| 227 | B | T7 | A | strip anchor, keep the WHAT |
| 238 | A | [REVIEW m6 | A | strip anchor, keep the WHAT |
| 270 | A | R2-F8 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 282 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### bin/lib/nav/cmds.cjs (7 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 12 | B | D-67 | A | strip anchor, keep the WHAT |
| 62 | B | D-02 | A | strip anchor, keep the WHAT |
| 68 | B | D-12 | A | strip anchor, keep the WHAT |
| 169 | A | [T6 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 169 | B | T6 | A | strip anchor, keep the WHAT |
| 228 | A | [T5 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 228 | B | T5 | A | strip anchor, keep the WHAT |

### bin/lib/nav/help.cjs (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 23 | A | R1-F7 | A | strip anchor, keep the WHAT |
| 23 | B | D-29 | A | strip anchor, keep the WHAT |
| 71 | A | R1-F7 | A | strip anchor, keep the WHAT |
| 97 | A | R1-F4 | A | strip anchor, keep the WHAT |

### bin/lib/nav/registry-consts.cjs (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 29 | A | R4-F1 | A | strip anchor, keep the WHAT |
| 29 | B | D-88 | A | strip anchor, keep the WHAT |

### bin/lib/nav/registry.cjs (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 55 | B | D-20 | B | delete lineage-only line, ids ride the ledger |

### bin/lib/nav/status.cjs (13 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 66 | A | [D-0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 66 | B | D-06 | A | strip anchor, keep the WHAT |
| 83 | A | [phase-ux L3 | A | strip anchor, keep the WHAT |
| 87 | A | [phase-ux L3 | A | strip anchor, keep the WHAT |
| 89 | B | T5 | A | strip anchor, keep the WHAT |
| 124 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 256 | B | D-23 | A | strip anchor, keep the WHAT |
| 258 | A | [MIN-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 262 | A | [D-0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 262 | B | D-06 | A | strip anchor, keep the WHAT |
| 266 | B | T4 | A | strip anchor, keep the WHAT |
| 274 | B | D-67 | A | strip anchor, keep the WHAT |
| 297 | A | R4-F9 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### bin/lib/ops/brownfield-probe.cjs (5 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 2 | B | T4 | A | strip anchor, keep the WHAT |
| 4 | B | T5 | A | strip anchor, keep the WHAT |
| 31 | B | D-99 | A | strip anchor, keep the WHAT |
| 47 | B | T2 | A | strip anchor, keep the WHAT |
| 117 | B | D-94 | A | strip anchor, keep the WHAT |

### bin/lib/ops/brownfield.cjs (29 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 2 | A | R4-F1 | A | strip anchor, keep the WHAT |
| 5 | A | R2-F7 | A | strip anchor, keep the WHAT |
| 5 | B | Wave 3 | A | strip anchor, keep the WHAT |
| 6 | B | D-94 | A | strip anchor, keep the WHAT |
| 7 | A | R2-F3 | A | strip anchor, keep the WHAT |
| 8 | A | R2-F12 | A | strip anchor, keep the WHAT |
| 8 | B | D-89 | A | strip anchor, keep the WHAT |
| 9 | B | D-99 | A | strip anchor, keep the WHAT |
| 14 | B | Wave 4 | A | strip anchor, keep the WHAT |
| 15 | B | D-90 | A | strip anchor, keep the WHAT |
| 18 | B | D-100 | A | strip anchor, keep the WHAT |
| 24 | B | D-89 | A | strip anchor, keep the WHAT |
| 51 | B | T78 | A | strip anchor, keep the WHAT |
| 142 | B | D-92 | A | strip anchor, keep the WHAT |
| 160 | B | D-97 | A | strip anchor, keep the WHAT |
| 163 | A | R4-F7 | A | strip anchor, keep the WHAT |
| 206 | A | R2-F6 | A | strip anchor, keep the WHAT |
| 217 | A | R2-F12 | A | strip anchor, keep the WHAT |
| 329 | B | D-89 | A | strip anchor, keep the WHAT |
| 399 | B | D-94 | A | strip anchor, keep the WHAT |
| 403 | B | D-89 | A | strip anchor, keep the WHAT |
| 518 | B | D-92 | A | strip anchor, keep the WHAT |
| 535 | B | D-92 | A | strip anchor, keep the WHAT |
| 552 | B | D-98 | A | strip anchor, keep the WHAT |
| 555 | B | T46 | A | strip anchor, keep the WHAT |
| 579 | A | R1-F6 | A | strip anchor, keep the WHAT |
| 579 | B | D-90 | A | strip anchor, keep the WHAT |
| 619 | B | D-100 | A | strip anchor, keep the WHAT |
| 658 | A | R1-F6 | A | strip anchor, keep the WHAT |

### bin/lib/ops/changelog-core.cjs (22 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | R-05 | A | strip anchor, keep the WHAT |
| 7 | B | D-07 | A | strip anchor, keep the WHAT |
| 15 | A | R3-F8 | A | strip anchor, keep the WHAT |
| 15 | B | D-07 | A | strip anchor, keep the WHAT |
| 16 | A | R1-F5 | A | strip anchor, keep the WHAT |
| 20 | B | R-08 | A | strip anchor, keep the WHAT |
| 40 | B | R-06 | A | strip anchor, keep the WHAT |
| 55 | B | R-05 | A | strip anchor, keep the WHAT |
| 64 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 76 | B | R-01 | A | strip anchor, keep the WHAT |
| 106 | B | R-08 | A | strip anchor, keep the WHAT |
| 112 | B | R-01 | A | strip anchor, keep the WHAT |
| 235 | B | R-06 | A | strip anchor, keep the WHAT |
| 237 | B | R-08 | A | strip anchor, keep the WHAT |
| 320 | B | D-43 | A | strip anchor, keep the WHAT |
| 324 | B | R-08 | A | strip anchor, keep the WHAT |
| 354 | B | D-07 | A | strip anchor, keep the WHAT |
| 367 | B | T61 | A | strip anchor, keep the WHAT |
| 391 | A | R1-F5 | A | strip anchor, keep the WHAT |
| 394 | A | R3-F8 | A | strip anchor, keep the WHAT |
| 473 | A | R1-F5 | A | strip anchor, keep the WHAT |
| 485 | B | D-07 | A | strip anchor, keep the WHAT |

### bin/lib/ops/config.cjs (11 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 22 | A | [a-zA-Z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 26 | B | D-09 | A | strip anchor, keep the WHAT |
| 72 | B | D-09 | A | strip anchor, keep the WHAT |
| 75 | A | R3-F10 | A | strip anchor, keep the WHAT |
| 131 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 139 | B | T2 | A | strip anchor, keep the WHAT |
| 140 | A | [B-2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 140 | B | B-2 | A | strip anchor, keep the WHAT |
| 142 | B | B-2 | A | strip anchor, keep the WHAT |
| 204 | B | D-07 | A | strip anchor, keep the WHAT |
| 290 | A | [a-zA-Z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### bin/lib/ops/doctor.cjs (10 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 87 | B | D-63 | A | strip anchor, keep the WHAT |
| 94 | A | [C-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 94 | B | T4 | A | strip anchor, keep the WHAT |
| 107 | B | F-6 | A | strip anchor, keep the WHAT |
| 111 | A | RT3-F11 | A | strip anchor, keep the WHAT |
| 111 | B | D-14 | A | strip anchor, keep the WHAT |
| 124 | A | R3-F1 | A | strip anchor, keep the WHAT |
| 126 | A | RT3-F11 | A | strip anchor, keep the WHAT |
| 126 | B | D-14 | A | strip anchor, keep the WHAT |
| 222 | B | D-02 | A | strip anchor, keep the WHAT |

### bin/lib/ops/feedback.cjs (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 236 | B | B-19 | A | strip anchor, keep the WHAT |
| 276 | A | [y/ | D | string-context audit: rewrite anchor-free or pin frozen-string |

### bin/lib/ops/gate.cjs (73 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 18 | B | T5 | A | strip anchor, keep the WHAT |
| 19 | B | T7 | A | strip anchor, keep the WHAT |
| 22 | B | T6 | A | strip anchor, keep the WHAT |
| 24 | B | T7 | A | strip anchor, keep the WHAT |
| 74 | A | [D-0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 74 | B | D-07 | A | strip anchor, keep the WHAT |
| 170 | A | [B-4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 184 | A | [Phase D T7 | A | strip anchor, keep the WHAT |
| 184 | B | T7 | A | strip anchor, keep the WHAT |
| 185 | A | R2-F5 | A | strip anchor, keep the WHAT |
| 190 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 197 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 197 | B | T3 | A | strip anchor, keep the WHAT |
| 201 | A | [Phase D T7 | A | strip anchor, keep the WHAT |
| 201 | B | T7 | A | strip anchor, keep the WHAT |
| 205 | A | [Phase D T1 | A | strip anchor, keep the WHAT |
| 205 | B | T10 | A | strip anchor, keep the WHAT |
| 215 | B | R-35 | A | strip anchor, keep the WHAT |
| 226 | A | R2-F11 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 234 | A | [D-0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 234 | B | D-02 | A | strip anchor, keep the WHAT |
| 235 | B | D-01 | A | strip anchor, keep the WHAT |
| 324 | A | [m7 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 344 | A | [U2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 344 | B | D-04 | A | strip anchor, keep the WHAT |
| 354 | A | [U2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 354 | B | D-01 | A | strip anchor, keep the WHAT |
| 357 | B | T33 | A | strip anchor, keep the WHAT |
| 430 | B | D-62 | A | strip anchor, keep the WHAT |
| 540 | A | [B-4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 549 | B | T2 | A | strip anchor, keep the WHAT |
| 565 | A | [Phase-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 565 | B | B-22 | A | strip anchor, keep the WHAT |
| 581 | B | D-62 | A | strip anchor, keep the WHAT |
| 651 | A | [Phase D T1 | A | strip anchor, keep the WHAT |
| 651 | B | T10 | A | strip anchor, keep the WHAT |
| 664 | A | [R-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 668 | B | B-18 | A | strip anchor, keep the WHAT |
| 690 | B | T8 | A | strip anchor, keep the WHAT |
| 700 | A | [R3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 700 | B | B-19 | A | strip anchor, keep the WHAT |
| 705 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 705 | B | B-3 | A | strip anchor, keep the WHAT |
| 737 | B | D-30 | A | strip anchor, keep the WHAT |
| 748 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 748 | B | T4 | A | strip anchor, keep the WHAT |
| 753 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 753 | B | T5 | A | strip anchor, keep the WHAT |
| 775 | B | B-11 | A | strip anchor, keep the WHAT |
| 776 | B | B-19 | A | strip anchor, keep the WHAT |
| 825 | A | [Phase P T6 | A | strip anchor, keep the WHAT |
| 825 | B | T6 | A | strip anchor, keep the WHAT |
| 827 | B | D-26 | A | strip anchor, keep the WHAT |
| 853 | B | T2 | A | strip anchor, keep the WHAT |
| 872 | A | [Phase R/ | A | strip anchor, keep the WHAT |
| 872 | B | D-01 | A | strip anchor, keep the WHAT |
| 873 | B | D-20 | A | strip anchor, keep the WHAT |
| 883 | B | D-20 | A | strip anchor, keep the WHAT |
| 930 | A | [P4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 930 | B | T8 | A | strip anchor, keep the WHAT |
| 940 | A | [R3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 940 | B | B-19 | A | strip anchor, keep the WHAT |
| 1049 | B | T6 | A | strip anchor, keep the WHAT |
| 1065 | B | R-03 | A | strip anchor, keep the WHAT |
| 1222 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 1222 | B | B-3 | A | strip anchor, keep the WHAT |
| 1238 | A | [P4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 1238 | B | T8 | A | strip anchor, keep the WHAT |
| 1239 | A | RT2-F4 | A | strip anchor, keep the WHAT |
| 1249 | A | §3 | A | strip anchor, keep the WHAT |
| 1352 | B | D-66 | A | strip anchor, keep the WHAT |
| 1354 | B | T73 | A | strip anchor, keep the WHAT |
| 1355 | B | D-63 | A | strip anchor, keep the WHAT |

### bin/lib/ops/gitseed.cjs (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 37 | A | [A-Za-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 41 | A | [A-Z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 106 | A | [A-Za-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 188 | A | [y/ | D | string-context audit: rewrite anchor-free or pin frozen-string |

### bin/lib/ops/push.cjs (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 78 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 145 | B | R-01 | A | strip anchor, keep the WHAT |

### bin/lib/ops/setup.cjs (8 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 26 | B | D-63 | A | strip anchor, keep the WHAT |
| 39 | B | D-63 | A | strip anchor, keep the WHAT |
| 50 | B | D-63 | A | strip anchor, keep the WHAT |
| 133 | B | D-94 | A | strip anchor, keep the WHAT |
| 230 | B | R-05 | A | strip anchor, keep the WHAT |
| 274 | B | D-63 | B | delete lineage-only line, ids ride the ledger |
| 302 | A | [ans1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 350 | A | [y/ | D | string-context audit: rewrite anchor-free or pin frozen-string |

### bin/lib/ops/track.cjs (23 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 2 | A | §3 | A | strip anchor, keep the WHAT |
| 2 | B | D-15 | A | strip anchor, keep the WHAT |
| 3 | A | RT2-F5 | A | strip anchor, keep the WHAT |
| 5 | A | RT2-F10 | A | strip anchor, keep the WHAT |
| 6 | A | RT3-F7 | A | strip anchor, keep the WHAT |
| 28 | A | §3 | A | strip anchor, keep the WHAT |
| 30 | B | T8 | A | strip anchor, keep the WHAT |
| 35 | B | T8 | A | strip anchor, keep the WHAT |
| 39 | A | RT2-F5 | A | strip anchor, keep the WHAT |
| 41 | B | T8 | A | strip anchor, keep the WHAT |
| 49 | A | §3 | A | strip anchor, keep the WHAT |
| 54 | A | §3 | A | strip anchor, keep the WHAT |
| 88 | A | RT3-F7 | A | strip anchor, keep the WHAT |
| 102 | A | RT3-F12 | A | strip anchor, keep the WHAT |
| 121 | A | RT3-F7 | A | strip anchor, keep the WHAT |
| 146 | A | §3 | A | strip anchor, keep the WHAT |
| 204 | B | T8 | A | strip anchor, keep the WHAT |
| 235 | A | RT2-F10 | A | strip anchor, keep the WHAT |
| 295 | A | §3 | A | strip anchor, keep the WHAT |
| 317 | A | §3 | A | strip anchor, keep the WHAT |
| 337 | A | RT3-F7 | A | strip anchor, keep the WHAT |
| 373 | A | §3 | A | strip anchor, keep the WHAT |
| 510 | A | §3 | A | strip anchor, keep the WHAT |

### bin/lib/render/views.cjs (57 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 11 | B | D-05 | A | strip anchor, keep the WHAT |
| 14 | B | D-08 | A | strip anchor, keep the WHAT |
| 17 | B | D-05 | A | strip anchor, keep the WHAT |
| 29 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 29 | B | T2 | A | strip anchor, keep the WHAT |
| 31 | A | R4-F6 | A | strip anchor, keep the WHAT |
| 34 | B | B-15 | A | strip anchor, keep the WHAT |
| 37 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 37 | B | B-15 | A | strip anchor, keep the WHAT |
| 42 | B | T7 | A | strip anchor, keep the WHAT |
| 48 | A | R4-F1 | A | strip anchor, keep the WHAT |
| 48 | B | D-30 | A | strip anchor, keep the WHAT |
| 52 | B | D-01 | A | strip anchor, keep the WHAT |
| 54 | B | D-41 | A | strip anchor, keep the WHAT |
| 58 | B | T36 | A | strip anchor, keep the WHAT |
| 60 | B | D-02 | B | delete lineage-only line, ids ride the ledger |
| 62 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 62 | B | T7 | A | strip anchor, keep the WHAT |
| 66 | B | B-10 | A | strip anchor, keep the WHAT |
| 69 | B | T8 | A | strip anchor, keep the WHAT |
| 71 | B | T4 | A | strip anchor, keep the WHAT |
| 72 | B | T29 | A | strip anchor, keep the WHAT |
| 77 | B | T29 | A | strip anchor, keep the WHAT |
| 78 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 82 | B | T4 | A | strip anchor, keep the WHAT |
| 84 | B | T8 | A | strip anchor, keep the WHAT |
| 88 | B | T3 | A | strip anchor, keep the WHAT |
| 89 | B | D-29 | A | strip anchor, keep the WHAT |
| 91 | B | D-32 | A | strip anchor, keep the WHAT |
| 94 | B | T1 | A | strip anchor, keep the WHAT |
| 95 | B | T1 | A | strip anchor, keep the WHAT |
| 96 | A | R4-F14 | A | strip anchor, keep the WHAT |
| 99 | B | D-08 | A | strip anchor, keep the WHAT |
| 104 | B | D-08 | A | strip anchor, keep the WHAT |
| 109 | B | T8 | A | strip anchor, keep the WHAT |
| 114 | A | R3-F1 | A | strip anchor, keep the WHAT |
| 114 | B | D-03 | A | strip anchor, keep the WHAT |
| 128 | B | D-08 | A | strip anchor, keep the WHAT |
| 160 | B | D-08 | A | strip anchor, keep the WHAT |
| 205 | A | R3-F1 | A | strip anchor, keep the WHAT |
| 205 | B | D-03 | A | strip anchor, keep the WHAT |
| 218 | A | R3-F1 | A | strip anchor, keep the WHAT |
| 218 | B | D-03 | A | strip anchor, keep the WHAT |
| 268 | A | R2-F10 | A | strip anchor, keep the WHAT |
| 380 | B | D-08 | A | strip anchor, keep the WHAT |
| 389 | B | D-08 | A | strip anchor, keep the WHAT |
| 393 | A | R3-F1 | A | strip anchor, keep the WHAT |
| 393 | B | D-03 | A | strip anchor, keep the WHAT |
| 401 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 402 | B | D-08 | A | strip anchor, keep the WHAT |
| 417 | A | R1-F4 | A | strip anchor, keep the WHAT |
| 417 | B | D-03 | A | strip anchor, keep the WHAT |
| 425 | A | R1-F4 | A | strip anchor, keep the WHAT |
| 425 | B | D-03 | A | strip anchor, keep the WHAT |
| 446 | A | R3-F1 | A | strip anchor, keep the WHAT |
| 446 | B | D-03 | A | strip anchor, keep the WHAT |
| 476 | A | R3-F1 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### bin/lib/task/archive.cjs (28 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 1 | B | T2 | B | delete lineage-only line, ids ride the ledger |
| 52 | A | [REVIEW P1 | A | strip anchor, keep the WHAT |
| 116 | B | F-1 | A | strip anchor, keep the WHAT |
| 144 | B | D-06 | A | strip anchor, keep the WHAT |
| 167 | B | D-07 | A | strip anchor, keep the WHAT |
| 200 | B | D-64 | A | strip anchor, keep the WHAT |
| 206 | B | D-34 | A | strip anchor, keep the WHAT |
| 230 | A | [R4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 230 | B | B-21 | A | strip anchor, keep the WHAT |
| 255 | A | [REVIEW P2 | A | strip anchor, keep the WHAT |
| 258 | B | T8 | A | strip anchor, keep the WHAT |
| 327 | B | T8 | A | strip anchor, keep the WHAT |
| 333 | B | T17 | A | strip anchor, keep the WHAT |
| 340 | A | RT3-F11 | A | strip anchor, keep the WHAT |
| 340 | B | D-14 | A | strip anchor, keep the WHAT |
| 413 | B | T5 | A | strip anchor, keep the WHAT |
| 418 | B | T18 | A | strip anchor, keep the WHAT |
| 432 | A | [REVIEW P2 | A | strip anchor, keep the WHAT |
| 438 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 442 | A | [REVIEW P2 | A | strip anchor, keep the WHAT |
| 476 | A | [REVIEW P2 | A | strip anchor, keep the WHAT |
| 485 | A | [REVIEW P1 | A | strip anchor, keep the WHAT |
| 485 | B | R-03 | A | strip anchor, keep the WHAT |
| 505 | B | T8 | A | strip anchor, keep the WHAT |
| 510 | B | F-3 | A | strip anchor, keep the WHAT |
| 547 | A | [D-0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 547 | B | T3 | A | strip anchor, keep the WHAT |
| 571 | B | F-5 | A | strip anchor, keep the WHAT |

### bin/lib/task/changelog.cjs (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 20 | B | D-07 | A | strip anchor, keep the WHAT |
| 89 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### bin/lib/task/checkpoint.cjs (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 1 | B | T2 | B | delete lineage-only line, ids ride the ledger |

### bin/lib/task/commit.cjs (38 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 1 | B | T2 | B | delete lineage-only line, ids ride the ledger |
| 27 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 27 | B | B-10 | A | strip anchor, keep the WHAT |
| 29 | B | B-22 | A | strip anchor, keep the WHAT |
| 40 | A | [R4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 43 | B | B-4 | A | strip anchor, keep the WHAT |
| 54 | B | T9 | A | strip anchor, keep the WHAT |
| 76 | B | B-22 | A | strip anchor, keep the WHAT |
| 88 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 88 | B | B-8 | A | strip anchor, keep the WHAT |
| 104 | B | D-33 | A | strip anchor, keep the WHAT |
| 134 | B | T2 | A | strip anchor, keep the WHAT |
| 192 | B | D-03 | A | strip anchor, keep the WHAT |
| 195 | A | [REVIEW P1 | A | strip anchor, keep the WHAT |
| 195 | B | R-07 | A | strip anchor, keep the WHAT |
| 225 | A | [R4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 225 | B | T2 | A | strip anchor, keep the WHAT |
| 226 | B | D-30 | A | strip anchor, keep the WHAT |
| 241 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 241 | B | T2 | A | strip anchor, keep the WHAT |
| 243 | A | [REVIEW P1 | A | strip anchor, keep the WHAT |
| 243 | B | R-07 | A | strip anchor, keep the WHAT |
| 253 | B | D-62 | A | strip anchor, keep the WHAT |
| 291 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 291 | B | T7 | A | strip anchor, keep the WHAT |
| 300 | B | R-01 | A | strip anchor, keep the WHAT |
| 310 | A | [Phase D T7 | A | strip anchor, keep the WHAT |
| 310 | B | T7 | A | strip anchor, keep the WHAT |
| 315 | A | [Phase W T1 | A | strip anchor, keep the WHAT |
| 315 | B | T16 | A | strip anchor, keep the WHAT |
| 317 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 319 | A | [Phase D T1 | A | strip anchor, keep the WHAT |
| 319 | B | T10 | A | strip anchor, keep the WHAT |
| 320 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 321 | A | [Phase D T5 | A | strip anchor, keep the WHAT |
| 321 | B | T5 | A | strip anchor, keep the WHAT |
| 322 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 344 | B | F-5 | A | strip anchor, keep the WHAT |

### bin/lib/task/context.cjs (11 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 34 | B | T4 | A | strip anchor, keep the WHAT |
| 59 | B | D-06 | A | strip anchor, keep the WHAT |
| 71 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 71 | B | B-11 | A | strip anchor, keep the WHAT |
| 78 | B | D-67 | A | strip anchor, keep the WHAT |
| 97 | B | D-19 | A | strip anchor, keep the WHAT |
| 119 | A | R3-F3 | A | strip anchor, keep the WHAT |
| 119 | B | D-41 | A | strip anchor, keep the WHAT |
| 129 | B | D-65 | A | strip anchor, keep the WHAT |
| 140 | A | R3-F3 | A | strip anchor, keep the WHAT |
| 140 | B | D-41 | A | strip anchor, keep the WHAT |

### bin/lib/task/index.cjs (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | D-03 | A | strip anchor, keep the WHAT |

### bin/lib/task/init.cjs (25 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 1 | B | T2 | B | delete lineage-only line, ids ride the ledger |
| 43 | B | D-34 | A | strip anchor, keep the WHAT |
| 59 | B | D-30 | A | strip anchor, keep the WHAT |
| 83 | B | T10 | A | strip anchor, keep the WHAT |
| 88 | B | T5 | A | strip anchor, keep the WHAT |
| 94 | A | [REVIEW P2 | A | strip anchor, keep the WHAT |
| 112 | A | [T5 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 123 | A | R4-F2 | A | strip anchor, keep the WHAT |
| 123 | B | D-34 | A | strip anchor, keep the WHAT |
| 134 | B | D-29 | A | strip anchor, keep the WHAT |
| 142 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 142 | B | T2 | A | strip anchor, keep the WHAT |
| 146 | B | D-12 | A | strip anchor, keep the WHAT |
| 150 | B | T5 | A | strip anchor, keep the WHAT |
| 152 | B | D-12 | A | strip anchor, keep the WHAT |
| 156 | A | [Phase D T5 | A | strip anchor, keep the WHAT |
| 156 | B | T5 | A | strip anchor, keep the WHAT |
| 160 | A | [Phase W T6 | A | strip anchor, keep the WHAT |
| 160 | B | T6 | A | strip anchor, keep the WHAT |
| 168 | B | D-06 | A | strip anchor, keep the WHAT |
| 192 | B | D-01 | A | strip anchor, keep the WHAT |
| 195 | B | D-22 | A | strip anchor, keep the WHAT |
| 205 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 205 | B | T2 | A | strip anchor, keep the WHAT |
| 265 | B | R-03 | A | strip anchor, keep the WHAT |

### bin/lib/task/plansnap.cjs (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 1 | B | T2 | B | delete lineage-only line, ids ride the ledger |
| 20 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 20 | B | B-21 | A | strip anchor, keep the WHAT |
| 27 | B | B-21 | A | strip anchor, keep the WHAT |

### bin/lib/task/stage.cjs (5 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 1 | B | T2 | B | delete lineage-only line, ids ride the ledger |
| 22 | A | R2-F8 | A | strip anchor, keep the WHAT |
| 22 | B | D-41 | A | strip anchor, keep the WHAT |
| 27 | A | [T6 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 27 | B | T6 | A | strip anchor, keep the WHAT |

### hooks/commit-msg.sh (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 36 | B | D-94 | A | strip anchor, keep the WHAT |

### scripts/census-dispose.sh (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 125 | A | [y/ | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 138 | A | [y/ | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 144 | A | [y/ | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 172 | A | [y/ | D | string-context audit: rewrite anchor-free or pin frozen-string |

### skills/gos-build/reference/build-patterns.md (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 142 | B | T1 | A | strip anchor, keep the WHAT |

### skills/gos-build/scripts/aggregate.sh (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 2 | B | D-12 | A | strip anchor, keep the WHAT |

### skills/gos-plan/SKILL.md (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 51 | B | D-05 | A | strip anchor, keep the WHAT |

### skills/gos-plan/examples/complete-plan.md (13 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 10 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 11 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 12 | B | T3 | B | delete lineage-only line, ids ride the ledger |
| 13 | B | T3 | B | delete lineage-only line, ids ride the ledger |
| 17 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 18 | B | T6 | B | delete lineage-only line, ids ride the ledger |
| 30 | B | T1 | A | strip anchor, keep the WHAT |
| 41 | B | T2 | A | strip anchor, keep the WHAT |
| 52 | B | T3 | A | strip anchor, keep the WHAT |
| 55 | B | T1 | A | strip anchor, keep the WHAT |
| 64 | B | T4 | A | strip anchor, keep the WHAT |
| 73 | B | T5 | A | strip anchor, keep the WHAT |
| 85 | B | T6 | B | delete lineage-only line, ids ride the ledger |

### skills/gos-plan/reference/revision-loop.md (7 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 21 | B | T4 | A | strip anchor, keep the WHAT |
| 22 | B | T4 | A | strip anchor, keep the WHAT |
| 26 | B | D-05 | A | strip anchor, keep the WHAT |
| 61 | B | D-05 | A | strip anchor, keep the WHAT |
| 62 | B | D-08 | A | strip anchor, keep the WHAT |
| 66 | B | D-05 | A | strip anchor, keep the WHAT |
| 76 | B | D-05 | A | strip anchor, keep the WHAT |

### skills/gos-plan/reference/task-decomposition.md (21 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 15 | B | T1 | A | strip anchor, keep the WHAT |
| 16 | B | T2 | A | strip anchor, keep the WHAT |
| 17 | B | T3 | B | delete lineage-only line, ids ride the ledger |
| 18 | B | T4 | B | delete lineage-only line, ids ride the ledger |
| 24 | B | T1 | A | strip anchor, keep the WHAT |
| 25 | B | T2 | A | strip anchor, keep the WHAT |
| 26 | B | T3 | A | strip anchor, keep the WHAT |
| 32 | B | T1 | A | strip anchor, keep the WHAT |
| 33 | B | T2 | B | delete lineage-only line, ids ride the ledger |
| 34 | B | T3 | A | strip anchor, keep the WHAT |
| 35 | B | T4 | A | strip anchor, keep the WHAT |
| 43 | B | T1 | A | strip anchor, keep the WHAT |
| 49 | B | T2 | A | strip anchor, keep the WHAT |
| 53 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 55 | B | T3 | B | delete lineage-only line, ids ride the ledger |
| 57 | B | T1 | A | strip anchor, keep the WHAT |
| 59 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 66 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 67 | B | T2 | B | delete lineage-only line, ids ride the ledger |
| 68 | B | T3 | B | delete lineage-only line, ids ride the ledger |
| 81 | B | T3 | A | strip anchor, keep the WHAT |

### skills/gos-plan/reference/thinking-models.md (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 18 | B | T4 | A | strip anchor, keep the WHAT |
| 21 | B | T2 | A | strip anchor, keep the WHAT |
| 47 | B | Wave 1 | A | strip anchor, keep the WHAT |
| 54 | B | T1 | A | strip anchor, keep the WHAT |

### skills/gos-project/reference/evolve.md (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 16 | B | R-03 | A | strip anchor, keep the WHAT |
| 19 | B | D-05 | A | strip anchor, keep the WHAT |

### skills/gos-project/reference/new-project.md (3 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 15 | B | R-01 | A | strip anchor, keep the WHAT |
| 20 | B | R-01 | A | strip anchor, keep the WHAT |
| 24 | B | D-01 | A | strip anchor, keep the WHAT |

### skills/gos-review/prompts/spec-reviewer.md (3 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 19 | B | D-01 | B | delete lineage-only line, ids ride the ledger |
| 20 | B | R-01 | B | delete lineage-only line, ids ride the ledger |
| 30 | B | D-01 | A | strip anchor, keep the WHAT |

### skills/gos-review/reference/review-checklists.md (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 8 | B | D-01 | B | delete lineage-only line, ids ride the ledger |

### skills/gos-router/SKILL.md (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 33 | B | R-01 | A | strip anchor, keep the WHAT |
| 61 | A | Lv0-Lv4 | A | strip anchor, keep the WHAT |
| 64 | B | D-62 | A | strip anchor, keep the WHAT |
| 95 | A | [Lv3 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### skills/gos-router/reference/gap-closure.md (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 29 | A | Lv0-Lv1 | B | delete lineage-only line, ids ride the ledger |

### skills/gos-ship/SKILL.md (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 26 | B | D-34 | A | strip anchor, keep the WHAT |

### skills/gos-ship/reference/artifact-lifecycle.md (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 17 | A | [Phase W T1 | A | strip anchor, keep the WHAT |
| 17 | B | T17 | A | strip anchor, keep the WHAT |

### skills/gos-ship/scripts/security.sh (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 8 | A | [A-Za-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 9 | B | D-11 | A | strip anchor, keep the WHAT |
| 17 | B | D-11 | A | strip anchor, keep the WHAT |
| 132 | B | D-11 | A | strip anchor, keep the WHAT |

### skills/gos-think/SKILL.md (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 29 | B | D-34 | A | strip anchor, keep the WHAT |

### skills/gos-think/examples/spec-with-redteam.md (12 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 18 | B | R-01 | A | strip anchor, keep the WHAT |
| 22 | B | D-01 | A | strip anchor, keep the WHAT |
| 24 | B | D-62 | A | strip anchor, keep the WHAT |
| 52 | B | D-02 | A | strip anchor, keep the WHAT |
| 59 | B | D-03 | A | strip anchor, keep the WHAT |
| 67 | B | T1 | A | strip anchor, keep the WHAT |
| 68 | B | T2 | A | strip anchor, keep the WHAT |
| 69 | B | T3 | A | strip anchor, keep the WHAT |
| 70 | B | T4 | A | strip anchor, keep the WHAT |
| 87 | B | D-01 | A | strip anchor, keep the WHAT |
| 94 | B | D-01 | A | strip anchor, keep the WHAT |
| 95 | B | D-03 | A | strip anchor, keep the WHAT |

### skills/gos-think/prompts/red-team-attacker.md (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 22 | A | [MISUSE/ | A | strip anchor, keep the WHAT |
| 32 | A | [Phase 6 | A | strip anchor, keep the WHAT |

### skills/gos-think/reference/codebase-mapping.md (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 38 | B | D-20 | A | strip anchor, keep the WHAT |

### skills/gos-think/reference/dialogue-protocol.md (3 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 8 | B | D-62 | A | strip anchor, keep the WHAT |
| 50 | B | D-62 | A | strip anchor, keep the WHAT |
| 113 | B | D-01 | A | strip anchor, keep the WHAT |

### skills/gos-think/reference/red-team.md (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 88 | B | F-1 | A | strip anchor, keep the WHAT |
| 89 | B | F-2 | A | strip anchor, keep the WHAT |
| 90 | B | F-3 | A | strip anchor, keep the WHAT |
| 91 | B | F-4 | A | strip anchor, keep the WHAT |

### skills/gos-think/scripts/prune-decisions.sh (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | D-23 | A | strip anchor, keep the WHAT |

### skills/gos-verify/SKILL.md (5 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 21 | B | D-36 | A | strip anchor, keep the WHAT |
| 28 | B | D-26 | A | strip anchor, keep the WHAT |
| 35 | B | D-25 | B | delete lineage-only line, ids ride the ledger |
| 41 | B | T1 | A | strip anchor, keep the WHAT |
| 42 | B | T2 | A | strip anchor, keep the WHAT |

### test/checks/gitprobe-monopoly.sh (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 2 | A | RT3-F11 | A | strip anchor, keep the WHAT |
| 2 | B | D-14 | A | strip anchor, keep the WHAT |
| 17 | B | T14 | A | strip anchor, keep the WHAT |
| 18 | B | T6 | A | strip anchor, keep the WHAT |

### test/checks/stale-verbs.sh (3 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 2 | B | R-01 | A | strip anchor, keep the WHAT |
| 76 | A | [A-Za-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 77 | A | [A-Za-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### test/fixtures/gh-stub/gh (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 2 | B | T70 | A | strip anchor, keep the WHAT |

### test/golden/pre-split/contract.txt (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 142 | A | [U2 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### test/gos-cli-tests.sh (9 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 89 | B | R-01 | B | delete lineage-only line, ids ride the ledger |
| 156 | B | R-01 | B | delete lineage-only line, ids ride the ledger |
| 317 | B | D-01 | A | strip anchor, keep the WHAT |
| 331 | B | D-03 | A | strip anchor, keep the WHAT |
| 340 | B | D-02 | A | strip anchor, keep the WHAT |
| 349 | B | F-5 | B | delete lineage-only line, ids ride the ledger |
| 364 | B | F-1 | A | strip anchor, keep the WHAT |
| 383 | B | D-11 | B | delete lineage-only line, ids ride the ledger |
| 394 | B | F-2 | B | delete lineage-only line, ids ride the ledger |

### test/pack-check.sh (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 2 | B | R-09 | A | strip anchor, keep the WHAT |

### test/run-sections.sh (16 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 45 | B | T36 | A | strip anchor, keep the WHAT |
| 64 | A | [R3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 64 | B | T9 | A | strip anchor, keep the WHAT |
| 71 | A | R4-F3 | A | strip anchor, keep the WHAT |
| 71 | B | T7 | A | strip anchor, keep the WHAT |
| 74 | A | U3-U6 | A | strip anchor, keep the WHAT |
| 74 | B | T35 | A | strip anchor, keep the WHAT |
| 76 | B | D-63 | A | strip anchor, keep the WHAT |
| 77 | B | T74 | A | strip anchor, keep the WHAT |
| 199 | B | F-1 | A | strip anchor, keep the WHAT |
| 207 | A | R4-F4 | A | strip anchor, keep the WHAT |
| 207 | B | T5 | A | strip anchor, keep the WHAT |
| 230 | A | [Phase D T1 | A | strip anchor, keep the WHAT |
| 230 | B | T10 | A | strip anchor, keep the WHAT |
| 231 | A | §7 | A | strip anchor, keep the WHAT |
| 231 | B | T12 | A | strip anchor, keep the WHAT |

### test/sections/T1-schema.test.sh (11 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T1 | A | strip anchor, keep the WHAT |
| 4 | A | W1-T1 | B | delete lineage-only line, ids ride the ledger |
| 4 | B | W1 | B | delete lineage-only line, ids ride the ledger |
| 20 | B | T1 | A | strip anchor, keep the WHAT |
| 25 | B | T1 | A | strip anchor, keep the WHAT |
| 33 | B | T1 | A | strip anchor, keep the WHAT |
| 45 | B | T1 | A | strip anchor, keep the WHAT |
| 64 | B | F-8 | A | strip anchor, keep the WHAT |
| 79 | B | T1 | A | strip anchor, keep the WHAT |
| 89 | B | T1 | A | strip anchor, keep the WHAT |
| 96 | B | T1 | A | strip anchor, keep the WHAT |

### test/sections/T10-security-e2e.test.sh (16 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T10 | A | strip anchor, keep the WHAT |
| 10 | A | [Phase W T5 | A | strip anchor, keep the WHAT |
| 10 | B | T5 | A | strip anchor, keep the WHAT |
| 66 | B | D-01 | A | strip anchor, keep the WHAT |
| 80 | B | D-12 | A | strip anchor, keep the WHAT |
| 124 | B | D-01 | A | strip anchor, keep the WHAT |
| 130 | B | T1 | A | strip anchor, keep the WHAT |
| 140 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 140 | B | T2 | A | strip anchor, keep the WHAT |
| 149 | B | D-02 | A | strip anchor, keep the WHAT |
| 155 | B | D-03 | A | strip anchor, keep the WHAT |
| 163 | B | R-02 | B | delete lineage-only line, ids ride the ledger |
| 236 | A | [REVIEW P2 | A | strip anchor, keep the WHAT |
| 240 | A | [Phase W T5 | A | strip anchor, keep the WHAT |
| 240 | B | T5 | A | strip anchor, keep the WHAT |
| 277 | A | [T4 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### test/sections/T100-navigator.test.sh (3 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | Wave 4 | A | strip anchor, keep the WHAT |
| 60 | B | D-20 | A | strip anchor, keep the WHAT |
| 99 | B | T99 | A | strip anchor, keep the WHAT |

### test/sections/T101-issue-tokens.test.sh (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T101 | A | strip anchor, keep the WHAT |
| 6 | B | R-01 | A | strip anchor, keep the WHAT |

### test/sections/T102-ai-trace.test.sh (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 6 | B | T102 | A | strip anchor, keep the WHAT |

### test/sections/T12-wiring.test.sh (16 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T12 | A | strip anchor, keep the WHAT |
| 9 | A | [Phase W T5 | A | strip anchor, keep the WHAT |
| 9 | B | T5 | A | strip anchor, keep the WHAT |
| 26 | B | T12 | A | strip anchor, keep the WHAT |
| 30 | B | T12 | A | strip anchor, keep the WHAT |
| 38 | B | T12 | A | strip anchor, keep the WHAT |
| 43 | B | T12 | A | strip anchor, keep the WHAT |
| 46 | B | T12 | A | strip anchor, keep the WHAT |
| 55 | B | T12 | A | strip anchor, keep the WHAT |
| 71 | B | T12 | A | strip anchor, keep the WHAT |
| 77 | B | T12 | A | strip anchor, keep the WHAT |
| 90 | B | T12 | A | strip anchor, keep the WHAT |
| 100 | B | T12 | A | strip anchor, keep the WHAT |
| 110 | B | T12 | A | strip anchor, keep the WHAT |
| 119 | A | [R4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 119 | B | T12 | A | strip anchor, keep the WHAT |

### test/sections/T13-semantic-contracts.test.sh (23 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T13 | A | strip anchor, keep the WHAT |
| 20 | A | [F1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 20 | B | T13 | A | strip anchor, keep the WHAT |
| 28 | A | §2 | A | strip anchor, keep the WHAT |
| 28 | B | T13 | A | strip anchor, keep the WHAT |
| 41 | A | §2 | A | strip anchor, keep the WHAT |
| 41 | B | T13 | A | strip anchor, keep the WHAT |
| 43 | A | §2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 50 | A | [F1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 52 | A | [F1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 55 | B | T13 | A | strip anchor, keep the WHAT |
| 56 | B | T46 | A | strip anchor, keep the WHAT |
| 60 | B | T13 | A | strip anchor, keep the WHAT |
| 61 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 61 | B | T2 | A | strip anchor, keep the WHAT |
| 70 | B | D-64 | A | strip anchor, keep the WHAT |
| 74 | B | T13 | A | strip anchor, keep the WHAT |
| 75 | B | T5 | A | strip anchor, keep the WHAT |
| 88 | B | T13 | A | strip anchor, keep the WHAT |
| 89 | B | D-09 | A | strip anchor, keep the WHAT |
| 99 | A | [R1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 99 | B | T13 | A | strip anchor, keep the WHAT |
| 122 | B | T13 | A | strip anchor, keep the WHAT |

### test/sections/T14-state-b.test.sh (24 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T14 | A | strip anchor, keep the WHAT |
| 8 | A | [Phase W T5 | A | strip anchor, keep the WHAT |
| 8 | B | T5 | A | strip anchor, keep the WHAT |
| 22 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 65 | B | D-01 | A | strip anchor, keep the WHAT |
| 90 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 100 | A | [B-2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 105 | B | Wave 1 | B | delete lineage-only line, ids ride the ledger |
| 107 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 134 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 143 | B | Wave 1 | B | delete lineage-only line, ids ride the ledger |
| 145 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 158 | B | Wave 1 | B | delete lineage-only line, ids ride the ledger |
| 160 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 182 | A | [B-2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 188 | B | Wave 1 | B | delete lineage-only line, ids ride the ledger |
| 190 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 194 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 222 | B | Wave 1 | B | delete lineage-only line, ids ride the ledger |
| 240 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 285 | A | [F1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 299 | B | Wave 1 | B | delete lineage-only line, ids ride the ledger |
| 301 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 338 | A | [R4 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### test/sections/T15-lessons.test.sh (29 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T15 | A | strip anchor, keep the WHAT |
| 4 | B | D-64 | A | strip anchor, keep the WHAT |
| 7 | A | [R3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 33 | B | T15 | B | delete lineage-only line, ids ride the ledger |
| 40 | B | T15 | A | strip anchor, keep the WHAT |
| 62 | B | T15 | A | strip anchor, keep the WHAT |
| 80 | B | T15 | A | strip anchor, keep the WHAT |
| 90 | B | T15 | A | strip anchor, keep the WHAT |
| 101 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 101 | B | T15 | B | delete lineage-only line, ids ride the ledger |
| 110 | B | T15 | B | delete lineage-only line, ids ride the ledger |
| 120 | B | T15 | A | strip anchor, keep the WHAT |
| 137 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 137 | B | T15 | A | strip anchor, keep the WHAT |
| 152 | B | T15 | A | strip anchor, keep the WHAT |
| 165 | B | T15 | A | strip anchor, keep the WHAT |
| 188 | B | T15 | A | strip anchor, keep the WHAT |
| 219 | B | D-09 | A | strip anchor, keep the WHAT |
| 229 | B | T15 | A | strip anchor, keep the WHAT |
| 248 | B | T15 | A | strip anchor, keep the WHAT |
| 276 | B | T15 | A | strip anchor, keep the WHAT |
| 313 | B | T15 | A | strip anchor, keep the WHAT |
| 342 | B | T15 | A | strip anchor, keep the WHAT |
| 353 | B | T15 | A | strip anchor, keep the WHAT |
| 358 | B | T15 | A | strip anchor, keep the WHAT |
| 366 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 366 | B | T15 | A | strip anchor, keep the WHAT |
| 375 | B | T15 | A | strip anchor, keep the WHAT |
| 395 | B | T15 | A | strip anchor, keep the WHAT |

### test/sections/T16-truth.test.sh (20 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T16 | A | strip anchor, keep the WHAT |
| 27 | B | T16 | A | strip anchor, keep the WHAT |
| 44 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 44 | B | T16 | A | strip anchor, keep the WHAT |
| 56 | B | T16 | A | strip anchor, keep the WHAT |
| 71 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 71 | B | T16 | A | strip anchor, keep the WHAT |
| 75 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 75 | B | T16 | A | strip anchor, keep the WHAT |
| 79 | A | [R2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 79 | B | T16 | A | strip anchor, keep the WHAT |
| 91 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 91 | B | T16 | A | strip anchor, keep the WHAT |
| 118 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 118 | B | T16 | A | strip anchor, keep the WHAT |
| 123 | B | T3 | A | strip anchor, keep the WHAT |
| 129 | A | [R4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 129 | B | T16 | A | strip anchor, keep the WHAT |
| 137 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 137 | B | T16 | A | strip anchor, keep the WHAT |

### test/sections/T17-semantic-engine.test.sh (23 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T17 | A | strip anchor, keep the WHAT |
| 5 | A | W3-T5 | A | strip anchor, keep the WHAT |
| 5 | B | W3 | A | strip anchor, keep the WHAT |
| 10 | A | [Phase W T5 | A | strip anchor, keep the WHAT |
| 10 | B | T5 | A | strip anchor, keep the WHAT |
| 21 | B | D-01 | A | strip anchor, keep the WHAT |
| 29 | B | D-01 | B | delete lineage-only line, ids ride the ledger |
| 42 | B | Wave 1 | B | delete lineage-only line, ids ride the ledger |
| 44 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 55 | A | [B-2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 57 | B | D-99 | A | strip anchor, keep the WHAT |
| 64 | B | D-02 | A | strip anchor, keep the WHAT |
| 73 | B | R-99 | A | strip anchor, keep the WHAT |
| 112 | A | [B-4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 139 | B | T2 | A | strip anchor, keep the WHAT |
| 149 | B | Wave 1 | B | delete lineage-only line, ids ride the ledger |
| 151 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 178 | B | Wave 1 | B | delete lineage-only line, ids ride the ledger |
| 180 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 189 | A | [B-5 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 221 | B | T2 | A | strip anchor, keep the WHAT |
| 233 | A | [B-4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 251 | A | [B-6 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### test/sections/T18-f1-gate-lessons.test.sh (20 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T18 | A | strip anchor, keep the WHAT |
| 4 | A | R4-F7 | B | delete lineage-only line, ids ride the ledger |
| 4 | B | D-34 | B | delete lineage-only line, ids ride the ledger |
| 5 | A | [R3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 42 | B | T18 | A | strip anchor, keep the WHAT |
| 48 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 48 | B | T18 | A | strip anchor, keep the WHAT |
| 62 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 62 | B | T18 | A | strip anchor, keep the WHAT |
| 90 | B | T18 | A | strip anchor, keep the WHAT |
| 103 | A | [B-8 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 103 | B | T18 | A | strip anchor, keep the WHAT |
| 122 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 122 | B | T18 | A | strip anchor, keep the WHAT |
| 146 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 146 | B | T18 | A | strip anchor, keep the WHAT |
| 156 | A | [R4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 156 | B | T18 | A | strip anchor, keep the WHAT |
| 163 | B | Wave 1 | B | delete lineage-only line, ids ride the ledger |
| 164 | B | T1 | B | delete lineage-only line, ids ride the ledger |

### test/sections/T19-mounting.test.sh (31 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T19 | A | strip anchor, keep the WHAT |
| 4 | A | R4-F1 | B | delete lineage-only line, ids ride the ledger |
| 4 | B | D-33 | B | delete lineage-only line, ids ride the ledger |
| 8 | A | [Phase W T5 | A | strip anchor, keep the WHAT |
| 8 | B | T5 | A | strip anchor, keep the WHAT |
| 33 | B | B-9 | A | strip anchor, keep the WHAT |
| 35 | B | B-9 | A | strip anchor, keep the WHAT |
| 57 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 57 | B | T19 | A | strip anchor, keep the WHAT |
| 71 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 71 | B | T19 | A | strip anchor, keep the WHAT |
| 77 | A | [B-1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 77 | B | T19 | A | strip anchor, keep the WHAT |
| 87 | A | [R4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 87 | B | T19 | A | strip anchor, keep the WHAT |
| 91 | B | T19 | A | strip anchor, keep the WHAT |
| 110 | B | T19 | A | strip anchor, keep the WHAT |
| 121 | B | T19 | A | strip anchor, keep the WHAT |
| 132 | A | [D-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 132 | B | T19 | A | strip anchor, keep the WHAT |
| 134 | A | §3 | A | strip anchor, keep the WHAT |
| 146 | A | [Phase W T6 | A | strip anchor, keep the WHAT |
| 146 | B | T6 | A | strip anchor, keep the WHAT |
| 153 | A | [B-3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 153 | B | T19 | A | strip anchor, keep the WHAT |
| 159 | A | [B-2 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 159 | B | T19 | A | strip anchor, keep the WHAT |
| 166 | A | [F1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 166 | B | T19 | A | strip anchor, keep the WHAT |
| 173 | A | [B-4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 173 | B | T19 | A | strip anchor, keep the WHAT |

### test/sections/T2-project.test.sh (8 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T2 | A | strip anchor, keep the WHAT |
| 4 | A | W1-T2 | B | delete lineage-only line, ids ride the ledger |
| 4 | B | W1 | B | delete lineage-only line, ids ride the ledger |
| 19 | B | T2 | A | strip anchor, keep the WHAT |
| 31 | B | T2 | A | strip anchor, keep the WHAT |
| 42 | B | T2 | A | strip anchor, keep the WHAT |
| 52 | B | T2 | A | strip anchor, keep the WHAT |
| 61 | B | T2 | A | strip anchor, keep the WHAT |

### test/sections/T20-map-scan.test.sh (11 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T20 | A | strip anchor, keep the WHAT |
| 5 | B | T2 | A | strip anchor, keep the WHAT |
| 82 | B | T20 | A | strip anchor, keep the WHAT |
| 92 | B | T20 | A | strip anchor, keep the WHAT |
| 98 | A | [Phase P T2 | A | strip anchor, keep the WHAT |
| 136 | B | T20 | A | strip anchor, keep the WHAT |
| 143 | B | T20 | A | strip anchor, keep the WHAT |
| 156 | A | [Phase P T2 | A | strip anchor, keep the WHAT |
| 162 | B | T20 | A | strip anchor, keep the WHAT |
| 169 | B | T20 | A | strip anchor, keep the WHAT |
| 185 | B | T20 | A | strip anchor, keep the WHAT |

### test/sections/T21-map-closure.test.sh (16 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T21 | A | strip anchor, keep the WHAT |
| 38 | B | T21 | A | strip anchor, keep the WHAT |
| 51 | B | T21 | B | delete lineage-only line, ids ride the ledger |
| 63 | B | T21 | A | strip anchor, keep the WHAT |
| 74 | B | T21 | A | strip anchor, keep the WHAT |
| 82 | B | T21 | A | strip anchor, keep the WHAT |
| 90 | B | T21 | A | strip anchor, keep the WHAT |
| 96 | B | T21 | A | strip anchor, keep the WHAT |
| 107 | A | R3-F12 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 112 | B | T21 | A | strip anchor, keep the WHAT |
| 128 | B | T21 | A | strip anchor, keep the WHAT |
| 138 | B | T21 | A | strip anchor, keep the WHAT |
| 148 | B | T21 | A | strip anchor, keep the WHAT |
| 158 | B | T21 | A | strip anchor, keep the WHAT |
| 166 | B | T21 | A | strip anchor, keep the WHAT |
| 175 | B | T21 | A | strip anchor, keep the WHAT |

### test/sections/T22-map-gate-impact.test.sh (14 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T22 | A | strip anchor, keep the WHAT |
| 8 | A | [Phase W T5 | A | strip anchor, keep the WHAT |
| 8 | B | T5 | A | strip anchor, keep the WHAT |
| 19 | B | T1 | A | strip anchor, keep the WHAT |
| 26 | B | D-01 | B | delete lineage-only line, ids ride the ledger |
| 39 | B | Wave 1 | B | delete lineage-only line, ids ride the ledger |
| 41 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 62 | B | T22 | A | strip anchor, keep the WHAT |
| 73 | B | T22 | A | strip anchor, keep the WHAT |
| 86 | B | T22 | A | strip anchor, keep the WHAT |
| 94 | B | T22 | A | strip anchor, keep the WHAT |
| 105 | B | T22 | A | strip anchor, keep the WHAT |
| 118 | B | T22 | A | strip anchor, keep the WHAT |
| 133 | B | T22 | A | strip anchor, keep the WHAT |

### test/sections/T23-concerns.test.sh (16 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T23 | A | strip anchor, keep the WHAT |
| 8 | A | [Phase W T5 | A | strip anchor, keep the WHAT |
| 8 | B | T5 | A | strip anchor, keep the WHAT |
| 24 | B | T23 | A | strip anchor, keep the WHAT |
| 33 | B | T23 | A | strip anchor, keep the WHAT |
| 38 | B | T23 | A | strip anchor, keep the WHAT |
| 46 | B | T23 | A | strip anchor, keep the WHAT |
| 55 | B | T23 | A | strip anchor, keep the WHAT |
| 66 | A | [T6 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 66 | B | T23 | A | strip anchor, keep the WHAT |
| 92 | B | T23 | A | strip anchor, keep the WHAT |
| 106 | B | T23 | A | strip anchor, keep the WHAT |
| 113 | B | T23 | A | strip anchor, keep the WHAT |
| 118 | B | T23 | A | strip anchor, keep the WHAT |
| 124 | B | T23 | A | strip anchor, keep the WHAT |
| 133 | B | T23 | A | strip anchor, keep the WHAT |

### test/sections/T24-map-contracts.test.sh (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T24 | A | strip anchor, keep the WHAT |

### test/sections/T25-map-selfcheck.test.sh (6 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T25 | A | strip anchor, keep the WHAT |
| 17 | B | T25 | A | strip anchor, keep the WHAT |
| 18 | B | T46 | A | strip anchor, keep the WHAT |
| 54 | B | T25 | A | strip anchor, keep the WHAT |
| 55 | B | T46 | A | strip anchor, keep the WHAT |
| 70 | B | T25 | A | strip anchor, keep the WHAT |

### test/sections/T26-nav-hints.test.sh (8 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T26 | A | strip anchor, keep the WHAT |
| 44 | B | T26 | A | strip anchor, keep the WHAT |
| 54 | B | T26 | A | strip anchor, keep the WHAT |
| 62 | B | T26 | A | strip anchor, keep the WHAT |
| 71 | A | [phase-ux L3 | A | strip anchor, keep the WHAT |
| 74 | B | T26 | A | strip anchor, keep the WHAT |
| 85 | B | T26 | A | strip anchor, keep the WHAT |
| 97 | B | T26 | A | strip anchor, keep the WHAT |

### test/sections/T27-archive-slug.test.sh (6 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T27 | A | strip anchor, keep the WHAT |
| 7 | A | [Phase W T5 | A | strip anchor, keep the WHAT |
| 7 | B | T5 | A | strip anchor, keep the WHAT |
| 25 | B | T27 | A | strip anchor, keep the WHAT |
| 35 | B | T27 | A | strip anchor, keep the WHAT |
| 50 | B | T27 | A | strip anchor, keep the WHAT |

### test/sections/T28-router-state-first.test.sh (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T28 | A | strip anchor, keep the WHAT |
| 19 | B | T28 | A | strip anchor, keep the WHAT |
| 27 | B | T28 | A | strip anchor, keep the WHAT |
| 35 | B | T28 | A | strip anchor, keep the WHAT |

### test/sections/T29-command-registry.test.sh (22 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T29 | A | strip anchor, keep the WHAT |
| 4 | A | §4 | B | delete lineage-only line, ids ride the ledger |
| 4 | B | T5 | B | delete lineage-only line, ids ride the ledger |
| 17 | A | R4-F2 | A | strip anchor, keep the WHAT |
| 40 | B | T29 | A | strip anchor, keep the WHAT |
| 53 | B | T29 | A | strip anchor, keep the WHAT |
| 66 | B | T29 | A | strip anchor, keep the WHAT |
| 82 | A | R2-F7 | A | strip anchor, keep the WHAT |
| 103 | B | T29 | A | strip anchor, keep the WHAT |
| 104 | A | §4 | A | strip anchor, keep the WHAT |
| 104 | B | T12 | A | strip anchor, keep the WHAT |
| 106 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 116 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 117 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 122 | B | T29 | A | strip anchor, keep the WHAT |
| 146 | B | T29 | A | strip anchor, keep the WHAT |
| 156 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 162 | B | T29 | A | strip anchor, keep the WHAT |
| 180 | B | T29 | A | strip anchor, keep the WHAT |
| 234 | B | T29 | A | strip anchor, keep the WHAT |
| 248 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 265 | B | T29 | A | strip anchor, keep the WHAT |

### test/sections/T3-decision.test.sh (20 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T3 | A | strip anchor, keep the WHAT |
| 4 | A | W2-T3 | B | delete lineage-only line, ids ride the ledger |
| 4 | B | W2 | B | delete lineage-only line, ids ride the ledger |
| 8 | A | [Phase W T5 | A | strip anchor, keep the WHAT |
| 8 | B | T5 | A | strip anchor, keep the WHAT |
| 24 | B | T3 | A | strip anchor, keep the WHAT |
| 35 | B | T3 | B | delete lineage-only line, ids ride the ledger |
| 40 | B | T3 | A | strip anchor, keep the WHAT |
| 45 | B | T3 | B | delete lineage-only line, ids ride the ledger |
| 50 | B | T3 | B | delete lineage-only line, ids ride the ledger |
| 54 | B | T3 | A | strip anchor, keep the WHAT |
| 58 | B | T3 | A | strip anchor, keep the WHAT |
| 63 | B | T3 | A | strip anchor, keep the WHAT |
| 76 | B | D-99 | A | strip anchor, keep the WHAT |
| 85 | B | D-01 | A | strip anchor, keep the WHAT |
| 89 | B | T3 | B | delete lineage-only line, ids ride the ledger |
| 114 | B | T3 | B | delete lineage-only line, ids ride the ledger |
| 122 | B | T3 | A | strip anchor, keep the WHAT |
| 130 | B | T3 | B | delete lineage-only line, ids ride the ledger |
| 150 | B | T3 | B | delete lineage-only line, ids ride the ledger |

### test/sections/T30-map-edges.test.sh (15 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T30 | A | strip anchor, keep the WHAT |
| 4 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 37 | B | T30 | A | strip anchor, keep the WHAT |
| 50 | B | T30 | A | strip anchor, keep the WHAT |
| 56 | B | T30 | B | delete lineage-only line, ids ride the ledger |
| 61 | B | T30 | A | strip anchor, keep the WHAT |
| 68 | B | T30 | A | strip anchor, keep the WHAT |
| 73 | B | T30 | A | strip anchor, keep the WHAT |
| 97 | B | T30 | A | strip anchor, keep the WHAT |
| 108 | B | T30 | A | strip anchor, keep the WHAT |
| 119 | B | T30 | A | strip anchor, keep the WHAT |
| 126 | B | T30 | A | strip anchor, keep the WHAT |
| 136 | B | T30 | A | strip anchor, keep the WHAT |
| 146 | A | [Phase P T2 | A | strip anchor, keep the WHAT |
| 160 | B | T30 | A | strip anchor, keep the WHAT |

### test/sections/T31-map-gate.test.sh (18 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T31 | A | strip anchor, keep the WHAT |
| 4 | B | R-07 | A | strip anchor, keep the WHAT |
| 5 | B | T5 | B | delete lineage-only line, ids ride the ledger |
| 8 | A | [Phase W T5 | A | strip anchor, keep the WHAT |
| 8 | B | T5 | A | strip anchor, keep the WHAT |
| 35 | B | T31 | A | strip anchor, keep the WHAT |
| 39 | B | T31 | A | strip anchor, keep the WHAT |
| 49 | B | T31 | A | strip anchor, keep the WHAT |
| 56 | B | T31 | A | strip anchor, keep the WHAT |
| 60 | B | T31 | A | strip anchor, keep the WHAT |
| 67 | B | T31 | A | strip anchor, keep the WHAT |
| 77 | B | T31 | A | strip anchor, keep the WHAT |
| 84 | B | T31 | A | strip anchor, keep the WHAT |
| 92 | B | T31 | A | strip anchor, keep the WHAT |
| 97 | B | T31 | A | strip anchor, keep the WHAT |
| 105 | B | T31 | A | strip anchor, keep the WHAT |
| 119 | B | T22 | B | delete lineage-only line, ids ride the ledger |
| 125 | B | D-01 | B | delete lineage-only line, ids ride the ledger |

### test/sections/T32-map-render.test.sh (11 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T32 | A | strip anchor, keep the WHAT |
| 4 | B | R-03 | A | strip anchor, keep the WHAT |
| 11 | B | T32 | A | strip anchor, keep the WHAT |
| 55 | B | T32 | A | strip anchor, keep the WHAT |
| 61 | B | T32 | A | strip anchor, keep the WHAT |
| 75 | B | T32 | A | strip anchor, keep the WHAT |
| 82 | B | T32 | A | strip anchor, keep the WHAT |
| 91 | B | T32 | A | strip anchor, keep the WHAT |
| 96 | B | T32 | A | strip anchor, keep the WHAT |
| 120 | B | T32 | A | strip anchor, keep the WHAT |
| 126 | B | T32 | A | strip anchor, keep the WHAT |

### test/sections/T33-map-manifest.test.sh (16 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | A | [R-0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 3 | B | T33 | A | strip anchor, keep the WHAT |
| 6 | A | [Phase W T5 | A | strip anchor, keep the WHAT |
| 6 | B | T5 | A | strip anchor, keep the WHAT |
| 25 | B | T22 | B | delete lineage-only line, ids ride the ledger |
| 31 | B | D-01 | B | delete lineage-only line, ids ride the ledger |
| 45 | A | §3 | A | strip anchor, keep the WHAT |
| 60 | B | T33 | A | strip anchor, keep the WHAT |
| 67 | B | T33 | A | strip anchor, keep the WHAT |
| 75 | B | T33 | A | strip anchor, keep the WHAT |
| 81 | B | T33 | A | strip anchor, keep the WHAT |
| 93 | B | T33 | A | strip anchor, keep the WHAT |
| 98 | B | T33 | A | strip anchor, keep the WHAT |
| 99 | B | T33 | A | strip anchor, keep the WHAT |
| 102 | B | B-5 | A | strip anchor, keep the WHAT |
| 111 | B | T33 | A | strip anchor, keep the WHAT |

### test/sections/T34-map-tsection.test.sh (7 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T34 | A | strip anchor, keep the WHAT |
| 4 | B | R-10 | A | strip anchor, keep the WHAT |
| 16 | B | T34 | A | strip anchor, keep the WHAT |
| 43 | B | T34 | A | strip anchor, keep the WHAT |
| 48 | B | T34 | A | strip anchor, keep the WHAT |
| 55 | B | T34 | A | strip anchor, keep the WHAT |
| 60 | B | T34 | A | strip anchor, keep the WHAT |

### test/sections/T35-codemap-coverage.test.sh (6 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T35 | A | strip anchor, keep the WHAT |
| 39 | B | T35 | A | strip anchor, keep the WHAT |
| 45 | B | T35 | A | strip anchor, keep the WHAT |
| 51 | B | D-20 | A | strip anchor, keep the WHAT |
| 61 | B | T35 | A | strip anchor, keep the WHAT |
| 72 | B | T35 | A | strip anchor, keep the WHAT |

### test/sections/T35-u-closure-summary.test.sh (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T4 | A | strip anchor, keep the WHAT |

### test/sections/T35-u-init.test.sh (10 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T35 | A | strip anchor, keep the WHAT |
| 4 | A | T1-T4 | B | delete lineage-only line, ids ride the ledger |
| 4 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 7 | B | T7 | A | strip anchor, keep the WHAT |
| 28 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 61 | B | T1 | A | strip anchor, keep the WHAT |
| 103 | B | T2 | B | delete lineage-only line, ids ride the ledger |
| 142 | B | T3 | B | delete lineage-only line, ids ride the ledger |
| 170 | B | T4 | B | delete lineage-only line, ids ride the ledger |
| 171 | A | R2-M1 | A | strip anchor, keep the WHAT |

### test/sections/T35-u-negative.test.sh (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T7 | B | delete lineage-only line, ids ride the ledger |

### test/sections/T35-u-status.test.sh (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | A | R4-F8 | A | strip anchor, keep the WHAT |
| 4 | B | T5 | A | strip anchor, keep the WHAT |

### test/sections/T36-callgraph.test.sh (14 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T36 | A | strip anchor, keep the WHAT |
| 4 | B | D-36 | B | delete lineage-only line, ids ride the ledger |
| 42 | A | [REVIEW M3 | A | strip anchor, keep the WHAT |
| 45 | B | T36 | A | strip anchor, keep the WHAT |
| 55 | B | T36 | A | strip anchor, keep the WHAT |
| 82 | B | T36 | A | strip anchor, keep the WHAT |
| 99 | B | R-03 | A | strip anchor, keep the WHAT |
| 118 | B | T36 | A | strip anchor, keep the WHAT |
| 122 | B | T36 | A | strip anchor, keep the WHAT |
| 146 | B | T36 | A | strip anchor, keep the WHAT |
| 181 | B | T36 | A | strip anchor, keep the WHAT |
| 191 | B | D-29 | A | strip anchor, keep the WHAT |
| 232 | B | T36 | A | strip anchor, keep the WHAT |
| 248 | B | T36 | A | strip anchor, keep the WHAT |

### test/sections/T37-phase-ux.test.sh (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T37 | A | strip anchor, keep the WHAT |
| 56 | A | [L3 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### test/sections/T38-annotation-extensions.test.sh (10 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 5 | B | T38 | A | strip anchor, keep the WHAT |
| 25 | B | T38 | A | strip anchor, keep the WHAT |
| 38 | B | T38 | A | strip anchor, keep the WHAT |
| 43 | B | T38 | A | strip anchor, keep the WHAT |
| 49 | B | T38 | A | strip anchor, keep the WHAT |
| 63 | B | T38 | A | strip anchor, keep the WHAT |
| 74 | B | T38 | A | strip anchor, keep the WHAT |
| 82 | B | T38 | A | strip anchor, keep the WHAT |
| 88 | B | T38 | A | strip anchor, keep the WHAT |
| 95 | B | T38 | A | strip anchor, keep the WHAT |

### test/sections/T39-render-park.test.sh (22 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T39 | A | strip anchor, keep the WHAT |
| 5 | A | T1-T12 | B | delete lineage-only line, ids ride the ledger |
| 5 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 49 | B | T90 | A | strip anchor, keep the WHAT |
| 84 | B | T1 | A | strip anchor, keep the WHAT |
| 92 | B | T2 | A | strip anchor, keep the WHAT |
| 100 | B | T5 | A | strip anchor, keep the WHAT |
| 120 | B | T2 | A | strip anchor, keep the WHAT |
| 126 | B | T3 | A | strip anchor, keep the WHAT |
| 133 | B | T11 | A | strip anchor, keep the WHAT |
| 137 | B | T8 | B | delete lineage-only line, ids ride the ledger |
| 142 | B | T6 | A | strip anchor, keep the WHAT |
| 153 | B | T4 | A | strip anchor, keep the WHAT |
| 161 | B | T6 | A | strip anchor, keep the WHAT |
| 168 | B | T7 | A | strip anchor, keep the WHAT |
| 182 | B | T10 | A | strip anchor, keep the WHAT |
| 188 | B | Wave 1 | B | delete lineage-only line, ids ride the ledger |
| 190 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 201 | B | T7 | A | strip anchor, keep the WHAT |
| 206 | B | T9 | A | strip anchor, keep the WHAT |
| 223 | B | T11 | A | strip anchor, keep the WHAT |
| 227 | B | T12 | A | strip anchor, keep the WHAT |

### test/sections/T4-requirement.test.sh (13 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T4 | A | strip anchor, keep the WHAT |
| 4 | B | Wave 2 | B | delete lineage-only line, ids ride the ledger |
| 31 | B | T4 | A | strip anchor, keep the WHAT |
| 39 | B | T4 | B | delete lineage-only line, ids ride the ledger |
| 44 | B | T4 | A | strip anchor, keep the WHAT |
| 49 | B | T4 | A | strip anchor, keep the WHAT |
| 54 | B | T4 | A | strip anchor, keep the WHAT |
| 61 | B | T4 | A | strip anchor, keep the WHAT |
| 68 | B | T4 | B | delete lineage-only line, ids ride the ledger |
| 77 | B | T4 | B | delete lineage-only line, ids ride the ledger |
| 82 | B | T4 | A | strip anchor, keep the WHAT |
| 89 | B | T4 | A | strip anchor, keep the WHAT |
| 94 | B | T4 | A | strip anchor, keep the WHAT |

### test/sections/T40-paths-registry.test.sh (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T40 | A | strip anchor, keep the WHAT |
| 23 | B | T40 | A | strip anchor, keep the WHAT |
| 30 | B | T40 | A | strip anchor, keep the WHAT |
| 76 | B | T40 | A | strip anchor, keep the WHAT |

### test/sections/T41-paths-cmd.test.sh (6 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T41 | A | strip anchor, keep the WHAT |
| 30 | B | T41 | A | strip anchor, keep the WHAT |
| 42 | B | T41 | A | strip anchor, keep the WHAT |
| 71 | B | T41 | A | strip anchor, keep the WHAT |
| 103 | B | T41 | A | strip anchor, keep the WHAT |
| 126 | B | T41 | A | strip anchor, keep the WHAT |

### test/sections/T42-context-paths.test.sh (7 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T42 | A | strip anchor, keep the WHAT |
| 39 | B | T42 | A | strip anchor, keep the WHAT |
| 59 | B | T42 | A | strip anchor, keep the WHAT |
| 67 | B | T42 | A | strip anchor, keep the WHAT |
| 85 | B | T42 | A | strip anchor, keep the WHAT |
| 100 | B | T42 | A | strip anchor, keep the WHAT |
| 119 | B | T42 | A | strip anchor, keep the WHAT |

### test/sections/T43-orphan-gate.test.sh (9 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T43 | A | strip anchor, keep the WHAT |
| 25 | B | T43 | A | strip anchor, keep the WHAT |
| 35 | B | T43 | A | strip anchor, keep the WHAT |
| 46 | B | T43 | A | strip anchor, keep the WHAT |
| 53 | B | T43 | A | strip anchor, keep the WHAT |
| 63 | B | T43 | A | strip anchor, keep the WHAT |
| 80 | B | T43 | A | strip anchor, keep the WHAT |
| 91 | B | T43 | A | strip anchor, keep the WHAT |
| 102 | B | T43 | A | strip anchor, keep the WHAT |

### test/sections/T44-static-splice.test.sh (5 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T44 | A | strip anchor, keep the WHAT |
| 4 | B | T5 | A | strip anchor, keep the WHAT |
| 32 | A | [T5 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 50 | B | T44 | A | strip anchor, keep the WHAT |
| 51 | B | T46 | A | strip anchor, keep the WHAT |

### test/sections/T45-ship-transaction.test.sh (9 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T45 | A | strip anchor, keep the WHAT |
| 34 | B | T45 | A | strip anchor, keep the WHAT |
| 43 | A | [T4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 43 | B | T45 | A | strip anchor, keep the WHAT |
| 57 | B | T45 | A | strip anchor, keep the WHAT |
| 70 | B | T45 | A | strip anchor, keep the WHAT |
| 84 | B | T45 | A | strip anchor, keep the WHAT |
| 97 | B | T45 | A | strip anchor, keep the WHAT |
| 109 | B | T45 | A | strip anchor, keep the WHAT |

### test/sections/T46-module-structure.test.sh (5 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T46 | A | strip anchor, keep the WHAT |
| 238 | B | T46 | A | strip anchor, keep the WHAT |
| 243 | B | T46 | A | strip anchor, keep the WHAT |
| 250 | B | T46 | A | strip anchor, keep the WHAT |
| 256 | B | T46 | A | strip anchor, keep the WHAT |

### test/sections/T47-module-require-direction.test.sh (8 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T47 | A | strip anchor, keep the WHAT |
| 5 | B | T46 | A | strip anchor, keep the WHAT |
| 6 | B | T36 | A | strip anchor, keep the WHAT |
| 19 | B | T47 | A | strip anchor, keep the WHAT |
| 24 | B | T47 | A | strip anchor, keep the WHAT |
| 39 | B | T47 | A | strip anchor, keep the WHAT |
| 59 | B | T47 | A | strip anchor, keep the WHAT |
| 65 | B | T47 | A | strip anchor, keep the WHAT |

### test/sections/T48-byname-tiers.test.sh (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T48 | A | strip anchor, keep the WHAT |
| 64 | B | T48 | A | strip anchor, keep the WHAT |

### test/sections/T49-baseline-c4.test.sh (6 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T49 | A | strip anchor, keep the WHAT |
| 22 | B | T49 | A | strip anchor, keep the WHAT |
| 35 | B | T49 | A | strip anchor, keep the WHAT |
| 42 | B | T49 | A | strip anchor, keep the WHAT |
| 47 | B | T49 | A | strip anchor, keep the WHAT |
| 61 | B | T49 | A | strip anchor, keep the WHAT |

### test/sections/T5-guard.test.sh (17 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T5 | A | strip anchor, keep the WHAT |
| 4 | A | W3-T5 | B | delete lineage-only line, ids ride the ledger |
| 4 | B | W3 | B | delete lineage-only line, ids ride the ledger |
| 21 | B | T5 | A | strip anchor, keep the WHAT |
| 28 | B | T5 | A | strip anchor, keep the WHAT |
| 41 | B | T5 | A | strip anchor, keep the WHAT |
| 48 | B | T5 | A | strip anchor, keep the WHAT |
| 53 | B | D-12 | A | strip anchor, keep the WHAT |
| 65 | A | [T4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 65 | B | T5 | A | strip anchor, keep the WHAT |
| 67 | B | T95 | A | strip anchor, keep the WHAT |
| 76 | B | T5 | A | strip anchor, keep the WHAT |
| 92 | B | T5 | A | strip anchor, keep the WHAT |
| 108 | B | T5 | A | strip anchor, keep the WHAT |
| 112 | B | T5 | A | strip anchor, keep the WHAT |
| 116 | A | [Phase C/ | A | strip anchor, keep the WHAT |
| 116 | B | T5 | A | strip anchor, keep the WHAT |

### test/sections/T50-archive-transaction.test.sh (5 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T50 | B | delete lineage-only line, ids ride the ledger |
| 37 | B | T50 | A | strip anchor, keep the WHAT |
| 56 | B | T50 | A | strip anchor, keep the WHAT |
| 76 | B | T50 | A | strip anchor, keep the WHAT |
| 94 | B | T50 | A | strip anchor, keep the WHAT |

### test/sections/T51-commit-guard.test.sh (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T51 | A | strip anchor, keep the WHAT |
| 51 | B | D-17 | A | strip anchor, keep the WHAT |

### test/sections/T52-gitseed-render.test.sh (6 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T52 | A | strip anchor, keep the WHAT |
| 58 | A | [A-Z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 65 | A | [A-Z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 85 | B | R-04 | B | delete lineage-only line, ids ride the ledger |
| 99 | A | R4-F7 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 107 | B | R-03 | A | strip anchor, keep the WHAT |

### test/sections/T53-changelog-core.test.sh (3 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T53 | A | strip anchor, keep the WHAT |
| 5 | B | T54 | A | strip anchor, keep the WHAT |
| 220 | A | [v1 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### test/sections/T54-changelog-add.test.sh (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T54 | A | strip anchor, keep the WHAT |
| 9 | B | T35 | A | strip anchor, keep the WHAT |

### test/sections/T55-changelog-lint.test.sh (5 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T55 | A | strip anchor, keep the WHAT |
| 5 | B | R-06 | A | strip anchor, keep the WHAT |
| 8 | B | R-08 | A | strip anchor, keep the WHAT |
| 9 | A | R4-F12 | A | strip anchor, keep the WHAT |
| 109 | A | R4-F12 | A | strip anchor, keep the WHAT |

### test/sections/T56-init-git.test.sh (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T56 | A | strip anchor, keep the WHAT |
| 17 | B | T35 | A | strip anchor, keep the WHAT |

### test/sections/T57-archive-single-track.test.sh (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T57 | A | strip anchor, keep the WHAT |

### test/sections/T6-brownfield.test.sh (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T6 | B | delete lineage-only line, ids ride the ledger |
| 18 | B | T6 | A | strip anchor, keep the WHAT |
| 33 | B | T6 | A | strip anchor, keep the WHAT |
| 39 | B | T6 | A | strip anchor, keep the WHAT |

### test/sections/T60-commitlint-hook.test.sh (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T60 | A | strip anchor, keep the WHAT |
| 112 | A | D6-D8 | A | strip anchor, keep the WHAT |
| 149 | B | D-94 | A | strip anchor, keep the WHAT |
| 192 | B | D-94 | A | strip anchor, keep the WHAT |

### test/sections/T61-gate-wiring.test.sh (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T61 | A | strip anchor, keep the WHAT |

### test/sections/T63-cli-wiring.test.sh (3 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T63 | A | strip anchor, keep the WHAT |
| 14 | B | T29 | A | strip anchor, keep the WHAT |
| 81 | B | T29 | A | strip anchor, keep the WHAT |

### test/sections/T64-context-template-paths.test.sh (3 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T64 | A | strip anchor, keep the WHAT |
| 55 | B | T64 | A | strip anchor, keep the WHAT |
| 71 | B | T64 | A | strip anchor, keep the WHAT |

### test/sections/T65-allowlist-product.test.sh (13 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T65 | A | strip anchor, keep the WHAT |
| 7 | B | T47 | A | strip anchor, keep the WHAT |
| 39 | B | T65 | A | strip anchor, keep the WHAT |
| 60 | B | T65 | A | strip anchor, keep the WHAT |
| 68 | B | T65 | A | strip anchor, keep the WHAT |
| 83 | B | T65 | A | strip anchor, keep the WHAT |
| 94 | B | T65 | A | strip anchor, keep the WHAT |
| 106 | B | T65 | A | strip anchor, keep the WHAT |
| 115 | B | T65 | A | strip anchor, keep the WHAT |
| 130 | B | T65 | A | strip anchor, keep the WHAT |
| 150 | B | T65 | A | strip anchor, keep the WHAT |
| 161 | B | T65 | A | strip anchor, keep the WHAT |
| 173 | B | T65 | A | strip anchor, keep the WHAT |

### test/sections/T66-census-reconcile.test.sh (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 6 | B | T66 | A | strip anchor, keep the WHAT |

### test/sections/T67-gates-trust.test.sh (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T67 | A | strip anchor, keep the WHAT |
| 5 | B | T61 | A | strip anchor, keep the WHAT |

### test/sections/T68-section-run.test.sh (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T68 | A | strip anchor, keep the WHAT |
| 6 | B | T67 | A | strip anchor, keep the WHAT |
| 102 | A | T1-T0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 103 | A | T1-T0 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### test/sections/T69-init-coding.test.sh (1 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T69 | A | strip anchor, keep the WHAT |

### test/sections/T7-render.test.sh (14 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T7 | A | strip anchor, keep the WHAT |
| 4 | B | D-08 | A | strip anchor, keep the WHAT |
| 34 | B | T7 | A | strip anchor, keep the WHAT |
| 44 | B | T7 | A | strip anchor, keep the WHAT |
| 53 | B | T7 | A | strip anchor, keep the WHAT |
| 57 | B | T7 | A | strip anchor, keep the WHAT |
| 74 | B | T7 | A | strip anchor, keep the WHAT |
| 82 | B | T7 | A | strip anchor, keep the WHAT |
| 89 | B | T7 | A | strip anchor, keep the WHAT |
| 110 | B | T7 | A | strip anchor, keep the WHAT |
| 122 | B | T7 | A | strip anchor, keep the WHAT |
| 135 | B | T7 | A | strip anchor, keep the WHAT |
| 160 | B | T7 | A | strip anchor, keep the WHAT |
| 167 | B | T7 | A | strip anchor, keep the WHAT |

### test/sections/T70-feedback-cmds.test.sh (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T70 | A | strip anchor, keep the WHAT |
| 9 | B | T67 | A | strip anchor, keep the WHAT |

### test/sections/T71-phase-amend-reposlug.test.sh (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T71 | A | strip anchor, keep the WHAT |
| 84 | A | [A-Z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### test/sections/T72-lessons-json.test.sh (17 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T72 | A | strip anchor, keep the WHAT |
| 47 | B | T72 | A | strip anchor, keep the WHAT |
| 67 | B | T72 | A | strip anchor, keep the WHAT |
| 83 | B | T72 | A | strip anchor, keep the WHAT |
| 98 | B | T72 | A | strip anchor, keep the WHAT |
| 127 | B | T72 | A | strip anchor, keep the WHAT |
| 146 | B | T72 | A | strip anchor, keep the WHAT |
| 156 | A | §8 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 161 | B | T72 | A | strip anchor, keep the WHAT |
| 195 | B | T72 | A | strip anchor, keep the WHAT |
| 215 | B | T72 | A | strip anchor, keep the WHAT |
| 224 | B | T72 | A | strip anchor, keep the WHAT |
| 233 | B | T72 | A | strip anchor, keep the WHAT |
| 251 | B | T72 | A | strip anchor, keep the WHAT |
| 256 | B | T72 | A | strip anchor, keep the WHAT |
| 285 | B | T72 | A | strip anchor, keep the WHAT |
| 305 | B | T72 | A | strip anchor, keep the WHAT |

### test/sections/T73-gate-evidence.test.sh (8 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T73 | A | strip anchor, keep the WHAT |
| 28 | B | T73 | A | strip anchor, keep the WHAT |
| 32 | B | T73 | A | strip anchor, keep the WHAT |
| 47 | B | T73 | A | strip anchor, keep the WHAT |
| 69 | B | T73 | A | strip anchor, keep the WHAT |
| 91 | B | T73 | A | strip anchor, keep the WHAT |
| 97 | B | T73 | A | strip anchor, keep the WHAT |
| 104 | B | D-01 | B | delete lineage-only line, ids ride the ledger |

### test/sections/T74-i18n.test.sh (13 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T74 | A | strip anchor, keep the WHAT |
| 28 | B | T74 | A | strip anchor, keep the WHAT |
| 36 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 39 | A | [a-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 50 | B | T74 | B | delete lineage-only line, ids ride the ledger |
| 64 | B | T74 | A | strip anchor, keep the WHAT |
| 70 | B | T74 | A | strip anchor, keep the WHAT |
| 97 | B | T74 | A | strip anchor, keep the WHAT |
| 105 | B | T74 | A | strip anchor, keep the WHAT |
| 125 | B | T74 | A | strip anchor, keep the WHAT |
| 128 | B | T74 | A | strip anchor, keep the WHAT |
| 160 | B | T74 | A | strip anchor, keep the WHAT |
| 179 | B | T74 | A | strip anchor, keep the WHAT |

### test/sections/T75-blast.test.sh (16 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T75 | A | strip anchor, keep the WHAT |
| 40 | B | T75 | A | strip anchor, keep the WHAT |
| 50 | B | T75 | A | strip anchor, keep the WHAT |
| 55 | B | T75 | A | strip anchor, keep the WHAT |
| 60 | B | T75 | A | strip anchor, keep the WHAT |
| 70 | B | T75 | A | strip anchor, keep the WHAT |
| 83 | B | T75 | A | strip anchor, keep the WHAT |
| 91 | B | T75 | B | delete lineage-only line, ids ride the ledger |
| 106 | B | T75 | A | strip anchor, keep the WHAT |
| 107 | A | t75-p0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 110 | A | t75-p0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 120 | B | T75 | A | strip anchor, keep the WHAT |
| 125 | B | Wave 1 | B | delete lineage-only line, ids ride the ledger |
| 126 | B | T1 | B | delete lineage-only line, ids ride the ledger |
| 141 | B | T75 | A | strip anchor, keep the WHAT |
| 145 | B | T75 | A | strip anchor, keep the WHAT |

### test/sections/T76-aggregate-push.test.sh (20 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T76 | A | strip anchor, keep the WHAT |
| 38 | B | T76 | A | strip anchor, keep the WHAT |
| 58 | B | T76 | B | delete lineage-only line, ids ride the ledger |
| 65 | B | T76 | A | strip anchor, keep the WHAT |
| 73 | B | T76 | A | strip anchor, keep the WHAT |
| 79 | B | T76 | A | strip anchor, keep the WHAT |
| 91 | B | T76 | A | strip anchor, keep the WHAT |
| 109 | B | T76 | A | strip anchor, keep the WHAT |
| 128 | B | T76 | A | strip anchor, keep the WHAT |
| 139 | B | T76 | A | strip anchor, keep the WHAT |
| 149 | B | T76 | A | strip anchor, keep the WHAT |
| 158 | B | T76 | A | strip anchor, keep the WHAT |
| 166 | B | T76 | A | strip anchor, keep the WHAT |
| 177 | B | T76 | A | strip anchor, keep the WHAT |
| 199 | B | T76 | A | strip anchor, keep the WHAT |
| 200 | B | T76 | A | strip anchor, keep the WHAT |
| 214 | B | T76 | A | strip anchor, keep the WHAT |
| 215 | B | D-85 | A | strip anchor, keep the WHAT |
| 234 | B | T76 | A | strip anchor, keep the WHAT |
| 244 | B | T76 | A | strip anchor, keep the WHAT |

### test/sections/T77-gitseed-neveroverwrite.test.sh (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T77 | A | strip anchor, keep the WHAT |
| 5 | B | R-01 | A | strip anchor, keep the WHAT |

### test/sections/T78-registry-brownfield.test.sh (9 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T78 | A | strip anchor, keep the WHAT |
| 6 | A | R4-F1 | A | strip anchor, keep the WHAT |
| 8 | B | D-88 | B | delete lineage-only line, ids ride the ledger |
| 23 | B | T78 | A | strip anchor, keep the WHAT |
| 35 | B | T78 | A | strip anchor, keep the WHAT |
| 43 | A | R4-F1 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 46 | B | T78 | A | strip anchor, keep the WHAT |
| 69 | B | T78 | A | strip anchor, keep the WHAT |
| 80 | B | T78 | A | strip anchor, keep the WHAT |

### test/sections/T79-brownfield-probe.test.sh (5 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T79 | A | strip anchor, keep the WHAT |
| 61 | B | T79 | B | delete lineage-only line, ids ride the ledger |
| 75 | B | T79 | B | delete lineage-only line, ids ride the ledger |
| 96 | B | T79 | B | delete lineage-only line, ids ride the ledger |
| 117 | B | T79 | A | strip anchor, keep the WHAT |

### test/sections/T8-phase-archive.test.sh (18 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T8 | A | strip anchor, keep the WHAT |
| 39 | B | T8 | A | strip anchor, keep the WHAT |
| 50 | B | T8 | B | delete lineage-only line, ids ride the ledger |
| 54 | B | T8 | A | strip anchor, keep the WHAT |
| 62 | B | T8 | B | delete lineage-only line, ids ride the ledger |
| 67 | B | T8 | A | strip anchor, keep the WHAT |
| 75 | B | T8 | A | strip anchor, keep the WHAT |
| 83 | B | T8 | A | strip anchor, keep the WHAT |
| 90 | B | T8 | A | strip anchor, keep the WHAT |
| 100 | B | T8 | A | strip anchor, keep the WHAT |
| 112 | B | T8 | A | strip anchor, keep the WHAT |
| 117 | B | T8 | A | strip anchor, keep the WHAT |
| 143 | B | T8 | B | delete lineage-only line, ids ride the ledger |
| 148 | B | T8 | A | strip anchor, keep the WHAT |
| 157 | B | T8 | A | strip anchor, keep the WHAT |
| 187 | B | T8 | A | strip anchor, keep the WHAT |
| 212 | B | T8 | A | strip anchor, keep the WHAT |
| 234 | B | T8 | A | strip anchor, keep the WHAT |

### test/sections/T80-brownfield-adopt.test.sh (5 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T80 | B | delete lineage-only line, ids ride the ledger |
| 40 | B | D-89 | A | strip anchor, keep the WHAT |
| 158 | B | D-89 | A | strip anchor, keep the WHAT |
| 218 | A | R4-F7 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 362 | A | R1-F7 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### test/sections/T81-brownfield-handoff.test.sh (13 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T81 | A | strip anchor, keep the WHAT |
| 7 | B | D-90 | A | strip anchor, keep the WHAT |
| 10 | B | D-98 | A | strip anchor, keep the WHAT |
| 12 | B | D-92 | A | strip anchor, keep the WHAT |
| 14 | A | Lv0-Lv4 | A | strip anchor, keep the WHAT |
| 18 | B | D-100 | A | strip anchor, keep the WHAT |
| 23 | A | R3-F5 | B | delete lineage-only line, ids ride the ledger |
| 24 | B | T80 | A | strip anchor, keep the WHAT |
| 64 | B | D-90 | A | strip anchor, keep the WHAT |
| 111 | B | D-92 | A | strip anchor, keep the WHAT |
| 144 | B | D-100 | A | strip anchor, keep the WHAT |
| 197 | A | R3-F5 | A | strip anchor, keep the WHAT |
| 205 | B | T80 | A | strip anchor, keep the WHAT |

### test/sections/T82-brownfield-edges.test.sh (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T82 | A | strip anchor, keep the WHAT |
| 106 | A | [T4 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 106 | B | T94 | A | strip anchor, keep the WHAT |
| 121 | A | R2-F13 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### test/sections/T83-delta-decisions.test.sh (5 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T83 | A | strip anchor, keep the WHAT |
| 27 | B | T45 | A | strip anchor, keep the WHAT |
| 61 | B | T83 | A | strip anchor, keep the WHAT |
| 80 | B | T83 | A | strip anchor, keep the WHAT |
| 89 | B | T83 | A | strip anchor, keep the WHAT |

### test/sections/T85-security-depth.test.sh (7 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T85 | A | strip anchor, keep the WHAT |
| 4 | B | T1 | A | strip anchor, keep the WHAT |
| 9 | B | T85 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 61 | B | T1 | A | strip anchor, keep the WHAT |
| 77 | B | T1 | A | strip anchor, keep the WHAT |
| 84 | B | D-11 | A | strip anchor, keep the WHAT |
| 133 | B | D-11 | A | strip anchor, keep the WHAT |

### test/sections/T86-truth-replay-surface.test.sh (6 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T86 | A | strip anchor, keep the WHAT |
| 4 | B | D-04 | A | strip anchor, keep the WHAT |
| 5 | B | D-05 | A | strip anchor, keep the WHAT |
| 122 | B | D-05 | A | strip anchor, keep the WHAT |
| 140 | B | T3 | A | strip anchor, keep the WHAT |
| 151 | B | T14 | A | strip anchor, keep the WHAT |

### test/sections/T87-config-twolayer.test.sh (14 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T87 | A | strip anchor, keep the WHAT |
| 12 | A | [R3 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 41 | B | T87 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 82 | B | T87 | B | delete lineage-only line, ids ride the ledger |
| 89 | B | T87 | A | strip anchor, keep the WHAT |
| 97 | B | T87 | A | strip anchor, keep the WHAT |
| 105 | B | T87 | A | strip anchor, keep the WHAT |
| 121 | B | T87 | A | strip anchor, keep the WHAT |
| 133 | B | T87 | A | strip anchor, keep the WHAT |
| 165 | B | T87 | A | strip anchor, keep the WHAT |
| 180 | B | T87 | A | strip anchor, keep the WHAT |
| 208 | B | T87 | A | strip anchor, keep the WHAT |
| 226 | B | T87 | A | strip anchor, keep the WHAT |
| 251 | B | T87 | A | strip anchor, keep the WHAT |

### test/sections/T88-autorender.test.sh (15 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T88 | A | strip anchor, keep the WHAT |
| 46 | B | T88 | A | strip anchor, keep the WHAT |
| 53 | B | T88 | A | strip anchor, keep the WHAT |
| 61 | B | T88 | A | strip anchor, keep the WHAT |
| 67 | B | T88 | A | strip anchor, keep the WHAT |
| 75 | B | T88 | A | strip anchor, keep the WHAT |
| 83 | B | T88 | A | strip anchor, keep the WHAT |
| 91 | B | T88 | A | strip anchor, keep the WHAT |
| 101 | B | T88 | A | strip anchor, keep the WHAT |
| 106 | B | T88 | A | strip anchor, keep the WHAT |
| 114 | B | T88 | A | strip anchor, keep the WHAT |
| 123 | B | T88 | A | strip anchor, keep the WHAT |
| 137 | B | T88 | A | strip anchor, keep the WHAT |
| 148 | B | T88 | A | strip anchor, keep the WHAT |
| 158 | B | T88 | A | strip anchor, keep the WHAT |

### test/sections/T89-changelog-path.test.sh (3 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T89 | A | strip anchor, keep the WHAT |
| 30 | B | T89 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 82 | A | R3-F8 | A | strip anchor, keep the WHAT |

### test/sections/T9-contract.test.sh (10 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T9 | A | strip anchor, keep the WHAT |
| 20 | B | T9 | A | strip anchor, keep the WHAT |
| 24 | B | T9 | B | delete lineage-only line, ids ride the ledger |
| 28 | B | T9 | A | strip anchor, keep the WHAT |
| 32 | B | T9 | A | strip anchor, keep the WHAT |
| 35 | B | T9 | A | strip anchor, keep the WHAT |
| 39 | B | T9 | A | strip anchor, keep the WHAT |
| 53 | B | T9 | A | strip anchor, keep the WHAT |
| 65 | B | T9 | A | strip anchor, keep the WHAT |
| 72 | B | T9 | A | strip anchor, keep the WHAT |

### test/sections/T90-projectmd-gate.test.sh (8 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T90 | A | strip anchor, keep the WHAT |
| 9 | B | T39 | A | strip anchor, keep the WHAT |
| 63 | B | T90 | A | strip anchor, keep the WHAT |
| 71 | B | T90 | A | strip anchor, keep the WHAT |
| 91 | B | T90 | A | strip anchor, keep the WHAT |
| 103 | B | T90 | A | strip anchor, keep the WHAT |
| 122 | B | T90 | A | strip anchor, keep the WHAT |
| 134 | B | T90 | A | strip anchor, keep the WHAT |

### test/sections/T91-ledger-reconcile.test.sh (9 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T91 | A | strip anchor, keep the WHAT |
| 41 | B | T91 | A | strip anchor, keep the WHAT |
| 64 | B | T91 | A | strip anchor, keep the WHAT |
| 86 | B | T91 | A | strip anchor, keep the WHAT |
| 97 | B | T91 | A | strip anchor, keep the WHAT |
| 106 | B | T91 | A | strip anchor, keep the WHAT |
| 123 | B | T91 | A | strip anchor, keep the WHAT |
| 127 | B | D-01 | A | strip anchor, keep the WHAT |
| 131 | B | T91 | A | strip anchor, keep the WHAT |

### test/sections/T92-logs-cmd.test.sh (3 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T92 | A | strip anchor, keep the WHAT |
| 130 | B | T2 | A | strip anchor, keep the WHAT |
| 195 | B | T11 | A | strip anchor, keep the WHAT |

### test/sections/T93-gitprobe.test.sh (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | A | §3 | A | strip anchor, keep the WHAT |
| 3 | B | T93 | A | strip anchor, keep the WHAT |

### test/sections/T94-schemav4.test.sh (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T94 | A | strip anchor, keep the WHAT |
| 17 | B | D-12 | A | strip anchor, keep the WHAT |
| 176 | B | D-18 | A | strip anchor, keep the WHAT |
| 257 | B | D-12 | A | strip anchor, keep the WHAT |

### test/sections/T95-repo-id-guard.test.sh (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T95 | A | strip anchor, keep the WHAT |
| 20 | B | D-18 | A | strip anchor, keep the WHAT |

### test/sections/T96-lang-boundary.test.sh (2 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T96 | A | strip anchor, keep the WHAT |
| 10 | B | T1 | A | strip anchor, keep the WHAT |

### test/sections/T97-gap-migrate.test.sh (3 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | T97 | A | strip anchor, keep the WHAT |
| 57 | A | [feed0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 205 | A | [bad0 | D | string-context audit: rewrite anchor-free or pin frozen-string |

### test/sections/T98a-track-core.test.sh (6 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | D-15 | A | strip anchor, keep the WHAT |
| 12 | A | RT2-F2 | A | strip anchor, keep the WHAT |
| 22 | B | D-14 | A | strip anchor, keep the WHAT |
| 47 | B | T97 | A | strip anchor, keep the WHAT |
| 221 | A | RT3-F7 | A | strip anchor, keep the WHAT |
| 318 | B | D-14 | A | strip anchor, keep the WHAT |

### test/sections/T98b-track-txn.test.sh (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 3 | B | D-15 | A | strip anchor, keep the WHAT |
| 4 | A | RT3-F7 | A | strip anchor, keep the WHAT |
| 10 | A | B1-B3 | A | strip anchor, keep the WHAT |
| 162 | A | B1-B3 | A | strip anchor, keep the WHAT |

### test/sections/T99-gate-flip-leg.test.sh (4 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 4 | B | T99 | A | strip anchor, keep the WHAT |
| 5 | A | RT2-F4 | A | strip anchor, keep the WHAT |
| 24 | B | D-14 | A | strip anchor, keep the WHAT |
| 195 | B | D-14 | A | strip anchor, keep the WHAT |

### test/workflow-lint.sh (5 hit(s))

| line | tier | matched | letter | action |
|:--|:--|:--|:--|:--|
| 2 | A | R4-F8 | A | strip anchor, keep the WHAT |
| 25 | A | [A-Za-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 37 | A | [A-Za-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 52 | A | [A-Za-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |
| 117 | A | [A-Za-z0 | D | string-context audit: rewrite anchor-free or pin frozen-string |

