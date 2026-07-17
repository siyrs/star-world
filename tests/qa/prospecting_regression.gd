extends SceneTree

const ProspectingRegistryScript = preload("res://src/exploration/prospecting_registry.gd")
const ProspectingPolicyScript = preload("res://src/exploration/prospecting_policy.gd")
const ProspectingServiceScript = preload("res://src/exploration/prospecting_service.gd")
const ProspectingMigrationScript = preload("res://src/exploration/prospecting_state_migration.gd")
const ItemRegistryScript = preload("res://src/inventory/item_registry.gd")
const PromptResolverScript = preload("res://src/experience/interaction_prompt_resolver.gd")
const HeldItemPolicyScript = preload("res://src/player/held_item_visual_policy.gd")
const PlayerScene = preload("res://scenes/game/player.tscn")
const ServiceHubScene = preload("res://scenes/ui/service_hub.tscn")

var checks := 0
var failures: Array[String] = []


class FakeWorld:
	extends Node
	var profile_id := "abyss_world"
	var geology_enabled := true

	func world_to_block(position: Vector3) -> Vector3i:
		return Vector3i(floori(position.x), floori(position.y), floori(position.z))

	func block_to_chunk(position: Vector3i) -> Vector2i:
		return Vector2i(floori(float(position.x) / 16.0), floori(float(position.z) / 16.0))

	func get_initial_block(position: Vector3i) -> String:
		if not geology_enabled:
			return "air"
		if posmod(position.x + position.z + position.y, 17) == 0:
			return "diamond_ore"
		if posmod(position.x * 3 + position.z - position.y, 13) == 0:
			return "gold_ore"
		if posmod(position.x - position.z + position.y, 7) == 0:
			return "iron_ore"
		if posmod(position.x + position.z * 2 + position.y, 5) == 0:
			return "coal_ore"
		return "stone"


class FakeInventory:
	extends Node
	var registry
	var selected_item_id := "prospecting_kit"

	func get_selected_item() -> Dictionary:
		return {"item_id": selected_item_id, "count": 1, "metadata": {}}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_and_policy()
	await _test_service_lifecycle()
	_test_migration_and_budgets()
	await _test_player_experience_contracts()
	if failures.is_empty():
		print("QA PROSPECTING PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA PROSPECTING FAILURE: %s" % failure)
		print("QA PROSPECTING FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_registry_and_policy() -> void:
	var item_registry = ItemRegistryScript.new()
	_check(item_registry.load_from_file(), "production item registry loads")
	var registry = ProspectingRegistryScript.new()
	_check(registry.schema_version == 1, "prospecting schema version is stable")
	_check(registry.get_validation_errors().is_empty(), "prospecting data has no structural errors")
	_check(registry.validate_item_registry(item_registry), "prospecting item capability is registered")
	_check(registry.get_tool_item_id() == "prospecting_kit", "registry exposes the canonical prospecting tool")
	var config := registry.get_config()
	_check(int(config.get("max_samples", 0)) <= 2048, "scan sample budget stays under the hard limit")
	_check(int(config.get("max_records", 0)) == 64, "persistent discovery history is bounded")
	var tiers: Array = config.get("density_tiers", [])
	_check(ProspectingPolicyScript.classify_density(0.0, tiers).get("id", "") == "sparse", "zero density is sparse")
	_check(ProspectingPolicyScript.classify_density(0.0199, tiers).get("id", "") == "sparse", "density remains sparse below the normal boundary")
	_check(ProspectingPolicyScript.classify_density(0.02, tiers).get("id", "") == "normal", "normal boundary is inclusive")
	_check(ProspectingPolicyScript.classify_density(0.045, tiers).get("id", "") == "promising", "promising boundary is inclusive")
	_check(ProspectingPolicyScript.classify_density(0.075, tiers).get("id", "") == "rich", "rich boundary is inclusive")
	var bands: Array = config.get("depth_bands", [])
	_check(ProspectingPolicyScript.depth_band(10, bands).get("id", "") == "deep", "Y10 is deep")
	_check(ProspectingPolicyScript.depth_band(11, bands).get("id", "") == "lower", "Y11 enters the lower band")
	_check(ProspectingPolicyScript.depth_band(20, bands).get("id", "") == "middle", "Y20 enters the middle band")
	_check(ProspectingPolicyScript.depth_band(40, bands).get("id", "") == "upper", "Y40 is upper geology")
	var tied_counts := {"coal_ore": 2, "iron_ore": 2, "gold_ore": 2, "diamond_ore": 2}
	_check(
		ProspectingPolicyScript.dominant_ore(tied_counts, config.get("ore_blocks", [])).get("block_id", "") == "diamond_ore",
		"equal signals prefer the rarer configured ore"
	)
	var summary := ProspectingPolicyScript.summarize(
		{"coal_ore": 4, "iron_ore": 2, "gold_ore": 1, "diamond_ore": 0},
		100,
		120,
		18,
		"star_continent",
		config
	)
	_check(str(summary.get("dominant_block_id", "")) == "coal_ore", "summary reports only a dominant ore class")
	_check(not str(summary.get("message", "")).contains("坐标"), "summary message does not disclose exact ore coordinates")
	_check(not summary.has("positions") and not summary.has("ore_positions"), "policy output contains no coordinate list")


func _test_service_lifecycle() -> void:
	var item_registry = ItemRegistryScript.new()
	item_registry.load_from_file()
	var service = ProspectingServiceScript.new()
	root.add_child(service)
	_check(service.setup(item_registry), "prospecting service accepts production data")
	var world := FakeWorld.new()
	var player := Node3D.new()
	root.add_child(world)
	root.add_child(player)
	player.global_position = Vector3(17.5, 20.0, -18.5)
	service.attach_world(world, player)
	var ignored: Dictionary = service.use_item("stick", 1000)
	_check(not bool(ignored.get("handled", true)), "unrelated items are not intercepted")
	var result: Dictionary = service.use_item("prospecting_kit", 1000)
	_check(bool(result.get("handled", false)) and bool(result.get("success", false)), "prospecting kit completes a bounded scan")
	_check(int(result.get("sample_count", 0)) <= 700, "runtime scan respects max_samples")
	_check(int(result.get("geology_samples", 0)) >= 24, "runtime scan has enough geology evidence")
	_check(str(result.get("record_key", "")).begins_with("1,-2:"), "record key uses coarse chunk and depth band")
	_check((result.get("chunk", []) as Array) == [1, -2], "result exposes only the coarse chunk coordinate")
	_check(not result.has("positions") and not result.has("ore_positions") and not result.has("coordinates"), "service does not leak ore locations")
	_check(str(result.get("message", "")).contains("粗粒度趋势"), "player message explains the limited scan precision")
	_check(int(result.get("sequence", 0)) == 1, "first successful scan receives a stable discovery sequence")
	var first_snapshot := service.get_snapshot()
	_check(int(first_snapshot.get("record_count", 0)) == 1, "successful scan creates one discovery record")
	var cooldown: Dictionary = service.use_item("prospecting_kit", 1500)
	_check(bool(cooldown.get("handled", false)) and not bool(cooldown.get("success", true)), "cooldown request is handled without scanning")
	_check(str(cooldown.get("reason", "")) == "cooldown", "cooldown has an explicit reason")
	_check(int(service.get_snapshot().get("record_count", 0)) == 1, "cooldown does not duplicate records")
	player.global_position = Vector3(34.5, 20.0, -18.5)
	var second: Dictionary = service.use_item("prospecting_kit", 2100)
	_check(bool(second.get("success", false)), "scan works again after cooldown")
	_check(int(service.get_snapshot().get("record_count", 0)) == 2, "a new chunk creates a second persistent discovery")
	var serialized := service.serialize()
	_check(int(serialized.get("version", 0)) == 3, "exploration records serialize with the hardened version 3 contract")
	_check((serialized.get("records", []) as Array).size() == 2, "exploration records serialize")
	var restored = ProspectingServiceScript.new()
	root.add_child(restored)
	restored.setup(item_registry)
	restored.deserialize(serialized)
	_check(int(restored.get_snapshot().get("record_count", 0)) == 2, "exploration records deserialize")
	_check(not restored.get_record(str(second.get("record_key", ""))).is_empty(), "record lookup survives reload")
	world.geology_enabled = false
	restored.attach_world(world, player)
	var rejected: Dictionary = restored.use_item("prospecting_kit", 4000)
	_check(str(rejected.get("reason", "")) == "insufficient_geology", "air-only scan is rejected as insufficient geology")
	_check(not bool(rejected.get("success", true)), "insufficient geology does not create a false result")
	service.queue_free()
	restored.queue_free()
	world.queue_free()
	player.queue_free()
	await process_frame
	await process_frame


func _test_migration_and_budgets() -> void:
	var records: Array[Dictionary] = []
	for index in 70:
		records.append({
			"record_key": "%d,0:middle" % index,
			"chunk": [index, 0],
			"profile_id": "star_continent",
			"depth_band_id": "middle",
			"depth_label": "中层",
			"density_id": "normal",
			"density_label": "普通",
			"ore_ratio": 0.03,
			"dominant_block_id": "iron_ore",
			"dominant_label": "铁矿",
			"message": "历史记录",
			"scanned_at_msec": index,
		})
	var migrated := ProspectingMigrationScript.normalize_world_state({"metadata": {}, "exploration": {"records": records}})
	_check(int(migrated.get("exploration", {}).get("version", 0)) == 3, "old world receives exploration version 3")
	var item_registry = ItemRegistryScript.new()
	item_registry.load_from_file()
	var service = ProspectingServiceScript.new()
	root.add_child(service)
	service.setup(item_registry)
	service.deserialize(migrated.get("exploration", {}))
	var snapshot := service.get_snapshot()
	_check(int(snapshot.get("record_count", 0)) == 64, "oversized imported discovery history is trimmed to the configured budget")
	var keys: Array = snapshot.get("record_keys", [])
	_check(str(keys.front()) == "6,0:middle" and str(keys.back()) == "69,0:middle", "record trimming keeps the newest discoveries")
	service.queue_free()


func _test_player_experience_contracts() -> void:
	var item_registry = ItemRegistryScript.new()
	item_registry.load_from_file()
	var inventory := FakeInventory.new()
	inventory.registry = item_registry
	root.add_child(inventory)
	var prompt_resolver = PromptResolverScript.new()
	var prompt: Dictionary = prompt_resolver.resolve({}, inventory, null)
	_check(bool(prompt.get("visible", false)), "holding prospecting kit exposes an interaction prompt")
	_check(str(prompt.get("secondary", "")).contains("勘探当前区域"), "prompt explains the real right-click action")
	_check(str(prompt.get("subtitle", "")).contains("不暴露具体坐标"), "prompt explicitly rejects x-ray precision")
	var held_policy = HeldItemPolicyScript.new()
	_check(held_policy.action_kind(&"prospect") == HeldItemPolicyScript.ACTION_USE, "prospecting triggers the first-person use animation")
	var player = PlayerScene.instantiate()
	_check(str(player.get_script().resource_path) == "res://src/player/exploration_player.gd", "production player uses the exploration adapter")
	_check(player.has_method("bind_prospecting_service"), "production player exposes the prospecting port")
	player.queue_free()
	var hub = ServiceHubScene.instantiate()
	_check(str(hub.get_script().resource_path) == "res://src/ui/exploration_progression_service_hub.gd", "production service hub composes exploration")
	hub.queue_free()
	inventory.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
