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
│  ├─ Creature Catalog Integrity
│  ├─ Conditional Ecology Profiles
│  ├─ Population / Per-species Budgets
│  ├─ Weighted Live Danger
│  ├─ Hostile Attack Profiles
│  └─ Dodgeable Windup State Machine
│
├─ Exploration Domain
│  ├─ Bounded / Calibrated Prospecting
│  ├─ Persistent Discovery Records
│  ├─ Exploration Journal
│  ├─ Profile-aware Milestones
│  └─ Atomic Milestone Rewards
│
├─ Agriculture & Ranch Domain
│  ├─ Crop / Soil / Fertilizer
│  ├─ Husbandry / Breeding
│  ├─ Feed Attraction
│  ├─ Persistent Products
│  └─ Batched Lifecycle Feedback
│
├─ Machine Domain
│  ├─ MachineRuntimeScheduler
│  ├─ Machine Progress / State Policies
│  ├─ Furnace Domain Adapter
│  └─ Batched Completion Feedback
│
├─ Persistence Domain
│  ├─ Atomic Save Transaction
│  ├─ Domain Migration / Whitelist
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

### 1. 运行、保存与发行可靠性

- 真实 WASD、鼠标、按钮和输入上下文；
- 世界启动保护、非空白画面和安全出生；
- 渐进区块加载、卸载和自适应预算；
- F3 诊断与多轮生命周期 soak；
- 原子 JSON、临时文件和备份恢复；
- Windows Release 实际导出、启动、截图、报告和资源退出检查。

### 2. 建造、交互与机器基础

- 工作台世界授权；
- 位置型箱子和内容保护；
- 精确目标和统一放置预览；
- 台阶、楼梯、耕地、床和玻璃板非整块几何；
- 四方向楼梯与真实旋转碰撞；
- 修理台与耐久恢复事务；
- Furnace 原料、燃料、产出、持续进度、离线恢复和拆除保护；
- Machine Base 共享调度、严格状态迁移、队列/ETA、批量完成反馈和生命周期；
- 方块、物品、配方、视觉、采集和保存目录门禁。

Machine Base 合同见 [MACHINE_BASE.md](MACHINE_BASE.md)。

### 3. 玩家体验与原创视觉

- 持久新手引导和上下文操作提示；
- 有界消息队列；
- 第一人称手持物、挥动和使用反馈；
- 十阶段世界采集裂纹；
- 原创程序化 16×16 像素纹理；
- Design Token 与 1024×576 布局门禁；
- 纯展示层鼠标透传，不修改业务状态。

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
- 多对动物同帧繁殖和多幼崽成年批量反馈；
- 畜牧与牧场显式生命周期参与者；
- 独立状态白名单和旧世界恢复。

### 6. 地图资源、生态与危险

- 五张地图独立资源档案；
- 矿物深度与累计阈值数据驱动；
- 保持旧 Seed、hash、salt、深度和概率兼容；
- 地图选择显示资源特点；
- 五地图动物权重、被动/敌对上限和生成节奏；
- 地图、深度、昼夜、敌对、岩浆和洞穴组成危险分；
- HUD 风险反馈与 125 样本硬预算；
- 普通敌对数量和精英危险权重分离；
- 同帧昼夜、生态和攻击状态事件合并为一次危险评估；
- 同方块环境样本复用；
- 多敌对全局来袭提示；
- 种群清理保护真实物理掉落。

### 7. 探矿、日志与地图成长

- 可制作、可重复使用的简易探矿仪；
- 固定半径、步长和样本硬预算；
- 深度、密度和主矿物趋势；
- 不返回矿物方块坐标；
- 最多 64 条持久发现；
- J 键日志、稳定 sequence 和世界内时间；
- 八个探索里程碑；
- profile-aware 地图印记；
- 五种地图材料和五种工作台校准探矿仪；
- 生产资源概率下的目标可达性校验；
- 错误地图明确拒绝且不进入冷却；
- 领取、制作、扫描、保存和完整重载闭环。

### 8. 原子奖励与背包事务

- 八个里程碑的独立奖励状态；
- `locked / claimable / claimed`；
- 原子多物品背包事务；
- 背包满时保持待领取；
- 重试和重复领取幂等；
- 合成服务复用同一事务入口；
- 新世界显式探索与奖励 Schema。

### 9. 可躲避敌对攻击与深渊精英

- 独立敌对攻击档案；
- 数据驱动前摇、命中范围、取消范围和冷却；
- 红色、发光、无碰撞预警圈；
- 后退躲避和击退/硬直打断；
- 前摇结束时重新验证距离；
- 深渊重击者低频条件、独立上限、重击权衡和有用途掉落；
- 五敌对同步生成、前摇、取消、死亡、掉落和重载真实验收。

### 10. ServiceHub 生命周期组合化 · 五个参与者

生产入口继续保留七层继承，当前已迁移：

```text
ServiceHubFeatureCoordinator
├─ machine_runtime
│  ├─ MachineRuntimeScheduler
│  └─ FurnaceService
├─ husbandry_runtime
├─ ranch_runtime
├─ exploration_runtime
└─ exploration_journal_rewards
```

已完成：

- Coordinator 位于 Gameplay 根；
- 唯一参与者 ID；
- 显式依赖；
- 缺失依赖与自依赖拒绝；
- 按顺序规范化世界状态；
- 正序 begin/attach/activate/save；
- 逆序 clear/shutdown；
- 48 条有界阶段诊断；
- 共享保存 Payload；
- 共享角色 Snapshot；
- 原公共字段和节点路径兼容；
- 玩家端口显式解绑；
- 外部实体长期信号显式解除；
- 返回菜单、失败启动和退出清理；
- 真实输入、保存、菜单、重载和发行验收。

见 [SERVICE_HUB_FEATURE_LIFECYCLE.md](SERVICE_HUB_FEATURE_LIFECYCLE.md)。

## 下一阶段重点

### 1. 第二种小型机器

在 Machine Base 已稳定的前提下，增加第一种非 Furnace 生产机器。建议优先：

```text
石材切割机
→ 单输入 / 单输出
→ 无复杂能源网络
→ 位置型保存
→ 共享 Scheduler
→ 独立配方 Registry
→ 只读 UI Snapshot
```

目标不是扩大内容数量，而是证明第二个领域可以复用：

- 注册合同；
- 调度；
- 状态迁移；
- 保存；
- 队列/ETA；
- 批量反馈；
- 菜单与重载生命周期。

禁止：

- 复制 Furnace `_process`；
- 每台机器创建 Timer；
- 独立写世界文件；
- 把所有机器规则加入 FurnaceService；
- 立即引入复杂电网、管道或物流网络。

### 2. Agriculture 生命周期参与者

Agriculture 仍在 Character 继承层中负责反序列化、世界绑定、保存和清理。

建议迁移为：

```text
agriculture_runtime
├─ AgricultureService
├─ AgricultureInteractionAdapter
└─ SoilMoisture / Fertilizer
```

必须保持：

- `agriculture` 存档字段；
- 右键交互；
- 水源、浇灌和堆肥；
- 六小时离线成长上限；
- 生产节点路径；
- 现有农业桌面流程。

### 3. 多敌对焦点可读性与下一张精英

全局 HUD 已解决数量和最快时间，中心提示仍是单一 RayCast 目标。

下一步可增加纯只读优先级：

```text
当前瞄准的蓄力精英
→ 当前瞄准的普通蓄力敌人
→ 最近即将命中的敌人提示
→ 普通目标信息
```

不得自动移动准星或切换攻击目标。

在焦点与压力预算稳定后，再为极寒冰原或荒漠遗迹增加第二只低频精英。仍必须满足地图限定、条件、独立上限、可观察攻击差异、真实反制和有用途掉落。

### 4. 建筑交互与连接形状

- 门开关与方向状态；
- 栅栏自动连接；
- 梯子攀爬；
- 玻璃板自动连接；
- 更多方向化方块；
- 批量建筑和旧世界兼容回归。

视觉、碰撞、预览和提交必须使用同一形状合同。

### 5. 质量平台与规模压测

- 提取 GitHub Actions reusable workflow；
- 16 个机器领域注册上限回归；
- 100+ Machine 实例共享调度压测；
- 24 只受管动物长期模拟；
- 同步繁殖、成长和产物压力用例；
- 大型农场和牧场压测；
- 大量方向化建筑区块重建压测；
- 90+ 物品与配方 UI 滚动性能；
- 多小时运行 soak；
- 数据注册表统一诊断报告。

## 产品优先级

```text
P0  输入、保存、世界可见性、发行稳定性      持续守护
P1  第二种小型机器                          当前玩家/架构里程碑
P1  Agriculture 生命周期参与者              当前维护性里程碑
P1  多敌对焦点与下一张低频精英              下一战斗里程碑
P2  建筑交互与连接形状                      提升建造表达
P3  CI 组合化、规模压测和复杂自动化          合同稳定后推进
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
15. 数据驱动目标验证生产可达性；
16. 多物品业务使用原子背包事务；
17. Feature clear/shutdown 使用逆序；
18. 运行提示去重且有界；
19. 同步批量事件不得线性放大 Toast 和音效；
20. 世界状态迁移按参与者顺序执行；
21. 玩家能力端口在菜单、失败和 Shutdown 时显式解绑；
22. 外部实体长期信号在领域清理前主动断开；
23. 敌对攻击有可观察前摇、稳定取消原因和真实躲避；
24. 纯视觉攻击提示没有碰撞且不改变伤害判定；
25. 新物种通过脚本/数据目录双向校验；
26. 精英具有低频条件、独立上限、可读权衡和有用途掉落；
27. 敌对数量与威胁权重分离；
28. 同帧高频事件按帧合并；
29. 机器领域注册到共享 Scheduler，不创建每实例 Timer；
30. 机器领域不独立写文件；
31. 新分支基于最新 `master`，不得回退并行改动。

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
