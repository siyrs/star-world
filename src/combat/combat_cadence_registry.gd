class_name CombatCadenceRegistry
extends RefCounted

const DATA_PATH := "res://data/combat_cadence.json"
const MIN_COOLDOWN_SECONDS := 0.10
const MAX_COOLDOWN_SECONDS := 3.00
const MAX_KNOCKBACK := 12.0
const MAX_HIT_STUN_SECONDS := 1.0

var _loaded := false
var _default_profile: Dictionary = {}
var _profiles: Dictionary = {}


func ensure_loaded() -> bool:
	return true if _loaded else load_from_file()


func load_from_file(path: String = DATA_PATH) -> bool:
	_loaded = false
	_default_profile.clear()
	_profiles.clear()
	if not FileAccess.file_exists(path):
		push_error("Combat cadence data not found: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Combat cadence data cannot be opened: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("Combat cadence data must be a JSON object")
		return false
	var root: Dictionary = parsed
	var raw_default: Variant = root.get("default_profile", {})
	if raw_default is not Dictionary:
		push_error("Combat cadence default_profile must be an object")
		return false
	_default_profile = _normalize_profile(raw_default, "unarmed")
	var raw_profiles: Variant = root.get("profiles", [])
	if raw_profiles is not Array:
		push_error("Combat cadence profiles must be an array")
		return false
	for raw_profile in raw_profiles:
		if raw_profile is not Dictionary:
			continue
		var item_id := str(raw_profile.get("item_id", "")).strip_edges()
		if item_id.is_empty() or _profiles.has(item_id):
			continue
		_profiles[item_id] = _normalize_profile(raw_profile, item_id)
	_loaded = not _default_profile.is_empty()
	return _loaded


func get_profile(item_id: String = "") -> Dictionary:
	ensure_loaded()
	var result := _default_profile.duplicate(true)
	var normalized_item_id := item_id.strip_edges()
	if not normalized_item_id.is_empty() and _profiles.has(normalized_item_id):
		result.merge(_profiles[normalized_item_id], true)
	result["item_id"] = normalized_item_id
	return result


func has_profile(item_id: String) -> bool:
	ensure_loaded()
	return _profiles.has(item_id)


func get_profile_count() -> int:
	ensure_loaded()
	return _profiles.size()


func get_snapshot() -> Dictionary:
	ensure_loaded()
	return {
		"default_profile": _default_profile.duplicate(true),
		"profiles": _profiles.duplicate(true),
	}


func _normalize_profile(raw: Dictionary, fallback_id: String) -> Dictionary:
	return {
		"id": str(raw.get("id", fallback_id)),
		"cooldown_seconds": clampf(
			float(raw.get("cooldown_seconds", 0.72)),
			MIN_COOLDOWN_SECONDS,
			MAX_COOLDOWN_SECONDS
		),
		"knockback_horizontal": clampf(
			float(raw.get("knockback_horizontal", 2.4)), 0.0, MAX_KNOCKBACK
		),
		"knockback_vertical": clampf(
			float(raw.get("knockback_vertical", 0.42)), 0.0, MAX_KNOCKBACK
		),
		"hit_stun_seconds": clampf(
			float(raw.get("hit_stun_seconds", 0.16)), 0.0, MAX_HIT_STUN_SECONDS
		),
	}
