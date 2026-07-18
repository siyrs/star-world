# 星的世界 · Product & Architecture Roadmap

## 产品定位

《星的世界》是长期可扩展的单人沙盒生存建造游戏基础，而不是只展示地形的体素 Demo。

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
│  ├─ Block State
│  └─ Directional / Partial Block Geometry
│
├─ Player Domain
│  ├─ Movement / Survival
│  ├─ Inventory Transactions
│  ├─ Equipment / Attributes
│  └─ Combat
│
├─ Harvest Domain
│  ├─ Tool Capability
│  ├─ Block Hardness
│  ├─ Harvest Policy
│  └─ Durability / Repair
│
├─ Exploration & Ecology Domain
│  ├─ Resource Profiles
│  ├─ Creature Ecology Profiles
│  ├─ Live Danger Assessment
│  ├─ Bounded Prospecting
│  ├─ Calibrated Prospecting Profiles
│  ├─ Persistent Discovery Records
│  ├─ Exploration Journal
│  ├─ Profile-aware Milestones
│  └─ Atomic Milestone Rewards
│
├─ Agriculture & Ranch Domain
│  ├─ Crop / Soil / Fertilizer
│  ├─ Husbandry / Attraction
│  └─ Persistent Products
│
├─ Interaction Domain
│  ├─ Block Interaction
│  ├─ Placement Preview
│  ├─ Extension Ports
│  ├─ Container
│  └─ Machine
│
├─ Persistence Domain
│  ├─ Atomic Save Transaction
│  ├─ Migration / Whitelist
│  └─ Recovery
│
└─ Experience Layer
   ├─ UI / Feedback / Audio
   ├─ First-person Viewmodel
   ├─ Guidance / Input Contexts
   └─ Runtime Diagnostics
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

### 3. 玩家体验与视觉

- 持久新手引导和上下文操作提示；
- 有界消息队列；
- 第一人称手持物、挥动和使用反馈；
- 十阶段世界采集裂纹；
- 原创程序化 16×16 像素纹理；
- Design Token 与 1024×576 布局门禁；
- 纯展示层鼠标透传、不修改业务状态。

### 4. 工具、装备与战斗

- 镐、斧、铲、锄和剑；
- 木、石、铁、金、钻石能力层级；
- 方块硬度、工具门槛、速度和掉落资格；
- 按住采集和背包满保护；
- 主手与四类防具槽；
- 属性聚合、防御减伤和速度修正；
- 攻击冷却、击退、硬直、命中反馈和耐久事务；
- 修理失败回滚和 metadata 保留。

### 5. 农业与牧场

- 干燥/湿润耕地、水源和水桶浇灌；
- 小麦、胡萝卜、马铃薯多阶段成长；
- 有界离线成长、成熟收获和自动补种；
- 堆肥与成熟保护；
- 鸡、牛、猪繁殖、幼崽成长和持久管理；
- 饲料吸引和持久鸡蛋；
- 食物加工链；
- 高数量对象共享调度。

### 6. 地图资源分布

- 五张地图独立资源档案；
- 矿物深度与累计阈值数据驱动；
- 保持旧 Seed、hash、salt、深度和概率兼容；
- 地图选择显示资源特点；
- 同 Seed 密度和生产 VoxelWorld 验收。

见 [RESOURCE_DISTRIBUTION.md](RESOURCE_DISTRIBUTION.md)。

### 7. 粗粒度探矿

- 可制作、可重复使用的简易探矿仪；
- 固定半径、步长和样本硬预算；
- 深度、密度和主矿物趋势；
- 不返回矿物坐标；
- 冷却、岩层不足和 UI 阻断保护；
- 最多 64 条持久发现；
- 真实桌面和 Release 验收。

见 [PROSPECTING_SYSTEM.md](PROSPECTING_SYSTEM.md)。

### 8. 地图生态与实时危险

- 五地图动物权重、被动/敌对上限和生成节奏；
- 深渊白天敌对压力与天空群岛低敌对上限；
- 昼夜生成概率；
- 地图、深度、昼夜、敌对、岩浆和洞穴组成危险分；
- 每 0.75 秒最多 125 个环境样本；
- HUD 风险反馈；
- 探矿记录保存危险上下文。

见 [CREATURE_ECOLOGY_DANGER.md](CREATURE_ECOLOGY_DANGER.md)。

### 9. 探索日志与稳定存档

- J 键生产日志；
- 世界日期、时间、地图、区块、深度、趋势和危险；
- 同区域刷新去重；
- 稳定 sequence；
- last_result 严格白名单；
- 独立日志输入上下文；
- 探索状态 v3 和完整世界重载。

见 [EXPLORATION_JOURNAL.md](EXPLORATION_JOURNAL.md)。

### 10. 原子探索奖励

- 八个里程碑的独立奖励状态；
- `locked / claimable / claimed`；
- 原子多物品背包事务；
- 背包满时保持待领取；
- 重试和重复领取幂等；
- 合成服务复用同一事务入口；
- 新世界显式探索与奖励 schema。

见 [EXPLORATION_MILESTONE_REWARDS.md](EXPLORATION_MILESTONE_REWARDS.md)。

### 11. 地图印记与校准探矿

- 共享 `MapProfileCatalog`；
- profile-aware 地图印记里程碑；
- 生产资源概率下的目标可达性校验；
- 五种不占方块 ID 的地图材料；
- 五种工作台校准探矿仪；
- 旧简易探矿仪完全兼容；
- 每工具理论样本和全局 768 硬上限；
- 错误地图明确拒绝；
- 领取、制作、真实扫描、保存和完整重载闭环。

见 [MAP_SIGNATURE_PROSPECTING.md](MAP_SIGNATURE_PROSPECTING.md)。

## 下一阶段重点

### 1. ServiceHub 生命周期组合化

目标：控制不断增长的 `*_progression_service_hub.gd` 深继承链，同时不进行高风险大重写。

建议从探索领域开始增加小型参与者合同：

```text
install(hub)
begin_world(state)
attach_game(world, player)
activate()
save_into(payload)
clear()
snapshot_into(snapshot)
```

迁移顺序：

```text
探索奖励或日志
→ 探矿与危险
→ 牧场产物
→ 农业与维修
```

约束：

- 每次只迁移一个低风险功能；
- 保留旧 Hub 公共字段和调用入口；
- 不创建万能 FeatureManager；
- 生命周期顺序必须有回归；
- 返回菜单、启动失败和 `_exit_tree` 都必须清理。

### 2. 敌对攻击前摇与少量精英生态

在现有 CombatService、CreatureSpawner 和危险系统上增加：

- 敌对攻击前摇；
- 可读的方向和危险提示；
- 更明确的死亡原因；
- 每张地图少量精英变体；
- 精英掉落与地图成长路线关联。

先保证攻击可读和可躲避，不立即增加 Boss、大量状态效果或复杂行为树。

### 3. Machine Base 与自动化接口

从成熟 FurnaceService 提取小型能力：

- 输入/输出；
- 进度与阻塞；
- 燃料或能源接口；
- 暂停与有界离线推进；
- 位置型序列化；
- UI 只消费 snapshot。

不得把熔炉服务扩大为万能 MachineManager。

### 4. 建筑交互扩展

- 门开关与方向状态；
- 栅栏自动连接；
- 梯子攀爬；
- 玻璃板自动连接；
- 更多方向化方块；
- 建筑结构批量和旧世界兼容回归。

视觉、碰撞、预览和提交必须使用同一形状合同。

### 5. 质量平台与规模压测

- 提取 GitHub Actions reusable workflow；
- 大型农场和牧场压测；
- 大量方向化建筑区块重建压测；
- 探索日志、奖励和物品规模的存档体积报告；
- 90+ 物品与配方 UI 滚动性能；
- 多小时运行 soak；
- 数据注册表统一诊断报告。

## 产品优先级

```text
P0  输入、保存、世界可见性、发行稳定性          持续守护
P1  ServiceHub 生命周期组合化                    当前架构里程碑
P1  敌对攻击前摇与少量精英生态                  提升风险回报
P2  Machine Base 与自动化接口                   复用成熟机器能力
P2  建筑交互与自动连接形状                      提升建造表达
P2  CI reusable workflow 与规模压测              控制长期成本
P3  更多内容、结构、机器和生物                  在闭环与压测后扩展
```

每个里程碑必须具备：

```text
用户目标
→ 可玩闭环
→ 领域边界
→ 数据合同
→ 存档合同
→ 失败反馈
→ Runtime 回归
→ 真实桌面验收
→ Windows Release 验收
```

## 工程质量标准

所有新增系统必须满足：

1. 独立领域服务或明确纯策略；
2. 数据注册表驱动；
3. 唯一持久状态所有者；
4. 存档兼容与异常数据规范化；
5. 领域回归、真实桌面和 Windows Release 验收；
6. 日志无脚本错误、解析错误和资源泄漏；
7. UI 不直接修改领域 Dictionary；
8. Player 不承担存档、面板或复杂规则；
9. 高数量对象共享调度；
10. 高成本工作具有预算、硬上限和诊断；
11. 扩展公共合同保留兼容入口或明确迁移；
12. 方块 numeric ID 只追加；
13. 可制作方块通过物品、世界、视觉、采集和保存 round-trip；
14. 持久顺序不依赖跨会话无意义的进程相对时间；
15. 动态 Dictionary 持久化必须经过白名单和大小上限；
16. 功能 Overlay ID 通过共享合同分配；
17. 数据驱动目标必须在生产概率和状态下可达；
18. 新材料必须拥有真实用途，不能成为死内容；
19. 派生视图不得复制持久事实源形成双写；
20. 新分支基于最新 `master`，不得回退并行改动。

## 设计规范

### UI

- 使用统一 Design Token；
- 支持最低 1024×576；
- 错误状态必须可理解；
- 阻塞面板拥有独立 InputContext；
- 世界提示不与阻塞面板叠加；
- 关键结果不能只依靠颜色。

### 代码

- 避免 God Object；
- 服务职责单一；
- 通过事件、小型端口和能力查询降低耦合；
- 优先组合，继承只用于薄适配；
- 动态调用边界显式类型收窄；
- 领域写入返回可验证成功或失败；
- 跨目录关系必须有完整性门禁；
- 世界生成差异优先使用纯策略；
- 迁移必须处理重复、未知字段和超额数据。

### 产品

- 先解决玩家能否理解和完成目标，再增加内容数量；
- 不用隐藏惩罚制造深度；
- 工具不足、空间不足、权限不足和资源稀缺必须提前解释；
- 探测功能不得通过精确坐标替代真实探索；
- 持久数据必须在游戏内具有可访问价值；
- 新功能不能破坏移动、鼠标、画面、保存或退出资源；
- 每次主分支更新保留可复现发行证据。
