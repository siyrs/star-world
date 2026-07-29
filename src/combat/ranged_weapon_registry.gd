class_name RangedWeaponRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/ranged_combat.json"
const MAX_DRAW_SECONDS := 5.0
const MAX_PROJECTILE_SPEED := 96.0
const MAX_PROJECTILE_DISTANCE := 256.0
const MAX_PROJECTILE_LIFETIME := 12.0

var schema_version := 0
var _profiles: Dictionary = {}


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	var staged: Dictionary = {}
	if not FileAccess.file_exists(path):
		push_error("Ranged combat registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open ranged combat registry: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary or parsed.get("profiles", null) is not Array:
		push_error("Invalid ranged combat registry JSON: %s" % path)
		return false
	var next_schema_version := maxi(1, int(parsed.get("schema_version", 1)))
	for raw_profile: Variant in parsed.get("profiles", []):
		if raw_profile is not Dictionary:
			push_error("Ranged combat profile is not a dictionary")
			return false
		var normalized := _normalize_profile(raw_profile)
		var profile_id := str(normalized.get("id", ""))
		if normalized.is_empty() or staged.has(profile_id):
			push_error("Invalid or duplicate ranged combat profile: %s" % profile_id)
			return false
		staged[profile_id] = normalized
	if staged.is_empty():
		push_error("Ranged combat registry has no profiles")
		return false
	_profiles = staged
	schema_version = next_schema_version
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
	if profile_id.is_empty() or weapon_item_id != profile_id or ammo_item_id.is_empty():
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
	var durability_cost := int(raw_profile.get("durability_cost", 0))
	var collision_mask := int(raw_profile.get("collision_mask", 0))
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
		or durability_cost <= 0
		or collision_mask <= 0
	):
		return {}
	return {
		"id": profile_id,
		"weapon_item_id": weapon_item_id,
		"ammo_item_id": ammo_item_id,
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
		"durability_cost": durability_cost,
		"collision_mask": collision_mask,
	}
