# 星的世界 · Product & Architecture Roadmap

## 产品定位

《星的世界》不是简单的体素 Demo，而是长期可扩展的单人沙盒生存建造游戏基础。

核心原则：

- 玩家体验优先；
- 系统模块化；
- 数据驱动扩展；
- 每个玩法拥有独立领域边界；
- 所有重要功能必须可测试、可保存、可恢复；
- 功能先形成可玩的闭环，再扩展内容数量；
- 旧世界、方块 numeric ID 和 Seed 结果必须有明确兼容策略；
- 真实桌面与最终 Windows Release 是合入主分支的必要证据。

## 当前领域结构

```text
Game Runtime
├─ World Domain
│  ├─ Chunk Streaming
│  ├─ Terrain Generation
│  ├─ Resource Distribution
│  ├─ Block State
│  └─ Directional / Partial Block Geometry
│
├─ Player Domain
│  ├─ Movement
│  ├─ Survival
│  ├─ Inventory
│  ├─ Equipment
│  ├─ Attributes
│  └─ Combat
│
├─ Harvest Domain
│  ├─ Tool Capability
│  ├─ Block Hardness
│  ├─ Harvest Policy
│  ├─ Timed Harvest Transaction
│  └─ Durability / Repair
│
├─ Exploration & Ecology Domain
│  ├─ Resource Profiles
│  ├─ Prospecting Registry
│  ├─ Bounded Area Sampling
│  ├─ Creature Ecology Profiles
│  ├─ Live Danger Assessment
│  ├─ Persistent Discovery Records
│  ├─ Exploration Journal
│  └─ Milestone Policy
│
├─ Agriculture & Ranch Domain
│  ├─ Crop Registry
│  ├─ Soil Moisture
│  ├─ Fertilizer
│  ├─ Husbandry
│  ├─ Attraction
│  └─ Persistent Products
│
├─ Interaction Domain
│  ├─ Block Interaction
│  ├─ Placement Preview
│  ├─ Extension Ports
│  ├─ Container
│  └─ Machine
│
├─ Crafting & Machine Domain
│  ├─ Recipes
│  ├─ Stations
│  ├─ Furnace
│  └─ Repair Station
│
├─ Persistence Domain
│  ├─ Atomic Save Transaction
│  ├─ Migration
│  ├─ Whitelisted Dynamic State
│  └─ Recovery
│
└─ Experience Layer
   ├─ UI
   ├─ Feedback
   ├─ First-person Viewmodel
   ├─ Audio
   ├─ Guidance
   ├─ Input Contexts
   └─ Runtime Diagnostics
```

## 已完成里程碑

### 1. 基础运行与发行可靠性

- 真实 WASD、鼠标、按钮和 InputContext；
- 世界启动保护与非空白画面门禁；
- 安全出生与跨区块碰撞预加载；
- 渐进区块加载和自适应预算；
- F3 诊断与多轮生命周期 soak；
- 原子 JSON、临时文件与备份恢复；
- Windows Release 实际导出、启动、截图、报告和资源退出检查。

### 2. 建造、交互与机器

- 工作台世界授权；
- 位置型箱子及内容保护；
- 熔炉原料、燃料、产出、持续进度和离线恢复；
- 修理台与耐久恢复事务；
- 精确体素焦点、绿色/红色放置预览；
- 台阶、楼梯、耕地和床的真实非整块几何；
- 木楼梯四方向放置、旋转斜坡碰撞与统一掉落；
- 玻璃板从“可制作但不可放置”修复为真实双轴薄方块；
- 方块、物品、配方、视觉和采集的跨目录完整性门禁；
- 交互、机器、UI 和存档领域分离。

### 3. 玩家体验与原创视觉

- 持久化新手引导；
- 上下文操作提示；
- 有界即时反馈；
- 第一人称手持物、挥动、使用、采集动作；
- 十阶段世界采集裂纹；
- 原创程序化 16×16 像素方块纹理；
- Design Token 与 1024×576 布局门禁；
- 视觉层无碰撞、鼠标透传且不修改业务状态。

### 4. 工具、装备与战斗成长

- 镐、斧、铲、锄和剑；
- 木、石、铁、金、钻石能力层级；
- 方块硬度、推荐工具、错误工具速度和掉落门槛；
- 按住采集、进度、掉落资格与背包满保护；
- 工具、武器和防具耐久；
- 主手与四类防具槽；
- 属性聚合、防御减伤和移动/采集修正；
- 攻击冷却、击退、硬直、命中反馈与单次耐久事务；
- 修理材料、失败回滚和 metadata 保留。

### 5. 农业与牧场生产链

- 干燥/湿润耕地、邻近水源与水桶浇灌；
- 小麦、胡萝卜、马铃薯多阶段生长；
- 有界离线成长、成熟收获和自动补种；
- 堆肥施肥与成熟保护；
- 鸡、牛、猪喂养、繁殖、幼崽成长和持久管理；
- 饲料吸引与持久鸡蛋生产；
- 面包、烤马铃薯、熟鸡蛋等食物链；
- 高数量对象共享调度，不为每个作物或动物产品创建独立 Timer。

### 6. 地图资源层级基础

- 五张地图拥有独立资源档案；
- 矿物深度与累计阈值数据驱动；
- 保持旧 Seed、hash、salt、深度和概率兼容；
- 地图选择界面展示资源特点；
- 同 Seed 密度排序和生产 VoxelWorld 验收；
- 为探索反馈、地图危险度和特有掉落建立稳定基础。

架构合同见 [RESOURCE_DISTRIBUTION.md](RESOURCE_DISTRIBUTION.md)。

### 7. 粗粒度探索反馈

- 可制作、可重复使用的简易探矿仪；
- 真实右键扫描当前区域；
- 固定半径、步长和最多 700 个样本的硬预算；
- 浅层/中层/下层/深层反馈；
- 贫瘠/普通/可观/富集反馈；
- 只报告最强矿物类型，不返回矿物坐标；
- 冷却、岩层样本不足和 UI 阻断保护；
- 当前区块与深度组成稳定发现记录；
- 最多 64 条发现记录，随世界保存与迁移；
- 第一人称使用动画、HUD 反馈、真实桌面与 Release 门禁。

架构合同见 [PROSPECTING_SYSTEM.md](PROSPECTING_SYSTEM.md)。

### 8. 地图生态与实时危险

- 五张地图拥有独立动物权重、被动/敌对上限和生成节奏；
- 深渊白天敌对压力、天空群岛低敌对上限等地图差异；
- 昼夜阶段影响敌对生成概率与上限；
- 附近敌对生物的有界距离查询；
- 地图、深度、昼夜、敌对、岩浆和洞穴组成 0–100 危险分；
- 每 0.75 秒最多 125 个环境样本；
- HUD 显示低、警戒、危险、极高四档风险和主要原因；
- 探矿记录保存扫描时危险上下文；
- 探索状态 v1 → v2 迁移、真实桌面与 Windows Release 验收。

架构合同见 [CREATURE_ECOLOGY_DANGER.md](CREATURE_ECOLOGY_DANGER.md)。

### 9. 探索日志与里程碑

- 按 `J` 打开的生产探索日志；
- 记录世界内日期、时间、地图、区块、深度、资源趋势和危险上下文；
- 同一区块与深度重新扫描只更新原记录；
- `sequence + world_day + world_time` 提供跨会话稳定顺序；
- `last_result` 使用严格存档白名单，不允许坐标数组或未知字段回流；
- 七个数据驱动探索里程碑；
- 日志只派生探矿记录，不保存第二份状态；
- 独立 `CONTEXT_JOURNAL`、鼠标和玩家输入隔离；
- 修理与日志使用共享扩展 Overlay ID 合同；
- 探索存档 v3、1024×576 布局、完整世界重载与 Release 门禁。

架构合同见 [EXPLORATION_JOURNAL.md](EXPLORATION_JOURNAL.md)。

## 下一阶段重点

### 1. 地图特有发现与奖励事务

目标：让不同地图的探索结果真正改变玩家成长路线，而不是仅显示不同概率。

当前进度：

```text
资源档案与地图提示（已完成）
→ 简易探矿工具（已完成）
→ 当前区域粗粒度资源倾向（已完成）
→ 实时深度与危险提示（已完成）
→ 持久探索日志与里程碑（已完成）
→ 地图特有发现与材料
→ 里程碑奖励事务
```

下一步约束：

- 每张地图先增加少量有明确用途的特有发现，不批量堆砌同质矿石；
- 新方块 numeric ID 只能追加；
- 特有材料必须接入物品、配方、视觉、采集、资源分布、探矿和存档完整性；
- 里程碑奖励由独立事务服务发放，UI 不直接写背包；
- 背包满时保留待领取状态，不能吞掉奖励；
- 探测仍只提供粗粒度信息，禁止精确坐标透视。

### 2. 敌对生态反馈与少量精英变体

在现有 CombatService、CreatureSpawner 和危险系统上逐步增加：

- 敌对生物攻击前摇和可读危险提示；
- 更明确的死亡原因与风险来源；
- 地图与深度驱动的少量精英变体；
- 精英掉落与地图特有成长路线关联；
- 不立即堆叠 Boss、大量状态效果或复杂行为树。

先保证风险、收益和反馈可理解，再增加内容数量。

### 3. Machine Base 与自动化接口

在成熟 FurnaceService 基础上建立小型共享合同：

- 输入/输出能力；
- 进度与阻塞状态；
- 能源或燃料接口；
- 暂停与有界离线推进；
- 位置型序列化；
- 世界可视状态；
- UI 只消费 snapshot。

新机器应复用小型能力，不把 FurnaceService 扩大成万能 MachineManager。

### 4. 建筑交互扩展

当前建议：

- 门的开关与方向状态；
- 栅栏连接；
- 梯子攀爬；
- 玻璃板自动连接；
- 更多方向化方块；
- 建筑结构批量回归；
- 旧世界与方块 ID 兼容。

所有视觉、碰撞、预览和提交必须使用同一形状/方向合同。

### 5. 架构与质量平台扩展

在继续增加领域前逐步处理：

- 将多层 `*_progression_service_hub.gd` 继承迁移为小型 Feature Installer 组合；
- 建立 UI 扩展面板注册合同，避免基础 `GameUI` 持续增加专用分支；
- 提取 GitHub Actions reusable workflow，减少重复安装和项目导入；
- 大型农场、牧场和方向化建筑压测；
- 探索记录与长期存档体积报告；
- 多小时运行 soak；
- 数据注册表统一目录。

不得用一次性大重写替换成熟服务，必须按功能切片渐进迁移。

## 产品优先级

```text
P0  输入、保存、世界可见性、发行稳定性          持续守护
P1  地图特有发现与探索奖励事务                  当前里程碑
P1  敌对攻击前摇与少量精英生态                  提升风险回报
P2  Machine Base 与自动化接口                   复用成熟机器能力
P2  建筑交互与自动连接形状                      提升建造表达
P2  ServiceHub / UI 扩展 / CI 组合化             控制长期复杂度
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

1. 独立领域服务或明确的纯策略；
2. 数据注册表驱动；
3. 唯一状态所有者；
4. 存档兼容与异常数据规范化；
5. 领域回归测试；
6. 真实桌面交互测试；
7. Windows Release 验收；
8. 日志无脚本错误、解析错误和资源泄漏；
9. UI 不直接修改领域 Dictionary；
10. Player 不承担存档、面板或复杂规则；
11. 高数量对象共享调度，不为每对象创建独立 `_process` 或 Timer；
12. 高成本工作具有预算、上限和诊断；
13. 扩展公共合同保留兼容入口或提供明确迁移；
14. 方块 numeric ID 只追加；
15. 可制作方块必须通过物品、世界、视觉、采集和保存 round-trip；
16. 持久顺序不得依赖跨会话无意义的进程相对时间；
17. 动态 Dictionary 写入存档必须经过字段白名单和大小上限；
18. 功能 Overlay ID 必须通过共享注册合同分配；
19. 新分支必须基于最新 `master`，不得回退并行改动。

## 设计规范

### UI

- 使用统一 Design Token；
- 明确视觉层级；
- 支持最低 1024×576；
- 错误状态必须可理解；
- 世界提示不与阻塞面板叠加；
- 纯展示 HUD 必须鼠标透传；
- 阻塞面板必须拥有独立 InputContext；
- 关键结果不能只依靠颜色表达。

### 代码

- 避免 God Object；
- 服务职责单一；
- 通过事件、小型端口和能力查询降低耦合；
- 优先组合，继承只用于薄适配层；
- 动态调用边界显式类型收窄；
- 领域写入必须返回可验证成功或失败；
- 世界生成差异优先拆为纯策略，不继续扩大 Generator 条件分支；
- 跨数据目录关系必须有自动完整性门禁；
- 派生视图不得复制持久事实源形成双写状态；
- 所有迁移必须能够处理重复、未知字段和超额数据。

### 产品

- 先解决用户能否理解和完成目标，再增加内容数量；
- 不用隐藏惩罚制造“深度”；
- 工具不足、空间不足、权限不足、作物未成熟和资源稀缺必须提前解释；
- 探测功能不得通过精确坐标替代真实探索；
- 持久数据必须在游戏内具有可访问的玩家价值；
- 新功能不能破坏移动、鼠标、按钮、画面、保存或退出资源；
- 每次主分支更新都保留可复现的发行证据。
