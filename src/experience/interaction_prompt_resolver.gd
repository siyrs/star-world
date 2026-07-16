class_name InteractionPromptResolver
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")
const HarvestRegistryScript = preload("res://src/harvest/block_harvest_registry.gd")
const HarvestPolicyScript = preload("res://src/harvest/block_harvest_policy.gd")
const PlacementPreviewPolicyScript = preload(
	"res://src/interaction/placement_preview_policy.gd"
)

var _harvest_registry = HarvestRegistryScript.new()
var _harvest_policy = HarvestPolicyScript.new()


func resolve(
	focus: Dictionary,
	inventory: Node,
	interaction_service: Node,
	entity_interaction_service: Node = null
) -> Dictionary:
	var selected := _selected_item_context(inventory)
	var focus_type := str(focus.get("type", ""))
	match focus_type:
		"entity":
			return _entity_prompt(focus, selected, entity_interaction_service)
		"block":
			return _block_prompt(focus, selected, interaction_service)
		_:
			return _held_item_prompt(selected)


func _entity_prompt(
	focus: Dictionary, selected: Dictionary, entity_interaction_service: Node
) -> Dictionary:
	if (
		entity_interaction_service != null
		and entity_interaction_service.has_method("get_entity_prompt")
	):
		var custom_result: Variant = entity_interaction_service.call(
			"get_entity_prompt", focus, str(selected.get("item_id", ""))
		)
		if custom_result is Dictionary and not custom_result.is_empty():
			return custom_result.duplicate(true)
	var subtitle := "生物"
	if focus.has("health") and focus.has("max_health"):
		subtitle = "生命 %.0f / %.0f" % [
			float(focus.get("health", 0.0)), float(focus.get("max_health", 0.0))
		]
	return {
		"visible": true,
		"title": str(focus.get("display_name", "生物")),
		"subtitle": subtitle,
		"primary": "[鼠标左键] 攻击",
		"secondary": "",
		"tone": "warning",
	}


func _block_prompt(
	focus: Dictionary, selected: Dictionary, interaction_service: Node
) -> Dictionary:
	var block_id := str(focus.get("block_id", ""))
	var profile: Dictionary = _harvest_registry.get_profile(block_id)
	var evaluation: Dictionary = _harvest_policy.evaluate(profile, selected)
	var breakable := bool(evaluation.get("breakable", false))
	var primary := "[按住鼠标左键] 采集" if breakable else ""
	var secondary := ""
	var has_interaction_hint := false
	if interaction_service != null:
		var interaction_hint := ""
		if interaction_service.has_method("get_interaction_hint_for_item"):
			interaction_hint = str(
				interaction_service.call(
					"get_interaction_hint_for_item",
					block_id,
					str(selected.get("item_id", ""))
				)
			)
		elif interaction_service.has_method("get_interaction_hint"):
			interaction_hint = str(interaction_service.call("get_interaction_hint", block_id))
		if not interaction_hint.is_empty():
			secondary = "[鼠标右键] %s" % interaction_hint.trim_prefix("右键")
			has_interaction_hint = true
	if secondary.is_empty():
		secondary = _placement_use_hint(focus, selected)
	if secondary.is_empty():
		secondary = _selected_use_hint(selected)
	var subtitle := _harvest_subtitle(evaluation, selected)
	var tone := "info" if bool(evaluation.get("can_drop", false)) else "warning"
	if not has_interaction_hint and not str(selected.get("block_id", "")).is_empty():
		var placement_status := _placement_status(focus)
		if not placement_status.is_empty():
			subtitle = placement_status
			var preview: Dictionary = focus.get("placement_preview", {})
			tone = "info" if bool(preview.get("valid", false)) else "warning"
	return {
		"visible": breakable or not secondary.is_empty() or not profile.is_empty(),
		"title": str(focus.get("display_name", block_id)),
		"subtitle": subtitle,
		"primary": primary,
		"secondary": secondary,
		"tone": tone,
	}


func _harvest_subtitle(evaluation: Dictionary, selected: Dictionary) -> String:
	if not bool(evaluation.get("breakable", false)):
		return "无法破坏"
	var duration := float(evaluation.get("duration_seconds", 0.0))
	var preferred := str(evaluation.get("preferred_tool", ""))
	var required := str(evaluation.get("required_tool", ""))
	if not bool(evaluation.get("can_drop", false)):
		var minimum := int(evaluation.get("minimum_power", 0))
		var requirement := HarvestPolicyScript.tool_type_label(required)
		if minimum > 0:
			requirement = "至少%s%s" % [
				HarvestPolicyScript.power_label(minimum), requirement
			]
		return "%s才能获得掉落 · 当前约 %.1f 秒" % [requirement, duration]
	if not preferred.is_empty() and not bool(evaluation.get("matches_preferred", false)):
		return "推荐使用%s · 当前约 %.1f 秒" % [
			HarvestPolicyScript.tool_type_label(preferred), duration
		]
	var tool_name := str(selected.get("display_name", "空手"))
	return "%s · 约 %.1f 秒" % [tool_name, duration]


func _placement_use_hint(focus: Dictionary, selected: Dictionary) -> String:
	if str(selected.get("block_id", "")).is_empty():
		return ""
	var preview: Dictionary = focus.get("placement_preview", {})
	if preview.is_empty() or not bool(preview.get("placement_visible", false)):
		return "瞄准一个可用方块表面"
	if bool(preview.get("valid", false)):
		return "[鼠标右键] 放置 %s" % str(selected.get("display_name", "方块"))
	return "无法放置：%s" % _placement_reason_text(preview)


func _placement_status(focus: Dictionary) -> String:
	var preview: Dictionary = focus.get("placement_preview", {})
	if preview.is_empty() or not bool(preview.get("placement_visible", false)):
		return "瞄准一个可用方块表面"
	if not bool(preview.get("valid", false)):
		return _placement_reason_text(preview)
	var position: Variant = preview.get("placement_position", [])
	if position is Array and position.size() >= 3:
		return "绿色预览格  %d, %d, %d · 可以放置" % [
			int(position[0]), int(position[1]), int(position[2])
		]
	return "绿色预览格 · 可以放置"


func _placement_reason_text(preview: Dictionary) -> String:
	var occupied_id := str(preview.get("occupied_block_id", ""))
	var occupied_name := ""
	if not occupied_id.is_empty() and occupied_id != BlockRegistryScript.AIR:
		occupied_name = str(
			BlockRegistryScript.get_definition(occupied_id).get("name", occupied_id)
		)
	return PlacementPreviewPolicyScript.reason_text(
		str(preview.get("reason", "placement_unavailable")), occupied_name
	)


func _held_item_prompt(selected: Dictionary) -> Dictionary:
	if not str(selected.get("block_id", "")).is_empty():
		return {
			"visible": true,
			"title": str(selected.get("display_name", "选中方块")),
			"subtitle": "先把准星移到方块表面",
			"primary": "",
			"secondary": "出现绿色预览格后按鼠标右键放置",
			"tone": "warning",
		}
	var use_hint := _selected_use_hint(selected)
	if use_hint.is_empty():
		return {}
	return {
		"visible": true,
		"title": str(selected.get("display_name", "选中物品")),
		"subtitle": "瞄准一个合适的位置",
		"primary": "",
		"secondary": use_hint,
		"tone": "info",
	}


func _selected_use_hint(selected: Dictionary) -> String:
	if not str(selected.get("block_id", "")).is_empty():
		return "[鼠标右键] 放置 %s" % str(selected.get("display_name", "方块"))
	if bool(selected.get("is_food", false)):
		return "[鼠标右键] 食用 %s" % str(selected.get("display_name", "食物"))
	return ""


func _selected_item_context(inventory: Node) -> Dictionary:
	var hand := {
		"item_id": "",
		"display_name": "空手",
		"block_id": "",
		"is_food": false,
		"tool_type": "hand",
		"power": 0,
		"mining_speed": 1.0,
		"is_durable": false,
	}
	if inventory == null or not inventory.has_method("get_selected_item"):
		return hand
	var slot: Dictionary = inventory.call("get_selected_item")
	var item_id := str(slot.get("item_id", ""))
	if item_id.is_empty():
		return hand
	var registry = inventory.get("registry")
	var definition: Dictionary = {}
	var display_name := item_id
	if registry != null:
		if registry.has_method("get_item"):
			definition = registry.call("get_item", item_id)
		if registry.has_method("get_display_name"):
			display_name = str(registry.call("get_display_name", item_id))
	var block_id := BlockRegistryScript.get_block_for_item(item_id)
	return {
		"item_id": item_id,
		"display_name": display_name,
		"block_id": block_id if block_id != BlockRegistryScript.AIR else "",
		"is_food": definition.has("food"),
		"tool_type": str(definition.get("tool_type", "hand")),
		"power": maxi(0, int(definition.get("power", 0))),
		"mining_speed": maxf(0.1, float(definition.get("mining_speed", 1.0))),
		"is_durable": int(definition.get("durability", 0)) > 0,
	}
