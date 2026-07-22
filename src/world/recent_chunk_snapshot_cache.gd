class_name RecentChunkSnapshotCache
extends RefCounted

const MAX_SNAPSHOTS := 64
const CHUNK_CELL_COUNT := 16 * 64 * 16
const BYTES_PER_CELL := 4
const MAX_COORD_SAMPLES := 16

var _entries: Dictionary = {}
var _lru_order: Array[Vector2i] = []
var _store_count := 0
var _hit_count := 0
var _miss_count := 0
var _eviction_count := 0
var _patch_count := 0
var _rejection_count := 0
var _max_entries := 0
var _last_coord := Vector2i.ZERO
var _last_action := "none"


func store(chunk_coord: Vector2i, blocks: PackedInt32Array) -> bool:
	if blocks.size() != CHUNK_CELL_COUNT:
		_rejection_count += 1
		_last_coord = chunk_coord
		_last_action = "reject_size"
		return false
	if _entries.has(chunk_coord):
		_remove_from_order(chunk_coord)
	_entries[chunk_coord] = blocks.duplicate()
	_lru_order.append(chunk_coord)
	_store_count += 1
	_last_coord = chunk_coord
	_last_action = "store"
	while _lru_order.size() > MAX_SNAPSHOTS:
		var evicted_coord: Vector2i = _lru_order.pop_front()
		_entries.erase(evicted_coord)
		_eviction_count += 1
		_last_coord = evicted_coord
		_last_action = "evict"
	_max_entries = maxi(_max_entries, _entries.size())
	return true


func take(chunk_coord: Vector2i) -> PackedInt32Array:
	if not _entries.has(chunk_coord):
		_miss_count += 1
		_last_coord = chunk_coord
		_last_action = "miss"
		return PackedInt32Array()
	var snapshot: PackedInt32Array = _entries.get(chunk_coord, PackedInt32Array())
	_entries.erase(chunk_coord)
	_remove_from_order(chunk_coord)
	_hit_count += 1
	_last_coord = chunk_coord
	_last_action = "hit"
	return snapshot


func patch(chunk_coord: Vector2i, cell_index: int, numeric_block_id: int) -> bool:
	if not _entries.has(chunk_coord) or cell_index < 0 or cell_index >= CHUNK_CELL_COUNT:
		return false
	var snapshot: PackedInt32Array = _entries.get(chunk_coord, PackedInt32Array())
	if snapshot.size() != CHUNK_CELL_COUNT:
		_entries.erase(chunk_coord)
		_remove_from_order(chunk_coord)
		_rejection_count += 1
		_last_coord = chunk_coord
		_last_action = "reject_corrupt"
		return false
	snapshot[cell_index] = numeric_block_id
	_entries[chunk_coord] = snapshot
	_patch_count += 1
	_last_coord = chunk_coord
	_last_action = "patch"
	return true


func has(chunk_coord: Vector2i) -> bool:
	return _entries.has(chunk_coord)


func entry_count() -> int:
	return _entries.size()


func clear(reset_counters: bool = true) -> void:
	_entries.clear()
	_lru_order.clear()
	if not reset_counters:
		return
	_store_count = 0
	_hit_count = 0
	_miss_count = 0
	_eviction_count = 0
	_patch_count = 0
	_rejection_count = 0
	_max_entries = 0
	_last_coord = Vector2i.ZERO
	_last_action = "none"


func get_stats() -> Dictionary:
	var samples: Array = []
	for index in mini(_lru_order.size(), MAX_COORD_SAMPLES):
		var coord: Vector2i = _lru_order[index]
		samples.append([coord.x, coord.y])
	return {
		"entry_count": _entries.size(),
		"capacity": MAX_SNAPSHOTS,
		"cell_count_per_snapshot": CHUNK_CELL_COUNT,
		"estimated_bytes": _entries.size() * CHUNK_CELL_COUNT * BYTES_PER_CELL,
		"store_count": _store_count,
		"hit_count": _hit_count,
		"miss_count": _miss_count,
		"eviction_count": _eviction_count,
		"patch_count": _patch_count,
		"rejection_count": _rejection_count,
		"max_entries": _max_entries,
		"last_coord": [_last_coord.x, _last_coord.y],
		"last_action": _last_action,
		"cached_coord_samples": samples,
	}


func _remove_from_order(chunk_coord: Vector2i) -> void:
	var index := _lru_order.find(chunk_coord)
	if index >= 0:
		_lru_order.remove_at(index)
