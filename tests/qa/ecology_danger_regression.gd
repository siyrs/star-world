extends SceneTree

const EcologyRegistryScript = preload("res://src/entity/creature_ecology_registry.gd")
const EcologyPolicyScript = preload("res://src/entity/creature_ecology_policy.gd")
const SpawnerScript = preload("res://src/entity/creature_spawner.gd")
const DangerRegistryScript = preload("res://src/exploration/exploration_danger_registry.gd")
const DangerPolicyScript = preload("res://src/exploration/exploration_danger_policy.gd")
const DangerServiceScript = preload("res://src/exploration/exploration_danger_service.gd")
const ProspectingServiceScript = preload("res://src/exploration/prospecting_service.gd")
const ProspectingMigrationScript = preload("res://src/exploration/prospecting_state_migration.gd")
const ItemRegistryScript = preload("res://src/inventory/item_registry.gd")

var checks := 0
var failures: Array[String] = []


class FakeDayNight:
	extends Node
	var phase := "day"
	func get_phase() -> String:
		return phase
	func is_night() -> bool:
		return phase == "night"


class FakeEcologySpawner:
	extends Node
	var danger_base := 8
	var hostile_count := 0
	var hostile_pressure := 0.0
	func get_ecology_snapshot() -> Dictionary:
		return {"danger_base":danger_base, "profile_id":"fake"}
	func get_nearby_hostile_count(_position: Vector3, _radius: float) -> int:
		return hostile_count
	func get_nearby_hostile_pressure(_position: Vector3, _radius: float) -> float:
		return maxf(float(hostile_count), hostile_pressure)


class FakeWorld:
	extends Node
	var profile_id := "star_continent"
	var mode := "safe"
	func world_to_block(position: Vector3) -> Vector3i:
		return Vector3i(floori(position.x), floori(position.y), floori(position.z))
	func block_to_chunk(position: Vector3i) -> Vector2i:
		return Vector2i(floori(float(position.x) / 16.0), floori(float(position.z) / 16.0))
	func get_initial_block(position: Vector3i) -> String:
		if position.y < 1 or position.y > 63:
			return "air"
		if mode == "danger":
			if position.x == 0 and position.z == 0 and posmod(position.y, 4) == 0:
				return "lava"
			if position.x == 4 or position.z == 4:
				return "air"
		if posmod(position.x * 3 + position.y * 5 + position.z * 7, 37) == 0:
			return "diamond_ore"
		if posmod(position.x * 5 + position.y * 3 + position.z * 11, 19) == 0:
			return "iron_ore"
		return "stone"


class FakeDangerService:
	extends Node
	var snapshot := {
		"tier_id":"dangerous",
		"tier_label":"危险",
		"score":58,
		"reasons":["深层", "夜晚"],
	}
	func get_snapshot() -> Dictionary:
		return snapshot.duplicate(true)
	func refresh_now() -> Dictionary:
		return get_snapshot()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_ecology_registry_and_policy()
	await _test_production_spawner_contract()
	_test_danger_policy()
	await _test_danger_service_budget()
	await _test_prospecting_danger_persistence()
	if failures.is_empty():
		print("QA ECOLOGY DANGER PASS | checks=%d" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA ECOLOGY DANGER FAILURE: %s" % failure)
		print("QA ECOLOGY DANGER FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _test_ecology_registry_and_policy() -> void:
	var registry = EcologyRegistryScript.new()
	_check(registry.schema_version == 2, "production ecology uses conditional schema version 2")
	_check(registry.get_validation_errors().is_empty(), "production ecology registry has no validation errors")
	_check(
		registry.get_profile_ids() == ["abyss_world", "desert_ruins", "frozen_wastes", "sky_islands", "star_continent"],
		"all five maps expose ecology profiles"
	)
	var star := registry.get_profile("star_continent")
	var abyss := registry.get_profile("abyss_world")
	var sky := registry.get_profile("sky_islands")
	_check(EcologyPolicyScript.hostile_cap(star, "day") == 0, "balanced world has no daytime hostile population")
	_check(EcologyPolicyScript.hostile_cap(star, "night") == 2, "balanced world allows two night hostiles")
	_check(EcologyPolicyScript.hostile_cap(abyss, "day") == 2, "abyss keeps hostile pressure during daytime")
	_check(EcologyPolicyScript.hostile_cap(abyss, "night") == 5, "abyss night cap is map-specific")
	_check(
		EcologyPolicyScript.choose_species(star, "day", 0, 0, 0.0, 0.0) == "chicken",
		"balanced daytime ecology selects passive species"
	)
	_check(
		EcologyPolicyScript.choose_species(abyss, "day", 0, 0, 0.1, 0.0) == "zombie",
		"abyss daytime surface ecology can select normal hostile species"
	)
	_check(
		EcologyPolicyScript.choose_species(star, "night", 12, 0, 0.99, 0.0) == "zombie",
		"hostile population remains available when passive cap is full"
	)
	_check(
		EcologyPolicyScript.choose_species(star, "night", 12, 2, 0.0, 0.0).is_empty(),
		"ecology refuses spawning when both caps are full"
	)
	_check(
		EcologyPolicyScript.weighted_species(sky.get("passive_species", []), 0.2) == "chicken",
		"sky islands strongly prefer chickens"
	)
	var abyss_hostiles: Array = abyss.get("hostile_species", [])
	_check(
		EcologyPolicyScript.weighted_species(
			abyss_hostiles,
			0.99,
			"night",
			{"player_y":35.0, "species_counts":{}}
		) == "abyss_brute",
		"night enables the rare abyss elite"
	)
	_check(
		EcologyPolicyScript.weighted_species(
			abyss_hostiles,
			0.99,
			"day",
			{"player_y":35.0, "species_counts":{}}
		) == "zombie",
		"surface daytime excludes the elite"
	)
	_check(
		EcologyPolicyScript.weighted_species(
			abyss_hostiles,
			0.99,
			"day",
			{"player_y":15.0, "species_counts":{}}
		) == "abyss_brute",
		"deep abyss enables the elite outside night"
	)
	_check(
		EcologyPolicyScript.weighted_species(
			abyss_hostiles,
			0.99,
			"night",
			{"player_y":15.0, "species_counts":{"abyss_brute":1}}
		) == "zombie",
		"elite species cap prevents duplicate brutes"
	)


func _test_production_spawner_contract() -> void:
	var day_night := FakeDayNight.new()
	var player := Node3D.new()
	var spawner = SpawnerScript.new()
	root.add_child(day_night)
	root.add_child(player)
	root.add_child(spawner)
	await process_frame
	spawner.set_map_profile("abyss_world")
	spawner.setup(player, null, day_night, Callable(), false)
	var abyss_snapshot: Dictionary = spawner.get_ecology_snapshot()
	_check(str(abyss_snapshot.get("profile_id", "")) == "abyss_world", "production spawner keeps the selected map ecology")
	_check(int(abyss_snapshot.get("hostile_cap", 0)) == 2, "production spawner applies abyss daytime cap")
	_check(int(abyss_snapshot.get("danger_base", 0)) == 36, "production spawner exposes map danger base")
	day_night.phase = "night"
	_check(int(spawner.get_ecology_snapshot().get("hostile_cap", 0)) == 5, "production spawner updates cap with phase")
	var nearby := Node3D.new()
	nearby.add_to_group("hostile")
	spawner.add_child(nearby)
	nearby.global_position = Vector3(2, 0, 0)
	var distant := Node3D.new()
	distant.add_to_group("hostile")
	spawner.add_child(distant)
	distant.global_position = Vector3(40, 0, 0)
	_check(spawner.get_nearby_hostile_count(Vector3.ZERO, 18.0) == 1, "nearby hostile query respects radius and generic hostile identity")
	_check(is_equal_approx(spawner.get_nearby_hostile_pressure(Vector3.ZERO, 18.0), 1.0), "normal hostile pressure defaults to one")
	spawner.clear_creatures()
	spawner.queue_free()
	player.queue_free()
	day_night.queue_free()
	await process_frame
	await process_frame


func _test_danger_policy() -> void:
	var config := DangerRegistryScript.new().get_config()
	var safe := DangerPolicyScript.assess(
		{"map_id":"star_continent", "map_base":8, "player_y":42, "phase":"day", "hostile_count":0, "lava_samples":0, "air_samples":0, "total_samples":125},
		config
	)
	_check(str(safe.get("tier_id", "")) == "safe", "surface daytime balanced world is low danger")
	var severe := DangerPolicyScript.assess(
		{"map_id":"abyss_world", "map_base":36, "player_y":7, "phase":"night", "hostile_count":2, "lava_samples":2, "air_samples":70, "total_samples":125},
		config
	)
	_check(str(severe.get("tier_id", "")) == "severe", "deep abyss night with hostiles and lava is severe")
	_check(int(severe.get("score", 0)) == 100, "danger score is clamped to 100")
	_check((severe.get("reasons", []) as Array).has("夜晚"), "danger reasons explain night pressure")
	_check((severe.get("reasons", []) as Array).has("附近岩浆"), "danger reasons explain lava pressure")
	var normal_hostile := DangerPolicyScript.assess(
		{"map_id":"star_continent", "map_base":8, "player_y":42, "phase":"day", "hostile_count":1, "hostile_pressure":1.0, "lava_samples":0, "air_samples":0, "total_samples":125},
		config
	)
	var elite_hostile := DangerPolicyScript.assess(
		{"map_id":"star_continent", "map_base":8, "player_y":42, "phase":"day", "hostile_count":1, "hostile_pressure":2.0, "lava_samples":0, "air_samples":0, "total_samples":125},
		config
	)
	_check(int(elite_hostile.get("score", 0)) > int(normal_hostile.get("score", 0)), "elite hostile pressure raises danger without pretending there are two bodies")
	_check((elite_hostile.get("reasons", []) as Array).has("附近精英敌对生物"), "danger reason explains elite pressure")


func _test_danger_service_budget() -> void:
	var day_night := FakeDayNight.new()
	day_night.phase = "night"
	var spawner := FakeEcologySpawner.new()
	spawner.danger_base = 36
	spawner.hostile_count = 2
	spawner.hostile_pressure = 3.0
	var world := FakeWorld.new()
	world.profile_id = "abyss_world"
	world.mode = "danger"
	var player := Node3D.new()
	player.global_position = Vector3(0.5, 8.0, 0.5)
	var service = DangerServiceScript.new()
	root.add_child(day_night)
	root.add_child(spawner)
	root.add_child(world)
	root.add_child(player)
	root.add_child(service)
	await process_frame
	_check(bool(service.setup(day_night, spawner)), "danger service accepts production data")
	service.attach_world(world, player)
	var snapshot: Dictionary = service.refresh_now()
	_check(int(snapshot.get("sample_count", 0)) <= 125, "danger service never exceeds the hard sample budget")
	_check(str(snapshot.get("tier_id", "")) in ["dangerous", "severe"], "danger service detects the hostile abyss environment")
	_check(is_equal_approx(float(snapshot.get("hostile_pressure", 0.0)), 3.0), "danger service consumes weighted hostile pressure")
	_check(not snapshot.has("position") and not snapshot.has("coordinates"), "danger snapshot does not expose exact environment coordinates")
	spawner.hostile_count = 0
	spawner.hostile_pressure = 0.0
	spawner.danger_base = 8
	day_night.phase = "day"
	world.profile_id = "star_continent"
	world.mode = "safe"
	player.global_position.y = 42.0
	var lower: Dictionary = service.refresh_now()
	_check(int(lower.get("score", 100)) < int(snapshot.get("score", 0)), "danger service responds to safer map, phase and depth")
	service.clear()
	service.queue_free()
	player.queue_free()
	world.queue_free()
	spawner.queue_free()
	day_night.queue_free()
	await process_frame
	await process_frame


func _test_prospecting_danger_persistence() -> void:
	var items = ItemRegistryScript.new()
	_check(items.load_from_file(), "item registry loads for prospecting integration")
	var danger := FakeDangerService.new()
	var world := FakeWorld.new()
	world.profile_id = "star_continent"
	var player := Node3D.new()
	player.global_position = Vector3(0.5, 16.0, 0.5)
	var service = ProspectingServiceScript.new()
	root.add_child(danger)
	root.add_child(world)
	root.add_child(player)
	root.add_child(service)
	await process_frame
	_check(bool(service.setup(items, danger)), "prospecting accepts the danger service")
	service.attach_world(world, player)
	var result: Dictionary = service.use_item("prospecting_kit", 5000)
	_check(bool(result.get("success", false)), "prospecting completes with danger context")
	_check(str(result.get("danger_tier_id", "")) == "dangerous", "prospecting result includes current danger tier")
	_check(int(result.get("danger_score", 0)) == 58, "prospecting result includes current danger score")
	_check(str(result.get("message", "")).contains("当前危险"), "player-facing prospecting message includes danger")
	var serialized: Dictionary = service.serialize()
	_check(int(serialized.get("version", 0)) == 3, "exploration persistence advances to version 3")
	var records: Array = serialized.get("records", [])
	_check(records.size() == 1 and str(records[0].get("danger_label", "")) == "危险", "stored discovery retains danger label")
	var migrated := ProspectingMigrationScript.normalize_exploration_state({
		"version":1,
		"records":[{"record_key":"0,0:deep", "chunk":[0,0], "depth_band_id":"deep", "depth_label":"深层", "density_id":"normal", "density_label":"普通"}],
	})
	_check(int(migrated.get("version", 0)) == 3, "version 1 exploration state migrates to version 3")
	var migrated_records: Array = migrated.get("records", [])
	_check(str(migrated_records[0].get("danger_tier_id", "")) == "unknown", "old records receive safe unknown danger defaults")
	service.clear()
	service.queue_free()
	player.queue_free()
	world.queue_free()
	danger.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
