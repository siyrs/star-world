# Test Plan

## Scope and environment

PM owns pre-implementation strategy; an independent QA specialist is activated after developer self-tests. Target: Windows, official Godot 4.x console/editor, fresh and existing `user://` data.

| ID | Function Point | Related AC | Scenario | Expected Result | Priority |
|---|---|---|---|---|---|
| TC-001 | FP-001 | AC-001 | import project and start main scene | no parse errors; menu available | P0 |
| TC-002 | FP-003 | AC-002 | create each of five maps with fixed seeds | five playable, distinct environments | P0 |
| TC-003 | FP-002, FP-004 | AC-003 | move/jump/mine/place/select slot | collision and interactions update world | P0 |
| TC-004 | FP-005, FP-006 | AC-004 | enumerate items/recipes, stack and craft | at least 30 items/recipes, real input consumption/output | P0 |
| TC-005 | FP-007, FP-008 | AC-005 | advance time/hunger; spawn and damage mobs | survival changes; four creature types act and drop | P1 |
| TC-006 | FP-009 | AC-006 | modify blocks/save/relaunch/load | player, inventory and changes restored | P0 |
| TC-007 | FP-010 | AC-007 | exercise HUD/settings/audio/docs/build | visible HUD, persisted settings, audio calls, build instructions | P1 |

## Entry and exit rules

- Entry: both developers provide self-test evidence; Godot import succeeds.
- Exit: all P0 pass, no blocker/critical bug, P1 failures documented or fixed.
- Any QA-reported fix returns to `self-tested`, then independent QA retest; no bug is closed on developer assertion alone.
- Regression: boot/menu, five maps, player interaction, inventory/crafting, save round-trip, survival/entities.

## QA Readiness Decision

- Concrete test cases ready before implementation: yes
- Retest expectations defined: yes
- Ready at: 2026-07-11

