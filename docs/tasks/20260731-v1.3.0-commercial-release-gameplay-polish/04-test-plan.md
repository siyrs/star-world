# Test Plan

## Test Scope
- 当前源码 fresh Windows Release、全部正式地图/世界预设/任务/内容、正常与极端输入、碰撞/边界、水域/水下、存读档/死亡复活/切换、UI/音频/设置、性能/长稳、日志、修复回归。

## Out of Scope
- 未经授权的正式发布/推送、付费/账号资源、非 Windows 导出目标。工具缺失不自动移出范围，先尝试项目内替代。

## PM ↔ QA Test Strategy Alignment
| Item | Result | Notes |
|---|---|---|
| Test scope agreed | yes | QA-001 已独立复核 TC-001..020、五地图沙盒旅程和发布证据边界 |
| Test data ready | yes | 五个正式 Profile、固定 Seed、唯一 QA 世界命名和用户数据哈希保护规则已确定 |
| Test environment ready | yes | Windows x64、Godot 4.7、本地 export templates、GL Compatibility |
| Pass/fail criteria agreed | yes | P0/P1 必须为 0 或有外部阻塞证据；AC-001..010 |
| Regression scope agreed | yes | 原复现、相邻流程、全部受影响 Profile、fresh EXE 与 production-scene 双层证据 |

## QA Questions Back to PM
| Question | Reason | PM Answer | Need User Confirmation | Status |
|---|---|---|---|---|
| 如何定义程序化世界的“地图完整覆盖”？ | 可能没有独立关卡场景 | PM：以全部正式世界预设/生物群系/任务区域/特殊区域/入口为唯一清单，固定 Seed 和兴趣点证据；正常玩家路径仍需验证 | no | resolved |

## Test Environment
- Environment: Windows x64；Godot 4.7 stable；GL Compatibility；1280×720 基线，另测窗口/全屏和代表性分辨率。
- Branch / Commit: `codex/commercial-release-gameplay-polish`；每轮记录精确 commit。
- Test data: 当前用户 `user://worlds` 的 12 个世界、settings、trash 和 recovery 为不可变基线；QA 世界使用 `qa-v130-<UTC>-<profile>-<seed>`；损坏/旧档测试只能操作备份副本。每个 Profile 的出生回归至少覆盖固定 Seed，正式旅程记录实际 Profile/Seed/world id。

## Test Cases
| ID | Function Point | Related AC | Scenario | Steps | Expected Result | Priority | Status |
|---|---|---|---|---|---|---|---|
| TC-001 | FP-001,FP-003 | AC-001 | 当前源码导入、全量回归与 fresh release smoke | 运行 editor scan、`tests/run_all.ps1`、独立输出 fresh export/smoke | 命令退出 0；新产物哈希/时间戳；启动/退出、JSON/截图/日志齐全，无致命日志 | P0 | not-started |
| TC-002 | FP-002 | AC-002,AC-003 | 地图和内容发现完整性 | 交叉 scenes/data/src/menu/save/teleport/测试与正式入口，去重并标记正式/隔离 | 无未解释可加载正式内容；每项有来源和入口 | P0 | not-started |
| TC-003 | FP-004 | AC-002,AC-003 | 每个正式 Profile 的正常入口发布验收旅程 | 从主菜单用真实 InputEvent 新建固定 Seed QA 世界；完成移动/转向/跳跃/冲刺/采集/拾取/放置/背包/合成/暂停，跨越至少一个 chunk 接缝并返回，完成探索里程碑/奖励，保存→菜单→继续，死亡→复活→再次保存/读取 | Profile/Seed/world id、出生/相机/HUD/音频/日志正确；关键状态往返一致；无 P0/P1。项目没有传统主支线、结算或胜利状态，故“通关”记为 N/A，不得伪造通关 | P0 | in-progress |
| TC-004 | FP-004 | AC-002,AC-003 | 重复进入、正常菜单切换和返回 | 每个 Profile 首次进入、退出菜单、Continue、再次进入；通过新建/读取切换世界后返回 | 无黑白屏/卡死/错误出生/状态丢失；项目无正式传送入口，传送项记 N/A | P0 | not-started |
| TC-005 | FP-005 | AC-004 | 碰撞、空气墙、接缝、边界、高低处/狭窄区 | 正常探索并执行贴墙、墙跳、斜坡、高落、边界绕行 | 视觉与碰撞一致，不穿模/永久卡死/掉世界；意外跌落可恢复 | P0 | not-started |
| TC-006 | FP-006 | AC-004 | 正式水体/冰下水体/熔岩全状态流转 | 星辰大陆岸边/高处入水、浅深水、水面/水下、反复进出/上岸；极寒冰原验证冰层与冰下水；深渊世界验证熔岩接触/伤害/死亡恢复 | 已实现的流体移动、碰撞、相机与恢复稳定；未实现的氧气/溺水/专用水下视听必须以产品事实记 N/A，不得伪造；熔岩若正式可达必须有安全伤害/恢复行为 | P1 | not-started |
| TC-007 | FP-006,FP-007 | AC-004,AC-005 | 水中交互、死亡、复活、存读档、地图切换 | 执行水中极端流程 | 水状态不残留/重复应用，死亡与读档安全 | P0 | not-started |
| TC-008 | FP-007 | AC-005 | 新建/自动/手动/覆盖/多槽/重进 | 保存位置、方向、地图、任务、背包、装备、建造、解锁、NPC/敌人、生命/时间 | 全部重要状态往返一致 | P0 | not-started |
| TC-009 | FP-007 | AC-005 | 任务/对话/战斗/死亡前后存读档 | 各状态保存、退出、重开并继续 | 不重复初始化/领奖，不阻塞、不进入模型/地下 | P0 | not-started |
| TC-010 | FP-007 | AC-005 | 损坏与旧存档容错 | 使用隔离副本注入截断/未知字段/旧版本样本 | 游戏不因单个坏档无法启动；日志有上下文；安全回退/迁移 | P0 | not-started |
| TC-011 | FP-008 | AC-006 | 主菜单/HUD/背包/合成/设置/暂停/退出 | 正常操作及快速反复开关 | 按钮、焦点、布局、文本、状态和退出正确 | P1 | not-started |
| TC-012 | FP-008 | AC-006 | 分辨率、窗口/全屏、焦点丢失恢复 | 切换代表性分辨率和显示模式，Alt-Tab 恢复 | UI 不遮挡/溢出；输入/音频/暂停行为合理 | P1 | not-started |
| TC-013 | FP-008 | AC-006 | 连跳/冲刺/攻击/拾取/交互/物品切换/建拆极端操作 | 快速连续与边移动边操作 | 无状态锁死、重复奖励、明显延迟或日志刷屏 | P1 | not-started |
| TC-014 | FP-008 | AC-006 | NPC/敌人/AI/音频/动画反馈 | 触发全部正式实体与攻击/受伤/死亡/掉落 | AI 不大面积卡死/隔墙攻击，反馈与状态匹配 | P1 | not-started |
| TC-015 | FP-009 | AC-007 | 主菜单及每图关键区域性能基线 | 固定参数采集 FPS/1% low/帧时/CPU/GPU/内存/显存/GC/加载 | 数据完整可重复，无严重卡顿；瓶颈有根因 | P1 | not-started |
| TC-016 | FP-009 | AC-007 | 快速移动/转镜头/地图切换/连续读档/大量实体压力 | 运行固定压力脚本并采样 | 不崩溃/死循环；资源与帧时恢复到合理区间 | P1 | not-started |
| TC-017 | FP-009 | AC-007 | 长时间运行 | 覆盖代表性地图和状态的有界 soak，周期采样 | 无持续非预期内存增长、严重掉帧或高频错误 | P1 | not-started |
| TC-018 | FP-010 | AC-008,AC-009 | 每项问题修复 focused regression | 用原复现步骤和新增自动化重测 | 原问题消失且相邻流程无回归 | P0 | not-started |
| TC-019 | FP-010 | AC-008,AC-009 | QA 报告缺陷修复重测循环 | QA 报 bug→Developer 修复自测→同一 QA 用例复测 | QA 明确通过；不得跳过重测 | P0 | not-started |
| TC-020 | FP-011 | AC-010 | 发布文档和 Git 完整性 | 核对覆盖矩阵、问题、性能、回归、报告、提交和 Git 状态 | 小提交齐全；无密钥/大临时产物；未推送/发布 | P0 | not-started |

## Bugfix Retest Cases
| Bug ID | Retest Case ID | Steps | Expected Result | Status |
|---|---|---|---|---|
| BUG-QA-002 | RTC-QA-002 | 用调用方指定的精确 `-OutputPath` 运行 production-scene desktop acceptance，并核对主截图与 10 个命名截图 | 内层 32 checks/10 captures 与外层 runner 均 exit 0；精确输出存在且非空 | qa-passed |
| BUG-UI-002 | RTC-UI-002 | 重跑 headless design-system 与 desktop visual；独立查看 map/settings，补 1024×576，并覆盖 Button/Secondary/Primary/MenuPrimary/Card/Selected/Ghost/Danger 的 normal/hover/pressed/focus | 12px 文本按有效合成背景 WCAG ≥4.5；disabled 单列可辨；无重叠/截断；真实 pointer 状态和返回按钮可辨认 | bugfixing |
| BUG-SPAWN-001 | RTC-SPAWN-001 | 5 profiles×6 fixed seeds（含 24681357）、合成树叶遮挡夹具、相邻地形/旧档/解析器回归；复跑 desktop input contract 与三轮 leak 检查 | 确定性开放出生、可离开、无水/熔岩/冰面/临崖、无 1 米下调；无相邻回归或 ObjectDB leak | bugfixing |
| 动态登记 | RTC-<BUG-ID> | 先执行原始复现，再验证修复并覆盖相邻状态 | 缺陷不可复现；日志/性能无退化；QA 独立确认 | not-started |

## Regression Scope
- 全部 AC-001..010；每张正式地图；每个受影响系统的正常、失败、重入、存读档和相邻极端路径；全量自动化、fresh release smoke、长稳和日志扫描。

## Five-profile Release Journeys

| Profile | Required release journey focus | Seeds / evidence |
|---|---|---|
| `star_continent` | 森林、平原、河流、夜间敌对；跨 chunk 接缝；水域；探索里程碑 | 固定 seed + 实际 Profile/Seed/world id、截图、日志、状态快照 |
| `desert_ruins` | 沙地、遗迹、石柱、仙人掌、地下富矿；建筑内外与地下返回 | 同上 |
| `frozen_wastes` | 雪地、高峰、冰层与冰下水、饥饿加速；高低差/边界恢复 | 同上 |
| `sky_islands` | 浮岛、高空坠落/恢复、搭桥建造、岛间可达 | 同上 |
| `abyss_world` | 洞穴、大型地下、晶体、敌对、熔岩接触/死亡恢复 | 同上 |

- 项目正式内容没有传统 Quest/Mission、主支线、胜利、结算或后续关卡；因此每图“通关”严格记为 N/A，以完整正常入口发布验收旅程和八个探索里程碑总体覆盖作为当前产品的可完成性标准。
- 每个 Profile 首次/重复进入、保存→菜单→继续、死亡→复活→再保存/读取均必须实际执行；不能以直接调用通关函数或修改存档替代。

## Performance and Soak Pass Rules

- fresh Windows EXE，1280×720、GL Compatibility、VSync off；记录 OS/CPU/RAM/GPU/driver/power mode、commit、EXE/PCK hash、渲染器、分辨率、工具和固定 Seed。
- 每个 Profile warm-up 60 秒后采样至少 180 秒：平均 FPS ≥50、1% Low ≥40、p95 frame time ≤25 ms、p99 ≤33.3 ms；声明的加载段以外不得频繁出现 >100 ms。
- fresh EXE 从启动到可操作 ≤15 秒；chunk pending 必须在 30 秒内降至 warning 以下并连续 3 个样本稳定，且无 critical。
- 120 分钟长稳覆盖五 Profile、保存/读取和菜单往返；无崩溃或持续退化。warm-up 后 Private/Working Set 斜率 ≤1 MiB/min，结束增长 ≤15%，返回菜单后合理回落。
- Godot refcount 模型若没有 GC 次数/停顿指标则明确记 N/A，并以 allocator/object/frame spike/leak 证据替代；不得写 0 假装有效。
- CPU 或 GPU ≥95% 且 FPS 未达门槛为 P1；优化前后必须同硬件、Seed、场景、时长，关键指标不得回归超过 5%。
- 任何 P0/P1 未关闭均为不发布；计时/flaky/性能修复要求连续 3 次通过。

## Entry Criteria
- [x] Development handoff completed（首批 BUG-QA-002/UI-002；spawn 包仍在 bugfixing）
- [x] Self-test evidence provided（首批；不代表 QA 通过）
- [x] Test environment ready
- [x] 地图与内容唯一清单完成
- [x] QA 隔离存档/Seed/证据目录就绪

## Exit Criteria
- [ ] P0 cases passed
- [ ] No blocking bugs
- [ ] Regression scope completed
- [ ] 所有正式地图实际进入且可通关地图实际通关
- [ ] P1 为 0 或有外部阻塞证据
- [ ] 性能前后数据与长稳结果齐全

## QA Readiness Decision
- Concrete test cases ready before implementation: yes
- Retest expectations defined: yes
- Ready at: 2026-07-31 10:27 +08:00
- Notes: QA-001 已独立完成 Gate 4 复核，无开放问题；所有 QA 报告 bug 必须由 Developer 修复+self-test，再由同一 QA 使用原用例与相邻流程重测。
