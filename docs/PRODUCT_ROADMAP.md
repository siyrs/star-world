# 星的世界 · Product & Architecture Roadmap

## 产品定位

《星的世界》是长期可扩展的单人沙盒生存建造游戏基础，而不是只展示体素地形的 Demo。

核心原则：

- 玩家体验优先；
- 系统模块化、数据驱动；
- 每个玩法拥有明确状态所有者；
- 功能先形成可玩的闭环，再扩展内容数量；
- 所有重要功能必须可测试、可保存、可恢复；
- 旧世界、方块 numeric ID 和 Seed 结果必须有明确兼容策略；
- 真实桌面与最终 Windows Release 是合入主分支的必要证据。

## 当前领域结构

```text
Game Runtime
├─ World Domain
│  ├─ Chunk Streaming
│  ├─ Terrain Generation
│  ├─ Resource Distribution
│  ├─ Shared Map Identity
│  └─ Directional / Partial Block Geometry
│
├─ Player Domain
│  ├─ Movement / Survival
│  ├─ Inventory Transactions
│  ├─ Equipment / Attributes
│  └─ Combat Cadence
│
├─ Creature & Ecology Domain
│  ├─ Creature Factory / Catalog Integrity
│  ├─ Conditional Ecology Profiles
│  ├─ Population / Per-species Budgets
│  ├─ Weighted Live Danger
│  ├─ Hostile Attack Profiles
│  ├─ Dodgeable Windup State Machine
│  └─ Batched Threat Invalidation
│
├─ Exploration Domain
│  ├─ Bounded / Calibrated Prospecting
│  ├─ Persistent Discovery Records
│  ├─ Exploration Journal
│  ├─ Profile-aware Milestones
│  ├─ Atomic Milestone Rewards
│  └─ Cached / Batched Danger Assessment
│
├─ Agriculture & Ranch Domain
│  ├─ Crop / Soil / Fertilizer
│  ├─ Husbandry / Breeding
│  ├─ Feed Attraction
│  ├─ Persistent Products
│  ├─ Batched Ranch Feedback
│  └─ Batched Husbandry Lifecycle Feedback
│
├─ Harvest / Interaction / Machine Domain
│  ├─ Tool Capability / Hardness
│  ├─ Placement Preview / Partial Shapes
│  ├─ Container
│  ├─ Furnace
│  └─ Repair
│
├─ Persistence Domain
│  ├─ Atomic Save Transaction
│  ├─ Migration / Whitelist
│  └─ Recovery
│
└─ Experience & Composition Layer
   ├─ UI / Feedback / Audio
   ├─ First-person Viewmodel
   ├─ Guidance / Input Contexts
   ├─ Runtime Diagnostics
   └─ Feature Lifecycle Participants
```

## 已完成里程碑

### 1. 运行与发行可靠性

- 真实 WASD、鼠标、按钮和输入上下文；
- 世界启动保护、非空白画面和安全出生；
- 渐进区块加载、卸载和自适应预算；
- F3 诊断与多轮生命周期 soak；
- 原子 JSON、临时文件和备份恢复；
- Windows Release 实际导出、启动、截图、报告和资源退出检查。

### 2. 建造、交互与机器

- 工作台世界授权；
- 位置型箱子和内容保护；
- 熔炉持续进度、燃料、离线恢复和存档；
- 修理台与耐久恢复事务；
- 精确目标和统一放置预览；
- 台阶、楼梯、耕地、床和玻璃板非整块几何；
- 四方向楼梯与真实旋转碰撞；
- 方块、物品、配方、视觉、采集和保存目录门禁。

### 3. 玩家体验与原创视觉

- 持久新手引导和上下文操作提示；
- 有界消息队列；
- 第一人称手持物、挥动和使用反馈；
- 十阶段世界采集裂纹；
- 原创程序化 16×16 像素纹理；
- Design Token 与 1024×576 布局门禁；
- 纯展示层鼠标透传、不修改业务状态。

### 4. 工具、装备与玩家战斗

- 镐、斧、铲、锄和剑；
- 木、石、铁、金、钻石能力层级；
- 方块硬度、工具门槛、速度和掉落资格；
- 按住采集和背包满保护；
- 主手与四类防具槽；
- 属性聚合、防御减伤和速度修正；
- 玩家攻击冷却、击退、硬直、命中反馈和耐久事务；
- 修理失败回滚和 metadata 保留。

### 5. 农业、畜牧与牧场生产链

- 干燥/湿润耕地、水源和水桶浇灌；
- 小麦、胡萝卜、马铃薯多阶段成长；
- 有界离线成长、成熟收获和自动补种；
- 堆肥与成熟保护；
- 鸡、牛、猪繁殖、幼崽成长和持久管理；
- 饲料吸引和持久鸡蛋；
- 鸡蛋到熟鸡蛋的食物加工链；
- 高数量对象共享调度；
- 多动物同周期产物合并为一条摘要和一次音效；
- 动物开始跟随和停止跟随具有有界反馈；
- 多对动物同帧繁殖合并为一条出生摘要；
- 多只幼崽同帧成年合并为一条成长摘要；
- 出生/成长待表现事件硬上限为 64；
- 畜牧存档使用独立字段白名单迁移。

### 6. 地图资源、生态与危险

- 五张地图独立资源档案；
- 矿物深度与累计阈值数据驱动；
- 保持旧 Seed、hash、salt、深度和概率兼容；
- 地图选择显示资源特点；
- 五地图动物权重、被动/敌对上限和生成节奏；
- 地图、深度、昼夜、敌对、岩浆和洞穴组成危险分；
- HUD 风险反馈与 125 样本硬预算；
- 普通敌对数量和精英危险权重分离；
- 危险解除后提供玩家反馈；
- 昼夜、生态和威胁事件按帧合并；
- 同一玩家方块内事件评估复用环境样本；
- 原始事件、实际评估、避免评估和缓存复用进入诊断；
- 多敌对前摇聚合显示数量、精英数量和最快命中时间；
- 生物死亡和离树即时使危险状态失效；
- 生物清场不会删除死亡后生成的物理掉落。

相关合同：

- [RESOURCE_DISTRIBUTION.md](RESOURCE_DISTRIBUTION.md)
- [CREATURE_ECOLOGY_DANGER.md](CREATURE_ECOLOGY_DANGER.md)
- [HOSTILE_ATTACK_WINDUP.md](HOSTILE_ATTACK_WINDUP.md)
- [ABYSS_ELITE_ECOLOGY.md](ABYSS_ELITE_ECOLOGY.md)
- [MULTI_HOSTILE_DANGER_BATCHING.md](MULTI_HOSTILE_DANGER_BATCHING.md)

### 7. 探矿、日志与地图成长

- 可制作、可重复使用的简易探矿仪；
- 固定半径、步长和样本硬预算；
- 深度、密度和主矿物趋势；
- 不返回矿物方块坐标；
- 最多 64 条持久发现；
- J 键日志、稳定 sequence 和世界内时间；
- 八个探索里程碑；
- profile-aware 地图印记；
- 五种不占方块 ID 的地图材料；
- 五种工作台校准探矿仪；
- 生产资源概率下的目标可达性校验；
- 错误地图明确拒绝且不进入冷却；
- 领取、制作、真实扫描、保存和完整重载闭环。

相关合同：

- [PROSPECTING_SYSTEM.md](PROSPECTING_SYSTEM.md)
- [EXPLORATION_JOURNAL.md](EXPLORATION_JOURNAL.md)
- [MAP_SIGNATURE_PROSPECTING.md](MAP_SIGNATURE_PROSPECTING.md)

### 8. 原子探索奖励与背包事务

- 八个里程碑的独立奖励状态；
- `locked / claimable / claimed`；
- 原子多物品背包事务；
- 背包满时保持待领取；
- 重试和重复领取幂等；
- 合成服务复用同一事务入口；
- 新世界显式探索与奖励 Schema。

见 [EXPLORATION_MILESTONE_REWARDS.md](EXPLORATION_MILESTONE_REWARDS.md)。

### 9. 可躲避敌对攻击与深渊精英

- 独立 `hostile_attacks.json`；
- 数据驱动前摇、命中范围、取消范围和冷却；
- 红色、发光、无碰撞预警圈；
- 后退躲避和击退/硬直打断；
- 前摇结束时重新验证实际距离；
- 普通僵尸保持 0.8 秒前摇和五秒节奏；
- 深渊重击者仅夜间或 Y19 以下低概率出现；
- 精英最多一只、1:9 权重、1.35 秒重击和七秒恢复；
- 固定深渊余烬掉落进入现有校准探矿路线；
- 真实躲避、承伤、打断、击杀、拾取、保存和重载验收。

相关合同：

- [HOSTILE_ATTACK_WINDUP.md](HOSTILE_ATTACK_WINDUP.md)
- [ABYSS_ELITE_ECOLOGY.md](ABYSS_ELITE_ECOLOGY.md)

### 10. ServiceHub 生命周期组合化 · 四个参与者

生产入口和继承路径保持：

```text
Gameplay
→ Tool
→ Character
→ Repair
→ Husbandry
→ Ranch
→ Exploration
```

当前参与者：

```text
ServiceHubFeatureCoordinator
├─ husbandry_runtime
│  ├─ AnimalHusbandryService
│  └─ HusbandryInteractionAdapter
├─ ranch_runtime
│  ├─ AnimalAttractionService
│  └─ AnimalProductService
├─ exploration_runtime
│  ├─ ExplorationDangerService
│  └─ ProspectingService
└─ exploration_journal_rewards
   ├─ ExplorationJournalService
   └─ ExplorationMilestoneRewardService
```

显式依赖：

```text
ranch_runtime → husbandry_runtime
exploration_journal_rewards → exploration_runtime
```

已完成：

- 唯一参与者 ID；
- 显式依赖；
- 缺失依赖与自依赖拒绝；
- 按注册顺序规范化世界状态；
- 正序 begin/attach/activate/save；
- 逆序 clear/shutdown；
- 48 条有界阶段诊断；
- 共享保存 Payload；
- 共享角色 Snapshot；
- 八个公共字段和节点路径兼容；
- 探矿和实体交互旧玩家端口显式解绑；
- 受管动物长期死亡回调显式解除；
- 返回菜单、失败启动和退出清理；
- 真实输入、保存、菜单、重载和发行验收。

相关合同：

- [SERVICE_HUB_FEATURE_LIFECYCLE.md](SERVICE_HUB_FEATURE_LIFECYCLE.md)
- [HUSBANDRY_RUNTIME_LIFECYCLE.md](HUSBANDRY_RUNTIME_LIFECYCLE.md)
- [RANCH_RUNTIME_LIFECYCLE.md](RANCH_RUNTIME_LIFECYCLE.md)
- [EXPLORATION_RUNTIME_LIFECYCLE.md](EXPLORATION_RUNTIME_LIFECYCLE.md)

### 11. 多敌对危险事件合并与全局攻击提示

已完成：

```text
phase_changed / ecology_changed / threat_changed
→ 同帧原因集合和原始次数
→ 每批最多 64 个事件
→ 每帧最多一次危险评估
→ 同方块环境缓存
→ 125 样本物理扫描硬上限
```

生产验收覆盖：

- 五只敌对同帧生成；
- 五只敌对同帧进入前摇；
- 五个实体红色预警圈；
- 一条全局“来袭攻击 ×5 · 最快命中时间”提示；
- 五只敌对同步取消；
- 同帧昼夜变化、三只死亡、两只卸载和生态变化；
- 三个真实物理掉落不被清场删除；
- 物理拾取、保存和完整重载。

见 [MULTI_HOSTILE_DANGER_BATCHING.md](MULTI_HOSTILE_DANGER_BATCHING.md)。

## 下一阶段重点

### 1. 多敌对焦点优先级与长期压力

全局 HUD 已能显示攻击数量和最快命中时间。下一步优化中心上下文提示和长期运行：

```text
当前瞄准的蓄力精英
→ 当前瞄准的普通蓄力敌人
→ 最近即将命中的敌人摘要
→ 普通目标信息
```

约束：

- 不自动移动准星；
- 不自动选择攻击目标；
- 不暴露敌人坐标；
- 不为每个敌人创建新的全局 UI；
- 64 节点威胁查询和 125 环境样本上限保持不变。

压力验收：

- 多轮五敌对生成、前摇、取消、死亡和重建；
- 多红圈重叠截图；
- 多死亡和多掉落拾取；
- Event/Assessment 比率报告；
- 长时间危险缓存命中率；
- ObjectDB、节点和信号退出检查。

### 2. 下一张地图精英

在多敌对预算稳定后，第二只精英仍必须满足：

```text
地图限定
→ 明确条件与独立上限
→ 可观察攻击差异
→ 真实躲避或反制
→ 有用途掉落
```

建议优先极寒冰原或荒漠遗迹。不得只提高生命、速度和伤害，也不立即增加 Boss、复杂状态效果或大型行为树。

### 3. Machine Base 与自动化接口

从成熟 FurnaceService 提取小型能力：

- 输入/输出；
- 进度与阻塞；
- 燃料或能源接口；
- 暂停与有界离线推进；
- 位置型序列化；
- UI 只消费 Snapshot。

不得把熔炉服务扩大为万能 MachineManager。

### 4. 建筑交互与连接形状

- 门开关与方向状态；
- 栅栏自动连接；
- 梯子攀爬；
- 玻璃板自动连接；
- 更多方向化方块；
- 建筑结构批量和旧世界兼容回归。

视觉、碰撞、预览和提交必须使用同一形状合同。

### 5. 质量平台与规模压测

- 提取 GitHub Actions reusable workflow；
- 24 只受管动物长期模拟；
- 同步繁殖、成长和产物压力用例；
- 大型农场和牧场压测；
- 大量方向化建筑区块重建压测；
- 探索日志、奖励和物品规模的存档体积报告；
- 90+ 物品与配方 UI 滚动性能；
- 多小时运行 soak；
- 数据注册表统一诊断报告。

## 产品优先级

```text
P0  输入、保存、世界可见性、发行稳定性          持续守护
P1  多敌对焦点优先级与长期压力                   当前玩家/性能里程碑
P1  下一张地图精英                              下一内容里程碑
P2  Machine Base 与自动化接口                   复用成熟机器能力
P2  建筑交互与连接形状                          提升建造表达
P3  CI 组合化、规模压测和更多内容                在合同稳定后推进
```

## 工程质量标准

所有新增系统必须满足：

1. 独立领域服务、纯策略或生命周期参与者；
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
12. 高成本工作具有预算、上限和诊断；
13. 公共合同保留兼容入口或提供迁移；
14. 方块 numeric ID 只追加；
15. 数据驱动目标必须验证生产可达性；
16. 多物品业务必须使用原子背包事务；
17. Feature clear/shutdown 使用逆依赖顺序；
18. 运行提示必须去重且有界；
19. 同步批量领域事件不得线性放大 Toast 和音效；
20. 世界状态迁移按参与者顺序执行并进入诊断；
21. 玩家能力端口必须在菜单、失败和 Shutdown 时显式解绑；
22. 对外部实体建立的长期信号必须在领域清理前主动断开；
23. 同帧高成本失效事件必须先合并，再执行实际评估；
24. 原始事件数、实际评估数、合并数和丢弃数必须分别诊断；
25. 环境缓存只能在明确不变的空间键内复用，并由周期评估重新验证；
26. 物理扫描的单次预算和同帧执行次数必须同时受限；
27. 敌对攻击必须有可观察前摇、稳定取消原因和真实躲避路径；
28. 纯视觉攻击提示不得拥有碰撞或改变伤害判定；
29. 全局攻击提示不得泄漏攻击者坐标或自动选择目标；
30. 生物攻击冷却不得与玩家伤害保护形成静默丢弃；
31. 新物种必须通过脚本/数据目录双向校验；
32. 精英必须有低频条件、独立上限、可读权衡和有用途掉落；
33. 敌对数量与威胁权重不得混为同一指标；
34. 生物清场不得删除已经生成的物理掉落；
35. 新分支必须基于最新 `master`，不得回退并行改动。

每个里程碑必须具备：

```text
用户目标
→ 可玩闭环
→ 领域边界
→ 数据合同
→ 生命周期合同
→ 存档合同
→ 失败反馈
→ Runtime 回归
→ 真实桌面验收
→ Windows Release 验收
```
