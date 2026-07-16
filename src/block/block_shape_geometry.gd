class_name BlockShapeGeometry
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const FACE_POS_X := 0
const FACE_NEG_X := 1
const FACE_POS_Y := 2
const FACE_NEG_Y := 3
const FACE_POS_Z := 4
const FACE_NEG_Z := 5
const EPSILON := 0.0001


static func get_local_boxes(block_id: String) -> Array[AABB]:
	var shape := str(BlockRegistryScript.get_definition(block_id).get("shape", "cube"))
	match shape:
		"slab":
			return [AABB(Vector3.ZERO, Vector3(1.0, 0.5, 1.0))]
		"stairs":
			return [
				AABB(Vector3.ZERO, Vector3(1.0, 0.5, 1.0)),
				AABB(Vector3(0.0, 0.5, 0.5), Vector3(1.0, 0.5, 0.5)),
			]
		"bed":
			return [AABB(Vector3.ZERO, Vector3(1.0, 0.5625, 1.0))]
		_:
			if block_id in ["farmland", "farmland_wet"]:
				return [AABB(Vector3.ZERO, Vector3(1.0, 0.9375, 1.0))]
			return [AABB(Vector3.ZERO, Vector3.ONE)]


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
	return shape not in ["slab", "stairs", "bed", "crop"]


static func uses_partial_geometry(block_id: String) -> bool:
	return not is_full_cube(block_id) and str(
		BlockRegistryScript.get_definition(block_id).get("shape", "cube")
	) != "crop"


static func face_enabled(block_id: String, box_index: int, face_index: int) -> bool:
	var shape := str(BlockRegistryScript.get_definition(block_id).get("shape", "cube"))
	# The upper stair box sits directly on the lower box. Its bottom face would be
	# fully internal, so omit it from both the render and collision meshes.
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
