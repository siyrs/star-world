class_name ExplorationMilestoneRewardRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/exploration_milestone_rewards.json"
const ItemRegistryScript = preload("res://src/inventory/item_registry.gd")
const JournalRegistryScript = preload("res://src/exploration/exploration_journal_registry.gd")
const PROFILE_IDS: Array[String] = [
	"star_continent",
	"desert_ruins",
	"frozen_wastes",
	"sky_islands",
	"abyss_world",
]

var schema_version := 0
var item_registry = ItemRegistryScript.new()
var journal_registry = JournalRegistryScript.new()
var _rewards: Dictionary = {}
var _reward_order: Array[String] = []
var _validation_errors: Array[String] = []


func _init() -> void:
	item_registry.load_from_file()
	if not load_from_file():
		_install_fallback()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	schema_version = 0
	_rewards.clear()
	_reward_order.clear()
	_validation_errors.clear()
	if not FileAccess.file_exists(path):
		_record_error("Exploration reward data is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_record_error("Unable to open exploration reward data: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		_record_error("Exploration reward data must be an object: %s" % path)
		return false
	var data: Dictionary = parsed
	schema_version = int(data.get("schema_version", 0))
	if schema_version != 1:
		_record_error("Unsupported exploration reward schema_version: %d" % schema_version)
	var milestone_ids: Dictionary = {}
	for milestone: Dictionary in journal_registry.get_milestones():
		milestone_ids[str(milestone.get("id", ""))] = true
	var raw_rewards: Variant = data.get("rewards", [])
	if raw_rewards is not Array:
		_record_error("Exploration rewards must be an array")
		return false
	for raw_reward: Variant in raw_rewards:
		if raw_reward is not Dictionary:
			_record_error("Exploration reward entry must be an object")
			continue
		var reward: Dictionary = raw_reward
		var milestone_id := str(reward.get("milestone_id", "")).strip_edges()
		var description := str(reward.get("description", "")).strip_edges()
		if milestone_id.is_empty() or description.is_empty():
			_record_error("Exploration reward has empty milestone identity or description")
			continue
		if _rewards.has(milestone_id):
			_record_error("Duplicate exploration reward: %s" % milestone_id)
			continue
		if not milestone_ids.has(milestone_id):
			_record_error("Exploration reward references unknown milestone: %s" % milestone_id)
			continue
		var items := _normalize_items(reward.get("items", []), milestone_id)
		if items.is_empty():
			_record_error("Exploration reward contains no valid items: %s" % milestone_id)
			continue
		var profile_bonus: Dictionary = {}
		var raw_profile_bonus: Variant = reward.get("profile_bonus", {})
		if raw_profile_bonus is Dictionary:
			for raw_profile_id: Variant in raw_profile_bonus.keys():
				var profile_id := str(raw_profile_id).strip_edges()
				if profile_id not in PROFILE_IDS:
					_record_error("Exploration reward has unknown map profile '%s': %s" % [profile_id, milestone_id])
					continue
				var bonus_items := _normalize_items(raw_profile_bonus[raw_profile_id], "%s/%s" % [milestone_id, profile_id])
				if bonus_items.is_empty():
					_record_error("Exploration reward map bonus is empty: %s/%s" % [milestone_id, profile_id])
					continue
				profile_bonus[profile_id] = bonus_items
		var normalized := {
			"milestone_id": milestone_id,
			"description": description,
			"items": items,
			"profile_bonus": profile_bonus,
		}
		_rewards[milestone_id] = normalized
		_reward_order.append(milestone_id)
	for milestone_id: String in milestone_ids.keys():
		if not _rewards.has(milestone_id):
			_record_error("Exploration milestone has no reward: %s" % milestone_id)
	return _validation_errors.is_empty()


func get_reward_ids() -> Array[String]:
	return _reward_order.duplicate()


func has_reward(milestone_id: String) -> bool:
	return _rewards.has(milestone_id)


func get_reward(milestone_id: String, profile_id: String = "star_continent") -> Dictionary:
	var raw_reward: Variant = _rewards.get(milestone_id, {})
	if raw_reward is not Dictionary:
		return {}
	var reward: Dictionary = raw_reward
	var items: Array = reward.get("items", []).duplicate(true)
	var profile_bonus: Dictionary = reward.get("profile_bonus", {})
	var raw_bonus: Variant = profile_bonus.get(profile_id, [])
	if raw_bonus is Array:
		for raw_item: Variant in raw_bonus:
			if raw_item is Dictionary:
				items.append(raw_item.duplicate(true))
	items = _combine_items(items)
	return {
		"milestone_id": milestone_id,
		"description": str(reward.get("description", "")),
		"profile_id": profile_id,
		"items": items,
		"reward_label": describe_items(items),
		"has_profile_bonus": profile_bonus.has(profile_id),
	}


func describe_items(items: Array) -> String:
	var parts: Array[String] = []
	for raw_item: Variant in items:
		if raw_item is not Dictionary:
			continue
		var item: Dictionary = raw_item
		var item_id := str(item.get("item_id", ""))
		var count := int(item.get("count", 0))
		if item_id.is_empty() or count <= 0:
			continue
		parts.append("%s ×%d" % [item_registry.get_display_name(item_id), count])
	return "、".join(parts)


func get_validation_errors() -> Array[String]:
	return _validation_errors.duplicate()


func _normalize_items(raw_items: Variant, context: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw_items is not Array:
		_record_error("Exploration reward items must be an array: %s" % context)
		return result
	for raw_item: Variant in raw_items:
		if raw_item is not Dictionary:
			_record_error("Exploration reward item must be an object: %s" % context)
			continue
		var item: Dictionary = raw_item
		var item_id := str(item.get("item_id", item.get("id", ""))).strip_edges()
		var count := int(item.get("count", 0))
		if not item_registry.has_item(item_id):
			_record_error("Exploration reward references unknown item '%s': %s" % [item_id, context])
			continue
		if count < 1 or count > 256:
			_record_error("Exploration reward has invalid item count for %s: %s" % [item_id, context])
			continue
		var raw_metadata: Variant = item.get("metadata", {})
		var metadata: Dictionary = raw_metadata.duplicate(true) if raw_metadata is Dictionary else {}
		result.append({"item_id": item_id, "count": count, "metadata": metadata})
	return _combine_items(result)


func _combine_items(items: Array) -> Array[Dictionary]:
	var order: Array[String] = []
	var combined: Dictionary = {}
	for raw_item: Variant in items:
		if raw_item is not Dictionary:
			continue
		var item: Dictionary = raw_item
		var item_id := str(item.get("item_id", ""))
		var metadata: Dictionary = item.get("metadata", {})
		var key := "%s|%s" % [item_id, JSON.stringify(metadata)]
		if not combined.has(key):
			combined[key] = {
				"item_id": item_id,
				"count": 0,
				"metadata": metadata.duplicate(true),
			}
			order.append(key)
		var entry: Dictionary = combined[key]
		entry["count"] = int(entry.get("count", 0)) + int(item.get("count", 0))
		combined[key] = entry
	var result: Array[Dictionary] = []
	for key: String in order:
		result.append(combined[key].duplicate(true))
	return result


func _install_fallback() -> void:
	schema_version = 1
	_rewards = {
		"first_discovery": {
			"milestone_id":"first_discovery",
			"description":"完成第一份区域勘探后领取基础补给。",
			"items":[{"item_id":"torch", "count":4, "metadata":{}}],
			"profile_bonus":{},
		},
		"three_regions": {
			"milestone_id":"three_regions",
			"description":"踏勘三个区块后领取铁锭。",
			"items":[{"item_id":"iron_ingot", "count":2, "metadata":{}}],
			"profile_bonus":{},
		},
	}
	_reward_order = ["first_discovery", "three_regions"]


func _record_error(message: String) -> void:
	_validation_errors.append(message)
	push_warning(message)
