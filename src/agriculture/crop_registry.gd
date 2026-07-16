class_name CropRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/crops.json"

var schema_version: int = 0
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
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open crop registry: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary or parsed.get("crops", null) is not Array:
		push_error("Invalid crop registry JSON: %s" % path)
		return false
	schema_version = maxi(1, int(parsed.get("schema_version", 1)))
	var raw_crops: Array = parsed.get("crops", [])
	for raw_value in raw_crops:
		if raw_value is not Dictionary:
			continue
		var raw_crop: Dictionary = raw_value
		var crop_id: String = str(raw_crop.get("id", "")).strip_edges()
		var seed_item: String = str(raw_crop.get("seed_item", "")).strip_edges()
		var produce_item: String = str(raw_crop.get("produce_item", "")).strip_edges()
		var stage_blocks: Array[String] = _normalize_stage_blocks(
			raw_crop.get("stage_blocks", [])
		)
		var stage_seconds: Array[float] = _normalize_stage_seconds(
			raw_crop.get("stage_seconds", [])
		)
		if (
			crop_id.is_empty()
			or seed_item.is_empty()
			or produce_item.is_empty()
			or stage_blocks.size() < 2
			or stage_seconds.size() != stage_blocks.size() - 1
			or _crops.has(crop_id)
			or _by_seed.has(seed_item)
		):
			continue
		var raw_harvest: Dictionary = raw_crop.get("harvest", {}).duplicate(true)
		var outputs: Array[Dictionary] = _normalize_harvest_outputs(
			raw_harvest,
			produce_item,
			seed_item
		)
		if outputs.is_empty():
			continue
		var normalized: Dictionary = {
			"id": crop_id,
			"name": str(raw_crop.get("name", crop_id)),
			"seed_item": seed_item,
			"produce_item": produce_item,
			"stage_blocks": stage_blocks,
			"stage_seconds": stage_seconds,
			"harvest": {
				"auto_replant": bool(raw_harvest.get("auto_replant", true)),
				"outputs": outputs,
			},
		}
		_crops[crop_id] = normalized
		_by_seed[seed_item] = crop_id
		for stage_block: String in stage_blocks:
			if _by_stage_block.has(stage_block):
				_crops.erase(crop_id)
				_by_seed.erase(seed_item)
				break
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


func get_harvest_outputs(crop_id: String) -> Array[Dictionary]:
	var crop: Dictionary = _crops.get(crop_id, {})
	var harvest: Dictionary = crop.get("harvest", {})
	var raw_outputs: Variant = harvest.get("outputs", [])
	var result: Array[Dictionary] = []
	if raw_outputs is Array:
		for raw_output in raw_outputs:
			if raw_output is Dictionary:
				result.append(raw_output.duplicate(true))
	return result


func should_auto_replant(crop_id: String) -> bool:
	var crop: Dictionary = _crops.get(crop_id, {})
	var harvest: Dictionary = crop.get("harvest", {})
	return bool(harvest.get("auto_replant", true))


func crop_count() -> int:
	return _crops.size()


func _normalize_stage_blocks(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw_value is not Array:
		return result
	for stage_value in raw_value:
		var stage_block: String = str(stage_value).strip_edges()
		if not stage_block.is_empty() and stage_block not in result:
			result.append(stage_block)
	return result


func _normalize_stage_seconds(raw_value: Variant) -> Array[float]:
	var result: Array[float] = []
	if raw_value is not Array:
		return result
	for seconds_value in raw_value:
		result.append(maxf(0.1, float(seconds_value)))
	return result


func _normalize_harvest_outputs(
	harvest: Dictionary,
	produce_item: String,
	seed_item: String
) -> Array[Dictionary]:
	var merged: Dictionary = {}
	var raw_outputs: Variant = harvest.get("outputs", [])
	if raw_outputs is Array:
		for raw_output in raw_outputs:
			if raw_output is not Dictionary:
				continue
			var item_id: String = str(raw_output.get("item_id", "")).strip_edges()
			var count: int = maxi(0, int(raw_output.get("count", 0)))
			if item_id.is_empty() or count <= 0:
				continue
			merged[item_id] = int(merged.get(item_id, 0)) + count
	if merged.is_empty():
		var produce_count: int = maxi(0, int(harvest.get("produce_count", 1)))
		var seed_count: int = maxi(0, int(harvest.get("seed_count", 1)))
		if produce_count > 0:
			merged[produce_item] = int(merged.get(produce_item, 0)) + produce_count
		if seed_count > 0:
			merged[seed_item] = int(merged.get(seed_item, 0)) + seed_count
	var result: Array[Dictionary] = []
	var item_ids: Array = merged.keys()
	item_ids.sort()
	for raw_item_id in item_ids:
		var item_id: String = str(raw_item_id)
		result.append({"item_id": item_id, "count": int(merged[item_id])})
	return result
