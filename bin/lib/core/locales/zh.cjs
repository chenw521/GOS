// core/locales/zh.cjs — zh-CN catalog (P15 translation layer)
// Rules: command tokens NEVER embedded literally — use {cmd:<name>} placeholders
// resolved from the CLI registry (section lint enforces); locale-invariant
// fields (codes/paths/commands/✓✗) never appear here; missing keys fall back
// to en with an advisory (never crash, never empty). Frozen carve-out keys are
// deliberately NOT translated (byte-stability; they fall back to en).
'use strict';

// contract.* frozen strings are English by design (frozen surface, one
// final migration then byte-stable) — zh entries REFERENCE the CONTRACTS
// source (copies forbidden), so zh render equals en for these keys.
const { CONTRACTS } = require('../state.cjs');

module.exports = {
 // ---- gate-family actionable entries, keyed by failure code
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
  'gate.registry-gap-advisory': '[registry-gap] .gos/ 下有 {n} 个已 tracked 的文件缺少 GOS_PATHS 注册表条目——tracked 文件永不被收养；补注册条目即可消除此提示。仅提示（永不失败，--strict 下同样）。',

  // ---- status / guidance surfaces (first-user high-frequency, FB-1) ----
  'status.localeLine': '语言: {locale}（来源: {source}）— 可用 GOS_LANG 或 {cmd:setup} --lang <en|zh-CN> 切换',
  'status.noActiveTask.next': '下一步: 运行 `gos init <level> "<意图>"` 开始一个任务',

  'logs.receipts.title': '真相回执 — {path}（显示最近 {n} 条，共 {total} 条）',
  'logs.exemptions.title': '门禁豁免 — {path}（显示最近 {n} 条，共 {total} 条）',
  'logs.audit.title': '边审计 — {path}（显示最近 {n} 条，共 {total} 条）',
  'logs.empty': '暂无条目——对应命令运行后账本会自动填充',
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

  'lessons.attribution': 'lessons: 已加载 {projN} 条项目 + {globN} 条全局（项目: {projPath}; 全局: {globPath}）— 即将过期: {expiring}',
  'lessons.unavailable': 'lessons: 不可用（{reason}）——最常用的命令绝不能被坏文件卡死；修复: `gos lessons list` 查看详情',
  'lessons.stageSubsetHeader': '本阶段相关教训（标记 #{stage}）:',
  'lessons.remainderPointer': '… 另有 {n} 条（本阶段之外的仓库记忆）——完整清单: `gos lessons list`',
  'lessons.projectLabel': '仓库知识 · 永不过期',
  'lessons.modelLabel': '跨仓库行为 · 到期自动过期',

  'langBoundary.trackedStore': '语言边界：{file} 受 git 跟踪——跟踪态的 GOS 知识文件仅允许英文，保存前请将内容改写为英文（未跟踪的存储不受语言限制）',

  'gap.migrate.removed': '✓ 已将 {n} 条 stage-back 镜像行从 concerns.md 迁入缺口历史台账——state.gaps 仍是唯一事实源',
  'gap.migrate.none': 'concerns.md 中没有 (auto) 镜像行——无需迁移',
  'gap.migrate.dupes': '⚠ {n} 条镜像行已在台账中（按文本去重）——从 concerns.md 清除但不再重复追加',
  'gap.history.empty': '（暂无缺口历史——stage-back 镜像经由 {cmd:gap} migrate 落入此处）',
  'gap.history.skipped': '⚠ 已跳过 {n} 行格式错误的台账行（.gos/logs/gap-history.ndjson）',
  'concerns.err.anchorMissingDirty': 'concerns.md 受 git 跟踪但 .concerns-anchors.json 缺失，且文件与 HEAD blob 不一致——疑似手改；请用 git checkout 恢复，或先提交该改动（禁止借此重建，防止洗白）',

  'track.err.notRepo': 'track: 不是 git 仓库——gos track 只在 git 工作树内翻转文件',
  'track.err.notFound': 'track: {path} 无法解析为本仓库内的常规文件（不存在、是目录、或在工作树之外）',
  'track.err.scope': 'track: {path} 在 .gos/ 范围之外——gos track 只翻转 .gos/ 下的文件',
  'track.err.symlink': 'track: {path} 未解析到自身（argv 含符号链接或穿越段；规范路径: {canon}）——受跟踪的 GOS 存储必须是常规文件；请指向真实文件',
  'track.err.caseArg': 'track: 大小写不匹配——argv 为 {arg}，规范路径为 {canon}；请用规范拼写重跑（大小写不敏感的克隆会让二者分叉）',
  'track.err.caseDisk': 'track: 磁盘上存在大小写冲突——{other} 与 {path} 仅大小写不同；大小写不敏感的克隆会覆盖其一，请先重命名其中一个',
  'track.err.zone': 'track: {path} 位于永不跟踪区 {zone}——该区设计为机器本地，任何文件都不可翻转',
  'track.err.env': 'track: {path} 是机密文件（.env 家族）——机密绝不能被 git 跟踪',
  'track.err.unborn': 'track: 本仓库尚无提交（HEAD 未诞生）——翻转需要与 HEAD blob 对账；请先完成首次提交再重跑',
  'track.err.tracked': 'track: {path} 已被跟踪——无需翻转（待翻转清单事务落地后，对已跟踪目标的重跑将成为经验证的无操作，历史跟踪文件也可获得 adopt 记录）',
  'track.err.gitignoreUnsafe': 'track: {path} 含 gitignore 模式无法原样表达的路径段（以 ! 或 # 开头、尾部空格）——请先重命名该文件',
  'track.err.gitAdd': 'track: {path} 的 git add 失败: {err}——翻转已回滚：工作区文件已按字节还原且 git 暂存区已清扫干净；请解决 git 错误后重跑',
  'track.err.rollbackIncomplete': 'track: 回滚不完整——{items}；事务前字节保留在 {dir}（请手动改名恢复后再重跑）',
  'track.prescan.storeCjk': 'track: 语言预扫描——受跟踪存储 {file} 在 {where} 携带 CJK: {text}——跟踪态的 GOS 存储仅允许英文；请先改写内容（所有存储清理干净之前，翻转不做任何改动）',
  'track.prescan.targetCjk': 'track: 目标 {path} 第 {line} 行携带 CJK: {text}——跟踪态存储仅允许英文；请先用英文改写该文件再重跑',
  'track.prescan.sanitize': 'track: 净化预扫描在 {path} 第 {line} 行命中（{pattern}）: {text}——机器本地数据不得随仓库流转；请清除泄漏后重跑',
  'track.surgery.verifyFail': 'track: gitignore 手术验证失败——忽略集差异为 [{diff}]，应恰好等于目标；已回滚，未做任何更改',
  'track.done.surgery': '✓ 已跟踪 {path}——.gos/.gitignore 否定规则 {negation} 验证通过（忽略集差异 == 目标），{census}，已通过 git add 暂存',
  'track.done.noSurgery': '✓ 已跟踪 {path}——目标未被忽略（无需 gitignore 手术），{census}，已通过 git add 暂存',
  'track.done.manifest': '  翻转清单：{path} 已记录于 HEAD {head}（随翻转一并暂存）',
  'track.adopt.done': '✓ 已收编 {path}——已被 git 跟踪但缺清单记录；adopt 记录已追加至 .gos/track-manifest.json（{census}），已通过 git add 暂存',
  'track.noop.done': '✓ {path} 已被跟踪——清单记录存在，{census}；经验证的无操作，零改动',
  'track.err.censusContradiction': 'track: {path} 已被 git 跟踪，但 census 条目 {key} 标记为 git:false——矛盾需人工裁决：先修正 census.json（或取消跟踪该文件）再重跑',
  'track.preset.err.missing': 'track --knowledge: {path} 缺失——预设要求三份导览文件齐备（.gos/codebase/structure.md、conventions.md、concerns.md）',
  'track.knowledge.done': '✓ knowledge 预设完成：{n} 个文件已加 born-at: {head} 戳',

 // ---- / gate 翻转对账腿（tracked .gos 文件的 census/git/清单三方
  'gate.flip-git-probe-failed': {
    what: '翻转对账腿无法确立 git 事实',
    why: '故障关闭：没有探测事实时 gate 拒绝对账，绝不猜测',
  },
  'gate.flip-census-corrupt': {
    what: 'census.json 在 gate 时无法解析为 JSON',
    why: '处置台账就是对账源——台账损坏即整体判负',
  },
  'gate.flip-census-contradicts': {
    what: '某个已跟踪的 .gos 文件被 git:false 的 census 条目覆盖',
    why: 'census 与 git 对跟踪集合各执一词——必有一方不再描述现实',
  },
  'gate.flip-census-phantom': {
    what: '某个 census .gos 条目声明 git:true 但其下没有任何被跟踪文件',
    why: '声明为已跟踪却无跟踪实体的区域属于台账漂移',
  },
  'gate.flip-manifest-missing': {
    what: '某个已跟踪的 .gos 文件既无 census git:true 认可，也无翻转清单记录',
    why: '义务附着于被跟踪文件——没有台账踪迹的被跟踪文件是未经记账的翻转',
  },
  'gate.flip.pass': '✓ flip-reconcile：{n} 个被跟踪 .gos 文件——census/git 取值一致，清单义务满足',
  'gate.flip.skipNoGit': 'flip-reconcile：不是 git 工作树——无从对账跟踪集合，本腿跳过',

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
  "setup.onboard.codingHint": "┃ 把 coding-standards 书集种入本仓库：gos init coding（命令原样，各语言一致）",
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

  // 令牌与 JSON 字段名保持原样不翻译；命令一律用 {cmd:…} 占位符
  'brownfield.fatal.line': '✗ {msg}',
  'brownfield.title': 'brownfield 接管报告 — {root}',
  'brownfield.hooksClass.unset': 'core.hooksPath：未设置——种下的钩子处于休眠（git 读 .git/hooks/；GOS 绝不写 .git/hooks/ 或 git config）',
  'brownfield.hooksClass.gosHooksDir': 'core.hooksPath：解析到 <top>/hooks——已是活跃的 gos 钩子目录；不会向其中种入任何文件',
  'brownfield.hooksClass.foreign': 'core.hooksPath：由外部钩子管理器接管——GOS 绝不碰 git config 或其钩子目录',
  'brownfield.assetsHeader': '资产清单：',
  'brownfield.reasonLine': '原因：{reason}',
  'brownfield.rem.header': '补救步骤：',
  'brownfield.rem.step': '{n}. {asset}：运行 {command}',
  'brownfield.ovr.header': '强制覆盖（破坏性——执行任何命令前先读后果说明）：',
  'brownfield.ovr.step': '{n}. 接管 {asset}：运行 {command}',
  'brownfield.ovr.consequence': '后果：{text}',
  'brownfield.err.notGit': '不是 git 仓库——{cmd:brownfield} 接管的是已存在的仓库（exit 4）',
  'brownfield.err.cwd': 'cwd 不是仓库顶层——请从 {top} 运行（exit 4；CLI 按 cwd 解析 .gos/）',
  'brownfield.err.self': '这是 GOS 仓库自身——自我接管属于开发动作，已拒绝（exit 5）',
  'brownfield.err.corruptState': '钩子状态文件损坏（不是可解析的 JSON）：{path}——修复或删除后重跑；它驱动卸载还原，绝不被改写（exit 1）',
  'brownfield.err.unknownFlag': 'brownfield 的未知 flag：{flag}（已知：--json、--overwrite [<asset>]、--print-agents-skeleton）',
  'brownfield.err.unexpectedArg': 'brownfield 的多余参数：{arg}',
  'brownfield.err.doubleOverwrite': 'overwrite flag 只传一次——裸传或带单个资产名',
  "brownfield.err.unknownAsset": "--overwrite 的资产名未知：'{name}'（探测到的资产：{known}）",
  'brownfield.err.lockedOverwrite': '拒绝 --overwrite {asset}：{why}',
  'brownfield.err.skeletonCombo': '--print-agents-skeleton 需单独使用——它打印起始骨架后即退出（不做任何仓库操作）',
  'brownfield.why.neverConfig': 'core.hooksPath 只读探测——GOS 绝不修改',
  'brownfield.why.agent': 'AGENTS.md / CLAUDE.md / GEMINI.md 是用户自有的引导文件——GOS 绝不写入（改为打印骨架）',
  'brownfield.why.userHook': '用户自有钩子文件（locked_user_owned）——GOS 绝不替换用户钩子；请人工审查并手动串联',
  'brownfield.why.foreignHooks': '外部钩子管理器持有 core.hooksPath（locked_user_owned）——GOS 绝不修改；请人工审查串联方式',
  'brownfield.why.liveDir': 'core.hooksPath 已解析到 <top>/hooks——种入会立即激活钩子；该目录归激活命令管理',
  'brownfield.why.blocked': '路径不可接管（{reason}）',
  'brownfield.why.userHookRow': '用户自有钩子（locked_user_owned）——仅人工审查；绝不自动替换',
  'brownfield.why.driftedHookRow': 'GOS 血统钩子带本地修改——原样保留',
  'brownfield.why.foreignRow': '外部钩子管理器持有 core.hooksPath（{raw}）——串联需人工审查；GOS 绝不修改',
  'brownfield.why.liveDirRow': 'core.hooksPath 解析到 <top>/hooks——种入会立即激活；该目录归激活路径管理',
  'brownfield.why.hooksPathRow.unset': '未设置——钩子休眠种入；GOS 绝不写 .git/hooks/ 或 git config',
  'brownfield.why.hooksPathRow.gosHooksDir': '解析到 <top>/hooks——已是激活布局',
  'brownfield.why.hooksPathRow.foreign': '外部值——只读探测，绝不修改',
  'brownfield.why.detected': '检测到既有 commitlint 配置（{names}）——不被种入的 yaml 遮蔽',
  'brownfield.why.divergedYamlRow': 'commitlint.config.yaml 与 GOS 母版不一致——原样保留',
  'brownfield.why.divergedGateRow': '文件与 GOS 种入的内容不一致——原样保留',
  'brownfield.why.noLock': '`.lock` 未被忽略——机器锁可能被提交',
  'brownfield.note.appended': '已补上缺失的 .lock 行',
  'brownfield.why.agentAbsent': '缺失——可通过 {cmd:brownfield} --print-agents-skeleton 打印起始骨架（仅 stdout，绝不写入）；此处 brownfield 指接管既有仓库，不是 D-22 决策导入',
  'brownfield.why.agentPresent': '已存在——用户自有文件，绝不触碰',
  'brownfield.why.agentIrregular': '路径被非常规条目占用——请人工审查',
  'brownfield.why.writeFailed': '写入失败：{message}',
  'brownfield.why.engineSkip': '本次不可接管——引擎跳过原因：{outcome}；请手动清理该路径上的目录或不可读文件后重试',
  'brownfield.cons.replace': '替换你的文件；备份在 {path}',
  "brownfield.cons.createBeside": "创建 'commitlint.config.yaml'——它会优先于你现有的配置生效（{names}）",
  'brownfield.cons.append': '向你的文件追加缺失的 .lock 行；备份在 {path}',
  'brownfield.handoff.header': '下一步：',
  'brownfield.handoff.mapPreview': 'codebase map：此处不运行——唯一触发点是 {cmd:init} <level>（Lv3 推荐、Lv4 自动生成）',
  'brownfield.handoff.platformsHeader': 'AI 平台技能链接（只读探测）：',
  'brownfield.handoff.platformRow': '{name}：{status}',
  'brownfield.handoff.platformFix': '修复缺失链接：运行 {cmd:setup} --no-onboard',
  'brownfield.handoff.noPlatform': '未检测到任何 AI 平台——运行 {cmd:setup} --no-onboard 链接 GOS 技能',
  'brownfield.skeleton.body': '# AGENTS.md —— 起始骨架\n# （逐节填写内容后删除这些注释行）\n\n项目介绍：这个仓库是什么、给谁用（一小段话）。\n\n## 构建\n\n如何构建/编译本项目——命令，以及成功构建是什么样子。\n\n## 测试\n\n如何运行测试套件——命令，以及如何判读结果。\n\n## 约定\n\n贡献者必须遵守的约定（代码风格、提交信息、评审流程）。\n',
  'brownfield.skeleton.note': '仅打印到 stdout——GOS 绝不写 AGENTS.md/CLAUDE.md/GEMINI.md；需要文件请自行重定向保存',

  // ---- spec gate 底线（卡列契约、版本域） ----
  'gate.spec-gate-card-column': {
    what: '决策卡表格违反列契约',
    why: 'Activates 列缺失、单元格为空、或与 Pros 列雷同——不指名消费者的价值内核单元格只是装饰，不是决策',
  },
  'gate.spec-gate-version-unknown': {
    what: 'spec gate 戳记超出本 CLI 认识的底线版本域',
    why: '未知戳记必须关门失败，新状态不能在旧 CLI 下空转放行',
  },

  // ---- commit 侧守卫（阶段单调性） ----
  'commit.stage-regression-blocked': {
    what: '请求的阶段 {stage} 落后于当前阶段 {current}',
    why: '已越过的阶段不能重复推进——该提交会给历史早已越过的节点再写一次推进标签',
    fix: '如需幂等重交请重跑当前阶段提交；要重新冻结 spec 请用 gos commit think --refreeze（仅改状态，不推进阶段）',
  },

  // ---- auto 模式：runner 信任存储（机器本地） ----
  'auto.store.missing': {
    what: '未找到 auto 运行时存储：{path}',
    why: '存储缺失与损坏同等对待——绝不静默重建新存储',
    fix: '运行 {cmd:auto} on 创建（若追踪计数器暗示历史用量会先告警）',
  },
  'auto.store.corrupt': {
    what: '{path} 的 auto 运行时存储损坏或未通过结构校验',
    why: '损坏的存储无法核验 runner 信任状态（计数器、熔断、锁、审批）',
    fix: '检查该文件；无法恢复时运行 {cmd:auto} off --purge 后 {cmd:auto} on——成本历史由追踪镜像计数保留',
  },
  'auto.store.versionMismatch': {
    what: '存储 schema v{found} 高于本 CLI 已知版本（已知 v{known}）',
    why: '未来形态的存储可能包含本版本会误读的记录',
    fix: '升级写入该存储的 GOS 版本；切勿手改 store_schema_version',
  },
  'auto.store.unwritable': {
    what: 'auto 运行时存储目录不可写：{path}',
    why: '不可写则 auto 循环无法持久化计数器、熔断状态与运行锁',
    fix: '检查属主/权限（及 XDG_DATA_HOME 覆盖值）后重新运行 {cmd:auto} on',
  },
  'auto.store.lockHeld': {
    what: '已有 auto 运行在进行中（pid {pid}，始于 {since}）',
    why: '运行锁按机器+仓库排他',
    fix: '等待其结束；确认真正卡死时，待心跳过期或核实无 gos 进程后再谨慎移除',
  },
  'auto.store.lockHeartbeatStale': {
    what: '运行锁由 pid {pid} 持有，但心跳已过期',
    why: 'pid 复用可伪造存活；过期心跳是第二信号',
    fix: '确认持有进程已死后，加 --break-lock 重试',
  },
  'auto.store.lockCrossHost': {
    what: '运行锁由另一台机器持有（{hostname}，克隆 {clone}）',
    why: '本机存储无法判断远端 pid——跨主机是否过期在本机不可验证',
    fix: '确认那台机器上无 runner 存活后再加 --break-lock（会记录为接管事件）',
  },
  'auto.store.lockBreakRefused': {
    what: '--break-lock 被拒绝：pid {pid} 在 {hostname} 上存活',
    why: '存活 pid + 新鲜心跳即锁的合法持有者；强拆会破坏运行中的循环（本次尝试已记录为接管事件）',
    fix: '等待运行结束；持有进程死亡后才可 break',
  },
  'auto.store.recreatedOverHistory': {
    what: '追踪计数器暗示存在历史用量（spawn {spawnCount} 次、trip {tripCount} 次），却要新建空存储',
    why: '成本历史不能因存储丢失而静默清零',
    fix: '确认这是预期行为——计数器会从追踪镜像继承',
  },

  // ---- auto 模式：主机适配器 / 能力协商 ----
  'auto.host.unknown': {
    what: '主机在 registry.json 矩阵中无条目',
    why: '未知主机一律 fail-closed',
    fix: '安装受支持的主机或新增矩阵条目',
  },
  'auto.host.probeVersion': {
    what: '二进制版本缺失或无法解析',
    why: 'spawn 时能力探测失败',
    fix: '更新主机二进制；消息中已列出矩阵条目',
  },
  'auto.host.probeNoMatch': {
    what: '已安装版本不满足任何矩阵条目',
    why: '版本偏斜',
    fix: '更新主机或新增 registry.json 条目',
  },
  'auto.host.probeHelpFlags': {
    what: '帮助输出缺少必需旗标',
    why: 'CLI 契约已变化',
    fix: '更新主机或修正条目的 required_flags',
  },
  'auto.host.probeConfig': {
    what: '主机配置根目录无法解析',
    why: '适配器需要配置根目录',
    fix: '创建主机配置目录或设置 OPENCODE_CONFIG_DIR',
  },
  'auto.host.invalidRow': {
    what: '矩阵条目 version_range 无效',
    why: '策略禁止恒等锁定',
    fix: '在 registry.json 使用语义谓词 (>=, <)',
  },
  'auto.host.registryUnreadable': {
    what: 'registry.json 缺失或损坏',
    why: '协商数据不可用',
    fix: '重装 GOS 或修复 registry.json',
  },
  'auto.host.statusNotSelectable': {
    what: '矩阵状态非 verified',
    why: 'fixture-tested/probe-pending 仅作展示',
    fix: '主机经 dogfood 验证翻转条目后方可选用',
  },
  'auto.host.streamMalformed': {
    what: '事件流包含畸形 JSON',
    why: '流契约被破坏',
    fix: '归类为失败计入熔断器，绝不崩溃',
  },
  'auto.host.streamNoTerminal': {
    what: '流结束时缺少终态事件',
    why: '无可验证结果',
    fix: '计为失败；建议重新探测主机版本',
  },
  'auto.host.displayOnly': {
    what: '对仅展示主机尝试 spawn',
    why: '该适配器无活动路径',
    fix: '改用 verified 主机',
  },
  'auto.host.spawnError': {
    what: '主机进程 spawn 失败或超时',
    why: '环境类失败',
    fix: '以 env 类失败计入熔断器',
  },

  // ---- auto 模式：能力启动器（档位 + 沙箱引擎） ----
  'auto.launcher.unknown-profile': {
    what: 'auto 档位 "{name}" 不在可选列表：{known}',
    why: '未知档位绝不静默回退——掩码与 deny 姿态不能靠猜测',
    fix: '传 {known} 之一（默认 restricted）；full 还需显式 allowFull 标志',
  },
  'auto.launcher.full-flag-required': {
    what: '请求 full 能力档位但未携带显式升级标志',
    why: 'full 放宽了 deny 基线，必须是明确选择而非默认漂移',
    fix: '带上显式 allowFull 选项重跑，或继续使用 restricted/workspace',
  },
  'auto.launcher.missing-mandatory-mask': {
    what: '档位 "{profile}" 缺少强制掩码：{missing}',
    why: '信任存储、交付凭据与宿主状态目录在所有档位都必须被掩蔽——缺一项就重新打开旁路',
    fix: '在 profile 文件中恢复对应 mask 条目，或升级 CLI 使档位保持完整',
  },
  'auto.launcher.profile-corrupt': {
    what: 'auto 档位 "{name}" 校验失败：{detail}',
    why: '残缺的能力档位无法安全组装',
    fix: '修复 {file} 中的 JSON 或重装模板',
  },
  'auto.launcher.profile-unreadable': {
    what: 'auto 档位 "{name}" 无法读取（{detail}）',
    why: '启动器拒绝在未验证档位时派生会话',
    fix: '恢复 {file} 或重装 CLI 包',
  },
  'auto.launcher.escape-detected': {
    what: '派生会话流命中 deny 模式 "{pattern}"：{line}',
    why: '词法层是纵深而非冗余——捕获流出现命中说明注入配置被绕过或忽略',
    fix: '检查 store 中的派生记录；断路器将其计为一次失败',
  },
  'auto.launcher.tier-lexical': '加固档位：lexical——PATH 上无沙箱引擎（bwrap）；deny 仅由注入配置与逃逸探测器兜底（网络保持开放；模型提供方凭据按设计可读）',

  // ---- auto 模式：熔断器（三层暂停护栏） ----
  'auto.breaker.invalidLimits': {
    what: '熔断器上限被拒绝：{detail}',
    why: 'N/K/B 是带下限保证的护栏——静默钳制或补默认值会让循环以弱于配置的保护继续运行',
    fix: '为 N（连续失败）、K（stage 进入次数）、B（派生预算）全部传入 >= 1 的整数',
  },
  'auto.breaker.tripped': {
    what: '自动循环已暂停：熔断层 {layer} 触发——{reason}',
    why: '熔断后绝不自动恢复；暂停时保留配置，显式重新启用即可原样恢复',
    fix: '用 {cmd:auto} status 查看熔断记录，处理对应失败类别后用 {cmd:auto} on 重新启用',
  },
  'auto.breaker.invalidTimeout': {
    what: '{name} 的值无效：{value}',
    why: '单次派生超时是安全边界——格式错误的覆盖值绝不能静默回退默认值',
    fix: '设置为 >= 1 的整数秒数，或清除该变量以使用默认值（墙钟 3600 秒、空闲 600 秒）',
  },
  'auto.breaker.advanceCheckFailed': {
    what: 'stage 推进判定失败：无法建立 git 可达性真相',
    why: '推进以提交可达性计分，绝不用时间戳——没有 git 真相就无法判定结果',
    fix: '检查仓库健康（派生前 HEAD oid 与当前 HEAD 都必须可解析），然后恢复自动循环',
  },

  // ---- auto 模式：循环执行器 ----
  'auto.loop.markerActive': {
    what: 'auto 家族拒绝在 runner 派生的会话内运行',
    why: '派生的阶段会话绝不能持有循环控制权（标记即边界）',
    fix: '在普通终端运行 {cmd:auto} 相关命令',
  },
  'auto.loop.modeOff': {
    what: 'auto 模式处于关闭状态',
    why: '恢复绝不自动派生；关闭的存储仅是配置',
    fix: '用 {cmd:auto} on 重新启用后再运行',
  },
  'auto.loop.noTask': {
    what: '没有活跃的 GOS 任务——auto 循环无任务可驱动',
    why: '循环按阶段推进的是单个活跃任务',
    fix: '先用 {cmd:init} 启动任务，再重新运行',
  },
  'auto.loop.taskAtEnd': {
    what: '任务已处于 {stage} 阶段——auto 循环到此结束',
    why: '归档与交付是人工关卡；无交付适配器也能干净终止',
    fix: '手动完成该阶段（归档/推送），或开始下一个任务',
  },
  'auto.loop.hostNotSelectable': {
    what: '主机 {host} 不可用于真实运行',
    why: '只有 verified 状态的主机可派生会话，其余状态仅作展示',
    fix: '用 {cmd:auto} status 查看主机矩阵并选择已验证的主机',
  },
  'auto.loop.detachedHead': {
    what: '仓库处于 detached HEAD 状态',
    why: '阶段提交将无法归属到任何分支',
    fix: '检出任务工作分支后重新运行',
  },
  'auto.loop.workBranchFailed': {
    what: '无法从主干分支 {branch} 切换到工作分支 {work}',
    why: '循环绝不在主干上开发（仅 PR 裁决）',
    fix: '解决检出阻碍（提交或暂存）后重新运行',
  },
  'auto.loop.externalMutation': {
    what: '任务状态在 auto 循环之外被改动：{detail}',
    why: '外部改动以暂停报告处理——绝不计入连续失败层',
    fix: '审查该改动；若为有意为之，再显式恢复循环',
  },
  'auto.loop.stateCorrupt': {
    what: '任务状态无法读取',
    why: '状态不可读则循环无法复核任务身份',
    fix: '修复 .gos/state.json 后恢复 auto 循环',
  },
  'auto.loop.spawnComposeFailed': {
    what: '启动器能力档案组合失败：{detail}',
    why: '没有组合好的能力档案就不派生任何会话',
    fix: '检查档案模板与引擎探测结果后恢复',
  },
  'auto.loop.stampFailed': {
    what: '流戳记写入被拒绝：{detail}',
    why: '派生与流的配对必须在任何消费者读取前可验证',
    fix: '检查存储；无法恢复时运行 {cmd:auto} off --purge 后 {cmd:auto} on',
  },
  'auto.loop.iterationCap': {
    what: '已达迭代上限 {max}',
    why: '显式安全上限先于熔断层止住了循环',
    fix: '提高上限或重新发起一次运行',
  },

  // ---- auto 模式：批准边界（委派审批） ----
  'auto.ratify.pendingRecorded': '阶段 {stage} 的审批已记为 PENDING（auto）：仅做结构性检查——runner 会在会话退出后依据捕获流戳记完成批准',
  'auto.ratify.pendingBlocks': {
    what: '阶段 {stage} 存在未获 runner 批准的 PENDING 自动审批',
    why: '一次委派阶段的推进在 runner 批准落地前发生——证据从未对照外部存储核验过',
    fix: '恢复 auto 循环由 runner 依据存储戳记完成批准（{cmd:auto} run），或经 {cmd:auto} status 查看戳记记录；切勿手改审批记录',
  },
  'auto.ratify.stampMissing': {
    what: 'runner 存储中没有派生 {spawnId} 的流戳记',
    why: '批准以派生与其捕获流哈希配对——没有戳记就无法核验该配对',
    fix: 'runner 会在每次派生退出时写入戳记；缺失说明派生未完成或存储被重置——重跑该阶段',
  },
  'auto.ratify.stageMismatch': {
    what: '派生 {spawnId} 的流戳记属于其他阶段而非 {stage}',
    why: '批准按阶段限定——其他阶段的戳记不能越过此边界',
    fix: '以派生实际工作的阶段执行批准，或重跑该阶段派生',
  },
  'auto.ratify.hashMismatch': {
    what: '派生 {spawnId} 的捕获流哈希与存储戳记不符',
    why: 'runner 观察到的流与戳记的流不一致——配对可能已被篡改',
    fix: '将该阶段产出视为未核验；检查存储记录并重跑该阶段派生',
  },
  'auto.ratify.noTask': {
    what: '无可读取的任务状态用于批准',
    why: '批准后的审批要写回任务状态文件',
    fix: '在含活跃任务的仓库根目录运行，然后重新运行 auto 循环',
  },

  // ---- auto 模式：红队编排 ----
  'auto.redteam.promptDrift': {
    what: '存储中的红队提示模板哈希与 runner 模板不一致',
    why: '红队证据只能与 runner 持有的提示配对——哈希漂移意味着配对失效',
    fix: '若漂移符合预期，运行 {cmd:auto} off --purge 后再 {cmd:auto} on 重建存储',
  },
  'auto.redteam.composeFailed': {
    what: '组合红队评审派生失败：{detail}',
    why: '评审派生必须在能力档案下组合且工作区只读',
    fix: '检查档案数据与引擎探测结果后重试该轮',
  },
  'auto.redteam.stampFailed': {
    what: '红队轮次写入存储被拒绝：{detail}',
    why: '轮次与流的配对必须在任何消费者读取前可验证',
    fix: '检查存储；无法恢复时运行 {cmd:auto} off --purge 后 {cmd:auto} on',
  },
  'auto.redteam.findingsUnparsable': {
    what: '一轮红队评审结束时没有可识别的发现数结论',
    why: '垃圾输出归类为失败轮——绝不计为零发现',
    fix: '重跑该轮；持续失败将由委托门保持并转人工审查',
  },
  'auto.redteam.roundFailed': {
    what: '一轮红队评审派生在给出结论前失败',
    why: '失败的派生不构成审查证据，绝不计为零发现',
    fix: '排查派生失败详情（本地存储）后重跑该轮',
  },
};
