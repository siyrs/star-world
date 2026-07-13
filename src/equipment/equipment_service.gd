class_name EquipmentService
extends Node

## Equipment domain foundation.
## Owns equipped item state and attribute aggregation.
## UI, Player and combat systems should consume snapshots only.

signal equipment_changed(snapshot: Dictionary)

const DEFAULT_ATTRIBUTES := {
	"attack_damage": 0.0,
	"defense": 0.0,
	"movement_speed": 0.0,
}

var slots: Dictionary = {}
var attributes: Dictionary = DEFAULT_ATTRIBUTES.duplicate(true)


func equip(slot_id: String, item: Dictionary) -> bool:
	if slot_id.is_empty() or item.is_empty():
		return false
	slots[slot_id] = item.duplicate(true)
	_recalculate()
	return true


func unequip(slot_id: String) -> Dictionary:
	var item: Dictionary = slots.get(slot_id, {})
	slots.erase(slot_id)
	_recalculate()
	return item


func get_snapshot() -> Dictionary:
	return {
		"slots": slots.duplicate(true),
		"attributes": attributes.duplicate(true),
	}


func serialize() -> Dictionary:
	return get_snapshot()


func deserialize(data: Dictionary) -> void:
	slots = data.get("slots", {}).duplicate(true)
	_recalculate()


func _recalculate() -> void:
	attributes = DEFAULT_ATTRIBUTES.duplicate(true)
	for item in slots.values():
		if item is Dictionary:
			for key in attributes.keys():
				attributes[key] += float(item.get(key, 0.0))
	equipment_changed.emit(get_snapshot())
