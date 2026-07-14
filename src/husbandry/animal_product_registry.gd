class_name AnimalProductRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/animal_products.json"

var schema_version: int = 0
var _update_interval_seconds: float = 1.0
var _max_offline_seconds: float = 21600.0
var _pickup_spawn_radius: float = 14.0
var _profiles: Dictionary = {}
var _species_profiles: Dictionary = {}
var _loaded: bool = false


func ensure_loaded(path: String = DEFAULT_DATA_PATH) -> bool:
	if _loaded:
		return not _profiles.is_empty()
	return load_from_file(path)


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_loaded = true
	_profiles.clear()
	_species_profiles.clear()
	if not FileAccess.file_exists(path):
		push_error("Animal product registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open animal product registry: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary or parsed.get("profiles", []) is not Array:
		push_error("Invalid animal product registry JSON: %s" % path)
		return false
	var data: Dictionary = parsed
	schema_version = maxi(1, int(data.get("schema_version", 1)))
	_update_interval_seconds = clampf(
		float(data.get("update_interval_seconds", 1.0)), 0.1, 10.0
	)
	_max_offline_seconds = clampf(
		float(data.get("max_offline_seconds", 21600.0)), 0.0, 86400.0
	)
	_pickup_spawn_radius = clampf(
		float(data.get("pickup_spawn_radius", 14.0)), 2.0, 48.0
	)
	for raw_profile: Variant in data.get("profiles", []):
		if raw_profile is not Dictionary:
			continue
		var profile := _normalize_profile(raw_profile)
		var profile_id := str(profile.get("id", ""))
		var species_id := str(profile.get("species_id", ""))
		if (
			profile_id.is_empty()
			or species_id.is_empty()
			or _profiles.has(profile_id)
			or _species_profiles.has(species_id)
		):
			continue
		_profiles[profile_id] = profile
		_species_profiles[species_id] = profile
	return not _profiles.is_empty()


func get_profile(profile_id: String) -> Dictionary:
	ensure_loaded()
	return _profiles.get(profile_id, {}).duplicate(true)


func get_profile_for_species(species_id: String) -> Dictionary:
	ensure_loaded()
	return _species_profiles.get(species_id, {}).duplicate(true)


func get_all_profiles() -> Array[Dictionary]:
	ensure_loaded()
	var result: Array[Dictionary] = []
	for raw_profile: Variant in _profiles.values():
		if raw_profile is Dictionary:
			result.append(raw_profile.duplicate(true))
	return result


func profile_count() -> int:
	ensure_loaded()
	return _profiles.size()


func get_update_interval_seconds() -> float:
	ensure_loaded()
	return _update_interval_seconds


func get_max_offline_seconds() -> float:
	ensure_loaded()
	return _max_offline_seconds


func get_pickup_spawn_radius() -> float:
	ensure_loaded()
	return _pickup_spawn_radius


func _normalize_profile(raw_profile: Dictionary) -> Dictionary:
	var profile_id := str(raw_profile.get("id", ""))
	var species_id := str(raw_profile.get("species_id", ""))
	var product_item := str(raw_profile.get("product_item", ""))
	var interval_seconds := float(raw_profile.get("interval_seconds", 0.0))
	var max_pending := int(raw_profile.get("max_pending", 0))
	if (
		profile_id.is_empty()
		or species_id.is_empty()
		or product_item.is_empty()
		or interval_seconds <= 0.0
		or max_pending < 1
	):
		return {}
	return {
		"id": profile_id,
		"species_id": species_id,
		"product_item": product_item,
		"interval_seconds": clampf(interval_seconds, 5.0, 86400.0),
		"max_pending": clampi(max_pending, 1, 64),
		"adult_only": bool(raw_profile.get("adult_only", true)),
	}
