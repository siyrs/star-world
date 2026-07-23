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
│  ├─ Lightweight Self-healing World Catalog
│  ├─ Domain Migration / Whitelist
│  └─ Resumable GitHub Release Auto-update
│
└─ Experience & Composition Layer
   ├─ UI / Feedback / Audio
   ├─ First-person Viewmodel
   ├─ Input Contexts / Guidance
   ├─ Runtime Diagnostics
   └─ Feature Lifecycle Participants
```

## 已完成里程碑

### 1. 运行、保存与发行可靠性

- 真实 WASD、鼠标、按钮和输入上下文；
- 世界启动保护、非空白画面和安全出生；
- 渐进 Chunk 加载/卸载、自适应预算和最近 64 个卸载 Chunk 快照；
- F3 诊断、多轮生命周期 soak 和资源泄漏门禁；
- 原子 JSON、临时文件、备份恢复和严格存档迁移；
- 轻量世界目录：`world.json` 保持唯一权威，`catalog.json` 缺失或损坏时按需自愈；
- 主菜单显示存档大小和目录耗时，稳态不再读取所有世界完整 payload；
- 生产世界不再保存或构造无用的 `loaded_chunks`；
- Windows Release 实际导出、启动、截图、报告和退出资源检查；
- Range / If-Range / ETag 跨重启续传、双重 SHA-256 和失败回滚；
- Tag 驱动的 Windows GitHub Release 固定资产发布。

合同见：

- [WORLD_CATALOG.md](WORLD_CATALOG.md)
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

### 5. 玩家体验、工具、装备与战斗

- 持久新手引导、上下文提示和有界消息队列；
- 第一人称手持物、挥动、使用反馈和十阶段采集裂纹；
- 木、石、铁、金、钻石工具能力层级；
- 主手和四类防具、属性、防御、耐久、修理与失败回滚；
- 玩家攻击冷却、击退、硬直、命中反馈和原子耐久事务；
- 普通僵尸和深渊重击者拥有可躲避攻击前摇；
- 多敌对同步事件按帧合并，环境扫描不超过 125 样本；
- 五敌对真实场地从 2,205 次即时修改优化为一次生产批次，场地构建由接近超时降至亚秒级。

### 6. 地图资源、生态、探矿与成长

- 五张地图独立资源、生态、危险基础值和地图印记；
- 保持旧 Seed、hash、salt、深度和概率兼容；
- 简易探矿仪与五种地图校准仪，固定采样预算且不暴露矿物坐标；
- J 键探索日志、稳定 sequence、最多 64 条发现和八个里程碑；
- 五种地图材料、原子奖励和错误地图无冷却拒绝；
- 深渊低频精英与有用途掉落。

### 7. 组合根、规模门禁与 CI

- ServiceHub 当前六个显式生命周期参与者拥有唯一 ID、依赖和逆序清理；
- 128 个物理掉落共享一个可暂停运行时，碰撞锚点与视觉浮动解耦；
- 物理掉落节点上限、无损堆叠、混合机器/作物/敌对/Chunk 耐久验收；
- 结构完整性使用一个事件驱动、可暂停运行时，并向角色/F3 Snapshot 暴露有界诊断；
- 六个规模专项已迁移到 reusable Godot quality gate；
- 严格导入、静态验证、等待式领域脚本、真实桌面和 Artifact 语义统一；
- 总 Runtime、完整桌面矩阵和 Windows Release 仍由单一权威工作流显式拥有。

## 下一阶段重点

### 1. 统一运行与保存健康报告

把已有机器、农业、畜牧、牧场、危险、Chunk、掉落、轻量世界目录和结构完整性诊断聚合到 F3：

```text
共享预算使用率
队列 / 活跃对象 / 批次峰值
最近保存字节与耗时
目录命中率 / 回退 / 自愈
结构候选 / 清理 / 物品回退
当前健康等级与最主要瓶颈
```

聚合层只读取有界 Snapshot，不复制完整领域 Dictionary；显示层不得反向修改领域状态。

### 2. 长期规模与恢复

- 多小时运行 soak 与周期性真实保存；
- 多世界、大存档目录长期增长；
- 存档损坏、备份恢复和目录重建组合测试；
- 多敌对死亡、掉落、卸载和 Chunk 热返回压力；
- 大量玻璃板/栅栏邻接切换与结构完整性连续压力；
- Release 环境下的加载时间和退出资源报告。

### 3. 内容扩展前置条件

新生物、远程攻击、Boss、更多机器或结构方块必须先形成可玩的闭环，并复用现有状态、预算、保存和桌面验收合同。不得通过复制 Timer、平行存档领域或全世界扫描快速堆内容。

### 4. 自动化扩展前置条件

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
8. 日志无脚本错误、解析错误和资源泄漏；
9. UI 不直接修改领域 Dictionary；
10. Player 不承担存档、面板或复杂规则；
11. 高数量对象共享调度；
12. 高成本工作有预算、上限和诊断；
13. 公共合同保留兼容入口或提供明确迁移；
14. 方块 numeric ID 只追加；
15. 新分支基于最新 `master`，不得回退并行改动；
16. 已合并能力必须及时移出“下一阶段”，避免路线图与主分支事实漂移。
