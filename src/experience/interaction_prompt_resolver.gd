class_name InteractionPromptResolver
extends RefCounted

const BlockRegistryScript = preload("res://src/block/block_registry.gd")


func resolve(focus: Dictionary, inventory: Node, interaction_service: Node) -> Dictionary:
	var selected := _selected_item_context(inventory)
	var focus_type := str(focus.get("type", ""))
	match focus_type:
		"entity":
			return _entity_prompt(focus)
		"block":
			return _block_prompt(focus, selected, interaction_service)
		_:
			return _held_item_prompt(selected)


func _entity_prompt(focus: Dictionary) -> Dictionary:
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
	var primary := ""
	if bool(focus.get("collectible", false)):
		primary = "[鼠标左键] 采集"
	var secondary := ""
	if interaction_service != null and interaction_service.has_method("get_interaction_hint"):
		var interaction_hint := str(interaction_service.call("get_interaction_hint", block_id))
		if not interaction_hint.is_empty():
			secondary = "[鼠标右键] %s" % interaction_hint.trim_prefix("右键")
	if secondary.is_empty():
		secondary = _selected_use_hint(selected)
	return {
		"visible": not primary.is_empty() or not secondary.is_empty(),
		"title": str(focus.get("display_name", block_id)),
		"subtitle": "世界方块",
		"primary": primary,
		"secondary": secondary,
		"tone": "info",
	}


func _held_item_prompt(selected: Dictionary) -> Dictionary:
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
	if inventory == null or not inventory.has_method("get_selected_item"):
		return {}
	var slot: Dictionary = inventory.call("get_selected_item")
	var item_id := str(slot.get("item_id", ""))
	if item_id.is_empty():
		return {}
	var registry = inventory.get("registry")
	var definition: Dictionary = {}
	var display_name := item_id
	if registry != null:
		if registry.has_method("get_item"):
			definition = registry.call("get_item", item_id)
		if registry.has_method("get_display_name"):
			display_name = str(registry.call("get_display_name", item_id))
	return {
		"item_id": item_id,
		"display_name": display_name,
		"block_id": (
			BlockRegistryScript.get_block_for_item(item_id)
			if BlockRegistryScript.get_block_for_item(item_id) != BlockRegistryScript.AIR
			else ""
		),
		"is_food": definition.has("food"),
	}
