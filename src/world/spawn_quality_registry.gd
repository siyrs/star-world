class_name SpawnQualityRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/spawn_quality_profiles.json"
const DEFAULT_PROFILE_ID := "star_continent"
const MapProfileCatalogScript = preload("res://src/world/map_profile_catalog.gd")
const BUILTIN_DEFAULTS := {
	"search_radius": 64,
	"candidate_budget": 192,
	"wall_time_budget_ms": 30000,
	"clearance_radius": 2,
	"obstacle_scan_radius": 5,
	"view_distance": 6,
	"minimum_clearance_ratio": 0.84,
	"minimum_walkable_neighbors": 6,
	"minimum_open_view_directions": 3,
	"minimum_forward_view_distance": 4,
	"minimum_obstacle_distance": 3.0,
	"maximum_step_height": 1,
	"rejected_surface_blocks": ["wood", "leaves", "ice", "cactus", "ruin_pillar", "bedrock"],
	"nearby_obstacle_blocks": ["wood", "leaves", "cactus", "ruin_pillar"],
	"hazard_blocks": ["water", "lava"],
	"forward_direction": [0, -1],
	"weights": {
		"clearance": 0.35,
		"walkability": 0.25,
		"visibility": 0.30,
		"proximity": 0.10,
	},
}

var schema_version := 0
var default_profile_id := DEFAULT_PROFILE_ID
var _defaults: Dictionary = {}
var _profiles: Dictionary = {}
var _validation_errors: Array[String] = []
var _loaded_from_file := false


func _init() -> void:
	if not load_from_file():
		_install_builtin_fallback()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_reset()
	if not FileAccess.file_exists(path):
		_record_error("Spawn quality registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_record_error("Unable to open spawn quality registry: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		_record_error("Invalid spawn quality JSON root: %s" % path)
		return false
	var root_data: Dictionary = parsed
	schema_version = maxi(1, int(root_data.get("schema_version", 1)))
	default_profile_id = str(root_data.get("default_profile", DEFAULT_PROFILE_ID)).strip_edges()
	var raw_defaults: Variant = root_data.get("defaults", {})
	if raw_defaults is not Dictionary:
		_record_error("Spawn quality defaults must be an object")
		return false
	_defaults = _normalize_policy((raw_defaults as Dictionary).duplicate(true))
	var raw_profiles: Variant = root_data.get("profiles", [])
	if raw_profiles is not Array:
		_record_error("Spawn quality profiles must be an array")
		return false
	for raw_profile: Variant in raw_profiles:
		if raw_profile is not Dictionary:
			_record_error("Spawn quality profile entry must be an object")
			continue
		var profile_id := str((raw_profile as Dictionary).get("id", "")).strip_edges()
		if profile_id.is_empty():
			_record_error("Spawn quality profile id is empty")
			continue
		if _profiles.has(profile_id):
			_record_error("Duplicate spawn quality profile: %s" % profile_id)
			continue
		var merged := _defaults.duplicate(true)
		for key: Variant in (raw_profile as Dictionary).keys():
			if str(key) not in ["id", "summary"]:
				merged[key] = (raw_profile as Dictionary).get(key)
		merged = _normalize_policy(merged)
		merged["id"] = profile_id
		merged["summary"] = str((raw_profile as Dictionary).get("summary", "")).strip_edges()
		_profiles[profile_id] = merged
	for required_id: String in MapProfileCatalogScript.get_ids():
		if not _profiles.has(required_id):
			_record_error("Missing spawn quality profile: %s" % required_id)
	if not _profiles.has(default_profile_id):
		_record_error("Unknown default spawn quality profile: %s" % default_profile_id)
		default_profile_id = DEFAULT_PROFILE_ID
	_loaded_from_file = _validation_errors.is_empty()
	return _loaded_from_file


func get_profile(profile_id: String) -> Dictionary:
	var resolved_id := profile_id if _profiles.has(profile_id) else default_profile_id
	return (_profiles.get(resolved_id, _defaults) as Dictionary).duplicate(true)


func get_profile_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in _profiles.keys():
		result.append(str(raw_id))
	result.sort()
	return result


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func get_snapshot(profile_id: String) -> Dictionary:
	var profile := get_profile(profile_id)
	return {
		"schema_version": schema_version,
		"loaded_from_file": _loaded_from_file,
		"profile_id": str(profile.get("id", "")),
		"summary": str(profile.get("summary", "")),
		"search_radius": int(profile.get("search_radius", 0)),
		"candidate_budget": int(profile.get("candidate_budget", 0)),
		"validation_error_count": _validation_errors.size(),
	}


func _normalize_policy(raw_policy: Dictionary) -> Dictionary:
	var result := BUILTIN_DEFAULTS.duplicate(true)
	for key: Variant in raw_policy.keys():
		result[key] = raw_policy.get(key)
	result["search_radius"] = clampi(int(result.get("search_radius", 64)), 8, 64)
	result["candidate_budget"] = clampi(int(result.get("candidate_budget", 192)), 16, 512)
	result["wall_time_budget_ms"] = clampi(int(result.get("wall_time_budget_ms", 30000)), 5000, 120000)
	result["clearance_radius"] = clampi(int(result.get("clearance_radius", 2)), 1, 4)
	result["obstacle_scan_radius"] = clampi(int(result.get("obstacle_scan_radius", 5)), 2, 8)
	result["view_distance"] = clampi(int(result.get("view_distance", 6)), 3, 12)
	result["minimum_clearance_ratio"] = clampf(
		float(result.get("minimum_clearance_ratio", 0.84)), 0.5, 1.0
	)
	result["minimum_walkable_neighbors"] = clampi(
		int(result.get("minimum_walkable_neighbors", 6)), 2, 8
	)
	result["minimum_open_view_directions"] = clampi(
		int(result.get("minimum_open_view_directions", 3)), 1, 4
	)
	result["minimum_forward_view_distance"] = clampi(
		int(result.get("minimum_forward_view_distance", 4)),
		1,
		int(result["view_distance"])
	)
	result["minimum_obstacle_distance"] = clampf(
		float(result.get("minimum_obstacle_distance", 3.0)), 1.0, 8.0
	)
	result["maximum_step_height"] = clampi(int(result.get("maximum_step_height", 1)), 1, 3)
	for list_key: String in [
		"rejected_surface_blocks",
		"nearby_obstacle_blocks",
		"hazard_blocks",
	]:
		result[list_key] = _normalize_string_array(result.get(list_key, []))
	var raw_forward: Variant = result.get("forward_direction", [0, -1])
	if (
		raw_forward is not Array
		or (raw_forward as Array).size() < 2
		or (int(raw_forward[0]) == 0 and int(raw_forward[1]) == 0)
	):
		result["forward_direction"] = [0, -1]
	else:
		result["forward_direction"] = [
			clampi(int(raw_forward[0]), -1, 1),
			clampi(int(raw_forward[1]), -1, 1),
		]
	var raw_weights: Variant = result.get("weights", {})
	var weights := BUILTIN_DEFAULTS["weights"].duplicate(true) as Dictionary
	if raw_weights is Dictionary:
		for key: Variant in weights.keys():
			weights[key] = maxf(0.0, float((raw_weights as Dictionary).get(key, weights[key])))
	var weight_total := (
		float(weights.get("clearance", 0.0))
		+ float(weights.get("walkability", 0.0))
		+ float(weights.get("visibility", 0.0))
		+ float(weights.get("proximity", 0.0))
	)
	if weight_total <= 0.0:
		weights = BUILTIN_DEFAULTS["weights"].duplicate(true)
	else:
		for key: Variant in weights.keys():
			weights[key] = float(weights[key]) / weight_total
	result["weights"] = weights
	return result


func _normalize_string_array(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw_value is not Array:
		return result
	for raw_entry: Variant in raw_value:
		var entry := str(raw_entry).strip_edges()
		if not entry.is_empty() and entry not in result:
			result.append(entry)
	return result


func _install_builtin_fallback() -> void:
	_defaults = _normalize_policy(BUILTIN_DEFAULTS)
	for profile_id: String in MapProfileCatalogScript.get_ids():
		var profile := _defaults.duplicate(true)
		profile["id"] = profile_id
		profile["summary"] = "Built-in safe spawn quality fallback."
		_profiles[profile_id] = profile
	schema_version = 1
	default_profile_id = DEFAULT_PROFILE_ID


func _reset() -> void:
	schema_version = 0
	default_profile_id = DEFAULT_PROFILE_ID
	_defaults.clear()
	_profiles.clear()
	_validation_errors.clear()
	_loaded_from_file = false


func _record_error(message: String) -> void:
	_validation_errors.append(message)
	push_warning(message)
