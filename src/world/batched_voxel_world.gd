class_name BatchedVoxelWorld
extends "res://src/world/voxel_world.gd"

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const MAX_REBUILD_BATCH_DEPTH := 8
const MAX_DIRTY_REBUILD_CHUNKS := 256
const MAX_BLOCK_MUTATIONS_PER_BATCH := 4096
const MAX_BATCH_REASON_LENGTH := 64

var _rebuild_batch_depth := 0
var _dirty_rebuild_chunks: Dictionary = {}
var _rebuild_request_count := 0
var _rebuild_execution_count := 0
var _coalesced_rebuild_count := 0
var _rebuild_flush_count := 0
var _forced_capacity_flush_count := 0
var _max_dirty_rebuild_chunks := 0
var _last_rebuild_flush_usec := 0
var _last_rebuild_flush_chunk_count := 0
var _last_rebuild_reason := ""


func clear_world() -> void:
	_reset_rebuild_runtime()
	super.clear_world()


func begin_chunk_rebuild_batch(reason: String = "bulk_mutation") -> bool:
	if _rebuild_batch_depth >= MAX_REBUILD_BATCH_DEPTH:
		return false
	_rebuild_batch_depth += 1
	if _rebuild_batch_depth == 1:
		_last_rebuild_reason = reason.strip_edges().left(MAX_BATCH_REASON_LENGTH)
	return true


func end_chunk_rebuild_batch(flush: bool = true) -> Dictionary:
	if _rebuild_batch_depth <= 0:
		return {
			"success": false,
			"reason": "no_active_batch",
			"stats": get_chunk_rebuild_stats(),
		}
	_rebuild_batch_depth -= 1
	if _rebuild_batch_depth == 0 and flush:
		return flush_chunk_rebuilds("batch_complete")
	return {
		"success": true,
		"flushed": false,
		"pending_chunks": _dirty_rebuild_chunks.size(),
		"batch_depth": _rebuild_batch_depth,
		"stats": get_chunk_rebuild_stats(),
	}


func flush_chunk_rebuilds(reason: String = "manual") -> Dictionary:
	var pending_coords: Array[Vector2i] = []
	for raw_coord: Variant in _dirty_rebuild_chunks.keys():
		pending_coords.append(Vector2i(raw_coord))
	if pending_coords.is_empty():
		return {
			"success": true,
			"flushed": false,
			"pending_chunks": 0,
			"executed_chunks": 0,
			"elapsed_usec": 0,
			"stats": get_chunk_rebuild_stats(),
		}
	pending_coords.sort_custom(
		func(first: Vector2i, second: Vector2i) -> bool:
			return first.x < second.x or (first.x == second.x and first.y < second.y)
	)
	_dirty_rebuild_chunks.clear()
	var started_at := Time.get_ticks_usec()
	var executed := 0
	for coord: Vector2i in pending_coords:
		var chunk: Variant = chunks.get(coord)
		if not is_instance_valid(chunk):
			chunk = _building_chunks.get(coord)
		if not is_instance_valid(chunk) or not chunk.has_method("rebuild_mesh"):
			continue
		chunk.call("rebuild_mesh")
		executed += 1
	_rebuild_execution_count += executed
	_rebuild_flush_count += 1
	_last_rebuild_flush_chunk_count = executed
	_last_rebuild_flush_usec = Time.get_ticks_usec() - started_at
	if not reason.strip_edges().is_empty():
		_last_rebuild_reason = reason.strip_edges().left(MAX_BATCH_REASON_LENGTH)
	return {
		"success": true,
		"flushed": true,
		"pending_chunks": pending_coords.size(),
		"executed_chunks": executed,
		"elapsed_usec": _last_rebuild_flush_usec,
		"stats": get_chunk_rebuild_stats(),
	}


func apply_block_mutations(
	changes: Array,
	reason: String = "bounded_bulk_mutation"
) -> Dictionary:
	var requested := changes.size()
	var accepted := mini(requested, MAX_BLOCK_MUTATIONS_PER_BATCH)
	var truncated := maxi(0, requested - accepted)
	if not begin_chunk_rebuild_batch(reason):
		return {
			"success": false,
			"reason": "batch_depth_exhausted",
			"requested": requested,
			"accepted": 0,
			"changed": 0,
			"unchanged": 0,
			"rejected": requested,
			"truncated": 0,
			"rebuild": get_chunk_rebuild_stats(),
		}
	var changed := 0
	var unchanged := 0
	var rejected := 0
	for index in accepted:
		var raw_change: Variant = changes[index]
		if raw_change is not Dictionary:
			rejected += 1
			continue
		var change: Dictionary = raw_change
		var position := _mutation_position(change.get("position", null))
		var block_id := str(change.get("block_id", ""))
		if position == INVALID_MUTATION_POSITION or not BlockRegistryScript.has_block(block_id):
			rejected += 1
			continue
		if set_block(position, block_id):
			changed += 1
		else:
			unchanged += 1
	var flush_result := end_chunk_rebuild_batch(true)
	return {
		"success": true,
		"reason": "ok",
		"requested": requested,
		"accepted": accepted,
		"changed": changed,
		"unchanged": unchanged,
		"rejected": rejected,
		"truncated": truncated,
		"rebuild": flush_result.get("stats", get_chunk_rebuild_stats()),
	}


func get_chunk_rebuild_stats() -> Dictionary:
	return {
		"batch_depth": _rebuild_batch_depth,
		"batch_active": _rebuild_batch_depth > 0,
		"pending_chunks": _dirty_rebuild_chunks.size(),
		"request_count": _rebuild_request_count,
		"execution_count": _rebuild_execution_count,
		"coalesced_count": _coalesced_rebuild_count,
		"flush_count": _rebuild_flush_count,
		"forced_capacity_flush_count": _forced_capacity_flush_count,
		"max_dirty_chunks": _max_dirty_rebuild_chunks,
		"last_flush_usec": _last_rebuild_flush_usec,
		"last_flush_chunk_count": _last_rebuild_flush_chunk_count,
		"last_reason": _last_rebuild_reason,
		"max_batch_depth": MAX_REBUILD_BATCH_DEPTH,
		"max_dirty_chunk_budget": MAX_DIRTY_REBUILD_CHUNKS,
		"max_mutations_per_batch": MAX_BLOCK_MUTATIONS_PER_BATCH,
	}


func reset_chunk_rebuild_stats() -> void:
	_rebuild_request_count = 0
	_rebuild_execution_count = 0
	_coalesced_rebuild_count = 0
	_rebuild_flush_count = 0
	_forced_capacity_flush_count = 0
	_max_dirty_rebuild_chunks = _dirty_rebuild_chunks.size()
	_last_rebuild_flush_usec = 0
	_last_rebuild_flush_chunk_count = 0
	_last_rebuild_reason = ""


func get_streaming_stats() -> Dictionary:
	var result: Dictionary = super.get_streaming_stats()
	var rebuild := get_chunk_rebuild_stats()
	result["rebuild"] = rebuild
	result["rebuild_requests"] = int(rebuild.get("request_count", 0))
	result["rebuild_executions"] = int(rebuild.get("execution_count", 0))
	result["rebuild_coalesced"] = int(rebuild.get("coalesced_count", 0))
	result["rebuild_pending"] = int(rebuild.get("pending_chunks", 0))
	result["rebuild_last_usec"] = int(rebuild.get("last_flush_usec", 0))
	return result


func _rebuild_affected_chunks(block_position: Vector3i) -> void:
	for coord: Vector2i in _affected_chunk_coords(block_position):
		_rebuild_request_count += 1
		if _dirty_rebuild_chunks.has(coord):
			_coalesced_rebuild_count += 1
			continue
		if _dirty_rebuild_chunks.size() >= MAX_DIRTY_REBUILD_CHUNKS:
			_forced_capacity_flush_count += 1
			flush_chunk_rebuilds("dirty_chunk_capacity")
		_dirty_rebuild_chunks[coord] = true
	_max_dirty_rebuild_chunks = maxi(
		_max_dirty_rebuild_chunks,
		_dirty_rebuild_chunks.size()
	)
	if _rebuild_batch_depth == 0:
		flush_chunk_rebuilds("immediate_mutation")


func _affected_chunk_coords(block_position: Vector3i) -> Array[Vector2i]:
	var chunk_coord := block_to_chunk(block_position)
	var local := to_local_block(block_position)
	var result: Array[Vector2i] = [chunk_coord]
	if local.x == 0:
		result.append(chunk_coord + Vector2i.LEFT)
	if local.x == CHUNK_SIZE - 1:
		result.append(chunk_coord + Vector2i.RIGHT)
	if local.z == 0:
		result.append(chunk_coord + Vector2i.UP)
	if local.z == CHUNK_SIZE - 1:
		result.append(chunk_coord + Vector2i.DOWN)
	return result


func _reset_rebuild_runtime() -> void:
	_rebuild_batch_depth = 0
	_dirty_rebuild_chunks.clear()
	_rebuild_request_count = 0
	_rebuild_execution_count = 0
	_coalesced_rebuild_count = 0
	_rebuild_flush_count = 0
	_forced_capacity_flush_count = 0
	_max_dirty_rebuild_chunks = 0
	_last_rebuild_flush_usec = 0
	_last_rebuild_flush_chunk_count = 0
	_last_rebuild_reason = ""


const INVALID_MUTATION_POSITION := Vector3i(2147483647, 2147483647, 2147483647)


func _mutation_position(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return INVALID_MUTATION_POSITION
