# 星的世界 · Product & Architecture Roadmap

> 本文件是仓库当前状态的顶层权威视图。各次迭代的详细设计、验收与历史证据保留在对应的 `PRODUCT_ROADMAP_ITERATION_*.md` 中，避免顶层路线图再次因复制历史状态而漂移。

## 产品定位

《星的世界》是长期可扩展的单人沙盒生存建造游戏基础，而不是只展示体素地形的 Demo。

核心原则：

- 玩家体验优先；
- 系统模块化、数据驱动；
- 每个玩法拥有明确状态所有者；
- 功能先形成可玩的闭环，再扩展内容数量；
- 重要功能必须可测试、可保存、可恢复；
- 旧世界、方块 numeric ID、Seed 与既有视觉基线必须有兼容策略；
- 高数量对象必须共享调度并具有硬预算；
- 真实桌面与最终 Windows Release 是仓库功能合入 `master` 的必要证据；
- CI、Hosted Runner 或 retained fixture 不得伪造真实人员、真实硬件、真实签名私钥或商业资格证据。

## 当前交付状态

- v1.3.0 原始仓库功能清单：**11/11 complete + passed**；
- Repository QA：**passed**；
- Repository acceptance：**accepted**；
- Repository delivery：**delivered**；
- Repository P0/P1 blockers：**0**；
- Iteration 65：Task Workspace Governance Closure 已完成，当前状态由 canonical task contract 统一；
- Iteration 66：Five-Map Weather & Climate 已进入最终仓库门禁，作为 v1.3.0 之后的玩法扩展，不重开已完成的 11 个原始功能点；
- Commercial release：继续 **HOLD**，仅等待真实外部资格、真实目标硬件、严格 soak、故障实验、发行签名/证书 Pin 与 bootstrap 等外部控制，不允许用仓库 CI 替代。

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
├─ Climate Domain
│  ├─ Exact Five-Map Weather Registry
│  ├─ Deterministic Seed + Transition Selection
│  ├─ Persistent Weather State / Duration
│  ├─ Bounded Survival Exposure
│  └─ DayNight-owned Sky / Light / Fog / Cloud Composition
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
│  ├─ Protected Trash / Bounded Slot Manager / Original-ID Restore
│  ├─ Domain Migration / Settings Whitelist
│  ├─ Release Candidate Chain / Offline Promotion
│  └─ Publisher-pinned Signed Auto-update
│
└─ Experience & Composition Layer
   ├─ Professional Celestial UI Design System / UI Kit
   ├─ Hero Menu / Responsive Management Workspaces
   ├─ HUD / Weather Status / Feedback / Audio
   ├─ First-person Viewmodel
   ├─ Input Contexts / Guidance
   ├─ Virtualized & Indexed Save Browser / Query / Sort
   ├─ Runtime Diagnostics / Unified Runtime & Save Health
   ├─ F3 Save Source / Checkpoint Timeline
   └─ Eight Feature Lifecycle Participants
```

## 八个生产 FeatureLifecycle 参与者

生产组合根当前按以下顺序注册，并由 Coordinator 逆序清理：

1. `agriculture_runtime`
2. `ranch_runtime`
3. `water_lava_runtime`
4. `exploration_runtime`
5. `exploration_reward_runtime`
6. `exploration_journal_runtime`
7. `weather_runtime`
8. `autosave_runtime`

关键约束：

- Autosave 最后注册，因此退出世界时最先停止，不会在下游领域清理过程中再创建检查点；
- Weather 紧邻 Autosave 之前注册，其状态通过现有 `world.json` 聚合事务保存；
- Weather 不拥有第二套时钟、环境或存档；`DayNightService` 仍是 sun/sky/cloud/fog 的 single state owner；
- Weather 清理后不得留下伪造的 `clear/star_continent` runtime snapshot；
- 无 Weather profile 时必须保持 Iteration 65 的基础天空兼容行为，包括 `0.8` 云层 opacity 基线。

## 已完成能力面

### 世界、建造与结构

- 五地图确定性地形、资源分布和地图身份；
- 渐进 Chunk streaming、最近 Chunk 快照缓存和有界世界修改批次；
- 台阶、四向楼梯、玻璃板、栅栏、双格门、贴墙梯子；
- 结构完整性共享运行时、跨 Chunk 支撑、自愈与满背包掉落回退。

### 生存、战斗、生态与成长

- 生存饥饿/饱和、装备属性、耐久与修理；
- 攻击冷却、击退、硬直、方向受击、可躲避敌对前摇；
- 五地图生态、危险预算、精英生态与掉落经济；
- 农业、畜牧、牧场生产链与有界离线推进；
- 探矿、探索日志、里程碑与原子奖励。

### 机器与自动化

- Furnace / Stonecutter / Machine Capability 合同；
- Indexed MachineRuntimeScheduler；
- 相邻箱子有界供料、燃料和收货；
- 不引入每机器 Timer、平行存档或无界全世界扫描。

### 保存、恢复、目录与回收站

- 原子 `world.json`、`.tmp/.bak` 恢复和严格迁移；[SELF_HEALING_SAVE_RECOVERY.md](SELF_HEALING_SAVE_RECOVERY.md) 规定语义校验、恢复暂存/有效备份，以及恢复成功后原子重建主文件并保留 `.bak`；
- 多世界目录扫描中的主文件修复每次最多 8 个，世界始终可见并通过确定性后续扫描渐进收敛；显式完整加载不受目录修复预算限制；
- 轻量世界目录 `catalog.json` 是 `world.json` 的派生、自愈、严格白名单索引；目录 sidecar 重建使用与主文件修复独立的写入预算，每次最多 16 个；完整存档读取使用另一独立预算，每次最多 32 个；写入预算耗尽时可使用最多 64 条的瞬时目录暂存，目录暂存只保存白名单 metadata、不进入存档，并通过后续扫描渐进收敛；
- 存档浏览器采用固定 24 行可复用行池和分页；自动整理每帧只执行一次有界目录扫描，最多 6 次自动收敛，不创建 Timer/Thread；索引搜索覆盖名称、ID、地图和 Seed，排序覆盖最近更新、名称和存档大小，页面切换和查询只使用内存索引；
- pause-aware Autosave、15/60/300 秒失败退避和 12 条 checkpoint timeline；
- 回收站最多 32 个物理目录，容量满时拒绝新删除而不是自动清理；玩家删除使用二次确认，撤销恢复保留原 world ID；固定 24 行的回收站管理页复用行池并分页展示，指定恢复不会误消费最新条目，损坏 Manifest 条目只允许确认永久清理；
- 统一运行与保存健康报告聚合固定来源、运行分量与运营分量，并通过 F3 暴露主要瓶颈、保存/目录恢复证据；RuntimeHealthReport 不进入存档。

### UI、桌面与 Release

- 统一 Celestial UI Design System；
- Hero 主菜单、地图/设置/存档工作区、HUD、背包/合成/机器/探索界面；
- 双分辨率、超宽屏、高 DPI、控制器焦点与真实旅程证据；
- Windows Release 真实导出/启动/截图/退出资源检查；
- Release Candidate chain of custody、offline promotion、publisher signing gate 与 publisher-pinned signed auto-update 合同。

## Iteration 66 · Five-Map Weather & Climate

Iteration 66 的仓库任务清单：

1. 严格注册且仅注册五张正式地图气候；
2. 每张地图保留 clear baseline，并拥有地图标志性天气；
3. `(map_id, world_seed, transition_index)` 决定性选择状态与持续时间，不使用全局 mutable RNG；
4. 当前天气、剩余时间和 transition identity 进入现有 `world.json`；
5. 旧世界缺失 weather key 时安全 normalize；
6. 危险天气只通过 `SurvivalService.add_exhaustion()` 施加有界环境压力；
7. `DayNightService` 保持环境 single owner；
8. WeatherStatusBadge 与现有 GameUI feedback 路径展示状态；
9. Weather 作为第八个 FeatureLifecycle participant 前置于 Autosave；
10. 生命周期回归从 7 participant 升级为 8 participant；
11. 具备 deterministic / persistence / survival / environment headless regression；
12. 具备真实桌面天气渲染与 HUD screenshot evidence；
13. Weather 门禁必须组合执行 Iteration 65 + 完整 `tests/run_all.ps1`；
14. 完整仓库回归通过后必须重新导出并运行 Windows Release smoke；
15. fresh checkout 的完整回归必须自行执行 strict Godot import，不能依赖另一个 job 的隔离工作区；
16. 保持无天气旧视觉基线，防止天气抽象层改变旧世界默认云层表现；
17. PR 最终 head 必须无 unresolved blocking review thread，所有当前 head CI 门禁通过后才允许合入 `master`。

详细合同：

- [WEATHER_CLIMATE_SYSTEM.md](WEATHER_CLIMATE_SYSTEM.md)
- [PRODUCT_ROADMAP_ITERATION_66.md](PRODUCT_ROADMAP_ITERATION_66.md)
- [ARCHITECTURE_AUDIT_2026-08-07_ITERATION_66.md](ARCHITECTURE_AUDIT_2026-08-07_ITERATION_66.md)

## 当前下一阶段

### A. 仓库内产品迭代

长期规模与恢复已经由 Iteration 58 及后续永久门禁覆盖；当前 v1.3.0 原始仓库任务没有未完成 P0/P1。后续新增玩法必须继续遵守“完整闭环 + 保存/恢复 + 有界预算 + Headless + 真实桌面 + Windows Release”的合同。天气之后的 lightning damage、wind physics、shelter detection、precipitation collision、Boss、更多机器或跨 Chunk 自动化都不是默认必做项；只有出现明确玩家价值与性能证据后才立项，避免用系统数量替代玩法质量。

### B. 商业发布外部资格

商业发布仍需在仓库之外真实完成并绑定同一候选身份的资格/安全证据，包括：

- 独立 E4-H 复核；
- 最低/推荐真实目标硬件；
- 严格 7,200 秒最终候选 soak；
- 真实 HDD / antivirus / power-loss 等故障实验；
- 真实发行证书、可信 TSA、publisher certificate pin 与 manifest signer pin；
- 最终离线 promotion / distribution 操作与外部回执。

这些项目在真实证据产生前必须保持 **HOLD**，仓库自动化只能验证证据结构和不可篡改链，不能替代事实本身。

## 工程质量标准

所有新增系统必须满足：

1. 独立领域服务或明确纯策略；
2. 数据注册表驱动；
3. 唯一状态所有者；
4. 存档兼容与异常数据规范化；
5. 工作量与对象数量具有硬预算；
6. 领域回归测试；
7. fresh-checkout strict import；
8. 真实桌面交互/视觉测试；
9. 完整仓库回归；
10. Windows Release 验收；
11. 文档、任务清单与生产实现保持同一事实源；
12. 真实外部证据永不由 CI 伪造。

## 最近迭代索引

- [Iteration 57 · Combat Feedback / Intensity / Economy](PRODUCT_ROADMAP_ITERATION_57.md)
- [Iteration 58 · Long-term Scale & Recovery](PRODUCT_ROADMAP_ITERATION_58.md)
- Iteration 59 · Release Integrity & Lifecycle（详见对应 release integrity 文档与永久门禁）
- [Iteration 60 · External Qualification Evidence Kit](PRODUCT_ROADMAP_ITERATION_60.md)
- [Iteration 61 · Release Candidate Chain of Custody](PRODUCT_ROADMAP_ITERATION_61.md)
- [Iteration 62 · Offline Release Promotion](PRODUCT_ROADMAP_ITERATION_62.md)
- [Iteration 63 · Publisher Signing Gate](PRODUCT_ROADMAP_ITERATION_63.md)
- [Iteration 64 · Publisher-pinned Auto-update](PRODUCT_ROADMAP_ITERATION_64.md)
- [Iteration 65 · Task Workspace Governance Closure](PRODUCT_ROADMAP_ITERATION_65.md)
- [Iteration 66 · Five-Map Weather & Climate](PRODUCT_ROADMAP_ITERATION_66.md)
