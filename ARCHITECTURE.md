# Star World 架构

## 目标

项目使用 Godot 4 的场景树和模块化 GDScript，而非自建 3D 引擎。生成世界与玩法服务通过小而稳定的公开方法和 signal 交互，使得网格重建、输入、UI、存档和生物可以独立测试。

## 运行时结构

```text
Game (Node3D)
├─ VoxelWorld
│  ├─ WorldGenerator
│  └─ VoxelChunk[]
├─ Player
├─ Sun + WorldEnvironment
└─ GameplayServiceHub (`service_hub.tscn`)
   ├─ InputContext
   ├─ Inventory
   ├─ Crafting
   ├─ Save
   ├─ Survival
   ├─ DayNight
   ├─ AudioService + AudioBridge
   ├─ CreatureSpawner
   ├─ MainMenu
   └─ GameUI (HUD / Inventory / Crafting / Pause / Death)
```

`res://scenes/ui/service_hub.tscn` 是游戏服务的组合根。它会在 `_ready()` 中实例化所有服务，并将合成系统连接到背包、将 UI 连接到生存/时间状态、将 UI 的覆盖层状态连接到统一输入上下文。

## 模块责任

| 模块 | 路径 | 责任 |
|---|---|---|
| Core | `src/core` | 启动场景、世界切换、收集完整存档状态 |
| Block | `src/block` | 方块 ID、材质/碰撞属性、方块到物品的映射 |
| World / Chunk | `src/world`, `src/chunk` | Seed 生成、区块流式加载、表面网格和碰撞重建 |
| Input | `src/input` | 管理菜单、游戏、背包、合成、暂停和死亡上下文；独占鼠标捕获与玩家输入开关 |
| Player | `src/player` | 第一人称移动、RayCast 交互、快捷栏动作；只在游戏上下文消费输入 |
| Inventory | `src/inventory` | 物品注册、堆叠、槽位交换、快捷装备、选中槽和序列化 |
| Crafting | `src/crafting` | 配方注册、工位限制、原子检查/消耗/产出 |
| Save | `src/save` | 多世界目录、版本迁移、原子 JSON 写入、设置持久化 |
| Survival | `src/survival` | 生命、饥饿、精确消费选中食物、死亡/重生以及昼夜光照 |
| Entity | `src/entity` | 程序化模型、有限状态 AI、刷新、掉落物和拾取 |
| UI | `src/ui`, `scenes/ui` | 主菜单、地图/存档/设置、HUD、背包、合成和覆盖层状态机 |
| Audio | `src/audio` | 运行时 PCM 合成和游戏 signal 音效桥接 |
| Data | `data` | JSON 物品、配方、地图与生物注册表 |

## 公开集成合同

### 服务组合

```gdscript
var service_hub = preload("res://scenes/ui/service_hub.tscn").instantiate()
service_hub.name = "GameplayServiceHub"
add_child(service_hub)
service_hub.start_world_requested.connect(_on_start_world_requested)

func _on_start_world_requested(state: Dictionary) -> void:
    var meta: Dictionary = state["metadata"]
    start_world(meta["map_id"], int(meta["seed"]), meta["id"], state)
    service_hub.attach_game(world, player, sun, world_environment, ground_resolver)
```

`attach_game` 使用鸭子类型合同：玩家可实现 `bind_inventory` / `bind_survival` / `set_input_enabled`，世界可实现 `serialize` 或 `serialize_overrides`。服务不依赖具体世界类。

### InputContextService

- 上下文：`menu`, `gameplay`, `inventory`, `crafting`, `pause`, `death`。
- `set_context` 是鼠标模式和玩家输入开关的唯一游戏内协调入口。
- 只有 `gameplay` 上下文捕获鼠标并启用玩家控制；其他上下文显示鼠标并停用玩家控制。
- 从 UI 返回游戏时会释放残留 GUI 焦点，避免键盘仍被按钮或输入框占用。
- Signals：`context_changed`, `gameplay_input_changed`。

### GameUI

- 背包、合成、暂停和死亡界面由单一覆盖层状态机管理，任一时刻最多只有一个阻塞层。
- UI 通过 `input_context_requested` 请求上下文，不直接修改鼠标捕获状态。
- `begin_gameplay` / `end_gameplay` 负责清理跨世界残留状态。

### InventoryService

- 写入：`add_item` / `remove_item` / `remove_from_slot` / `swap_slots` / `clear`
- 查询：`count_item` / `has_items` / `get_slot` / `get_selected_item` / `is_hotbar_slot`
- 选择与装备：`select_slot` / `select_relative` / `equip_slot` / `consume_selected`
- 持久化：`serialize` / `deserialize`
- Signals：`inventory_changed`, `slot_changed`, `selected_slot_changed`, `slot_equipped`, `item_added`, `item_removed`

背包 UI 将“当前可使用快捷栏槽位”和“等待交换的源槽位”作为两个独立状态。单击快捷栏会更新真实选中槽；右键或双击背包物品会把它装备到当前快捷栏槽位。

### CraftingService

- `setup(inventory)` 注入背包。
- `set_station("hand" | "workbench" | "furnace")` 切换工位。
- `can_craft` 先验证数量和工位；`craft` 消耗输入并写入输出。若输出没有空间，会回滚已消耗材料。

### Survival / DayNight

- 伤害入口：`take_damage(amount, cause)`；为玩家合同同时保留 `damage` 别名。
- 食物：`consume_food`, `consume_inventory_item`, `consume_selected_inventory_item`。玩家右键使用食物时只消耗当前选中槽，不会误删其他同名堆叠。
- 昼夜：`attach_lighting(sun, world_environment)`, `set_time`, `set_map_profile`, `is_night`。

### SaveService

- `create_world(name, map_id, seed, extra)` 创建默认状态并立即落盘。
- `save_world` / `load_world` / `list_worlds` / `delete_world` 实现多存档生命周期。
- 世界 ID 要求为安全单路径段，防止路径穿越。

## 数据合同

### 物品

`data/items.json` 每项至少包含 `id`, `name`, `category`, `max_stack`。可放置物品通过 `block_id` 映射世界方块；食物使用 `food` 和 `saturation`；工具/武器可包含 `durability`, `power`, `damage`。

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
metadata { id, name, map_id, seed, created_at, updated_at, play_seconds }
player   { position[3], rotation[3] }
inventory{ version, selected_slot, slot_count, hotbar_size, slots[] }
world    { block_overrides, loaded_chunks }
survival { health, hunger, saturation, alive }
day_night{ time_of_day, day, cycle_duration, map_id }
```

地形由 `map_id + seed` 重建，存档仅保存玩家改动的稀疏 `block_overrides`，因此建筑可恢复而存档不会随探索范围无界增长。`SaveService` 在读取 v1 时补齐生存和昼夜字段并升级到 v2。

## 测试边界

`tests/developer_a/core_smoke_test.gd` 覆盖五类 Seed 地形、出生净空、体素网格/碰撞、Chunk 流式装卸和世界修改恢复；`tests/developer_b/run_tests.gd` 覆盖堆叠、合成原子性、存档往返、生存、昼夜、生物与设置；`tests/qa/integration_regression.gd` 覆盖菜单路由、多存档闭包、战斗/食用/掉落、音效和退出生命周期；`tests/qa/input_interaction_regression.gd` 覆盖输入上下文所有权、覆盖层互斥、快捷栏装备和精确消费选中物品。`validate_data.ps1` 独立校验 JSON 数量、唯一 ID 和配方引用完整性。
