class_name EquipmentService
extends Node

signal equipment_changed(snapshot: Dictionary)
signal item_equipped(slot_id: String, item: Dictionary, previous: Dictionary)
signal item_unequipped(slot_id: String, item: Dictionary)
signal item_broken(slot_id: String, item_id: String, display_name: String, reason: String)
signal transaction_rejected(reason: String, context: Dictionary)

const RegistryScript = preload("res://src/equipment/equipment_registry.gd")
const SERIAL_VERSION := 2
const MAIN_HAND_SLOT := "main_hand"

var item_registry
var registry = RegistryScript.new()
var slots: Dictionary = {}


func _ready() -> void:
	_ensure_ready()


func setup(p_item_registry) -> void:
	item_registry = p_item_registry
	_ensure_ready()
	_emit_changed()


func clear() -> void:
	_ensure_ready()
	slots.clear()
	_ensure_slots()
	_emit_changed()


func get_slot(slot_id: String) -> Dictionary:
	_ensure_ready()
	return slots.get(slot_id, {}).duplicate(true)


func get_slot_definition(slot_id: String) -> Dictionary:
	return registry.get_slot(slot_id)


func get_slot_definitions() -> Array:
	return registry.get_slots()


func get_attribute_definitions() -> Dictionary:
	return registry.get_attribute_definitions()


func get_attribute_modifiers() -> Dictionary:
	_ensure_ready()
	var result: Dictionary = {}
	for slot_id in registry.get_slot_order():
		var item: Dictionary = slots.get(slot_id, {})
		if item.is_empty():
			continue
		var definition := _item_definition(str(item.get("item_id", "")))
		var modifiers: Dictionary = registry.get_item_attributes(definition)
		for raw_key in modifiers:
			var key := str(raw_key)
			result[key] = float(result.get(key, 0.0)) + float(modifiers[raw_key])
	return result


func get_snapshot() -> Dictionary:
	_ensure_ready()
	return {
		"version": SERIAL_VERSION,
		"slots": slots.duplicate(true),
		"attributes": get_attribute_modifiers(),
	}


func can_equip_item(item: Dictionary, requested_slot: String = "") -> bool:
	return not resolve_item_slot(item, requested_slot).is_empty()


func resolve_item_slot(item: Dictionary, requested_slot: String = "") -> String:
	_ensure_ready()
	var item_id := str(item.get("item_id", ""))
	if item_id.is_empty() or int(item.get("count", 0)) <= 0:
		return ""
	var definition := _item_definition(item_id)
	if definition.is_empty():
		return ""
	var resolved_slot := requested_slot.strip_edges()
	if resolved_slot.is_empty():
		resolved_slot = registry.resolve_slot(definition)
	if resolved_slot.is_empty() or not registry.is_item_allowed(resolved_slot, definition):
		return ""
	if item_registry != null and item_registry.has_method("get_max_stack"):
		if int(item_registry.call("get_max_stack", item_id)) != 1:
			return ""
	return resolved_slot


func equip_from_inventory(inventory: Node, inventory_index: int, requested_slot: String = "") -> bool:
	if (
		inventory == null
		or not inventory.has_method("get_slot")
		or not inventory.has_method("remove_from_slot")
		or not inventory.has_method("add_item")
	):
		_reject("inventory_contract_missing", {"inventory_index": inventory_index})
		return false
	var source: Dictionary = inventory.call("get_slot", inventory_index)
	var slot_id := resolve_item_slot(source, requested_slot)
	if slot_id.is_empty():
		_reject(
			"item_not_equippable",
			{"inventory_index": inventory_index, "item_id": str(source.get("item_id", ""))}
		)
		return false
	var previous: Dictionary = get_slot(slot_id)
	if not previous.is_empty() and not _can_return_previous(inventory, source, previous):
		_reject("inventory_full", {"slot_id": slot_id, "inventory_index": inventory_index})
		return false
	var removed: Dictionary = inventory.call("remove_from_slot", inventory_index, 1)
	if removed.is_empty():
		_reject("source_remove_failed", {"slot_id": slot_id, "inventory_index": inventory_index})
		return false
	if not previous.is_empty():
		var previous_remaining := int(
			inventory.call(
				"add_item",
				str(previous.get("item_id", "")),
				1,
				previous.get("metadata", {}).duplicate(true)
			)
		)
		if previous_remaining > 0:
			inventory.call(
				"add_item",
				str(removed.get("item_id", "")),
				1,
				removed.get("metadata", {}).duplicate(true)
			)
			_reject("swap_rollback", {"slot_id": slot_id, "inventory_index": inventory_index})
			return false
	slots[slot_id] = _normalize_item(removed)
	item_equipped.emit(slot_id, get_slot(slot_id), previous)
	_emit_changed()
	return true


func unequip_to_inventory(inventory: Node, slot_id: String) -> bool:
	var item := get_slot(slot_id)
	if item.is_empty():
		return false
	if inventory == null or not inventory.has_method("add_item"):
		_reject("inventory_contract_missing", {"slot_id": slot_id})
		return false
	if inventory.has_method("can_add_item") and not bool(
		inventory.call(
			"can_add_item",
			str(item.get("item_id", "")),
			1,
			item.get("metadata", {}).duplicate(true)
		)
	):
		_reject("inventory_full", {"slot_id": slot_id})
		return false
	var remaining := int(
		inventory.call(
			"add_item",
			str(item.get("item_id", "")),
			1,
			item.get("metadata", {}).duplicate(true)
		)
	)
	if remaining > 0:
		_reject("inventory_full", {"slot_id": slot_id})
		return false
	slots[slot_id] = {}
	item_unequipped.emit(slot_id, item.duplicate(true))
	_emit_changed()
	return true


# Compatibility entry point for tests and external integrations. Runtime UI should use
# equip_from_inventory so inventory and equipment stay in one transaction.
func equip(slot_id: String, item: Dictionary) -> bool:
	_ensure_ready()
	if not registry.has_slot(slot_id) or item.is_empty():
		return false
	var item_id := str(item.get("item_id", ""))
	if not item_id.is_empty() and resolve_item_slot(item, slot_id).is_empty():
		return false
	var previous := get_slot(slot_id)
	slots[slot_id] = item.duplicate(true) if item_id.is_empty() else _normalize_item(item)
	item_equipped.emit(slot_id, get_slot(slot_id), previous)
	_emit_changed()
	return true


func unequip(slot_id: String) -> Dictionary:
	_ensure_ready()
	var item := get_slot(slot_id)
	if item.is_empty():
		return {}
	slots[slot_id] = {}
	item_unequipped.emit(slot_id, item.duplicate(true))
	_emit_changed()
	return item


func consume_durability(slot_id: String, amount: int = 1, reason: String = "use") -> Dictionary:
	var item := get_slot(slot_id)
	if item.is_empty() or amount <= 0:
		return {"consumed": false, "broken": false}
	var item_id := str(item.get("item_id", ""))
	var definition := _item_definition(item_id)
	var maximum := maxi(0, int(definition.get("durability", 0)))
	if maximum <= 0:
		return {"consumed": false, "broken": false, "item_id": item_id}
	var metadata: Dictionary = item.get("metadata", {}).duplicate(true)
	var before := clampi(int(metadata.get("durability", maximum)), 0, maximum)
	var after := maxi(0, before - amount)
	if after <= 0:
		slots[slot_id] = {}
		var display_name := str(definition.get("name", item_id))
		item_broken.emit(slot_id, item_id, display_name, reason)
		_emit_changed()
		return {
			"consumed": true,
			"broken": true,
			"slot_id": slot_id,
			"item_id": item_id,
			"before": before,
			"after": 0,
		}
	metadata["durability"] = after
	item["metadata"] = metadata
	slots[slot_id] = item
	_emit_changed()
	return {
		"consumed": true,
		"broken": false,
		"slot_id": slot_id,
		"item_id": item_id,
		"before": before,
		"after": after,
	}


func consume_armor_durability(amount: int = 1, reason: String = "damage") -> Array:
	var results: Array = []
	for slot_id in registry.get_slot_order():
		if slot_id == MAIN_HAND_SLOT:
			continue
		var item := get_slot(slot_id)
		if item.is_empty():
			continue
		var result := consume_durability(slot_id, amount, reason)
		if bool(result.get("consumed", false)):
			results.append(result)
	return results


func serialize() -> Dictionary:
	_ensure_ready()
	return {"version": SERIAL_VERSION, "slots": slots.duplicate(true)}


func deserialize(data: Dictionary) -> bool:
	_ensure_ready()
	slots.clear()
	_ensure_slots()
	var raw_slots = data.get("slots", {})
	if raw_slots is not Dictionary:
		_emit_changed()
		return data.is_empty()
	for raw_slot_id in raw_slots:
		var slot_id := str(raw_slot_id)
		var raw_item = raw_slots[raw_slot_id]
		if not registry.has_slot(slot_id) or raw_item is not Dictionary:
			continue
		var item: Dictionary = raw_item
		if item.is_empty():
			continue
		if resolve_item_slot(item, slot_id).is_empty():
			continue
		slots[slot_id] = _normalize_item(item)
	_emit_changed()
	return true


func _ensure_ready() -> void:
	registry.ensure_loaded()
	_ensure_slots()


func _ensure_slots() -> void:
	for slot_id in registry.get_slot_order():
		if not slots.has(slot_id) or slots[slot_id] is not Dictionary:
			slots[slot_id] = {}
	var stale: Array[String] = []
	for raw_slot_id in slots:
		var slot_id := str(raw_slot_id)
		if not registry.has_slot(slot_id):
			stale.append(slot_id)
	for slot_id in stale:
		slots.erase(slot_id)


func _normalize_item(item: Dictionary) -> Dictionary:
	var result := {
		"item_id": str(item.get("item_id", "")),
		"count": 1,
	}
	var metadata = item.get("metadata", {})
	if metadata is Dictionary and not metadata.is_empty():
		result["metadata"] = metadata.duplicate(true)
	return result


func _item_definition(item_id: String) -> Dictionary:
	if item_id.is_empty() or item_registry == null or not item_registry.has_method("get_item"):
		return {}
	return item_registry.call("get_item", item_id)


func _can_return_previous(inventory: Node, source: Dictionary, previous: Dictionary) -> bool:
	if previous.is_empty():
		return true
	if inventory.has_method("can_add_item") and bool(
		inventory.call(
			"can_add_item",
			str(previous.get("item_id", "")),
			1,
			previous.get("metadata", {}).duplicate(true)
		)
	):
		return true
	# Equippable items are non-stackable. Removing the source frees its exact slot,
	# guaranteeing room for the previous item even when the rest of the inventory is full.
	return int(source.get("count", 0)) == 1


func _emit_changed() -> void:
	equipment_changed.emit(get_snapshot())


func _reject(reason: String, context: Dictionary) -> void:
	var payload := context.duplicate(true)
	payload["reason"] = reason
	transaction_rejected.emit(reason, payload)
