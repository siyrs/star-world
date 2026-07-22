class_name CachedBatchedVoxelWorld
extends "res://src/world/batched_voxel_world.gd"

const CachedChunkScript = preload("res://src/chunk/cached_voxel_chunk.gd")
const SnapshotCacheScript = preload("res://src/world/recent_chunk_snapshot_cache.gd")
const CacheBlockRegistryScript = preload("res://src/block/block_registry.gd")

var _recent_chunk_cache = SnapshotCacheScript.new()


func clear_world() -> void:
	_recent_chunk_cache.clear(true)
	super.clear_world()


func set_block(block_position: Vector3i, block_id: String) -> bool:
	var changed := super.set_block(block_position, block_id)
	if not changed:
		return false
	var chunk_coord := block_to_chunk(block_position)
	if chunks.has(chunk_coord) or _building_chunks.has(chunk_coord):
		return true
	var local_position := to_local_block(block_position)
	var cell_index := CachedChunkScript.local_cell_index(local_position)
	var numeric_id := CacheBlockRegistryScript.get_numeric_id(block_id)
	_recent_chunk_cache.patch(chunk_coord, cell_index, numeric_id)
	return true


func get_recent_chunk_cache_stats() -> Dictionary:
	return _recent_chunk_cache.get_stats()


func clear_recent_chunk_cache(reset_counters: bool = false) -> void:
	_recent_chunk_cache.clear(reset_counters)


func get_streaming_stats() -> Dictionary:
	var result: Dictionary = super.get_streaming_stats()
	result["recent_chunk_cache"] = get_recent_chunk_cache_stats()
	return result


func _begin_next_chunk_build() -> bool:
	while true:
		var raw_coord = _streaming_scheduler.pop_next()
		if raw_coord == null:
			return false
		var coord := Vector2i(raw_coord)
		if (
			chunks.has(coord)
			or _building_chunks.has(coord)
			or _chunk_distance(coord, _focus_chunk) > render_distance
		):
			continue
		var chunk := _create_cached_or_fresh_chunk(coord)
		_building_chunks[coord] = chunk
		_active_build_chunk = chunk
		_active_build_coord = coord
		return true
	return false


func _load_chunk_synchronously(chunk_coord: Vector2i) -> Node:
	if chunks.has(chunk_coord):
		return chunks[chunk_coord]
	var chunk = _building_chunks.get(chunk_coord)
	if chunk == null or not is_instance_valid(chunk):
		chunk = _create_cached_or_fresh_chunk(chunk_coord)
		_building_chunks[chunk_coord] = chunk
	while not bool(chunk.call("build_step", CHUNK_CELL_COUNT)):
		pass
	_building_chunks.erase(chunk_coord)
	if chunk == _active_build_chunk:
		_active_build_chunk = null
		_active_build_coord = INVALID_CHUNK_COORD
	chunks[chunk_coord] = chunk
	_streaming_scheduler.remove(chunk_coord)
	_sync_pending_snapshot()
	chunk_loaded.emit(chunk_coord)
	return chunk


func _unload_chunk(chunk_coord: Vector2i) -> void:
	_cache_chunk_snapshot(chunk_coord, chunks.get(chunk_coord))
	super._unload_chunk(chunk_coord)


func _cancel_build(chunk_coord: Vector2i) -> void:
	_cache_chunk_snapshot(chunk_coord, _building_chunks.get(chunk_coord))
	super._cancel_build(chunk_coord)


func _create_cached_or_fresh_chunk(chunk_coord: Vector2i) -> Node:
	var chunk = CachedChunkScript.new()
	add_child(chunk)
	var snapshot: PackedInt32Array = _recent_chunk_cache.take(chunk_coord)
	if (
		snapshot.size() == SnapshotCacheScript.CHUNK_CELL_COUNT
		and bool(chunk.call("begin_initialize_from_snapshot", chunk_coord, self, snapshot))
	):
		return chunk
	chunk.call("begin_initialize", chunk_coord, self)
	return chunk


func _cache_chunk_snapshot(chunk_coord: Vector2i, chunk: Variant) -> bool:
	if (
		not is_instance_valid(chunk)
		or not chunk.has_method("can_capture_block_snapshot")
		or not bool(chunk.call("can_capture_block_snapshot"))
		or not chunk.has_method("capture_block_snapshot")
	):
		return false
	var snapshot: PackedInt32Array = chunk.call("capture_block_snapshot")
	return _recent_chunk_cache.store(chunk_coord, snapshot)
