# 星的世界 · Product & Architecture Roadmap

## 产品定位

《星的世界》是长期可扩展的单人沙盒生存建造游戏基础，而不是只展示体素地形的 Demo。

核心原则：

- 玩家体验优先；
- 系统模块化、数据驱动；
- 每个玩法拥有明确状态所有者；
- 功能先形成可玩的闭环，再扩展内容数量；
- 重要功能必须可测试、可保存、可恢复；
- 旧世界、方块 numeric ID 和 Seed 结果必须有兼容策略；
- 高数量对象必须共享调度并具有预算；
- 真实桌面与最终 Windows Release 是合入主分支的必要证据。

## 当前领域结构

```text
Game Runtime
├─ World Domain
│  ├─ Chunk Streaming / Terrain Generation
│  ├─ Recent Chunk Snapshot Cache
│  ├─ Bounded World Mutation Batching
│  ├─ Resource Distribution / Map Identity
│  └─ Directional / Connected / Structural Block Geometry
│
├─ Player Domain
│  ├─ Movement / Ladder Climbing / Survival
│  ├─ Inventory Transactions
│  ├─ Equipment / Attributes
│  └─ Combat Cadence
│
├─ Creature & Ecology Domain
│  ├─ Creature Catalog / Conditional Ecology
│  ├─ Population / Per-species Budgets
│  ├─ Weighted Danger / Event Batching
│  └─ Dodgeable Hostile Windups / Elite Ecology
│
├─ Exploration Domain
│  ├─ Bounded / Calibrated Prospecting
│  ├─ Persistent Journal / Milestones
│  └─ Atomic Rewards
│
├─ Agriculture & Ranch Domain
│  ├─ AgricultureRuntimeParticipant / Pausable Crops
│  ├─ Atomic Harvest / Soil / Fertilizer
│  ├─ Husbandry / Breeding / Attraction
│  └─ Persistent Products / Batched Feedback
│
├─ Machine Domain
│  ├─ Indexed MachineRuntimeScheduler
│  ├─ FurnaceService / StonecutterService
│  ├─ MachineInteractionRouter / Atomic Capability
│  └─ Bounded Adjacent Chest Automation
│
├─ Persistence & Release Domain
│  ├─ Atomic Save Transaction / Backup Recovery
│  ├─ Bounded Pause-aware Autosave / Retry Evidence
│  ├─ Bounded Save Checkpoint Timeline / Source Correlation
│  ├─ Lightweight Self-healing World Catalog
│  ├─ Bounded Read / Write / Transient Catalog Stage
│  ├─ Protected Trash / Bounded Slot Manager / Original-ID Restore
│  ├─ Domain Migration / Settings Whitelist
│  └─ Resumable GitHub Release Auto-update
│
└─ Experience & Composition Layer
   ├─ Professional Celestial UI Design System / UI Kit
   ├─ Hero Menu / Responsive Management Workspaces
   ├─ HUD / Feedback / Audio
   ├─ First-person Viewmodel
   ├─ Input Contexts / Guidance
   ├─ Canonical Settings / Fact-driven Autosave Feedback
   ├─ Virtualized & Indexed Save Browser / Query / Sort
   ├─ Two-step Delete Confirmation / Undo Restore
   ├─ Virtualized Trash Manager / Selected Restore / Confirmed Purge
   ├─ Runtime Diagnostics / Unified Runtime & Save Health
   ├─ F3 Save Source / Checkpoint Timeline
   └─ Seven Feature Lifecycle Participants
```

## 已完成里程碑

### 1. 运行、保存与发行可靠性

- 真实 WASD、鼠标、按钮和输入上下文；
- 世界启动保护、非空白画面和安全出生；
- 渐进 Chunk 加载/卸载、自适应预算和最近 64 个卸载 Chunk 快照；
- F3 诊断、多轮生命周期 soak 和资源泄漏门禁；
- 统一运行与保存健康报告：机器、农业、畜牧、牧场、生态、Chunk、掉落、结构、目录和保存证据进入同一 Telemetry 时间线；
- 健康投影最多 12 行、8 条问题，75% 警告、90% 严重，并确定性显示主要瓶颈；
- F3 双栏显示保留原运行诊断，同时呈现最近保存字节/耗时、目录回退/自愈和共享预算；
- 保存检查点时间线严格区分 manual、autosave、return_to_menu、system，固定保留最近 12 条事件；
- 检查点被淘汰后四类来源累计与 dropped 计数仍精确，任意扩展 payload 均被白名单剔除；
- F3 显示保存来源累计、历史预算、最近检查点和下一次自动保存倒计时，时间线不进入 `world.json`；
- 成功返回主菜单或启动失败会结束健康报告中的世界身份，最终保存失败则继续保留当前世界与观察引用；
- 有界自动保存按未暂停活动时间运行，可选关闭或 2/5/10/15 分钟，单帧最多计入 1 秒；
- 自动保存复用正式 `save_current()`，手动成功保存取消 pending 并重置同一倒计时，不创建第二个 Timer 或存档域；
- 连续自动保存失败使用 15/60/300 秒有界退避，成功后清零失败压力，领域只发事实并由组合层展示；
- `GameSettingsPolicy` 统一默认值、范围、白名单和自动保存周期，SettingsPanel 不再拥有重复默认字典；
- 自动保存作为第七个 FeatureLifecycle 参与者依赖全部持久玩法域，反向清理时最先停机；
- 最终保存失败时继续保留当前世界和 F3 world attachment，只有成功返回主菜单后才解除运行时观察；
- 原子 JSON、临时文件、备份恢复和严格存档迁移；
- `world.json` 语法损坏或核心结构失效时，会从有效 `.tmp` / `.bak` 恢复并原子重建主文件，同时保留有效备份；
- 存档浏览器和 F3 显示恢复、主文件修复与失败证据，目录只在权威主文件重新可用后自愈；
- 轻量世界目录：`world.json` 保持唯一权威，`catalog.json` 缺失或损坏时按需自愈；
- 目录 sidecar 重建拥有独立的每次最多 16 个写入预算，世界始终可见并确定性收敛；
- 缺失目录时完整存档读取每次最多 32 个，预算外世界使用可继续的占位行并渐进补齐 metadata；
- 跨刷新目录暂存最多 64 项严格白名单 entry，96 世界完整读取由 176 次降为恰好 96 次；
- 存档浏览器固定 24 行复用池，通过分页访问全部世界，刷新与翻页不再按世界数量创建控件；
- 存档面板可见时每帧最多推进一次目录整理、最多自动整理 6 轮，积压归零后立即停用 process；
- 存档 metadata 使用只读浅引用和 `world_id → metadata` 直接索引，不再全量深拷贝或线性查找；
- 存档搜索覆盖名称、ID、地图和 Seed，查询最长 64 字符、最多 8 个唯一 token，逐键输入不触发全目录工作；
- 存档排序支持最近更新、名称和存档大小，平局由稳定 world ID 确定性打破；
- 搜索、排序和分页只作用于内存索引，不增加 catalog `list_count`，隐藏选择会自动清空；
- 玩家删除必须二次确认，首击不执行任何磁盘操作，选择、查询、刷新或隐藏面板会取消确认；
- 完整世界目录通过原子重命名进入回收站，Primary、Sidecar、`.bak/.tmp` 与未来目录文件一起保留；
- 回收站最多 32 个物理目录，满时拒绝新删除而不是自动清理旧数据；
- 删除时间使用跨会话严格单调 Unix 微秒序列，同一秒快速删除仍能确定真实最近条目；
- 撤销恢复使用原 world ID，冲突时保留 Trash，成功后 Primary、Sidecar 和 Backup 不重写；
- 固定 24 行的回收站管理页通过最多两页访问 32 个物理槽位，翻页不增加目录扫描；
- 回收站支持指定恢复任意有效条目，损坏 Manifest 明确显示、禁止恢复但可经二次确认清理；
- 永久清理只接受安全 Trash ID，释放精确一个容量单位，不调用活动世界 `delete_world()`；
- 异常外部目录扫描最多 64 个，并通过损坏与溢出标量诊断保持有界；
- 玩家 UI 永不调用维护级永久 `delete_world()`，测试和明确维护清理仍保留兼容 API；
- 主菜单显示存档大小、目录耗时、待读世界、目录待写、暂存数量、暂存命中、搜索匹配、分页边界和可管理回收站状态；
- 生产世界不再保存或构造无用的 `loaded_chunks`；
- Windows Release 实际导出、启动、截图、报告和退出资源检查；
- Range / If-Range / ETag 跨重启续传、双重 SHA-256 和失败回滚；
- Tag 驱动的 Windows GitHub Release 固定资产发布。

合同见：

- [BOUNDED_AUTOSAVE_RUNTIME.md](BOUNDED_AUTOSAVE_RUNTIME.md)
- [SAVE_CHECKPOINT_TIMELINE.md](SAVE_CHECKPOINT_TIMELINE.md)
- [RUNTIME_HEALTH_REPORT.md](RUNTIME_HEALTH_REPORT.md)
- [SELF_HEALING_SAVE_RECOVERY.md](SELF_HEALING_SAVE_RECOVERY.md)
- [WORLD_CATALOG.md](WORLD_CATALOG.md)
- [BOUNDED_CATALOG_REBUILD.md](BOUNDED_CATALOG_REBUILD.md)
- [BOUNDED_AUTHORITATIVE_READS.md](BOUNDED_AUTHORITATIVE_READS.md)
- [TRANSIENT_CATALOG_STAGING.md](TRANSIENT_CATALOG_STAGING.md)
- [VIRTUALIZED_SAVE_BROWSER.md](VIRTUALIZED_SAVE_BROWSER.md)
- [INDEXED_SAVE_BROWSER.md](INDEXED_SAVE_BROWSER.md)
- [PROTECTED_SAVE_DELETION.md](PROTECTED_SAVE_DELETION.md)
- [BOUNDED_TRASH_MANAGER.md](BOUNDED_TRASH_MANAGER.md)
- [GITHUB_RELEASE_AUTO_UPDATE.md](GITHUB_RELEASE_AUTO_UPDATE.md)
- [RECENT_CHUNK_SNAPSHOT_CACHE.md](RECENT_CHUNK_SNAPSHOT_CACHE.md)

### 2. 建造、交互和结构完整性

- 工作台、箱子、熔炉、修理台、床和石材切割机；
- 精确目标、统一放置预览和非空内容保护；
- 台阶、四方向楼梯、玻璃板、木栅栏、双格木门和贴墙梯子；
- 双格木门原子放置、上下半一致开关、成对采集和旧 numeric ID 兼容；
- 梯子四方向薄碰撞、真实攀爬、跳离和瞬时攀爬状态；
- 玻璃板与栅栏从实时邻居派生连接臂/横杆，不保存邻接掩码；
- 预览、视觉、碰撞、采集和完整重载共享同一形状合同；
- 邻居改变只重建当前与边界 Chunk；
- 多格场地和大规模世界修改通过 4,096 项有界批次收敛重建；
- 门地面或梯子背墙失效时，通过一个可暂停共享结构完整性运行时自动清理；
- 候选队列、每帧候选、结构和修改均有硬预算，内部删除事件不会递归排队；
- 失效门与梯子精确返回规范物品，背包满时按类型聚合到现有共享物理掉落运行时；
- 旧世界中的浮空半门和无支撑梯子在世界开始后按稀疏覆盖自愈；
- 128 扇门与 256 个梯子的跨 Chunk 支撑压力、保存、重载和满背包回退形成永久门禁。

合同见：

- [CONNECTED_BLOCK_SHAPES.md](CONNECTED_BLOCK_SHAPES.md)
- [DOUBLE_HEIGHT_OAK_DOORS.md](DOUBLE_HEIGHT_OAK_DOORS.md)
- [DIRECTIONAL_LADDER_CLIMBING.md](DIRECTIONAL_LADDER_CLIMBING.md)
- [BOUNDED_WORLD_MUTATION_BATCHING.md](BOUNDED_WORLD_MUTATION_BATCHING.md)
- [BOUNDED_STRUCTURAL_INTEGRITY.md](BOUNDED_STRUCTURAL_INTEGRITY.md)

### 3. Machine Base 与轻量自动化

- 单一可暂停机器调度循环，没有每机器 Timer；
- 最多 16 个机器领域、4,096 台持久机器和四小时有界离线推进；
- 活跃机器索引、可运行 Furnace/Stonecutter 索引和批量完成反馈；
- 512 台真实机器供料、加工、收货、保存和完整重载验收；
- 通用机器槽位、原子插入/提取和满背包零部分写入；
- 上方箱子供料/燃料、下方箱子收货；
- 每 0.5 秒最多检查 16 台机器、搬运 64 件并进行 128 次事务探测；
- 自动化游标、候选缓存和运行统计不进入存档。

合同见：

- [MACHINE_BASE.md](MACHINE_BASE.md)
- [MACHINE_CAPABILITY_CONTRACT.md](MACHINE_CAPABILITY_CONTRACT.md)
- [LIGHTWEIGHT_MACHINE_AUTOMATION.md](LIGHTWEIGHT_MACHINE_AUTOMATION.md)

### 4. 农业、畜牧与牧场生产链

- 小麦、胡萝卜、马铃薯，多阶段成长、灌溉、堆肥和自动补种；
- 农业真实 Pause、四小时有界离线成长和原子成熟收获；
- 2,048 株真实作物同批成长、可视化、保存和重载验收；
- 重叠水源样本缓存、世界修改批处理和精确成熟总数；
- 鸡、牛、猪繁殖、幼崽成长、饲料吸引和持久产物；
- 多动物同周期产物、出生和成长合并反馈；
- Agriculture、Husbandry 与 Ranch 均为显式生命周期参与者。

### 5. 统一专业 UI 与玩家体验

- 建立“星际远征”统一专业 UI 设计系统，使用语义颜色、8pt 间距、字体、圆角、控件高度和键盘焦点；
- 主菜单从居中按钮堆叠重构为世界观 Hero + 远征 Command Deck；
- 程序化星空增加星云、星座、轨道、卫星与行星，不依赖外部图片资产；
- 地图、设置和存档统一标题、工具、内容、状态和固定操作层级；
- HUD 建立生命/时间、威胁、当前物品、快捷栏、交互和教学优先级；
- 背包、合成、容器、机器和探索日志使用统一工作区与内部滚动；
- 暂停、死亡和更新提示使用共享暗幕、Modal 和主次操作；
- F3 重构为运行与运营双卡诊断中心，保持完整鼠标穿透；
- 1024×576 与 1280×720 均通过布局回归；
- 同一真实旅程固定输出主菜单、地图、设置、存档、HUD、暂停、背包、合成、探索日志、F3 共十张截图；
- 持久新手引导、上下文提示和有界消息队列；
- 第一人称手持物、挥动、使用反馈和十阶段采集裂纹；
- 木、石、铁、金、钻石工具能力层级；
- 主手和四类防具、属性、防御、耐久、修理与失败回滚；
- 玩家攻击冷却、击退、硬直、命中反馈和原子耐久事务；
- 普通僵尸和深渊重击者拥有可躲避攻击前摇；
- 多敌对同步事件按帧合并，环境扫描不超过 125 样本；
- 五敌对真实场地从 2,205 次即时修改优化为一次生产批次，场地构建由接近超时降至亚秒级。

合同见：

- [UI_DESIGN_SYSTEM.md](UI_DESIGN_SYSTEM.md)

### 6. 地图资源、生态、探矿与成长

- 五张地图独立资源、生态、危险基础值和地图印记；
- 保持旧 Seed、hash、salt、深度和概率兼容；
- 简易探矿仪与五种地图校准仪，固定采样预算且不暴露矿物坐标；
- J 键探索日志、稳定 sequence、最多 64 条发现和八个里程碑；
- 五种地图材料、原子奖励和错误地图无冷却拒绝；
- 深渊低频精英与有用途掉落。

### 7. 组合根、规模门禁与 CI

- ServiceHub 当前七个显式生命周期参与者拥有唯一 ID、依赖和逆序清理；
- 自动保存依赖全部持久玩法参与者，反向清理时优先停止检查点；
- 128 个物理掉落共享一个可暂停运行时，碰撞锚点与视觉浮动解耦；
- 物理掉落节点上限、无损堆叠、混合机器/作物/敌对/Chunk 耐久验收；
- 结构完整性使用一个事件驱动、可暂停运行时，并向角色/F3 Snapshot 暴露有界诊断；
- 最终 ServiceHub 拥有稳定 `RuntimeHealthReport` 节点，聚合层和 F3 均不反向修改领域状态；
- 保存检查点时间线拥有独立 reusable Godot 门禁，验证真实暂停保存、自动保存、F3 关联和不持久化；
- 统一专业 UI 拥有静态设计合同、双分辨率 Headless 回归和十屏真实桌面门禁；
- 六个规模专项已迁移到 reusable Godot quality gate，自动保存另有独立复用门禁；
- 严格导入、静态验证、等待式领域脚本、真实桌面和 Artifact 语义统一；
- 总 Runtime、完整桌面矩阵和 Windows Release 仍由单一权威工作流显式拥有。

## 下一阶段重点

### 1. 长期规模与恢复

- 多小时运行 soak，验证周期自动保存、连续失败退避、恢复成功、手动保存交错以及 12 条检查点历史持续淘汰；
- 多世界、大存档目录长期增长、跨会话索引重建和查询压力；
- 跨会话验证主文件修复 8、权威读取 32、sidecar 写入 16、目录暂存 64、活动 UI 行池 24、自动整理 6 轮、查询 64 字符、8 token、回收站物理 32、扫描 64、管理行池 24、检查点历史 12 和单一自动保存 pending 的收敛与失效；
- 应用重启后的目录命中、指定回收站恢复、损坏槽位治理和长周期大存档压力；
- 多敌对死亡、掉落、卸载和 Chunk 热返回压力；
- 大量玻璃板/栅栏邻接切换与结构完整性连续压力；
- Release 环境下的加载时间和退出资源报告；
- 跨世界会话验证当前世界检查点过滤、旧历史保留和显式会话重置；
- 继续基于真实截图验证超宽屏、高 DPI 和控制器焦点，而不是在没有证据时扩展新 UI 状态。

### 2. 内容扩展前置条件

新生物、远程攻击、Boss、更多机器或结构方块必须先形成可玩的闭环，并复用现有状态、预算、保存、UI 和桌面验收合同。不得通过复制 Timer、平行存档领域或全世界扫描快速堆内容。

### 3. 自动化扩展前置条件

在以下证据出现前，不引入管道、电网或跨 Chunk 物流：

- 相邻箱子自动化真实世界使用率；
- 16 台机器周期预算不足的证据；
- 玩家确实需要跨越多方块搬运；
- 路径、拓扑和 Chunk 生命周期压测；
- 存档迁移、断电/堵塞和故障恢复合同。

## 工程质量标准

所有新增系统必须满足：

1. 独立领域服务或明确纯策略；
2. 数据注册表驱动；
3. 唯一状态所有者；
4. 存档兼容与异常数据规范化；
5. 领域回归测试；
6. 真实桌面交互测试；
7. Windows Release 验收；

## Iteration 57 · 战斗反馈、强度与弹药经济（2026-08-06）

- 方向受击共享权威 Combat 结果，提供前/右/后/左、近战/深渊弹/环境、最终伤害和护甲吸收；
- 方向脉冲固定四槽，可关闭视觉效果并保留文字；相机冲击为本地有界设置；
- 休闲、标准和高危只缩放 Encounter 冷却与危险预算，不修改正式编组或存档；
- Encounter 奖励只提供燧石和火药，注册表与运行时事务拒绝成品弹药；
- 箭矢正式消耗燧石，完成奖励输入到制造输出的闭环；
- 2 射手 + 4 僵尸 + 1 重击者的 3,600 秒确定性长稳纳入永久门禁；
- 商业发布继续 **HOLD**，等待 E4-H 与真实目标硬件 7,200 秒资格。

合同见：

- [COMBAT_FEEDBACK_INTENSITY_ECONOMY.md](COMBAT_FEEDBACK_INTENSITY_ECONOMY.md)
- [COMBAT_FEEDBACK_INTENSITY_ECONOMY_TESTING.md](COMBAT_FEEDBACK_INTENSITY_ECONOMY_TESTING.md)
- [PRODUCT_ROADMAP_ITERATION_57.md](PRODUCT_ROADMAP_ITERATION_57.md)

## Iteration 58 · 长期规模与恢复资格（2026-08-06）

- `catalog.pending` 为 world 与派生 sidecar 建立跨文件崩溃边界；
- 同字节长度 stale catalog 在进程重启后强制回读权威 world、预算内重建并恢复纯命中；
- 24 小时、288 个五分钟窗口、三次失败退避突发和 6 次手动保存形成确定性资格；
- 检查点历史持续保持 12 条，累计原因计数与五世界本次进入过滤保持精确；
- 24 轮结构批处理与 5 轮满 128 掉落生命周期逐轮清零；
- 连接形状、Chunk 热返回、多世界恢复和既有长稳进入同一永久门禁；
- 3440×1440、2× 逻辑缩放和真实 Joypad 焦点路线输出 PNG/JSON 证据；
- 商业发布继续 **HOLD**，等待独立 E4-H、真实目标硬件和 7,200 秒最终包 soak。

合同见：

- [LONG_TERM_SCALE_RECOVERY.md](LONG_TERM_SCALE_RECOVERY.md)
- [LONG_TERM_SCALE_RECOVERY_TESTING.md](LONG_TERM_SCALE_RECOVERY_TESTING.md)
- [PRODUCT_ROADMAP_ITERATION_58.md](PRODUCT_ROADMAP_ITERATION_58.md)

## Iteration 59 · Release Integrity and Lifecycle

Iteration 59 closes the remaining repository-automatable integrity gaps after the 24-hour/scale qualification:

- trash restore now validates and, when possible, repairs `world.json/.tmp/.bak` before promotion;
- wrong-world and all-corrupt candidates fail with `world_payload_unrecoverable` and remain purgeable;
- Release builds produce `user://diagnostics/release-lifecycle-report.json` from the real scene/world/save/quit boundaries;
- an eight-cycle campaign combines 24 hostile deaths, unique rewards and drops, 16 Chunk hot returns, cross-Chunk pane/fence rebuilds and structural queue convergence;
- the permanent workflow and full runner retain this contract;
- the stale July feature board is reconciled with merged evidence.

The next work is external qualification, not another gameplay subsystem: independent E4-H review, minimum/recommended real hardware, strict 7,200-second target-hardware soak, and real HDD/antivirus/power-loss laboratory evidence. Commercial release remains **HOLD** until those packages exist.


## Iteration 60 · 可审计外部资格证据（2026-08-06）

- `fixture`、`hosted_reference` 与 `target_hardware` 使用明确且互斥的证据类别；
- 独立 E4-H、最低/推荐硬件、严格 7,200 秒 soak 与三类故障实验绑定同一 commit、EXE 和 PCK；
- 最低与推荐硬件复用同一最终包，不允许每台机器重新导出不同候选；
- GDScript 与 PowerShell 双验证器在组包后重新核对全部子证据，拒绝手工 JSON 重绑定；
- GitHub Hosted Runner 与 retained fixture 永远不能产生商业发布通过状态；
- 商业发布继续 **HOLD**，等待真实人员与物理机器执行证据。

合同见：

- [EXTERNAL_QUALIFICATION_EVIDENCE_KIT.md](EXTERNAL_QUALIFICATION_EVIDENCE_KIT.md)
- [PRODUCT_ROADMAP_ITERATION_60.md](PRODUCT_ROADMAP_ITERATION_60.md)

## Iteration 61 · 最终候选证据链（2026-08-06）

- 最终 EXE/PCK 在外部测试前生成稳定 `candidate_id`，绑定 commit、版本、字节长度、SHA-256 与发布合同；
- 候选身份不包含绝对路径，同一字节跨机器复制后保持同一身份；
- 最终二进制、资格包、七份摘要和八份支持报告形成可直接检查的 19 文件规范载荷；
- 支持报告覆盖两档五地图矩阵、生命周期、soak 周期/进度和三类故障恢复证据；
- 目录严格拒绝旧文件合并、缺失文件、可见/隐藏额外文件、哈希变化、reparse point 和不安全路径；
- `artifact_manifest` 与摘要 JSON 重新核对，支持报告与来源摘要重新核对，并派生稳定 `bundle_id`；
- 永久门禁覆盖摘要篡改、支持报告篡改、候选身份篡改、可见/隐藏文件注入和目录穿越；
- 商业发布继续 **HOLD**，证据链完整性不能替代真实 E4-H、硬件、soak 或故障实验。

合同见：

- [RELEASE_CANDIDATE_CHAIN_OF_CUSTODY.md](RELEASE_CANDIDATE_CHAIN_OF_CUSTODY.md)
- [PRODUCT_ROADMAP_ITERATION_61.md](PRODUCT_ROADMAP_ITERATION_61.md)


## Iteration 62 · 离线发布晋级与身份钉死（2026-08-07）

- Promotion Pin 用稳定 `pin_id` 将发布所有者选择绑定到 candidate、chain bundle、package、commit、版本和最终 EXE/PCK；
- 商业 `-RequireReleaseGate` 必须同时提供在 Promotion Bundle 之外保留的 `ExpectedPinId`，不再只依赖包内自洽；
- 已验收的 Iteration 61 19 文件证据链保持不变，由独立 Promotion Bundle 外层封装；
- Promotion Bundle 固化 `release_qualification.json`、`project.godot` 与 `export_presets.cfg`，接收端通过临时合成 contract root 离线复核，不依赖当前 checkout；
- 外层清单继续拒绝缺失/额外/隐藏文件、哈希和长度漂移、reparse point、目录穿越与 promotion identity 漂移；
- 接收端验证回执写在不可变 Promotion Bundle 之外，并记录 promotion/pin/candidate/bundle/package 身份、manifest 哈希和验证器哈希；
- 永久门禁覆盖合同快照篡改、内层链篡改、错误 Pin、可见/隐藏注入、路径穿越、promotion ID 篡改和包内回执写入；
- 商业发布继续 **HOLD**，离线晋级完整性不能替代真实 E4-H、物理硬件、7,200 秒 soak、故障实验或发行方签名体系。

合同见：

- [RELEASE_PROMOTION_OFFLINE_VALIDATION.md](RELEASE_PROMOTION_OFFLINE_VALIDATION.md)
- [PRODUCT_ROADMAP_ITERATION_62.md](PRODUCT_ROADMAP_ITERATION_62.md)


## Iteration 63 · 发行签名与最终分发门禁（2026-08-07）

- 商业候选必须先完成 Authenticode 签名与可信时间戳，再生成 candidate_id 和开始硬件/soak 资格；验收后重新签名被明确禁止；
- Windows 验签复用系统 Authenticode 信任引擎，并要求 Code Signing EKU；商业门禁同时要求可信时间戳与 Time Stamping EKU；
- 最终发行者身份不依赖 Subject 文本或 SHA-1 thumbprint，而由 Promotion Bundle 外部保留的发行证书 DER SHA-256 钉死；
- Distribution Gate 同时验证 Iteration 62 Promotion Pin、Promotion Bundle、已资格 EXE 哈希、发行证书 SHA-256 与可信时间戳；
- 已签名 EXE 必须与 candidate-chain 中已资格 EXE 的 SHA-256 完全一致，从而证明签名发生在资格验证之前；
- Distribution Receipt 写在不可变 Promotion Bundle 之外，并记录发行证书、时间戳证书和验证器哈希；
- Windows CI 使用 hosted runner 上真实可信且已时间戳的 Authenticode 二进制验证系统信任、证书 SHA-256 Pin 与时间戳 EKU；该 fixture 不是 Star World 且 Promotion 仍为 reference-only，不能关闭商业门禁；
- 商业发布继续 **HOLD**，真实发行私钥、CA 证书、可信 TSA、真实外部资格和最终发行操作仍由外部安全环境产生。

合同见：

- [RELEASE_PUBLISHER_SIGNING_GATE.md](RELEASE_PUBLISHER_SIGNING_GATE.md)
- [PRODUCT_ROADMAP_ITERATION_63.md](PRODUCT_ROADMAP_ITERATION_63.md)


## Iteration 64 · 发行者钉死自动更新（2026-08-07）

- 自动更新不再把同源 GitHub Release ZIP、`.sha256` 与未签名 Manifest 视为独立发行身份；
- `update-manifest.json` 升级到 schema/protocol 2，并由 detached CMS `update-manifest.p7s` 绑定 EXE、PCK 与全部载荷哈希；
- staged EXE 同时验证 Windows Authenticode、Code Signing EKU、当前安装 Publisher Certificate SHA-256 Pin、可信 TSA 与 Time Stamping EKU；
- Manifest signer 与 EXE publisher 使用当前安装版本携带的独立证书 SHA-256 Pin，目标包不能决定本次认证使用的信任根；
- 每个信任域最多四个 Pin，证书轮换必须先部署 old+new overlap，再移除旧 Pin；
- helper 在任何安装目录 `Move-Item` 之前完成逐文件哈希、CMS 与 Authenticode 认证，原有 ACK/rollback 事务保持不变；
- Hosted CI 只生成 `REFERENCE-ONLY` 更新资产，不再直接创建未签名商业 GitHub Release；真实上传由外部签名工作站工具在验证 EXE/TSA、CMS 与双 Pin 后执行；
- 仓库默认真实 Pin 为空并 fail-close，首次生产启用必须通过已信任/手动渠道部署带真实 Pin 的基线版本；
- 商业发布继续 **HOLD**，真实发行/Manifest 私钥、证书 Pin 与 Iterations 60-63 的真实外部资格仍由外部安全环境产生。

合同见：

- [GITHUB_RELEASE_AUTO_UPDATE.md](GITHUB_RELEASE_AUTO_UPDATE.md)
- [PUBLISHER_PINNED_AUTO_UPDATE.md](PUBLISHER_PINNED_AUTO_UPDATE.md)
- [PRODUCT_ROADMAP_ITERATION_64.md](PRODUCT_ROADMAP_ITERATION_64.md)
