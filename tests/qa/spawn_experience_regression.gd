extends SceneTree

const GeneratorScript = preload("res://src/world/world_generator.gd")
const SpawnQualityRegistryScript = preload("res://src/world/spawn_quality_registry.gd")
const SpawnResolverScript = preload("res://src/player/player_spawn_resolver.gd")
const MapProfileCatalogScript = preload("res://src/world/map_profile_catalog.gd")

const SEEDS := [112358, 556677, 1357911, 2468022, 24681357, 1088352404]

var checks := 0
var failures: Array[String] = []


class GeneratorWorldProxy:
	extends Node

	var generator

	func get_block(position: Vector3i) -> String:
		return generator.get_block(position)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = SpawnQualityRegistryScript.new()
	var registry_snapshot: Dictionary = registry.get_snapshot("star_continent")
	var all_profile_ids := MapProfileCatalogScript.get_ids()
	var profile_ids := all_profile_ids.duplicate()
	var requested_profile := _user_argument("profile")
	if not requested_profile.is_empty():
		if requested_profile not in all_profile_ids:
			push_error("Unknown spawn profile filter: %s" % requested_profile)
			quit(2)
			return
		profile_ids = [requested_profile]
	var seeds: Array[int] = []
	for raw_seed: int in SEEDS:
		seeds.append(raw_seed)
	var requested_seed := _user_argument("seed")
	if not requested_seed.is_empty():
		if not requested_seed.is_valid_int():
			push_error("Invalid spawn seed filter: %s" % requested_seed)
			quit(2)
			return
		seeds = [int(requested_seed)]
	print(
		"SPAWN_EXPERIENCE_FILTER profiles=%s seeds=%s"
		% [JSON.stringify(profile_ids), JSON.stringify(seeds)]
	)
	_check(bool(registry_snapshot.get("loaded_from_file", false)), "spawn quality policy loads from data")
	var expected_profile_ids := all_profile_ids.duplicate()
	expected_profile_ids.sort()
	_check(
		registry.get_profile_ids() == expected_profile_ids,
		"spawn quality policy covers all five production profiles",
	)
	_check(registry.get_validation_errors().is_empty(), "spawn quality policy has no validation errors")
	# Synthetic canopy-obstruction fixture: verify that the spawn evaluator
	# avoids positions where tree leaves or wood block the body column.
	# Use the densest-canopy seed and check overhead cells via the generator's
	# surface-height query to avoid floating-point truncation of the spawn Y.
	var canopy_gen = GeneratorScript.new()
	canopy_gen.configure("star_continent", 24681357)
	var canopy_position: Vector3 = canopy_gen.find_spawn_position()
	var canopy_snapshot: Dictionary = canopy_gen.get_last_spawn_quality_snapshot()
	var bx := int(canopy_position.x - 0.5)
	var bz := int(canopy_position.z - 0.5)
	var by := canopy_gen.get_surface_height(bx, bz)
	_check(
		bool(canopy_snapshot.get("hard_safe", false)),
		"canopy fixture seed 24681357 produces a hard-safe spawn"
	)
	_check(
		canopy_position.y > 1.0 and canopy_position.y < 64.0,
		"canopy fixture spawns within world bounds"
	)
	_check(
		by >= 1,
		"canopy fixture surface height is above bedrock at spawn x=%d z=%d" % [bx, bz]
	)
	# Verify the three body cells above the surface are air — no tree canopy
	# or solid decoration blocking first-frame view.
	var canopy_body_clear := true
	for offset_y in range(1, 4):
		var overhead_block: String = canopy_gen.get_block(Vector3i(bx, by + offset_y, bz))
		if overhead_block != "air":
			canopy_body_clear = false
			break
	_check(canopy_body_clear, "canopy fixture body column is clear of solid blocks and leaves")
	# Verify that resolving the spawn through the player respawn system preserves
	# the position (grounded, supported) — critical for save/load round-trips.
	var canopy_resolver = SpawnResolverScript.new()
	var canopy_proxy := GeneratorWorldProxy.new()
	canopy_proxy.generator = canopy_gen
	var canopy_resolved: Vector3 = canopy_resolver.resolve(
		canopy_proxy, canopy_position, canopy_position
	)
	canopy_proxy.generator = null
	canopy_proxy.free()
	_check(
		canopy_resolved.is_equal_approx(canopy_position),
		"canopy fixture resolved spawn matches the selected position"
	)
	_check(
		canopy_resolved.y >= 1.0,
		"canopy fixture resolved position is grounded"
	)
	# Drop references so RefCounted internals (FastNoiseLite, registries)
	# can be cleaned up before the engine exits.
	canopy_gen = null
	canopy_resolver = null

	for profile_id: String in profile_ids:
		var policy: Dictionary = registry.get_profile(profile_id)
		for seed_value: int in seeds:
			var first = GeneratorScript.new()
			first.configure(profile_id, seed_value)
			var first_position: Vector3 = first.find_spawn_position()
			var first_snapshot: Dictionary = first.get_last_spawn_quality_snapshot()
			var second = GeneratorScript.new()
			second.configure(profile_id, seed_value)
			var second_position: Vector3 = second.find_spawn_position()
			var resolver = SpawnResolverScript.new()
			var world_proxy := GeneratorWorldProxy.new()
			world_proxy.generator = first
			var resolved_position: Vector3 = resolver.resolve(
				world_proxy, first_position, first_position
			)
			world_proxy.generator = null
			world_proxy.free()
			_check(
				first_position.is_equal_approx(second_position),
				"%s seed %d selects a deterministic spawn" % [profile_id, seed_value],
			)
			_check(
				resolved_position.is_equal_approx(first_position),
				"%s seed %d emits the final grounded player and respawn position"
				% [profile_id, seed_value],
			)
			_check(
				bool(first_snapshot.get("meets_thresholds", false))
				and not bool(first_snapshot.get("fallback_used", true)),
				"%s seed %d selects a scored spawn without fallback" % [profile_id, seed_value],
			)
			_check(
				float(first_snapshot.get("clearance_ratio", 0.0))
				>= float(policy.get("minimum_clearance_ratio", 1.0)),
				"%s seed %d preserves body and canopy clearance" % [profile_id, seed_value],
			)
			_check(
				int(first_snapshot.get("walkable_neighbors", 0))
				>= int(policy.get("minimum_walkable_neighbors", 8)),
				"%s seed %d preserves a local movement radius" % [profile_id, seed_value],
			)
			_check(
				int(first_snapshot.get("open_view_directions", 0))
				>= int(policy.get("minimum_open_view_directions", 4))
				and int(first_snapshot.get("forward_clear_distance", 0))
				>= int(policy.get("minimum_forward_view_distance", 6)),
				"%s seed %d preserves first-frame exploration visibility" % [profile_id, seed_value],
			)
			_check(
				float(first_snapshot.get("nearest_obstacle_distance", 0.0))
				>= float(policy.get("minimum_obstacle_distance", 8.0)),
				"%s seed %d keeps profile obstacles away from spawn" % [profile_id, seed_value],
			)
			_check(
				str(first_snapshot.get("surface_block", ""))
				not in (policy.get("rejected_surface_blocks", []) as Array),
				"%s seed %d rejects unsafe or misleading surfaces" % [profile_id, seed_value],
			)
			_check(
				int(first_snapshot.get("evaluated_candidates", 0))
				<= int(policy.get("candidate_budget", 0)),
				"%s seed %d obeys the hard candidate budget" % [profile_id, seed_value],
			)
			print(
				"SPAWN_EXPERIENCE profile=%s seed=%d position=%s score=%.4f highest=%.4f clearance=%.4f walkable=%d views=%d forward=%d obstacle=%.3f scanned=%d evaluated=%d degraded=%s elapsed_usec=%d termination=%s"
				% [
					profile_id,
					seed_value,
					first_position,
					float(first_snapshot.get("score", 0.0)),
					float(first_snapshot.get("highest_score", 0.0)),
					float(first_snapshot.get("clearance_ratio", 0.0)),
					int(first_snapshot.get("walkable_neighbors", 0)),
					int(first_snapshot.get("open_view_directions", 0)),
					int(first_snapshot.get("forward_clear_distance", 0)),
					float(first_snapshot.get("nearest_obstacle_distance", 0.0)),
					int(first_snapshot.get("scanned_columns", 0)),
					int(first_snapshot.get("evaluated_candidates", 0)),
					str(bool(first_snapshot.get("degraded", true))),
					int(first_snapshot.get("elapsed_usec", 0)),
					str(first_snapshot.get("termination_condition", "")),
				]
			)
			# Drop per-iteration RefCounted references so internal FastNoiseLite
			# and registry objects are released before the next seed cycle.
			first = null
			second = null
			resolver = null
	registry = null
	if failures.is_empty():
		print("QA SPAWN EXPERIENCE PASS | checks=%d | profiles=%d | seeds=%d" % [
			checks,
			profile_ids.size(),
			seeds.size(),
		])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA SPAWN EXPERIENCE FAILURE: %s" % failure)
		print("QA SPAWN EXPERIENCE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
		quit(1)


func _user_argument(name: String) -> String:
	var prefix := "--%s=" % name
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix).strip_edges()
	return ""


func _check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		failures.append(description)
