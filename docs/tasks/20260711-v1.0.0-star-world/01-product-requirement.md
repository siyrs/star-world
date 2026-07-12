# Product Requirement

## Goal and scope

Deliver a runnable Windows Godot 4.x game, 《星的世界》, with a simplified but complete Minecraft-like loop: choose one of five seeded worlds, explore a voxel world, mine/collect/place blocks, manage survival and inventory, craft, meet creatures, save, quit, and resume.

## Function Points

| ID | Function Point | Priority | Status |
|---|---|---|---|
| FP-001 | Godot project, main menu, Windows launch | P0 | confirmed |
| FP-002 | 18+ voxel block types, collision, add/remove | P0 | confirmed |
| FP-003 | seeded chunk generation, load/unload, five map environments | P0 | confirmed |
| FP-004 | first-person movement, jump, gravity, mining/placing, hotbar keys | P0 | confirmed |
| FP-005 | 30+ stackable inventory items and hotbar UI | P0 | confirmed |
| FP-006 | workbench and 30+ real recipes | P0 | confirmed |
| FP-007 | health, hunger, death/respawn, day/night lighting | P0 | confirmed |
| FP-008 | chicken, cow, pig, zombie AI/health/drops | P1 | confirmed |
| FP-009 | multi-world save of seed/chunks/player/inventory/buildings | P0 | confirmed |
| FP-010 | HUD, settings, save/continue UI, synthesized game audio | P1 | confirmed |

## Acceptance Criteria

| ID | Criteria | Related Function Point | Pass Rule |
|---|---|---|---|
| AC-001 | Project starts into a usable main menu | FP-001 | Godot headless import succeeds and interactive scene reaches menu |
| AC-002 | All five named maps can create distinct seeded worlds | FP-003 | each map type loads terrain with distinct rules/resources/environment |
| AC-003 | Player can move, jump, collide, mine and place | FP-002, FP-004 | automated script parse plus interactive smoke test |
| AC-004 | Inventory stacks 30+ items and crafting exposes 30+ recipes | FP-005, FP-006 | registry/recipe tests and UI smoke test |
| AC-005 | Survival, day/night, three animals and zombie work | FP-007, FP-008 | runtime smoke test verifies state changes/spawn/AI/drop paths |
| AC-006 | Save/reload restores modified blocks, player and inventory | FP-009 | save round-trip test plus relaunch smoke test |
| AC-007 | HUD/settings/audio and documentation/build steps are present | FP-001, FP-010 | inspection and runnable package verification |

## Boundaries and decisions

- Godot 4.x + GDScript, Windows desktop, no custom low-level engine.
- Procedural low-poly voxel models and synthesized tones are acceptable art/audio for the complete playable simplified version.
- No multiplayer, redstone-equivalent automation, advanced fluids, infinite commercial-scale biome catalogue, or production marketplace assets in v1.0.0.
- User explicitly authorized immediate implementation in the 2026-07-11 request; no open questions remain.

## Product Manager Decision

- Requirement ready for feasibility review: yes
- Requirement ready for development: yes
- Decision time: 2026-07-11

