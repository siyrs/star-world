class_name BlockLadderPolicy
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")

const FAMILY := "ladder"
const THICKNESS := 0.125
const CONTACT_DEPTH := 0.52
const CONTACT_MARGIN := 0.06
const MAX_CONTACT_CELLS := 18
const VARIANTS: Array[String] = [
	"ladder",
	"ladder_east",
	"ladder_north",
	"ladder_west",
]


static func supports(block_id: String) -> bool:
	var definition: Dictionary = BlockRegistryScript.get_definition(block_id)
	return (
		str(definition.get("orientation_family", "")) == FAMILY
		and str(definition.get("shape", "")) == "ladder"
	)


static func rotation_quarters(block_id: String) -> int:
	return posmod(
		int(BlockRegistryScript.get_definition(block_id).get("rotation_quarters", 0)),
		4
	)


static func variant_for_quarters(quarters: int) -> String:
	return VARIANTS[posmod(quarters, 4)]


static func resolve_for_face_normal(block_id: String, face_normal: Vector3) -> String:
	if not supports(block_id):
		return block_id
	var outward := _horizontal_cardinal(face_normal)
	if outward == Vector3i.ZERO:
		return ""
	return variant_for_support_offset(-outward)


static func variant_for_support_offset(offset: Vector3i) -> String:
	match offset:
		Vector3i.BACK:
			return VARIANTS[0]
		Vector3i.RIGHT:
			return VARIANTS[1]
		Vector3i.FORWARD:
			return VARIANTS[2]
		Vector3i.LEFT:
			return VARIANTS[3]
		_:
			return ""


static func support_offset(block_id: String) -> Vector3i:
	match rotation_quarters(block_id):
		1:
			return Vector3i.RIGHT
		2:
			return Vector3i.FORWARD
		3:
			return Vector3i.LEFT
		_:
			return Vector3i.BACK


static func outward_offset(block_id: String) -> Vector3i:
	return -support_offset(block_id)


static func direction_name(block_id: String) -> String:
	match rotation_quarters(block_id):
		1:
			return "east"
		2:
			return "north"
		3:
			return "west"
		_:
			return "south"


static func local_box(block_id: String) -> AABB:
	match rotation_quarters(block_id):
		1:
			return AABB(Vector3(1.0 - THICKNESS, 0.0, 0.0), Vector3(THICKNESS, 1.0, 1.0))
		2:
			return AABB(Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, THICKNESS))
		3:
			return AABB(Vector3(0.0, 0.0, 0.0), Vector3(THICKNESS, 1.0, 1.0))
		_:
			return AABB(Vector3(0.0, 0.0, 1.0 - THICKNESS), Vector3(1.0, 1.0, THICKNESS))


static func is_valid_support(block_id: String) -> bool:
	if block_id == BlockRegistryScript.AIR:
		return false
	var definition: Dictionary = BlockRegistryScript.get_definition(block_id)
	if bool(definition.get("ladder_anchor", false)):
		return true
	return (
		bool(definition.get("solid", false))
		and str(definition.get("shape", "cube")) == "cube"
	)


static func has_support(world: Node, block_position: Vector3i, block_id: String) -> bool:
	return (
		world != null
		and is_instance_valid(world)
		and world.has_method("get_block")
		and supports(block_id)
		and is_valid_support(
			str(world.call("get_block", block_position + support_offset(block_id)))
		)
	)


static func placement_world_boxes(block_id: String, block_position: Vector3i) -> Array[AABB]:
	if not supports(block_id):
		return []
	return [AABB(Vector3(block_position) + local_box(block_id).position, local_box(block_id).size)]


static func climb_zone(block_id: String, block_position: Vector3i) -> AABB:
	var box := local_box(block_id)
	match rotation_quarters(block_id):
		1:
			box.position.x = maxf(0.0, box.position.x - CONTACT_DEPTH)
			box.size.x = 1.0 - box.position.x
		2:
			box.size.z = minf(1.0, box.end.z + CONTACT_DEPTH)
		3:
			box.size.x = minf(1.0, box.end.x + CONTACT_DEPTH)
		_:
			box.position.z = maxf(0.0, box.position.z - CONTACT_DEPTH)
			box.size.z = 1.0 - box.position.z
	return AABB(Vector3(block_position) + box.position, box.size)


static func resolve_contact(world: Node, body_bounds: AABB) -> Dictionary:
	var result := {
		"active":false,
		"scan_count":0,
		"candidate_count":0,
		"budget_exhausted":false,
	}
	if (
		world == null
		or not is_instance_valid(world)
		or not world.has_method("world_to_block")
		or not world.has_method("get_block")
		or body_bounds.size.length_squared() <= 0.0
	):
		return result
	var scan_bounds := body_bounds.grow(CONTACT_MARGIN)
	var minimum: Vector3i = world.call(
		"world_to_block", scan_bounds.position + Vector3.ONE * 0.001
	)
	var maximum: Vector3i = world.call(
		"world_to_block", scan_bounds.end - Vector3.ONE * 0.001
	)
	var best_distance := INF
	var best: Dictionary = {}
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			for z in range(minimum.z, maximum.z + 1):
				if int(result["scan_count"]) >= MAX_CONTACT_CELLS:
					result["budget_exhausted"] = true
					break
				result["scan_count"] = int(result["scan_count"]) + 1
				var position := Vector3i(x, y, z)
				var block_id := str(world.call("get_block", position))
				if not supports(block_id) or not has_support(world, position, block_id):
					continue
				result["candidate_count"] = int(result["candidate_count"]) + 1
				var zone := climb_zone(block_id, position)
				if not body_bounds.intersects(zone):
					continue
				var distance := body_bounds.get_center().distance_squared_to(zone.get_center())
				if distance >= best_distance:
					continue
				best_distance = distance
				best = {
					"active":true,
					"block_position":position,
					"block_id":block_id,
					"support_position":position + support_offset(block_id),
					"support_offset":support_offset(block_id),
					"outward_offset":outward_offset(block_id),
					"support_direction":direction_name(block_id),
					"distance_squared":distance,
				}
			if bool(result["budget_exhausted"]):
				break
		if bool(result["budget_exhausted"]):
			break
	if not best.is_empty():
		result.merge(best, true)
	return result


static func _horizontal_cardinal(value: Vector3) -> Vector3i:
	var absolute := value.abs()
	if absolute.y > maxf(absolute.x, absolute.z):
		return Vector3i.ZERO
	if absolute.x < 0.5 and absolute.z < 0.5:
		return Vector3i.ZERO
	if absolute.x >= absolute.z:
		return Vector3i(1 if value.x > 0.0 else -1, 0, 0)
	return Vector3i(0, 0, 1 if value.z > 0.0 else -1)
