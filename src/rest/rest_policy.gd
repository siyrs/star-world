class_name RestPolicy
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/rest.json"

var schema_version: int = 0
var bed_blocks: Array[String] = []
var sleep_start_hour: float = 19.0
var sleep_end_hour: float = 6.0
var wake_hour: float = 6.5
var spawn_offsets: Array[Vector3i] = []
var required_clearance_blocks: int = 2


func _init() -> void:
	load_from_file()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_reset_defaults()
	if not FileAccess.file_exists(path):
		push_error("Rest policy is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open rest policy: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("Invalid rest policy JSON: %s" % path)
		return false
	var data: Dictionary = parsed
	schema_version = maxi(1, int(data.get("schema_version", 1)))
	var raw_bed_blocks: Variant = data.get("bed_blocks", [])
	if raw_bed_blocks is Array:
		bed_blocks.clear()
		for raw_block: Variant in raw_bed_blocks:
			var block_id := str(raw_block).strip_edges()
			if not block_id.is_empty() and block_id not in bed_blocks:
				bed_blocks.append(block_id)
	var raw_window: Variant = data.get("sleep_window", {})
	if raw_window is Dictionary:
		var window: Dictionary = raw_window
		sleep_start_hour = fposmod(float(window.get("start_hour", sleep_start_hour)), 24.0)
		sleep_end_hour = fposmod(float(window.get("end_hour", sleep_end_hour)), 24.0)
		wake_hour = fposmod(float(window.get("wake_hour", wake_hour)), 24.0)
	var raw_offsets: Variant = data.get("spawn_offsets", [])
	if raw_offsets is Array:
		spawn_offsets.clear()
		for raw_offset: Variant in raw_offsets:
			var offset := _vector3i_from_value(raw_offset)
			if offset != Vector3i.ZERO or raw_offset == [0, 0, 0]:
				if offset not in spawn_offsets:
					spawn_offsets.append(offset)
	required_clearance_blocks = clampi(
		int(data.get("required_clearance_blocks", required_clearance_blocks)), 2, 4
	)
	if bed_blocks.is_empty() or spawn_offsets.is_empty():
		push_error("Rest policy has no usable beds or spawn offsets: %s" % path)
		_reset_defaults()
		return false
	return true


func is_bed_block(block_id: String) -> bool:
	return block_id in bed_blocks


func is_sleep_time(hour: float) -> bool:
	var normalized := fposmod(hour, 24.0)
	if is_equal_approx(sleep_start_hour, sleep_end_hour):
		return true
	if sleep_start_hour > sleep_end_hour:
		return normalized >= sleep_start_hour or normalized < sleep_end_hour
	return normalized >= sleep_start_hour and normalized < sleep_end_hour


func get_spawn_offsets() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	result.assign(spawn_offsets)
	return result


func _reset_defaults() -> void:
	schema_version = 1
	bed_blocks = ["oak_bed"]
	sleep_start_hour = 19.0
	sleep_end_hour = 6.0
	wake_hour = 6.5
	spawn_offsets = [
		Vector3i(1, 0, 0),
		Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1),
		Vector3i(0, 0, -1),
		Vector3i(1, 0, 1),
		Vector3i(1, 0, -1),
		Vector3i(-1, 0, 1),
		Vector3i(-1, 0, -1),
		Vector3i(0, 1, 0),
	]
	required_clearance_blocks = 2


func _vector3i_from_value(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() >= 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO
