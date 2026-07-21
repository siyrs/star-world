extends SceneTree

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const DoorPolicyScript = preload("res://src/block/block_door_policy.gd")
const DoorServiceScript = preload("res://src/interaction/block_door_interaction_service.gd")
const ShapeGeometryScript = preload("res://src/block/block_shape_geometry.gd")
const PlacementPolicyScript = preload("res://src/interaction/placement_preview_policy.gd")
const HarvestRegistryScript = preload("res://src/harvest/block_harvest_registry.gd")
const HarvestServiceScript = preload("res://src/harvest/block_harvest_service.gd")
const ToolServiceScript = preload("res://src/tools/tool_service.gd")
const InventoryServiceScript = preload("res://src/inventory/inventory_service.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node
	var blocks: Dictionary = {}
	var fail_next_position := Vector3i(2147483647,2147483647,2147483647)

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(_key(position), "air"))

	func set_block(position: Vector3i, block_id: String) -> bool:
		if position == fail_next_position:
			fail_next_position = Vector3i(2147483647,2147483647,2147483647)
			return false
		var old_id := get_block(position)
		if old_id == block_id:
			return false
		if block_id == "air":
			blocks.erase(_key(position))
		else:
			blocks[_key(position)] = block_id
		return true

	func remove_block(position: Vector3i) -> String:
		var old_id := get_block(position)
		if old_id == "air":
			return "air"
		blocks.erase(_key(position))
		return old_id

	func _key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x,position.y,position.z]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_and_policy()
	_test_geometry_and_preview()
	await _test_atomic_place_toggle_and_harvest()
	await _test_production_composition()
	if failures.is_empty():
		print("QA DOUBLE DOOR PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA DOUBLE DOOR FAILURE: %s" % failure)
		print("QA DOUBLE DOOR FAIL | checks=%d | failures=%d" % [checks,failures.size()])
		quit(1)


func _test_catalog_and_policy() -> void:
	_check(BlockRegistryScript.get_numeric_id("oak_door") == 23,"legacy oak_door numeric ID remains stable")
	var variants: Array[String] = []
	variants.append_array(DoorPolicyScript.CLOSED_LOWER)
	variants.append_array(DoorPolicyScript.CLOSED_UPPER)
	variants.append_array(DoorPolicyScript.OPEN_LOWER)
	variants.append_array(DoorPolicyScript.OPEN_UPPER)
	_check(variants.size() == 16,"door policy exposes all orientation, half and open states")
	_check(variants.duplicate().size() == variants.size(),"door state table remains bounded")
	for block_id: String in variants:
		_check(BlockRegistryScript.has_block(block_id),"door variant is registered: %s" % block_id)
		_check(BlockRegistryScript.get_item_id(block_id) == "oak_door","door variant drops the canonical item: %s" % block_id)
		_check(DoorPolicyScript.supports(block_id),"door policy recognizes variant: %s" % block_id)
	for quarter in 4:
		var lower := DoorPolicyScript.closed_lower_for_quarters(quarter)
		var upper := DoorPolicyScript.upper_variant(lower)
		_check(DoorPolicyScript.rotation_quarters(lower) == quarter,"closed lower preserves orientation %d" % quarter)
		_check(DoorPolicyScript.is_valid_pair(lower,upper),"closed pair is valid for orientation %d" % quarter)
		_check(DoorPolicyScript.is_valid_pair(DoorPolicyScript.toggled_variant(lower),DoorPolicyScript.toggled_variant(upper)),"open pair is valid for orientation %d" % quarter)
	var harvest_registry = HarvestRegistryScript.new()
	var open_profile: Dictionary = harvest_registry.get_profile("oak_door_upper_open_west")
	_check(str(open_profile.get("preferred_tool","")) == "axe","door variants inherit the canonical axe harvest rule")
	_check(str(open_profile.get("drop_item","")) == "oak_door","upper/open variants retain one canonical drop")


func _test_geometry_and_preview() -> void:
	var closed_box := DoorPolicyScript.local_box("oak_door")
	var open_box := DoorPolicyScript.local_box("oak_door_open")
	_check(closed_box.size.is_equal_approx(Vector3(1.0,1.0,0.125)),"closed south door blocks the centered doorway plane")
	_check(open_box.position.x == 0.0 and open_box.size.is_equal_approx(Vector3(0.125,1.0,1.0)),"open south door rotates to the cell edge")
	_check(not ShapeGeometryScript.is_full_cube("oak_door"),"doors enter the shared partial geometry pipeline")
	_check(ShapeGeometryScript.get_local_boxes("oak_door_open_north").size() == 1,"each persisted half uses one bounded geometry box")
	var policy = PlacementPolicyScript.new()
	var focus := {
		"type":"block",
		"hit_position":[0,0,0],
		"hit_block_id":"stone",
		"placement_position":[1,1,0],
		"placement_target_block_id":"air",
		"placement_upper_block_id":"air",
		"placement_support_block_id":"stone",
	}
	var valid: Dictionary = policy.evaluate(focus,"oak_door")
	_check(bool(valid.get("valid",false)),"double door preview accepts two empty cells above solid support")
	_check((valid.get("placement_boxes",[]) as Array).size() == 2,"double door preview renders lower and upper boxes")
	_check((valid.get("placement_companion_position",[]) as Array) == [1,2,0],"preview exposes the upper companion position")
	var occupied_focus := focus.duplicate(true)
	occupied_focus["placement_upper_block_id"] = "stone"
	var occupied: Dictionary = policy.evaluate(occupied_focus,"oak_door")
	_check(str(occupied.get("reason","")) == "door_upper_occupied","occupied upper cells reject placement before commit")
	var unsupported_focus := focus.duplicate(true)
	unsupported_focus["placement_support_block_id"] = "air"
	var unsupported: Dictionary = policy.evaluate(unsupported_focus,"oak_door")
	_check(str(unsupported.get("reason","")) == "door_support_missing","missing support rejects placement before commit")
	var upper_overlap := AABB(Vector3(1.2,2.1,0.44),Vector3(0.3,0.5,0.1))
	var overlap: Dictionary = policy.evaluate(focus,"oak_door",upper_overlap)
	_check(str(overlap.get("reason","")) == "player_overlap","player overlap checks include the upper door half")


func _test_atomic_place_toggle_and_harvest() -> void:
	var host := Node.new()
	root.add_child(host)
	var inventory = InventoryServiceScript.new()
	var tools = ToolServiceScript.new()
	var doors = DoorServiceScript.new()
	var harvest = HarvestServiceScript.new()
	for node: Node in [inventory,tools,doors,harvest]:
		host.add_child(node)
	await process_frame
	tools.call("setup",inventory.registry)
	harvest.call("setup",tools,null,doors)
	inventory.add_item("oak_door",2)
	inventory.select_slot(0)
	var world := FakeWorld.new()
	host.add_child(world)
	var lower := Vector3i(4,5,6)
	var upper := lower+Vector3i.UP
	world.set_block(lower+Vector3i.DOWN,"stone")
	var placed: Dictionary = doors.call("try_place_block",world,inventory,lower,"oak_door_east","air")
	_check(bool(placed.get("success",false)),"door service atomically places a supported double door")
	_check(world.get_block(lower) == "oak_door_east" and world.get_block(upper) == "oak_door_upper_east","placement commits matching lower and upper variants")
	_check(inventory.count_item("oak_door") == 1,"one double door placement consumes exactly one item")
	var opened: Dictionary = doors.call("try_interact",world,inventory,upper,world.get_block(upper))
	_check(bool(opened.get("success",false)) and bool(opened.get("opened",false)),"right click on either half opens the complete door")
	_check(world.get_block(lower) == "oak_door_open_east" and world.get_block(upper) == "oak_door_upper_open_east","open toggle updates both persisted halves")
	world.fail_next_position = upper
	var failed_toggle: Dictionary = doors.call("try_interact",world,inventory,lower,world.get_block(lower))
	_check(not bool(failed_toggle.get("success",true)),"upper write failure rejects the toggle")
	_check(world.get_block(lower) == "oak_door_open_east" and world.get_block(upper) == "oak_door_upper_open_east","failed toggle rolls the lower half back to its original state")
	var harvest_result: Dictionary = harvest.call("harvest_immediately",world,inventory,upper,world.get_block(upper))
	_check(str(harvest_result.get("status","")) == "completed","harvesting the upper half completes through the production harvest service")
	_check(world.get_block(lower) == "air" and world.get_block(upper) == "air","harvesting either half removes the complete pair")
	_check(inventory.count_item("oak_door") == 2,"paired removal grants exactly one canonical door item")
	_check((harvest_result.get("removed_positions",[]) as Array).size() == 2,"harvest evidence records both removed cells")
	world.set_block(lower+Vector3i.DOWN,"stone")
	world.set_block(upper,"stone")
	var count_before := inventory.count_item("oak_door")
	var rejected: Dictionary = doors.call("try_place_block",world,inventory,lower,"oak_door","air")
	_check(str(rejected.get("reason","")) == "door_upper_occupied","runtime placement rejects an occupied upper cell")
	_check(world.get_block(lower) == "air" and world.get_block(upper) == "stone","rejected placement leaves both world cells unchanged")
	_check(inventory.count_item("oak_door") == count_before,"rejected placement consumes no item")
	world.set_block(upper,"air")
	inventory.select_slot(8)
	var raced: Dictionary = doors.call("try_place_block",world,inventory,lower,"oak_door","air")
	_check(str(raced.get("reason","")) == "door_inventory_race","empty selected slot triggers the inventory race rollback")
	_check(world.get_block(lower) == "air" and world.get_block(upper) == "air","inventory race restores both cells")
	host.queue_free()
	await process_frame
	await process_frame


func _test_production_composition() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	for _frame in 3:
		await process_frame
	var doors: Node = hub.get("door_interaction_service") as Node
	_check(doors != null,"production ServiceHub exposes the door structure service")
	_check(hub.get_node_or_null("DoorInteraction") == doors,"door structure service keeps a stable production node path")
	_check(hub.block_harvest_service.get("structure_service") == doors,"production harvest delegates linked removal to the door service")
	_check(hub.block_interaction.get_extension_count() >= 2,"door interaction joins the existing extension pipeline")
	if hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	hub.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
