class_name VoxelTargetResolver
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const EPSILON := 0.001
const AXIS_EPSILON := 0.0001
const GRID_SAMPLE_STEP := 0.05


func resolve(ray: RayCast3D, world: Node) -> Dictionary:
	if (
		ray == null
		or not is_instance_valid(ray)
		or world == null
		or not world.has_method("world_to_block")
		or not world.has_method("get_block")
	):
		return {}
	ray.hit_from_inside = true
	ray.force_raycast_update()
	var grid_result := _resolve_grid_ray(ray, world)
	var origin_block: Vector3i = world.call("world_to_block", ray.global_position)
	var origin_block_id := str(world.call("get_block", origin_block))
	if _is_grid_target(origin_block_id) and not grid_result.is_empty():
		return grid_result
	if not ray.is_colliding():
		return grid_result
	var collider: Variant = ray.get_collider()
	if collider is Node and (
		collider.is_in_group("creatures") or collider.has_method("take_damage")
	):
		return {"type":"entity", "collider":collider}
	var point: Vector3 = ray.get_collision_point()
	var ray_direction: Vector3 = _ray_direction(ray)
	var raw_normal: Vector3 = ray.get_collision_normal()
	# Godot reports a zero normal when a ray starts inside a collision shape.
	# Traverse the voxel data in that case so close-up tree canopies and walls
	# still produce the exit face and its adjacent placement cell.
	if raw_normal.length_squared() <= AXIS_EPSILON:
		if not grid_result.is_empty():
			return grid_result
	var physics_result := _resolve_block_sample(
		point,
		raw_normal,
		ray_direction,
		Callable(world, "world_to_block"),
		Callable(world, "get_block"),
		collider
	)
	if not physics_result.is_empty():
		if (
			str(physics_result.get("placement_block_id", BlockRegistryScript.AIR))
			!= BlockRegistryScript.AIR
			and not grid_result.is_empty()
			and str(grid_result.get("placement_block_id", ""))
			== BlockRegistryScript.AIR
		):
			return grid_result
		return physics_result
	return grid_result


func resolve_from_sample(
	point: Vector3,
	raw_normal: Vector3,
	ray_direction: Vector3,
	world_to_block: Callable,
	get_block: Callable
) -> Dictionary:
	return _resolve_block_sample(
		point, raw_normal, ray_direction, world_to_block, get_block, null
	)


func resolve_grid_from_sample(
	origin: Vector3,
	ray_direction: Vector3,
	max_distance: float,
	world_to_block: Callable,
	get_block: Callable
) -> Dictionary:
	if (
		not world_to_block.is_valid()
		or not get_block.is_valid()
		or max_distance <= 0.0
	):
		return {}
	var direction := ray_direction.normalized()
	if direction.length_squared() <= AXIS_EPSILON:
		return {}
	var current_cell: Vector3i = world_to_block.call(origin)
	var current_id := str(get_block.call(current_cell))
	var started_inside := _is_grid_target(current_id)
	var last_solid_cell := current_cell
	var last_solid_id := current_id
	var distance := GRID_SAMPLE_STEP
	while distance <= max_distance + GRID_SAMPLE_STEP:
		var sample_position := origin + direction * minf(distance, max_distance)
		var next_cell: Vector3i = world_to_block.call(sample_position)
		distance += GRID_SAMPLE_STEP
		if next_cell == current_cell:
			continue
		var next_id := str(get_block.call(next_cell))
		var next_is_target := _is_grid_target(next_id)
		if started_inside:
			if not next_is_target:
				if next_id != BlockRegistryScript.AIR:
					current_cell = next_cell
					continue
				var exit_normal := next_cell - last_solid_cell
				if _is_cardinal(exit_normal):
					return _grid_result(
						last_solid_cell,
						last_solid_id,
						next_cell,
						BlockRegistryScript.AIR,
						exit_normal,
						origin + direction * maxf(0.0, distance - GRID_SAMPLE_STEP)
					)
			else:
				last_solid_cell = next_cell
				last_solid_id = next_id
		elif next_is_target:
			var entry_normal := current_cell - next_cell
			if _is_cardinal(entry_normal):
				return _grid_result(
					next_cell,
					next_id,
					current_cell,
					current_id,
					entry_normal,
					origin + direction * maxf(0.0, distance - GRID_SAMPLE_STEP)
				)
		current_cell = next_cell
		current_id = next_id
	return {}


func _resolve_block_sample(
	point: Vector3,
	raw_normal: Vector3,
	ray_direction: Vector3,
	world_to_block: Callable,
	get_block: Callable,
	collider: Variant
) -> Dictionary:
	if not world_to_block.is_valid() or not get_block.is_valid():
		return {}
	var direction: Vector3 = ray_direction.normalized()
	if direction.length_squared() <= AXIS_EPSILON:
		return {}
	# Probe into the surface along the actual ray. This identifies the voxel the
	# player sees even when the collision point lies exactly on an integer edge.
	var hit_position: Vector3i = world_to_block.call(point + direction * EPSILON)
	var hit_block: String = str(get_block.call(hit_position))
	if hit_block == BlockRegistryScript.AIR:
		# Concave shapes may report a point infinitesimally inside the source face.
		# The opposite probe recovers the visible voxel without changing the face.
		hit_position = world_to_block.call(point - direction * EPSILON)
		hit_block = str(get_block.call(hit_position))
	if hit_block == BlockRegistryScript.AIR:
		return {}
	var face_normal: Vector3i = _resolve_face_normal(
		raw_normal, point, hit_position, direction
	)
	if face_normal == Vector3i.ZERO:
		return {}
	var placement_position := hit_position + face_normal
	return {
		"type":"block",
		"collider":collider,
		"collision_point":point,
		"collision_normal":Vector3(face_normal),
		"hit_position":hit_position,
		"hit_block_id":hit_block,
		"placement_position":placement_position,
		"placement_block_id":str(get_block.call(placement_position)),
	}


func _resolve_grid_ray(ray: RayCast3D, world: Node) -> Dictionary:
	var origin := ray.global_position
	var endpoint := ray.to_global(ray.target_position)
	var direction := endpoint - origin
	return resolve_grid_from_sample(
		origin,
		direction,
		direction.length(),
		Callable(world, "world_to_block"),
		Callable(world, "get_block")
	)


func _grid_result(
	hit_position: Vector3i,
	hit_block_id: String,
	placement_position: Vector3i,
	placement_block_id: String,
	face_normal: Vector3i,
	collision_point: Vector3
) -> Dictionary:
	return {
		"type":"block",
		"collider":null,
		"collision_point":collision_point,
		"collision_normal":Vector3(face_normal),
		"hit_position":hit_position,
		"hit_block_id":hit_block_id,
		"placement_position":placement_position,
		"placement_block_id":placement_block_id,
	}


func _is_grid_target(block_id: String) -> bool:
	return (
		block_id != BlockRegistryScript.AIR
		and BlockRegistryScript.is_solid(block_id)
	)


func _is_cardinal(value: Vector3i) -> bool:
	return absi(value.x) + absi(value.y) + absi(value.z) == 1


func _ray_direction(ray: RayCast3D) -> Vector3:
	var origin: Vector3 = ray.global_position
	var endpoint: Vector3 = ray.to_global(ray.target_position)
	var direction: Vector3 = endpoint - origin
	return direction.normalized() if direction.length_squared() > AXIS_EPSILON else Vector3.ZERO


func _resolve_face_normal(
	raw_normal: Vector3,
	point: Vector3,
	hit_position: Vector3i,
	ray_direction: Vector3
) -> Vector3i:
	var snapped: Vector3i = _dominant_axis(raw_normal)
	if snapped != Vector3i.ZERO:
		return snapped
	var local_point: Vector3 = point - Vector3(hit_position)
	var candidates: Array[Dictionary] = [
		{"normal":Vector3i.LEFT, "distance":absf(local_point.x)},
		{"normal":Vector3i.RIGHT, "distance":absf(1.0 - local_point.x)},
		{"normal":Vector3i.DOWN, "distance":absf(local_point.y)},
		{"normal":Vector3i.UP, "distance":absf(1.0 - local_point.y)},
		{"normal":Vector3i(0, 0, -1), "distance":absf(local_point.z)},
		{"normal":Vector3i(0, 0, 1), "distance":absf(1.0 - local_point.z)},
	]
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("distance", INF)) < float(b.get("distance", INF))
	)
	if not candidates.is_empty():
		return candidates[0].get("normal", Vector3i.ZERO)
	return -_dominant_axis(ray_direction)


func _dominant_axis(value: Vector3) -> Vector3i:
	var absolute := value.abs()
	if absolute.length_squared() <= AXIS_EPSILON:
		return Vector3i.ZERO
	if absolute.x >= absolute.y and absolute.x >= absolute.z:
		return Vector3i(1 if value.x >= 0.0 else -1, 0, 0)
	if absolute.y >= absolute.x and absolute.y >= absolute.z:
		return Vector3i(0, 1 if value.y >= 0.0 else -1, 0)
	return Vector3i(0, 0, 1 if value.z >= 0.0 else -1)
