# 探索日志与里程碑合同

## 目标

地图资源、实时危险和简易探矿已经能够产生持久发现，但玩家此前无法在游戏中重新阅读这些记录。本系统把现有探矿记录转换为可访问、可排序、可迁移的探索日志，同时保持“粗粒度趋势，不提供精确透视坐标”的产品边界。

```text
ProspectingService（唯一持久事实源）
→ ExplorationJournalService（派生只读模型）
→ ExplorationJournalPolicy（聚合与里程碑）
→ ExplorationJournalPanel（J 键玩家界面）
```

日志服务不保存第二份记录，不直接修改探矿状态，也不负责世界扫描。

## 持久状态 v3

`ProspectingStateMigration.VERSION = 3`。

每条记录包含：

```text
record_key
chunk
profile_id
depth_band_id / depth_label
density_id / density_label
ore_ratio
dominant_block_id / dominant_label
danger_tier_id / danger_label / danger_score / danger_reasons
sequence
world_day
world_time
scanned_at_msec（仅兼容与诊断，不用于跨会话排序）
```

### 稳定顺序

旧实现把 `Time.get_ticks_msec()` 写入存档。该值是当前进程启动后的相对时间，重启游戏后没有跨会话比较意义。

v3 使用：

- `sequence`：当前世界内的稳定发现顺序；
- `world_day`：游戏内天数；
- `world_time`：游戏内 0–24 小时时间。

重新扫描相同 `chunk + depth band` 时：

1. 不增加记录总数；
2. 更新原记录；
3. 分配新的 sequence；
4. 移动到最新记录位置。

保存或载入时可以压缩 sequence 的空洞，但相对顺序必须保持不变。

## 迁移与安全

### 重复记录

迁移按输入顺序读取记录。相同 `record_key` 多次出现时，只保留最后一个，并把它移动到最新位置。

这可以防止损坏或手工编辑的旧存档造成：

- 日志行数虚高；
- 同一区域重复显示；
- 序列化后重复记录继续扩散。

### last_result 白名单

旧实现会直接复制存档中的整个 `last_result` Dictionary。恶意或损坏存档可以重新注入：

```text
positions
ore_positions
coordinates
任意动态字段
```

v3 只保留明确白名单字段。精确坐标数组、未知字段和超长文本全部被丢弃。

允许保留的空间信息只有粗粒度 `chunk = [x, z]`。

### 边界

- 危险原因最多 6 条；
- 消息最大 320 字符；
- 世界时间规范化到 `0 <= time < 24`；
- 世界天数至少为 1；
- 探矿记录总量继续由 `max_records = 64` 限制；
- 日志面板默认只显示最近 24 条。

## 日志派生模型

`ExplorationJournalService` 连接 `ProspectingService.scan_completed`，每次扫描后重新生成只读 snapshot。

snapshot 包含：

```text
record_count
unique_chunk_count
depth_band_count
rich_count
highest_danger_score
latest_sequence
completed_milestone_count
milestone_count
milestones
records（最近、倒序、受显示预算限制）
has_more_records
```

该服务没有自己的 serialize/deserialize，因为所有数据都能从探矿记录确定性重建。

## 数据驱动里程碑

生产配置位于：

```text
data/exploration_journal.json
```

当前里程碑：

| ID | 条件 |
|---|---|
| `first_discovery` | 保存 1 条发现 |
| `three_regions` | 记录 3 个不同区块 |
| `deep_delver` | 记录深层发现 |
| `rich_signal` | 记录富集区域 |
| `danger_scout` | 在危险或极高区域勘探 |
| `four_depths` | 覆盖四种深度层 |
| `seasoned_explorer` | 保存 12 条发现 |

里程碑只读取记录，不发放物品，不修改世界。后续若增加奖励，应由独立事务服务消费“首次完成”事件，不能让 UI 直接发放物品。

## 玩家界面

按 `J` 打开探索日志。

界面显示：

- 总记录数、不同区块数、里程碑进度和最高危险；
- 每个里程碑的完成状态和进度；
- 最近发现的世界日期、地图、区块、深度、资源密度、主矿物信号和危险原因。

界面不显示：

- 方块级坐标；
- 矿物坐标列表；
- 环境危险坐标；
- 从玩家到目标的路径。

日志 Overlay：

- 使用独立 `CONTEXT_JOURNAL`；
- 打开时禁用玩家移动、攻击、采集、探矿和放置；
- 鼠标变为可见；
- 不暂停世界模拟；
- 再按 J 或 Esc 关闭并恢复 gameplay context。

## 扩展 Overlay ID

基础 `GameUI.Overlay` 占用 `0..6`。功能子类此前直接硬编码修理面板为 `7`，继续添加功能会产生碰撞。

扩展 ID 现在统一位于：

```text
GameUiExtensionOverlayIds
├─ REPAIR = 7
└─ EXPLORATION_JOURNAL = 8
```

新增功能面板必须在该合同中分配唯一 ID，并通过静态门禁验证，不得在子类里自行猜测下一个数字。

## 测试门禁

### 静态合同

`validate_exploration_journal.ps1` 验证：

- schema 与显示预算；
- 里程碑 ID、类型、阈值和必需集合；
- 修理/日志 Overlay ID 唯一且位于扩展范围；
- J 键输入合同；
- 探索迁移版本为 3。

### 领域回归

`exploration_journal_regression.gd` 覆盖：

- v1/v2 数据迁移至 v3；
- 重复 key 最新项胜出；
- sequence 与世界时间；
- last_result 白名单和坐标字段清除；
- 同区块刷新不重复；
- 保存、载入和下一 sequence；
- 七个生产里程碑；
- 最新优先排序；
- 生产 ServiceHub、RepairGameUI、输入上下文和 1024×576 布局。

### 真实桌面

`exploration_journal_desktop_acceptance.gd` 使用生产：

```text
GameScene
VoxelWorld
ExplorationPlayer
ProspectingService
ExplorationJournalService
RepairGameUI
InputContextService
SaveService
```

真实验证：

1. 右键探矿；
2. 多区块记录与同区块刷新；
3. 真实 J 键打开日志；
4. 鼠标和玩家输入隔离；
5. 里程碑与最新优先顺序；
6. 1024×576 布局；
7. 正式保存；
8. 返回菜单；
9. 完整世界重载；
10. 日志记录和顺序恢复；
11. 截图与日志证据。
