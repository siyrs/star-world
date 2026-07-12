class_name ItemRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/items.json"

var _items: Dictionary = {}
var schema_version: int = 0


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_items.clear()
	if not FileAccess.file_exists(path):
		push_error("Item registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open item registry: %s" % path)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.has("items"):
		push_error("Invalid item registry JSON: %s" % path)
		return false
	schema_version = int(parsed.get("schema_version", 1))
	for raw_item in parsed["items"]:
		if raw_item is Dictionary:
			var item_id := str(raw_item.get("id", ""))
			if not item_id.is_empty():
				_items[item_id] = raw_item.duplicate(true)
	return not _items.is_empty()


func has_item(item_id: String) -> bool:
	return _items.has(item_id)


func get_item(item_id: String) -> Dictionary:
	return _items.get(item_id, {}).duplicate(true)


func get_max_stack(item_id: String) -> int:
	return maxi(1, int(_items.get(item_id, {}).get("max_stack", 64)))


func get_display_name(item_id: String) -> String:
	return str(_items.get(item_id, {}).get("name", item_id))


func get_block_id(item_id: String) -> String:
	return str(_items.get(item_id, {}).get("block_id", ""))


func all_items() -> Array:
	var result: Array = []
	for item in _items.values():
		result.append(item.duplicate(true))
	return result


func item_count() -> int:
	return _items.size()
