# 星的世界 · Product & Architecture Roadmap

## 产品定位

《星的世界》是长期可扩展的单人第一人称 3D 像素沙盒生存建造游戏基础，而不是一次性体素 Demo。

核心原则：

- 玩家体验优先；
- 系统模块化；
- 数据驱动扩展；
- 每个玩法拥有明确领域边界；
- 重要功能可测试、可保存、可恢复；
- 先形成可玩的闭环，再扩大内容数量；
- 旧世界、方块 numeric ID 和 Seed 结果具有明确兼容策略；
- 真实桌面与最终 Windows Release 是主分支合入门禁。

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
│  ├─ Inventory Transactions
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
│  ├─ Milestone Policy
│  └─ Milestone Reward Transactions
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
│  ├─ Atomic Craft Transaction
│  ├─ Stations
│  ├─ Furnace
│  └─ Repair Station
│
├─ Persistence Domain
│  ├─ Atomic Save Transaction
│  ├─ Domain Migration
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
- 玻璃板真实双轴薄方块；
- 方块、物品、配方、视觉和采集的跨目录完整性门禁。

### 3. 玩家体验与原创视觉

- 持久化新手引导；
- 上下文操作提示；
- 有界即时反馈；
- 第一人称手持物、挥动、使用和采集动作；
- 十阶段世界采集裂纹；
- 原创程序化 16×16 像素方块纹理；
- Design Token 与紧凑布局门禁；
- 视觉层无碰撞、鼠标透传且不修改业务状态。

### 4. 工具、装备与战斗成长

- 镐、斧、铲、锄和剑；
- 木、石、铁、金、钻石能力层级；
- 方块硬度、工具建议、错误工具速度和掉落门槛；
- 按住采集、进度、背包满保护；
- 工具、武器和防具耐久；
- 主手与四类防具槽；
- 属性聚合、防御减伤和移动/采集修正；
- 攻击冷却、击退、硬直和命中反馈；
- 修理材料、失败回滚和 metadata 保留。

### 5. 农业与牧场生产链

- 干燥/湿润耕地、邻近水源与水桶浇灌；
- 小麦、胡萝卜、马铃薯多阶段生长；
- 有界离线成长、成熟收获和自动补种；
- 堆肥施肥与成熟保护；
- 鸡、牛、猪喂养、繁殖、幼崽成长和持久管理；
- 饲料吸引与持久鸡蛋生产；
- 面包、烤马铃薯、熟鸡蛋等食物链；
- 高数量对象共享调度。

### 6. 地图资源层级基础

- 五张地图拥有独立资源档案；
- 矿物深度与累计阈值数据驱动；
- 保持旧 Seed、hash、salt、深度和概率兼容；
- 地图选择界面展示资源特点；
- 同 Seed 密度排序和生产 VoxelWorld 验收。

架构合同见 [RESOURCE_DISTRIBUTION.md](RESOURCE_DISTRIBUTION.md)。

### 7. 粗粒度探索反馈

- 可制作、可重复使用的简易探矿仪；
- 真实右键扫描当前区域；
- 固定半径、步长和最多 700 个样本的硬预算；
- 深度、密度和主矿物类型反馈；
- 冷却、岩层样本不足和 UI 阻断保护；
- 最多 64 条发现记录；
- 不返回矿物精确坐标。

架构合同见 [PROSPECTING_SYSTEM.md](PROSPECTING_SYSTEM.md)。

### 8. 地图生态与实时危险

- 五张地图拥有独立动物权重、被动/敌对上限和生成节奏；
- 昼夜阶段影响敌对生成概率与上限；
- 附近敌对生物有界查询；
- 地图、深度、昼夜、敌对、岩浆和洞穴组成 0–100 危险分；
- 每 0.75 秒最多 125 个环境样本；
- HUD 显示四档风险与主要原因；
- 探矿记录保存扫描时危险上下文。

架构合同见 [CREATURE_ECOLOGY_DANGER.md](CREATURE_ECOLOGY_DANGER.md)。

### 9. 探索日志与里程碑

- 按 `J` 打开的生产探索日志；
- 稳定发现编号、世界日期、地图、区块、深度、资源趋势和危险上下文；
- 同一区块与深度重新扫描只更新原记录；
- `last_result` 严格存档白名单；
- 七个数据驱动探索里程碑；
- 日志只派生探矿记录，不保存第二份事实状态；
- 独立 `CONTEXT_JOURNAL`；
- 探索存档 v3 与完整世界重载。

架构合同见 [EXPLORATION_JOURNAL.md](EXPLORATION_JOURNAL.md)。

### 10. 探索里程碑奖励与原子背包事务

- 七个里程碑全部拥有数据驱动奖励；
- 初次勘探具有五地图差异补给；
- `InventoryTransactionPolicy` 在副本中模拟完整移除和加入；
- 多物品包只会全部成功或完全失败；
- 生产合成服务使用同一事务入口；
- 日志 UI 只调用奖励服务，不直接写背包；
- 背包满时保持待领取，释放空间后可重试；
- 重复领取幂等；
- claimed 状态独立持久化和迁移；
- 新世界初始 schema 包含探索与奖励域；
- 真实鼠标领取、36 格满背包、返回菜单、完整重载和 Windows Release 门禁。

架构合同见 [EXPLORATION_MILESTONE_REWARDS.md](EXPLORATION_MILESTONE_REWARDS.md)。

## 下一阶段重点

### 1. 地图特有发现与有用途材料

目标：让地图差异进一步进入生产链，而不是只通过概率和一次补给表达。

当前进度：

```text
资源档案与地图提示（已完成）
→ 简易探矿与粗粒度趋势（已完成）
→ 实时危险、日志和里程碑（已完成）
→ 原子里程碑奖励（已完成）
→ 地图特有发现
→ 有明确消费场景的特有材料
```

约束：

- 每张地图先增加少量、可解释的特有发现；
- 不批量堆砌仅颜色不同的同质矿石；
- 新方块 numeric ID 只能追加；
- 新材料必须接入物品、配方或功能、探矿、日志、存档和完整性门禁；
- 单个世界内即可使用，不设计依赖跨世界搬运的配方；
- 探测仍不提供方块级坐标。

### 2. ServiceHub 生命周期参与者

当前生产 Hub 通过多层继承叠加功能。下一步建立渐进式生命周期参与者合同：

```text
prepare_world
attach_game
activate
serialize_into
clear
snapshot
```

先迁移新领域，不一次性重写成熟系统；每次迁移必须保持场景入口、存档键和测试兼容。

### 3. 敌对生态反馈与少量精英变体

- 敌对生物攻击前摇和可读危险提示；
- 更明确的死亡原因与风险来源；
- 地图与深度驱动的少量精英变体；
- 精英掉落与地图成长路线关联；
- 不立即堆叠 Boss、大量状态效果或复杂行为树。

### 4. Machine Base 与自动化接口

在成熟 FurnaceService 基础上建立小型共享合同：

- 输入/输出能力；
- 进度与阻塞状态；
- 能源或燃料接口；
- 暂停与有界离线推进；
- 位置型序列化；
- 世界可视状态；
- UI 只消费 snapshot。

### 5. 建筑交互扩展

- 门的开关与方向状态；
- 栅栏连接；
- 梯子攀爬；
- 玻璃板自动连接；
- 更多方向化方块；
- 建筑结构批量回归；
- 旧世界与方块 ID 兼容。

### 6. 质量平台组合化

- 提取 GitHub Actions reusable workflow；
- 减少重复 Godot 安装和 strict import；
- 大型农场、牧场和方向化建筑压测；
- 探索记录与长期存档体积报告；
- 多小时运行 soak；
- 数据注册表统一目录。

## 产品优先级

```text
P0  输入、保存、世界可见性、发行稳定性          持续守护
P1  地图特有发现与有用途材料                    当前里程碑
P1  ServiceHub 生命周期参与者                   控制组合复杂度
P1  敌对攻击前摇与少量精英生态                  提升风险回报
P2  Machine Base 与自动化接口                   复用成熟机器能力
P2  建筑交互与自动连接形状                      提升建造表达
P2  CI reusable workflow 与规模压测              控制长期成本
P3  更多内容、结构、机器和生物                  在闭环后扩展
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
3. 唯一状态所有者；
4. 存档兼容与异常数据规范化；
5. 领域回归测试；
6. 真实桌面交互测试；
7. Windows Release 验收；
8. 日志无脚本错误、解析错误和资源泄漏；
9. UI 不直接修改领域 Dictionary 或背包；
10. Player 不承担存档、面板或复杂规则；
11. 高数量对象共享调度；
12. 高成本工作具有预算、上限和诊断；
13. 扩展公共合同保留兼容入口或提供迁移；
14. 方块 numeric ID 只追加；
15. 可制作方块通过物品、世界、视觉、采集和保存 round-trip；
16. 持久顺序不依赖进程相对时间；
17. 动态 Dictionary 存档使用字段白名单和大小上限；
18. 功能 Overlay ID 通过共享合同分配；
19. 多物品领域写入必须使用整体事务，不能逐项预判容量；
20. 失败事务不得公开中间状态；
21. 派生视图不得复制持久事实源形成双写；
22. 新分支基于最新 `master`，不得回退并行改动。

## 设计规范

### UI

- 使用统一 Design Token；
- 支持最低 1024×576；
- 错误状态可理解；
- 阻塞面板拥有独立 InputContext；
- 纯展示 HUD 鼠标透传；
- 关键结果不只依靠颜色；
- 领取按钮只调用事务服务。

### 代码

- 避免 God Object；
- 服务职责单一；
- 通过事件、小型端口和能力查询降低耦合；
- 优先组合，继承只用于薄适配层；
- 动态调用边界显式类型收窄；
- 世界生成差异优先拆为纯策略；
- 跨数据目录关系具有自动完整性门禁；
- 所有迁移处理重复、未知字段和超额数据。

### 产品

- 先解决玩家能否理解和完成目标，再增加内容数量；
- 不用隐藏惩罚制造深度；
- 空间不足、工具不足、权限不足和资源稀缺提前解释；
- 探测功能不得用精确坐标替代真实探索；
- 持久数据必须在游戏内具有可访问价值；
- 新功能不能破坏移动、鼠标、按钮、画面、保存或退出资源；
- 每次主分支更新保留可复现发行证据。
