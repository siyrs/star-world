extends SceneTree

const InteractionRegistry = preload("res://src/interaction/block_interaction_registry.gd")
const InteractionServiceScript = preload("res://src/interaction/block_interaction_service.gd")
const ContainerStorageScript = preload("res://src/inventory/container_storage_service.gd")
const FurnaceScript = preload("res://src/machine/furnace_service.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const CraftingScript = preload("res://src/crafting/crafting_service.gd")
const SurvivalScript = preload("res://src/survival/survival_service.gd")
const GameUIScript = preload("res://src/ui/game_ui.gd")
const InputContextScript = preload("res://src/input/input_context_service.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")
const PlayerScene = preload("res://scenes/game/player.tscn")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends RefCounted

	func block_key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_contract()
	await _test_station_machine_and_container_interactions()
	await _test_service_hub_persistence()
	if failures.is_empty():
		print("QA BLOCK INTERACTION PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA BLOCK INTERACTION FAILURE: %s" % failure)
		print("QA BLOCK INTERACTION FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_registry_contract() -> void:
	_check(InteractionRegistry.has_interaction("crafting_table"), "workbench is interactable")
	_check(InteractionRegistry.has_interaction("furnace"), "furnace is interactable")
	_check(InteractionRegistry.is_machine("furnace"), "furnace is registered as a machine")
	_check(InteractionRegistry.is_container("chest"), "chest is registered as a container")
	_check(
		not InteractionRegistry.has_interaction("stone"),
		"ordinary blocks do not enter the interaction path",
	)


func _test_station_machine_and_container_interactions() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var crafting = CraftingScript.new()
	var survival = SurvivalScript.new()
	var storage = ContainerStorageScript.new()
	var furnace = FurnaceScript.new()
	var game_ui = GameUIScript.new()
	var interactions = InteractionServiceScript.new()
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
	var position := Vector3i(4, 20, -3)

	_check(
		interactions.interact(world, position, "crafting_table"),
		"right-click interaction opens a workbench",
	)
	_check(
		(
			game_ui.get_active_overlay() == GameUIScript.Overlay.CRAFTING
			and crafting.active_station == "workbench"
		),
		"workbench interaction grants only the workbench station",
	)
	var station_select := game_ui.crafting_panel.get("_station_select") as OptionButton
	_check(
		station_select != null and station_select.disabled,
		"advanced crafting stations cannot be selected manually",
	)
	game_ui.close_overlay()
	_check(
		crafting.active_station == "hand",
		"closing the crafting overlay revokes the temporary workbench station",
	)
	_check(interactions.interact(world, position, "furnace"), "furnace interaction opens a machine")
	var machine_id := interactions.get_machine_id(world, position, "furnace")
	_check(
		(
			game_ui.get_active_overlay() == GameUIScript.Overlay.FURNACE
			and furnace.get_active_machine_id() == machine_id
			and crafting.active_station == "hand"
		),
		"furnace interaction is isolated from the crafting station state",
	)
	_check(
		contexts.back() == InputContextScript.CONTEXT_MACHINE,
		"furnace overlay owns the machine input context",
	)
	game_ui.close_overlay()

	_check(interactions.interact(world, position, "chest"), "chest interaction opens storage")
	var container_id := interactions.get_container_id(world, position, "chest")
	_check(
		(
			game_ui.get_active_overlay() == GameUIScript.Overlay.CONTAINER
			and storage.get_active_container_id() == container_id
		),
		"container overlay and storage service share one active container",
	)
	_check(
		not contexts.is_empty() and contexts.back() == InputContextScript.CONTEXT_CONTAINER,
		"container overlay owns a dedicated non-gameplay input context",
	)
	_check(
		game_ui.container_panel.get("_container_buttons").size() == 27,
		"a chest renders twenty-seven storage slots",
	)

	inventory.clear()
	inventory.add_item("stone", 70)
	_check(
		storage.transfer_from_inventory(inventory, 0, container_id),
		"an inventory stack transfers into the active chest",
	)
	_check(
		(
			int(storage.get_slot(container_id, 0).get("count", 0)) == 64
			and inventory.count_item("stone") == 6
		),
		"container transfer preserves exact item counts",
	)
	_check(
		not interactions.can_break_block(world, position, "chest"),
		"non-empty chests cannot be destroyed silently",
	)
	_check(
		storage.transfer_to_inventory(inventory, 0, container_id),
		"a chest stack transfers back into the player inventory",
	)
	_check(
		storage.is_empty(container_id) and inventory.count_item("stone") == 70,
		"round-trip transfer conserves the complete stack",
	)
	_check(
		interactions.can_break_block(world, position, "chest"),
		"empty chests can be removed",
	)
	interactions.on_block_removed(world, position, "chest")
	_check(
		not storage.has_container(container_id), "removing an empty chest clears its storage record"
	)

	var saved_id := interactions.get_container_id(world, Vector3i(8, 20, 2), "chest")
	storage.ensure_container(saved_id)
	storage.add_item(saved_id, "apple", 3, {"quality": "fresh"})
	var restored = ContainerStorageScript.new()
	host.add_child(restored)
	restored.setup(inventory.registry)
	_check(restored.deserialize(storage.serialize()), "container state deserializes")
	_check(
		(
			str(restored.get_slot(saved_id, 0).get("item_id", "")) == "apple"
			and int(restored.get_slot(saved_id, 0).get("count", 0)) == 3
			and restored.get_slot(saved_id, 0).get("metadata", {}).get("quality", "") == "fresh"
		),
		"container serialization retains item metadata and counts",
	)

	var future_slots: Array = []
	for index in 36:
		future_slots.append({})
	future_slots[35] = {"item_id": "diamond", "count": 1}
	var compatibility = ContainerStorageScript.new()
	host.add_child(compatibility)
	compatibility.setup(inventory.registry)
	compatibility.deserialize(
		{
			"containers":
			{
				"chest@future":
				{
					"type": "chest",
					"slot_count": 36,
					"slots": future_slots,
				}
			}
		}
	)
	compatibility.ensure_container("chest@future", "chest", 27)
	_check(
		(
			compatibility.get_slot_count("chest@future") == 36
			and str(compatibility.get_slot("chest@future", 35).get("item_id", "")) == "diamond"
		),
		"opening an existing container never truncates future or legacy capacity",
	)

	var player = PlayerScene.instantiate()
	host.add_child(player)
	await process_frame
	player.setup_gameplay_services({"interaction": interactions})
	_check(
		(
			player.interaction_service == interactions
			and player.has_method("interact_or_use_selected_item")
		),
		"player receives the shared interaction service instead of owning UI logic",
	)
	game_ui.end_gameplay()
	host.queue_free()
	await process_frame
	await process_frame


func _test_service_hub_persistence() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	_check(hub.get_node_or_null("ContainerStorage") != null, "service hub mounts container storage")
	_check(hub.get_node_or_null("FurnaceService") != null, "service hub mounts furnace machines")
	_check(
		hub.get_node_or_null("BlockInteraction") != null, "service hub mounts block interactions"
	)
	var state: Dictionary = hub.save_service.create_world(
		"qa-container-%d" % Time.get_ticks_msec(), "star_continent", 424242
	)
	_check(
		state.get("containers", {}).get("containers", {}) is Dictionary,
		"new worlds include an empty container state",
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
	var container_id := "chest@1,22,1"
	hub.container_storage.ensure_container(container_id)
	hub.container_storage.add_item(container_id, "diamond", 2)
	_check(hub.save_current(), "service hub saves container state with the world transaction")
	var loaded: Dictionary = hub.save_service.load_world(world_id)
	var saved_containers: Dictionary = loaded.get("containers", {}).get("containers", {})
	var saved_container: Dictionary = saved_containers.get(container_id, {})
	var saved_slots: Array = saved_container.get("slots", [])
	var saved_count := 0
	if not saved_slots.is_empty() and saved_slots[0] is Dictionary:
		saved_count = int(saved_slots[0].get("count", 0))
	_check(saved_count == 2, "saved chest contents survive a world reload")
	hub.save_service.delete_world(world_id)
	if hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	hub.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
