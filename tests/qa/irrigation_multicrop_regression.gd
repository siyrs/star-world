extends SceneTree

const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const ToolScript = preload("res://src/tools/tool_service.gd")
const AgricultureScript = preload("res://src/agriculture/agriculture_service.gd")
const CropRegistryScript = preload("res://src/agriculture/crop_registry.gd")
const SoilPolicyScript = preload("res://src/agriculture/soil_moisture_policy.gd")
const FurnaceRecipeRegistryScript = preload("res://src/machine/furnace_recipe_registry.gd")

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
		var key: String = block_key(position)
		var previous: String = str(blocks.get(key, "air"))
		if previous == block_id:
			return false
		blocks[key] = block_id
		return true

	func block_key(position: Vector3i) -> String:
		return "%d,%d,%d" % [position.x, position.y, position.z]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_policy_and_atomic_bucket_transform()
	await _test_manual_irrigation_and_dry_growth()
	await _test_nearby_water_and_root_crop_outputs()
	if failures.is_empty():
		print("QA IRRIGATION MULTICROP PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA IRRIGATION MULTICROP FAILURE: %s" % failure)
		print(
			"QA IRRIGATION MULTICROP FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_policy_and_atomic_bucket_transform() -> void:
	var policy = SoilPolicyScript.new()
	_check(policy.dry_block == "farmland", "soil policy preserves the legacy dry farmland block")
	_check(policy.wet_block == "farmland_wet", "soil policy defines a distinct hydrated block")
	_check(policy.horizontal_radius == 4, "irrigation scans the configured four-block radius")
	_check(policy.dry_growth_multiplier < policy.wet_growth_multiplier, "dry soil grows slower than hydrated soil")
	var crops = CropRegistryScript.new()
	_check(crops.crop_count() == 3, "crop registry exposes three production crops")
	var carrot_outputs: Array[Dictionary] = crops.get_harvest_outputs("carrot")
	_check(
		carrot_outputs.size() == 1
		and str(carrot_outputs[0].get("item_id", "")) == "carrot"
		and int(carrot_outputs[0].get("count", 0)) == 2,
		"carrot harvest uses generic merged outputs",
	)
	var inventory = InventoryScript.new()
	inventory.clear()
	inventory.add_item("water_bucket", 1)
	inventory.select_slot(0)
	_check(
		inventory.replace_slot_item(0, "water_bucket", "bucket", {}),
		"inventory supports an atomic filled-to-empty bucket transform",
	)
	_check(str(inventory.get_slot(0).get("item_id", "")) == "bucket", "slot replacement keeps the result in the exact slot")
	_check(
		not inventory.replace_slot_item(0, "water_bucket", "bucket", {}),
		"slot replacement rejects an unexpected source item without mutation",
	)


func _test_manual_irrigation_and_dry_growth() -> void:
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
	var soil := Vector3i(0, 18, 0)
	var crop := soil + Vector3i.UP
	world.set_test_block(soil, "farmland")
	agriculture.attach_world(world, inventory)
	inventory.clear()
	inventory.add_item("water_bucket", 1)
	inventory.select_slot(0)
	var watered: Dictionary = agriculture.try_interact(
		world, inventory, soil, world.get_block(soil)
	)
	_check(bool(watered.get("success", false)), "water bucket interaction hydrates dry farmland")
	_check(world.get_block(soil) == "farmland_wet", "manual irrigation updates the visible soil block")
	_check(str(inventory.get_slot(0).get("item_id", "")) == "bucket", "watering returns an empty bucket")
	_check(
		float(agriculture.get_soil_state(soil).get("manual_remaining_seconds", 0.0)) >= 179.0,
		"manual hydration duration is persisted in soil state",
	)
	agriculture.advance_time(181.0)
	_check(world.get_block(soil) == "farmland", "manual irrigation expires back to dry farmland")
	_check(not bool(agriculture.get_soil_state(soil).get("hydrated", true)), "expired soil reports a dry state")
	inventory.add_item("wheat_seeds", 1)
	inventory.select_slot(1)
	var planted: Dictionary = agriculture.try_interact(
		world, inventory, soil, world.get_block(soil)
	)
	_check(bool(planted.get("success", false)), "crops can still be planted on dry soil")
	agriculture.advance_time(30.0)
	_check(world.get_block(crop) == "wheat_stage_0", "dry soil applies the configured slower growth rate")
	world.set_test_block(soil + Vector3i(4, 0, 0), "water")
	agriculture.soil_moisture.refresh_all()
	_check(world.get_block(soil) == "farmland_wet", "nearby water converts existing soil to hydrated farmland")
	agriculture.advance_time(15.0)
	_check(world.get_block(crop) == "wheat_stage_1", "hydrated growth resumes from accumulated dry progress")
	var saved: Dictionary = agriculture.serialize()
	var saved_soils: Dictionary = saved.get("soil_moisture", {}).get("soils", {})
	_check(not saved_soils.is_empty(), "soil moisture records are included in the agriculture save contract")
	host.queue_free()
	await process_frame
	await process_frame


func _test_nearby_water_and_root_crop_outputs() -> void:
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
	var carrot_soil := Vector3i(10, 20, 0)
	var potato_soil := Vector3i(12, 20, 0)
	var water_position := Vector3i(11, 20, 3)
	world.set_test_block(carrot_soil, "farmland")
	world.set_test_block(potato_soil, "farmland")
	world.set_test_block(water_position, "water")
	agriculture.attach_world(world, inventory)
	inventory.clear()
	inventory.add_item("carrot", 2)
	inventory.add_item("potato", 2)
	inventory.select_slot(0)
	var carrot_plant: Dictionary = agriculture.try_interact(
		world, inventory, carrot_soil, world.get_block(carrot_soil)
	)
	_check(bool(carrot_plant.get("success", false)), "carrots plant using the edible crop item")
	_check(world.get_block(carrot_soil) == "farmland_wet", "nearby water hydrates carrot soil")
	agriculture.advance_time(106.0)
	var carrot_position := carrot_soil + Vector3i.UP
	_check(world.get_block(carrot_position) == "carrot_stage_3", "carrots reach their mature visual stage")
	var carrot_harvest: Dictionary = agriculture.try_interact(
		world, inventory, carrot_position, world.get_block(carrot_position)
	)
	_check(bool(carrot_harvest.get("success", false)), "mature carrots harvest through the generic crop transaction")
	_check(inventory.count_item("carrot") == 3, "carrot harvest grants two items and preserves the spare planting item")
	_check(world.get_block(carrot_position) == "carrot_stage_0", "carrot harvest automatically replants")
	inventory.select_slot(1)
	var potato_plant: Dictionary = agriculture.try_interact(
		world, inventory, potato_soil, world.get_block(potato_soil)
	)
	_check(bool(potato_plant.get("success", false)), "potatoes plant using the edible crop item")
	agriculture.advance_time(126.0)
	var potato_position := potato_soil + Vector3i.UP
	_check(world.get_block(potato_position) == "potato_stage_3", "potatoes reach their mature visual stage")
	var potato_harvest: Dictionary = agriculture.try_interact(
		world, inventory, potato_position, world.get_block(potato_position)
	)
	_check(bool(potato_harvest.get("success", false)), "mature potatoes harvest through the same crop service")
	_check(inventory.count_item("potato") == 3, "potato harvest grants two items and preserves the spare planting item")
	var furnace_recipes = FurnaceRecipeRegistryScript.new()
	var baked_recipe: Dictionary = furnace_recipes.get_recipe_for_input("potato")
	_check(str(baked_recipe.get("output", {}).get("id", "")) == "baked_potato", "potatoes connect to the furnace food chain")
	host.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
