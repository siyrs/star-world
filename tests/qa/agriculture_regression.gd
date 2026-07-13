extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ToolScript = preload("res://src/tools/tool_service.gd")
const AgricultureScript = preload("res://src/agriculture/agriculture_service.gd")
const CropRegistryScript = preload("res://src/agriculture/crop_registry.gd")
const HarvestRegistryScript = preload("res://src/harvest/block_harvest_registry.gd")
const HarvestPolicyScript = preload("res://src/harvest/block_harvest_policy.gd")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node
	var blocks: Dictionary = {}

	func set_test_block(position: Vector3i, block_id: String) -> void:
		blocks[block_key(position)] = block_id

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(block_key(position), "air"))

	func set_block(position: Vector3i, block_id: String) -> bool:
		var key := block_key(position)
		var previous := str(blocks.get(key, "air"))
		if previous == block_id:
			return false
		blocks[key] = block_id
		return true

	func remove_block(position: Vector3i) -> String:
		var previous := get_block(position)
		if previous == "air":
			return "air"
		blocks[block_key(position)] = "air"
		return previous

	func block_key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_registry_and_shovel_policy()
	await _test_till_plant_grow_harvest()
	await _test_inventory_and_removal_safety()
	await _test_runtime_composition_and_migration()
	if failures.is_empty():
		print("QA AGRICULTURE PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA AGRICULTURE FAILURE: %s" % failure)
		print("QA AGRICULTURE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_registry_and_shovel_policy() -> void:
	var inventory = InventoryScript.new()
	var tools = ToolScript.new()
	tools.setup(inventory.registry)
	var crops = CropRegistryScript.new()
	var harvest_registry = HarvestRegistryScript.new()
	var harvest_policy = HarvestPolicyScript.new()
	_check(crops.crop_count() == 1, "crop registry loads the first production crop")
	var wheat: Dictionary = crops.get_crop("wheat")
	_check(str(wheat.get("seed_item", "")) == "wheat_seeds", "wheat declares its seed item")
	_check(Array(wheat.get("stage_blocks", [])).size() == 4, "wheat exposes four readable growth stages")
	_check(str(tools.get_tool_profile("wooden_shovel").get("tool_type", "")) == "shovel", "shovels are first-class tools")
	_check(str(tools.get_tool_profile("wooden_hoe").get("tool_type", "")) == "hoe", "hoes are first-class tools")
	var dirt: Dictionary = harvest_registry.get_profile("dirt")
	var hand_result: Dictionary = harvest_policy.evaluate(dirt, tools.get_tool_profile(""))
	var shovel_result: Dictionary = harvest_policy.evaluate(
		dirt, tools.get_tool_profile("wooden_shovel")
	)
	_check(
		float(shovel_result.get("duration_seconds", 99.0))
		< float(hand_result.get("duration_seconds", 0.0)),
		"a matching shovel harvests soil faster than hand",
	)
	_check(BlockRegistryScript.has_block("farmland"), "farmland is a registered world block")
	_check(
		str(BlockRegistryScript.get_definition("wheat_stage_3").get("shape", "")) == "crop",
		"mature wheat uses the lightweight crop mesh contract",
	)


func _test_till_plant_grow_harvest() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var tools = ToolScript.new()
	var agriculture = AgricultureScript.new()
	var world = FakeWorld.new()
	for node in [inventory, tools, agriculture, world]:
		host.add_child(node)
	await process_frame
	tools.setup(inventory.registry)
	agriculture.setup(inventory.registry, tools)
	agriculture.attach_world(world, inventory)
	inventory.clear()
	inventory.add_item("wooden_hoe", 1)
	inventory.add_item("wheat_seeds", 3)
	inventory.select_slot(0)
	var soil := Vector3i(2, 20, -3)
	var crop := soil + Vector3i.UP
	world.set_test_block(soil, "grass")
	var till_result: Dictionary = agriculture.try_interact(world, inventory, soil, "grass")
	_check(bool(till_result.get("success", false)), "right-click agriculture contract tills grass")
	_check(world.get_block(soil) == "farmland", "tilling commits farmland to the world")
	_check(
		int(inventory.get_slot(0).get("metadata", {}).get("durability", 60)) == 59,
		"tilling consumes exactly one hoe durability",
	)
	inventory.select_slot(1)
	var plant_result: Dictionary = agriculture.try_interact(world, inventory, soil, "farmland")
	_check(bool(plant_result.get("success", false)), "seeds plant on valid farmland")
	_check(world.get_block(crop) == "wheat_stage_0", "planting publishes the first visible crop stage")
	_check(inventory.count_item("wheat_seeds") == 2, "planting consumes one seed")
	_check(agriculture.get_crop_count() == 1, "agriculture owns one position-based crop state")
	var early_result: Dictionary = agriculture.try_interact(
		world, inventory, crop, world.get_block(crop)
	)
	_check(str(early_result.get("reason", "")) == "crop_growing", "immature crops explain why harvest is unavailable")
	agriculture.advance_time(106.0)
	_check(world.get_block(crop) == "wheat_stage_3", "bounded time advancement reaches mature wheat")
	var harvest_result: Dictionary = agriculture.try_interact(
		world, inventory, crop, world.get_block(crop)
	)
	_check(bool(harvest_result.get("success", false)), "mature wheat can be harvested")
	_check(inventory.count_item("wheat") == 1, "harvest grants wheat produce")
	_check(inventory.count_item("wheat_seeds") == 4, "harvest returns enough seeds for expansion")
	_check(world.get_block(crop) == "wheat_stage_0", "harvest automatically replants the crop")
	agriculture.advance_time(26.0)
	_check(world.get_block(crop) == "wheat_stage_1", "growth resumes after automatic replanting")
	var saved: Dictionary = agriculture.serialize()
	var restored_world = FakeWorld.new()
	var restored = AgricultureScript.new()
	host.add_child(restored_world)
	host.add_child(restored)
	await process_frame
	restored_world.set_test_block(soil, "farmland")
	restored.setup(inventory.registry, tools)
	_check(restored.deserialize(saved), "crop state deserializes")
	restored.attach_world(restored_world, inventory)
	_check(restored.get_crop_count() == 1, "restored agriculture keeps the crop record")
	_check(restored_world.get_block(crop) == "wheat_stage_1", "restored crop stage is synchronized into the world")
	host.queue_free()
	await process_frame
	await process_frame


func _test_inventory_and_removal_safety() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new(9, 9)
	var tools = ToolScript.new()
	var agriculture = AgricultureScript.new()
	var world = FakeWorld.new()
	for node in [inventory, tools, agriculture, world]:
		host.add_child(node)
	await process_frame
	tools.setup(inventory.registry)
	agriculture.setup(inventory.registry, tools)
	var soil := Vector3i(4, 18, 1)
	var crop := soil + Vector3i.UP
	world.set_test_block(soil, "farmland")
	world.set_test_block(crop, "wheat_stage_3")
	agriculture.deserialize(
		{
			"saved_at_unix": int(Time.get_unix_time_from_system()),
			"crops": {
				"crop@4,19,1": {
					"crop_id": "wheat",
					"position": [4, 19, 1],
					"stage": 3,
					"elapsed_seconds": 0.0,
				}
			},
		}
	)
	agriculture.attach_world(world, inventory)
	inventory.clear()
	inventory.add_item("dirt", 64 * 9)
	var rejected: Dictionary = agriculture.try_interact(world, inventory, crop, "wheat_stage_3")
	_check(str(rejected.get("reason", "")) == "inventory_full", "full inventories reject crop harvest")
	_check(world.get_block(crop) == "wheat_stage_3", "failed harvest keeps the crop mature")
	_check(inventory.count_item("wheat") == 0, "failed harvest does not duplicate produce")
	agriculture.on_block_removed(world, soil, "farmland")
	_check(agriculture.get_crop_count() == 0, "breaking farmland removes its owned crop state")
	_check(world.get_block(crop) == "air", "breaking farmland removes the unsupported crop block")
	host.queue_free()
	await process_frame
	await process_frame


func _test_runtime_composition_and_migration() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	_check(hub.get_node_or_null("AgricultureService") != null, "service hub mounts the agriculture domain")
	_check(hub.get("agriculture_service") != null, "composition root exposes agriculture for diagnostics and saves")
	_check(
		int(hub.block_interaction.call("get_extension_count")) >= 1,
		"agriculture registers through the generic interaction extension port",
	)
	var migrated: Dictionary = hub.save_service.call(
		"_migrate", {"save_version": 2, "metadata": {}, "inventory": {}}
	)
	_check(migrated.get("agriculture", null) is Dictionary, "old saves migrate an empty agriculture state")
	var state: Dictionary = hub.save_service.create_world(
		"agriculture-regression-%d" % Time.get_ticks_msec(), "star_continent", 31337
	)
	_check(state.get("agriculture", null) is Dictionary, "new worlds include agriculture in the atomic state")
	if not state.is_empty():
		hub.save_service.delete_world(str(state.get("metadata", {}).get("id", "")))
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	hub.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
