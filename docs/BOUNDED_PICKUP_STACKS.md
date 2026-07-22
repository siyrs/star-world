# 有界物理掉落堆叠合同

## 目标

保留敌对和生物死亡后可见、可碰撞、可拾取的真实世界掉落，同时防止高频战斗在三分钟掉落寿命窗口内持续创建 `Area3D`、碰撞监测器、Mesh 和材质。

本系统不把掉落变成瞬时背包奖励，也不删除超预算物品。它只在物理节点压力出现时合并同类掉落，并为超过节点预算的物品保留有界待物化数量。

## 玩家规则

- 少量掉落继续散落在地面，前八个物理节点不会为了优化而立即合并；
- 第九个及之后的附近同类掉落会合并到已有堆；
- 合并堆在世界中显示 `×N` 数量；
- 玩家触碰后仍使用现有背包收取逻辑，背包不足时剩余数量继续留在同一个物理堆；
- 不同物品不会互相合并；
- 超过合并半径的物品保持独立；
- 返回菜单或进入新世界时，旧世界掉落和待物化数量全部清理。

## 生产结构

```text
Creature / hostile death
→ ItemPickup
→ CreatureSpawner child event
→ BoundedPickupStackCoordinator
   ├─ small-drop readability threshold
   ├─ nearby same-item merge
   ├─ hard physical-node budget
   ├─ exact pending item totals
   └─ bounded diagnostics
```

`ItemPickup` 继续是生产 `Area3D`，保留碰撞和自动拾取；新增的只是可合并数量合同和世界空间计数标签。

## 硬预算

| 项目 | 上限 |
|---|---:|
| 小规模自然散落阈值 | 8 个节点 |
| 活动物理掉落节点 | 128 |
| 单次合并扫描节点 | 64 |
| 待物化物品类型 | 256 |
| 单次 Flush 物化类型 | 16 |
| 单个物理掉落数量 | 65,535 |
| 合并半径 | 1.75 米 |
| 新 Timer | 0 |
| 新逐帧 Scheduler | 0 |

当节点已经达到 128 时，新掉落先进入当前会话内的待物化计数。任一物理节点离开后，协调器按稳定物品 ID 顺序，每次最多物化 16 种物品。物品数量不会因为节点预算被丢弃。

## 一致性合同

### 合并

```text
source count
→ candidate.merge_items(source count)
→ candidate 增加实际接收数量
→ source 只减少同样数量
→ source 为零时才释放节点
```

每个候选堆最多持有 65,535 件。超过该上限的剩余数量继续寻找其他候选或保留在源堆。

### 背包部分接收

原有收取合同保持：

```text
物理堆 64
背包只能接收 20
→ 背包增加 20
→ 同一物理堆保留 44
```

计数标签同步更新为 `×44`。

### 节点预算

```text
第 129 个物理节点进入
→ 尝试有界邻近合并
→ 仍不能合并则把精确数量写入 pending
→ 释放临时节点
→ 有容量后重新物化
```

待物化状态只负责当前会话内的资源压力，不拥有世界事实。真正的世界存档仍由背包、容器、机器、农业和稀疏方块领域负责。

## 生命周期

协调器由生产 `ExplorationProgressionServiceHub` 组合，绑定既有 `CreatureSpawner`：

- `_begin_world`：清空旧计数和待物化物品；
- `activate_gameplay`：开始接受新掉落事件；
- `return_to_menu`：先停用并清空，再执行完整世界清理；
- `world_start_failed`：清理所有瞬时状态；
- `_exit_tree`：断开 Spawner 信号并 Shutdown。

运行快照通过：

```text
character_snapshot.pickups
```

暴露节点数、堆叠节点数、可见/待物化总数、合并数、预算延迟数和硬上限。

## 存档边界

以下内容**不进入存档**：

```text
pickup_stack
pending_pickups
merge_count
merged_item_count
pickup node positions
pickup lifetime
count label state
```

物理掉落本来就是当前会话的瞬时奖励表现；只有成功进入玩家背包后才随背包保存。返回菜单前未拾取的物理掉落继续按既有产品语义清理。

## 测试

### 领域回归

`tests/qa/pickup_stack_regression.gd` 验证：

- 同类精确合并和数量标签；
- 100 个附近掉落压缩到不超过 8 个节点；
- 可见物品总数仍为 100；
- 第 129 个不同物品在节点预算处延迟；
- 释放一个节点后延迟物品重新物化；
- 可见加待物化总数始终精确。

### 真实混合桌面

`tests/qa/mixed_runtime_endurance_desktop_acceptance.gd` 同时运行：

- 连接玻璃板和栅栏；
- 16 台机器与相邻箱子自动化；
- 64 株混合作物成长；
- 64 个真实敌对死亡掉落；
- Chunk 卸载与快照热返回；
- 正式保存、加载、菜单和完整重载。

验收输出 1024×576 截图、JSON 报告和 stdout/stderr，并确认所有 64 个掉落在堆叠和拾取后仍精确存在。
