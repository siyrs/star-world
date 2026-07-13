extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ToolScript = preload("res://src/tools/tool_service.gd")
const HarvestScript = preload("res://src/harvest/block_harvest_service.gd")
const HarvestRegistryScript = preload("res://src/harvest/block_harvest_registry.gd")
const HarvestPolicyScript = preload("res://src/harvest/block_harvest_policy.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")
const PlayerScene = preload("res://scenes/game/player.tscn")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node
	var blocks: Dictionary = {}
	var removed: Array[String] = []

	func set_test_block(position: Vector3i, block_id: String) -> void:
		blocks[_key(position)] = block_id

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(_key(position), "air"))

	func remove_block(position: Vector3i) -> String:
		var key := _key(position)
		var previous := str(blocks.get(key, "air"))
		blocks[key] = "air"
		if previous != "air":
			removed.append(previous)
		return previous

	func block_key(position: Vector3i) -> String:
		return _key(position)

	func _key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


class InteractionProbe:
	extends Node
	var allow_break := true
	var removed_count := 0

	func can_break_block(_world, _position: Vector3i, _block_id: String) -> bool:
		return allow_break

	func on_block_removed(_world, _position: Vector3i, _block_id: String) -> void:
		removed_count += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_policy_and_registry()
	await _test_progress_drop_and_durability()
	await _test_wrong_tool_and_inventory_safety()
	await _test_durability_persistence()
	await _test_runtime_composition()
	if failures.is_empty():
		print("QA TOOL HARVEST PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("QA TOOL HARVEST FAILURE: %s" % failure)
		print("QA TOOL HARVEST FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_policy_and_registry() -> void:
	var inventory = InventoryScript.new()
	var tools = ToolScript.new()
	tools.setup(inventory.registry)
	var registry = HarvestRegistryScript.new()
	var policy = HarvestPolicyScript.new()
	_check(registry.rule_count() >= 10, "harvest rules load from a dedicated registry")
	var stone: Dictionary = registry.get_profile("stone")
	var hand: Dictionary = tools.get_tool_profile("")
	var wooden_pickaxe: Dictionary = tools.get_tool_profile("wooden_pickaxe")
	var hand_stone: Dictionary = policy.evaluate(stone, hand)
	var wood_stone: Dictionary = policy.evaluate(stone, wooden_pickaxe)
	_check(not bool(hand_stone.get("can_drop", true)), "stone mined by hand does not grant a drop")
	_check(bool(wood_stone.get("can_drop", false)), "wooden pickaxe qualifies for stone drops")
	_check(
		float(wood_stone.get("duration_seconds", 99.0))
		< float(hand_stone.get("duration_seconds", 0.0)),
		"matching tools mine their preferred blocks faster",
	)
	var iron_ore: Dictionary = registry.get_profile("iron_ore")
	_check(
		not bool(policy.evaluate(iron_ore, wooden_pickaxe).get("can_drop", true)),
		"wooden pickaxe cannot harvest iron ore",
	)
	_check(
		bool(policy.evaluate(iron_ore, tools.get_tool_profile("stone_pickaxe")).get("can_drop", false)),
		"stone pickaxe reaches the iron ore tier",
	)
	var diamond_ore: Dictionary = registry.get_profile("diamond_ore")
	_check(
		not bool(policy.evaluate(diamond_ore, tools.get_tool_profile("stone_pickaxe")).get("can_drop", true)),
		"stone pickaxe cannot harvest diamond ore",
	)
	_check(
		bool(policy.evaluate(diamond_ore, tools.get_tool_profile("iron_pickaxe")).get("can_drop", false)),
		"iron pickaxe reaches the diamond ore tier",
	)
	var wood: Dictionary = registry.get_profile("wood")
	_check(
		float(policy.evaluate(wood, tools.get_tool_profile("wooden_axe")).get("duration_seconds", 99.0))
		< float(policy.evaluate(wood, wooden_pickaxe).get("duration_seconds", 0.0)),
		"axes outperform pickaxes on wooden blocks",
	)
	_check(
		not bool(policy.evaluate(registry.get_profile("bedrock"), tools.get_tool_profile("diamond_pickaxe")).get("breakable", true)),
		"bedrock remains unbreakable regardless of tool tier",
	)


func _test_progress_drop_and_durability() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var tools = ToolScript.new()
	var interactions = InteractionProbe.new()
	var harvest = HarvestScript.new()
	var world = FakeWorld.new()
	for node in [inventory, tools, interactions, harvest, world]:
		host.add_child(node)
	await process_frame
	tools.setup(inventory.registry)
	harvest.setup(tools, interactions)
	inventory.clear()
	inventory.add_item("wooden_pickaxe", 1)
	inventory.select_slot(0)
	var position := Vector3i(2, 20, -3)
	world.set_test_block(position, "stone")
	var preview: Dictionary = harvest.get_preview("stone", inventory)
	var duration := float(preview.get("duration_seconds", 1.0))
	var progress_events := 0
	harvest.harvest_progress_changed.connect(
		func(snapshot: Dictionary) -> void:
			if not snapshot.is_empty():
				progress_events += 1
	)
	var partial: Dictionary = harvest.advance(world, inventory, position, "stone", duration * 0.45)
	_check(str(partial.get("status", "")) == "progress", "harvest begins as a timed action")
	_check(world.get_block(position) == "stone", "a partial hold does not instantly remove the block")
	var completed: Dictionary = harvest.advance(world, inventory, position, "stone", duration)
	_check(str(completed.get("status", "")) == "completed", "holding long enough completes harvesting")
	_check(world.get_block(position) == "air", "completed harvesting commits the world mutation")
	_check(inventory.count_item("cobblestone") == 1, "stone follows the cobblestone drop rule")
	var tool_slot: Dictionary = inventory.get_slot(0)
	_check(
		int(tool_slot.get("metadata", {}).get("durability", 60)) == 59,
		"successful harvesting consumes exactly one durability",
	)
	_check(progress_events >= 2, "progress snapshots are emitted for the experience layer")
	_check(interactions.removed_count == 1, "block removal cleanup runs through interaction coordination")
	inventory.update_slot_metadata(0, {"durability": 1})
	world.set_test_block(position, "stone")
	var broken_events := 0
	tools.item_broken.connect(
		func(_slot: int, _item_id: String, _name: String, _reason: String) -> void:
			broken_events += 1
	)
	harvest.harvest_immediately(world, inventory, position, "stone")
	_check(broken_events == 1, "a tool emits one break event when durability reaches zero")
	_check(inventory.get_slot(0).is_empty(), "broken tools are removed from their exact slot")
	host.queue_free()
	await process_frame
	await process_frame


func _test_wrong_tool_and_inventory_safety() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryScript.new()
	var tools = ToolScript.new()
	var interactions = InteractionProbe.new()
	var harvest = HarvestScript.new()
	var world = FakeWorld.new()
	for node in [inventory, tools, interactions, harvest, world]:
		host.add_child(node)
	await process_frame
	tools.setup(inventory.registry)
	harvest.setup(tools, interactions)
	inventory.clear()
	inventory.add_item("wooden_pickaxe", 1)
	inventory.select_slot(0)
	var position := Vector3i(4, 18, 1)
	world.set_test_block(position, "diamond_ore")
	var result: Dictionary = harvest.harvest_immediately(world, inventory, position, "diamond_ore")
	_check(str(result.get("status", "")) == "completed", "wrong-tier tools may still break a block slowly")
	_check(not bool(result.get("drop_granted", true)), "wrong-tier harvesting never grants protected ore drops")
	_check(inventory.count_item("diamond") == 0, "diamond is not duplicated by an insufficient tool")
	_check(
		int(inventory.get_slot(0).get("metadata", {}).get("durability", 60)) == 59,
		"wrong-tier block breaking still consumes tool durability",
	)
	var full_inventory = InventoryScript.new(9, 9)
	var full_tools = ToolScript.new()
	var full_harvest = HarvestScript.new()
	host.add_child(full_inventory)
	host.add_child(full_tools)
	host.add_child(full_harvest)
	await process_frame
	full_tools.setup(full_inventory.registry)
	full_harvest.setup(full_tools, interactions)
	full_inventory.clear()
	full_inventory.add_item("wooden_pickaxe", 1)
	full_inventory.add_item("dirt", 64 * 8)
	full_inventory.select_slot(0)
	world.set_test_block(position, "stone")
	var rejected: Dictionary = full_harvest.harvest_immediately(world, full_inventory, position, "stone")
	_check(str(rejected.get("reason", "")) == "inventory_full", "full inventories reject collectible harvests")
	_check(world.get_block(position) == "stone", "inventory rejection preserves the world block")
	host.queue_free()
	await process_frame
	await process_frame


func _test_durability_persistence() -> void:
	var inventory = InventoryScript.new()
	inventory.clear()
	inventory.add_item("iron_pickaxe", 1)
	inventory.update_slot_metadata(0, {"durability": 42, "custom_name": "星星的镐"})
	var saved: Dictionary = inventory.serialize()
	var restored = InventoryScript.new()
	_check(restored.deserialize(saved), "inventory with durable metadata deserializes")
	var restored_slot: Dictionary = restored.get_slot(0)
	_check(
		int(restored_slot.get("metadata", {}).get("durability", 0)) == 42,
		"remaining durability survives the existing inventory save contract",
	)
	_check(
		str(restored_slot.get("metadata", {}).get("custom_name", "")) == "星星的镐",
		"durability updates preserve unrelated item metadata",
	)
	var tools = ToolScript.new()
	tools.setup(restored.registry)
	_check(
		int(tools.get_slot_context(restored_slot).get("remaining_durability", 0)) == 42,
		"tool context reads restored durability without a new save schema",
	)


func _test_runtime_composition() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	_check(hub.get_node_or_null("ToolService") != null, "service hub mounts the tool domain")
	_check(hub.get_node_or_null("BlockHarvestService") != null, "service hub mounts the harvest domain")
	_check(hub.get("harvest_progress_overlay") != null, "service hub mounts the harvest experience overlay")
	var player = PlayerScene.instantiate()
	_check(player.has_method("bind_tool_service"), "player scene exposes the tool service port")
	_check(player.has_method("bind_harvest_service"), "player scene exposes the harvest service port")
	player.queue_free()
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	hub.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
