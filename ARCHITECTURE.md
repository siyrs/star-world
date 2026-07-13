# Star World 架构

## 目标

项目使用 Godot 4 的场景树和模块化 GDScript。世界、输入、交互、UI、存档、诊断和性能控制通过小而稳定的公开方法与 signal 协作。

工程约束：

- 运行时状态必须有唯一所有者；
- 高成本工作必须有预算和上限；
- UI 只表达用户意图，不直接修改领域数据；
- Player 不承载存档、面板、容器或性能策略；
- 诊断展示不能参与鼠标命中；
- 新功能必须通过真实 Godot、桌面窗口和 Windows Release 验收；
- 退出码为 0 不能掩盖脚本错误或资源泄漏。

## 运行时结构

```text
Game (Node3D)
├─ VoxelWorld
│  ├─ WorldGenerator
│  ├─ ChunkStreamingScheduler
│  └─ VoxelChunk[]
├─ Player
│  ├─ PlayerMovementController
│  ├─ PlayerSpawnResolver
│  └─ PlayerPhysicsProfile
├─ Sun + WorldEnvironment
├─ RuntimeDiagnosticsCoordinator
│  ├─ RuntimeTelemetryService
│  ├─ AdaptiveStreamingController
│  │  ├─ AdaptiveStreamingPolicy
│  │  └─ StreamingBudgetAdapter
│  └─ DiagnosticsOverlay
└─ GameplayServiceHub (`service_hub.tscn`)
   ├─ GameplayInput
   ├─ InputContext
   ├─ SimulationPause
   ├─ Inventory
   ├─ ContainerStorage
   ├─ Crafting
   ├─ BlockInteraction
   ├─ Save
   ├─ Survival
   ├─ DayNight
   ├─ AudioService + AudioBridge
   ├─ CreatureSpawner
   ├─ MainMenu
   └─ GameUI
      ├─ HUD
      ├─ InventoryPanel
      ├─ CraftingPanel
      ├─ ContainerPanel
      ├─ Pause
      └─ Death
```

`Game` 是世界和最终运行诊断的组合根。`GameplayServiceHub` 是玩法服务组合根。两者职责不同：

- `Game` 创建世界、玩家、相机、运行诊断并执行世界生命周期；
- `GameplayServiceHub` 创建领域服务、装载状态、注入 Player 依赖并执行保存事务；
- `RuntimeDiagnosticsCoordinator` 只观察运行状态和协调性能预算，不保存玩法数据。

## 世界生命周期

```text
menu
  → loading
  → create/start world
  → validate spawn chunk mesh + collision
  → resolve supported player spawn
  → attach gameplay services
  → activate and validate player camera
  → attach diagnostics and adaptive streaming
  → gameplay
  → save transaction
  → stop simulation services
  → restore streaming baseline
  → detach diagnostics
  → clear chunks / collisions / creatures
  → menu
```

`loading` 阶段始终禁用玩家输入。只有世界、玩家、输入、交互、UI、相机和出生区块全部完成验证后，`world_started` 才允许进入 gameplay。

启动失败必须：

- 隐藏无效 Player；
- 清理半启动世界；
- 解除运行时引用；
- 恢复 menu InputContext；
- 恢复可点击主菜单；
- 显示具体错误原因。

返回主菜单前必须先完成保存。保存失败时保留当前世界和 UI。

## 模块责任

| 模块 | 路径 | 责任 |
|---|---|---|
| Core | `src/core` | 世界生命周期、安全出生、物理层策略、启动验证、真实暂停 |
| Block | `src/block` | 方块 ID、材质/碰撞属性、方块到物品映射 |
| World / Chunk | `src/world`, `src/chunk` | Seed 生成、渐进流式加载、共享材质、网格与碰撞 |
| Performance | `src/performance` | 纯预算策略、世界能力适配、热身/冷却/防抖控制 |
| Diagnostics | `src/diagnostics` | 遥测、健康评价、报告、最终 Release smoke |
| Input | `src/input` | 默认按键修复、输入查询、上下文和窗口焦点 |
| Player | `src/player` | 第一人称协调器、移动、RayCast 命中和玩法意图 |
| Interaction | `src/interaction` | 方块能力注册、工作台/熔炉/箱子路由、拆除策略 |
| Inventory | `src/inventory` | 玩家背包、容器存储、堆叠、转移、装备和序列化 |
| Crafting | `src/crafting` | 配方注册、真实工位权限、原子消耗和产出 |
| Save | `src/save` | 多世界目录、兼容迁移、带备份的原子 JSON 写入 |
| Survival | `src/survival` | 生命、饥饿、食物、死亡/重生和昼夜光照 |
| Entity | `src/entity` | 程序化模型、有限状态 AI、种群维护、掉落物和拾取 |
| UI | `src/ui`, `scenes/ui` | 主菜单、HUD、背包、合成、容器和覆盖层状态机 |
| Audio | `src/audio` | 程序化 PCM、音效桥接、明确停止与资源释放 |
| Data | `data` | JSON 物品、配方、地图与生物注册表 |

## 公开集成合同

### Game / GameplayServiceHub

```gdscript
service_hub.start_world_requested.connect(_on_world_state_requested)
world_started.connect(func(_profile, _seed, _world_id): service_hub.activate_gameplay())

func _on_world_state_requested(state: Dictionary) -> void:
    var metadata: Dictionary = state["metadata"]
    start_world(
        metadata["map_id"],
        int(metadata["seed"]),
        metadata["id"],
        state
    )
```

`attach_game` 使用鸭子类型合同。Player 可实现：

```text
setup_gameplay_services
bind_inventory
bind_survival
bind_input_service
bind_interaction_service
set_input_enabled
serialize_state
```

世界可实现：

```text
serialize_state
serialize
serialize_overrides
resolve_ground_position
get_streaming_stats
```

ServiceHub 不依赖具体世界实现类。

### WorldRuntimeGuard

在隐藏加载界面前验证：

```text
world.is_started
loaded chunk count > 0
spawn chunk build complete
surface_face_count > 0
MeshInstance3D.mesh != null
CollisionShape3D.shape != null
Viewport current camera == Player Camera
```

任何失败都回滚到菜单，不允许留下空白画面。

### GameplayInputActions / GameplayInputService

- `ensure_default_bindings()` 是默认按键注册的唯一入口；
- WASD 同时注册物理键位和逻辑键码，并提供方向键后备；
- 残缺 action 会逐项修复；
- 输入服务封装移动、跳跃、冲刺、快捷栏、保存、背包、合成和 F3；
- Player 与 GameUI 不维护第二套按键定义。

### InputContextService

上下文：

```text
menu
loading
gameplay
inventory
crafting
container
pause
death
```

只有窗口聚焦且处于 `gameplay` 时才捕获鼠标并启用 Player。离开 gameplay 或窗口失焦时释放残留 action，避免粘键。

背包、合成和容器只阻断玩家输入；暂停与死亡还会请求 `SimulationPauseService` 停止真实模拟。

### SimulationPauseService

- 是 `SceneTree.paused` 的唯一写入者；
- 暂停和死亡停止世界、生物、昼夜和物理；
- 继续、重生、返回菜单和服务退出都会清除暂停；
- UI 只发布暂停意图。

### PlayerMovementController / PlayerSpawnResolver

- `PlayerMovementController.step` 只处理重力、跳跃、方向、加速度和 `move_and_slide`；
- `PlayerSpawnResolver.resolve` 同时校验有限坐标、身体净空和脚下支撑；
- Player 保存 `position`、yaw 和独立 `look_pitch`；
- 世界切换和重生清除残留速度；
- Player 不创建面板、不保存容器、不判断性能阈值。

### BlockInteractionRegistry / BlockInteractionService

- 注册表描述静态方块能力；
- Player 右键只把命中结果交给交互服务；
- 工作台和熔炉由真实世界方块授予权限；
- 箱子使用稳定位置 ID；
- 非空箱子拒绝拆除。

右键优先级：

```text
可交互方块 → 放置选中方块 → 食用选中食物
```

详细合同见 [BLOCK_INTERACTIONS.md](BLOCK_INTERACTIONS.md)。

### GameUI

覆盖层状态：

```text
NONE
INVENTORY
CRAFTING
CONTAINER
PAUSE
DEATH
```

任一时刻最多一个阻塞层。GameUI 请求输入上下文和暂停意图，但不直接写鼠标模式、Player 输入或 SceneTree 暂停。

HUD 和 F3 面板是纯展示层，整棵 Control 树必须使用鼠标透传策略。

### InventoryService / ContainerStorageService

Inventory：

```text
add_item
remove_item
remove_from_slot
swap_slots
select_slot
select_relative
equip_slot
consume_selected
serialize
deserialize
```

ContainerStorage：

- 每个稳定容器 ID 拥有独立槽位；
- 物品写入经过 ItemRegistry 和最大堆叠校验；
- 背包与容器转移保证数量守恒；
- 空间不足时回滚剩余数量；
- UI 不直接修改容器数组；
- 容器与世界在同一次保存事务中持久化。

### CraftingService

- `C` 只打开随身合成；
- 工作台和熔炉权限只能通过可信世界交互获得；
- 工位展示不可手动绕过；
- 输出空间不足时回滚材料；
- 关闭高级工位界面时回收权限。

### AtomicJsonStore / SaveService

写入顺序：

```text
new data → .tmp
old primary → .bak
.tmp → primary
failure → restore .bak
```

读取依次尝试主文件、有效临时文件和备份。存档浏览使用无副作用读取。

### ChunkStreamingScheduler / VoxelChunk

- 出生区块同步完成，确保立即有地形和碰撞；
- 周边区块拆为体素生成和网格/碰撞阶段；
- 构建受单步数量、单帧步骤和软时间预算约束；
- 移出视距的未完成任务可取消；
- 区块共享体素材质；
- `get_streaming_stats()` 暴露队列和预算执行结果。

### AdaptiveStreamingPolicy / Controller

四档状态：

```text
conservative
guarded
balanced
throughput
```

分层职责：

- Policy：纯快照决策；
- Adapter：读取/写入世界预算能力；
- Controller：热身、确认、冷却、防抖、严重压力快速降载；
- Telemetry：发布状态；
- Overlay：展示状态。

控制器只改变构建预算，不改变玩家视距。退出世界、禁用或释放节点时恢复基础预算。详细合同见 [ADAPTIVE_STREAMING.md](ADAPTIVE_STREAMING.md)。

### RuntimeTelemetry / DiagnosticsOverlay

遥测记录：

```text
frame timing
stutters
memory
nodes
draw calls
streaming queue
adaptive streaming state
creatures / pickups
input context
mouse mode
pause
player position
health
```

F3 面板不修改任何业务状态。详细合同见 [RUNTIME_DIAGNOSTICS.md](RUNTIME_DIAGNOSTICS.md)。

### CreaturePopulationPolicy

- 只统计当前 Spawner 的直接子生物；
- 定期回收远离玩家的生物；
- 生物只在完整 gameplay 生命周期激活后开始刷新；
- 返回菜单和世界切换必须清空旧生物。

### AudioService

- 程序化音频缓存由 AudioService 唯一持有；
- `stop_ambient()` 用于普通世界切换；
- `shutdown()` 停止播放器、解除 stream 并清空缓存；
- `dispose()` 是终止状态，显式释放播放器节点；
- 释放后所有播放请求都是无副作用 no-op；
- Release smoke 在退出前等待音频服务器结算并执行 dispose。

## 存档 Schema v2

```text
save_version
metadata   { id, name, map_id, seed, created_at, updated_at, play_seconds }
player     { position[3], rotation[3], look_pitch }
inventory  { version, selected_slot, slot_count, hotbar_size, slots[] }
containers { version, containers { stable_id → type, slot_count, slots[] } }
world      { block_overrides, loaded_chunks }
survival   { health, hunger, saturation, alive }
day_night  { time_of_day, day, cycle_duration, map_id }
```

地形由 `map_id + seed` 重建，存档只保存稀疏方块修改。缺失 `containers` 的旧存档会迁移为空容器状态。

## 测试边界

```text
core_smoke_test.gd                 五地图、出生、Chunk、世界修改、组合根
run_tests.gd                       物品、合成、存档、生存、昼夜、生物、设置
integration_regression.gd          菜单、存档、战斗、食用、音频、退出
input_interaction_regression.gd    输入所有权、覆盖层、选中物品
movement_lifecycle_regression.gd   真实 WASD、焦点、安全出生、移动恢复
physics_interaction_regression.gd  物理层、生物攻击、玩家专用拾取
block_interaction_regression.gd    工位、箱子、转移、拆除、持久化
desktop_input_contract_regression  HUD 透传、真实控件命中
runtime_diagnostics_regression.gd  遥测、健康策略、F3 透传
adaptive_streaming_regression.gd   档位、边界、滞后、冷却、恢复
 audio_lifecycle_regression.gd     程序化音频停止、缓存和播放器释放
runtime_stability_regression.gd    暂停、渐进区块、备份恢复、种群回收
runtime_soak_regression.gd         三轮世界启动、跨区块、返回和资源回收
settings_retest.gd                 设置保存和运行时应用
desktop_acceptance_regression.gd   真实窗口、按钮、鼠标、画面
Windows release smoke              最终 EXE、跨区块 soak、截图、日志、泄漏
```

每个 PR 和 `master` 更新都会在 Windows + Godot 4.7 上执行完整套件。只有源码、桌面窗口和最终 Release 三层均通过才允许合并。
