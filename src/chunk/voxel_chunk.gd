class_name VoxelChunk
extends StaticBody3D

enum BuildPhase {
	IDLE,
	GENERATING,
	MESHING,
	READY,
}

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
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
const FACE_VERTICES := [
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)],
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)],
]
const FACE_VERTEX_ORDER := [0, 1, 2, 0, 2, 3]
const UVS := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]

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
	return (
		local_position.x >= 0
		and local_position.x < SIZE
		and local_position.z >= 0
		and local_position.z < SIZE
		and local_position.y >= 0
		and local_position.y < HEIGHT
	)


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
		var numeric_id := BlockRegistryScript.get_numeric_id(
			str(_world.call("get_initial_block", global_block))
		)
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
			for face_index in FACE_DIRECTIONS.size():
				var neighbor_id := _get_neighbor_block(
					global_block, local_position, FACE_DIRECTIONS[face_index]
				)
				if not _should_draw_face(block_id, neighbor_id):
					continue
				_append_face(_visual_tool, local_origin, face_index, block_id)
				_visual_faces += 1
				if BlockRegistryScript.is_solid(block_id):
					_append_face(_collision_tool, local_origin, face_index, block_id)
					_collision_faces += 1
		_build_cursor += 1


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
		_collision_shape.shape = collision_mesh.create_trimesh_shape()
	else:
		_collision_shape.shape = null
	_visual_tool = null
	_collision_tool = null
	_build_cursor = TOTAL_CELLS
	_build_phase = BuildPhase.READY


func _get_neighbor_block(
	global_block: Vector3i, local_block: Vector3i, direction: Vector3i
) -> String:
	var neighbor_local := local_block + direction
	if contains_local(neighbor_local):
		return get_local_block(neighbor_local)
	if _world != null:
		return str(_world.call("get_block", global_block + direction))
	return BlockRegistryScript.AIR


func _should_draw_face(block_id: String, neighbor_id: String) -> bool:
	if neighbor_id == BlockRegistryScript.AIR:
		return true
	if neighbor_id == block_id and BlockRegistryScript.is_transparent(block_id):
		return false
	return BlockRegistryScript.is_transparent(neighbor_id)


func _append_face(
	tool: SurfaceTool, local_origin: Vector3, face_index: int, block_id: String
) -> void:
	var direction: Vector3 = Vector3(FACE_DIRECTIONS[face_index])
	var color := BlockRegistryScript.get_color(block_id)
	if direction.y < -0.5:
		color = color.darkened(0.32)
	elif absf(direction.y) < 0.5:
		color = color.darkened(0.14)
	var corners: Array = FACE_VERTICES[face_index]
	for corner_index in FACE_VERTEX_ORDER:
		tool.set_normal(direction)
		tool.set_color(color)
		tool.set_uv(UVS[corner_index])
		tool.add_vertex(local_origin + Vector3(corners[corner_index]))


static func _get_shared_voxel_material() -> StandardMaterial3D:
	if _shared_voxel_material == null:
		_shared_voxel_material = StandardMaterial3D.new()
		_shared_voxel_material.vertex_color_use_as_albedo = true
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
	return Vector3i(x, y, z)


func _index(x: int, y: int, z: int) -> int:
	return (y * SIZE + z) * SIZE + x
