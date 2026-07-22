# Shared Pickup Runtime

## 目标

真实世界掉落继续保持：

- 可见；
- 可碰撞拾取；
- 支持同类堆叠；
- 支持世界空间数量标签；
- 180 秒后自然消失；
- Pause 时冻结；
- 返回菜单和切换世界时完整清理。

同时避免最多 128 个 `ItemPickup` 各自运行 `_process`，并避免浮动动画直接改变 `Area3D` 的碰撞锚点。

## 生产结构

```text
PickupAwareExplorationRuntimeParticipant
└─ BoundedPickupStackCoordinator
   ├─ event-maintained pickup membership
   ├─ one PROCESS_MODE_PAUSABLE runtime loop
   ├─ pressure-aware stack consolidation
   ├─ pending no-loss materialization
   └─ bounded runtime diagnostics

ItemPickup
├─ stable Area3D collision anchor
├─ PickupVisual child
│  ├─ shared BoxMesh
│  ├─ shared color material
│  └─ Label3D ×N
└─ shared-runtime port
```

## 单一运行循环

生产协调器拥有唯一的：

```gdscript
func _process(delta: float) -> void:
    advance_shared_runtime(delta)
```

每个生产 `ItemPickup` 在进入协调器后执行：

```gdscript
configure_shared_runtime(phase)
→ set_process(false)
```

因此最大压力下：

```text
128 个物理掉落节点
→ 1 个共享 Process 回调
→ 0 个生产掉落独立 Process 回调
```

独立测试或未来不经过生产 Spawner 的薄场景仍保留一个兼容后备：未被共享运行时接管的 `ItemPickup` 可以自行推进。后备和生产运行时都显式使用 `PROCESS_MODE_PAUSABLE`。

## 碰撞锚点稳定

旧视觉动画直接执行：

```gdscript
position.y += sin(...) * delta
```

这会让：

- 拾取球体上下移动；
- 合并距离基于不断变化的节点位置；
- 长时间数值累计影响锚点；
- 视觉效果和物理语义耦合。

现在 `ItemPickup` 保持自身位置不变，只更新：

```text
PickupVisual.position.y
PickupVisual.rotation.y
```

硬边界：

| 项目 | 上限 |
|---|---:|
| 物理掉落节点 | 128 |
| 单次共享推进节点 | 128 |
| 单次 Delta | 0.25 秒 |
| 浮动振幅 | 0.12 米 |
| 合并扫描 | 64 节点 |
| 同类合并半径 | 1.75 米 |

## 暂停语义

协调器和后备掉落都使用：

```text
PROCESS_MODE_PAUSABLE
```

真实 `SimulationPauseService` 设置 `SceneTree.paused = true` 后：

- 视觉旋转停止；
- 浮动相位停止；
- `life_seconds` 不减少；
- 合并后的数量和位置不变；
- 恢复后从原时间继续。

菜单、设置和暂停 UI 仍可通过各自的 `PROCESS_MODE_ALWAYS` 工作。

## 共享视觉资源

`PickupVisualResourceCache` 复用：

```text
1 个 BoxMesh
1 个 SphereShape3D
每种颜色 1 个 StandardMaterial3D
```

材质缓存硬上限为 256。达到上限时，新颜色使用未缓存材质，不会拒绝或隐藏掉落。

缓存只持有不可变展示资源，不持有：

- 掉落数量；
- 世界位置；
- 剩余寿命；
- 背包引用；
- 合并状态。

## 生命周期

```text
install
→ bind CreatureSpawner
→ 监听 child_entered_tree / child_exiting_tree

activate
→ 注册已有掉落
→ 根据是否存在节点启停共享 Process

begin_world / clear
→ 停止 Process
→ 清空成员、Pending 和运行计数

shutdown
→ 断开 Spawner 信号
→ 释放引用
```

成员目录由现有 Spawner 事件维护，不在每帧重新扫描所有子节点。

## 存档边界

继续不保存：

```text
pickup_runtime
runtime_step_count
runtime_advance_count
visual_resources
visual_offset
remaining pickup lifetime
pending_pickups
pickup world positions
```

未拾取掉落仍属于当前世界会话的瞬时表现。已经拾取的物品通过 Inventory 进入正式世界存档。

## 诊断

`character_snapshot.pickups` 增加：

```text
runtime_process_mode
runtime_processing
runtime_node_budget
tracked_runtime_pickup_count
individual_process_count
runtime_step_count
runtime_advance_count
runtime_elapsed_seconds
expired_pickup_count
max_runtime_nodes_observed
max_runtime_delta_seconds
last_runtime_step
visual_resources
```

这些字段用于证明：

- 生产独立 `_process` 数量为零；
- 共享运行工作量受 128 节点限制；
- Pause 和世界生命周期正确；
- 共享资源数量受 256 材质预算保护。

## 测试

### 静态合同

```text
tests/developer_b/validate_pickup_shared_runtime.ps1
```

### 领域回归

```text
tests/qa/pickup_shared_runtime_regression.gd
```

验证：

- 两个节点由一次共享调用推进；
- 碰撞锚点不移动；
- 视觉根保持 0.12 米振幅；
- 同色节点共享 Mesh、Shape 和 Material；
- SceneTree Pause 冻结；
- 128 节点全部由共享运行时推进；
- 大 Delta 限制为 0.25 秒；
- 128 个过期节点只清理一次。

### 真实桌面与可视化

```text
tests/qa/pickup_shared_runtime_desktop_acceptance.gd
```

生产流程创建 128 个真实物理掉落，验证共享动画、稳定碰撞、真实暂停、资源复用、保存边界、菜单清理和完整重载，并输出 1024×576 截图与 JSON 报告。
