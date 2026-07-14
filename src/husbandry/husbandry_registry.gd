class_name HusbandryRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/husbandry.json"

var schema_version: int = 0
var _data: Dictionary = {}
var _species: Dictionary = {}
var _loaded: bool = false


func ensure_loaded(path: String = DEFAULT_DATA_PATH) -> bool:
	if _loaded:
		return not _species.is_empty()
	return load_from_file(path)


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_loaded = true
	_data.clear()
	_species.clear()
	if not FileAccess.file_exists(path):
		push_error("Husbandry registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open husbandry registry: %s" % path)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary or parsed.get("species", {}) is not Dictionary:
		push_error("Invalid husbandry registry JSON: %s" % path)
		return false
	_data = parsed.duplicate(true)
	schema_version = maxi(1, int(_data.get("schema_version", 1)))
	var raw_species: Dictionary = _data.get("species", {})
	for raw_species_id in raw_species:
		var species_id := str(raw_species_id)
		var raw_profile = raw_species[raw_species_id]
		if species_id.is_empty() or raw_profile is not Dictionary:
			continue
		var profile := _normalize_profile(species_id, raw_profile)
		if not profile.is_empty():
			_species[species_id] = profile
	return not _species.is_empty()


func supports_species(species_id: String) -> bool:
	ensure_loaded()
	return _species.has(species_id)


func get_species(species_id: String) -> Dictionary:
	ensure_loaded()
	return _species.get(species_id, {}).duplicate(true)


func get_all_species() -> Array[Dictionary]:
	ensure_loaded()
	var result: Array[Dictionary] = []
	for species_id in _species:
		result.append(_species[species_id].duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	return result


func species_count() -> int:
	ensure_loaded()
	return _species.size()


func get_pair_radius() -> float:
	ensure_loaded()
	return maxf(1.0, float(_data.get("pair_radius", 6.0)))


func get_max_managed_animals() -> int:
	ensure_loaded()
	return maxi(2, int(_data.get("max_managed_animals", 24)))


func get_max_offline_seconds() -> float:
	ensure_loaded()
	return maxf(0.0, float(_data.get("max_offline_seconds", 21600.0)))


func get_simulation_radius() -> float:
	ensure_loaded()
	return maxf(8.0, float(_data.get("simulation_radius", 48.0)))


func get_baby_scale() -> float:
	ensure_loaded()
	return clampf(float(_data.get("baby_scale", 0.58)), 0.25, 0.9)


func _normalize_profile(species_id: String, raw_profile: Dictionary) -> Dictionary:
	var feed_item := str(raw_profile.get("feed_item", ""))
	var growth_seconds := float(raw_profile.get("growth_seconds", 0.0))
	var love_seconds := float(raw_profile.get("love_seconds", 0.0))
	var cooldown_seconds := float(raw_profile.get("breed_cooldown_seconds", 0.0))
	var reduction_ratio := float(raw_profile.get("baby_growth_reduction_ratio", 0.0))
	if (
		feed_item.is_empty()
		or growth_seconds <= 0.0
		or love_seconds <= 0.0
		or cooldown_seconds <= 0.0
		or reduction_ratio <= 0.0
	):
		return {}
	return {
		"id": species_id,
		"name": str(raw_profile.get("name", species_id)),
		"feed_item": feed_item,
		"growth_seconds": growth_seconds,
		"love_seconds": love_seconds,
		"breed_cooldown_seconds": cooldown_seconds,
		"baby_growth_reduction_ratio": clampf(reduction_ratio, 0.01, 1.0),
	}
