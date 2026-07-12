class_name VoxelChunk
extends StaticBody3D

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const SIZE := 16
const HEIGHT := 64

const FACE_DIRECTIONS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1)
]
const FACE_VERTICES := [
	[Vector3(1,0,0), Vector3(1,1,0), Vector3(1,1,1), Vector3(1,0,1)],
	[Vector3(0,0,1), Vector3(0,1,1), Vector3(0,1,0), Vector3(0,0,0)],
	[Vector3(0,1,1), Vector3(1,1,1), Vector3(1,1,0), Vector3(0,1,0)],
	[Vector3(0,0,0), Vector3(1,0,0), Vector3(1,0,1), Vector3(0,0,1)],
	[Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1)],
	[Vector3(1,0,0), Vector3(0,0,0), Vector3(0,1,0), Vector3(1,1,0)]
]
const UVS := [Vector2(0,1), Vector2(1,1), Vector2(1,0), Vector2(0,0)]

var chunk_coord := Vector2i.ZERO
var blocks := PackedInt32Array()
var surface_face_count := 0
var _world: Node
var _mesh_instance: MeshInstance3D
var _collision_shape: CollisionShape3D


func _ready() -> void:
	_ensure_children()


func initialize(p_chunk_coord: Vector2i, p_world: Node) -> void:
	chunk_coord = p_chunk_coord
	_world = p_world
	name = "Chunk_%d_%d" % [chunk_coord.x, chunk_coord.y]
	position = Vector3(chunk_coord.x * SIZE, 0.0, chunk_coord.y * SIZE)
	_ensure_children()
	blocks.resize(SIZE * HEIGHT * SIZE)
	var origin := Vector3i(chunk_coord.x * SIZE, 0, chunk_coord.y * SIZE)
	for y in HEIGHT:
		for z in SIZE:
			for x in SIZE:
				var global_block := origin + Vector3i(x, y, z)
				var block_id: String = _world.call("get_initial_block", global_block)
				blocks[_index(x, y, z)] = BlockRegistryScript.get_numeric_id(block_id)
	rebuild_mesh()


func get_local_block(local_position: Vector3i) -> String:
	if not contains_local(local_position):
		return BlockRegistryScript.AIR
	return BlockRegistryScript.get_block_id(blocks[_index(local_position.x, local_position.y, local_position.z)])


func set_local_block(local_position: Vector3i, block_id: String, rebuild: bool = true) -> bool:
	if not contains_local(local_position) or not BlockRegistryScript.has_block(block_id):
		return false
	var array_index := _index(local_position.x, local_position.y, local_position.z)
	var numeric_id := BlockRegistryScript.get_numeric_id(block_id)
	if blocks[array_index] == numeric_id:
		return false
	blocks[array_index] = numeric_id
	if rebuild:
		rebuild_mesh()
	return true


func contains_local(local_position: Vector3i) -> bool:
	return local_position.x >= 0 and local_position.x < SIZE and local_position.z >= 0 and local_position.z < SIZE and local_position.y >= 0 and local_position.y < HEIGHT


func rebuild_mesh() -> void:
	_ensure_children()
	var visual_tool := SurfaceTool.new()
	var collision_tool := SurfaceTool.new()
	visual_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	collision_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var visual_faces := 0
	var collision_faces := 0
	var origin := Vector3i(chunk_coord.x * SIZE, 0, chunk_coord.y * SIZE)
	for y in HEIGHT:
		for z in SIZE:
			for x in SIZE:
				var block_id := BlockRegistryScript.get_block_id(blocks[_index(x, y, z)])
				if block_id == BlockRegistryScript.AIR:
					continue
				var global_block := origin + Vector3i(x, y, z)
				var local_origin := Vector3(x, y, z)
				for face_index in FACE_DIRECTIONS.size():
					var neighbor_id := _get_neighbor_block(global_block, Vector3i(x, y, z), FACE_DIRECTIONS[face_index])
					if not _should_draw_face(block_id, neighbor_id):
						continue
					_append_face(visual_tool, local_origin, face_index, block_id)
					visual_faces += 1
					if BlockRegistryScript.is_solid(block_id):
						_append_face(collision_tool, local_origin, face_index, block_id)
						collision_faces += 1
	surface_face_count = visual_faces
	if visual_faces > 0:
		var visual_mesh := visual_tool.commit()
		visual_mesh.surface_set_material(0, _create_voxel_material())
		_mesh_instance.mesh = visual_mesh
	else:
		_mesh_instance.mesh = null
	if collision_faces > 0:
		var collision_mesh := collision_tool.commit()
		_collision_shape.shape = collision_mesh.create_trimesh_shape()
	else:
		_collision_shape.shape = null


func get_block_count() -> int:
	var count := 0
	for numeric_id in blocks:
		if numeric_id != 0:
			count += 1
	return count


func _get_neighbor_block(global_block: Vector3i, local_block: Vector3i, direction: Vector3i) -> String:
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


func _append_face(tool: SurfaceTool, local_origin: Vector3, face_index: int, block_id: String) -> void:
	var direction: Vector3 = Vector3(FACE_DIRECTIONS[face_index])
	var color := BlockRegistryScript.get_color(block_id)
	if direction.y < -0.5:
		color = color.darkened(0.32)
	elif absf(direction.y) < 0.5:
		color = color.darkened(0.14)
	var corners: Array = FACE_VERTICES[face_index]
	var order := [0, 1, 2, 0, 2, 3]
	for corner_index in order:
		tool.set_normal(direction)
		tool.set_color(color)
		tool.set_uv(UVS[corner_index])
		tool.add_vertex(local_origin + Vector3(corners[corner_index]))


func _create_voxel_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


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


func _index(x: int, y: int, z: int) -> int:
	return (y * SIZE + z) * SIZE + x

