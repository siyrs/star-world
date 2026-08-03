class_name WorldGeneratorColumnCache
extends RefCounted

# One generated voxel column is queried repeatedly for every Y cell and again while
# neighbouring chunk faces are meshed. The cache keeps only deterministic X/Z
# facts; it never stores mutable world blocks or player overrides.
const DEFAULT_CAPACITY := 8192
const MIN_CAPACITY := 256
const MAX_CAPACITY := 32768
const ORDER_COMPACTION_THRESHOLD := 2048

var enabled := true
var capacity := DEFAULT_CAPACITY

var _entries: Dictionary = {}
var _insertion_order: Array[Vector2i] = []
var _order_head := 0

var _height_hit_count := 0
var _height_miss_count := 0
var _height_store_count := 0
var _sky_strength_hit_count := 0
var _sky_strength_miss_count := 0
var _sky_strength_store_count := 0
var _bypass_count := 0
var _eviction_count := 0
var _maximum_entry_count := 0
var _clear_count := 0


func _init(p_capacity: int = DEFAULT_CAPACITY) -> void:
	capacity = clampi(p_capacity, MIN_CAPACITY, MAX_CAPACITY)


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	clear(false)


func configure_capacity(value: int) -> void:
	capacity = clampi(value, MIN_CAPACITY, MAX_CAPACITY)
	while _entries.size() > capacity:
		_evict_oldest()
	_compact_order_if_needed(true)


func get_height(column: Vector2i) -> Variant:
	if not enabled:
		_bypass_count += 1
		return null
	var raw_entry: Variant = _entries.get(column)
	if raw_entry is Dictionary and (raw_entry as Dictionary).has("height"):
		_height_hit_count += 1
		return int((raw_entry as Dictionary)["height"])
	_height_miss_count += 1
	return null


func store_height(column: Vector2i, height: int) -> void:
	if not enabled:
		return
	var entry := _entry_for_write(column)
	if not entry.has("height"):
		_height_store_count += 1
	entry["height"] = height
	_entries[column] = entry


func get_sky_strength(column: Vector2i) -> Variant:
	if not enabled:
		_bypass_count += 1
		return null
	var raw_entry: Variant = _entries.get(column)
	if raw_entry is Dictionary and (raw_entry as Dictionary).has("sky_strength"):
		_sky_strength_hit_count += 1
		return float((raw_entry as Dictionary)["sky_strength"])
	_sky_strength_miss_count += 1
	return null


func store_sky_strength(column: Vector2i, strength: float) -> void:
	if not enabled:
		return
	var entry := _entry_for_write(column)
	if not entry.has("sky_strength"):
		_sky_strength_store_count += 1
	entry["sky_strength"] = strength
	_entries[column] = entry


func clear(reset_counters: bool = false) -> void:
	_entries.clear()
	_insertion_order.clear()
	_order_head = 0
	_clear_count += 1
	if reset_counters:
		_height_hit_count = 0
		_height_miss_count = 0
		_height_store_count = 0
		_sky_strength_hit_count = 0
		_sky_strength_miss_count = 0
		_sky_strength_store_count = 0
		_bypass_count = 0
		_eviction_count = 0
		_maximum_entry_count = 0
		_clear_count = 0


func get_stats() -> Dictionary:
	return {
		"enabled": enabled,
		"capacity": capacity,
		"entry_count": _entries.size(),
		"maximum_entry_count": _maximum_entry_count,
		"active_order_count": maxi(0, _insertion_order.size() - _order_head),
		"backing_order_count": _insertion_order.size(),
		"height_hit_count": _height_hit_count,
		"height_miss_count": _height_miss_count,
		"height_store_count": _height_store_count,
		"sky_strength_hit_count": _sky_strength_hit_count,
		"sky_strength_miss_count": _sky_strength_miss_count,
		"sky_strength_store_count": _sky_strength_store_count,
		"bypass_count": _bypass_count,
		"eviction_count": _eviction_count,
		"clear_count": _clear_count,
	}


func _entry_for_write(column: Vector2i) -> Dictionary:
	var raw_entry: Variant = _entries.get(column)
	if raw_entry is Dictionary:
		return (raw_entry as Dictionary).duplicate()
	while _entries.size() >= capacity:
		_evict_oldest()
	var entry: Dictionary = {}
	_entries[column] = entry
	_insertion_order.append(column)
	_maximum_entry_count = maxi(_maximum_entry_count, _entries.size())
	return entry


func _evict_oldest() -> void:
	while _order_head < _insertion_order.size():
		var column := _insertion_order[_order_head]
		_order_head += 1
		if not _entries.has(column):
			continue
		_entries.erase(column)
		_eviction_count += 1
		_compact_order_if_needed(false)
		return
	# Defensive recovery: queue and dictionary must never diverge, but a bounded
	# clear is safer than spinning forever if future code violates that invariant.
	_entries.clear()
	_insertion_order.clear()
	_order_head = 0


func _compact_order_if_needed(force: bool) -> void:
	if _order_head <= 0:
		return
	if (
		not force
		and _order_head < ORDER_COMPACTION_THRESHOLD
		and _order_head * 2 < _insertion_order.size()
	):
		return
	var compacted: Array[Vector2i] = []
	for index in range(_order_head, _insertion_order.size()):
		var column := _insertion_order[index]
		if _entries.has(column):
			compacted.append(column)
	_insertion_order = compacted
	_order_head = 0
