class_name EquipmentRegistry
extends RefCounted

const DEFAULT_DATA_PATH := "res://data/equipment.json"

var schema_version: int = 0
var _slots: Dictionary = {}
var _slot_order: Array[String] = []
var _attributes: Dictionary = {}


func load_from_file(path: String = DEFAULT_DATA_PATH) -> bool:
	_slots.clear()
	_slot_order.clear()
	_attributes.clear()
	schema_version = 0
	if not FileAccess.file_exists(path):
		push_error("Equipment registry is missing: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open equipment registry: %s" % path)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary or parsed.get("slots", null) is not Array:
		push_error("Invalid equipment registry JSON: %s" % path)
		return false
	schema_version = maxi(1, int(parsed.get("schema_version", 1)))
	var raw_slots: Array = parsed.get("slots", [])
	for raw_value in raw_slots:
		if raw_value is not Dictionary:
			continue
		var raw_slot: Dictionary = raw_value
		var slot_id := str(raw_slot.get("id", "")).strip_edges()
		if slot_id.is_empty() or _slots.has(slot_id):
			continue
		var allowed: Array[String] = []
		var raw_allowed = raw_slot.get("allowed", [])
		if raw_allowed is Array:
			for category in raw_allowed:
				var normalized := str(category).strip_edges()
				if not normalized.is_empty() and not allowed.has(normalized):
					allowed.append(normalized)
		var normalized_slot := {
			"id": slot_id,
			"name": str(raw_slot.get("name", slot_id)),
			"allowed": allowed,
			"order": int(raw_slot.get("order", _slot_order.size())),
		}
		_slots[slot_id] = normalized_slot
		_slot_order.append(slot_id)
	_slot_order.sort_custom(
		func(first: String, second: String) -> bool:
			return int(_slots[first].get("order", 0)) < int(_slots[second].get("order", 0))
	)
	var raw_attributes = parsed.get("attributes", {})
	if raw_attributes is Dictionary:
		_attributes = raw_attributes.duplicate(true)
	return not _slots.is_empty()


func ensure_loaded() -> bool:
	return not _slots.is_empty() or load_from_file()


func has_slot(slot_id: String) -> bool:
	ensure_loaded()
	return _slots.has(slot_id)


func get_slot(slot_id: String) -> Dictionary:
	ensure_loaded()
	return _slots.get(slot_id, {}).duplicate(true)


func get_slots() -> Array:
	ensure_loaded()
	var result: Array = []
	for slot_id in _slot_order:
		result.append(get_slot(slot_id))
	return result


func get_slot_order() -> Array[String]:
	ensure_loaded()
	return _slot_order.duplicate()


func slot_count() -> int:
	ensure_loaded()
	return _slot_order.size()


func get_attribute_definitions() -> Dictionary:
	ensure_loaded()
	return _attributes.duplicate(true)


func resolve_slot(item_definition: Dictionary) -> String:
	ensure_loaded()
	var equipment_data := _equipment_data(item_definition)
	var explicit_slot := str(equipment_data.get("slot", "")).strip_edges()
	if not explicit_slot.is_empty() and is_item_allowed(explicit_slot, item_definition):
		return explicit_slot
	var category := str(item_definition.get("category", "")).strip_edges()
	for slot_id in _slot_order:
		var allowed: Array = _slots[slot_id].get("allowed", [])
		if allowed.has(category):
			return slot_id
	return ""


func is_item_allowed(slot_id: String, item_definition: Dictionary) -> bool:
	ensure_loaded()
	if not _slots.has(slot_id) or item_definition.is_empty():
		return false
	var equipment_data := _equipment_data(item_definition)
	var explicit_slot := str(equipment_data.get("slot", "")).strip_edges()
	if not explicit_slot.is_empty() and explicit_slot != slot_id:
		return false
	var category := str(item_definition.get("category", "")).strip_edges()
	var allowed: Array = _slots[slot_id].get("allowed", [])
	return allowed.has(category)


func get_item_attributes(item_definition: Dictionary) -> Dictionary:
	var equipment_data := _equipment_data(item_definition)
	var raw_attributes = equipment_data.get("attributes", {})
	return raw_attributes.duplicate(true) if raw_attributes is Dictionary else {}


func _equipment_data(item_definition: Dictionary) -> Dictionary:
	var raw_equipment = item_definition.get("equipment", {})
	return raw_equipment.duplicate(true) if raw_equipment is Dictionary else {}
