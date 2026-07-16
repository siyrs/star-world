class_name RepairRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/repair_profiles.json"

var schema_version: int = 0
var station_block: String = ""
var _profiles: Array[Dictionary] = []
var _profiles_by_item: Dictionary = {}
var _loaded: bool = false


func ensure_loaded(path: String = DEFAULT_DATA_PATH) -> bool:
	if _loaded:
		return not _profiles.is_empty()
	return load_from_file(path)


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_profiles.clear()
	_profiles_by_item.clear()
	station_block = ""
	schema_version = 0
	_loaded = true
	if not FileAccess.file_exists(path):
		push_error("Repair profile registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open repair profile registry: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("Invalid repair profile JSON: %s" % path)
		return false
	var payload: Dictionary = parsed
	schema_version = maxi(1, int(payload.get("schema_version", 1)))
	station_block = str(payload.get("station_block", "")).strip_edges()
	var raw_profiles_value: Variant = payload.get("profiles", [])
	if station_block.is_empty() or raw_profiles_value is not Array:
		push_error("Repair profile registry is missing station_block or profiles")
		return false
	var raw_profiles: Array = raw_profiles_value
	for raw_profile_value in raw_profiles:
		if raw_profile_value is not Dictionary:
			continue
		var raw_profile: Dictionary = raw_profile_value
		var profile_id: String = str(raw_profile.get("id", "")).strip_edges()
		var material_item: String = str(raw_profile.get("material_item", "")).strip_edges()
		var material_count: int = maxi(1, int(raw_profile.get("material_count", 1)))
		var restore_ratio: float = clampf(float(raw_profile.get("restore_ratio", 0.0)), 0.0, 1.0)
		var raw_items_value: Variant = raw_profile.get("items", [])
		if (
			profile_id.is_empty()
			or material_item.is_empty()
			or restore_ratio <= 0.0
			or raw_items_value is not Array
		):
			continue
		var item_ids: Array[String] = []
		for raw_item_id in raw_items_value:
			var item_id: String = str(raw_item_id).strip_edges()
			if item_id.is_empty() or item_id in item_ids:
				continue
			if _profiles_by_item.has(item_id):
				push_error("Repair item is assigned more than once: %s" % item_id)
				_profiles.clear()
				_profiles_by_item.clear()
				return false
			item_ids.append(item_id)
		if item_ids.is_empty():
			continue
		var normalized: Dictionary = {
			"id": profile_id,
			"material_item": material_item,
			"material_count": material_count,
			"restore_ratio": restore_ratio,
			"items": item_ids.duplicate(),
		}
		_profiles.append(normalized)
		for item_id in item_ids:
			_profiles_by_item[item_id] = normalized.duplicate(true)
	if _profiles.is_empty():
		push_error("Repair profile registry contains no valid profiles")
		return false
	return true


func get_station_block() -> String:
	ensure_loaded()
	return station_block


func get_profile_for_item(item_id: String) -> Dictionary:
	ensure_loaded()
	return _profiles_by_item.get(item_id, {}).duplicate(true)


func get_profiles() -> Array[Dictionary]:
	ensure_loaded()
	var result: Array[Dictionary] = []
	for profile in _profiles:
		result.append(profile.duplicate(true))
	return result


func profile_count() -> int:
	ensure_loaded()
	return _profiles.size()
