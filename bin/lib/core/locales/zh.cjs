// core/locales/zh.cjs — zh-CN catalog (P15 D-63 translation layer)
// Rules: command tokens NEVER embedded literally — use {cmd:<name>} placeholders
// resolved from the CLI registry (section T74 lint enforces); locale-invariant
// fields (codes/paths/commands/✓✗) never appear here; missing keys fall back
// to en with an advisory (never crash, never empty). Frozen carve-out keys are
// deliberately NOT translated (byte-stability; they fall back to en).
'use strict';

// contract.* frozen strings are English by design (D-68: frozen surface, one
// final migration then byte-stable) — zh entries REFERENCE the CONTRACTS
// source (copies forbidden), so zh render equals en for these keys.
const { CONTRACTS } = require('../state.cjs');

module.exports = {
  // ---- gate-family actionable entries, keyed by failure code (D-66 join) ----
  'gate.coverage-uncovered': {
    what: '已记录的决策没有任何任务覆盖',
    why: '没有任务落地的决策只是一句空话',
  },
  'gate.decision-uncovered': {
    what: '已记录的决策没有任何任务覆盖',
    why: '没有任务落地的决策只是一句空话',
  },
  'gate.truths-unverified': {
    what: '可观察真相尚未验证',
    why: '未验证的真相只是断言，门禁不能为断言放行',
  },
  'gate.diff-zero-hit': {
    what: '任务申报的文件没有一个出现在变更里',
    why: '计划声称的改动从未发生——空转伪装成进展',
  },
  'gate.undeclared-diff-file': {
    what: '有变更文件未被任何任务申报，也不在豁免清单',
    why: '未申报的改动正是副作用绕过评审的通道',
  },
  'gate.spec-gate-card-missing': {
    what: '决策在 spec 中没有选项卡',
    why: '不展示备选方案的决策是模型偏好，不是决策',
  },
  'gate.lessons-deletion-audit': {
    what: 'lessons 条目被删除但没有处置审计行',
    why: '不记账的删除正是碍事教训悄悄消失的方式',
  },
  'gate.orphan-deferred-finding': {
    what: '延后的评审发现没有停泊位',
    why: '任务归档时它就丢了，没人会再记得',
  },
  'gate.changelog-lint': {
    what: 'CHANGELOG.md 未通过变更记录检查',
    why: '变更记录是交付的一部分，不是事后补笔',
  },
  'gate.gates-lint-exit': {
    what: '配置的 lint 规则未通过',
    why: '仓库级 lint 规则是硬门禁，不是建议',
  },

  // ---- status / guidance surfaces (first-user high-frequency, FB-1) ----
  'status.localeLine': '语言: {locale}（来源: {source}）— 可用 GOS_LANG 或 {cmd:setup} --lang <en|zh-CN> 切换',
  'status.noActiveTask.next': '下一步: 运行 `gos init <level> "<意图>"` 开始一个任务',
  'status.headlessAutoConfirm': '📍 本任务由 headless 自动确认（已审计）',
  'status.aiChatStart': '→ 或在 AI 对话中: "用 GOS ..."',
  'status.aiChatContinue': '→ 在 AI 对话中: "用 GOS 继续"',
  'guidance.intent.confirm1': '→ 与用户确认意图。给出 2-3 个带取舍说明的设计选项。',
  'guidance.intent.confirm2': '→ 展示全部档位（Lv0-Lv4），高亮推荐项。',
  'guidance.intent.confirm3': '→ 用户确认后: `gos init <level> "<确认后的意图>"`',
  'guidance.build.core': '→ 改动前习惯: 编辑共享文件前先跑 `gos map blast <paths>`——它会列出还需连带检查什么、为什么。',
  'guidance.build.aggregate': '→ 每个并行波次之后: 跑聚合脚本（一条命令 = 冲突扫描 + 对接 + 统一构建）。',
  'guidance.build.commit': '→ 全部任务完成 + 测试全绿: `gos commit build`，然后加载 `gos-review`。',

  // ---- setup surfaces ----
  'setup.lang.prompt': '语言 [1] English  [2] 中文 (zh-CN) — 回车 = 保持现状: ',
  'setup.lang.saved': '语言已保存: {locale}（来源: {source}）',
  'help.contractKeysHeader': '  契约键（非命令，测试断言用）:',

  // ---- lessons 归因 (D-67; 仅控制台本地化——md 视图恒 en, F8) ----
  'lessons.attribution': 'lessons: 已加载 {projN} 条项目 + {globN} 条全局（项目: {projPath}; 全局: {globPath}）— 即将过期: {expiring}',
  'lessons.unavailable': 'lessons: 不可用（{reason}）——最常用的命令绝不能被坏文件卡死；修复: `gos lessons list` 查看详情',
  'lessons.stageSubsetHeader': '本阶段相关教训（标记 #{stage}）:',
  'lessons.remainderPointer': '… 另有 {n} 条（本阶段之外的仓库记忆）——完整清单: `gos lessons list`',
  'lessons.projectLabel': '仓库知识 · 永不过期',
  'lessons.modelLabel': '跨仓库行为 · 到期自动过期',

  // ---- CONTRACTS frozen-string aliases (reference, never copy; zh == en) ----
  'contract.gateFailedPrefix': CONTRACTS.gate_verdicts.gateFailedPrefix,
  'contract.allPass': CONTRACTS.gate_verdicts.allPass,
  'contract.noActiveTask': CONTRACTS.state_semantics.noActiveTask,
  'contract.commitBlocked': CONTRACTS.state_semantics.commitBlocked,
  'contract.globalWriteHint': CONTRACTS.semantic_checks.globalWriteHint,
  "setup.onboard.agentsDesc1": "┃ AGENTS.md 注入：往当前目录 AGENTS.md 加一段\"开发任务先跑 /gos\"的引导，",
  "setup.onboard.agentsDesc2": "┃ 让新会话的 AI 主动用 GOS（不存在则创建，已含 GOS 段则跳过）。",
  "setup.onboard.agentsPrompt": "    写入 AGENTS.md 引导？ [Y/n]: ",
  "setup.onboard.agentsSkip": "┃ ✓ AGENTS.md 已含 GOS 段，跳过",
  "setup.onboard.agentsWritten": "┃ ✓ 已写入 {path}",
  "setup.onboard.checkerDesc": "┃  checker（审查员，team 编制的灵魂）：用与主力不同的模型交叉验证",
  "setup.onboard.checkerPrompt": "    checker 模型 [回车={suggestion}]: ",
  "setup.onboard.doneRestart": "│ 重启你的 AI 助手，然后：                                        │",
  "setup.onboard.doneStart": "│   开始：对它说 \"用 GOS 帮我 ...\"  或输入 /gos                  │",
  "setup.onboard.doneTitle": "╭─ 完成 ────────────────────────────────────────────────────────╮",
  "setup.onboard.doneVerify": "│   验证：问它 \"list your GOS skills\"（应列出 8 个）             │",
  "setup.onboard.eliteDesc": "┃  3) elite      全员强模型。关键项目质量至上，成本最高",
  "setup.onboard.implementerPrompt": "    执行者 implementer 模型 [回车={def}]: ",
  "setup.onboard.langKept": "┃ 保持现状 / kept current",
  "setup.onboard.leanDesc": "┃  4) lean       成本优先：执行/研究用快模型，设计保底。批量小任务首选",
  "setup.onboard.otherRoles": "┃ （其余角色继续用探测映射；随时 {cmd:config} models set <agent> <model> 调整）",
  "setup.onboard.pinRoles": "┃ 语义档位会自动映射，但你可以钉死关键角色（回车=接受探测值）：",
  "setup.onboard.probeFailed": "┃ 未能自动探测你的模型列表（没找到 opencode.json 的 provider 配置）。",
  "setup.onboard.probeResult": "┃ 探测到你的模型池（strong 猜测={strong}，fast 猜测={fast}）。",
  "setup.onboard.profilePrompt": "选择 [1-4]（回车=1 team，当前: {current}）: ",
  "setup.onboard.profileSaved": "┃ ✓ 编制 = {profile}",
  "setup.onboard.selfCheck": "┃ 自检: 运行 {cmd:doctor} 查看完整诊断（skills 链接/平台/编制）。",
  "setup.onboard.skipRefine": "┃ 跳过细化，当前全部按 inherit 处理——之后可用下面命令手动钉死：",
  "setup.onboard.soloChangeLater": "┃ （将来想改：{cmd:config} models profile <name>）",
  "setup.onboard.soloDesc": "┃  2) solo       全员跟随当前会话模型。最简单，零额外成本，但交叉验证失效",
  "setup.onboard.soloNoRefine": "┃ solo 无需细化：所有子代理直接继承你的会话模型。",
  "setup.onboard.step1Desc": "┃ GOS 输出文案的语言（命令、代码路径、✓/✗ 符号在任何语言下保持不变）。",
  "setup.onboard.step1Options": "┃  1) English  2) 中文 (zh-CN)",
  "setup.onboard.step1Title": "┏━ [1/4] 语言 / Language",
  "setup.onboard.step2Desc1": "┃ 这一步决定：GOS 派发子任务（实现/审查/红队攻击）时用什么档位的模型。",
  "setup.onboard.step2Desc2": "┃ 它影响成本、速度，以及最重要的——审查者是否用\"不同视角\"交叉验证你的主力模型。",
  "setup.onboard.step2Title": "┏━ [2/4] 团队编制（谁替你干活）",
  "setup.onboard.step3Title": "┏━ [3/4] 编制细化（语义档位 → 你的具体模型）",
  "setup.onboard.subtitle": "│ 接下来 4 步，每步都可回车采用推荐值，随时 Ctrl+C 用默认配置  │",
  "setup.onboard.teamDesc": "┃  1) team ★推荐  设计/审查用强模型，执行跟随当前；审查员用『异构模型』交叉验证",
  "setup.onboard.teamWhy": "┃                （最推荐的原因：主力模型的盲点，恰好需要不同的模型才看得见）",
  "setup.onboard.title": "╭─ GOS 安装向导 / Onboarding ───────────────────────────────────╮",
  "map.net.intro": "节点=path 锚点（人机同键） 边=语义依赖（五类提取+手工）。用途：改动任一节点 → 查闭包，连带检查必查文件。",
  "map.net.autoSection": "自动段（数据生成——勿手改；每次 scan 重新生成）",
  "map.net.familyStats": "边族统计",
  "map.family.calls": "calls（②调用点→cmd 锚）",
  "map.family.contracts": "contracts（③契约串消费者）",
  "map.family.testof": "testof（⑤段标注→cmd）",
  "map.family.hand": "hand（手工边 edges.json）",
  "map.family.testof_fn": "testof_fn（⑦段标注→fn）",
  "map.net.handDetail": "手工边明细（edges.json）",
  "map.net.closureQuickRef": "闭包速查（cmd → 必跑测试段）",
  "map.net.fnQuickRef": "fn 速查（fn → 测试它的段）",
  "map.net.fullGraph": "全图（mermaid）",
  "map.closure.summaryHit": "摘要：本次改动牵连 {files} 个文件、{sections} 个测试段（清单见上，自查/必跑后再提交）",
  "map.closure.summaryNone": "摘要：边网未覆盖本次改动（无已知牵连，非安全证明）",
  "map.allowlist.v1Green": "require 方向断言绿（lib↔lib 边 ⊆ allowlist v1，{n} 个方向）",
  "map.allowlist.v2Green": "require 方向断言绿（v2：{modules} 个模块，{dirs} 个方向，{edges} 条边）",
  "map.allowlist.dirViolation": "require 方向违规：{from} → {to}（模块向 {fr}→{tr} 不在白名单{drift}）",
  "map.allowlist.moduleDrift": "；模块漂移——端点不在任何已登记 moduleRoot 下",
};
