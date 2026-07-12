# 公开脚本 API

本项目是本地单人 Godot 游戏，没有网络 HTTP API。模块通过 GDScript 方法与 signal 协作。

## World

- `VoxelWorld.start_world(profile_id, seed, world_id, saved_state)`：生成并启动世界。
- `get_block` / `set_block` / `remove_block`：查询、放置和破坏方块。
- `set_focus`：设置 Chunk 流式加载中心。
- `serialize`：返回稀疏方块修改与已加载 Chunk 元数据。
- Signals：`chunk_loaded`、`chunk_unloaded`、`block_broken`、`block_placed`。

## Inventory / Crafting

- `InventoryService.add_item` / `remove_item` / `swap_slots` / `select_slot`。
- `InventoryService.serialize` / `deserialize`。
- `CraftingService.set_station` / `can_craft` / `craft`。

## Save / Gameplay

- `SaveService.create_world` / `save_world` / `load_world` / `list_worlds` / `delete_world`。
- `GameplayServiceHub.attach_game` 连接玩家、世界、UI、生存、音频与生物刷新。
- `StarWorldGame.collect_state` / `request_save` 汇总并持久化完整状态。

更完整的数据合同和场景树见根目录 [ARCHITECTURE.md](../ARCHITECTURE.md)。
