class_name VoxelChunk
extends StaticBody3D

enum BuildPhase {
	IDLE,
	GENERATING,
	MESHING,
	READY,
}

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const TextureAtlasScript = preload("res://src/block/block_texture_atlas.gd")
const ShapeGeometryScript = preload("res://src/block/block_shape_geometry.gd")
const SIZE := 16
const HEIGHT := 64
const TOTAL_CELLS := SIZE * HEIGHT * SIZE
const FACE_DIRECTIONS := [
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(0, -1, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]
const FULL_FACE_VERTICES := [
	[Vector3(1,0,0),Vector3(1,1,0),Vector3(1,1,1),Vector3(1,0,1)],
	[Vector3(0,0,1),Vector3(0,1,1),Vector3(0,1,0),Vector3(0,0,0)],
	[Vector3(0,1,1),Vector3(1,1,1),Vector3(1,1,0),Vector3(0,1,0)],
	[Vector3(0,0,0),Vector3(1,0,0),Vector3(1,0,1),Vector3(0,0,1)],
	[Vector3(0,0,1),Vector3(1,0,1),Vector3(1,1,1),Vector3(0,1,1)],
	[Vector3(1,0,0),Vector3(0,0,0),Vector3(0,1,0),Vector3(1,1,0)],
]
const FACE_VERTEX_ORDER := [0, 1, 2, 0, 2, 3]
const CROP_PLANES := [
	[Vector3(0.14,0.02,0.14),Vector3(0.86,0.02,0.86),Vector3(0.86,1.0,0.86),Vector3(0.14,1.0,0.14)],
	[Vector3(0.86,0.02,0.14),Vector3(0.14,0.02,0.86),Vector3(0.14,1.0,0.86),Vector3(0.86,1.0,0.14)],
]
const CROP_NORMALS := [
	Vector3(0.70710678,0.0,-0.70710678),
	Vector3(0.70710678,0.0,0.70710678),
]

static var _shared_voxel_material: StandardMaterial3D

var chunk_coord := Vector2i.ZERO
var blocks := PackedInt32Array()
var surface_face_count := 0
var _world: Node
var _mesh_instance: MeshInstance3D
var _collision_shape: CollisionShape3D
var _build_phase: int = BuildPhase.IDLE
var _build_cursor := 0
var _visual_faces := 0
var _collision_faces := 0
var _visual_tool: SurfaceTool
var _collision_tool: SurfaceTool
var _pending_generation_overrides: Dictionary = {}


func _ready() -> void:
	_ensure_children()


func initialize(p_chunk_coord: Vector2i, p_world: Node) -> void:
	begin_initialize(p_chunk_coord, p_world)
	while not build_step(TOTAL_CELLS):
		pass


func begin_initialize(p_chunk_coord: Vector2i, p_world: Node) -> void:
	chunk_coord = p_chunk_coord
	_world = p_world
	name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	position = Vector3(chunk_coord.x * SIZE, 0.0, chunk_coord.y * SIZE)
	_ensure_children()
	blocks.resize(TOTAL_CELLS)
	blocks.fill(0)
	_pending_generation_overrides.clear()
	_build_cursor = 0
	_build_phase = BuildPhase.GENERATING
	surface_face_count = 0
	_mesh_instance.mesh = null
	_collision_shape.shape = null


func build_step(cell_budget: int) -> bool:
	var remaining := maxi(1, cell_budget)
	while remaining > 0:
		match _build_phase:
			BuildPhase.GENERATING:
				var generation_count := mini(remaining, TOTAL_CELLS - _build_cursor)
				_generate_cells(generation_count)
				remaining -= generation_count
				if _build_cursor >= TOTAL_CELLS:
					_begin_mesh_build()
			BuildPhase.MESHING:
				var mesh_count := mini(remaining, TOTAL_CELLS - _build_cursor)
				_mesh_cells(mesh_count)
				remaining -= mesh_count
				if _build_cursor >= TOTAL_CELLS:
					_commit_mesh_build()
					return true
			BuildPhase.READY:
				return true
			_:
				return false
	return _build_phase == BuildPhase.READY


func is_build_complete() -> bool:
	return _build_phase == BuildPhase.READY


func get_build_progress() -> float:
	match _build_phase:
		BuildPhase.GENERATING:
			return 0.5 * float(_build_cursor) / float(TOTAL_CELLS)
		BuildPhase.MESHING:
			return 0.5 + 0.5 * float(_build_cursor) / float(TOTAL_CELLS)
		BuildPhase.READY:
			return 1.0
		_:
			return 0.0


func get_local_block(local_position: Vector3i) -> String:
	if not contains_local(local_position):
		return BlockRegistryScript.AIR
	var array_index := _index(local_position.x, local_position.y, local_position.z)
	if _pending_generation_overrides.has(array_index):
		return BlockRegistryScript.get_block_id(int(_pending_generation_overrides[array_index]))
	return BlockRegistryScript.get_block_id(blocks[array_index])


func set_local_block(local_position: Vector3i, block_id: String, rebuild: bool = true) -> bool:
	if not contains_local(local_position) or not BlockRegistryScript.has_block(block_id):
		return false
	var array_index := _index(local_position.x, local_position.y, local_position.z)
	var numeric_id := BlockRegistryScript.get_numeric_id(block_id)
	if _build_phase == BuildPhase.GENERATING and array_index >= _build_cursor:
		if int(_pending_generation_overrides.get(array_index, -1)) == numeric_id:
			return false
		_pending_generation_overrides[array_index] = numeric_id
		return true
	if blocks[array_index] == numeric_id:
		return false
	blocks[array_index] = numeric_id
	if rebuild:
		rebuild_mesh()
	return true


func contains_local(local_position: Vector3i) -> bool:
	return local_position.x >= 0 and local_position.x < SIZE and local_position.z >= 0 and local_position.z < SIZE and local_position.y >= 0 and local_position.y < HEIGHT


func rebuild_mesh() -> void:
	if _build_phase == BuildPhase.GENERATING:
		while not build_step(TOTAL_CELLS):
			pass
		return
	_begin_mesh_build()
	while not build_step(TOTAL_CELLS):
		pass


func get_block_count() -> int:
	var count := 0
	for numeric_id in blocks:
		if numeric_id != 0:
			count += 1
	return count


func _generate_cells(count: int) -> void:
	var origin := Vector3i(chunk_coord.x * SIZE, 0, chunk_coord.y * SIZE)
	for _offset in count:
		var local_position := _position_from_index(_build_cursor)
		var global_block := origin + local_position
		var numeric_id := BlockRegistryScript.get_numeric_id(str(_world.call("get_initial_block", global_block)))
		if _pending_generation_overrides.has(_build_cursor):
			numeric_id = int(_pending_generation_overrides[_build_cursor])
			_pending_generation_overrides.erase(_build_cursor)
		blocks[_build_cursor] = numeric_id
		_build_cursor += 1


func _begin_mesh_build() -> void:
	_visual_tool = SurfaceTool.new()
	_collision_tool = SurfaceTool.new()
	_visual_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_collision_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_visual_faces = 0
	_collision_faces = 0
	_build_cursor = 0
	_build_phase = BuildPhase.MESHING


func _mesh_cells(count: int) -> void:
	var origin := Vector3i(chunk_coord.x * SIZE, 0, chunk_coord.y * SIZE)
	for _offset in count:
		var local_position := _position_from_index(_build_cursor)
		var block_id := BlockRegistryScript.get_block_id(blocks[_build_cursor])
		if block_id != BlockRegistryScript.AIR:
			var global_block := origin + local_position
			var local_origin := Vector3(local_position)
			var shape := str(BlockRegistryScript.get_definition(block_id).get("shape", "cube"))
			if shape == "crop":
				_append_crop(_visual_tool, local_origin, block_id)
				_visual_faces += CROP_PLANES.size()
			elif ShapeGeometryScript.uses_partial_geometry(block_id):
				_append_partial_block(global_block, local_position, local_origin, block_id, shape)
			else:
				_append_full_cube(global_block, local_position, local_origin, block_id)
		_build_cursor += 1


func _append_full_cube(global_block: Vector3i, local_position: Vector3i, local_origin: Vector3, block_id: String) -> void:
	for face_index in FACE_DIRECTIONS.size():
		var neighbor_id := _get_neighbor_block(global_block, local_position, FACE_DIRECTIONS[face_index])
		if not _should_draw_shape_face(block_id, neighbor_id):
			continue
		_append_cube_face(_visual_tool, local_origin, face_index, block_id, true)
		_visual_faces += 1
		if BlockRegistryScript.is_solid(block_id):
			_append_cube_face(_collision_tool, local_origin, face_index, block_id, false)
			_collision_faces += 1


func _append_partial_block(global_block: Vector3i, local_position: Vector3i, local_origin: Vector3, block_id: String, shape: String) -> void:
	var boxes: Array[AABB] = ShapeGeometryScript.get_local_boxes(block_id)
	for box_index in boxes.size():
		var box: AABB = boxes[box_index]
		for face_index in FACE_DIRECTIONS.size():
			if not ShapeGeometryScript.face_enabled(block_id, box_index, face_index):
				continue
			if ShapeGeometryScript.face_is_cell_boundary(box, face_index):
				var neighbor_id := _get_neighbor_block(global_block, local_position, FACE_DIRECTIONS[face_index])
				if not _should_draw_shape_face(block_id, neighbor_id):
					continue
			_append_box_face(_visual_tool, local_origin, box, face_index, block_id, true)
			_visual_faces += 1
	if not BlockRegistryScript.is_solid(block_id):
		return
	if shape == "stairs":
		_append_stair_ramp_collision(_collision_tool, local_origin)
		_collision_faces += 5
	else:
		for box_index in boxes.size():
			var box: AABB = boxes[box_index]
			for face_index in FACE_DIRECTIONS.size():
				if ShapeGeometryScript.face_enabled(block_id, box_index, face_index):
					_append_box_face(_collision_tool, local_origin, box, face_index, block_id, false)
					_collision_faces += 1


func _commit_mesh_build() -> void:
	surface_face_count = _visual_faces
	if _visual_faces > 0:
		var visual_mesh := _visual_tool.commit()
		visual_mesh.surface_set_material(0, _get_shared_voxel_material())
		_mesh_instance.mesh = visual_mesh
	else:
		_mesh_instance.mesh = null
	if _collision_faces > 0:
		var collision_mesh := _collision_tool.commit()
		var collision_shape := collision_mesh.create_trimesh_shape()
		if collision_shape is ConcavePolygonShape3D:
			collision_shape.backface_collision = true
		_collision_shape.shape = collision_shape
	else:
		_collision_shape.shape = null
	_visual_tool = null
	_collision_tool = null
	_build_cursor = TOTAL_CELLS
	_build_phase = BuildPhase.READY


func _get_neighbor_block(global_block: Vector3i, local_block: Vector3i, direction: Vector3i) -> String:
	var neighbor_local := local_block + direction
	if contains_local(neighbor_local):
		return get_local_block(neighbor_local)
	if _world != null:
		return str(_world.call("get_block", global_block + direction))
	return BlockRegistryScript.AIR


func _should_draw_shape_face(block_id: String, neighbor_id: String) -> bool:
	if neighbor_id == BlockRegistryScript.AIR:
		return true
	if neighbor_id == block_id and BlockRegistryScript.is_transparent(block_id):
		return false
	if BlockRegistryScript.is_transparent(neighbor_id):
		return true
	return not ShapeGeometryScript.is_full_cube(neighbor_id)


func _append_cube_face(tool: SurfaceTool, local_origin: Vector3, face_index: int, block_id: String, with_visual_data: bool) -> void:
	var direction := Vector3(FACE_DIRECTIONS[face_index])
	var corners: Array = FULL_FACE_VERTICES[face_index]
	var shade := _face_shade(direction)
	var uvs: Array[Vector2] = TextureAtlasScript.get_uvs(block_id, face_index)
	for corner_index in FACE_VERTEX_ORDER:
		tool.set_normal(direction)
		if with_visual_data:
			tool.set_color(shade)
			tool.set_uv(uvs[corner_index])
		tool.add_vertex(local_origin + Vector3(corners[corner_index]))


func _append_box_face(tool: SurfaceTool, local_origin: Vector3, box: AABB, face_index: int, block_id: String, with_visual_data: bool) -> void:
	var direction := Vector3(FACE_DIRECTIONS[face_index])
	var corners: Array[Vector3] = ShapeGeometryScript.face_vertices(box, face_index)
	var shade := _face_shade(direction)
	var uvs: Array[Vector2] = TextureAtlasScript.get_uvs(block_id, face_index)
	for corner_index in FACE_VERTEX_ORDER:
		tool.set_normal(direction)
		if with_visual_data:
			tool.set_color(shade)
			tool.set_uv(uvs[corner_index])
		tool.add_vertex(local_origin + corners[corner_index])


func _face_shade(direction: Vector3) -> Color:
	if direction.y < -0.5:
		return Color(0.68,0.68,0.68,1.0)
	if absf(direction.y) < 0.5:
		return Color(0.86,0.86,0.86,1.0)
	return Color.WHITE


func _append_stair_ramp_collision(tool: SurfaceTool, local_origin: Vector3) -> void:
	var a := Vector3(0,0.5,0)
	var b := Vector3(1,0.5,0)
	var c := Vector3(0,0,0)
	var d := Vector3(1,0,0)
	var e := Vector3(0,0,1)
	var f := Vector3(1,0,1)
	var g := Vector3(0,1,1)
	var h := Vector3(1,1,1)
	_append_collision_quad(tool, local_origin, [c,d,f,e], Vector3.DOWN)
	_append_collision_quad(tool, local_origin, [e,f,h,g], Vector3(0,0,1))
	_append_collision_quad(tool, local_origin, [a,g,h,b], Vector3(0,1,-0.5).normalized())
	_append_collision_triangle(tool, local_origin, [c,g,e], Vector3.LEFT)
	_append_collision_triangle(tool, local_origin, [d,f,h], Vector3.RIGHT)


func _append_collision_quad(tool: SurfaceTool, local_origin: Vector3, corners: Array, normal: Vector3) -> void:
	for corner_index in FACE_VERTEX_ORDER:
		tool.set_normal(normal)
		tool.add_vertex(local_origin + Vector3(corners[corner_index]))


func _append_collision_triangle(tool: SurfaceTool, local_origin: Vector3, corners: Array, normal: Vector3) -> void:
	for corner: Variant in corners:
		tool.set_normal(normal)
		tool.add_vertex(local_origin + Vector3(corner))


func _append_crop(tool: SurfaceTool, local_origin: Vector3, block_id: String) -> void:
	var definition := BlockRegistryScript.get_definition(block_id)
	var height := clampf(float(definition.get("crop_height", 1.0)), 0.08, 1.0)
	var uvs: Array[Vector2] = TextureAtlasScript.get_uvs(block_id, 4)
	for plane_index in CROP_PLANES.size():
		var corners: Array = CROP_PLANES[plane_index]
		var normal: Vector3 = CROP_NORMALS[plane_index]
		for corner_index in FACE_VERTEX_ORDER:
			var corner: Vector3 = corners[corner_index]
			corner.y = minf(corner.y, height)
			tool.set_normal(normal)
			tool.set_color(Color.WHITE)
			tool.set_uv(uvs[corner_index])
			tool.add_vertex(local_origin + corner)


static func reset_visual_cache_for_tests() -> void:
	_shared_voxel_material = null
	TextureAtlasScript.reset_cache_for_tests()


static func _get_shared_voxel_material() -> StandardMaterial3D:
	if _shared_voxel_material == null:
		_shared_voxel_material = StandardMaterial3D.new()
		_shared_voxel_material.vertex_color_use_as_albedo = true
		_shared_voxel_material.albedo_texture = TextureAtlasScript.get_texture()
		_shared_voxel_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_shared_voxel_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_shared_voxel_material.alpha_scissor_threshold = 0.45
		_shared_voxel_material.roughness = 0.92
		_shared_voxel_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _shared_voxel_material


func _ensure_children() -> void:
	if _mesh_instance == null:
		_mesh_instance = get_node_or_null("Mesh")
		if _mesh_instance == null:
			_mesh_instance = MeshInstance3D.new()
			_mesh_instance.name = "Mesh"
			add_child(_mesh_instance)
	if _collision_shape == null:
		_collision_shape = get_node_or_null("Collision")
		if _collision_shape == null:
			_collision_shape = CollisionShape3D.new()
			_collision_shape.name = "Collision"
			add_child(_collision_shape)


func _position_from_index(linear_index: int) -> Vector3i:
	var x := linear_index % SIZE
	var yz: int = linear_index / SIZE
	var z := yz % SIZE
	var y: int = yz / SIZE
	return Vector3i(x,y,z)


func _index(x: int, y: int, z: int) -> int:
	return (y * SIZE + z) * SIZE + x
