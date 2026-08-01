class_name StarWorldGenerator
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const ResourceDistributionRegistryScript = preload("res://src/world/resource_distribution_registry.gd")
const WorldDecorationRegistryScript = preload("res://src/world/world_decoration_registry.gd")
const WorldDecorationPolicyScript = preload("res://src/world/world_decoration_policy.gd")
const SpawnQualityRegistryScript = preload("res://src/world/spawn_quality_registry.gd")
const WORLD_HEIGHT := 64
const SEA_LEVEL := 18
const RESOURCE_ROLL_SALT := 211
const SPAWN_DIRECTIONS := [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
]
const SPAWN_NEIGHBOR_DIRECTIONS := [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]

var profile_id := "star_continent"
var seed_value := 734521
var height_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var cave_noise := FastNoiseLite.new()
var resource_distribution = ResourceDistributionRegistryScript.new()
var world_decorations = WorldDecorationRegistryScript.new()
var spawn_quality = SpawnQualityRegistryScript.new()
var _decoration_profile: Dictionary = {}
var _spawn_quality_profile: Dictionary = {}
var _decoration_tree_exclusion_density := 0
var _decoration_profile_refresh_count := 0
var _last_spawn_quality_snapshot: Dictionary = {}


func _init() -> void:
	_refresh_decoration_profile()
	_refresh_spawn_quality_profile()


func configure(p_profile_id: String, p_seed: int) -> void:
	profile_id = normalize_profile_id(p_profile_id)
	_refresh_decoration_profile()
	_refresh_spawn_quality_profile()
	seed_value = p_seed
	height_noise.seed = seed_value
	height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	height_noise.frequency = 0.012
	height_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	height_noise.fractal_octaves = 4
	detail_noise.seed = seed_value ^ 0x51F2A3
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.frequency = 0.038
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 3
	cave_noise.seed = seed_value ^ 0x7A31C9
	cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	cave_noise.frequency = 0.075
	cave_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	cave_noise.fractal_octaves = 3


func normalize_profile_id(value: String) -> String:
	match value:
		"green_continent", "green", "star_continent": return "star_continent"
		"desert", "desert_ruins": return "desert_ruins"
		"ice", "snow", "frozen_wastes": return "frozen_wastes"
		"mountains", "sky", "sky_islands": return "sky_islands"
		"caves", "cave", "abyss_world": return "abyss_world"
		_: return "star_continent"


func _refresh_decoration_profile() -> void:
	_decoration_profile = world_decorations.get_profile(profile_id)
	_decoration_tree_exclusion_density = int(
		_decoration_profile.get("tree_exclusion_density", 0)
	)
	_decoration_profile_refresh_count += 1


func get_decoration_profile_snapshot() -> Dictionary:
	var snapshot := world_decorations.get_snapshot(profile_id)
	var raw_rules: Variant = _decoration_profile.get("rules", [])
	snapshot["profile_refresh_count"] = _decoration_profile_refresh_count
	snapshot["cached_rule_count"] = (raw_rules as Array).size() if raw_rules is Array else 0
	return snapshot


func get_decoration_summary() -> String:
	return world_decorations.get_summary(profile_id)


func get_spawn_quality_profile_snapshot() -> Dictionary:
	return spawn_quality.get_snapshot(profile_id)


func get_last_spawn_quality_snapshot() -> Dictionary:
	return _last_spawn_quality_snapshot.duplicate(true)


func get_poi_snapshot(x: int, z: int) -> Dictionary:
	return WorldDecorationPolicyScript.get_poi_snapshot(
		_decoration_profile,
		x,
		z,
		Callable(self, "_hash_roll")
	)


func get_block(block_position: Vector3i) -> String:
	if block_position.y < 0 or block_position.y >= WORLD_HEIGHT:
		return BlockRegistryScript.AIR
	if block_position.y == 0:
		return BlockRegistryScript.BEDROCK
	var terrain_height := get_surface_height(block_position.x, block_position.z)
	if profile_id == "sky_islands":
		return _get_sky_block(block_position, terrain_height)
	if block_position.y > terrain_height:
		if profile_id == "star_continent" or profile_id == "sky_islands":
			var tree_block := _get_tree_block(block_position, terrain_height)
			if tree_block != BlockRegistryScript.AIR:
				return tree_block
		if profile_id == "star_continent" and block_position.y <= SEA_LEVEL:
			return "water"
		if profile_id == "frozen_wastes" and block_position.y <= SEA_LEVEL:
			return "ice" if block_position.y == SEA_LEVEL else "water"
		if block_position.y <= terrain_height + 4:
			var decoration := _get_decoration_block(block_position, terrain_height)
			if decoration != BlockRegistryScript.AIR:
				return decoration
		return BlockRegistryScript.AIR
	if profile_id == "abyss_world" and block_position.y > 3 and block_position.y < terrain_height - 2:
		var cave_density := cave_noise.get_noise_3d(
			block_position.x,
			block_position.y * 0.9,
			block_position.z
		)
		if cave_density > 0.51:
			return (
				"lava"
				if block_position.y <= 4
				and _hash_roll(block_position.x, block_position.y, block_position.z, 17) < 3600
				else BlockRegistryScript.AIR
			)
	return _layer_block(block_position, terrain_height)


func get_surface_height(x: int, z: int) -> int:
	var broad := height_noise.get_noise_2d(x, z)
	var detail := detail_noise.get_noise_2d(x, z)
	match profile_id:
		"desert_ruins":
			return clampi(18 + roundi(broad * 5.0 + detail * 2.0), 10, 31)
		"frozen_wastes":
			return clampi(22 + roundi(broad * 10.0 + detail * 3.0), 11, 43)
		"sky_islands":
			return clampi(42 + roundi(broad * 5.0 + detail * 2.0), 32, 53)
		"abyss_world":
			return clampi(35 + roundi(broad * 4.0 + detail * 2.0), 27, 44)
		_:
			var river := absf(detail_noise.get_noise_2d(x * 0.62, z * 0.62))
			if river < 0.065:
				return SEA_LEVEL - 2
			return clampi(21 + roundi(broad * 7.0 + detail * 2.0), 12, 35)


func find_spawn_position() -> Vector3:
	var started_at := Time.get_ticks_usec()
	var search_radius := int(_spawn_quality_profile.get("search_radius", 64))
	var candidate_budget := int(_spawn_quality_profile.get("candidate_budget", 192))
	var wall_time_budget_usec := int(_spawn_quality_profile.get("wall_time_budget_ms", 30000)) * 1000
	var scanned_columns := 0
	var evaluated_candidates := 0
	var first_safe_candidate := Vector3(INF, INF, INF)
	var first_safe_snapshot: Dictionary = {}
	var best_candidate := Vector3(INF, INF, INF)
	var best_snapshot: Dictionary = {}
	var highest_scoring_candidate := Vector3(INF, INF, INF)
	var highest_scoring_snapshot: Dictionary = {}
	var termination_condition := "search_radius_exhausted"
	for radius in range(0, search_radius + 1):
		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				if radius > 0 and absi(x) != radius and absi(z) != radius:
					continue
				scanned_columns += 1
				var top := find_walkable_surface(x, z)
				if top < 1:
					continue
				var candidate := Vector3(x + 0.5, top + 1.05, z + 0.5)
				var snapshot := _evaluate_spawn_candidate(x, z, top, radius)
				evaluated_candidates += 1
				if bool(snapshot.get("hard_safe", false)) and not _is_valid_spawn_found(first_safe_candidate):
					first_safe_candidate = candidate
					first_safe_snapshot = snapshot
				if bool(snapshot.get("hard_safe", false)) and (
					highest_scoring_snapshot.is_empty()
					or float(snapshot.get("score", 0.0))
					> float(highest_scoring_snapshot.get("score", 0.0))
				):
					highest_scoring_candidate = candidate
					highest_scoring_snapshot = snapshot
				if bool(snapshot.get("meets_thresholds", false)) and (
					best_snapshot.is_empty()
					or float(snapshot.get("score", 0.0)) > float(best_snapshot.get("score", 0.0))
				):
					best_candidate = candidate
					best_snapshot = snapshot
				if evaluated_candidates >= candidate_budget:
					termination_condition = "candidate_budget_reached"
					break
				if Time.get_ticks_usec() - started_at >= wall_time_budget_usec:
					termination_condition = "wall_time_budget_exhausted"
					break
			if evaluated_candidates >= candidate_budget:
				break
			if termination_condition == "wall_time_budget_exhausted":
				break
		if evaluated_candidates >= candidate_budget:
			break
		if termination_condition == "wall_time_budget_exhausted":
			break
	if _is_valid_spawn_found(best_candidate):
		_finalize_spawn_snapshot(
			best_snapshot,
			highest_scoring_snapshot,
			scanned_columns,
			evaluated_candidates,
			termination_condition,
			started_at,
			false
		)
		_last_spawn_quality_snapshot = best_snapshot
		return best_candidate
	if _is_valid_spawn_found(highest_scoring_candidate):
		_finalize_spawn_snapshot(
			highest_scoring_snapshot,
			highest_scoring_snapshot,
			scanned_columns,
			evaluated_candidates,
			termination_condition,
			started_at,
			true
		)
		_last_spawn_quality_snapshot = highest_scoring_snapshot
		push_warning(
			"Spawn quality thresholds were not met for profile=%s seed=%d; using highest-scoring hard-safe candidate."
			% [profile_id, seed_value]
		)
		return highest_scoring_candidate
	if _is_valid_spawn_found(first_safe_candidate):
		_finalize_spawn_snapshot(
			first_safe_snapshot,
			highest_scoring_snapshot,
			scanned_columns,
			evaluated_candidates,
			termination_condition,
			started_at,
			true
		)
		_last_spawn_quality_snapshot = first_safe_snapshot
		push_warning(
			"Spawn quality thresholds were not met for profile=%s seed=%d; using first safe candidate."
			% [profile_id, seed_value]
		)
		return first_safe_candidate
	_last_spawn_quality_snapshot = {
		"profile_id": profile_id,
		"seed": seed_value,
		"meets_thresholds": false,
		"fallback_used": true,
		"scanned_columns": scanned_columns,
		"evaluated_candidates": evaluated_candidates,
		"highest_score": 0.0,
		"termination_condition": termination_condition,
		"elapsed_usec": Time.get_ticks_usec() - started_at,
	}
	# Desperate fallback: scan for any walkable surface near origin, then
	# expand search radius before the last-resort position.
	var fallback_spawn := _find_any_walkable_surface(16)
	if _is_valid_spawn_found(fallback_spawn):
		push_warning(
			"No safe spawn found for profile=%s seed=%d; falling back to nearest walkable surface at %s."
			% [profile_id, seed_value, fallback_spawn]
		)
		return fallback_spawn
	# Second pass with a wider radius before the last resort.
	fallback_spawn = _find_any_walkable_surface(search_radius)
	if _is_valid_spawn_found(fallback_spawn):
		push_warning(
			"No safe spawn near origin for profile=%s seed=%d; falling back to distant walkable surface at %s."
			% [profile_id, seed_value, fallback_spawn]
		)
		return fallback_spawn
	# Truly no walkable surface anywhere — place the player just under the
	# world ceiling so they will immediately fall onto the highest solid block
	# instead of spawning in the void at an arbitrary Y.
	push_error(
		"No walkable surface found anywhere for profile=%s seed=%d; spawning at ceiling fallback."
		% [profile_id, seed_value]
	)
	return Vector3(0.5, float(WORLD_HEIGHT) - 3.0, 0.5)


func find_walkable_surface(x: int, z: int) -> int:
	for y in range(WORLD_HEIGHT - 3, 0, -1):
		var block_id := get_block(Vector3i(x, y, z))
		if not BlockRegistryScript.is_solid(block_id) or block_id in ["leaves", "ice"]:
			continue
		# The player origin starts above the surface and the first-person camera
		# occupies the third cell. Keep all three cells clear so nearby decoration
		# or a tree canopy cannot hide the initial view even when the body fits.
		if (
			get_block(Vector3i(x, y + 1, z)) == BlockRegistryScript.AIR
			and get_block(Vector3i(x, y + 2, z)) == BlockRegistryScript.AIR
			and get_block(Vector3i(x, y + 3, z)) == BlockRegistryScript.AIR
		):
			return y
	return -1


func _find_any_walkable_surface(max_radius: int) -> Vector3:
	for radius in range(0, max_radius + 1):
		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				if radius > 0 and absi(x) != radius and absi(z) != radius:
					continue
				var top := find_walkable_surface(x, z)
				if top >= 1:
					return Vector3(x + 0.5, top + 1.05, z + 0.5)
	return Vector3(INF, INF, INF)


func _refresh_spawn_quality_profile() -> void:
	_spawn_quality_profile = spawn_quality.get_profile(profile_id)


func _evaluate_spawn_candidate(x: int, z: int, top: int, radius: int) -> Dictionary:
	var surface_block: String = get_block(Vector3i(x, top, z))
	var rejected_surfaces: Array = _spawn_quality_profile.get("rejected_surface_blocks", [])
	var hazard_blocks: Array = _spawn_quality_profile.get("hazard_blocks", [])
	var clearance_data: Dictionary = _evaluate_spawn_clearance(x, z, top)
	var clearance_ratio: float = float(clearance_data.get("clearance_ratio", 0.0))
	var body_blocked: bool = bool(clearance_data.get("body_blocked", true))
	var hazard_in_body: bool = bool(clearance_data.get("hazard_in_body", true))
	var walkable_neighbors: int = _evaluate_spawn_walkability(x, z, top, rejected_surfaces)
	var view_data: Dictionary = _evaluate_spawn_visibility(x, z, top)
	var open_view_directions: int = int(view_data.get("open_view_directions", 0))
	var forward_clear_distance: int = int(view_data.get("forward_clear_distance", 0))
	var visibility_ratio: float = float(view_data.get("visibility_ratio", 0.0))
	var obstacle_distance: float = _evaluate_spawn_obstacle_proximity(x, z, top)
	var walkability_ratio: float = float(walkable_neighbors) / float(SPAWN_NEIGHBOR_DIRECTIONS.size())
	var proximity_ratio: float = 1.0 - clampf(
		float(radius) / float(maxi(1, int(_spawn_quality_profile.get("search_radius", 64)))),
		0.0,
		1.0
	)
	var weights: Dictionary = _spawn_quality_profile.get("weights", {})
	var score: float = (
		clearance_ratio * float(weights.get("clearance", 0.35))
		+ walkability_ratio * float(weights.get("walkability", 0.25))
		+ visibility_ratio * float(weights.get("visibility", 0.30))
		+ proximity_ratio * float(weights.get("proximity", 0.10))
	)
	var surface_ok: bool = surface_block not in rejected_surfaces
	var clearance_ok: bool = clearance_ratio >= float(_spawn_quality_profile.get("minimum_clearance_ratio", 0.84))
	var walkable_ok: bool = walkable_neighbors >= int(_spawn_quality_profile.get("minimum_walkable_neighbors", 6))
	var view_ok: bool = (
		open_view_directions >= int(_spawn_quality_profile.get("minimum_open_view_directions", 3))
		and forward_clear_distance >= int(_spawn_quality_profile.get("minimum_forward_view_distance", 4))
	)
	var obstacle_ok: bool = obstacle_distance >= float(_spawn_quality_profile.get("minimum_obstacle_distance", 3.0))
	var meets_thresholds: bool = (
		surface_ok and clearance_ok and walkable_ok and view_ok and obstacle_ok
	)
	# "Hard safe" requires the position to be immediately survivable:
	# the surface is supported, the body column is not blocked or filled
	# with hazards, and at least one neighbour is walkable.
	var hard_safe: bool = (
		not body_blocked
		and not hazard_in_body
		and surface_ok
		and walkable_neighbors >= 1
	)
	return {
		"profile_id": profile_id,
		"seed": seed_value,
		"position": [x + 0.5, top + 1.05, z + 0.5],
		"surface_block": surface_block,
		"score": snappedf(score, 0.0001),
		"clearance_ratio": snappedf(clearance_ratio, 0.0001),
		"walkable_neighbors": walkable_neighbors,
		"open_view_directions": open_view_directions,
		"forward_clear_distance": forward_clear_distance,
		"nearest_obstacle_distance": snappedf(obstacle_distance, 0.001),
		"hard_safe": hard_safe,
		"meets_thresholds": meets_thresholds,
	}


func _evaluate_spawn_clearance(x: int, z: int, top: int) -> Dictionary:
	var hazard_blocks: Array = _spawn_quality_profile.get("hazard_blocks", [])
	var clearance_radius := int(_spawn_quality_profile.get("clearance_radius", 2))
	var clear_columns := 0
	var total_columns := 0
	var body_blocked := true
	var hazard_in_body := false
	for offset_x in range(-clearance_radius, clearance_radius + 1):
		for offset_z in range(-clearance_radius, clearance_radius + 1):
			total_columns += 1
			var column_clear := true
			for offset_y in range(1, 4):
				var block_id: String = get_block(Vector3i(x + offset_x, top + offset_y, z + offset_z))
				if BlockRegistryScript.is_solid(block_id):
					column_clear = false
					break
				if block_id in hazard_blocks:
					hazard_in_body = true
					column_clear = false
					break
			# The centre column (offset 0,0) represents the player body.
			# If any of its 3 cells is blocked the player cannot stand up.
			if offset_x == 0 and offset_z == 0 and not column_clear:
				body_blocked = true
			elif offset_x == 0 and offset_z == 0:
				body_blocked = false
			if column_clear:
				clear_columns += 1
	return {
		"clearance_ratio": snappedf(float(clear_columns) / float(maxi(1, total_columns)), 0.0001),
		"body_blocked": body_blocked,
		"hazard_in_body": hazard_in_body,
	}


func _evaluate_spawn_walkability(x: int, z: int, top: int, rejected_surfaces: Array) -> int:
	var walkable_neighbors := 0
	var maximum_step_height := int(_spawn_quality_profile.get("maximum_step_height", 1))
	for direction: Vector2i in SPAWN_NEIGHBOR_DIRECTIONS:
		var neighbor_top := find_walkable_surface(x + direction.x, z + direction.y)
		if neighbor_top >= 1 and absi(neighbor_top - top) <= maximum_step_height:
			var neighbor_surface := get_block(Vector3i(x + direction.x, neighbor_top, z + direction.y))
			if neighbor_surface not in rejected_surfaces:
				walkable_neighbors += 1
	return walkable_neighbors


func _evaluate_spawn_visibility(x: int, z: int, top: int) -> Dictionary:
	var view_distance := int(_spawn_quality_profile.get("view_distance", 6))
	var view_clear_distances: Array[int] = []
	var total_clear_view_cells := 0
	var open_view_directions := 0
	for direction: Vector2i in SPAWN_DIRECTIONS:
		var clear_distance := 0
		for distance in range(1, view_distance + 1):
			var block_id := get_block(
				Vector3i(x + direction.x * distance, top + 2, z + direction.y * distance)
			)
			if BlockRegistryScript.is_solid(block_id):
				break
			clear_distance = distance
		view_clear_distances.append(clear_distance)
		total_clear_view_cells += clear_distance
		if clear_distance >= view_distance:
			open_view_directions += 1
	var forward_direction := _spawn_forward_direction()
	var forward_index := SPAWN_DIRECTIONS.find(forward_direction)
	return {
		"open_view_directions": open_view_directions,
		"forward_clear_distance": view_clear_distances[forward_index] if forward_index >= 0 else 0,
		"visibility_ratio": snappedf(float(total_clear_view_cells) / float(SPAWN_DIRECTIONS.size() * view_distance), 0.0001),
	}


func _evaluate_spawn_obstacle_proximity(x: int, z: int, top: int) -> float:
	var nearby_obstacles: Array = _spawn_quality_profile.get("nearby_obstacle_blocks", [])
	var obstacle_scan_radius := int(_spawn_quality_profile.get("obstacle_scan_radius", 5))
	var nearest_obstacle_distance := float(obstacle_scan_radius + 1)
	for offset_x in range(-obstacle_scan_radius, obstacle_scan_radius + 1):
		for offset_z in range(-obstacle_scan_radius, obstacle_scan_radius + 1):
			if offset_x == 0 and offset_z == 0:
				continue
			var horizontal_distance := Vector2(offset_x, offset_z).length()
			if horizontal_distance >= nearest_obstacle_distance:
				continue
			for offset_y in range(1, 5):
				var block_id := get_block(Vector3i(x + offset_x, top + offset_y, z + offset_z))
				if block_id in nearby_obstacles:
					nearest_obstacle_distance = horizontal_distance
					break
	return snappedf(nearest_obstacle_distance, 0.001)


func _finalize_spawn_snapshot(
	selected_snapshot: Dictionary,
	highest_snapshot: Dictionary,
	scanned_columns: int,
	evaluated_candidates: int,
	termination_condition: String,
	started_at: int,
	degraded: bool
) -> void:
	selected_snapshot["scanned_columns"] = scanned_columns
	selected_snapshot["evaluated_candidates"] = evaluated_candidates
	selected_snapshot["highest_score"] = float(
		highest_snapshot.get("score", selected_snapshot.get("score", 0.0))
	)
	selected_snapshot["fallback_used"] = degraded
	selected_snapshot["degraded"] = degraded
	selected_snapshot["termination_condition"] = termination_condition
	selected_snapshot["elapsed_usec"] = Time.get_ticks_usec() - started_at


func _spawn_forward_direction() -> Vector2i:
	var raw_direction: Variant = _spawn_quality_profile.get("forward_direction", [0, -1])
	if raw_direction is Array and (raw_direction as Array).size() >= 2:
		var direction := Vector2i(int(raw_direction[0]), int(raw_direction[1]))
		if direction in SPAWN_DIRECTIONS:
			return direction
	return Vector2i(0, -1)


func _is_valid_spawn_found(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _layer_block(position: Vector3i, terrain_height: int) -> String:
	var depth := terrain_height - position.y
	if depth >= 4:
		return _ore_or_stone(position)
	match profile_id:
		"desert_ruins":
			if depth <= 3: return "sand"
		"frozen_wastes":
			if depth == 0: return "snow"
			if depth <= 3: return "dirt"
		"abyss_world":
			if depth == 0: return "stone_bricks"
			return "stone"
		_:
			if depth == 0: return "grass"
			if depth <= 3: return "dirt"
	return _ore_or_stone(position)


func _ore_or_stone(position: Vector3i) -> String:
	var roll := _hash_roll(position.x, position.y, position.z, RESOURCE_ROLL_SALT)
	return resource_distribution.resolve_block(profile_id, position.y, roll)


func _get_sky_block(position: Vector3i, terrain_height: int) -> String:
	var strength := _sky_island_strength(position.x, position.z)
	if strength <= 0.0:
		return BlockRegistryScript.AIR
	if position.y > terrain_height:
		var tree_block := _get_tree_block(position, terrain_height)
		if tree_block != BlockRegistryScript.AIR:
			return tree_block
		if position.y <= terrain_height + 4:
			return _get_decoration_block(position, terrain_height)
		return BlockRegistryScript.AIR
	var thickness := 3 + roundi(strength * 10.0)
	var bottom := terrain_height - thickness
	if position.y < bottom:
		return BlockRegistryScript.AIR
	var depth := terrain_height - position.y
	if depth == 0: return "grass"
	if depth <= 2: return "dirt"
	return _ore_or_stone(position)


func _sky_island_strength(x: int, z: int) -> float:
	var cell_size := 32
	var base_cell_x := floori(float(x) / cell_size)
	var base_cell_z := floori(float(z) / cell_size)
	var best := -1.0
	for cell_x in range(base_cell_x - 1, base_cell_x + 2):
		for cell_z in range(base_cell_z - 1, base_cell_z + 2):
			var offset_x := _hash_roll(cell_x, 0, cell_z, 91) % 15 - 7
			var offset_z := _hash_roll(cell_x, 0, cell_z, 131) % 15 - 7
			var center := Vector2(
				cell_x * cell_size + cell_size / 2 + offset_x,
				cell_z * cell_size + cell_size / 2 + offset_z
			)
			var radius := 11.0 + float(_hash_roll(cell_x, 0, cell_z, 177) % 8)
			var strength := 1.0 - Vector2(x, z).distance_to(center) / radius
			best = maxf(best, strength)
	return best


func _get_tree_block(position: Vector3i, terrain_height: int) -> String:
	if position.y <= terrain_height or position.y > terrain_height + 8:
		return BlockRegistryScript.AIR
	var density := 90 if profile_id == "sky_islands" else 185
	for tree_x in range(position.x - 2, position.x + 3):
		for tree_z in range(position.z - 2, position.z + 3):
			if not _tree_here(tree_x, tree_z, density):
				continue
			var ground := get_surface_height(tree_x, tree_z)
			if ground < SEA_LEVEL:
				continue
			if profile_id == "sky_islands" and _sky_island_strength(tree_x, tree_z) < 0.45:
				continue
			if (
				position.x == tree_x
				and position.z == tree_z
				and position.y >= ground + 1
				and position.y <= ground + 4
			):
				return "wood"
			var dx := absi(position.x - tree_x)
			var dz := absi(position.z - tree_z)
			if (
				position.y >= ground + 3
				and position.y <= ground + 5
				and dx <= 2
				and dz <= 2
			):
				if position.y < ground + 5 or dx + dz <= 2:
					return "leaves"
	return BlockRegistryScript.AIR


func _tree_here(x: int, z: int, density: int = 185) -> bool:
	return _hash_roll(x, 0, z, 701) < density


# Surface decorations and low-frequency POI structures are interpreted from a
# strict registry. Hash salts and thresholds remain identical to the legacy
# generator so unexplored chunks in existing worlds preserve their Seed output.
# The normalized profile is copied once per configure() call; the block hot path
# only reads that cached Dictionary and never allocates another deep copy.
func _get_decoration_block(position: Vector3i, terrain_height: int) -> String:
	var tree_present := (
		_decoration_tree_exclusion_density > 0
		and _tree_here(position.x, position.z, _decoration_tree_exclusion_density)
	)
	var sky_strength := (
		_sky_island_strength(position.x, position.z)
		if profile_id == "sky_islands"
		else 1.0
	)
	return WorldDecorationPolicyScript.resolve_block(
		_decoration_profile,
		position,
		terrain_height,
		tree_present,
		sky_strength,
		Callable(self, "_hash_roll")
	)


func _hash_roll(x: int, y: int, z: int, salt: int) -> int:
	var value := (
		(x * 73856093)
		^ (y * 19349663)
		^ (z * 83492791)
		^ seed_value
		^ (salt * 265443576)
	)
	value = (value ^ (value >> 13)) * 1274126177
	return int(value & 0x7FFFFFFF) % 10000
