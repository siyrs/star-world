class_name CropRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/crops.json"

var schema_version := 0
var _crops: Dictionary = {}
var _by_seed: Dictionary = {}
var _by_stage_block: Dictionary = {}


func _init() -> void:
	load_from_file()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_crops.clear()
	_by_seed.clear()
	_by_stage_block.clear()
	schema_version = 0
	if not FileAccess.file_exists(path):
		push_error("Crop registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open crop registry: %s" % path)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary or parsed.get("crops", null) is not Array:
		push_error("Invalid crop registry JSON: %s" % path)
		return false
	schema_version = maxi(1, int(parsed.get("schema_version", 1)))
	var raw_crops: Array = parsed.get("crops", [])
	for raw_value in raw_crops:
		if raw_value is not Dictionary:
			continue
		var raw_crop: Dictionary = raw_value
		var crop_id := str(raw_crop.get("id", "")).strip_edges()
		var seed_item := str(raw_crop.get("seed_item", "")).strip_edges()
		var produce_item := str(raw_crop.get("produce_item", "")).strip_edges()
		var stage_blocks: Array[String] = []
		var raw_stage_blocks = raw_crop.get("stage_blocks", [])
		if raw_stage_blocks is Array:
			for stage_value in raw_stage_blocks:
				var stage_block := str(stage_value).strip_edges()
				if not stage_block.is_empty():
					stage_blocks.append(stage_block)
		var stage_seconds: Array[float] = []
		var raw_stage_seconds = raw_crop.get("stage_seconds", [])
		if raw_stage_seconds is Array:
			for seconds_value in raw_stage_seconds:
				stage_seconds.append(maxf(0.1, float(seconds_value)))
		if (
			crop_id.is_empty()
			or seed_item.is_empty()
			or produce_item.is_empty()
			or stage_blocks.size() < 2
			or stage_seconds.size() != stage_blocks.size() - 1
			or _crops.has(crop_id)
		):
			continue
		var harvest: Dictionary = raw_crop.get("harvest", {}).duplicate(true)
		harvest["produce_count"] = maxi(1, int(harvest.get("produce_count", 1)))
		harvest["seed_count"] = maxi(1, int(harvest.get("seed_count", 1)))
		var normalized := {
			"id": crop_id,
			"name": str(raw_crop.get("name", crop_id)),
			"seed_item": seed_item,
			"produce_item": produce_item,
			"stage_blocks": stage_blocks,
			"stage_seconds": stage_seconds,
			"harvest": harvest,
		}
		_crops[crop_id] = normalized
		_by_seed[seed_item] = crop_id
		for stage_block in stage_blocks:
			_by_stage_block[stage_block] = crop_id
	return not _crops.is_empty()


func get_crop(crop_id: String) -> Dictionary:
	return _crops.get(crop_id, {}).duplicate(true)


func get_crop_by_seed(item_id: String) -> Dictionary:
	return get_crop(str(_by_seed.get(item_id, "")))


func get_crop_by_stage_block(block_id: String) -> Dictionary:
	return get_crop(str(_by_stage_block.get(block_id, "")))


func is_crop_block(block_id: String) -> bool:
	return _by_stage_block.has(block_id)


func get_stage_index(crop_id: String, block_id: String) -> int:
	var crop: Dictionary = _crops.get(crop_id, {})
	var stage_blocks: Array = crop.get("stage_blocks", [])
	return stage_blocks.find(block_id)


func get_stage_block(crop_id: String, stage_index: int) -> String:
	var crop: Dictionary = _crops.get(crop_id, {})
	var stage_blocks: Array = crop.get("stage_blocks", [])
	if stage_blocks.is_empty():
		return ""
	return str(stage_blocks[clampi(stage_index, 0, stage_blocks.size() - 1)])


func get_stage_duration(crop_id: String, stage_index: int) -> float:
	var crop: Dictionary = _crops.get(crop_id, {})
	var durations: Array = crop.get("stage_seconds", [])
	if durations.is_empty() or stage_index < 0 or stage_index >= durations.size():
		return 0.0
	return maxf(0.1, float(durations[stage_index]))


func crop_count() -> int:
	return _crops.size()
