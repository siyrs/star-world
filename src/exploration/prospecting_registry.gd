class_name ProspectingRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/prospecting.json"
const BlockRegistryScript = preload("res://src/block/block_registry.gd")

var schema_version := 0
var _config: Dictionary = {}
var _validation_errors: Array[String] = []


func _init() -> void:
	load_from_file()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_config.clear()
	_validation_errors.clear()
	schema_version = 0
	if not FileAccess.file_exists(path):
		_record_error("Prospecting registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_record_error("Unable to open prospecting registry: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		_record_error("Prospecting registry must be a JSON object: %s" % path)
		return false
	var data: Dictionary = parsed
	schema_version = maxi(0, int(data.get("schema_version", 0)))
	if schema_version != 1:
		_record_error("Unsupported prospecting schema_version: %d" % schema_version)
	var tool_item_id := str(data.get("tool_item_id", "")).strip_edges()
	if tool_item_id.is_empty():
		_record_error("Prospecting tool_item_id is empty")
	var horizontal_radius := int(data.get("horizontal_radius", 0))
	var vertical_radius := int(data.get("vertical_radius", 0))
	var horizontal_step := int(data.get("horizontal_step", 0))
	var vertical_step := int(data.get("vertical_step", 0))
	var max_samples := int(data.get("max_samples", 0))
	var minimum_geology_samples := int(data.get("minimum_geology_samples", 0))
	var cooldown_seconds := float(data.get("cooldown_seconds", 0.0))
	var max_records := int(data.get("max_records", 0))
	if horizontal_radius < 1 or horizontal_radius > 16:
		_record_error("horizontal_radius must be between 1 and 16")
	if vertical_radius < 1 or vertical_radius > 24:
		_record_error("vertical_radius must be between 1 and 24")
	if horizontal_step < 1 or horizontal_step > horizontal_radius:
		_record_error("horizontal_step is outside its safe range")
	if vertical_step < 1 or vertical_step > vertical_radius:
		_record_error("vertical_step is outside its safe range")
	if max_samples < 1 or max_samples > 2048:
		_record_error("max_samples must be between 1 and 2048")
	if minimum_geology_samples < 1 or minimum_geology_samples > max_samples:
		_record_error("minimum_geology_samples is outside its safe range")
	if cooldown_seconds < 0.0 or cooldown_seconds > 10.0:
		_record_error("cooldown_seconds must be between 0 and 10")
	if max_records < 1 or max_records > 256:
		_record_error("max_records must be between 1 and 256")
	var geology_blocks := _normalize_block_ids(data.get("geology_blocks", []), "geology")
	var ore_blocks := _normalize_ore_profiles(data.get("ore_blocks", []))
	var density_tiers := _normalize_density_tiers(data.get("density_tiers", []))
	var depth_bands := _normalize_depth_bands(data.get("depth_bands", []))
	if geology_blocks.is_empty():
		_record_error("Prospecting geology block list is empty")
	if ore_blocks.is_empty():
		_record_error("Prospecting ore profile list is empty")
	if density_tiers.is_empty():
		_record_error("Prospecting density tier list is empty")
	if depth_bands.is_empty():
		_record_error("Prospecting depth band list is empty")
	for ore_profile: Dictionary in ore_blocks:
		if str(ore_profile.get("block_id", "")) not in geology_blocks:
			_record_error("Ore block is not included in geology_blocks: %s" % ore_profile.get("block_id", ""))
	_config = {
		"tool_item_id": tool_item_id,
		"horizontal_radius": horizontal_radius,
		"vertical_radius": vertical_radius,
		"horizontal_step": horizontal_step,
		"vertical_step": vertical_step,
		"max_samples": max_samples,
		"minimum_geology_samples": minimum_geology_samples,
		"cooldown_seconds": cooldown_seconds,
		"max_records": max_records,
		"geology_blocks": geology_blocks,
		"ore_blocks": ore_blocks,
		"density_tiers": density_tiers,
		"depth_bands": depth_bands,
	}
	return _validation_errors.is_empty()


func validate_item_registry(item_registry: Variant) -> bool:
	if item_registry == null or not item_registry.has_method("get_item"):
		_record_error("Prospecting requires an item registry")
		return false
	var tool_item_id := get_tool_item_id()
	var definition: Dictionary = item_registry.call("get_item", tool_item_id)
	if definition.is_empty():
		_record_error("Prospecting tool item is not registered: %s" % tool_item_id)
		return false
	if str(definition.get("category", "")) != "utility":
		_record_error("Prospecting tool must use the utility item category")
	if not bool(definition.get("prospecting", false)):
		_record_error("Prospecting tool item is missing prospecting=true")
	return _validation_errors.is_empty()


func get_config() -> Dictionary:
	return _config.duplicate(true)


func get_tool_item_id() -> String:
	return str(_config.get("tool_item_id", ""))


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func _normalize_block_ids(raw_value: Variant, label: String) -> Array[String]:
	var result: Array[String] = []
	if raw_value is not Array:
		_record_error("Prospecting %s block list must be an array" % label)
		return result
	for raw_id in raw_value:
		var block_id := str(raw_id).strip_edges()
		if block_id.is_empty() or block_id in result:
			continue
		if not BlockRegistryScript.has_block(block_id):
			_record_error("Unknown prospecting %s block: %s" % [label, block_id])
			continue
		result.append(block_id)
	return result


func _normalize_ore_profiles(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	if raw_value is not Array:
		_record_error("Prospecting ore_blocks must be an array")
		return result
	for raw_profile in raw_value:
		if raw_profile is not Dictionary:
			continue
		var profile: Dictionary = raw_profile
		var block_id := str(profile.get("block_id", "")).strip_edges()
		if block_id.is_empty() or seen.has(block_id):
			continue
		if not BlockRegistryScript.has_block(block_id):
			_record_error("Unknown prospecting ore block: %s" % block_id)
			continue
		seen[block_id] = true
		result.append({
			"block_id": block_id,
			"label": str(profile.get("label", block_id)),
			"priority": int(profile.get("priority", 0)),
		})
	return result


func _normalize_density_tiers(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var previous := -0.000001
	if raw_value is not Array:
		_record_error("Prospecting density_tiers must be an array")
		return result
	for raw_tier in raw_value:
		if raw_tier is not Dictionary:
			continue
		var tier: Dictionary = raw_tier
		var minimum := float(tier.get("min_ratio", -1.0))
		if minimum < 0.0 or minimum > 1.0 or minimum <= previous:
			_record_error("Prospecting density tiers must be strictly increasing between 0 and 1")
			continue
		previous = minimum
		result.append({
			"id": str(tier.get("id", "tier_%d" % result.size())),
			"label": str(tier.get("label", "未知")),
			"min_ratio": minimum,
		})
	return result


func _normalize_depth_bands(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var previous := -1
	if raw_value is not Array:
		_record_error("Prospecting depth_bands must be an array")
		return result
	for raw_band in raw_value:
		if raw_band is not Dictionary:
			continue
		var band: Dictionary = raw_band
		var max_y := int(band.get("max_y", -1))
		if max_y <= previous:
			_record_error("Prospecting depth bands must use increasing max_y values")
			continue
		previous = max_y
		result.append({
			"id": str(band.get("id", "band_%d" % result.size())),
			"label": str(band.get("label", "未知")),
			"max_y": max_y,
		})
	return result


func _record_error(message: String) -> void:
	if message not in _validation_errors:
		_validation_errors.append(message)
	push_warning(message)
