class_name RangedWeaponRegistry
extends RefCounted

const DEFAULT_DATA_PATHS: Array[String] = [
	"res://data/ranged_combat.json",
	"res://data/firearms.json",
]
const MAX_DRAW_SECONDS := 5.0
const MAX_PROJECTILE_SPEED := 96.0
const MAX_PROJECTILE_DISTANCE := 256.0
const MAX_PROJECTILE_LIFETIME := 12.0
const MIN_FIRE_INTERVAL_SECONDS := 0.06
const MAX_FIRE_INTERVAL_SECONDS := 3.0
const MAX_MAGAZINE_CAPACITY := 64
const MAX_RELOAD_SECONDS := 8.0
const MAX_HITSCAN_DISTANCE := 128.0
const MAX_PELLETS_PER_SHOT := 12
const MAX_SPREAD_DEGREES := 12.0
const MAX_DAMAGE_PER_PELLET := 24.0
const MAX_RAW_DAMAGE_PER_SHOT := 48.0
const MAX_RECOIL_DEGREES := 12.0
const ALLOWED_ACTION_KINDS: Array[String] = ["charge", "firearm"]
const ALLOWED_DELIVERY_KINDS: Array[String] = ["projectile", "hitscan"]
const ALLOWED_FIRE_MODES: Array[String] = ["semi", "auto", "pump"]

var schema_version := 0
var _profiles: Dictionary = {}


func load_from_file(path: String = "") -> bool:
	var source_paths: Array[String] = DEFAULT_DATA_PATHS.duplicate()
	if not path.strip_edges().is_empty():
		source_paths = [path]
	var staged: Dictionary = {}
	var staged_schema_version := 0
	for source_path: String in source_paths:
		var parsed: Dictionary = _read_source(source_path)
		if parsed.is_empty():
			return false
		staged_schema_version = maxi(
			staged_schema_version,
			maxi(1, int(parsed.get("schema_version", 1)))
		)
		var raw_profiles: Variant = parsed.get("profiles", [])
		if raw_profiles is not Array:
			push_error("Ranged combat profiles must be an array: %s" % source_path)
			return false
		for raw_profile: Variant in raw_profiles:
			if raw_profile is not Dictionary:
				push_error("Ranged combat profile is not a dictionary: %s" % source_path)
				return false
			var normalized: Dictionary = _normalize_profile(raw_profile)
			var profile_id := str(normalized.get("id", ""))
			if normalized.is_empty() or staged.has(profile_id):
				push_error("Invalid or duplicate ranged combat profile: %s" % profile_id)
				return false
			staged[profile_id] = normalized
	if staged.is_empty():
		push_error("Ranged combat registry has no profiles")
		return false
	_profiles = staged
	schema_version = staged_schema_version
	return true


func ensure_loaded() -> bool:
	return not _profiles.is_empty() or load_from_file()


func has_profile(weapon_item_id: String) -> bool:
	ensure_loaded()
	return _profiles.has(weapon_item_id)


func get_profile(weapon_item_id: String) -> Dictionary:
	ensure_loaded()
	return _profiles.get(weapon_item_id, {}).duplicate(true)


func get_profiles() -> Array:
	ensure_loaded()
	var ids: Array[String] = []
	for raw_id: Variant in _profiles.keys():
		ids.append(str(raw_id))
	ids.sort()
	var result: Array = []
	for profile_id: String in ids:
		result.append(get_profile(profile_id))
	return result


func profile_count() -> int:
	ensure_loaded()
	return _profiles.size()


func _normalize_profile(raw_profile: Dictionary) -> Dictionary:
	var profile_id := str(raw_profile.get("id", "")).strip_edges()
	var weapon_item_id := str(raw_profile.get("weapon_item_id", "")).strip_edges()
	var ammo_item_id := str(raw_profile.get("ammo_item_id", "")).strip_edges()
	var action_kind := str(raw_profile.get("action_kind", "charge")).strip_edges()
	var default_delivery := "projectile" if action_kind == "charge" else "hitscan"
	var delivery_kind := str(raw_profile.get("delivery_kind", default_delivery)).strip_edges()
	var durability_cost := int(raw_profile.get("durability_cost", 0))
	var collision_mask := int(raw_profile.get("collision_mask", 0))
	if (
		profile_id.is_empty()
		or weapon_item_id != profile_id
		or ammo_item_id.is_empty()
		or action_kind not in ALLOWED_ACTION_KINDS
		or delivery_kind not in ALLOWED_DELIVERY_KINDS
		or durability_cost <= 0
		or collision_mask <= 0
	):
		return {}
	var common := {
		"id": profile_id,
		"weapon_item_id": weapon_item_id,
		"ammo_item_id": ammo_item_id,
		"action_kind": action_kind,
		"delivery_kind": delivery_kind,
		"durability_cost": durability_cost,
		"collision_mask": collision_mask,
	}
	if action_kind == "charge":
		return _normalize_charge_profile(raw_profile, common)
	return _normalize_firearm_profile(raw_profile, common)


func _normalize_charge_profile(raw_profile: Dictionary, common: Dictionary) -> Dictionary:
	if str(common.get("delivery_kind", "")) != "projectile":
		return {}
	var draw_seconds := float(raw_profile.get("draw_seconds", 0.0))
	var minimum_draw_ratio := float(raw_profile.get("minimum_draw_ratio", -1.0))
	var minimum_damage := float(raw_profile.get("minimum_damage", -1.0))
	var maximum_damage := float(raw_profile.get("maximum_damage", -1.0))
	var minimum_speed := float(raw_profile.get("minimum_speed", -1.0))
	var maximum_speed := float(raw_profile.get("maximum_speed", -1.0))
	var gravity := float(raw_profile.get("gravity", -1.0))
	var max_distance := float(raw_profile.get("max_distance", 0.0))
	var max_lifetime := float(raw_profile.get("max_lifetime_seconds", 0.0))
	var cooldown_seconds := float(raw_profile.get("cooldown_seconds", 0.0))
	var knockback_horizontal := float(raw_profile.get("knockback_horizontal", -1.0))
	var knockback_vertical := float(raw_profile.get("knockback_vertical", -1.0))
	var hit_stun_seconds := float(raw_profile.get("hit_stun_seconds", -1.0))
	if (
		draw_seconds <= 0.0
		or draw_seconds > MAX_DRAW_SECONDS
		or minimum_draw_ratio < 0.0
		or minimum_draw_ratio >= 1.0
		or minimum_damage <= 0.0
		or maximum_damage < minimum_damage
		or minimum_speed <= 0.0
		or maximum_speed < minimum_speed
		or maximum_speed > MAX_PROJECTILE_SPEED
		or gravity < 0.0
		or max_distance <= 0.0
		or max_distance > MAX_PROJECTILE_DISTANCE
		or max_lifetime <= 0.0
		or max_lifetime > MAX_PROJECTILE_LIFETIME
		or cooldown_seconds <= 0.0
		or knockback_horizontal < 0.0
		or knockback_vertical < 0.0
		or hit_stun_seconds < 0.0
	):
		return {}
	var result := common.duplicate(true)
	result.merge(
		{
			"draw_seconds": draw_seconds,
			"minimum_draw_ratio": minimum_draw_ratio,
			"minimum_damage": minimum_damage,
			"maximum_damage": maximum_damage,
			"minimum_speed": minimum_speed,
			"maximum_speed": maximum_speed,
			"gravity": gravity,
			"max_distance": max_distance,
			"max_lifetime_seconds": max_lifetime,
			"cooldown_seconds": cooldown_seconds,
			"knockback_horizontal": knockback_horizontal,
			"knockback_vertical": knockback_vertical,
			"hit_stun_seconds": hit_stun_seconds,
		},
		true
	)
	return result


func _normalize_firearm_profile(raw_profile: Dictionary, common: Dictionary) -> Dictionary:
	if str(common.get("delivery_kind", "")) != "hitscan":
		return {}
	var fire_mode := str(raw_profile.get("fire_mode", "")).strip_edges()
	var magazine_capacity := int(raw_profile.get("magazine_capacity", 0))
	var reload_seconds := float(raw_profile.get("reload_seconds", 0.0))
	var fire_interval_seconds := float(raw_profile.get("fire_interval_seconds", 0.0))
	var pellet_count := int(raw_profile.get("pellet_count", 0))
	var spread_degrees := float(raw_profile.get("spread_degrees", -1.0))
	var damage_per_pellet := float(raw_profile.get("damage_per_pellet", 0.0))
	var max_distance := float(raw_profile.get("max_distance", 0.0))
	var knockback_horizontal := float(raw_profile.get("knockback_horizontal", -1.0))
	var knockback_vertical := float(raw_profile.get("knockback_vertical", -1.0))
	var hit_stun_seconds := float(raw_profile.get("hit_stun_seconds", -1.0))
	var recoil_pitch_degrees := float(raw_profile.get("recoil_pitch_degrees", -1.0))
	var recoil_yaw_degrees := float(raw_profile.get("recoil_yaw_degrees", -1.0))
	var total_raw_damage := damage_per_pellet * float(pellet_count)
	if (
		fire_mode not in ALLOWED_FIRE_MODES
		or magazine_capacity <= 0
		or magazine_capacity > MAX_MAGAZINE_CAPACITY
		or reload_seconds <= 0.0
		or reload_seconds > MAX_RELOAD_SECONDS
		or fire_interval_seconds < MIN_FIRE_INTERVAL_SECONDS
		or fire_interval_seconds > MAX_FIRE_INTERVAL_SECONDS
		or pellet_count <= 0
		or pellet_count > MAX_PELLETS_PER_SHOT
		or spread_degrees < 0.0
		or spread_degrees > MAX_SPREAD_DEGREES
		or damage_per_pellet <= 0.0
		or damage_per_pellet > MAX_DAMAGE_PER_PELLET
		or total_raw_damage > MAX_RAW_DAMAGE_PER_SHOT
		or max_distance <= 0.0
		or max_distance > MAX_HITSCAN_DISTANCE
		or knockback_horizontal < 0.0
		or knockback_vertical < 0.0
		or hit_stun_seconds < 0.0
		or recoil_pitch_degrees < 0.0
		or recoil_pitch_degrees > MAX_RECOIL_DEGREES
		or recoil_yaw_degrees < 0.0
		or recoil_yaw_degrees > MAX_RECOIL_DEGREES
	):
		return {}
	var result := common.duplicate(true)
	result.merge(
		{
			"fire_mode": fire_mode,
			"magazine_capacity": magazine_capacity,
			"reload_seconds": reload_seconds,
			"fire_interval_seconds": fire_interval_seconds,
			"pellet_count": pellet_count,
			"spread_degrees": spread_degrees,
			"damage_per_pellet": damage_per_pellet,
			"max_distance": max_distance,
			"knockback_horizontal": knockback_horizontal,
			"knockback_vertical": knockback_vertical,
			"hit_stun_seconds": hit_stun_seconds,
			"recoil_pitch_degrees": recoil_pitch_degrees,
			"recoil_yaw_degrees": recoil_yaw_degrees,
		},
		true
	)
	return result


func _read_source(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Ranged combat registry is missing: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open ranged combat registry: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("Invalid ranged combat registry JSON: %s" % path)
		return {}
	return parsed
