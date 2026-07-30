class_name HostileAttackRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/hostile_attacks.json"
const SUPPORTED_SCHEMA_VERSIONS: Array[int] = [1, 2]
const ALLOWED_ATTACK_KINDS: Array[String] = ["melee", "ranged"]
const ALLOWED_DELIVERY_KINDS: Array[String] = ["direct", "projectile"]
const ALLOWED_PROJECTILE_VISUALS: Array[String] = ["arrow", "bolt", "orb"]
const MAX_RANGED_ATTACK_RANGE := 32.0
const MAX_PROJECTILE_SPEED := 64.0
const MAX_PROJECTILE_DISTANCE := 64.0
const MAX_PROJECTILE_LIFETIME := 8.0
const MAX_COVER_PROBES := 8

var schema_version := 0
var _profiles: Dictionary = {}
var _validation_errors: Array[String] = []


func _init() -> void:
	if not load_from_file():
		_install_fallback()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	var errors: Array[String] = []
	if not FileAccess.file_exists(path):
		_errors_append(errors, "Hostile attack data is missing: %s" % path)
		_validation_errors = errors
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_errors_append(errors, "Unable to open hostile attack data: %s" % path)
		_validation_errors = errors
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		_errors_append(errors, "Hostile attack data must be an object: %s" % path)
		_validation_errors = errors
		return false
	var root_data: Dictionary = parsed
	var next_schema_version := int(root_data.get("schema_version", 0))
	if next_schema_version not in SUPPORTED_SCHEMA_VERSIONS:
		_errors_append(errors, "Unsupported hostile attack schema_version: %d" % next_schema_version)
	var raw_profiles: Variant = root_data.get("profiles", [])
	if raw_profiles is not Array:
		_errors_append(errors, "Hostile attack profiles must be an array")
		_validation_errors = errors
		return false
	var staged: Dictionary = {}
	for raw_profile: Variant in raw_profiles:
		if raw_profile is not Dictionary:
			_errors_append(errors, "Hostile attack profile must be an object")
			continue
		var normalized := _normalize_profile(raw_profile, next_schema_version, errors)
		var species_id := str(normalized.get("species_id", ""))
		if species_id.is_empty():
			continue
		if staged.has(species_id):
			_errors_append(errors, "Duplicate hostile attack profile: %s" % species_id)
			continue
		staged[species_id] = normalized
	if staged.is_empty():
		_errors_append(errors, "Hostile attack data contains no valid profiles")
	if not errors.is_empty():
		_validation_errors = errors.duplicate()
		return false
	_profiles = staged
	schema_version = next_schema_version
	_validation_errors.clear()
	return true


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


func _normalize_profile(
	raw_profile: Dictionary,
	data_schema_version: int,
	errors: Array[String]
) -> Dictionary:
	var species_id := str(raw_profile.get("species_id", "")).strip_edges()
	var source_id := str(raw_profile.get("source_id", species_id)).strip_edges()
	if species_id.is_empty() or source_id.is_empty():
		_errors_append(errors, "Hostile attack profile has empty species/source identity")
		return {}
	var attack_kind := str(raw_profile.get("attack_kind", "melee")).strip_edges()
	var delivery_kind := str(raw_profile.get("delivery_kind", "direct")).strip_edges()
	if attack_kind not in ALLOWED_ATTACK_KINDS or delivery_kind not in ALLOWED_DELIVERY_KINDS:
		_errors_append(errors, "Invalid hostile attack kind/delivery for %s" % species_id)
		return {}
	if attack_kind == "melee" and delivery_kind != "direct":
		_errors_append(errors, "Melee hostile attacks must use direct delivery: %s" % species_id)
		return {}
	if attack_kind == "ranged" and delivery_kind != "projectile":
		_errors_append(errors, "Ranged hostile attacks must use projectile delivery: %s" % species_id)
		return {}
	var detection_range := float(raw_profile.get("detection_range", 0.0))
	var attack_range := float(raw_profile.get("attack_range", 0.0))
	var minimum_range := float(raw_profile.get("minimum_range", 0.0))
	var preferred_range := float(raw_profile.get("preferred_range", attack_range))
	var windup_seconds := float(raw_profile.get("windup_seconds", 0.0))
	var cooldown_seconds := float(raw_profile.get("cooldown_seconds", 0.0))
	var cancel_range_multiplier := float(raw_profile.get("cancel_range_multiplier", 0.0))
	var cancel_recovery_seconds := float(raw_profile.get("cancel_recovery_seconds", 0.0))
	var target_leash_multiplier := float(raw_profile.get("target_leash_multiplier", 0.0))
	var telegraph_radius_multiplier := float(raw_profile.get("telegraph_radius_multiplier", 0.0))
	var max_attack_range := 6.0 if attack_kind == "melee" else MAX_RANGED_ATTACK_RANGE
	if attack_range < 0.25 or attack_range > max_attack_range:
		_errors_append(errors, "Invalid hostile attack range for %s" % species_id)
		return {}
	if detection_range <= attack_range or detection_range > 64.0:
		_errors_append(errors, "Detection range must exceed attack range for %s" % species_id)
		return {}
	if minimum_range < 0.0 or minimum_range >= attack_range:
		_errors_append(errors, "Invalid hostile minimum range for %s" % species_id)
		return {}
	if preferred_range < minimum_range or preferred_range > attack_range:
		_errors_append(errors, "Invalid hostile preferred range for %s" % species_id)
		return {}
	if windup_seconds < 0.1 or windup_seconds > 3.0:
		_errors_append(errors, "Invalid hostile attack windup for %s" % species_id)
		return {}
	if cooldown_seconds < 0.5 or cooldown_seconds > 30.0:
		_errors_append(errors, "Invalid hostile attack cooldown for %s" % species_id)
		return {}
	if cancel_range_multiplier < 1.0 or cancel_range_multiplier > 3.0:
		_errors_append(errors, "Invalid hostile attack cancel range for %s" % species_id)
		return {}
	if cancel_recovery_seconds < 0.0 or cancel_recovery_seconds > cooldown_seconds:
		_errors_append(errors, "Invalid hostile attack cancel recovery for %s" % species_id)
		return {}
	if target_leash_multiplier < 1.0 or target_leash_multiplier > 3.0:
		_errors_append(errors, "Invalid hostile target leash for %s" % species_id)
		return {}
	if telegraph_radius_multiplier < 0.5 or telegraph_radius_multiplier > 2.0:
		_errors_append(errors, "Invalid hostile telegraph radius for %s" % species_id)
		return {}
	var result := {
		"species_id": species_id,
		"source_id": source_id,
		"attack_kind": attack_kind,
		"delivery_kind": delivery_kind,
		"detection_range": detection_range,
		"minimum_range": minimum_range,
		"preferred_range": preferred_range,
		"attack_range": attack_range,
		"windup_seconds": windup_seconds,
		"cooldown_seconds": cooldown_seconds,
		"cancel_range_multiplier": cancel_range_multiplier,
		"cancel_recovery_seconds": cancel_recovery_seconds,
		"target_leash_multiplier": target_leash_multiplier,
		"telegraph_radius_multiplier": telegraph_radius_multiplier,
		"requires_line_of_sight": bool(raw_profile.get("requires_line_of_sight", false)),
		"cover_probe_count": 0,
	}
	if attack_kind == "melee":
		return result
	var projectile_speed := float(raw_profile.get("projectile_speed", 0.0))
	var projectile_gravity := float(raw_profile.get("projectile_gravity", 0.0))
	var projectile_distance := float(raw_profile.get("projectile_max_distance", 0.0))
	var projectile_lifetime := float(raw_profile.get("projectile_lifetime_seconds", 0.0))
	var projectile_collision_mask := int(raw_profile.get("projectile_collision_mask", 0))
	var knockback_horizontal := float(raw_profile.get("projectile_knockback_horizontal", 0.0))
	var knockback_vertical := float(raw_profile.get("projectile_knockback_vertical", 0.0))
	var hit_stun_seconds := float(raw_profile.get("projectile_hit_stun_seconds", 0.0))
	var visual_kind := str(raw_profile.get("projectile_visual_kind", "orb")).strip_edges()
	var visual_color := str(raw_profile.get("projectile_visual_color", "#D75BFF")).strip_edges()
	var cover_probe_count := int(raw_profile.get("cover_probe_count", 0))
	var cover_probe_radius := float(raw_profile.get("cover_probe_radius", 0.0))
	var cover_refresh_seconds := float(raw_profile.get("cover_refresh_seconds", 0.0))
	var strafe_seconds := float(raw_profile.get("strafe_seconds", 0.0))
	if projectile_speed <= 0.0 or projectile_speed > MAX_PROJECTILE_SPEED:
		_errors_append(errors, "Invalid hostile projectile speed for %s" % species_id)
		return {}
	if projectile_gravity < 0.0 or projectile_gravity > 32.0:
		_errors_append(errors, "Invalid hostile projectile gravity for %s" % species_id)
		return {}
	if projectile_distance < attack_range or projectile_distance > MAX_PROJECTILE_DISTANCE:
		_errors_append(errors, "Invalid hostile projectile distance for %s" % species_id)
		return {}
	if projectile_lifetime < 0.2 or projectile_lifetime > MAX_PROJECTILE_LIFETIME:
		_errors_append(errors, "Invalid hostile projectile lifetime for %s" % species_id)
		return {}
	if projectile_collision_mask <= 0:
		_errors_append(errors, "Invalid hostile projectile collision mask for %s" % species_id)
		return {}
	if knockback_horizontal < 0.0 or knockback_horizontal > 12.0:
		_errors_append(errors, "Invalid hostile projectile knockback for %s" % species_id)
		return {}
	if knockback_vertical < 0.0 or knockback_vertical > 4.0:
		_errors_append(errors, "Invalid hostile projectile vertical knockback for %s" % species_id)
		return {}
	if hit_stun_seconds < 0.0 or hit_stun_seconds > 2.0:
		_errors_append(errors, "Invalid hostile projectile hit stun for %s" % species_id)
		return {}
	if visual_kind not in ALLOWED_PROJECTILE_VISUALS or not Color.html_is_valid(visual_color):
		_errors_append(errors, "Invalid hostile projectile visual for %s" % species_id)
		return {}
	if cover_probe_count < 0 or cover_probe_count > MAX_COVER_PROBES:
		_errors_append(errors, "Hostile cover probe budget exceeded for %s" % species_id)
		return {}
	if cover_probe_count > 0 and (cover_probe_radius < 0.5 or cover_probe_radius > 6.0):
		_errors_append(errors, "Invalid hostile cover radius for %s" % species_id)
		return {}
	if cover_probe_count > 0 and (cover_refresh_seconds < 0.25 or cover_refresh_seconds > 3.0):
		_errors_append(errors, "Invalid hostile cover refresh for %s" % species_id)
		return {}
	if cover_probe_count > 0 and (strafe_seconds < 0.2 or strafe_seconds > 3.0):
		_errors_append(errors, "Invalid hostile strafe duration for %s" % species_id)
		return {}
	result.merge({
		"requires_line_of_sight": bool(raw_profile.get("requires_line_of_sight", true)),
		"projectile_speed": projectile_speed,
		"projectile_gravity": projectile_gravity,
		"projectile_max_distance": projectile_distance,
		"projectile_lifetime_seconds": projectile_lifetime,
		"projectile_collision_mask": projectile_collision_mask,
		"projectile_knockback_horizontal": knockback_horizontal,
		"projectile_knockback_vertical": knockback_vertical,
		"projectile_hit_stun_seconds": hit_stun_seconds,
		"projectile_visual_kind": visual_kind,
		"projectile_visual_color": visual_color,
		"cover_probe_count": cover_probe_count,
		"cover_probe_radius": cover_probe_radius,
		"cover_refresh_seconds": cover_refresh_seconds,
		"strafe_seconds": strafe_seconds,
	}, true)
	if data_schema_version == 1:
		result["requires_line_of_sight"] = false
	return result


func _install_fallback() -> void:
	schema_version = 2
	_profiles = {
		"zombie": _melee_fallback("zombie", 18.0, 1.65, 1.35, 0.8, 5.0, 0.6, 1.4, 1.05),
		"abyss_brute": _melee_fallback("abyss_brute", 20.0, 2.2, 1.8, 1.35, 7.0, 0.85, 1.35, 1.2),
		"abyss_marksman": {
			"species_id":"abyss_marksman", "source_id":"abyss_marksman",
			"attack_kind":"ranged", "delivery_kind":"projectile",
			"detection_range":30.0, "minimum_range":5.5, "preferred_range":13.0,
			"attack_range":24.0, "windup_seconds":1.1, "cooldown_seconds":4.8,
			"cancel_range_multiplier":1.12, "cancel_recovery_seconds":0.75,
			"target_leash_multiplier":1.35, "telegraph_radius_multiplier":1.0,
			"requires_line_of_sight":true, "projectile_speed":18.0,
			"projectile_gravity":0.8, "projectile_max_distance":28.0,
			"projectile_lifetime_seconds":2.2, "projectile_collision_mask":3,
			"projectile_knockback_horizontal":2.2, "projectile_knockback_vertical":0.18,
			"projectile_hit_stun_seconds":0.12, "projectile_visual_kind":"orb",
			"projectile_visual_color":"#D75BFF", "cover_probe_count":6,
			"cover_probe_radius":3.5, "cover_refresh_seconds":0.8, "strafe_seconds":1.2,
		},
	}


func _melee_fallback(
	species_id: String,
	detection: float,
	attack: float,
	preferred: float,
	windup: float,
	cooldown: float,
	cancel_recovery: float,
	leash: float,
	telegraph: float
) -> Dictionary:
	return {
		"species_id":species_id, "source_id":species_id,
		"attack_kind":"melee", "delivery_kind":"direct",
		"detection_range":detection, "minimum_range":0.0,
		"preferred_range":preferred, "attack_range":attack,
		"windup_seconds":windup, "cooldown_seconds":cooldown,
		"cancel_range_multiplier":1.35 if species_id == "zombie" else 1.25,
		"cancel_recovery_seconds":cancel_recovery,
		"target_leash_multiplier":leash,
		"telegraph_radius_multiplier":telegraph,
		"requires_line_of_sight":false, "cover_probe_count":0,
	}


func _errors_append(errors: Array[String], message: String) -> void:
	errors.append(message)
	push_warning(message)
