# Development Plan

## Architecture and feasibility

Godot 4.x project using modular GDScript. `Core` owns contracts and scene orchestration; `Block/Chunk/World` own voxel data, procedural generation and mesh/collision lifecycle; `Player` owns input and raycast interaction. Independent data/gameplay services own `Inventory/Crafting/Save/Survival/Entity/Audio/UI`. JSON/resource registries provide at least 30 items and recipes. Save files use versioned JSON under `user://worlds/<id>/`, including sparse block overrides.

| Item | Decision / Guidance |
|---|---|
| Rendering | chunk-local voxel mesh or bounded pooled block meshes; collision rebuilt per changed chunk |
| World | deterministic seed + map profile; 16x16 horizontal chunks with bounded vertical generation and dynamic radius |
| Persistence | generated base world plus sparse modifications, player and inventory state |
| Compatibility | Godot 4.3+ GDScript APIs; Windows keyboard/mouse |
| Feasibility | yes; high difficulty; simplified complete implementations are explicitly allowed |

## Ownership and implementation order

1. Developer A: only `project.godot`, `src/core/**`, `src/block/**`, `src/chunk/**`, `src/world/**`, `src/player/**`, `scenes/game/**`, and A-owned tests.
2. Developer B: only `src/inventory/**`, `src/crafting/**`, `src/save/**`, `src/survival/**`, `src/entity/**`, `src/ui/**`, `src/audio/**`, `data/**`, `assets/**`, `scenes/ui/**`, `scenes/entities/**`, and B-owned tests/docs.
3. PM integrates contracts; developers self-test; independent QA pass follows; QA bugs return to the owning developer and must be retested.

## Shared contracts

- Core emits world/player/inventory signals; services communicate through public methods/signals, not cross-editing.
- World exposes `get_block`, `set_block`, `remove_block`, `world_to_block`, `block_to_world`, and sparse override serialization.
- Inventory exposes add/remove/count/selected slot and serialization; UI is a consumer.
- Save service accepts a complete state dictionary and world overrides; it does not own voxel generation.

## Risks and rollback

- Engine absent locally: acquire official portable Godot 4 console binary; retain source even if packaging is blocked.
- Voxel performance: bounded render distance and world height, greedy/surface-only mesh generation.
- Integration: fixed ownership boundaries and PM-owned handoffs.
- Rollback is file-level via Git diff; no destructive repository commands.

## Developer Confirmation

- Architect guidance reviewed: yes (PM-owned architecture due minimal roster)
- Feasibility reviewed: yes
- Concrete implementation plan ready: yes
- Ready to implement after user confirmation: yes
- Confirmed at: 2026-07-11

