class_name BlockHarvestRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/block_harvest.json"
const BlockRegistryScript = preload("res://src/block/block_registry.gd")

var schema_version := 0
var _rules: Dictionary = {}


func _init() -> void:
	load_from_file()


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_rules.clear()
	if not FileAccess.file_exists(path):
		push_error("Block harvest registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open block harvest registry: %s" % path)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary or parsed.get("rules") is not Array:
		push_error("Invalid block harvest registry: %s" % path)
		return false
	schema_version = int(parsed.get("schema_version", 1))
	for raw_rule in parsed["rules"]:
		if raw_rule is not Dictionary:
			continue
		var block_id := str(raw_rule.get("block_id", ""))
		if block_id.is_empty() or not BlockRegistryScript.has_block(block_id):
			continue
		_rules[block_id] = raw_rule.duplicate(true)
	return true


func get_profile(block_id: String) -> Dictionary:
	if not BlockRegistryScript.has_block(block_id):
		return {}
	var definition := BlockRegistryScript.get_definition(block_id)
	var rule: Dictionary = _rules.get(block_id, {})
	if rule.is_empty():
		var parent_id := str(
			definition.get("harvest_parent", definition.get("visual_parent", ""))
		)
		if not parent_id.is_empty():
			rule = _rules.get(parent_id, {})
	var hardness := float(definition.get("hardness", 0.0))
	var default_breakable := (
		block_id != BlockRegistryScript.AIR
		and hardness >= 0.0
		and block_id not in ["water", "lava"]
	)
	return {
		"block_id": block_id,
		"display_name": str(definition.get("name", block_id)),
		"hardness": maxf(0.0, hardness),
		"breakable": bool(rule.get("breakable", default_breakable)),
		"collectible": BlockRegistryScript.is_collectible(block_id),
		"preferred_tool": str(rule.get("preferred_tool", "")),
		"required_tool": str(rule.get("required_tool", "")),
		"minimum_power": maxi(0, int(rule.get("minimum_power", 0))),
		"drop_requires_tool": bool(rule.get("drop_requires_tool", false)),
		"drop_item": str(rule.get("drop_item", BlockRegistryScript.get_item_id(block_id))),
		"drop_count": maxi(0, int(rule.get("drop_count", 1))),
		"wrong_tool_speed_multiplier": clampf(
			float(rule.get("wrong_tool_speed_multiplier", 0.4)), 0.05, 1.0
		),
	}


func get_rule(block_id: String) -> Dictionary:
	return _rules.get(block_id, {}).duplicate(true)


func rule_count() -> int:
	return _rules.size()
