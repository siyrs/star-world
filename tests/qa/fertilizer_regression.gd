extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ToolScript = preload("res://src/tools/tool_service.gd")
const AgricultureScript = preload(
	"res://src/agriculture/fertilizable_agriculture_service.gd"
)
const FertilizerRegistryScript = preload(
	"res://src/agriculture/fertilizer_registry.gd"
)
const FertilizerPolicyScript = preload(
	"res://src/agriculture/fertilizer_policy.gd"
)
const CropRegistryScript = preload("res://src/agriculture/crop_registry.gd")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node
	var blocks: Dictionary = {}
	var fail_next_set := false

	func set_test_block(position: Vector3i, block_id: String) -> void:
		blocks[block_key(position)] = block_id

	func get_block(position: Vector3i) -> String:
		return str(blocks.get(block_key(position), "air"))

	func set_block(position: Vector3i, block_id: String) -> bool:
		if fail_next_set:
			fail_next_set = false
			return false
		var key := block_key(position)
		var previous := str(blocks.get(key, "air"))
		if previous == block_id:
			return false
		blocks[key] = block_id
		return true

	func block_key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_registry_and_policy()
	await _test_transaction_and_maturity_guard()
	await _test_world_failure_rolls_back_compost()
	await _test_composition_root()
	if failures.is_empty():
		print("QA FERTILIZER PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA FERTILIZER FAILURE: %s" % failure)
		print("QA FERTILIZER FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_registry_and_policy() -> void:
	var registry = FertilizerRegistryScript.new()
	var policy = FertilizerPolicyScript.new()
	var crops = CropRegistryScript.new()
	_check(registry.profile_count() == 1, "fertilizer registry loads the first production profile")
	var compost: Dictionary = registry.get_profile("compost")
	_check(str(compost.get("name", "")) == "堆肥", "compost exposes a player-facing name")
	_check(int(compost.get("stage_advances", 0)) == 1, "compost advances exactly one growth stage")
	var wheat: Dictionary = crops.get_crop("wheat")
	var growing: Dictionary = policy.evaluate(compost, wheat, 0)
	_check(bool(growing.get("success", false)), "fertilizer policy accepts an immature crop")
	_check(int(growing.get("target_stage", -1)) == 1, "fertilizer policy computes the next stage")
	var mature: Dictionary = policy.evaluate(compost, wheat, 3)
	_check(str(mature.get("reason", "")) == "crop_mature", "fertilizer policy protects mature crops")


func _test_transaction_and_maturity_guard() -> void:
	var host := Node.new()
	root.add_child(host)
	var world = FakeWorld.new()
	var inventory = InventoryScript.new()
	var tools = ToolScript.new()
	var agriculture = AgricultureScript.new()
	for node in [world, inventory, tools, agriculture]:
		host.add_child(node)
	await process_frame
	tools.setup(inventory.registry)
	agriculture.setup(inventory.registry, tools)
	var soil := Vector3i(2, 20, -3)
	var crop := soil + Vector3i.UP
	world.set_test_block(soil, "farmland_wet")
	world.set_test_block(crop, "wheat_stage_0")
	agriculture.deserialize(_crop_state("wheat", crop, 0, "farmland_wet", soil))
	agriculture.attach_world(world, inventory)
	inventory.clear()
	inventory.add_item("compost", 4, {"batch":"qa"})
	inventory.select_slot(0)
	var event_counter := {"count": 0}
	agriculture.crop_fertilized.connect(
		func(_position, _crop_id, _item_id, _from_stage, _to_stage):
			event_counter["count"] = int(event_counter.get("count", 0)) + 1
	)
	for expected_stage in [1, 2, 3]:
		var before_count := inventory.count_item("compost")
		var current_block := world.get_block(crop)
		var result: Dictionary = agriculture.try_interact(world, inventory, crop, current_block)
		_check(bool(result.get("success", false)), "compost advances wheat to stage %d" % expected_stage)
		_check(world.get_block(crop) == "wheat_stage_%d" % expected_stage, "world publishes fertilized stage %d" % expected_stage)
		_check(inventory.count_item("compost") == before_count - 1, "successful fertilization consumes one compost")
		_check(int(agriculture.get_crop_state(crop).get("stage", -1)) == expected_stage, "domain state matches fertilized stage %d" % expected_stage)
	_check(int(event_counter.get("count", 0)) == 3, "each successful application emits one fertilizer event")
	var mature_count := inventory.count_item("compost")
	var mature_result: Dictionary = agriculture.try_interact(
		world, inventory, crop, world.get_block(crop)
	)
	_check(str(mature_result.get("reason", "")) == "crop_mature", "mature crops reject extra compost")
	_check(inventory.count_item("compost") == mature_count, "mature rejection does not consume compost")
	_check(
		str(agriculture.get_interaction_hint("wheat_stage_3", "compost")).contains("先收获"),
		"mature compost hint tells the player to harvest first",
	)
	var saved: Dictionary = agriculture.serialize()
	var saved_crops: Dictionary = saved.get("crops", {})
	var saved_crop: Dictionary = saved_crops.get("crop@2,21,-3", {})
	_check(int(saved_crop.get("stage", -1)) == 3, "fertilized crop stage is serialized")
	host.queue_free()
	await process_frame
	await process_frame


func _test_world_failure_rolls_back_compost() -> void:
	var host := Node.new()
	root.add_child(host)
	var world = FakeWorld.new()
	var inventory = InventoryScript.new()
	var tools = ToolScript.new()
	var agriculture = AgricultureScript.new()
	for node in [world, inventory, tools, agriculture]:
		host.add_child(node)
	await process_frame
	tools.setup(inventory.registry)
	agriculture.setup(inventory.registry, tools)
	var soil := Vector3i(7, 18, 4)
	var crop := soil + Vector3i.UP
	world.set_test_block(soil, "farmland_wet")
	world.set_test_block(crop, "carrot_stage_0")
	agriculture.deserialize(_crop_state("carrot", crop, 0, "farmland_wet", soil))
	agriculture.attach_world(world, inventory)
	inventory.clear()
	inventory.add_item("compost", 1, {"batch":"rollback"})
	inventory.select_slot(0)
	world.fail_next_set = true
	var result: Dictionary = agriculture.try_interact(
		world, inventory, crop, world.get_block(crop)
	)
	_check(str(result.get("reason", "")) == "fertilizer_commit_failed", "world write failures reject fertilizer commits")
	_check(world.get_block(crop) == "carrot_stage_0", "failed fertilizer commit leaves the crop unchanged")
	_check(inventory.count_item("compost") == 1, "failed fertilizer commit restores compost")
	_check(
		str(inventory.get_slot(0).get("metadata", {}).get("batch", "")) == "rollback",
		"fertilizer rollback preserves item metadata",
	)
	_check(int(agriculture.get_crop_state(crop).get("stage", -1)) == 0, "failed fertilizer commit leaves domain state unchanged")
	var non_crop: Dictionary = agriculture.try_interact(world, inventory, Vector3i.ZERO, "stone")
	_check(not bool(non_crop.get("handled", false)), "fertilizer does not claim unrelated world interactions")
	host.queue_free()
	await process_frame
	await process_frame


func _test_composition_root() -> void:
	var hub = ServiceHubScene.instantiate()
	root.add_child(hub)
	await process_frame
	await process_frame
	var agriculture = hub.get("agriculture_service")
	_check(agriculture != null, "composition root mounts agriculture")
	_check(
		agriculture != null and agriculture.has_method("get_fertilizer_profile"),
		"composition root selects the fertilizable agriculture implementation",
	)
	var compost_profile: Dictionary = {}
	if agriculture != null and agriculture.has_method("get_fertilizer_profile"):
		compost_profile = agriculture.call("get_fertilizer_profile", "compost")
	_check(not compost_profile.is_empty(), "runtime agriculture exposes the compost profile")
	_check(
		agriculture != null and agriculture.has_signal("crop_fertilized"),
		"runtime agriculture exposes fertilizer feedback events",
	)
	if hub.get("audio_service") != null and hub.audio_service.has_method("shutdown"):
		hub.audio_service.shutdown()
	hub.queue_free()
	await process_frame
	await process_frame


func _crop_state(
	crop_id: String,
	crop_position: Vector3i,
	stage: int,
	soil_block: String,
	soil_position: Vector3i
) -> Dictionary:
	return {
		"version": 2,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"crops": {
			"crop@%d,%d,%d" % [crop_position.x, crop_position.y, crop_position.z]: {
				"crop_id": crop_id,
				"position": [crop_position.x, crop_position.y, crop_position.z],
				"stage": stage,
				"elapsed_seconds": 0.0,
			}
		},
		"soil_moisture": {
			"version": 1,
			"soils": {
				"soil@%d,%d,%d" % [soil_position.x, soil_position.y, soil_position.z]: {
					"position": [soil_position.x, soil_position.y, soil_position.z],
					"block_id": soil_block,
					"manual_remaining_seconds": 0.0,
				}
			},
		},
	}


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
