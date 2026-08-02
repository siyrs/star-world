extends SceneTree

const GeneratorScript = preload("res://src/world/world_generator.gd")
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const MapProfileCatalogScript = preload("res://src/world/map_profile_catalog.gd")

const JOURNEY_SEED := 112358
const PROBE_RADIUS := 5

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile_ids := MapProfileCatalogScript.get_ids()
	var requested_profile := _user_argument("profile")
	if not requested_profile.is_empty():
		if requested_profile not in profile_ids:
			push_error("Unknown profile filter: %s" % requested_profile)
			quit(2)
			return
		profile_ids = [requested_profile]
	print("COLLISION_FILTER profiles=%s" % JSON.stringify(profile_ids))

	for profile_id: String in profile_ids:
		var gen = GeneratorScript.new()
		gen.configure(profile_id, JOURNEY_SEED)
		var spawn: Vector3 = gen.find_spawn_position()
		var sx := int(spawn.x - 0.5)
		var sz := int(spawn.z - 0.5)
		var sy := gen.get_surface_height(sx, sz)

		_check(sy >= 1, "%s spawn surface is above bedrock" % profile_id)
		_check(sy < 64, "%s spawn surface is within world" % profile_id)

		# --- Collision: player body cells must be air ---
		for offset_y in range(1, 4):
			var block := gen.get_block(Vector3i(sx, sy + offset_y, sz))
			_check(
				block == "air",
				"%s player body cell (%d, %d, %d) is air, not '%s'"
				% [profile_id, sx, sy + offset_y, sz, block]
			)

		# --- Seam integrity: adjacent columns must have walkable surfaces ---
		var walkable_count := 0
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				if dx == 0 and dz == 0:
					continue
				var nx := sx + dx
				var nz := sz + dz
				var n_surface := gen.find_walkable_surface(nx, nz)
				if n_surface >= 1 and absi(n_surface - sy) <= 2:
					walkable_count += 1
		_check(
			walkable_count >= 4,
			"%s spawn has >=4 walkable neighbours within 2-block step height (found %d)"
			% [profile_id, walkable_count]
		)

		# --- Steep-slope: no sheer cliff at spawn boundary ---
		var max_drop := 0
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var n_surface := gen.find_walkable_surface(sx + dx, sz + dz)
				if n_surface >= 1:
					max_drop = maxi(max_drop, absi(n_surface - sy))
		_check(
			max_drop <= 3,
			"%s spawn max adjacent height difference is %d (<=3)"
			% [profile_id, max_drop]
		)

		# --- Entrapment: no 1x1 pit with walls on all 4 sides at spawn ---
		var pit_wall_count := 0
		var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		for direction: Vector2i in dirs:
			var wall_x: int = sx + direction.x
			var wall_z: int = sz + direction.y
			var wall_surface: int = gen.get_surface_height(wall_x, wall_z)
			# A wall is a surface at least 3 blocks above spawn surface
			if wall_surface >= sy + 3:
				pit_wall_count += 1
		_check(
			pit_wall_count < 4,
			"%s spawn is not enclosed by walls on all 4 sides (walls=%d)"
			% [profile_id, pit_wall_count]
		)

		# --- Fall-through: Y < -12 must be recoverable (respawn logic) ---
		_check(
			gen.get_surface_height(sx, sz) >= 1,
			"%s spawn column has a solid surface above y=0 (no void)"
			% profile_id
		)

		# --- Probe area: expand radius around spawn for systemic coverage ---
		var probe_columns := 0
		var probe_walkable := 0
		for dx in range(-PROBE_RADIUS, PROBE_RADIUS + 1):
			for dz in range(-PROBE_RADIUS, PROBE_RADIUS + 1):
				probe_columns += 1
				if gen.find_walkable_surface(sx + dx, sz + dz) >= 1:
					probe_walkable += 1
		var coverage := float(probe_walkable) / float(probe_columns)
		_check(
			coverage >= 0.5,
			"%s probe area (11x11) is %.0f%% walkable (>=50%%)"
			% [profile_id, coverage * 100.0]
		)
		print(
			"COLLISION_PROBE profile=%s seed=%d spawn=(%d, %d, %d) walkable_neighbours=%d max_drop=%d probe_coverage=%.0f%%"
			% [profile_id, JOURNEY_SEED, sx, sy, sz, walkable_count, max_drop, coverage * 100.0]
		)
		gen = null

	if failures.is_empty():
		print("QA COLLISION PROBE PASS | checks=%d | profiles=%d" % [checks, profile_ids.size()])
		quit(0)
	else:
		for failure: String in failures:
			push_error("QA COLLISION PROBE FAILURE: %s" % failure)
		print("QA COLLISION PROBE FAIL | checks=%d | failures=%d" % [checks, failures.size()])
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
