class_name HostileEncounterRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/hostile_encounters.json"
const SUPPORTED_SCHEMA_VERSIONS: Array[int] = [1]
const ALLOWED_ROLES: Array[String] = ["vanguard", "support", "finisher"]
const ALLOWED_SPECIES: Array[String] = ["zombie", "abyss_marksman", "abyss_brute"]
const MAX_PROFILES := 16
const MAX_MEMBERS_PER_ENCOUNTER := 5
const MAX_MEMBER_COUNT_PER_ENTRY := 3
const MAX_TOTAL_PRESSURE := 8.0
const MIN_SPAWN_RADIUS := 12.0
const MAX_SPAWN_RADIUS := 36.0

var schema_version := 0
var _profiles: Dictionary = {}
var _validation_errors: Array[String] = []


func _init() -> void:
	if not load_from_file():
		_install_fallback()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	var errors: Array[String] = []
	if not FileAccess.file_exists(path):
		errors.append("Hostile encounter data is missing: %s" % path)
		_validation_errors = errors
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Unable to open hostile encounter data: %s" % path)
		_validation_errors = errors
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		errors.append("Hostile encounter data must be an object")
		_validation_errors = errors
		return false
	var root_data: Dictionary = parsed
	var next_schema_version := int(root_data.get("schema_version", 0))
	if next_schema_version not in SUPPORTED_SCHEMA_VERSIONS:
		errors.append("Unsupported hostile encounter schema_version: %d" % next_schema_version)
	var raw_profiles: Variant = root_data.get("profiles", [])
	if raw_profiles is not Array:
		errors.append("Hostile encounter profiles must be an array")
		_validation_errors = errors
		return false
	if raw_profiles.size() > MAX_PROFILES:
		errors.append("Hostile encounter profile count exceeds %d" % MAX_PROFILES)
	var staged: Dictionary = {}
	for raw_profile: Variant in raw_profiles:
		if raw_profile is not Dictionary:
			errors.append("Hostile encounter profile must be an object")
			continue
		var normalized := _normalize_profile(raw_profile, errors)
		var profile_id := str(normalized.get("id", ""))
		if profile_id.is_empty():
			continue
		if staged.has(profile_id):
			errors.append("Duplicate hostile encounter profile: %s" % profile_id)
			continue
		staged[profile_id] = normalized
	if staged.is_empty():
		errors.append("Hostile encounter data contains no valid profiles")
	if not errors.is_empty():
		_validation_errors = errors.duplicate()
		return false
	_profiles = staged
	schema_version = next_schema_version
	_validation_errors.clear()
	return true


func get_profile(profile_id: String) -> Dictionary:
	var raw_profile: Variant = _profiles.get(profile_id, {})
	return raw_profile.duplicate(true) if raw_profile is Dictionary else {}


func get_profiles() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = _profiles.keys()
	ids.sort()
	for raw_id: Variant in ids:
		result.append(get_profile(str(raw_id)))
	return result


func get_profile_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in _profiles.keys():
		result.append(str(raw_id))
	result.sort()
	return result


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func _normalize_profile(raw_profile: Dictionary, errors: Array[String]) -> Dictionary:
	var profile_id := str(raw_profile.get("id", "")).strip_edges()
	var display_name := str(raw_profile.get("display_name", profile_id)).strip_edges()
	if profile_id.is_empty() or profile_id.length() > 48 or display_name.is_empty():
		errors.append("Hostile encounter profile has invalid identity")
		return {}
	var map_ids := _normalize_string_array(raw_profile.get("map_ids", []), 8)
	var phase_ids := _normalize_string_array(raw_profile.get("phase_ids", []), 4)
	if map_ids.is_empty() or phase_ids.is_empty():
		errors.append("Hostile encounter profile lacks map or phase scope: %s" % profile_id)
		return {}
	for phase_id: String in phase_ids:
		if phase_id not in ["day", "dawn", "dusk", "night"]:
			errors.append("Invalid hostile encounter phase for %s: %s" % [profile_id, phase_id])
			return {}
	var weight := int(raw_profile.get("weight", 0))
	var minimum_player_y := float(raw_profile.get("minimum_player_y", -64.0))
	var maximum_player_y := float(raw_profile.get("maximum_player_y", 96.0))
	var minimum_health_ratio := float(raw_profile.get("minimum_health_ratio", 0.5))
	var cooldown_seconds := float(raw_profile.get("cooldown_seconds", 30.0))
	var minimum_existing_pressure := float(raw_profile.get("minimum_existing_pressure", 0.0))
	var maximum_existing_pressure := float(raw_profile.get("maximum_existing_pressure", 0.0))
	var maximum_total_pressure := float(raw_profile.get("maximum_total_pressure", 0.0))
	var minimum_spawn_radius := float(raw_profile.get("minimum_spawn_radius", 20.0))
	var maximum_spawn_radius := float(raw_profile.get("maximum_spawn_radius", 28.0))
	if weight < 1 or weight > 100:
		errors.append("Invalid hostile encounter weight: %s" % profile_id)
		return {}
	if minimum_player_y > maximum_player_y:
		errors.append("Invalid hostile encounter vertical range: %s" % profile_id)
		return {}
	if minimum_health_ratio < 0.2 or minimum_health_ratio > 1.0:
		errors.append("Invalid hostile encounter health threshold: %s" % profile_id)
		return {}
	if cooldown_seconds < 8.0 or cooldown_seconds > 180.0:
		errors.append("Invalid hostile encounter cooldown: %s" % profile_id)
		return {}
	if minimum_existing_pressure < 0.0 or maximum_existing_pressure < minimum_existing_pressure:
		errors.append("Invalid hostile encounter existing pressure range: %s" % profile_id)
		return {}
	if maximum_total_pressure <= 0.0 or maximum_total_pressure > MAX_TOTAL_PRESSURE:
		errors.append("Invalid hostile encounter total pressure: %s" % profile_id)
		return {}
	if (
		minimum_spawn_radius < MIN_SPAWN_RADIUS
		or maximum_spawn_radius < minimum_spawn_radius
		or maximum_spawn_radius > MAX_SPAWN_RADIUS
	):
		errors.append("Invalid hostile encounter spawn radius: %s" % profile_id)
		return {}
	var raw_members: Variant = raw_profile.get("members", [])
	if raw_members is not Array:
		errors.append("Hostile encounter members must be an array: %s" % profile_id)
		return {}
	var members: Array[Dictionary] = []
	var member_count := 0
	var species_counts: Dictionary = {}
	for raw_member: Variant in raw_members:
		if raw_member is not Dictionary:
			errors.append("Hostile encounter member must be an object: %s" % profile_id)
			continue
		var species_id := str(raw_member.get("species_id", "")).strip_edges()
		var role := str(raw_member.get("role", "")).strip_edges()
		var count := int(raw_member.get("count", 0))
		if species_id not in ALLOWED_SPECIES or role not in ALLOWED_ROLES:
			errors.append("Invalid hostile encounter member for %s" % profile_id)
			continue
		if count < 1 or count > MAX_MEMBER_COUNT_PER_ENTRY:
			errors.append("Invalid hostile encounter member count for %s" % profile_id)
			continue
		member_count += count
		species_counts[species_id] = int(species_counts.get(species_id, 0)) + count
		members.append({"species_id": species_id, "role": role, "count": count})
	if member_count < 2 or member_count > MAX_MEMBERS_PER_ENCOUNTER:
		errors.append("Hostile encounter member total must be 2..%d: %s" % [MAX_MEMBERS_PER_ENCOUNTER, profile_id])
		return {}
	if members.is_empty():
		return {}
	return {
		"id": profile_id,
		"display_name": display_name,
		"map_ids": map_ids,
		"phase_ids": phase_ids,
		"weight": weight,
		"minimum_player_y": minimum_player_y,
		"maximum_player_y": maximum_player_y,
		"minimum_health_ratio": minimum_health_ratio,
		"cooldown_seconds": cooldown_seconds,
		"minimum_existing_pressure": minimum_existing_pressure,
		"maximum_existing_pressure": maximum_existing_pressure,
		"maximum_total_pressure": maximum_total_pressure,
		"minimum_spawn_radius": minimum_spawn_radius,
		"maximum_spawn_radius": maximum_spawn_radius,
		"member_count": member_count,
		"species_counts": species_counts,
		"members": members,
	}


func _normalize_string_array(raw_value: Variant, maximum_size: int) -> Array[String]:
	var result: Array[String] = []
	if raw_value is not Array:
		return result
	for raw_item: Variant in raw_value:
		var item := str(raw_item).strip_edges()
		if item.is_empty() or item in result:
			continue
		result.append(item)
		if result.size() >= maximum_size:
			break
	return result


func _install_fallback() -> void:
	schema_version = 1
	_profiles = {
		"continent_night_patrol": {
			"id":"continent_night_patrol", "display_name":"夜行巡猎队",
			"map_ids":["star_continent"], "phase_ids":["night"], "weight":1,
			"minimum_player_y":-64.0, "maximum_player_y":96.0,
			"minimum_health_ratio":0.5, "cooldown_seconds":34.0,
			"minimum_existing_pressure":0.0, "maximum_existing_pressure":0.0,
			"maximum_total_pressure":2.5, "minimum_spawn_radius":22.0,
			"maximum_spawn_radius":27.0, "member_count":2,
			"species_counts":{"zombie":2},
			"members":[{"species_id":"zombie", "role":"vanguard", "count":2}],
		}
	}
