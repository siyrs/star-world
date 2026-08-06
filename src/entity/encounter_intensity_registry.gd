class_name EncounterIntensityRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/encounter_intensity_profiles.json"
const SUPPORTED_SCHEMA_VERSIONS: Array[int] = [1]
const DEFAULT_PROFILE_ID := "standard"
const REQUIRED_PROFILE_IDS: Array[String] = ["casual", "standard", "high_risk"]
const MAX_PROFILES := 8
const MIN_COOLDOWN_MULTIPLIER := 0.5
const MAX_COOLDOWN_MULTIPLIER := 2.0
const MIN_DANGER_PRESSURE_MULTIPLIER := 0.5
const MAX_DANGER_PRESSURE_MULTIPLIER := 1.5

var schema_version := 0
var _profiles: Dictionary = {}
var _validation_errors: Array[String] = []


func _init() -> void:
	if not load_from_file():
		_install_fallback()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	var errors: Array[String] = []
	if not FileAccess.file_exists(path):
		errors.append("Encounter intensity data is missing: %s" % path)
		_validation_errors = errors
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Unable to open encounter intensity data: %s" % path)
		_validation_errors = errors
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		errors.append("Encounter intensity data must be an object")
		_validation_errors = errors
		return false
	var root_data: Dictionary = parsed
	var next_schema_version := int(root_data.get("schema_version", 0))
	if next_schema_version not in SUPPORTED_SCHEMA_VERSIONS:
		errors.append("Unsupported encounter intensity schema_version: %d" % next_schema_version)
	var raw_profiles: Variant = root_data.get("profiles", [])
	if raw_profiles is not Array:
		errors.append("Encounter intensity profiles must be an array")
		_validation_errors = errors
		return false
	if raw_profiles.size() > MAX_PROFILES:
		errors.append("Encounter intensity profile count exceeds %d" % MAX_PROFILES)
	var staged: Dictionary = {}
	for raw_profile: Variant in raw_profiles:
		if raw_profile is not Dictionary:
			errors.append("Encounter intensity profile must be an object")
			continue
		var normalized := _normalize_profile(raw_profile, errors)
		var profile_id := str(normalized.get("id", ""))
		if profile_id.is_empty():
			continue
		if staged.has(profile_id):
			errors.append("Duplicate encounter intensity profile: %s" % profile_id)
			continue
		staged[profile_id] = normalized
	for profile_id: String in REQUIRED_PROFILE_IDS:
		if not staged.has(profile_id):
			errors.append("Required encounter intensity profile is missing: %s" % profile_id)
	if not errors.is_empty():
		_validation_errors = errors.duplicate()
		return false
	_profiles = staged
	schema_version = next_schema_version
	_validation_errors.clear()
	return true


func get_profile(profile_id: String) -> Dictionary:
	var normalized_id := normalize_profile_id(profile_id)
	var raw_profile: Variant = _profiles.get(normalized_id, {})
	return raw_profile.duplicate(true) if raw_profile is Dictionary else {}


func get_profile_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in _profiles.keys():
		result.append(str(raw_id))
	result.sort()
	return result


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func normalize_profile_id(value: Variant) -> String:
	var requested := str(value).strip_edges().to_lower()
	return requested if _profiles.has(requested) else DEFAULT_PROFILE_ID


func _normalize_profile(raw_profile: Dictionary, errors: Array[String]) -> Dictionary:
	var profile_id := str(raw_profile.get("id", "")).strip_edges().to_lower()
	var display_name := str(raw_profile.get("display_name", "")).strip_edges()
	if profile_id not in REQUIRED_PROFILE_IDS:
		errors.append("Encounter intensity profile has an unsupported identity: %s" % profile_id)
		return {}
	if display_name.is_empty() or display_name.length() > 24:
		errors.append("Encounter intensity profile has an invalid display name: %s" % profile_id)
		return {}
	var cooldown_multiplier := float(raw_profile.get("cooldown_multiplier", 0.0))
	var danger_multiplier := float(raw_profile.get("danger_pressure_multiplier", 0.0))
	if (
		not is_finite(cooldown_multiplier)
		or cooldown_multiplier < MIN_COOLDOWN_MULTIPLIER
		or cooldown_multiplier > MAX_COOLDOWN_MULTIPLIER
	):
		errors.append("Encounter intensity cooldown multiplier is invalid: %s" % profile_id)
		return {}
	if (
		not is_finite(danger_multiplier)
		or danger_multiplier < MIN_DANGER_PRESSURE_MULTIPLIER
		or danger_multiplier > MAX_DANGER_PRESSURE_MULTIPLIER
	):
		errors.append("Encounter intensity danger multiplier is invalid: %s" % profile_id)
		return {}
	return {
		"id": profile_id,
		"display_name": display_name,
		"cooldown_multiplier": cooldown_multiplier,
		"danger_pressure_multiplier": danger_multiplier,
	}


func _install_fallback() -> void:
	_profiles = {
		"casual": {
			"id":"casual", "display_name":"休闲",
			"cooldown_multiplier":1.35, "danger_pressure_multiplier":0.75,
		},
		"standard": {
			"id":"standard", "display_name":"标准",
			"cooldown_multiplier":1.0, "danger_pressure_multiplier":1.0,
		},
		"high_risk": {
			"id":"high_risk", "display_name":"高风险",
			"cooldown_multiplier":0.75, "danger_pressure_multiplier":1.25,
		},
	}
	schema_version = 1
