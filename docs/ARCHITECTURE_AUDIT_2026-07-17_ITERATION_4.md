# 全仓架构审计 · 第四轮 · 2026-07-17

## 审计基线

本轮基于：

```text
master@9703a921ba98ff4e8d403842d76b5b8bfacdb5be
```

审查范围覆盖：

- 根目录产品、构建、架构与玩家文档；
- `data` 中物品、方块、资源、生态、危险、农业、牧场和机器合同；
- 世界生成、区块流式、玩家、输入、交互、背包、装备、战斗、农业、牧场、机器、存档和体验层；
- 最新的资源分布、探矿、目录完整性、地图生态与实时危险实现；
- GameUI、功能子类、InputContext 与扩展 Overlay；
- 静态校验、领域回归、真实桌面流程和 Windows Release 门禁；
- 最近主分支提交与当前路线图状态。

审计原则仍为：先保护输入、保存、世界可见性、旧存档和发行包，再推进可被玩家真实使用的功能闭环。

## 总体结论

前三轮迭代已经建立了地图资源档案、粗粒度探矿、地图生态和实时危险度。世界差异不再只停留在地形外观层面。

本轮最明显的缺口是：探索记录虽然已经持久化，却没有成为玩家可访问的产品能力。同时，记录排序和迁移仍存在跨会话语义错误，UI 扩展编号也没有统一合同。这三类问题会在继续增加探索内容和功能面板时快速放大。

## 本轮发现与处置

### P0 · 探索时间使用了错误时钟

#### 问题

探矿记录持久化：

```text
scanned_at_msec = Time.get_ticks_msec()
```

`Time.get_ticks_msec()` 是当前进程启动后的相对毫秒数。退出并重新启动游戏后，不同会话的值没有可比较意义。

如果探索日志直接依赖该字段排序，会出现：

- 新会话记录的数值可能小于旧会话；
- “最新发现”顺序在重启后错误；
- 测试使用人工递增毫秒数时通过，但真实存档行为不可靠。

#### 处置

探索存档升级为 v3，增加：

```text
sequence   世界内稳定发现顺序
world_day  游戏内天数
world_time 游戏内 0–24 小时时间
```

`scanned_at_msec` 只保留为兼容和诊断信息，不再承担跨会话排序。

### P0 · 动态 last_result 可重新注入精确坐标

#### 问题

旧迁移逻辑直接复制：

```gdscript
result["last_result"] = raw_last.duplicate(true)
```

损坏或手工修改的存档可以向运行态重新注入：

```text
positions
ore_positions
coordinates
任意未知字段
```

这绕过了探矿服务“不暴露精确坐标”的产品合同，也让存档尺寸和 UI 数据边界不可控。

#### 处置

v3 对 `last_result` 使用严格白名单：

- 只保留已声明的结果、风险、时间、区块与诊断字段；
- 删除全部未知字段；
- 删除精确坐标数组；
- 文本和危险原因有明确上限；
- 仅允许粗粒度区块坐标 `[chunk_x, chunk_z]`。

### P1 · 重复 record_key 会污染探索计数

#### 问题

旧反序列化会覆盖 `_records[record_key]`，但仍然向 `_record_order` 追加重复 key。

结果可能表现为：

- `record_count` 大于真实唯一记录数；
- 序列化输出重复记录；
- 里程碑被错误提前完成；
- UI 同一区域出现多行。

#### 处置

迁移和运行态均执行相同规则：

```text
同 record_key
→ 删除旧顺序位置
→ 最新记录胜出
→ 移动到队尾
```

重新扫描同一 `chunk + depth band` 会更新原记录，而不是增加新行。

### P1 · 持久探索发现没有玩家入口

#### 问题

探矿记录已经进入存档，但玩家只能看到扫描当下的 Toast。关闭提示后，无法查看：

- 去过哪些区块；
- 哪些区域资源富集；
- 扫描时的危险程度；
- 哪种深度尚未探索；
- 当前探索进度。

这是“已经存了数据，但没有形成产品价值”的典型半闭环。

#### 处置

新增：

```text
ExplorationJournalRegistry
ExplorationJournalPolicy
ExplorationJournalService
ExplorationJournalPanel
```

按 `J` 打开日志，展示：

- 记录总数和不同区块数；
- 最近发现；
- 世界内日期和时间；
- 地图、深度、密度、主矿物趋势与危险原因；
- 七个数据驱动探索里程碑。

日志服务只派生视图，不保存第二份探索状态，避免双写漂移。

### P1 · 扩展 Overlay ID 存在碰撞风险

#### 问题

基础 `GameUI.Overlay` 使用 `0..6`，`RepairGameUI` 在子类中硬编码：

```gdscript
const REPAIR_OVERLAY := 7
```

新增日志面板若直接扩展基础 enum 或再次猜测数字，可能与修理面板发生碰撞，表现为：

- 打开日志却进入修理上下文；
- 错误面板可见；
- Esc/J 无法正确关闭；
- InputContext 与鼠标状态错误。

#### 处置

建立共享合同：

```text
GameUiExtensionOverlayIds
├─ REPAIR = 7
└─ EXPLORATION_JOURNAL = 8
```

静态校验保证扩展 ID 唯一且不占用基础范围。修理面板也迁移到该合同。

### P1 · 路线图已落后于主分支

#### 问题

当前路线图仍把以下能力列为未来工作：

- 深度与危险提示；
- 地图与昼夜生态权重；
- 探索日志与里程碑。

其中前两项已在 PR #31 完成，日志和里程碑在本轮完成。

#### 处置

路线图更新为真实状态，下一阶段转向：

```text
地图特有发现与材料
→ 探索里程碑奖励事务
→ 敌对生物攻击前摇和少量精英变体
→ Machine Base
→ 建筑交互与自动连接
```

### P1 · 测试断言与生产迁移版本漂移

#### 问题

生产 `ProspectingStateMigration.VERSION` 已是 2，但 `prospecting_regression.gd` 仍断言旧世界迁移为版本 1。

这说明：

- 测试本身没有被持续执行到该路径，或断言没有随功能升级维护；
- 仅增加新专项而不重新运行相邻旧领域，会留下错误安全感。

#### 处置

- 原探矿回归更新到 v3；
- 新日志专项强制重新运行探矿回归；
- 全量 `run_all.ps1` 接入日志静态与领域测试；
- PR 继续触发完整 Runtime、真实桌面与 Windows Release。

## 新增架构

```text
ProspectingService
├─ 唯一持久记录状态
├─ sequence / world_day / world_time
├─ v3 白名单序列化
└─ scan_completed
        ↓
ExplorationJournalService
├─ 不持久化
├─ 监听记录变化
└─ 生成只读 snapshot
        ↓
ExplorationJournalPolicy
├─ 最新优先排序
├─ 唯一区块聚合
├─ 深度/密度/危险统计
└─ 数据驱动里程碑
        ↓
ExplorationJournalPanel
├─ J 键入口
├─ CONTEXT_JOURNAL
├─ 1024×576 布局
└─ 不显示精确坐标
```

## 测试与验收

本轮新增：

- `validate_exploration_journal.ps1`；
- `exploration_journal_regression.gd`；
- `exploration_journal_desktop_acceptance.gd`；
- `Exploration journal quality gates`；
- 原探矿回归 v3 更新；
- 完整测试入口接入。

重点验证：

1. v1/v2 → v3 迁移；
2. 重复 key 去重；
3. last_result 白名单；
4. 精确坐标字段清除；
5. 稳定 sequence 与世界时间；
6. 同区域刷新不增加记录；
7. 七个里程碑；
8. 修理/日志 Overlay ID 不冲突；
9. 真实 J 键；
10. 输入与鼠标隔离；
11. 1024×576 布局；
12. 保存、返回菜单和完整世界重载；
13. Windows Release 实际导出与启动。

## 后续优化建议

### 1. 探索奖励事务

里程碑当前只读，不直接发放奖励。下一轮应新增独立事务服务：

```text
首次里程碑完成
→ 检查已领取状态
→ 原子发放奖励
→ 背包满时保留待领取
→ 持久化领取状态
```

不能让日志 UI 直接写背包。

### 2. 地图特有材料

优先增加少量真正改变制作路线的地图材料，而不是仅提高现有矿石数量。新方块 ID 必须继续只追加，并接入目录完整性、资源档案、探矿、掉落和存档门禁。

### 3. ServiceHub 继承链

当前功能通过多层 `*_progression_service_hub.gd` 继承叠加。短期仍可维护，但继续增加系统会让初始化顺序和 super 调用变脆弱。

建议逐步转为：

```text
ServiceHub
→ FeatureInstaller 数组
→ 每个 Installer 注册服务、端口、保存贡献与清理贡献
```

不得一次性重写所有成熟领域。

### 4. Reusable CI

专项工作流继续增长，重复执行 Godot 安装、项目导入和同类前置步骤。建议在下一轮提取 reusable workflow，同时保留每个专项的可读名称和证据 artifact。

### 5. UI 扩展注册

Overlay ID 已统一，下一步可以进一步建立小型 UI 扩展注册表，让面板负责：

```text
overlay_id
input_context
show/hide
close cleanup
```

避免基础 `GameUI` 的 `_set_overlay` 继续增加功能专用分支。
