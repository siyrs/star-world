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
│  ├─ Resource Distribution / Map Identity
│  └─ Directional / Partial Block Geometry
│
├─ Player Domain
│  ├─ Movement / Survival
│  ├─ Inventory Transactions
│  ├─ Equipment / Attributes
│  └─ Combat Cadence
│
├─ Creature & Ecology Domain
│  ├─ Creature Catalog / Conditional Ecology
│  ├─ Population / Per-species Budgets
│  ├─ Weighted Danger
│  └─ Dodgeable Hostile Windups
│
├─ Exploration Domain
│  ├─ Bounded / Calibrated Prospecting
│  ├─ Persistent Journal / Milestones
│  └─ Atomic Rewards
│
├─ Agriculture & Ranch Domain
│  ├─ Crops / Soil / Fertilizer
│  ├─ Husbandry / Breeding / Attraction
│  └─ Persistent Products / Batched Feedback
│
├─ Machine Domain
│  ├─ MachineRuntimeScheduler
│  ├─ Machine State / Progress / Completion Policies
│  ├─ FurnaceService
│  ├─ StonecutterService
│  ├─ MachineInteractionRouter / Atomic Capability
│  └─ Bounded Adjacent Chest Automation
│
├─ Persistence & Release Domain
│  ├─ Atomic Save Transaction
│  ├─ Domain Migration / Whitelist
│  ├─ Backup Recovery
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
- 渐进区块加载、卸载和自适应预算；
- F3 诊断与多轮生命周期 soak；
- 原子 JSON、临时文件和备份恢复；
- Windows Release 实际导出、启动、截图、报告和资源退出检查；
- 首次启动检查 GitHub 最新稳定 Release；
- Range / If-Range / ETag 跨重启续传；
- ZIP 与逐文件 SHA-256、Manifest 白名单；
- 外部更新助手目录切换、自动重启、ACK 和失败回滚；
- Tag 驱动的 Windows GitHub Release 固定资产发布。

### 2. 建造、交互与目录完整性

- 工作台、箱子、熔炉、修理台、床和石材切割机；
- 位置型世界交互和非空内容保护；
- 精确目标和统一放置预览；
- 台阶、四方向楼梯、耕地、床和玻璃板非整块几何；
- 方块、物品、配方、视觉、采集和保存目录门禁；
- 新方块 numeric ID 只追加。

### 3. Machine Base、能力合同与轻量自动化

共享结构：

```text
MachineRuntimeScheduler
├─ FurnaceService
├─ StonecutterService
└─ MachineAutomationService

MachineInteractionRouter
└─ Atomic Machine Capability
```

已完成：

- 单一可暂停机器调度循环；
- 最多 16 个机器领域、4096 台持久机器；
- 四小时离线推进和 512 次模拟迭代上限；
- 严格机器状态白名单；
- 队列、下一份剩余时间和整批 ETA；
- 同帧跨机器完成合并为一条消息和一次音效；
- Furnace 原料、燃料、产出、离线恢复和拆除保护；
- Stonecutter 无燃料单输入/单输出加工；
- 通用机器打开、槽位、拆除和位置 ID 路由；
- `get_machine_capabilities`、原子插入和原子提取；
- 满背包与满容器时零部分写入；
- 机器正上方箱子供料、正下方箱子收货；
- 每 0.5 秒最多 16 台机器、64 件物品、128 次事务探测；
- 事件维护候选目录，常规周期不遍历全部机器；
- 自动化游标、缓存和统计不进入存档；
- 两种机器同批加工、保存、菜单清理和完整重载验收。

合同见：

- [MACHINE_BASE.md](MACHINE_BASE.md)
- [STONECUTTER_MACHINE.md](STONECUTTER_MACHINE.md)
- [MACHINE_CAPABILITY_CONTRACT.md](MACHINE_CAPABILITY_CONTRACT.md)
- [LIGHTWEIGHT_MACHINE_AUTOMATION.md](LIGHTWEIGHT_MACHINE_AUTOMATION.md)

### 4. 玩家体验与原创视觉

- 持久新手引导和上下文操作提示；
- 有界消息队列；
- 第一人称手持物、挥动和使用反馈；
- 十阶段世界采集裂纹；
- 原创程序化 16×16 像素纹理；
- Design Token 与 1024×576 布局门禁；
- 纯展示层鼠标透传，不修改业务状态。

### 5. 工具、装备与玩家战斗

- 镐、斧、铲、锄和剑；
- 木、石、铁、金、钻石能力层级；
- 方块硬度、工具门槛、速度和掉落资格；
- 按住采集和背包满保护；
- 主手与四类防具槽；
- 属性聚合、防御减伤和速度修正；
- 玩家攻击冷却、击退、硬直、命中反馈和耐久事务；
- 修理失败回滚和 metadata 保留。

### 6. 农业、畜牧与牧场生产链

- 干燥/湿润耕地、水源和水桶浇灌；
- 小麦、胡萝卜、马铃薯多阶段成长；
- 有界离线成长、成熟收获和自动补种；
- 堆肥与成熟保护；
- 鸡、牛、猪繁殖、幼崽成长和持久管理；
- 饲料吸引和持久鸡蛋；
- 多动物同周期产物、出生和成长批量反馈；
- 畜牧与牧场显式生命周期参与者；
- 独立状态白名单和旧世界恢复。

### 7. 地图资源、生态与危险

- 五张地图独立资源档案；
- 保持旧 Seed、hash、salt、深度和概率兼容；
- 五地图动物权重、被动/敌对上限和生成节奏；
- 地图、深度、昼夜、敌对、岩浆和洞穴组成危险分；
- HUD 风险反馈与 125 样本硬预算；
- 同帧昼夜、生态和攻击状态事件合并；
- 同方块环境样本复用；
- 多敌对全局来袭提示；
- 深渊低频重击精英和有用途掉落；
- 种群清理保护真实物理掉落。

### 8. 探矿、日志与地图成长

- 简易探矿仪和五种地图校准仪；
- 固定半径、步长和样本硬预算；
- 深度、密度和主矿物趋势，不返回方块级坐标；
- 最多 64 条持久发现；
- J 键日志、稳定 sequence 和世界内时间；
- 八个探索里程碑；
- profile-aware 地图印记；
- 五种地图材料和原子奖励；
- 错误地图明确拒绝且不进入冷却；
- 领取、制作、扫描、保存和完整重载闭环。

### 9. ServiceHub 生命周期组合化

生产入口继续保留七层继承，当前五个参与者：

```text
ServiceHubFeatureCoordinator
├─ machine_runtime
├─ husbandry_runtime
├─ ranch_runtime
├─ exploration_runtime
└─ exploration_journal_rewards
```

已完成：

- Coordinator 位于 Gameplay 根；
- 唯一参与者 ID 和显式依赖；
- 按顺序规范化、开始、绑定、激活和保存；
- 逆序 clear / shutdown；
- 48 条有界阶段诊断；
- 共享保存 Payload 和角色 Snapshot；
- 公共字段、节点路径和玩家端口兼容；
- 返回菜单、失败启动和退出清理；
- 真实输入、保存、菜单、重载和发行验收。

## 下一阶段重点

### 1. Agriculture 生命周期参与者

农业仍在 Character 继承层中负责反序列化、世界绑定、保存和清理。

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
- 水源、浇灌、肥料和离线成长；
- 作物位置、阶段和计时兼容；
- 不为每株作物创建 Timer。

### 2. 连接型建筑

优先建立邻接与方向纯策略：

```text
门开关与朝向
→ 栅栏连接
→ 梯子攀爬
→ 玻璃板自动连接
```

视觉、碰撞、预览、提交和保存必须使用同一形状合同。

### 3. 长期规模与性能

在继续扩大内容前补充：

- 多机器自动供料、加工、收货和离线恢复压测；
- 机器、畜牧、牧场和危险共享调度预算报告；
- 大量方向/非整块方块区块重建压测；
- 存档体积与加载时间报告；
- 多小时运行 soak；
- 多敌对死亡、掉落和卸载压力。

### 4. CI reusable workflow

专项工作流数量持续增长。提取可复用模板：

```text
strict import
→ static validators
→ domain scripts
→ optional desktop script
→ artifact upload
```

完整 Windows Release 仍保留单一权威工作流。

### 5. 自动化扩展前置条件

在以下数据出现前，不引入管道、电网或跨 Chunk 物流：

- 相邻箱子自动化真实世界使用率；
- 16 台机器周期预算不足的证据；
- 玩家确实需要跨越多方块搬运；
- 路径、拓扑和 Chunk 生命周期的压测方案；
- 存档迁移和故障恢复合同。

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
15. 新分支基于最新 `master`，不得回退并行改动。
