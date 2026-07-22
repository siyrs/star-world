# Architecture Audit · 2026-07-22 · Iteration 26

## 范围

本轮从最新 `master` 审计：

- `BaseCreature.die()` 与真实世界掉落生成；
- `ItemPickup` 的节点、碰撞、材质、寿命和背包收取；
- `CreatureSpawner` 的种群清理与世界生命周期；
- 多敌对死亡和物理掉落验收；
- 机器、农业、连接结构和最近 Chunk 缓存的规模测试；
- 现有 `runtime_soak_regression.gd`；
- ServiceHub Snapshot、保存边界和 Windows Release 门禁。

前几轮已经分别证明：

```text
2,048 株作物
512 台机器
3,000+ 连接结构修改
三轮 Chunk 卸载和热返回
```

可以在硬预算内运行。尚未闭环的是这些领域与连续敌对死亡、物理掉落同时存在时的节点和碰撞压力。

## 结论

当前生物死亡对每一种掉落创建一个独立 `ItemPickup Area3D`。每个节点拥有：

```text
Area3D
CollisionShape3D
SphereShape3D
MeshInstance3D
BoxMesh
StandardMaterial3D
_process
```

单个掉落寿命为 180 秒。高频战斗中，即使附近全部掉落都是同一个物品，节点数量仍随死亡次数增长。

## 发现 1：同类掉落没有物理堆叠合同

原流程：

```text
Creature death
→ roll drops
→ 每个 item_id 创建一个 ItemPickup
→ add_child 到 CreatureSpawner
```

64 个僵尸在短时间内各掉落一块腐肉，会形成 64 个 Area3D。继续战斗时，三分钟窗口内可以积累更多碰撞监测和材质实例。

### 修复

`ItemPickup` 增加精确堆叠端口：

```text
can_merge(item_id)
merge_items(count)
get_pickup_snapshot()
```

同类堆叠保留准确数量，超过单节点 65,535 的部分不会被吞掉。

## 发现 2：无条件合并会破坏少量掉落的可读性

玩家击败三只敌人时，三个散落的小方块比瞬间收缩成一堆更容易理解掉落来源。

### 修复

使用压力阈值：

```text
物理节点 ≤ 8
→ 保持自然散落

物理节点 > 8
→ 在 1.75 米范围内合并同类物品
```

只有资源压力出现时才合并，不为微小场景牺牲视觉反馈。

## 发现 3：只做邻近合并仍然没有最坏情况边界

以下情况无法通过邻近同类合并解决：

- 128 种不同物品；
- 相同物品分散在很远的位置；
- 单个堆已经达到 65,535；
- 大量脚本或未来玩法同步产生不同奖励。

### 修复

建立硬节点预算：

| 项目 | 上限 |
|---|---:|
| 活动物理掉落节点 | 128 |
| 单次候选扫描 | 64 |
| 待物化物品类型 | 256 |
| 单次物化类型 | 16 |
| 单节点物品数量 | 65,535 |

第 129 个节点如果无法合并，会把准确物品数量放入当前世界会话的待物化队列，然后释放临时节点。节点释放后，协调器按稳定物品 ID 顺序重新物化。

## 发现 4：节点限制不能以删除物品为代价

错误方案：

```text
if pickup_count >= 128:
    queue_free(new_pickup)
```

这会在压力最大时直接吞掉玩家奖励。

### 修复

业务数量与表现节点分离：

```text
visible_item_total
+
pending_item_total
=
全部未拾取物品
```

任何时候都可以通过运行 Snapshot 验证数量守恒。待物化队列有 256 种物品的明确边界；到达类型边界时，新物品继续保留原物理节点，而不是丢弃。

## 发现 5：堆叠后玩家无法知道数量

旧掉落只显示一个 0.3 米方块。把 64 件合并成一个节点但仍显示相同方块，会隐藏奖励规模。

### 修复

合并堆增加世界空间 `Label3D`：

```text
×64
```

标签使用 Billboard、固定屏幕尺寸、描边和深度穿透，只有数量大于一时显示。背包部分接收后标签同步更新剩余数量。

## 发现 6：协调器不能成为第二个逐帧系统

每帧扫描所有掉落会让优化本身随节点数量增长。

### 修复

协调器只监听现有 Spawner 的：

```text
child_entered_tree
child_exiting_tree
```

新掉落进入时才执行最多 64 个候选检查；节点离开时才尝试物化待处理物品。

没有：

- Timer；
- `_process`；
- 额外 Scheduler；
- 全世界扫描；
- Chunk 扫描。

## 发现 7：原 soak 不包含真实高成本领域组合

原 `runtime_soak_regression.gd` 主要验证三次世界开始、短距离移动、Streaming 队列和菜单节点清理。它不会同时创建：

- 机器及自动化；
- 成熟农田；
- 连接建筑；
- 多敌对死亡；
- 大量物理掉落；
- Chunk 卸载/热返回。

### 修复

新增真实混合桌面验收：

```text
连接结构
+
16 台机器
+
64 株作物
+
64 次敌对死亡
+
物理掉落堆叠与拾取
+
Chunk 卸载和热返回
+
保存、菜单和完整重载
```

该测试不是替代现有长期 soak，而是补充一个高信号、可视化的跨领域组合基线。

## 生产结构

```text
ExplorationProgressionServiceHub
├─ CreatureSpawner
├─ BoundedPickupStackCoordinator
├─ ExplorationRuntimeParticipant
└─ JournalRewardParticipant
```

协调器位于现有生物和探索表现层，不进入 Machine、Agriculture 或 World 状态所有者。

## 生命周期

```text
_begin_world
→ 清除旧 pending 和统计

activate_gameplay
→ 接受新掉落事件

return_to_menu / world_start_failed
→ 停用并清除

_exit_tree
→ 断开信号并 shutdown
```

完整世界清理仍由 `CreatureSpawner.clear_creatures()` 删除旧生物和物理掉落。

## 存档边界

物理掉落和待物化数量沿用既有“当前世界会话瞬时奖励”语义，不进入 JSON。

明确不保存：

```text
pickup_stack
pending_pickups
merged_item_count
pickup node positions
pickup lifetime
count labels
```

玩家已经拾取的物品继续通过 Inventory 保存。

## 验收要求

### 静态合同

- 小规模阈值固定 8；
- 物理节点固定 128；
- 合并扫描固定 64；
- 待物化类型固定 256；
- 单次物化固定 16；
- 单堆固定 65,535；
- 无 Timer、无 `_process`、无 serialize、无 FileAccess；
- 生产 ServiceHub 组合和 Snapshot 完整。

### 领域回归

- 精确合并和 `×N` 标签；
- 100 个同类掉落压缩到不超过 8 个节点；
- 100 件物品总数不变；
- 第 129 个不同物品延迟；
- 节点释放后重新物化；
- 可见和待物化数量守恒。

### 真实桌面与可视化

- 600+ 世界修改；
- 16 台机器完成和收货；
- 64 株作物成熟；
- 64 个真实僵尸死亡掉落；
- 掉落节点有界且数量精确；
- 世界空间堆叠数量可见；
- 全部物品真实拾取；
- 多 Chunk 卸载和热返回；
- 保存、JSON 加载、菜单清理和完整重载；
- 1024×576 截图与 JSON 报告；
- Windows Release 实际导出和启动。

## 后续

完成后优先提取重复的专项工作流为 reusable workflow：

```text
strict import
→ static validator
→ domain scripts
→ optional desktop test
→ artifact upload
```

随后再建立更长时间的发布前组合 soak。若真实报告显示掉落节点已不再是主要成本，再根据证据审计生物物理更新、Mesh 构建或容器事务，而不是继续增加无证据的缓存层。
