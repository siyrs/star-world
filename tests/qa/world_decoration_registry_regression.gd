extends SceneTree

const RegistryScript = preload("res://src/world/world_decoration_registry.gd")
const GeneratorScript = preload("res://src/world/world_generator.gd")
const MapSelectionPanelScript = preload("res://src/ui/map_selection_panel.gd")
const PROFILE_IDS: Array[String] = [
	"star_continent",
	"desert_ruins",
	"frozen_wastes",
	"sky_islands",
	"abyss_world",
]
const TEST_SEEDS: Array[int] = [734521, 8451397, 73190462]
const EXPECTED_RULE_COUNTS := {
	"star_continent": 3,
	"desert_ruins": 4,
	"frozen_wastes": 1,
	"sky_islands": 3,
	"abyss_world": 1,
}

var checks := 0
var failures: Array[String] = []
var compatibility_samples := 0
var decoration_counts: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registry_contract()
	_test_invalid_registry_rejection()
	_test_seed_compatibility()
	_test_poi_snapshot()
	await _test_map_selection_contract()
	if failures.is_empty():
		print(
			"QA WORLD DECORATION REGISTRY PASS | checks=%d | compatibility_samples=%d | counts=%s"
			% [checks, compatibility_samples, decoration_counts]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA WORLD DECORATION REGISTRY FAILURE: %s" % failure)
		print(
			"QA WORLD DECORATION REGISTRY FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _test_registry_contract() -> void:
	var registry = RegistryScript.new()
	_check(registry.schema_version == 1, "world decoration schema version is stable")
	_check(registry.max_rules_per_profile == 16, "world decoration rule budget is fixed at sixteen")
	_check(
		registry.get_validation_errors().is_empty(),
		"production world decoration data has no validation errors"
	)
	_check(
		registry.get_profile_ids()
		== ["abyss_world", "desert_ruins", "frozen_wastes", "sky_islands", "star_continent"],
		"all five production maps expose decoration profiles"
	)
	for profile_id: String in PROFILE_IDS:
		var profile: Dictionary = registry.get_profile(profile_id)
		var snapshot: Dictionary = registry.get_snapshot(profile_id)
		var rule_ids: Array[String] = registry.get_rule_ids(profile_id)
		_check(str(profile.get("id", "")) == profile_id, "%s returns its own decoration profile" % profile_id)
		_check(not str(profile.get("summary", "")).is_empty(), "%s exposes a player-facing landmark summary" % profile_id)
		_check(
			rule_ids.size() == int(EXPECTED_RULE_COUNTS.get(profile_id, 0)),
			"%s preserves its bounded rule count" % profile_id
		)
		_check(rule_ids.size() <= registry.max_rules_per_profile, "%s stays inside the rule budget" % profile_id)
		_check(bool(snapshot.get("loaded_from_file", false)), "%s is loaded from the production data registry" % profile_id)
		_check(int(snapshot.get("validation_error_count", -1)) == 0, "%s snapshot reports no validation errors" % profile_id)
	_check(
		registry.get_profile("unknown").get("id", "") == "star_continent",
		"unknown decoration profiles use the stable balanced fallback"
	)


func _test_invalid_registry_rejection() -> void:
	var path := "user://invalid-world-decoration-registry.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "invalid registry fixture opens for writing")
	if file == null:
		return
	file.store_string(JSON.stringify({
		"schema_version": 1,
		"default_profile": "bad",
		"max_rules_per_profile": 1,
		"profiles": [
			{
				"id": "bad",
				"summary": "invalid fixture",
				"rules": [
					{
						"id": "unknown_block",
						"type": "surface_roll",
						"block_id": "not_a_block",
						"roll_salt": 1,
						"minimum_roll": 0,
						"maximum_roll": 10,
					}
				]
			}
		]
	}))
	file.close()
	var registry = RegistryScript.new()
	_check(not registry.load_from_file(path), "invalid decoration registry is rejected")
	_check(not registry.get_validation_errors().is_empty(), "invalid decoration registry exposes validation evidence")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_seed_compatibility() -> void:
	for profile_id: String in PROFILE_IDS:
		var profile_count := 0
		for seed_value: int in TEST_SEEDS:
			var generator = GeneratorScript.new()
			generator.configure(profile_id, seed_value)
			for x in range(-64, 65, 4):
				for z in range(-64, 65, 4):
					var terrain_height := generator.get_surface_height(x, z)
					for offset in range(1, 5):
						var position := Vector3i(x, terrain_height + offset, z)
						var actual := str(generator.call("_get_decoration_block", position, terrain_height))
						var expected := _legacy_decoration_block(
							generator,
							profile_id,
							position,
							terrain_height
						)
						compatibility_samples += 1
						_check(
							actual == expected,
							"%s seed=%d preserves legacy decoration at %s"
							% [profile_id, seed_value, position]
						)
						if seed_value == TEST_SEEDS[0] and actual != "air":
							profile_count += 1
		decoration_counts[profile_id] = profile_count
		_check(profile_count > 0, "%s produces deterministic decoration in the sampled region" % profile_id)


func _test_poi_snapshot() -> void:
	var generator = GeneratorScript.new()
	generator.configure("desert_ruins", TEST_SEEDS[0])
	var active_snapshot: Dictionary = {}
	for cell_x in range(-4, 5):
		for cell_z in range(-4, 5):
			var probe_x := cell_x * 48 + 24
			var probe_z := cell_z * 48 + 24
			var snapshot: Dictionary = generator.get_poi_snapshot(probe_x, probe_z)
			var sites: Array = snapshot.get("sites", [])
			if not sites.is_empty() and bool((sites[0] as Dictionary).get("active", false)):
				active_snapshot = snapshot
				break
		if not active_snapshot.is_empty():
			break
	_check(not active_snapshot.is_empty(), "desert registry exposes an active ruin site in bounded nearby cells")
	if active_snapshot.is_empty():
		return
	var sites: Array = active_snapshot.get("sites", [])
	var site: Dictionary = sites[0]
	_check(str(active_snapshot.get("profile_id", "")) == "desert_ruins", "POI snapshot retains the authoritative profile id")
	_check(int(active_snapshot.get("rule_count", 0)) == 4, "POI snapshot exposes the full desert decoration budget")
	_check(str(site.get("rule_id", "")) == "desert_ruin_pillars", "POI snapshot identifies the ruin structure rule")
	_check(site.get("center", Vector2i.ZERO) is Vector2i, "POI snapshot exposes a deterministic ruin center")
	var center: Vector2i = site.get("center", Vector2i.ZERO)
	var repeated: Dictionary = generator.get_poi_snapshot(center.x, center.y)
	var repeated_sites: Array = repeated.get("sites", [])
	_check(
		not repeated_sites.is_empty()
		and (repeated_sites[0] as Dictionary).get("center", Vector2i.ZERO) == center,
		"repeated POI lookup preserves the same center"
	)
	var terrain_height := generator.get_surface_height(center.x, center.y)
	var pillar_count := 0
	for x in range(center.x - 4, center.x + 5):
		for z in range(center.y - 4, center.y + 5):
			for offset in range(1, 5):
				if generator.get_block(Vector3i(x, generator.get_surface_height(x, z) + offset, z)) == "ruin_pillar":
					pillar_count += 1
	_check(pillar_count > 0, "active POI snapshot corresponds to generated ruin pillar blocks")
	print("QA WORLD POI SITE | center=%s | terrain_height=%d | pillars=%d | site=%s" % [center, terrain_height, pillar_count, site])


func _test_map_selection_contract() -> void:
	var panel = MapSelectionPanelScript.new()
	root.add_child(panel)
	for _frame in 3:
		await process_frame
	for profile_id: String in PROFILE_IDS:
		panel.call("_select_profile", profile_id)
		var summary := str(panel.call("get_decoration_summary", profile_id))
		var visible_label := panel.get("_resource_summary_label") as Label
		var visible_text := visible_label.text if visible_label != null else ""
		_check(not summary.is_empty(), "%s decoration summary is available to map selection" % profile_id)
		_check(visible_text.contains("地表地标"), "%s map briefing labels its POI identity" % profile_id)
		_check(visible_text.contains(summary), "%s map briefing displays its authoritative decoration summary" % profile_id)
	panel.queue_free()
	for _frame in 3:
		await process_frame


func _legacy_decoration_block(
	generator,
	profile_id: String,
	position: Vector3i,
	terrain_height: int
) -> String:
	var x := position.x
	var z := position.z
	match profile_id:
		"star_continent":
			if position.y != terrain_height + 1 or terrain_height < GeneratorScript.SEA_LEVEL:
				return "air"
			if bool(generator.call("_tree_here", x, z, 185)):
				return "air"
			var roll := _hash(generator, x, 0, z, 911)
			if roll < 600: return "tall_grass"
			if roll < 680: return "flower_red"
			if roll < 740: return "flower_yellow"
		"desert_ruins":
			var pillar_height := _legacy_ruin_pillar_height(generator, x, z)
			if pillar_height > 0 and position.y <= terrain_height + pillar_height:
				return "ruin_pillar"
			var cactus_height := 0
			if _hash(generator, x, 0, z, 937) < 90:
				cactus_height = 1 + _hash(generator, x, 0, z, 941) % 2
			if cactus_height > 0 and position.y <= terrain_height + cactus_height:
				return "cactus"
			if position.y != terrain_height + 1:
				return "air"
			if _legacy_ruin_debris_here(generator, x, z):
				return "ruin_pillar"
			if _hash(generator, x, 0, z, 977) < 150:
				return "dead_bush"
		"frozen_wastes":
			if position.y == terrain_height + 1 and _hash(generator, x, 0, z, 983) < 60:
				return "dead_bush"
		"sky_islands":
			if position.y != terrain_height + 1:
				return "air"
			if float(generator.call("_sky_island_strength", x, z)) < 0.35:
				return "air"
			if bool(generator.call("_tree_here", x, z, 90)):
				return "air"
			var roll := _hash(generator, x, 0, z, 907)
			if roll < 500: return "tall_grass"
			if roll < 580: return "flower_yellow"
			if roll < 640: return "flower_red"
		"abyss_world":
			if position.y == terrain_height + 1 and _hash(generator, x, 0, z, 991) < 130:
				return "glow_crystal"
	return "air"


func _legacy_ruin_site_center(generator, cell_x: int, cell_z: int) -> Vector2i:
	var offset_x := _hash(generator, cell_x, 0, cell_z, 953) % 24 - 12
	var offset_z := _hash(generator, cell_x, 0, cell_z, 967) % 24 - 12
	return Vector2i(cell_x * 48 + 24 + offset_x, cell_z * 48 + 24 + offset_z)


func _legacy_ruin_pillar_height(generator, x: int, z: int) -> int:
	var cell_x := floori(float(x) / 48.0)
	var cell_z := floori(float(z) / 48.0)
	if _hash(generator, cell_x, 0, cell_z, 971) < 4200:
		return 0
	var center := _legacy_ruin_site_center(generator, cell_x, cell_z)
	var local_x := x - center.x
	var local_z := z - center.y
	if absi(local_x) > 4 or absi(local_z) > 4:
		return 0
	if posmod(local_x, 3) != 0 or posmod(local_z, 3) != 0:
		return 0
	return 1 + _hash(generator, x, 0, z, 983) % 4


func _legacy_ruin_debris_here(generator, x: int, z: int) -> bool:
	var cell_x := floori(float(x) / 48.0)
	var cell_z := floori(float(z) / 48.0)
	if _hash(generator, cell_x, 0, cell_z, 971) < 4200:
		return false
	var center := _legacy_ruin_site_center(generator, cell_x, cell_z)
	if absi(x - center.x) > 9 or absi(z - center.y) > 9:
		return false
	return _hash(generator, x, 0, z, 991) < 110


func _hash(generator, x: int, y: int, z: int, salt: int) -> int:
	return int(generator.call("_hash_roll", x, y, z, salt))


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
