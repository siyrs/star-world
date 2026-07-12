class_name PlayerSpawnResolver
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const BODY_RADIUS := 0.34
const BODY_HEIGHT := 1.8
const SEARCH_RADIUS := 8


func resolve(world: Node, preferred: Vector3, fallback: Vector3) -> Vector3:
	var safe_fallback := fallback if _is_reasonable_position(fallback) else Vector3(0.5, 50.0, 0.5)
	if (
		_is_reasonable_position(preferred)
		and is_position_clear(world, preferred)
		and is_position_supported(world, preferred)
	):
		return preferred
	var grounding_source := preferred if _is_finite_vector(preferred) else safe_fallback
	var grounded_preferred := _resolve_ground(world, grounding_source)
	if is_position_clear(world, grounded_preferred) and is_position_supported(world, grounded_preferred):
		return grounded_preferred
	var grounded_fallback := _resolve_ground(world, safe_fallback)
	if is_position_clear(world, grounded_fallback) and is_position_supported(world, grounded_fallback):
		return grounded_fallback
	for radius in range(1, SEARCH_RADIUS + 1):
		for offset_x in range(-radius, radius + 1):
			for offset_z in range(-radius, radius + 1):
				if absi(offset_x) != radius and absi(offset_z) != radius:
					continue
				var candidate := safe_fallback + Vector3(offset_x, 0.0, offset_z)
				candidate = _resolve_ground(world, candidate)
				if is_position_clear(world, candidate) and is_position_supported(world, candidate):
					return candidate
	return grounded_fallback


func is_position_clear(world: Node, feet_position: Vector3) -> bool:
	if not _is_reasonable_position(feet_position):
		return false
	if world == null or not world.has_method("get_block"):
		return true
	var minimum := feet_position + Vector3(-BODY_RADIUS, 0.05, -BODY_RADIUS)
	var maximum := feet_position + Vector3(BODY_RADIUS, BODY_HEIGHT - 0.05, BODY_RADIUS)
	for x in range(floori(minimum.x), floori(maximum.x) + 1):
		for y in range(floori(minimum.y), floori(maximum.y) + 1):
			for z in range(floori(minimum.z), floori(maximum.z) + 1):
				var block_id := str(world.call("get_block", Vector3i(x, y, z)))
				if BlockRegistryScript.is_solid(block_id):
					return false
	return true


func is_position_supported(world: Node, feet_position: Vector3) -> bool:
	if world == null or not world.has_method("get_block"):
		return true
	var support_y := floori(feet_position.y - 0.1)
	var minimum_x := floori(feet_position.x - BODY_RADIUS)
	var maximum_x := floori(feet_position.x + BODY_RADIUS)
	var minimum_z := floori(feet_position.z - BODY_RADIUS)
	var maximum_z := floori(feet_position.z + BODY_RADIUS)
	for x in range(minimum_x, maximum_x + 1):
		for z in range(minimum_z, maximum_z + 1):
			var block_id := str(world.call("get_block", Vector3i(x, support_y, z)))
			if BlockRegistryScript.is_solid(block_id):
				return true
	return false


func _resolve_ground(world: Node, candidate: Vector3) -> Vector3:
	if world != null and world.has_method("resolve_ground_position"):
		return world.call("resolve_ground_position", candidate)
	return candidate


func _is_reasonable_position(value: Vector3) -> bool:
	return _is_finite_vector(value) and value.y >= 0.0 and value.y <= 256.0


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
