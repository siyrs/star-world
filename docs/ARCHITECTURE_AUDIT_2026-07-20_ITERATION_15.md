# 全仓架构审计 · 2026-07-20 · 第十五轮

## 范围

本轮从 `master@8c098ad0853c0cf416437ae6cac5606cd9150ff1` 开始，重点审查：

- Machine Base 的第二领域扩展能力；
- Furnace 与世界机器交互的耦合；
- 机器 UI、输入上下文和 Overlay 扩展；
- 方块、物品、配方、视觉、采集和存档目录；
- 跨领域调度、反馈和诊断；
- 真实桌面、全量 Runtime 和 Windows Release 门禁。

审计原则：先证明共享基础能承载第二个真实领域，再考虑电网、物流或大型自动化。

## 总体结论

第十四轮 Machine Base 已经建立了共享调度、生命周期、状态迁移和完成反馈，但外围交互仍然把“机器”等同于 Furnace。如果直接增加新机器，团队仍会在 BlockInteraction、UI 和拆除保护处复制 Furnace 分支。

本轮以石材切割机作为第一种非 Furnace 机器，同时把外围交互改成可注册合同。目标不是增加一个孤立内容，而是验证：

```text
第二个机器领域
→ 不复制 Furnace Process
→ 不创建独立 Timer
→ 不独立写文件
→ 不修改旧机器存档路径
→ 不在 BlockInteraction 增加新硬编码槽位
```

## 本轮发现与处置

### P1 · 机器交互仍是 Furnace 专用

#### 现状

`BlockInteractionService` 的机器路径直接持有 FurnaceService，并假设所有机器都有：

```text
input
fuel
output
```

#### 风险

- 无燃料机器仍被迫伪造 fuel 槽；
- 每种新机器需要新的 `if/elif`；
- 打开、拆除保护和删除逻辑分散；
- 世界位置 ID 可能使用不同前缀规则；
- Machine Base 只覆盖计时，没有覆盖玩家入口。

#### 处置

新增 `MachineInteractionRouter`：

```text
machine_type
→ service
→ UI port
→ slot contract
→ removal message
```

生产 BlockInteraction 只解析机器类型和稳定位置 ID，具体机器规则由路由与领域服务处理。保留直接注入 Furnace 的兼容入口。

### P1 · Machine Base 尚未经过第二领域验证

#### 现状

共享 Scheduler 只有 Furnace 一个生产 Domain。

#### 风险

一个领域通过测试，只能证明抽象没有破坏 Furnace，不能证明它适合新机器。

#### 处置

新增 StonecutterService，并与 Furnace 同时注册到同一个 Scheduler。真实验收要求一个 Batch 同时完成：

```text
Furnace       → 铁锭 ×1
Stonecutter   → 石台阶 ×4
```

同时只允许一条玩家摘要和一次音效。

### P1 · 机器存档白名单只有 Furnace

#### 现状

MachineStateMigration 只规范化 `furnaces`。

#### 风险

新领域若在参与者中自行拼接和校验，会重新产生多套迁移策略。

#### 处置

保持 `machines.version = 1`，增加可选 `stonecutters` 白名单：

```json
{
  "version": 1,
  "saved_at_unix": 0,
  "furnaces": {},
  "stonecutters": {}
}
```

全局机器实例上限仍为 4096，旧世界缺少字段时补为空对象。

### P1 · UI 扩展 ID 需要统一治理

#### 现状

Repair 和 Exploration 已使用扩展 Overlay ID，但新机器 UI 若自行选择数字，可能冲突。

#### 处置

Stonecutter 使用共享目录中的 ID 9：

```text
Repair               7
Exploration Journal  8
Stonecutter           9
```

真实桌面验证打开、关闭、输入阻断、鼠标释放和恢复。

### P1 · 新方块必须进入完整目录

#### 现状

新增机器方块不仅需要 BlockRegistry 和 ItemRegistry，还必须进入：

```text
Crafting
Interaction
Harvest
Visual
Persistence
```

首轮视觉门禁正确发现 Stonecutter 没有权威视觉 Profile。

#### 处置

- 方块 ID 只追加；
- 物品和工作台配方完整；
- 镐类采集规则；
- 复用 `repair_station` 的已验证工业视觉；
- 静态合同检查视觉继承和 numeric ID 顺序。

### P1 · 动态边界需要显式类型收窄

真实桌面首轮还发现：

1. 子类 UI 常量与父类同名，严格解析失败；
2. 动态 `call()` 返回的机器 ID 缺少显式 String 收窄；
3. 动态调用的 `Array` 不能直接满足 `Array[String]` 参数。

处置：

- 常量更名，避免继承命名冲突；
- 测试和生产动态边界显式 `str()` / 类型声明；
- Router 接受普通 Array，并逐项规范化为 `Array[String]`。

这些规则已经沉淀进真实桌面和静态合同。

## 玩家功能推进

### 石材切割机

工作台制作：

```text
圆石 ×6
铁锭 ×2
```

加工：

| 输入 | 输出 | 时间 |
|---|---|---:|
| 圆石 | 石砖 | 3.0 秒 |
| 石头 | 石台阶 ×2 | 2.5 秒 |
| 石砖 | 石台阶 ×2 | 2.0 秒 |

玩家可见：

- 无燃料说明；
- 当前配方；
- 加工进度；
- 队列任务数；
- 下一份剩余时间；
- 整批 ETA；
- 原料和产出槽；
- 非空拆除提示。

### 跨机器完成反馈

Furnace 与 Stonecutter 同帧完成时：

```text
领域完成事件逐项保留
→ 帧末一次汇总
→ 一条机器加工完成消息
→ 一次 craft 音效
```

诊断新增机器类型集合和类型数量，避免跨领域 Batch 只知道“有两台机器”却不知道属于哪些领域。

## 兼容性

保持：

- 七层 ServiceHub 入口；
- `machine_runtime` 生命周期参与者 ID；
- `/Services/FurnaceService`；
- Furnace UI 和直接实例化模式；
- `machines.version = 1`；
- `machines.furnaces`；
- 四小时离线推进；
- 512 次单次模拟迭代；
- 所有旧方块 numeric ID；
- 原世界、玩家、探索、畜牧和生态 Schema。

新增：

- `/Services/StonecutterService`；
- `/Services/MachineInteractionRouter`；
- 可选 `machines.stonecutters`；
- Stonecutter Overlay 9。

## 测试门禁

### 静态

```text
validate_data.ps1
validate_catalog_integrity.ps1
validate_machine_base.ps1
validate_stonecutter_machine.ps1
validate_block_visuals.ps1
```

### 领域

```text
stonecutter_machine_regression.gd
machine_base_regression.gd
block_interaction_regression.gd
furnace_machine_regression.gd
```

### 真实桌面

```text
放置后的真实右键
→ Stonecutter Overlay
→ 鼠标投入石材
→ Furnace + Stonecutter 同批完成
→ 一条反馈 / 一次音效
→ 非空拆除保护
→ 真实取回产出
→ 保存 / 菜单 / 完整重载
```

### 最终发行

仍要求：

```text
全部专项
→ 全量 Runtime
→ 完整真实桌面矩阵
→ Windows Release 实际导出并启动
→ 才允许进入 master
```

## 后续优化点

### P1 · 机器能力端口

下一阶段应增加小型能力查询，而不是立即建立物流网络：

```text
can_insert(slot, item)
can_extract(slot)
get_machine_capabilities()
```

先让自动输入/输出只依赖槽位能力，不依赖 Furnace 或 Stonecutter 类型。

### P1 · Agriculture 生命周期参与者

农业仍在 Character Hub 继承层中拥有反序列化、世界绑定、保存和清理。应迁移为独立 `agriculture_runtime`，同时保持作物、土壤和肥料 Schema。

### P2 · 连接型建筑

门、栅栏、梯子和玻璃板仍需要统一邻接与方向合同，避免视觉、碰撞、预览和保存分别实现连接规则。

### P2 · CI 组合化

专项工作流数量继续增长。应提取 reusable workflow，复用：

```text
strict import
→ static validator
→ domain scripts
→ optional desktop script
→ artifact upload
```

完整 Windows Release 继续保留单一权威门禁。
