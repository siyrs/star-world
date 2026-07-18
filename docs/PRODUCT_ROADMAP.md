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
│  ├─ Bounded / Calibrated Prospecting
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
├─ Interaction & Machine Domain
│  ├─ Block Interaction
│  ├─ Placement Preview
│  ├─ Extension Ports
│  ├─ Container
│  └─ Furnace / Repair
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

### 6. 地图资源、生态与危险

- 五张地图独立资源档案；
- 矿物深度与累计阈值数据驱动；
- 保持旧 Seed、hash、salt、深度和概率兼容；
- 地图选择显示资源特点；
- 五地图动物权重、被动/敌对上限和生成节奏；
- 地图、深度、昼夜、敌对、岩浆和洞穴组成危险分；
- HUD 风险反馈与有界环境采样。

相关合同：

- [RESOURCE_DISTRIBUTION.md](RESOURCE_DISTRIBUTION.md)
- [CREATURE_ECOLOGY_DANGER.md](CREATURE_ECOLOGY_DANGER.md)

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
- 错误地图明确拒绝；
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
- 新世界显式探索与奖励 schema。

见 [EXPLORATION_MILESTONE_REWARDS.md](EXPLORATION_MILESTONE_REWARDS.md)。

### 9. ServiceHub 生命周期组合化 · 第一阶段

生产 Hub 目前仍保留兼容继承入口：

```text
Gameplay
→ Tool
→ Character
→ Repair
→ Husbandry
→ Ranch
→ Exploration
```

第一批已经把“探索日志 + 里程碑奖励”迁移为生命周期参与者：

```text
ServiceHubFeatureCoordinator
→ ExplorationJournalRewardParticipant
   ├─ ExplorationJournalService
   └─ ExplorationMilestoneRewardService
```

已完成：

- 唯一参与者 ID；
- 完整生命周期合同；
- 正序安装/开始/保存；
- 逆序 clear/shutdown；
- 48 条有界阶段诊断；
- 共享保存 payload；
- 共享角色诊断 snapshot；
- 公共字段和节点路径兼容；
- 返回菜单、世界失败和退出清理；
- 新奖励可领取单次提示；
- 继续世界不重复提示已有待领奖励；
- 真实右键、J 键、领取、保存、菜单、重载和失败启动验收。

见 [SERVICE_HUB_FEATURE_LIFECYCLE.md](SERVICE_HUB_FEATURE_LIFECYCLE.md)。

## 下一阶段重点

### 1. 探矿与危险生命周期参与者

在第一批合同稳定后，下一批迁移真实世界依赖较强的探索服务：

```text
map profile
→ danger begin/attach/activate
→ prospecting begin/attach/player bind
→ exploration save
→ diagnostics
→ return/failure/shutdown clear
```

约束：

- 保留 `prospecting_service` 和 `exploration_danger_service` 公共字段；
- 保留玩家 `bind_prospecting_service` 入口；
- 错误地图校准不进入冷却；
- 世界启动失败不得留下玩家或世界引用；
- 迁移前后探索存档逐字段一致；
- 不把 Coordinator 下移到基础 Hub，直到至少两个参与者通过完整发行验收。

### 2. 敌对攻击前摇与少量精英生态

当前普通敌对生物进入攻击范围后会立即造成伤害。下一条玩家闭环：

```text
进入攻击范围
→ 锁定方向
→ 可见/可听前摇
→ 玩家可后退、击退或打断
→ 目标仍有效才命中
→ 明确死亡原因
```

随后再增加少量地图精英：

- 每张地图最多一个轻量变体；
- 数据驱动生命、速度、前摇、伤害和掉落；
- 精英材料必须进入地图成长路线；
- 不立即引入 Boss、复杂状态效果或行为树。

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
P1  探矿与危险参与者迁移                        当前架构里程碑
P1  敌对攻击前摇与可躲避战斗                    下一玩家闭环
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
19. 新分支必须基于最新 `master`，不得回退并行改动。

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
