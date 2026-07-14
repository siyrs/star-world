class_name FertilizerRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/fertilizers.json"

var schema_version := 0
var _profiles: Dictionary = {}


func _init() -> void:
	load_from_file()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_profiles.clear()
	schema_version = 0
	if not FileAccess.file_exists(path):
		push_error("Fertilizer registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open fertilizer registry: %s" % path)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary or parsed.get("fertilizers", null) is not Array:
		push_error("Invalid fertilizer registry JSON: %s" % path)
		return false
	schema_version = maxi(1, int(parsed.get("schema_version", 1)))
	for raw_value in parsed.get("fertilizers", []):
		if raw_value is not Dictionary:
			continue
		var raw_profile: Dictionary = raw_value
		var profile_id := str(raw_profile.get("id", "")).strip_edges()
		var item_id := str(raw_profile.get("item_id", "")).strip_edges()
		if profile_id.is_empty() or item_id.is_empty() or _profiles.has(item_id):
			continue
		var allowed_crops: Array[String] = []
		var raw_allowed = raw_profile.get("allowed_crops", [])
		if raw_allowed is Array:
			for crop_value in raw_allowed:
				var crop_id := str(crop_value).strip_edges()
				if not crop_id.is_empty() and crop_id not in allowed_crops:
					allowed_crops.append(crop_id)
		_profiles[item_id] = {
			"id": profile_id,
			"item_id": item_id,
			"name": str(raw_profile.get("name", profile_id)),
			"stage_advances": clampi(int(raw_profile.get("stage_advances", 1)), 1, 3),
			"allowed_crops": allowed_crops,
		}
	return not _profiles.is_empty()


func has_item(item_id: String) -> bool:
	return _profiles.has(item_id)


func get_profile(item_id: String) -> Dictionary:
	return _profiles.get(item_id, {}).duplicate(true)


func profile_count() -> int:
	return _profiles.size()
