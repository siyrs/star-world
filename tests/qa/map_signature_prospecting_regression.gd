extends SceneTree

const MapProfileCatalogScript = preload("res://src/world/map_profile_catalog.gd")
const ResourceRegistryScript = preload("res://src/world/resource_distribution_registry.gd")
const EcologyRegistryScript = preload("res://src/entity/creature_ecology_registry.gd")
const ProspectingRegistryScript = preload("res://src/exploration/prospecting_registry.gd")
const ProspectingServiceScript = preload("res://src/exploration/prospecting_service.gd")
const JournalRegistryScript = preload("res://src/exploration/exploration_journal_registry.gd")
const JournalPolicyScript = preload("res://src/exploration/exploration_journal_policy.gd")
const RewardRegistryScript = preload("res://src/exploration/exploration_milestone_reward_registry.gd")
const ItemRegistryScript = preload("res://src/inventory/item_registry.gd")
const InventoryScript = preload("res://src/inventory/inventory_service.gd")
const CraftingScript = preload("res://src/crafting/crafting_service.gd")

const TOOL_BY_PROFILE := {
	"star_continent":"verdant_prospecting_kit",
	"desert_ruins":"ruin_prospecting_kit",
	"frozen_wastes":"frost_prospecting_kit",
	"sky_islands":"sky_prospecting_kit",
	"abyss_world":"abyss_prospecting_kit",
}
const MATERIAL_BY_PROFILE := {
	"star_continent":"verdant_resonance",
	"desert_ruins":"ruin_sun_glass",
	"frozen_wastes":"frost_heart_crystal",
	"sky_islands":"sky_wind_crystal",
	"abyss_world":"abyss_cinder",
}

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node
	var profile_id := "star_continent"

	func world_to_block(position: Vector3) -> Vector3i:
		return Vector3i(floori(position.x), floori(position.y), floori(position.z))

	func block_to_chunk(position: Vector3i) -> Vector2i:
		return Vector2i(floori(float(position.x) / 16.0), floori(float(position.z) / 16.0))

	func get_initial_block(position: Vector3i) -> String:
		if posmod(position.x + position.y + position.z, 19) == 0:
			return "diamond_ore"
		if posmod(position.x * 2 + position.z - position.y, 11) == 0:
			return "gold_ore"
		if posmod(position.x - position.z + position.y, 7) == 0:
			return "iron_ore"
		if posmod(position.x + position.z * 2 + position.y, 5) == 0:
			return "coal_ore"
		return "stone"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_shared_map_catalog()
	_test_signature_rules_and_rewards()
	await _test_calibrated_tool_runtime()
	await _test_calibrated_recipe_round_trip()
	if failures.is_empty():
		print("QA MAP SIGNATURE PROSPECTING PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA MAP SIGNATURE PROSPECTING FAILURE: %s" % failure)
		print("QA MAP SIGNATURE PROSPECTING FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_shared_map_catalog() -> void:
	var expected := MapProfileCatalogScript.get_ids()
	_check(expected == ["star_continent", "desert_ruins", "frozen_wastes", "sky_islands", "abyss_world"], "shared map catalog preserves the production map order")
	var resource_ids := ResourceRegistryScript.new().get_profile_ids()
	var ecology_ids := EcologyRegistryScript.new().get_profile_ids()
	var sorted_expected := expected.duplicate()
	sorted_expected.sort()
	_check(resource_ids == sorted_expected, "resource profiles match the shared map catalog")
	_check(ecology_ids == sorted_expected, "ecology profiles match the shared map catalog")
	for profile_id: String in expected:
		_check(not MapProfileCatalogScript.label(profile_id).is_empty(), "%s has one shared display label" % profile_id)


func _test_signature_rules_and_rewards() -> void:
	var journal_registry = JournalRegistryScript.new()
	var reward_registry = RewardRegistryScript.new()
	_check(journal_registry.schema_version == 2 and journal_registry.get_validation_errors().is_empty(), "profile-aware journal registry loads cleanly")
	_check(reward_registry.schema_version == 2 and reward_registry.get_validation_errors().is_empty(), "profile-aware reward registry loads cleanly")
	for profile_id: String in MapProfileCatalogScript.get_ids():
		var record := _matching_record(profile_id)
		var snapshot := JournalPolicyScript.build_snapshot([record], journal_registry.get_config())
		var signature := _find_milestone(snapshot, "signature_finding")
		_check(bool(signature.get("completed", false)), "%s matching record completes its map signature" % profile_id)
		_check(str(signature.get("matched_profile_id", "")) == profile_id, "%s signature keeps its matched map identity" % profile_id)
		var reward := reward_registry.get_reward("signature_finding", profile_id)
		var material_id := str(MATERIAL_BY_PROFILE[profile_id])
		_check(_item_count(reward.get("items", []), material_id) == 1, "%s signature reward grants its unique material" % profile_id)
		var wrong_record := record.duplicate(true)
		wrong_record["profile_id"] = _next_profile(profile_id)
		var wrong_snapshot := JournalPolicyScript.build_snapshot([wrong_record], journal_registry.get_config())
		_check(not bool(_find_milestone(wrong_snapshot, "signature_finding").get("completed", false)), "%s signature conditions do not leak into another map" % profile_id)


func _test_calibrated_tool_runtime() -> void:
	var item_registry = ItemRegistryScript.new()
	_check(item_registry.load_from_file(), "production items load for calibrated runtime tests")
	var registry = ProspectingRegistryScript.new()
	_check(registry.validate_item_registry(item_registry), "all calibrated tools satisfy the prospecting item contract")
	var world := FakeWorld.new()
	var player := Node3D.new()
	var service = ProspectingServiceScript.new()
	root.add_child(world)
	root.add_child(player)
	root.add_child(service)
	_check(service.setup(item_registry), "production prospecting service accepts all calibrated tools")
	player.global_position = Vector3(0.5, 20.0, 0.5)
	service.attach_world(world, player)
	var now_msec := 1000
	for profile_id: String in MapProfileCatalogScript.get_ids():
		world.profile_id = profile_id
		var tool_id := str(TOOL_BY_PROFILE[profile_id])
		var config := registry.get_tool_config(tool_id)
		var result: Dictionary = service.use_item(tool_id, now_msec)
		_check(bool(result.get("success", false)), "%s calibrated tool completes a bounded scan in its own map" % profile_id)
		_check(str(result.get("tool_item_id", "")) == tool_id, "%s scan reports the exact calibrated tool" % profile_id)
		_check(int(result.get("sample_count", 0)) <= int(config.get("max_samples", 0)), "%s runtime scan respects its configured hard budget" % profile_id)
		_check(int(result.get("scan_profile", {}).get("theoretical_samples", 0)) == int(config.get("theoretical_samples", 0)), "%s runtime diagnostic matches the registry sample plan" % profile_id)
		_check(not result.has("positions") and not result.has("coordinates"), "%s calibrated scan never returns exact coordinates" % profile_id)
		world.profile_id = _next_profile(profile_id)
		var rejected: Dictionary = service.use_item(tool_id, now_msec + 1000)
		_check(str(rejected.get("reason", "")) == "wrong_calibration", "%s calibrated tool rejects a different map" % profile_id)
		player.global_position.x += 18.0
		now_msec += 3000
	service.queue_free()
	world.queue_free()
	player.queue_free()
	await process_frame
	await process_frame


func _test_calibrated_recipe_round_trip() -> void:
	for profile_id: String in MapProfileCatalogScript.get_ids():
		var inventory = InventoryScript.new(36, 9)
		var crafting = CraftingScript.new()
		root.add_child(inventory)
		root.add_child(crafting)
		crafting.setup(inventory)
		crafting.set_station("workbench")
		var tool_id := str(TOOL_BY_PROFILE[profile_id])
		var material_id := str(MATERIAL_BY_PROFILE[profile_id])
		var recipe: Dictionary = crafting.get_recipe(tool_id)
		_check(not recipe.is_empty(), "%s calibrated tool has a production crafting recipe" % profile_id)
		var ingredients: Dictionary = recipe.get("ingredients", {})
		for raw_item_id: Variant in ingredients.keys():
			inventory.add_item(str(raw_item_id), int(ingredients[raw_item_id]))
		var before_material := inventory.count_item(material_id)
		_check(before_material == 1, "%s recipe consumes exactly one signature material" % profile_id)
		_check(crafting.can_craft(tool_id), "%s calibrated recipe resolves all real requirements" % profile_id)
		_check(crafting.craft(tool_id), "%s calibrated tool crafting commits atomically" % profile_id)
		_check(inventory.count_item(tool_id) == 1, "%s calibrated tool enters the real inventory" % profile_id)
		_check(inventory.count_item("prospecting_kit") == 0 and inventory.count_item(material_id) == 0, "%s recipe consumes the base tool and signature material once" % profile_id)
		inventory.queue_free()
		crafting.queue_free()
		await process_frame


func _matching_record(profile_id: String) -> Dictionary:
	var depth_id := "middle"
	var density_id := "normal"
	var danger_id := "safe"
	match profile_id:
		"star_continent":
			depth_id = "lower"
			density_id = "promising"
		"desert_ruins":
			depth_id = "upper"
			density_id = "rich"
		"frozen_wastes":
			depth_id = "deep"
			density_id = "normal"
		"sky_islands":
			depth_id = "upper"
			density_id = "normal"
		"abyss_world":
			depth_id = "middle"
			density_id = "normal"
			danger_id = "dangerous"
	return {
		"record_key":"0,0:%s" % depth_id,
		"chunk":[0,0],
		"profile_id":profile_id,
		"depth_band_id":depth_id,
		"depth_label":depth_id,
		"density_id":density_id,
		"density_label":density_id,
		"ore_ratio":0.08 if density_id == "rich" else 0.04,
		"dominant_block_id":"iron_ore",
		"dominant_label":"铁矿",
		"danger_tier_id":danger_id,
		"danger_label":danger_id,
		"danger_score":72 if danger_id == "dangerous" else 18,
		"danger_reasons":["夜晚"] if danger_id == "dangerous" else [],
		"message":"粗粒度趋势",
		"sequence":1,
		"world_day":1,
		"world_time":12.0,
		"scanned_at_msec":1000,
	}


func _find_milestone(snapshot: Dictionary, milestone_id: String) -> Dictionary:
	var raw_milestones: Variant = snapshot.get("milestones", [])
	if raw_milestones is not Array:
		return {}
	for raw_milestone: Variant in raw_milestones:
		if raw_milestone is Dictionary and str(raw_milestone.get("id", "")) == milestone_id:
			return raw_milestone.duplicate(true)
	return {}


func _item_count(raw_items: Variant, item_id: String) -> int:
	var total := 0
	if raw_items is not Array:
		return total
	for raw_item: Variant in raw_items:
		if raw_item is Dictionary and str(raw_item.get("item_id", "")) == item_id:
			total += int(raw_item.get("count", 0))
	return total


func _next_profile(profile_id: String) -> String:
	var ids := MapProfileCatalogScript.get_ids()
	var index := ids.find(profile_id)
	return ids[(index + 1) % ids.size()]


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
