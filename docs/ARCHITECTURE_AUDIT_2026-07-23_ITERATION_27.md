# Architecture Audit · 2026-07-23 · Iteration 27

## 范围

本轮从 `master@4f37ec929b3467be1aeb75bfd3ac137cb428930c` 审计：

- `ItemPickup` 的视觉、碰撞、寿命和拾取；
- `PickupStackCoordinator` 的 128 节点上限与事件驱动堆叠；
- `CreatureSpawner` 子节点生命周期；
- `SimulationPauseService`；
- Exploration Runtime Participant；
- 物理掉落、混合运行和 Windows Release 门禁。

上一轮已经解决了高频死亡导致物理掉落节点无界增长的问题：

```text
自然散落阈值 8
物理节点上限 128
候选扫描上限 64
Pending 保留准确数量
```

本轮继续审计“已经被限制的 128 个节点在持续运行时仍付出什么成本”。

## 结论

节点数量已经有界，但每个 `ItemPickup` 仍拥有自己的 `_process`：

```text
rotation.y += delta * 2.2
position.y += sin(...) * delta * 0.12
life_seconds -= delta
```

在最坏情况下，生产世界同时存在 128 个独立回调。更重要的是，浮动动画直接改变 `Area3D` 的位置，使碰撞球、拾取范围和堆叠距离跟着展示动画移动。

此外每个节点重复创建：

```text
BoxMesh
SphereShape3D
StandardMaterial3D
```

同一种物品的 128 个掉落会创建大量相同资源。

## 发现 1：节点有界，但 `_process` 回调仍按节点增长

当前上限为 128，因此不会无限增长，但运行成本仍是：

```text
N 个掉落
→ N 个 SceneTree Process 分发
→ N 次脚本回调
```

该成本与已经存在的合并协调器重复，因为协调器已经拥有完整的掉落成员事件。

### 修复

将动画与寿命推进迁移到 `PickupStackCoordinator`：

```text
child_entered_tree
→ 注册掉落
→ configure_shared_runtime
→ ItemPickup.set_process(false)

一个 Coordinator _process
→ 最多推进 128 个已注册节点
```

协调器只有在：

```text
active
且
存在真实掉落节点
```

时才启用 Process。

## 发现 2：浮动展示移动了物理锚点

旧实现直接累计：

```gdscript
position.y += sin(Time.get_ticks_msec() * 0.004) * delta * 0.12
```

问题：

- `Area3D` 碰撞球会随视觉上下移动；
- 玩家拾取距离会轻微波动；
- 合并半径使用的世界位置包含展示偏移；
- 长时累计依赖帧率和浮点误差；
- 无法分别测试“视觉在动”和“物理位置稳定”。

### 修复

新增：

```text
ItemPickup
├─ PickupCollision
└─ PickupVisual
   ├─ PickupMesh
   └─ StackCount
```

共享运行时只更新：

```text
PickupVisual.position.y
PickupVisual.rotation.y
```

`ItemPickup.position` 和 `global_position` 始终是稳定碰撞锚点。

## 发现 3：Pause 语义继承自 Always 根层

`GameplayServiceHub` 使用 `PROCESS_MODE_ALWAYS`，以保证暂停菜单和 UI 能继续工作。旧掉落作为其后代，没有显式覆盖 Process Mode。

结果是 Pause 时可能继续：

- 旋转；
- 浮动；
- 减少 180 秒寿命；
- 最终在暂停菜单中消失。

### 修复

协调器和独立后备掉落都显式设置：

```text
PROCESS_MODE_PAUSABLE
```

真实 `SimulationPauseService.set_paused(true)` 会冻结视觉与寿命，恢复后从原状态继续。

## 发现 4：每个节点重复分配相同资源

旧 `_ready()` 每次创建：

```text
BoxMesh 0.3 × 0.3 × 0.3
SphereShape3D radius 0.32
StandardMaterial3D by item color
```

Mesh 和 Shape 完全相同，同色物品的 Material 也相同。

### 修复

新增 `PickupVisualResourceCache`：

| 资源 | 策略 |
|---|---|
| BoxMesh | 全进程共享一个 |
| SphereShape3D | 全进程共享一个 |
| Material | 按颜色共享 |
| 材质缓存 | 最多 256 项 |

超过 256 种颜色时使用未缓存材质，而不是拒绝掉落。

## 发现 5：共享运行时必须保持事件维护

错误方案：

```text
每帧 spawner.get_children()
→ 筛选 pickups
→ 排序
→ 推进
```

这会让优化重新引入全量目录扫描。

### 修复

继续复用：

```text
child_entered_tree
child_exiting_tree
```

维护 `Array[Node]` 成员。每帧只遍历已经验证的、最多 128 个运行节点。

## 发现 6：共享 Delta 需要上限

窗口恢复、断点或异常帧可能传入较大 `delta`。如果直接扣除寿命，会让掉落在单帧中过度老化。

### 修复

```text
MAX_RUNTIME_DELTA_SECONDS = 0.25
```

单次共享推进最多扣除四分之一秒。正常帧不受影响。

## 生产结构

```text
PickupAwareExplorationRuntimeParticipant
└─ BoundedPickupStackCoordinator
   ├─ pressure-aware merging
   ├─ no-loss pending materialization
   ├─ event-maintained runtime directory
   ├─ one pausable process
   └─ PickupVisualResourceCache

ItemPickup
├─ compatibility fallback process
├─ shared runtime disable port
├─ stable Area3D anchor
└─ visual-only child animation
```

独立后备 `_process` 只用于没有生产 Coordinator 的薄场景；生产节点接管后全部 `set_process(false)`。

## 硬预算

| 项目 | 上限 |
|---|---:|
| 物理掉落节点 | 128 |
| 单次运行推进节点 | 128 |
| 单次 Delta | 0.25 秒 |
| 自然散落阈值 | 8 |
| 合并扫描 | 64 |
| Pending 类型 | 256 |
| 单次物化 | 16 |
| 单堆数量 | 65,535 |
| 材质缓存 | 256 |
| 新 Timer | 0 |
| 新持久字段 | 0 |

## 存档边界

继续不保存：

```text
pickup_runtime
tracked pickup nodes
runtime elapsed
visual phase
visual resource cache
remaining lifetime
pending pickups
world-space count labels
```

玩家已经拾取的物品仍由 Inventory 保存。

## 验收

### 静态合同

- 生产一个共享 `_process`；
- `PROCESS_MODE_PAUSABLE`；
- 128 节点和 0.25 秒 Delta；
- ItemPickup 可禁用独立 Process；
- 动画只修改 `PickupVisual`；
- 禁止 `position.y +=`；
- Mesh/Shape/Material 共享；
- 材质缓存上限 256；
- 无 Timer、文件或序列化。

### 领域测试

- 两节点一次共享推进；
- 碰撞锚点零漂移；
- 视觉根在 0.12 米振幅内；
- 同色节点资源 ID 一致；
- SceneTree Pause 冻结；
- 恢复后继续；
- 128 节点零独立 Process；
- 大 Delta 限制；
- 128 个过期节点精确清理。

### 真实桌面与可视化

- 生产世界 128 个真实 `Area3D`；
- 256 件可见物品；
- 一套共享 Mesh、Shape 和 Material；
- 实际 Simulation Pause；
- 1024×576 截图；
- JSON 基准报告；
- 正式保存、菜单和完整重载；
- 新世界无旧掉落和运行统计；
- 完整 Runtime、桌面矩阵和 Windows Release。

## 后续

下一阶段应优先处理 CI 结构重复：

```text
strict import
→ static validators
→ domain scripts
→ optional desktop acceptance
→ artifact upload
```

在不削弱单一权威 Windows Release 的前提下提取 reusable workflow。只有新的真实运行报告证明 128 节点共享循环仍占主导，才考虑 MultiMesh 或更复杂的展示批处理。
