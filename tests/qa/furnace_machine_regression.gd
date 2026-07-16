extends SceneTree

const FurnaceScript = preload("res://src/machine/furnace_service.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ContainerStorageScript = preload("res://src/inventory/container_storage_service.gd")
const CraftingScript = preload("res://src/crafting/crafting_service.gd")
const SurvivalScript = preload("res://src/survival/survival_service.gd")
const InteractionScript = preload("res://src/interaction/block_interaction_service.gd")
const GameUIScript = preload("res://src/ui/game_ui.gd")
const InputContextScript = preload("res://src/input/input_context_service.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends RefCounted

	func block_key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_processing_and_transfer_contract()
	await _test_persistence_and_offline_progress()
	await _test_world_interaction_and_ui()
	await _test_service_hub_save_transaction()
	if failures.is_empty():
		print("QA FURNACE MACHINE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA FURNACE MACHINE FAILURE: %s" % failure)
		print("QA FURNACE MACHINE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_processing_and_transfer_contract() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var furnace = FurnaceScript.new()
	host.add_child(inventory)
	host.add_child(furnace)
	await process_frame
	furnace.setup(inventory.registry)
	_check(furnace.recipes.recipe_count() == 7, "seven dedicated furnace recipes load")
	_check(furnace.fuels.fuel_count() >= 4, "multiple fuels load through a dedicated registry")
	var machine_id := "furnace@4,20,-3"
	_check(furnace.open_machine(machine_id), "a furnace machine opens by stable world id")
	inventory.clear()
	inventory.add_item("raw_iron", 8)
	inventory.add_item("coal", 1)
	_check(
		furnace.transfer_from_inventory_auto(inventory, 0, machine_id),
		"smeltable inventory items route into the input slot",
	)
	_check(
		furnace.transfer_from_inventory_auto(inventory, 1, machine_id),
		"fuel inventory items route into the fuel slot",
	)
	_check(
		inventory.count_item("raw_iron") == 0 and inventory.count_item("coal") == 0,
		"machine insertion removes exactly the accepted inventory counts",
	)
	var smelted_events := 0
	furnace.item_smelted.connect(
		func(_machine_id: String, _recipe_id: String, _output: Dictionary) -> void:
			smelted_events += 1
	)
	furnace.advance_time(48.1, true)
	var snapshot: Dictionary = furnace.get_machine_snapshot(machine_id)
	_check(
		str(snapshot.get("output", {}).get("item_id", "")) == "iron_ingot"
		and int(snapshot.get("output", {}).get("count", 0)) == 8,
		"one coal processes eight iron items through elapsed-time simulation",
	)
	_check(smelted_events == 8, "each completed item emits one domain completion event")
	_check(
		snapshot.get("input", {}).is_empty()
		and snapshot.get("fuel", {}).is_empty()
		and is_zero_approx(float(snapshot.get("burn_remaining_seconds", 0.0))),
		"completed work consumes exact input and fuel without hidden leftovers",
	)
	_check(
		furnace.transfer_to_inventory(inventory, FurnaceScript.SLOT_OUTPUT, machine_id),
		"completed output transfers back to the player inventory",
	)
	_check(inventory.count_item("iron_ingot") == 8, "output transfer conserves the processed count")
	_check(furnace.can_remove_machine(machine_id), "an empty idle furnace can be removed safely")
	inventory.add_item("apple", 1)
	_check(
		not furnace.transfer_from_inventory_auto(inventory, 0, machine_id),
		"unsupported items are rejected instead of disappearing",
	)
	host.queue_free()
	await process_frame
	await process_frame


func _test_persistence_and_offline_progress() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var furnace = FurnaceScript.new()
	host.add_child(inventory)
	host.add_child(furnace)
	await process_frame
	furnace.setup(inventory.registry)
	var machine_id := "furnace@offline"
	furnace.ensure_machine(machine_id)
	inventory.clear()
	inventory.add_item("raw_gold", 1)
	inventory.add_item("oak_log", 1)
	furnace.transfer_from_inventory_auto(inventory, 0, machine_id)
	furnace.transfer_from_inventory_auto(inventory, 1, machine_id)
	furnace.advance_time(2.0, false)
	var saved: Dictionary = furnace.serialize()
	saved["saved_at_unix"] = int(Time.get_unix_time_from_system()) - 10
	var restored = FurnaceScript.new()
	host.add_child(restored)
	await process_frame
	restored.setup(inventory.registry)
	_check(restored.deserialize(saved), "furnace state deserializes from the world transaction")
	var restored_snapshot: Dictionary = restored.get_machine_snapshot(machine_id)
	_check(
		str(restored_snapshot.get("output", {}).get("item_id", "")) == "gold_ingot",
		"bounded offline elapsed time completes valid pending work",
	)
	_check(
		float(restored_snapshot.get("burn_remaining_seconds", 0.0)) >= 0.0,
		"fuel time is normalized during offline recovery",
	)
	var blocked_id := "furnace@blocked"
	var now := int(Time.get_unix_time_from_system())
	var blocked_state := {
		"version": 1,
		"saved_at_unix": now,
		"furnaces": {
			blocked_id: {
				"type": "furnace",
				"input": {"item_id": "raw_iron", "count": 1},
				"fuel": {"item_id": "coal", "count": 1},
				"output": {"item_id": "iron_ingot", "count": 64},
				"progress_seconds": 0.0,
				"burn_remaining_seconds": 0.0,
				"burn_total_seconds": 0.0,
			}
		},
	}
	var blocked = FurnaceScript.new()
	host.add_child(blocked)
	await process_frame
	blocked.setup(inventory.registry)
	blocked.deserialize(blocked_state)
	blocked.advance_time(30.0, false)
	var blocked_snapshot: Dictionary = blocked.get_machine_snapshot(blocked_id)
	_check(
		int(blocked_snapshot.get("input", {}).get("count", 0)) == 1
		and int(blocked_snapshot.get("fuel", {}).get("count", 0)) == 1
		and int(blocked_snapshot.get("output", {}).get("count", 0)) == 64,
		"a full output slot pauses work without consuming input or fuel",
	)
	host.queue_free()
	await process_frame
	await process_frame


func _test_world_interaction_and_ui() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var crafting = CraftingScript.new()
	var survival = SurvivalScript.new()
	var storage = ContainerStorageScript.new()
	var furnace = FurnaceScript.new()
	var game_ui = GameUIScript.new()
	var interactions = InteractionScript.new()
	for service in [inventory, crafting, survival, storage, furnace, game_ui, interactions]:
		host.add_child(service)
	await process_frame
	crafting.setup(inventory)
	storage.setup(inventory.registry)
	furnace.setup(inventory.registry)
	game_ui.setup(inventory, crafting, survival, null, null, null, storage, furnace)
	interactions.setup(game_ui, storage, inventory, furnace)
	var contexts: Array[StringName] = []
	game_ui.input_context_requested.connect(func(context: StringName): contexts.append(context))
	game_ui.begin_gameplay()
	var world := FakeWorld.new()
	var position := Vector3i(7, 21, -2)
	_check(interactions.interact(world, position, "furnace"), "right-click opens a real furnace machine")
	var machine_id := interactions.get_machine_id(world, position, "furnace")
	_check(
		game_ui.get_active_overlay() == GameUIScript.Overlay.FURNACE
		and furnace.get_active_machine_id() == machine_id,
		"furnace UI and machine service share the same stable machine id",
	)
	_check(
		not contexts.is_empty() and contexts.back() == InputContextScript.CONTEXT_MACHINE,
		"machine overlays own a dedicated non-gameplay input context",
	)
	_check(game_ui.get_furnace_panel() != null, "game UI mounts the dedicated furnace panel")
	inventory.clear()
	inventory.add_item("raw_iron", 1)
	inventory.add_item("coal", 1)
	furnace.transfer_from_inventory_auto(inventory, 0, machine_id)
	furnace.transfer_from_inventory_auto(inventory, 1, machine_id)
	_check(
		not interactions.can_break_block(world, position, "furnace"),
		"non-empty furnaces cannot be destroyed with their contents",
	)
	furnace.transfer_to_inventory(inventory, FurnaceScript.SLOT_INPUT, machine_id)
	furnace.transfer_to_inventory(inventory, FurnaceScript.SLOT_FUEL, machine_id)
	game_ui.close_overlay()
	_check(
		furnace.get_active_machine_id().is_empty()
		and contexts.back() == InputContextScript.CONTEXT_GAMEPLAY,
		"closing the furnace restores gameplay input and releases the active machine",
	)
	_check(interactions.can_break_block(world, position, "furnace"), "empty furnaces can be removed")
	interactions.on_block_removed(world, position, "furnace")
	_check(not furnace.has_machine(machine_id), "removing an empty furnace clears its machine record")
	_check(interactions.interact(world, position, "crafting_table"), "workbench interaction remains separate")
	_check(
		game_ui.get_active_overlay() == GameUIScript.Overlay.CRAFTING
		and crafting.active_station == "workbench",
		"workbench still grants only the crafting domain",
	)
	game_ui.end_gameplay()
	host.queue_free()
	await process_frame
	await process_frame


func _test_service_hub_save_transaction() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	_check(hub.get_node_or_null("FurnaceService") != null, "service hub mounts the furnace domain")
	var state: Dictionary = hub.save_service.create_world(
		"qa-furnace-%d" % Time.get_ticks_msec(), "star_continent", 424242
	)
	_check(
		state.get("machines", {}).get("furnaces", {}) is Dictionary,
		"new worlds include an empty machine state",
	)
	if state.is_empty():
		hub.queue_free()
		await process_frame
		return
	var world_id := str(state.get("metadata", {}).get("id", ""))
	hub.current_state = state.duplicate(true)
	hub.current_world_id = world_id
	var machine_id := "furnace@1,22,1"
	var machine_state := {
		"version": 1,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"furnaces": {
			machine_id: {
				"type": "furnace",
				"input": {},
				"fuel": {},
				"output": {"item_id": "iron_ingot", "count": 2},
				"progress_seconds": 0.0,
				"burn_remaining_seconds": 0.0,
				"burn_total_seconds": 0.0,
			}
		},
	}
	hub.furnace_service.deserialize(machine_state)
	_check(hub.save_current(), "service hub saves furnace state in the world transaction")
	var loaded: Dictionary = hub.save_service.load_world(world_id)
	var saved_machine: Dictionary = loaded.get("machines", {}).get("furnaces", {}).get(machine_id, {})
	_check(
		int(saved_machine.get("output", {}).get("count", 0)) == 2,
		"saved furnace output survives a world reload",
	)
	_check(hub.save_service.delete_world(world_id), "furnace test world is cleaned up")
	if hub.audio_service != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	hub.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
