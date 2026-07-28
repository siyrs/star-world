extends SceneTree

const GeneratorScript = preload("res://src/world/world_generator.gd")

var checks := 0
var failures: Array[String] = []
var sampled_blocks := 0
var sampled_poi_queries := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var generator = GeneratorScript.new()
	var initial_snapshot: Dictionary = generator.get_decoration_profile_snapshot()
	_check(
		int(initial_snapshot.get("profile_refresh_count", -1)) == 1,
		"default decoration profile is cached exactly once during construction"
	)
	_check(
		int(initial_snapshot.get("cached_rule_count", -1)) == 3,
		"default cache exposes the bounded grassland rule count"
	)

	generator.configure("desert_ruins", 734521)
	var configured_snapshot: Dictionary = generator.get_decoration_profile_snapshot()
	var configured_refresh_count := int(configured_snapshot.get("profile_refresh_count", -1))
	_check(configured_refresh_count == 2, "configure refreshes the profile cache exactly once")
	_check(
		int(configured_snapshot.get("cached_rule_count", -1)) == 4,
		"desert cache owns all four normalized decoration rules"
	)

	for x in range(-48, 49, 3):
		for z in range(-48, 49, 3):
			var terrain_height := generator.get_surface_height(x, z)
			for offset in range(1, 5):
				generator.get_block(Vector3i(x, terrain_height + offset, z))
				sampled_blocks += 1
			generator.get_poi_snapshot(x, z)
			sampled_poi_queries += 1

	var after_hot_path: Dictionary = generator.get_decoration_profile_snapshot()
	_check(
		int(after_hot_path.get("profile_refresh_count", -1)) == configured_refresh_count,
		"thousands of block and POI queries reuse one cached profile"
	)
	_check(
		int(after_hot_path.get("cached_rule_count", -1)) == 4,
		"hot-path queries do not mutate the cached desert rule set"
	)

	generator.configure("sky_islands", 8451397)
	var switched_snapshot: Dictionary = generator.get_decoration_profile_snapshot()
	_check(
		int(switched_snapshot.get("profile_refresh_count", -1)) == configured_refresh_count + 1,
		"switching map profiles refreshes the cache once and only once"
	)
	_check(
		int(switched_snapshot.get("cached_rule_count", -1)) == 3,
		"profile switching replaces the cache with the sky-island rules"
	)

	for x in range(-24, 25, 4):
		for z in range(-24, 25, 4):
			var terrain_height := generator.get_surface_height(x, z)
			generator.get_block(Vector3i(x, terrain_height + 1, z))
			sampled_blocks += 1
	var final_snapshot: Dictionary = generator.get_decoration_profile_snapshot()
	_check(
		int(final_snapshot.get("profile_refresh_count", -1))
		== int(switched_snapshot.get("profile_refresh_count", -2)),
		"sky-island block generation also keeps the cache stable"
	)

	if failures.is_empty():
		print(
			"QA WORLD DECORATION HOT PATH PASS | checks=%d | blocks=%d | poi_queries=%d | refreshes=%d"
			% [
				checks,
				sampled_blocks,
				sampled_poi_queries,
				int(final_snapshot.get("profile_refresh_count", -1)),
			]
		)
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA WORLD DECORATION HOT PATH FAILURE: %s" % failure)
		print(
			"QA WORLD DECORATION HOT PATH FAIL | checks=%d | failures=%d"
			% [checks, failures.size()]
		)
		quit(1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
