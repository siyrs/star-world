class_name CreatureEcologyRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/creature_ecology.json"
const CreatureFactoryScript = preload("res://src/entity/creature_factory.gd")
const PHASE_IDS: Array[String] = ["day", "dawn", "dusk", "night"]

var schema_version := 0
var default_profile_id := "star_continent"
var _profiles: Dictionary = {}
var _validation_errors: Array[String] = []


func _init() -> void:
	if not load_from_file():
		_install_fallback()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_profiles.clear()
	_validation_errors.clear()
	schema_version = 0
	default_profile_id = "star_continent"
	if not FileAccess.file_exists(path):
		_record_error("Creature ecology data is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_record_error("Unable to open creature ecology data: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		_record_error("Creature ecology root must be an object: %s" % path)
		return false
	var root_data: Dictionary = parsed
	var raw_profiles: Variant = root_data.get("profiles", [])
	if raw_profiles is not Array:
		_record_error("Creature ecology profiles must be an array")
		return false
	schema_version = int(root_data.get("schema_version", 0))
	if schema_version not in [1, 2]:
		_record_error("Unsupported creature ecology schema_version: %d" % schema_version)
	default_profile_id = str(root_data.get("default_profile", "star_continent")).strip_edges()
	var known_species: Dictionary = {}
	for raw_species_id: Variant in CreatureFactoryScript.SCRIPTS.keys():
		known_species[str(raw_species_id)] = true
	for raw_profile: Variant in raw_profiles:
		if raw_profile is not Dictionary:
			_record_error("Creature ecology profile entry must be an object")
			continue
		var normalized := _normalize_profile(raw_profile, known_species)
		var profile_id := str(normalized.get("id", ""))
		if not profile_id.is_empty():
			_profiles[profile_id] = normalized
	if _profiles.is_empty():
		_record_error("Creature ecology contains no valid profiles")
		return false
	if not _profiles.has(default_profile_id):
		_record_error("Unknown default creature ecology profile: %s" % default_profile_id)
		default_profile_id = get_profile_ids()[0]
	return _validation_errors.is_empty()


func get_profile(profile_id: String) -> Dictionary:
	var resolved_id := profile_id if _profiles.has(profile_id) else default_profile_id
	return _profiles.get(resolved_id, {}).duplicate(true)


func get_profile_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in _profiles.keys():
		result.append(str(raw_id))
	result.sort()
	return result


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func _normalize_profile(raw_profile: Dictionary, known_species: Dictionary) -> Dictionary:
	var profile_id := str(raw_profile.get("id", "")).strip_edges()
	if profile_id.is_empty():
		_record_error("Creature ecology profile id is empty")
		return {}
	if _profiles.has(profile_id):
		_record_error("Duplicate creature ecology profile: %s" % profile_id)
		return {}
	var passive_cap := clampi(int(raw_profile.get("passive_cap", 0)), 0, 64)
	var hostile_cap_day := clampi(int(raw_profile.get("hostile_cap_day", 0)), 0, 32)
	var hostile_cap_night := clampi(int(raw_profile.get("hostile_cap_night", 0)), 0, 32)
	if hostile_cap_night < hostile_cap_day:
		_record_error("Night hostile cap must not be below day cap: %s" % profile_id)
		return {}
	var passive_species := _normalize_species(
		raw_profile.get("passive_species", []), known_species, profile_id, "passive"
	)
	var hostile_species := _normalize_species(
		raw_profile.get("hostile_species", []), known_species, profile_id, "hostile"
	)
	if passive_cap > 0 and passive_species.is_empty():
		_record_error("Passive ecology has no species: %s" % profile_id)
		return {}
	if hostile_cap_night > 0 and hostile_species.is_empty():
		_record_error("Hostile ecology has no species: %s" % profile_id)
		return {}
	var chances := {"day":0.0, "dawn":0.0, "dusk":0.0, "night":0.0}
	var raw_chances: Variant = raw_profile.get("hostile_chance", {})
	if raw_chances is Dictionary:
		for phase: String in chances.keys():
			chances[phase] = clampf(float(raw_chances.get(phase, 0.0)), 0.0, 1.0)
	return {
		"id": profile_id,
		"name": str(raw_profile.get("name", profile_id)),
		"danger_base": clampi(int(raw_profile.get("danger_base", 0)), 0, 60),
		"spawn_interval_seconds": clampf(
			float(raw_profile.get("spawn_interval_seconds", 8.0)), 1.0, 30.0
		),
		"passive_cap": passive_cap,
		"hostile_cap_day": hostile_cap_day,
		"hostile_cap_night": hostile_cap_night,
		"hostile_chance": chances,
		"passive_species": passive_species,
		"hostile_species": hostile_species,
	}


func _normalize_species(
	raw_entries: Variant, known_species: Dictionary, profile_id: String, category: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw_entries is not Array:
		_record_error("%s species must be an array: %s" % [category, profile_id])
		return result
	var seen: Dictionary = {}
	for raw_entry: Variant in raw_entries:
		if raw_entry is not Dictionary:
			_record_error("%s species entry must be an object: %s" % [category, profile_id])
			continue
		var entry: Dictionary = raw_entry
		var species_id := str(entry.get("id", "")).strip_edges()
		var weight := int(entry.get("weight", 0))
		if not known_species.has(species_id):
			_record_error("Unknown %s species '%s' in %s" % [category, species_id, profile_id])
			continue
		if seen.has(species_id):
			_record_error("Duplicate %s species '%s' in %s" % [category, species_id, profile_id])
			continue
		if weight <= 0:
			_record_error("Species weight must be positive for %s in %s" % [species_id, profile_id])
			continue
		var cap := clampi(int(entry.get("cap", 0)), 0, 32)
		var condition_mode := str(entry.get("condition_mode", "all")).strip_edges()
		if condition_mode not in ["all", "any"]:
			_record_error("Unknown ecology condition mode '%s' for %s in %s" % [condition_mode, species_id, profile_id])
			continue
		var phase_ids: Array[String] = []
		var raw_phase_ids: Variant = entry.get("phase_ids", [])
		if raw_phase_ids is not Array:
			_record_error("Ecology phase_ids must be an array for %s in %s" % [species_id, profile_id])
			continue
		for raw_phase_id: Variant in raw_phase_ids:
			var phase_id := str(raw_phase_id).strip_edges()
			if phase_id not in PHASE_IDS:
				_record_error("Unknown ecology phase '%s' for %s in %s" % [phase_id, species_id, profile_id])
				continue
			if phase_id not in phase_ids:
				phase_ids.append(phase_id)
		var normalized := {
			"id": species_id,
			"weight": weight,
			"cap": cap,
			"condition_mode": condition_mode,
			"phase_ids": phase_ids,
		}
		if entry.has("min_player_y"):
			normalized["min_player_y"] = clampi(int(entry.get("min_player_y", 0)), -64, 128)
		if entry.has("max_player_y"):
			normalized["max_player_y"] = clampi(int(entry.get("max_player_y", 63)), -64, 128)
		if normalized.has("min_player_y") and normalized.has("max_player_y"):
			if int(normalized["max_player_y"]) < int(normalized["min_player_y"]):
				_record_error("Invalid player height condition for %s in %s" % [species_id, profile_id])
				continue
		seen[species_id] = true
		result.append(normalized)
	return result


func _install_fallback() -> void:
	schema_version = 2
	default_profile_id = "star_continent"
	_profiles = {
		"star_continent": {
			"id":"star_continent",
			"name":"Built-in balanced ecology",
			"danger_base":8,
			"spawn_interval_seconds":8.0,
			"passive_cap":12,
			"hostile_cap_day":0,
			"hostile_cap_night":2,
			"hostile_chance":{"day":0.0,"dawn":0.05,"dusk":0.25,"night":0.65},
			"passive_species":[
				{"id":"chicken","weight":1,"cap":0,"condition_mode":"all","phase_ids":[]},
				{"id":"cow","weight":1,"cap":0,"condition_mode":"all","phase_ids":[]},
				{"id":"pig","weight":1,"cap":0,"condition_mode":"all","phase_ids":[]},
			],
			"hostile_species":[
				{"id":"zombie","weight":1,"cap":0,"condition_mode":"all","phase_ids":[]}
			],
		}
	}


func _record_error(message: String) -> void:
	_validation_errors.append(message)
	push_warning(message)
