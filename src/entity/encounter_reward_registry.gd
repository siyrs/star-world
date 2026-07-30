class_name EncounterRewardRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/encounter_rewards.json"
const SUPPORTED_SCHEMA_VERSIONS: Array[int] = [1]
const ALLOWED_REWARD_ITEMS: Array[String] = [
	"arrow",
	"gunpowder",
	"light_round",
	"shotgun_shell",
]
const MAX_PROFILES := 16
const MAX_REWARD_TYPES := 4
const MAX_REWARD_PER_ITEM := 8
const MAX_TOTAL_REWARD_QUANTITY := 16
const MAX_EFFICIENT_SHOT_LIMIT := 16

var schema_version := 0
var _profiles: Dictionary = {}
var _validation_errors: Array[String] = []


func _init() -> void:
	if not load_from_file():
		_install_fallback()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	var errors: Array[String] = []
	if not FileAccess.file_exists(path):
		errors.append("Encounter reward data is missing: %s" % path)
		_validation_errors = errors
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Unable to open encounter reward data: %s" % path)
		_validation_errors = errors
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		errors.append("Encounter reward data must be an object")
		_validation_errors = errors
		return false
	var root_data: Dictionary = parsed
	var next_schema_version := int(root_data.get("schema_version", 0))
	if next_schema_version not in SUPPORTED_SCHEMA_VERSIONS:
		errors.append(
			"Unsupported encounter reward schema_version: %d" % next_schema_version
		)
	var raw_profiles: Variant = root_data.get("profiles", [])
	if raw_profiles is not Array:
		errors.append("Encounter reward profiles must be an array")
		_validation_errors = errors
		return false
	if raw_profiles.size() > MAX_PROFILES:
		errors.append("Encounter reward profile count exceeds %d" % MAX_PROFILES)
	var staged: Dictionary = {}
	for raw_profile: Variant in raw_profiles:
		if raw_profile is not Dictionary:
			errors.append("Encounter reward profile must be an object")
			continue
		var normalized := _normalize_profile(raw_profile, errors)
		var profile_id := str(normalized.get("encounter_profile_id", ""))
		if profile_id.is_empty():
			continue
		if staged.has(profile_id):
			errors.append("Duplicate encounter reward profile: %s" % profile_id)
			continue
		staged[profile_id] = normalized
	if staged.is_empty():
		errors.append("Encounter reward data contains no valid profiles")
	if not errors.is_empty():
		_validation_errors = errors.duplicate()
		return false
	_profiles = staged
	schema_version = next_schema_version
	_validation_errors.clear()
	return true


func get_profile(encounter_profile_id: String) -> Dictionary:
	var raw_profile: Variant = _profiles.get(encounter_profile_id, {})
	return raw_profile.duplicate(true) if raw_profile is Dictionary else {}


func get_profile_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id: Variant in _profiles.keys():
		result.append(str(raw_id))
	result.sort()
	return result


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func build_reward(encounter_profile_id: String, shot_count: int) -> Dictionary:
	var profile := get_profile(encounter_profile_id)
	if profile.is_empty():
		return {}
	var rewards: Dictionary = profile.get("base_rewards", {}).duplicate(true)
	var efficient_limit := int(profile.get("efficient_shot_limit", 0))
	var efficient := efficient_limit > 0 and maxi(0, shot_count) <= efficient_limit
	if efficient:
		for raw_item_id: Variant in profile.get("efficient_bonus", {}).keys():
			var item_id := str(raw_item_id)
			rewards[item_id] = int(rewards.get(item_id, 0)) + int(
				profile.get("efficient_bonus", {}).get(raw_item_id, 0)
			)
	return {
		"encounter_profile_id": encounter_profile_id,
		"display_name": str(profile.get("display_name", "遭遇补给")),
		"rewards": rewards,
		"efficient": efficient,
		"efficient_shot_limit": efficient_limit,
		"shot_count": maxi(0, shot_count),
	}


func _normalize_profile(raw_profile: Dictionary, errors: Array[String]) -> Dictionary:
	var profile_id := str(raw_profile.get("encounter_profile_id", "")).strip_edges()
	var display_name := str(raw_profile.get("display_name", "")).strip_edges()
	if profile_id.is_empty() or profile_id.length() > 64:
		errors.append("Encounter reward profile has an invalid identity")
		return {}
	if display_name.is_empty() or display_name.length() > 40:
		errors.append("Encounter reward profile has an invalid display name: %s" % profile_id)
		return {}
	var base_rewards := _normalize_reward_map(
		raw_profile.get("base_rewards", {}),
		"base_rewards",
		profile_id,
		errors
	)
	var efficient_bonus := _normalize_reward_map(
		raw_profile.get("efficient_bonus", {}),
		"efficient_bonus",
		profile_id,
		errors
	)
	var efficient_shot_limit := int(raw_profile.get("efficient_shot_limit", 0))
	if efficient_shot_limit < 0 or efficient_shot_limit > MAX_EFFICIENT_SHOT_LIMIT:
		errors.append("Encounter reward efficiency limit is invalid: %s" % profile_id)
		return {}
	if base_rewards.is_empty():
		errors.append("Encounter reward profile has no base rewards: %s" % profile_id)
		return {}
	var total_quantity := _reward_total(base_rewards) + _reward_total(efficient_bonus)
	if total_quantity > MAX_TOTAL_REWARD_QUANTITY:
		errors.append("Encounter reward quantity exceeds %d: %s" % [MAX_TOTAL_REWARD_QUANTITY, profile_id])
		return {}
	return {
		"encounter_profile_id": profile_id,
		"display_name": display_name,
		"base_rewards": base_rewards,
		"efficient_shot_limit": efficient_shot_limit,
		"efficient_bonus": efficient_bonus,
		"maximum_total_reward_quantity": total_quantity,
	}


func _normalize_reward_map(
	raw_rewards: Variant,
	field_name: String,
	profile_id: String,
	errors: Array[String]
) -> Dictionary:
	if raw_rewards is not Dictionary:
		errors.append("Encounter reward %s must be an object: %s" % [field_name, profile_id])
		return {}
	if raw_rewards.size() > MAX_REWARD_TYPES:
		errors.append("Encounter reward %s exceeds %d item types: %s" % [field_name, MAX_REWARD_TYPES, profile_id])
		return {}
	var normalized: Dictionary = {}
	for raw_item_id: Variant in raw_rewards.keys():
		var item_id := str(raw_item_id).strip_edges()
		var quantity := int(raw_rewards.get(raw_item_id, 0))
		if item_id not in ALLOWED_REWARD_ITEMS:
			errors.append("Encounter reward contains unsupported item %s: %s" % [item_id, profile_id])
			continue
		if quantity <= 0 or quantity > MAX_REWARD_PER_ITEM:
			errors.append("Encounter reward quantity is invalid for %s: %s" % [item_id, profile_id])
			continue
		normalized[item_id] = quantity
	return normalized


func _reward_total(rewards: Dictionary) -> int:
	var total := 0
	for raw_quantity: Variant in rewards.values():
		total += maxi(0, int(raw_quantity))
	return total


func _install_fallback() -> void:
	_profiles = {
		"continent_night_patrol": {
			"encounter_profile_id":"continent_night_patrol",
			"display_name":"夜行巡猎补给",
			"base_rewards":{"light_round":1},
			"efficient_shot_limit":3,
			"efficient_bonus":{"light_round":1},
			"maximum_total_reward_quantity":2,
		},
		"abyss_skirmish": {
			"encounter_profile_id":"abyss_skirmish",
			"display_name":"深渊游猎补给",
			"base_rewards":{"gunpowder":1, "light_round":3},
			"efficient_shot_limit":5,
			"efficient_bonus":{"light_round":2},
			"maximum_total_reward_quantity":6,
		},
		"abyss_assault": {
			"encounter_profile_id":"abyss_assault",
			"display_name":"深渊突袭补给",
			"base_rewards":{"gunpowder":2, "light_round":4, "shotgun_shell":1},
			"efficient_shot_limit":7,
			"efficient_bonus":{"light_round":2},
			"maximum_total_reward_quantity":9,
		},
	}
	schema_version = 1
