class_name BlockShapeGeometry
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const OrientationPolicyScript = preload("res://src/block/block_orientation_policy.gd")
const ConnectionPolicyScript = preload("res://src/block/block_connection_policy.gd")
const DoorPolicyScript = preload("res://src/block/block_door_policy.gd")
const FACE_POS_X := 0
const FACE_NEG_X := 1
const FACE_POS_Y := 2
const FACE_NEG_Y := 3
const FACE_POS_Z := 4
const FACE_NEG_Z := 5
const EPSILON := 0.0001

const PANE_MIN := 0.4375
const PANE_MAX := 0.5625
const PANE_THICKNESS := 0.125
const FENCE_POST_MIN := 0.375
const FENCE_POST_MAX := 0.625
const FENCE_POST_SIZE := 0.25
const FENCE_RAIL_MIN := 0.40625
const FENCE_RAIL_THICKNESS := 0.1875
const FENCE_RAIL_LEVELS: Array[float] = [0.3125, 0.6875]


static func get_local_boxes(block_id: String, connection_mask: int = -1) -> Array[AABB]:
	var shape := str(BlockRegistryScript.get_definition(block_id).get("shape", "cube"))
	var boxes: Array[AABB] = []
	match shape:
		"slab":
			boxes = [AABB(Vector3.ZERO, Vector3(1.0, 0.5, 1.0))]
		"stairs":
			boxes = [
				AABB(Vector3.ZERO, Vector3(1.0, 0.5, 1.0)),
				AABB(Vector3(0.0, 0.5, 0.5), Vector3(1.0, 0.5, 0.5)),
			]
		"bed":
			boxes = [AABB(Vector3.ZERO, Vector3(1.0, 0.5625, 1.0))]
		"pane":
			boxes = _pane_boxes(_connection_mask(block_id, connection_mask))
		"fence":
			boxes = _fence_boxes(_connection_mask(block_id, connection_mask))
		"door":
			boxes = [DoorPolicyScript.local_box(block_id)]
		_:
			if block_id in ["farmland", "farmland_wet"]:
				boxes = [AABB(Vector3.ZERO, Vector3(1.0, 0.9375, 1.0))]
			else:
				boxes = [AABB(Vector3.ZERO, Vector3.ONE)]
	if shape == "stairs":
		return _rotate_boxes(boxes, OrientationPolicyScript.rotation_quarters(block_id))
	return boxes


static func get_bounds(block_id: String, connection_mask: int = -1) -> AABB:
	var boxes := get_local_boxes(block_id, connection_mask)
	if boxes.is_empty():
		return AABB(Vector3.ZERO, Vector3.ONE)
	var minimum := boxes[0].position
	var maximum := boxes[0].end
	for index in range(1, boxes.size()):
		var box: AABB = boxes[index]
		minimum.x = minf(minimum.x, box.position.x)
		minimum.y = minf(minimum.y, box.position.y)
		minimum.z = minf(minimum.z, box.position.z)
		maximum.x = maxf(maximum.x, box.end.x)
		maximum.y = maxf(maximum.y, box.end.y)
		maximum.z = maxf(maximum.z, box.end.z)
	return AABB(minimum, maximum - minimum)


static func boxes_as_snapshot(block_id: String, connection_mask: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for box: AABB in get_local_boxes(block_id, connection_mask):
		result.append({
			"position":[box.position.x, box.position.y, box.position.z],
			"size":[box.size.x, box.size.y, box.size.z],
		})
	return result


static func is_full_cube(block_id: String) -> bool:
	if block_id in ["farmland", "farmland_wet"]:
		return false
	var shape := str(BlockRegistryScript.get_definition(block_id).get("shape", "cube"))
	return shape not in ["slab", "stairs", "bed", "crop", "pane", "fence", "door"]


static func uses_partial_geometry(block_id: String) -> bool:
	return not is_full_cube(block_id) and str(
		BlockRegistryScript.get_definition(block_id).get("shape", "cube")
	) != "crop"


static func face_enabled(
	block_id: String,
	box_index: int,
	face_index: int,
	boxes: Array[AABB] = []
) -> bool:
	var shape := str(BlockRegistryScript.get_definition(block_id).get("shape", "cube"))
	if shape == "stairs" and box_index == 1 and face_index == FACE_NEG_Y:
		return false
	if shape in ["pane", "fence"] and not boxes.is_empty():
		return not _face_fully_covered_by_neighbor_box(boxes, box_index, face_index)
	return true


static func face_is_cell_boundary(box: AABB, face_index: int) -> bool:
	match face_index:
		FACE_POS_X:
			return absf(box.end.x - 1.0) <= EPSILON
		FACE_NEG_X:
			return absf(box.position.x) <= EPSILON
		FACE_POS_Y:
			return absf(box.end.y - 1.0) <= EPSILON
		FACE_NEG_Y:
			return absf(box.position.y) <= EPSILON
		FACE_POS_Z:
			return absf(box.end.z - 1.0) <= EPSILON
		FACE_NEG_Z:
			return absf(box.position.z) <= EPSILON
		_:
			return false


static func face_vertices(box: AABB, face_index: int) -> Array[Vector3]:
	var x0 := box.position.x
	var y0 := box.position.y
	var z0 := box.position.z
	var x1 := box.end.x
	var y1 := box.end.y
	var z1 := box.end.z
	match face_index:
		FACE_POS_X:
			return [Vector3(x1,y0,z0), Vector3(x1,y1,z0), Vector3(x1,y1,z1), Vector3(x1,y0,z1)]
		FACE_NEG_X:
			return [Vector3(x0,y0,z1), Vector3(x0,y1,z1), Vector3(x0,y1,z0), Vector3(x0,y0,z0)]
		FACE_POS_Y:
			return [Vector3(x0,y1,z1), Vector3(x1,y1,z1), Vector3(x1,y1,z0), Vector3(x0,y1,z0)]
		FACE_NEG_Y:
			return [Vector3(x0,y0,z0), Vector3(x1,y0,z0), Vector3(x1,y0,z1), Vector3(x0,y0,z1)]
		FACE_POS_Z:
			return [Vector3(x0,y0,z1), Vector3(x1,y0,z1), Vector3(x1,y1,z1), Vector3(x0,y1,z1)]
		FACE_NEG_Z:
			return [Vector3(x1,y0,z0), Vector3(x0,y0,z0), Vector3(x0,y1,z0), Vector3(x1,y1,z0)]
		_:
			return []


static func world_boxes(
	block_id: String,
	block_position: Vector3i,
	connection_mask: int = -1
) -> Array[AABB]:
	var result: Array[AABB] = []
	for box: AABB in get_local_boxes(block_id, connection_mask):
		result.append(AABB(Vector3(block_position) + box.position, box.size))
	return result


static func get_stair_ramp_collision_faces(block_id: String) -> Array[Dictionary]:
	if str(BlockRegistryScript.get_definition(block_id).get("shape", "")) != "stairs":
		return []
	var a := Vector3(0,0.5,0)
	var b := Vector3(1,0.5,0)
	var c := Vector3(0,0,0)
	var d := Vector3(1,0,0)
	var e := Vector3(0,0,1)
	var f := Vector3(1,0,1)
	var g := Vector3(0,1,1)
	var h := Vector3(1,1,1)
	var base_faces: Array[Dictionary] = [
		{"normal":Vector3.DOWN, "corners":[c,d,f,e]},
		{"normal":Vector3(0,0,1), "corners":[e,f,h,g]},
		{"normal":Vector3(0,1,-0.5).normalized(), "corners":[a,g,h,b]},
		{"normal":Vector3.LEFT, "corners":[c,g,e]},
		{"normal":Vector3.RIGHT, "corners":[d,f,h]},
	]
	var quarters := OrientationPolicyScript.rotation_quarters(block_id)
	var result: Array[Dictionary] = []
	for raw_face: Dictionary in base_faces:
		var corners: Array[Vector3] = []
		for raw_corner: Variant in raw_face.get("corners", []):
			corners.append(rotate_local_point(Vector3(raw_corner), quarters))
		result.append({
			"normal":rotate_direction(
				Vector3(raw_face.get("normal", Vector3.UP)), quarters
			).normalized(),
			"corners":corners,
		})
	return result


static func rotate_local_point(point: Vector3, quarters: int) -> Vector3:
	match posmod(quarters, 4):
		1:
			return Vector3(point.z, point.y, 1.0 - point.x)
		2:
			return Vector3(1.0 - point.x, point.y, 1.0 - point.z)
		3:
			return Vector3(1.0 - point.z, point.y, point.x)
		_:
			return point


static func rotate_direction(direction: Vector3, quarters: int) -> Vector3:
	match posmod(quarters, 4):
		1:
			return Vector3(direction.z, direction.y, -direction.x)
		2:
			return Vector3(-direction.x, direction.y, -direction.z)
		3:
			return Vector3(-direction.z, direction.y, direction.x)
		_:
			return direction


static func _connection_mask(block_id: String, requested_mask: int) -> int:
	if requested_mask >= 0:
		return requested_mask & ConnectionPolicyScript.ALL
	return ConnectionPolicyScript.fallback_mask(block_id)


static func _pane_boxes(mask: int) -> Array[AABB]:
	if mask == (ConnectionPolicyScript.EAST | ConnectionPolicyScript.WEST):
		return [AABB(Vector3(0.0,0.0,PANE_MIN), Vector3(1.0,1.0,PANE_THICKNESS))]
	if mask == (ConnectionPolicyScript.NORTH | ConnectionPolicyScript.SOUTH):
		return [AABB(Vector3(PANE_MIN,0.0,0.0), Vector3(PANE_THICKNESS,1.0,1.0))]
	var result: Array[AABB] = [
		AABB(Vector3(PANE_MIN,0.0,PANE_MIN), Vector3(PANE_THICKNESS,1.0,PANE_THICKNESS))
	]
	if ConnectionPolicyScript.has_direction(mask, ConnectionPolicyScript.EAST):
		result.append(AABB(Vector3(PANE_MAX,0.0,PANE_MIN), Vector3(1.0-PANE_MAX,1.0,PANE_THICKNESS)))
	if ConnectionPolicyScript.has_direction(mask, ConnectionPolicyScript.WEST):
		result.append(AABB(Vector3(0.0,0.0,PANE_MIN), Vector3(PANE_MIN,1.0,PANE_THICKNESS)))
	if ConnectionPolicyScript.has_direction(mask, ConnectionPolicyScript.SOUTH):
		result.append(AABB(Vector3(PANE_MIN,0.0,PANE_MAX), Vector3(PANE_THICKNESS,1.0,1.0-PANE_MAX)))
	if ConnectionPolicyScript.has_direction(mask, ConnectionPolicyScript.NORTH):
		result.append(AABB(Vector3(PANE_MIN,0.0,0.0), Vector3(PANE_THICKNESS,1.0,PANE_MIN)))
	return result


static func _fence_boxes(mask: int) -> Array[AABB]:
	var result: Array[AABB] = [
		AABB(Vector3(FENCE_POST_MIN,0.0,FENCE_POST_MIN), Vector3(FENCE_POST_SIZE,1.0,FENCE_POST_SIZE))
	]
	for direction_bit in [
		ConnectionPolicyScript.EAST,
		ConnectionPolicyScript.WEST,
		ConnectionPolicyScript.SOUTH,
		ConnectionPolicyScript.NORTH,
	]:
		if ConnectionPolicyScript.has_direction(mask, int(direction_bit)):
			_append_fence_rails(result, int(direction_bit))
	return result


static func _append_fence_rails(result: Array[AABB], direction_bit: int) -> void:
	for y: float in FENCE_RAIL_LEVELS:
		match direction_bit:
			ConnectionPolicyScript.EAST:
				result.append(AABB(Vector3(FENCE_POST_MAX,y,FENCE_RAIL_MIN), Vector3(1.0-FENCE_POST_MAX,FENCE_RAIL_THICKNESS,FENCE_RAIL_THICKNESS)))
			ConnectionPolicyScript.WEST:
				result.append(AABB(Vector3(0.0,y,FENCE_RAIL_MIN), Vector3(FENCE_POST_MIN,FENCE_RAIL_THICKNESS,FENCE_RAIL_THICKNESS)))
			ConnectionPolicyScript.SOUTH:
				result.append(AABB(Vector3(FENCE_RAIL_MIN,y,FENCE_POST_MAX), Vector3(FENCE_RAIL_THICKNESS,FENCE_RAIL_THICKNESS,1.0-FENCE_POST_MAX)))
			ConnectionPolicyScript.NORTH:
				result.append(AABB(Vector3(FENCE_RAIL_MIN,y,0.0), Vector3(FENCE_RAIL_THICKNESS,FENCE_RAIL_THICKNESS,FENCE_POST_MIN)))


static func _face_fully_covered_by_neighbor_box(
	boxes: Array[AABB],
	box_index: int,
	face_index: int
) -> bool:
	if box_index < 0 or box_index >= boxes.size():
		return false
	var box: AABB = boxes[box_index]
	for other_index in boxes.size():
		if other_index == box_index:
			continue
		var other: AABB = boxes[other_index]
		match face_index:
			FACE_POS_X:
				if absf(box.end.x - other.position.x) <= EPSILON and _covers(other.position.y,other.end.y,box.position.y,box.end.y) and _covers(other.position.z,other.end.z,box.position.z,box.end.z):
					return true
			FACE_NEG_X:
				if absf(box.position.x - other.end.x) <= EPSILON and _covers(other.position.y,other.end.y,box.position.y,box.end.y) and _covers(other.position.z,other.end.z,box.position.z,box.end.z):
					return true
			FACE_POS_Y:
				if absf(box.end.y - other.position.y) <= EPSILON and _covers(other.position.x,other.end.x,box.position.x,box.end.x) and _covers(other.position.z,other.end.z,box.position.z,box.end.z):
					return true
			FACE_NEG_Y:
				if absf(box.position.y - other.end.y) <= EPSILON and _covers(other.position.x,other.end.x,box.position.x,box.end.x) and _covers(other.position.z,other.end.z,box.position.z,box.end.z):
					return true
			FACE_POS_Z:
				if absf(box.end.z - other.position.z) <= EPSILON and _covers(other.position.x,other.end.x,box.position.x,box.end.x) and _covers(other.position.y,other.end.y,box.position.y,box.end.y):
					return true
			FACE_NEG_Z:
				if absf(box.position.z - other.end.z) <= EPSILON and _covers(other.position.x,other.end.x,box.position.x,box.end.x) and _covers(other.position.y,other.end.y,box.position.y,box.end.y):
					return true
	return false


static func _covers(
	cover_min: float,
	cover_max: float,
	target_min: float,
	target_max: float
) -> bool:
	return cover_min <= target_min + EPSILON and cover_max >= target_max - EPSILON


static func _rotate_boxes(boxes: Array[AABB], quarters: int) -> Array[AABB]:
	if posmod(quarters, 4) == 0:
		return boxes
	var result: Array[AABB] = []
	for box: AABB in boxes:
		var minimum := Vector3(INF, INF, INF)
		var maximum := Vector3(-INF, -INF, -INF)
		for x in [box.position.x, box.end.x]:
			for y in [box.position.y, box.end.y]:
				for z in [box.position.z, box.end.z]:
					var rotated := rotate_local_point(Vector3(x,y,z), quarters)
					minimum.x = minf(minimum.x, rotated.x)
					minimum.y = minf(minimum.y, rotated.y)
					minimum.z = minf(minimum.z, rotated.z)
					maximum.x = maxf(maximum.x, rotated.x)
					maximum.y = maxf(maximum.y, rotated.y)
					maximum.z = maxf(maximum.z, rotated.z)
		result.append(AABB(minimum, maximum - minimum))
	return result
