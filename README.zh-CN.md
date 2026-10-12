# GOS — Get Organized System

[English](README.md) | [简体中文](README.zh-CN.md)

[![CI](https://github.com/chenw521/GOS/actions/workflows/ci.yml/badge.svg)](https://github.com/chenw521/GOS/actions/workflows/ci.yml)
> [!NOTE]
> 尚未发布——GOS 正在打磨中，首个版本（GitHub Packages 内测或直接上公共 npm）将在打磨完成后发布。公共 npm 包名已预留。
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> **AI 编程代理的确定性执行层 + 自适应工作流。**
> 小任务零负担直过；大项目全治理 + 对抗验证。
> 次旗舰模型得到一副跳不掉的能力外骨骼；旗舰模型得到一个哄不动的挑战者。

## 为什么需要 GOS

AI 编码代理以两种相反的方式失败：

- **次旗舰模型**（flash 级、开源系）：跳步骤、没证据就说"做完了"、跨会话丢上下文、幻觉命令。嘴上叮嘱"小心点"没用——它们需要**硬门**（exit 1）、**文件系统证据**（伪造不了）、**预计算下一步**（迷路不了）。
- **旗舰模型**：不需要更多规则，需要的是**被挑战**。让写 spec 的同一个模型审 spec，什么都审不出来。GOS 派出全新上下文的对抗攻击者（有条件时用*不同*的模型），攻击到一轮空手而归为止。
- **所有模型**：改个 typo 走重流程是税；做个功能零流程是赌博。流程重量必须随任务量级伸缩。

GOS 用一套系统同时处理这三件事——它把 [Superpowers](https://github.com/obra/superpowers)（过程纪律）、GSD（项目机器）和 OpenSpec（工件生命周期）的精华吸收进一个零配置工作流，底下垫着一层确定性 CLI。

## 证据

- **自举**：GOS 用 GOS 开发。本仓库自身就是一个 Lv4 项目——20+ 任务/phase 走完整管线（THINK → PLAN → BUILD → REVIEW → VERIFY → SHIP）交付，积累 30 条项目教训，v0.11 以来每个发版都能追溯到它的决策与已验证真值。回归套件——64 个 section、1500+ 条活断言——就是 CI 主干。
- **Benchmark 进行中**：外部任务套件基准正在针对当前版本重建；早期 runs 已随其测量的旧版本一并退役。方法论站得住时再公布数字。

## 工作原理

### 基线环——永不在场缺席，typo 也不例外

```
INTENT（确认意图）→ [自适应中间流程] → VERIFY（证明）→ TRACE（留痕）
```

### 自适应路由——不用的流程一分钱不付

| 级别 | 任务 | 流程 |
|:---|:---|:---|
| Lv0 | typo、注释 | 直接执行 |
| Lv1 | 小 bug | BUILD → VERIFY |
| Lv2 | 明确小功能 | THINK → BUILD → VERIFY |
| Lv3 | 新功能 | THINK → PLAN → BUILD → REVIEW → VERIFY → SHIP |
| Lv4 | 大项目 | phase 生命周期：claim → 完整 Lv3 → archive → 下一个 |

Agent 推荐级别，你可以一句话升降档。

### 三层架构，一套系统

| 层 | 级别 | DNA | 职责 |
|:---|:---|:---|:---|
| Engineer | Lv0–Lv2 | Superpowers 纪律 | 直接执行、TDD、系统性调试、小任务波次构建 |
| Designer | Lv3 | OpenSpec 生命周期 | THINK → PLAN → BUILD → REVIEW → VERIFY → SHIP + 门控工件 |
| Chief Designer | Lv4 | GSD 项目机器 | PROJECT/ROADMAP/DECISIONS 生命周期，phase claim → 完整 Lv3 → archive |

### 确定性层——流程为什么"粘得住"

零依赖 Node CLI（`gos`，Node ≥ 20）把工作流的口头承诺变成机械事实：

- **硬门**：`gos gate all` 在决策未覆盖、真值未验证、diff 超出申报文件、spec 哈希漂移时 exit 1。skill 依裁决路由。
- **文件系统兜底**："做完了"在工件落盘前被拒绝；已验证真值必须携带 `{command, output, artifact}` 三元证据——`--replay` 模式重执行命令、从*真实* stdout 提取摘录。
- **语义层**：plan Covers ↔ 决策精确双向匹配；diff-hit 检查（申报 Files ⊇ 实际 diff）；fn 级调用图影响闭合（`gos map closure`）在跑测试*之前*告诉你这次改动牵连谁。
- **跨会话记忆**：分型教训库（project 型永久留存；model 型 +90 天自动过期——模型迭代后旧教训会腐烂）、带 supersede 链的决策记录、跨会话 `gos resume`。

### 对抗即默认

THINK 与 PLAN 的产物会被全新上下文的 Red Team 轮次攻击（有人手时用异构模型）。每条 finding 必须有处置——ACCEPT / PARTIAL / REJECT-with-facts / DEFER。橡皮图章是流程违规，不是风格选择。

### Lv4 phase 生命周期（数周级项目）

Phase 从路线图认领，内部跑完整 Lv3，归档时合并回 `project.json`（单一事实源）并渲染 markdown 视图。真实世界的摩擦被显式建模：乱序完成合法（prev-done 门），故意搁置的 phase 有第一阶级的 `parked` 状态、作为 milestone 欠账持续可见——没有任何东西会静默消失。

## 快速开始

### 绿地——三步从零开始

```bash
npm i -g @chenw521/gos        # 公网 npm 安装
# 发布前的替代方式（现在即可用，跟随 main）：
# npm i -g github:chenw521/GOS
gos setup
```

> ⚠️ **装对包。** 包名是 **`@chenw521/gos`**——它提供的 bin 命令是 `gos`。公共 npm 上已存在一个名为 `gos` 的无关第三方抢注包，装那个包得不到 GOS。

macOS / Linux / Windows 全平台（需要提权的符号链接自动降级为 junction）。Node ≥ 20。重启 AI 助手，问它 *"list your gos skills"* 验证。然后直接描述任务——GOS 自动激活并推荐级别：

```
用 GOS 实现一个用户认证功能        # 或者就一句：这个 bug 帮我修一下
```

任何时候敲 `gos`（无参数）即显示状态和下一步。

### 接管已有仓库（brownfield）

仓库里已经有自己的历史、配置和文件，怎么接入 GOS？`gos brownfield`
逐路径探测、归类冲突、只补种缺失的资产——是接管，不是霸占：

```bash
gos brownfield          # 接管报告（--json 输出机器可读格式）
```

```
brownfield 接管报告 — '/path/to/repo'
core.hooksPath：未设置——种下的钩子处于休眠（git 读 .git/hooks/；GOS 绝不写 .git/hooks/ 或 git config）
资产清单：
  created            hooks/commit-msg [inactive]
  report_only        AGENTS.md
补救步骤：
  1. hooks/commit-msg：运行 gos setup --commitlint
  2. AGENTS.md：运行 gos brownfield --print-agents-skeleton
```

它绝不做的事：绝不覆盖已存在的文件（必须显式 `gos brownfield --overwrite <asset>`——用户自有钩子仍会拒绝）；绝不写入 AGENTS.md / CLAUDE.md / GEMINI.md（`--print-agents-skeleton` 只向 stdout 打印起始骨架）；种下的钩子保持**休眠**，直到 `gos setup --commitlint`；模板包仍由 `gos init git` 种入，不在此步。术语说明：此处的 "brownfield" 指*把 GOS 接管进已有仓库*——与 GOS 历史中决策导入的 "brownfield import" 无关。

<!-- gos:core-shortlist begin -->
- `gos`（无参数）— 状态 + 下一步（零记忆入口）
- `gos init <level> "<intent>"` — 开始任务
- `gos commit <stage>` — 原子提交 + 阶段推进
- `gos gate all` — 硬门（失败 exit 1）
- `gos context <stage>` — 预计算上下文 JSON
- `gos resume` — 跨会话恢复摘要
- `gos instructions <stage>` — 阶段指引
- `gos phase <sub>` — Lv4 phase 生命周期
- `gos decision <sub>` — 记录/修订决策
- `gos help [--json]` — 全量能力发现

全量能力: `gos help [--json]`
<!-- gos:core-shortlist end -->

<details>
<summary>更多 CLI 面</summary>

```bash
gos gate semantic                 # 双向覆盖 + diff-hit + 影响闭合
gos map closure <file> --semantic # 这次改动牵连谁（fn 调用图）
gos lessons add --type project "…" # 跨会话存活的仓库记忆
gos map blast <paths>                 # 改动前影响报告：还需连带检查什么、为什么
gos setup --lang zh-CN                # 中文界面（GOS_LANG=zh 可单次覆盖）
gos truth verify T1 --replay      # 证据来自真实 stdout，不是口头声称
gos render                        # 重新渲染 DECISIONS/ROADMAP/REQUIREMENTS 视图
gos setup --local                 # 开发模式：从 git 检出做符号链接
gos teardown                      # 移除 skills 链接
```

</details>

## 何时用 / 何时不用

| 用 GOS，当... | 换别的，当... |
|:---|:---|
| 日常任务用次旗舰/便宜模型——需要外骨骼 | 需要 UAT/安全/UI 专用 phase 机器和多仓库 workstream 开箱即用 → **GSD** |
| 任务大小混杂（typo 到功能），小任务被重流程烦到 | 规格即交付物（契约先行、合规）→ **OpenSpec** |
| 想要跨任务记忆（教训、决策、已验证真值） | 完全信任模型、零治理 → 纯 skill（**Superpowers**） |
| 旗舰 + 大项目：想要它被挑战，而不只是被管理 | |

GOS 是融合层不是替代品：装了 Superpowers 的话，`gos-build` 自动激活其战术子技能（TDD、debugging、并行代理）；不装也能独立运行。

## 项目结构

```
GOS/
├── bin/gos.cjs          # 零依赖* CLI：硬门、语义层、原子提交
│                        #   （*仅一个依赖：acorn，供 AST 调用图）
├── skills/              # 8 个薄 skill（<55 行：路由表 + HARD-GATE）+ 懒加载参考
│   ├── gos-router/      # 入口：评估 → 推荐级别 → 串联阶段
│   ├── gos-project/     # Lv4 总设计师：PROJECT/ROADMAP/DECISIONS 生命周期
│   ├── gos-think/       # 逐灰区对话 + D-NN 决策 + Red Team
│   ├── gos-plan/        # 波次执行 + 决策覆盖门 + 修订环
│   ├── gos-build/       # 波次实现 + TDD + 聚合协议
│   ├── gos-review/      # 两阶段：规格符合 → 代码质量
│   ├── gos-verify/      # 一次一真值 + 拿证据说话
│   └── gos-ship/        # 变更记录 + 归档 + 清扫扫描
├── templates/           # spec / plan / verify / review / trace 骨架
├── .gos/                # 工作流工件（project/ 入库；state.json 本地）
├── .opencode/ .codex/ .claude-plugin/   # 平台适配
└── AGENTS.md            # 路由规则 + 工具映射
```

## 来源与现状

基于对 [Superpowers](https://github.com/obra/superpowers)（v5.0.6）、GSD（v1.38.5）、OpenSpec（v1.2.0）的系统性分析构建——提炼为 GOS 的三层架构，而非整体照搬。

| 里程碑 | 状态 |
|:---|:---|
| v0.1–v0.2 skills + 模板 + 平台适配 | ✅ |
| 确定性 CLI 层（硬门、语义检查、真值证据） | ✅ |
| 边网 codemap 2.0（fn 级调用图、影响闭合） | ✅ |
| Lv4 phase 生命周期，v0.11→v0.15 全程自举 | ✅ |
| npm 分发（GitHub Packages 内测 → 开源日上公共 npm）+ CI | 进行中 |
| v1.0 正式发布 | 📋 |

## CLI 速查

<!-- gos:core-shortlist begin -->
- `gos`（无参数）——状态 + 下一步（零记忆入口）
- `gos init <level> "<intent>"`——开始任务
- `gos commit <stage>`——原子提交 + 阶段推进
- `gos gate all`——硬门禁（失败 exit 1）
- `gos context <stage>`——预计算上下文 JSON
- `gos resume`——跨会话恢复摘要
- `gos instructions <stage>`——逐阶段指引
- `gos phase <sub>`——Lv4 phase 生命周期
- `gos decision <sub>`——记录/修订决策
- `gos help [--json]`——全量能力发现

Full capability: `gos help [--json]`
<!-- gos:core-shortlist end -->

## 社区

- **贡献指南** — 提 PR 前先读 [CONTRIBUTING.md](CONTRIBUTING.md)（本地绿=CI 绿命令清单、changelog 义务、AI 代码声明条款）。
- **更新日志** — [CHANGELOG.md](CHANGELOG.md)（Keep a Changelog 格式；更早历史见 `git log`）。
- **Bug 与功能请求** — [issue 表单](https://github.com/chenw521/GOS/issues/new/choose)（bug 表单带 AI 助手 / 模型 / `gos --version` 结构化字段）。

## License

[MIT](LICENSE)
