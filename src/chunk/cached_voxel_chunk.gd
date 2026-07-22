class_name CachedVoxelChunk
extends "res://src/chunk/voxel_chunk.gd"

var _snapshot_hydrated := false
var _generation_cells_skipped := 0


func begin_initialize(p_chunk_coord: Vector2i, p_world: Node) -> void:
	_snapshot_hydrated = false
	_generation_cells_skipped = 0
	super.begin_initialize(p_chunk_coord, p_world)


func begin_initialize_from_snapshot(
	p_chunk_coord: Vector2i,
	p_world: Node,
	snapshot: PackedInt32Array
) -> bool:
	if snapshot.size() != TOTAL_CELLS:
		return false
	super.begin_initialize(p_chunk_coord, p_world)
	blocks = snapshot.duplicate()
	_pending_generation_overrides.clear()
	_snapshot_hydrated = true
	_generation_cells_skipped = TOTAL_CELLS
	_begin_mesh_build()
	return true


func can_capture_block_snapshot() -> bool:
	return (
		blocks.size() == TOTAL_CELLS
		and _build_phase != BuildPhase.IDLE
		and _build_phase != BuildPhase.GENERATING
	)


func capture_block_snapshot() -> PackedInt32Array:
	if not can_capture_block_snapshot():
		return PackedInt32Array()
	return blocks.duplicate()


func was_hydrated_from_snapshot() -> bool:
	return _snapshot_hydrated


func get_cache_build_stats() -> Dictionary:
	return {
		"snapshot_hydrated": _snapshot_hydrated,
		"generation_cells_skipped": _generation_cells_skipped,
		"build_complete": is_build_complete(),
		"build_progress": get_build_progress(),
	}


static func local_cell_index(local_position: Vector3i) -> int:
	if (
		local_position.x < 0
		or local_position.x >= SIZE
		or local_position.y < 0
		or local_position.y >= HEIGHT
		or local_position.z < 0
		or local_position.z >= SIZE
	):
		return -1
	return local_position.x + SIZE * (local_position.z + SIZE * local_position.y)
