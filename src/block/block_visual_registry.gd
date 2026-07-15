class_name BlockVisualRegistry
extends RefCounted

const DATA_PATH := "res://data/block_visuals.json"
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const FACE_TOP := 2
const FACE_BOTTOM := 3

var schema_version := 0
var tile_size := 16
var atlas_columns := 8
var _tiles: Dictionary = {}
var _blocks: Dictionary = {}
var _tile_order: Array[String] = []
var _tile_indices: Dictionary = {}


func ensure_loaded() -> bool:
	if not _tiles.is_empty() and not _blocks.is_empty():
		return true
	return load_from_file()


func load_from_file(path: String = DATA_PATH) -> bool:
	_clear()
	if not FileAccess.file_exists(path):
		push_error("Block visual data is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Block visual data could not be opened: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("Block visual data must be a JSON object: %s" % path)
		return false
	return _load_dictionary(parsed)


func get_tile_size() -> int:
	ensure_loaded()
	return tile_size


func get_atlas_columns() -> int:
	ensure_loaded()
	return atlas_columns


func get_atlas_rows() -> int:
	ensure_loaded()
	return maxi(1, ceili(float(_tile_order.size()) / float(maxi(1, atlas_columns))))


func get_atlas_pixel_size() -> Vector2i:
	return Vector2i(get_atlas_columns() * get_tile_size(), get_atlas_rows() * get_tile_size())


func get_tile_count() -> int:
	ensure_loaded()
	return _tile_order.size()


func get_tile_ids() -> Array[String]:
	ensure_loaded()
	return _tile_order.duplicate()


func get_tile_index(tile_id: String) -> int:
	ensure_loaded()
	return int(_tile_indices.get(tile_id, _tile_indices.get("air", 0)))


func get_tile_style(tile_id: String) -> Dictionary:
	ensure_loaded()
	var value: Variant = _tiles.get(tile_id, _tiles.get("air", {}))
	return value.duplicate(true) if value is Dictionary else {}


func get_block_profile(block_id: String) -> Dictionary:
	ensure_loaded()
	var value: Variant = _blocks.get(block_id, _blocks.get(BlockRegistryScript.AIR, {}))
	return value.duplicate(true) if value is Dictionary else {}


func get_tile_id(block_id: String, face_index: int) -> String:
	var profile := get_block_profile(block_id)
	var face_key := "side"
	if face_index == FACE_TOP:
		face_key = "top"
	elif face_index == FACE_BOTTOM:
		face_key = "bottom"
	var tile_id := str(
		profile.get(
			face_key,
			profile.get("all", profile.get("side", profile.get("top", "air")))
		)
	)
	return tile_id if _tiles.has(tile_id) else "air"


func get_validation_errors() -> Array[String]:
	ensure_loaded()
	return _validate_loaded_data()


func _load_dictionary(data: Dictionary) -> bool:
	schema_version = maxi(0, int(data.get("schema_version", 0)))
	tile_size = clampi(int(data.get("tile_size", 16)), 8, 32)
	atlas_columns = clampi(int(data.get("atlas_columns", 8)), 1, 32)
	var raw_tiles: Variant = data.get("tiles", {})
	var raw_order: Variant = data.get("tile_order", [])
	var raw_blocks: Variant = data.get("blocks", {})
	if raw_tiles is not Dictionary or raw_order is not Array or raw_blocks is not Dictionary:
		return false
	for raw_tile_id: Variant in raw_order:
		var tile_id := str(raw_tile_id).strip_edges()
		if tile_id.is_empty() or _tile_indices.has(tile_id):
			continue
		var raw_style: Variant = raw_tiles.get(tile_id, {})
		if raw_style is not Dictionary:
			continue
		_tile_indices[tile_id] = _tile_order.size()
		_tile_order.append(tile_id)
		_tiles[tile_id] = _normalize_style(raw_style)
	for raw_block_id: Variant in raw_blocks:
		var block_id := str(raw_block_id).strip_edges()
		var raw_profile: Variant = raw_blocks[raw_block_id]
		if block_id.is_empty() or raw_profile is not Dictionary:
			continue
		var profile: Dictionary = {}
		for raw_key: Variant in raw_profile:
			var key := str(raw_key)
			if key in ["all", "top", "side", "bottom"]:
				profile[key] = str(raw_profile[raw_key]).strip_edges()
		_blocks[block_id] = profile
	var errors := _validate_loaded_data()
	for error_text: String in errors:
		push_error("Block visual registry: %s" % error_text)
	return errors.is_empty()


func _normalize_style(raw_style: Dictionary) -> Dictionary:
	var style := raw_style.duplicate(true)
	style["pattern"] = str(style.get("pattern", "noise")).strip_edges()
	var palette: Array[String] = []
	var raw_palette: Variant = style.get("palette", [])
	if raw_palette is Array:
		for raw_color: Variant in raw_palette:
			palette.append(str(raw_color))
	style["palette"] = palette
	return style


func _validate_loaded_data() -> Array[String]:
	var errors: Array[String] = []
	if schema_version != 1:
		errors.append("unsupported schema_version %d" % schema_version)
	if tile_size != 16:
		errors.append("tile_size must remain 16 for the pixel-art contract")
	if _tile_order.is_empty():
		errors.append("tile_order is empty")
	if not _tiles.has("air"):
		errors.append("air tile is missing")
	for tile_id: String in _tile_order:
		var style: Dictionary = _tiles.get(tile_id, {})
		if str(style.get("pattern", "")).is_empty():
			errors.append("tile %s has no pattern" % tile_id)
		var palette: Variant = style.get("palette", [])
		if palette is not Array or palette.is_empty():
			errors.append("tile %s has no palette" % tile_id)
	for block_id: String in BlockRegistryScript.BLOCK_IDS:
		if not _blocks.has(block_id):
			errors.append("block %s has no visual profile" % block_id)
			continue
		var profile: Dictionary = _blocks.get(block_id, {})
		if profile.is_empty():
			errors.append("block %s has an empty visual profile" % block_id)
			continue
		for face_index in 6:
			var tile_id := get_tile_id(block_id, face_index)
			if not _tiles.has(tile_id):
				errors.append("block %s references missing tile %s" % [block_id, tile_id])
	return errors


func _clear() -> void:
	schema_version = 0
	tile_size = 16
	atlas_columns = 8
	_tiles.clear()
	_blocks.clear()
	_tile_order.clear()
	_tile_indices.clear()
