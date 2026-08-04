extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const SaveServiceScript = preload("res://src/save/save_service.gd")

var checks := 0
var failures: Array[String] = []
var _world_id := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var inventory = InventoryScript.new(36, 9)
	var restored = InventoryScript.new(36, 9)
	var save_service = SaveServiceScript.new()
	root.add_child(inventory)
	root.add_child(restored)
	root.add_child(save_service)
	await process_frame

	var expected_items := {
		"torch": 28,
		"cooked_chicken": 6,
		"iron_ingot": 4,
		"coal": 8,
		"bread": 6,
		"diamond": 1,
		"gold_ingot": 3,
		"iron_pickaxe": 1,
		"abyss_cinder": 1,
	}
	for item_id: String in expected_items.keys():
		_check(
			int(inventory.add_item(item_id, int(expected_items[item_id]))) == 0,
			"reward fixture adds exact %s quantity" % item_id,
		)
	inventory.select_slot(2)
	var canonical_before: Dictionary = inventory.serialize()
	_check(
		_total_item_count(inventory) == 58,
		"reward fixture contains the exact aggregate reward quantity",
	)

	var state := save_service.create_world(
		"Exploration-Reward-Canonical-%d" % Time.get_ticks_msec(),
		"abyss_world",
		78241639,
	)
	_world_id = str(state.get("metadata", {}).get("id", ""))
	_check(not _world_id.is_empty(), "real SaveService creates an isolated reward world")
	state["inventory"] = canonical_before.duplicate(true)
	state["exploration_rewards"] = {
		"version": 1,
		"claimed": [
			"first_discovery",
			"three_regions",
			"deep_delver",
			"rich_signal",
			"danger_scout",
			"four_depths",
			"seasoned_explorer",
			"signature_finding",
		],
	}
	_check(
		save_service.save_world(_world_id, state),
		"real SaveService writes the authoritative reward inventory",
	)
	var loaded: Dictionary = save_service.load_world(_world_id)
	_check(not loaded.is_empty(), "real SaveService reloads the reward world JSON")
	_check(
		(loaded.get("exploration_rewards", {}).get("claimed", []) as Array).size() == 8,
		"reward world JSON retains all eight claimed identities",
	)
	_check(
		restored.deserialize(loaded.get("inventory", {})),
		"InventoryService accepts the JSON-decoded reward payload",
	)
	var canonical_after: Dictionary = restored.serialize()
	_check(
		canonical_after == canonical_before,
		"SaveService JSON plus InventoryService canonicalization preserves exact slots and metadata",
	)
	_check(
		int(canonical_after.get("selected_slot", -1)) == 2,
		"canonical save roundtrip preserves the selected hotbar slot",
	)
	for item_id: String in expected_items.keys():
		_check(
			restored.count_item(item_id) == int(expected_items[item_id]),
			"canonical save roundtrip preserves exact %s quantity" % item_id,
		)
	_check(
		_total_item_count(restored) == 58,
		"canonical save roundtrip neither duplicates nor loses reward items",
	)

	if not _world_id.is_empty():
		save_service.delete_world(_world_id)
	inventory.queue_free()
	restored.queue_free()
	save_service.queue_free()
	for _frame in 8:
		await process_frame
	if failures.is_empty():
		print(
			"QA EXPLORATION REWARD INVENTORY PERSISTENCE PASS | checks=%d"
			% checks
		)
		quit(0)
		return
	for failure: String in failures:
		push_error(
			"QA EXPLORATION REWARD INVENTORY PERSISTENCE FAILURE: %s"
			% failure
		)
	print(
		"QA EXPLORATION REWARD INVENTORY PERSISTENCE FAIL | checks=%d | failures=%d"
		% [checks, failures.size()]
	)
	quit(1)


func _total_item_count(inventory: Node) -> int:
	var total := 0
	for index in int(inventory.get("slot_count")):
		total += int((inventory.get_slot(index) as Dictionary).get("count", 0))
	return total


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
