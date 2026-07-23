extends RefCounted

const DEFAULT_RADIUS := 10
const DEFAULT_CLEARANCE_HEIGHT := 4
const MAX_RADIUS := 12
const MAX_CLEARANCE_HEIGHT := 5
const MAX_MUTATIONS_PER_BATCH := 4096


static func build_mutations(
	origin: Vector3i,
	floor_y: int,
	radius: int = DEFAULT_RADIUS,
	clearance_height: int = DEFAULT_CLEARANCE_HEIGHT
) -> Array[Dictionary]:
	var safe_radius := clampi(radius, 1, MAX_RADIUS)
	var safe_clearance := clampi(clearance_height, 1, MAX_CLEARANCE_HEIGHT)
	var mutations: Array[Dictionary] = []
	for x_offset in range(-safe_radius, safe_radius + 1):
		for z_offset in range(-safe_radius, safe_radius + 1):
			var floor_position := Vector3i(
				origin.x + x_offset,
				floor_y,
				origin.z + z_offset
			)
			mutations.append({
				"position": floor_position,
				"block_id": "stone",
			})
			for y_offset in range(1, safe_clearance + 1):
				mutations.append({
					"position": floor_position + Vector3i(0, y_offset, 0),
					"block_id": "air",
				})
	return mutations


static func expected_mutation_count(
	radius: int = DEFAULT_RADIUS,
	clearance_height: int = DEFAULT_CLEARANCE_HEIGHT
) -> int:
	var safe_radius := clampi(radius, 1, MAX_RADIUS)
	var safe_clearance := clampi(clearance_height, 1, MAX_CLEARANCE_HEIGHT)
	var side := safe_radius * 2 + 1
	return side * side * (safe_clearance + 1)
