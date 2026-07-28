class_name WorldDecorationRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/world_decoration_profiles.json"
const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const PolicyScript = preload("res://src/world/world_decoration_policy.gd")
const MAX_RULES_HARD_LIMIT := 16

var schema_version := 0
var default_profile_id := "star_continent"
var max_rules_per_profile := MAX_RULES_HARD_LIMIT
var _profiles: Dictionary = {}
var _validation_errors: Array[String] = []
var _loaded_from_file := false


func _init() -> void:
	if not load_from_file():
		_install_builtin_fallback()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_profiles.clear()
	_validation_errors.clear()
	schema_version = 0
	default_profile_id = "star_continent"
	max_rules_per_profile = MAX_RULES_HARD_LIMIT
	_loaded_from_file = false
	if not FileAccess.file_exists(path):
		_record_error("World decoration registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_record_error("Unable to open world decoration registry: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		_record_error("Invalid world decoration JSON root: %s" % path)
		return false
	var root_data: Dictionary = parsed
	schema_version = maxi(1, int(root_data.get("schema_version", 1)))
	default_profile_id = str(root_data.get("default_profile", "star_continent")).strip_edges()
	max_rules_per_profile = clampi(
		int(root_data.get("max_rules_per_profile", MAX_RULES_HARD_LIMIT)),
		1,
		MAX_RULES_HARD_LIMIT
	)
	var raw_profiles: Variant = root_data.get("profiles", [])
	if raw_profiles is not Array:
		_record_error("World decoration profiles must be an array: %s" % path)
		return false
	for raw_value: Variant in raw_profiles:
		if raw_value is not Dictionary:
			_record_error("World decoration profile entry must be an object")
			continue
		var normalized := _normalize_profile(raw_value)
		var profile_id := str(normalized.get("id", ""))
		if not profile_id.is_empty():
			_profiles[profile_id] = normalized
	if _profiles.is_empty():
		_record_error("World decoration registry contains no valid profiles")
		return false
	if default_profile_id.is_empty() or not _profiles.has(default_profile_id):
		_record_error("Unknown default world decoration profile: %s" % default_profile_id)
		default_profile_id = get_profile_ids()[0]
	_loaded_from_file = _validation_errors.is_empty()
	return _loaded_from_file


func get_profile(profile_id: String) -> Dictionary:
	var resolved_id := profile_id if _profiles.has(profile_id) else default_profile_id
	return (_profiles.get(resolved_id, {}) as Dictionary).duplicate(true)


func get_profile_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in _profiles.keys():
		result.append(str(raw_id))
	result.sort()
	return result


func get_summary(profile_id: String) -> String:
	return str(get_profile(profile_id).get("summary", ""))


func get_rule_ids(profile_id: String) -> Array[String]:
	var result: Array[String] = []
	var raw_rules: Variant = get_profile(profile_id).get("rules", [])
	if raw_rules is Array:
		for raw_rule: Variant in raw_rules:
			if raw_rule is Dictionary:
				result.append(str(raw_rule.get("id", "")))
	return result


func get_tree_exclusion_density(profile_id: String) -> int:
	return int(get_profile(profile_id).get("tree_exclusion_density", 0))


func get_snapshot(profile_id: String) -> Dictionary:
	var profile := get_profile(profile_id)
	var raw_rules: Variant = profile.get("rules", [])
	return {
		"schema_version": schema_version,
		"loaded_from_file": _loaded_from_file,
		"profile_id": str(profile.get("id", "")),
		"summary": str(profile.get("summary", "")),
		"rule_count": (raw_rules as Array).size() if raw_rules is Array else 0,
		"rule_budget": max_rules_per_profile,
		"rule_ids": get_rule_ids(profile_id),
		"validation_error_count": _validation_errors.size(),
	}


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func _normalize_profile(raw_profile: Dictionary) -> Dictionary:
	var profile_id := str(raw_profile.get("id", "")).strip_edges()
	if profile_id.is_empty():
		_record_error("World decoration profile id is empty")
		return {}
	if _profiles.has(profile_id):
		_record_error("Duplicate world decoration profile: %s" % profile_id)
		return {}
	var summary := str(raw_profile.get("summary", "")).strip_edges()
	if summary.is_empty():
		_record_error("World decoration summary is empty: %s" % profile_id)
		return {}
	var raw_rules: Variant = raw_profile.get("rules", [])
	if raw_rules is not Array:
		_record_error("World decoration rules must be an array: %s" % profile_id)
		return {}
	if raw_rules.size() > max_rules_per_profile:
		_record_error(
			"World decoration profile exceeds %d rules: %s"
			% [max_rules_per_profile, profile_id]
		)
		return {}
	var rules: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for raw_rule: Variant in raw_rules:
		if raw_rule is not Dictionary:
			_record_error("World decoration rule must be an object: %s" % profile_id)
			continue
		var normalized := _normalize_rule(profile_id, raw_rule)
		var rule_id := str(normalized.get("id", ""))
		if rule_id.is_empty():
			continue
		if seen_ids.has(rule_id):
			_record_error("Duplicate world decoration rule '%s': %s" % [rule_id, profile_id])
			continue
		seen_ids[rule_id] = true
		rules.append(normalized)
	if rules.is_empty():
		_record_error("World decoration profile has no valid rules: %s" % profile_id)
		return {}
	return {
		"id": profile_id,
		"name": str(raw_profile.get("name", profile_id)).strip_edges(),
		"summary": summary,
		"tree_exclusion_density": clampi(
			int(raw_profile.get("tree_exclusion_density", 0)),
			0,
			PolicyScript.ROLL_SCALE - 1
		),
		"rules": rules,
	}


func _normalize_rule(profile_id: String, raw_rule: Dictionary) -> Dictionary:
	var rule_id := str(raw_rule.get("id", "")).strip_edges()
	var rule_type := str(raw_rule.get("type", "")).strip_edges()
	var block_id := str(raw_rule.get("block_id", "")).strip_edges()
	if rule_id.is_empty():
		_record_error("World decoration rule id is empty: %s" % profile_id)
		return {}
	if rule_type not in PolicyScript.ALLOWED_RULE_TYPES:
		_record_error("Unknown world decoration rule type '%s': %s" % [rule_type, profile_id])
		return {}
	if not BlockRegistryScript.has_block(block_id):
		_record_error("Unknown decoration block '%s': %s" % [block_id, profile_id])
		return {}
	var normalized: Dictionary = {
		"id": rule_id,
		"type": rule_type,
		"block_id": block_id,
		"minimum_surface_y": clampi(int(raw_rule.get("minimum_surface_y", -1)), -1, 63),
		"minimum_sky_strength": clampf(float(raw_rule.get("minimum_sky_strength", -1.0)), -1.0, 1.0),
		"exclude_tree": bool(raw_rule.get("exclude_tree", false)),
	}
	match rule_type:
		"surface_roll":
			var minimum_roll := int(raw_rule.get("minimum_roll", 0))
			var maximum_roll := int(raw_rule.get("maximum_roll", 0))
			if minimum_roll < 0 or maximum_roll <= minimum_roll or maximum_roll > PolicyScript.ROLL_SCALE:
				_record_error("Invalid surface roll range for %s/%s" % [profile_id, rule_id])
				return {}
			normalized.merge({
				"surface_offset": clampi(int(raw_rule.get("surface_offset", 1)), 1, 4),
				"roll_salt": int(raw_rule.get("roll_salt", 0)),
				"minimum_roll": minimum_roll,
				"maximum_roll": maximum_roll,
			}, true)
		"column_roll":
			var maximum_roll := int(raw_rule.get("maximum_roll", 0))
			var minimum_height := int(raw_rule.get("minimum_height", 1))
			var maximum_height := int(raw_rule.get("maximum_height", minimum_height))
			if maximum_roll <= 0 or maximum_roll > PolicyScript.ROLL_SCALE:
				_record_error("Invalid column probability for %s/%s" % [profile_id, rule_id])
				return {}
			if minimum_height < 1 or maximum_height < minimum_height or maximum_height > 8:
				_record_error("Invalid column height for %s/%s" % [profile_id, rule_id])
				return {}
			normalized.merge({
				"roll_salt": int(raw_rule.get("roll_salt", 0)),
				"maximum_roll": maximum_roll,
				"height_roll_salt": int(raw_rule.get("height_roll_salt", 0)),
				"minimum_height": minimum_height,
				"maximum_height": maximum_height,
			}, true)
		"ruin_grid":
			if not _normalize_site_rule(profile_id, rule_id, raw_rule, normalized):
				return {}
			var minimum_height := int(raw_rule.get("minimum_height", 1))
			var maximum_height := int(raw_rule.get("maximum_height", minimum_height))
			var grid_spacing := int(raw_rule.get("grid_spacing", 1))
			if minimum_height < 1 or maximum_height < minimum_height or maximum_height > 8:
				_record_error("Invalid ruin height for %s/%s" % [profile_id, rule_id])
				return {}
			if grid_spacing < 1 or grid_spacing > 16:
				_record_error("Invalid ruin grid spacing for %s/%s" % [profile_id, rule_id])
				return {}
			normalized.merge({
				"grid_spacing": grid_spacing,
				"height_roll_salt": int(raw_rule.get("height_roll_salt", 0)),
				"minimum_height": minimum_height,
				"maximum_height": maximum_height,
			}, true)
		"ruin_debris":
			if not _normalize_site_rule(profile_id, rule_id, raw_rule, normalized):
				return {}
			var maximum_roll := int(raw_rule.get("maximum_roll", 0))
			if maximum_roll <= 0 or maximum_roll > PolicyScript.ROLL_SCALE:
				_record_error("Invalid ruin debris probability for %s/%s" % [profile_id, rule_id])
				return {}
			normalized.merge({
				"surface_offset": clampi(int(raw_rule.get("surface_offset", 1)), 1, 4),
				"roll_salt": int(raw_rule.get("roll_salt", 0)),
				"maximum_roll": maximum_roll,
			}, true)
	return normalized


func _normalize_site_rule(
	profile_id: String,
	rule_id: String,
	raw_rule: Dictionary,
	normalized: Dictionary
) -> bool:
	var cell_size := int(raw_rule.get("cell_size", 0))
	var site_minimum_roll := int(raw_rule.get("site_minimum_roll", PolicyScript.ROLL_SCALE))
	var offset_span := int(raw_rule.get("center_offset_span", 0))
	var local_radius := int(raw_rule.get("local_radius", 0))
	if cell_size < 16 or cell_size > 256:
		_record_error("Invalid POI cell size for %s/%s" % [profile_id, rule_id])
		return false
	if site_minimum_roll < 0 or site_minimum_roll >= PolicyScript.ROLL_SCALE:
		_record_error("Invalid POI activation threshold for %s/%s" % [profile_id, rule_id])
		return false
	if offset_span < 1 or offset_span > cell_size:
		_record_error("Invalid POI center span for %s/%s" % [profile_id, rule_id])
		return false
	if local_radius < 1 or local_radius > cell_size / 2:
		_record_error("Invalid POI local radius for %s/%s" % [profile_id, rule_id])
		return false
	normalized.merge({
		"cell_size": cell_size,
		"site_roll_salt": int(raw_rule.get("site_roll_salt", 0)),
		"site_minimum_roll": site_minimum_roll,
		"center_x_salt": int(raw_rule.get("center_x_salt", 0)),
		"center_z_salt": int(raw_rule.get("center_z_salt", 0)),
		"center_offset_span": offset_span,
		"local_radius": local_radius,
	}, true)
	return true


func _install_builtin_fallback() -> void:
	schema_version = 1
	default_profile_id = "star_continent"
	max_rules_per_profile = MAX_RULES_HARD_LIMIT
	_loaded_from_file = false
	_profiles = {
		"star_continent": _fallback_profile(
			"star_continent",
			"Built-in grassland decoration fallback.",
			185,
			[
				_surface_rule("grassland_tall_grass", "tall_grass", 911, 0, 600, 18, true),
				_surface_rule("grassland_red_flower", "flower_red", 911, 600, 680, 18, true),
				_surface_rule("grassland_yellow_flower", "flower_yellow", 911, 680, 740, 18, true),
			]
		),
		"desert_ruins": _fallback_profile(
			"desert_ruins",
			"Built-in desert decoration fallback.",
			0,
			[
				{
					"id":"desert_ruin_pillars", "type":"ruin_grid", "block_id":"ruin_pillar",
					"minimum_surface_y":-1, "minimum_sky_strength":-1.0, "exclude_tree":false,
					"cell_size":48, "site_roll_salt":971, "site_minimum_roll":4200,
					"center_x_salt":953, "center_z_salt":967, "center_offset_span":24,
					"local_radius":4, "grid_spacing":3, "height_roll_salt":983,
					"minimum_height":1, "maximum_height":4,
				},
				{
					"id":"desert_cactus", "type":"column_roll", "block_id":"cactus",
					"minimum_surface_y":-1, "minimum_sky_strength":-1.0, "exclude_tree":false,
					"roll_salt":937, "maximum_roll":90, "height_roll_salt":941,
					"minimum_height":1, "maximum_height":2,
				},
				{
					"id":"desert_ruin_debris", "type":"ruin_debris", "block_id":"ruin_pillar",
					"minimum_surface_y":-1, "minimum_sky_strength":-1.0, "exclude_tree":false,
					"surface_offset":1, "cell_size":48, "site_roll_salt":971,
					"site_minimum_roll":4200, "center_x_salt":953, "center_z_salt":967,
					"center_offset_span":24, "local_radius":9, "roll_salt":991,
					"maximum_roll":110,
				},
				_surface_rule("desert_dead_bush", "dead_bush", 977, 0, 150),
			]
		),
		"frozen_wastes": _fallback_profile(
			"frozen_wastes",
			"Built-in frozen decoration fallback.",
			0,
			[_surface_rule("frozen_dead_bush", "dead_bush", 983, 0, 60)]
		),
		"sky_islands": _fallback_profile(
			"sky_islands",
			"Built-in sky decoration fallback.",
			90,
			[
				_surface_rule("sky_tall_grass", "tall_grass", 907, 0, 500, -1, true, 0.35),
				_surface_rule("sky_yellow_flower", "flower_yellow", 907, 500, 580, -1, true, 0.35),
				_surface_rule("sky_red_flower", "flower_red", 907, 580, 640, -1, true, 0.35),
			]
		),
		"abyss_world": _fallback_profile(
			"abyss_world",
			"Built-in abyss decoration fallback.",
			0,
			[_surface_rule("abyss_glow_crystal", "glow_crystal", 991, 0, 130)]
		),
	}


func _fallback_profile(
	profile_id: String,
	summary: String,
	tree_density: int,
	rules: Array
) -> Dictionary:
	return {
		"id": profile_id,
		"name": profile_id,
		"summary": summary,
		"tree_exclusion_density": tree_density,
		"rules": rules,
	}


func _surface_rule(
	rule_id: String,
	block_id: String,
	salt: int,
	minimum_roll: int,
	maximum_roll: int,
	minimum_surface_y: int = -1,
	exclude_tree: bool = false,
	minimum_sky_strength: float = -1.0
) -> Dictionary:
	return {
		"id": rule_id,
		"type": "surface_roll",
		"block_id": block_id,
		"minimum_surface_y": minimum_surface_y,
		"minimum_sky_strength": minimum_sky_strength,
		"exclude_tree": exclude_tree,
		"surface_offset": 1,
		"roll_salt": salt,
		"minimum_roll": minimum_roll,
		"maximum_roll": maximum_roll,
	}


func _record_error(message: String) -> void:
	_validation_errors.append(message)
	push_warning(message)
