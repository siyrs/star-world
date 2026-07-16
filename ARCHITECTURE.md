# Star World 架构

## 目标

项目使用 Godot 4 的场景树和模块化 GDScript。世界、输入、交互、机器、UI、存档、玩家体验、诊断和性能控制通过小而稳定的公开方法与 signal 协作。

工程约束：

- 运行时状态必须有唯一所有者；
- 高成本工作必须有预算和上限；
- UI 只表达用户意图，不直接修改领域数据；
- Player 不承载存档、面板、容器、机器或性能策略；
- 诊断与引导展示不能参与鼠标命中；
- 持续加工不能伪装成即时合成；
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
│  ├─ PlayerPhysicsProfile
│  └─ PlayerFocusResolver
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
   ├─ FurnaceService
   │  ├─ FurnaceRecipeRegistry
   │  └─ FurnaceFuelRegistry
   ├─ Crafting
   ├─ BlockInteraction
   ├─ PlayerExperienceCoordinator
   │  ├─ GameplayFeedbackService
   │  ├─ OnboardingService
   │  └─ InteractionPromptResolver
   ├─ Save
   ├─ Survival
   ├─ DayNight
   ├─ AudioService + AudioBridge
   ├─ CreatureSpawner
   ├─ MainMenu
   └─ GameUI
      ├─ HUD
      ├─ GuidanceOverlay
      ├─ InventoryPanel
      ├─ CraftingPanel
      ├─ FurnacePanel
      ├─ ContainerPanel
      ├─ Pause
      └─ Death
```

组合根职责：

- `Game` 创建世界、玩家、相机和运行诊断，执行世界生命周期；
- `GameplayServiceHub` 创建领域服务、装载状态、注入依赖并执行保存事务；
- `RuntimeDiagnosticsCoordinator` 观察运行状态并协调性能预算，不保存玩法数据；
- `PlayerExperienceCoordinator` 把领域事实转换为提示和引导，不拥有世界数据；
- `GameUI` 管理互斥界面状态，不直接修改 Player、SceneTree 或领域 Dictionary。

## 世界生命周期

```text
menu
  → loading
  → reset pause / input / transient experience
  → deserialize inventory / containers / machines / survival / time / onboarding
  → create or start world
  → validate spawn chunk mesh + collision
  → resolve supported player spawn
  → attach gameplay services and player experience
  → activate and validate player camera
  → attach diagnostics and adaptive streaming
  → gameplay
  → save one atomic world transaction
  → stop simulation services
  → restore streaming baseline
  → detach diagnostics and player experience
  → clear chunks / collisions / creatures / containers / machines
  → menu
```

`loading` 阶段始终禁用玩家输入。只有世界、玩家、输入、交互、UI、相机和出生区块全部完成验证后，`world_started` 才允许进入 gameplay。

启动失败必须：

- 隐藏无效 Player；
- 清理半启动世界；
- 解除 Player、Prompt、诊断和机器活动引用；
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
| Player | `src/player` | 第一人称协调、移动、RayCast 焦点和玩法意图 |
| Interaction | `src/interaction` | 方块能力注册、工作台/机器/箱子路由、拆除策略 |
| Inventory | `src/inventory` | 玩家背包、容器存储、堆叠、转移、装备和序列化 |
| Machine | `src/machine` | 熔炉配方、燃料、机器槽位、时间推进、离线恢复和序列化 |
| Crafting | `src/crafting` | 随身/工作台配方、工位权限、原子消耗和产出 |
| Experience | `src/experience` | 即时反馈、上下文提示、持久引导和体验协调 |
| Save | `src/save` | 多世界目录、兼容迁移、带备份的原子 JSON 写入 |
| Survival | `src/survival` | 生命、饥饿、食物、死亡/重生和昼夜光照 |
| Entity | `src/entity` | 程序化模型、有限状态 AI、种群维护、掉落物和拾取 |
| UI | `src/ui`, `scenes/ui` | 主菜单、HUD、引导、背包、合成、熔炉、容器和覆盖层状态机 |
| Audio | `src/audio` | 程序化 PCM、音效桥接、明确停止与资源释放 |
| Data | `data` | JSON 物品、普通配方、熔炉配方、燃料、地图与生物注册表 |

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

`attach_game` 使用能力合同。Player 可实现：

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

隐藏加载界面前验证：

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
- 输入服务封装移动、跳跃、冲刺、快捷栏、保存、背包、合成、F1 和 F3；
- Player 与 GameUI 不维护第二套按键定义。

### InputContextService

上下文：

```text
menu
loading
gameplay
inventory
crafting
machine
container
pause
death
```

只有窗口聚焦且处于 `gameplay` 时才捕获鼠标并启用 Player。离开 gameplay 或窗口失焦时释放残留 action，避免粘键。

背包、合成、机器和容器只阻断玩家输入；暂停与死亡还会请求 `SimulationPauseService` 停止真实模拟。

### SimulationPauseService

- 是 `SceneTree.paused` 的唯一写入者；
- 暂停和死亡停止世界、生物、昼夜、机器和物理；
- 继续、重生、返回菜单和服务退出都会清除暂停；
- UI 只发布暂停意图。

### PlayerMovementController / PlayerSpawnResolver / PlayerFocusResolver

- `PlayerMovementController.step` 只处理重力、跳跃、方向、加速度和 `move_and_slide`；
- `PlayerSpawnResolver.resolve` 同时校验有限坐标、身体净空和脚下支撑；
- `PlayerFocusResolver` 将 RayCast 命中统一转换为 block/entity 描述；
- Player 保存 `position`、yaw 和独立 `look_pitch`；
- 世界切换和重生清除残留速度；
- Player 只发布 `interaction_focus_changed` 与 `gameplay_action_reported`；
- Player 不创建面板、不保存容器/机器、不判断性能阈值。

### BlockInteractionRegistry / BlockInteractionService

注册表描述静态能力：

```text
crafting_table → crafting(workbench)
furnace        → machine(furnace)
chest          → container(chest, 27)
```

交互服务：

- 接收 Player 的世界命中；
- 生成稳定位置 ID；
- 路由到 Crafting、Furnace 或 Container 域；
- 执行非空拆除保护；
- 方块移除后清理领域记录。

右键优先级：

```text
可交互方块 → 放置选中方块 → 食用选中食物
```

详细合同见 [BLOCK_INTERACTIONS.md](BLOCK_INTERACTIONS.md)。

### GameUI

覆盖层：

```text
NONE
INVENTORY
CRAFTING
FURNACE
CONTAINER
PAUSE
DEATH
```

任一时刻最多一个阻塞层。GameUI 请求输入上下文和暂停意图，但不直接写鼠标模式、Player 输入或 SceneTree 暂停。

HUD、GuidanceOverlay 和 F3 面板是展示层，整棵 Control 树必须使用鼠标透传策略。

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

- 只拥有 `hand` 与 `workbench` 配方；
- `C` 只打开随身合成；
- 工作台权限只能通过可信世界交互获得；
- 工位展示不可手动绕过；
- 输出空间不足时回滚材料；
- 关闭工作台界面时回收权限。

### FurnaceService

- 每个 `furnace@x,y,z` 拥有独立原料、燃料、产出和计时；
- 配方来自 `furnace_recipes.json`；
- 燃料来自 `fuels.json`；
- 产出满时不消费输入或燃料；
- UI 关闭后继续运行，SceneTree 暂停时停止；
- 保存时记录机器状态和时间戳；
- 加载时执行有上限的离线模拟；
- 三槽非空时阻止拆除；
- UI 只调用转移 API，不修改内部 Dictionary。

详细合同见 [FURNACE_MACHINES.md](FURNACE_MACHINES.md)。

### PlayerExperienceCoordinator

- 连接 Player、Inventory、GameUI、BlockInteraction 和 FurnaceService；
- 焦点描述交给 `InteractionPromptResolver`；
- 玩法动作交给 `OnboardingService` 与 `GameplayFeedbackService`；
- 熔炉完成事件转换为去重 Toast；
- 世界进入/退出时挂载或释放 Player 引用；
- 引导状态进入世界保存事务；
- 不修改世界、背包或机器数据。

详细合同见 [PLAYER_EXPERIENCE.md](PLAYER_EXPERIENCE.md)。

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
machines   { version, saved_at_unix, furnaces { stable_id → slots + progress + fuel } }
world      { block_overrides, loaded_chunks }
survival   { health, hunger, saturation, alive }
day_night  { time_of_day, day, cycle_duration, map_id }
experience { version, onboarding }
```

地形由 `map_id + seed` 重建，存档只保存稀疏方块修改。缺失 `containers`、`machines` 或 `experience` 的旧存档会迁移为空状态。

## 测试边界

自动门禁分为：

- 数据：物品、普通配方、熔炉配方、燃料、地图、生物引用完整；
- 领域：背包、合成、容器、熔炉、存档、生存、输入和性能策略；
- 集成：世界启动、鼠标、WASD、覆盖层、交互路由和保存事务；
- 布局：最低 `1024×576` 下关键界面完整且互不遮挡；
- 桌面：真实鼠标点击主菜单、暂停和熔炉原料/燃料/产出/关闭按钮；
- 视觉：世界中央区域不能是空白或单一天空；
- 发行：实际 Windows Release 导出、启动、跨区块 soak、截图、JSON 和日志扫描；
- 生命周期：多轮进入/退出、资源释放、无 ObjectDB 泄漏。

任何新增领域都必须至少补充一个纯领域回归、一个集成回归，并在涉及 UI 时补真实桌面鼠标验收。
