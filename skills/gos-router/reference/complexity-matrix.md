# Complexity Assessment Matrix

Detailed signal evaluation for gos-router Step 2.

## Signal Weights

| Signal | Weight | Rationale |
|:---|:---|:---|
| Files affected | High (×3) | More files = more integration risk |
| Design decisions | High (×3) | Undecided design = THINK investment needed |
| Feature type | Medium (×2) | New features need more exploration than fixes |
| Estimated time | Medium (×2) | Time correlates with complexity |
| Scope | High (×3) | Multi-module = architectural decisions |

## Scoring

Score each signal 0-2 (Low/Medium/High), multiply by weight, sum:

| Total Score | Recommended Level |
|:---|:---|
| 0-4 | Lv0 (direct execution) |
| 5-8 | Lv1 (BUILD → VERIFY) |
| 9-14 | Lv2 (THINK → BUILD → VERIFY) |
| 15-22 | Lv3 (THINK → PLAN → BUILD → REVIEW → SHIP) |
| 23+ | Lv4 (full + milestone loop) |

## Level Adjustment Rules

- **User says "simple"/"just fix"**: cap at Lv1
- **User says "thorough"/"careful"**: floor at Lv3
- **Brownfield code (existing codebase)**: +1 to score (integration risk)
- **User has been burned before on similar tasks**: +2 (trust deficit)
- **Time pressure**: -1 (but never below Lv0)
