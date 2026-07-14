class_name AnimalAttractionRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/animal_attraction.json"

var schema_version: int = 0
var _refresh_seconds: float = 0.25
var _target_timeout_seconds: float = 0.75
var _species: Dictionary = {}
var _loaded: bool = false


func ensure_loaded(path: String = DEFAULT_DATA_PATH) -> bool:
	if _loaded:
		return not _species.is_empty()
	return load_from_file(path)


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_loaded = true
	_species.clear()
	if not FileAccess.file_exists(path):
		push_error("Animal attraction registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open animal attraction registry: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary or parsed.get("species", {}) is not Dictionary:
		push_error("Invalid animal attraction registry JSON: %s" % path)
		return false
	var data: Dictionary = parsed
	schema_version = maxi(1, int(data.get("schema_version", 1)))
	_refresh_seconds = clampf(float(data.get("refresh_seconds", 0.25)), 0.05, 2.0)
	_target_timeout_seconds = maxf(
		_refresh_seconds + 0.05, float(data.get("target_timeout_seconds", 0.75))
	)
	var raw_species: Dictionary = data.get("species", {})
	for raw_species_id: Variant in raw_species:
		var species_id := str(raw_species_id)
		var raw_profile: Variant = raw_species[raw_species_id]
		if species_id.is_empty() or raw_profile is not Dictionary:
			continue
		var profile := _normalize_profile(species_id, raw_profile)
		if not profile.is_empty():
			_species[species_id] = profile
	return not _species.is_empty()


func supports_species(species_id: String) -> bool:
	ensure_loaded()
	return _species.has(species_id)


func get_profile(species_id: String) -> Dictionary:
	ensure_loaded()
	return _species.get(species_id, {}).duplicate(true)


func get_all_profiles() -> Array[Dictionary]:
	ensure_loaded()
	var result: Array[Dictionary] = []
	for raw_profile: Variant in _species.values():
		if raw_profile is Dictionary:
			result.append(raw_profile.duplicate(true))
	return result


func species_count() -> int:
	ensure_loaded()
	return _species.size()


func get_refresh_seconds() -> float:
	ensure_loaded()
	return _refresh_seconds


func get_target_timeout_seconds() -> float:
	ensure_loaded()
	return _target_timeout_seconds


func _normalize_profile(species_id: String, raw_profile: Dictionary) -> Dictionary:
	var follow_radius := float(raw_profile.get("follow_radius", 0.0))
	var stop_distance := float(raw_profile.get("stop_distance", 0.0))
	if follow_radius <= 1.0 or stop_distance <= 0.0 or stop_distance >= follow_radius:
		return {}
	return {
		"species_id": species_id,
		"follow_radius": clampf(follow_radius, 2.0, 32.0),
		"stop_distance": clampf(stop_distance, 0.5, follow_radius - 0.25),
	}
