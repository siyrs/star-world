class_name ItemRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/items.json"
const DEFAULT_EXTENSION_PATHS: Array[String] = [
	"res://data/ranged_combat.json",
]

var _items: Dictionary = {}
var schema_version: int = 0


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	var source_paths: Array[String] = [path]
	if path == DEFAULT_DATA_PATH:
		for extension_path: String in DEFAULT_EXTENSION_PATHS:
			source_paths.append(extension_path)
	var staged_items: Dictionary = {}
	var staged_schema_version := 0
	for source_path: String in source_paths:
		var parsed := _read_source(source_path)
		if parsed.is_empty():
			return false
		staged_schema_version = maxi(
			staged_schema_version,
			int(parsed.get("schema_version", 1))
		)
		var raw_items: Variant = parsed.get("items", [])
		if raw_items is not Array:
			push_error("Invalid item registry JSON: %s" % source_path)
			return false
		for raw_item: Variant in raw_items:
			if raw_item is not Dictionary:
				push_error("Invalid item definition in: %s" % source_path)
				return false
			var item_id := str(raw_item.get("id", "")).strip_edges()
			if item_id.is_empty() or staged_items.has(item_id):
				push_error("Duplicate or empty item id '%s' in: %s" % [item_id, source_path])
				return false
			staged_items[item_id] = raw_item.duplicate(true)
	if staged_items.is_empty():
		return false
	_items = staged_items
	schema_version = maxi(1, staged_schema_version)
	return true


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
	for item: Variant in _items.values():
		result.append(item.duplicate(true))
	return result


func item_count() -> int:
	return _items.size()


func _read_source(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Item registry is missing: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open item registry: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary or not parsed.has("items"):
		push_error("Invalid item registry JSON: %s" % path)
		return {}
	return parsed
