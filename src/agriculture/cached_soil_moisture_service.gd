class_name CachedSoilMoistureService
extends "res://src/agriculture/soil_moisture_service.gd"

const MAX_REFRESH_SAMPLE_CACHE_CELLS := 65536
const MAX_REFRESH_REASON_LENGTH := 64

var _sample_cache: Dictionary = {}
var _sample_cache_active := false
var _window_sample_reads := 0
var _window_cache_hits := 0
var _window_capacity_exhausted := false
var _refresh_batch_count := 0
var _refresh_record_count := 0
var _sample_read_count := 0
var _cache_hit_count := 0
var _cache_capacity_exhaustion_count := 0
var _max_cache_cells := 0
var _last_refresh: Dictionary = {}


func attach_world_without_refresh(p_world: Node) -> void:
	world = p_world
	_refresh_accumulator = policy.refresh_interval_seconds
	_rebuild_refresh_keys()


func refresh_all() -> void:
	if world == null:
		return
	var batch_started := _begin_world_batch("soil_refresh_all")
	_begin_sample_window()
	var record_count := _soils.size()
	super.refresh_all()
	_finish_sample_window("all", record_count)
	_end_world_batch(batch_started)


func refresh_budgeted(max_records: int) -> void:
	if world == null or _refresh_keys.is_empty():
		return
	var record_count := mini(maxi(1, max_records), _refresh_keys.size())
	var batch_started := _begin_world_batch("soil_refresh_budgeted")
	_begin_sample_window()
	super.refresh_budgeted(max_records)
	_finish_sample_window("budgeted", record_count)
	_end_world_batch(batch_started)


func clear() -> void:
	super.clear()
	_reset_cache_runtime()


func get_runtime_snapshot() -> Dictionary:
	return {
		"refresh_batch_count": _refresh_batch_count,
		"refresh_record_count": _refresh_record_count,
		"sample_read_count": _sample_read_count,
		"cache_hit_count": _cache_hit_count,
		"cache_capacity_exhaustion_count": _cache_capacity_exhaustion_count,
		"max_cache_cells": _max_cache_cells,
		"cache_cell_budget": MAX_REFRESH_SAMPLE_CACHE_CELLS,
		"last_refresh": _last_refresh.duplicate(true),
	}


func _has_nearby_water(position: Vector3i) -> bool:
	if not _sample_cache_active:
		return super._has_nearby_water(position)
	if world == null:
		return false
	for y_offset in range(-policy.vertical_radius, policy.vertical_radius + 1):
		for x_offset in range(-policy.horizontal_radius, policy.horizontal_radius + 1):
			for z_offset in range(-policy.horizontal_radius, policy.horizontal_radius + 1):
				if x_offset == 0 and y_offset == 0 and z_offset == 0:
					continue
				var candidate := position + Vector3i(x_offset, y_offset, z_offset)
				var is_water := false
				if _sample_cache.has(candidate):
					_window_cache_hits += 1
					is_water = bool(_sample_cache[candidate])
				else:
					_window_sample_reads += 1
					is_water = policy.is_water_block(str(world.call("get_block", candidate)))
					if _sample_cache.size() < MAX_REFRESH_SAMPLE_CACHE_CELLS:
						_sample_cache[candidate] = is_water
					else:
						_window_capacity_exhausted = true
				if is_water:
					return true
	return false


func _begin_sample_window() -> void:
	_sample_cache.clear()
	_sample_cache_active = true
	_window_sample_reads = 0
	_window_cache_hits = 0
	_window_capacity_exhausted = false


func _finish_sample_window(reason: String, record_count: int) -> void:
	_sample_cache_active = false
	_refresh_batch_count += 1
	_refresh_record_count += maxi(0, record_count)
	_sample_read_count += _window_sample_reads
	_cache_hit_count += _window_cache_hits
	if _window_capacity_exhausted:
		_cache_capacity_exhaustion_count += 1
	_max_cache_cells = maxi(_max_cache_cells, _sample_cache.size())
	_last_refresh = {
		"reason": reason.left(MAX_REFRESH_REASON_LENGTH),
		"record_count": maxi(0, record_count),
		"sample_reads": _window_sample_reads,
		"cache_hits": _window_cache_hits,
		"cache_cells": _sample_cache.size(),
		"capacity_exhausted": _window_capacity_exhausted,
	}
	_sample_cache.clear()


func _begin_world_batch(reason: String) -> bool:
	return (
		world != null
		and world.has_method("begin_chunk_rebuild_batch")
		and world.has_method("end_chunk_rebuild_batch")
		and bool(world.call("begin_chunk_rebuild_batch", reason.left(MAX_REFRESH_REASON_LENGTH)))
	)


func _end_world_batch(started: bool) -> void:
	if started and world != null and world.has_method("end_chunk_rebuild_batch"):
		world.call("end_chunk_rebuild_batch", true)


func _reset_cache_runtime() -> void:
	_sample_cache.clear()
	_sample_cache_active = false
	_window_sample_reads = 0
	_window_cache_hits = 0
	_window_capacity_exhausted = false
	_refresh_batch_count = 0
	_refresh_record_count = 0
	_sample_read_count = 0
	_cache_hit_count = 0
	_cache_capacity_exhaustion_count = 0
	_max_cache_cells = 0
	_last_refresh.clear()
