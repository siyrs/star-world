class_name HostileAttackRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/hostile_attacks.json"

var schema_version := 0
var _profiles: Dictionary = {}
var _validation_errors: Array[String] = []


func _init() -> void:
	if not load_from_file():
		_install_fallback()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	schema_version = 0
	_profiles.clear()
	_validation_errors.clear()
	if not FileAccess.file_exists(path):
		_record_error("Hostile attack data is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_record_error("Unable to open hostile attack data: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		_record_error("Hostile attack data must be an object: %s" % path)
		return false
	var root_data: Dictionary = parsed
	schema_version = int(root_data.get("schema_version", 0))
	if schema_version != 1:
		_record_error("Unsupported hostile attack schema_version: %d" % schema_version)
	var raw_profiles: Variant = root_data.get("profiles", [])
	if raw_profiles is not Array:
		_record_error("Hostile attack profiles must be an array")
		return false
	for raw_profile: Variant in raw_profiles:
		if raw_profile is not Dictionary:
			_record_error("Hostile attack profile must be an object")
			continue
		var normalized := _normalize_profile(raw_profile)
		var species_id := str(normalized.get("species_id", ""))
		if species_id.is_empty():
			continue
		if _profiles.has(species_id):
			_record_error("Duplicate hostile attack profile: %s" % species_id)
			continue
		_profiles[species_id] = normalized
	if _profiles.is_empty():
		_record_error("Hostile attack data contains no valid profiles")
		return false
	return _validation_errors.is_empty()


func get_profile(species_id: String) -> Dictionary:
	var raw_profile: Variant = _profiles.get(species_id, {})
	return raw_profile.duplicate(true) if raw_profile is Dictionary else {}


func get_profile_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in _profiles.keys():
		result.append(str(raw_id))
	result.sort()
	return result


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func _normalize_profile(raw_profile: Dictionary) -> Dictionary:
	var species_id := str(raw_profile.get("species_id", "")).strip_edges()
	var source_id := str(raw_profile.get("source_id", species_id)).strip_edges()
	if species_id.is_empty() or source_id.is_empty():
		_record_error("Hostile attack profile has empty species/source identity")
		return {}
	var detection_range := float(raw_profile.get("detection_range", 0.0))
	var attack_range := float(raw_profile.get("attack_range", 0.0))
	var windup_seconds := float(raw_profile.get("windup_seconds", 0.0))
	var cooldown_seconds := float(raw_profile.get("cooldown_seconds", 0.0))
	var cancel_range_multiplier := float(raw_profile.get("cancel_range_multiplier", 0.0))
	var cancel_recovery_seconds := float(raw_profile.get("cancel_recovery_seconds", 0.0))
	var target_leash_multiplier := float(raw_profile.get("target_leash_multiplier", 0.0))
	var telegraph_radius_multiplier := float(
		raw_profile.get("telegraph_radius_multiplier", 0.0)
	)
	if attack_range < 0.25 or attack_range > 6.0:
		_record_error("Invalid hostile attack range for %s" % species_id)
		return {}
	if detection_range <= attack_range or detection_range > 64.0:
		_record_error("Detection range must exceed attack range for %s" % species_id)
		return {}
	if windup_seconds < 0.1 or windup_seconds > 3.0:
		_record_error("Invalid hostile attack windup for %s" % species_id)
		return {}
	if cooldown_seconds < 0.5 or cooldown_seconds > 30.0:
		_record_error("Invalid hostile attack cooldown for %s" % species_id)
		return {}
	if cancel_range_multiplier < 1.0 or cancel_range_multiplier > 3.0:
		_record_error("Invalid hostile attack cancel range for %s" % species_id)
		return {}
	if cancel_recovery_seconds < 0.0 or cancel_recovery_seconds > cooldown_seconds:
		_record_error("Invalid hostile attack cancel recovery for %s" % species_id)
		return {}
	if target_leash_multiplier < 1.0 or target_leash_multiplier > 3.0:
		_record_error("Invalid hostile target leash for %s" % species_id)
		return {}
	if telegraph_radius_multiplier < 0.5 or telegraph_radius_multiplier > 2.0:
		_record_error("Invalid hostile telegraph radius for %s" % species_id)
		return {}
	return {
		"species_id": species_id,
		"source_id": source_id,
		"detection_range": detection_range,
		"attack_range": attack_range,
		"windup_seconds": windup_seconds,
		"cooldown_seconds": cooldown_seconds,
		"cancel_range_multiplier": cancel_range_multiplier,
		"cancel_recovery_seconds": cancel_recovery_seconds,
		"target_leash_multiplier": target_leash_multiplier,
		"telegraph_radius_multiplier": telegraph_radius_multiplier,
	}


func _install_fallback() -> void:
	schema_version = 1
	_profiles = {
		"zombie": {
			"species_id":"zombie",
			"source_id":"zombie",
			"detection_range":18.0,
			"attack_range":1.65,
			"windup_seconds":0.8,
			"cooldown_seconds":5.0,
			"cancel_range_multiplier":1.35,
			"cancel_recovery_seconds":0.6,
			"target_leash_multiplier":1.4,
			"telegraph_radius_multiplier":1.05,
		}
	}


func _record_error(message: String) -> void:
	_validation_errors.append(message)
	push_warning(message)
