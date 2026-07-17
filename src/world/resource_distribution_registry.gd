class_name ResourceDistributionRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/resource_distribution.json"
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const PolicyScript = preload("res://src/world/resource_distribution_policy.gd")

var schema_version: int = 0
var default_profile_id := "star_continent"
var _profiles: Dictionary = {}
var _validation_errors: Array[String] = []


func _init() -> void:
	if not load_from_file():
		_install_builtin_fallback()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_profiles.clear()
	_validation_errors.clear()
	schema_version = 0
	default_profile_id = "star_continent"
	if not FileAccess.file_exists(path):
		_record_error("Resource distribution registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_record_error("Unable to open resource distribution registry: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		_record_error("Invalid resource distribution JSON root: %s" % path)
		return false
	var root_data: Dictionary = parsed
	var raw_profiles: Variant = root_data.get("profiles", [])
	if raw_profiles is not Array:
		_record_error("Resource distribution profiles must be an array: %s" % path)
		return false
	schema_version = maxi(1, int(root_data.get("schema_version", 1)))
	default_profile_id = str(root_data.get("default_profile", "star_continent")).strip_edges()
	for raw_value in raw_profiles:
		if raw_value is not Dictionary:
			_record_error("Resource distribution profile entry must be an object")
			continue
		var raw_profile: Dictionary = raw_value
		var normalized: Dictionary = _normalize_profile(raw_profile)
		var profile_id := str(normalized.get("id", ""))
		if profile_id.is_empty():
			continue
		_profiles[profile_id] = normalized
	if _profiles.is_empty():
		_record_error("Resource distribution registry contains no valid profiles")
		return false
	if default_profile_id.is_empty() or not _profiles.has(default_profile_id):
		_record_error("Unknown default resource profile: %s" % default_profile_id)
		default_profile_id = get_profile_ids()[0]
	return true


func get_profile(profile_id: String) -> Dictionary:
	var resolved_id: String = profile_id if _profiles.has(profile_id) else default_profile_id
	return _profiles.get(resolved_id, {}).duplicate(true)


func get_profile_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id in _profiles.keys():
		result.append(str(raw_id))
	result.sort()
	return result


func get_summary(profile_id: String) -> String:
	return str(get_profile(profile_id).get("summary", ""))


func resolve_block(profile_id: String, y: int, roll: int) -> String:
	return PolicyScript.resolve_block(get_profile(profile_id), y, roll)


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func _normalize_profile(raw_profile: Dictionary) -> Dictionary:
	var profile_id := str(raw_profile.get("id", "")).strip_edges()
	if profile_id.is_empty():
		_record_error("Resource distribution profile id is empty")
		return {}
	if _profiles.has(profile_id):
		_record_error("Duplicate resource distribution profile: %s" % profile_id)
		return {}
	var summary := str(raw_profile.get("summary", "")).strip_edges()
	if summary.is_empty():
		_record_error("Resource distribution summary is empty: %s" % profile_id)
		return {}
	var fallback_block := str(raw_profile.get("fallback_block", "stone")).strip_edges()
	if not BlockRegistryScript.has_block(fallback_block):
		_record_error("Unknown fallback block '%s' for resource profile %s" % [fallback_block, profile_id])
		return {}
	var raw_entries: Variant = raw_profile.get("entries", [])
	if raw_entries is not Array:
		_record_error("Resource distribution entries must be an array: %s" % profile_id)
		return {}
	var entries: Array[Dictionary] = []
	var seen_blocks: Dictionary = {}
	var previous_threshold := 0
	for raw_entry in raw_entries:
		if raw_entry is not Dictionary:
			_record_error("Resource distribution entry must be an object: %s" % profile_id)
			continue
		var entry_data: Dictionary = raw_entry
		var block_id := str(entry_data.get("block_id", "")).strip_edges()
		var min_y := int(entry_data.get("min_y", 1))
		var max_y := int(entry_data.get("max_y", 0))
		var threshold := int(entry_data.get("cumulative_threshold", 0))
		if not BlockRegistryScript.has_block(block_id):
			_record_error("Unknown resource block '%s' for profile %s" % [block_id, profile_id])
			continue
		if seen_blocks.has(block_id):
			_record_error("Duplicate resource block '%s' for profile %s" % [block_id, profile_id])
			continue
		if min_y < 0 or max_y < min_y:
			_record_error("Invalid height range for %s in profile %s" % [block_id, profile_id])
			continue
		if threshold <= previous_threshold or threshold >= PolicyScript.ROLL_SCALE:
			_record_error("Resource thresholds must be strictly increasing below %d: %s" % [PolicyScript.ROLL_SCALE, profile_id])
			continue
		seen_blocks[block_id] = true
		previous_threshold = threshold
		entries.append({
			"block_id": block_id,
			"min_y": min_y,
			"max_y": max_y,
			"cumulative_threshold": threshold,
		})
	if entries.is_empty():
		_record_error("Resource distribution profile has no valid entries: %s" % profile_id)
		return {}
	return {
		"id": profile_id,
		"name": str(raw_profile.get("name", profile_id)),
		"summary": summary,
		"fallback_block": fallback_block,
		"entries": entries,
	}


func _install_builtin_fallback() -> void:
	schema_version = 1
	default_profile_id = "star_continent"
	_profiles = {
		"star_continent": {
			"id": "star_continent",
			"name": "Built-in balanced resources",
			"summary": "Balanced built-in resource fallback.",
			"fallback_block": "stone",
			"entries": [
				{"block_id":"diamond_ore", "min_y":1, "max_y":10, "cumulative_threshold":22},
				{"block_id":"gold_ore", "min_y":1, "max_y":19, "cumulative_threshold":70},
				{"block_id":"iron_ore", "min_y":1, "max_y":33, "cumulative_threshold":205},
				{"block_id":"coal_ore", "min_y":1, "max_y":63, "cumulative_threshold":500},
			],
		}
	}


func _record_error(message: String) -> void:
	_validation_errors.append(message)
	push_warning(message)
