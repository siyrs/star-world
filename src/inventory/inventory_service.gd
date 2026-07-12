class_name InventoryService
extends Node

signal inventory_changed
signal slot_changed(index: int, slot: Dictionary)
signal selected_slot_changed(index: int, slot: Dictionary)
signal item_added(item_id: String, count: int)
signal item_removed(item_id: String, count: int)

const SERIAL_VERSION := 1
const ItemRegistryScript = preload("res://src/inventory/item_registry.gd")

var registry = ItemRegistryScript.new()
var slot_count: int = 36
var hotbar_size: int = 9
var selected_slot: int = 0
var slots: Array = []


func _init(p_slot_count: int = 36, p_hotbar_size: int = 9) -> void:
	slot_count = maxi(9, p_slot_count)
	hotbar_size = clampi(p_hotbar_size, 1, slot_count)
	registry.load_from_file()
	_reset_slots()


func _reset_slots() -> void:
	slots.clear()
	for index in slot_count:
		slots.append({})
	selected_slot = 0


func add_item(item_id: String, count: int = 1, metadata: Dictionary = {}) -> int:
	if count <= 0:
		return 0
	if not registry.has_item(item_id):
		push_warning("Unknown item: %s" % item_id)
		return count
	var remaining := count
	var max_stack := registry.get_max_stack(item_id)
	for index in slots.size():
		var slot: Dictionary = slots[index]
		if str(slot.get("item_id", "")) == item_id and int(slot.get("count", 0)) < max_stack and slot.get("metadata", {}) == metadata:
			var accepted := mini(remaining, max_stack - int(slot["count"]))
			slot["count"] = int(slot["count"]) + accepted
			slots[index] = slot
			remaining -= accepted
			slot_changed.emit(index, slot.duplicate(true))
			if remaining == 0:
				break
	if remaining > 0:
		for index in slots.size():
			if slots[index].is_empty():
				var accepted := mini(remaining, max_stack)
				var new_slot := {"item_id": item_id, "count": accepted}
				if not metadata.is_empty():
					new_slot["metadata"] = metadata.duplicate(true)
				slots[index] = new_slot
				remaining -= accepted
				slot_changed.emit(index, new_slot.duplicate(true))
				if remaining == 0:
					break
	var added := count - remaining
	if added > 0:
		item_added.emit(item_id, added)
		inventory_changed.emit()
		_emit_selected_slot()
	return remaining


func remove_item(item_id: String, count: int = 1) -> int:
	var remaining := maxi(0, count)
	for index in slots.size():
		var slot: Dictionary = slots[index]
		if str(slot.get("item_id", "")) != item_id:
			continue
		var removed := mini(remaining, int(slot.get("count", 0)))
		slot["count"] = int(slot["count"]) - removed
		remaining -= removed
		if int(slot["count"]) <= 0:
			slot = {}
		slots[index] = slot
		slot_changed.emit(index, slot.duplicate(true))
		if remaining == 0:
			break
	var removed_total := count - remaining
	if removed_total > 0:
		item_removed.emit(item_id, removed_total)
		inventory_changed.emit()
		_emit_selected_slot()
	return removed_total


func remove_from_slot(index: int, count: int = 1) -> Dictionary:
	if index < 0 or index >= slots.size() or slots[index].is_empty() or count <= 0:
		return {}
	var slot: Dictionary = slots[index]
	var taken := mini(count, int(slot.get("count", 0)))
	var result := {"item_id": str(slot.get("item_id", "")), "count": taken, "metadata": slot.get("metadata", {}).duplicate(true)}
	slot["count"] = int(slot["count"]) - taken
	if int(slot["count"]) <= 0:
		slot = {}
	slots[index] = slot
	slot_changed.emit(index, slot.duplicate(true))
	inventory_changed.emit()
	_emit_selected_slot()
	return result


func count_item(item_id: String) -> int:
	var total := 0
	for slot in slots:
		if str(slot.get("item_id", "")) == item_id:
			total += int(slot.get("count", 0))
	return total


func has_items(requirements: Dictionary) -> bool:
	for item_id in requirements:
		if count_item(str(item_id)) < int(requirements[item_id]):
			return false
	return true


func select_slot(index: int) -> void:
	if hotbar_size <= 0:
		return
	selected_slot = posmod(index, hotbar_size)
	_emit_selected_slot()


func select_relative(offset: int) -> void:
	select_slot(selected_slot + offset)


func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {}
	return slots[index].duplicate(true)


func get_selected_item() -> Dictionary:
	return get_slot(selected_slot)


func swap_slots(first: int, second: int) -> bool:
	if first < 0 or second < 0 or first >= slots.size() or second >= slots.size():
		return false
	var temporary: Dictionary = slots[first]
	slots[first] = slots[second]
	slots[second] = temporary
	slot_changed.emit(first, get_slot(first))
	slot_changed.emit(second, get_slot(second))
	inventory_changed.emit()
	_emit_selected_slot()
	return true


func consume_selected(count: int = 1) -> Dictionary:
	return remove_from_slot(selected_slot, count)


func clear() -> void:
	_reset_slots()
	inventory_changed.emit()
	_emit_selected_slot()


func grant_starter_kit() -> void:
	add_item("oak_planks", 16)
	add_item("apple", 4)
	add_item("wooden_pickaxe", 1)
	add_item("torch", 8)


func serialize() -> Dictionary:
	var saved_slots: Array = []
	for slot in slots:
		saved_slots.append(slot.duplicate(true))
	return {"version": SERIAL_VERSION, "selected_slot": selected_slot, "slot_count": slot_count, "hotbar_size": hotbar_size, "slots": saved_slots}


func deserialize(data: Dictionary) -> bool:
	if not data.has("slots") or not data["slots"] is Array:
		return false
	slot_count = maxi(9, int(data.get("slot_count", 36)))
	hotbar_size = clampi(int(data.get("hotbar_size", 9)), 1, slot_count)
	_reset_slots()
	var saved_slots: Array = data["slots"]
	for index in mini(saved_slots.size(), slot_count):
		var raw_slot = saved_slots[index]
		if raw_slot is Dictionary:
			var item_id := str(raw_slot.get("item_id", ""))
			var item_count := int(raw_slot.get("count", 0))
			if registry.has_item(item_id) and item_count > 0:
				slots[index] = {"item_id": item_id, "count": mini(item_count, registry.get_max_stack(item_id)), "metadata": raw_slot.get("metadata", {}).duplicate(true)}
	selected_slot = clampi(int(data.get("selected_slot", 0)), 0, hotbar_size - 1)
	inventory_changed.emit()
	_emit_selected_slot()
	return true


func _emit_selected_slot() -> void:
	selected_slot_changed.emit(selected_slot, get_selected_item())
