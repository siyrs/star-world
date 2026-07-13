class_name ToolService
extends Node

signal durability_changed(
	slot_index: int, item_id: String, remaining: int, maximum: int, reason: String
)
signal item_broken(slot_index: int, item_id: String, display_name: String, reason: String)

var item_registry


func setup(p_item_registry) -> void:
	item_registry = p_item_registry


func get_tool_profile(item_id: String) -> Dictionary:
	var definition: Dictionary = {}
	if item_registry != null and item_registry.has_method("get_item"):
		definition = item_registry.call("get_item", item_id)
	if definition.is_empty():
		return _hand_profile()
	var maximum := maxi(0, int(definition.get("durability", 0)))
	var tool_type := str(definition.get("tool_type", "hand"))
	return {
		"item_id": item_id,
		"display_name": str(definition.get("name", item_id)),
		"category": str(definition.get("category", "")),
		"tool_type": tool_type,
		"power": maxi(0, int(definition.get("power", 0))),
		"mining_speed": maxf(0.1, float(definition.get("mining_speed", 1.0))),
		"maximum_durability": maximum,
		"is_tool": str(definition.get("category", "")) == "tool",
		"is_durable": maximum > 0,
	}


func get_slot_context(slot: Dictionary) -> Dictionary:
	if slot.is_empty():
		return _hand_profile()
	var item_id := str(slot.get("item_id", ""))
	var profile := get_tool_profile(item_id)
	var maximum := int(profile.get("maximum_durability", 0))
	var metadata: Dictionary = slot.get("metadata", {})
	var remaining := maximum
	if maximum > 0:
		remaining = clampi(int(metadata.get("durability", maximum)), 0, maximum)
	profile["remaining_durability"] = remaining
	profile["durability_ratio"] = (
		float(remaining) / float(maximum) if maximum > 0 else 1.0
	)
	profile["metadata"] = metadata.duplicate(true)
	return profile


func get_selected_context(inventory: Node) -> Dictionary:
	if inventory == null or not inventory.has_method("get_selected_item"):
		return _hand_profile()
	var slot: Dictionary = inventory.call("get_selected_item")
	return get_slot_context(slot)


func consume_selected_durability(
	inventory: Node, amount: int = 1, reason: String = "use"
) -> Dictionary:
	if inventory == null:
		return {}
	var slot_index := int(inventory.get("selected_slot"))
	return consume_slot_durability(inventory, slot_index, amount, reason)


func consume_slot_durability(
	inventory: Node, slot_index: int, amount: int = 1, reason: String = "use"
) -> Dictionary:
	if (
		inventory == null
		or amount <= 0
		or not inventory.has_method("get_slot")
		or not inventory.has_method("update_slot_metadata")
	):
		return {}
	var slot: Dictionary = inventory.call("get_slot", slot_index)
	if slot.is_empty():
		return {}
	var context := get_slot_context(slot)
	var maximum := int(context.get("maximum_durability", 0))
	if maximum <= 0:
		return {
			"changed": false,
			"broken": false,
			"item_id": str(context.get("item_id", "")),
		}
	var item_id := str(context.get("item_id", ""))
	var remaining := maxi(0, int(context.get("remaining_durability", maximum)) - amount)
	if remaining <= 0:
		if inventory.has_method("remove_from_slot"):
			inventory.call("remove_from_slot", slot_index, 1)
		item_broken.emit(
			slot_index,
			item_id,
			str(context.get("display_name", item_id)),
			reason
		)
		return {
			"changed": true,
			"broken": true,
			"item_id": item_id,
			"remaining": 0,
			"maximum": maximum,
		}
	var metadata: Dictionary = slot.get("metadata", {}).duplicate(true)
	metadata["durability"] = remaining
	if not bool(inventory.call("update_slot_metadata", slot_index, metadata)):
		return {}
	durability_changed.emit(slot_index, item_id, remaining, maximum, reason)
	return {
		"changed": true,
		"broken": false,
		"item_id": item_id,
		"remaining": remaining,
		"maximum": maximum,
	}


func format_durability(slot: Dictionary) -> String:
	var context := get_slot_context(slot)
	var maximum := int(context.get("maximum_durability", 0))
	if maximum <= 0:
		return ""
	return "%d / %d" % [int(context.get("remaining_durability", maximum)), maximum]


func _hand_profile() -> Dictionary:
	return {
		"item_id": "",
		"display_name": "空手",
		"category": "",
		"tool_type": "hand",
		"power": 0,
		"mining_speed": 1.0,
		"maximum_durability": 0,
		"remaining_durability": 0,
		"durability_ratio": 1.0,
		"is_tool": false,
		"is_durable": false,
		"metadata": {},
	}
