class_name ProspectingRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/prospecting.json"
const HARD_MAX_SAMPLES := 768
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const MapProfileCatalogScript = preload("res://src/world/map_profile_catalog.gd")
const SCAN_FIELDS: Array[String] = [
	"horizontal_radius",
	"vertical_radius",
	"horizontal_step",
	"vertical_step",
	"max_samples",
	"minimum_geology_samples",
	"cooldown_seconds",
]

var schema_version := 0
var _base_config: Dictionary = {}
var _default_tool_item_id := ""
var _tools: Dictionary = {}
var _tool_order: Array[String] = []
var _validation_errors: Array[String] = []


func _init() -> void:
	load_from_file()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_base_config.clear()
	_default_tool_item_id = ""
	_tools.clear()
	_tool_order.clear()
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
	if schema_version != 2:
		_record_error("Unsupported prospecting schema_version: %d" % schema_version)
	var base_scan := _normalize_scan_config(data, {}, "default")
	var max_records := int(data.get("max_records", 0))
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
	_base_config = base_scan.duplicate(true)
	_base_config["max_records"] = max_records
	_base_config["geology_blocks"] = geology_blocks
	_base_config["ore_blocks"] = ore_blocks
	_base_config["density_tiers"] = density_tiers
	_base_config["depth_bands"] = depth_bands
	_default_tool_item_id = str(data.get("default_tool_item_id", "")).strip_edges()
	if _default_tool_item_id.is_empty():
		_record_error("Prospecting default_tool_item_id is empty")
	_normalize_tools(data.get("tools", []), base_scan)
	if _tools.is_empty():
		_record_error("Prospecting tool list is empty")
	if not _tools.has(_default_tool_item_id):
		_record_error("Prospecting default tool is not registered: %s" % _default_tool_item_id)
	return _validation_errors.is_empty()


func validate_item_registry(item_registry: Variant) -> bool:
	if item_registry == null or not item_registry.has_method("get_item"):
		_record_error("Prospecting requires an item registry")
		return false
	for tool_item_id: String in _tool_order:
		var definition: Dictionary = item_registry.call("get_item", tool_item_id)
		if definition.is_empty():
			_record_error("Prospecting tool item is not registered: %s" % tool_item_id)
			continue
		if str(definition.get("category", "")) != "utility":
			_record_error("Prospecting tool must use the utility item category: %s" % tool_item_id)
		if int(definition.get("max_stack", 0)) != 1:
			_record_error("Prospecting tool must not stack: %s" % tool_item_id)
		if not bool(definition.get("prospecting", false)):
			_record_error("Prospecting tool item is missing prospecting=true: %s" % tool_item_id)
	return _validation_errors.is_empty()


func get_config() -> Dictionary:
	var result := _base_config.duplicate(true)
	result["default_tool_item_id"] = _default_tool_item_id
	var tools: Array[Dictionary] = []
	for tool_item_id: String in _tool_order:
		tools.append(get_tool_config(tool_item_id))
	result["tools"] = tools
	return result


func get_tool_item_id() -> String:
	# Compatibility entry point for older callers and save diagnostics.
	return _default_tool_item_id


func get_tool_ids() -> Array[String]:
	return _tool_order.duplicate()


func is_tool_item(item_id: String) -> bool:
	return _tools.has(item_id)


func get_tool_config(item_id: String) -> Dictionary:
	var raw_tool: Variant = _tools.get(item_id, {})
	if raw_tool is not Dictionary:
		return {}
	var result: Dictionary = raw_tool.duplicate(true)
	for key: Variant in _base_config.keys():
		if not result.has(key):
			result[key] = _base_config[key].duplicate(true) if _base_config[key] is Array or _base_config[key] is Dictionary else _base_config[key]
	return result


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func _normalize_tools(raw_value: Variant, base_scan: Dictionary) -> void:
	if raw_value is not Array:
		_record_error("Prospecting tools must be an array")
		return
	var seen_calibrations: Dictionary = {}
	for raw_tool: Variant in raw_value:
		if raw_tool is not Dictionary:
			_record_error("Prospecting tool entry must be an object")
			continue
		var tool: Dictionary = raw_tool
		var item_id := str(tool.get("item_id", "")).strip_edges()
		var label := str(tool.get("label", "")).strip_edges()
		var calibration_id := str(tool.get("calibration_id", "")).strip_edges()
		var summary := str(tool.get("summary", "")).strip_edges()
		var required_profile_id := str(tool.get("required_profile_id", "")).strip_edges()
		if item_id.is_empty() or label.is_empty() or calibration_id.is_empty() or summary.is_empty():
			_record_error("Prospecting tool has empty identity text")
			continue
		if _tools.has(item_id):
			_record_error("Duplicate prospecting tool item: %s" % item_id)
			continue
		if seen_calibrations.has(calibration_id):
			_record_error("Duplicate prospecting calibration: %s" % calibration_id)
			continue
		if not required_profile_id.is_empty() and not MapProfileCatalogScript.is_valid(required_profile_id):
			_record_error("Unknown prospecting calibration map: %s" % required_profile_id)
			continue
		var raw_overrides: Variant = tool.get("overrides", {})
		if raw_overrides is not Dictionary:
			_record_error("Prospecting tool overrides must be an object: %s" % item_id)
			continue
		var scan_config := _normalize_scan_config(raw_overrides, base_scan, item_id)
		var normalized := scan_config.duplicate(true)
		normalized["item_id"] = item_id
		normalized["label"] = label
		normalized["calibration_id"] = calibration_id
		normalized["summary"] = summary
		normalized["required_profile_id"] = required_profile_id
		_tools[item_id] = normalized
		_tool_order.append(item_id)
		seen_calibrations[calibration_id] = true


func _normalize_scan_config(source: Dictionary, fallback: Dictionary, context: String) -> Dictionary:
	var config: Dictionary = {}
	for field_name: String in SCAN_FIELDS:
		config[field_name] = source.get(field_name, fallback.get(field_name, 0))
	var horizontal_radius := int(config.get("horizontal_radius", 0))
	var vertical_radius := int(config.get("vertical_radius", 0))
	var horizontal_step := int(config.get("horizontal_step", 0))
	var vertical_step := int(config.get("vertical_step", 0))
	var max_samples := int(config.get("max_samples", 0))
	var minimum_geology_samples := int(config.get("minimum_geology_samples", 0))
	var cooldown_seconds := float(config.get("cooldown_seconds", 0.0))
	if horizontal_radius < 1 or horizontal_radius > 16:
		_record_error("horizontal_radius must be between 1 and 16: %s" % context)
	if vertical_radius < 1 or vertical_radius > 24:
		_record_error("vertical_radius must be between 1 and 24: %s" % context)
	if horizontal_step < 1 or horizontal_step > maxi(1, horizontal_radius):
		_record_error("horizontal_step is outside its safe range: %s" % context)
	if vertical_step < 1 or vertical_step > maxi(1, vertical_radius):
		_record_error("vertical_step is outside its safe range: %s" % context)
	if max_samples < 1 or max_samples > HARD_MAX_SAMPLES:
		_record_error("max_samples must be between 1 and %d: %s" % [HARD_MAX_SAMPLES, context])
	if minimum_geology_samples < 1 or minimum_geology_samples > maxi(1, max_samples):
		_record_error("minimum_geology_samples is outside its safe range: %s" % context)
	if cooldown_seconds < 0.0 or cooldown_seconds > 10.0:
		_record_error("cooldown_seconds must be between 0 and 10: %s" % context)
	var horizontal_samples := floori(float(2 * horizontal_radius) / maxi(1, horizontal_step)) + 1
	var vertical_samples := floori(float(2 * vertical_radius) / maxi(1, vertical_step)) + 1
	var theoretical_samples := horizontal_samples * horizontal_samples * vertical_samples
	if theoretical_samples > max_samples:
		_record_error("Theoretical prospecting samples exceed max_samples for %s: %d > %d" % [context, theoretical_samples, max_samples])
	config["horizontal_radius"] = horizontal_radius
	config["vertical_radius"] = vertical_radius
	config["horizontal_step"] = horizontal_step
	config["vertical_step"] = vertical_step
	config["max_samples"] = max_samples
	config["minimum_geology_samples"] = minimum_geology_samples
	config["cooldown_seconds"] = cooldown_seconds
	config["theoretical_samples"] = theoretical_samples
	return config


func _normalize_block_ids(raw_value: Variant, label: String) -> Array[String]:
	var result: Array[String] = []
	if raw_value is not Array:
		_record_error("Prospecting %s block list must be an array" % label)
		return result
	for raw_id: Variant in raw_value:
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
	for raw_profile: Variant in raw_value:
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
	for raw_tier: Variant in raw_value:
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
	for raw_band: Variant in raw_value:
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
