class_name VoxelWorld
extends Node3D

signal world_ready(profile_id: String, seed: int)
signal chunk_loaded(chunk_coord: Vector2i)
signal chunk_unloaded(chunk_coord: Vector2i)
signal block_changed(block_position: Vector3i, old_block: String, new_block: String)
signal block_broken(block_position: Vector3i, block_id: String)
signal block_placed(block_position: Vector3i, block_id: String)

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const ChunkScript = preload("res://src/chunk/voxel_chunk.gd")
const GeneratorScript = preload("res://src/world/world_generator.gd")
const CHUNK_SIZE := 16
const WORLD_HEIGHT := 64

@export_range(1, 5, 1) var render_distance := 2
@export_range(2, 7, 1) var unload_distance := 3
@export_range(1, 4, 1) var chunks_per_frame := 1

var is_started := false
var profile_id := "star_continent"
var seed_value := 734521
var world_id := "quick-world"
var generator = GeneratorScript.new()
var block_overrides: Dictionary = {}
var chunks: Dictionary = {}
var pending_chunks: Array[Vector2i] = []
var spawn_position := Vector3(0.5, 40.0, 0.5)

var _focus_node: Node3D
var _focus_position := Vector3.ZERO
var _focus_chunk := Vector2i(999999, 999999)
var _stream_update_accumulator := 0.0


func start_world(p_profile_id: String, p_seed: int, p_world_id: String, saved_state: Dictionary = {}) -> void:
	clear_world()
	profile_id = generator.normalize_profile_id(p_profile_id)
	seed_value = p_seed
	world_id = p_world_id
	generator.configure(profile_id, seed_value)
	var world_state: Dictionary = saved_state.get("world", saved_state)
	load_sparse_overrides(world_state.get("block_overrides", world_state.get("overrides", {})))
	spawn_position = generator.find_spawn_position()
	_focus_position = spawn_position
	_focus_chunk = block_to_chunk(world_to_block(spawn_position))
	is_started = true
	_load_chunk(_focus_chunk)
	_refresh_streaming(true)
	world_ready.emit(profile_id, seed_value)


func clear_world() -> void:
	is_started = false
	pending_chunks.clear()
	for chunk in chunks.values():
		if is_instance_valid(chunk):
			chunk.queue_free()
	chunks.clear()
	block_overrides.clear()
	_focus_node = null


func _process(delta: float) -> void:
	if not is_started:
		return
	if _focus_node != null and is_instance_valid(_focus_node):
		_focus_position = _focus_node.global_position
	_stream_update_accumulator += delta
	var next_focus_chunk := block_to_chunk(world_to_block(_focus_position))
	if next_focus_chunk != _focus_chunk or _stream_update_accumulator >= 0.4:
		_focus_chunk = next_focus_chunk
		_stream_update_accumulator = 0.0
		_refresh_streaming(false)
	for load_index in mini(chunks_per_frame, pending_chunks.size()):
		if pending_chunks.is_empty():
			break
		var next_coord := Vector2i(pending_chunks.pop_front())
		if _chunk_distance(next_coord, _focus_chunk) <= render_distance and not chunks.has(next_coord):
			_load_chunk(next_coord)


func set_focus(focus: Variant) -> void:
	if focus is Node3D:
		_focus_node = focus
		_focus_position = focus.global_position
	elif focus is Vector3:
		_focus_node = null
		_focus_position = focus
	_focus_chunk = block_to_chunk(world_to_block(_focus_position))
	_refresh_streaming(false)


func get_spawn_position() -> Vector3:
	return spawn_position


func get_block(block_position: Vector3i) -> String:
	if block_position.y < 0 or block_position.y >= WORLD_HEIGHT:
		return BlockRegistryScript.AIR
	var key := block_key(block_position)
	if block_overrides.has(key):
		return str(block_overrides[key])
	var chunk_coord := block_to_chunk(block_position)
	var chunk = chunks.get(chunk_coord)
	if chunk != null and is_instance_valid(chunk):
		return chunk.get_local_block(to_local_block(block_position))
	return generator.get_block(block_position)


func get_initial_block(block_position: Vector3i) -> String:
	var key := block_key(block_position)
	if block_overrides.has(key):
		return str(block_overrides[key])
	return generator.get_block(block_position)


func set_block(block_position: Vector3i, block_id: String) -> bool:
	if block_position.y <= 0 or block_position.y >= WORLD_HEIGHT or not BlockRegistryScript.has_block(block_id):
		return false
	var old_block := get_block(block_position)
	if old_block == block_id:
		return false
	var key := block_key(block_position)
	var generated_block := generator.get_block(block_position)
	if block_id == generated_block:
		block_overrides.erase(key)
	else:
		block_overrides[key] = block_id
	var chunk_coord := block_to_chunk(block_position)
	var chunk = chunks.get(chunk_coord)
	if chunk != null and is_instance_valid(chunk):
		chunk.set_local_block(to_local_block(block_position), block_id, false)
	_rebuild_affected_chunks(block_position)
	block_changed.emit(block_position, old_block, block_id)
	if block_id == BlockRegistryScript.AIR:
		block_broken.emit(block_position, old_block)
	else:
		block_placed.emit(block_position, block_id)
	return true


func remove_block(block_position: Vector3i) -> String:
	var old_block := get_block(block_position)
	if old_block == BlockRegistryScript.AIR or old_block == BlockRegistryScript.BEDROCK:
		return BlockRegistryScript.AIR
	if set_block(block_position, BlockRegistryScript.AIR):
		return old_block
	return BlockRegistryScript.AIR


func world_to_block(world_position: Vector3) -> Vector3i:
	return Vector3i(floori(world_position.x), floori(world_position.y), floori(world_position.z))


func block_to_world(block_position: Vector3i) -> Vector3:
	return Vector3(block_position) + Vector3(0.5, 0.5, 0.5)


func block_to_chunk(block_position: Vector3i) -> Vector2i:
	return Vector2i(floori(float(block_position.x) / CHUNK_SIZE), floori(float(block_position.z) / CHUNK_SIZE))


func to_local_block(block_position: Vector3i) -> Vector3i:
	return Vector3i(posmod(block_position.x, CHUNK_SIZE), block_position.y, posmod(block_position.z, CHUNK_SIZE))


func serialize_sparse_overrides() -> Dictionary:
	return block_overrides.duplicate(true)


func serialize_overrides() -> Dictionary:
	return serialize_sparse_overrides()


func load_sparse_overrides(data: Variant) -> void:
	block_overrides.clear()
	if data is not Dictionary:
		return
	for key in data:
		var block_id := str(data[key])
		if _is_valid_block_key(str(key)) and BlockRegistryScript.has_block(block_id):
			block_overrides[str(key)] = block_id


func serialize() -> Dictionary:
	var loaded: Array = []
	for coord: Vector2i in chunks.keys():
		loaded.append([coord.x, coord.y])
	return {
		"version": 1,
		"profile_id": profile_id,
		"seed": seed_value,
		"world_id": world_id,
		"block_overrides": serialize_sparse_overrides(),
		"loaded_chunks": loaded
	}


func serialize_state() -> Dictionary:
	return serialize()


func resolve_ground_position(candidate: Vector3) -> Vector3:
	var x := floori(candidate.x)
	var z := floori(candidate.z)
	for y in range(WORLD_HEIGHT - 3, 0, -1):
		var block_id := get_block(Vector3i(x, y, z))
		if not BlockRegistryScript.is_solid(block_id) or block_id == "leaves":
			continue
		if get_block(Vector3i(x, y + 1, z)) == BlockRegistryScript.AIR and get_block(Vector3i(x, y + 2, z)) == BlockRegistryScript.AIR:
			return Vector3(candidate.x, y + 1.05, candidate.z)
	return Vector3(candidate.x, maxf(candidate.y, 50.0), candidate.z)


func get_loaded_chunk_count() -> int:
	return chunks.size()


func get_loaded_chunk_coords() -> Array:
	return chunks.keys().duplicate()


func force_load_chunk(chunk_coord: Vector2i) -> Node:
	return _load_chunk(chunk_coord)


func _refresh_streaming(force: bool) -> void:
	if not is_started:
		return
	var wanted: Array[Vector2i] = []
	for offset_x in range(-render_distance, render_distance + 1):
		for offset_z in range(-render_distance, render_distance + 1):
			wanted.append(_focus_chunk + Vector2i(offset_x, offset_z))
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _distance_squared(a, _focus_chunk) < _distance_squared(b, _focus_chunk))
	for coord in wanted:
		if not chunks.has(coord) and not pending_chunks.has(coord):
			pending_chunks.append(coord)
	for coord: Vector2i in chunks.keys().duplicate():
		if _chunk_distance(coord, _focus_chunk) > unload_distance:
			_unload_chunk(coord)
	if force and chunks.has(_focus_chunk):
		pending_chunks.erase(_focus_chunk)


func _load_chunk(chunk_coord: Vector2i) -> Node:
	if chunks.has(chunk_coord):
		return chunks[chunk_coord]
	var chunk = ChunkScript.new()
	add_child(chunk)
	chunk.initialize(chunk_coord, self)
	chunks[chunk_coord] = chunk
	pending_chunks.erase(chunk_coord)
	chunk_loaded.emit(chunk_coord)
	return chunk


func _unload_chunk(chunk_coord: Vector2i) -> void:
	var chunk = chunks.get(chunk_coord)
	if chunk != null and is_instance_valid(chunk):
		chunk.queue_free()
	chunks.erase(chunk_coord)
	chunk_unloaded.emit(chunk_coord)


func _rebuild_affected_chunks(block_position: Vector3i) -> void:
	var chunk_coord := block_to_chunk(block_position)
	var local := to_local_block(block_position)
	var affected: Array[Vector2i] = [chunk_coord]
	if local.x == 0: affected.append(chunk_coord + Vector2i.LEFT)
	if local.x == CHUNK_SIZE - 1: affected.append(chunk_coord + Vector2i.RIGHT)
	if local.z == 0: affected.append(chunk_coord + Vector2i.UP)
	if local.z == CHUNK_SIZE - 1: affected.append(chunk_coord + Vector2i.DOWN)
	for coord in affected:
		var chunk = chunks.get(coord)
		if chunk != null and is_instance_valid(chunk):
			chunk.rebuild_mesh()


func block_key(block_position: Vector3i) -> String:
	return "%d,%d,%d" % [block_position.x, block_position.y, block_position.z]


func _is_valid_block_key(value: String) -> bool:
	var parts := value.split(",")
	if parts.size() != 3:
		return false
	return parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int()


func _chunk_distance(first: Vector2i, second: Vector2i) -> int:
	return maxi(absi(first.x - second.x), absi(first.y - second.y))


func _distance_squared(first: Vector2i, second: Vector2i) -> int:
	var delta := first - second
	return delta.x * delta.x + delta.y * delta.y
