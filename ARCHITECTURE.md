# Star World 架构

## 目标

项目使用 Godot 4 的场景树和模块化 GDScript。世界、输入、交互、UI、存档和生物通过小而稳定的公开方法与 signal 协作；高成本任务有明确预算，运行时状态有唯一所有者，新增玩法必须附带真实 Godot 回归。

## 运行时结构

```text
Game (Node3D)
├─ VoxelWorld
│  ├─ WorldGenerator
│  ├─ ChunkStreamingScheduler
│  └─ VoxelChunk[]
├─ Player
├─ Sun + WorldEnvironment
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
   └─ GameUI (HUD / Inventory / Crafting / Container / Pause / Death)
```

`GameplayServiceHub` 是组合根。它负责创建领域服务、连接信号、装载世界状态、注入 Player 依赖并将所有领域状态写入同一个世界保存事务。领域服务之间不通过硬编码场景路径互相查找。

## 世界生命周期

```text
menu
  → loading
  → start world
  → restore safe player state
  → attach input / interaction / gameplay services
  → gameplay
  → save transaction
  → menu
```

`loading` 阶段始终禁用玩家输入。只有世界、玩家、输入服务、交互服务和 UI 全部完成绑定后，`Game.world_started` 才触发 `activate_gameplay()`。

返回主菜单前必须先完成保存。写入失败时保留当前世界和 UI，不会静默丢失状态。

## 模块责任

| 模块 | 路径 | 责任 |
|---|---|---|
| Core | `src/core` | 世界生命周期、安全出生点、物理层策略、真实暂停 |
| Block | `src/block` | 方块 ID、材质/碰撞属性、方块到物品映射 |
| World / Chunk | `src/world`, `src/chunk` | Seed 生成、渐进区块流式加载、共享材质、网格与碰撞 |
| Input | `src/input` | 默认按键修复、输入查询、菜单/加载/游戏/UI/死亡上下文、窗口焦点 |
| Player | `src/player` | 第一人称协调器、移动控制器、RayCast 命中与玩法意图 |
| Interaction | `src/interaction` | 方块能力注册、工作台/熔炉/箱子交互协调、拆除策略 |
| Inventory | `src/inventory` | 玩家背包、容器存储、堆叠、转移、快捷装备和序列化 |
| Crafting | `src/crafting` | 配方注册、真实工位权限、原子消耗和产出 |
| Save | `src/save` | 多世界目录、兼容迁移、带备份的原子 JSON 写入 |
| Survival | `src/survival` | 生命、饥饿、食物、死亡/重生和昼夜光照 |
| Entity | `src/entity` | 程序化模型、有限状态 AI、种群维护、掉落物和拾取 |
| UI | `src/ui`, `scenes/ui` | 主菜单、HUD、背包、合成、容器和覆盖层状态机 |
| Audio | `src/audio` | 运行时 PCM 合成和 gameplay signal 音效桥接 |
| Data | `data` | JSON 物品、配方、地图与生物注册表 |

## 公开集成合同

### 服务组合与世界启动

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
```

世界可实现 `serialize_state`、`serialize` 或 `serialize_overrides`。ServiceHub 不依赖具体世界类。

### GameplayInputActions / GameplayInputService

- `ensure_default_bindings()` 是默认按键注册的唯一入口。
- WASD 同时注册物理键位和逻辑键码，并提供方向键后备。
- 残缺 action 会逐项修复，不要求 action 完全为空。
- 输入服务封装移动、跳跃、冲刺、快捷栏、保存、背包和合成查询。
- Player 与 GameUI 不各自维护另一套按键定义。

### InputContextService

支持：

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

只有窗口聚焦且处于 `gameplay` 时才捕获鼠标并启用 Player。离开 gameplay 或窗口失焦时会释放残留 action 状态，防止 W/Shift 粘键。

背包、合成和容器只阻断玩家输入；暂停与死亡还会请求 `SimulationPauseService` 停止真实世界模拟。

### SimulationPauseService

- 是 `SceneTree.paused` 的唯一写入者。
- 暂停菜单和死亡界面停止世界、生物、昼夜和物理。
- 继续、重生、返回菜单和服务退出都会清除残留暂停。
- UI 只发布暂停意图，不直接写 SceneTree。

### PlayerMovementController / PlayerSpawnResolver

- `PlayerMovementController.step` 只处理重力、跳跃、方向归一化、加速度和 `move_and_slide`。
- `PlayerSpawnResolver.resolve` 校验有限坐标、世界边界和角色净空。
- Player 保存 `position`、yaw 和独立 `look_pitch`。
- 世界切换和重生都会清除残留速度。

### BlockInteractionRegistry / BlockInteractionService

- 注册表描述方块能力，不保存运行时状态。
- Player 右键只把命中结果交给交互服务。
- 工作台和熔炉由真实世界方块授予工位能力。
- 箱子使用位置稳定 ID 打开 `ContainerStorageService`。
- 非空箱子拒绝拆除，避免内容静默丢失。
- 详细合同见 [BLOCK_INTERACTIONS.md](BLOCK_INTERACTIONS.md)。

右键优先级：

```text
可交互方块 → 放置选中方块 → 食用选中食物
```

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

### InventoryService

- 写入：`add_item`, `remove_item`, `remove_from_slot`, `swap_slots`, `clear`
- 查询：`count_item`, `has_items`, `get_slot`, `get_selected_item`, `is_hotbar_slot`
- 选择与装备：`select_slot`, `select_relative`, `equip_slot`, `consume_selected`
- 持久化：`serialize`, `deserialize`

黄色高亮表示真实快捷栏选择；蓝色高亮表示待交换源槽。快速装备会同步真实 `selected_slot`。

### ContainerStorageService

- 每个位置型容器拥有独立槽位数组。
- 所有物品写入都经过 ItemRegistry 校验和最大堆叠限制。
- 玩家背包与容器之间的转移保证数量守恒，空间不足时回滚剩余数量。
- 容器状态与世界状态在同一个保存事务中持久化。
- 当前箱子为 27 格；UI 不直接修改容器数据。

### CraftingService

- `setup(inventory)` 注入玩家背包。
- `set_station(hand | workbench | furnace)` 由可信交互路径设置。
- `C` 只打开随身合成。
- 工位下拉框只读，不能绕过世界方块使用高级配方。
- 输出空间不足时回滚材料。

### AtomicJsonStore / SaveService

写入顺序：

```text
new data → .tmp
old primary → .bak
.tmp → primary
failure → restore .bak
```

读取依次尝试主文件、有效临时文件和备份。存档浏览使用无副作用读取，不发出 `world_loaded`。

### ChunkStreamingScheduler / VoxelChunk

- 出生区块同步完成，确保进入世界后立即有地形与碰撞。
- 周边区块拆分为体素生成和网格/碰撞构建阶段。
- 构建受单步数量、单帧步骤和软时间预算约束。
- 移出视距的未完成任务可取消。
- 区块共享体素材质，避免重复资源分配。
- `get_streaming_stats()` 为性能 HUD 和后续自适应策略提供数据。

### CreaturePopulationPolicy

- 只统计当前 Spawner 的直接子生物。
- 定期回收远离玩家的生物，防止长时间游玩累积 AI 与物理对象。
- 生物只在完整 gameplay 生命周期激活后开始刷新。

## 数据合同

### 物品

`data/items.json` 每项至少包含：

```text
id, name, category, max_stack
```

可放置物品通过 `block_id` 映射方块；食物使用 `food` 和 `saturation`；工具和武器可包含 `durability`, `power`, `damage`。

### 配方

```json
{
  "id": "iron_pickaxe",
  "station": "workbench",
  "ingredients": {"iron_ingot": 3, "stick": 2},
  "output": {"id": "iron_pickaxe", "count": 1}
}
```

注册表测试会拒绝未知输入或输出 ID。

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

地形由 `map_id + seed` 重建，存档只保存稀疏方块修改。`containers` 是 v2 的兼容扩展字段；旧存档缺失该字段时自动补为空容器状态。

## 测试边界

- `core_smoke_test.gd`：五地图、出生净空、Chunk、世界修改和组合根。
- `run_tests.gd`：物品、合成、存档、生存、昼夜、生物和设置。
- `integration_regression.gd`：菜单、存档、战斗、食用、音频和退出。
- `input_interaction_regression.gd`：输入所有权、覆盖层和选中物品。
- `movement_lifecycle_regression.gd`：真实 WASD、窗口焦点和移动恢复。
- `physics_interaction_regression.gd`：物理层、生物攻击和玩家专用拾取。
- `block_interaction_regression.gd`：工作台、熔炉、箱子、转移守恒、拆除保护和持久化。
- `runtime_stability_regression.gd`：真实暂停、渐进区块、备份恢复和种群回收。
- `settings_retest.gd`：设置保存和运行时应用。
- `validate_data.ps1`：JSON 数量、唯一 ID 和配方引用完整性。

每个 PR 和 `master` 更新都会在 Windows + Godot 4.7 上执行完整运行时套件。
