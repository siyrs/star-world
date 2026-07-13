class_name FurnaceFuelRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/fuels.json"

var _fuels: Dictionary = {}


func _init(path: String = DEFAULT_DATA_PATH) -> void:
	load_from_file(path)


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_fuels.clear()
	if not FileAccess.file_exists(path):
		push_error("Fuel registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary or parsed.get("fuels", []) is not Array:
		push_error("Invalid fuel registry: %s" % path)
		return false
	for raw_fuel in parsed.get("fuels", []):
		if raw_fuel is not Dictionary:
			continue
		var item_id := str(raw_fuel.get("id", ""))
		var burn_seconds := float(raw_fuel.get("burn_seconds", 0.0))
		if item_id.is_empty() or burn_seconds <= 0.0:
			continue
		_fuels[item_id] = {
			"id": item_id,
			"name": str(raw_fuel.get("name", item_id)),
			"burn_seconds": burn_seconds,
		}
	return not _fuels.is_empty()


func fuel_count() -> int:
	return _fuels.size()


func is_fuel(item_id: String) -> bool:
	return _fuels.has(item_id)


func get_fuel(item_id: String) -> Dictionary:
	return _fuels.get(item_id, {}).duplicate(true)


func get_burn_seconds(item_id: String) -> float:
	return maxf(0.0, float(_fuels.get(item_id, {}).get("burn_seconds", 0.0)))


func get_all_fuels() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for fuel in _fuels.values():
		result.append(fuel.duplicate(true))
	return result
