class_name WeatherRegistry
extends RefCounted

const DATA_PATH := "res://data/weather_profiles.json"
const SCHEMA_VERSION := 1
const MAX_STATES_PER_PROFILE := 4
const EXPECTED_MAP_IDS: Array[String] = [
	"star_continent",
	"desert_ruins",
	"frozen_wastes",
	"sky_islands",
	"abyss_world",
]
const ALLOWED_TONES: Array[String] = ["success", "info", "warning", "error"]

var profiles: Dictionary = {}
var _validation_errors: Array[String] = []


func _init(path: String = DATA_PATH) -> void:
	load_profiles(path)


func load_profiles(path: String = DATA_PATH) -> bool:
	profiles.clear()
	_validation_errors.clear()
	if not FileAccess.file_exists(path):
		_validation_errors.append("Weather profile data is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_validation_errors.append("Unable to open weather profile data: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		_validation_errors.append("Weather profile root must be a Dictionary")
		return false
	if int(parsed.get("schema_version", 0)) != SCHEMA_VERSION:
		_validation_errors.append("Weather profile schema_version must be %d" % SCHEMA_VERSION)
	var raw_profiles: Variant = parsed.get("profiles", [])
	if raw_profiles is not Array:
		_validation_errors.append("Weather profiles must be an Array")
		return false
	for raw_profile: Variant in raw_profiles:
		if raw_profile is not Dictionary:
			_validation_errors.append("Weather profile entry must be a Dictionary")
			continue
		var normalized := _normalize_profile(raw_profile)
		if normalized.is_empty():
			continue
		var profile_id := str(normalized.get("id", ""))
		if profiles.has(profile_id):
			_validation_errors.append("Duplicate weather profile: %s" % profile_id)
			continue
		profiles[profile_id] = normalized
	for map_id: String in EXPECTED_MAP_IDS:
		if not profiles.has(map_id):
			_validation_errors.append("Missing weather profile for map: %s" % map_id)
	if profiles.size() != EXPECTED_MAP_IDS.size():
		_validation_errors.append(
			"Weather registry must contain exactly %d formal map profiles"
			% EXPECTED_MAP_IDS.size()
		)
	return _validation_errors.is_empty()


func get_profile(map_id: String) -> Dictionary:
	var raw: Variant = profiles.get(map_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func get_profile_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in profiles.keys():
		result.append(str(raw_id))
	result.sort()
	return result


func get_state(map_id: String, state_id: String) -> Dictionary:
	var profile := get_profile(map_id)
	var raw_states: Variant = profile.get("states", [])
	if raw_states is Array:
		for raw_state: Variant in raw_states:
			if raw_state is Dictionary and str(raw_state.get("id", "")) == state_id:
				return raw_state.duplicate(true)
	return {}


func get_state_ids(map_id: String) -> Array[String]:
	var result: Array[String] = []
	var profile := get_profile(map_id)
	var raw_states: Variant = profile.get("states", [])
	if raw_states is Array:
		for raw_state: Variant in raw_states:
			if raw_state is Dictionary:
				result.append(str(raw_state.get("id", "")))
	return result


func get_default_state_id(map_id: String) -> String:
	var profile := get_profile(map_id)
	return str(profile.get("default_state", "clear"))


func choose_state_id(map_id: String, world_seed: int, transition_index: int) -> String:
	var profile := get_profile(map_id)
	var raw_states: Variant = profile.get("states", [])
	if raw_states is not Array or raw_states.is_empty():
		return "clear"
	var total_weight := 0
	for raw_state: Variant in raw_states:
		if raw_state is Dictionary:
			total_weight += maxi(1, int(raw_state.get("weight", 1)))
	if total_weight <= 0:
		return get_default_state_id(map_id)
	var roll := _stable_hash("state|%s|%d|%d" % [map_id, world_seed, transition_index]) % total_weight
	for raw_state: Variant in raw_states:
		if raw_state is not Dictionary:
			continue
		roll -= maxi(1, int(raw_state.get("weight", 1)))
		if roll < 0:
			return str(raw_state.get("id", get_default_state_id(map_id)))
	return str(raw_states.back().get("id", get_default_state_id(map_id)))


func duration_for_state(
	map_id: String, state_id: String, world_seed: int, transition_index: int
) -> float:
	var state := get_state(map_id, state_id)
	if state.is_empty():
		state = get_state(map_id, get_default_state_id(map_id))
	if state.is_empty():
		return 90.0
	var minimum := maxi(15, int(state.get("min_duration_seconds", 60)))
	var maximum := maxi(minimum, int(state.get("max_duration_seconds", minimum)))
	var span := maximum - minimum + 1
	var offset := _stable_hash(
		"duration|%s|%s|%d|%d" % [map_id, state_id, world_seed, transition_index]
	) % span
	return float(minimum + offset)


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func _normalize_profile(raw: Dictionary) -> Dictionary:
	var profile_id := str(raw.get("id", "")).strip_edges()
	if profile_id.is_empty() or profile_id not in EXPECTED_MAP_IDS:
		_validation_errors.append("Unknown or empty weather profile id: %s" % profile_id)
		return {}
	var raw_states: Variant = raw.get("states", [])
	if raw_states is not Array or raw_states.is_empty():
		_validation_errors.append("Weather profile %s has no states" % profile_id)
		return {}
	if raw_states.size() > MAX_STATES_PER_PROFILE:
		_validation_errors.append(
			"Weather profile %s exceeds %d states" % [profile_id, MAX_STATES_PER_PROFILE]
		)
		return {}
	var states: Array[Dictionary] = []
	var state_ids: Array[String] = []
	for raw_state: Variant in raw_states:
		if raw_state is not Dictionary:
			_validation_errors.append("Weather state in %s must be a Dictionary" % profile_id)
			continue
		var state := _normalize_state(profile_id, raw_state)
		if state.is_empty():
			continue
		var state_id := str(state.get("id", ""))
		if state_id in state_ids:
			_validation_errors.append("Duplicate weather state %s/%s" % [profile_id, state_id])
			continue
		state_ids.append(state_id)
		states.append(state)
	var default_state := str(raw.get("default_state", "clear")).strip_edges()
	if default_state not in state_ids:
		_validation_errors.append(
			"Weather profile %s default state is not registered: %s"
			% [profile_id, default_state]
		)
	return {
		"id": profile_id,
		"default_state": default_state,
		"states": states,
	}


func _normalize_state(profile_id: String, raw: Dictionary) -> Dictionary:
	var state_id := str(raw.get("id", "")).strip_edges()
	var label := str(raw.get("label", "")).strip_edges()
	var tone := str(raw.get("tone", "info")).strip_edges()
	var weight := int(raw.get("weight", 0))
	var minimum := int(raw.get("min_duration_seconds", 0))
	var maximum := int(raw.get("max_duration_seconds", 0))
	var fog := float(raw.get("fog_multiplier", 0.0))
	var light := float(raw.get("light_multiplier", 0.0))
	var cloud := float(raw.get("cloud_opacity", -1.0))
	var sky_tint := str(raw.get("sky_tint", "")).strip_edges()
	var tint_strength := float(raw.get("tint_strength", -1.0))
	var exhaustion := float(raw.get("exhaustion_per_minute", -1.0))
	var valid := true
	if state_id.is_empty() or label.is_empty():
		valid = false
	if tone not in ALLOWED_TONES:
		valid = false
	if weight < 1 or weight > 1000:
		valid = false
	if minimum < 15 or maximum < minimum or maximum > 600:
		valid = false
	if fog < 0.5 or fog > 3.0:
		valid = false
	if light < 0.4 or light > 1.2:
		valid = false
	if cloud < 0.0 or cloud > 1.0:
		valid = false
	if not _is_hex_color(sky_tint):
		valid = false
	if tint_strength < 0.0 or tint_strength > 1.0:
		valid = false
	if exhaustion < 0.0 or exhaustion > 0.5:
		valid = false
	if not valid:
		_validation_errors.append("Invalid weather state contract: %s/%s" % [profile_id, state_id])
		return {}
	return {
		"id": state_id,
		"label": label,
		"tone": tone,
		"weight": weight,
		"min_duration_seconds": minimum,
		"max_duration_seconds": maximum,
		"fog_multiplier": fog,
		"light_multiplier": light,
		"cloud_opacity": cloud,
		"sky_tint": sky_tint,
		"tint_strength": tint_strength,
		"exhaustion_per_minute": exhaustion,
	}


func _is_hex_color(value: String) -> bool:
	if value.length() not in [7, 9] or not value.begins_with("#"):
		return false
	for index in range(1, value.length()):
		var code := value.unicode_at(index)
		var digit := code >= 48 and code <= 57
		var upper := code >= 65 and code <= 70
		var lower := code >= 97 and code <= 102
		if not digit and not upper and not lower:
			return false
	return true


func _stable_hash(text: String) -> int:
	var value: int = 2166136261
	for index in text.length():
		value = int(((value ^ text.unicode_at(index)) * 16777619) & 0x7FFFFFFF)
	return value
