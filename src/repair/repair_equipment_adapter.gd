class_name RepairEquipmentAdapter
extends Node

var equipment: Node


func setup(p_equipment: Node) -> void:
	equipment = p_equipment


func get_slot(slot_id: String) -> Dictionary:
	if equipment == null or not equipment.has_method("get_slot"):
		return {}
	return equipment.call("get_slot", slot_id)


func get_slot_definition(slot_id: String) -> Dictionary:
	if equipment == null or not equipment.has_method("get_slot_definition"):
		return {}
	return equipment.call("get_slot_definition", slot_id)


func get_slot_definitions() -> Array:
	if equipment == null or not equipment.has_method("get_slot_definitions"):
		return []
	return equipment.call("get_slot_definitions")


func update_slot_metadata(slot_id: String, metadata: Dictionary) -> bool:
	if (
		equipment == null
		or not equipment.has_method("serialize")
		or not equipment.has_method("deserialize")
	):
		return false
	var item: Dictionary = get_slot(slot_id)
	if item.is_empty():
		return false
	if metadata.is_empty():
		item.erase("metadata")
	else:
		item["metadata"] = metadata.duplicate(true)
	var state: Dictionary = equipment.call("serialize")
	var raw_slots_value: Variant = state.get("slots", {})
	if raw_slots_value is not Dictionary:
		return false
	var slots: Dictionary = raw_slots_value.duplicate(true)
	if not slots.has(slot_id):
		return false
	slots[slot_id] = item
	state["slots"] = slots
	return bool(equipment.call("deserialize", state))
