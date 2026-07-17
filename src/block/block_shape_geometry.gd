class_name BlockShapeGeometry
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const OrientationPolicyScript = preload("res://src/block/block_orientation_policy.gd")
const FACE_POS_X := 0
const FACE_NEG_X := 1
const FACE_POS_Y := 2
const FACE_NEG_Y := 3
const FACE_POS_Z := 4
const FACE_NEG_Z := 5
const EPSILON := 0.0001


static func get_local_boxes(block_id: String) -> Array[AABB]:
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
			boxes = [AABB(Vector3(0.0, 0.0, 0.4375), Vector3(1.0, 1.0, 0.125))]
		_:
			if block_id in ["farmland", "farmland_wet"]:
				boxes = [AABB(Vector3.ZERO, Vector3(1.0, 0.9375, 1.0))]
			else:
				boxes = [AABB(Vector3.ZERO, Vector3.ONE)]
	if shape in ["stairs", "pane"]:
		return _rotate_boxes(boxes, OrientationPolicyScript.rotation_quarters(block_id))
	return boxes


static func get_bounds(block_id: String) -> AABB:
	var boxes: Array[AABB] = get_local_boxes(block_id)
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


static func boxes_as_snapshot(block_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for box: AABB in get_local_boxes(block_id):
		result.append(
			{
				"position":[box.position.x, box.position.y, box.position.z],
				"size":[box.size.x, box.size.y, box.size.z],
			}
		)
	return result


static func is_full_cube(block_id: String) -> bool:
	if block_id in ["farmland", "farmland_wet"]:
		return false
	var shape := str(BlockRegistryScript.get_definition(block_id).get("shape", "cube"))
	return shape not in ["slab", "stairs", "bed", "crop", "pane"]


static func uses_partial_geometry(block_id: String) -> bool:
	return not is_full_cube(block_id) and str(
		BlockRegistryScript.get_definition(block_id).get("shape", "cube")
	) != "crop"


static func face_enabled(block_id: String, box_index: int, face_index: int) -> bool:
	var shape := str(BlockRegistryScript.get_definition(block_id).get("shape", "cube"))
	# The upper stair box sits directly on the lower box. Its bottom face is internal.
	return not (shape == "stairs" and box_index == 1 and face_index == FACE_NEG_Y)


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


static func world_boxes(block_id: String, block_position: Vector3i) -> Array[AABB]:
	var result: Array[AABB] = []
	for box: AABB in get_local_boxes(block_id):
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
		result.append(
			{
				"normal":rotate_direction(Vector3(raw_face.get("normal", Vector3.UP)), quarters).normalized(),
				"corners":corners,
			}
		)
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
					var rotated := rotate_local_point(Vector3(x, y, z), quarters)
					minimum.x = minf(minimum.x, rotated.x)
					minimum.y = minf(minimum.y, rotated.y)
					minimum.z = minf(minimum.z, rotated.z)
					maximum.x = maxf(maximum.x, rotated.x)
					maximum.y = maxf(maximum.y, rotated.y)
					maximum.z = maxf(maximum.z, rotated.z)
		result.append(AABB(minimum, maximum - minimum))
	return result
